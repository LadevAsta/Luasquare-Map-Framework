if not CLIENT then return end
LUASQUARE_AUDIO = LUASQUARE_AUDIO or {}
local AUDIO = LUASQUARE_AUDIO
AUDIO.Editor = AUDIO.Editor or {}
local EDITOR = AUDIO.Editor
local THEME = LUASQUARE_EDITOR_THEME
local userInput = _G.input

EDITOR.SharedSpecs = EDITOR.SharedSpecs or {
    sounds = {folder = 'sounds', id = 'shared_audio', label = 'Shared audio', tables = {'sounds', 'musicBuses'}},
    subtitles = {folder = 'subtitles', id = 'shared_subtitle', label = 'Shared subtitles', tables = {'subtitles'}},
    subtitle_styles = {folder = 'subtitle_styles', id = 'shared_subtitle_style',
        label = 'Shared subtitle styles', tables = {'subtitleStyles'}},
    pa_lines = {folder = 'pa_lines', id = 'shared_pa', label = 'Shared PA lines', tables = {'paLines'}}
}
EDITOR.FontFaces = EDITOR.FontFaces or {
    'Roboto', 'Roboto Black', 'Roboto Condensed', 'Roboto Light', 'Roboto Medium', 'Roboto Mono',
    'Roboto Thin', 'Arial', 'Courier New', 'Tahoma', 'Trebuchet MS', 'Verdana'
}
EDITOR.Subwindows = EDITOR.Subwindows or setmetatable({}, {__mode = 'k'})
EDITOR.SubwindowSerial = EDITOR.SubwindowSerial or 0

function EDITOR.RegisterSubwindow(frame)
    if not IsValid(frame) then return frame end
    EDITOR.SubwindowSerial = EDITOR.SubwindowSerial + 1
    EDITOR.Subwindows[frame] = EDITOR.SubwindowSerial
    return frame
end

hook.Add('Think', 'LUASQUARE_AUDIO_EditorSubwindowFocus', function()
    local cursorX, cursorY = userInput.GetCursorPos()
    local hovered, hoveredSerial = nil, -1
    for frame, serial in pairs(EDITOR.Subwindows) do
        if not IsValid(frame) then EDITOR.Subwindows[frame] = nil
        elseif frame:IsVisible() then
            local x, y = frame:LocalToScreen(0, 0)
            if cursorX >= x and cursorX <= x + frame:GetWide()
                and cursorY >= y and cursorY <= y + frame:GetTall() and serial > hoveredSerial then
                hovered, hoveredSerial = frame, serial
            end
        end
    end
    if hovered ~= EDITOR.HoveredSubwindow then
        EDITOR.HoveredSubwindow = hovered
        if IsValid(hovered) then
            EDITOR.SubwindowSerial = EDITOR.SubwindowSerial + 1
            EDITOR.Subwindows[hovered] = EDITOR.SubwindowSerial
            hovered:MoveToFront()
        end
    end
end)

local function clone(value)
    return type(value) == 'table' and table.Copy(value) or value
end

local function collectFiles(root, searchPath, out)
    local files, folders = file.Find(root .. '/*', searchPath)
    for _, name in ipairs(files or {}) do
        if string.GetExtensionFromFilename(name) == 'json' then table.insert(out, root .. '/' .. name) end
    end
    for _, name in ipairs(folders or {}) do collectFiles(root .. '/' .. name, searchPath, out) end
end

