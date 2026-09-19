# Archived Acceptance Test Run

Status: `experiment_rbmk` reference acceptance passed after remediation 5. Multiplayer test 19 and multi-core fixture tests 20–24 remain explicitly deferred as recorded at the end of this log.
1. [LUASQUARE MAP] Activated experiment_rbmk from experiment_rbmk/main.json Passed.
2. map editor issue upon loading through find packed manifest:
```
[LUASQUARE MAP EDITOR] data_static/luasquare/components/experiment_rbmk/core.json:components.1.config.fuelPresets: invalid array size: invalid configuration
data_static/luasquare/components/experiment_rbmk/bindings.json:components.1.config.tags: invalid array size: invalid configuration
```
Map initialization went as intended however.
3. Passed.
4. Passed until rod selection rejection test
```
[LUASQUARE_CONTROL] rodctrl: failed: no rods selected
[LUASQUARE_CONTROL] rodctrl.key.s: failed: action rejected
```
Does not move any rod however, keypad locking perpetually without natural way of resetting is not intended.
5. Passed until hotwell drain valve not draining hotwell.
6. Many field in plant debug render shows
```
table: 0x8088092... > table: 0x8088092...
```
name isnt shown as their reference.
Power loss test passed.
7. Passed
8. Passed except sync button locking itself perpetually after failed sync due to action reject. This is not intended behavior.
```
[LUASQUARE_TURBINE] NORMAL trip reference.tg1: SYNC_MISMATCH
[LUASQUARE_POWERGENERATOR] Trip reference.tg1_generator: SYNC_MISMATCH
[LUASQUARE_CONTROL] button_tg1_sync: failed: action rejected
```
Sync button should not lock itself. Turbine sent reject action signal while it shouldn't be in this case. The sync failure happens for turbine as intended.
Auto-sync works.
9. Passed. ramped up correctly, shutting down and turning it back on skips MW ramping. lack of fuel causes it to ramp down until grid dead.
10. Passed.
11. Passed.
12. Passed.
13. Debug view works. Performance issue at certain angles. Noted for optimization in the future.
14. Map Plant Node Editor requires more work.
- Map editor launching button actually should belong to the broader Powerplant framework category not RBMK.
- All nodes have no label but this is due to source already not having label.
- the node can be dragged, but uneasily. placement preview unavailable, suggest a preview update during dragging event.
- First click on a node loaded by loading packed manifest shifts them into the grid.
- Node connection link are not fully visualized, suggest highlighting lines on selected node and the lines should be straight-S-perpendicular or L-perpendicular(depending on how their shape is adjusted) lines instead of current direct (angled) node-to-node. And these lines may be dragged by cursor to adjust their shape as well.
- Different viewing mode for those connection link is suggested.
    - Fluids
    - Electricals
- Showing direction of connection via arrow head is suggested, back-and-fourth should draws 2 line.
- Right-click context menu is not available. suggested for creating links and node deletion instead of using the large inspector tab.
Plant initialization is good. Tick is as intended, feed water initialize as intended.
- Showing a contextual info panel at left side of the cursor when hovering on the node is suggested.
- Tool bar are left side bar that is wide. Some action contained within can be moved to right-click context menu instead (Add,Remove, Duplicate node, start connect >expand> Fluid, Electrical) And the bar should be a top bar instead of left side bar due to UI cluttering the graph viewport. Rightclick also add node at that clicked position.
- Suggested (meta) node connection workflow
    1. Right click node
    2. Select from context menu hover start connection >
    3. start connection expand into Fluid, Electrical, etc that the component node supports.
    4. Select Fluid.
    5. Other nodes that support Fluid input highlight at their border.
    6. Left click on the highlighted to connect there. Clicking on empty space cancels.
