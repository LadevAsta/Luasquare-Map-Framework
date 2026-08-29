if not CLIENT then return end
local AUDIO, EDITOR = LUASQUARE_AUDIO, LUASQUARE_AUDIO.Editor

local function newLines()
    return EDITOR.LoadMasterSource('pa_lines')
end

local function newChannels()
    return {schema = AUDIO.Schema, id = game.GetMap() .. '_pa_channels', label = 'Map PA channels', paChannels = {}}
end

local function workingSource(workspace)
    local editor = AUDIO.SubtitleSequenceEditor
    return IsValid(editor) and editor.WorkspaceSessions and editor.WorkspaceSessions[workspace]
        and editor.WorkspaceSessions[workspace].source or nil
end

local function definitions(tableName, working)
    local out = table.Copy((AUDIO.ClientCatalog and AUDIO.ClientCatalog[tableName]) or {})
    for id, definition in pairs(EDITOR.GetSharedDefinitions(tableName, working)) do out[id] = definition end
    return out
end

local function soundDefinition(id)
    return definitions('sounds')[AUDIO.NormalizeId(id)]
end

local function soundDuration(id)
    local sound = soundDefinition(id)
    return sound and (tonumber(sound.duration) or 0) * 100 / math.max(tonumber(sound.pitch) or 100, 1) or 0
end

local function lineDuration(line)
    local duration = 0
    for _, clip in ipairs(line.clips or {}) do duration = math.max(duration, (clip.at or 0) + soundDuration(clip.sound)) end
    return duration
end

local function stopPreview(frame)
    frame.Simulating = false
    for _, handle in ipairs(frame.PreviewSounds or {}) do EDITOR.StopLocalSound(handle) end
    frame.PreviewSounds = {}
    AUDIO.ClientClearSubtitlePreviews()
end

local function previewSound(frame, soundId, offset, subtitle)
    local sound = soundDefinition(soundId)
    if not sound then return end
    local actualSource = frame.ActualSourcePreview and sound.mode ~= 'music'
    offset = actualSource and 0 or math.max(tonumber(offset) or 0, 0)
    local rate = math.max((sound.pitch or 100) / 100, 0.001)
    local mediaOffset = offset * rate
    EDITOR.PlayLocalSound(sound, function(ok, handle) if ok then table.insert(frame.PreviewSounds, handle) end end,
        {seekable = not actualSource, startTime = mediaOffset})
    if subtitle == false then return end
    for sequenceId, sequence in pairs(definitions('subtitles', workingSource('sequences'))) do
        if sequence.sound == soundId then
            local ok, id = AUDIO.ClientPreviewSubtitleSequence(sequence,
                {offset = mediaOffset, playbackRate = rate,
                    styles = definitions('subtitleStyles', workingSource('styles'))})
            if ok then frame.LastSubtitlePreview = id end
            break
        end
    end
end

local function startLinePreview(frame, line)
    local startAt = frame.ActualSourcePreview and 0 or math.max(frame.PAPlayhead or 0, 0)
    if frame.ActualSourcePreview then frame.PAPlayhead = 0 end
    stopPreview(frame) frame.PreviewSounds, frame.SimStarted, frame.FiredClips = {}, RealTime() - startAt, {}
    local intro = line.introTone
    if intro == nil then intro = frame.PreviewChannel and frame.PreviewChannel.introTone end
    frame.IntroDuration = intro and soundDuration(intro) or 0
    if intro and startAt < frame.IntroDuration then previewSound(frame, intro, startAt, false) end
    frame.Simulating, frame.SimLine = true, line
end

local function pauseLinePreview(frame)
    if frame.Simulating then frame.PAPlayhead = math.max(RealTime() - frame.SimStarted, 0) end
    stopPreview(frame)
end

local function mutate(frame, callback, rebuild)
    EDITOR.Push(frame.Session) callback() frame.Session.dirty = true if rebuild then frame:Rebuild() end
end

