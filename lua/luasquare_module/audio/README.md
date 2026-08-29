# Luasquare source-driven audio

`LUASQUARE_AUDIO` compiles trusted `luasquare.audio/v1` JSON packs. The server owns playback, PA queues, variables such as bus volume, and soundscape state. Clients receive a bounded compiled catalog, music transport changes, and subtitle-sequence start/stop events; audio bytes and raw sources are never networked.

## Source layout

Include timeline first when audio actions should appear in choreography:

```lua
include('luasquare_module/timeline/engine.lua')
include('luasquare_module/audio/engine.lua')
```

Reusable registry assets are global across maps and load recursively:

```text
data_static/luasquare_audio/_shared/<contributor>/sounds/*.json
data_static/luasquare_audio/_shared/<contributor>/subtitles/*.json
data_static/luasquare_audio/_shared/<contributor>/subtitle_styles/*.json
data_static/luasquare_audio/_shared/<contributor>/pa_lines/*.json
```

Only entity-dependent declarations are map-owned:

```text
data_static/luasquare_audio/<map>/channels/*.json
data_static/luasquare_audio/<map>/soundscapes/*.json
```

The contributor segment prevents mounted addons from hiding one another. Framework foundations use `luasquare`; DFR-owned media uses `darkenergyconstruct`. Shared files are merged by normalized lexical path. IDs are global: the first definition wins, a collision warning names both origins, and unrelated definitions from the later pack still load. Legacy non-namespaced folders remain readable with migration warnings.

Editor masters have fixed draft paths under `garrysmod/data/luasquare_audio/drafts/_shared/luasquare/`: `sounds/shared_audio.json`, `subtitles/shared_subtitle.json`, `subtitle_styles/shared_subtitle_style.json`, and `pa_lines/shared_pa.json`. Packed contributor assets remain read-only in the Shared Pool browser and must be explicitly imported before editing. Map channel and soundscape drafts continue to mirror their map-owned folders.

Sound paths are relative to `sound/`. Modes are:

- `music`: synchronized, seekable client `IGModAudioChannel` playback.
- `global`: Source playback emitted once at each listener, preserving DSP without an emitter declaration.
- `source`: positional Source playback that requires a PA-channel emitter or an explicit runtime entity, position, or targetname.

Sound declarations never own emitters. A music sound may list `musicBuses`; an empty list permits any bus. WAV and constant-bitrate MP3 durations are measured with `SoundDuration` when possible; use an explicit duration for OGG, VBR MP3, sound scripts, or unresolved files.

## Shared registry example

```json
{
  "schema": "luasquare.audio/v1",
  "id": "facility_shared_audio",
  "sounds": {
    "facility.intro": {
      "path": "facility/pa_intro.wav",
      "mode": "global",
      "duration": 0.8,
      "channel": "voice",
      "dsp": 1
    },
    "facility.evacuate_voice": {
      "path": "facility/evacuate.wav",
      "mode": "global",
      "duration": 5.2,
      "channel": "voice"
    },
    "facility.music": {
      "path": "music/reactor_loop.ogg",
      "mode": "music",
      "duration": 126.4,
      "loop": true,
      "musicBuses": ["reactor"]
    }
  },
  "musicBuses": {
    "reactor": {"label": "Reactor music", "volume": 1}
  }
}
```

Subtitle timing belongs to the subtitle sequence. Each sound may be linked by at most one automatic sequence:

```json
{
  "schema": "luasquare.audio/v1",
  "id": "facility_subtitles",
  "subtitles": {
    "facility.evacuate": {
      "sound": "facility.evacuate_voice",
      "speaker": "FACILITY",
      "style": "facility_emergency",
      "chunks": [
        {"id": "opening", "at": 0.2, "duration": 2.1, "text": "Evacuate the reactor hall."},
        {"id": "route", "at": 2.6, "duration": 2.2, "text": "Proceed to the marked exits."}
      ]
    }
  }
}
```

Chunk times use source-media seconds and follow effective pitch/playback rate. One playback creates one parent HUD box; concurrent chunks share it, timing gaps temporarily hide it, and other sounds create independently moving boxes. Stopping a sound cancels pending chunks and fades active chunks.

