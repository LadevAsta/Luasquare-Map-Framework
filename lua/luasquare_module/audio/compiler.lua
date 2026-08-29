LUASQUARE_AUDIO = LUASQUARE_AUDIO or {}
local AUDIO = LUASQUARE_AUDIO

local extensions = {wav = true, mp3 = true, ogg = true}
local soundModes = {music = true, source = true, global = true}
local channels = {auto = true, weapon = true, voice = true, item = true, body = true, stream = true, static = true}

local function object(value) return type(value) == 'table' and value or {} end

local function compileEmitters(values, path, diagnostics, origin)
    local emitters = {}
    for index, value in ipairs(values or {}) do
        local at = path .. '[' .. index .. ']'
        if type(value) ~= 'table' then
            AUDIO.AddDiagnostic(diagnostics, 'error', at, 'emitter must be an object', origin)
        elseif value.global then
            table.insert(emitters, {kind = 'global'})
        elseif type(value.targetname) == 'string' and value.targetname ~= ''
            and not string.find(value.targetname, '[%z\1-\31]') then
            table.insert(emitters, {kind = 'targetname', targetname = value.targetname})
        elseif type(value.position) == 'table' and tonumber(value.position[1])
            and tonumber(value.position[2]) and tonumber(value.position[3]) then
            table.insert(emitters, {kind = 'position', position = {
                tonumber(value.position[1]), tonumber(value.position[2]), tonumber(value.position[3])
            }})
        else
            AUDIO.AddDiagnostic(diagnostics, 'error', at, 'emitter needs global, targetname, or xyz position', origin)
        end
    end
    return emitters
end

local function compileSounds(values, diagnostics, origin)
    local out = {}
    for rawId, value in pairs(object(values)) do
        local id = AUDIO.NormalizeId(rawId)
        local path = 'sounds.' .. tostring(rawId)
        if not id or type(value) ~= 'table' then
            AUDIO.AddDiagnostic(diagnostics, 'error', path, 'invalid sound definition', origin)
        else
            local isSoundScript = type(value.script) == 'string' and value.script ~= ''
            local soundPath = string.gsub(tostring(isSoundScript and value.script or value.path or ''), '\\', '/')
            if isSoundScript and value.path ~= nil then
                AUDIO.AddDiagnostic(diagnostics, 'error', path,
                    'sound definition must use either path or script, not both', origin)
            end
            local extension = string.lower(string.match(soundPath, '%.([%w]+)$') or '')
            local invalidFile = not isSoundScript and (not extensions[extension]
                or string.sub(string.lower(soundPath), 1, 6) == 'sound/')
            local invalidScript = isSoundScript and (string.find(soundPath, '/', 1, true)
                or not string.match(soundPath, '^[%w_%.%-]+$'))
            if not AUDIO.IsSafePath(soundPath) or invalidFile or invalidScript then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. (isSoundScript and '.script' or '.path'),
                    'unsafe or unsupported sound path', origin)
            end
            local mode = string.lower(tostring(value.mode or 'source'))
            if not soundModes[mode] then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.mode', 'mode must be music, source, or global', origin)
                mode = 'source'
            end
            if isSoundScript and mode ~= 'source' and mode ~= 'global' then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.mode',
                    'sound scripts can only use Source or global playback', origin)
            end
            if value.emitters ~= nil then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.emitters',
                    'sound emitters are no longer supported; put emitters on a PA channel or pass them at runtime', origin)
            end
            if value.subtitle ~= nil then
                AUDIO.AddDiagnostic(diagnostics, 'warning', path .. '.subtitle',
                    'legacy sound subtitle link loaded; new sources declare the sound on the subtitle sequence', origin)
            end
            local channel = string.lower(tostring(value.channel or (mode == 'music' and 'stream' or 'auto')))
            if not channels[channel] then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.channel', 'unsupported channel name', origin)
                channel = 'auto'
            end
            local duration = tonumber(value.duration)
            if value.duration ~= nil and (not duration or duration <= 0) then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.duration',
                    'duration must be a positive number', origin)
                duration = nil
            end
            if not isSoundScript and (not duration or duration <= 0) and SERVER and SoundDuration
                and (extension == 'wav' or extension == 'mp3') then
                local measured = tonumber(SoundDuration(soundPath)) or 0
                if measured > 0 then duration = measured end
            end
            local musicBuses = {}
            for _, busId in ipairs(value.musicBuses or {}) do
                local normalized = AUDIO.NormalizeId(busId)
                if normalized then table.insert(musicBuses, normalized) end
            end
            out[id] = {
                id = id, label = tostring(value.label or rawId), path = soundPath,
                soundScript = isSoundScript, mode = mode,
                volume = AUDIO.Clamp(value.volume or 1, 0, 1), pitch = math.floor(AUDIO.Clamp(value.pitch or 100, 1, 255)),
                soundLevel = math.floor(AUDIO.Clamp(value.soundLevel or 75, 0, 511)),
                dsp = math.floor(AUDIO.Clamp(value.dsp or 1, 0, 133)), channel = channel,
                loop = value.loop and true or false,
                musicBuses = musicBuses,
                duration = duration and AUDIO.Clamp(duration, 0.01, 86400) or nil,
                legacySubtitle = AUDIO.NormalizeId(value.subtitle),
                hearingRadius = value.hearingRadius ~= nil and AUDIO.Clamp(value.hearingRadius, 0, 50000) or nil,
                _origin = origin
            }
            if not out[id].duration then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.duration',
                    'sound requires a measurable or explicit duration', origin)
            end
        end
    end
    return out
