LITHOS_POWERPLANT = LITHOS_POWERPLANT or {}
LITHOS_POWERPLANT.Debug = LITHOS_POWERPLANT.Debug or {}
LITHOS_POWERPLANT.Debug.ClientState = {
    Networks = {},
    Pumps = {},
    Valves = {},
    Condensers = {}
}

local function copyMonitorPos(data)
    if not data or not data.monitorPos then return nil end
    return data.monitorPos + (data.monitorOffset or Vector(0, 0, 0))
end

function LITHOS_POWERPLANT.Debug.BuildNetworks()
    LITHOS_POWERPLANT.Debug.ClientState.Networks = {}
    if not LITHOS_FLUID then return end
    for name, network in pairs(LITHOS_FLUID.Networks) do
        local pos = copyMonitorPos(network)
        if pos then
            table.insert(LITHOS_POWERPLANT.Debug.ClientState.Networks, {
                name = name,
                type = network.type,
                fluidType = network.fluidType,
                amount = network.amount or 0,
                maxAmount = network.maxAmount or 0,
                hardMaxAmount = network.hardMaxAmount or 0,
                pressure = network.pressure or 0,
                maxPressure = network.maxPressure or 0,
                temperature = network.temperature or 0,
                ruptured = network.ruptured and true or false,
                serviceEnabled = network.serviceEnabled and true or false,
                pos = pos
            })
        end
    end
end

function LITHOS_POWERPLANT.Debug.BuildPumps()
    LITHOS_POWERPLANT.Debug.ClientState.Pumps = {}
    if not LITHOS_PUMP then return end
    for name, pump in pairs(LITHOS_PUMP.Pumps) do
        local pos = copyMonitorPos(pump)
        if pos then
            table.insert(LITHOS_POWERPLANT.Debug.ClientState.Pumps, {
                name = name,
                source = pump.source,
                target = pump.target,
                rate = pump.rate or 0,
                headPressure = pump.headPressure or 0,
                enabled = pump.enabled and true or false,
                speedLevel = pump.speedLevel or 1,
                speedMultiplier = LITHOS_PUMP.GetPumpSpeedMultiplier and LITHOS_PUMP.GetPumpSpeedMultiplier(pump) or 0,
                lastFlow = pump.lastFlow or 0,
                pos = pos
            })
        end
    end
end

function LITHOS_POWERPLANT.Debug.BuildValves()
    LITHOS_POWERPLANT.Debug.ClientState.Valves = {}
    if not LITHOS_VALVE then return end
    for name, valve in pairs(LITHOS_VALVE.Valves) do
        local pos = copyMonitorPos(valve)
        if pos then
            table.insert(LITHOS_POWERPLANT.Debug.ClientState.Valves, {
                name = name,
                a = valve.a,
                b = valve.b,
                open = valve.open and true or false,
                bidirectional = valve.bidirectional and true or false,
                maxFlow = valve.maxFlow or 0,
                lastFlow = valve.lastFlow or 0,
                pos = pos
            })
        end
    end
end

function LITHOS_POWERPLANT.Debug.BuildCondensers()
    LITHOS_POWERPLANT.Debug.ClientState.Condensers = {}
    if not LITHOS_CONDENSER then return end
    for name, condenser in pairs(LITHOS_CONDENSER.Condensers) do
        local pos = copyMonitorPos(condenser)
        if pos then
            table.insert(LITHOS_POWERPLANT.Debug.ClientState.Condensers, {
                name = name,
                input = condenser.input,
                output = condenser.output,
                ratio = condenser.ratio or 0,
                enabled = condenser.enabled and true or false,
                godMode = condenser.godMode and true or false,
                lastSteamUsed = condenser.lastSteamUsed or 0,
                lastWaterMade = condenser.lastWaterMade or 0,
                pos = pos
            })
        end
    end
end

function LITHOS_POWERPLANT.Debug.Tick()
    LITHOS_POWERPLANT.Debug.BuildNetworks()
    LITHOS_POWERPLANT.Debug.BuildPumps()
    LITHOS_POWERPLANT.Debug.BuildValves()
    LITHOS_POWERPLANT.Debug.BuildCondensers()
    LITHOS_POWERPLANT.Debug.Broadcast()
end

function LITHOS_POWERPLANT.Debug.Broadcast()
    net.Start('LITHOS_PowerplantDebugState')
    net.WriteTable(LITHOS_POWERPLANT.Debug.ClientState)
    net.Broadcast()
end

function LITHOS_POWERPLANT.Debug.Start()
    if timer.Exists('LITHOS_POWERPLANT_DebugTimer') then timer.Remove('LITHOS_POWERPLANT_DebugTimer') end
    timer.Create('LITHOS_POWERPLANT_DebugTimer', 0.25, 0, function() LITHOS_POWERPLANT.Debug.Tick() end)
    print('[LITHOS_POWERPLANT_DEBUG] Started')
end
