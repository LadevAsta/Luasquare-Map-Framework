if not CLIENT then return end

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
local DISPLAY = LUASQUARE_3D2D
local EDITOR = DISPLAY.Editor or {}
DISPLAY.Editor = EDITOR

local function encodeString(value)
    local encoded = util.TableToJSON({tostring(value)}, false) or '[""]'
    return string.sub(encoded, 2, -2)
end

local function isArray(value)
    if type(value) ~= 'table' then return false end
    local maximum = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then return false end
        maximum = math.max(maximum, key)
    end
    for index = 1, maximum do if value[index] == nil then return false end end
    return true, maximum
end

local function canonicalJSON(value, depth)
    depth = depth or 0
    local prefix = string.rep('  ', depth)
    local childPrefix = string.rep('  ', depth + 1)
    if type(value) == 'string' then return encodeString(value) end
    if type(value) == 'number' then return tostring(value) end
    if type(value) == 'boolean' then return value and 'true' or 'false' end
    if type(value) ~= 'table' then return 'null' end
    local array, count = isArray(value)
    local parts = {}
    if array then
        for index = 1, count do parts[index] = childPrefix .. canonicalJSON(value[index], depth + 1) end
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

local function safeId(value, fallback)
    return DISPLAY.NormalizeId(value) or fallback
end

local function themeDraftDirectory()
    return DISPLAY.DraftRoot .. '/_themes'
end

local function defaultPack()
    return {
        schema = DISPLAY.Schema,
        kind = 'theme_pack',
        group = 'new_theme_group',
        defaultTheme = 'normal',
        themes = {
            normal = {
                text = {220, 245, 255, 255}, title = {255, 255, 255, 255},
                background = {4, 12, 16, 220}, panel = {8, 22, 28, 230},
                border = {80, 190, 220, 220}, accent = {70, 220, 160, 255},
                bar_background = {18, 32, 36, 240}, warning = {255, 210, 70, 255},
                critical = {255, 90, 90, 255}, inactive = {90, 110, 115, 255}
            }
        }
    }
end

local function listThemeSources()
    local out = {}
    local packed = DISPLAY.SourceRoot .. '/_themes'
    for _, name in ipairs(file.Find(packed .. '/*.json', 'GAME') or {}) do
        table.insert(out, {label = 'Packed - ' .. name, path = packed .. '/' .. name, realm = 'GAME', readOnly = true})
    end
    local drafts = themeDraftDirectory()
    for _, name in ipairs(file.Find(drafts .. '/*.json', 'DATA') or {}) do
        table.insert(out, {label = 'Draft - ' .. name, path = drafts .. '/' .. name, realm = 'DATA', readOnly = false})
    end
    table.sort(out, function(left, right) return left.label < right.label end)
    return out
end

local function readTheme(entry)
    local json = entry and file.Read(entry.path, entry.realm)
    local source = json and util.JSONToTable(json)
    if type(source) ~= 'table' or tostring(source.kind or '') ~= 'theme_pack' then
        return nil, 'Unable to read a theme_pack source.'
    end
    return source
end

local ThemePanel = {}

function ThemePanel:Init()
    self:SetTitle('Luasquare Theme Color Configuration')
    self:SetSize(math.min(ScrW() - 80, 1050), math.min(ScrH() - 80, 720))
    self:Center() self:SetSizable(true) self:SetDeleteOnClose(true)
    self.Source = defaultPack()
    self.Origin = 'New theme pack'
    self.ReadOnly = false
    self.Dirty = false
    self.History = {}
    self.Future = {}
    self.ThemeId = 'normal'

    self.Toolbar = self:Add('DPanel') self.Toolbar:Dock(TOP) self.Toolbar:SetTall(34)
    self.Toolbar:DockPadding(4, 3, 4, 3)
    self.SourcePicker = self.Toolbar:Add('DComboBox') self.SourcePicker:Dock(LEFT) self.SourcePicker:SetWide(260)
    self.SourcePicker.OnSelect = function(_, _, _, entry)
        if not self._refreshing then self:OpenEntry(entry) end
    end
    local function button(text, callback, width)
        local control = self.Toolbar:Add('DButton') control:Dock(LEFT) control:DockMargin(4, 0, 0, 0)
        control:SetWide(width or 70) control:SetText(text) control.DoClick = callback
        return control
    end
    button('New', function() self:ConfirmDiscard(function() self:Replace(defaultPack(), 'New theme pack', false) end) end, 52)
    button('Save draft', function() self:SaveDraft() end, 82)
    button('Undo', function() self:Undo() end, 55)
    button('Redo', function() self:Redo() end, 55)
    button('Validate', function() self:ValidateMessage() end, 68)

    self.Body = self:Add('DHorizontalDivider') self.Body:Dock(FILL) self.Body:SetLeftWidth(310) self.Body:SetDividerWidth(5)
    self.Left = self.Body:Add('DPanel') self.Body:SetLeft(self.Left)
    self.ThemeList = self.Left:Add('DListView') self.ThemeList:Dock(TOP) self.ThemeList:SetTall(250)
    self.ThemeList:AddColumn('Themes')
    self.ThemeList.OnRowSelected = function(_, _, line) self.ThemeId = line.ThemeId self.TokenId = nil self:RebuildInspector() end
    self.TokenList = self.Left:Add('DListView') self.TokenList:Dock(FILL)
    self.TokenList:AddColumn('Tokens')
    self.TokenList.OnRowSelected = function(_, _, line) self.TokenId = line.TokenId self:RebuildInspector() end
    self.Inspector = self.Body:Add('DScrollPanel') self.Body:SetRight(self.Inspector)
    self.Status = self:Add('DLabel') self.Status:Dock(BOTTOM) self.Status:SetTall(38)
    self.Status:SetWrap(true) self.Status:SetContentAlignment(4) self.Status:DockMargin(6, 2, 6, 2)
    self:Replace(self.Source, self.Origin, false)
