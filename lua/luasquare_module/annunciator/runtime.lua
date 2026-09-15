if not SERVER then return end

LUASQUARE_ANNUNCIATOR = LUASQUARE_ANNUNCIATOR or {}
local ANN = LUASQUARE_ANNUNCIATOR

ANN.DataProviders = ANN.DataProviders or {}
ANN.ProviderValues = ANN.ProviderValues or {}
ANN.Sources = ANN.Sources or {}
ANN.SourceDiagnostics = ANN.SourceDiagnostics or {}
ANN.Groups = ANN.Groups or {}
ANN.Alarms = ANN.Alarms or {}
ANN.Revision = ANN.Revision or 0
ANN.Sequence = ANN.Sequence or 0
ANN.TimerName = 'LUASQUARE_ANNUNCIATOR_Runtime'
ANN.GlobalMutedUntil = ANN.GlobalMutedUntil or 0

local function log(message)
    print('[LUASQUARE_ANNUNCIATOR] ' .. tostring(message))
end

local function now()
    return CurTime and CurTime() or os.clock()
end

local function jsonSafe(value, depth, seen)
    depth = depth or 0
    if depth > 16 then return nil end
    local kind = type(value)
    if kind == 'nil' or kind == 'number' or kind == 'string' or kind == 'boolean' then return value end
    if kind ~= 'table' then return tostring(value) end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local result, count = {}, 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 4096 then break end
        result[type(key) == 'number' and key or tostring(key)] = jsonSafe(item, depth + 1, seen)
    end
    seen[value] = nil
    return result
end

local function normalizeFields(fields)
    local result = {}
    for _, field in ipairs(type(fields) == 'table' and fields or {}) do
        if #result >= 512 then break end
        if type(field) == 'table' and type(field.path) == 'string' and field.path ~= '' then
            table.insert(result, {
                path = field.path,
                type = tostring(field.type or 'unknown'),
                label = field.label and tostring(field.label) or nil
            })
        end
    end
    return result
end

function ANN.RegisterDataProvider(id, getter, options)
    id = ANN.NormalizeId(id)
    if not id or type(getter) ~= 'function' then return false, 'invalid provider' end
    options = options or {}
    ANN.DataProviders[id] = {
        id = id,
        getter = getter,
        interval = math.max(tonumber(options.interval) or ANN.TickInterval, 0.02),
        fields = normalizeFields(options.fields),
        label = tostring(options.label or id),
        nextSample = 0,
        nextDiagnostic = 0
    }
    return true
end

function ANN.UnregisterDataProvider(id)
    id = ANN.NormalizeId(id)
    if not id or not ANN.DataProviders[id] then return false end
    ANN.DataProviders[id] = nil
    ANN.ProviderValues[id] = nil
    return true
end

function ANN.GetDataProvider(id)
    return ANN.DataProviders[ANN.NormalizeId(id)]
end

function ANN.GetDataProviders()
    return ANN.DataProviders
end

function ANN.GetProviderValue(id)
    return ANN.ProviderValues[ANN.NormalizeId(id)]
end

local function publicState(alarm)
    local state = alarm.state
    return {
        id = alarm.id,
        label = alarm.label,
        group = alarm.group,
        tier = alarm.tier,
        color = ANN.DeepCopy(alarm.color),
        active = state.active,
        acknowledged = state.acknowledged,
        resolved = state.resolved,
        test = state.test,
        muted = alarm.tier > 1 and alarm.tier < 4
            and ANN.IsMuted and ANN.IsMuted(alarm.group) or false,
        message = state.message,
        activatedAt = state.activatedAt,
        acknowledgedAt = state.acknowledgedAt,
        resolvedAt = state.resolvedAt,
        changedAt = state.changedAt,
        visualState = ANN.GetVisualState(state)
    }
end

local function publicGroup(group)
    return {
        id = group.id,
        label = group.label,
        muteSeconds = group.muteSeconds,
        mutedUntil = group.mutedUntil or 0,
        muted = ANN.IsMuted and ANN.IsMuted(group.id) or false
    }
