# JSON-driven Control Layer

`LUASQUARE_CONTROL` is shared map infrastructure. The server owns physical movement,
component dispatch, availability, requests, keypad buffers/targets, and operator history.
Map Lua registers trusted actions/predicates; map-owned JSON declares control instances.
The editor and timeline adapters never execute source Lua.

For [manifest-owned plants](../map/README.md), component adapters register instance-qualified actions/predicates and the loader initializes selected controls after all owners exist. `experiment_controls.lua` is retired. Physical control IDs and the v1 schema are unchanged; reference action/provider IDs are now `reference.*`. Paired-pump targets use `control.target_group`. DFR migration remains deferred. Run `node tools/check_control.js --map=experiment_rbmk` for the current reference VMF/BSP audit; the unfiltered audit also checks DFR and currently fails its `containment_lower` binding. The [archived migration acceptance](../map/archive/ACCEPTANCE.md) distinguishes static results from the completed in-game run.

Packed sources: `data_static/luasquare/control/<map>/*.json`, loaded through `GAME`.
Editor drafts: `garrysmod/data/luasquare/control/drafts/<map>/<pack>.json`, never loaded automatically.
Schema: `luasquare.control/v1`. Limits: 1,024 controls per map, 512 KiB per pack,
16 nesting levels, 128 packs, 64 predicates/owner locks per control, and 500 history entries.
The control limit includes generated physical keypad subcomponents.
Control JSON readers preserve string object keys (`util.JSONToTable` with
`ignoreConversions = true`), including keypad digit slots, in packed sources,
drafts and network catalogs. Parser depth/breadth limits remain enabled.
Editor diagnostics and live state use wrapped, scrollable text viewports; the
display, timeline, annunciator and audio editors share these diagnostic widgets.
Right-click diagnostic/live-state text and choose **Copy text** to copy its entire
contents. Momentary return acknowledgement allows the engine's `m_flWait` plus
the five-second movement timeout, including inherited waits omitted by GetKeyValues.
All packs and physical bindings validate before activation. Diagnostics identify the
source, control/field, and error. Registered IDs and parameter types must match exactly.

## Registration and startup

Include cleanup first, then the display/timeline engines used by the map, then
`luasquare_module/control/engine.lua`. Register actions, predicates, and any referenced
SEG7 displays before `LUASQUARE_CONTROL.Start(game.GetMap())`. Start displays/simulation
after control activation. The client autorun loads shared compiler/state/editor code;
the server entry point sends every shared/client file with `AddCSLuaFile`.

```lua
LUASQUARE_CONTROL.RegisterAction('plant.pump_speed', {
    label = 'SPEED',
    parameters = {name = {type = 'string'}, level = {type = 'integer', min = 1, max = 4}},
    getValue = function(params) return PLANT.GetPump(params.name).speedLevel end,
    callback = function(actor, params, control, value, context)
        return PLANT.SetPumpSpeed(params.name, params.level)
    end
})
LUASQUARE_CONTROL.RegisterPredicate('plant.ready', {
    label = 'Plant ready', parameters = {},
    callback = function(actor, params, control)
        return PLANT.Ready, 'plant unavailable'
    end
})
```

Parameter metadata is an object keyed by parameter name. Supported types: `number`,
`integer`, `boolean`, `string`; numeric `min`/`max`, string `maxLength`/`choices`,
`default`, and `optional` are supported. Choices are a set such as `{open = true}`.
Callbacks returning `false, reason` produce a terminal expected rejection. The request
fails and a physical toggle is restored, but the control does not acquire a persistent
fault or lock. Lua errors, unavailable predicates, invalid physical input,
acknowledgement timeouts and failed recovery are faults. `nil` remains compatible with
trusted methods that return no result. Predicates return `false, reason` to block.
Actions may declare `severity = 'critical'` for red accepted-action console logs,
`diagnostic = true` for key diagnostics, and `getValue(params, control)` for measured
old/new operator values. A keypad submit action can additionally declare
`initialize(actor, params, control, initialValue, context)` to reconstruct its owned
target on start/reload. Initializers must preserve plant inventories; rod selection
submission intentionally has no initializer.