end

function ThemePanel:RefreshSources()
    self._refreshing = true
    self.SourcePicker:Clear()
    for _, entry in ipairs(listThemeSources()) do self.SourcePicker:AddChoice(entry.label, entry) end
    self.SourcePicker:SetValue(self.Origin)
    self._refreshing = false
end

function ThemePanel:ConfirmDiscard(callback)
    if not self.Dirty then callback() return end
    Derma_Query('Discard unsaved theme changes?', 'Unsaved theme pack', 'Discard', callback,
        'Cancel', function() self:RefreshSources() end)
end

function ThemePanel:OpenEntry(entry)
    if not entry then self:RefreshSources() return end
    self:ConfirmDiscard(function()
        local source, message = readTheme(entry)
        if source then self:Replace(source, entry.path, entry.readOnly)
        else Derma_Message(message, 'Open failed', 'OK') self:RefreshSources() end
    end)
end

function ThemePanel:Replace(source, origin, readOnly)
    self.Source = DISPLAY.DeepCopy(source)
    self.Origin = origin
    self.ReadOnly = readOnly and true or false
    self.Dirty = false self.History = {} self.Future = {}
    self.ThemeId = self.Source.defaultTheme or next(self.Source.themes or {})
    self.TokenId = nil
    self:Compile() self:RebuildLists() self:RebuildInspector() self:RefreshSources()
end

function ThemePanel:PushHistory()
    table.insert(self.History, DISPLAY.DeepCopy(self.Source))
    if #self.History > 100 then table.remove(self.History, 1) end
    self.Future = {}
end

function ThemePanel:Changed(callback)
    if self.ReadOnly then
        Derma_Message('Packed themes are read-only. Save as a draft before editing.', 'Read-only theme', 'OK')
        return
    end
    self:PushHistory() callback() self.Dirty = true
    self:Compile() self:RebuildLists() self:RebuildInspector()
end

function ThemePanel:Undo()
    local source = table.remove(self.History) if not source then return end
    table.insert(self.Future, DISPLAY.DeepCopy(self.Source)) self.Source = source self.Dirty = true
    self:Compile() self:RebuildLists() self:RebuildInspector()
end

function ThemePanel:Redo()
    local source = table.remove(self.Future) if not source then return end
    table.insert(self.History, DISPLAY.DeepCopy(self.Source)) self.Source = source self.Dirty = true
    self:Compile() self:RebuildLists() self:RebuildInspector()
end

function ThemePanel:Compile()
    local compiled, diagnostics = DISPLAY.CompileSource(self.Source, self.Origin)
    self.Compiled = compiled self.Diagnostics = diagnostics or {}
    local text = DISPLAY.DiagnosticsText(self.Diagnostics)
    self.Status:SetText((self.ReadOnly and 'PACKED READ-ONLY' or 'DRAFT EDITABLE')
        .. (self.Dirty and ' - UNSAVED' or '') .. ' - ' .. self.Origin .. '\n'
        .. (text ~= '' and text or 'Valid theme pack'))
    if IsValid(self.DisplayEditor) then
        self.DisplayEditor.Session.themeOverride = compiled
        if compiled then
            self.DisplayEditor.Session.themeSimulation = self.ThemeId or compiled.defaultTheme
            self.DisplayEditor.PreviewCanvas:InvalidateLayout(true)
        end
    end
    return compiled ~= nil
end