end

function ANN.GetAlarm(id)
    return ANN.Alarms[ANN.NormalizeId(id)]
end

function ANN.GetGroup(id)
    return ANN.Groups[ANN.NormalizeId(id)]
end

function ANN.GetState(id)
    local alarm = ANN.GetAlarm(id)
    return alarm and publicState(alarm) or nil
end

local function inScope(alarm, scope)
    scope = ANN.NormalizeId(scope)
    return not scope or scope == 'all' or alarm.group == scope or alarm.id == scope
end

function ANN.GetCounts(scope)
    local counts = {active = 0, unacknowledged = 0, resolved = 0, test = 0, total = 0}
    for _, alarm in pairs(ANN.Alarms) do
        if inScope(alarm, scope) then
            counts.total = counts.total + 1
            if alarm.state.active then counts.active = counts.active + 1 end
            if alarm.state.active and not alarm.state.acknowledged then
                counts.unacknowledged = counts.unacknowledged + 1
            end
            if alarm.state.resolved then counts.resolved = counts.resolved + 1 end
            if alarm.state.test then counts.test = counts.test + 1 end
        end
    end
    return counts
end

function ANN.GetSnapshot(scope)
    local alarms, groups = {}, {}
    for id, alarm in pairs(ANN.Alarms) do
        if inScope(alarm, scope) then
            alarms[id] = publicState(alarm)
            groups[alarm.group] = publicGroup(ANN.Groups[alarm.group])
        end
    end
    return {
        schema = ANN.Schema,
        revision = ANN.Revision,
        sequence = ANN.Sequence,
        serverTime = now(),
        globalMutedUntil = ANN.GlobalMutedUntil,
        alarms = alarms,
        groups = groups,
        counts = ANN.GetCounts(scope)
    }
end

local function emitAlarmChange(alarm, reason)
    ANN.Sequence = ANN.Sequence + 1
    alarm.state.changedAt = now()
    local state = publicState(alarm)
    hook.Run('LuasquareAnnunciatorAlarmChanged', alarm.id, state, reason)
    if ANN.BroadcastDelta then
        ANN.BroadcastDelta({sequence = ANN.Sequence, alarms = {[alarm.id] = state}})
    end
end

local function emitGroupChange(group, reason)
    ANN.Sequence = ANN.Sequence + 1
    local state = publicGroup(group)
    local alarms = {}
    for id, alarm in pairs(ANN.Alarms) do
        if alarm.group == group.id then alarms[id] = publicState(alarm) end
    end
    hook.Run('LuasquareAnnunciatorGroupChanged', group.id, state, reason)
    if ANN.BroadcastDelta then
        ANN.BroadcastDelta({
            sequence = ANN.Sequence,
            groups = {[group.id] = state},
            alarms = alarms,
            globalMutedUntil = ANN.GlobalMutedUntil
        })
    end
end

local function resolveMessage(alarm)
    if type(alarm.message) == 'string' then return alarm.message end
    if type(alarm.message) ~= 'table' then return alarm.label end
    local value, valid = ANN.ResolveOperand(alarm.message, ANN.ProviderValues)
    if not valid or value == nil then value = alarm.message.default end
    return value == nil and alarm.label or tostring(value)
end

local function runtimeDiagnostic(alarm, key, message)
    alarm._diagnostics = alarm._diagnostics or {}
    if alarm._diagnostics[key] then return end
    alarm._diagnostics[key] = true
    ANN.SourceDiagnostics[alarm._origin] = ANN.SourceDiagnostics[alarm._origin] or {}
    ANN.AddDiagnostic(ANN.SourceDiagnostics[alarm._origin], 'warning',
        '$.alarms.' .. alarm.id, message, alarm._origin)
    log(message)
end

