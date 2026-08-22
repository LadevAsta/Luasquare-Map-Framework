if not CLIENT then return end

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
local DISPLAY = LUASQUARE_3D2D
local EDITOR = DISPLAY.Editor or {}
DISPLAY.Editor = EDITOR
EDITOR.Clipboard = EDITOR.Clipboard or nil

local CHUNK_BYTES = 48000
local transferSerial = 0

local function normalizeMap()
    return string.lower(string.gsub(game.GetMap() or 'unknown', '[^%w_%-]', '_'))
end

local function isArray(value)
    if type(value) ~= 'table' then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then return false end
        count = math.max(count, key)
    end
    for index = 1, count do if value[index] == nil then return false end end
    return true, count
end

local function encodeString(value)
    local encoded = util.TableToJSON({tostring(value)}, false) or '[""]'
    return string.sub(encoded, 2, -2)
end

local function canonicalJSON(value, depth)
    depth = depth or 0
    local prefix = string.rep('  ', depth)
    local childPrefix = string.rep('  ', depth + 1)
    if type(value) == 'string' then return encodeString(value) end
    if type(value) == 'number' then
        if value ~= value or value == math.huge or value == -math.huge then return 'null' end
        return tostring(value)
    end
    if type(value) == 'boolean' then return value and 'true' or 'false' end
    if type(value) ~= 'table' then return 'null' end

    local array, count = isArray(value)
    local parts = {}
    if array then
        for index = 1, count do
            parts[index] = childPrefix .. canonicalJSON(value[index], depth + 1)
        end
        if #parts == 0 then return '[]' end
        return '[\n' .. table.concat(parts, ',\n') .. '\n' .. prefix .. ']'
    end

    local keys = {}
    for key in pairs(value) do table.insert(keys, tostring(key)) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        table.insert(parts, childPrefix .. encodeString(key) .. ': ' .. canonicalJSON(value[key], depth + 1))
    end
    if #parts == 0 then return '{}' end
    return '{\n' .. table.concat(parts, ',\n') .. '\n' .. prefix .. '}'
end

local function defaultSource()
    return {
        schema = DISPLAY.Schema,
        kind = 'display',
        id = 'new_display',
        buildMode = 'complex',
        target = 'DISPLAY64x32_new_display',
        unitWidth = 64,
        unitHeight = 32,
        scale = 0.125,
        themeGroup = 'default',
        editorGrid = 8,
        editorSnapElements = true,
        showPageTabs = true,
        interaction = {enabled = true, distance = 128, lineOfSight = true},
        pages = {{id = 'overview', label = 'Overview', elements = {}}}
    }
end

local function canEdit()
    local player = LocalPlayer()
    return game.SinglePlayer() or (IsValid(player) and player:IsAdmin())
end

local function draftDirectory()
    return DISPLAY.DraftRoot .. '/' .. normalizeMap()
end

local function safeFileId(id)
    return DISPLAY.NormalizeId(id) or 'display'
end

local function listSources()
    local out = {}
    local packedRoot = DISPLAY.SourceRoot .. '/' .. normalizeMap()
    for _, name in ipairs(file.Find(packedRoot .. '/*.json', 'GAME') or {}) do
        table.insert(out, {label = 'Packed · ' .. name, path = packedRoot .. '/' .. name, realm = 'GAME', readOnly = true})
    end
    local draftRoot = draftDirectory()
    for _, name in ipairs(file.Find(draftRoot .. '/*.json', 'DATA') or {}) do
        table.insert(out, {label = 'Draft · ' .. name, path = draftRoot .. '/' .. name, realm = 'DATA', readOnly = false})
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

local function readSource(entry)
    local json = entry and file.Read(entry.path, entry.realm)
    local source = json and util.JSONToTable(json)
    if type(source) ~= 'table' then return nil, 'Unable to parse ' .. tostring(entry and entry.path) end
    if tostring(source.kind or 'display') ~= 'display' then return nil, 'The editor opens display sources only.' end
    return source
end

