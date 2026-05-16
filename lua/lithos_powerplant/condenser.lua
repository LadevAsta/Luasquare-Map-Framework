if LITHOS_CONDENSER_CORE_LOADED then return end
LITHOS_CONDENSER_CORE_LOADED = true
LITHOS_CONDENSER = LITHOS_CONDENSER or {}
LITHOS_CONDENSER.Condensers = LITHOS_CONDENSER.Condensers or {}
LITHOS_CONDENSER.TickInterval = LITHOS_CONDENSER.TickInterval or 0.1

-- =========================================
-- REGISTER
-- =========================================
function LITHOS_CONDENSER.RegisterCondenser(name, data)
    data = data or {}
    LITHOS_CONDENSER.Condensers[name] = {
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

function LITHOS_CONDENSER.GetCondenser(name)
    return LITHOS_CONDENSER.Condensers[name]
end

function LITHOS_CONDENSER.SetCondenser(name, enabled)
    local condenser = LITHOS_CONDENSER.GetCondenser(name)
    if not condenser then
        print('[LITHOS_CONDENSER] Unknown condenser: ' .. tostring(name))
        return false
    end

    local wasEnabled = condenser.enabled
    condenser.enabled = enabled and true or false
    if condenser.enabled and not wasEnabled and condenser.startRelay and LITHOS_FLUID then LITHOS_FLUID.FireRelay(condenser.startRelay) end
    if not condenser.enabled and wasEnabled and condenser.stopRelay and LITHOS_FLUID then LITHOS_FLUID.FireRelay(condenser.stopRelay) end
    return true
end

-- =========================================
-- UPDATE
-- =========================================
function LITHOS_CONDENSER.UpdateCondenser(name, dt)
    local condenser = LITHOS_CONDENSER.GetCondenser(name)
    if not condenser then return end
    condenser.lastSteamUsed = 0
    condenser.lastWaterMade = 0
    if not condenser.enabled then return end
    if not LITHOS_FLUID then return end

    local input = LITHOS_FLUID.GetNetwork(condenser.input)
    local output = LITHOS_FLUID.GetNetwork(condenser.output)
    if not input then
        print('[LITHOS_CONDENSER] Unknown input network: ' .. tostring(condenser.input))
        return
    end

    if not output then
        print('[LITHOS_CONDENSER] Unknown output network: ' .. tostring(condenser.output))
        return
    end

    local ratio = math.max(condenser.ratio, 0.0001)
    local outputFree = math.max((output.hardMaxAmount or output.maxAmount) - output.amount, 0)
    local rateLimit = condenser.maxRate
    if rateLimit ~= math.huge then rateLimit = rateLimit * dt end

    local steamToUse = math.min(input.amount, outputFree * ratio, rateLimit)
    if steamToUse <= 0 then return end

    local removed = LITHOS_FLUID.RemoveFluid(condenser.input, steamToUse)
    local waterMade = removed / ratio
    local added = LITHOS_FLUID.AddFluid(condenser.output, waterMade)
    if added < waterMade then
        LITHOS_FLUID.AddFluid(condenser.input, (waterMade - added) * ratio)
        waterMade = added
        removed = added * ratio
    end

    output.temperature = 20
    condenser.lastSteamUsed = removed / math.max(dt, 0.0001)
    condenser.lastWaterMade = waterMade / math.max(dt, 0.0001)
end

function LITHOS_CONDENSER.UpdateAll()
    local dt = LITHOS_CONDENSER.TickInterval
    for name, _ in pairs(LITHOS_CONDENSER.Condensers) do
        LITHOS_CONDENSER.UpdateCondenser(name, dt)
    end
end

function LITHOS_CONDENSER.Start()
    if timer.Exists('LITHOS_CONDENSER_UpdateTimer') then timer.Remove('LITHOS_CONDENSER_UpdateTimer') end
    timer.Create('LITHOS_CONDENSER_UpdateTimer', LITHOS_CONDENSER.TickInterval, 0, function() LITHOS_CONDENSER.UpdateAll() end)
    print('[LITHOS_CONDENSER] Started')
end

print('[LITHOS_CONDENSER] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- LITHOS_CONDENSER.RegisterCondenser('god_condenser', {
--     input = 'main_steam',
--     output = 'condensate',
--     ratio = 1600,
--     maxRate = math.huge,
--     enabled = true,
--     godMode = true,
--     monitorPos = Vector(0, 0, 128)
-- })
-- LITHOS_CONDENSER.Start()
