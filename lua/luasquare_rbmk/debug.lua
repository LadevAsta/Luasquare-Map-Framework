RBMK = RBMK or {}
RBMK.Debug = RBMK.Debug or {}
RBMK.Debug.ClientState = {
    Cells = {},
    FluxLines = {},
    VesselInfo = {}
}

local DEBUG_WIRE_VERSION = 3
local DEBUG_PACKET_VESSEL = 1
local DEBUG_PACKET_CELLS = 2
local DEBUG_PACKET_FLUX = 3
local DEBUG_PACKET_END = 4
local DEBUG_CELL_CHUNK_SIZE = 64
local DEBUG_FLUX_CHUNK_SIZE = 96

local function writeString(value)
    net.WriteString(value ~= nil and tostring(value) or '')
end

local function writeOptionalString(value)
    net.WriteBool(value ~= nil)
    if value ~= nil then net.WriteString(tostring(value)) end
end

local function writeVector(value)
    net.WriteVector(value or Vector(0, 0, 0))
end

local function writePoint(value)
    net.WriteBool(value ~= nil)
    if not value then return end
    net.WriteUInt(value.x or 0, 16)
    net.WriteUInt(value.y or 0, 16)
end

local function startDebugPacket(packetType, sequence)
    net.Start('RBMK_DebugState')
    net.WriteUInt(DEBUG_WIRE_VERSION, 8)
    net.WriteUInt(packetType, 4)
    net.WriteUInt(sequence, 16)
end

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
        data.autoRegulator = cell.autoRegulator and true or false
        data.autoInsertion = cell.autoInsertion or 0
        data.autoTargetInsertion = cell.autoTargetInsertion or 0
        data.autoMaxInsertion = cell.autoMaxInsertion or 0
        data.graphiteTip = cell.graphiteTip and true or false
        data.reflector = cell.reflector and true or false
        data.visualEnt = cell.visualEnt
        data.powerBlocked = cell.powerBlocked and true or false
        data.stuck = cell.stuck and true or false
        data.scramStuck = cell.scramStuck and true or false
        data.scramStuckPending = cell.scramStuckPending and true or false
        data.stuckInsertion = cell.stuckInsertion or 0
        data.lastStuckReason = cell.lastStuckReason
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
        lastFlashBoilMW = RBMK.LastFlashBoilMW or 0,
        lastSteamGenerated = RBMK.LastSteamGenerated or 0,
        lastFlashSteamGenerated = RBMK.LastFlashSteamGenerated or 0,
        autoRegulatorEnabled = RBMK.AutoRegulatorEnabled and true or false,
        autoRegulatorUsePID = RBMK.AutoRegulatorUsePID and true or false,
        autoRegulatorTargetMW = RBMK.AutoRegulatorTargetMW or 0,
        autoRegulatorTargetInsertion = RBMK.AutoRegulatorTargetInsertion or 0,
        autoRegulatorLastError = RBMK.AutoRegulatorLastError or 0,
        controlRodPowerGrid = RBMK.ControlRodPowerGrid,
        controlRodPowerBreaker = RBMK.ControlRodPowerBreaker,
        controlRodPowerDemandMW = RBMK.ControlRodPowerDemandMW or 0,
        controlRodPowerAcceptedMW = RBMK.ControlRodPowerAcceptedMW or 0,
        controlRodPowered = RBMK.ControlRodPowered ~= false,
        controlRodMovingCount = RBMK.ControlRodMovingCount or 0,
        controlRodBlockedCount = RBMK.ControlRodBlockedCount or 0,
        controlRodStuckCount = RBMK.ControlRodStuckCount or 0,
        integrityScore = RBMK.IntegrityScore or 1,
        integrityDamage = RBMK.IntegrityDamage or 0,
        integrityLastDamage = RBMK.IntegrityLastDamage or 0,
        integrityLastDamageReason = RBMK.IntegrityLastDamageReason,
        steamSeparator = RBMK.SteamSeparator,
        lastRecircFlow = RBMK.LastRecircFlow or 0,
        lastNaturalCirculationFlow = RBMK.LastNaturalCirculationFlow or 0,
        lastEffectiveCoreFlow = RBMK.LastEffectiveCoreFlow or 0,
        lastSteamQuality = RBMK.LastSteamQuality or 0,
        lastVoidFraction = RBMK.LastVoidFraction or 0,
        lastWetSteamReturned = RBMK.LastWetSteamReturned or 0,
        lastWetWaterReturned = RBMK.LastWetWaterReturned or 0,
        lastDryoutRisk = RBMK.LastDryoutRisk or 0,
        waterTemperature = RBMK.WaterTemperature or 0,
        steamTemperature = RBMK.SteamTemperature or 0,
        boilingTemperature = RBMK.LastBoilingTemperature or RBMK.WaterBoilingTemperature or 0,
        coolingEfficiency = RBMK.LastCoolingEfficiency or 0,
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
    RBMK.Debug.NetSequence = ((RBMK.Debug.NetSequence or 0) % 65535) + 1
    local sequence = RBMK.Debug.NetSequence
    local state = RBMK.Debug.ClientState or {}
    local cells = state.Cells or {}
    local fluxLines = state.FluxLines or {}

    RBMK.Debug.BroadcastVesselInfo(sequence, state.VesselInfo or {})
    RBMK.Debug.BroadcastCellChunks(sequence, cells)
    RBMK.Debug.BroadcastFluxChunks(sequence, fluxLines)

    startDebugPacket(DEBUG_PACKET_END, sequence)
    net.Broadcast()
