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
        machinery = DFR.Machinery or {},
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
end
