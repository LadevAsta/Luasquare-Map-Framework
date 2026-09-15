local CONTROL = LUASQUARE_CONTROL

-- Pure draft model: never resolves entities, invokes registrations, or sends requests.
function CONTROL.NewPreview(compiled)
    local preview = {controls = {}, time = 0, tick = 0, history = {}}
    for _, definition in ipairs(compiled.controls) do
        local control = CONTROL.DeepCopy(definition)
        control.actualPosition, control.acceptedPosition = control.initialPosition or 'out', control.initialPosition or 'out'
        control.buffer, control.acceptedValue = tostring(control.initialValue or 0), control.initialValue
        control.locks, control.cooldownUntil = {}, 0
        preview.controls[control.id] = control
    end
    function preview:Log(message)
        table.insert(self.history, message)
        if #self.history > 100 then table.remove(self.history, 1) end
    end
    function preview:Available(control, seen)
        seen = seen or {}
        if seen[control.id] then return false end
        seen[control.id] = true
        if control.fault or next(control.locks) or control.active or control.returning or control.cooldownUntil > self.time then return false end
        local parent = self.controls[control.parent]
        return not parent or self:Available(parent, seen)
    end
    function preview:Action(control, event, value)
        local ref = control.actions[event]
        self:Log(control.id .. ': simulated ' .. event .. (ref and (' -> ' .. ref.id) or ' (no component action)'))
        if ref and ref.id == 'control.keypad_edit' then self:Key(ref.params.keypad, ref.params.operation, ref.params.digit)
        elseif ref and ref.id == 'control.keypad_submit' then self:Request(ref.params.keypad, 'submitValue') end
        if control.kind == 'keypad' then
            control.acceptedValue = math.min(value == nil and (tonumber(control.buffer) or 0) or value, control.maxValue)
            control.buffer = control.clearOnSubmit == false and tostring(control.acceptedValue) or ''
        elseif control.kind == 'toggle' then control.acceptedPosition = event end
        control.cooldownUntil = self.time + control.cooldown
    end
    function preview:Dispatch(control)
        local request = control.pending
        if not request then return end
        if self.time >= request.expiresAt then control.pending = nil; self:Log(control.id .. ': expired; no new lock'); return end
        if not self:Available(control) then return end
        control.pending = nil
        local op = request.operation
        local target = (op == 'pressIn' or op == 'pressInLock') and 'in'
            or (op == 'pressOut' or op == 'pressOutLock') and 'out'
        if string.sub(op, -4) == 'Lock' then control.lockTick = self.tick + 1 end
        if control.kind == 'keypad' then self:Action(control, 'submit', request.value)
        elseif target == control.actualPosition then self:Log(control.id .. ': already satisfied; no repeated action')
        elseif control.target then
            control.active = {target = target or (control.actualPosition == 'in' and 'out' or 'in'), deadline = self.time + 5}
            control.actualPosition = 'moving'
            if control.kind == 'momentary' then self:Action(control, 'press') end
            self:Log(control.id .. ': simulated physical dispatch; endpoint acknowledgement required')
        else self:Action(control, control.kind == 'momentary' and 'press' or target or (control.acceptedPosition == 'in' and 'out' or 'in')) end
    end
    function preview:Request(id, operation, value)
        local control = self.controls[id]
        if not control then return false end
        if control.kind == 'keypad' and operation ~= 'submitValue' or control.kind ~= 'keypad' and operation == 'submitValue'
            or control.kind == 'momentary' and operation ~= 'press' and operation ~= 'pressLock' then return false end
        if operation == 'submitValue' and value ~= nil and (not CONTROL.Finite(value) or value < 0 or value ~= math.floor(value)) then return false end
        if control.pending then self:Log(id .. ': pending request superseded') end
        control.pending = {operation = operation, value = value, expiresAt = self.time + 2}
        self:Dispatch(control)
        return true
    end
    function preview:Step(seconds)
        self.time, self.tick = self.time + seconds, self.tick + 1
        for _, control in pairs(self.controls) do
            if control.lockTick and self.tick >= control.lockTick then
                control.lockTick = nil; control.locks.preview = true; self:Log(control.id .. ': next-tick preview lock')
            end
            if control.active and self.time >= control.active.deadline then
                control.active = nil; control.fault = 'simulated acknowledgement timeout'; control.actualPosition = control.acceptedPosition
            end
            self:Dispatch(control)
        end
    end
    function preview:Endpoint(id)
        local control = self.controls[id]
        if not control then return end
        if control.active then
            control.actualPosition = control.active.target
            if control.kind == 'toggle' then self:Action(control, control.active.target) end
            if control.kind == 'momentary' and control.actualPosition == 'in' then control.returning = true end
            control.active = nil
        elseif control.kind == 'momentary' then control.actualPosition = 'out'; control.returning = nil end
    end
    function preview:Key(id, operation, digit)
        local control = self.controls[id]
        if not control or control.kind ~= 'keypad' or not self:Available(control) then return false end
        if operation == 'clear' then control.buffer = ''
        elseif operation == 'backspace' then control.buffer = string.sub(control.buffer, 1, -2)
        elseif operation == 'digit' and CONTROL.Finite(digit) and digit >= 0 and digit <= 9 and digit == math.floor(digit) then
            if #control.buffer < control.maxDigits then control.buffer = control.buffer .. tostring(digit) end
            if (tonumber(control.buffer) or 0) >= control.maxValue then control.buffer = tostring(control.maxValue) end
        else return false end
        return true
    end
    return preview
end
