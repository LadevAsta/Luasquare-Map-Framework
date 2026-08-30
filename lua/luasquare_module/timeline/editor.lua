if not CLIENT then return end
LUASQUARE_TIMELINE = LUASQUARE_TIMELINE or {}
local TIMELINE = LUASQUARE_TIMELINE

local EDITOR = TIMELINE.Editor or {}
TIMELINE.Editor = EDITOR

local TRACK_HEIGHT = 64
local RULER_HEIGHT = 30
local LABEL_WIDTH = 170
local MIN_ZOOM = 20
local MAX_ZOOM = 240
local SCROLLBAR_SIZE = 14
local COMPONENT_SHELF_HEIGHT = 190
local DEFAULT_SNAP_SECONDS = 0.1

local function defaultSource()
    return {
        schema = TIMELINE.Schema,
        id = 'new_timeline',
        label = 'New Timeline',
        channel = 'default',
        conflictPolicy = 'reject',
        restartPolicy = 'reject',
        duration = 5,
        tracks = {},
        editor = {snapEnabled = true, snapSeconds = DEFAULT_SNAP_SECONDS}
    }
end

local function normalizeFileName(value)
    value = string.lower(tostring(value or 'timeline'))
    value = string.gsub(value, '[^%w_%-]', '_')
    return value ~= '' and value or 'timeline'
end

local function sourceTrack(session, index)
    return session.source and session.source.tracks and session.source.tracks[index]
end

local function sourceClip(session, selection)
    if not selection then return nil end
    local track = sourceTrack(session, selection.track)
    return track and track.clips and track.clips[selection.clip] or nil
end

local function usedIds(source, clipsOnly)
    local ids = {}
    for _, track in ipairs(source.tracks or {}) do
        if not clipsOnly and track.id then ids[track.id] = true end
        for _, clip in ipairs(track.clips or {}) do
            if clip.id then ids[clip.id] = true end
        end
    end
    return ids
end

local function uniqueId(source, base, clipsOnly)
    base = normalizeFileName(base)
    local ids = usedIds(source, clipsOnly)
    if not ids[base] then return base end
    local suffix = 2
    while ids[base .. '_' .. suffix] do suffix = suffix + 1 end
    return base .. '_' .. suffix
end

local function componentCategory(component)
    local category = tostring(component and component.type or 'other')
    if string.StartWith(category, 'dfr.catalyzer') then return 'DFR / Catalyzers' end
    if string.StartWith(category, 'dfr.machinery') then return 'DFR / Machinery' end
    if string.StartWith(category, 'dfr.core_visual') then return 'DFR / Core Visuals' end
    if string.StartWith(category, 'dfr.reactor_machine') then return 'DFR / Reactor Machine' end
    if string.StartWith(category, 'dfr.procedure') then return 'DFR / Procedures' end
    if string.StartWith(category, 'audio.music') then return 'Audio / Music' end
    if string.StartWith(category, 'audio.pa') then return 'Audio / PA' end
    if string.StartWith(category, 'audio.soundscape') then return 'Audio / Soundscapes' end
    if string.StartWith(category, 'audio.ambient') then return 'Audio / Ambient' end
    if string.StartWith(category, 'luasquare.3d2display') then return 'Displays' end
    local root = string.match(category, '^([^.]+)') or category
    local labels = {
        audio = 'Audio', catalyzer = 'Catalyzers', machinery = 'Machinery',
        reactor = 'Reactor', display = 'Displays', source = 'Source endpoints'
    }
    return labels[root] or string.upper(string.sub(root, 1, 1)) .. string.sub(root, 2)
end

local function addLabel(parent, text)
    local label = parent:Add('DLabel')
    label:Dock(TOP)
    label:DockMargin(4, 5, 4, 1)
    label:SetText(text)
    label:SetTextColor(Color(220, 220, 220))
    label:SetTall(18)
    return label
end

local function addText(parent, labelText, value, changed)
    addLabel(parent, labelText)
    local entry = parent:Add('DTextEntry')
    entry:Dock(TOP)
    entry:DockMargin(4, 0, 4, 2)
    entry:SetValue(tostring(value or ''))
    entry.OnEnter = function(self) changed(self:GetValue()) end
    entry.OnLoseFocus = function(self) changed(self:GetValue()) end
    return entry
end

local function addNumber(parent, labelText, value, minimum, maximum, decimals, changed)
    local slider = parent:Add('DNumSlider')
    slider:Dock(TOP)
    slider:DockMargin(4, 1, 4, 1)
    slider:SetText(labelText)
    slider:SetMin(tonumber(minimum) or 0)
    slider:SetMax(tonumber(maximum) or 100)
    slider:SetDecimals(math.max(math.floor(tonumber(decimals) or 2), 0))
    slider:SetValue(tonumber(value) or 0)
    slider.OnValueChanged = function(_, newValue) changed(tonumber(newValue) or 0) end
    return slider
end

local function recursiveDrafts(root, out)
    local files, directories = file.Find(root .. '/*', 'DATA')
    for _, name in ipairs(files or {}) do
        if string.sub(string.lower(name), -5) == '.json' then table.insert(out, root .. '/' .. name) end
    end
    for _, directory in ipairs(directories or {}) do recursiveDrafts(root .. '/' .. directory, out) end
end

local Editor = {}

function Editor:Init()
    self:SetTitle('Luasquare JSON Timeline Editor')
    self:SetDeleteOnClose(true)
    self:SetSizable(false)
    self:SetDraggable(false)
    self:ShowCloseButton(true)
    self:SetSize(ScrW(), ScrH())
    self:SetPos(0, 0)
    self:SetAlpha(245)
    self:MakePopup()

    self.Session = {
        source = defaultSource(),
        compiled = nil,
        diagnostics = {},
        origin = 'new',
        draftPath = nil,
        readOnly = false,
        dirty = false,
        history = {},
        future = {},
        selection = nil,
        ownerId = nil,
        mutedTracks = {},
        playhead = 0,
        playing = false,
        playStartedAt = 0,
        zoom = 80,
        scrollX = 0,
        scrollY = 0,
        fullscreen = true,
        componentsVisible = true,
        livePreviewTime = nil,
        livePreviewStartedAt = nil,
        pendingLiveSeek = nil
    }
    self.Audio = TIMELINE.CreateAudioPreview()
    self.ClosingConfirmed = false
    self:BuildUI()
    self:Compile(false)
    TIMELINE.RequestCatalog()
    timer.Simple(0, function() if IsValid(self) and LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.ApplyTree(self) end end)
end

