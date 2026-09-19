return function(RBMK)
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
        heat = 20
    }
end

-- Creates control rod column (name, group, indicatorSpriteEnt, visualEnt, graphiteTipped, reflectorFunctionality, insertion)
function RBMK.CreateControlRod(name, group, indicatorSpriteEnt, visualEnt, graphiteTip, reflector, insertion)
    insertion = insertion or 1.0
    name = name or 'unnamed'
    group = group or 'nocolor'
    visualEnt = visualEnt
    if graphiteTip == nil then graphiteTip = true end
    reflector = reflector or false
    local rod = {
        type = RBMK.CELL_CONTROL,
        heat = 20,
        insertion = insertion,
        targetInsertion = insertion,
        lastInsertion = insertion,
        inserting = false,
        stationaryTime = 0,
        movingTime = 0,
        moveSpeed = 0.005,
        visualEnt = visualEnt,
        graphiteTip = graphiteTip,
        reflector = reflector,
        autoRegulator = false,
        autoInsertion = 0,
        autoTargetInsertion = 0,
        autoMaxInsertion = RBMK.AutoRegulatorMaxInsertion or 0.1,
        name = name,
        group = group
    }

    RBMK.Rods[name] = rod
    if indicatorSpriteEnt ~= nil then RBMK.Selector.RegisterIndicator(name, indicatorSpriteEnt) end
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

-- Layout Utils
function RBMK.FillBlanksWithSteam(opts)
    opts = opts or {}
    local ignoreEdge = opts.ignoreEdge
    local ignoreNearVoid = opts.ignoreNearVoid
    local dirs4 = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
    local function fillCell(x, y)
        local cell = RBMK.GetCell(x, y)
        if not cell or cell.type ~= RBMK.CELL_BLANK then return end
        -- Preserve the reference layout's historical edge selection.
        if ignoreEdge and x == 1 or y == 1 or x == RBMK.Width or y == RBMK.Height then return end
        if ignoreNearVoid then
            for _, dir in ipairs(dirs4) do
                local other = RBMK.GetCell(x + dir[1], y + dir[2])
                if other and other.type == RBMK.CELL_VOID then return end
            end
        end
        RBMK.SetCell(x, y, RBMK.CreateSteamChannel())
    end
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            fillCell(x, y)
        end
    end

    RBMK.RecalculatePools()
end
end
