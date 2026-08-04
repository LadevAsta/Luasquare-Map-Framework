DFR = DFR or {}
DFR.TimelineOwners = DFR.TimelineOwners or {}

DFR.TimelineRegistry = LUASQUARE_TIMELINE.CreateRegistry('DFR', {
    time = function() return DFR.GetTime() end,
    log = function(message) DFR.Log(message) end,
    tickInterval = 0.05,
    releaseLocks = function(owner) DFR.UnlockControlsByOwner(owner) end,
    actions = {
        binding = function(action)
            local all = action.all
            if all == nil then
                local binding = DFR.GetBinding(action.binding)
                all = binding and binding.all
            end
            if all then return DFR.FireBindingAll(action.binding, action.input, action.value) end
            return DFR.FireBinding(action.binding, action.input, action.value)
        end,
        machinery = function(action)
            return DFR.CommandMachinery(action.machinery, action.input, action.value)
        end
    }
})

function DFR.CreateTimelineOwner(ownerId, options)
    local owner = LUASQUARE_TIMELINE.CreateOwner(DFR.TimelineRegistry, ownerId, options)
    if owner then DFR.TimelineOwners[ownerId] = owner end
    return owner
end

function DFR.GetTimelineOwner(ownerId)
    return DFR.TimelineOwners[tostring(ownerId or '')]
end

function DFR.RegisterTimeline(id, definition)
    return DFR.TimelineRegistry:Register(id, definition)
end

function DFR.StartTimeline(id, context)
    return DFR.TimelineRegistry:Start(id, context)
end

function DFR.CancelTimeline(id, reason)
    return DFR.TimelineRegistry:Cancel(id, reason)
end

function DFR.PauseTimeline(id)
    return DFR.TimelineRegistry:Pause(id)
end

function DFR.ResumeTimeline(id)
    return DFR.TimelineRegistry:Resume(id)
end

function DFR.CancelAllTimelines(reason)
    DFR.TimelineRegistry:CancelAll(reason)
    return true
end

function DFR.GetTimelineSnapshot(options)
    return DFR.TimelineRegistry:GetSnapshot(options)
end

function DFR.GetTimelineOwnerSnapshots()
    local snapshots = {}
    for ownerId, owner in pairs(DFR.TimelineOwners or {}) do
        snapshots[ownerId] = owner:GetSnapshot()
    end
    return snapshots
end
