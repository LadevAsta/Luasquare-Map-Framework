RBMK = RBMK or {}

function RBMK.MixTemperature(currentAmount, currentTemperature, addedAmount, addedTemperature)
    currentAmount = math.max(tonumber(currentAmount) or 0, 0)
    addedAmount = math.max(tonumber(addedAmount) or 0, 0)
    currentTemperature = tonumber(currentTemperature) or 20
    addedTemperature = tonumber(addedTemperature) or currentTemperature
    local total = currentAmount + addedAmount
    if total <= 0 then return currentTemperature end
    return (currentTemperature * currentAmount + addedTemperature * addedAmount) / total
end

function RBMK.GetWaterFraction()
    if RBMK.MaxWater <= 0 then return 0 end
    return math.Clamp((RBMK.Water or 0) / RBMK.MaxWater, 0, 1)
end

function RBMK.GetCoolingEfficiency()
    local fraction = RBMK.GetWaterFraction()
    local lowFraction = RBMK.CoolingLowWaterFraction or 0.1
    local optimalFraction = RBMK.CoolingOptimalWaterFraction or 0.8
    if fraction >= optimalFraction then return 1 end
    if fraction <= 0 then return RBMK.CoolingDryEfficiency or 0.02 end
    if fraction <= lowFraction then
        return Lerp(fraction / math.max(lowFraction, 0.0001), RBMK.CoolingDryEfficiency or 0.02, RBMK.CoolingLowEfficiency or 0.08)
    end

    local range = math.max(optimalFraction - lowFraction, 0.0001)
    return Lerp((fraction - lowFraction) / range, RBMK.CoolingLowEfficiency or 0.08, 1)
end

function RBMK.GetBoilingTemperature()
    local pressure = RBMK.RPVPressure or 0
    RBMK.WaterBoilingTemperature = (RBMK.WaterBoilingTemperatureBase or 100) + pressure * (RBMK.WaterBoilingPressureFactor or 0)
    return RBMK.WaterBoilingTemperature
end

function RBMK.DoFlashBoilStep()
    if RBMK.Water <= 0 then return 0 end
    if RBMK.GetWaterFraction() > (RBMK.CoolingLowWaterFraction or 0.1) then return 0 end
    RBMK.UpdateRPVPressure()
    local boilingTemperature = RBMK.GetBoilingTemperature()
    if (RBMK.WaterTemperature or 20) <= boilingTemperature then return 0 end

    local excessKJ = (RBMK.WaterTemperature - boilingTemperature) * RBMK.WaterSpecificHeatKJPerL * RBMK.Water
    local waterWanted = excessKJ / RBMK.WaterLatentHeatKJPerL
    local freeSteam = math.max(RBMK.HardMaxSteam - RBMK.Steam, 0)
    local maxWaterBySteamSpace = freeSteam / (RBMK.SteamExpansionRatio or 1600)
    local waterUsed = math.min(waterWanted, RBMK.Water, maxWaterBySteamSpace)
    if waterUsed <= 0 then return 0 end

    local usedKJ = waterUsed * RBMK.WaterLatentHeatKJPerL
    local steamMade = waterUsed * (RBMK.SteamExpansionRatio or 1600)
    RBMK.Water = RBMK.Water - waterUsed
    RBMK.WaterTemperature = boilingTemperature
    RBMK.SteamTemperature = RBMK.MixTemperature(RBMK.Steam, RBMK.SteamTemperature, steamMade, boilingTemperature)
    RBMK.Steam = RBMK.Steam + steamMade
    RBMK.LastFlashSteamGenerated = (RBMK.LastFlashSteamGenerated or 0) + steamMade
    RBMK.UpdateRPVPressure()
    RBMK.LastBoilingTemperature = RBMK.GetBoilingTemperature()
    return usedKJ
end

