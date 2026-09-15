if not SERVER then return end
local CONTROL = LUASQUARE_CONTROL
CONTROL.Requests = {}
CONTROL.RequestOrder = {}
CONTROL.History = {}
CONTROL.Sources = {}
CONTROL.Revision = 0
CONTROL.Serial = 0
CONTROL.HistorySerial = 0
CONTROL.EntityControls = {}
CONTROL.InternalInputs = {}
local terminal = {completed = true, expired = true, superseded = true, cancelled = true, failed = true}
local operations = {press = 'Press', toggle = 'Press', pressIn = 'PressIn', pressOut = 'PressOut',
    pressLock = 'Press', pressInLock = 'PressIn', pressOutLock = 'PressOut'}
local combined = {pressLock = true, pressInLock = true, pressOutLock = true}

local function actorName(actor)
    if type(actor) == 'string' then return string.sub(actor, 1, 128) end
    if IsValid(actor) then
        if actor:IsPlayer() then return string.sub(actor:Nick(), 1, 128) end
        return string.sub(actor:GetName() ~= '' and actor:GetName() or actor:GetClass(), 1, 128)
    end
    return 'SERVER'
end

local function physicalState(entity)
    if not IsValid(entity) then return 'missing' end
    local state = entity:GetInternalVariable('m_toggle_state')
    if state == 0 then return 'in' end
    if state == 1 then return 'out' end
    if state == 2 or state == 3 then return 'moving' end
    return 'unknown'
end
CONTROL.PhysicalState = physicalState

local function input(entity, name, actor)
    if not IsValid(entity) then return false end
    CONTROL.InternalInputs[entity] = (CONTROL.InternalInputs[entity] or 0) + 1
    local ok, result = pcall(entity.Input, entity, name, IsValid(actor) and actor or game.GetWorld(), entity, '')
    CONTROL.InternalInputs[entity] = CONTROL.InternalInputs[entity] - 1
    return ok and result ~= false
end

local function record(control, request, outcome, action, oldValue, newValue, reason)
    CONTROL.HistorySerial = CONTROL.HistorySerial + 1
    local entry = {sequence = CONTROL.HistorySerial, time = os.date('%H:%M:%S'), actor = request and request.actorLabel or 'SERVER',
        controlId = control.id, requestId = request and request.id, label = control.label, action = action and action.label or request and request.operation,
        oldValue = oldValue, newValue = newValue, outcome = outcome, reason = reason,
        severity = action and action.severity or 'info'}
    table.insert(CONTROL.History, entry)
    if #CONTROL.History > 500 then table.remove(CONTROL.History, 1) end
    if outcome == 'accepted' and not (action and action.diagnostic) then
        local text = '[' .. entry.time .. ' ' .. entry.actor .. '] ' .. entry.label .. ': ' .. tostring(entry.action)
        if oldValue ~= nil then text = text .. ' ' .. tostring(oldValue) .. ' > ' .. tostring(newValue) end
        MsgC(entry.severity == 'critical' and Color(255, 80, 80) or Color(255, 255, 255), text .. '\n')
    elseif reason then print('[LUASQUARE_CONTROL] ' .. control.id .. ': ' .. outcome .. ': ' .. reason) end
    hook.Run('LUASQUARE_CONTROL_Log', entry)
end

local function finish(request, status, reason)
    if not request or terminal[request.status] then return end
    request.status, request.reason, request.endedAt = status, reason, CurTime()
    local control = CONTROL.Controls[request.controlId]
    if control then record(control, request, status, nil, nil, nil, reason) end
    hook.Run('LUASQUARE_CONTROL_RequestTerminal', request)
    if type(request.context.onComplete) == 'function' then
        local ok, message = pcall(request.context.onComplete, request)
        if not ok then print('[LUASQUARE_CONTROL] Completion callback failed: ' .. tostring(message)) end
    end
end

function CONTROL.RegisterAction(id, definition)
    id = CONTROL.NormalizeId(id)
    if not id or type(definition) ~= 'table' or type(definition.callback) ~= 'function' then return false end
    CONTROL.Actions[id] = definition
    return true
end

function CONTROL.RegisterPredicate(id, definition)
    id = CONTROL.NormalizeId(id)
    if not id or type(definition) ~= 'table' or type(definition.callback) ~= 'function' then return false end
    CONTROL.Predicates[id] = definition
    return true
end

function CONTROL.GetControl(id) return CONTROL.Controls[id] end
function CONTROL.GetRequest(id) return CONTROL.Requests[id] end
function CONTROL.IsTerminal(request) return request and terminal[request.status] == true end
function CONTROL.GetHistory() return CONTROL.DeepCopy(CONTROL.History) end

