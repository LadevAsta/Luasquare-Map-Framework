local MAP = LUASQUARE_MAP
MAP.RegisterPackage('instruments', {})
include('luasquare_module/seg7display.lua')
include('luasquare_module/gaugedisplay.lua')
local classes = {}
for _, pack in pairs(REFERENCE.packs) do
    for _, node in ipairs(pack.components) do
        if node.type == 'instrument.seg7' then for _, name in ipairs(node.config.digits) do classes[name] = 'prop_dynamic' end
        elseif node.type == 'instrument.gauge' then classes[node.config.entity] = 'func_movelinear'
        elseif node.type == 'source.binding' then
            local class = ({relay = 'logic_relay', sound = 'ambient_generic', shake = 'env_shake', mover = 'func_movelinear', sprite = 'env_sprite'})[node.config.profile]
            for _, name in ipairs(node.config.targets) do classes[name] = class end
        elseif node.type == 'rbmk.core' then
            for _, cell in ipairs(node.config.cells) do
                if cell.indicator then classes[cell.indicator] = 'env_sprite' end
                if cell.visual then classes[cell.visual] = 'func_movelinear' end
            end
            for index = 0, (node.config.blowoutValveCount or 0) - 1 do classes[node.config.blowoutValvePrefix .. '_' .. index] = 'func_movelinear' end
        end
    end
end
local entityCache = {}
IsValid = function(value) return type(value) == 'table' and value.testEntity == true end
ents.FindByName = function(name)
    if not classes[name] then return {} end
    if not entityCache[name] then
        entityCache[name] = {testEntity = true, GetClass = function() return classes[name] end,
            GetName = function() return name end, Fire = function() end, SetSkin = function() end, GetInternalVariable = function() return 0 end}
    end
    return {entityCache[name]}
end
local compiled, diagnostics = MAP.Compile(REFERENCE.manifest, REFERENCE.packs)
assert(compiled, MAP.DiagnosticsText(diagnostics))
compiled.sources = {} -- Existing source compilers are checked separately below.
local instance, err = MAP.Create(compiled)
assert(instance, err)
local CONTROL = LUASQUARE_CONTROL
CONTROL.Schema, CONTROL.MaxControls, CONTROL.MaxSourceBytes = 'luasquare.control/v1', 1024, 512 * 1024
CONTROL.Predicates = CONTROL.Predicates or {}
include('luasquare_module/control/shared.lua')
include('luasquare_module/control/compiler.lua')
SERVER = true
include('luasquare_module/control/runtime.lua')
SERVER = false
local controls, errors = CONTROL.CompileSource(REFERENCE_CONTROLS, 'migrated reference controls', {
    Actions = CONTROL.Actions, Predicates = CONTROL.Predicates, Displays = LUASQUARE_SEG7.Displays})
assert(controls, CONTROL.DiagnosticsText(errors))
local telemetry = instance.telemetry['reference.presentation']()
assert(telemetry.alarms.separatorPresent and telemetry.rpv == nil and telemetry.graphs == nil,
    'alarm integration must not recreate obsolete display presentation placeholders')
local core = instance:Get('reference')
assert(#core.BlowoutValves == 89 and core.BlowoutValves[1].targetName == 'brush_rpv_0'
    and core.BlowoutValves[89].targetName == 'brush_rpv_88' and core.BlowoutValves[1].resolved,
    'RBMK core must directly own and cache its declared blowout mover range')
for _, field in ipairs({'Water', 'MaxWater', 'MaxSteam', 'HardMaxSteam', 'ColumnVolume', 'TotalVolume', 'SteamSpace', 'Width', 'Height'}) do
    assert(math.abs(core[field] - BASELINE.core[field]) < 0.000001, 'core capacity changed: ' .. field .. ' ' .. tostring(core[field]) .. ' ~= ' .. tostring(BASELINE.core[field]))
end
for _, declaration in ipairs(BASELINE.registrations) do
    local kind = declaration.type:match('^plant%.(.+)$')
    if kind then
        local specification = MAP.PlantDefinitions[kind]
        local namespace = _G[specification.namespace]
        local config = MAP.Copy(declaration.config)
        for key, value in pairs(config) do if type(value) == 'table' and (key:match('Pos$') or key:match('Offset$')) then config[key] = Vector(unpack(value)) end end
        namespace[specification.register](declaration.id, config)
        local before, after = namespace[specification.storage][declaration.id], instance:Get('reference.' .. declaration.id:lower())
        for key, value in pairs(before) do
            if type(value) == 'number' then
                local acceptedDrainRemediation = declaration.id == 'hotwell_drain_valve' and key == 'minFlowFraction' and after[key] == 0.2
                assert(acceptedDrainRemediation or type(after[key]) == 'number' and (value == after[key] or math.abs(value - after[key]) < 0.000001), declaration.id .. '.' .. key .. ': numeric state changed: ' .. tostring(value) .. ' -> ' .. tostring(after[key]))
            elseif type(value) == 'boolean' then assert(after[key] == value, declaration.id .. '.' .. key .. ': initial flag changed') end
        end
    end
end
assert(MAP.Destroy(instance))
for _, specification in pairs(MAP.PlantDefinitions) do _G[specification.namespace][specification.storage] = {} end
classes.brush_rpv_88 = nil
local missingMover, moverProblem = MAP.Create(compiled)
assert(not missingMover and moverProblem:find('brush_rpv_88', 1, true), 'missing direct blowout mover rejects activation')
assert(not next(LUASQUARE_RBMK.Instances) and not next(LUASQUARE_ENDPOINT.Ports), 'blowout validation failure rolls back the partial plant')
classes.brush_rpv_88 = 'func_movelinear'
classes.SEG7_fixture_0, classes.SEG7_fixture_1 = 'prop_dynamic', 'prop_dynamic'
ents.GetAll = function()
    local result = {}
    for name in pairs(classes) do local found = ents.FindByName(name); if found[1] then result[#result + 1] = found[1] end end
    return result
end
local segManifest = {schema = MAP.Schema, id = 'seg7_test', packages = {'instruments'}, packs = {'seg7.json'}}
local segPacks = {['seg7.json'] = {schema = MAP.ComponentSchema, id = 'seg7', components = {
    {id = 'seg7.fixture', type = 'instrument.seg7', config = {prefix = 'fixture', interval = 0.1}}
}}}
local segCompiled, segErrors = MAP.Compile(segManifest, segPacks)
assert(segCompiled, MAP.DiagnosticsText(segErrors))
local segInstance, segProblem = MAP.Create(segCompiled); assert(segInstance, segProblem)
assert(LUASQUARE_SEG7.Displays['seg7.fixture'][1] == 'SEG7_fixture_0' and LUASQUARE_SEG7.Displays['seg7.fixture'][2] == 'SEG7_fixture_1')
assert(MAP.Destroy(segInstance))
classes.SEG7_fixture_1, classes.SEG7_fixture_2 = nil, 'prop_dynamic'
local gapInstance, gapProblem = MAP.Create(segCompiled)
assert(not gapInstance and gapProblem:find('gap in SEG7', 1, true), 'SEG7 prefix discovery rejects index gaps')
classes.SEG7_fixture_1, classes.SEG7_fixture_2 = 'func_button', nil
local classInstance, classProblem = MAP.Create(segCompiled)
assert(not classInstance and classProblem:find('must be prop_dynamic', 1, true), 'SEG7 prefix discovery rejects wrong classes')
print('Validated reference core capacities and every numeric/boolean plant constructor default against the captured declarations.')
