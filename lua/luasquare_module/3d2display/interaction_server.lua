if not SERVER then return end

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
local DISPLAY = LUASQUARE_3D2D

local function interactionDisplay(runtimeDisplay, player)
    local display = DISPLAY.DeepCopy(runtimeDisplay.definition)
    local explicitPosition = display.pos ~= nil
    local expectsTarget = display.target ~= nil or display.posTarget ~= nil
    local targetFound
    display.pos, display.ang, targetFound = DISPLAY.ResolvePlacement(display)
    display.placementValid = explicitPosition or targetFound or not expectsTarget
    if display.facePlayer and IsValid(player) then
        display.ang = Angle(0, player:EyeAngles().y - 90, 90)
    end
    display.activePage = runtimeDisplay.activePage
    display.variableValues = DISPLAY.DeepCopy(runtimeDisplay.variables or {})
    return display
end

local function lineOfSight(player, display, hit)
    if display.interaction.lineOfSight == false then return true end
    local trace = util.TraceLine({
        start = player:EyePos(),
        endpos = hit.point,
        filter = player,
        mask = MASK_SOLID
    })
    if not trace.Hit then return true end
    return trace.HitPos:DistToSqr(hit.point) <= 64
end

local function findPage(display)
    for _, page in ipairs(display.pages or {}) do
        if page.id == display.activePage then return page end
    end
    return display.pages and display.pages[1] or nil
end

local function hitTarget(display, x, y)
    local tabs = DISPLAY.GetTabRects and DISPLAY.GetTabRects(display) or {}
    for _, tab in ipairs(tabs) do
        if DISPLAY.PointInRect(x, y, tab) then
            return {kind = 'page', id = tab.id, page = tab}
        end
    end
    local page = findPage(display)
    if not page then return nil end
    for index = #page.elements, 1, -1 do
        local element = page.elements[index]
        local resolved = DISPLAY.ApplyConditions(element, DISPLAY.ProviderValues, display.variableValues)
        if resolved.visible ~= false and resolved.action
            and DISPLAY.PointInElement(x, y, resolved, CurTime()) then
            return {kind = 'element', id = resolved.id, page = page, element = resolved}
        end
    end
    return nil
end

function DISPLAY.FindPlayerInteraction(player)
    if not IsValid(player) or not player:Alive() then return nil end
    local eye = player:EyePos()
    local direction = player:GetAimVector()
    local best
    for _, runtimeDisplay in pairs(DISPLAY.Displays or {}) do
        local definition = runtimeDisplay.definition
        if definition.visible ~= false and definition.interaction and definition.interaction.enabled then
            local display = interactionDisplay(runtimeDisplay, player)
            local inFov = display.placementValid and DISPLAY.PassesInteractionFOV(display, eye, direction)
            local hit = inFov and DISPLAY.ProjectRayToCanvas(display, eye, direction) or nil
            local maximum = definition.interaction.distance or 128
            if hit and hit.distance <= maximum and lineOfSight(player, display, hit) then
                local target = hitTarget(display, hit.x, hit.y)
                if target and (not best or hit.distance < best.hit.distance) then
                    best = {runtime = runtimeDisplay, display = display, hit = hit, target = target}
                end
            end
        end
    end
    return best
end

local function runAction(player, interaction)
    local element = interaction.target.element
    local action = element and DISPLAY.Actions[element.action]
    if not action then return false end
    local current = CurTime()
    if current < (action.lastUse[player] or 0) then return false end
    local context = {
        displayId = interaction.runtime.id,
        pageId = interaction.target.page.id,
        elementId = element.id,
        payload = DISPLAY.DeepCopy(element.actionPayload),
        hit = {x = interaction.hit.x, y = interaction.hit.y}
    }
    if action.canUse then
        local ok, allowed = pcall(
            action.canUse,
            player,
            interaction.runtime,
            interaction.target.page,
            element,
            context
        )
        if not ok or allowed == false then return false end
    end
    local ok, result = pcall(
        action.callback,
        player,
        interaction.runtime,
        interaction.target.page,
        element,
        context
    )
    if not ok then
        print('[LUASQUARE_3D2D] Action ' .. action.id .. ' failed: ' .. tostring(result))
        return false
    end
    if result == false then return false end
    action.lastUse[player] = current + action.cooldown
    return true
end

hook.Add('KeyPress', 'LUASQUARE_3D2D_RaycastUse', function(player, key)
    if key ~= IN_USE then return end
    local interaction = DISPLAY.FindPlayerInteraction(player)
    if not interaction then return end
    local used = false
    if interaction.target.kind == 'page' then
        used = DISPLAY.SetDisplayPage(interaction.runtime.id, interaction.target.id, player)
    elseif interaction.target.kind == 'element' then
        used = runAction(player, interaction)
    end
    if used then player.LUASQUARE_3D2D_SuppressUseUntil = CurTime() + 0.1 end
end)

hook.Add('PlayerUse', 'LUASQUARE_3D2D_SuppressWorldUse', function(player)
    if CurTime() < (player.LUASQUARE_3D2D_SuppressUseUntil or 0) then return false end
end)
