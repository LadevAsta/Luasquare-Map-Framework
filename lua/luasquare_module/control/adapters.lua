local CONTROL = LUASQUARE_CONTROL
CONTROL.AdapterIds = {}

function CONTROL.UnregisterAdapters()
    for _, id in ipairs(CONTROL.AdapterIds) do
        if LUASQUARE_TIMELINE then LUASQUARE_TIMELINE.UnregisterComponent(id) end
        if LUASQUARE_3D2D then LUASQUARE_3D2D.Actions[id] = nil end
    end
    CONTROL.AdapterIds = {}
end

function CONTROL.RegisterAdapters()
    CONTROL.UnregisterAdapters()
    for id, control in pairs(CONTROL.Controls) do
        if not control.keypadKey then
            local controlId, componentId = id, 'control.' .. id
            table.insert(CONTROL.AdapterIds, componentId)
            if LUASQUARE_3D2D then
                LUASQUARE_3D2D.RegisterAction(componentId, {label = control.label, cooldown = control.cooldown,
                    callback = function(actor, _, _, _, context)
                        local payload = context.payload or {}
                        local requestId, status = CONTROL.Request(controlId, payload.operation or (control.kind == 'keypad' and 'submitValue' or 'press'),
                            {actor = actor, value = payload.value, owner = 'display', displayId = context.displayId})
                        return requestId ~= nil and status ~= 'failed'
                    end})
            end
            if LUASQUARE_TIMELINE then
                local actions = {}
                for _, operation in ipairs(CONTROL.Operations) do
                    local compatible = control.kind == 'keypad' and operation == 'submitValue'
                        or control.kind == 'momentary' and (operation == 'press' or operation == 'pressLock')
                        or control.kind == 'toggle' and operation ~= 'submitValue'
                    if compatible then
                        local requestOperation = operation
                        actions[string.lower(operation)] = {kind = 'marker', label = operation, seekPolicy = 'reject',
                            parameters = operation == 'submitValue' and {{id = 'value', type = 'number', min = 0, max = control.maxValue, decimals = 0, default = 0}} or {},
                            execute = function(_, params, _, run)
                                if run.preview then return false end
                                local owner = run.controlOwner
                                local requestId = CONTROL.Request(controlId, requestOperation, {actor = run.context.actor or 'TIMELINE',
                                    owner = owner, value = params.value})
                                if not requestId then return false end
                                return {controlRequestId = requestId}
                            end}
                    end
                end
                LUASQUARE_TIMELINE.RegisterComponent(componentId, {type = 'control', label = control.label, actions = actions})
            end
        end
    end
end
