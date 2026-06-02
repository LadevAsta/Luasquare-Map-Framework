if LUASQUARE_FLUID_CORE_LOADED then return end
LUASQUARE_FLUID_CORE_LOADED = true
LUASQUARE_FLUID = LUASQUARE_FLUID or {}
LUASQUARE_FLUID.Networks = LUASQUARE_FLUID.Networks or {}
LUASQUARE_FLUID.EntityCache = LUASQUARE_FLUID.EntityCache or {}
LUASQUARE_FLUID.TickInterval = LUASQUARE_FLUID.TickInterval or 0.1
LUASQUARE_FLUID.PressureUnit = 'bar'
LUASQUARE_FLUID.ReferenceSteamTemperature = 100
LUASQUARE_FLUID.WaterThermalPressureFactor = 0.02

LUASQUARE_FLUID.TYPE_SIMPLE = 'simple'
LUASQUARE_FLUID.TYPE_STEAMLINE = 'steamline'
LUASQUARE_FLUID.TYPE_COOLANT = 'coolant'

local DEFAULT_WATER_HEAT_CAPACITY = 4.186

-- =========================================
-- ENTITY CACHE
-- =========================================
function LUASQUARE_FLUID.GetEnt(name)
    local cached = LUASQUARE_FLUID.EntityCache[name]
    if IsValid(cached) then return cached end
    local ent = ents.FindByName(name)[1]
    if IsValid(ent) then LUASQUARE_FLUID.EntityCache[name] = ent end
    return ent
end

function LUASQUARE_FLUID.FireRelay(name)
    local ent = LUASQUARE_FLUID.GetEnt(name)
    if not IsValid(ent) then
        print('[LUASQUARE_FLUID] Missing relay: ' .. tostring(name))
        return false
    end

    ent:Fire('Trigger')
    return true
end

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_FLUID.RegisterNetwork(name, data)
    data = data or {}
    local networkType = data.type or LUASQUARE_FLUID.TYPE_SIMPLE
    local maxAmount = math.max(tonumber(data.maxAmount) or 100, 0.0001)
    local hardMaxAmount = tonumber(data.hardMaxAmount)
    if not hardMaxAmount then
        if networkType == LUASQUARE_FLUID.TYPE_STEAMLINE or networkType == LUASQUARE_FLUID.TYPE_COOLANT then
            hardMaxAmount = maxAmount * 2
        else
            hardMaxAmount = maxAmount
        end
    end
    hardMaxAmount = math.max(hardMaxAmount, maxAmount)
    local maxPressure = tonumber(data.maxPressure) or 100
    local volume = tonumber(data.volume)
    if not volume then
        if networkType == LUASQUARE_FLUID.TYPE_STEAMLINE and (data.fluidType or 'water') == 'steam' then
            volume = maxAmount / math.max(maxPressure, 0.0001)
        else
            volume = maxAmount
        end
    end

    LUASQUARE_FLUID.Networks[name] = {
        name = name,
        type = networkType,
        fluidType = data.fluidType or (networkType == LUASQUARE_FLUID.TYPE_COOLANT and 'coolant' or 'water'),
        amount = math.Clamp(tonumber(data.amount) or 0, 0, hardMaxAmount),
        maxAmount = maxAmount,
        hardMaxAmount = hardMaxAmount,
        volume = math.max(volume, 0.0001),
        pressure = tonumber(data.pressure) or 0,
        maxPressure = maxPressure,
        pressureFactor = tonumber(data.pressureFactor) or 1,
        temperature = tonumber(data.temperature) or 20,
        thermalEnergyKJ = math.max(tonumber(data.thermalEnergyKJ) or 0, 0),
        lastThermalMW = 0,
        steamQuality = math.Clamp(tonumber(data.steamQuality) or 1, 0, 1),
        wetCarryover = math.max(tonumber(data.wetCarryover) or 0, 0),
        ambientTemperature = tonumber(data.ambientTemperature) or 20,
        thermalLossRate = tonumber(data.thermalLossRate) or 0,
        serviceRate = tonumber(data.serviceRate) or 0,
        serviceEnabled = data.serviceEnabled and true or false,
        overflowEnabled = data.overflowEnabled and true or false,
        overflowTarget = data.overflowTarget or 'void',
        overflowLevelFraction = math.Clamp(tonumber(data.overflowLevelFraction) or 0.99, 0, 1),
        overflowRate = tonumber(data.overflowRate) or math.huge,
        lastOverflowFlow = 0,
        ruptured = false,
        ruptureRelays = data.ruptureRelays or {},
        ruptureLeakRate = tonumber(data.ruptureLeakRate) or 0,
        ruptureFlowMultiplier = tonumber(data.ruptureFlowMultiplier) or 0.25,
        flowMultiplier = 1,
        coolingTower = data.coolingTower,
        coolantHeatCapacityKJPerL = tonumber(data.coolantHeatCapacityKJPerL) or DEFAULT_WATER_HEAT_CAPACITY,
        coolantCoolingDelta = tonumber(data.coolantCoolingDelta) or 1,
        coolantHighTemperature = tonumber(data.coolantHighTemperature),
        coolantOverheated = false,
        lastCoolantFlow = 0,
        lastCoolantHeatRemovedMW = 0,
        coolantCooling = false,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }

    LUASQUARE_FLUID.UpdatePressure(name)
