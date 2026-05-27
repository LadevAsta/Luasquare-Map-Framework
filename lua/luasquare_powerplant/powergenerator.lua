if LUASQUARE_POWERGENERATOR_CORE_LOADED then return end
LUASQUARE_POWERGENERATOR_CORE_LOADED = true
LUASQUARE_POWERGENERATOR = LUASQUARE_POWERGENERATOR or {}
LUASQUARE_POWERGENERATOR.Generators = LUASQUARE_POWERGENERATOR.Generators or {}
LUASQUARE_POWERGENERATOR.TickInterval = LUASQUARE_POWERGENERATOR.TickInterval or 0.1

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_POWERGENERATOR.RegisterGenerator(name, data)
    data = data or {}
    local maxMW = tonumber(data.maxMW) or tonumber(data.ratedMW) or 1
    local generatorType = data.type or (data.turbine and 'turbine' or 'static')
    local breaker = data.breaker or (name .. '_breaker')

    LUASQUARE_POWERGENERATOR.Generators[name] = {
        name = name,
        type = generatorType,
        grid = data.grid,
        breaker = breaker,
        enabled = data.enabled ~= false,
        tripped = data.tripped and true or false,
        synced = data.synced and true or false,
        turbine = data.turbine,
        ratedMW = tonumber(data.ratedMW) or maxMW,
        maxMW = maxMW,
        outputMW = tonumber(data.outputMW) or 0,
        targetMW = tonumber(data.targetMW) or tonumber(data.outputMW) or 0,
        rampRateMW = tonumber(data.rampRateMW) or maxMW,
        autoStart = data.autoStart and true or false,
        autoSync = data.autoSync and true or false,
        gridRPM = tonumber(data.gridRPM) or 1800,
        syncRPMTolerance = tonumber(data.syncRPMTolerance) or 8,
        syncPhaseTolerance = tonumber(data.syncPhaseTolerance) or 8,
        syncFailureTrips = data.syncFailureTrips and true or false,
        gridLossTrips = data.gridLossTrips and true or false,
        lastMW = 0,
        lastAcceptedMW = 0,
        lastRPMError = 0,
        lastPhaseError = 0,
        lastSyncBlockReason = nil,
        tripReason = nil,
        startRelay = data.startRelay,
        stopRelay = data.stopRelay,
        syncRelay = data.syncRelay,
        tripRelay = data.tripRelay,
        resetRelay = data.resetRelay,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }

    if LUASQUARE_POWERGRID and not LUASQUARE_POWERGRID.GetBreaker(breaker) then
        LUASQUARE_POWERGRID.RegisterBreaker(breaker, {
            grid = data.grid,
            owner = name,
            kind = 'generator',
            closed = data.closed or data.breakerClosed,
            maxMW = maxMW,
            monitorPos = data.breakerMonitorPos,
            monitorTarget = data.breakerMonitorTarget,
            monitorOffset = data.breakerMonitorOffset
        })
    end

    local turbine = data.turbine and LUASQUARE_TURBINE and LUASQUARE_TURBINE.GetTurbine(data.turbine)
    if turbine then turbine.generator = name end
end

function LUASQUARE_POWERGENERATOR.RegisterTurbineGenerator(name, data)
    data = data or {}
    data.type = 'turbine'
    return LUASQUARE_POWERGENERATOR.RegisterGenerator(name, data)
end

function LUASQUARE_POWERGENERATOR.GetGenerator(name)
    return LUASQUARE_POWERGENERATOR.Generators[name]
end

function LUASQUARE_POWERGENERATOR.FireRelay(relay)
    if relay and LUASQUARE_FLUID then LUASQUARE_FLUID.FireRelay(relay) end
end

local function normalizePhase(value)
    return ((value or 0) + 180) % 360 - 180
end

function LUASQUARE_POWERGENERATOR.GetBreaker(generator)
    if not LUASQUARE_POWERGRID then return nil end
    return LUASQUARE_POWERGRID.GetBreaker(generator.breaker)
end