local function predicatesReason(control, actor)
    for _, ref in ipairs(control.predicates) do
        local definition = CONTROL.Predicates[ref.id]
        if not definition then return 'missing predicate ' .. ref.id end
        local ok, allowed, reason = pcall(definition.callback, actor, ref.params, control)
        if not ok then return 'predicate failed: ' .. tostring(allowed) end
        if allowed == false then return reason or 'requirements not satisfied' end
    end
end

function CONTROL.GetUnavailableReason(id, flight, seen, actor)
    local control = CONTROL.Controls[id]
    if not control then return 'unknown control', 'binding' end
    actor = actor or flight and flight.context.actor
    seen = seen or {}
    if seen[id] then return 'cyclic keypad parent', 'binding' end
    seen[id] = true
    if control.target and (not IsValid(control.entity) or control.entity:GetName() ~= control.target
        or control.entity:GetClass() ~= control.class) then return 'missing or changed physical binding', 'binding' end
    if control.fault then return control.fault, 'fault' end
    if control.keyControls then
        for _, token in ipairs(CONTROL.KeypadKeyTokens) do
            local child = CONTROL.Controls[control.keyControls[token]]
            if child then
                if not IsValid(child.entity) or child.entity:GetName() ~= child.target or child.entity:GetClass() ~= child.class then
                    return 'Key ' .. token .. ': missing or changed physical binding', 'binding'
                end
                if child.fault then return 'Key ' .. token .. ': ' .. child.fault, 'fault' end
            end
        end
    end
    for owner, reason in pairs(control.locks) do
        if not (flight and flight.lockApplied and flight.context.owner == owner
            and control.lockGenerations[owner] == flight.lockGeneration) then return reason, 'lock' end
    end
    if control.parent then
        local parentReason, parentKind = CONTROL.GetUnavailableReason(control.parent, nil, seen, actor)
        if parentReason then return parentReason, parentKind end
    end
    local reason = predicatesReason(control, actor)
    if reason then return reason, 'predicate' end
    if not flight then
        if control.active or control.returning or (control.target and physicalState(control.entity) == 'moving') then return 'control moving', 'movement' end
        if control.target and physicalState(control.entity) == 'unknown' then return 'unsupported button state', 'binding' end
        if control.kind == 'toggle' and control.target and physicalState(control.entity) ~= control.acceptedPosition then
            return 'physical position does not match accepted component state', 'binding'
        end
        if CurTime() < control.lockedUntil then return 'control cooldown', 'cooldown' end
    end
end

function CONTROL.IsAvailable(id, actor) return CONTROL.GetUnavailableReason(id, nil, nil, actor) == nil end

local function sync(control)
    local reason, kind = CONTROL.GetUnavailableReason(control.id)
    local locked = reason ~= nil
    -- Movement/cooldown are admission guards, not permission to interrupt Source's normal return.
    local physicalLocked = locked and kind ~= 'movement'
        and (kind ~= 'cooldown' or not control.active and not control.returning)
    -- Internal reconciliation must reach its endpoint while logical fault/owner locks stay intact.
    if control.recovering then physicalLocked = false end
    if IsValid(control.entity) then
        local engineLocked = control.entity:GetInternalVariable('m_bLocked')
        if control.physicalLocked ~= physicalLocked or engineLocked ~= physicalLocked then
            input(control.entity, physicalLocked and 'Lock' or 'Unlock')
            control.physicalLocked = physicalLocked
        end
    end
    if control.indicatorLocked ~= locked then
        for _, entity in ipairs(control.indicators or {}) do if IsValid(entity) then input(entity, locked and 'ShowSprite' or 'HideSprite') end end
        control.indicatorLocked = locked
    end
end

local function syncKeypadKeys(control)
    for _, id in pairs(control.keyControls or {}) do
        local child = CONTROL.Controls[id]
        if child then sync(child) end
    end
end

function CONTROL.Lock(id, owner, reason)
    local control = CONTROL.Controls[id]
    owner = CONTROL.NormalizeId(owner)
    if not control or not owner then return false end
    if not control.locks[owner] then
        local count = 0
        for _ in pairs(control.locks) do count = count + 1 end
        if count >= 64 then return false end
    end
    control.locks[owner] = string.sub(tostring(reason or ('locked by ' .. owner)), 1, 256)
    control.lockSerial = control.lockSerial + 1
    control.lockGenerations[owner] = control.lockSerial
    sync(control)
    syncKeypadKeys(control)
    if CONTROL.PublishState then CONTROL.PublishState() end
    return true
end

function CONTROL.Unlock(id, owner)
    local control = CONTROL.Controls[id]
    owner = CONTROL.NormalizeId(owner)
    if not control or not owner then return false end
    control.locks[owner] = nil
    control.lockGenerations[owner] = nil
    sync(control)
    if control.pending then CONTROL.Dispatch(control, control.pending) end
    syncKeypadKeys(control)
    if CONTROL.PublishState then CONTROL.PublishState() end
    return true
