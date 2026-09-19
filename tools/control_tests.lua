-- Deterministic Source/GMod API doubles; run through tools/check_control.js.
SERVER, CLIENT = true, false
local time, tick, hooks, entities, sources, trace = 0, 0, {}, {}, {}, {}
function CurTime() return time end
function RealTime() return time end
function Color(...) return {...} end
function MsgC() end
function AddCSLuaFile() end
function IsValid(entity) return type(entity) == 'table' and entity.valid == true end
engine = {TickCount = function() return tick end}
local world = {valid = true, IsPlayer = function() return false end, GetName = function() return 'world' end, GetClass = function() return 'worldspawn' end}
game = {GetMap = function() return 'test' end, GetWorld = function() return world end}
hook = {
    Add = function(event, id, callback) hooks[event] = hooks[event] or {}; hooks[event][id] = callback end,
    Remove = function(event, id) if hooks[event] then hooks[event][id] = nil end end,
    Run = function(event, ...)
        for _, callback in pairs(hooks[event] or {}) do
            local value = callback(...)
            if value ~= nil then return value end
        end
    end
}
file = {Find = function() return {'test.json'} end, Size = function() return 100 end,
    Read = function() return 'test' end}
util = {JSONToTable = function(bytes, ignoreLimits, ignoreConversions)
    assert(ignoreLimits == false and ignoreConversions == true, 'control JSON must preserve string object keys without disabling parser limits')
    return sources[bytes]
end}
ents = {FindByName = function(name)
    local result = {}
    for _, entity in ipairs(entities) do if entity.valid and entity.name == name then table.insert(result, entity) end end
    return result
end}
LUASQUARE_SEG7 = {Displays = {digits = true, fwlevelctrl = true, hotwellctrl = true, rodctrl = true, aprctrl = true},
    SetDisplay = function(id, value) trace[#trace + 1] = {'display', id, value} end}
function include(path)
    if path == 'luasquare_module/control/network_server.lua' then return end
    return dofile('lua/' .. path)
end
include('luasquare_module/control/engine.lua')
local CONTROL = LUASQUARE_CONTROL
local count, blocked, reject, calls = 0, false, false, 0
CONTROL.RegisterAction('test.action', {label = 'Test', parameters = {}, callback = function()
    calls = calls + 1
    return not reject
end})
CONTROL.RegisterPredicate('test.available', {parameters = {}, callback = function() return not blocked, 'blocked by test' end})
local function check(condition, message)
    assert(condition, message)
    count = count + 1
end
local function entity(name, class)
    local out = {valid = true, name = name, class = class or 'func_button', state = 1, locked = false}
    function out:GetName() return self.name end
    function out:GetClass() return self.class end
    function out:IsPlayer() return false end
    function out:GetInternalVariable(key) return key == 'm_toggle_state' and self.state or key == 'm_bLocked' and self.locked end
    function out:Input(input, activator)
        if hook.Run('AcceptInput', self, input, activator) then return end
        trace[#trace + 1] = {input, tick, self.name}
        if input == 'Lock' then self.locked = true; return end
        if input == 'Unlock' then self.locked = false; return end
        if input == 'ShowSprite' or input == 'HideSprite' then return end
        if self.locked then return end
        local target = input == 'PressIn' and 'in' or input == 'PressOut' and 'out' or self.state == 1 and 'in' or 'out'
        if (target == 'in' and self.state == 0) or (target == 'out' and self.state == 1) then return end
        if self.genericReports then CONTROL.ReportOutput('OnPressed', self, activator)
        else CONTROL.ReportOutput(CONTROL.EntityControls[self], 'OnPressed', self, activator) end
        self.target = target
        self.state = target == 'in' and 2 or 3
    end
    function out:Complete()
        self.state = self.target == 'in' and 0 or 1
        local event = self.target == 'in' and 'OnIn' or 'OnOut'
        if self.genericReports then CONTROL.ReportOutput(event, self, world)
        else CONTROL.ReportOutput(CONTROL.EntityControls[self], event, self, world) end
    end
    entities[#entities + 1] = out
    return out
end
local function advance(seconds)
    time = time + seconds
    tick = tick + 1
    CONTROL.Tick()
end
local function setup(kind)
    CONTROL.Stop()
    time, tick, entities, trace, blocked, reject, calls = 0, 0, {}, {}, false, false, 0
    local button = entity('CTRLI_button')
    local actions = kind == 'toggle' and {['in'] = {id = 'test.action'}, out = {id = 'test.action'}} or {press = {id = 'test.action'}}
    sources.test = {schema = CONTROL.Schema, id = 'test', controls = {{id = 'button', kind = kind or 'toggle',
        target = 'CTRLI_button', class = 'func_button', cooldown = 0, actions = actions,
        predicates = {{id = 'test.available'}}}}}
    local ok, message = CONTROL.Start('test')
    assert(ok, message)
    return button
end

local button = setup('toggle')
CONTROL.Lock('button', 'owner', 'locked')
local id = CONTROL.Request('button', 'pressInLock', {owner = 'owner', actor = 'AUTO'})
check(CONTROL.GetRequest(id).status == 'pending' and button.state == 1, 'own lock must block combined request')
advance(1)
CONTROL.Unlock('button', 'owner')
check(CONTROL.GetRequest(id).status == 'dispatched' and not button.locked, 'unlock dispatches actual input first')
advance(0.001)
check(button.locked and CONTROL.Controls.button.locks.owner ~= nil, 'combined lock applied next server tick')
button:Complete()
check(CONTROL.GetRequest(id).status == 'completed' and calls == 1, 'own post-press lock must allow accepted output')
CONTROL.ReportOutput('button', 'OnIn', button, world)

button = setup('momentary')
reject = true
id = CONTROL.Request('button', 'press', {})
check(CONTROL.GetRequest(id).status == 'failed' and not CONTROL.Controls.button.fault and not button.locked,
    'expected action rejection is terminal without a persistent control fault')
check(calls == 1, 'duplicate output must not dispatch twice')
check(not CONTROL.ReportOutput('button', 'OnIn', world, world), 'caller identity required')
button = setup('toggle'); button.genericReports = true
id = CONTROL.Request('button', 'pressIn', {actor = 'Generic automation'}); button:Complete()
check(CONTROL.GetRequest(id).status == 'completed' and calls == 1 and CONTROL.Controls.button.lastActor == 'Generic automation',
    'ID-free outputs resolve their registered entity and retain accepted actor identity')
CONTROL.ReportOutput('OnIn', button, world)
check(calls == 1, 'duplicate ID-free endpoint cannot dispatch twice')
local impostor = entity('CTRLI_button')
check(not CONTROL.ReportOutput('OnPressed', impostor, world) and not CONTROL.ReportOutput('OnPressed', 'CTRLI_button', world),
    'ID-free output requires the actual registered entity, not a matching name or string')
button.name = 'changed_target'
check(not CONTROL.ReportOutput('OnPressed', button, world), 'ID-free output still validates full targetname')
button.name = 'CTRLI_button'; button.class = 'prop_dynamic'
check(not CONTROL.ReportOutput('OnPressed', button, world), 'ID-free output still validates class')
button = setup('momentary'); button.genericReports = true
id = CONTROL.Request('button', 'press', {}); button:Complete()
check(CONTROL.GetRequest(id).status == 'completed' and calls == 1, 'ID-free press executes once and endpoint acknowledges movement')
check(CONTROL.Wiring('first') == CONTROL.Wiring('second') and string.find(CONTROL.Wiring(), "ReportOutput('OnPressed',CALLER,ACTIVATOR)", 1, true),
    'generated Hammer wiring is identical for every control')

button = setup('toggle')
CONTROL.Lock('button', 'owner', 'blocked')
id = CONTROL.Request('button', 'pressOutLock', {owner = 'new_owner'})
advance(2)
check(CONTROL.GetRequest(id).status == 'expired' and CONTROL.Controls.button.locks.new_owner == nil, 'expiry applies no combined lock')
local first = CONTROL.Request('button', 'pressIn', {})
local latest = CONTROL.Request('button', 'pressOut', {})
check(CONTROL.GetRequest(first).status == 'superseded', 'single latest pending request')
CONTROL.CancelRequest(latest)
CONTROL.Unlock('button', 'owner')
check(button.state == 1, 'cancelled pending request must not execute')

button = setup('toggle')
id = CONTROL.Request('button', 'pressOutLock', {owner = 'owner'})
check(CONTROL.GetRequest(id).status == 'completed' and calls == 0, 'already-satisfied Out does not repeat action')
advance(0)
check(button.locked, 'already-satisfied combined operation still locks next tick')

button = setup('toggle')
id = CONTROL.Request('button', 'pressInLock', {owner = 'owner'})
advance(0)
CONTROL.Lock('button', 'other', 'new safety blocker')
button:Complete()
check(CONTROL.GetRequest(id).status == 'failed', 'other owner must block action-bearing output')
button:Complete()
check(CONTROL.Controls.button.fault ~= nil and button.state == 1, 'rejected lever restores accepted position')
check(CONTROL.ResetFault('button') and CONTROL.Controls.button.locks.other ~= nil, 'fault reset preserves owner locks')

button = setup('momentary')
id = CONTROL.Request('button', 'pressLock', {owner = 'owner'})
check(calls == 1 and not button.locked, 'pressLock runs ordinary physical press first')
advance(0)
check(button.locked, 'pressLock next-tick lock')
button:Complete()
check(CONTROL.GetRequest(id).status == 'completed', 'momentary endpoint acknowledges request')
button.target = 'out'; button:Complete()
check(calls == 1 and not CONTROL.Controls.button.returning, 'momentary return does not repeat action')

button = setup('toggle')
id = CONTROL.Request('button', 'pressIn', {})
advance(5)
check(CONTROL.GetRequest(id).status == 'failed', 'missing endpoint acknowledgement times out')
CONTROL.Stop()
check(not hooks.Think.LUASQUARE_CONTROL_Think and next(CONTROL.EntityControls) == nil, 'stop removes runtime hooks and entities')

setup('toggle')
local valid = CONTROL.DeepCopy(sources.test)
valid.controls = {{id = 'pad', kind = 'keypad', display = 'digits', maxDigits = 3, maxValue = 100, initialValue = 20,
    clearOnSubmit = false, cooldown = 0, keys = {}, actions = {submit = {id = 'test.action'}}}}
for _, token in ipairs(CONTROL.KeypadKeyTokens) do
    if token ~= 'b' and token ~= 'c' then
        local target = 'CTRLI_KPD_' .. token .. '_pad'
        valid.controls[1].keys[token] = target
        entity(target).genericReports = true
    end
end
sources.test = valid
local keypadCatalog = {Actions = CONTROL.Actions, Predicates = CONTROL.Predicates, Displays = LUASQUARE_SEG7.Displays}
CONTROL.Stop(); assert(CONTROL.Start('test'))
local padSnapshot = CONTROL.GetSnapshot().controls
local memberCount, keyCount = 0, 0
for _ in pairs(padSnapshot) do memberCount = memberCount + 1 end
for _ in pairs(padSnapshot.pad.keys) do keyCount = keyCount + 1 end
check(memberCount == 1 and keyCount == 11 and not padSnapshot['pad.key.0'], 'keypad is one public member with nested physical key states')
CONTROL.Lock('pad', 'procedure', 'parent unavailable')
local allLocked = true
for _, keyId in pairs(CONTROL.Controls.pad.keyControls) do allLocked = allLocked and CONTROL.Controls[keyId].entity.locked end
check(allLocked, 'parent owner lock immediately locks all owned keys')
CONTROL.Unlock('pad', 'procedure')
check(not CONTROL.Controls['pad.key.0'].entity.locked, 'parent unlock synchronizes owned physical keys')
CONTROL.EditKeypad('pad', 'clear')
id = CONTROL.Request('pad.key.7', 'press', {actor = 'Keypad operator'})
local keyButton = CONTROL.Controls['pad.key.7'].entity
keyButton:Complete(); keyButton.target = 'out'; keyButton:Complete()
check(CONTROL.Controls.pad.buffer == '7' and CONTROL.GetRequest(id).status == 'completed', 'generated physical digit executes its parent edit without authored actions')
id = CONTROL.Request('pad.key.s', 'press', {actor = 'Keypad operator'})
keyButton = CONTROL.Controls['pad.key.s'].entity; keyButton:Complete(); keyButton.target = 'out'; keyButton:Complete()
check(CONTROL.Controls.pad.acceptedValue == 7 and CONTROL.Controls.pad.lastActor == 'Keypad operator', 'generated submit uses parent action and actual actor attribution')
advance(0.3)
CONTROL.Lock('pad', 'retained', 'keep owner lock')
CONTROL.Controls['pad.key.1'].fault = 'key test fault'
check(not CONTROL.IsAvailable('pad') and not CONTROL.IsAvailable('pad.key.0'), 'owned key fault makes the keypad and other keys unavailable')
local faultButton = CONTROL.Controls['pad.key.1'].entity
faultButton.name = 'wrong_binding'
check(not CONTROL.ResetFault('pad') and CONTROL.Controls['pad.key.1'].fault, 'group fault reset validates every physical key before clearing')
faultButton.name = 'CTRLI_KPD_1_pad'
check(CONTROL.ResetFault('pad') and not CONTROL.Controls['pad.key.1'].fault and CONTROL.Controls.pad.locks.retained,
    'one keypad fault reset reconciles owned keys and preserves independent parent owner locks')
CONTROL.Unlock('pad', 'retained')
CONTROL.Controls.pad.acceptedValue = 20
local adapterCatalog = {}
LUASQUARE_TIMELINE = {UnregisterComponent = function() end, RegisterComponent = function(id, definition) adapterCatalog[id] = definition end}
CONTROL.RegisterAdapters()
check(adapterCatalog['control.pad'] and adapterCatalog['control.pad'].actions.submitvalue and not adapterCatalog['control.pad.key.0'],
    'timeline catalogs expose one keypad submission and hide generated keys')
LUASQUARE_TIMELINE = nil
CONTROL.EditKeypad('pad', 'clear')
CONTROL.EditKeypad('pad', 'digit', 9); CONTROL.EditKeypad('pad', 'digit', 9); CONTROL.EditKeypad('pad', 'digit', 9)
check(CONTROL.Controls.pad.buffer == '100', 'keypad maximum clamping')
reject = true
id = CONTROL.Request('pad', 'submitValue', {})
check(CONTROL.GetRequest(id).status == 'failed' and not CONTROL.Controls.pad.fault
    and CONTROL.Controls.pad.buffer == '100' and CONTROL.Controls.pad.acceptedValue == 20,
    'expected keypad rejection preserves buffer and target without a sticky fault')
reject = false; CONTROL.ResetFault('pad')
id = CONTROL.Request('pad', 'submitValue', {value = 35})
check(CONTROL.GetRequest(id).status == 'completed' and CONTROL.Controls.pad.acceptedValue == 35 and CONTROL.Controls.pad.buffer == '35', 'direct numeric submit uses same authoritative action')
check(CONTROL.Request('pad', 'submitValue', {value = 1.5}) == nil, 'fractional keypad input rejected')

local bad = CONTROL.DeepCopy(valid)
bad.controls[1].keys['0'] = nil
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'keypad requires every digit binding')
bad = CONTROL.DeepCopy(valid); bad.controls[1].keys.s = nil
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'keypad requires submit binding')
bad = CONTROL.DeepCopy(valid); bad.controls[1].keys.b = 'CTRLI_KPD_b_pad'; bad.controls[1].keys.c = 'CTRLI_KPD_c_pad'
local grouped = CONTROL.CompileSource(bad, 'keypad test', keypadCatalog)
check(grouped and #grouped.controls == 14, 'optional clear/backspace generate owned keys when supplied')
CONTROL.Stop(); sources.test = bad
entity('CTRLI_KPD_b_pad').genericReports = true; entity('CTRLI_KPD_c_pad').genericReports = true
assert(CONTROL.Start('test'))
CONTROL.EditKeypad('pad', 'clear'); CONTROL.EditKeypad('pad', 'digit', 4); CONTROL.EditKeypad('pad', 'digit', 2)
CONTROL.Request('pad.key.b', 'press', {})
keyButton = CONTROL.Controls['pad.key.b'].entity; keyButton:Complete(); keyButton.target = 'out'; keyButton:Complete()
check(CONTROL.Controls.pad.buffer == '4', 'generated optional backspace edits the owned buffer')
CONTROL.Request('pad.key.c', 'press', {})
keyButton = CONTROL.Controls['pad.key.c'].entity; keyButton:Complete(); keyButton.target = 'out'; keyButton:Complete()
check(CONTROL.Controls.pad.buffer == '', 'generated optional clear empties the owned buffer')
CONTROL.Request('pad.key.s', 'press', {})
keyButton = CONTROL.Controls['pad.key.s'].entity; keyButton:Complete(); keyButton.target = 'out'; keyButton:Complete()
check(CONTROL.Controls.pad.acceptedValue == 0, 'generated physical submit preserves empty-as-zero behavior')
bad = CONTROL.DeepCopy(valid); bad.controls[1].keys.x = 'CTRLI_KPD_x_pad'
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'unknown key slots rejected')
bad = CONTROL.DeepCopy(valid); bad.controls[1].keys['0'] = bad.controls[1].keys['1']
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'duplicate physical key targets rejected')
bad = CONTROL.DeepCopy(valid); bad.controls[1].keys['0'] = 'CTRLI_KPD_s_anotherpad'
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'KPD token must match its authored slot')
bad = CONTROL.DeepCopy(valid); bad.controls[1].keys['0'] = '../unsafe'
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'unsafe keypad bindings rejected')
bad = CONTROL.DeepCopy(valid); bad.controls[1].keys['0'] = 'CTRLI_custom_override'
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) ~= nil, 'safe non-KPD manual target overrides supported')
bad = CONTROL.DeepCopy(valid); bad.controls[2] = {id = 'pad.key.0', kind = 'momentary'}
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'generated key IDs cannot collide with declared controls')
local oldLimit = CONTROL.MaxControls; CONTROL.MaxControls = 5
check(CONTROL.CompileSource(valid, 'keypad test', keypadCatalog) == nil, 'map limit counts generated physical subcomponents')
CONTROL.MaxControls = oldLimit
bad = CONTROL.DeepCopy(valid)
bad.controls[1].lua = 'return true'
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'executable or unknown fields rejected')
bad = CONTROL.DeepCopy(valid); bad.controls[2] = CONTROL.DeepCopy(bad.controls[1])
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'duplicate IDs rejected')
bad = CONTROL.DeepCopy(valid); bad.controls[1].actions.submit.id = 'unknown'
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'unknown registrations rejected')
bad = CONTROL.DeepCopy(valid); bad.controls[1].maxValue = math.huge
check(CONTROL.CompileSource(bad, 'keypad test', keypadCatalog) == nil, 'nonfinite JSON numbers rejected')
bad = CONTROL.DeepCopy(valid); bad.controls[1].display = 'unknown'
check(CONTROL.CompileSource(bad, 'test', {Actions = CONTROL.Actions, Predicates = CONTROL.Predicates, Displays = LUASQUARE_SEG7.Displays}) == nil, 'unknown SEG7 references rejected')

