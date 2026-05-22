if LUASQUARE_COOLINGTOWER_CORE_LOADED then return end
LUASQUARE_COOLINGTOWER_CORE_LOADED = true
LUASQUARE_COOLINGTOWER = LUASQUARE_COOLINGTOWER or {}
LUASQUARE_COOLINGTOWER.CoolingTowers = LUASQUARE_COOLINGTOWER.CoolingTowers or {}
LUASQUARE_COOLINGTOWER.TickInterval = LUASQUARE_COOLINGTOWER.TickInterval or 0.1

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_COOLINGTOWER.RegisterCoolingTower(name, data)
    data = data or {}
    local basinMaxAmount = math.max(tonumber(data.basinMaxAmount) or tonumber(data.maxAmount) or 1000, 0.0001)
    LUASQUARE_COOLINGTOWER.CoolingTowers[name] = {
        name = name,
        output = data.output,
        maxRate = tonumber(data.maxRate) or 1000,
        enabled = data.enabled and true or false,
        outputTemperature = tonumber(data.outputTemperature) or 20,
        basinAmount = math.Clamp(math.max(tonumber(data.basinAmount) or 0, 0), 0, basinMaxAmount),
        basinMaxAmount = basinMaxAmount,
        basinTemperature = tonumber(data.basinTemperature) or tonumber(data.temperature) or 40,
        basinPressure = 0,
        basinMaxPressure = tonumber(data.basinMaxPressure) or 20,
        startRelay = data.startRelay,
        stopRelay = data.stopRelay,
        pendingWaterReceived = 0,
        lastWaterReceived = 0,
        lastWaterCooled = 0,
        lastHeatRemoved = 0,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
    LUASQUARE_COOLINGTOWER.UpdateBasinPressure(name)
end

function LUASQUARE_COOLINGTOWER.GetCoolingTower(name)
    return LUASQUARE_COOLINGTOWER.CoolingTowers[name]
end

function LUASQUARE_COOLINGTOWER.UpdateBasinPressure(name)
    local tower = LUASQUARE_COOLINGTOWER.GetCoolingTower(name)
    if not tower then return 0 end

    local fillFraction = math.Clamp((tower.basinAmount or 0) / math.max(tower.basinMaxAmount or 1, 0.0001), 0, 1)
    tower.basinPressure = fillFraction * math.max(tower.basinMaxPressure or 0, 0)
    return tower.basinPressure
end

function LUASQUARE_COOLINGTOWER.GetBasinPressure(name)
    return LUASQUARE_COOLINGTOWER.UpdateBasinPressure(name)
end

function LUASQUARE_COOLINGTOWER.AddToBasin(name, amount, temperature)
    local tower = LUASQUARE_COOLINGTOWER.GetCoolingTower(name)
    if not tower then
        print('[LUASQUARE_COOLINGTOWER] Unknown cooling tower: ' .. tostring(name))
        return 0
    end

    amount = math.max(tonumber(amount) or 0, 0)
    local free = math.max((tower.basinMaxAmount or 0) - (tower.basinAmount or 0), 0)
    local moved = math.min(amount, free)
    if moved <= 0 then return 0 end

    local mixTemperature = temperature or tower.basinTemperature
    if LUASQUARE_FLUID and LUASQUARE_FLUID.MixTemperature then
        tower.basinTemperature = LUASQUARE_FLUID.MixTemperature(tower.basinAmount or 0, tower.basinTemperature or 20, moved, mixTemperature)
    else
        local total = (tower.basinAmount or 0) + moved
        tower.basinTemperature = ((tower.basinTemperature or 20) * (tower.basinAmount or 0) + mixTemperature * moved) / math.max(total, 0.0001)
    end

    tower.basinAmount = (tower.basinAmount or 0) + moved
    tower.pendingWaterReceived = (tower.pendingWaterReceived or 0) + moved
    LUASQUARE_COOLINGTOWER.UpdateBasinPressure(name)
    return moved
end

function LUASQUARE_COOLINGTOWER.SetCoolingTower(name, enabled)
    local tower = LUASQUARE_COOLINGTOWER.GetCoolingTower(name)
    if not tower then
        print('[LUASQUARE_COOLINGTOWER] Unknown cooling tower: ' .. tostring(name))
        return false
    end

    local wasEnabled = tower.enabled
    tower.enabled = enabled and true or false
    if tower.enabled and not wasEnabled and tower.startRelay and LUASQUARE_FLUID then LUASQUARE_FLUID.FireRelay(tower.startRelay) end
    if not tower.enabled and wasEnabled and tower.stopRelay and LUASQUARE_FLUID then LUASQUARE_FLUID.FireRelay(tower.stopRelay) end
    return true
end

-- =========================================
-- UPDATE
-- =========================================
function LUASQUARE_COOLINGTOWER.UpdateCoolingTower(name, dt)
    local tower = LUASQUARE_COOLINGTOWER.GetCoolingTower(name)
    if not tower then return end
    tower.lastWaterReceived = (tower.pendingWaterReceived or 0) / math.max(dt, 0.0001)
    tower.pendingWaterReceived = 0
    tower.lastWaterCooled = 0
    tower.lastHeatRemoved = 0
    if not tower.enabled then return end
    if not LUASQUARE_FLUID then return end

    local output = LUASQUARE_FLUID.GetNetwork(tower.output)
    if not output then
        print('[LUASQUARE_COOLINGTOWER] Unknown output network: ' .. tostring(tower.output))
        return
    end

    local outputFree = math.max((output.hardMaxAmount or output.maxAmount) - output.amount, 0)
    local requested = math.min(tower.basinAmount or 0, outputFree, tower.maxRate * dt)
    if requested <= 0 then return end

    local inputTemperature = tower.basinTemperature or tower.outputTemperature
    tower.basinAmount = math.max((tower.basinAmount or 0) - requested, 0)
    local added = LUASQUARE_FLUID.AddFluid(tower.output, requested, tower.outputTemperature)
    if added < requested then LUASQUARE_COOLINGTOWER.AddToBasin(name, requested - added, inputTemperature) end

    tower.lastWaterCooled = added / math.max(dt, 0.0001)
    tower.lastHeatRemoved = math.max(inputTemperature - tower.outputTemperature, 0) * added / math.max(dt, 0.0001)
    LUASQUARE_COOLINGTOWER.UpdateBasinPressure(name)
end

function LUASQUARE_COOLINGTOWER.UpdateAll()
    local dt = LUASQUARE_COOLINGTOWER.TickInterval
    for name, _ in pairs(LUASQUARE_COOLINGTOWER.CoolingTowers) do
        LUASQUARE_COOLINGTOWER.UpdateCoolingTower(name, dt)
    end
end

function LUASQUARE_COOLINGTOWER.Start()
    if timer.Exists('LUASQUARE_COOLINGTOWER_UpdateTimer') then timer.Remove('LUASQUARE_COOLINGTOWER_UpdateTimer') end
    timer.Create('LUASQUARE_COOLINGTOWER_UpdateTimer', LUASQUARE_COOLINGTOWER.TickInterval, 0, function() LUASQUARE_COOLINGTOWER.UpdateAll() end)
    print('[LUASQUARE_COOLINGTOWER] Started')
end

print('[LUASQUARE_COOLINGTOWER] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- LUASQUARE_COOLINGTOWER.RegisterCoolingTower('main_cooling_tower', {
--     output = 'feedwater',
--     basinMaxAmount = 10000,
--     maxRate = 1000,
--     enabled = true,
--     outputTemperature = 20
-- })
-- LUASQUARE_COOLINGTOWER.Start()