end

function CONTROL.UnlockOwner(owner)
    owner = CONTROL.NormalizeId(owner)
    if not owner then return false end
    for _, request in pairs(CONTROL.Requests) do
        if request.context.owner == owner then request.lockAtTick = nil end
    end
    for id in pairs(CONTROL.Controls) do CONTROL.Unlock(id, owner) end
end

local function updateDisplay(control)
    if control.display and LUASQUARE_SEG7 then LUASQUARE_SEG7.SetDisplay(control.display, tonumber(control.buffer) or 0) end
end

function CONTROL.EditKeypad(id, operation, digit)
    local control = CONTROL.Controls[id]
    if not control or control.kind ~= 'keypad' or not CONTROL.IsAvailable(id) then return false end
    if operation == 'digit' then
        if not CONTROL.Finite(digit) or digit < 0 or digit > 9 or digit ~= math.floor(digit) then return false end
        if #control.buffer >= control.maxDigits then return true end
        control.buffer = control.buffer .. tostring(digit)
        if tonumber(control.buffer) >= control.maxValue then control.buffer = tostring(control.maxValue) end
    elseif operation == 'clear' then control.buffer = ''
    elseif operation == 'backspace' then control.buffer = string.sub(control.buffer, 1, -2)
    else return false end
    updateDisplay(control)
    return true
end

local function execute(control, request, event)
    local reason = CONTROL.GetUnavailableReason(control.id, request)
    if reason then return false, reason end
    local ref = control.actions[event]
    if not ref then
        if control.kind == 'toggle' then control.acceptedPosition = event end
        return true
    end
    if control.rejectNextOwner then
        control.rejectNextOwner = nil
        return false, 'explicit live-test action rejection fixture'
    end
    local action = CONTROL.Actions[ref.id]
    if not action then return false, 'missing action ' .. ref.id end
    local params, message = CONTROL.ValidateParameters(action, ref.params)
    if not params then return false, message end
    if request.context.params ~= nil then
        if not action.allowRequestParams or type(request.context.params) ~= 'table' then return false, 'action does not accept request parameters' end
        local overrides = CONTROL.DeepCopy(params)
        for key, value in pairs(request.context.params) do overrides[key] = value end
        params, message = CONTROL.ValidateParameters(action, overrides)
        if not params then return false, message end
    end
    local oldValue = control.kind == 'keypad' and control.acceptedValue or control.acceptedPosition
    if type(action.getValue) == 'function' then
        local ok, measured = pcall(action.getValue, params, control)
        if not ok then return false, 'action value reader failed: ' .. tostring(measured) end
        oldValue = measured
    end
    local value = request.context.value
    if event == 'submit' then
        value = value == nil and (tonumber(control.buffer) or 0) or value
        if not CONTROL.Finite(value) or value < 0 or value ~= math.floor(value) then return false, 'invalid keypad value' end
        value = math.min(value, control.maxValue)
    end
    local ok, result, detail = pcall(action.callback, request.context.actor, params, control, value, request.context)
    if not ok then return false, tostring(result) end
    if result == false then return false, detail or 'action rejected' end
    if event == 'submit' then
        control.acceptedValue = value
        control.buffer = control.clearOnSubmit == false and tostring(value) or ''
        updateDisplay(control)
    elseif control.kind == 'toggle' then control.acceptedPosition = event end
    control.lockedUntil = CurTime() + control.cooldown
    control.lastActor, control.lastUseTime = request.actorLabel, CurTime()
    local newValue = event == 'submit' and value or event
    if type(action.getValue) == 'function' then
        local measured, result = pcall(action.getValue, params, control)
        if measured then newValue = result end
    end
    record(control, request, 'accepted', action, oldValue, newValue)
    return true
end

local function fault(control, request, reason)
    reason = string.sub(tostring(reason), 1, 1024)
    finish(request, 'failed', reason)
    if control.pending then finish(control.pending, 'failed', reason) end
    control.active, control.pending = nil, nil
    control.fault = reason
    control.recoveryTimedOut = nil
    if IsValid(control.entity) and physicalState(control.entity) ~= control.acceptedPosition then
        control.recovering = {position = control.acceptedPosition, deadline = CurTime() + CONTROL.AcknowledgementSeconds}
        input(control.entity, 'Unlock')
        input(control.entity, control.acceptedPosition == 'in' and 'PressIn' or 'PressOut')
    end
    sync(control)
end

