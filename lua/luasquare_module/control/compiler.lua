local CONTROL = LUASQUARE_CONTROL
local allowedFields = {id = true, label = true, kind = true, target = true, class = true, predicates = true,
    cooldown = true, lockIndicator = true, actions = true, maxDigits = true, maxValue = true,
    initialValue = true, clearOnSubmit = true, display = true, parent = true, initialPosition = true, keys = true}

function CONTROL.CompileSource(source, origin, catalogs)
    catalogs = catalogs or CONTROL
    local diagnostics, compiled, ids = {}, {}, {}
    local function errorAt(path, message) table.insert(diagnostics, {origin = origin, path = path, message = message, severity = 'error'}) end
    local function denseArray(value, path, limit)
        if type(value) ~= 'table' then errorAt(path, 'expected array'); return false end
        local count = 0
        for key in pairs(value) do
            count = count + 1
            if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then errorAt(path, 'expected dense array'); return false end
        end
        if count ~= #value or count > limit then errorAt(path, 'invalid or excessive array'); return false end
        return true
    end
    local function reference(ref, catalog, path)
        if type(ref) ~= 'table' or not CONTROL.NormalizeId(ref.id) then errorAt(path, 'expected registered reference'); return end
        for key in pairs(ref) do if key ~= 'id' and key ~= 'params' then errorAt(path, 'unknown reference field ' .. tostring(key)) end end
        local definition = catalog and catalog[ref.id]
        if not definition then errorAt(path, 'unknown registration ' .. ref.id); return end
        local params, message = CONTROL.ValidateParameters(definition, ref.params)
        if not params then errorAt(path, message); return end
        return {id = ref.id, params = params}
    end
    if type(source) ~= 'table' or not CONTROL.SafeTree(source) then errorAt('$', 'invalid or excessive JSON tree'); return nil, diagnostics end
    for key in pairs(source) do if key ~= 'schema' and key ~= 'id' and key ~= 'controls' then errorAt('$', 'unknown pack field ' .. tostring(key)) end end
    if source.schema ~= CONTROL.Schema then errorAt('$.schema', 'expected ' .. CONTROL.Schema) end
    if not CONTROL.NormalizeId(source.id) or source.id ~= CONTROL.NormalizeId(source.id) then errorAt('$.id', 'expected lowercase stable ID') end
    if type(source.controls) ~= 'table' then errorAt('$.controls', 'expected controls array'); return nil, diagnostics end
    local count = 0
    for index in pairs(source.controls) do
        count = count + 1
        if type(index) ~= 'number' or index < 1 or index ~= math.floor(index) then errorAt('$.controls', 'expected dense array') end
    end
    if count ~= #source.controls or count > CONTROL.MaxControls then errorAt('$.controls', 'invalid or excessive controls array') end
    for index, input in ipairs(source.controls) do
        local path = '$.controls[' .. index .. ']'
        if type(input) ~= 'table' then errorAt(path, 'expected control object') else
            local control = CONTROL.DeepCopy(input)
            for key in pairs(control) do if not allowedFields[key] then errorAt(path, 'unknown control field ' .. tostring(key)) end end
            local id = CONTROL.NormalizeId(control.id)
            if not id or id ~= control.id or ids[id] then errorAt(path .. '.id', 'invalid or duplicate lowercase ID') end
            if id then ids[id] = true end
            if control.kind ~= 'momentary' and control.kind ~= 'toggle' and control.kind ~= 'keypad' then errorAt(path .. '.kind', 'expected momentary, toggle, or keypad') end
            control.label = control.label or control.id
            if type(control.label) ~= 'string' or #control.label > 160 then errorAt(path .. '.label', 'invalid label') end
            control.cooldown = control.cooldown == nil and 0.25 or control.cooldown
            if not CONTROL.Finite(control.cooldown) or control.cooldown < 0 or control.cooldown > 60 then errorAt(path .. '.cooldown', 'expected 0..60 seconds') end
            if control.target then
                if type(control.target) ~= 'string' or #control.target > 160 or not string.match(control.target, '^CTRLI_[%w_%.%-]+$') then errorAt(path .. '.target', 'expected exact CTRLI_ targetname') end
                if control.class ~= 'func_button' and control.class ~= 'func_rot_button' then errorAt(path .. '.class', 'unsupported button class') end
                if control.kind == 'keypad' then errorAt(path, 'keypad binds physical subcomponents in keys') end
            elseif control.class then errorAt(path .. '.class', 'class requires target') end
            if control.lockIndicator and (type(control.lockIndicator) ~= 'string' or not string.match(control.lockIndicator, '^[%w_%.%-]+$')) then errorAt(path .. '.lockIndicator', 'unsafe sprite targetname') end
            if control.parent and control.parent ~= CONTROL.NormalizeId(control.parent) then errorAt(path .. '.parent', 'invalid parent keypad ID') end
            if control.initialPosition and control.initialPosition ~= 'in' and control.initialPosition ~= 'out' then errorAt(path .. '.initialPosition', 'expected in or out') end
            local predicates = {}
            if control.predicates ~= nil then denseArray(control.predicates, path .. '.predicates', 64) end
            for predicateIndex, ref in ipairs(type(control.predicates) == 'table' and control.predicates or {}) do
                local normalized = reference(ref, catalogs.Predicates, path .. '.predicates[' .. predicateIndex .. ']')
                if normalized then table.insert(predicates, normalized) end
            end
            control.predicates = predicates
            local actions = {}
            if control.actions ~= nil and type(control.actions) ~= 'table' then errorAt(path .. '.actions', 'expected object') end
            for event, ref in pairs(type(control.actions) == 'table' and control.actions or {}) do
                local allowed = control.kind == 'keypad' and event == 'submit' or control.kind == 'momentary' and event == 'press'
                    or control.kind == 'toggle' and (event == 'in' or event == 'out')
                if not allowed then errorAt(path .. '.actions.' .. tostring(event), 'event incompatible with kind') else
                    actions[event] = reference(ref, catalogs.Actions, path .. '.actions.' .. event)
                end
            end
            control.actions = actions
            if control.kind == 'keypad' then
                if not CONTROL.Finite(control.maxDigits) or control.maxDigits ~= math.floor(control.maxDigits) or control.maxDigits < 1 or control.maxDigits > 9 then errorAt(path .. '.maxDigits', 'expected integer 1..9') end
                if not CONTROL.Finite(control.maxValue) or control.maxValue < 0 or control.maxValue ~= math.floor(control.maxValue)
                    or (CONTROL.Finite(control.maxDigits) and control.maxValue > 10 ^ control.maxDigits - 1) then errorAt(path .. '.maxValue', 'invalid integer limit') end
                control.initialValue = control.initialValue or 0
                if not CONTROL.Finite(control.initialValue) or control.initialValue ~= math.floor(control.initialValue)
                    or control.initialValue < 0 or (CONTROL.Finite(control.maxValue) and control.initialValue > control.maxValue) then errorAt(path .. '.initialValue', 'outside keypad limits') end
                if control.clearOnSubmit ~= nil and type(control.clearOnSubmit) ~= 'boolean' then errorAt(path .. '.clearOnSubmit', 'expected boolean') end
                if not actions.submit then errorAt(path .. '.actions.submit', 'submit action required') end
                if control.display and not (catalogs.Displays and catalogs.Displays[control.display]) then errorAt(path .. '.display', 'unknown SEG7 display') end
                control.keyControls = {}
                if type(control.keys) ~= 'table' then errorAt(path .. '.keys', 'expected keypad key bindings: digits 0..9 and s are required') else
                    local allowedKeys, boundTargets = {}, {}
                    for _, token in ipairs(CONTROL.KeypadKeyTokens) do allowedKeys[token] = true end
                    for token in pairs(control.keys) do if not allowedKeys[token] then errorAt(path .. '.keys.' .. tostring(token), 'unknown keypad key') end end
                    for _, token in ipairs(CONTROL.KeypadKeyTokens) do
                        local target = control.keys[token]
                        local required = token ~= 'b' and token ~= 'c'
                        if target == nil and required then errorAt(path .. '.keys.' .. token, 'required physical key is missing')
                        elseif target ~= nil then
                            local keyPath = path .. '.keys.' .. token
                            if type(target) ~= 'string' or #target > 160 or not string.match(target, '^CTRLI_[%w_%.%-]+$') then
                                errorAt(keyPath, 'expected exact CTRLI_ targetname')
                            elseif boundTargets[target] then errorAt(keyPath, 'key target is already assigned') else
                                boundTargets[target] = true
                                local encodedToken = CONTROL.KeypadKeyName(target)
                                if string.sub(target, 1, 10) == 'CTRLI_KPD_' and encodedToken ~= token then errorAt(keyPath, 'KPD key token does not match this slot') end
                                local keyId = CONTROL.KeypadKeyId(id or 'invalid', token)
                                if keyId ~= CONTROL.NormalizeId(keyId) then errorAt(keyPath, 'keypad ID is too long for generated key IDs') end
                                local params = {keypad = control.id}
                                local actionId = 'control.keypad_edit'
                                if token == 's' then
                                    actionId = 'control.keypad_submit'
                                else
                                    params.operation = token == 'b' and 'backspace' or token == 'c' and 'clear' or 'digit'
                                    params.digit = tonumber(token)
                                end
                                local ref = reference({id = actionId, params = params}, catalogs.Actions, keyPath)
                                control.keyControls[token] = keyId
                                table.insert(compiled, {id = keyId, label = string.sub(tostring(control.label), 1, 140) .. ' / '
                                    .. (CONTROL.KeypadKeyLabels[token] or ('Digit ' .. token)), kind = 'momentary',
                                    parent = control.id, keypadKey = token, target = target, class = 'func_button',
                                    cooldown = 0.25, predicates = {}, actions = {press = ref}})
                            end
                        end
                    end
                end
            else
                for _, key in ipairs({'maxDigits', 'maxValue', 'initialValue', 'clearOnSubmit', 'display', 'keys'}) do
                    if control[key] ~= nil then errorAt(path .. '.' .. key, 'field requires keypad kind') end
                end
            end
            table.insert(compiled, control)
        end
    end
    local compiledIds, compiledTargets = {}, {}
    for _, control in ipairs(compiled) do
        local path = tostring(control.id or '$.controls')
        if control.id then
            if compiledIds[control.id] then errorAt(path, 'generated or declared control ID collision') end
            compiledIds[control.id] = true
        end
        if control.target then
            if compiledTargets[control.target] then errorAt(path, 'ambiguous physical binding') end
            compiledTargets[control.target] = true
        end
    end
    if #compiled > CONTROL.MaxControls then errorAt('$.controls', 'too many controls including keypad subcomponents') end
    if #diagnostics > 0 then return nil, diagnostics end
    return {id = source.id, controls = compiled}, diagnostics
end
