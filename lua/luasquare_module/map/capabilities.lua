local MAP = LUASQUARE_MAP

function MAP.ReadPath(value, path)
    if type(path) ~= 'string' or #path > 256 then return nil end
    local depth = 0
    for part in path:gmatch('[^.]+') do
        depth = depth + 1
        if depth > 8 or type(value) ~= 'table' then return nil end
        local child = value[part]
        if child == nil then child = value[tonumber(part)] end
        value = child
    end
    if type(value) == 'number' and not MAP.Finite(value) then return nil end
    return value
end

function MAP.RegisterTelemetry(instance, node, getter, fields)
    local read = getter
    getter = function()
        local object = instance.objects[node.id]
        if instance.destroyed or (object and object.Destroyed) then return {available = false} end
        return read()
    end
    instance.telemetry = instance.telemetry or {}
    assert(not instance.telemetry[node.id], 'duplicate telemetry provider')
    instance.telemetry[node.id] = getter
    if LUASQUARE_CONTROL and LUASQUARE_CONTROL.RegisterPredicate then
        for suffix, kind in pairs({boolean = 'boolean', at_least = 'number', at_most = 'number'}) do
            local id = node.id .. '.' .. suffix
            assert(MAP.IsId(id), 'predicate ID exceeds limit: ' .. id)
            assert(not LUASQUARE_CONTROL.Predicates[id], 'duplicate predicate ' .. id)
            local registered = LUASQUARE_CONTROL.RegisterPredicate(id, {label = node.id .. ' ' .. suffix,
                parameters = {path = {type = 'string'}, value = {type = kind}}, callback = function(_, params)
                    local ok, snapshot = pcall(getter)
                    local value = ok and MAP.ReadPath(snapshot, params.path)
                    if type(value) ~= kind then return false, 'telemetry field unavailable: ' .. params.path end
                    if suffix == 'boolean' then return value == params.value end
                    if not MAP.Finite(value) then return false, 'telemetry is not finite' end
                    if suffix == 'at_least' then return value >= params.value end
                    return value <= params.value
                end})
            assert(registered ~= false, 'predicate registration failed: ' .. id)
            instance:Own(function() LUASQUARE_CONTROL.Predicates[id] = nil end)
        end
    end
    for _, namespace in pairs({display = LUASQUARE_3D2D, annunciator = LUASQUARE_ANNUNCIATOR}) do
        if namespace and namespace.RegisterDataProvider then
            namespace.RegisterDataProvider(node.id, getter, {label = node.id, fields = fields, interval = 0.2})
            instance:Own(function()
                if namespace.UnregisterDataProvider then namespace.UnregisterDataProvider(node.id)
                elseif namespace.DataProviders then namespace.DataProviders[node.id] = nil end
            end)
        end
    end
end

function MAP.PrimitiveSnapshot(object)
    local snapshot = {}
    for key, value in pairs(object or {}) do
        if type(key) == 'string' and (type(value) == 'boolean' or (type(value) == 'string' and #value <= 256) or MAP.Finite(value)) then snapshot[key] = value end
    end
    return snapshot
end

function MAP.RegisterControlAction(instance, node, suffix, definition)
    if not LUASQUARE_CONTROL then return end
    local id = node.id .. '.' .. suffix
    assert(MAP.IsId(id), 'action ID exceeds limit: ' .. id)
    assert(not LUASQUARE_CONTROL.Actions[id], 'duplicate action ' .. id)
    local callback = definition.callback
    definition.callback = function(...)
        local object = instance.objects[node.id]
        if instance.destroyed or not object or object.Destroyed then return false, 'component unavailable: ' .. node.id end
        return callback(...)
    end
    assert(LUASQUARE_CONTROL.RegisterAction(id, definition) ~= false, 'action registration failed: ' .. id)
    instance:Own(function() LUASQUARE_CONTROL.Actions[id] = nil end)
end

function MAP.DescribeTelemetry(instance, id)
    local fields, getter = {}, (instance.telemetry or {})[id]
    if not getter then return fields end
    local ok, snapshot = pcall(getter)
    if not ok then return fields end
    local function visit(value, path, depth)
        if #fields >= 512 or depth > 5 then return end
        if type(value) == 'table' then
            local keys = {}; for key in pairs(value) do keys[#keys + 1] = key end
            table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
            for _, key in ipairs(keys) do visit(value[key], path == '' and tostring(key) or path .. '.' .. tostring(key), depth + 1) end
        elseif type(value) == 'string' or type(value) == 'boolean' or MAP.Finite(value) then
            local descriptor = (MAP.Types[instance.nodes[id].type].fields or {})[path]
            fields[#fields + 1] = {path = path, type = type(value), unit = descriptor and descriptor.unit,
                notes = descriptor and descriptor.unit and 'Unit: ' .. descriptor.unit or nil}
        end
    end
    visit(snapshot, '', 0)
    return fields
end

function MAP.DescribeInstance(instance)
    local nodes = {}
    for id, node in pairs(instance.nodes) do
        nodes[id] = {type = node.type, source = node.source, telemetry = MAP.DescribeTelemetry(instance, id)}
    end
    return nodes
end

function MAP.BindPlantActions(instance, node, object, namespace, definitions)
    for suffix, specification in pairs(definitions) do
        local method, parameter, field = specification[1], specification[2], specification[3]
        local parameters = parameter and {value = MAP.Copy(parameter)} or {}
        if parameter then parameters.value.optional = true end
        MAP.RegisterControlAction(instance, node, suffix, {
            label = node.id .. ' ' .. suffix,
            severity = specification.critical and 'critical' or nil,
            parameters = parameters,
            getValue = field and function() return object[field] end or nil,
            callback = function(_, params, _, value)
                local argument = params.value
                if argument == nil then argument = value end
                if parameter then
                    local validated, err = MAP.ValidateValue(parameter, argument, 'value')
                    if err then return false, err end
                    argument = validated
                end
                return namespace[method](node.id, argument)
            end
        })
    end
end
