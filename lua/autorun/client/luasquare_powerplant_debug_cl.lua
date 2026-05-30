if not CLIENT then return end
LUASQUARE_POWERPLANT = LUASQUARE_POWERPLANT or {}
LUASQUARE_POWERPLANT.Debug = LUASQUARE_POWERPLANT.Debug or {}
LUASQUARE_POWERPLANT.Debug.ClientState = {
    Networks = {},
    Pumps = {},
    Valves = {},
    Condensers = {},
    HeatExchangers = {},
    Deaerators = {},
    Turbines = {},
    CoolingTowers = {},
    Grids = {},
    Breakers = {},
    Transformers = {},
    Generators = {},
    DieselGenerators = {}
}

local DEBUG_WIRE_VERSION = 3
local DEBUG_PACKET_START = 1
local DEBUG_PACKET_CATEGORY = 2
local DEBUG_PACKET_END = 3

local DEBUG_CATEGORIES = {
    {name = 'Networks', schema = {
        {'name', 'string'}, {'type', 'string'}, {'fluidType', 'string'},
        {'amount', 'number'}, {'maxAmount', 'number'}, {'hardMaxAmount', 'number'},
        {'volume', 'number'}, {'pressure', 'number'}, {'maxPressure', 'number'}, {'temperature', 'number'},
        {'ruptured', 'bool'}, {'serviceEnabled', 'bool'}, {'pos', 'vector'}
    }},
    {name = 'Pumps', schema = {
        {'name', 'string'}, {'source', 'string'}, {'target', 'string'},
        {'rate', 'number'}, {'headPressure', 'number'}, {'enabled', 'bool'},
        {'speedLevel', 'number'}, {'speedMultiplier', 'number'}, {'regulate', 'bool'},
        {'regulationMode', 'string'}, {'regulationTarget', 'number'}, {'regulationLevel', 'number'},
        {'regulationFactor', 'number'}, {'grid', 'string'}, {'breaker', 'string'},
        {'peakMW', 'number'}, {'lastPowerMW', 'number'}, {'lastPowerAcceptedMW', 'number'},
        {'lastFlow', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Valves', schema = {
        {'name', 'string'}, {'a', 'string'}, {'b', 'string'},
        {'open', 'bool'}, {'bidirectional', 'bool'}, {'maxFlow', 'number'}, {'lastFlow', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Condensers', schema = {
        {'name', 'string'}, {'input', 'string'}, {'output', 'string'}, {'ratio', 'number'},
        {'coolantNetwork', 'string'}, {'coolantPump', 'string'}, {'enabled', 'bool'}, {'godMode', 'bool'},
        {'lastSteamUsed', 'number'}, {'lastWaterMade', 'number'}, {'lastHeatRejectedMW', 'number'},
        {'lastCoolantFlow', 'number'}, {'lastCoolantTemperature', 'number'}, {'pos', 'vector'}
    }},
    {name = 'HeatExchangers', schema = {
        {'name', 'string'}, {'hotNetwork', 'string'}, {'coldNetwork', 'string'},
        {'hotPump', 'string'}, {'coldPump', 'string'}, {'enabled', 'bool'},
        {'effectiveness', 'number'}, {'approachTemperature', 'number'}, {'maxThermalMW', 'number'},
        {'lastHeatMW', 'number'}, {'lastHotFlow', 'number'}, {'lastColdFlow', 'number'},
        {'lastHotTemperature', 'number'}, {'lastColdTemperature', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Deaerators', schema = {
        {'name', 'string'}, {'tankNetwork', 'string'}, {'steamInput', 'string'},
        {'enabled', 'bool'}, {'targetTemperature', 'number'}, {'maxSteamRate', 'number'},
        {'lastSteamUsed', 'number'}, {'lastWaterMade', 'number'}, {'lastHeatMW', 'number'},
        {'tankTemperature', 'number'}, {'tankAmount', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Turbines', schema = {
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
    {name = 'CoolingTowers', schema = {
        {'name', 'string'}, {'input', 'string'}, {'basin', 'string'}, {'output', 'string'},
        {'maxRate', 'number'}, {'enabled', 'bool'}, {'working', 'bool'}, {'outputTemperature', 'number'},
        {'basinAmount', 'number'}, {'basinMaxAmount', 'number'}, {'basinTemperature', 'number'},
        {'basinPressure', 'number'}, {'basinMaxPressure', 'number'}, {'lastWaterReceived', 'number'},
        {'lastWaterCooled', 'number'}, {'lastHeatRemoved', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Grids', schema = {
        {'name', 'string'}, {'type', 'string'}, {'enabled', 'bool'}, {'tripped', 'bool'},
        {'energized', 'bool'}, {'stiff', 'bool'}, {'frequency', 'number'}, {'nominalFrequency', 'number'},
        {'voltage', 'number'}, {'phase', 'number'}, {'sourceCapacityMW', 'number'},
        {'demandMW', 'number'}, {'currentDemandMW', 'number'}, {'batteryMWh', 'number'},
        {'batteryCapacityMWh', 'number'}, {'batteryChargeFraction', 'number'}, {'batteryLastMW', 'number'},
        {'availableImportMW', 'number'}, {'lastGenerationMW', 'number'}, {'lastLoadMW', 'number'},
        {'lastImportMW', 'number'}, {'lastAvailableMW', 'number'}, {'lastBalanceMW', 'number'},
        {'tripReason', 'string'}, {'pos', 'vector'}
    }},
    {name = 'Breakers', schema = {
        {'name', 'string'}, {'grid', 'string'}, {'owner', 'string'}, {'kind', 'string'},
        {'closed', 'bool'}, {'tripped', 'bool'}, {'maxMW', 'number'}, {'lastMW', 'number'},
        {'tripReason', 'string'}, {'pos', 'vector'}
    }},
    {name = 'Transformers', schema = {
        {'name', 'string'}, {'from', 'string'}, {'to', 'string'}, {'enabled', 'bool'}, {'closed', 'bool'},
        {'bidirectional', 'bool'}, {'tripped', 'bool'}, {'available', 'bool'}, {'maxMW', 'number'},
        {'lastMW', 'number'}, {'pos', 'vector'}
    }},
    {name = 'Generators', schema = {
        {'name', 'string'}, {'type', 'string'}, {'grid', 'string'}, {'breaker', 'string'},
        {'enabled', 'bool'}, {'tripped', 'bool'}, {'synced', 'bool'}, {'turbine', 'string'},
        {'ratedMW', 'number'}, {'maxMW', 'number'}, {'outputMW', 'number'}, {'targetMW', 'number'},
        {'motoringMW', 'number'}, {'reversePowerTripMW', 'number'}, {'reversePowerTripDelay', 'number'},
        {'reversePowerTimer', 'number'}, {'lastReverseMW', 'number'}, {'lastMW', 'number'},
        {'lastAcceptedMW', 'number'}, {'lastRPMError', 'number'},
        {'lastPhaseError', 'number'}, {'lastSyncBlockReason', 'string'}, {'tripReason', 'string'}, {'pos', 'vector'}
    }},
    {name = 'DieselGenerators', schema = {
        {'name', 'string'}, {'generator', 'string'}, {'fuelNetwork', 'string'}, {'enabled', 'bool'},
        {'targetMW', 'number'}, {'lastTargetMW', 'number'}, {'lastAvailableMW', 'number'},
        {'fuelTankAmount', 'number'}, {'fuelTankCapacity', 'number'}, {'lastFuelDraw', 'number'},
        {'lastFuelUsed', 'number'}, {'pos', 'vector'}
    }}
}

local function emptyClientState()
    local state = {}
    for _, category in ipairs(DEBUG_CATEGORIES) do
        state[category.name] = {}
    end
    return state
end

local function readValue(valueType)
    if valueType == 'number' then return net.ReadFloat() end
    if valueType == 'bool' then return net.ReadBool() end
    if valueType == 'vector' then return net.ReadVector() end
    if valueType == 'string' then
        if not net.ReadBool() then return nil end
        return net.ReadString()
    end
    return nil
end

local function readItem(schema)
    local item = {}
    for _, field in ipairs(schema) do
        item[field[1]] = readValue(field[2])
    end
    return item
end

function LUASQUARE_POWERPLANT.Debug.ReceiveStatePacket()
    local version = net.ReadUInt(8)
    if version ~= DEBUG_WIRE_VERSION then return end

    local packetType = net.ReadUInt(4)
    local sequence = net.ReadUInt(16)

    if packetType == DEBUG_PACKET_START then
        LUASQUARE_POWERPLANT.Debug.PendingState = emptyClientState()
        LUASQUARE_POWERPLANT.Debug.PendingState.Sequence = sequence
        return
    end

    local pending = LUASQUARE_POWERPLANT.Debug.PendingState
    if not pending or pending.Sequence ~= sequence then return end

    if packetType == DEBUG_PACKET_CATEGORY then
        local category = DEBUG_CATEGORIES[net.ReadUInt(4)]
        local count = net.ReadUInt(16)
        if not category then return end
        for _ = 1, count do
            table.insert(pending[category.name], readItem(category.schema))
        end
    elseif packetType == DEBUG_PACKET_END then
        LUASQUARE_POWERPLANT.Debug.ClientState = pending
        LUASQUARE_POWERPLANT.Debug.PendingState = nil
    end
end

timer.Simple(10, function()
    if not GetGlobal2Bool('LUASQUARE_FRAMEWORK_INITIALIZED_GLOBAL', false) then
        print('[Luasquare Powerplant Debug Client] No powerplant detected after 10 seconds, terminating')
        return
    end

    net.Receive('LUASQUARE_PowerplantDebugState', function()
        LUASQUARE_POWERPLANT.Debug.ReceiveStatePacket()
    end)

    hook.Add('PostDrawTranslucentRenderables', 'LuasquarePowerplant_DebugRender', function()
        LUASQUARE_POWERPLANT.Debug.Render()
    end)
    print('[Luasquare Powerplant Debug Client] Client initialized')
end)

function LUASQUARE_POWERPLANT.Debug.GetSetting(name, default)
    local cvar = GetConVar('luasquare_powerplant_' .. name)
    if not cvar then return default end
    return cvar:GetBool()
end

function LUASQUARE_POWERPLANT.Debug.GetSettingNumber(name, default)
    local cvar = GetConVar('luasquare_powerplant_' .. name)
    if not cvar then return default end
    return cvar:GetFloat()
end

function LUASQUARE_POWERPLANT.Debug.DrawWorldText(pos, text, color)
    cam.Start3D2D(pos, Angle(0, LocalPlayer():EyeAngles().y - 90, 90), LUASQUARE_POWERPLANT.Debug.GetSettingNumber('debug_textscale', 0.2))
    local y = 0
    for line in string.gmatch(text, '[^\n]+') do
        draw.SimpleTextOutlined(line, 'DermaDefault', 0, y, color or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
        y = y + 14
    end
    cam.End3D2D()
end

function LUASQUARE_POWERPLANT.Debug.RenderNetwork(network)
    local lines = {
        'NET ' .. tostring(network.name),
        tostring(network.fluidType) .. ' ' .. tostring(network.type),
        string.format('A %.1f / %.1f', network.amount or 0, network.maxAmount or 0),
        string.format('V %.1f', network.volume or 0),
        string.format('P %.1f / %.1f bar', network.pressure or 0, network.maxPressure or 0),
        string.format('T %.1f C', network.temperature or 0)
    }
    if network.ruptured then table.insert(lines, 'RUPTURED') end
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(network.pos, table.concat(lines, '\n'), Color(0, 220, 255))
end

function LUASQUARE_POWERPLANT.Debug.RenderPump(pump)
    local lines = {
        'PUMP ' .. tostring(pump.name),
        tostring(pump.source) .. ' > ' .. tostring(pump.target),
        'EN ' .. tostring(pump.enabled),
        string.format('SPD %d %.2fx', pump.speedLevel or 0, pump.speedMultiplier or 0),
        string.format('FLOW %.2f/s', pump.lastFlow or 0),
        string.format('HEAD %.1f bar', pump.headPressure or 0)
    }
    if pump.regulate then table.insert(lines, string.format('REG %s %.1f/%.1f %.2fx', tostring(pump.regulationMode or ''), pump.regulationLevel or 0, pump.regulationTarget or 0, pump.regulationFactor or 0)) end
    if (pump.peakMW or 0) > 0 then table.insert(lines, string.format('PWR %.2f/%.2f MW %s', pump.lastPowerAcceptedMW or 0, pump.lastPowerMW or 0, tostring(pump.breaker or ''))) end
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(pump.pos, table.concat(lines, '\n'), Color(255, 220, 0))
end

function LUASQUARE_POWERPLANT.Debug.RenderValve(valve)
    local lines = {
        'VALVE ' .. tostring(valve.name),
        tostring(valve.a) .. ' <-> ' .. tostring(valve.b),
        'OPEN ' .. tostring(valve.open),
        'BI ' .. tostring(valve.bidirectional),
        string.format('FLOW %.2f/s', valve.lastFlow or 0)
    }
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(valve.pos, table.concat(lines, '\n'), Color(255, 160, 60))
end

function LUASQUARE_POWERPLANT.Debug.RenderCondenser(condenser)
    local lines = {
        'COND ' .. tostring(condenser.name),
        tostring(condenser.input) .. ' > ' .. tostring(condenser.output),
        'EN ' .. tostring(condenser.enabled),
        string.format('S %.1f/s', condenser.lastSteamUsed or 0),
        string.format('W %.3f/s', condenser.lastWaterMade or 0),
        string.format('HEAT %.1f MW', condenser.lastHeatRejectedMW or 0)
    }
    if condenser.coolantNetwork then
        table.insert(lines, tostring(condenser.coolantPump or 'coolant') .. ' > ' .. tostring(condenser.coolantNetwork))
        table.insert(lines, string.format('CW %.1f/s %.1f C', condenser.lastCoolantFlow or 0, condenser.lastCoolantTemperature or 0))
    end
    if condenser.godMode then table.insert(lines, 'GOD') end
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(condenser.pos, table.concat(lines, '\n'), Color(100, 255, 100))
end

function LUASQUARE_POWERPLANT.Debug.RenderHeatExchanger(exchanger)
    local lines = {
        'HX ' .. tostring(exchanger.name),
        tostring(exchanger.hotNetwork) .. ' > ' .. tostring(exchanger.coldNetwork),
        'EN ' .. tostring(exchanger.enabled),
        string.format('HEAT %.1f MW', exchanger.lastHeatMW or 0),
        string.format('HOT %.1f/s %.1f C', exchanger.lastHotFlow or 0, exchanger.lastHotTemperature or 0),
        string.format('COLD %.1f/s %.1f C', exchanger.lastColdFlow or 0, exchanger.lastColdTemperature or 0)
    }
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(exchanger.pos, table.concat(lines, '\n'), Color(120, 255, 180))
end

function LUASQUARE_POWERPLANT.Debug.RenderDeaerator(deaerator)
    local lines = {
        'DEAER ' .. tostring(deaerator.name),
        tostring(deaerator.steamInput) .. ' > ' .. tostring(deaerator.tankNetwork),
        'EN ' .. tostring(deaerator.enabled),
        string.format('TANK %.1f C / %.1f C', deaerator.tankTemperature or 0, deaerator.targetTemperature or 0),
        string.format('AMT %.1f', deaerator.tankAmount or 0),
        string.format('BLEED %.1f/s MAKE %.3f/s', deaerator.lastSteamUsed or 0, deaerator.lastWaterMade or 0),
        string.format('HEAT %.1f MW', deaerator.lastHeatMW or 0)
    }
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(deaerator.pos, table.concat(lines, '\n'), Color(180, 255, 210))
end

function LUASQUARE_POWERPLANT.Debug.RenderTurbine(turbine)
    local outputName = turbine.condenserOutput or turbine.output
    local lines = {
        'TURB ' .. tostring(turbine.name),
        tostring(turbine.input) .. ' > ' .. tostring(outputName),
        'BOILER ' .. tostring(turbine.boiler or 'none'),
        'EN ' .. tostring(turbine.enabled) .. ' SYNC ' .. tostring(turbine.synced) .. ' FAIL ' .. tostring(turbine.catastrophicFailed),
        string.format('VLV %.1f%% BYP %.1f%%', (turbine.valve or 0) * 100, (turbine.bypassValve or 0) * 100),
        string.format('RPM %.0f PH %.1f', turbine.rpm or 0, turbine.phase or 0),
        string.format('RATED %.0f/s MAX %.0f/s', turbine.ratedSteamRate or 0, turbine.maxSteamRate or 0),
        string.format('IN %.1f/s %.2fx', turbine.lastInletSteam or 0, turbine.lastInletPressureScale or 0),
        string.format('S %.1f/s B %.1f/s', turbine.lastSteamUsed or 0, turbine.lastBypassSteam or 0),
        string.format('HW %.3f/s %.1fC BHW %.3f/s %.1fC', turbine.lastCondensateMade or 0, turbine.lastCondensateTemperature or 0, turbine.lastBypassCondensateMade or 0, turbine.lastBypassCondensateTemperature or 0),
        string.format('MWth %.1f SHARE %.0f%% FLOW %.0f%% EFF %.0f%%', turbine.lastBoilerMW or 0, (turbine.lastSteamShare or 0) * 100, (turbine.lastTurbineSteamFraction or 0) * 100, (turbine.cycleEfficiency or 0) * 100),
        string.format('MW %.1f VIB %.1f', turbine.lastMW or 0, turbine.vibration or 0)
    }
    if turbine.tripped then table.insert(lines, 'TRIP ' .. tostring(turbine.tripLevel or 'normal') .. ' ' .. tostring(turbine.tripReason or '')) end
    if turbine.severeTripFired and not turbine.severeTripStopFired then table.insert(lines, string.format('SEVERE BRAKING > %.0f RPM', turbine.severeTripBrakeRPM or 0)) end
    if turbine.extremeTripFired then table.insert(lines, string.format('EXTREME TRIP > %.0f RPM', turbine.extremeTripRPM or 0)) end
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(turbine.pos, table.concat(lines, '\n'), Color(180, 220, 255))
end

function LUASQUARE_POWERPLANT.Debug.RenderCoolingTower(tower)
    local lines = {
        'COOL ' .. tostring(tower.name),
        'BASIN > ' .. tostring(tower.output),
        'EN ' .. tostring(tower.enabled),
        'WK ' .. tostring(tower.working),
        string.format('IN %.2f/s OUT %.2f/s', tower.lastWaterReceived or 0, tower.lastWaterCooled or 0),
        string.format('B %.1f / %.1f', tower.basinAmount or 0, tower.basinMaxAmount or 0),
        string.format('BP %.1f / %.1f bar', tower.basinPressure or 0, tower.basinMaxPressure or 0),
        string.format('BT %.1f C', tower.basinTemperature or 0),
        string.format('OUT %.1f C', tower.outputTemperature or 0),
        string.format('HEAT %.1f C-l/s', tower.lastHeatRemoved or 0)
    }
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(tower.pos, table.concat(lines, '\n'), Color(120, 220, 255))
end

function LUASQUARE_POWERPLANT.Debug.RenderGrid(grid)
    local lines = {
        'GRID ' .. tostring(grid.name),
        tostring(grid.type) .. ' EN ' .. tostring(grid.energized),
        string.format('F %.2f / %.2f Hz', grid.frequency or 0, grid.nominalFrequency or 0),
        string.format('V %.0f PH %.1f', grid.voltage or 0, grid.phase or 0),
        string.format('GEN %.1f LOAD %.1f MW', grid.lastGenerationMW or 0, grid.lastLoadMW or 0),
        string.format('DEMAND %.1f / %.1f MW', grid.currentDemandMW or 0, grid.demandMW or 0),
        string.format('IMP %.1f AV %.1f MW', grid.lastImportMW or 0, grid.lastAvailableMW or 0),
        string.format('BAL %.1f MW', grid.lastBalanceMW or 0)
    }
    if (grid.batteryCapacityMWh or 0) > 0 then
        table.insert(lines, string.format('BATT %.1f/%.1f MWh %.1f MW', grid.batteryMWh or 0, grid.batteryCapacityMWh or 0, grid.batteryLastMW or 0))
    end
    if grid.tripped then table.insert(lines, 'TRIP ' .. tostring(grid.tripReason or '')) end
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(grid.pos, table.concat(lines, '\n'), Color(180, 255, 180))
end

function LUASQUARE_POWERPLANT.Debug.RenderBreaker(breaker)
    local lines = {
        'BRKR ' .. tostring(breaker.name),
        tostring(breaker.kind) .. ' ' .. tostring(breaker.owner or ''),
        'GRID ' .. tostring(breaker.grid),
        'CLOSED ' .. tostring(breaker.closed),
        string.format('MW %.1f / %.1f', breaker.lastMW or 0, breaker.maxMW or 0)
    }
    if breaker.tripped then table.insert(lines, 'TRIP ' .. tostring(breaker.tripReason or '')) end
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(breaker.pos, table.concat(lines, '\n'), Color(255, 255, 160))
end

function LUASQUARE_POWERPLANT.Debug.RenderTransformer(transformer)
    local lines = {
        'XFMR ' .. tostring(transformer.name),
        tostring(transformer.from) .. ' > ' .. tostring(transformer.to),
        'EN ' .. tostring(transformer.enabled) .. ' CLOSED ' .. tostring(transformer.closed),
        'AVAIL ' .. tostring(transformer.available) .. ' BI ' .. tostring(transformer.bidirectional),
        string.format('MW %.1f / %.1f', transformer.lastMW or 0, transformer.maxMW or 0)
    }
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(transformer.pos, table.concat(lines, '\n'), Color(210, 255, 180))
end

function LUASQUARE_POWERPLANT.Debug.RenderGenerator(generator)
    local lines = {
        'GEN ' .. tostring(generator.name),
        tostring(generator.type) .. ' > ' .. tostring(generator.grid),
        'EN ' .. tostring(generator.enabled) .. ' SYNC ' .. tostring(generator.synced),
        'BRKR ' .. tostring(generator.breaker),
        string.format('MW %.1f / %.1f', generator.lastAcceptedMW or 0, generator.maxMW or 0),
        string.format('ERR %.1f RPM %.1f DEG', generator.lastRPMError or 0, generator.lastPhaseError or 0)
    }
    if (generator.motoringMW or 0) > 0 then
        table.insert(lines, string.format('REV %.1f / %.1f MW %.1fs', generator.lastReverseMW or 0, generator.reversePowerTripMW or 0, generator.reversePowerTimer or 0))
    end
    if generator.lastSyncBlockReason then table.insert(lines, 'SYNC ' .. tostring(generator.lastSyncBlockReason)) end
    if generator.tripped then table.insert(lines, 'TRIP ' .. tostring(generator.tripReason or '')) end
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(generator.pos, table.concat(lines, '\n'), Color(220, 220, 255))
end

function LUASQUARE_POWERPLANT.Debug.RenderDieselGenerator(diesel)
    local fuelPercent = 0
    if (diesel.fuelTankCapacity or 0) > 0 then fuelPercent = (diesel.fuelTankAmount or 0) / diesel.fuelTankCapacity * 100 end
    local lines = {
        'DIESEL ' .. tostring(diesel.name),
        'GEN ' .. tostring(diesel.generator),
        'EN ' .. tostring(diesel.enabled),
        string.format('MW %.1f / %.1f', diesel.lastAvailableMW or 0, diesel.lastTargetMW or diesel.targetMW or 0),
        string.format('FUEL %.1f / %.1f %.0f%%', diesel.fuelTankAmount or 0, diesel.fuelTankCapacity or 0, fuelPercent),
        string.format('DRAW %.2f/s USE %.2f/s', diesel.lastFuelDraw or 0, diesel.lastFuelUsed or 0)
    }
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(diesel.pos, table.concat(lines, '\n'), Color(255, 230, 160))
end

function LUASQUARE_POWERPLANT.Debug.Render()
    if not LUASQUARE_POWERPLANT.Debug.GetSetting('debug_enabled', false) then return end
    local state = LUASQUARE_POWERPLANT.Debug.ClientState
    if LUASQUARE_POWERPLANT.Debug.GetSetting('show_networks', true) then
        for _, network in ipairs(state.Networks or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderNetwork(network)
        end
    end
    if LUASQUARE_POWERPLANT.Debug.GetSetting('show_pumps', true) then
        for _, pump in ipairs(state.Pumps or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderPump(pump)
        end
    end
    if LUASQUARE_POWERPLANT.Debug.GetSetting('show_valves', true) then
        for _, valve in ipairs(state.Valves or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderValve(valve)
        end
    end
    if LUASQUARE_POWERPLANT.Debug.GetSetting('show_condensers', true) then
        for _, condenser in ipairs(state.Condensers or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderCondenser(condenser)
        end
        for _, exchanger in ipairs(state.HeatExchangers or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderHeatExchanger(exchanger)
        end
        for _, deaerator in ipairs(state.Deaerators or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderDeaerator(deaerator)
        end
    end
    if LUASQUARE_POWERPLANT.Debug.GetSetting('show_turbines', true) then
        for _, turbine in ipairs(state.Turbines or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderTurbine(turbine)
        end
    end
    if LUASQUARE_POWERPLANT.Debug.GetSetting('show_coolingtowers', true) then
        for _, tower in ipairs(state.CoolingTowers or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderCoolingTower(tower)
        end
    end
    if LUASQUARE_POWERPLANT.Debug.GetSetting('show_grids', true) then
        for _, grid in ipairs(state.Grids or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderGrid(grid)
        end
        for _, transformer in ipairs(state.Transformers or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderTransformer(transformer)
        end
    end
    if LUASQUARE_POWERPLANT.Debug.GetSetting('show_breakers', true) then
        for _, breaker in ipairs(state.Breakers or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderBreaker(breaker)
        end
    end
    if LUASQUARE_POWERPLANT.Debug.GetSetting('show_generators', true) then
        for _, generator in ipairs(state.Generators or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderGenerator(generator)
        end
        for _, diesel in ipairs(state.DieselGenerators or {}) do
            LUASQUARE_POWERPLANT.Debug.RenderDieselGenerator(diesel)
        end
    end
end
