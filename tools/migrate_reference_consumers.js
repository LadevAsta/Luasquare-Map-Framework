const fs = require('fs');
const path = require('path');
const {execFileSync} = require('child_process');
process.chdir(path.resolve(__dirname, '..'));
const controlPath = 'data_static/luasquare/control/experiment_rbmk/operator_controls.json';
const controls = JSON.parse(fs.readFileSync(controlPath, 'utf8'));
const machineActions = {pump_speed: 'speed', pump_enabled: 'enabled', valve: 'enabled', transformer: 'enabled', grid_reset: 'reset', diesel: 'enabled',
    generator_trip: 'trip', generator_sync: 'sync', generator_reset: 'reset', generator_auto_sync: 'auto_sync', turbine_valve: 'valve', turbine_bypass: 'bypass',
    turbine_repair: 'repair', turbine_extreme_trip: 'extreme_trip', deaerator_steam: 'steam', deaerator_relief: 'relief', deaerator_overflow: 'overflow', deaerator_auto: 'auto'};
for (const control of controls.controls) {
    if (control.display && !control.display.startsWith('reference.')) control.display = 'reference.instrument.' + control.display.toLowerCase();
    for (const action of Object.values(control.actions || {})) {
        if (!action.id.startsWith('rbmk.')) continue;
        const suffix = action.id.slice(5), params = action.params || {};
        if (machineActions[suffix]) {
            action.id = 'reference.' + params.name + '.' + machineActions[suffix];
            action.params = {};
            const value = params.level ?? params.enabled ?? params.percent;
            if (value !== undefined) action.params.value = value;
        } else if (suffix.startsWith('alarm_')) action.id = 'reference.alarms.' + suffix.slice(6);
        else if (suffix === 'feedwater_target' || suffix === 'hotwell_target') action.id = 'reference.' + suffix + '.target';
        else action.id = 'reference.' + suffix;
    }
}
fs.writeFileSync(controlPath, JSON.stringify(controls, null, 2) + '\n');
const providers = {'rbmk.fw_flow': ['reference.panel.feedwater', ''], 'rbmk.cooling_loop': ['reference.panel.cooling', ''],
    'rbmk.electrical': ['reference.panel.electrical', ''], 'rbmk.rpv': ['reference.presentation', 'rpv.'], 'rbmk.tg1': ['reference.presentation', 'turbine.'],
    'rbmk.deaerator': ['reference.presentation', 'deaerator.'], 'rbmk.graphs': ['reference.presentation', 'graphs.'], 'rbmk.annunciator': ['reference.presentation', 'alarms.']};
function walk(value) {
    if (!value || typeof value !== 'object') return;
    if (providers[value.provider]) {
        const [provider, prefix] = providers[value.provider]; value.provider = provider;
        if (value.path) value.path = prefix + value.path;
    }
    Object.values(value).forEach(walk);
}
// These consumers only rename scalar references. Preserve their existing layout
// so the review shows wiring changes instead of unrelated JSON reformatting.
function replaceLeaves(text, value) {
    const tokens = [...text.matchAll(/"(?:\\.|[^"\\])*"|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\]:,]/g)];
    let cursor = 0;
    const edits = [];
    function visit(next) {
        const token = tokens[cursor++];
        if (token[0] === '{') {
            while (tokens[cursor][0] !== '}') {
                const key = JSON.parse(tokens[cursor++][0]); cursor++; visit(next[key]);
                if (tokens[cursor][0] === ',') cursor++;
            }
            cursor++;
        } else if (token[0] === '[') {
            let index = 0;
            while (tokens[cursor][0] !== ']') { visit(next[index++]); if (tokens[cursor][0] === ',') cursor++; }
            cursor++;
        } else if (JSON.parse(token[0]) !== next) edits.push({start: token.index, end: token.index + token[0].length, text: JSON.stringify(next)});
    }
    visit(value);
    for (const edit of edits.reverse()) text = text.slice(0, edit.start) + edit.text + text.slice(edit.end);
    return text;
}
for (const directory of ['data_static/luasquare/3d2display/experiment_rbmk', 'data_static/luasquare/annunciator/experiment_rbmk']) {
    for (const name of fs.readdirSync(directory).filter(name => name.endsWith('.json'))) {
        const file = path.join(directory, name), current = fs.readFileSync(file, 'utf8');
        const text = process.argv.includes('--restore-format') ? execFileSync('git', ['show', 'HEAD:' + file.replaceAll('\\', '/')], {encoding: 'utf8'}) : current;
        const source = JSON.parse(text); walk(source);
        if (process.argv.includes('--restore-format') && JSON.stringify(source) !== JSON.stringify(JSON.parse(current))) throw Error('Unexpected consumer content: ' + file);
        fs.writeFileSync(file, replaceLeaves(text, source));
    }
}
console.log('Migrated reference control actions, instrument IDs and packed telemetry consumers without aliases.');
