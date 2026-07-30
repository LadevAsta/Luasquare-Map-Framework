DFR = DFR or {}
DFR.ReactorMachine = DFR.ReactorMachine or {}

DFR.ReactorMachine.DefaultPositions = DFR.ReactorMachine.DefaultPositions or {
    upperDeployed = 'dfr_pt_upper_1',
    upperRetracted = 'dfr_pt_upper_2',
    lowerDeployed = 'dfr_pt_lower_1',
    lowerRetracted = 'dfr_pt_lower_2',
    stabilizerDeployed = 'dfr_pt_stab_1',
    stabilizerService = 'dfr_pt_stab_2',
    stabilizerRetracted = 'dfr_pt_stab_3'
}

local function mergeDefaults(data, defaults)
    data = data or {}
    local out = {}
    for key, value in pairs(defaults or {}) do out[key] = value end
    for key, value in pairs(data) do out[key] = value end
    return out
end

local function registerBinding(id, targetName, class, notes, all)
    return DFR.RegisterBinding(id, {
        targetName = targetName,
        class = class,
        required = false,
        all = all and true or false,
        notes = notes
    })
end

local function registerPathTrack(id, targetName, notes)
    return registerBinding(id, targetName, 'path_track', notes)
end

local function registerDoor(id, targetName, label)
    registerBinding(id, targetName, 'func_door_rotating', label)
    return DFR.RegisterMachinery(id, {
        type = 'door',
        binding = id,
        label = label or id,
        openInput = 'Open',
        closeInput = 'Close',
        state = 'closed'
    })
end

local function registerRotator(id, targetName, label, spinSpeed)
    registerBinding(id, targetName, 'func_rotating', label)
    return DFR.RegisterMachinery(id, {
        type = 'rotator',
        binding = id,
        label = label or id,
        spinSpeed = spinSpeed or 40,
        startInput = 'Start',
        stopInput = 'Stop',
        setSpeedInput = 'SetSpeed'
    })
end

function DFR.RegisterDefaultReactorMachineLayout(options)
    options = options or {}
    local positions = mergeDefaults(options.positions, DFR.ReactorMachine.DefaultPositions)
    DFR.ReactorMachine.Positions = positions
    DFR.ReactorMachine.Registered = true

    DFR.RegisterMachineryPath('upper_shaft_path', {
        nodes = {
            positions.upperDeployed,
            positions.upperRetracted
        }
    })

    DFR.RegisterMachineryPath('lower_shaft_path', {
        nodes = {
            positions.lowerDeployed,
            positions.lowerRetracted
        }
    })

    DFR.RegisterMachineryPath('stabilizer_shaft_path', {
        nodes = {
            positions.stabilizerDeployed,
            positions.stabilizerService,
            positions.stabilizerRetracted
        },
        switches = {
            {
                node = positions.stabilizerService,
                to = positions.stabilizerRetracted,
                binding = 'stabilizer_service_path_switch',
                enableInput = 'EnableAlternatePath',
                disableInput = 'DisableAlternatePath'
            }
        }
    })

    registerPathTrack('stabilizer_service_path_switch', positions.stabilizerService, 'Switches stabilizer train from service node to retracted branch.')

    registerBinding('upper_shaft_train', options.upperTrain or 'dfr_train_upper', 'func_tracktrain', 'Upper reactor shaft train')
    registerBinding('lower_shaft_train', options.lowerTrain or 'dfr_train_lower', 'func_tracktrain', 'Lower reactor shaft train')
    registerBinding('stabilizer_shaft_train', options.stabilizerTrain or 'dfr_train_stab', 'func_tracktrain', 'Stabilizer shaft train')

    DFR.RegisterMachinery('upper_shaft_train', {
        type = 'tracktrain',
        binding = 'upper_shaft_train',
        label = 'Upper Shaft',
        path = 'upper_shaft_path',
        initialNode = positions.upperRetracted,
        deployNode = positions.upperDeployed,
        retractNode = positions.upperRetracted
    })

    DFR.RegisterMachinery('lower_shaft_train', {
        type = 'tracktrain',
        binding = 'lower_shaft_train',
        label = 'Lower Shaft',
        path = 'lower_shaft_path',
        initialNode = positions.lowerRetracted,
        deployNode = positions.lowerDeployed,
        retractNode = positions.lowerRetracted
    })

    DFR.RegisterMachinery('stabilizer_shaft_train', {
        type = 'tracktrain',
        binding = 'stabilizer_shaft_train',
        label = 'Stabilizer Shaft',
        path = 'stabilizer_shaft_path',
        initialNode = positions.stabilizerRetracted,
        deployNode = positions.stabilizerDeployed,
        retractNode = positions.stabilizerRetracted
    })

    registerRotator('stabilizer_rotator', options.stabilizerRotator or 'dfr_rot_stab', 'Stabilizer Rotator', options.stabilizerSpinSpeed or 40)

    for i = 1, 4 do
        registerDoor('stabilizer_arm_' .. i, options['stabilizerArm' .. i] or ('dfr_rot_stab_arm_' .. i), 'Stabilizer Arm ' .. i)
    end

    registerRotator('upper_director_lens_rotator_1', options.upperLensRotator1 or 'dfr_rot_shaft_upper_1', 'Upper Director Lens 1', options.lensSpinSpeed or 20)
    registerRotator('upper_director_lens_rotator_2', options.upperLensRotator2 or 'dfr_rot_shaft_upper_2', 'Upper Director Lens 2', options.lensSpinSpeed or 20)
    registerRotator('lower_director_lens_rotator_1', options.lowerLensRotator1 or 'dfr_rot_shaft_lower_1', 'Lower Director Lens 1', options.lensSpinSpeed or 20)
    registerRotator('lower_director_lens_rotator_2', options.lowerLensRotator2 or 'dfr_rot_shaft_lower_2', 'Lower Director Lens 2', options.lensSpinSpeed or 20)

    DFR.Log('Default DFR reactor machine layout registered')
    return true