function Editor:BuildUI()
    self.Toolbar = self:Add('DPanel')
    self.Toolbar:Dock(TOP)
    self.Toolbar:SetTall(34)

    local function toolbarButton(text, width, callback)
        local button = self.Toolbar:Add('DButton')
        button:Dock(LEFT)
        button:DockMargin(2, 4, 0, 4)
        button:SetWide(width)
        button:SetText(text)
        button.DoClick = callback
        return button
    end

    toolbarButton('File...', 56, function() self:OpenSourceManager() end)
    toolbarButton('New', 48, function() self:RequestSourceChange(function() self:NewSource() end) end)
    toolbarButton('Save draft', 76, function() self:SaveDraft() end)
    toolbarButton('Undo', 48, function() self:Undo() end)
    toolbarButton('Redo', 48, function() self:Redo() end)
    toolbarButton('Validate', 62, function() self:ShowDiagnostics() end)
    toolbarButton('Refresh', 58, function() TIMELINE.RequestCatalog() end)
    toolbarButton('+ Track', 58, function() self:OpenAddTrackMenu() end)
    toolbarButton('Play', 48, function() self:PlaySimulation() end)
    toolbarButton('Pause', 48, function() self:PauseSimulation() end)
    toolbarButton('Stop', 48, function() self:StopPreview() end)
    toolbarButton('Live', 48, function() self:ConfirmLivePreview() end)
    toolbarButton('Audio', 50, function() self:LoadReferenceAudio(true) end)
    self.ComponentsButton = toolbarButton('Components', 82, function()
        self.Session.componentsVisible = not self.Session.componentsVisible
        self.Workspace:InvalidateLayout(true)
        self:RefreshEditorControls()
    end)
    self.WindowModeButton = toolbarButton('Windowed', 72, function()
        self:SetFullscreenMode(not self.Session.fullscreen)
    end)

    self.SourceLabel = self.Toolbar:Add('DLabel')
    self.SourceLabel:Dock(FILL)
    self.SourceLabel:DockMargin(6, 4, 4, 4)
    self.SourceLabel:SetTextColor(Color(210, 215, 220))
    self.SourceLabel:SetContentAlignment(4)
    self.SourceLabel:SetZPos(10000)

    self.ZoomSlider = self.Toolbar:Add('DNumSlider')
    self.ZoomSlider:Dock(RIGHT)
    self.ZoomSlider:DockMargin(2, 3, 4, 3)
    self.ZoomSlider:SetWide(190)
    self.ZoomSlider:SetText('Zoom')
    self.ZoomSlider:SetMin(MIN_ZOOM)
    self.ZoomSlider:SetMax(MAX_ZOOM)
    self.ZoomSlider:SetDecimals(0)
    self.ZoomSlider:SetValue(self.Session.zoom)
    self.ZoomSlider.OnValueChanged = function(_, value)
        self.Session.zoom = TIMELINE.Clamp(value, MIN_ZOOM, MAX_ZOOM)
    end

    self.SnapSlider = self.Toolbar:Add('DNumSlider')
    self.SnapSlider:Dock(RIGHT)
    self.SnapSlider:DockMargin(2, 3, 2, 3)
    self.SnapSlider:SetWide(160)
    self.SnapSlider:SetText('Snap')
    self.SnapSlider:SetMin(0.01)
    self.SnapSlider:SetMax(2)
    self.SnapSlider:SetDecimals(2)
    self.SnapSlider:SetValue(DEFAULT_SNAP_SECONDS)
    self.SnapSlider.OnValueChanged = function(control, value)
        if control._ignore or self.Session.readOnly then return end
        self.Session.source.editor = self.Session.source.editor or {}
        self.Session.source.editor.snapSeconds = math.max(tonumber(value) or DEFAULT_SNAP_SECONDS, 0.01)
        self.Session.dirty = true
        self:Compile(false, false)
    end
    self.SnapButton = toolbarButton('Snap: ON', 68, function()
        if self.Session.readOnly then return end
        self.Session.source.editor = self.Session.source.editor or {}
        self.Session.source.editor.snapEnabled = self.Session.source.editor.snapEnabled == false
        self.Session.dirty = true
        self:Compile(false, false)
    end)

    self.Body = self:Add('DPanel')
    self.Body:Dock(FILL)
    self.Body.PerformLayout = function(panel, width, height)
        local right = math.max(math.floor(width * 0.22), 320)
        local workspaceWidth = math.max(width - right - 4, 100)
        panel.Workspace:SetPos(0, 0)
        panel.Workspace:SetSize(workspaceWidth, height)
        panel.Inspector:SetPos(width - right, 0)
        panel.Inspector:SetSize(right, height)
    end
    self.Body.Paint = function(_, width, height)
        surface.SetDrawColor(28, 31, 34, 232)
        surface.DrawRect(0, 0, width, height)
    end

    self.Workspace = self.Body:Add('DPanel')
    self.Body.Workspace = self.Workspace
    self.Workspace.Paint = function() end
    self.Workspace.PerformLayout = function(panel, width, height)
        local shelfHeight = self.Session.componentsVisible and math.min(COMPONENT_SHELF_HEIGHT, math.floor(height * 0.32)) or 0
        panel.Canvas:SetPos(0, 0)
        panel.Canvas:SetSize(width, math.max(height - shelfHeight - (shelfHeight > 0 and 4 or 0), 80))
        panel.ComponentShelf:SetVisible(shelfHeight > 0)
        if shelfHeight > 0 then
            panel.ComponentShelf:SetPos(0, height - shelfHeight)
            panel.ComponentShelf:SetSize(width, shelfHeight)
        end
    end

    self.ComponentShelf = self.Workspace:Add('DPanel')
    self.Workspace.ComponentShelf = self.ComponentShelf
    self.ComponentShelf.Paint = function(_, width, height)
        surface.SetDrawColor(35, 39, 43, 244)
        surface.DrawRect(0, 0, width, height)
        draw.SimpleText('COMPONENT INVENTORY - drag an action onto a matching track or empty space',
            'DermaDefaultBold', 8, 6, Color(220, 225, 230))
    end
    self.Explorer = self.ComponentShelf:Add('DTree')
    self.Explorer:Dock(FILL)
    self.Explorer:DockMargin(4, 24, 4, 4)
    self.Explorer.OnNodeSelected = function(_, node)
        if node.TimelineComponent then
            self.Session.inventoryComponent = node.TimelineComponent.id
        end
    end

    self.Canvas = self.Workspace:Add('DPanel')
    self.Workspace.Canvas = self.Canvas
    self.Canvas:SetCursor('arrow')
    self.Canvas.Paint = function(_, width, height) self:PaintTimeline(width, height) end
    self.Canvas.OnMousePressed = function(_, code) self:TimelineMousePressed(code) end
    self.Canvas.OnMouseReleased = function(_, code) self:TimelineMouseReleased(code) end
    self.Canvas.OnCursorMoved = function(_, x, y) self:TimelineMouseMoved(x, y) end
    self.Canvas.OnMouseWheeled = function(_, delta)
        self:UpdateScrollBounds()
        if input.IsKeyDown(KEY_LSHIFT) then
            self.Session.scrollX = TIMELINE.Clamp(
                self.Session.scrollX - delta * 48, 0, self.Session.maxScrollX or 0)
        else
            self.Session.scrollY = TIMELINE.Clamp(
                self.Session.scrollY - delta * 40, 0, self.Session.maxScrollY or 0)
        end
        return true
    end
    self.Canvas:Receiver('LUASQUARE_TIMELINE_COMPONENT', function(_, panels, dropped, _, x, y)
        if not dropped or self.Session.readOnly then return end
        local node = panels and panels[1]
        if node and node.TimelineDrop then self:AddDropAt(node.TimelineDrop, x, y) end
        if node and not node.TimelineDrop and node.TimelineComponent then
            self:AddComponentAt(node.TimelineComponent, x, y)
        end
    end)

    self.VerticalScroll = self.Canvas:Add('DPanel')
    self.VerticalScroll:Dock(RIGHT)
    self.VerticalScroll:SetWide(SCROLLBAR_SIZE)
    self.VerticalScroll:SetCursor('sizens')
    self.VerticalScroll.Paint = function(panel, width, height)
        self:PaintVerticalScroll(panel, width, height)
    end
    self.VerticalScroll.OnMousePressed = function(panel, code)
        if code ~= MOUSE_LEFT then return end
        self.VerticalScrollDragging = true
        panel:MouseCapture(true)
        local _, y = panel:LocalCursorPos()
        self:SetVerticalScrollFromCursor(y)
    end
    self.VerticalScroll.OnCursorMoved = function(_, _, y)
        if self.VerticalScrollDragging then self:SetVerticalScrollFromCursor(y) end
    end
    self.VerticalScroll.OnMouseReleased = function(panel, code)
        if code ~= MOUSE_LEFT then return end
        self.VerticalScrollDragging = false
        panel:MouseCapture(false)
    end

    self.HorizontalScroll = self.Canvas:Add('DPanel')
    self.HorizontalScroll:Dock(BOTTOM)
    self.HorizontalScroll:SetTall(SCROLLBAR_SIZE)
    self.HorizontalScroll:SetCursor('sizewe')
    self.HorizontalScroll.Paint = function(panel, width, height)
        self:PaintHorizontalScroll(panel, width, height)
    end
    self.HorizontalScroll.OnMousePressed = function(panel, code)
        if code ~= MOUSE_LEFT then return end
        self.HorizontalScrollDragging = true
        panel:MouseCapture(true)
        local x = panel:LocalCursorPos()
        self:SetHorizontalScrollFromCursor(x)
    end
    self.HorizontalScroll.OnCursorMoved = function(_, x)
        if self.HorizontalScrollDragging then self:SetHorizontalScrollFromCursor(x) end
    end
    self.HorizontalScroll.OnMouseReleased = function(panel, code)
        if code ~= MOUSE_LEFT then return end
        self.HorizontalScrollDragging = false
        panel:MouseCapture(false)
    end

    self.Inspector = self.Body:Add('DScrollPanel')
    self.Body.Inspector = self.Inspector
    local function paintInspector(_, width, height)
        surface.SetDrawColor(43, 47, 51)
        surface.DrawRect(0, 0, width, height)
    end
    self.Inspector.Paint = paintInspector
    self.Inspector:GetCanvas().Paint = paintInspector

    self.Status = self:Add('DLabel')
    self.Status:Dock(BOTTOM)
    self.Status:SetTall(30)
    self.Status:SetContentAlignment(4)
    self.Status:SetTextInset(6, 0)
    self.Status:SetTextColor(Color(225, 225, 225))
    self:RefreshEditorControls()
end

function Editor:Close()
    if not self.ClosingConfirmed and self.Session.dirty then self:RequestClose() return end
    self:SetVisible(false)
    self:Remove()
end

function Editor:OnRemove()
    self:StopPreview()
    self.Audio:Stop()
    if IsValid(self.SourceManager) then self.SourceManager:Remove() end
    hook.Remove('LUASQUARE_TIMELINE_CatalogUpdated', 'LUASQUARE_TIMELINE_EditorCatalog')
    hook.Remove('LUASQUARE_TIMELINE_PreviewStatus', 'LUASQUARE_TIMELINE_EditorPreviewStatus')
end

function Editor:RequestClose()
    if not self.Session.dirty then
        self.ClosingConfirmed = true
        self:Close()
        return
    end
    Derma_Query('Discard unsaved timeline changes?', 'Unsaved timeline', 'Discard', function()
        self.ClosingConfirmed = true
        self:Close()
    end, 'Keep editing')
end

function Editor:RequestSourceChange(callback)
    if not self.Session.dirty then callback() return end
    Derma_Query('Discard unsaved timeline changes?', 'Unsaved timeline', 'Discard', callback, 'Cancel', function()
        self:RefreshEditorControls()
    end)
end

function Editor:SetFullscreenMode(enabled)
    self.Session.fullscreen = enabled and true or false
    self:SetSizable(not self.Session.fullscreen)
    self:SetDraggable(not self.Session.fullscreen)
    if self.Session.fullscreen then
        self:SetSize(ScrW(), ScrH())
        self:SetPos(0, 0)
    else
        self:SetSize(math.min(math.max(ScrW() * 0.78, 1050), ScrW() - 40),
            math.min(math.max(ScrH() * 0.78, 700), ScrH() - 40))
        self:Center()
    end
    if IsValid(self.WindowModeButton) then
        self.WindowModeButton:SetText(self.Session.fullscreen and 'Windowed' or 'Fullscreen')
    end
end

