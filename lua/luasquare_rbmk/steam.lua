RBMK = RBMK or {}

function RBMK.DoSteamStep()
    local thermalKJ = 0
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type ~= RBMK.CELL_STEAM then continue end
            if cell.heat <= 100 then continue end
            if RBMK.Water <= 0 then continue end

            RBMK.UpdateRPVPressure()
            local thermalMass = cell.thermalMassKJPerC or RBMK.ChannelThermalMassKJPerC
            local transferFactor = cell.heatTransfer or RBMK.ChannelBoilingHeatTransfer
            local availableKJ = (cell.heat - RBMK.WaterBoilingTemperature) * thermalMass * transferFactor
            if availableKJ <= 0 then continue end

            local heatToBoiling = math.max(RBMK.WaterBoilingTemperature - (RBMK.WaterTemperature or 20), 0) * RBMK.WaterSpecificHeatKJPerL
            local kjPerLiter = heatToBoiling + RBMK.WaterLatentHeatKJPerL
            if kjPerLiter <= 0 then continue end

            local waterWanted = availableKJ / kjPerLiter
            local waterUsed = math.min(waterWanted, RBMK.Water)
            local freeSteam = math.max(RBMK.HardMaxSteam - RBMK.Steam, 0)
            local maxWaterBySteamSpace = freeSteam / (RBMK.SteamExpansionRatio or 1600)
            waterUsed = math.min(waterUsed, maxWaterBySteamSpace)
            if waterUsed <= 0 then continue end

            local usedKJ = waterUsed * kjPerLiter
            local cooling = usedKJ / thermalMass
            local steamMade = waterUsed * (RBMK.SteamExpansionRatio or 1600)
            if steamMade > freeSteam then
                steamMade = freeSteam
                waterUsed = steamMade / (RBMK.SteamExpansionRatio or 1600)
                usedKJ = waterUsed * kjPerLiter
                cooling = usedKJ / thermalMass
            end

            cell.heat = cell.heat - cooling
            RBMK.Water = RBMK.Water - waterUsed
            RBMK.WaterTemperature = RBMK.WaterBoilingTemperature
            RBMK.Steam = RBMK.Steam + steamMade
            thermalKJ = thermalKJ + usedKJ
            RBMK.UpdateRPVPressure()
        end
    end

    RBMK.LastThermalMW = (thermalKJ / math.max(RBMK.TickInterval, 0.0001)) / 1000
end

function RBMK.RecalculatePools()
    local steamChannels = 0
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type == RBMK.CELL_STEAM then steamChannels = steamChannels + 1 end
        end
    end

    RBMK.TotalVolume = steamChannels * RBMK.ColumnVolume
    RBMK.MinSteamSpace = RBMK.TotalVolume * RBMK.RPVMinSteamSpaceFraction
    RBMK.MaxWater = math.max(RBMK.TotalVolume - RBMK.MinSteamSpace, 0)
    RBMK.Water = math.Clamp(RBMK.Water, 0, RBMK.MaxWater)
    RBMK.UpdateRPVPressure()
end

function RBMK.AddInitialWater(percent)
    local factor = math.Clamp(percent,0,100) / 100
    RBMK.Water = RBMK.MaxWater * factor
    RBMK.UpdateRPVPressure()
end

function RBMK.GetRPVPressure()
    return RBMK.RPVPressure or 0
end

function RBMK.GetSteamSpace()
    if RBMK.TotalVolume <= 0 then return 0 end
    return math.max(RBMK.TotalVolume - RBMK.Water, RBMK.MinSteamSpace)
end

function RBMK.GetSteamCapacityAtPressure(pressure)
    return RBMK.GetSteamSpace() * math.max(tonumber(pressure) or 0, 0) / math.max(RBMK.SteamPressureFactor, 0.0001)
end

