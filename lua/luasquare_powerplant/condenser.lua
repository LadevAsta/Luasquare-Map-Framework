if LUASQUARE_CONDENSER_CORE_LOADED then return end
LUASQUARE_CONDENSER_CORE_LOADED = true
LUASQUARE_CONDENSER = LUASQUARE_CONDENSER or {}
LUASQUARE_CONDENSER.Condensers = LUASQUARE_CONDENSER.Condensers or {}
LUASQUARE_CONDENSER.TickInterval = LUASQUARE_CONDENSER.TickInterval or 0.1

local DEFAULT_WATER_HEAT_CAPACITY = 4.186
local DEFAULT_LATENT_HEAT = 2257

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_CONDENSER.RegisterCondenser(name, data)
    data = data or {}
    LUASQUARE_CONDENSER.Condensers[name] = {
        name = name,
        input = data.input,
        output = data.output,
        ratio = tonumber(data.ratio) or 1600,
        maxRate = tonumber(data.maxRate) or math.huge,
        enabled = data.enabled and true or false,
        godMode = data.godMode and true or false,
        startRelay = data.startRelay,
        stopRelay = data.stopRelay,
        outputTemperature = tonumber(data.outputTemperature) or 20,
        coolantNetwork = data.coolantNetwork,
        coolantPump = data.coolantPump,
        effectiveness = math.Clamp(tonumber(data.effectiveness) or 0.85, 0, 1),
        approachTemperature = math.max(tonumber(data.approachTemperature) or 5, 0),
        steamLatentHeatKJPerL = tonumber(data.steamLatentHeatKJPerL) or DEFAULT_LATENT_HEAT,
        coolantHeatCapacityKJPerL = tonumber(data.coolantHeatCapacityKJPerL) or DEFAULT_WATER_HEAT_CAPACITY,
        maxThermalMW = tonumber(data.maxThermalMW),
        lastSteamUsed = 0,
        lastWaterMade = 0,
        lastHeatRejectedMW = 0,
        lastCoolantFlow = 0,
        lastCoolantTemperature = 0,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
end

function LUASQUARE_CONDENSER.GetCondenser(name)
    return LUASQUARE_CONDENSER.Condensers[name]
end

function LUASQUARE_CONDENSER.SetCondenser(name, enabled)
    local condenser = LUASQUARE_CONDENSER.GetCondenser(name)
    if not condenser then
        print('[LUASQUARE_CONDENSER] Unknown condenser: ' .. tostring(name))
        return false
    end

    local wasEnabled = condenser.enabled
    condenser.enabled = enabled and true or false
    if condenser.enabled and not wasEnabled and condenser.startRelay and LUASQUARE_FLUID then LUASQUARE_FLUID.FireRelay(condenser.startRelay) end
    if not condenser.enabled and wasEnabled and condenser.stopRelay and LUASQUARE_FLUID then LUASQUARE_FLUID.FireRelay(condenser.stopRelay) end
    return true
end

-- =========================================
-- UPDATE
-- =========================================
local function getPumpFlow(name)
    if not name or not LUASQUARE_PUMP then return 0 end
    local pump = LUASQUARE_PUMP.GetPump(name)
    if not pump or not pump.enabled then return 0 end
    return math.max(pump.lastFlow or 0, 0)
end

local function updateSurfaceCondenser(condenser, input, output, dt)
    local coolant = LUASQUARE_FLUID.GetNetwork(condenser.coolantNetwork)
    if not coolant then
        print('[LUASQUARE_CONDENSER] Unknown coolant network: ' .. tostring(condenser.coolantNetwork))
        return
    end

    local coolantFlow = getPumpFlow(condenser.coolantPump)
    condenser.lastCoolantFlow = coolantFlow
    condenser.lastCoolantTemperature = coolant.temperature or 0
    if coolantFlow <= 0 then return end

    local delta = (input.temperature or 100) - (coolant.temperature or 20) - (condenser.approachTemperature or 0)
    if delta <= 0 then return end

    local cp = math.max(condenser.coolantHeatCapacityKJPerL or DEFAULT_WATER_HEAT_CAPACITY, 0.0001)
    local latent = math.max(condenser.steamLatentHeatKJPerL or DEFAULT_LATENT_HEAT, 0.0001)
    local ratio = math.max(condenser.ratio, 0.0001)
    local outputFree = math.max((output.hardMaxAmount or output.maxAmount) - output.amount, 0)
    local rateLimit = condenser.maxRate
    if rateLimit ~= math.huge then rateLimit = rateLimit * dt end

    local heatCapacityKJ = coolantFlow * cp * delta * (condenser.effectiveness or 0) * dt
    if condenser.maxThermalMW then heatCapacityKJ = math.min(heatCapacityKJ, math.max(condenser.maxThermalMW, 0) * 1000 * dt) end
    local steamByHeat = heatCapacityKJ / latent * ratio
    local steamToUse = math.min(input.amount, outputFree * ratio, rateLimit, steamByHeat)
    if steamToUse <= 0 then return end

    local removed = LUASQUARE_FLUID.RemoveFluid(condenser.input, steamToUse)
    local waterMade = removed / ratio
    local added = LUASQUARE_FLUID.AddFluid(condenser.output, waterMade, condenser.outputTemperature)
    if added < waterMade then
        LUASQUARE_FLUID.AddFluid(condenser.input, (waterMade - added) * ratio, input.temperature)
        waterMade = added
        removed = added * ratio
    end

    local heatRejectedKJ = waterMade * latent
    if heatRejectedKJ > 0 then
        local thermalMass = math.max(math.max(coolant.amount or 0, coolantFlow * dt) * cp, 0.0001)
        coolant.temperature = (coolant.temperature or 20) + heatRejectedKJ / thermalMass
        LUASQUARE_FLUID.UpdatePressure(coolant.name)
    end

    condenser.lastSteamUsed = removed / math.max(dt, 0.0001)
    condenser.lastWaterMade = waterMade / math.max(dt, 0.0001)
    condenser.lastHeatRejectedMW = heatRejectedKJ / math.max(dt, 0.0001) / 1000
    condenser.lastCoolantTemperature = coolant.temperature or 0
end

local function updateDirectCondenser(condenser, input, output, dt)
    local ratio = math.max(condenser.ratio, 0.0001)
    local outputFree = math.max((output.hardMaxAmount or output.maxAmount) - output.amount, 0)
    local rateLimit = condenser.maxRate
    if rateLimit ~= math.huge then rateLimit = rateLimit * dt end

    local steamToUse = math.min(input.amount, outputFree * ratio, rateLimit)
    if steamToUse <= 0 then return end

    local removed = LUASQUARE_FLUID.RemoveFluid(condenser.input, steamToUse)
    local waterMade = removed / ratio
    local added = LUASQUARE_FLUID.AddFluid(condenser.output, waterMade, condenser.outputTemperature)
    if added < waterMade then
        LUASQUARE_FLUID.AddFluid(condenser.input, (waterMade - added) * ratio, input.temperature)
        waterMade = added
        removed = added * ratio
    end

    condenser.lastSteamUsed = removed / math.max(dt, 0.0001)
    condenser.lastWaterMade = waterMade / math.max(dt, 0.0001)
    condenser.lastHeatRejectedMW = (waterMade * math.max(condenser.steamLatentHeatKJPerL or DEFAULT_LATENT_HEAT, 0.0001)) / math.max(dt, 0.0001) / 1000
end

function LUASQUARE_CONDENSER.UpdateCondenser(name, dt)
    local condenser = LUASQUARE_CONDENSER.GetCondenser(name)
    if not condenser then return end
    condenser.lastSteamUsed = 0
    condenser.lastWaterMade = 0
    condenser.lastHeatRejectedMW = 0
    condenser.lastCoolantFlow = 0
    if not condenser.enabled then return end
    if not LUASQUARE_FLUID then return end

    local input = LUASQUARE_FLUID.GetNetwork(condenser.input)
    local output = LUASQUARE_FLUID.GetNetwork(condenser.output)
    if not input then
        print('[LUASQUARE_CONDENSER] Unknown input network: ' .. tostring(condenser.input))
        return
    end

    if not output then
        print('[LUASQUARE_CONDENSER] Unknown output network: ' .. tostring(condenser.output))
        return
    end

    if condenser.coolantNetwork then
        updateSurfaceCondenser(condenser, input, output, dt)
    else
        updateDirectCondenser(condenser, input, output, dt)
    end
end

function LUASQUARE_CONDENSER.UpdateAll()
    local dt = LUASQUARE_CONDENSER.TickInterval
    for name, _ in pairs(LUASQUARE_CONDENSER.Condensers) do
        LUASQUARE_CONDENSER.UpdateCondenser(name, dt)
    end
end

function LUASQUARE_CONDENSER.Start()
    if timer.Exists('LUASQUARE_CONDENSER_UpdateTimer') then timer.Remove('LUASQUARE_CONDENSER_UpdateTimer') end
    timer.Create('LUASQUARE_CONDENSER_UpdateTimer', LUASQUARE_CONDENSER.TickInterval, 0, function() LUASQUARE_CONDENSER.UpdateAll() end)
    print('[LUASQUARE_CONDENSER] Started')
end

print('[LUASQUARE_CONDENSER] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- LUASQUARE_CONDENSER.RegisterCondenser('god_condenser', {
--     input = 'main_steam',
--     output = 'condensate',
--     ratio = 1600,
--     maxRate = math.huge,
--     enabled = true,
--     godMode = true,
--     monitorPos = Vector(0, 0, 128)
-- })
-- LUASQUARE_CONDENSER.Start()