local function newRequest(control, operation, context)
    CONTROL.Serial = CONTROL.Serial + 1
    local request = {id = CONTROL.Serial, controlId = control.id, operation = operation,
        context = context, actorLabel = actorName(context.actor), status = 'pending', createdAt = CurTime(), expiresAt = CurTime() + CONTROL.QueueSeconds}
    CONTROL.Requests[request.id] = request
    table.insert(CONTROL.RequestOrder, request.id)
    local index = 1
    while #CONTROL.RequestOrder > 2048 and index <= #CONTROL.RequestOrder do
        local oldId = CONTROL.RequestOrder[index]
        if CONTROL.IsTerminal(CONTROL.Requests[oldId]) and not CONTROL.Requests[oldId].lockAtTick then
            table.remove(CONTROL.RequestOrder, index)
            CONTROL.Requests[oldId] = nil
        else index = index + 1 end
    end
    return request
end

function CONTROL.Dispatch(control, request)
    if not request or request.status ~= 'pending' then return false end
    if CurTime() >= request.expiresAt then
        if control.pending == request then control.pending = nil end
        finish(request, 'expired', 'control unavailable for two seconds')
        return false
    end
    if CONTROL.GetUnavailableReason(control.id, nil, nil, request.context.actor) then return false end
    control.pending = nil
    request.status, request.dispatchedAt = 'dispatched', CurTime()
    local target = (request.operation == 'pressIn' or request.operation == 'pressInLock') and 'in'
        or (request.operation == 'pressOut' or request.operation == 'pressOutLock') and 'out'
    request.targetPosition = target
    if combined[request.operation] then request.lockAtTick = engine.TickCount() + 1 end
    if not control.target then
        local event = control.kind == 'keypad' and 'submit' or control.kind == 'toggle'
            and (target or (control.acceptedPosition == 'in' and 'out' or 'in')) or 'press'
        local ok, reason = execute(control, request, event)
        if ok then finish(request, 'completed') else fault(control, request, reason) end
    elseif target and physicalState(control.entity) == target then
        finish(request, 'completed')
    else
        control.active = request
        request.expectedPosition = target or (control.acceptedPosition == 'in' and 'out' or 'in')
        request.deadline = CurTime() + CONTROL.AcknowledgementSeconds
        -- Input is synchronous: its outputs may arrive before Dispatch returns.
        input(control.entity, 'Unlock', request.context.actor)
        if not input(control.entity, operations[request.operation], request.context.actor) then
            request.lockAtTick = nil
            fault(control, request, 'physical input failed')
        end
    end
    return true
end

function CONTROL.Request(id, operation, context)
    local control = CONTROL.Controls[id]
    if not CONTROL.Running or not control then return nil, 'unknown or inactive control' end
    if operation ~= 'submitValue' and not operations[operation] then return nil, 'unknown operation' end
    if control.kind == 'keypad' and operation ~= 'submitValue' then return nil, 'keypad requires submitValue' end
    if control.kind ~= 'keypad' and operation == 'submitValue' then return nil, 'not a keypad' end
    if control.kind == 'momentary' and operation ~= 'press' and operation ~= 'pressLock' then return nil, 'momentary control requires press' end
    context = context or {}
    if type(context) ~= 'table' then return nil, 'invalid context' end
    if context.owner ~= nil and not CONTROL.NormalizeId(context.owner) then return nil, 'invalid owner' end
    if context.params ~= nil and (type(context.params) ~= 'table' or not CONTROL.SafeTree(context.params)) then return nil, 'invalid typed request parameters' end
    if combined[operation] and not CONTROL.NormalizeId(context.owner) then return nil, 'press-and-lock requires owner' end
    if operation == 'submitValue' and context.value ~= nil and (not CONTROL.Finite(context.value) or context.value < 0 or context.value ~= math.floor(context.value)) then return nil, 'invalid numeric value' end
    local requestContext = {}
    for key, value in pairs(context) do requestContext[key] = value end
    requestContext.owner = context.owner and CONTROL.NormalizeId(context.owner) or nil
    requestContext.params = context.params and CONTROL.DeepCopy(context.params) or nil
    local request = newRequest(control, operation, requestContext)
    if control.pending then finish(control.pending, 'superseded', 'replaced by newer request') end
    control.pending = request
    CONTROL.Dispatch(control, request)
    return request.id, request.status
end

function CONTROL.CancelRequest(id)
    local request = CONTROL.Requests[id]
    if not request or request.status ~= 'pending' then return false end
    local control = CONTROL.Controls[request.controlId]
    if control and control.pending == request then control.pending = nil end
    finish(request, 'cancelled', 'request cancelled')
    return true
end

function CONTROL.CancelOwner(owner)
    owner = CONTROL.NormalizeId(owner)
    if not owner then return false end
    for _, control in pairs(CONTROL.Controls) do
        if control.rejectNextOwner == owner then control.rejectNextOwner = nil end
    end
    for id, request in pairs(CONTROL.Requests) do if request.context.owner == owner then CONTROL.CancelRequest(id) end end
