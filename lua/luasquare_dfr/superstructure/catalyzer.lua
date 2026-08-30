DFR = DFR or {}
DFR.Catalyzers = DFR.Catalyzers or {}

-- Reactor Darkfusion Catalyzers
-- These are cannons that transfer darkfusion fuel into the actual reactor core.
-- Closely work with attached fuel receptacle.
-- Many catalyzers can use same one receptacle.
-- In Active Fuel Cycle, the most-ready (Least system heat then longest time since last fire) catalyzer will fire on set interval
-- Catalyzer deliver large gulp of fuel point into the core per seconds in a short fire time until it cease.
-- In Passive Fuel Cycle, all intact catalyzers fire fuel into the core at lower intensity than Active although with less final resource efficiency and slightly worse wear and tear.
-- All Catalyzers will each delivers set constant fuel point into the core

-- When catalyzer is transferring fuel into the core, it will take away available yield in the fuel cell of the receptacle until none is left or until condition of the cell is failed.
-- Yield gives fuel point to the core.
-- Catalyzer also read other attributes of the fuel. and systematically transmit that data to the core for further physics calculation.

local Catalyzer = {}
Catalyzer.__index = Catalyzer

local PREFIXES = {
    [1] = 'CZ1_',
    [2] = 'CZ2_',
    [3] = 'CZ3_',
    [4] = 'CZ4_',
    [5] = '',
    [6] = 'CZ6_'
}

local GROUPS = {
    { key = 'catalyzer_hull_beam_high', class = 'env_beam' },
    { key = 'catalyzer_hull_beam_low', class = 'env_beam' },
    { key = 'catalyzer_hull_beamtar_1', class = 'info_target', validationOnly = true },
    { key = 'catalyzer_hull_beamtar_2', class = 'info_target', validationOnly = true },
    { key = 'catalyzer_hull_explode', class = 'env_explosion', all = true, excluded = true },
    { key = 'catalyzer_hull_light', class = 'light' },
    { key = 'catalyzer_hull_mdl_destructible', class = 'prop_dynamic', all = true, excluded = true },
    { key = 'catalyzer_hull_mdl_inner', class = 'prop_dynamic', all = true },
    { key = 'catalyzer_hull_mdl_platform', class = 'prop_dynamic', validationOnly = true },
    { key = 'catalyzer_hull_mdl_socket', class = 'prop_dynamic', validationOnly = true },
    { key = 'catalyzer_hull_particlesys_dmgexplode', class = 'info_particle_system', excluded = true },
    { key = 'catalyzer_hull_particlesys_dmgfire', class = 'info_particle_system', all = true, excluded = true },
    { key = 'catalyzer_hull_snd_alert', class = 'ambient_generic' },
    { key = 'catalyzer_hull_snd_endfire', class = 'ambient_generic' },
    { key = 'catalyzer_hull_snd_fire', class = 'ambient_generic', all = true },
    { key = 'catalyzer_hull_snd_windup', class = 'ambient_generic', all = true },
    { key = 'catalyzer_hull_sprite', class = 'env_sprite', all = true },
    { key = 'catalyzer_hull_sprite_indicator', class = 'env_sprite', all = true },
    { key = 'catalyzer_tip_beam_dark', class = 'env_beam', reserved = true },
    { key = 'catalyzer_tip_beam_light', class = 'env_beam' },
    { key = 'catalyzer_tip_beamtar_1', class = 'info_target', validationOnly = true },
    { key = 'catalyzer_tip_mdl', class = 'prop_dynamic' },
    { key = 'catalyzer_tip_mdl_impact', class = 'prop_dynamic' },
    { key = 'catalyzer_tip_mdl_len', class = 'prop_dynamic', all = true },
    { key = 'catalyzer_tip_rot_1', class = 'func_rotating' },
    { key = 'catalyzer_tip_rot_2', class = 'func_rotating' },
    { key = 'catalyzer_tip_shake', class = 'env_shake' },
    { key = 'catalyzer_tip_snd_charge', class = 'ambient_generic', all = true },
    { key = 'catalyzer_tip_snd_end', class = 'ambient_generic' },
    { key = 'catalyzer_tip_snd_shoot', class = 'ambient_generic' },
    { key = 'catalyzer_tip_sprite', class = 'env_sprite', all = true },
    { key = 'catalyzer_tip_sprite_impact', class = 'env_sprite' }
}

DFR.CatalyzerPrefixes = PREFIXES
DFR.CatalyzerGroups = GROUPS
DFR.CatalyzerTimelineNames = {
    annihilationFire = 'annihilation_fire',
    darkFusionCatalysis = 'dark_fusion_catalysis',
    activeFuelCycleFire = 'active_fuel_cycle_fire',
    passiveFuelCycleInitialFire = 'passive_fuel_cycle_initial_fire'
}
local BOOTSTRAP_RESET_TIMER = 'LUASQUARE_DFR_CatalyzerBootstrapReset'

