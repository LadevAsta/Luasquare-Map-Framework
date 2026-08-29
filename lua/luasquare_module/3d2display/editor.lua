if not CLIENT then return end

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
local DISPLAY = LUASQUARE_3D2D
local EDITOR = DISPLAY.Editor or {}
DISPLAY.Editor = EDITOR
EDITOR.Clipboard = EDITOR.Clipboard or nil
local userInput = _G.input

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
        variables = {},
        editorGrid = 8,
        editorSnapElements = true,
        showPageTabs = true,
        interaction = {enabled = true, distance = 128, lineOfSight = true},
        pages = {{id = 'overview', label = 'Overview', elements = {}}}
    }
end

local function migrateSourceConditions(source)
    local migrated = 0
    local function migrateObject(object)
        if type(object) ~= 'table' then return end
        local conditions = DISPLAY.DeepCopy(object.conditions or {})
        if object.variants ~= nil then
            for index, variant in ipairs(object.variants or {}) do
                table.insert(conditions, {
                    id = variant.id or ('legacy_variant_' .. index),
                    when = DISPLAY.DeepCopy(variant.when),
                    apply = DISPLAY.DeepCopy(variant.set or {})
                })
            end
            object.variants = nil
            migrated = migrated + 1
        end
        if object.visibleWhen ~= nil then
            table.insert(conditions, 1, {
                id = 'legacy_visibility',
                when = DISPLAY.DeepCopy(object.visibleWhen),
                apply = {visible = true},
                otherwise = {visible = false}
            })
            object.visibleWhen = nil
            migrated = migrated + 1
        end
        if #conditions > 0 then object.conditions = conditions end
    end
    for _, line in ipairs(source.lines or {}) do migrateObject(line) end
    for _, page in ipairs(source.pages or {}) do
        for _, element in ipairs(page.elements or {}) do
            migrateObject(element)
            for _, line in ipairs(element.lines or {}) do migrateObject(line) end
        end
    end
    return migrated
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
        previewTarget = nil,
        animationPreview = {},
        variableSimulation = {},
        inspectorCategories = {}
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

local function pushHistoryValue(session, value)
    table.insert(session.history, DISPLAY.DeepCopy(value))
    if #session.history > 100 then table.remove(session.history, 1) end
    session.future = {}
end

local function activePageSource(session)
    return session.source.pages and session.source.pages[session.activePage] or nil
end

local function objectAtSelection(source, selection)
    if not selection then return nil end
    if selection.kind == 'display' then return source end
    if selection.kind == 'page' then return source.pages and source.pages[selection.page] end
    local page = source.pages and source.pages[selection.page]
    if selection.kind == 'element' then return page and page.elements and page.elements[selection.element] end
    if selection.kind == 'line' then
        if source.buildMode == 'simple' then return source.lines and source.lines[selection.line] end
        local element = page and page.elements and page.elements[selection.element]
        return element and element.lines and element.lines[selection.line]
    end
end

local function selectionObject(session)
    return objectAtSelection(session.source, session.selection)
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
    self.Subwindows = {}
    self.SubwindowSerial = 0
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

    self.SourcePicker = self.Toolbar:Add('DButton')
    self.SourcePicker:Dock(LEFT)
    self.SourcePicker:SetWide(62)
    self.SourcePicker:SetText('File...')
    self.SourcePicker.DoClick = function() self:OpenSourceWindow() end

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
    self.SourcePathLabel = self.Toolbar:Add('DLabel')
    self.SourcePathLabel:Dock(FILL)
    self.SourcePathLabel:DockMargin(6, 0, 4, 0)
    self.SourcePathLabel:SetContentAlignment(4)
    self.SourcePathLabel:SetTextColor(Color(215, 215, 215))
    self.SourcePathLabel:SetZPos(10000)

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
    self.PreviewCanvas.OnMouseReleased = function(panel)
        panel:MouseCapture(false)
        local wasDragging = self.Drag and self.Drag.changed
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
    timer.Simple(0, function() if IsValid(self) and LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.ApplyTree(self) end end)
end

function EditorPanel:RefreshSources()
    if IsValid(self.SourcePicker) then self.SourcePicker:SetText('File...') end
    if IsValid(self.SourcePathLabel) then
        local origin = tostring(self.Session.origin or 'New source')
        self.SourcePathLabel:SetText(origin)
        self.SourcePathLabel:SetTooltip(origin)
    end
    if IsValid(self.SourceWindow) then self:PopulateSourceWindow() end
end

function EditorPanel:PopulateSourceWindow()
    if not IsValid(self.SourceWindowList) then return end
    local filter = string.lower(IsValid(self.SourceWindowSearch) and self.SourceWindowSearch:GetValue() or '')
    self.SourceWindowList:Clear()
    for _, entry in ipairs(listSources()) do
        local path = tostring(entry.path)
        if filter == '' or string.find(string.lower(path), filter, 1, true) then
            local line = self.SourceWindowList:AddLine(entry.readOnly and 'Packed' or 'Draft',
                string.GetFileFromFilename(path), path)
            line.SourceEntry = entry
            line:SetTooltip(path)
        end
    end
end

function EditorPanel:OpenSourceWindow()
    if IsValid(self.SourceWindow) then self:ActivateSubwindow(self.SourceWindow) return end
    local frame = vgui.Create('DFrame')
    self.SourceWindow = frame
    frame:SetTitle('3D2D Display Sources')
    frame:SetSize(math.min(ScrW() - 80, 900), math.min(ScrH() - 80, 600))
    frame.OnRemove = function()
        if IsValid(self) then
            self.Subwindows[frame] = nil
            self.SourceWindow = nil
        end
    end
    local search = frame:Add('DTextEntry')
    self.SourceWindowSearch = search
    search:Dock(TOP)
    search:DockMargin(6, 6, 6, 4)
    search:SetPlaceholderText('Search complete source path...')
    search.OnChange = function() self:PopulateSourceWindow() end
    local list = frame:Add('DListView')
    self.SourceWindowList = list
    list:Dock(FILL)
    list:DockMargin(6, 0, 6, 4)
    list:SetMultiSelect(false)
    list:AddColumn('Kind'):SetFixedWidth(70)
    list:AddColumn('File'):SetFixedWidth(220)
    list:AddColumn('Complete path')
    local function loadSelected()
        local selected = list:GetSelectedLine()
        local line = selected and list:GetLine(selected)
        if not line or not line.SourceEntry then return end
        local entry = line.SourceEntry
        self:ConfirmDiscard(function()
            local source, message = readSource(entry)
            if source then
                self:ReplaceSource(source, entry.path, entry.readOnly)
                if IsValid(frame) then frame:Close() end
            else
                Derma_Message(message, 'Open failed', 'OK')
            end
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
        self:ConfirmDiscard(function()
            self:ReplaceSource(defaultSource(), 'New source', false)
            if IsValid(frame) then frame:Close() end
        end)
    end)
    button('Load selected', loadSelected)
    button('Save draft', function() self:SaveDraft() self:PopulateSourceWindow() end)
    button('Close', function() frame:Close() end)
    self:PopulateSourceWindow()
    self:ActivateSubwindow(frame)
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
    if IsValid(self.ConditionWindow) then self.ConditionWindow:Remove() end
    if IsValid(self.VariableWindow) then self.VariableWindow:Remove() end
    self.Session = makeSession()
    self._skipExpansionCapture = true
    self.Session.source = DISPLAY.DeepCopy(source)
    self.Session.migratedConditions = migrateSourceConditions(self.Session.source)
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
    if IsValid(self.ConditionWindow) then self.ConditionWindow:Remove() end
    if IsValid(self.VariableWindow) then self.VariableWindow:Remove() end
    local previous = table.remove(self.Session.history)
    if not previous then return end
    table.insert(self.Session.future, snapshot(self.Session))
    self.Session.source = previous
    self.Session.dirty = true
    self:Compile() self:RebuildHierarchy() self:RebuildInspector()
end

function EditorPanel:Redo()
    if IsValid(self.ConditionWindow) then self.ConditionWindow:Remove() end
    if IsValid(self.VariableWindow) then self.VariableWindow:Remove() end
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
    if compiled then
        local simulation = self.Session.variableSimulation or {}
        for name, definition in pairs(compiled.variables or {}) do
            if simulation[name] == nil then simulation[name] = DISPLAY.DeepCopy(definition.default) end
            if definition.type == 'number' then
                local value = tonumber(simulation[name]) or definition.default or 0
                if definition.min then value = math.max(value, definition.min) end
                if definition.max then value = math.min(value, definition.max) end
                simulation[name] = value
            elseif definition.type == 'boolean' and type(simulation[name]) ~= 'boolean' then
                simulation[name] = definition.default
            elseif definition.type == 'string' and type(simulation[name]) ~= 'string' then
                simulation[name] = definition.default
            elseif definition.type == 'enum' and not table.HasValue(definition.choices or {}, simulation[name]) then
                simulation[name] = definition.default
            end
        end
        for name in pairs(simulation) do
            if not compiled.variables[name] then simulation[name] = nil end
        end
        self.Session.variableSimulation = simulation
        compiled.variableValues = DISPLAY.DeepCopy(simulation)
    end
    local errors = DISPLAY.DiagnosticsText(diagnostics)
    local dirty = self.Session.dirty and ' · UNSAVED' or ''
    local mode = self.Session.readOnly and 'PACKED READ-ONLY' or 'DRAFT EDITABLE'
    local migration = (self.Session.migratedConditions or 0) > 0
        and ('\nMigrated ' .. self.Session.migratedConditions .. ' legacy condition field(s); drafts save the new format.') or ''
    self.Status:SetText(mode .. dirty .. ' · ' .. self.Session.origin
        .. (errors ~= '' and ('\n' .. errors) or '\nValid source') .. migration)
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

function EditorPanel:ActivateSubwindow(frame)
    if not IsValid(frame) then return end
    frame:SetDeleteOnClose(true)
    frame:Center()
    self.SubwindowSerial = (self.SubwindowSerial or 0) + 1
    self.Subwindows[frame] = self.SubwindowSerial
    self.ActiveSubwindow = frame
    frame:MakePopup()
    frame:MoveToFront()
    timer.Simple(0, function() if IsValid(frame) and LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.ApplyTree(frame) end end)
end

function EditorPanel:Think()
    local cursorX, cursorY = userInput.GetCursorPos()
    local hovered
    local hoveredSerial = -1
    for frame, serial in pairs(self.Subwindows or {}) do
        if not IsValid(frame) then
            self.Subwindows[frame] = nil
        elseif frame:IsVisible() then
            local x, y = frame:LocalToScreen(0, 0)
            if cursorX >= x and cursorX <= x + frame:GetWide()
                and cursorY >= y and cursorY <= y + frame:GetTall()
                and serial > hoveredSerial then
                hovered = frame
                hoveredSerial = serial
            end
        end
    end
    if hovered ~= self.HoveredSubwindow then
        self.HoveredSubwindow = hovered
        if IsValid(hovered) then
            self.SubwindowSerial = (self.SubwindowSerial or 0) + 1
            self.Subwindows[hovered] = self.SubwindowSerial
            self.ActiveSubwindow = hovered
            hovered:MoveToFront()
        end
    end
