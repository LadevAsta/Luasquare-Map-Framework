if not CLIENT then return end

LUASQUARE_ANNUNCIATOR = LUASQUARE_ANNUNCIATOR or {}
local ANN = LUASQUARE_ANNUNCIATOR

ANN.NetSnapshot = 'LUASQUARE_ANNUNCIATOR_Snapshot'
ANN.NetDelta = 'LUASQUARE_ANNUNCIATOR_Delta'
ANN.NetRequest = 'LUASQUARE_ANNUNCIATOR_Request'
ANN.NetCatalog = 'LUASQUARE_ANNUNCIATOR_Catalog'
ANN.NetCatalogRequest = 'LUASQUARE_ANNUNCIATOR_CatalogRequest'
ANN.ClientState = ANN.ClientState or {alarms = {}, groups = {}, revision = 0, sequence = 0}
ANN.EditorCatalog = ANN.EditorCatalog or {}

if not GetConVar(ANN.VolumeConVar) then
    CreateClientConVar(ANN.VolumeConVar, '1', true, true,
        'Annunciator, alarm, siren, and test volume', 0, 1)
end

local transfers = {}

local function decode(payload)
    if not payload or payload == '' then return nil end
    local json = util.Decompress(payload)
    return json and util.JSONToTable(json) or nil
end

local function receiveChunk(kind, callback)
    local serial = net.ReadUInt(32)
    local index = net.ReadUInt(16)
    local count = net.ReadUInt(16)
    local length = net.ReadUInt(16)
    if count < 1 or count > 128 or index < 1 or index > count or length > ANN.NetChunkBytes then return end
    local chunk = net.ReadData(length)
    local key = kind .. ':' .. serial
    local transfer = transfers[key]
    if not transfer or transfer.count ~= count then
        transfer = {count = count, chunks = {}, received = 0, expires = RealTime() + 15}
        transfers[key] = transfer
    end
    if not transfer.chunks[index] then
        transfer.chunks[index] = chunk
        transfer.received = transfer.received + 1
    end
    if transfer.received ~= transfer.count then return end
    local payload = table.concat(transfer.chunks)
    transfers[key] = nil
    callback(decode(payload))
end

net.Receive(ANN.NetSnapshot, function()
    receiveChunk('snapshot', function(snapshot)
        if type(snapshot) ~= 'table' or type(snapshot.alarms) ~= 'table' then return end
        ANN.ClientState = snapshot
        hook.Run('LuasquareAnnunciatorSnapshot', snapshot)
    end)
end)

net.Receive(ANN.NetCatalog, function()
    receiveChunk('catalog', function(catalog)
        if type(catalog) ~= 'table' then return end
        ANN.EditorCatalog = catalog
        hook.Run('LuasquareAnnunciatorCatalog', catalog)
    end)
end)

net.Receive(ANN.NetDelta, function()
    local length = net.ReadUInt(16)
    if length < 1 or length > 60000 then return end
    local delta = decode(net.ReadData(length))
    if type(delta) ~= 'table' then return end
    local state = ANN.ClientState
    if delta.revision ~= state.revision then
        net.Start(ANN.NetRequest)
        net.SendToServer()
        return
    end
    if (delta.sequence or 0) <= (state.sequence or 0) then return end
    if (delta.sequence or 0) > (state.sequence or 0) + 1 then
        net.Start(ANN.NetRequest)
        net.SendToServer()
        return
    end
    for id, alarm in pairs(delta.alarms or {}) do state.alarms[id] = alarm end
    for id, group in pairs(delta.groups or {}) do state.groups[id] = group end
    if delta.globalMutedUntil ~= nil then state.globalMutedUntil = delta.globalMutedUntil end
    state.sequence = delta.sequence
    state.serverTime = delta.serverTime
    hook.Run('LuasquareAnnunciatorDelta', delta)
end)

hook.Add('Think', 'LUASQUARE_ANNUNCIATOR_TransferCleanup', function()
    local current = RealTime()
    for key, transfer in pairs(transfers) do
        if current > transfer.expires then transfers[key] = nil end
    end
end)

hook.Add('InitPostEntity', 'LUASQUARE_ANNUNCIATOR_Request', function()
    if util.NetworkStringToID(ANN.NetRequest) == 0 then return end
    net.Start(ANN.NetRequest)
    net.SendToServer()
end)

function ANN.RequestEditorCatalog()
    if util.NetworkStringToID(ANN.NetCatalogRequest) == 0 then return false end
    net.Start(ANN.NetCatalogRequest)
    net.SendToServer()
    return true
end
