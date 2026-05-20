if LUASQUARE_ANNUNCIATOR_CORE_LOADED then return end
LUASQUARE_ANNUNCIATOR_CORE_LOADED = true
-- Alarm lifecycle: off -> fast_flash, ACK -> on, clear -> slow_flash, RESET -> off.
LUASQUARE_ANNUNCIATOR = LUASQUARE_ANNUNCIATOR or {}
LUASQUARE_ANNUNCIATOR.Alarms = LUASQUARE_ANNUNCIATOR.Alarms or {}
LUASQUARE_ANNUNCIATOR.Bindings = LUASQUARE_ANNUNCIATOR.Bindings or {}
LUASQUARE_ANNUNCIATOR.PropDisplays = LUASQUARE_ANNUNCIATOR.PropDisplays or {}
LUASQUARE_ANNUNCIATOR.EntityCache = LUASQUARE_ANNUNCIATOR.EntityCache or {}
LUASQUARE_ANNUNCIATOR.MissingEntities = LUASQUARE_ANNUNCIATOR.MissingEntities or {}

LUASQUARE_ANNUNCIATOR.TickInterval = LUASQUARE_ANNUNCIATOR.TickInterval or 0.1
LUASQUARE_ANNUNCIATOR.DefaultMuteDuration = LUASQUARE_ANNUNCIATOR.DefaultMuteDuration or 60
LUASQUARE_ANNUNCIATOR.DefaultReAlarmDelay = LUASQUARE_ANNUNCIATOR.DefaultReAlarmDelay or 180
LUASQUARE_ANNUNCIATOR.UnmuteCueLeadTime = LUASQUARE_ANNUNCIATOR.UnmuteCueLeadTime or 1
LUASQUARE_ANNUNCIATOR.UnmuteCueSound = LUASQUARE_ANNUNCIATOR.UnmuteCueSound or nil
LUASQUARE_ANNUNCIATOR.UnmuteCueDistance = LUASQUARE_ANNUNCIATOR.UnmuteCueDistance or 75
LUASQUARE_ANNUNCIATOR.UnmuteCueVolume = LUASQUARE_ANNUNCIATOR.UnmuteCueVolume or 1
LUASQUARE_ANNUNCIATOR.UnmuteCuePitch = LUASQUARE_ANNUNCIATOR.UnmuteCuePitch or 100
LUASQUARE_ANNUNCIATOR.CorePos = LUASQUARE_ANNUNCIATOR.CorePos or nil
LUASQUARE_ANNUNCIATOR.MutedUntil = LUASQUARE_ANNUNCIATOR.MutedUntil or 0
LUASQUARE_ANNUNCIATOR.WasMuted = LUASQUARE_ANNUNCIATOR.WasMuted or false
LUASQUARE_ANNUNCIATOR.MuteCuePlayed = LUASQUARE_ANNUNCIATOR.MuteCuePlayed or false

LUASQUARE_ANNUNCIATOR.STATE_OFF = 'off'
LUASQUARE_ANNUNCIATOR.STATE_FAST_FLASH = 'fast_flash'
LUASQUARE_ANNUNCIATOR.STATE_ON = 'on'
LUASQUARE_ANNUNCIATOR.STATE_SLOW_FLASH = 'slow_flash'

local defaultSkins = {
    off = 0,
    fast_flash = 1,
    on = 2,
    slow_flash = 3
}

local function getTime()
    if CurTime then return CurTime() end
    return os.clock()
end

local function normalizeEntities(data)
    local entities = {}
    if isstring(data) then return {data} end
    if data.entity then table.insert(entities, data.entity) end

    if istable(data.entities) then
        for _, entityName in ipairs(data.entities) do
            table.insert(entities, entityName)
        end
    end

    return entities
end

local function copySkins(skins)
    local out = {}
    for state, skin in pairs(defaultSkins) do
        out[state] = skin
    end

    if istable(skins) then
        for state, skin in pairs(skins) do
            out[state] = tonumber(skin) or out[state]
        end
    end

    return out