Chunks fade in and out by default. Set `"fadeEnabled": false` on an individual chunk for an immediate appearance/disappearance. Text remains fixed relative to its parent box; only the parent entry motion and opacity are animated unless a style explicitly enables its glitch effect.

PA lines are shared, reusable schedules. Clip time zero begins after the selected intro:

```json
{
  "schema": "luasquare.audio/v1",
  "id": "facility_pa_lines",
  "paLines": {
    "facility.evacuate": {
      "introTone": "facility.intro",
      "clips": [
        {"id": "voice", "at": 0, "sound": "facility.evacuate_voice"}
      ]
    }
  }
}
```

Omit `introTone` to inherit the channel tone, set a sound ID to override it, or use `false` to skip it. Clips may overlap. A map channel contains optional intro/interruption tones, queue policy, hearing radius, and positional emitters. Global line sounds ignore those emitters; source sounds require them.

## Runtime API

```lua
LUASQUARE_AUDIO.PlayMusic('reactor', 'facility.music', {loop = true})
LUASQUARE_AUDIO.PauseMusic('reactor')
LUASQUARE_AUDIO.ResumeMusic('reactor')
LUASQUARE_AUDIO.SeekMusic('reactor', 30)
LUASQUARE_AUDIO.StopMusic('reactor', 2)

LUASQUARE_AUDIO.EnqueuePA('facility', 'facility.evacuate', {priority = 100})
LUASQUARE_AUDIO.GetPALineDuration('facility.evacuate', 'facility')
LUASQUARE_AUDIO.ClearPAChannel('facility', 'alarm reset')

local ok, instanceId = LUASQUARE_AUDIO.PlaySound('machine.loop', {
    entity = machineEntity,
    loop = true,
    ownerId = 'reactor_machine'
})
LUASQUARE_AUDIO.StopSound(instanceId)

local ok, subtitleId = LUASQUARE_AUDIO.StartSubtitleSequence('facility.evacuate')
LUASQUARE_AUDIO.StopSubtitleSequence(subtitleId)
```

PA announcements queue FIFO at equal/lower priority. A higher-priority line cancels every active/pending clip and subtitle group owned by the interrupted line, plays only the interruption tone, then begins the replacement body. The channel waits its configured post-line silence before dequeuing again.

## Editors and timelines

Open `Spawn Menu -> Options -> Luasquare -> Editors` for the windowed Sound Registry, Subtitle Sequence/Style, and PA editors. The subtitle and PA editors initially occupy the top half of the screen, leaving the world and subtitle HUD visible below them. Their timeline toolbars contain zoom and snapping controls, with a draggable horizontal scrollbar beneath the timeline. The subtitle editor has independent Sequences and Styles workspaces. Subtitle chunks may opt into text-color overrides; otherwise they inherit their selected style.

Authoring preview uses a seekable local stream even when the registered runtime mode is `source` or `global`; enable **actual client-local Source playback** only when positional/DSP behavior must be checked, in which case preview begins at zero. Both modes are client-only simulations and never enqueue an authoritative PA line or fire a timeline component. Space toggles play/pause and Shift+Space starts from zero. Packed contributors are browsed through the read-only Shared Pool; Save Draft writes the applicable fixed master or map-owned draft and shows the exact export path. Pool refresh and all previews are client-local and never mutate server catalogs or PA queues. Runtime changes still require an explicit source reload.

Audio registers these timeline components after catalog load:

- `audio.music:<bus>`: play, pause, resume, seek, stop, and bus volume.
- `audio.pa:<channel>`: enqueue a registered PA line or clear the channel.
- `audio.soundscape:<group>`: set or reset state.
- `audio.ambient`: play/stop registered global Source sounds.

PA markers show nominal intro, body, and post-line-silence segments in the timeline editor. Queue waiting is intentionally not visualized. Music and soundscapes support live-preview reconstruction; PA and Source one-shots reject nonzero reconstruction.

Client music/subtitle settings remain under `Options -> Luasquare -> Audio System`. `ReloadSources()` and framework cleanup stop active audio, clear queues and subtitle groups, reset soundscapes, and remove runtime state before loading replacements.
