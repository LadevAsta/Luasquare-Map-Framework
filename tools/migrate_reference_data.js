// Deterministic import of the captured pre-migration declarations. Run
// check_map.js --catalog first. This generates JSON data, never executable Lua.
const fs = require('fs');
const path = require('path');
process.chdir(path.resolve(__dirname, '..'));
const baseline = require('./fixtures/experiment_rbmk_before.json');
const catalog = JSON.parse(fs.readFileSync('.control-build/migration/catalog.json', 'utf8'));
const clone = value => JSON.parse(JSON.stringify(value));
const qualify = name => 'reference.' + name.toLowerCase();
const plant = [], instruments = [], bindings = [], links = [];
const movedFields = new Set(['breakerClosed', 'closed', 'breakerMonitorPos', 'breakerMonitorOffset', 'generatorMonitorOffset']);
const dieselGenerated = new Set(['grid', 'breaker', 'rampRateMW', 'autoStart']);
const bindingIds = new Map();
function binding(target, profile) {
    const key = profile + ':' + target;
    if (bindingIds.has(key)) return bindingIds.get(key);
    const id = qualify('binding.' + target.replace(/[^a-z0-9_.-]/gi, '_'));
    if (bindings.some(node => node.id === id)) throw Error('Binding ID collision: ' + id);
    bindings.push({id, type: 'source.binding', config: {profile, targets: [target], required: false}});
    bindingIds.set(key, id);
    return id;
}
function endpoint(name) {
    if (name === 'service' || name === 'makeup') return {component: 'reference.supply', port: 'fluid'};
    if (name === 'void') return {component: 'reference.drain', port: 'fluid'};
    if (name === 'rbmk_recirc') return {component: 'reference', port: 'recirculation'};
    if (name === 'rbmk' || name === 'rbmk_water' || name === 'rbmk_water_percent') return {component: 'reference', port: 'water'};
    return {component: qualify(name), port: 'fluid'};
}
const input = (component, property, round = 'none') => ({component, path: property, round});
const feeds = {
    reactor_mwth: input('reference', 'thermalMW', 'floor'), f1_coretemp: input('reference.fuel_5_5', 'coreHeat', 'floor'),
    f1_skintemp: input('reference.fuel_5_5', 'skinHeat', 'floor'), f1_coltemp: input('reference.fuel_5_5', 'heat', 'floor'),
    totalflux: input('reference', 'TotalFluxSubtracted', 'floor'), averageXenon: input('reference', 'AverageXenon', 'floor'),
    aprinsertion: input('reference', 'aprPercent', 'floor'), gauge_maxtemp: input('reference', 'MaxHeat'),
    gauge_waterlevel: input('reference.main_steam_separator', 'levelPercent'), gauge_steamlevel: input('reference.main_steam_separator', 'steamPercent'),
    gauge_steamline_pressure: input('reference.main_steam', 'pressureFraction'), gauge_rpvpressure: input('reference', 'pressurePercent'),
    gauge_hotwell: input('reference.hotwell', 'levelPercent'), gauge_hotwell_temp: input('reference.hotwell', 'temperature')
};
for (const declaration of baseline.registrations) {
    const node = {id: qualify(declaration.id), type: declaration.type, config: clone(declaration.config)};
    if (node.type.startsWith('instrument.')) {
        node.id = qualify('instrument.' + declaration.id);
        if (node.type === 'instrument.seg7') node.config = {digits: node.config};
        node.config.interval = node.type === 'instrument.seg7' ? 0.1 : 0.2;
        if (feeds[declaration.id]) node.config.input = feeds[declaration.id];
        instruments.push(node); continue;
    }
    const spec = catalog.plant[node.type.slice(6)];
    for (const key of Object.keys(node.config)) {
        if (spec.bindings?.[key]) node.config[key] = binding(node.config[key], spec.bindings[key]);
        else if (spec.endpoints?.[key]) {
            node.config[key] = endpoint(node.config[key]);
            const forward = !['target', 'b', 'overflowTarget'].includes(key);
            links.push({from: forward ? clone(node.config[key]) : {component: node.id, port: key},
                to: forward ? {component: node.id, port: key} : clone(node.config[key])});
            delete node.config[key];
        } else if (spec.references?.[key]) node.config[key] = qualify(node.config[key]);
        else if (!spec.fields[key]) {
            if (movedFields.has(key) || node.type === 'plant.diesel' && dieselGenerated.has(key)) delete node.config[key];
            else throw Error(node.id + ': unaccounted field ' + key);
        }
    }
    if (node.type === 'plant.breaker' && node.config.owner && baseline.registrations.some(n => n.id === node.config.owner)) node.config.owner = qualify(node.config.owner);
    if (node.type === 'plant.pump' && node.config.peakMW || node.type === 'plant.generator') node.dependsOn = [node.config.breaker];
    if (node.type === 'plant.diesel') node.dependsOn = [node.config.generator];
    plant.push(node);
}
plant.push({id: 'reference.supply', type: 'plant.boundary', config: {mode: 'supply'}}, {id: 'reference.drain', type: 'plant.boundary', config: {mode: 'drain'}});
const settings = {};
for (const key of Object.keys(catalog.types['rbmk.core'].fields.settings.fields)) {
    const original = key[0].toUpperCase() + key.slice(1);
    if (baseline.core[original] !== undefined) settings[key] = baseline.core[original];
}
const kindByCode = {1: 'fuel', 2: 'steam', 3: 'control', 4: 'reflector', 5: 'blank', 7: 'source', 8: 'absorber', 9: 'void'};
const cells = [];
baseline.core.Matrix.forEach((column, x) => column.forEach((original, y) => {
    const kind = kindByCode[original.type]; if (!kind) throw Error('Unsupported cell code ' + original.type);
    const cell = {x: x + 1, y: y + 1, kind};
    if (kind === 'fuel') cell.fuel = original.fuelType;
    if (kind === 'control') Object.assign(cell, {name: original.name, group: original.group, indicator: baseline.indicators[original.name] && binding(baseline.indicators[original.name], 'sprite'),
        visual: original.visualEnt && binding(original.visualEnt, 'mover'), insertion: original.insertion, graphiteTip: original.graphiteTip, reflector: original.reflector,
        autoRegulator: original.autoRegulator, autoMaxInsertion: original.autoMaxInsertion});
    if (kind === 'source') Object.assign(cell, {sourceStrength: original.sourceStrength, closedSource: original.closedSource});
    if (kind === 'reflector') cell.reflectorIn = original.reflectorIn;
    cells.push(cell);
}));
const core = {id: 'reference', type: 'rbmk.core', config: {model: baseline.core.ModelName, origin: baseline.core.WorldOrigin, spacing: baseline.core.CellSpacing,
    width: baseline.core.Width, height: baseline.core.Height, column: [64, 64, 256], hollowPercent: 10, initialWaterPercent: 85, tickInterval: 0.1,
    settings, cells, separator: 'reference.main_steam_separator', grid: 'reference.station_grid', breaker: 'reference.rbmk_control_rods_breaker',
    blowoutValvePrefix: 'brush_rpv', blowoutValveCount: 89, catastrophicRelay: binding('explodetest', 'relay')}};