-- Migrated RBMK sources are compiled against actual component registrations by
-- check_map.js; this suite keeps the Control Layer behavioral regressions.
local compiled, diagnostics
for _, definition in ipairs(DFR_SOURCE.controls) do
    for _, ref in pairs(definition.actions or {}) do CONTROL.RegisterAction(ref.id, {parameters = {}, callback = function() return true end}) end
    for _, ref in ipairs(definition.predicates or {}) do CONTROL.RegisterPredicate(ref.id, {parameters = {}, callback = function() return true end}) end
end
compiled, diagnostics = CONTROL.CompileSource(DFR_SOURCE, 'packed DFR')
check(compiled ~= nil, CONTROL.DiagnosticsText(diagnostics))
local timers = {}
timer = {Exists = function(id) return timers[id] ~= nil end,
    Create = function(id, _, _, callback) timers[id] = callback end, Remove = function(id) timers[id] = nil end}
LUASQUARE_TIMELINE = {TickInterval = 0.05}
include('luasquare_module/timeline/shared.lua')
include('luasquare_module/timeline/compiler.lua')
include('luasquare_module/timeline/runtime.lua')
local TIMELINE = LUASQUARE_TIMELINE
TIMELINE.RegisterComponent('test.owner', {safeReset = function() end, actions = {}})
local function choreography(required, operation)
    return {id = 'control_test', label = 'Control test', channel = 'test', duration = 0,
        restartPolicy = 'restart', conflictPolicy = 'replace', tracks = {{id = 'controls'}}, clips = {{id = 'request', at = 0, kind = 'marker',
            target = {kind = 'component', id = 'control.button'}, action = operation or 'pressin', params = {},
            required = required, minimumSuccess = 0, trackIndex = 1}}}
