RBMK = RBMK or {}
local dirs4 = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
RBMK.FluxRange = 5
function RBMK.DoFluxStep()
    if RBMK.Debug.DrawFluxRays then RBMK.Debug.FluxLines = {} end
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
    if cell.type == RBMK.CELL_SOURCE then return cell.sourceStrength or 20 end
    -- Fuel only
    if cell.type ~= RBMK.CELL_FUEL then return 0 end
    local fuel = RBMK.FuelTypes[cell.fuelType]
    if not fuel then return 0 end
    local x = math.max((cell.lastFlux or 0) - (cell.xenon or 0), 0)
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
        if RBMK.Debug.DrawFluxRays then RBMK.Debug.AddFluxLine(startPos, endPos, flux, dx, dy) end
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
        cell.flux = (cell.flux or 0) + flux
        return false, dirX, dirY, flux
    end

    -- Steam
    if cell.type == RBMK.CELL_STEAM then return true, dirX, dirY, flux end
    -- Reflector
    if cell.type == RBMK.CELL_REFLECTOR then return true, -dirX, -dirY, flux end
    -- Control Rod
    if cell.type == RBMK.CELL_CONTROL then
        local insertion = cell.insertion or 0
        local reduction = insertion / 100
        flux = flux * (1 - reduction)
        return true, dirX, dirY, flux
    end
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