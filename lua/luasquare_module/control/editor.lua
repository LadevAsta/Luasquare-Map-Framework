if not CLIENT then return end
local CONTROL = LUASQUARE_CONTROL
CONTROL.Editor = CONTROL.Editor or {}
local EDITOR = CONTROL.Editor
local THEME = LUASQUARE_EDITOR_THEME

local function window(title, width, height)
    local frame = vgui.Create('DFrame')
    frame:SetTitle(title)
    frame:SetSize(width, height)
    frame:Center()
    frame:SetSizable(true)
    frame:SetDraggable(true)
    frame:SetMinWidth(math.min(width, 700))
    frame:SetMinHeight(math.min(height, 420))
    frame:MakePopup()
    THEME.ApplyEditor(frame)
    local expand = frame.btnMaxim
    expand:SetEnabled(true)
    expand:SetTooltip('Fullscreen')
    expand.DoClick = function()
        if frame.WindowBounds then
            local bounds = frame.WindowBounds
            frame:SetSize(bounds.w, bounds.h)
            frame:SetPos(bounds.x, bounds.y)
            frame.WindowBounds = nil
            expand:SetTooltip('Fullscreen')
        else
            local x, y = frame:GetPos()
            frame.WindowBounds = {x = x, y = y, w = frame:GetWide(), h = frame:GetTall()}
            frame:SetPos(0, 0)
            frame:SetSize(ScrW(), ScrH())
            expand:SetTooltip('Restore window')
        end
    end
    return frame
end

local function button(parent, text, callback)
    local control = parent:Add('DButton')
    control:Dock(TOP)
    control:SetTall(25)
    control:SetText(text)
    control.DoClick = callback
    THEME.Apply(control)
    return control
end

local function label(parent, text)
    local control = parent:Add('DLabel')
    control:Dock(TOP)
    control:SetTall(22)
    control:SetText(text)
    THEME.Apply(control)
end

local function kindLabel(kind)
    return kind == 'momentary' and 'press' or kind
end

local function assetCategory(id, value)
    if type(value) == 'table' and value.category then return value.category end
    local target = type(value) == 'table' and value.target
    if target and string.sub(target, 1, 6) == 'CTRLI_' then
        if string.sub(target, 1, 10) == 'CTRLI_KPD_' then
            local _, name = CONTROL.KeypadKeyName(target)
            return name or 'Malformed keypad key'
        end
        return string.match(target, '^CTRLI_([^_]+)_') or 'Uncategorized'
    end
    return string.match(id, '^([^%.]+)') or 'asset'
end

local function focusHoveredWindow(children)
    if input.IsMouseDown(MOUSE_LEFT) then return end
    local hovered = vgui.GetHoveredPanel()
    local underCursor = {}
    while IsValid(hovered) do
        if hovered:GetClassName() == 'DMenu' or hovered:IsModal() then return end
        underCursor[hovered] = true
        hovered = hovered:GetParent()
    end
    local candidate
    for index = #children, 1, -1 do
        local child = children[index]
        if IsValid(child) and child:IsVisible() then
            local x, y = child:LocalCursorPos()
            if x >= 0 and y >= 0 and x < child:GetWide() and y < child:GetTall() then
                candidate = candidate or child
                if underCursor[child] then candidate = child; break end
            end
        end
    end
    if candidate and not candidate:IsActive() then
        candidate:MoveToFront()
        candidate:RequestFocus()
    end
end

local function choiceField(parent, title, current, choices, callback, enabled)
    label(parent, title)
    local combo = parent:Add('DComboBox')
    combo:Dock(TOP)
    combo:SetTall(25)
    combo:SetSortItems(false)
    combo:SetEnabled(enabled ~= false)
    local selected = tostring(current or '(default)')
    for _, choice in ipairs(choices) do
        combo:AddChoice(choice.label, choice)
        if current == choice.value then selected = choice.label end
    end
    combo:SetValue(selected)
    combo.OnSelect = function(_, _, _, choice) callback(choice.value) end
    combo.OnMenuOpened = function(_, menu) THEME.ApplyTree(menu) end
    THEME.Apply(combo)
    return combo
end

