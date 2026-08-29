if not CLIENT then return end
local AUDIO, EDITOR = LUASQUARE_AUDIO, LUASQUARE_AUDIO.Editor
local RULER, TRACK, LABEL, LANE = 28, 48, 120, 42

local function newSequences() return EDITOR.LoadMasterSource('subtitles') end
local function newStyles() return EDITOR.LoadMasterSource('subtitle_styles') end

local function sequenceDuration(sequence)
    local duration = 0
    for _, chunk in ipairs(sequence.chunks or {}) do
        duration = math.max(duration, (tonumber(chunk.at) or 0) + (tonumber(chunk.duration) or 0))
    end
    return duration
end

local function shared(tableName, working)
    local values = table.Copy((AUDIO.ClientCatalog and AUDIO.ClientCatalog[tableName]) or {})
    for id, value in pairs(EDITOR.GetSharedDefinitions(tableName, working)) do values[id] = value end
    return values
end

local function linkedSound(frame, sequence)
    return shared('sounds', frame.SoundWorkingSource)[AUDIO.NormalizeId(sequence.sound)]
end

local function availableStyles(frame)
    local styleSession = frame.WorkspaceSessions and frame.WorkspaceSessions.styles
    return shared('subtitleStyles', styleSession and styleSession.source)
end

local function stopPreview(frame)
    EDITOR.StopLocalSound(frame.AudioPreview) frame.AudioPreview = nil frame.Playing = false
    for _, handle in ipairs(frame.LayerAudio or {}) do EDITOR.StopLocalSound(handle) end
    frame.LayerAudio = {}
    for _, id in ipairs(frame.LayerGroups or {}) do AUDIO.ClientStopSubtitleGroup(id) end
    frame.LayerGroups = {}
    if frame.PreviewGroup then AUDIO.ClientStopSubtitleGroup(frame.PreviewGroup) frame.PreviewGroup = nil end
end

local function startPreview(frame, sequence, layered)
    if not layered then stopPreview(frame) end
    local compiled = table.Copy(sequence) compiled.duration = sequenceDuration(sequence)
    local sound = linkedSound(frame, sequence)
    local actualSource = frame.ActualSourcePreview and sound and sound.mode ~= 'music'
    local offset = actualSource and 0 or frame.Playhead or 0
    if actualSource then frame.Playhead = 0 end
    local rate = math.max(sound and (sound.pitch or 100) / 100 or 1, 0.001)
    local ok, id = AUDIO.ClientPreviewSubtitleSequence(compiled,
        {offset = offset, playbackRate = rate, styles = availableStyles(frame)})
    if ok and not layered then frame.PreviewGroup = id end
    if ok and layered then frame.LayerGroups = frame.LayerGroups or {} table.insert(frame.LayerGroups, id) end
    if sound then
        EDITOR.PlayLocalSound(sound, function(success, handle)
            if not success then return end
            if IsValid(handle.channel) then
                handle.channel:SetPlaybackRate(rate)
            end
            if layered then
                frame.LayerAudio = frame.LayerAudio or {} table.insert(frame.LayerAudio, handle)
            else frame.AudioPreview = handle end
        end, {seekable = not actualSource, startTime = offset})
    end
    if not layered then
        frame.Playing, frame.PreviewRate = true, rate
        frame.PlayStarted = RealTime() - offset / rate
    end
end

local function pausePreview(frame)
    if frame.Playing then
        frame.Playhead = math.max((RealTime() - frame.PlayStarted) * (frame.PreviewRate or 1), 0)
    end
    stopPreview(frame)
end

