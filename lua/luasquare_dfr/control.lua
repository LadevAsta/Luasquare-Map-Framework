DFR = DFR or {}
if not LUASQUARE_CONTROLBINDING then include('luasquare_module/controlbinding.lua') end
DFR.StartupLevers = DFR.StartupLevers or {}

DFR.ControlRegistry = LUASQUARE_CONTROLBINDING.CreateRegistry('DFR', {
    time = function() return DFR.GetTime() end,
    getState = function() return DFR.GetState() end,
    isHalted = function() return DFR.Halted and true or false end,
    log = function(message) DFR.Log(message) end,
    halt = function(reason) DFR.Halt(reason) end,
    actorName = function(actor) return DFR.GetActorName(actor) end,
    defaultLockSeconds = DFR.Config.DefaultControlLockSeconds
})

DFR.Controls = DFR.ControlRegistry.Controls

function DFR.RegisterControl(id, data)
    return DFR.ControlRegistry:Register(id, data)
end

function DFR.IsControlAvailable(id)
    return DFR.ControlRegistry:IsAvailable(id)
end

function DFR.UseControl(id, activator, value)
    return DFR.ControlRegistry:Use(id, activator, value)
end

function DFR.GetControlSnapshot()
    return DFR.ControlRegistry:GetSnapshot()
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
