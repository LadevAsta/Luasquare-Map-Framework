if LUASQUARE_PUMP_CORE_LOADED then return end
LUASQUARE_PUMP_CORE_LOADED = true
LUASQUARE_PUMP = LUASQUARE_PUMP or {}
LUASQUARE_PUMP.Pumps = LUASQUARE_PUMP.Pumps or {}
LUASQUARE_PUMP.TickInterval = LUASQUARE_PUMP.TickInterval or 0.1

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_PUMP.RegisterPump(name, data)
    data = data or {}
    local speedLevels = data.speedLevels or {0, 0.25, 0.5, 0.75, 1}
    local speedLevel = tonumber(data.speedLevel)
    if speedLevel == nil then
        if data.enabled then speedLevel = #speedLevels else speedLevel = 1 end
    end
    local peakMW = tonumber(data.peakMW)
    local breaker = data.breaker or data.powerBreaker or (peakMW and (name .. '_breaker') or nil)
    LUASQUARE_PUMP.Pumps[name] = {
        name = name,
        source = data.source,
        target = data.target,
        rate = tonumber(data.rate) or 1,
        headPressure = tonumber(data.headPressure) or 0,
        enabled = data.enabled and true or false,
        speedLevels = speedLevels,
        speedLevel = math.Clamp(speedLevel, 1, #speedLevels),
        flowMultiplier = tonumber(data.flowMultiplier) or 1,
        minFlowFraction = math.Clamp(tonumber(data.minFlowFraction) or 0, 0, 1),
        regulate = data.regulate and true or false,
        regulationMode = data.regulationMode or 'fill',
        regulationSensor = data.regulationSensor,
        regulationTarget = tonumber(data.regulationTarget) or tonumber(data.targetPercent),
        regulationDeadband = tonumber(data.regulationDeadband) or 0.5,
        regulationGain = tonumber(data.regulationGain) or 0.1,
        regulationMinOutput = math.Clamp(tonumber(data.regulationMinOutput) or 0, 0, 1),
        regulationFactor = 1,
        regulationLevel = 0,
        grid = data.grid or data.powerGrid,
        breaker = breaker,
        peakMW = peakMW,
        lastPowerMW = 0,
        lastPowerAcceptedMW = 0,
        lastFlow = 0,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }

    if peakMW and LUASQUARE_POWERGRID and not LUASQUARE_POWERGRID.GetBreaker(breaker) then
        LUASQUARE_POWERGRID.RegisterBreaker(breaker, {
            grid = data.grid or data.powerGrid,
            owner = name,
            kind = 'pump',
            closed = data.breakerClosed ~= false,
            maxMW = tonumber(data.breakerMaxMW) or peakMW,
            monitorPos = data.breakerMonitorPos,
            monitorTarget = data.breakerMonitorTarget,
            monitorOffset = data.breakerMonitorOffset
        })
    end
end

function LUASQUARE_PUMP.GetPump(name)
    return LUASQUARE_PUMP.Pumps[name]
end

function LUASQUARE_PUMP.SetPump(name, enabled)
    local pump = LUASQUARE_PUMP.GetPump(name)
    if not pump then
        print('[LUASQUARE_PUMP] Unknown pump: ' .. tostring(name))
        return false
    end

    pump.enabled = enabled and true or false
    if pump.enabled and (pump.speedLevels[pump.speedLevel] or 0) <= 0 then pump.speedLevel = #pump.speedLevels end
    if not pump.enabled then pump.lastFlow = 0 end
    return true
end

function LUASQUARE_PUMP.SetPumpSpeed(name, level)
    local pump = LUASQUARE_PUMP.GetPump(name)
    if not pump then
        print('[LUASQUARE_PUMP] Unknown pump: ' .. tostring(name))
        return false
    end

    pump.speedLevel = math.Clamp(math.floor(tonumber(level) or 1), 1, #pump.speedLevels)
    pump.enabled = (pump.speedLevels[pump.speedLevel] or 0) > 0
    if not pump.enabled then pump.lastFlow = 0 end
    return true
end

function LUASQUARE_PUMP.GetPumpSpeedMultiplier(pump)
    return pump.speedLevels[pump.speedLevel] or 0
end

function LUASQUARE_PUMP.ApplyPowerLoad(pump, speedMultiplier)
    pump.lastPowerMW = 0
    pump.lastPowerAcceptedMW = 0
    if not pump.peakMW then return speedMultiplier end
    if speedMultiplier <= 0 then return 0 end
    if not LUASQUARE_POWERGRID then return 0 end

    local requestedMW = math.max(pump.peakMW * speedMultiplier, 0)
    if requestedMW <= 0 then return 0 end

    local acceptedMW = LUASQUARE_POWERGRID.SubmitLoad(pump.grid, pump.name, requestedMW, pump.breaker)
    pump.lastPowerMW = requestedMW
    pump.lastPowerAcceptedMW = acceptedMW
    if acceptedMW <= 0 then return 0 end
    return speedMultiplier * math.Clamp(acceptedMW / math.max(requestedMW, 0.0001), 0, 1)
end

function LUASQUARE_PUMP.SetRegulationTarget(name, percent)
    local pump = LUASQUARE_PUMP.GetPump(name)
    if not pump then
        print('[LUASQUARE_PUMP] Unknown pump: ' .. tostring(name))
        return false
    end

    pump.regulationTarget = math.Clamp(tonumber(percent) or 0, 0, 100)
    pump.regulate = true
    return true
end

function LUASQUARE_PUMP.SetRegulationEnabled(name, enabled)
    local pump = LUASQUARE_PUMP.GetPump(name)
    if not pump then
        print('[LUASQUARE_PUMP] Unknown pump: ' .. tostring(name))
        return false
    end

    pump.regulate = enabled and true or false
    pump.regulationFactor = pump.regulate and pump.regulationFactor or 1
    return true
end

function LUASQUARE_PUMP.GetEndpointLevelPercent(endpoint)
    if endpoint == 'rbmk' or endpoint == 'rbmk_water' or endpoint == 'rbmk_water_percent' then
        if not RBMK or not RBMK.MaxWater or RBMK.MaxWater <= 0 then return 0 end
        return math.Clamp(((RBMK.Water or 0) / RBMK.MaxWater) * 100, 0, 100)
    end

    local network = LUASQUARE_FLUID and LUASQUARE_FLUID.GetNetwork(endpoint)
    if network then return math.Clamp((network.amount or 0) / math.max(network.maxAmount or 1, 0.0001) * 100, 0, 100) end

    local tower = LUASQUARE_COOLINGTOWER and LUASQUARE_COOLINGTOWER.GetCoolingTower(endpoint)
    if tower then return math.Clamp((tower.basinAmount or 0) / math.max(tower.basinMaxAmount or 1, 0.0001) * 100, 0, 100) end

    local deaerator = LUASQUARE_DEAERATOR and LUASQUARE_DEAERATOR.GetDeaerator(endpoint)
    if deaerator then return LUASQUARE_DEAERATOR.GetLevelPercent(endpoint) end

    local separator = LUASQUARE_STEAMSEPARATOR and LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(endpoint)
    if separator then return LUASQUARE_STEAMSEPARATOR.GetLevelPercent(endpoint) end

    return 0
end

function LUASQUARE_PUMP.GetRegulationSensorLevel(pump)
    local sensor = pump.regulationSensor
    if sensor == 'source' then sensor = pump.source end
    if sensor == 'target' then sensor = pump.target end
    sensor = sensor or (pump.regulationMode == 'drain' and pump.source or pump.target)
    return LUASQUARE_PUMP.GetEndpointLevelPercent(sensor)
end

function LUASQUARE_PUMP.GetRegulationFactor(pump)
    if not pump.regulate or not pump.regulationTarget then
        pump.regulationFactor = 1
        return 1
    end

    local level = LUASQUARE_PUMP.GetRegulationSensorLevel(pump)
    pump.regulationLevel = level
    local target = pump.regulationTarget
    local deadband = pump.regulationDeadband or 0
    local error
    if pump.regulationMode == 'drain' then
        error = level - target
    else
        error = target - level
    end

    if error <= deadband then
        pump.regulationFactor = 0
        return 0
    end

    local factor = math.Clamp((error - deadband) * (pump.regulationGain or 0.1), 0, 1)
    if factor > 0 and pump.regulationMinOutput > 0 then factor = math.max(factor, pump.regulationMinOutput) end
    pump.regulationFactor = factor
    return factor
end

function LUASQUARE_PUMP.GetTargetPressure(target)
    if target == 'rbmk' then
        if not RBMK then return 0 end
        return RBMK.RPVPressure or 0
    end

    local network = LUASQUARE_FLUID and LUASQUARE_FLUID.GetNetwork(target)
    if not network then
        if LUASQUARE_COOLINGTOWER and LUASQUARE_COOLINGTOWER.GetCoolingTower(target) then
            return LUASQUARE_COOLINGTOWER.GetBasinPressure(target)
        end
        if LUASQUARE_DEAERATOR and LUASQUARE_DEAERATOR.GetDeaerator(target) then
            local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(target)
            LUASQUARE_DEAERATOR.UpdatePressure(deaerator)
            return deaerator.pressure or 0
        end
        if target == 'rbmk_recirc' then
            if not RBMK then return 0 end
            return RBMK.RPVPressure or 0
        end
        if LUASQUARE_STEAMSEPARATOR and LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(target) then
            return LUASQUARE_STEAMSEPARATOR.GetPressure(target)
        end
        return 0
    end
    return network.pressure or 0
end

function LUASQUARE_PUMP.AddToTarget(target, amount, dischargePressure, temperature)
    if target == 'rbmk' then
        if not RBMK or not RBMK.AddWaterFromPump then return 0 end
        return RBMK.AddWaterFromPump(amount, dischargePressure, temperature)
    end

    if LUASQUARE_COOLINGTOWER and LUASQUARE_COOLINGTOWER.GetCoolingTower(target) then
        return LUASQUARE_COOLINGTOWER.AddToBasin(target, amount, temperature)
    end

    if LUASQUARE_DEAERATOR and LUASQUARE_DEAERATOR.GetDeaerator(target) then
        return LUASQUARE_DEAERATOR.AddWater(target, amount, temperature)
    end

    if target == 'rbmk_recirc' then
        if not RBMK or not RBMK.AddRecirculationWater then return 0 end
        return RBMK.AddRecirculationWater(amount, dischargePressure, temperature)
    end

    if LUASQUARE_STEAMSEPARATOR and LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(target) then
        return LUASQUARE_STEAMSEPARATOR.AddWater(target, amount, temperature)
    end

    if not LUASQUARE_FLUID then return 0 end
    return LUASQUARE_FLUID.AddFluid(target, amount, temperature)
end

function LUASQUARE_PUMP.GetSourceEndpoint(sourceName)
    if sourceName == 'service' or sourceName == 'makeup' or sourceName == 'void' then
        return {
            amount = math.huge,
            pressure = 0,
            temperature = 20,
            remove = function(amount) return math.max(tonumber(amount) or 0, 0) end,
            addBack = function() return 0 end
        }
    end

    if LUASQUARE_FLUID then
        local network = LUASQUARE_FLUID.GetNetwork(sourceName)
        if network then
            return {
                amount = network.amount or 0,
                pressure = network.pressure or 0,
                temperature = network.temperature or 20,
                remove = function(amount) return LUASQUARE_FLUID.RemoveFluid(sourceName, amount) end,
                addBack = function(amount, temperature) return LUASQUARE_FLUID.AddFluid(sourceName, amount, temperature) end
            }
        end
    end

    if LUASQUARE_DEAERATOR and LUASQUARE_DEAERATOR.GetDeaerator(sourceName) then
        local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(sourceName)
        return {
            amount = deaerator.amount or 0,
            pressure = deaerator.pressure or 0,
            temperature = deaerator.temperature or 20,
            remove = function(amount) return LUASQUARE_DEAERATOR.RemoveWater(sourceName, amount) end,
            addBack = function(amount, temperature) return LUASQUARE_DEAERATOR.AddWater(sourceName, amount, temperature) end
        }
    end

    if LUASQUARE_STEAMSEPARATOR and LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(sourceName) then
        local separator = LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(sourceName)
        return {
            amount = separator.waterAmount or 0,
            pressure = separator.pressure or 0,
            temperature = separator.waterTemperature or 100,
            remove = function(amount) return LUASQUARE_STEAMSEPARATOR.RemoveWater(sourceName, amount) end,
            addBack = function(amount, temperature) return LUASQUARE_STEAMSEPARATOR.AddWater(sourceName, amount, temperature) end
        }
    end

    return nil
end

-- =========================================
-- UPDATE
-- =========================================
function LUASQUARE_PUMP.UpdatePump(name, dt)
    local pump = LUASQUARE_PUMP.GetPump(name)
    if not pump then return end
    if not pump.enabled then
        pump.lastFlow = 0
        pump.lastPowerMW = 0
        pump.lastPowerAcceptedMW = 0
        return
    end
    if not LUASQUARE_FLUID then return end
    pump.lastFlow = 0
    local speedMultiplier = LUASQUARE_PUMP.GetPumpSpeedMultiplier(pump) * LUASQUARE_PUMP.GetRegulationFactor(pump)
    speedMultiplier = LUASQUARE_PUMP.ApplyPowerLoad(pump, speedMultiplier)
    if speedMultiplier <= 0 then return end

    local source = LUASQUARE_PUMP.GetSourceEndpoint(pump.source)
    if not source then
        print('[LUASQUARE_PUMP] Unknown source endpoint: ' .. tostring(pump.source))
        return
    end

    local dischargePressure = (source.pressure or 0) + pump.headPressure
    local targetPressure = LUASQUARE_PUMP.GetTargetPressure(pump.target)
    if dischargePressure <= targetPressure then return end

    local pressureScale = math.Clamp((dischargePressure - targetPressure) / math.max(dischargePressure, 0.0001), 0, 1)
    if pressureScale > 0 and pump.minFlowFraction > 0 then pressureScale = math.max(pressureScale, pump.minFlowFraction) end
    local requested = pump.rate * dt * pressureScale * pump.flowMultiplier * speedMultiplier
    local removed = source.remove(requested)
    local added = LUASQUARE_PUMP.AddToTarget(pump.target, removed, dischargePressure, source.temperature)
    if added < removed then source.addBack(removed - added, source.temperature) end
    pump.lastFlow = added / math.max(dt, 0.0001)
end

function LUASQUARE_PUMP.UpdateAll()
    local dt = LUASQUARE_PUMP.TickInterval
    for name, _ in pairs(LUASQUARE_PUMP.Pumps) do
        LUASQUARE_PUMP.UpdatePump(name, dt)
    end
end

function LUASQUARE_PUMP.Start()
    if timer.Exists('LUASQUARE_PUMP_UpdateTimer') then timer.Remove('LUASQUARE_PUMP_UpdateTimer') end
    timer.Create('LUASQUARE_PUMP_UpdateTimer', LUASQUARE_PUMP.TickInterval, 0, function() LUASQUARE_PUMP.UpdateAll() end)
    print('[LUASQUARE_PUMP] Started')
end

print('[LUASQUARE_PUMP] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- LUASQUARE_PUMP.RegisterPump('feedwater_pump_a', {
--     source = 'feedwater',
--     target = 'rbmk',
--     rate = 5,
--     headPressure = 25,
--     speedLevels = {0, 0.33, 0.66, 1},
--     enabled = false
-- })
-- LUASQUARE_PUMP.SetPump('feedwater_pump_a', true)
-- LUASQUARE_PUMP.Start()