end

function EditorPanel:OpenPreviewWindow()
    if IsValid(self.PreviewWindow) then self:ActivateSubwindow(self.PreviewWindow) return end
    local frame = vgui.Create('DFrame')
    self.PreviewWindow = frame
    frame:SetTitle('Runtime Preview')
    frame:SetSize(390, 175)
    frame:SetSizable(false)
    self:ActivateSubwindow(frame)
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

function EditorPanel:SetSelection(selection, switchPage, preserveHitCycle)
    if not selection then return end
    if not preserveHitCycle then self.Session.hitCycle = nil end
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

function EditorPanel:InspectorAdd(className)
    local target = self.InspectorTarget or self.Inspector
    local control = target:Add(className)
    if target == self.InspectorTarget and IsValid(self.InspectorTarget) then
        self.CurrentInspectorOrder = (self.CurrentInspectorOrder or 0) + 1
        control.LuasquareInspectorOrder = self.CurrentInspectorOrder
        control:SetZPos(self.CurrentInspectorOrder)
    end
    return control
end

function EditorPanel:BeginInspectorCategory(title, key, expandedByDefault)
    self.InspectorTarget = nil
    local category = self.Inspector:Add('DCollapsibleCategory')
    category:Dock(TOP)
    category:DockMargin(4, 3, 4, 0)
    category:SetLabel(title)
    local states = self.Session.inspectorCategories or {}
    self.Session.inspectorCategories = states
    local expanded = states[key]
    if expanded == nil then expanded = expandedByDefault ~= false end
    category:SetExpanded(expanded)
    category.OnToggle = function(_, open) states[key] = open and true or false end
    local content = vgui.Create('DPanel', category)
    content:SetPaintBackground(false)
    content:DockPadding(0, 2, 0, 4)
    content.PerformLayout = function(panel)
        local height = 6
        local children = panel:GetChildren()
        table.sort(children, function(left, right)
            return (left.LuasquareInspectorOrder or 0) < (right.LuasquareInspectorOrder or 0)
        end)
        for order, child in ipairs(children) do
            if child.LuasquareInspectorOrder and child:GetZPos() ~= order then child:SetZPos(order) end
            local _, top, _, bottom = child:GetDockMargin()
            height = height + child:GetTall() + top + bottom
        end
        panel:SetTall(math.max(height, 8))
    end
    category:SetContents(content)
    self.InspectorTarget = content
    self.CurrentInspectorCategory = category
    self.CurrentInspectorOrder = 0
    return category
end

function EditorPanel:EndInspectorCategory()
    if IsValid(self.InspectorTarget) then self.InspectorTarget:InvalidateLayout(true) end
    if IsValid(self.CurrentInspectorCategory) then self.CurrentInspectorCategory:InvalidateLayout(true) end
    self.InspectorTarget = nil
    self.CurrentInspectorCategory = nil
    self.CurrentInspectorOrder = nil
end

function EditorPanel:AddInspectorLabel(text)
    local label = self:InspectorAdd('DLabel')
    label:Dock(TOP)
    label:DockMargin(6, 5, 6, 0)
    label:SetText(text)
    label:SetWrap(true)
    label:SetAutoStretchVertical(true)
    return label
end

function EditorPanel:AddTextField(labelText, object, key)
    self:AddInspectorLabel(labelText)
    local field = self:InspectorAdd('DTextEntry')
    field:Dock(TOP)
    field:DockMargin(6, 2, 6, 0)
    field:SetValue(tostring(object[key] or ''))
    field.OnEnter = function(input)
        local value = input:GetValue()
        self:Changed(function() object[key] = value ~= '' and value or nil end)
    end
end

function EditorPanel:AddNumberField(labelText, object, key, minimum, maximum, decimals, initialValue, onChanged)
    local slider = self:InspectorAdd('DNumSlider')
    slider:Dock(TOP)
    slider:DockMargin(6, 2, 6, 0)
    slider:SetText(labelText)
    slider:SetMin(minimum)
    slider:SetMax(maximum)
    slider:SetDecimals(decimals or 0)
    slider:SetValue(tonumber(object[key]) or tonumber(initialValue) or minimum)
    slider.OnValueChanged = function(input, value)
        if input._ignore then return end
        if onChanged then onChanged(tonumber(value)) return end
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
    local field = self:InspectorAdd('DTextEntry')
    field:Dock(TOP)
    field:DockMargin(6, 2, 6, 0)
    field:SetMultiline(true)
    field:SetTall(80)
    field:SetValue(canonicalJSON(object[key] ~= nil and object[key] or {}))
    local apply = self:InspectorAdd('DButton')
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

function EditorPanel:AddBoolField(labelText, object, key, defaultValue, onChanged)
    local box = self:InspectorAdd('DCheckBoxLabel')
    box:Dock(TOP) box:DockMargin(6, 5, 6, 0)
    box:SetText(labelText)
    box:SetValue(object[key] == nil and (defaultValue and 1 or 0) or (object[key] and 1 or 0))
    box:SizeToContents()
    box.OnChange = function(_, checked)
        local value = checked and true or false
        if onChanged then onChanged(value)
        else self:Changed(function() object[key] = value end) end
    end
    return box
end

function EditorPanel:AddChoiceField(labelText, object, key, choices, fallback)
    self:AddInspectorLabel(labelText)
    local combo = self:InspectorAdd('DComboBox')
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
    local out = {}
    local known = {}
    for _, theme in pairs(pack and pack.themes or {}) do
        for token in pairs(theme.tokens or theme.colors or theme) do
            if not known[token] then known[token] = true table.insert(out, token) end
        end
    end
    table.sort(out)
    return out
end

function EditorPanel:OpenColorPicker(object, key, onChanged)
    local frame = vgui.Create('DFrame')
    frame:SetTitle('Choose custom color') frame:SetSize(330, 390)
    self:ActivateSubwindow(frame)
    local mixer = frame:Add('DColorMixer')
    mixer:Dock(FILL) mixer:DockMargin(8, 8, 8, 4)
    mixer:SetPalette(true) mixer:SetAlphaBar(true) mixer:SetWangs(true)
    local currentColor = colorArray(object[key])
    mixer:SetColor(Color(currentColor[1], currentColor[2], currentColor[3], currentColor[4]))
    local apply = frame:Add('DButton')
    apply:Dock(BOTTOM) apply:DockMargin(8, 4, 8, 8) apply:SetTall(28) apply:SetText('Apply RGBA')
    apply.DoClick = function()
        local color = mixer:GetColor()
        local selectedValue = {color.r, color.g, color.b, color.a}
        if onChanged then onChanged(selectedValue)
        else self:Changed(function() object[key] = selectedValue end) end
        frame:Close()
    end
end

local inheritedColorKeys = {
    color = 'textColor',
    textColor = 'textColor',
    titleColor = 'titleColor',
    backgroundColor = 'backgroundColor',
    borderColor = 'borderColor',
    barColor = 'barColor',
    fillColor = 'barColor',
    tint = false
}

function EditorPanel:AddColorField(labelText, object, key, allowInherit, onChanged)
    self:AddInspectorLabel(labelText)
    local row = self:InspectorAdd('DPanel')
    row:Dock(TOP) row:DockMargin(6, 2, 6, 0) row:SetTall(28)
    local selector = row:Add('DComboBox')
    selector:Dock(FILL)
    if allowInherit then selector:AddChoice('Inherit (use parent/theme default)', '__inherit') end
    for _, token in ipairs(self:ThemeTokens()) do selector:AddChoice('Theme: @' .. token, '@' .. token) end
    selector:AddChoice('Custom RGBA...', '__custom')
    local current = object[key]
    local inheritedKey = inheritedColorKeys[key]
    local inherited = inheritedKey and (self.Session.compiled or self.Session.source)[inheritedKey]
        or (key == 'tint' and {255, 255, 255, 255} or '@text')
    local inheritedLabel = type(inherited) == 'string' and inherited
        or ('RGBA ' .. table.concat(colorArray(inherited), ', '))
    selector:SetValue(current == nil and ('Inherit: ' .. inheritedLabel)
        or (type(current) == 'string' and ('Theme: ' .. current)
        or ('RGBA: ' .. table.concat(colorArray(current), ', '))))
    local swatch = row:Add('DButton')
    swatch:Dock(RIGHT) swatch:DockMargin(4, 0, 0, 0) swatch:SetWide(54) swatch:SetText('Edit')
    swatch.Paint = function(button, width, height)
        local source = object[key] == nil and inherited or object[key]
        local display = self.Session.compiled or self.Session.source
        local resolved = DISPLAY.ResolveThemeToken(display, source, {r = 255, g = 255, b = 255, a = 255}, DISPLAY.ClientState)
        surface.SetDrawColor(resolved.r, resolved.g, resolved.b, resolved.a)
        surface.DrawRect(2, 2, width - 4, height - 4)
        surface.SetDrawColor(20, 20, 20, 255)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end
    local function assign(value)
        value = DISPLAY.DeepCopy(value)
        if onChanged then object[key] = DISPLAY.DeepCopy(value) onChanged(value)
        else self:Changed(function() object[key] = value end) end
    end
    local customCallback = onChanged and function(value)
        object[key] = DISPLAY.DeepCopy(value)
        onChanged(value)
    end or nil
    selector.OnSelect = function(_, _, _, value)
        if value == '__custom' then self:OpenColorPicker(object, key, customCallback)
        else assign(value == '__inherit' and nil or value) end
    end
    swatch.DoClick = function() self:OpenColorPicker(object, key, customCallback) end
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
    frame:SetTitle('Material browser') frame:SetSize(820, 600)
    self:ActivateSubwindow(frame)
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
    content.Think = function()
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
    local row = self:InspectorAdd('DPanel')
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

local function valueTypeName(value)
    if type(value) ~= 'table' then return type(value) end
    return 'object'
end

function EditorPanel:ProviderPaths(providerId)
    local paths = {}
    local known = {}
    local function add(path, valueType, value, label)
        path = tostring(path or '')
        if path == '' then return end
        if known[path] then
            local existing = known[path]
            if value ~= nil then
                existing.value = value
                if not existing.type or existing.type == 'unknown' then
                    existing.type = valueType or valueTypeName(value)
                end
            end
            if label and not existing.label then existing.label = label end
            return
        end
        if #paths >= 512 then return end
        local entry = {path = path, type = valueType or valueTypeName(value), value = value, label = label}
        known[path] = entry
        table.insert(paths, entry)
    end
    local catalog = (DISPLAY.KnownProviders or {})[providerId] or {}
    for _, field in ipairs(catalog.fields or {}) do add(field.path, field.type, nil, field.label) end
    local function walk(value, prefix, depth)
        if #paths >= 512 or depth > 8 then return end
        if type(value) ~= 'table' then add(prefix, type(value), value) return end
        local hadChild = false
        for childKey, child in SortedPairs(value) do
            hadChild = true
            local path = prefix == '' and tostring(childKey) or (prefix .. '.' .. tostring(childKey))
            walk(child, path, depth + 1)
            if #paths >= 512 then break end
        end
        if not hadChild and prefix ~= '' then add(prefix, 'object', value) end
    end
    walk((DISPLAY.ClientState.Providers or {})[providerId], '', 0)
    table.sort(paths, function(left, right) return left.path < right.path end)
    return paths
