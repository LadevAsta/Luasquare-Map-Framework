DFR = DFR or {}
DFR.CoreVisual = DFR.CoreVisual or {}
DFR.CoreState = DFR.CoreState or {
    sphereRadiusMeters = 0,
    stellarRadiusMeters = 0,
    eventHorizonRadiusMeters = 0,
    shieldRadiusMeters = 0,
    preset = 'offline'
}

local HAMMER_UNIT_METERS = 0.0254
local ANIMATOR_TIMER = 'LUASQUARE_DFR_CoreVisualAnimator'
local BOOTSTRAP_RESET_TIMER = 'LUASQUARE_DFR_CoreVisualBootstrapReset'

local CORE_STATE_FIELDS = {
    core_sphere = 'sphereRadiusMeters',
    core_stellar = 'stellarRadiusMeters',
    core_blackhole = 'eventHorizonRadiusMeters',
    core_shield = 'shieldRadiusMeters'
}

local function clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if math.Clamp then return math.Clamp(value, minValue, maxValue) end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function copyAxes(value)
    value = value or {}
    return {
        x = tonumber(value.x) or 1,
        y = tonumber(value.y) or 1,
        z = tonumber(value.z) or 1
    }
end

local function randomBetween(minValue, maxValue)
    if math.Rand then return math.Rand(minValue, maxValue) end
    return minValue + (maxValue - minValue) * math.random()
end

local function calculateModelScale(visual, radiusMeters)
    radiusMeters = math.max(tonumber(radiusMeters) or 0, 0)
    local unscaledRadiusHammer = tonumber(visual.basisRadiusHammer)
    if unscaledRadiusHammer and unscaledRadiusHammer > 0 then
        return radiusMeters / (unscaledRadiusHammer * HAMMER_UNIT_METERS)
    end

    local basisRadiusMeters = tonumber(visual.basisRadiusMeters)
    if not basisRadiusMeters or basisRadiusMeters <= 0 then return 0 end
    return radiusMeters / basisRadiusMeters * (tonumber(visual.basisScale) or 1)
end

local function registerVisual(id, targetName, data)
    data = data or {}
    local basisRadiusHammer = tonumber(data.basisRadiusHammer)
    if basisRadiusHammer and basisRadiusHammer <= 0 then basisRadiusHammer = nil end
    local basisRadiusMeters = tonumber(data.basisRadiusMeters)
    local basisScale = tonumber(data.basisScale)

    if basisRadiusHammer and basisRadiusMeters and basisRadiusMeters > 0 then
        basisScale = basisRadiusMeters / (basisRadiusHammer * HAMMER_UNIT_METERS)
    else
        if not basisScale or basisScale <= 0 then basisScale = 1 end
        if basisRadiusHammer then basisRadiusMeters = basisRadiusHammer * basisScale * HAMMER_UNIT_METERS end
    end

    local debugData = {}
    for key, value in pairs(data.debug or {}) do debugData[key] = value end
    if (data.kind or 'entity') == 'prop' then
        debugData.radiusMeters = debugData.radiusMeters or { min = 0, max = 50, decimals = 3, unit = 'm' }
        debugData.transitionSeconds = debugData.transitionSeconds or { min = 0, max = 10, decimals = 2, unit = 's' }
        debugData.wobbleAmplitudePercent = debugData.wobbleAmplitudePercent or { min = 0, max = 10, decimals = 2, unit = '%' }
        debugData.wobbleIntervalSeconds = debugData.wobbleIntervalSeconds or { min = 0.1, max = 5, decimals = 2, unit = 's' }
        debugData.pulseAmplitudePercent = debugData.pulseAmplitudePercent or { min = 0, max = 25, decimals = 1, unit = '%' }
    end

    DFR.CoreVisual[id] = {
        id = id,
        label = data.label or id,
        binding = data.binding or id,
        targetName = targetName,
        kind = data.kind or 'entity',
        all = data.all and true or false,
        onInput = data.onInput,
        offInput = data.offInput,
        basisScale = basisScale,
        basisRadiusHammer = basisRadiusHammer,
        basisRadiusMeters = basisRadiusMeters,
        baseRadiusMeters = basisRadiusMeters,
        targetRadiusMeters = basisRadiusMeters,
        currentRadiusMeters = basisRadiusMeters,
        currentRadiusHammer = basisRadiusMeters and basisRadiusMeters / HAMMER_UNIT_METERS or nil,
        currentScaleMultiplier = 1,
        currentModelScale = basisScale,
        targetScaleMultiplier = 1,
        targetModelScale = basisScale,
        commandedAxisFactors = { x = 1, y = 1, z = 1 },
        commandedAxisScales = { x = basisScale, y = basisScale, z = basisScale },
        lastTransitionSeconds = 0,
        lastCommandedEnabled = nil,
        drawEnabled = nil,
        wobble = {
            enabled = data.wobbleEnabled ~= false,
            amplitudePercent = tonumber(data.wobbleAmplitudePercent) or 2,
            minIntervalSeconds = tonumber(data.wobbleMinIntervalSeconds) or 0.8,
            maxIntervalSeconds = tonumber(data.wobbleMaxIntervalSeconds) or 1.4,
            nextAt = 0
        },
        pulse = nil,
        debug = debugData
    }

    DFR.RegisterBinding(data.binding or id, {
        targetName = targetName,
        class = data.class,
        required = data.required and true or false,
        all = data.all and true or false,
        notes = data.notes
    })

    return true
