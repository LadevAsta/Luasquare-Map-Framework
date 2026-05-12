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
                if fuel then cell.heat = cell.heat + cell.flux * fuel.heatFactor end
            end
        end
    end
end

-- Xenon
function RBMK.DoXenonStep()
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type == RBMK.CELL_FUEL then
                local fuel = RBMK.FuelTypes[cell.fuelType]
                if fuel then
                    local gen = fuel.xenonGen(cell.flux)
                    local burn = fuel.xenonBurn(cell.flux)
                    cell.xenon = cell.xenon * 0.9999
                    cell.xenon = math.max(0, math.Clamp(cell.xenon + gen - burn, 0, 99))
                end
            end
        end
    end
end