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
        data.leaking = cell.leaking and true or false
        data.meltingDown = cell.meltingDown and true or false
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
    RBMK.Debug.ClientState = RBMK.Debug.ClientState or {}
    RBMK.Debug.ClientState.FluxLines = RBMK.Debug.ClientState.FluxLines or {}
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
        lastThermalMW = RBMK.LastThermalMW or 0,
        waterTemperature = RBMK.WaterTemperature or 0,
        water = RBMK.Water or 0,
        maxWater = RBMK.MaxWater or 0,
        steam = RBMK.Steam or 0,
        maxSteam = RBMK.MaxSteam or 0,
        hardMaxSteam = RBMK.HardMaxSteam or 0,
        totalVolume = RBMK.TotalVolume or 0,
        steamSpace = RBMK.SteamSpace or 0,
        minSteamSpace = RBMK.MinSteamSpace or 0,
        rpvPressure = RBMK.RPVPressure or 0,
        pressureUnit = RBMK.PressureUnit or 'bar',
        steamOutletOpen = RBMK.SteamOutletOpen and true or false,
        feedwaterInletOpen = RBMK.FeedwaterInletOpen and true or false,
        drainValveOpen = RBMK.DrainValveOpen and true or false,
        lastSteamExportFlow = RBMK.LastSteamExportFlow or 0,
        lastDrainFlow = RBMK.LastDrainFlow or 0,
        blowoutPressure = RBMK.BlowoutPressure or 0,
        catastrophicPressure = RBMK.CatastrophicPressure or 0,
        eventFailed = RBMK.EventState and RBMK.EventState.Failed or false,
        failureReason = RBMK.EventState and RBMK.EventState.FailureReason or nil,
        lastBlowoutSteamLoss = RBMK.EventState and RBMK.EventState.LastBlowoutSteamLoss or 0,
        lastBlowoutPressure = RBMK.EventState and RBMK.EventState.LastBlowoutPressure or 0,
        lastBlowoutValve = RBMK.EventState and RBMK.EventState.LastBlowoutValve or nil,
        lastBlowoutCount = RBMK.EventState and RBMK.EventState.LastBlowoutCount or 0,
        lastBlowoutDuration = RBMK.EventState and RBMK.EventState.LastBlowoutDuration or 0,
        blowoutEnabled = RBMK.BlowoutEnabled and true or false,
        blowoutValveCount = RBMK.BlowoutValves and #RBMK.BlowoutValves or 0,
        lastFuelLeak = RBMK.EventState and RBMK.EventState.LastFuelLeak or nil,
        lastMeltdown = RBMK.EventState and RBMK.EventState.LastMeltdown or nil
    }
end

function RBMK.Debug.Tick()
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
