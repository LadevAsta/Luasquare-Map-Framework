LUASQUARE_TIMELINE = LUASQUARE_TIMELINE or {}
local TIMELINE = LUASQUARE_TIMELINE

function TIMELINE.NormalizeId(value)
    if value == nil then return nil end
    value = string.lower(tostring(value))
    value = string.gsub(value, '[^%w_%.%-:]', '_')
    if value == '' then return nil end
    return value
end

function TIMELINE.DeepCopy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        out[TIMELINE.DeepCopy(key, seen)] = TIMELINE.DeepCopy(item, seen)
    end
    return out
end

function TIMELINE.Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function TIMELINE.IsSafePath(path)
    if type(path) ~= 'string' or path == '' then return false end
    local normalized = string.gsub(path, '\\', '/')
    if string.find(normalized, '%.%.', 1, false) then return false end
    if string.sub(normalized, 1, 1) == '/' then return false end
    if string.find(normalized, ':', 1, true) then return false end
    if string.find(normalized, '[%z\1-\31]') then return false end
    return true
end

function TIMELINE.IsRunning(run)
    return run and (run.status == 'running' or run.status == 'paused')
end

function TIMELINE.Ease(curve, fraction)
    fraction = TIMELINE.Clamp(fraction, 0, 1)
    curve = string.lower(tostring(curve or 'linear'))
    if curve == 'smoothstep' then return fraction * fraction * (3 - 2 * fraction) end
    if curve == 'ease_in' or curve == 'easein' then return fraction * fraction end
    if curve == 'ease_out' or curve == 'easeout' then
        local inverse = 1 - fraction
        return 1 - inverse * inverse
    end
    if curve == 'ease_in_out' or curve == 'easeinout' then
        if fraction < 0.5 then return 2 * fraction * fraction end
        local inverse = -2 * fraction + 2
        return 1 - inverse * inverse * 0.5
    end
    return fraction
end

function TIMELINE.AddDiagnostic(diagnostics, severity, path, message)
    table.insert(diagnostics, {
        severity = severity or 'error',
        path = tostring(path or '$'),
        message = tostring(message or 'unknown diagnostic')
    })
end

function TIMELINE.HasErrors(diagnostics)
    for _, diagnostic in ipairs(diagnostics or {}) do
        if diagnostic.severity == 'error' then return true end
    end
    return false
end

function TIMELINE.DiagnosticsText(diagnostics)
    local lines = {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        table.insert(lines, string.format('[%s] %s: %s',
            string.upper(diagnostic.severity or 'error'),
            tostring(diagnostic.path or '$'),
            tostring(diagnostic.message or '')))
    end
    return #lines > 0 and table.concat(lines, '\n') or 'Valid timeline source.'
end

function TIMELINE.CanonicalJSON(source, pretty)
    if not util or not util.TableToJSON then return nil end
    return util.TableToJSON(source, pretty ~= false)
end

function TIMELINE.MakeTarget(value)
    if value == nil or value == 'self' or value == '$self' then return {kind = 'self'} end
    if type(value) == 'string' then
        return {kind = 'component', id = TIMELINE.NormalizeId(value)}
    end
    if type(value) ~= 'table' then return nil end
    if value.kind then
        local kind = string.lower(tostring(value.kind))
        if kind == 'self' then return {kind = 'self'} end
        if kind == 'component' or kind == 'child' or kind == 'resolver' then
            local id = TIMELINE.NormalizeId(value.id)
            return id and {kind = kind, id = id} or nil
        end
        return nil
    end
    if value.self then return {kind = 'self'} end
    if value.component then
        return {kind = 'component', id = TIMELINE.NormalizeId(value.component)}
    end
    if value.child then
        return {kind = 'child', id = TIMELINE.NormalizeId(value.child)}
    end
    if value.resolver then
        return {kind = 'resolver', id = TIMELINE.NormalizeId(value.resolver)}
    end
    return nil
end

function TIMELINE.SimulateSource(compiled, playhead, mutedTracks)
    playhead = math.max(tonumber(playhead) or 0, 0)
    mutedTracks = mutedTracks or {}
    local result = {time = playhead, clips = {}, events = {}, values = {}}
    if type(compiled) ~= 'table' then return result end
    for _, clip in ipairs(compiled.clips or {}) do
        local track = compiled.tracks and compiled.tracks[clip.trackIndex]
        local muted = mutedTracks[clip.trackIndex] or mutedTracks[tostring(clip.trackIndex)]
            or (track and mutedTracks[track.id])
        local state = {status = muted and 'muted' or 'pending'}
        if not muted and playhead >= clip.at then
            if clip.kind == 'duration' then
                state.status = playhead < clip.endsAt and 'active' or 'completed'
                state.fraction = clip.duration <= 0 and 1
                    or TIMELINE.Clamp((playhead - clip.at) / clip.duration, 0, 1)
            elseif clip.kind == 'number' then
                local fraction = clip.duration <= 0 and 1
                    or TIMELINE.Clamp((playhead - clip.at) / clip.duration, 0, 1)
                state.fraction = fraction
                state.value = clip.from + (clip.to - clip.from) * TIMELINE.Ease(clip.curve, fraction)
                state.status = fraction < 1 and 'active' or 'completed'
                result.values[clip.id] = state.value
            else
                state.status = 'completed'
            end
            table.insert(result.events, {
                clipId = clip.id,
                trackId = track and track.id,
                kind = clip.kind,
                status = state.status,
                value = state.value
            })
        end
        result.clips[clip.id] = state
    end
    return result
end
