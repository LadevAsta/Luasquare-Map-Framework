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
DFR.ReactorMachine.InitialRetractionDelay = DFR.ReactorMachine.InitialRetractionDelay or 10

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
        speedInputScale = 0.01,
        debug = {
            speed = {
                min = 0,
                max = 100,
                decimals = 1,
                unit = '%'
            }
        },
        startInput = 'Start',
        stopInput = 'Stop',
        setSpeedInput = 'SetSpeed'
    })
end

function DFR.PrimeReactorMachineForInitialRetraction()
    for _, id in ipairs({
        'upper_shaft_train',
        'lower_shaft_train',
        'stabilizer_shaft_train'
    }) do
        local machine = DFR.GetMachinery(id)
        if machine and machine.deployNode then
            -- The Source entity may spawn between nodes even though the logical
            -- default is retracted. Route from the deployed side once so the
            -- initial retract command cannot collapse into a no-op Stop.
            machine.currentNode = machine.deployNode
            machine.destinationNode = nil
            machine.route = nil
            machine.direction = nil
            machine.state = 'initializing'
        end
    end
end

function DFR.ScheduleInitialReactorMachineRetraction(delay)
    local owner = DFR.ReactorMachine.TimelineOwner
    if not owner then return false end
    if delay ~= nil and tonumber(delay) ~= DFR.ReactorMachine.ConfiguredInitialRetractionDelay then
        DFR.RegisterDefaultReactorMachineTimelines(delay)
        owner = DFR.ReactorMachine.TimelineOwner
    end
    return owner:Start('initial_retract', {})
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

    DFR.RegisterDefaultReactorMachineTimelines(options.initialRetractionDelay)

    DFR.Log('Default DFR reactor machine layout registered')
    if options.initialRetraction ~= false then
        DFR.ScheduleInitialReactorMachineRetraction(options.initialRetractionDelay)
    end
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

local function deployPrimaryShafts()
    return run({
        'upper_shaft_train',
        'lower_shaft_train'
    }, DFR.DeployMachinery)
end

local function deployStabilizerShaft()
    return run({'stabilizer_shaft_train'}, DFR.DeployMachinery)
end

local function closeStabilizerArms()
    return run({
        'stabilizer_arm_1',
        'stabilizer_arm_2',
        'stabilizer_arm_3',
        'stabilizer_arm_4'
    }, DFR.CloseMachinery)
end

local function openStabilizerArms()
    return run({
        'stabilizer_arm_1',
        'stabilizer_arm_2',
        'stabilizer_arm_3',
        'stabilizer_arm_4'
    }, DFR.OpenMachinery)
end

local function stopMovingShafts()
    return run({
        'stabilizer_shaft_train',
        'upper_shaft_train',
        'lower_shaft_train'
    }, DFR.StopMachinery)
end

local function commandRetraction()
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

function DFR.SetReactorStabilizerImmediate(active)
    if active then
        run({'stabilizer_rotator'}, DFR.StartMachinery)
        return openStabilizerArms()
    end
    closeStabilizerArms()
    return run({'stabilizer_rotator'}, DFR.StopMachinery)
end

