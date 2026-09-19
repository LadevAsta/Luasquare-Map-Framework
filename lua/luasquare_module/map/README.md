# Declarative map instances

The server loads `luasquare.map/v1` manifests from `data_static/luasquare/map/` and `luasquare.components/v1` packs from `data_static/luasquare/components/`, through `GAME`. The reference entry point selects `experiment_rbmk/main.json`. Its `reference` core and all plant, binding, instrument and presentation declarations are packed data. `experiment_controls.lua`, the singleton selector, and the executable reference layout have been retired.

Changes to plant sources require a **map reload**. There is no live plant replacement or inventory-preserving reload. Editor exports go to `data/luasquare/map/drafts/` and `data/luasquare/components/drafts/`; copy reviewed files into the matching packed paths manually. Drafts never load automatically. Existing display, Control, audio, timeline and annunciator sources keep their v1 schemas.

The approved implementation covers subpasses 01–30 and has passed its RBMK acceptance cycle. DFR migration is deferred, the parent pass remains Planned, and DFR remains `foundation-0.1`. Static tests remain separate from the completed real Garry's Mod run; see the [archived acceptance procedure](archive/ACCEPTANCE.md) and [run log](archive/ACCEPTANCETESTS.md).

## Source contract

```json
{
  "schema": "luasquare.map/v1",
  "id": "my_map",
  "packages": ["source", "powerplant", "rbmk", "instruments", "presentation"],
  "packs": ["my_map/plant.json"],
  "sources": {"control": ["my_map/operator_controls.json"]},
  "overrides": {"unit.tank": {"amount": 500}},
  "startup": {"intervals": {"LUASQUARE_FLUID": 0.1}}
}
```

Package IDs select trusted `MAP.RegisterPackage` registrations, never Lua paths. Required packages must exist; an entry `{"id":"optional_package","optional":true}` may be absent. Dependencies still must be selected explicitly (`rbmk` requires `powerplant`). Select `presentation` to use existing JSON engines and their integrations. Sources lists are exhaustive: manifest-owned engines do not also discover map or shared sources. Include shared themes and audio registries explicitly.

```json
{
  "schema": "luasquare.components/v1",
  "id": "my_plant",
  "presets": {"reservoir": {"type": "plant.fluid", "config": {"maxAmount": 1000}}},
  "components": [
    {"id": "unit.tank", "preset": "reservoir", "config": {"amount": 400}, "editor": {"x": 0, "y": 0, "group": "Unit", "label": "Unit tank"}},
    {"id": "unit.pump", "type": "plant.pump", "config": {"rate": 10, "enabled": false}},
    {"id": "unit.drain", "type": "plant.boundary", "config": {"mode": "drain"}}
  ],
  "links": [
    {"from": {"component": "unit.tank", "port": "fluid"}, "to": {"component": "unit.pump", "port": "source"}},
    {"from": {"component": "unit.pump", "port": "target"}, "to": {"component": "unit.drain", "port": "fluid"}}
  ]
}
```

Component IDs are map-wide, lowercase, stable, and at most 128 characters; references never depend on pack order. Port names are case-sensitive (`regulationSensor`, for example). Duplicate component/preset/pack IDs, duplicate inclusions, duplicate links, incompatible port kind/unit/fluid/direction/cardinality and missing references are errors. Physical cycles are legal. `dependsOn` describes **construction** dependencies and must be acyclic.

Precedence is type defaults, preset config, component config, then manifest overrides. Objects merge by field; arrays replace as a whole, including empty arrays. Strict decoding preserves empty arrays versus objects and numeric object keys. Duplicate JSON keys, comments, trailing commas, invalid UTF-8/Unicode, nonfinite numbers and `null` source values are rejected. Omit optional fields instead of using null. Unknown schema versions and configuration fields are errors. A future incompatible schema needs an explicit migration; there is no automatic version conversion.

`derived` maps a numeric field to a declared capacity, for example `{"maxAmount":{"component":"unit.core","field":"MaxWater","unit":"L","scale":1.2,"offset":0}}`. It adds a construction dependency and resolves after the owner's geometry exists. Units must agree. An explicit manifest override for that field takes precedence over the derivation.