end

function LUASQUARE_FLUID.GetNetwork(name)
    return LUASQUARE_FLUID.Networks[name]
end

function LUASQUARE_FLUID.GetCoolantCirculationFlow(name)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network or network.type ~= LUASQUARE_FLUID.TYPE_COOLANT then return 0 end

    local flow = 0
    if LUASQUARE_PUMP then
        for _, pump in pairs(LUASQUARE_PUMP.Pumps or {}) do
            if pump.source == name and (pump.target == name or pump.target == network.coolingTower) then
                flow = flow + math.max(pump.lastFlow or 0, 0)
            end
        end
    end

    network.lastCoolantFlow = flow
    return flow
end

function LUASQUARE_FLUID.GetCoolantNetworkForTower(towerName)
    if not towerName then return nil end
    for _, network in pairs(LUASQUARE_FLUID.Networks) do
        if network.type == LUASQUARE_FLUID.TYPE_COOLANT and network.coolingTower == towerName then return network end
    end
    return nil
end

-- =========================================
-- AMOUNT
-- =========================================
function LUASQUARE_FLUID.SetAmount(name, amount)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown network: ' .. tostring(name))
        return 0
    end

    network.amount = math.Clamp(tonumber(amount) or 0, 0, network.hardMaxAmount or network.maxAmount)
    LUASQUARE_FLUID.UpdatePressure(name)
    return network.amount
end

function LUASQUARE_FLUID.MixTemperature(currentAmount, currentTemperature, addedAmount, addedTemperature)
    currentAmount = math.max(tonumber(currentAmount) or 0, 0)
    addedAmount = math.max(tonumber(addedAmount) or 0, 0)
    currentTemperature = tonumber(currentTemperature) or 20
    addedTemperature = tonumber(addedTemperature) or currentTemperature
    local total = currentAmount + addedAmount
    if total <= 0 then return currentTemperature end
    return (currentTemperature * currentAmount + addedTemperature * addedAmount) / total
end

function LUASQUARE_FLUID.AddFluid(name, amount, temperature)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown network: ' .. tostring(name))
        return 0
    end

    amount = math.max(tonumber(amount) or 0, 0)
    local free = math.max((network.hardMaxAmount or network.maxAmount) - network.amount, 0)
    local moved = math.min(amount, free)
    network.temperature = LUASQUARE_FLUID.MixTemperature(network.amount, network.temperature, moved, temperature)
    network.amount = network.amount + moved
    LUASQUARE_FLUID.UpdatePressure(name)
    return moved
end

function LUASQUARE_FLUID.RemoveFluid(name, amount)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown network: ' .. tostring(name))
        return 0
    end

    amount = math.max(tonumber(amount) or 0, 0)
    local moved = math.min(amount, network.amount)
    if moved > 0 and (network.thermalEnergyKJ or 0) > 0 then
        local share = moved / math.max(network.amount, 0.0001)
        network.thermalEnergyKJ = math.max((network.thermalEnergyKJ or 0) - (network.thermalEnergyKJ or 0) * share, 0)
    end
    network.amount = network.amount - moved
    LUASQUARE_FLUID.UpdatePressure(name)
    return moved
