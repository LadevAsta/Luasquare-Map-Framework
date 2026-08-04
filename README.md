# Luasquare Map Framework

Lua-driven reactor, power-plant, instrumentation, and Hammer integration systems for Garry's Mod maps.

Luasquare began as an RBMK-style reactor experiment, but it is now a broader map-simulation framework. It provides a simulated reactor core, fluid and electrical plant systems, reusable control-room modules, Source entity bindings, developer visualizations, and the early foundation of a fictional Dark Fusion Reactor.

> [!WARNING]
> This project is under active development. The APIs, tuning values, and map-integration conventions are not stable, and several systems are prototypes or have not yet been thoroughly tested. It is intended for addon developers and Hammer mappers, not as a finished drop-in gamemode.

## What is included

| Area | Current capabilities |
| --- | --- |
| RBMK simulation | Grid-based reactor layouts; four-direction neutron-flux propagation; fuel, xenon, heat, control rods, automatic regulation, vessel water/steam, recirculation, pressure, integrity, leaks, blowouts, SCRAM, and failure handling |
| Balance of plant | Fluid networks, pumps, valves, heat exchangers, steam separators, condensers, deaerators, cooling towers, turbines, generators, diesel generators, electrical grids, breakers, and transformers |
| Map modules | 3D2D displays and graphs, skin-based seven-segment displays, gauges, numeric keypads, annunciators, control bindings, Source entity bindings, and movable-machinery helpers |
| Dark Fusion Reactor | A staged reactor framework with startup controls, resource state, VMF bindings, machinery, independently animated core visuals, reusable timelines, six-catalyzer sequencing, telemetry, debug controls, and a guarded simulation tick |
| Development tools | Client-side RBMK and plant overlays, DFR admin controls in the spawn menu, bundled annunciator/display assets, and asset-generation scripts |
| Reference content | The playable `experiment_rbmk` BSP, its editable VMF source, an LRBMKP-400 layout, and a complete map-specific RBMK bootstrap |

The simulation is gameplay-oriented and fictionalized. It borrows concepts from real plant systems and from other games such as Minecraft 1.12's HBM's Nuclear Tech Mod, but it is not an engineering model or an exact recreation of a real RBMK.

## Project status

The RBMK and balance-of-plant code form the most complete demonstration in this repository. The reference bootstrap connects a reactor to a steam separator, turbine-generator, condenser, deaerator, cooling loop, pumps, electrical grids, control-room displays, and alarms.

The Dark Fusion Reactor package is a foundation for the `gm_darkfusion_v2` project. Its binding, machinery, visual, startup, and debug layers exist, but the full reactor physics, procedures, faults, disasters, audio, subtitles, and facility simulation described in the design notes are not complete.

There is currently no compatibility promise between revisions, no automated test suite, and no automatic dependency detection.

## Installation

Clone or copy the repository into the Garry's Mod addons directory:

```text
garrysmod/
`-- addons/
    `-- luasquare_map_framework/
        |-- lua/
        |-- maps/
        |-- materials/
        |-- models/
        `-- sound/
```

Restart Garry's Mod or reload the map after changing server-side framework files. **Clean Up Everything** now clears framework declarations, registries, entity caches, debug commands, and named runtime timers before map entities respawn. A map with a run-on-spawn bootstrap then constructs a fresh simulation automatically.

## Trying the RBMK reference map

Start the included map:

```text
map experiment_rbmk
```

The map's `lua_run` automatically includes the current bootstrap when the map loads and after **Clean Up Everything**. The bootstrap only initializes once for each spawned map state.

The reference is deliberately map-specific. Its targetnames, positions, capacities, relays, controls, and display registrations are examples to study and adapt rather than defaults suitable for another map.

The editable map source is available at [`maps/experiment_rbmk.vmf`](maps/experiment_rbmk.vmf). Open it in Hammer or Hammer++ to inspect the entity I/O, targetname conventions, control-room wiring, and `lua_run` integration alongside the Lua bootstrap.

## Integrating Luasquare into a map

Luasquare does not automatically create a plant. A map owns a bootstrap script that:

1. Includes the reusable modules it needs.
2. Configures tick rates and simulation constants.
3. Registers reactor cells, fluid networks, machinery, grids, displays, alarms, and Hammer targetnames.
4. Starts each registered system.
5. Exposes operator actions through a named `lua_run` entity and its `RunPassedCode` input.

A small server-side bootstrap has this general shape:

```lua
include('luasquare_module/cleanup.lua')

if LUASQUARE_MY_MAP_SIM_INITIALIZED then return end

include('luasquare_module/seg7display.lua')
include('luasquare_module/3d2display.lua')
include('luasquare_module/annunciator/annunciator.lua')
include('luasquare_powerplant/init.lua')
include('luasquare_rbmk/init.lua')

RBMK.WorldOrigin = Vector(0, 0, 0)
RBMK.CellSpacing = 64
RBMK.CreateMatrix(3, 3)
RBMK.SetCell(2, 2, RBMK.CreateFuelChannel('MEU'))
RBMK.FillBlanksWithSteam()
RBMK.AddInitialWater(80)

