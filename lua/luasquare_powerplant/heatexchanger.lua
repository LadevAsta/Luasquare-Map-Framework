if LUASQUARE_HEATEXCHANGER_CORE_LOADED then return end
LUASQUARE_HEATEXCHANGER_CORE_LOADED = true
LUASQUARE_HEATEXCHANGER = LUASQUARE_HEATEXCHANGER or {}
LUASQUARE_HEATEXCHANGER.HeatExchangers = LUASQUARE_HEATEXCHANGER.HeatExchangers or {}
LUASQUARE_HEATEXCHANGER.TickInterval = LUASQUARE_HEATEXCHANGER.TickInterval or 0.1

local DEFAULT_WATER_HEAT_CAPACITY = 4.186

function LUASQUARE_HEATEXCHANGER.RegisterHeatExchanger(name, data)
    data = data or {}
    LUASQUARE_HEATEXCHANGER.HeatExchangers[name] = {
        name = name,
        hotNetwork = data.hotNetwork,
        coldNetwork = data.coldNetwork,
        hotPump = data.hotPump,
        coldPump = data.coldPump,
        effectiveness = math.Clamp(tonumber(data.effectiveness) or 0.75, 0, 1),
        approachTemperature = math.max(tonumber(data.approachTemperature) or 2, 0),
        maxThermalMW = tonumber(data.maxThermalMW),
        heatCapacityKJPerL = tonumber(data.heatCapacityKJPerL) or DEFAULT_WATER_HEAT_CAPACITY,
        enabled = data.enabled ~= false,
        lastHeatMW = 0,
        lastHotFlow = 0,
        lastColdFlow = 0,
        lastHotTemperature = 0,
        lastColdTemperature = 0,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
end

function LUASQUARE_HEATEXCHANGER.GetHeatExchanger(name)
    return LUASQUARE_HEATEXCHANGER.HeatExchangers[name]
end

function LUASQUARE_HEATEXCHANGER.SetHeatExchanger(name, enabled)
    local exchanger = LUASQUARE_HEATEXCHANGER.GetHeatExchanger(name)
    if not exchanger then
        print('[LUASQUARE_HEATEXCHANGER] Unknown heat exchanger: ' .. tostring(name))
        return false
    end

    exchanger.enabled = enabled and true or false
    return true
end

local function getPumpFlow(name)
    if not name or not LUASQUARE_PUMP then return 0 end
    local pump = LUASQUARE_PUMP.GetPump(name)
    if not pump or not pump.enabled then return 0 end
    return math.max(pump.lastFlow or 0, 0)
end

local function getNetworkFlow(pumpName, network)
    if network and LUASQUARE_FLUID and network.type == LUASQUARE_FLUID.TYPE_COOLANT and LUASQUARE_FLUID.GetCoolantCirculationFlow then
        return LUASQUARE_FLUID.GetCoolantCirculationFlow(network.name)
    end

    return getPumpFlow(pumpName)
end

local function addNetworkHeat(network, heatKJ, heatCapacity)
    if not network or math.abs(heatKJ) <= 0 then return end
    local thermalMass = math.max((network.amount or 0) * heatCapacity, 0.0001)
    network.temperature = (network.temperature or 20) + heatKJ / thermalMass
    if LUASQUARE_FLUID then LUASQUARE_FLUID.UpdatePressure(network.name) end
end

function LUASQUARE_HEATEXCHANGER.UpdateHeatExchanger(name, dt)
    local exchanger = LUASQUARE_HEATEXCHANGER.GetHeatExchanger(name)
    if not exchanger then return end

    exchanger.lastHeatMW = 0
    exchanger.lastHotFlow = 0
    exchanger.lastColdFlow = 0
    if not exchanger.enabled or not LUASQUARE_FLUID then return end

    local hot = LUASQUARE_FLUID.GetNetwork(exchanger.hotNetwork)
    local cold = LUASQUARE_FLUID.GetNetwork(exchanger.coldNetwork)
    if not hot or not cold then return end

    local hotFlow = getNetworkFlow(exchanger.hotPump, hot)
    local coldFlow = getNetworkFlow(exchanger.coldPump, cold)
    exchanger.lastHotFlow = hotFlow
    exchanger.lastColdFlow = coldFlow
    exchanger.lastHotTemperature = hot.temperature or 0
    exchanger.lastColdTemperature = cold.temperature or 0

    local flow = math.min(hotFlow, coldFlow)
    if flow <= 0 then return end

    local delta = (hot.temperature or 20) - (cold.temperature or 20) - (exchanger.approachTemperature or 0)
    if delta <= 0 then return end

    local heatCapacity = math.max(exchanger.heatCapacityKJPerL or DEFAULT_WATER_HEAT_CAPACITY, 0.0001)
    local heatKJ = flow * heatCapacity * delta * (exchanger.effectiveness or 0) * dt
    if exchanger.maxThermalMW then heatKJ = math.min(heatKJ, math.max(exchanger.maxThermalMW, 0) * 1000 * dt) end
    if heatKJ <= 0 then return end

    addNetworkHeat(hot, -heatKJ, heatCapacity)
    addNetworkHeat(cold, heatKJ, heatCapacity)
    exchanger.lastHeatMW = heatKJ / math.max(dt, 0.0001) / 1000
    exchanger.lastHotTemperature = hot.temperature or 0
    exchanger.lastColdTemperature = cold.temperature or 0
end

function LUASQUARE_HEATEXCHANGER.UpdateAll()
    local dt = LUASQUARE_HEATEXCHANGER.TickInterval
    for name, _ in pairs(LUASQUARE_HEATEXCHANGER.HeatExchangers) do
        LUASQUARE_HEATEXCHANGER.UpdateHeatExchanger(name, dt)
    end
end

function LUASQUARE_HEATEXCHANGER.Start()
    if timer.Exists('LUASQUARE_HEATEXCHANGER_UpdateTimer') then timer.Remove('LUASQUARE_HEATEXCHANGER_UpdateTimer') end
    timer.Create('LUASQUARE_HEATEXCHANGER_UpdateTimer', LUASQUARE_HEATEXCHANGER.TickInterval, 0, function() LUASQUARE_HEATEXCHANGER.UpdateAll() end)
    print('[LUASQUARE_HEATEXCHANGER] Started')
end

print('[LUASQUARE_HEATEXCHANGER] Loaded')