local function resolveProps(alarm)
    if alarm._propsResolved then
        local valid = #alarm._props > 0
        for _, entity in ipairs(alarm._props) do
            if not IsValid(entity) then valid = false break end
        end
        if valid or now() < (alarm._nextResolve or 0) then return alarm._props end
    end
    alarm._propsResolved = true
    alarm._nextResolve = now() + 5
    alarm._props = {}
    for _, targetname in ipairs(alarm.indicator.targetnames) do
        local accepted = 0
        for _, entity in ipairs(ents.FindByName(targetname) or {}) do
            if IsValid(entity) and entity:GetClass() == 'prop_dynamic' then
                local expected = alarm.indicator.expectedModel
                if not expected or string.lower(entity:GetModel() or '') == string.lower(expected) then
                    table.insert(alarm._props, entity)
                    if alarm._visual then
                        entity:SetSkin(alarm.indicator.skins[alarm._visual])
                    end
                    accepted = accepted + 1
                end
            end
        end
        if accepted == 0 then
            runtimeDiagnostic(alarm, 'prop:' .. targetname,
                'Indicator target did not resolve to a matching prop_dynamic: ' .. targetname)
        end
    end
    return alarm._props
end

local function applyVisual(alarm, force)
    local visual = ANN.GetVisualState(alarm.state)
    local props = resolveProps(alarm)
    if not force and alarm._visual == visual then return end
    alarm._visual = visual
    local skin = alarm.indicator.skins[visual]
    for _, entity in ipairs(props) do
        if IsValid(entity) then entity:SetSkin(skin) end
    end
end

local function stopAudio(alarm)
    if LUASQUARE_AUDIO and LUASQUARE_AUDIO.StopOwnerSounds then
        LUASQUARE_AUDIO.StopOwnerSounds('annunciator:' .. alarm.id)
    end
    alarm._audioPlaying = false
    alarm._nextRepeat = nil
end

function ANN.IsMuted(scope)
    local current = now()
    if current < (ANN.GlobalMutedUntil or 0) then return true end
    local group = ANN.Groups[ANN.NormalizeId(scope)]
    return group ~= nil and current < (group.mutedUntil or 0)
end

local function audioEligible(alarm)
    if not alarm.audio then return false end
    local state = alarm.state
    if alarm.tier == 4 then return state.active end
    if not state.active and not state.test then return false end
    if ANN.IsMuted(alarm.group) then return false end
    if state.acknowledged and alarm.audio.ackSilences then return false end
    return true
end

local function emitterOptions(alarm)
    if alarm.tier == 4 then return {global = true} end
    for _, entity in ipairs(resolveProps(alarm)) do
        if IsValid(entity) then return {entity = entity} end
    end
    local group = ANN.Groups[alarm.group]
    local origin = group and group.soundOrigin
    if not origin then return {} end
    if origin.targetname then return {targetname = origin.targetname} end
    if origin.position then
        return {position = Vector(origin.position[1], origin.position[2], origin.position[3])}
    end
    return {}
end

local function playAudio(alarm, looped)
    if not LUASQUARE_AUDIO or not LUASQUARE_AUDIO.PlaySound then return false end
    local options = emitterOptions(alarm)
    options.ownerId = 'annunciator:' .. alarm.id
    options.loop = looped
    options.clientVolumeConVar = ANN.VolumeConVar
    options.pitch = alarm.audio.pitch
    options.volume = alarm.audio.volume
    options.soundLevel = alarm.audio.soundLevel
    options.subtitle = false
    local ok, reason = LUASQUARE_AUDIO.PlaySound(alarm.audio.sound, options)
    if not ok and not alarm._audioDiagnostic then
        alarm._audioDiagnostic = true
        runtimeDiagnostic(alarm, 'audio-playback',
            'Audio unavailable for ' .. alarm.id .. ': ' .. tostring(reason))
    end
    return ok
end

