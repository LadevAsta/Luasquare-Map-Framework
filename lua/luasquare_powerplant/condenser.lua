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
    local steamMaxAmount = math.max(tonumber(data.steamMaxAmount) or tonumber(data.maxSteamAmount) or 50000, 0.0001)
    local steamHardMaxAmount = math.max(tonumber(data.steamHardMaxAmount) or tonumber(data.hardMaxSteamAmount) or steamMaxAmount, steamMaxAmount)
    local steamMaxPressure = math.max(tonumber(data.steamMaxPressure) or 5, 0.0001)
    local steamVolume = tonumber(data.steamVolume) or tonumber(data.volume) or (steamMaxAmount / steamMaxPressure)

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
        steamAmount = math.Clamp(tonumber(data.steamAmount) or 0, 0, steamHardMaxAmount),
        steamMaxAmount = steamMaxAmount,
        steamHardMaxAmount = steamHardMaxAmount,
        steamVolume = math.max(steamVolume, 0.0001),
        steamPressure = 0,
        steamMaxPressure = steamMaxPressure,
        steamTemperature = tonumber(data.steamTemperature) or 100,
        pendingSteamAccepted = 0,
        lastSteamAccepted = 0,
        lastSteamUsed = 0,
        lastWaterMade = 0,
        lastHeatRejectedMW = 0,
        lastCoolantFlow = 0,
        lastCoolantTemperature = 0,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }

    LUASQUARE_CONDENSER.UpdateSteamPressure(name)
end

function LUASQUARE_CONDENSER.GetCondenser(name)
    return LUASQUARE_CONDENSER.Condensers[name]
end

function LUASQUARE_CONDENSER.UpdateSteamPressure(name)
    local condenser = LUASQUARE_CONDENSER.GetCondenser(name)
    if not condenser then return 0 end
    local referenceK = (LUASQUARE_FLUID and LUASQUARE_FLUID.ReferenceSteamTemperature or 100) + 273.15
    local temperatureK = math.max((condenser.steamTemperature or 100) + 273.15, 1)
    condenser.steamPressure = math.max(condenser.steamAmount or 0, 0) / math.max(condenser.steamVolume or 1, 0.0001) * (temperatureK / referenceK)
    return condenser.steamPressure
end

function LUASQUARE_CONDENSER.AcceptSteam(name, amount, temperature)
    local condenser = LUASQUARE_CONDENSER.GetCondenser(name)
    if not condenser then
        print('[LUASQUARE_CONDENSER] Unknown condenser: ' .. tostring(name))
        return 0
    end

    if not condenser.enabled then return 0 end
    amount = math.max(tonumber(amount) or 0, 0)
    local free = math.max((condenser.steamHardMaxAmount or condenser.steamMaxAmount) - (condenser.steamAmount or 0), 0)
    local moved = math.min(amount, free)
    if moved <= 0 then return 0 end

    if LUASQUARE_FLUID and LUASQUARE_FLUID.MixTemperature then
        condenser.steamTemperature = LUASQUARE_FLUID.MixTemperature(condenser.steamAmount or 0, condenser.steamTemperature or 100, moved, temperature or condenser.steamTemperature)
    end
    condenser.steamAmount = (condenser.steamAmount or 0) + moved
    condenser.pendingSteamAccepted = (condenser.pendingSteamAccepted or 0) + moved
    LUASQUARE_CONDENSER.UpdateSteamPressure(name)
    return moved
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

local function getCoolantFlow(condenser, coolant)
    if coolant and LUASQUARE_FLUID and coolant.type == LUASQUARE_FLUID.TYPE_COOLANT and LUASQUARE_FLUID.GetCoolantCirculationFlow then
        return LUASQUARE_FLUID.GetCoolantCirculationFlow(coolant.name)
    end

    return getPumpFlow(condenser.coolantPump)
end

local function removeInternalSteam(condenser, amount)
    local removed = math.min(math.max(amount or 0, 0), condenser.steamAmount or 0)
    condenser.steamAmount = math.max((condenser.steamAmount or 0) - removed, 0)
    return removed
end

local function returnInternalSteam(condenser, amount, temperature)
    if amount <= 0 then return end
    if LUASQUARE_FLUID and LUASQUARE_FLUID.MixTemperature then
        condenser.steamTemperature = LUASQUARE_FLUID.MixTemperature(condenser.steamAmount or 0, condenser.steamTemperature or 100, amount, temperature or condenser.steamTemperature)
    end
    condenser.steamAmount = math.min((condenser.steamAmount or 0) + amount, condenser.steamHardMaxAmount or condenser.steamMaxAmount)
end

local function condenseSteam(condenser, source, output, dt, removeSteam, returnSteam)
    local ratio = math.max(condenser.ratio, 0.0001)
    local outputFree = math.max((output.hardMaxAmount or output.maxAmount) - output.amount, 0)
    local rateLimit = condenser.maxRate
    if rateLimit ~= math.huge then rateLimit = rateLimit * dt end

    local steamToUse = math.min(source.amount or 0, outputFree * ratio, rateLimit)
    if steamToUse <= 0 then return 0, 0, 0 end

    local removed = removeSteam(steamToUse)
    local waterMade = removed / ratio
    local added = LUASQUARE_FLUID.AddFluid(condenser.output, waterMade, condenser.outputTemperature)
    if added < waterMade then
        returnSteam((waterMade - added) * ratio, source.temperature)
        waterMade = added
        removed = added * ratio
    end

    local heatRejectedKJ = waterMade * math.max(condenser.steamLatentHeatKJPerL or DEFAULT_LATENT_HEAT, 0.0001)
    return removed, waterMade, heatRejectedKJ
