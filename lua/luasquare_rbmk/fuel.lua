RBMK = RBMK or {}
-- Fuel Flux Function
function RBMK.MEUFlux(x)
    return math.log(x + 1, 10) * 0.5 * 20
end

function RBMK.MOXFlux(x)
    return math.log(x + 1, 10) * 0.5 * 40
end

function RBMK.HEUFlux(x)
    return math.sqrt(x) * 5
end

-- Fuel Heat Logic
function RBMK.DoFuelHeat()
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type == RBMK.CELL_FUEL then
                local fuel = RBMK.FuelTypes[cell.fuelType]
                local outputFlux = RBMK.GetCellFluxOutput(cell)
                if fuel then cell.coreHeat = cell.coreHeat + outputFlux * fuel.heatFactor end
                -- Unholy internal heat diffusion
                local coreDiff = cell.coreHeat - cell.skinHeat
                local coreTransfer = (coreDiff / 2) * fuel.diffusion
                cell.coreHeat = cell.coreHeat - coreTransfer
                cell.skinHeat = cell.skinHeat + coreTransfer
                local vesselDiff = cell.skinHeat - cell.heat
                local vesselTransfer = vesselDiff / 2
                cell.skinHeat = cell.skinHeat - vesselTransfer
                cell.heat = cell.heat + vesselTransfer
                -- MELT!
                if cell.skinHeat >= fuel.meltingPoint then
                    local pulse = (cell.coreHeat + cell.skinHeat) / 30
                    cell.coreHeat = cell.coreHeat + pulse
                    cell.skinHeat = cell.skinHeat + pulse
                    cell.heat = cell.heat + pulse
                end
            end
        end
    end
end

-- Xenon
function RBMK.DoXenonStep()
    RBMK.AverageXenon = 0
    local xenonSum = 0
    local fuelrodCount = 0
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type == RBMK.CELL_FUEL then
                local fuel = RBMK.FuelTypes[cell.fuelType]
                if fuel and fuel ~= RBMK.FuelTypes.EMPTY then
                    local gen = fuel.xenonGen(cell.flux)
                    local burn = fuel.xenonBurn(cell.flux)
                    cell.xenon = cell.xenon * 0.9999
                    cell.xenon = math.max(0, math.Clamp(cell.xenon + gen - burn, 0, 99))
                    fuelrodCount = fuelrodCount + 1
                    xenonSum = xenonSum + cell.xenon
                end
            end
        end
    end
    RBMK.AverageXenon = xenonSum / fuelrodCount
end