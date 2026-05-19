LUASQUARE_POWERPLANT = LUASQUARE_POWERPLANT or {}
LUASQUARE_POWERPLANT.Debug = LUASQUARE_POWERPLANT.Debug or {}
LUASQUARE_POWERPLANT.Debug.ClientState = {
    Networks = {},
    Pumps = {},
    Valves = {},
    Condensers = {}
}

local function copyMonitorPos(data)
    if not data or not data.monitorPos then return nil end
    return data.monitorPos + (data.monitorOffset or Vector(0, 0, 0))
end

function LUASQUARE_POWERPLANT.Debug.BuildNetworks()
    LUASQUARE_POWERPLANT.Debug.ClientState.Networks = {}
    if not LUASQUARE_FLUID then return end
    for name, network in pairs(LUASQUARE_FLUID.Networks) do
        local pos = copyMonitorPos(network)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.Networks, {
                name = name,
                type = network.type,
                fluidType = network.fluidType,
                amount = network.amount or 0,
                maxAmount = network.maxAmount or 0,
                hardMaxAmount = network.hardMaxAmount or 0,
                volume = network.volume or 0,
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

function LUASQUARE_POWERPLANT.Debug.BuildPumps()
    LUASQUARE_POWERPLANT.Debug.ClientState.Pumps = {}
    if not LUASQUARE_PUMP then return end
    for name, pump in pairs(LUASQUARE_PUMP.Pumps) do
        local pos = copyMonitorPos(pump)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.Pumps, {
                name = name,
                source = pump.source,
                target = pump.target,
                rate = pump.rate or 0,
                headPressure = pump.headPressure or 0,
                enabled = pump.enabled and true or false,
                speedLevel = pump.speedLevel or 1,
                speedMultiplier = LUASQUARE_PUMP.GetPumpSpeedMultiplier and LUASQUARE_PUMP.GetPumpSpeedMultiplier(pump) or 0,
                lastFlow = pump.lastFlow or 0,
                pos = pos
            })
        end
    end
end

function LUASQUARE_POWERPLANT.Debug.BuildValves()
    LUASQUARE_POWERPLANT.Debug.ClientState.Valves = {}
    if not LUASQUARE_VALVE then return end
    for name, valve in pairs(LUASQUARE_VALVE.Valves) do
        local pos = copyMonitorPos(valve)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.Valves, {
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

function LUASQUARE_POWERPLANT.Debug.BuildCondensers()
    LUASQUARE_POWERPLANT.Debug.ClientState.Condensers = {}
    if not LUASQUARE_CONDENSER then return end
    for name, condenser in pairs(LUASQUARE_CONDENSER.Condensers) do
        local pos = copyMonitorPos(condenser)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.Condensers, {
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

function LUASQUARE_POWERPLANT.Debug.Tick()
    LUASQUARE_POWERPLANT.Debug.BuildNetworks()
    LUASQUARE_POWERPLANT.Debug.BuildPumps()
    LUASQUARE_POWERPLANT.Debug.BuildValves()
    LUASQUARE_POWERPLANT.Debug.BuildCondensers()
    LUASQUARE_POWERPLANT.Debug.Broadcast()
end

function LUASQUARE_POWERPLANT.Debug.Broadcast()
    net.Start('LUASQUARE_PowerplantDebugState')
    net.WriteTable(LUASQUARE_POWERPLANT.Debug.ClientState)
    net.Broadcast()
end

function LUASQUARE_POWERPLANT.Debug.Start()
    if timer.Exists('LUASQUARE_POWERPLANT_DebugTimer') then timer.Remove('LUASQUARE_POWERPLANT_DebugTimer') end
    timer.Create('LUASQUARE_POWERPLANT_DebugTimer', 0.25, 0, function() LUASQUARE_POWERPLANT.Debug.Tick() end)
    print('[LUASQUARE_POWERPLANT_DEBUG] Started')
end
