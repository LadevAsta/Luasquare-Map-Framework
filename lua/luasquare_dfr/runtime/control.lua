DFR = DFR or {}
local CONTROL = LUASQUARE_CONTROL

-- Trusted reactor behavior only. Map control instances are owned by JSON packs.
function DFR.RegisterOperatorAction(id, definition)
    local actionId = 'dfr.' .. id
    CONTROL.RegisterAction(actionId, {label = definition.label or id, parameters = {},
        callback = function(actor, _, control) return definition.callback(actor, nil, control) end})
    CONTROL.RegisterPredicate(actionId, {label = definition.label or id, parameters = {},
        callback = function(_, _, control)
            if DFR.Halted then return false, 'DFR simulation halted' end
            local states = definition.allowedStates
            if states and not states[DFR.GetState()] then return false, 'unavailable in current DFR state' end
            if definition.canUse then return definition.canUse(control) end
            return true
        end})
    return true
end
