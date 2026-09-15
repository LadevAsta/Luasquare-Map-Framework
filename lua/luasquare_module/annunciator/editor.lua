if not CLIENT then return end

LUASQUARE_ANNUNCIATOR = LUASQUARE_ANNUNCIATOR or {}
local ANN = LUASQUARE_ANNUNCIATOR

ANN.Editor = ANN.Editor or {}
local EDITOR = ANN.Editor

local function mapName()
    return string.lower(game.GetMap() or 'unknown')
end

local function safeName(value)
    value = string.lower(tostring(value or 'annunciator_pack'))
    value = string.gsub(value, '[^%w_%-]', '_')
    return value ~= '' and value or 'annunciator_pack'
end

local function defaultSource()
    return {
        schema = ANN.Schema,
        kind = 'annunciator_pack',
        id = 'new_annunciator_pack',
        label = 'New Annunciator Pack',
        groups = {
            main = {
                label = 'Main',
                muteSeconds = 60,
                soundOrigin = {position = {0, 0, 0}}
            }
        },
        alarms = {}
    }
end

local function defaultAlarm(group)
    return {
        label = 'NEW ALARM',
        group = group,
        tier = 2,
        condition = {provider = '', path = '', op = 'truthy'},
        indicator = {
            targetnames = {},
            skins = {off = 0, fast_flash = 1, on = 2, slow_flash = 3}
        },
        audio = {
            sound = '',
            mode = 'once',
            repeatSeconds = 10,
            ackSilences = true,
            pitch = 100
        },
        reAlarmSeconds = 180
    }
end

local function draftEntries()
    local root = ANN.DraftRoot .. '/' .. mapName()
    local entries = {}
    local files = file.Find(root .. '/*.json', 'DATA')
    for _, name in ipairs(files or {}) do
        table.insert(entries, {
            label = 'Draft · ' .. name,
            path = root .. '/' .. name,
            realm = 'DATA',
            readOnly = false
        })
    end
    for path in pairs(ANN.EditorCatalog.sources or {}) do
        table.insert(entries, {
            label = 'Packed · ' .. string.GetFileFromFilename(path),
            path = path,
            realm = 'GAME',
            readOnly = true
        })
    end
    table.sort(entries, function(left, right) return left.label < right.label end)
    return entries
end

local function leafValue(raw)
    if raw == 'true' then return true end
    if raw == 'false' then return false end
    if raw == 'null' or raw == '' then return nil end
    return tonumber(raw) or raw
end

local function tierColor(alarm)
    local color = alarm and alarm.color or ANN.GetTierColor(alarm and alarm.tier or 2)
    return Color(color[1] or color.r or 255, color[2] or color.g or 196,
        color[3] or color.b or 48, color[4] or color.a or 255)
end

local function soundDefinition(id)
    return ANN.EditorCatalog.sounds and ANN.EditorCatalog.sounds[id]
end

local PANEL = {}

