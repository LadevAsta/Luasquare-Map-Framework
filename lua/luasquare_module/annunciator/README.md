# Luasquare source-driven annunciators

`LUASQUARE_ANNUNCIATOR` is the server-authoritative alarm lifecycle and presentation engine for `luasquare.annunciator/v1`. JSON packs own alarm declarations; Lua providers expose bounded telemetry. Sources cannot call Lua, Source inputs, console commands, URLs, or raw sound paths.

## Loading and source layout

Include Timeline and Audio before the annunciator when using every integration:

```lua
include('luasquare_module/timeline/engine.lua')
include('luasquare_module/audio/engine.lua')
include('luasquare_module/annunciator/engine.lua')
```

Packed sources are read from:

```text
data_static/luasquare/annunciator/<map>/*.json
```

The editor writes canonical drafts to:

```text
garrysmod/data/luasquare/annunciator/drafts/<map>/*.json
```

Packed files are read-only in the editor. Copy one into an editable session, validate it, then export a draft for manual promotion into a map addon's `data_static` tree.

## Providers and conditions

Register every referenced provider before `Start`:

```lua
LUASQUARE_ANNUNCIATOR.RegisterDataProvider('plant.alarms', function()
    return {
        pressure = PLANT.Pressure or 0,
        pressureLimit = PLANT.PressureLimit or 50,
        online = PLANT.Online and true or false,
        messages = {pressure = string.format('%.1f bar', PLANT.Pressure or 0)}
    }
end, {
    interval = 0.2,
    label = 'Plant alarm telemetry',
    fields = {
        {path = 'pressure', type = 'number', label = 'Pressure'},
        {path = 'pressureLimit', type = 'number', label = 'Pressure limit'},
        {path = 'online', type = 'boolean', label = 'Online'}
    }
})
```

A leaf condition binds `provider` and dotted `path`, then uses `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, or `truthy`. The comparison `value` may be a primitive or another provider/path binding. Conditions compose with `all`, `any`, and `not`. Missing paths and failed providers retain the last valid alarm state; provider failures are rate-limited in diagnostics.

If `clearCondition` is absent, an active alarm resolves when its activation condition becomes false. A separate clear condition supports hysteresis:

```json
{
  "condition": {"provider": "plant.alarms", "path": "pressure", "op": "gt",
    "value": {"provider": "plant.alarms", "path": "pressureLimit"}},
  "clearCondition": {"provider": "plant.alarms", "path": "pressure", "op": "lt", "value": 45}
}
```

## Pack shape

A pack contains any number of groups and alarms:

```json
{
  "schema": "luasquare.annunciator/v1",
  "kind": "annunciator_pack",
  "id": "plant_annunciators",
  "groups": {
    "reactor": {
      "label": "Reactor",
      "muteSeconds": 60,
      "soundOrigin": {"targetname": "ANN_REACTOR_AUDIO"},
      "defaults": {"reAlarmSeconds": 180}
    }
  },
  "alarms": {
    "pressure_high": {
      "label": "PRESSURE HIGH",
      "group": "reactor",
      "tier": 3,
      "condition": {"provider": "plant.alarms", "path": "pressure", "op": "gt", "value": 50},
      "message": {"provider": "plant.alarms", "path": "messages.pressure"},
      "indicator": {
        "targetnames": ["ANN_REACTOR_pressure_high"],
        "expectedModel": "models/luasquare/ann/annunciator.mdl",
        "skins": {"off": 0, "fast_flash": 1, "on": 2, "slow_flash": 3}
      },
      "audio": {
        "sound": "plant.pressure_alarm",
        "mode": "repeat",
        "repeatSeconds": 8,
        "ackSilences": true
      },
      "reAlarmSeconds": 180
    }
  }
}
```

Indicator targetnames are explicit. The editor can discover `prop_dynamic` names matching `ANN_<UPPERCASE_GROUP>_<alarm>` and copy them into the list; the runtime does not create hidden convention bindings. All linked props receive the same skin, and the first valid prop is the local emitter. A group fallback may use a targetname or `[x, y, z]` position.

Audio references only registered `LUASQUARE_AUDIO` sound IDs. `once` starts once per activation/test opportunity, `loop` remains owned until silenced, and `repeat` starts one-shot instances at `repeatSeconds`. Missing sounds and props produce warnings without disabling visual alarm state.

## Tiers and lifecycle

- Tier 1 Status is steady white while its condition is true. It has no audio and ignores ACK, RESET, and TEST.
- Tier 2 Warning defaults to yellow local presentation.
- Tier 3 Critical defaults to red local presentation.
- Tier 4 Siren defaults to purple/red global presentation. It ignores MUTE and TEST; ACK changes its visual acknowledgement but never silences it.

Warning/Critical/Siren alarms fast-flash when new, become steady after ACK, slow-flash after their clear condition, and return off after RESET. TEST applies only to Warning/Critical alarms, clears their applicable timed mute, and remains latched until ACK. MUTE may be global or group-scoped; eligible active alarms resume when it expires. `reAlarmSeconds` defaults to 180, and zero disables re-alarm.

## Runtime APIs

Queries:

- `GetAlarm(id)`, `GetGroup(id)`, `GetState(id)`, `GetSnapshot(scope)`, `GetCounts(scope)`
- `GetDataProvider(id)`, `GetDataProviders()`, `GetProviderValue(id)`

Controls:

- `Acknowledge(scope)`, `Reset(scope)`
- `Mute(duration)` for the legacy global call or `Mute(group, duration)`
- `Unmute(scope)`, `Test(scope)`, and the preserved `TestAll()`
- `Start()`, `Stop()`, `ReloadSources()`

No-argument `Acknowledge()`, `Reset()`, `Mute()`, and `TestAll()` remain suitable for existing VMF `lua_run` calls. Alarm and group transitions publish `LuasquareAnnunciatorAlarmChanged` and `LuasquareAnnunciatorGroupChanged`.

3D2D actions are `annunciator.acknowledge`, `.reset`, `.mute`, `.unmute`, and `.test`; their action payload accepts `scope` and, for mute, `duration`. Timeline marker actions with the same names live on `annunciator.controls`.

Clients receive bounded snapshots/deltas for late join and presentation. The 3D2D `alarm` field reads this client state directly. The userinfo convar `luasquare_audio_annunciator_volume` scales alarms, sirens, repeats, and TEST playback per recipient.

The editor is available at **Options → Luasquare → Editors → Annunciator Editor** to authorized single-player hosts/admins. Its separate Sources window searches packed sources and drafts and owns load/new/save/copy operations. The alarm inspector uses a searchable registered-sound browser, a color picker, a pitch override, and a collapsed advanced section for explicit targetnames and skin-map JSON. Convention prop discovery remains explicit: selecting a detected prop writes its targetname/model into the draft.

Client-only lifecycle simulation can play and stop the selected registered sound according to its once/loop/repeat policy, pitch, ACK behavior, mute state, tier restrictions, and the annunciator volume convar. Closing the editor stops its preview timer/channel. The model preview measures the selected model bounds and aims the camera through its thinnest axis so the broad annunciator face is visible. Editor information and validation are written to the console and the editor status/diagnostics areas rather than notification popups.
