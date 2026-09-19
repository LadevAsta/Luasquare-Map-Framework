-- Focused native-layout/theme regression checks; no map or gameplay operations.
CLIENT = true
unpack = unpack or table.unpack
Color = function(r, g, b) return {r = r, g = g, b = b} end
math.Round = math.Round or function(value) return math.floor(value + 0.5) end
IsValid = function(value) return type(value) == 'table' end
ScrW, ScrH = function() return 1920 end, function() return 1080 end
surface = {SetDrawColor = function() end, DrawRect = function() end, DrawOutlinedRect = function() end, DrawLine = function() end}
draw = {RoundedBox = function() end, RoundedBoxEx = function() end, SimpleText = function() end}
local activeWindow, hoveredPanel, mouseX, mouseY, mouseHeld = nil, nil, 0, 0, false
MOUSE_LEFT = 107
MOUSE_RIGHT = 108
KEY_LCONTROL = 109
input = {IsMouseDown = function() return mouseHeld end, IsKeyDown = function() return false end}
gui = {MouseX = function() return mouseX end}
local lastMenu
DermaMenu = function()
    local menu = {options = {}, submenus = {}}
    function menu:AddOption(text, callback) self.options[text] = callback; return panel and panel('DMenuOption') end
    function menu:AddSubMenu(text)
        local child = DermaMenu(); self.submenus[text] = child
        return child, panel and panel('DMenuOption')
    end
    function menu:Open() lastMenu = self end
    return menu