const capacityFields = {
    tg1: {exhaustVolume: ['SteamSpace'], exhaustMaxAmount: ['MaxSteam'], exhaustHardMaxAmount: ['HardMaxSteam']},
    main_cooling_tower: {basinMaxAmount: ['MaxWater']},
    main_condenser: {steamMaxAmount: ['MaxSteam'], steamHardMaxAmount: ['HardMaxSteam'], steamVolume: ['SteamSpace']},
    main_deaerator: {amount: ['MaxWater', 2 / 3], maxAmount: ['MaxWater'], hardMaxAmount: ['MaxWater', 1.05], steamSpace: ['SteamSpace', 0.25], steamMaxAmount: ['SteamSpace', 1.5]},
    main_steam_separator: {waterAmount: ['MaxWater', 0.8], maxWaterAmount: ['MaxWater', 1.2], hardMaxWaterAmount: ['MaxWater', 1.35],
        maxSteamAmount: ['MaxSteam'], hardMaxSteamAmount: ['HardMaxSteam'], steamVolume: ['SteamSpace'], maxPressure: ['RPVMaxPressure'], hardMaxPressure: ['RPVHardPressure'],
        steamRatio: ['SteamExpansionRatio'], steamLatentHeatKJPerL: ['WaterLatentHeatKJPerL']},
    main_steam: {volume: ['SteamSpace', 0.5], maxAmount: ['MaxSteam', 0.5], hardMaxAmount: ['HardMaxSteam', 0.5]},
    hotwell: {maxAmount: ['MaxWater'], hardMaxAmount: ['MaxWater', 1.2]}
};
for (const [id, fields] of Object.entries(capacityFields)) {
    const node = plant.find(node => node.id === qualify(id)); node.derived = {};
    for (const [key, [field, scale = 1]] of Object.entries(fields)) {
        node.derived[key] = {component: 'reference', field, scale, unit: catalog.types['rbmk.core'].capacities[field].unit};
        delete node.config[key];
    }
}
plant.find(node => node.id === 'reference.hotwell_drain_valve').config.minFlowFraction = 0.2;
function write(family, name, value) {
    const destination = `data_static/luasquare/${family}/experiment_rbmk/${name}.json`;
    fs.mkdirSync(path.dirname(destination), {recursive: true}); fs.writeFileSync(destination, JSON.stringify(value, null, 2) + '\n');
}
const laneByType = {'source.binding': -1800, 'plant.boundary': -1400, 'plant.fluid': -1150, 'plant.pump': -850, 'plant.valve': -600,
    'plant.separator': -300, 'rbmk.core': -250, 'plant.deaerator': 0, 'plant.heat_exchanger': 300, 'plant.turbine': 300,
    'plant.condenser': 600, 'plant.cooling_tower': 900, 'instrument.seg7': 1200, 'instrument.gauge': 1200,
    'control.target_group': 1450, 'rbmk.presentation': 1700, 'annunciator.console': 1900, 'rbmk.cell': 1900};
