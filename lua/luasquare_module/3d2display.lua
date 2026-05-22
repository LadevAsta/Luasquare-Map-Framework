if LUASQUARE_3D2D_CORE_LOADED then return end
LUASQUARE_3D2D_CORE_LOADED = true
LUASQUARE_3D2D = LUASQUARE_3D2D or {}
LUASQUARE_3D2D.Displays = LUASQUARE_3D2D.Displays or {}
LUASQUARE_3D2D.Bindings = LUASQUARE_3D2D.Bindings or {}
LUASQUARE_3D2D.EntityCache = LUASQUARE_3D2D.EntityCache or {}
LUASQUARE_3D2D.ClientState = LUASQUARE_3D2D.ClientState or { Displays = {} }

LUASQUARE_3D2D.TickInterval = LUASQUARE_3D2D.TickInterval or 0.1
LUASQUARE_3D2D.NetMessage = 'LUASQUARE_3D2D_State'
LUASQUARE_3D2D.DefaultScale = LUASQUARE_3D2D.DefaultScale or 0.1

local function copyColor(value, fallback)
    if not value then
        if not fallback then return nil end
        return Color(fallback.r or 255, fallback.g or 255, fallback.b or 255, fallback.a or 255)
    end

    fallback = fallback or Color(255, 255, 255)
    return Color(value.r or fallback.r or 255, value.g or fallback.g or 255, value.b or fallback.b or 255, value.a or fallback.a or 255)
end

local function copyVector(value)
    if not value then return nil end
    if value.x == nil or value.y == nil or value.z == nil then return nil end
    return Vector(value.x or 0, value.y or 0, value.z or 0)
end

local function copyAngle(value)
    if not value then return nil end
    if value.p == nil or value.y == nil or value.r == nil then return nil end
    return Angle(value.p or 0, value.y or 0, value.r or 0)
end

local function addAngle(base, offset)
    if not base then return nil end
    if not offset then return base end
    return Angle((base.p or 0) + (offset.p or 0), (base.y or 0) + (offset.y or 0), (base.r or 0) + (offset.r or 0))
end

local function roundPositive(value, fallback)
    value = tonumber(value)
    if not value or value <= 0 then value = fallback or 1 end
    return math.max(math.floor(value + 0.5), 1)
end

local function firstNumber(source, keys)
    for _, key in ipairs(keys) do
        if source[key] ~= nil then
            local value = tonumber(source[key])
            if value and value > 0 then return value end
        end
    end

    return nil
end

local function resolveDisplayMetrics(data)
    local unitWidth = firstNumber(data, {'unitWidth', 'hammerWidth', 'panelWidth', 'worldWidth', 'width'}) or 25.6
    local unitHeight = firstNumber(data, {'unitHeight', 'hammerHeight', 'panelHeight', 'worldHeight', 'height'}) or 12.8
    local desiredScale = firstNumber(data, {'pixelScale', 'scale'}) or LUASQUARE_3D2D.DefaultScale or 0.1
    local resolutionWidth = firstNumber(data, {'resolutionWidth', 'pixelWidth', 'canvasWidth'})
    local resolutionHeight = firstNumber(data, {'resolutionHeight', 'pixelHeight', 'canvasHeight'})
    local adjustedResolution = false

    if data.legacyPixelSize then
        resolutionWidth = roundPositive(data.width, 256)
        resolutionHeight = roundPositive(data.height, 128)
        return {
            unitWidth = resolutionWidth * desiredScale,
            unitHeight = resolutionHeight * desiredScale,
            width = resolutionWidth,
            height = resolutionHeight,
            scale = desiredScale,
            desiredScale = desiredScale
        }
    end

    if resolutionWidth and resolutionHeight then
        local scale = unitWidth / resolutionWidth
        local expectedHeight = roundPositive(unitHeight / scale, resolutionHeight)
        if math.abs(expectedHeight - resolutionHeight) > 1 then
            resolutionHeight = expectedHeight
            adjustedResolution = true
        else
            resolutionHeight = roundPositive(resolutionHeight, 128)
        end

        return {
            unitWidth = unitWidth,
            unitHeight = unitHeight,
            width = roundPositive(resolutionWidth, 256),
            height = resolutionHeight,
            scale = scale,
            desiredScale = desiredScale,
            adjustedResolution = adjustedResolution
        }
    end

    if resolutionWidth then
        local scale = unitWidth / resolutionWidth
        return {
            unitWidth = unitWidth,
            unitHeight = unitHeight,
            width = roundPositive(resolutionWidth, 256),
            height = roundPositive(unitHeight / scale, 128),
            scale = scale,
            desiredScale = desiredScale
        }
    end

    if resolutionHeight then
        local scale = unitHeight / resolutionHeight
        return {
            unitWidth = unitWidth,
            unitHeight = unitHeight,
            width = roundPositive(unitWidth / scale, 256),
            height = roundPositive(resolutionHeight, 128),
            scale = scale,
            desiredScale = desiredScale
        }
    end

    return {
        unitWidth = unitWidth,
        unitHeight = unitHeight,
        width = roundPositive(unitWidth / desiredScale, 256),
        height = roundPositive(unitHeight / desiredScale, 128),
        scale = desiredScale,
        desiredScale = desiredScale
    }