end

local function hasEntity(entities, entityName)
    for _, existing in ipairs(entities) do
        if existing == entityName then return true end
    end

    return false
end

local function appendEntities(target, source)
    if isstring(source) then
        if not hasEntity(target, source) then table.insert(target, source) end
    elseif istable(source) then
        if source.entity or source.entities then
            for _, entityName in ipairs(normalizeEntities(source)) do
                if not hasEntity(target, entityName) then table.insert(target, entityName) end
            end
        else
            for _, entityName in ipairs(source) do
                if not hasEntity(target, entityName) then table.insert(target, entityName) end
            end
        end
    end
end

-- =========================================
-- ENTITY CACHE
-- =========================================
function LUASQUARE_ANNUNCIATOR.GetEnt(name)
    if not name then return nil end
    local cached = LUASQUARE_ANNUNCIATOR.EntityCache[name]
    if IsValid(cached) then return cached end
    local ent = ents.FindByName(name)[1]
    if IsValid(ent) then LUASQUARE_ANNUNCIATOR.EntityCache[name] = ent end
    return ent
end

function LUASQUARE_ANNUNCIATOR.FireTarget(name, input, value)
    local ent = LUASQUARE_ANNUNCIATOR.GetEnt(name)
    if not IsValid(ent) then
        if not LUASQUARE_ANNUNCIATOR.MissingEntities[name] then
            LUASQUARE_ANNUNCIATOR.MissingEntities[name] = true
            print('[LUASQUARE_ANNUNCIATOR] Missing entity: ' .. tostring(name))
        end
        return false
    end

    ent:Fire(input, value)
    return true
end

function LUASQUARE_ANNUNCIATOR.SetCorePosition(pos)
    LUASQUARE_ANNUNCIATOR.CorePos = pos
end

function LUASQUARE_ANNUNCIATOR.SetUnmuteCue(soundName, distance, volume, pitch)
    LUASQUARE_ANNUNCIATOR.UnmuteCueSound = soundName
    if distance ~= nil then LUASQUARE_ANNUNCIATOR.UnmuteCueDistance = tonumber(distance) or LUASQUARE_ANNUNCIATOR.UnmuteCueDistance end
    if volume ~= nil then LUASQUARE_ANNUNCIATOR.UnmuteCueVolume = tonumber(volume) or LUASQUARE_ANNUNCIATOR.UnmuteCueVolume end
    if pitch ~= nil then LUASQUARE_ANNUNCIATOR.UnmuteCuePitch = tonumber(pitch) or LUASQUARE_ANNUNCIATOR.UnmuteCuePitch end
end

function LUASQUARE_ANNUNCIATOR.PlayCoreSound(soundName, distance, volume, pitch)
    if not soundName then return false end
    local pos = LUASQUARE_ANNUNCIATOR.CorePos
    if not pos then
        if not LUASQUARE_ANNUNCIATOR.MissingCoreSoundOrigin then
            LUASQUARE_ANNUNCIATOR.MissingCoreSoundOrigin = true
            print('[LUASQUARE_ANNUNCIATOR] Missing core position for sound: ' .. tostring(soundName))
        end
        return false
    end

    sound.Play(soundName, pos, tonumber(distance) or LUASQUARE_ANNUNCIATOR.UnmuteCueDistance, tonumber(pitch) or LUASQUARE_ANNUNCIATOR.UnmuteCuePitch, tonumber(volume) or LUASQUARE_ANNUNCIATOR.UnmuteCueVolume)
    return true
end

function LUASQUARE_ANNUNCIATOR.ApplyPropDisplaysToAlarm(name)
    local alarm = LUASQUARE_ANNUNCIATOR.Alarms[name]
    if not alarm then return end

    for _, display in pairs(LUASQUARE_ANNUNCIATOR.PropDisplays) do
        local indicator = display.indicators[name]
        if indicator then
            appendEntities(alarm.entities, indicator)
            if display.skins then alarm.skins = copySkins(display.skins) end
        end
    end