end

local function defaultInputs(visual)
    if visual.kind == 'beam' or visual.kind == 'light' or visual.kind == 'sprite' then
        return 'TurnOn', 'TurnOff'
    end
    return 'Enable', 'Disable'
end

local function fireAxis(visual, axis, modelScale, transitionSeconds)
    local inputName = 'SetScale' .. string.upper(axis)
    local value = string.format('%.8f %.4f', modelScale, transitionSeconds)
    return DFR.SourceBindings:Fire(visual.binding, inputName, value, { all = visual.all })
end

local function commandAxes(visual, factors, transitionSeconds)
    if not visual or visual.kind ~= 'prop' then return false end
    factors = copyAxes(factors)
    transitionSeconds = math.max(tonumber(transitionSeconds) or 0, 0)
    local baseRadius = math.max(tonumber(visual.baseRadiusMeters) or 0, 0)
    local scales = {
        x = calculateModelScale(visual, baseRadius * factors.x),
        y = calculateModelScale(visual, baseRadius * factors.y),
        z = calculateModelScale(visual, baseRadius * factors.z)
    }

    visual.commandedAxisFactors = factors
    visual.commandedAxisScales = scales
    visual.currentModelScale = (scales.x + scales.y + scales.z) / 3
    visual.currentRadiusMeters = baseRadius
    visual.currentRadiusHammer = baseRadius / HAMMER_UNIT_METERS
    visual.currentScaleMultiplier = visual.basisRadiusMeters and visual.basisRadiusMeters > 0
        and baseRadius / visual.basisRadiusMeters or 0
    visual.lastTransitionSeconds = transitionSeconds

    local okX = fireAxis(visual, 'x', scales.x, transitionSeconds)
    local okY = fireAxis(visual, 'y', scales.y, transitionSeconds)
    local okZ = fireAxis(visual, 'z', scales.z, transitionSeconds)
    return okX and okY and okZ
end

function DFR.RegisterCoreVisual(id, targetName, data)
    return registerVisual(id, targetName, data)
end

