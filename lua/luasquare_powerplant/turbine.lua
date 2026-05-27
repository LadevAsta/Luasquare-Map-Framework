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
        ratedInletPressure = tonumber(data.ratedInletPressure),
        ratedPressureDelta = tonumber(data.ratedPressureDelta),
        steamRatio = tonumber(data.steamRatio) or 1600,
        exhaustRatio = tonumber(data.exhaustRatio) or 400,
        condenserRatio = tonumber(data.condenserRatio) or tonumber(data.exhaustRatio) or 400,
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
        resetRelay = data.resetRelay,
        soundEntity = data.soundEntity,
        soundEntity2 = data.soundEntity2,
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
        lastExhaustMade = 0,
        lastCondensateMade = 0,
        lastBypassCondensateMade = 0,
        lastCondensateTemperature = tonumber(data.condenserOutputTemperature) or 80,
        lastBypassCondensateTemperature = tonumber(data.bypassCondenserOutputTemperature) or tonumber(data.condenserOutputTemperature) or 95,
        lastBoilerMW = 0,
        lastSteamShare = 0,
        lastMW = 0,
        lastFlowLimited = false,
        tripReason = nil,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
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

function LUASQUARE_TURBINE.Trip(name, reason)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    if turbine.tripped then return true end
    turbine.tripped = true
    turbine.synced = false
    turbine.enabled = false
    turbine.bypassValve = 0
    turbine.valve = 0
    turbine.tripReason = reason or 'UNKNOWN'
    if turbine.generator and LUASQUARE_POWERGENERATOR then
        local generator = LUASQUARE_POWERGENERATOR.GetGenerator(turbine.generator)
        if generator and not generator.tripped then LUASQUARE_POWERGENERATOR.Trip(turbine.generator, turbine.tripReason) end
    end
    LUASQUARE_TURBINE.FireRelay(turbine.tripRelay)
    print('[LUASQUARE_TURBINE] Trip ' .. tostring(name) .. ': ' .. tostring(turbine.tripReason))
    return true
end

function LUASQUARE_TURBINE.ResetTrip(name)
    local turbine = LUASQUARE_TURBINE.GetTurbine(name)
    if not turbine then
        print('[LUASQUARE_TURBINE] Unknown turbine: ' .. tostring(name))
        return false
    end

    turbine.tripped = false
    turbine.tripReason = nil
    turbine.enabled = true
    if turbine.generator and LUASQUARE_POWERGENERATOR then
        local generator = LUASQUARE_POWERGENERATOR.GetGenerator(turbine.generator)
        if generator and generator.tripped then LUASQUARE_POWERGENERATOR.ResetTrip(turbine.generator) end
    end
    LUASQUARE_TURBINE.FireRelay(turbine.resetRelay)
    return true
end

function LUASQUARE_TURBINE.GetPhaseError(turbine)
    local phase = ((turbine.phase or 0) + 180) % 360 - 180
    return phase
end

function LUASQUARE_TURBINE.CanSync(turbine)
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

    local removed = LUASQUARE_FLUID.RemoveFluid(inputName, amount)
    local exhaustMade = removed * math.max(exhaustRatio, 0) / math.max(steamRatio, 0.0001)
    local added = LUASQUARE_FLUID.AddFluid(outputName, exhaustMade, input.temperature)
    if added < exhaustMade then
        local returned = (exhaustMade - added) * math.max(steamRatio, 0.0001) / math.max(exhaustRatio, 0.0001)
        LUASQUARE_FLUID.AddFluid(inputName, returned, input.temperature)
        removed = math.max(removed - returned, 0)
        exhaustMade = added
    end

    return removed, exhaustMade
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
    local removed = LUASQUARE_FLUID.RemoveFluid(inputName, amount)
    local waterMade = removed / ratio
    local added = LUASQUARE_FLUID.AddFluid(outputName, waterMade, outputTemperature or input.temperature)
    if added < waterMade then
        LUASQUARE_FLUID.AddFluid(inputName, (waterMade - added) * ratio, input.temperature)
        waterMade = added
        removed = added * ratio
    end

    return removed, waterMade
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

function LUASQUARE_TURBINE.DoBypassFlow(turbine, dt)
    turbine.lastBypassSteam = 0
    turbine.lastBypassCondensateMade = 0
    if (not turbine.bypassOutput and not turbine.bypassCondenserOutput) or turbine.bypassValve <= 0 then return end
    if not LUASQUARE_FLUID then return end
    local input = LUASQUARE_FLUID.GetNetwork(turbine.input)
    local outputName = turbine.bypassCondenserOutput or turbine.bypassOutput
    local output = LUASQUARE_FLUID.GetNetwork(outputName)
    if not input or not output then return end

    local requested
    local moved
    local condensate = 0
    if turbine.bypassCondenserOutput then
        requested = LUASQUARE_TURBINE.GetCondenserFlowRequest(turbine, input, output, turbine.bypassValve, turbine.bypassMaxSteamRate, dt)
        local outputTemperature = LUASQUARE_TURBINE.GetCondensateOutputTemperature(turbine, input, turbine.bypassCondenserOutputTemperature, turbine.bypassSteamTemperatureInfluence)
        moved, condensate = LUASQUARE_TURBINE.CondenseSteamToWater(turbine.input, turbine.bypassCondenserOutput, requested, LUASQUARE_TURBINE.GetCondenserWaterRatio(turbine), outputTemperature)
        turbine.lastBypassCondensateTemperature = outputTemperature
    else
        requested = LUASQUARE_TURBINE.GetFlowRequest(turbine, input, output, turbine.bypassValve, turbine.bypassMaxSteamRate, dt)
        moved = LUASQUARE_TURBINE.MoveSteam(turbine.input, turbine.bypassOutput, requested, turbine.exhaustRatio, turbine.steamRatio)
    end
    turbine.lastBypassSteam = moved / math.max(dt, 0.0001)
    turbine.lastBypassCondensateMade = condensate / math.max(dt, 0.0001)