end

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_ANNUNCIATOR.RegisterAlarm(name, data)
    data = data or {}
    if not name then
        print('[LUASQUARE_ANNUNCIATOR] Missing alarm name')
        return
    end

    LUASQUARE_ANNUNCIATOR.Bindings[name] = nil
    LUASQUARE_ANNUNCIATOR.Alarms[name] = {
        name = name,
        label = data.label or name,
        group = data.group,
        priority = tonumber(data.priority) or 0,
        active = data.active and true or false,
        acknowledged = data.acknowledged and true or false,
        resolved = false,
        state = LUASQUARE_ANNUNCIATOR.STATE_OFF,
        entities = normalizeEntities(data),
        skins = copySkins(data.skins),
        sound = data.sound or data.soundWav or data.soundFile,
        soundEntity = data.soundEntity,
        soundLevel = tonumber(data.soundDistance or data.distance or data.soundLevel) or 75,
        soundPitch = tonumber(data.soundPitch or data.pitch) or 100,
        soundVolume = tonumber(data.soundVolume or data.volume) or 1,
        soundPos = data.soundPos or data.pos,
        useCoreSoundOrigin = (data.useCoreSoundOrigin or data.soundFromCore or data.coreSound) and true or false,
        ackStopsSound = data.ackStopsSound ~= false,
        reAlarmDelay = tonumber(data.reAlarmDelay) or LUASQUARE_ANNUNCIATOR.DefaultReAlarmDelay,
        resolvedSound = data.resolvedSound or data.resolvedSoundWav,
        resolvedSoundEntity = data.resolvedSoundEntity,
        onTrip = data.onTrip,
        onClear = data.onClear,
        onStateChanged = data.onStateChanged,
        getter = data.getter or data.condition,
        message = data.message,
        acknowledgedTime = nil,
        testActive = false
    }

    if LUASQUARE_ANNUNCIATOR.Alarms[name].getter then
        LUASQUARE_ANNUNCIATOR.Bindings[name] = LUASQUARE_ANNUNCIATOR.Alarms[name].getter
    end

    LUASQUARE_ANNUNCIATOR.ApplyPropDisplaysToAlarm(name)
    LUASQUARE_ANNUNCIATOR.RefreshAlarmState(name)
end

function LUASQUARE_ANNUNCIATOR.RegisterPropDisplay(name, data)
    data = data or {}
    local indicators = data.indicators or {}
    LUASQUARE_ANNUNCIATOR.PropDisplays[name] = {
        name = name,
        indicators = indicators,
        skins = data.skins
    }

    for alarmName, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        local indicator = indicators[alarmName]
        if indicator then
            appendEntities(alarm.entities, indicator)
            if data.skins then alarm.skins = copySkins(data.skins) end
            alarm.lastRenderedState = nil
            LUASQUARE_ANNUNCIATOR.RefreshAlarmState(alarmName)
        end
    end
end

function LUASQUARE_ANNUNCIATOR.BindAlarm(name, getter)
    local alarm = LUASQUARE_ANNUNCIATOR.Alarms[name]
    if not alarm then
        print('[LUASQUARE_ANNUNCIATOR] Unknown alarm: ' .. tostring(name))
        return
    end

    alarm.getter = getter
    LUASQUARE_ANNUNCIATOR.Bindings[name] = getter
end

function LUASQUARE_ANNUNCIATOR.RegisterProp(name, entityName)
    local alarm = LUASQUARE_ANNUNCIATOR.Alarms[name]
    if not alarm then
        print('[LUASQUARE_ANNUNCIATOR] Unknown alarm: ' .. tostring(name))
        return
    end

    table.insert(alarm.entities, entityName)
    alarm.lastRenderedState = nil
    LUASQUARE_ANNUNCIATOR.RefreshAlarmState(name)