function ThemePanel:ValidateMessage()
    self:Compile()
    local text = DISPLAY.DiagnosticsText(self.Diagnostics)
    Derma_Message(text ~= '' and text or 'Theme pack is valid.', 'Theme validation', 'OK')
end

function ThemePanel:SaveDraft()
    if not self:Compile() then self:ValidateMessage() return end
    file.CreateDir(DISPLAY.DraftRoot)
    file.CreateDir(themeDraftDirectory())
    local path = themeDraftDirectory() .. '/' .. safeId(self.Source.group, 'theme_pack') .. '.json'
    file.Write(path, canonicalJSON(self.Source) .. '\n')
    self.Origin = 'data/' .. path self.ReadOnly = false self.Dirty = false
    self:Compile() self:RefreshSources()
    SetClipboardText(self.Origin)
    notification.AddLegacy('Theme draft saved; exact path copied.', NOTIFY_GENERIC, 4)
end

function ThemePanel:RebuildLists()
    self.ThemeList:Clear() self.TokenList:Clear()
    self.Source.themes = type(self.Source.themes) == 'table' and self.Source.themes or {}
    if not self.Source.themes[self.ThemeId] then self.ThemeId = self.Source.defaultTheme or next(self.Source.themes) end
    for id in SortedPairs(self.Source.themes) do
        local line = self.ThemeList:AddLine((id == self.Source.defaultTheme and '* ' or '') .. id) line.ThemeId = id
    end
    local theme = self.Source.themes and self.Source.themes[self.ThemeId]
    if theme and theme.tokens then theme = theme.tokens end
    if not theme then return end
    for id in SortedPairs(theme) do
        local line = self.TokenList:AddLine(id) line.TokenId = id
    end
end

local function clearScroll(panel)
    local canvas = IsValid(panel) and panel:GetCanvas()
    if not IsValid(canvas) then return end
    for _, child in ipairs(canvas:GetChildren()) do child:Remove() end
end

function ThemePanel:AddLabel(text)
    local label = self.Inspector:Add('DLabel') label:Dock(TOP) label:DockMargin(7, 5, 7, 0)
    label:SetText(text) label:SetWrap(true) label:SetAutoStretchVertical(true) return label
end

function ThemePanel:AddTextEntry(labelText, value, callback)
    self:AddLabel(labelText)
    local entry = self.Inspector:Add('DTextEntry') entry:Dock(TOP) entry:DockMargin(7, 2, 7, 0)
    entry:SetValue(tostring(value or '')) entry.OnEnter = function(input) callback(input:GetValue()) end
end

