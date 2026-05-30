if LUASQUARE_DEAERATOR_CORE_LOADED then return end
LUASQUARE_DEAERATOR_CORE_LOADED = true
LUASQUARE_DEAERATOR = LUASQUARE_DEAERATOR or {}
LUASQUARE_DEAERATOR.Deaerators = LUASQUARE_DEAERATOR.Deaerators or {}
LUASQUARE_DEAERATOR.TickInterval = LUASQUARE_DEAERATOR.TickInterval or 0.1

local DEFAULT_WATER_HEAT_CAPACITY = 4.186
local DEFAULT_LATENT_HEAT = 2257

function LUASQUARE_DEAERATOR.RegisterDeaerator(name, data)
    data = data or {}
    LUASQUARE_DEAERATOR.Deaerators[name] = {
        name = name,
        tankNetwork = data.tankNetwork,
        steamInput = data.steamInput,
        enabled = data.enabled and true or false,
        targetTemperature = tonumber(data.targetTemperature) or 105,
        maxSteamRate = tonumber(data.maxSteamRate) or 0,
        steamToWaterRatio = tonumber(data.steamToWaterRatio) or 1600,
        steamLatentHeatKJPerL = tonumber(data.steamLatentHeatKJPerL) or DEFAULT_LATENT_HEAT,
        waterHeatCapacityKJPerL = tonumber(data.waterHeatCapacityKJPerL) or DEFAULT_WATER_HEAT_CAPACITY,
        lastSteamUsed = 0,
        lastWaterMade = 0,
        lastHeatMW = 0,
        tankTemperature = 0,
        tankAmount = 0,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
end

function LUASQUARE_DEAERATOR.GetDeaerator(name)
    return LUASQUARE_DEAERATOR.Deaerators[name]
end

function LUASQUARE_DEAERATOR.SetDeaerator(name, enabled)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then
        print('[LUASQUARE_DEAERATOR] Unknown deaerator: ' .. tostring(name))
        return false
    end

    deaerator.enabled = enabled and true or false
    return true
end

function LUASQUARE_DEAERATOR.UpdateDeaerator(name, dt)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then return end

    deaerator.lastSteamUsed = 0
    deaerator.lastWaterMade = 0
    deaerator.lastHeatMW = 0
    if not LUASQUARE_FLUID then return end

    local tank = LUASQUARE_FLUID.GetNetwork(deaerator.tankNetwork)
    if tank then
        deaerator.tankTemperature = tank.temperature or 0
        deaerator.tankAmount = tank.amount or 0
    end

    if not deaerator.enabled or not tank or not deaerator.steamInput then return end
    local steam = LUASQUARE_FLUID.GetNetwork(deaerator.steamInput)
    if not steam then return end

    local target = deaerator.targetTemperature or 105
    local temperatureGap = target - (tank.temperature or 20)
    if temperatureGap <= 0 then return end

    local cp = math.max(deaerator.waterHeatCapacityKJPerL or DEFAULT_WATER_HEAT_CAPACITY, 0.0001)
    local latent = math.max(deaerator.steamLatentHeatKJPerL or DEFAULT_LATENT_HEAT, 0.0001)
    local ratio = math.max(deaerator.steamToWaterRatio or 1600, 0.0001)
    local freeWater = math.max((tank.hardMaxAmount or tank.maxAmount) - (tank.amount or 0), 0)
    if freeWater <= 0 then return end

    local heatNeededKJ = temperatureGap * math.max(tank.amount or 0, 0) * cp
    local waterByHeat = heatNeededKJ / latent
    local waterWanted = math.min(waterByHeat, freeWater, (deaerator.maxSteamRate or 0) * dt / ratio, (steam.amount or 0) / ratio)
    if waterWanted <= 0 then return end

    local steamWanted = waterWanted * ratio
    local removed = LUASQUARE_FLUID.RemoveFluid(deaerator.steamInput, steamWanted)
    local waterMade = removed / ratio
    local added = LUASQUARE_FLUID.AddFluid(deaerator.tankNetwork, waterMade, target)
    if added < waterMade then
        LUASQUARE_FLUID.AddFluid(deaerator.steamInput, (waterMade - added) * ratio, steam.temperature)
        waterMade = added
        removed = added * ratio
    end

    local heatKJ = waterMade * latent
    if heatKJ > 0 and tank.amount > 0 then
        tank.temperature = math.min(target, (tank.temperature or 20) + heatKJ / math.max(tank.amount * cp, 0.0001))
        LUASQUARE_FLUID.UpdatePressure(deaerator.tankNetwork)
    end

    deaerator.lastSteamUsed = removed / math.max(dt, 0.0001)
    deaerator.lastWaterMade = waterMade / math.max(dt, 0.0001)
    deaerator.lastHeatMW = heatKJ / math.max(dt, 0.0001) / 1000
    deaerator.tankTemperature = tank.temperature or 0
    deaerator.tankAmount = tank.amount or 0
end

function LUASQUARE_DEAERATOR.UpdateAll()
    local dt = LUASQUARE_DEAERATOR.TickInterval
    for name, _ in pairs(LUASQUARE_DEAERATOR.Deaerators) do
        LUASQUARE_DEAERATOR.UpdateDeaerator(name, dt)
    end
end

function LUASQUARE_DEAERATOR.Start()
    if timer.Exists('LUASQUARE_DEAERATOR_UpdateTimer') then timer.Remove('LUASQUARE_DEAERATOR_UpdateTimer') end
    timer.Create('LUASQUARE_DEAERATOR_UpdateTimer', LUASQUARE_DEAERATOR.TickInterval, 0, function() LUASQUARE_DEAERATOR.UpdateAll() end)
    print('[LUASQUARE_DEAERATOR] Started')
end

print('[LUASQUARE_DEAERATOR] Loaded')
