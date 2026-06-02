RBMK = RBMK or {}
local ROD_EPSILON = 0.0001

local function clamp01(value)
    return math.Clamp(tonumber(value) or 0, 0, 1)
end

local function rodNeedsMainMovement(cell)
    return math.abs((cell.targetInsertion or 0) - (cell.insertion or 0)) > ROD_EPSILON
end

local function updateAutoRegulatorTarget(cell)
    if not cell.autoRegulator then
        cell.autoTargetInsertion = 0
    else
        local maxInsertion = cell.autoMaxInsertion or RBMK.AutoRegulatorMaxInsertion or 0.1
        cell.autoTargetInsertion = math.Clamp(RBMK.AutoRegulatorTargetInsertion or 0, 0, maxInsertion)
    end
end

local function rodNeedsAutoMovement(cell)
    updateAutoRegulatorTarget(cell)
    return math.abs((cell.autoTargetInsertion or 0) - (cell.autoInsertion or 0)) > ROD_EPSILON
end

local function moveToward(value, target, speed)
    local diff = target - value
    if math.abs(diff) <= speed then return target end
    local dir = diff < 0 and -1 or 1
    return value + dir * speed
end

local function forEachControlRod(callback)
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local column = RBMK.Matrix[x]
            local cell = column and column[y]
            if cell and cell.type == RBMK.CELL_CONTROL then callback(cell, x, y) end
        end
    end
end

function RBMK.GetControlRodPowerState()
    return {
        grid = RBMK.ControlRodPowerGrid,
        breaker = RBMK.ControlRodPowerBreaker,
        demandMW = RBMK.ControlRodPowerDemandMW or 0,
        acceptedMW = RBMK.ControlRodPowerAcceptedMW or 0,
        powered = RBMK.ControlRodPowered ~= false,
        movingCount = RBMK.ControlRodMovingCount or 0,
        blockedCount = RBMK.ControlRodBlockedCount or 0,
        stuckCount = RBMK.ControlRodStuckCount or 0
    }
end

function RBMK.UpdateControlRodPower(movingCount)
    movingCount = math.max(math.floor(tonumber(movingCount) or 0), 0)
    local demandMW = movingCount * math.max(tonumber(RBMK.ControlRodMWPerRod) or 0, 0)
    local gridName = RBMK.ControlRodPowerGrid
    local breakerName = RBMK.ControlRodPowerBreaker
    local acceptedMW = 0
    local powered = true
    if demandMW > 0 and gridName then
        powered = false
        if LUASQUARE_POWERGRID and LUASQUARE_POWERGRID.CanServeLoad and LUASQUARE_POWERGRID.SubmitLoad and LUASQUARE_POWERGRID.CanServeLoad(gridName, demandMW, breakerName) then
            acceptedMW = LUASQUARE_POWERGRID.SubmitLoad(gridName, 'rbmk_control_rods', demandMW, breakerName)
            if RBMK.ControlRodPowerAllOrNothing == false then
                powered = acceptedMW > 0
            else
                powered = acceptedMW >= demandMW * 0.999
            end
        end
    elseif demandMW > 0 and RBMK.ControlRodPowerRequired then
        powered = false
    end

    RBMK.ControlRodPowerDemandMW = demandMW
    RBMK.ControlRodPowerAcceptedMW = acceptedMW
    RBMK.ControlRodPowered = powered
    RBMK.ControlRodMovingCount = movingCount
    return powered, acceptedMW, demandMW
end

function RBMK.GetScramStuckChance(rod)
    if not rod or not rod.graphiteTip then return 0 end
    local baseChance = tonumber(RBMK.ScramStuckBaseChance) or 0.01
    local damageChance = tonumber(RBMK.ScramStuckDamageChance) or 0.12
    local maxChance = tonumber(RBMK.ScramStuckMaxChance) or 0.25
    local integrity = math.Clamp(tonumber(RBMK.IntegrityScore) or 1, 0, 1)
    return math.Clamp(baseChance + damageChance * (1 - integrity), 0, maxChance)
end

function RBMK.GetScramStuckInsertion(rod)
    local current = clamp01(rod and rod.insertion or 0)
    local minInsertion = clamp01(RBMK.ScramStuckMinInsertion or 0.20)
    local maxInsertion = clamp01(RBMK.ScramStuckMaxInsertion or 0.35)
    return math.Clamp(math.max(current, minInsertion), minInsertion, maxInsertion)
end

