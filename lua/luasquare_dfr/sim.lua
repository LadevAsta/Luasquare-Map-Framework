DFR = DFR or {}

function DFR.StopTimer()
    if timer and timer.Exists and timer.Exists(DFR.Config.TimerName) then
        timer.Remove(DFR.Config.TimerName)
    end
end

function DFR.Start()
    if DFR.Halted then
        DFR.Log('Start rejected: simulation halted (' .. tostring(DFR.HaltReason) .. ')')
        return false
    end

    if DFR.ValidateBindings and not DFR.ValidateBindings() then
        DFR.Halt('required map bindings are missing')
        return false
    end

    DFR.Running = true
    DFR.LastTickTime = DFR.GetTime()

    if timer and timer.Create then
        DFR.StopTimer()
        timer.Create(DFR.Config.TimerName, DFR.Config.TickInterval, 0, function()
            local ok, err = pcall(function()
                local now = DFR.GetTime()
                local dt = now - (DFR.LastTickTime or now)
                DFR.LastTickTime = now
                DFR.Tick(dt)
            end)

            if not ok then DFR.Halt(err) end
        end)
    end

    DFR.Log('Started')
    return true
end

function DFR.Stop(reason)
    DFR.Running = false
    DFR.StopTimer()
    DFR.Log('Stopped: ' .. tostring(reason or 'manual stop'))
    return true
end

local function clampPercent(value)
    return math.Clamp(tonumber(value) or 0, 0, 100)
end

function DFR.TickOffline(dt)
    DFR.Resources.reactorOutputGW = 0
    DFR.Resources.reactorOutputTW = 0
    DFR.RefreshFuelReadiness()

    local recovery = (DFR.Config.OfflineIntegrityRecoveryPerSecond or 0) * dt
    DFR.Resources.superstructureIntegrityPercent = clampPercent((DFR.Resources.superstructureIntegrityPercent or 0) + recovery)
end

function DFR.Tick(dt)
    if not DFR.Running or DFR.Halted then return end
    dt = tonumber(dt) or DFR.Config.TickInterval or 0.1
    dt = math.Clamp(dt, 0, DFR.Config.MaxDeltaTime or 0.5)
    DFR.LastDeltaTime = dt

    local state = DFR.GetState()
    if state == DFR.STATE_OFFLINE then
        DFR.TickOffline(dt)
    elseif state == DFR.STATE_STARTUP_PREP then
        DFR.RefreshFuelReadiness()
        DFR.Resources.reactorOutputGW = 0
        DFR.Resources.reactorOutputTW = 0
        if DFR.TickStartupPrep then DFR.TickStartupPrep(dt) end
    elseif state == DFR.STATE_MANUAL_STARTUP then
        DFR.Resources.reactorOutputGW = 0
        DFR.Resources.reactorOutputTW = 0
        if DFR.TickManualStartup then DFR.TickManualStartup(dt) end
    elseif state == DFR.STATE_CONTROLLED_SHUTDOWN then
        DFR.Resources.reactorOutputGW = 0
        DFR.Resources.reactorOutputTW = 0
    end
end
