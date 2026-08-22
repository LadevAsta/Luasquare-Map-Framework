# Luasquare 3D2D display authoring

The display engine reads declarative JSON from `data_static`, validates it, and builds an in-memory render tree. JSON defines presentation only. Lua remains responsible for authoritative values and actions.

## Loading order

```lua
include('luasquare_module/3d2display/engine.lua')

LUASQUARE_3D2D.RegisterDataProvider('example.reactor', function()
    return {
        state = REACTOR.State,
        power = REACTOR.PowerMW,
        pressure = REACTOR.PressureBar
    }
end, {interval = 0.2})

LUASQUARE_3D2D.RegisterAction('example.scram', {
    label = 'SCRAM reactor',
    cooldown = 1,
    canUse = function(actor) return actor:IsAdmin() end,
    callback = function(actor, display, page, element, context)
        return REACTOR.SCRAM(actor, context.payload)
    end
})

LUASQUARE_3D2D.Start()
```

Providers and actions must be registered before `Start`, because source compilation rejects unknown references. A provider should return JSON-safe primitives/tables and should not mutate display definitions.

## Source locations

```text
data_static/luasquare_3d2display/_themes/<group>.json
data_static/luasquare_3d2display/<map>/<display_id>.json
```

The runtime reads these through the `GAME` search path. This lets a map addon ship its own layouts while depending on the framework addon for Lua. Use one display per file and a stable, unique ID.

Editor drafts are deliberately separate:

```text
garrysmod/data/luasquare_3d2display/drafts/<map>/<display_id>.json
```

Copy approved drafts into the map addon's `data_static` tree before running GMAD.

## Simple example

```json
{
  "schema": "luasquare.3d2display/v1",
  "id": "reactor_status",
  "buildMode": "simple",
  "target": "DISPLAY64x32_reactor_status",
  "scale": 0.1,
  "themeGroup": "plant",
  "title": "REACTOR STATUS",
  "lines": [
    {
      "type": "value",
      "label": "POWER",
      "value": {"provider": "example.reactor", "path": "power", "default": 0},
      "decimals": 1,
      "unit": "MW"
    },
    {
      "type": "bar",
      "label": "PRESSURE",
      "fraction": {"provider": "example.reactor", "path": "pressureFraction"},
      "height": 6
    }
  ]
}
```

Supported line types are `text`, `value`, `columns`, `bar`, `phase`, and `graph`.

`DISPLAY64x32_` describes Hammer-unit surface dimensions. The canvas resolution is derived from scale; at `0.1`, a 64×32 HU surface becomes a 640×320 canvas. `unitWidth`/`unitHeight` override parsed surface dimensions, while `width`/`height` explicitly set canvas dimensions.

## Complex example

```json
{
  "schema": "luasquare.3d2display/v1",
  "id": "reactor_console",
  "buildMode": "complex",
  "target": "DISPLAY64x32_reactor_console",
  "scale": 0.1,
  "themeGroup": "plant",
  "defaultPage": "overview",
  "interaction": {"enabled": true, "distance": 128, "lineOfSight": true},
  "pages": [
    {
      "id": "overview",
      "label": "OVERVIEW",
      "elements": [
        {
          "id": "background_gradient",
          "type": "Material",
          "x": 0, "y": 24, "width": 640, "height": 296, "z": -2,
          "material": "vgui/gradient-r",
          "tint": [20, 80, 100, 140]
        },
        {
          "id": "status",
          "type": "LinePanel",
          "x": 12, "y": 36, "width": 420, "height": 260, "z": 0,
          "title": "STATUS",
          "lines": [
            {"type": "value", "label": "STATE", "value": {"provider": "example.reactor", "path": "state"}}
          ]
        },
        {
          "id": "scram",
          "type": "LinePanel",
          "x": 448, "y": 36, "width": 180, "height": 90, "z": 1,
          "title": "SCRAM",
          "action": "example.scram",
          "actionPayload": {"source": "main_console"},
          "lines": [{"type": "text", "text": "AIM + USE"}]
        }
      ]
    }
  ]
}
```

Complex elements use canvas-space `x`, `y`, `width`, `height`, and integer `z`. Equal `z` values preserve declaration order. Available types:

- `LinePanel`: a positioned line renderer with optional panel material/background.
- `Material`: VMT, synchronized frame sequence, tint, and flash.
- `SolidRectangle`: background or decoration.
- `Annunciator`: named `LUASQUARE_ANNUNCIATOR` alarm state.

Multiple pages produce a built-in tab strip. Set `showPageTabs` to `false` to
hide the strip and remove its raycast hit regions while retaining page changes
through `SetDisplayPage`, cycle helpers, or Hammer buttons. Page state is shared
and server-authoritative.