end

function CONTROL.ReportOutput(id, event, caller, activator)
    if id == 'OnPressed' or id == 'OnIn' or id == 'OnOut' then
        -- Preferred Hammer form: ReportOutput(event, CALLER, ACTIVATOR).
        -- Resolve the registered entity directly; target/class checks below still apply.
        local reportedEvent, reportedCaller, reportedActivator = id, event, caller
        id = IsValid(reportedCaller) and CONTROL.EntityControls[reportedCaller] or nil
        event, caller, activator = reportedEvent, reportedCaller, reportedActivator
    end
    local control = CONTROL.Controls[id]
    if not CONTROL.Running or not control or not control.target or caller ~= control.entity or not IsValid(caller)
        or caller:GetName() ~= control.target or caller:GetClass() ~= control.class then return false end
    if event ~= 'OnPressed' and event ~= 'OnIn' and event ~= 'OnOut' then return false end
    local position = event == 'OnIn' and 'in' or event == 'OnOut' and 'out' or nil
    if position and physicalState(caller) ~= position then return false end
    if control.recovering then
        if position == control.recovering.position then control.recovering = nil; sync(control) end
        return true
    end
    if control.returning then
        if event == 'OnOut' then control.returning = nil; sync(control) end
        return true
    end
    local request = control.active
    if not request then
        if event ~= 'OnPressed' then return false end
        -- Ignore movement here: Source has started accepting this physical interaction.
        local candidate = {context = {actor = activator}}
        local reason = CONTROL.GetUnavailableReason(id, candidate)
        if reason or CurTime() < control.lockedUntil then fault(control, nil, reason or 'control cooldown'); return false end
        request = newRequest(control, 'press', {actor = activator, owner = 'hammer'})
        request.status, request.deadline = 'dispatched', CurTime() + CONTROL.AcknowledgementSeconds
        request.expectedPosition = control.acceptedPosition == 'in' and 'out' or 'in'
        control.active = request
    end
    if event == 'OnPressed' then
        if request.pressed then return true end
        request.pressed = true
        if control.kind == 'momentary' then
            local ok, reason = execute(control, request, 'press')
            if not ok then fault(control, request, reason); return false end
            request.actionExecuted = true
        end
        return true
    end
    if position ~= request.expectedPosition then return false end
    if control.kind == 'toggle' then
        local ok, reason = execute(control, request, position)
        if not ok then fault(control, request, reason); return false end
    elseif not request.actionExecuted then return false end
    control.active = nil
    if control.kind == 'momentary' and position == 'in' then
        local keys = caller.GetKeyValues and caller:GetKeyValues() or {}
        -- GetKeyValues does not reliably retain inherited Hammer keys. Read
        -- Source's actual configured wait before budgeting the return timeout.
        local wait = math.max(tonumber(caller:GetInternalVariable('m_flWait')) or tonumber(keys.wait) or 0, 0)
        control.returning = {deadline = CurTime() + wait + CONTROL.AcknowledgementSeconds}
    end
    finish(request, 'completed')
    sync(control)
    return true
end

function CONTROL.ResetFault(id)
    local control = CONTROL.Controls[id]
    if control and control.kind == 'keypad' then
        for _, keyId in pairs(control.keyControls or {}) do
            local child = CONTROL.Controls[keyId]
            if not child or child.recovering or not IsValid(child.entity) or child.entity:GetName() ~= child.target
                or child.entity:GetClass() ~= child.class or physicalState(child.entity) ~= child.acceptedPosition then return false end
        end
        for _, keyId in pairs(control.keyControls or {}) do
            local child = CONTROL.Controls[keyId]
            if child.fault then CONTROL.ResetFault(keyId) end
        end
        control.fault = nil
        sync(control); syncKeypadKeys(control)
        return true
    end
    if not control or not control.fault or control.recovering
        or (control.target and (not IsValid(control.entity) or control.entity:GetName() ~= control.target
            or control.entity:GetClass() ~= control.class or physicalState(control.entity) ~= control.acceptedPosition)) then return false end
    control.fault = nil
    control.recoveryTimedOut = nil
    sync(control)
    return true
end