end

function EditorPanel:AddBindingField(labelText, object, key)
    self:AddInspectorLabel(labelText)
    local binding = type(object[key]) == 'table' and object[key] or {}
    local sourceType = self:InspectorAdd('DComboBox')
    sourceType:Dock(TOP) sourceType:DockMargin(6, 2, 6, 0)
    sourceType:AddChoice('Data provider', 'provider')
    sourceType:AddChoice('Display variable', 'variable')
    sourceType:SetValue(binding.variable ~= nil and 'Display variable' or 'Data provider')

    local source = self:InspectorAdd('DComboBox')
    source:Dock(TOP) source:DockMargin(6, 2, 6, 0)
    local path = self:InspectorAdd('DComboBox')
    path:Dock(TOP) path:DockMargin(6, 2, 6, 0)
    local manualPath = self:InspectorAdd('DTextEntry')
    manualPath:Dock(TOP) manualPath:DockMargin(6, 2, 6, 0)
    manualPath:SetPlaceholderText('Provider path (manual entry)')

    local function configure(mode)
        source:Clear()
        path:Clear()
        path:SetVisible(mode == 'provider')
        manualPath:SetVisible(mode == 'provider')
        if mode == 'variable' then
            source:SetValue(binding.variable or 'Display variable')
            for name, definition in SortedPairs(self.Session.source.variables or {}) do
                source:AddChoice(tostring(definition.label or name), name)
            end
        else
            source:SetValue(binding.provider or 'Provider')
            for id, provider in SortedPairs(DISPLAY.KnownProviders or {}) do
                source:AddChoice(tostring(provider.label or id), id)
            end
            path:SetValue(tostring(binding.path or ''))
            manualPath:SetValue(tostring(binding.path or ''))
            for _, field in ipairs(self:ProviderPaths(binding.provider)) do
                local suffix = field.value ~= nil and (' = ' .. tostring(field.value)) or ''
                path:AddChoice(string.format('%s [%s]%s', field.label or field.path, field.type or '?', suffix), field.path)
            end
        end
    end
    sourceType.OnSelect = function(_, _, _, mode)
        self:Changed(function()
            object[key] = {provider = ''}
            if mode == 'variable' then object[key] = {variable = ''} end
        end)
    end
    source.OnSelect = function(_, _, _, id)
        self:Changed(function()
            object[key] = type(object[key]) == 'table' and object[key] or {}
            if object[key].variable ~= nil then object[key].variable = id
            else object[key].provider = id object[key].path = nil end
        end)
    end
    path.OnSelect = function(_, _, _, selectedPath)
        self:Changed(function()
            object[key] = type(object[key]) == 'table' and object[key] or {}
            object[key].path = selectedPath ~= '' and selectedPath or nil
        end)
    end
    manualPath.OnEnter = function(input)
        self:Changed(function()
            object[key] = type(object[key]) == 'table' and object[key] or {}
            object[key].path = input:GetValue() ~= '' and input:GetValue() or nil
        end)
    end
    configure(binding.variable ~= nil and 'variable' or 'provider')
end

function EditorPanel:AddActionFields(object)
    self:AddInspectorLabel('Named action')
    local action = self:InspectorAdd('DComboBox')
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
            local row = self:InspectorAdd('DPanel')
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
    local add = self:InspectorAdd('DButton')
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
end

function EditorPanel:AddFrameEditor(object)
    self:AddInspectorLabel('Material frames')
    for index, path in ipairs(object.frames or {}) do
        local row = self:InspectorAdd('DPanel')
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
    local add = self:InspectorAdd('DButton')
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

local conditionOperatorChoices = {
    {label = 'is true', value = 'truthy'},
    {label = '==', value = 'eq'},
    {label = '!=', value = 'ne'},
    {label = '>', value = 'gt'},
    {label = '>=', value = 'gte'},
    {label = '<', value = 'lt'},
    {label = '<=', value = 'lte'}
}

local conditionEffectSpecs = {
    {key = 'visible', label = 'Visibility', kind = 'boolean', default = true},
    {key = 'flashEnabled', label = 'Flash enabled', kind = 'boolean', default = true},
    {key = 'frameAnimationEnabled', label = 'Frame animation enabled', kind = 'boolean', default = true},
    {key = 'rotationAnimationEnabled', label = 'Rotation animation enabled', kind = 'boolean', default = true},
    {key = 'color', label = 'Color', kind = 'color', default = '@text'},
    {key = 'tint', label = 'Material tint', kind = 'color', default = {255, 255, 255, 255}},
    {key = 'backgroundColor', label = 'Background color', kind = 'color', default = '@panel'},
    {key = 'borderColor', label = 'Border color', kind = 'color', default = '@border'},
    {key = 'material', label = 'Material', kind = 'material', default = 'vgui/white'},
    {key = 'flashSeconds', label = 'Flash seconds', kind = 'number', default = 0.25, min = 0, max = 60},
    {key = 'frameSeconds', label = 'Frame seconds', kind = 'number', default = 0.25, min = 0, max = 60},
    {key = 'rotationDegrees', label = 'Rotation degrees', kind = 'number', default = 0, min = -360000, max = 360000},
    {key = 'rotationSpeedDegreesPerSecond', label = 'Rotation speed (deg/s)', kind = 'number', default = 0, min = -10000, max = 10000}
}

function EditorPanel:AddConditionComparisonField(condition)
    if not condition.when or condition.when.op == 'truthy' then return end
    local definition
    local inferredType
    local currentValue = DISPLAY.ResolveBinding(
        condition.when,
        DISPLAY.ClientState.Providers or {},
        self.Session.variableSimulation or {}
    )
    if condition.when.variable then
        definition = (self.Session.source.variables or {})[condition.when.variable]
        inferredType = definition and definition.type
    else
        for _, field in ipairs(self:ProviderPaths(condition.when.provider)) do
            if field.path == condition.when.path then inferredType = field.type break end
        end
    end
    inferredType = inferredType or type(currentValue)
    self:AddInspectorLabel('Comparison source [' .. tostring(inferredType or 'unknown')
        .. '] current: ' .. tostring(currentValue))
    local source = self:InspectorAdd('DComboBox')
    source:Dock(TOP) source:DockMargin(6, 2, 6, 0)
    source:AddChoice('Literal value', 'literal')
    source:AddChoice('Display variable', 'variable')
    source:SetValue(DISPLAY.IsBinding(condition.when.value) and condition.when.value.variable
        and 'Display variable' or 'Literal value')
    source.OnSelect = function(_, _, _, mode)
        self:Changed(function()
            if mode == 'variable' then
                local first
                for name in SortedPairs(self.Session.source.variables or {}) do first = name break end
                condition.when.value = {variable = first or ''}
            elseif inferredType == 'boolean' then condition.when.value = false
            elseif inferredType == 'number' then condition.when.value = 0
            else condition.when.value = '' end
        end)
    end

    if DISPLAY.IsBinding(condition.when.value) and condition.when.value.variable then
        self:AddInspectorLabel('Comparison display variable')
        local variables = self:InspectorAdd('DComboBox')
        variables:Dock(TOP) variables:DockMargin(6, 2, 6, 0)
        variables:SetValue(condition.when.value.variable)
        for name, variable in SortedPairs(self.Session.source.variables or {}) do
            variables:AddChoice(tostring(variable.label or name) .. ' [' .. tostring(variable.type) .. ']', name)
        end
        variables.OnSelect = function(_, _, _, name)
            self:Changed(function() condition.when.value = {variable = name} end)
        end
        return
    end

    self:AddInspectorLabel('Comparison value')
    if inferredType == 'boolean' then
        local holder = {value = condition.when.value and true or false}
        self:AddBoolField('Value is true', holder, 'value', false, function(value)
            self:Changed(function() condition.when.value = value end)
        end)
    elseif inferredType == 'enum' and definition then
        self:AddChoiceField('Enum value', condition.when, 'value', definition.choices or {}, definition.default)
    elseif inferredType == 'color' then
        self:AddColorField('Color value', condition.when, 'value', false)
    else
        local entry = self:InspectorAdd('DTextEntry')
        entry:Dock(TOP) entry:DockMargin(6, 2, 6, 0)
        entry:SetValue(tostring(condition.when.value == nil and '' or condition.when.value))
        entry.OnEnter = function(input)
            local raw = string.Trim(input:GetValue())
            local value = inferredType == 'number' and tonumber(raw) or raw
            if inferredType == 'number' and value == nil then
                notification.AddLegacy('Comparison requires a number.', NOTIFY_ERROR, 3)
                return
            end
            self:Changed(function() condition.when.value = value end)
        end
    end
end

function EditorPanel:AddConditionEffects(condition, branchName, labelText)
    self:AddInspectorLabel(labelText)
    local branch = condition[branchName] or {}
    for _, spec in ipairs(conditionEffectSpecs) do
        local effectSpec = spec
        if branch[effectSpec.key] ~= nil then
            if effectSpec.kind == 'boolean' then self:AddBoolField(effectSpec.label, branch, effectSpec.key, effectSpec.default)
            elseif effectSpec.kind == 'color' then self:AddColorField(effectSpec.label, branch, effectSpec.key, false)
            elseif effectSpec.kind == 'material' then self:AddMaterialField(effectSpec.label, branch, effectSpec.key)
            else self:AddNumberField(effectSpec.label, branch, effectSpec.key, effectSpec.min, effectSpec.max, 2, effectSpec.default) end
            local remove = self:InspectorAdd('DButton')
            remove:Dock(TOP) remove:DockMargin(6, 1, 6, 3) remove:SetTall(20)
            remove:SetText('Remove ' .. effectSpec.label .. ' effect')
            remove.DoClick = function()
                self:Changed(function()
                    condition[branchName][effectSpec.key] = nil
                    if not next(condition[branchName]) then condition[branchName] = branchName == 'apply' and {} or nil end
                end)
            end
        end
    end
    local add = self:InspectorAdd('DButton')
    add:Dock(TOP) add:DockMargin(6, 3, 6, 4) add:SetText('Add ' .. string.lower(labelText) .. ' effect...')
    add.DoClick = function()
        local menu = DermaMenu()
        for _, spec in ipairs(conditionEffectSpecs) do
            local effectSpec = spec
            if branch[effectSpec.key] == nil then
                menu:AddOption(effectSpec.label, function()
                    self:Changed(function()
                        condition[branchName] = condition[branchName] or {}
                        condition[branchName][effectSpec.key] = DISPLAY.DeepCopy(effectSpec.default)
                    end)
                end)
            end
        end
        menu:Open()
    end
end

local conditionSymbols = {
    truthy = 'is true', eq = '==', ne = '!=', gt = '>', gte = '>=', lt = '<', lte = '<='
}

