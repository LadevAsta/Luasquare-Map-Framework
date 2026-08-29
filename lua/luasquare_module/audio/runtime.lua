if not SERVER then return end
LUASQUARE_AUDIO = LUASQUARE_AUDIO or {}
local AUDIO = LUASQUARE_AUDIO

AUDIO.Sources = AUDIO.Sources or {}
AUDIO.SourceDiagnostics = AUDIO.SourceDiagnostics or {}
AUDIO.CatalogRevision = AUDIO.CatalogRevision or 0
AUDIO.Catalog = AUDIO.Catalog or {
    sounds = {}, subtitles = {}, subtitleStyles = {}, musicBuses = {}, paLines = {},
    paChannels = {}, soundscapeGroups = {}
}
AUDIO.MusicStates = AUDIO.MusicStates or {}
AUDIO.MusicBusVolumes = AUDIO.MusicBusVolumes or {}
AUDIO.AmbientInstances = AUDIO.AmbientInstances or {}
AUDIO.SubtitleInstances = AUDIO.SubtitleInstances or {}
AUDIO.PAStates = AUDIO.PAStates or {}
AUDIO.SoundscapeStates = AUDIO.SoundscapeStates or {}
AUDIO.InstanceSerial = AUDIO.InstanceSerial or 0
AUDIO.TimerName = 'LUASQUARE_AUDIO_Runtime'

local categories = AUDIO.SourceCategories
local getSoundProperties = _G.sound and _G.sound.GetProperties
local channelValues = {
    auto = CHAN_AUTO or 0, weapon = CHAN_WEAPON or 1, voice = CHAN_VOICE or 2, item = CHAN_ITEM or 3,
    body = CHAN_BODY or 4, stream = CHAN_STREAM or 5, static = CHAN_STATIC or 6
}

local function log(message) print('[LUASQUARE_AUDIO] ' .. tostring(message)) end
local function now() return CurTime() end
local function humans() return player.GetHumans and player.GetHumans() or player.GetAll() end
local function nextId(prefix)
    AUDIO.InstanceSerial = (AUDIO.InstanceSerial + 1) % 4294967295
    return tostring(prefix or 'audio') .. ':' .. AUDIO.InstanceSerial
end

local function allRecipients()
    local out = {}
    for _, ply in ipairs(humans()) do if IsValid(ply) then table.insert(out, ply) end end
    return out
end

local function uniqueRecipients(target, values)
    for _, ply in ipairs(values or {}) do if IsValid(ply) and ply:IsPlayer() then target[ply] = true end end
end

local function recipientList(set)
    local out = {}
    for ply in pairs(set or {}) do if IsValid(ply) then table.insert(out, ply) end end
    return out
end

local function fileExists(definition)
    if definition.soundScript then
        return getSoundProperties and getSoundProperties(definition.path) ~= nil
    end
    return definition.path ~= '' and file.Exists('sound/' .. definition.path, 'GAME')
end

local function validateEmitterTargets(emitters, diagnosticPath, origin, diagnostics, rejected)
    for _, emitter in ipairs(emitters or {}) do
        if emitter.kind == 'targetname' and #(ents.FindByName(emitter.targetname) or {}) == 0 then
            AUDIO.AddDiagnostic(diagnostics, 'error', diagnosticPath,
                'emitter targetname did not resolve: ' .. emitter.targetname, origin)
            rejected[origin] = true
        end
    end
end

local function validateCatalog(catalog, diagnostics, rejected)
    for _, sound in pairs(catalog.sounds) do
        if not fileExists(sound) then
            AUDIO.AddDiagnostic(diagnostics, 'error', 'sounds.' .. sound.id .. '.path', 'sound file not found', sound._origin)
            rejected[sound._origin] = true
        elseif sound.legacySubtitle and not catalog.subtitles[sound.legacySubtitle] then
            AUDIO.AddDiagnostic(diagnostics, 'error', 'sounds.' .. sound.id .. '.subtitle', 'unknown legacy subtitle', sound._origin)
            rejected[sound._origin] = true
        end
        for _, busId in ipairs(sound.musicBuses or {}) do
            if sound.mode ~= 'music' or not catalog.musicBuses[busId] then
                AUDIO.AddDiagnostic(diagnostics, 'error', 'sounds.' .. sound.id .. '.musicBuses',
                    'unknown or incompatible music bus: ' .. busId, sound._origin)
                rejected[sound._origin] = true
            end
        end
    end
    local subtitleSoundOwners = {}
    for _, subtitle in pairs(catalog.subtitles) do
        local linkedSound = subtitle.sound and catalog.sounds[subtitle.sound]
        if not linkedSound then
            AUDIO.AddDiagnostic(diagnostics, 'error', 'subtitles.' .. subtitle.id .. '.sound',
                'unknown linked sound', subtitle._origin)
            rejected[subtitle._origin] = true
        elseif subtitleSoundOwners[subtitle.sound] then
            AUDIO.AddDiagnostic(diagnostics, 'error', 'subtitles.' .. subtitle.id .. '.sound',
                'sound already linked by ' .. subtitleSoundOwners[subtitle.sound], subtitle._origin)
            rejected[subtitle._origin] = true
        else
            subtitleSoundOwners[subtitle.sound] = subtitle.id
            for _, chunk in ipairs(subtitle.chunks or {}) do
                if chunk.at + chunk.duration > linkedSound.duration + 0.001 then
                    AUDIO.AddDiagnostic(diagnostics, 'error', 'subtitles.' .. subtitle.id .. '.chunks.' .. chunk.id,
                        'chunk extends beyond linked sound duration', subtitle._origin)
                    rejected[subtitle._origin] = true
                end
                local styleId = chunk.style or subtitle.style
                if not catalog.subtitleStyles[styleId] then
                    AUDIO.AddDiagnostic(diagnostics, 'error', 'subtitles.' .. subtitle.id .. '.chunks.' .. chunk.id .. '.style',
                        'unknown subtitle style', subtitle._origin)
                    rejected[subtitle._origin] = true
                end
            end
        end
        if not catalog.subtitleStyles[subtitle.style] then
            AUDIO.AddDiagnostic(diagnostics, 'error', 'subtitles.' .. subtitle.id .. '.style', 'unknown subtitle style', subtitle._origin)
            rejected[subtitle._origin] = true
        end
    end
    for _, line in pairs(catalog.paLines) do
        local maximumEnd = 0
        if type(line.introTone) == 'string' then
            local tone = catalog.sounds[line.introTone]
            if not tone or (tone.mode ~= 'source' and tone.mode ~= 'global') or tone.loop then
                AUDIO.AddDiagnostic(diagnostics, 'error', 'paLines.' .. line.id .. '.introTone',
                    'intro tone must reference a non-looping Source/global sound', line._origin)
                rejected[line._origin] = true
            end
        end
        for _, clip in ipairs(line.clips or {}) do
            local sound = catalog.sounds[clip.sound]
            if not sound or (sound.mode ~= 'source' and sound.mode ~= 'global') or sound.loop then
                AUDIO.AddDiagnostic(diagnostics, 'error', 'paLines.' .. line.id .. '.clips.' .. clip.id,
                    'clip must reference a non-looping Source/global sound', line._origin)
                rejected[line._origin] = true
            else
                maximumEnd = math.max(maximumEnd, clip.at + sound.duration * 100 / sound.pitch)
            end
        end
        line.duration = maximumEnd
    end
    for _, channel in pairs(catalog.paChannels) do
        for _, field in ipairs({'introTone', 'interruptTone'}) do
            local soundId = channel[field]
            local sound = soundId and catalog.sounds[soundId]
            if soundId and (not sound or (sound.mode ~= 'source' and sound.mode ~= 'global') or sound.loop) then
                AUDIO.AddDiagnostic(diagnostics, 'error', 'paChannels.' .. channel.id .. '.' .. field,
                    'tone must reference a non-looping Source/global sound', channel._origin)
                rejected[channel._origin] = true
            end
        end
        validateEmitterTargets(channel.emitters, 'paChannels.' .. channel.id .. '.emitters',
            channel._origin, diagnostics, rejected)
    end
    for _, group in pairs(catalog.soundscapeGroups) do
        for stateId, targets in pairs(group.states) do
            for _, targetname in ipairs(targets) do
                local found, correct = ents.FindByName(targetname) or {}, 0
                for _, entity in ipairs(found) do
                    if IsValid(entity) and entity:GetClass() == 'env_soundscape' then correct = correct + 1 end
                end
                if correct == 0 then
                    AUDIO.AddDiagnostic(diagnostics, 'error',
                        'soundscapeGroups.' .. group.id .. '.states.' .. stateId,
                        'targetname has no env_soundscape: ' .. targetname, group._origin)
                    rejected[group._origin] = true
                end
            end
        end
    end
