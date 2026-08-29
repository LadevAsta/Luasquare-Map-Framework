if not CLIENT then return end
local AUDIO, EDITOR = LUASQUARE_AUDIO, LUASQUARE_AUDIO.Editor

local function newSource()
    return EDITOR.LoadMasterSource('sounds')
end

EDITOR.SoundSearchIndex = EDITOR.SoundSearchIndex or {paths = {}, pathSet = {}, directories = {}, head = 1,
    directorySet = {}, building = false, built = false, revision = 0}

local function normalizeSoundPath(path)
    path = string.gsub(tostring(path or ''), '\\', '/')
    path = string.gsub(path, '^GAME/', '') path = string.gsub(path, '^sound/', '')
    local extension = string.lower(string.GetExtensionFromFilename(path) or '')
    if extension ~= 'wav' and extension ~= 'mp3' and extension ~= 'ogg' then return nil end
    return AUDIO.IsSafePath(path) and path or nil
end

local function startSoundIndex()
    local index = EDITOR.SoundSearchIndex
    if index.built or index.building then return index end
    index.paths, index.pathSet, index.directories = {}, {}, {'sound'}
    index.head, index.directorySet, index.building, index.built = 1, {sound = true}, true, false
    index.revision = index.revision + 1
    timer.Create('LUASQUARE_AUDIO_SoundSearchIndex', 0, 0, function()
        local changed = false
        for _ = 1, 12 do
            local directory = index.directories[index.head] index.head = index.head + 1
            if not directory then
                index.building, index.built = false, true table.sort(index.paths)
                index.directories, index.directorySet, index.head = {}, {}, 1
                index.revision = index.revision + 1 timer.Remove('LUASQUARE_AUDIO_SoundSearchIndex') return
            end
            local files, folders = file.Find(directory .. '/*', 'GAME')
            for _, name in ipairs(files or {}) do
                local path = normalizeSoundPath(directory .. '/' .. name)
                if path and not index.pathSet[path] then
                    index.pathSet[path] = true table.insert(index.paths, path) changed = true
                end
            end
            for _, name in ipairs(folders or {}) do
                local child = directory .. '/' .. name
                if not index.directorySet[child] then index.directorySet[child] = true table.insert(index.directories, child) end
            end
        end
        if changed then index.revision = index.revision + 1 end
    end)
    return index
end