function LUASQUARE_POWERGENERATOR.GetGrid(generator)
    if not LUASQUARE_POWERGRID then return nil end
    return LUASQUARE_POWERGRID.GetGrid(generator.grid)
end

-- =========================================
-- OPERATORS
-- =========================================
function LUASQUARE_POWERGENERATOR.SetEnabled(name, enabled)
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator(name)
    if not generator then
        print('[LUASQUARE_POWERGENERATOR] Unknown generator: ' .. tostring(name))
        return false
    end

    local wasEnabled = generator.enabled
    generator.enabled = enabled and true or false
    if generator.enabled and not wasEnabled then LUASQUARE_POWERGENERATOR.FireRelay(generator.startRelay) end
    if not generator.enabled and wasEnabled then
        LUASQUARE_POWERGENERATOR.Unsync(name)
        LUASQUARE_POWERGENERATOR.FireRelay(generator.stopRelay)
    end
    return true
end

function LUASQUARE_POWERGENERATOR.SetOutputMW(name, mw)
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator(name)
    if not generator then
        print('[LUASQUARE_POWERGENERATOR] Unknown generator: ' .. tostring(name))
        return false
    end

    generator.targetMW = math.Clamp(tonumber(mw) or 0, 0, generator.maxMW)
    return true
end

function LUASQUARE_POWERGENERATOR.Trip(name, reason)
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator(name)
    if not generator then
        print('[LUASQUARE_POWERGENERATOR] Unknown generator: ' .. tostring(name))
        return false
    end

    if generator.tripped then return true end
    generator.tripped = true
    generator.enabled = false
    generator.synced = false
    generator.tripReason = reason or 'TRIP'
    if LUASQUARE_POWERGRID then LUASQUARE_POWERGRID.TripBreaker(generator.breaker, generator.tripReason) end

    local turbine = generator.turbine and LUASQUARE_TURBINE and LUASQUARE_TURBINE.GetTurbine(generator.turbine)
    if turbine then
        turbine.synced = false
        turbine.lastMW = 0
        if not turbine.tripped then LUASQUARE_TURBINE.Trip(generator.turbine, generator.tripReason) end
    end

    LUASQUARE_POWERGENERATOR.FireRelay(generator.tripRelay)
    print('[LUASQUARE_POWERGENERATOR] Trip ' .. tostring(name) .. ': ' .. tostring(generator.tripReason))
    return true
end

function LUASQUARE_POWERGENERATOR.ResetTrip(name)
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator(name)
    if not generator then
        print('[LUASQUARE_POWERGENERATOR] Unknown generator: ' .. tostring(name))
        return false
    end

    generator.tripped = false
    generator.tripReason = nil
    generator.enabled = true
    if LUASQUARE_POWERGRID then LUASQUARE_POWERGRID.ResetBreaker(generator.breaker, false) end

    local turbine = generator.turbine and LUASQUARE_TURBINE and LUASQUARE_TURBINE.GetTurbine(generator.turbine)
    if turbine and turbine.tripped then LUASQUARE_TURBINE.ResetTrip(generator.turbine) end

    LUASQUARE_POWERGENERATOR.FireRelay(generator.resetRelay)
    return true
end