end

local function strictDuplicate(catalog, source)
    for _, category in ipairs(categories) do
        for id in pairs(source[category] or {}) do
            if catalog[category][id] then return category, id, catalog[category][id] end
        end
    end
end

local function mergeSharedCategory(catalog, source, category, path, diagnostics, reportCollisions)
    for id, definition in pairs(source[category] or {}) do
        local existing = catalog[category][id]
        if existing and reportCollisions then
            AUDIO.AddDiagnostic(diagnostics, 'warning', category .. '.' .. id,
                'duplicate id already supplied by ' .. tostring(existing._origin)
                    .. '; first definition retained', path)
        elseif not existing then catalog[category][id] = definition end
    end
end

local function mergeStrictCategory(catalog, source, category)
    for id, definition in pairs(source[category] or {}) do catalog[category][id] = definition end
end

local function mergeSources(excluded, diagnostics, reportCollisions)
    local catalog = {
        sounds = {}, subtitles = {}, subtitleStyles = {},
        musicBuses = {}, paLines = {}, paChannels = {}, soundscapeGroups = {}
    }
    local paths, packOrigins = {}, {}
    for path in pairs(AUDIO.Sources) do table.insert(paths, path) end
    table.sort(paths, function(a, b)
        local lowerA, lowerB = string.lower(string.gsub(a, '\\', '/')), string.lower(string.gsub(b, '\\', '/'))
        return lowerA == lowerB and a < b or lowerA < lowerB
    end)
    for _, path in ipairs(paths) do
        local source = AUDIO.Sources[path]
        if not excluded[path] then
            local shared = AUDIO.GetSharedPathInfo(path) ~= nil
            local duplicate = false
            if packOrigins[source.id] then
                if reportCollisions then
                    AUDIO.AddDiagnostic(diagnostics, shared and 'warning' or 'error', 'id',
                        'duplicate pack id already supplied by ' .. packOrigins[source.id]
                            .. '; first source remains authoritative', path)
                end
                duplicate = not shared
            end
            if not shared and not duplicate then
                local category, id, existing = strictDuplicate(catalog, source)
                if existing then
                    if reportCollisions then AUDIO.AddDiagnostic(diagnostics, 'error', category .. '.' .. id,
                        'duplicate id already supplied by ' .. tostring(existing._origin), path) end
                    duplicate = true
                end
            end
            if duplicate then
                excluded[path] = true
            else
                packOrigins[source.id] = packOrigins[source.id] or path
                for _, category in ipairs(categories) do
                    if shared then mergeSharedCategory(catalog, source, category, path, diagnostics, reportCollisions)
                    else mergeStrictCategory(catalog, source, category) end
                end
            end
        end
    end
    if not catalog.subtitleStyles.default then
        catalog.subtitleStyles.default = {
            id = 'default', label = 'Default', color = {255, 255, 255, 255},
            speakerColor = {150, 205, 255, 255}, font = 'Roboto', size = 24, weight = 500,
            glitch = {enabled = false, intensity = 1, interval = 0.06}, _origin = '<built-in>'
        }
    end
    for soundId, sound in pairs(catalog.sounds) do
        local sequence = sound.legacySubtitle and catalog.subtitles[sound.legacySubtitle]
        if sequence and not sequence.sound then sequence.sound = soundId end
    end
    return catalog
end