end
button = setup('toggle')
local ok, run = TIMELINE.StartCompiled('test.owner', 'required', choreography(true, 'pressinlock'), {actor = 'DECAOS'})
check(ok and run.status == 'running', 'timeline must remain running until required movement completes')
advance(0)
check(button.locked and CONTROL.Controls.button.locks[run.controlOwner], 'timeline combined operation uses valid isolated owner')
button:Complete(); TIMELINE.Tick()
check(run.status == 'completed' and CONTROL.History[#CONTROL.History].actor == 'DECAOS', 'timeline completion and automation blame survive asynchronous movement')

button = setup('toggle'); CONTROL.Lock('button', 'safety', 'blocked')
ok, run = TIMELINE.StartCompiled('test.owner', 'expiry', choreography(true), {})
advance(2); TIMELINE.Tick()
check(run.status == 'failed', 'required control expiry fails timeline')
ok, run = TIMELINE.StartCompiled('test.owner', 'optional', choreography(false), {})
advance(2); TIMELINE.Tick()
check(run.status == 'completed', 'optional control expiry produces diagnostics without failing timeline')
ok, run = TIMELINE.StartCompiled('test.owner', 'cancel', choreography(true), {})
local pendingId = run.controlRequests[1].id
TIMELINE.CancelRun(run, 'test cancellation'); CONTROL.Unlock('button', 'safety')
check(CONTROL.GetRequest(pendingId).status == 'cancelled' and button.state == 1, 'timeline cancellation removes pending physical requests')
check(not TIMELINE.StartCompiled('test.owner', 'seek', choreography(false), {}, {seekTo = 1}), 'optional physical markers also reject nonzero seek')
check(not TIMELINE.StartCompiled('test.owner', 'preview', choreography(false), {}, {preview = true}), 'controls excluded from live timeline preview before dispatch')

button = setup('toggle')
local originalInput = button.Input
button.Input = function(self, name, ...) if name == 'PressIn' then return false end; return originalInput(self, name, ...) end
id = CONTROL.Request('button', 'pressInLock', {owner = 'dispatch_failure'})
advance(0)
check(CONTROL.GetRequest(id).status == 'failed' and not CONTROL.Controls.button.locks.dispatch_failure, 'failed physical dispatch creates no next-tick owner lock')
button = setup('toggle')
id = CONTROL.Request('button', 'pressOutLock', {owner = 'editor.1'})
CONTROL.UnlockOwner('editor.1'); advance(0)
check(not CONTROL.Controls.button.locks['editor.1'], 'closing an owner cancels its scheduled next-tick lock')

local draft = CONTROL.NewPreview(assert(CONTROL.CompileSource(sources.test)))
local liveCalls = calls
draft:Request('button', 'pressInLock'); draft:Step(0.05); draft:Endpoint('button')
check(draft.controls.button.locks.preview and draft.controls.button.acceptedPosition == 'in' and calls == liveCalls and button.state == 1,
    'local draft simulation mutates neither authoritative controls nor registered actions')
bad = CONTROL.DeepCopy(sources.test); bad.controls[1].predicates = {unexpected = {id = 'test.available'}}
check(CONTROL.CompileSource(bad) == nil, 'predicate objects cannot masquerade as arrays')

button = setup('toggle')
id = CONTROL.Request('button', 'pressInLock', {owner = 'owner'})
advance(0); CONTROL.Lock('button', 'owner', 'new same-owner restriction'); button:Complete()
check(CONTROL.GetRequest(id).status == 'failed', 'same-owner lock replacement is a new blocker, not the admitted operation lock')
button:Complete(); button.name = 'changed_binding'
check(not CONTROL.ResetFault('button'), 'fault reset requires unchanged valid binding')
button.name = 'CTRLI_button'; check(CONTROL.ResetFault('button'), 'fault resets after binding and position match')

button = setup('toggle')
id = CONTROL.Request('button', 'pressIn', {})
local oldPending = CONTROL.Request('button', 'pressOut', {})
local newPending = CONTROL.Request('button', 'pressOut', {})
check(CONTROL.GetRequest(id).status == 'dispatched' and CONTROL.GetRequest(oldPending).status == 'superseded', 'new pending request preserves dispatched movement')
button:Complete(); advance(0.05); button:Complete()
check(CONTROL.GetRequest(newPending).status == 'completed' and calls == 2, 'latest queued request dispatches behind completed movement')

button = setup('momentary')
button.GetKeyValues = function() return {wait = 10} end
id = CONTROL.Request('button', 'press', {}); button:Complete(); advance(6)
check(not CONTROL.Controls.button.fault and CONTROL.Controls.button.returning, 'momentary acknowledgement allows original Hammer wait before return')
button.target = 'out'; button:Complete()

button = setup('momentary')
local readVariable = button.GetInternalVariable
button.GetInternalVariable = function(self, key)
    if key == 'm_flWait' then return 10 end
    return readVariable(self, key)
end
button.GetKeyValues = function() return {} end
id = CONTROL.Request('button', 'press', {}); button:Complete(); advance(6)
check(not CONTROL.Controls.button.fault and CONTROL.Controls.button.returning,
    'inherited engine wait survives missing Hammer keyvalue and prevents premature return fault')
button.target = 'out'; button:Complete()
check(not CONTROL.Controls.button.returning and not CONTROL.Controls.button.fault,
    'delayed native return clears movement tracking without fault')

button = setup('toggle')
CONTROL.Controls.button.rejectNextOwner = 'editor.1'
id = CONTROL.Request('button', 'pressIn', {}); button:Complete(); button:Complete()
check(CONTROL.GetRequest(id).status == 'failed' and calls == 0 and CONTROL.ResetFault('button'), 'explicit rejection fixture restores without calling component')
CONTROL.Controls.button.rejectNextOwner = 'editor.1'; CONTROL.CancelOwner('editor.1')
check(not CONTROL.Controls.button.rejectNextOwner, 'editor cancellation clears unused owned fixture')

button = setup('toggle')
local actor = entity('Lambda actor', 'npc_test')
id = CONTROL.Request('button', 'pressIn', {actor = actor}); actor.valid = false; button:Complete()
check(CONTROL.Controls.button.lastActor == 'Lambda actor' and CONTROL.History[#CONTROL.History].actor == 'Lambda actor', 'actor identity survives entity removal during movement')

button = setup('toggle')
id = CONTROL.Request('button', 'pressIn', {});
check(CONTROL.ReloadSources('test') and CONTROL.GetRequest(id) == nil and CONTROL.Controls.button.recovering, 'reload cancels old requests and internally reconciles interrupted movement')
button:Complete()
check(calls == 0 and CONTROL.ResetFault('button'), 'reloaded movement never dispatches an abandoned component action')

button = setup('toggle')
CONTROL.RegisterAction('test.typed', {parameters = {number = {type = 'integer', min = 0, max = 10}},
    allowRequestParams = true, callback = function(_, params) calls = params.number; return true end})
CONTROL.Controls.button.actions['in'] = {id = 'test.typed', params = {number = 3}}
local payload = {number = 7}
id = CONTROL.Request('button', 'pressIn', {params = payload}); payload.number = 2; button:Complete()
check(calls == 7, 'typed asynchronous request parameters are copied and validated')
CONTROL.Controls.button.actions.out = {id = 'test.typed', params = {number = 3}}
id = CONTROL.Request('button', 'pressOut', {params = {number = 1.5}}); button:Complete()
check(CONTROL.GetRequest(id).status == 'failed' and calls == 7, 'invalid typed override cannot reach trusted action')

-- Network permission, subscriber lifecycle, payload bounds and immediate state tests.
button = setup('toggle')
local normalComplete = button.Complete
button.Complete = function(self)
    -- Source SDK TriggerAndWait checks m_bLocked before committing TS_AT_TOP/OnIn.
    if self.target == 'in' and self.locked then return end
    return normalComplete(self)
end
id = CONTROL.Request('button', 'pressInLock', {owner = 'owner'})
advance(0); button:Complete(); advance(5)
check(CONTROL.GetRequest(id).status == 'failed' and calls == 0 and CONTROL.Controls.button.locks.owner,
    'SDK lock-suppressed endpoint faults honestly and retains the combined owner lock')
button:Complete()
check(CONTROL.ResetFault('button') and CONTROL.Controls.button.locks.owner, 'SDK acknowledgement failure restores position without dropping owner lock')

button = setup('toggle')
local receivers, commands, sent, reads = {}, {}, {}, {}
function RealTime() return time end
game.SinglePlayer = function() return false end
util.AddNetworkString = function() end
util.TableToJSON = CONTROL.CanonicalJSON
util.Compress = function(value) return value end
ents.FindByClass = function(class)
    local result = {}
    for _, out in ipairs(entities) do if out.class == class then result[#result + 1] = out end end
    return result
end
concommand = {Add = function(id, callback) commands[id] = callback end}
net = {Receive = function(id, callback) receivers[id] = callback end,
    Start = function(id) sent[#sent + 1] = id end, WriteUInt = function() end,
    WriteData = function(value, bytes) assert(bytes <= CONTROL.ChunkBytes and #value == bytes) end,
    Send = function() end, Broadcast = function() end,
    ReadString = function() return table.remove(reads, 1) end,
    ReadBool = function() return table.remove(reads, 1) end,
    ReadDouble = function() return table.remove(reads, 1) end}
dofile('lua/luasquare_module/control/network_server.lua')
CONTROL.StartNetwork()
local player = entity('Admin', 'player')
function player:IsPlayer() return true end
function player:Nick() return self.name end
function player:IsAdmin() return self.admin == true end
function player:EntIndex() return 9 end
local receive = receivers.LUASQUARE_CONTROL_Command
reads = {'subscribe'}; receive(80, player)
check(#sent == 0, 'non-admin cannot subscribe or operate editor')
player.admin = true; reads = {'subscribe'}; receive(80, player)
check(#sent >= 3, 'late editor subscription receives catalog, source and initial state')
time = time + 2; reads = {'lock', 'button'}; local before = #sent; receive(80, player)
check(CONTROL.Controls.button.locks['editor.9'] and #sent > before, 'explicit locks publish subscriber state immediately')
reads = {'unlock', 'button'}; receive(80, player)
check(CONTROL.Controls.button.locks['editor.9'], 'editor commands obey rate limit')
time = time + 1; reads = {'unlock', 'button'}; receive(2049, player)
check(CONTROL.Controls.button.locks['editor.9'], 'oversized editor payload rejected')
reads = {'request', 'button', 'pressInLock', false}; receive(160, player)
local editorPending = CONTROL.Controls.button.pending.id
reads = {'close'}; receive(80, player)
check(not CONTROL.Controls.button.locks['editor.9'] and CONTROL.GetRequest(editorPending).status == 'cancelled', 'editor close cancels pending and releases owned locks')
CONTROL.Stop()
check(not hooks.Think.LUASQUARE_CONTROL_Network and not hooks.PlayerDisconnected.LUASQUARE_CONTROL_EditorDisconnect, 'stop removes subscriber hooks')
-- Partial manual migration must not block read-only discovery/authoring.
button.name = 'legacy_button'
entity('CTRLI_Alpha', 'func_button')
entity('CTRLI_alpha', 'func_rot_button')
entity('CTRLI_ignored', 'prop_dynamic')
entity('ctrli_lowercase', 'func_button')
entity('CTRLI_KPD_0_pad', 'func_button')
entity('CTRLI_KPD_s_pad', 'func_button')
entity('CTRLI_KPD_1_pad', 'func_rot_button')
check(not CONTROL.Start('test') and not CONTROL.Running, 'missing packed binding keeps runtime inactive')
local catalog = CONTROL.EditorCatalog()
check(#catalog.entities == 2 and catalog.entities[1].diagnostic == 'normalized suffix collision'
    and catalog.entities[2].diagnostic == 'normalized suffix collision',
    'offline discovery finds exact uppercase prefixes on both button classes and diagnoses collisions')
check(#catalog.keypadEntities == 3 and catalog.keypadEntities[1].key == '0' and catalog.keypadEntities[1].keypad == 'pad',
    'KPD discovery is separated from ordinary physical controls and identifies each key token/name')
check(catalog.keypadEntities[2].diagnostic == 'keypad subcomponents require func_button', 'KPD discovery diagnoses incompatible physical classes')
check(catalog.sources['data_static/luasquare/control/test/test.json'] == sources.test and #catalog.diagnostics > 0,
    'compiled packed source and binding diagnostics remain available for inactive authoring')
sent = {}; player.admin = false; time = time + 3
reads = {'subscribe'}; receive(80, player)
check(#sent == 0, 'offline discovery retains editor permission checks')
player.admin = true; reads = {'subscribe'}; receive(80, player)
check(#sent >= 3 and hooks.PlayerDisconnected.LUASQUARE_CONTROL_EditorDisconnect,
    'inactive editor receives discovery catalog, sources and state with disconnect cleanup')
local serialBefore = CONTROL.Serial
time = time + 3; reads = {'request', 'button', 'pressIn', false}; receive(160, player)
check(CONTROL.Serial == serialBefore and button.state == 1, 'inactive discovery does not enable live gameplay requests')
hook.Run('PlayerDisconnected', player)
CONTROL.StopNetwork()
check(not hooks.PlayerDisconnected.LUASQUARE_CONTROL_EditorDisconnect, 'inactive editor subscription cleans up')
print('Passed ' .. count .. ' Control Layer/timeline/network assertions and DFR packed-source compiler check; RBMK compilation is covered by check_map.js.')
