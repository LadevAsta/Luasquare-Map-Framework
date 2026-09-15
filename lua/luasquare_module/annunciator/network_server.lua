if not SERVER then return end

LUASQUARE_ANNUNCIATOR = LUASQUARE_ANNUNCIATOR or {}
local ANN = LUASQUARE_ANNUNCIATOR

ANN.NetSnapshot = 'LUASQUARE_ANNUNCIATOR_Snapshot'
ANN.NetDelta = 'LUASQUARE_ANNUNCIATOR_Delta'
ANN.NetRequest = 'LUASQUARE_ANNUNCIATOR_Request'
ANN.NetCatalog = 'LUASQUARE_ANNUNCIATOR_Catalog'
ANN.NetCatalogRequest = 'LUASQUARE_ANNUNCIATOR_CatalogRequest'

util.AddNetworkString(ANN.NetSnapshot)
util.AddNetworkString(ANN.NetDelta)
util.AddNetworkString(ANN.NetRequest)
util.AddNetworkString(ANN.NetCatalog)
util.AddNetworkString(ANN.NetCatalogRequest)

local requestCooldowns = setmetatable({}, {__mode = 'k'})
local catalogCooldowns = setmetatable({}, {__mode = 'k'})

local function encode(value, maximum)
    local json = util.TableToJSON(value, false)
    if not json or #json > maximum then return nil end
    return util.Compress(json)
end

local function sendChunks(message, payload, recipients, serial)
    if not payload then return false end
    local chunkBytes = ANN.NetChunkBytes
    local count = math.max(math.ceil(#payload / chunkBytes), 1)
    for index = 1, count do
        local chunk = string.sub(payload, (index - 1) * chunkBytes + 1, index * chunkBytes)
        net.Start(message)
        net.WriteUInt(serial % 4294967295, 32)
        net.WriteUInt(index, 16)
        net.WriteUInt(count, 16)
        net.WriteUInt(#chunk, 16)
        net.WriteData(chunk, #chunk)
        if recipients then net.Send(recipients) else net.Broadcast() end
    end
    return true
end

function ANN.SendSnapshot(recipients)
    local payload = encode(ANN.GetSnapshot(), ANN.MaxSnapshotBytes)
    return sendChunks(ANN.NetSnapshot, payload, recipients, ANN.Revision * 65536 + ANN.Sequence)
end

function ANN.BroadcastSnapshot()
    return ANN.SendSnapshot()
end

function ANN.BroadcastDelta(delta)
    delta.revision = ANN.Revision
    delta.serverTime = CurTime()
    local payload = encode(delta, 60000)
    if not payload or #payload > 60000 then return ANN.BroadcastSnapshot() end
    net.Start(ANN.NetDelta)
    net.WriteUInt(#payload, 16)
    net.WriteData(payload, #payload)
    net.Broadcast()
end

local function canEdit(ply)
    return game.SinglePlayer() or (IsValid(ply) and ply:IsAdmin())
end

local function providerCatalog()
    local result = {}
    for id, provider in pairs(ANN.DataProviders) do
        local fields = ANN.DeepCopy(provider.fields)
        local seen = {}
        for _, field in ipairs(fields) do seen[field.path] = true end
        local function discover(value, prefix, depth)
            if depth > 8 or #fields >= 512 then return end
            if type(value) ~= 'table' then
                if prefix ~= '' and not seen[prefix] then
                    seen[prefix] = true
                    table.insert(fields, {
                        path = prefix,
                        type = type(value),
                        label = prefix .. ' (live)'
                    })
                end
                return
            end
            for key, child in pairs(value) do
                if #fields >= 512 then break end
                local path = prefix == '' and tostring(key) or prefix .. '.' .. tostring(key)
                discover(child, path, depth + 1)
            end
        end
        discover(ANN.ProviderValues[id], '', 0)
        table.sort(fields, function(left, right) return left.path < right.path end)
        result[id] = {
            id = id,
            label = provider.label,
            interval = provider.interval,
            fields = fields,
            value = ANN.DeepCopy(ANN.ProviderValues[id])
        }
    end
    return result
end

local function propCatalog()
    local result = {}
    for _, entity in ipairs(ents.FindByClass('prop_dynamic') or {}) do
        if #result >= 1024 then break end
        local targetname = entity:GetName()
        local group, alarm = string.match(targetname or '', '^ANN_([A-Z0-9]+)_(.+)$')
        if group and alarm then
            table.insert(result, {
                targetname = targetname,
                group = string.lower(group),
                alarm = ANN.NormalizeId(alarm),
                model = entity:GetModel()
            })
        end
    end
    table.sort(result, function(left, right) return left.targetname < right.targetname end)
    return result
end

local function audioCatalog()
    local result = {}
    for id, sound in pairs(LUASQUARE_AUDIO and LUASQUARE_AUDIO.Catalog
        and LUASQUARE_AUDIO.Catalog.sounds or {}) do
        if sound.mode == 'source' or sound.mode == 'global' then
            result[id] = {
                id = id,
                label = sound.label or id,
                mode = sound.mode,
                path = sound.path,
                script = sound.script,
                soundScript = sound.soundScript,
                volume = sound.volume,
                pitch = sound.pitch,
                soundLevel = sound.soundLevel,
                channel = sound.channel,
                dsp = sound.dsp,
                duration = sound.duration,
                loop = sound.loop
            }
        end
    end
    return result
end

function ANN.SendEditorCatalog(ply)
    if not canEdit(ply) then return false end
    local sources = {}
    for path, source in pairs(ANN.Sources) do
        sources[path] = ANN.DeepCopy(source.source)
    end
    local catalog = {
        revision = ANN.Revision,
        map = game.GetMap(),
        providers = providerCatalog(),
        props = propCatalog(),
        sounds = audioCatalog(),
        sources = sources,
        diagnostics = ANN.DeepCopy(ANN.SourceDiagnostics)
    }
    local payload = encode(catalog, 4 * 1024 * 1024)
    return sendChunks(ANN.NetCatalog, payload, ply, ANN.Revision)
end

net.Receive(ANN.NetRequest, function(_, ply)
    local current = RealTime()
    if current < (requestCooldowns[ply] or 0) then return end
    requestCooldowns[ply] = current + 1
    ANN.SendSnapshot(ply)
end)

net.Receive(ANN.NetCatalogRequest, function(_, ply)
    if not canEdit(ply) then return end
    local current = RealTime()
    if current < (catalogCooldowns[ply] or 0) then return end
    catalogCooldowns[ply] = current + 2
    ANN.SendEditorCatalog(ply)
end)

hook.Add('PlayerInitialSpawn', 'LUASQUARE_ANNUNCIATOR_LateJoin', function(ply)
    timer.Simple(2, function()
        if IsValid(ply) and LUASQUARE_ANNUNCIATOR then
            LUASQUARE_ANNUNCIATOR.SendSnapshot(ply)
        end
    end)
end)
