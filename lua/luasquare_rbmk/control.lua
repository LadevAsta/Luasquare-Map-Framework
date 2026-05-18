RBMK = RBMK or {}
function RBMK.DoControlStep()
    RBMK.DoAutoRegulatorStep()
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type == RBMK.CELL_CONTROL then
                local diff = cell.targetInsertion - cell.insertion
                local speed = cell.moveSpeed or 0.005
                if cell.scramBoost then
                    speed = speed * RBMK.ControlrodScramBoost
                    if cell.insertion >= 0.95 then cell.scramBoost = false end
                end

                if math.abs(diff) <= speed then
                    cell.insertion = cell.targetInsertion
                else
                    local dir = 1
                    if diff < 0 then dir = -1 end
                    cell.insertion = cell.insertion + dir * speed
                end

                local delta = cell.insertion - cell.lastInsertion
                cell.inserting = delta > 0
                if math.abs(delta) > 0.0001 then
                    cell.stationaryTime = 0
                    if cell.inserting then cell.movingTime = math.min(cell.movingTime + RBMK.TickInterval, 10) end
                else
                    cell.stationaryTime = cell.stationaryTime + RBMK.TickInterval
                    if cell.stationaryTime >= 10 then cell.movingTime = 0 end
                end

                cell.lastInsertion = cell.insertion
                RBMK.UpdateAutoRegulatorRod(cell)
            end
        end
    end
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
    if not cell.autoRegulator then
        cell.autoTargetInsertion = 0
    else
        local maxInsertion = cell.autoMaxInsertion or RBMK.AutoRegulatorMaxInsertion or 0.1
        cell.autoTargetInsertion = math.Clamp(RBMK.AutoRegulatorTargetInsertion or 0, 0, maxInsertion)
    end

    local diff = (cell.autoTargetInsertion or 0) - (cell.autoInsertion or 0)
    local speed = (RBMK.AutoRegulatorResponseRate or 0.03) * (RBMK.TickInterval or 0.1)
    if math.abs(diff) <= speed then
        cell.autoInsertion = cell.autoTargetInsertion or 0
    else
        local dir = 1
        if diff < 0 then dir = -1 end
        cell.autoInsertion = (cell.autoInsertion or 0) + dir * speed
    end
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

function RBMK.UpdateRodVisual(cell)
    if not cell.visualEnt then return end
    local ent = ents.FindByName(cell.visualEnt)[1]
    if not IsValid(ent) then return end
    local speed = RBMK.GetRodVisualSpeed(cell)
    ent:Fire('SetSpeed', tostring(speed))
    ent:Fire('SetPosition', tostring(1 - cell.targetInsertion))
end

function RBMK.SCRAM()
    for _, rod in pairs(RBMK.Rods) do
        rod.targetInsertion = 1
        rod.scramBoost = true
        RBMK.UpdateRodVisual(rod)
    end
end