function AUDIO.RebuildCatalog()
    local diagnostics, excluded = {}, {}
    local catalog = mergeSources(excluded, diagnostics, true)
    for _ = 1, math.max(table.Count(AUDIO.Sources), 1) + 1 do
        local previous = table.Count(excluded)
        catalog = mergeSources(excluded, diagnostics, false)
        validateCatalog(catalog, diagnostics, excluded)
        if table.Count(excluded) == previous then break end
    end
    catalog = mergeSources(excluded, diagnostics, false)
    validateCatalog(catalog, diagnostics, {})
    AUDIO.Catalog = catalog
    AUDIO.SubtitleBySound = {}
    for sequenceId, sequence in pairs(catalog.subtitles) do
        if sequence.sound then AUDIO.SubtitleBySound[sequence.sound] = sequenceId end
    end
    AUDIO.CatalogRevision = AUDIO.CatalogRevision + 1
    for path in pairs(excluded) do log('Audio pack unavailable: ' .. path) end
    if #diagnostics > 0 then log(AUDIO.DiagnosticsText(diagnostics)) end
    for id, bus in pairs(catalog.musicBuses) do
        if AUDIO.MusicBusVolumes[id] == nil then AUDIO.MusicBusVolumes[id] = bus.volume end
    end
    for id in pairs(AUDIO.MusicBusVolumes) do
        if not catalog.musicBuses[id] then AUDIO.MusicBusVolumes[id] = nil end
    end
    if AUDIO.RegisterTimelineComponents then AUDIO.RegisterTimelineComponents() end
    if AUDIO.BroadcastCatalog then AUDIO.BroadcastCatalog() end
    return true, diagnostics
end

function AUDIO.LoadSource(path, deferRebuild)
    path = string.gsub(tostring(path or ''), '\\', '/')
    if not AUDIO.IsSafePath(path) or string.sub(string.lower(path), -5) ~= '.json' then
        return false, 'unsafe audio source path'
    end
    local json = file.Read(path, 'GAME')
    if not json then return false, 'audio source not found: ' .. path end
    local compiled, diagnostics = AUDIO.DecodeSource(json, path)
    diagnostics = diagnostics or {}
    if compiled then
        local lowerPath, allowed = string.lower(path), {}
        local sharedInfo = AUDIO.GetSharedPathInfo(path)
        if sharedInfo then
            allowed = sharedInfo.allowed
            if sharedInfo.legacy then
                AUDIO.AddDiagnostic(diagnostics, 'warning', '$',
                    'legacy shared folder; migrate to _shared/<namespace>/' .. sharedInfo.folder, path)
            end
        elseif string.find(lowerPath, '/channels/', 1, true) then
            allowed.paChannels = true
        elseif string.find(lowerPath, '/soundscapes/', 1, true) then
            allowed.soundscapeGroups = true
        end
        for _, category in ipairs(categories) do
            if table.Count(compiled[category] or {}) > 0 and not allowed[category] then
                AUDIO.AddDiagnostic(diagnostics, 'error', category,
                    'category is not allowed in this audio source folder', path)
            end
        end
        if AUDIO.HasErrors(diagnostics) then compiled = nil end
    end
    AUDIO.SourceDiagnostics[path] = diagnostics or {}
    if not compiled then
        log(AUDIO.DiagnosticsText(diagnostics))
        AUDIO.Sources[path] = nil
        return false, AUDIO.DiagnosticsText(diagnostics)
    end
    AUDIO.Sources[path] = compiled
    if not deferRebuild then AUDIO.RebuildCatalog() end
    return true, compiled
end

local function loadDirectory(root)
    local count = 0
    local files, directories = file.Find(root .. '/*', 'GAME')
    for _, name in ipairs(files or {}) do
        if string.sub(string.lower(name), -5) == '.json' and AUDIO.LoadSource(root .. '/' .. name, true) then count = count + 1 end
    end
    for _, directory in ipairs(directories or {}) do count = count + loadDirectory(root .. '/' .. directory) end
    return count
end

function AUDIO.LoadMapSources(mapName)
    AUDIO.Sources = {}
    AUDIO.SourceDiagnostics = {}
    local count = loadDirectory(AUDIO.SourceRoot .. '/_shared')
    local map = string.lower(tostring(mapName or game.GetMap() or ''))
    if map ~= '' then
        -- Scan the map root so misplaced shared registries are diagnosed instead of silently ignored.
        count = count + loadDirectory(AUDIO.SourceRoot .. '/' .. map)
    end
    AUDIO.RebuildCatalog()
    AUDIO.Start()
    log('Loaded ' .. count .. ' audio pack(s)')
    return count
end

function AUDIO.ReloadSources()
    if LUASQUARE_TIMELINE and LUASQUARE_TIMELINE.CancelOwner then
        for componentId in pairs(AUDIO.TimelineComponents or {}) do
            LUASQUARE_TIMELINE.CancelOwner(componentId, 'audio sources reloaded')
        end
    end
    AUDIO.Reset('audio sources reloaded')
    return AUDIO.LoadMapSources(game.GetMap())
end

local function musicPosition(state)
    if not state then return 0 end
    if state.status ~= 'playing' then return state.offset or 0 end
    return math.max((state.offset or 0) + (now() - (state.startedAt or now()))
        * (state.playbackRate or 1), 0)
end

local function publicMusicState(state)
    return state and {
        busId = state.busId, soundId = state.soundId, status = state.status,
        startedAt = state.startedAt, offset = state.offset, loop = state.loop,
        volume = state.volume, busVolume = AUDIO.MusicBusVolumes[state.busId] or 1,
        playbackRate = state.playbackRate or 1, fadeSeconds = state.fadeSeconds or 0
    } or nil
end

function AUDIO.GetMusicSnapshot()
    local out = {}
    for id, state in pairs(AUDIO.MusicStates) do out[id] = publicMusicState(state) end
    return out
end

local function stopMusicSubtitle(state)
    if state and state.subtitleId and AUDIO.StopSubtitleSequence then
        AUDIO.StopSubtitleSequence(state.subtitleId) state.subtitleId = nil
    end
end