local function subtitleSpans(line, introDuration)
    local bySound, spans = {}, {}
    for sequenceId, sequence in pairs(definitions('subtitles', workingSource('sequences'))) do
        if sequence.sound then bySound[sequence.sound] = {id = sequenceId, value = sequence} end
    end
    for clipIndex, clip in ipairs(line.clips or {}) do
        local entry, sound = bySound[clip.sound], soundDefinition(clip.sound)
        if entry and sound then
            local rate = math.max((tonumber(sound.pitch) or 100) / 100, 0.001)
            for chunkIndex, chunk in ipairs(entry.value.chunks or {}) do
                table.insert(spans, {clip = clipIndex, chunk = chunkIndex, sequenceId = entry.id,
                    id = chunk.id, at = introDuration + (clip.at or 0) + (chunk.at or 0) / rate,
                    duration = (chunk.duration or 0) / rate})
            end
        end
    end
    table.sort(spans, function(a, b) return a.at == b.at and (a.clip == b.clip and a.chunk < b.chunk or a.clip < b.clip) or a.at < b.at end)
    local ends, maximumLane = {}, 1
    for _, span in ipairs(spans) do
        local lane = 1 while ends[lane] and ends[lane] > span.at + 0.0001 do lane = lane + 1 end
        span.lane, ends[lane], maximumLane = lane, span.at + span.duration, math.max(maximumLane, lane)
    end
    return spans, maximumLane
end