function DFR.RegisterDefaultCoreVisuals(options)
    options = options or {}

    registerVisual('core_sphere', options.coreSphere or 'dfr_prop_coresphere', {
        label = 'Core Sphere', kind = 'prop', class = 'prop_scalable',
        basisRadiusHammer = options.coreSphereBasisRadiusHammer or 230,
        basisRadiusMeters = options.coreSphereBasisRadiusMeters or 5.842,
        debug = options.coreSphereDebug
    })
    registerVisual('core_stellar', options.coreStellar or 'dfr_prop_corestellar', {
        label = 'Stellar Core', kind = 'prop', class = 'prop_scalable',
        basisRadiusHammer = options.coreStellarBasisRadiusHammer or 64,
        basisRadiusMeters = options.coreStellarBasisRadiusMeters or 5.842,
        debug = options.coreStellarDebug
    })
    registerVisual('core_blackhole', options.coreBlackhole or 'dfr_prop_coreblackhole', {
        label = 'Event Horizon', kind = 'prop', class = 'prop_scalable',
        basisRadiusHammer = options.coreBlackholeBasisRadiusHammer or 100,
        basisRadiusMeters = options.coreBlackholeBasisRadiusMeters or 5.842,
        debug = options.coreBlackholeDebug
    })
    registerVisual('core_shield', options.coreShield or 'dfr_prop_coreshield', {
        label = 'Core Shield', kind = 'prop', class = 'prop_scalable',
        basisRadiusHammer = options.coreShieldBasisRadiusHammer or 700,
        basisRadiusMeters = options.coreShieldBasisRadiusMeters or 5.842,
        debug = options.coreShieldDebug
    })

    registerVisual('beam_director', options.directorBeam or 'beam_core_director', { label = 'Director Beam', kind = 'beam', class = 'env_beam', all = true })
    registerVisual('beam_annihilation', options.annihilationBeam or 'beam_core_annihilation', { label = 'Annihilation Beam', kind = 'beam', class = 'env_beam', all = true })
    registerVisual('beam_darkfusion', options.darkFusionBeam or 'beam_core_darkfusion', { label = 'Dark Fusion Beam', kind = 'beam', class = 'env_beam', all = true })
    registerVisual('beam_unstable', options.unstableBeam or 'beam_core_unstable', { label = 'Unstable Beam', kind = 'beam', class = 'env_beam', all = true })
    registerVisual('beam_catalyze', options.catalyzeBeam or 'beam_core_catalyze', { label = 'Catalyze Beam', kind = 'beam', class = 'env_beam', all = true })
    registerVisual('core_chamber_light', options.coreChamberLight or 'light_corechamber', { label = 'Core Chamber Light', kind = 'light', class = 'light' })

    DFR.StartCoreVisualAnimator()
    DFR.ResetCoreVisuals()
    if timer and timer.Create then
        if timer.Exists(BOOTSTRAP_RESET_TIMER) then timer.Remove(BOOTSTRAP_RESET_TIMER) end
        timer.Create(BOOTSTRAP_RESET_TIMER, 0.25, 1, function()
            if DFR and DFR.ResetCoreVisuals then DFR.ResetCoreVisuals() end
        end)
    end

    DFR.Log('Default DFR core visuals registered')
    return true
end

function DFR.SetCoreVisualDrawEnabled(id, enabled)
    local visual = DFR.CoreVisual[id]
    if not visual then return false end
    enabled = enabled and true or false
    visual.drawEnabled = enabled
    visual.lastCommandedEnabled = enabled
    return DFR.SourceBindings:Fire(visual.binding, enabled and 'EnableDraw' or 'DisableDraw', nil, { all = visual.all })
end

function DFR.SetCoreVisualEnabled(id, enabled)
    local visual = DFR.CoreVisual[id]
    if not visual then
        DFR.Log('Unknown core visual: ' .. tostring(id))
        return false
    end

    if visual.kind == 'prop' then return DFR.SetCoreVisualDrawEnabled(id, enabled) end
    local onInput, offInput = defaultInputs(visual)
    local inputName = enabled and (visual.onInput or onInput) or (visual.offInput or offInput)
    visual.lastCommandedEnabled = enabled and true or false
    return DFR.SourceBindings:Fire(visual.binding, inputName, nil, { all = visual.all })
end

