if not CLIENT then return end

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
local DISPLAY = LUASQUARE_3D2D
local materialCache = {}
local colorKeys = {
    color = true,
    textColor = true,
    titleColor = true,
    backgroundColor = true,
    borderColor = true,
    barColor = true,
    barBackgroundColor = true,
    valueColor = true,
    warnColor = true,
    criticalColor = true,
    lineColor = true,
    fillColor = true,
    axisColor = true,
    axisLabelColor = true,
    tint = true
}

local function asColor(value, fallback)
    local tableColor = DISPLAY.ColorTable(value, fallback)
    return Color(tableColor.r, tableColor.g, tableColor.b, tableColor.a)
end

local function themed(display, value, fallback)
    local tableColor = DISPLAY.ResolveThemeToken(display, value, fallback, DISPLAY.ClientState)
    return Color(tableColor.r, tableColor.g, tableColor.b, tableColor.a)
end

local function resolveColors(display, value, parentKey)
    if colorKeys[parentKey] then return themed(display, value) end
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, item in pairs(value) do out[key] = resolveColors(display, item, key) end
    return out
end

local function resolveItem(display, item)
    local resolved = DISPLAY.ApplyConditions(
        item,
        DISPLAY.ClientState.Providers or {},
        display.variableValues or {}
    )
    return resolveColors(display, resolved)
end

local function getMaterial(path)
    if not path or path == '' then return nil end
    if not materialCache[path] then materialCache[path] = Material(path, 'smooth') end
    return materialCache[path]
end

