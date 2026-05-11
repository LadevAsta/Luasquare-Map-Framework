RBMK = RBMK or {}

RBMK.FuelTypes = {}

RBMK.FuelTypes.EMPTY = {
    name = 'Empty Fuel',
    meltingPoint = 3000,
    heatFactor = 0.0,
    fluxFunction = function(x) return x end,
    xenonGen = function(x) return 0 end,
    xenonBurn = function(x) return 1 end
}

RBMK.FuelTypes.MEU = {
    name = 'Medium Enriched Uranium Fuel',
    meltingPoint = 2865,
    heatFactor = 0.65,
    fluxFunction = function(x) return math.log(x + 1, 10) * 0.5 * 20 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 50 end
}

RBMK.FuelTypes.MOX = {
    name = 'Mixed Oxide Fuel',
    meltingPoint = 2815,
    heatFactor = 1.0,
    fluxFunction = function(x) return math.log(x + 1, 10) * 0.5 * 40 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 50 end
}

RBMK.FuelTypes.HEU = {
    name = 'Highly Enriched Uranium Fuel',
    meltingPoint = 2865,
    heatFactor = 1.0,
    fluxFunction = function(x) return math.sqrt(x) * 5 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 50 end
}