function RBMK.DoSteamStep()
    RBMK.LastSteamGenerated = 0
    RBMK.LastFlashSteamGenerated = 0
    local flashKJ = RBMK.DoFlashBoilStep()
    local thermalKJ = 0
    RBMK.UpdateRPVPressure()
    local coolingEfficiency = RBMK.GetCoolingEfficiency()
    local boilingTemperature = RBMK.GetBoilingTemperature()
    RBMK.LastCoolingEfficiency = coolingEfficiency
    RBMK.LastBoilingTemperature = boilingTemperature
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type ~= RBMK.CELL_STEAM then continue end
            if cell.heat <= RBMK.WaterTemperature and cell.heat <= RBMK.SteamTemperature then continue end

            local thermalMass = cell.thermalMassKJPerC or RBMK.ChannelThermalMassKJPerC
            local transferFactor = cell.heatTransfer or RBMK.ChannelBoilingHeatTransfer
            local heatSinkTemperature = RBMK.Water > 0 and RBMK.WaterTemperature or RBMK.SteamTemperature
            local availableKJ = math.max(cell.heat - heatSinkTemperature, 0) * thermalMass * transferFactor * coolingEfficiency
            if availableKJ <= 0 then continue end

            local usedKJ = 0
            if RBMK.Water > 0 then
                local heatToBoiling = math.max(boilingTemperature - (RBMK.WaterTemperature or 20), 0) *
                    RBMK.WaterSpecificHeatKJPerL * RBMK.Water
                local waterHeatKJ = math.min(availableKJ, heatToBoiling)
                if waterHeatKJ > 0 then
                    RBMK.WaterTemperature = RBMK.WaterTemperature + waterHeatKJ / math.max(RBMK.Water * RBMK.WaterSpecificHeatKJPerL, 0.0001)
                    availableKJ = availableKJ - waterHeatKJ
                    usedKJ = usedKJ + waterHeatKJ
                end

                if availableKJ > 0 and RBMK.WaterTemperature >= boilingTemperature - 0.001 then
                    local waterWanted = availableKJ / RBMK.WaterLatentHeatKJPerL
                    local waterUsed = math.min(waterWanted, RBMK.Water)
                    local freeSteam = math.max(RBMK.HardMaxSteam - RBMK.Steam, 0)
                    local maxWaterBySteamSpace = freeSteam / (RBMK.SteamExpansionRatio or 1600)
                    waterUsed = math.min(waterUsed, maxWaterBySteamSpace)

                    if waterUsed > 0 then
                        local vaporKJ = waterUsed * RBMK.WaterLatentHeatKJPerL
                        local steamMade = waterUsed * (RBMK.SteamExpansionRatio or 1600)
                        RBMK.Water = RBMK.Water - waterUsed
                        RBMK.SteamTemperature = RBMK.MixTemperature(RBMK.Steam, RBMK.SteamTemperature, steamMade, boilingTemperature)
                        RBMK.Steam = RBMK.Steam + steamMade
                        RBMK.LastSteamGenerated = RBMK.LastSteamGenerated + steamMade
                        availableKJ = availableKJ - vaporKJ
                        usedKJ = usedKJ + vaporKJ
                    end
                end
            elseif RBMK.Steam > 0 then
                local steamHeatKJ = math.min(availableKJ, RBMK.Steam * (RBMK.SteamSpecificHeatKJPerUnitC or 0.002) * 500)
                RBMK.SteamTemperature = RBMK.SteamTemperature + steamHeatKJ / math.max(RBMK.Steam * (RBMK.SteamSpecificHeatKJPerUnitC or 0.002), 0.0001)
                usedKJ = usedKJ + steamHeatKJ
            end

            if usedKJ <= 0 then continue end
            cell.heat = cell.heat - (usedKJ / thermalMass)
            thermalKJ = thermalKJ + usedKJ
            RBMK.UpdateRPVPressure()
            boilingTemperature = RBMK.GetBoilingTemperature()
            RBMK.LastBoilingTemperature = boilingTemperature
        end
    end

    flashKJ = flashKJ + RBMK.DoFlashBoilStep()
    RBMK.LastThermalMW = (thermalKJ / math.max(RBMK.TickInterval, 0.0001)) / 1000
    RBMK.LastFlashBoilMW = (flashKJ / math.max(RBMK.TickInterval, 0.0001)) / 1000
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
    local referenceK = (RBMK.SteamReferenceTemperature or 100) + 273.15
    local steamK = math.max((RBMK.SteamTemperature or RBMK.SteamReferenceTemperature or 100) + 273.15, 1)
    return RBMK.GetSteamSpace() * math.max(tonumber(pressure) or 0, 0) /
        math.max(RBMK.SteamPressureFactor, 0.0001) * (referenceK / steamK)
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
    local referenceK = (RBMK.SteamReferenceTemperature or 100) + 273.15
    local steamK = math.max((RBMK.SteamTemperature or RBMK.SteamReferenceTemperature or 100) + 273.15, 1)
    RBMK.RPVPressure = math.max(RBMK.Steam / RBMK.SteamSpace, 0) * RBMK.SteamPressureFactor * (steamK / referenceK)
    return RBMK.RPVPressure
end

function RBMK.SetSteamNetwork(name)
    RBMK.SteamNetwork = name
end

function RBMK.AddWaterFromPump(amount, pressure, temperature)
    amount = math.max(tonumber(amount) or 0, 0)
    pressure = tonumber(pressure) or 0
    if not RBMK.FeedwaterInletOpen then return 0 end
    if pressure <= RBMK.GetRPVPressure() then return 0 end

    local freeWater = RBMK.MaxWater - RBMK.Water
    local moved = math.min(amount, math.max(freeWater, 0))
    RBMK.WaterTemperature = RBMK.MixTemperature(RBMK.Water, RBMK.WaterTemperature, moved, temperature or RBMK.WaterTemperature)
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

    local ratedPressureDelta = RBMK.SteamOutletRatedPressureDelta or RBMK.RPVMaxPressure
    local scale = math.Clamp(pressureDelta / math.max(ratedPressureDelta, 0.0001), 0, 1)
    local exportRate = math.max(RBMK.SteamSpace * 0.05, RBMK.Steam * RBMK.SteamOutletFlowRate)
    local requested = exportRate * scale * RBMK.TickInterval
    local moved = math.min(requested, RBMK.Steam)
    local accepted = LUASQUARE_FLUID.AddFluid(RBMK.SteamNetwork, moved, RBMK.SteamTemperature)
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
        local accepted = LUASQUARE_FLUID.AddFluid(RBMK.DrainNetwork, drained, RBMK.WaterTemperature)
        RBMK.Water = RBMK.Water - accepted
        RBMK.LastDrainFlow = accepted / math.max(RBMK.TickInterval, 0.0001)
    else
        RBMK.Water = RBMK.Water - drained
        RBMK.LastDrainFlow = drained / math.max(RBMK.TickInterval, 0.0001)
    end

    RBMK.UpdateRPVPressure()
end
