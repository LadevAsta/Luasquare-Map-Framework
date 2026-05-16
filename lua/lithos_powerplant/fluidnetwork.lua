if LITHOS_FLUID_CORE_LOADED then return end
LITHOS_FLUID_CORE_LOADED = true
LITHOS_FLUID = LITHOS_FLUID or {}
LITHOS_FLUID.Networks = LITHOS_FLUID.Networks or {}
LITHOS_FLUID.EntityCache = LITHOS_FLUID.EntityCache or {}
LITHOS_FLUID.TickInterval = LITHOS_FLUID.TickInterval or 0.1
LITHOS_FLUID.PressureUnit = 'bar'

LITHOS_FLUID.TYPE_SIMPLE = 'simple'
LITHOS_FLUID.TYPE_STEAMLINE = 'steamline'

-- =========================================
-- ENTITY CACHE
-- =========================================
function LITHOS_FLUID.GetEnt(name)
    local cached = LITHOS_FLUID.EntityCache[name]
    if IsValid(cached) then return cached end
    local ent = ents.FindByName(name)[1]
    if IsValid(ent) then LITHOS_FLUID.EntityCache[name] = ent end
    return ent
end

function LITHOS_FLUID.FireRelay(name)
    local ent = LITHOS_FLUID.GetEnt(name)
    if not IsValid(ent) then
        print('[LITHOS_FLUID] Missing relay: ' .. tostring(name))
        return false
    end

    ent:Fire('Trigger')
    return true
end