local function addLineTimeline(frame, parent, line)
    frame.PAZoom, frame.PASnap, frame.PAScroll = frame.PAZoom or 80, frame.PASnap or 0.1, frame.PAScroll or 0
    local controls = vgui.Create('DPanel', parent) controls:Dock(TOP) controls:SetTall(32)
    local play = vgui.Create('DButton', controls) play:Dock(LEFT) play:SetWide(105) play:SetText('Preview locally')
    play.DoClick = function() startLinePreview(frame, line) end
    local stop = vgui.Create('DButton', controls) stop:Dock(LEFT) stop:SetWide(70) stop:SetText('Stop')
    stop.DoClick = function() stopPreview(frame) frame.PAPlayhead = 0 end
    local add = vgui.Create('DButton', controls) add:Dock(LEFT) add:SetWide(90) add:SetText('Add clip')
    add.DoClick = function()
        mutate(frame, function()
            line.clips = line.clips or {} local used = {}
            for _, clip in ipairs(line.clips) do used[clip.id] = true end
            table.insert(line.clips, {id = EDITOR.UniqueId(used, 'clip'), at = 0, sound = ''})
            frame.SelectedClip = #line.clips
        end, true)
    end
    EDITOR.AddCompactNumber(controls, 'Zoom', frame.PAZoom, 30, 200, 0,
        function(value) frame.PAZoom = value end, 180)
    EDITOR.AddCompactNumber(controls, 'Snap', frame.PASnap, 0.01, 2, 2,
        function(value) frame.PASnap = value end, 180)
    local initialIntro = line.introTone
    if initialIntro == nil then initialIntro = frame.PreviewChannel and frame.PreviewChannel.introTone end
    local initialIntroDuration = initialIntro and soundDuration(initialIntro) or 0
    local _, subtitleLaneCount = subtitleSpans(line, initialIntroDuration)
    local timeline = vgui.Create('DPanel', parent) timeline:Dock(TOP) timeline:SetTall(135 + subtitleLaneCount * 28)
    timeline.Paint = function(self, width, height)
        local zoom, scroll = frame.PAZoom or 80, frame.PAScroll or 0
        surface.SetDrawColor(17, 21, 25) surface.DrawRect(0, 0, width, height)
        local intro = line.introTone
        if intro == nil then intro = frame.PreviewChannel and frame.PreviewChannel.introTone end
        local introDuration = intro and soundDuration(intro) or 0
        for second = math.floor(scroll), math.ceil(introDuration + lineDuration(line) + 2) do
            local x = 100 + (second - scroll) * zoom
            surface.SetDrawColor(55, 60, 65) surface.DrawLine(x, 0, x, height)
            draw.SimpleText(second .. 's', 'DermaDefault', x + 2, 3, Color(200, 200, 200))
        end
        draw.SimpleText('INTRO', 'DermaDefaultBold', 7, 39, color_white)
        draw.SimpleText('BODY', 'DermaDefaultBold', 7, 91, color_white)
        draw.SimpleText('SUBTITLES', 'DermaDefaultBold', 7, 132, color_white)
        if introDuration > 0 then
            local introX = 100 - scroll * zoom
            surface.SetDrawColor(205, 145, 55) surface.DrawRect(introX, 29, introDuration * zoom, 34)
            draw.SimpleText(intro, 'DermaDefault', introX + 4, 39, color_white)
        elseif line.introTone == false then draw.SimpleText('SKIPPED', 'DermaDefault',
            104 - scroll * zoom, 39, Color(150, 150, 150)) end
        self.ClipRects = {}
        for index, clip in ipairs(line.clips or {}) do
            local x = 100 + (introDuration + (clip.at or 0) - scroll) * zoom
            local w = math.max(soundDuration(clip.sound) * zoom, 12)
            surface.SetDrawColor(frame.SelectedClip == index and Color(230, 170, 55) or Color(110, 75, 180))
            surface.DrawRect(x, 81, w, 38) draw.SimpleText(clip.id or index, 'DermaDefault', x + 4, 92, color_white)
            self.ClipRects[index] = {x = x, y = 81, w = w, h = 38, intro = introDuration}
        end
        local spans = subtitleSpans(line, introDuration)
        for _, span in ipairs(spans) do
            local x = 100 + (span.at - scroll) * zoom
            local y, w = 124 + (span.lane - 1) * 28, math.max(span.duration * zoom, 8)
            surface.SetDrawColor(42, 145, 120) surface.DrawRect(x, y, w, 22)
            surface.SetDrawColor(135, 230, 205) surface.DrawOutlinedRect(x, y, w, 22, 1)
            draw.SimpleText(span.id or span.sequenceId, 'DermaDefault', x + 3, y + 4, color_white)
        end
        local current = frame.Simulating and (RealTime() - frame.SimStarted) or frame.PAPlayhead or 0
        local cursor = 100 + (current - scroll) * zoom
        surface.SetDrawColor(255, 80, 65) surface.DrawLine(cursor, 0, cursor, height)
    end
    timeline.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end self:RequestFocus() local x, y = self:LocalCursorPos()
        for index = #(self.ClipRects or {}), 1, -1 do
            local rect = self.ClipRects[index]
            if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
                frame.SelectedClip = index frame.PAClipDrag = {index = index, startX = x,
                    at = line.clips[index].at or 0, snapshot = table.Copy(frame.Session.source), moved = false}
                self:MouseCapture(true) return
            end
        end
        frame.PAPlayheadDrag = true frame.PAPlayhead = math.max((x - 100) / (frame.PAZoom or 80)
            + (frame.PAScroll or 0), 0)
        self:MouseCapture(true)
    end
    timeline.OnCursorMoved = function(self, x)
        if frame.PAPlayheadDrag then
            frame.PAPlayhead = math.max((x - 100) / (frame.PAZoom or 80)
                + (frame.PAScroll or 0), 0) return
        end
        local drag = frame.PAClipDrag
        if not drag then return end
        local snap = frame.PASnap or 0.1
        line.clips[drag.index].at = math.max(math.Round((drag.at
            + (x - drag.startX) / (frame.PAZoom or 80)) / snap) * snap, 0)
        frame.Session.dirty, drag.moved = true, true
    end
    timeline.OnMouseReleased = function(self, code)
        if code ~= MOUSE_LEFT then return end
        if frame.PAClipDrag and frame.PAClipDrag.moved then
            table.insert(frame.Session.history, frame.PAClipDrag.snapshot) frame.Session.future = {}
        end
        local shouldRebuild = frame.PAClipDrag ~= nil
        frame.PAClipDrag, frame.PAPlayheadDrag = nil, nil self:MouseCapture(false)
        if shouldRebuild then frame:Rebuild() end
    end
    timeline.OnMouseWheeled = function(_, delta)
        local maximum = timeline.MaximumScroll and timeline.MaximumScroll() or math.huge
        frame.PAScroll = math.Clamp((frame.PAScroll or 0) - delta * 0.5, 0, maximum)
        return true
    end
    timeline:SetKeyboardInputEnabled(true)
    timeline.OnKeyCodePressed = function(_, key) if frame.OnKeyCodePressed then frame:OnKeyCodePressed(key) end end
    timeline.Think = function()
        if not frame.Simulating or not frame.SimLine then return end
        frame.PAPlayhead = math.max(RealTime() - frame.SimStarted, 0)
        local elapsed = RealTime() - frame.SimStarted - frame.IntroDuration
        if elapsed < 0 then return end
        for index, clip in ipairs(frame.SimLine.clips or {}) do
            if not frame.FiredClips[index] and elapsed >= (clip.at or 0) then
                frame.FiredClips[index] = true
                local offset = elapsed - (clip.at or 0)
                if offset < soundDuration(clip.sound) then previewSound(frame, clip.sound, offset) end
            end
        end
        if elapsed >= lineDuration(frame.SimLine) then frame.Simulating = false end
    end
    local function visibleSeconds()
        return math.max((timeline:GetWide() - 100) / math.max(frame.PAZoom or 80, 1), 0.1)
    end
    local function totalDuration()
        local silence = frame.PreviewChannel and tonumber(frame.PreviewChannel.silenceSeconds) or 2
        return initialIntroDuration + lineDuration(line) + math.max(silence or 0, 0)
    end
    local function maximumScroll() return math.max(totalDuration() - visibleSeconds(), 0) end
    timeline.MaximumScroll = maximumScroll
    EDITOR.AddTimelineScrollbar(parent,
        function() return frame.PAScroll or 0 end,
        function(value) frame.PAScroll = value end,
        maximumScroll,
        visibleSeconds)