function EDITOR.ListSources(category, mapOwned)
    local spec = EDITOR.SharedSpecs[category]
    local packedRoot = mapOwned and (AUDIO.SourceRoot .. '/' .. game.GetMap() .. '/' .. category)
        or (AUDIO.SourceRoot .. '/_shared')
    local draftRoot = mapOwned and (AUDIO.DraftRoot .. '/' .. game.GetMap() .. '/' .. category)
        or (AUDIO.DraftRoot .. '/_shared/luasquare/' .. (spec and spec.folder or category))
    local out = {}
    local packed, drafts = {}, {}
    collectFiles(packedRoot, 'GAME', packed)
    collectFiles(draftRoot, 'DATA', drafts)
    local function append(path, search, packedSource)
        local info = AUDIO.GetSharedPathInfo('/' .. string.gsub(path, '\\', '/'))
        if mapOwned or info and info.folder == spec.folder then
            table.insert(out, {path = path, search = search, packed = packedSource,
                namespace = info and info.namespace or game.GetMap(), legacy = info and info.legacy or false})
        end
    end
    for _, path in ipairs(packed) do append(path, 'GAME', true) end
    for _, path in ipairs(drafts) do append(path, 'DATA', false) end
    table.sort(out, function(a, b) return a.path < b.path end)
    return out, draftRoot
end

function EDITOR.ReadSource(item)
    local json = item and file.Read(item.path, item.search)
    local source = json and util.JSONToTable(json) or nil
    if type(source) == 'table' then
        local legacyOwners = {}
        for soundId, definition in pairs(source.sounds or {}) do
            if definition.subtitle then legacyOwners[definition.subtitle] = soundId definition.subtitle = nil end
        end
        for subtitleId, definition in pairs(source.subtitles or {}) do
            if definition.chunks == nil and type(definition.text) == 'string' then
                definition.chunks = {{id = 'line', at = 0,
                    duration = tonumber(definition.duration) or 1, text = definition.text,
                    speaker = definition.speaker, style = definition.style,
                    duckMusic = definition.duckMusic, duckAmount = definition.duckAmount}}
                definition.sound = definition.sound or legacyOwners[subtitleId]
                definition.text, definition.duration = nil, nil
            end
        end
    end
    return type(source) == 'table' and AUDIO.NormalizeSourceTables(source) or nil
end

function EDITOR.UniqueId(values, wanted)
    wanted = AUDIO.NormalizeId(wanted) or 'new_item'
    local id, suffix = wanted, 2
    while values[id] do id = wanted .. '_' .. suffix suffix = suffix + 1 end
    return id
end

function EDITOR.NewSession(source, category, mapOwned)
    source = AUDIO.NormalizeSourceTables(clone(source or {}))
    return {source = source, history = {}, future = {}, dirty = false,
        category = category, mapOwned = mapOwned, selected = nil}
end

function EDITOR.Push(session)
    table.insert(session.history, clone(session.source))
    if #session.history > 64 then table.remove(session.history, 1) end
    session.future, session.dirty = {}, true
end

function EDITOR.Undo(session)
    local value = table.remove(session.history)
    if not value then return false end
    table.insert(session.future, clone(session.source))
    session.source, session.dirty = value, true
    return true
end

function EDITOR.Redo(session)
    local value = table.remove(session.future)
    if not value then return false end
    table.insert(session.history, clone(session.source))
    session.source, session.dirty = value, true
    return true
end

function EDITOR.Validate(session)
    local compiled, diagnostics = AUDIO.CompileSource(session.source, 'editor')
    return compiled, diagnostics or {}
end

function EDITOR.DraftPath(session)
    local _, root = EDITOR.ListSources(session.category, session.mapOwned)
    local spec = not session.mapOwned and EDITOR.SharedSpecs[session.category]
    local id = spec and spec.id or AUDIO.NormalizeId(session.source.id) or 'audio_pack'
    return root .. '/' .. id .. '.json'
end

function EDITOR.NewMasterSource(category)
    local spec = EDITOR.SharedSpecs[category]
    if not spec then return nil end
    local source = {schema = AUDIO.Schema, id = spec.id, label = spec.label}
    for _, tableName in ipairs(spec.tables) do source[tableName] = {} end
    return AUDIO.NormalizeSourceTables(source)
end

