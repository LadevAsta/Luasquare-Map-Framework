if not CLIENT then return end
LUASQUARE_TIMELINE = LUASQUARE_TIMELINE or {}
local TIMELINE = LUASQUARE_TIMELINE

TIMELINE.Net = TIMELINE.Net or {
    CatalogRequest = 'LUASQUARE_TIMELINE_CatalogRequest',
    CatalogChunk = 'LUASQUARE_TIMELINE_CatalogChunk',
    PreviewChunk = 'LUASQUARE_TIMELINE_PreviewChunk',
    PreviewStop = 'LUASQUARE_TIMELINE_PreviewStop',
    PreviewStatus = 'LUASQUARE_TIMELINE_PreviewStatus'
}

local transfers = {}
local uploadSerial = 0

function TIMELINE.RequestCatalog()
    if not game.SinglePlayer() then return false end
    net.Start(TIMELINE.Net.CatalogRequest)
    net.SendToServer()
    return true
end

local function receiveChunk()
    local transferId = net.ReadUInt(32)
    local index = net.ReadUInt(16)
    local count = net.ReadUInt(16)
    local bytes = net.ReadUInt(16)
    if count < 1 or count > 64 or index < 1 or index > count or bytes > TIMELINE.NetChunkBytes then return end
    local bucket = transfers[transferId] or {chunks = {}, count = count, bytes = 0}
    transfers[transferId] = bucket
    if bucket.count ~= count or bucket.chunks[index] then return end
    local chunk = net.ReadData(bytes)
    if not chunk then return end
    bucket.chunks[index] = chunk
    bucket.bytes = bucket.bytes + bytes
    for part = 1, count do if not bucket.chunks[part] then return end end
    transfers[transferId] = nil
    local json = util.Decompress(table.concat(bucket.chunks))
    local catalog = json and util.JSONToTable(json) or nil
    if type(catalog) ~= 'table' then return end
    TIMELINE.ClientCatalog = catalog
    hook.Run('LUASQUARE_TIMELINE_CatalogUpdated', catalog)
end

net.Receive(TIMELINE.Net.CatalogChunk, receiveChunk)

function TIMELINE.SendLivePreview(source, ownerId, seekTo, mutedTracks)
    if not game.SinglePlayer() then return false, 'Timeline editor is single-player only.' end
    local runtimeSource = TIMELINE.DeepCopy(source)
    runtimeSource.editor = nil
    local json = util.TableToJSON({
        source = runtimeSource,
        ownerId = ownerId,
        seekTo = tonumber(seekTo) or 0,
        mutedTracks = mutedTracks or {}
    }, false)
    local payload = json and util.Compress(json) or nil
    if not payload or #payload > TIMELINE.MaxPreviewBytes then return false, 'Preview source is too large.' end
    uploadSerial = (uploadSerial + 1) % 4294967295
    local count = math.max(math.ceil(#payload / TIMELINE.NetChunkBytes), 1)
    for index = 1, count do
        local first = (index - 1) * TIMELINE.NetChunkBytes + 1
        local chunk = string.sub(payload, first, first + TIMELINE.NetChunkBytes - 1)
        net.Start(TIMELINE.Net.PreviewChunk)
        net.WriteUInt(uploadSerial, 32)
        net.WriteUInt(index, 16)
        net.WriteUInt(count, 16)
        net.WriteUInt(#chunk, 16)
        net.WriteData(chunk, #chunk)
        net.SendToServer()
    end
    return true
end

function TIMELINE.StopLivePreview()
    if not game.SinglePlayer() then return false end
    net.Start(TIMELINE.Net.PreviewStop)
    net.SendToServer()
    return true
end

net.Receive(TIMELINE.Net.PreviewStatus, function()
    local ok = net.ReadBool()
    local message = net.ReadString()
    local runId = net.ReadString()
    TIMELINE.LivePreviewStatus = {ok = ok, message = message, runId = runId}
    hook.Run('LUASQUARE_TIMELINE_PreviewStatus', ok, message, runId)
end)
