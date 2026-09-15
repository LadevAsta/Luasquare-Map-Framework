// Regenerate entity data with VBSP, preserving all existing non-entity compiled data.
// This prevents this VBSP build's onlyents mode from deleting unrelated static props.
const fs = require('fs');
const path = require('path');
const {execFileSync} = require('child_process');
const root = path.resolve(__dirname, '..');
const game = path.resolve(root, '../..');
const vbsp = path.resolve(game, '../bin/vbsp.exe');
function rebuild(source, original, destination) {
    const before = fs.readFileSync(original);
    const base = path.basename(source, '.vmf');
    const build = path.join(root, '.control-build/compile', base);
    fs.mkdirSync(build, {recursive: true});
    const vmf = path.join(build, base + '.vmf');
    const bsp = path.join(build, base + '.bsp');
    fs.copyFileSync(source, vmf);
    fs.copyFileSync(original, bsp);
    execFileSync(vbsp, ['-game', game, '-onlyents', '-keepstalezip', vmf], {stdio: 'pipe'});
    const compiled = fs.readFileSync(bsp);
    if (before.subarray(0,4).toString() !== 'VBSP' || compiled.readInt32LE(4) !== before.readInt32LE(4)) throw Error('BSP format mismatch');
    const start = compiled.readInt32LE(8), length = compiled.readInt32LE(12);
    if (start < 1036 || length < 1 || start + length > compiled.length) throw Error('Invalid compiled entity lump');
    const entities = compiled.subarray(start, start + length);
    const text = entities.toString();
    if (!text.includes('LUASQUARE_CONTROL.ReportOutput') || /(?:DFR.UseControl|LUASQUARE_KEYPAD\.)/.test(text)) throw Error('Unmigrated compiled controls');
    const offset = Math.ceil(before.length / 4) * 4;
    const result = Buffer.alloc(offset + entities.length);
    before.copy(result);
    entities.copy(result, offset);
    result.writeInt32LE(offset, 8);
    result.writeInt32LE(entities.length, 12);
    result.writeInt32LE(compiled.readInt32LE(16), 16);
    result.writeInt32LE(compiled.readInt32LE(20), 20);
    // Every non-entity lump, including absolute game-lump offsets, remains byte-identical.
    for (let i = 1; i < 64; i++) {
        const h = 8 + i * 16;
        const o = before.readInt32LE(h), n = before.readInt32LE(h + 4);
        if (!before.subarray(h, h + 16).equals(result.subarray(h, h + 16)) || !before.subarray(o, o + n).equals(result.subarray(o, o + n))) throw Error('Non-entity data changed');
    }
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    fs.writeFileSync(destination, result);
    process.stdout.write(base + ': regenerated ' + entities.length + ' entity bytes; all 63 non-entity lumps preserved.\n');
}
if (require.main === module) {
    rebuild(path.join(root, 'maps/experiment_rbmk.vmf'), path.join(root, 'maps/experiment_rbmk.bsp'), path.join(root, '.control-build/rbmk/experiment_rbmk.bsp'));
    const external = path.resolve(root, '../DarkEnergyConstruct-Reactor-Map');
    const stagedSource = path.join(root, '.control-build/dfr/maps/gm_darkfusion_v2.vmf');
    rebuild(fs.existsSync(stagedSource) ? stagedSource : path.join(external, 'maps/gm_darkfusion_v2.vmf'), path.join(external, 'maps/gm_darkfusion_v2.bsp'), path.join(root, '.control-build/dfr/maps/gm_darkfusion_v2.bsp'));
}
module.exports = {rebuild};
