LUASQUARE_AUDIO = LUASQUARE_AUDIO or {}
local AUDIO = LUASQUARE_AUDIO

function AUDIO.NormalizeId(value)
    if value == nil then return nil end
    value = string.lower(tostring(value))
    value = string.gsub(value, '[^%w_%.%-:]', '_')
    return value ~= '' and value or nil
end

function AUDIO.DeepCopy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do out[AUDIO.DeepCopy(key, seen)] = AUDIO.DeepCopy(item, seen) end
    return out
end

function AUDIO.Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    return math.min(math.max(value, minimum), maximum)
end

function AUDIO.IsSafePath(path)
    if type(path) ~= 'string' or path == '' then return false end
    path = string.gsub(path, '\\', '/')
    if string.sub(path, 1, 1) == '/' or string.find(path, ':', 1, true)
        or string.find(path, '%.%.', 1, false) or string.find(path, '[%z\1-\31]') then return false end
    return true
end

function AUDIO.AddDiagnostic(diagnostics, severity, path, message, origin)
    table.insert(diagnostics, {
        severity = severity or 'error', path = tostring(path or '$'),
        message = tostring(message or 'unknown error'), origin = origin
    })
end

function AUDIO.HasErrors(diagnostics)
    for _, diagnostic in ipairs(diagnostics or {}) do
        if diagnostic.severity == 'error' then return true end
    end
    return false
end

function AUDIO.DiagnosticsText(diagnostics)
    local lines = {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        table.insert(lines, string.format('[%s] %s%s: %s',
            string.upper(diagnostic.severity or 'error'),
            diagnostic.origin and (diagnostic.origin .. ' ') or '',
            diagnostic.path or '$', diagnostic.message or ''))
    end
    return #lines > 0 and table.concat(lines, '\n') or 'Valid audio source.'
end

function AUDIO.ColorTable(value, fallback)
    fallback = fallback or {255, 255, 255, 255}
    if type(value) ~= 'table' then return AUDIO.DeepCopy(fallback) end
    return {
        math.floor(AUDIO.Clamp(value[1] or value.r or fallback[1], 0, 255)),
        math.floor(AUDIO.Clamp(value[2] or value.g or fallback[2], 0, 255)),
        math.floor(AUDIO.Clamp(value[3] or value.b or fallback[3], 0, 255)),
        math.floor(AUDIO.Clamp(value[4] or value.a or fallback[4] or 255, 0, 255))
    }
end

function AUDIO.CanonicalJSON(source, pretty)
    return util and util.TableToJSON and util.TableToJSON(source, pretty ~= false) or nil
end

AUDIO.SourceCategories = AUDIO.SourceCategories or {
    'sounds', 'subtitles', 'subtitleStyles', 'musicBuses',
    'paLines', 'paChannels', 'soundscapeGroups'
}

local sharedFolderCategories = {
    sounds = {sounds = true, musicBuses = true},
    subtitles = {subtitles = true},
    subtitle_styles = {subtitleStyles = true},
    pa_lines = {paLines = true}
}

function AUDIO.NormalizeSourceTables(source)
    if type(source) ~= 'table' then return source end
    for _, category in ipairs(AUDIO.SourceCategories) do
        if type(source[category]) ~= 'table' then source[category] = {} end
    end
    return source
end

function AUDIO.GetSharedPathInfo(path)
    local normalized = string.lower(string.gsub(tostring(path or ''), '\\', '/'))
    local namespace, folder = string.match(normalized, '/_shared/([^/]+)/([^/]+)/')
    if namespace and sharedFolderCategories[folder] then
        return {namespace = namespace, folder = folder,
            allowed = sharedFolderCategories[folder], legacy = false}
    end
    folder = string.match(normalized, '/_shared/([^/]+)/')
    if folder and sharedFolderCategories[folder] then
        return {namespace = 'legacy', folder = folder,
            allowed = sharedFolderCategories[folder], legacy = true}
    end
    return nil
end
