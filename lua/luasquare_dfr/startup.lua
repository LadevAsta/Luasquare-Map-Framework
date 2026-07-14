DFR = DFR or {}
DFR.Startup = DFR.Startup or {}

local function clamp(value, minValue, maxValue)
    if math.Clamp then return math.Clamp(value, minValue, maxValue) end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

function DFR.ResetStartupSystems()
    DFR.Startup = {
        stabilizerActive = false,
        stabilizerPowerGW = 0,
        containmentFieldStrengthPercent = 0,
        containmentFieldStabilityPercent = 0,
        directorBeamActive = false,
        directorBeamPrecisionPercent = 0,
        directorBeamImprecisionPercent = 100,
        lensXOffset = 0.5,
        lensYOffset = 0.5,
        lensZOffset = 0.5,
        manualStartupStartedAt = nil
    }
end

DFR.ResetStartupSystems()

function DFR.UpdateDirectorBeamPrecision()
    local startup = DFR.Startup
    local dx = math.abs((startup.lensXOffset or 0.5) - 0.5)
    local dy = math.abs((startup.lensYOffset or 0.5) - 0.5)
    local dz = math.abs((startup.lensZOffset or 0.5) - 0.5)
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local maxDistance = math.sqrt(0.5 * 0.5 * 3)
    local imprecision = clamp((distance / maxDistance) * 100, 0, 100)

    startup.directorBeamImprecisionPercent = imprecision
    startup.directorBeamPrecisionPercent = 100 - imprecision
    return startup.directorBeamPrecisionPercent
end

function DFR.BeginManualStartup(activator)
    if not DFR.CanEnterStartupPrep() then
        DFR.Log('Manual startup rejected: fuel readiness is not satisfied')
        return false
    end

    DFR.ResetStartupSystems()
    DFR.Startup.manualStartupStartedAt = DFR.GetTime()
    if DFR.DeployStartupMachinery then DFR.DeployStartupMachinery() end
    return DFR.RequestTransition(DFR.STATE_MANUAL_STARTUP, 'manual startup accepted', activator)
end

function DFR.AbortStartupPrep(activator)
    DFR.ClearStartupLevers()
    DFR.ResetStartupSystems()
    if DFR.RetractStartupMachinery then DFR.RetractStartupMachinery() end
    return DFR.RequestTransition(DFR.STATE_OFFLINE, 'startup prep aborted', activator)
end

function DFR.SetStabilizerActive(active)
    DFR.Startup.stabilizerActive = active and true or false
    DFR.Startup.stabilizerPowerGW = DFR.Startup.stabilizerActive and (DFR.Config.StabilizerStartupPowerGW or 8) or 0
    if DFR.Startup.stabilizerActive then
        if DFR.ActivateStabilizerMachinery then DFR.ActivateStabilizerMachinery() end
    else
        if DFR.DeactivateStabilizerMachinery then DFR.DeactivateStabilizerMachinery() end
    end
    DFR.Log('Stabilizer ' .. (DFR.Startup.stabilizerActive and 'active' or 'offline'))
    return true
end

function DFR.AdjustContainmentField(deltaPercent)
    if not DFR.Startup.stabilizerActive then
        DFR.Log('Containment command rejected: stabilizer is offline')
        return false
    end

    local limit = DFR.Config.ContainmentFieldStartupLimitPercent or 35
    local value = (DFR.Startup.containmentFieldStrengthPercent or 0) + (tonumber(deltaPercent) or 0)
    DFR.Startup.containmentFieldStrengthPercent = clamp(value, 0, limit)
    DFR.Log(string.format('Containment field %.1f%%', DFR.Startup.containmentFieldStrengthPercent))
    return true
end

function DFR.SetDirectorBeamActive(active)
    if active and not DFR.Startup.stabilizerActive then
        DFR.Log('Director beam rejected: stabilizer is offline')
        return false
    end

    DFR.Startup.directorBeamActive = active and true or false
    DFR.UpdateDirectorBeamPrecision()
    if DFR.CoreVisual and DFR.CoreVisual.beam_director and DFR.SetCoreBeamActive then
        DFR.SetCoreBeamActive('director', DFR.Startup.directorBeamActive)
    end
    if DFR.SetDirectorLensMachineryActive then DFR.SetDirectorLensMachineryActive(DFR.Startup.directorBeamActive) end
    DFR.Log('Director beam ' .. (DFR.Startup.directorBeamActive and 'active' or 'offline'))
    return true
end

function DFR.AdjustLens(axis, delta)
    local key = nil
    axis = tostring(axis or ''):lower()
    if axis == 'x' then key = 'lensXOffset' end
    if axis == 'y' then key = 'lensYOffset' end
    if axis == 'z' then key = 'lensZOffset' end
    if not key then return false end

    DFR.Startup[key] = clamp((DFR.Startup[key] or 0.5) + (tonumber(delta) or 0), 0, 1)
    DFR.UpdateDirectorBeamPrecision()
    DFR.Log(string.format(
        'Lens %s %.3f precision %.1f%%',
        string.upper(axis),
        DFR.Startup[key],
        DFR.Startup.directorBeamPrecisionPercent or 0
    ))
    return true
