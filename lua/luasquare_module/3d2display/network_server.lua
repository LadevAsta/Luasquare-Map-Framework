if not SERVER then return end

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

for _, name in pairs(DISPLAY.Net) do util.AddNetworkString(name) end

local CHUNK_BYTES = 48000
local MAX_TRANSFER_BYTES = 512 * 1024
local MAX_SOURCE_BYTES = 2 * 1024 * 1024
local MAX_SNAPSHOT_BYTES = 8 * 1024 * 1024
local MAX_DELTA_BYTES = 1024 * 1024
local transferSerial = 0
local requests = setmetatable({}, {__mode = 'k'})
local uploads = setmetatable({}, {__mode = 'k'})

local function canAdmin(player)
    if not IsValid(player) then return true end
    if game.SinglePlayer() then return true end
    return player.IsAdmin and player:IsAdmin()
end

local function nextTransferId()
    transferSerial = (transferSerial + 1) % 4294967295
    return transferSerial
end

local function encode(payload)
    local json = util.TableToJSON(payload, false)
    if not json then return nil end
    return util.Compress(json)
end

local function hasBroadcastRecipients()
    return #_G.player.GetHumans() > 0
end

local function sendChunked(message, payload, recipient, maximumBytes)
    -- Map bootstrap and cleanup can publish state before the listen-server
    -- host has a player entity. There is nothing to deliver in that window;
    -- the normal initial snapshot supplies the complete state after joining.
    if recipient == nil and not hasBroadcastRecipients() then return true end
    local compressed = encode(payload)
    if not compressed then return false end
    if #compressed > (maximumBytes or MAX_SNAPSHOT_BYTES) then
        print('[LUASQUARE_3D2D] Refused oversized ' .. message .. ' payload (' .. #compressed .. ' compressed bytes)')
        return false
    end
    local transferId = nextTransferId()
    local count = math.max(math.ceil(#compressed / CHUNK_BYTES), 1)
    for index = 1, count do
        local first = (index - 1) * CHUNK_BYTES + 1
        local chunk = string.sub(compressed, first, first + CHUNK_BYTES - 1)
        net.Start(message)
        net.WriteUInt(transferId, 32)
        net.WriteUInt(index, 16)
        net.WriteUInt(count, 16)
        net.WriteUInt(#chunk, 16)
        net.WriteData(chunk, #chunk)
        if recipient then net.Send(recipient) else net.Broadcast() end
    end
    return true
end

function DISPLAY.SendSnapshot(player)
    return sendChunked(DISPLAY.Net.Snapshot, DISPLAY.GetSnapshot(), player, MAX_SNAPSHOT_BYTES)
end

function DISPLAY.BroadcastSnapshot()
    if not hasBroadcastRecipients() then return true end
    return sendChunked(DISPLAY.Net.Snapshot, DISPLAY.GetSnapshot(), nil, MAX_SNAPSHOT_BYTES)
end

local function hasEntries(value)
    for _ in pairs(value or {}) do return true end
    return false
end

function DISPLAY.BroadcastDelta(delta)
    if not hasEntries(delta.providers) and not hasEntries(delta.variables) and not hasEntries(delta.pages)
        and not hasEntries(delta.themes) and not hasEntries(delta.annunciators)
        and #(delta.graphSamples or {}) == 0 then return false end
    if not hasBroadcastRecipients() then return true end
    local sent = sendChunked(DISPLAY.Net.Delta, delta, nil, MAX_DELTA_BYTES)
    if not sent then DISPLAY.BroadcastSnapshot() end
    return sent
end

net.Receive(DISPLAY.Net.Request, function(_, player)
    local current = CurTime()
    if current < (requests[player] or 0) then return end
    requests[player] = current + 0.5
    DISPLAY.SendSnapshot(player)
end)

hook.Add('PlayerInitialSpawn', 'LUASQUARE_3D2D_SendSourceSnapshot', function(player)
    timer.Simple(1, function()
        if IsValid(player) and LUASQUARE_3D2D and LUASQUARE_3D2D.SendSnapshot then
            LUASQUARE_3D2D.SendSnapshot(player)
        end
    end)
end)

local function editorResult(player, ok, message)
    net.Start(DISPLAY.Net.EditorResult)
    net.WriteBool(ok and true or false)
    net.WriteString(tostring(message or ''))
    net.Send(player)
end

net.Receive(DISPLAY.Net.EditorUpload, function(_, player)
    if not canAdmin(player) then return end
    local uploadId = net.ReadUInt(32)
    local targetDisplay = DISPLAY.NormalizeId(net.ReadString())
    local index = net.ReadUInt(16)
    local count = net.ReadUInt(16)
    local bytes = net.ReadUInt(16)
    if not targetDisplay or index < 1 or count < 1 or index > count
        or bytes > CHUNK_BYTES or count > math.ceil(MAX_TRANSFER_BYTES / CHUNK_BYTES) then return end

    local playerUploads = uploads[player]
    if not playerUploads then playerUploads = {} uploads[player] = playerUploads end
    local upload = playerUploads[uploadId]
    if not upload or upload.count ~= count or upload.target ~= targetDisplay then
        upload = {count = count, received = 0, bytes = 0, chunks = {}, target = targetDisplay, startedAt = CurTime()}
        playerUploads[uploadId] = upload
    end
    if CurTime() - upload.startedAt > 15 then playerUploads[uploadId] = nil return end
    local chunk = net.ReadData(bytes)
    if not upload.chunks[index] then
        upload.chunks[index] = chunk
        upload.received = upload.received + 1
        upload.bytes = upload.bytes + bytes
        if upload.bytes > MAX_TRANSFER_BYTES then playerUploads[uploadId] = nil return end
    end
    if upload.received < upload.count then return end
    playerUploads[uploadId] = nil

    local compressed = table.concat(upload.chunks)
    if #compressed > MAX_TRANSFER_BYTES then return end
    local json = util.Decompress(compressed)
    if not json or #json > MAX_SOURCE_BYTES then
        editorResult(player, false, 'preview source exceeds size limit')
        return
    end
    local source = util.JSONToTable(json)
    if type(source) ~= 'table' then
        editorResult(player, false, 'preview contains invalid JSON')
        return
    end
    local ok, message = DISPLAY.ApplyPreview(source, targetDisplay, player)
    if ok then
        editorResult(player, true, 'preview applied to ' .. targetDisplay)
    else
        editorResult(player, false, message)
    end
end)

net.Receive(DISPLAY.Net.EditorClear, function(_, player)
    if not canAdmin(player) then return end
    local targetDisplay = DISPLAY.NormalizeId(net.ReadString())
    local preview = targetDisplay and DISPLAY.Previews[targetDisplay]
    if not preview or preview.owner ~= player then
        editorResult(player, false, 'no preview owned on that display')
        return
    end
    DISPLAY.ClearPreview(targetDisplay, 'editor clear')
    editorResult(player, true, 'preview restored')
end)

hook.Add('PlayerDisconnected', 'LUASQUARE_3D2D_ClearEditorPreviews', function(player)
    DISPLAY.ClearAllPreviews('preview owner disconnected', player)
    uploads[player] = nil
    requests[player] = nil
end)