end

local function linesBody(frame, panel)
    local split = vgui.Create('DHorizontalDivider', panel) split:Dock(FILL) split:SetDividerWidth(5) split:SetLeftWidth(300)
    local left, right = vgui.Create('DPanel', split), vgui.Create('DScrollPanel', split) split:SetLeft(left) split:SetRight(right)
    local add = vgui.Create('DButton', left) add:Dock(TOP) add:SetText('Add PA line')
    local list = vgui.Create('DListView', left) list:Dock(FILL) list:AddColumn('PA line ID')
    for _, id in ipairs(EDITOR.SortedIds(frame.Session.source.paLines)) do
        local row = list:AddLine(id) row.ItemId = id if frame.Session.selected == id then list:SelectItem(row) end
    end
    add.DoClick = function()
        EDITOR.Mutate(frame, function(source)
            local id = EDITOR.UniqueId(source.paLines, 'new_pa_line')
            source.paLines[id] = {label = 'New PA line', clips = {}} frame.Session.selected = id
        end)
    end
    list.OnRowSelected = function(_, _, row) stopPreview(frame) frame.Session.selected = row.ItemId frame.SelectedClip = nil frame:Rebuild() end
    local line = frame.Session.source.paLines[frame.Session.selected or '']
    if not line then EDITOR.AddLabel(right, 'Select or add a PA line.') return end
    EDITOR.AddLabel(right, 'SHARED PA LINE · ' .. frame.Session.selected)
    local lineId = frame.Session.selected
    EDITOR.AddText(right, 'PA line ID', lineId, function(value)
        local newId = AUDIO.NormalizeId(value)
        if not newId or (newId ~= lineId and frame.Session.source.paLines[newId]) then return end
        EDITOR.Mutate(frame, function(source)
            source.paLines[newId], source.paLines[lineId] = source.paLines[lineId], nil
            frame.Session.selected = newId
        end)
    end)
    local channelIds = EDITOR.SortedIds(AUDIO.ClientCatalog.paChannels or {})
    if #channelIds > 0 then
        local currentChannel = frame.PreviewChannelId or channelIds[1]
        frame.PreviewChannelId, frame.PreviewChannel = currentChannel,
            AUDIO.ClientCatalog.paChannels[currentChannel]
        EDITOR.AddChoice(right, 'Simulation channel', currentChannel, channelIds, function(value)
            frame.PreviewChannelId, frame.PreviewChannel = value, AUDIO.ClientCatalog.paChannels[value]
            frame:Rebuild()
        end)
    end
    EDITOR.AddText(right, 'Label', line.label, function(value) mutate(frame, function() line.label = value end) end)
    EDITOR.AddChoice(right, 'Intro behavior', line.introTone == false and 'skip' or line.introTone and 'override' or 'inherit',
        {'inherit', 'override', 'skip'}, function(value)
            mutate(frame, function() line.introTone = value == 'skip' and false or value == 'override' and '' or nil end, true)
        end)
    if type(line.introTone) == 'string' then
        EDITOR.AddText(right, 'Override intro sound ID', line.introTone, function(value)
            mutate(frame, function() line.introTone = AUDIO.NormalizeId(value) or value end)
        end)
        local pickIntro = vgui.Create('DButton', right) pickIntro:Dock(TOP) pickIntro:DockMargin(6, 0, 6, 4)
        pickIntro:SetText('Search intro sounds...') pickIntro.DoClick = function()
            EDITOR.OpenIdPicker('Select intro sound', definitions('sounds'), function(soundId)
                mutate(frame, function() line.introTone = soundId end, true)
            end, function(sound) return sound.mode == 'source' or sound.mode == 'global' end)
        end
    end
    addLineTimeline(frame, right, line)
    local clip = line.clips and line.clips[frame.SelectedClip]
    if clip then
        EDITOR.AddLabel(right, 'CLIP · ' .. tostring(clip.id))
        EDITOR.AddText(right, 'Clip ID', clip.id, function(value) mutate(frame, function() clip.id = AUDIO.NormalizeId(value) or clip.id end, true) end)
        EDITOR.AddNumber(right, 'Start after intro (seconds)', clip.at or 0, 0, 3600, 3,
            function(value) mutate(frame, function() clip.at = value end) end)
        EDITOR.AddText(right, 'Registered sound ID', clip.sound, function(value)
            mutate(frame, function() clip.sound = AUDIO.NormalizeId(value) or value end)
        end)
        local pickSound = vgui.Create('DButton', right) pickSound:Dock(TOP) pickSound:DockMargin(6, 0, 6, 4)
        pickSound:SetText('Search registered sounds...') pickSound.DoClick = function()
            EDITOR.OpenIdPicker('Select PA clip sound', definitions('sounds'), function(soundId)
                mutate(frame, function() clip.sound = soundId end, true)
            end, function(sound) return sound.mode == 'source' or sound.mode == 'global' end)
        end
        local remove = vgui.Create('DButton', right) remove:Dock(TOP) remove:DockMargin(6, 6, 6, 3)
        remove:SetText('Delete clip') remove.DoClick = function()
            EDITOR.Mutate(frame, function() table.remove(line.clips, frame.SelectedClip) frame.SelectedClip = nil end)
        end
        local duplicate = vgui.Create('DButton', right) duplicate:Dock(TOP) duplicate:DockMargin(6, 1, 6, 4)
        duplicate:SetText('Duplicate clip') duplicate.DoClick = function()
            EDITOR.Mutate(frame, function()
                local copy = table.Copy(clip) local used = {}
                for _, existing in ipairs(line.clips) do used[existing.id] = true end
                copy.id, copy.at = EDITOR.UniqueId(used, clip.id), (clip.at or 0) + (frame.PASnap or 0.1)
                table.insert(line.clips, copy) frame.SelectedClip = #line.clips
            end)
        end
    end
    EDITOR.AddLabel(right, string.format('Derived body duration: %.3f seconds', lineDuration(line)))
    EDITOR.AddCheck(right, 'Use actual client-local Source playback (not seekable)', frame.ActualSourcePreview, function(value)
        pauseLinePreview(frame) frame.ActualSourcePreview = value
    end)
    EDITOR.AddLabel(right,
        'Local preview is a client-only simulation. It never enqueues the server PA channel or fires a timeline component.')
    EDITOR.AddLabel(right, 'Space: play/pause    Shift+Space: play from 0s')
    local sequenceBySound, styles = {}, definitions('subtitleStyles', workingSource('styles'))
    for sequenceId, sequence in pairs(definitions('subtitles', workingSource('sequences'))) do
        if sequence.sound then sequenceBySound[sequence.sound] = {id = sequenceId, value = sequence} end
    end
    for _, item in ipairs(line.clips or {}) do
        if not soundDefinition(item.sound) then
            EDITOR.AddLabel(right, 'MISSING SOUND: ' .. tostring(item.sound))
        else
            local linked = sequenceBySound[item.sound]
            if linked then
                local defaultStyle = linked.value.style or 'default'
                if not styles[defaultStyle] and defaultStyle ~= 'default' then
                    EDITOR.AddLabel(right, 'MISSING SUBTITLE STYLE: ' .. defaultStyle .. ' (' .. linked.id .. ')')
                end
                for _, chunk in ipairs(linked.value.chunks or {}) do
                    if chunk.style and not styles[chunk.style] then
                        EDITOR.AddLabel(right, 'MISSING SUBTITLE STYLE: ' .. chunk.style .. ' (' .. linked.id .. ')')
                    end
                end
            end
        end
    end
    local deleteLine = vgui.Create('DButton', right) deleteLine:Dock(TOP) deleteLine:DockMargin(6, 8, 6, 4)
    deleteLine:SetText('Delete PA line') deleteLine.DoClick = function()
        stopPreview(frame)
        EDITOR.Mutate(frame, function(source) source.paLines[lineId] = nil frame.Session.selected = nil end)
    end