local function startMusicSubtitle(state, sound)
    stopMusicSubtitle(state)
    local sequenceId = sound and AUDIO.SubtitleBySound and AUDIO.SubtitleBySound[sound.id]
    if not sequenceId or not AUDIO.StartSubtitleSequence then return end
    local ok, instanceId = AUDIO.StartSubtitleSequence(sequenceId, {
        recipients = allRecipients(), offset = state.offset or 0,
        playbackRate = state.playbackRate or 1, ownerId = state.ownerId
    })
    if ok then state.subtitleId = instanceId end
end

local function effectiveTimeScale()
    local scale = game.GetTimeScale and game.GetTimeScale() or 1
    local host = GetConVar('host_timescale')
    if host then scale = scale * host:GetFloat() end
    return AUDIO.Clamp(scale, 0, 5)
end

function AUDIO.PlayMusic(busId, soundId, options)
    options = options or {}
    busId, soundId = AUDIO.NormalizeId(busId), AUDIO.NormalizeId(soundId)
    local bus, sound = AUDIO.Catalog.musicBuses[busId], AUDIO.Catalog.sounds[soundId]
    if not bus then return false, 'unknown music bus' end
    if not sound or sound.mode ~= 'music' then return false, 'unknown or incompatible music sound' end
    if #(sound.musicBuses or {}) > 0 and not table.HasValue(sound.musicBuses, busId) then
        return false, 'music sound is not assigned to this bus'
    end
    if AUDIO.MusicStates[busId] then AUDIO.StopMusic(busId, options.replaceFade or 0) end
    local offset = math.max(tonumber(options.offset) or 0, 0)
    if sound.duration and sound.duration > 0 then
        offset = sound.loop and (offset % sound.duration) or math.min(offset, sound.duration)
    end
    AUDIO.MusicStates[busId] = {
        busId = busId, soundId = soundId, status = options.paused and 'paused' or 'playing',
        startedAt = now(), offset = offset, loop = options.loop ~= nil and options.loop or sound.loop,
        volume = AUDIO.Clamp(options.volume or 1, 0, 1),
        playbackRate = effectiveTimeScale() * sound.pitch / 100,
        ownerId = tostring(options.ownerId or '')
    }
    if AUDIO.MusicStates[busId].status == 'playing' then
        startMusicSubtitle(AUDIO.MusicStates[busId], sound)
    end
    if AUDIO.BroadcastMusicState then AUDIO.BroadcastMusicState(busId, publicMusicState(AUDIO.MusicStates[busId])) end
    return true, AUDIO.MusicStates[busId]
end

function AUDIO.PauseMusic(busId)
    busId = AUDIO.NormalizeId(busId)
    local state = busId and AUDIO.MusicStates[busId]
    if not state or state.status ~= 'playing' then return false, 'music bus is not playing' end
    state.offset, state.status = musicPosition(state), 'paused'
    stopMusicSubtitle(state)
    if AUDIO.BroadcastMusicState then AUDIO.BroadcastMusicState(busId, publicMusicState(state)) end
    return true
end

function AUDIO.ResumeMusic(busId)
    busId = AUDIO.NormalizeId(busId)
    local state = busId and AUDIO.MusicStates[busId]
    if not state or state.status ~= 'paused' then return false, 'music bus is not paused' end
    state.startedAt, state.status = now(), 'playing'
    startMusicSubtitle(state, AUDIO.Catalog.sounds[state.soundId])
    if AUDIO.BroadcastMusicState then AUDIO.BroadcastMusicState(busId, publicMusicState(state)) end
    return true
end

function AUDIO.SeekMusic(busId, seconds)
    busId = AUDIO.NormalizeId(busId)
    local state = busId and AUDIO.MusicStates[busId]
    if not state then return false, 'music bus is idle' end
    local sound = AUDIO.Catalog.sounds[state.soundId]
    seconds = math.max(tonumber(seconds) or 0, 0)
    if sound and sound.duration then seconds = state.loop and seconds % sound.duration or math.min(seconds, sound.duration) end
    state.offset, state.startedAt = seconds, now()
    if state.status == 'playing' then startMusicSubtitle(state, sound) end
    if AUDIO.BroadcastMusicState then AUDIO.BroadcastMusicState(busId, publicMusicState(state)) end
    return true
end

function AUDIO.StopMusic(busId, fadeSeconds)
    busId = AUDIO.NormalizeId(busId)
    if not busId or not AUDIO.MusicStates[busId] then return false, 'music bus is idle' end
    stopMusicSubtitle(AUDIO.MusicStates[busId])
    AUDIO.MusicStates[busId] = nil
    if AUDIO.BroadcastMusicState then AUDIO.BroadcastMusicState(busId, nil, AUDIO.Clamp(fadeSeconds or 0, 0, 30)) end
    return true
end

function AUDIO.SetMusicBusVolume(busId, volume, transitionSeconds)
    busId = AUDIO.NormalizeId(busId)
    if not busId or not AUDIO.Catalog.musicBuses[busId] then return false, 'unknown music bus' end
    AUDIO.MusicBusVolumes[busId] = AUDIO.Clamp(volume, 0, 1)
    local state = AUDIO.MusicStates[busId]
    if AUDIO.BroadcastMusicState and state then
        local public = publicMusicState(state)
        public.volumeTransition = AUDIO.Clamp(transitionSeconds or 0, 0, 30)
        AUDIO.BroadcastMusicState(busId, public)
    end
    return true
end

local function emitterPosition(emitter)
    if emitter.kind == 'global' then return nil end
    if emitter.kind == 'entity' and IsValid(emitter.entity) then return emitter.entity:GetPos() end
    if emitter.kind == 'position' then return emitter.position end
end

local function playersAt(position, radius)
    if not position then return allRecipients() end
    local filter = RecipientFilter()
    filter:AddPAS(position)
    local out = filter:GetPlayers() or {}
    if radius and radius > 0 then
        local filtered = {}
        local radiusSquared = radius * radius
        for _, ply in ipairs(out) do
            if IsValid(ply) and ply:GetPos():DistToSqr(position) <= radiusSquared then table.insert(filtered, ply) end
        end
        out = filtered
    end
    return out
end