local function sendPreview(source, targetDisplay)
    if util.NetworkStringToID(DISPLAY.Net.EditorUpload) == 0 then
        return false, 'The server display runtime is not loaded.'
    end
    local json = canonicalJSON(source)
    local compressed = util.Compress(json)
    if not compressed or #compressed > 512 * 1024 then return false, 'Preview is too large.' end
    transferSerial = (transferSerial + 1) % 4294967295
    local count = math.max(math.ceil(#compressed / CHUNK_BYTES), 1)
    for index = 1, count do
        local first = (index - 1) * CHUNK_BYTES + 1
        local chunk = string.sub(compressed, first, first + CHUNK_BYTES - 1)
        net.Start(DISPLAY.Net.EditorUpload)
        net.WriteUInt(transferSerial, 32)
        net.WriteString(targetDisplay)
        net.WriteUInt(index, 16)
        net.WriteUInt(count, 16)
        net.WriteUInt(#chunk, 16)
        net.WriteData(chunk, #chunk)
        net.SendToServer()
    end
    return true
end

function EDITOR.ClearPreview(targetDisplay)
    targetDisplay = DISPLAY.NormalizeId(targetDisplay)
    if not targetDisplay then return end
    if util.NetworkStringToID(DISPLAY.Net.EditorClear) == 0 then return end
    net.Start(DISPLAY.Net.EditorClear)
    net.WriteString(targetDisplay)
    net.SendToServer()
end

local function makeSession()
    return {
        source = defaultSource(),
        origin = 'New source',
        readOnly = false,
        dirty = false,
        history = {},
        future = {},
        selection = nil,
        activePage = 1,
        themeSimulation = nil,
        diagnostics = {},
        compiled = nil,
        expandedNodes = {display = true},
        hitCycle = nil,
        rightClick = nil,
        previewTarget = nil
    }
end

local function snapshot(session)
    return DISPLAY.DeepCopy(session.source)
end

local function pushHistory(session)
    table.insert(session.history, snapshot(session))
    if #session.history > 100 then table.remove(session.history, 1) end
    session.future = {}
end

local function activePageSource(session)
    return session.source.pages and session.source.pages[session.activePage] or nil
end

local function selectionObject(session)
    local selection = session.selection
    if not selection then return nil end
    if selection.kind == 'display' then return session.source end
    if selection.kind == 'page' then return session.source.pages and session.source.pages[selection.page] end
    local page = session.source.pages and session.source.pages[selection.page]
    if selection.kind == 'element' then return page and page.elements and page.elements[selection.element] end
    if selection.kind == 'line' then
        if session.source.buildMode == 'simple' then return session.source.lines and session.source.lines[selection.line] end
        local element = page and page.elements and page.elements[selection.element]
        return element and element.lines and element.lines[selection.line]
    end
end

local elementTypeAliases = {
    linepanel = 'line_panel',
    line_panel = 'line_panel',
    material = 'material',
    solidrectangle = 'solid_rectangle',
    solid_rectangle = 'solid_rectangle',
    annunciator = 'annunciator'
}

local function normalizedElementType(value)
    return elementTypeAliases[string.lower(tostring(value or ''))]
end

local function selectionKey(selection, source)
    if not selection then return nil end
    if selection.kind == 'display' then return 'display' end
    local page = source.pages and source.pages[selection.page]
    local pageKey = page and tostring(page.id or selection.page) or tostring(selection.page or '')
    if selection.kind == 'page' then return 'page:' .. pageKey end
    local element = page and page.elements and page.elements[selection.element]
    local elementKey = element and tostring(element.id or selection.element) or tostring(selection.element or '')
    if selection.kind == 'element' then return 'element:' .. pageKey .. ':' .. elementKey end
    local line
    if source.buildMode == 'simple' then
        line = source.lines and source.lines[selection.line]
        return 'line:simple:' .. tostring(line and line.id or selection.line or '')
    end
    line = element and element.lines and element.lines[selection.line]
    return 'line:' .. pageKey .. ':' .. elementKey .. ':' .. tostring(line and line.id or selection.line or '')
end

local EditorPanel = {}

function EditorPanel:Init()
    self.Session = makeSession()
    self:SetTitle('Luasquare Source-Driven 3D2D Editor')
    self:SetSizable(false)
    self:SetDraggable(false)
    self:SetDeleteOnClose(true)
    self:SetSize(ScrW(), ScrH())
    self:SetPos(0, 0)

    self.Toolbar = self:Add('DPanel')
    self.Toolbar:Dock(TOP)
    self.Toolbar:SetTall(34)
    self.Toolbar:DockPadding(4, 3, 4, 3)

    self.SourcePicker = self.Toolbar:Add('DComboBox')
    self.SourcePicker:Dock(LEFT)
    self.SourcePicker:SetWide(250)
    self.SourcePicker:SetValue('Open packed source or draft…')
    self.SourcePicker.OnSelect = function(_, _, _, data)
        if self._refreshingSourcePicker then return end
        self:OpenEntry(data)
    end

    local function toolButton(label, callback, width)
        local button = self.Toolbar:Add('DButton')
        button:Dock(LEFT)
        button:DockMargin(4, 0, 0, 0)
        button:SetWide(width or 68)
        button:SetText(label)
        button.DoClick = callback
        return button
    end
    self.NewButton = toolButton('New', function()
        self:ConfirmDiscard(function() self:ReplaceSource(defaultSource(), 'New source', false) end)
    end, 54)
    self.SaveButton = toolButton('Save draft', function() self:SaveDraft() end, 80)
    self.UndoButton = toolButton('Undo', function() self:Undo() end, 54)
    self.RedoButton = toolButton('Redo', function() self:Redo() end, 54)
    self.ValidateButton = toolButton('Validate', function()
        self:Compile()
        local diagnostics = DISPLAY.DiagnosticsText(self.Session.diagnostics)
        Derma_Message(diagnostics ~= '' and diagnostics or 'Source is valid.', 'Display validation', 'OK')
    end, 65)

    self.ElementSnapButton = toolButton('Element snap: ON', function()
        local enabled = self.Session.source.editorSnapElements ~= false
        self:Changed(function() self.Session.source.editorSnapElements = not enabled end)
        self:RefreshSnapControls()
    end, 118)
    self.GridSlider = self.Toolbar:Add('DNumSlider')
    self.GridSlider:Dock(LEFT)
    self.GridSlider:DockMargin(6, -3, 0, -3)
    self.GridSlider:SetWide(205)
    self.GridSlider:SetText('Grid')
    self.GridSlider:SetMin(0)
    self.GridSlider:SetMax(128)
    self.GridSlider:SetDecimals(0)
    self.GridSlider.OnValueChanged = function(input, value)
        if input._ignore or self.Session.readOnly then return end
        if not input._historyOpen then pushHistory(self.Session) end
        input._historyOpen = true
        input._changeSerial = (input._changeSerial or 0) + 1
        local serial = input._changeSerial
        timer.Simple(0.35, function()
            if IsValid(input) and input._changeSerial == serial then input._historyOpen = false end
        end)
        self.Session.source.editorGrid = math.floor(tonumber(value) or 0)
        self.Session.dirty = true
        self:Compile()
    end

    self.ThemeEditorButton = self.Toolbar:Add('DButton')
    self.ThemeEditorButton:Dock(RIGHT)
    self.ThemeEditorButton:DockMargin(4, 0, 0, 0)
    self.ThemeEditorButton:SetWide(72)
    self.ThemeEditorButton:SetText('Themes')
    self.ThemeEditorButton.DoClick = function()
        if EDITOR.OpenThemeEditor then EDITOR.OpenThemeEditor(self) end
    end
    self.PreviewButton = self.Toolbar:Add('DButton')
    self.PreviewButton:Dock(RIGHT)
    self.PreviewButton:DockMargin(4, 0, 0, 0)
    self.PreviewButton:SetWide(76)
    self.PreviewButton:SetText('Preview')
    self.PreviewButton.DoClick = function() self:OpenPreviewWindow() end

    self.Body = self:Add('DHorizontalDivider')
    self.Body:Dock(FILL)
    self.Body:SetLeftWidth(245)
    self.Body:SetDividerWidth(5)

    self.HierarchyPanel = self.Body:Add('DPanel')
    self.HierarchyPanel:DockPadding(4, 4, 4, 4)
    self.Hierarchy = self.HierarchyPanel:Add('DTree')
    self.Hierarchy:Dock(FILL)
    self.Hierarchy.OnNodeSelected = function(_, node)
        if self._rebuildingHierarchy or not node.Selection then return end
        self:SetSelection(node.Selection, true)
    end
    self.Hierarchy.DoRightClick = function(_, node)
        if node and node.Selection then
            self:SetSelection(node.Selection, true)
            self:OpenSelectionMenu(node.Selection)
        end
        return true
    end
    self.Body:SetLeft(self.HierarchyPanel)

    self.Right = self.Body:Add('DHorizontalDivider')
    self.Right:SetLeftWidth(math.max(self:GetWide() - 560, 500))
    self.Right:SetDividerWidth(5)
    self.Body:SetRight(self.Right)

    self.PreviewCanvas = self.Right:Add('DPanel')
    self.PreviewCanvas:SetCursor('crosshair')
    self.PreviewCanvas.Paint = function(panel, width, height) self:PaintCanvas(panel, width, height) end
    self.PreviewCanvas.OnMousePressed = function(panel, code) self:CanvasPressed(panel, code) end
    self.PreviewCanvas.OnMouseReleased = function()
        local wasDragging = self.Drag and self.Drag.moved
        self.Drag = nil
        self.SnapGuides = nil
        self:Compile()
        if wasDragging then self.Session.hitCycle = nil end
        self:SyncHierarchySelection()
    end
    self.PreviewCanvas.OnCursorMoved = function(panel, x, y) self:CanvasMoved(panel, x, y) end
    self.Right:SetLeft(self.PreviewCanvas)

    self.Inspector = self.Right:Add('DScrollPanel')
    self.Right:SetRight(self.Inspector)

    self.Status = self:Add('DLabel')
    self.Status:Dock(BOTTOM)
    self.Status:SetTall(42)
    self.Status:SetWrap(true)
    self.Status:SetContentAlignment(4)
    self.Status:DockMargin(6, 2, 6, 2)

    self:RefreshSources()
    self:ReplaceSource(self.Session.source, self.Session.origin, false)
end

function EditorPanel:RefreshSources()
    self._refreshingSourcePicker = true
    self.SourcePicker:Clear()
    for _, entry in ipairs(listSources()) do self.SourcePicker:AddChoice(entry.label, entry) end
    self.SourcePicker:SetValue(self.Session.origin or 'Open packed source or draft...')
    self._refreshingSourcePicker = false
end

function EditorPanel:RefreshThemes()
    if IsValid(self.PreviewThemePicker) then self:PopulatePreviewThemes(self.PreviewThemePicker) end
end

function EditorPanel:RefreshSnapControls()
    if IsValid(self.ElementSnapButton) then
        local enabled = self.Session.source.editorSnapElements ~= false
        self.ElementSnapButton:SetText('Element snap: ' .. (enabled and 'ON' or 'OFF'))
        self.ElementSnapButton:SetEnabled(not self.Session.readOnly)
    end
    if IsValid(self.GridSlider) then
        self.GridSlider._ignore = true
        self.GridSlider:SetValue(tonumber(self.Session.source.editorGrid) or 8)
        self.GridSlider:SetEnabled(not self.Session.readOnly)
        self.GridSlider._ignore = false
    end
end

function EditorPanel:ConfirmDiscard(callback)
    if not self.Session.dirty then callback() return end
    Derma_Query(
        'Discard unsaved editor changes?',
        'Unsaved source',
        'Discard',
        callback,
        'Cancel',
        function() self:RefreshSources() end
    )
end

function EditorPanel:OpenEntry(entry)
    if not entry then self:RefreshSources() return end
    self:ConfirmDiscard(function()
        local source, message = readSource(entry)
        if source then
            self:ReplaceSource(source, entry.path, entry.readOnly)
        else
            Derma_Message(message, 'Open failed', 'OK')
            self:RefreshSources()
        end
    end)
end

function EditorPanel:ReplaceSource(source, origin, readOnly)
    self.Session = makeSession()
    self._skipExpansionCapture = true
    self.Session.source = DISPLAY.DeepCopy(source)
    self.Session.origin = origin
    self.Session.readOnly = readOnly and true or false
    self.Session.activePage = 1
    self.Session.selection = {kind = 'display'}
    self:Compile()
    self:RebuildHierarchy()
    self:RebuildInspector()
    self:RefreshSnapControls()
    self:RefreshSources()
end

function EditorPanel:Changed(callback)
    if self.Session.readOnly then
        Derma_Message('Packed data_static sources are read-only. Save this source as a draft before editing.', 'Read-only source', 'OK')
        return false
    end
    pushHistory(self.Session)
    callback()
    self.Session.dirty = true
    self:Compile()
    self:RebuildHierarchy()
    self:RebuildInspector()
    return true
end

function EditorPanel:Undo()
    local previous = table.remove(self.Session.history)
    if not previous then return end
    table.insert(self.Session.future, snapshot(self.Session))
    self.Session.source = previous
    self.Session.dirty = true
    self:Compile() self:RebuildHierarchy() self:RebuildInspector()
end

function EditorPanel:Redo()
    local nextSource = table.remove(self.Session.future)
    if not nextSource then return end
    table.insert(self.Session.history, snapshot(self.Session))
    self.Session.source = nextSource
    self.Session.dirty = true
    self:Compile() self:RebuildHierarchy() self:RebuildInspector()
end

function EditorPanel:Compile()
    local compiled, diagnostics = DISPLAY.CompileSource(self.Session.source, self.Session.origin)
    self.Session.compiled = compiled
    self.Session.diagnostics = diagnostics or {}
    if compiled and compiled.buildMode == 'complex' and compiled.pages[self.Session.activePage] then
        compiled.activePage = compiled.pages[self.Session.activePage].id
    end
    local errors = DISPLAY.DiagnosticsText(diagnostics)
    local dirty = self.Session.dirty and ' · UNSAVED' or ''
    local mode = self.Session.readOnly and 'PACKED READ-ONLY' or 'DRAFT EDITABLE'
    self.Status:SetText(mode .. dirty .. ' · ' .. self.Session.origin .. (errors ~= '' and ('\n' .. errors) or '\nValid source'))
    self:UpdateCanvasMetricsLabel()
    if IsValid(self.PreviewCanvas) then self.PreviewCanvas:InvalidateLayout(true) end
    self:RefreshThemes()
    self:RefreshSnapControls()
    return compiled ~= nil
end

function EditorPanel:SaveDraft()
    if not canEdit() then return end
    local directory = draftDirectory()
    file.CreateDir(DISPLAY.DraftRoot)
    file.CreateDir(DISPLAY.DraftRoot .. '/' .. normalizeMap())
    local path = directory .. '/' .. safeFileId(self.Session.source.id) .. '.json'
    file.Write(path, canonicalJSON(self.Session.source) .. '\n')
    self.Session.origin = 'data/' .. path
    self.Session.readOnly = false
    self.Session.dirty = false
    self:Compile()
    self:RefreshSources()
    SetClipboardText(self.Session.origin)
    notification.AddLegacy('Draft saved; exact path copied to clipboard.', NOTIFY_GENERIC, 4)
end

function EditorPanel:PopulatePreviewThemes(picker)
    if not IsValid(picker) then return end
    picker:Clear()
    picker:AddChoice('Runtime theme', false)
    local group = self.Session.compiled and self.Session.compiled.themeGroup
        or self.Session.source.themeGroup or 'default'
    local pack = (DISPLAY.ClientState.ThemePacks or {})[group]
    for themeId in SortedPairs(pack and pack.themes or {}) do picker:AddChoice(themeId, themeId) end
    picker:SetValue(self.Session.themeSimulation or 'Runtime theme')
end

function EditorPanel:OpenPreviewWindow()
    if IsValid(self.PreviewWindow) then self.PreviewWindow:MakePopup() return end
    local frame = vgui.Create('DFrame')
    self.PreviewWindow = frame
    frame:SetTitle('Runtime Preview')
    frame:SetSize(390, 175)
    frame:Center()
    frame:SetSizable(false)
    frame:MakePopup()
    frame.OnRemove = function() if self.PreviewWindow == frame then self.PreviewWindow = nil end end

    local target = frame:Add('DComboBox')
    target:Dock(TOP) target:DockMargin(8, 8, 8, 0)
    target:SetValue(self.Session.previewTarget or 'Runtime display')
    for _, display in ipairs((DISPLAY.ClientState or {}).Displays or {}) do
        target:AddChoice(display.id, display.id)
    end
    target.OnSelect = function(_, _, _, id) self.Session.previewTarget = id end

    local theme = frame:Add('DComboBox')
    theme:Dock(TOP) theme:DockMargin(8, 6, 8, 0)
    self.PreviewThemePicker = theme
    self:PopulatePreviewThemes(theme)
    theme.OnSelect = function(_, _, _, themeId)
        self.Session.themeSimulation = themeId or nil
        self.PreviewCanvas:InvalidateLayout(true)
    end

    local apply = frame:Add('DButton')
    apply:Dock(TOP) apply:DockMargin(8, 10, 8, 0) apply:SetText('Apply to runtime display')
    apply.DoClick = function()
        local _, selected = target:GetSelected()
        self.Session.previewTarget = selected or self.Session.previewTarget
        self:Preview(self.Session.previewTarget)
    end
    local restore = frame:Add('DButton')
    restore:Dock(TOP) restore:DockMargin(8, 5, 8, 0) restore:SetText('Restore packed display')
    restore.DoClick = function()
        local _, selected = target:GetSelected()
        local id = selected or self.Session.previewTarget or DISPLAY.NormalizeId(self.Session.source.id)
        if id then EDITOR.ClearPreview(id) end
    end
end

function EditorPanel:Preview(target)
    if not self:Compile() then
        Derma_Message(DISPLAY.DiagnosticsText(self.Session.diagnostics), 'Preview validation failed', 'OK')
        return
    end
    target = target or DISPLAY.NormalizeId(self.Session.source.id)
    if not target then return end
    local ok, message = sendPreview(self.Session.source, target)
    if not ok then Derma_Message(message, 'Preview failed', 'OK') end
end

function EditorPanel:RebuildHierarchyLegacy()
    self.Hierarchy:Clear()
    local root = self.Hierarchy:AddNode(tostring(self.Session.source.id or 'Display'))
    root.Selection = {kind = 'display'}
    if self.Session.source.buildMode == 'simple' then
        for index, line in ipairs(self.Session.source.lines or {}) do
            local node = root:AddNode(string.format('%02d · %s', index, line.label or line.text or line.type or 'line'))
            node.Selection = {kind = 'line', line = index}
        end
    else
        for pageIndex, page in ipairs(self.Session.source.pages or {}) do
            local pageNode = root:AddNode(page.label or page.id or ('Page ' .. pageIndex))
            pageNode.Selection = {kind = 'page', page = pageIndex}
            for elementIndex, element in ipairs(page.elements or {}) do
                local node = pageNode:AddNode(string.format('z%s · %s · %s', element.z or 0, element.type or '?', element.id or elementIndex))
                node.Selection = {kind = 'element', page = pageIndex, element = elementIndex}
                for lineIndex, line in ipairs(element.lines or {}) do
                    local lineNode = node:AddNode(line.label or line.text or line.type or ('Line ' .. lineIndex))
                    lineNode.Selection = {kind = 'line', page = pageIndex, element = elementIndex, line = lineIndex}
                end
            end
        end
    end
    root:SetExpanded(true)
end

function EditorPanel:CaptureExpandedNodes()
    if not IsValid(self.Hierarchy) then return end
    local expanded = self.Session.expandedNodes or {}
    local function walk(node)
        if node.EditorKey then expanded[node.EditorKey] = node:GetExpanded() end
        for _, child in ipairs(node:GetChildNodes()) do walk(child) end
    end
    for _, node in ipairs(self.Hierarchy:Root():GetChildNodes()) do walk(node) end
    self.Session.expandedNodes = expanded
    local bar = self.Hierarchy:GetVBar()
    if IsValid(bar) then self.Session.hierarchyScroll = bar:GetScroll() end
end

function EditorPanel:RebuildHierarchy()
    if self._skipExpansionCapture then self._skipExpansionCapture = false
    else self:CaptureExpandedNodes() end
    self._rebuildingHierarchy = true
    self.Hierarchy:Clear()
    self.HierarchyNodes = {}
    local function configure(node, selection)
        node.Selection = selection
        node.EditorKey = selectionKey(selection, self.Session.source)
        self.HierarchyNodes[node.EditorKey] = node
        node:SetExpanded(self.Session.expandedNodes[node.EditorKey] == true, true)
        return node
    end
    local root = configure(self.Hierarchy:AddNode(tostring(self.Session.source.id or 'Display')), {kind = 'display'})
    if self.Session.source.buildMode == 'simple' then
        for index, line in ipairs(self.Session.source.lines or {}) do
            configure(root:AddNode(string.format('%02d - %s', index, line.label or line.text or line.type or 'line')),
                {kind = 'line', line = index})
        end
    else
        for pageIndex, page in ipairs(self.Session.source.pages or {}) do
            local pageNode = configure(root:AddNode(page.label or page.id or ('Page ' .. pageIndex)),
                {kind = 'page', page = pageIndex})
            for elementIndex, element in ipairs(page.elements or {}) do
                local node = configure(pageNode:AddNode(string.format('z%s - %s - %s',
                    element.z or 0, element.type or '?', element.id or elementIndex)),
                    {kind = 'element', page = pageIndex, element = elementIndex})
                for lineIndex, line in ipairs(element.lines or {}) do
                    configure(node:AddNode(line.label or line.text or line.type or ('Line ' .. lineIndex)),
                        {kind = 'line', page = pageIndex, element = elementIndex, line = lineIndex})
                end
            end
        end
    end
    root:SetExpanded(true, true)
    self.Session.expandedNodes.display = true
    self._rebuildingHierarchy = false
    self:SyncHierarchySelection()
    local scroll = self.Session.hierarchyScroll
    timer.Simple(0, function()
        if not IsValid(self) or not IsValid(self.Hierarchy) then return end
        local bar = self.Hierarchy:GetVBar()
        if IsValid(bar) then bar:SetScroll(scroll or 0) end
    end)
end

function EditorPanel:SyncHierarchySelection()
    if not IsValid(self.Hierarchy) then return end
    local key = selectionKey(self.Session.selection, self.Session.source)
    local node = self.HierarchyNodes and self.HierarchyNodes[key]
    if not IsValid(node) then return end
    self._rebuildingHierarchy = true
    self.Hierarchy:SetSelectedItem(node)
    local parent = node:GetParentNode()
    while IsValid(parent) and parent ~= self.Hierarchy do
        if parent.EditorKey then
            parent:SetExpanded(true, true)
            self.Session.expandedNodes[parent.EditorKey] = true
        end
        parent = parent.GetParentNode and parent:GetParentNode() or nil
    end
    self._rebuildingHierarchy = false
end

function EditorPanel:SetSelection(selection, switchPage)
    if not selection then return end
    self.Session.selection = DISPLAY.DeepCopy(selection)
    if switchPage and selection.page and self.Session.activePage ~= selection.page then
        self.Session.activePage = selection.page
        self.Session.hitCycle = nil
        self:Compile()
    end
    self:SyncHierarchySelection()
    self:RebuildInspector()
end

local function clearScrollPanel(panel)
    if not IsValid(panel) then return end
    local canvas = panel:GetCanvas()
    if not IsValid(canvas) then return end
    for _, child in ipairs(canvas:GetChildren()) do child:Remove() end
end

function EditorPanel:AddInspectorLabel(text)
    local label = self.Inspector:Add('DLabel')
    label:Dock(TOP)
    label:DockMargin(6, 5, 6, 0)
    label:SetText(text)
    label:SetWrap(true)
    label:SetAutoStretchVertical(true)
    return label
end

function EditorPanel:AddTextField(labelText, object, key)
    self:AddInspectorLabel(labelText)
    local field = self.Inspector:Add('DTextEntry')
    field:Dock(TOP)
    field:DockMargin(6, 2, 6, 0)
    field:SetValue(tostring(object[key] or ''))
    field.OnEnter = function(input)
        local value = input:GetValue()
        self:Changed(function() object[key] = value ~= '' and value or nil end)
    end
end

function EditorPanel:AddNumberField(labelText, object, key, minimum, maximum, decimals, initialValue)
    local slider = self.Inspector:Add('DNumSlider')
    slider:Dock(TOP)
    slider:DockMargin(6, 2, 6, 0)
    slider:SetText(labelText)
    slider:SetMin(minimum)
    slider:SetMax(maximum)
    slider:SetDecimals(decimals or 0)
    slider:SetValue(tonumber(object[key]) or tonumber(initialValue) or minimum)
    slider.OnValueChanged = function(input, value)
        if input._ignore then return end
        if self.Session.readOnly then return end
        if not input._historyOpen then pushHistory(self.Session) end
        input._historyOpen = true
        local changeSerial = (input._changeSerial or 0) + 1
        input._changeSerial = changeSerial
        timer.Simple(0.35, function()
            if IsValid(input) and input._changeSerial == changeSerial then input._historyOpen = false end
        end)
        object[key] = tonumber(value)
        self.Session.dirty = true
        self:Compile()
    end
end

function EditorPanel:UpdateCanvasMetricsLabel()
    if not IsValid(self.CanvasMetricsLabel) then return end
    local compiled = self.Session.compiled
    if not compiled then
        self.CanvasMetricsLabel:SetText('Working canvas unavailable until the source is valid.')
        return
    end
    local explicit = self.Session.source.width ~= nil or self.Session.source.height ~= nil
    local detail = explicit and '\nExplicit pixel width/height override is active in this source.' or ''
    self.CanvasMetricsLabel:SetText(string.format(
        'Working canvas after scale: %d × %d px\nPhysical size: %.3f × %.3f Hammer units · %.4f HU/px%s',
        compiled.width,
        compiled.height,
        compiled.unitWidth,
        compiled.unitHeight,
        compiled.scale,
        detail
    ))
    self.CanvasMetricsLabel:InvalidateLayout(true)
end

function EditorPanel:AddJSONField(labelText, object, key)
    self:AddInspectorLabel(labelText .. ' (JSON)')
    local field = self.Inspector:Add('DTextEntry')
    field:Dock(TOP)
    field:DockMargin(6, 2, 6, 0)
    field:SetMultiline(true)
    field:SetTall(80)
    field:SetValue(canonicalJSON(object[key] ~= nil and object[key] or {}))
    local apply = self.Inspector:Add('DButton')
    apply:Dock(TOP)
    apply:DockMargin(6, 2, 6, 4)
    apply:SetText('Apply ' .. labelText)
    apply.DoClick = function()
        local wrapper = util.JSONToTable('{"value":' .. field:GetValue() .. '}')
        if type(wrapper) ~= 'table' or wrapper.value == nil then
            notification.AddLegacy('Invalid JSON value', NOTIFY_ERROR, 3)
            return
        end
        self:Changed(function() object[key] = wrapper.value end)
    end
end

function EditorPanel:AddBoolField(labelText, object, key, defaultValue)
    local box = self.Inspector:Add('DCheckBoxLabel')
    box:Dock(TOP) box:DockMargin(6, 5, 6, 0)
    box:SetText(labelText)
    box:SetValue(object[key] == nil and (defaultValue and 1 or 0) or (object[key] and 1 or 0))
    box:SizeToContents()
    box.OnChange = function(_, checked)
        self:Changed(function() object[key] = checked and true or false end)
    end
    return box
end

function EditorPanel:AddChoiceField(labelText, object, key, choices, fallback)
    self:AddInspectorLabel(labelText)
    local combo = self.Inspector:Add('DComboBox')
    combo:Dock(TOP) combo:DockMargin(6, 2, 6, 0)
    combo:SetValue(tostring(object[key] or fallback or ''))
    for _, choice in ipairs(choices or {}) do
        if type(choice) == 'table' then combo:AddChoice(choice.label or choice[1], choice.value or choice[2])
        else combo:AddChoice(tostring(choice), choice) end
    end
    combo.OnSelect = function(_, _, _, value)
        self:Changed(function() object[key] = value end)
    end
    return combo
end

local function colorArray(value)
    local color = DISPLAY.ColorTable(value, {r = 255, g = 255, b = 255, a = 255})
    return {color.r or 255, color.g or 255, color.b or 255, color.a or 255}
end

function EditorPanel:ThemeTokens()
    local group = self.Session.source.themeGroup or 'default'
    local pack = self.Session.themeOverride
        or (DISPLAY.ClientState.ThemePacks or {})[group]
    local themeId = self.Session.themeSimulation or (pack and pack.defaultTheme)
    local theme = pack and pack.themes and pack.themes[themeId]
    local tokens = theme and (theme.tokens or theme) or {}
    local out = {}
    for token in pairs(tokens) do table.insert(out, token) end
    table.sort(out)
    return out
end

function EditorPanel:OpenColorPicker(object, key)
    local frame = vgui.Create('DFrame')
    frame:SetTitle('Choose custom color') frame:SetSize(330, 390) frame:Center() frame:MakePopup()
    local mixer = frame:Add('DColorMixer')
    mixer:Dock(FILL) mixer:DockMargin(8, 8, 8, 4)
    mixer:SetPalette(true) mixer:SetAlphaBar(true) mixer:SetWangs(true)
    local value = colorArray(object[key])
    mixer:SetColor(Color(value[1], value[2], value[3], value[4]))
    local apply = frame:Add('DButton')
    apply:Dock(BOTTOM) apply:DockMargin(8, 4, 8, 8) apply:SetTall(28) apply:SetText('Apply RGBA')
    apply.DoClick = function()
        local color = mixer:GetColor()
        self:Changed(function() object[key] = {color.r, color.g, color.b, color.a} end)
        frame:Close()
    end
end

function EditorPanel:AddColorField(labelText, object, key, allowInherit)
    self:AddInspectorLabel(labelText)
    local row = self.Inspector:Add('DPanel')
    row:Dock(TOP) row:DockMargin(6, 2, 6, 0) row:SetTall(25)
    local mode = row:Add('DComboBox')
    mode:Dock(LEFT) mode:SetWide(95)
    if allowInherit then mode:AddChoice('Inherit', 'inherit') end
    mode:AddChoice('Theme token', 'theme') mode:AddChoice('Custom RGBA', 'custom')
    local current = object[key]
    mode:SetValue(current == nil and 'Inherit' or (type(current) == 'string' and 'Theme token' or 'Custom RGBA'))
    local choose = row:Add('DButton')
    choose:Dock(FILL) choose:DockMargin(4, 0, 0, 0)
    choose:SetText(type(current) == 'string' and current or (current and table.concat(colorArray(current), ', ') or 'Choose...'))
    local function openFor(selectedMode)
        if selectedMode == 'inherit' then self:Changed(function() object[key] = nil end) return end
        if selectedMode == 'custom' then self:OpenColorPicker(object, key) return end
        local menu = DermaMenu()
        for _, token in ipairs(self:ThemeTokens()) do
            menu:AddOption('@' .. token, function() self:Changed(function() object[key] = '@' .. token end) end)
        end
        if #self:ThemeTokens() == 0 then menu:AddOption('No theme tokens available', function() end) end
        menu:Open()
    end
    mode.OnSelect = function(_, _, _, value) openFor(value) end
    choose.DoClick = function()
        if type(object[key]) == 'string' then openFor('theme') else openFor('custom') end
    end
end

local function normalizeMaterialEditorPath(path)
    path = string.Trim(string.lower(string.gsub(tostring(path or ''), '\\', '/')))
    path = string.gsub(path, '^materials/', '')
    path = string.gsub(path, '%.vmt$', '')
    if path == '' or string.find(path, '..', 1, true) or string.find(path, '://', 1, true)
        or string.sub(path, 1, 1) == '/' or string.find(path, '[^%w_/%.-]') then return nil end
    return path
end

EDITOR.MaterialSearchIndex = EDITOR.MaterialSearchIndex or {
    paths = {},
    pathSet = {},
    directories = {},
    directoryHead = 1,
    directorySet = {},
    building = false,
    built = false,
    revision = 0
}

local function startMaterialSearchIndex()
    local index = EDITOR.MaterialSearchIndex
    if index.built or index.building then return index end
    index.paths = {}
    index.pathSet = {}
    index.directories = {'materials'}
    index.directoryHead = 1
    index.directorySet = {materials = true}
    index.building = true
    index.built = false
    index.revision = index.revision + 1
    timer.Create('LUASQUARE_3D2D_MaterialSearchIndex', 0, 0, function()
        local changed = false
        for _ = 1, 12 do
            local directory = index.directories[index.directoryHead]
            index.directoryHead = index.directoryHead + 1
            if not directory then
                index.building = false
                index.built = true
                table.sort(index.paths)
                index.directories = {}
                index.directorySet = {}
                index.directoryHead = 1
                index.revision = index.revision + 1
                timer.Remove('LUASQUARE_3D2D_MaterialSearchIndex')
                return
            end
            local files, directories = file.Find(directory .. '/*', 'GAME')
            for _, name in ipairs(files or {}) do
                if string.lower(string.GetExtensionFromFilename(name) or '') == 'vmt' then
                    local path = normalizeMaterialEditorPath(directory .. '/' .. name)
                    if path and not index.pathSet[path] then
                        index.pathSet[path] = true
                        table.insert(index.paths, path)
                        changed = true
                    end
                end
            end
            for _, name in ipairs(directories or {}) do
                local child = directory .. '/' .. name
                if not index.directorySet[child] then
                    index.directorySet[child] = true
                    table.insert(index.directories, child)
                end
            end
        end
        if changed then index.revision = index.revision + 1 end
    end)
    return index
end

function EditorPanel:OpenMaterialPicker(callback, initial)
    local frame = vgui.Create('DFrame')
    frame:SetTitle('Material browser') frame:SetSize(820, 600) frame:Center() frame:MakePopup()
    local search = frame:Add('DTextEntry')
    search:Dock(TOP) search:DockMargin(8, 8, 8, 4)
    search:SetPlaceholderText('Search every mounted material path')

    local apply = frame:Add('DButton')
    apply:Dock(BOTTOM) apply:DockMargin(8, 4, 8, 8) apply:SetTall(28) apply:SetText('Use material path')
    local pathEntry = frame:Add('DTextEntry')
    pathEntry:Dock(BOTTOM) pathEntry:DockMargin(8, 4, 8, 0) pathEntry:SetTall(24)
    pathEntry:SetPlaceholderText('Material path (materials/ and .vmt are optional)')
    local searchStatus = frame:Add('DLabel')
    searchStatus:Dock(BOTTOM) searchStatus:DockMargin(8, 2, 8, 0) searchStatus:SetTall(18)

    local previewContainer = frame:Add('DPanel')
    previewContainer:Dock(RIGHT) previewContainer:DockMargin(4, 4, 8, 4) previewContainer:SetWide(240)
    local previewStatus = previewContainer:Add('DLabel')
    previewStatus:Dock(BOTTOM) previewStatus:SetTall(38) previewStatus:SetWrap(true)
    previewStatus:SetContentAlignment(5) previewStatus:SetText('No material selected')
    local preview = previewContainer:Add('DPanel')
    preview:Dock(FILL)

    local content = frame:Add('DPanel')
    content:Dock(FILL) content:DockMargin(8, 4, 4, 4)
    local browser = content:Add('DFileBrowser')
    browser:Dock(FILL)
    browser:SetPath('GAME') browser:SetBaseFolder('materials') browser:SetFileTypes('*.vmt') browser:SetOpen(true)
    local results = content:Add('DListView')
    results:Dock(FILL) results:SetMultiSelect(false) results:SetVisible(false)
    results:AddColumn('Material search results')

    local selected = normalizeMaterialEditorPath(initial)
    local previewMaterial
    local previewWidth, previewHeight = 0, 0
    preview.Paint = function(_, width, height)
        surface.SetDrawColor(18, 20, 23, 255)
        surface.DrawRect(0, 0, width, height)
        if not previewMaterial or previewMaterial:IsError() then return end
        local margin = 8
        local availableWidth = math.max(width - margin * 2, 1)
        local availableHeight = math.max(height - margin * 2, 1)
        local ratio = math.min(availableWidth / math.max(previewWidth, 1), availableHeight / math.max(previewHeight, 1))
        local drawWidth = math.max(math.floor(previewWidth * ratio), 1)
        local drawHeight = math.max(math.floor(previewHeight * ratio), 1)
        local x = math.floor((width - drawWidth) * 0.5)
        local y = math.floor((height - drawHeight) * 0.5)
        surface.SetMaterial(previewMaterial)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(x, y, drawWidth, drawHeight)
    end
    local function selectPath(path, synchronizeEntry)
        local normalized = normalizeMaterialEditorPath(path)
        selected = normalized
        if not normalized then
            previewMaterial = nil
            previewStatus:SetText('Invalid material path')
            preview:InvalidateLayout(true)
            return false
        end
        if synchronizeEntry ~= false then
            pathEntry._synchronizing = true
            pathEntry:SetValue(normalized)
            pathEntry._synchronizing = false
        end
        previewMaterial = Material(normalized, 'smooth')
        local texture = not previewMaterial:IsError() and previewMaterial:GetTexture('$basetexture') or nil
        previewWidth = texture and texture:Width() or 32
        previewHeight = texture and texture:Height() or 32
        previewStatus:SetText(previewMaterial:IsError()
            and ('Material not available\n' .. normalized)
            or string.format('%d x %d\n%s', previewWidth, previewHeight, normalized))
        preview:InvalidateLayout(true)
        return true
    end
    browser.OnSelect = function(_, path) selectPath(path) end
    browser.OnDoubleClick = function(_, path)
        selectPath(path)
        if selected then callback(selected) frame:Close() end
    end

    results.OnRowSelected = function(_, _, line) selectPath(line.MaterialPath) end
    results.DoDoubleClick = function(_, _, line)
        if selectPath(line.MaterialPath) then callback(selected) frame:Close() end
    end

    local index = startMaterialSearchIndex()
    local function refreshSearch()
        local query = string.lower(string.Trim(search:GetValue()))
        local searching = query ~= ''
        browser:SetVisible(not searching)
        results:SetVisible(searching)
        if not searching then
            searchStatus:SetText(index.building and 'Building global material index in the background...' or 'Browsing materials/')
            return
        end
        local matches = {}
        local total = 0
        for _, path in ipairs(index.paths) do
            if string.find(path, query, 1, true) then
                total = total + 1
                if #matches < 750 then table.insert(matches, path) end
            end
        end
        table.sort(matches)
        results:Clear()
        for _, path in ipairs(matches) do
            local line = results:AddLine(path)
            line.MaterialPath = path
        end
        local suffix = index.building and ' (indexing...)' or ''
        searchStatus:SetText(string.format('%d match(es); showing %d%s', total, #matches, suffix))
    end
    search.OnValueChange = function() refreshSearch() end
    frame.Think = function()
        if frame._materialIndexRevision == index.revision then return end
        if RealTime() < (frame._nextMaterialSearchRefresh or 0) then return end
        frame._nextMaterialSearchRefresh = RealTime() + 0.2
        frame._materialIndexRevision = index.revision
        if search:GetValue() ~= '' then refreshSearch()
        elseif index.built then searchStatus:SetText('Browsing materials/ - global index ready') end
    end

    pathEntry.OnValueChange = function(input)
        if input._synchronizing then return end
        input._changeSerial = (input._changeSerial or 0) + 1
        local serial = input._changeSerial
        timer.Simple(0.15, function()
            if not IsValid(input) or input._changeSerial ~= serial then return end
            selectPath(input:GetValue(), false)
        end)
    end
    pathEntry.OnEnter = function(input) selectPath(input:GetValue(), true) end
    apply.DoClick = function()
        if selectPath(pathEntry:GetValue(), true) then callback(selected) frame:Close()
        else notification.AddLegacy('Select a safe VMT path first.', NOTIFY_ERROR, 3) end
    end
    if selected then selectPath(selected, true) end
    refreshSearch()
end

function EditorPanel:AddMaterialField(labelText, object, key)
    self:AddInspectorLabel(labelText)
    local row = self.Inspector:Add('DPanel')
    row:Dock(TOP) row:DockMargin(6, 2, 6, 0) row:SetTall(24)
    local entry = row:Add('DTextEntry')
    entry:Dock(FILL) entry:SetValue(tostring(object[key] or ''))
    entry.OnEnter = function(input)
        local path = normalizeMaterialEditorPath(input:GetValue())
        if path then self:Changed(function() object[key] = path end)
        else notification.AddLegacy('Unsafe material path.', NOTIFY_ERROR, 3) end
    end
    local browse = row:Add('DButton')
    browse:Dock(RIGHT) browse:DockMargin(4, 0, 0, 0) browse:SetWide(70) browse:SetText('Browse')
    browse.DoClick = function()
        self:OpenMaterialPicker(function(path) self:Changed(function() object[key] = path end) end, object[key])
    end
end

function EditorPanel:AddBindingField(labelText, object, key)
    self:AddInspectorLabel(labelText)
    local binding = type(object[key]) == 'table' and object[key] or {}
    local provider = self.Inspector:Add('DComboBox')
    provider:Dock(TOP) provider:DockMargin(6, 2, 6, 0)
    provider:SetValue(binding.provider or 'Provider')
    for id in SortedPairs(DISPLAY.KnownProviders or {}) do provider:AddChoice(id, id) end
    provider.OnSelect = function(_, _, _, id)
        self:Changed(function()
            object[key] = type(object[key]) == 'table' and object[key] or {}
            object[key].provider = id
        end)
    end
    local path = self.Inspector:Add('DTextEntry')
    path:Dock(TOP) path:DockMargin(6, 2, 6, 0) path:SetPlaceholderText('Provider path')
    path:SetValue(tostring(binding.path or ''))
    path.OnEnter = function(input)
        self:Changed(function()
            object[key] = type(object[key]) == 'table' and object[key] or {}
            object[key].path = input:GetValue() ~= '' and input:GetValue() or nil
        end)
    end
end

function EditorPanel:AddActionFields(object)
    self:AddInspectorLabel('Named action')
    local action = self.Inspector:Add('DComboBox')
    action:Dock(TOP) action:DockMargin(6, 2, 6, 0)
    action:AddChoice('No action', false)
    for id in SortedPairs(DISPLAY.KnownActions or {}) do action:AddChoice(id, id) end
    action:SetValue(object.action or 'No action')
    action.OnSelect = function(_, _, _, id)
        self:Changed(function() object.action = id or nil end)
    end

    self:AddInspectorLabel('Action payload (scalar fields)')
    for key, value in SortedPairs(type(object.actionPayload) == 'table' and object.actionPayload or {}) do
        if type(value) ~= 'table' then
            local row = self.Inspector:Add('DPanel')
            row:Dock(TOP) row:DockMargin(6, 2, 6, 0) row:SetTall(24)
            local label = row:Add('DLabel') label:Dock(LEFT) label:SetWide(90) label:SetText(tostring(key))
            local entry = row:Add('DTextEntry') entry:Dock(FILL) entry:SetValue(tostring(value))
            entry.OnEnter = function(input)
                local raw = input:GetValue()
                local parsed = tonumber(raw)
                if raw == 'true' then parsed = true elseif raw == 'false' then parsed = false elseif parsed == nil then parsed = raw end
                self:Changed(function() object.actionPayload[key] = parsed end)
            end
            local remove = row:Add('DButton') remove:Dock(RIGHT) remove:SetWide(25) remove:SetText('X')
            remove.DoClick = function() self:Changed(function() object.actionPayload[key] = nil end) end
        end
    end
    local add = self.Inspector:Add('DButton')
    add:Dock(TOP) add:DockMargin(6, 3, 6, 0) add:SetText('Add payload field')
    add.DoClick = function()
        Derma_StringRequest('Payload field', 'Enter a new scalar field name.', '', function(key)
            key = string.Trim(key or '')
            if key == '' then return end
            self:Changed(function()
                object.actionPayload = type(object.actionPayload) == 'table' and object.actionPayload or {}
                object.actionPayload[key] = ''
            end)
        end)
    end
    self:AddJSONField('Advanced action payload', object, 'actionPayload')
end

function EditorPanel:AddFrameEditor(object)
    self:AddInspectorLabel('Material frames')
    for index, path in ipairs(object.frames or {}) do
        local row = self.Inspector:Add('DPanel')
        row:Dock(TOP) row:DockMargin(6, 2, 6, 0) row:SetTall(24)
        local browse = row:Add('DButton') browse:Dock(FILL) browse:SetText(index .. ': ' .. tostring(path))
        browse.DoClick = function()
            self:OpenMaterialPicker(function(selected)
                self:Changed(function() object.frames[index] = selected end)
            end, path)
        end
        local up = row:Add('DButton') up:Dock(RIGHT) up:SetWide(24) up:SetText('^')
        up:SetEnabled(index > 1)
        up.DoClick = function()
            self:Changed(function() object.frames[index], object.frames[index - 1] = object.frames[index - 1], object.frames[index] end)
        end
        local down = row:Add('DButton') down:Dock(RIGHT) down:SetWide(24) down:SetText('v')
        down:SetEnabled(index < #(object.frames or {}))
        down.DoClick = function()
            self:Changed(function() object.frames[index], object.frames[index + 1] = object.frames[index + 1], object.frames[index] end)
        end
        local remove = row:Add('DButton') remove:Dock(RIGHT) remove:SetWide(24) remove:SetText('X')
        remove.DoClick = function() self:Changed(function() table.remove(object.frames, index) end) end
    end
    local add = self.Inspector:Add('DButton')
    add:Dock(TOP) add:DockMargin(6, 3, 6, 0) add:SetText('Add material frame')
    add.DoClick = function()
        self:OpenMaterialPicker(function(path)
            self:Changed(function()
                object.frames = object.frames or {}
                table.insert(object.frames, path)
            end)
        end)
    end
end

function EditorPanel:AddVariantEditor(object)
    self:AddInspectorLabel('Condition variants')
    for index, variant in ipairs(object.variants or {}) do
        local row = self.Inspector:Add('DPanel')
        row:Dock(TOP) row:DockMargin(6, 2, 6, 0) row:SetTall(24)
        local when = variant.when or {}
        local summary = string.format('%d: %s.%s %s', index, when.provider or '?', when.path or '', when.op or 'truthy')
        local edit = row:Add('DButton') edit:Dock(FILL) edit:SetText(summary)
        edit.DoClick = function() self:OpenVariantWindow(object, index) end
        local up = row:Add('DButton') up:Dock(RIGHT) up:SetWide(24) up:SetText('^') up:SetEnabled(index > 1)
        up.DoClick = function() self:Changed(function() object.variants[index], object.variants[index - 1] = object.variants[index - 1], object.variants[index] end) end
        local down = row:Add('DButton') down:Dock(RIGHT) down:SetWide(24) down:SetText('v') down:SetEnabled(index < #(object.variants or {}))
        down.DoClick = function() self:Changed(function() object.variants[index], object.variants[index + 1] = object.variants[index + 1], object.variants[index] end) end
        local remove = row:Add('DButton') remove:Dock(RIGHT) remove:SetWide(24) remove:SetText('X')
        remove.DoClick = function() self:Changed(function() table.remove(object.variants, index) end) end
    end
    local add = self.Inspector:Add('DButton')
    add:Dock(TOP) add:DockMargin(6, 3, 6, 0) add:SetText('Add basic variant')
    add.DoClick = function()
        self:Changed(function()
            object.variants = object.variants or {}
            table.insert(object.variants, {when = {provider = '', op = 'truthy'}, set = {visible = true}})
        end)
    end
    self:AddJSONField('Advanced variants', object, 'variants')
end

function EditorPanel:OpenVariantWindow(object, index)
    local variant = object.variants and object.variants[index]
    if not variant then return end
    local frame = vgui.Create('DFrame')
    frame:SetTitle('Edit basic variant') frame:SetSize(420, 330) frame:Center() frame:MakePopup()
    local form = frame:Add('DForm') form:Dock(FILL) form:DockMargin(8, 8, 8, 8) form:SetName('First-match variant')
    local provider = form:ComboBox('Provider')
    provider:SetValue(variant.when and variant.when.provider or '')
    for id in SortedPairs(DISPLAY.KnownProviders or {}) do provider:AddChoice(id, id) end
    local path = form:TextEntry('Path') path:SetValue(variant.when and variant.when.path or '')
    local operation = form:ComboBox('Operator')
    for _, op in ipairs({'truthy', 'eq', 'ne', 'gt', 'gte', 'lt', 'lte'}) do operation:AddChoice(op, op) end
    operation:SetValue(variant.when and variant.when.op or 'truthy')
    local comparison = form:TextEntry('Comparison value')
    comparison:SetValue(tostring(variant.when and variant.when.value or ''))
    local visible = form:CheckBox('Override visibility') visible:SetChecked(variant.set and variant.set.visible ~= nil)
    local visibleValue = form:CheckBox('Visible') visibleValue:SetChecked(not variant.set or variant.set.visible ~= false)
    local material = form:TextEntry('Material override') material:SetValue(tostring(variant.set and variant.set.material or ''))
    local pendingColor = DISPLAY.DeepCopy(variant.set and variant.set.color)
    local pendingTint = DISPLAY.DeepCopy(variant.set and variant.set.tint)
    local function addVariantColor(labelText, current, assign)
        local combo = form:ComboBox(labelText)
        combo:AddChoice('No override', false)
        for _, token in ipairs(self:ThemeTokens()) do combo:AddChoice('@' .. token, '@' .. token) end
        combo:AddChoice('Custom RGBA...', '__custom')
        combo:SetValue(type(current) == 'string' and current or (current and 'Custom RGBA' or 'No override'))
        combo.OnSelect = function(_, _, _, selectedValue)
            if selectedValue ~= '__custom' then assign(selectedValue or nil) return end
            local picker = vgui.Create('DFrame')
            picker:SetTitle(labelText) picker:SetSize(320, 390) picker:Center() picker:MakePopup()
            local mixer = picker:Add('DColorMixer') mixer:Dock(FILL) mixer:DockMargin(8, 8, 8, 4)
            mixer:SetPalette(true) mixer:SetAlphaBar(true) mixer:SetWangs(true)
            local rgba = colorArray(current) mixer:SetColor(Color(rgba[1], rgba[2], rgba[3], rgba[4]))
            local accept = picker:Add('DButton') accept:Dock(BOTTOM) accept:DockMargin(8, 4, 8, 8)
            accept:SetTall(28) accept:SetText('Use RGBA')
            accept.DoClick = function()
                local color = mixer:GetColor()
                assign({color.r, color.g, color.b, color.a})
                combo:SetValue('Custom RGBA')
                picker:Close()
            end
        end
    end
    addVariantColor('Color override', pendingColor, function(selectedColor) pendingColor = selectedColor end)
    addVariantColor('Tint override', pendingTint, function(selectedTint) pendingTint = selectedTint end)
    local flash = form:NumSlider('Flash seconds', nil, 0, 60, 2)
    flash:SetValue(tonumber(variant.set and variant.set.flashSeconds) or 0)
    local apply = form:Button('Apply variant')
    apply.DoClick = function()
        local _, providerId = provider:GetSelected()
        local _, op = operation:GetSelected()
        local raw = comparison:GetValue()
        local compare = tonumber(raw)
        if raw == 'true' then compare = true elseif raw == 'false' then compare = false elseif compare == nil then compare = raw end
        self:Changed(function()
            variant.when = {provider = providerId or provider:GetValue(), path = path:GetValue() ~= '' and path:GetValue() or nil, op = op or operation:GetValue()}
            if variant.when.op ~= 'truthy' then variant.when.value = compare end
            variant.set = variant.set or {}
            variant.set.visible = visible:GetChecked() and visibleValue:GetChecked() or nil
            variant.set.material = normalizeMaterialEditorPath(material:GetValue())
            variant.set.color = DISPLAY.DeepCopy(pendingColor)
            variant.set.tint = DISPLAY.DeepCopy(pendingTint)
            variant.set.flashSeconds = flash:GetValue() > 0 and flash:GetValue() or nil
        end)
        frame:Close()
    end
end

function EditorPanel:AddFeatureMenu(object, kind)
    local menu = DermaMenu()
    local function feature(label, key, value)
        if object[key] ~= nil then return end
        menu:AddOption(label, function()
            self:Changed(function() object[key] = DISPLAY.DeepCopy(value) end)
        end)
    end
    feature('Text color', 'textColor', '@text')
    feature('Background color', 'backgroundColor', '@panel')
    feature('Border color', 'borderColor', '@border')
    feature('Flash animation', 'flashSeconds', 0.25)
    feature('Condition variants', 'variants', {})
    if kind == 'element' then
        feature('Named action', 'action', '')
        feature('Action payload', 'actionPayload', {})
    end
    if normalizedElementType(object.type) == 'line_panel' then
        feature('Background material', 'backgroundMaterial', 'vgui/white')
    elseif normalizedElementType(object.type) == 'material' then
        feature('Frame animation', 'frames', {})
        feature('Tint', 'tint', {255, 255, 255, 255})
    end
    menu:Open()
end

function EditorPanel:AddFeatureButton(object, kind)
    local button = self.Inspector:Add('DButton')
    button:Dock(TOP) button:DockMargin(6, 7, 6, 0) button:SetText('Add feature...')
    button.DoClick = function() self:AddFeatureMenu(object, kind) end
end

function EditorPanel:RebuildInspector()
    -- DScrollPanel owns its canvas and scrollbar. Removing the scroll panel's
    -- direct children destroys those internals and leaves its layout hook
    -- trying to measure a NULL canvas on the next resize.
    clearScrollPanel(self.Inspector)
    self.CanvasMetricsLabel = nil
    local object = selectionObject(self.Session)
    if not object then self:AddInspectorLabel('Nothing selected.') return end
    local selection = self.Session.selection
    self:AddInspectorLabel(string.upper(selection.kind) .. (self.Session.readOnly and ' · READ ONLY' or ''))
    if selection.kind == 'display' then
        self:AddTextField('Display ID', object, 'id')
        self:AddTextField('Targetname', object, 'target')
        self:AddTextField('Theme group', object, 'themeGroup')
        self:AddColorField('Default text color', object, 'textColor', true)
        self:AddColorField('Title color', object, 'titleColor', true)
        self:AddColorField('Background color', object, 'backgroundColor', true)
        self:AddColorField('Border color', object, 'borderColor', true)
        self:AddColorField('Accent / bar color', object, 'barColor', true)
        local parsed = DISPLAY.ParseTargetMetrics(object.target) or {}
        local compiled = self.Session.compiled or {}
        local unitWidth = object.unitWidth or object.hammerWidth or parsed.unitWidth or compiled.unitWidth
        local unitHeight = object.unitHeight or object.hammerHeight or parsed.unitHeight or compiled.unitHeight
        self:AddNumberField('Canvas width (Hammer units)', object, 'unitWidth', 0.01, 100000, 2, unitWidth)
        self:AddNumberField('Canvas height (Hammer units)', object, 'unitHeight', 0.01, 100000, 2, unitHeight)
        self:AddNumberField('Scale (HU per canvas pixel)', object, 'scale', 0.001, 10, 3, compiled.scale)
        self.CanvasMetricsLabel = self:AddInspectorLabel('')
        self:UpdateCanvasMetricsLabel()
        if object.width ~= nil or object.height ~= nil then
            local clearPixelSize = self.Inspector:Add('DButton')
            clearPixelSize:Dock(TOP)
            clearPixelSize:DockMargin(6, 3, 6, 3)
            clearPixelSize:SetText('Remove explicit pixel-size override')
            clearPixelSize.DoClick = function()
                self:Changed(function()
                    object.width = nil
                    object.height = nil
                end)
            end
        end
        self:AddBoolField('Show page switching tabs', object, 'showPageTabs', true)
        object.interaction = type(object.interaction) == 'table' and object.interaction or {}
        self:AddInspectorLabel('INTERACTION')
        self:AddBoolField('Enable raycast interaction', object.interaction, 'enabled', false)
        self:AddNumberField('Maximum distance', object.interaction, 'distance', 16, 4096, 0, 128)
        self:AddNumberField('Field of view', object.interaction, 'fov', 1, 180, 1, 30)
        self:AddBoolField('Require line of sight', object.interaction, 'lineOfSight', true)
        self:AddJSONField('Advanced interaction', object, 'interaction')
        local mode = self.Inspector:Add('DComboBox')
        mode:Dock(TOP) mode:DockMargin(6, 7, 6, 0) mode:SetValue(object.buildMode or 'simple')
        mode:AddChoice('simple', 'simple') mode:AddChoice('complex', 'complex')
        mode.OnSelect = function(_, _, _, value)
            self:Changed(function()
                object.buildMode = value
                if value == 'simple' then object.lines = object.lines or {}
                else object.pages = object.pages or {{id = 'overview', label = 'Overview', elements = {}}} end
            end)
        end
        local addPage = self.Inspector:Add('DButton')
        addPage:Dock(TOP) addPage:DockMargin(6, 4, 6, 0) addPage:SetText('Add complex page')
        addPage.DoClick = function()
            self:Changed(function()
                object.buildMode = 'complex'
                object.pages = object.pages or {}
                table.insert(object.pages, {id = 'page_' .. (#object.pages + 1), label = 'Page ' .. (#object.pages + 1), elements = {}})
                self.Session.activePage = #object.pages
                self.Session.selection = {kind = 'page', page = #object.pages}
            end)
        end
    elseif selection.kind == 'page' then
        self:AddTextField('Page ID', object, 'id')
        self:AddTextField('Tab label', object, 'label')
        local selectButton = self.Inspector:Add('DButton')
        selectButton:Dock(TOP) selectButton:DockMargin(6, 8, 6, 0) selectButton:SetText('Show this page')
        selectButton.DoClick = function() self.Session.activePage = selection.page self:Compile() end
        local add = self.Inspector:Add('DButton')
        add:Dock(TOP) add:DockMargin(6, 4, 6, 0) add:SetText('Add element')
        add.DoClick = function() self:AddElementMenu() end
    elseif selection.kind == 'element' then
        self:AddTextField('Element ID', object, 'id')
        self:AddNumberField('X', object, 'x', -10000, 10000, 0)
        self:AddNumberField('Y', object, 'y', -10000, 10000, 0)
        self:AddNumberField('Width', object, 'width', 1, 32768, 0)
        self:AddNumberField('Height', object, 'height', 1, 32768, 0)
        self:AddNumberField('Layer (z)', object, 'z', -1000, 1000, 0)
        local elementType = normalizedElementType(object.type)
        if elementType == 'material' then
            self:AddMaterialField('Material path', object, 'material')
            self:AddNumberField('Frame seconds', object, 'frameSeconds', 0.02, 60, 2)
            self:AddNumberField('Flash seconds', object, 'flashSeconds', 0.02, 60, 2)
            self:AddBoolField('Loop animation', object, 'loop', true)
            self:AddFrameEditor(object)
            self:AddColorField('Material tint', object, 'tint', true)
        elseif elementType == 'line_panel' then
            self:AddTextField('Panel title', object, 'title')
            self:AddNumberField('Line height', object, 'lineHeight', 1, 4096, 0, self.Session.source.lineHeight or 16)
            self:AddNumberField('Padding', object, 'padding', 0, 4096, 0, 6)
            self:AddBoolField('Draw background', object, 'drawBackground', true)
            self:AddBoolField('Draw border', object, 'drawBorder', true)
            self:AddColorField('Panel background', object, 'backgroundColor', true)
            self:AddColorField('Panel border', object, 'borderColor', true)
            self:AddColorField('Panel title color', object, 'titleColor', true)
            if object.backgroundMaterial ~= nil then self:AddMaterialField('Background material', object, 'backgroundMaterial') end
            local addLine = self.Inspector:Add('DButton')
            addLine:Dock(TOP) addLine:DockMargin(6, 4, 6, 0) addLine:SetText('Add line')
            addLine.DoClick = function()
                self:Changed(function()
                    object.lines = object.lines or {}
                    table.insert(object.lines, {type = 'value', label = 'VALUE', value = 0})
                end)
            end
        elseif elementType == 'solid_rectangle' then
            self:AddColorField('Rectangle color', object, 'color', false)
            self:AddNumberField('Flash seconds', object, 'flashSeconds', 0.02, 60, 2)
        elseif elementType == 'annunciator' then
            self:AddTextField('Alarm ID', object, 'alarm')
            self:AddTextField('Label', object, 'label')
            self:AddColorField('Text color', object, 'textColor', true)
            self:AddColorField('Background color', object, 'backgroundColor', true)
        end
        self:AddActionFields(object)
        self:AddVariantEditor(object)
        self:AddFeatureButton(object, 'element')
    elseif selection.kind == 'line' then
        self:AddChoiceField('Line type', object, 'type', {'text', 'value', 'bar', 'phase', 'graph', 'columns'}, 'text')
        self:AddTextField('Label / text', object, object.type == 'text' and 'text' or 'label')
        self:AddBindingField('Provider value binding', object, 'value')
        if object.type == 'value' or object.type == 'bar' or object.type == 'phase' or object.type == 'graph' then
            self:AddNumberField('Decimals', object, 'decimals', 0, 8, 0, 0)
            self:AddTextField('Unit', object, 'unit')
        end
        if object.type == 'bar' then
            self:AddBindingField('Fraction binding', object, 'fraction')
            self:AddNumberField('Bar height', object, 'height', 1, 4096, 0, 8)
            self:AddColorField('Bar fill', object, 'fillColor', true)
        elseif object.type == 'phase' then
            self:AddNumberField('Minimum', object, 'min', -100000, 100000, 2, -180)
            self:AddNumberField('Maximum', object, 'max', -100000, 100000, 2, 180)
        elseif object.type == 'graph' then
            self:AddNumberField('Graph height', object, 'height', 1, 4096, 0, 90)
            self:AddNumberField('History seconds', object, 'seconds', 0.1, 3600, 1, 60)
            self:AddBoolField('Show X axis', object, 'showXAxis', true)
            self:AddBoolField('Show Y axis', object, 'showYAxis', true)
            self:AddJSONField('Advanced graph series', object, 'series')
        elseif object.type == 'columns' then
            self:AddNumberField('Column height', object, 'height', 1, 4096, 0, 56)
            self:AddNumberField('Column gap', object, 'columnsGap', 0, 4096, 0, 6)
            self:AddJSONField('Advanced columns', object, 'columns')
        end
        self:AddColorField('Line text color', object, 'color', true)
        self:AddVariantEditor(object)
        self:AddFeatureButton(object, 'line')
        local row = self.Inspector:Add('DPanel')
        row:Dock(TOP) row:DockMargin(6, 5, 6, 0) row:SetTall(24)
        for _, direction in ipairs({-1, 1}) do
            local button = row:Add('DButton')
            button:Dock(direction < 0 and LEFT or RIGHT) button:SetWide(80)
            button:SetText(direction < 0 and 'Move up' or 'Move down')
            button.DoClick = function() self:MoveLine(direction) end
        end
    end
    if selection.kind ~= 'display' then
        local remove = self.Inspector:Add('DButton')
        remove:Dock(TOP) remove:DockMargin(6, 10, 6, 6) remove:SetText('Delete selected')
        remove.DoClick = function() self:DeleteSelection() end
    end
end

local function uniqueObjectId(items, preferred, fallback)
    local used = {}
    for _, item in ipairs(items or {}) do
        if item.id then used[tostring(item.id)] = true end
    end
    local base = DISPLAY.NormalizeId(preferred) or fallback
    if not used[base] then return base end
    local serial = 2
    while used[base .. '_' .. serial] do serial = serial + 1 end
    return base .. '_' .. serial
end

function EditorPanel:CopySelection(asJSON)
    local object = selectionObject(self.Session)
    local selection = self.Session.selection
    if not object or not selection or selection.kind == 'display' then return end
    EDITOR.Clipboard = {kind = selection.kind, value = DISPLAY.DeepCopy(object)}
    if asJSON then
        SetClipboardText(canonicalJSON(object))
        notification.AddLegacy('Selection JSON copied to clipboard.', NOTIFY_GENERIC, 3)
    end
end

function EditorPanel:PasteClipboard(targetSelection)
    local clipboard = EDITOR.Clipboard
    if not clipboard then return end
    targetSelection = targetSelection or self.Session.selection or {kind = 'display'}
    self:Changed(function()
        if clipboard.kind == 'element' and self.Session.source.buildMode == 'complex' then
            local pageIndex = targetSelection.page or self.Session.activePage
            local page = self.Session.source.pages and self.Session.source.pages[pageIndex]
            if not page then return end
            page.elements = page.elements or {}
            local copy = DISPLAY.DeepCopy(clipboard.value)
            copy.id = uniqueObjectId(page.elements, tostring(copy.id or 'element') .. '_copy', 'element_copy')
            local offset = math.max(tonumber(self.Session.source.editorGrid) or 0, 8)
            copy.x = (tonumber(copy.x) or 0) + offset
            copy.y = (tonumber(copy.y) or 0) + offset
            table.insert(page.elements, copy)
            self.Session.activePage = pageIndex
            self.Session.selection = {kind = 'element', page = pageIndex, element = #page.elements}
        elseif clipboard.kind == 'line' then
            local lines, pageIndex, elementIndex
            if self.Session.source.buildMode == 'simple' then
                lines = self.Session.source.lines
            elseif targetSelection.kind == 'element' or targetSelection.kind == 'line' then
                pageIndex = targetSelection.page
                elementIndex = targetSelection.element
                local element = self.Session.source.pages[pageIndex].elements[elementIndex]
                if normalizedElementType(element.type) == 'line_panel' then lines = element.lines end
            end
            if not lines then return end
            local copy = DISPLAY.DeepCopy(clipboard.value)
            copy.id = uniqueObjectId(lines, tostring(copy.id or 'line') .. '_copy', 'line_copy')
            table.insert(lines, copy)
            self.Session.selection = {kind = 'line', page = pageIndex, element = elementIndex, line = #lines}
        elseif clipboard.kind == 'page' and self.Session.source.buildMode == 'complex' then
            local pages = self.Session.source.pages or {}
            local copy = DISPLAY.DeepCopy(clipboard.value)
            copy.id = uniqueObjectId(pages, tostring(copy.id or 'page') .. '_copy', 'page_copy')
            copy.label = tostring(copy.label or copy.id) .. ' Copy'
            table.insert(pages, copy)
            self.Session.activePage = #pages
            self.Session.selection = {kind = 'page', page = #pages}
        end
        self.Session.hitCycle = nil
    end)
end

function EditorPanel:DuplicateSelection()
    self:CopySelection(false)
    self:PasteClipboard(self.Session.selection)
end

function EditorPanel:MovePage(direction)
    local selection = self.Session.selection
    if not selection or selection.kind ~= 'page' then return end
    local pages = self.Session.source.pages or {}
    local target = selection.page + direction
    if not pages[target] then return end
    self:Changed(function()
        pages[selection.page], pages[target] = pages[target], pages[selection.page]
        selection.page = target
        self.Session.activePage = target
    end)
end

function EditorPanel:ChangeLayer(operation)
    local selection = self.Session.selection
    local page = selection and selection.page and self.Session.source.pages[selection.page]
    local element = page and page.elements and page.elements[selection.element]
    if not element then return end
    self:Changed(function()
        local minimum, maximum = 0, 0
        for _, sibling in ipairs(page.elements) do
            minimum = math.min(minimum, tonumber(sibling.z) or 0)
            maximum = math.max(maximum, tonumber(sibling.z) or 0)
        end
        if operation == 'front' then element.z = maximum + 1
        elseif operation == 'back' then element.z = minimum - 1
        elseif operation == 'forward' then element.z = (tonumber(element.z) or 0) + 1
        else element.z = (tonumber(element.z) or 0) - 1 end
        self.Session.hitCycle = nil
    end)
end

function EditorPanel:OpenSelectionMenu(selection)
    if not selection or selection.kind == 'display' then return end
    local menu = DermaMenu()
    if selection.kind == 'page' then
        menu:AddOption('Show page', function() self:SetSelection(selection, true) end)
        menu:AddOption('Add element', function() self:SetSelection(selection, true) self:AddElementMenu() end)
        if EDITOR.Clipboard and EDITOR.Clipboard.kind == 'element' then
            menu:AddOption('Paste element', function() self:PasteClipboard(selection) end)
        end
        menu:AddOption('Copy page', function() self:CopySelection(false) end)
        menu:AddOption('Duplicate page', function() self:DuplicateSelection() end)
        menu:AddOption('Move page left', function() self:MovePage(-1) end)
        menu:AddOption('Move page right', function() self:MovePage(1) end)
    elseif selection.kind == 'element' then
        menu:AddOption('Copy element', function() self:CopySelection(false) end)
        if EDITOR.Clipboard and EDITOR.Clipboard.kind == 'element' then
            menu:AddOption('Paste element', function() self:PasteClipboard(selection) end)
        end
        menu:AddOption('Duplicate element', function() self:DuplicateSelection() end)
        menu:AddOption('Copy as JSON', function() self:CopySelection(true) end)
        local layer = menu:AddSubMenu('Layer')
        layer:AddOption('Bring forward', function() self:ChangeLayer('forward') end)
        layer:AddOption('Send backward', function() self:ChangeLayer('backward') end)
        layer:AddOption('Bring to front', function() self:ChangeLayer('front') end)
        layer:AddOption('Send to back', function() self:ChangeLayer('back') end)
    elseif selection.kind == 'line' then
        menu:AddOption('Copy line', function() self:CopySelection(false) end)
        if EDITOR.Clipboard and EDITOR.Clipboard.kind == 'line' then
            menu:AddOption('Paste line', function() self:PasteClipboard(selection) end)
        end
        menu:AddOption('Duplicate line', function() self:DuplicateSelection() end)
        menu:AddOption('Copy as JSON', function() self:CopySelection(true) end)
        menu:AddOption('Move up', function() self:MoveLine(-1) end)
        menu:AddOption('Move down', function() self:MoveLine(1) end)
    end
    menu:AddSpacer()
    menu:AddOption('Delete', function() self:DeleteSelection() end):SetIcon('icon16/delete.png')
    menu:Open()
end

function EditorPanel:DeleteSelection()
    local selection = self.Session.selection
    if not selection or selection.kind == 'display' then return end
    if selection.kind == 'page' and #(self.Session.source.pages or {}) <= 1 then
        notification.AddLegacy('A complex display must retain one page.', NOTIFY_ERROR, 3)
        return
    end
    self:Changed(function()
        if selection.kind == 'page' then
            table.remove(self.Session.source.pages, selection.page)
            self.Session.activePage = math.Clamp(self.Session.activePage, 1, math.max(#self.Session.source.pages, 1))
        elseif selection.kind == 'element' then
            table.remove(self.Session.source.pages[selection.page].elements, selection.element)
        elseif selection.kind == 'line' then
            if self.Session.source.buildMode == 'simple' then
                table.remove(self.Session.source.lines, selection.line)
            else
                local element = self.Session.source.pages[selection.page].elements[selection.element]
                table.remove(element.lines, selection.line)
            end
        end
        self.Session.selection = {kind = 'display'}
    end)
end

function EditorPanel:AddElementMenu(x, y)
    local menu = DermaMenu()
    local page = activePageSource(self.Session)
    if not page then return end
    local types = {
        {'Line panel', {type = 'line_panel', width = 220, height = 140, title = 'Panel', lines = {}}},
        {'Material', {type = 'material', width = 128, height = 128, material = 'vgui/white'}},
        {'Solid rectangle', {type = 'solid_rectangle', width = 128, height = 64, color = {40, 80, 90, 220}}},
        {'Annunciator', {type = 'annunciator', width = 160, height = 36, alarm = 'alarm_id', label = 'ALARM'}}
    }
    for _, item in ipairs(types) do
        menu:AddOption(item[1], function()
            self:Changed(function()
                page.elements = page.elements or {}
                local element = DISPLAY.DeepCopy(item[2])
                element.id = uniqueObjectId(page.elements, 'element_' .. (#page.elements + 1), 'element')
                element.x = math.floor(x or 16) element.y = math.floor(y or 32) element.z = #page.elements
                table.insert(page.elements, element)
                self.Session.selection = {kind = 'element', page = self.Session.activePage, element = #page.elements}
            end)
        end)
    end
    menu:Open()
end

function EditorPanel:MoveLine(direction)
    local selection = self.Session.selection
    if not selection or selection.kind ~= 'line' then return end
    local lines
    if self.Session.source.buildMode == 'simple' then lines = self.Session.source.lines
    else
        local page = self.Session.source.pages[selection.page]
        local element = page and page.elements[selection.element]
        lines = element and element.lines
    end
    local target = selection.line + direction
    if not lines or not lines[target] then return end
    self:Changed(function()
        lines[selection.line], lines[target] = lines[target], lines[selection.line]
        selection.line = target
    end)
end

function EditorPanel:CanvasTransform(panel)
    local compiled = self.Session.compiled
    if not compiled then return 1, 0, 0 end
    local scale = math.min(panel:GetWide() / compiled.width, panel:GetTall() / compiled.height)
    scale = math.max(scale, 0.05)
    return scale, 0, 0
end

function EditorPanel:PaintCanvas(panel, width, height)
    surface.SetDrawColor(22, 24, 27, 255) surface.DrawRect(0, 0, width, height)
    local compiled = self.Session.compiled
    if not compiled then draw.SimpleText('Source has validation errors', 'DermaDefaultBold', width / 2, height / 2, Color(255, 100, 100), 1, 1) return end
    local scale, offsetX, offsetY = self:CanvasTransform(panel)
    local screenX, screenY = panel:LocalToScreen(0, 0)
    local canvasX, canvasY = screenX + offsetX, screenY + offsetY
    render.SetScissorRect(
        math.floor(canvasX),
        math.floor(canvasY),
        math.ceil(canvasX + compiled.width * scale),
        math.ceil(canvasY + compiled.height * scale),
        true
    )
    local matrix = Matrix()
    matrix:Translate(Vector(canvasX, canvasY, 0))
    matrix:Scale(Vector(scale, scale, 1))
    matrix:Translate(Vector(-screenX, -screenY, 0))
    cam.PushModelMatrix(matrix)
        local group = compiled.themeGroup or 'default'
        local previous = DISPLAY.ClientState.ThemeState[group]
        local previousPack = DISPLAY.ClientState.ThemePacks[group]
        if self.Session.themeOverride and self.Session.themeOverride.group == group then
            DISPLAY.ClientState.ThemePacks[group] = self.Session.themeOverride
        end
        if self.Session.themeSimulation then DISPLAY.ClientState.ThemeState[group] = self.Session.themeSimulation end
        DISPLAY.DrawDisplayCanvas(compiled)
        DISPLAY.ClientState.ThemeState[group] = previous
        DISPLAY.ClientState.ThemePacks[group] = previousPack
        local selected = selectionObject(self.Session)
        if self.Session.selection and self.Session.selection.kind == 'element' and selected then
            surface.SetDrawColor(255, 220, 70, 255)
            surface.DrawOutlinedRect(selected.x or 0, selected.y or 0, selected.width or 1, selected.height or 1, 2)
            surface.DrawRect((selected.x or 0) + (selected.width or 1) - 6, (selected.y or 0) + (selected.height or 1) - 6, 6, 6)
        end
        surface.SetDrawColor(255, 220, 70, 150)
        for _, guide in ipairs(self.SnapGuides or {}) do
            if guide.axis == 'x' then surface.DrawLine(guide.value, 0, guide.value, compiled.height)
            else surface.DrawLine(0, guide.value, compiled.width, guide.value) end
        end
    cam.PopModelMatrix()
    render.SetScissorRect(0, 0, 0, 0, false)
end

function EditorPanel:CanvasPoint(panel, x, y)
    local scale, offsetX, offsetY = self:CanvasTransform(panel)
    return (x - offsetX) / scale, (y - offsetY) / scale
end

function EditorPanel:CanvasHits(x, y)
    local page = activePageSource(self.Session)
    local hits = {}
    for index, source in ipairs(page and page.elements or {}) do
        local resolved = DISPLAY.ApplyVariants(source, DISPLAY.ClientState.Providers or {})
        resolved.x = tonumber(resolved.x) or 0
        resolved.y = tonumber(resolved.y) or 0
        resolved.width = tonumber(resolved.width or resolved.w) or 64
        resolved.height = tonumber(resolved.height or resolved.h) or 32
        if resolved.visible ~= false and DISPLAY.PointInRect(x, y, resolved) then
            table.insert(hits, {index = index, z = tonumber(resolved.z) or 0, order = index})
        end
    end
    table.sort(hits, function(left, right)
        if left.z == right.z then return left.order > right.order end
        return left.z > right.z
    end)
    return hits
end

local function hitSignature(hits)
    local out = {}
    for index, hit in ipairs(hits) do out[index] = tostring(hit.index) .. ':' .. tostring(hit.z) end
    return table.concat(out, ',')
end

function EditorPanel:SelectCanvasHit(x, y, hits)
    if #hits == 0 then return nil end
    local signature = hitSignature(hits)
    local cycle = self.Session.hitCycle
    local same = cycle and cycle.page == self.Session.activePage and cycle.signature == signature
        and math.abs(cycle.x - x) <= 4 and math.abs(cycle.y - y) <= 4
    local position = same and (cycle.position % #hits + 1) or 1
    self.Session.hitCycle = {page = self.Session.activePage, signature = signature, x = x, y = y, position = position}
    local selection = {kind = 'element', page = self.Session.activePage, element = hits[position].index}
    self:SetSelection(selection, true)
    return selection
end

function EditorPanel:CanvasPressed(panel, code)
    local x, y = panel:CursorPos()
    x, y = self:CanvasPoint(panel, x, y)
    if code == MOUSE_RIGHT then
        if self.Session.source.buildMode == 'complex' then
            local hits = self:CanvasHits(x, y)
            if #hits == 0 then
                self.Session.rightClick = nil
                self:AddElementMenu(x, y)
                return
            end
            local previous = self.Session.rightClick
            local now = SysTime()
            if previous and previous.page == self.Session.activePage and now - previous.time <= 0.3
                and math.abs(previous.x - x) <= 4 and math.abs(previous.y - y) <= 4 then
                previous.cancelled = true
                self.Session.rightClick = nil
                self:AddElementMenu(x, y)
                return
            end
            self.Session.hitCycle = nil
            local selection = self:SelectCanvasHit(x, y, hits)
            local pending = {time = now, x = x, y = y, page = self.Session.activePage, selection = selection}
            self.Session.rightClick = pending
            timer.Simple(0.3, function()
                if not IsValid(self) or pending.cancelled or self.Session.rightClick ~= pending then return end
                self.Session.rightClick = nil
                self:OpenSelectionMenu(pending.selection)
            end)
        else
            local menu = DermaMenu()
            for _, lineType in ipairs({'text', 'value', 'bar', 'phase', 'graph', 'columns'}) do
                menu:AddOption('Add ' .. lineType .. ' line', function()
                    self:Changed(function()
                        self.Session.source.lines = self.Session.source.lines or {}
                        table.insert(self.Session.source.lines, {type = lineType, label = string.upper(lineType), value = 0})
                    end)
                end)
            end
            menu:Open()
        end
        return
    end
    if code ~= MOUSE_LEFT or self.Session.source.buildMode ~= 'complex' then return end
    local page = activePageSource(self.Session)
    if not page then return end
    local selection = self:SelectCanvasHit(x, y, self:CanvasHits(x, y))
    if not selection then return end
    local element = page.elements[selection.element]
    local elementX = tonumber(element.x) or 0
    local elementY = tonumber(element.y) or 0
    local elementWidth = tonumber(element.width or element.w) or 64
    local elementHeight = tonumber(element.height or element.h) or 32
    local resize = x >= elementX + elementWidth - 10 and y >= elementY + elementHeight - 10
    if not self.Session.readOnly then
        pushHistory(self.Session)
        element.x = elementX element.y = elementY
        element.width = elementWidth element.height = elementHeight
        self.Drag = {
            element = element,
            x = x,
            y = y,
            startX = element.x,
            startY = element.y,
            width = element.width,
            height = element.height,
            resize = resize,
            moved = false
        }
    end
end

local function snapValue(value, candidates, tolerance)
    local best, distance = value, tolerance + 1
    for _, candidate in ipairs(candidates) do
        local current = math.abs(value - candidate)
        if current < distance then best, distance = candidate, current end
    end
    return best, distance <= tolerance and best or nil
end

local function snapPosition(value, size, candidates, tolerance)
    local bestValue, bestGuide, bestDistance = value, nil, tolerance + 1
    for _, offset in ipairs({0, size * 0.5, size}) do
        for _, candidate in ipairs(candidates) do
            local distance = math.abs(value + offset - candidate)
            if distance < bestDistance then
                bestValue = value + candidate - (value + offset)
                bestGuide = candidate
                bestDistance = distance
            end
        end
    end
    return bestValue, bestDistance <= tolerance and bestGuide or nil
end

function EditorPanel:CanvasMoved(panel, cursorX, cursorY)
    local drag = self.Drag
    if not drag then return end
    local x, y = self:CanvasPoint(panel, cursorX, cursorY)
    local dx, dy = x - drag.x, y - drag.y
    if math.abs(dx) > 0.25 or math.abs(dy) > 0.25 then drag.moved = true end
    local grid = tonumber(self.Session.source.editorGrid) or 8
    local page = activePageSource(self.Session)
    local compiled = self.Session.compiled or {}
    local xCandidates, yCandidates = {0, compiled.width or 512}, {0, compiled.height or 256}
    if self.Session.source.editorSnapElements ~= false then
        for _, sibling in ipairs(page and page.elements or {}) do
            if sibling ~= drag.element then
                local siblingX = tonumber(sibling.x) or 0
                local siblingY = tonumber(sibling.y) or 0
                local siblingWidth = tonumber(sibling.width or sibling.w) or 64
                local siblingHeight = tonumber(sibling.height or sibling.h) or 32
                table.insert(xCandidates, siblingX) table.insert(xCandidates, siblingX + siblingWidth) table.insert(xCandidates, siblingX + siblingWidth / 2)
                table.insert(yCandidates, siblingY) table.insert(yCandidates, siblingY + siblingHeight) table.insert(yCandidates, siblingY + siblingHeight / 2)
            end
        end
    end
    self.SnapGuides = {}
    if drag.resize then
        local width = math.max(1, drag.width + dx)
        local height = math.max(1, drag.height + dy)
        if grid > 0 then
            width = math.floor(width / grid + 0.5) * grid
            height = math.floor(height / grid + 0.5) * grid
        end
        local snappedX, guideX = snapValue(drag.element.x + width, xCandidates, 4)
        local snappedY, guideY = snapValue(drag.element.y + height, yCandidates, 4)
        drag.element.width = math.max(snappedX - drag.element.x, 1)
        drag.element.height = math.max(snappedY - drag.element.y, 1)
        if guideX then table.insert(self.SnapGuides, {axis = 'x', value = guideX}) end
        if guideY then table.insert(self.SnapGuides, {axis = 'y', value = guideY}) end
    else
        local newX = drag.startX + dx
        local newY = drag.startY + dy
        if grid > 0 then
            newX = math.floor(newX / grid + 0.5) * grid
            newY = math.floor(newY / grid + 0.5) * grid
        end
        local snappedX, guideX = snapPosition(newX, drag.element.width, xCandidates, 4)
        local snappedY, guideY = snapPosition(newY, drag.element.height, yCandidates, 4)
        drag.element.x = snappedX
        drag.element.y = snappedY
        if guideX then table.insert(self.SnapGuides, {axis = 'x', value = guideX}) end
        if guideY then table.insert(self.SnapGuides, {axis = 'y', value = guideY}) end
    end
    self.Session.dirty = true
    self:Compile()
end

function EditorPanel:OnClose()
    EDITOR.Frame = nil
end

function EditorPanel:Close()
    if self._closeApproved then
        if IsValid(self.PreviewWindow) then self.PreviewWindow:Remove() end
        return self.BaseClass.Close(self)
    end
    self:ConfirmDiscard(function()
        if not IsValid(self) then return end
        self._closeApproved = true
        self:Close()
    end)
end

vgui.Register('LUASQUARE_3D2D_Editor', EditorPanel, 'DFrame')

function EDITOR.Open()
    if not canEdit() then
        notification.AddLegacy('The display editor is single-player/admin only.', NOTIFY_ERROR, 4)
        return
    end
    if IsValid(EDITOR.Frame) then EDITOR.Frame:MakePopup() return EDITOR.Frame end
    EDITOR.Frame = vgui.Create('LUASQUARE_3D2D_Editor')
    EDITOR.Frame:MakePopup()
    return EDITOR.Frame
end

net.Receive(DISPLAY.Net.EditorResult, function()
    local ok = net.ReadBool()
    local message = net.ReadString()
    notification.AddLegacy(message, ok and NOTIFY_GENERIC or NOTIFY_ERROR, 5)
end)

hook.Add('LUASQUARE_3D2D_SnapshotUpdated', 'LUASQUARE_3D2D_EditorRefreshTargets', function()
    if IsValid(EDITOR.Frame) then EDITOR.Frame:RefreshSources() end
end)

hook.Add('PopulateToolMenu', 'LUASQUARE_3D2D_EditorMenu', function()
    spawnmenu.AddToolMenuOption('Options', 'Luasquare', 'Luasquare3D2DEditor', '3D2D Display Editor', '', '', function(panel)
        panel:Help('Build JSON-backed Simple and Complex displays. Packed sources open read-only; Save draft writes a canonical JSON file under data/.')
        panel:Button('Open display editor').DoClick = EDITOR.Open
    end)
end)
