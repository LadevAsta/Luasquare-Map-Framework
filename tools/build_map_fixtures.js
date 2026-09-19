// Authoring fixtures only. No file generated here is selected by normal startup.
const fs = require('fs');
const path = require('path');
process.chdir(path.resolve(__dirname, '..'));
function write(family, name, value) {
    const destination = `data_static/luasquare/${family}/_fixtures/${name}.json`;
    fs.mkdirSync(path.dirname(destination), {recursive: true});
    fs.writeFileSync(destination, JSON.stringify(value, null, 2) + '\n');
}
const components = [], controls = [];
for (const [index, name] of ['alpha', 'beta'].entries()) {
    const core = `fixture.${name}`;
    components.push(
        {id: `${core}.grid`, type: 'plant.grid', config: {type: 'offsite', sourceCapacityMW: 100, enabled: true}},
        {id: `${core}.rods`, type: 'plant.breaker', config: {grid: `${core}.grid`, closed: true, maxMW: 10}},
        {id: `${core}.steam`, type: 'plant.fluid', config: {type: 'steamline', fluidType: 'steam', amount: 0, maxAmount: 50000, hardMaxAmount: 100000, volume: 1000}},
        {id: `${core}.supply`, type: 'plant.boundary', config: {mode: 'supply', temperature: 20}},
        {id: `${core}.feed`, type: 'plant.pump', config: {source: {component: `${core}.supply`, port: 'fluid'}, target: {component: core, port: 'water'}, rate: 100, headPressure: 200, enabled: false}},
        {id: core, type: 'rbmk.core', config: {model: `Isolation ${name}`, origin: [index * 512, 0, 256], width: 3, height: 3,
            initialWaterPercent: 85, steamNetwork: `${core}.steam`, grid: `${core}.grid`, breaker: `${core}.rods`,
            settings: {blowoutEnabled: false, autoRegulatorEnabled: false},
            cells: [{x: 2, y: 2, kind: 'fuel', fuel: 'MEU'}, {x: 1, y: 2, kind: 'source', sourceStrength: 26, closedSource: false},
                {x: 3, y: 2, kind: 'control', name: 'R1', group: 'test', insertion: 1, autoRegulator: true}],
            autofill: {ignoreEdge: false, ignoreNearVoid: false}}, editor: {x: index * 400, y: 0, group: name}}
    );
    for (const [suffix, action, params] of [
        ['scram', `${core}.scram`, {}], ['select', `${core}.rod_toggle`, {name: 'R1'}],
        ['feed_on', `${core}.feed.enabled`, {value: true}], ['feed_off', `${core}.feed.enabled`, {value: false}]
    ]) controls.push({id: `${core}.${suffix}`, kind: 'momentary', label: `${name} ${suffix}`, actions: {press: {id: action, params}}});
    for (const [suffix, action, value] of [['rods_out', 'rod_target', 100], ['rods_in', 'rod_target', 0], ['apr_on', 'apr_target', 10], ['apr_off', 'apr_target', 0]]) {
        controls.push({id: `${core}.${suffix}`, kind: 'momentary', label: `${name} ${suffix}`,
            actions: {press: {id: `${core}.${action}`, params: {value}}}});
    }
}
write('components', 'two_core', {schema: 'luasquare.components/v1', id: 'fixture.two_core', components});
write('control', 'two_core_controls', {schema: 'luasquare.control/v1', id: 'fixture.two_core_controls', controls});
write('map', 'two_core', {schema: 'luasquare.map/v1', id: 'fixture.two_core', packages: ['powerplant', 'rbmk', 'presentation'],
    packs: ['_fixtures/two_core.json'], sources: {control: ['_fixtures/two_core_controls.json']}});
write('components', 'heat_exchanger', {schema: 'luasquare.components/v1', id: 'fixture.heat_exchanger', components: [
    {id: 'hx.hot', type: 'plant.fluid', config: {amount: 1000, maxAmount: 1000, temperature: 90}},
    {id: 'hx.cold', type: 'plant.fluid', config: {amount: 1000, maxAmount: 1000, temperature: 20}},
    {id: 'hx.hot_pump', type: 'plant.pump', config: {source: {component: 'hx.hot', port: 'fluid'}, target: {component: 'hx.hot', port: 'fluid'}, rate: 100, headPressure: 10, enabled: true}},
    {id: 'hx.cold_pump', type: 'plant.pump', config: {source: {component: 'hx.cold', port: 'fluid'}, target: {component: 'hx.cold', port: 'fluid'}, rate: 100, headPressure: 10, enabled: true}},
    {id: 'hx.exchanger', type: 'plant.heat_exchanger', config: {hotNetwork: 'hx.hot', coldNetwork: 'hx.cold', hotPump: 'hx.hot_pump', coldPump: 'hx.cold_pump', effectiveness: 0.8, approachTemperature: 5, maxThermalMW: 10, enabled: true}}
]});
write('map', 'heat_exchanger', {schema: 'luasquare.map/v1', id: 'fixture.heat_exchanger', packages: ['powerplant'], packs: ['_fixtures/heat_exchanger.json']});
console.log('Wrote opt-in two-core and heat-exchanger fixtures.');
