RBMK = RBMK or {}

function RBMK.CreateBlank()
    return {
        type = RBMK.CELL_BLANK,
        heat = 20
    }
end

function RBMK.CreateFuelChannel(fuelType)
    return {
        type = RBMK.CELL_FUEL,
        fuelType = fuelType or 'MEU',
        heat = 20,
        flux = 0,
        lastFlux = 0,
        xenon = 0
    }
end

function RBMK.CreateSteamChannel()
    return {
        type = RBMK.CELL_STEAM,
        heat = 20,
        coolingRate = 1.0
    }
end

function RBMK.CreateNeutronSource(strength)
    return {
        type = RBMK.CELL_SOURCE,
        heat = 20,
        flux = 0,
        lastFlux = 0,
        sourceStrength = strength or 20
    }
end