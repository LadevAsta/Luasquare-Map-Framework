DFR = DFR or {}
DFR.TimelineOwners = DFR.TimelineOwners or {}

local TIMELINE = LUASQUARE_TIMELINE

local OwnerFacade = {}
OwnerFacade.__index = OwnerFacade

function OwnerFacade:Start(localName, context, options)
    return TIMELINE.Start(self.Id, localName, context, options)
end

function OwnerFacade:Cancel(localName, reason)
    return TIMELINE.Cancel(self.Id, localName, reason)
end

function OwnerFacade:CancelAll(reason)
    return TIMELINE.CancelOwner(self.Id, reason)
end

function OwnerFacade:IsActive(localName)
    local snapshot = TIMELINE.GetOwnerSnapshot(self.Id)
    for _, definition in ipairs(snapshot.definitions) do
        if definition.id == localName then return definition.active end
    end
    return false
end

function OwnerFacade:GetDefinition(localName)
    return TIMELINE.GetDefinition(self.Id, localName)
end

function OwnerFacade:GetActiveInChannel(channel)
    return TIMELINE.GetActiveInChannel(self.Id, channel)
end

function OwnerFacade:GetSnapshot()
    return TIMELINE.GetOwnerSnapshot(self.Id)
end

function DFR.GetTimelineOwner(ownerId)
    ownerId = TIMELINE.NormalizeId(ownerId)
    if not ownerId then return nil end
    local facade = DFR.TimelineOwners[ownerId]
    if not facade then
        facade = setmetatable({Id = ownerId}, OwnerFacade)
        DFR.TimelineOwners[ownerId] = facade
    end
    return facade
end

function DFR.RegisterTimelineComponent(id, definition)
    return TIMELINE.RegisterComponent(id, definition)
end

function DFR.BindComponentTimeline(ownerId, localName, sourcePath, options)
    local ok, result = TIMELINE.BindTimeline(ownerId, localName, sourcePath, options)
    if not ok then
        DFR.Log('Timeline bind failed for ' .. tostring(ownerId) .. '/' .. tostring(localName)
            .. ': ' .. tostring(result))
    end
    if ok then DFR.GetTimelineOwner(ownerId) end
    return ok, result
end

function DFR.StartTimeline(ownerId, localName, context, options)
    return TIMELINE.Start(ownerId, localName, context, options)
end

function DFR.CancelTimeline(ownerId, localName, reason)
    return TIMELINE.Cancel(ownerId, localName, reason)
end

function DFR.PauseTimeline(ownerId, localName)
    return TIMELINE.Pause(ownerId, localName)
end

function DFR.ResumeTimeline(ownerId, localName)
    return TIMELINE.Resume(ownerId, localName)
end

function DFR.CancelAllTimelines(reason)
    for ownerId in pairs(DFR.TimelineOwners or {}) do TIMELINE.CancelOwner(ownerId, reason) end
    return true
end

function DFR.GetTimelineSnapshot(options)
    return TIMELINE.GetSnapshot(options)
end

function DFR.GetTimelineOwnerSnapshots()
    local snapshots = {}
    for ownerId in pairs(DFR.TimelineOwners or {}) do
        snapshots[ownerId] = TIMELINE.GetOwnerSnapshot(ownerId)
    end
    return snapshots
end

function DFR.RegisterMachineryTimelineComponent(id, machine)
    machine = machine or DFR.GetMachinery(id)
    if not machine then return false end
    local componentId = 'machinery:' .. tostring(id)
    local actions = {
        stop = {
            kind = 'marker', label = 'Stop', seekPolicy = 'apply',
            execute = function() return DFR.StopMachinery(id) end
        }
    }
    if machine.type == 'tracktrain' then
        actions.deploy = {
            kind = 'marker', label = 'Deploy', seekPolicy = 'apply',
            execute = function() return DFR.DeployMachinery(id) end
        }
        actions.retract = {
            kind = 'marker', label = 'Retract', seekPolicy = 'apply',
            execute = function() return DFR.RetractMachinery(id) end
        }
    elseif machine.type == 'door' then
        actions.open = {
            kind = 'duration', label = 'Open for duration', seekPolicy = 'apply',
            start = function() return DFR.OpenMachinery(id) end,
            finish = function() return DFR.CloseMachinery(id) end,
            cancel = function() return DFR.CloseMachinery(id) end
        }
        actions.open_marker = {
            kind = 'marker', label = 'Open', seekPolicy = 'apply',
            execute = function() return DFR.OpenMachinery(id) end
        }
        actions.close = {
            kind = 'marker', label = 'Close', seekPolicy = 'apply',
            execute = function() return DFR.CloseMachinery(id) end
        }
    else
        actions.start = {
            kind = 'duration', label = 'Run for duration', seekPolicy = 'apply',
            start = function() return DFR.StartMachinery(id) end,
            finish = function() return DFR.StopMachinery(id) end,
            cancel = function() return DFR.StopMachinery(id) end
        }
        actions.start_marker = {
            kind = 'marker', label = 'Start', seekPolicy = 'apply',
            execute = function() return DFR.StartMachinery(id) end
        }
        actions.set_speed = {
            kind = 'number', label = 'Set speed', seekPolicy = 'apply',
            min = machine.debug and machine.debug.speed and machine.debug.speed.min or 0,
            max = machine.debug and machine.debug.speed and machine.debug.speed.max or 100,
            decimals = machine.debug and machine.debug.speed and machine.debug.speed.decimals or 1,
            unit = '%',
            set = function(_, _, value) return DFR.SetMachinerySpeed(id, value) end
        }
    end
    return DFR.RegisterTimelineComponent(componentId, {
        type = 'dfr.machinery.' .. tostring(machine.type or 'generic'),
        label = machine.label or id,
        context = machine,
        actions = actions,
        safeReset = function()
            if machine.type == 'door' then return DFR.CloseMachinery(id) end
            return DFR.StopMachinery(id)
        end
    })
