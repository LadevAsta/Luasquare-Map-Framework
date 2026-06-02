if LUASQUARE_STEAMSEPARATOR_CORE_LOADED then return end
LUASQUARE_STEAMSEPARATOR_CORE_LOADED = true
LUASQUARE_STEAMSEPARATOR = LUASQUARE_STEAMSEPARATOR or {}
LUASQUARE_STEAMSEPARATOR.Separators = LUASQUARE_STEAMSEPARATOR.Separators or {}
LUASQUARE_STEAMSEPARATOR.TickInterval = LUASQUARE_STEAMSEPARATOR.TickInterval or 0.1

local DEFAULT_LATENT_HEAT = 2257
local DEFAULT_STEAM_RATIO = 1600

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_STEAMSEPARATOR.RegisterSteamSeparator(name, data)
    data = data or {}
    local maxWaterAmount = math.max(tonumber(data.maxWaterAmount) or tonumber(data.maxAmount) or 10000, 0.0001)
    local hardMaxWaterAmount = math.max(tonumber(data.hardMaxWaterAmount) or tonumber(data.hardMaxAmount) or maxWaterAmount * 1.1, maxWaterAmount)
    local maxSteamAmount = math.max(tonumber(data.maxSteamAmount) or 10000, 0.0001)
    local maxPressure = math.max(tonumber(data.maxPressure) or 80, 0.0001)
    local steamVolume = tonumber(data.steamVolume) or maxSteamAmount / maxPressure

    LUASQUARE_STEAMSEPARATOR.Separators[name] = {
        name = name,
        enabled = data.enabled ~= false,
        drySteamNetwork = data.drySteamNetwork or data.output or data.steamNetwork,
        waterAmount = math.Clamp(tonumber(data.waterAmount) or tonumber(data.amount) or 0, 0, hardMaxWaterAmount),
        maxWaterAmount = maxWaterAmount,
        hardMaxWaterAmount = hardMaxWaterAmount,
        waterTemperature = tonumber(data.waterTemperature) or tonumber(data.temperature) or 100,
        steamAmount = math.Clamp(tonumber(data.steamAmount) or 0, 0, maxSteamAmount),
        maxSteamAmount = maxSteamAmount,
        hardMaxSteamAmount = math.max(tonumber(data.hardMaxSteamAmount) or maxSteamAmount * 1.25, maxSteamAmount),
        steamVolume = math.max(steamVolume, 0.0001),
        steamTemperature = tonumber(data.steamTemperature) or tonumber(data.temperature) or 100,
        pressure = 0,
        maxPressure = maxPressure,
        hardMaxPressure = tonumber(data.hardMaxPressure) or maxPressure * 1.25,
        outletValve = math.Clamp(tonumber(data.outletValve) or 1, 0, 1),
        outputMaxSteamRate = tonumber(data.outputMaxSteamRate) or 10000,
        ratedOutputPressure = tonumber(data.ratedOutputPressure) or maxPressure,
        separationEfficiency = math.Clamp(tonumber(data.separationEfficiency) or 0.995, 0, 1),
        highLevelFraction = math.Clamp(tonumber(data.highLevelFraction) or 0.85, 0, 1),
        lowLevelFraction = math.Clamp(tonumber(data.lowLevelFraction) or 0.15, 0, 1),
        flooded = false,
        lowLevel = false,
        steamRatio = tonumber(data.steamRatio) or DEFAULT_STEAM_RATIO,
        steamLatentHeatKJPerL = tonumber(data.steamLatentHeatKJPerL) or DEFAULT_LATENT_HEAT,
        thermalEnergyKJ = math.max(tonumber(data.thermalEnergyKJ) or 0, 0),
        lastWetWaterIn = 0,
        lastWetSteamIn = 0,
        lastDrySteamOut = 0,
        lastCarryover = 0,
        lastFeedwaterIn = 0,
        lastRecircOut = 0,
        lastPressureScale = 0,
        lastThermalMW = 0,
        lastSteamQuality = 1,
        pendingWetWaterIn = 0,
        pendingWetSteamIn = 0,
        pendingFeedwaterIn = 0,
        pendingRecircOut = 0,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }

    LUASQUARE_STEAMSEPARATOR.UpdatePressure(name)