local function makeEmitter(value)
    if IsValid(value) then return {kind = 'entity', entity = value} end
    if isvector(value) then return {kind = 'position', position = value} end
    if type(value) ~= 'table' then return nil end
    if value.kind == 'global' or value.global then return {kind = 'global'} end
    if IsValid(value.entity) then return {kind = 'entity', entity = value.entity} end
    if isvector(value.position) then return {kind = 'position', position = value.position} end
    if type(value.position) == 'table' then
        return {kind = 'position', position = Vector(tonumber(value.position[1]) or 0,
            tonumber(value.position[2]) or 0, tonumber(value.position[3]) or 0)}
    end
    if type(value.targetname) == 'string' then return {kind = 'targetname', targetname = value.targetname} end
end

local function resolveEmitters(sound, options)
    if sound.mode == 'global' then return {{kind = 'global'}} end
    local definitions = options.emitters
    local explicitlyConfigured = options.emitters ~= nil or options.entity ~= nil or options.position ~= nil
        or options.targetname ~= nil or options.global == true
    if options.global then definitions = {{global = true}}
    elseif options.entity then definitions = {options.entity}
    elseif options.position then definitions = {options.position}
    elseif options.targetname then definitions = {{targetname = options.targetname}} end
    local out = {}
    for _, value in ipairs(definitions or {}) do
        local emitter = makeEmitter(value)
        if emitter and emitter.kind == 'targetname' then
            for _, entity in ipairs(ents.FindByName(emitter.targetname) or {}) do
                if IsValid(entity) then table.insert(out, {kind = 'entity', entity = entity}) end
            end
        elseif emitter then table.insert(out, emitter) end
    end
    if #out == 0 and not explicitlyConfigured and sound.mode ~= 'source' then table.insert(out, {kind = 'global'}) end
    return out
end

local function emitAt(sound, emitter, recipients, instance)
    if emitter.kind == 'global' then
        for _, ply in ipairs(recipients) do
            local filter = RecipientFilter() filter:AddPlayer(ply)
            EmitSound(sound.path, ply:GetPos(), ply:EntIndex(), channelValues[sound.channel] or CHAN_AUTO,
                sound.volume, sound.soundLevel, SND_SHOULDPAUSE or 128, sound.pitch, sound.dsp, filter)
            table.insert(instance.emittedFrom, ply)
        end
        return #recipients > 0
    end
    local entity = emitter.entity
    if emitter.kind == 'position' then
        entity = ents.Create('info_target')
        if IsValid(entity) then
            entity:SetPos(emitter.position) entity:Spawn()
            entity.LuasquareAudioTemporary = true
            table.insert(instance.temporaryEntities, entity)
        end
    end
    if not IsValid(entity) then return false end
    local filter = RecipientFilter()
    for _, ply in ipairs(recipients) do filter:AddPlayer(ply) end
    EmitSound(sound.path, entity:GetPos(), entity:EntIndex(), channelValues[sound.channel] or CHAN_AUTO,
        sound.volume, sound.soundLevel, SND_SHOULDPAUSE or 128, sound.pitch, sound.dsp, filter)
    table.insert(instance.emittedFrom, entity)
    return true
end

function AUDIO.GetSubtitleSequenceDuration(subtitleId, playbackRate)
    subtitleId = AUDIO.NormalizeId(subtitleId)
    local definition = subtitleId and AUDIO.Catalog.subtitles[subtitleId]
    if not definition then return nil end
    return definition.duration / math.max(tonumber(playbackRate) or 1, 0.001)
end

function AUDIO.StartSubtitleSequence(subtitleId, options)
    options = options or {}
    subtitleId = AUDIO.NormalizeId(subtitleId)
    local definition = subtitleId and AUDIO.Catalog.subtitles[subtitleId]
    if not definition then return false, 'unknown subtitle sequence' end
    local rate = AUDIO.Clamp(options.playbackRate or 1, 0.001, 8)
    local offset = AUDIO.Clamp(options.offset or 0, 0, definition.duration)
    local duration = math.max((definition.duration - offset) / rate, 0.01)
    local id = nextId('subtitle')
    local instance = {
        id = id, subtitleId = subtitleId, startedAt = now(), endsAt = now() + duration,
        recipients = options.recipients or allRecipients(), duration = duration,
        playbackRate = rate, offset = offset, ownerId = tostring(options.ownerId or '')
    }
    AUDIO.SubtitleInstances[id] = instance
    if AUDIO.SendSubtitleStart then AUDIO.SendSubtitleStart(instance) end
    return true, id
end


function AUDIO.ShowSubtitle(subtitleId, options)
    return AUDIO.StartSubtitleSequence(subtitleId, options)
end

function AUDIO.StopSubtitleSequence(instanceId)
    local instance = AUDIO.SubtitleInstances[tostring(instanceId or '')]
    if not instance then return false end
    AUDIO.SubtitleInstances[instance.id] = nil
    if AUDIO.SendSubtitleStop then AUDIO.SendSubtitleStop(instance) end
    return true
end


AUDIO.StopSubtitle = AUDIO.StopSubtitleSequence

function AUDIO.GetSubtitleSnapshot()
    local out = {}
    for id, instance in pairs(AUDIO.SubtitleInstances) do
        out[id] = {id = id, subtitleId = instance.subtitleId, startedAt = instance.startedAt,
            endsAt = instance.endsAt, playbackRate = instance.playbackRate, offset = instance.offset,
            ownerId = instance.ownerId}
    end
    return out
end