function DFR.SetCoreVisualRadiusMeters(id, radiusMeters, changeTime)
    local visual = DFR.CoreVisual[id]
    radiusMeters = tonumber(radiusMeters)
    if not visual or visual.kind ~= 'prop' or not radiusMeters then
        DFR.Log('Unknown or non-scalable core visual radius target: ' .. tostring(id))
        return false
    end

    radiusMeters = math.max(radiusMeters, 0)
    visual.baseRadiusMeters = radiusMeters
    visual.targetRadiusMeters = radiusMeters
    visual.targetModelScale = calculateModelScale(visual, radiusMeters)
    visual.targetScaleMultiplier = visual.basisRadiusMeters and visual.basisRadiusMeters > 0
        and radiusMeters / visual.basisRadiusMeters or 0

    local stateField = CORE_STATE_FIELDS[id]
    if stateField then DFR.CoreState[stateField] = radiusMeters end
    return commandAxes(visual, visual.commandedAxisFactors, changeTime)
end

function DFR.SetCoreVisualScale(id, scale, changeTime)
    local visual = DFR.CoreVisual[id]
    if not visual then return false end
    local basisRadius = tonumber(visual.basisRadiusMeters)
    if not basisRadius then return false end
    return DFR.SetCoreVisualRadiusMeters(id, basisRadius * (tonumber(scale) or 1), changeTime)
end

function DFR.GetCoreVisualMeasurement(id)
    local visual = DFR.CoreVisual[id]
    if not visual then return nil end
    return {
        multiplier = visual.currentScaleMultiplier,
        modelScale = visual.currentModelScale,
        radiusMeters = visual.baseRadiusMeters,
        radiusHammer = visual.baseRadiusMeters and visual.baseRadiusMeters / HAMMER_UNIT_METERS or nil,
        targetMultiplier = visual.targetScaleMultiplier,
        targetModelScale = visual.targetModelScale,
        targetRadiusMeters = visual.targetRadiusMeters,
        axisFactors = copyAxes(visual.commandedAxisFactors),
        axisScales = copyAxes(visual.commandedAxisScales),
        transitionSeconds = visual.lastTransitionSeconds
    }
end

function DFR.GetCoreVisualRadiusMeters(id)
    local visual = DFR.CoreVisual[id]
    return visual and visual.baseRadiusMeters or nil
end

function DFR.SetCoreVisualWobble(id, enabled, options)
    local visual = DFR.CoreVisual[id]
    if not visual or visual.kind ~= 'prop' then return false end
    options = options or {}
    local wobble = visual.wobble
    wobble.enabled = enabled and true or false
    wobble.amplitudePercent = clamp(options.amplitudePercent or wobble.amplitudePercent, 0, 10)
    wobble.minIntervalSeconds = clamp(options.minIntervalSeconds or wobble.minIntervalSeconds, 0.1, 5)
    wobble.maxIntervalSeconds = clamp(options.maxIntervalSeconds or wobble.maxIntervalSeconds, wobble.minIntervalSeconds, 5)
    wobble.nextAt = 0

    if not wobble.enabled and not visual.pulse then commandAxes(visual, { x = 1, y = 1, z = 1 }, 0.25) end
    return true
end

function DFR.PulseCoreVisual(id, options)
    local visual = DFR.CoreVisual[id]
    if not visual or visual.kind ~= 'prop' or (visual.baseRadiusMeters or 0) <= 0 then return false end
    options = options or {}
    local now = DFR.GetTime()
    local pulse = {
        startedAt = now,
        stage = 1,
        originFactors = copyAxes(visual.commandedAxisFactors),
        amplitudePercent = clamp(options.amplitudePercent or 10, 0, 25),
        undershootPercent = clamp(options.undershootPercent or 3, 0, 15),
        attackSeconds = clamp(options.attackSeconds or 0.20, 0.05, 2),
        undershootSeconds = clamp(options.undershootSeconds or 0.25, 0.05, 2),
        settleSeconds = clamp(options.settleSeconds or 0.45, 0.05, 3)
    }
    visual.pulse = pulse

    local factor = 1 + pulse.amplitudePercent / 100
    commandAxes(visual, {
        x = pulse.originFactors.x * factor,
        y = pulse.originFactors.y * factor,
        z = pulse.originFactors.z * factor
    }, pulse.attackSeconds)
    return true
