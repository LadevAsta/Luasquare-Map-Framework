DFR = DFR or {}
DFR.Machinery = DFR.Machinery or {}

local function asString(value)
    if value == nil then return nil end
    return tostring(value)
end

function DFR.RegisterMachinery(id, data)
    data = data or {}
    if not id or id == '' then
        DFR.Log('Rejected machinery with missing id')
        return false
    end

    DFR.Machinery[id] = {
        id = id,
        binding = data.binding or id,
        label = data.label or id,
        class = data.class,
        deployInput = data.deployInput or data.forwardInput or 'StartForward',
        retractInput = data.retractInput or data.backwardInput or 'StartBackward',
        stopInput = data.stopInput or 'Stop',
        openInput = data.openInput or 'Open',
        closeInput = data.closeInput or 'Close',
        startInput = data.startInput or 'Start',
        setSpeedInput = data.setSpeedInput or 'SetSpeed',
        setPositionInput = data.setPositionInput or 'SetPosition',
        deploySpeed = data.deploySpeed,
        retractSpeed = data.retractSpeed,
        spinSpeed = data.spinSpeed,
        state = 'idle',
        lastCommand = nil,
        lastCommandTime = nil
    }

    return true
end

function DFR.GetMachinery(id)
    return DFR.Machinery[id]
end

function DFR.CommandMachinery(id, inputName, value)
    local machine = DFR.GetMachinery(id)
    if not machine then
        DFR.Log('Unknown machinery: ' .. tostring(id))
        return false
    end

    local ok = DFR.FireBinding(machine.binding, inputName, asString(value))
    if ok then
        machine.lastCommand = inputName
        machine.lastCommandTime = DFR.GetTime()
    end

    return ok
end

function DFR.SetMachinerySpeed(id, speed)
    local machine = DFR.GetMachinery(id)
    if not machine then return false end
    return DFR.CommandMachinery(id, machine.setSpeedInput, speed)
end

function DFR.SetMachineryPosition(id, position)
    local machine = DFR.GetMachinery(id)
    if not machine then return false end
    return DFR.CommandMachinery(id, machine.setPositionInput, position)
end

function DFR.DeployMachinery(id)
    local machine = DFR.GetMachinery(id)
    if not machine then return false end
    if machine.deploySpeed ~= nil then DFR.SetMachinerySpeed(id, machine.deploySpeed) end
    local ok = DFR.CommandMachinery(id, machine.deployInput)
    if ok then machine.state = 'deploying' end
    return ok
end

function DFR.RetractMachinery(id)
    local machine = DFR.GetMachinery(id)
    if not machine then return false end
    if machine.retractSpeed ~= nil then DFR.SetMachinerySpeed(id, machine.retractSpeed) end
    local ok = DFR.CommandMachinery(id, machine.retractInput)
    if ok then machine.state = 'retracting' end
    return ok
end

function DFR.StopMachinery(id)
    local machine = DFR.GetMachinery(id)
    if not machine then return false end
    local ok = DFR.CommandMachinery(id, machine.stopInput)
    if ok then machine.state = 'stopped' end
    return ok
end

function DFR.StartMachinery(id)
    local machine = DFR.GetMachinery(id)
    if not machine then return false end
    if machine.spinSpeed ~= nil then DFR.SetMachinerySpeed(id, machine.spinSpeed) end
    local ok = DFR.CommandMachinery(id, machine.startInput)
    if ok then machine.state = 'running' end
    return ok
end

function DFR.OpenMachinery(id)
    local machine = DFR.GetMachinery(id)
    if not machine then return false end
    local ok = DFR.CommandMachinery(id, machine.openInput)
    if ok then machine.state = 'open' end
    return ok
end

function DFR.CloseMachinery(id)
    local machine = DFR.GetMachinery(id)
    if not machine then return false end
    local ok = DFR.CommandMachinery(id, machine.closeInput)
    if ok then machine.state = 'closed' end
    return ok
end

local function runOptional(ids, fn)
    local ok = true
    for _, id in ipairs(ids or {}) do
        if DFR.GetMachinery(id) then
            local result = fn(id)
            ok = result and ok
        end
    end
    return ok
end

function DFR.DeployStartupMachinery()
    return runOptional({
        'reactor_shaft_train',
        'stabilizer_base_train'
    }, DFR.DeployMachinery)
end

function DFR.RetractStartupMachinery()
    runOptional({
        'stabilizer_arm_1',
        'stabilizer_arm_2',
        'stabilizer_arm_3',
        'stabilizer_arm_4'
    }, DFR.CloseMachinery)

    runOptional({
        'stabilizer_base_rotor'
    }, DFR.StopMachinery)

    return runOptional({
        'stabilizer_base_train',
        'reactor_shaft_train'
    }, DFR.RetractMachinery)
end

function DFR.ActivateStabilizerMachinery()
    runOptional({
        'stabilizer_base_rotor'
    }, DFR.StartMachinery)

    return runOptional({
        'stabilizer_arm_1',
        'stabilizer_arm_2',
        'stabilizer_arm_3',
        'stabilizer_arm_4'
    }, DFR.OpenMachinery)
end

function DFR.DeactivateStabilizerMachinery()
    runOptional({
        'stabilizer_arm_1',
        'stabilizer_arm_2',
        'stabilizer_arm_3',
        'stabilizer_arm_4'
    }, DFR.CloseMachinery)

    return runOptional({
        'stabilizer_base_rotor'
    }, DFR.StopMachinery)
end