end

local function shallowCopyAllowed(source, keys)
    local out = {}
    for _, key in ipairs(keys) do
        if source[key] ~= nil then out[key] = source[key] end
    end
    return out
end

local lineKeys = {
    'type', 'text', 'label', 'value', 'unit', 'decimals', 'min', 'max', 'fraction',
    'width', 'height', 'font', 'color', 'valueColor', 'barColor', 'backgroundColor',
    'warn', 'warnColor', 'critical', 'criticalColor', 'columns', 'sub', 'columnsGap'
}

local function normalizeLine(line)
    if istable(line) then
        local out = shallowCopyAllowed(line, lineKeys)
        out.type = out.type or (out.label and 'value' or 'text')
        out.color = copyColor(out.color, nil)
        out.valueColor = copyColor(out.valueColor, nil)
        out.barColor = copyColor(out.barColor, nil)
        out.backgroundColor = copyColor(out.backgroundColor, nil)
        out.warnColor = copyColor(out.warnColor, nil)
        out.criticalColor = copyColor(out.criticalColor, nil)
        return out
    end

    return {
        type = 'text',
        text = tostring(line or '')
    }
end

local function normalizeLines(content)
    local lines = {}

    if istable(content) and content.lines then
        content = content.lines
    end

    if istable(content) then
        for _, line in ipairs(content) do
            table.insert(lines, normalizeLine(line))
        end
        return lines
    end

    local text = tostring(content or '')
    for line in string.gmatch(text, '[^\n]+') do
        table.insert(lines, normalizeLine(line))
    end
    if #lines <= 0 then table.insert(lines, normalizeLine('')) end
    return lines
end

local function sanitizeDisplay(name, display)
    local out = {
        name = name,
        title = display.title,
        scale = tonumber(display.scale) or LUASQUARE_3D2D.DefaultScale or 0.1,
        unitWidth = tonumber(display.unitWidth) or 25.6,
        unitHeight = tonumber(display.unitHeight) or 12.8,
        width = tonumber(display.width) or 256,
        height = tonumber(display.height) or 128,
        padding = tonumber(display.padding) or 8,
        lineHeight = tonumber(display.lineHeight) or 16,
        titleHeight = tonumber(display.titleHeight) or 28,
        anchorX = tonumber(display.anchorX) or 0,
        anchorY = tonumber(display.anchorY) or 0,
        visible = display.visible ~= false,
        facePlayer = display.facePlayer and true or false,
        drawBackground = display.drawBackground ~= false,
        drawBorder = display.drawBorder ~= false,
        font = display.font or 'Luasquare3D2D_Line',
        titleFont = display.titleFont or 'Luasquare3D2D_Title',
        textColor = copyColor(display.textColor, Color(220, 245, 255)),
        titleColor = copyColor(display.titleColor, Color(255, 255, 255)),
        backgroundColor = copyColor(display.backgroundColor, Color(4, 12, 16, 220)),
        borderColor = copyColor(display.borderColor, Color(80, 190, 220, 220)),
        barColor = copyColor(display.barColor, Color(70, 220, 160)),
        barBackgroundColor = copyColor(display.barBackgroundColor, Color(18, 32, 36, 240)),
        pos = copyVector(display.resolvedPos or display.pos),
        ang = copyAngle(display.resolvedAng or display.ang or display.angle),
        lines = normalizeLines(display.content)
    }

    return out