function RBMK.TryScheduleScramStuck(rod)
    if not rod or not rod.graphiteTip then return false end
    if rod.stuck or rod.scramStuck or rod.scramStuckPending then return false end

    local eligibleMax = clamp01(RBMK.ScramStuckEligibleMaxInsertion or 0.40)
    if (rod.insertion or 0) > eligibleMax then return false end

    local chance = RBMK.GetScramStuckChance(rod)
    if math.Rand(0, 1) > chance then return false end

    rod.scramStuck = true
    rod.scramStuckPending = true
    rod.stuckInsertion = RBMK.GetScramStuckInsertion(rod)
    rod.lastStuckReason = 'SCRAM_GRAPHITE_SPIKE'
    return true
end

function RBMK.RepairRod(name)
    local rod = RBMK.GetRod(name)
    if not rod then
        print('[' .. RBMK.ModelName .. '] Unknown rod repair target: ' .. tostring(name))
        return false
    end

    rod.stuck = false
    rod.scramStuck = false
    rod.scramStuckPending = false
    rod.stuckInsertion = nil
    rod.lastStuckReason = nil
    rod.powerBlocked = false
    rod.visualHeld = false
    RBMK.UpdateRodVisual(rod)
    return true
end

function RBMK.RepairAllRods()
    local repaired = 0
    for _, rod in pairs(RBMK.Rods) do
        if rod.stuck or rod.scramStuck or rod.scramStuckPending then repaired = repaired + 1 end
        rod.stuck = false
        rod.scramStuck = false
        rod.scramStuckPending = false
        rod.stuckInsertion = nil
        rod.lastStuckReason = nil
        rod.powerBlocked = false
        rod.visualHeld = false
        RBMK.UpdateRodVisual(rod)
    end
    return repaired
end

function RBMK.DoControlStep()
    RBMK.DoAutoRegulatorStep()
    local movingCount = 0
    local stuckCount = 0

    forEachControlRod(function(cell)
        cell.powerBlocked = false
        if cell.stuck or cell.scramStuckPending or cell.scramStuck then stuckCount = stuckCount + 1 end
        if not cell.stuck and not cell.scramStuckPending then
            if rodNeedsMainMovement(cell) and not cell.scramBoost then movingCount = movingCount + 1 end
            if rodNeedsAutoMovement(cell) then movingCount = movingCount + 1 end
        else
            updateAutoRegulatorTarget(cell)
        end
    end)

    local powered = RBMK.UpdateControlRodPower(movingCount)
    local blockedCount = 0

    forEachControlRod(function(cell)
        local previousInsertion = cell.insertion or 0
        local canMoveMain = powered or cell.scramBoost
        local needsMain = rodNeedsMainMovement(cell)
        local needsAuto = rodNeedsAutoMovement(cell)
        local rodBlocked = false

        if cell.scramStuckPending and cell.stuckInsertion then
            local speed = (cell.moveSpeed or 0.005) * (RBMK.ControlrodScramBoost or 1)
            cell.insertion = moveToward(cell.insertion or 0, cell.stuckInsertion, speed)
            if (cell.insertion or 0) >= (cell.stuckInsertion or 0) - ROD_EPSILON then
                cell.insertion = cell.stuckInsertion
                cell.stuck = true
                cell.scramStuckPending = false
                RBMK.HoldRodVisual(cell)
            end
        elseif cell.stuck then
            if cell.stuckInsertion then cell.insertion = clamp01(cell.stuckInsertion) end
            RBMK.HoldRodVisual(cell)
        else
            if needsMain then
                if canMoveMain then
                    if cell.visualHeld then RBMK.UpdateRodVisual(cell) end
                    local speed = cell.moveSpeed or 0.005
                    if cell.scramBoost then speed = speed * (RBMK.ControlrodScramBoost or 1) end
                    cell.insertion = moveToward(cell.insertion or 0, cell.targetInsertion or 0, speed)
                else
                    cell.powerBlocked = true
                    rodBlocked = true
                    RBMK.HoldRodVisual(cell)
                end
            end

            if needsAuto then
                if powered then
                    local speed = (RBMK.AutoRegulatorResponseRate or 0.03) * (RBMK.TickInterval or 0.1)
                    cell.autoInsertion = moveToward(cell.autoInsertion or 0, cell.autoTargetInsertion or 0, speed)
                else
                    cell.powerBlocked = true
                    rodBlocked = true
                end
            end

            if cell.scramBoost and (cell.insertion or 0) >= 0.95 then cell.scramBoost = false end
        end

        if rodBlocked then blockedCount = blockedCount + 1 end

        local delta = (cell.insertion or 0) - (cell.lastInsertion or previousInsertion)
        cell.inserting = delta > 0
        if math.abs(delta) > ROD_EPSILON then
            cell.stationaryTime = 0
            if cell.inserting then cell.movingTime = math.min((cell.movingTime or 0) + (RBMK.TickInterval or 0.1), 10) end
        else
            cell.stationaryTime = (cell.stationaryTime or 0) + (RBMK.TickInterval or 0.1)
            if cell.stationaryTime >= 10 then cell.movingTime = 0 end
        end

        cell.lastInsertion = cell.insertion
    end)

    RBMK.ControlRodBlockedCount = blockedCount
    RBMK.ControlRodStuckCount = stuckCount