local function currentMaterial(element, previewAnimations)
    local frames = element.frames or {}
    if #frames > 0 then
        local frameSeconds = tonumber(element.frameSeconds) or 0
        if element.animationDisabled or element.frameAnimationEnabled == false
            or previewAnimations == false or frameSeconds < 0.2 then
            return frames[1] or element.material
        end
        local epoch = tonumber(element.animationEpoch) or 0
        local index = math.floor((DISPLAY.GetSynchronizedTime() - epoch) / frameSeconds)
        if element.loop == false then index = math.min(math.max(index, 0), #frames - 1) end
        return frames[index % #frames + 1]
    end
    return element.material
end

local function flashAlpha(element, alpha, previewAnimations)
    if element.animationDisabled or element.flashEnabled == false or previewAnimations == false then return alpha end
    local seconds = tonumber(element.flashSeconds)
    if not seconds or seconds < 0.02 then return alpha end
    local phase = math.floor(DISPLAY.GetSynchronizedTime() / seconds) % 2
    return phase == 0 and alpha or math.floor(alpha * (tonumber(element.flashMinimum) or 0.2))
end

local function drawMaterial(element, x, y, width, height, previewAnimations)
    local material = getMaterial(currentMaterial(element, previewAnimations))
    if not material or material:IsError() then return end
    local tint = asColor(element.tint or element.color, {r = 255, g = 255, b = 255, a = 255})
    tint.a = flashAlpha(element, tint.a, previewAnimations)
    surface.SetMaterial(material)
    surface.SetDrawColor(tint)
    local rotation = DISPLAY.GetElementRotation(element, DISPLAY.GetSynchronizedTime(), previewAnimations)
    if rotation % 360 == 0 then surface.DrawTexturedRect(x, y, width, height)
    else surface.DrawTexturedRectRotated(x + width * 0.5, y + height * 0.5, width, height, rotation) end
end

local function graphHistoryKey(displayId, pageId, elementId, line, lineIndex, series, seriesIndex)
    local graphId = DISPLAY.NormalizeId(line.id or ('graph_' .. lineIndex))
    return table.concat({
        displayId,
        pageId or 'simple',
        elementId or 'lines',
        graphId,
        tostring(series.id or seriesIndex)
    }, ':')
end

local function injectGraphHistory(display, pageId, elementId, line, lineIndex)
    if line.type ~= 'graph' then return end
    if type(line.series) ~= 'table' or #line.series == 0 then
        line.series = {{id = 'value', label = line.label, value = line.value, color = line.color}}
    end
    for seriesIndex, series in ipairs(line.series) do
        local key = graphHistoryKey(display.id, pageId, elementId, line, lineIndex, series, seriesIndex)
        local history = (DISPLAY.ClientState.Graphs or {})[key]
        series.points = history and DISPLAY.DeepCopy(history.points) or {}
    end
    line.now = DISPLAY.GetSynchronizedTime()
end

local function lineAdvance(line, lineHeight)
    if line.type == 'columns' then
        return (tonumber(line.height) or math.max(lineHeight * 3, 56)) + 6
    end
    if line.type == 'graph' then
        return (tonumber(line.height) or math.max(lineHeight * 5, 90)) + lineHeight + 12
    end
    if line.type == 'bar' or line.type == 'phase' then
        return lineHeight + (tonumber(line.height) or 8) + 4
    end
    return lineHeight
end

local function drawLines(display, lines, x, y, width, height, pageId, elementId, lineHeight)
    local bottom = y + height
    for index, source in ipairs(lines or {}) do
        local line = resolveItem(display, source)
        if line.visible ~= false and y <= bottom then
            injectGraphHistory(display, pageId, elementId, line, index)
            DISPLAY.RenderLine(display, line, x, y, width, lineHeight)
            y = y + lineAdvance(line, lineHeight)
        end
    end
end

local function drawLinePanel(display, element, pageId, previewAnimations)
    local x, y = element.x, element.y
    local width, height = element.width, element.height
    if element.backgroundMaterial then
        drawMaterial({
            material = element.backgroundMaterial,
            tint = element.backgroundTint,
            flashSeconds = element.flashSeconds,
            flashMinimum = element.flashMinimum
        }, x, y, width, height, previewAnimations)
    end
    if element.drawBackground ~= false then
        local sourceColor = element.backgroundColor or themed(display, '@panel')
        local background = Color(sourceColor.r, sourceColor.g, sourceColor.b, sourceColor.a)
        background.a = flashAlpha(element, background.a, previewAnimations)
        surface.SetDrawColor(background)
        surface.DrawRect(x, y, width, height)
    end
    if element.drawBorder ~= false then
        local sourceColor = element.borderColor or display.borderColor
        local border = Color(sourceColor.r, sourceColor.g, sourceColor.b, sourceColor.a)
        border.a = flashAlpha(element, border.a, previewAnimations)
        surface.SetDrawColor(border)
        surface.DrawOutlinedRect(x, y, width, height, math.max(tonumber(element.borderWidth) or 1, 1))
    end
    local padding = tonumber(element.padding) or 6
    local lineHeight = tonumber(element.lineHeight) or display.lineHeight or 16
    local contentY = y + padding
    if element.title and element.title ~= '' then
        draw.SimpleText(
            tostring(element.title),
            element.titleFont or display.titleFont or 'Luasquare3D2D_Title',
            x + padding,
            contentY,
            element.titleColor or display.titleColor,
            TEXT_ALIGN_LEFT,
            TEXT_ALIGN_TOP
        )
        contentY = contentY + (tonumber(element.titleHeight) or display.titleHeight or 28)
    end
    drawLines(
        display,
        element.lines,
        x + padding,
        contentY,
        math.max(width - padding * 2, 1),
        math.max(y + height - padding - contentY, 1),
        pageId,
        element.id,
        lineHeight
    )
end

local annunciatorColors = {
    inactive = '@inactive',
    active = '@critical',
    acknowledged = '@warning',
    muted = '@warning',
    reset = '@accent',
    missing = '@inactive'
}

local function drawAnnunciator(display, element, previewAnimations)
    local alarm = (DISPLAY.ClientState.Annunciators or {})[element.alarm]
        or {state = 'missing', label = element.alarm or 'MISSING'}
    local state = tostring(alarm.state or 'inactive')
    local background = element.backgroundColor or themed(display, annunciatorColors[state] or '@inactive')
    local flash = DISPLAY.DeepCopy(element)
    if flash.flashSeconds == nil and state == 'active' then flash.flashSeconds = 0.25 end
    if flash.flashSeconds == nil and state == 'reset' then flash.flashSeconds = 0.75 end
    background.a = flashAlpha(flash, background.a, previewAnimations)
    surface.SetDrawColor(background)
    surface.DrawRect(element.x, element.y, element.width, element.height)
    surface.SetDrawColor(element.borderColor or display.borderColor)
    surface.DrawOutlinedRect(element.x, element.y, element.width, element.height, 1)
    draw.SimpleText(
        tostring(element.label or alarm.label or element.alarm),
        element.font or display.font or 'Luasquare3D2D_Line',
        element.x + element.width * 0.5,
        element.y + element.height * 0.5,
        element.textColor or color_white,
        TEXT_ALIGN_CENTER,
        TEXT_ALIGN_CENTER
    )
end

function DISPLAY.GetActivePage(display)
    local pageId = display.activePage or display.defaultPage
    for _, page in ipairs(display.pages or {}) do
        if page.id == pageId then return page end
    end
    return display.pages and display.pages[1] or nil
end

local function drawTabs(display)
    for _, rect in ipairs(DISPLAY.GetTabRects(display)) do
        local active = rect.id == display.activePage
        local hovered = DISPLAY.Hover and DISPLAY.Hover.displayId == display.id
            and DISPLAY.Hover.kind == 'page' and DISPLAY.Hover.id == rect.id
        surface.SetDrawColor(active and display.barColor
            or (hovered and themed(display, '@warning') or themed(display, '@panel')))
        surface.DrawRect(rect.x, rect.y, rect.width, rect.height)
        surface.SetDrawColor(display.borderColor)
        surface.DrawOutlinedRect(rect.x, rect.y, rect.width, rect.height, 1)
        draw.SimpleText(
            tostring(rect.label),
            display.font,
            rect.x + rect.width * 0.5,
            rect.y + rect.height * 0.5,
            display.textColor,
            TEXT_ALIGN_CENTER,
            TEXT_ALIGN_CENTER
        )
    end
end

function DISPLAY.RenderElement(display, source, pageId, renderOptions)
    local element = resolveItem(display, source)
    if element.visible == false then return end
    local animationKey = tostring(pageId or 'simple') .. ':' .. tostring(element.id)
    local previewAnimations = not renderOptions or not renderOptions.animationPreview
        or renderOptions.animationPreview[animationKey] ~= false
    if element.type == 'solid_rectangle' then
        local color = element.color or element.backgroundColor or display.barColor
        color.a = flashAlpha(element, color.a, previewAnimations)
        surface.SetDrawColor(color)
        surface.DrawRect(element.x, element.y, element.width, element.height)
    elseif element.type == 'material' then
        drawMaterial(element, element.x, element.y, element.width, element.height, previewAnimations)
    elseif element.type == 'line_panel' then
        drawLinePanel(display, element, pageId, previewAnimations)
    elseif element.type == 'annunciator' then
        drawAnnunciator(display, element, previewAnimations)
    end

    if DISPLAY.Hover and DISPLAY.Hover.displayId == display.id
        and DISPLAY.Hover.kind == 'element' and DISPLAY.Hover.id == element.id then
        surface.SetDrawColor(themed(display, '@warning'))
        surface.DrawOutlinedRect(element.x, element.y, element.width, element.height, 2)
    end
end

local function resolveDisplayStyle(source, variableValues)
    local display = DISPLAY.DeepCopy(source)
    local structural = {pages = true, lines = true, variables = true, variableValues = true}
    for key, value in pairs(source) do
        if not structural[key] then
            display[key] = DISPLAY.ResolveDynamic(value, DISPLAY.ClientState.Providers or {}, variableValues or {})
        end
    end
    display.font = display.font or 'Luasquare3D2D_Line'
    display.titleFont = display.titleFont or 'Luasquare3D2D_Title'
    display.textColor = themed(display, display.textColor, {r = 220, g = 245, b = 255, a = 255})
    display.titleColor = themed(display, display.titleColor, {r = 255, g = 255, b = 255, a = 255})
    display.backgroundColor = themed(display, display.backgroundColor, {r = 4, g = 12, b = 16, a = 220})
    display.borderColor = themed(display, display.borderColor, {r = 80, g = 190, b = 220, a = 220})
    display.barColor = themed(display, display.barColor, {r = 70, g = 220, b = 160, a = 255})
    display.barBackgroundColor = themed(display, display.barBackgroundColor, {r = 18, g = 32, b = 36, a = 240})
    return display
end

function DISPLAY.DrawDisplayCanvas(source, renderOptions)
    local variableValues = renderOptions and renderOptions.variableValues or source.variableValues or {}
    local display = resolveDisplayStyle(source, variableValues)
    display.variableValues = variableValues
    local width = display.width or 256
    local height = display.height or 128
    if display.drawBackground then
        surface.SetDrawColor(display.backgroundColor)
        surface.DrawRect(0, 0, width, height)
    end
    if display.drawBorder then
        surface.SetDrawColor(display.borderColor)
        surface.DrawOutlinedRect(0, 0, width, height, 1)
    end

    if display.buildMode == 'complex' then
        local page = DISPLAY.GetActivePage(display)
        if page then
            for _, element in ipairs(page.elements or {}) do DISPLAY.RenderElement(display, element, page.id, renderOptions) end
        end
        drawTabs(display)
        return
    end

    local padding = display.padding or 8
    local y = padding
    if display.title and display.title ~= '' then
        draw.SimpleText(display.title, display.titleFont, padding, y, display.titleColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        y = y + (display.titleHeight or 28)
    end
    drawLines(
        display,
        display.lines,
        padding,
        y,
        math.max(width - padding * 2, 1),
        math.max(height - padding - y, 1),
        nil,
        nil,
        display.lineHeight or 16
    )
end

function DISPLAY.RenderDisplay(source)
    if not DISPLAY.ShouldRenderDisplay(source) then return end
    local ang = DISPLAY.GetRenderAngle(source, LocalPlayer())
    local originX = -(source.width or 256) * (source.anchorX or 0)
    local originY = -(source.height or 128) * (source.anchorY or 0)
    cam.Start3D2D(source.pos, ang, source.scale or 0.1)
        local matrix = Matrix()
        matrix:SetTranslation(Vector(originX, originY, 0))
        cam.PushModelMatrix(matrix, true)
            DISPLAY.DrawDisplayCanvas(source)
        cam.PopModelMatrix()
    cam.End3D2D()
end
