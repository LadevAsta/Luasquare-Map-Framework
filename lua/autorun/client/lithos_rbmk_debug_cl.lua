RBMK = RBMK or {}
RBMK.Debug = RBMK.Debug or {}
RBMK.Debug.ClientState = {
    Cells = {},
    FluxLines = {},
    VesselInfo = {}
}

RBMK.CELL_FUEL = RBMK.CELL_FUEL or 1
RBMK.CELL_STEAM = RBMK.CELL_STEAM or 2
RBMK.CELL_CONTROL = RBMK.CELL_CONTROL or 3
RBMK.CELL_REFLECTOR = RBMK.CELL_REFLECTOR or 4
RBMK.CELL_BLANK = RBMK.CELL_BLANK or 5
RBMK.CELL_AUTOROD = RBMK.CELL_AUTOROD or 6
RBMK.CELL_SOURCE = RBMK.CELL_SOURCE or 7
RBMK.CELL_ABSORBER = RBMK.CELL_ABSORBER or 8
RBMK.CELL_VOID = RBMK.CELL_VOID or 9

RBMK.CellSymbols = RBMK.CellSymbols or {
    [RBMK.CELL_BLANK] = 'B',
    [RBMK.CELL_FUEL] = 'F',
    [RBMK.CELL_STEAM] = 'S',
    [RBMK.CELL_CONTROL] = 'C',
    [RBMK.CELL_REFLECTOR] = 'RF',
    [RBMK.CELL_AUTOROD] = 'CA',
    [RBMK.CELL_SOURCE] = 'NS',
    [RBMK.CELL_ABSORBER] = 'AB',
    [RBMK.CELL_VOID] = 'X'
}

-- Client Debug module
timer.Simple(5, function()
    if not GetGlobal2Bool('LITHOSQUARE_RBMK_INITIALIZED_GLOBAL', false) then
        print('[Lithosquare RBMK Debug Module] No RBMK detected after 5 seconds, terminating')
        return
    end

    print('[Lithosquare RBMK Debug Module] Client initialized')

    net.Receive('RBMK_DebugState', function()
        RBMK = RBMK or {}
        RBMK.Debug = RBMK.Debug or {}
        RBMK.Debug.ClientState = net.ReadTable() or {
            Cells = {},
            FluxLines = {},
            VesselInfo = {}
        }
    end)

    hook.Add('PostDrawTranslucentRenderables', 'LithosRBMK_DebugRender', function()
        if not RBMK.Debug then return end
        if not RBMK.Debug.ClientState then return end
        RBMK.Debug.RenderCells()
        RBMK.Debug.RenderFluxLines()
        RBMK.Debug.RenderVesselInfo()
    end)
end)

function RBMK.Debug.GetSetting(name, default)
    local cvar = GetConVar('lithos_rbmk_' .. name)
    if not cvar then return default end
    return cvar:GetBool()
end

function RBMK.Debug.GetSettingNumber(name, default)
    local cvar = GetConVar('lithos_rbmk_' .. name)
    if not cvar then return default end
    return cvar:GetFloat()
end

function RBMK.Debug.GetCellWorldPos(x, y)
    if RBMK.CellToWorld then
        return RBMK.CellToWorld(x, y)
    end

    local info = RBMK.Debug.ClientState.VesselInfo or {}
    local origin = info.worldOrigin or Vector(0, 0, 0)
    local spacing = info.cellSpacing or 64
    return origin + Vector((x - 1) * spacing, (y - 1) * spacing, 0)
end

function RBMK.Debug.DrawWorldText(pos, text, color)
    cam.Start3D2D(pos, Angle(0, LocalPlayer():EyeAngles().y - 90, 90), RBMK.Debug.GetSettingNumber('debug_textscale', 1.0))
    draw.SimpleTextOutlined(text, 'DermaDefault', -10, 0, color or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1.2, color_black)
    cam.End3D2D()
end

