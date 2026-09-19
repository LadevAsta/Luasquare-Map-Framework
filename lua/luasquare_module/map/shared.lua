local MAP = LUASQUARE_MAP
MAP.JSONArrayMeta, MAP.JSONObjectMeta = {}, {}
function MAP.Array(value) return setmetatable(value or {}, MAP.JSONArrayMeta) end
function MAP.Object(value) return setmetatable(value or {}, MAP.JSONObjectMeta) end

function MAP.IsId(value)
    return type(value) == 'string' and #value <= 128 and value:match('^[a-z0-9_][a-z0-9_.%-]*$') ~= nil
end

function MAP.IsPort(value)
    return type(value) == 'string' and #value <= 128 and value:match('^[a-zA-Z0-9_][a-zA-Z0-9_.%-]*$') ~= nil
end

function MAP.Finite(value)
    return type(value) == 'number' and value == value and value ~= math.huge and value ~= -math.huge
end

function MAP.Copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    local meta = getmetatable(value)
    if meta == MAP.JSONArrayMeta or meta == MAP.JSONObjectMeta then setmetatable(result, meta) end
    for key, child in pairs(value) do result[key] = MAP.Copy(child) end
    return result
end

function MAP.IsArray(value)
    if type(value) ~= 'table' then return false end
    if getmetatable(value) == MAP.JSONObjectMeta then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
        count = count + 1
    end
    return count == #value
end

function MAP.Merge(base, override)
    local result = MAP.Object(MAP.Copy(base or {}))
    for key, value in pairs(override or {}) do
        if type(value) == 'table' and type(result[key]) == 'table'
            and not MAP.IsArray(value) and not MAP.IsArray(result[key]) then
            result[key] = MAP.Merge(result[key], value)
        else result[key] = MAP.Copy(value) end
    end
    return result
end

function MAP.SafeTree(value, stringLimit)
    local seen, count = {}, 0
    local function visit(child, depth)
        count = count + 1
        if count > MAP.Limits.values or depth > MAP.Limits.depth then return false end
        local kind = type(child)
        if kind == 'number' then return MAP.Finite(child) end
        if kind == 'string' then return #child <= (stringLimit or MAP.Limits.string) and not child:find('%z') end
        if kind ~= 'table' then return kind == 'boolean' or kind == 'nil' end
        if seen[child] then return false end
        seen[child] = true
        for key, item in pairs(child) do
            if type(key) == 'string' then
                if #key > 128 or key:find('[%z\1-\31]') then return false end
            elseif type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
            if not visit(item, depth + 1) then return false end
        end
        seen[child] = nil
        return true
    end
    return visit(value, 0)
end

function MAP.SourcePath(family, path)
    if not MAP.IsId(family) or type(path) ~= 'string' or #path > 240 then return nil end
    if path:sub(1, 1) == '/' or path:find('..', 1, true) or path:find('//', 1, true)
        or path:sub(1, 2) == './' or path:find('/./', 1, true)
        or not path:match('^[a-z0-9_/%-.]+%.json$') then return nil end
    return 'data_static/luasquare/' .. family .. '/' .. path
end

function MAP.RegisterType(id, definition)
    assert(MAP.IsId(id) and type(definition) == 'table', 'invalid component type')
    assert(not MAP.Types[id], 'duplicate component type: ' .. id)
    assert(type(definition.fields) == 'table', 'component fields required')
    MAP.Types[id] = definition
end

function MAP.RegisterPackage(id, definition)
    assert(MAP.IsId(id) and type(definition) == 'table', 'invalid package')
    assert(not MAP.Packages[id], 'duplicate package: ' .. id)
    MAP.Packages[id] = definition
end

