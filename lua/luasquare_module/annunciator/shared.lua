LUASQUARE_ANNUNCIATOR = LUASQUARE_ANNUNCIATOR or {}
local ANN = LUASQUARE_ANNUNCIATOR

function ANN.NormalizeId(value)
    if value == nil then return nil end
    value = string.lower(tostring(value))
    value = string.gsub(value, '[^%w_%.%-:]', '_')
    return value ~= '' and value or nil
end

function ANN.DeepCopy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do
        result[ANN.DeepCopy(key, seen)] = ANN.DeepCopy(item, seen)
    end
    return result
end

function ANN.Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.min(math.max(value, minimum), maximum)
end

function ANN.AddDiagnostic(diagnostics, severity, path, message, origin)
    table.insert(diagnostics, {
        severity = severity or 'error',
        path = tostring(path or '$'),
        message = tostring(message or 'unknown error'),
        origin = origin
    })
end

function ANN.HasErrors(diagnostics)
    for _, diagnostic in ipairs(diagnostics or {}) do
        if diagnostic.severity == 'error' then return true end
    end
    return false
end

function ANN.DiagnosticsText(diagnostics)
    local lines = {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        table.insert(lines, string.format('[%s] %s%s: %s',
            string.upper(diagnostic.severity or 'error'),
            diagnostic.origin and (diagnostic.origin .. ' ') or '',
            diagnostic.path or '$', diagnostic.message or ''))
    end
    return #lines > 0 and table.concat(lines, '\n') or 'Valid annunciator source.'
end

local function jsonString(value)
    local escapes = {
        ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
        ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'
    }
    return '"' .. string.gsub(tostring(value), '[%z\1-\31\\"]', function(character)
        return escapes[character] or string.format('\\u%04x', string.byte(character))
    end) .. '"'
end

local function isArray(value)
    local maximum, count = 0, 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then return false, 0 end
        maximum = math.max(maximum, key)
        count = count + 1
    end
    return count > 0 and maximum == count, maximum
end

local function encodeJSON(value, pretty, depth, seen)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return 'null' end
        return tostring(value)
    end
    if kind == 'string' then return jsonString(value) end
    if kind ~= 'table' or seen[value] then return 'null' end
    seen[value] = true
    local array, maximum = isArray(value)
    local currentIndent = pretty and string.rep('  ', depth) or ''
    local childIndent = pretty and string.rep('  ', depth + 1) or ''
    local separator = pretty and ',\n' or ','
    local spacer = pretty and ': ' or ':'
    local parts = {}
    if array then
        for index = 1, maximum do
            table.insert(parts, childIndent .. encodeJSON(value[index], pretty, depth + 1, seen))
        end
    else
        local keys = {}
        for key in pairs(value) do table.insert(keys, tostring(key)) end
        table.sort(keys)
        for _, key in ipairs(keys) do
            table.insert(parts, childIndent .. jsonString(key) .. spacer
                .. encodeJSON(value[key], pretty, depth + 1, seen))
        end
    end
    seen[value] = nil
    local opening, closing = array and '[' or '{', array and ']' or '}'
    if #parts == 0 then return opening .. closing end
    if pretty then return opening .. '\n' .. table.concat(parts, separator) .. '\n' .. currentIndent .. closing end
    return opening .. table.concat(parts, separator) .. closing
end

function ANN.CanonicalJSON(source, pretty)
    return encodeJSON(source, pretty ~= false, 0, {})
end

function ANN.GetPath(value, path)
    if path == nil or path == '' then return value, true end
    if type(path) ~= 'string' then return nil, false end
    local current = value
    for part in string.gmatch(path, '[^%.]+') do
        if type(current) ~= 'table' then return nil, false end
        local key = tonumber(part) or part
        current = current[key]
        if current == nil then return nil, false end
    end
    return current, true
end

function ANN.IsSafeTargetname(value)
    return type(value) == 'string' and value ~= ''
        and not string.find(value, '[%z\1-\31]')
        and not string.find(value, '[;\r\n]')
end

function ANN.GetTierColor(tier)
    local colors = {
        [1] = {245, 245, 245, 255},
        [2] = {255, 196, 48, 255},
        [3] = {235, 56, 48, 255},
        [4] = {204, 48, 220, 255}
    }
    return ANN.DeepCopy(colors[tonumber(tier)] or colors[2])
end

function ANN.GetVisualState(state)
    if not state then return 'off' end
    if state.test then return 'fast_flash' end
    if state.active then return state.acknowledged and 'on' or 'fast_flash' end
    if state.resolved then return 'slow_flash' end
    return 'off'
end

local comparisons = {
    eq = function(left, right) return left == right end,
    ne = function(left, right) return left ~= right end,
    gt = function(left, right) return type(left) == 'number' and type(right) == 'number' and left > right end,
    gte = function(left, right) return type(left) == 'number' and type(right) == 'number' and left >= right end,
    lt = function(left, right) return type(left) == 'number' and type(right) == 'number' and left < right end,
    lte = function(left, right) return type(left) == 'number' and type(right) == 'number' and left <= right end,
    truthy = function(left) return left and true or false end
}

function ANN.ResolveOperand(operand, samples)
    if type(operand) ~= 'table' or operand.provider == nil then return operand, true end
    local sample = samples and samples[operand.provider]
    if sample == nil then return nil, false end
    return ANN.GetPath(sample, operand.path)
end

function ANN.EvaluateCondition(condition, samples)
    if type(condition) ~= 'table' then return false, false end
    if condition.all then
        local allTrue = true
        for _, child in ipairs(condition.all) do
            local result, valid = ANN.EvaluateCondition(child, samples)
            if not valid then return false, false end
            if not result then allTrue = false end
        end
        return allTrue, true
    end
    if condition.any then
        local anyTrue = false
        for _, child in ipairs(condition.any) do
            local result, valid = ANN.EvaluateCondition(child, samples)
            if not valid then return false, false end
            if result then anyTrue = true end
        end
        return anyTrue, true
    end
    if condition['not'] then
        local result, valid = ANN.EvaluateCondition(condition['not'], samples)
        return not result, valid
    end
    local left, leftValid = ANN.ResolveOperand({
        provider = condition.provider,
        path = condition.path
    }, samples)
    if not leftValid then return false, false end
    local right, rightValid = ANN.ResolveOperand(condition.value, samples)
    if not rightValid then return false, false end
    local compare = comparisons[condition.op]
    if not compare then return false, false end
    return compare(left, right), true
end
