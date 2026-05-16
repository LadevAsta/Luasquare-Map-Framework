if LITHOS_PUMP_CORE_LOADED then return end
LITHOS_PUMP_CORE_LOADED = true
LITHOS_PUMP = LITHOS_PUMP or {}
LITHOS_PUMP.Pumps = LITHOS_PUMP.Pumps or {}
LITHOS_PUMP.TickInterval = LITHOS_PUMP.TickInterval or 0.1

-- =========================================
-- REGISTER
-- =========================================
function LITHOS_PUMP.RegisterPump(name, data)
    data = data or {}
    local speedLevels = data.speedLevels or {0, 0.25, 0.5, 0.75, 1}
    local speedLevel = tonumber(data.speedLevel)
    if speedLevel == nil then
        if data.enabled then speedLevel = #speedLevels else speedLevel = 1 end
    end
    LITHOS_PUMP.Pumps[name] = {
        name = name,
        source = data.source,
        target = data.target,
        rate = tonumber(data.rate) or 1,
        headPressure = tonumber(data.headPressure) or 0,
        enabled = data.enabled and true or false,
        speedLevels = speedLevels,
        speedLevel = math.Clamp(speedLevel, 1, #speedLevels),
        flowMultiplier = tonumber(data.flowMultiplier) or 1,
        lastFlow = 0,
        monitorPos = data.monitorPos,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
end

function LITHOS_PUMP.GetPump(name)
    return LITHOS_PUMP.Pumps[name]
end

function LITHOS_PUMP.SetPump(name, enabled)
    local pump = LITHOS_PUMP.GetPump(name)
    if not pump then
        print('[LITHOS_PUMP] Unknown pump: ' .. tostring(name))
        return false
    end

    pump.enabled = enabled and true or false
    if pump.enabled and (pump.speedLevels[pump.speedLevel] or 0) <= 0 then pump.speedLevel = #pump.speedLevels end
    if not pump.enabled then pump.lastFlow = 0 end
    return true
end

function LITHOS_PUMP.SetPumpSpeed(name, level)
    local pump = LITHOS_PUMP.GetPump(name)
    if not pump then
        print('[LITHOS_PUMP] Unknown pump: ' .. tostring(name))
        return false
    end

    pump.speedLevel = math.Clamp(math.floor(tonumber(level) or 1), 1, #pump.speedLevels)
    pump.enabled = (pump.speedLevels[pump.speedLevel] or 0) > 0
    if not pump.enabled then pump.lastFlow = 0 end
    return true
end

function LITHOS_PUMP.GetPumpSpeedMultiplier(pump)
    return pump.speedLevels[pump.speedLevel] or 0
end

function LITHOS_PUMP.GetTargetPressure(target)
    if target == 'rbmk' then
        if not RBMK then return 0 end
        return RBMK.RPVPressure or 0
    end

    local network = LITHOS_FLUID and LITHOS_FLUID.GetNetwork(target)
    if not network then return 0 end
    return network.pressure or 0
end

function LITHOS_PUMP.AddToTarget(target, amount, dischargePressure)
    if target == 'rbmk' then
        if not RBMK or not RBMK.AddWaterFromPump then return 0 end
        return RBMK.AddWaterFromPump(amount, dischargePressure)
    end

    if not LITHOS_FLUID then return 0 end
    return LITHOS_FLUID.AddFluid(target, amount)
end

-- =========================================
-- UPDATE
-- =========================================
function LITHOS_PUMP.UpdatePump(name, dt)
    local pump = LITHOS_PUMP.GetPump(name)
    if not pump then return end
    if not pump.enabled then
        pump.lastFlow = 0
        return
    end
    if not LITHOS_FLUID then return end
    pump.lastFlow = 0
    local speedMultiplier = LITHOS_PUMP.GetPumpSpeedMultiplier(pump)
    if speedMultiplier <= 0 then return end

    local source = LITHOS_FLUID.GetNetwork(pump.source)
    if not source then
        print('[LITHOS_PUMP] Unknown source network: ' .. tostring(pump.source))
        return
    end

    local dischargePressure = (source.pressure or 0) + pump.headPressure
    local targetPressure = LITHOS_PUMP.GetTargetPressure(pump.target)
    if dischargePressure <= targetPressure then return end

    local pressureScale = math.Clamp((dischargePressure - targetPressure) / math.max(dischargePressure, 0.0001), 0, 1)
    local requested = pump.rate * dt * pressureScale * pump.flowMultiplier * speedMultiplier
    local removed = LITHOS_FLUID.RemoveFluid(pump.source, requested)
    local added = LITHOS_PUMP.AddToTarget(pump.target, removed, dischargePressure)
    if added < removed then LITHOS_FLUID.AddFluid(pump.source, removed - added) end
    pump.lastFlow = added / math.max(dt, 0.0001)
end

function LITHOS_PUMP.UpdateAll()
    local dt = LITHOS_PUMP.TickInterval
    for name, _ in pairs(LITHOS_PUMP.Pumps) do
        LITHOS_PUMP.UpdatePump(name, dt)
    end
end

function LITHOS_PUMP.Start()
    if timer.Exists('LITHOS_PUMP_UpdateTimer') then timer.Remove('LITHOS_PUMP_UpdateTimer') end
    timer.Create('LITHOS_PUMP_UpdateTimer', LITHOS_PUMP.TickInterval, 0, function() LITHOS_PUMP.UpdateAll() end)
    print('[LITHOS_PUMP] Started')
end

print('[LITHOS_PUMP] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- LITHOS_PUMP.RegisterPump('feedwater_pump_a', {
--     source = 'feedwater',
--     target = 'rbmk',
--     rate = 5,
--     headPressure = 25,
--     speedLevels = {0, 0.33, 0.66, 1},
--     enabled = false
-- })
-- LITHOS_PUMP.SetPump('feedwater_pump_a', true)
-- LITHOS_PUMP.Start()