function LUASQUARE_POWERGENERATOR.CanSync(name)
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator(name)
    if not generator or generator.type ~= 'turbine' then return false end
    if generator.tripped or not generator.enabled then
        generator.lastSyncBlockReason = generator.tripped and 'GENERATOR_TRIPPED' or 'GENERATOR_OFFLINE'
        return false
    end
    if not LUASQUARE_POWERGRID or not LUASQUARE_POWERGRID.IsGridEnergized(generator.grid) then
        generator.lastSyncBlockReason = 'GRID_DEAD'
        return false
    end

    local breaker = LUASQUARE_POWERGENERATOR.GetBreaker(generator)
    if breaker and breaker.tripped then
        generator.lastSyncBlockReason = 'BREAKER_TRIPPED'
        return false
    end

    local turbine = generator.turbine and LUASQUARE_TURBINE and LUASQUARE_TURBINE.GetTurbine(generator.turbine)
    if not turbine then
        generator.lastSyncBlockReason = 'NO_TURBINE'
        return false
    end
    if turbine.catastrophicFailed then
        generator.lastSyncBlockReason = 'TURBINE_DESTROYED'
        return false
    end
    if turbine.tripped or not turbine.enabled then
        generator.lastSyncBlockReason = turbine.tripped and 'TURBINE_TRIPPED' or 'TURBINE_OFFLINE'
        return false
    end

    local gridRPM = LUASQUARE_POWERGRID.GetGridRPM(generator.grid, generator.gridRPM)
    turbine.gridRPM = gridRPM
    generator.lastRPMError = math.abs((turbine.rpm or 0) - gridRPM)
    generator.lastPhaseError = math.abs(normalizePhase(turbine.phase or 0))

    if generator.lastRPMError > generator.syncRPMTolerance or generator.lastPhaseError > generator.syncPhaseTolerance then
        generator.lastSyncBlockReason = 'SYNC_MISMATCH'
        return false
    end

    generator.lastSyncBlockReason = nil
    return true
end

function LUASQUARE_POWERGENERATOR.Sync(name)
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator(name)
    if not generator then
        print('[LUASQUARE_POWERGENERATOR] Unknown generator: ' .. tostring(name))
        return false
    end

    if generator.type ~= 'turbine' then
        generator.synced = true
        if LUASQUARE_POWERGRID then LUASQUARE_POWERGRID.SetBreaker(generator.breaker, true) end
        return true
    end

    if not LUASQUARE_POWERGENERATOR.CanSync(name) then
        local reason = generator.lastSyncBlockReason or 'SYNC_FAILURE'
        local hardFailure = reason == 'GENERATOR_OFFLINE' or reason == 'TURBINE_OFFLINE' or reason == 'NO_TURBINE'
        if hardFailure or generator.syncFailureTrips then LUASQUARE_POWERGENERATOR.Trip(name, reason) end
        return false
    end

    local turbine = LUASQUARE_TURBINE.GetTurbine(generator.turbine)
    local gridRPM = LUASQUARE_POWERGRID.GetGridRPM(generator.grid, generator.gridRPM)
    turbine.synced = true
    turbine.rpm = gridRPM
    turbine.gridRPM = gridRPM
    turbine.phase = 0
    turbine.loadMW = generator.maxMW
    turbine.tripReason = nil
    generator.synced = true
    LUASQUARE_POWERGRID.SetBreaker(generator.breaker, true)
    LUASQUARE_POWERGENERATOR.FireRelay(generator.syncRelay)
    return true
end

function LUASQUARE_POWERGENERATOR.Unsync(name)
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator(name)
    if not generator then
        print('[LUASQUARE_POWERGENERATOR] Unknown generator: ' .. tostring(name))
        return false
    end

    generator.synced = false
    generator.lastMW = 0
    generator.lastAcceptedMW = 0
    if LUASQUARE_POWERGRID then LUASQUARE_POWERGRID.SetBreaker(generator.breaker, false) end

    local turbine = generator.turbine and LUASQUARE_TURBINE and LUASQUARE_TURBINE.GetTurbine(generator.turbine)
    if turbine then
        turbine.synced = false
        turbine.lastMW = 0
    end
    return true
end

