# Luasquare Map Framework agent guide

This file applies to the entire repository. Luasquare is an actively developed Garry's Mod addon, not a standalone Lua application. Preserve mapper-facing behavior, Source entity integration, server authority, and cleanup/reload behavior when making changes.

## Read before changing code

1. Check `git status --short` and preserve all pre-existing edits. Never assume a dirty file is disposable.
2. Read `lua/implementation_passes.txt`. Its Planned and Applied sections are the current implementation-pass plan and should not be silently reordered, reclassified, or rewritten.
3. Read `lua/module_checklist.txt` for the intended package boundaries and longer-term DFR decomposition. Its progress labels can lag newer implementation-pass notes and current code.
4. Read the root `README.md` and the README inside any source-driven subsystem being changed:
   - `lua/luasquare_module/3d2display/README.md`
   - `lua/luasquare_module/timeline/README.md`
   - `lua/luasquare_module/audio/README.md`
5. Inspect the relevant entry point, compiler, runtime, networking files, editor, and packed JSON examples before changing a public API or schema.

When documentation and code disagree, establish what the runtime currently does before editing. Treat the current consolidated data paths under `data_static/luasquare/` as canonical. Report stale documentation rather than copying an obsolete path into new code.

## Token efficiency

- Read and follow C:\Users\chang\.codex\RTK.md.
- Use RTK for supported shell commands. Use `rtk proxy` when complete, unfiltered output is needed.
- Use Headroom's MCP compression selectively for large, repetitive content when it reduces total context usage.
- Do not resend content already read merely to compress it.
- Retrieve original content whenever omitted details are needed for editing, debugging, or verification.
- Preserve required documentation reads, complete source inspection, diagnostics, and validation.
- If either tool is unavailable, report it briefly and continue with normal tools.

## Architecture boundaries

- `lua/luasquare_module/` is reusable Garry's Mod map-simulation infrastructure. It must not know DFR or map-specific targetnames.
- `lua/luasquare_powerplant/` contains reusable fluid, thermal, turbine, generator, and grid simulation.
- `lua/luasquare_rbmk/` contains the RBMK simulation and the bundled reference-map integration.
- `lua/luasquare_dfr/` contains Dark Fusion Reactor state, physics, procedures, presentation, and DFR-specific wrappers around shared modules.
- Map-owned bootstrap scripts own VMF targetnames, coordinates, capacities, relays, and map-specific orchestration. Reusable modules own behavior.
- The external `DarkEnergyConstruct-Reactor-Map` repository owns the `gm_darkfusion_v2` bootstrap. The `experiment_rbmk` bootstrap remains here as the framework example.
- Keep simulation state, operator controls, telemetry/presentation, developer debugging, and map bindings separate.
- Do not move behavior into the RBMK package unless it is RBMK-specific. Do not refactor RBMK merely because adjacent shared or DFR code is being changed; touch it when a shared API change requires it.

Most APIs live in persistent global namespaces such as `LUASQUARE_3D2D`, `LUASQUARE_TIMELINE`, `LUASQUARE_AUDIO`, `LUASQUARE_SOURCEBINDING`, `LUASQUARE_CONTROLBINDING`, `LUASQUARE_MACHINERY`, `LUASQUARE_*` power-plant namespaces, `RBMK`, and `DFR`. Add generic capabilities to the appropriate shared namespace and keep map instances/configuration in bootstraps.

## Current direction

- The current DFR version is `foundation-0.1`. Do not bump it to `foundation-0.2` until the pass plan explicitly says its prerequisite migration passes are complete.
- Source-driven 3D2D displays, JSON timelines, and source-driven audio are implemented. Extend their v1 schemas compatibly unless a deliberate schema migration is part of the task.
- The declarative annunciator migration is implemented. The existing control-binding module is not the finished Control Layer described in the Planned section; do not mistake that prototype for completion of the later pass.
- Near-term planned work includes the full control layer, a 3D2D logging element, display power/injection behavior, graph optimization, development-mode gating, broader JSON migration, and the revised catalyzer control flow. Do not select or bundle multiple passes without user direction.
- The DFR remains incomplete. `lua/module_checklist.txt` defines the intended locations for future core physics, alarms, faults, resources, facility systems, hazards, and endings.