function AUDIO.PlaySound(soundId, options)
    options = options or {}
    soundId = AUDIO.NormalizeId(soundId)
    local sound = soundId and AUDIO.Catalog.sounds[soundId]
    if not sound or (sound.mode ~= 'source' and sound.mode ~= 'global') then
        return false, 'unknown or incompatible Source/global sound'
    end
    local emitters = resolveEmitters(sound, options)
    if #emitters == 0 then return false, 'no sound emitter resolved' end
    local effectiveLoop = options.loop ~= nil and options.loop or sound.loop
    local instance = {
        id = nextId('sound'), soundId = soundId, ownerId = tostring(options.ownerId or ''),
        soundPath = sound.path, startedAt = now(),
        endsAt = not effectiveLoop and (now() + sound.duration * 100 / sound.pitch) or nil,
        loop = effectiveLoop, emittedFrom = {}, temporaryEntities = {}, subtitleId = nil
    }
    local recipientSet, emitted = {}, false
    for _, emitter in ipairs(emitters) do
        local recipients = emitter.kind == 'global' and allRecipients()
            or playersAt(emitterPosition(emitter), tonumber(options.hearingRadius) or sound.hearingRadius)
        uniqueRecipients(recipientSet, recipients)
        emitted = emitAt(sound, emitter, recipients, instance) or emitted
    end
    if not emitted then
        for _, entity in ipairs(instance.temporaryEntities) do if IsValid(entity) then entity:Remove() end end
        return false, 'no recipients or valid emitters'
    end
    AUDIO.AmbientInstances[instance.id] = instance
    local subtitleSequence = AUDIO.SubtitleBySound and AUDIO.SubtitleBySound[soundId]
    if subtitleSequence and options.subtitle ~= false then
        local ok, subtitleInstance = AUDIO.StartSubtitleSequence(subtitleSequence, {
            recipients = recipientList(recipientSet), playbackRate = sound.pitch / 100,
            ownerId = instance.ownerId
        })
        if ok then instance.subtitleId = subtitleInstance end
    end
    return true, instance.id
end

local function stopInstance(instance)
    if not instance then return false end
    AUDIO.AmbientInstances[instance.id] = nil
    local path = instance.soundPath
        or (AUDIO.Catalog.sounds[instance.soundId] and AUDIO.Catalog.sounds[instance.soundId].path)
    for _, entity in ipairs(instance.emittedFrom or {}) do
        if path and IsValid(entity) then entity:StopSound(path) end
    end
    for _, entity in ipairs(instance.temporaryEntities or {}) do if IsValid(entity) then entity:Remove() end end
    if instance.subtitleId then AUDIO.StopSubtitle(instance.subtitleId) end
    return true
end

function AUDIO.StopSound(instanceOrSoundId, options)
    options = options or {}
    local key = tostring(instanceOrSoundId or '')
    if AUDIO.AmbientInstances[key] then return stopInstance(AUDIO.AmbientInstances[key]) end
    local soundId = AUDIO.NormalizeId(key)
    local stopped = 0
    for _, instance in pairs(table.Copy(AUDIO.AmbientInstances)) do
        if instance.soundId == soundId and (not options.ownerId or instance.ownerId == tostring(options.ownerId)) then
            stopInstance(instance)
            stopped = stopped + 1
        end
    end
    return stopped > 0, stopped > 0 and stopped or 'sound instance not found'
end

function AUDIO.StopOwnerSounds(ownerId)
    ownerId = tostring(ownerId or '')
    local stopped = 0
    for _, instance in pairs(table.Copy(AUDIO.AmbientInstances)) do
        if instance.ownerId == ownerId and stopInstance(instance) then stopped = stopped + 1 end
    end
    return stopped
end

function AUDIO.GetSoundSnapshot()
    local out = {}
    for id, instance in pairs(AUDIO.AmbientInstances) do
        out[id] = {id = id, soundId = instance.soundId, ownerId = instance.ownerId,
            startedAt = instance.startedAt, endsAt = instance.endsAt, loop = instance.loop}
    end
    return out
end

local function paState(id)
    local state = AUDIO.PAStates[id]
    if not state then
        state = {id = id, phase = 'idle', queue = {}, activeInstances = {}, clipStates = {}}
        AUDIO.PAStates[id] = state
    end
    return state
end

local function effectiveSoundDuration(sound)
    return sound and sound.duration * 100 / math.max(sound.pitch or 100, 1) or 0
end

local function lineIntroSound(channel, line)
    if line.introTone == false then return nil end
    if type(line.introTone) == 'string' then return line.introTone end
    return channel.introTone
end

local function paPlaybackOptions(state, item, subtitle)
    local channel = AUDIO.Catalog.paChannels[state.id]
    return {emitters = channel.emitters, hearingRadius = channel.hearingRadius,
        ownerId = state.runOwner, subtitle = subtitle ~= false}
end

local function paStopActive(state)
    if state.toneInstance then AUDIO.StopSound(state.toneInstance) end
    for instanceId in pairs(state.activeInstances or {}) do AUDIO.StopSound(instanceId) end
    if state.runOwner and state.runOwner ~= '' then AUDIO.StopOwnerSounds(state.runOwner) end
    state.toneInstance, state.activeInstances, state.clipStates = nil, {}, {}
end

local function paEnterIdle(state)
    state.phase, state.current, state.pending, state.phaseEnds, state.lineStartedAt,
        state.activeOwner, state.runOwner = 'idle', nil, nil, nil, nil, nil, nil
    state.activeInstances, state.clipStates = {}, {}
end

local function paStartLine(state, item)
    local line = item and AUDIO.Catalog.paLines[item.lineId]
    if not line then paEnterIdle(state) return false end
    state.phase, state.current, state.pending = 'line', item, nil
    state.lineStartedAt, state.phaseEnds = now(), now() + line.duration
    state.activeOwner, state.clipStates, state.activeInstances = item.ownerId, {}, {}
    for index in ipairs(line.clips) do state.clipStates[index] = false end
    return true
end

local function paPlayTone(state, soundId, item, phase)
    state.pending, state.current, state.activeOwner = item, nil, item and item.ownerId or ''
    state.runOwner = 'pa:' .. state.id .. ':' .. nextId('line')
    if not soundId then return paStartLine(state, item) end
    local sound = AUDIO.Catalog.sounds[soundId]
    local ok, instanceId = AUDIO.PlaySound(soundId, paPlaybackOptions(state, item, false))
    if not ok then return paStartLine(state, item) end
    state.phase, state.toneInstance = phase, instanceId
    state.phaseEnds = now() + effectiveSoundDuration(sound)
    return true
end

local function paBeginQueued(state)
    local item = table.remove(state.queue, 1)
    if not item then paEnterIdle(state) return false end
    local channel, line = AUDIO.Catalog.paChannels[state.id], AUDIO.Catalog.paLines[item.lineId]
    return paPlayTone(state, lineIntroSound(channel, line), item, 'intro_tone')