function EDITOR.LoadMasterSource(category)
    local source = EDITOR.NewMasterSource(category)
    local spec = EDITOR.SharedSpecs[category]
    if not spec then return source end
    local relative = '/_shared/luasquare/' .. spec.folder .. '/' .. spec.id .. '.json'
    local path = AUDIO.DraftRoot .. relative
    if file.Exists(path, 'DATA') then return EDITOR.ReadSource({path = path, search = 'DATA'}) or source end
    return source
end

local function mergePoolDefinition(snapshot, origins, item, tableName, id, definition)
    if snapshot.definitions[tableName][id] then
        table.insert(snapshot.diagnostics, {severity = 'warning', path = tableName .. '.' .. id,
            origin = item.path, message = 'duplicate shared ID; first definition from '
                .. origins[tableName][id] .. ' retained'})
        return
    end
    local copy = clone(definition)
    copy._editorOrigin, copy._editorNamespace = item.path, item.namespace
    snapshot.definitions[tableName][id], origins[tableName][id] = copy, item.path
end

function EDITOR.RefreshSharedPool()
    local snapshot, origins, packOrigins = {definitions = {}, sources = {}, diagnostics = {}}, {}, {}
    for _, category in ipairs({'sounds', 'subtitles', 'subtitle_styles', 'pa_lines'}) do
        local spec = EDITOR.SharedSpecs[category]
        for _, item in ipairs(EDITOR.ListSources(category, false)) do
            if item.legacy then
                table.insert(snapshot.diagnostics, {severity = 'warning', path = '$', origin = item.path,
                    message = 'legacy shared folder; import into the namespaced Luasquare master'})
            end
            local source = EDITOR.ReadSource(item)
            if source then
                local compiled, sourceDiagnostics = AUDIO.CompileSource(source, item.path)
                for _, diagnostic in ipairs(sourceDiagnostics or {}) do table.insert(snapshot.diagnostics, diagnostic) end
                if not compiled then source = nil end
            end
            if source then
                table.insert(snapshot.sources, item)
                if packOrigins[source.id] then
                    table.insert(snapshot.diagnostics, {severity = 'warning', path = 'id', origin = item.path,
                        message = 'duplicate pack ID already supplied by ' .. packOrigins[source.id]
                            .. '; definitions still merge independently'})
                else packOrigins[source.id] = item.path end
                for _, tableName in ipairs(spec.tables) do
                    snapshot.definitions[tableName] = snapshot.definitions[tableName] or {}
                    origins[tableName] = origins[tableName] or {}
                    for id, definition in pairs(source[tableName] or {}) do
                        mergePoolDefinition(snapshot, origins, item, tableName, id, definition)
                    end
                end
            else
                table.insert(snapshot.diagnostics, {severity = 'error', path = '$', origin = item.path,
                    message = 'unable to decode shared source'})
            end
        end
    end
    snapshot.origins = origins
    EDITOR.SharedPool = snapshot
    return snapshot
end

function EDITOR.GetSharedDefinitions(tableName, workingSource)
    local pool = EDITOR.SharedPool or EDITOR.RefreshSharedPool()
    local values = clone(pool.definitions[tableName] or {})
    for id, definition in pairs(workingSource and workingSource[tableName] or {}) do values[id] = clone(definition) end
    return values
end

function EDITOR.Save(session)
    local compiled, diagnostics = EDITOR.Validate(session)
    if not compiled then return false, AUDIO.DiagnosticsText(diagnostics) end
    local path = EDITOR.DraftPath(session)
    local output = clone(session.source)
    local spec = not session.mapOwned and EDITOR.SharedSpecs[session.category]
    local permitted = {}
    if spec then
        output.id = spec.id
        for _, tableName in ipairs(spec.tables) do permitted[tableName] = true end
    elseif session.category == 'channels' then permitted.paChannels = true
    elseif session.category == 'soundscapes' then permitted.soundscapeGroups = true end
    if next(permitted) then
        for _, tableName in ipairs(AUDIO.SourceCategories) do if not permitted[tableName] then output[tableName] = nil end end
    end
    file.CreateDir(string.GetPathFromFilename(path))
    file.Write(path, AUDIO.CanonicalJSON(output, true))
    if spec then session.source.id = spec.id end
    session.dirty, session.loadedPath = false, path
    if spec then EDITOR.RefreshSharedPool() end
    return true, path