-- =========================================
-- REGISTER
-- =========================================
function LITHOS_FLUID.RegisterNetwork(name, data)
    data = data or {}
    local networkType = data.type or LITHOS_FLUID.TYPE_SIMPLE
    local maxAmount = math.max(tonumber(data.maxAmount) or 100, 0.0001)
    local hardMaxAmount = maxAmount
    if networkType == LITHOS_FLUID.TYPE_STEAMLINE then hardMaxAmount = tonumber(data.hardMaxAmount) or maxAmount * 2 end
    hardMaxAmount = math.max(hardMaxAmount, maxAmount)
    LITHOS_FLUID.Networks[name] = {
        name = name,
        type = networkType,
        fluidType = data.fluidType or 'water',
        amount = math.Clamp(tonumber(data.amount) or 0, 0, hardMaxAmount),
        maxAmount = maxAmount,
        hardMaxAmount = hardMaxAmount,
        pressure = tonumber(data.pressure) or 0,
        maxPressure = tonumber(data.maxPressure) or 100,
        temperature = tonumber(data.temperature) or 20,
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

    LITHOS_FLUID.UpdatePressure(name)
end

function LITHOS_FLUID.GetNetwork(name)
    return LITHOS_FLUID.Networks[name]
end

-- =========================================
-- AMOUNT
-- =========================================
function LITHOS_FLUID.SetAmount(name, amount)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then
        print('[LITHOS_FLUID] Unknown network: ' .. tostring(name))
        return 0
    end

    network.amount = math.Clamp(tonumber(amount) or 0, 0, network.hardMaxAmount or network.maxAmount)
    LITHOS_FLUID.UpdatePressure(name)
    return network.amount
end

function LITHOS_FLUID.AddFluid(name, amount)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then
        print('[LITHOS_FLUID] Unknown network: ' .. tostring(name))
        return 0
    end

    amount = math.max(tonumber(amount) or 0, 0)
    local free = math.max((network.hardMaxAmount or network.maxAmount) - network.amount, 0)
    local moved = math.min(amount, free)
    network.amount = network.amount + moved
    LITHOS_FLUID.UpdatePressure(name)
    return moved
end

function LITHOS_FLUID.RemoveFluid(name, amount)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then
        print('[LITHOS_FLUID] Unknown network: ' .. tostring(name))
        return 0
    end

    amount = math.max(tonumber(amount) or 0, 0)
    local moved = math.min(amount, network.amount)
    network.amount = network.amount - moved
    LITHOS_FLUID.UpdatePressure(name)
    return moved
end

function LITHOS_FLUID.TransferFluid(fromName, toName, amount)
    local fromNetwork = LITHOS_FLUID.GetNetwork(fromName)
    local toNetwork = LITHOS_FLUID.GetNetwork(toName)
    if not fromNetwork then
        print('[LITHOS_FLUID] Unknown source network: ' .. tostring(fromName))
        return 0
    end

    if not toNetwork then
        print('[LITHOS_FLUID] Unknown target network: ' .. tostring(toName))
        return 0
    end

    local requested = math.max(tonumber(amount) or 0, 0)
    requested = requested * math.min(fromNetwork.flowMultiplier or 1, toNetwork.flowMultiplier or 1)
    local removed = LITHOS_FLUID.RemoveFluid(fromName, requested)
    local added = LITHOS_FLUID.AddFluid(toName, removed)
    if added < removed then LITHOS_FLUID.AddFluid(fromName, removed - added) end
    return added
end

function LITHOS_FLUID.GetFillFraction(name)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then return 0 end
    return math.Clamp(network.amount / network.maxAmount, 0, 1)
end

function LITHOS_FLUID.GetFillPercent(name)
    return LITHOS_FLUID.GetFillFraction(name) * 100
end

-- =========================================
-- PRESSURE AND TEMPERATURE
-- =========================================
function LITHOS_FLUID.UpdatePressure(name)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then return 0 end
    if network.type ~= LITHOS_FLUID.TYPE_STEAMLINE then return network.pressure or 0 end

    network.pressure = math.max(network.amount / network.maxAmount, 0) * network.maxPressure
    return network.pressure
end

function LITHOS_FLUID.SetPressure(name, pressure)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then
        print('[LITHOS_FLUID] Unknown network: ' .. tostring(name))
        return 0
    end

    network.pressure = math.max(tonumber(pressure) or 0, 0)
    return network.pressure
end

function LITHOS_FLUID.SetTemperature(name, temperature)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then
        print('[LITHOS_FLUID] Unknown network: ' .. tostring(name))
        return 0
    end

    network.temperature = tonumber(temperature) or network.temperature or 20
    return network.temperature
end

-- =========================================
-- SERVICE PUMP AND RUPTURE
-- =========================================
function LITHOS_FLUID.SetServicePump(name, enabled)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then
        print('[LITHOS_FLUID] Unknown network: ' .. tostring(name))
        return false
    end

    network.serviceEnabled = enabled and true or false
    return true
end

function LITHOS_FLUID.RuptureNetwork(name)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then
        print('[LITHOS_FLUID] Unknown network: ' .. tostring(name))
        return false
    end

    if network.ruptured then return true end
    if not network.ruptureRelays or #network.ruptureRelays <= 0 then return false end

    network.ruptured = true
    network.flowMultiplier = network.ruptureFlowMultiplier
    local relay = network.ruptureRelays[math.random(1, #network.ruptureRelays)]
    LITHOS_FLUID.FireRelay(relay)
    print('[LITHOS_FLUID] Network ruptured: ' .. tostring(name))
    return true
end

function LITHOS_FLUID.RepairNetwork(name)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then
        print('[LITHOS_FLUID] Unknown network: ' .. tostring(name))
        return false
    end

    network.ruptured = false
    network.flowMultiplier = 1
    return true
end

-- =========================================
-- UPDATE LOOP
-- =========================================
function LITHOS_FLUID.UpdateNetwork(name, dt)
    local network = LITHOS_FLUID.GetNetwork(name)
    if not network then return end

    if network.serviceEnabled and network.serviceRate > 0 then
        LITHOS_FLUID.AddFluid(name, network.serviceRate * dt)
    end

    if network.ruptured and network.ruptureLeakRate > 0 then
        LITHOS_FLUID.RemoveFluid(name, network.ruptureLeakRate * dt)
    end

    if network.type == LITHOS_FLUID.TYPE_STEAMLINE then
        LITHOS_FLUID.UpdatePressure(name)
        if network.pressure > network.maxPressure then LITHOS_FLUID.RuptureNetwork(name) end
    end
end

function LITHOS_FLUID.UpdateAll()
    local dt = LITHOS_FLUID.TickInterval
    for name, _ in pairs(LITHOS_FLUID.Networks) do
        LITHOS_FLUID.UpdateNetwork(name, dt)
    end
end

function LITHOS_FLUID.Start()
    if timer.Exists('LITHOS_FLUID_UpdateTimer') then timer.Remove('LITHOS_FLUID_UpdateTimer') end
    timer.Create('LITHOS_FLUID_UpdateTimer', LITHOS_FLUID.TickInterval, 0, function() LITHOS_FLUID.UpdateAll() end)
    print('[LITHOS_FLUID] Started')
end

print('[LITHOS_FLUID] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- include('lithos_powerplant/fluidnetwork.lua')
--
-- LITHOS_FLUID.RegisterNetwork('main_steam', {
--     type = LITHOS_FLUID.TYPE_STEAMLINE,
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
-- LITHOS_FLUID.RegisterNetwork('feedwater', {
--     type = LITHOS_FLUID.TYPE_SIMPLE,
--     fluidType = 'water',
--     amount = 5000,
--     maxAmount = 10000,
--     serviceRate = 25
-- })
--
-- LITHOS_FLUID.SetServicePump('feedwater', true)
-- LITHOS_FLUID.Start()