local function openBrowser(callback)
    local frame = vgui.Create('DFrame')
    frame:SetTitle('GAME/sound browser') frame:SetSize(760, 600) frame:Center()
    frame:MakePopup() frame:SetSizable(true) frame:SetDraggable(true)
    EDITOR.RegisterSubwindow(frame)
    local search = vgui.Create('DTextEntry', frame) search:Dock(TOP) search:DockMargin(6, 6, 6, 4)
    search:SetPlaceholderText('Search every mounted WAV, MP3, and OGG path...')
    local use = vgui.Create('DButton', frame) use:Dock(BOTTOM) use:DockMargin(6, 2, 6, 6)
    use:SetTall(28) use:SetText('Use sound path')
    local pathEntry = vgui.Create('DTextEntry', frame) pathEntry:Dock(BOTTOM) pathEntry:DockMargin(6, 2, 6, 2)
    pathEntry:SetPlaceholderText('Path relative to sound/')
    local status = vgui.Create('DLabel', frame) status:Dock(BOTTOM) status:SetTall(20)
    status:SetTextColor(Color(220, 220, 220)) status:DockMargin(6, 0, 6, 0)
    local content = vgui.Create('DPanel', frame) content:Dock(FILL) content:DockMargin(6, 0, 6, 2)
    local browser = vgui.Create('DFileBrowser', content) browser:Dock(FILL)
    browser:SetPath('GAME') browser:SetBaseFolder('sound') browser:SetOpen(false)
    local list = vgui.Create('DListView', content) list:Dock(FILL) list:SetVisible(false) list:AddColumn('Search results')
    local selected, shownRevision, nextRefresh
    local function select(path)
        selected = normalizeSoundPath(path)
        pathEntry:SetValue(selected or tostring(path or ''))
        status:SetText(selected and ('Selected: ' .. selected) or 'Select a WAV, MP3, or OGG file.')
        return selected ~= nil
    end
    browser.OnSelect = function(_, path) select(path) end
    browser.OnDoubleClick = function(_, path) if select(path) then callback(selected) frame:Close() end end
    list.OnRowSelected = function(_, _, row) select(row.SoundPath) end
    list.DoDoubleClick = function(_, _, row) if select(row.SoundPath) then callback(selected) frame:Close() end end
    pathEntry.OnValueChange = function(self) selected = normalizeSoundPath(self:GetValue()) end
    pathEntry.OnEnter = function() if selected then callback(selected) frame:Close() end end
    use.DoClick = function() if select(pathEntry:GetValue()) then callback(selected) frame:Close() end end
    local function rebuild()
        local needle = string.lower(string.Trim(search:GetValue()))
        local searching = needle ~= ''
        browser:SetVisible(not searching) list:SetVisible(searching)
        if not searching then status:SetText('Browse folded folders or enter a global search.') return end
        local index = startSoundIndex() list:Clear() local count = 0
        for _, path in ipairs(index.paths) do
            if string.find(string.lower(path), needle, 1, true) then
                local row = list:AddLine(path) row.SoundPath = path count = count + 1
                if count >= 750 then break end
            end
        end
        status:SetText(index.building and string.format('Indexing... %d sounds found', #index.paths)
            or string.format('%d result(s)%s', count, count >= 750 and ' (capped)' or ''))
        shownRevision = index.revision
    end
    search.OnValueChange = rebuild
    content.Think = function()
        if search:GetValue() == '' or RealTime() < (nextRefresh or 0) then return end
        nextRefresh = RealTime() + 0.2
        local index = EDITOR.SoundSearchIndex
        if index.revision ~= shownRevision then rebuild() end
    end
    frame.OnRemove = function()
        local index = EDITOR.SoundSearchIndex
        if index.building and timer.Exists('LUASQUARE_AUDIO_SoundSearchIndex') then
            timer.Remove('LUASQUARE_AUDIO_SoundSearchIndex') index.building = false
        end
    end
    rebuild()
    if LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.ApplyTree(frame) end
end

local function body(frame, panel)
    local split = vgui.Create('DHorizontalDivider', panel) split:Dock(FILL) split:SetDividerWidth(5) split:SetLeftWidth(330)
    local left = vgui.Create('DPanel', split) local right = vgui.Create('DScrollPanel', split)
    split:SetLeft(left) split:SetRight(right)
    local add = vgui.Create('DButton', left) add:Dock(TOP) add:SetText('Add sound')
    local list = vgui.Create('DListView', left) list:Dock(FILL) list:AddColumn('ID') list:AddColumn('Mode'):SetFixedWidth(65)
    for _, id in ipairs(EDITOR.SortedIds(frame.Session.source.sounds)) do
        local line = list:AddLine(id, frame.Session.source.sounds[id].mode or 'source') line.SoundId = id
        if frame.Session.selected == id then list:SelectItem(line) end
    end
    add.DoClick = function()
        EDITOR.Mutate(frame, function(source)
            local id = EDITOR.UniqueId(source.sounds, 'new_sound')
            source.sounds[id] = {label = 'New sound', mode = 'global', path = 'buttons/button14.wav',
                volume = 1, pitch = 100, channel = 'auto', soundLevel = 75, dsp = 0, duration = 1}
            frame.Session.selected = id
        end)
    end
    list.OnRowSelected = function(_, _, line) frame.Session.selected = line.SoundId frame:Rebuild() end
    local id = frame.Session.selected
    local definition = id and frame.Session.source.sounds[id]
    if not definition then EDITOR.AddLabel(right, 'Select or add a registered sound.') return end
    local function change(callback, rebuild)
        EDITOR.Push(frame.Session) callback(definition) frame.Session.dirty = true
        if rebuild then frame:Rebuild() end
    end
    EDITOR.AddLabel(right, 'SOUND DEFINITION · ' .. id)
    EDITOR.AddText(right, 'ID', id, function(value)
        local newId = AUDIO.NormalizeId(value)
        if not newId or (newId ~= id and frame.Session.source.sounds[newId]) then return end
        EDITOR.Mutate(frame, function(source)
            source.sounds[newId], source.sounds[id] = source.sounds[id], nil frame.Session.selected = newId
        end)
    end)
    EDITOR.AddText(right, 'Label', definition.label, function(value) change(function(item) item.label = value end) end)
    EDITOR.AddChoice(right, 'Mode', definition.mode, {'global', 'source', 'music'}, function(value)
        change(function(item) item.mode = value end, true)
    end)
    local referenceType = definition.script and 'sound script' or 'file path'
    EDITOR.AddChoice(right, 'Reference type', referenceType, {'file path', 'sound script'}, function(value)
        change(function(item)
            if value == 'sound script' then item.script, item.path = item.script or '', nil
            else item.path, item.script = item.path or '', nil end
        end, true)
    end)
    if definition.script ~= nil then
        EDITOR.AddText(right, 'Registered Source sound script', definition.script, function(value)
            change(function(item) item.script = value end)
        end)
    else
        EDITOR.AddText(right, 'Path relative to sound/', definition.path, function(value)
            change(function(item) item.path = value end)
        end)
        local browse = vgui.Create('DButton', right) browse:Dock(TOP) browse:DockMargin(6, 0, 6, 4)
        browse:SetText('Browse GAME/sound...') browse.DoClick = function()
            openBrowser(function(path)
                change(function(item)
                    item.path, item.script = path, nil
                    local duration = SoundDuration(path)
                    if duration and duration > 0 then item.duration = duration end
                end, true)
            end)
        end
    end
    EDITOR.AddNumber(right, 'Duration (seconds)', definition.duration or 1, 0.001, 36000, 3,
        function(value) change(function(item) item.duration = value end) end)
    EDITOR.AddNumber(right, 'Volume', definition.volume or 1, 0, 1, 3,
        function(value) change(function(item) item.volume = value end) end)
    EDITOR.AddNumber(right, 'Pitch', definition.pitch or 100, 1, 255, 0,
        function(value) change(function(item) item.pitch = value end) end)
    EDITOR.AddChoice(right, 'Source channel', definition.channel or 'auto',
        {'auto', 'weapon', 'voice', 'item', 'body', 'stream', 'static'},
        function(value) change(function(item) item.channel = value end) end)
    EDITOR.AddNumber(right, 'Sound level', definition.soundLevel or 75, 0, 180, 0,
        function(value) change(function(item) item.soundLevel = value end) end)
    EDITOR.AddNumber(right, 'DSP', definition.dsp or 0, 0, 255, 0,
        function(value) change(function(item) item.dsp = value end) end)
    EDITOR.AddCheck(right, 'Loop', definition.loop, function(value)
        change(function(item) item.loop = value end)
    end)
    EDITOR.AddText(right, 'Music bus membership (comma-separated; empty = any)',
        table.concat(definition.musicBuses or {}, ', '), function(value)
            change(function(item)
                item.musicBuses = {}
                for raw in string.gmatch(value, '[^,%s]+') do
                    local busId = AUDIO.NormalizeId(raw)
                    if busId then table.insert(item.musicBuses, busId) end
                end
            end)
        end)
    local preview = vgui.Create('DButton', right) preview:Dock(TOP) preview:DockMargin(6, 8, 6, 2)
    preview:SetText('Local preview') preview.DoClick = function()
        EDITOR.StopLocalSound(frame.AudioPreview)
        EDITOR.PlayLocalSound(definition, function(ok, handle) if ok then frame.AudioPreview = handle end end)
    end
    local stop = vgui.Create('DButton', right) stop:Dock(TOP) stop:DockMargin(6, 0, 6, 2) stop:SetText('Stop preview')
    stop.DoClick = function() EDITOR.StopLocalSound(frame.AudioPreview) frame.AudioPreview = nil end
    local remove = vgui.Create('DButton', right) remove:Dock(TOP) remove:DockMargin(6, 8, 6, 4)
    remove:SetText('Delete sound') remove.DoClick = function()
        EDITOR.Mutate(frame, function(source) source.sounds[id] = nil frame.Session.selected = nil end)
    end
end

local function openBusEditor(editor)
    if IsValid(editor.BusWindow) then editor.BusWindow:MakePopup() return end
    local frame = vgui.Create('DFrame')
    frame:SetTitle('Shared music buses') frame:SetSize(600, 440) frame:Center()
    frame:SetSizable(true) frame:SetDraggable(true) frame:MakePopup() editor.BusWindow = frame
    EDITOR.RegisterSubwindow(frame)
    local list = vgui.Create('DListView', frame) list:Dock(LEFT) list:SetWide(230) list:AddColumn('Bus ID')
    local inspector = vgui.Create('DScrollPanel', frame) inspector:Dock(FILL)
    local add = vgui.Create('DButton', list) add:Dock(BOTTOM) add:SetText('Add bus')
    local selected
    local function rebuildInspector()
        inspector:Clear() local bus = selected and editor.Session.source.musicBuses[selected]
        if not bus then EDITOR.AddLabel(inspector, 'Select or add a music bus.') return end
        EDITOR.AddLabel(inspector, 'MUSIC BUS · ' .. selected)
        EDITOR.AddText(inspector, 'Label', bus.label, function(value)
            EDITOR.Push(editor.Session) bus.label = value editor.Session.dirty = true
        end)
        EDITOR.AddNumber(inspector, 'Default volume', bus.volume or 1, 0, 1, 3, function(value)
            EDITOR.Push(editor.Session) bus.volume = value editor.Session.dirty = true
        end)
        local remove = vgui.Create('DButton', inspector) remove:Dock(TOP) remove:DockMargin(6, 8, 6, 4)
        remove:SetText('Delete bus') remove.DoClick = function()
            EDITOR.Push(editor.Session) editor.Session.source.musicBuses[selected] = nil
            editor.Session.dirty, selected = true, nil frame:RebuildList()
        end
    end
    frame.RebuildList = function()
        list:Clear()
        for _, id in ipairs(EDITOR.SortedIds(editor.Session.source.musicBuses)) do
            local row = list:AddLine(id) row.BusId = id if selected == id then list:SelectItem(row) end
        end
        rebuildInspector()
    end
    add.DoClick = function()
        EDITOR.Push(editor.Session) selected = EDITOR.UniqueId(editor.Session.source.musicBuses, 'new_bus')
        editor.Session.source.musicBuses[selected] = {label = 'New music bus', volume = 1}
        editor.Session.dirty = true frame:RebuildList()
    end
    list.OnRowSelected = function(_, _, row) selected = row.BusId rebuildInspector() end
    frame.OnRemove = function() editor.BusWindow = nil if IsValid(editor) then editor:Rebuild() end end
    frame:RebuildList()
    if LUASQUARE_EDITOR_THEME then LUASQUARE_EDITOR_THEME.ApplyTree(frame) end
end

function AUDIO.OpenSoundRegistryEditor()
    if IsValid(AUDIO.SoundRegistryEditor) then AUDIO.SoundRegistryEditor:MakePopup() return AUDIO.SoundRegistryEditor end
    EDITOR.RefreshSharedPool()
    local frame = EDITOR.BuildFrame('Luasquare Sound Registry Editor', newSource(), 'sounds', false, body)
    local baseSetSource = frame.SetSource
    frame.SetSource = function(self, ...)
        EDITOR.StopLocalSound(self.AudioPreview) self.AudioPreview = nil
        return baseSetSource(self, ...)
    end
    local buses = vgui.Create('DButton', frame.Toolbar) buses:Dock(RIGHT) buses:SetWide(105) buses:SetText('Music buses...')
    buses.DoClick = function() openBusEditor(frame) end
    frame.NewSource = function(self) self:SetSource(EDITOR.NewMasterSource('sounds')) end
    local originalRemove = frame.OnRemove
    frame.OnRemove = function(self)
        EDITOR.StopLocalSound(self.AudioPreview)
        if IsValid(self.BusWindow) then self.BusWindow:Remove() end
        if originalRemove then originalRemove(self) end
    end
    AUDIO.SoundRegistryEditor = frame return frame
end
