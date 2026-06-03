if LUASQUARE_POWERGRID_CORE_LOADED then return end
LUASQUARE_POWERGRID_CORE_LOADED = true
LUASQUARE_POWERGRID = LUASQUARE_POWERGRID or {}
LUASQUARE_POWERGRID.Grids = LUASQUARE_POWERGRID.Grids or {}
LUASQUARE_POWERGRID.Breakers = LUASQUARE_POWERGRID.Breakers or {}
LUASQUARE_POWERGRID.Transformers = LUASQUARE_POWERGRID.Transformers or {}
LUASQUARE_POWERGRID.TickInterval = LUASQUARE_POWERGRID.TickInterval or 0.1

local DEFAULT_MAX_MW = 1000000000

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_POWERGRID.RegisterGrid(name, data)
    data = data or {}
    local gridType = data.type or 'onsite'
    local nominalFrequency = tonumber(data.nominalFrequency) or 60
    local sourceCapacityMW = tonumber(data.sourceCapacityMW) or tonumber(data.maxImportMW) or 0
    local stiff = data.stiff
    if stiff == nil then stiff = gridType == 'offsite' end

    LUASQUARE_POWERGRID.Grids[name] = {
        name = name,
        type = gridType,
        enabled = data.enabled ~= false,
        tripped = data.tripped and true or false,
        stiff = stiff and true or false,
        nominalFrequency = nominalFrequency,
        frequency = tonumber(data.frequency) or (data.enabled == false and 0 or nominalFrequency),
        voltage = tonumber(data.voltage) or 0,
        phase = tonumber(data.phase) or 0,
        sourceCapacityMW = sourceCapacityMW,
        baseGenerationMW = tonumber(data.baseGenerationMW) or 0,
        baseLoadMW = tonumber(data.baseLoadMW) or 0,
        demandMW = tonumber(data.demandMW) or tonumber(data.targetDemandMW) or 0,
        currentDemandMW = tonumber(data.currentDemandMW) or tonumber(data.demandMW) or tonumber(data.targetDemandMW) or 0,
        minDemandMW = tonumber(data.minDemandMW) or 0,
        maxDemandMW = tonumber(data.maxDemandMW) or DEFAULT_MAX_MW,
        demandRampMWPerSecond = tonumber(data.demandRampMWPerSecond) or DEFAULT_MAX_MW,
        batteryCapacityMWh = tonumber(data.batteryCapacityMWh) or 0,
        batteryMWh = math.Clamp(tonumber(data.batteryMWh) or tonumber(data.batteryCapacityMWh) or 0, 0, tonumber(data.batteryCapacityMWh) or 0),
        batteryMaxDischargeMW = tonumber(data.batteryMaxDischargeMW) or 0,
        batteryMaxChargeMW = tonumber(data.batteryMaxChargeMW) or 0,
        batteryChargeEfficiency = math.Clamp(tonumber(data.batteryChargeEfficiency) or 0.92, 0.0001, 1),
        batteryDischargeEfficiency = math.Clamp(tonumber(data.batteryDischargeEfficiency) or 0.92, 0.0001, 1),
        batteryTripOnEmpty = data.batteryTripOnEmpty and true or false,
        batteryLastMW = 0,
        batteryChargeFraction = 0,
        inertia = tonumber(data.inertia) or 4,
        droopHz = tonumber(data.droopHz) or 1.5,
        underFrequencyTrip = tonumber(data.underFrequencyTrip) or 54,
        overFrequencyTrip = tonumber(data.overFrequencyTrip) or 66,
        overloadTripFraction = tonumber(data.overloadTripFraction) or 1.0,
        overloadTripHardFraction = tonumber(data.overloadTripHardFraction) or 1.5,
        tripDelay = tonumber(data.tripDelay) or 30,
        overloadTimer = 0,
        underFrequencyTimer = 0,
        pendingGenerationMW = 0,
        pendingLoadMW = 0,
        availableImportMW = 0,
        lastGenerationMW = 0,
        lastLoadMW = 0,
        lastImportMW = 0,
        lastAvailableMW = 0,
        lastBalanceMW = 0,
        energized = data.enabled ~= false and (gridType == 'offsite' or sourceCapacityMW > 0 or (tonumber(data.baseGenerationMW) or 0) > 0),
        tripReason = nil,
        tripRelay = data.tripRelay,
        resetRelay = data.resetRelay,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
end

function LUASQUARE_POWERGRID.RegisterBreaker(name, data)
    data = data or {}
    LUASQUARE_POWERGRID.Breakers[name] = {
        name = name,
        grid = data.grid,
        owner = data.owner,
        kind = data.kind or 'generic',
        closed = data.closed and true or false,
        tripped = data.tripped and true or false,
        maxMW = tonumber(data.maxMW) or DEFAULT_MAX_MW,
        demandMW = math.max(tonumber(data.demandMW) or tonumber(data.loadMW) or 0, 0),
        lastDemandAcceptedMW = 0,
        demandServed = nil,
        pendingMW = 0,
        lastMW = 0,
        tripRelay = data.tripRelay,
        closeRelay = data.closeRelay,
        openRelay = data.openRelay,
        resetRelay = data.resetRelay,
        demandMetRelay = data.demandMetRelay or data.poweredRelay or data.servedRelay or data.loadServedRelay,
        demandUnmetRelay = data.demandUnmetRelay or data.unpoweredRelay or data.unservedRelay or data.loadUnservedRelay,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
end

function LUASQUARE_POWERGRID.RegisterTransformer(name, data)
    data = data or {}
    LUASQUARE_POWERGRID.Transformers[name] = {
        name = name,
        from = data.from or data.source,
        to = data.to or data.target,
        enabled = data.enabled ~= false,
        closed = data.closed ~= false,
        bidirectional = data.bidirectional ~= false,
        tripped = data.tripped and true or false,
        maxMW = tonumber(data.maxMW) or 1,
        lastMW = 0,
        available = false,
        tripRelay = data.tripRelay,
        resetRelay = data.resetRelay,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
end

function LUASQUARE_POWERGRID.GetGrid(name)
    return LUASQUARE_POWERGRID.Grids[name]
end

function LUASQUARE_POWERGRID.GetBreaker(name)
    return LUASQUARE_POWERGRID.Breakers[name]
end

function LUASQUARE_POWERGRID.GetTransformer(name)
    return LUASQUARE_POWERGRID.Transformers[name]
end

function LUASQUARE_POWERGRID.FireRelay(relay)
    if relay and LUASQUARE_FLUID then LUASQUARE_FLUID.FireRelay(relay) end
end

-- =========================================
-- OPERATORS
-- =========================================
function LUASQUARE_POWERGRID.SetGridEnabled(name, enabled)
    local grid = LUASQUARE_POWERGRID.GetGrid(name)
    if not grid then
        print('[LUASQUARE_POWERGRID] Unknown grid: ' .. tostring(name))
        return false
    end

    grid.enabled = enabled and true or false
    if not grid.enabled then grid.energized = false end
    return true
end

function LUASQUARE_POWERGRID.SetGridDemand(name, mw)
    local grid = LUASQUARE_POWERGRID.GetGrid(name)
    if not grid then
        print('[LUASQUARE_POWERGRID] Unknown grid: ' .. tostring(name))
        return false
    end

    grid.demandMW = math.Clamp(tonumber(mw) or 0, grid.minDemandMW or 0, grid.maxDemandMW or DEFAULT_MAX_MW)
    return true
end

function LUASQUARE_POWERGRID.SetBreakerDemand(name, mw)
    local breaker = LUASQUARE_POWERGRID.GetBreaker(name)
    if not breaker then
        print('[LUASQUARE_POWERGRID] Unknown breaker: ' .. tostring(name))
        return false
    end

    breaker.demandMW = math.max(tonumber(mw) or 0, 0)
    if breaker.demandMW <= 0 then breaker.lastDemandAcceptedMW = 0 end
    return true
end

function LUASQUARE_POWERGRID.TripGrid(name, reason)
    local grid = LUASQUARE_POWERGRID.GetGrid(name)
    if not grid then
        print('[LUASQUARE_POWERGRID] Unknown grid: ' .. tostring(name))
        return false
    end

    if grid.tripped then return true end
    grid.tripped = true
    grid.energized = false
    grid.tripReason = reason or 'TRIP'
    LUASQUARE_POWERGRID.FireRelay(grid.tripRelay)
    print('[LUASQUARE_POWERGRID] TRIP ' .. tostring(name) .. ': ' .. tostring(grid.tripReason))
    return true
end

function LUASQUARE_POWERGRID.ResetGrid(name)
    local grid = LUASQUARE_POWERGRID.GetGrid(name)
    if not grid then
        print('[LUASQUARE_POWERGRID] Unknown grid: ' .. tostring(name))
        return false
    end

    grid.tripped = false
    grid.tripReason = nil
    grid.overloadTimer = 0
    grid.underFrequencyTimer = 0
    grid.enabled = true
    LUASQUARE_POWERGRID.FireRelay(grid.resetRelay)
    return true
end

function LUASQUARE_POWERGRID.SetBreaker(name, closed)
    local breaker = LUASQUARE_POWERGRID.GetBreaker(name)
    if not breaker then
        print('[LUASQUARE_POWERGRID] Unknown breaker: ' .. tostring(name))
        return false
    end

    if breaker.tripped and closed then return false end
    local wasClosed = breaker.closed
    breaker.closed = closed and true or false
    if breaker.closed and not wasClosed then LUASQUARE_POWERGRID.FireRelay(breaker.closeRelay) end
    if not breaker.closed and wasClosed then
        breaker.pendingMW = 0
        breaker.lastMW = 0
        LUASQUARE_POWERGRID.FireRelay(breaker.openRelay)
    end
    return true
end

function LUASQUARE_POWERGRID.TripBreaker(name, reason)
    local breaker = LUASQUARE_POWERGRID.GetBreaker(name)
    if not breaker then
        print('[LUASQUARE_POWERGRID] Unknown breaker: ' .. tostring(name))
        return false
    end

    breaker.tripped = true
    breaker.closed = false
    breaker.tripReason = reason or 'TRIP'
    breaker.pendingMW = 0
    breaker.lastMW = 0
    LUASQUARE_POWERGRID.FireRelay(breaker.tripRelay)
    return true
end

function LUASQUARE_POWERGRID.ResetBreaker(name, close)
    local breaker = LUASQUARE_POWERGRID.GetBreaker(name)
    if not breaker then
        print('[LUASQUARE_POWERGRID] Unknown breaker: ' .. tostring(name))
        return false
    end

    breaker.tripped = false
    breaker.tripReason = nil
    if close ~= nil then
        breaker.closed = close and true or false
        if not breaker.closed then
            breaker.pendingMW = 0
            breaker.lastMW = 0
        end
    end
    LUASQUARE_POWERGRID.FireRelay(breaker.resetRelay)
    return true
end

function LUASQUARE_POWERGRID.SetTransformer(name, closed)
    local transformer = LUASQUARE_POWERGRID.GetTransformer(name)
    if not transformer then
        print('[LUASQUARE_POWERGRID] Unknown transformer: ' .. tostring(name))
        return false
    end

    if transformer.tripped and closed then return false end
    transformer.closed = closed and true or false
    return true
end

-- =========================================
-- POWER FLOW
-- =========================================
function LUASQUARE_POWERGRID.IsGridEnergized(name)
    local grid = LUASQUARE_POWERGRID.GetGrid(name)
    return grid and grid.enabled and not grid.tripped and grid.energized or false
end

function LUASQUARE_POWERGRID.GetGridRPM(name, nominalRPM)
    local grid = LUASQUARE_POWERGRID.GetGrid(name)
    if not grid then return tonumber(nominalRPM) or 0 end

    nominalRPM = tonumber(nominalRPM) or 1800
    return nominalRPM * (grid.frequency or 0) / math.max(grid.nominalFrequency or 60, 0.0001)
end

local function acceptThroughBreaker(breakerName, mw)
    local amount = math.max(tonumber(mw) or 0, 0)
    if not breakerName then return nil, amount end

    local breaker = LUASQUARE_POWERGRID.GetBreaker(breakerName)
    if not breaker or breaker.tripped or not breaker.closed then return breaker, 0 end

    local accepted = math.min(amount, breaker.maxMW or amount)
    breaker.pendingMW = (breaker.pendingMW or 0) + accepted
    return breaker, accepted
end

function LUASQUARE_POWERGRID.SubmitGeneration(gridName, sourceName, mw, breakerName)
    local breaker, accepted = acceptThroughBreaker(breakerName, mw)
    if accepted <= 0 then return 0 end

    local targetGrid = gridName or (breaker and breaker.grid)
    local grid = LUASQUARE_POWERGRID.GetGrid(targetGrid)
    if not grid or not grid.enabled or grid.tripped then
        if breaker then breaker.pendingMW = math.max((breaker.pendingMW or 0) - accepted, 0) end
        return 0
    end

    grid.pendingGenerationMW = (grid.pendingGenerationMW or 0) + accepted
    return accepted
end

function LUASQUARE_POWERGRID.SubmitLoad(gridName, sourceName, mw, breakerName)
    local breaker, accepted = acceptThroughBreaker(breakerName, mw)
    if accepted <= 0 then return 0 end

    local targetGrid = gridName or (breaker and breaker.grid)
    local grid = LUASQUARE_POWERGRID.GetGrid(targetGrid)
    if not grid or not grid.enabled or grid.tripped then
        if breaker then breaker.pendingMW = math.max((breaker.pendingMW or 0) - accepted, 0) end
        return 0
    end

    grid.pendingLoadMW = (grid.pendingLoadMW or 0) + accepted
    return accepted
end

function LUASQUARE_POWERGRID.CanServeLoad(gridName, mw, breakerName)
    local grid = LUASQUARE_POWERGRID.GetGrid(gridName)
    if not grid or not grid.enabled or grid.tripped or not grid.energized then return false end

    if breakerName then
        local breaker = LUASQUARE_POWERGRID.GetBreaker(breakerName)
        if not breaker or breaker.tripped or not breaker.closed then return false end
        if (tonumber(mw) or 0) > (breaker.maxMW or DEFAULT_MAX_MW) then return false end
    end

    return true
end

function LUASQUARE_POWERGRID.SubmitBreakerDemands(gridName)
    for name, breaker in pairs(LUASQUARE_POWERGRID.Breakers) do
        if breaker.grid == gridName and (breaker.demandMW or 0) > 0 then
            breaker.lastDemandAcceptedMW = LUASQUARE_POWERGRID.SubmitLoad(gridName, breaker.owner or name, breaker.demandMW, name)
        elseif breaker.grid == gridName then
            breaker.lastDemandAcceptedMW = 0
        end
    end
end

function LUASQUARE_POWERGRID.UpdateBreakerDemandRelays()
    for _, breaker in pairs(LUASQUARE_POWERGRID.Breakers) do
        local demand = math.max(breaker.demandMW or 0, 0)
        local grid = LUASQUARE_POWERGRID.GetGrid(breaker.grid)
        local served = demand > 0 and breaker.closed and not breaker.tripped and grid and grid.enabled and not grid.tripped and grid.energized and
            (breaker.lastDemandAcceptedMW or 0) >= demand * 0.999

        if served and not breaker.demandServed then
            LUASQUARE_POWERGRID.FireRelay(breaker.demandMetRelay)
        elseif not served and breaker.demandServed then
            LUASQUARE_POWERGRID.FireRelay(breaker.demandUnmetRelay)
        elseif demand > 0 and breaker.demandServed == nil and not served then
            LUASQUARE_POWERGRID.FireRelay(breaker.demandUnmetRelay)
        end

        breaker.demandServed = served and true or false
    end
end

local function allocateTransformerFlow(grid, importMW, exportMW)
    local remaining = math.max(importMW or 0, 0)
    local exportRemaining = math.max(exportMW or 0, 0)
    for _, transformer in pairs(LUASQUARE_POWERGRID.Transformers) do
        if remaining > 0 and transformer.to == grid.name and transformer.available then
            local draw = math.min(remaining, transformer.maxMW or remaining)
            transformer.lastMW = draw
            remaining = remaining - draw
            local source = LUASQUARE_POWERGRID.GetGrid(transformer.from)
            if source then source.pendingLoadMW = (source.pendingLoadMW or 0) + draw end
        elseif exportRemaining > 0 and transformer.to == grid.name and transformer.available and transformer.bidirectional then
            local sent = math.min(exportRemaining, transformer.maxMW or exportRemaining)
            transformer.lastMW = -sent
            exportRemaining = exportRemaining - sent
            local source = LUASQUARE_POWERGRID.GetGrid(transformer.from)
            if source then source.pendingGenerationMW = (source.pendingGenerationMW or 0) + sent end
        elseif transformer.to == grid.name then
            transformer.lastMW = 0
        end
    end
end

function LUASQUARE_POWERGRID.UpdateGrid(name, dt)
    local grid = LUASQUARE_POWERGRID.GetGrid(name)
    if not grid then return end

    LUASQUARE_POWERGRID.SubmitBreakerDemands(name)

    local demandTarget = math.Clamp(grid.demandMW or 0, grid.minDemandMW or 0, grid.maxDemandMW or DEFAULT_MAX_MW)
    local demandStep = math.max(grid.demandRampMWPerSecond or DEFAULT_MAX_MW, 0) * dt
    grid.currentDemandMW = math.Approach(grid.currentDemandMW or 0, demandTarget, demandStep)
    grid.batteryLastMW = 0

    local generation = (grid.pendingGenerationMW or 0) + (grid.baseGenerationMW or 0)
    local demandLoad = (grid.pendingLoadMW or 0) + (grid.baseLoadMW or 0) + (grid.currentDemandMW or 0)
    local sourceCapacity = grid.sourceCapacityMW or 0
    local localCapacity = generation + sourceCapacity
    local importCapacity = grid.availableImportMW or 0
    local batteryCapacityMWh = grid.batteryCapacityMWh or 0
    local batteryDischargeMW = 0
    local batteryChargeMW = 0

    if batteryCapacityMWh > 0 then
        local hours = math.max(dt / 3600, 0.000001)
        local batteryMWh = math.Clamp(grid.batteryMWh or 0, 0, batteryCapacityMWh)
        local unmetAfterImport = math.max(demandLoad - localCapacity - importCapacity, 0)
        local storedDischargeMW = batteryMWh * (grid.batteryDischargeEfficiency or 1) / hours
        batteryDischargeMW = math.min(unmetAfterImport, grid.batteryMaxDischargeMW or 0, storedDischargeMW)

        if batteryDischargeMW > 0 then
            batteryMWh = math.max(batteryMWh - (batteryDischargeMW * hours / math.max(grid.batteryDischargeEfficiency or 1, 0.0001)), 0)
        else
            local freeMWh = math.max(batteryCapacityMWh - batteryMWh, 0)
            local chargeSupplyMW = math.max(localCapacity + importCapacity - demandLoad, 0)
            local storedChargeMW = freeMWh / math.max(grid.batteryChargeEfficiency or 1, 0.0001) / hours
            batteryChargeMW = math.min(chargeSupplyMW, grid.batteryMaxChargeMW or 0, storedChargeMW)
            if batteryChargeMW > 0 then
                batteryMWh = math.min(batteryMWh + batteryChargeMW * hours * (grid.batteryChargeEfficiency or 1), batteryCapacityMWh)
            end
        end

        grid.batteryMWh = batteryMWh
        grid.batteryLastMW = batteryDischargeMW > 0 and batteryDischargeMW or -batteryChargeMW
        grid.batteryChargeFraction = batteryCapacityMWh > 0 and math.Clamp(batteryMWh / batteryCapacityMWh, 0, 1) or 0
    end

    local load = demandLoad + batteryChargeMW
    local deficitBeforeImport = math.max(load - localCapacity - batteryDischargeMW, 0)
    local importMW = math.min(deficitBeforeImport, importCapacity)
    local exportMW = math.min(math.max(localCapacity + batteryDischargeMW - load, 0), importCapacity)
    local available = localCapacity + importMW + batteryDischargeMW
    local availableCapacity = localCapacity + importCapacity + batteryDischargeMW
    local balance = available - load - exportMW
    local energized = grid.enabled and not grid.tripped and (grid.stiff or availableCapacity > 0)

    if not energized then
        grid.frequency = Lerp(math.Clamp(dt * 2, 0, 1), grid.frequency or 0, 0)
        grid.energized = false
    else
        grid.energized = true
        local targetFrequency = grid.nominalFrequency or 60
        local regulatingCapacity = math.max(availableCapacity, load, 1)
        if not grid.stiff then
            local balanceFraction = math.Clamp(balance / regulatingCapacity, -1, 1)
            targetFrequency = targetFrequency + balanceFraction * (grid.droopHz or 1.5)
        end
        grid.frequency = Lerp(math.Clamp(dt / math.max(grid.inertia or 1, 0.0001), 0, 1), grid.frequency or targetFrequency, targetFrequency)
    end

    if grid.enabled and not grid.tripped and not grid.stiff then
        local overload = load > math.max(availableCapacity, 0.0001) * (grid.overloadTripFraction or 1.15)
        local hardOverload = load > math.max(availableCapacity, 0.0001) * (grid.overloadTripHardFraction or 1.50)
        if overload then grid.overloadTimer = (grid.overloadTimer or 0) + dt else grid.overloadTimer = math.max((grid.overloadTimer or 0) - dt, 0) end

        local badFrequency = grid.energized and ((grid.frequency or 0) < (grid.underFrequencyTrip or 54) or (grid.frequency or 0) > (grid.overFrequencyTrip or 66))
        if badFrequency then grid.underFrequencyTimer = (grid.underFrequencyTimer or 0) + dt else grid.underFrequencyTimer = math.max((grid.underFrequencyTimer or 0) - dt, 0) end

        if grid.overloadTimer >= (grid.tripDelay or 30) or hardOverload then
            LUASQUARE_POWERGRID.TripGrid(name, 'OVERLOAD')
        elseif grid.underFrequencyTimer >= (grid.tripDelay or 30) then
            LUASQUARE_POWERGRID.TripGrid(name, 'FREQUENCY')
        elseif grid.batteryTripOnEmpty and batteryCapacityMWh > 0 and (grid.batteryMWh or 0) <= 0 and balance < 0 then
            LUASQUARE_POWERGRID.TripGrid(name, 'BATTERY_EMPTY')
        end
    end

    grid.phase = ((grid.phase or 0) + (grid.frequency or 0) * 360 * dt) % 360
    grid.lastGenerationMW = generation
    grid.lastLoadMW = load
    grid.lastImportMW = importMW - exportMW
    grid.lastAvailableMW = availableCapacity
    grid.lastBalanceMW = balance
    allocateTransformerFlow(grid, importMW, exportMW)

    grid.pendingGenerationMW = 0
    grid.pendingLoadMW = 0
end

function LUASQUARE_POWERGRID.UpdateAll()
    local dt = LUASQUARE_POWERGRID.TickInterval

    for _, breaker in pairs(LUASQUARE_POWERGRID.Breakers) do
        breaker.lastMW = breaker.pendingMW or 0
        breaker.pendingMW = 0
    end

    for _, grid in pairs(LUASQUARE_POWERGRID.Grids) do
        grid.availableImportMW = 0
    end

    for _, transformer in pairs(LUASQUARE_POWERGRID.Transformers) do
        local sourceEnergized = LUASQUARE_POWERGRID.IsGridEnergized(transformer.from)
        transformer.available = transformer.enabled and transformer.closed and not transformer.tripped and sourceEnergized
        transformer.lastMW = 0
        if transformer.available then
            local target = LUASQUARE_POWERGRID.GetGrid(transformer.to)
            if target then target.availableImportMW = (target.availableImportMW or 0) + (transformer.maxMW or 0) end
        end
    end

    for name, _ in pairs(LUASQUARE_POWERGRID.Grids) do
        LUASQUARE_POWERGRID.UpdateGrid(name, dt)
    end

    LUASQUARE_POWERGRID.UpdateBreakerDemandRelays()
end

function LUASQUARE_POWERGRID.Start()
    if timer.Exists('LUASQUARE_POWERGRID_UpdateTimer') then timer.Remove('LUASQUARE_POWERGRID_UpdateTimer') end
    timer.Create('LUASQUARE_POWERGRID_UpdateTimer', LUASQUARE_POWERGRID.TickInterval, 0, function() LUASQUARE_POWERGRID.UpdateAll() end)
    print('[LUASQUARE_POWERGRID] Started')
end

print('[LUASQUARE_POWERGRID] Loaded')