local function updateAudio(alarm, currentTime)
    if not audioEligible(alarm) then
        if alarm._audioPlaying then stopAudio(alarm) end
        return
    end
    local mode = alarm.audio.mode
    if mode == 'loop' then
        if not alarm._audioPlaying then alarm._audioPlaying = playAudio(alarm, true) end
    elseif mode == 'once' then
        if not alarm._audioPlaying then
            playAudio(alarm, false)
            alarm._audioPlaying = true
        end
    elseif currentTime >= (alarm._nextRepeat or 0) then
        playAudio(alarm, false)
        alarm._nextRepeat = currentTime + alarm.audio.repeatSeconds
        alarm._audioPlaying = true
    end
end

local function resetAudioGate(alarm)
    stopAudio(alarm)
    alarm._audioPlaying = false
end

local function setTrip(alarm, currentTime)
    local state = alarm.state
    state.active = true
    state.acknowledged = false
    state.resolved = false
    state.activatedAt = currentTime
    state.acknowledgedAt = nil
    state.resolvedAt = nil
    resetAudioGate(alarm)
    applyVisual(alarm)
    emitAlarmChange(alarm, 'activated')
end

local function setResolved(alarm, currentTime)
    local state = alarm.state
    state.active = false
    state.resolved = true
    state.resolvedAt = currentTime
    stopAudio(alarm)
    applyVisual(alarm)
    emitAlarmChange(alarm, 'resolved')
end

local function updateAlarm(alarm, currentTime)
    local condition, conditionValid = ANN.EvaluateCondition(alarm.condition, ANN.ProviderValues)
    if not conditionValid then return end
    local state = alarm.state
    local message = resolveMessage(alarm)
    if message ~= state.message then
        state.message = message
        emitAlarmChange(alarm, 'message')
    end
    if alarm.tier == 1 then
        if state.active ~= condition then
            state.active = condition
            state.acknowledged = false
            state.resolved = false
            state.activatedAt = condition and currentTime or nil
            state.resolvedAt = not condition and currentTime or nil
            applyVisual(alarm)
            emitAlarmChange(alarm, condition and 'activated' or 'cleared')
        end
        return
    end
    if condition and not state.active then
        setTrip(alarm, currentTime)
    elseif state.active then
        local clear = not condition
        if alarm.clearCondition then
            local clearValue, clearValid = ANN.EvaluateCondition(alarm.clearCondition, ANN.ProviderValues)
            clear = clearValid and clearValue or false
        end
        if clear then setResolved(alarm, currentTime) end
    end
    if state.active and state.acknowledged and alarm.reAlarmSeconds > 0
        and currentTime >= (state.acknowledgedAt or currentTime) + alarm.reAlarmSeconds then
        state.acknowledged = false
        state.acknowledgedAt = nil
        resetAudioGate(alarm)
        applyVisual(alarm)
        emitAlarmChange(alarm, 'realarm')
    end
    updateAudio(alarm, currentTime)
end

local function sampleProviders(currentTime)
    for id, provider in pairs(ANN.DataProviders) do
        if currentTime >= provider.nextSample then
            provider.nextSample = currentTime + provider.interval
            local ok, value = pcall(provider.getter)
            if ok and value ~= nil then
                ANN.ProviderValues[id] = jsonSafe(value)
            elseif currentTime >= provider.nextDiagnostic then
                provider.nextDiagnostic = currentTime + 10
                log('Provider ' .. id .. ' failed; retaining last valid sample: '
                    .. tostring(ok and 'returned nil' or value))
            end
        end
    end
end

function ANN.Update()
    if not ANN.RuntimeStarted then return end
    local currentTime = now()
    sampleProviders(currentTime)
    local muted = ANN.IsMuted()
    if ANN._lastGlobalMuted ~= muted then
        ANN._lastGlobalMuted = muted
        if ANN.BroadcastSnapshot then ANN.BroadcastSnapshot() end
    end
    for _, group in pairs(ANN.Groups) do
        local groupMuted = ANN.IsMuted(group.id)
        if group._lastMuted ~= groupMuted then
            group._lastMuted = groupMuted
            emitGroupChange(group, groupMuted and 'muted' or 'unmuted')
        end
    end
    for _, alarm in pairs(ANN.Alarms) do
        updateAlarm(alarm, currentTime)
        applyVisual(alarm)
    end