end

function LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(name)
    return LUASQUARE_STEAMSEPARATOR.Separators[name]
end

function LUASQUARE_STEAMSEPARATOR.GetLevelFraction(name)
    local separator = LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(name)
    if not separator then return 0 end
    return math.Clamp((separator.waterAmount or 0) / math.max(separator.maxWaterAmount or 1, 0.0001), 0, 1)
end

function LUASQUARE_STEAMSEPARATOR.GetLevelPercent(name)
    return LUASQUARE_STEAMSEPARATOR.GetLevelFraction(name) * 100
end

function LUASQUARE_STEAMSEPARATOR.GetPressure(name)
    local separator = LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(name)
    if not separator then return 0 end
    return LUASQUARE_STEAMSEPARATOR.UpdatePressure(name)
end

function LUASQUARE_STEAMSEPARATOR.UpdatePressure(nameOrSeparator)
    local separator = type(nameOrSeparator) == 'table' and nameOrSeparator or LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(nameOrSeparator)
    if not separator then return 0 end
    local referenceK = 100 + 273.15
    local steamK = math.max((separator.steamTemperature or 100) + 273.15, 1)
    separator.pressure = math.max(separator.steamAmount or 0, 0) / math.max(separator.steamVolume or 1, 0.0001) * (steamK / referenceK)
    return separator.pressure
end

function LUASQUARE_STEAMSEPARATOR.SetOutletValve(name, value)
    local separator = LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(name)
    if not separator then
        print('[LUASQUARE_STEAMSEPARATOR] Unknown separator: ' .. tostring(name))
        return false
    end

    separator.outletValve = math.Clamp(tonumber(value) or 0, 0, 1)
    return true
end

function LUASQUARE_STEAMSEPARATOR.AdjustOutletValvePercent(name, percentDelta)
    local separator = LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(name)
    if not separator then
        print('[LUASQUARE_STEAMSEPARATOR] Unknown separator: ' .. tostring(name))
        return false
    end

    return LUASQUARE_STEAMSEPARATOR.SetOutletValve(name, (separator.outletValve or 0) + (tonumber(percentDelta) or 0) / 100)
end

-- =========================================
-- INVENTORY
-- =========================================
local function addWaterInventory(separator, amount, temperature)
    amount = math.max(tonumber(amount) or 0, 0)
    local free = math.max((separator.hardMaxWaterAmount or separator.maxWaterAmount) - (separator.waterAmount or 0), 0)
    local moved = math.min(amount, free)
    if moved > 0 and LUASQUARE_FLUID and LUASQUARE_FLUID.MixTemperature then
        separator.waterTemperature = LUASQUARE_FLUID.MixTemperature(separator.waterAmount or 0, separator.waterTemperature or 100, moved, temperature or separator.waterTemperature)
    end
    separator.waterAmount = (separator.waterAmount or 0) + moved
    return moved
end

function LUASQUARE_STEAMSEPARATOR.AddWater(name, amount, temperature)
    local separator = LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(name)
    if not separator then
        print('[LUASQUARE_STEAMSEPARATOR] Unknown separator: ' .. tostring(name))
        return 0
    end

    local moved = addWaterInventory(separator, amount, temperature)
    separator.pendingFeedwaterIn = (separator.pendingFeedwaterIn or 0) + moved
    return moved
end

function LUASQUARE_STEAMSEPARATOR.RemoveWater(name, amount)
    local separator = LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(name)
    if not separator then
        print('[LUASQUARE_STEAMSEPARATOR] Unknown separator: ' .. tostring(name))
        return 0
    end

    amount = math.max(tonumber(amount) or 0, 0)
    local moved = math.min(amount, separator.waterAmount or 0)
    separator.waterAmount = math.max((separator.waterAmount or 0) - moved, 0)
    separator.pendingRecircOut = (separator.pendingRecircOut or 0) + moved
    return moved
