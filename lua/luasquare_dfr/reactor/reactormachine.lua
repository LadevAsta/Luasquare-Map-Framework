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

    DFR.RegisterDefaultReactorMachineTimelines({
        initialRetractionDelay = options.initialRetractionDelay,
        timelineSources = options.timelineSources or options.timelines
    })

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

local REACTOR_TIMELINE_ROOT = 'data_static/luasquare_timeline/_components/dfr.reactor_machine/'

local function reactorMachineCleanup()
    closeStabilizerArms()
    DFR.StopMachinery('stabilizer_rotator')
    stopMovingShafts()
    return true
end

function DFR.RegisterDefaultReactorMachineTimelines(options)
    if type(options) ~= 'table' then options = {initialRetractionDelay = options} end
    local initialDelay = math.max(
        tonumber(options.initialRetractionDelay) or DFR.ReactorMachine.InitialRetractionDelay or 10,
        0.01
    )
    DFR.ReactorMachine.ConfiguredInitialRetractionDelay = initialDelay

    local reactorChildren = {
        upper_shaft = 'machinery:upper_shaft_train',
        lower_shaft = 'machinery:lower_shaft_train',
        stabilizer_shaft = 'machinery:stabilizer_shaft_train',
        stabilizer_rotator = 'machinery:stabilizer_rotator',
        stabilizer_arm_1 = 'machinery:stabilizer_arm_1',
        stabilizer_arm_2 = 'machinery:stabilizer_arm_2',
        stabilizer_arm_3 = 'machinery:stabilizer_arm_3',
        stabilizer_arm_4 = 'machinery:stabilizer_arm_4'
    }
    DFR.RegisterTimelineComponent('reactor_machine', {
        type = 'dfr.reactor_machine',
        label = 'DFR Reactor Machine',
        children = reactorChildren,
        actions = {
            deploy_primary_shafts = {
                kind = 'marker', label = 'Deploy primary shafts', seekPolicy = 'apply',
                execute = function() return deployPrimaryShafts() end
            },
            deploy_stabilizer_shaft = {
                kind = 'marker', label = 'Deploy stabilizer shaft', seekPolicy = 'apply',
                execute = function() return deployStabilizerShaft() end
            },
            safe_retract = {
                kind = 'marker', label = 'Safe retract', seekPolicy = 'apply',
                execute = function() return commandRetraction() end
            },
            prime_initial_retract = {
                kind = 'marker', label = 'Prime initial retraction', seekPolicy = 'apply',
                execute = function() DFR.PrimeReactorMachineForInitialRetraction() return true end
            },
            stabilizer_open_and_spin = {
                kind = 'marker', label = 'Open arms and start rotor', seekPolicy = 'apply',
                execute = function()
                    local rotor = DFR.StartMachinery('stabilizer_rotator')
                    return openStabilizerArms() and rotor
                end
            },
            open_stabilizer_arms = {
                kind = 'marker', label = 'Open stabilizer arms', seekPolicy = 'apply',
                execute = function() return openStabilizerArms() end
            },
            close_stabilizer_arms = {
                kind = 'marker', label = 'Close stabilizer arms', seekPolicy = 'apply',
                execute = function() return closeStabilizerArms() end
            },
            stop_stabilizer_rotor = {
                kind = 'marker', label = 'Stop stabilizer rotor', seekPolicy = 'apply',
                execute = function() return DFR.StopMachinery('stabilizer_rotator') end
            }
        },
        safeReset = reactorMachineCleanup
    })
    for _, componentId in pairs(reactorChildren) do
        local component = LUASQUARE_TIMELINE.Components[componentId]
        if component then component.parent = 'reactor_machine' end
    end
    LUASQUARE_TIMELINE.CatalogRevision = LUASQUARE_TIMELINE.CatalogRevision + 1
    LUASQUARE_TIMELINE.RegisterLifecycleHandler('dfr.reactor_machine.cancel', function()
        return reactorMachineCleanup()
    end)
    DFR.ReactorMachine.TimelineOwner = DFR.GetTimelineOwner('reactor_machine')

    local sources = options.timelineSources or options.timelines or {}
    local names = {
        'deploy', 'retract', 'initial_retract', 'stabilizer_warmup',
        'stabilizer_shutdown', 'pre_annihilation_gate'
    }
    local ok = true
    for _, name in ipairs(names) do
        local sourcePath = sources[name] or (REACTOR_TIMELINE_ROOT .. name .. '.json')
        local source = sourcePath
        if name == 'initial_retract' and initialDelay ~= 10 and not sources[name] then
            local compiled = LUASQUARE_TIMELINE.Sources[sourcePath]
                or LUASQUARE_TIMELINE.LoadSource(sourcePath)
            if compiled then
                local adjusted = LUASQUARE_TIMELINE.DeepCopy(compiled.source)
                adjusted.duration = initialDelay
                for _, track in ipairs(adjusted.tracks or {}) do
                    for _, clip in ipairs(track.clips or {}) do clip.at = initialDelay end
                end
                source = adjusted
            end
        end
        ok = DFR.BindComponentTimeline('reactor_machine', name, source) and ok
    end
    return ok
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