function CONTROL.Tick()
    if not CONTROL.Running then return end
    for _, request in pairs(CONTROL.Requests) do
        if request.lockAtTick and engine.TickCount() >= request.lockAtTick then
            request.lockAtTick = nil
            if request.status ~= 'cancelled' and request.status ~= 'expired' and request.status ~= 'superseded' then
                request.lockApplied = true
                CONTROL.Lock(request.controlId, request.context.owner, request.context.lockReason)
                local control = CONTROL.Controls[request.controlId]
                request.lockGeneration = control and control.lockGenerations[request.context.owner]
            end
        end
    end
    if CurTime() < (CONTROL.NextRefresh or 0) then return end
    CONTROL.NextRefresh = CurTime() + CONTROL.TickInterval
    for _, control in pairs(CONTROL.Controls) do
        if control.fault and IsValid(control.entity) and not control.recovering
            and physicalState(control.entity) ~= control.acceptedPosition and not control.recoveryTimedOut then
            control.recovering = {position = control.acceptedPosition, deadline = CurTime() + CONTROL.AcknowledgementSeconds}
            input(control.entity, 'Unlock')
            input(control.entity, control.acceptedPosition == 'in' and 'PressIn' or 'PressOut')
        end
        if control.kind == 'toggle' and IsValid(control.entity) and not control.fault and not control.active and not control.recovering then
            local position = physicalState(control.entity)
            if (position == 'in' or position == 'out') and position ~= control.acceptedPosition then
                fault(control, nil, 'unreported physical position change')
            end
        end
        if control.active and CurTime() >= control.active.deadline then fault(control, control.active, 'movement acknowledgement timed out') end
        if control.returning and CurTime() >= control.returning.deadline then
            control.returning = nil
            fault(control, nil, 'momentary return timed out')
        end
        if control.recovering and CurTime() >= control.recovering.deadline then
            control.recovering = nil
            control.recoveryTimedOut = true
            control.fault = 'position restoration timed out'
        end
        sync(control)
        if control.pending then CONTROL.Dispatch(control, control.pending) end
    end
end

function CONTROL.GetSnapshot()
    local controls = {}
    local function state(control)
        return {id = control.id, label = control.label, kind = control.kind, target = control.target, acceptedPosition = control.acceptedPosition,
            actualPosition = control.target and physicalState(control.entity) or control.acceptedPosition,
            unavailableReason = CONTROL.GetUnavailableReason(control.id), available = CONTROL.IsAvailable(control.id),
            locks = CONTROL.DeepCopy(control.locks), fault = control.fault, buffer = control.buffer,
            acceptedValue = control.acceptedValue, lastActor = control.lastActor, lastUseTime = control.lastUseTime,
            lockedUntil = control.lockedUntil, pending = control.pending and {id = control.pending.id,
                operation = control.pending.operation, expiresAt = control.pending.expiresAt},
            active = control.active and {id = control.active.id, operation = control.active.operation}}
    end
    for id, control in pairs(CONTROL.Controls) do
        if not control.keypadKey then
            controls[id] = state(control)
            if control.keyControls then
                controls[id].keys = {}
                for token, keyId in pairs(control.keyControls) do controls[id].keys[token] = state(CONTROL.Controls[keyId]) end
            end
        end
    end
    return {revision = CONTROL.Revision, controls = controls, running = CONTROL.Running == true}
end

function CONTROL.Stop()
    if LUASQUARE_TIMELINE then
        for _, run in pairs(LUASQUARE_TIMELINE.Active or {}) do
            if #(run.controlRequests or {}) > 0 then LUASQUARE_TIMELINE.CancelRun(run, 'control runtime stopped') end
        end
    end
    CONTROL.Running = false
    CONTROL.RestartPositions = CONTROL.RestartPositions or {}
    for _, request in pairs(CONTROL.Requests) do if not terminal[request.status] then finish(request, 'cancelled', 'control runtime stopped') end end
    for _, control in pairs(CONTROL.Controls) do
        if IsValid(control.entity) then
            local previous = CONTROL.RestartPositions[control.id]
            CONTROL.RestartPositions[control.id] = {entity = control.entity, position = control.acceptedPosition,
                interrupted = control.active ~= nil or control.returning ~= nil or control.recovering ~= nil
                    or previous and previous.entity == control.entity and previous.interrupted}
        end
        control.active, control.pending, control.returning, control.recovering = nil, nil, nil, nil
        if IsValid(control.entity) then input(control.entity, control.originalLocked and 'Lock' or 'Unlock') end
        for _, entity in ipairs(control.indicators or {}) do if IsValid(entity) then input(entity, 'HideSprite') end end
    end
    for _, event in ipairs({'Think', 'AcceptInput', 'PlayerUse'}) do hook.Remove(event, 'LUASQUARE_CONTROL_' .. event) end
    if CONTROL.StopNetwork then CONTROL.StopNetwork() end
    if CONTROL.UnregisterAdapters then CONTROL.UnregisterAdapters() end
    CONTROL.EntityControls, CONTROL.InternalInputs = {}, {}
end

