if LITHOS_VALVE_CORE_LOADED then return end
LITHOS_VALVE_CORE_LOADED = true
LITHOS_VALVE = LITHOS_VALVE or {}
LITHOS_VALVE.Valves = LITHOS_VALVE.Valves or {}
LITHOS_VALVE.TickInterval = LITHOS_VALVE.TickInterval or 0.1

function LITHOS_VALVE.RegisterValve(name, data)
    data = data or {}
    LITHOS_VALVE.Valves[name] = {
        name = name,
        a = data.a,
        b = data.b,
        maxFlow = tonumber(data.maxFlow) or 1,
        open = data.open and true or false,
        bidirectional = data.bidirectional ~= false,
        lastFlow = 0,
        monitorPos = data.monitorPos,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
end

function LITHOS_VALVE.GetValve(name)
    return LITHOS_VALVE.Valves[name]
end

function LITHOS_VALVE.SetValve(name, open)
    local valve = LITHOS_VALVE.GetValve(name)
    if not valve then
        print('[LITHOS_VALVE] Unknown valve: ' .. tostring(name))
        return false
    end

    valve.open = open and true or false
    if not valve.open then valve.lastFlow = 0 end
    return true
end

function LITHOS_VALVE.GetEndpointPressure(endpoint)
    if endpoint == 'rbmk_steam' or endpoint == 'rbmk_water' then
        if not RBMK then return 0 end
        return RBMK.GetRPVPressure and RBMK.GetRPVPressure() or RBMK.RPVPressure or 0
    end

    local network = LITHOS_FLUID and LITHOS_FLUID.GetNetwork(endpoint)
    if not network then return 0 end
    return network.pressure or 0
end

function LITHOS_VALVE.RemoveFromEndpoint(endpoint, amount)
    amount = math.max(tonumber(amount) or 0, 0)
    if endpoint == 'rbmk_steam' then
        if not RBMK then return 0 end
        local moved = math.min(amount, RBMK.Steam or 0)
        RBMK.Steam = RBMK.Steam - moved
        RBMK.UpdateRPVPressure()
        return moved
    end

    if endpoint == 'rbmk_water' then
        if not RBMK then return 0 end
        local moved = math.min(amount, RBMK.Water or 0)
        RBMK.Water = RBMK.Water - moved
        RBMK.UpdateRPVPressure()
        return moved
    end

    if not LITHOS_FLUID then return 0 end
    return LITHOS_FLUID.RemoveFluid(endpoint, amount)
end

function LITHOS_VALVE.AddToEndpoint(endpoint, amount, pressure)
    amount = math.max(tonumber(amount) or 0, 0)
    if endpoint == 'rbmk_steam' then
        if not RBMK then return 0 end
        local freeSteam = math.max((RBMK.HardMaxSteam or math.huge) - (RBMK.Steam or 0), 0)
        local moved = math.min(amount, freeSteam)
        RBMK.Steam = RBMK.Steam + moved
        RBMK.UpdateRPVPressure()
        return moved
    end

    if endpoint == 'rbmk_water' then
        if not RBMK or not RBMK.AddWaterFromPump then return 0 end
        return RBMK.AddWaterFromPump(amount, pressure or 0)
    end

    if not LITHOS_FLUID then return 0 end
    return LITHOS_FLUID.AddFluid(endpoint, amount)
end

function LITHOS_VALVE.RestoreToEndpoint(endpoint, amount)
    amount = math.max(tonumber(amount) or 0, 0)
    if endpoint == 'rbmk_steam' then
        if not RBMK then return 0 end
        local freeSteam = math.max((RBMK.HardMaxSteam or math.huge) - (RBMK.Steam or 0), 0)
        local moved = math.min(amount, freeSteam)
        RBMK.Steam = RBMK.Steam + moved
        RBMK.UpdateRPVPressure()
        return moved
    end

    if endpoint == 'rbmk_water' then
        if not RBMK then return 0 end
        local freeWater = math.max((RBMK.MaxWater or math.huge) - (RBMK.Water or 0), 0)
        local moved = math.min(amount, freeWater)
        RBMK.Water = RBMK.Water + moved
        RBMK.UpdateRPVPressure()
        return moved
    end

    if not LITHOS_FLUID then return 0 end
    return LITHOS_FLUID.AddFluid(endpoint, amount)
end

function LITHOS_VALVE.Transfer(a, b, amount, pressure)
    local removed = LITHOS_VALVE.RemoveFromEndpoint(a, amount)
    local added = LITHOS_VALVE.AddToEndpoint(b, removed, pressure)
    if added < removed then LITHOS_VALVE.RestoreToEndpoint(a, removed - added) end
    return added
end

function LITHOS_VALVE.UpdateValve(name, dt)
    local valve = LITHOS_VALVE.GetValve(name)
    if not valve then return end
    valve.lastFlow = 0
    if not valve.open then return end

    local pressureA = LITHOS_VALVE.GetEndpointPressure(valve.a)
    local pressureB = LITHOS_VALVE.GetEndpointPressure(valve.b)
    local fromEndpoint = valve.a
    local toEndpoint = valve.b
    local sourcePressure = pressureA
    local pressureDelta = pressureA - pressureB

    if pressureDelta < 0 and valve.bidirectional then
        fromEndpoint = valve.b
        toEndpoint = valve.a
        sourcePressure = pressureB
        pressureDelta = -pressureDelta
    end

    if pressureDelta <= 0 then return end

    local pressureScale = math.Clamp(pressureDelta / math.max(sourcePressure, 0.0001), 0, 1)
    local requested = valve.maxFlow * pressureScale * dt
    local moved = LITHOS_VALVE.Transfer(fromEndpoint, toEndpoint, requested, sourcePressure)
    valve.lastFlow = moved / math.max(dt, 0.0001)
end

function LITHOS_VALVE.UpdateAll()
    local dt = LITHOS_VALVE.TickInterval
    for name, _ in pairs(LITHOS_VALVE.Valves) do
        LITHOS_VALVE.UpdateValve(name, dt)
    end
end

function LITHOS_VALVE.Start()
    if timer.Exists('LITHOS_VALVE_UpdateTimer') then timer.Remove('LITHOS_VALVE_UpdateTimer') end
    timer.Create('LITHOS_VALVE_UpdateTimer', LITHOS_VALVE.TickInterval, 0, function() LITHOS_VALVE.UpdateAll() end)
    print('[LITHOS_VALVE] Started')
end

print('[LITHOS_VALVE] Loaded')
