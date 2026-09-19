local MAP = LUASQUARE_MAP
local input = {type = 'object', optional = true, fields = {
    component = {type = 'id'}, path = {type = 'string', maxLength = 256, asset = 'telemetry'},
    scale = {type = 'number', min = -1e9, max = 1e9, default = 1},
    offset = {type = 'number', min = -1e12, max = 1e12, default = 0},
    round = {type = 'string', choices = {none = true, floor = true, nearest = true}, default = 'none'},
    unavailable = {type = 'string', choices = {hold = true, zero = true}, default = 'hold'}}}

local function getter(instance, node, apply)
    local binding = node.config.input
    if not binding then return end
    local provider = instance.telemetry and instance.telemetry[binding.component]
    if not provider then error('unknown telemetry provider: ' .. binding.component) end
    return function()
        local ok, snapshot = pcall(provider)
        local value = ok and MAP.ReadPath(snapshot, binding.path)
        if not MAP.Finite(value) then
            if binding.unavailable == 'zero' then value = 0 else return end
        end
        value = value * binding.scale + binding.offset
        if binding.round == 'floor' then value = math.floor(value)
        elseif binding.round == 'nearest' then value = math.floor(value + 0.5) end
        apply(node.id, value)
    end
end
local function validate(node, compiled)
    if node.config.input and not compiled.nodes[node.config.input.component] then return false, 'unknown input component' end
    if node.type == 'instrument.gauge' and node.config.max <= node.config.min then return false, 'gauge maximum must exceed minimum' end
    if node.type == 'instrument.seg7' and (node.config.prefix == nil) == (node.config.digits == nil) then
        return false, 'exactly one of prefix or digits is required'
    end
    return true
end
local function seg7Digits(config)
    if config.digits then return config.digits end
    local found, scanned = {}, 0
    local prefix = 'SEG7_' .. config.prefix .. '_'
    for _, entity in ipairs(ents.GetAll()) do
        scanned = scanned + 1
        if scanned > 16384 then return nil, 'SEG7 entity scan limit exceeded' end
        if IsValid(entity) then
            local name = entity:GetName()
            local suffix = name:sub(1, #prefix) == prefix and name:sub(#prefix + 1)
            if suffix and suffix:match('^%d+$') then
                local index = tonumber(suffix)
                if index >= 32 then return nil, 'SEG7 digit index exceeds 31: ' .. name end
                if entity:GetClass() ~= 'prop_dynamic' then return nil, 'SEG7 digit must be prop_dynamic: ' .. name end
                if found[index] then return nil, 'duplicate SEG7 digit index: ' .. index end
                found[index] = name
            end
        end
    end
    local digits = MAP.Array()
    for index = 0, 31 do
        if found[index] then digits[index + 1] = found[index]
        elseif index == 0 then return nil, 'no SEG7 digits found for prefix: ' .. config.prefix
        else
            for later = index + 1, 31 do if found[later] then return nil, 'gap in SEG7 digit indices at ' .. index end end
            break
        end
    end
    return digits
end
local function start(instance, node)
    local namespace = node.type == 'instrument.seg7' and LUASQUARE_SEG7 or LUASQUARE_GAUGE
    local update = getter(instance, node, node.type == 'instrument.seg7' and namespace.SetDisplay or namespace.SetGauge)
    if not update then return end
    local name = 'LUASQUARE_MAP_Instrument_' .. node.id
    instance:Own(function() timer.Remove(name) end)
    timer.Create(name, node.config.interval, 0, update)
    update()
end
MAP.RegisterType('instrument.seg7', {package = 'instruments', label = 'Seven-segment display',
    fields = {prefix = {type = 'id', maxLength = 96, asset = 'seg7', optional = true},
        digits = {type = 'array', minItems = 1, maxItems = 32, optional = true, items = {type = 'string', maxLength = 128, asset = 'entity'}},
        input = input, interval = {type = 'number', min = 0.02, max = 10, default = 0.1}},
    validateDefinition = validate,
    create = function(instance, node)
        if LUASQUARE_SEG7.Displays[node.id] then return false, 'display ID collision' end
        local digits, err = seg7Digits(node.config)
        if not digits then return false, err end
        LUASQUARE_SEG7.RegisterDisplay(node.id, digits)
        instance:Own(function() LUASQUARE_SEG7.Displays[node.id] = nil; LUASQUARE_SEG7.Bindings[node.id] = nil end)
        return {}
    end,
    validate = function(_, node)
        local digits, err = seg7Digits(node.config)
        if not digits then return false, err end
        for _, target in ipairs(digits) do
            local entities = ents.FindByName(target)
            if #entities ~= 1 or not IsValid(entities[1]) or entities[1]:GetClass() ~= 'prop_dynamic' then return false, 'SEG7 digit must resolve to one prop_dynamic: ' .. target end
        end
        return true
    end, start = start})
MAP.RegisterType('instrument.gauge', {package = 'instruments', label = 'Physical gauge',
    fields = {entity = {type = 'string', maxLength = 128, asset = 'entity'}, min = {type = 'number', default = 0}, max = {type = 'number', default = 100},
        speed = {type = 'number', min = 0, max = 1e6, optional = true}, invert = {type = 'boolean', default = false},
        input = input, interval = {type = 'number', min = 0.02, max = 10, default = 0.2}},
    validateDefinition = validate,
    create = function(instance, node)
        if LUASQUARE_GAUGE.Gauges[node.id] then return false, 'gauge ID collision' end
        LUASQUARE_GAUGE.RegisterGauge(node.id, node.config)
        instance:Own(function() LUASQUARE_GAUGE.Gauges[node.id] = nil; LUASQUARE_GAUGE.Bindings[node.id] = nil end)
        return {}
    end,
    validate = function(_, node)
        local entities = ents.FindByName(node.config.entity)
        if #entities ~= 1 or entities[1]:GetClass() ~= 'func_movelinear' then return false, 'gauge requires one func_movelinear' end
    end, start = start})

MAP.RegisterType('control.target_group', {package = 'instruments', label = 'Shared pump target', fields = {
    pumps = {type = 'array', minItems = 1, maxItems = 64, items = {type = 'id'}},
    sensor = {type = 'object', optional = true, fields = {component = {type = 'id'}, port = {type = 'port'}}}},
    validateDefinition = function(node, compiled)
        for _, id in ipairs(node.config.pumps) do if not compiled.nodes[id] or compiled.nodes[id].type ~= 'plant.pump' then return false, 'unknown pump: ' .. id end end
        if node.config.sensor and not compiled.nodes[node.config.sensor.component] then return false, 'unknown level sensor' end
        return true
    end,
    register = function(instance, node)
        local function setTarget(_, _, _, value)
            if not MAP.Finite(value) or value < 0 or value > 100 then return false, 'invalid target' end
            for _, id in ipairs(node.config.pumps) do if not LUASQUARE_PUMP.GetPump(id) then return false, 'pump unavailable' end end
            for _, id in ipairs(node.config.pumps) do LUASQUARE_PUMP.SetRegulationTarget(id, value) end
            return true
        end
        MAP.RegisterControlAction(instance, node, 'target', {label = node.id .. ' target', parameters = {}, callback = setTarget, initialize = setTarget})
        MAP.RegisterTelemetry(instance, node, function()
            local pump = instance:Get(node.config.pumps[1])
            return {target = pump.regulationTarget or 0, level = node.config.sensor and LUASQUARE_ENDPOINT.Read(node.config.sensor, 'levelPercent', 0) or pump.regulationLevel or 0}
        end)
    end})
