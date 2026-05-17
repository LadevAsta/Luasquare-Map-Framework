RBMK = RBMK or {}
RBMK.ModelName = 'Unknown RBMK'
RBMK.Width = 0
RBMK.Height = 0
RBMK.Matrix = {}
RBMK.TickInterval = 0.1

RBMK.ColumnVolume = RBMK.ColumnVolume or 1000
RBMK.TotalVolume = RBMK.TotalVolume or 0
RBMK.SteamSpace = RBMK.SteamSpace or 0
RBMK.MinSteamSpace = RBMK.MinSteamSpace or 0
RBMK.RPVMinSteamSpaceFraction = RBMK.RPVMinSteamSpaceFraction or 0.05
RBMK.SteamExpansionRatio = RBMK.SteamExpansionRatio or 1600
RBMK.SteamPressureFactor = RBMK.SteamPressureFactor or 1

RBMK.Water = 0
RBMK.WaterTemperature = 20
RBMK.Steam = 0
RBMK.MaxWater = 0
RBMK.MaxSteam = 0
RBMK.HardMaxSteam = 0
RBMK.RPVPressure = 0
RBMK.RPVMaxPressure = 70
RBMK.RPVHardPressure = 110
RBMK.RPVSteamReliefPressure = 5
RBMK.PressureUnit = 'bar'
RBMK.SteamNetwork = nil
RBMK.SteamOutletOpen = true
RBMK.FeedwaterInletOpen = true
RBMK.DrainValveOpen = false
RBMK.DrainNetwork = nil
RBMK.SteamOutletFlowRate = 0.25
RBMK.DrainFlowRate = 10

RBMK.WaterSpecificHeatKJPerL = 4.186
RBMK.WaterLatentHeatKJPerL = 2257
RBMK.WaterBoilingTemperature = 100
RBMK.ChannelThermalMassKJPerC = 250
RBMK.ChannelBoilingHeatTransfer = 0.08
RBMK.LastThermalMW = 0
RBMK.LastSteamExportFlow = 0
RBMK.LastDrainFlow = 0

RBMK.EventState = RBMK.EventState or {}
RBMK.EventState.NextBlowout = 0
RBMK.EventState.BlowoutValveCooldowns = RBMK.EventState.BlowoutValveCooldowns or {}
RBMK.EventState.NextLeakCheck = 0
RBMK.EventState.Failed = false
RBMK.EventState.FailureReason = nil

RBMK.BlowoutEnabled = RBMK.BlowoutEnabled ~= false
RBMK.BlowoutPressure = RBMK.BlowoutPressure or 85
RBMK.BlowoutCooldown = RBMK.BlowoutCooldown or 0.1
RBMK.BlowoutColumnCooldown = RBMK.BlowoutColumnCooldown or 1.5
RBMK.BlowoutValvePrefix = RBMK.BlowoutValvePrefix or 'rbmk_blowout'
RBMK.BlowoutFallbackValveCount = RBMK.BlowoutFallbackValveCount or 20
RBMK.BlowoutValves = RBMK.BlowoutValves or {}
RBMK.BlowoutMinColumnsPerPass = RBMK.BlowoutMinColumnsPerPass or 1
RBMK.BlowoutMaxColumnsPerPass = RBMK.BlowoutMaxColumnsPerPass or 1
RBMK.BlowoutSteamLoss = RBMK.BlowoutSteamLoss or 0.5
RBMK.BlowoutMinSpeed = RBMK.BlowoutMinSpeed or 64
RBMK.BlowoutMaxSpeed = RBMK.BlowoutMaxSpeed or 320
RBMK.BlowoutFallSpeed = RBMK.BlowoutFallSpeed or 320
RBMK.BlowoutMinDuration = RBMK.BlowoutMinDuration or 0.2
RBMK.BlowoutMaxDuration = RBMK.BlowoutMaxDuration or 1

RBMK.CatastrophicPressure = RBMK.CatastrophicPressure or 130
RBMK.CatastrophicFailureRelay = RBMK.CatastrophicFailureRelay or nil
RBMK.CatastrophicClearDelay = RBMK.CatastrophicClearDelay or 5

