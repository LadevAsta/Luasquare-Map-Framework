DFR = DFR or {}
DFR.Debug = DFR.Debug or {}
DFR.LogHistory = DFR.LogHistory or {}

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
        startup = DFR.Startup or {},
        machinery = DFR.GetMachinerySnapshot and DFR.GetMachinerySnapshot() or DFR.Machinery or {},
        coreVisuals = DFR.CoreVisual or {},
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
    if boolArg(arg(args, 1)) then
        DFR.ActivateStabilizerMachinery()
    else
        DFR.DeactivateStabilizerMachinery()
    end
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

debugCommand('luasquare_dfr_visual_sync', function()
    if DFR.CoreVisual then DFR.CoreVisual.LastSyncedState = nil end
    if DFR.SyncCoreVisuals then DFR.SyncCoreVisuals() end
end)
