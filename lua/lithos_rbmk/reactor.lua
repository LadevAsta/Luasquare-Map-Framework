RBMK = RBMK or {}
RBMK.ModelName = 'Unknown RBMK'
RBMK.Width = 0
RBMK.Height = 0
RBMK.Matrix = {}
RBMK.TickInterval = 0.1

RBMK.Water = 0
RBMK.Steam = 0
RBMK.MaxWater = 0
RBMK.MaxSteam = 0

RBMK.AverageHeat = 20
RBMK.MaxHeat = 20

-- =========================================
-- MATRIX
-- =========================================
function RBMK.CreateMatrix(w, h)
    RBMK.Width = w
    RBMK.Height = h
    RBMK.Matrix = {}
    for x = 1, w do
        RBMK.Matrix[x] = {}
        for y = 1, h do
            RBMK.Matrix[x][y] = RBMK.CreateBlank()
        end
    end
end

-- =========================================
-- CELLS
-- =========================================
function RBMK.SetCell(x, y, cell)
    if not RBMK.Matrix[x] then return end
    if not RBMK.Matrix[x][y] then return end
    RBMK.Matrix[x][y] = cell
end

function RBMK.GetCell(x, y)
    if not RBMK.Matrix[x] then return nil end
    return RBMK.Matrix[x][y]
end

-- Reactor tick
function RBMK.Tick()
    RBMK.DoFluxStep()
    RBMK.DoXenonStep()
    RBMK.DoFuelHeat()
    RBMK.CommitFlux()
    RBMK.DoHeatStep()
    RBMK.DoSteamStep()
    RBMK.DoControlStep()
    RBMK.UpdateTelemetry()
    RBMK.Debug.Tick()
end

-- Data Accessor
function RBMK.GetHeat(x, y)
    local cell = RBMK.GetCell(x, y)
    if not cell then return 0 end
    return cell.heat or 0
end

function RBMK.GetFlux(x, y)
    local cell = RBMK.GetCell(x, y)
    if not cell then return 0 end
    return cell.flux or 0
end

function RBMK.GetCellType(x, y)
    local cell = RBMK.GetCell(x, y)
    if not cell then return nil end
    return cell.type
end

function RBMK.GetRodInsertion(x, y)
    local cell = RBMK.GetCell(x, y)
    if not cell then return 0 end
    return cell.rodInsertion or 0
end

-- Utilities
function RBMK.RecalculatePools()
    local steamChannels = 0
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type == RBMK.CELL_STEAM then steamChannels = steamChannels + 1 end
        end
    end

    RBMK.Water = steamChannels * 1000
    RBMK.MaxSteam = steamChannels * 16000
end

-- Start loop
function RBMK.Start()
    if timer.Exists('RBMK_Tick') then timer.Remove('RBMK_Tick') end
    timer.Create('RBMK_Tick', RBMK.TickInterval, 0, function() RBMK.Tick() end)
    print('[LITHOS_RBMK] Started')
end

-- =========================================
-- Functions
-- =========================================
function RBMK.CellToWorld(x, y)
    return RBMK.WorldOrigin + Vector((x - 1) * RBMK.CellSpacing, (y - 1) * RBMK.CellSpacing, 0)
end

function RBMK.UpdateTelemetry()
    local totalHeat = 0
    local validCells = 0
    local maxHeat = 0
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type ~= RBMK.CELL_VOID then
                totalHeat = totalHeat + (cell.heat or 0)
                validCells = validCells + 1
                if cell.heat > maxHeat then maxHeat = cell.heat end
            end
        end
    end

    RBMK.AverageHeat = 0
    if validCells > 0 then RBMK.AverageHeat = totalHeat / validCells end
    RBMK.MaxHeat = maxHeat
end