end
local function panel(class)
    local value = {class = class, children = {}, w = 800, h = 600}
    function value:GetClassName() return self.class end
    function value:GetChildren() return self.children end
    function value:GetParent() return self.parent end
    function value:IsModal() return false end
    function value:IsVisible() return self.visible ~= false end
    function value:IsActive() return activeWindow == self end
    function value:LocalCursorPos() return mouseX - (self.x or 0), mouseY - (self.y or 0) end
    function value:MoveToFront() self.frontCount = (self.frontCount or 0) + 1 end
    function value:RequestFocus() activeWindow = self end
    function value:Think()
        self.nativeTicks = (self.nativeTicks or 0) + 1
        if self.Dragging then self:SetPos(mouseX - self.Dragging[1], mouseY - self.Dragging[2]) end
        if self.Sizing then self:SetSize(mouseX - self.Sizing[1], mouseY - self.Sizing[2]) end
    end
    function value:SetTextColor(color) self.textColor = color end
    function value:SetTextStyleColor(color) self.styleColor = color end
    function value:SetText(text) self.text = text end
    function value:GetText() return self.text or '' end
    function value:GetValue() return self.text or '' end
    function value:SetValue(text) self.text = text end
    function value:SetEnabled(enabled) self.enabled = enabled end
    function value:SetTooltip(text) self.tooltip = text end
    function value:SetTitle(text) self.title = text end
    function value:SetSize(w, h) self.w, self.h = w, h end
    function value:SetWide(w) self.w = w end
    function value:SetTall(h) self.h = h end
    function value:Dock() end
    function value:DockMargin() end
    function value:SetMouseInputEnabled() end
    function value:SetVisible(enabled) self.visible = enabled end
    function value:SetCursor() end
    function value:MouseCapture(enabled) self.captured = enabled end
    function value:SetWrap(enabled) self.wrap = enabled end
    function value:SetAutoStretchVertical(enabled) self.autoStretch = enabled end
    function value:SetContentAlignment(alignment) self.alignment = alignment end
    function value:SetTextInset() end
    function value:InvalidateLayout() self.layoutInvalidated = true end
    function value:SetEditable(enabled) self.editable = enabled end
    function value:SetMultiline() end
    function value:SetPlaceholderText(text) self.placeholder = text end
    function value:SetHighlightColor() end
    function value:SetCursorColor() end
    function value:SetSortItems() end
    function value:SetMultiSelect(enabled) self.multiSelect = enabled end
    function value:SetPath(path) self.path = path end
    function value:SetBaseFolder(path) self.baseFolder = path end
    function value:SetFileTypes(types) self.fileTypes = types end
    function value:SetOpen(enabled) self.open = enabled end
    function value:AddSheet(name, contents) self.sheets = self.sheets or {}; self.sheets[name] = contents end
    function value:AddChoice(text, data)
        self.choices = self.choices or {}
        self.choices[#self.choices + 1] = {text = text, data = data}
    end
    function value:Clear() self.children = {} end
    function value:GetCanvas()
        if not self.canvas then self.canvas = self:Add('Panel') end
        return self.canvas
    end
    function value:AddColumn() return self:Add('DButton') end
    function value:SetFixedWidth() end
    function value:AddLine(...) local line = self:Add('DListView_Line'); line.values = {...}; return line end
    function value:GetLines() return self.children end
    function value:SelectItem(row) row.selected = true end
    function value:Close() if self.OnRemove then self:OnRemove() end end
    function value:Remove() if self.OnRemove then self:OnRemove() end self.removed = true end
    function value:GetWide() return self.w end
    function value:GetTall() return self.h end
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:GetPos() return self.x or 0, self.y or 0 end
    function value:SetSizable(enabled) self.sizable = enabled end
    function value:SetDraggable(enabled) self.draggable = enabled end
    function value:SetMinWidth(w) self.minWidth = w end
    function value:SetMinHeight(h) self.minHeight = h end
    function value:SetMinMax(minimum, maximum) self.minimum, self.maximum = minimum, maximum end
    function value:SetDecimals(decimals) self.decimals = decimals end
    function value:SetInterval(interval) self.interval = interval end
    function value:Setup(kind, settings) self.setupKind, self.setupSettings = kind, settings end
    function value:CreateRow(category, name)
        local row = self:Add('DProperty_Generic'); row.category, row.name = category, name
        return row
    end
    function value:MakePopup() end
    function value:Center() if self.PerformLayout then self:PerformLayout(self.w, self.h) end end
    function value:IsHovered() return false end
    function value:IsLineSelected() return self.selected end
    function value:PerformLayout(w, h)
        assert(type(w) == 'number' and type(h) == 'number', 'native DFrame dimensions lost')
        self.nativeWidth, self.nativeHeight = w, h
    end
    function value:Add(kind)
        local child = panel(kind)
        child.parent = self
        table.insert(self.children, child)
        return child
    end
    if class == 'DFrame' then
        for _, name in ipairs({'btnClose', 'btnMaxim', 'btnMinim'}) do
            value[name] = value:Add('DButton')
            value[name].Paint = function() return name end
        end
    end
    return value
end
vgui = {Create = function(class, parent)
    local value = panel(class)
    if parent then value.parent = parent; table.insert(parent.children, value) end
    return value
end, GetHoveredPanel = function() return hoveredPanel end}
LUASQUARE_EDITOR_THEME = nil
dofile('lua/luasquare_module/editor_theme.lua')
local diagnostics = LUASQUARE_EDITOR_THEME.CreateTextArea(panel('DPanel'))
diagnostics:SetText(string.rep('Long diagnostic\n', 100))
assert(diagnostics.class == 'DScrollPanel' and diagnostics.TextLabel.wrap and diagnostics.TextLabel.autoStretch,
    'diagnostics must wrap and grow inside a scrollable viewport')
assert(diagnostics:GetText() == string.rep('Long diagnostic\n', 100) and diagnostics.layoutInvalidated,
    'diagnostics must retain all text and refresh scroll layout')
dofile('lua/luasquare_module/control/editor.lua')
local makeWindow
for index = 1, 20 do
    local name, value = debug.getupvalue(LUASQUARE_CONTROL.Editor.Open, index)
    if not name then break end
    if name == 'window' then makeWindow = value; break end
end
assert(makeWindow, 'editor window helper missing')
local frame = makeWindow('Regression', 800, 600)
local expand = frame.btnMaxim
assert(#frame.children == 3 and expand.enabled, 'extra title-bar button or disabled native maximize')
assert(expand:Paint() == 'btnMaxim' and frame.btnClose:Paint() == 'btnClose', 'native icons replaced by theme')
assert(frame.sizable and frame.draggable, 'native resizing/dragging disabled')
frame:PerformLayout(900, 700)
assert(frame.nativeWidth == 900 and frame.nativeHeight == 700)
frame:Center()
assert(frame.nativeWidth == 800 and frame.nativeHeight == 600)
frame:SetPos(140, 90)
expand.DoClick()
assert(frame.w == 1920 and frame.h == 1080)
frame:PerformLayout(frame.w, frame.h)
expand.DoClick()
assert(frame.w == 800 and frame.h == 600 and frame.x == 140 and frame.y == 90)
local theme = LUASQUARE_EDITOR_THEME
local root = panel('Panel')
local header = root:Add('DButton')
local row = root:Add('DListView_Line')
local text = row:Add('DListViewLabel')
local bar = root:Add('DVScrollBar')
local grip = bar:Add('DScrollBarGrip')
theme.ApplyTree(root)
assert(header.textColor == theme.Colors.text and type(header.Paint) == 'function')
assert(text.textColor == theme.Colors.text)
text:UpdateColours({})
assert(text.styleColor == theme.Colors.text, 'Derma scheme can replace white list text')
row:Paint(100, 20)
row.selected = true
row:Paint(100, 20)
assert(type(bar.Paint) == 'function' and type(grip.Paint) == 'function')
bar:Paint(15, 100)
grip:Paint(15, 40)
local menu = panel('DMenu')
local option = menu:Add('DMenuOption')
theme.ApplyTree(menu)
option:UpdateColours({})
assert(type(menu.Paint) == 'function' and option.styleColor == theme.Colors.text, 'dropdown menu loses dark/white styling')
timer = {Simple = function(_, callback) callback() end}
local control = LUASQUARE_CONTROL
control.Editor.Frame = nil
control.EditorCommand = function() end
control.Client = {controls = {}, history = {}, catalog = {Actions = {}, Predicates = {}, entities = {
    {target = 'CTRLI_pumps_fixture', class = 'func_rot_button', id = 'pumps_fixture'}
}}}
control.Editor.Open()
local editor = control.Editor.Frame
editor.Source.controls = {{id = 'fixture', kind = 'toggle'}}
editor.Selected = 1
editor:Rebuild()
local function find(root, class, text)
    for _, child in ipairs(root.children) do
        if child.class == class and (not text or child.text == text) then return child end
        local found = find(child, class, text)
        if found then return found end
    end
end
local dropdown = assert(find(editor.Inspector, 'DComboBox', 'Use physical position / default'))
dropdown:OnSelect(2, 'In', dropdown.choices[2].data)
assert(editor.Source.controls[1].initialPosition == 'in', 'position dropdown does not store typed In value')
local choosePhysical = assert(find(editor.Inspector, 'DButton', 'Choose physical CTRLI_ button: (virtual)'))
choosePhysical.DoClick()
local discovered = assert(find(editor.DiscoveryWindow, 'DListView_Line'))
assert(discovered.values[1] == 'pumps' and discovered.AssetId == 'CTRLI_pumps_fixture',
    'physical category must group the first suffix segment without changing target identity')
discovered.parent.OnRowSelected(discovered.parent, 1, discovered)
assert(editor.Source.controls[1].target == 'CTRLI_pumps_fixture' and editor.Source.controls[1].class == 'func_rot_button',
    'physical chooser must fill target and actual entity class')
local kind = assert(find(editor.Inspector, 'DComboBox', 'Toggle'))
kind:OnSelect(1, 'Press', kind.choices[1].data)
assert(editor.Source.controls[1].kind == 'momentary' and editor.List.children[1].values[1] == 'press',
    'Press label must preserve compatible packed kind')
control.Client.catalog.Actions.fixture = {parameters = {enabled = {type = 'boolean'},
    mode = {type = 'string', choices = {open = true, closed = true}}, digit = {type = 'integer', min = 0, max = 9}}}
editor.Source.controls[1].actions = {press = {id = 'fixture', params = {enabled = true, mode = 'open', digit = 0}}}
editor:Rebuild()
local boolean = assert(find(editor.Inspector, 'DComboBox', 'Yes'))
boolean:OnSelect(2, 'No', boolean.choices[2].data)
assert(editor.Source.controls[1].actions.press.params.enabled == false, 'boolean dropdown loses false value')
assert(find(editor.Inspector, 'DComboBox', 'open') and find(editor.Inspector, 'DComboBox', '0'), 'registered choices/digits remain freeform')
editor.ReadOnly = true
editor:Rebuild()
assert(find(editor.Inspector, 'DComboBox', 'Press').enabled == false, 'packed inspector dropdown must stay read-only')
editor.ReadOnly = false
editor:Rebuild()
kind = assert(find(editor.Inspector, 'DComboBox', 'Press'))
kind:OnSelect(3, 'Keypad', kind.choices[3].data)
local limit = assert(find(editor.Inspector, 'DComboBox', '4'))
assert(#limit.choices == 9, 'maximum digits should offer 1 through 9')
limit:OnSelect(9, '9', limit.choices[9].data)
local clear = assert(find(editor.Inspector, 'DComboBox', 'Yes'))
clear:OnSelect(2, 'No', clear.choices[2].data)
assert(editor.Source.controls[1].maxDigits == 9 and editor.Source.controls[1].clearOnSubmit == false,
    'keypad dropdowns must preserve integer and false values')
control.Client.catalog.keypadEntities = {}
for _, token in ipairs(control.KeypadKeyTokens) do
    if token ~= 'b' and token ~= 'c' then
        table.insert(control.Client.catalog.keypadEntities, {target = 'CTRLI_KPD_' .. token .. '_fixture',
            key = token, keypad = 'fixture', class = 'func_button'})
    end
end
editor:Rebuild()
local chooseKeypad = assert(find(editor.Inspector, 'DButton', 'Choose discovered keypad / fill all keys'))
chooseKeypad.DoClick()
local group = assert(find(editor.DiscoveryWindow, 'DListView_Line'))
assert(group.AssetId == 'fixture' and group.values[1] == 'Keypad')
group.parent.OnRowSelected(group.parent, 1, group)
assert(#editor.Source.controls == 1 and editor.Source.controls[1].keys.s == 'CTRLI_KPD_s_fixture'
    and editor.Source.controls[1].keys['9'] == 'CTRLI_KPD_9_fixture', 'group chooser must fill required keys without authored child members')
local chooseDigit = assert(find(editor.Inspector, 'DButton', 'Choose Digit 0 (required): CTRLI_KPD_0_fixture'))
chooseDigit.DoClick()
local slot = assert(find(editor.DiscoveryWindow, 'DListView_Line'))
assert(#slot.parent.children == 1 and slot.AssetId == 'CTRLI_KPD_0_fixture', 'digit slot browser must only discover the matching KPD token')
slot.parent.OnRowSelected(slot.parent, 1, slot)
local override = assert(find(editor.Inspector, 'DTextEntry', 'CTRLI_KPD_0_fixture'))
override:SetText('CTRLI_manual_digit'); override.OnEnter()
assert(editor.Source.controls[1].keys['0'] == 'CTRLI_manual_digit', 'keypad slot must retain manual text override authoring')
mouseX, mouseY, mouseHeld = 230, 160, true
editor.Dragging = {30, 20}
editor:Think()
assert(editor.x == 200 and editor.y == 140 and editor.nativeTicks == 1, 'status updater must preserve native drag Think')
editor.Dragging = nil; editor.Sizing = {10, 15}
editor:Think()
assert(editor.w == 220 and editor.h == 145, 'status updater must preserve native resize Think')
editor.Sizing = nil
local child = makeWindow('Hover focus', 300, 250)
child:SetPos(300, 300)
editor.ChildWindows[#editor.ChildWindows + 1] = child
activeWindow, hoveredPanel, mouseX, mouseY, mouseHeld = editor, editor, 310, 310, false
editor:Think()
assert(activeWindow == child and child.frontCount == 1, 'occluded subwindow must focus when cursor enters its bounds')
editor:Think()
assert(child.frontCount == 1, 'active subwindow should retain its existing focused control')
activeWindow, mouseHeld = editor, true
editor:Think()
assert(activeWindow == editor, 'hover focus must not interrupt captured dragging/resizing')
mouseHeld, hoveredPanel = false, menu
editor:Think()
assert(activeWindow == editor, 'hover focus must not occlude open dropdown menus')
print('Control editor native layout/fullscreen and recursive theme regression checks passed.')
editor.ReadOnly = false
editor.Source.controls = {{id = 'fixture', kind = 'momentary', cooldown = 0.25,
    actions = {press = {id = 'fixture', params = {}}}}}
editor.Selected = 1; editor:Rebuild()
local wang = assert(find(editor.Inspector, 'DNumberWang'))
assert(wang.minimum == 0 and wang.maximum == 60 and wang.decimals == 2, 'cooldown spinner must match compiler limits')
math.Clamp = math.Clamp or function(value, minimum, maximum) return math.max(minimum, math.min(maximum, value)) end
wang:OnValueChanged(0.5)
assert(editor.Source.controls[1].cooldown == 0.5 and editor.Dirty, 'cooldown changes must be undoable and unsaved')
local outputs = assert(find(editor.Inspector, 'DListView'))
assert(outputs.children[3].ActionEvent == 'press', 'action list must expose the configured event')
local pendingDiscard
Derma_Query = function(_, _, _, callback) pendingDiscard = callback end
editor:Close()
assert(pendingDiscard and not editor.CloseApproved, 'dirty editor close must wait for explicit confirmation')
print('Control editor cooldown/output-list and unsaved-close checks passed.')

-- Reuse the native VGUI double to exercise the new plant window lifecycle.
LUASQUARE_MAP = {Schema = 'luasquare.map/v1', ComponentSchema = 'luasquare.components/v1', Types = {}, Packages = {},
    Limits = {packs = 128, nodes = 2048, links = 8192, values = 131072, depth = 24, string = 4096}, Client = {state = {}}}
for _, name in ipairs({'shared', 'json', 'compiler', 'document'}) do dofile('lua/luasquare_module/map/' .. name .. '.lua') end
local inspectionClosed = false
local inspectionRequests = {}
LUASQUARE_MAP.InspectionRequest = function(...) inspectionRequests[#inspectionRequests + 1] = {...} end
LUASQUARE_MAP.CloseInspection = function() inspectionClosed = true end
dofile('lua/luasquare_module/map/editor.lua')
LUASQUARE_MAP.Editor.Open()
local plant = LUASQUARE_MAP.Editor.Frame
assert(plant.sizable and plant.draggable and plant.btnMaxim.enabled)
plant.Dragging = {10, 15}; mouseX, mouseY = 230, 160; plant:Think()
assert(plant.x == 220 and plant.y == 145 and plant.nativeTicks == 1, 'plant editor preserves native drag Think')
plant.Dragging = nil; plant.Sizing = {10, 15}; plant:Think()
assert(plant.w == 220 and plant.h == 145, 'plant editor preserves native resize Think')
plant.Sizing = nil
plant.btnMaxim.DoClick(); assert(plant.w == 1920 and plant.h == 1080)
plant.btnMaxim.DoClick(); assert(plant.w == 220 and plant.h == 145)
assert(plant.btnMinim.enabled and LUASQUARE_MAP.Editor.Toolbar and LUASQUARE_MAP.Editor.Splitter,
    'plant editor exposes native minimize, top toolbar and resizable inspector splitter')
assert(find(LUASQUARE_MAP.Editor.Toolbar, 'DButton', 'Manifest'), 'manifest settings must sit beside Sources in the top toolbar')
assert(find(LUASQUARE_MAP.Editor.Toolbar, 'DButton', 'Bindings'), 'non-flow bindings and instruments require a dedicated manager')
LUASQUARE_MAP.Client.catalog = {sources = {map = {'experiment_rbmk/main.json'}, components = {}}}
find(LUASQUARE_MAP.Editor.Toolbar, 'DButton', 'Sources').DoClick()
local sourceManager = assert(LUASQUARE_MAP.Editor.SourceManager)
local draftBrowser = assert(find(sourceManager, 'DFileBrowser'))
assert(draftBrowser.path == 'DATA' and draftBrowser.baseFolder == 'luasquare/map/drafts',
    'source manager uses a local draft file browser instead of a typed load path')
local packedLoadButton = find(sourceManager, 'DButton', 'Load selected packed manifest')
local draftLoadButton = find(sourceManager, 'DButton', 'Load selected local draft')
assert(packedLoadButton and draftLoadButton and draftLoadButton.tooltip,
    'source manager provides explicit reliable load actions for packed sources and drafts')
local packedList = assert(find(sourceManager, 'DListView'))
local packedRow = assert(find(packedList, 'DListView_Line'))
packedList:OnRowSelected(1, packedRow); packedLoadButton.DoClick()
local packedRequest = inspectionRequests[#inspectionRequests]
assert(packedRequest[1] == 2 and packedRequest[2] == 'map' and packedRequest[3] == 'experiment_rbmk/main.json',
    'explicit packed-manifest load sends the selected catalog path')
LUASQUARE_MAP.RegisterType('test.node', {fields = {rate = {type = 'number', min = -20, max = 500, default = 1,
    description = 'Test flow rate.'}}, ports = {
    output = {kind = 'fluid', direction = 'out', unit = 'L'}, input = {kind = 'fluid', direction = 'in', unit = 'L'}
}, label = 'Test node'})
LUASQUARE_MAP.RegisterType('test.owner', {fields = {support = {type = 'id', optional = true}}, ports = {}, label = 'Generated owner',
    generation = {{field = 'support', type = 'test.node', defaults = {}}}})
local document = LUASQUARE_MAP.Editor.document
local pack = document.packs['new/plant.json']
pack.components[1] = {id = 'a', type = 'test.node', config = {}, editor = {x = 0, y = 0, label = 'A'}}
pack.components[2] = {id = 'b', type = 'test.node', config = {}, editor = {x = 320, y = 0, label = 'B'}}
pack.links[1] = {from = {component = 'a', port = 'output'}, to = {component = 'b', port = 'input'}}
LUASQUARE_MAP.Editor.compiled = assert(document:Compile())
local canvas = LUASQUARE_MAP.Editor.Canvas
mouseX, mouseY = 50, 50
canvas:OnMousePressed(MOUSE_LEFT); canvas:OnMouseReleased(MOUSE_LEFT)
assert(pack.components[1].editor.x == 0 and pack.components[1].editor.y == 0,
    'selection click must not shift a packed node onto the snap grid')
assert(find(LUASQUARE_MAP.Editor.Inspector, 'DTextEntry', 'A'), 'component label must be explicitly editable')
find(LUASQUARE_MAP.Editor.Inspector, 'DButton', 'Open component settings').DoClick()
local settingsWindow = LUASQUARE_MAP.Editor.children[#LUASQUARE_MAP.Editor.children]
local properties = assert(find(settingsWindow, 'DProperties'), 'component settings must use a dedicated typed property grid')
local rate = assert(find(properties, 'DProperty_Generic'))
assert(rate.setupSettings.min == -20 and rate.setupSettings.max == 500 and rate.tooltip:find('Test flow rate', 1, true),
    'numeric properties use schema ranges and expose field help')
rate:DataChanged(25)
assert(not (document.manifest.overrides and document.manifest.overrides.a), 'property changes remain staged before Apply')
find(settingsWindow, 'DButton', 'Apply changes').DoClick()
assert(document.manifest.overrides.a.rate == 25, 'Apply commits staged component settings once')
canvas:OnMousePressed(MOUSE_LEFT); mouseX, mouseY = 82, 82; canvas:Think(); canvas:Paint(900, 600)
assert(LUASQUARE_MAP.Editor.Graph.positions.a.x == 32 and LUASQUARE_MAP.Editor.Graph.positions.a.y == 32,
    'drag preview updates before release')
canvas:OnMouseReleased(MOUSE_LEFT)
assert(pack.components[1].editor.x == 32 and pack.components[1].editor.y == 32, 'node drag commits snapped editor coordinates')
canvas:Paint(900, 600)
local routed = LUASQUARE_MAP.Editor.Graph.links[1]
for index = 1, #routed.points - 1 do
    local p, q = routed.points[index], routed.points[index + 1]
    assert(p.x == q.x or p.y == q.y, 'automatic connection route must remain orthogonal')
end
local routeEnd, bPosition = routed.points[#routed.points], LUASQUARE_MAP.Editor.Graph.positions.b
assert(routeEnd.x == bPosition.x or routeEnd.x == bPosition.x + 190 or routeEnd.y == bPosition.y or routeEnd.y == bPosition.y + 70,
    'connection arrow endpoint must terminate on a destination node border')
assert((routeEnd.x == bPosition.x and routed.arrow.x == 1) or (routeEnd.x == bPosition.x + 190 and routed.arrow.x == -1)
    or (routeEnd.y == bPosition.y and routed.arrow.y == 1) or (routeEnd.y == bPosition.y + 70 and routed.arrow.y == -1),
    'connection arrow orientation follows the reached destination border')
local first, second = routed.points[1], routed.points[2]
mouseX, mouseY = (first.x + second.x) / 2 + 40, (first.y + second.y) / 2 + 40
canvas:OnMousePressed(MOUSE_LEFT)
assert(LUASQUARE_MAP.Editor.selectedLink and LUASQUARE_MAP.Editor.selectedLink.index == 1,
    'clicking an authored route selects and highlights that connection')
mouseX, mouseY = mouseX + 32, mouseY + 16; canvas:Think(); canvas:OnMouseReleased(MOUSE_LEFT)
assert(pack.links[1].editor and #pack.links[1].editor.bends == 1, 'route anchor persists as editor-only metadata')
local oldAnchorX = pack.links[1].editor.bends[1].x
canvas:Paint(900, 600)
local aPosition = LUASQUARE_MAP.Editor.Graph.positions.a
mouseX, mouseY = aPosition.sx + 30, aPosition.sy + 30
canvas:OnMousePressed(MOUSE_LEFT); mouseX = mouseX + 32; canvas:Think(); canvas:OnMouseReleased(MOUSE_LEFT)
assert(pack.links[1].editor.bends[1].x == oldAnchorX + 16,
    'moving one connected node carries the persisted route anchor by half the endpoint movement')
mouseX, mouseY = pack.components[1].editor.x + 45, pack.components[1].editor.y + 45
canvas:OnMousePressed(MOUSE_RIGHT); canvas:OnMouseReleased(MOUSE_RIGHT)
assert(lastMenu and lastMenu.options.Duplicate and lastMenu.options.Remove and lastMenu.submenus['Start connection'],
    'node right-click exposes authoring and typed connection actions')
pack.components[3] = {id = 'c', type = 'test.node', config = {}, editor = {x = 640, y = 0, label = 'C'}}
LUASQUARE_MAP.Editor.compiled = assert(document:Compile())
local fluidMenu = assert(lastMenu.submenus['Start connection'].submenus.Fluid)
fluidMenu.options.output()
assert(LUASQUARE_MAP.Editor.connecting and LUASQUARE_MAP.Editor.connecting.port == 'output',
    'typed connection action enters destination-selection mode')
mouseX, mouseY = 700, 70
canvas:OnMousePressed(MOUSE_LEFT)
assert(not LUASQUARE_MAP.Editor.connecting and #pack.links == 2 and pack.links[2].to.component == 'c',
    'highlighted compatible destination commits through the compiler')
canvas:Paint(900, 600); aPosition = LUASQUARE_MAP.Editor.Graph.positions.a
mouseX, mouseY = aPosition.sx + 30, aPosition.sy + 30
canvas:OnMousePressed(MOUSE_RIGHT); canvas:OnMouseReleased(MOUSE_RIGHT)
assert(lastMenu.submenus['Start connection'].submenus.Fluid.options.output)
lastMenu.submenus['Start connection'].submenus.Fluid.options.output()
mouseX, mouseY = 950, 600; canvas:OnMousePressed(MOUSE_LEFT)
assert(not LUASQUARE_MAP.Editor.connecting, 'empty-space click cancels connection mode')
mouseX, mouseY = 950, 600
canvas:OnMousePressed(MOUSE_RIGHT); canvas:OnMouseReleased(MOUSE_RIGHT)
assert(lastMenu.options['Add component here'] and lastMenu.options['Add from preset here'],
    'empty-space context menu exposes add-at-cursor component and preset actions')
local viewMode = assert(find(LUASQUARE_MAP.Editor.Toolbar, 'DComboBox'))
assert(#viewMode.choices == 4, 'link view offers All, Fluid, Electrical and References filters')
viewMode:OnSelect(1, 'Fluid / thermal', 'fluid')
assert(LUASQUARE_MAP.Editor.viewMode == 'fluid', 'link view selection updates graph filtering')
pack.components[4] = {id = 'owner', type = 'test.owner', config = {}, editor = {x = 0, y = 240, label = 'Owner'}}
LUASQUARE_MAP.Editor.compiled = assert(document:Compile())
canvas:Paint(900, 600)
local generated = assert(LUASQUARE_MAP.Editor.Graph.positions['owner.support'])
local reference
for _, item in ipairs(LUASQUARE_MAP.Editor.Graph.links) do if item.referenceKey == 'owner>owner.support' then reference = item; break end end
assert(reference, 'generated component reference line is present')
viewMode:OnSelect(1, 'All links', 'all')
local referenceStart = {x = reference.anchor.x, y = reference.anchor.y}
local rp, rq = reference.points[1], reference.points[2]
mouseX, mouseY = (rp.x + rq.x) / 2 + 40, (rp.y + rq.y) / 2 + 40
canvas:OnMousePressed(MOUSE_LEFT); mouseX = mouseX + 32; canvas:Think(); canvas:Paint(900, 600)
local previewReference
for _, item in ipairs(LUASQUARE_MAP.Editor.Graph.links) do if item.referenceKey == 'owner>owner.support' then previewReference = item; break end end
assert(previewReference and previewReference.anchor.x ~= referenceStart.x,
    'first drag of a configuration-reference route previews immediately')
canvas:OnMouseReleased(MOUSE_LEFT)
assert(document.manifest.editor.referenceBends['owner>owner.support'],
    'configuration-reference route anchors persist as manifest editor metadata')
mouseX, mouseY = generated.sx + 25, generated.sy + 25
canvas:OnMousePressed(MOUSE_LEFT); mouseX, mouseY = mouseX + 32, mouseY + 32; canvas:Think(); canvas:OnMouseReleased(MOUSE_LEFT)
assert(document.manifest.editor.generatedPositions['owner.support'],
    'generated support nodes have independently persisted editor positions')
LUASQUARE_MAP.RegisterPackage('source', {})
LUASQUARE_MAP.RegisterType('test.hidden_binding', {package = 'source', fields = {target = {type = 'id'}}, ports = {}, label = 'Hidden binding'})
document.manifest.packages[#document.manifest.packages + 1] = 'source'
pack.components[#pack.components + 1] = {id = 'hidden_binding', type = 'test.hidden_binding', config = {target = 'a'}, editor = {x = 640, y = 240}}
LUASQUARE_MAP.Editor.compiled = assert(document:Compile())
canvas:Paint(900, 600)
assert(not LUASQUARE_MAP.Editor.Graph.positions.hidden_binding,
    'binding management nodes stay out of the plant flow graph')
local bindingsButton = find(LUASQUARE_MAP.Editor.Toolbar, 'DButton', 'Bindings')
bindingsButton.DoClick()
assert(LUASQUARE_MAP.Editor.ManagedPanel.parent == LUASQUARE_MAP.Editor.Workspace and canvas.visible == false,
    'Bindings toggles the main graph viewport to an in-window management table')
local managedList = assert(find(LUASQUARE_MAP.Editor.ManagedPanel, 'DListView'))
for _, row in ipairs(managedList.children) do if row.ComponentID == 'hidden_binding' then managedList:OnRowSelected(1, row); break end end
assert(LUASQUARE_MAP.Editor.selection.hidden_binding, 'selecting a managed row directs the main inspector to that component')
bindingsButton.DoClick(); assert(canvas.visible == true, 'Graph toggle restores the plant canvas')
plant:SetSize(1000, 700)
mouseX = 100; LUASQUARE_MAP.Editor.Splitter:OnMousePressed(); mouseX = 75; LUASQUARE_MAP.Editor.Splitter:Think(); LUASQUARE_MAP.Editor.Splitter:OnMouseReleased()
assert(LUASQUARE_MAP.Editor.Inspector:GetWide() > 340, 'inspector splitter changes inspector width')
assert(LUASQUARE_MAP.Editor.document:Edit(function(document) document.manifest.id = 'changed'; return true end))
pendingDiscard = nil; plant:Close(); assert(pendingDiscard and not inspectionClosed)
pendingDiscard(); assert(inspectionClosed and LUASQUARE_MAP.Editor.document == nil, 'close clears local previews and subscriptions')
print('Plant editor drag preview, contexts, typed connection, routing, filters, splitter and cleanup checks passed.')