end

local function compileStyles(values, diagnostics, origin)
    local out = {}
    for rawId, value in pairs(object(values)) do
        local id = AUDIO.NormalizeId(rawId)
        if id and type(value) == 'table' then
            local glitch = object(value.glitch)
            out[id] = {
                id = id, label = tostring(value.label or rawId),
                color = AUDIO.ColorTable(value.color), speakerColor = AUDIO.ColorTable(value.speakerColor, {150, 205, 255, 255}),
                font = tostring(value.font or 'Roboto'), size = math.floor(AUDIO.Clamp(value.size or 24, 12, 72)),
                weight = math.floor(AUDIO.Clamp(value.bold and 800 or value.weight or 500, 100, 1000)),
                glitch = {enabled = glitch.enabled and true or false,
                    intensity = AUDIO.Clamp(glitch.intensity or 1, 0, 4), interval = AUDIO.Clamp(glitch.interval or 0.06, 0.02, 1)},
                _origin = origin
            }
        else
            AUDIO.AddDiagnostic(diagnostics, 'error', 'subtitleStyles.' .. tostring(rawId), 'invalid style', origin)
        end
    end
    return out
end

local function compileSubtitles(values, diagnostics, origin)
    local out = {}
    for rawId, value in pairs(object(values)) do
        local id = AUDIO.NormalizeId(rawId)
        local path = 'subtitles.' .. tostring(rawId)
        if not id or type(value) ~= 'table' then
            AUDIO.AddDiagnostic(diagnostics, 'error', path, 'invalid subtitle sequence', origin)
        else
            local legacy = type(value.text) == 'string' and value.chunks == nil
            local rawChunks = value.chunks
            if legacy then
                AUDIO.AddDiagnostic(diagnostics, 'warning', path,
                    'legacy single-text subtitle migrated to one timed chunk', origin)
                rawChunks = {{id = 'line', at = 0, duration = value.duration, text = value.text,
                    speaker = value.speaker, style = value.style, duckMusic = value.duckMusic,
                    duckAmount = value.duckAmount}}
            end
            local chunks, chunkIds, maximumEnd = {}, {}, 0
            if type(rawChunks) ~= 'table' or #rawChunks == 0 then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.chunks',
                    'subtitle sequence requires at least one chunk', origin)
            elseif #rawChunks > 128 then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.chunks',
                    'subtitle sequence exceeds the 128 chunk limit', origin)
            else
                for index, chunk in ipairs(rawChunks) do
                    local chunkPath = path .. '.chunks[' .. index .. ']'
                    local chunkId = type(chunk) == 'table' and AUDIO.NormalizeId(chunk.id or ('chunk_' .. index)) or nil
                    local at = type(chunk) == 'table' and tonumber(chunk.at) or nil
                    local duration = type(chunk) == 'table' and tonumber(chunk.duration) or nil
                    local text = type(chunk) == 'table' and chunk.text or nil
                    if not chunkId or chunkIds[chunkId] then
                        AUDIO.AddDiagnostic(diagnostics, 'error', chunkPath .. '.id', 'missing or duplicate chunk id', origin)
                    elseif not at or at < 0 then
                        AUDIO.AddDiagnostic(diagnostics, 'error', chunkPath .. '.at', 'chunk time must be zero or greater', origin)
                    elseif not duration or duration <= 0 then
                        AUDIO.AddDiagnostic(diagnostics, 'error', chunkPath .. '.duration', 'chunk duration must be positive', origin)
                    elseif type(text) ~= 'string' or text == '' then
                        AUDIO.AddDiagnostic(diagnostics, 'error', chunkPath .. '.text', 'chunk text is required', origin)
                    else
                        chunkIds[chunkId] = true
                        local glitch = type(chunk.glitch) == 'table' and chunk.glitch or nil
                        local compiled = {
                            id = chunkId, at = AUDIO.Clamp(at, 0, 86400),
                            duration = AUDIO.Clamp(duration, 0.02, 3600), text = string.sub(text, 1, 2048),
                            speaker = chunk.speaker ~= nil and string.sub(tostring(chunk.speaker), 1, 128) or nil,
                            style = chunk.style ~= nil and (AUDIO.NormalizeId(chunk.style) or 'default') or nil,
                            color = chunk.color and AUDIO.ColorTable(chunk.color) or nil,
                            speakerColor = chunk.speakerColor and AUDIO.ColorTable(chunk.speakerColor) or nil,
                            font = chunk.font ~= nil and tostring(chunk.font) or nil,
                            size = chunk.size ~= nil and math.floor(AUDIO.Clamp(chunk.size, 12, 72)) or nil,
                            weight = chunk.weight ~= nil and math.floor(AUDIO.Clamp(chunk.weight, 100, 1000)) or nil,
                            duckMusic = chunk.duckMusic,
                            duckAmount = chunk.duckAmount ~= nil and AUDIO.Clamp(chunk.duckAmount, 0, 1) or nil,
                            fadeEnabled = chunk.fadeEnabled ~= false,
                            glitch = glitch and {enabled = glitch.enabled and true or false,
                                intensity = AUDIO.Clamp(glitch.intensity or 1, 0, 4),
                                interval = AUDIO.Clamp(glitch.interval or 0.06, 0.02, 1)} or nil,
                            _order = index
                        }
                        maximumEnd = math.max(maximumEnd, compiled.at + compiled.duration)
                        table.insert(chunks, compiled)
                    end
                end
            end
            table.sort(chunks, function(a, b) return a.at == b.at and a._order < b._order or a.at < b.at end)
            out[id] = {
                id = id, label = tostring(value.label or rawId), sound = AUDIO.NormalizeId(value.sound),
                speaker = string.sub(tostring(value.speaker or ''), 1, 128),
                style = AUDIO.NormalizeId(value.style) or 'default',
                duckMusic = value.duckMusic ~= false, duckAmount = AUDIO.Clamp(value.duckAmount or 0.45, 0, 1),
                chunks = chunks, duration = maximumEnd, legacy = legacy, _origin = origin
            }
            if not out[id].sound and not legacy then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.sound',
                    'subtitle sequence must name its registered sound', origin)
            end
        end
    end
    return out