-- =========================================
-- UPDATE
-- =========================================
function LUASQUARE_POWERGENERATOR.UpdateTurbineGenerator(name, generator, dt)
    local turbine = generator.turbine and LUASQUARE_TURBINE and LUASQUARE_TURBINE.GetTurbine(generator.turbine)
    local breaker = LUASQUARE_POWERGENERATOR.GetBreaker(generator)
    local grid = LUASQUARE_POWERGENERATOR.GetGrid(generator)
    generator.lastMW = 0
    generator.lastAcceptedMW = 0

    if not turbine or not grid then return end

    local gridEnergized = LUASQUARE_POWERGRID.IsGridEnergized(generator.grid)
    local gridRPM = LUASQUARE_POWERGRID.GetGridRPM(generator.grid, generator.gridRPM)
    turbine.gridRPM = gridRPM
    generator.lastRPMError = math.abs((turbine.rpm or 0) - gridRPM)
    generator.lastPhaseError = math.abs(normalizePhase(turbine.phase or 0))

    if generator.autoSync and not generator.synced and LUASQUARE_POWERGENERATOR.CanSync(name) then
        LUASQUARE_POWERGENERATOR.Sync(name)
        breaker = LUASQUARE_POWERGENERATOR.GetBreaker(generator)
    end

    local closed = breaker and breaker.closed and not breaker.tripped
    if not generator.enabled or generator.tripped or turbine.tripped or not gridEnergized then
        if generator.synced and generator.gridLossTrips and not gridEnergized then
            LUASQUARE_POWERGENERATOR.Trip(name, 'GRID_LOSS')
        elseif generator.synced then
            LUASQUARE_POWERGENERATOR.Unsync(name)
        end
        return
    end

    if not closed then
        if generator.synced then LUASQUARE_POWERGENERATOR.Unsync(name) end
        return
    end

    turbine.synced = true
    turbine.gridRPM = gridRPM
    turbine.loadMW = generator.maxMW
    generator.synced = true

    local produced = math.Clamp(turbine.lastMW or 0, 0, generator.maxMW)
    local accepted = LUASQUARE_POWERGRID.SubmitGeneration(generator.grid, name, produced, generator.breaker)
    generator.lastMW = produced
    generator.lastAcceptedMW = accepted
end

function LUASQUARE_POWERGENERATOR.UpdateStaticGenerator(name, generator, dt)
    generator.lastMW = 0
    generator.lastAcceptedMW = 0

    if not generator.enabled or generator.tripped then return end
    if not LUASQUARE_POWERGRID then return end

    local breaker = LUASQUARE_POWERGENERATOR.GetBreaker(generator)
    if breaker and not breaker.closed and generator.autoStart then LUASQUARE_POWERGRID.SetBreaker(generator.breaker, true) end
    breaker = LUASQUARE_POWERGENERATOR.GetBreaker(generator)
    if breaker and (breaker.tripped or not breaker.closed) then return end

    local step = (generator.rampRateMW or generator.maxMW) * dt
    local target = math.Clamp(generator.targetMW or 0, 0, generator.maxMW)
    generator.outputMW = math.Approach(generator.outputMW or 0, target, step)

    local accepted = LUASQUARE_POWERGRID.SubmitGeneration(generator.grid, name, generator.outputMW, generator.breaker)
    generator.lastMW = generator.outputMW
    generator.lastAcceptedMW = accepted
    generator.synced = accepted > 0
end

function LUASQUARE_POWERGENERATOR.UpdateGenerator(name, dt)
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator(name)
    if not generator then return end

    if generator.type == 'turbine' then
        LUASQUARE_POWERGENERATOR.UpdateTurbineGenerator(name, generator, dt)
    else
        LUASQUARE_POWERGENERATOR.UpdateStaticGenerator(name, generator, dt)
    end
end

function LUASQUARE_POWERGENERATOR.UpdateAll()
    local dt = LUASQUARE_POWERGENERATOR.TickInterval
    for name, _ in pairs(LUASQUARE_POWERGENERATOR.Generators) do
        LUASQUARE_POWERGENERATOR.UpdateGenerator(name, dt)
    end
end

function LUASQUARE_POWERGENERATOR.Start()
    if timer.Exists('LUASQUARE_POWERGENERATOR_UpdateTimer') then timer.Remove('LUASQUARE_POWERGENERATOR_UpdateTimer') end
    timer.Create('LUASQUARE_POWERGENERATOR_UpdateTimer', LUASQUARE_POWERGENERATOR.TickInterval, 0, function() LUASQUARE_POWERGENERATOR.UpdateAll() end)
    print('[LUASQUARE_POWERGENERATOR] Started')
end

print('[LUASQUARE_POWERGENERATOR] Loaded')