Trusted actions may explicitly opt into `allowRequestParams = true` for typed
`context.params` overrides; merged parameters revalidate at execution. Editor and
display clients cannot supply these overrides. DFR developer tuning commands use
packed virtual controls, typed bounded arguments, and an admin predicate. Lifecycle,
read-only diagnostics, and the command that requests an existing operator control
remain their own debug entry points.

## Source example

```json
{
  "schema": "luasquare.control/v1",
  "id": "operator_controls",
  "controls": [{
    "id": "pump_speed_2", "label": "Coolant Pump A", "kind": "momentary",
    "target": "CTRLI_pump_speed_2", "class": "func_button", "cooldown": 0.25,
    "predicates": [{"id": "plant.ready", "params": {}}],
    "actions": {"press": {"id": "plant.pump_speed", "params": {"name": "pump_a", "level": 2}}}
  }]
}
```

Kinds are `momentary`, `toggle`, and `keypad`. Virtual controls omit `target`/`class`.
Toggle actions are `in` and `out`; an actionless endpoint only updates accepted
position. Momentary actions are `press`; endpoint reports acknowledge movement/return.
`initialPosition` optionally declares `in`/`out`. Physical kind must match Hammer's
toggle flag. `lockIndicator` optionally names an `env_sprite`; the runtime only uses
its fixed `ShowSprite`/`HideSprite` inputs. IDs are stable lowercase strings;
physical targetnames require exact uppercase `CTRLI_`, followed by a safe suffix.

The `experiment_rbmk` VMF source now uses descriptive `CTRLI_<category>_<name>`
targets and `CTRLI_KPD_<key>_<keypad>` keys for `aprctrl`, `fwlevelctrl`,
`hotwellctrl`, and `rodctrl`, matching its packed control source. Its physical
controls report all three outputs directly to `RBMK_SYSTEM` using the generic
`CALLER` wiring below. Safety covers use registered position predicates instead
of competing Hammer Lock/Unlock outputs. Numeric brush-derived control IDs have
been replaced with descriptive target suffixes, such as
`pump_speed_feedwater_pump_a_level_2` and `safety_tg1_sync`; safety predicate
references use the new IDs. Existing drafts/timeline markers referencing old
numeric IDs must be updated manually; drafts are not automatically rewritten. The BSP
must be rebuilt manually from this VMF before testing these source bindings.
The RBMK run-on-spawn bootstrap defers initialization until the next tick so
brush buttons finish spawning and initialize their movement endpoints before
Control Layer reads their state or performs reconciliation. Cleanup cancels
the pending namespaced bootstrap timer along with other framework activity.

Keypads add integer `maxDigits` (1–9), `maxValue`, `initialValue`, boolean
`clearOnSubmit`, optional registered SEG7 `display`, a `submit` action, and `keys`.
Each keypad is one authored virtual member. Its `keys` object maps string tokens
`0`–`9`, `s` (submit), `b` (backspace), and `c` (clear) to physical targetnames.
Digits and submit are mandatory; omit optional backspace/clear when absent.
The compiler creates owned `func_button` press controls and their trusted actions.
Authors do not declare child members, parent references or digit actions.
Parent availability locks all keys; explicit parent locks synchronize them immediately.
Empty buffers submit zero, values clamp to the maximum, and failed submissions keep
both the buffer and accepted target. Only successful submission is an operator log;
key presses are diagnostics. SEG7 updates immediately.

```json
{
  "id": "name", "label": "Target", "kind": "keypad",
  "maxDigits": 4, "maxValue": 9999, "initialValue": 0,
  "clearOnSubmit": true,
  "actions": {"submit": {"id": "plant.target", "params": {}}},
  "keys": {
    "0": "CTRLI_KPD_0_name", "1": "CTRLI_KPD_1_name",
    "2": "CTRLI_KPD_2_name", "3": "CTRLI_KPD_3_name",
    "4": "CTRLI_KPD_4_name", "5": "CTRLI_KPD_5_name",
    "6": "CTRLI_KPD_6_name", "7": "CTRLI_KPD_7_name",
    "8": "CTRLI_KPD_8_name", "9": "CTRLI_KPD_9_name",
    "s": "CTRLI_KPD_s_name"
  }
}
```

