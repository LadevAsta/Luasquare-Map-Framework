local MAP, THEME = LUASQUARE_MAP, LUASQUARE_EDITOR_THEME
MAP.Editor = {children = {}, selection = {}}
local EDITOR = MAP.Editor
local foreground, background = Color(235, 235, 235), Color(38, 38, 38)
local function report(text)
    print('[LUASQUARE MAP EDITOR] ' .. tostring(text))
    if IsValid(EDITOR.Status) then EDITOR.Status:SetText(tostring(text)) end
end
local function window(title, width, height)
    local panel = vgui.Create('DFrame')
    panel:SetTitle(title); panel:SetSize(width, height); panel:Center()
    panel:SetSizable(true); panel:SetDraggable(true); panel:SetMinWidth(360); panel:SetMinHeight(240)
    panel:MakePopup(); THEME.ApplyEditor(panel)
    panel.btnMaxim:SetEnabled(false)
    if IsValid(EDITOR.Frame) then
        for index = #EDITOR.children, 1, -1 do if not IsValid(EDITOR.children[index]) then table.remove(EDITOR.children, index) end end
        if #EDITOR.children >= 32 then table.remove(EDITOR.children, 1):Remove() end
        EDITOR.children[#EDITOR.children + 1] = panel
    end
    return panel
end
local function label(parent, text)
    local panel = parent:Add('DLabel'); panel:Dock(TOP); panel:SetTall(24); panel:SetText(text); panel:SetTextColor(foreground)
    return panel
end
local function button(parent, text, callback)
    local panel = parent:Add('DButton'); panel:Dock(TOP); panel:SetTall(26); panel:SetText(text); panel.DoClick = callback; THEME.Apply(panel)
    return panel
end
local function textEntry(parent, text, callback)
    local panel = parent:Add('DTextEntry'); panel:Dock(TOP); panel:SetTall(26); panel:SetText(tostring(text or '')); THEME.Apply(panel)
    panel.OnEnter = function() callback(panel:GetValue()) end
    return panel
end
local function keys(value)
    local result = {}; for key in pairs(value or {}) do result[#result + 1] = key end
    table.sort(result); return result
end
local function choose(title, items, callback)
    local frame = window(title, 560, 580)
    local search = frame:Add('DTextEntry'); search:Dock(TOP); search:SetTall(28); search:SetPlaceholderText('Search ID, type, or label')
    local accept = frame:Add('DButton'); accept:Dock(BOTTOM); accept:SetTall(30); accept:SetText('Select highlighted item')
    local list = frame:Add('DListView'); list:Dock(FILL); list:AddColumn('ID'); list:AddColumn('Category / description')
    local selected
    local function rebuild()
        list:Clear(); local query = search:GetValue():lower()
        for _, id in ipairs(keys(items)) do
            local description = (items[id].package and items[id].package .. ' / ' or '') .. tostring(items[id].label or items[id].type or '')
            if (id .. ' ' .. description):lower():find(query, 1, true) then local row = list:AddLine(id, description); row.ItemID = id end
        end
        THEME.ApplyEditor(frame)
    end
    search.OnChange = rebuild
    list.OnRowSelected = function(_, _, row) selected = row.ItemID end
    local function commit(row)
        local id = row and row.ItemID or selected
        if not id or not items[id] then report('Select an item first.'); return end
        callback(id, items[id]); frame:Close()
    end
    list.DoDoubleClick = function(_, _, row) commit(row) end
    accept.DoClick = function() commit() end
    rebuild()
end
local function changed(ok, err)
    if not ok then report(err); return end
    local compiled, diagnostics = EDITOR.document:Compile()
    EDITOR.compiled = compiled
    EDITOR.diagnostics = diagnostics
    report(compiled and 'Structure valid. Export drafts, promote packed sources manually, then reload the map.' or MAP.DiagnosticsText(diagnostics))
    if EDITOR.RefreshInspector then EDITOR.RefreshInspector() end
    if EDITOR.RefreshManaged then EDITOR.RefreshManaged() end
end
local function edit(callback) changed(EDITOR.document:Edit(callback)) end
local function defaultValue(field)
    if field.default ~= nil then
        local value = MAP.Copy(field.default)
        if field.type == 'array' then return MAP.Array(value) end
        return value
    end
    if field.choices then return keys(field.choices)[1] end
    if field.oneOf then return defaultValue(field.oneOf[1]) end
    if field.type == 'boolean' then return false end
    if field.type == 'number' or field.type == 'integer' then return field.min or 0 end
    if field.type == 'vector' then return {0, 0, 0} end
    if field.type == 'array' then return MAP.Array() end
    if field.type == 'object' then
        local result = MAP.Object(); for name, child in pairs(field.fields) do if not child.optional then result[name] = defaultValue(child) end end
        return result
    end
    return ''
end

local function fieldTooltip(name, field)
    local parts = {field.description or ('Configuration field `' .. name .. '`.')}
    parts[#parts + 1] = 'Type: ' .. tostring(field.type or 'value') .. (field.unit and (', unit: ' .. field.unit) or '') .. '.'
    if field.min ~= nil or field.max ~= nil then
        parts[#parts + 1] = 'Range: ' .. tostring(field.min or '-unbounded') .. ' to ' .. tostring(field.max or 'unbounded') .. '.'
    end
    if field.default ~= nil then parts[#parts + 1] = 'Default: ' .. tostring(field.default) .. '.' end
    return table.concat(parts, ' ')
end

local fieldEditor
local function arrayTableEditor(title, field, value, set)
    local frame = window(title, 640, 520)
    local actions = frame:Add('DPanel'); actions:Dock(BOTTOM); actions:SetTall(32)
    local add = actions:Add('DButton'); add:Dock(LEFT); add:SetWide(110); add:SetText('Add entry')
    local remove = actions:Add('DButton'); remove:Dock(LEFT); remove:SetWide(130); remove:SetText('Delete selected')
    local apply = actions:Add('DButton'); apply:Dock(RIGHT); apply:SetWide(120); apply:SetText('Apply table')
    local list = frame:Add('DListView'); list:Dock(FILL); list:SetMultiSelect(false); list:AddColumn('#'); list:AddColumn('Value')
    local draft, selected = MAP.Array(MAP.Copy(value or {})), nil
    local function rebuild()
        list:Clear()
        for index, item in ipairs(draft) do
            local shown = type(item) == 'table' and MAP.CanonicalJSON(item) or tostring(item)
            local row = list:AddLine(index, shown); row.ArrayIndex = index
        end
        THEME.ApplyEditor(frame)
    end
    list.OnRowSelected = function(_, _, row) selected = row.ArrayIndex end
    add.DoClick = function()
        if #draft >= (field.maxItems or 4096) then report('Array limit reached'); return end
        if field.items.asset and field.items.asset ~= 'name' then
            local items = {}
            if field.items.asset == 'entity' then
                for _, entity in ipairs((MAP.Client.catalog or {}).entities or {}) do items[entity.name] = {label = entity.class} end
            end
            choose('Add ' .. title, items, function(id) draft[#draft + 1] = id; rebuild() end)
            return
        end
        local dialog = window('Add ' .. title, 460, 180)
        label(dialog, 'Enter the new value, then press Enter.')
        textEntry(dialog, '', function(item)
            if item == '' then report('Value cannot be empty'); return end
            draft[#draft + 1] = item; rebuild(); dialog:Close()
        end)
    end
    remove.DoClick = function()
        if not selected or not draft[selected] then report('Select an entry first.'); return end
        table.remove(draft, selected); selected = nil; rebuild()
    end
    apply.DoClick = function() set(draft); frame:Close() end
    rebuild()
end
fieldEditor = function(parent, title, field, value, set, context)
    local heading = label(parent, title .. (field.unit and ' [' .. field.unit .. ']' or ''))
    heading:SetTooltip(fieldTooltip(title, field))
    if field.oneOf then
        local selected = field.oneOf[1]
        for _, choice in ipairs(field.oneOf) do if not select(2, MAP.ValidateValue(choice, value)) then selected = choice; break end end
        local combo = parent:Add('DComboBox'); combo:Dock(TOP); combo:SetTall(26)
        for _, choice in ipairs(field.oneOf) do combo:AddChoice(choice.type, choice) end
        combo:SetValue(selected.type); combo.OnSelect = function(_, _, _, choice) set(defaultValue(choice)) end
        fieldEditor(parent, 'Value', selected, value, set)
    elseif field.choices then
        local combo = parent:Add('DComboBox'); combo:Dock(TOP); combo:SetTall(26)
        for _, id in ipairs(keys(field.choices)) do combo:AddChoice(id) end
        combo:SetValue(tostring(value or '(default)')); combo.OnSelect = function(_, _, selected) set(selected) end
    elseif field.type == 'boolean' then
        local control = parent:Add('DCheckBoxLabel'); control:Dock(TOP); control:SetTall(26); control:SetText('Enabled'); control:SetValue(value == true)
        control.OnChange = function(_, state) set(state) end
    elseif field.type == 'number' or field.type == 'integer' then
        local control = parent:Add('DNumberWang'); control:Dock(TOP); control:SetTall(28); control:SetMinMax(field.min or -1e15, field.max or 1e15)
        control:SetDecimals(field.type == 'integer' and 0 or 6); control:SetValue(value or 0)
        control.OnEnter = function() set(control:GetValue()) end
        control.OnLoseFocus = function() if control:GetValue() ~= value then set(control:GetValue()) end end
    elseif field.type == 'port' then
        button(parent, tostring(value or 'Choose port'), function()
            local node = context and EDITOR.document:Resolve(context.component)
            local items = {}; for name, descriptor in pairs(node and MAP.Types[node.type].ports or {}) do items[name] = {label = descriptor.kind .. ' ' .. (descriptor.unit or '')} end
            choose(title, items, function(id) set(id) end)
        end)
    elseif field.type == 'id' and not field.asset then
        button(parent, tostring(value or 'Choose component'), function()
            local items = {}
            for _, pack in pairs(EDITOR.document.packs) do for _, node in ipairs(pack.components) do
                local resolved = EDITOR.document:Resolve(node.id)
                if not field.reference or resolved and resolved.type == field.reference then items[node.id] = node end
            end end
            for id, node in pairs(EDITOR.compiled and EDITOR.compiled.nodes or {}) do
                if node.generatedBy and (not field.reference or node.type == field.reference) then items[id] = node end
            end
            choose(title, items, function(id) set(id) end)
        end)
    elseif field.type == 'array' and field.items and field.items.type == 'string' then
        button(parent, 'Edit ' .. title .. ' table (' .. #(value or {}) .. ')', function() arrayTableEditor(title, field, value, set) end)
    elseif field.type == 'object' or field.type == 'array' or field.type == 'vector' then
        button(parent, 'Edit ' .. title, function()
            local frame = window(title, 510, 600)
            local scroll = frame:Add('DScrollPanel'); scroll:Dock(FILL)
            local draft = MAP.Copy(value or defaultValue(field))
            local page = 1
            local function drawFields()
                scroll:Clear()
                button(scroll, 'Apply changes', function() set(draft); frame:Close() end)
                if field.type == 'object' then
                    for _, name in ipairs(keys(field.fields)) do fieldEditor(scroll, name, field.fields[name], draft[name], function(item) draft[name] = item end, draft) end
                else
                    local descriptor = field.type == 'vector' and {type = 'number'} or field.items
                    if field.type == 'array' then
                        button(scroll, 'Add item', function()
                            if #draft >= (field.maxItems or 4096) then report('Array limit reached'); return end
                            draft[#draft + 1] = defaultValue(descriptor); page = math.ceil(#draft / 32); drawFields()
                        end)
                        button(scroll, 'Previous / next page (' .. page .. ')', function() page = page % math.max(math.ceil(#draft / 32), 1) + 1; drawFields() end)
                    end
                    for index = (page - 1) * 32 + 1, math.min(page * 32, #draft) do
                        fieldEditor(scroll, tostring(index), descriptor, draft[index], function(item) draft[index] = item end)
                        if field.type == 'array' then button(scroll, 'Remove ' .. index, function() table.remove(draft, index); drawFields() end) end
                    end
                end
                THEME.ApplyEditor(frame)
            end
            drawFields()
        end)
    else
        textEntry(parent, value, set)
        if field.asset and field.asset ~= 'name' then button(parent, 'Browse ' .. field.asset, function()
            local items = {}
            if field.asset == 'entity' then
                for _, entity in ipairs((MAP.Client.catalog or {}).entities or {}) do items[entity.name] = {label = entity.class} end
            elseif field.asset == 'seg7' then
                for prefix, count in pairs((MAP.Client.catalog or {}).seg7Prefixes or {}) do items[prefix] = {label = count .. ' contiguous candidate digits'} end
            elseif field.asset == 'timeline_source' then
                for _, path in ipairs(((MAP.Client.catalog or {}).sources or {}).timeline or {}) do items[path] = {label = 'Timeline source'} end
            elseif field.asset == 'timeline_component' then
                for id, item in pairs((MAP.Client.catalog or {}).timelineComponents or {}) do items[id] = item end
            elseif field.asset == 'telemetry' and context then
                for _, active in pairs((MAP.Client.catalog or {}).active or {}) do
                    for _, descriptor in ipairs(((active.nodes or {})[context.component] or {}).telemetry or {}) do
                        items[descriptor.path] = {label = descriptor.type .. ' ' .. (descriptor.unit or '')}
                    end
                end
            end
            choose(title, items, function(id) set(id) end)
        end) end
    end
    if field.optional then button(parent, 'Use default / omit', function() set(nil) end) end
    THEME.ApplyEditor(parent)
end

local function gridEditor(id, resolved)
    local frame = window('RBMK cells — ' .. id, 850, 750)
    local kind, cell = 'fuel', {kind = 'fuel', fuel = 'MEU'}
    local tools = frame:Add('DPanel'); tools:Dock(RIGHT); tools:SetWide(250)
    local scroll = tools:Add('DScrollPanel'); scroll:Dock(FILL)
    local function properties()
        scroll:Clear()
        fieldEditor(scroll, 'Cell kind', MAP.Types['rbmk.core'].fields.cells.items.fields.kind, kind, function(value)
            kind, cell = value, {kind = value}; properties()
        end)
        for _, name in ipairs(keys(MAP.Types['rbmk.core'].fields.cells.items.fields)) do
            if name ~= 'x' and name ~= 'y' and name ~= 'kind' then
                fieldEditor(scroll, name, MAP.Types['rbmk.core'].fields.cells.items.fields[name], cell[name], function(value) cell[name] = value end)
            end
        end
    end
    properties()
    local canvas = frame:Add('DPanel'); canvas:Dock(FILL)
    local colors = {fuel = Color(90, 150, 70), control = Color(170, 90, 80), steam = Color(75, 125, 170), reflector = Color(165, 160, 80), source = Color(160, 90, 175)}
    canvas.Paint = function(panel, width, height)
        surface.SetDrawColor(background); surface.DrawRect(0, 0, width, height)
        local node = EDITOR.document:Resolve(id) or resolved
        local cells, config = {}, node.config
        for _, item in ipairs(config.cells or {}) do cells[item.x .. '/' .. item.y] = item end
        local size = math.min(width / config.width, height / config.height)
        for x = 1, config.width do for y = 1, config.height do
            local item = cells[x .. '/' .. y]
            surface.SetDrawColor(item and colors[item.kind] or Color(65, 65, 65)); surface.DrawRect((x - 1) * size + 1, (y - 1) * size + 1, size - 2, size - 2)
            if size >= 24 and item then draw.SimpleText(item.name or item.kind:sub(1, 1):upper(), 'DermaDefault', (x - 0.5) * size, (y - 0.5) * size, foreground, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER) end
        end end
    end
    canvas.OnMousePressed = function(panel, code)
        local x, y = panel:LocalCursorPos()
        local size = math.min(panel:GetWide() / resolved.config.width, panel:GetTall() / resolved.config.height)
        local value = cell
        if code == MOUSE_RIGHT then value = nil end
        changed(EDITOR.document:SetCell(id, math.floor(x / size) + 1, math.floor(y / size) + 1, value))
    end
    label(tools, 'Left: paint. Right: clear. Undo in main window.')
    THEME.ApplyEditor(frame)
end

local function nodeLabel(id, node)
    node = node or (EDITOR.document and EDITOR.document:Find(id)) or (EDITOR.compiled and EDITOR.compiled.nodes[id])
    local editor = node and type(node.editor) == 'table' and node.editor or nil
    local definition = node and MAP.Types[node.type or ((EDITOR.document and EDITOR.document:Resolve(id) or {}).type)] or nil
    return editor and editor.label or definition and definition.label or id
end

local function configurationEditor(id, resolved, definition)
    resolved = resolved or (EDITOR.document and EDITOR.document:Resolve(id))
    if not resolved or type(resolved.config) ~= 'table' then report('Component configuration is unavailable until its declaration resolves.'); return end
    local frame = window(nodeLabel(id, resolved) .. ' settings', 720, 720)
    local staged, touched = MAP.Copy(resolved.config), {}
    local actions = frame:Add('DPanel'); actions:Dock(BOTTOM); actions:SetTall(34)
    local apply = actions:Add('DButton'); apply:Dock(RIGHT); apply:SetWide(150); apply:SetText('Apply changes')
    apply:SetTooltip('Validate and commit every staged property change as one undoable edit.')
    local pending = actions:Add('DLabel'); pending:Dock(FILL); pending:SetText('  No staged changes'); pending:SetTextColor(foreground)
    local function stage(name, value)
        staged[name], touched[name] = MAP.Copy(value), true
        pending:SetText('  Changes staged — press Apply')
    end
    apply.DoClick = function()
        if not next(touched) then report('No component setting changes to apply.'); return end
        edit(function(document)
            if not document:Resolve(id) then return false, 'unknown component' end
            document.manifest.overrides = document.manifest.overrides or MAP.Object()
            document.manifest.overrides[id] = document.manifest.overrides[id] or MAP.Object()
            for name in pairs(touched) do document.manifest.overrides[id][name] = MAP.Copy(staged[name]) end
            return true
        end)
        frame:Close()
    end
    local scroll = frame:Add('DScrollPanel'); scroll:Dock(FILL)
    label(scroll, 'Typed component settings. Edits are staged locally until Apply; source defaults remain available through Clear overrides.')
    button(scroll, 'Clear all manifest overrides for this component', function()
        edit(function(document)
            if document.manifest.overrides then document.manifest.overrides[id] = nil end
            return true
        end)
        frame:Close()
    end)
    local properties = scroll:Add('DProperties'); properties:Dock(TOP)
    local propertyCount = 0
    for _, name in ipairs(keys(definition.fields)) do
        local field, value = definition.fields[name], resolved.config[name]
        local scalar = not field.oneOf and not field.choices and not field.asset
            and (field.type == 'boolean' or field.type == 'number' or field.type == 'integer' or field.type == 'string')
        if scalar then
            propertyCount = propertyCount + 1
            local row = properties:CreateRow('Configuration', name .. (field.unit and ' [' .. field.unit .. ']' or ''))
            local setup = nil
            if field.type == 'number' or field.type == 'integer' then
                local basis = math.max(math.abs(tonumber(value) or 0), math.abs(tonumber(field.default) or 0), 1)
                setup = {min = field.min ~= nil and field.min or math.min(0, -basis * 4),
                    max = field.max ~= nil and field.max or math.max(1, basis * 4)}
            end
            row:Setup(field.type == 'boolean' and 'Boolean' or field.type == 'integer' and 'Int' or field.type == 'number' and 'Float' or 'Generic', setup)
            row:SetTooltip(fieldTooltip(name, field))
            row:SetValue(value == nil and '' or value)
            row.DataChanged = function(_, changedValue)
                local parsed = changedValue
                if field.type == 'boolean' then parsed = changedValue == true or changedValue == 1 or changedValue == '1' or changedValue == 'true'
                elseif field.type == 'number' or field.type == 'integer' then
                    parsed = tonumber(changedValue)
                    if not parsed then report(name .. ': expected a number'); return end
                    if field.type == 'integer' then parsed = math.Round(parsed) end
                    parsed = math.Clamp(parsed, field.min or -1e15, field.max or 1e15)
                else parsed = tostring(changedValue) end
                stage(name, parsed)
            end
        end
    end
    properties:SetTall(math.max(80, propertyCount * 24 + 32))
    label(scroll, 'References, choices and structured values')
    for _, name in ipairs(keys(definition.fields)) do
        local field = definition.fields[name]
        local scalar = not field.oneOf and not field.choices and not field.asset
            and (field.type == 'boolean' or field.type == 'number' or field.type == 'integer' or field.type == 'string')
        if not scalar then
            fieldEditor(scroll, name, field, staged[name], function(value) stage(name, value) end,
                {component = id})
            if name == 'tags' then label(scroll, 'Tags are optional mapper metadata retained on Source bindings; they do not change entity resolution.') end
        end
    end
    THEME.ApplyEditor(frame)
end

function EDITOR.RefreshInspector()
    if not IsValid(EDITOR.Inspector) then return end
    local parent = EDITOR.Inspector; parent:Clear()
    local id = keys(EDITOR.selection)[1]
    local node = id and (EDITOR.document:Find(id) or (EDITOR.compiled and EDITOR.compiled.nodes[id]))
    if not node and EDITOR.selectedLink then
        local selected = EDITOR.selectedLink
        local pack = selected.path and EDITOR.document.packs[selected.path]
        local link = pack and pack.links and pack.links[selected.index] or selected.value
        if link then
            label(parent, 'Selected connection')
            label(parent, nodeLabel(link.from.component) .. ' / ' .. tostring(link.from.port or 'config') .. '  >  '
                .. nodeLabel(link.to.component) .. ' / ' .. tostring(link.to.port or 'reference'))
            label(parent, link.from.component .. '  >  ' .. link.to.component)
            label(parent, 'Drag the square route anchor to change where the orthogonal path turns.')
            if selected.path then
                button(parent, 'Remove selected connection', function()
                    edit(function(document) table.remove(document.packs[selected.path].links, selected.index); return true end)
                    EDITOR.selectedLink = nil; EDITOR.RefreshInspector()
                end)
            else label(parent, 'This is a configuration reference. Change its endpoint in the owning component settings.') end
            THEME.ApplyEditor(parent); return
        end
        EDITOR.selectedLink = nil
    end
    if not node then label(parent, 'Select a graph component or authored connection.'); return end
    local resolved = EDITOR.document:Resolve(id)
    local definition = MAP.Types[resolved and resolved.type or node.type]
    label(parent, nodeLabel(id, node)); label(parent, id .. '  [' .. tostring(node.type or node.preset) .. ']')
    if node.generatedBy then
        label(parent, 'Generated by ' .. node.generatedBy .. ' because its configuration requires this supporting component.')
        label(parent, 'Its graph position is editable here; change runtime settings through owner overrides.')
    end
    if not node.generatedBy then
        label(parent, 'Display label')
        textEntry(parent, node.editor and node.editor.label or '', function(value)
            edit(function(document)
                local declaration = document:Find(id)
                if not declaration then return false, 'Component declaration is unavailable' end
                declaration.editor = declaration.editor or {}
                declaration.editor.label = value ~= '' and value or nil
                return true
            end)
        end)
    end
    label(parent, 'Graph group')
    textEntry(parent, node.editor and node.editor.group or '', function(value) changed(EDITOR.document:Group(EDITOR.selection, value)) end)
    if definition then
        button(parent, resolved and resolved.type == 'rbmk.core' and 'Open reactor settings' or 'Open component settings', function()
            configurationEditor(id, resolved, definition)
        end)
        label(parent, 'Settings open in a typed, resizable properties window.')
        if not node.generatedBy then button(parent, 'Bind derived capacity', function()
            local destinations = {}
            for name, field in pairs(definition.fields) do if field.type == 'number' then destinations[name] = {label = field.unit or 'numeric field'} end end
            choose('Derived configuration field', destinations, function(field)
                local items = {}
                for targetId, target in pairs(EDITOR.compiled and EDITOR.compiled.nodes or {}) do
                    for capacity, descriptor in pairs(MAP.Types[target.type].capacities or {}) do
                        if not definition.fields[field].unit or definition.fields[field].unit == descriptor.unit then
                            items[targetId .. '.' .. capacity] = {label = descriptor.unit, component = targetId, field = capacity, unit = descriptor.unit, scale = 1, offset = 0}
                        end
                    end
                end
                choose('Capacity source', items, function(_, selected)
                    local frame = window('Derived capacity transform', 500, 330)
                    local content = frame:Add('DScrollPanel'); content:Dock(FILL)
                    local ref = {component = selected.component, field = selected.field, unit = selected.unit, scale = 1, offset = 0}
                    fieldEditor(content, 'Scale', {type = 'number'}, 1, function(value) ref.scale = value end)
                    fieldEditor(content, 'Offset', {type = 'number', unit = selected.unit}, 0, function(value) ref.offset = value end)
                    button(content, 'Apply derivation', function()
                        edit(function(document)
                            local declaration = document:Find(id); declaration.derived = declaration.derived or {}; declaration.derived[field] = ref
                            if document.manifest.overrides and document.manifest.overrides[id] then document.manifest.overrides[id][field] = nil end
                            return true
                        end)
                        frame:Close()
                    end)
                end)
            end)
        end) end
        if resolved and resolved.type == 'rbmk.core' then button(parent, 'Edit reactor cell grid', function() gridEditor(id, resolved) end) end
        local portNames = keys(definition.ports)
        if #portNames > 0 then label(parent, 'Ports: ' .. table.concat(portNames, ', ') .. ' (connect from the node context menu)') end
    end
    for path, pack in pairs(EDITOR.document.packs) do
        for index, link in ipairs(pack.links or {}) do
            if link.from.component == id or link.to.component == id then
                button(parent, 'Remove link: ' .. link.from.component .. '/' .. link.from.port .. ' > ' .. link.to.component .. '/' .. link.to.port,
                    function() edit(function(document) table.remove(document.packs[path].links, index); return true end) end)
            end
        end
    end
    label(parent, 'Inspection (read only)')
    local inspection = parent:Add('DPanel'); inspection:Dock(TOP); inspection:SetTall(0)
    EDITOR.RefreshState = function()
        if not IsValid(inspection) then return end
        inspection:Clear()
        local snapshot = MAP.Client.state[id]
        local names = keys(type(snapshot) == 'table' and snapshot or {})
        inspection:SetTall(#names * 24)
        for _, name in ipairs(names) do label(inspection, name .. ': ' .. tostring(snapshot[name])) end
        THEME.ApplyEditor(inspection)
    end
    EDITOR.RefreshState()
    THEME.ApplyEditor(parent)
end

local function newDocument()
    EDITOR.savedRevision = 0
    EDITOR.pack = 'new/plant.json'
    EDITOR.path = 'new/map.json'
    EDITOR.document = MAP.NewDocument({schema = MAP.Schema, id = 'new_map', packages = keys(MAP.Packages), packs = {EDITOR.pack}},
        {[EDITOR.pack] = {schema = MAP.ComponentSchema, id = 'new_plant', components = MAP.Array(), links = MAP.Array()}})
    EDITOR.selection = {}; changed(true)
end
local function draft(family, path)
    if not MAP.SourcePath(family, path) then return nil end
    return 'luasquare/' .. family .. '/drafts/' .. path
end
local function saveDrafts(overwriteApproved)
    local paths = {{family = 'map', path = EDITOR.path, source = EDITOR.document.manifest}}
    for path, source in pairs(EDITOR.document.packs) do paths[#paths + 1] = {family = 'components', path = path, source = source} end
    local prepared, existing = {}, 0
    for _, item in ipairs(paths) do
        local path, bytes = draft(item.family, item.path), MAP.CanonicalJSON(item.source)
        if not path or not bytes or #bytes > MAP.Limits.bytes then report('Invalid draft path or excessive source'); return end
        prepared[#prepared + 1] = {path = path, bytes = bytes}
        if file.Exists(path, 'DATA') then existing = existing + 1 end
    end
    if existing > 0 and not overwriteApproved then
        Derma_Query('Export would overwrite ' .. existing .. ' existing draft file(s). Continue?', 'Export plant drafts', 'Overwrite drafts',
            function() saveDrafts(true) end, 'Cancel')
        return
    end
    for _, item in ipairs(prepared) do
        file.CreateDir(item.path:match('^(.*)/[^/]+$')); file.Write(item.path, item.bytes)
    end
    report('Drafts exported under data/luasquare/{map,components}/drafts/. Promote manually and reload the map.')
    EDITOR.savedRevision = EDITOR.document.revision
end
local function manifestEditor()
    local frame = window('Manifest settings', 600, 650)
    local scroll = frame:Add('DScrollPanel'); scroll:Dock(FILL)
    local function rebuild()
        scroll:Clear()
        label(scroll, 'Map instance ID')
        textEntry(scroll, EDITOR.document.manifest.id, function(value)
            if not MAP.IsId(value) then report('Invalid map instance ID'); return end
            edit(function(document) document.manifest.id = value; return true end)
        end)
        label(scroll, 'Trusted packages')
        local selected = {}
        for _, entry in ipairs(EDITOR.document.manifest.packages or {}) do selected[type(entry) == 'table' and entry.id or entry] = true end
        for _, id in ipairs(keys(MAP.Packages)) do
            fieldEditor(scroll, id, {type = 'boolean'}, selected[id] == true, function(value)
                edit(function(document)
                    selected[id] = value or nil; document.manifest.packages = keys(selected); return true
                end)
            end)
        end
        label(scroll, 'Simulation intervals (seconds; map reload required)')
        local namespaces = {LUASQUARE_3D2D = true, LUASQUARE_ANNUNCIATOR = true}
        for namespace in pairs((EDITOR.document.manifest.startup or {}).intervals or {}) do namespaces[namespace] = true end
        for _, namespace in ipairs(keys(namespaces)) do
            fieldEditor(scroll, namespace, {type = 'number', min = 0.02, max = 10, optional = true, unit = 's'},
                ((EDITOR.document.manifest.startup or {}).intervals or {})[namespace], function(value)
                    edit(function(document)
                        document.manifest.startup = document.manifest.startup or {}
                        document.manifest.startup.intervals = document.manifest.startup.intervals or {}
                        document.manifest.startup.intervals[namespace] = value; return true
                    end)
                end)
        end
        for _, family in ipairs({'control', '3d2display', 'audio', 'annunciator', 'timeline'}) do
            label(scroll, family .. ' sources')
            button(scroll, 'Add ' .. family .. ' source', function()
                local items = {}
                for _, path in ipairs((MAP.Client.catalog and MAP.Client.catalog.sources[family]) or {}) do items[path] = {label = family} end
                choose('Select ' .. family .. ' source', items, function(path)
                    edit(function(document)
                        document.manifest.sources = document.manifest.sources or {}
                        local paths = document.manifest.sources[family] or {}
                        for _, existing in ipairs(paths) do if existing == path then return false, 'Source already selected' end end
                        paths[#paths + 1] = path; document.manifest.sources[family] = paths; return true
                    end)
                    rebuild()
                end)
            end)
            for index, path in ipairs((EDITOR.document.manifest.sources or {})[family] or {}) do
                button(scroll, 'Remove ' .. path, function()
                    edit(function(document) table.remove(document.manifest.sources[family], index); return true end); rebuild()
                end)
            end
        end
        THEME.ApplyEditor(frame)
    end
    rebuild()
end

local function sourceManager()
    if IsValid(EDITOR.SourceManager) then EDITOR.SourceManager:MakePopup(); return end
    local outer = window('Plant source manager', 820, 680); EDITOR.SourceManager = outer
    local actions = outer:Add('DPanel'); actions:Dock(TOP); actions:SetTall(92)
    local exportPath = actions:Add('DTextEntry'); exportPath:Dock(TOP); exportPath:SetTall(28); exportPath:SetText(EDITOR.path or 'new/map.json')
    exportPath:SetPlaceholderText('Draft export path, for example my_map/main.json')
    exportPath:SetTooltip('Destination under data/luasquare/map/drafts/. Loading uses the browsers below; this field only chooses where Export writes.')
    local actionRow = actions:Add('DPanel'); actionRow:Dock(FILL)
    local function action(text, width, tooltip, callback)
        local control = actionRow:Add('DButton'); control:Dock(LEFT); control:SetWide(width); control:SetText(text); control:SetTooltip(tooltip); control.DoClick = callback
        return control
    end
    action('New document', 120, 'Start a new unsaved manifest and component pack.', function()
        newDocument(); exportPath:SetText(EDITOR.path)
    end)
    action('Create pack', 110, 'Create and select another component pack in this document.', function()
        local dialog = window('New component pack', 500, 260)
        label(dialog, 'Relative path, for example my_map/pumps.json. Press Enter to create.')
        textEntry(dialog, '', function(value)
            if not MAP.SourcePath('components', value) or EDITOR.document.packs[value] then report('Invalid or duplicate component pack path'); return end
            local id = value:gsub('%.json$', ''):gsub('/', '.')
            if not MAP.IsId(id) then report('Invalid component pack ID'); return end
            edit(function(document)
                document.packs[value] = {schema = MAP.ComponentSchema, id = id, components = MAP.Array(), links = MAP.Array()}
                document.manifest.packs[#document.manifest.packs + 1] = value
                EDITOR.pack = value; return true
            end)
            dialog:Close()
        end)
    end)
    action('Active pack', 105, 'Choose which included component pack receives newly added nodes and links.', function()
        choose('Component packs', EDITOR.document.packs, function(id) EDITOR.pack = id; report('Active pack: ' .. id) end)
    end)
    action('Attach pack', 105, 'Attach a packed read-only component source to the current draft document.', function()
        local items = {}; for _, name in ipairs(((MAP.Client.catalog or {}).sources or {}).components or {}) do items[name] = {label = 'Packed component pack'} end
        choose('Attach component pack', items, function(id)
            if EDITOR.document.packs[id] then report('Pack is already included'); return end
            EDITOR.attachPath = id; MAP.InspectionRequest(2, 'components', id)
        end)
    end)
    action('Export drafts', 120, 'Write the manifest and every included pack under data/ after an overwrite check.', function()
        EDITOR.path = exportPath:GetValue(); saveDrafts()
    end)

    local sheets = outer:Add('DPropertySheet'); sheets:Dock(FILL)
    local packed = vgui.Create('DPanel', sheets)
    local packedHint = label(packed, 'Packed manifests are read-only. Select a row, then use Load selected manifest.')
    packedHint:SetTooltip('Packed sources come from data_static and cannot be overwritten by this editor.')
    local packedSearch = packed:Add('DTextEntry'); packedSearch:Dock(TOP); packedSearch:SetTall(28); packedSearch:SetPlaceholderText('Search packed manifests')
    local packedLoad = packed:Add('DButton'); packedLoad:Dock(BOTTOM); packedLoad:SetTall(32); packedLoad:SetText('Load selected packed manifest')
    packedLoad:SetTooltip('Load the highlighted manifest and all of its declared component packs into a local editable document.')
    local packedList = packed:Add('DListView'); packedList:Dock(FILL); packedList:SetMultiSelect(false); packedList:AddColumn('Manifest path')
    local packedSelection
    local function rebuildPacked()
        packedList:Clear(); local query = packedSearch:GetValue():lower()
        for _, name in ipairs((((MAP.Client or {}).catalog or {}).sources or {}).map or {}) do
            if name:lower():find(query, 1, true) then local row = packedList:AddLine(name); row.ManifestPath = name end
        end
    end
    local function loadPacked(row)
        local selected = row and row.ManifestPath or packedSelection
        if not selected then report('Select a packed manifest first.'); return end
        EDITOR.path = selected; exportPath:SetText(selected); EDITOR.pending = nil
        report('Loading packed manifest ' .. selected .. ' ...')
        MAP.InspectionRequest(2, 'map', selected)
    end
    packedSearch.OnChange = rebuildPacked
    packedList.OnRowSelected = function(_, _, row) packedSelection = row.ManifestPath end
    packedList.DoDoubleClick = function(_, _, row) loadPacked(row) end
    packedLoad.DoClick = function() loadPacked() end
    sheets:AddSheet('Packed manifests', packed, 'icon16/package.png')

    local drafts = vgui.Create('DPanel', sheets)
    local draftHint = label(drafts, 'Browse saved manifest drafts. Component drafts declared by the selected manifest load with it.')
    draftHint:SetTooltip('Drafts live under data/luasquare/map/drafts/ and never activate automatically.')
    local draftLoad = drafts:Add('DButton'); draftLoad:Dock(BOTTOM); draftLoad:SetTall(32); draftLoad:SetText('Load selected local draft')
    draftLoad:SetTooltip('Open the highlighted manifest draft without changing the running plant.')
    local browser = drafts:Add('DFileBrowser'); browser:Dock(FILL); browser:SetPath('DATA'); browser:SetBaseFolder('luasquare/map/drafts')
    browser:SetFileTypes('*.json'); browser:SetOpen(true)
    local draftSelection
    browser.OnSelect = function(_, selected) draftSelection = tostring(selected or ''):gsub('\\', '/') end
    local function draftRelative(selected)
        local prefix = 'luasquare/map/drafts/'
        local relative = selected and selected:sub(1, #prefix) == prefix and selected:sub(#prefix + 1) or selected
        return relative and MAP.SourcePath('map', relative) and relative or nil
    end
    local function loadDraft()
        local relative = draftRelative(draftSelection)
        local location = relative and draft('map', relative)
        local manifest, err = location and MAP.DecodeJSON(file.Read(location, 'DATA'))
        if not manifest then report(err or 'Invalid draft path'); return end
        local packs = {}
        for _, name in ipairs(manifest.packs or {}) do
            local packPath = draft('components', name)
            local pack, problem = packPath and MAP.DecodeJSON(file.Read(packPath, 'DATA'))
            if not pack then report(problem or 'Missing component draft'); return end
            packs[name] = pack
        end
        EDITOR.path, EDITOR.pack = relative, manifest.packs[1]
        exportPath:SetText(relative)
        EDITOR.document = MAP.NewDocument(manifest, packs); EDITOR.selection = {}; changed(true)
        EDITOR.savedRevision = 0
    end
    draftLoad.DoClick = loadDraft
    sheets:AddSheet('Local drafts', drafts, 'icon16/folder_page.png')
    EDITOR.SourceManagerRefresh = rebuildPacked
    outer.OnRemove = function() if EDITOR.SourceManager == outer then EDITOR.SourceManager, EDITOR.SourceManagerRefresh = nil, nil end end
    rebuildPacked(); THEME.ApplyEditor(outer)
end

local function legacyOpen()
    if IsValid(EDITOR.Frame) then EDITOR.Frame:MakePopup(); return end
    EDITOR.children, EDITOR.selection = {}, {}
    local frame = window('Luasquare plant graph — structural preview', 1280, 820); EDITOR.Frame = frame
    frame.btnMaxim:SetEnabled(true)
    frame.btnMaxim.DoClick = function()
        if frame.WindowBounds then
            local bounds = frame.WindowBounds; frame:SetSize(bounds.w, bounds.h); frame:SetPos(bounds.x, bounds.y); frame.WindowBounds = nil
        else
            local x, y = frame:GetPos(); frame.WindowBounds = {x = x, y = y, w = frame:GetWide(), h = frame:GetTall()}
            frame:SetPos(0, 0); frame:SetSize(ScrW(), ScrH())
        end
    end
    local status = frame:Add('DTextEntry'); status:Dock(BOTTOM); status:SetTall(90); status:SetMultiline(true); status:SetEditable(false); EDITOR.Status = status
    local toolbar = frame:Add('DPanel'); toolbar:Dock(LEFT); toolbar:SetWide(180)
    local inspector = frame:Add('DScrollPanel'); inspector:Dock(RIGHT); inspector:SetWide(320); EDITOR.Inspector = inspector
    local canvas = frame:Add('DPanel'); canvas:Dock(FILL)
    local panX, panY, zoom = 40, 40, 1
    local drag
    local function position(node, index)
        local editor = type(node.editor) == 'table' and node.editor or {}
        return MAP.Finite(editor.x) and editor.x or (index - 1) % 4 * 220, MAP.Finite(editor.y) and editor.y or math.floor((index - 1) / 4) * 100
    end
    local function nodes()
        local result = {}; for path, pack in pairs(EDITOR.document.packs) do for _, node in ipairs(pack.components) do result[#result + 1] = {node = node, path = path} end end
        for _, node in pairs(EDITOR.compiled and EDITOR.compiled.nodes or {}) do
            if node.generatedBy then result[#result + 1] = {node = node, path = 'generated: ' .. node.generatedBy} end
        end
        table.sort(result, function(a, b) return a.node.id < b.node.id end); return result
    end
    canvas.Paint = function(_, width, height)
        surface.SetDrawColor(background); surface.DrawRect(0, 0, width, height)
        local positions = {}
        for index, entry in ipairs(nodes()) do local x, y = position(entry.node, index); positions[entry.node.id] = {x = x * zoom + panX, y = y * zoom + panY} end
        surface.SetDrawColor(125, 145, 150)
        for _, pack in pairs(EDITOR.document.packs) do for _, link in ipairs(pack.links or {}) do
            local a, b = positions[link.from.component], positions[link.to.component]
            if a and b then surface.DrawLine(a.x + 95 * zoom, a.y + 32 * zoom, b.x + 95 * zoom, b.y + 32 * zoom) end
        end end
        local function referenceLines(value, descriptor, owner)
            if descriptor.type == 'id' and positions[value] then
                local a, b = positions[owner], positions[value]
                if a and b and owner ~= value then surface.DrawLine(a.x + 180 * zoom, a.y + 60 * zoom, b.x + 10 * zoom, b.y + 10 * zoom) end
            elseif type(value) == 'table' and descriptor.type == 'object' then
                for key, field in pairs(descriptor.fields or {}) do if key ~= 'port' then referenceLines(value[key], field, owner) end end
            elseif type(value) == 'table' and descriptor.type == 'array' then
                for _, item in ipairs(value) do referenceLines(item, descriptor.items, owner) end
            end
        end
        surface.SetDrawColor(95, 110, 115)
        for id, node in pairs(EDITOR.compiled and EDITOR.compiled.nodes or {}) do
            referenceLines(node.config, {type = 'object', fields = MAP.Types[node.type].fields}, id)
        end
        for _, entry in ipairs(nodes()) do
            local node, at = entry.node, positions[entry.node.id]
            surface.SetDrawColor(EDITOR.selection[node.id] and Color(85, 105, 115) or Color(62, 62, 62)); surface.DrawRect(at.x, at.y, 190 * zoom, 70 * zoom)
            draw.SimpleText(node.id, 'DermaDefaultBold', at.x + 5, at.y + 5, foreground)
            draw.SimpleText(node.type or ('preset: ' .. tostring(node.preset)), 'DermaDefault', at.x + 5, at.y + 23, foreground)
            draw.SimpleText((node.editor and node.editor.group or '') .. '  ' .. entry.path, 'DermaDefault', at.x + 5, at.y + 42, Color(180, 180, 180))
        end
    end
    canvas.OnMouseWheeled = function(panel, delta)
        local x, y = panel:LocalCursorPos(); local previous = zoom; zoom = math.Clamp(zoom * (delta > 0 and 1.15 or 1 / 1.15), 0.2, 3)
        panX, panY = x - (x - panX) / previous * zoom, y - (y - panY) / previous * zoom; return true
    end
    canvas.OnMousePressed = function(panel, code)
        local x, y = panel:LocalCursorPos()
        if code == MOUSE_RIGHT then drag = {x = x, y = y, panX = panX, panY = panY}; panel:MouseCapture(true); return end
        for index, entry in ipairs(nodes()) do
            local nx, ny = position(entry.node, index)
            if x >= nx * zoom + panX and x <= (nx + 190) * zoom + panX and y >= ny * zoom + panY and y <= (ny + 70) * zoom + panY then
                if not input.IsKeyDown(KEY_LCONTROL) then EDITOR.selection = {} end
                EDITOR.selection[entry.node.id] = true
                drag = {x = x, y = y, origins = {}}
                for i, selected in ipairs(nodes()) do if EDITOR.selection[selected.node.id] and not selected.node.generatedBy then local a, b = position(selected.node, i); drag.origins[selected.node.id] = {x = a, y = b} end end
                panel:MouseCapture(true); EDITOR.RefreshInspector(); MAP.InspectionRequest(3, keys(EDITOR.selection)); return
            end
        end
        EDITOR.selection = {}; EDITOR.RefreshInspector(); MAP.InspectionRequest(3, {})
    end
    canvas.OnMouseReleased = function(panel)
        if drag and drag.origins then
            local x, y = panel:LocalCursorPos(); local movement = drag
            edit(function()
                for id, origin in pairs(movement.origins) do
                    local node = EDITOR.document:Find(id); node.editor = node.editor or {}
                    node.editor.x = math.Round((origin.x + (x - movement.x) / zoom) / 16) * 16
                    node.editor.y = math.Round((origin.y + (y - movement.y) / zoom) / 16) * 16
                end
                return true
            end)
        end
        drag = nil; panel:MouseCapture(false)
    end
    canvas.Think = function(panel)
        if drag and not drag.origins then local x, y = panel:LocalCursorPos(); panX, panY = drag.panX + x - drag.x, drag.panY + y - drag.y end
    end
    button(toolbar, 'Sources / drafts', sourceManager)
    button(toolbar, 'Find component', function()
        local items = {}; for _, entry in ipairs(nodes()) do items[entry.node.id] = entry.node end
        choose('Components', items, function(id)
            EDITOR.selection = {[id] = true}; EDITOR.RefreshInspector(); MAP.InspectionRequest(3, {id})
            for index, entry in ipairs(nodes()) do if entry.node.id == id then
                local x, y = position(entry.node, index); panX, panY = 30 - x * zoom, 30 - y * zoom; break
            end end
        end)
    end)
    button(toolbar, 'Add component', function()
        choose('Component catalog', MAP.Types, function(typeId, definition)
            local base, index = typeId:gsub('%.', '_'), 1
            while EDITOR.document:Find(base .. '_' .. index) do index = index + 1 end
            edit(function()
                local config = MAP.Object(); for name, field in pairs(definition.fields) do if not field.optional then config[name] = defaultValue(field) end end
                table.insert(EDITOR.document.packs[EDITOR.pack].components, {id = base .. '_' .. index, type = typeId, config = config})
                return true
            end)
        end)
    end)
    button(toolbar, 'Duplicate selection', function() changed(EDITOR.document:Duplicate(EDITOR.selection, EDITOR.pack)) end)
    button(toolbar, 'Remove selection', function() changed(EDITOR.document:Remove(EDITOR.selection)) end)
    button(toolbar, 'Undo', function() changed(EDITOR.document:History(false)) end)
    button(toolbar, 'Redo', function() changed(EDITOR.document:History(true)) end)
    button(toolbar, 'Validate structure', function() changed(true) end)
    button(toolbar, 'Find diagnostic', function()
        local items = {}
        for index, diagnostic in ipairs(EDITOR.diagnostics or {}) do
            local id = tostring(index) .. ': ' .. tostring(diagnostic.path)
            items[id] = {label = diagnostic.message, diagnostic = diagnostic}
        end
        choose('Compiler diagnostics', items, function(_, item)
            local diagnostic, selected = item.diagnostic
            for path, pack in pairs(EDITOR.document.packs) do
                local index = tonumber((diagnostic.path or ''):match('^components%.(%d+)'))
                if diagnostic.source == MAP.SourcePath('components', path) and index and pack.components[index] then selected = pack.components[index].id end
                for _, node in ipairs(pack.components) do
                    if (diagnostic.path or ''):sub(1, #node.id) == node.id then selected = node.id end
                end
            end
            if selected then EDITOR.selection = {[selected] = true}; EDITOR.RefreshInspector() end
            report((diagnostic.path or '') .. ': ' .. diagnostic.message)
        end)
    end)
    button(toolbar, 'Create preset', function()
        local id = keys(EDITOR.selection)[1]; if not id then return end
        local frame = window('Reusable component preset', 400, 260)
        textEntry(frame, id .. '.preset', function(name) changed(EDITOR.document:MakePreset(id, name, EDITOR.pack)); frame:Close() end)
    end)
    button(toolbar, 'Add from preset', function()
        local items = {}
        for _, pack in pairs(EDITOR.document.packs) do
            for id, preset in pairs(pack.presets or {}) do items[id] = {label = preset.type} end
        end
        choose('Reusable presets', items, function(preset)
            local index, id = 1, preset .. '_1'
            while EDITOR.document:Find(id) do index = index + 1; id = preset .. '_' .. index end
            if not MAP.IsId(id) then report('Generated component ID exceeds limit'); return end
            edit(function(document)
                table.insert(document.packs[EDITOR.pack].components, {id = id, preset = preset, config = MAP.Object()}); return true
            end)
        end)
    end)
    label(toolbar, 'Wheel: zoom'); label(toolbar, 'Right drag: pan'); label(toolbar, 'Ctrl: multiple selection'); label(toolbar, 'Drag: snap to 16 units')
    local frameThink = frame.Think
    frame.Think = function(self)
        if frameThink then frameThink(self) end
        if input.IsMouseDown(MOUSE_LEFT) then return end
        local hovered, underCursor = vgui.GetHoveredPanel(), {}
        while IsValid(hovered) do
            if hovered:GetClassName() == 'DMenu' or hovered:IsModal() then return end
            underCursor[hovered] = true
            hovered = hovered:GetParent()
        end
        local candidate
        for index = #EDITOR.children, 1, -1 do
            local child = EDITOR.children[index]
            if IsValid(child) and child:IsVisible() then
                local x, y = child:LocalCursorPos()
                if x >= 0 and y >= 0 and x < child:GetWide() and y < child:GetTall() then
                    candidate = candidate or child
                    if underCursor[child] then candidate = child; break end
                end
            end
        end
        if candidate and not candidate:IsActive() then candidate:MoveToFront(); candidate:RequestFocus() end
    end
    local nativeClose = frame.Close
    frame.Close = function(self)
        if not self.CloseApproved and EDITOR.document and EDITOR.document.revision ~= (EDITOR.savedRevision or 0) then
            Derma_Query('Discard unsaved plant draft changes?', 'Plant editor', 'Discard', function() self.CloseApproved = true; self:Close() end, 'Keep editing')
            return
        end
        nativeClose(self)
    end
    frame.OnRemove = function()
        for _, child in ipairs(EDITOR.children) do if IsValid(child) then child:Remove() end end
        EDITOR.children, EDITOR.selection, EDITOR.pending = {}, {}, nil
        EDITOR.document, EDITOR.compiled, EDITOR.RefreshState, EDITOR.savedRevision = nil, nil, nil, nil
        MAP.CloseInspection()
    end
    newDocument(); THEME.ApplyEditor(frame); MAP.InspectionRequest(1)
end

local nodeColors = {
    source = Color(120, 150, 165), machinery = Color(190, 140, 75), powerplant = Color(70, 150, 190),
    rbmk = Color(185, 95, 80), instruments = Color(165, 135, 200), presentation = Color(95, 175, 125)
}
local linkColors = {fluid = Color(70, 165, 220), electrical = Color(235, 195, 70), references = Color(145, 145, 155)}
local electricalKinds = {['plant.grid'] = true, ['plant.breaker'] = true, ['plant.transformer'] = true,
    ['plant.generator'] = true, ['plant.diesel'] = true}

local function portCategory(port)
    if not port then return 'references' end
    if port.kind == 'fluid' or port.kind == 'thermal' then return 'fluid' end
    if electricalKinds[port.kind] then return 'electrical' end
    return 'references'
end

local function compatiblePorts(source, target)
    return source and target and source.kind == target.kind
        and (not source.unit or not target.unit or source.unit == target.unit)
        and (not source.fluid or not target.fluid or source.fluid == target.fluid)
        and not (source.direction == 'out' and target.direction == 'out')
        and not (source.direction == 'in' and target.direction == 'in')
end

function EDITOR.Open()
    if IsValid(EDITOR.Frame) then EDITOR.Frame:MakePopup(); return end
    EDITOR.children, EDITOR.selection, EDITOR.viewMode, EDITOR.workspaceMode, EDITOR.connecting, EDITOR.selectedLink = {}, {}, 'all', 'graph', nil, nil
    local frame = window('Luasquare plant graph — structural preview', 1280, 820); EDITOR.Frame = frame
    frame.btnMaxim:SetEnabled(true); frame.btnMinim:SetEnabled(true)
    frame.btnMaxim.DoClick = function()
        if frame.WindowBounds then
            local bounds = frame.WindowBounds; frame:SetSize(bounds.w, bounds.h); frame:SetPos(bounds.x, bounds.y); frame.WindowBounds = nil
        else
            local x, y = frame:GetPos(); frame.WindowBounds = {x = x, y = y, w = frame:GetWide(), h = frame:GetTall()}
            frame:SetPos(0, 0); frame:SetSize(ScrW(), ScrH())
        end
    end
    local status = frame:Add('DTextEntry'); status:Dock(BOTTOM); status:SetTall(90); status:SetMultiline(true); status:SetEditable(false); EDITOR.Status = status
    local toolbar = frame:Add('DPanel'); toolbar:Dock(TOP); toolbar:SetTall(30); EDITOR.Toolbar = toolbar
    local function tool(text, width, callback)
        local control = toolbar:Add('DButton'); control:Dock(LEFT); control:SetWide(width or 92); control:SetText(text); control.DoClick = callback; THEME.Apply(control)
        return control
    end
    local inspector = frame:Add('DScrollPanel'); inspector:Dock(RIGHT); inspector:SetWide(340); EDITOR.Inspector = inspector
    local splitter = frame:Add('DPanel'); splitter:Dock(RIGHT); splitter:SetWide(7); splitter:SetCursor('sizewe'); EDITOR.Splitter = splitter
    splitter.OnMousePressed = function(panel)
        local x = gui.MouseX and gui.MouseX() or 0
        panel.Resize = {x = x, width = inspector:GetWide()}; panel:MouseCapture(true)
    end
    splitter.OnMouseReleased = function(panel) panel.Resize = nil; panel:MouseCapture(false) end
    splitter.Think = function(panel)
        if panel.Resize then
            local x = gui.MouseX and gui.MouseX() or panel.Resize.x
            inspector:SetWide(math.Clamp(panel.Resize.width + panel.Resize.x - x, 260, math.max(frame:GetWide() - 420, 260)))
        end
    end
    local workspace = frame:Add('DPanel'); workspace:Dock(FILL); EDITOR.Workspace = workspace
    local canvas = workspace:Add('DPanel'); canvas:Dock(FILL); EDITOR.Canvas = canvas
    local panX, panY, zoom, drag = 40, 40, 1, nil
    local NODE_W, NODE_H = 190, 70
    local function managedDefinition(definition, typeId)
        return definition.package == 'source' or definition.package == 'instruments' or definition.package == 'presentation'
            or typeId == 'rbmk.presentation'
    end
    local function generatedEditor(id)
        return (((EDITOR.document.manifest.editor or {}).generatedPositions or {})[id])
    end
    local function entries(includeManaged)
        local result = {}
        local function include(node)
            local resolved = EDITOR.document:Resolve(node.id) or node
            local definition = MAP.Types[resolved.type] or {}
            return includeManaged or not managedDefinition(definition, resolved.type)
        end
        for path, pack in pairs(EDITOR.document.packs) do for _, node in ipairs(pack.components or {}) do
            if include(node) then result[#result + 1] = {node = node, path = path} end
        end end
        for _, node in pairs(EDITOR.compiled and EDITOR.compiled.nodes or {}) do
            if node.generatedBy and include(node) then result[#result + 1] = {node = node, path = 'generated: ' .. node.generatedBy} end
        end
        table.sort(result, function(a, b) return a.node.id < b.node.id end)
        return result
    end
    local function position(entry, index)
        local editor = entry.node.generatedBy and generatedEditor(entry.node.id)
            or type(entry.node.editor) == 'table' and entry.node.editor or {}
        local x, y = MAP.Finite(editor.x) and editor.x or (index - 1) % 4 * 220, MAP.Finite(editor.y) and editor.y or math.floor((index - 1) / 4) * 100
        if drag and drag.kind == 'nodes' and drag.origins[entry.node.id] then x, y = x + drag.dx / zoom, y + drag.dy / zoom end
        return x, y
    end
    local function borderPoint(from, to)
        local fx, fy = from.x + NODE_W / 2, from.y + NODE_H / 2
        local tx, ty = to.x + NODE_W / 2, to.y + NODE_H / 2
        if math.abs(tx - fx) >= math.abs(ty - fy) then
            return {x = from.x + (tx >= fx and NODE_W or 0), y = fy}, 'horizontal'
        end
        return {x = fx, y = from.y + (ty >= fy and NODE_H or 0)}, 'vertical'
    end
    local function borderDirection(node, point)
        local epsilon = 0.001
        if math.abs(point.x - node.x) <= epsilon then return {x = 1, y = 0} end
        if math.abs(point.x - node.x - NODE_W) <= epsilon then return {x = -1, y = 0} end
        if math.abs(point.y - node.y) <= epsilon then return {x = 0, y = 1} end
        return {x = 0, y = -1}
    end
    local function route(a, b, anchor)
        local first, axis = borderPoint(a, b)
        local last = borderPoint(b, a)
        anchor = anchor or {x = (first.x + last.x) / 2, y = (first.y + last.y) / 2}
        local points = {first}
        if axis == 'horizontal' then
            points[#points + 1] = {x = anchor.x, y = first.y}
            points[#points + 1] = {x = anchor.x, y = last.y}
        else
            points[#points + 1] = {x = first.x, y = anchor.y}
            points[#points + 1] = {x = last.x, y = anchor.y}
        end
        points[#points + 1] = last
        return points, anchor
    end
    local function draggedAnchor(link, anchor, key)
        if drag and drag.kind == 'bend' and drag.item.key == key then
            return {x = anchor.x + drag.dx / zoom, y = anchor.y + drag.dy / zoom}
        end
        if not drag or drag.kind ~= 'nodes' then return anchor end
        local count = (drag.origins[link.from.component] and 1 or 0) + (drag.origins[link.to.component] and 1 or 0)
        if count == 0 then return anchor end
        return {x = anchor.x + drag.dx / zoom * count / 2, y = anchor.y + drag.dy / zoom * count / 2}
    end
    local function graph()
        local result = {entries = entries(), positions = {}, byId = {}, links = {}}
        for index, entry in ipairs(result.entries) do
            local x, y = position(entry, index)
            result.positions[entry.node.id] = {x = x, y = y, sx = x * zoom + panX, sy = y * zoom + panY}
            result.byId[entry.node.id] = entry
        end
        for path, pack in pairs(EDITOR.document.packs) do for index, link in ipairs(pack.links or {}) do
            local a, b = result.positions[link.from.component], result.positions[link.to.component]
            if a and b then
                local fromNode, toNode = EDITOR.document:Resolve(link.from.component), EDITOR.document:Resolve(link.to.component)
                local fromPort = fromNode and (MAP.Types[fromNode.type].ports or {})[link.from.port]
                local toPort = toNode and (MAP.Types[toNode.type].ports or {})[link.to.port]
                local category = portCategory(fromPort or toPort)
                local bends = link.editor and link.editor.bends
                local anchor = bends and bends[1] and {x = bends[1].x, y = bends[1].y} or nil
                local key = 'link:' .. path .. ':' .. index
                if not anchor then anchor = select(2, route(a, b)) end
                local points; points, anchor = route(a, b, draggedAnchor(link, anchor, key))
                result.links[#result.links + 1] = {key = key, path = path, index = index, value = link, category = category,
                    points = points, anchor = anchor, arrow = borderDirection(b, points[#points]),
                    reverseArrow = borderDirection(a, points[1]), fromPort = fromPort, toPort = toPort}
            end
        end end
        local function references(value, descriptor, owner)
            local a, b = result.positions[owner], result.positions[value]
            if descriptor.type == 'id' and descriptor.asset ~= 'name' and a and b and value ~= owner then
                local target = EDITOR.compiled and EDITOR.compiled.nodes[value]
                local category = target and electricalKinds[target.type] and 'electrical' or 'references'
                local ref = {from = {component = owner}, to = {component = value}}
                local referenceKey, key = owner .. '>' .. value, 'reference:' .. owner .. '>' .. value
                local anchor = (((EDITOR.document.manifest.editor or {}).referenceBends or {})[referenceKey])
                if not anchor then anchor = select(2, route(a, b)) else anchor = {x = anchor.x, y = anchor.y} end
                local points; points, anchor = route(a, b, draggedAnchor(ref, anchor, key))
                result.links[#result.links + 1] = {key = key, referenceKey = referenceKey, value = ref, category = category,
                    points = points, anchor = anchor, arrow = borderDirection(b, points[#points])}
            elseif type(value) == 'table' and descriptor.type == 'object' then
                for key, field in pairs(descriptor.fields or {}) do if key ~= 'port' then references(value[key], field, owner) end end
            elseif type(value) == 'table' and descriptor.type == 'array' then
                for _, item in ipairs(value) do references(item, descriptor.items, owner) end
            end
        end
        for id, node in pairs(EDITOR.compiled and EDITOR.compiled.nodes or {}) do
            references(node.config, {type = 'object', fields = MAP.Types[node.type].fields}, id)
        end
        EDITOR.Graph = result
        return result
    end
    local function visible(category) return EDITOR.viewMode == 'all' or EDITOR.viewMode == category end
    local function selectedLink(item)
        return EDITOR.selectedLink and EDITOR.selectedLink.key == item.key
    end
    local function highlightedLink(item)
        return selectedLink(item) or EDITOR.selection[item.value.from.component] or EDITOR.selection[item.value.to.component]
    end
    local function screen(point) return point.x * zoom + panX, point.y * zoom + panY end
    local function line(points, color, highlighted, arrow)
        surface.SetDrawColor(color)
        for index = 1, #points - 1 do
            local ax, ay, bx, by = screen(points[index]); bx, by = screen(points[index + 1])
            surface.DrawLine(ax, ay, bx, by)
            if highlighted then surface.DrawLine(ax + 1, ay + 1, bx + 1, by + 1) end
        end
        if #points > 1 then
            local bx, by = screen(points[#points])
            local angle = math.atan2 and math.atan2(arrow.y, arrow.x) or math.atan(arrow.y, arrow.x)
            local size = 8
            surface.DrawLine(bx, by, bx - math.cos(angle - 0.55) * size, by - math.sin(angle - 0.55) * size)
            surface.DrawLine(bx, by, bx - math.cos(angle + 0.55) * size, by - math.sin(angle + 0.55) * size)
        end
    end
    local function nodeAt(x, y, model)
        for index = #model.entries, 1, -1 do
            local entry, at = model.entries[index], model.positions[model.entries[index].node.id]
            if x >= at.sx and x <= at.sx + NODE_W * zoom and y >= at.sy and y <= at.sy + NODE_H * zoom then return entry, index end
        end
    end
    local function segmentDistance(x, y, ax, ay, bx, by)
        local dx, dy = bx - ax, by - ay
        local length = dx * dx + dy * dy
        local amount = length > 0 and math.Clamp(((x - ax) * dx + (y - ay) * dy) / length, 0, 1) or 0
        local px, py = ax + dx * amount, ay + dy * amount
        return math.sqrt((x - px) * (x - px) + (y - py) * (y - py))
    end
    local function hitAt(x, y, model)
        local hits = {}
        for index = #model.entries, 1, -1 do
            local entry, at = model.entries[index], model.positions[model.entries[index].node.id]
            if x >= at.sx and x <= at.sx + NODE_W * zoom and y >= at.sy and y <= at.sy + NODE_H * zoom then
                hits[#hits + 1] = {kind = 'node', entry = entry, key = 'node:' .. entry.node.id}
            end
        end
        for index = #model.links, 1, -1 do
            local item = model.links[index]
            if visible(item.category) then
                for point = 1, #item.points - 1 do
                    local ax, ay = screen(item.points[point]); local bx, by = screen(item.points[point + 1])
                    if segmentDistance(x, y, ax, ay, bx, by) <= 7 then
                        hits[#hits + 1] = {kind = 'link', item = item, key = item.key}
                        break
                    end
                end
            end
        end
        if #hits == 0 then EDITOR.hitCycle = nil; return nil end
        local cycle = EDITOR.hitCycle
        local same = cycle and math.abs(cycle.x - x) <= 4 and math.abs(cycle.y - y) <= 4 and cycle.count == #hits
        local selected = same and cycle.index % #hits + 1 or 1
        EDITOR.hitCycle = {x = x, y = y, count = #hits, index = selected}
        return hits[selected]
    end
    local function destinationPorts(sourceId, sourcePort, targetId)
        local result = {}
        local sourceNode, targetNode = EDITOR.document:Resolve(sourceId), EDITOR.document:Resolve(targetId)
        local source = sourceNode and (MAP.Types[sourceNode.type].ports or {})[sourcePort]
        for name, descriptor in pairs(targetNode and MAP.Types[targetNode.type].ports or {}) do
            if compatiblePorts(source, descriptor) then result[name] = {label = descriptor.kind .. ' ' .. (descriptor.unit or ''), descriptor = descriptor} end
        end
        return result
    end
    local function connectTo(targetId)
        local state = EDITOR.connecting
        if not state or targetId == state.component then return end
        local ports = destinationPorts(state.component, state.port, targetId)
        local names = keys(ports)
        local function commit(targetPort)
            local sourceNode = EDITOR.document:Resolve(state.component)
            local source = MAP.Types[sourceNode.type].ports[state.port]
            local from, to = {component = state.component, port = state.port}, {component = targetId, port = targetPort}
            if source.direction == 'in' then from, to = to, from end
            EDITOR.connecting = nil
            changed(EDITOR.document:Connect(from, to, EDITOR.pack))
        end
        if #names == 1 then commit(names[1]) elseif #names > 1 then choose('Destination port', ports, commit) end
    end
    local function beginConnection(id, port)
        EDITOR.connecting = {component = id, port = port}
        report('Select a highlighted compatible destination; click empty space to cancel.')
    end
    local function createPreset(id)
        local dialog = window('Reusable component preset', 400, 260)
        textEntry(dialog, id .. '.preset', function(name) changed(EDITOR.document:MakePreset(id, name, EDITOR.pack)); dialog:Close() end)
    end
    local function addTypeAt(typeId, definition, x, y)
        local base, index = typeId:gsub('%.', '_'), 1
        while EDITOR.document:Find(base .. '_' .. index) do index = index + 1 end
        local newId = base .. '_' .. index
        edit(function()
            local config = MAP.Object(); for name, field in pairs(definition.fields) do if not field.optional then config[name] = defaultValue(field) end end
            table.insert(EDITOR.document.packs[EDITOR.pack].components, {id = newId, type = typeId, config = config,
                editor = {x = math.Round(x / 16) * 16, y = math.Round(y / 16) * 16, label = definition.label or typeId}})
            return true
        end)
        EDITOR.selection, EDITOR.selectedLink = {[newId] = true}, nil
        EDITOR.RefreshInspector()
        report('Added ' .. newId .. '. Configure any required references shown in the inspector.')
    end
    local function addAt(x, y)
        local types = {}
        for id, definition in pairs(MAP.Types) do
            if definition.package ~= 'source' and definition.package ~= 'instruments' then types[id] = definition end
        end
        choose('Plant component catalog', types, function(typeId, definition) addTypeAt(typeId, definition, x, y) end)
    end
    local function addPresetAt(x, y)
        local items = {}
        for _, pack in pairs(EDITOR.document.packs) do
            for id, preset in pairs(pack.presets or {}) do items[id] = {label = preset.type} end
        end
        choose('Reusable presets', items, function(preset)
            local index, id = 1, preset .. '_1'
            while EDITOR.document:Find(id) do index = index + 1; id = preset .. '_' .. index end
            if not MAP.IsId(id) then report('Generated component ID exceeds limit'); return end
            edit(function(document)
                table.insert(document.packs[EDITOR.pack].components, {id = id, preset = preset, config = MAP.Object(),
                    editor = {x = math.Round(x / 16) * 16, y = math.Round(y / 16) * 16}})
                return true
            end)
        end)
    end
    local function showWorkspace(mode)
        EDITOR.workspaceMode = mode
        canvas:SetVisible(mode == 'graph')
        if IsValid(EDITOR.ManagedPanel) then EDITOR.ManagedPanel:SetVisible(mode == 'bindings') end
        if IsValid(EDITOR.BindingsButton) then EDITOR.BindingsButton:SetText(mode == 'bindings' and 'Graph' or 'Bindings') end
        workspace:InvalidateLayout(true)
    end
    local function managedComponents()
        if IsValid(EDITOR.ManagedPanel) then showWorkspace(EDITOR.workspaceMode == 'bindings' and 'graph' or 'bindings'); return end
        local managed = workspace:Add('DPanel'); managed:Dock(FILL); EDITOR.ManagedPanel = managed
        local actions = managed:Add('DPanel'); actions:Dock(BOTTOM); actions:SetTall(32)
        local add = actions:Add('DButton'); add:Dock(LEFT); add:SetWide(190); add:SetText('Add binding / instrument')
        add:SetTooltip('Open the searchable binding/instrument catalog. The new declaration is added to the active component pack.')
        local remove = actions:Add('DButton'); remove:Dock(LEFT); remove:SetWide(150); remove:SetText('Delete selected')
        remove:SetTooltip('Confirm deletion of the selected managed declaration in a separate dialog.')
        local hint = actions:Add('DLabel'); hint:Dock(FILL); hint:SetText('  Select a row to inspect and configure it on the right.'); hint:SetTextColor(foreground)
        local search = managed:Add('DTextEntry'); search:Dock(TOP); search:SetTall(28); search:SetPlaceholderText('Search labels, IDs and types')
        local list = managed:Add('DListView'); list:Dock(FILL); list:SetMultiSelect(false)
        list:AddColumn('Label'); list:AddColumn('ID'); list:AddColumn('Type'); list:AddColumn('Pack')
        local selected
        local function rebuild()
            if not IsValid(list) then return end
            list:Clear(); local query = search:GetValue():lower()
            for _, entry in ipairs(entries(true)) do
                local resolved = EDITOR.document:Resolve(entry.node.id) or entry.node
                local definition = MAP.Types[resolved.type] or {}
                if managedDefinition(definition, resolved.type) then
                    local shown = nodeLabel(entry.node.id, entry.node)
                    if (shown .. ' ' .. entry.node.id .. ' ' .. tostring(resolved.type)):lower():find(query, 1, true) then
                        local row = list:AddLine(shown, entry.node.id, resolved.type, entry.path); row.ComponentID = entry.node.id
                    end
                end
            end
            THEME.ApplyEditor(frame)
        end
        EDITOR.RefreshManaged = rebuild
        search.OnChange = rebuild
        list.OnRowSelected = function(_, _, row)
            selected = row.ComponentID
            EDITOR.selection, EDITOR.selectedLink = {[selected] = true}, nil
            EDITOR.RefreshInspector(); MAP.InspectionRequest(3, {selected})
        end
        remove.DoClick = function()
            if not selected then report('Select a binding or instrument first.'); return end
            local removing = selected
            Derma_Query('Delete ' .. nodeLabel(removing) .. ' (' .. removing .. ')?', 'Delete managed component', 'Delete', function()
                changed(EDITOR.document:Remove({[removing] = true})); selected = nil
            end, 'Cancel')
        end
        add.DoClick = function()
            local types = {}
            for id, definition in pairs(MAP.Types) do
                if managedDefinition(definition, id) then types[id] = definition end
            end
            choose('Binding and instrument catalog', types, function(typeId, definition) addTypeAt(typeId, definition, 0, 0); rebuild() end)
        end
        rebuild(); showWorkspace('bindings')
    end
    local function nodeMenu(entry)
        local menu = DermaMenu()
        if entry.node.generatedBy then
            local info = menu:AddOption('Generated by ' .. entry.node.generatedBy); info:SetEnabled(false)
        else
            menu:AddOption('Duplicate', function() changed(EDITOR.document:Duplicate(EDITOR.selection, EDITOR.pack)) end)
            menu:AddOption('Remove', function() changed(EDITOR.document:Remove(EDITOR.selection)) end)
            menu:AddOption('Create preset', function() createPreset(entry.node.id) end)
        end
        local definition = MAP.Types[(EDITOR.document:Resolve(entry.node.id) or {}).type]
        local connections = menu:AddSubMenu('Start connection')
        local categories = {}
        for name, descriptor in pairs(definition and definition.ports or {}) do
            local category = portCategory(descriptor); categories[category] = categories[category] or {}; categories[category][name] = descriptor
        end
        for _, category in ipairs({'fluid', 'electrical', 'references'}) do if categories[category] then
            local submenu = connections:AddSubMenu(category:gsub('^%l', string.upper))
            for _, name in ipairs(keys(categories[category])) do submenu:AddOption(name, function() beginConnection(entry.node.id, name) end) end
        end end
        menu:Open()
    end
    local function canvasMenu(x, y)
        local menu = DermaMenu()
        menu:AddOption('Add component here', function() addAt((x - panX) / zoom, (y - panY) / zoom) end)
        menu:AddOption('Add from preset here', function() addPresetAt((x - panX) / zoom, (y - panY) / zoom) end)
        if next(EDITOR.selection) then
            menu:AddOption('Duplicate selection', function() changed(EDITOR.document:Duplicate(EDITOR.selection, EDITOR.pack)) end)
            menu:AddOption('Remove selection', function() changed(EDITOR.document:Remove(EDITOR.selection)) end)
        end
        menu:Open()
    end
    canvas.Paint = function(_, width, height)
        surface.SetDrawColor(background); surface.DrawRect(0, 0, width, height)
        local model = graph()
        for _, item in ipairs(model.links) do if visible(item.category) then
            line(item.points, highlightedLink(item) and Color(245, 245, 245) or linkColors[item.category], highlightedLink(item), item.arrow)
            if item.fromPort and item.fromPort.direction == 'both' and item.toPort and item.toPort.direction == 'both' then
                local reverse = {}; for index = #item.points, 1, -1 do reverse[#reverse + 1] = {x = item.points[index].x, y = item.points[index].y + 5 / zoom} end
                line(reverse, highlightedLink(item) and Color(245, 245, 245) or linkColors[item.category], false, item.reverseArrow)
            end
            if selectedLink(item) then
                local x, y = screen(item.anchor); surface.SetDrawColor(230, 230, 230); surface.DrawRect(x - 5, y - 5, 10, 10)
            end
        end end
        local compatible = {}
        if EDITOR.connecting then for id in pairs(model.byId) do if #keys(destinationPorts(EDITOR.connecting.component, EDITOR.connecting.port, id)) > 0 then compatible[id] = true end end end
        for _, entry in ipairs(model.entries) do
            local node, at = entry.node, model.positions[entry.node.id]
            surface.SetDrawColor(EDITOR.selection[node.id] and Color(85, 105, 115) or Color(62, 62, 62)); surface.DrawRect(at.sx, at.sy, NODE_W * zoom, NODE_H * zoom)
            local definition = MAP.Types[(EDITOR.document:Resolve(node.id) or {}).type] or {}
            surface.SetDrawColor(compatible[node.id] and Color(90, 235, 120) or nodeColors[definition.package] or Color(150, 150, 150))
            surface.DrawOutlinedRect(at.sx, at.sy, NODE_W * zoom, NODE_H * zoom, compatible[node.id] and 3 or 2)
            draw.SimpleText(nodeLabel(node.id, node), 'DermaDefaultBold', at.sx + 5, at.sy + 5, foreground)
            draw.SimpleText(node.id, 'DermaDefault', at.sx + 5, at.sy + 23, foreground)
            draw.SimpleText((node.type or ('preset: ' .. tostring(node.preset))) .. '  ' .. entry.path, 'DermaDefault', at.sx + 5, at.sy + 42, Color(180, 180, 180))
        end
        local mx, my = canvas:LocalCursorPos(); local hovered = nodeAt(mx, my, model)
        if hovered then
            local resolved = EDITOR.document:Resolve(hovered.node.id); local definition = resolved and MAP.Types[resolved.type] or {}
            local ports = keys(definition.ports); local lines = {nodeLabel(hovered.node.id, hovered.node),
                hovered.node.id, resolved and resolved.type or 'invalid', hovered.path, hovered.node.generatedBy and ('generated by ' .. hovered.node.generatedBy) or '',
                #ports > 0 and ('ports: ' .. table.concat(ports, ', ')) or 'no typed ports'}
            local bx, by = math.max(mx - 300, 4), math.min(my + 18, height - 112)
            surface.SetDrawColor(28, 28, 28, 245); surface.DrawRect(bx, by, 290, 104)
            for index, value in ipairs(lines) do if value ~= '' then draw.SimpleText(value, 'DermaDefault', bx + 7, by + index * 16 - 12, foreground) end end
        end
    end
    canvas.OnMouseWheeled = function(panel, delta)
        local x, y = panel:LocalCursorPos(); local previous = zoom; zoom = math.Clamp(zoom * (delta > 0 and 1.15 or 1 / 1.15), 0.2, 3)
        panX, panY = x - (x - panX) / previous * zoom, y - (y - panY) / previous * zoom; return true
    end
    canvas.OnMousePressed = function(panel, code)
        local x, y = panel:LocalCursorPos(); local model = graph()
        if code == MOUSE_RIGHT then drag = {kind = 'right', x = x, y = y, panX = panX, panY = panY}; panel:MouseCapture(true); return end
        if code ~= MOUSE_LEFT then return end
        local hit = hitAt(x, y, model)
        local selected = hit and hit.kind == 'link' and hit.item
        if selected then
            EDITOR.selectedLink = {key = selected.key, path = selected.path, index = selected.index,
                referenceKey = selected.referenceKey, value = selected.value}
            EDITOR.selection = {}
            drag = {kind = 'bend', x = x, y = y, item = selected, anchor = MAP.Copy(selected.anchor), dx = 0, dy = 0}
            panel:MouseCapture(true); EDITOR.RefreshInspector(); MAP.InspectionRequest(3, {}); return
        end
        local entry = hit and hit.kind == 'node' and hit.entry
        if entry then
            if EDITOR.connecting then connectTo(entry.node.id); return end
            EDITOR.selectedLink = nil
            if not input.IsKeyDown(KEY_LCONTROL) then EDITOR.selection = {} end
            EDITOR.selection[entry.node.id] = true
            local origins = {}; for _, selected in ipairs(model.entries) do if EDITOR.selection[selected.node.id] then
                local at = model.positions[selected.node.id]; origins[selected.node.id] = {x = at.x, y = at.y}
            end end
            drag = {kind = 'nodes', x = x, y = y, dx = 0, dy = 0, origins = origins}; panel:MouseCapture(true)
            EDITOR.RefreshInspector(); MAP.InspectionRequest(3, keys(EDITOR.selection)); return
        end
        if EDITOR.connecting then EDITOR.connecting = nil; report('Connection cancelled.'); return end
        EDITOR.selection, EDITOR.selectedLink = {}, nil; EDITOR.RefreshInspector(); MAP.InspectionRequest(3, {})
    end
    canvas.OnMouseReleased = function(panel, code)
        if not drag then return end
        local x, y = panel:LocalCursorPos(); local movement = drag
        if movement.kind == 'right' then
            if math.abs(x - movement.x) < 4 and math.abs(y - movement.y) < 4 then
                local entry = nodeAt(x, y, graph()); if entry then
                    EDITOR.selectedLink = nil
                    if not EDITOR.selection[entry.node.id] then EDITOR.selection = {[entry.node.id] = true}; EDITOR.RefreshInspector() end
                    nodeMenu(entry)
                else canvasMenu(x, y) end
            end
        elseif movement.kind == 'nodes' and movement.dx * movement.dx + movement.dy * movement.dy >= 9 then
            edit(function(document)
                local shiftX, shiftY = movement.dx / zoom, movement.dy / zoom
                for _, pack in pairs(document.packs) do for _, link in ipairs(pack.links or {}) do
                    local bends = link.editor and link.editor.bends
                    local count = (movement.origins[link.from.component] and 1 or 0) + (movement.origins[link.to.component] and 1 or 0)
                    if bends and bends[1] and count > 0 then
                        bends[1].x = math.Round((bends[1].x + shiftX * count / 2) / 16) * 16
                        bends[1].y = math.Round((bends[1].y + shiftY * count / 2) / 16) * 16
                    end
                end end
                local referenceBends = (document.manifest.editor or {}).referenceBends or {}
                for key, bend in pairs(referenceBends) do
                    local owner, target = key:match('^([^>]+)>([^>]+)$')
                    local count = (movement.origins[owner] and 1 or 0) + (movement.origins[target] and 1 or 0)
                    if count > 0 then
                        bend.x = math.Round((bend.x + shiftX * count / 2) / 16) * 16
                        bend.y = math.Round((bend.y + shiftY * count / 2) / 16) * 16
                    end
                end
                for id, origin in pairs(movement.origins) do
                    local x = math.Round((origin.x + shiftX) / 16) * 16
                    local y = math.Round((origin.y + shiftY) / 16) * 16
                    local node = document:Find(id)
                    if node then node.editor = node.editor or {}; node.editor.x, node.editor.y = x, y
                    else
                        document.manifest.editor = document.manifest.editor or MAP.Object()
                        document.manifest.editor.generatedPositions = document.manifest.editor.generatedPositions or MAP.Object()
                        document.manifest.editor.generatedPositions[id] = {x = x, y = y}
                    end
                end
                return true
            end)
        elseif movement.kind == 'bend' and movement.dx * movement.dx + movement.dy * movement.dy >= 9 then
            edit(function(document)
                local point = {
                    x = math.Round((movement.anchor.x + movement.dx / zoom) / 16) * 16,
                    y = math.Round((movement.anchor.y + movement.dy / zoom) / 16) * 16}
                if movement.item.path then
                    local link = document.packs[movement.item.path].links[movement.item.index]
                    link.editor = link.editor or {}; link.editor.bends = MAP.Array({point})
                else
                    document.manifest.editor = document.manifest.editor or MAP.Object()
                    document.manifest.editor.referenceBends = document.manifest.editor.referenceBends or MAP.Object()
                    document.manifest.editor.referenceBends[movement.item.referenceKey] = point
                end
                return true
            end)
        end
        drag = nil; panel:MouseCapture(false)
    end
    canvas.Think = function(panel)
        if not drag then return end
        local x, y = panel:LocalCursorPos(); drag.dx, drag.dy = x - drag.x, y - drag.y
        if drag.kind == 'right' and drag.dx * drag.dx + drag.dy * drag.dy >= 16 then panX, panY = drag.panX + drag.dx, drag.panY + drag.dy end
    end
    tool('Sources', 90, sourceManager)
    tool('Manifest', 90, manifestEditor)
    EDITOR.BindingsButton = tool('Bindings', 90, managedComponents)
    EDITOR.BindingsButton:SetTooltip('Toggle the graph viewport to the in-window bindings, instruments and integrations table.')
    tool('Find', 70, function()
        local items = {}; for _, entry in ipairs(entries()) do items[entry.node.id] = entry.node end
        choose('Components', items, function(id)
            EDITOR.selection = {[id] = true}; EDITOR.RefreshInspector(); MAP.InspectionRequest(3, {id})
            local model = graph(); local at = model.positions[id]
            if at then showWorkspace('graph'); panX, panY = 30 - at.x * zoom, 30 - at.y * zoom else
                if not IsValid(EDITOR.ManagedPanel) then managedComponents() else showWorkspace('bindings') end
            end
        end)
    end)
    tool('Undo', 65, function() changed(EDITOR.document:History(false)) end)
    tool('Redo', 65, function() changed(EDITOR.document:History(true)) end)
    tool('Validate', 75, function() changed(true) end)
    tool('Diagnostics', 90, function()
        local items = {}; for index, diagnostic in ipairs(EDITOR.diagnostics or {}) do items[tostring(index)] = {label = diagnostic.path .. ': ' .. diagnostic.message, diagnostic = diagnostic} end
        choose('Compiler diagnostics', items, function(_, item) report(item.label) end)
    end)
    local modes = toolbar:Add('DComboBox'); modes:Dock(LEFT); modes:SetWide(115); modes:SetValue('All links')
    for _, item in ipairs({{'All links', 'all'}, {'Fluid / thermal', 'fluid'}, {'Electrical', 'electrical'}, {'References', 'references'}}) do modes:AddChoice(item[1], item[2]) end
    modes.OnSelect = function(_, _, _, value) EDITOR.viewMode = value end
    local hint = toolbar:Add('DLabel'); hint:Dock(FILL); hint:SetText('  Right click: actions  |  Right drag: pan  |  Wheel: zoom'); hint:SetTextColor(foreground)
    local frameThink = frame.Think
    frame.Think = function(self)
        if frameThink then frameThink(self) end
        if input.IsMouseDown(MOUSE_LEFT) then return end
        local hovered, underCursor = vgui.GetHoveredPanel(), {}
        while IsValid(hovered) do if hovered:GetClassName() == 'DMenu' or hovered:IsModal() then return end; underCursor[hovered] = true; hovered = hovered:GetParent() end
        local candidate
        for index = #EDITOR.children, 1, -1 do local child = EDITOR.children[index]
            if IsValid(child) and child:IsVisible() then local x, y = child:LocalCursorPos()
                if x >= 0 and y >= 0 and x < child:GetWide() and y < child:GetTall() then candidate = candidate or child; if underCursor[child] then candidate = child; break end end
            end
        end
        if candidate and not candidate:IsActive() then candidate:MoveToFront(); candidate:RequestFocus() end
    end
    local nativeClose = frame.Close
    frame.Close = function(self)
        if not self.CloseApproved and EDITOR.document and EDITOR.document.revision ~= (EDITOR.savedRevision or 0) then
            Derma_Query('Discard unsaved plant draft changes?', 'Plant editor', 'Discard', function() self.CloseApproved = true; self:Close() end, 'Keep editing'); return
        end
        nativeClose(self)
    end
    frame.OnRemove = function()
        for _, child in ipairs(EDITOR.children) do if IsValid(child) then child:Remove() end end
        EDITOR.children, EDITOR.selection, EDITOR.pending, EDITOR.connecting, EDITOR.selectedLink, EDITOR.Graph, EDITOR.Toolbar, EDITOR.Splitter = {}, {}, nil, nil, nil, nil, nil, nil
        EDITOR.ManagedPanel, EDITOR.RefreshManaged, EDITOR.hitCycle, EDITOR.Workspace, EDITOR.BindingsButton = nil, nil, nil, nil, nil
        EDITOR.document, EDITOR.compiled, EDITOR.RefreshState, EDITOR.savedRevision = nil, nil, nil, nil
        MAP.CloseInspection()
    end
    newDocument(); THEME.ApplyEditor(frame); MAP.InspectionRequest(1)
end

hook.Add('LUASQUARE_MAP_Catalog', 'LUASQUARE_MAP_EditorCatalog', function()
    if EDITOR.document and EDITOR.document.manifest.id == 'new_map' and EDITOR.document.revision == 0 then EDITOR.document.manifest.packages = keys(MAP.Packages) end
    if EDITOR.document then changed(true) end
    if EDITOR.SourceManagerRefresh then EDITOR.SourceManagerRefresh() end
end)
hook.Add('LUASQUARE_MAP_Source', 'LUASQUARE_MAP_EditorSource', function(value)
    if value.error then report(value.error); EDITOR.pending = nil; return end
    if type(value.sourceText) ~= 'string' then report('Packed source transfer is missing canonical source text'); EDITOR.pending = nil; return end
    local source, sourceError = MAP.DecodeJSON(value.sourceText, MAP.Limits.bytes)
    if not source then report(sourceError or 'Packed source transfer is invalid'); EDITOR.pending = nil; return end
    value.source = source
    if value.family == 'components' and value.path == EDITOR.attachPath then
        EDITOR.attachPath = nil
        edit(function(document)
            if document.packs[value.path] then return false, 'Pack is already included' end
            document.packs[value.path] = MAP.Copy(value.source)
            document.manifest.packs[#document.manifest.packs + 1] = value.path
            EDITOR.pack = value.path; return true
        end)
        return
    end
    if value.family == 'map' then EDITOR.pending = {manifest = value.source, packs = {}, path = value.path, index = 1}
    elseif EDITOR.pending and value.family == 'components' then
        EDITOR.pending.packs[value.path] = value.source; EDITOR.pending.index = EDITOR.pending.index + 1
    else return end
    local pending = EDITOR.pending
    local path = pending.manifest.packs[pending.index]
    if path then timer.Simple(0.15, function() if IsValid(EDITOR.Frame) and EDITOR.pending == pending then MAP.InspectionRequest(2, 'components', path) end end)
    else
        EDITOR.path, EDITOR.pack = pending.path, pending.manifest.packs[1]
        EDITOR.document = MAP.NewDocument(pending.manifest, pending.packs); EDITOR.pending, EDITOR.selection = nil, {}; changed(true)
        EDITOR.savedRevision = 0
    end
end)
hook.Add('LUASQUARE_MAP_TransferError', 'LUASQUARE_MAP_EditorTransferError', function(message)
    if not EDITOR.pending then return end
    EDITOR.pending = nil
    report('Packed source transfer failed: ' .. tostring(message))
end)
concommand.Add('luasquare_map_editor', EDITOR.Open)
hook.Add('LUASQUARE_MAP_State', 'LUASQUARE_MAP_EditorState', function()
    if EDITOR.RefreshState then EDITOR.RefreshState() end
end)
