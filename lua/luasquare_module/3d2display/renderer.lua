if not CLIENT or LUASQUARE_3D2D_RENDERER_LOADED then return end
LUASQUARE_3D2D_RENDERER_LOADED = true

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
local DISPLAY = LUASQUARE_3D2D

CreateClientConVar('luasquare_3d2d_maxdistance', '2500', true, false)
CreateClientConVar('luasquare_3d2d_fovcheck', '1', true, false)

surface.CreateFont('Luasquare3D2D_Title', {font = 'Roboto', size = 24, weight = 700, antialias = true})
surface.CreateFont('Luasquare3D2D_Line', {font = 'Roboto Mono', size = 18, weight = 500, antialias = true})
surface.CreateFont('Luasquare3D2D_Small', {font = 'Roboto Mono', size = 14, weight = 500, antialias = true})

local function formatValue(value, decimals, unit)
    if type(value) == 'number' then
        value = string.format('%.' .. math.max(math.floor(tonumber(decimals) or 0), 0) .. 'f', value)
    elseif type(value) == 'boolean' then
        value = value and 'YES' or 'NO'
    elseif value == nil then
        value = '--'
    else
        value = tostring(value)
    end
    return value .. (unit and unit ~= '' and (' ' .. tostring(unit)) or '')
end

local function lineColor(display, line)
    if line.critical then return line.criticalColor or Color(255, 90, 90) end
    if line.warn then return line.warnColor or Color(255, 210, 70) end
    return line.color or display.textColor or color_white
end

local function drawTextLine(display, line, x, y, width)
    local alignment = line.align == 'center' and TEXT_ALIGN_CENTER
        or (line.align == 'right' and TEXT_ALIGN_RIGHT or TEXT_ALIGN_LEFT)
    local drawX = alignment == TEXT_ALIGN_CENTER and x + width * 0.5
        or (alignment == TEXT_ALIGN_RIGHT and x + width or x)
    draw.SimpleText(tostring(line.text or line.label or ''), line.font or display.font or 'Luasquare3D2D_Line',
        drawX, y, lineColor(display, line), alignment, TEXT_ALIGN_TOP)
end