end

local function emittersEditor(frame, parent, channel)
    EDITOR.AddLabel(parent, 'EMITTERS')
    for index, emitter in ipairs(channel.emitters or {}) do
        local text = emitter.global and 'Global' or emitter.targetname and ('Target: ' .. emitter.targetname)
            or emitter.position and string.format('Position: %g %g %g', emitter.position[1] or 0,
                emitter.position[2] or 0, emitter.position[3] or 0) or 'Invalid emitter'
        local button = vgui.Create('DButton', parent) button:Dock(TOP) button:DockMargin(6, 1, 6, 1)
        button:SetText(text .. '   [remove]') button.DoClick = function()
            EDITOR.Mutate(frame, function() table.remove(channel.emitters, index) end)
        end
    end
    local target = vgui.Create('DButton', parent) target:Dock(TOP) target:DockMargin(6, 4, 6, 1) target:SetText('Add targetname emitter')
    target.DoClick = function()
        Derma_StringRequest('Targetname emitter', 'Map targetname', '', function(value)
            EDITOR.Mutate(frame, function() channel.emitters = channel.emitters or {} table.insert(channel.emitters, {targetname = value}) end)
        end)
    end
    local position = vgui.Create('DButton', parent) position:Dock(TOP) position:DockMargin(6, 1, 6, 1) position:SetText('Add position emitter')
    position.DoClick = function()
        Derma_StringRequest('Position emitter', 'Space-separated X Y Z', '0 0 0', function(value)
            local x, y, z = string.match(value, '^%s*([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)%s*$')
            if not x then return end
            EDITOR.Mutate(frame, function() channel.emitters = channel.emitters or {}
                table.insert(channel.emitters, {position = {tonumber(x), tonumber(y), tonumber(z)}}) end)
        end)
    end
    local global = vgui.Create('DButton', parent) global:Dock(TOP) global:DockMargin(6, 1, 6, 4) global:SetText('Add global emitter')
    global.DoClick = function() EDITOR.Mutate(frame, function()
        channel.emitters = channel.emitters or {} table.insert(channel.emitters, {global = true})
    end) end
