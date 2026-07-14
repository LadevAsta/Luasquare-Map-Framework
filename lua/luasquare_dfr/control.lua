DFR = DFR or {}
DFR.Controls = DFR.Controls or {}
DFR.StartupLevers = DFR.StartupLevers or {}

function DFR.RegisterControl(id, data)
    data = data or {}
    if not id or id == '' then
        DFR.Log('Rejected control with missing id')
        return false
    end

    DFR.Controls[id] = {
        id = id,
        label = data.label or id,
        allowedStates = data.allowedStates or {},
        lockSeconds = tonumber(data.lockSeconds) or DFR.Config.DefaultControlLockSeconds,
        callback = data.callback or data.onUse,
        lockedUntil = 0,
        lastUseTime = nil,
        lastActor = nil
    }

    return true
end

local function stateAllowed(control)
    if not control.allowedStates or next(control.allowedStates) == nil then return true end
    return control.allowedStates[DFR.GetState()] and true or false
end

function DFR.IsControlAvailable(id)
    local control = DFR.Controls[id]
    if not control then return false end
    if DFR.Halted then return false end
    if not stateAllowed(control) then return false end
    return DFR.GetTime() >= (control.lockedUntil or 0)
end

function DFR.UseControl(id, activator, value)
    local control = DFR.Controls[id]
    if not control then
        DFR.Log('Unknown control: ' .. tostring(id))
        return false
    end

    local now = DFR.GetTime()
    if DFR.Halted then
        DFR.Log('Rejected control ' .. tostring(id) .. ': simulation halted')
        return false
    end

    if now < (control.lockedUntil or 0) then
        return false
    end

    if not stateAllowed(control) then
        DFR.Log('Rejected control ' .. tostring(id) .. ' in state ' .. tostring(DFR.GetState()))
        return false
    end

    if control.callback then
        local ok, result = pcall(control.callback, activator, value, control)
        if not ok then
            DFR.Halt('Control ' .. tostring(id) .. ' failed: ' .. tostring(result))
            return false
        end
        if result == false then return false end
    end

    control.lockedUntil = now + (tonumber(control.lockSeconds) or DFR.Config.DefaultControlLockSeconds)
    control.lastUseTime = now
    control.lastActor = DFR.GetActorName(activator)
    return true
end

function DFR.ClearStartupLevers()
    DFR.StartupLevers = {}
end

function DFR.ArmStartupLever(id, activator)
    local now = DFR.GetTime()
    local window = DFR.Config.StartupLeverArmWindow or 5
    DFR.StartupLevers[id] = {
        armedAt = now,
        actor = DFR.GetActorName(activator)
    }

    for leverId, data in pairs(DFR.StartupLevers) do
        if now - (data.armedAt or 0) > window then
            DFR.StartupLevers[leverId] = nil
        end
    end

    local armedCount = 0
    for _ in pairs(DFR.StartupLevers) do armedCount = armedCount + 1 end
    DFR.Log('Startup lever armed: ' .. tostring(id) .. ' (' .. tostring(armedCount) .. '/3)')

    if DFR.StartupLevers.startup_lever_1 and DFR.StartupLevers.startup_lever_2 and DFR.StartupLevers.startup_lever_3 then
        DFR.ClearStartupLevers()
        return DFR.RequestTransition(DFR.STATE_STARTUP_PREP, 'triple startup levers armed', activator)
    end

    return true
end

function DFR.RegisterStartupLever(id, label)
    return DFR.RegisterControl(id, {
        label = label or id,
        allowedStates = {
            [DFR.STATE_OFFLINE] = true
        },
        callback = function(activator)
            return DFR.ArmStartupLever(id, activator)
        end
    })
end