end

function EDITOR.ConfirmDiscard(session, callback)
    if not session.dirty then callback() return end
    Derma_Query('Discard unsaved audio-pack changes?', 'Unsaved changes', 'Discard', callback, 'Cancel')
end

function EDITOR.AddLabel(parent, text)
    local label = vgui.Create('DLabel', parent)
    label:Dock(TOP) label:DockMargin(6, 4, 6, 0) label:SetText(text or '') label:SetTextColor(Color(225, 225, 225))
    label:SetTall(18)
    return label
end

function EDITOR.AddText(parent, label, value, changed, multiline)
    EDITOR.AddLabel(parent, label)
    local field = vgui.Create(multiline and 'DTextEntry' or 'DTextEntry', parent)
    field:Dock(TOP) field:DockMargin(6, 0, 6, 4) field:SetValue(tostring(value or ''))
    if multiline then field:SetMultiline(true) field:SetTall(72) end
    field.OnEnter = function(self) changed(self:GetValue()) end
    field.OnLoseFocus = function(self) changed(self:GetValue()) end
    return field
end

function EDITOR.AddNumber(parent, label, value, minimum, maximum, decimals, changed)
    local slider = vgui.Create('DNumSlider', parent)
    slider:Dock(TOP) slider:DockMargin(6, 2, 6, 2) slider:SetText(label)
    slider:SetMinMax(minimum, maximum) slider:SetDecimals(decimals or 2) slider:SetValue(value or 0)
    slider.OnValueChanged = function(_, number) changed(number) end
    return slider
end

function EDITOR.AddCompactNumber(parent, label, value, minimum, maximum, decimals, changed, width)
    local slider = vgui.Create('DNumSlider', parent)
    slider:Dock(LEFT) slider:DockMargin(4, 2, 2, 2) slider:SetWide(width or 220)
    slider:SetText(label) slider:SetMinMax(minimum, maximum)
    slider:SetDecimals(decimals or 2) slider:SetValue(value or 0)
    slider.OnValueChanged = function(_, number) changed(number) end
    return slider
end

function EDITOR.AddTimelineScrollbar(parent, getValue, setValue, getMaximum, getVisible)
    local bar = vgui.Create('DPanel', parent)
    bar:Dock(TOP) bar:DockMargin(6, 2, 6, 5) bar:SetTall(18)
    local function metrics(self)
        local width = math.max(self:GetWide(), 1)
        local maximum = math.max(tonumber(getMaximum()) or 0, 0)
        local visible = math.max(tonumber(getVisible()) or 0, 0.001)
        local thumbWidth = maximum <= 0 and width
            or math.Clamp(width * visible / (maximum + visible), 24, width)
        local value = math.Clamp(tonumber(getValue()) or 0, 0, maximum)
        local thumbX = maximum > 0 and (width - thumbWidth) * value / maximum or 0
        return width, maximum, thumbX, thumbWidth
    end
    bar.Paint = function(self, width, height)
        local _, _, thumbX, thumbWidth = metrics(self)
        surface.SetDrawColor(23, 27, 31) surface.DrawRect(0, 0, width, height)
        surface.SetDrawColor(self.Dragging and Color(115, 165, 200) or Color(78, 92, 104))
        surface.DrawRect(thumbX, 2, thumbWidth, height - 4)
        surface.SetDrawColor(145, 160, 172) surface.DrawOutlinedRect(thumbX, 2, thumbWidth, height - 4, 1)
    end
    local function move(self, x, preserveOffset)
        local width, maximum, _, thumbWidth = metrics(self)
        if maximum <= 0 or width <= thumbWidth then setValue(0) return end
        local offset = preserveOffset and (self.DragOffset or thumbWidth * 0.5) or thumbWidth * 0.5
        setValue(math.Clamp((x - offset) / (width - thumbWidth) * maximum, 0, maximum))
    end
    bar.OnMousePressed = function(self, code)
        if code ~= MOUSE_LEFT then return end
        local x = self:LocalCursorPos()
        local _, _, thumbX, thumbWidth = metrics(self)
        self.DragOffset = x >= thumbX and x <= thumbX + thumbWidth and x - thumbX or thumbWidth * 0.5
        self.Dragging = true self:MouseCapture(true) move(self, x, true)
    end
    bar.OnCursorMoved = function(self, x)
        if self.Dragging then move(self, x, true) end
    end
    bar.OnMouseReleased = function(self, code)
        if code ~= MOUSE_LEFT then return end
        self.Dragging = false self.DragOffset = nil self:MouseCapture(false)
    end
    bar.OnCursorEntered = function(self) self:SetCursor('hand') end
    bar.OnCursorExited = function(self) if not self.Dragging then self:SetCursor('arrow') end end
    return bar
