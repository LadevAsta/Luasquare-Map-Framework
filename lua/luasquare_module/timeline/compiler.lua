LUASQUARE_TIMELINE = LUASQUARE_TIMELINE or {}
local TIMELINE = LUASQUARE_TIMELINE

local clipKinds = {marker = true, duration = true, number = true, timeline = true}
local curves = {
    linear = true,
    smoothstep = true,
    ease_in = true,
    ease_out = true,
    ease_in_out = true,
    easein = true,
    easeout = true,
    easeinout = true
}
local lifecycleKeys = {
    startGuard = true,
    runGuard = true,
    onStart = true,
    onCancel = true,
    onComplete = true
}

local function nonNegative(value, fallback)
    return math.max(tonumber(value) or fallback or 0, 0)
end

local function compileTarget(value, path, diagnostics)
    local target = TIMELINE.MakeTarget(value)
    if not target or not target.kind or (target.kind ~= 'self' and not target.id) then
        TIMELINE.AddDiagnostic(diagnostics, 'error', path, 'invalid component target')
        return {kind = 'self'}
    end
    return target
end

local function compileClip(source, track, trackIndex, clipIndex, ids, diagnostics)
    local path = string.format('tracks[%d].clips[%d]', trackIndex, clipIndex)
    if type(source) ~= 'table' then
        TIMELINE.AddDiagnostic(diagnostics, 'error', path, 'clip must be an object')
        return nil
    end
    local id = TIMELINE.NormalizeId(source.id) or ('clip_' .. trackIndex .. '_' .. clipIndex)
    if ids[id] then TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.id', 'duplicate clip id: ' .. id) end
    ids[id] = true
    local kind = string.lower(tostring(source.kind or 'marker'))
    if not clipKinds[kind] then
        TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.kind', 'unknown clip kind: ' .. kind)
        kind = 'marker'
    end
    local clip = {
        id = id,
        label = tostring(source.label or id),
        kind = kind,
        at = nonNegative(source.at),
        duration = nonNegative(source.duration),
        required = source.required and true or false,
        minimumSuccess = math.max(math.floor(tonumber(source.minimumSuccess) or 0), 0),
        target = compileTarget(source.target or track.target, path .. '.target', diagnostics),
        params = type(source.params) == 'table' and TIMELINE.DeepCopy(source.params) or {},
        metadata = type(source.metadata) == 'table' and TIMELINE.DeepCopy(source.metadata) or {},
        trackIndex = trackIndex,
        clipIndex = clipIndex
    }
    if kind == 'timeline' then
        clip.timeline = TIMELINE.NormalizeId(source.timeline)
        if not clip.timeline then
            TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.timeline', 'child timeline id is required')
        end
    else
        clip.action = TIMELINE.NormalizeId(source.action)
        if not clip.action then
            TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.action', 'component action id is required')
        end
    end
    if kind == 'number' then
        clip.from = tonumber(source.from)
        clip.to = tonumber(source.to)
        if clip.from == nil then TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.from', 'numeric start value is required') end
        if clip.to == nil then TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.to', 'numeric end value is required') end
        clip.curve = string.lower(tostring(source.curve or 'linear'))
        if not curves[clip.curve] then
            TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.curve', 'unsupported curve: ' .. clip.curve)
            clip.curve = 'linear'
        end
    end
    clip.endsAt = clip.at + clip.duration
    return clip
end

