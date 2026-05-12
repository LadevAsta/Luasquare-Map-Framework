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
        heat = 20, -- channel temp
        skinHeat = 20, -- fuel skin temp
        coreHeat = 20, -- fuel core temp
        flux = 0,
        lastFlux = 0,
        xenon = 0
    }
end

function RBMK.CreateSteamChannel()
    return {
        type = RBMK.CELL_STEAM,
        heat = 20,
        coolingRate = 0.05,
        waterUseRate = 0.01
    }
end

-- Creates control rod column (name, group, visualEnt, graphiteTipped, reflectorFunctionality, insertion)
function RBMK.CreateControlRod(name, group, visualEnt, graphiteTip, reflector, insertion)
    insertion = insertion or 1.0
    name = name or 'unnamed'
    group = group or 'nocolor'
    visualEnt = visualEnt
    graphiteTip = graphiteTip or true
    reflector = reflector or false
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
        visualEnt = visualEnt,
        graphiteTip = graphiteTip,
        reflector = reflector,
        name = name,
        group = group
    }

    RBMK.Rods[name] = rod
    return rod
end

function RBMK.CreateReflector(reflectorIn)
    if reflectorIn == nil then reflectorIn = true end
    return {
        type = RBMK.CELL_REFLECTOR,
        reflectorIn = reflectorIn,
        heat = 20
    }
end

function RBMK.CreateAbsorber()
    return {
        type = RBMK.CELL_ABSORBER,
        heat = 20
    }
end

function RBMK.CreateVoid()
    return {
        type = RBMK.CELL_VOID
    }
end

function RBMK.CreateNeutronSource(strength, closedSource)
    closedSource = closedSource or false
    return {
        type = RBMK.CELL_SOURCE,
        heat = 20,
        flux = 0,
        lastFlux = 0,
        sourceStrength = strength or 20,
        closedSource = closedSource --If true, Stop emitting Flux and act as Reflector instead
    }
end