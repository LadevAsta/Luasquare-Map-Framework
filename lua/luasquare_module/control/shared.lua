local CONTROL = LUASQUARE_CONTROL
CONTROL.KeypadKeyTokens = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 's', 'b', 'c'}
CONTROL.KeypadKeyLabels = {s = 'Submit', b = 'Backspace', c = 'Clear'}

function CONTROL.KeypadKeyId(id, token) return id .. '.key.' .. token end

function CONTROL.KeypadKeyName(target)
    if type(target) ~= 'string' then return end
    return string.match(target, '^CTRLI_KPD_([0-9sbc])_(.+)$')
end

function CONTROL.NormalizeId(value)
    if type(value) ~= 'string' or #value > 128 then return nil end
    value = string.lower(value)
    return string.match(value, '^[a-z0-9_][a-z0-9_%.%-]*$') and value or nil
end

function CONTROL.Finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

function CONTROL.DeepCopy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = CONTROL.DeepCopy(child) end
    return result
end

function CONTROL.SafeTree(value, depth, seen)
    depth, seen = depth or 0, seen or {}
    if depth > 16 then return false end
    if type(value) == 'number' then return CONTROL.Finite(value) end
    if type(value) == 'string' then return #value <= 4096 end
    if type(value) ~= 'table' then return type(value) == 'boolean' or value == nil end
    if seen[value] then return false end
    seen[value] = true
    local count = 0
    for key, child in pairs(value) do
        count = count + 1
        if count > 4096 or (type(key) ~= 'string' and type(key) ~= 'number')
            or not CONTROL.SafeTree(child, depth + 1, seen) then return false end
    end
    seen[value] = nil
    return true
end

function CONTROL.ValidateParameters(definition, values)
    if values == nil then values = {} end
    if type(values) ~= 'table' then return nil, 'parameters must be an object' end
    local result = {}
    local fields = definition.parameters or {}
    for key in pairs(values) do if not fields[key] then return nil, 'unknown parameter ' .. tostring(key) end end
    for key, field in pairs(fields) do
        local value = values[key]
        if value == nil then value = field.default end
        if value == nil and field.optional then
            result[key] = nil
        elseif field.type == 'number' or field.type == 'integer' then
            if not CONTROL.Finite(value) or (field.type == 'integer' and value ~= math.floor(value))
                or (field.min and value < field.min) or (field.max and value > field.max) then
                return nil, 'invalid numeric parameter ' .. key
            end
            result[key] = value
        elseif field.type == 'boolean' then
            if type(value) ~= 'boolean' then return nil, 'invalid boolean parameter ' .. key end
            result[key] = value
        elseif field.type == 'string' then
            if type(value) ~= 'string' or #value > (field.maxLength or 128)
                or string.find(value, '[%z\1-\31]') then return nil, 'invalid string parameter ' .. key end
            if field.choices and not field.choices[value] then return nil, 'invalid choice ' .. key end
            result[key] = value
        else return nil, 'unknown parameter type ' .. key end
    end
    return result
end

local function jsonString(value)
    local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
    return '"' .. string.gsub(value, '[%z\1-\31\\"]', function(char)
        return escapes[char] or string.format('\\u%04x', string.byte(char))
    end) .. '"'
end

local function encode(value, depth)
    if value == nil then return 'null' end
    if type(value) == 'string' then return jsonString(value) end
    if type(value) ~= 'table' then return tostring(value) end
    local keys, count, maximum, array = {}, 0, 0, true
    for key in pairs(value) do
        count = count + 1
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then array = false else maximum = math.max(maximum, key) end
        table.insert(keys, key)
    end
    array = array and maximum == count and count > 0
    table.sort(keys, function(a, b) return array and a < b or (not array and tostring(a) < tostring(b)) end)
    local pieces, indent = {}, string.rep('  ', depth + 1)
    for _, key in ipairs(keys) do
        table.insert(pieces, indent .. (array and '' or jsonString(tostring(key)) .. ': ') .. encode(value[key], depth + 1))
    end
    local opening, closing = array and '[' or '{', array and ']' or '}'
    if count == 0 then return opening .. closing end
    return opening .. '\n' .. table.concat(pieces, ',\n') .. '\n' .. string.rep('  ', depth) .. closing
end

function CONTROL.CanonicalJSON(value)
    if not CONTROL.SafeTree(value) then return nil end
    return encode(value, 0) .. '\n'
end

function CONTROL.DiagnosticsText(diagnostics)
    local out = {}
    for _, item in ipairs(diagnostics or {}) do table.insert(out, (item.origin or '') .. ' ' .. item.path .. ': ' .. item.message) end
    return #out > 0 and table.concat(out, '\n') or 'Valid control source.'
end

function CONTROL.Wiring()
    local out = {}
    for _, event in ipairs({'OnPressed', 'OnIn', 'OnOut'}) do
        table.insert(out, event .. " -> <map lua_run> RunPassedCode: LUASQUARE_CONTROL.ReportOutput('" .. event .. "',CALLER,ACTIVATOR)")
    end
    return table.concat(out, '\n')
end
