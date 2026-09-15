LUASQUARE_ANNUNCIATOR = LUASQUARE_ANNUNCIATOR or {}
local ANN = LUASQUARE_ANNUNCIATOR

local validOps = {eq = true, ne = true, gt = true, gte = true, lt = true, lte = true, truthy = true}
local validModes = {once = true, loop = true, ['repeat'] = true}
local validVisuals = {off = true, fast_flash = true, on = true, slow_flash = true}

local function checkKeys(value, allowed, path, diagnostics)
    if type(value) ~= 'table' then return end
    for key in pairs(value) do
        if type(key) ~= 'number' and not allowed[key] then
            ANN.AddDiagnostic(diagnostics, 'error', path .. '.' .. tostring(key),
                'unknown or unsafe schema field')
        end
    end
end

local function checkBinding(binding, path, diagnostics, providers, allowDefault)
    checkKeys(binding, allowDefault and {provider = true, path = true, default = true}
        or {provider = true, path = true}, path, diagnostics)
    if type(binding) ~= 'table' or not ANN.NormalizeId(binding.provider) then
        ANN.AddDiagnostic(diagnostics, 'error', path, 'binding requires a provider ID')
        return
    end
    binding.provider = ANN.NormalizeId(binding.provider)
    providers[binding.provider] = true
    if binding.path ~= nil and (type(binding.path) ~= 'string' or string.find(binding.path, '[%z\1-\31]')) then
        ANN.AddDiagnostic(diagnostics, 'error', path .. '.path', 'path must be a safe dotted string')
    end
end

local function checkCondition(condition, path, diagnostics, providers, depth)
    depth = (depth or 0) + 1
    if depth > 16 then
        ANN.AddDiagnostic(diagnostics, 'error', path, 'condition nesting exceeds 16 levels')
        return
    end
    if type(condition) ~= 'table' then
        ANN.AddDiagnostic(diagnostics, 'error', path, 'condition must be an object')
        return
    end
    checkKeys(condition, {
        all = true, any = true, ['not'] = true,
        provider = true, path = true, op = true, value = true
    }, path, diagnostics)
    local forms = (condition.all and 1 or 0) + (condition.any and 1 or 0)
        + (condition['not'] and 1 or 0) + (condition.provider and 1 or 0)
    if forms ~= 1 then
        ANN.AddDiagnostic(diagnostics, 'error', path, 'condition must contain exactly one of all, any, not, or provider')
        return
    end
    if condition.all or condition.any then
        local children = condition.all or condition.any
        if type(children) ~= 'table' or #children < 1 or #children > 64 then
            ANN.AddDiagnostic(diagnostics, 'error', path, 'all/any requires 1 to 64 child conditions')
            return
        end
        for index, child in ipairs(children) do
            checkCondition(child, path .. '[' .. index .. ']', diagnostics, providers, depth)
        end
        return
    end
    if condition['not'] then
        checkCondition(condition['not'], path .. '.not', diagnostics, providers, depth)
        return
    end
    local conditionBinding = {provider = condition.provider, path = condition.path}
    checkBinding(conditionBinding, path, diagnostics, providers, false)
    condition.provider = conditionBinding.provider
    if not validOps[condition.op] then
        ANN.AddDiagnostic(diagnostics, 'error', path .. '.op', 'invalid comparison operator')
    end
    if type(condition.value) == 'table' and condition.value.provider ~= nil then
        checkBinding(condition.value, path .. '.value', diagnostics, providers, false)
    elseif condition.op ~= 'truthy' and condition.value == nil then
        ANN.AddDiagnostic(diagnostics, 'error', path .. '.value', 'comparison value is required')
    end
end

