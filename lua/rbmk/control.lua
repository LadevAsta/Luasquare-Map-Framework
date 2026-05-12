RBMK = RBMK or {}

function RBMK.DoControlStep()
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
            end
        end
    end
end

function RBMK.GetRod(name)
    return RBMK.Rods[name]
end

function RBMK.SetRodInsertionByName(name, insertion)
    local rod = RBMK.GetRod(name)
    if not rod then
        print('[%s] Unknown rod: ' .. tostring(name), RBMK.ModelName or 'RBMK')
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

    if not movedSomeRods then print('[%s] No existing rods in group : ' .. tostring(group), RBMK.ModelName or 'RBMK') end
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