end

function LUASQUARE_STEAMSEPARATOR.AddSteam(name, amount, temperature, thermalKJ)
    local separator = LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(name)
    if not separator then return 0 end
    amount = math.max(tonumber(amount) or 0, 0)
    local free = math.max((separator.hardMaxSteamAmount or separator.maxSteamAmount) - (separator.steamAmount or 0), 0)
    local moved = math.min(amount, free)
    if moved > 0 and LUASQUARE_FLUID and LUASQUARE_FLUID.MixTemperature then
        separator.steamTemperature = LUASQUARE_FLUID.MixTemperature(separator.steamAmount or 0, separator.steamTemperature or 100, moved, temperature or separator.steamTemperature)
    end
    separator.steamAmount = (separator.steamAmount or 0) + moved
    separator.thermalEnergyKJ = (separator.thermalEnergyKJ or 0) + math.max(tonumber(thermalKJ) or 0, 0) * (amount > 0 and moved / amount or 0)
    LUASQUARE_STEAMSEPARATOR.UpdatePressure(separator)
    return moved
end

function LUASQUARE_STEAMSEPARATOR.AcceptWetMixture(name, wetWater, wetSteam, waterTemperature, steamTemperature, thermalKJ, quality)
    local separator = LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(name)
    if not separator or not separator.enabled then return 0, 0 end

    wetWater = math.max(tonumber(wetWater) or 0, 0)
    wetSteam = math.max(tonumber(wetSteam) or 0, 0)
    local waterAccepted = addWaterInventory(separator, wetWater, waterTemperature or separator.waterTemperature)
    local steamAccepted = LUASQUARE_STEAMSEPARATOR.AddSteam(name, wetSteam, steamTemperature or separator.steamTemperature, thermalKJ)
    separator.pendingWetWaterIn = (separator.pendingWetWaterIn or 0) + waterAccepted
    separator.pendingWetSteamIn = (separator.pendingWetSteamIn or 0) + steamAccepted
    separator.lastSteamQuality = tonumber(quality) or separator.lastSteamQuality or 1
    return waterAccepted, steamAccepted
end

-- =========================================
-- UPDATE
-- =========================================
local function resetTelemetry(separator)
    separator.lastWetWaterIn = 0
    separator.lastWetSteamIn = 0
    separator.lastDrySteamOut = 0
    separator.lastCarryover = 0
    separator.lastFeedwaterIn = 0
    separator.lastRecircOut = 0
    separator.lastPressureScale = 0
    separator.lastThermalMW = 0
end

function LUASQUARE_STEAMSEPARATOR.GetCarryoverFraction(separator)
    local level = 0
    if (separator.maxWaterAmount or 0) > 0 then level = (separator.waterAmount or 0) / separator.maxWaterAmount end
    local high = separator.highLevelFraction or 0.85
    if level <= high then return 0 end
    local floodFactor = math.Clamp((level - high) / math.max(1 - high, 0.0001), 0, 1)
    local baseline = math.max(1 - (separator.separationEfficiency or 1), 0)
    return math.Clamp(baseline + floodFactor * 0.10, 0, 0.25)
end