RBMK.FuelLeakCheckInterval = RBMK.FuelLeakCheckInterval or 30
RBMK.FuelLeakTemperature = RBMK.FuelLeakTemperature or 1500
RBMK.FuelLeakBaseChance = RBMK.FuelLeakBaseChance or 5
RBMK.FuelLeakChanceStep = RBMK.FuelLeakChanceStep or 5
RBMK.FuelLeakTemperatureStep = RBMK.FuelLeakTemperatureStep or 50
RBMK.FuelLeakHeatRate = RBMK.FuelLeakHeatRate or 50
RBMK.FuelLeakRelay = RBMK.FuelLeakRelay or nil
RBMK.FuelMeltdownTemperature = RBMK.FuelMeltdownTemperature or 3000
RBMK.FuelMeltdownDelay = RBMK.FuelMeltdownDelay or 30
RBMK.FuelMeltdownRelay = RBMK.FuelMeltdownRelay or nil

RBMK.AverageHeat = 20
RBMK.MaxHeat = 20

RBMK.AverageXenon = 0

--TODO : Somehow Implement Megawatt Thermal (thermal transfer method). Which will be used by Auto control rod to stabilize the reactor for power production later (New Turbine Module in lithos_powerplant).
-- Pressure is gameplay bar. Steam is stored as 1 bar steam-equivalent liters.

-- =========================================
-- MATRIX
-- =========================================
function RBMK.CreateMatrix(w, h)
    RBMK.Width = w
    RBMK.Height = h
    RBMK.Matrix = {}
    for x = 1, w do
        RBMK.Matrix[x] = {}
        for y = 1, h do
            RBMK.Matrix[x][y] = RBMK.CreateBlank()
        end
    end
end

-- =========================================
-- CELLS
-- =========================================
function RBMK.SetCell(x, y, cell)
    if not RBMK.Matrix[x] then return end
    if not RBMK.Matrix[x][y] then return end
    RBMK.Matrix[x][y] = cell
end

function RBMK.GetCell(x, y)
    if not RBMK.Matrix[x] then return nil end
    return RBMK.Matrix[x][y]
end

-- Reactor tick
function RBMK.Tick()
    RBMK.DoFluxStep()
    RBMK.DoXenonStep()
    RBMK.DoFuelHeat()
    RBMK.CommitFlux()
    RBMK.DoHeatStep()
    RBMK.DoSteamStep()
    RBMK.DoSteamExportStep()
    RBMK.DoDrainStep()
    RBMK.DoControlStep()
    RBMK.UpdateTelemetry()
    RBMK.DoEventStep()
    RBMK.Debug.Tick()
end

-- Data Accessor
function RBMK.GetHeat(x, y)
    local cell = RBMK.GetCell(x, y)
    if not cell then return 0 end
    return cell.heat or 0
end

function RBMK.GetCoreHeat(x, y)
    local cell = RBMK.GetCell(x, y)
    if cell.type ~= RBMK.CELL_FUEL then return 0 end
    return cell.coreHeat or 0
end

function RBMK.GetSkinHeat(x, y)
    local cell = RBMK.GetCell(x, y)
    if cell.type ~= RBMK.CELL_FUEL then return 0 end
    return cell.skinHeat or 0
end

function RBMK.GetFlux(x, y)
    local cell = RBMK.GetCell(x, y)
    if not cell then return 0 end
    return cell.flux or 0
end

function RBMK.GetCellType(x, y)
    local cell = RBMK.GetCell(x, y)
    if not cell then return nil end
    return cell.type
end

function RBMK.GetRodInsertion(x, y)
    local cell = RBMK.GetCell(x, y)
    if not cell then return 0 end
    return cell.rodInsertion or 0
end

-- =========================================
-- Utilities
-- =========================================

function RBMK.CalculateColumnVolume(width, length, height, hollowPercentage)
    -- In hammer, I assume 1 unit is 1 inch. This converts cubic inches to liters
    hollowPercentage = hollowPercentage or 50
    RBMK.ColumnVolume = width * length * height * 0.016387064 * (hollowPercentage / 100)
end

-- Start loop
function RBMK.Start()
    if timer.Exists('RBMK_Tick') then timer.Remove('RBMK_Tick') end
    timer.Create('RBMK_Tick', RBMK.TickInterval, 0, function() RBMK.Tick() end)
    print('[LITHOS_RBMK] Started')
