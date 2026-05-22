if LUASQUARE_VALVE_CORE_LOADED then return end
LUASQUARE_VALVE_CORE_LOADED = true
LUASQUARE_VALVE = LUASQUARE_VALVE or {}
LUASQUARE_VALVE.Valves = LUASQUARE_VALVE.Valves or {}
LUASQUARE_VALVE.TickInterval = LUASQUARE_VALVE.TickInterval or 0.1

function LUASQUARE_VALVE.RegisterValve(name, data)
    data = data or {}
    LUASQUARE_VALVE.Valves[name] = {
        name = name,
        a = data.a,
        b = data.b,
        maxFlow = tonumber(data.maxFlow) or 1,
        open = data.open and true or false,
        bidirectional = data.bidirectional ~= false,
        lastFlow = 0,
        monitorPos = data.monitorPos,
        monitorTarget = data.monitorTarget or data.monitorEntity or data.monitorName,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
end

function LUASQUARE_VALVE.GetValve(name)
    return LUASQUARE_VALVE.Valves[name]
end

function LUASQUARE_VALVE.SetValve(name, open)
    local valve = LUASQUARE_VALVE.GetValve(name)
    if not valve then
        print('[LUASQUARE_VALVE] Unknown valve: ' .. tostring(name))
        return false
    end

    valve.open = open and true or false
    if not valve.open then valve.lastFlow = 0 end
    return true
end

function LUASQUARE_VALVE.GetEndpointPressure(endpoint)
    if endpoint == 'void' then return 0 end
    if endpoint == 'rbmk_steam' or endpoint == 'rbmk_water' then
        if not RBMK then return 0 end
        return RBMK.GetRPVPressure and RBMK.GetRPVPressure() or RBMK.RPVPressure or 0
    end

    local network = LUASQUARE_FLUID and LUASQUARE_FLUID.GetNetwork(endpoint)
    if not network then return 0 end
    return network.pressure or 0
end

function LUASQUARE_VALVE.GetEndpointTemperature(endpoint)
    if endpoint == 'void' then return 20 end
    if endpoint == 'rbmk_steam' then
        if not RBMK then return 20 end
        return RBMK.SteamTemperature or 100
    end

    if endpoint == 'rbmk_water' then
        if not RBMK then return 20 end
        return RBMK.WaterTemperature or 20
    end

    local network = LUASQUARE_FLUID and LUASQUARE_FLUID.GetNetwork(endpoint)
    if not network then return 20 end
    return network.temperature or 20
end

function LUASQUARE_VALVE.RemoveFromEndpoint(endpoint, amount)
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

    if not LUASQUARE_FLUID then return 0 end
    return LUASQUARE_FLUID.RemoveFluid(endpoint, amount)
end

function LUASQUARE_VALVE.AddToEndpoint(endpoint, amount, pressure, temperature)
    amount = math.max(tonumber(amount) or 0, 0)
    if endpoint == 'void' then return amount end
    if endpoint == 'rbmk_steam' then
        if not RBMK then return 0 end
        local freeSteam = math.max((RBMK.HardMaxSteam or math.huge) - (RBMK.Steam or 0), 0)
        local moved = math.min(amount, freeSteam)
        RBMK.SteamTemperature = RBMK.MixTemperature and RBMK.MixTemperature(RBMK.Steam or 0, RBMK.SteamTemperature or 100, moved, temperature or 100) or RBMK.SteamTemperature
        RBMK.Steam = RBMK.Steam + moved
        RBMK.UpdateRPVPressure()
        return moved
    end

    if endpoint == 'rbmk_water' then
        if not RBMK or not RBMK.AddWaterFromPump then return 0 end
        return RBMK.AddWaterFromPump(amount, pressure or 0, temperature)
    end

    if not LUASQUARE_FLUID then return 0 end
    return LUASQUARE_FLUID.AddFluid(endpoint, amount, temperature)
end

function LUASQUARE_VALVE.RestoreToEndpoint(endpoint, amount, temperature)
    amount = math.max(tonumber(amount) or 0, 0)
    if endpoint == 'rbmk_steam' then
        if not RBMK then return 0 end
        local freeSteam = math.max((RBMK.HardMaxSteam or math.huge) - (RBMK.Steam or 0), 0)
        local moved = math.min(amount, freeSteam)
        RBMK.SteamTemperature = RBMK.MixTemperature and RBMK.MixTemperature(RBMK.Steam or 0, RBMK.SteamTemperature or 100, moved, temperature or 100) or RBMK.SteamTemperature
        RBMK.Steam = RBMK.Steam + moved
        RBMK.UpdateRPVPressure()
        return moved
    end

    if endpoint == 'rbmk_water' then
        if not RBMK then return 0 end
        local freeWater = math.max((RBMK.MaxWater or math.huge) - (RBMK.Water or 0), 0)
        local moved = math.min(amount, freeWater)
        RBMK.WaterTemperature = RBMK.MixTemperature and RBMK.MixTemperature(RBMK.Water or 0, RBMK.WaterTemperature or 20, moved, temperature or 20) or RBMK.WaterTemperature
        RBMK.Water = RBMK.Water + moved
        RBMK.UpdateRPVPressure()
        return moved
    end

    if not LUASQUARE_FLUID then return 0 end
    return LUASQUARE_FLUID.AddFluid(endpoint, amount, temperature)
end

function LUASQUARE_VALVE.Transfer(a, b, amount, pressure)
    local temperature = LUASQUARE_VALVE.GetEndpointTemperature(a)
    local removed = LUASQUARE_VALVE.RemoveFromEndpoint(a, amount)
    local added = LUASQUARE_VALVE.AddToEndpoint(b, removed, pressure, temperature)
    if added < removed then LUASQUARE_VALVE.RestoreToEndpoint(a, removed - added, temperature) end
    return added
end

function LUASQUARE_VALVE.UpdateValve(name, dt)
    local valve = LUASQUARE_VALVE.GetValve(name)
    if not valve then return end
    valve.lastFlow = 0
    if not valve.open then return end

    local pressureA = LUASQUARE_VALVE.GetEndpointPressure(valve.a)
    local pressureB = LUASQUARE_VALVE.GetEndpointPressure(valve.b)
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
    local moved = LUASQUARE_VALVE.Transfer(fromEndpoint, toEndpoint, requested, sourcePressure)
    valve.lastFlow = moved / math.max(dt, 0.0001)
end

function LUASQUARE_VALVE.UpdateAll()
    local dt = LUASQUARE_VALVE.TickInterval
    for name, _ in pairs(LUASQUARE_VALVE.Valves) do
        LUASQUARE_VALVE.UpdateValve(name, dt)
    end
end

function LUASQUARE_VALVE.Start()
    if timer.Exists('LUASQUARE_VALVE_UpdateTimer') then timer.Remove('LUASQUARE_VALVE_UpdateTimer') end
    timer.Create('LUASQUARE_VALVE_UpdateTimer', LUASQUARE_VALVE.TickInterval, 0, function() LUASQUARE_VALVE.UpdateAll() end)
    print('[LUASQUARE_VALVE] Started')
end

print('[LUASQUARE_VALVE] Loaded')
