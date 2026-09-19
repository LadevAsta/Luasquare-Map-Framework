LUASQUARE_MAP = {Schema = 'luasquare.map/v1', ComponentSchema = 'luasquare.components/v1', Types = {}, Packages = {}, Instances = {},
    Limits = {nodes = 64, packs = 16, links = 128, depth = 24, values = 4096, string = 4096}}
dofile('lua/luasquare_module/map/shared.lua')
dofile('lua/luasquare_module/map/compiler.lua')
dofile('lua/luasquare_module/map/runtime.lua')
dofile('lua/luasquare_module/map/capabilities.lua')
LUASQUARE_SOURCEBINDING_LOADED, LUASQUARE_MACHINERY_LOADED = nil, nil
LUASQUARE_SOURCEBINDING, LUASQUARE_MACHINERY = nil, nil
dofile('lua/luasquare_module/sourcebinding.lua')
dofile('lua/luasquare_module/machinery.lua')
dofile('lua/luasquare_module/map/bindings.lua')
local MAP = LUASQUARE_MAP
MAP.RegisterPackage('source', {})
local fired, entities = {}, {}
IsValid = function(entity) return type(entity) == 'table' and entity.valid end
ents = {FindByName = function(name) return entities[name] or {} end}
CurTime = function() return 0 end
local function entity(class)
    return {valid = true, GetClass = function() return class end,
        Fire = function(_, name, value) fired[#fired + 1] = {name, value} end}
end
LUASQUARE_CONTROL = {Actions = {}, RegisterAction = function(id, definition) LUASQUARE_CONTROL.Actions[id] = definition end}
LUASQUARE_3D2D, LUASQUARE_ANNUNCIATOR = nil, nil
local manifest = {schema = MAP.Schema, id = 'bindings', packages = {'source'}, packs = {'bindings.json'}}
local pack = {schema = MAP.ComponentSchema, id = 'bindings', components = {
    {id = 'motor.entity', type = 'source.binding', config = {profile = 'rotator', targets = {'motor'}}},
    {id = 'motor', type = 'machinery.machine', config = {binding = 'motor.entity', configuredSpeed = 50}}
}}
local function compile(source)
    local compiled, diagnostics = MAP.Compile(manifest, {['bindings.json'] = source or pack})
    assert(compiled, MAP.DiagnosticsText(diagnostics))
    return compiled
end
entities.motor = {entity('func_rotating')}
local instance = assert(MAP.Create(compile()))
assert(#fired == 0, 'construction must not start machinery')
assert(LUASQUARE_CONTROL.Actions['motor.start'].callback(nil, {}))
assert(fired[#fired][1] == 'Start')
assert(not LUASQUARE_CONTROL.Actions['motor.speed'].callback(nil, {value = -1}))
assert(not LUASQUARE_CONTROL.Actions['motor.speed'].callback(nil, {value = math.huge}))
assert(LUASQUARE_CONTROL.Actions['motor.speed'].callback(nil, {value = 25}))
assert(instance.telemetry.motor().currentSpeed == 25)
assert(MAP.Destroy(instance))
assert(fired[#fired][1] == 'Stop', 'machine must stop before binding registry is released')
assert(not next(LUASQUARE_CONTROL.Actions))
assert(not next(LUASQUARE_SOURCEBINDING.Registries) and not next(LUASQUARE_MACHINERY.Registries))
entities.motor = {entity('logic_relay')}
local failed, err = MAP.Create(compile())
assert(not failed and err:find('wrong entity class', 1, true))
assert(not next(LUASQUARE_CONTROL.Actions) and not next(MAP.Instances))
entities.motor = {entity('func_rotating'), entity('func_rotating')}
failed, err = MAP.Create(compile())
assert(not failed and err:find('ambiguous', 1, true))
local bad = MAP.Copy(pack)
bad.components[1].config.targets = {'motor*'}
assert(not MAP.Compile(manifest, {['bindings.json'] = bad}))
bad = MAP.Copy(pack)
bad.components[2].config.startInput = 'RunScriptCode'
assert(not MAP.Compile(manifest, {['bindings.json'] = bad}))
assert(MAP.ReadPath({state = false}, 'state') == false)
print('Validated exact Source bindings, class checks, trusted machinery actions, bounds and cleanup ordering.')