Automatic pump breakers and diesel generators are expanded before construction. A powered pump without `breaker` produces `<pump>.breaker`; a generator without `breaker` produces `<generator>.breaker`; a diesel without `generator` produces `<diesel>.generator`, with its breaker. IDs are collision-checked. Specify explicit references to use existing nodes. Generated nodes are visible in the graph and accept manifest overrides by their generated ID. The reference pack declares its historical generated objects explicitly so their original settings remain reviewable.

Limits: 1 MiB per source, 8 MiB per loading group, 128 packs per family, 2,048 components including generated nodes, 8,192 links, 24 nesting levels and 131,072 values. Source paths must be relative, lowercase `.json` paths without traversal, schemes or absolute paths. No source field executes Lua, console commands or arbitrary Source inputs.

## Catalog and adapters

The catalog supplies typed fields, defaults, limits, units and ports. Values use the existing simulation units: water/fluid inventories in liters, pressure in bar, temperature in Celsius, electrical/thermal power in MW, battery storage in MWh, time in seconds and physical anchors in Hammer units. Field metadata takes precedence for exceptions; historical tuning formulas are unchanged.

| Package | Components |
| --- | --- |
| `source` | `source.binding`, `machinery.machine`, `machinery.path` |
| `powerplant` | `plant.fluid`, `plant.boundary`, `plant.valve`, `plant.pump`, `plant.heat_exchanger`, `plant.separator`, `plant.condenser`, `plant.deaerator`, `plant.cooling_tower`, `plant.grid`, `plant.breaker`, `plant.transformer`, `plant.generator`, `plant.diesel`, `plant.turbine` |
| `rbmk` | `rbmk.core`, `rbmk.cell`, `rbmk.presentation` |
| `instruments` | `instrument.seg7`, `instrument.gauge`, `control.target_group` |
| `presentation` | `annunciator.console`, `timeline.owner`; existing v1 source engines |

Source bindings name exact targets, a registered class profile, required/optional and first/all resolution, notes/tags/unit. Profiles whitelist fixed inputs. Machinery exposes its registered movements and tracktrain destinations; it cannot author arbitrary input names. `LUASQUARE_MAP.ReportPathTrack(mapId, machineId, CALLER)` is the trusted arrival bridge for a declared `path_track`; operator movement still uses Control requests.

Plant fluid/thermal references use `{component,port}` capabilities; special RBMK strings and provider aliases are gone. Supply/drain boundaries are explicit components. Core-specific adapters live in `luasquare_rbmk`, outside reusable powerplant modules. Event relays, rupture relays, turbine emitters/shakes, rod visuals and selector sprites reference logical Source bindings. Each RBMK core resolves its own `blowoutValvePrefix` plus `blowoutValveCount` directly to exact `func_movelinear` entities and owns that cache and effect cleanup. Continuous machine effects stop before their owner is destroyed.

`rbmk.core` owns its matrix, fuel definitions/state, rods, selector, APR/PID, inventories, failures, effects and debug state. `LUASQUARE_RBMK.Get('reference')` explicitly addresses the reference core. Server simulation never swaps a global `RBMK` table. Cores interact only through declared plant connections. `fuelPresets` selects a trusted built-in fuel `model` and bounded numeric overrides; xenon/flux functions remain Lua. The cell-grid author supports fuel, control, steam, reflector, blank, source, absorber, void and autofill. Rod percentage input retains the operator convention: 100% withdraws, 0% inserts.

Every machine declaration registers `<component>.<action>` and a telemetry provider at `<component>`. Boolean/numeric telemetry predicates are `<component>.boolean`, `.at_least` and `.at_most`, with typed `path`/`value` parameters. A destroyed owner is unavailable. Display and annunciator catalogs expose telemetry paths. Instruments select a component/path with bounded scale/offset and rounding; unavailable values can hold or become zero. `control.target_group` shares one target across explicitly listed pumps, including initial keypad application.

