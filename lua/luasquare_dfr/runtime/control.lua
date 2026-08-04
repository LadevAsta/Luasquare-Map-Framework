DFR = DFR or {}
if not LUASQUARE_CONTROLBINDING then include('luasquare_module/controlbinding.lua') end

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

function DFR.GetControlUnavailableReason(id)
    return DFR.ControlRegistry:GetUnavailableReason(id)
end

function DFR.LockControl(id, owner, reason)
    return DFR.ControlRegistry:Lock(id, owner, reason)
end

function DFR.UnlockControl(id, owner)
    return DFR.ControlRegistry:Unlock(id, owner)
end

function DFR.UnlockControlsByOwner(owner)
    return DFR.ControlRegistry:UnlockOwner(owner)
end

function DFR.UseControl(id, activator, value)
    return DFR.ControlRegistry:Use(id, activator, value)
end

function DFR.GetControlSnapshot()
    return DFR.ControlRegistry:GetSnapshot()
end
