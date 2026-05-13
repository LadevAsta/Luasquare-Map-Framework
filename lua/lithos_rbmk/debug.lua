RBMK = RBMK or {}
RBMK.Debug = RBMK.Debug or {}
RBMK.Debug.ClientState = {
    Cells = {},
    FluxLines = {},
    VesselInfo = {}
}

function RBMK.Debug.BuildCells()
    RBMK.Debug.ClientState.Cells = {}
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.GetCell(x, y)
            if cell then RBMK.Debug.BuildCell(x, y, cell) end
        end
    end
end

function RBMK.Debug.BuildCell(x, y, cell)
    if cell.type == RBMK.CELL_VOID then return end
    local data = {
        x = x,
        y = y,
        type = cell.type,
        symbol = RBMK.CellSymbols[cell.type] or '?',
        -- Shared
        heat = cell.heat or 0
    }

    if cell.type == RBMK.CELL_FUEL then
        data.fuelType = cell.fuelType or 'UNKNOWN'
        data.skinHeat = cell.skinHeat or 0
        data.coreHeat = cell.coreHeat or 0
        data.flux = cell.flux or 0
        data.lastFlux = cell.lastFlux or 0
        data.xenon = cell.xenon or 0
    end

    if cell.type == RBMK.CELL_STEAM then
        data.coolingRate = cell.coolingRate or 0
        data.waterUseRate = cell.waterUseRate or 0
    end

    if cell.type == RBMK.CELL_CONTROL then
        data.name = cell.name or 'unnamed'
        data.group = cell.group or 'nocolor'
        data.insertion = cell.insertion or 0
        data.targetInsertion = cell.targetInsertion or 0
        data.lastInsertion = cell.lastInsertion or 0
        data.inserting = cell.inserting or 0
        data.stationaryTime = cell.stationaryTime or 0
        data.movingTime = cell.movingTime or 0
        data.moveSpeed = cell.moveSpeed or 0
        data.graphiteTip = cell.graphiteTip and true or false
        data.reflector = cell.reflector and true or false
        data.visualEnt = cell.visualEnt
    end

    if cell.type == RBMK.CELL_REFLECTOR then data.reflectorIn = cell.reflectorIn and true or false end

    if cell.type == RBMK.CELL_SOURCE then
        data.flux = cell.flux or 0
        data.lastFlux = cell.lastFlux or 0
        data.sourceStrength = cell.sourceStrength or 0
        data.closedSource = cell.closedSource and true or false
    end

    table.insert(RBMK.Debug.ClientState.Cells, data)
end

function RBMK.Debug.AddFluxLine(startPos, endPos, flux, dx, dy)
    table.insert(RBMK.Debug.ClientState.FluxLines, {
        start = startPos,
        finish = endPos,
        flux = flux,
        dx = dx,
        dy = dy
    })
end

function RBMK.Debug.BuildFluxLines()
    -- FluxLines already populated
    -- by AddFluxLine during flux sim
end

function RBMK.Debug.BuildVesselInfo()
    RBMK.Debug.ClientState.VesselInfo = {
        worldOrigin = RBMK.WorldOrigin or Vector(0,0,0),
        cellSpacing = RBMK.CellSpacing or 64,
        cellSymbols = RBMK.CellSymbols,
        model = RBMK.ModelName or 'UNKNOWN',
        averageHeat = RBMK.AverageHeat or 0,
        maxHeat = RBMK.MaxHeat or 0,
        totalFlux = RBMK.TotalFlux or 0,
        averageXenon = RBMK.AverageXenon or 0,
        water = RBMK.Water or 0,
        maxWater = RBMK.MaxWater or 0,
        steam = RBMK.Steam or 0,
        maxSteam = RBMK.MaxSteam or 0
    }
end

function RBMK.Debug.Tick()
    RBMK.Debug.ClientState.FluxLines = {}
    RBMK.Debug.BuildCells()
    --RBMK.Debug.BuildFluxLines()
    RBMK.Debug.BuildVesselInfo()
    RBMK.Debug.Broadcast()
end

function RBMK.Debug.Broadcast()
    net.Start('RBMK_DebugState')
    net.WriteTable(RBMK.Debug.ClientState)
    net.Broadcast()