## Garry's Mod Lua and realm rules

- This code runs in Garry's Mod Lua/LuaJIT and uses GMod APIs; it is not portable stock Lua. Do not add external Lua dependencies.
- Preserve one-time load guards such as `LUASQUARE_*_CORE_LOADED` and explicit `include(...)` ordering.
- Shared/client files must be sent with `AddCSLuaFile` from a server-loaded entry point. Client autorun loaders under `lua/autorun/client/` initialize client engines and UI.
- Keep server-only entity, timer, concommand, file-write, and networking code out of client execution. Keep rendering, VGUI, and client audio-channel code out of server execution.
- The server owns simulation state, timeline execution, display actions/variables, PA queues, soundscape state, and other gameplay decisions. Client previews are simulations and must not mutate authoritative runtime state.
- Treat all net messages and player interactions as untrusted. Preserve or add payload limits, authorization, rate/cooldown checks, target validation, range/plane/line-of-sight checks where relevant, and server-side revalidation of requested actions.
- Do not allow JSON sources to execute Lua, console commands, arbitrary `EntFire`, URLs, absolute paths, or path traversal. Expose trusted behavior through named registrations and typed/validated parameters.
- Prefer bounded tables, capped discovery, chunked payloads, incremental state, and late-join snapshots over sending full runtime structures repeatedly.

## Lifecycle and cleanup

- Server bootstraps should include `luasquare_module/cleanup.lua` before guarded initialization.
- Framework globals and map bootstrap guards should use `LUASQUARE_`, `RBMK_`, or `DFR_` prefixes. Register an exceptional global through `LUASQUARE_CLEANUP.RegisterGlobal`.
- Named runtime timers should use one of those prefixes. Register any exceptional timer prefix through `LUASQUARE_CLEANUP.RegisterTimerPrefix`.
- New long-lived subsystems must survive the normal workflow: `PreCleanupMap` stops/cancels runtime activity, globals and caches are cleared, map entities respawn, and the run-on-spawn bootstrap reconstructs a clean instance.
- Cancel timelines and stop audio/effects while their owners and entity bindings still exist. Do not leave hooks, timers, commands, channels, stale entity references, or preview state behind.
- Use `IsValid` for entity lifetime checks and invalidate caches when map entities can respawn.

## Declarative source workflow

- Packed, distributable sources live under:
  - `data_static/luasquare/3d2display/`
  - `data_static/luasquare/timeline/`
  - `data_static/luasquare/audio/`
  - `data_static/luasquare/annunciator/`
- These sources are loaded through the `GAME` search path so map addons can contribute data while depending on this framework's Lua runtime.
- Files under `garrysmod/data/luasquare/.../drafts/` are editor output. They are intentionally not production sources and are not loaded automatically. Do not promote or overwrite drafts unless the task asks for it.
- Preserve schema identifiers (`luasquare.3d2display/v1`, `luasquare.timeline/v1`, `luasquare.audio/v1`, and `luasquare.annunciator/v1`), stable IDs, deterministic/canonical JSON output, diagnostics, and read-only treatment of packed sources.
- Extend the compiler, runtime, networking/catalog representation, editor controls, documentation, and representative packed JSON together when adding a schema feature.
- Display/timeline/audio/annunciator editors must remain safe development tools. Preview must be reversible, isolated from production channels where promised, and cleaned on close, disconnect, cleanup, or source reload.

## Coding conventions

