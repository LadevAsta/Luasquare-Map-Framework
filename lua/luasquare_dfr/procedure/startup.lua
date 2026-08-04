DFR = DFR or {}
DFR.StartupProcedure = DFR.StartupProcedure or {}
DFR.StartupLevers = DFR.StartupLevers or {}

function DFR.ResetStartupProcedure()
    DFR.StartupProcedure.State = { manualStartupStartedAt = nil }
end

function DFR.ResetStartupSystems()
    DFR.ResetStartupProcedure()
    if DFR.ResetStabilizer then DFR.ResetStabilizer() end
    if DFR.ResetDirectorBeam then DFR.ResetDirectorBeam() end
end

function DFR.GetStartupSnapshot()
    local stabilizer = DFR.Stabilizer and DFR.Stabilizer.State or {}
    local director = DFR.DirectorBeam and DFR.DirectorBeam.State or {}
    local procedure = DFR.StartupProcedure.State or {}
    return {
        stabilizerActive = stabilizer.active and true or false,
        stabilizerRequested = stabilizer.requested and true or false,
        stabilizerPowerGW = stabilizer.powerGW or 0,
        containmentFieldStrengthPercent = stabilizer.fieldStrengthPercent or 0,
        containmentFieldStabilityPercent = stabilizer.fieldStabilityPercent or 0,
        directorBeamActive = director.active and true or false,
        directorBeamPrecisionPercent = director.precisionPercent or 0,
        directorBeamImprecisionPercent = director.imprecisionPercent or 100,
        lensXOffset = director.lensXOffset or 0.5,
        lensYOffset = director.lensYOffset or 0.5,
        lensZOffset = director.lensZOffset or 0.5,
        manualStartupStartedAt = procedure.manualStartupStartedAt
    }
end

function DFR.ClearStartupLevers()
    DFR.StartupLevers = {}
end

function DFR.ArmStartupLever(id, activator)
    local now = DFR.GetTime()
    local window = DFR.Config.StartupLeverArmWindow or 5
    DFR.StartupLevers[id] = { armedAt = now, actor = DFR.GetActorName(activator) }
    for leverId, data in pairs(DFR.StartupLevers) do
        if now - (data.armedAt or 0) > window then DFR.StartupLevers[leverId] = nil end
    end
    local armedCount = 0
    for _ in pairs(DFR.StartupLevers) do armedCount = armedCount + 1 end
    DFR.Log('Startup lever armed: ' .. tostring(id) .. ' (' .. tostring(armedCount) .. '/3)')
    if DFR.StartupLevers.startup_lever_1 and DFR.StartupLevers.startup_lever_2
        and DFR.StartupLevers.startup_lever_3 then
        DFR.ClearStartupLevers()
        return DFR.RequestTransition(DFR.STATE_STARTUP_PREP, 'triple startup levers armed', activator)
    end
    return true
end

function DFR.RegisterStartupLever(id, label)
    return DFR.RegisterControl(id, {
        label = label or id,
        allowedStates = {[DFR.STATE_OFFLINE] = true},
        callback = function(activator) return DFR.ArmStartupLever(id, activator) end
    })
end

function DFR.BeginManualStartup(activator)
    if not DFR.CanEnterStartupPrep() then
        DFR.Log('Manual startup rejected: fuel readiness is not satisfied')
        return false
    end
    DFR.ResetStartupSystems()
    DFR.StartupProcedure.State.manualStartupStartedAt = DFR.GetTime()
    local transitioned = DFR.RequestTransition(
        DFR.STATE_MANUAL_STARTUP, 'manual startup accepted', activator
    )
    if transitioned and DFR.DeployStartupMachinery then DFR.DeployStartupMachinery() end
    return transitioned
end

function DFR.AbortStartupPrep(activator)
    DFR.ClearStartupLevers()
    DFR.ResetStartupSystems()
    local transitioned = DFR.RequestTransition(DFR.STATE_OFFLINE, 'startup prep aborted', activator)
    if transitioned and DFR.RetractStartupMachinery then DFR.RetractStartupMachinery() end
    return transitioned
end

function DFR.TickStartupPrep(dt)
    DFR.RefreshFuelReadiness()
end

function DFR.TickManualStartup(dt)
    if DFR.TickStabilizer then DFR.TickStabilizer(dt) end
    if DFR.TickDirectorBeam then DFR.TickDirectorBeam(dt) end
end

function DFR.RegisterStartupPrepControls()
    DFR.RegisterControl('manual_startup_begin', {
        label = 'Begin Manual Startup',
        allowedStates = {[DFR.STATE_STARTUP_PREP] = true},
        callback = function(activator) return DFR.BeginManualStartup(activator) end
    })
    DFR.RegisterControl('startup_prep_abort', {
        label = 'Abort Startup Prep',
        allowedStates = {[DFR.STATE_STARTUP_PREP] = true},
        callback = function(activator) return DFR.AbortStartupPrep(activator) end
    })
end

function DFR.RegisterManualStartupControls()
    DFR.RegisterControl('stabilizer_enable', {
        label = 'Enable Stabilizer',
        allowedStates = {[DFR.STATE_MANUAL_STARTUP] = true},
        callback = function() return DFR.SetStabilizerActive(true) end
    })
    DFR.RegisterControl('stabilizer_disable', {
        label = 'Disable Stabilizer',
        allowedStates = {[DFR.STATE_MANUAL_STARTUP] = true},
        callback = function() return DFR.SetStabilizerActive(false) end
    })
    DFR.RegisterControl('containment_raise', {
        label = 'Raise Containment Field',
        allowedStates = {[DFR.STATE_MANUAL_STARTUP] = true},
        callback = function()
            return DFR.AdjustContainmentField(DFR.Config.ContainmentFieldStepPercent or 5)
        end
    })
    DFR.RegisterControl('containment_lower', {
        label = 'Lower Containment Field',
        allowedStates = {[DFR.STATE_MANUAL_STARTUP] = true},
        callback = function()
            return DFR.AdjustContainmentField(-(DFR.Config.ContainmentFieldStepPercent or 5))
        end
    })
    DFR.RegisterControl('director_beam_enable', {
        label = 'Enable Director Beam',
        allowedStates = {[DFR.STATE_MANUAL_STARTUP] = true},
        callback = function() return DFR.SetDirectorBeamActive(true) end
    })
    DFR.RegisterControl('director_beam_disable', {
        label = 'Disable Director Beam',
        allowedStates = {[DFR.STATE_MANUAL_STARTUP] = true},
        callback = function() return DFR.SetDirectorBeamActive(false) end
    })
    local step = DFR.Config.LensOffsetStep or 0.025
    for _, axis in ipairs({'x', 'y', 'z'}) do
        DFR.RegisterControl('lens_' .. axis .. '_plus', {
            label = 'Lens ' .. string.upper(axis) .. ' Plus',
            allowedStates = {[DFR.STATE_MANUAL_STARTUP] = true},
            callback = function() return DFR.AdjustLens(axis, step) end
        })
        DFR.RegisterControl('lens_' .. axis .. '_minus', {
            label = 'Lens ' .. string.upper(axis) .. ' Minus',
            allowedStates = {[DFR.STATE_MANUAL_STARTUP] = true},
            callback = function() return DFR.AdjustLens(axis, -step) end
        })
    end
end

DFR.ResetStartupProcedure()