end

-- =========================================
-- STATE
-- =========================================
function LUASQUARE_ANNUNCIATOR.GetDisplayState(alarm)
    if alarm.testActive then return LUASQUARE_ANNUNCIATOR.STATE_FAST_FLASH end

    if alarm.active then
        if alarm.acknowledged then return LUASQUARE_ANNUNCIATOR.STATE_ON end
        return LUASQUARE_ANNUNCIATOR.STATE_FAST_FLASH
    end

    if alarm.resolved then return LUASQUARE_ANNUNCIATOR.STATE_SLOW_FLASH end
    return LUASQUARE_ANNUNCIATOR.STATE_OFF
end

function LUASQUARE_ANNUNCIATOR.SetPropState(alarm, state)
    local skin = alarm.skins[state]
    if skin == nil then return end

    for _, entityName in ipairs(alarm.entities or {}) do
        local ent = LUASQUARE_ANNUNCIATOR.GetEnt(entityName)
        if IsValid(ent) then
            ent:SetSkin(skin)
        elseif not alarm.missingEntities or not alarm.missingEntities[entityName] then
            alarm.missingEntities = alarm.missingEntities or {}
            alarm.missingEntities[entityName] = true
            print('[LUASQUARE_ANNUNCIATOR] Missing indicator entity: ' .. tostring(entityName))
        end
    end
end

function LUASQUARE_ANNUNCIATOR.PlaySound(alarm, soundName, soundEntity)
    if not soundName and not soundEntity then return false end

    if soundEntity then
        return LUASQUARE_ANNUNCIATOR.FireTarget(soundEntity, 'PlaySound')
    end

    if alarm.useCoreSoundOrigin then
        return LUASQUARE_ANNUNCIATOR.PlayCoreSound(soundName, alarm.soundLevel, alarm.soundVolume, alarm.soundPitch)
    end

    local emitter
    for _, entityName in ipairs(alarm.entities or {}) do
        emitter = LUASQUARE_ANNUNCIATOR.GetEnt(entityName)
        if IsValid(emitter) then break end
    end

    if IsValid(emitter) then
        emitter:EmitSound(soundName, alarm.soundLevel, alarm.soundPitch, alarm.soundVolume)
        return true
    end

    if alarm.soundPos then
        sound.Play(soundName, alarm.soundPos, alarm.soundLevel, alarm.soundPitch, alarm.soundVolume)
        return true
    end

    if not alarm.missingSoundOrigin then
        alarm.missingSoundOrigin = true
        print('[LUASQUARE_ANNUNCIATOR] Missing sound origin for alarm: ' .. tostring(alarm.name))
    end
    return false
end

function LUASQUARE_ANNUNCIATOR.StopSound(alarm, soundName, soundEntity)
    if soundEntity then
        LUASQUARE_ANNUNCIATOR.FireTarget(soundEntity, 'StopSound')
        return
    end

    if not soundName then return end
    for _, entityName in ipairs(alarm.entities or {}) do
        local ent = LUASQUARE_ANNUNCIATOR.GetEnt(entityName)
        if IsValid(ent) then ent:StopSound(soundName) end
    end
end

function LUASQUARE_ANNUNCIATOR.IsMuted()
    return getTime() < (LUASQUARE_ANNUNCIATOR.MutedUntil or 0)
end

function LUASQUARE_ANNUNCIATOR.ShouldSoundAlarm(alarm)
    if not alarm.active and not alarm.testActive then return false end
    if LUASQUARE_ANNUNCIATOR.IsMuted() then return false end
    if alarm.testActive then return true end
    if alarm.acknowledged and alarm.ackStopsSound then return false end
    return true
end

function LUASQUARE_ANNUNCIATOR.WillSoundAfterMute(alarm)
    if not alarm.active and not alarm.testActive then return false end
    if not alarm.sound and not alarm.soundEntity then return false end
    if alarm.testActive then return true end
    if alarm.acknowledged and alarm.ackStopsSound then return false end
    return true
