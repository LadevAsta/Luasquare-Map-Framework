# Luasquare JSON timelines

The timeline engine schedules declarative `luasquare.timeline/v1` sources while Lua owns every operation that can affect the server or map. JSON cannot run Lua, console commands, target arbitrary Source entities, or issue raw EntFire inputs.

## Source locations

Store reusable component choreography under:

```text
data_static/luasquare_timeline/_components/<component_type>/<timeline_id>.json
```

Store map procedures under:

```text
data_static/luasquare_timeline/<map>/<timeline_id>.json
```

The in-game editor writes canonical drafts under `garrysmod/data/luasquare_timeline/drafts/`, mirroring the packed path. Drafts are not loaded automatically; copy finished sources into `data_static` before packing, or pass a draft path explicitly from a development bootstrap.

Each file contains one timeline. Timing is in seconds. Tracks execute in declaration order, and clips at the same time execute in track order followed by clip order.

## Component registration

Register trusted capabilities on the server before binding a source:

```lua
include('luasquare_module/timeline/engine.lua')

LUASQUARE_TIMELINE.RegisterComponent('demo_machine', {
    type = 'example.machine',
    label = 'Demo Machine',
    actions = {
        enabled = {
            kind = 'duration',
            label = 'Enabled for duration',
            seekPolicy = 'apply',
            start = function() return DEMO.Enable() end,
            finish = function() return DEMO.Disable() end,
            cancel = function() return DEMO.Disable() end
        },
        set_speed = {
            kind = 'number',
            label = 'Speed',
            min = 0,
            max = 100,
            decimals = 1,
            unit = '%',
            seekPolicy = 'apply',
            set = function(_, _, value) return DEMO.SetSpeed(value) end
        }
    },
    safeReset = function()
        DEMO.Disable()
        return true
    end
})

LUASQUARE_TIMELINE.BindTimeline(
    'demo_machine',
    'startup',
    'data_static/luasquare_timeline/_components/example.machine/startup.json'
)

LUASQUARE_TIMELINE.Start('demo_machine', 'startup', {actor = player})
```

`marker` actions expose `execute`. `duration` actions expose `start`, `finish`, and optional `cancel`. `number` actions expose `set` and are sampled once per timeline tick. Numeric source values are clamped and rounded from capability metadata.

Components may expose child IDs for editor hierarchy and relative targets. Dynamic collections use `RegisterTargetResolver`. Timeline-level validation, entry, cancellation, and completion logic uses named `RegisterLifecycleHandler` callbacks.

Direct Source entities must be exposed through `RegisterEntityEndpoint` with an explicit action-to-input allowlist. Never place targetnames or arbitrary inputs in timeline JSON.

## JSON example

```json
{
  "schema": "luasquare.timeline/v1",
  "id": "example_startup",
  "label": "Example Startup",
  "channel": "operation",
  "conflictPolicy": "replace",
  "duration": 5,
  "tracks": [
    {
      "id": "machine",
      "label": "Machine",
      "target": "self",
      "clips": [
        {
          "id": "run",
          "kind": "duration",
          "at": 0,
          "duration": 5,
          "action": "enabled",
          "required": true
        },
        {
          "id": "speed",
          "kind": "number",
          "at": 0,
          "duration": 3,
          "action": "set_speed",
          "from": 0,
          "to": 60,
          "curve": "smoothstep"
        }
      ]
    }
  ],
  "editor": {
    "referenceAudio": {
      "path": "sound/music/example.ogg",
      "timelineStartSeconds": 0,
      "volume": 0.5
    }
  }
}
```

Clip kinds are `marker`, `duration`, `number`, and `timeline`. Supported numeric curves are `linear`, `smoothstep`, `ease_in`, `ease_out`, and `ease_in_out`.

## Editor and preview

Open `Spawn Menu -> Options -> Luasquare -> Timeline Editor`. The editor is intentionally restricted to single-player.

Packed sources open read-only. Save one as a draft before editing. The component browser is populated from the server's sanitized component catalog. Drag a component onto the timeline to create a track and clip, then select the clip to choose an exposed action and its typed parameters.

Simulation preview changes only the editor playhead. Live preview requires confirmation, rejects production channel conflicts, and invokes real component actions. Every live-previewable component must provide `safeReset`; preview stop, failure, editor closure, cleanup, or completion invokes that reset. This is a safe-state reset, not an exact restoration of prior entity state.

Reference audio is client-side editor metadata. It uses a seekable `IGModAudioChannel`, is removed from live-preview uploads, and never becomes a runtime sound action. Audio bytes are never networked.