local function compileGroup(id, source, path, diagnostics)
    if type(source) ~= 'table' then
        ANN.AddDiagnostic(diagnostics, 'error', path, 'group must be an object')
        return nil
    end
    checkKeys(source, {
        label = true, soundOrigin = true, muteSeconds = true, defaults = true
    }, path, diagnostics)
    local group = ANN.DeepCopy(source)
    group.id = id
    group.label = tostring(group.label or id)
    group.muteSeconds = ANN.Clamp(group.muteSeconds or 60, 0, 3600)
    group.defaults = type(group.defaults) == 'table' and group.defaults or {}
    checkKeys(group.defaults, {
        tier = true, indicator = true, audio = true, color = true, reAlarmSeconds = true
    }, path .. '.defaults', diagnostics)
    if group.soundOrigin ~= nil then
        if type(group.soundOrigin) ~= 'table' then
            ANN.AddDiagnostic(diagnostics, 'error', path .. '.soundOrigin', 'sound origin must be an object')
        elseif group.soundOrigin.targetname ~= nil then
            checkKeys(group.soundOrigin, {targetname = true}, path .. '.soundOrigin', diagnostics)
            if not ANN.IsSafeTargetname(group.soundOrigin.targetname) then
                ANN.AddDiagnostic(diagnostics, 'error', path .. '.soundOrigin.targetname', 'unsafe targetname')
            end
        elseif type(group.soundOrigin.position) ~= 'table' or #group.soundOrigin.position ~= 3 then
            ANN.AddDiagnostic(diagnostics, 'error', path .. '.soundOrigin', 'sound origin requires targetname or a three-number position')
        else
            checkKeys(group.soundOrigin, {position = true}, path .. '.soundOrigin', diagnostics)
            for index = 1, 3 do
                if type(group.soundOrigin.position[index]) ~= 'number' then
                    ANN.AddDiagnostic(diagnostics, 'error', path .. '.soundOrigin.position', 'position values must be numbers')
                    break
                end
            end
        end
    end
    return group
end

local function applyDefaults(alarm, defaults)
    for key, value in pairs(defaults or {}) do
        if alarm[key] == nil then alarm[key] = ANN.DeepCopy(value) end
    end
end