end

function EDITOR.AddChoice(parent, label, value, choices, changed)
    EDITOR.AddLabel(parent, label)
    local combo = vgui.Create('DComboBox', parent)
    combo:Dock(TOP) combo:DockMargin(6, 0, 6, 4) combo:SetValue(tostring(value or ''))
    for _, choice in ipairs(choices or {}) do combo:AddChoice(choice, choice, choice == value) end
    combo.OnSelect = function(_, _, text, data) changed(data or text) end
    return combo
end

function EDITOR.AddFontChoice(parent, label, value, changed, allowInherit)
    EDITOR.AddLabel(parent, label)
    local combo = vgui.Create('DComboBox', parent)
    combo:Dock(TOP) combo:DockMargin(6, 0, 6, 4)
    if allowInherit then combo:AddChoice('Inherit from style', false, value == nil or value == '') end
    local known = {}
    for _, font in ipairs(EDITOR.FontFaces) do
        known[font] = true combo:AddChoice(font, font, font == value)
    end
    if value and value ~= '' and not known[value] then combo:AddChoice(value .. ' (current custom)', value, true) end
    combo:SetValue(value and value ~= '' and value or allowInherit and 'Inherit from style' or 'Roboto')
    combo.OnSelect = function(_, _, text, data)
        if allowInherit and text == 'Inherit from style' then changed(nil) else changed(data or text) end
    end
    return combo
end

function EDITOR.AddCheck(parent, label, value, changed)
    local check = vgui.Create('DCheckBoxLabel', parent)
    check:Dock(TOP) check:DockMargin(6, 3, 6, 3) check:SetText(label) check:SetValue(value and 1 or 0)
    check:SetTextColor(Color(225, 225, 225)) check:SizeToContents()
    check.OnChange = function(_, enabled) changed(enabled) end
    return check
end

function EDITOR.OpenSourceManager(editor)
    local frame = vgui.Create('DFrame')
    frame:SetTitle('Audio source manager') frame:SetSize(760, 520) frame:Center()
    frame:MakePopup() frame:SetSizable(true) frame:SetDraggable(true)
    EDITOR.RegisterSubwindow(frame)
    local search = vgui.Create('DTextEntry', frame)
    search:Dock(TOP) search:DockMargin(6, 6, 6, 4) search:SetPlaceholderText('Search full source path...')
    local list = vgui.Create('DListView', frame)
    list:Dock(FILL) list:DockMargin(6, 0, 6, 6) list:AddColumn('Kind'):SetFixedWidth(70) list:AddColumn('Path')
    local function rebuild()
        list:Clear()
        local needle = string.lower(search:GetValue())
        for _, item in ipairs(EDITOR.ListSources(editor.Session.category, editor.Session.mapOwned)) do
            if needle == '' or string.find(string.lower(item.path), needle, 1, true) then
                local kind = item.legacy and 'Legacy' or item.packed and 'Packed' or 'Draft'
                local line = list:AddLine(kind, item.path) line.SourceItem = item
            end
        end
    end
    search.OnValueChange = rebuild
    list.DoDoubleClick = function(_, _, line)
        if not line.SourceItem then return end
        if not editor.Session.mapOwned and line.SourceItem.packed then
            Derma_Message('Packed contributor sources are read-only. Use Shared Pool to import individual assets into the master draft.',
                'Read-only contributor', 'OK')
            return
        end
        EDITOR.ConfirmDiscard(editor.Session, function()
            local source = EDITOR.ReadSource(line.SourceItem)
            if not source then Derma_Message('Unable to decode source.', 'Load failed', 'OK') return end
            editor:SetSource(source, line.SourceItem.path, line.SourceItem.packed)
            frame:Close()
        end)
    end
    rebuild()
    if THEME then THEME.ApplyTree(frame) end
