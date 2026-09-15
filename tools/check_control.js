// Requires luaparse and fengari in .control-build/testdeps (see control README).
const fs = require('fs');
const path = require('path');
const {execFileSync} = require('child_process');
const luaparse = require('../.control-build/testdeps/node_modules/luaparse');
const {lua, lauxlib, lualib, to_luastring} = require('../.control-build/testdeps/node_modules/fengari');
const root = path.resolve(__dirname, '..');
const external = path.resolve(root, '../DarkEnergyConstruct-Reactor-Map');
process.chdir(root);
const changed = execFileSync('git', ['diff', '--name-only'], {encoding: 'utf8'}).trim().split(/\r?\n/);
function files(directory) {
    return fs.readdirSync(directory, {withFileTypes:true}).flatMap(entry => entry.isDirectory() ? files(path.join(directory, entry.name)) : [path.join(directory, entry.name)]);
}
const luaFiles = new Set([...changed.filter(p => p.endsWith('.lua') && fs.existsSync(p)), ...files('lua/luasquare_module/control').filter(p => p.endsWith('.lua')),
    'lua/autorun/client/luasquare_control_client.lua', 'lua/luasquare_rbmk/bootstrapper/experiment_controls.lua',
    'tools/control_tests.lua', 'tools/control_editor_tests.lua', path.join(external, 'lua/luasquare_dfr/bootstrapper/gm_darkfusion_v2.lua')]);
for (const file of luaFiles) luaparse.parse(fs.readFileSync(file, 'utf8'), {luaVersion:'5.1'});
process.stdout.write('Parsed ' + luaFiles.size + ' changed/new Lua files.\n');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
function push(value) {
    if (value === null || value === undefined) lua.lua_pushnil(L);
    else if (typeof value === 'string') lua.lua_pushstring(L, to_luastring(value));
    else if (typeof value === 'boolean') lua.lua_pushboolean(L, value);
    else if (typeof value === 'number') lua.lua_pushnumber(L, value);
    else {
        lua.lua_newtable(L);
        for (const [key, child] of Object.entries(value)) {
            if (Array.isArray(value)) lua.lua_pushinteger(L, Number(key)+1); else lua.lua_pushstring(L, to_luastring(key));
            push(child); lua.lua_settable(L, -3);
        }
    }
}
push(JSON.parse(fs.readFileSync('data_static/luasquare/control/experiment_rbmk/operator_controls.json','utf8')));
lua.lua_setglobal(L, to_luastring('RBMK_SOURCE'));
push(JSON.parse(fs.readFileSync(path.join(external, 'data_static/luasquare/control/gm_darkfusion_v2/operator_controls.json'),'utf8')));
lua.lua_setglobal(L, to_luastring('DFR_SOURCE'));
const result = lauxlib.luaL_dofile(L, to_luastring('tools/control_tests.lua'));
if (result !== lua.LUA_OK) throw Error(lua.lua_tojsstring(L, -1));
const editorResult = lauxlib.luaL_dofile(L, to_luastring('tools/control_editor_tests.lua'));
if (editorResult !== lua.LUA_OK) throw Error(lua.lua_tojsstring(L, -1));
if (process.argv.includes('--sources-only')) {
    process.stdout.write('Source/runtime checks complete; manual VMF/BSP audit skipped.\n');
    process.exit(0);
}

const {entities} = require('./control_migration');
function reportCodes(id, event) {
    return [`LUASQUARE_CONTROL.ReportOutput('${event}',CALLER,ACTIVATOR)`,
        `LUASQUARE_CONTROL.ReportOutput('${id}','${event}',CALLER,ACTIVATOR)`];
}
function compiledEntities(text) {
    const tokens = text.match(/"(?:\\.|[^"\\])*"|[{}]/g) || [];
    const records = [];
    let index = 0;
    while (index < tokens.length) {
        if (tokens[index++] !== '{') throw Error('Invalid BSP entity opening');
        const record = {};
        while (tokens[index] !== '}') {
            const key = tokens[index++], value = tokens[index++];
            if (!key || !value || !key.startsWith('"') || !value.startsWith('"')) throw Error('Invalid BSP entity property');
            const name = key.slice(1, -1);
            (record[name] ||= []).push(value.slice(1, -1));
        }
        index++;
        records.push(record);
    }
    return records;
}
for (const [directory, map] of [[root, 'experiment_rbmk'], [external, 'gm_darkfusion_v2']]) {
    const vmf = entities(fs.readFileSync(path.join(directory, 'maps', map + '.vmf'), 'utf8'));
    const source = JSON.parse(fs.readFileSync(path.join(directory, 'data_static/luasquare/control', map, 'operator_controls.json'), 'utf8'));
    const physical = source.controls.flatMap(control => control.kind === 'keypad'
        ? Object.entries(control.keys).map(([token,target]) => ({id:control.id+'.key.'+token, target, class:'func_button', kind:'momentary'}))
        : control.target ? [control] : []);
    const targets = new Set(physical.map(control => control.target));
    for (const control of physical) {
        const matches = vmf.filter(entity => entity.props.targetname === control.target);
        if (matches.length !== 1 || matches[0].props.classname !== control.class) throw Error('Invalid physical binding: ' + control.id);
        if (((Number(matches[0].props.spawnflags) & 32) !== 0) !== (control.kind === 'toggle')) throw Error('Physical kind mismatch: ' + control.id);
        for (const event of ['OnPressed', 'OnIn', 'OnOut']) {
            const output = matches[0].outputs.filter(output => output.event === event && reportCodes(control.id, event).includes(output.parts[2]));
            if (output.length !== 1 || output[0].parts[3] !== '0') throw Error('Invalid report wiring: ' + control.id);
        }
    }
    for (const entity of vmf) for (const output of entity.outputs) {
        if (targets.has(output.parts[0]) && ['Lock', 'Unlock'].includes(output.parts[1])) throw Error('Competing native lock: ' + entity.props.id);
        if (['func_button', 'func_rot_button'].includes(entity.props.classname) && output.parts[1] === 'RunPassedCode'
            && !output.parts[2].startsWith('LUASQUARE_CONTROL.ReportOutput')) throw Error('Unmigrated operator output: ' + entity.props.id);
    }
    const bsp = fs.readFileSync(path.join(directory, 'maps', map + '.bsp'));
    const compiled = bsp.subarray(bsp.readInt32LE(8), bsp.readInt32LE(8) + bsp.readInt32LE(12)).toString();
    if (/(?:DFR.UseControl|LUASQUARE_KEYPAD\.)/.test(compiled)) throw Error('Old API in compiled map');
    const compiledRecords = compiledEntities(compiled);
    for (const control of physical) {
        const matches = compiledRecords.filter(record => record.targetname?.[0] === control.target && record.classname?.[0] === control.class);
        if (matches.length !== 1) throw Error('Invalid compiled binding: ' + control.id);
        for (const event of ['OnPressed', 'OnIn', 'OnOut']) {
            const reports = (matches[0][event] || []).filter(output => reportCodes(control.id, event).some(code => output.includes(code)));
            if (reports.length !== 1) throw Error('Missing/duplicate compiled report: ' + control.id);
        }
    }
    process.stdout.write(map + ': audited ' + source.controls.length + ' controls, ' + physical.length + ' physical bindings and rebuilt BSP reports.\n');
}