Physical buttons and keypads remain in `luasquare.control/v1`. Their actions refer to instance-qualified registrations. Player use, display interactions and timeline automation retain Control authority, locks, acknowledgement, validation, attribution and request cleanup. Timeline/display actions address `control.<control_id>` when operating controls. The plant editor never invokes them.

`timeline.owner` registers a procedure component with `targets:[{alias,component}]` and `timelines:[{slot,source}]`. The source must also be selected in the manifest. Targets are registered timeline capabilities (including `control.<id>` and audio adapters); bindings and clip capabilities are checked before activation. `<owner>.start` and `<owner>.cancel` Control actions take a `slot`. No procedure runs automatically. Cancellation stops owned requests before their target components are destroyed.

## Lifecycle and extension API

Include `luasquare_module/cleanup.lua` before guarded bootstrap initialization. Include `luasquare_module/map/engine.lua`, then call `LUASQUARE_MAP.Load(relativeManifestPath)` after Source entities initialize. It returns an instance or actionable diagnostics. `MAP.Load` owns source loading and activation; do not also call existing engines' discovery/Start methods for that plant.

`MAP.RegisterType(id, definition)` supplies `package`, `fields`, `ports`, optional `capacities`, trusted `validateDefinition`, and `create/link/initialize/register/validate/start/stop/destroy` methods. Lifecycle callbacks receive `(instance, compiledNode, object)`; `create` returns the object, and returning `false, reason` or raising aborts startup. `instance:Get(id)` accesses another constructed object. Register rollback callbacks with `instance:Own(callback)` **before** allocating resources that could survive a constructor exception. `instance:Own(callback, 'consumers')` stops dependent activity first.

The loader compiles, constructs in dependency order, resolves links and derived capacities, initializes/registers/validates integrations, preflights selected sources and controls, and then starts simulation. Failure unwinds consumers, component stops, resource releases and destructors in reverse ownership order; no instance remains active. Cleanup stops timelines, controls, alarms, displays and audio while owners/bindings still exist. Start priority preserves core/plant timer ordering; the reference keeps core/plant 0.1 s, SEG7 0.1 s, gauges/displays 0.2 s and annunciators 0.5 s. GMod timer scheduling still requires in-game comparison.

`MAP.Destroy(instanceOrId, reason)` is idempotent. `MAP.StopAll(reason)` is used during cleanup. Production replacement requires reload; `MAP.Create` rejects a second active map instance. Multiple cores belong to the same map instance. Trusted package implementations can extend the catalog, but sources cannot select an include path.

## Editor and inspection

Run `luasquare_map_editor`, or use Options → Luasquare → Powerplant Framework → Plant graph / source editor. The dark main window uses native drag, resize, minimize and maximize/restore. Child windows focus on hover without interrupting a captured drag or an open menu.

Use the separate Sources window to search packed manifests, select one row and load it with the explicit load button. Local drafts use a file browser rooted at `data/luasquare/map/drafts/`; export destinations are separate and existing files require overwrite confirmation. Packed files are read-only. Packages, source selections, overrides and startup settings are edited through the Manifest button beside Sources. Keypad bindings and preview remain in the Control editor; the plant source manager does not launch other subsystem editors. The compact top toolbar also contains search, undo/redo, validation, link view and diagnostics. Right-click empty graph space to add a component or preset at that coordinate. Right-click a node to duplicate, remove, create a preset or start a typed connection. Compatible destinations highlight until selected; clicking empty space cancels. Right-drag pans and the wheel zooms.