function decorate(nodes, group) {
    const rows = new Map();
    for (const node of nodes) {
        const x = laneByType[node.type] ?? (node.type.startsWith('plant.') ? 1050 : 1500);
        const row = rows.get(x) || 0; rows.set(x, row + 1);
        node.editor = {x, y: row * 100, group, label: node.id.split('.').pop().replaceAll('_', ' ').toUpperCase()};
    }
}
const coreNodes = [core, {id: 'reference.fuel_5_5', type: 'rbmk.cell', config: {core: 'reference', x: 5, y: 5}}];
decorate(coreNodes, 'core'); decorate(plant, 'plant'); decorate(bindings, 'bindings');
write('components', 'core', {schema: 'luasquare.components/v1', id: 'reference.core', components: coreNodes});
write('components', 'plant', {schema: 'luasquare.components/v1', id: 'reference.plant', components: plant, links});
write('components', 'bindings', {schema: 'luasquare.components/v1', id: 'reference.bindings', components: bindings});
instruments.push({id: 'reference.feedwater_target', type: 'control.target_group', config: {pumps: ['reference.feedwater_pump_a', 'reference.feedwater_pump_b'], sensor: {component: 'reference.main_steam_separator', port: 'fluid'}}},
    {id: 'reference.hotwell_target', type: 'control.target_group', config: {pumps: ['reference.hotwell_makeup_pump'], sensor: {component: 'reference.hotwell', port: 'fluid'}}});
decorate(instruments, 'instruments');
write('components', 'instruments', {schema: 'luasquare.components/v1', id: 'reference.instruments', components: instruments});
const presentation = [
    {id: 'reference.presentation', type: 'rbmk.presentation', config: {core: 'reference', separator: qualify('main_steam_separator'), turbine: qualify('tg1'), generator: qualify('tg1_generator'),
        grid: qualify('station_grid'), coolant: qualify('cooling_water'), deaerator: qualify('main_deaerator')}},
    {id: 'reference.alarms', type: 'annunciator.console', config: {}}
];
decorate(presentation, 'presentation');
write('components', 'presentation', {schema: 'luasquare.components/v1', id: 'reference.presentation', components: presentation});
const displays = fs.readdirSync('data_static/luasquare/3d2display/experiment_rbmk').filter(name => name.endsWith('.json')).sort().map(name => 'experiment_rbmk/' + name);
write('map', 'main', {schema: 'luasquare.map/v1', id: 'experiment_rbmk', packages: ['source', 'powerplant', 'rbmk', 'instruments', 'presentation'],
    packs: ['experiment_rbmk/core.json', 'experiment_rbmk/plant.json', 'experiment_rbmk/bindings.json', 'experiment_rbmk/instruments.json', 'experiment_rbmk/presentation.json'],
    sources: {control: ['experiment_rbmk/operator_controls.json'], ['3d2display']: ['_themes/rbmk.json', ...displays], annunciator: ['experiment_rbmk/rbmk_annunciators.json'],
        audio: ['_shared/luasquare/sounds/foundation_buses.json', '_shared/luasquare/sounds/rbmk_annunciators.json', '_shared/luasquare/subtitle_styles/foundation_styles.json']},
    startup: {intervals: {LUASQUARE_3D2D: 0.2, LUASQUARE_ANNUNCIATOR: 0.5, ...Object.fromEntries(Object.entries(baseline.intervals).filter(([key]) => Object.values(catalog.plant).some(spec => spec.namespace === key)))}}});
console.log('Imported reference components and explicit existing source selections.');
