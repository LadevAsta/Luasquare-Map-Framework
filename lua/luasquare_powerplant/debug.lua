LUASQUARE_POWERPLANT = LUASQUARE_POWERPLANT or {}
LUASQUARE_POWERPLANT.Debug = LUASQUARE_POWERPLANT.Debug or {}
LUASQUARE_POWERPLANT.Debug.ClientState = {
    Networks = {},
    Pumps = {},
    Valves = {},
    Condensers = {},
    Turbines = {},
    CoolingTowers = {},
    Grids = {},
    Breakers = {},
    Transformers = {},
    Generators = {},
    DieselGenerators = {}
}

local DEBUG_WIRE_VERSION = 1
local DEBUG_PACKET_START = 1
local DEBUG_PACKET_CATEGORY = 2
local DEBUG_PACKET_END = 3

local DEBUG_CATEGORIES = {
    {name = 'Networks', chunkSize = 32, schema = {
        {'name', 'string'}, {'type', 'string'}, {'fluidType', 'string'},
        {'amount', 'number'}, {'maxAmount', 'number'}, {'hardMaxAmount', 'number'},
        {'volume', 'number'}, {'pressure', 'number'}, {'maxPressure', 'number'}, {'temperature', 'number'},
        {'ruptured', 'bool'}, {'serviceEnabled', 'bool'}, {'pos', 'vector'}
    }},
    {name = 'Pumps', chunkSize = 32, schema = {
        {'name', 'string'}, {'source', 'string'}, {'target', 'string'},
        {'rate', 'number'}, {'headPressure', 'number'}, {'enabled', 'bool'},
        {'speedLevel', 'number'}, {'speedMultiplier', 'number'}, {'regulate', 'bool'},
        {'regulationMode', 'string'}, {'regulationTarget', 'number'}, {'regulationLevel', 'number'},
        {'regulationFactor', 'number'}, {'grid', 'string'}, {'breaker', 'string'},
        {'peakMW', 'number'}, {'lastPowerMW', 'number'}, {'lastPowerAcceptedMW', 'number'},
        {'lastFlow', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Valves', chunkSize = 48, schema = {
        {'name', 'string'}, {'a', 'string'}, {'b', 'string'},
        {'open', 'bool'}, {'bidirectional', 'bool'}, {'maxFlow', 'number'}, {'lastFlow', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Condensers', chunkSize = 32, schema = {
        {'name', 'string'}, {'input', 'string'}, {'output', 'string'}, {'ratio', 'number'},
        {'enabled', 'bool'}, {'godMode', 'bool'}, {'lastSteamUsed', 'number'}, {'lastWaterMade', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Turbines', chunkSize = 16, schema = {
        {'name', 'string'}, {'input', 'string'}, {'boiler', 'string'}, {'output', 'string'},
        {'condenserOutput', 'string'}, {'bypassCondenserOutput', 'string'},
        {'enabled', 'bool'}, {'tripped', 'bool'}, {'tripLevel', 'string'}, {'tripRelayFired', 'bool'},
        {'severeTripFired', 'bool'}, {'severeTripStopFired', 'bool'}, {'severeTripRPM', 'number'},
        {'severeTripBrakeRPM', 'number'}, {'extremeTripFired', 'bool'}, {'extremeTripRPM', 'number'},
        {'catastrophicFailed', 'bool'}, {'synced', 'bool'}, {'autoSync', 'bool'},
        {'valve', 'number'}, {'bypassValve', 'number'}, {'maxSteamRate', 'number'}, {'ratedSteamRate', 'number'},
        {'rpm', 'number'}, {'phase', 'number'}, {'vibration', 'number'}, {'cycleEfficiency', 'number'},
        {'lastBoilerMW', 'number'}, {'lastSteamShare', 'number'}, {'lastTurbineSteamFraction', 'number'},
        {'lastInletSteam', 'number'}, {'lastInletPressureScale', 'number'}, {'lastSteamUsed', 'number'},
        {'lastBypassSteam', 'number'}, {'lastExhaustMade', 'number'}, {'lastCondensateMade', 'number'},
        {'lastBypassCondensateMade', 'number'}, {'lastCondensateTemperature', 'number'},
        {'lastBypassCondensateTemperature', 'number'}, {'lastMW', 'number'}, {'tripReason', 'string'}, {'pos', 'vector'}
    }},
    {name = 'CoolingTowers', chunkSize = 24, schema = {
        {'name', 'string'}, {'input', 'string'}, {'basin', 'string'}, {'output', 'string'},
        {'maxRate', 'number'}, {'enabled', 'bool'}, {'working', 'bool'}, {'outputTemperature', 'number'},
        {'basinAmount', 'number'}, {'basinMaxAmount', 'number'}, {'basinTemperature', 'number'},
        {'basinPressure', 'number'}, {'basinMaxPressure', 'number'}, {'lastWaterReceived', 'number'},
        {'lastWaterCooled', 'number'}, {'lastHeatRemoved', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Grids', chunkSize = 24, schema = {
        {'name', 'string'}, {'type', 'string'}, {'enabled', 'bool'}, {'tripped', 'bool'},
        {'energized', 'bool'}, {'stiff', 'bool'}, {'frequency', 'number'}, {'nominalFrequency', 'number'},
        {'voltage', 'number'}, {'phase', 'number'}, {'sourceCapacityMW', 'number'},
        {'availableImportMW', 'number'}, {'lastGenerationMW', 'number'}, {'lastLoadMW', 'number'},
        {'lastImportMW', 'number'}, {'lastAvailableMW', 'number'}, {'lastBalanceMW', 'number'},
        {'tripReason', 'string'}, {'pos', 'vector'}
    }},
    {name = 'Breakers', chunkSize = 32, schema = {
        {'name', 'string'}, {'grid', 'string'}, {'owner', 'string'}, {'kind', 'string'},
        {'closed', 'bool'}, {'tripped', 'bool'}, {'maxMW', 'number'}, {'lastMW', 'number'},
        {'tripReason', 'string'}, {'pos', 'vector'}
    }},
    {name = 'Transformers', chunkSize = 32, schema = {
        {'name', 'string'}, {'from', 'string'}, {'to', 'string'}, {'enabled', 'bool'}, {'closed', 'bool'},
        {'bidirectional', 'bool'}, {'tripped', 'bool'}, {'available', 'bool'}, {'maxMW', 'number'},
        {'lastMW', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Generators', chunkSize = 24, schema = {
        {'name', 'string'}, {'type', 'string'}, {'grid', 'string'}, {'breaker', 'string'},
        {'enabled', 'bool'}, {'tripped', 'bool'}, {'synced', 'bool'}, {'turbine', 'string'},
        {'ratedMW', 'number'}, {'maxMW', 'number'}, {'outputMW', 'number'}, {'targetMW', 'number'},
        {'lastMW', 'number'}, {'lastAcceptedMW', 'number'}, {'lastRPMError', 'number'},
        {'lastPhaseError', 'number'}, {'lastSyncBlockReason', 'string'}, {'tripReason', 'string'}, {'pos', 'vector'}
    }},
    {name = 'DieselGenerators', chunkSize = 32, schema = {
        {'name', 'string'}, {'generator', 'string'}, {'fuelNetwork', 'string'}, {'enabled', 'bool'},
        {'targetMW', 'number'}, {'lastTargetMW', 'number'}, {'lastAvailableMW', 'number'},
        {'fuelTankAmount', 'number'}, {'fuelTankCapacity', 'number'}, {'lastFuelDraw', 'number'},
        {'lastFuelUsed', 'number'}, {'pos', 'vector'}
    }}
}

local function startDebugPacket(packetType, sequence)
    net.Start('LUASQUARE_PowerplantDebugState')
    net.WriteUInt(DEBUG_WIRE_VERSION, 8)
    net.WriteUInt(packetType, 4)
    net.WriteUInt(sequence, 16)
end

local function writeValue(valueType, value)
    if valueType == 'number' then
        net.WriteFloat(value or 0)
    elseif valueType == 'bool' then
        net.WriteBool(value and true or false)
    elseif valueType == 'vector' then
        net.WriteVector(value or Vector(0, 0, 0))
    elseif valueType == 'string' then
        net.WriteBool(value ~= nil)
        if value ~= nil then net.WriteString(tostring(value)) end
    end
end

local function writeItem(schema, item)
    for _, field in ipairs(schema) do
        writeValue(field[2], item[field[1]])
    end
end

local function copyMonitorPos(data)
    if not LUASQUARE_POWERPLANT.ResolveMonitorPos then return nil end
    return LUASQUARE_POWERPLANT.ResolveMonitorPos(data)
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
                regulate = pump.regulate and true or false,
                regulationMode = pump.regulationMode,
                regulationTarget = pump.regulationTarget or 0,
                regulationLevel = pump.regulationLevel or 0,
                regulationFactor = pump.regulationFactor or 0,
                grid = pump.grid,
                breaker = pump.breaker,
                peakMW = pump.peakMW or 0,
                lastPowerMW = pump.lastPowerMW or 0,
                lastPowerAcceptedMW = pump.lastPowerAcceptedMW or 0,
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

function LUASQUARE_POWERPLANT.Debug.BuildTurbines()
    LUASQUARE_POWERPLANT.Debug.ClientState.Turbines = {}
    if not LUASQUARE_TURBINE then return end
    for name, turbine in pairs(LUASQUARE_TURBINE.Turbines) do
        local pos = copyMonitorPos(turbine)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.Turbines, {
                name = name,
                input = turbine.input,
                boiler = turbine.boiler,
                output = turbine.output,
                condenserOutput = turbine.condenserOutput,
                bypassCondenserOutput = turbine.bypassCondenserOutput,
                enabled = turbine.enabled and true or false,
                tripped = turbine.tripped and true or false,
                tripLevel = turbine.tripLevel,
                tripRelayFired = turbine.tripRelayFired and true or false,
                severeTripFired = turbine.severeTripFired and true or false,
                severeTripStopFired = turbine.severeTripStopFired and true or false,
                severeTripRPM = turbine.severeTripRPM or 0,
                severeTripBrakeRPM = turbine.severeTripBrakeRPM or 0,
                extremeTripFired = turbine.extremeTripFired and true or false,
                extremeTripRPM = turbine.extremeTripRPM or 0,
                catastrophicFailed = turbine.catastrophicFailed and true or false,
                synced = turbine.synced and true or false,
                autoSync = turbine.autoSync and true or false,
                valve = turbine.valve or 0,
                bypassValve = turbine.bypassValve or 0,
                maxSteamRate = turbine.maxSteamRate or 0,
                ratedSteamRate = turbine.ratedSteamRate or turbine.maxSteamRate or 0,
                rpm = turbine.rpm or 0,
                phase = turbine.phase or 0,
                vibration = turbine.vibration or 0,
                cycleEfficiency = turbine.cycleEfficiency or turbine.efficiency or 0,
                lastBoilerMW = turbine.lastBoilerMW or 0,
                lastSteamShare = turbine.lastSteamShare or 0,
                lastTurbineSteamFraction = turbine.lastTurbineSteamFraction or 0,
                lastInletSteam = turbine.lastInletSteam or 0,
                lastInletPressureScale = turbine.lastInletPressureScale or 0,
                lastSteamUsed = turbine.lastSteamUsed or 0,
                lastBypassSteam = turbine.lastBypassSteam or 0,
                lastExhaustMade = turbine.lastExhaustMade or 0,
                lastCondensateMade = turbine.lastCondensateMade or 0,
                lastBypassCondensateMade = turbine.lastBypassCondensateMade or 0,
                lastCondensateTemperature = turbine.lastCondensateTemperature or 0,
                lastBypassCondensateTemperature = turbine.lastBypassCondensateTemperature or 0,
                lastMW = turbine.lastMW or 0,
                tripReason = turbine.tripReason,
                pos = pos
            })
        end
    end
end

function LUASQUARE_POWERPLANT.Debug.BuildCoolingTowers()
    LUASQUARE_POWERPLANT.Debug.ClientState.CoolingTowers = {}
    if not LUASQUARE_COOLINGTOWER then return end
    for name, tower in pairs(LUASQUARE_COOLINGTOWER.CoolingTowers) do
        local pos = copyMonitorPos(tower)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.CoolingTowers, {
                name = name,
                input = tower.input,
                basin = tower.basin,
                output = tower.output,
                maxRate = tower.maxRate or 0,
                enabled = tower.enabled and true or false,
                working = tower.working and true or false,
                outputTemperature = tower.outputTemperature or 0,
                basinAmount = tower.basinAmount or 0,
                basinMaxAmount = tower.basinMaxAmount or 0,
                basinTemperature = tower.basinTemperature or 0,
                basinPressure = tower.basinPressure or 0,
                basinMaxPressure = tower.basinMaxPressure or 0,
                lastWaterReceived = tower.lastWaterReceived or 0,
                lastWaterCooled = tower.lastWaterCooled or 0,
                lastHeatRemoved = tower.lastHeatRemoved or 0,
                pos = pos
            })
        end
    end
end

function LUASQUARE_POWERPLANT.Debug.BuildGrids()
    LUASQUARE_POWERPLANT.Debug.ClientState.Grids = {}
    if not LUASQUARE_POWERGRID then return end
    for name, grid in pairs(LUASQUARE_POWERGRID.Grids) do
        local pos = copyMonitorPos(grid)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.Grids, {
                name = name,
                type = grid.type,
                enabled = grid.enabled and true or false,
                tripped = grid.tripped and true or false,
                energized = grid.energized and true or false,
                stiff = grid.stiff and true or false,
                frequency = grid.frequency or 0,
                nominalFrequency = grid.nominalFrequency or 0,
                voltage = grid.voltage or 0,
                phase = grid.phase or 0,
                sourceCapacityMW = grid.sourceCapacityMW or 0,
                availableImportMW = grid.availableImportMW or 0,
                lastGenerationMW = grid.lastGenerationMW or 0,
                lastLoadMW = grid.lastLoadMW or 0,
                lastImportMW = grid.lastImportMW or 0,
                lastAvailableMW = grid.lastAvailableMW or 0,
                lastBalanceMW = grid.lastBalanceMW or 0,
                tripReason = grid.tripReason,
                pos = pos
            })
        end
    end
end

function LUASQUARE_POWERPLANT.Debug.BuildBreakers()
    LUASQUARE_POWERPLANT.Debug.ClientState.Breakers = {}
    if not LUASQUARE_POWERGRID then return end
    for name, breaker in pairs(LUASQUARE_POWERGRID.Breakers) do
        local pos = copyMonitorPos(breaker)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.Breakers, {
                name = name,
                grid = breaker.grid,
                owner = breaker.owner,
                kind = breaker.kind,
                closed = breaker.closed and true or false,
                tripped = breaker.tripped and true or false,
                maxMW = breaker.maxMW or 0,
                lastMW = breaker.lastMW or 0,
                tripReason = breaker.tripReason,
                pos = pos
            })
        end
    end
end

function LUASQUARE_POWERPLANT.Debug.BuildTransformers()
    LUASQUARE_POWERPLANT.Debug.ClientState.Transformers = {}
    if not LUASQUARE_POWERGRID then return end
    for name, transformer in pairs(LUASQUARE_POWERGRID.Transformers) do
        local pos = copyMonitorPos(transformer)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.Transformers, {
                name = name,
                from = transformer.from,
                to = transformer.to,
                enabled = transformer.enabled and true or false,
                closed = transformer.closed and true or false,
                bidirectional = transformer.bidirectional and true or false,
                tripped = transformer.tripped and true or false,
                available = transformer.available and true or false,
                maxMW = transformer.maxMW or 0,
                lastMW = transformer.lastMW or 0,
                pos = pos
            })
        end
    end
