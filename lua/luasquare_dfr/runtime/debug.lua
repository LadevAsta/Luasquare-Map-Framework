DFR = DFR or {}
DFR.Debug = DFR.Debug or {}
DFR.LogHistory = DFR.LogHistory or {}

DFR.Debug.CatalogRequestMessage = 'LUASQUARE_DFR_DebugCatalogRequest'
DFR.Debug.CatalogMessage = 'LUASQUARE_DFR_DebugCatalog'

if SERVER and util and util.AddNetworkString then
    util.AddNetworkString(DFR.Debug.CatalogRequestMessage)
    util.AddNetworkString(DFR.Debug.CatalogMessage)
end

function DFR.GetTime()
    if CurTime then return CurTime() end
    return os.clock()
end

function DFR.FormatTime()
    return string.format('%.3f', DFR.GetTime())
end

function DFR.Log(message)
    local line = '[DFR ' .. DFR.FormatTime() .. '] ' .. tostring(message)
    table.insert(DFR.LogHistory, line)
    if #DFR.LogHistory > 100 then table.remove(DFR.LogHistory, 1) end
    print(line)
end

function DFR.GetSnapshot()
    local controls = {}
    for id, control in pairs(DFR.Controls or {}) do
        controls[id] = {
            id = id,
            label = control.label,
            lockedUntil = control.lockedUntil or 0,
            available = DFR.IsControlAvailable and DFR.IsControlAvailable(id) or false,
            lastUseTime = control.lastUseTime
        }
    end

    local missingBindings = {}
    for id, binding in pairs(DFR.Bindings or {}) do
        if binding.missing then
            missingBindings[id] = {
                id = id,
                targetName = binding.targetName,
                required = binding.required and true or false,
                class = binding.class
            }
        end
    end

    return {
        version = DFR.Version,
        state = DFR.GetState and DFR.GetState() or nil,
        previousState = DFR.State and DFR.State.previous or nil,
        running = DFR.Running and true or false,
        halted = DFR.Halted and true or false,
        haltReason = DFR.HaltReason,
        lastTickTime = DFR.LastTickTime,
        lastDeltaTime = DFR.LastDeltaTime,
        lastTransition = DFR.State and DFR.State.lastTransition or nil,
        resources = DFR.Resources or {},
        startup = DFR.GetStartupSnapshot and DFR.GetStartupSnapshot() or {},
        stabilizer = DFR.GetStabilizerState and DFR.GetStabilizerState() or {},
        directorBeam = DFR.GetDirectorBeamState and DFR.GetDirectorBeamState() or {},
        machinery = DFR.GetMachinerySnapshot and DFR.GetMachinerySnapshot() or DFR.Machinery or {},
        coreVisuals = DFR.CoreVisual or {},
        coreState = DFR.CoreState or {},
        timelines = DFR.GetTimelineSnapshot and DFR.GetTimelineSnapshot() or {},
        catalyzers = DFR.GetCatalyzerSnapshot and DFR.GetCatalyzerSnapshot() or {},
        startupLevers = DFR.StartupLevers or {},
        missingBindings = missingBindings,
        controls = controls
    }
end

function DFR.PrintSnapshot()
    local snapshot = DFR.GetSnapshot()
    DFR.Log('State=' .. tostring(snapshot.state) .. ' Running=' .. tostring(snapshot.running) .. ' Halted=' .. tostring(snapshot.halted))
    local resources = snapshot.resources or {}
    DFR.Log(string.format(
        'Matter=%.1f%% Antimatter=%.1f%% FuelCells=%s/%s Ready=%s DECAOS=%s Integrity=%.1f%%',
        tonumber(resources.matterReservePercent) or 0,
        tonumber(resources.antimatterReservePercent) or 0,
        tostring(resources.fuelReceptacleCount or 0),
        tostring((DFR.Config and DFR.Config.StartupRequiredFuelReceptacles) or 3),
        tostring(resources.fuelReceptaclesReady and true or false),
        tostring(resources.decaosOnline and true or false),
        tonumber(resources.superstructureIntegrityPercent) or 0
    ))

    local machineryCount = 0
    local movingCount = 0
    for _, machine in pairs(snapshot.machinery or {}) do
        machineryCount = machineryCount + 1
        if machine.state == 'moving' or machine.state == 'deploying' or machine.state == 'retracting' then
            movingCount = movingCount + 1
        end
    end

    local missingCount = 0
    for _ in pairs(snapshot.missingBindings or {}) do missingCount = missingCount + 1 end
    DFR.Log('BindingsMissing=' .. tostring(missingCount) .. ' Machinery=' .. tostring(machineryCount) .. ' Moving=' .. tostring(movingCount))