function EDITOR.Open()
    if IsValid(EDITOR.Frame) then EDITOR.Frame:MakePopup(); return end
    local frame = window('Control Layer Editor - draft authoring / packed live tests', math.min(1200, ScrW() - 40), math.min(820, ScrH() - 40))
    frame:SetMinWidth(math.min(frame:GetWide(), 950))
    EDITOR.Frame = frame
    frame.Source = {schema = CONTROL.Schema, id = 'new_controls', controls = {}}
    frame.Undo, frame.Redo, frame.ReadOnly = {}, {}, false
    frame.ChildWindows = {}
    local toolbar = frame:Add('DPanel')
    toolbar:Dock(TOP)
    toolbar:SetTall(32)
    THEME.Apply(toolbar, 'panel')
    local left = frame:Add('DPanel')
    left:Dock(LEFT)
    left:SetWide(285)
    THEME.Apply(left, 'panel')
    local search = left:Add('DTextEntry')
    search:Dock(TOP)
    search:SetPlaceholderText('Search authored controls')
    THEME.Apply(search)
    frame.List = left:Add('DListView')
    frame.List:Dock(FILL)
    frame.List:AddColumn('Kind'):SetFixedWidth(80)
    frame.List:AddColumn('Control')
    local right = frame:Add('DScrollPanel')
    right:Dock(RIGHT)
    right:SetWide(325)
    THEME.Apply(right)
    frame.LiveStatus = THEME.CreateTextArea(right)
    frame.LiveStatus:Dock(TOP)
    frame.LiveStatus:SetTall(150)
    THEME.Apply(frame.LiveStatus)
    label(right, 'LIVE TESTS: affect gameplay; packed controls only')
    frame.LiveId = right:Add('DTextEntry')
    frame.LiveId:Dock(TOP)
    frame.LiveId:SetPlaceholderText('Packed control ID')
    THEME.Apply(frame.LiveId)
    button(right, 'Browse packed runtime controls', function()
        frame:Picker('Runtime controls', CONTROL.Client.controls, function(id) frame.LiveId:SetText(id) end)
    end)
    local numeric = right:Add('DTextEntry')
    numeric:Dock(TOP)
    numeric:SetPlaceholderText('Integer for submitValue')
    THEME.Apply(numeric)
    for _, operation in ipairs(CONTROL.Operations) do
        local op = operation
        button(right, 'LIVE ' .. op, function()
            local value = op == 'submitValue' and tonumber(numeric:GetValue()) or nil
            if op == 'submitValue' and not CONTROL.Finite(value) then frame:Report('Enter a valid integer.'); return end
            CONTROL.EditorCommand('request', frame.LiveId:GetValue(), op, value)
        end)
    end
    for _, command in ipairs({'lock', 'unlock', 'resetFault'}) do
        local cmd = command
        button(right, 'LIVE ' .. cmd .. ' (editor-owned locks)', function() CONTROL.EditorCommand(cmd, frame.LiveId:GetValue()) end)
    end
    button(right, 'LIVE arm one action rejection (fault fixture)', function() CONTROL.EditorCommand('armFault', frame.LiveId:GetValue()) end)
    button(right, 'Operator history', function()
        local history = window('Control operator history', 850, 500)
        table.insert(frame.ChildWindows, history)
        local list = history:Add('DListView')
        list:Dock(FILL)
        for _, heading in ipairs({'Time', 'Actor', 'Control / action', 'Value', 'Outcome'}) do list:AddColumn(heading) end
        for _, entry in ipairs(CONTROL.Client.history) do
            list:AddLine(entry.time, entry.actor, entry.label .. ' / ' .. tostring(entry.action),
                tostring(entry.oldValue or '') .. ' > ' .. tostring(entry.newValue or ''), entry.outcome .. ' ' .. (entry.reason or ''))
        end
        THEME.ApplyTree(history)
    end)
    local center = frame:Add('DPanel')
    center:Dock(FILL)
    THEME.Apply(center, 'panel')
    frame.Status = THEME.CreateTextArea(center)
    frame.Status:Dock(BOTTOM)
    frame.Status:SetTall(90)
    THEME.Apply(frame.Status)
    frame.Inspector = center:Add('DScrollPanel')
    frame.Inspector:Dock(FILL)

    function frame:Report(message)
        self.Status:SetText(message)
        print('[LUASQUARE_CONTROL EDITOR] ' .. message)
    end
    function frame:Change(callback)
        if self.ReadOnly then self:Report('Packed source is read-only. Save a draft first.'); return end
        table.insert(self.Undo, CONTROL.DeepCopy(self.Source))
        if #self.Undo > 100 then table.remove(self.Undo, 1) end
        self.Redo = {}
        callback()
        self.Dirty = true
        self:Rebuild()
    end
    function frame:ConfirmDiscard(callback)
        if not self.Dirty then callback(); return end
        Derma_Query('Discard unsaved control changes?', 'Unsaved control source', 'Discard', function()
            if IsValid(self) then callback() end
        end, 'Cancel')
    end
    local nativeClose = frame.Close
    frame.Close = function(self)
        if self.CloseApproved then return nativeClose(self) end
        self:ConfirmDiscard(function() self.CloseApproved = true; nativeClose(self) end)
    end
    function frame:Picker(title, values, callback)
        local picker = window(title, 620, 460)
        table.insert(self.ChildWindows, picker)
        local filter = picker:Add('DTextEntry')
        filter:Dock(TOP)
        filter:SetPlaceholderText('Search IDs / labels / categories')
        local list = picker:Add('DListView')
        list:Dock(FILL)
        list:AddColumn('Category'):SetFixedWidth(140)
        list:AddColumn('ID / label')
        local function refresh()
            list:Clear()
            local pool = type(values) == 'function' and values() or values
            local keys = {}
            for id in pairs(pool or {}) do table.insert(keys, id) end
            table.sort(keys)
            for _, id in ipairs(keys) do
                local value = pool[id]
                local text = id .. ' ' .. (type(value) == 'table' and (value.label or '') or '')
                if string.find(string.lower(text), string.lower(filter:GetValue()), 1, true) then
                    local line = list:AddLine(assetCategory(id, value), text)
                    line.AssetId = id
                end
            end
            THEME.ApplyTree(picker)
        end
        filter.OnChange = refresh
        list.OnRowSelected = function(_, _, line) callback(line.AssetId); picker:Close() end
        picker.Refresh = refresh
        refresh()
        return picker
    end
    function frame:Inspect()
        self.Inspector:Clear()
        local control = self.Source.controls[self.Selected or 0]
        if not control then label(self.Inspector, 'Select a control or add one.'); return end
        local function textField(title, object, key, number)
            label(self.Inspector, title)
            local entry = self.Inspector:Add('DTextEntry')
            entry:Dock(TOP)
            entry:SetText(tostring(object[key] or ''))
            entry:SetEditable(not self.ReadOnly)
            entry.OnEnter = function()
                local value = number and tonumber(entry:GetValue()) or entry:GetValue()
                if number and not CONTROL.Finite(value) then self:Report('Invalid number.'); return end
                self:Change(function()
                    object[key] = value ~= '' and value or nil
                    if object == control and key == 'target' and value == '' then control.class = nil end
                end)
            end
            THEME.Apply(entry)
        end
        textField('Stable lowercase ID (Enter to apply)', control, 'id')
        textField('Label', control, 'label')
        local function choose(title, object, key, choices, fallback)
            return choiceField(self.Inspector, title, object[key] == nil and fallback or object[key], choices,
                function(value) self:Change(function() object[key] = value end) end, not self.ReadOnly)
        end
        choiceField(self.Inspector, 'Kind', control.kind, {
            {label = 'Press', value = 'momentary'}, {label = 'Toggle', value = 'toggle'}, {label = 'Keypad', value = 'keypad'}
        }, function(kind)
            if kind == control.kind then return end
            self:Change(function()
                control.kind = kind
                local allowed = kind == 'keypad' and {submit = true} or kind == 'toggle' and {['in'] = true, out = true} or {press = true}
                for event in pairs(control.actions or {}) do if not allowed[event] then control.actions[event] = nil end end
                if kind == 'keypad' then
                    control.target, control.class, control.parent, control.initialPosition = nil, nil, nil, nil
                    control.maxDigits, control.maxValue, control.initialValue = 4, 9999, 0
                    control.clearOnSubmit = true
                    control.keys = {}
                else
                    for _, key in ipairs({'maxDigits', 'maxValue', 'initialValue', 'clearOnSubmit', 'display', 'keys'}) do control[key] = nil end
                end
            end)
            self:Report('Kind changed. Select compatible actions; Undo restores the previous definition.')
        end, not self.ReadOnly)
        if control.kind ~= 'keypad' then
            button(self.Inspector, 'Choose physical CTRLI_ button: ' .. (control.target or '(virtual)'), function()
                self.DiscoveryWindow = self:Picker('Discovered physical CTRLI_ buttons', function()
                    local values = {}
                    for _, entity in ipairs(CONTROL.Client.catalog and CONTROL.Client.catalog.entities or {}) do values[entity.target] = entity end
                    return values
                end, function(target)
                    for _, entity in ipairs(CONTROL.Client.catalog and CONTROL.Client.catalog.entities or {}) do
                        if entity.target == target then
                            if entity.diagnostic then self:Report(entity.diagnostic .. ': ' .. target); return end
                            self:Change(function() control.target, control.class = target, entity.class end)
                            return
                        end
                    end
                end)
                CONTROL.EditorCommand('subscribe')
            end):SetEnabled(not self.ReadOnly)
            textField('Manual CTRLI_ target fallback (blank = virtual)', control, 'target')
            choose('Physical class', control, 'class', {{label = 'None (virtual)', value = nil},
                {label = 'func_button', value = 'func_button'}, {label = 'func_rot_button', value = 'func_rot_button'}})
        end
        label(self.Inspector, 'Cooldown seconds')
        local cooldown = self.Inspector:Add('DNumberWang')
        cooldown:Dock(TOP)
        cooldown:SetMinMax(0, 60)
        cooldown:SetDecimals(2)
        cooldown:SetInterval(0.05)
        cooldown:SetValue(control.cooldown == nil and 0.25 or control.cooldown)
        cooldown:SetEnabled(not self.ReadOnly)
        cooldown.OnValueChanged = function(_, value)
            value = tonumber(value)
            if self.ReadOnly or not CONTROL.Finite(value) or value == control.cooldown then return end
            table.insert(self.Undo, CONTROL.DeepCopy(self.Source))
            if #self.Undo > 100 then table.remove(self.Undo, 1) end
            self.Redo, self.Dirty, control.cooldown = {}, true, math.Clamp(value, 0, 60)
        end
        THEME.Apply(cooldown)
        if control.kind == 'toggle' then
            choose('Initial position', control, 'initialPosition', {{label = 'Use physical position / default', value = nil},
                {label = 'In', value = 'in'}, {label = 'Out', value = 'out'}})
        end
        textField('Optional lock env_sprite target', control, 'lockIndicator')
        local catalog = CONTROL.Client.catalog or {}
        if control.kind == 'keypad' then
            control.keys = control.keys or {}
            button(self.Inspector, 'Choose discovered keypad / fill all keys', function()
                local groups = {}
                self.DiscoveryWindow = self:Picker('Discovered KPD keypads', function()
                    groups = {}
                    for _, entity in ipairs(CONTROL.Client.catalog and CONTROL.Client.catalog.keypadEntities or {}) do
                        if entity.key and not entity.diagnostic then
                            groups[entity.keypad] = groups[entity.keypad] or {keys = {}, category = 'Keypad'}
                            groups[entity.keypad].keys[entity.key] = entity.target
                        end
                    end
                    for _, group in pairs(groups) do
                        local count = 0
                        for _, token in ipairs(CONTROL.KeypadKeyTokens) do if token ~= 'b' and token ~= 'c' and group.keys[token] then count = count + 1 end end
                        group.label = count .. '/11 required keys'
                    end
                    return groups
                end, function(name)
                    self:Change(function() control.keys = CONTROL.DeepCopy(groups[name].keys) end)
                end)
                CONTROL.EditorCommand('subscribe')
            end):SetEnabled(not self.ReadOnly)
            for _, key in ipairs(CONTROL.KeypadKeyTokens) do
                local token = key
                local required = token ~= 'b' and token ~= 'c'
                local title = (CONTROL.KeypadKeyLabels[token] or ('Digit ' .. token)) .. (required and ' (required)' or ' (optional)')
                button(self.Inspector, 'Choose ' .. title .. ': ' .. (control.keys and control.keys[token] or '(unassigned)'), function()
                    self.DiscoveryWindow = self:Picker('KPD ' .. title, function()
                        local values = {}
                        for _, entity in ipairs(CONTROL.Client.catalog and CONTROL.Client.catalog.keypadEntities or {}) do
                            if entity.key == token then values[entity.target] = entity end
                        end
                        return values
                    end, function(target)
                        for _, entity in ipairs(CONTROL.Client.catalog and CONTROL.Client.catalog.keypadEntities or {}) do
                            if entity.target == target then
                                if entity.diagnostic then self:Report(entity.diagnostic .. ': ' .. target); return end
                                self:Change(function() control.keys = control.keys or {}; control.keys[token] = target end)
                                return
                            end
                        end
                    end)
                    CONTROL.EditorCommand('subscribe')
                end):SetEnabled(not self.ReadOnly)
                textField(title .. ' target override', control.keys, token)
            end
            local digitLimits = {}
            for value = 1, 9 do table.insert(digitLimits, {label = tostring(value), value = value}) end
            choose('Maximum digits', control, 'maxDigits', digitLimits)
            for _, key in ipairs({'maxValue', 'initialValue'}) do textField(key, control, key, true) end
            textField('SEG7 display ID', control, 'display')
            button(self.Inspector, 'Browse SEG7 displays', function() self:Picker('SEG7 displays', catalog.Displays, function(id) self:Change(function() control.display = id end) end) end)
            choose('Clear on submit', control, 'clearOnSubmit', {{label = 'Yes', value = true}, {label = 'No', value = false}}, true)
        end
        local function parameterField(title, ref, key, parameter)
            local choices = {}
            if parameter.optional or parameter.default ~= nil then table.insert(choices, {label = 'Default / unset', value = nil}) end
            if parameter.type == 'boolean' then
                table.insert(choices, {label = 'Yes', value = true}); table.insert(choices, {label = 'No', value = false})
            elseif parameter.choices then
                local keys = {}
                for value in pairs(parameter.choices) do table.insert(keys, value) end
                table.sort(keys)
                for _, value in ipairs(keys) do table.insert(choices, {label = tostring(value), value = value}) end
            elseif parameter.type == 'integer' and parameter.min and parameter.max and parameter.max - parameter.min <= 20 then
                for value = math.ceil(parameter.min), math.floor(parameter.max) do table.insert(choices, {label = tostring(value), value = value}) end
            else
                textField(title, ref.params, key, parameter.type == 'number' or parameter.type == 'integer')
                return
            end
            choose(title, ref.params, key, choices)
        end
        local events = control.kind == 'keypad' and {'submit'} or control.kind == 'toggle' and {'in', 'out'} or {'press'}
        label(self.Inspector, 'Component actions')
        local actionList = self.Inspector:Add('DListView')
        actionList:Dock(TOP); actionList:SetTall(110)
        actionList:AddColumn('Event'):SetFixedWidth(70)
        actionList:AddColumn('Registered action')
        local selectedEvent = self.ActionEvent
        if not (control.actions and control.actions[selectedEvent or '']) then selectedEvent = nil end
        for _, event in ipairs(events) do
            if control.actions and control.actions[event] then
                local row = actionList:AddLine(event, control.actions[event].id)
                row.ActionEvent = event
                selectedEvent = selectedEvent or event
            end
        end
        self.ActionEvent = selectedEvent
        for _, row in ipairs(actionList:GetLines()) do
            if row.ActionEvent == selectedEvent then actionList:SelectItem(row); break end
        end
        actionList.OnRowSelected = function(_, _, row) self.ActionEvent = row.ActionEvent; self:Inspect() end
        local actionButtons = self.Inspector:Add('DPanel')
        actionButtons:Dock(TOP); actionButtons:SetTall(30)
        local addAction = actionButtons:Add('DButton')
        addAction:Dock(LEFT); addAction:SetWide(85); addAction:SetText('Add')
        addAction:SetEnabled(not self.ReadOnly)
        addAction.DoClick = function()
            local available = {}
            for _, event in ipairs(events) do if not (control.actions and control.actions[event]) then available[event] = {label = event} end end
            if not next(available) then self:Report('All supported events are assigned. Select an entry to change its action.'); return end
            self:Picker('Choose output event', available, function(event)
                self:Picker('Registered actions', catalog.Actions, function(id)
                    self:Change(function()
                        control.actions = control.actions or {}
                        control.actions[event] = {id = id, params = {}}
                        self.ActionEvent = event
                    end)
                end)
            end)
        end
        local deleteAction = actionButtons:Add('DButton')
        deleteAction:Dock(LEFT); deleteAction:SetWide(85); deleteAction:SetText('Delete')
        deleteAction:SetEnabled(not self.ReadOnly and selectedEvent ~= nil)
        deleteAction.DoClick = function() self:Change(function() control.actions[selectedEvent] = nil; self.ActionEvent = nil end) end
        if selectedEvent then
            local ref = control.actions[selectedEvent]
            local eventChoices = {}
            for _, event in ipairs(events) do table.insert(eventChoices, {label = event, value = event}) end
            choiceField(self.Inspector, 'Output event', selectedEvent, eventChoices, function(event)
                if event == selectedEvent then return end
                if control.actions[event] then self:Report('That event already has an action.'); return end
                self:Change(function()
                    control.actions[event], control.actions[selectedEvent] = ref, nil
                    self.ActionEvent = event
                end)
            end, not self.ReadOnly)
            button(self.Inspector, 'Registered action: ' .. ref.id, function()
                self:Picker('Registered actions', catalog.Actions, function(id)
                    self:Change(function() control.actions[selectedEvent] = {id = id, params = {}} end)
                end)
            end):SetEnabled(not self.ReadOnly)
            local parameters = catalog.Actions and catalog.Actions[ref.id] and catalog.Actions[ref.id].parameters or {}
            local keys = {}; for key in pairs(parameters) do table.insert(keys, key) end; table.sort(keys)
            for _, key in ipairs(keys) do
                local parameter = parameters[key]
                ref.params = ref.params or {}
                parameterField(key .. ' (' .. parameter.type .. ')', ref, key, parameter)
            end
        end
        for index, ref in ipairs(control.predicates or {}) do
            local predicateIndex = index
            label(self.Inspector, 'Availability: ' .. ref.id)
            for key, parameter in pairs(catalog.Predicates and catalog.Predicates[ref.id] and catalog.Predicates[ref.id].parameters or {}) do
                ref.params = ref.params or {}
                parameterField('Predicate ' .. key, ref, key, parameter)
            end
            button(self.Inspector, 'Remove predicate ' .. index, function() self:Change(function() table.remove(control.predicates, predicateIndex) end) end)
        end
        button(self.Inspector, 'Add availability predicate', function()
            self:Picker('Availability predicates', catalog.Predicates, function(id)
                self:Change(function() control.predicates = control.predicates or {}; table.insert(control.predicates, {id = id, params = {}}) end)
            end)
        end)
        button(self.Inspector, 'Copy Hammer wiring', function() local text = CONTROL.Wiring(); SetClipboardText(text); self:Report(text) end)
        button(self.Inspector, 'Validate / simulate draft locally', function()
            local compiled, diagnostics = CONTROL.CompileSource(self.Source, 'editor', catalog)
            self:Report(CONTROL.DiagnosticsText(diagnostics))
            if compiled then self:Preview(compiled, control.id) end
        end)
        THEME.ApplyTree(self.Inspector)
    end
    function frame:Preview(compiled, id)
        local draft = CONTROL.NewPreview(compiled)
        local view = window('LOCAL draft simulator - registrations/predicates are not executed', 800, 670)
        table.insert(self.ChildWindows, view)
        local tools = view:Add('DScrollPanel')
        tools:Dock(LEFT); tools:SetWide(245)
        local value = tools:Add('DTextEntry')
        value:Dock(TOP); value:SetPlaceholderText('Integer submission / digit')
        local status = THEME.CreateTextArea(view)
        status:Dock(FILL)
        local function refresh()
            status:SetText('LOCAL time: ' .. draft.time .. ' tick: ' .. draft.tick .. '\nNamed predicates are simulated as available.\n'
                .. (util.TableToJSON(draft.controls[id], true) or '') .. '\n' .. table.concat(draft.history, '\n'))
        end
        for _, operation in ipairs(CONTROL.Operations) do
            local op = operation
            button(tools, 'SIMULATE ' .. op, function()
                if not draft:Request(id, op, tonumber(value:GetValue())) then self:Report('Operation/value incompatible with draft control.') end
                refresh()
            end)
        end
        button(tools, 'Advance one tick (0.05s)', function() draft:Step(0.05); refresh() end)
        button(tools, 'Advance past queue expiry (2.1s)', function() draft:Step(2.1); refresh() end)
        button(tools, 'Acknowledge endpoint / return', function() draft:Endpoint(id); refresh() end)
        button(tools, 'Local lock', function() draft.controls[id].locks.preview = true; refresh() end)
        button(tools, 'Local unlock', function() draft.controls[id].locks.preview = nil; draft:Dispatch(draft.controls[id]); refresh() end)
        button(tools, 'Cancel local pending request', function() draft.controls[id].pending = nil; refresh() end)
        for _, operation in ipairs({'digit', 'clear', 'backspace'}) do
            local op = operation
            button(tools, 'Local keypad ' .. op, function() draft:Key(id, op, tonumber(value:GetValue())); refresh() end)
        end
        THEME.ApplyTree(view)
        refresh()
    end
    function frame:Rebuild()
        self.List:Clear()
        for index, control in ipairs(self.Source.controls) do
            if string.find(string.lower((control.id or '') .. ' ' .. (control.label or '')), string.lower(search:GetValue()), 1, true) then
                local line = self.List:AddLine(kindLabel(control.kind), control.id)
                line.ControlIndex = index
            end
        end
        self:Inspect()
        THEME.ApplyTree(self.List)
    end
    function frame:Sources()
        if IsValid(self.SourceWindow) then self.SourceWindow:MakePopup(); return end
        local sources = window('Control packed sources / drafts', 780, 520)
        self.SourceWindow = sources
        table.insert(self.ChildWindows, sources)
        local filter = sources:Add('DTextEntry')
        filter:Dock(TOP)
        filter:SetPlaceholderText('Search source paths')
        local list = sources:Add('DListView')
        list:Dock(FILL)
        list:AddColumn('Type'):SetFixedWidth(90)
        list:AddColumn('File'):SetFixedWidth(180)
        list:AddColumn('Source path')
        local selectedSource, packId
        local function refresh()
            selectedSource = nil
            list:Clear()
            for path, source in pairs(CONTROL.Client.catalog and CONTROL.Client.catalog.sources or {}) do
                if string.find(string.lower(path), string.lower(filter:GetValue()), 1, true) then
                    local line = list:AddLine('Packed', string.match(path, '[^/]+$'), path)
                    line.Source, line.ReadOnly, line.Path = source, true, path
                end
            end
            local root = 'luasquare/control/drafts/' .. game.GetMap() .. '/'
            for _, name in ipairs(file.Find(root .. '*.json', 'DATA') or {}) do
                if string.find(root .. name, filter:GetValue(), 1, true) then
                    local line = list:AddLine('Draft', name, root .. name)
                    line.Path = root .. name
                end
            end
            THEME.ApplyTree(sources)
            if IsValid(packId) then packId:SetText(self.Source.id); packId:SetEditable(not self.ReadOnly) end
        end
        local function load(line)
            if line.ReadOnly and not line.Source then self:Report('Packed source transfer still pending; refresh shortly.'); return end
            local source = line.Source or util.JSONToTable(file.Read(line.Path, 'DATA') or '', false, true)
            local compiled, diagnostics = CONTROL.CompileSource(source, line.Path or 'packed source', CONTROL.Client.catalog)
            if not compiled then self:Report(CONTROL.DiagnosticsText(diagnostics)); return end
            self.Source, self.ReadOnly, self.Undo, self.Redo, self.Selected, self.Dirty = CONTROL.DeepCopy(source), line.ReadOnly == true, {}, {}, nil, false
            self:Rebuild(); self:Report(line.ReadOnly and 'Packed source is read-only.' or 'Draft loaded.')
            return true
        end
        list.OnRowSelected = function(_, _, line) selectedSource = line end
        local actions = sources:Add('DPanel')
        actions:Dock(BOTTOM); actions:SetTall(36)
        local function sourceButton(title, callback)
            local b = actions:Add('DButton'); b:Dock(LEFT); b:DockMargin(4, 4, 0, 4)
            b:SetWide(112); b:SetText(title); b.DoClick = callback
            return b
        end
        sourceButton('Load selected', function()
            if not selectedSource then self:Report('Select a source to load.'); return end
            local entry = selectedSource
            self:ConfirmDiscard(function() if load(entry) then sources:Close() end end)
        end)
        sourceButton('Editable copy', function()
            if not selectedSource then self:Report('Select a source to copy.'); return end
            local entry = selectedSource
            self:ConfirmDiscard(function()
                if not load(entry) then return end
                self.ReadOnly, self.Dirty = false, true
                self:Rebuild(); sources:Close()
            end)
        end)
        sourceButton('New pack', function()
            local function reset()
                self.Source = {schema = CONTROL.Schema, id = 'new_controls', controls = {}}
                self.ReadOnly, self.Dirty, self.Selected, self.Undo, self.Redo = false, false, nil, {}, {}
                self:Rebuild()
                refresh()
                self:Report('New draft. Set the pack ID and add controls before saving.')
            end
            if self.Dirty then Derma_Query('Discard unsaved changes?', 'New draft', 'Discard', reset, 'Cancel') else reset() end
        end)
        sourceButton('Save draft', function()
            local catalog = CONTROL.Client.catalog or {}
            local compiled, diagnostics = CONTROL.CompileSource(self.Source, 'editor', catalog)
            if not compiled then self:Report(CONTROL.DiagnosticsText(diagnostics)); return end
            local json = CONTROL.CanonicalJSON(self.Source)
            if not json or #json > CONTROL.MaxSourceBytes then self:Report('Source too large.'); return end
            local root = 'luasquare/control/drafts/' .. game.GetMap()
            file.CreateDir(root)
            local path = root .. '/' .. self.Source.id .. '.json'
            local function save()
                file.Write(path, json)
                self.ReadOnly, self.Dirty = false, false
                self:Rebuild(); refresh(); self:Report('Saved draft: data/' .. path)
            end
            if file.Exists(path, 'DATA') then Derma_Query('Overwrite ' .. path .. '?', 'Existing draft', 'Overwrite', save, 'Cancel') else save() end
        end)
        sourceButton('Refresh', function() CONTROL.EditorCommand('subscribe'); refresh() end)
        label(sources, 'Current pack ID (Enter to apply)')
        packId = sources:Add('DTextEntry'); packId:Dock(TOP); packId:SetText(self.Source.id)
        packId:SetEditable(not self.ReadOnly)
        packId.OnEnter = function()
            local id = packId:GetValue()
            if id ~= CONTROL.NormalizeId(id) then self:Report('Invalid pack ID.'); return end
            self:Change(function() self.Source.id = id end)
        end
        filter.OnChange = refresh
        sources.Refresh = refresh
        refresh(); THEME.ApplyTree(sources)
    end
    local function tool(text, callback)
        local b = toolbar:Add('DButton')
        b:Dock(LEFT)
        b:SetWide(105)
        b:SetText(text)
        b.DoClick = callback
        THEME.Apply(b)
    end
    tool('Sources / save', function() frame:Sources() end)
    tool('Add virtual', function() frame:Change(function()
        local n = #frame.Source.controls + 1
        table.insert(frame.Source.controls, {id = 'new_' .. n, kind = 'momentary', cooldown = 0.25})
        frame.Selected = n
    end) end)
    tool('Discover CTRLI_', function()
        local values = {}
        frame.DiscoveryWindow = frame:Picker('Discovered CTRLI_ buttons', function()
            values = {}
            for _, entity in ipairs(CONTROL.Client.catalog and CONTROL.Client.catalog.entities or {}) do values[entity.target] = entity end
            return values
        end, function(target)
            local entity = values[target]
            if entity.diagnostic then frame:Report(entity.diagnostic .. ': ' .. target); return end
            local function add(kind)
                frame:Picker('Select acting component action', CONTROL.Client.catalog.Actions, function(actionId) frame:Change(function()
                for _, control in ipairs(frame.Source.controls) do if control.id == entity.id or control.target == target then frame:Report('Duplicate ID or target; discovery rejected.'); return end end
                local events = kind == 'toggle' and {['in'] = {id = actionId, params = {}}} or {press = {id = actionId, params = {}}}
                table.insert(frame.Source.controls, {id = entity.id, kind = kind, target = target, class = entity.class, actions = events})
                frame.Selected = #frame.Source.controls
                end) end)
            end
            Derma_Query('Select the physical kind explicitly. Match the Hammer toggle flag.', 'Discovered control',
                'Press', function() add('momentary') end, 'Toggle', function() add('toggle') end, 'Cancel')
        end)
        CONTROL.EditorCommand('subscribe')
    end)
    tool('Delete', function() frame:Change(function() if frame.Selected then table.remove(frame.Source.controls, frame.Selected); frame.Selected = nil end end) end)
    tool('Undo', function()
        if frame.ReadOnly or #frame.Undo == 0 then return end
        table.insert(frame.Redo, CONTROL.DeepCopy(frame.Source)); frame.Source = table.remove(frame.Undo); frame.Dirty = true; frame:Rebuild()
    end)
    tool('Redo', function()
        if frame.ReadOnly or #frame.Redo == 0 then return end
        table.insert(frame.Undo, CONTROL.DeepCopy(frame.Source)); frame.Source = table.remove(frame.Redo); frame.Dirty = true; frame:Rebuild()
    end)
    frame.List.OnRowSelected = function(_, _, line) frame.Selected = line.ControlIndex; frame:Inspect() end
    search.OnChange = function() frame:Rebuild() end
    local nativeThink = frame.Think
    frame.Think = function(self)
        if nativeThink then nativeThink(self) end
        focusHoveredWindow(self.ChildWindows)
        local state = CONTROL.Client.controls[frame.LiveId:GetValue()]
        frame.LiveStatus:SetText(state and (util.TableToJSON(state, true) or '') or 'Select a packed runtime control. Live tests change gameplay.')
    end
    frame.OnRemove = function()
        if IsValid(frame.SourceWindow) then frame.SourceWindow:Close() end
        for _, child in ipairs(frame.ChildWindows) do if IsValid(child) then child:Close() end end
        hook.Remove('LUASQUARE_CONTROL_ClientCatalog', 'LUASQUARE_CONTROL_EditorCatalog')
        CONTROL.EditorCommand('close')
    end
    hook.Add('LUASQUARE_CONTROL_ClientCatalog', 'LUASQUARE_CONTROL_EditorCatalog', function()
        if IsValid(frame) then
            frame:Rebuild()
            local catalog = CONTROL.Client.catalog
            frame:Report('Discovered ' .. #(catalog.entities or {}) .. ' CTRLI_ buttons in the running map. '
                .. #(catalog.keypadEntities or {}) .. ' KPD subcomponents. '
                .. (catalog.running and 'Control runtime active.' or 'Control runtime inactive; discovery and drafts remain available.')
                .. (#(catalog.diagnostics or {}) > 0 and '\n' .. CONTROL.DiagnosticsText(catalog.diagnostics) or ''))
            if IsValid(frame.DiscoveryWindow) then frame.DiscoveryWindow.Refresh() end
            if IsValid(frame.SourceWindow) and frame.SourceWindow.Refresh then frame.SourceWindow.Refresh() end
        else hook.Remove('LUASQUARE_CONTROL_ClientCatalog', 'LUASQUARE_CONTROL_EditorCatalog') end
    end)
    frame:Rebuild()
    THEME.ApplyEditor(frame, {toolbar, left, center})
    timer.Simple(0, function()
        if IsValid(frame) then THEME.ApplyTree(frame) end
    end)
    frame:Report('Load a packed source or create a draft. Catalogs/live tests require single-player or admin permission. Live tests operate packed controls only.')
    CONTROL.EditorCommand('subscribe')
end