end

local function paCanPlayLine(channel, line, interruption)
    local soundIds = {}
    local tone = interruption and channel.interruptTone or lineIntroSound(channel, line)
    if tone then table.insert(soundIds, tone) end
    for _, clip in ipairs(line.clips) do table.insert(soundIds, clip.sound) end
    for _, soundId in ipairs(soundIds) do
        local sound = AUDIO.Catalog.sounds[soundId]
        if sound and sound.mode == 'source'
            and #resolveEmitters(sound, {emitters = channel.emitters}) == 0 then
            return false, 'no PA emitter resolved for ' .. soundId
        end
    end
    return true
end

function AUDIO.GetPALineDuration(lineId, channelId, options)
    options = options or {}
    lineId, channelId = AUDIO.NormalizeId(lineId), AUDIO.NormalizeId(channelId)
    local line = lineId and AUDIO.Catalog.paLines[lineId]
    local channel = channelId and AUDIO.Catalog.paChannels[channelId]
    if not line then return nil, 'unknown PA line' end
    local introSeconds = 0
    if channel and not options.interrupted then
        local intro = lineIntroSound(channel, line)
        introSeconds = effectiveSoundDuration(intro and AUDIO.Catalog.sounds[intro])
    end
    local silence = channel and channel.silenceSeconds or 0
    return introSeconds + line.duration + silence,
        {intro = introSeconds, body = line.duration, silence = silence}
end

function AUDIO.GetPALineSnapshot()
    local out = {}
    for id, line in pairs(AUDIO.Catalog.paLines) do
        out[id] = {id = id, label = line.label, introTone = line.introTone,
            duration = line.duration, clips = AUDIO.DeepCopy(line.clips)}
    end
    return out
end

function AUDIO.EnqueuePA(channelId, lineId, options)
    options = options or {}
    channelId, lineId = AUDIO.NormalizeId(channelId), AUDIO.NormalizeId(lineId)
    local channel, line = AUDIO.Catalog.paChannels[channelId], AUDIO.Catalog.paLines[lineId]
    if not channel then return false, 'unknown PA channel' end
    if not line then return false, 'unknown PA line' end
    local state = paState(channelId)
    local item = {
        lineId = lineId, priority = math.floor(tonumber(options.priority) or 0),
        subtitle = options.subtitle, ownerId = tostring(options.ownerId or '')
    }
    local currentPriority = state.current and state.current.priority or state.pending and state.pending.priority or -math.huge
    local interruptible = state.phase ~= 'idle' and state.phase ~= 'silence'
    if interruptible and item.priority > currentPriority then
        local available, reason = paCanPlayLine(channel, line, true)
        if not available then return false, reason end
        paStopActive(state)
        paPlayTone(state, channel.interruptTone, item, 'interrupt_tone')
        return true, 'interrupted'
    end
    local available, reason = paCanPlayLine(channel, line, false)
    if not available then return false, reason end
    if state.phase == 'idle' then
        table.insert(state.queue, item)
        paBeginQueued(state)
        return true, 'started'
    end
    if #state.queue >= channel.maxQueue then return false, 'PA queue is full' end
    table.insert(state.queue, item)
    return true, 'queued'
end

function AUDIO.ClearPAChannel(channelId, reason)
    channelId = AUDIO.NormalizeId(channelId)
    local state = channelId and AUDIO.PAStates[channelId]
    if not state then return false, 'unknown or idle PA channel' end
    paStopActive(state)
    paEnterIdle(state)
    state.queue = {}
    state.reason = tostring(reason or 'cleared')
    return true
end

function AUDIO.ClearPAOwner(channelId, ownerId, reason)
    channelId, ownerId = AUDIO.NormalizeId(channelId), tostring(ownerId or '')
    local state = channelId and AUDIO.PAStates[channelId]
    if not state or ownerId == '' then return false, 'unknown PA channel or owner' end
    local retained, removed = {}, false
    for _, item in ipairs(state.queue or {}) do
        if item.ownerId ~= ownerId then table.insert(retained, item) else removed = true end
    end
    state.queue = retained
    local ownsActive = state.activeOwner == ownerId
        or state.current and state.current.ownerId == ownerId
        or state.pending and state.pending.ownerId == ownerId
    if ownsActive then
        paStopActive(state)
        paEnterIdle(state)
        state.reason = tostring(reason or 'owner cleared')
        paBeginQueued(state)
    end
    return ownsActive or removed
end

function AUDIO.GetPASnapshot()
    local out = {}
    for id, state in pairs(AUDIO.PAStates) do
        out[id] = {id = id, phase = state.phase, queued = #state.queue,
            currentLine = state.current and state.current.lineId
                or state.pending and state.pending.lineId or nil,
            priority = state.current and state.current.priority or nil, phaseEnds = state.phaseEnds}
    end
    return out
end

local function soundscapeEntities(targetname)
    local out, wrongClass = {}, 0
    for _, entity in ipairs(ents.FindByName(targetname) or {}) do
        if IsValid(entity) and entity:GetClass() == 'env_soundscape' then table.insert(out, entity) end
        if IsValid(entity) and entity:GetClass() ~= 'env_soundscape' then wrongClass = wrongClass + 1 end
    end
    return out, wrongClass
end

function AUDIO.SetSoundscapeState(groupId, stateId)
    groupId, stateId = AUDIO.NormalizeId(groupId), AUDIO.NormalizeId(stateId)
    local group = groupId and AUDIO.Catalog.soundscapeGroups[groupId]
    if not group then return false, 'unknown soundscape group' end
    if stateId and not group.states[stateId] then return false, 'unknown soundscape state' end
    local allTargets = {}
    for _, targets in pairs(group.states) do for _, target in ipairs(targets) do allTargets[target] = true end end
    for target in pairs(allTargets) do for _, entity in ipairs(soundscapeEntities(target)) do entity:Fire('Disable') end end
    if stateId then
        for _, target in ipairs(group.states[stateId]) do
            local entities, wrongClass = soundscapeEntities(target)
            if #entities == 0 then log('Missing env_soundscape target: ' .. target) end
            if wrongClass > 0 then
                log(string.format('%d wrongly classed soundscape target(s): %s', wrongClass, target))
            end
            for _, entity in ipairs(entities) do entity:Fire('Enable') end
        end
    end
    AUDIO.SoundscapeStates[groupId] = stateId
    if AUDIO.BroadcastStateDelta then AUDIO.BroadcastStateDelta('soundscape', groupId, stateId) end
    return true
