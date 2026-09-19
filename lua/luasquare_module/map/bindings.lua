local MAP = LUASQUARE_MAP

-- Input names belong to trusted adapters, never to a source document.
local profiles = {
    mover = {class = 'func_movelinear', methods = {open = 'Open', close = 'Close', position = 'SetPosition', speed = 'SetSpeed'}},
    rotator = {class = 'func_rotating', methods = {start = 'Start', stop = 'Stop', speed = 'SetSpeed'}},
    door = {class = 'func_door', methods = {open = 'Open', close = 'Close'}},
    rotating_door = {class = 'func_door_rotating', methods = {open = 'Open', close = 'Close'}},
    tracktrain = {class = 'func_tracktrain', methods = {deploy = 'Deploy', retract = 'Retract', stop = 'Stop', speed = 'SetSpeed'}},
    sprite = {class = 'env_sprite', inputs = {show = 'ShowSprite', hide = 'HideSprite'}},
    relay = {class = 'logic_relay', inputs = {trigger = 'Trigger'}},
    sound = {class = 'ambient_generic', inputs = {start = 'PlaySound', stop = 'StopSound'}},
    shake = {class = 'env_shake', inputs = {start = 'StartShake', stop = 'StopShake'}},
    path = {class = 'path_track', inputs = {alternate_on = 'EnableAlternatePath', alternate_off = 'DisableAlternatePath'}}
}
local choices = {}
for key in pairs(profiles) do choices[key] = true end

local function registry(instance)
    if instance.bindings then return instance.bindings end
    local name = 'LUASQUARE_MAP_' .. instance.id
    assert(not LUASQUARE_SOURCEBINDING.Registries[name] and not LUASQUARE_MACHINERY.Registries[name], 'map binding registry collision')
    instance:Own(function()
        if instance.bindings then instance.bindings:ClearCache() end
        LUASQUARE_SOURCEBINDING.Registries[name] = nil
        LUASQUARE_MACHINERY.Registries[name] = nil
    end)
    instance.bindings = LUASQUARE_SOURCEBINDING.CreateRegistry(name)
    instance.machinery = LUASQUARE_MACHINERY.CreateRegistry(name, {source = instance.bindings})
    return instance.bindings
end

