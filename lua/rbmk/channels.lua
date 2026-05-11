RBMK = RBMK or {}
RBMK.Rods = RBMK.Rods or {}

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

-- Creates control rod column (insertion, name, group)
function RBMK.CreateControlRod(insertion, name, group)
    insertion = insertion or 1.0
    name = name or 'unnamed'
    group = group or 'nocolor'
    local rod = {
        type = RBMK.CELL_CONTROL,
        heat = 20,
        insertion = insertion,
        targetInsertion = insertion,
        lastInsertion = insertion,
        inserting = 0,
        stationaryTime = 0,
        movingTime = 0,
        moveSpeed = 0.005,
        graphiteTip = true,
        name = name,
        group = group
    }

    RBMK.Rods[name] = rod
    return rod
end

function RBMK.CreateReflector()
    return {
        type = RBMK.CELL_REFLECTOR,
        heat = 20
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