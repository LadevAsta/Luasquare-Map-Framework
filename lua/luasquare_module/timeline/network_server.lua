if not SERVER then return end
LUASQUARE_TIMELINE = LUASQUARE_TIMELINE or {}
local TIMELINE = LUASQUARE_TIMELINE

TIMELINE.Net = TIMELINE.Net or {
    CatalogRequest = 'LUASQUARE_TIMELINE_CatalogRequest',
    CatalogChunk = 'LUASQUARE_TIMELINE_CatalogChunk',
    PreviewChunk = 'LUASQUARE_TIMELINE_PreviewChunk',
    PreviewStop = 'LUASQUARE_TIMELINE_PreviewStop',
    PreviewStatus = 'LUASQUARE_TIMELINE_PreviewStatus'
}

for _, name in pairs(TIMELINE.Net) do util.AddNetworkString(name) end

local transfers = setmetatable({}, {__mode = 'k'})
local serial = 0

local function addPreviewTarget(ids, value)
    local id = type(value) == 'table' and value.id or TIMELINE.NormalizeId(value)
    if id then ids[id] = true end
end

local function allowed(player)
    return game.SinglePlayer() and IsValid(player)
end

local function sendStatus(player, ok, message, run)
    net.Start(TIMELINE.Net.PreviewStatus)
    net.WriteBool(ok and true or false)
    net.WriteString(tostring(message or ''))
    net.WriteString(run and run.runId or '')
    net.Send(player)
end