end

function LUASQUARE_POWERPLANT.Debug.BuildGenerators()
    LUASQUARE_POWERPLANT.Debug.ClientState.Generators = {}
    if not LUASQUARE_POWERGENERATOR then return end
    for name, generator in pairs(LUASQUARE_POWERGENERATOR.Generators) do
        local pos = copyMonitorPos(generator)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.Generators, {
                name = name,
                type = generator.type,
                grid = generator.grid,
                breaker = generator.breaker,
                enabled = generator.enabled and true or false,
                tripped = generator.tripped and true or false,
                synced = generator.synced and true or false,
                turbine = generator.turbine,
                ratedMW = generator.ratedMW or 0,
                maxMW = generator.maxMW or 0,
                outputMW = generator.outputMW or 0,
                targetMW = generator.targetMW or 0,
                lastMW = generator.lastMW or 0,
                lastAcceptedMW = generator.lastAcceptedMW or 0,
                lastRPMError = generator.lastRPMError or 0,
                lastPhaseError = generator.lastPhaseError or 0,
                lastSyncBlockReason = generator.lastSyncBlockReason,
                tripReason = generator.tripReason,
                pos = pos
            })
        end
    end
end

function LUASQUARE_POWERPLANT.Debug.BuildDieselGenerators()
    LUASQUARE_POWERPLANT.Debug.ClientState.DieselGenerators = {}
    if not LUASQUARE_DIESELGENERATOR then return end
    for name, diesel in pairs(LUASQUARE_DIESELGENERATOR.Generators) do
        local pos = copyMonitorPos(diesel)
        if pos then
            table.insert(LUASQUARE_POWERPLANT.Debug.ClientState.DieselGenerators, {
                name = name,
                generator = diesel.generator,
                fuelNetwork = diesel.fuelNetwork,
                enabled = diesel.enabled and true or false,
                targetMW = diesel.targetMW or 0,
                lastTargetMW = diesel.lastTargetMW or 0,
                lastAvailableMW = diesel.lastAvailableMW or 0,
                fuelTankAmount = diesel.fuelTankAmount or 0,
                fuelTankCapacity = diesel.fuelTankCapacity or 0,
                lastFuelDraw = diesel.lastFuelDraw or 0,
                lastFuelUsed = diesel.lastFuelUsed or 0,
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
    LUASQUARE_POWERPLANT.Debug.BuildTurbines()
    LUASQUARE_POWERPLANT.Debug.BuildCoolingTowers()
    LUASQUARE_POWERPLANT.Debug.BuildGrids()
    LUASQUARE_POWERPLANT.Debug.BuildBreakers()
    LUASQUARE_POWERPLANT.Debug.BuildTransformers()
    LUASQUARE_POWERPLANT.Debug.BuildGenerators()
    LUASQUARE_POWERPLANT.Debug.BuildDieselGenerators()
    LUASQUARE_POWERPLANT.Debug.Broadcast()
end

function LUASQUARE_POWERPLANT.Debug.Broadcast()
    LUASQUARE_POWERPLANT.Debug.NetSequence = ((LUASQUARE_POWERPLANT.Debug.NetSequence or 0) % 65535) + 1
    local sequence = LUASQUARE_POWERPLANT.Debug.NetSequence
    local state = LUASQUARE_POWERPLANT.Debug.ClientState or {}

    startDebugPacket(DEBUG_PACKET_START, sequence)
    net.Broadcast()

    for categoryIndex, category in ipairs(DEBUG_CATEGORIES) do
        LUASQUARE_POWERPLANT.Debug.BroadcastCategoryChunks(sequence, categoryIndex, category, state[category.name] or {})
    end

    startDebugPacket(DEBUG_PACKET_END, sequence)
    net.Broadcast()
end

function LUASQUARE_POWERPLANT.Debug.BroadcastCategoryChunks(sequence, categoryIndex, category, items)
    for startIndex = 1, #items, category.chunkSize do
        local endIndex = math.min(startIndex + category.chunkSize - 1, #items)
        startDebugPacket(DEBUG_PACKET_CATEGORY, sequence)
        net.WriteUInt(categoryIndex, 4)
        net.WriteUInt(endIndex - startIndex + 1, 16)
        for i = startIndex, endIndex do
            writeItem(category.schema, items[i])
        end
        net.Broadcast()
    end
end

function LUASQUARE_POWERPLANT.Debug.Start()
    if timer.Exists('LUASQUARE_POWERPLANT_DebugTimer') then timer.Remove('LUASQUARE_POWERPLANT_DebugTimer') end
    timer.Create('LUASQUARE_POWERPLANT_DebugTimer', 0.25, 0, function() LUASQUARE_POWERPLANT.Debug.Tick() end)
    print('[LUASQUARE_POWERPLANT_DEBUG] Started')
end