local function compileAlarm(id, source, groups, path, diagnostics, providers)
    if type(source) ~= 'table' then
        ANN.AddDiagnostic(diagnostics, 'error', path, 'alarm must be an object')
        return nil
    end
    checkKeys(source, {
        label = true, group = true, tier = true, condition = true, clearCondition = true,
        message = true, indicator = true, audio = true, color = true, reAlarmSeconds = true
    }, path, diagnostics)
    local alarm = ANN.DeepCopy(source)
    alarm.id = id
    alarm.label = tostring(alarm.label or id)
    alarm.group = ANN.NormalizeId(alarm.group)
    applyDefaults(alarm, groups[alarm.group] and groups[alarm.group].defaults)
    alarm.tier = math.floor(tonumber(alarm.tier) or 0)
    if not groups[alarm.group] then ANN.AddDiagnostic(diagnostics, 'error', path .. '.group', 'unknown group') end
    if alarm.tier < 1 or alarm.tier > 4 then ANN.AddDiagnostic(diagnostics, 'error', path .. '.tier', 'tier must be 1, 2, 3, or 4') end
    checkCondition(alarm.condition, path .. '.condition', diagnostics, providers)
    if alarm.clearCondition ~= nil then
        checkCondition(alarm.clearCondition, path .. '.clearCondition', diagnostics, providers)
    end
    if alarm.message ~= nil and type(alarm.message) == 'table' then
        checkBinding(alarm.message, path .. '.message', diagnostics, providers, true)
    elseif alarm.message ~= nil and type(alarm.message) ~= 'string' then
        ANN.AddDiagnostic(diagnostics, 'error', path .. '.message', 'message must be a string or provider binding')
    end
    alarm.reAlarmSeconds = ANN.Clamp(alarm.reAlarmSeconds == nil and 180 or alarm.reAlarmSeconds, 0, 86400)
    if alarm.color ~= nil then
        if type(alarm.color) ~= 'table' then
            ANN.AddDiagnostic(diagnostics, 'error', path .. '.color', 'color must be an array or color object')
        else
            alarm.color = {
                math.floor(ANN.Clamp(alarm.color[1] or alarm.color.r or 255, 0, 255)),
                math.floor(ANN.Clamp(alarm.color[2] or alarm.color.g or 255, 0, 255)),
                math.floor(ANN.Clamp(alarm.color[3] or alarm.color.b or 255, 0, 255)),
                math.floor(ANN.Clamp(alarm.color[4] or alarm.color.a or 255, 0, 255))
            }
        end
    else
        alarm.color = ANN.GetTierColor(alarm.tier)
    end
    alarm.indicator = type(alarm.indicator) == 'table' and alarm.indicator or {}
    checkKeys(alarm.indicator, {
        targetnames = true, expectedModel = true, skins = true
    }, path .. '.indicator', diagnostics)
    alarm.indicator.targetnames = type(alarm.indicator.targetnames) == 'table' and alarm.indicator.targetnames or {}
    if #alarm.indicator.targetnames > 64 then
        ANN.AddDiagnostic(diagnostics, 'error', path .. '.indicator.targetnames', 'at most 64 targets are allowed')
    end
    for index, targetname in ipairs(alarm.indicator.targetnames) do
        if not ANN.IsSafeTargetname(targetname) then
            ANN.AddDiagnostic(diagnostics, 'error', path .. '.indicator.targetnames[' .. index .. ']', 'unsafe targetname')
        end
    end
    if alarm.indicator.expectedModel ~= nil and type(alarm.indicator.expectedModel) ~= 'string' then
        ANN.AddDiagnostic(diagnostics, 'error', path .. '.indicator.expectedModel', 'expected model must be a string')
    end
    local skins = alarm.indicator.skins or {off = 0, fast_flash = 1, on = 2, slow_flash = 3}
    checkKeys(skins, validVisuals, path .. '.indicator.skins', diagnostics)
    alarm.indicator.skins = {}
    for visual in pairs(validVisuals) do
        local skin = tonumber(skins[visual])
        if skin == nil or skin < 0 or skin > 255 then
            ANN.AddDiagnostic(diagnostics, 'error', path .. '.indicator.skins.' .. visual, 'skin must be between 0 and 255')
        else
            alarm.indicator.skins[visual] = math.floor(skin)
        end
    end
    if alarm.audio ~= nil then
        if alarm.tier == 1 then
            ANN.AddDiagnostic(diagnostics, 'error', path .. '.audio', 'status alarms cannot define audio')
        elseif type(alarm.audio) ~= 'table' or not ANN.NormalizeId(alarm.audio.sound) then
            ANN.AddDiagnostic(diagnostics, 'error', path .. '.audio', 'audio requires a registered sound ID')
        else
            checkKeys(alarm.audio, {
                sound = true, mode = true, repeatSeconds = true, ackSilences = true,
                pitch = true, volume = true, soundLevel = true
            }, path .. '.audio', diagnostics)
            alarm.audio.sound = ANN.NormalizeId(alarm.audio.sound)
            alarm.audio.mode = alarm.audio.mode or 'once'
            if not validModes[alarm.audio.mode] then
                ANN.AddDiagnostic(diagnostics, 'error', path .. '.audio.mode', 'mode must be once, loop, or repeat')
            end
            alarm.audio.repeatSeconds = ANN.Clamp(alarm.audio.repeatSeconds or 10, 0.25, 3600)
            alarm.audio.ackSilences = alarm.audio.ackSilences ~= false
            if alarm.audio.pitch ~= nil and tonumber(alarm.audio.pitch) == nil then
                ANN.AddDiagnostic(diagnostics, 'error', path .. '.audio.pitch', 'pitch must be a number')
            elseif alarm.audio.pitch ~= nil then
                alarm.audio.pitch = math.floor(ANN.Clamp(alarm.audio.pitch, 1, 255))
            end
            if alarm.audio.volume ~= nil and tonumber(alarm.audio.volume) == nil then
                ANN.AddDiagnostic(diagnostics, 'error', path .. '.audio.volume', 'volume must be a number')
            elseif alarm.audio.volume ~= nil then
                alarm.audio.volume = ANN.Clamp(alarm.audio.volume, 0, 1)
            end
            if alarm.audio.soundLevel ~= nil and tonumber(alarm.audio.soundLevel) == nil then
                ANN.AddDiagnostic(diagnostics, 'error', path .. '.audio.soundLevel', 'sound level must be a number')
            elseif alarm.audio.soundLevel ~= nil then
                alarm.audio.soundLevel = math.floor(ANN.Clamp(alarm.audio.soundLevel, 0, 511))
            end
            if alarm.tier == 4 then alarm.audio.ackSilences = false end
        end
    elseif alarm.tier == 4 then
        ANN.AddDiagnostic(diagnostics, 'error', path .. '.audio', 'siren alarms require audio')
    end
    return alarm