local function bindingId(unit, key)
    return 'catalyzer_' .. tostring(unit.id) .. '_' .. key
end

local function fire(unit, key, inputName, value)
    local id = unit.bindings[key]
    if not id then return false end
    local group = unit.groups[key]
    if group and group.all then return DFR.FireBindingAll(id, inputName, value) end
    return DFR.FireBinding(id, inputName, value)
end

local function setEffects(unit, keys, active)
    for _, key in ipairs(keys) do
        local group = unit.groups[key]
        if group and not group.excluded and not group.reserved then
            local inputName = active and 'TurnOn' or 'TurnOff'
            if group.class == 'env_sprite' then inputName = active and 'ShowSprite' or 'HideSprite' end
            fire(unit, key, inputName)
        end
    end
end

local function setRotators(unit, active)
    for _, key in ipairs({'catalyzer_tip_rot_1', 'catalyzer_tip_rot_2'}) do
        fire(unit, key, active and 'Start' or 'Stop')
    end
end

local function sound(unit, key, active)
    fire(unit, key, active and 'PlaySound' or 'StopSound')
end

local function stopAllAudio(unit)
    for _, key in ipairs({
        'catalyzer_hull_snd_alert',
        'catalyzer_hull_snd_endfire',
        'catalyzer_hull_snd_fire',
        'catalyzer_hull_snd_windup',
        'catalyzer_tip_snd_charge',
        'catalyzer_tip_snd_end',
        'catalyzer_tip_snd_shoot'
    }) do
        sound(unit, key, false)
    end
end

local CHARGE_EFFECTS = {
    'catalyzer_hull_beam_low',
    'catalyzer_hull_light',
    'catalyzer_hull_sprite',
    'catalyzer_hull_sprite_indicator'
}

local HIGH_EFFECTS = {'catalyzer_hull_beam_high'}
local FIRE_EFFECTS = {
    'catalyzer_tip_beam_light',
    'catalyzer_tip_sprite',
    'catalyzer_tip_sprite_impact'
}

function DFR.GetCatalyzer(id)
    return DFR.Catalyzers[tonumber(id)]
end

local CATALYZER_TIMELINE_ROOT = 'data_static/luasquare/timeline/_components/dfr.catalyzer/'

local function registerGroupComponent(unit, group)
    local componentId = 'catalyzer:' .. unit.id .. ':' .. group.key
    local actions = {}
    local enableInput, disableInput
    if not group.excluded and not group.validationOnly and not group.reserved then
        if group.class == 'env_sprite' then
            enableInput, disableInput = 'ShowSprite', 'HideSprite'
        elseif group.class == 'env_beam' or group.class == 'light' then
            enableInput, disableInput = 'TurnOn', 'TurnOff'
        elseif group.class == 'func_rotating' then
            enableInput, disableInput = 'Start', 'Stop'
        elseif group.class == 'ambient_generic' then
            enableInput, disableInput = 'PlaySound', 'StopSound'
        elseif group.class == 'env_shake' then
            enableInput, disableInput = 'StartShake', 'StopShake'
        elseif group.key == 'catalyzer_tip_mdl_impact' then
            enableInput, disableInput = 'Enable', 'Disable'
        end
    end
    if enableInput then
        actions.enabled = {
            kind = 'duration', label = 'Enabled for duration', seekPolicy = 'reject',
            start = function() return fire(unit, group.key, enableInput) end,
            finish = function() return fire(unit, group.key, disableInput) end,
            cancel = function() return fire(unit, group.key, disableInput) end
        }
        actions.enable = {
            kind = 'marker', label = enableInput, seekPolicy = 'reject',
            execute = function() return fire(unit, group.key, enableInput) end
        }
        actions.disable = {
            kind = 'marker', label = disableInput, seekPolicy = 'apply',
            execute = function() return fire(unit, group.key, disableInput) end
        }
    end
    DFR.RegisterTimelineComponent(componentId, {
        type = 'dfr.catalyzer.' .. tostring(group.class or 'binding'),
        label = 'Catalyzer ' .. unit.id .. ' / ' .. group.key,
        parent = 'catalyzer:' .. unit.id,
        context = {unit = unit, group = group},
        actions = actions,
        notes = group.excluded and 'Excluded from normal operation'
            or (group.reserved and 'Reserved for future behavior'
            or (group.validationOnly and 'Validation only' or nil)),
        safeReset = disableInput and function() return fire(unit, group.key, disableInput) end or nil
    })
    return componentId
end