end

local function updateSurfaceCondenser(condenser, source, output, dt, removeSteam, returnSteam)
    local coolant = LUASQUARE_FLUID.GetNetwork(condenser.coolantNetwork)
    if not coolant then
        print('[LUASQUARE_CONDENSER] Unknown coolant network: ' .. tostring(condenser.coolantNetwork))
        return
    end

    local coolantFlow = getCoolantFlow(condenser, coolant)
    condenser.lastCoolantFlow = coolantFlow
    condenser.lastCoolantTemperature = coolant.temperature or 0
    if coolantFlow <= 0 then return end

    local delta = (source.temperature or 100) - (coolant.temperature or 20) - (condenser.approachTemperature or 0)
    if delta <= 0 then return end

    local cp = math.max(condenser.coolantHeatCapacityKJPerL or coolant.coolantHeatCapacityKJPerL or DEFAULT_WATER_HEAT_CAPACITY, 0.0001)
    local latent = math.max(condenser.steamLatentHeatKJPerL or DEFAULT_LATENT_HEAT, 0.0001)
    local ratio = math.max(condenser.ratio, 0.0001)
    local heatCapacityKJ = coolantFlow * cp * delta * (condenser.effectiveness or 0) * dt
    if condenser.maxThermalMW then heatCapacityKJ = math.min(heatCapacityKJ, math.max(condenser.maxThermalMW, 0) * 1000 * dt) end

    local heatSteamLimit = heatCapacityKJ / latent * ratio
    local oldMaxRate = condenser.maxRate
    condenser.maxRate = math.min(oldMaxRate, heatSteamLimit / math.max(dt, 0.0001))
    local removed, waterMade, heatRejectedKJ = condenseSteam(condenser, source, output, dt, removeSteam, returnSteam)
    condenser.maxRate = oldMaxRate
    if removed <= 0 then return end

    local thermalMass = math.max(math.max(coolant.amount or 0, coolantFlow * dt) * cp, 0.0001)
    coolant.temperature = (coolant.temperature or 20) + heatRejectedKJ / thermalMass
    LUASQUARE_FLUID.UpdatePressure(coolant.name)

    condenser.lastSteamUsed = removed / math.max(dt, 0.0001)
    condenser.lastWaterMade = waterMade / math.max(dt, 0.0001)
    condenser.lastHeatRejectedMW = heatRejectedKJ / math.max(dt, 0.0001) / 1000
    condenser.lastCoolantTemperature = coolant.temperature or 0
end

local function updateDirectCondenser(condenser, source, output, dt, removeSteam, returnSteam)
    local removed, waterMade, heatRejectedKJ = condenseSteam(condenser, source, output, dt, removeSteam, returnSteam)
    condenser.lastSteamUsed = removed / math.max(dt, 0.0001)
    condenser.lastWaterMade = waterMade / math.max(dt, 0.0001)
    condenser.lastHeatRejectedMW = heatRejectedKJ / math.max(dt, 0.0001) / 1000
end

function LUASQUARE_CONDENSER.UpdateCondenser(name, dt)
    local condenser = LUASQUARE_CONDENSER.GetCondenser(name)
    if not condenser then return end
    condenser.lastSteamAccepted = (condenser.pendingSteamAccepted or 0) / math.max(dt, 0.0001)
    condenser.pendingSteamAccepted = 0
    condenser.lastSteamUsed = 0
    condenser.lastWaterMade = 0
    condenser.lastHeatRejectedMW = 0
    condenser.lastCoolantFlow = 0
    if not condenser.enabled then return end
    if not LUASQUARE_FLUID then return end

    local output = LUASQUARE_FLUID.GetNetwork(condenser.output)
    if not output then
        print('[LUASQUARE_CONDENSER] Unknown output network: ' .. tostring(condenser.output))
        return
    end

    local source
    local removeSteam
    local returnSteam
    if condenser.input then
        local input = LUASQUARE_FLUID.GetNetwork(condenser.input)
        if not input then
            print('[LUASQUARE_CONDENSER] Unknown input network: ' .. tostring(condenser.input))
            return
        end
        source = input
        removeSteam = function(amount) return LUASQUARE_FLUID.RemoveFluid(condenser.input, amount) end
        returnSteam = function(amount, temperature) LUASQUARE_FLUID.AddFluid(condenser.input, amount, temperature) end
    else
        source = {
            amount = condenser.steamAmount or 0,
            temperature = condenser.steamTemperature or 100
        }
        removeSteam = function(amount) return removeInternalSteam(condenser, amount) end
        returnSteam = function(amount, temperature) returnInternalSteam(condenser, amount, temperature) end
    end

    if condenser.coolantNetwork then
        updateSurfaceCondenser(condenser, source, output, dt, removeSteam, returnSteam)
    else
        updateDirectCondenser(condenser, source, output, dt, removeSteam, returnSteam)
    end

    LUASQUARE_CONDENSER.UpdateSteamPressure(name)
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
