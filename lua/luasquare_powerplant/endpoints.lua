if LUASQUARE_ENDPOINT_CORE_LOADED then return end
LUASQUARE_ENDPOINT_CORE_LOADED = true
LUASQUARE_ENDPOINT = {Ports = {}}
local ENDPOINT = LUASQUARE_ENDPOINT

function ENDPOINT.Register(component, port, definition)
    assert(type(component) == 'string' and type(port) == 'string' and type(definition) == 'table', 'invalid endpoint')
    local key = component .. '/' .. port
    assert(not ENDPOINT.Ports[key], 'duplicate endpoint: ' .. key)
    ENDPOINT.Ports[key] = definition
    return function() if ENDPOINT.Ports[key] == definition then ENDPOINT.Ports[key] = nil end end
end

function ENDPOINT.Get(ref)
    if type(ref) ~= 'table' or type(ref.component) ~= 'string' or type(ref.port) ~= 'string' then return nil end
    return ENDPOINT.Ports[ref.component .. '/' .. ref.port]
end

function ENDPOINT.Read(ref, property, fallback)
    local endpoint = ENDPOINT.Get(ref)
    if not endpoint or not endpoint.snapshot then return fallback end
    local value = endpoint.snapshot()[property]
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return fallback end
    return value
end
