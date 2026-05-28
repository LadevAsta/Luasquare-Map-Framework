if LUASQUARE_DIESELGENERATOR_CORE_LOADED then return end
LUASQUARE_DIESELGENERATOR_CORE_LOADED = true
LUASQUARE_DIESELGENERATOR = LUASQUARE_DIESELGENERATOR or {}
LUASQUARE_DIESELGENERATOR.Generators = LUASQUARE_DIESELGENERATOR.Generators or {}
LUASQUARE_DIESELGENERATOR.TickInterval = LUASQUARE_DIESELGENERATOR.TickInterval or 0.1

function LUASQUARE_DIESELGENERATOR.RegisterDieselGenerator(name, data)
    data = data or {}
    local generatorName = data.generator or data.generatorName or (name .. '_generator')
    local ratedMW = tonumber(data.ratedMW) or tonumber(data.maxMW) or 1
    local maxMW = tonumber(data.maxMW) or ratedMW

    LUASQUARE_DIESELGENERATOR.Generators[name] = {
        name = name,
        generator = generatorName,
        fuelNetwork = data.fuelNetwork or data.fuelSource,
        fuelTankCapacity = tonumber(data.fuelTankCapacity) or 100,
        fuelTankAmount = math.Clamp(tonumber(data.fuelTankAmount) or 0, 0, tonumber(data.fuelTankCapacity) or 100),
        refuelRate = tonumber(data.refuelRate) or 5,
        fuelConsumptionPerMWSecond = tonumber(data.fuelConsumptionPerMWSecond) or 0.01,
        idleFuelRate = tonumber(data.idleFuelRate) or 0,
        enabled = data.enabled and true or false,
        targetMW = tonumber(data.targetMW) or 0,
        ratedMW = ratedMW,
        maxMW = maxMW,
        lastFuelDraw = 0,
        lastFuelUsed = 0,
        lastAvailableMW = 0,
        lastTargetMW = 0,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }

    if LUASQUARE_POWERGENERATOR and not LUASQUARE_POWERGENERATOR.GetGenerator(generatorName) then
        LUASQUARE_POWERGENERATOR.RegisterGenerator(generatorName, {
            type = 'static',
            grid = data.grid,
            breaker = data.breaker or data.powerBreaker or (generatorName .. '_breaker'),
            ratedMW = ratedMW,
            maxMW = maxMW,
            outputMW = 0,
            targetMW = 0,
            rampRateMW = tonumber(data.rampRateMW) or maxMW,
            autoStart = data.autoStart and true or false,
            enabled = data.enabled and true or false,
            closed = data.closed or data.breakerClosed,
            monitorPos = data.generatorMonitorPos or data.monitorPos,
            monitorTarget = data.generatorMonitorTarget,
            monitorOffset = data.generatorMonitorOffset or data.monitorOffset,
            breakerMonitorPos = data.breakerMonitorPos or data.monitorPos,
            breakerMonitorTarget = data.breakerMonitorTarget,
            breakerMonitorOffset = data.breakerMonitorOffset or data.monitorOffset
        })
    end
end

function LUASQUARE_DIESELGENERATOR.GetDieselGenerator(name)
    return LUASQUARE_DIESELGENERATOR.Generators[name]
end

function LUASQUARE_DIESELGENERATOR.SetEnabled(name, enabled)
    local diesel = LUASQUARE_DIESELGENERATOR.GetDieselGenerator(name)
    if not diesel then
        print('[LUASQUARE_DIESELGENERATOR] Unknown diesel generator: ' .. tostring(name))
        return false
    end

    diesel.enabled = enabled and true or false
    local generator = LUASQUARE_POWERGENERATOR and LUASQUARE_POWERGENERATOR.GetGenerator(diesel.generator)
    if generator then generator.enabled = diesel.enabled end
    return true
end