end

-- =========================================
-- SERVER API
-- =========================================
if SERVER then
    AddCSLuaFile('luasquare_module/3d2display.lua')
    util.AddNetworkString(LUASQUARE_3D2D.NetMessage)

    function LUASQUARE_3D2D.GetEnt(name)
        if not name then return nil end
        local cached = LUASQUARE_3D2D.EntityCache[name]
        if IsValid(cached) then return cached end
        local ent = ents.FindByName(name)[1]
        if IsValid(ent) then LUASQUARE_3D2D.EntityCache[name] = ent end
        return ent
    end

    function LUASQUARE_3D2D.RegisterDisplay(name, data)
        if not data then
            print('[LUASQUARE_3D2D] Missing data for display: ' .. tostring(name))
            return
        end

        local metrics = resolveDisplayMetrics(data)
        if metrics.adjustedResolution then
            print('[LUASQUARE_3D2D] Adjusted resolution height for ' .. tostring(name) .. ' to preserve Hammer-unit panel size.')
        end

        LUASQUARE_3D2D.Displays[name] = {
            entity = data.entity or data.target or data.infoTarget,
            posTarget = data.posTarget or data.positionTarget,
            angleTarget = data.angleTarget or data.angTarget,
            useTargetAngle = data.useTargetAngle or data.targetAngle or ((data.target or data.infoTarget) and true or false),
            pos = data.pos,
            offset = data.offset or Vector(0, 0, 0),
            ang = data.ang or data.angle,
            angleOffset = data.angleOffset or data.angOffset or Angle(0, 0, 0),
            title = data.title,
            content = data.content or data.lines or '',
            scale = metrics.scale,
            desiredScale = metrics.desiredScale,
            unitWidth = metrics.unitWidth,
            unitHeight = metrics.unitHeight,
            width = metrics.width,
            height = metrics.height,
            padding = data.padding,
            lineHeight = data.lineHeight,
            titleHeight = data.titleHeight,
            anchorX = data.anchorX,
            anchorY = data.anchorY,
            visible = data.visible,
            facePlayer = data.facePlayer,
            drawBackground = data.drawBackground,
            drawBorder = data.drawBorder,
            font = data.font,
            titleFont = data.titleFont,
            textColor = data.textColor,
            titleColor = data.titleColor,
            backgroundColor = data.backgroundColor,
            borderColor = data.borderColor,
            barColor = data.barColor,
            barBackgroundColor = data.barBackgroundColor
        }
    end

    function LUASQUARE_3D2D.SetDisplay(name, content)
        local display = LUASQUARE_3D2D.Displays[name]
        if not display then
            print('[LUASQUARE_3D2D] Unknown display: ' .. tostring(name))
            return
        end

        display.content = content or ''
    end

    function LUASQUARE_3D2D.BindDisplay(name, getter)
        LUASQUARE_3D2D.Bindings[name] = getter
    end

    function LUASQUARE_3D2D.ResolvePosition(display)
        local offset = display.offset or Vector(0, 0, 0)
        local direct = copyVector(display.pos)
        if direct then return direct + offset end

        local targetName = display.posTarget or (isstring and isstring(display.pos) and display.pos) or display.entity
        if not targetName then return nil end

        local ent = LUASQUARE_3D2D.GetEnt(targetName)
        if IsValid(ent) then return ent:GetPos() + offset end
        return nil
    end

    function LUASQUARE_3D2D.ResolveAngle(display)
        local offset = display.angleOffset or Angle(0, 0, 0)
        local direct = copyAngle(display.ang)
        if direct then return addAngle(direct, offset) end

        local targetName = display.angleTarget or (isstring and isstring(display.ang) and display.ang)
        if not targetName and display.useTargetAngle then
            targetName = display.posTarget or (isstring and isstring(display.pos) and display.pos) or display.entity
        end

        if not targetName then return nil end
        local ent = LUASQUARE_3D2D.GetEnt(targetName)
        if IsValid(ent) then return addAngle(ent:GetAngles(), offset) end
        return nil
    end

    function LUASQUARE_3D2D.BuildClientState()
        local state = { Displays = {} }

        for name, display in pairs(LUASQUARE_3D2D.Displays) do
            if display.visible ~= false then
                local pos = LUASQUARE_3D2D.ResolvePosition(display)
                if pos then
                    display.resolvedPos = pos
                    display.resolvedAng = LUASQUARE_3D2D.ResolveAngle(display)
                    table.insert(state.Displays, sanitizeDisplay(name, display))
                    display.resolvedPos = nil
                    display.resolvedAng = nil
                elseif not display.warnedMissingPosition then
                    print('[LUASQUARE_3D2D] Missing position/entity for display: ' .. tostring(name))
                    display.warnedMissingPosition = true
                end
            end
        end

        LUASQUARE_3D2D.ClientState = state
        return state
    end

    function LUASQUARE_3D2D.Broadcast()
        net.Start(LUASQUARE_3D2D.NetMessage)
        net.WriteTable(LUASQUARE_3D2D.ClientState or { Displays = {} })
        net.Broadcast()
    end

    function LUASQUARE_3D2D.UpdateAll()
        for displayName, getter in pairs(LUASQUARE_3D2D.Bindings) do
            local ok, value = pcall(getter)
            if ok then
                LUASQUARE_3D2D.SetDisplay(displayName, value)
            else
                print('[LUASQUARE_3D2D] Getter failed for ' .. tostring(displayName))
                print(value)
            end
        end

        LUASQUARE_3D2D.BuildClientState()
        LUASQUARE_3D2D.Broadcast()
    end

    function LUASQUARE_3D2D.Start()
        if timer.Exists('LUASQUARE_3D2D_UpdateTimer') then timer.Remove('LUASQUARE_3D2D_UpdateTimer') end
        timer.Create('LUASQUARE_3D2D_UpdateTimer', LUASQUARE_3D2D.TickInterval, 0, function() LUASQUARE_3D2D.UpdateAll() end)
        print('[LUASQUARE_3D2D] Started')
    end

    function LUASQUARE_3D2D.Stop()
        if timer.Exists('LUASQUARE_3D2D_UpdateTimer') then timer.Remove('LUASQUARE_3D2D_UpdateTimer') end
        print('[LUASQUARE_3D2D] Stopped')
    end

    print('[LUASQUARE_3D2D] Loaded server')