end

function LUASQUARE_FLUID.AddSteam(name, amount, temperature, thermalKJ, quality, wetCarryover)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown steam network: ' .. tostring(name))
        return 0
    end

    amount = math.max(tonumber(amount) or 0, 0)
    local beforeAmount = network.amount or 0
    local beforeQuality = network.steamQuality or 1
    local beforeCarryover = network.wetCarryover or 0
    local moved = LUASQUARE_FLUID.AddFluid(name, amount, temperature)
    if moved <= 0 then return 0 end

    local acceptedFraction = amount > 0 and moved / amount or 0
    network.thermalEnergyKJ = (network.thermalEnergyKJ or 0) + math.max(tonumber(thermalKJ) or 0, 0) * acceptedFraction
    network.steamQuality = LUASQUARE_FLUID.MixTemperature(beforeAmount, beforeQuality, moved, math.Clamp(tonumber(quality) or 1, 0, 1))
    network.wetCarryover = LUASQUARE_FLUID.MixTemperature(beforeAmount, beforeCarryover, moved, math.max(tonumber(wetCarryover) or 0, 0))
    return moved
end

function LUASQUARE_FLUID.RemoveSteam(name, amount)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown steam network: ' .. tostring(name))
        return 0, 100, 0, 1, 0
    end

    amount = math.max(tonumber(amount) or 0, 0)
    local beforeAmount = math.max(network.amount or 0, 0)
    local moved = math.min(amount, beforeAmount)
    local share = beforeAmount > 0 and moved / beforeAmount or 0
    local thermalKJ = (network.thermalEnergyKJ or 0) * share
    local temperature = network.temperature or 100
    local quality = network.steamQuality or 1
    local wetCarryover = network.wetCarryover or 0
    if moved <= 0 then return 0, temperature, 0, quality, wetCarryover end

    network.amount = beforeAmount - moved
    network.thermalEnergyKJ = math.max((network.thermalEnergyKJ or 0) - thermalKJ, 0)
    if network.amount <= 0 then
        network.steamQuality = 1
        network.wetCarryover = 0
        network.thermalEnergyKJ = 0
    end
    LUASQUARE_FLUID.UpdatePressure(name)
    return moved, temperature, thermalKJ, quality, wetCarryover
end

function LUASQUARE_FLUID.TransferFluid(fromName, toName, amount)
    local fromNetwork = LUASQUARE_FLUID.GetNetwork(fromName)
    local toNetwork = LUASQUARE_FLUID.GetNetwork(toName)
    if not fromNetwork then
        print('[LUASQUARE_FLUID] Unknown source network: ' .. tostring(fromName))
        return 0
    end

    if not toNetwork then
        print('[LUASQUARE_FLUID] Unknown target network: ' .. tostring(toName))
        return 0
    end

    local requested = math.max(tonumber(amount) or 0, 0)
    requested = requested * math.min(fromNetwork.flowMultiplier or 1, toNetwork.flowMultiplier or 1)
    local removed = LUASQUARE_FLUID.RemoveFluid(fromName, requested)
    local added = LUASQUARE_FLUID.AddFluid(toName, removed, fromNetwork.temperature)
    if added < removed then LUASQUARE_FLUID.AddFluid(fromName, removed - added, fromNetwork.temperature) end
    return added
end

function LUASQUARE_FLUID.GetFillFraction(name)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then return 0 end
    return math.Clamp(network.amount / network.maxAmount, 0, 1)
end

function LUASQUARE_FLUID.GetFillPercent(name)
    return LUASQUARE_FLUID.GetFillFraction(name) * 100
end

function LUASQUARE_FLUID.SetOverflow(name, enabled)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown network: ' .. tostring(name))
        return false
    end

    network.overflowEnabled = enabled and true or false
    if not network.overflowEnabled then network.lastOverflowFlow = 0 end
    return true