end

local function run(ids, fn)
    local ok = true
    local any = false
    for _, id in ipairs(ids) do
        if DFR.GetMachinery(id) then
            any = true
            ok = fn(id) and ok
        end
    end
    return any and ok
end

function DFR.DeployReactorMachine()
    return run({
        'upper_shaft_train',
        'lower_shaft_train',
        'stabilizer_shaft_train'
    }, DFR.DeployMachinery)
end

function DFR.RetractReactorMachine()
    run({
        'stabilizer_arm_1',
        'stabilizer_arm_2',
        'stabilizer_arm_3',
        'stabilizer_arm_4'
    }, DFR.CloseMachinery)

    run({
        'stabilizer_rotator',
        'upper_director_lens_rotator_1',
        'upper_director_lens_rotator_2',
        'lower_director_lens_rotator_1',
        'lower_director_lens_rotator_2'
    }, DFR.StopMachinery)

    return run({
        'stabilizer_shaft_train',
        'upper_shaft_train',
        'lower_shaft_train'
    }, DFR.RetractMachinery)
end

function DFR.ActivateReactorStabilizerMachine()
    run({
        'stabilizer_rotator'
    }, DFR.StartMachinery)

    return run({
        'stabilizer_arm_1',
        'stabilizer_arm_2',
        'stabilizer_arm_3',
        'stabilizer_arm_4'
    }, DFR.OpenMachinery)
end

function DFR.DeactivateReactorStabilizerMachine()
    run({
        'stabilizer_arm_1',
        'stabilizer_arm_2',
        'stabilizer_arm_3',
        'stabilizer_arm_4'
    }, DFR.CloseMachinery)

    return run({
        'stabilizer_rotator'
    }, DFR.StopMachinery)
end

function DFR.SetDirectorLensMachineryActive(active)
    local fn = active and DFR.StartMachinery or DFR.StopMachinery
    return run({
        'upper_director_lens_rotator_1',
        'upper_director_lens_rotator_2',
        'lower_director_lens_rotator_1',
        'lower_director_lens_rotator_2'
    }, fn)
end