end

function EDITOR.OpenSharedPool(editor)
    local spec = EDITOR.SharedSpecs[editor.Session.category]
    if not spec then return end
    local pool = EDITOR.RefreshSharedPool()
    local frame = vgui.Create('DFrame')
    frame:SetTitle('Shared audio pool - ' .. spec.label) frame:SetSize(900, 600) frame:Center()
    frame:SetSizable(true) frame:SetDraggable(true) frame:MakePopup()
    EDITOR.RegisterSubwindow(frame)
    local status = vgui.Create('DLabel', frame) status:Dock(BOTTOM) status:SetTall(42)
    status:SetTextColor(Color(225, 225, 225)) status:SetWrap(true) status:DockMargin(6, 0, 6, 2)
    local search = vgui.Create('DTextEntry', frame) search:Dock(TOP) search:DockMargin(6, 6, 6, 4)
    search:SetPlaceholderText('Search ID, contributor namespace, or source path...')
    local details = vgui.Create('DTextEntry', frame) details:Dock(RIGHT) details:DockMargin(4, 0, 6, 4)
    details:SetWide(330) details:SetMultiline(true) details:SetEditable(false)
    local list = vgui.Create('DListView', frame) list:Dock(FILL) list:DockMargin(6, 0, 6, 4)
    list:AddColumn('Category'):SetFixedWidth(110) list:AddColumn('ID'):SetFixedWidth(220)
    list:AddColumn('Namespace'):SetFixedWidth(135) list:AddColumn('Source path')
    local selected
    local function rebuild()
        list:Clear() selected = nil
        local needle = string.lower(search:GetValue())
        for _, tableName in ipairs(spec.tables) do
            for _, id in ipairs(EDITOR.SortedIds(pool.definitions[tableName])) do
                local definition = pool.definitions[tableName][id]
                local haystack = string.lower(id .. ' ' .. tostring(definition._editorNamespace or '')
                    .. ' ' .. tostring(definition._editorOrigin or ''))
                if needle == '' or string.find(haystack, needle, 1, true) then
                    local row = list:AddLine(tableName, id, definition._editorNamespace or '', definition._editorOrigin or '')
                    row.TableName, row.DefinitionId, row.Definition = tableName, id, definition
                end
            end
        end
        status:SetText(#pool.diagnostics > 0 and AUDIO.DiagnosticsText(pool.diagnostics)
            or 'Read-only contributor pool. Import copies the selected definition into the master draft.')
    end
    list.OnRowSelected = function(_, _, row)
        selected = row details:SetValue(AUDIO.CanonicalJSON(row.Definition, true) or '')
    end
    local import = vgui.Create('DButton', frame) import:Dock(BOTTOM) import:DockMargin(6, 0, 6, 6)
    import:SetTall(28) import:SetText('Import selected into master draft')
    local refresh = vgui.Create('DButton', frame) refresh:Dock(BOTTOM) refresh:DockMargin(6, 0, 6, 3)
    refresh:SetTall(26) refresh:SetText('Refresh mounted shared pool')
    local function importSelected()
        if not selected or not selected.Definition then return end
        local destination = editor.Session.source[selected.TableName]
        if destination[selected.DefinitionId] then
            status:SetText('Import rejected: master already contains ID ' .. selected.DefinitionId) return
        end
        EDITOR.Push(editor.Session)
        local definition = clone(selected.Definition)
        definition._editorOrigin, definition._editorNamespace = nil, nil
        destination[selected.DefinitionId] = definition
        editor.Session.dirty, editor.Session.selected = true, selected.DefinitionId
        editor:Rebuild() status:SetText('Imported ' .. selected.DefinitionId .. ' into ' .. spec.id)
    end
    refresh.DoClick = function() pool = EDITOR.RefreshSharedPool() rebuild() end
    import.DoClick = importSelected list.DoDoubleClick = importSelected search.OnValueChange = rebuild
    rebuild()
    if THEME then THEME.ApplyTree(frame) end
