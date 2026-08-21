if not CLIENT then return end

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
local DISPLAY = LUASQUARE_3D2D
local EDITOR = DISPLAY.Editor or {}
DISPLAY.Editor = EDITOR

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
        compiled = nil
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
    self.SourcePicker.OnSelect = function(_, _, _, data) self:OpenEntry(data) end

    local function toolButton(label, callback, width)
        local button = self.Toolbar:Add('DButton')
        button:Dock(LEFT)
        button:DockMargin(4, 0, 0, 0)
        button:SetWide(width or 68)
        button:SetText(label)
        button.DoClick = callback
        return button
    end
    self.NewButton = toolButton('New', function() self:ReplaceSource(defaultSource(), 'New source', false) end, 54)
    self.SaveButton = toolButton('Save draft', function() self:SaveDraft() end, 80)
    self.UndoButton = toolButton('Undo', function() self:Undo() end, 54)
    self.RedoButton = toolButton('Redo', function() self:Redo() end, 54)
    self.ValidateButton = toolButton('Validate', function()
        self:Compile()
        local diagnostics = DISPLAY.DiagnosticsText(self.Session.diagnostics)
        Derma_Message(diagnostics ~= '' and diagnostics or 'Source is valid.', 'Display validation', 'OK')
    end, 65)

    self.TargetPicker = self.Toolbar:Add('DComboBox')
    self.TargetPicker:Dock(RIGHT)
    self.TargetPicker:SetWide(180)
    self.TargetPicker:SetValue('Runtime display')
    self.ThemePicker = self.Toolbar:Add('DComboBox')
    self.ThemePicker:Dock(RIGHT)
    self.ThemePicker:DockMargin(4, 0, 0, 0)
    self.ThemePicker:SetWide(125)
    self.ThemePicker:SetValue('Theme preview')
    self.ThemePicker.OnSelect = function(_, _, _, themeId)
        self.Session.themeSimulation = themeId
    end
    self.ClearButton = self.Toolbar:Add('DButton')
    self.ClearButton:Dock(RIGHT)
    self.ClearButton:DockMargin(4, 0, 0, 0)
    self.ClearButton:SetWide(76)
    self.ClearButton:SetText('Restore')
    self.ClearButton.DoClick = function()
        local _, target = self.TargetPicker:GetSelected()
        if target then EDITOR.ClearPreview(target) end
    end
    self.PreviewButton = self.Toolbar:Add('DButton')
    self.PreviewButton:Dock(RIGHT)
    self.PreviewButton:DockMargin(4, 0, 0, 0)
    self.PreviewButton:SetWide(76)
    self.PreviewButton:SetText('Preview')
    self.PreviewButton.DoClick = function() self:Preview() end

    self.Body = self:Add('DHorizontalDivider')
    self.Body:Dock(FILL)
    self.Body:SetLeftWidth(245)
    self.Body:SetDividerWidth(5)

    self.HierarchyPanel = self.Body:Add('DPanel')
    self.HierarchyPanel:DockPadding(4, 4, 4, 4)
    self.Hierarchy = self.HierarchyPanel:Add('DTree')
    self.Hierarchy:Dock(FILL)
    self.Hierarchy.OnNodeSelected = function(_, node)
        if node.Selection then self.Session.selection = node.Selection self:RebuildInspector() end
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
        self.Drag = nil
        self.SnapGuides = nil
        self:Compile()
        self:RebuildHierarchy()
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
    self.SourcePicker:Clear()
    for _, entry in ipairs(listSources()) do self.SourcePicker:AddChoice(entry.label, entry) end
    self.TargetPicker:Clear()
    for _, display in ipairs((DISPLAY.ClientState or {}).Displays or {}) do
        self.TargetPicker:AddChoice(display.id, display.id)
    end
end

function EditorPanel:RefreshThemes()
    if not IsValid(self.ThemePicker) then return end
    self.ThemePicker:Clear()
    local group = self.Session.compiled and self.Session.compiled.themeGroup or self.Session.source.themeGroup or 'default'
    local pack = (DISPLAY.ClientState.ThemePacks or {})[group]
    for themeId in pairs(pack and pack.themes or {}) do self.ThemePicker:AddChoice(themeId, themeId) end
end

function EditorPanel:OpenEntry(entry)
    if self.Session.dirty then
        Derma_Query('Discard unsaved editor changes?', 'Unsaved source', 'Discard', function()
            local source, message = readSource(entry)
            if source then self:ReplaceSource(source, entry.path, entry.readOnly) else Derma_Message(message, 'Open failed', 'OK') end
        end, 'Cancel')
        return
    end
    local source, message = readSource(entry)
    if source then self:ReplaceSource(source, entry.path, entry.readOnly) else Derma_Message(message, 'Open failed', 'OK') end
