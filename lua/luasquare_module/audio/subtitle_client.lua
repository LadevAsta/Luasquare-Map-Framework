if not CLIENT then return end
LUASQUARE_AUDIO = LUASQUARE_AUDIO or {}
local AUDIO = LUASQUARE_AUDIO

AUDIO.ClientSubtitleGroups = AUDIO.ClientSubtitleGroups or {}
AUDIO.ClientSubtitles = AUDIO.ClientSubtitleGroups
local fontCache, previewSerial = {}, 0
local FADE_SECONDS, SLIDE_PIXELS = 0.25, 12

local function settingBool(name, fallback)
    local convar = GetConVar(name)
    return convar and convar:GetBool() or fallback
end

local function copy(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, child in pairs(value) do out[key] = copy(child) end
    return out
end

local function mergedStyle(sequence, chunk, overrideStyles)
    local styles = overrideStyles or AUDIO.ClientCatalog.subtitleStyles or {}
    local style = copy(styles[AUDIO.NormalizeId(chunk.style or sequence.style or 'default')]
        or styles.default or {color = {255, 255, 255, 255}, speakerColor = {150, 205, 255, 255},
            font = 'Roboto', size = 24, weight = 500, glitch = {enabled = false}})
    for _, field in ipairs({'color', 'speakerColor', 'font', 'size', 'weight', 'glitch'}) do
        if chunk[field] ~= nil then style[field] = copy(chunk[field]) end
    end
    return style
end

local function drawColor(value, alpha)
    value = value or {255, 255, 255, 255}
    return Color(value[1] or 255, value[2] or 255, value[3] or 255,
        math.floor((value[4] or 255) * alpha))
end

local function fontFor(style)
    local key = tostring(style.font) .. ':' .. tostring(style.size) .. ':' .. tostring(style.weight)
    if fontCache[key] then return fontCache[key] end
    local name = 'LUASQUARE_AUDIO_Subtitle_' .. util.CRC(key)
    surface.CreateFont(name, {font = style.font or 'Roboto', size = style.size or 24,
        weight = style.weight or 500, antialias = true, extended = true})
    fontCache[key] = name
    return name
end

local function wrapText(text, font, maximum)
    surface.SetFont(font)
    local lines, line = {}, ''
    for word in string.gmatch(tostring(text or ''), '%S+') do
        local candidate = line == '' and word or (line .. ' ' .. word)
        if surface.GetTextSize(candidate) > maximum and line ~= '' then
            table.insert(lines, line) line = word
        else line = candidate end
    end
    if line ~= '' then table.insert(lines, line) end
    if #lines == 0 then table.insert(lines, '') end
    return lines
end

local function trimGroupLimit()
    local convar = GetConVar('luasquare_audio_subtitle_max')
    local maximum = math.Clamp(convar and convar:GetInt() or 3, 1, 3)
    local active = 0
    for index = #AUDIO.ClientSubtitleGroups, 1, -1 do
        local group = AUDIO.ClientSubtitleGroups[index]
        if not group.endingAt then
            active = active + 1
            if active > maximum then group.endingAt = RealTime() end
        end
    end
end

function AUDIO.ClientStartSubtitleGroup(options)
    options = options or {}
    if not settingBool('luasquare_audio_subtitles_enabled', true) then return false end
    local definition = options.definition
        or (AUDIO.ClientCatalog.subtitles or {})[AUDIO.NormalizeId(options.subtitleId)]
    if type(definition) ~= 'table' or type(definition.chunks) ~= 'table' then return false end
    definition = copy(definition)
    if not tonumber(definition.duration) or definition.duration <= 0 then
        definition.duration = 0
        for _, chunk in ipairs(definition.chunks) do
            definition.duration = math.max(definition.duration,
                (tonumber(chunk.at) or 0) + (tonumber(chunk.duration) or 0))
        end
    end
    local group = {
        id = tostring(options.id or ('local:' .. tostring(SysTime()))),
        subtitleId = options.subtitleId or definition.id, definition = definition,
        startedAt = tonumber(options.startedAt) or CurTime(),
        playbackRate = math.max(tonumber(options.playbackRate) or 1, 0.001),
        offset = math.max(tonumber(options.offset) or 0, 0),
        bornAt = RealTime(), chunkStates = {}, preview = options.preview and true or false,
        styles = options.styles and copy(options.styles) or nil
    }
    for index, chunk in ipairs(group.definition.chunks) do
        group.chunkStates[index] = {definition = chunk}
    end
    table.insert(AUDIO.ClientSubtitleGroups, group)
    trimGroupLimit()
    return true, group.id
end

function AUDIO.ClientStopSubtitleGroup(id)
    id = tostring(id or '')
    for _, group in ipairs(AUDIO.ClientSubtitleGroups) do
        if group.id == id and not group.endingAt then
            group.endingAt = RealTime()
            for _, state in ipairs(group.chunkStates) do
                if state.active and not state.endingAt then state.endingAt = RealTime() end
            end
            return true
        end
    end
    return false
end

function AUDIO.ClientPreviewSubtitleSequence(definition, options)
    options = options or {}
    previewSerial = previewSerial + 1
    return AUDIO.ClientStartSubtitleGroup({id = 'editor:' .. previewSerial,
        subtitleId = definition.id, definition = definition,
        startedAt = CurTime(), offset = tonumber(options.offset) or 0,
        playbackRate = options.playbackRate, styles = options.styles, preview = true})
end

function AUDIO.ClientClearSubtitlePreviews()
    for _, group in ipairs(AUDIO.ClientSubtitleGroups) do
        if group.preview and not group.endingAt then AUDIO.ClientStopSubtitleGroup(group.id) end
    end
end

function AUDIO.ClientClearSubtitles()
    AUDIO.ClientSubtitleGroups = {}
    AUDIO.ClientSubtitles = AUDIO.ClientSubtitleGroups
end
AUDIO.ClientAddSubtitle = AUDIO.ClientStartSubtitleGroup
AUDIO.ClientStopSubtitle = AUDIO.ClientStopSubtitleGroup

local function mediaTime(group)
    return group.offset + math.max(CurTime() - group.startedAt, 0) * group.playbackRate
end

local function updateGroups()
    local currentReal = RealTime()
    for _, group in ipairs(AUDIO.ClientSubtitleGroups) do
        local elapsed = mediaTime(group)
        if not group.endingAt then
            for _, state in ipairs(group.chunkStates) do
                local chunk = state.definition
                if not state.started and elapsed >= chunk.at then
                    state.started, state.active, state.bornAt = true, true, currentReal
                end
                if state.active and not state.endingAt and elapsed >= chunk.at + chunk.duration then
                    state.endingAt = currentReal
                end
                if state.endingAt and (chunk.fadeEnabled == false
                    or currentReal - state.endingAt >= FADE_SECONDS) then state.active = false end
            end
            if elapsed >= (group.definition.duration or 0) then
                group.endingAt = currentReal
            end
        end
    end
    for index = #AUDIO.ClientSubtitleGroups, 1, -1 do
        local group = AUDIO.ClientSubtitleGroups[index]
        if group.endingAt and currentReal - group.endingAt >= FADE_SECONDS then
            table.remove(AUDIO.ClientSubtitleGroups, index)
        end
    end
end

local function stateDuckFactor(group, state)
    if group.endingAt or not state.active or state.endingAt then return 1 end
    local chunk, sequence = state.definition, group.definition
    local enabled = chunk.duckMusic
    if enabled == nil then enabled = sequence.duckMusic end
    if not enabled then return 1 end
    local amount = chunk.duckAmount
    if amount == nil then amount = sequence.duckAmount end
    return 1 - math.Clamp(tonumber(amount) or 0.45, 0, 1)
end

function AUDIO.GetSubtitleDuckFactor()
    if not settingBool('luasquare_audio_ducking_enabled', true) then return 1 end
    local factor = 1
    for _, group in ipairs(AUDIO.ClientSubtitleGroups) do
        for _, state in ipairs(group.chunkStates) do factor = math.min(factor, stateDuckFactor(group, state)) end
    end
    return factor
end

local function drawGlitchText(text, font, x, y, foreground, style)
    local glitch = style.glitch or {}
    local offsetX, offsetY = 0, 0
    if glitch.enabled then
        local seed = math.floor(RealTime() / math.max(glitch.interval or 0.06, 0.02))
        local intensity = glitch.intensity or 1
        offsetX = util.SharedRandom('luaudio_x' .. seed .. text, -intensity, intensity)
        offsetY = util.SharedRandom('luaudio_y' .. seed .. text, -intensity, intensity)
        draw.SimpleText(text, font, x - 1 + offsetX, y,
            Color(255, 50, 70, foreground.a * 0.45), TEXT_ALIGN_LEFT)
        draw.SimpleText(text, font, x + 1 - offsetX, y,
            Color(40, 190, 255, foreground.a * 0.45), TEXT_ALIGN_LEFT)
    end
    draw.SimpleText(text, font, x + offsetX, y + offsetY, foreground, TEXT_ALIGN_LEFT)
end

local function layoutGroup(group, width)
    local chunks, height = {}, 10
    for _, state in ipairs(group.chunkStates) do
        if state.active then
            local chunk, style = state.definition, mergedStyle(group.definition, state.definition, group.styles)
            local font = fontFor(style)
            local speaker = chunk.speaker
            if speaker == nil then speaker = group.definition.speaker end
            local prefix = speaker and speaker ~= '' and ('[' .. speaker .. ']: ') or ''
            surface.SetFont(font)
            local prefixWidth = surface.GetTextSize(prefix)
            local lines = wrapText(chunk.text, font, width - 36 - math.min(prefixWidth, width * 0.35))
            local lineHeight = (style.size or 24) + 4
            local fadeEnabled = chunk.fadeEnabled ~= false
            local fadeIn = fadeEnabled and math.Clamp((RealTime() - (state.bornAt or RealTime())) / FADE_SECONDS, 0, 1) or 1
            local fadeOut = fadeEnabled and state.endingAt
                and 1 - math.Clamp((RealTime() - state.endingAt) / FADE_SECONDS, 0, 1) or 1
            table.insert(chunks, {style = style, font = font, prefix = prefix,
                prefixWidth = prefixWidth, lines = lines, lineHeight = lineHeight,
                alpha = fadeIn * fadeOut, fadeIn = fadeIn, fadeOut = fadeOut})
            height = height + #lines * lineHeight + 4
        end
    end
    if #chunks == 0 then return nil end
    local alpha = 0
    for _, chunk in ipairs(chunks) do alpha = math.max(alpha, chunk.alpha) end
    return {group = group, chunks = chunks, height = height, alpha = alpha}
end

hook.Add('HUDPaint', 'LUASQUARE_AUDIO_SubtitleHUD', function()
    updateGroups()
    if not settingBool('luasquare_audio_subtitles_enabled', true) then return end
    local width = math.min(math.floor(ScrW() * 0.62), 1000)
    local layouts, totalHeight = {}, 0
    for _, group in ipairs(AUDIO.ClientSubtitleGroups) do
        local layout = layoutGroup(group, width)
        if layout then table.insert(layouts, layout) totalHeight = totalHeight + layout.height + 8 end
    end
    if #layouts == 0 then return end
    local x, y = math.floor((ScrW() - width) * 0.5), math.floor(ScrH() * 0.78 - totalHeight)
    for _, layout in ipairs(layouts) do
        local entranceAlpha = math.Clamp((RealTime() - (layout.group.bornAt or RealTime())) / FADE_SECONDS, 0, 1)
        local boxAlpha = entranceAlpha * layout.alpha
        local boxY = y + (1 - boxAlpha) * SLIDE_PIXELS
        surface.SetDrawColor(5, 8, 12, math.floor(205 * boxAlpha))
        surface.DrawRect(x, boxY, width, layout.height)
        surface.SetDrawColor(90, 160, 210, math.floor(210 * boxAlpha))
        surface.DrawOutlinedRect(x, boxY, width, layout.height, 1)
        local textY = boxY + 5
        for _, item in ipairs(layout.chunks) do
            local alpha = item.alpha * entranceAlpha
            local textX = x + 18
            if item.prefix ~= '' then
                drawGlitchText(item.prefix, item.font, textX, textY,
                    drawColor(item.style.speakerColor, alpha), item.style)
            end
            for lineIndex, line in ipairs(item.lines) do
                local lineX = textX + (lineIndex == 1 and item.prefixWidth or 0)
                drawGlitchText(line, item.font, lineX,
                    textY + (lineIndex - 1) * item.lineHeight,
                    drawColor(item.style.color, alpha), item.style)
            end
            textY = textY + #item.lines * item.lineHeight + 4
        end
        y = y + layout.height + 8
    end
end)