local function assignLanes(chunks)
    local order, ends, lanes = {}, {}, {}
    for index, chunk in ipairs(chunks or {}) do table.insert(order, {index = index, chunk = chunk}) end
    table.sort(order, function(a, b)
        local aa, ba = tonumber(a.chunk.at) or 0, tonumber(b.chunk.at) or 0
        return aa == ba and a.index < b.index or aa < ba
    end)
    for _, entry in ipairs(order) do
        local at, lane = tonumber(entry.chunk.at) or 0, 1
        while ends[lane] and ends[lane] > at + 0.0001 do lane = lane + 1 end
        ends[lane] = at + (tonumber(entry.chunk.duration) or 0)
        lanes[entry.index] = lane
    end
    return lanes, math.max(#ends, 1)
end

local function paintTimeline(canvas, width, height)
    local frame, sequence = canvas.Editor, canvas.Sequence
    surface.SetDrawColor(18, 21, 25) surface.DrawRect(0, 0, width, height)
    local zoom, scroll = frame.Zoom or 90, frame.SubtitleScroll or 0
    local sound = linkedSound(frame, sequence)
    local duration = math.max(sound and sound.duration or 0, sequenceDuration(sequence), 5)
    for second = math.floor(scroll), math.ceil(duration) do
        local x = LABEL + (second - scroll) * zoom
        surface.SetDrawColor(55, 62, 68) surface.DrawLine(x, 0, x, height)
        draw.SimpleText(second .. 's', 'DermaDefault', x + 3, 6, Color(205, 205, 205))
    end
    surface.SetDrawColor(38, 44, 50) surface.DrawRect(0, RULER, width, TRACK)
    draw.SimpleText('SOUND', 'DermaDefaultBold', 8, RULER + 17, Color(220, 220, 220))
    if sound then
        local soundX = LABEL - scroll * zoom
        surface.SetDrawColor(85, 100, 120) surface.DrawRect(soundX, RULER + 7, sound.duration * zoom, TRACK - 14)
        draw.SimpleText(sound.label or sequence.sound, 'DermaDefault', soundX + 5, RULER + 16, color_white)
    end
    canvas.Rects = {}
    for index, chunk in ipairs(sequence.chunks or {}) do
        local x = LABEL + ((chunk.at or 0) - scroll) * zoom
        local w = math.max((chunk.duration or 0) * zoom, 10)
        local y = RULER + TRACK + ((canvas.Lanes[index] or 1) - 1) * LANE + 5
        surface.SetDrawColor(frame.SelectedChunk == index and Color(220, 165, 55) or Color(45, 135, 175))
        surface.DrawRect(x, y, w, LANE - 10)
        surface.SetDrawColor(frame.SelectedChunk == index and Color(255, 225, 130) or Color(170, 220, 245))
        surface.DrawOutlinedRect(x, y, w, LANE - 10, frame.SelectedChunk == index and 2 or 1)
        draw.SimpleText(chunk.id or index, 'DermaDefault', x + 4, y + 8, color_white)
        if frame.SelectedChunk == index then
            surface.SetDrawColor(255, 235, 155) surface.DrawRect(x + w - 4, y + 2, 6, LANE - 14)
        end
        canvas.Rects[index] = {x = x, y = y, w = w, h = LANE - 10}
    end
    local playX = LABEL + ((frame.Playhead or 0) - scroll) * zoom
    surface.SetDrawColor(255, 90, 70) surface.DrawLine(playX, 0, playX, height)
end

local function hitsAt(canvas, x, y)
    local hits = {}
    for index, rect in pairs(canvas.Rects or {}) do
        if x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then table.insert(hits, index) end
    end
    table.sort(hits, function(a, b) return a > b end)
    return hits
end

local function installTimelineInput(canvas)
    canvas.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end
        self:RequestFocus()
        local frame, x, y = self.Editor, self:LocalCursorPos()
        if y <= RULER then
            frame.DragPlayhead = true frame.Playhead = math.max((x - LABEL) / frame.Zoom + (frame.SubtitleScroll or 0), 0)
            self:MouseCapture(true) return
        end
        local selectedRect = frame.SelectedChunk and self.Rects and self.Rects[frame.SelectedChunk]
        local selectedHit = selectedRect and x >= selectedRect.x and x <= selectedRect.x + selectedRect.w
            and y >= selectedRect.y and y <= selectedRect.y + selectedRect.h
        local index
        if selectedHit then index = frame.SelectedChunk else
            local hits = hitsAt(self, x, y)
            if #hits > 0 then
                local last = frame.HitCycle
                local same = last and math.abs(last.x - x) <= 4 and math.abs(last.y - y) <= 4
                    and table.concat(last.hits, ',') == table.concat(hits, ',')
                local position = same and last.position % #hits + 1 or 1
                frame.HitCycle = {x = x, y = y, hits = hits, position = position}
                index = hits[position]
            end
        end
        if not index then return end
        local selectionChanged = frame.SelectedChunk ~= index
        frame.SelectedChunk = index
        local rect = self.Rects[index]
        frame.ChunkDrag = {index = index, resize = math.abs(x - rect.x - rect.w) <= 8,
            startX = x, at = self.Sequence.chunks[index].at, duration = self.Sequence.chunks[index].duration,
            snapshot = table.Copy(frame.Session.source), moved = false, selectionChanged = selectionChanged}
        self:MouseCapture(true)
    end
    canvas.OnCursorMoved = function(self, x, y)
        local frame = self.Editor
        if frame.DragPlayhead then
            frame.Playhead = math.max((x - LABEL) / frame.Zoom + (frame.SubtitleScroll or 0), 0) return
        end
        local drag = frame.ChunkDrag
        if drag then
            local delta, snap = (x - drag.startX) / frame.Zoom, math.max(frame.Snap or 0.1, 0.001)
            local chunk = self.Sequence.chunks[drag.index]
            if drag.resize then chunk.duration = math.max(math.Round((drag.duration + delta) / snap) * snap, snap)
            else chunk.at = math.max(math.Round((drag.at + delta) / snap) * snap, 0) end
            drag.moved, frame.Session.dirty, frame.HitCycle = true, true, nil return
        end
        local rect = frame.SelectedChunk and self.Rects and self.Rects[frame.SelectedChunk]
        if rect and x >= rect.x and x <= rect.x + rect.w and y >= rect.y and y <= rect.y + rect.h then
            self:SetCursor(math.abs(x - rect.x - rect.w) <= 8 and 'sizewe' or 'sizeall')
        else self:SetCursor('arrow') end
    end
    canvas.OnMouseReleased = function(self, code)
        if code ~= MOUSE_LEFT then return end
        local frame = self.Editor
        if frame.ChunkDrag and frame.ChunkDrag.moved then
            table.insert(frame.Session.history, frame.ChunkDrag.snapshot) frame.Session.future = {}
        end
        local moved = frame.ChunkDrag and frame.ChunkDrag.moved
        local selectionChanged = frame.ChunkDrag and frame.ChunkDrag.selectionChanged
        frame.ChunkDrag, frame.DragPlayhead = nil, nil self:MouseCapture(false)
        if moved or selectionChanged then frame:Rebuild() frame:RequestFocus() end
    end
    canvas.OnMouseWheeled = function(self, delta)
        local maximum = self.MaximumScroll and self.MaximumScroll() or math.huge
        self.Editor.SubtitleScroll = math.Clamp((self.Editor.SubtitleScroll or 0) - delta * 0.5, 0, maximum)
        return true
    end
end

local addColor

local function addChunkInspector(frame, parent, sequence)
    local chunk = sequence.chunks and sequence.chunks[frame.SelectedChunk]
    if not chunk then EDITOR.AddLabel(parent, 'Select a subtitle chunk.') return end
    local function change(callback, rebuild)
        EDITOR.Push(frame.Session) callback(chunk) frame.Session.dirty = true if rebuild then frame:Rebuild() end
    end
    EDITOR.AddLabel(parent, 'CHUNK - ' .. tostring(chunk.id))
    EDITOR.AddText(parent, 'ID', chunk.id, function(value) change(function(item) item.id = AUDIO.NormalizeId(value) or item.id end, true) end)
    EDITOR.AddNumber(parent, 'Start (media seconds)', chunk.at or 0, 0, 3600, 3,
        function(value) change(function(item) item.at = value end) end)
    EDITOR.AddNumber(parent, 'Duration', chunk.duration or 1, 0.02, 120, 3,
        function(value) change(function(item) item.duration = value end) end)
    EDITOR.AddText(parent, 'Text', chunk.text, function(value) change(function(item) item.text = value end) end, true)
    EDITOR.AddText(parent, 'Speaker override', chunk.speaker, function(value)
        change(function(item) item.speaker = value ~= '' and value or nil end)
    end)
    EDITOR.AddChoice(parent, 'Style', chunk.style or sequence.style, EDITOR.SortedIds(availableStyles(frame)),
        function(value) change(function(item) item.style = value end) end)
    EDITOR.AddFontChoice(parent, 'Font override', chunk.font, function(value)
        change(function(item) item.font = value end)
    end, true)
    EDITOR.AddNumber(parent, 'Font size override', chunk.size or 24, 12, 72, 0,
        function(value) change(function(item) item.size = value end) end)
    EDITOR.AddNumber(parent, 'Font weight override', chunk.weight or 500, 100, 1000, 0,
        function(value) change(function(item) item.weight = value end) end)
    local glitch = chunk.glitch or {}
    EDITOR.AddCheck(parent, 'Glitch override enabled', glitch.enabled, function(value)
        change(function(item) item.glitch = item.glitch or {} item.glitch.enabled = value end)
    end)
    EDITOR.AddNumber(parent, 'Glitch intensity', glitch.intensity or 1, 0, 4, 2,
        function(value) change(function(item) item.glitch = item.glitch or {} item.glitch.intensity = value end) end)
    EDITOR.AddNumber(parent, 'Glitch interval', glitch.interval or 0.06, 0.02, 1, 2,
        function(value) change(function(item) item.glitch = item.glitch or {} item.glitch.interval = value end) end)
    EDITOR.AddCheck(parent, 'Duck music', chunk.duckMusic ~= false,
        function(value) change(function(item) item.duckMusic = value end) end)
    EDITOR.AddNumber(parent, 'Ducking amount', chunk.duckAmount or 0.45, 0, 1, 2,
        function(value) change(function(item) item.duckAmount = value end) end)
    EDITOR.AddCheck(parent, 'Fade chunk in and out', chunk.fadeEnabled ~= false,
        function(value) change(function(item) item.fadeEnabled = value end) end)
    local colorOverridden = chunk.color ~= nil
    EDITOR.AddCheck(parent, 'Override text color', colorOverridden, function(value)
        local styles = availableStyles(frame)
        local style = styles[AUDIO.NormalizeId(chunk.style or sequence.style or 'default')] or styles.default
        local inherited = style and style.color or {255, 255, 255, 255}
        change(function(item) item.color = value and table.Copy(inherited) or nil end, true)
    end)
    if colorOverridden then
        addColor(parent, 'Text color override', chunk.color, function(value)
            change(function(item) item.color = value end)
        end)
    end
    local remove = vgui.Create('DButton', parent) remove:Dock(TOP) remove:DockMargin(6, 8, 6, 4)
    remove:SetText('Delete chunk') remove.DoClick = function()
        EDITOR.Mutate(frame, function() table.remove(sequence.chunks, frame.SelectedChunk) frame.SelectedChunk = nil end)
    end
end

local function sequencesBody(frame, panel)
    frame.Session.source.subtitles = frame.Session.source.subtitles or {}
    local split = vgui.Create('DHorizontalDivider', panel) split:Dock(FILL) split:SetDividerWidth(5) split:SetLeftWidth(280)
    local left, center = vgui.Create('DPanel', split), vgui.Create('DHorizontalDivider', split)
    split:SetLeft(left) split:SetRight(center) center:SetDividerWidth(5) center:SetLeftWidth(math.max(frame:GetWide() - 680, 450))
    local timelineHost, inspector = vgui.Create('DScrollPanel', center), vgui.Create('DScrollPanel', center)
    center:SetLeft(timelineHost) center:SetRight(inspector)
    local add = vgui.Create('DButton', left) add:Dock(TOP) add:SetText('Add sequence')
    local list = vgui.Create('DListView', left) list:Dock(FILL) list:AddColumn('Sequence ID')
    for _, id in ipairs(EDITOR.SortedIds(frame.Session.source.subtitles)) do
        local row = list:AddLine(id) row.SequenceId = id if frame.Session.selected == id then list:SelectItem(row) end
    end
    add.DoClick = function()
        EDITOR.Mutate(frame, function(source)
            local id = EDITOR.UniqueId(source.subtitles, 'new_sequence')
            source.subtitles[id] = {label = 'New sequence', sound = '', style = 'default', chunks = {}}
            frame.Session.selected = id
        end)
    end
    list.OnRowSelected = function(_, _, row)
        stopPreview(frame) frame.Session.selected, frame.SelectedChunk, frame.HitCycle = row.SequenceId, nil, nil frame:Rebuild()
    end
    local sequence = frame.Session.source.subtitles[frame.Session.selected or '']
    if not sequence then EDITOR.AddLabel(timelineHost, 'Select or add a subtitle sequence.') return end
    frame.Zoom, frame.Snap, frame.SubtitleScroll = frame.Zoom or 90, frame.Snap or 0.1, frame.SubtitleScroll or 0
    local controls = vgui.Create('DPanel', timelineHost) controls:Dock(TOP) controls:SetTall(34)
    local function control(text, click)
        local button = vgui.Create('DButton', controls) button:Dock(LEFT) button:SetWide(88) button:SetText(text) button.DoClick = click
    end
    control('Play', function() startPreview(frame, sequence, false) end)
    control('Pause', function()
        pausePreview(frame)
    end)
    control('Stop', function() stopPreview(frame) frame.Playhead = 0 end)
    control('Layer preview', function() startPreview(frame, sequence, true) end)
    control('Add chunk', function()
        EDITOR.Mutate(frame, function()
            sequence.chunks = sequence.chunks or {} local ids = {}
            for _, chunk in ipairs(sequence.chunks) do ids[chunk.id] = true end
            table.insert(sequence.chunks, {id = EDITOR.UniqueId(ids, 'sentence'), at = frame.Playhead or 0,
                duration = 2, text = 'Subtitle text'})
            frame.SelectedChunk = #sequence.chunks
        end)
    end)
    EDITOR.AddCompactNumber(controls, 'Zoom', frame.Zoom, 30, 240, 0,
        function(value) frame.Zoom = value end, 180)
    EDITOR.AddCompactNumber(controls, 'Snap', frame.Snap, 0.01, 2, 2,
        function(value) frame.Snap = value end, 180)
    local lanes, laneCount = assignLanes(sequence.chunks)
    local canvas = vgui.Create('DPanel', timelineHost) canvas:Dock(TOP)
    canvas:SetTall(RULER + TRACK + laneCount * LANE + 8)
    canvas.Editor, canvas.Sequence, canvas.Lanes = frame, sequence, lanes
    canvas:SetKeyboardInputEnabled(true)
    canvas.OnKeyCodePressed = function(_, key) if frame.OnKeyCodePressed then frame:OnKeyCodePressed(key) end end
    canvas.Paint = paintTimeline installTimelineInput(canvas)
    canvas.Think = function()
        if not frame.Playing then return end
        frame.Playhead = math.max((RealTime() - frame.PlayStarted) * (frame.PreviewRate or 1), 0)
        local sound = linkedSound(frame, sequence)
        if frame.Playhead >= math.max(sound and sound.duration or 0, sequenceDuration(sequence)) then frame.Playing = false end
    end
    local function timelineDuration()
        local currentSound = linkedSound(frame, sequence)
        return math.max(currentSound and currentSound.duration or 0, sequenceDuration(sequence), 1)
    end
    local function visibleSeconds()
        return math.max((canvas:GetWide() - LABEL) / math.max(frame.Zoom or 90, 1), 0.1)
    end
    local function maximumScroll() return math.max(timelineDuration() - visibleSeconds(), 0) end
    canvas.MaximumScroll = maximumScroll
    EDITOR.AddTimelineScrollbar(timelineHost,
        function() return frame.SubtitleScroll or 0 end,
        function(value) frame.SubtitleScroll = value end,
        maximumScroll, visibleSeconds)
    local sequenceId = frame.Session.selected
    EDITOR.AddLabel(inspector, 'SEQUENCE - ' .. sequenceId)
    EDITOR.AddText(inspector, 'Sequence ID', sequenceId, function(value)
        local newId = AUDIO.NormalizeId(value)
        if not newId or newId ~= sequenceId and frame.Session.source.subtitles[newId] then return end
        EDITOR.Mutate(frame, function(source)
            source.subtitles[newId], source.subtitles[sequenceId] = source.subtitles[sequenceId], nil
            frame.Session.selected = newId
        end)
    end)
    EDITOR.AddText(inspector, 'Linked registered sound', sequence.sound, function(value)
        EDITOR.Push(frame.Session) sequence.sound = AUDIO.NormalizeId(value) or value frame.Session.dirty = true
    end)
    local pickSound = vgui.Create('DButton', inspector) pickSound:Dock(TOP) pickSound:DockMargin(6, 0, 6, 4)
    pickSound:SetText('Search registered sounds...') pickSound.DoClick = function()
        EDITOR.OpenIdPicker('Select subtitle audio', shared('sounds'), function(id)
            EDITOR.Push(frame.Session) sequence.sound = id frame.Session.dirty = true frame:Rebuild()
        end)
    end
    EDITOR.AddChoice(inspector, 'Default style', sequence.style or 'default', EDITOR.SortedIds(availableStyles(frame)),
        function(value) EDITOR.Push(frame.Session) sequence.style = value frame.Session.dirty = true end)
    EDITOR.AddText(inspector, 'Default speaker', sequence.speaker, function(value)
        EDITOR.Push(frame.Session) sequence.speaker = value frame.Session.dirty = true
    end)
    EDITOR.AddCheck(inspector, 'Use actual client-local Source playback (not seekable)', frame.ActualSourcePreview, function(value)
        pausePreview(frame) frame.ActualSourcePreview = value
    end)
    EDITOR.AddLabel(inspector,
        'Preview is client-local only. It never starts server audio, timelines, or map components.')
    EDITOR.AddLabel(inspector, 'Space: play/pause    Shift+Space: play from 0s')
    addChunkInspector(frame, inspector, sequence)
    local remove = vgui.Create('DButton', inspector) remove:Dock(TOP) remove:DockMargin(6, 8, 6, 4)
    remove:SetText('Delete sequence') remove.DoClick = function()
        stopPreview(frame) EDITOR.Mutate(frame, function(source) source.subtitles[sequenceId], frame.Session.selected = nil, nil end)
    end
end

addColor = function(parent, label, value, changed)
    EDITOR.AddLabel(parent, label)
    local mixer = vgui.Create('DColorMixer', parent) mixer:Dock(TOP) mixer:DockMargin(6, 0, 6, 6)
    mixer:SetTall(145) mixer:SetPalette(true) mixer:SetAlphaBar(true) mixer:SetWangs(true)
    value = value or {255, 255, 255, 255}
    mixer:SetColor(Color(value[1] or 255, value[2] or 255, value[3] or 255, value[4] or 255))
    mixer.ValueChanged = function(_, color) changed({color.r, color.g, color.b, color.a}) end
end

local function stylesBody(frame, panel)
    frame.Session.source.subtitleStyles = frame.Session.source.subtitleStyles or {}
    local split = vgui.Create('DHorizontalDivider', panel) split:Dock(FILL) split:SetDividerWidth(5) split:SetLeftWidth(280)
    local left, right = vgui.Create('DPanel', split), vgui.Create('DScrollPanel', split)
    split:SetLeft(left) split:SetRight(right)
    local add = vgui.Create('DButton', left) add:Dock(TOP) add:SetText('Add style')
    local list = vgui.Create('DListView', left) list:Dock(FILL) list:AddColumn('Style ID')
    for _, id in ipairs(EDITOR.SortedIds(frame.Session.source.subtitleStyles)) do
        local row = list:AddLine(id) row.StyleId = id if frame.Session.selected == id then list:SelectItem(row) end
    end
    add.DoClick = function()
        EDITOR.Mutate(frame, function(source)
            local id = EDITOR.UniqueId(source.subtitleStyles, 'new_style')
            source.subtitleStyles[id] = {label = 'New style', font = 'Roboto', size = 24, weight = 500,
                color = {255, 255, 255, 255}, speakerColor = {150, 205, 255, 255},
                glitch = {enabled = false, intensity = 1, interval = 0.06}}
            frame.Session.selected = id
        end)
    end
    list.OnRowSelected = function(_, _, row) frame.Session.selected = row.StyleId frame:Rebuild() end
    local id, style = frame.Session.selected, frame.Session.source.subtitleStyles[frame.Session.selected or '']
    if not style then EDITOR.AddLabel(right, 'Select or add a reusable subtitle style.') return end
    local function change(callback, rebuild)
        EDITOR.Push(frame.Session) callback(style) frame.Session.dirty = true if rebuild then frame:Rebuild() end
    end
    style.glitch = style.glitch or {}
    EDITOR.AddLabel(right, 'STYLE - ' .. id)
    EDITOR.AddText(right, 'Style ID', id, function(value)
        local newId = AUDIO.NormalizeId(value)
        if not newId or newId ~= id and frame.Session.source.subtitleStyles[newId] then return end
        EDITOR.Mutate(frame, function(source)
            source.subtitleStyles[newId], source.subtitleStyles[id] = source.subtitleStyles[id], nil
            frame.Session.selected = newId
        end)
    end)
    EDITOR.AddText(right, 'Label', style.label, function(value) change(function(item) item.label = value end) end)
    EDITOR.AddFontChoice(right, 'Font face', style.font or 'Roboto', function(value)
        change(function(item) item.font = value end)
    end)
    EDITOR.AddNumber(right, 'Font size', style.size or 24, 12, 72, 0, function(value) change(function(item) item.size = value end) end)
    EDITOR.AddNumber(right, 'Weight', style.weight or 500, 100, 1000, 0, function(value) change(function(item) item.weight = value end) end)
    addColor(right, 'Text color', style.color, function(value) change(function(item) item.color = value end) end)
    addColor(right, 'Speaker color', style.speakerColor, function(value) change(function(item) item.speakerColor = value end) end)
    EDITOR.AddCheck(right, 'Glitch enabled', style.glitch.enabled, function(value)
        change(function(item) item.glitch.enabled = value end)
    end)
    EDITOR.AddNumber(right, 'Glitch intensity', style.glitch.intensity or 1, 0, 4, 2,
        function(value) change(function(item) item.glitch.intensity = value end) end)
    EDITOR.AddNumber(right, 'Glitch interval', style.glitch.interval or 0.06, 0.02, 1, 2,
        function(value) change(function(item) item.glitch.interval = value end) end)
    local preview = vgui.Create('DButton', right) preview:Dock(TOP) preview:DockMargin(6, 8, 6, 2)
    preview:SetText('Preview style on subtitle HUD') preview.DoClick = function()
        AUDIO.ClientPreviewSubtitleSequence({id = 'style_preview', style = id, speaker = 'FOUNDATION', duration = 3,
            chunks = {{id = 'preview', at = 0, duration = 3, text = 'Subtitle style preview.', style = id}}},
            {styles = availableStyles(frame)})
    end
    local remove = vgui.Create('DButton', right) remove:Dock(TOP) remove:DockMargin(6, 2, 6, 4)
    remove:SetText('Delete style') remove.DoClick = function()
        EDITOR.Mutate(frame, function(source) source.subtitleStyles[id], frame.Session.selected = nil, nil end)
    end
end

local function body(frame, panel)
    if frame.Workspace == 'styles' then stylesBody(frame, panel) else sequencesBody(frame, panel) end
end

function AUDIO.OpenSubtitleSequenceEditor()
    if IsValid(AUDIO.SubtitleSequenceEditor) then AUDIO.SubtitleSequenceEditor:MakePopup() return AUDIO.SubtitleSequenceEditor end
    EDITOR.RefreshSharedPool()
    local frame = EDITOR.BuildFrame('Luasquare Subtitle Sequence and Style Editor', newSequences(), 'subtitles', false, body)
    frame:SetSize(ScrW(), math.floor(ScrH() * 0.5)) frame:SetPos(0, 0)
    frame.Workspace, frame.WorkspaceSessions = 'sequences', {}
    frame.WorkspaceSessions.sequences = frame.Session
    frame.WorkspaceSessions.styles = EDITOR.NewSession(newStyles(), 'subtitle_styles', false)
    local baseSetSource = frame.SetSource
    frame.SetSource = function(self, ...)
        stopPreview(self) AUDIO.ClientClearSubtitlePreviews()
        local result = baseSetSource(self, ...)
        self.WorkspaceSessions[self.Workspace] = self.Session
        return result
    end
    local sequences = vgui.Create('DButton', frame.Toolbar) sequences:Dock(RIGHT) sequences:SetWide(105) sequences:SetText('Sequences')
    local styles = vgui.Create('DButton', frame.Toolbar) styles:Dock(RIGHT) styles:SetWide(105) styles:SetText('Styles')
    local function switch(workspace)
        if workspace == frame.Workspace then return end
        stopPreview(frame) frame.WorkspaceSessions[frame.Workspace] = frame.Session frame.Workspace = workspace
        frame.Session = frame.WorkspaceSessions[workspace] frame:Rebuild()
    end
    sequences.DoClick = function() switch('sequences') end styles.DoClick = function() switch('styles') end
    frame.OnKeyCodePressed = function(self, key)
        if key ~= KEY_SPACE or self.Workspace ~= 'sequences' then return end
        local sequence = self.Session.source.subtitles[self.Session.selected or '']
        if not sequence then return end
        local shift = _G.input.IsKeyDown(KEY_LSHIFT) or _G.input.IsKeyDown(KEY_RSHIFT)
        if shift then
            pausePreview(self) self.Playhead = 0 startPreview(self, sequence, false)
        elseif self.Playing then pausePreview(self)
        else startPreview(self, sequence, false) end
    end
    frame.NewSource = function(self)
        stopPreview(self)
        local category = self.Workspace == 'styles' and 'subtitle_styles' or 'subtitles'
        self:SetSource(EDITOR.NewMasterSource(category), nil, false, category, false)
    end
    local inheritedClose = frame.Close
    frame.Close = function(self)
        local dirty = false
        for _, session in pairs(self.WorkspaceSessions or {}) do dirty = dirty or session.dirty end
        if not dirty then self._closeApproved = true return inheritedClose(self) end
        Derma_Query('Discard unsaved subtitle sequence/style changes?', 'Unsaved changes', 'Discard', function()
            if not IsValid(self) then return end
            self._closeApproved = true inheritedClose(self)
        end, 'Cancel')
    end
    frame.btnClose.DoClick = function() frame:Close() end
    frame.OnRemove = function(self) stopPreview(self) AUDIO.ClientClearSubtitlePreviews() end
    frame:Rebuild()
    AUDIO.SubtitleSequenceEditor = frame return frame
end
