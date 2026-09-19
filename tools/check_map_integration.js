const fs = require('fs');
const path = require('path');
const {lua, lauxlib, lualib, to_luastring} = require('../.control-build/testdeps/node_modules/fengari');
const {entities} = require('./control_migration');
process.chdir(path.resolve(__dirname, '..'));
const state = lauxlib.luaL_newstate(); lualib.luaL_openlibs(state);
function push(value) {
    lua.lua_checkstack(state, 8);
    if (value === null || value === undefined) lua.lua_pushnil(state);
    else if (typeof value === 'string') lua.lua_pushstring(state, to_luastring(value));
    else if (typeof value === 'number') lua.lua_pushnumber(state, value);
    else if (typeof value === 'boolean') lua.lua_pushboolean(state, value);
    else {
        lua.lua_newtable(state);
        for (const [key, child] of Object.entries(value)) {
            if (Array.isArray(value)) lua.lua_pushinteger(state, Number(key) + 1); else lua.lua_pushstring(state, to_luastring(key));
            push(child); lua.lua_settable(state, -3);
        }
    }
}
const files = {};
function collect(directory) {
    for (const entry of fs.readdirSync(directory, {withFileTypes: true})) {
        const location = directory + '/' + entry.name;
        if (entry.isDirectory()) collect(location);
        else if (entry.name.endsWith('.json')) files[location] = fs.readFileSync(location, 'utf8');
    }
}
collect('data_static/luasquare');
push(files); lua.lua_setglobal(state, to_luastring('TEST_FILES'));
push(entities(fs.readFileSync('maps/experiment_rbmk.vmf', 'utf8')).map(entity => entity.props));
lua.lua_setglobal(state, to_luastring('TEST_ENTITIES'));
lua.lua_pushcfunction(state, L => {
    try { push(JSON.parse(lua.lua_tojsstring(L, 1))); } catch { lua.lua_pushnil(L); }
    return 1;
});
lua.lua_setglobal(state, to_luastring('TEST_JSON_DECODE'));
const result = lauxlib.luaL_dofile(state, to_luastring('tools/map_integration_tests.lua'));
if (result !== lua.LUA_OK) throw Error(lua.lua_tojsstring(state, -1));