function Catalyzer:RegisterTimelines(options)
    options = options or {}
    local ownerId = 'catalyzer:' .. tostring(self.id)
    local children = {}
    for _, group in ipairs(GROUPS) do children[group.key] = registerGroupComponent(self, group) end
    DFR.RegisterTimelineComponent(ownerId, {
        type = 'dfr.catalyzer',
        label = 'Catalyzer ' .. tostring(self.id),
        children = children,
        context = self,
        actions = {
            set_mode = {
                kind = 'marker', label = 'Set logical mode', seekPolicy = 'reject',
                parameters = {{
                    id = 'mode', label = 'Mode', type = 'enum', default = 'OFFLINE',
                    choices = {'OFFLINE', 'CHARGING_LOW', 'CHARGING_HIGH', 'FIRING', 'CHARGED'}
                }},
                execute = function(_, params)
                    local mode = string.upper(tostring(params.mode or ''))
                    if mode == 'FIRING' and not DFR.IsCatalyzerAvailable(self.id) then return false end
                    return DFR.SetCatalyzerMode(self.id, mode)
                end
            }
        },
        safeReset = function() return DFR.SetCatalyzerMode(self.id, 'OFFLINE') end
    })
    LUASQUARE_TIMELINE.RegisterLifecycleHandler('dfr.catalyzer.cancel', function(_, run)
        local component = run and LUASQUARE_TIMELINE.Components[run.ownerId]
        local unit = component and component.context
        return unit and DFR.SetCatalyzerMode(unit.id, 'OFFLINE') or false
    end)
    self.timelineOwner = DFR.GetTimelineOwner(ownerId)
    local source = options.annihilation_fire or options.annihilationFire
        or (CATALYZER_TIMELINE_ROOT .. 'annihilation_fire.json')
    return DFR.BindComponentTimeline(ownerId, 'annihilation_fire', source)
end

function Catalyzer:StartTimeline(name, context, runOptions)
    if not self.timelineOwner then return false end
    return self.timelineOwner:Start(name, context, runOptions)
end

function Catalyzer:CancelTimeline(name, reason)
    return self.timelineOwner and self.timelineOwner:Cancel(name, reason) or false
end

function Catalyzer:CancelAllTimelines(reason)
    return self.timelineOwner and self.timelineOwner:CancelAll(reason) or false
end

function Catalyzer:IsTimelineActive(name)
    return self.timelineOwner and self.timelineOwner:IsActive(name) or false
end

function Catalyzer:GetTimelineSnapshot()
    return self.timelineOwner and self.timelineOwner:GetSnapshot()
        or { ownerId = 'catalyzer:' .. tostring(self.id), definitions = {}, runs = {} }
end

function DFR.StartCatalyzerTimeline(id, name, context, runOptions)
    local unit = DFR.GetCatalyzer(id)
    return unit and unit:StartTimeline(name, context, runOptions) or false
end

function DFR.CancelCatalyzerTimeline(id, name, reason)
    local unit = DFR.GetCatalyzer(id)
    return unit and unit:CancelTimeline(name, reason) or false
end

function DFR.GetCatalyzerTimelineSnapshot(id)
    local unit = DFR.GetCatalyzer(id)
    return unit and unit:GetTimelineSnapshot() or nil
end

function DFR.IsCatalyzerAvailable(id)
    local unit = DFR.GetCatalyzer(id)
    if not unit then return false end
    return #DFR.ResolveBindingAll(unit.bindings.catalyzer_tip_beam_light) > 0
end

function DFR.SetCatalyzerMode(id, mode)
    local unit = DFR.GetCatalyzer(id)
    if not unit then return false end
    mode = string.upper(tostring(mode or ''))

    if mode == 'OFFLINE' then
        setEffects(unit, CHARGE_EFFECTS, false)
        setEffects(unit, HIGH_EFFECTS, false)
        setEffects(unit, FIRE_EFFECTS, false)
        fire(unit, 'catalyzer_tip_shake', 'StopShake')
        fire(unit, 'catalyzer_tip_beam_dark', 'TurnOff')
        setRotators(unit, false)
        fire(unit, 'catalyzer_tip_mdl_impact', 'Disable')
        stopAllAudio(unit)
    elseif mode == 'CHARGING_LOW' then
        fire(unit, 'catalyzer_tip_beam_dark', 'TurnOff')
        setEffects(unit, CHARGE_EFFECTS, true)
        setEffects(unit, HIGH_EFFECTS, false)
        setEffects(unit, FIRE_EFFECTS, false)
        setRotators(unit, false)
        sound(unit, 'catalyzer_hull_snd_alert', true)
        sound(unit, 'catalyzer_hull_snd_windup', true)
        sound(unit, 'catalyzer_tip_snd_charge', true)
    elseif mode == 'CHARGING_HIGH' then
        setEffects(unit, CHARGE_EFFECTS, true)
        setEffects(unit, HIGH_EFFECTS, true)
        setEffects(unit, FIRE_EFFECTS, false)
        setRotators(unit, true)
    elseif mode == 'FIRING' then
        setEffects(unit, CHARGE_EFFECTS, true)
        setEffects(unit, HIGH_EFFECTS, true)
        setEffects(unit, FIRE_EFFECTS, true)
        fire(unit, 'catalyzer_tip_mdl_impact', 'Enable')
        fire(unit, 'catalyzer_tip_shake', 'StartShake')
        sound(unit, 'catalyzer_hull_snd_fire', true)
        sound(unit, 'catalyzer_tip_snd_shoot', true)
    elseif mode == 'CHARGED' then
        setEffects(unit, FIRE_EFFECTS, false)
        fire(unit, 'catalyzer_tip_mdl_impact', 'Disable')
        fire(unit, 'catalyzer_tip_shake', 'StopShake')
        sound(unit, 'catalyzer_hull_snd_fire', false)
        sound(unit, 'catalyzer_tip_snd_shoot', false)
        sound(unit, 'catalyzer_hull_snd_endfire', true)
        sound(unit, 'catalyzer_tip_snd_end', true)
    else
        return false
    end

    unit.mode = mode
    return true
