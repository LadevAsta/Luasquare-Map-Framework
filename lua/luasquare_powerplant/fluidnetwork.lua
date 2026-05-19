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
    local hardMaxAmount = maxAmount
    if networkType == LUASQUARE_FLUID.TYPE_STEAMLINE then hardMaxAmount = tonumber(data.hardMaxAmount) or maxAmount * 2 end
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
        fluidType = data.fluidType or 'water',
        amount = math.Clamp(tonumber(data.amount) or 0, 0, hardMaxAmount),
        maxAmount = maxAmount,
        hardMaxAmount = hardMaxAmount,
        volume = math.max(volume, 0.0001),
        pressure = tonumber(data.pressure) or 0,
        maxPressure = maxPressure,
        pressureFactor = tonumber(data.pressureFactor) or 1,
        temperature = tonumber(data.temperature) or 20,
        ambientTemperature = tonumber(data.ambientTemperature) or 20,
        thermalLossRate = tonumber(data.thermalLossRate) or 0,
        serviceRate = tonumber(data.serviceRate) or 0,
        serviceEnabled = data.serviceEnabled and true or false,
        ruptured = false,
        ruptureRelays = data.ruptureRelays or {},
        ruptureLeakRate = tonumber(data.ruptureLeakRate) or 0,
        ruptureFlowMultiplier = tonumber(data.ruptureFlowMultiplier) or 0.25,
        flowMultiplier = 1,
        monitorPos = data.monitorPos,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }

    LUASQUARE_FLUID.UpdatePressure(name)
end

function LUASQUARE_FLUID.GetNetwork(name)
    return LUASQUARE_FLUID.Networks[name]
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
    network.amount = network.amount - moved
    LUASQUARE_FLUID.UpdatePressure(name)
    return moved
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

-- =========================================
-- PRESSURE AND TEMPERATURE
-- =========================================
function LUASQUARE_FLUID.UpdatePressure(name)
    local network = LUASQUARE_FLUID.GetNetwork(name)
    if not network then return 0 end
    if network.type ~= LUASQUARE_FLUID.TYPE_STEAMLINE then return network.pressure or 0 end

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

    if network.serviceEnabled and network.serviceRate > 0 then
        LUASQUARE_FLUID.AddFluid(name, network.serviceRate * dt)
    end

    if network.ruptured and network.ruptureLeakRate > 0 then
        LUASQUARE_FLUID.RemoveFluid(name, network.ruptureLeakRate * dt)
    end

    if network.thermalLossRate and network.thermalLossRate > 0 then
        local ambient = network.ambientTemperature or 20
        network.temperature = network.temperature + (ambient - network.temperature) * math.Clamp(network.thermalLossRate * dt, 0, 1)
    end

    if network.type == LUASQUARE_FLUID.TYPE_STEAMLINE then
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