end

function DFR.DebugCanRun(ply)
    if not ply then return true end
    if IsValid and not IsValid(ply) then return true end
    if game and game.SinglePlayer and game.SinglePlayer() then return true end
    if ply.IsAdmin and ply:IsAdmin() then return true end
    return false
end

local function copyRange(range)
    if type(range) ~= 'table' then return nil end
    return {
        min = tonumber(range.min) or 0,
        max = tonumber(range.max) or 1,
        decimals = math.max(math.floor(tonumber(range.decimals) or 0), 0),
        unit = tostring(range.unit or '')
    }
end

local function sortByLabel(items)
    table.sort(items, function(a, b)
        local aLabel = string.lower(tostring(a.label or a.id or ''))
        local bLabel = string.lower(tostring(b.label or b.id or ''))
        if aLabel == bLabel then return tostring(a.id or '') < tostring(b.id or '') end
        return aLabel < bLabel
    end)
    return items
end

local function getBindingStatus(id)
    local binding = DFR.SourceBindings and DFR.SourceBindings:Get(id) or nil
    if not binding then
        return {
            id = id,
            targetNames = {},
            foundCount = 0,
            missing = true
        }
    end

    local entities = DFR.SourceBindings:ResolveAll(id)
    local targetNames = DFR.SourceBindings:GetTargetNames(binding)
    return {
        id = id,
        targetName = binding.targetName,
        targetNames = targetNames,
        class = binding.class,
        required = binding.required and true or false,
        all = binding.all and true or false,
        notes = binding.notes,
        foundCount = #entities,
        missing = #entities == 0
    }
end