end

function LUASQUARE_ANNUNCIATOR.UpdateAlarmSound(alarm)
    local shouldSound = LUASQUARE_ANNUNCIATOR.ShouldSoundAlarm(alarm)
    if shouldSound and not alarm.soundPlaying then
        alarm.soundPlaying = LUASQUARE_ANNUNCIATOR.PlaySound(alarm, alarm.sound, alarm.soundEntity)
    elseif not shouldSound and alarm.soundPlaying then
        LUASQUARE_ANNUNCIATOR.StopSound(alarm, alarm.sound, alarm.soundEntity)
        alarm.soundPlaying = false
    end
end

function LUASQUARE_ANNUNCIATOR.RefreshAlarmState(name)
    local alarm = LUASQUARE_ANNUNCIATOR.Alarms[name]
    if not alarm then return end

    local state = LUASQUARE_ANNUNCIATOR.GetDisplayState(alarm)
    if alarm.lastRenderedState ~= state then
        LUASQUARE_ANNUNCIATOR.SetPropState(alarm, state)
        if alarm.onStateChanged then
            local ok, err = pcall(alarm.onStateChanged, alarm, state)
            if not ok then print(err) end
        end
        alarm.lastRenderedState = state
    end

    alarm.state = state
    LUASQUARE_ANNUNCIATOR.UpdateAlarmSound(alarm)
end

function LUASQUARE_ANNUNCIATOR.SetAlarm(name, active, message)
    local alarm = LUASQUARE_ANNUNCIATOR.Alarms[name]
    if not alarm then
        print('[LUASQUARE_ANNUNCIATOR] Unknown alarm: ' .. tostring(name))
        return false
    end

    active = active and true or false
    if message ~= nil then alarm.message = message end
    if active == alarm.active then
        LUASQUARE_ANNUNCIATOR.RefreshAlarmState(name)
        return true
    end

    alarm.active = active
    if active then
        alarm.acknowledged = false
        alarm.acknowledgedTime = nil
        alarm.resolved = false
        alarm.tripTime = getTime()
        if alarm.onTrip then
            local ok, err = pcall(alarm.onTrip, alarm)
            if not ok then print(err) end
        end
    else
        alarm.resolved = true
        alarm.clearTime = getTime()
        LUASQUARE_ANNUNCIATOR.StopSound(alarm, alarm.sound, alarm.soundEntity)
        alarm.soundPlaying = false
        LUASQUARE_ANNUNCIATOR.PlaySound(alarm, alarm.resolvedSound, alarm.resolvedSoundEntity)
        if alarm.onClear then
            local ok, err = pcall(alarm.onClear, alarm)
            if not ok then print(err) end
        end
    end

    LUASQUARE_ANNUNCIATOR.RefreshAlarmState(name)
    return true
end

function LUASQUARE_ANNUNCIATOR.GetAlarm(name)
    return LUASQUARE_ANNUNCIATOR.Alarms[name]
end

function LUASQUARE_ANNUNCIATOR.GetActiveCount()
    local count = 0
    for _, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        if alarm.active or alarm.testActive then count = count + 1 end
    end
    return count
end

function LUASQUARE_ANNUNCIATOR.GetUnacknowledgedCount()
    local count = 0
    for _, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        if (alarm.active or alarm.testActive) and not alarm.acknowledged then count = count + 1 end
    end
    return count
end

function LUASQUARE_ANNUNCIATOR.GetState()
    local state = {}
    for name, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        state[name] = {
            name = name,
            label = alarm.label,
            group = alarm.group,
            priority = alarm.priority,
            active = alarm.active,
            testActive = alarm.testActive,
            acknowledged = alarm.acknowledged,
            resolved = alarm.resolved,
            state = alarm.state,
            message = alarm.message
        }
    end

    return state