end

-- =========================================
-- Reactor Events
-- =========================================

function RBMK.GetTime()
    if CurTime then return CurTime() end
    return os.clock()
end

function RBMK.FireRelay(relayName)
    if not relayName then return false end
    local ent = ents.FindByName(relayName)[1]
    if not IsValid(ent) then
        print('[LITHOS_RBMK] Missing relay: ' .. tostring(relayName))
        return false
    end

    ent:Fire('Trigger')
    return true
end

function RBMK.ClearBlowoutValves()
    RBMK.BlowoutValves = {}
    if RBMK.EventState then RBMK.EventState.BlowoutValveCooldowns = {} end
end

function RBMK.RegisterBlowoutValve(targetName, key)
    if not targetName then return nil end
    key = key or targetName
    local ent = ents.FindByName(targetName)[1]
    local valve = {
        key = key,
        targetName = targetName,
        ent = IsValid(ent) and ent or nil,
        resolved = IsValid(ent)
    }

    table.insert(RBMK.BlowoutValves, valve)
    return valve
end

function RBMK.RegisterBlowoutValveRange(prefix, count, startIndex)
    prefix = prefix or RBMK.BlowoutValvePrefix
    count = math.max(math.floor(tonumber(count) or 0), 0)
    startIndex = math.floor(tonumber(startIndex) or 0)
    for i = startIndex, startIndex + count - 1 do
        RBMK.RegisterBlowoutValve(prefix .. '_' .. i)
    end
end

function RBMK.EnsureBlowoutValveRegistry()
    if #RBMK.BlowoutValves > 0 then return end
    RBMK.RegisterBlowoutValveRange(RBMK.BlowoutValvePrefix, RBMK.BlowoutFallbackValveCount, 0)
end

function RBMK.ResolveBlowoutValve(valve)
    if not valve then return nil end
    if IsValid(valve.ent) then return valve.ent end
    if valve.resolved then return nil end
    if not valve.targetName then return nil end

    valve.ent = ents.FindByName(valve.targetName)[1]
    valve.resolved = true
    if not IsValid(valve.ent) then valve.ent = nil end
    return valve.ent
end

function RBMK.GetBlowoutValves()
    RBMK.EnsureBlowoutValveRegistry()
    return RBMK.BlowoutValves
end

function RBMK.GetAvailableBlowoutValves(now)
    local available = {}
    local cooldowns = RBMK.EventState.BlowoutValveCooldowns or {}
    for _, valve in ipairs(RBMK.GetBlowoutValves()) do
        if now >= (cooldowns[valve.key] or 0) then table.insert(available, valve) end
    end

    return available
end

function RBMK.SetBlowoutEnabled(enabled)
    RBMK.BlowoutEnabled = enabled and true or false
end

function RBMK.GetBlowoutColumnCount(overFactor, availableCount)
    local minColumns = math.Clamp(math.floor(tonumber(RBMK.BlowoutMinColumnsPerPass) or 1), 1, 8)
    local maxColumns = math.Clamp(math.floor(tonumber(RBMK.BlowoutMaxColumnsPerPass) or minColumns), minColumns, 8)
    maxColumns = math.min(maxColumns, availableCount)
    minColumns = math.min(minColumns, maxColumns)
    if maxColumns <= minColumns then return maxColumns end

    local biasedRoll = math.Rand(0, 1) ^ Lerp(overFactor, 2.5, 0.45)
    return math.Clamp(math.floor(Lerp(biasedRoll, minColumns, maxColumns) + 0.5), minColumns, maxColumns)
end

function RBMK.GetBlowoutMotion(overFactor)
    local speedBias = math.Rand(0, 1) ^ Lerp(overFactor, 2.2, 0.55)
    local durationBias = math.Rand(0, 1) ^ Lerp(overFactor, 2.2, 0.55)
    local speed = Lerp(speedBias, RBMK.BlowoutMinSpeed, RBMK.BlowoutMaxSpeed)
    local duration = Lerp(durationBias, RBMK.BlowoutMinDuration, RBMK.BlowoutMaxDuration)
    return speed, duration
end