LUASQUARE_FLUID.RegisterNetwork('main_steam', {
    fluidType = 'steam',
    amount = 0,
    maxAmount = 10000,
    pressure = 1,
    temperature = 100
})

RBMK.SetSteamNetwork('main_steam')

RBMK.Start()
LUASQUARE_FLUID.Start()

LUASQUARE_MY_MAP_SIM_INITIALIZED = true
```

In Hammer, place a `lua_run`, enable **Run Code on Spawn**, give it a stable targetname such as `MY_MAP_SIM`, and put the bootstrap `include(...)` in its `Code` keyvalue. The spawn flag is required for automatic rebuilding after **Clean Up Everything**. Buttons and relays can then send calls to it:

```text
Target:      MY_MAP_SIM
Input:       RunPassedCode
Parameter:   RBMK.SCRAM()
```

Framework-owned globals and map bootstrap guards should use a `LUASQUARE_`, `RBMK_`, or `DFR_` prefix so cleanup can remove them. A map can register an exceptional name with `LUASQUARE_CLEANUP.RegisterGlobal(name)`. Custom named timers should use the same prefixes, or register their prefix with `LUASQUARE_CLEANUP.RegisterTimerPrefix(prefix)`.

Keep VMF targetnames and map coordinates in the map's bootstrap. Reusable behavior belongs in `luasquare_module`, `luasquare_powerplant`, or the relevant reactor package.

For a real integration example, see [`lua/luasquare_rbmk/bootstrapper/experiment_rbmk.lua`](lua/luasquare_rbmk/bootstrapper/experiment_rbmk.lua). The reactor grid itself is defined separately in [`lua/luasquare_rbmk/layouts/LRBMKP-400.lua`](lua/luasquare_rbmk/layouts/LRBMKP-400.lua).

## Displays and Hammer naming

The 3D2D module can derive panel dimensions from an `info_target` name:

```text
DISPLAY512x256_reactor_status
```

`512x256` is the surface size in Hammer units, not the canvas resolution. At the default `0.1` scale, that surface produces a `5120x2560` canvas. Place the target at the upper-left corner of the panel, with local X following the panel width and local Z pointing away from the display surface. Explicit dimensions and scale in the bootstrap override the name metadata.

The framework also includes:

- Skin-driven pseudo seven-segment models with digits, blank, and minus states.
- Source-entity gauges driven by registered getter functions.
- Server-authored 3D2D text, bar, and graph displays replicated to clients.
- Alarm annunciators with active, acknowledged, muted, reset, and re-alarm behavior.

## Debugging

After a framework bootstrap has run, open:

```text
Spawn Menu -> Options -> Luasquare
```

The **RBMK Framework** and **Powerplant Framework** panels control client-side world overlays and filters. Registered components need `monitorPos`, a named monitor target, or reactor world-position data to appear in the appropriate overlay.

The **Dark Fusion Reactor** panel exposes development controls for state changes, binding validation, machinery, core radii and animation, timelines, and individual catalyzer inspection. These commands are restricted to single-player, admins, and the server console. They are test tools, not player-facing reactor controls. The DFR remains a work in progress.

## Repository layout

```text
lua/
|-- autorun/client/          Client debug overlays and spawn-menu panels
|-- luasquare_module/        Reusable displays, controls, bindings, and machinery
|-- luasquare_powerplant/    Fluid, thermal, turbine, generator, and grid systems
|-- luasquare_rbmk/          RBMK core simulation, layouts, and example bootstrap
`-- luasquare_dfr/           DFR runtime, reactor, procedure, presentation, and superstructure modules
maps/                        Compiled reference map and editable VMF source
materials/, models/, sound/ Bundled control-room and environmental assets
tools/                       Annunciator model/material generation scripts
```

Most public APIs are organized in global namespaces:

- `RBMK`
- `LUASQUARE_FLUID`, `LUASQUARE_PUMP`, `LUASQUARE_VALVE`
- `LUASQUARE_TURBINE`, `LUASQUARE_POWERGENERATOR`, `LUASQUARE_POWERGRID`
- `LUASQUARE_3D2D`, `LUASQUARE_SEG7`, `LUASQUARE_GAUGE`, `LUASQUARE_ANNUNCIATOR`
- `LUASQUARE_SOURCEBINDING`, `LUASQUARE_CONTROLBINDING`, `LUASQUARE_MACHINERY`
- `DFR`

Registration tables in the Lua source are currently the API reference. Many modules also contain a commented example near the end of the file.

## Contributing

When changing the framework:

- Keep map-specific targetnames and orchestration in bootstrap scripts.
- Keep generic Source and display helpers independent of a particular reactor.
- Treat telemetry, operator controls, simulation state, and developer debug state as separate concerns.
- Test changes in a fresh map session, including late-joining clients when networking or displays are affected.

The architecture backlog and current implementation notes are tracked in [`lua/module_checklist.txt`](lua/module_checklist.txt).

## License

This project is licensed under the [GNU General Public License v3](LICENSE).
