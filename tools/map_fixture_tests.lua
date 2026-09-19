local MAP = LUASQUARE_MAP
MAP.Limits.values, MAP.Limits.nodes = 131072, 2048
unpack = table.unpack
function include(path) return dofile('lua/' .. path) end
IsValid = function() return false end
math.Round = function(number) return math.floor(number + 0.5) end
Color = function(r, g, b, a) return {r = r, g = g, b = b, a = a or 255} end
hook = {Add = function() end, Remove = function() end, Run = function() end}
include('luasquare_powerplant/init.lua')
include('luasquare_powerplant/catalog.lua')
include('luasquare_powerplant/components.lua')
include('luasquare_rbmk/components.lua')
include('luasquare_rbmk/presentation.lua')
include('luasquare_module/map/instruments.lua')
include('luasquare_module/map/sources.lua')
MAP.ActivateSources = nil -- Component tests do not mock successful source activation.
MAP.RegisterPackage('powerplant', {})
MAP.RegisterPackage('rbmk', {})
MAP.RegisterPackage('presentation', {})
for name, fixture in pairs(FIXTURES) do
    local compiled, diagnostics = MAP.Compile(fixture.manifest, fixture.packs)
    assert(compiled, MAP.DiagnosticsText(diagnostics))
    -- Source-engine integration has separate tests; this harness exercises the
    -- actual component constructors, registration, timer setup and destruction.
    compiled.sources = {}
    local instance, err = MAP.Create(compiled)
    assert(instance, err)
    if name == 'two_core' then
        local a, b = instance:Get('fixture.alpha'), instance:Get('fixture.beta')
        local water = b.Water
        assert(a ~= b and a.Matrix ~= b.Matrix)
        assert(LUASQUARE_CONTROL.Actions['fixture.alpha.rod_toggle'].callback(nil, {name = 'R1'}))
        assert(LUASQUARE_CONTROL.Actions['fixture.alpha.rod_target'].callback(nil, {}, nil, 50))
        assert(b.Selector.GetSelectionCount() == 0 and b.Rods.R1.targetInsertion == 1)
        assert(LUASQUARE_CONTROL.Actions['fixture.alpha.feed.enabled'].callback(nil, {value = true}))
        LUASQUARE_PUMP.UpdatePump('fixture.alpha.feed', 0.1)
        assert(b.Water == water)
        assert(instance.telemetry['fixture.alpha']().cells == nil)
        a.Destroy()
        assert(not b.Destroyed and LUASQUARE_RBMK.Get('fixture.beta') == b)
    else
        LUASQUARE_PUMP.UpdatePump('hx.hot_pump', 0.1)
        LUASQUARE_PUMP.UpdatePump('hx.cold_pump', 0.1)
        local hot, cold = instance:Get('hx.hot'), instance:Get('hx.cold')
        local before = hot.temperature + cold.temperature
        LUASQUARE_HEATEXCHANGER.UpdateAll()
        assert(hot.temperature < 90 and cold.temperature > 20)
        assert(math.abs(hot.temperature + cold.temperature - before) < 0.0001, 'heat exchanger energy balance')
    end
    assert(MAP.Destroy(instance))
    assert(not next(LUASQUARE_ENDPOINT.Ports) and not next(LUASQUARE_RBMK.Instances))
    assert(not next(LUASQUARE_CONTROL.Actions))
end
print('Validated packed two-core and heat-exchanger construction, actions, isolation, energy balance and cleanup.')

local generatedManifest = {schema = MAP.Schema, id = 'generated', packages = {'powerplant'}, packs = {'generated.json'}}
local generatedPacks = {['generated.json'] = {schema = MAP.ComponentSchema, id = 'generated', components = {
    {id = 'grid', type = 'plant.grid', config = {type = 'offsite'}},
    {id = 'pump', type = 'plant.pump', config = {grid = 'grid', peakMW = 2}},
    {id = 'diesel', type = 'plant.diesel', config = {grid = 'grid', ratedMW = 3}}
}}}
local generated, errors = MAP.Compile(generatedManifest, generatedPacks)
assert(generated, MAP.DiagnosticsText(errors))
assert(generated.nodes['pump.breaker'].generatedBy == 'pump')
assert(generated.nodes['diesel.generator.breaker'].config.maxMW == 3)
local generatedInstance, problem = MAP.Create(generated)
assert(generatedInstance, problem)
assert(generatedInstance:Get('pump').breaker == 'pump.breaker')
assert(generatedInstance:Get('diesel').generator == 'diesel.generator')
assert(MAP.Destroy(generatedInstance))
local generatedDocument = MAP.NewDocument(generatedManifest, generatedPacks)
assert(generatedDocument:SetOverride('diesel.generator.breaker', 'maxMW', 4))
assert(generatedDocument:Duplicate({diesel = true}, 'generated.json'))
local duplicated, duplicateErrors = generatedDocument:Compile()
assert(duplicated, MAP.DiagnosticsText(duplicateErrors))
assert(duplicated.nodes['diesel_copy.generator.breaker'].config.maxMW == 4)
assert(duplicated.nodes.diesel_copy.config.generator == 'diesel_copy.generator')
assert(not generatedDocument:Remove({['diesel.generator'] = true}))
assert(generatedDocument:MakePreset('pump', 'pump.preset', 'generated.json'))
assert(generatedDocument.packs['generated.json'].presets['pump.preset'].config.breaker == nil)
assert(generatedDocument:Compile(), 'presets regenerate independent owned children')
generatedPacks['generated.json'].components[4] = {id = 'pump.breaker', type = 'plant.breaker', config = {}}
assert(not MAP.Compile(generatedManifest, generatedPacks), 'generated IDs cannot shadow explicit declarations')
print('Validated nested generated generators/breakers, deterministic IDs, ownership and collisions.')
