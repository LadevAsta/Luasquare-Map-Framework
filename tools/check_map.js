// Development-only Lua interpreter; no addon runtime dependency.
const fs = require('fs');
const path = require('path');
const luaparse = require('../.control-build/testdeps/node_modules/luaparse');
const {lua, lauxlib, lualib, to_luastring} = require('../.control-build/testdeps/node_modules/fengari');
process.chdir(path.resolve(__dirname, '..'));
for (const directory of ['lua/luasquare_module/map', 'lua/luasquare_rbmk', 'lua/luasquare_powerplant']) {
    for (const name of fs.readdirSync(directory)) {
        if (name.endsWith('.lua')) luaparse.parse(fs.readFileSync(directory + '/' + name, 'utf8'), {luaVersion: '5.1'});
    }
}
for (const name of ['lua/autorun/luasquare_map.lua', 'lua/autorun/luasquare_rbmk_schema.lua']) {
    luaparse.parse(fs.readFileSync(name, 'utf8'), {luaVersion: '5.1'});
}
const state = lauxlib.luaL_newstate();
lualib.luaL_openlibs(state);
const result = lauxlib.luaL_dofile(state, to_luastring('tools/map_tests.lua'));
if (result !== lua.LUA_OK) throw Error(lua.lua_tojsstring(state, -1));
console.log('Map compiler and lifecycle checks passed.');
const coreResult = lauxlib.luaL_dofile(state, to_luastring('tools/rbmk_instance_tests.lua'));
if (coreResult !== lua.LUA_OK) throw Error(lua.lua_tojsstring(state, -1));
const bindingsResult = lauxlib.luaL_dofile(state, to_luastring('tools/map_binding_tests.lua'));
if (bindingsResult !== lua.LUA_OK) throw Error(lua.lua_tojsstring(state, -1));
const documentResult = lauxlib.luaL_dofile(state, to_luastring('tools/map_document_tests.lua'));
if (documentResult !== lua.LUA_OK) throw Error(lua.lua_tojsstring(state, -1));
function transferRealm(script, inputName, inputValue, outputName) {
    const realm = lauxlib.luaL_newstate();
    lualib.luaL_openlibs(realm);
    lua.lua_pushstring(realm, to_luastring(inputValue));
    lua.lua_setglobal(realm, to_luastring(inputName));
    const status = lauxlib.luaL_dofile(realm, to_luastring(script));
    if (status !== lua.LUA_OK) throw Error(lua.lua_tojsstring(realm, -1));
    lua.lua_getglobal(realm, to_luastring(outputName));
    const output = lua.lua_tojsstring(realm, -1);
    lua.lua_close(realm);
    return output;
}
const transferSource = JSON.stringify({fuelPresets: [], tags: [], links: [], defaults: {}, overrides: {},
    bulk: Array.from({length: 4096}, (_, index) => `entry_${index}`)});
