dofile('lua/luasquare_module/map/document.lua')
local MAP = LUASQUARE_MAP
MAP.RegisterType('source.test', {package = 'source', fields = {
    targetname = {type = 'string'}, alias = {type = 'id', asset = 'name', optional = true}, peer = {type = 'id', optional = true},
    reference = {type = 'object', optional = true, fields = {component = {type = 'id'}, port = {type = 'id'}}}},
    ports = {inlet = {kind = 'test', direction = 'in', unit = 'L', maxLinks = 1}, outlet = {kind = 'test', direction = 'out', unit = 'L'}}})
local manifest = {schema = MAP.Schema, id = 'editor', packages = {'source'}, packs = {'a.json', 'b.json'}, overrides = {a = {targetname = 'a'}}}
local packs = {
    ['a.json'] = {schema = MAP.ComponentSchema, id = 'a', components = {
        {id = 'a', type = 'source.test', config = {targetname = 'brush', alias = 'b', peer = 'b'}},
        {id = 'outside', type = 'source.test', config = {targetname = 'a'}}}},
    ['b.json'] = {schema = MAP.ComponentSchema, id = 'b', components = {
        {id = 'b', type = 'source.test', config = {targetname = 'b', peer = 'outside', reference = {component = 'a', port = 'outlet'}}, dependsOn = {'a'}}},
        links = {{from = {component = 'a', port = 'outlet'}, to = {component = 'b', port = 'inlet'}}}}
}
local document = MAP.NewDocument(manifest, packs)
assert(document:Compile())
assert(document:Duplicate({a = true, b = true}, 'a.json'))
local a, b = document:Find('a_copy'), document:Find('b_copy')
assert(a.config.targetname == 'a', 'physical targetnames must never be remapped')
assert(a.config.alias == 'b', 'local aliases must not be remapped as component references')
assert(a.config.peer == 'b_copy' and b.config.peer == 'outside')
assert(b.config.reference.component == 'a_copy' and b.dependsOn[1] == 'a_copy')
assert(document:Compile())
assert(#document.packs['a.json'].links == 1, 'cross-pack internal link duplicated once')
assert(document:History(false) and not document:Find('a_copy'))
assert(document:History(true) and document:Find('a_copy'))
local revision = document.revision
assert(not document:Connect({component = 'a', port = 'outlet'}, {component = 'a_copy', port = 'outlet'}, 'a.json'))
assert(document.revision == revision and document:Compile(), 'failed edit restores entire document')
assert(document:MakePreset('a', 'test.preset', 'a.json'))
assert(document:Find('a').preset == 'test.preset' and not document.manifest.overrides.a)
assert(document:SetOverride('a', 'targetname', 'override'))
local compiled = assert(document:Compile()); assert(compiled.nodes.a.config.targetname == 'override')
assert(document:Group({a = true, b = true}, 'first unit'))
assert(document:Find('a').editor.group == 'first unit')
assert(document:Remove({a = true}))
assert(not document:Compile(), 'surviving references produce diagnostics after deletion')
assert(document:History(false) and document:Compile())
print('Validated editor undo/redo, transactional edits, cross-pack duplication, reference remapping and preset overrides.')