- Follow the style of the file being edited: four-space indentation, single-quoted strings in Lua, early returns, small local helpers, and a local namespace alias (`local DISPLAY = LUASQUARE_3D2D`, for example) in larger subsystem files.
- Public API names use the existing namespace's `PascalCase` convention. Internal fields and JSON keys generally use `camelCase`; stable IDs and paths are normalized lowercase strings where the subsystem requires it.
- Prefer explicit tables and readable control flow over metaprogramming. Avoid generated Lua.
- Keep configuration/tuning near the owning namespace or DFR config, not scattered as unexplained constants. Preserve units and document conversions, especially Hammer units versus 3D2D canvas pixels and plant power/energy units.
- Hooks, timers, net strings, concommands, components, providers, actions, and bindings need stable, namespaced identifiers.
- Maintain compatibility with existing packed sources and map bootstraps unless the requested pass explicitly permits a clean migration. When compatibility is intentionally dropped, update every repository-owned caller and document the break.
- Do not hand-edit compiled models, textures, audio, or BSP binary output. Edit source assets or the scripts under `tools/` and regenerate only when the task requires it. Treat `maps/experiment_rbmk.vmf` as map source and `maps/experiment_rbmk.bsp` as compiled output.

## In-game Editor standards
- When developing in-game gui editor, see documentation on https://wiki.facepunch.com/gmod/VGUI_Element_List for available elements to be used. The design should empathize the user.
- All editor GUIs shall use gray and dark-gray surfaces with white text. Avoid white controls and white title/tool bars background because default light-gray text becomes difficult to read.
- Editors shall not have locked gui window and have drag-rescale enabled, Unless explicitly stated otherwise in the task.
- New vgui have disabled fullscreen/windowed icon button disabled by default, if editor needs a fullscreen/windowed option, enable that button rather than inventing a new one.
- Editors shall have a separate subwindow for creating, finding, loading, and saving packed sources and drafts.
- Editors shall prefer searchable, categorized asset browsers over dropdowns when selecting registered assets whose catalogs may grow substantially.
- To prevent subwindow being occluded by the main window when the main window is focused, make the subwindow focus itself when cursor is hovered above.
- AVOID relying too much on freeform text input fields in editor such as JSON, or input fields that can obviously replaced with dropdowns for example, When choosing Enums, choosing cases, choosing type, choosing kind. This is to avoid author error.
- Text fields that should only accept numbers should just use DNumberWang. If the value may be large, make it wide too.
- Editor diagnostics and informational hints shall print to the console (and may also use a scrollable in-window status area); do not use notification or message popups which has been confirmed to be occluded by editor windows when testing. confirmation dialogs that require an explicit user choice remain appropriate. do note that console is only accessible after editor is closed. otherwise they are occluded as well. Important hints and diagnostics should use an in-window status area.

## Validation

Always perform available static checks:

- Review `git diff --check`, `git diff --stat`, and the focused diff.
- Parse every changed JSON file with a strict JSON parser.
- Search for all callers/registrations when renaming an API, ID, net message, target convention, source path, or schema field.
- Verify server/client inclusion and `AddCSLuaFile` paths for every new Lua file.
- Check cleanup registration and late-join synchronization for new persistent or networked state.

VMF source editing, BSP Rebuilds and Real in-game testing are Manual workflow on user's side.
So, when the testing needs to edit the map vmf, provide a list of needed change or new things to add to the user so that the changes are developed properly in Hammer++ Editor.
DO NOT directly edit the vmf as this expose the risks of vmf corruption and user may lose track of the change.
IF vmf edit is prompted make sure that it will not corrupt the vmf structure, and do not attempt to edit world geometry at all.
For in-game verification, Tell the user to test it in a real Garry's Mod map session, provide a numbered list of testing needed. (What need to be tested? And how it is tested while considering the available gameplay implementation or tool or debug utilities).

## Documentation and handoff

- Update the relevant README when a public API, schema, source layout, editor workflow, map convention, or operator/developer behavior changes.
- Only update `lua/implementation_passes.txt` only when the user asks for planning/status edits or when the completed task clearly authorizes moving that exact pass between sections.
- Update `lua/module_checklist.txt` when architectural ownership or implemented module status materially changes, while preserving its hierarchy format.
- In the handoff, distinguish implemented behavior from prototypes and plans, name affected realms/subsystems, list validation performed, and call out any required map reload, source export, BSP rebuild, or late-join testing.