end

-- =========================================
-- OPERATOR INPUTS
-- =========================================
function LUASQUARE_ANNUNCIATOR.Acknowledge()
    for name, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        if alarm.testActive then
            alarm.testActive = false
            if alarm.active then
                alarm.acknowledged = true
                alarm.acknowledgedTime = getTime()
            else
                LUASQUARE_ANNUNCIATOR.StopSound(alarm, alarm.sound, alarm.soundEntity)
                alarm.soundPlaying = false
            end
        elseif alarm.active then
            alarm.acknowledged = true
            alarm.acknowledgedTime = getTime()
        end
        LUASQUARE_ANNUNCIATOR.RefreshAlarmState(name)
    end
end

LUASQUARE_ANNUNCIATOR.Ack = LUASQUARE_ANNUNCIATOR.Acknowledge

function LUASQUARE_ANNUNCIATOR.Reset()
    for name, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        if alarm.resolved and not alarm.active then
            alarm.resolved = false
            alarm.acknowledged = false
        end
        LUASQUARE_ANNUNCIATOR.RefreshAlarmState(name)
    end
end

function LUASQUARE_ANNUNCIATOR.Mute(duration)
    duration = tonumber(duration) or LUASQUARE_ANNUNCIATOR.DefaultMuteDuration
    LUASQUARE_ANNUNCIATOR.MutedUntil = getTime() + math.max(duration, 0)
    LUASQUARE_ANNUNCIATOR.MuteCuePlayed = false

    for name, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        LUASQUARE_ANNUNCIATOR.StopSound(alarm, alarm.sound, alarm.soundEntity)
        alarm.soundPlaying = false
        LUASQUARE_ANNUNCIATOR.RefreshAlarmState(name)
    end
end

function LUASQUARE_ANNUNCIATOR.TestAll()
    LUASQUARE_ANNUNCIATOR.MutedUntil = 0
    LUASQUARE_ANNUNCIATOR.MuteCuePlayed = false
    for name, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        alarm.testActive = true
        alarm.acknowledged = false
        alarm.acknowledgedTime = nil
        LUASQUARE_ANNUNCIATOR.RefreshAlarmState(name)
    end
end

LUASQUARE_ANNUNCIATOR.Test = LUASQUARE_ANNUNCIATOR.TestAll

-- =========================================
-- UPDATE LOOP
-- =========================================
function LUASQUARE_ANNUNCIATOR.UpdateMute()
    local muted = LUASQUARE_ANNUNCIATOR.IsMuted()
    if muted and not LUASQUARE_ANNUNCIATOR.MuteCuePlayed and LUASQUARE_ANNUNCIATOR.UnmuteCueSound then
        local remaining = (LUASQUARE_ANNUNCIATOR.MutedUntil or 0) - getTime()
        if remaining <= LUASQUARE_ANNUNCIATOR.UnmuteCueLeadTime and LUASQUARE_ANNUNCIATOR.HasSoundAfterMute() then
            LUASQUARE_ANNUNCIATOR.PlayCoreSound(
                LUASQUARE_ANNUNCIATOR.UnmuteCueSound,
                LUASQUARE_ANNUNCIATOR.UnmuteCueDistance,
                LUASQUARE_ANNUNCIATOR.UnmuteCueVolume,
                LUASQUARE_ANNUNCIATOR.UnmuteCuePitch
            )
            LUASQUARE_ANNUNCIATOR.MuteCuePlayed = true
        end
    end

    if LUASQUARE_ANNUNCIATOR.WasMuted and not muted and LUASQUARE_ANNUNCIATOR.HasSoundAfterMute() then
        for _, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
            LUASQUARE_ANNUNCIATOR.UpdateAlarmSound(alarm)
        end
        LUASQUARE_ANNUNCIATOR.MuteCuePlayed = false
    end

    LUASQUARE_ANNUNCIATOR.WasMuted = muted
end