The graph shows generated nodes, cross-pack links and configuration references. **Bindings** toggles the main viewport to a searchable in-window table for Source bindings, machinery, physical instruments and non-flow presentation integrations; selecting a row drives the normal inspector, while add and confirmed delete operations use short dialogs. Configuration references touching those hidden management nodes are omitted from the canvas. Link views filter All, Fluid / thermal, Electrical or References. Connections use directed orthogonal routes that terminate at node borders; arrow orientation is derived from the reached border and bidirectional ports use two lanes. Selecting a node highlights every touching link. Every visible authored or configuration-reference route can be selected and its single turn anchor dragged with an immediate preview. Repeated clicks at an overlapping node/link location cycle its hit stack. Authored anchors use optional `link.editor.bends`; reference anchors use `manifest.editor.referenceBends`. Both follow connected-node movement and remain authoring-only metadata alongside component `editor.x`, `editor.y`, `editor.group` and `editor.label`. Labels are preferred in graph headings and connection descriptions, with stable IDs retained as secondary text. Node movement previews live and commits to the 16-unit grid only after a meaningful drag, so selection clicks do not move nodes. Generated nodes identify their owner and can be positioned independently through manifest editor metadata; runtime settings remain owner configuration or explicit overrides. A resizable inspector and cursor-side hover card expose labels, IDs, types, packs, generated owners, state and typed ports. Duplicate remaps internal references; explicit external references remain unchanged.

Component configuration opens in a resizable `DProperties` window. Numeric controls receive their schema range, property tooltips describe type/unit/range/default, and changes remain staged until **Apply changes** commits one validated undo step. References and enumerations retain searchable typed selectors, string arrays such as Source targets/tags use add/delete tables, and RBMK cells retain their palette/grid. Tags are mapper metadata and do not affect Source entity resolution. Structural preview is local and creates no gameplay objects or inventories. Invalid drafts remain editable and diagnostic text appears both in-window and in the console. Undo retains at most 64 snapshots with a 16 MiB encoded history budget. Closing clears preview/subscriptions; unsaved changes require a discard choice.

The reference feedwater, cooling-loop and electrical dashboards are complex-build 3D2D layouts bound directly to component telemetry. The former graph-visible `telemetry.panel` placeholder nodes and simple-build `columns` lines are no longer used.

Server catalogs and source reads require single-player or admin authority. Transfers are revisioned, at most 8 MiB queued per client, chunked at 24,000 bytes, with bounded reassembly and expiry. Packed sources cross this boundary as validated canonical JSON text and are decoded independently on the client, preserving empty arrays and empty objects. Discovery caps files/directories/entities. At most 32 selected components are inspected at 2 Hz, with changed primitive fields sent incrementally. Opening/subscribing after joining initializes current state; a plant lifetime reset clears clients. Requests cannot apply plant edits, execute actions or load drafts. Disconnect, timeout, close and map cleanup remove subscriptions.

The transfer envelope permits its canonical `sourceText` string up to the 1 MiB per-source limit while ordinary decoded source fields retain the 4,096-byte string limit. Envelope decode failures are reported in the console and editor status area and cancel the pending load.

`instrument.seg7` accepts exactly one entity mode. `prefix: "name"` discovers contiguous `SEG7_name_0` through `SEG7_name_N` `prop_dynamic` entities, capped at 32 digits; index 0 is the least-significant digit. Gaps, duplicate indices and wrong classes reject startup. Existing maps may keep the explicit `digits` binding array. The editor catalog groups discovered SEG7 prefixes for structured selection.

## Automated checks

Development-only dependencies are `luaparse` and `fengari` under `.control-build/testdeps/node_modules`; the addon requires neither. From the repository root:

```text
node tools/check_map.js
node tools/check_map_integration.js
node tools/check_control.js --map=experiment_rbmk
node tools/check_migration_static.js
git diff --check
```

Checks cover strict/canonical JSON, merge precedence, references/units/bounds/cycles, rollback, actual constructor parity against `tools/fixtures/experiment_rbmk_before.json`, generated components, multi-core isolation and intentional transfers, heat exchange, actual reference and fixture source engines, VMF entity classes, telemetry protocols, Control semantics and native editor lifecycle doubles. They do not emulate GMod rendering, physics movement, real network transport or audio playback. The broader default Control audit also checks deferred DFR, whose current `containment_lower` physical binding audit fails; it is not part of RBMK acceptance.

`tools/migrate_reference_data.js` reconstructs the reference packs from the captured declarations and a catalog exported by `check_map.js --catalog`. `build_map_fixtures.js` creates opt-in test packs. These are maintenance tools, not startup paths. Historical Control migration execution is disabled to prevent overwriting current instance-qualified wiring. No VMF geometry or BSP was edited during this migration.
