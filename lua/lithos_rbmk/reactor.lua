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

RBMK.AverageXenon = 0

--TODO : Somehow Implement Megawatt Thermal (thermal transfer method). Which will be used by Auto control rod to stabilize the reactor for power production later (New Turbine Module in lithos_powerplant).
--TODO : Implement Pressure in the reactor vessel. RPV will accept less and less water from Steamline network or ECCS if the incoming has lower pressure vice-versa.

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

function RBMK.GetCoreHeat(x, y)
    local cell = RBMK.GetCell(x, y)
    if cell.type ~= RBMK.CELL_FUEL then return 0 end
    return cell.coreHeat or 0
end

function RBMK.GetSkinHeat(x, y)
    local cell = RBMK.GetCell(x, y)
    if cell.type ~= RBMK.CELL_FUEL then return 0 end
    return cell.skinHeat or 0
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

    RBMK.MaxWater = steamChannels * 10
    RBMK.MaxSteam = steamChannels * 16000
end

function RBMK.AddInitialWater(percent)
    local factor = math.Clamp(percent,0,100) / 100
    RBMK.Water = RBMK.MaxWater * factor
end

-- Start loop
function RBMK.Start()
    if timer.Exists('RBMK_Tick') then timer.Remove('RBMK_Tick') end
    timer.Create('RBMK_Tick', RBMK.TickInterval, 0, function() RBMK.Tick() end)
    print('[LITHOS_RBMK] Started')
end

-- =========================================
-- Reactor Events
-- =========================================

function RBMK.BlowoutSteam()
    --Blowout Select a random RPV column to make them jump.
    --Naming convention for RPV in the map is [Name]_0, [Name]_1, [Name]_2... Name defined by mapper via map script.
    --Auto-detect how many RPV is found then apply the number.
    --If there are no func_movelinear found at all, fall back to default value.
    --This ent-fire func_movelinears with random setspeed and fire 'Close' input at it after a random duration, making them fall.
    --1 Second After which, they can start jumping again.
    --This function is called repeatedly by it's helper that reads RPV Pressure.
    --The helper of this will scale frequency, set speed and duration based on how much overpressured the RPV is.
    --Each jump removes a configurable static amount of steam. so no water return.
    --This can also be manually called by it's API through in-map's button.
end

function RBMK.FuelChannelLeakCheck()
    --Check every 30 seconds
    --Select an offending fuel channel whose CELL Heat has breached 1500 C.
    --Starting from 5% then +5% chance per 50 C above 1500 C.
end

function RBMK.FuelChannelLeak()
    --Fired when it's check success, Throw warning to annunciator(NYI) 
    --and trigger runaway heat logic on the offending fuel channel which will likely result in blowout or meltdown.
    --If there are no water to flashboil and couldn't cause blowout, the heat will just keep rising until FuelChannelMelt.
end

function RBMK.FuelMeltdown()
    --Occurs when fuel channel's temperature exceed 3000 C and there are no water or steam to blowout.
    --This function throw warning to annunciator and ent-fire a logic_relay.
    --Then waits for 30 seconds before causing a steam explosion or violent chemical reactions
    --which in turn, Trigger Catastrophic Failure anyways.
end

function RBMK.CatastrophicFailure()
    --Violently(in theory) destroy the reactor after upper threshold overpressure is breached.
    --This is the last destination of 'meltdown' and the final nail in the sarcophagus of Lithosquare RBMK.
    --This function ent-fire a logic_relay. Mapper defines how it will happen.
    --Then stop RBMK tick timer.
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