function Editor:RefreshEditorControls()
    local editor = self.Session.source.editor or {}
    if IsValid(self.SourceLabel) then
        local origin = self.Session.origin == 'new' and 'New timeline' or tostring(self.Session.origin)
        self.SourceLabel:SetText(origin)
        self.SourceLabel:SetTooltip(origin)
    end
    if IsValid(self.SnapButton) then
        self.SnapButton:SetText('Snap: ' .. (editor.snapEnabled == false and 'OFF' or 'ON'))
    end
    if IsValid(self.SnapSlider) then
        self.SnapSlider._ignore = true
        self.SnapSlider:SetValue(tonumber(editor.snapSeconds) or DEFAULT_SNAP_SECONDS)
        self.SnapSlider:SetEnabled(editor.snapEnabled ~= false and not self.Session.readOnly)
        self.SnapSlider._ignore = false
    end
    if IsValid(self.ComponentsButton) then
        self.ComponentsButton:SetText(self.Session.componentsVisible and 'Hide parts' or 'Components')
    end
end

function Editor:Compile(markDirty, rebuildInspector)
    local compiled, diagnostics = TIMELINE.CompileSource(self.Session.source, self.Session.origin)
    self.Session.compiled = compiled
    self.Session.diagnostics = diagnostics or {}
    if markDirty then self.Session.dirty = true end
    self.Status:SetText((self.Session.readOnly and 'PACKED READ-ONLY  ' or 'DRAFT EDITABLE  ')
        .. (self.Session.dirty and 'UNSAVED  ' or '')
        .. (compiled and 'Valid source' or 'Source has errors')
        .. '  |  ' .. tostring(self.Session.draftPath or self.Session.origin))
    if rebuildInspector ~= false then self:RebuildInspector() end
    self:RefreshEditorControls()
end

function Editor:Commit(callback, rebuildInspector)
    if self.Session.readOnly then
        Derma_Message('Save the packed source as a draft before editing it.', 'Read-only source', 'OK')
        return false
    end
    table.insert(self.Session.history, TIMELINE.DeepCopy(self.Session.source))
    if #self.Session.history > 100 then table.remove(self.Session.history, 1) end
    self.Session.future = {}
    callback(self.Session.source)
    self:Compile(true, rebuildInspector == true)
    return true
end

function Editor:Undo()
    local previous = table.remove(self.Session.history)
    if not previous then return end
    table.insert(self.Session.future, TIMELINE.DeepCopy(self.Session.source))
    self.Session.source = previous
    self:Compile(true)
end

function Editor:Redo()
    local nextSource = table.remove(self.Session.future)
    if not nextSource then return end
    table.insert(self.Session.history, TIMELINE.DeepCopy(self.Session.source))
    self.Session.source = nextSource
    self:Compile(true)
end

function Editor:NewSource()
    self:StopPreview()
    self.Session.source = defaultSource()
    self.Session.origin = 'new'
    self.Session.draftPath = nil
    self.Session.readOnly = false
    self.Session.dirty = true
    self.Session.history = {}
    self.Session.future = {}
    self.Session.selection = nil
    self.Session.playhead = 0
    self:Compile(false)
    self:PopulateSources()
end

function Editor:OpenSource(item)
    local source
    if item.kind == 'packed' then
        source = TIMELINE.DeepCopy(item.source)
    else
        local json = file.Read(item.path, 'DATA')
        source = json and util.JSONToTable(json) or nil
    end
    if type(source) ~= 'table' then
        Derma_Message('Unable to read timeline source.', 'Open failed', 'OK')
        return
    end
    self:StopPreview()
    self.Session.source = source
    self.Session.origin = item.path
    self.Session.draftPath = item.kind == 'draft' and item.path or nil
    self.Session.readOnly = item.kind == 'packed'
    self.Session.dirty = false
    self.Session.history = {}
    self.Session.future = {}
    self.Session.selection = nil
    self.Session.playhead = 0
    local bindingPath = item.path
    if item.kind == 'draft' then
        local suffix = string.match(bindingPath, '^' .. TIMELINE.DraftRoot .. '/(.+)$')
        if suffix then bindingPath = TIMELINE.SourceRoot .. '/' .. suffix end
    end
    for _, component in ipairs((TIMELINE.ClientCatalog and TIMELINE.ClientCatalog.components) or {}) do
        for _, timeline in ipairs(component.timelines or {}) do
            if timeline.sourcePath == bindingPath then
                self.Session.ownerId = component.id
                break
            end
        end
    end
    self:Compile(false)
    self:LoadReferenceAudio(false)
    self:PopulateSources()
end

function Editor:DraftPath()
    if self.Session.draftPath then return self.Session.draftPath end
    local origin = tostring(self.Session.origin or '')
    local suffix = string.match(origin, '^' .. TIMELINE.SourceRoot .. '/(.+)$')
    if not suffix then suffix = game.GetMap() .. '/' .. normalizeFileName(self.Session.source.id) .. '.json' end
    return TIMELINE.DraftRoot .. '/' .. suffix
end

function Editor:SaveDraft()
    local compiled = TIMELINE.CompileSource(self.Session.source, self.Session.origin)
    if not compiled then self:ShowDiagnostics() return end
    local path = self:DraftPath()
    local directory = string.GetPathFromFilename(path)
    file.CreateDir(string.TrimRight(directory, '/'))
    local json = TIMELINE.CanonicalJSON(self.Session.source, true)
    if not json then return end
    file.Write(path, json)
    self.Session.draftPath = path
    self.Session.origin = path
    self.Session.readOnly = false
    self.Session.dirty = false
    self:Compile(false)
    self:PopulateSources()
    notification.AddLegacy('Timeline draft saved: data/' .. path, NOTIFY_GENERIC, 6)
end

function Editor:PopulateSources()
    self:RefreshEditorControls()
    if IsValid(self.SourceManager) then self:PopulateSourceManager() end
end

function Editor:GetSourceEntries()
    local entries = {}
    for _, source in ipairs((TIMELINE.ClientCatalog and TIMELINE.ClientCatalog.sources) or {}) do
        table.insert(entries, {kind = 'packed', path = source.path, source = source.source})
    end
    local drafts = {}
    recursiveDrafts(TIMELINE.DraftRoot, drafts)
    table.sort(drafts)
    for _, path in ipairs(drafts) do table.insert(entries, {kind = 'draft', path = path}) end
    table.sort(entries, function(a, b) return tostring(a.path) < tostring(b.path) end)
    return entries
end

function Editor:PopulateSourceManager()
    if not IsValid(self.SourceManagerList) then return end
    local filter = string.lower(IsValid(self.SourceManagerSearch) and self.SourceManagerSearch:GetValue() or '')
    self.SourceManagerList:Clear()
    for _, entry in ipairs(self:GetSourceEntries()) do
        local path = tostring(entry.path)
        if filter == '' or string.find(string.lower(path), filter, 1, true) then
            local line = self.SourceManagerList:AddLine(entry.kind == 'packed' and 'Packed' or 'Draft',
                string.GetFileFromFilename(path), path)
            line.SourceEntry = entry
            line:SetTooltip(path)
        end
    end
end

function Editor:OpenSourceManager()
    if IsValid(self.SourceManager) then self.SourceManager:MakePopup() self.SourceManager:MoveToFront() return end
    local frame = vgui.Create('DFrame')
    self.SourceManager = frame
    frame:SetTitle('Timeline Sources')
    frame:SetSize(math.min(ScrW() - 80, 850), math.min(ScrH() - 80, 570))
    frame:Center()
    frame:SetDeleteOnClose(true)
    frame.OnRemove = function() if IsValid(self) then self.SourceManager = nil end end

    local search = frame:Add('DTextEntry')
    self.SourceManagerSearch = search
    search:Dock(TOP)
    search:DockMargin(6, 6, 6, 4)
    search:SetPlaceholderText('Search complete source path...')
    search.OnChange = function() self:PopulateSourceManager() end

    local list = frame:Add('DListView')
    self.SourceManagerList = list
    list:Dock(FILL)
    list:DockMargin(6, 0, 6, 4)
    list:SetMultiSelect(false)
    list:AddColumn('Kind'):SetFixedWidth(70)
    list:AddColumn('File'):SetFixedWidth(210)
    list:AddColumn('Complete path')

    local function loadSelected()
        local selected = list:GetSelectedLine()
        local line = selected and list:GetLine(selected)
        if not line or not line.SourceEntry then return end
        self:RequestSourceChange(function()
            self:OpenSource(line.SourceEntry)
            if IsValid(frame) then frame:Close() end
        end)
    end
    list.DoDoubleClick = loadSelected

    local buttons = frame:Add('DPanel')
    buttons:Dock(BOTTOM)
    buttons:SetTall(36)
    local function button(label, callback)
        local control = buttons:Add('DButton')
        control:Dock(LEFT)
        control:DockMargin(6, 4, 0, 4)
        control:SetWide(110)
        control:SetText(label)
        control.DoClick = callback
    end
    button('New', function()
        self:RequestSourceChange(function()
            self:NewSource()
            if IsValid(frame) then frame:Close() end
        end)
    end)
    button('Load selected', loadSelected)
    button('Save draft', function() self:SaveDraft() self:PopulateSourceManager() end)
    button('Close', function() frame:Close() end)
    self:PopulateSourceManager()
    frame:MakePopup()
    timer.Simple(0, function() if IsValid(frame) and LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.ApplyTree(frame) end end)
end