end

function DFR.TickStartupPrep(dt)
    DFR.RefreshFuelReadiness()
end

function DFR.TickManualStartup(dt)
    local startup = DFR.Startup
    if startup.stabilizerActive then
        local target = startup.containmentFieldStrengthPercent or 0
        local stability = startup.containmentFieldStabilityPercent or 0
        local rate = target > stability and 8 or 4
        local direction = target > stability and 1 or -1
        local nextValue = stability + direction * rate * dt
        if direction > 0 then
            startup.containmentFieldStabilityPercent = math.min(nextValue, target)
        else
            startup.containmentFieldStabilityPercent = math.max(nextValue, target)
        end
    else
        startup.containmentFieldStabilityPercent = math.max((startup.containmentFieldStabilityPercent or 0) - 10 * dt, 0)
    end

    if startup.directorBeamActive then
        local drift = DFR.Config.DirectorBeamAutoDriftPerSecond or 0
        startup.lensXOffset = clamp((startup.lensXOffset or 0.5) + math.sin(DFR.GetTime() * 0.17) * drift * dt, 0, 1)
        startup.lensYOffset = clamp((startup.lensYOffset or 0.5) + math.sin(DFR.GetTime() * 0.23) * drift * dt, 0, 1)
        startup.lensZOffset = clamp((startup.lensZOffset or 0.5) + math.sin(DFR.GetTime() * 0.31) * drift * dt, 0, 1)
    end

    DFR.UpdateDirectorBeamPrecision()
end

function DFR.RegisterStartupPrepControls()
    DFR.RegisterControl('manual_startup_begin', {
        label = 'Begin Manual Startup',
        allowedStates = {
            [DFR.STATE_STARTUP_PREP] = true
        },
        callback = function(activator)
            return DFR.BeginManualStartup(activator)
        end
    })

    DFR.RegisterControl('startup_prep_abort', {
        label = 'Abort Startup Prep',
        allowedStates = {
            [DFR.STATE_STARTUP_PREP] = true
        },
        callback = function(activator)
            return DFR.AbortStartupPrep(activator)
        end
    })
end

function DFR.RegisterManualStartupControls()
    DFR.RegisterControl('stabilizer_enable', {
        label = 'Enable Stabilizer',
        allowedStates = {
            [DFR.STATE_MANUAL_STARTUP] = true
        },
        callback = function()
            return DFR.SetStabilizerActive(true)
        end
    })

    DFR.RegisterControl('stabilizer_disable', {
        label = 'Disable Stabilizer',
        allowedStates = {
            [DFR.STATE_MANUAL_STARTUP] = true
        },
        callback = function()
            return DFR.SetStabilizerActive(false)
        end
    })

    DFR.RegisterControl('containment_raise', {
        label = 'Raise Containment Field',
        allowedStates = {
            [DFR.STATE_MANUAL_STARTUP] = true
        },
        callback = function()
            return DFR.AdjustContainmentField(DFR.Config.ContainmentFieldStepPercent or 5)
        end
    })

    DFR.RegisterControl('containment_lower', {
        label = 'Lower Containment Field',
        allowedStates = {
            [DFR.STATE_MANUAL_STARTUP] = true
        },
        callback = function()
            return DFR.AdjustContainmentField(-(DFR.Config.ContainmentFieldStepPercent or 5))
        end
    })

    DFR.RegisterControl('director_beam_enable', {
        label = 'Enable Director Beam',
        allowedStates = {
            [DFR.STATE_MANUAL_STARTUP] = true
        },
        callback = function()
            return DFR.SetDirectorBeamActive(true)
        end
    })

    DFR.RegisterControl('director_beam_disable', {
        label = 'Disable Director Beam',
        allowedStates = {
            [DFR.STATE_MANUAL_STARTUP] = true
        },
        callback = function()
            return DFR.SetDirectorBeamActive(false)
        end
    })

    local step = DFR.Config.LensOffsetStep or 0.025
    for _, axis in ipairs({'x', 'y', 'z'}) do
        DFR.RegisterControl('lens_' .. axis .. '_plus', {
            label = 'Lens ' .. string.upper(axis) .. ' Plus',
            allowedStates = {
                [DFR.STATE_MANUAL_STARTUP] = true
            },
            callback = function()
                return DFR.AdjustLens(axis, step)
            end
        })

        DFR.RegisterControl('lens_' .. axis .. '_minus', {
            label = 'Lens ' .. string.upper(axis) .. ' Minus',
            allowedStates = {
                [DFR.STATE_MANUAL_STARTUP] = true
            },
            callback = function()
                return DFR.AdjustLens(axis, -step)
            end
        })
    end
end