local function conditionSummary(condition, index)
    local when = type(condition.when) == 'table' and condition.when or {}
    local source
    if when.variable then source = '$' .. tostring(when.variable)
    elseif when.provider then
        source = tostring(when.provider)
        if when.path and when.path ~= '' then source = source .. '.' .. tostring(when.path) end
    elseif when.all then source = 'all(...)'
    elseif when.any then source = 'any(...)'
    elseif when['not'] then source = 'not(...)'
    else source = '?' end
    return string.format('%d. %s: %s %s', index, tostring(condition.id or 'condition'), source,
        conditionSymbols[when.op or 'truthy'] or '?')
end

local function parseEditorScalar(raw)
    raw = string.Trim(tostring(raw or ''))
    if raw == 'true' then return true end
    if raw == 'false' then return false end
    local number = tonumber(raw)
    if number ~= nil then return number end
    if string.sub(raw, 1, 1) == '[' or string.sub(raw, 1, 1) == '{' then
        local wrapper = util.JSONToTable('{"value":' .. raw .. '}')
        if type(wrapper) == 'table' and wrapper.value ~= nil then return wrapper.value end
    end
    return raw
end

local function conditionMaterialCallback(setEffect, entry)
    return function(path)
        setEffect(path)
        if IsValid(entry) then entry:SetValue(path) end
    end
end

local function conditionColorCallback(setEffect)
    return function(value)
        if string.sub(value, 1, 1) == '@' then setEffect(value)
        else setEffect(parseEditorScalar(value)) end
    end
end