function CONTROL.Start(mapName)
    mapName = mapName or game.GetMap()
    if not CONTROL.NormalizeId(mapName) then return false, 'invalid map name' end
    if CONTROL.Running then return false, 'control runtime already started' end
    local root = 'data_static/luasquare/control/' .. mapName .. '/'
    local names = file.Find(root .. '*.json', 'GAME') or {}
    table.sort(names)
    local definitions, sources, diagnostics, packs, targets, total = {}, {}, {}, {}, {}, 0
    if #names > 128 then return false, 'too many control packs' end
    for _, name in ipairs(names) do
        local path = root .. name
        if not string.match(name, '^[%w_%.%-]+%.json$') then return false, 'unsafe source path' end
        if (file.Size(path, 'GAME') or -1) > CONTROL.MaxSourceBytes then return false, 'source too large: ' .. path end
        local bytes = file.Read(path, 'GAME')
        local source = bytes and #bytes <= CONTROL.MaxSourceBytes and util.JSONToTable(bytes, false, true)
        local compiled, errors = CONTROL.CompileSource(source, path, {Actions = CONTROL.Actions,
            Predicates = CONTROL.Predicates, Displays = LUASQUARE_SEG7 and LUASQUARE_SEG7.Displays or {}})
        for _, item in ipairs(errors) do table.insert(diagnostics, item) end
        if compiled then
            if packs[compiled.id] then table.insert(diagnostics, {origin = path, path = '$.id', message = 'duplicate pack ID'}) end
            packs[compiled.id] = true
            sources[path] = source
            for _, definition in ipairs(compiled.controls) do
                total = total + 1
                if definitions[definition.id] then table.insert(diagnostics, {origin = path, path = definition.id, message = 'duplicate control ID'}) end
                if definition.target and targets[definition.target] then table.insert(diagnostics, {origin = path, path = definition.id, message = 'ambiguous physical binding'}) end
                if definition.target then targets[definition.target] = true end
                definitions[definition.id] = definition
            end
        end
    end
    if total > CONTROL.MaxControls then return false, 'too many controls' end
    local bindings = {}
    for id, definition in pairs(definitions) do
        if definition.parent and (not definitions[definition.parent] or definitions[definition.parent].kind ~= 'keypad' or definition.kind == 'keypad') then
            table.insert(diagnostics, {path = id, message = 'invalid keypad parent'})
        end
        for _, ref in pairs(definition.actions) do
            if ref.id == 'control.keypad_edit' or ref.id == 'control.keypad_submit' then
                local parent = definitions[ref.params.keypad]
                if not parent or parent.kind ~= 'keypad' or definition.parent ~= parent.id then
                    table.insert(diagnostics, {path = id .. '.actions', message = 'keypad key must declare its matching keypad parent'})
                end
            end
        end
        for _, ref in ipairs(definition.predicates) do
            if ref.id == 'control.position' and not definitions[ref.params.control] then
                table.insert(diagnostics, {path = id .. '.predicates', message = 'unknown control position reference'})
            end
        end
        if definition.target then
            local entities = ents.FindByName(definition.target)
            local previous = CONTROL.RestartPositions and CONTROL.RestartPositions[id]
            local movingWithoutOwner = #entities == 1 and physicalState(entities[1]) == 'moving'
                and not (previous and previous.entity == entities[1] and previous.interrupted)
            if #entities ~= 1 or entities[1]:GetClass() ~= definition.class or physicalState(entities[1]) == 'unknown' or movingWithoutOwner then
                table.insert(diagnostics, {path = id, message = 'missing, ambiguous, wrong-class or unsupported button binding'})
            else bindings[id] = entities[1] end
        end
        if definition.lockIndicator then
            local entities = ents.FindByName(definition.lockIndicator)
            if #entities == 0 then table.insert(diagnostics, {path = id, message = 'missing lock indicator'}) end
            for _, entity in ipairs(entities) do if entity:GetClass() ~= 'env_sprite' then table.insert(diagnostics, {path = id, message = 'lock indicator must be env_sprite'}) end end
        end
    end
    CONTROL.SourceDiagnostics = diagnostics
    CONTROL.EditorSources = sources -- Read-only authoring does not require valid live entity bindings.
    if #diagnostics > 0 then print(CONTROL.DiagnosticsText(diagnostics)); return false, CONTROL.DiagnosticsText(diagnostics) end
    CONTROL.Controls, CONTROL.Requests, CONTROL.RequestOrder, CONTROL.History = {}, {}, {}, {}
    CONTROL.Sources, CONTROL.EntityControls = sources, {}
    CONTROL.Revision = CONTROL.Revision + 1
    CONTROL.MapName, CONTROL.Running, CONTROL.NextRefresh = mapName, true, 0
    for id, definition in pairs(definitions) do
        local control = CONTROL.DeepCopy(definition)
        control.entity, control.locks, control.lockedUntil = bindings[id], {}, 0
        control.lockGenerations, control.lockSerial = {}, 0
        control.acceptedPosition = control.kind == 'momentary' and 'out' or control.initialPosition or (control.target and physicalState(control.entity)) or 'out'
        local previous = CONTROL.RestartPositions and CONTROL.RestartPositions[id]
        if previous and previous.entity == control.entity and previous.interrupted then
            control.acceptedPosition = control.initialPosition or previous.position
        end
        if control.kind == 'keypad' then control.buffer, control.acceptedValue = tostring(control.initialValue), control.initialValue; updateDisplay(control) end
        if control.entity then
            control.originalLocked = control.entity:GetInternalVariable('m_bLocked') == true
            CONTROL.EntityControls[control.entity] = id
        end
        control.indicators = control.lockIndicator and ents.FindByName(control.lockIndicator) or {}
        CONTROL.Controls[id] = control
    end
    for _, control in pairs(CONTROL.Controls) do
        if control.target and physicalState(control.entity) ~= control.acceptedPosition then
            control.fault = 'source initialization requires physical position reconciliation'
            control.recovering = {position = control.acceptedPosition, deadline = CurTime() + CONTROL.AcknowledgementSeconds}
            input(control.entity, 'Unlock')
            input(control.entity, control.acceptedPosition == 'in' and 'PressIn' or 'PressOut')
        end
    end
    CONTROL.RestartPositions = nil
    for _, control in pairs(CONTROL.Controls) do
        local ref = control.kind == 'keypad' and control.actions.submit
        local action = ref and CONTROL.Actions[ref.id]
        if action and type(action.initialize) == 'function' then
            local ok, result = pcall(action.initialize, nil, ref.params, control, control.acceptedValue, {owner = 'control.initialize'})
            if not ok or result == false then
                CONTROL.Stop()
                return false, control.id .. ': target initialization failed: ' .. tostring(result)
            end
        end
    end
    hook.Add('Think', 'LUASQUARE_CONTROL_Think', CONTROL.Tick)
    hook.Add('AcceptInput', 'LUASQUARE_CONTROL_AcceptInput', function(entity, name, activator)
        local id = CONTROL.EntityControls[entity]
        if not id or (CONTROL.InternalInputs[entity] or 0) > 0 then return end
        name = string.lower(name)
        if name == 'lock' or name == 'unlock' then return true end
        local operation = ({press = 'press', pressin = 'pressIn', pressout = 'pressOut', use = 'press'})[name]
        if operation then CONTROL.Request(id, operation, {actor = activator, owner = 'source_io'}); return true end
    end)
    hook.Add('PlayerUse', 'LUASQUARE_CONTROL_PlayerUse', function(actor, entity)
        local id = CONTROL.EntityControls[entity]
        if id and not CONTROL.IsAvailable(id, actor) then return false end
    end)
    CONTROL.Tick()
    hook.Run('LUASQUARE_CONTROL_Started', CONTROL.MapName)
    if CONTROL.RegisterAdapters then CONTROL.RegisterAdapters() end
    if CONTROL.StartNetwork then CONTROL.StartNetwork() end
    if CONTROL.BroadcastReset then CONTROL.BroadcastReset() end
    return true
