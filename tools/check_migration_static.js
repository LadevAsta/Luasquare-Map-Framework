// Development-only validation of the complete working-tree migration.
const fs = require('fs');
const path = require('path');
const {execFileSync} = require('child_process');
const luaparse = require('../.control-build/testdeps/node_modules/luaparse');
process.chdir(path.resolve(__dirname, '..'));
function paths(args) {
    return execFileSync('git', ['-c', 'core.safecrlf=false', ...args], {encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore']}).split('\0').filter(Boolean);
}
const files = [...new Set([...paths(['diff', '--name-only', '--diff-filter=ACMR', '-z']), ...paths(['ls-files', '--others', '--exclude-standard', '-z'])])];
let lua = 0, json = 0;
for (const file of files) {
    if (/\.(vmf|bsp)$/i.test(file)) throw Error('Unexpected map asset edit: ' + file);
    if (!/\.(lua|json|js|md|txt)$/.test(file)) continue;
    const source = fs.readFileSync(file, 'utf8');
    if (file.endsWith('.lua')) { luaparse.parse(source, {luaVersion: '5.1'}); lua++; }
    if (file.endsWith('.json')) { JSON.parse(source); json++; }
    if (/^(<<<<<<< |=======\s*$|>>>>>>> )/m.test(source)) throw Error('Conflict marker: ' + file);
}
execFileSync('git', ['diff', '--check'], {stdio: ['ignore', 'pipe', 'pipe']});
console.log(`Validated ${lua} changed/new Lua files, ${json} strict JSON files, conflict markers, whitespace and unchanged VMF/BSP assets.`);