function RBMK.Debug.RenderCell(x, y, cell)
    if cell.type == RBMK.CELL_VOID or
    (not RBMK.Debug.GetSetting('show_blank', false) and cell.type == RBMK.CELL_BLANK) or
    (not RBMK.Debug.GetSetting('show_steam', true) and cell.type == RBMK.CELL_STEAM) then return end
    local pos = RBMK.Debug.GetCellWorldPos(x, y)
    local lines = {}
    local symbol = RBMK.CellSymbols[cell.type] or '?'
    table.insert(lines, symbol)
    table.insert(lines, string.format('H: %.1f', cell.heat or 0))
    if cell.type == RBMK.CELL_FUEL then
        table.insert(lines, string.format('sH: %.1f', cell.skinHeat or 0))
        table.insert(lines, string.format('cH: %.1f', cell.coreHeat or 0))
        table.insert(lines, tostring(cell.fuelType or '???'))
        table.insert(lines, string.format('F: %.1f', cell.flux or 0))
        table.insert(lines, string.format('X: %.1f', cell.xenon or 0))
    elseif cell.type == RBMK.CELL_CONTROL then
        table.insert(lines, string.format('%s', cell.name or '???'))
        table.insert(lines, string.format('I: %.2f', cell.insertion or 0))
        table.insert(lines, string.format('> %.2f', cell.targetInsertion or 0))
    elseif cell.type == RBMK.CELL_REFLECTOR then
        table.insert(lines, string.format('RE: %s', tostring(cell.reflectorIn)))
    elseif cell.type == RBMK.CELL_SOURCE then
        table.insert(lines, string.format('SRC: %.1f', cell.sourceStrength or 0))
        table.insert(lines, string.format('CLS: %s', tostring(cell.closedSource)))
    elseif cell.type == RBMK.CELL_STEAM then
        table.insert(lines, string.format('W: %.1f', cell.water or 0))
    end

    local text = table.concat(lines, ' ')
    cam.Start3D2D(pos + Vector(0, 0, 20), Angle(0, LocalPlayer():EyeAngles().y - 90, 90), RBMK.Debug.GetSettingNumber('debug_textscale_cell', 1.0))
    draw.SimpleTextOutlined(text, 'DermaDefault', 0, 0, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
    draw.SimpleTextOutlined(string.format('[ %d,%d ]', x, y), 'DermaDefault', 0, -20, Color(255, 255, 0), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
    cam.End3D2D()
end

function RBMK.Debug.RenderCells()
    if not RBMK.Debug.GetSetting('debug_enabled', true) then return end
    local state = RBMK.Debug.ClientState
    if not state.Cells then return end
    for _, cell in ipairs(state.Cells) do
        RBMK.Debug.RenderCell(cell.x, cell.y, cell)
    end
end

function RBMK.Debug.RenderFluxLines()
    if not RBMK.Debug.GetSetting('draw_flux_rays', true) then return end
    local state = RBMK.Debug.ClientState
    if not state.FluxLines then return end
    render.SetColorMaterial()
    for _, line in ipairs(state.FluxLines) do
        if line.flux < 0.05 then continue end
        local offset = Vector(0, 0, 0)
        local color = Color(0, 255, 0)
        -- HORIZONTAL
        if line.dx ~= 0 then
            -- East
            if line.dx > 0 then
                offset = Vector(0, 6, 0)
                color = Color(0, 255, 0)
            end

            -- West
            if line.dx < 0 then
                offset = Vector(0, -6, 0)
                color = Color(0, 88, 0)
            end
        end

        -- VERTICAL
        if line.dy ~= 0 then
            -- North
            if line.dy > 0 then
                offset = Vector(-6, 0, 0)
                color = Color(0, 255, 0)
            end

            -- South
            if line.dy < 0 then
                offset = Vector(6, 0, 0)
                color = Color(0, 88, 0)
            end
        end

        local startPos = line.start + offset
        local endPos = line.finish + offset
        -- MAIN LINE
        render.DrawLine(startPos, endPos, color, true)
        -- ARROW
        local arrowDir = endPos - startPos
        arrowDir:Normalize()
        local back = arrowDir * -6
        local right = Vector(-arrowDir.y, arrowDir.x, 0)
        local arrowA = endPos + back + right * 3
        render.DrawLine(endPos, arrowA, color, true)
        -- FLUX TEXT
        local textPos = arrowA + offset * 0.5 + Vector(0, 0, -4)
        RBMK.Debug.DrawWorldText(textPos, string.format('%.1f', line.flux), color)
    end
end

function RBMK.Debug.RenderVesselInfo()
    if not RBMK.Debug.GetSetting('debug_enabled', true) then return end
    local info = RBMK.Debug.ClientState.VesselInfo
    if not info then return end
    local origin = info.worldOrigin or Vector(0, 0, 0)
    local basePos = origin + Vector(0, 0, 128)
    local lines = {'MODEL: ' .. tostring(info.model),
    string.format('AVG H: %.1f', info.averageHeat or 0),
    string.format('MAX H: %.1f', info.maxHeat or 0),
    string.format('FLUX: %.1f', info.totalFlux or 0),
    string.format('XENON: %.1f', info.averageXenon or 0),
    string.format('WATER: %.1f / %.1f', info.water or 0, info.maxWater or 0),
    string.format('STEAM: %.1f / %.1f', info.steam or 0, info.maxSteam or 0)}
    for i, line in ipairs(lines) do
        local pos = basePos + Vector(0, 0, -(i - 1) * 8)
        RBMK.Debug.DrawWorldText(pos, line, Color(0, 255, 255))
    end
end