end

function LUASQUARE_TURBINE.DoTurbineFlow(turbine, dt)
    turbine.lastSteamUsed = 0
    turbine.lastExhaustMade = 0
    turbine.lastCondensateMade = 0
    turbine.lastFlowLimited = false
    if turbine.tripped or not turbine.enabled then return 0 end
    if not LUASQUARE_FLUID then return 0 end
    local input = LUASQUARE_FLUID.GetNetwork(turbine.input)
    local outputName = turbine.condenserOutput or turbine.output
    local output = LUASQUARE_FLUID.GetNetwork(outputName)
    if not input or not output then return 0 end

    local requested
    local moved
    local exhaust = 0
    local condensate = 0
    if turbine.condenserOutput then
        requested = LUASQUARE_TURBINE.GetCondenserFlowRequest(turbine, input, output, turbine.valve, turbine.maxSteamRate, dt)
        local outputTemperature = LUASQUARE_TURBINE.GetCondensateOutputTemperature(turbine, input, turbine.condenserOutputTemperature, turbine.condenserSteamTemperatureInfluence)
        moved, condensate = LUASQUARE_TURBINE.CondenseSteamToWater(turbine.input, turbine.condenserOutput, requested, LUASQUARE_TURBINE.GetCondenserWaterRatio(turbine), outputTemperature)
        turbine.lastCondensateTemperature = outputTemperature
    else
        requested = LUASQUARE_TURBINE.GetFlowRequest(turbine, input, output, turbine.valve, turbine.maxSteamRate, dt)
        moved, exhaust = LUASQUARE_TURBINE.MoveSteam(turbine.input, turbine.output, requested, turbine.exhaustRatio, turbine.steamRatio)
    end
    turbine.lastSteamUsed = moved / math.max(dt, 0.0001)
    turbine.lastExhaustMade = exhaust / math.max(dt, 0.0001)
    turbine.lastCondensateMade = condensate / math.max(dt, 0.0001)
    turbine.lastFlowLimited = requested > 0 and moved < requested * 0.99
    return turbine.lastSteamUsed
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
        return
    end

    local boilerMW = LUASQUARE_TURBINE.GetBoilerThermalMW(turbine)
    local rawMW
    if boilerMW then
        local totalSteamUse = LUASQUARE_TURBINE.GetBoilerSteamUse(turbine)
        local steamShare = totalSteamUse > 0 and math.Clamp((turbine.lastSteamUsed or 0) / totalSteamUse, 0, 1) or 0
        turbine.lastBoilerMW = boilerMW
        turbine.lastSteamShare = steamShare
        rawMW = boilerMW * math.Clamp(turbine.cycleEfficiency or turbine.efficiency or 0.32, 0, 1) * steamShare
    else
        turbine.lastBoilerMW = 0
        turbine.lastSteamShare = 0
        rawMW = turbine.lastSteamUsed * turbine.mwPerSteamPerSecond * turbine.efficiency
    end

    if turbine.loadMW and turbine.loadMW > 0 then rawMW = math.min(rawMW, turbine.loadMW) end
    turbine.lastMW = math.Clamp(rawMW, 0, turbine.maxMW)
end

function LUASQUARE_TURBINE.UpdateTrips(name, turbine)
    if turbine.tripped then return end
    if turbine.rpm >= turbine.tripRPM then
        LUASQUARE_TURBINE.Trip(name, 'OVERSPEED')
        return
    end

    if turbine.vibration >= turbine.tripVibration then
        LUASQUARE_TURBINE.Trip(name, 'HIGH_VIBRATION')
    end
end

function LUASQUARE_TURBINE.UpdateSoundEffect(turbine)
    if not turbine.soundEntity then return end
    local rpmFraction = math.Clamp((turbine.rpm or 0) / math.max(turbine.designRPM, 0.0001), 0, 1.25)

    local shouldPlay = rpmFraction >= turbine.soundStartRPMFraction and not turbine.tripped
    local shouldPlay2 = rpmFraction >= turbine.soundOptimalRPMFraction and not turbine.tripped

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
    local shouldShake = vibration >= turbine.shakeStartVibration and not turbine.tripped
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

    LUASQUARE_TURBINE.DoBypassFlow(turbine, dt)
    local steamRate = LUASQUARE_TURBINE.DoTurbineFlow(turbine, dt)
    LUASQUARE_TURBINE.UpdateRotor(turbine, steamRate, dt)
    if turbine.autoSync and not turbine.generator and not turbine.synced and LUASQUARE_TURBINE.CanSync(turbine) then LUASQUARE_TURBINE.Sync(name) end
    if skipPower then return end

    LUASQUARE_TURBINE.UpdatePower(turbine)
    LUASQUARE_TURBINE.UpdateTrips(name, turbine)
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