end

function EditorPanel:ReplaceSource(source, origin, readOnly)
    self.Session = makeSession()
    self.Session.source = DISPLAY.DeepCopy(source)
    self.Session.origin = origin
    self.Session.readOnly = readOnly and true or false
    self.Session.activePage = 1
    self.Session.selection = {kind = 'display'}
    self:Compile()
    self:RebuildHierarchy()
    self:RebuildInspector()
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

function EditorPanel:Preview()
    if not self:Compile() then
        Derma_Message(DISPLAY.DiagnosticsText(self.Session.diagnostics), 'Preview validation failed', 'OK')
        return
    end
    local _, target = self.TargetPicker:GetSelected()
    target = target or DISPLAY.NormalizeId(self.Session.source.id)
    if not target then return end
    local ok, message = sendPreview(self.Session.source, target)
    if not ok then Derma_Message(message, 'Preview failed', 'OK') end
end

function EditorPanel:RebuildHierarchy()
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
        self:AddNumberField('Editor grid (0 disables)', object, 'editorGrid', 0, 128, 0)
        self:AddJSONField('Interaction', object, 'interaction')
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
        if object.type == 'material' then
            self:AddTextField('Material path', object, 'material')
            self:AddNumberField('Frame seconds', object, 'frameSeconds', 0.02, 60, 2)
            self:AddNumberField('Flash seconds', object, 'flashSeconds', 0.02, 60, 2)
            self:AddJSONField('Frame ordering', object, 'frames')
            self:AddJSONField('Tint', object, 'tint')
        elseif object.type == 'line_panel' then
            self:AddTextField('Panel title', object, 'title')
            local addLine = self.Inspector:Add('DButton')
            addLine:Dock(TOP) addLine:DockMargin(6, 4, 6, 0) addLine:SetText('Add line')
            addLine.DoClick = function()
                self:Changed(function()
                    object.lines = object.lines or {}
                    table.insert(object.lines, {type = 'value', label = 'VALUE', value = 0})
                end)
            end
        elseif object.type == 'annunciator' then
            self:AddTextField('Alarm ID', object, 'alarm')
        end
        self:AddTextField('Named action', object, 'action')
        self:AddJSONField('Action payload', object, 'actionPayload')
        self:AddJSONField('Condition variants', object, 'variants')
    elseif selection.kind == 'line' then
        self:AddTextField('Line type', object, 'type')
        self:AddTextField('Label / text', object, object.type == 'text' and 'text' or 'label')
        self:AddJSONField('Provider value binding', object, 'value')
        self:AddJSONField('Condition variants', object, 'variants')
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

function EditorPanel:DeleteSelection()
    local selection = self.Session.selection
    if not selection or selection.kind == 'display' then return end
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
                element.id = 'element_' .. (#page.elements + 1)
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
        if self.Session.themeSimulation then DISPLAY.ClientState.ThemeState[group] = self.Session.themeSimulation end
        DISPLAY.DrawDisplayCanvas(compiled)
        DISPLAY.ClientState.ThemeState[group] = previous
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

function EditorPanel:CanvasPressed(panel, code)
    local x, y = panel:CursorPos()
    x, y = self:CanvasPoint(panel, x, y)
    if code == MOUSE_RIGHT then
        if self.Session.source.buildMode == 'complex' then self:AddElementMenu(x, y)
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
    for index = #(page.elements or {}), 1, -1 do
        local element = page.elements[index]
        if DISPLAY.PointInRect(x, y, element) then
            self.Session.selection = {kind = 'element', page = self.Session.activePage, element = index}
            self:RebuildHierarchy() self:RebuildInspector()
            local resize = x >= element.x + element.width - 10 and y >= element.y + element.height - 10
            if not self.Session.readOnly then
                pushHistory(self.Session)
                self.Drag = {element = element, x = x, y = y, startX = element.x, startY = element.y, width = element.width, height = element.height, resize = resize}
            end
            return
        end
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
    local grid = tonumber(self.Session.source.editorGrid) or 8
    local page = activePageSource(self.Session)
    local xCandidates, yCandidates = {0, self.Session.source.width or 512}, {0, self.Session.source.height or 256}
    for _, sibling in ipairs(page and page.elements or {}) do
        if sibling ~= drag.element then
            table.insert(xCandidates, sibling.x) table.insert(xCandidates, sibling.x + sibling.width) table.insert(xCandidates, sibling.x + sibling.width / 2)
            table.insert(yCandidates, sibling.y) table.insert(yCandidates, sibling.y + sibling.height) table.insert(yCandidates, sibling.y + sibling.height / 2)
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
