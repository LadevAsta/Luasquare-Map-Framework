if not CLIENT then return end

LUASQUARE_EDITOR_THEME = LUASQUARE_EDITOR_THEME or {}
local THEME = LUASQUARE_EDITOR_THEME

THEME.Colors = THEME.Colors or {
    frame = Color(43, 46, 50), panel = Color(49, 53, 58), inset = Color(31, 35, 39),
    raised = Color(62, 67, 72), border = Color(83, 91, 99), text = Color(228, 232, 235),
    muted = Color(174, 181, 187), accent = Color(62, 166, 214),
    hover = Color(72, 78, 84), pressed = Color(35, 39, 43), disabled = Color(50, 54, 58)
}

local function paint(color, border)
    return function(_, width, height)
        surface.SetDrawColor(color) surface.DrawRect(0, 0, width, height)
        if border then
            surface.SetDrawColor(border) surface.DrawOutlinedRect(0, 0, width, height, 1)
        end
    end
end

function THEME.Apply(panel, kind)
    if not IsValid(panel) or (panel.LuasquareThemed and not kind) then return panel end
    panel.LuasquareThemed = true
    local colors = THEME.Colors
    local className = panel.GetClassName and panel:GetClassName() or panel.ClassName or ''
    local parent = panel.GetParent and panel:GetParent()
    if IsValid(parent) and (panel == parent.btnClose or panel == parent.btnMaxim or panel == parent.btnMinim) then
        return panel -- Preserve Derma's native title-bar icons and hover/disabled rendering.
    end
    if IsValid(parent) and parent.GetClassName and parent:GetClassName() == 'DNumberWang'
        and (panel == parent.Up or panel == parent.Down) then return panel end
    if kind == 'frame' or className == 'DFrame' then
        panel.Paint = function(self, width, height)
            draw.RoundedBox(3, 0, 0, width, height, colors.frame)
            draw.RoundedBoxEx(3, 0, 0, width, 25, colors.raised, true, true, false, false)
        end
    elseif kind == 'inset' or className == 'DTree' or className == 'DListView' or className == 'DMenu' then
        panel.Paint = paint(colors.inset, colors.border)
    elseif className == 'DMenuOption' then
        panel:SetTextColor(colors.text)
        panel.UpdateColours = function(self) self:SetTextStyleColor(colors.text) end
        panel.Paint = function(self, width, height)
            surface.SetDrawColor(self:IsHovered() and colors.hover or colors.inset)
            surface.DrawRect(0, 0, width, height)
            return false -- Native label rendering retains menu alignment and text inset.
        end
    elseif kind == 'panel' then
        panel.Paint = paint(colors.panel)
    elseif className == 'DLabel' or className == 'DListViewLabel' or className == 'DListViewHeaderLabel' then
        panel:SetTextColor(colors.text)
        if className == 'DListViewLabel' then
            panel.UpdateColours = function(self) self:SetTextStyleColor(colors.text) end
        end
    elseif className == 'DVScrollBar' then
        panel.Paint = paint(colors.inset)
    elseif className == 'DScrollBarGrip' then
        panel.Paint = function(self, width, height)
            surface.SetDrawColor(self:IsHovered() and colors.hover or colors.raised)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(colors.border)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
        end
    elseif className == 'DButton' or className == 'DComboBox' then
        panel:SetTextColor(colors.text)
        panel.Paint = function(self, width, height)
            local color = not self:IsEnabled() and colors.disabled
                or (self:IsDown() and colors.pressed)
                or (self:IsHovered() and colors.hover)
                or colors.raised
            surface.SetDrawColor(color)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(colors.border)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
            draw.SimpleText(self:GetText() or '', self:GetFont() or 'DermaDefault',
                width / 2, height / 2, self:GetTextColor() or colors.text,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    elseif className == 'DTextEntry' or className == 'DNumberWang' then
        panel:SetTextColor(colors.text)
        panel:SetHighlightColor(colors.accent)
        panel:SetCursorColor(colors.text)
        panel.Paint = function(self, width, height)
            surface.SetDrawColor(colors.inset)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(colors.border)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
            local placeholder = self.GetPlaceholderText and self:GetPlaceholderText() or ''
            if self:GetValue() == '' and placeholder ~= '' and not self:HasFocus() then
                draw.SimpleText(placeholder, self:GetFont() or 'DermaDefault', 5,
                    self:GetMultiline() and 5 or height / 2, colors.muted, TEXT_ALIGN_LEFT,
                    self:GetMultiline() and TEXT_ALIGN_TOP or TEXT_ALIGN_CENTER)
            else
                self:DrawTextEntryText(colors.text, colors.accent, colors.text)
            end
        end
    elseif className == 'DCheckBoxLabel' then
        panel:SetTextColor(colors.text)
    elseif className == 'DListView_Line' then
        panel.Paint = function(self, width, height)
            local color = self:IsLineSelected() and colors.accent
                or (self:IsHovered() and colors.raised)
                or colors.inset
            surface.SetDrawColor(color)
            surface.DrawRect(0, 0, width, height)
        end
    elseif className == 'DListView_ColumnHeader' then
        panel:SetTextColor(colors.text)
        panel.Paint = function(self, width, height)
            surface.SetDrawColor(colors.raised)
            surface.DrawRect(0, 0, width, height)
            surface.SetDrawColor(colors.border)
            surface.DrawOutlinedRect(0, 0, width, height, 1)
            draw.SimpleText(self:GetText() or '', self:GetFont() or 'DermaDefault', 6,
                height / 2, colors.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
    end
    if className == 'DScrollPanel' and IsValid(panel:GetCanvas()) then
        panel:GetCanvas().Paint = paint(colors.panel)
    end
    return panel
end

function THEME.ApplyEditor(frame, panels)
    if not IsValid(frame) then return end
    THEME.Apply(frame, 'frame')
    for _, panel in ipairs(panels or {}) do THEME.Apply(panel, 'panel') end
    THEME.ApplyTree(frame)
end

function THEME.ApplyTree(root)
    if not IsValid(root) then return end
    THEME.Apply(root)
    for _, child in ipairs(root:GetChildren() or {}) do THEME.ApplyTree(child) end
end

function THEME.PaintTimeline(panel)
    if IsValid(panel) then panel.Paint = paint(THEME.Colors.inset, THEME.Colors.border) end
end

-- Wrapped text grows inside a bounded viewport instead of clipping diagnostics.
function THEME.CreateTextArea(parent)
    local panel = vgui.Create('DScrollPanel', parent)
    local text = panel:Add('DLabel')
    text:Dock(TOP)
    text:DockMargin(6, 4, 6, 4)
    text:SetWrap(true)
    text:SetAutoStretchVertical(true)
    text:SetContentAlignment(7)
    text:SetText('')
    text:SetMouseInputEnabled(true)
    text:SetCursor('ibeam')
    text.OnMousePressed = function(_, button)
        if button ~= MOUSE_RIGHT then return end
        local menu = DermaMenu()
        menu:AddOption('Copy text', function() SetClipboardText(text:GetText()) end)
        menu:Open()
        THEME.ApplyTree(menu)
    end
    text.OnMouseWheeled = function(_, delta) return panel:OnMouseWheeled(delta) end
    panel.TextLabel = text
    function panel:SetText(value)
        value = tostring(value or '')
        if text:GetText() == value then return end
        text:SetText(value)
        text:InvalidateLayout(true)
        self:InvalidateLayout(true)
    end
    panel.SetValue = panel.SetText
    function panel:GetText() return text:GetText() end
    function panel:SetTextColor(value) text:SetTextColor(value) end
    function panel:SetWrap(value) text:SetWrap(value) end
    function panel:SetContentAlignment(value) text:SetContentAlignment(value) end
    function panel:SetTextInset(x, y) text:SetTextInset(x, y) end
    THEME.ApplyTree(panel)
    return panel
end