function ThemePanel:RebuildInspector()
    clearScroll(self.Inspector)
    self:AddLabel('THEME PACK')
    self:AddTextEntry('Group ID', self.Source.group, function(value)
        self:Changed(function() self.Source.group = safeId(value, self.Source.group) end)
    end)
    self:AddLabel('Default theme')
    local default = self.Inspector:Add('DComboBox') default:Dock(TOP) default:DockMargin(7, 2, 7, 0)
    default:SetValue(self.Source.defaultTheme or '')
    for id in SortedPairs(self.Source.themes or {}) do default:AddChoice(id, id) end
    default.OnSelect = function(_, _, _, id) self:Changed(function() self.Source.defaultTheme = id end) end
    local addTheme = self.Inspector:Add('DButton') addTheme:Dock(TOP) addTheme:DockMargin(7, 8, 7, 0) addTheme:SetText('Add theme')
    addTheme.DoClick = function()
        Derma_StringRequest('Add theme', 'Theme ID', 'theme', function(value)
            local id = safeId(value) if not id or self.Source.themes[id] then return end
            self:Changed(function() self.Source.themes[id] = {} self.ThemeId = id end)
        end)
    end
    local theme = self.Source.themes and self.Source.themes[self.ThemeId]
    if not theme then return end
    if theme.tokens then theme = theme.tokens end
    self:AddLabel('SELECTED THEME - ' .. self.ThemeId)
    local duplicate = self.Inspector:Add('DButton') duplicate:Dock(TOP) duplicate:DockMargin(7, 3, 7, 0) duplicate:SetText('Duplicate theme')
    duplicate.DoClick = function()
        Derma_StringRequest('Duplicate theme', 'New theme ID', self.ThemeId .. '_copy', function(value)
            local id = safeId(value) if not id or self.Source.themes[id] then return end
            self:Changed(function() self.Source.themes[id] = DISPLAY.DeepCopy(self.Source.themes[self.ThemeId]) self.ThemeId = id end)
        end)
    end
    local rename = self.Inspector:Add('DButton') rename:Dock(TOP) rename:DockMargin(7, 3, 7, 0) rename:SetText('Rename theme')
    rename.DoClick = function()
        Derma_StringRequest('Rename theme', 'New theme ID', self.ThemeId, function(value)
            local id = safeId(value) if not id or (id ~= self.ThemeId and self.Source.themes[id]) then return end
            self:Changed(function()
                self.Source.themes[id] = self.Source.themes[self.ThemeId]
                self.Source.themes[self.ThemeId] = nil
                if self.Source.defaultTheme == self.ThemeId then self.Source.defaultTheme = id end
                self.ThemeId = id
            end)
        end)
    end
    local remove = self.Inspector:Add('DButton') remove:Dock(TOP) remove:DockMargin(7, 3, 7, 0) remove:SetText('Delete theme')
    remove:SetEnabled(table.Count(self.Source.themes) > 1)
    remove.DoClick = function()
        self:Changed(function()
            self.Source.themes[self.ThemeId] = nil self.ThemeId = next(self.Source.themes)
            if not self.Source.themes[self.Source.defaultTheme] then self.Source.defaultTheme = self.ThemeId end
        end)
    end
    local addToken = self.Inspector:Add('DButton') addToken:Dock(TOP) addToken:DockMargin(7, 8, 7, 0) addToken:SetText('Add color token')
    addToken.DoClick = function()
        Derma_StringRequest('Add token', 'Token ID', 'color', function(value)
            local id = safeId(value) if not id or theme[id] then return end
            self:Changed(function() theme[id] = {255, 255, 255, 255} self.TokenId = id end)
        end)
    end
    if not self.TokenId or not theme[self.TokenId] then return end
    self:AddLabel('SELECTED TOKEN - @' .. self.TokenId)
    local mixer = self.Inspector:Add('DColorMixer') mixer:Dock(TOP) mixer:DockMargin(7, 4, 7, 0) mixer:SetTall(280)
    mixer:SetPalette(true) mixer:SetAlphaBar(true) mixer:SetWangs(true)
    local color = DISPLAY.ColorTable(theme[self.TokenId]) mixer:SetColor(Color(color.r, color.g, color.b, color.a))
    local apply = self.Inspector:Add('DButton') apply:Dock(TOP) apply:DockMargin(7, 3, 7, 0) apply:SetText('Apply token color')
    apply.DoClick = function()
        local selected = mixer:GetColor()
        self:Changed(function() theme[self.TokenId] = {selected.r, selected.g, selected.b, selected.a} end)
    end
    local renameToken = self.Inspector:Add('DButton') renameToken:Dock(TOP) renameToken:DockMargin(7, 3, 7, 0) renameToken:SetText('Rename token')
    renameToken.DoClick = function()
        Derma_StringRequest('Rename token', 'New token ID', self.TokenId, function(value)
            local id = safeId(value) if not id or (id ~= self.TokenId and theme[id]) then return end
            self:Changed(function() theme[id] = theme[self.TokenId] theme[self.TokenId] = nil self.TokenId = id end)
        end)
    end
    local deleteToken = self.Inspector:Add('DButton') deleteToken:Dock(TOP) deleteToken:DockMargin(7, 3, 7, 7) deleteToken:SetText('Delete token')
    deleteToken.DoClick = function() self:Changed(function() theme[self.TokenId] = nil self.TokenId = nil end) end
end

function ThemePanel:Close()
    if self._closeApproved then return self.BaseClass.Close(self) end
    self:ConfirmDiscard(function()
        if not IsValid(self) then return end
        self._closeApproved = true self:Close()
    end)
end

function ThemePanel:OnRemove()
    if IsValid(self.DisplayEditor) then
        self.DisplayEditor.Session.themeOverride = self.PreviousThemeOverride
        self.DisplayEditor.Session.themeSimulation = self.PreviousThemeSimulation
        self.DisplayEditor.PreviewCanvas:InvalidateLayout(true)
    end
    if EDITOR.ThemeFrame == self then EDITOR.ThemeFrame = nil end
end

vgui.Register('LUASQUARE_3D2D_ThemeEditor', ThemePanel, 'DFrame')

function EDITOR.OpenThemeEditor(displayEditor)
    if IsValid(EDITOR.ThemeFrame) then EDITOR.ThemeFrame:MakePopup() return EDITOR.ThemeFrame end
    local frame = vgui.Create('LUASQUARE_3D2D_ThemeEditor')
    frame.DisplayEditor = displayEditor
    frame.PreviousThemeOverride = displayEditor and displayEditor.Session.themeOverride
    frame.PreviousThemeSimulation = displayEditor and displayEditor.Session.themeSimulation
    EDITOR.ThemeFrame = frame
    frame:MakePopup()
    frame:Compile()
    return frame
end