Per-display, panel, title, and individual-line font scaling is currently
unsupported. Text renders at the registered Garry's Mod font size. Legacy
`fontScale` and `titleFontScale` source fields are accepted but ignored.

## Conditions and variants

A condition is a provider/path binding with `op` and optional `value`:

```json
{
  "provider": "example.reactor",
  "path": "pressure",
  "op": "gte",
  "value": 70
}
```

Operators are `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, and `truthy`. Compose conditions with `all`, `any`, or `not`.

`visibleWhen` controls base visibility. `variants` are checked in source order and only the first matching `set` is applied:

```json
{
  "variants": [
    {
      "when": {"provider": "example.reactor", "path": "trip", "op": "truthy"},
      "set": {"borderColor": "@critical", "flashSeconds": 0.5}
    }
  ]
}
```

Variants may change visibility, material/frames, animation timing, tint, or colors. Material paths are normalized and reject traversal, URLs, absolute paths, and unsupported characters.

## Themes

```json
{
  "schema": "luasquare.3d2display/v1",
  "kind": "theme_pack",
  "group": "plant",
  "defaultTheme": "normal",
  "themes": {
    "normal": {"text": [220,245,255,255], "background": [4,12,16,230], "border": [80,190,220,255], "accent": [70,220,160,255]},
    "emergency": {"text": [255,225,220,255], "background": [28,3,3,240], "border": [255,75,65,255], "accent": [255,120,70,255]}
  }
}
```

Reference tokens as `@text`, `@title`, `@background`, `@panel`, `@border`, `@accent`, `@bar_background`, `@warning`, `@critical`, or `@inactive`. Literal RGBA arrays override theme tokens. `SetThemeGroup(groupId, themeId)` updates every display in the group.

## Materials and animation

- `material`: normal or animated VMT path, without `materials/` or `.vmt`.
- `frames`: ordered material paths.
- `frameSeconds`: time per explicit frame.
- `loop`: set false to stop on the final frame.
- `tint`: theme token or RGBA.
- `flashSeconds`: half-cycle duration.
- `flashMinimum`: dim alpha multiplier.
- `animationEpoch`: optional server epoch; otherwise zero is shared.

Material bytes are never networked. Clients load installed assets and choose frames from synchronized server time.

## Interaction security

Interaction uses crosshair ray-to-plane projection and Use. There is no mouse capture or raw command execution. The server independently resolves the display and checks:

- configured distance and display bounds;
- line of sight;
- current shared page;
- conditional visibility;
- registered action and cooldown;
- optional action `canUse` callback.

Action callbacks receive `(actor, runtimeDisplay, page, element, context)`. `context.payload` is a copy of the source-defined payload, and `context.hit` is the validated canvas position.

## Runtime and editor APIs

Primary server APIs:

- `RegisterDataProvider`, `UnregisterDataProvider`, `RegisterAction`
- `RegisterThemePack`, `SetThemeGroup`
- `CompileSource`, `LoadSource`, `LoadMapSources`, `ReloadSources`
- `BuildDisplay`, `RemoveDisplay`, `SetDisplayPage`, `GetDisplayPage`
- `CycleDisplayPage`, `NextDisplayPage`, `PreviousDisplayPage`, `GetSnapshot`
- `Start`, `Stop`

Page state is shared and server-authoritative. Hammer buttons can call the
cycle helpers from a server-side `lua_run`, for example:

```lua
LUASQUARE_3D2D.PreviousDisplayPage('reactor_console')
LUASQUARE_3D2D.NextDisplayPage('reactor_console')
```

Cycling wraps by default. Pass `false` as the third argument of the next or
previous helper to clamp at the first/last page. Raycast interaction remains
opt-in even when a display contains multiple pages or named actions.

The spawnmenu editor is under `Options -> Luasquare -> 3D2D Display Editor`.
Packed sources open read-only. Save a draft to edit. The editor preserves tree
expansion and synchronizes viewport selection, cycles through overlapping
elements from the highest layer downward, and provides context-menu clipboard,
layer, duplication, and deletion operations. Grid size and sibling snapping are
stored with each source.

The structured inspector includes provider/action selection, color and theme
tokens, VMT browsing and frame ordering, material tint, basic variants, and
interaction controls. Advanced JSON remains available for nested or extension
data. The Preview window temporarily replaces a runtime display while retaining
its physical placement; Restore clears it explicitly.
Disconnect, cleanup, runtime stop, or source reload also restores packed state.

The Themes window opens packed theme packs read-only and saves editable drafts
under `data/luasquare_3d2display/drafts/_themes/`. Its working theme is simulated
only in the editor viewport. Copy the completed JSON into
`data_static/luasquare_3d2display/_themes/` before packing.