end

local function compilePALines(values, diagnostics, origin)
    local out = {}
    for rawId, value in pairs(object(values)) do
        local id = AUDIO.NormalizeId(rawId)
        local path = 'paLines.' .. tostring(rawId)
        if not id or type(value) ~= 'table' then
            AUDIO.AddDiagnostic(diagnostics, 'error', path, 'invalid PA line', origin)
        else
            local introTone
            if value.introTone == false then introTone = false
            elseif value.introTone ~= nil then
                introTone = AUDIO.NormalizeId(value.introTone)
                if not introTone then AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.introTone', 'invalid intro tone id', origin) end
            end
            local clips, clipIds = {}, {}
            if type(value.clips) ~= 'table' or #value.clips == 0 then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.clips', 'PA line requires at least one sound clip', origin)
            elseif #value.clips > 128 then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.clips', 'PA line exceeds the 128 clip limit', origin)
            else
                for index, clip in ipairs(value.clips) do
                    local clipPath = path .. '.clips[' .. index .. ']'
                    local clipId = type(clip) == 'table' and AUDIO.NormalizeId(clip.id or ('clip_' .. index)) or nil
                    local at = type(clip) == 'table' and tonumber(clip.at) or nil
                    local sound = type(clip) == 'table' and AUDIO.NormalizeId(clip.sound) or nil
                    if not clipId or clipIds[clipId] then
                        AUDIO.AddDiagnostic(diagnostics, 'error', clipPath .. '.id', 'missing or duplicate clip id', origin)
                    elseif not at or at < 0 then
                        AUDIO.AddDiagnostic(diagnostics, 'error', clipPath .. '.at', 'clip time must be zero or greater', origin)
                    elseif not sound then
                        AUDIO.AddDiagnostic(diagnostics, 'error', clipPath .. '.sound', 'clip sound id is required', origin)
                    else
                        clipIds[clipId] = true
                        table.insert(clips, {id = clipId, at = AUDIO.Clamp(at, 0, 86400),
                            sound = sound, _order = index})
                    end
                end
            end
            table.sort(clips, function(a, b) return a.at == b.at and a._order < b._order or a.at < b.at end)
            out[id] = {id = id, label = tostring(value.label or rawId), introTone = introTone,
                clips = clips, duration = 0, _origin = origin}
        end
    end
    return out