function DFR.BuildDebugCatalog()
    local currentState = DFR.GetState and DFR.GetState() or nil
    local catalog = {
        wireVersion = 2,
        generatedAt = DFR.GetTime(),
        overview = {
            version = DFR.Version,
            state = currentState,
            previousState = DFR.State and DFR.State.previous or nil,
            running = DFR.Running and true or false,
            halted = DFR.Halted and true or false,
            haltReason = DFR.HaltReason,
            lastDeltaTime = DFR.LastDeltaTime
        },
        validation = DFR.LastBindingValidation,
        states = {},
        controls = {},
        machinery = {},
        visuals = {},
        coreState = DFR.CoreState or {},
        startup = DFR.GetStartupSnapshot and DFR.GetStartupSnapshot() or {},
        stabilizer = DFR.GetStabilizerState and DFR.GetStabilizerState() or {},
        directorBeam = DFR.GetDirectorBeamState and DFR.GetDirectorBeamState() or {},
        timelines = DFR.GetTimelineSnapshot and DFR.GetTimelineSnapshot() or {},
        timelinePhase = DFR.PreAnnihilation and DFR.PreAnnihilation.Phase or nil,
        timelineOwners = {},
        catalyzers = DFR.GetCatalyzerSnapshot and DFR.GetCatalyzerSnapshot() or {},
        reactorMachineTimeline = DFR.GetReactorMachineTimelineSnapshot
            and DFR.GetReactorMachineTimelineSnapshot() or nil,
        bindings = {}
    }

    for id in pairs(DFR.States or {}) do
        table.insert(catalog.states, {
            id = id,
            label = id,
            current = id == currentState,
            allowed = DFR.IsTransitionAllowed and DFR.IsTransitionAllowed(currentState, id) or false
        })
    end

    for id, control in pairs(DFR.Controls or {}) do
        table.insert(catalog.controls, {
            id = id,
            label = control.label or id,
            available = DFR.IsControlAvailable and DFR.IsControlAvailable(id) or false,
            unavailableReason = DFR.GetControlUnavailableReason and DFR.GetControlUnavailableReason(id) or nil,
            lockedUntil = control.lockedUntil or 0,
            lastUseTime = control.lastUseTime,
            lastActor = control.lastActor
        })
    end

    for id, machine in pairs(DFR.Machinery or {}) do
        local binding = getBindingStatus(machine.binding or id)
        local path = DFR.MachineryRegistry and DFR.MachineryRegistry.Paths[machine.path] or nil
        local debugData = machine.debug or {}
        local actions = {}

        if machine.type == 'tracktrain' then
            actions = { deploy = true, retract = true, stop = true, move = true }
        elseif machine.type == 'rotator' then
            actions = { start = true, stop = true, speed = debugData.speed ~= nil }
        elseif machine.type == 'door' then
            actions = { open = true, close = true }
        else
            actions = { start = true, stop = true }
        end

        table.insert(catalog.machinery, {
            id = id,
            label = machine.label or id,
            type = machine.type,
            binding = machine.binding or id,
            targetNames = binding.targetNames,
            class = binding.class,
            foundCount = binding.foundCount,
            missing = binding.missing,
            state = machine.state,
            currentNode = machine.currentNode,
            destinationNode = machine.destinationNode,
            nodes = path and path.nodes or {},
            configuredSpeed = machine.configuredSpeed,
            currentSpeed = machine.currentSpeed,
            sourceSpeed = machine.sourceSpeed,
            speed = copyRange(debugData.speed),
            actions = actions,
            capabilities = actions
        })
    end

    for id, visual in pairs(DFR.CoreVisual or {}) do
        if type(visual) == 'table' and visual.id then
            local binding = getBindingStatus(visual.binding or id)
            local measurement = DFR.GetCoreVisualMeasurement and DFR.GetCoreVisualMeasurement(id, true) or nil
            local debugData = visual.debug or {}
            local canSetRadius = debugData.radiusMeters ~= nil and (tonumber(visual.basisRadiusMeters) or 0) > 0
            table.insert(catalog.visuals, {
                id = id,
                label = visual.label or id,
                kind = visual.kind,
                binding = visual.binding or id,
                targetNames = binding.targetNames,
                class = binding.class,
                foundCount = binding.foundCount,
                missing = binding.missing,
                basisScale = visual.basisScale,
                basisRadiusMeters = visual.basisRadiusMeters,
                basisRadiusHammer = visual.basisRadiusHammer,
                radiusMeters = measurement and measurement.radiusMeters or visual.currentRadiusMeters,
                radiusHammer = measurement and measurement.radiusHammer or visual.currentRadiusHammer,
                multiplier = measurement and measurement.multiplier or visual.currentScaleMultiplier,
                modelScale = measurement and measurement.modelScale or visual.currentModelScale,
                axisFactors = measurement and measurement.axisFactors or visual.commandedAxisFactors,
                axisScales = measurement and measurement.axisScales or visual.commandedAxisScales,
                wobble = visual.wobble and {
                    enabled = visual.wobble.enabled and true or false,
                    amplitudePercent = visual.wobble.amplitudePercent,
                    minIntervalSeconds = visual.wobble.minIntervalSeconds,
                    maxIntervalSeconds = visual.wobble.maxIntervalSeconds,
                    nextAt = visual.wobble.nextAt
                } or nil,
                pulse = visual.pulse and {
                    stage = visual.pulse.stage,
                    startedAt = visual.pulse.startedAt,
                    amplitudePercent = visual.pulse.amplitudePercent
                } or nil,
                lastCommandedEnabled = visual.lastCommandedEnabled,
                radius = copyRange(debugData.radiusMeters),
                transition = copyRange(debugData.transitionSeconds),
                wobbleAmplitude = copyRange(debugData.wobbleAmplitudePercent),
                wobbleInterval = copyRange(debugData.wobbleIntervalSeconds),
                pulseAmplitude = copyRange(debugData.pulseAmplitudePercent),
                actions = {
                    enable = true,
                    disable = true,
                    radius = canSetRadius,
                    wobble = canSetRadius,
                    pulse = canSetRadius
                },
                capabilities = {
                    enable = true,
                    disable = true,
                    radius = canSetRadius,
                    wobble = canSetRadius,
                    pulse = canSetRadius
                }
            })
        end
    end

    for id in pairs(DFR.Bindings or {}) do
        local binding = getBindingStatus(id)
        binding.label = id
        table.insert(catalog.bindings, binding)
    end

    for ownerId, owner in pairs(DFR.TimelineOwners or {}) do
        local snapshot = owner:GetSnapshot()
        snapshot.id = ownerId
        table.insert(catalog.timelineOwners, snapshot)
    end

    sortByLabel(catalog.states)
    sortByLabel(catalog.controls)
    sortByLabel(catalog.machinery)
    sortByLabel(catalog.visuals)
    sortByLabel(catalog.bindings)
    table.sort(catalog.timelineOwners, function(a, b) return tostring(a.id) < tostring(b.id) end)

    catalog.overview.controlCount = #catalog.controls
    catalog.overview.machineCount = #catalog.machinery
    catalog.overview.visualCount = #catalog.visuals
    catalog.overview.bindingCount = #catalog.bindings
    catalog.overview.missingBindingCount = 0
    for _, binding in ipairs(catalog.bindings) do
        if binding.missing then catalog.overview.missingBindingCount = catalog.overview.missingBindingCount + 1 end
    end

    return catalog
