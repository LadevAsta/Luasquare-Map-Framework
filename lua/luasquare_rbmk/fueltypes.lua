RBMK = RBMK or {}
RBMK.FuelTypes = {}

RBMK.FuelTypes.EMPTY = {
    name = 'Empty Fuel',
    description = 'you are not supposed to see this',
    yield = 0,
    depletion = 0.0,
    meltingPoint = 6969,
    heatFactor = 0.0,
    diffusion = 0.02,
    fuelClass = 'NONE',
    fluxFunction = function(x) return x end,
    xenonGen = function(x) return 0 end,
    xenonBurn = function(x) return 1 end
}

RBMK.FuelTypes.MEU = {
    name = 'Medium Enriched Uranium Fuel',
    description = '20% U-235 fuel assembly, Reactor-Grade.',
    yield = 100000000,
    depletion = 0.0,
    meltingPoint = 2865,
    heatFactor = 0.65,
    diffusion = 0.02,
    fuelClass = 'SAFE / Square-Root',
    fluxFunction = function(x) return math.log(x + 1, 10) * 0.5 * 20 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 500 end
}

RBMK.FuelTypes.MOX = {
    name = 'Mixed Oxide Fuel',
    description = 'Contains both Plutonium and Uranium oxide.',
    yield = 100000000,
    depletion = 0.0,
    meltingPoint = 2815,
    heatFactor = 1.0,
    diffusion = 0.02,
    fuelClass = 'MODERATE / Square-Root',
    fluxFunction = function(x) return math.log(x + 1, 10) * 0.5 * 40 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 500 end
}

RBMK.FuelTypes.HEU = {
    name = 'Highly Enriched Uranium Fuel',
    description = '80% U-235 fuel assembly, Reactor-Grade.',
    yield = 100000000,
    depletion = 0.0,
    meltingPoint = 2865,
    heatFactor = 1.0,
    diffusion = 0.02,
    fuelClass = 'MODERATE / Square-Root',
    fluxFunction = function(x) return math.sqrt(x) * 5 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 500 end
}

RBMK.FuelTypes.WGU = {
    name = 'Weapon-Grade Uranium',
    description = '>90% U-235 fuel assembly...? Weapon-Grade.',
    yield = 100000000,
    depletion = 0.0,
    meltingPoint = 2865,
    heatFactor = 1.25,
    diffusion = 0.02,
    fuelClass = 'CAUTION / Square-Root',
    fluxFunction = function(x) return math.sqrt(x) * 8 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 500 end
}

RBMK.FuelTypes.XEN = {
    name = 'Fissile Xen Crystals',
    description = 'Highly compressed augmented Xen Crystals. Capable of Nuclear Fissile within cheap conventional Nuclear Reactors.',
    yield = 100000000,
    depletion = 0.0,
    meltingPoint = 4242,
    heatFactor = 1.33,
    diffusion = 0.02,
    fuelClass = 'DANGEROUS / Linear',
    fluxFunction = function(x) return 30 + (x * (4 / 5)) end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 500 end
}

RBMK.FuelTypes.YME = {
    name = 'Yaemikium-837 Experimental Fuel',
    description = 'Yae Miko is not related to the production of these extremely powerful anomalous fuel that shouldnt ever be used in the first place.',
    yield = 100000000,
    depletion = 0.0,
    meltingPoint = 2995,
    heatFactor = 1.5,
    diffusion = 0.02,
    fuelClass = 'DANGEROUS / Square-Root',
    fluxFunction = function(x) return math.sqrt(x) * 20 end,
    xenonGen = function(x) return x * 0.05 end,
    xenonBurn = function(x) return (x * x) / 500 end
}

RBMK.FuelTypes.YMX = {
    name = 'Yaemikium-837-Xtreme Reactor Destroyer',
    description = 'YME-837 fuel with added 99% fried tofu additives(4.4 Tonnes). Do not use in power reactors. Use it in some shrine instead.',
    yield = 100000000,
    depletion = 0.0,
    meltingPoint = 6780,
    heatFactor = 1.88,
    diffusion = 0.02,
    fuelClass = 'DISASTER / CHAOS-QUADRATIC',
    fluxFunction = function(x) return 16 + (x * x) / math.random(10, 25) end,
    xenonGen = function(x) return 0 end,
    xenonBurn = function(x) return 1 end
}