end

function ANN.CompileSource(source, origin)
    local diagnostics = {}
    if type(source) ~= 'table' then
        ANN.AddDiagnostic(diagnostics, 'error', '$', 'source must be a JSON object', origin)
        return nil, diagnostics
    end
    checkKeys(source, {
        schema = true, kind = true, id = true, label = true, groups = true, alarms = true
    }, '$', diagnostics)
    if source.schema ~= ANN.Schema then ANN.AddDiagnostic(diagnostics, 'error', '$.schema', 'unsupported schema', origin) end
    if source.kind ~= 'annunciator_pack' then ANN.AddDiagnostic(diagnostics, 'error', '$.kind', 'kind must be annunciator_pack', origin) end
    local id = ANN.NormalizeId(source.id)
    if not id then ANN.AddDiagnostic(diagnostics, 'error', '$.id', 'pack ID is required', origin) end
    if type(source.groups) ~= 'table' then ANN.AddDiagnostic(diagnostics, 'error', '$.groups', 'groups object is required', origin) end
    if type(source.alarms) ~= 'table' then ANN.AddDiagnostic(diagnostics, 'error', '$.alarms', 'alarms object is required', origin) end
    local compiled = {id = id, label = tostring(source.label or id or 'Annunciator'), groups = {}, alarms = {}, providers = {}, source = ANN.DeepCopy(source), origin = origin}
    local groupCount = 0
    for rawId, groupSource in pairs(type(source.groups) == 'table' and source.groups or {}) do
        groupCount = groupCount + 1
        local groupId = ANN.NormalizeId(rawId)
        if not groupId or compiled.groups[groupId] then
            ANN.AddDiagnostic(diagnostics, 'error', '$.groups.' .. tostring(rawId), 'invalid or duplicate normalized group ID', origin)
        else
            compiled.groups[groupId] = compileGroup(groupId, groupSource, '$.groups.' .. tostring(rawId), diagnostics)
        end
    end
    if groupCount > ANN.MaxGroups then
        ANN.AddDiagnostic(diagnostics, 'error', '$.groups',
            'group count exceeds ' .. ANN.MaxGroups, origin)
    end
    local alarmCount = 0
    for rawId, alarmSource in pairs(type(source.alarms) == 'table' and source.alarms or {}) do
        alarmCount = alarmCount + 1
        local alarmId = ANN.NormalizeId(rawId)
        if not alarmId or compiled.alarms[alarmId] then
            ANN.AddDiagnostic(diagnostics, 'error', '$.alarms.' .. tostring(rawId), 'invalid or duplicate normalized alarm ID', origin)
        else
            compiled.alarms[alarmId] = compileAlarm(alarmId, alarmSource, compiled.groups, '$.alarms.' .. tostring(rawId), diagnostics, compiled.providers)
        end
    end
    if alarmCount > ANN.MaxAlarms then
        ANN.AddDiagnostic(diagnostics, 'error', '$.alarms',
            'alarm count exceeds ' .. ANN.MaxAlarms, origin)
    end
    if not next(compiled.groups) then ANN.AddDiagnostic(diagnostics, 'error', '$.groups', 'at least one group is required', origin) end
    if not next(compiled.alarms) then ANN.AddDiagnostic(diagnostics, 'error', '$.alarms', 'at least one alarm is required', origin) end
    return ANN.HasErrors(diagnostics) and nil or compiled, diagnostics
end
