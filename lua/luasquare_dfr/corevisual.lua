DFR = DFR or {}
DFR.CoreVisual = DFR.CoreVisual or {}

local function registerVisual(id, targetName, data)
    data = data or {}
    DFR.CoreVisual[id] = {
        id = id,
        binding = data.binding or id,
        targetName = targetName,
        kind = data.kind or 'entity',
        all = data.all and true or false,
        onInput = data.onInput,
        offInput = data.offInput,
        basisScale = tonumber(data.basisScale) or 1,
        basisRadiusMeters = tonumber(data.basisRadiusMeters)
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

function DFR.RegisterCoreVisual(id, targetName, data)
    return registerVisual(id, targetName, data)
end

function DFR.RegisterDefaultCoreVisuals(options)
    options = options or {}

    registerVisual('core_sphere', options.coreSphere or 'dfr_prop_coresphere', {
        kind = 'prop',
        class = 'prop_scalable',
        basisScale = options.coreSphereBasisScale or 1,
        basisRadiusMeters = options.coreSphereBasisRadiusMeters
    })
    registerVisual('core_stellar', options.coreStellar or 'dfr_prop_corestellar', {
        kind = 'prop',
        class = 'prop_scalable',
        basisScale = options.coreStellarBasisScale or 1,
        basisRadiusMeters = options.coreStellarBasisRadiusMeters
    })
    registerVisual('core_blackhole', options.coreBlackhole or 'dfr_prop_coreblackhole', {
        kind = 'prop',
        class = 'prop_scalable',
        basisScale = options.coreBlackholeBasisScale or 1,
        basisRadiusMeters = options.coreBlackholeBasisRadiusMeters
    })
    registerVisual('core_shield', options.coreShield or 'dfr_prop_coreshield', {
        kind = 'prop',
        class = 'prop_scalable',
        basisScale = options.coreShieldBasisScale or 1,
        basisRadiusMeters = options.coreShieldBasisRadiusMeters
    })

    registerVisual('beam_director', options.directorBeam or 'beam_core_director', { kind = 'beam', class = 'env_beam', all = true })
    registerVisual('beam_annihilation', options.annihilationBeam or 'beam_core_annihilation', { kind = 'beam', class = 'env_beam', all = true })
    registerVisual('beam_darkfusion', options.darkFusionBeam or 'beam_core_darkfusion', { kind = 'beam', class = 'env_beam', all = true })
    registerVisual('beam_unstable', options.unstableBeam or 'beam_core_unstable', { kind = 'beam', class = 'env_beam', all = true })
    registerVisual('beam_catalyze', options.catalyzeBeam or 'beam_core_catalyze', { kind = 'beam', class = 'env_beam', all = true })
    registerVisual('core_chamber_light', options.coreChamberLight or 'light_corechamber', { kind = 'light', class = 'light' })

    DFR.Log('Default DFR core visuals registered')
    return true
end

function DFR.SetCoreVisualEnabled(id, enabled)
    local visual = DFR.CoreVisual[id]
    if not visual then
        DFR.Log('Unknown core visual: ' .. tostring(id))
        return false
    end

    local onInput, offInput = defaultInputs(visual)
    local inputName = enabled and (visual.onInput or onInput) or (visual.offInput or offInput)
    return DFR.SourceBindings:Fire(visual.binding, inputName, nil, { all = visual.all })
end

function DFR.SetCoreVisualScale(id, scale, changeTime)
    local visual = DFR.CoreVisual[id]
    if not visual then
        DFR.Log('Unknown core visual scale target: ' .. tostring(id))
        return false
    end

    scale = (tonumber(scale) or 1) * (visual.basisScale or 1)
    changeTime = tonumber(changeTime) or 0

    local called = DFR.SourceBindings:Call(visual.binding, 'SetModelScale', { all = visual.all }, scale, changeTime)
    if called then return true end

    return DFR.SourceBindings:Fire(visual.binding, 'SetScale', scale, { all = visual.all })
end

function DFR.SetCoreBeamActive(name, active)
    return DFR.SetCoreVisualEnabled('beam_' .. tostring(name), active)
end

function DFR.SyncCoreVisuals()
    if not DFR.CoreVisual then return false end
    if not DFR.CoreVisual.core_chamber_light then return false end
    local state = DFR.GetState and DFR.GetState() or DFR.STATE_OFFLINE
    if DFR.CoreVisual.LastSyncedState == state then return true end
    DFR.CoreVisual.LastSyncedState = state

    local online = state ~= DFR.STATE_OFFLINE and state ~= DFR.STATE_HALTED_ERROR
    DFR.SetCoreVisualEnabled('core_chamber_light', online)
    DFR.SetCoreVisualEnabled('core_sphere', online)
    DFR.SetCoreVisualEnabled('core_shield', state == DFR.STATE_MANUAL_STARTUP or state == DFR.STATE_ANNIHILATION_STAGE)
    DFR.SetCoreVisualEnabled('core_stellar', state == DFR.STATE_ANNIHILATION_STAGE)
    DFR.SetCoreVisualEnabled('core_blackhole', false)
    DFR.SetCoreBeamActive('annihilation', state == DFR.STATE_ANNIHILATION_STAGE)
    DFR.SetCoreBeamActive('darkfusion', false)
    DFR.SetCoreBeamActive('unstable', false)
    DFR.SetCoreBeamActive('catalyze', false)
    return true
end
