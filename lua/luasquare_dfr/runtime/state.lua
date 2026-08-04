DFR = DFR or {}

DFR.STATE_OFFLINE = 'OFFLINE'
DFR.STATE_STARTUP_PREP = 'STARTUP_PREP'
DFR.STATE_MANUAL_STARTUP = 'MANUAL_STARTUP'
DFR.STATE_ANNIHILATION_STAGE = 'ANNIHILATION_STAGE'
DFR.STATE_CONTROLLED_SHUTDOWN = 'CONTROLLED_SHUTDOWN'
DFR.STATE_HALTED_ERROR = 'HALTED_ERROR'

DFR.States = DFR.States or {
    [DFR.STATE_OFFLINE] = true,
    [DFR.STATE_STARTUP_PREP] = true,
    [DFR.STATE_MANUAL_STARTUP] = true,
    [DFR.STATE_ANNIHILATION_STAGE] = true,
    [DFR.STATE_CONTROLLED_SHUTDOWN] = true,
    [DFR.STATE_HALTED_ERROR] = true
}

DFR.ValidTransitions = DFR.ValidTransitions or {
    [DFR.STATE_OFFLINE] = {
        [DFR.STATE_STARTUP_PREP] = true
    },
    [DFR.STATE_STARTUP_PREP] = {
        [DFR.STATE_MANUAL_STARTUP] = true,
        [DFR.STATE_OFFLINE] = true
    },
    [DFR.STATE_MANUAL_STARTUP] = {
        [DFR.STATE_ANNIHILATION_STAGE] = true,
        [DFR.STATE_CONTROLLED_SHUTDOWN] = true,
        [DFR.STATE_OFFLINE] = true
    },
    [DFR.STATE_ANNIHILATION_STAGE] = {
        [DFR.STATE_CONTROLLED_SHUTDOWN] = true
    },
    [DFR.STATE_CONTROLLED_SHUTDOWN] = {
        [DFR.STATE_OFFLINE] = true
    },
    [DFR.STATE_HALTED_ERROR] = {}
}

DFR.State = DFR.State or {
    current = DFR.STATE_OFFLINE,
    previous = nil,
    enteredAt = DFR.GetTime and DFR.GetTime() or 0,
    lastTransition = nil,
    history = {}
}

DFR.Resources = DFR.Resources or {
    matterReservePercent = DFR.Config.InitialMatterReservePercent,
    antimatterReservePercent = DFR.Config.InitialAntimatterReservePercent,
    fuelReceptacleCount = DFR.Config.InitialFuelReceptacleCount,
    fuelReceptaclesReady = false,
    decaosOnline = DFR.Config.InitialDecaosOnline,
    superstructureIntegrityPercent = DFR.Config.InitialSuperstructureIntegrityPercent,
    reactorOutputGW = 0,
    reactorOutputTW = 0
}

function DFR.GetState()
    return DFR.State.current
end

function DFR.RefreshFuelReadiness()
    local required = DFR.Config.StartupRequiredFuelReceptacles or 3
    local matterReady = (tonumber(DFR.Resources.matterReservePercent) or 0) > 0
    local antimatterReady = (tonumber(DFR.Resources.antimatterReservePercent) or 0) > 0
    local receptaclesReady = (tonumber(DFR.Resources.fuelReceptacleCount) or 0) >= required
    DFR.Resources.fuelReceptaclesReady = matterReady and antimatterReady and receptaclesReady
    return DFR.Resources.fuelReceptaclesReady
end

function DFR.CanEnterStartupPrep()
    return DFR.RefreshFuelReadiness()
end

function DFR.GetActorName(actor)
    if not actor then return nil end
    if type(actor) == 'string' then return actor end
    if actor.Nick then return actor:Nick() end
    if actor.GetName then return actor:GetName() end
    return tostring(actor)
end

local function recordTransition(fromState, toState, reason, actor)
    local transition = {
        time = DFR.GetTime(),
        from = fromState,
        to = toState,
        reason = reason,
        actor = DFR.GetActorName(actor)
    }

    DFR.State.lastTransition = transition
    table.insert(DFR.State.history, transition)
    if #DFR.State.history > 50 then table.remove(DFR.State.history, 1) end
end

function DFR.IsTransitionAllowed(fromState, toState)
    if toState == DFR.STATE_HALTED_ERROR then return true end
    local allowed = DFR.ValidTransitions[fromState]
    return allowed and allowed[toState] or false
end

function DFR.RequestTransition(nextState, reason, actor)
    if not DFR.States[nextState] then
        DFR.Log('Rejected unknown state transition to ' .. tostring(nextState))
        return false
    end

    local current = DFR.GetState()
    if current == nextState then return true end

    if not DFR.IsTransitionAllowed(current, nextState) then
        DFR.Log('Rejected invalid transition ' .. tostring(current) .. ' -> ' .. tostring(nextState) .. ': ' .. tostring(reason or 'no reason'))
        return false
    end

    if nextState == DFR.STATE_STARTUP_PREP and not DFR.CanEnterStartupPrep() then
        DFR.Log('Rejected startup prep: fuel readiness is not satisfied')
        return false
    end

    if DFR.CancelAllTimelines then
        DFR.CancelAllTimelines('reactor state changing to ' .. tostring(nextState))
    end

    DFR.State.previous = current
    DFR.State.current = nextState
    DFR.State.enteredAt = DFR.GetTime()
    recordTransition(current, nextState, reason, actor)
    if nextState == DFR.STATE_OFFLINE then
        if DFR.ResetStartupSystems then DFR.ResetStartupSystems() end
        if DFR.ResetCoreVisuals then DFR.ResetCoreVisuals() end
        if DFR.ResetCatalyzers then DFR.ResetCatalyzers() end
    end
    DFR.Log('Transition ' .. tostring(current) .. ' -> ' .. tostring(nextState) .. ': ' .. tostring(reason or 'no reason'))
    return true
end

function DFR.Halt(reason)
    DFR.Halted = true
    DFR.HaltReason = reason or 'critical error'
    DFR.Running = false
    if DFR.CancelAllTimelines then DFR.CancelAllTimelines('reactor halted') end
    if DFR.State.current ~= DFR.STATE_HALTED_ERROR then
        local current = DFR.State.current
        DFR.State.previous = current
        DFR.State.current = DFR.STATE_HALTED_ERROR
        DFR.State.enteredAt = DFR.GetTime()
        recordTransition(current, DFR.STATE_HALTED_ERROR, DFR.HaltReason, nil)
    end
    DFR.Log('HALTED: ' .. tostring(DFR.HaltReason))
    if DFR.StopTimer then DFR.StopTimer() end
end

