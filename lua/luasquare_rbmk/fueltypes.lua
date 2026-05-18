RBMK = RBMK or {}
RBMK.FuelTypes = {}

RBMK.FuelTypes.EMPTY = {
    name = 'Empty Fuel',
    yield = 0,
    depletion = 0.0,
    meltingPoint = 6969,
    heatFactor = 0.0,
    diffusion = 0.02,
    fluxFunction = function(x) return x end,
    xenonGen = function(x) return 0 end,
    xenonBurn = function(x) return 1 end
}

RBMK.FuelTypes.MEU = {
    name = 'Medium Enriched Uranium Fuel',
    yield = 100000000,
    depletion = 0.0,
    meltingPoint = 2865,
    heatFactor = 0.65,
    diffusion = 0.02,
    fluxFunction = function(x) return math.log(x + 1, 10) * 0.5 * 20 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 500 end
}

RBMK.FuelTypes.MOX = {
    name = 'Mixed Oxide Fuel',
    yield = 100000000,
    depletion = 0.0,
    meltingPoint = 2815,
    heatFactor = 1.0,
    diffusion = 0.02,
    fluxFunction = function(x) return math.log(x + 1, 10) * 0.5 * 40 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 500 end
}

RBMK.FuelTypes.HEU = {
    name = 'Highly Enriched Uranium Fuel',
    yield = 100000000,
    depletion = 0.0,
    meltingPoint = 2865,
    heatFactor = 1.0,
    diffusion = 0.02,
    fluxFunction = function(x) return math.sqrt(x) * 5 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 500 end
}