function EditorPanel:OpenConditionWindow(object, index, initialCondition)
    if self.Session.readOnly then
        Derma_Message('Save the packed source as a draft before editing conditions.', 'Read-only source', 'OK')
        return
    end
    if IsValid(self.ConditionWindow) then self.ConditionWindow:Remove() end

    local selection = DISPLAY.DeepCopy(self.Session.selection)
    local sourceCondition = initialCondition or (object.conditions and object.conditions[index]) or {}
    local working = DISPLAY.DeepCopy(sourceCondition)
    working.id = tostring(working.id or ('condition_' .. tostring((object.conditions and #object.conditions or 0) + 1)))
    working.when = type(working.when) == 'table' and working.when or {provider = '', op = 'truthy'}
    working.apply = type(working.apply) == 'table' and working.apply or {}

    local frame = vgui.Create('DFrame')
    self.ConditionWindow = frame
    frame:SetTitle(index and ('Edit condition ' .. tostring(index)) or 'Add condition')
    frame:SetSize(math.min(860, ScrW() - 80), math.min(720, ScrH() - 80))
    frame:SetSizable(true)
    frame:SetMinWidth(650)
    frame:SetMinHeight(520)
    self:ActivateSubwindow(frame)
    frame.OnRemove = function()
        if self.ConditionWindow == frame then self.ConditionWindow = nil end
    end

    local buttons = frame:Add('DPanel')
    buttons:Dock(BOTTOM) buttons:DockMargin(8, 4, 8, 8) buttons:SetTall(30)
    local cancel = buttons:Add('DButton')
    cancel:Dock(RIGHT) cancel:SetWide(90) cancel:SetText('Cancel')
    cancel.DoClick = function() frame:Close() end
    local apply = buttons:Add('DButton')
    apply:Dock(RIGHT) apply:DockMargin(0, 0, 6, 0) apply:SetWide(110) apply:SetText('Apply condition')

    local sheets = frame:Add('DPropertySheet')
    sheets:Dock(FILL) sheets:DockMargin(8, 8, 8, 0)
    local sourceTab = vgui.Create('DScrollPanel', sheets)
    local trueTab = vgui.Create('DScrollPanel', sheets)
    local falseTab = vgui.Create('DScrollPanel', sheets)
    local advancedTab = vgui.Create('DPanel', sheets)
    sheets:AddSheet('Condition', sourceTab, 'icon16/wrench.png')
    sheets:AddSheet('When true', trueTab, 'icon16/accept.png')
    sheets:AddSheet('When false', falseTab, 'icon16/cancel.png')
    sheets:AddSheet('Advanced JSON', advancedTab, 'icon16/script_code.png')

    local function addLabel(parent, text)
        local label = parent:Add('DLabel')
        label:Dock(TOP) label:DockMargin(8, 5, 8, 0) label:SetTall(18) label:SetText(text)
        return label
    end
    local function addEntry(parent, value, callback)
        local entry = parent:Add('DTextEntry')
        entry:Dock(TOP) entry:DockMargin(8, 1, 8, 2) entry:SetTall(24) entry:SetValue(tostring(value or ''))
        entry.OnValueChange = function(input) callback(input:GetValue()) end
        return entry
    end
    local function addCombo(parent, value, choices, callback)
        local combo = parent:Add('DComboBox')
        combo:Dock(TOP) combo:DockMargin(8, 1, 8, 2) combo:SetTall(24) combo:SetValue(tostring(value or ''))
        for _, choice in ipairs(choices or {}) do combo:AddChoice(choice.label or tostring(choice.value), choice.value) end
        combo.OnSelect = function(_, _, _, selected) callback(selected) end
        return combo
    end

    local rebuildSource
    rebuildSource = function()
        sourceTab:GetCanvas():Clear()
        addLabel(sourceTab, 'Condition ID')
        addEntry(sourceTab, working.id, function(value) working.id = value end)

        local when = working.when
        local nested = when.all ~= nil or when.any ~= nil or when['not'] ~= nil
        if nested then
            local notice = addLabel(sourceTab, 'This rule uses nested all/any/not logic. Edit it in Advanced JSON, or replace it with a simple condition.')
            notice:SetWrap(true) notice:SetTall(40)
            local replace = sourceTab:Add('DButton')
            replace:Dock(TOP) replace:DockMargin(8, 4, 8, 6) replace:SetTall(25) replace:SetText('Replace with simple condition')
            replace.DoClick = function()
                working.when = {provider = '', op = 'truthy'}
                rebuildSource()
            end
            return
        end

        local mode = when.variable ~= nil and 'variable' or 'provider'
        addLabel(sourceTab, 'Condition source type')
        addCombo(sourceTab, mode == 'variable' and 'Display variable' or 'Data provider', {
            {label = 'Data provider', value = 'provider'},
            {label = 'Display variable', value = 'variable'}
        }, function(selected)
            local previousOperator = when.op or 'truthy'
            local previousValue = when.value
            if selected == 'variable' then working.when = {variable = '', op = previousOperator, value = previousValue}
            else working.when = {provider = '', op = previousOperator, value = previousValue} end
            rebuildSource()
        end)

        if mode == 'variable' then
            local choices = {}
            for name, definition in SortedPairs(self.Session.source.variables or {}) do
                table.insert(choices, {label = tostring(definition.label or name) .. ' [' .. tostring(definition.type) .. ']', value = name})
            end
            addLabel(sourceTab, 'Display variable')
            addCombo(sourceTab, when.variable or 'Select variable', choices, function(selected)
                working.when.variable = selected
                rebuildSource()
            end)
        else
            local providers = {}
            for id, provider in SortedPairs(DISPLAY.KnownProviders or {}) do
                table.insert(providers, {label = tostring(provider.label or id), value = id})
            end
            addLabel(sourceTab, 'Data provider')
            addCombo(sourceTab, when.provider or 'Select provider', providers, function(selected)
                working.when.provider = selected
                working.when.path = nil
                rebuildSource()
            end)
            addLabel(sourceTab, 'Discovered provider path')
            local pathChoices = {}
            for _, field in ipairs(self:ProviderPaths(when.provider)) do
                local suffix = field.value ~= nil and (' = ' .. tostring(field.value)) or ''
                table.insert(pathChoices, {
                    label = string.format('%s [%s]%s', field.label or field.path, field.type or '?', suffix),
                    value = field.path
                })
            end
            addCombo(sourceTab, when.path or 'Root value', pathChoices, function(selected)
                working.when.path = selected ~= '' and selected or nil
            end)
            addLabel(sourceTab, 'Provider path (manual entry)')
            local manualPath = addEntry(sourceTab, when.path, function(value)
                working.when.path = value ~= '' and value or nil
            end)
            manualPath:SetPlaceholderText('Nested path, for example reactor.power')
        end

        addLabel(sourceTab, 'Operator')
        addCombo(sourceTab, conditionSymbols[when.op or 'truthy'] or 'is true', conditionOperatorChoices, function(selected)
            working.when.op = selected
            if selected == 'truthy' then working.when.value = nil end
            rebuildSource()
        end)
        if (when.op or 'truthy') == 'truthy' then return end

        local comparisonMode = DISPLAY.IsBinding(when.value) and when.value.variable and 'variable' or 'literal'
        addLabel(sourceTab, 'Comparison source')
        addCombo(sourceTab, comparisonMode == 'variable' and 'Display variable' or 'Literal value', {
            {label = 'Literal value', value = 'literal'},
            {label = 'Display variable', value = 'variable'}
        }, function(selected)
            if selected == 'variable' then working.when.value = {variable = ''}
            else working.when.value = '' end
            rebuildSource()
        end)
        if comparisonMode == 'variable' then
            local choices = {}
            for name, definition in SortedPairs(self.Session.source.variables or {}) do
                table.insert(choices, {label = tostring(definition.label or name) .. ' [' .. tostring(definition.type) .. ']', value = name})
            end
            addLabel(sourceTab, 'Comparison display variable')
            addCombo(sourceTab, when.value.variable or 'Select variable', choices, function(selected)
                working.when.value = {variable = selected}
            end)
        else
            addLabel(sourceTab, 'Comparison value (number, true/false, string, or JSON value)')
            local shown = type(when.value) == 'table' and canonicalJSON(when.value) or tostring(when.value == nil and '' or when.value)
            addEntry(sourceTab, shown, function(value) working.when.value = parseEditorScalar(value) end)
        end
    end

    local rebuildEffects
    rebuildEffects = function(tab, branchName)
        tab:GetCanvas():Clear()
        local branch = type(working[branchName]) == 'table' and working[branchName] or {}
        if branchName == 'otherwise' then
            local help = addLabel(tab, 'Optional false-branch effects. With no effects, the immutable base properties are used.')
            help:SetWrap(true) help:SetTall(38)
        end
        for _, spec in ipairs(conditionEffectSpecs) do
            local effectSpec = spec
            local effectKey = effectSpec.key
            local enabled = branch[effectKey] ~= nil
            local function setEffect(value) branch[effectKey] = value end
            local toggle = tab:Add('DCheckBoxLabel')
            toggle:Dock(TOP) toggle:DockMargin(8, 6, 8, 0) toggle:SetText(effectSpec.label)
            toggle:SetValue(enabled and 1 or 0) toggle:SizeToContents()
            toggle.OnChange = function(_, checked)
                if type(working[branchName]) ~= 'table' then working[branchName] = {} end
                local values = working[branchName]
                if checked then values[effectKey] = DISPLAY.DeepCopy(effectSpec.default)
                else values[effectKey] = nil end
                rebuildEffects(tab, branchName)
            end
            if enabled then
                if effectSpec.kind == 'boolean' then
                    addCombo(tab, branch[effectKey] and 'true' or 'false', {
                        {label = 'true', value = true}, {label = 'false', value = false}
                    }, function(value) setEffect(value and true or false) end)
                elseif effectSpec.kind == 'number' then
                    local number = tab:Add('DNumberWang')
                    number:Dock(TOP) number:DockMargin(24, 1, 8, 2) number:SetTall(24)
                    number:SetMinMax(effectSpec.min, effectSpec.max) number:SetDecimals(3)
                    number:SetValue(tonumber(branch[effectKey]) or effectSpec.default)
                    number.OnValueChanged = function(input) setEffect(tonumber(input:GetValue()) or effectSpec.default) end
                elseif effectSpec.kind == 'material' then
                    local row = tab:Add('DPanel')
                    row:Dock(TOP) row:DockMargin(24, 1, 8, 2) row:SetTall(24)
                    local browse = row:Add('DButton')
                    browse:Dock(RIGHT) browse:SetWide(70) browse:SetText('Browse')
                    local entry = row:Add('DTextEntry')
                    entry:Dock(FILL) entry:DockMargin(0, 0, 4, 0) entry:SetValue(tostring(branch[effectKey] or ''))
                    entry.OnValueChange = function(input) setEffect(input:GetValue()) end
                    browse.DoClick = function()
                        self:OpenMaterialPicker(conditionMaterialCallback(setEffect, entry), branch[effectKey])
                    end
                else
                    local shown = type(branch[effectKey]) == 'table' and canonicalJSON(branch[effectKey])
                        or tostring(branch[effectKey] or '')
                    local entry = addEntry(tab, shown, conditionColorCallback(setEffect))
                    entry:DockMargin(24, 1, 8, 2)
                    entry:SetPlaceholderText('Theme token such as @critical, or [r,g,b,a]')
                end
            end
        end
    end

    local advanced = advancedTab:Add('DTextEntry')
    advanced:Dock(FILL) advanced:DockMargin(8, 8, 8, 4) advanced:SetMultiline(true)
    advanced:SetValue(canonicalJSON(working))
    local advancedButtons = advancedTab:Add('DPanel')
    advancedButtons:Dock(BOTTOM) advancedButtons:DockMargin(8, 4, 8, 8) advancedButtons:SetTall(28)
    local refreshJSON = advancedButtons:Add('DButton')
    refreshJSON:Dock(LEFT) refreshJSON:SetWide(190) refreshJSON:SetText('Refresh from structured fields')
    refreshJSON.DoClick = function() advanced:SetValue(canonicalJSON(working)) end
    local loadJSON = advancedButtons:Add('DButton')
    loadJSON:Dock(RIGHT) loadJSON:SetWide(190) loadJSON:SetText('Load JSON into working copy')
    loadJSON.DoClick = function()
        local parsed = util.JSONToTable(advanced:GetValue())
        if type(parsed) ~= 'table' then
            notification.AddLegacy('Condition JSON is invalid.', NOTIFY_ERROR, 3)
            return
        end
        working = parsed
        working.id = tostring(working.id or 'condition')
        working.when = type(working.when) == 'table' and working.when or {provider = '', op = 'truthy'}
        working.apply = type(working.apply) == 'table' and working.apply or {}
        rebuildSource()
        rebuildEffects(trueTab, 'apply')
        rebuildEffects(falseTab, 'otherwise')
        advanced:SetValue(canonicalJSON(working))
    end

    apply.DoClick = function()
        working.id = DISPLAY.NormalizeId(working.id)
        if not working.id then
            notification.AddLegacy('Condition ID is invalid.', NOTIFY_ERROR, 3)
            return
        end
        if type(working.otherwise) == 'table' and not next(working.otherwise) then working.otherwise = nil end
        local trial = DISPLAY.DeepCopy(self.Session.source)
        local trialObject = objectAtSelection(trial, selection)
        local currentObject = objectAtSelection(self.Session.source, selection)
        if not trialObject or not currentObject then
            notification.AddLegacy('The edited object no longer exists.', NOTIFY_ERROR, 3)
            frame:Close()
            return
        end
        trialObject.conditions = type(trialObject.conditions) == 'table' and trialObject.conditions or {}
        if index then trialObject.conditions[index] = DISPLAY.DeepCopy(working)
        else table.insert(trialObject.conditions, DISPLAY.DeepCopy(working)) end
        local compiled, diagnostics = DISPLAY.CompileSource(trial, tostring(self.Session.origin) .. '#condition')
        if not compiled then
            Derma_Message(DISPLAY.DiagnosticsText(diagnostics), 'Condition validation failed', 'OK')
            return
        end
        frame:Close()
        self:Changed(function()
            currentObject.conditions = type(currentObject.conditions) == 'table' and currentObject.conditions or {}
            if index then currentObject.conditions[index] = DISPLAY.DeepCopy(working)
            else table.insert(currentObject.conditions, DISPLAY.DeepCopy(working)) end
        end)
    end

    rebuildSource()
    rebuildEffects(trueTab, 'apply')
    rebuildEffects(falseTab, 'otherwise')
end

function EditorPanel:AddConditionEditor(object)
    local conditions = type(object.conditions) == 'table' and object.conditions or {}
    for index, condition in ipairs(conditions) do
        local row = self:InspectorAdd('DPanel')
        row:Dock(TOP) row:DockMargin(6, 3, 6, 0) row:SetTall(26)
        local remove = row:Add('DButton')
        remove:Dock(RIGHT) remove:SetWide(28) remove:SetText('X') remove:SetTooltip('Delete condition')
        remove.DoClick = function() self:Changed(function() table.remove(object.conditions, index) end) end
        local down = row:Add('DButton')
        down:Dock(RIGHT) down:SetWide(28) down:SetText('v') down:SetEnabled(index < #conditions)
        down:SetTooltip('Move condition later')
        down.DoClick = function()
            self:Changed(function() object.conditions[index], object.conditions[index + 1] = object.conditions[index + 1], object.conditions[index] end)
        end
        local up = row:Add('DButton')
        up:Dock(RIGHT) up:SetWide(28) up:SetText('^') up:SetEnabled(index > 1) up:SetTooltip('Move condition earlier')
        up.DoClick = function()
            self:Changed(function() object.conditions[index], object.conditions[index - 1] = object.conditions[index - 1], object.conditions[index] end)
        end
        local duplicate = row:Add('DButton')
        duplicate:Dock(RIGHT) duplicate:SetWide(42) duplicate:SetText('Copy') duplicate:SetTooltip('Duplicate condition')
        duplicate.DoClick = function()
            self:Changed(function()
                local copy = DISPLAY.DeepCopy(condition)
                local base = DISPLAY.NormalizeId(tostring(copy.id or 'condition') .. '_copy') or 'condition_copy'
                local candidate = base
                local serial = 2
                local used = {}
                for _, existing in ipairs(object.conditions) do used[existing.id] = true end
                while used[candidate] do candidate = base .. '_' .. serial serial = serial + 1 end
                copy.id = candidate
                table.insert(object.conditions, index + 1, copy)
            end)
        end
        local edit = row:Add('DButton')
        edit:Dock(FILL) edit:SetContentAlignment(4) edit:SetText(conditionSummary(condition, index))
        edit:SetTooltip('Open the dedicated condition editor')
        edit.DoClick = function() self:OpenConditionWindow(object, index) end
    end
    local add = self:InspectorAdd('DButton')
    add:Dock(TOP) add:DockMargin(6, 5, 6, 4) add:SetText('Add condition...')
    add.DoClick = function()
        local firstProvider
        for id in SortedPairs(DISPLAY.KnownProviders or {}) do firstProvider = id break end
        local base = 'condition_' .. (#conditions + 1)
        local candidate = base
        local serial = 2
        local used = {}
        for _, condition in ipairs(conditions) do used[condition.id] = true end
        while used[candidate] do candidate = base .. '_' .. serial serial = serial + 1 end
        self:OpenConditionWindow(object, nil, {
            id = candidate,
            when = {provider = firstProvider or '', op = 'truthy'},
            apply = {visible = true}
        })
    end
end

local variableTypes = {'number', 'boolean', 'string', 'enum', 'color'}

local function setVariableType(definition, typeName)
    definition.type = typeName
    definition.min = nil
    definition.max = nil
    definition.decimals = nil
    definition.choices = nil
    if typeName == 'number' then
        definition.default = tonumber(definition.default) or 0
        definition.min = 0
        definition.max = 100
        definition.decimals = 2
    elseif typeName == 'boolean' then definition.default = definition.default and true or false
    elseif typeName == 'string' then definition.default = tostring(definition.default or '')
    elseif typeName == 'enum' then definition.choices = {'option'} definition.default = 'option'
    elseif typeName == 'color' then definition.default = '@text' end
end

function EditorPanel:OpenVariableWindow(source)
    if self.Session.readOnly then
        Derma_Message('Save the packed source as a draft before editing variables.', 'Read-only source', 'OK')
        return
    end
    if IsValid(self.VariableWindow) then self:ActivateSubwindow(self.VariableWindow) return end

    local working = DISPLAY.DeepCopy(type(source.variables) == 'table' and source.variables or {})
    local simulation = DISPLAY.DeepCopy(self.Session.variableSimulation or {})
    for name, definition in pairs(working) do
        if simulation[name] == nil then simulation[name] = DISPLAY.DeepCopy(definition.default) end
    end

    local frame = vgui.Create('DFrame')
    self.VariableWindow = frame
    frame:SetTitle('Exposed Display Variables')
    frame:SetSize(math.min(900, ScrW() - 80), math.min(680, ScrH() - 80))
    frame:SetSizable(true) frame:SetMinWidth(700) frame:SetMinHeight(500)
    self:ActivateSubwindow(frame)
    frame.OnRemove = function() if self.VariableWindow == frame then self.VariableWindow = nil end end

    local bottom = frame:Add('DPanel')
    bottom:Dock(BOTTOM) bottom:DockMargin(8, 4, 8, 8) bottom:SetTall(30)
    local cancel = bottom:Add('DButton')
    cancel:Dock(RIGHT) cancel:SetWide(90) cancel:SetText('Cancel') cancel.DoClick = function() frame:Close() end
    local apply = bottom:Add('DButton')
    apply:Dock(RIGHT) apply:DockMargin(0, 0, 6, 0) apply:SetWide(120) apply:SetText('Apply variables')

    local toolbar = frame:Add('DPanel')
    toolbar:Dock(TOP) toolbar:DockMargin(8, 8, 8, 0) toolbar:SetTall(28)
    local newName = toolbar:Add('DTextEntry')
    newName:Dock(FILL) newName:SetPlaceholderText('New variable ID')
    local add = toolbar:Add('DButton')
    add:Dock(RIGHT) add:DockMargin(6, 0, 0, 0) add:SetWide(75) add:SetText('Add')
    local duplicate = toolbar:Add('DButton')
    duplicate:Dock(RIGHT) duplicate:DockMargin(6, 0, 0, 0) duplicate:SetWide(75) duplicate:SetText('Duplicate')
    local remove = toolbar:Add('DButton')
    remove:Dock(RIGHT) remove:DockMargin(6, 0, 0, 0) remove:SetWide(70) remove:SetText('Delete')

    local body = frame:Add('DHorizontalDivider')
    body:Dock(FILL) body:DockMargin(8, 6, 8, 0) body:SetLeftWidth(300) body:SetDividerWidth(5)
    local list = body:Add('DListView')
    list:AddColumn('Variable') list:AddColumn('Type') list:AddColumn('Default')
    body:SetLeft(list)
    local inspector = body:Add('DScrollPanel')
    body:SetRight(inspector)
    local selectedName
    local rebuildingList = false

    local function addLabel(text)
        local label = inspector:Add('DLabel')
        label:Dock(TOP) label:DockMargin(8, 6, 8, 0) label:SetTall(18) label:SetText(text)
        return label
    end
    local function addEntry(value, callback)
        local entry = inspector:Add('DTextEntry')
        entry:Dock(TOP) entry:DockMargin(8, 1, 8, 2) entry:SetTall(24) entry:SetValue(tostring(value or ''))
        entry.OnValueChange = function(input) callback(input:GetValue()) end
        return entry
    end
    local function addCombo(value, choices, callback)
        local combo = inspector:Add('DComboBox')
        combo:Dock(TOP) combo:DockMargin(8, 1, 8, 2) combo:SetTall(24) combo:SetValue(tostring(value or ''))
        for _, choice in ipairs(choices or {}) do combo:AddChoice(tostring(choice), choice) end
        combo.OnSelect = function(_, _, _, selected) callback(selected) end
        return combo
    end
    local function addNumber(value, minimum, maximum, decimals, callback)
        local number = inspector:Add('DNumberWang')
        number:Dock(TOP) number:DockMargin(8, 1, 8, 2) number:SetTall(24)
        number:SetMinMax(minimum, maximum) number:SetDecimals(decimals or 2) number:SetValue(tonumber(value) or 0)
        number.OnValueChanged = function(input) callback(tonumber(input:GetValue()) or 0) end
        return number
    end
    local function addBoolean(labelText, value, callback)
        local box = inspector:Add('DCheckBoxLabel')
        box:Dock(TOP) box:DockMargin(8, 6, 8, 2) box:SetText(labelText)
        box:SetValue(value and 1 or 0) box:SizeToContents()
        box.OnChange = function(_, checked) callback(checked and true or false) end
        return box
    end
    local function addVariableColor(labelText, values, key, callback)
        addLabel(labelText)
        local row = inspector:Add('DPanel')
        row:Dock(TOP) row:DockMargin(8, 1, 8, 2) row:SetTall(24)
        local edit = row:Add('DButton')
        edit:Dock(RIGHT) edit:SetWide(70) edit:SetText('RGBA...')
        local combo = row:Add('DComboBox')
        combo:Dock(FILL) combo:DockMargin(0, 0, 4, 0)
        local current = values[key]
        combo:SetValue(type(current) == 'table' and canonicalJSON(current) or tostring(current or '@text'))
        for _, token in ipairs(self:ThemeTokens()) do combo:AddChoice('@' .. token, '@' .. token) end
        combo.OnSelect = function(_, _, _, value) values[key] = value callback(value) end
        edit.DoClick = function()
            self:OpenColorPicker(values, key, function(value)
                values[key] = DISPLAY.DeepCopy(value)
                callback(value)
            end)
        end
    end

    local rebuildList
    local rebuildInspector
    rebuildList = function()
        rebuildingList = true
        list:Clear()
        local selectedLine
        for name, definition in SortedPairs(working) do
            local shownDefault = type(definition.default) == 'table' and util.TableToJSON(definition.default, false)
                or tostring(definition.default)
            local line = list:AddLine(name, tostring(definition.type or 'number'), shownDefault)
            line.VariableName = name
            if name == selectedName then selectedLine = line end
        end
        if selectedLine then list:SelectItem(selectedLine) end
        rebuildingList = false
    end
    local function chooseUnusedName(preferred)
        local base = DISPLAY.NormalizeId(preferred) or 'variable'
        local candidate = base
        local serial = 2
        while working[candidate] do candidate = base .. '_' .. serial serial = serial + 1 end
        return candidate
    end

    rebuildInspector = function()
        clearScrollPanel(inspector)
        local definition = selectedName and working[selectedName]
        duplicate:SetEnabled(definition ~= nil) remove:SetEnabled(definition ~= nil)
        if not definition then
            addLabel('Select a variable, or enter a new ID above.')
            return
        end

        addLabel('Variable ID')
        local renameRow = inspector:Add('DPanel')
        renameRow:Dock(TOP) renameRow:DockMargin(8, 1, 8, 2) renameRow:SetTall(24)
        local renameButton = renameRow:Add('DButton')
        renameButton:Dock(RIGHT) renameButton:SetWide(70) renameButton:SetText('Rename')
        local rename = renameRow:Add('DTextEntry')
        rename:Dock(FILL) rename:DockMargin(0, 0, 4, 0) rename:SetValue(selectedName)
        renameButton.DoClick = function()
            local normalized = DISPLAY.NormalizeId(rename:GetValue())
            if not normalized or (normalized ~= selectedName and working[normalized]) then
                notification.AddLegacy('Variable ID is invalid or already used.', NOTIFY_ERROR, 3)
                return
            end
            if normalized ~= selectedName then
                working[normalized] = definition working[selectedName] = nil
                simulation[normalized] = simulation[selectedName] simulation[selectedName] = nil
                selectedName = normalized
                rebuildList() rebuildInspector()
            end
        end

        addLabel('Label')
        addEntry(definition.label, function(value) definition.label = value ~= '' and value or nil end)
        addLabel('Type')
        addCombo(definition.type or 'number', variableTypes, function(typeName)
            setVariableType(definition, typeName)
            simulation[selectedName] = DISPLAY.DeepCopy(definition.default)
            rebuildList() rebuildInspector()
        end)

        local typeName = definition.type or 'number'
        if typeName == 'number' then
            addLabel('Default')
            addNumber(definition.default, -1000000000, 1000000000, 3, function(value) definition.default = value end)
            addLabel('Minimum')
            addNumber(definition.min, -1000000000, 1000000000, 3, function(value) definition.min = value end)
            addLabel('Maximum')
            addNumber(definition.max, -1000000000, 1000000000, 3, function(value) definition.max = value end)
            addLabel('Decimals')
            addNumber(definition.decimals, 0, 8, 0, function(value) definition.decimals = math.floor(value) end)
        elseif typeName == 'boolean' then
            addBoolean('Default value', definition.default, function(value) definition.default = value end)
        elseif typeName == 'string' then
            addLabel('Default')
            addEntry(definition.default, function(value) definition.default = value end)
        elseif typeName == 'enum' then
            addLabel('Choices (comma separated)')
            local choices = addEntry(table.concat(definition.choices or {}, ', '), function() end)
            local applyChoices = inspector:Add('DButton')
            applyChoices:Dock(TOP) applyChoices:DockMargin(8, 1, 8, 3) applyChoices:SetTall(23) applyChoices:SetText('Apply choices')
            applyChoices.DoClick = function()
                local values = {}
                for value in string.gmatch(choices:GetValue(), '[^,]+') do
                    value = string.Trim(value)
                    if value ~= '' and not table.HasValue(values, value) then table.insert(values, value) end
                end
                if #values == 0 then
                    notification.AddLegacy('An enum requires at least one choice.', NOTIFY_ERROR, 3)
                    return
                end
                definition.choices = values
                if not table.HasValue(values, definition.default) then definition.default = values[1] end
                if not table.HasValue(values, simulation[selectedName]) then simulation[selectedName] = definition.default end
                rebuildList() rebuildInspector()
            end
            addLabel('Default')
            addCombo(definition.default, definition.choices, function(value) definition.default = value end)
        elseif typeName == 'color' then
            addVariableColor('Default color', definition, 'default', function() rebuildList() rebuildInspector() end)
        end

        addLabel('Editor simulation (not saved in source)')
        local simulated = simulation[selectedName]
        if typeName == 'number' then
            addNumber(simulated, definition.min or -1000000000, definition.max or 1000000000,
                definition.decimals or 2, function(value) simulation[selectedName] = value end)
        elseif typeName == 'boolean' then
            addBoolean('Simulated value', simulated, function(value) simulation[selectedName] = value end)
        elseif typeName == 'enum' then
            addCombo(simulated or definition.default, definition.choices, function(value) simulation[selectedName] = value end)
        elseif typeName == 'color' then
            addVariableColor('Simulated color', simulation, selectedName, function() rebuildInspector() end)
        else
            addEntry(simulated, function(value) simulation[selectedName] = value end)
        end
    end

    list.OnRowSelected = function(_, _, line)
        if rebuildingList then return end
        selectedName = line.VariableName
        rebuildInspector()
    end
    add.DoClick = function()
        local name = DISPLAY.NormalizeId(newName:GetValue())
        if not name or working[name] then
            notification.AddLegacy('Variable ID is invalid or already used.', NOTIFY_ERROR, 3)
            return
        end
        working[name] = {type = 'number', default = 0, min = 0, max = 100, decimals = 2}
        simulation[name] = 0 selectedName = name newName:SetValue('')
        rebuildList() rebuildInspector()
    end
    newName.OnEnter = function() add:DoClick() end
    duplicate.DoClick = function()
        if not selectedName or not working[selectedName] then return end
        local name = chooseUnusedName(selectedName .. '_copy')
        working[name] = DISPLAY.DeepCopy(working[selectedName])
        simulation[name] = DISPLAY.DeepCopy(simulation[selectedName])
        selectedName = name rebuildList() rebuildInspector()
    end
    remove.DoClick = function()
        if not selectedName then return end
        working[selectedName] = nil simulation[selectedName] = nil selectedName = next(working)
        rebuildList() rebuildInspector()
    end
    apply.DoClick = function()
        local trial = DISPLAY.DeepCopy(self.Session.source)
        trial.variables = DISPLAY.DeepCopy(working)
        local compiled, diagnostics = DISPLAY.CompileSource(trial, tostring(self.Session.origin) .. '#variables')
        if not compiled then
            Derma_Message(DISPLAY.DiagnosticsText(diagnostics), 'Variable validation failed', 'OK')
            return
        end
        frame:Close()
        self:Changed(function()
            source.variables = DISPLAY.DeepCopy(working)
            self.Session.variableSimulation = DISPLAY.DeepCopy(simulation)
        end)
    end

    selectedName = next(working)
    rebuildList()
    rebuildInspector()
end

function EditorPanel:AddVariableEditor(source)
    local variables = type(source.variables) == 'table' and source.variables or {}
    local count = table.Count(variables)
    self:AddInspectorLabel(string.format('%d exposed variable%s configured.', count, count == 1 and '' or 's'))
    for name, definition in SortedPairs(variables) do
        self:AddInspectorLabel(string.format('%s [%s]', name, tostring(definition.type or 'unknown')))
    end
    local manage = self:InspectorAdd('DButton')
    manage:Dock(TOP) manage:DockMargin(6, 5, 6, 4) manage:SetText('Manage exposed variables...')
    manage.DoClick = function() self:OpenVariableWindow(source) end
end

function EditorPanel:AddAnimationEditor(object, elementType)
    self:AddBoolField('Disable all animation', object, 'animationDisabled', false)
    local page = activePageSource(self.Session)
    local animationKey = tostring(page and page.id or 'simple') .. ':' .. tostring(object.id)
    local preview = self:InspectorAdd('DCheckBoxLabel')
    preview:Dock(TOP) preview:DockMargin(6, 5, 6, 0)
    preview:SetText('Preview animation in editor')
    preview:SetValue(self.Session.animationPreview[animationKey] == false and 0 or 1)
    preview:SizeToContents()
    preview.OnChange = function(_, enabled)
        self.Session.animationPreview[animationKey] = enabled and true or false
        if IsValid(self.PreviewCanvas) then self.PreviewCanvas:InvalidateLayout(true) end
    end
    self:AddInspectorLabel('Flash below 0.02 seconds and frames below 0.20 seconds are disabled.')
    self:AddBoolField('Enable flashing', object, 'flashEnabled', true)
    self:AddNumberField('Flash half-cycle seconds', object, 'flashSeconds', 0, 60, 2, 0)
    if elementType == 'material' then
        self:AddBoolField('Enable frame animation', object, 'frameAnimationEnabled', true)
        self:AddNumberField('Seconds per frame', object, 'frameSeconds', 0, 60, 2, 0)
        self:AddBoolField('Loop frames (off holds final frame)', object, 'loop', true)
        self:AddFrameEditor(object)
        self:AddNumberField('Static rotation (degrees)', object, 'rotationDegrees', -360000, 360000, 2, 0)
        self:AddBoolField('Enable animated rotation', object, 'rotationAnimationEnabled', true)
        self:AddNumberField('Rotation speed (degrees/second)', object, 'rotationSpeedDegreesPerSecond', -10000, 10000, 2, 0)
        self:AddNumberField('Animation epoch (server seconds)', object, 'animationEpoch', -1000000000, 1000000000, 3, 0)
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
    feature('Text color', kind == 'line' and 'color' or 'textColor', '@text')
    feature('Background color', 'backgroundColor', '@panel')
    feature('Border color', 'borderColor', '@border')
    feature('Flash animation', 'flashSeconds', 0.25)
    feature('Conditions', 'conditions', {})
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
    local button = self:InspectorAdd('DButton')
    button:Dock(TOP) button:DockMargin(6, 7, 6, 0) button:SetText('Add feature...')
    button.DoClick = function() self:AddFeatureMenu(object, kind) end
end

function EditorPanel:RebuildInspectorLegacy()
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
            local clearPixelSize = self:InspectorAdd('DButton')
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
        local mode = self:InspectorAdd('DComboBox')
        mode:Dock(TOP) mode:DockMargin(6, 7, 6, 0) mode:SetValue(object.buildMode or 'simple')
        mode:AddChoice('simple', 'simple') mode:AddChoice('complex', 'complex')
        mode.OnSelect = function(_, _, _, value)
            self:Changed(function()
                object.buildMode = value
                if value == 'simple' then object.lines = object.lines or {}
                else object.pages = object.pages or {{id = 'overview', label = 'Overview', elements = {}}} end
            end)
        end
        local addPage = self:InspectorAdd('DButton')
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
        local selectButton = self:InspectorAdd('DButton')
        selectButton:Dock(TOP) selectButton:DockMargin(6, 8, 6, 0) selectButton:SetText('Show this page')
        selectButton.DoClick = function() self.Session.activePage = selection.page self:Compile() end
        local add = self:InspectorAdd('DButton')
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
            local addLine = self:InspectorAdd('DButton')
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
        local row = self:InspectorAdd('DPanel')
        row:Dock(TOP) row:DockMargin(6, 5, 6, 0) row:SetTall(24)
        for _, direction in ipairs({-1, 1}) do
            local button = row:Add('DButton')
            button:Dock(direction < 0 and LEFT or RIGHT) button:SetWide(80)
            button:SetText(direction < 0 and 'Move up' or 'Move down')
            button.DoClick = function() self:MoveLine(direction) end
        end
    end
    if selection.kind ~= 'display' then
        local remove = self:InspectorAdd('DButton')
        remove:Dock(TOP) remove:DockMargin(6, 10, 6, 6) remove:SetText('Delete selected')
        remove.DoClick = function() self:DeleteSelection() end
    end
end

function EditorPanel:RebuildInspector()
    clearScrollPanel(self.Inspector)
    self.InspectorTarget = nil
    self.CanvasMetricsLabel = nil
    local object = selectionObject(self.Session)
    if not object then self:AddInspectorLabel('Nothing selected.') return end
    local selection = self.Session.selection
    local kind = selection.kind
    self:AddInspectorLabel(string.upper(kind) .. (self.Session.readOnly and ' · READ ONLY' or ''))

    if kind == 'display' then
        self:BeginInspectorCategory('General', 'display.general', true)
        self:AddTextField('Display ID', object, 'id')
        self:AddTextField('Targetname', object, 'target')
        self:AddTextField('Theme group', object, 'themeGroup')
        local mode = self:InspectorAdd('DComboBox')
        mode:Dock(TOP) mode:DockMargin(6, 7, 6, 0) mode:SetValue(object.buildMode or 'simple')
        mode:AddChoice('Simple', 'simple') mode:AddChoice('Complex', 'complex')
        mode.OnSelect = function(_, _, _, value)
            self:Changed(function()
                object.buildMode = value
                if value == 'simple' then object.lines = object.lines or {}
                else object.pages = object.pages or {{id = 'overview', label = 'Overview', elements = {}}} end
            end)
        end
        local addPage = self:InspectorAdd('DButton')
        addPage:Dock(TOP) addPage:DockMargin(6, 4, 6, 3) addPage:SetText('Add complex page')
        addPage.DoClick = function()
            self:Changed(function()
                object.buildMode = 'complex' object.pages = object.pages or {}
                table.insert(object.pages, {id = 'page_' .. (#object.pages + 1), label = 'Page ' .. (#object.pages + 1), elements = {}})
                self.Session.activePage = #object.pages
                self.Session.selection = {kind = 'page', page = #object.pages}
            end)
        end
        self:EndInspectorCategory()

        self:BeginInspectorCategory('Canvas', 'display.canvas', true)
        local parsed = DISPLAY.ParseTargetMetrics(object.target) or {}
        local compiled = self.Session.compiled or {}
        self:AddNumberField('Canvas width (Hammer units)', object, 'unitWidth', 0.01, 100000, 2,
            object.unitWidth or object.hammerWidth or parsed.unitWidth or compiled.unitWidth)
        self:AddNumberField('Canvas height (Hammer units)', object, 'unitHeight', 0.01, 100000, 2,
            object.unitHeight or object.hammerHeight or parsed.unitHeight or compiled.unitHeight)
        self:AddNumberField('Scale (HU per canvas pixel)', object, 'scale', 0.001, 10, 3, compiled.scale)
        self.CanvasMetricsLabel = self:AddInspectorLabel('') self:UpdateCanvasMetricsLabel()
        self:AddBoolField('Show page switching tabs', object, 'showPageTabs', true)
        if object.width ~= nil or object.height ~= nil then
            local clear = self:InspectorAdd('DButton') clear:Dock(TOP) clear:DockMargin(6, 3, 6, 3)
            clear:SetText('Remove explicit pixel-size override')
            clear.DoClick = function() self:Changed(function() object.width = nil object.height = nil end) end
        end
        self:EndInspectorCategory()

        self:BeginInspectorCategory('Appearance', 'display.appearance', true)
        self:AddColorField('Default text color', object, 'textColor', true)
        self:AddColorField('Title color', object, 'titleColor', true)
        self:AddColorField('Background color', object, 'backgroundColor', true)
        self:AddColorField('Border color', object, 'borderColor', true)
        self:AddColorField('Accent / bar color', object, 'barColor', true)
        self:EndInspectorCategory()

        self:BeginInspectorCategory('Interaction', 'display.interaction', false)
        object.interaction = type(object.interaction) == 'table' and object.interaction or {}
        self:AddBoolField('Enable raycast interaction', object.interaction, 'enabled', false)
        self:AddNumberField('Maximum distance', object.interaction, 'distance', 16, 4096, 0, 128)
        self:AddNumberField('Field of view', object.interaction, 'fov', 1, 180, 1, 30)
        self:AddBoolField('Require line of sight', object.interaction, 'lineOfSight', true)
        self:EndInspectorCategory()

        self:BeginInspectorCategory('Variables', 'display.variables', false)
        self:AddVariableEditor(object)
        self:EndInspectorCategory()
        self:BeginInspectorCategory('Advanced', 'display.advanced', false)
        self:AddJSONField('Interaction extensions', object, 'interaction')
        self:AddJSONField('Variable definitions', object, 'variables')
        self:EndInspectorCategory()
    elseif kind == 'page' then
        self:BeginInspectorCategory('Page', 'page.general', true)
        self:AddTextField('Page ID', object, 'id') self:AddTextField('Tab label', object, 'label')
        local show = self:InspectorAdd('DButton') show:Dock(TOP) show:DockMargin(6, 5, 6, 0) show:SetText('Show this page')
        show.DoClick = function() self.Session.activePage = selection.page self:Compile() end
        local add = self:InspectorAdd('DButton') add:Dock(TOP) add:DockMargin(6, 4, 6, 4) add:SetText('Add element')
        add.DoClick = function() self:AddElementMenu() end
        self:EndInspectorCategory()
    elseif kind == 'element' then
        local elementType = normalizedElementType(object.type)
        self:BeginInspectorCategory('Layout', 'element.layout', true)
        self:AddTextField('Element ID', object, 'id')
        self:AddNumberField('X', object, 'x', -10000, 10000, 0)
        self:AddNumberField('Y', object, 'y', -10000, 10000, 0)
        self:AddNumberField('Width', object, 'width', 1, 32768, 0)
        self:AddNumberField('Height', object, 'height', 1, 32768, 0)
        self:AddNumberField('Layer (z)', object, 'z', -1000, 1000, 0)
        self:EndInspectorCategory()

        self:BeginInspectorCategory('Content', 'element.content', true)
        if elementType == 'material' then self:AddMaterialField('Material path', object, 'material')
        elseif elementType == 'line_panel' then
            self:AddTextField('Panel title', object, 'title')
            self:AddNumberField('Line height', object, 'lineHeight', 1, 4096, 0, self.Session.source.lineHeight or 16)
            self:AddNumberField('Padding', object, 'padding', 0, 4096, 0, 6)
            local addLine = self:InspectorAdd('DButton') addLine:Dock(TOP) addLine:DockMargin(6, 4, 6, 0) addLine:SetText('Add line')
            addLine.DoClick = function() self:Changed(function() object.lines = object.lines or {} table.insert(object.lines, {type = 'value', label = 'VALUE', value = 0}) end) end
        elseif elementType == 'annunciator' then
            self:AddTextField('Alarm ID', object, 'alarm') self:AddTextField('Label', object, 'label')
        end
        self:EndInspectorCategory()

        self:BeginInspectorCategory('Appearance', 'element.appearance', true)
        if elementType == 'material' then self:AddColorField('Material tint', object, 'tint', true)
        elseif elementType == 'line_panel' then
            self:AddBoolField('Draw background', object, 'drawBackground', true)
            self:AddBoolField('Draw border', object, 'drawBorder', true)
            self:AddColorField('Panel background', object, 'backgroundColor', true)
            self:AddColorField('Panel border', object, 'borderColor', true)
            self:AddColorField('Panel title color', object, 'titleColor', true)
            if object.backgroundMaterial ~= nil then self:AddMaterialField('Background material', object, 'backgroundMaterial') end
        elseif elementType == 'solid_rectangle' then self:AddColorField('Rectangle color', object, 'color', false)
        elseif elementType == 'annunciator' then
            self:AddColorField('Text color', object, 'textColor', true)
            self:AddColorField('Background color', object, 'backgroundColor', true)
        end
        self:EndInspectorCategory()

        self:BeginInspectorCategory('Visual Animation', 'element.animation', false)
        self:AddAnimationEditor(object, elementType)
        self:EndInspectorCategory()
        self:BeginInspectorCategory('Data & Actions', 'element.data', false)
        self:AddActionFields(object) self:AddFeatureButton(object, 'element')
        self:EndInspectorCategory()
        self:BeginInspectorCategory('Conditions', 'element.conditions', false)
        self:AddConditionEditor(object)
        self:EndInspectorCategory()
        self:BeginInspectorCategory('Advanced', 'element.advanced', false)
        self:AddJSONField('Conditions', object, 'conditions')
        self:AddJSONField('Action payload', object, 'actionPayload')
        self:EndInspectorCategory()
    elseif kind == 'line' then
        self:BeginInspectorCategory('Content', 'line.content', true)
        self:AddChoiceField('Line type', object, 'type', {'text', 'value', 'bar', 'phase', 'graph', 'columns'}, 'text')
        self:AddTextField('Label / text', object, object.type == 'text' and 'text' or 'label')
        if object.type == 'value' or object.type == 'bar' or object.type == 'phase' or object.type == 'graph' then
            self:AddNumberField('Decimals', object, 'decimals', 0, 8, 0, 0) self:AddTextField('Unit', object, 'unit')
        end
        self:EndInspectorCategory()
        self:BeginInspectorCategory('Data Binding', 'line.data', true)
        self:AddBindingField('Value binding', object, 'value')
        if object.type == 'bar' then self:AddBindingField('Fraction binding', object, 'fraction') end
        self:EndInspectorCategory()
        self:BeginInspectorCategory('Appearance', 'line.appearance', true)
        self:AddColorField('Line text color', object, 'color', true)
        if object.type == 'bar' then self:AddColorField('Bar fill', object, 'fillColor', true) end
        self:EndInspectorCategory()
        self:BeginInspectorCategory('Type Settings', 'line.type_settings', true)
        if object.type == 'bar' then self:AddNumberField('Bar height', object, 'height', 1, 4096, 0, 8)
        elseif object.type == 'phase' then
            self:AddNumberField('Minimum', object, 'min', -100000, 100000, 2, -180)
            self:AddNumberField('Maximum', object, 'max', -100000, 100000, 2, 180)
        elseif object.type == 'graph' then
            self:AddNumberField('Graph height', object, 'height', 1, 4096, 0, 90)
            self:AddNumberField('History seconds', object, 'seconds', 0.1, 3600, 1, 60)
            self:AddBoolField('Show X axis', object, 'showXAxis', true) self:AddBoolField('Show Y axis', object, 'showYAxis', true)
        elseif object.type == 'columns' then
            self:AddNumberField('Column height', object, 'height', 1, 4096, 0, 56)
            self:AddNumberField('Column gap', object, 'columnsGap', 0, 4096, 0, 6)
        end
        self:EndInspectorCategory()
        self:BeginInspectorCategory('Conditions', 'line.conditions', false)
        self:AddConditionEditor(object)
        self:EndInspectorCategory()
        self:BeginInspectorCategory('Advanced', 'line.advanced', false)
        self:AddJSONField('Conditions', object, 'conditions')
        if object.type == 'graph' then self:AddJSONField('Graph series', object, 'series') end
        if object.type == 'columns' then self:AddJSONField('Columns', object, 'columns') end
        self:EndInspectorCategory()
        local row = self:InspectorAdd('DPanel') row:Dock(TOP) row:DockMargin(6, 5, 6, 0) row:SetTall(24)
        for _, direction in ipairs({-1, 1}) do
            local button = row:Add('DButton') button:Dock(direction < 0 and LEFT or RIGHT) button:SetWide(80)
            button:SetText(direction < 0 and 'Move up' or 'Move down') button.DoClick = function() self:MoveLine(direction) end
        end
    end
    self.InspectorTarget = nil
    if kind ~= 'display' then
        local remove = self.Inspector:Add('DButton') remove:Dock(TOP) remove:DockMargin(6, 10, 6, 6)
        remove:SetText('Delete selected') remove.DoClick = function() self:DeleteSelection() end
    end
end

-- Keep the old method name as a compatibility alias without retaining the
-- obsolete variant inspector behavior.
EditorPanel.RebuildInspectorLegacy = EditorPanel.RebuildInspector

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
        DISPLAY.DrawDisplayCanvas(compiled, {
            animationPreview = self.Session.animationPreview,
            variableValues = self.Session.variableSimulation
        })
        DISPLAY.ClientState.ThemeState[group] = previous
        DISPLAY.ClientState.ThemePacks[group] = previousPack
        local selected = selectionObject(self.Session)
        if self.Session.selection and self.Session.selection.kind == 'element' and selected then
            surface.SetDrawColor(255, 220, 70, 255)
            surface.DrawOutlinedRect(selected.x or 0, selected.y or 0, selected.width or 1, selected.height or 1, 2)
            local handleSize = math.max(8 / math.max(scale, 0.001), 2)
            surface.DrawRect(
                (selected.x or 0) + (selected.width or 1) - handleSize * 0.5,
                (selected.y or 0) + (selected.height or 1) - handleSize * 0.5,
                handleSize,
                handleSize
            )
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

function EditorPanel:SelectedElementPriority(x, y)
    local selection = self.Session.selection
    if not selection or selection.kind ~= 'element' or selection.page ~= self.Session.activePage then return nil end
    local element = selectionObject(self.Session)
    if not element then return nil end
    local scale = self:CanvasTransform(self.PreviewCanvas)
    local handleTolerance = 10 / math.max(scale, 0.001)
    local borderTolerance = 5 / math.max(scale, 0.001)
    local left = tonumber(element.x) or 0
    local top = tonumber(element.y) or 0
    local width = tonumber(element.width or element.w) or 64
    local height = tonumber(element.height or element.h) or 32
    local right = left + width
    local bottom = top + height
    if math.abs(x - right) <= handleTolerance and math.abs(y - bottom) <= handleTolerance then
        return 'resize', element
    end
    local insideExpanded = x >= left - borderTolerance and x <= right + borderTolerance
        and y >= top - borderTolerance and y <= bottom + borderTolerance
    local nearBorder = math.abs(x - left) <= borderTolerance or math.abs(x - right) <= borderTolerance
        or math.abs(y - top) <= borderTolerance or math.abs(y - bottom) <= borderTolerance
    if insideExpanded and nearBorder then return 'move', element end
    return nil
end

function EditorPanel:BeginElementDrag(element, x, y, resize)
    if self.Session.readOnly or not element then return end
    local elementX = tonumber(element.x) or 0
    local elementY = tonumber(element.y) or 0
    local elementWidth = tonumber(element.width or element.w) or 64
    local elementHeight = tonumber(element.height or element.h) or 32
    element.x = elementX element.y = elementY
    element.width = elementWidth element.height = elementHeight
    self.Drag = {
        element = element,
        x = x,
        y = y,
        startX = elementX,
        startY = elementY,
        width = elementWidth,
        height = elementHeight,
        resize = resize and true or false,
        moved = false,
        before = snapshot(self.Session),
        historyRecorded = false
    }
end

function EditorPanel:CanvasHits(x, y)
    local page = activePageSource(self.Session)
    local hits = {}
    for index, source in ipairs(page and page.elements or {}) do
        local resolved = DISPLAY.ApplyConditions(
            source,
            DISPLAY.ClientState.Providers or {},
            self.Session.variableSimulation or {}
        )
        resolved.x = tonumber(resolved.x) or 0
        resolved.y = tonumber(resolved.y) or 0
        resolved.width = tonumber(resolved.width or resolved.w) or 64
        resolved.height = tonumber(resolved.height or resolved.h) or 32
        resolved.type = normalizedElementType(resolved.type)
        local previewKey = tostring(page and page.id or 'simple') .. ':' .. tostring(resolved.id)
        local previewAnimations = self.Session.animationPreview[previewKey] ~= false
        if resolved.visible ~= false and DISPLAY.PointInElement(
            x,
            y,
            resolved,
            DISPLAY.GetSynchronizedTime(),
            previewAnimations
        ) then
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
    self:SetSelection(selection, true, true)
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
    local priority, priorityElement = self:SelectedElementPriority(x, y)
    if priority then
        self.Session.hitCycle = nil
        panel:MouseCapture(true)
        self:BeginElementDrag(priorityElement, x, y, priority == 'resize')
        return
    end
    local selection = self:SelectCanvasHit(x, y, self:CanvasHits(x, y))
    if not selection then return end
    local element = page.elements[selection.element]
    panel:MouseCapture(true)
    self:BeginElementDrag(element, x, y, false)
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
    local x, y = self:CanvasPoint(panel, cursorX, cursorY)
    if not drag then
        local priority = self:SelectedElementPriority(x, y)
        panel:SetCursor(priority == 'resize' and 'sizenwse' or (priority == 'move' and 'sizeall' or 'arrow'))
        return
    end
    local dx, dy = x - drag.x, y - drag.y
    if math.abs(dx) > 0.25 or math.abs(dy) > 0.25 then
        drag.moved = true
    end
    if not drag.moved then return end
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
        local finalWidth = math.max(snappedX - drag.element.x, 1)
        local finalHeight = math.max(snappedY - drag.element.y, 1)
        if finalWidth == drag.element.width and finalHeight == drag.element.height then return end
        if not drag.historyRecorded then
            pushHistoryValue(self.Session, drag.before)
            drag.historyRecorded = true
        end
        drag.element.width = finalWidth
        drag.element.height = finalHeight
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
        if snappedX == drag.element.x and snappedY == drag.element.y then return end
        if not drag.historyRecorded then
            pushHistoryValue(self.Session, drag.before)
            drag.historyRecorded = true
        end
        drag.element.x = snappedX
        drag.element.y = snappedY
        if guideX then table.insert(self.SnapGuides, {axis = 'x', value = guideX}) end
        if guideY then table.insert(self.SnapGuides, {axis = 'y', value = guideY}) end
    end
    drag.changed = true
    self.Session.dirty = true
    self:Compile()
end

function EditorPanel:OnClose()
    EDITOR.Frame = nil
end

function EditorPanel:Close()
    if self._closeApproved then
        for frame in pairs(self.Subwindows or {}) do
            if IsValid(frame) then frame:Remove() end
        end
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