Add a virtual control, choose Keypad, set its ID, limits, display and submit action,
then choose a discovered keypad to fill its key fields together or browse each slot.
The slot browser only shows matching `CTRLI_KPD_<token>_<name>` buttons; the ordinary
browser excludes all `CTRLI_KPD_` entities. Manual text overrides allow existing
safe `CTRLI_` targetnames without renaming map entities. KPD-prefixed overrides must
match the slot token. Full targetnames are preserved, and duplicate bindings reject.
All key buttons use the same three ID-free Hammer reports shown below.
Runtime snapshots show one keypad with nested `keys` state. Display/timeline catalogs
expose its integer submission, not generated key components. ResetFault on the keypad
checks every key's binding and physical/accepted position before clearing key faults;
other owner locks remain. Generated IDs are `<keypad>.key.<token>` and are internal.
Earlier flat-key keypad sources must be grouped into `keys`; bundled RBMK sources
are migrated without changing their physical targetnames. Old per-key explicit-ID
reports need the reusable ID-free wiring during the user's manual Hammer migration.

`control.position` takes `control` and `position` (`in`/`out`). Physical position
must match; toggle controls also require the accepted component position to match.
This replaces competing native safety-cover Lock/Unlock outputs while preserving
the cover's original momentary movement and automatic return delay.

## Hammer wiring and request semantics

Each registered physical button reports all three outputs to the map's `lua_run`:

```text
OnPressed -> RunPassedCode: LUASQUARE_CONTROL.ReportOutput('OnPressed',CALLER,ACTIVATOR)
OnIn      -> RunPassedCode: LUASQUARE_CONTROL.ReportOutput('OnIn',CALLER,ACTIVATOR)
OnOut     -> RunPassedCode: LUASQUARE_CONTROL.ReportOutput('OnOut',CALLER,ACTIVATOR)
```

Use zero output delay and unlimited firing. Remove old operator Lua and competing
native Lock/Unlock outputs. Keep unrelated visual outputs and machinery/path callbacks.

`CALLER` is the originating entity; its `GetName()` returns the Hammer targetname.
The runtime resolves its existing registered binding, then validates entity identity,
full targetname, class, event and physical state. These same parameters can be copied
to every physical control. The older four-argument form with an explicit ID remains
supported for existing wiring. Reports must come directly from the button's output,
since an intermediate relay changes the caller.
Reports must identify the actual bound entity, exact target/class, event and endpoint.
The namespaced `AcceptInput`/`PlayerUse` guards protect registered controls only.
Synchronous internal entity inputs preserve activator identity and permit owned motion.

`Request(id, operation, context)` returns `requestId, status`; inspect `GetRequest(id)`
or supply trusted `context.onComplete(request)` for asynchronous terminal results.
Statuses: `pending`, `dispatched`, `completed`, `expired`, `superseded`, `cancelled`,
`failed`. Queue acceptance does not mean component completion. Context identifies
an actor entity/player or a trusted automation name, plus a stable lowercase `owner`.
Clients supply neither blame identity nor lock owner; the server constructs both.

Operations: `press`, `toggle`, `pressIn`, `pressOut`, `pressLock`, `pressInLock`,
`pressOutLock`, `submitValue`. Momentary controls accept Press/PressLock only;
keypads accept submitValue only, optionally with `context.value` as a nonnegative
integer. Incompatible operations and fractional values reject.

Combined operations first dispatch the corresponding ordinary press, respecting
**every existing owner lock, including their own**, then lock for the requesting
owner on the next server tick. They do not wait for an endpoint/component result.
The accepted movement remains eligible through its own new lock; other/new owner
locks and changed predicates still reject its component action. Already-satisfied
In/Out requests repeat no action but still schedule the next-tick lock. Input failure
does not schedule a lock; post-dispatch action/movement failure retains an applied lock.

Each control retains one newest pending request; a newer pending request supersedes
the old one while dispatched movement continues. Pending requests expire two seconds
after submission, including time spent behind movement/cooldown. Unlock dispatches
immediately, sending engine Unlock before Press. Endpoint acknowledgement is limited
to five seconds. Momentary return timeout additionally allows Hammer's declared wait.
Predicates refresh every 0.05 seconds; explicit owner locks synchronize immediately.