end
--RBMK.Debug = RBMK.Debug or {}
--RBMK.Debug.FluxLines = {}
-- function RBMK.Debug.GetSetting(name, default)
--     local cvar = GetConVar('lithos_rbmk_' .. name)
--     if not cvar then return default end
--     return cvar:GetBool()
-- end
-- function RBMK.Debug.DrawCells()
--     for x = 1, RBMK.Width do
--         for y = 1, RBMK.Height do
--             local cell = RBMK.GetCell(x, y)
--             if cell then RBMK.Debug.DrawCell(x, y, cell) end
--         end
--     end
-- end
-- function RBMK.Debug.DrawCell(x, y, cell)
--     if cell.type == RBMK.CELL_VOID or (not RBMK.Debug.GetSetting('show_blank', false) and cell.type == RBMK.CELL_BLANK) or (not RBMK.Debug.GetSetting('show_steam', true) and cell.type == RBMK.CELL_STEAM) then return end
--     local pos = RBMK.CellToWorld(x, y)
--     local lines = {}
--     local symbol = RBMK.CellSymbols[cell.type] or '?'
--     table.insert(lines, symbol)
--     table.insert(lines, string.format('H: %.1f', cell.heat or 0))
--     if cell.type == RBMK.CELL_FUEL then
--         table.insert(lines, string.format('sH: %.1f', cell.skinHeat or 0))
--         table.insert(lines, string.format('cH: %.1f', cell.coreHeat or 0))
--         table.insert(lines, string.format('%s', cell.fuelType or 0))
--         table.insert(lines, string.format('F: %.1f', cell.flux or 0))
--         table.insert(lines, string.format('X: %.1f', cell.xenon or 0))
--     elseif cell.type == RBMK.CELL_CONTROL then
--         table.insert(lines, string.format('N: %s', cell.name or '???'))
--         table.insert(lines, string.format('I: %.2f', cell.insertion or 0))
--         table.insert(lines, string.format('> %.2f', cell.targetInsertion or 0))
--     elseif cell.type == RBMK.CELL_REFLECTOR then
--         table.insert(lines, string.format('RE: %s', tostring(cell.reflectorIn) or '???'))
--     end
--     local text = table.concat(lines, ' ')
--     debugoverlay.Text(pos + Vector(0, 0, 20), text, RBMK.TickInterval + 0.02, true)
--     local postext = '[ ' .. tostring(x) .. ',' .. tostring(y) .. ' ]'
--     debugoverlay.Text(pos + Vector(0, 0, 30), postext, RBMK.TickInterval + 0.02, true)
-- end
-- function RBMK.Debug.AddFluxLine(startPos, endPos, flux, dx, dy)
--     table.insert(RBMK.Debug.FluxLines, {
--         start = startPos,
--         finish = endPos,
--         flux = flux,
--         dx = dx,
--         dy = dy
--     })
-- end
-- function RBMK.Debug.DrawFluxLines()
--     if not RBMK.Debug.GetSetting('draw_flux_rays', true) then return end
--     local duration = RBMK.TickInterval + 0.01
--     for _, line in ipairs(RBMK.Debug.FluxLines) do
--         if line.flux < 0.05 then continue end
--         local offset = Vector(0, 0, 0)
--         local color = Color(0, 255, 0)
--         -- Horizontal rays
--         if line.dx ~= 0 then
--             -- East
--             if line.dx > 0 then
--                 offset = Vector(0, 6, 0)
--                 color = Color(0, 255, 0)
--             end
--             -- West
--             if line.dx < 0 then
--                 offset = Vector(0, -6, 0)
--                 color = Color(0, 88, 0)
--             end
--         end
--         -- Vertical rays
--         if line.dy ~= 0 then
--             -- North
--             if line.dy > 0 then
--                 offset = Vector(-6, 0, 0)
--                 color = Color(0, 255, 0)
--             end
--             -- South
--             if line.dy < 0 then
--                 offset = Vector(6, 0, 0)
--                 color = Color(0, 88, 0)
--             end
--         end
--         local startPos = line.start + offset
--         local endPos = line.finish + offset
--         -- Main line
--         debugoverlay.Line(startPos, endPos, duration, color, true)
--         -- Arrow
--         local arrowDir = endPos - startPos
--         arrowDir:Normalize()
--         local back = arrowDir * -6
--         local right = Vector(-arrowDir.y, arrowDir.x, 0)
--         local arrowA = endPos + back + right * 3
--         --local arrowB = endPos + back - right * 3
--         debugoverlay.Line(endPos, arrowA, duration, color, true)
--         --debugoverlay.Line(endPos, arrowB, duration, color, true)
--         -- Flux text near arrow
--         local textPos = arrowA + offset * 0.5 + Vector(0, 0, -4)
--         debugoverlay.Text(textPos, string.format('%.1f', line.flux), duration, true)
--     end
-- end
-- function RBMK.Debug.DrawVesselInfo()
--     local base = RBMK.WorldOrigin + Vector(0, 0, 128)
--     local duration = RBMK.TickInterval + 0.01
--     local lines = {string.format('MODEL: %s', RBMK.ModelName or 'UNKNOWN'), string.format('AVG H: %.1f', RBMK.AverageHeat or 0), string.format('MAX H: %.1f', RBMK.MaxHeat or 0), string.format('FLUX: %.1f', RBMK.TotalFlux or 0), string.format('XENON: %.1f', RBMK.AverageXenon or 0), string.format('WATER: %.1f / %.1f', RBMK.Water or 0, RBMK.MaxWater or 0), string.format('STEAM: %.1f / %.1f', RBMK.Steam or 0, RBMK.MaxSteam or 0)}
--     for i, line in ipairs(lines) do
--         local pos = base + Vector(0, 0, -(i - 1) * 8)
--         debugoverlay.Text(pos, line, duration, true)
--     end
-- end
-- function RBMK.Debug.Tick()
--     if not RBMK.Debug.GetSetting('debug_enabled', true) then return end
--     RBMK.Debug.DrawCells()
--     RBMK.Debug.DrawFluxLines()
--     RBMK.Debug.DrawVesselInfo()
-- end