function LUASQUARE_STEAMSEPARATOR.ExportDrySteam(name, separator, dt)
    if not separator.enabled or not separator.drySteamNetwork or not LUASQUARE_FLUID then return 0 end
    if (separator.steamAmount or 0) <= 0 or (separator.outletValve or 0) <= 0 then return 0 end

    LUASQUARE_STEAMSEPARATOR.UpdatePressure(separator)
    local target = LUASQUARE_FLUID.GetNetwork(separator.drySteamNetwork)
    if not target then return 0 end

    local pressureDelta = (separator.pressure or 0) - (target.pressure or 0)
    if pressureDelta <= 0 then return 0 end

    local pressureScale = math.Clamp(pressureDelta / math.max(separator.ratedOutputPressure or separator.maxPressure or 1, 0.0001), 0, 1)
    local requested = (separator.outputMaxSteamRate or 0) * (separator.outletValve or 0) * pressureScale * dt
    local moved = math.min(requested, separator.steamAmount or 0)
    if moved <= 0 then return 0 end

    local carryoverFraction = LUASQUARE_STEAMSEPARATOR.GetCarryoverFraction(separator)
    local energyShare = moved / math.max(separator.steamAmount or moved, 0.0001)
    local thermalKJ = (separator.thermalEnergyKJ or 0) * energyShare
    local quality = math.Clamp(1 - carryoverFraction, 0, 1)
    local accepted
    if LUASQUARE_FLUID.AddSteam then
        accepted = LUASQUARE_FLUID.AddSteam(separator.drySteamNetwork, moved, separator.steamTemperature, thermalKJ, quality, carryoverFraction)
    else
        accepted = LUASQUARE_FLUID.AddFluid(separator.drySteamNetwork, moved, separator.steamTemperature)
    end

    accepted = math.min(accepted or 0, moved)
    local acceptedShare = accepted / math.max(moved, 0.0001)
    separator.steamAmount = math.max((separator.steamAmount or 0) - accepted, 0)
    separator.thermalEnergyKJ = math.max((separator.thermalEnergyKJ or 0) - thermalKJ * acceptedShare, 0)
    separator.lastDrySteamOut = accepted / math.max(dt, 0.0001)
    separator.lastCarryover = carryoverFraction * accepted / math.max(dt, 0.0001)
    separator.lastPressureScale = pressureScale
    separator.lastThermalMW = (thermalKJ * acceptedShare / math.max(dt, 0.0001)) / 1000
    LUASQUARE_STEAMSEPARATOR.UpdatePressure(separator)
    return accepted
end

function LUASQUARE_STEAMSEPARATOR.UpdateSteamSeparator(name, dt)
    local separator = LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(name)
    if not separator then return end
    resetTelemetry(separator)
    separator.lastWetWaterIn = (separator.pendingWetWaterIn or 0) / math.max(dt, 0.0001)
    separator.lastWetSteamIn = (separator.pendingWetSteamIn or 0) / math.max(dt, 0.0001)
    separator.lastFeedwaterIn = (separator.pendingFeedwaterIn or 0) / math.max(dt, 0.0001)
    separator.lastRecircOut = (separator.pendingRecircOut or 0) / math.max(dt, 0.0001)
    separator.pendingWetWaterIn = 0
    separator.pendingWetSteamIn = 0
    separator.pendingFeedwaterIn = 0
    separator.pendingRecircOut = 0
    LUASQUARE_STEAMSEPARATOR.UpdatePressure(separator)
    LUASQUARE_STEAMSEPARATOR.ExportDrySteam(name, separator, dt)
    local level = LUASQUARE_STEAMSEPARATOR.GetLevelFraction(name)
    separator.lowLevel = level <= (separator.lowLevelFraction or 0.15)
    separator.flooded = level >= 1
end

function LUASQUARE_STEAMSEPARATOR.UpdateAll()
    local dt = LUASQUARE_STEAMSEPARATOR.TickInterval
    for name, _ in pairs(LUASQUARE_STEAMSEPARATOR.Separators) do
        LUASQUARE_STEAMSEPARATOR.UpdateSteamSeparator(name, dt)
    end
end

function LUASQUARE_STEAMSEPARATOR.Start()
    if timer.Exists('LUASQUARE_STEAMSEPARATOR_UpdateTimer') then timer.Remove('LUASQUARE_STEAMSEPARATOR_UpdateTimer') end
    timer.Create('LUASQUARE_STEAMSEPARATOR_UpdateTimer', LUASQUARE_STEAMSEPARATOR.TickInterval, 0, function() LUASQUARE_STEAMSEPARATOR.UpdateAll() end)
    print('[LUASQUARE_STEAMSEPARATOR] Started')
end

print('[LUASQUARE_STEAMSEPARATOR] Loaded')