end

local function loadSource(path)
    local raw = file.Read(path, 'GAME')
    if not raw then return false, 'source not found' end
    if #raw > ANN.MaxSourceBytes then return false, 'source exceeds byte limit' end
    local source = util.JSONToTable(raw)
    if not source then return false, 'invalid JSON' end
    local compiled, diagnostics = ANN.CompileSource(source, path)
    diagnostics = diagnostics or {}
    if compiled then
        if ANN.PackIds[compiled.id] then
            ANN.AddDiagnostic(diagnostics, 'error', '$.id',
                'duplicate pack ID; first-loaded source retained from ' .. ANN.PackIds[compiled.id], path)
        end
        for providerId in pairs(compiled.providers) do
            if not ANN.DataProviders[providerId] then
                ANN.AddDiagnostic(diagnostics, 'error', '$.alarms',
                    'unregistered provider: ' .. providerId, path)
            end
        end
        for id in pairs(compiled.groups) do
            if ANN.Groups[id] then
                ANN.AddDiagnostic(diagnostics, 'error', '$.groups.' .. id,
                    'duplicate group ID; first-loaded source retained', path)
            end
        end
        for id in pairs(compiled.alarms) do
            if ANN.Alarms[id] then
                ANN.AddDiagnostic(diagnostics, 'error', '$.alarms.' .. id,
                    'duplicate alarm ID; first-loaded source retained', path)
            end
        end
        if table.Count(ANN.Groups) + table.Count(compiled.groups) > ANN.MaxGroups then
            ANN.AddDiagnostic(diagnostics, 'error', '$.groups',
                'installed group count would exceed ' .. ANN.MaxGroups, path)
        end
        if table.Count(ANN.Alarms) + table.Count(compiled.alarms) > ANN.MaxAlarms then
            ANN.AddDiagnostic(diagnostics, 'error', '$.alarms',
                'installed alarm count would exceed ' .. ANN.MaxAlarms, path)
        end
    end
    ANN.SourceDiagnostics[path] = diagnostics
    if not compiled or ANN.HasErrors(diagnostics) then
        log('Rejected source ' .. path .. ':\n' .. ANN.DiagnosticsText(diagnostics))
        return false, ANN.DiagnosticsText(diagnostics)
    end
    ANN.Sources[path] = compiled
    ANN.PackIds[compiled.id] = path
    for id, group in pairs(compiled.groups) do
        group.mutedUntil = 0
        ANN.Groups[id] = group
    end
    for id, alarm in pairs(compiled.alarms) do
        alarm._origin = path
        alarm.state = {
            active = false,
            acknowledged = false,
            resolved = false,
            test = false,
            message = alarm.label,
            changedAt = now()
        }
        ANN.Alarms[id] = alarm
        if alarm.audio and LUASQUARE_AUDIO and LUASQUARE_AUDIO.Catalog
            and not LUASQUARE_AUDIO.Catalog.sounds[alarm.audio.sound] then
            runtimeDiagnostic(alarm, 'audio-id',
                'Registered sound ID is unavailable for ' .. id .. ': ' .. alarm.audio.sound)
        end
        applyVisual(alarm, true)
    end
    return true, compiled
end

local function collectSourcePaths(root, result)
    local files, directories = file.Find(root .. '/*', 'GAME')
    for _, name in ipairs(files or {}) do
        if string.sub(string.lower(name), -5) == '.json' then
            table.insert(result, root .. '/' .. name)
        end
    end
    for _, directory in ipairs(directories or {}) do
        collectSourcePaths(root .. '/' .. directory, result)
    end
end

local function sourcePaths(root)
    local result = {}
    collectSourcePaths(root, result)
    table.sort(result, function(left, right) return string.lower(left) < string.lower(right) end)
    return result
end