end

function EDITOR.BuildFrame(title, source, category, mapOwned, bodyBuilder)
    local frame = vgui.Create('DFrame')
    frame:SetTitle(title) frame:SetSize(math.min(ScrW() * 0.82, 1500), math.min(ScrH() * 0.82, 920))
    frame:Center() frame:SetSizable(true) frame:SetDraggable(true) frame:MakePopup()
    frame.Session = EDITOR.NewSession(source, category, mapOwned)
    frame.Toolbar = vgui.Create('DPanel', frame) frame.Toolbar:Dock(TOP) frame.Toolbar:SetTall(32)
    frame.Status = vgui.Create('DLabel', frame) frame.Status:Dock(BOTTOM) frame.Status:SetTall(34)
    frame.Status:SetTextColor(Color(220, 220, 220)) frame.Status:DockMargin(6, 0, 6, 2)
    local function button(text, callback)
        local control = vgui.Create('DButton', frame.Toolbar)
        control:Dock(LEFT) control:DockMargin(3, 3, 0, 3) control:SetWide(82) control:SetText(text)
        control.DoClick = callback return control
    end
    button('New', function() EDITOR.ConfirmDiscard(frame.Session, function() frame:NewSource() end) end)
    button('Load...', function() EDITOR.OpenSourceManager(frame) end)
    if not mapOwned then frame.SharedPoolButton = button('Shared pool', function() EDITOR.OpenSharedPool(frame) end) end
    button('Save draft', function()
        local ok, message = EDITOR.Save(frame.Session)
        frame.Status:SetText(ok and ('Saved: data/' .. message) or message)
    end)
    button('Undo', function() if EDITOR.Undo(frame.Session) then frame:Rebuild() end end)
    button('Redo', function() if EDITOR.Redo(frame.Session) then frame:Rebuild() end end)
    button('Validate', function()
        local compiled, diagnostics = EDITOR.Validate(frame.Session)
        frame.Status:SetText(compiled and (#diagnostics == 0 and 'Valid source' or AUDIO.DiagnosticsText(diagnostics))
            or AUDIO.DiagnosticsText(diagnostics))
    end)
    frame.Body = vgui.Create('DPanel', frame) frame.Body:Dock(FILL)
    if THEME then THEME.Apply(frame, 'frame') THEME.Apply(frame.Toolbar, 'panel') THEME.Apply(frame.Body, 'panel') end
    frame.Rebuild = function(self)
        self.Body:Clear() bodyBuilder(self, self.Body)
        self.Status:SetText((self.Session.dirty and 'UNSAVED · ' or '') .. 'Export: data/' .. EDITOR.DraftPath(self.Session))
        if IsValid(self.SharedPoolButton) then self.SharedPoolButton:SetVisible(not self.Session.mapOwned) end
        if THEME then THEME.ApplyTree(self) end
    end
    frame.SetSource = function(self, newSource, path, packed, newCategory, newMapOwned)
        local selectedCategory = newCategory or self.Session.category or category
        local selectedMapOwned = newMapOwned
        if selectedMapOwned == nil then selectedMapOwned = self.Session.mapOwned end
        self.Session = EDITOR.NewSession(newSource, selectedCategory, selectedMapOwned)
        self.Session.loadedPath, self.Session.packed = path, packed self:Rebuild()
    end
    local baseClose = frame.Close
    frame.Close = function(self)
        if self._closeApproved then return baseClose(self) end
        EDITOR.ConfirmDiscard(self.Session, function()
            if not IsValid(self) then return end
            self._closeApproved = true baseClose(self)
        end)
    end
    frame.btnClose.DoClick = function() frame:Close() end
    frame:Rebuild()
    return frame
end

function EDITOR.Mutate(frame, callback, rebuild)
    EDITOR.Push(frame.Session) callback(frame.Session.source)
    if rebuild ~= false then frame:Rebuild() end
end

function EDITOR.SortedIds(values)
    local out = {}
    for id in pairs(values or {}) do table.insert(out, id) end
    table.sort(out) return out
end

function EDITOR.OpenIdPicker(title, values, callback, predicate)
    local frame = vgui.Create('DFrame')
    frame:SetTitle(title or 'Select registered ID') frame:SetSize(620, 520) frame:Center()
    frame:SetSizable(true) frame:SetDraggable(true) frame:MakePopup()
    EDITOR.RegisterSubwindow(frame)
    local search = vgui.Create('DTextEntry', frame) search:Dock(TOP) search:DockMargin(6, 6, 6, 4)
    search:SetPlaceholderText('Search ID or label...')
    local list = vgui.Create('DListView', frame) list:Dock(FILL) list:DockMargin(6, 0, 6, 6)
    list:AddColumn('ID') list:AddColumn('Label')
    local function rebuild()
        list:Clear() local needle = string.lower(search:GetValue())
        for _, id in ipairs(EDITOR.SortedIds(values)) do
            local definition = values[id]
            local label = tostring(definition.label or '')
            if (not predicate or predicate(definition))
                and (needle == '' or string.find(string.lower(id .. ' ' .. label), needle, 1, true)) then
                local row = list:AddLine(id, label) row.ItemId = id
            end
        end
    end
    search.OnValueChange = rebuild
    list.DoDoubleClick = function(_, _, row) callback(row.ItemId) frame:Close() end
    rebuild() if THEME then THEME.ApplyTree(frame) end return frame
end

function EDITOR.StopLocalSound(preview)
    if not preview then return end
    if IsValid(preview.channel) then preview.channel:Stop() end
    if preview.path and IsValid(LocalPlayer()) then LocalPlayer():StopSound(preview.path) end
end

function EDITOR.PlayLocalSound(definition, callback, options)
    options = options or {}
    local reference = definition and (definition.path or definition.script)
    if not reference then return false end
    local streamPreview = definition.mode == 'music'
        or options.seekable and definition.path and not definition.soundScript and not definition.script
    if streamPreview then
        sound.PlayFile('sound/' .. reference, 'noplay noblock', function(channel, code, message)
            if not IsValid(channel) then if callback then callback(false, message or code) end return end
            channel:SetVolume(definition.volume or 1)
            channel:SetPlaybackRate(math.max((definition.pitch or 100) / 100, 0.001))
            if tonumber(options.startTime) and options.startTime > 0 then channel:SetTime(options.startTime) end
            channel:Play()
            if callback then callback(true, {channel = channel, seekable = true}) end
        end)
        return true
    end
    if not IsValid(LocalPlayer()) then return false end
    local channels = {auto = CHAN_AUTO, weapon = CHAN_WEAPON, voice = CHAN_VOICE,
        item = CHAN_ITEM, body = CHAN_BODY, stream = CHAN_STREAM, static = CHAN_STATIC}
    LocalPlayer():EmitSound(reference, definition.soundLevel or 75,
        definition.pitch or 100, definition.volume or 1,
        channels[definition.channel or 'auto'] or CHAN_AUTO, 0, definition.dsp or 0)
    if callback then callback(true, {path = reference, seekable = false}) end
    return true
end
