if not SERVER then return end
LUASQUARE_AUDIO = LUASQUARE_AUDIO or {}
local AUDIO = LUASQUARE_AUDIO

AUDIO.Net = AUDIO.Net or {
    Request = 'LUASQUARE_AUDIO_Request', Catalog = 'LUASQUARE_AUDIO_Catalog',
    Snapshot = 'LUASQUARE_AUDIO_Snapshot', State = 'LUASQUARE_AUDIO_State',
    Music = 'LUASQUARE_AUDIO_Music',
    SubtitleStart = 'LUASQUARE_AUDIO_SubtitleStart', SubtitleStop = 'LUASQUARE_AUDIO_SubtitleStop',
    Reset = 'LUASQUARE_AUDIO_Reset'
}
for _, name in pairs(AUDIO.Net) do util.AddNetworkString(name) end

local serial, requests = 0, setmetatable({}, {__mode = 'k'})
local function hasPlayers() return #player.GetHumans() > 0 end
local function sendChunked(message, value, recipient, maximum)
    if recipient == nil and not hasPlayers() then return true end
    local json = util.TableToJSON(value, false)
    local payload = json and util.Compress(json) or nil
    if not payload or #payload > (maximum or AUDIO.MaxCatalogBytes) then return false end
    serial = (serial + 1) % 4294967295
    local count = math.max(math.ceil(#payload / AUDIO.NetChunkBytes), 1)
    for index = 1, count do
        local first = (index - 1) * AUDIO.NetChunkBytes + 1
        local chunk = string.sub(payload, first, first + AUDIO.NetChunkBytes - 1)
        net.Start(message)
        net.WriteUInt(serial, 32) net.WriteUInt(index, 16) net.WriteUInt(count, 16)
        net.WriteUInt(#chunk, 16) net.WriteData(chunk, #chunk)
        if recipient then net.Send(recipient) else net.Broadcast() end
    end
    return true
end

function AUDIO.SendCatalog(recipient) return sendChunked(AUDIO.Net.Catalog, AUDIO.GetCatalogSnapshot(), recipient) end
function AUDIO.BroadcastCatalog() return AUDIO.SendCatalog(nil) end
function AUDIO.SendStateSnapshot(recipient) return sendChunked(AUDIO.Net.Snapshot, AUDIO.GetSnapshot(), recipient, 512 * 1024) end
function AUDIO.BroadcastStateSnapshot() return AUDIO.SendStateSnapshot(nil) end

function AUDIO.BroadcastStateDelta(kind, id, value)
    return sendChunked(AUDIO.Net.State, {kind = kind, id = id, value = value}, nil, 128 * 1024)
end

function AUDIO.BroadcastMusicState(busId, state, fadeSeconds)
    return sendChunked(AUDIO.Net.Music, {
        busId = busId, state = state, removed = state == nil, fadeSeconds = tonumber(fadeSeconds) or 0
    }, nil, 128 * 1024)
end

function AUDIO.SendSubtitleStart(instance)
    if #(instance.recipients or {}) == 0 then return true end
    net.Start(AUDIO.Net.SubtitleStart)
    net.WriteString(string.sub(instance.id, 1, 96))
    net.WriteString(string.sub(instance.subtitleId, 1, 96))
    net.WriteFloat(instance.startedAt or CurTime())
    net.WriteFloat(instance.playbackRate or 1)
    net.WriteFloat(instance.offset or 0)
    net.Send(instance.recipients)
    return true
end

function AUDIO.SendSubtitleStop(instance)
    if #(instance.recipients or {}) == 0 then return true end
    net.Start(AUDIO.Net.SubtitleStop)
    net.WriteString(string.sub(instance.id, 1, 96))
    net.Send(instance.recipients)
    return true
end

function AUDIO.BroadcastReset(reason)
    if not hasPlayers() then return true end
    net.Start(AUDIO.Net.Reset) net.WriteString(string.sub(tostring(reason or 'reset'), 1, 256)) net.Broadcast()
    return true
end

net.Receive(AUDIO.Net.Request, function(_, ply)
    if not IsValid(ply) or CurTime() < (requests[ply] or 0) then return end
    requests[ply] = CurTime() + 0.5
    AUDIO.SendCatalog(ply) AUDIO.SendStateSnapshot(ply)
end)

hook.Add('PlayerInitialSpawn', 'LUASQUARE_AUDIO_InitialState', function(ply)
    timer.Simple(1, function()
        if IsValid(ply) and LUASQUARE_AUDIO then
            LUASQUARE_AUDIO.SendCatalog(ply) LUASQUARE_AUDIO.SendStateSnapshot(ply)
        end
    end)
end)

hook.Add('PlayerDisconnected', 'LUASQUARE_AUDIO_ClearRequestLimit', function(ply) requests[ply] = nil end)
