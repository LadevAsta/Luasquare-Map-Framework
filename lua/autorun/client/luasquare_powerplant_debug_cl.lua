if not CLIENT then return end
LUASQUARE_POWERPLANT = LUASQUARE_POWERPLANT or {}
LUASQUARE_POWERPLANT.Debug = LUASQUARE_POWERPLANT.Debug or {}
LUASQUARE_POWERPLANT.Debug.ClientState = {
    Networks = {},
    Pumps = {},
    Valves = {},
    Condensers = {}
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
            Condensers = {}
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
end
