DFR = DFR or {}
if not LUASQUARE_MACHINERY then include('luasquare_module/machinery.lua') end

DFR.MachineryRegistry = LUASQUARE_MACHINERY.CreateRegistry('DFR', {
    source = DFR.SourceBindings,
    log = function(message) DFR.Log(message) end,
    time = function() return DFR.GetTime() end
})

DFR.Machinery = DFR.MachineryRegistry.Machines

function DFR.RegisterMachinery(id, data)
    return DFR.MachineryRegistry:RegisterMachine(id, data)
end

function DFR.RegisterMachineryPath(id, data)
    return DFR.MachineryRegistry:RegisterPath(id, data)
end

function DFR.GetMachinery(id)
    return DFR.MachineryRegistry:GetMachine(id)
end

function DFR.CommandMachinery(id, inputName, value)
    return DFR.MachineryRegistry:Command(id, inputName, value)
end

function DFR.SetMachinerySpeed(id, speed)
    return DFR.MachineryRegistry:SetSpeed(id, speed)
end

function DFR.SetMachineryPosition(id, position)
    return DFR.MachineryRegistry:SetPosition(id, position)
end

function DFR.DeployMachinery(id)
    return DFR.MachineryRegistry:Deploy(id)
end

function DFR.RetractMachinery(id)
    return DFR.MachineryRegistry:Retract(id)
end

function DFR.StopMachinery(id)
    return DFR.MachineryRegistry:Stop(id)
end

function DFR.StartMachinery(id)
    return DFR.MachineryRegistry:Start(id)
end

function DFR.OpenMachinery(id)
    return DFR.MachineryRegistry:Open(id)
end

function DFR.CloseMachinery(id)
    return DFR.MachineryRegistry:Close(id)
end

function DFR.MoveTrackTrainTo(id, destinationNode)
    return DFR.MachineryRegistry:MoveTrackTrainTo(id, destinationNode)
end

function DFR.OnPathTrackPassed(nodeName, machineId)
    return DFR.MachineryRegistry:OnPathTrackPassed(nodeName, machineId)
end

DFR.PathTrackPassed = DFR.OnPathTrackPassed
DFR.TrackPassed = DFR.OnPathTrackPassed

function DFR.GetMachinerySnapshot()
    return DFR.MachineryRegistry:GetSnapshot()
end
