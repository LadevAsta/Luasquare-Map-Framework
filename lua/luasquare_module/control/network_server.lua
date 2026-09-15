local CONTROL = LUASQUARE_CONTROL
local subscribers, cooldowns = {}, setmetatable({}, {__mode = 'k'})
local serial = 0
for _, name in ipairs({'Catalog', 'Source', 'State', 'Command', 'Reset'}) do util.AddNetworkString('LUASQUARE_CONTROL_' .. name) end

local function allowed(player) return IsValid(player) and (game.SinglePlayer() or player:IsAdmin()) end
local function owner(player) return 'editor.' .. player:EntIndex() end

local function send(message, value, player)
    local json = util.TableToJSON(value)
    if not json or #json > CONTROL.MaxTransferBytes then return false end
    local payload = util.Compress(json)
    if not payload or #payload > CONTROL.MaxTransferBytes then return false end
    serial = (serial + 1) % 4294967295
    local count = math.max(math.ceil(#payload / CONTROL.ChunkBytes), 1)
    for index = 1, count do
        local chunk = string.sub(payload, (index - 1) * CONTROL.ChunkBytes + 1, index * CONTROL.ChunkBytes)
        net.Start('LUASQUARE_CONTROL_' .. message)
        net.WriteUInt(serial, 32)
        net.WriteUInt(index, 16)
        net.WriteUInt(count, 16)
        net.WriteUInt(#chunk, 16)
        net.WriteData(chunk, #chunk)
        net.Send(player)
    end
    return true
end

local function registrations(values)
    local out = {}
    for id, definition in pairs(values) do out[id] = {label = definition.label or id, parameters = CONTROL.DeepCopy(definition.parameters or {})} end
    return out
end

function CONTROL.EditorCatalog()
    local entities, keypadEntities, displays, suffixes = {}, {}, {}, {}
    for _, class in ipairs({'func_button', 'func_rot_button'}) do
        for _, entity in ipairs(ents.FindByClass(class)) do
            if #entities + #keypadEntities >= CONTROL.MaxControls then break end
            local suffix = string.match(entity:GetName(), '^CTRLI_(.+)$')
            if suffix then
                local id = CONTROL.NormalizeId(suffix)
                local item = {target = entity:GetName(), class = class, id = id}
                if string.sub(entity:GetName(), 1, 10) == 'CTRLI_KPD_' then
                    item.key, item.keypad = CONTROL.KeypadKeyName(entity:GetName())
                    if not item.key then item.diagnostic = 'expected CTRLI_KPD_<0..9/s/b/c>_<name>'
                    elseif class ~= 'func_button' then item.diagnostic = 'keypad subcomponents require func_button' end
                    table.insert(keypadEntities, item)
                else table.insert(entities, item) end
                if id then suffixes[id] = (suffixes[id] or 0) + 1 end
            end
        end
    end
    table.sort(keypadEntities, function(a, b) return a.target < b.target end)
    table.sort(entities, function(a, b) return a.target < b.target end)
    for _, entity in ipairs(entities) do
        if not entity.id then entity.diagnostic = 'suffix cannot form a stable ID'
        elseif suffixes[entity.id] > 1 then entity.diagnostic = 'normalized suffix collision' end
    end
    for _, entity in ipairs(keypadEntities) do
        if not entity.id then entity.diagnostic = 'suffix cannot form a stable ID'
        elseif suffixes[entity.id] > 1 then entity.diagnostic = 'normalized suffix collision' end
    end
    for id in pairs(LUASQUARE_SEG7 and LUASQUARE_SEG7.Displays or {}) do displays[id] = true end
    return {revision = CONTROL.Revision, map = game.GetMap(), running = CONTROL.Running == true,
        sources = CONTROL.EditorSources or CONTROL.Sources, entities = entities, keypadEntities = keypadEntities,
        Actions = registrations(CONTROL.Actions), Predicates = registrations(CONTROL.Predicates), Displays = displays,
        diagnostics = CONTROL.SourceDiagnostics or {}}
end

local function sendCatalog(player)
    local catalog = CONTROL.EditorCatalog()
    local sources = catalog.sources
    -- Individual sources retain their 512 KiB bound even when the map has many packs.
    catalog.sources = {}
    for path in pairs(sources) do catalog.sources[path] = false end
    if not send('Catalog', catalog, player) then return end
    local paths = {}
    for path in pairs(sources) do table.insert(paths, path) end
    table.sort(paths)
    for _, path in ipairs(paths) do
        send('Source', {revision = CONTROL.Revision, path = path, source = sources[path]}, player)
    end
end

local function unsubscribe(player)
    subscribers[player] = nil
    CONTROL.CancelOwner(owner(player))
    CONTROL.UnlockOwner(owner(player))
end

local function sendStates(player, controls, history)
    local batch, count = {}, 0
    for id, state in pairs(controls) do
        batch[id], count = state, count + 1
        if count == 64 then
            send('State', {revision = CONTROL.Revision, controls = batch}, player)
            batch, count = {}, 0
        end
    end
    if count > 0 or history and #history > 0 then
        send('State', {revision = CONTROL.Revision, controls = batch, historyAppend = history}, player)
    end
end

local function sendFullState(player)
    local snapshot = CONTROL.GetSnapshot()
    local controls = snapshot.controls
    snapshot.controls = {}
    send('State', {snapshot = snapshot, history = CONTROL.GetHistory(), full = true}, player)
    sendStates(player, controls)
end

net.Receive('LUASQUARE_CONTROL_Command', function(bits, player)
    if bits > 2048 or not allowed(player) then return end
    local command = net.ReadString()
    if command == 'close' then unsubscribe(player); return end
    local now = RealTime()
    if now < (cooldowns[player] or 0) then return end
    cooldowns[player] = now + (command == 'subscribe' and 2 or 0.15)
    if command == 'subscribe' then
        hook.Add('PlayerDisconnected', 'LUASQUARE_CONTROL_EditorDisconnect', unsubscribe)
        subscribers[player] = {nextSend = 0, previous = {}, historySequence = CONTROL.HistorySerial}
        sendCatalog(player)
        sendFullState(player)
        return
    end
    if not CONTROL.Running then
        send('State', {revision = CONTROL.Revision, diagnostic = 'Control runtime is inactive. Discovery and draft authoring remain available; live tests require valid packed bindings.'}, player)
        return
    end
    if not subscribers[player] then return end
    local id = net.ReadString()
    if #id > 128 or not CONTROL.Controls[id] or CONTROL.Controls[id].keypadKey then return end
    if command == 'lock' then CONTROL.Lock(id, owner(player), 'editor test lock')
    elseif command == 'armFault' then
        CONTROL.Controls[id].rejectNextOwner = owner(player)
        send('State', {revision = CONTROL.Revision, diagnostic = 'Armed one action rejection for ' .. id .. '. The next action will fault; test in a disposable session.'}, player)
    elseif command == 'unlock' then CONTROL.Unlock(id, owner(player))
    elseif command == 'resetFault' then CONTROL.ResetFault(id)
    elseif command == 'request' then
        local operation, hasValue = net.ReadString(), net.ReadBool()
        local value = hasValue and net.ReadDouble() or nil
        if value ~= nil and not CONTROL.Finite(value) then return end
        local requestId, status = CONTROL.Request(id, operation, {actor = player, value = value, owner = owner(player)})
        if not requestId then send('State', {revision = CONTROL.Revision, diagnostic = status}, player) end
    end
end)

local function publish(force)
    for player, subscription in pairs(subscribers) do
        if not allowed(player) then unsubscribe(player)
        elseif force or RealTime() >= subscription.nextSend then
            subscription.nextSend = RealTime() + 0.25
            local snapshot = CONTROL.GetSnapshot()
            local changed = {}
            for id, state in pairs(snapshot.controls) do
                local json = util.TableToJSON(state)
                if subscription.previous[id] ~= json then changed[id] = state; subscription.previous[id] = json end
            end
            local history = {}
            for _, entry in ipairs(CONTROL.History) do
                if entry.sequence > subscription.historySequence then table.insert(history, entry) end
            end
            subscription.historySequence = CONTROL.HistorySerial
            if next(changed) or #history > 0 then sendStates(player, changed, history) end
        end
    end
end

function CONTROL.PublishState() if CONTROL.Running then publish(true) end end

function CONTROL.StartNetwork()
    hook.Add('PlayerDisconnected', 'LUASQUARE_CONTROL_EditorDisconnect', unsubscribe)
    hook.Add('Think', 'LUASQUARE_CONTROL_Network', function() publish(false) end)
end

function CONTROL.BroadcastReset()
    net.Start('LUASQUARE_CONTROL_Reset')
    net.Broadcast()
    for player, subscription in pairs(subscribers) do
        subscription.previous = {}
        subscription.historySequence = CONTROL.HistorySerial
        sendCatalog(player)
        sendFullState(player)
    end
end

function CONTROL.StopNetwork()
    for player in pairs(subscribers) do CONTROL.CancelOwner(owner(player)) end
    subscribers = {}
    hook.Remove('Think', 'LUASQUARE_CONTROL_Network')
    hook.Remove('PlayerDisconnected', 'LUASQUARE_CONTROL_EditorDisconnect')
    net.Start('LUASQUARE_CONTROL_Reset')
    net.Broadcast()
end

concommand.Add('luasquare_control_reload', function(player)
    if IsValid(player) and not allowed(player) then return end
    local ok, reason = CONTROL.ReloadSources()
    print('[LUASQUARE_CONTROL] ' .. (ok and 'Sources reloaded.' or tostring(reason)))
end)

concommand.Add('luasquare_control_reject_next', function(player, _, args)
    if IsValid(player) and not allowed(player) then return end
    local control = CONTROL.Controls[args[1] or '']
    if not CONTROL.Running or not control then print('[LUASQUARE_CONTROL] Unknown packed control.'); return end
    control.rejectNextOwner = IsValid(player) and owner(player) or 'debug.fixture'
    print('[LUASQUARE_CONTROL] Armed explicit one-action rejection fixture: ' .. control.id)
end)
