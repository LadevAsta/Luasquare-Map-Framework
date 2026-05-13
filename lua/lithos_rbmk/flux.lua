RBMK = RBMK or {}
local dirs4 = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
RBMK.TotalFlux = 0
RBMK.TotalFluxSubtracted = 0
function RBMK.DoFluxStep()
    RBMK.TotalFlux = 0
    RBMK.Debug.FluxLines = {}
    RBMK.ClearFlux()
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.GetCell(x, y)
            if cell then RBMK.EmitCellFlux(x, y, cell) end
        end
    end
end

function RBMK.ClearFlux()
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.GetCell(x, y)
            if cell then cell.flux = 0 end
        end
    end
end

-- Flux Output
function RBMK.GetCellFluxOutput(cell)
    -- Neutron source
    if cell.type == RBMK.CELL_SOURCE then
        if cell.closedSource then return 0 end
        return cell.sourceStrength or 20
    end

    -- Fuel only
    if cell.type ~= RBMK.CELL_FUEL or cell.fuelType == 'EMPTY' then return 0 end
    local fuel = RBMK.FuelTypes[cell.fuelType]
    if not fuel then return 0 end
    local baseFlux = cell.lastFlux or 0
    local xenon = cell.xenon or 0
    local x = baseFlux * ((100 - xenon) / 100)
    return fuel.fluxFunction(x)
end

function RBMK.EmitCellFlux(x, y, cell)
    local strength = RBMK.GetCellFluxOutput(cell)
    if strength <= 0 then return end
    for _, dir in ipairs(dirs4) do
        RBMK.EmitRay(x, y, dir[1], dir[2], strength)
    end
end

function RBMK.EmitRay(startX, startY, dirX, dirY, strength)
    RBMK.TotalFlux = RBMK.TotalFlux + strength
    RBMK.TotalFluxSubtracted = RBMK.TotalFlux - RBMK.TotalFluxSubtractDefine
    local x = startX
    local y = startY
    local dx = dirX
    local dy = dirY
    local flux = strength
    for i = 1, RBMK.FluxRange do
        local startPos = RBMK.CellToWorld(x, y)
        x = x + dx
        y = y + dy
        local cell = RBMK.GetCell(x, y)
        if not cell then break end
        local raycontinue, newDx, newDy, newFlux = RBMK.ProcessRayCell(cell, dx, dy, flux)
        dx = newDx or dx
        dy = newDy or dy
        flux = newFlux or flux
        local endPos = RBMK.CellToWorld(x, y)
        RBMK.Debug.AddFluxLine(startPos, endPos, flux, dx, dy)
        if not raycontinue then break end
        if flux <= 0.001 then break end
    end
end

-- Ray cell interaction
function RBMK.ProcessRayCell(cell, dirX, dirY, flux)
    -- Blank
    if cell.type == RBMK.CELL_BLANK then return true, dirX, dirY, flux end
    -- Fuel
    if cell.type == RBMK.CELL_FUEL then
        if cell.fuelType == 'EMPTY' then return true, dirX, dirY, flux end
        cell.flux = (cell.flux or 0) + flux
        return false, dirX, dirY, flux
    end

    -- Steam
    if cell.type == RBMK.CELL_STEAM then return true, dirX, dirY, flux end
    -- Control Rod
    if cell.type == RBMK.CELL_CONTROL then
        local ins = math.Clamp(cell.insertion or 1, 0, 1)
        -- Graphite tip zone
        if cell.graphiteTip and cell.inserting and ins > 0.85 and ins < 0.95 then
            local moveFactor = math.Clamp(cell.movingTime / 10, 0, 1)
            local spike = 1 + ((0.95 - ins) * 4) * moveFactor
            flux = flux * spike
        else
            flux = flux * (1 - ins)
        end

        if flux <= 0.001 then return false, dirX, dirY, 0 end
        if cell.reflector then return true, -dirX, -dirY, flux end
        return true, dirX, dirY, flux
    end

    -- Neutron Source
    if cell.type == RBMK.CELL_SOURCE then
        if cell.closedSource then return true, -dirX, -dirY, flux end
        return false, dirX, dirY, flux
    end

    -- Reflector
    if cell.type == RBMK.CELL_REFLECTOR then
        if cell.reflectorIn then
            return true, -dirX, -dirY, flux
        else
            return true, dirX, dirY, flux
        end
    end

    if cell.type == RBMK.CELL_ABSORBER then return false, dirX, dirY, flux end
    return false
end

-- commit flux
function RBMK.CommitFlux()
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.GetCell(x, y)
            if cell then cell.lastFlux = cell.flux or 0 end
        end
    end
end