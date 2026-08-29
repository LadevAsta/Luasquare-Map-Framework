if not CLIENT then return end

LUASQUARE_EDITOR_THEME = LUASQUARE_EDITOR_THEME or {}
local THEME = LUASQUARE_EDITOR_THEME

THEME.Colors = THEME.Colors or {
    frame = Color(43, 46, 50), panel = Color(49, 53, 58), inset = Color(31, 35, 39),
    raised = Color(62, 67, 72), border = Color(83, 91, 99), text = Color(228, 232, 235),
    muted = Color(174, 181, 187), accent = Color(62, 166, 214)
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
    if not IsValid(panel) or panel.LuasquareThemed then return panel end
    panel.LuasquareThemed = true
    local colors = THEME.Colors
    local className = panel.GetClassName and panel:GetClassName() or panel.ClassName or ''
    if kind == 'frame' or className == 'DFrame' then
        panel.Paint = function(self, width, height)
            draw.RoundedBox(3, 0, 0, width, height, colors.frame)
            draw.RoundedBoxEx(3, 0, 0, width, 25, colors.raised, true, true, false, false)
        end
    elseif kind == 'inset' or className == 'DTree' or className == 'DListView' then
        panel.Paint = paint(colors.inset, colors.border)
    elseif kind == 'panel' then
        panel.Paint = paint(colors.panel)
    elseif className == 'DLabel' then
        panel:SetTextColor(colors.text)
    end
    if className == 'DScrollPanel' and IsValid(panel:GetCanvas()) then
        panel:GetCanvas().Paint = paint(colors.panel)
    end
    return panel
end

function THEME.ApplyTree(root)
    if not IsValid(root) then return end
    THEME.Apply(root)
    for _, child in ipairs(root:GetChildren() or {}) do THEME.ApplyTree(child) end
end

function THEME.PaintTimeline(panel)
    if IsValid(panel) then panel.Paint = paint(THEME.Colors.inset, THEME.Colors.border) end
end
