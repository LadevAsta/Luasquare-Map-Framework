if LUASQUARE_COOLINGTOWER_CORE_LOADED then return end
LUASQUARE_COOLINGTOWER_CORE_LOADED = true
LUASQUARE_COOLINGTOWER = LUASQUARE_COOLINGTOWER or {}
LUASQUARE_COOLINGTOWER.CoolingTowers = LUASQUARE_COOLINGTOWER.CoolingTowers or {}
LUASQUARE_COOLINGTOWER.TickInterval = LUASQUARE_COOLINGTOWER.TickInterval or 0.1

local DEFAULT_WATER_HEAT_CAPACITY = 4.186

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_COOLINGTOWER.RegisterCoolingTower(name, data)
    data = data or {}
    local basinMaxAmount = math.max(tonumber(data.basinMaxAmount) or tonumber(data.maxAmount) or 1000, 0.0001)
    LUASQUARE_COOLINGTOWER.CoolingTowers[name] = {
        name = name,
        output = data.output,
        coolantNetwork = data.coolantNetwork,
        maxRate = tonumber(data.maxRate) or 1000,
        enabled = data.enabled and true or false,
        working = data.working and true or false,
        outputTemperature = tonumber(data.outputTemperature) or 20,
        basinAmount = math.Clamp(math.max(tonumber(data.basinAmount) or 0, 0), 0, basinMaxAmount),
        basinMaxAmount = basinMaxAmount,
        basinTemperature = tonumber(data.basinTemperature) or tonumber(data.temperature) or 40,
        basinPressure = 0,
        basinMaxPressure = tonumber(data.basinMaxPressure) or 20,
        evaporationFraction = math.Clamp(tonumber(data.evaporationFraction) or tonumber(data.driftFraction) or 0, 0, 1),
        startRelay = data.startRelay,
        stopRelay = data.stopRelay,
        workRelay = data.workRelay,
        idleRelay = data.idleRelay,
        pendingWaterReceived = 0,
        lastWaterReceived = 0,
        lastWaterCooled = 0,
        lastHeatRemoved = 0,
        lastHeatRemovedMW = 0,
        lastCoolantFlow = 0,
        lastCoolantTemperature = 0,
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
local function setWorking(tower, working)
    working = working and true or false
    if tower.working == working then return end
    tower.working = working
    if not LUASQUARE_FLUID then return end
    if working and tower.workRelay then LUASQUARE_FLUID.FireRelay(tower.workRelay) end
    if not working and tower.idleRelay then LUASQUARE_FLUID.FireRelay(tower.idleRelay) end
end

local function findCoolantNetwork(name, tower)
    if not LUASQUARE_FLUID then return nil end
    if tower.coolantNetwork then
        local coolant = LUASQUARE_FLUID.GetNetwork(tower.coolantNetwork)
        if coolant and coolant.type == LUASQUARE_FLUID.TYPE_COOLANT then return coolant end
    end

    return LUASQUARE_FLUID.GetCoolantNetworkForTower and LUASQUARE_FLUID.GetCoolantNetworkForTower(name) or nil
end

local function updateCoolantTower(name, tower, coolant, dt)
    tower.coolantNetwork = coolant.name
    tower.lastWaterCooled = 0
    tower.lastHeatRemoved = 0
    tower.lastHeatRemovedMW = 0
    tower.lastCoolantFlow = 0
    tower.lastCoolantTemperature = coolant.temperature or 0
    coolant.lastCoolantHeatRemovedMW = 0
    coolant.coolantCooling = false
    coolant.coolantOverheated = coolant.coolantHighTemperature and (coolant.temperature or 0) >= coolant.coolantHighTemperature or false
    if not tower.enabled then
        setWorking(tower, false)
        return
    end

    local coolantFlow = LUASQUARE_FLUID.GetCoolantCirculationFlow and LUASQUARE_FLUID.GetCoolantCirculationFlow(coolant.name) or 0
    local coolingFlow = math.min(coolantFlow, math.max(tower.maxRate or 0, 0))
    local returnAmount = math.min(tower.basinAmount or 0, coolingFlow * dt, math.max((coolant.hardMaxAmount or coolant.maxAmount) - (coolant.amount or 0), 0))
    local inputTemperature = tower.basinTemperature or coolant.temperature or 20
    local delta = inputTemperature - (tower.outputTemperature or 20)
    local active = returnAmount > 0 and delta > (coolant.coolantCoolingDelta or 1)
    tower.lastCoolantFlow = coolantFlow
    tower.lastWaterCooled = returnAmount / math.max(dt, 0.0001)
    tower.lastCoolantTemperature = coolant.temperature or 0
    coolant.coolantCooling = active
    coolant.lastCoolantFlow = coolantFlow
    if returnAmount <= 0 then
        setWorking(tower, false)
        return
    end

    local cp = math.max(coolant.coolantHeatCapacityKJPerL or DEFAULT_WATER_HEAT_CAPACITY, 0.0001)
    local returnTemperature = inputTemperature
    local heatKJ = 0
    if active then
        returnTemperature = tower.outputTemperature or inputTemperature
        heatKJ = math.max(inputTemperature - returnTemperature, 0) * returnAmount * cp
    end

    local returned = LUASQUARE_FLUID.AddFluid(coolant.name, returnAmount, returnTemperature)
    tower.basinAmount = math.max((tower.basinAmount or 0) - returned, 0)

    local evaporation = 0
    if active and (tower.evaporationFraction or 0) > 0 then
        evaporation = math.min(tower.basinAmount or 0, returned * tower.evaporationFraction)
        tower.basinAmount = math.max((tower.basinAmount or 0) - evaporation, 0)
    end

    LUASQUARE_COOLINGTOWER.UpdateBasinPressure(name)
    tower.lastCoolantTemperature = coolant.temperature or 0
    tower.lastHeatRemoved = heatKJ / math.max(cp * math.max(dt, 0.0001), 0.0001)
    tower.lastHeatRemovedMW = heatKJ / math.max(dt, 0.0001) / 1000
    coolant.lastCoolantHeatRemovedMW = tower.lastHeatRemovedMW
    coolant.coolantOverheated = coolant.coolantHighTemperature and (coolant.temperature or 0) >= coolant.coolantHighTemperature or false
    setWorking(tower, active)
end

function LUASQUARE_COOLINGTOWER.UpdateCoolingTower(name, dt)
    local tower = LUASQUARE_COOLINGTOWER.GetCoolingTower(name)
    if not tower then return end
    tower.lastWaterReceived = (tower.pendingWaterReceived or 0) / math.max(dt, 0.0001)
    tower.pendingWaterReceived = 0
    tower.lastWaterCooled = 0
    tower.lastHeatRemoved = 0
    tower.lastHeatRemovedMW = 0
    tower.lastCoolantFlow = 0

    local coolant = findCoolantNetwork(name, tower)
    if coolant then
        updateCoolantTower(name, tower, coolant, dt)
        return
    end

    if not tower.enabled then return end
    if not LUASQUARE_FLUID then return end

    local output = LUASQUARE_FLUID.GetNetwork(tower.output)
    if not output then
        print('[LUASQUARE_COOLINGTOWER] Unknown output network: ' .. tostring(tower.output))
        return
    end

    local outputFree = math.max((output.hardMaxAmount or output.maxAmount) - output.amount, 0)
    local requested = math.min(tower.basinAmount or 0, outputFree, tower.maxRate * dt)
    local wasWorking = tower.working
    if requested <= 0 then
        if wasWorking then
            LUASQUARE_FLUID.FireRelay(tower.stopRelay)
            tower.working = false
        end
        return
    end

    local inputTemperature = tower.basinTemperature or tower.outputTemperature
    tower.basinAmount = math.max((tower.basinAmount or 0) - requested, 0)
    local added = LUASQUARE_FLUID.AddFluid(tower.output, requested, tower.outputTemperature)
    if added < requested then LUASQUARE_COOLINGTOWER.AddToBasin(name, requested - added, inputTemperature) end

    tower.lastWaterCooled = added / math.max(dt, 0.0001)
    tower.lastHeatRemoved = math.max(inputTemperature - tower.outputTemperature, 0) * added / math.max(dt, 0.0001)
    LUASQUARE_COOLINGTOWER.UpdateBasinPressure(name)

    if not wasWorking then
        LUASQUARE_FLUID.FireRelay(tower.startRelay)
        tower.working = true
    end
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