end

function DFR.CancelCoreVisualPulse(id, settleSeconds)
    local visual = DFR.CoreVisual[id]
    if not visual or visual.kind ~= 'prop' then return false end
    visual.pulse = nil
    visual.wobble.nextAt = DFR.GetTime() + math.max(tonumber(settleSeconds) or 0.25, 0)
    return commandAxes(visual, { x = 1, y = 1, z = 1 }, settleSeconds or 0.25)
end

local function tickPulse(visual, now)
    local pulse = visual.pulse
    if not pulse then return false end
    local elapsed = now - pulse.startedAt

    if pulse.stage == 1 and elapsed >= pulse.attackSeconds then
        pulse.stage = 2
        local factor = 1 - pulse.undershootPercent / 100
        commandAxes(visual, {
            x = pulse.originFactors.x * factor,
            y = pulse.originFactors.y * factor,
            z = pulse.originFactors.z * factor
        }, pulse.undershootSeconds)
    elseif pulse.stage == 2 and elapsed >= pulse.attackSeconds + pulse.undershootSeconds then
        pulse.stage = 3
        commandAxes(visual, { x = 1, y = 1, z = 1 }, pulse.settleSeconds)
    elseif pulse.stage == 3 and elapsed >= pulse.attackSeconds + pulse.undershootSeconds + pulse.settleSeconds then
        visual.pulse = nil
        visual.wobble.nextAt = now
    end

    return true
end

local function tickWobble(visual, now)
    local wobble = visual.wobble
    if not wobble or not wobble.enabled or visual.pulse or (visual.baseRadiusMeters or 0) <= 0 then return end
    if now < (wobble.nextAt or 0) then return end

    local interval = randomBetween(wobble.minIntervalSeconds, wobble.maxIntervalSeconds)
    local amplitude = wobble.amplitudePercent / 100
    local factors = {
        x = 1 + randomBetween(-amplitude, amplitude),
        y = 1 + randomBetween(-amplitude, amplitude),
        z = 1 + randomBetween(-amplitude, amplitude)
    }
    wobble.nextAt = now + interval
    commandAxes(visual, factors, interval)
end

function DFR.TickCoreVisuals()
    local now = DFR.GetTime()
    for _, visual in pairs(DFR.CoreVisual or {}) do
        if type(visual) == 'table' and visual.id and visual.kind == 'prop'
            and not tickPulse(visual, now) then
            tickWobble(visual, now)
        end
    end
end

function DFR.StartCoreVisualAnimator()
    if not timer or not timer.Create then return false end
    if timer.Exists(ANIMATOR_TIMER) then return true end
    timer.Create(ANIMATOR_TIMER, 0.05, 0, function()
        if DFR and DFR.TickCoreVisuals then DFR.TickCoreVisuals() end
    end)
    return true
end

function DFR.SetCoreVisualTargets(targets, transitionSeconds)
    targets = targets or {}
    local values = {
        core_sphere = math.max(tonumber(targets.core_sphere or targets.sphereRadiusMeters or DFR.CoreState.sphereRadiusMeters) or 0, 0),
        core_stellar = math.max(tonumber(targets.core_stellar or targets.stellarRadiusMeters or DFR.CoreState.stellarRadiusMeters) or 0, 0),
        core_blackhole = math.max(tonumber(targets.core_blackhole or targets.eventHorizonRadiusMeters or DFR.CoreState.eventHorizonRadiusMeters) or 0, 0),
        core_shield = math.max(tonumber(targets.core_shield or targets.shieldRadiusMeters or DFR.CoreState.shieldRadiusMeters) or 0, 0)
    }

    if values.core_stellar > 0 and values.core_shield > 0 then
        values.core_shield = math.max(
            values.core_shield,
            values.core_stellar + (DFR.Config.CoreShieldMinimumMarginMeters or 0.5)
        )
    end

    local ok = true
    for id, radius in pairs(values) do
        if DFR.CoreVisual[id] then ok = DFR.SetCoreVisualRadiusMeters(id, radius, transitionSeconds) and ok end
    end
    if targets.shieldVisible ~= nil and DFR.CoreVisual.core_shield
        and DFR.CoreVisual.core_shield.drawEnabled ~= (targets.shieldVisible and true or false) then
        DFR.SetCoreVisualDrawEnabled('core_shield', targets.shieldVisible)
    end
    return ok