function ANN.ReloadSources(mapName)
    for _, alarm in pairs(ANN.Alarms) do
        stopAudio(alarm)
        if alarm.state then
            alarm.state.active = false
            alarm.state.resolved = false
            alarm.state.test = false
            applyVisual(alarm, true)
        end
    end
    ANN.Sources = {}
    ANN.PackIds = {}
    ANN.SourceDiagnostics = {}
    ANN.Groups = {}
    ANN.Alarms = {}
    ANN.GlobalMutedUntil = 0
    local map = string.lower(tostring(mapName or game.GetMap() or ''))
    local loaded = 0
    for _, path in ipairs(sourcePaths(ANN.SourceRoot .. '/' .. map)) do
        if loadSource(path) then loaded = loaded + 1 end
    end
    ANN.Revision = ANN.Revision + 1
    if ANN.BroadcastSnapshot then ANN.BroadcastSnapshot() end
    return loaded
end

function ANN.Acknowledge(scope)
    local changed = 0
    for _, alarm in pairs(ANN.Alarms) do
        if inScope(alarm, scope) and alarm.tier > 1 then
            local state = alarm.state
            if state.test or (state.active and not state.acknowledged) then
                state.test = false
                if state.active then
                    state.acknowledged = true
                    state.acknowledgedAt = now()
                end
                if alarm.audio and alarm.audio.ackSilences and alarm.tier ~= 4 then
                    stopAudio(alarm)
                end
                applyVisual(alarm)
                emitAlarmChange(alarm, 'acknowledged')
                changed = changed + 1
            end
        end
    end
    return changed
end

function ANN.Reset(scope)
    local changed = 0
    for _, alarm in pairs(ANN.Alarms) do
        if inScope(alarm, scope) and alarm.tier > 1 and alarm.state.resolved then
            alarm.state.resolved = false
            alarm.state.acknowledged = false
            alarm.state.acknowledgedAt = nil
            alarm.state.resolvedAt = nil
            applyVisual(alarm)
            emitAlarmChange(alarm, 'reset')
            changed = changed + 1
        end
    end
    return changed
end

function ANN.Mute(scope, duration)
    if type(scope) == 'number' and duration == nil then duration, scope = scope, nil end
    scope = ANN.NormalizeId(scope)
    if scope == 'all' or scope == 'global' then scope = nil end
    local currentTime = now()
    if scope then
        local group = ANN.Groups[scope]
        if not group then return false, 'unknown group' end
        group.mutedUntil = currentTime + ANN.Clamp(duration or group.muteSeconds, 0, 3600)
        emitGroupChange(group, 'muted')
    else
        ANN.GlobalMutedUntil = currentTime + ANN.Clamp(duration or 60, 0, 3600)
        if ANN.BroadcastSnapshot then ANN.BroadcastSnapshot() end
    end
    for _, alarm in pairs(ANN.Alarms) do
        if inScope(alarm, scope) and alarm.tier ~= 4 then stopAudio(alarm) end
    end
    return true
end

function ANN.Unmute(scope)
    scope = ANN.NormalizeId(scope)
    if scope == 'all' or scope == 'global' then scope = nil end
    if scope then
        local group = ANN.Groups[scope]
        if not group then return false, 'unknown group' end
        group.mutedUntil = 0
        emitGroupChange(group, 'unmuted')
    else
        ANN.GlobalMutedUntil = 0
        for _, group in pairs(ANN.Groups) do group.mutedUntil = 0 end
        if ANN.BroadcastSnapshot then ANN.BroadcastSnapshot() end
    end
    for _, alarm in pairs(ANN.Alarms) do
        if inScope(alarm, scope) and alarm.tier ~= 4 then resetAudioGate(alarm) end
    end
    return true
end