end

function RBMK.Debug.BroadcastVesselInfo(sequence, info)
    startDebugPacket(DEBUG_PACKET_VESSEL, sequence)
    writeVector(info.worldOrigin)
    net.WriteFloat(info.cellSpacing or 64)
    writeString(info.model or 'UNKNOWN')
    net.WriteFloat(info.averageHeat or 0)
    net.WriteFloat(info.maxHeat or 0)
    net.WriteFloat(info.totalFlux or 0)
    net.WriteFloat(info.averageXenon or 0)
    net.WriteFloat(info.lastThermalMW or 0)
    net.WriteFloat(info.lastFlashBoilMW or 0)
    net.WriteFloat(info.lastSteamGenerated or 0)
    net.WriteFloat(info.lastFlashSteamGenerated or 0)
    net.WriteBool(info.autoRegulatorEnabled and true or false)
    net.WriteBool(info.autoRegulatorUsePID and true or false)
    net.WriteFloat(info.autoRegulatorTargetMW or 0)
    net.WriteFloat(info.autoRegulatorTargetInsertion or 0)
    net.WriteFloat(info.autoRegulatorLastError or 0)
    writeOptionalString(info.controlRodPowerGrid)
    writeOptionalString(info.controlRodPowerBreaker)
    net.WriteFloat(info.controlRodPowerDemandMW or 0)
    net.WriteFloat(info.controlRodPowerAcceptedMW or 0)
    net.WriteBool(info.controlRodPowered and true or false)
    net.WriteUInt(info.controlRodMovingCount or 0, 16)
    net.WriteUInt(info.controlRodBlockedCount or 0, 16)
    net.WriteUInt(info.controlRodStuckCount or 0, 16)
    net.WriteFloat(info.integrityScore or 1)
    net.WriteFloat(info.integrityDamage or 0)
    net.WriteFloat(info.integrityLastDamage or 0)
    writeOptionalString(info.integrityLastDamageReason)
    writeOptionalString(info.steamSeparator)
    net.WriteFloat(info.lastRecircFlow or 0)
    net.WriteFloat(info.lastNaturalCirculationFlow or 0)
    net.WriteFloat(info.lastEffectiveCoreFlow or 0)
    net.WriteFloat(info.lastSteamQuality or 0)
    net.WriteFloat(info.lastVoidFraction or 0)
    net.WriteFloat(info.lastWetSteamReturned or 0)
    net.WriteFloat(info.lastWetWaterReturned or 0)
    net.WriteFloat(info.lastDryoutRisk or 0)
    net.WriteFloat(info.waterTemperature or 0)
    net.WriteFloat(info.steamTemperature or 0)
    net.WriteFloat(info.boilingTemperature or 0)
    net.WriteFloat(info.coolingEfficiency or 0)
    net.WriteFloat(info.water or 0)
    net.WriteFloat(info.maxWater or 0)
    net.WriteFloat(info.steam or 0)
    net.WriteFloat(info.maxSteam or 0)
    net.WriteFloat(info.hardMaxSteam or 0)
    net.WriteFloat(info.totalVolume or 0)
    net.WriteFloat(info.steamSpace or 0)
    net.WriteFloat(info.minSteamSpace or 0)
    net.WriteFloat(info.rpvPressure or 0)
    writeString(info.pressureUnit or 'bar')
    net.WriteBool(info.steamOutletOpen and true or false)
    net.WriteBool(info.feedwaterInletOpen and true or false)
    net.WriteBool(info.drainValveOpen and true or false)
    net.WriteFloat(info.lastSteamExportFlow or 0)
    net.WriteFloat(info.lastDrainFlow or 0)
    net.WriteFloat(info.blowoutPressure or 0)
    net.WriteFloat(info.catastrophicPressure or 0)
    net.WriteBool(info.eventFailed and true or false)
    writeOptionalString(info.failureReason)
    net.WriteFloat(info.lastBlowoutSteamLoss or 0)
    net.WriteFloat(info.lastBlowoutPressure or 0)
    writeOptionalString(info.lastBlowoutValve)
    net.WriteUInt(info.lastBlowoutCount or 0, 16)
    net.WriteFloat(info.lastBlowoutDuration or 0)
    net.WriteBool(info.blowoutEnabled and true or false)
    net.WriteUInt(info.blowoutValveCount or 0, 16)
    writePoint(info.lastFuelLeak)
    writePoint(info.lastMeltdown)
    net.Broadcast()
