if not CLIENT then return end

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
local DISPLAY = LUASQUARE_3D2D

local function activePage(display)
    for _, page in ipairs(display.pages or {}) do
        if page.id == display.activePage then return page end
    end
    return display.pages and display.pages[1] or nil
end

local function targetAt(display, x, y)
    for _, tab in ipairs(DISPLAY.GetTabRects(display)) do
        if DISPLAY.PointInRect(x, y, tab) then
            return {kind = 'page', id = tab.id}
        end
    end

    local page = activePage(display)
    if not page then return nil end
    local providers = DISPLAY.ClientState.Providers or {}
    for index = #page.elements, 1, -1 do
        local element = DISPLAY.ApplyVariants(page.elements[index], providers)
        if element.visible ~= false and element.action
            and DISPLAY.PointInRect(x, y, element) then
            return {kind = 'element', id = element.id}
        end
    end
end

local function lineOfSight(player, display, hit)
    if display.interaction.lineOfSight == false then return true end
    local trace = util.TraceLine({
        start = player:EyePos(),
        endpos = hit.point,
        filter = player,
        mask = MASK_SOLID
    })
    return not trace.Hit or trace.HitPos:DistToSqr(hit.point) <= 64
end

hook.Add('Think', 'LUASQUARE_3D2D_RaycastHover', function()
    DISPLAY.Hover = nil
    local player = LocalPlayer()
    if not IsValid(player) or not player:Alive() then return end

    local eye = player:EyePos()
    local direction = player:GetAimVector()
    local bestDistance
    for _, source in ipairs((DISPLAY.ClientState or {}).Displays or {}) do
        if source.visible ~= false and source.pos and source.interaction
            and source.interaction.enabled then
            local display = DISPLAY.DeepCopy(source)
            display.ang = DISPLAY.GetRenderAngle(display, player)
            local inFov = DISPLAY.PassesInteractionFOV(display, eye, direction)
            local hit = inFov and DISPLAY.ProjectRayToCanvas(display, eye, direction) or nil
            local maximum = tonumber(display.interaction.distance) or 128
            if hit and hit.distance <= maximum and (not bestDistance or hit.distance < bestDistance)
                and lineOfSight(player, display, hit) then
                local target = targetAt(display, hit.x, hit.y)
                if target then
                    bestDistance = hit.distance
                    DISPLAY.Hover = {
                        displayId = display.id,
                        kind = target.kind,
                        id = target.id,
                        x = hit.x,
                        y = hit.y
                    }
                end
            end
        end
    end
end)