end

-- =========================================
-- CLIENT RENDERER
-- =========================================
if CLIENT then
    surface.CreateFont('Luasquare3D2D_Title', {
        font = 'Roboto',
        size = 24,
        weight = 700,
        antialias = true
    })

    surface.CreateFont('Luasquare3D2D_Line', {
        font = 'Roboto Mono',
        size = 18,
        weight = 500,
        antialias = true
    })

    surface.CreateFont('Luasquare3D2D_Small', {
        font = 'Roboto Mono',
        size = 14,
        weight = 500,
        antialias = true
    })

    local function formatValue(value, decimals, unit)
        if isnumber(value) then
            decimals = tonumber(decimals)
            if decimals then
                value = string.format('%.' .. math.Clamp(decimals, 0, 6) .. 'f', value)
            else
                value = tostring(math.floor(value))
            end
        else
            value = tostring(value or '')
        end

        if unit and unit ~= '' then value = value .. ' ' .. tostring(unit) end
        return value
    end

    local function getLineColor(display, line)
        if line.critical then return line.criticalColor or Color(255, 80, 80) end
        if line.warn then return line.warnColor or Color(255, 210, 70) end
        return line.color or display.textColor or color_white
    end

    local function lineFraction(line)
        if line.fraction ~= nil then return math.Clamp(tonumber(line.fraction) or 0, 0, 1) end
        local minValue = tonumber(line.min) or 0
        local maxValue = tonumber(line.max) or 1
        local range = maxValue - minValue
        if range == 0 then return 0 end
        return math.Clamp(((tonumber(line.value) or 0) - minValue) / range, 0, 1)
    end

    local function drawTextLine(display, line, x, y, width)
        draw.SimpleText(line.text or '', line.font or display.font, x, y, getLineColor(display, line), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    local function drawValueLine(display, line, x, y, width)
        local color = getLineColor(display, line)
        local valueColor = line.valueColor or color
        local valueText = formatValue(line.value, line.decimals, line.unit)
        local font = line.font or display.font
        draw.SimpleText(tostring(line.label or ''), font, x, y, color, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(valueText, font, x + width, y, valueColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end

    local function drawBarLine(display, line, x, y, width, lineHeight)
        local label = line.label or line.text
        if label then draw.SimpleText(tostring(label), line.font or display.font, x, y, getLineColor(display, line), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP) end

        local barY = y + (label and math.floor(lineHeight * 0.9) or 1)
        local barHeight = tonumber(line.height) or 8
        local fraction = lineFraction(line)
        surface.SetDrawColor(line.backgroundColor or display.barBackgroundColor or Color(20, 20, 20, 230))
        surface.DrawRect(x, barY, width, barHeight)
        surface.SetDrawColor(line.barColor or display.barColor or Color(80, 220, 150))
        surface.DrawRect(x, barY, math.floor(width * fraction), barHeight)
    end

    local function drawPhaseLine(display, line, x, y, width, lineHeight)
        local label = line.label or line.text or 'PHASE'
        draw.SimpleText(tostring(label), line.font or display.font, x, y, getLineColor(display, line), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local barY = y + math.floor(lineHeight * 0.9)
        local barHeight = tonumber(line.height) or 10
        local value = tonumber(line.value) or 0
        local minValue = tonumber(line.min) or -180
        local maxValue = tonumber(line.max) or 180
        local range = maxValue - minValue
        local fraction = range ~= 0 and math.Clamp((value - minValue) / range, 0, 1) or 0.5
        local markerX = x + math.floor(width * fraction)
        local centerX = x + math.floor(width * 0.5)

        surface.SetDrawColor(line.backgroundColor or display.barBackgroundColor or Color(20, 20, 20, 230))
        surface.DrawRect(x, barY, width, barHeight)
        surface.SetDrawColor(display.borderColor or Color(100, 200, 220))
        surface.DrawRect(centerX - 1, barY - 2, 2, barHeight + 4)
        surface.SetDrawColor(line.barColor or display.barColor or Color(80, 220, 150))
        surface.DrawRect(markerX - 2, barY - 3, 4, barHeight + 6)
        draw.SimpleText(formatValue(value, line.decimals, line.unit), line.font or display.font, x + width, y, line.valueColor or display.textColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end
    local function drawColumnsLine(display, line, x, y, width, lineHeight)
        local columns = line.columns or {}
        local count = #columns
        if count <= 0 then return end

        local gap = tonumber(line.columnsGap) or 6
        local columnWidth = math.floor((width - gap * (count - 1)) / count)
        local columnHeight = tonumber(line.height) or math.max(lineHeight * 3, 56)

        for index, column in ipairs(columns) do
            local columnX = x + (index - 1) * (columnWidth + gap)
            surface.SetDrawColor(column.backgroundColor or Color(8, 20, 24, 180))
            surface.DrawRect(columnX, y, columnWidth, columnHeight)
            surface.SetDrawColor(column.borderColor or display.borderColor or Color(80, 190, 220, 220))
            surface.DrawOutlinedRect(columnX, y, columnWidth, columnHeight, 1)

            draw.SimpleText(tostring(column.label or ''), display.font, columnX + 6, y + 5, column.color or display.textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(tostring(column.value or ''), display.titleFont, columnX + columnWidth * 0.5, y + 24, column.valueColor or column.color or display.titleColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            draw.SimpleText(tostring(column.sub or ''), 'Luasquare3D2D_Small', columnX + columnWidth * 0.5, y + columnHeight - 18, column.color or display.textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end


    function LUASQUARE_3D2D.RenderLine(display, line, x, y, width, lineHeight)
        if line.type == 'value' then
            drawValueLine(display, line, x, y, width)
        elseif line.type == 'columns' then
            drawColumnsLine(display, line, x, y, width, lineHeight)
        elseif line.type == 'bar' then
            drawBarLine(display, line, x, y, width, lineHeight)
        elseif line.type == 'phase' then
            drawPhaseLine(display, line, x, y, width, lineHeight)
        else
            drawTextLine(display, line, x, y, width)
        end
    end

    function LUASQUARE_3D2D.RenderDisplay(display)
        if not display.visible or not display.pos then return end

        local ang = display.ang or Angle(0, 0, 90)
        if display.facePlayer and IsValid(LocalPlayer()) then
            ang = Angle(0, LocalPlayer():EyeAngles().y - 90, 90)
        end

        local width = display.width or 256
        local height = display.height or 128
        local padding = display.padding or 8
        local lineHeight = display.lineHeight or 16
        local titleHeight = display.titleHeight or 28
        local originX = -width * (display.anchorX or 0)
        local originY = -height * (display.anchorY or 0)
        local x = originX + padding
        local y = originY + padding
        local innerWidth = width - padding * 2

        cam.Start3D2D(display.pos, ang, display.scale or 0.1)
            if display.drawBackground then
                surface.SetDrawColor(display.backgroundColor or Color(4, 12, 16, 220))
                surface.DrawRect(originX, originY, width, height)
            end
            if display.drawBorder then
                surface.SetDrawColor(display.borderColor or Color(80, 190, 220, 220))
                surface.DrawOutlinedRect(originX, originY, width, height, 1)
            end

            if display.title and display.title ~= '' then
                draw.SimpleText(display.title, display.titleFont, x, y, display.titleColor or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                y = y + titleHeight
            end

            for _, line in ipairs(display.lines or {}) do
                if y <= originY + height - padding then
                    LUASQUARE_3D2D.RenderLine(display, line, x, y, innerWidth, lineHeight)
                end
                if line.type == 'columns' then
                    y = y + (tonumber(line.height) or math.max(lineHeight * 3, 56)) + 6
                elseif line.type == 'bar' or line.type == 'phase' then
                    y = y + lineHeight + (tonumber(line.height) or 8) + 4
                else
                    y = y + lineHeight
                end
            end
        cam.End3D2D()
    end

    function LUASQUARE_3D2D.Render()
        local state = LUASQUARE_3D2D.ClientState or { Displays = {} }
        for _, display in ipairs(state.Displays or {}) do
            LUASQUARE_3D2D.RenderDisplay(display)
        end
    end

    net.Receive(LUASQUARE_3D2D.NetMessage, function()
        LUASQUARE_3D2D.ClientState = net.ReadTable() or { Displays = {} }
    end)

    hook.Add('PostDrawTranslucentRenderables', 'Luasquare3D2D_Render', function()
        LUASQUARE_3D2D.Render()
    end)

    print('[LUASQUARE_3D2D] Loaded client')
end

-- =========================================
-- EXAMPLES
-- =========================================
-- include('luasquare_module/3d2display.lua')
--
-- LUASQUARE_3D2D.RegisterDisplay('rpv_status', {
--     pos = Vector(0, 0, 128),
--     ang = Angle(0, 90, 90),
--     -- width/height are Hammer units. scale is Hammer units per canvas pixel.
--     -- Use resolutionWidth/resolutionHeight when you need to override the derived pixel canvas.
--     scale = 0.1,
--     width = 32,
--     height = 15,
--     title = 'RPV STATUS'
-- })
-- LUASQUARE_3D2D.BindDisplay('rpv_status', function()
--     return {
--         { type = 'value', label = 'Power', value = RBMK.LastThermalMW or 0, decimals = 0, unit = 'MWt' },
--         { type = 'value', label = 'Pressure', value = RBMK.RPVPressure or 0, decimals = 1, unit = 'bar' },
--         { type = 'bar', label = 'Water', value = RBMK.Water or 0, min = 0, max = RBMK.MaxWater or 1 },
--         { type = 'value', label = 'Steam T', value = RBMK.SteamTemperature or 0, decimals = 1, unit = 'C' }
--     }
-- end)
--
-- LUASQUARE_3D2D.RegisterDisplay('sync_status', {
--     pos = Vector(0, 64, 128),
--     ang = Angle(0, 90, 90),
--     width = 34,
--     height = 17,
--     title = 'GENERATOR SYNC'
-- })
-- LUASQUARE_3D2D.BindDisplay('sync_status', function()
--     return {
--         { type = 'value', label = 'RPM', value = 1798.5, decimals = 1 },
--         { type = 'value', label = 'Grid Hz', value = 60.0, decimals = 2, unit = 'Hz' },
--         { type = 'phase', label = 'Phase', value = -12.5, min = -180, max = 180, decimals = 1, unit = 'deg' },
--         { type = 'bar', label = 'Voltage Match', fraction = 0.94 }
--     }
-- end)
--
-- LUASQUARE_3D2D.Start()