function LUASQUARE_DIESELGENERATOR.SetTargetMW(name, mw)
    local diesel = LUASQUARE_DIESELGENERATOR.GetDieselGenerator(name)
    if not diesel then
        print('[LUASQUARE_DIESELGENERATOR] Unknown diesel generator: ' .. tostring(name))
        return false
    end

    diesel.targetMW = math.Clamp(tonumber(mw) or 0, 0, diesel.maxMW or 0)
    return true
end

function LUASQUARE_DIESELGENERATOR.Refuel(diesel, dt)
    diesel.lastFuelDraw = 0
    if not LUASQUARE_FLUID or not diesel.fuelNetwork then return end
    local free = math.max((diesel.fuelTankCapacity or 0) - (diesel.fuelTankAmount or 0), 0)
    if free <= 0 then return end

    local requested = math.min(free, (diesel.refuelRate or 0) * dt)
    local moved = LUASQUARE_FLUID.RemoveFluid(diesel.fuelNetwork, requested)
    diesel.fuelTankAmount = math.min((diesel.fuelTankAmount or 0) + moved, diesel.fuelTankCapacity or 0)
    diesel.lastFuelDraw = moved / math.max(dt, 0.0001)
end

function LUASQUARE_DIESELGENERATOR.UpdateDieselGenerator(name, dt)
    local diesel = LUASQUARE_DIESELGENERATOR.GetDieselGenerator(name)
    if not diesel then return end

    LUASQUARE_DIESELGENERATOR.Refuel(diesel, dt)
    diesel.lastFuelUsed = 0
    diesel.lastAvailableMW = 0
    diesel.lastTargetMW = 0

    local generator = LUASQUARE_POWERGENERATOR and LUASQUARE_POWERGENERATOR.GetGenerator(diesel.generator)
    if not generator then return end
    generator.enabled = diesel.enabled
    if not diesel.enabled or generator.tripped then
        generator.targetMW = 0
        return
    end

    local fuelRate = math.max(diesel.fuelConsumptionPerMWSecond or 0, 0)
    local requestedMW = math.Clamp(diesel.targetMW or 0, 0, diesel.maxMW or 0)
    local fuelNeeded = ((diesel.idleFuelRate or 0) + requestedMW * fuelRate) * dt
    local availableFuel = diesel.fuelTankAmount or 0
    local availableMW = requestedMW
    if fuelNeeded > availableFuel then
        local fuelForLoad = math.max(availableFuel - (diesel.idleFuelRate or 0) * dt, 0)
        availableMW = fuelRate > 0 and math.min(requestedMW, fuelForLoad / math.max(fuelRate * dt, 0.0001)) or requestedMW
        fuelNeeded = availableFuel
    end

    diesel.fuelTankAmount = math.max(availableFuel - fuelNeeded, 0)
    diesel.lastFuelUsed = fuelNeeded / math.max(dt, 0.0001)
    diesel.lastAvailableMW = availableMW
    diesel.lastTargetMW = requestedMW
    generator.targetMW = availableMW
end

function LUASQUARE_DIESELGENERATOR.UpdateAll()
    local dt = LUASQUARE_DIESELGENERATOR.TickInterval
    for name, _ in pairs(LUASQUARE_DIESELGENERATOR.Generators) do
        LUASQUARE_DIESELGENERATOR.UpdateDieselGenerator(name, dt)
    end
end

function LUASQUARE_DIESELGENERATOR.Start()
    if timer.Exists('LUASQUARE_DIESELGENERATOR_UpdateTimer') then timer.Remove('LUASQUARE_DIESELGENERATOR_UpdateTimer') end
    timer.Create('LUASQUARE_DIESELGENERATOR_UpdateTimer', LUASQUARE_DIESELGENERATOR.TickInterval, 0, function() LUASQUARE_DIESELGENERATOR.UpdateAll() end)
    print('[LUASQUARE_DIESELGENERATOR] Started')
end

print('[LUASQUARE_DIESELGENERATOR] Loaded')
