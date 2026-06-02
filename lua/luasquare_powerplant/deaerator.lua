if LUASQUARE_DEAERATOR_CORE_LOADED then return end
LUASQUARE_DEAERATOR_CORE_LOADED = true
LUASQUARE_DEAERATOR = LUASQUARE_DEAERATOR or {}
LUASQUARE_DEAERATOR.Deaerators = LUASQUARE_DEAERATOR.Deaerators or {}
LUASQUARE_DEAERATOR.TickInterval = LUASQUARE_DEAERATOR.TickInterval or 0.1

local DEFAULT_WATER_HEAT_CAPACITY = 4.186
local DEFAULT_LATENT_HEAT = 2257

function LUASQUARE_DEAERATOR.RegisterDeaerator(name, data)
    data = data or {}
    local maxAmount = math.max(tonumber(data.maxAmount) or 100000, 0.0001)
    local hardMaxAmount = math.max(tonumber(data.hardMaxAmount) or maxAmount * 1.1, maxAmount)
    local steamSpace = math.max(tonumber(data.steamSpace) or maxAmount * 0.15, 0.0001)
    local steamMaxAmount = math.max(tonumber(data.steamMaxAmount) or steamSpace * 6, 0)

    LUASQUARE_DEAERATOR.Deaerators[name] = {
        name = name,
        tankNetwork = data.tankNetwork,
        steamInput = data.steamInput,
        steamSource = data.steamSource or data.steamTurbine or data.turbine,
        enabled = data.enabled and true or false,
        amount = math.Clamp(tonumber(data.amount) or tonumber(data.tankAmount) or 0, 0, hardMaxAmount),
        maxAmount = maxAmount,
        hardMaxAmount = hardMaxAmount,
        temperature = tonumber(data.temperature) or tonumber(data.tankTemperature) or 85,
        ambientTemperature = tonumber(data.ambientTemperature) or 20,
        thermalLossRate = tonumber(data.thermalLossRate) or 0.001,
        pressure = tonumber(data.pressure) or 0,
        maxPressure = tonumber(data.maxPressure) or 12,
        hardMaxPressure = tonumber(data.hardMaxPressure) or 20,
        pressureFactor = tonumber(data.pressureFactor) or 1,
        steamSpace = steamSpace,
        steamAmount = math.max(tonumber(data.steamAmount) or 0, 0),
        steamMaxAmount = steamMaxAmount,
        steamPressure = 0,
        steamTemperature = tonumber(data.steamTemperature) or tonumber(data.temperature) or 100,
        nonCondensibleAmount = math.max(tonumber(data.nonCondensibleAmount) or 0, 0),
        steamCondenseFraction = math.Clamp(tonumber(data.steamCondenseFraction) or 0.95, 0, 1),
        floodLevelFraction = math.Clamp(tonumber(data.floodLevelFraction) or 0.95, 0, 1),
        flooded = false,
        ruptured = data.ruptured and true or false,
        targetTemperature = tonumber(data.targetTemperature) or 105,
        targetPressure = tonumber(data.targetPressure) or 6,
        pressureDeadband = tonumber(data.pressureDeadband) or 0.25,
        temperatureDeadband = tonumber(data.temperatureDeadband) or 2,
        highTemperature = tonumber(data.highTemperature) or 120,
        highPressure = tonumber(data.highPressure) or tonumber(data.maxPressure) or 12,
        autoRegulator = data.autoRegulator and true or false,
        regulatorRate = tonumber(data.regulatorRate) or 0.2,
        steamValve = math.Clamp(tonumber(data.steamValve) or 0, 0, 1),
        reliefValve = math.Clamp(tonumber(data.reliefValve) or 0, 0, 1),
        overflowValve = math.Clamp(tonumber(data.overflowValve) or (data.overflowEnabled and 1 or 0), 0, 1),
        overflowTarget = data.overflowTarget,
        overflowLevelFraction = math.Clamp(tonumber(data.overflowLevelFraction) or 0.99, 0, 1),
        overflowRate = tonumber(data.overflowRate) or math.huge,
        maxSteamRate = tonumber(data.maxSteamRate) or 0,
        maxReliefRate = tonumber(data.maxReliefRate) or tonumber(data.reliefRate) or 500,
        floodedReliefFactor = math.Clamp(tonumber(data.floodedReliefFactor) or 0.2, 0, 1),
        steamToWaterRatio = tonumber(data.steamToWaterRatio) or 1600,
        steamLatentHeatKJPerL = tonumber(data.steamLatentHeatKJPerL) or DEFAULT_LATENT_HEAT,
        waterHeatCapacityKJPerL = tonumber(data.waterHeatCapacityKJPerL) or DEFAULT_WATER_HEAT_CAPACITY,
        ruptureRelays = data.ruptureRelays or {},
        pendingSteamUsed = 0,
        pendingWaterMade = 0,
        pendingHeatKJ = 0,
        lastSteamUsed = 0,
        lastWaterMade = 0,
        lastReliefFlow = 0,
        lastOverflowFlow = 0,
        lastHeatMW = 0,
        tankTemperature = 0,
        tankAmount = 0,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
    LUASQUARE_DEAERATOR.UpdatePressure(name)
end

function LUASQUARE_DEAERATOR.GetDeaerator(name)
    return LUASQUARE_DEAERATOR.Deaerators[name]
end

function LUASQUARE_DEAERATOR.GetEffectiveSteamSpace(deaerator)
    local fillFraction = math.Clamp((deaerator.amount or 0) / math.max(deaerator.maxAmount or 1, 0.0001), 0, 1.25)
    local spaceFraction = math.Clamp(1 - fillFraction, 0.05, 1)
    return math.max((deaerator.steamSpace or 1) * spaceFraction, 0.0001)
end

function LUASQUARE_DEAERATOR.UpdatePressure(nameOrDeaerator)
    local deaerator = type(nameOrDeaerator) == 'table' and nameOrDeaerator or LUASQUARE_DEAERATOR.GetDeaerator(nameOrDeaerator)
    if not deaerator then return 0 end

    local referenceK = (LUASQUARE_FLUID and LUASQUARE_FLUID.ReferenceSteamTemperature or 100) + 273.15
    local temperatureK = math.max((deaerator.steamTemperature or deaerator.temperature or 100) + 273.15, 1)
    local vaporMass = math.max((deaerator.steamAmount or 0) + (deaerator.nonCondensibleAmount or 0), 0)
    deaerator.steamPressure = vaporMass / LUASQUARE_DEAERATOR.GetEffectiveSteamSpace(deaerator) * (temperatureK / referenceK) * (deaerator.pressureFactor or 1)
    deaerator.pressure = deaerator.steamPressure
    deaerator.tankAmount = deaerator.amount or 0
    deaerator.tankTemperature = deaerator.temperature or 0
    deaerator.flooded = (deaerator.amount or 0) >= (deaerator.maxAmount or 0) * (deaerator.floodLevelFraction or 1)
    return deaerator.pressure
end

function LUASQUARE_DEAERATOR.GetLevelPercent(name)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then return 0 end
    return math.Clamp((deaerator.amount or 0) / math.max(deaerator.maxAmount or 1, 0.0001) * 100, 0, 100)
end

function LUASQUARE_DEAERATOR.AddWater(name, amount, temperature)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator or deaerator.ruptured then return 0 end
    amount = math.max(tonumber(amount) or 0, 0)
    local free = math.max((deaerator.hardMaxAmount or deaerator.maxAmount) - (deaerator.amount or 0), 0)
    local moved = math.min(amount, free)
    if moved <= 0 then return 0 end
    if LUASQUARE_FLUID and LUASQUARE_FLUID.MixTemperature then
        deaerator.temperature = LUASQUARE_FLUID.MixTemperature(deaerator.amount or 0, deaerator.temperature or 20, moved, temperature or deaerator.temperature)
    end
    deaerator.amount = (deaerator.amount or 0) + moved
    LUASQUARE_DEAERATOR.UpdatePressure(deaerator)
    return moved
end

function LUASQUARE_DEAERATOR.RemoveWater(name, amount)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator or deaerator.ruptured then return 0 end
    amount = math.max(tonumber(amount) or 0, 0)
    local moved = math.min(amount, deaerator.amount or 0)
    deaerator.amount = math.max((deaerator.amount or 0) - moved, 0)
    LUASQUARE_DEAERATOR.UpdatePressure(deaerator)
    return moved
end

function LUASQUARE_DEAERATOR.GetTemperature(name)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    return deaerator and deaerator.temperature or 20
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

function LUASQUARE_DEAERATOR.SetSteamValve(name, value)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then return false end
    deaerator.steamValve = math.Clamp(tonumber(value) or 0, 0, 1)
    return true
end

function LUASQUARE_DEAERATOR.AdjustSteamValve(name, delta)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then return false end
    return LUASQUARE_DEAERATOR.SetSteamValve(name, deaerator.steamValve + (tonumber(delta) or 0))
end

function LUASQUARE_DEAERATOR.SetSteamValvePercent(name, percent)
    return LUASQUARE_DEAERATOR.SetSteamValve(name, (tonumber(percent) or 0) / 100)
end

function LUASQUARE_DEAERATOR.AdjustSteamValvePercent(name, percentDelta)
    return LUASQUARE_DEAERATOR.AdjustSteamValve(name, (tonumber(percentDelta) or 0) / 100)
end

function LUASQUARE_DEAERATOR.SetReliefValve(name, value)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then return false end
    deaerator.reliefValve = math.Clamp(tonumber(value) or 0, 0, 1)
    return true
end

function LUASQUARE_DEAERATOR.AdjustReliefValve(name, delta)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then return false end
    return LUASQUARE_DEAERATOR.SetReliefValve(name, deaerator.reliefValve + (tonumber(delta) or 0))
end

function LUASQUARE_DEAERATOR.SetReliefValvePercent(name, percent)
    return LUASQUARE_DEAERATOR.SetReliefValve(name, (tonumber(percent) or 0) / 100)
end

function LUASQUARE_DEAERATOR.AdjustReliefValvePercent(name, percentDelta)
    return LUASQUARE_DEAERATOR.AdjustReliefValve(name, (tonumber(percentDelta) or 0) / 100)
end

function LUASQUARE_DEAERATOR.SetOverflowValve(name, value)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then return false end
    deaerator.overflowValve = math.Clamp(tonumber(value) or 0, 0, 1)
    if deaerator.overflowValve <= 0 then deaerator.lastOverflowFlow = 0 end
    return true
end

function LUASQUARE_DEAERATOR.AdjustOverflowValve(name, delta)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then return false end
    return LUASQUARE_DEAERATOR.SetOverflowValve(name, deaerator.overflowValve + (tonumber(delta) or 0))
end

function LUASQUARE_DEAERATOR.SetOverflowValvePercent(name, percent)
    return LUASQUARE_DEAERATOR.SetOverflowValve(name, (tonumber(percent) or 0) / 100)
end

function LUASQUARE_DEAERATOR.AdjustOverflowValvePercent(name, percentDelta)
    return LUASQUARE_DEAERATOR.AdjustOverflowValve(name, (tonumber(percentDelta) or 0) / 100)
end

function LUASQUARE_DEAERATOR.SetAutoRegulator(name, enabled)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then return false end
    deaerator.autoRegulator = enabled and true or false
    return true
end

local function fireRuptureRelays(deaerator)
    if not LUASQUARE_FLUID then return end
    for _, relay in ipairs(deaerator.ruptureRelays or {}) do
        LUASQUARE_FLUID.FireRelay(relay)
    end
end

function LUASQUARE_DEAERATOR.Rupture(name, reason)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator or deaerator.ruptured then return false end
    deaerator.ruptured = true
    deaerator.enabled = false
    deaerator.steamValve = 0
    deaerator.reliefValve = 1
    deaerator.ruptureReason = reason or 'OVERPRESSURE'
    fireRuptureRelays(deaerator)
    print('[LUASQUARE_DEAERATOR] Ruptured ' .. tostring(name) .. ': ' .. tostring(deaerator.ruptureReason))
    return true
end

local function updateAutoRegulator(deaerator, dt)
    if not deaerator.autoRegulator then return end
    local rate = (deaerator.regulatorRate or 0.2) * dt
    local pressure = deaerator.pressure or 0
    local pressureTarget = deaerator.targetPressure or 0
    local pressureBand = deaerator.pressureDeadband or 0
    local temperature = deaerator.temperature or 20
    local temperatureTarget = deaerator.targetTemperature or 105
    local temperatureBand = deaerator.temperatureDeadband or 0

    if pressure > pressureTarget + pressureBand then
        deaerator.reliefValve = math.Clamp((deaerator.reliefValve or 0) + rate * 2, 0, 1)
        deaerator.steamValve = math.Clamp((deaerator.steamValve or 0) - rate, 0, 1)
    elseif pressure < pressureTarget - pressureBand then
        deaerator.reliefValve = math.Clamp((deaerator.reliefValve or 0) - rate * 2, 0, 1)
        if temperature < temperatureTarget - temperatureBand then
            deaerator.steamValve = math.Clamp((deaerator.steamValve or 0) + rate, 0, 1)
        end
    elseif temperature < temperatureTarget - temperatureBand then
        deaerator.steamValve = math.Clamp((deaerator.steamValve or 0) + rate, 0, 1)
        deaerator.reliefValve = math.Clamp((deaerator.reliefValve or 0) - rate, 0, 1)
    else
        deaerator.steamValve = math.Clamp((deaerator.steamValve or 0) - rate, 0, 1)
        deaerator.reliefValve = math.Clamp((deaerator.reliefValve or 0) - rate, 0, 1)
    end
end

local function addHeatingSteam(name, deaerator, steamAmount, steamTemperature)
    local condenseFraction = math.Clamp(deaerator.steamCondenseFraction or 0.95, 0, 1)
    local retainedSteam = steamAmount * (1 - condenseFraction)
    local condensedSteam = steamAmount - retainedSteam
    local ratio = math.max(deaerator.steamToWaterRatio or 1600, 0.0001)
    local waterMade = condensedSteam / ratio
    local added = LUASQUARE_DEAERATOR.AddWater(name, waterMade, steamTemperature or deaerator.steamTemperature)

    if added < waterMade then
        local rejectedWater = waterMade - added
        condensedSteam = math.max(condensedSteam - rejectedWater * ratio, 0)
        waterMade = added
    end

    local steamFree = math.max((deaerator.steamMaxAmount or 0) - (deaerator.steamAmount or 0), 0)
    local retained = math.min(retainedSteam, steamFree)
    if retained > 0 and LUASQUARE_FLUID and LUASQUARE_FLUID.MixTemperature then
        deaerator.steamTemperature = LUASQUARE_FLUID.MixTemperature(deaerator.steamAmount or 0, deaerator.steamTemperature or 100, retained, steamTemperature or deaerator.steamTemperature)
    end
    deaerator.steamAmount = (deaerator.steamAmount or 0) + retained

    local cp = math.max(deaerator.waterHeatCapacityKJPerL or DEFAULT_WATER_HEAT_CAPACITY, 0.0001)
    local latent = math.max(deaerator.steamLatentHeatKJPerL or DEFAULT_LATENT_HEAT, 0.0001)
    local heatKJ = waterMade * latent
    if heatKJ > 0 and (deaerator.amount or 0) > 0 then
        deaerator.temperature = math.min(math.max(deaerator.targetTemperature or 105, deaerator.temperature or 20), (deaerator.temperature or 20) + heatKJ / math.max((deaerator.amount or 0) * cp, 0.0001))
    end

    LUASQUARE_DEAERATOR.UpdatePressure(deaerator)
    deaerator.pendingSteamUsed = (deaerator.pendingSteamUsed or 0) + steamAmount
    deaerator.pendingWaterMade = (deaerator.pendingWaterMade or 0) + waterMade
    deaerator.pendingHeatKJ = (deaerator.pendingHeatKJ or 0) + heatKJ
    return steamAmount, waterMade, heatKJ
end

function LUASQUARE_DEAERATOR.PullFromTurbineExhaust(turbineName, turbine, dt)
    if not LUASQUARE_TURBINE or not LUASQUARE_TURBINE.TakeExhaustSteam then return 0 end
    local total = 0
    for name, deaerator in pairs(LUASQUARE_DEAERATOR.Deaerators or {}) do
        if deaerator.enabled and not deaerator.ruptured and deaerator.steamSource == turbineName then
            local freeWater = math.max((deaerator.hardMaxAmount or deaerator.maxAmount) - (deaerator.amount or 0), 0)
            local ratio = math.max(deaerator.steamToWaterRatio or 1600, 0.0001)
            local request = math.min((deaerator.maxSteamRate or 0) * (deaerator.steamValve or 0) * dt, freeWater * ratio)
            if request > 0 then
                local removed, temperature = LUASQUARE_TURBINE.TakeExhaustSteam(turbine or turbineName, request)
                if removed > 0 then
                    addHeatingSteam(name, deaerator, removed, temperature)
                    total = total + removed
                end
            end
        end
    end
    return total
end

local function consumeLegacyHeatingSteam(name, deaerator, dt)
    if deaerator.steamSource then return end
    if not deaerator.enabled or not deaerator.steamInput or not LUASQUARE_FLUID then return end
    local steam = LUASQUARE_FLUID.GetNetwork(deaerator.steamInput)
    if not steam then return end

    local ratio = math.max(deaerator.steamToWaterRatio or 1600, 0.0001)
    local freeWater = math.max((deaerator.hardMaxAmount or deaerator.maxAmount) - (deaerator.amount or 0), 0)
    local steamWanted = math.min((deaerator.maxSteamRate or 0) * (deaerator.steamValve or 0) * dt, steam.amount or 0, freeWater * ratio)
    if steamWanted <= 0 then return end

    local removed = LUASQUARE_FLUID.RemoveFluid(deaerator.steamInput, steamWanted)
    local used = addHeatingSteam(name, deaerator, removed, steam.temperature)
    if used < removed then LUASQUARE_FLUID.AddFluid(deaerator.steamInput, removed - used, steam.temperature) end
end

local function ventRelief(deaerator, dt)
    local relief = math.max(deaerator.maxReliefRate or 0, 0) * math.max(deaerator.reliefValve or 0, 0) * dt
    if relief <= 0 then return end
    if deaerator.flooded then relief = relief * (deaerator.floodedReliefFactor or 0.2) end
    local steamRemoved = math.min(relief, deaerator.steamAmount or 0)
    deaerator.steamAmount = math.max((deaerator.steamAmount or 0) - steamRemoved, 0)
    local remaining = relief - steamRemoved
    local gasRemoved = math.min(remaining, deaerator.nonCondensibleAmount or 0)
    deaerator.nonCondensibleAmount = math.max((deaerator.nonCondensibleAmount or 0) - gasRemoved, 0)
    deaerator.lastReliefFlow = (steamRemoved + gasRemoved) / math.max(dt, 0.0001)
    LUASQUARE_DEAERATOR.UpdatePressure(deaerator)
end

local function addToOverflowTarget(target, amount, temperature)
    amount = math.max(tonumber(amount) or 0, 0)
    if target == 'void' or target == nil then return amount end
    if LUASQUARE_FLUID and LUASQUARE_FLUID.GetNetwork(target) then
        return LUASQUARE_FLUID.AddFluid(target, amount, temperature)
    end
    if LUASQUARE_STEAMSEPARATOR and LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(target) then
        return LUASQUARE_STEAMSEPARATOR.AddWater(target, amount, temperature)
    end
    if LUASQUARE_DEAERATOR and LUASQUARE_DEAERATOR.GetDeaerator(target) then
        return LUASQUARE_DEAERATOR.AddWater(target, amount, temperature)
    end
    return 0
end

local function applyOverflow(name, deaerator, dt)
    deaerator.lastOverflowFlow = 0
    if (deaerator.overflowValve or 0) <= 0 or not deaerator.overflowTarget then return end

    local threshold = (deaerator.maxAmount or 0) * math.Clamp(deaerator.overflowLevelFraction or 0.99, 0, 1)
    local excess = math.max((deaerator.amount or 0) - threshold, 0)
    if excess <= 0 then return end

    local requested = math.min(excess, math.max(deaerator.overflowRate or math.huge, 0) * (deaerator.overflowValve or 0) * dt)
    local temperature = deaerator.temperature or 20
    local removed = LUASQUARE_DEAERATOR.RemoveWater(name, requested)
    local accepted = addToOverflowTarget(deaerator.overflowTarget, removed, temperature)
    if accepted < removed then LUASQUARE_DEAERATOR.AddWater(name, removed - accepted, temperature) end
    deaerator.lastOverflowFlow = accepted / math.max(dt, 0.0001)
end

local function applyThermalLoss(deaerator, dt)
    local rate = math.max(deaerator.thermalLossRate or 0, 0)
    if rate <= 0 then return end
    local ambient = deaerator.ambientTemperature or 20
    local factor = math.Clamp(rate * dt, 0, 1)
    deaerator.temperature = (deaerator.temperature or ambient) + (ambient - (deaerator.temperature or ambient)) * factor
    deaerator.steamTemperature = (deaerator.steamTemperature or ambient) + (ambient - (deaerator.steamTemperature or ambient)) * factor
end

function LUASQUARE_DEAERATOR.UpdateDeaerator(name, dt)
    local deaerator = LUASQUARE_DEAERATOR.GetDeaerator(name)
    if not deaerator then return end

    deaerator.lastSteamUsed = (deaerator.pendingSteamUsed or 0) / math.max(dt, 0.0001)
    deaerator.lastWaterMade = (deaerator.pendingWaterMade or 0) / math.max(dt, 0.0001)
    deaerator.lastHeatMW = (deaerator.pendingHeatKJ or 0) / math.max(dt, 0.0001) / 1000
    deaerator.pendingSteamUsed = 0
    deaerator.pendingWaterMade = 0
    deaerator.pendingHeatKJ = 0
    deaerator.lastReliefFlow = 0
    deaerator.lastOverflowFlow = 0
    LUASQUARE_DEAERATOR.UpdatePressure(deaerator)
    if deaerator.ruptured then return end

    updateAutoRegulator(deaerator, dt)
    consumeLegacyHeatingSteam(name, deaerator, dt)
    ventRelief(deaerator, dt)
    applyOverflow(name, deaerator, dt)
    applyThermalLoss(deaerator, dt)
    LUASQUARE_DEAERATOR.UpdatePressure(deaerator)
    if (deaerator.pressure or 0) >= (deaerator.hardMaxPressure or math.huge) then
        LUASQUARE_DEAERATOR.Rupture(name, 'OVERPRESSURE')
    end
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