end

function RBMK.Debug.WriteCell(cell)
    net.WriteUInt(cell.x or 0, 16)
    net.WriteUInt(cell.y or 0, 16)
    net.WriteUInt(cell.type or RBMK.CELL_VOID, 4)
    net.WriteFloat(cell.heat or 0)

    if cell.type == RBMK.CELL_FUEL then
        writeString(cell.fuelType or 'UNKNOWN')
        net.WriteFloat(cell.skinHeat or 0)
        net.WriteFloat(cell.coreHeat or 0)
        net.WriteFloat(cell.flux or 0)
        net.WriteFloat(cell.lastFlux or 0)
        net.WriteFloat(cell.xenon or 0)
        net.WriteBool(cell.leaking and true or false)
        net.WriteBool(cell.meltingDown and true or false)
    elseif cell.type == RBMK.CELL_CONTROL then
        writeString(cell.name or 'unnamed')
        writeString(cell.group or 'nocolor')
        net.WriteFloat(cell.insertion or 0)
        net.WriteFloat(cell.targetInsertion or 0)
        net.WriteFloat(cell.lastInsertion or 0)
        net.WriteBool(cell.inserting and true or false)
        net.WriteFloat(cell.stationaryTime or 0)
        net.WriteFloat(cell.movingTime or 0)
        net.WriteFloat(cell.moveSpeed or 0)
        net.WriteBool(cell.autoRegulator and true or false)
        net.WriteFloat(cell.autoInsertion or 0)
        net.WriteFloat(cell.autoTargetInsertion or 0)
        net.WriteFloat(cell.autoMaxInsertion or 0)
        net.WriteBool(cell.graphiteTip and true or false)
        net.WriteBool(cell.reflector and true or false)
        net.WriteEntity(IsValid(cell.visualEnt) and cell.visualEnt or NULL)
        net.WriteBool(cell.powerBlocked and true or false)
        net.WriteBool(cell.stuck and true or false)
        net.WriteBool(cell.scramStuck and true or false)
        net.WriteBool(cell.scramStuckPending and true or false)
        net.WriteFloat(cell.stuckInsertion or 0)
        writeOptionalString(cell.lastStuckReason)
    elseif cell.type == RBMK.CELL_REFLECTOR then
        net.WriteBool(cell.reflectorIn and true or false)
    elseif cell.type == RBMK.CELL_SOURCE then
        net.WriteFloat(cell.flux or 0)
        net.WriteFloat(cell.lastFlux or 0)
        net.WriteFloat(cell.sourceStrength or 0)
        net.WriteBool(cell.closedSource and true or false)
    end
end

function RBMK.Debug.BroadcastCellChunks(sequence, cells)
    for startIndex = 1, #cells, DEBUG_CELL_CHUNK_SIZE do
        local endIndex = math.min(startIndex + DEBUG_CELL_CHUNK_SIZE - 1, #cells)
        startDebugPacket(DEBUG_PACKET_CELLS, sequence)
        net.WriteUInt(endIndex - startIndex + 1, 16)
        for i = startIndex, endIndex do
            RBMK.Debug.WriteCell(cells[i])
        end
        net.Broadcast()
    end
end

function RBMK.Debug.WriteFluxLine(line)
    writeVector(line.start)
    writeVector(line.finish)
    net.WriteFloat(line.flux or 0)
    net.WriteInt(line.dx or 0, 4)
    net.WriteInt(line.dy or 0, 4)
end

function RBMK.Debug.BroadcastFluxChunks(sequence, fluxLines)
    for startIndex = 1, #fluxLines, DEBUG_FLUX_CHUNK_SIZE do
        local endIndex = math.min(startIndex + DEBUG_FLUX_CHUNK_SIZE - 1, #fluxLines)
        startDebugPacket(DEBUG_PACKET_FLUX, sequence)
        net.WriteUInt(endIndex - startIndex + 1, 16)
        for i = startIndex, endIndex do
            RBMK.Debug.WriteFluxLine(fluxLines[i])
        end
        net.Broadcast()
    end
end