- Hover-focus behavior works
- Resizable, Cannot be minimized (it is disabled but don't have to be)
- Find function is working.
- Text is mostly readable.
- Inspector panel cannot be resized (drag-expanding to the side)
- brush_rpv (the moving part during overpressure) is technically intended to be a part of RBMK reactor core itself. Which means they shouldn't actually show up in node editor or use source binding at all (To prevent unnecessary extra processing). RBMK directly fire moveforward to these func_movelinear brushes accordingly to random selection and what brush name prefix provided to it eg. "brush_rpv_*" 0,1,2,3... until maximum of provided rpv brush number.
- Other Editors can be launched from here as intended.
- SEG7 architecture need few changes!
    - From now SEG7 display will have SEG7_* prefix. Auto detect will use this to assign SEG7 propdynamic automatically when prompted. similar to keypads.
- The way I see it (currently with errors in test 2), you arranged the node graph in a rectangular grid, where I am required to drag them around to see clear connection visualization through connection lines. You should try re-arrange it (and have the JSON store editor node position if it hasn't yet)
- Coloring on the node's border is suggested. depending on what component it is.
15. Test deferred until next editor improvement.
16. Test deferred until next editor improvement and earlier error is explained/fixed.
17. Passed.
18. Pending until next improvement.
19. Cannot be tested in current environment, deferred.

20. Pending
21. Pending
22. Pending
23. Pending
24. Pending

## Remediation implemented (1); retest pending

The observations above are preserved as the record of the first acceptance run. The following code and packed-source remedies are implemented and have static/mock regression coverage:

- Packed source inspection now transfers validated canonical source text and decodes it independently on the client, preserving empty `fuelPresets`, `tags`, links, defaults and overrides across separated realms.
- A trusted action callback returning `false` now completes as an expected rejection without a persistent Control fault. Rod submission with no selection and turbine synchronization outside tolerance restore the requesting control for reuse; actual turbine/generator trips remain intact. Lua errors, invalid physical input, acknowledgement timeout and failed recovery remain locking faults.
- `reference.hotwell_drain_valve` declares `minFlowFraction: 0.2`.
- Plant debug output formats typed endpoints as stable `component/port` labels and uses debug wire version 11 on both realms.
- The reference RBMK core directly owns `brush_rpv_0` through `brush_rpv_88` using `blowoutValvePrefix` and `blowoutValveCount`; the 89 graph-visible source bindings were removed.
- `instrument.seg7` supports bounded contiguous prefix discovery while retaining explicit digit arrays for the current BSP.
- The plant editor was moved to Powerplant Framework and revised with native minimize, a top toolbar, context-menu authoring, live snapped dragging, labels and arranged reference positions, a resizable inspector, hover cards, family borders, selected-link highlighting, typed link views and arrows, orthogonal routing with stored bend handles, and a compiler-validated connection workflow.

Reload `experiment_rbmk`, then repeat tests 2, 4, 5, 6, 8 and 14–18. After those pass, run pending tests 20–24. Test 19 remains deferred until a multiplayer environment is available. The RBMK debug angle-dependent performance observation remains a future optimization item.


2. Failed, Cannot load experiment_rbmk from find manifest. Revamp the find packed manifest window to become more aligned to the established source manager window standards in other editors! (Double-click load is unreliable)
4. passed
5. passed
6. OVF Field for NET reference.hotwell remains Table: 0x80880...
8. Sync reset itself once resolved. However, button appears to not move as it got its position reset during rejected press immediately. Action rejection event reaching the button itself shouldn't even happen at all (Turbine always accept sync signal. It shall handle the actual syncing internally with its generator, no reaction while tripped, open breaker while synced, close while not yet synced (common cause of trip)).
14. Editor is too broken to test further.
- Right clicking on certain node type produce errors:
```
[luasquare_map_framework] addons/luasquare_map_framework/lua/luasquare_module/map/editor.lua:862: attempt to index local 'submenu' (a nil value)
  1. nodeMenu - addons/luasquare_map_framework/lua/luasquare_module/map/editor.lua:862
   2. unknown - addons/luasquare_map_framework/lua/luasquare_module/map/editor.lua:949

[LUASQUARE MAP EDITOR] data_static/luasquare/components/new/plant.json:components.1.config.pumps: invalid array size: invalid configuration
[LUASQUARE MAP EDITOR] data_static/luasquare/components/new/plant.json:components.1.config.pumps: invalid array size: invalid configuration

[luasquare_map_framework] addons/luasquare_map_framework/lua/luasquare_module/map/editor.lua:862: attempt to index local 'submenu' (a nil value)
  1. nodeMenu - addons/luasquare_map_framework/lua/luasquare_module/map/editor.lua:862
   2. unknown - addons/luasquare_map_framework/lua/luasquare_module/map/editor.lua:949

```
Submenu for starting connections of different type does not show up either.
- Rendering of S/L perpendicular lines does not meet requirement
    - Arrow head only visible when the line hit the left side of the box. otherwise occluded. Arrow head should draw at the border of the box, whether its the side or top or bottom border.
    - lines still could not be modified by cursor hitting and dragging on them.
        - Suggested: When clicking on the visuallized line, it highlight(indicating selection) and show 'anchor' point that dictates the line's shape. Moving this anchor point changes where the line turns from horizontal to vertical(from source node). When the line itself is moved by node dragging, anchor moves with it.
- Find packed manifest could not load anything in at all.
- Load local draft is unclear (Tooltips needed.) IT should open up a browser to find saved draft not out typing the path above.
- source manager (sources) window is out-of standard and risk accidental overwrites through confusion. Reevaluate and align with the existing standard in other editors.
- manifest settings and startup settings should be out of that source manager window and be next to the sources button instead
- buttons that open other editors should be removed. There are no reasonable use case due to too much gui clutter.
- Unexplainable by-creation of breaker and generator when placing node such as diesel? extra created nodes cannot be moved around.

## Remediation implemented (2); retest pending

The second-run observations above remain unchanged. The following remedies are now implemented with static/mock regression coverage:

- The Sources window follows the source-manager workflow: searchable packed manifests have an explicit **Load selected packed manifest** action, local drafts use a bounded `DFileBrowser` with an explicit load action and tooltips, export paths are visually separate, and existing draft files require overwrite confirmation. Manifest and startup settings moved beside Sources in the main toolbar, and buttons that launched unrelated editors were removed.
- The node context menu now uses Garry's Mod's actual `DMenu:AddSubMenu` return contract, so Start connection categories and their supported ports open correctly.
- Orthogonal links terminate at the reached node border so direction arrows remain visible on every side. Any visible route segment can be clicked to select and highlight the link. A selected link exposes one draggable turn anchor; its editor-only position persists and follows movement of either connected node.
- Generated breakers and generators identify their owning component, explain how their runtime configuration is controlled, and can be positioned independently. Their positions are stored in manifest editor metadata and validated against the generated component set.
- Plant debug serializes `NET reference.hotwell` overflow and other typed endpoint references as stable `component/port` labels.
- Generator synchronization consumes every valid sync command internally. A tripped generator ignores it, an already synchronized generator opens its breaker, and an unsynchronized generator attempts closure. Configured mismatch trips remain active without returning an action rejection to the momentary Control button.

Reload `experiment_rbmk`, then repeat tests 2, 6, 8 and 14–18. Tests 4 and 5 passed in the second run. After the remaining reference tests pass, run pending tests 20–24. Test 19 remains deferred until a multiplayer environment is available. The RBMK debug angle-dependent performance observation remains a future optimization item.

2. Failed. experiment_rbmk/main.json stuck at 'Loading packed manifest experiment_rbmk/main.json ...' possibly stuck or is taking extremely long time to load (>10 mins) Focused diagnose and fix needed. (Corrupted data?) 
- The Two _fixtures could load.

## Remediation implemented (3); focused retest pending

The packed reference data was not corrupted. `experiment_rbmk/plant.json` is about 39 KiB and is transferred inside a JSON `sourceText` string. The inspection client requested the intended 1 MiB envelope-string allowance, but the strict JSON tokenizer still applied its default string threshold before the later tree check. Smaller fixture packs remained below that threshold, while the reference transfer was rejected silently and left the editor waiting.

- Strict JSON validation now applies the caller-provided string limit during tokenization as well as tree validation. Normal source decoding retains the existing 4,096-byte field-string limit; only the validated inspection envelope permits its bounded source-text string.
- Client transfer-decode failures now print a diagnostic and clear the editor's pending load instead of leaving `Loading packed manifest ...` displayed indefinitely.
- The separated server/client transfer regression now carries a source envelope larger than the old tokenizer threshold and verifies that it arrives without truncation.

Reload `experiment_rbmk` and repeat test 2. If it passes, continue the pending retests 6, 8 and 14–18.

2. Loaded, Inaccurate representation of actually built plant. Invalid namespace or tick interval error shows up. No electrical, reference connection lines is shown (No connection?)
```
local structural preview:startup.intervals.LUASQUARE_COOLINGTOWER: invalid namespace or tick interval
local structural preview:startup.intervals.LUASQUARE_HEATEXCHANGER: invalid namespace or tick interval
local structural preview:startup.intervals.LUASQUARE_STEAMSEPARATOR: invalid namespace or tick interval
local structural preview:startup.intervals.LUASQUARE_DIESELGENERATOR: invalid namespace or tick interval
local structural preview:startup.intervals.LUASQUARE_DEAERATOR: invalid namespace or tick interval
local structural preview:startup.intervals.LUASQUARE_CONDENSER: invalid namespace or tick interval
local structural preview:startup.intervals.LUASQUARE_POWERGRID: invalid namespace or tick interval
local structural preview:startup.intervals.LUASQUARE_TURBINE: invalid namespace or tick interval
local structural preview:startup.intervals.LUASQUARE_PUMP: invalid namespace or tick interval
local structural preview:startup.intervals.LUASQUARE_VALVE: invalid namespace or tick interval
local structural preview:startup.intervals.LUASQUARE_POWERGENERATOR: invalid namespace or tick interval

```
6. Passed
8. Passed
14. Editor next improvement.
- Labelling function appears to be missing. The top most text field which I assume is label, isn't used anywhere and isn't utilized. Label should be used in place of IDs whenever possible when showing information in editor. (such as on header name of a node, connection link target > target)
- The following shouldn't have place on the node graph (No flow to display) and should be instead moved toward other dedicated subwindow for management and creation:
    - Source bindings
    - Instruments (SEG7/GAUGES)
- Many properties editing in inspector are extremely cluttering in the current state, try to adopt the use of DProperties in many components (espicially turbine, it should have subwindow for settings like RBMK does).
- The 'tags' and 'targets' are a very strange UI. Suggest redesigning it into a Table with Add/Delete entries.
    - What is tags used here?
- S/L Lines are moveable now but it lacks drag preview, making it harder to see the snap. The anchor square does move but they often insignificant since cursor can already move the line. in some cases, SOME lines are invisible to cursor and not moveable or selectable.
- More for nodes and connection lines, Node/Lines that overlap on top of each other(vertically or horizontally) should have hitstack so their selection can be alternated.
- We have to remove 'Presentation' placeholders. It is not used anymore and is interfering the current development. Which also involves redesigning/creating new 3D2D (complex buildmode) for experiment_rbmk. And delete 'column' line in simple buildmode. We are transitioning into more stable state of the development now.
    - Yes, this pass involves creating new 3D2D screens for this.

## Remediation implemented (4); editor/display retest pending

The observations above remain the record of the third acceptance run. The following focused editor and 3D2D changes are implemented with static/mock coverage:

- The inspection catalog now transfers the registered plant startup namespaces to the client compiler. Loading `experiment_rbmk/main.json` no longer reports valid `LUASQUARE_*` plant intervals as unknown, allowing compiled configuration-reference and electrical lines to be built.
- Component `editor.label` is now an explicit editable field and is preferred in node headings, hover details and connection descriptions; stable IDs remain visible as secondary identity.
- Source bindings, machinery, SEG7/gauges, shared control targets and non-flow integrations moved out of the plant-flow canvas into the searchable **Bindings** management window, which supports creation, selection/configuration and deletion.
- Graph reference routing now requires both endpoints to be visible. References owned by or targeting a hidden management node are omitted instead of passing a missing position into the per-frame route builder.
- Component configuration moved into a resizable typed `DProperties` window. Reference/enum fields retain searchable selectors, while string arrays such as Source `targets` and `tags` use an add/delete table. Tags are optional mapper metadata and do not affect entity resolution.
- Authored link anchors now update the complete orthogonal route during dragging. Repeated clicks at an overlapping node/link location cycle its hit stack instead of permanently selecting only the top item.
- The generic `telemetry.panel` component and the three reference panel placeholders were removed. Feedwater, cooling-loop and electrical displays are new complex-build dashboards bound directly to instance-qualified component telemetry. RPV, turbine, deaerator and graph sources likewise read their owning component providers directly. The retained `reference.presentation` integration now publishes annunciator alarm data only.
- Simple-build 3D2D sources now reject the obsolete `columns` line, and the editor no longer offers it in simple mode. Complex `LinePanel` elements are the supported dashboard layout.

Reload `experiment_rbmk`, repeat test 2 for graph accuracy, repeat test 12 for every changed physical display, then repeat test 14. If those pass, continue tests 15–18.

2. Passed
12. Passed
14. Some changes wanted.
- 'Binding and instruments' current subwindow direction proven to be complicated to use. (Too many windows involved in the process of adding more binding. And the subwindow hover-focusing makes it worse for third window struggling to be focused.)
    - Suggested solution, Binding and instruments becomes a toggle to occupy and change the graph viewport into table with add/delete binding (hides graph viewport and the operation remains in main window). As for add/delete binding, it will be subwindow. Clicking on one of table entry directs the inspector there.
- S/L Lines that is Fluid/Thermal is only selectable and adjustable, Electrical and Reference does not.
- S/L lines' arrow head no longer draw in expected orientation at destination node's border causing them to be disappear again when line arrive from anywhere that's not left border.
- Initial dragging of S/L lines does not preview. Later dragging previews as intended.
- The DProperties grid with sliders, when a slider is adjusted, very large amount of lag is observed. Causing heavy stall. Suggested an Apply button for the component setting subwindow.
- DProperties slider is also defaulted to 0.0-1.0, set these to appropriate value for each of the properties you're seeing.
- Documenting properties field with settooltip is suggested if possible.

## Remediation implemented (5); focused editor retest pending

The fourth-run observations above remain the acceptance record. The requested editor changes are now implemented with compiler and native-VGUI mock coverage:

- **Bindings** is now an in-window workspace toggle. It replaces the graph viewport with the searchable management table, and selecting a row updates the existing inspector. Adding opens the catalog window; deleting uses a confirmation dialog. The former hover-focused management window was removed.
- Every visible route category is hit-testable. Authored fluid/electrical links and generated electrical/reference configuration lines can be selected, previewed while dragging, and assigned a persistent turn anchor. Configuration-reference anchors use validated `manifest.editor.referenceBends` metadata and follow connected node movement.
- Route arrows derive their direction from the exact destination border rather than the final route segment, including zero-length terminal turns, so left/right/top/bottom arrivals render consistently.
- A route with no saved anchor now receives its calculated anchor before drag preview, fixing the missing preview on the first adjustment.
- `DProperties` changes are staged locally and compile only when **Apply changes** is pressed, avoiding a full-document rebuild for every slider event. Numeric properties receive schema-defined ranges (with a bounded value-derived fallback), and tooltips expose available description, type, unit, range and default information.

Reload `experiment_rbmk` and repeat test 14, focusing on the Bindings/Graph toggle, one route from each visible link category, arrows entering all node sides, first-drag preview, and turbine/component property editing. If it passes, continue tests 15–18.

14. Passed, more improvement is for next pass.
15. Passed
16. Passed but exposes a problem with RBMK Core node having setting in setting and not being used with DProperties, 2 different "Edit cells" one being the hellish array and one being the visual grid. Visual grid is supposed to be the only one but it does not take effect.
17. Passed
18. Passed

Acceptance passed.

Due to high workload, Multi-Core test will be deferred since it is not possible with the current capability of the graph editor and not having target debug draw. It will remains untested until necessary in the future.
Warning