end

function RBMK.DoAutoRegulatorStep()
    local currentMW = RBMK.LastThermalMW or 0
    local targetMW = RBMK.AutoRegulatorTargetMW or 0
    local dt = RBMK.TickInterval or 0.1
    local maxInsertion = RBMK.AutoRegulatorMaxInsertion or 0.1

    if not RBMK.AutoRegulatorEnabled or targetMW <= 0 then
        RBMK.AutoRegulatorTargetInsertion = 0
        RBMK.AutoRegulatorIntegral = 0
        RBMK.AutoRegulatorLastError = 0
        return
    end

    local error = currentMW - targetMW
    local control
    if RBMK.AutoRegulatorUsePID then
        RBMK.AutoRegulatorIntegral = math.Clamp(
            (RBMK.AutoRegulatorIntegral or 0) + error * dt,
            -(RBMK.AutoRegulatorIntegralLimit or 10000),
            RBMK.AutoRegulatorIntegralLimit or 10000
        )
        local derivative = (error - (RBMK.AutoRegulatorLastError or 0)) / math.max(dt, 0.0001)
        RBMK.AutoRegulatorLastError = error
        control = error * (RBMK.AutoRegulatorKp or 0) +
            RBMK.AutoRegulatorIntegral * (RBMK.AutoRegulatorKi or 0) +
            derivative * (RBMK.AutoRegulatorKd or 0)
    else
        RBMK.AutoRegulatorLastError = error
        control = error * (RBMK.AutoRegulatorKp or 0)
    end

    local target = (RBMK.AutoRegulatorTargetInsertion or 0) + control
    RBMK.AutoRegulatorTargetInsertion = math.Clamp(target, 0, maxInsertion)
end

function RBMK.UpdateAutoRegulatorRod(cell)
    updateAutoRegulatorTarget(cell)

    local speed = (RBMK.AutoRegulatorResponseRate or 0.03) * (RBMK.TickInterval or 0.1)
    cell.autoInsertion = moveToward(cell.autoInsertion or 0, cell.autoTargetInsertion or 0, speed)
end

function RBMK.SetAutoRegulatorEnabled(enabled)
    RBMK.AutoRegulatorEnabled = enabled and true or false
end

function RBMK.SetAutoRegulatorPIDEnabled(enabled)
    RBMK.AutoRegulatorUsePID = enabled and true or false
    RBMK.AutoRegulatorIntegral = 0
    RBMK.AutoRegulatorLastError = 0
end

function RBMK.SetAutoRegulatorTargetMW(targetMW)
    RBMK.AutoRegulatorTargetMW = math.max(tonumber(targetMW) or 0, 0)
end

function RBMK.SetRodAutoRegulator(name, enabled, maxInsertion)
    local rod = RBMK.GetRod(name)
    if not rod then
        print('[' .. RBMK.ModelName .. '] Unknown auto regulator rod: ' .. tostring(name))
        return false
    end

    rod.autoRegulator = enabled and true or false
    if maxInsertion then rod.autoMaxInsertion = math.Clamp(tonumber(maxInsertion) or 0, 0, 1) end
    if not rod.autoRegulator then rod.autoTargetInsertion = 0 end
    return true
end

function RBMK.SetGroupAutoRegulator(group, enabled, maxInsertion)
    local movedSomeRods = false
    for _, rod in pairs(RBMK.Rods) do
        if rod.group == group then
            rod.autoRegulator = enabled and true or false
            if maxInsertion then rod.autoMaxInsertion = math.Clamp(tonumber(maxInsertion) or 0, 0, 1) end
            if not rod.autoRegulator then rod.autoTargetInsertion = 0 end
            movedSomeRods = true
        end
    end

    if not movedSomeRods then print('[' .. RBMK.ModelName .. '] No existing rods in group : ' .. tostring(group)) end
    return movedSomeRods