end

function LUASQUARE_FLUID.AddToOverflowTarget(target, amount, temperature)
    amount = math.max(tonumber(amount) or 0, 0)
    if target == 'void' or target == nil then return amount end
    if LUASQUARE_STEAMSEPARATOR and LUASQUARE_STEAMSEPARATOR.GetSteamSeparator(target) then
        return LUASQUARE_STEAMSEPARATOR.AddWater(target, amount, temperature)
    end
    if LUASQUARE_DEAERATOR and LUASQUARE_DEAERATOR.GetDeaerator(target) then
        return LUASQUARE_DEAERATOR.AddWater(target, amount, temperature)
    end
    return LUASQUARE_FLUID.AddFluid(target, amount, temperature)
end

function LUASQUARE_FLUID.ApplyOverflow(name, dt)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then return 0 end
    network.lastOverflowFlow = 0
    if not network.overflowEnabled then return 0 end

    local threshold = (network.maxAmount or 0) * math.Clamp(network.overflowLevelFraction or 0.99, 0, 1)
    local excess = math.max((network.amount or 0) - threshold, 0)
    if excess <= 0 then return 0 end

    local requested = math.min(excess, math.max(network.overflowRate or math.huge, 0) * math.max(dt or LUASQUARE_FLUID.TickInterval or 0.1, 0))
    local temperature = network.temperature or 20
    local removed = LUASQUARE_FLUID.RemoveFluid(name, requested)
    local accepted = LUASQUARE_FLUID.AddToOverflowTarget(network.overflowTarget, removed, temperature)
    if accepted < removed then LUASQUARE_FLUID.AddFluid(name, removed - accepted, temperature) end
    network.lastOverflowFlow = accepted / math.max(dt or LUASQUARE_FLUID.TickInterval or 0.1, 0.0001)
    return accepted
end

-- =========================================
-- PRESSURE AND TEMPERATURE
-- =========================================
function LUASQUARE_FLUID.UpdatePressure(name)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then return 0 end
    if network.type ~= LUASQUARE_FLUID.TYPE_STEAMLINE and network.type ~= LUASQUARE_FLUID.TYPE_COOLANT then return network.pressure or 0 end

    if network.fluidType == 'steam' then
        local referenceK = LUASQUARE_FLUID.ReferenceSteamTemperature + 273.15
        local temperatureK = math.max((network.temperature or LUASQUARE_FLUID.ReferenceSteamTemperature) + 273.15, 1)
        network.pressure = math.max(network.amount / math.max(network.volume or network.maxAmount, 0.0001), 0) *
            (temperatureK / referenceK) * (network.pressureFactor or 1)
    else
        local fillPressure = math.max(network.amount / math.max(network.maxAmount, 0.0001), 0) * network.maxPressure
        local thermalPressure = math.max((network.temperature or 20) - 100, 0) * (LUASQUARE_FLUID.WaterThermalPressureFactor or 0)
        network.pressure = fillPressure + thermalPressure
    end

    return network.pressure
end

function LUASQUARE_FLUID.SetPressure(name, pressure)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown network: ' .. tostring(name))
        return 0
    end

    network.pressure = math.max(tonumber(pressure) or 0, 0)
    return network.pressure
end

function LUASQUARE_FLUID.SetTemperature(name, temperature)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown network: ' .. tostring(name))
        return 0
    end

    network.temperature = tonumber(temperature) or network.temperature or 20
    LUASQUARE_FLUID.UpdatePressure(name)
    return network.temperature
end

-- =========================================
-- SERVICE PUMP AND RUPTURE
-- =========================================
function LUASQUARE_FLUID.SetServicePump(name, enabled)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown network: ' .. tostring(name))
        return false
    end

    network.serviceEnabled = enabled and true or false
    return true
end