function MAP.ValidateValue(field, value, path)
    path = path or 'config'
    if value == nil then
        if field.default ~= nil then value = MAP.Copy(field.default)
        elseif field.optional then return nil
        else return nil, path .. ': required field' end
    end
    local kind = field.type
    if field.oneOf then
        for _, choice in ipairs(field.oneOf) do
            local result, err = MAP.ValidateValue(choice, value, path)
            if not err then return result end
        end
        return nil, path .. ': no matching value type'
    end
    if kind == 'number' or kind == 'integer' then
        if not MAP.Finite(value) or (kind == 'integer' and value % 1 ~= 0)
            or (field.min and value < field.min) or (field.max and value > field.max) then
            return nil, path .. ': invalid ' .. kind
        end
    elseif kind == 'string' or kind == 'id' or kind == 'port' then
        if type(value) ~= 'string' or #value > (field.maxLength or 256)
            or value:find('[%z\1-\31]') or (kind == 'id' and not MAP.IsId(value)) or (kind == 'port' and not MAP.IsPort(value)) then
            return nil, path .. ': invalid ' .. kind
        end
        if field.choices and not field.choices[value] then return nil, path .. ': unknown choice' end
    elseif kind == 'boolean' then
        if type(value) ~= 'boolean' then return nil, path .. ': expected boolean' end
    elseif kind == 'array' or kind == 'vector' then
        if not MAP.IsArray(value) or #value > (field.maxItems or 4096)
            or #value < (field.minItems or 0) or (kind == 'vector' and #value ~= 3) then
            return nil, path .. ': invalid array size' end
        local result = MAP.Array()
        for i, child in ipairs(value) do
            local item, err = MAP.ValidateValue(kind == 'vector' and {type = 'number'} or field.items, child, path .. '[' .. i .. ']')
            if err then return nil, err end
            result[i] = item
        end
        return result
    elseif kind == 'object' then
        if type(value) ~= 'table' or getmetatable(value) == MAP.JSONArrayMeta then return nil, path .. ': expected object' end
        local result = {}
        for key in pairs(value) do
            if not (field.fields or {})[key] then return nil, path .. '.' .. tostring(key) .. ': unknown field' end
        end
        for key, descriptor in pairs(field.fields or {}) do
            local item, err = MAP.ValidateValue(descriptor, value[key], path .. '.' .. key)
            if err then return nil, err end
            result[key] = item
        end
        return result
    else return nil, path .. ': unregistered field type' end
    return value
end

function MAP.Linked(compiled, id, port)
    for _, link in ipairs(compiled.links) do
        if link.to.component == id and link.to.port == port then return link.from end
        if link.from.component == id and link.from.port == port then return link.to end
    end
end

function MAP.DiagnosticsText(diagnostics)
    local lines = {}
    for _, item in ipairs(diagnostics or {}) do
        lines[#lines + 1] = tostring(item.source or 'manifest') .. ':' .. tostring(item.path or '') .. ': ' .. item.message
    end
    return table.concat(lines, '\n')
end

-- Sorting object keys makes editor exports and fixture comparisons reproducible.
function MAP.CanonicalJSON(value, stringLimit)
    if not MAP.SafeTree(value, stringLimit) then return nil, 'unsafe JSON tree' end
    local function quote(str)
        local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
        return '"' .. str:gsub('[%z\1-\31\\"]', function(c)
            return escapes[c] or string.format('\\u%04x', c:byte())
        end) .. '"'
    end
    local function encode(item)
        if type(item) == 'string' then return quote(item) end
        if type(item) ~= 'table' then return item == nil and 'null' or tostring(item) end
        local keys, pieces = {}, {}
        local array = MAP.IsArray(item) and (#item > 0 or getmetatable(item) == MAP.JSONArrayMeta)
        for key in pairs(item) do keys[#keys + 1] = key end
        table.sort(keys, function(a, b) return array and a < b or (not array and tostring(a) < tostring(b)) end)
        for _, key in ipairs(keys) do pieces[#pieces + 1] = (array and '' or quote(tostring(key)) .. ':') .. encode(item[key]) end
        return (array and '[' or '{') .. table.concat(pieces, ',') .. (array and ']' or '}')
    end
    return encode(value) .. '\n'
end