end

function RBMK.SetAllAutoRegulators(enabled, maxInsertion)
    for _, rod in pairs(RBMK.Rods) do
        rod.autoRegulator = enabled and true or false
        if maxInsertion then rod.autoMaxInsertion = math.Clamp(tonumber(maxInsertion) or 0, 0, 1) end
        if not rod.autoRegulator then rod.autoTargetInsertion = 0 end
    end
end

function RBMK.GetRod(name)
    return RBMK.Rods[name]
end

function RBMK.SetRodInsertionByName(name, insertion)
    local rod = RBMK.GetRod(name)
    if not rod then
        print('[' .. RBMK.ModelName .. '] Unknown rod: ' .. tostring(name))
        return
    end

    insertion = math.Clamp(insertion, 0, 1)
    rod.targetInsertion = insertion
    RBMK.UpdateRodVisual(rod)
end

function RBMK.SetGroupInsertion(group, insertion)
    insertion = math.Clamp(insertion, 0, 1)
    local movedSomeRods = false
    for _, rod in pairs(RBMK.Rods) do
        if rod.group == group then
            rod.targetInsertion = insertion
            movedSomeRods = true
            RBMK.UpdateRodVisual(rod)
        end
    end

    if not movedSomeRods then print('[' .. RBMK.ModelName .. '] No existing rods in group : ' .. tostring(group)) end
end

function RBMK.SetReflectorState(x, y, enabled)
    local cell = RBMK.GetCell(x, y)
    if not cell then return false end
    if cell.type ~= RBMK.CELL_REFLECTOR then return false end
    cell.reflectorIn = enabled and true or false
    return true
end

function RBMK.ToggleReflector(x, y)
    local cell = RBMK.GetCell(x, y)
    if not cell then return false end
    if cell.type ~= RBMK.CELL_REFLECTOR then return false end
    cell.reflectorIn = not cell.reflectorIn
    return true
end

function RBMK.SetNeutronSourceState(x, y, closed)
    local cell = RBMK.GetCell(x, y)
    if not cell then return false end
    if cell.type ~= RBMK.CELL_SOURCE then return false end
    cell.closedSource = closed and true or false
    return true
end

function RBMK.ToggleNeutronSource(x, y)
    local cell = RBMK.GetCell(x, y)
    if not cell then return false end
    if cell.type ~= RBMK.CELL_SOURCE then return false end
    cell.closedSource = not cell.closedSource
    return true
end

function RBMK.GetRodVisualSpeed(cell)
    local moveDistance = RBMK.RodMoveDistance or 64
    local tickRate = 1 / RBMK.TickInterval
    if cell.scramBoost then return cell.moveSpeed * moveDistance * tickRate * RBMK.ControlrodScramBoost end
    return cell.moveSpeed * moveDistance * tickRate
end

function RBMK.GetRodVisualTargetInsertion(cell)
    if cell.stuck then return cell.insertion or cell.stuckInsertion or cell.targetInsertion or 0 end
    if cell.scramStuckPending and cell.stuckInsertion then return cell.stuckInsertion end
    return cell.targetInsertion or 0
end

function RBMK.UpdateRodVisual(cell)
    if not cell.visualEnt then return end
    local ent = ents.FindByName(cell.visualEnt)[1]
    if not IsValid(ent) then return end
    local speed = RBMK.GetRodVisualSpeed(cell)
    ent:Fire('SetSpeed', tostring(speed))
    ent:Fire('SetPosition', tostring(1 - RBMK.GetRodVisualTargetInsertion(cell)))
    cell.visualHeld = false
end

function RBMK.HoldRodVisual(cell)
    if not cell.visualEnt then return end
    if cell.visualHeld and math.abs((cell.visualHoldInsertion or 0) - (cell.insertion or 0)) <= ROD_EPSILON then return end
    local ent = ents.FindByName(cell.visualEnt)[1]
    if not IsValid(ent) then return end
    ent:Fire('SetSpeed', '0')
    ent:Fire('SetPosition', tostring(1 - (cell.insertion or 0)))
    cell.visualHeld = true
    cell.visualHoldInsertion = cell.insertion or 0
end

function RBMK.SCRAM()
    for _, rod in pairs(RBMK.Rods) do
        rod.targetInsertion = 1
        rod.scramBoost = true
        RBMK.TryScheduleScramStuck(rod)
        RBMK.UpdateRodVisual(rod)
    end
end