function TIMELINE.CompileSource(source, origin)
    local diagnostics = {}
    origin = tostring(origin or 'memory')
    if type(source) ~= 'table' then
        TIMELINE.AddDiagnostic(diagnostics, 'error', '$', 'timeline source must be an object')
        return nil, diagnostics
    end
    if source.schema ~= TIMELINE.Schema then
        TIMELINE.AddDiagnostic(diagnostics, 'error', 'schema',
            'unsupported schema; expected ' .. TIMELINE.Schema)
    end
    local id = TIMELINE.NormalizeId(source.id)
    if not id then TIMELINE.AddDiagnostic(diagnostics, 'error', 'id', 'stable timeline id is required') end
    local compiled = {
        schema = TIMELINE.Schema,
        id = id or 'invalid',
        label = tostring(source.label or id or 'Timeline'),
        channel = TIMELINE.NormalizeId(source.channel) or 'default',
        conflictPolicy = string.lower(tostring(source.conflictPolicy or 'reject')),
        restartPolicy = string.lower(tostring(source.restartPolicy or 'reject')),
        cancelChildrenOnComplete = source.cancelChildrenOnComplete ~= false,
        duration = nonNegative(source.duration),
        lifecycle = {},
        tracks = {},
        clips = {},
        editor = type(source.editor) == 'table' and TIMELINE.DeepCopy(source.editor) or {},
        origin = origin,
        source = TIMELINE.DeepCopy(source)
    }
    if compiled.conflictPolicy ~= 'reject' and compiled.conflictPolicy ~= 'replace'
        and compiled.conflictPolicy ~= 'ignore' then
        TIMELINE.AddDiagnostic(diagnostics, 'error', 'conflictPolicy', 'must be reject, replace, or ignore')
    end
    if compiled.restartPolicy ~= 'reject' and compiled.restartPolicy ~= 'restart'
        and compiled.restartPolicy ~= 'ignore' then
        TIMELINE.AddDiagnostic(diagnostics, 'error', 'restartPolicy', 'must be reject, restart, or ignore')
    end
    for key, value in pairs(source.lifecycle or {}) do
        if not lifecycleKeys[key] then
            TIMELINE.AddDiagnostic(diagnostics, 'error', 'lifecycle.' .. tostring(key), 'unknown lifecycle phase')
        elseif type(value) ~= 'string' or not TIMELINE.NormalizeId(value) then
            TIMELINE.AddDiagnostic(diagnostics, 'error', 'lifecycle.' .. key, 'handler id must be a string')
        else
            compiled.lifecycle[key] = TIMELINE.NormalizeId(value)
        end
    end
    local audio = compiled.editor.referenceAudio
    if audio ~= nil then
        if type(audio) ~= 'table' then
            TIMELINE.AddDiagnostic(diagnostics, 'error', 'editor.referenceAudio', 'must be an object')
            compiled.editor.referenceAudio = nil
        elseif not TIMELINE.IsSafePath(audio.path) then
            TIMELINE.AddDiagnostic(diagnostics, 'error', 'editor.referenceAudio.path', 'unsafe audio path')
        else
            audio.path = string.gsub(audio.path, '\\', '/')
            audio.timelineStartSeconds = tonumber(audio.timelineStartSeconds) or 0
            audio.volume = TIMELINE.Clamp(audio.volume or 1, 0, 1)
        end
    end
    local trackIds = {}
    local clipIds = {}
    for trackIndex, sourceTrack in ipairs(source.tracks or {}) do
        local path = 'tracks[' .. trackIndex .. ']'
        if type(sourceTrack) ~= 'table' then
            TIMELINE.AddDiagnostic(diagnostics, 'error', path, 'track must be an object')
        else
            local trackId = TIMELINE.NormalizeId(sourceTrack.id) or ('track_' .. trackIndex)
            if trackIds[trackId] then
                TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.id', 'duplicate track id: ' .. trackId)
            end
            trackIds[trackId] = true
            local track = {
                id = trackId,
                label = tostring(sourceTrack.label or trackId),
                target = compileTarget(sourceTrack.target, path .. '.target', diagnostics),
                order = trackIndex,
                clips = {}
            }
            for clipIndex, sourceClip in ipairs(sourceTrack.clips or {}) do
                local clip = compileClip(sourceClip, track, trackIndex, clipIndex, clipIds, diagnostics)
                if clip then
                    table.insert(track.clips, clip)
                    table.insert(compiled.clips, clip)
                    compiled.duration = math.max(compiled.duration, clip.endsAt)
                end
            end
            table.insert(compiled.tracks, track)
        end
    end
    table.sort(compiled.clips, function(a, b)
        if a.at ~= b.at then return a.at < b.at end
        if a.trackIndex ~= b.trackIndex then return a.trackIndex < b.trackIndex end
        return a.clipIndex < b.clipIndex
    end)
    if TIMELINE.HasErrors(diagnostics) then return nil, diagnostics end
    return compiled, diagnostics
end

function TIMELINE.DecodeSource(json, origin)
    if type(json) ~= 'string' or json == '' or not util or not util.JSONToTable then
        return nil, {{severity = 'error', path = '$', message = 'empty or unavailable JSON input'}}
    end
    local source = util.JSONToTable(json)
    if type(source) ~= 'table' then
        return nil, {{severity = 'error', path = '$', message = 'malformed JSON'}}
    end
    return TIMELINE.CompileSource(source, origin)
end