`Lock(id, owner, reason)`, `Unlock(id, owner)`, `UnlockOwner(owner)`,
`CancelRequest(requestId)`, and `CancelOwner(owner)` manage independent ownership.
Cancellation removes pending requests; accepted gameplay movement is not undone.
UnlockOwner also removes that owner's scheduled next-tick locks. `GetSnapshot()`
separates actual/accepted positions, pending/active requests, faults, locks, and keypad
state. `GetHistory()` returns bounded structured server `HH:MM:SS` logs with actor,
control/action labels, old/new values, severity, outcome and diagnostic reasons.

Expected action rejections restore the last accepted physical position with Control
Layer component dispatch suppressed; retained Hammer-native outputs still run. They
do not set `control.fault`, so a momentary sync button or keypad remains usable after
the rejected request completes. A hardware/validation fault blocks new interaction.
`ResetFault(id)` requires a valid binding and matching actual/
accepted positions and preserves every owner lock. Recovery is internal reconciliation,
never a public bypass operation.

Engine acceptance remains important: Valve's [Source SDK button implementation](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/buttons.cpp)
checks `m_bLocked` in `TriggerAndWait` before publishing `OnIn`. A GMod branch with
that behavior can suppress the acknowledgement when a next-tick lock lands before
the endpoint. This runtime obeys the requested lock tick and faults on timeout;
it does not silently delay the lock or invent a Hammer report. Verify this explicitly
in the rebuilt GMod maps before accepting the combined-operation workflow.

## Display, timeline, and editor

Each control registers `control.<id>` as a display action and timeline component.
Display payloads may specify `operation`/integer `value`; normal server display
range, plane, LOS, visibility, page and authorization checks remain in force.
Presentation-only display page navigation remains in the display engine.

Timeline actions use lowercase operation IDs (`pressinlock`, `pressoutlock`, etc.).
Keypad `submitvalue` has an integer-valued numeric parameter and is a marker,
never interpolation. Runs wait for outstanding requests and evaluate actual completion
against marker success thresholds. Required failure/expiry fails the run; optional
failure logs diagnostics. Cancellation removes pending requests. Control markers
reject nonzero seek and timeline live preview, including optional clips. Timeline
lock owners are `run.controlOwner`; release them explicitly through UnlockOwner
when the owning orchestration no longer needs them.