function LUASQUARE_ANNUNCIATOR.HasSoundAfterMute()
    for _, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        if LUASQUARE_ANNUNCIATOR.WillSoundAfterMute(alarm) then return true end
    end

    return false
end

function LUASQUARE_ANNUNCIATOR.UpdateReAlarm()
    local now = getTime()
    for name, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        if alarm.active and alarm.acknowledged and alarm.reAlarmDelay and alarm.reAlarmDelay > 0 and
        now >= (alarm.acknowledgedTime or now) + alarm.reAlarmDelay then
            alarm.acknowledged = false
            alarm.acknowledgedTime = nil
            LUASQUARE_ANNUNCIATOR.RefreshAlarmState(name)
        end
    end
end


function LUASQUARE_ANNUNCIATOR.UpdateAll()
    for alarmName, getter in pairs(LUASQUARE_ANNUNCIATOR.Bindings) do
        local ok, active, message = pcall(getter)
        if ok then
            LUASQUARE_ANNUNCIATOR.SetAlarm(alarmName, active, message)
        else
            print('[LUASQUARE_ANNUNCIATOR] Getter failed for ' .. tostring(alarmName))
            print(active)
        end
    end

    LUASQUARE_ANNUNCIATOR.UpdateMute()
    LUASQUARE_ANNUNCIATOR.UpdateReAlarm()
end

function LUASQUARE_ANNUNCIATOR.Start()
    if timer.Exists('LUASQUARE_ANNUNCIATOR_UpdateTimer') then timer.Remove('LUASQUARE_ANNUNCIATOR_UpdateTimer') end
    timer.Create('LUASQUARE_ANNUNCIATOR_UpdateTimer', LUASQUARE_ANNUNCIATOR.TickInterval, 0, function() LUASQUARE_ANNUNCIATOR.UpdateAll() end)
    print('[LUASQUARE_ANNUNCIATOR] Started')
end

function LUASQUARE_ANNUNCIATOR.Stop()
    if timer.Exists('LUASQUARE_ANNUNCIATOR_UpdateTimer') then timer.Remove('LUASQUARE_ANNUNCIATOR_UpdateTimer') end
    for _, alarm in pairs(LUASQUARE_ANNUNCIATOR.Alarms) do
        LUASQUARE_ANNUNCIATOR.StopSound(alarm, alarm.sound, alarm.soundEntity)
        alarm.soundPlaying = false
    end
    print('[LUASQUARE_ANNUNCIATOR] Stopped')
end

print('[LUASQUARE_ANNUNCIATOR] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- include('luasquare_module/annunciator/annunciator.lua')
-- LUASQUARE_ANNUNCIATOR.SetCorePosition(Vector(0, 0, 128))
-- LUASQUARE_ANNUNCIATOR.SetUnmuteCue('buttons/button17.wav', 90, 1, 100)
--
-- LUASQUARE_ANNUNCIATOR.RegisterAlarm('rpv_high_pressure', {
--     label = 'RPV HIGH PRESS',
--     soundWav = 'ambient/alarms/warningbell1.wav',
--     soundDistance = 90,
--     soundVolume = 1,
--     soundPitch = 100,
--     -- useCoreSoundOrigin = true can be used for alarms with no indicator prop.
--     getter = function()
--         return RBMK.RPVPressure > 60
--     end
-- })
-- LUASQUARE_ANNUNCIATOR.RegisterPropDisplay('main_alarm_panel', {
--     indicators = {
--         rpv_high_pressure = 'ann_rpv_high_pressure'
--     }
-- })
--
-- Hammer buttons can call these with lua_run:
-- LUASQUARE_ANNUNCIATOR.Acknowledge()
-- LUASQUARE_ANNUNCIATOR.Mute()
-- LUASQUARE_ANNUNCIATOR.Reset()
-- LUASQUARE_ANNUNCIATOR.TestAll()
--
-- LUASQUARE_ANNUNCIATOR.Start()
