if not CLIENT then return end

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
local DISPLAY = LUASQUARE_3D2D

DISPLAY.Net = DISPLAY.Net or {
    Snapshot = 'LUASQUARE_3D2D_SourceSnapshot',
    Delta = 'LUASQUARE_3D2D_SourceDelta',
    Request = 'LUASQUARE_3D2D_SourceRequest',
    EditorUpload = 'LUASQUARE_3D2D_EditorUpload',
    EditorClear = 'LUASQUARE_3D2D_EditorClear',
    EditorResult = 'LUASQUARE_3D2D_EditorResult'
}
DISPLAY.ClientState = DISPLAY.ClientState or {
    Displays = {}, Providers = {}, ThemePacks = {}, ThemeState = {}, Annunciators = {}, Graphs = {}
}
DISPLAY.ClientTransfers = DISPLAY.ClientTransfers or {}

local TRANSFER_TIMEOUT = 15

local function requestSnapshot()
    if util.NetworkStringToID(DISPLAY.Net.Request) == 0 then return false end
    net.Start(DISPLAY.Net.Request)
    net.SendToServer()
    return true
end

DISPLAY.RequestSnapshot = requestSnapshot

local function hydrateSnapshot(snapshot)
    for _, display in ipairs(snapshot.Displays or {}) do
        display.pos = DISPLAY.TableToVector(display.pos)
        display.ang = DISPLAY.TableToAngle(display.ang)
    end
    DISPLAY.ClientState = snapshot
    DISPLAY.ClientState.Providers = DISPLAY.ClientState.Providers or {}
    DISPLAY.ClientState.ThemePacks = DISPLAY.ClientState.ThemePacks or {}
    DISPLAY.ClientState.ThemeState = DISPLAY.ClientState.ThemeState or {}
    DISPLAY.ClientState.Annunciators = DISPLAY.ClientState.Annunciators or {}
    DISPLAY.ClientState.Graphs = DISPLAY.ClientState.Graphs or {}
    DISPLAY.ClientRevision = snapshot.revision
    DISPLAY.LastDeltaSequence = 0
    DISPLAY.ServerTimeOffset = CurTime() - (tonumber(snapshot.serverTime) or CurTime())
    DISPLAY.KnownProviders = snapshot.ProviderCatalog or {}
    DISPLAY.KnownActions = snapshot.ActionCatalog or {}
    hook.Run('LUASQUARE_3D2D_SnapshotUpdated', snapshot)
end

local function appendGraphSample(sample)
    local graphs = DISPLAY.ClientState.Graphs
    local graph = graphs[sample.key]
    if not graph then
        graph = {key = sample.key, points = {}}
        graphs[sample.key] = graph
    end
    table.insert(graph.points, {t = sample.t, v = sample.v})
    local cutoff = (tonumber(sample.t) or 0) - math.max(tonumber(graph.seconds) or 60, 1)
    while graph.points[1] and (tonumber(graph.points[1].t) or 0) < cutoff do
        table.remove(graph.points, 1)
    end
    if #graph.points > 4096 then table.remove(graph.points, 1) end
end

local function applyDelta(delta)
    if delta.revision ~= DISPLAY.ClientRevision then
        requestSnapshot()
        return
    end
    if tonumber(delta.sequence) and tonumber(delta.sequence) <= (DISPLAY.LastDeltaSequence or 0) then return end
    DISPLAY.LastDeltaSequence = tonumber(delta.sequence) or DISPLAY.LastDeltaSequence
    DISPLAY.ServerTimeOffset = CurTime() - (tonumber(delta.serverTime) or CurTime())
    for id, value in pairs(delta.providers or {}) do DISPLAY.ClientState.Providers[id] = value end
    for group, theme in pairs(delta.themes or {}) do DISPLAY.ClientState.ThemeState[group] = theme end
    for id, value in pairs(delta.annunciators or {}) do DISPLAY.ClientState.Annunciators[id] = value end
    for id, page in pairs(delta.pages or {}) do
        for _, display in ipairs(DISPLAY.ClientState.Displays or {}) do
            if display.id == id then display.activePage = page break end
        end
    end
    for _, sample in ipairs(delta.graphSamples or {}) do appendGraphSample(sample) end
    hook.Run('LUASQUARE_3D2D_StateUpdated', delta)
end

function DISPLAY.GetSynchronizedTime()
    return CurTime() - (DISPLAY.ServerTimeOffset or 0)
end

local function receiveChunk(message, maximumBytes, callback)
    net.Receive(message, function()
        local transferId = net.ReadUInt(32)
        local index = net.ReadUInt(16)
        local count = net.ReadUInt(16)
        local bytes = net.ReadUInt(16)
        if index < 1 or count < 1 or index > count or bytes > 48000
            or count > math.ceil(maximumBytes / 48000) then return end
        local key = message .. ':' .. tostring(transferId)
        local transfer = DISPLAY.ClientTransfers[key]
        if not transfer or transfer.count ~= count then
            transfer = {count = count, received = 0, bytes = 0, chunks = {}}
            DISPLAY.ClientTransfers[key] = transfer
            timer.Simple(TRANSFER_TIMEOUT, function()
                if DISPLAY.ClientTransfers[key] == transfer then DISPLAY.ClientTransfers[key] = nil end
            end)
        end
        local chunk = net.ReadData(bytes)
        if not transfer.chunks[index] then
            transfer.chunks[index] = chunk
            transfer.received = transfer.received + 1
            transfer.bytes = transfer.bytes + bytes
            if transfer.bytes > maximumBytes then
                DISPLAY.ClientTransfers[key] = nil
                return
            end
        end
        if transfer.received < count then return end
        DISPLAY.ClientTransfers[key] = nil
        local json = util.Decompress(table.concat(transfer.chunks))
        local payload = json and util.JSONToTable(json) or nil
        if type(payload) == 'table' then callback(payload) end
    end)
end

receiveChunk(DISPLAY.Net.Snapshot, 8 * 1024 * 1024, hydrateSnapshot)
receiveChunk(DISPLAY.Net.Delta, 1024 * 1024, applyDelta)

hook.Add('InitPostEntity', 'LUASQUARE_3D2D_RequestSourceSnapshot', function()
    local attempts = 0
    timer.Create('LUASQUARE_3D2D_ClientSnapshotRequest', 0.5, 20, function()
        attempts = attempts + 1
        if requestSnapshot() or attempts >= 20 then timer.Remove('LUASQUARE_3D2D_ClientSnapshotRequest') end
    end)
end)