function PANEL:Init()
    self:SetTitle('Luasquare Annunciator Editor')
    self:SetSize(math.min(ScrW() - 60, 1500), math.min(ScrH() - 60, 900))
    self:Center()
    self:SetSizable(true)
    self:SetDeleteOnClose(true)

    self.Source = defaultSource()
    self.Origin = '<new>'
    self.ReadOnly = false
    self.Dirty = false
    self.UndoStack = {}
    self.RedoStack = {}
    self.Selection = {kind = 'pack'}
    self.Simulation = {visualState = 'off', muted = false}

    self.Toolbar = self:Add('DPanel')
    self.Toolbar:Dock(TOP)
    self.Toolbar:SetTall(34)

    local function tool(text, callback, width)
        local button = self.Toolbar:Add('DButton')
        button:Dock(LEFT)
        button:DockMargin(3, 3, 0, 3)
        button:SetWide(width or 74)
        button:SetText(text)
        button.DoClick = callback
        return button
    end

    tool('Sources...', function() self:OpenSources() end, 82)
    self.EditCopyButton = tool('Editable copy', function()
        self.ReadOnly = false
        self.Origin = '<copy>'
        self.Dirty = true
        self:RefreshAll()
    end, 92)
    tool('Undo', function() self:Undo() end, 56)
    tool('Redo', function() self:Redo() end, 56)
    tool('Validate', function() self:Validate(true) end, 70)
    tool('Refresh catalog', function()
        ANN.RequestEditorCatalog()
    end, 108)

    self.Status = self.Toolbar:Add('DLabel')
    self.Status:Dock(FILL)
    self.Status:DockMargin(10, 0, 5, 0)
    self.Status:SetContentAlignment(6)

    self.Body = self:Add('DPanel')
    self.Body:Dock(FILL)

    self.Left = self.Body:Add('DPanel')
    self.Left:Dock(LEFT)
    self.Left:SetWide(290)

    self.Hierarchy = self.Left:Add('DTree')
    self.Hierarchy:Dock(FILL)
    self.Hierarchy.OnNodeSelected = function(_, node)
        if node.LuasquareSelection then
            self:StopPreviewAudio()
            self.Selection = node.LuasquareSelection
            self:RebuildInspector()
        end
    end

    self.HierarchyButtons = self.Left:Add('DPanel')
    self.HierarchyButtons:Dock(BOTTOM)
    self.HierarchyButtons:SetTall(62)
    local addGroup = self.HierarchyButtons:Add('DButton')
    addGroup:Dock(TOP)
    addGroup:SetText('Add group')
    addGroup.DoClick = function() self:AddGroup() end
    local addAlarm = self.HierarchyButtons:Add('DButton')
    addAlarm:Dock(LEFT)
    addAlarm:SetWide(145)
    addAlarm:SetText('Add alarm')
    addAlarm.DoClick = function() self:AddAlarm() end
    local remove = self.HierarchyButtons:Add('DButton')
    remove:Dock(FILL)
    remove:SetText('Delete selected')
    remove.DoClick = function() self:DeleteSelection() end

    self.Center = self.Body:Add('DPanel')
    self.Center:Dock(FILL)
    self.Center:DockMargin(4, 0, 4, 0)

    self.Preview = self.Center:Add('DPanel')
    self.Preview:Dock(TOP)
    self.Preview:SetTall(150)
    self.Preview.Paint = function(panel, width, height)
        surface.SetDrawColor(18, 20, 24, 255)
        surface.DrawRect(0, 0, width, height)
        local alarm = self:GetSelectedAlarm()
        local color = tierColor(alarm)
        local state = self.Simulation.visualState
        local lit = state ~= 'off'
        if state == 'fast_flash' then lit = math.floor(RealTime() / 0.25) % 2 == 0 end
        if state == 'slow_flash' then lit = math.floor(RealTime() / 0.75) % 2 == 0 end
        local drawColor = lit and color
            or Color(44, 48, 54)
        surface.SetDrawColor(drawColor)
        surface.DrawRect(24, 28, width - 48, height - 56)
        surface.SetDrawColor(170, 175, 182)
        surface.DrawOutlinedRect(24, 28, width - 48, height - 56, 2)
        draw.SimpleText(alarm and alarm.label or 'SELECT AN ALARM', 'DermaLarge',
            width / 2, height / 2 - 8, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.upper(state) .. (self.Simulation.muted and ' · MUTED' or ''),
            'DermaDefault', width / 2, height / 2 + 24, color_white,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    self.SimulationBar = self.Center:Add('DPanel')
    self.SimulationBar:Dock(TOP)
    self.SimulationBar:SetTall(30)
    local states = {
        off = function() self.Simulation.visualState = 'off' self:StopPreviewAudio() end,
        trip = function()
            local alarm = self:GetSelectedAlarm()
            self.Simulation.visualState = alarm and alarm.tier == 1 and 'on' or 'fast_flash'
            self:PlayPreviewAudio(false)
        end,
        ack = function()
            local alarm = self:GetSelectedAlarm()
            if alarm and alarm.tier == 1 then return end
            self.Simulation.visualState = 'on'
            if not alarm or (alarm.tier ~= 4
                and (not alarm.audio or alarm.audio.ackSilences ~= false)) then
                self:StopPreviewAudio()
            end
        end,
        clear = function()
            local alarm = self:GetSelectedAlarm()
            self.Simulation.visualState = alarm and alarm.tier == 1 and 'off' or 'slow_flash'
            self:StopPreviewAudio()
        end,
        mute = function()
            local alarm = self:GetSelectedAlarm()
            if alarm and alarm.tier == 4 then self:Report('Siren alarms ignore MUTE.') return end
            self.Simulation.muted = not self.Simulation.muted
            if self.Simulation.muted then self:StopPreviewAudio() else self:PlayPreviewAudio(false) end
        end,
        test = function()
            local alarm = self:GetSelectedAlarm()
            if not alarm or alarm.tier == 1 or alarm.tier == 4 then
                self:Report('TEST applies only to Warning and Critical alarms.')
                return
            end
            self.Simulation.visualState = 'fast_flash'
            self.Simulation.muted = false
            self:PlayPreviewAudio(true)
        end
    }
    for _, name in ipairs({'off', 'trip', 'ack', 'clear', 'mute', 'test'}) do
        local button = self.SimulationBar:Add('DButton')
        button:Dock(LEFT)
        button:SetWide(66)
        button:SetText(string.upper(name))
        button.DoClick = states[name]
    end

    self.Diagnostics = LUASQUARE_EDITOR_THEME.CreateTextArea(self.Center)
    self.Diagnostics:Dock(FILL)

    self.Right = self.Body:Add('DScrollPanel')
    self.Right:Dock(RIGHT)
    self.Right:SetWide(410)

    local baseClose = self.Close
    self.Close = function(panel)
        if panel.LuasquareCloseApproved then return baseClose(panel) end
        panel:ConfirmDiscard(function()
            if not IsValid(panel) then return end
            panel.LuasquareCloseApproved = true
            baseClose(panel)
        end)
    end
    self.btnClose.DoClick = function() self:Close() end

    self:RefreshAll()
    ANN.RequestEditorCatalog()
    timer.Simple(0, function()
        if IsValid(self) and LUASQUARE_EDITOR_THEME then
            LUASQUARE_EDITOR_THEME.ApplyEditor(self, {
                self.Toolbar, self.Body, self.Left, self.HierarchyButtons,
                self.Center, self.SimulationBar
            })
        end
    end)
end

function PANEL:Think()
    self.EditCopyButton:SetVisible(self.ReadOnly)
    if self.ReportUntil and RealTime() < self.ReportUntil then
        self.Status:SetText(self.ReportText or '')
        return
    end
    self.Status:SetText((self.ReadOnly and 'PACKED - READ ONLY' or 'DRAFT')
        .. (self.Dirty and ' - UNSAVED' or '') .. ' - ' .. tostring(self.Origin))
end

function PANEL:Report(message)
    message = tostring(message or '')
    self.ReportText = message
    self.ReportUntil = RealTime() + 5
    print('[LUASQUARE_ANNUNCIATOR_EDITOR] ' .. message)
end

function PANEL:StopPreviewAudio()
    if self.PreviewTimer then timer.Remove(self.PreviewTimer) end
    self.PreviewTimer = nil
    local audioEditor = LUASQUARE_AUDIO and LUASQUARE_AUDIO.Editor
    if audioEditor and audioEditor.StopLocalSound then
        audioEditor.StopLocalSound(self.PreviewAudio)
    elseif self.PreviewAudio and self.PreviewAudio.path and IsValid(LocalPlayer()) then
        LocalPlayer():StopSound(self.PreviewAudio.path)
    end
    self.PreviewAudio = nil
end

function PANEL:PlayPreviewOnce(definition)
    local audioEditor = LUASQUARE_AUDIO and LUASQUARE_AUDIO.Editor
    if audioEditor and audioEditor.PlayLocalSound then
        return audioEditor.PlayLocalSound(definition, function(ok, preview)
            if not IsValid(self) then
                if ok and audioEditor.StopLocalSound then audioEditor.StopLocalSound(preview) end
                return
            end
            if ok then self.PreviewAudio = preview else self:Report('Sound preview failed.') end
        end)
    end
    local reference = definition.path or definition.script
    if not reference or not IsValid(LocalPlayer()) then return false end
    LocalPlayer():EmitSound(reference, definition.soundLevel or 75,
        definition.pitch or 100, definition.volume or 1)
    self.PreviewAudio = {path = reference}
    return true
end

function PANEL:PlayPreviewAudio(isTest)
    local alarm = self:GetSelectedAlarm()
    if not alarm or not alarm.audio then return end
    if alarm.tier == 1 or (isTest and alarm.tier == 4) then
        self:StopPreviewAudio()
        return
    end
    if self.Simulation.muted and alarm.tier ~= 4 then return end
    local definition = soundDefinition(alarm.audio.sound)
    if not definition then
        self:Report('Select a registered sound before previewing this alarm.')
        return
    end
    self:StopPreviewAudio()
    definition = ANN.DeepCopy(definition)
    definition.pitch = tonumber(alarm.audio.pitch) or definition.pitch or 100
    local volume = GetConVar(ANN.VolumeConVar)
    definition.volume = (tonumber(definition.volume) or 1)
        * (volume and volume:GetFloat() or 1)
    if not self:PlayPreviewOnce(definition) then
        self:Report('Sound preview could not be started.')
        return
    end
    if alarm.audio.mode == 'repeat' then
        EDITOR.PreviewSerial = (EDITOR.PreviewSerial or 0) + 1
        self.PreviewTimer = 'LUASQUARE_ANNUNCIATOR_EditorPreview_' .. EDITOR.PreviewSerial
        timer.Create(self.PreviewTimer, math.max(tonumber(alarm.audio.repeatSeconds) or 10, 0.25), 0, function()
            if not IsValid(self) then timer.Remove(self.PreviewTimer) return end
            self:PlayPreviewOnce(definition)
        end)
    end
end

function PANEL:OnRemove()
    self:StopPreviewAudio()
    if IsValid(self.SourceWindow) then self.SourceWindow:Close() end
end

function PANEL:PushHistory()
    table.insert(self.UndoStack, ANN.DeepCopy(self.Source))
    if #self.UndoStack > 64 then table.remove(self.UndoStack, 1) end
    self.RedoStack = {}
end

function PANEL:Change(callback)
    if self.ReadOnly then
        self:Report('Packed sources are read-only. Create an editable copy first.')
        return
    end
    self:StopPreviewAudio()
    self:PushHistory()
    callback()
    self.Dirty = true
    self:RefreshAll()
end

function PANEL:Undo()
    local previous = table.remove(self.UndoStack)
    if not previous then return end
    self:StopPreviewAudio()
    table.insert(self.RedoStack, ANN.DeepCopy(self.Source))
    self.Source = previous
    self.Dirty = true
    self.Selection = {kind = 'pack'}
    self:RefreshAll()
end

function PANEL:Redo()
    local nextSource = table.remove(self.RedoStack)
    if not nextSource then return end
    self:StopPreviewAudio()
    table.insert(self.UndoStack, ANN.DeepCopy(self.Source))
    self.Source = nextSource
    self.Dirty = true
    self.Selection = {kind = 'pack'}
    self:RefreshAll()
end

function PANEL:ReplaceSource(source, origin, readOnly)
    self:StopPreviewAudio()
    self.Source = ANN.DeepCopy(source)
    self.Origin = origin
    self.ReadOnly = readOnly and true or false
    self.Dirty = false
    self.UndoStack = {}
    self.RedoStack = {}
    self.Selection = {kind = 'pack'}
    self:RefreshAll()
end

function PANEL:ConfirmDiscard(callback)
    if not self.Dirty then callback() return end
    Derma_Query('Discard unsaved annunciator changes?', 'Unsaved annunciator source',
        'Discard', callback, 'Cancel')
end

function PANEL:OpenSources()
    if IsValid(self.SourceWindow) then
        self.SourceWindow:MakePopup()
        self.SourceWindow:RequestFocus()
        return
    end
    local frame = vgui.Create('DFrame')
    self.SourceWindow = frame
    frame:SetTitle('Annunciator Sources')
    frame:SetSize(760, 540)
    frame:Center()
    frame:SetSizable(true)
    frame:MakePopup()

    local search = frame:Add('DTextEntry')
    search:Dock(TOP)
    search:DockMargin(6, 6, 6, 4)
    search:SetPlaceholderText('Search packed and draft annunciator sources...')

    local list = frame:Add('DListView')
    list:Dock(FILL)
    list:DockMargin(6, 0, 6, 4)
    list:AddColumn('Kind'):SetFixedWidth(80)
    list:AddColumn('File'):SetFixedWidth(220)
    list:AddColumn('Path')

    local controls = frame:Add('DPanel')
    controls:Dock(BOTTOM)
    controls:SetTall(36)

    local function button(text, width, callback)
        local control = controls:Add('DButton')
        control:Dock(LEFT)
        control:DockMargin(4, 4, 0, 4)
        control:SetWide(width)
        control:SetText(text)
        control.DoClick = callback
        return control
    end

    local function selectedEntry()
        local line = list:GetSelectedLine()
        local row = line and list:GetLine(line)
        return row and row.LuasquareEntry
    end

    local function loadEntry(entry, editableCopy)
        if not entry then self:Report('Select a source to load.') return end
        local source = entry.realm == 'GAME' and ANN.EditorCatalog.sources[entry.path]
            or util.JSONToTable(file.Read(entry.path, entry.realm) or '')
        if type(source) ~= 'table' then
            self:Report('Unable to read source: ' .. tostring(entry.path))
            return
        end
        self:ConfirmDiscard(function()
            if not IsValid(self) then return end
            self:StopPreviewAudio()
            self:ReplaceSource(source, editableCopy and '<copy of ' .. entry.path .. '>' or entry.path,
                editableCopy and false or entry.readOnly)
            if editableCopy then self.Dirty = true end
            if IsValid(frame) then frame:Close() end
        end)
    end

    local function rebuild()
        list:Clear()
        local needle = string.lower(search:GetValue() or '')
        for _, entry in ipairs(draftEntries()) do
            if needle == '' or string.find(string.lower(entry.label .. ' ' .. entry.path), needle, 1, true) then
                local kind = entry.readOnly and 'Packed' or 'Draft'
                local row = list:AddLine(kind, string.GetFileFromFilename(entry.path), entry.path)
                row.LuasquareEntry = entry
            end
        end
        if LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.ApplyTree(frame) end
    end

    button('Load selected', 108, function() loadEntry(selectedEntry(), false) end)
    button('Editable copy', 104, function() loadEntry(selectedEntry(), true) end)
    button('New pack', 82, function()
        self:ConfirmDiscard(function()
            if not IsValid(self) then return end
            self:StopPreviewAudio()
            self:ReplaceSource(defaultSource(), '<new>', false)
            if IsValid(frame) then frame:Close() end
        end)
    end)
    button('Save current draft', 132, function() self:SaveDraft() rebuild() end)
    search.OnValueChange = rebuild
    list.DoDoubleClick = function(_, _, row) loadEntry(row.LuasquareEntry, false) end
    frame.OnRemove = function() if IsValid(self) then self.SourceWindow = nil end end
    rebuild()
    if LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.ApplyEditor(frame, {controls}) end
end

function PANEL:SaveDraft()
    if self.ReadOnly then
        self:Report('Create an editable copy before saving.')
        return
    end
    local compiled = self:Validate(true)
    if not compiled then return end
    local root = ANN.DraftRoot .. '/' .. mapName()
    file.CreateDir(ANN.DraftRoot)
    file.CreateDir(root)
    local path = root .. '/' .. safeName(self.Source.id) .. '.json'
    file.Write(path, ANN.CanonicalJSON(self.Source, true) .. '\n')
    self.Origin = path
    self.Dirty = false
    SetClipboardText('data/' .. path)
    self:Report('Canonical draft saved to data/' .. path .. '; path copied.')
end

function PANEL:Validate(notify)
    local compiled, diagnostics = ANN.CompileSource(self.Source, self.Origin)
    self.Diagnostics:SetValue(ANN.DiagnosticsText(diagnostics))
    if notify then
        self:Report(compiled and 'Annunciator source is valid.'
            or 'Annunciator source has errors; see Diagnostics.')
    end
    return compiled
end

function PANEL:RefreshAll()
    self:RebuildHierarchy()
    self:RebuildInspector()
    self:Validate(false)
    timer.Simple(0, function()
        if IsValid(self) and LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.ApplyTree(self) end
    end)
end

function PANEL:RebuildHierarchy()
    self.Hierarchy:Clear()
    local root = self.Hierarchy:AddNode(self.Source.label or self.Source.id or 'Pack')
    root.LuasquareSelection = {kind = 'pack'}
    local groupIds = {}
    for id in pairs(self.Source.groups or {}) do table.insert(groupIds, id) end
    table.sort(groupIds)
    for _, groupId in ipairs(groupIds) do
        local group = self.Source.groups[groupId]
        local groupNode = root:AddNode(group.label or groupId)
        groupNode.LuasquareSelection = {kind = 'group', id = groupId}
        local alarmIds = {}
        for alarmId, alarm in pairs(self.Source.alarms or {}) do
            if alarm.group == groupId then table.insert(alarmIds, alarmId) end
        end
        table.sort(alarmIds)
        for _, alarmId in ipairs(alarmIds) do
            local alarm = self.Source.alarms[alarmId]
            local node = groupNode:AddNode(alarm.label or alarmId)
            node.LuasquareSelection = {kind = 'alarm', id = alarmId}
        end
        groupNode:SetExpanded(true)
    end
    root:SetExpanded(true)
end

function PANEL:GetSelectedAlarm()
    return self.Selection.kind == 'alarm' and self.Source.alarms[self.Selection.id] or nil
end

function PANEL:AddGroup()
    self:Change(function()
        local index, id = 1, 'new_group'
        while self.Source.groups[id] do index = index + 1 id = 'new_group_' .. index end
        self.Source.groups[id] = {
            label = 'New Group',
            muteSeconds = 60,
            soundOrigin = {position = {0, 0, 0}}
        }
        self.Selection = {kind = 'group', id = id}
    end)
end

function PANEL:AddAlarm()
    local group = self.Selection.kind == 'group' and self.Selection.id
        or next(self.Source.groups or {})
    if not group then return end
    self:Change(function()
        local index, id = 1, 'new_alarm'
        while self.Source.alarms[id] do index = index + 1 id = 'new_alarm_' .. index end
        self.Source.alarms[id] = defaultAlarm(group)
        self.Selection = {kind = 'alarm', id = id}
    end)
end

function PANEL:DeleteSelection()
    local selection = self.Selection
    if selection.kind == 'pack' then return end
    self:Change(function()
        if selection.kind == 'alarm' then
            self.Source.alarms[selection.id] = nil
        elseif selection.kind == 'group' then
            for id, alarm in pairs(self.Source.alarms) do
                if alarm.group == selection.id then self.Source.alarms[id] = nil end
            end
            self.Source.groups[selection.id] = nil
        end
        self.Selection = {kind = 'pack'}
    end)
end

function PANEL:AddLabel(text)
    local label = self.Right:Add('DLabel')
    label:Dock(TOP)
    label:DockMargin(6, 6, 6, 1)
    label:SetText(text)
    label:SetTextColor(Color(225, 225, 225))
    return label
end

function PANEL:AddTextField(labelText, object, key)
    self:AddLabel(labelText)
    local entry = self.Right:Add('DTextEntry')
    entry:Dock(TOP)
    entry:DockMargin(6, 0, 6, 2)
    entry:SetValue(tostring(object[key] or ''))
    entry:SetEditable(not self.ReadOnly)
    entry.OnEnter = function(input)
        local value = input:GetValue()
        self:Change(function() object[key] = value ~= '' and value or nil end)
    end
    return entry
end

function PANEL:AddNumber(labelText, object, key, minimum, maximum)
    local slider = self.Right:Add('DNumSlider')
    slider:Dock(TOP)
    slider:DockMargin(6, 2, 6, 2)
    slider:SetText(labelText)
    slider:SetMin(minimum)
    slider:SetMax(maximum)
    slider:SetDecimals(2)
    slider:SetValue(tonumber(object[key]) or minimum)
    slider:SetEnabled(not self.ReadOnly)
    slider.OnValueChanged = function(input, value)
        if input.LuasquareLoading then return end
        input.LuasquareLoading = true
        timer.Simple(0.25, function()
            if not IsValid(input) then return end
            input.LuasquareLoading = false
            self:Change(function() object[key] = tonumber(input:GetValue()) end)
        end)
    end
end

function PANEL:AddChoice(labelText, object, key, choices)
    self:AddLabel(labelText)
    local combo = self.Right:Add('DComboBox')
    combo:Dock(TOP)
    combo:DockMargin(6, 0, 6, 2)
    combo:SetValue(tostring(object[key] or ''))
    combo:SetEnabled(not self.ReadOnly)
    for _, choice in ipairs(choices) do combo:AddChoice(tostring(choice), choice) end
    combo.OnSelect = function(_, _, _, value)
        self:Change(function() object[key] = value end)
    end
    return combo
end

function PANEL:AddJSON(labelText, object, key)
    self:AddLabel(labelText .. ' (structured JSON)')
    local entry = self.Right:Add('DTextEntry')
    entry:Dock(TOP)
    entry:DockMargin(6, 0, 6, 2)
    entry:SetTall(100)
    entry:SetMultiline(true)
    entry:SetEditable(not self.ReadOnly)
    entry:SetValue(ANN.CanonicalJSON(object[key] or {}, true))
    local apply = self.Right:Add('DButton')
    apply:Dock(TOP)
    apply:DockMargin(6, 0, 6, 4)
    apply:SetText('Apply ' .. labelText)
    apply:SetEnabled(not self.ReadOnly)
    apply.DoClick = function()
        local wrapped = util.JSONToTable('{"value":' .. entry:GetValue() .. '}')
        if type(wrapped) ~= 'table' or wrapped.value == nil then
            self:Report('Invalid JSON for ' .. labelText .. '.')
            return
        end
        self:Change(function() object[key] = wrapped.value end)
    end
end

function PANEL:AddColorPicker(alarm)
    self:AddLabel('Color override')
    local mixer = self.Right:Add('DColorMixer')
    mixer:Dock(TOP)
    mixer:DockMargin(6, 0, 6, 2)
    mixer:SetTall(170)
    mixer:SetPalette(true)
    mixer:SetAlphaBar(true)
    mixer:SetWangs(true)
    mixer:SetColor(tierColor(alarm))
    mixer:SetEnabled(not self.ReadOnly)

    local controls = self.Right:Add('DPanel')
    controls:Dock(TOP)
    controls:DockMargin(6, 0, 6, 4)
    controls:SetTall(26)
    if LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.Apply(controls, 'panel') end
    local apply = controls:Add('DButton')
    apply:Dock(LEFT)
    apply:SetWide(190)
    apply:SetText('Apply color override')
    apply:SetEnabled(not self.ReadOnly)
    apply.DoClick = function()
        local color = mixer:GetColor()
        self:Change(function() alarm.color = {color.r, color.g, color.b, color.a} end)
    end
    local reset = controls:Add('DButton')
    reset:Dock(FILL)
    reset:DockMargin(4, 0, 0, 0)
    reset:SetText('Use tier color')
    reset:SetEnabled(not self.ReadOnly)
    reset.DoClick = function() self:Change(function() alarm.color = nil end) end
end

function PANEL:AddSoundField(alarm)
    self:AddLabel('Registered sound ID')
    local row = self.Right:Add('DPanel')
    row:Dock(TOP)
    row:DockMargin(6, 0, 6, 2)
    row:SetTall(26)
    if LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.Apply(row, 'panel') end
    local entry = row:Add('DTextEntry')
    entry:Dock(FILL)
    entry:SetEditable(false)
    entry:SetValue(tostring(alarm.audio.sound or ''))
    local browse = row:Add('DButton')
    browse:Dock(RIGHT)
    browse:DockMargin(4, 0, 0, 0)
    browse:SetWide(92)
    browse:SetText('Browse...')
    browse:SetEnabled(not self.ReadOnly)
    browse.DoClick = function()
        local audioEditor = LUASQUARE_AUDIO and LUASQUARE_AUDIO.Editor
        if not audioEditor or not audioEditor.OpenIdPicker then
            self:Report('The Audio registry browser is not available.')
            return
        end
        audioEditor.OpenIdPicker('Select registered annunciator sound',
            ANN.EditorCatalog.sounds or {}, function(id)
                if not IsValid(self) then return end
                self:Change(function() alarm.audio.sound = id end)
            end, function(definition)
                return definition.mode == 'source' or definition.mode == 'global'
            end)
    end

    local preview = self.Right:Add('DButton')
    preview:Dock(TOP)
    preview:DockMargin(6, 0, 6, 4)
    preview:SetText('Play / stop selected sound')
    preview.DoClick = function()
        if self.PreviewAudio or (self.PreviewTimer and timer.Exists(self.PreviewTimer)) then
            self:StopPreviewAudio()
        else
            self:PlayPreviewAudio(false)
        end
    end
end

function PANEL:AddConditionBuilder(alarm, key, labelText, optional)
    key = key or 'condition'
    labelText = labelText or 'Activation condition'
    local condition = alarm[key]
    if type(condition) ~= 'table' then
        local add = self.Right:Add('DButton')
        add:Dock(TOP)
        add:DockMargin(6, 4, 6, 4)
        add:SetText('Add ' .. labelText)
        add:SetEnabled(not self.ReadOnly)
        add.DoClick = function()
            self:Change(function()
                alarm[key] = {provider = '', path = '', op = 'truthy'}
            end)
        end
        return
    end
    if optional then
        local remove = self.Right:Add('DButton')
        remove:Dock(TOP)
        remove:DockMargin(6, 4, 6, 2)
        remove:SetText('Remove ' .. labelText)
        remove:SetEnabled(not self.ReadOnly)
        remove.DoClick = function()
            self:Change(function() alarm[key] = nil end)
        end
    end
    if type(condition) ~= 'table' or not condition.provider then
        self:AddJSON(labelText, alarm, key)
        return
    end
    self:AddLabel(labelText .. ' provider')
    local provider = self.Right:Add('DComboBox')
    provider:Dock(TOP)
    provider:DockMargin(6, 0, 6, 2)
    provider:SetValue(condition.provider or '')
    provider:SetEnabled(not self.ReadOnly)
    for id, definition in pairs(ANN.EditorCatalog.providers or {}) do
        provider:AddChoice(definition.label or id, id)
    end
    provider.OnSelect = function(_, _, _, id)
        self:Change(function() condition.provider = id condition.path = '' end)
    end
    self:AddLabel(labelText .. ' path')
    local path = self.Right:Add('DComboBox')
    path:Dock(TOP)
    path:DockMargin(6, 0, 6, 2)
    path:SetValue(condition.path or '')
    path:SetEnabled(not self.ReadOnly)
    local definition = ANN.EditorCatalog.providers
        and ANN.EditorCatalog.providers[condition.provider]
    for _, field in ipairs(definition and definition.fields or {}) do
        path:AddChoice(field.label or field.path, field.path)
    end
    path.OnSelect = function(_, _, _, value)
        self:Change(function() condition.path = value end)
    end
    self:AddChoice('Operator', condition, 'op',
        {'eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'truthy'})
    if condition.op ~= 'truthy' then
        self:AddLabel('Comparison value')
        local valueEntry = self.Right:Add('DTextEntry')
        valueEntry:Dock(TOP)
        valueEntry:DockMargin(6, 0, 6, 2)
        valueEntry:SetValue(condition.value == nil and '' or tostring(condition.value))
        valueEntry:SetEditable(not self.ReadOnly)
        local apply = self.Right:Add('DButton')
        apply:Dock(TOP)
        apply:DockMargin(6, 0, 6, 4)
        apply:SetText('Apply comparison value')
        apply:SetEnabled(not self.ReadOnly)
        apply.DoClick = function()
            self:Change(function()
                condition.value = leafValue(valueEntry:GetValue())
            end)
        end
    end
    self:AddJSON('Advanced ' .. string.lower(labelText), alarm, key)
end

function PANEL:AddMessageBuilder(alarm)
    local binding = alarm.message
    if type(binding) ~= 'table' or not binding.provider then
        self:AddJSON('Message / message binding', alarm, 'message')
        local useBinding = self.Right:Add('DButton')
        useBinding:Dock(TOP)
        useBinding:DockMargin(6, 0, 6, 4)
        useBinding:SetText('Use provider message binding')
        useBinding:SetEnabled(not self.ReadOnly)
        useBinding.DoClick = function()
            self:Change(function() alarm.message = {provider = '', path = '', default = alarm.label} end)
        end
        return
    end
    self:AddLabel('Message provider')
    local provider = self.Right:Add('DComboBox')
    provider:Dock(TOP)
    provider:DockMargin(6, 0, 6, 2)
    provider:SetValue(binding.provider)
    provider:SetEnabled(not self.ReadOnly)
    for id, definition in pairs(ANN.EditorCatalog.providers or {}) do
        provider:AddChoice(definition.label or id, id)
    end
    provider.OnSelect = function(_, _, _, id)
        self:Change(function() binding.provider = id binding.path = '' end)
    end
    self:AddLabel('Message path')
    local path = self.Right:Add('DComboBox')
    path:Dock(TOP)
    path:DockMargin(6, 0, 6, 2)
    path:SetValue(binding.path or '')
    path:SetEnabled(not self.ReadOnly)
    local definition = ANN.EditorCatalog.providers
        and ANN.EditorCatalog.providers[binding.provider]
    for _, field in ipairs(definition and definition.fields or {}) do
        path:AddChoice(field.label or field.path, field.path)
    end
    path.OnSelect = function(_, _, _, value)
        self:Change(function() binding.path = value end)
    end
    self:AddTextField('Message fallback', binding, 'default')
    local static = self.Right:Add('DButton')
    static:Dock(TOP)
    static:DockMargin(6, 0, 6, 4)
    static:SetText('Use static alarm label')
    static:SetEnabled(not self.ReadOnly)
    static.DoClick = function()
        self:Change(function() alarm.message = alarm.label end)
    end
end

function PANEL:AddPropDiscovery(alarm, parent)
    parent = parent or self.Right
    local label = parent:Add('DLabel')
    label:Dock(TOP)
    label:DockMargin(0, 5, 0, 1)
    label:SetText('Detected ANN_<GROUP>_<alarm> props')
    label:SetTextColor(Color(225, 225, 225))
    local combo = parent:Add('DComboBox')
    combo:Dock(TOP)
    combo:DockMargin(0, 0, 0, 2)
    combo:SetValue('Select detected prop')
    combo:SetEnabled(not self.ReadOnly)
    for _, prop in ipairs(ANN.EditorCatalog.props or {}) do
        combo:AddChoice(prop.targetname .. ' · ' .. tostring(prop.model), prop)
    end
    combo.OnSelect = function(_, _, _, prop)
        if type(prop) ~= 'table' then return end
        self:Change(function()
            alarm.indicator = alarm.indicator or {}
            alarm.indicator.targetnames = alarm.indicator.targetnames or {}
            table.insert(alarm.indicator.targetnames, prop.targetname)
            alarm.indicator.expectedModel = prop.model
        end)
    end
end

function PANEL:AddAdvancedIndicator(alarm)
    local category = self.Right:Add('DCollapsibleCategory')
    category:Dock(TOP)
    category:DockMargin(6, 5, 6, 4)
    category:SetLabel('Advanced indicator binding')
    category:SetExpanded(false)
    local content = vgui.Create('DPanel', category)
    content:DockPadding(6, 4, 6, 6)
    content:SetTall(332)
    if LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.Apply(content, 'panel') end
    category:SetContents(content)

    local targetLabel = content:Add('DLabel')
    targetLabel:Dock(TOP)
    targetLabel:SetText('Explicit targetnames (one per line or comma-separated)')
    targetLabel:SetTextColor(Color(225, 225, 225))
    local targets = content:Add('DTextEntry')
    targets:Dock(TOP)
    targets:SetTall(54)
    targets:SetMultiline(true)
    targets:SetEditable(not self.ReadOnly)
    targets:SetValue(table.concat(alarm.indicator.targetnames or {}, '\n'))
    local applyTargets = content:Add('DButton')
    applyTargets:Dock(TOP)
    applyTargets:DockMargin(0, 2, 0, 4)
    applyTargets:SetText('Apply explicit targetnames')
    applyTargets:SetEnabled(not self.ReadOnly)
    applyTargets.DoClick = function()
        local parsed, seen = {}, {}
        for targetname in string.gmatch(targets:GetValue(), '[^,%s]+') do
            if targetname ~= '' and not seen[targetname] then
                seen[targetname] = true
                table.insert(parsed, targetname)
            end
        end
        self:Change(function() alarm.indicator.targetnames = parsed end)
    end

    local skinLabel = content:Add('DLabel')
    skinLabel:Dock(TOP)
    skinLabel:SetText('Skin mapping JSON')
    skinLabel:SetTextColor(Color(225, 225, 225))
    local skins = content:Add('DTextEntry')
    skins:Dock(TOP)
    skins:SetTall(84)
    skins:SetMultiline(true)
    skins:SetEditable(not self.ReadOnly)
    skins:SetValue(ANN.CanonicalJSON(alarm.indicator.skins or {}, true))
    local applySkins = content:Add('DButton')
    applySkins:Dock(TOP)
    applySkins:DockMargin(0, 2, 0, 4)
    applySkins:SetText('Apply skin mapping')
    applySkins:SetEnabled(not self.ReadOnly)
    applySkins.DoClick = function()
        local wrapped = util.JSONToTable('{"value":' .. skins:GetValue() .. '}')
        if type(wrapped) ~= 'table' or type(wrapped.value) ~= 'table' then
            self:Report('Invalid indicator skin mapping JSON.')
            return
        end
        self:Change(function() alarm.indicator.skins = wrapped.value end)
    end
    self:AddPropDiscovery(alarm, content)
end

function PANEL:AddModelPreview(alarm)
    local models = file.Find('models/luasquare/ann/*.mdl', 'GAME')
    self:AddLabel('Indicator model preview')
    local combo = self.Right:Add('DComboBox')
    combo:Dock(TOP)
    combo:DockMargin(6, 0, 6, 2)
    for _, name in ipairs(models or {}) do
        combo:AddChoice(name, 'models/luasquare/ann/' .. name)
    end
    combo:SetEnabled(not self.ReadOnly)
    local preview = self.Right:Add('DModelPanel')
    preview:Dock(TOP)
    preview:DockMargin(6, 0, 6, 4)
    preview:SetTall(210)
    preview:SetFOV(32)
    preview:SetAnimated(false)
    preview:SetAmbientLight(Color(90, 90, 90))
    preview:SetDirectionalLight(BOX_FRONT, Color(255, 255, 255))
    preview:SetDirectionalLight(BOX_TOP, Color(140, 140, 140))
    preview.LayoutEntity = function(_, entity) entity:SetAngles(angle_zero) end
    local initial = alarm.indicator and alarm.indicator.expectedModel
        or (models and models[1] and 'models/luasquare/ann/' .. models[1])

    local function frameModel()
        if not IsValid(preview) then return end
        local entity = preview:GetEntity()
        if not IsValid(entity) then return end
        entity:SetAngles(angle_zero)
        entity:SetSkin(tonumber(alarm.indicator.skins and alarm.indicator.skins.on) or 0)
        local mins, maxs = entity:GetRenderBounds()
        local center = (mins + maxs) * 0.5
        local size = maxs - mins
        local direction, width, height = Vector(1, 0, 0), size.y, size.z
        if size.y <= size.x and size.y <= size.z then
            direction, width, height = Vector(0, 1, 0), size.x, size.z
        elseif size.z <= size.x and size.z <= size.y then
            direction, width, height = Vector(0, 0, 1), size.x, size.y
        end
        if preview.LuasquareFlipFace then direction = direction * -1 end
        local span = math.max(width, height, 1)
        local distance = span * 0.5 / math.tan(math.rad(preview:GetFOV() * 0.5)) * 1.15
        preview:SetLookAt(center)
        preview:SetCamPos(center + direction * distance)
    end

    local function setModel(path)
        preview:SetModel(path)
        timer.Simple(0, frameModel)
    end
    if initial then
        combo:SetValue(string.GetFileFromFilename(initial))
        setModel(initial)
    end
    combo.OnSelect = function(_, _, _, path)
        setModel(path)
        if not self.ReadOnly then
            self:Change(function()
                alarm.indicator = alarm.indicator or {}
                alarm.indicator.expectedModel = path
            end)
        end
    end
    local flip = self.Right:Add('DButton')
    flip:Dock(TOP)
    flip:DockMargin(6, 0, 6, 4)
    flip:SetText('Flip preview face')
    flip.DoClick = function()
        preview.LuasquareFlipFace = not preview.LuasquareFlipFace
        frameModel()
    end
end

function PANEL:RebuildInspector()
    self.Right:Clear()
    local selection = self.Selection
    if selection.kind == 'pack' then
        self:AddTextField('Pack ID', self.Source, 'id')
        self:AddTextField('Pack label', self.Source, 'label')
        return
    end
    if selection.kind == 'group' then
        local group = self.Source.groups[selection.id]
        if not group then return end
        self:AddLabel('Group ID: ' .. selection.id)
        self:AddTextField('Label', group, 'label')
        self:AddNumber('Default mute seconds', group, 'muteSeconds', 0, 3600)
        self:AddJSON('Fallback sound origin', group, 'soundOrigin')
        self:AddJSON('Group defaults', group, 'defaults')
        return
    end
    local alarm = self.Source.alarms[selection.id]
    if not alarm then return end
    alarm.indicator = alarm.indicator or {
        targetnames = {},
        skins = {off = 0, fast_flash = 1, on = 2, slow_flash = 3}
    }
    self:AddLabel('Alarm ID: ' .. selection.id)
    self:AddTextField('Label', alarm, 'label')
    self:AddChoice('Group', alarm, 'group', table.GetKeys(self.Source.groups or {}))
    self:AddChoice('Tier', alarm, 'tier', {1, 2, 3, 4})
    self:AddConditionBuilder(alarm, 'condition', 'Activation condition', false)
    self:AddConditionBuilder(alarm, 'clearCondition', 'Clear condition', true)
    self:AddMessageBuilder(alarm)
    self:AddNumber('Re-alarm seconds', alarm, 'reAlarmSeconds', 0, 86400)
    self:AddColorPicker(alarm)
    self:AddAdvancedIndicator(alarm)
    self:AddModelPreview(alarm)
    alarm.audio = alarm.audio or {}
    self:AddLabel('Audio policy')
    self:AddSoundField(alarm)
    self:AddChoice('Sound mode', alarm.audio, 'mode', {'once', 'loop', 'repeat'})
    self:AddNumber('Repeat seconds', alarm.audio, 'repeatSeconds', 0.25, 3600)
    self:AddNumber('Pitch override', alarm.audio, 'pitch', 1, 255)
    local ack = self.Right:Add('DCheckBoxLabel')
    ack:Dock(TOP)
    ack:DockMargin(6, 4, 6, 4)
    ack:SetText('ACK silences audio')
    ack:SetValue(alarm.audio.ackSilences ~= false and 1 or 0)
    ack:SetEnabled(not self.ReadOnly)
    ack.OnChange = function(_, value)
        self:Change(function() alarm.audio.ackSilences = value and true or false end)
    end
end

vgui.Register('LuasquareAnnunciatorEditor', PANEL, 'DFrame')

function EDITOR.Open()
    if not game.SinglePlayer() and (not IsValid(LocalPlayer()) or not LocalPlayer():IsAdmin()) then
        print('[LUASQUARE_ANNUNCIATOR_EDITOR] The Annunciator Editor requires admin access.')
        return nil
    end
    if IsValid(EDITOR.Frame) then
        EDITOR.Frame:MakePopup()
        EDITOR.Frame:RequestFocus()
        return EDITOR.Frame
    end
    EDITOR.Frame = vgui.Create('LuasquareAnnunciatorEditor')
    EDITOR.Frame:MakePopup()
    return EDITOR.Frame
end

hook.Add('LuasquareAnnunciatorCatalog', 'LUASQUARE_ANNUNCIATOR_EditorCatalog', function()
    if IsValid(EDITOR.Frame) then
        EDITOR.Frame:StopPreviewAudio()
        EDITOR.Frame:RefreshAll()
    end
end)