end

function AUDIO.GetSoundscapeState(groupId)
    return AUDIO.SoundscapeStates[AUDIO.NormalizeId(groupId)]
end

function AUDIO.ResetSoundscapeGroup(groupId)
    groupId = AUDIO.NormalizeId(groupId)
    local group = groupId and AUDIO.Catalog.soundscapeGroups[groupId]
    if not group then return false, 'unknown soundscape group' end
    return AUDIO.SetSoundscapeState(groupId, group.defaultState)
end

function AUDIO.GetCatalogSnapshot()
    local catalog = AUDIO.DeepCopy(AUDIO.Catalog)
    for _, category in ipairs(categories) do
        for _, definition in pairs(catalog[category]) do definition._origin = nil end
    end
    return {revision = AUDIO.CatalogRevision, catalog = catalog}
end

function AUDIO.GetSnapshot()
    return {revision = AUDIO.CatalogRevision, music = AUDIO.GetMusicSnapshot(),
        soundscapes = AUDIO.DeepCopy(AUDIO.SoundscapeStates), timeScale = effectiveTimeScale()}
end

local function paStartDueClip(state, index, clip, elapsed)
    if state.clipStates[index] or elapsed < clip.at then return end
    state.clipStates[index] = true
    local ok, instanceId = AUDIO.PlaySound(clip.sound,
        paPlaybackOptions(state, state.current, state.current.subtitle))
    if ok then state.activeInstances[instanceId] = true end
end

local function tickPA(current)
    for _, state in pairs(AUDIO.PAStates) do
        if state.phase == 'line' then
            local line = state.current and AUDIO.Catalog.paLines[state.current.lineId]
            if not line then
                paStopActive(state) paEnterIdle(state)
            else
                local elapsed = current - state.lineStartedAt
                for index, clip in ipairs(line.clips) do
                    paStartDueClip(state, index, clip, elapsed)
                end
                if current >= state.phaseEnds then
                    paStopActive(state)
                    state.current, state.phase = nil, 'silence'
                    state.phaseEnds = current + AUDIO.Catalog.paChannels[state.id].silenceSeconds
                end
            end
        elseif state.phaseEnds and current >= state.phaseEnds then
            if state.toneInstance then AUDIO.StopSound(state.toneInstance) end
            state.toneInstance = nil
            if state.phase == 'intro_tone' or state.phase == 'interrupt_tone' then
                local pending = state.pending state.pending = nil paStartLine(state, pending)
            elseif state.phase == 'silence' then
                state.phaseEnds = nil
                if not paBeginQueued(state) then paEnterIdle(state) end
            end
        end
    end
end

function AUDIO.Tick()
    local current = now()
    for _, instance in pairs(table.Copy(AUDIO.AmbientInstances)) do
        if instance.endsAt and current >= instance.endsAt then stopInstance(instance) end
    end
    for id, subtitle in pairs(AUDIO.SubtitleInstances) do
        if current >= subtitle.endsAt then AUDIO.StopSubtitle(id) end
    end
    tickPA(current)
    local timeScale = effectiveTimeScale()
    local timeScaleChanged = false
    for busId, state in pairs(table.Copy(AUDIO.MusicStates)) do
        local sound = AUDIO.Catalog.sounds[state.soundId]
        local targetRate = timeScale * (sound and sound.pitch or 100) / 100
        if math.abs((state.playbackRate or 1) - targetRate) > 0.001 then
            state.offset, state.startedAt = musicPosition(state), current
            state.playbackRate, timeScaleChanged = targetRate, true
            if state.status == 'playing' then startMusicSubtitle(state, sound) end
            if AUDIO.BroadcastMusicState then AUDIO.BroadcastMusicState(busId, publicMusicState(state)) end
        end
        if state.status == 'playing' and sound and not state.loop and sound.duration
            and musicPosition(state) >= sound.duration then AUDIO.StopMusic(busId, 0) end
    end
    if timeScaleChanged and AUDIO.BroadcastStateDelta then
        AUDIO.BroadcastStateDelta('timescale', nil, timeScale)
    end
end

function AUDIO.Start()
    if not timer.Exists(AUDIO.TimerName) then timer.Create(AUDIO.TimerName, AUDIO.TickInterval, 0, AUDIO.Tick) end
    for id, group in pairs(AUDIO.Catalog.soundscapeGroups) do
        if AUDIO.SoundscapeStates[id] == nil and group.defaultState then AUDIO.SetSoundscapeState(id, group.defaultState) end
    end
    return true
end

function AUDIO.Reset(reason)
    for busId in pairs(table.Copy(AUDIO.MusicStates)) do AUDIO.StopMusic(busId, 0) end
    for channelId in pairs(AUDIO.PAStates) do AUDIO.ClearPAChannel(channelId, reason or 'audio reset') end
    for _, instance in pairs(table.Copy(AUDIO.AmbientInstances)) do stopInstance(instance) end
    for id in pairs(table.Copy(AUDIO.SubtitleInstances)) do AUDIO.StopSubtitle(id) end
    for id in pairs(AUDIO.Catalog.soundscapeGroups or {}) do AUDIO.SetSoundscapeState(id, nil) end
    AUDIO.MusicStates, AUDIO.MusicBusVolumes, AUDIO.PAStates, AUDIO.AmbientInstances,
        AUDIO.SubtitleInstances, AUDIO.SoundscapeStates = {}, {}, {}, {}, {}, {}
    if timer.Exists(AUDIO.TimerName) then timer.Remove(AUDIO.TimerName) end
    if AUDIO.BroadcastReset then AUDIO.BroadcastReset(reason) end
    return true
end

AUDIO.Start()