end

local function channelsBody(frame, panel)
    local split = vgui.Create('DHorizontalDivider', panel) split:Dock(FILL) split:SetDividerWidth(5) split:SetLeftWidth(300)
    local left, right = vgui.Create('DPanel', split), vgui.Create('DScrollPanel', split) split:SetLeft(left) split:SetRight(right)
    local add = vgui.Create('DButton', left) add:Dock(TOP) add:SetText('Add map channel')
    local list = vgui.Create('DListView', left) list:Dock(FILL) list:AddColumn('Channel ID')
    for _, id in ipairs(EDITOR.SortedIds(frame.Session.source.paChannels)) do
        local row = list:AddLine(id) row.ItemId = id if frame.Session.selected == id then list:SelectItem(row) end
    end
    add.DoClick = function()
        EDITOR.Mutate(frame, function(source)
            local id = EDITOR.UniqueId(source.paChannels, 'new_channel')
            source.paChannels[id] = {label = 'New channel', maxQueue = 16, silenceSeconds = 2,
                hearingRadius = 0, emitters = {}} frame.Session.selected = id
        end)
    end
    list.OnRowSelected = function(_, _, row) frame.Session.selected = row.ItemId frame:Rebuild() end
    local channel = frame.Session.source.paChannels[frame.Session.selected or '']
    if not channel then EDITOR.AddLabel(right, 'Select or add a map PA channel.') return end
    EDITOR.AddLabel(right, 'MAP PA CHANNEL · ' .. frame.Session.selected)
    local channelId = frame.Session.selected
    EDITOR.AddText(right, 'Channel ID', channelId, function(value)
        local newId = AUDIO.NormalizeId(value)
        if not newId or (newId ~= channelId and frame.Session.source.paChannels[newId]) then return end
        EDITOR.Mutate(frame, function(source)
            source.paChannels[newId], source.paChannels[channelId] = source.paChannels[channelId], nil
            frame.Session.selected = newId
        end)
    end)
    EDITOR.AddText(right, 'Label', channel.label, function(value) mutate(frame, function() channel.label = value end) end)
    EDITOR.AddText(right, 'Default intro sound (optional)', channel.introTone, function(value)
        mutate(frame, function() channel.introTone = value ~= '' and (AUDIO.NormalizeId(value) or value) or nil end)
    end)
    EDITOR.AddText(right, 'Interruption sound (optional)', channel.interruptTone, function(value)
        mutate(frame, function() channel.interruptTone = value ~= '' and (AUDIO.NormalizeId(value) or value) or nil end)
    end)
    EDITOR.AddNumber(right, 'Queue size', channel.maxQueue or 16, 1, 128, 0,
        function(value) mutate(frame, function() channel.maxQueue = math.floor(value) end) end)
    EDITOR.AddNumber(right, 'Post-line silence', channel.silenceSeconds or 2, 0, 30, 2,
        function(value) mutate(frame, function() channel.silenceSeconds = value end) end)
    EDITOR.AddNumber(right, 'Hearing radius (0 = PAS)', channel.hearingRadius or 0, 0, 32768, 0,
        function(value) mutate(frame, function() channel.hearingRadius = value end) end)
    emittersEditor(frame, right, channel)
    local deleteChannel = vgui.Create('DButton', right) deleteChannel:Dock(TOP)
    deleteChannel:DockMargin(6, 8, 6, 4) deleteChannel:SetText('Delete channel')
    deleteChannel.DoClick = function()
        EDITOR.Mutate(frame, function(source) source.paChannels[channelId] = nil frame.Session.selected = nil end)
    end