end

DFR.CoreVisualPresets = DFR.CoreVisualPresets or {
    offline = {
        radii = { core_sphere = 0, core_stellar = 0, core_blackhole = 0, core_shield = 0 },
        draw = { core_sphere = true, core_stellar = false, core_blackhole = false, core_shield = false }
    },
    annihilation_entry = {
        radii = { core_sphere = 3.0, core_stellar = 3.5, core_blackhole = 0, core_shield = 4.0 },
        draw = { core_sphere = true, core_stellar = true, core_blackhole = false, core_shield = true }
    },
    dark_fusion_future = {
        radii = { core_sphere = 5.8, core_stellar = 0, core_blackhole = 3.5, core_shield = 0 },
        draw = { core_sphere = true, core_stellar = false, core_blackhole = true, core_shield = false }
    }
}

function DFR.ApplyCoreVisualPreset(name, transitionSeconds)
    local preset = DFR.CoreVisualPresets[name]
    if not preset then return false end
    DFR.CoreState.preset = name

    local ok = DFR.SetCoreVisualTargets(preset.radii, transitionSeconds)
    for id, enabled in pairs(preset.draw or {}) do
        if DFR.CoreVisual[id] then DFR.SetCoreVisualDrawEnabled(id, enabled) end
    end
    return ok
end

function DFR.ResetCoreVisuals()
    for _, visual in pairs(DFR.CoreVisual or {}) do
        if type(visual) == 'table' and visual.id and visual.kind == 'prop' then
            visual.pulse = nil
            visual.commandedAxisFactors = { x = 1, y = 1, z = 1 }
            visual.wobble.nextAt = 0
        end
    end
    DFR.ApplyCoreVisualPreset('offline', 0)
    for _, beam in ipairs({ 'director', 'annihilation', 'darkfusion', 'unstable', 'catalyze' }) do
        DFR.SetCoreBeamActive(beam, false)
    end
    DFR.CoreVisual.LastSyncedState = nil
    return true
end

function DFR.SetCoreBeamActive(name, active)
    return DFR.SetCoreVisualEnabled('beam_' .. tostring(name), active)
end

function DFR.SyncCoreVisuals()
    if not DFR.CoreVisual or not DFR.CoreVisual.core_chamber_light then return false end
    local state = DFR.GetState and DFR.GetState() or DFR.STATE_OFFLINE
    if DFR.CoreVisual.LastSyncedState == state then return true end
    DFR.CoreVisual.LastSyncedState = state

    local offline = state == DFR.STATE_OFFLINE or state == DFR.STATE_HALTED_ERROR
    DFR.SetCoreVisualEnabled('core_chamber_light', not offline)
    if offline then DFR.ApplyCoreVisualPreset('offline', 0.25) end
    if state == DFR.STATE_ANNIHILATION_STAGE then DFR.ApplyCoreVisualPreset('annihilation_entry', 2) end

    DFR.SetCoreBeamActive('annihilation', state == DFR.STATE_ANNIHILATION_STAGE)
    DFR.SetCoreBeamActive('darkfusion', false)
    DFR.SetCoreBeamActive('unstable', false)
    DFR.SetCoreBeamActive('catalyze', false)
    return true
end