function Editor:PopulateComponents()
    self.Explorer:Clear()
    local catalog = TIMELINE.ClientCatalog or {}
    self.ComponentNodes = {}
    local categories = {}
    for _, component in ipairs(catalog.components or {}) do
        local category = componentCategory(component)
        categories[category] = categories[category] or {}
        table.insert(categories[category], component)
    end
    for category, components in SortedPairs(categories) do
        local categoryNode = self.Explorer:AddNode(category .. '  (' .. #components .. ')')
        for _, component in ipairs(components) do
            local node = categoryNode:AddNode(component.label .. '  [' .. component.id .. ']')
            node.TimelineComponent = component
            node.DoDoubleClick = function()
                self:AddComponentAt(component,
                    LABEL_WIDTH + self.Session.playhead * self.Session.zoom - self.Session.scrollX)
            end
            self.ComponentNodes[component.id] = node
            for _, action in ipairs(component.actions or {}) do
                local actionNode = node:AddNode(action.label .. '  [' .. action.kind .. ']')
                actionNode.TimelineComponent = component
                actionNode.TimelineDrop = {component = component, action = action}
                actionNode:Droppable('LUASQUARE_TIMELINE_COMPONENT')
                actionNode.DoDoubleClick = function()
                    self:AddDropAt(actionNode.TimelineDrop,
                        LABEL_WIDTH + self.Session.playhead * self.Session.zoom - self.Session.scrollX,
                        RULER_HEIGHT + 4)
                end
            end
            for _, timeline in ipairs(component.timelines or {}) do
                local timelineNode = node:AddNode(timeline.label .. '  [timeline]')
                timelineNode.TimelineComponent = component
                timelineNode.TimelineDrop = {component = component, timeline = timeline}
                timelineNode:Droppable('LUASQUARE_TIMELINE_COMPONENT')
                timelineNode.DoDoubleClick = function()
                    self:AddDropAt(timelineNode.TimelineDrop,
                        LABEL_WIDTH + self.Session.playhead * self.Session.zoom - self.Session.scrollX,
                        RULER_HEIGHT + 4)
                end
            end
        end
        categoryNode:SetExpanded(true)
    end
    if not self.Session.ownerId and catalog.components and catalog.components[1] then
        self.Session.ownerId = catalog.components[1].id
    end
    self:PopulateSources()
    self:RebuildInspector()
end

function Editor:OpenAddTrackMenu()
    local menu = DermaMenu()
    local categories = {}
    for _, component in ipairs((TIMELINE.ClientCatalog and TIMELINE.ClientCatalog.components) or {}) do
        if #(component.actions or {}) > 0 or #(component.timelines or {}) > 0 then
            local category = componentCategory(component)
            categories[category] = categories[category] or {}
            table.insert(categories[category], component)
        end
    end
    for category, components in SortedPairs(categories) do
        local submenu = menu:AddSubMenu(category)
        for _, component in ipairs(components) do
            local entry = component
            submenu:AddOption(entry.label, function()
                self:AddComponentAt(entry,
                    LABEL_WIDTH + self.Session.playhead * self.Session.zoom - self.Session.scrollX)
            end)
        end
    end
    menu:Open()
end

function Editor:AddClipMenu(menu, trackIndex, at)
    local track = sourceTrack(self.Session, trackIndex)
    local component = self:ComponentForTrack(track)
    if not component then
        menu:AddOption('Component is unresolved', function() end):SetEnabled(false)
        return
    end
    local actionMenu = menu:AddSubMenu('Add action clip')
    for _, action in ipairs(component.actions or {}) do
        local actionDefinition = action
        actionMenu:AddOption(actionDefinition.label .. ' [' .. actionDefinition.kind .. ']', function()
            self:AddDropAt({component = component, action = actionDefinition},
                LABEL_WIDTH + at * self.Session.zoom - self.Session.scrollX,
                RULER_HEIGHT + (trackIndex - 1) * TRACK_HEIGHT - self.Session.scrollY + 4)
        end)
    end
    if #(component.timelines or {}) > 0 then
        local timelineMenu = menu:AddSubMenu('Add child timeline')
        for _, timeline in ipairs(component.timelines or {}) do
            local definition = timeline
            timelineMenu:AddOption(definition.label, function()
                self:AddDropAt({component = component, timeline = definition},
                    LABEL_WIDTH + at * self.Session.zoom - self.Session.scrollX,
                    RULER_HEIGHT + (trackIndex - 1) * TRACK_HEIGHT - self.Session.scrollY + 4)
            end)
        end
    end
end

function Editor:AddComponentAt(component, x)
    if self.Session.readOnly then return end
    local action = component.actions and component.actions[1]
    local childTimeline = component.timelines and component.timelines[1]
    if not action and not childTimeline then return end
    self:AddDropAt({component = component, action = action, timeline = not action and childTimeline or nil}, x,
        RULER_HEIGHT + #(self.Session.source.tracks or {}) * TRACK_HEIGHT + 4)
end

function Editor:MakeClip(drop, at, source)
    local action = drop.action
    local timeline = drop.timeline
    local base = action and action.id or (timeline and timeline.id or 'clip')
    local clip = {
        id = uniqueId(source, 'clip_' .. base, true),
        label = action and action.label or (timeline and timeline.label or base),
        kind = action and action.kind or 'timeline',
        at = self:SnapTime(at),
        required = false
    }
    if action then
        clip.action = action.id
        clip.params = {}
        for _, parameter in ipairs(action.parameters or {}) do
            if parameter.default ~= nil then clip.params[parameter.id] = TIMELINE.DeepCopy(parameter.default) end
        end
        if action.kind == 'duration' then clip.duration = math.max(tonumber(action.defaultDuration) or 1, 0.01) end
        if action.kind == 'number' then
            clip.duration = 1
            clip.from = tonumber(action.min) or 0
            clip.to = tonumber(action.max) or 1
            clip.curve = 'linear'
        end
    else
        clip.timeline = timeline.id
    end
    return clip
end

function Editor:AddDropAt(drop, x, y)
    if self.Session.readOnly or not drop or not drop.component then return end
    local at = math.max((x + self.Session.scrollX - LABEL_WIDTH) / self.Session.zoom, 0)
    local row = math.floor((y + self.Session.scrollY - RULER_HEIGHT) / TRACK_HEIGHT) + 1
    local existing = sourceTrack(self.Session, row)
    local existingComponent = existing and self:ComponentForTrack(existing)
    if existing and (not existingComponent or existingComponent.id ~= drop.component.id) then
        notification.AddLegacy('That track targets ' .. tostring(existingComponent and existingComponent.label or 'another component') .. '.',
            NOTIFY_ERROR, 4)
        return
    end
    self:Commit(function(source)
        source.tracks = source.tracks or {}
        local trackIndex, track = row, source.tracks[row]
        if not track then
            trackIndex = #source.tracks + 1
            track = {
                id = uniqueId(source, 'track_' .. normalizeFileName(drop.component.id), false),
                label = drop.component.label,
                target = {component = drop.component.id},
                clips = {}
            }
            table.insert(source.tracks, track)
        end
        local clip = self:MakeClip(drop, at, source)
        table.insert(track.clips, clip)
        self.Session.selection = {track = trackIndex, clip = #track.clips}
    end, true)
end

function Editor:SnapTime(value, selection)
    value = math.max(tonumber(value) or 0, 0)
    local editor = self.Session.source.editor or {}
    if editor.snapEnabled == false then return math.Round(value, 3) end
    local interval = math.max(tonumber(editor.snapSeconds) or DEFAULT_SNAP_SECONDS, 0.01)
    local best = math.Round(value / interval) * interval
    local bestDistance = math.abs(best - value)
    local threshold = math.max(8 / math.max(self.Session.zoom, 1), interval * 0.35)
    local candidates = {0, self.Session.playhead}
    for trackIndex, track in ipairs(self.Session.source.tracks or {}) do
        for clipIndex, clip in ipairs(track.clips or {}) do
            if not selection or selection.track ~= trackIndex or selection.clip ~= clipIndex then
                local clipAt = tonumber(clip.at) or 0
                table.insert(candidates, clipAt)
                if clip.kind == 'duration' or clip.kind == 'number' then
                    table.insert(candidates, clipAt + (tonumber(clip.duration) or 0))
                end
            end
        end
    end
    for _, candidate in ipairs(candidates) do
        local distance = math.abs(candidate - value)
        if distance < bestDistance and distance <= threshold then best, bestDistance = candidate, distance end
    end
    self.Session.snapGuide = best
    return math.max(math.Round(best, 3), 0)
end

function Editor:AudioDurationForClip(track, clip)
    if not track or not clip or clip.kind ~= 'marker' then return nil end
    local component = self:ComponentForTrack(track)
    if not component or string.sub(component.id or '', 1, 6) ~= 'audio.' then return nil end
    if clip.action ~= 'play' and clip.action ~= 'enqueue' then return nil end
    local audio = LUASQUARE_AUDIO
    if component.type == 'audio.pa' and clip.action == 'enqueue' then
        local lineId = clip.params and clip.params.line
        local line = audio and audio.ClientCatalog and audio.ClientCatalog.paLines
            and audio.ClientCatalog.paLines[lineId]
        local channelId = string.sub(component.id or '', #'audio.pa:' + 1)
        local channel = audio and audio.ClientCatalog and audio.ClientCatalog.paChannels
            and audio.ClientCatalog.paChannels[channelId]
        if not line then return nil end
        local introId = line.introTone
        if introId == nil and channel then introId = channel.introTone end
        local intro = introId and audio.ClientCatalog.sounds[introId]
        local introDuration = intro and (tonumber(intro.duration) or 0)
            * 100 / math.max(tonumber(intro.pitch) or 100, 1) or 0
        local body = tonumber(line.duration) or 0
        local silence = channel and tonumber(channel.silenceSeconds) or 0
        local total = introDuration + body + silence
        return total > 0 and total or nil,
            {intro = introDuration, body = body, silence = silence}
    end
    local soundId = clip.params and clip.params.sound
    local definition = audio and audio.ClientCatalog and audio.ClientCatalog.sounds
        and audio.ClientCatalog.sounds[soundId]
    local duration = definition and tonumber(definition.duration)
    if duration and definition.mode ~= 'music' then
        duration = duration * 100 / math.max(tonumber(definition.pitch) or 100, 1)
    end
    return duration and duration > 0 and duration or nil
end

function Editor:UpdateScrollBounds()
    if not IsValid(self.Canvas) then return end
    local timeExtent = math.max(tonumber(self.Session.source.duration) or 0, 0)
    for _, track in ipairs(self.Session.source.tracks or {}) do
        for _, clip in ipairs(track.clips or {}) do
            local clipEnd = math.max(tonumber(clip.at) or 0, 0)
            if clip.kind == 'duration' or clip.kind == 'number' then
                clipEnd = clipEnd + math.max(tonumber(clip.duration) or 0, 0)
            else
                clipEnd = clipEnd + (self:AudioDurationForClip(track, clip) or 0)
            end
            timeExtent = math.max(timeExtent, clipEnd)
        end
    end
    local viewportWidth = math.max(self.Canvas:GetWide() - LABEL_WIDTH - SCROLLBAR_SIZE, 1)
    local viewportHeight = math.max(self.Canvas:GetTall() - SCROLLBAR_SIZE, 1)
    local timelineWidth = timeExtent * self.Session.zoom + 80
    local timelineHeight = RULER_HEIGHT + #(self.Session.source.tracks or {}) * TRACK_HEIGHT + 24
    self.Session.maxScrollX = math.max(timelineWidth - viewportWidth, 0)
    self.Session.maxScrollY = math.max(timelineHeight - viewportHeight, 0)
    self.Session.scrollViewportWidth = viewportWidth
    self.Session.scrollViewportHeight = viewportHeight
    self.Session.scrollX = TIMELINE.Clamp(self.Session.scrollX, 0, self.Session.maxScrollX)
    self.Session.scrollY = TIMELINE.Clamp(self.Session.scrollY, 0, self.Session.maxScrollY)
end

local function scrollThumb(viewport, maximum, length)
    if maximum <= 0 then return 0, length end
    local content = viewport + maximum
    local size = math.max(math.floor(length * viewport / content), 24)
    size = math.min(size, length)
    return length - size, size
end

function Editor:PaintHorizontalScroll(_, width, height)
    self:UpdateScrollBounds()
    surface.SetDrawColor(25, 28, 31)
    surface.DrawRect(0, 0, width, height)
    local travel, thumbWidth = scrollThumb(
        self.Session.scrollViewportWidth or 1, self.Session.maxScrollX or 0, width)
    local x = travel > 0 and (self.Session.scrollX / self.Session.maxScrollX) * travel or 0
    surface.SetDrawColor(self.Session.maxScrollX > 0 and Color(105, 115, 125) or Color(55, 60, 65))
    surface.DrawRect(x, 2, thumbWidth, math.max(height - 4, 1))
end

function Editor:PaintVerticalScroll(_, width, height)
    self:UpdateScrollBounds()
    surface.SetDrawColor(25, 28, 31)
    surface.DrawRect(0, 0, width, height)
    local travel, thumbHeight = scrollThumb(
        self.Session.scrollViewportHeight or 1, self.Session.maxScrollY or 0, height)
    local y = travel > 0 and (self.Session.scrollY / self.Session.maxScrollY) * travel or 0
    surface.SetDrawColor(self.Session.maxScrollY > 0 and Color(105, 115, 125) or Color(55, 60, 65))
    surface.DrawRect(2, y, math.max(width - 4, 1), thumbHeight)
end

function Editor:SetHorizontalScrollFromCursor(x)
    self:UpdateScrollBounds()
    local width = IsValid(self.HorizontalScroll) and self.HorizontalScroll:GetWide() or 1
    local travel, thumbWidth = scrollThumb(
        self.Session.scrollViewportWidth or 1, self.Session.maxScrollX or 0, width)
    if travel <= 0 then self.Session.scrollX = 0 return end
    local fraction = TIMELINE.Clamp((x - thumbWidth * 0.5) / travel, 0, 1)
    self.Session.scrollX = fraction * self.Session.maxScrollX
end

function Editor:SetVerticalScrollFromCursor(y)
    self:UpdateScrollBounds()
    local height = IsValid(self.VerticalScroll) and self.VerticalScroll:GetTall() or 1
    local travel, thumbHeight = scrollThumb(
        self.Session.scrollViewportHeight or 1, self.Session.maxScrollY or 0, height)
    if travel <= 0 then self.Session.scrollY = 0 return end
    local fraction = TIMELINE.Clamp((y - thumbHeight * 0.5) / travel, 0, 1)
    self.Session.scrollY = fraction * self.Session.maxScrollY
end

function Editor:ClipRect(trackIndex, clip)
    local x = LABEL_WIDTH + (tonumber(clip.at) or 0) * self.Session.zoom - self.Session.scrollX
    local y = RULER_HEIGHT + (trackIndex - 1) * TRACK_HEIGHT - self.Session.scrollY + 8
    local track = sourceTrack(self.Session, trackIndex)
    local audioDuration, audioSegments = self:AudioDurationForClip(track, clip)
    local isFixedWidth = clip.kind == 'marker' or clip.kind == 'timeline'
    local width = isFixedWidth and math.max((audioDuration or 0) * self.Session.zoom, 12)
        or math.max((tonumber(clip.duration) or 0) * self.Session.zoom, 12)
    return x, y, width, TRACK_HEIGHT - 16, audioDuration, audioSegments
end

local function paintAudioTail(x, y, width, height, duration, segments)
    if segments then
        local introWidth = segments.intro / duration * width
        local bodyWidth = segments.body / duration * width
        surface.SetDrawColor(210, 150, 55, 125)
        surface.DrawRect(x, y, introWidth, height)
        surface.SetDrawColor(135, 75, 185, 100)
        surface.DrawRect(x + introWidth, y, bodyWidth, height)
        surface.SetDrawColor(90, 100, 110, 120)
        surface.DrawRect(x + introWidth + bodyWidth, y,
            math.max(width - introWidth - bodyWidth, 0), height)
    end
    surface.SetDrawColor(175, 110, 205, 90)
    local stripeHeight = math.max(height - 6, 1)
    for stripeX = x + 12, x + width, 8 do surface.DrawRect(stripeX, y + 3, 3, stripeHeight) end
    surface.SetDrawColor(225, 160, 245)
    surface.DrawRect(x, y, 4, height)
    draw.SimpleText(string.format('%.2fs', duration), 'DermaDefault',
        x + 6, y + height - 16, Color(240, 210, 250))
end

function Editor:PaintTimeline(width, height)
    self:UpdateScrollBounds()
    surface.SetDrawColor(14, 17, 20, 224)
    surface.DrawRect(0, 0, width, height)
    surface.SetDrawColor(45, 50, 55)
    surface.DrawRect(0, 0, LABEL_WIDTH, height)
    surface.SetDrawColor(32, 36, 40)
    surface.DrawRect(LABEL_WIDTH, 0, width - LABEL_WIDTH, RULER_HEIGHT)
    local duration = math.max(tonumber(self.Session.source.duration) or 5, 1)
    local simulation = TIMELINE.SimulateSource(
        self.Session.compiled, self.Session.playhead, self.Session.mutedTracks)
    self.Session.simulation = simulation
    local firstSecond = math.max(math.floor(self.Session.scrollX / self.Session.zoom), 0)
    local lastSecond = math.ceil((self.Session.scrollX + width - LABEL_WIDTH) / self.Session.zoom)
    for second = firstSecond, math.min(lastSecond, math.ceil(duration) + 20) do
        local x = LABEL_WIDTH + second * self.Session.zoom - self.Session.scrollX
        surface.SetDrawColor(70, 75, 80)
        surface.DrawLine(x, 0, x, height)
        draw.SimpleText(second .. 's', 'DermaDefault', x + 3, 6, Color(200, 205, 210))
    end
    for trackIndex, track in ipairs(self.Session.source.tracks or {}) do
        local y = RULER_HEIGHT + (trackIndex - 1) * TRACK_HEIGHT - self.Session.scrollY
        if y + TRACK_HEIGHT >= RULER_HEIGHT and y <= height then
            local trackSelected = self.Session.selection and self.Session.selection.track == trackIndex
                and not self.Session.selection.clip
            surface.SetDrawColor(trackSelected and Color(42, 49, 55, 235)
                or (trackIndex % 2 == 0 and Color(25, 31, 35, 224) or Color(29, 31, 35, 224)))
            surface.DrawRect(LABEL_WIDTH, y, width - LABEL_WIDTH, TRACK_HEIGHT)
            surface.SetDrawColor(60, 65, 70)
            surface.DrawLine(0, y + TRACK_HEIGHT - 1, width, y + TRACK_HEIGHT - 1)
            local muted = self.Session.mutedTracks[track.id]
            draw.SimpleText((muted and '[M] ' or '') .. tostring(track.label or track.id),
                'DermaDefaultBold', 8, y + 10, muted and Color(150, 150, 150) or Color(230, 230, 230))
            draw.SimpleText(tostring(track.id), 'DermaDefault', 8, y + 29, Color(150, 155, 160))
            for clipIndex, clip in ipairs(track.clips or {}) do
                local x, clipY, clipWidth, clipHeight, audioDuration, audioSegments
                    = self:ClipRect(trackIndex, clip)
                if x + clipWidth >= LABEL_WIDTH and x <= width then
                    local selected = self.Session.selection and self.Session.selection.track == trackIndex
                        and self.Session.selection.clip == clipIndex
                    local state = simulation.clips[clip.id]
                    local active = state and state.status == 'active'
                    local completed = state and state.status == 'completed'
                    local color = active and Color(70, 160, 210)
                        or (completed and Color(48, 125, 105) or Color(50, 105, 145))
                    if muted then color = Color(75, 75, 75) end
                    surface.SetDrawColor(color)
                    surface.DrawRect(x, clipY, clipWidth, clipHeight)
                    if audioDuration then
                        paintAudioTail(x, clipY, clipWidth, clipHeight, audioDuration, audioSegments)
                    end
                    surface.SetDrawColor(selected and Color(255, 210, 65) or Color(130, 190, 225))
                    surface.DrawOutlinedRect(x, clipY, clipWidth, clipHeight, selected and 2 or 1)
                    if clipWidth > 30 then
                        draw.SimpleText(tostring(clip.label or clip.id), 'DermaDefault', x + 5,
                            clipY + 7, Color(245, 245, 245), TEXT_ALIGN_LEFT)
                    end
                end
            end
        end
    end
    local playheadX = LABEL_WIDTH + self.Session.playhead * self.Session.zoom - self.Session.scrollX
    surface.SetDrawColor(255, 185, 45)
    surface.DrawLine(playheadX, 0, playheadX, height)
    draw.SimpleText(string.format('%.2f', self.Session.playhead), 'DermaDefaultBold',
        playheadX + 4, height - 18, Color(255, 205, 80))
    draw.NoTexture()
    surface.DrawPoly({
        {x = playheadX - 5, y = 0}, {x = playheadX + 5, y = 0}, {x = playheadX, y = 8}
    })
    if self.Session.livePreviewTime then
        local liveX = LABEL_WIDTH + self.Session.livePreviewTime * self.Session.zoom - self.Session.scrollX
        surface.SetDrawColor(80, 235, 255)
        surface.DrawLine(liveX, 0, liveX, height)
        draw.SimpleText('LIVE ' .. string.format('%.2f', self.Session.livePreviewTime), 'DermaDefaultBold',
            liveX + 4, 4, Color(100, 240, 255))
    end
    if self.Session.snapGuide and (self.Drag or self.PlayheadDrag) then
        local snapX = LABEL_WIDTH + self.Session.snapGuide * self.Session.zoom - self.Session.scrollX
        surface.SetDrawColor(120, 230, 170, 180)
        surface.DrawLine(snapX, RULER_HEIGHT, snapX, height)
    end
end

function Editor:HitClip(x, y)
    for trackIndex = #(self.Session.source.tracks or {}), 1, -1 do
        local track = self.Session.source.tracks[trackIndex]
        for clipIndex = #(track.clips or {}), 1, -1 do
            local clip = track.clips[clipIndex]
            local cx, cy, cw, ch = self:ClipRect(trackIndex, clip)
            if x >= cx and x <= cx + cw and y >= cy and y <= cy + ch then
                return trackIndex, clipIndex, clip, x >= cx + cw - 7
            end
        end
    end
end

function Editor:TrackAt(y)
    local index = math.floor((y + self.Session.scrollY - RULER_HEIGHT) / TRACK_HEIGHT) + 1
    return sourceTrack(self.Session, index) and index or nil
end

function Editor:SetPlayheadFromCursor(x)
    local value = math.max((x + self.Session.scrollX - LABEL_WIDTH) / self.Session.zoom, 0)
    value = math.min(value, tonumber(self.Session.source.duration) or value)
    self.Session.playhead = self:SnapTime(value)
    if self.Session.playing then self.Session.playStartedAt = RealTime() - self.Session.playhead end
    self.Audio:SeekTimeline(self.Session.playhead)
end

function Editor:OpenTrackContext(trackIndex, at)
    local track = sourceTrack(self.Session, trackIndex)
    if not track then return end
    self.Session.selection = {track = trackIndex}
    self:RebuildInspector()
    local menu = DermaMenu()
    self:AddClipMenu(menu, trackIndex, at)
    menu:AddSpacer()
    menu:AddOption('Edit track properties', function()
        self.Session.selection = {track = trackIndex}
        self:RebuildInspector()
    end)
    menu:AddOption(self.Session.mutedTracks[track.id] and 'Unmute preview track' or 'Mute preview track', function()
        self.Session.mutedTracks[track.id] = not self.Session.mutedTracks[track.id]
    end)
    menu:AddOption('Move track up', function() self:MoveTrack(trackIndex, -1) end)
    menu:AddOption('Move track down', function() self:MoveTrack(trackIndex, 1) end)
    menu:AddOption('Duplicate track', function() self:DuplicateTrack(trackIndex) end)
    menu:AddSpacer()
    menu:AddOption('Delete track', function() self:DeleteTrack(trackIndex) end)
    menu:Open()
end

function Editor:TimelineMousePressed(code)
    local x, y = self.Canvas:LocalCursorPos()
    if code == MOUSE_MIDDLE then
        self:UpdateScrollBounds()
        self.Pan = {startX = x, startY = y, scrollX = self.Session.scrollX, scrollY = self.Session.scrollY}
        self.Canvas:SetCursor('sizeall')
        self.Canvas:MouseCapture(true)
        return
    end
    if code == MOUSE_RIGHT then
        local trackIndex, clipIndex = self:HitClip(x, y)
        if clipIndex then
            local menu = DermaMenu()
            menu:AddOption('Duplicate clip', function() self:DuplicateClip(trackIndex, clipIndex) end)
            menu:AddOption('Delete clip', function() self:DeleteClip(trackIndex, clipIndex) end)
            menu:Open()
            return
        end
        local index = self:TrackAt(y)
        if index then
            local at = math.max((x + self.Session.scrollX - LABEL_WIDTH) / self.Session.zoom, 0)
            self:OpenTrackContext(index, self:SnapTime(at))
        else
            local menu = DermaMenu()
            menu:AddOption('Add track...', function() self:OpenAddTrackMenu() end)
            menu:Open()
        end
        return
    end
    if code ~= MOUSE_LEFT then return end

    local playheadX = LABEL_WIDTH + self.Session.playhead * self.Session.zoom - self.Session.scrollX
    if y <= RULER_HEIGHT or math.abs(x - playheadX) <= 6 then
        self.PlayheadDrag = true
        self.Canvas:MouseCapture(true)
        self:SetPlayheadFromCursor(x)
        return
    end
    local trackIndex, clipIndex, clip, resize = self:HitClip(x, y)
    if clip then
        self.Session.selection = {track = trackIndex, clip = clipIndex}
        local track = sourceTrack(self.Session, trackIndex)
        local component = self:ComponentForTrack(track)
        local node = component and self.ComponentNodes and self.ComponentNodes[component.id]
        if node then self.Explorer:SetSelectedItem(node) end
        self:RebuildInspector()
        if not self.Session.readOnly then
            local resizable = self:IsClipResizable(trackIndex, clip)
            self.Drag = {
                track = trackIndex, clip = clipIndex, resize = resize and resizable,
                startX = x, originalAt = tonumber(clip.at) or 0,
                originalDuration = tonumber(clip.duration) or 0,
                before = TIMELINE.DeepCopy(self.Session.source), moved = false
            }
            self.Canvas:MouseCapture(true)
        end
        return
    end
    local track = self:TrackAt(y)
    self.Session.selection = track and x < LABEL_WIDTH and {track = track} or nil
    if not track or x >= LABEL_WIDTH then
        self.PlayheadDrag = true
        self.Canvas:MouseCapture(true)
        self:SetPlayheadFromCursor(x)
    end
    self:RebuildInspector()
end

function Editor:IsClipResizable(trackIndex, clip)
    if clip.kind == 'marker' or clip.kind == 'timeline' then return false end
    local component = self:ComponentForTrack(sourceTrack(self.Session, trackIndex))
    for _, action in ipairs(component and component.actions or {}) do
        if action.id == clip.action then return action.resizable ~= false end
    end
    return false
end

function Editor:TimelineMouseMoved(x, y)
    if self.Pan then
        self.Session.scrollX = TIMELINE.Clamp(
            self.Pan.scrollX - (x - self.Pan.startX), 0, self.Session.maxScrollX or 0)
        self.Session.scrollY = TIMELINE.Clamp(
            self.Pan.scrollY - (y - self.Pan.startY), 0, self.Session.maxScrollY or 0)
        return
    end
    if self.PlayheadDrag then
        self:SetPlayheadFromCursor(x)
        return
    end
    if not self.Drag then
        local trackIndex, _, clip, resize = self:HitClip(x, y)
        if clip and resize and self:IsClipResizable(trackIndex, clip) then
            self.Canvas:SetCursor('sizewe')
        else
            self.Canvas:SetCursor('arrow')
        end
        return
    end
    local clip = sourceClip(self.Session, self.Drag)
    if not clip then return end
    local delta = (x - self.Drag.startX) / self.Session.zoom
    if math.abs(delta) < 0.01 then return end
    self.Drag.moved = true
    if self.Drag.resize then
        local endAt = self:SnapTime(self.Drag.originalAt + self.Drag.originalDuration + delta, self.Drag)
        clip.duration = math.max(math.Round(endAt - (tonumber(clip.at) or 0), 3), 0)
    else
        clip.at = self:SnapTime(self.Drag.originalAt + delta, self.Drag)
    end
end

function Editor:TimelineMouseReleased(code)
    if code == MOUSE_MIDDLE and self.Pan then
        self.Pan = nil
        self.Canvas:SetCursor('arrow')
        self.Canvas:MouseCapture(false)
        return
    end
    if code == MOUSE_LEFT and self.PlayheadDrag then
        self.PlayheadDrag = nil
        self.Session.snapGuide = nil
        self.Canvas:MouseCapture(false)
        return
    end
    if code ~= MOUSE_LEFT or not self.Drag then return end
    local drag = self.Drag
    self.Drag = nil
    self.Session.snapGuide = nil
    self.Canvas:MouseCapture(false)
    if drag.moved then
        table.insert(self.Session.history, drag.before)
        self.Session.future = {}
        self:Compile(true)
    end
end

function Editor:DuplicateClip(trackIndex, clipIndex)
    self:Commit(function(source)
        local track = source.tracks[trackIndex]
        local copy = TIMELINE.DeepCopy(track.clips[clipIndex])
        copy.id = uniqueId(source, copy.id .. '_copy', true)
        copy.at = self:SnapTime((tonumber(copy.at) or 0) + 0.25)
        table.insert(track.clips, clipIndex + 1, copy)
        self.Session.selection = {track = trackIndex, clip = clipIndex + 1}
    end, true)
end

function Editor:DuplicateTrack(trackIndex)
    self:Commit(function(source)
        local original = source.tracks[trackIndex]
        if not original then return end
        local copy = TIMELINE.DeepCopy(original)
        copy.id = uniqueId(source, copy.id .. '_copy', false)
        copy.label = tostring(copy.label or copy.id) .. ' Copy'
        for _, clip in ipairs(copy.clips or {}) do
            clip.id = uniqueId(source, clip.id .. '_copy', true)
        end
        table.insert(source.tracks, trackIndex + 1, copy)
        self.Session.selection = {track = trackIndex + 1}
    end, true)
end

function Editor:MoveTrack(trackIndex, direction)
    local target = trackIndex + direction
    if target < 1 or target > #(self.Session.source.tracks or {}) then return end
    self:Commit(function(source)
        source.tracks[trackIndex], source.tracks[target] = source.tracks[target], source.tracks[trackIndex]
        self.Session.selection = {track = target}
    end, true)
end

function Editor:DeleteClip(trackIndex, clipIndex)
    self:Commit(function(source)
        table.remove(source.tracks[trackIndex].clips, clipIndex)
        self.Session.selection = nil
    end, true)
end

function Editor:DeleteTrack(trackIndex)
    local track = sourceTrack(self.Session, trackIndex)
    if track then self.Session.mutedTracks[track.id] = nil end
    self:Commit(function(source)
        table.remove(source.tracks, trackIndex)
        self.Session.selection = nil
    end, true)
end

function Editor:ComponentForTrack(track)
    local target = TIMELINE.MakeTarget(track and track.target)
    if not target then return nil end
    local componentId
    if target.kind == 'component' then
        componentId = target.id
    elseif target.kind == 'self' then
        componentId = self.Session.ownerId
    elseif target.kind == 'child' then
        for _, component in ipairs((TIMELINE.ClientCatalog and TIMELINE.ClientCatalog.components) or {}) do
            if component.id == self.Session.ownerId then
                componentId = component.children and component.children[target.id]
                break
            end
        end
    end
    for _, component in ipairs((TIMELINE.ClientCatalog and TIMELINE.ClientCatalog.components) or {}) do
        if component.id == componentId then return component end
    end
end

function Editor:RebuildInspector()
    if not IsValid(self.Inspector) then return end
    self.Inspector:Clear()
    local clip = sourceClip(self.Session, self.Session.selection)
    local track = self.Session.selection and sourceTrack(self.Session, self.Session.selection.track)
    if clip then
        self:BuildClipInspector(clip)
    elseif track then
        self:BuildTrackInspector(track, self.Session.selection.track)
    else
        self:BuildRootInspector()
    end
end

function Editor:BuildTrackInspector(track, trackIndex)
    addLabel(self.Inspector, 'TRACK')
    addText(self.Inspector, 'ID', track.id, function(value)
        value = normalizeFileName(value)
        for index, other in ipairs(self.Session.source.tracks or {}) do
            if index ~= trackIndex and other.id == value then
                notification.AddLegacy('Track ID already exists.', NOTIFY_ERROR, 3)
                return
            end
        end
        self:Commit(function() track.id = value end)
    end)
    addText(self.Inspector, 'Label', track.label, function(value)
        self:Commit(function() track.label = value end)
    end)
    addLabel(self.Inspector, 'Target component')
    local picker = self.Inspector:Add('DComboBox')
    picker:Dock(TOP)
    picker:DockMargin(4, 0, 4, 4)
    local current = self:ComponentForTrack(track)
    picker:SetValue(current and current.label or 'Unresolved target')
    for _, component in ipairs((TIMELINE.ClientCatalog and TIMELINE.ClientCatalog.components) or {}) do
        picker:AddChoice(component.label .. ' [' .. component.id .. ']', component)
    end
    picker.OnSelect = function(_, _, _, component)
        self:Commit(function()
            track.target = {component = component.id}
            track.label = track.label or component.label
        end, true)
    end
    local add = self.Inspector:Add('DButton')
    add:Dock(TOP)
    add:DockMargin(4, 4, 4, 4)
    add:SetText('Add clip at playhead...')
    add.DoClick = function()
        local menu = DermaMenu()
        self:AddClipMenu(menu, trackIndex, self.Session.playhead)
        menu:Open()
    end
    local muted = self.Inspector:Add('DCheckBoxLabel')
    muted:Dock(TOP)
    muted:DockMargin(4, 4, 4, 4)
    muted:SetText('Mute during editor preview')
    muted:SetValue(self.Session.mutedTracks[track.id] and 1 or 0)
    muted.OnChange = function(_, checked) self.Session.mutedTracks[track.id] = checked and true or nil end
    addLabel(self.Inspector, tostring(#(track.clips or {})) .. ' clip(s)')
end

function Editor:BuildRootInspector()
    local source = self.Session.source
    addLabel(self.Inspector, 'TIMELINE')
    addText(self.Inspector, 'ID', source.id, function(value)
        self:Commit(function(data) data.id = normalizeFileName(value) end)
    end)
    addText(self.Inspector, 'Label', source.label, function(value)
        self:Commit(function(data) data.label = value end)
    end)
    addText(self.Inspector, 'Channel', source.channel, function(value)
        self:Commit(function(data) data.channel = normalizeFileName(value) end)
    end)
    addLabel(self.Inspector, 'Conflict policy')
    local conflict = self.Inspector:Add('DComboBox')
    conflict:Dock(TOP)
    conflict:DockMargin(4, 0, 4, 3)
    conflict:SetValue(source.conflictPolicy or 'reject')
    for _, value in ipairs({'reject', 'replace', 'ignore'}) do conflict:AddChoice(value, value) end
    conflict.OnSelect = function(_, _, _, value)
        self:Commit(function(data) data.conflictPolicy = value end)
    end
    addLabel(self.Inspector, 'Restart policy')
    local restart = self.Inspector:Add('DComboBox')
    restart:Dock(TOP)
    restart:DockMargin(4, 0, 4, 3)
    restart:SetValue(source.restartPolicy or 'reject')
    for _, value in ipairs({'reject', 'restart', 'ignore'}) do restart:AddChoice(value, value) end
    restart.OnSelect = function(_, _, _, value)
        self:Commit(function(data) data.restartPolicy = value end)
    end
    addNumber(self.Inspector, 'Duration', source.duration, 0, 600, 2, function(value)
        self:Commit(function(data) data.duration = value end)
    end)

    addLabel(self.Inspector, 'Binding owner')
    local owner = self.Inspector:Add('DComboBox')
    owner:Dock(TOP)
    owner:DockMargin(4, 0, 4, 4)
    owner:SetValue(self.Session.ownerId or 'Select owner')
    for _, component in ipairs((TIMELINE.ClientCatalog and TIMELINE.ClientCatalog.components) or {}) do
        owner:AddChoice(component.label, component.id, component.id == self.Session.ownerId)
    end
    owner.OnSelect = function(_, _, _, id)
        self.Session.ownerId = id
        self:RebuildInspector()
    end

    addLabel(self.Inspector, 'REFERENCE AUDIO (EDITOR ONLY)')
    local audio = source.editor and source.editor.referenceAudio or {}
    addText(self.Inspector, 'GAME path', audio.path, function(value)
        self:Commit(function(data)
            data.editor = data.editor or {}
            data.editor.referenceAudio = data.editor.referenceAudio or {}
            data.editor.referenceAudio.path = value
        end)
    end)
    addNumber(self.Inspector, 'Timeline start', audio.timelineStartSeconds, -120, 600, 2, function(value)
        self:Commit(function(data)
            data.editor = data.editor or {}
            data.editor.referenceAudio = data.editor.referenceAudio or {}
            data.editor.referenceAudio.timelineStartSeconds = value
        end)
    end)
    addNumber(self.Inspector, 'Volume', audio.volume or 1, 0, 1, 2, function(value)
        self:Commit(function(data)
            data.editor = data.editor or {}
            data.editor.referenceAudio = data.editor.referenceAudio or {}
            data.editor.referenceAudio.volume = value
        end)
        self.Audio:SetVolume(value)
    end)

    addLabel(self.Inspector, 'LIFECYCLE HANDLERS')
    for _, phase in ipairs({'startGuard', 'runGuard', 'onStart', 'onCancel', 'onComplete'}) do
        local phaseId = phase
        addText(self.Inspector, phaseId, source.lifecycle and source.lifecycle[phaseId], function(value)
            self:Commit(function(data)
                data.lifecycle = data.lifecycle or {}
                data.lifecycle[phaseId] = value ~= '' and value or nil
            end)
        end)
    end
end

function Editor:BuildClipInspector(clip)
    local selection = self.Session.selection
    local track = sourceTrack(self.Session, selection.track)
    local component = self:ComponentForTrack(track)
    addLabel(self.Inspector, 'CLIP · ' .. tostring(component and component.label or track.label))
    addText(self.Inspector, 'ID', clip.id, function(value)
        self:Commit(function() clip.id = normalizeFileName(value) end)
    end)
    addText(self.Inspector, 'Label', clip.label, function(value)
        self:Commit(function() clip.label = value end)
    end)
    addNumber(self.Inspector, 'At', clip.at, 0, 600, 2, function(value)
        self:Commit(function() clip.at = value end)
    end)
    if clip.kind == 'duration' or clip.kind == 'number' then
        addNumber(self.Inspector, 'Duration', clip.duration, 0, 600, 2, function(value)
            self:Commit(function() clip.duration = value end)
        end)
    end
    local required = self.Inspector:Add('DCheckBoxLabel')
    required:Dock(TOP)
    required:DockMargin(4, 3, 4, 3)
    required:SetText('Required')
    required:SetValue(clip.required and 1 or 0)
    required.OnChange = function(_, value) self:Commit(function() clip.required = value and true or false end) end

    if clip.kind == 'timeline' then
        addText(self.Inspector, 'Child timeline', clip.timeline, function(value)
            self:Commit(function() clip.timeline = normalizeFileName(value) end)
        end)
        return
    end
    addLabel(self.Inspector, 'Action')
    local actionPicker = self.Inspector:Add('DComboBox')
    actionPicker:Dock(TOP)
    actionPicker:DockMargin(4, 0, 4, 4)
    actionPicker:SetValue(clip.action or 'Select action')
    local selectedAction
    for _, action in ipairs(component and component.actions or {}) do
        actionPicker:AddChoice(action.label .. ' [' .. action.kind .. ']', action, action.id == clip.action)
        if action.id == clip.action then selectedAction = action end
    end
    actionPicker.OnSelect = function(_, _, _, action)
        self:Commit(function()
            clip.action = action.id
            clip.kind = action.kind
            clip.params = {}
            if action.kind == 'duration' then clip.duration = math.max(tonumber(clip.duration) or 1, 0.05) end
            if action.kind == 'number' then
                clip.duration = math.max(tonumber(clip.duration) or 1, 0)
                clip.from = tonumber(action.min) or 0
                clip.to = tonumber(action.max) or 1
                clip.curve = 'linear'
            end
        end, true)
    end
    if clip.kind == 'number' then
        addNumber(self.Inspector, 'From', clip.from, selectedAction and selectedAction.min or -10000,
            selectedAction and selectedAction.max or 10000, selectedAction and selectedAction.decimals or 3,
            function(value) self:Commit(function() clip.from = value end) end)
        addNumber(self.Inspector, 'To', clip.to, selectedAction and selectedAction.min or -10000,
            selectedAction and selectedAction.max or 10000, selectedAction and selectedAction.decimals or 3,
            function(value) self:Commit(function() clip.to = value end) end)
        addLabel(self.Inspector, 'Curve')
        local curve = self.Inspector:Add('DComboBox')
        curve:Dock(TOP)
        curve:DockMargin(4, 0, 4, 4)
        curve:SetValue(clip.curve or 'linear')
        for _, value in ipairs({'linear', 'smoothstep', 'ease_in', 'ease_out', 'ease_in_out'}) do
            curve:AddChoice(value, value, value == clip.curve)
        end
        curve.OnSelect = function(_, _, _, value) self:Commit(function() clip.curve = value end) end
    end
    for _, parameter in ipairs(selectedAction and selectedAction.parameters or {}) do
        local definition = parameter
        clip.params = clip.params or {}
        local value = clip.params[definition.id]
        if value == nil then value = definition.default end
        if definition.type == 'number' then
            addNumber(self.Inspector, definition.label, value, definition.min or -10000,
                definition.max or 10000, definition.decimals or 2, function(newValue)
                    self:Commit(function() clip.params[definition.id] = newValue end)
                end)
        elseif definition.type == 'boolean' then
            local checkbox = self.Inspector:Add('DCheckBoxLabel')
            checkbox:Dock(TOP)
            checkbox:DockMargin(4, 3, 4, 3)
            checkbox:SetText(definition.label)
            checkbox:SetValue(value and 1 or 0)
            checkbox.OnChange = function(_, checked)
                self:Commit(function() clip.params[definition.id] = checked and true or false end)
            end
        elseif definition.type == 'enum' then
            addLabel(self.Inspector, definition.label)
            local picker = self.Inspector:Add('DComboBox')
            picker:Dock(TOP)
            picker:DockMargin(4, 0, 4, 4)
            picker:SetValue(tostring(value or ''))
            for _, choice in ipairs(definition.choices or {}) do picker:AddChoice(choice, choice, choice == value) end
            picker.OnSelect = function(_, _, _, choice)
                self:Commit(function() clip.params[definition.id] = choice end)
            end
        else
            addText(self.Inspector, definition.label, value, function(newValue)
                self:Commit(function() clip.params[definition.id] = newValue end)
            end)
        end
    end
end

function Editor:ShowDiagnostics()
    local _, diagnostics = TIMELINE.CompileSource(self.Session.source, self.Session.origin)
    Derma_Message(TIMELINE.DiagnosticsText(diagnostics), 'Timeline validation', 'OK')
end

function Editor:LoadReferenceAudio(showErrors)
    local audio = self.Session.source.editor and self.Session.source.editor.referenceAudio
    if not audio or not audio.path or audio.path == '' then
        if showErrors then Derma_Message('Set an editor reference-audio path first.', 'Reference audio', 'OK') end
        return false
    end
    return self.Audio:Load(audio, function(ok, message)
        if showErrors and not ok then Derma_Message(message, 'Reference audio failed', 'OK') end
    end)
end

function Editor:PlaySimulation()
    if not self.Session.compiled then self:ShowDiagnostics() return end
    self.Session.playing = true
    self.Session.playStartedAt = RealTime() - self.Session.playhead
    self.Audio:Play(self.Session.playhead)
end

function Editor:PauseSimulation()
    self.Session.playing = false
    self.Audio:Pause()
end

function Editor:StopPreview()
    self.Session.playing = false
    self.Audio:Pause()
    self.Session.livePreviewTime = nil
    self.Session.livePreviewStartedAt = nil
    self.Session.pendingLiveSeek = nil
    TIMELINE.StopLivePreview()
end

function Editor:ConfirmLivePreview()
    if not self.Session.compiled then self:ShowDiagnostics() return end
    if not self.Session.ownerId then
        Derma_Message('Select a binding owner in the inspector.', 'Live preview', 'OK')
        return
    end
    Derma_Query(
        'Live preview will actuate real registered map components.\nStopping it returns touched components to their declared safe state.',
        'Confirm live timeline preview', 'Start live preview', function()
            self.Session.pendingLiveSeek = self.Session.playhead
            local ok, reason = TIMELINE.SendLivePreview(self.Session.source, self.Session.ownerId,
                self.Session.playhead, self.Session.mutedTracks)
            if not ok then
                self.Session.pendingLiveSeek = nil
                Derma_Message(reason, 'Live preview failed', 'OK')
            end
        end, 'Cancel')
end

function Editor:Think()
    if self.Session.fullscreen and (self:GetWide() ~= ScrW() or self:GetTall() ~= ScrH()) then
        self:SetSize(ScrW(), ScrH())
        self:SetPos(0, 0)
    end
    if self.Session.playing then
        self.Session.playhead = RealTime() - self.Session.playStartedAt
        local duration = self.Session.compiled and self.Session.compiled.duration or 0
        if self.Session.playhead >= duration then
            self.Session.playhead = duration
            self:PauseSimulation()
        end
    end
    if self.Session.livePreviewStartedAt then
        local duration = self.Session.compiled and self.Session.compiled.duration or 0
        self.Session.livePreviewTime = math.min(CurTime() - self.Session.livePreviewStartedAt, duration)
        if self.Session.livePreviewTime >= duration then self.Session.livePreviewStartedAt = nil end
    end
    self.Audio:Update(self.Session.playhead, self.Session.playing)
end

vgui.Register('LUASQUARE_TIMELINE_Editor', Editor, 'DFrame')

function EDITOR.Open()
    if not game.SinglePlayer() then
        Derma_Message('The timeline editor is available only in single-player.', 'Timeline editor', 'OK')
        return nil
    end
    if IsValid(EDITOR.Window) then EDITOR.Window:MakePopup() return EDITOR.Window end
    EDITOR.Window = vgui.Create('LUASQUARE_TIMELINE_Editor')
    hook.Add('LUASQUARE_TIMELINE_CatalogUpdated', 'LUASQUARE_TIMELINE_EditorCatalog', function()
        if IsValid(EDITOR.Window) then EDITOR.Window:PopulateComponents() end
    end)
    hook.Add('LUASQUARE_TIMELINE_PreviewStatus', 'LUASQUARE_TIMELINE_EditorPreviewStatus', function(ok, message, runId)
        if IsValid(EDITOR.Window) then
            local lower = string.lower(tostring(message))
            if ok and runId and runId ~= '' and string.find(lower, 'started', 1, true) then
                local seek = tonumber(EDITOR.Window.Session.pendingLiveSeek) or 0
                EDITOR.Window.Session.livePreviewTime = seek
                EDITOR.Window.Session.livePreviewStartedAt = CurTime() - seek
                EDITOR.Window.Session.pendingLiveSeek = nil
            elseif not ok or not runId or runId == '' or string.find(lower, 'completed', 1, true)
                or string.find(lower, 'stopped', 1, true)
                or string.find(lower, 'cancelled', 1, true) then
                EDITOR.Window.Session.livePreviewTime = nil
                EDITOR.Window.Session.livePreviewStartedAt = nil
                EDITOR.Window.Session.pendingLiveSeek = nil
            end
            EDITOR.Window.Status:SetText((ok and 'OK · ' or 'ERROR · ') .. tostring(message))
        end
    end)
    TIMELINE.RequestCatalog()
    if LUASQUARE_AUDIO and LUASQUARE_AUDIO.RequestState then LUASQUARE_AUDIO.RequestState() end
    return EDITOR.Window
end