end

local function compileMusicBuses(values, diagnostics, origin)
    local out = {}
    for rawId, value in pairs(object(values)) do
        local id = AUDIO.NormalizeId(rawId)
        if id and type(value) == 'table' then
            out[id] = {id = id, label = tostring(value.label or rawId), volume = AUDIO.Clamp(value.volume or 1, 0, 1), _origin = origin}
        else AUDIO.AddDiagnostic(diagnostics, 'error', 'musicBuses.' .. tostring(rawId), 'invalid music bus', origin) end
    end
    return out
end

local function compilePA(values, diagnostics, origin)
    local out = {}
    for rawId, value in pairs(object(values)) do
        local id = AUDIO.NormalizeId(rawId)
        local path = 'paChannels.' .. tostring(rawId)
        if id and type(value) == 'table' then
            out[id] = {
                id = id, label = tostring(value.label or rawId), introTone = AUDIO.NormalizeId(value.introTone),
                interruptTone = AUDIO.NormalizeId(value.interruptTone), silenceSeconds = AUDIO.Clamp(value.silenceSeconds or 2, 0, 30),
                maxQueue = math.floor(AUDIO.Clamp(value.maxQueue or 16, 1, 64)),
                hearingRadius = value.hearingRadius ~= nil and AUDIO.Clamp(value.hearingRadius, 0, 50000) or nil,
                emitters = compileEmitters(value.emitters, path .. '.emitters', diagnostics, origin), _origin = origin
            }
        else AUDIO.AddDiagnostic(diagnostics, 'error', path, 'invalid PA channel', origin) end
    end
    return out
