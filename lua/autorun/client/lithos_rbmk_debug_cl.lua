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

RBMK.Debug.CellFilterSettings = {
    [RBMK.CELL_BLANK] = {'show_blank', false},
    [RBMK.CELL_FUEL] = {'show_fuel', true},
    [RBMK.CELL_STEAM] = {'show_steam', true},
    [RBMK.CELL_CONTROL] = {'show_control', true},
    [RBMK.CELL_AUTOROD] = {'show_autorod', true},
    [RBMK.CELL_REFLECTOR] = {'show_reflector', true},
    [RBMK.CELL_ABSORBER] = {'show_absorber', true},
    [RBMK.CELL_SOURCE] = {'show_neutronsource', true}
}

-- Client Debug module
timer.Simple(10, function()
    if not GetGlobal2Bool('LITHOSQUARE_RBMK_INITIALIZED_GLOBAL', false) then
        print('[Lithosquare RBMK Debug Client] No RBMK detected after 10 seconds, terminating')
        return
    end

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
    print('[Lithosquare RBMK Debug Client] Client initialized')
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

function RBMK.Debug.DrawWorldText(pos, text, color, sizeOverride)
    sizeOverride = sizeOverride or RBMK.Debug.GetSettingNumber('debug_textscale', 1.0)
    cam.Start3D2D(pos, Angle(0, LocalPlayer():EyeAngles().y - 90, 90), sizeOverride)
    draw.SimpleTextOutlined(text, 'DermaDefault', -10, 0, color or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1.2, color_black)
    cam.End3D2D()
end

function RBMK.Debug.ShouldRenderCell(cell)
    if not cell or cell.type == RBMK.CELL_VOID then return false end
    local filter = RBMK.Debug.CellFilterSettings[cell.type]
    if not filter then return true end
    return RBMK.Debug.GetSetting(filter[1], filter[2])
end

function RBMK.Debug.RenderCell(x, y, cell)
    if not RBMK.Debug.ShouldRenderCell(cell) then return end
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
        if cell.leaking then table.insert(lines, 'LEAK') end
        if cell.meltingDown then table.insert(lines, 'MELT') end
    elseif cell.type == RBMK.CELL_CONTROL then
        table.insert(lines, string.format('%s', cell.name or '???'))
        table.insert(lines, string.format('I: %.2f', cell.insertion or 0))
        table.insert(lines, string.format('> %.2f', cell.targetInsertion or 0))
    elseif cell.type == RBMK.CELL_REFLECTOR then
        table.insert(lines, string.format('RE: %s', tostring(cell.reflectorIn)))
    elseif cell.type == RBMK.CELL_SOURCE then
        table.insert(lines, string.format('SRC: %.1f', cell.sourceStrength or 0))
        table.insert(lines, string.format('CLS: %s', tostring(cell.closedSource)))
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
    if not RBMK.Debug.GetSetting('debug_enabled', true) then return end
    if not RBMK.Debug.GetSetting('draw_flux_rays', true)  then return end
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
                color = Color(0, 167, 0)
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
                color = Color(0, 167, 0)
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
        RBMK.Debug.DrawWorldText(textPos, string.format('%.1f', line.flux), color, RBMK.Debug.GetSettingNumber('debug_textscale_flux', 0.3))
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
    string.format('MWt: %.2f', info.lastThermalMW or 0),
    string.format('FLUX: %.1f', info.totalFlux or 0),
    string.format('XENON: %.1f', info.averageXenon or 0),
    string.format('--------------------------------'),
    string.format('WATER: %.1f / %.1f', info.water or 0, info.maxWater or 0),
    string.format('W TEMP: %.1f C', info.waterTemperature or 0),
    string.format('STEAM: %.1f / %.1f', info.steam or 0, info.maxSteam or 0),
    string.format('SPACE: %.1f / %.1f', info.steamSpace or 0, info.totalVolume or 0),
    string.format('RPV P: %.1f %s', info.rpvPressure or 0, info.pressureUnit or 'bar'),
    string.format('OUT: %s %.1f/s', tostring(info.steamOutletOpen), info.lastSteamExportFlow or 0),
    string.format('--------------------------------'),
    string.format('IN/DRAIN: %s / %s %.1f/s', tostring(info.feedwaterInletOpen), tostring(info.drainValveOpen), info.lastDrainFlow or 0),
    string.format('BLOWOUT: %s [%d]', tostring(info.blowoutEnabled), info.blowoutValveCount or 0),
    string.format('BLOW/CATA: %.1f / %.1f', info.blowoutPressure or 0, info.catastrophicPressure or 0)}
    if info.lastBlowoutSteamLoss and info.lastBlowoutSteamLoss > 0 then
        table.insert(lines, string.format('LAST BLOW: x%d %.1f @ %.1f %.1fs', info.lastBlowoutCount or 0, info.lastBlowoutSteamLoss or 0, info.lastBlowoutPressure or 0, info.lastBlowoutDuration or 0))
        table.insert(lines, string.format('BLOW COLS: %s', tostring(info.lastBlowoutValve or '?')))
    end
    if info.lastFuelLeak then table.insert(lines, string.format('LEAK: %d,%d', info.lastFuelLeak.x or 0, info.lastFuelLeak.y or 0)) end
    if info.lastMeltdown then table.insert(lines, string.format('MELT: %d,%d', info.lastMeltdown.x or 0, info.lastMeltdown.y or 0)) end
    if info.eventFailed then table.insert(lines, 'FAILED: ' .. tostring(info.failureReason or 'unknown')) end
    for i, line in ipairs(lines) do
        local pos = basePos + Vector(0, 0, -(i - 1) * 8)
        RBMK.Debug.DrawWorldText(pos, line, Color(0, 255, 255))
    end
end