MAP.RegisterType('source.binding', {package = 'source', label = 'Source entity binding', fields = {
    profile = {type = 'string', choices = choices},
    targets = {type = 'array', minItems = 1, maxItems = 256, items = {type = 'string', maxLength = 128, asset = 'entity'}},
    required = {type = 'boolean', default = true}, all = {type = 'boolean', default = false},
    notes = {type = 'string', maxLength = 4096, optional = true},
    tags = {type = 'array', maxItems = 32, default = MAP.Array(), items = {type = 'string', maxLength = 128}},
    unit = {type = 'string', maxLength = 64, optional = true}},
    validateDefinition = function(node)
        local seen = {}
        for _, target in ipairs(node.config.targets) do
            if target == '' or target:find('[*?]') or seen[target] then return false, 'targets must be unique exact targetnames' end
            seen[target] = true
        end
        return true
    end,
    create = function(instance, node)
        local bindings = registry(instance)
        bindings:Register(node.id, {targetNames = node.config.targets, class = profiles[node.config.profile].class,
            required = node.config.required, all = node.config.all, notes = node.config.notes, tags = node.config.tags, unit = node.config.unit})
        return bindings:Get(node.id)
    end,
    validate = function(instance, node)
        local entities = instance.bindings:ResolveAll(node.id)
        if node.config.required and #entities == 0 then return false, 'required Source binding has no entities' end
        if not node.config.all and #entities > 1 then return false, 'ambiguous Source binding; use all for an intentional group' end
        for _, entity in ipairs(entities) do
            if not IsValid(entity) or entity:GetClass() ~= profiles[node.config.profile].class then return false, 'wrong entity class for ' .. node.config.profile end
        end
        return true
    end,
    register = function(instance, node)
        for suffix, inputName in pairs(profiles[node.config.profile].inputs or {}) do
            MAP.RegisterControlAction(instance, node, suffix, {label = node.id .. ' ' .. suffix, parameters = {},
                callback = function() return instance.bindings:Fire(node.id, inputName) end})
        end
        MAP.RegisterTelemetry(instance, node, function()
            local entities = instance.bindings:ResolveAll(node.id)
            return {available = #entities > 0, count = #entities}
        end)
    end})

MAP.RegisterType('machinery.machine', {package = 'source', label = 'Source machinery', fields = {
    binding = {type = 'id'}, path = {type = 'id', optional = true},
    initialNode = {type = 'string', optional = true}, deployNode = {type = 'string', optional = true}, retractNode = {type = 'string', optional = true},
    configuredSpeed = {type = 'number', min = 0, max = 1e6, optional = true},
    deploySpeed = {type = 'number', min = 0, max = 1e6, optional = true}, retractSpeed = {type = 'number', min = 0, max = 1e6, optional = true},
    speedInputScale = {type = 'number', min = 0.000001, max = 1e6, default = 1}},
    validateDefinition = function(node, compiled)
        local binding = compiled.nodes[node.config.binding]
        if not binding or binding.type ~= 'source.binding' or not profiles[binding.config.profile].methods then return false, 'machine requires a machinery Source binding' end
        if binding.config.profile == 'tracktrain' then
            local path = compiled.nodes[node.config.path]
            if not path or path.type ~= 'machinery.path' then return false, 'tracktrain requires a path' end
            local names = {}
            for _, id in ipairs(path.config.nodes) do names[id] = true end
            for _, field in ipairs({'initialNode', 'deployNode', 'retractNode'}) do
                if not names[node.config[field]] then return false, field .. ' must address a path node' end
            end
        elseif node.config.path then return false, 'only tracktrains use paths' end
        return true
    end,
    create = function(instance, node)
        registry(instance)
        local binding = instance.compiled.nodes[node.config.binding]
        local config = MAP.Copy(node.config)
        config.type, config.class, config.all = binding.config.profile, profiles[binding.config.profile].class, binding.config.all
        instance.machinery:RegisterMachine(node.id, config)
        return instance.machinery:GetMachine(node.id)
    end,
    register = function(instance, node, object)
        if object.type == 'tracktrain' then
            MAP.RegisterControlAction(instance, node, 'destination', {label = node.id .. ' destination', parameters = {node = {type = 'string'}},
                callback = function(_, params) return instance.machinery:MoveTrackTrainTo(node.id, params.node) end})
        end
        for suffix, method in pairs(profiles[object.type].methods) do
            local parameter = (suffix == 'speed' or suffix == 'position') and {type = 'number', min = 0, max = suffix == 'position' and 1 or 1e6}
            MAP.RegisterControlAction(instance, node, suffix, {label = node.id .. ' ' .. suffix,
                parameters = parameter and {value = MAP.Merge(parameter, {optional = true})} or {},
                callback = function(_, params, _, value)
                    if parameter then
                        local err
                        value, err = MAP.ValidateValue(parameter, params.value == nil and value or params.value, 'value')
                        if err then return false, err end
                    end
                    return instance.machinery[method](instance.machinery, node.id, value)
                end})
        end
        MAP.RegisterTelemetry(instance, node, function() return MAP.PrimitiveSnapshot(object) end)
    end,
    stop = function(instance, node, object)
        if object and object.lastCommand then instance.machinery:Stop(node.id) end
    end})

-- Trusted Hammer bridge, explicitly addressed and restricted to a declared path.
-- Operator motion still goes through Control requests; this only reports arrival.
function MAP.ReportPathTrack(instanceId, machineId, caller)
    local instance = MAP.Instances[instanceId]
    if not instance or not instance.running or not instance.machinery or not IsValid(caller) or caller:GetClass() ~= 'path_track' then return false end
    local machine = instance.machinery:GetMachine(machineId)
    local path = machine and instance.machinery.Paths[machine.path]
    if not path then return false end
    for _, name in ipairs(path.nodes) do
        if name == caller:GetName() then instance.machinery:OnPathTrackPassed(name, machineId); return true end
    end
    return false
end

MAP.RegisterType('machinery.path', {package = 'source', label = 'Tracktrain path', fields = {
    nodes = {type = 'array', minItems = 2, maxItems = 256, items = {type = 'string', maxLength = 128}},
    edges = {type = 'array', default = MAP.Array(), maxItems = 1024, items = {type = 'object', fields = {
        from = {type = 'string'}, to = {type = 'string'}, direction = {type = 'string', choices = {forward = true, backward = true}, default = 'forward'}}}},
    switches = {type = 'array', default = MAP.Array(), maxItems = 256, items = {type = 'object', fields = {
        node = {type = 'string'}, to = {type = 'string'}, binding = {type = 'id'}}}}},
    validateDefinition = function(node, compiled)
        local names = {}
        for _, name in ipairs(node.config.nodes) do
            if name == '' or name:find('[*?]') or names[name] then return false, 'path nodes must be unique exact targetnames' end
            names[name] = true
        end
        for _, edge in ipairs(node.config.edges) do if not names[edge.from] or not names[edge.to] then return false, 'edge references an unknown path node' end end
        for _, switch in ipairs(node.config.switches) do
            local binding = compiled.nodes[switch.binding]
            if not names[switch.node] or not names[switch.to] or not binding or binding.type ~= 'source.binding' or binding.config.profile ~= 'path' then return false, 'invalid path switch' end
        end
        return true
    end,
    create = function(instance, node)
        registry(instance)
        instance.machinery:RegisterPath(node.id, node.config)
        return instance.machinery.Paths[node.id]
    end,
    validate = function(_, node)
        for _, name in ipairs(node.config.nodes) do
            local entities = ents.FindByName(name)
            if #entities ~= 1 or entities[1]:GetClass() ~= 'path_track' then return false, 'path requires one path_track: ' .. name end
        end
        return true
    end})
