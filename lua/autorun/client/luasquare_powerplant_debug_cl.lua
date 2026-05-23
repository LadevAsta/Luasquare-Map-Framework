if not CLIENT then return end
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
    Generators = {}
}

timer.Simple(10, function()
    if not GetGlobal2Bool('LUASQUARE_RBMK_INITIALIZED_GLOBAL', false) then
        print('[Luasquare Powerplant Debug Client] No powerplant detected after 10 seconds, terminating')
        return
    end

    net.Receive('LUASQUARE_PowerplantDebugState', function()
        LUASQUARE_POWERPLANT.Debug.ClientState = net.ReadTable() or {
            Networks = {},
            Pumps = {},
            Valves = {},
            Condensers = {},
            Turbines = {},
            CoolingTowers = {},
            Grids = {},
            Breakers = {},
            Transformers = {},
            Generators = {}
        }
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
        string.format('W %.3f/s', condenser.lastWaterMade or 0)
    }
    if condenser.godMode then table.insert(lines, 'GOD') end
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(condenser.pos, table.concat(lines, '\n'), Color(100, 255, 100))
end

function LUASQUARE_POWERPLANT.Debug.RenderTurbine(turbine)
    local outputName = turbine.condenserOutput or turbine.output
    local lines = {
        'TURB ' .. tostring(turbine.name),
        tostring(turbine.input) .. ' > ' .. tostring(outputName),
        'EN ' .. tostring(turbine.enabled) .. ' SYNC ' .. tostring(turbine.synced),
        string.format('VLV %.1f%% BYP %.1f%%', (turbine.valve or 0) * 100, (turbine.bypassValve or 0) * 100),
        string.format('RPM %.0f PH %.1f', turbine.rpm or 0, turbine.phase or 0),
        string.format('RATED %.0f/s MAX %.0f/s', turbine.ratedSteamRate or 0, turbine.maxSteamRate or 0),
        string.format('S %.1f/s B %.1f/s', turbine.lastSteamUsed or 0, turbine.lastBypassSteam or 0),
        string.format('HW %.3f/s BHW %.3f/s', turbine.lastCondensateMade or 0, turbine.lastBypassCondensateMade or 0),
        string.format('MW %.1f VIB %.1f', turbine.lastMW or 0, turbine.vibration or 0)
    }
    if turbine.tripped then table.insert(lines, 'TRIP ' .. tostring(turbine.tripReason or '')) end
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
        string.format('IMP %.1f AV %.1f MW', grid.lastImportMW or 0, grid.lastAvailableMW or 0),
        string.format('BAL %.1f MW', grid.lastBalanceMW or 0)
    }
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
    if generator.lastSyncBlockReason then table.insert(lines, 'SYNC ' .. tostring(generator.lastSyncBlockReason)) end
    if generator.tripped then table.insert(lines, 'TRIP ' .. tostring(generator.tripReason or '')) end
    LUASQUARE_POWERPLANT.Debug.DrawWorldText(generator.pos, table.concat(lines, '\n'), Color(220, 220, 255))
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
    end
end