function RBMK.BlowoutSteam()
    if not RBMK.BlowoutEnabled then return 0 end
    if RBMK.EventState.Failed then return 0 end
    local now = RBMK.GetTime()
    if now < (RBMK.EventState.NextBlowout or 0) then return 0 end

    local pressure = RBMK.UpdateRPVPressure()
    local overFactor = math.Clamp((pressure - RBMK.BlowoutPressure) / math.max(RBMK.CatastrophicPressure - RBMK.BlowoutPressure, 1), 0, 1)
    if overFactor <= 0 then return 0 end

    local availableValves = RBMK.GetAvailableBlowoutValves(now)
    if #availableValves <= 0 then return 0 end
    local jumpCount = RBMK.GetBlowoutColumnCount(overFactor, #availableValves)
    local jumped = {}
    local longestDuration = 0

    for _ = 1, jumpCount do
        local index = math.random(1, #availableValves)
        local valve = table.remove(availableValves, index)
        local speed, duration = RBMK.GetBlowoutMotion(overFactor)
        longestDuration = math.max(longestDuration, duration)

        local ent = RBMK.ResolveBlowoutValve(valve)
        if IsValid(ent) then
            ent:Fire('SetSpeed', tostring(speed))
            ent:Fire('Open')
            timer.Simple(duration, function()
                if IsValid(ent) then
                    ent:Fire('SetSpeed', tostring(RBMK.BlowoutFallSpeed))
                    ent:Fire('Close')
                end
            end)
        end

        RBMK.EventState.BlowoutValveCooldowns = RBMK.EventState.BlowoutValveCooldowns or {}
        RBMK.EventState.BlowoutValveCooldowns[valve.key] = now + duration + RBMK.BlowoutColumnCooldown
        table.insert(jumped, valve.key)
    end

    local steamLoss = RBMK.SteamSpace * RBMK.BlowoutSteamLoss * (0.5 + overFactor) * RBMK.TickInterval * #jumped
    steamLoss = math.min(steamLoss, RBMK.Steam)
    RBMK.Steam = RBMK.Steam - steamLoss
    RBMK.EventState.LastBlowoutSteamLoss = steamLoss
    RBMK.EventState.LastBlowoutPressure = pressure
    RBMK.EventState.LastBlowoutValve = table.concat(jumped, ',')
    RBMK.EventState.LastBlowoutCount = #jumped
    RBMK.EventState.LastBlowoutDuration = longestDuration
    RBMK.EventState.NextBlowout = now + RBMK.BlowoutCooldown
    RBMK.UpdateRPVPressure()
    return steamLoss
end

function RBMK.FuelChannelLeakCheck()
    -- THIS CHECK COLUMN TEMP! Which contributes to actual channel leaking.
    if RBMK.EventState.Failed then return false end
    local now = RBMK.GetTime()
    if now < (RBMK.EventState.NextLeakCheck or 0) then return false end
    RBMK.EventState.NextLeakCheck = now + RBMK.FuelLeakCheckInterval

    local offenders = {}
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.GetCell(x, y)
            if cell and cell.type == RBMK.CELL_FUEL and not cell.leaking then
                local hottest = cell.heat or 0
                if hottest >= RBMK.FuelLeakTemperature then
                    table.insert(offenders, {x = x, y = y, cell = cell, heat = hottest})
                end
            end
        end
    end

    if #offenders <= 0 then return false end
    local offender = offenders[math.random(1, #offenders)]
    local overTemp = offender.heat - RBMK.FuelLeakTemperature
    local chance = RBMK.FuelLeakBaseChance + math.floor(overTemp / RBMK.FuelLeakTemperatureStep) * RBMK.FuelLeakChanceStep
    chance = math.Clamp(chance, 0, 100)
    if math.Rand(0, 100) > chance then return false end

    RBMK.FuelChannelLeak(offender.x, offender.y, offender.cell)
    return true
end

function RBMK.FuelChannelLeak(x, y, cell)
    cell = cell or RBMK.GetCell(x, y)
    if not cell or cell.type ~= RBMK.CELL_FUEL then return false end
    if cell.leaking then return true end

    cell.leaking = true
    cell.leakStarted = RBMK.GetTime()
    RBMK.EventState.LastFuelLeak = {x = x, y = y, time = cell.leakStarted}
    RBMK.FireRelay(RBMK.FuelLeakRelay)
    print(string.format('[LITHOS_RBMK] Fuel channel leak at %d,%d', x or 0, y or 0))
    return true
end

function RBMK.DoFuelLeakStep()
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.GetCell(x, y)
            if cell and cell.type == RBMK.CELL_FUEL and cell.leaking then
                local heatAdd = RBMK.FuelLeakHeatRate * RBMK.TickInterval
                cell.heat = (cell.heat or 20) + heatAdd
                cell.skinHeat = (cell.skinHeat or cell.heat) + heatAdd * 1.5
                cell.coreHeat = (cell.coreHeat or cell.skinHeat) + heatAdd * 2
                if cell.heat >= RBMK.FuelMeltdownTemperature and not cell.meltingDown then
                    RBMK.FuelMeltdown(x, y, cell)
                end
            end
        end
    end
end

function RBMK.FuelMeltdown(x, y, cell)
    cell = cell or RBMK.GetCell(x, y)
    if not cell or cell.meltingDown then return false end

    cell.meltingDown = true
    cell.meltdownStarted = RBMK.GetTime()
    RBMK.EventState.LastMeltdown = {x = x, y = y, time = cell.meltdownStarted}
    RBMK.FireRelay(RBMK.FuelMeltdownRelay)
    print(string.format('[LITHOS_RBMK] Fuel meltdown started at %d,%d', x or 0, y or 0))

    timer.Simple(RBMK.FuelMeltdownDelay, function()
        if RBMK and RBMK.EventState and not RBMK.EventState.Failed then
            RBMK.CatastrophicFailure('fuel_meltdown')
        end
    end)
    return true
end

function RBMK.CatastrophicFailure(reason)
    if RBMK.EventState.Failed then return false end
    RBMK.EventState.Failed = true
    RBMK.EventState.FailureReason = reason or 'unknown'
    RBMK.EventState.FailureTime = RBMK.GetTime()
    RBMK.FireRelay(RBMK.CatastrophicFailureRelay)
    if timer.Exists('RBMK_Tick') then timer.Remove('RBMK_Tick') end
    print('[LITHOS_RBMK] Catastrophic failure: ' .. tostring(RBMK.EventState.FailureReason))
    timer.Simple(RBMK.CatastrophicClearDelay, function()
        if RBMK then RBMK.ClearReactorData() end
    end)
    return true
end

function RBMK.ClearReactorData()
    RBMK.Width = 0
    RBMK.Height = 0
    RBMK.Matrix = {}
    RBMK.Rods = {}
    RBMK.Water = 0
    RBMK.Steam = 0
    RBMK.MaxWater = 0
    RBMK.MaxSteam = 0
    RBMK.HardMaxSteam = 0
    RBMK.RPVPressure = 0
    RBMK.TotalVolume = 0
    RBMK.SteamSpace = 0
    RBMK.MinSteamSpace = 0
end

function RBMK.DoPressureEventStep()
    local pressure = RBMK.UpdateRPVPressure()
    RBMK.EventState.LastPressure = pressure
    if pressure >= RBMK.CatastrophicPressure then
        RBMK.CatastrophicFailure('overpressure')
        return
    end

    if pressure >= RBMK.BlowoutPressure then RBMK.BlowoutSteam() end
end

function RBMK.DoEventStep()
    if RBMK.EventState.Failed then return end
    RBMK.DoPressureEventStep()
    RBMK.FuelChannelLeakCheck()
    RBMK.DoFuelLeakStep()
end

-- =========================================
-- Functions
-- =========================================
function RBMK.CellToWorld(x, y)
    return RBMK.WorldOrigin + Vector((x - 1) * RBMK.CellSpacing, (y - 1) * RBMK.CellSpacing, 0)
end

function RBMK.UpdateTelemetry()
    local totalHeat = 0
    local validCells = 0
    local maxHeat = 0
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type ~= RBMK.CELL_VOID then
                totalHeat = totalHeat + (cell.heat or 0)
                validCells = validCells + 1
                if cell.heat > maxHeat then maxHeat = cell.heat end
            end
        end
    end

    RBMK.AverageHeat = 0
    if validCells > 0 then RBMK.AverageHeat = totalHeat / validCells end
    RBMK.MaxHeat = maxHeat
    RBMK.UpdateRPVPressure()
end
