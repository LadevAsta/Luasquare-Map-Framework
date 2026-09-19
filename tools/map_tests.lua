LUASQUARE_MAP = {Schema = 'luasquare.map/v1', ComponentSchema = 'luasquare.components/v1', Types = {}, Packages = {}, Instances = {},
    Limits = {nodes = 64, packs = 16, links = 128, depth = 24, values = 4096, string = 4096}}
dofile('lua/luasquare_module/map/shared.lua')
dofile('lua/luasquare_module/map/json.lua')
dofile('lua/luasquare_module/map/compiler.lua')
dofile('lua/luasquare_module/map/runtime.lua')
local MAP = LUASQUARE_MAP
local trace = {}
MAP.RegisterPackage('test', {})
MAP.RegisterType('test.tank', {package = 'test', fields = {
    amount = {type = 'number', min = 0, max = 100, default = 10},
    settings = {type = 'object', default = {}, fields = {
        enabled = {type = 'boolean', default = true}, count = {type = 'integer', default = 2}}},
    numbers = {type = 'array', items = {type = 'number'}, default = {1, 2}}},
    ports = {inlet = {direction = 'in', kind = 'fluid', fluid = 'water', unit = 'L', maxLinks = 1},
        outlet = {direction = 'out', kind = 'fluid', fluid = 'water', unit = 'L'}},
    create = function(instance, node)
        trace[#trace + 1] = 'create:' .. node.id
        instance:Own(function() trace[#trace + 1] = 'release:' .. node.id end)
        return {amount = node.config.amount}
    end,
    link = function(instance, node) assert(instance:Get('a') and instance:Get('b')); trace[#trace + 1] = 'link:' .. node.id end,
    start = function(_, node) trace[#trace + 1] = 'start:' .. node.id end,
    stop = function(_, node) trace[#trace + 1] = 'stop:' .. node.id end,
    destroy = function(_, node) trace[#trace + 1] = 'destroy:' .. node.id end})
local manifest = {schema = MAP.Schema, id = 'test', packages = {'test'}, packs = {'test/main.json'},
    overrides = {a = {settings = {count = 4}, numbers = {9}}}}
local packs = {['test/main.json'] = {schema = MAP.ComponentSchema, id = 'main',
    presets = {tank = {type = 'test.tank', config = {amount = 20, settings = {enabled = false}}}},
    components = {{id = 'a', preset = 'tank', config = {amount = 30}}, {id = 'b', type = 'test.tank', dependsOn = {'a'}}},
    links = {{from = {component = 'a', port = 'outlet'}, to = {component = 'b', port = 'inlet'}},
        {from = {component = 'b', port = 'outlet'}, to = {component = 'a', port = 'inlet'}}}}}
local compiled, diagnostics = MAP.Compile(manifest, packs)
assert(compiled, MAP.DiagnosticsText(diagnostics))
MAP.StartupNamespaces = {'LUASQUARE_TEST_RUNTIME'}
local namespaceManifest = MAP.Copy(manifest)
namespaceManifest.startup = {intervals = {LUASQUARE_TEST_RUNTIME = 0.25}}
assert(MAP.Compile(namespaceManifest, packs), 'client-catalogued startup namespace must compile')
MAP.StartupNamespaces = nil
assert(compiled.nodes.a.config.amount == 30)
assert(compiled.nodes.a.config.settings.enabled == false and compiled.nodes.a.config.settings.count == 4)
assert(#compiled.nodes.a.config.numbers == 1 and compiled.nodes.a.config.numbers[1] == 9)
assert(#trace == 0, 'compiler must not construct or activate')
local instance = assert(MAP.Create(compiled))
assert(instance.running and instance:Get('b').amount == 10)
assert(not MAP.Create(compiled), 'double activation rejected')
assert(table.concat(trace, ',') == 'create:a,create:b,link:a,link:b,start:a,start:b')
assert(MAP.Destroy(instance))
assert(table.concat(trace, ','):match('stop:b,stop:a,release:b,release:a,destroy:b,destroy:a$'))
assert(MAP.Destroy(instance), 'destroy is idempotent')

local function reject(edit, expected)
    local m, p = MAP.Copy(manifest), MAP.Copy(packs)
    edit(m, p['test/main.json'])
    local result, errors = MAP.Compile(m, p)
    assert(not result and MAP.DiagnosticsText(errors):find(expected, 1, true), MAP.DiagnosticsText(errors))
end
reject(function(_, p) p.components[2].id = 'a' end, 'duplicate component ID')
reject(function(m) m.packs[2] = m.packs[1] end, 'duplicate source')
reject(function(_, p) p.components[1].dependsOn = {'b'} end, 'construction cycle')
reject(function(_, p) p.components[1].dependsOn = {'missing'} end, 'missing component')
reject(function(_, p) p.components[1].config.amount = -1 end, 'invalid number')
reject(function(_, p) p.components[1].config.amount = math.huge end, 'source tree')
reject(function(_, p) p.components[1].config.lua = 'print(1)' end, 'unknown field')
reject(function(_, p) p.components[1].type = 'unknown' end, 'unknown component type')
reject(function(_, p) p.links[1].to.port = 'missing' end, 'unknown endpoint')
reject(function(_, p) p.links[3] = MAP.Copy(p.links[1]) end, 'cardinality exceeded')
reject(function(m) m.sources = {audio = {'../../escape.json'}} end, 'invalid or duplicate')
reject(function(m) m.sources = {audio = {'sounds/a.json', 'sounds/a.json'}} end, 'invalid or duplicate')
reject(function(m) m.packages = {'missing'} end, 'required package unavailable')
reject(function(m) m.editor = {generatedPositions = {ghost = {x = 0, y = 0}}} end, 'unknown generated component')
reject(function(m) m.editor = {referenceBends = {['source>ghost'] = {x = 0, y = 0}}} end, 'unknown reference endpoint')
assert(not MAP.SourcePath('map', '/absolute.json'))
assert(not MAP.SourcePath('map', 'https://example/a.json'))
assert(not MAP.SourcePath('map', 'a\\b.json'))
assert(MAP.CanonicalJSON({b = 2, a = 1}) == '{"a":1,"b":2}\n')
assert(MAP.ValidateJSON(MAP.CanonicalJSON({a = false, nested = {1, 2, 3}, number = -1.5e10})))
for _, invalid in ipairs({'{"a":1,"a":2}', '{"id":1,"\\u0069d":2}', '[1,]', '{"a":1,}', '/* comment */{}', '[01]', '[1.]', '[1e]', '[1e999]', '{} trailing', '{a:1}'}) do
    assert(not MAP.ValidateJSON(invalid), 'accepted invalid JSON: ' .. invalid)
end
local cyclic = {}; cyclic.self = cyclic; assert(not MAP.SafeTree(cyclic))
local strict = assert(MAP.DecodeJSON('{"array":[],"object":{},"nested":{"flag":false},"numericKeys":{"1":"first"}}'))
assert(MAP.IsArray(strict.array) and not MAP.IsArray(strict.object))
assert(MAP.CanonicalJSON(strict) == MAP.CanonicalJSON(assert(MAP.DecodeJSON(MAP.CanonicalJSON(strict)))))
assert(MAP.Merge({nested = {flag = true, count = 3}}, strict).nested.count == 3)
assert(MAP.Merge({array = {1, 2}, object = {keep = true}}, strict).object.keep == true)
assert(#MAP.Merge({array = {1, 2}}, strict).array == 0)
assert(not MAP.DecodeJSON('{"optional":null}'))
assert(not MAP.ValidateJSON('"' .. string.char(192, 128) .. '"'), 'overlong UTF-8 rejected')
assert(not MAP.ValidateJSON('"' .. string.char(237, 160, 128) .. '"'), 'UTF-8 surrogate rejected')

MAP.Types['test.tank'].ports.inlet.unit = 'kg'
reject(function() end, 'incompatible port')
MAP.Types['test.tank'].ports.inlet.unit = 'L'
MAP.Types['test.tank'].start = function(_, node) if node.id == 'b' then error('injected failure') end end
trace = {}
local failed, message = MAP.Create(compiled)
assert(not failed and message:find('injected failure', 1, true))
assert(not MAP.Instances.test)
assert(table.concat(trace, ','):match('stop:b,stop:a,release:b,release:a,destroy:b,destroy:a$'))
MAP.Types['test.tank'].create = function(instance, node)
    instance:Own(function() trace[#trace + 1] = 'partial:' .. node.id end)
    error('partial construction')
end
trace = {}
assert(not MAP.Create(compiled))
assert(table.concat(trace, ','):find('partial:a', 1, true) and not MAP.Instances.test)
print('Validated precedence, cycles, references, limits, source safety and failure rollback.')