end

local function body(frame, panel)
    if frame.Mode == 'channels' then channelsBody(frame, panel) else linesBody(frame, panel) end
end

function AUDIO.OpenPAEditor()
    if IsValid(AUDIO.PAEditor) then AUDIO.PAEditor:MakePopup() return AUDIO.PAEditor end
    EDITOR.RefreshSharedPool()
    local frame = EDITOR.BuildFrame('Luasquare PA Line and Channel Editor', newLines(), 'pa_lines', false, body)
    frame:SetSize(ScrW(), math.floor(ScrH() * 0.5)) frame:SetPos(0, 0)
    local baseSetSource = frame.SetSource
    frame.SetSource = function(self, ...)
        stopPreview(self)
        return baseSetSource(self, ...)
    end
    frame.Mode = 'lines'
    local lines = vgui.Create('DButton', frame.Toolbar) lines:Dock(RIGHT) lines:SetWide(110) lines:SetText('Shared lines')
    local channels = vgui.Create('DButton', frame.Toolbar) channels:Dock(RIGHT) channels:SetWide(120) channels:SetText('Map channels')
    local function switch(mode)
        EDITOR.ConfirmDiscard(frame.Session, function()
            stopPreview(frame) frame.Mode = mode
            if mode == 'channels' then frame:SetSource(newChannels(), nil, false, 'channels', true)
            else frame:SetSource(newLines(), nil, false, 'pa_lines', false) end
        end)
    end
    lines.DoClick = function() switch('lines') end channels.DoClick = function() switch('channels') end
    frame.OnKeyCodePressed = function(self, key)
        if key ~= KEY_SPACE or self.Mode ~= 'lines' then return end
        local line = self.Session.source.paLines[self.Session.selected or '']
        if not line then return end
        local shift = _G.input.IsKeyDown(KEY_LSHIFT) or _G.input.IsKeyDown(KEY_RSHIFT)
        if shift then
            pauseLinePreview(self) self.PAPlayhead = 0 startLinePreview(self, line)
        elseif self.Simulating then pauseLinePreview(self)
        else startLinePreview(self, line) end
    end
    frame.NewSource = function(self)
        if self.Mode == 'channels' then self:SetSource(newChannels(), nil, false, 'channels', true)
        else self:SetSource(EDITOR.NewMasterSource('pa_lines'), nil, false, 'pa_lines', false) end
    end
    frame.OnRemove = function(self) stopPreview(self) end
    AUDIO.PAEditor = frame return frame
end