end

function CONTROL.ReloadSources(mapName)
    CONTROL.Stop()
    return CONTROL.Start(mapName or CONTROL.MapName)
end

CONTROL.RegisterAction('control.keypad_edit', {label = 'Keypad edit', diagnostic = true, parameters = {
    keypad = {type = 'string'}, operation = {type = 'string', choices = {digit = true, clear = true, backspace = true}},
    digit = {type = 'integer', min = 0, max = 9, optional = true}},
    callback = function(_, params) return CONTROL.EditKeypad(params.keypad, params.operation, params.digit) end})
CONTROL.RegisterAction('control.keypad_submit', {label = 'Keypad submit', diagnostic = true,
    parameters = {keypad = {type = 'string'}}, callback = function(actor, params)
        local id, status = CONTROL.Request(params.keypad, 'submitValue', {actor = actor, owner = 'keypad'})
        return id ~= nil and status ~= 'failed'
    end})
CONTROL.RegisterPredicate('control.position', {label = 'Control position', parameters = {
    control = {type = 'string'}, position = {type = 'string', choices = {['in'] = true, out = true}}},
    callback = function(_, params)
        local control = CONTROL.GetControl(params.control)
        if not control then return false, 'safety cover unavailable' end
        local position = control.target and physicalState(control.entity) or control.acceptedPosition
        if position ~= params.position or (control.kind == 'toggle' and control.acceptedPosition ~= params.position) then
            return false, 'safety cover unavailable'
        end
        return true
    end})