end

if SERVER and net and net.Receive then
    local catalogChunkBytes = 60000
    local nextCatalogTransferId = 0
    local nextCatalogRequest = setmetatable({}, { __mode = 'k' })
    net.Receive(DFR.Debug.CatalogRequestMessage, function(_, ply)
        if not DFR or not DFR.DebugCanRun or not DFR.BuildDebugCatalog then return end
        if not DFR.DebugCanRun(ply) then return end

        local now = DFR.GetTime()
        if now < (nextCatalogRequest[ply] or 0) then return end
        nextCatalogRequest[ply] = now + 0.25

        local json = util.TableToJSON(DFR.BuildDebugCatalog(), false)
        local payload = json and util.Compress(json) or nil
        if not payload then
            DFR.Log('Unable to serialize debug catalog')
            return
        end

        nextCatalogTransferId = (nextCatalogTransferId + 1) % 4294967295
        local transferId = nextCatalogTransferId
        local payloadBytes = #payload
        local chunkCount = math.max(math.ceil(payloadBytes / catalogChunkBytes), 1)

        for chunkIndex = 1, chunkCount do
            local firstByte = (chunkIndex - 1) * catalogChunkBytes + 1
            local chunk = string.sub(payload, firstByte, firstByte + catalogChunkBytes - 1)
            net.Start(DFR.Debug.CatalogMessage)
            net.WriteUInt(transferId, 32)
            net.WriteUInt(chunkIndex, 16)
            net.WriteUInt(chunkCount, 16)
            net.WriteUInt(#chunk, 16)
            net.WriteData(chunk, #chunk)
            net.Send(ply)
        end
    end)
end

local function debugCommand(name, callback)
    if not SERVER or not concommand or not concommand.Add then return end

    concommand.Add(name, function(ply, cmd, args)
        if not DFR.DebugCanRun(ply) then
            DFR.Log('Rejected debug command ' .. tostring(name) .. ' from non-admin player')
            return
        end

        local ok, err = pcall(callback, ply, args or {})
        if not ok then DFR.Halt('Debug command ' .. tostring(name) .. ' failed: ' .. tostring(err)) end
    end)
end

local function arg(args, index)
    if not args then return nil end
    local value = args[index]
    if value == nil or value == '' then return nil end
    return value
end

local function boolArg(value)
    value = tostring(value or ''):lower()
    return value == '1' or value == 'true' or value == 'yes' or value == 'on'
end

debugCommand('luasquare_dfr_start', function()
    DFR.Start()
end)

debugCommand('luasquare_dfr_stop', function(ply, args)
    DFR.Stop(arg(args, 1) or 'debug command')
end)

debugCommand('luasquare_dfr_snapshot', function()
    DFR.PrintSnapshot()
end)

debugCommand('luasquare_dfr_halt', function(ply, args)
    DFR.Halt(arg(args, 1) or 'debug halt')
end)

debugCommand('luasquare_dfr_transition', function(ply, args)
    DFR.RequestTransition(arg(args, 1), arg(args, 2) or 'debug transition', ply)
end)

debugCommand('luasquare_dfr_use_control', function(ply, args)
    DFR.UseControl(arg(args, 1), ply, arg(args, 2))
end)

debugCommand('luasquare_dfr_register_v2_defaults', function()
    if DFR.RegisterDefaultReactorMachineLayout then DFR.RegisterDefaultReactorMachineLayout() end
    if DFR.RegisterDefaultCoreVisuals then DFR.RegisterDefaultCoreVisuals() end
    if DFR.RegisterDefaultCatalyzers then DFR.RegisterDefaultCatalyzers() end
    if DFR.RegisterPreAnnihilationProcedure then DFR.RegisterPreAnnihilationProcedure() end
end)

debugCommand('luasquare_dfr_validate_bindings', function()
    DFR.ValidateBindings()
end)

debugCommand('luasquare_dfr_clear_binding_cache', function()
    if DFR.SourceBindings and DFR.SourceBindings.ClearCache then DFR.SourceBindings:ClearCache() end
    DFR.Log('Binding cache cleared')
end)

debugCommand('luasquare_dfr_machine_move', function(ply, args)
    DFR.MoveTrackTrainTo(arg(args, 1), arg(args, 2))
end)

debugCommand('luasquare_dfr_machine_command', function(ply, args)
    DFR.CommandMachinery(arg(args, 1), arg(args, 2), arg(args, 3))
end)

debugCommand('luasquare_dfr_machine_start', function(ply, args)
    DFR.StartMachinery(arg(args, 1))
end)

debugCommand('luasquare_dfr_machine_stop', function(ply, args)
    DFR.StopMachinery(arg(args, 1))
end)

debugCommand('luasquare_dfr_machine_speed', function(ply, args)
    local id = arg(args, 1)
    local machine = id and DFR.GetMachinery(id) or nil
    local range = machine and machine.debug and machine.debug.speed or nil
    if not machine or not range then
        DFR.Log('Rejected debug speed for non-adjustable machinery: ' .. tostring(id))
        return
    end

    local value = math.Clamp(tonumber(arg(args, 2)) or tonumber(range.min) or 0, tonumber(range.min) or 0, tonumber(range.max) or 100)
    DFR.SetMachinerySpeed(id, value)
end)

debugCommand('luasquare_dfr_machine_open', function(ply, args)
    DFR.OpenMachinery(arg(args, 1))
end)

debugCommand('luasquare_dfr_machine_close', function(ply, args)
    DFR.CloseMachinery(arg(args, 1))
end)

debugCommand('luasquare_dfr_machine_deploy', function(ply, args)
    if arg(args, 1) then
        DFR.DeployMachinery(arg(args, 1))
    else
        DFR.DeployStartupMachinery()
    end
end)

debugCommand('luasquare_dfr_machine_retract', function(ply, args)
    if arg(args, 1) then
        DFR.RetractMachinery(arg(args, 1))
    else
        DFR.RetractStartupMachinery()
    end
end)

debugCommand('luasquare_dfr_stabilizer_machine', function(ply, args)
    DFR.SetReactorStabilizerImmediate(boolArg(arg(args, 1)))
end)

debugCommand('luasquare_dfr_path_pass', function(ply, args)
    DFR.OnPathTrackPassed(arg(args, 1), arg(args, 2))
end)

debugCommand('luasquare_dfr_visual_enable', function(ply, args)
    DFR.SetCoreVisualEnabled(arg(args, 1), boolArg(arg(args, 2)))
end)

debugCommand('luasquare_dfr_visual_scale', function(ply, args)
    DFR.SetCoreVisualScale(arg(args, 1), tonumber(arg(args, 2)) or 1, tonumber(arg(args, 3)) or 0)
end)

debugCommand('luasquare_dfr_visual_radius', function(ply, args)
    local id = arg(args, 1)
    local visual = id and DFR.CoreVisual and DFR.CoreVisual[id] or nil
    local radiusRange = visual and visual.debug and visual.debug.radiusMeters or nil
    local transitionRange = visual and visual.debug and visual.debug.transitionSeconds or nil
    if not visual or not radiusRange or (tonumber(visual.basisRadiusMeters) or 0) <= 0 then
        DFR.Log('Rejected debug radius for non-scalable visual: ' .. tostring(id))
        return
    end

    local radius = math.Clamp(tonumber(arg(args, 2)) or tonumber(radiusRange.min) or 0, tonumber(radiusRange.min) or 0, tonumber(radiusRange.max) or 50)
    local changeTime = tonumber(arg(args, 3)) or 0
    if transitionRange then
        changeTime = math.Clamp(changeTime, tonumber(transitionRange.min) or 0, tonumber(transitionRange.max) or 10)
    else
        changeTime = math.max(changeTime, 0)
    end

    DFR.SetCoreVisualRadiusMeters(id, radius, changeTime)
end)

debugCommand('luasquare_dfr_visual_sync', function()
    if DFR.CoreVisual then DFR.CoreVisual.LastSyncedState = nil end
    if DFR.SyncCoreVisuals then DFR.SyncCoreVisuals() end
end)

debugCommand('luasquare_dfr_visual_wobble', function(ply, args)
    local id = arg(args, 1)
    local visual = id and DFR.CoreVisual and DFR.CoreVisual[id] or nil
    local amplitudeRange = visual and visual.debug and visual.debug.wobbleAmplitudePercent or nil
    local intervalRange = visual and visual.debug and visual.debug.wobbleIntervalSeconds or nil
    if not visual or not amplitudeRange or not intervalRange then return end

    local amplitude = math.Clamp(
        tonumber(arg(args, 3)) or visual.wobble.amplitudePercent,
        tonumber(amplitudeRange.min) or 0,
        tonumber(amplitudeRange.max) or 10
    )
    local minimum = math.Clamp(
        tonumber(arg(args, 4)) or visual.wobble.minIntervalSeconds,
        tonumber(intervalRange.min) or 0.1,
        tonumber(intervalRange.max) or 5
    )
    local maximum = math.Clamp(
        tonumber(arg(args, 5)) or visual.wobble.maxIntervalSeconds,
        minimum,
        tonumber(intervalRange.max) or 5
    )
    DFR.SetCoreVisualWobble(id, boolArg(arg(args, 2)), {
        amplitudePercent = amplitude,
        minIntervalSeconds = minimum,
        maxIntervalSeconds = maximum
    })
end)

debugCommand('luasquare_dfr_visual_pulse', function(ply, args)
    local id = arg(args, 1)
    local visual = id and DFR.CoreVisual and DFR.CoreVisual[id] or nil
    local range = visual and visual.debug and visual.debug.pulseAmplitudePercent or nil
    if not visual or not range then return end
    local amplitude = math.Clamp(
        tonumber(arg(args, 2)) or 10,
        tonumber(range.min) or 0,
        tonumber(range.max) or 25
    )
    DFR.PulseCoreVisual(id, { amplitudePercent = amplitude })
end)

debugCommand('luasquare_dfr_pre_annihilation_start', function(ply)
    DFR.UseControl('pre_annihilation_begin', ply)
end)

debugCommand('luasquare_dfr_pre_annihilation_cancel', function(ply)
    DFR.UseControl('pre_annihilation_cancel', ply)
end)

debugCommand('luasquare_dfr_catalyzer_mode', function(ply, args)
    local id = math.floor(tonumber(arg(args, 1)) or 0)
    local mode = string.upper(tostring(arg(args, 2) or ''))
    local allowed = {
        OFFLINE = true,
        CHARGING_LOW = true,
        CHARGING_HIGH = true,
        FIRING = true,
        CHARGED = true
    }
    if id < 1 or id > 6 or not allowed[mode] then
        DFR.Log('Rejected catalyzer debug mode: ' .. tostring(id) .. ' ' .. tostring(mode))
        return
    end
    DFR.SetCatalyzerMode(id, mode)
end)

debugCommand('luasquare_dfr_catalyzer_timeline', function(ply, args)
    local id = math.floor(tonumber(arg(args, 1)) or 0)
    local name = arg(args, 2)
    local unit = DFR.GetCatalyzer(id)
    if not unit or not name or not unit.timelineOwner:GetDefinition(name) then
        DFR.Log('Rejected unknown catalyzer timeline: ' .. tostring(id) .. ' ' .. tostring(name))
        return
    end
    unit:StartTimeline(name, { actor = ply, debug = true })
end)

debugCommand('luasquare_dfr_catalyzer_timeline_cancel', function(ply, args)
    local unit = DFR.GetCatalyzer(math.floor(tonumber(arg(args, 1)) or 0))
    if unit then unit:CancelTimeline(arg(args, 2), 'debug cancellation') end
end)

debugCommand('luasquare_dfr_reactor_machine_timeline', function(ply, args)
    local name = arg(args, 1)
    local owner = DFR.ReactorMachine and DFR.ReactorMachine.TimelineOwner
    if not owner or not name or not owner:GetDefinition(name) then
        DFR.Log('Rejected unknown reactor-machine timeline: ' .. tostring(name))
        return
    end
    DFR.StartReactorMachineTimeline(name, { actor = ply, debug = true })
end)

debugCommand('luasquare_dfr_reactor_machine_timeline_cancel', function(ply, args)
    DFR.CancelReactorMachineTimeline(arg(args, 1), 'debug cancellation')
end)
