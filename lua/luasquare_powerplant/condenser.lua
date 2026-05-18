if LUASQUARE_CONDENSER_CORE_LOADED then return end
LUASQUARE_CONDENSER_CORE_LOADED = true
LUASQUARE_CONDENSER = LUASQUARE_CONDENSER or {}
LUASQUARE_CONDENSER.Condensers = LUASQUARE_CONDENSER.Condensers or {}
LUASQUARE_CONDENSER.TickInterval = LUASQUARE_CONDENSER.TickInterval or 0.1

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_CONDENSER.RegisterCondenser(name, data)
    data = data or {}
    LUASQUARE_CONDENSER.Condensers[name] = {
        name = name,
        input = data.input,
        output = data.output,
        ratio = tonumber(data.ratio) or 1600,
        maxRate = tonumber(data.maxRate) or math.huge,
        enabled = data.enabled and true or false,
        godMode = data.godMode and true or false,
        startRelay = data.startRelay,
        stopRelay = data.stopRelay,
        lastSteamUsed = 0,
        lastWaterMade = 0,
        monitorPos = data.monitorPos,
        monitorOffset = data.monitorOffset or Vector(0, 0, 0)
    }
end

function LUASQUARE_CONDENSER.GetCondenser(name)
    return LUASQUARE_CONDENSER.Condensers[name]
end

function LUASQUARE_CONDENSER.SetCondenser(name, enabled)
    local condenser = LUASQUARE_CONDENSER.GetCondenser(name)
    if not condenser then
        print('[LUASQUARE_CONDENSER] Unknown condenser: ' .. tostring(name))
        return false
    end

    local wasEnabled = condenser.enabled
    condenser.enabled = enabled and true or false
    if condenser.enabled and not wasEnabled and condenser.startRelay and LUASQUARE_FLUID then LUASQUARE_FLUID.FireRelay(condenser.startRelay) end
    if not condenser.enabled and wasEnabled and condenser.stopRelay and LUASQUARE_FLUID then LUASQUARE_FLUID.FireRelay(condenser.stopRelay) end
    return true
end

-- =========================================
-- UPDATE
-- =========================================
function LUASQUARE_CONDENSER.UpdateCondenser(name, dt)
    local condenser = LUASQUARE_CONDENSER.GetCondenser(name)
    if not condenser then return end
    condenser.lastSteamUsed = 0
    condenser.lastWaterMade = 0
    if not condenser.enabled then return end
    if not LUASQUARE_FLUID then return end

    local input = LUASQUARE_FLUID.GetNetwork(condenser.input)
    local output = LUASQUARE_FLUID.GetNetwork(condenser.output)
    if not input then
        print('[LUASQUARE_CONDENSER] Unknown input network: ' .. tostring(condenser.input))
        return
    end

    if not output then
        print('[LUASQUARE_CONDENSER] Unknown output network: ' .. tostring(condenser.output))
        return
    end

    local ratio = math.max(condenser.ratio, 0.0001)
    local outputFree = math.max((output.hardMaxAmount or output.maxAmount) - output.amount, 0)
    local rateLimit = condenser.maxRate
    if rateLimit ~= math.huge then rateLimit = rateLimit * dt end

    local steamToUse = math.min(input.amount, outputFree * ratio, rateLimit)
    if steamToUse <= 0 then return end

    local removed = LUASQUARE_FLUID.RemoveFluid(condenser.input, steamToUse)
    local waterMade = removed / ratio
    local added = LUASQUARE_FLUID.AddFluid(condenser.output, waterMade)
    if added < waterMade then
        LUASQUARE_FLUID.AddFluid(condenser.input, (waterMade - added) * ratio)
        waterMade = added
        removed = added * ratio
    end

    output.temperature = 20
    condenser.lastSteamUsed = removed / math.max(dt, 0.0001)
    condenser.lastWaterMade = waterMade / math.max(dt, 0.0001)
end

function LUASQUARE_CONDENSER.UpdateAll()
    local dt = LUASQUARE_CONDENSER.TickInterval
    for name, _ in pairs(LUASQUARE_CONDENSER.Condensers) do
        LUASQUARE_CONDENSER.UpdateCondenser(name, dt)
    end
end

function LUASQUARE_CONDENSER.Start()
    if timer.Exists('LUASQUARE_CONDENSER_UpdateTimer') then timer.Remove('LUASQUARE_CONDENSER_UpdateTimer') end
    timer.Create('LUASQUARE_CONDENSER_UpdateTimer', LUASQUARE_CONDENSER.TickInterval, 0, function() LUASQUARE_CONDENSER.UpdateAll() end)
    print('[LUASQUARE_CONDENSER] Started')
end

print('[LUASQUARE_CONDENSER] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- LUASQUARE_CONDENSER.RegisterCondenser('god_condenser', {
--     input = 'main_steam',
--     output = 'condensate',
--     ratio = 1600,
--     maxRate = math.huge,
--     enabled = true,
--     godMode = true,
--     monitorPos = Vector(0, 0, 128)
-- })
-- LUASQUARE_CONDENSER.Start()