function LUASQUARE_FLUID.RuptureNetwork(name)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown network: ' .. tostring(name))
        return false
    end

    if network.ruptured then return true end
    if not network.ruptureRelays or #network.ruptureRelays <= 0 then return false end

    network.ruptured = true
    network.flowMultiplier = network.ruptureFlowMultiplier
    local relay = network.ruptureRelays[math.random(1, #network.ruptureRelays)]
    LUASQUARE_FLUID.FireRelay(relay)
    print('[LUASQUARE_FLUID] Network ruptured: ' .. tostring(name))
    return true
end

function LUASQUARE_FLUID.RepairNetwork(name)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then
        print('[LUASQUARE_FLUID] Unknown network: ' .. tostring(name))
        return false
    end

    network.ruptured = false
    network.flowMultiplier = 1
    return true
end

-- =========================================
-- UPDATE LOOP
-- =========================================
function LUASQUARE_FLUID.UpdateNetwork(name, dt)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then return end
    network.lastOverflowFlow = 0
    if network.type == LUASQUARE_FLUID.TYPE_COOLANT then
        network.lastCoolantFlow = LUASQUARE_FLUID.GetCoolantCirculationFlow(name)
        network.lastCoolantHeatRemovedMW = 0
        network.coolantCooling = false
        network.coolantOverheated = network.coolantHighTemperature and (network.temperature or 0) >= network.coolantHighTemperature or false
    end
    network.lastThermalMW = 0

    if network.serviceEnabled and network.serviceRate > 0 then
        LUASQUARE_FLUID.AddFluid(name, network.serviceRate * dt)
    end

    if network.ruptured and network.ruptureLeakRate > 0 then
        LUASQUARE_FLUID.RemoveFluid(name, network.ruptureLeakRate * dt)
    end

    LUASQUARE_FLUID.ApplyOverflow(name, dt)

    if network.thermalLossRate and network.thermalLossRate > 0 then
        local ambient = network.ambientTemperature or 20
        network.temperature = network.temperature + (ambient - network.temperature) * math.Clamp(network.thermalLossRate * dt, 0, 1)
    end
    if network.fluidType == 'steam' and (network.thermalEnergyKJ or 0) > 0 then
        network.lastThermalMW = (network.thermalEnergyKJ or 0) / math.max(dt, 0.0001) / 1000
    end

    if network.type == LUASQUARE_FLUID.TYPE_STEAMLINE or network.type == LUASQUARE_FLUID.TYPE_COOLANT then
        LUASQUARE_FLUID.UpdatePressure(name)
        if network.pressure > network.maxPressure then LUASQUARE_FLUID.RuptureNetwork(name) end
    end
end

function LUASQUARE_FLUID.UpdateAll()
    local dt = LUASQUARE_FLUID.TickInterval
    for name, _ in pairs(LUASQUARE_FLUID.Networks) do
        LUASQUARE_FLUID.UpdateNetwork(name, dt)
    end
end

function LUASQUARE_FLUID.Start()
    if timer.Exists('LUASQUARE_FLUID_UpdateTimer') then timer.Remove('LUASQUARE_FLUID_UpdateTimer') end
    timer.Create('LUASQUARE_FLUID_UpdateTimer', LUASQUARE_FLUID.TickInterval, 0, function() LUASQUARE_FLUID.UpdateAll() end)
    print('[LUASQUARE_FLUID] Started')
end

print('[LUASQUARE_FLUID] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- include('luasquare_powerplant/fluidnetwork.lua')
--
-- LUASQUARE_FLUID.RegisterNetwork('main_steam', {
--     type = LUASQUARE_FLUID.TYPE_STEAMLINE,
--     fluidType = 'steam',
--     amount = 0,
--     maxAmount = 10000,
--     maxPressure = 120,
--     temperature = 280,
--     ruptureRelays = {'steamline_rupture_a', 'steamline_rupture_b'},
--     ruptureLeakRate = 250,
--     ruptureFlowMultiplier = 0.25
-- })
--
-- LUASQUARE_FLUID.RegisterNetwork('feedwater', {
--     type = LUASQUARE_FLUID.TYPE_SIMPLE,
--     fluidType = 'water',
--     amount = 5000,
--     maxAmount = 10000,
--     serviceRate = 25
-- })
--
-- LUASQUARE_FLUID.SetServicePump('feedwater', true)
-- LUASQUARE_FLUID.Start()