local function sendCompressed(player, messageName, value)
    local json = util.TableToJSON(value, false)
    local payload = json and util.Compress(json) or nil
    if not payload then return false end
    serial = (serial + 1) % 4294967295
    local count = math.max(math.ceil(#payload / TIMELINE.NetChunkBytes), 1)
    for index = 1, count do
        local first = (index - 1) * TIMELINE.NetChunkBytes + 1
        local chunk = string.sub(payload, first, first + TIMELINE.NetChunkBytes - 1)
        net.Start(messageName)
        net.WriteUInt(serial, 32)
        net.WriteUInt(index, 16)
        net.WriteUInt(count, 16)
        net.WriteUInt(#chunk, 16)
        net.WriteData(chunk, #chunk)
        net.Send(player)
    end
    return true
end

net.Receive(TIMELINE.Net.CatalogRequest, function(_, player)
    if not allowed(player) then return end
    sendCompressed(player, TIMELINE.Net.CatalogChunk, TIMELINE.GetComponentCatalog())
end)

local function previewTargets(ownerId, compiled)
    local ids = {}
    local owner = TIMELINE.Components[ownerId]
    for _, clip in ipairs(compiled.clips or {}) do
        local target = clip.target
        if target.kind == 'self' then
            ids[ownerId] = true
        elseif target.kind == 'component' then
            ids[target.id] = true
        elseif target.kind == 'child' then
            local childId = owner and owner.children and TIMELINE.NormalizeId(owner.children[target.id])
            if childId then ids[childId] = true end
        elseif target.kind == 'resolver' then
            local resolver = TIMELINE.TargetResolvers[target.id]
            if resolver then
                local ok, result = pcall(resolver.resolve, {}, {ownerId = ownerId, preview = true})
                if ok then
                    for _, value in ipairs(result or {}) do
                        addPreviewTarget(ids, value)
                    end
                end
            end
        end
    end
    return ids
end

local function startPreview(player, envelope)
    if type(envelope) ~= 'table' or type(envelope.source) ~= 'table' then
        return sendStatus(player, false, 'Malformed preview request.')
    end
    local ownerId = TIMELINE.NormalizeId(envelope.ownerId)
    if not ownerId or not TIMELINE.Components[ownerId] then
        return sendStatus(player, false, 'Select a registered owner component.')
    end
    local compiled, diagnostics = TIMELINE.CompileSource(envelope.source, 'editor live preview')
    if not compiled then return sendStatus(player, false, TIMELINE.DiagnosticsText(diagnostics)) end
    local valid, bindingDiagnostics = TIMELINE.ValidateBinding(ownerId, compiled)
    if not valid then return sendStatus(player, false, TIMELINE.DiagnosticsText(bindingDiagnostics)) end
    for componentId in pairs(previewTargets(ownerId, compiled)) do
        local component = TIMELINE.Components[componentId]
        if not component or type(component.safeReset) ~= 'function' then
            return sendStatus(player, false,
                'Live preview is unavailable: ' .. tostring(componentId) .. ' has no safe reset.')
        end
    end
    if TIMELINE.LivePreviewRun and TIMELINE.IsRunning(TIMELINE.LivePreviewRun) then
        TIMELINE.CancelRun(TIMELINE.LivePreviewRun, 'replaced by editor preview')
    end
    local ok, run = TIMELINE.StartCompiled(ownerId, '__editor_preview', compiled, {
        actor = player,
        editorPreview = true
    }, {
        preview = true,
        seekTo = tonumber(envelope.seekTo) or 0,
        mutedTracks = type(envelope.mutedTracks) == 'table' and envelope.mutedTracks or {}
    })
    if not ok then return sendStatus(player, false, type(run) == 'string' and run or 'Preview start failed.') end
    sendStatus(player, true, 'Live preview started.', run)
end

net.Receive(TIMELINE.Net.PreviewChunk, function(_, player)
    if not allowed(player) then return end
    local transferId = net.ReadUInt(32)
    local index = net.ReadUInt(16)
    local count = net.ReadUInt(16)
    local bytes = net.ReadUInt(16)
    if count < 1 or count > 32 or index < 1 or index > count or bytes > TIMELINE.NetChunkBytes then return end
    transfers[player] = transfers[player] or {}
    local bucket = transfers[player][transferId]
    if not bucket then
        bucket = {chunks = {}, count = count, bytes = 0, startedAt = RealTime()}
        transfers[player][transferId] = bucket
    end
    if bucket.count ~= count or bucket.chunks[index] then return end
    local chunk = net.ReadData(bytes)
    if not chunk then return end
    bucket.chunks[index] = chunk
    bucket.bytes = bucket.bytes + bytes
    if bucket.bytes > TIMELINE.MaxPreviewBytes then
        transfers[player][transferId] = nil
        return sendStatus(player, false, 'Preview source is too large.')
    end
    for part = 1, count do if not bucket.chunks[part] then return end end
    transfers[player][transferId] = nil
    local compressed = table.concat(bucket.chunks)
    local json = util.Decompress(compressed)
    local envelope = json and util.JSONToTable(json) or nil
    startPreview(player, envelope)
end)

net.Receive(TIMELINE.Net.PreviewStop, function(_, player)
    if not allowed(player) then return end
    local run = TIMELINE.LivePreviewRun
    if run and run.context and run.context.actor == player then
        TIMELINE.CancelRun(run, 'editor preview stopped')
    end
    sendStatus(player, true, 'Live preview stopped.')
end)

hook.Add('PlayerDisconnected', 'LUASQUARE_TIMELINE_StopPreview', function(player)
    transfers[player] = nil
    local run = TIMELINE.LivePreviewRun
    if run and run.context and run.context.actor == player then
        TIMELINE.CancelRun(run, 'preview owner disconnected')
    end
end)

hook.Add('LUASQUARE_TIMELINE_RunTerminal', 'LUASQUARE_TIMELINE_PreviewTerminalStatus', function(run)
    if not run or not run.preview or run.parent then return end
    local player = run.context and run.context.actor
    if not allowed(player) then return end
    local reason = run.failureReason or run.cancelReason
    local message = run.status == 'completed' and 'Live preview completed and reset safely.'
        or ('Live preview ' .. tostring(run.status) .. ': ' .. tostring(reason or 'no reason'))
    sendStatus(player, run.status ~= 'failed', message, run)
end)