end

local function compileSoundscapeStates(values, path, diagnostics, origin)
    local states = {}
    for rawState, targets in pairs(object(values)) do
        local stateId = AUDIO.NormalizeId(rawState)
        if stateId and type(targets) == 'table' then
            states[stateId] = {}
            for _, target in ipairs(targets) do
                local validTarget = type(target) == 'string' and target ~= ''
                    and not string.find(target, '[%z\1-\31]')
                if validTarget then
                    table.insert(states[stateId], target)
                else
                    AUDIO.AddDiagnostic(diagnostics, 'error',
                        path .. '.' .. tostring(rawState), 'invalid targetname', origin)
                end
            end
            if #states[stateId] == 0 then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.' .. tostring(rawState),
                    'soundscape state requires at least one targetname', origin)
            end
        else
            AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.' .. tostring(rawState),
                'invalid soundscape state', origin)
        end
    end
    return states
end

local function compileSoundscapes(values, diagnostics, origin)
    local out = {}
    for rawId, value in pairs(object(values)) do
        local id = AUDIO.NormalizeId(rawId)
        local path = 'soundscapeGroups.' .. tostring(rawId)
        if id and type(value) == 'table' then
            local states = compileSoundscapeStates(value.states, path .. '.states', diagnostics, origin)
            out[id] = {id = id, label = tostring(value.label or rawId), states = states,
                defaultState = AUDIO.NormalizeId(value.defaultState), _origin = origin}
            if table.Count(states) == 0 then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.states',
                    'soundscape group requires at least one state', origin)
            end
            if out[id].defaultState and not states[out[id].defaultState] then
                AUDIO.AddDiagnostic(diagnostics, 'error', path .. '.defaultState', 'unknown default state', origin)
            end
        else AUDIO.AddDiagnostic(diagnostics, 'error', path, 'invalid soundscape group', origin) end
    end
    return out
end

function AUDIO.CompileSource(source, origin)
    local diagnostics = {}
    origin = tostring(origin or 'memory')
    if type(source) ~= 'table' then return nil, {{severity = 'error', path = '$', message = 'audio pack must be an object', origin = origin}} end
    source = AUDIO.NormalizeSourceTables(AUDIO.DeepCopy(source))
    if source.schema ~= AUDIO.Schema then AUDIO.AddDiagnostic(diagnostics, 'error', 'schema', 'unsupported schema', origin) end
    local id = AUDIO.NormalizeId(source.id)
    if not id then AUDIO.AddDiagnostic(diagnostics, 'error', 'id', 'pack id is required', origin) end
    local compiled = {
        schema = AUDIO.Schema, id = id or 'invalid', label = tostring(source.label or id or 'Audio pack'), origin = origin,
        sounds = compileSounds(source.sounds, diagnostics, origin),
        subtitles = compileSubtitles(source.subtitles, diagnostics, origin),
        subtitleStyles = compileStyles(source.subtitleStyles, diagnostics, origin),
        musicBuses = compileMusicBuses(source.musicBuses, diagnostics, origin),
        paLines = compilePALines(source.paLines, diagnostics, origin),
        paChannels = compilePA(source.paChannels, diagnostics, origin),
        soundscapeGroups = compileSoundscapes(source.soundscapeGroups, diagnostics, origin),
        source = AUDIO.DeepCopy(source)
    }
    if AUDIO.HasErrors(diagnostics) then return nil, diagnostics end
    return compiled, diagnostics
end

function AUDIO.DecodeSource(json, origin)
    local source = type(json) == 'string' and util.JSONToTable(json) or nil
    if type(source) ~= 'table' then return nil, {{severity = 'error', path = '$', message = 'malformed JSON', origin = origin}} end
    return AUDIO.CompileSource(source, origin)
end