function DFR.RegisterDefaultReactorMachineTimelines(initialRetractionDelay)
    local owner = DFR.CreateTimelineOwner('reactor_machine', {
        defaultConflictPolicy = 'reject'
    })
    DFR.ReactorMachine.TimelineOwner = owner
    local initialDelay = math.max(
        tonumber(initialRetractionDelay) or DFR.ReactorMachine.InitialRetractionDelay or 10,
        0.01
    )
    DFR.ReactorMachine.ConfiguredInitialRetractionDelay = initialDelay

    owner:Register('deploy', {
        label = 'Deploy Reactor Machine',
        channel = 'movement',
        conflictPolicy = 'replace',
        duration = 3,
        steps = {
            { id = 'primary_shafts', at = 0, required = true, action = deployPrimaryShafts },
            { id = 'stabilizer_shaft', at = 3, required = true, action = deployStabilizerShaft }
        },
        onCancel = function() stopMovingShafts() end
    })
    owner:Register('retract', {
        label = 'Retract Reactor Machine',
        channel = 'movement',
        conflictPolicy = 'replace',
        duration = 0,
        steps = {
            { id = 'safe_retract', at = 0, required = true, action = commandRetraction }
        },
        onCancel = function() stopMovingShafts() end
    })
    owner:Register('initial_retract', {
        label = 'Initial Delayed Retraction',
        channel = 'bootstrap',
        conflictPolicy = 'replace',
        duration = initialDelay,
        cancelChildrenOnComplete = false,
        steps = {
            {
                id = 'initial_retract',
                at = initialDelay,
                required = true,
                action = function(context, instance)
                    DFR.PrimeReactorMachineForInitialRetraction()
                    return DFR.TimelineRegistry:StartChild(
                        instance, owner, 'retract', { initial = true }, { role = 'movement' }
                    )
                end
            }
        }
    })
    owner:Register('stabilizer_warmup', {
        label = 'Stabilizer Warm-up',
        channel = 'stabilizer',
        conflictPolicy = 'replace',
        duration = 5,
        steps = {
            {
                id = 'open_and_spin', at = 0, required = true,
                action = function()
                    local rotor = DFR.StartMachinery('stabilizer_rotator')
                    return openStabilizerArms() and rotor
                end
            },
            { id = 'close_arms', at = 3, required = true, action = closeStabilizerArms }
        },
        onCancel = function()
            closeStabilizerArms()
            DFR.StopMachinery('stabilizer_rotator')
        end
    })
    owner:Register('stabilizer_shutdown', {
        label = 'Stabilizer Shutdown',
        channel = 'stabilizer',
        conflictPolicy = 'replace',
        duration = 3,
        steps = {
            { id = 'close_arms', at = 0, required = true, action = closeStabilizerArms },
            {
                id = 'stop_rotor', at = 3, required = true,
                action = function() return DFR.StopMachinery('stabilizer_rotator') end
            }
        },
        onCancel = function()
            closeStabilizerArms()
            DFR.StopMachinery('stabilizer_rotator')
        end
    })
    owner:Register('pre_annihilation_gate', {
        label = 'Pre-Annihilation Stabilizer Gate',
        channel = 'stabilizer',
        conflictPolicy = 'replace',
        duration = 3,
        steps = {
            { id = 'force_open', at = 0, required = true, action = openStabilizerArms },
            { id = 'close', at = 3, required = true, action = closeStabilizerArms }
        },
        onCancel = function() closeStabilizerArms() end
    })
    return true
end

function DFR.StartReactorMachineTimeline(name, context, runOptions)
    local owner = DFR.ReactorMachine.TimelineOwner
    if not owner then return false end
    return owner:Start(name, context, runOptions)
end

function DFR.CancelReactorMachineTimeline(name, reason)
    local owner = DFR.ReactorMachine.TimelineOwner
    return owner and owner:Cancel(name, reason) or false
end

function DFR.GetReactorMachineTimelineSnapshot()
    local owner = DFR.ReactorMachine.TimelineOwner
    return owner and owner:GetSnapshot() or { ownerId = 'reactor_machine', definitions = {}, runs = {} }
end

function DFR.IsReactorMachineDeployed()
    local owner = DFR.ReactorMachine.TimelineOwner
    if owner and owner:GetActiveInChannel('movement') then return false end
    for _, id in ipairs({
        'upper_shaft_train',
        'lower_shaft_train',
        'stabilizer_shaft_train'
    }) do
        local machine = DFR.GetMachinery(id)
        if not machine or not DFR.ResolveBinding(machine.binding or id)
            or machine.currentNode ~= machine.deployNode then
            return false
        end
    end
    return true
end

function DFR.DeployReactorMachine()
    return DFR.StartReactorMachineTimeline('deploy', {})
end

function DFR.RetractReactorMachine()
    return DFR.StartReactorMachineTimeline('retract', {})
end

function DFR.ActivateReactorStabilizerMachine()
    return DFR.StartReactorMachineTimeline('stabilizer_warmup', {})
end

function DFR.DeactivateReactorStabilizerMachine()
    return DFR.StartReactorMachineTimeline('stabilizer_shutdown', {})
end

DFR.DeployStartupMachinery = DFR.DeployReactorMachine
DFR.RetractStartupMachinery = DFR.RetractReactorMachine
DFR.ActivateStabilizerMachinery = DFR.ActivateReactorStabilizerMachine
DFR.DeactivateStabilizerMachinery = DFR.DeactivateReactorStabilizerMachine

function DFR.SetDirectorLensMachineryActive(active)
    local fn = active and DFR.StartMachinery or DFR.StopMachinery
    return run({
        'upper_director_lens_rotator_1',
        'upper_director_lens_rotator_2',
        'lower_director_lens_rotator_1',
        'lower_director_lens_rotator_2'
    }, fn)
end
