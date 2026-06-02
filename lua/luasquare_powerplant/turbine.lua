if LUASQUARE_TURBINE_CORE_LOADED then return end
LUASQUARE_TURBINE_CORE_LOADED = true
LUASQUARE_TURBINE = LUASQUARE_TURBINE or {}
LUASQUARE_TURBINE.Turbines = LUASQUARE_TURBINE.Turbines or {}
LUASQUARE_TURBINE.EntityCache = LUASQUARE_TURBINE.EntityCache or {}
LUASQUARE_TURBINE.TickInterval = LUASQUARE_TURBINE.TickInterval or 0.1

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_TURBINE.RegisterTurbine(name, data)
    data = data or {}
    local maxSteamRate = tonumber(data.maxSteamRate) or 1000
    local boiler = data.boiler or data.thermalSource
    local tripVibration = tonumber(data.tripVibration) or 100
    local shakeStartVibration = tonumber(data.shakeStartVibration)
    if not shakeStartVibration and data.shakeStartRPMFraction then
        shakeStartVibration = (tonumber(data.shakeStartRPMFraction) or 0) * tripVibration
    end

    LUASQUARE_TURBINE.Turbines[name] = {
        name = name,
        input = data.input,
        output = data.output,
        bypassOutput = data.bypassOutput or data.output,
        condenser = data.condenser,
        bypassCondenser = data.bypassCondenser or data.condenser,
        condenserOutput = data.condenserOutput or data.condensateOutput,
        bypassCondenserOutput = data.bypassCondenserOutput or data.condenserOutput or data.condensateOutput,
        condenserOutputTemperature = tonumber(data.condenserOutputTemperature) or 80,
        bypassCondenserOutputTemperature = tonumber(data.bypassCondenserOutputTemperature) or tonumber(data.condenserOutputTemperature) or 95,
        condenserSteamTemperatureInfluence = math.Clamp(tonumber(data.condenserSteamTemperatureInfluence) or 0.08, 0, 1),
        bypassSteamTemperatureInfluence = math.Clamp(tonumber(data.bypassSteamTemperatureInfluence) or tonumber(data.condenserSteamTemperatureInfluence) or 0.16, 0, 1),
        enabled = data.enabled and true or false,
        tripped = data.tripped and true or false,
        synced = data.synced and true or false,
        autoSync = data.autoSync and true or false,
        valve = math.Clamp(tonumber(data.valve) or 0, 0, 1),
        bypassValve = math.Clamp(tonumber(data.bypassValve) or 0, 0, 1),
        maxSteamRate = maxSteamRate,
        ratedSteamRate = tonumber(data.ratedSteamRate) or maxSteamRate,
        bypassMaxSteamRate = tonumber(data.bypassMaxSteamRate) or maxSteamRate,
        inletMaxSteamRate = tonumber(data.inletMaxSteamRate) or math.max(maxSteamRate, tonumber(data.bypassMaxSteamRate) or maxSteamRate),
        maxPressureFlowScale = tonumber(data.maxPressureFlowScale) or 2,
        ratedInletPressure = tonumber(data.ratedInletPressure),
        ratedPressureDelta = tonumber(data.ratedPressureDelta),
        steamRatio = tonumber(data.steamRatio) or 1600,
        exhaustRatio = tonumber(data.exhaustRatio) or 400,
        condenserRatio = tonumber(data.condenserRatio) or tonumber(data.exhaustRatio) or 400,
        exhaustAmount = math.max(tonumber(data.exhaustAmount) or 0, 0),
        exhaustVolume = math.max(tonumber(data.exhaustVolume) or 10000, 0.0001),
        exhaustMaxAmount = math.max(tonumber(data.exhaustMaxAmount) or 10000, 0.0001),
        exhaustHardMaxAmount = math.max(tonumber(data.exhaustHardMaxAmount) or tonumber(data.exhaustMaxAmount) or 20000, tonumber(data.exhaustMaxAmount) or 10000, 0.0001),
        exhaustPressure = 0,
        exhaustTemperature = tonumber(data.exhaustTemperature) or 100,
        exhaustTripPressure = tonumber(data.exhaustTripPressure) or 5,
        exhaustTripDelay = tonumber(data.exhaustTripDelay) or 5,
        exhaustTripTimer = 0,
        exhaustHardMaxPressure = tonumber(data.exhaustHardMaxPressure) or 12,
        designRPM = tonumber(data.designRPM) or 1800,
        gridRPM = tonumber(data.gridRPM) or 1800,
        rpm = tonumber(data.rpm) or 0,
        inertia = tonumber(data.inertia) or 8,
        friction = tonumber(data.friction) or 0.08,
        noLoadOverspeed = tonumber(data.noLoadOverspeed) or 1.08,
        tripRPM = tonumber(data.tripRPM) or 1980,
        syncRPMTolerance = tonumber(data.syncRPMTolerance) or 8,
        syncPhaseTolerance = tonumber(data.syncPhaseTolerance) or 8,
        syncFailureTrips = data.syncFailureTrips ~= false,
        phase = tonumber(data.phase) or 0,
        efficiency = tonumber(data.efficiency) or 0.32,
        cycleEfficiency = tonumber(data.cycleEfficiency) or tonumber(data.efficiency) or 0.32,
        boiler = boiler,
        useSteamEnergy = (data.useSteamEnergy or data.thermalFromSteam) and true or false,
        mwPerSteamPerSecond = tonumber(data.mwPerSteamPerSecond) or 0.02,
        loadMW = tonumber(data.loadMW),
        maxMW = tonumber(data.maxMW) or (boiler and 1000000000 or 1000),
        generator = data.generator,
        vibration = 0,
        tripVibration = tripVibration,
        startRelay = data.startRelay,
        stopRelay = data.stopRelay,
        syncRelay = data.syncRelay,
        tripRelay = data.tripRelay,
        severeTripRelay = data.severeTripRelay,
        severeTripStopRelay = data.severeTripStopRelay,
        severeTripRPM = tonumber(data.severeTripRPM) or 100,
        severeTripBrakeRPM = tonumber(data.severeTripBrakeRPM) or 20,
        severeTripFired = false,
        severeTripStopFired = false,
        extremeTripRelay = data.extremeTripRelay,
        extremeTripRPM = tonumber(data.extremeTripRPM) or 1900,
        extremeTripFlowFraction = tonumber(data.extremeTripFlowFraction) or 1,
        extremeTripChance = tonumber(data.extremeTripChance) or 0.25,
        extremeTripFired = false,
        repairRelay = data.repairRelay,
        resetRelay = data.resetRelay,
        soundEntity = data.soundEntity,
        soundEntity2 = data.soundEntity2,
        soundStopRPM = tonumber(data.soundStopRPM) or 0,
        soundMinVolume = tonumber(data.soundMinVolume) or 1,
        soundMaxVolume = tonumber(data.soundMaxVolume) or 10,
        soundMinPitch = tonumber(data.soundMinPitch) or 80,
        soundMaxPitch = tonumber(data.soundMaxPitch) or 140,
        soundStartRPMFraction = tonumber(data.soundStartRPMFraction) or 0.02,
        soundOptimalRPMFraction = tonumber(data.soundOptimalRPMFraction) or 0.95,
        soundPlaying = false,
        sound2Playing = false,
        shakeEntity = data.shakeEntity,
        shakeMaxAmplitude = tonumber(data.shakeMaxAmplitude) or 16,
        shakeMinAmplitude = tonumber(data.shakeMinAmplitude) or 1,
        shakeMaxFrequency = tonumber(data.shakeMaxFrequency) or 255,
        shakeMinFrequency = tonumber(data.shakeMinFrequency) or 120,
        shakeStartVibration = shakeStartVibration or 1,
        shakeRepeatInterval = tonumber(data.shakeRepeatInterval) or tonumber(data.shakePulseInterval) or 0.5,
        nextShakeTime = 0,
        shakeActive = false,
        lastSteamUsed = 0,
        lastBypassSteam = 0,
        lastInletSteam = 0,
        lastInletPressureScale = 0,
        lastExhaustMade = 0,
        lastExhaustStored = 0,
        lastCondenserAccepted = 0,
        lastExhaustExtracted = 0,
        lastCondensateMade = 0,
        lastBypassCondensateMade = 0,
        lastCondensateTemperature = tonumber(data.condenserOutputTemperature) or 80,
        lastBypassCondensateTemperature = tonumber(data.bypassCondenserOutputTemperature) or tonumber(data.condenserOutputTemperature) or 95,
        lastBoilerMW = 0,
        lastSteamShare = 0,
        lastTurbineSteamFraction = 0,
        lastSteamThermalMW = 0,
        lastBypassSteamThermalMW = 0,
        lastSteamQuality = 1,
        lastWetCarryover = 0,
        lastMW = 0,
        lastFlowLimited = false,
        tripReason = nil,
        tripLevel = nil,
        tripRelayFired = false,
        catastrophicFailed = data.catastrophicFailed and true or false,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
    LUASQUARE_TURBINE.UpdateExhaustPressure(name)
end

function LUASQUARE_TURBINE.GetTurbine(name)
    return LUASQUARE_TURBINE.Turbines[name]
end

function LUASQUARE_TURBINE.GetEnt(name)
    if not name then return nil end
    local cached = LUASQUARE_TURBINE.EntityCache[name]
    if IsValid(cached) then return cached end
    local ent = ents.FindByName(name)[1]
    if IsValid(ent) then LUASQUARE_TURBINE.EntityCache[name] = ent end
    return ent
end

function LUASQUARE_TURBINE.FireRelay(relay)
    if relay and LUASQUARE_FLUID then LUASQUARE_FLUID.FireRelay(relay) end
end

function LUASQUARE_TURBINE.GetTime()
    if CurTime then return CurTime() end
    return os.clock()
end

function LUASQUARE_TURBINE.FireEnt(name, input, value)
    local ent = LUASQUARE_TURBINE.GetEnt(name)
    if not IsValid(ent) then return false end
    ent:Fire(input, value)
    return true
end

-- =========================================
-- OPERATOR CONTROL
-- =========================================
function LUASQUARE_TURBINE.SetEnabled(name, enabled)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    if enabled and turbine.catastrophicFailed then
        print('[LUASQUARE_TURBINE] Cannot enable catastrophically failed turbine: ' .. tostring(name))
        return false
    end

    local wasEnabled = turbine.enabled
    turbine.enabled = enabled and true or false
    if turbine.enabled and not wasEnabled then LUASQUARE_TURBINE.FireRelay(turbine.startRelay) end
    if not turbine.enabled and wasEnabled then
        if turbine.generator and LUASQUARE_POWERGENERATOR then
            local generator = LUASQUARE_POWERGENERATOR.GetGenerator(turbine.generator)
            if generator and generator.synced then LUASQUARE_POWERGENERATOR.Unsync(turbine.generator) end
        end
        turbine.synced = false
        LUASQUARE_TURBINE.FireRelay(turbine.stopRelay)
    end
    return true
end

function LUASQUARE_TURBINE.SetValve(name, value)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    turbine.valve = math.Clamp(tonumber(value) or 0, 0, 1)
    return true
end

function LUASQUARE_TURBINE.AdjustValve(name, delta)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    return LUASQUARE_TURBINE.SetValve(name, turbine.valve + (tonumber(delta) or 0))
end

function LUASQUARE_TURBINE.SetValvePercent(name, percent)
    return LUASQUARE_TURBINE.SetValve(name, (tonumber(percent) or 0) / 100)
end

function LUASQUARE_TURBINE.AdjustValvePercent(name, percentDelta)
    return LUASQUARE_TURBINE.AdjustValve(name, (tonumber(percentDelta) or 0) / 100)
end

function LUASQUARE_TURBINE.SetBypassValve(name, value)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    turbine.bypassValve = math.Clamp(tonumber(value) or 0, 0, 1)
    return true
end

function LUASQUARE_TURBINE.AdjustBypassValve(name, delta)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    return LUASQUARE_TURBINE.SetBypassValve(name, turbine.bypassValve + (tonumber(delta) or 0))
end

function LUASQUARE_TURBINE.SetBypassValvePercent(name, percent)
    return LUASQUARE_TURBINE.SetBypassValve(name, (tonumber(percent) or 0) / 100)
end

function LUASQUARE_TURBINE.AdjustBypassValvePercent(name, percentDelta)
    return LUASQUARE_TURBINE.AdjustBypassValve(name, (tonumber(percentDelta) or 0) / 100)
end

function LUASQUARE_TURBINE.SetAutoSync(name, enabled)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    turbine.autoSync = enabled and true or false
    return true
end

function LUASQUARE_TURBINE.SetLoadMW(name, mw)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    turbine.loadMW = math.Clamp(tonumber(mw) or 0, 0, turbine.maxMW)
    return true
end

function LUASQUARE_TURBINE.FireTripRelay(turbine)
    if turbine.tripRelayFired then return false end
    turbine.tripRelayFired = true
    LUASQUARE_TURBINE.FireRelay(turbine.tripRelay)
    return true
end

function LUASQUARE_TURBINE.GetTripSteamFlowFraction(turbine)
    local maxRate = math.max(turbine.maxSteamRate or turbine.ratedSteamRate or 0, 0.0001)
    return math.max(turbine.lastSteamUsed or 0, 0) / maxRate
end

function LUASQUARE_TURBINE.RollChance(chance)
    chance = math.Clamp(tonumber(chance) or 0, 0, 1)
    if chance <= 0 then return false end
    if chance >= 1 then return true end
    if math.Rand then return math.Rand(0, 1) <= chance end
    return math.random() <= chance
end

function LUASQUARE_TURBINE.ShouldExtremeTrip(turbine)
    if (turbine.rpm or 0) < (turbine.extremeTripRPM or 1900) then return false end
    if LUASQUARE_TURBINE.GetTripSteamFlowFraction(turbine) < (turbine.extremeTripFlowFraction or 1) then return false end
    return LUASQUARE_TURBINE.RollChance(turbine.extremeTripChance)
end

function LUASQUARE_TURBINE.ShutdownForTrip(turbine)
    turbine.tripped = true
    turbine.synced = false
    turbine.enabled = false
    turbine.bypassValve = 0
    turbine.valve = 0
end

function LUASQUARE_TURBINE.TripGenerator(turbine)
    if not turbine.generator or not LUASQUARE_POWERGENERATOR then return end
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator(turbine.generator)
    if generator and not generator.tripped then LUASQUARE_POWERGENERATOR.Trip(turbine.generator, turbine.tripReason) end
end

function LUASQUARE_TURBINE.ExtremeTrip(name, reason)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    if turbine.catastrophicFailed then return true end

    LUASQUARE_TURBINE.ShutdownForTrip(turbine)
    turbine.catastrophicFailed = true
    turbine.tripLevel = 'extreme'
    turbine.tripReason = reason or 'EXTREME_TRIP'
    turbine.extremeTripFired = true
    turbine.severeTripFired = false
    turbine.severeTripStopFired = false
    turbine.tripRelayFired = false
    LUASQUARE_TURBINE.TripGenerator(turbine)
    LUASQUARE_TURBINE.FireRelay(turbine.extremeTripRelay)
    print('[LUASQUARE_TURBINE] EXTREME TRIP ' .. tostring(name) .. ': ' .. tostring(turbine.tripReason))
    return true
end

function LUASQUARE_TURBINE.TestExtremeTrip(name)
    return LUASQUARE_TURBINE.ExtremeTrip(name, 'EXTREME_TRIP_TEST')
end

function LUASQUARE_TURBINE.Trip(name, reason, forceLevel)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    if turbine.tripped then return true end
    if turbine.catastrophicFailed then return false end

    if forceLevel == 'extreme' or (forceLevel ~= 'normal' and forceLevel ~= 'severe' and LUASQUARE_TURBINE.ShouldExtremeTrip(turbine)) then
        return LUASQUARE_TURBINE.ExtremeTrip(name, reason or 'EXTREME_TRIP')
    end

    LUASQUARE_TURBINE.ShutdownForTrip(turbine)
    turbine.tripReason = reason or 'UNKNOWN'
    turbine.tripRelayFired = false
    turbine.severeTripStopFired = false
    turbine.extremeTripFired = false
    local severe = forceLevel == 'severe' or (forceLevel ~= 'normal' and (turbine.rpm or 0) >= (turbine.severeTripRPM or 100))
    if severe then
        turbine.tripLevel = 'severe'
        turbine.severeTripFired = true
        LUASQUARE_TURBINE.FireRelay(turbine.severeTripRelay)
    else
        turbine.tripLevel = 'normal'
        turbine.severeTripFired = false
        LUASQUARE_TURBINE.FireTripRelay(turbine)
    end

    LUASQUARE_TURBINE.TripGenerator(turbine)
    LUASQUARE_TURBINE.UpdateSevereTrip(name, turbine)
    print('[LUASQUARE_TURBINE] ' .. string.upper(turbine.tripLevel or 'normal') .. ' trip ' .. tostring(name) .. ': ' .. tostring(turbine.tripReason))
    return true
end

function LUASQUARE_TURBINE.ResetTrip(name)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    if turbine.catastrophicFailed then
        print('[LUASQUARE_TURBINE] Cannot reset catastrophically failed turbine, repair required: ' .. tostring(name))
        return false
    end

    turbine.tripped = false
    turbine.tripReason = nil
    turbine.tripLevel = nil
    turbine.tripRelayFired = false
    turbine.severeTripFired = false
    turbine.severeTripStopFired = false
    turbine.extremeTripFired = false
    turbine.enabled = true
    if turbine.generator and LUASQUARE_POWERGENERATOR then
        local generator = LUASQUARE_POWERGENERATOR.GetGenerator(turbine.generator)
        if generator and generator.tripped then LUASQUARE_POWERGENERATOR.ResetTrip(turbine.generator) end
    end
    LUASQUARE_TURBINE.FireRelay(turbine.resetRelay)
    return true
end

function LUASQUARE_TURBINE.RepairCatastrophicFailure(name, enabled)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    turbine.catastrophicFailed = false
    turbine.tripped = false
    turbine.tripReason = nil
    turbine.tripLevel = nil
    turbine.tripRelayFired = false
    turbine.severeTripFired = false
    turbine.severeTripStopFired = false
    turbine.extremeTripFired = false
    turbine.enabled = enabled ~= false
    LUASQUARE_TURBINE.FireRelay(turbine.repairRelay)
    LUASQUARE_TURBINE.FireRelay(turbine.resetRelay)
    return true
end

function LUASQUARE_TURBINE.Repair(name, enabled)
    return LUASQUARE_TURBINE.RepairCatastrophicFailure(name, enabled)
end

function LUASQUARE_TURBINE.GetPhaseError(turbine)
    local phase = ((turbine.phase or 0) + 180) % 360 - 180
    return phase
end

function LUASQUARE_TURBINE.CanSync(turbine)
    if turbine.catastrophicFailed then return false end
    if turbine.tripped or not turbine.enabled then return false end
    local rpmError = math.abs((turbine.rpm or 0) - (turbine.gridRPM or turbine.designRPM))
    local phaseError = math.abs(LUASQUARE_TURBINE.GetPhaseError(turbine))
    return rpmError <= turbine.syncRPMTolerance and phaseError <= turbine.syncPhaseTolerance
end

function LUASQUARE_TURBINE.Sync(name)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    if turbine.generator and LUASQUARE_POWERGENERATOR then
        print('[LUASQUARE_TURBINE] Sync is owned by generator for turbine: ' .. tostring(name))
        return false
    end

    if LUASQUARE_TURBINE.CanSync(turbine) then
        turbine.synced = true
        turbine.phase = 0
        turbine.rpm = turbine.gridRPM
        LUASQUARE_TURBINE.FireRelay(turbine.syncRelay)
        return true
    end

    if turbine.syncFailureTrips then LUASQUARE_TURBINE.Trip(name, 'SYNC_FAILURE') end
    return false
end

function LUASQUARE_TURBINE.Unsync(name)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    if turbine.generator and LUASQUARE_POWERGENERATOR then
        print('[LUASQUARE_TURBINE] Unsync is owned by generator for turbine: ' .. tostring(name))
        return false
    end

    turbine.synced = false
    return true
end

-- =========================================
-- STEAM FLOW
-- =========================================
function LUASQUARE_TURBINE.GetNetworkPressure(network)
    if not network then return 0 end
    if LUASQUARE_FLUID then LUASQUARE_FLUID.UpdatePressure(network.name) end
    return network.pressure or 0
end

function LUASQUARE_TURBINE.UpdateExhaustPressure(nameOrTurbine)
    local turbine = type(nameOrTurbine) == 'table' and nameOrTurbine or LUASQUARE_TURBINE.GetTurbine(nameOrTurbine)
    if not turbine then return 0 end

    local referenceK = (LUASQUARE_FLUID and LUASQUARE_FLUID.ReferenceSteamTemperature or 100) + 273.15
    local temperatureK = math.max((turbine.exhaustTemperature or 100) + 273.15, 1)
    turbine.exhaustPressure = math.max(turbine.exhaustAmount or 0, 0) / math.max(turbine.exhaustVolume or 1, 0.0001) * (temperatureK / referenceK)
    return turbine.exhaustPressure
end

function LUASQUARE_TURBINE.GetInternalExhaustFreeSteam(turbine)
    local free = math.max((turbine.exhaustHardMaxAmount or turbine.exhaustMaxAmount or 0) - (turbine.exhaustAmount or 0), 0)
    return free * math.max(turbine.steamRatio or 1, 0.0001) / math.max(turbine.exhaustRatio or 1, 0.0001)
end

function LUASQUARE_TURBINE.AddInternalExhaust(turbine, amount, temperature)
    amount = math.max(tonumber(amount) or 0, 0)
    local free = math.max((turbine.exhaustHardMaxAmount or turbine.exhaustMaxAmount or 0) - (turbine.exhaustAmount or 0), 0)
    local moved = math.min(amount, free)
    if moved <= 0 then return 0 end

    if LUASQUARE_FLUID and LUASQUARE_FLUID.MixTemperature then
        turbine.exhaustTemperature = LUASQUARE_FLUID.MixTemperature(turbine.exhaustAmount or 0, turbine.exhaustTemperature or 100, moved, temperature or turbine.exhaustTemperature)
    end
    turbine.exhaustAmount = (turbine.exhaustAmount or 0) + moved
    turbine.lastExhaustStored = (turbine.lastExhaustStored or 0) + moved
    LUASQUARE_TURBINE.UpdateExhaustPressure(turbine)
    return moved
end

function LUASQUARE_TURBINE.PushExhaustToCondenser(turbine, condenserName)
    if not condenserName or not LUASQUARE_CONDENSER then return 0 end
    local amount = math.max(turbine.exhaustAmount or 0, 0)
    if amount <= 0 then return 0 end

    local accepted = LUASQUARE_CONDENSER.AcceptSteam(condenserName, amount, turbine.exhaustTemperature)
    accepted = math.min(accepted or 0, amount)
    if accepted <= 0 then return 0 end
    turbine.exhaustAmount = math.max((turbine.exhaustAmount or 0) - accepted, 0)
    turbine.lastCondenserAccepted = (turbine.lastCondenserAccepted or 0) + accepted
    LUASQUARE_TURBINE.UpdateExhaustPressure(turbine)
    return accepted
end

function LUASQUARE_TURBINE.TakeExhaustSteam(nameOrTurbine, amount)
    local turbine = type(nameOrTurbine) == 'table' and nameOrTurbine or LUASQUARE_TURBINE.GetTurbine(nameOrTurbine)
    if not turbine then return 0, 100 end

    amount = math.max(tonumber(amount) or 0, 0)
    local removed = math.min(amount, turbine.exhaustAmount or 0)
    if removed <= 0 then return 0, turbine.exhaustTemperature or 100 end

    turbine.exhaustAmount = math.max((turbine.exhaustAmount or 0) - removed, 0)
    turbine.lastExhaustExtracted = (turbine.lastExhaustExtracted or 0) + removed
    LUASQUARE_TURBINE.UpdateExhaustPressure(turbine)
    return removed, turbine.exhaustTemperature or 100
end

function LUASQUARE_TURBINE.OfferExhaustToDeaerators(turbine, dt)
    if not LUASQUARE_DEAERATOR or not LUASQUARE_DEAERATOR.PullFromTurbineExhaust then return 0 end
    return LUASQUARE_DEAERATOR.PullFromTurbineExhaust(turbine.name, turbine, dt) or 0
end

function LUASQUARE_TURBINE.PushStoredExhaust(turbine, dt)
    local accepted = 0
    LUASQUARE_TURBINE.OfferExhaustToDeaerators(turbine, dt or LUASQUARE_TURBINE.TickInterval)
    accepted = accepted + LUASQUARE_TURBINE.PushExhaustToCondenser(turbine, turbine.condenser)
    if turbine.bypassCondenser and turbine.bypassCondenser ~= turbine.condenser then
        accepted = accepted + LUASQUARE_TURBINE.PushExhaustToCondenser(turbine, turbine.bypassCondenser)
    end
    return accepted
end

function LUASQUARE_TURBINE.MoveSteam(inputName, outputName, amount, exhaustRatio, steamRatio)
    if not LUASQUARE_FLUID or amount <= 0 then return 0, 0 end
    local input = LUASQUARE_FLUID.GetNetwork(inputName)
    local output = LUASQUARE_FLUID.GetNetwork(outputName)
    if not input then
        print('[LUASQUARE_TURBINE] Unknown input network: ' .. tostring(inputName))
        return 0, 0
    end

    if not output then
        print('[LUASQUARE_TURBINE] Unknown output network: ' .. tostring(outputName))
        return 0, 0
    end

    local removed, inputTemperature, thermalKJ, quality, wetCarryover
    if LUASQUARE_FLUID.RemoveSteam and input.fluidType == 'steam' then
        removed, inputTemperature, thermalKJ, quality, wetCarryover = LUASQUARE_FLUID.RemoveSteam(inputName, amount)
    else
        removed = LUASQUARE_FLUID.RemoveFluid(inputName, amount)
        inputTemperature = input.temperature
        thermalKJ = 0
        quality = 1
        wetCarryover = 0
    end
    local exhaustMade = removed * math.max(exhaustRatio, 0) / math.max(steamRatio, 0.0001)
    local added
    if output.fluidType == 'steam' and LUASQUARE_FLUID.AddSteam then
        added = LUASQUARE_FLUID.AddSteam(outputName, exhaustMade, inputTemperature, thermalKJ, quality, wetCarryover)
    else
        added = LUASQUARE_FLUID.AddFluid(outputName, exhaustMade, inputTemperature)
    end
    if added < exhaustMade then
        local returned = (exhaustMade - added) * math.max(steamRatio, 0.0001) / math.max(exhaustRatio, 0.0001)
        if LUASQUARE_FLUID.AddSteam and input.fluidType == 'steam' then
            LUASQUARE_FLUID.AddSteam(inputName, returned, inputTemperature, thermalKJ * (returned / math.max(removed, 0.0001)), quality, wetCarryover)
        else
            LUASQUARE_FLUID.AddFluid(inputName, returned, inputTemperature)
        end
        removed = math.max(removed - returned, 0)
        exhaustMade = added
    end

    return removed, exhaustMade, thermalKJ, quality, wetCarryover
end

function LUASQUARE_TURBINE.GetCondensateOutputTemperature(turbine, input, baseTemperature, influence)
    local base = tonumber(baseTemperature) or 80
    local steamTemperature = input and tonumber(input.temperature) or base
    local factor = math.Clamp(tonumber(influence) or 0, 0, 1)
    return math.max(base, Lerp(factor, base, steamTemperature))
end

function LUASQUARE_TURBINE.CondenseSteamToWater(inputName, outputName, amount, waterRatio, outputTemperature)
    if not LUASQUARE_FLUID or amount <= 0 then return 0, 0 end
    local input = LUASQUARE_FLUID.GetNetwork(inputName)
    local output = LUASQUARE_FLUID.GetNetwork(outputName)
    if not input then
        print('[LUASQUARE_TURBINE] Unknown input network: ' .. tostring(inputName))
        return 0, 0
    end

    if not output then
        print('[LUASQUARE_TURBINE] Unknown condenser output network: ' .. tostring(outputName))
        return 0, 0
    end

    local ratio = math.max(waterRatio, 0.0001)
    local removed, inputTemperature, thermalKJ
    if LUASQUARE_FLUID.RemoveSteam and input.fluidType == 'steam' then
        removed, inputTemperature, thermalKJ = LUASQUARE_FLUID.RemoveSteam(inputName, amount)
    else
        removed = LUASQUARE_FLUID.RemoveFluid(inputName, amount)
        inputTemperature = input.temperature
        thermalKJ = 0
    end
    local waterMade = removed / ratio
    local added = LUASQUARE_FLUID.AddFluid(outputName, waterMade, outputTemperature or inputTemperature)
    if added < waterMade then
        local returned = (waterMade - added) * ratio
        if LUASQUARE_FLUID.AddSteam and input.fluidType == 'steam' then
            LUASQUARE_FLUID.AddSteam(inputName, returned, inputTemperature, thermalKJ * (returned / math.max(removed, 0.0001)), 1, 0)
        else
            LUASQUARE_FLUID.AddFluid(inputName, returned, inputTemperature)
        end
        waterMade = added
        removed = added * ratio
    end

    return removed, waterMade, thermalKJ
end

function LUASQUARE_TURBINE.MoveSteamToInternalExhaust(turbine, amount, input, condenserName)
    if not LUASQUARE_FLUID or amount <= 0 then return 0, 0, 0 end
    local removed, inputTemperature, thermalKJ, quality, wetCarryover
    if LUASQUARE_FLUID.RemoveSteam and input and input.fluidType == 'steam' then
        removed, inputTemperature, thermalKJ, quality, wetCarryover = LUASQUARE_FLUID.RemoveSteam(turbine.input, amount)
    else
        removed = LUASQUARE_FLUID.RemoveFluid(turbine.input, amount)
        inputTemperature = input and input.temperature or turbine.exhaustTemperature
        thermalKJ = 0
        quality = 1
        wetCarryover = 0
    end
    local exhaustMade = removed * math.max(turbine.exhaustRatio, 0) / math.max(turbine.steamRatio, 0.0001)
    local stored = LUASQUARE_TURBINE.AddInternalExhaust(turbine, exhaustMade, inputTemperature or turbine.exhaustTemperature)
    if stored < exhaustMade then
        local returned = (exhaustMade - stored) * math.max(turbine.steamRatio, 0.0001) / math.max(turbine.exhaustRatio, 0.0001)
        if LUASQUARE_FLUID.AddSteam and input and input.fluidType == 'steam' then
            LUASQUARE_FLUID.AddSteam(turbine.input, returned, inputTemperature, thermalKJ * (returned / math.max(removed, 0.0001)), quality, wetCarryover)
        else
            LUASQUARE_FLUID.AddFluid(turbine.input, returned, inputTemperature)
        end
        removed = math.max(removed - returned, 0)
        exhaustMade = stored
        thermalKJ = thermalKJ * (removed / math.max(removed + returned, 0.0001))
    end

    local oldCondenser = turbine.condenser
    turbine.condenser = condenserName or turbine.condenser
    local accepted = LUASQUARE_TURBINE.PushStoredExhaust(turbine, LUASQUARE_TURBINE.TickInterval)
    turbine.condenser = oldCondenser
    return removed, exhaustMade, accepted, thermalKJ, quality, wetCarryover
end

function LUASQUARE_TURBINE.GetFlowRequest(turbine, input, output, valve, maxSteamRate, dt)
    if valve <= 0 or maxSteamRate <= 0 then return 0 end
    local inputPressure = LUASQUARE_TURBINE.GetNetworkPressure(input)
    local outputPressure = LUASQUARE_TURBINE.GetNetworkPressure(output)
    local pressureDelta = inputPressure - outputPressure
    if pressureDelta <= 0 then return 0 end

    local ratedDelta = turbine.ratedPressureDelta or input.maxPressure or inputPressure
    local pressureScale = math.Clamp(pressureDelta / math.max(ratedDelta, 0.0001), 0, 1)
    return maxSteamRate * valve * pressureScale * dt
end

function LUASQUARE_TURBINE.GetCondenserFlowRequest(turbine, input, output, valve, maxSteamRate, dt)
    if valve <= 0 or maxSteamRate <= 0 then return 0 end
    local inputPressure = LUASQUARE_TURBINE.GetNetworkPressure(input)
    if inputPressure <= 0 then return 0 end

    local ratedPressure = turbine.ratedInletPressure or input.maxPressure or inputPressure
    local pressureScale = math.Clamp(inputPressure / math.max(ratedPressure, 0.0001), 0, 1)
    local outputFree = math.max((output.hardMaxAmount or output.maxAmount) - output.amount, 0)
    return math.min(maxSteamRate * valve * pressureScale * dt, outputFree * LUASQUARE_TURBINE.GetCondenserWaterRatio(turbine))
end

function LUASQUARE_TURBINE.GetCondenserWaterRatio(turbine)
    return math.max(turbine.steamRatio, 0.0001) * math.max(turbine.condenserRatio, 0.0001) / math.max(turbine.exhaustRatio, 0.0001)
end

function LUASQUARE_TURBINE.ResetFlowTelemetry(turbine)
    turbine.lastSteamUsed = 0
    turbine.lastBypassSteam = 0
    turbine.lastInletSteam = 0
    turbine.lastInletPressureScale = 0
    turbine.lastExhaustMade = 0
    turbine.lastExhaustStored = 0
    turbine.lastCondenserAccepted = 0
    turbine.lastExhaustExtracted = 0
    turbine.lastCondensateMade = 0
    turbine.lastBypassCondensateMade = 0
    turbine.lastFlowLimited = false
    turbine.lastSteamThermalMW = 0
    turbine.lastBypassSteamThermalMW = 0
    turbine.lastSteamQuality = 1
    turbine.lastWetCarryover = 0
end

function LUASQUARE_TURBINE.GetOutputFreeSteam(turbine, output, branch)
    if not output then return 0 end
    local free = math.max((output.hardMaxAmount or output.maxAmount) - output.amount, 0)
    if branch == 'turbine' and turbine.condenserOutput then return free * LUASQUARE_TURBINE.GetCondenserWaterRatio(turbine) end
    if branch == 'bypass' and turbine.bypassCondenserOutput then return free * LUASQUARE_TURBINE.GetCondenserWaterRatio(turbine) end
    return free * math.max(turbine.steamRatio, 0.0001) / math.max(turbine.exhaustRatio, 0.0001)
end

function LUASQUARE_TURBINE.GetInletPressureScale(turbine, input)
    local inputPressure = LUASQUARE_TURBINE.GetNetworkPressure(input)
    if inputPressure <= 0 then return 0 end

    local ratedPressure = turbine.ratedInletPressure or input.maxPressure or inputPressure
    local pressureScale = inputPressure / math.max(ratedPressure, 0.0001)
    return math.Clamp(pressureScale, 0, math.max(turbine.maxPressureFlowScale or 1, 1))
end

function LUASQUARE_TURBINE.GetSharedFlowRequests(turbine, input, turbineOutput, bypassOutput, dt)
    local turbineWeight = 0
    local bypassWeight = 0
    local turbineAvailable = turbineOutput or turbine.condenser
    local bypassAvailable = bypassOutput or turbine.bypassCondenser
    if turbine.valve > 0 and turbineAvailable then turbineWeight = turbine.valve * math.max(turbine.maxSteamRate or 0, 0) end
    if turbine.bypassValve > 0 and bypassAvailable then bypassWeight = turbine.bypassValve * math.max(turbine.bypassMaxSteamRate or 0, 0) end

    local totalWeight = turbineWeight + bypassWeight
    if totalWeight <= 0 then return 0, 0, 0, 0 end

    local pressureScale = LUASQUARE_TURBINE.GetInletPressureScale(turbine, input)
    if pressureScale <= 0 then return 0, 0, 0, pressureScale end

    local inletLimit = math.max(turbine.inletMaxSteamRate or turbine.maxSteamRate or 0, 0) * pressureScale * dt
    local valveDemand = totalWeight * pressureScale * dt
    local requested = math.min(inletLimit, valveDemand, input.amount or inletLimit)
    local turbineRequest = requested * (turbineWeight / totalWeight)
    local bypassRequest = requested * (bypassWeight / totalWeight)

    if turbine.condenser then
        turbineRequest = math.min(turbineRequest, LUASQUARE_TURBINE.GetInternalExhaustFreeSteam(turbine))
    elseif turbineOutput then
        turbineRequest = math.min(turbineRequest, LUASQUARE_TURBINE.GetOutputFreeSteam(turbine, turbineOutput, 'turbine'))
    end
    if turbine.bypassCondenser then
        bypassRequest = math.min(bypassRequest, LUASQUARE_TURBINE.GetInternalExhaustFreeSteam(turbine))
    elseif bypassOutput then
        bypassRequest = math.min(bypassRequest, LUASQUARE_TURBINE.GetOutputFreeSteam(turbine, bypassOutput, 'bypass'))
    end

    return turbineRequest, bypassRequest, requested, pressureScale
end

function LUASQUARE_TURBINE.MoveTurbineBranchSteam(turbine, amount, input)
    if amount <= 0 then return 0 end
    local moved
    local exhaust = 0
    local condensate = 0
    if turbine.condenser then
        local thermalKJ, quality, wetCarryover
        moved, exhaust, _, thermalKJ, quality, wetCarryover = LUASQUARE_TURBINE.MoveSteamToInternalExhaust(turbine, amount, input, turbine.condenser)
        turbine.lastSteamThermalMW = (thermalKJ or 0) / math.max(LUASQUARE_TURBINE.TickInterval, 0.0001) / 1000
        turbine.lastSteamQuality = quality or 1
        turbine.lastWetCarryover = wetCarryover or 0
    elseif turbine.condenserOutput then
        local outputTemperature = LUASQUARE_TURBINE.GetCondensateOutputTemperature(turbine, input, turbine.condenserOutputTemperature, turbine.condenserSteamTemperatureInfluence)
        local thermalKJ
        moved, condensate, thermalKJ = LUASQUARE_TURBINE.CondenseSteamToWater(turbine.input, turbine.condenserOutput, amount, LUASQUARE_TURBINE.GetCondenserWaterRatio(turbine), outputTemperature)
        turbine.lastSteamThermalMW = (thermalKJ or 0) / math.max(LUASQUARE_TURBINE.TickInterval, 0.0001) / 1000
        turbine.lastCondensateTemperature = outputTemperature
    else
        local thermalKJ, quality, wetCarryover
        moved, exhaust, thermalKJ, quality, wetCarryover = LUASQUARE_TURBINE.MoveSteam(turbine.input, turbine.output, amount, turbine.exhaustRatio, turbine.steamRatio)
        turbine.lastSteamThermalMW = (thermalKJ or 0) / math.max(LUASQUARE_TURBINE.TickInterval, 0.0001) / 1000
        turbine.lastSteamQuality = quality or 1
        turbine.lastWetCarryover = wetCarryover or 0
    end

    turbine.lastExhaustMade = exhaust
    turbine.lastCondensateMade = condensate
    return moved
end

function LUASQUARE_TURBINE.MoveBypassBranchSteam(turbine, amount, input)
    if amount <= 0 then return 0 end
    local moved
    local exhaust = 0
    local condensate = 0
    if turbine.bypassCondenser then
        local thermalKJ
        moved, exhaust, _, thermalKJ = LUASQUARE_TURBINE.MoveSteamToInternalExhaust(turbine, amount, input, turbine.bypassCondenser)
        turbine.lastBypassSteamThermalMW = (thermalKJ or 0) / math.max(LUASQUARE_TURBINE.TickInterval, 0.0001) / 1000
    elseif turbine.bypassCondenserOutput then
        local outputTemperature = LUASQUARE_TURBINE.GetCondensateOutputTemperature(turbine, input, turbine.bypassCondenserOutputTemperature, turbine.bypassSteamTemperatureInfluence)
        local thermalKJ
        moved, condensate, thermalKJ = LUASQUARE_TURBINE.CondenseSteamToWater(turbine.input, turbine.bypassCondenserOutput, amount, LUASQUARE_TURBINE.GetCondenserWaterRatio(turbine), outputTemperature)
        turbine.lastBypassSteamThermalMW = (thermalKJ or 0) / math.max(LUASQUARE_TURBINE.TickInterval, 0.0001) / 1000
        turbine.lastBypassCondensateTemperature = outputTemperature
    else
        local thermalKJ
        moved, _, thermalKJ = LUASQUARE_TURBINE.MoveSteam(turbine.input, turbine.bypassOutput, amount, turbine.exhaustRatio, turbine.steamRatio)
        turbine.lastBypassSteamThermalMW = (thermalKJ or 0) / math.max(LUASQUARE_TURBINE.TickInterval, 0.0001) / 1000
    end

    turbine.lastExhaustMade = (turbine.lastExhaustMade or 0) + exhaust
    turbine.lastBypassCondensateMade = condensate
    return moved
end

function LUASQUARE_TURBINE.DoSharedSteamFlow(turbine, dt)
    LUASQUARE_TURBINE.ResetFlowTelemetry(turbine)
    if turbine.tripped or not turbine.enabled then
        LUASQUARE_TURBINE.PushStoredExhaust(turbine, dt)
        turbine.lastExhaustStored = turbine.lastExhaustStored / math.max(dt, 0.0001)
        turbine.lastCondenserAccepted = turbine.lastCondenserAccepted / math.max(dt, 0.0001)
        turbine.lastExhaustExtracted = turbine.lastExhaustExtracted / math.max(dt, 0.0001)
        return 0
    end
    if not LUASQUARE_FLUID then return 0 end
    local input = LUASQUARE_FLUID.GetNetwork(turbine.input)
    if not input then return 0 end

    local turbineOutputName = turbine.condenserOutput or turbine.output
    local bypassOutputName = turbine.bypassCondenserOutput or turbine.bypassOutput
    local turbineOutput = turbineOutputName and LUASQUARE_FLUID.GetNetwork(turbineOutputName) or nil
    local bypassOutput = bypassOutputName and LUASQUARE_FLUID.GetNetwork(bypassOutputName) or nil

    local turbineRequest, bypassRequest, sharedRequest, pressureScale = LUASQUARE_TURBINE.GetSharedFlowRequests(turbine, input, turbineOutput, bypassOutput, dt)
    local turbineMoved = LUASQUARE_TURBINE.MoveTurbineBranchSteam(turbine, turbineRequest, input)
    local bypassMoved = LUASQUARE_TURBINE.MoveBypassBranchSteam(turbine, bypassRequest, input)

    turbine.lastSteamUsed = turbineMoved / math.max(dt, 0.0001)
    turbine.lastBypassSteam = bypassMoved / math.max(dt, 0.0001)
    turbine.lastInletSteam = turbine.lastSteamUsed + turbine.lastBypassSteam
    turbine.lastInletPressureScale = pressureScale or 0
    turbine.lastExhaustMade = turbine.lastExhaustMade / math.max(dt, 0.0001)
    turbine.lastExhaustStored = turbine.lastExhaustStored / math.max(dt, 0.0001)
    turbine.lastCondenserAccepted = turbine.lastCondenserAccepted / math.max(dt, 0.0001)
    turbine.lastExhaustExtracted = turbine.lastExhaustExtracted / math.max(dt, 0.0001)
    turbine.lastCondensateMade = turbine.lastCondensateMade / math.max(dt, 0.0001)
    turbine.lastBypassCondensateMade = turbine.lastBypassCondensateMade / math.max(dt, 0.0001)
    turbine.lastFlowLimited = sharedRequest > 0 and (turbineMoved + bypassMoved) < sharedRequest * 0.99
    return turbine.lastSteamUsed
end

function LUASQUARE_TURBINE.DoBypassFlow(turbine, dt)
    return LUASQUARE_TURBINE.DoSharedSteamFlow(turbine, dt)
end

function LUASQUARE_TURBINE.DoTurbineFlow(turbine, dt)
    return LUASQUARE_TURBINE.DoSharedSteamFlow(turbine, dt)
end

-- =========================================
-- UPDATE
-- =========================================
function LUASQUARE_TURBINE.UpdateRotor(turbine, steamRate, dt)
    local drive = math.Clamp(steamRate / math.max(turbine.ratedSteamRate or turbine.maxSteamRate, 0.0001), 0, 1)
    local freeRunRPM = turbine.designRPM * Lerp(drive, 0, turbine.noLoadOverspeed)
    local targetRPM = freeRunRPM

    if turbine.synced then
        targetRPM = turbine.gridRPM
        turbine.rpm = Lerp(math.Clamp(dt * turbine.inertia, 0, 1), turbine.rpm, targetRPM)
    else
        local accel = (targetRPM - turbine.rpm) / math.max(turbine.inertia, 0.0001)
        local drag = turbine.rpm * turbine.friction * math.max(1 - drive, 0)
        turbine.rpm = math.max(turbine.rpm + (accel - drag) * dt, 0)
    end

    turbine.phase = ((turbine.phase or 0) + ((turbine.rpm - turbine.gridRPM) / 60) * 360 * dt) % 360
    turbine.vibration = math.abs(turbine.rpm - targetRPM) * 0.05 + math.max(turbine.rpm - turbine.designRPM, 0) * 0.1
end

function LUASQUARE_TURBINE.GetBoilerThermalMW(turbine)
    local boiler = turbine.boiler
    if not boiler then return nil end

    if boiler == 'rbmk' then
        if not RBMK then return nil end
        return math.max((RBMK.LastThermalMW or 0) + (RBMK.LastFlashBoilMW or 0), 0)
    end

    if type(boiler) == 'function' then return math.max(tonumber(boiler(turbine)) or 0, 0) end
    if type(boiler) == 'table' then
        return math.max((boiler.LastThermalMW or boiler.lastThermalMW or 0) + (boiler.LastFlashBoilMW or boiler.lastFlashBoilMW or 0), 0)
    end

    return nil
end

function LUASQUARE_TURBINE.GetBoilerSteamUse(turbine)
    if not turbine.boiler then return turbine.lastSteamUsed or 0 end

    local total = 0
    for _, other in pairs(LUASQUARE_TURBINE.Turbines) do
        if other.boiler == turbine.boiler then total = total + math.max(other.lastSteamUsed or 0, 0) end
    end

    return math.max(total, turbine.lastSteamUsed or 0)
end

function LUASQUARE_TURBINE.UpdatePower(turbine)
    if not turbine.synced or turbine.tripped then
        turbine.lastMW = 0
        turbine.lastBoilerMW = 0
        turbine.lastSteamShare = 0
        turbine.lastTurbineSteamFraction = 0
        return
    end

    local boilerMW = LUASQUARE_TURBINE.GetBoilerThermalMW(turbine)
    local rawMW
    if turbine.useSteamEnergy then
        turbine.lastBoilerMW = turbine.lastSteamThermalMW or 0
        turbine.lastSteamShare = 0
        turbine.lastTurbineSteamFraction = math.Clamp((turbine.lastSteamUsed or 0) / math.max(turbine.ratedSteamRate or turbine.maxSteamRate, 0.0001), 0, 1)
        rawMW = (turbine.lastSteamThermalMW or 0) * math.Clamp(turbine.cycleEfficiency or turbine.efficiency or 0.32, 0, 1)
    elseif boilerMW then
        local totalSteamUse = LUASQUARE_TURBINE.GetBoilerSteamUse(turbine)
        local steamShare = totalSteamUse > 0 and math.Clamp((turbine.lastSteamUsed or 0) / totalSteamUse, 0, 1) or 0
        local steamFraction = math.Clamp((turbine.lastSteamUsed or 0) / math.max(turbine.ratedSteamRate or turbine.maxSteamRate, 0.0001), 0, 1)
        turbine.lastBoilerMW = boilerMW
        turbine.lastSteamShare = steamShare
        turbine.lastTurbineSteamFraction = steamFraction
        rawMW = boilerMW * math.Clamp(turbine.cycleEfficiency or turbine.efficiency or 0.32, 0, 1) * math.min(steamShare, steamFraction)
    else
        turbine.lastBoilerMW = 0
        turbine.lastSteamShare = 0
        turbine.lastTurbineSteamFraction = 0
        rawMW = turbine.lastSteamUsed * turbine.mwPerSteamPerSecond * turbine.efficiency
    end

    if turbine.loadMW and turbine.loadMW > 0 then rawMW = math.min(rawMW, turbine.loadMW) end
    turbine.lastMW = math.Clamp(rawMW, 0, turbine.maxMW)
end

function LUASQUARE_TURBINE.UpdateTrips(name, turbine)
    if turbine.tripped then return end
    LUASQUARE_TURBINE.UpdateExhaustPressure(turbine)
    if (turbine.exhaustPressure or 0) >= (turbine.exhaustHardMaxPressure or math.huge) then
        LUASQUARE_TURBINE.ExtremeTrip(name, 'EXHAUST_HARD_PRESSURE')
        return
    end

    if (turbine.exhaustPressure or 0) >= (turbine.exhaustTripPressure or math.huge) then
        turbine.exhaustTripTimer = (turbine.exhaustTripTimer or 0) + LUASQUARE_TURBINE.TickInterval
        if turbine.exhaustTripTimer >= (turbine.exhaustTripDelay or 0) then
            LUASQUARE_TURBINE.Trip(name, 'EXHAUST_BACKPRESSURE', 'normal')
            return
        end
    else
        turbine.exhaustTripTimer = 0
    end

    if turbine.rpm >= turbine.tripRPM then
        LUASQUARE_TURBINE.Trip(name, 'OVERSPEED')
        return
    end

    if turbine.vibration >= turbine.tripVibration then
        LUASQUARE_TURBINE.Trip(name, 'HIGH_VIBRATION')
    end
end

function LUASQUARE_TURBINE.UpdateSevereTrip(name, turbine)
    if not turbine.tripped or turbine.tripLevel ~= 'severe' then return end
    if turbine.tripRelayFired then return end
    if (turbine.rpm or 0) > (turbine.severeTripBrakeRPM or 20) then return end

    turbine.severeTripStopFired = true
    LUASQUARE_TURBINE.FireRelay(turbine.severeTripStopRelay)
    LUASQUARE_TURBINE.FireTripRelay(turbine)
    print('[LUASQUARE_TURBINE] Severe trip braked ' .. tostring(name) .. ' at ' .. string.format('%.1f', turbine.rpm or 0) .. ' RPM')
end

function LUASQUARE_TURBINE.UpdateSoundEffect(turbine)
    if not turbine.soundEntity then return end
    local rpm = turbine.rpm or 0
    local rpmFraction = math.Clamp((turbine.rpm or 0) / math.max(turbine.designRPM, 0.0001), 0, 1.25)

    local shouldPlay = rpm > (turbine.soundStopRPM or 0) and rpmFraction >= turbine.soundStartRPMFraction
    local shouldPlay2 = rpmFraction >= turbine.soundOptimalRPMFraction

    if shouldPlay and not turbine.soundPlaying then
        turbine.soundPlaying = LUASQUARE_TURBINE.FireEnt(turbine.soundEntity, 'PlaySound')
    elseif not shouldPlay and turbine.soundPlaying then
        LUASQUARE_TURBINE.FireEnt(turbine.soundEntity, 'StopSound')
        turbine.soundPlaying = false
    end

    if turbine.soundEntity2 then
        if shouldPlay2 and not turbine.sound2Playing then
            LUASQUARE_TURBINE.FireEnt(turbine.soundEntity2, 'PlaySound')
            turbine.sound2Playing = true
        elseif not shouldPlay2 and turbine.sound2Playing then
            LUASQUARE_TURBINE.FireEnt(turbine.soundEntity2, 'StopSound')
            turbine.sound2Playing = false
        end
    end

    if not shouldPlay then return end
    local volume = math.Clamp(Lerp(math.Clamp(rpmFraction, 0, 1), turbine.soundMinVolume, turbine.soundMaxVolume), 0, 10)
    local pitch = math.Clamp(Lerp(math.Clamp(rpmFraction, 0, 1), turbine.soundMinPitch, turbine.soundMaxPitch), 1, 255)
    LUASQUARE_TURBINE.FireEnt(turbine.soundEntity, 'Volume', tostring(volume))
    LUASQUARE_TURBINE.FireEnt(turbine.soundEntity, 'Pitch', tostring(pitch))
    if not shouldPlay2 then return end
    LUASQUARE_TURBINE.FireEnt(turbine.soundEntity2, 'Volume', tostring(volume))
    LUASQUARE_TURBINE.FireEnt(turbine.soundEntity2, 'Pitch', tostring(pitch))
end

function LUASQUARE_TURBINE.UpdateShakeEffect(turbine)
    if not turbine.shakeEntity then return end
    local vibration = turbine.vibration or 0
    local shouldShake = (turbine.rpm or 0) > 0 and vibration >= turbine.shakeStartVibration
    if not shouldShake then
        turbine.nextShakeTime = 0
        if turbine.shakeActive then
            LUASQUARE_TURBINE.FireEnt(turbine.shakeEntity, 'StopShake')
            turbine.shakeActive = false
        end
        return
    end

    local vibrationScale = math.Clamp(vibration / math.max(turbine.tripVibration, 0.0001), 0, 1)
    local amplitude = Lerp(vibrationScale, turbine.shakeMinAmplitude, turbine.shakeMaxAmplitude)
    local frequency = Lerp(vibrationScale, turbine.shakeMinFrequency, turbine.shakeMaxFrequency)
    LUASQUARE_TURBINE.FireEnt(turbine.shakeEntity, 'Amplitude', tostring(amplitude))
    LUASQUARE_TURBINE.FireEnt(turbine.shakeEntity, 'Frequency', tostring(frequency))

    local now = LUASQUARE_TURBINE.GetTime()
    if now >= (turbine.nextShakeTime or 0) then
        turbine.shakeActive = LUASQUARE_TURBINE.FireEnt(turbine.shakeEntity, 'StartShake') or turbine.shakeActive
        turbine.nextShakeTime = now + math.max(turbine.shakeRepeatInterval or 2, 0.1)
    end
end

function LUASQUARE_TURBINE.ClearShakeEffect(turbine)
    if not turbine.shakeEntity then return end
    if turbine.shakeActive then
        LUASQUARE_TURBINE.FireEnt(turbine.shakeEntity, 'StopShake')
    end
    turbine.shakeActive = false
    turbine.nextShakeTime = 0
end

function LUASQUARE_TURBINE.UpdateEffects(turbine)
    LUASQUARE_TURBINE.UpdateSoundEffect(turbine)
    LUASQUARE_TURBINE.UpdateShakeEffect(turbine)
end

function LUASQUARE_TURBINE.UpdateTurbine(name, dt, skipPower)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then return end

    local steamRate = LUASQUARE_TURBINE.DoSharedSteamFlow(turbine, dt)
    LUASQUARE_TURBINE.UpdateRotor(turbine, steamRate, dt)
    if turbine.autoSync and not turbine.generator and not turbine.synced and LUASQUARE_TURBINE.CanSync(turbine) then LUASQUARE_TURBINE.Sync(name) end
    if skipPower then return end

    LUASQUARE_TURBINE.UpdatePower(turbine)
    LUASQUARE_TURBINE.UpdateTrips(name, turbine)
    LUASQUARE_TURBINE.UpdateSevereTrip(name, turbine)
    LUASQUARE_TURBINE.UpdateEffects(turbine)
end

function LUASQUARE_TURBINE.UpdateAll()
    local dt = LUASQUARE_TURBINE.TickInterval
    for name, _ in pairs(LUASQUARE_TURBINE.Turbines) do
        LUASQUARE_TURBINE.UpdateTurbine(name, dt, true)
    end

    for name, turbine in pairs(LUASQUARE_TURBINE.Turbines) do
        LUASQUARE_TURBINE.UpdatePower(turbine)
        LUASQUARE_TURBINE.UpdateTrips(name, turbine)
        LUASQUARE_TURBINE.UpdateSevereTrip(name, turbine)
        LUASQUARE_TURBINE.UpdateEffects(turbine)
    end
end

function LUASQUARE_TURBINE.Start()
    if timer.Exists('LUASQUARE_TURBINE_UpdateTimer') then timer.Remove('LUASQUARE_TURBINE_UpdateTimer') end
    timer.Create('LUASQUARE_TURBINE_UpdateTimer', LUASQUARE_TURBINE.TickInterval, 0, function() LUASQUARE_TURBINE.UpdateAll() end)
    print('[LUASQUARE_TURBINE] Started')
end

function LUASQUARE_TURBINE.Stop()
    if timer.Exists('LUASQUARE_TURBINE_UpdateTimer') then timer.Remove('LUASQUARE_TURBINE_UpdateTimer') end
    for _, turbine in pairs(LUASQUARE_TURBINE.Turbines) do
        if turbine.soundPlaying then LUASQUARE_TURBINE.FireEnt(turbine.soundEntity, 'StopSound') end
        LUASQUARE_TURBINE.ClearShakeEffect(turbine)
        turbine.soundPlaying = false
    end
    print('[LUASQUARE_TURBINE] Stopped')
end

print('[LUASQUARE_TURBINE] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- LUASQUARE_TURBINE.RegisterTurbine('tg1', {
--     input = 'main_steam',
--     condenserOutput = 'hotwell',
--     bypassCondenserOutput = 'hotwell',
--     maxSteamRate = 1000,
--     valve = 0,
--     bypassValve = 0,
--     enabled = true,
--     soundEntity = 'tg1_loop',
--     shakeEntity = 'tg1_shake',
--     monitorPos = Vector(0, 0, 128)
-- })
-- LUASQUARE_TURBINE.AdjustValvePercent('tg1', 1)
-- LUASQUARE_TURBINE.AdjustBypassValvePercent('tg1', -1)
-- Use LUASQUARE_POWERGENERATOR.Sync('tg1_generator') for grid-connected turbine generators.
-- LUASQUARE_TURBINE.Start()