Open **Options → Luasquare → Editors → Control Layer Editor**. Windows are dark,
draggable/resizable. The native top-right maximize icon toggles fullscreen and
restores the previous window size and position; native title-bar layout is preserved.
The main status updater preserves native `DFrame:Think`, including dragging and
bottom-right resizing. Hovering a subwindow brings it forward and focuses it,
including when the main frame covers it; mouse dragging and open menus/modal
dialogs do not trigger a hover focus switch.
All windows use the shared editor palette, including list text, headers and scrollbars.
The live-test column scrolls when resized; native frame layout receives its dimensions.
The separate Sources window creates new drafts, loads packed sources read-only,
and saves canonical local drafts. Select a file, then use **Load selected** or
**Editable copy**; selecting a row never replaces the current source. File actions
share a bottom toolbar with **New pack**, **Save draft** and **Refresh**.
Cooldown uses a bounded decimal spinner (0..60 seconds). Component actions use
an event/action list with **Add**/**Delete** and the selected row's event, registered
action and typed parameters below it. Each supported event has at most one action.
Closing with unsaved changes requires confirmation, including after Undo/Redo.
Creating a new draft confirms before discarding
unsaved edits. Use Save
Draft before modifying a packed source. Inspectors provide typed action/predicate
parameters, searchable categorized catalogs, explicit physical kind/action discovery,
CTRLI suffix collision diagnostics, undo/redo, and copyable Hammer wiring.
Discovery reads live server `func_button`/`func_rot_button` targetnames with exact
uppercase `CTRLI_`. Authorized discovery and draft authoring remain available if
packed activation fails, including during partial manual migration. The discovery
window refreshes when its server catalog arrives; activation diagnostics stay visible.
Live tests still require successful packed activation. Hammer-only names are not
visible to the running map until the user's manual compile and map reload.
The inspector uses dropdowns for Press/Toggle/Keypad, physical class, In/Out,
Yes/No, registered parameter choices, and bounded integer ranges of up to 21 values.
Press is the human-facing label for the existing JSON `momentary` kind. The physical
CTRLI chooser browses discovered buttons and fills both target and class; manual
target text remains available as a fallback. Dropdown menus use the shared dark theme.
Physical browser categories are presentation-only: `CTRLI_pumps_speed_2` appears
under `pumps`, retaining the full targetname and proposed ID `pumps_speed_2`.
Names without a category/rest separator appear under `Uncategorized`; no category
field is added to JSON or runtime bindings.

**Simulate draft locally** models values, movement acknowledgements, queue expiry
and next-tick locks without entities/networking/action callbacks. Registered predicates
are simulated as available; this is authoring feedback, not gameplay validation.
The clearly labeled LIVE controls are explicit single-player/admin packed-source tests.
They show actual/accepted positions, unavailable reasons, locks, requests and keypad
values, and support requests, editor-owned locks, numeric submission and fault reset.
Closing/disconnecting cancels pending editor requests, scheduled locks and owner locks;
completed gameplay actions remain completed. Diagnostics appear in-window and console.
Editor subscriptions receive bounded revisioned/chunked registrations, individual
sources/history and incremental state; commands are authorized, bounded and rate-limited.
Reopening initializes current state/history for late joiners.

`Stop()` cancels dependent timelines before stopping controls, subscriptions, guards
and adapters while entities still exist. Cleanup stops timelines first and reconstructs
fresh bindings through the run-on-spawn bootstrap. `ReloadSources()` cancels activity
and rebuilds packed initial control/keypad state without resetting plant inventories.
Admin/server console: `luasquare_control_reload`. Editors close on cleanup/reload.

In a disposable test session, use **LIVE arm one action rejection** or admin/server
`luasquare_control_reject_next <packed-id>`, then request that control normally.
The next action-bearing output rejects without calling the component, allowing
physical restoration/fault/reset testing. Closing the editor clears its unused fixture.

## Migration and validation

The prototype `LUASQUARE_CONTROLBINDING`, `LUASQUARE_KEYPAD`, their two module files,
and DFR registry wrappers were removed. Old BSP operator wiring intentionally loses
compatibility. The framework owns experiment_rbmk packed controls and trusted map
actions; DarkEnergyConstruct-Reactor-Map owns gm_darkfusion_v2 controls/bootstrap/VMF.
DFR stays `foundation-0.1`; broader migration and the Logging Panel are separate.

Test-only tools use Node dependencies, not addon/runtime dependencies:

```text
npm install --prefix .control-build/testdeps --no-save --ignore-scripts luaparse fengari
node tools/check_control.js
node tools/check_control.js --sources-only
```

The checker parses changed/new Lua, strictly parses both packed JSON sources, and
executes deterministic Source/GMod API doubles for compiler, request, lock, fault,
keypad, timeline and isolated draft scenarios.
Use `--sources-only` while VMF wiring is being migrated manually; it skips map/BSP
audits. VMF editing, BSP builds and in-game checks are the user's manual workflow.
The offline migration/rebuild scripts are historical implementation tools, not part
of routine validation. They must not be run without an explicit user request.

Real Garry's Mod acceptance is still required:

1. Load both rebuilt maps fresh. Validate bindings; open the Control Editor and compare
   available/locked controls and sprites with player and NPC/LambdaPlayer interactions.
2. LIVE-test PressLock/InLock/OutLock: actual movement first, owner lock next tick,
   one component action. A pre-existing lock, including the same owner's, must block.
   Unlock within two seconds to dispatch; wait longer to expire without a new lock.
   Repeat with pending supersession, cancellation and a moving lever.
3. Observe momentary return and all safety covers' original waits while locked. Check
   endpoint acknowledgements and five-second movement timeout. In a disposable session,
   arm the editor's one-action rejection fixture on a toggle, then press it; confirm restoration/native outputs,
   fault lock, retained owner locks and explicit reset only after position reconciliation.
4. Test every keypad's digits, limit/clamp, empty zero, clear/backspace, failed submit,
   SEG7, direct integer submit, paired pump targets, APR enable/target and rod percentage
   inversion (including no selected rods). Check operator attribution and red trip logs.
5. Exercise display and required/optional/cancelled timeline requests; reject nonzero
   seek/live preview. Verify DFR triple-lever startup/pre-annihilation and RBMK workflows.
6. Repeat cleanup/reload, editor close/disconnect and late join. Confirm no stale bindings,
   pending/scheduled requests, duplicate guards/timers, retained editor locks or stale state.