end

function DFR.SetAvailableCatalyzersMode(mode, ids)
    local count = 0
    for _, id in ipairs(ids or {1, 2, 3, 4, 5, 6}) do
        if DFR.IsCatalyzerAvailable(id) and DFR.SetCatalyzerMode(id, mode) then count = count + 1 end
    end
    return count
end

function DFR.ResetCatalyzers()
    for id = 1, 6 do
        local unit = DFR.Catalyzers[id]
        if unit then
            unit:CancelAllTimelines('catalyzer reset')
            DFR.SetCatalyzerMode(id, 'OFFLINE')
        end
    end
    return true
end

function DFR.RegisterDefaultCatalyzers(options)
    options = options or {}
    DFR.Catalyzers = {}

    for id = 1, 6 do
        local prefix = options.prefixes and options.prefixes[id] or PREFIXES[id]
        local unit = setmetatable({
            id = id,
            prefix = prefix,
            mode = 'OFFLINE',
            bindings = {},
            groups = {}
        }, Catalyzer)

        DFR.Catalyzers[id] = unit
        for _, group in ipairs(GROUPS) do
            local registryId = bindingId(unit, group.key)
            unit.bindings[group.key] = registryId
            unit.groups[group.key] = group
            DFR.RegisterBinding(registryId, {
                targetName = prefix .. group.key,
                class = group.class,
                required = false,
                all = group.all and true or false,
                notes = group.excluded and 'Excluded from normal operation'
                    or (group.reserved and 'Reserved for dark-fusion behavior'
                    or (group.validationOnly and 'Validation only' or 'Catalyzer operational group'))
            })
        end
        local sharedTimelines = options.timelineSources or options.timelines or {}
        local unitTimelines = options.unitTimelineSources and options.unitTimelineSources[id] or {}
        local selectedTimelines = {}
        for name, path in pairs(sharedTimelines) do selectedTimelines[name] = path end
        for name, path in pairs(unitTimelines) do selectedTimelines[name] = path end
        unit:RegisterTimelines(selectedTimelines)
    end

    DFR.RegisterBinding('allcatalyzers_tip_beam_target', {
        targetName = 'allcatalyzers_tip_beam_target',
        class = 'info_target',
        required = false,
        notes = 'Shared endpoint; validation only'
    })

    DFR.ResetCatalyzers()
    if timer and timer.Create then
        if timer.Exists(BOOTSTRAP_RESET_TIMER) then timer.Remove(BOOTSTRAP_RESET_TIMER) end
        timer.Create(BOOTSTRAP_RESET_TIMER, 0.25, 1, function()
            if DFR and DFR.ResetCatalyzers then DFR.ResetCatalyzers() end
        end)
    end
    DFR.Log('Registered six DFR catalyzers (unit 5 is intentionally unprefixed)')
    return true
end

function DFR.GetCatalyzerSnapshot()
    local snapshot = {}
    for id = 1, 6 do
        local unit = DFR.Catalyzers[id]
        if unit then
            local found = {}
            local missing = {}
            local entityCount = 0
            for _, group in ipairs(GROUPS) do
                local count = #DFR.ResolveBindingAll(unit.bindings[group.key])
                entityCount = entityCount + count
                if count > 0 then
                    found[group.key] = count
                else
                    table.insert(missing, group.key)
                end
            end
            snapshot[id] = {
                id = id,
                prefix = unit.prefix,
                mode = unit.mode,
                available = (found.catalyzer_tip_beam_light or 0) > 0,
                logicalGroupCount = #GROUPS,
                entityCount = entityCount,
                found = found,
                missing = missing,
                timeline = unit:GetTimelineSnapshot()
            }
        end
    end
    return snapshot
end