function ANN.Test(scope)
    local normalized = ANN.NormalizeId(scope)
    if normalized and normalized ~= 'all' and normalized ~= 'global'
        and not ANN.Groups[normalized] then return false, 'unknown group' end
    if normalized then ANN.GlobalMutedUntil = 0 end
    ANN.Unmute(scope)
    local changed = 0
    for _, alarm in pairs(ANN.Alarms) do
        if inScope(alarm, scope) and (alarm.tier == 2 or alarm.tier == 3)
            and not alarm.state.test then
            alarm.state.test = true
            alarm.state.acknowledged = false
            alarm.state.acknowledgedAt = nil
            resetAudioGate(alarm)
            applyVisual(alarm)
            emitAlarmChange(alarm, 'test')
            changed = changed + 1
        end
    end
    return changed
end

ANN.TestAll = ANN.Test

local function registerIntegrations()
    if LUASQUARE_3D2D and LUASQUARE_3D2D.RegisterAction then
        local actions = {
            acknowledge = function(payload) return ANN.Acknowledge(payload.scope) end,
            reset = function(payload) return ANN.Reset(payload.scope) end,
            mute = function(payload) return ANN.Mute(payload.scope, payload.duration) end,
            unmute = function(payload) return ANN.Unmute(payload.scope) end,
            test = function(payload) return ANN.Test(payload.scope) end
        }
        for id, callback in pairs(actions) do
            LUASQUARE_3D2D.RegisterAction('annunciator.' .. id, {
                label = 'Annunciator ' .. id,
                callback = function(_, _, _, _, context)
                    local payload = type(context.payload) == 'table' and context.payload or {}
                    return callback(payload)
                end
            })
        end
    end
    if LUASQUARE_TIMELINE and LUASQUARE_TIMELINE.RegisterComponent then
        local function parameters(includeDuration)
            local result = {
                {id = 'scope', label = 'Scope', type = 'string', default = ''}
            }
            if includeDuration then
                table.insert(result, {
                    id = 'duration', label = 'Duration', type = 'number',
                    default = 60, min = 0, max = 3600
                })
            end
            return result
        end
        local function control(callback)
            return function(_, value, _, run)
                if run and run.preview then return true end
                return callback(value)
            end
        end
        LUASQUARE_TIMELINE.RegisterComponent('annunciator.controls', {
            type = 'annunciator.controls',
            label = 'Annunciator controls',
            safeReset = function() return true end,
            actions = {
                acknowledge = {
                    kind = 'marker',
                    parameters = parameters(false),
                    execute = control(function(value) return ANN.Acknowledge(value.scope) end)
                },
                reset = {
                    kind = 'marker',
                    parameters = parameters(false),
                    execute = control(function(value) return ANN.Reset(value.scope) end)
                },
                mute = {
                    kind = 'marker',
                    parameters = parameters(true),
                    execute = control(function(value) return ANN.Mute(value.scope, value.duration) end)
                },
                unmute = {
                    kind = 'marker',
                    parameters = parameters(false),
                    execute = control(function(value) return ANN.Unmute(value.scope) end)
                },
                test = {
                    kind = 'marker',
                    parameters = parameters(false),
                    execute = control(function(value) return ANN.Test(value.scope) end)
                }
            }
        })
    end
end

function ANN.Start()
    if ANN.RuntimeStarted then return true end
    ANN.RuntimeStarted = true
    registerIntegrations()
    ANN.ReloadSources(game.GetMap())
    timer.Create(ANN.TimerName, ANN.TickInterval, 0, ANN.Update)
    ANN.Update()
    return true
end

function ANN.Stop()
    if not ANN.RuntimeStarted then return true end
    timer.Remove(ANN.TimerName)
    for _, alarm in pairs(ANN.Alarms) do
        stopAudio(alarm)
        alarm.state.active = false
        alarm.state.resolved = false
        alarm.state.test = false
        applyVisual(alarm, true)
    end
    ANN.RuntimeStarted = false
    ANN.Revision = ANN.Revision + 1
    if ANN.BroadcastSnapshot then ANN.BroadcastSnapshot() end
    return true
end

hook.Add('PreCleanupMap', 'LUASQUARE_ANNUNCIATOR_Stop', function()
    if LUASQUARE_ANNUNCIATOR then LUASQUARE_ANNUNCIATOR.Stop() end
end)
