// Offline, one-time source migration. Never runs or generates Lua from VMF strings.
// External writes are staged inside this repository for review and permission handling.
const fs = require('fs');
const path = require('path');
const root = path.resolve(__dirname, '..');
const external = path.resolve(root, '../DarkEnergyConstruct-Reactor-Map');
const stage = path.join(root, '.control-build/dfr');
const esc = String.fromCharCode(27);

function entities(text) {
    const out = [];
    const pattern = /(?:^|\n)entity\s*\r?\n\{/g;
    let match;
    while ((match = pattern.exec(text))) {
        const start = match.index + (text[match.index] === '\n' ? 1 : 0);
        let position = text.indexOf('{', start), depth = 0, quote = false;
        for (; position < text.length; position++) {
            const char = text[position];
            if (char === '"' && text[position - 1] !== '\\') quote = !quote;
            if (!quote && char === '{') depth++;
            if (!quote && char === '}' && --depth === 0) break;
        }
        const end = position + 1;
        const block = text.slice(start, end);
        const header = block.slice(0, block.search(/\n\s*(?:connections|solid|editor)\s*\r?\n/));
        const props = Object.fromEntries([...header.matchAll(/"([^"\r\n]+)"\s+"([^"\r\n]*)"/g)].map(m => [m[1], m[2]]));
        const outputs = [...block.matchAll(/"(On[^"\r\n]+)"\s+"([^"\r\n]*)"/g)].map(m => ({event: m[1], value: m[2], parts: m[2].split(esc), text: m[0]}));
        out.push({start, end, block, props, outputs});
        pattern.lastIndex = end;
    }
    return out;
}

function literal(value) {
    value = value.trim();
    if (/^'[^'\\]*'$/.test(value)) return value.slice(1, -1);
    if (value === 'true' || value === 'false') return value === 'true';
    if (/^-?\d+(?:\.\d+)?$/.test(value)) return Number(value);
    if (value === 'ACTIVATOR') return null;
    throw Error('Unsupported literal: ' + value);
}
function reference(code) {
    const call = /^([A-Z_]+)\.([A-Za-z]+)\((.*)\)$/.exec(code.trim());
    if (!call) throw Error('Unsupported operator call: ' + code);
    const [, namespace, method, argumentsText] = call;
    const args = argumentsText === '' ? [] : argumentsText.split(',').map(literal);
    if (namespace === 'DFR') {
        if (method === 'UseControl') return {id: 'dfr.' + args[0], params: {}};
        if (method === 'NextCoreStatusPage') return {id: 'dfr.next_core_page', params: {}};
        if (method === 'PreviousCoreStatusPage') return {id: 'dfr.previous_core_page', params: {}};
    }
    if (namespace === 'LUASQUARE_KEYPAD') {
        if (method === 'Submit') return {id: 'control.keypad_submit', params: {keypad: args[0]}};
        return {id: 'control.keypad_edit', params: {keypad: args[0], operation: method === 'Press' ? 'digit' : method === 'Clear' ? 'clear' : 'backspace', ...(method === 'Press' ? {digit: args[1]} : {})}};
    }
    const table = {
        'LUASQUARE_PUMP.SetPumpSpeed': ['pump_speed', ['name', 'level']],
        'LUASQUARE_PUMP.SetPump': ['pump_enabled', ['name', 'enabled']],
        'LUASQUARE_VALVE.SetValve': ['valve', ['name', 'enabled']],
        'LUASQUARE_POWERGRID.SetTransformer': ['transformer', ['name', 'enabled']],
        'LUASQUARE_POWERGRID.ResetGrid': ['grid_reset', ['name']],
        'LUASQUARE_DIESELGENERATOR.SetEnabled': ['diesel', ['name', 'enabled']],
        'LUASQUARE_POWERGENERATOR.Trip': ['generator_trip', ['name']],
        'LUASQUARE_POWERGENERATOR.Sync': ['generator_sync', ['name']],
        'LUASQUARE_POWERGENERATOR.ResetTrip': ['generator_reset', ['name']],
        'LUASQUARE_POWERGENERATOR.SetAutoSync': ['generator_auto_sync', ['name', 'enabled']],
        'LUASQUARE_TURBINE.AdjustValvePercent': ['turbine_valve', ['name', 'percent']],
        'LUASQUARE_TURBINE.AdjustBypassValvePercent': ['turbine_bypass', ['name', 'percent']],
        'LUASQUARE_TURBINE.Repair': ['turbine_repair', ['name']],
        'LUASQUARE_TURBINE.TestExtremeTrip': ['turbine_extreme_trip', ['name']],
        'LUASQUARE_DEAERATOR.AdjustSteamValvePercent': ['deaerator_steam', ['name', 'percent']],
        'LUASQUARE_DEAERATOR.AdjustReliefValvePercent': ['deaerator_relief', ['name', 'percent']],
        'LUASQUARE_DEAERATOR.SetOverflowValvePercent': ['deaerator_overflow', ['name', 'percent']],
        'LUASQUARE_DEAERATOR.SetAutoRegulator': ['deaerator_auto', ['name', 'enabled']],
        'RBMK.SetNeutronSourceState': ['neutron_source', ['x', 'y', 'enabled']],
        'RBMK.SetReflectorState': ['reflector', ['x', 'y', 'enabled']],
        'RBMK.SetSteamOutletOpen': ['steam_outlet', ['enabled']],
        'RBMK.SetFeedwaterInletOpen': ['feedwater_inlet', ['enabled']],
        'RBMK.SCRAM': ['scram', []],
        'LUASQUARE_ROD_SELECTOR.Toggle': ['rod_toggle', ['name']],
        'LUASQUARE_ROD_SELECTOR.ToggleGroup': ['rod_group', ['name']],
        'LUASQUARE_ROD_SELECTOR.Clear': ['rod_clear', []],
        'LUASQUARE_ANNUNCIATOR.Reset': ['alarm_reset', []],
        'LUASQUARE_ANNUNCIATOR.Acknowledge': ['alarm_ack', []],
        'LUASQUARE_ANNUNCIATOR.Mute': ['alarm_mute', []],
        'LUASQUARE_ANNUNCIATOR.TestAll': ['alarm_test', []]
    };
    const entry = table[namespace + '.' + method];
    if (!entry) throw Error('No trusted adapter for ' + code);
    return {id: 'rbmk.' + entry[0], params: Object.fromEntries(entry[1].map((key, i) => [key, args[i]]))};
}

function controlLabel(control) {
    const title = text => text.replace(/_/g, ' ').replace(/\b\w/g, char => char.toUpperCase());
    const pads = {fwlevelctrl: 'Feedwater Level Target %', hotwellctrl: 'Hotwell Level Target %', rodctrl: 'Control Rod Withdrawal %', aprctrl: 'APR Thermal Target MW'};
    if (control.kind === 'keypad') return pads[control.id] || title(control.id);
    if (control.id.startsWith('guard_') || control.id.startsWith('debug.')) return control.label;
    const ref = control.actions.press || control.actions.in || control.actions.out;
    if (!ref) return control.label;
    if (ref.id.startsWith('control.keypad_')) return (pads[ref.params.keypad] || ref.params.keypad) + ': ' + (ref.params.operation || 'submit') + (ref.params.digit === undefined ? '' : ' ' + ref.params.digit);
    if (ref.params.name) return title(ref.params.name);
    if (ref.params.x !== undefined) return title(ref.id.split('.').pop()) + ' ' + ref.params.x + ',' + ref.params.y;
    return title(ref.id.split('.').pop());
}

function write(file, bytes) { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, bytes); }
function migrate(map, directory, outputDirectory) {
    const vmf = path.join(directory, 'maps', map + '.vmf');
    const text = fs.readFileSync(vmf, 'utf8');
    if (text.includes('LUASQUARE_CONTROL.ReportOutput')) throw Error('Already migrated: ' + map);
    const all = entities(text);
    const selected = all.filter(e => ['func_button', 'func_rot_button'].includes(e.props.classname) && e.outputs.some(o => o.parts[1] === 'RunPassedCode'));
    const controls = [], renamed = new Map(), ids = new Set();
    for (const entity of selected) {
        const lua = entity.outputs.filter(o => o.parts[1] === 'RunPassedCode');
        let id = map === 'gm_darkfusion_v2' && lua[0].parts[2].startsWith('DFR.UseControl') ? literal(/^DFR\.UseControl\(([^,]+)/.exec(lua[0].parts[2])[1])
            : (entity.props.targetname || 'button_' + entity.props.id).toLowerCase().replace(/[^a-z0-9_.-]/g, '_');
        if (ids.has(id)) id += '_' + entity.props.id;
        ids.add(id);
        const toggle = (Number(entity.props.spawnflags) & 32) !== 0;
        const control = {id, label: id.replace(/_/g, ' '), kind: toggle ? 'toggle' : 'momentary', target: 'CTRLI_' + id,
            class: entity.props.classname, cooldown: 0.25, actions: {}};
        if (entity.props.targetname) renamed.set(entity.props.targetname, control.target);
        for (const output of lua) {
            const ref = reference(output.parts[2]);
            if (control.kind === 'toggle') {
                if (output.event === 'OnPressed') control.actions.in = control.actions.out = ref;
                else control.actions[output.event === 'OnIn' ? 'in' : 'out'] = ref;
            } else {
                if (control.actions.press) throw Error('Multiple action-bearing outputs on momentary ' + id);
                control.actions.press = ref;
            }
            if (ref.id.startsWith('control.keypad_')) control.parent = ref.params.keypad;
        }
        if (map === 'gm_darkfusion_v2' && lua[0].parts[2].startsWith('DFR.UseControl')) control.predicates = [{id: 'dfr.' + id, params: {}}];
        if (control.kind === 'toggle' && Object.keys(control.actions).length === 1) {
            // One-way activation toggles retain an actionless return path.
        }
        controls.push(control);
        entity.control = control;
    }
    // Native safety covers that formerly locked an operator button become predicate-owned controls.
    const controlledNames = new Set(renamed.keys());
    for (const entity of all) {
        if (!['func_button', 'func_rot_button'].includes(entity.props.classname) || entity.control) continue;
        const locks = entity.outputs.filter(o => controlledNames.has(o.parts[0]) && ['Lock', 'Unlock'].includes(o.parts[1]));
        if (!locks.length) continue;
        const id = 'guard_' + entity.props.id;
        const control = {id, label: 'Safety cover ' + entity.props.id, kind: (Number(entity.props.spawnflags) & 32) ? 'toggle' : 'momentary', target: 'CTRLI_' + id,
            class: entity.props.classname, cooldown: 0.25, actions: {}};
        entity.control = control;
        if (entity.props.targetname) renamed.set(entity.props.targetname, control.target);
        controls.push(control);
        for (const output of locks) {
            if (output.parts[1] !== 'Unlock') continue;
            const guarded = controls.find(c => c.target === renamed.get(output.parts[0]));
            guarded.predicates = [...(guarded.predicates || []), {id: 'control.position', params: {control: id, position: output.event === 'OnIn' ? 'in' : 'out'}}];
        }
    }
    const changes = [];
    for (const entity of all) {
        let block = entity.block;
        if (entity.control) {
            const control = entity.control;
            if (entity.props.targetname) block = block.replace(/"targetname"\s+"[^"\r\n]*"/, '"targetname" "' + control.target + '"');
            else block = block.replace(/("classname"\s+"[^"\r\n]*")/, '$1\r\n\t"targetname" "' + control.target + '"');
            for (const output of entity.outputs.filter(o => o.parts[1] === 'RunPassedCode')) block = block.replace(output.text, '');
            const receiver = entity.outputs.find(o => o.parts[1] === 'RunPassedCode')?.parts[0] || (map === 'experiment_rbmk' ? 'RBMK_SYSTEM' : 'LUASQUARE');
            const wiring = ['OnPressed', 'OnIn', 'OnOut'].map(event => '\t\t"' + event + '" "' + [receiver, 'RunPassedCode', "LUASQUARE_CONTROL.ReportOutput('" + event + "',CALLER,ACTIVATOR)", '0', '-1'].join(esc) + '"').join('\r\n');
            if (/connections\s*\r?\n\s*\{/.test(block)) block = block.replace(/(connections\s*\r?\n\s*\{)/, '$1\r\n' + wiring);
            else block = block.replace(/\n\s*solid\s*\r?\n/, '\n\tconnections\r\n\t{\r\n' + wiring + '\r\n\t}\r\n\tsolid\r\n');
        }
        for (const output of entity.outputs) {
            if (renamed.has(output.parts[0])) {
                if (['Lock', 'Unlock'].includes(output.parts[1])) block = block.replace(output.text, '');
                else block = block.replace(output.text, output.text.replace(output.parts[0] + esc, renamed.get(output.parts[0]) + esc));
            }
        }
        if (block !== entity.block) changes.push({...entity, block});
    }
    let migrated = text;
    for (const change of changes.reverse()) migrated = migrated.slice(0, change.start) + change.block + migrated.slice(change.end);
    if (map === 'experiment_rbmk') {
        for (const [id, maxDigits, maxValue, initialValue, clearOnSubmit, action] of [
            ['fwlevelctrl', 3, 100, 80, false, 'feedwater_target'], ['hotwellctrl', 3, 100, 35, false, 'hotwell_target'],
            ['rodctrl', 3, 100, 0, true, 'rod_target'], ['aprctrl', 4, 9999, 0, false, 'apr_target']]) {
            controls.push({id, label: id, kind: 'keypad', maxDigits, maxValue, initialValue, clearOnSubmit, display: id, cooldown: 0.25,
                actions: {submit: {id: 'rbmk.' + action, params: {}}}});
        }
    } else {
        for (const id of ['pre_annihilation_begin', 'pre_annihilation_cancel']) controls.push({id, label: id.replace(/_/g, ' '), kind: 'momentary',
            predicates: [{id: 'dfr.' + id, params: {}}], actions: {press: {id: 'dfr.' + id, params: {}}}});
        controls.push({id: 'core_pulse', label: 'Pulse core presentation', kind: 'momentary', actions: {press: {id: 'dfr.core_pulse', params: {}}}});
        const debugCode = fs.readFileSync(path.join(root, 'lua/luasquare_dfr/runtime/debug.lua'), 'utf8');
        const direct = new Set(['start', 'stop', 'halt', 'snapshot', 'use_control', 'validate_bindings', 'clear_binding_cache', 'register_v2_defaults', 'pre_annihilation_start', 'pre_annihilation_cancel']);
        for (const match of debugCode.matchAll(/^debugCommand\('luasquare_dfr_([^']+)'/gm)) {
            if (direct.has(match[1])) continue;
            const id = 'debug.' + match[1];
            controls.push({id, label: 'Developer: ' + match[1].replace(/_/g, ' '), kind: 'momentary',
                predicates: [{id: 'dfr.' + id, params: {}}], actions: {press: {id: 'dfr.' + id, params: {}}}});
        }
    }
    for (const control of controls) control.label = controlLabel(control);
    controls.sort((a,b) => a.id.localeCompare(b.id));
    write(path.join(outputDirectory, 'maps', map + '.vmf'), migrated.replace(/^[\t ]+$/gm, ''));
    write(path.join(outputDirectory, 'data_static/luasquare/control', map, 'operator_controls.json'), JSON.stringify(compactKeypads({schema: 'luasquare.control/v1', id: map + '_controls', controls}), null, 2) + '\n');
    process.stdout.write(map + ': ' + controls.length + ' controls, ' + selected.length + ' operator entities migrated.\n');
}

function compactKeypads(source) {
    const parents = new Map(source.controls.filter(control => control.kind === 'keypad').map(control => [control.id, control]));
    for (const parent of parents.values()) parent.keys = parent.keys || {};
    source.controls = source.controls.filter(control => {
        const parent = parents.get(control.parent);
        if (!parent) return true;
        const action = control.actions?.press;
        const params = action?.params;
        if (control.kind !== 'momentary' || control.class !== 'func_button' || params?.keypad !== parent.id) throw Error('Unsupported legacy keypad key: ' + control.id);
        const token = action.id === 'control.keypad_submit' ? 's' : action.id === 'control.keypad_edit'
            ? params.operation === 'digit' ? String(params.digit) : params.operation === 'clear' ? 'c' : params.operation === 'backspace' ? 'b' : null : null;
        if (!token || parent.keys[token]) throw Error('Invalid or duplicate keypad key: ' + control.id);
        parent.keys[token] = control.target;
        return false;
    });
    for (const parent of parents.values()) for (const token of ['0','1','2','3','4','5','6','7','8','9','s']) {
        if (!parent.keys[token]) throw Error('Missing mandatory keypad key: ' + parent.id + '/' + token);
    }
    return source;
}

if (require.main === module) {
    migrate('experiment_rbmk', root, root);
    migrate('gm_darkfusion_v2', external, stage);
}
module.exports = {entities, reference, migrate, controlLabel, compactKeypads};
