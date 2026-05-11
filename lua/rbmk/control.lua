RBMK = RBMK or {}
function RBMK.DoControlStep()
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type == RBMK.CELL_CONTROL then
                local diff = cell.targetInsertion - cell.insertion
                local speed = cell.moveSpeed or 0.005
                if cell.scramBoost then
                    speed = speed * RBMK.ControlrodScramBoost or 2
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
        print('[RBMK] Unknown rod: ' .. tostring(name))
        return
    end

    insertion = math.Clamp(insertion, 0, 1)
    rod.targetInsertion = insertion
end

function RBMK.SetGroupInsertion(group, insertion)
    insertion = math.Clamp(insertion, 0, 1)
    local movedSomeRods = false
    for _, rod in pairs(RBMK.Rods) do
        if rod.group == group then
            rod.targetInsertion = insertion
            movedSomeRods = true
        end
    end

    if not movedSomeRods then print('[RBMK] No existing rods in group : ' .. tostring(group)) end
end

function RBMK.SCRAM()
    for _, rod in pairs(RBMK.Rods) do
        rod.targetInsertion = 1
        rod.scramBoost = true
    end
end