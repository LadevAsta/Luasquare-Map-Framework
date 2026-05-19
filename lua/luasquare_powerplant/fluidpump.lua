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
        lastFlow = 0,
        monitorPos = data.monitorPos,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
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

function LUASQUARE_PUMP.GetTargetPressure(target)
    if target == 'rbmk' then
        if not RBMK then return 0 end
        return RBMK.RPVPressure or 0
    end

    local network = LUASQUARE_FLUID and LUASQUARE_FLUID.GetNetwork(target)
    if not network then return 0 end
    return network.pressure or 0
end

function LUASQUARE_PUMP.AddToTarget(target, amount, dischargePressure, temperature)
    if target == 'rbmk' then
        if not RBMK or not RBMK.AddWaterFromPump then return 0 end
        return RBMK.AddWaterFromPump(amount, dischargePressure, temperature)
    end

    if not LUASQUARE_FLUID then return 0 end
    return LUASQUARE_FLUID.AddFluid(target, amount, temperature)
end

-- =========================================
-- UPDATE
-- =========================================
function LUASQUARE_PUMP.UpdatePump(name, dt)
    local pump = LUASQUARE_PUMP.GetPump(name)
    if not pump then return end
    if not pump.enabled then
        pump.lastFlow = 0
        return
    end
    if not LUASQUARE_FLUID then return end
    pump.lastFlow = 0
    local speedMultiplier = LUASQUARE_PUMP.GetPumpSpeedMultiplier(pump)
    if speedMultiplier <= 0 then return end

    local source = LUASQUARE_FLUID.GetNetwork(pump.source)
    if not source then
        print('[LUASQUARE_PUMP] Unknown source network: ' .. tostring(pump.source))
        return
    end

    local dischargePressure = (source.pressure or 0) + pump.headPressure
    local targetPressure = LUASQUARE_PUMP.GetTargetPressure(pump.target)
    if dischargePressure <= targetPressure then return end

    local pressureScale = math.Clamp((dischargePressure - targetPressure) / math.max(dischargePressure, 0.0001), 0, 1)
    local requested = pump.rate * dt * pressureScale * pump.flowMultiplier * speedMultiplier
    local removed = LUASQUARE_FLUID.RemoveFluid(pump.source, requested)
    local added = LUASQUARE_PUMP.AddToTarget(pump.target, removed, dischargePressure, source.temperature)
    if added < removed then LUASQUARE_FLUID.AddFluid(pump.source, removed - added, source.temperature) end
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