function RBMK.UpdateRPVPressure()
    RBMK.SteamSpace = RBMK.GetSteamSpace()
    if RBMK.SteamSpace <= 0 then
        RBMK.RPVPressure = 0
        RBMK.MaxSteam = 0
        RBMK.HardMaxSteam = 0
        return RBMK.RPVPressure
    end

    RBMK.MaxSteam = RBMK.GetSteamCapacityAtPressure(RBMK.RPVMaxPressure)
    RBMK.HardMaxSteam = RBMK.GetSteamCapacityAtPressure(RBMK.RPVHardPressure)
    RBMK.RPVPressure = math.max(RBMK.Steam / RBMK.SteamSpace, 0) * RBMK.SteamPressureFactor
    return RBMK.RPVPressure
end

function RBMK.SetSteamNetwork(name)
    RBMK.SteamNetwork = name
end

function RBMK.AddWaterFromPump(amount, pressure)
    amount = math.max(tonumber(amount) or 0, 0)
    pressure = tonumber(pressure) or 0
    if not RBMK.FeedwaterInletOpen then return 0 end
    if pressure <= RBMK.GetRPVPressure() then return 0 end

    local freeWater = RBMK.MaxWater - RBMK.Water
    local moved = math.min(amount, math.max(freeWater, 0))
    RBMK.Water = RBMK.Water + moved
    RBMK.UpdateRPVPressure()
    return moved
end

function RBMK.DoSteamExportStep()
    if not RBMK.SteamOutletOpen or not LUASQUARE_FLUID or not RBMK.SteamNetwork then
        RBMK.LastSteamExportFlow = 0
        RBMK.UpdateRPVPressure()
        return
    end

    local network = LUASQUARE_FLUID.GetNetwork(RBMK.SteamNetwork)
    if not network then
        RBMK.LastSteamExportFlow = 0
        RBMK.UpdateRPVPressure()
        return
    end

    local rpvPressure = RBMK.UpdateRPVPressure()
    local networkPressure = network.pressure or 0
    local pressureDelta = rpvPressure - networkPressure
    if pressureDelta <= 0 then
        RBMK.LastSteamExportFlow = 0
        return
    end

    local scale = math.Clamp(pressureDelta / math.max(RBMK.RPVMaxPressure, 0.0001), 0, 1)
    local exportRate = math.max(RBMK.SteamSpace * 0.05, RBMK.Steam * RBMK.SteamOutletFlowRate)
    local requested = exportRate * scale * RBMK.TickInterval
    local moved = math.min(requested, RBMK.Steam)
    local accepted = LUASQUARE_FLUID.AddFluid(RBMK.SteamNetwork, moved)
    RBMK.Steam = RBMK.Steam - accepted
    RBMK.LastSteamExportFlow = accepted / math.max(RBMK.TickInterval, 0.0001)
    RBMK.UpdateRPVPressure()
end

function RBMK.SetSteamOutletOpen(open)
    RBMK.SteamOutletOpen = open and true or false
end

function RBMK.SetFeedwaterInletOpen(open)
    RBMK.FeedwaterInletOpen = open and true or false
end

function RBMK.SetDrainValveOpen(open)
    RBMK.DrainValveOpen = open and true or false
end

function RBMK.SetDrainNetwork(name)
    RBMK.DrainNetwork = name
end

function RBMK.DoDrainStep()
    if not RBMK.DrainValveOpen then
        RBMK.LastDrainFlow = 0
        return
    end

    local requested = RBMK.DrainFlowRate * RBMK.TickInterval
    local drained = math.min(requested, RBMK.Water)
    if drained <= 0 then
        RBMK.LastDrainFlow = 0
        return
    end

    if LUASQUARE_FLUID and RBMK.DrainNetwork then
        local accepted = LUASQUARE_FLUID.AddFluid(RBMK.DrainNetwork, drained)
        RBMK.Water = RBMK.Water - accepted
        RBMK.LastDrainFlow = accepted / math.max(RBMK.TickInterval, 0.0001)
    else
        RBMK.Water = RBMK.Water - drained
        RBMK.LastDrainFlow = drained / math.max(RBMK.TickInterval, 0.0001)
    end

    RBMK.UpdateRPVPressure()
end
