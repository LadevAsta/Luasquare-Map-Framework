local MAP = LUASQUARE_MAP
local peers, revision = {}, 0
local CHUNK, MAX_BYTES = 24000, 8 * 1024 * 1024
for _, name in ipairs({'Request', 'Transfer', 'Reset'}) do util.AddNetworkString('LUASQUARE_MAP_' .. name) end
local function allowed(player) return IsValid(player) and (game.SinglePlayer() or player:IsAdmin()) end

local function enqueue(peer, kind, value, stringLimit)
    local text = MAP.CanonicalJSON(value, stringLimit)
    if not text or #text > MAX_BYTES then return false end
    if peer.queuedBytes + #text > MAX_BYTES then return false end
    peer.serial = (peer.serial + 1) % 4294967295
    peer.queue[#peer.queue + 1] = {kind = kind, text = text, serial = peer.serial, index = 1, count = math.ceil(#text / CHUNK)}
    peer.queuedBytes = peer.queuedBytes + #text
    return true
end

local function discover(family)
    local paths, remaining, directoriesLeft = {}, 256, 512
    local function walk(relative, depth)
        if depth > 4 or remaining <= 0 or directoriesLeft <= 0 then return end
        directoriesLeft = directoriesLeft - 1
        local files, directories = file.Find('data_static/luasquare/' .. family .. '/' .. relative .. '*', 'GAME')
        table.sort(files or {}); table.sort(directories or {})
        for _, name in ipairs(files or {}) do
            local path = relative .. name
            if MAP.SourcePath(family, path) then paths[#paths + 1] = path; remaining = remaining - 1 end
            if remaining <= 0 then break end
        end
        for _, name in ipairs(directories or {}) do
            if name:match('^[a-z0-9_%-]+$') then walk(relative .. name .. '/', depth + 1) end
        end
    end
    walk('', 0)
    return paths
end

function MAP.InspectionCatalog()
    local types, packages, sources = {}, {}, {}
    for id, definition in pairs(MAP.Types) do
        types[id] = {label = definition.label or id, package = definition.package,
            fields = MAP.Copy(definition.fields), ports = MAP.Copy(definition.ports or {}), capacities = MAP.Copy(definition.capacities or {}), generation = MAP.Copy(definition.generation or {})}
    end
    for id, definition in pairs(MAP.Packages) do packages[id] = {requires = MAP.Copy(definition.requires or {})} end
    for _, family in ipairs({'map', 'components', 'control', '3d2display', 'audio', 'timeline', 'annunciator'}) do sources[family] = discover(family) end
    local active = {}
    for id, instance in pairs(MAP.Instances) do
        active[id] = {running = instance.running, origin = instance.compiled.origin, nodes = MAP.DescribeInstance(instance)}
    end
    local entities, seg7Prefixes, scanned = {}, {}, 0
    local supported = {func_movelinear = true, func_rotating = true, func_door = true, func_door_rotating = true, func_tracktrain = true,
        env_sprite = true, logic_relay = true, ambient_generic = true, env_shake = true, path_track = true, prop_dynamic = true}
    for _, entity in ipairs(ents.GetAll()) do
        scanned = scanned + 1
        if scanned > 16384 or #entities >= 1024 then break end
        if IsValid(entity) and supported[entity:GetClass()] then
            local name = entity:GetName()
            if name ~= '' and #name <= 128 then
                entities[#entities + 1] = {name = name, class = entity:GetClass()}
                local prefix, index = name:match('^SEG7_([a-z0-9_][a-z0-9_.%-]*)_(%d+)$')
                if prefix and entity:GetClass() == 'prop_dynamic' and tonumber(index) < 32 then
                    seg7Prefixes[prefix] = (seg7Prefixes[prefix] or 0) + 1
                end
            end
        end
    end
    table.sort(entities, function(a, b) return a.name < b.name end)
    local timelineComponents, count = {}, 0
    for id, component in pairs(LUASQUARE_TIMELINE and LUASQUARE_TIMELINE.Components or {}) do
        if count >= 2048 then break end
        timelineComponents[id] = {label = component.label, type = component.type}; count = count + 1
    end
    local startupNamespaces, seenNamespaces = {}, {}
    for _, definition in pairs(MAP.PlantDefinitions or {}) do
        if definition.namespace and not seenNamespaces[definition.namespace] then
            seenNamespaces[definition.namespace] = true
            startupNamespaces[#startupNamespaces + 1] = definition.namespace
        end
    end
    table.sort(startupNamespaces)
    return {revision = revision, types = types, packages = packages, startupNamespaces = startupNamespaces,
        sources = sources, entities = entities, seg7Prefixes = seg7Prefixes,
        timelineComponents = timelineComponents, active = active, diagnostics = MAP.LastDiagnostics or {}}
end

net.Receive('LUASQUARE_MAP_Request', function(bits, player)
    if bits > 35000 or not allowed(player) then return end
    local operation = net.ReadUInt(3)
    if operation == 0 then peers[player] = nil; return end
    local peer = peers[player]
    if not peer then
        peer = {queue = {}, queuedBytes = 0, serial = 0, ids = {}, previous = {}, nextRequest = 0, expires = 0}
        peers[player] = peer
    end
    if CurTime() < peer.nextRequest then return end
    peer.nextRequest, peer.expires = CurTime() + 0.1, CurTime() + 30
    if operation == 1 then
        if CurTime() < (peer.nextCatalog or 0) then return end
        peer.nextCatalog = CurTime() + 2
        enqueue(peer, 1, MAP.InspectionCatalog())
    elseif operation == 2 then
        local family, path = net.ReadString(), net.ReadString()
        if family ~= 'map' and family ~= 'components' then return end
        if not MAP.SourcePath(family, path) then return end
        local source, err = MAP.ReadSource(family, path)
        -- Keep the source as a separately encoded document. This preserves
        -- empty JSON arrays across the inspection envelope even when catalog
        -- metadata contains ordinary empty Lua tables.
        local sourceText = source and MAP.CanonicalJSON(source) or nil
        enqueue(peer, 2, {revision = revision, family = family, path = path, sourceText = sourceText, error = err}, MAP.Limits.bytes)
    elseif operation == 3 then
        local count = net.ReadUInt(6)
        if count > 32 then return end
        local ids = {}
        for _ = 1, count do
            local id = net.ReadString()
            if not MAP.IsId(id) then return end
            ids[id] = true
        end
        peer.ids, peer.previous = ids, {}
    elseif operation == 4 then
        -- Heartbeat only. No operation in this protocol can mutate a plant.
    end
end)

local nextSample = 0
hook.Add('Think', 'LUASQUARE_MAP_Inspection', function()
    local sample = CurTime() >= nextSample
    if sample then nextSample = CurTime() + 0.5 end
    for player, peer in pairs(peers) do
        if not allowed(player) or CurTime() > peer.expires then peers[player] = nil
        else
            if sample and #peer.queue == 0 then
                local delta = {}
                for id in pairs(peer.ids) do
                    local state = false
                    for _, instance in pairs(MAP.Instances) do
                        local getter = instance.telemetry and instance.telemetry[id]
                        if getter then
                            local ok, result = pcall(getter)
                            if ok then state = MAP.PrimitiveSnapshot(result) end
                        end
                    end
                    local encoded = MAP.CanonicalJSON(state)
                    if encoded ~= peer.previous[id] then delta[id] = state; peer.previous[id] = encoded end
                end
                if next(delta) then enqueue(peer, 3, {revision = revision, state = delta}) end
            end
            local transfer = peer.queue[1]
            if transfer then
                local chunk = transfer.text:sub((transfer.index - 1) * CHUNK + 1, transfer.index * CHUNK)
                net.Start('LUASQUARE_MAP_Transfer')
                net.WriteUInt(transfer.kind, 2); net.WriteUInt(transfer.serial, 32)
                net.WriteUInt(transfer.index, 10); net.WriteUInt(transfer.count, 10)
                net.WriteUInt(#chunk, 15); net.WriteData(chunk, #chunk); net.Send(player)
                transfer.index = transfer.index + 1
                if transfer.index > transfer.count then peer.queuedBytes = peer.queuedBytes - #transfer.text; table.remove(peer.queue, 1) end
            end
        end
    end
end)

function MAP.ResetInspection()
    revision = (revision + 1) % 4294967295
    peers = {}
    net.Start('LUASQUARE_MAP_Reset'); net.Broadcast()
end
hook.Add('PlayerDisconnected', 'LUASQUARE_MAP_InspectionDisconnect', function(player) peers[player] = nil end)
hook.Add('PreCleanupMap', 'LUASQUARE_MAP_InspectionCleanup', MAP.ResetInspection)