end

function DFR.RegisterCoreVisualTimelineComponent(id)
    local visual = DFR.CoreVisual and DFR.CoreVisual[id]
    if not visual then return false end
    local actions = {
        enabled = {
            kind = 'duration', label = 'Visible/enabled', seekPolicy = 'apply',
            start = function() return DFR.SetCoreVisualEnabled(id, true) end,
            finish = function() return DFR.SetCoreVisualEnabled(id, false) end,
            cancel = function() return DFR.SetCoreVisualEnabled(id, false) end
        },
        enable = {
            kind = 'marker', label = 'Enable', seekPolicy = 'apply',
            execute = function() return DFR.SetCoreVisualEnabled(id, true) end
        },
        disable = {
            kind = 'marker', label = 'Disable', seekPolicy = 'apply',
            execute = function() return DFR.SetCoreVisualEnabled(id, false) end
        }
    }
    if visual.kind == 'prop' then
        actions.set_radius = {
            kind = 'number', label = 'Radius', seekPolicy = 'apply',
            min = visual.debug and visual.debug.radiusMeters and visual.debug.radiusMeters.min or 0,
            max = visual.debug and visual.debug.radiusMeters and visual.debug.radiusMeters.max or 50,
            decimals = 3,
            unit = 'm',
            set = function(_, params, value)
                return DFR.SetCoreVisualRadiusMeters(id, value, tonumber(params.transitionSeconds) or 0)
            end,
            parameters = {
                {id = 'transitionSeconds', label = 'Transition', type = 'number', default = 0,
                    min = 0, max = 10, decimals = 2, unit = 's'}
            }
        }
        actions.pulse = {
            kind = 'marker', label = 'Pulse', seekPolicy = 'skip',
            execute = function(_, params) return DFR.PulseCoreVisual(id, params) end
        }
    end
    return DFR.RegisterTimelineComponent('core_visual:' .. id, {
        type = 'dfr.core_visual.' .. tostring(visual.kind),
        label = visual.label or id,
        context = visual,
        actions = actions,
        safeReset = function()
            if visual.kind == 'prop' then DFR.SetCoreVisualRadiusMeters(id, 0, 0) end
            return DFR.SetCoreVisualEnabled(id, false)
        end
    })
end

function DFR.Register3D2DDisplayTimelineComponents()
    local display = LUASQUARE_3D2D
    if not display or not display.Displays then return 0 end
    DFR.TimelineDisplayComponents = DFR.TimelineDisplayComponents or {}
    for componentId in pairs(DFR.TimelineDisplayComponents) do
        local displayId = string.sub(componentId, #'display:' + 1)
        if not display.Displays[displayId] then
            LUASQUARE_TIMELINE.UnregisterComponent(componentId)
            DFR.TimelineDisplayComponents[componentId] = nil
        end
    end
    local count = 0
    for id, runtimeDisplay in pairs(display.Displays) do
        local displayId = id
        local currentDisplay = runtimeDisplay
        local actions = {
            set_page = {
                kind = 'marker', label = 'Set page', seekPolicy = 'apply',
                parameters = {{id = 'page', label = 'Page ID', type = 'string'}},
                execute = function(_, params) return display.SetDisplayPage(displayId, params.page) end
            }
        }
        for name, definition in pairs(currentDisplay.definition.variables or {}) do
            local variableName = name
            if definition.type == 'number' then
                actions['set_variable_' .. variableName] = {
                    kind = 'number', label = 'Variable: ' .. variableName, seekPolicy = 'apply',
                    min = definition.min, max = definition.max, decimals = definition.decimals,
                    set = function(_, _, value)
                        return display.SetDisplayVariable(displayId, variableName, value)
                    end
                }
            end
        end
        DFR.RegisterTimelineComponent('display:' .. displayId, {
            type = 'luasquare.3d2display',
            label = currentDisplay.definition.label or displayId,
            context = currentDisplay,
            actions = actions,
            safeReset = function()
                display.ResetDisplayVariables(displayId)
                if currentDisplay.definition.defaultPage then
                    display.SetDisplayPage(displayId, currentDisplay.definition.defaultPage)
                end
                return true
            end
        })
        DFR.TimelineDisplayComponents['display:' .. displayId] = true
        count = count + 1
    end
    return count
end


hook.Add('LUASQUARE_3D2D_DisplayBuilt', 'LUASQUARE_DFR_TimelineDisplayAdapter', function()
    if DFR and DFR.Register3D2DDisplayTimelineComponents then
        DFR.Register3D2DDisplayTimelineComponents()
    end
end)

hook.Add('LUASQUARE_3D2D_DisplaysClearing', 'LUASQUARE_DFR_TimelineDisplayAdapterClear', function()
    for componentId in pairs(DFR.TimelineDisplayComponents or {}) do
        LUASQUARE_TIMELINE.UnregisterComponent(componentId)
    end
    DFR.TimelineDisplayComponents = {}
end)

TIMELINE.LoadMapSources(game.GetMap())