const transferEnvelope = transferRealm('tools/map_transfer_server.lua', 'TRANSFER_SOURCE', transferSource, 'TRANSFER_ENVELOPE');
const transferResult = transferRealm('tools/map_transfer_client.lua', 'TRANSFER_ENVELOPE', transferEnvelope, 'TRANSFER_RESULT');
const transferred = JSON.parse(transferResult);
if (transferred.bulk.length !== 4096) throw Error('large separated-realm source transfer was truncated');
for (const key of ['fuelPresets', 'links', 'tags']) {
    if (!Array.isArray(transferred[key]) || transferred[key].length) throw Error(`separated-realm transfer changed ${key}`);
}
for (const key of ['defaults', 'overrides']) {
    if (!transferred[key] || Array.isArray(transferred[key]) || Object.keys(transferred[key]).length) {
        throw Error(`separated-realm transfer changed ${key}`);
    }
}
console.log('Separated server/client packed-source transfer checks passed.');
function push(value) {
    lua.lua_checkstack(state, 8);
    if (value === null || value === undefined) lua.lua_pushnil(state);
    else if (typeof value === 'string') lua.lua_pushstring(state, to_luastring(value));
    else if (typeof value === 'boolean') lua.lua_pushboolean(state, value);
    else if (typeof value === 'number') lua.lua_pushnumber(state, value);
    else {
        lua.lua_newtable(state);
        for (const [key, child] of Object.entries(value)) {
            if (Array.isArray(value)) lua.lua_pushinteger(state, Number(key) + 1); else lua.lua_pushstring(state, to_luastring(key));
            push(child); lua.lua_settable(state, -3);
        }
    }
}
const fixtures = {};
for (const name of ['two_core', 'heat_exchanger']) {
    fixtures[name] = {
        manifest: JSON.parse(fs.readFileSync(`data_static/luasquare/map/_fixtures/${name}.json`, 'utf8')),
        packs: {[`_fixtures/${name}.json`]: JSON.parse(fs.readFileSync(`data_static/luasquare/components/_fixtures/${name}.json`, 'utf8'))}
    };
}
push(fixtures); lua.lua_setglobal(state, to_luastring('FIXTURES'));
const fixtureResult = lauxlib.luaL_dofile(state, to_luastring('tools/map_fixture_tests.lua'));
if (fixtureResult !== lua.LUA_OK) throw Error(lua.lua_tojsstring(state, -1));
if (process.argv.includes('--catalog')) {
    function read(index) {
        lua.lua_checkstack(state, 8);
        index = lua.lua_absindex(state, index);
        const type = lua.lua_type(state, index);
        if (type === lua.LUA_TSTRING) return lua.lua_tojsstring(state, index);
        if (type === lua.LUA_TNUMBER) return lua.lua_tonumber(state, index);
        if (type === lua.LUA_TBOOLEAN) return lua.lua_toboolean(state, index);
        if (type !== lua.LUA_TTABLE) return null;
        const entries = [];
        lua.lua_pushnil(state);
        while (lua.lua_next(state, index)) { entries.push([read(-2), read(-1)]); lua.lua_pop(state, 1); }
        const array = entries.length && entries.every(([key]) => Number.isInteger(key) && key > 0 && key <= entries.length);
        return array ? entries.sort((a, b) => a[0] - b[0]).map(entry => entry[1]) : Object.fromEntries(entries);
    }
    lua.lua_getglobal(state, to_luastring('LUASQUARE_MAP'));
    lua.lua_getfield(state, -1, to_luastring('Types')); const types = read(-1); lua.lua_pop(state, 1);
    lua.lua_getfield(state, -1, to_luastring('PlantDefinitions')); const plant = read(-1); lua.lua_pop(state, 1);
    fs.mkdirSync('.control-build/migration', {recursive: true});
    fs.writeFileSync('.control-build/migration/catalog.json', JSON.stringify({types, plant}, null, 2));
}
if (fs.existsSync('data_static/luasquare/map/experiment_rbmk/main.json')) {
    const manifest = JSON.parse(fs.readFileSync('data_static/luasquare/map/experiment_rbmk/main.json', 'utf8'));
    const packs = Object.fromEntries(manifest.packs.map(name => [name, JSON.parse(fs.readFileSync('data_static/luasquare/components/' + name, 'utf8'))]));
    push({manifest, packs}); lua.lua_setglobal(state, to_luastring('REFERENCE'));
    push(JSON.parse(fs.readFileSync('data_static/luasquare/control/experiment_rbmk/operator_controls.json', 'utf8'))); lua.lua_setglobal(state, to_luastring('REFERENCE_CONTROLS'));
    push(JSON.parse(fs.readFileSync('tools/fixtures/experiment_rbmk_before.json', 'utf8'))); lua.lua_setglobal(state, to_luastring('BASELINE'));
    const referenceResult = lauxlib.luaL_dofile(state, to_luastring('tools/map_reference_tests.lua'));
    if (referenceResult !== lua.LUA_OK) throw Error(lua.lua_tojsstring(state, -1));
}