local function drawValueLine(display, line, x, y, width)
    local font = line.font or display.font or 'Luasquare3D2D_Line'
    draw.SimpleText(tostring(line.label or ''), font, x, y, lineColor(display, line), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(formatValue(line.value, line.decimals, line.unit), font, x + width, y,
        line.valueColor or lineColor(display, line), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
end

local function drawColumnsLine(display, line, x, y, width, lineHeight)
    local columns = line.columns or {}
    local count = math.max(#columns, 1)
    local gap = tonumber(line.columnsGap) or 6
    local columnWidth = (width - gap * (count - 1)) / count
    local columnHeight = tonumber(line.height) or math.max(lineHeight * 3, 56)
    for index, column in ipairs(columns) do
        local left = x + (index - 1) * (columnWidth + gap)
        local center = left + columnWidth * 0.5
        local font = column.font or line.font or display.font or 'Luasquare3D2D_Line'
        surface.SetDrawColor(column.backgroundColor or display.barBackgroundColor)
        surface.DrawRect(left, y, math.max(columnWidth, 1), columnHeight)
        surface.SetDrawColor(column.borderColor or display.borderColor)
        surface.DrawOutlinedRect(left, y, math.max(columnWidth, 1), columnHeight, 1)
        draw.SimpleText(tostring(column.label or ''), font, left + 6, y + 5, column.color or display.textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(tostring(column.value or '--'), column.valueFont or display.titleFont, center, y + 24,
            column.valueColor or column.color or display.titleColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        draw.SimpleText(tostring(column.sub or ''), column.subFont or 'Luasquare3D2D_Small', center, y + columnHeight - 18,
            column.subColor or display.textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end

local function drawBarLine(display, line, x, y, width, lineHeight)
    local height = tonumber(line.height) or 8
    local barY = y
    if line.label then
        drawValueLine(display, line, x, y, width)
        barY = y + lineHeight
    end
    local fraction = math.Clamp(tonumber(line.fraction) or 0, 0, tonumber(line.maxFraction) or 1)
    surface.SetDrawColor(line.backgroundColor or display.barBackgroundColor)
    surface.DrawRect(x, barY, width, height)
    surface.SetDrawColor(line.fillColor or line.barColor or (line.warn and Color(255, 210, 70)) or display.barColor)
    surface.DrawRect(x, barY, width * math.min(fraction, 1), height)
    surface.SetDrawColor(line.borderColor or display.borderColor)
    surface.DrawOutlinedRect(x, barY, width, height, 1)
end

local function drawPhaseLine(display, line, x, y, width, lineHeight)
    local font = line.font or display.font or 'Luasquare3D2D_Line'
    local value = tonumber(line.value) or 0
    local minimum = tonumber(line.min) or -180
    local maximum = tonumber(line.max) or 180
    local range = maximum - minimum
    local fraction = range ~= 0 and math.Clamp((value - minimum) / range, 0, 1) or 0.5
    local barY = y + math.floor(lineHeight * 0.9)
    local height = tonumber(line.height) or 10
    draw.SimpleText(tostring(line.label or line.text or 'PHASE'), font, x, y,
        lineColor(display, line), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(formatValue(value, line.decimals, line.unit), font, x + width, y,
        line.valueColor or display.textColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    surface.SetDrawColor(line.backgroundColor or display.barBackgroundColor)
    surface.DrawRect(x, barY, width, height)
    surface.SetDrawColor(line.borderColor or display.borderColor)
    surface.DrawRect(x + math.floor(width * 0.5) - 1, barY - 2, 2, height + 4)
    surface.SetDrawColor(line.barColor or display.barColor)
    surface.DrawRect(x + math.floor(width * fraction) - 2, barY - 3, 4, height + 6)
end

local function graphBounds(line)
    local minimum = tonumber(line.min)
    local maximum = tonumber(line.max)
    for _, series in ipairs(line.series or {}) do
        for _, point in ipairs(series.points or {}) do
            local value = tonumber(point.v or point.value or point[2])
            if value then
                minimum = minimum and math.min(minimum, value) or value
                maximum = maximum and math.max(maximum, value) or value
            end
        end
    end
    minimum = minimum or 0
    maximum = maximum or 1
    if maximum <= minimum then maximum = minimum + 1 end
    return minimum, maximum
end

local function drawGraphLine(display, line, x, y, width, lineHeight)
    local font = line.font or display.font or 'Luasquare3D2D_Line'
    local chartHeight = tonumber(line.height) or math.max(lineHeight * 5, 90)
    local chartY = y
    if line.label or line.text then
        draw.SimpleText(tostring(line.label or line.text), font, x, y, lineColor(display, line), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        local first = (line.series or {})[1] or {}
        draw.SimpleText(formatValue(first.value or line.value, line.decimals or first.decimals, line.unit or first.unit),
            font, x + width, y, first.color or line.valueColor or display.textColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        chartY = y + lineHeight
    end
    surface.SetDrawColor(line.backgroundColor or display.barBackgroundColor)
    surface.DrawRect(x, chartY, width, chartHeight)
    local showYAxis = line.showYAxis ~= false and line.showScale ~= false
    local showXAxis = line.showXAxis ~= false
    local leftMargin = showYAxis and (tonumber(line.yAxisWidth) or 42) or 4
    local bottomMargin = showXAxis and 18 or 4
    local plotX = x + leftMargin
    local plotY = chartY + 4
    local plotWidth = math.max(width - leftMargin - 4, 1)
    local plotHeight = math.max(chartHeight - bottomMargin - 4, 1)
    surface.SetDrawColor(line.gridColor or Color(70, 95, 105, 90))
    local yTicks = math.max(math.floor(tonumber(line.yTicks) or 4), 1)
    local xTicks = math.max(math.floor(tonumber(line.xTicks) or 4), 1)
    for index = 0, yTicks do
        local gridY = plotY + plotHeight * index / yTicks
        surface.DrawLine(plotX, gridY, plotX + plotWidth, gridY)
    end
    for index = 0, xTicks do
        local gridX = plotX + plotWidth * index / xTicks
        surface.DrawLine(gridX, plotY, gridX, plotY + plotHeight)
    end
    local minimum, maximum = graphBounds(line)
    local now = tonumber(line.now) or 0
    local seconds = math.max(tonumber(line.seconds) or 60, 0.1)
    for _, threshold in ipairs(line.thresholds or {}) do
        local value = tonumber(threshold.value)
        if value then
            local ty = plotY + plotHeight * (1 - math.Clamp((value - minimum) / (maximum - minimum), 0, 1))
            surface.SetDrawColor(threshold.color or Color(255, 210, 70))
            surface.DrawLine(plotX, ty, plotX + plotWidth, ty)
            if threshold.label then
                draw.SimpleText(tostring(threshold.label), line.axisFont or 'Luasquare3D2D_Small',
                    plotX + plotWidth - 2, ty - 1, threshold.color or display.textColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
            end
        end
    end
    for seriesIndex, series in ipairs(line.series or {}) do
        local previousX, previousY
        surface.SetDrawColor(series.lineColor or series.color or line.color or HSVToColor((seriesIndex - 1) * 90, 0.7, 1))
        for _, point in ipairs(series.points or {}) do
            local sampleTime = tonumber(point.t or point.time or point[1])
            local value = tonumber(point.v or point.value or point[2])
            if sampleTime and value and sampleTime >= now - seconds then
                local px = plotX + plotWidth * math.Clamp((sampleTime - (now - seconds)) / seconds, 0, 1)
                local py = plotY + plotHeight * (1 - math.Clamp((value - minimum) / (maximum - minimum), 0, 1))
                if previousX then surface.DrawLine(previousX, previousY, px, py) end
                previousX, previousY = px, py
            end
        end
    end
    local axisFont = line.axisFont or 'Luasquare3D2D_Small'
    local axisColor = line.axisColor or display.textColor
    if showYAxis then
        for index = 0, yTicks do
            local fraction = index / yTicks
            local value = maximum - (maximum - minimum) * fraction
            local ty = plotY + plotHeight * fraction
            draw.SimpleText(formatValue(value, line.decimals, line.unit), axisFont, plotX - 3, ty,
                axisColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
        end
    end
    if showXAxis then
        for index = 0, xTicks do
            local fraction = index / xTicks
            local remaining = -math.floor(seconds * (1 - fraction) + 0.5)
            draw.SimpleText(tostring(remaining) .. 's', axisFont, plotX + plotWidth * fraction,
                plotY + plotHeight + 2, axisColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
    surface.SetDrawColor(line.borderColor or display.borderColor)
    surface.DrawOutlinedRect(plotX, plotY, plotWidth, plotHeight, 1)
end

function DISPLAY.RenderLine(display, line, x, y, width, lineHeight)
    if line.type == 'value' then drawValueLine(display, line, x, y, width)
    elseif line.type == 'columns' then drawColumnsLine(display, line, x, y, width, lineHeight)
    elseif line.type == 'bar' then drawBarLine(display, line, x, y, width, lineHeight)
    elseif line.type == 'graph' then drawGraphLine(display, line, x, y, width, lineHeight)
    elseif line.type == 'phase' then drawPhaseLine(display, line, x, y, width, lineHeight)
    else drawTextLine(display, line, x, y, width) end
end

function DISPLAY.GetRenderAngle(display, player)
    if display.facePlayer and IsValid(player or LocalPlayer()) then
        return Angle(0, (player or LocalPlayer()):EyeAngles().y - 90, 90)
    end
    return display.ang or Angle(0, 0, 90)
end

function DISPLAY.GetDisplayCenterPos(display, player)
    if not display.pos then return nil end
    local angle = DISPLAY.GetRenderAngle(display, player)
    local scale = display.scale or 0.1
    local centerX = (0.5 - (display.anchorX or 0)) * (display.width or 256) * scale
    local centerY = (0.5 - (display.anchorY or 0)) * (display.height or 128) * scale
    return display.pos + angle:Forward() * centerX + angle:Right() * centerY
end

function DISPLAY.GetDisplayCullRadius(display)
    local width = (display.width or 256) * (display.scale or 0.1)
    local height = (display.height or 128) * (display.scale or 0.1)
    return math.sqrt(width * width + height * height) * 0.5
end

function DISPLAY.ShouldRenderDisplay(display)
    if not display.visible or not display.pos then return false end
    local player = LocalPlayer()
    if not IsValid(player) then return true end
    local center = DISPLAY.GetDisplayCenterPos(display, player) or display.pos
    local radius = DISPLAY.GetDisplayCullRadius(display)
    local distanceCvar = GetConVar('luasquare_3d2d_maxdistance')
    local maximum = tonumber(display.renderDistance) or (distanceCvar and distanceCvar:GetFloat()) or 2500
    if maximum > 0 and player:EyePos():DistToSqr(center) > (maximum + radius) ^ 2 then return false end
    local fovCheck = GetConVar('luasquare_3d2d_fovcheck')
    if not fovCheck or not fovCheck:GetBool() then return true end
    local direction = center - player:EyePos()
    local distance = direction:Length()
    if distance <= radius then return true end
    direction:Normalize()
    local fov = player.GetFOV and player:GetFOV() or 90
    local angularRadius = math.deg(math.atan(radius / math.max(distance, 0.001)))
    return player:EyeAngles():Forward():Dot(direction)
        >= math.cos(math.rad(math.Clamp(fov * 0.5 + 20 + angularRadius, 1, 160)))
end

function DISPLAY.Render()
    for _, display in ipairs((DISPLAY.ClientState or {}).Displays or {}) do DISPLAY.RenderDisplay(display) end
end

hook.Add('PostDrawTranslucentRenderables', 'Luasquare3D2D_Render', DISPLAY.Render)
