if not CLIENT then return end
LUASQUARE_AUDIO = LUASQUARE_AUDIO or {}
local AUDIO = LUASQUARE_AUDIO

AUDIO.Net = AUDIO.Net or {
    Request = 'LUASQUARE_AUDIO_Request', Catalog = 'LUASQUARE_AUDIO_Catalog',
    Snapshot = 'LUASQUARE_AUDIO_Snapshot', State = 'LUASQUARE_AUDIO_State',
    Music = 'LUASQUARE_AUDIO_Music',
    SubtitleStart = 'LUASQUARE_AUDIO_SubtitleStart', SubtitleStop = 'LUASQUARE_AUDIO_SubtitleStop',
    Reset = 'LUASQUARE_AUDIO_Reset'
}
AUDIO.ClientCatalog = AUDIO.ClientCatalog or {
    sounds = {}, subtitles = {}, subtitleStyles = {}, musicBuses = {}, paLines = {},
    paChannels = {}, soundscapeGroups = {}
}
AUDIO.ClientMusicStates = AUDIO.ClientMusicStates or {}

local transfers = {}
local function receiveChunk(message, callback)
    net.Receive(message, function()
        local transferId = net.ReadUInt(32)
        local index, count, bytes = net.ReadUInt(16), net.ReadUInt(16), net.ReadUInt(16)
        if count < 1 or count > 96 or index < 1 or index > count or bytes > AUDIO.NetChunkBytes then return end
        local key = message .. ':' .. transferId
        local bucket = transfers[key] or {count = count, chunks = {}, bytes = 0}
        transfers[key] = bucket
        if bucket.count ~= count or bucket.chunks[index] then return end
        local chunk = net.ReadData(bytes)
        if not chunk then return end
        bucket.chunks[index], bucket.bytes = chunk, bucket.bytes + bytes
        if bucket.bytes > AUDIO.MaxCatalogBytes then transfers[key] = nil return end
        for part = 1, count do if not bucket.chunks[part] then return end end
        transfers[key] = nil
        local json = util.Decompress(table.concat(bucket.chunks))
        local value = json and util.JSONToTable(json) or nil
        if type(value) == 'table' then callback(value) end
    end)
end

function AUDIO.RequestState()
    net.Start(AUDIO.Net.Request) net.SendToServer() return true
end

receiveChunk(AUDIO.Net.Catalog, function(snapshot)
    if type(snapshot.catalog) ~= 'table' then return end
    AUDIO.ClientCatalog, AUDIO.ClientCatalogRevision = snapshot.catalog, snapshot.revision
    if AUDIO.ApplyMusicSnapshot then AUDIO.ApplyMusicSnapshot(AUDIO.ClientMusicStates or {}) end
    hook.Run('LUASQUARE_AUDIO_CatalogUpdated', AUDIO.ClientCatalog)
end)

receiveChunk(AUDIO.Net.Snapshot, function(snapshot)
    AUDIO.ClientTimeScale = tonumber(snapshot.timeScale) or 1
    AUDIO.ClientSoundscapes = snapshot.soundscapes or {}
    if AUDIO.ApplyMusicSnapshot then AUDIO.ApplyMusicSnapshot(snapshot.music or {}) end
end)

receiveChunk(AUDIO.Net.Music, function(delta)
    if AUDIO.ApplyMusicState then AUDIO.ApplyMusicState(delta.busId, delta.state, delta.fadeSeconds) end
end)

receiveChunk(AUDIO.Net.State, function(delta)
    if delta.kind == 'soundscape' and type(delta.id) == 'string' then
        AUDIO.ClientSoundscapes = AUDIO.ClientSoundscapes or {}
        AUDIO.ClientSoundscapes[delta.id] = delta.value
    elseif delta.kind == 'timescale' then
        AUDIO.ClientTimeScale = tonumber(delta.value) or 1
    end
end)

net.Receive(AUDIO.Net.SubtitleStart, function()
    local definition = {
        id = net.ReadString(), subtitleId = net.ReadString(), startedAt = net.ReadFloat(),
        playbackRate = net.ReadFloat(), offset = net.ReadFloat()
    }
    if AUDIO.ClientStartSubtitleGroup then AUDIO.ClientStartSubtitleGroup(definition) end
end)

net.Receive(AUDIO.Net.SubtitleStop, function()
    local id = net.ReadString()
    if AUDIO.ClientStopSubtitleGroup then AUDIO.ClientStopSubtitleGroup(id) end
end)

net.Receive(AUDIO.Net.Reset, function()
    local reason = net.ReadString()
    if AUDIO.ClientReset then AUDIO.ClientReset(reason) end
end)

hook.Add('InitPostEntity', 'LUASQUARE_AUDIO_RequestState', function()
    timer.Simple(0.5, function() if LUASQUARE_AUDIO then LUASQUARE_AUDIO.RequestState() end end)
end)
