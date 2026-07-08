if LUASQUARE_3D2D_CORE_LOADED then return end
LUASQUARE_3D2D_CORE_LOADED = true
LUASQUARE_3D2D = LUASQUARE_3D2D or {}
LUASQUARE_3D2D.Displays = LUASQUARE_3D2D.Displays or {}
LUASQUARE_3D2D.Bindings = LUASQUARE_3D2D.Bindings or {}
LUASQUARE_3D2D.EntityCache = LUASQUARE_3D2D.EntityCache or {}
LUASQUARE_3D2D.ClientState = LUASQUARE_3D2D.ClientState or { Displays = {} }
LUASQUARE_3D2D.GraphHistory = LUASQUARE_3D2D.GraphHistory or {}

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

local function normalizeAnchorMode(value)
    if value == nil then return nil end
    value = string.lower(tostring(value)):gsub('[^%w]', '')
    if value == 'center' or value == 'centre' or value == 'middle' or value == 'centered' or value == 'centred' then return 'center' end
    if value == 'topleft' or value == 'lefttop' or value == 'top' or value == 'left' then return 'topleft' end
    return nil
end

local function resolveAnchor(data, axis)
    local key = axis == 'x' and 'anchorX' or 'anchorY'
    if data[key] ~= nil then return tonumber(data[key]) or 0 end

    local mode = normalizeAnchorMode(data.targetOrigin or data.anchor or data.anchorMode or data.origin or data.screenOrigin)
    if not mode and (data.centeredOnTarget or data.centerOnTarget or data.targetCentered or data.centered) then mode = 'center' end
    if mode == 'center' then return 0.5 end
    return 0
end

local lineKeys = {
    'type', 'text', 'label', 'value', 'unit', 'decimals', 'min', 'max', 'fraction',
    'width', 'height', 'font', 'color', 'valueColor', 'barColor', 'backgroundColor',
    'warn', 'warnColor', 'critical', 'criticalColor', 'columns', 'sub', 'columnsGap',
    'id', 'series', 'seconds', 'sampleInterval', 'mode', 'legend', 'grid', 'thresholds',
    'fill', 'fillColor', 'lineColor', 'borderColor'
}

local function normalizeGraphSeries(series, fallbackId, fallbackLabel)
    series = series or {}
    local out = shallowCopyAllowed(series, {
        'id', 'label', 'value', 'unit', 'decimals', 'color', 'lineColor', 'fillColor',
        'min', 'max', 'mode', 'fill'
    })
    out.id = out.id or fallbackId
    out.label = out.label or fallbackLabel or out.id
    out.color = copyColor(out.color, nil)
    out.lineColor = copyColor(out.lineColor, out.color)
    out.fillColor = copyColor(out.fillColor, nil)
    return out
end

local function normalizeGraphSeriesList(line)
    if istable(line.series) then
        local seriesList = {}
        for index, series in ipairs(line.series) do
            table.insert(seriesList, normalizeGraphSeries(series, tostring(index), series.label))
        end
        return seriesList
    end

    return {
        normalizeGraphSeries({
            id = 'value',
            label = line.label or 'VALUE',
            value = line.value,
            unit = line.unit,
            decimals = line.decimals,
            color = line.color or line.lineColor,
            lineColor = line.lineColor,
            fillColor = line.fillColor,
            min = line.min,
            max = line.max,
            mode = line.mode,
            fill = line.fill
        }, 'value', line.label or 'VALUE')
    }
end

local function normalizeGraphThresholds(thresholds)
    local out = {}
    if not istable(thresholds) then return out end
    for _, threshold in ipairs(thresholds) do
        if istable(threshold) then
            table.insert(out, {
                value = tonumber(threshold.value),
                label = threshold.label,
                color = copyColor(threshold.color, Color(255, 210, 70)),
                fillColor = copyColor(threshold.fillColor, nil),
                fill = threshold.fill and true or false
            })
        end
    end

    return out
end

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
        out.lineColor = copyColor(out.lineColor, nil)
        out.fillColor = copyColor(out.fillColor, nil)
        out.borderColor = copyColor(out.borderColor, nil)
        if out.type == 'graph' then
            out.series = normalizeGraphSeriesList(line)
            out.thresholds = normalizeGraphThresholds(line.thresholds)
        end
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
        anchorX = resolveAnchor(display, 'x'),
        anchorY = resolveAnchor(display, 'y'),
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
        renderDistance = tonumber(display.renderDistance),
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
            targetOrigin = data.targetOrigin,
            anchor = data.anchor,
            anchorMode = data.anchorMode,
            origin = data.origin,
            screenOrigin = data.screenOrigin,
            centeredOnTarget = data.centeredOnTarget,
            centerOnTarget = data.centerOnTarget,
            targetCentered = data.targetCentered,
            centered = data.centered,
            visible = data.visible,
            facePlayer = data.facePlayer,
            drawBackground = data.drawBackground,
            drawBorder = data.drawBorder,
            renderDistance = data.renderDistance,
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

    function LUASQUARE_3D2D.GetTime()
        if CurTime then return CurTime() end
        return os.clock()
    end

    function LUASQUARE_3D2D.GetGraphSeriesHistory(displayName, graphId, seriesId)
        local displayHistory = LUASQUARE_3D2D.GraphHistory[displayName]
        if not displayHistory then
            displayHistory = {}
            LUASQUARE_3D2D.GraphHistory[displayName] = displayHistory
        end

        local graphHistory = displayHistory[graphId]
        if not graphHistory then
            graphHistory = {}
            displayHistory[graphId] = graphHistory
        end

        local seriesHistory = graphHistory[seriesId]
        if not seriesHistory then
            seriesHistory = { samples = {}, lastSampleTime = nil }
            graphHistory[seriesId] = seriesHistory
        end

        return seriesHistory
    end

    function LUASQUARE_3D2D.TrimGraphSamples(samples, cutoff)
        while samples[1] and (samples[1].t or 0) < cutoff do
            table.remove(samples, 1)
        end
    end

    function LUASQUARE_3D2D.CopyGraphSamples(samples)
        local out = {}
        for _, sample in ipairs(samples or {}) do
            table.insert(out, {t = sample.t or 0, v = sample.v or 0})
        end
        return out
    end

    function LUASQUARE_3D2D.ApplyGraphHistory(displayName, lines)
        local now = LUASQUARE_3D2D.GetTime()

        for lineIndex, line in ipairs(lines or {}) do
            if line.type == 'graph' then
                local graphId = tostring(line.id or ('line_' .. lineIndex))
                local seconds = math.max(tonumber(line.seconds) or 60, LUASQUARE_3D2D.TickInterval or 0.1)
                local sampleInterval = math.max(tonumber(line.sampleInterval) or LUASQUARE_3D2D.TickInterval or 0.1, 0.01)
                local cutoff = now - seconds
                local autoMin = nil
                local autoMax = nil

                line.id = graphId
                line.seconds = seconds
                line.sampleInterval = sampleInterval
                line.now = now

                for seriesIndex, series in ipairs(line.series or {}) do
                    local seriesId = tostring(series.id or (seriesIndex == 1 and 'value' or seriesIndex))
                    local history = LUASQUARE_3D2D.GetGraphSeriesHistory(displayName, graphId, seriesId)
                    local value = tonumber(series.value)

                    if value ~= nil and (not history.lastSampleTime or now >= history.lastSampleTime + sampleInterval) then
                        table.insert(history.samples, {t = now, v = value})
                        history.lastSampleTime = now
                    end

                    LUASQUARE_3D2D.TrimGraphSamples(history.samples, cutoff)
                    series.id = seriesId
                    series.points = LUASQUARE_3D2D.CopyGraphSamples(history.samples)

                    for _, point in ipairs(series.points) do
                        if autoMin == nil or point.v < autoMin then autoMin = point.v end
                        if autoMax == nil or point.v > autoMax then autoMax = point.v end
                    end
                end

                if line.min == nil or line.max == nil then
                    autoMin = autoMin or 0
                    autoMax = autoMax or 1
                    if autoMin == autoMax then
                        autoMin = autoMin - 1
                        autoMax = autoMax + 1
                    else
                        local padding = (autoMax - autoMin) * 0.08
                        autoMin = autoMin - padding
                        autoMax = autoMax + padding
                    end

                    if line.min == nil then line.min = autoMin end
                    if line.max == nil then line.max = autoMax end
                end
            end
        end
    end

    function LUASQUARE_3D2D.BuildClientState()
        local state = { Displays = {} }

        for name, display in pairs(LUASQUARE_3D2D.Displays) do
            if display.visible ~= false then
                local pos = LUASQUARE_3D2D.ResolvePosition(display)
                if pos then
                    display.resolvedPos = pos
                    display.resolvedAng = LUASQUARE_3D2D.ResolveAngle(display)
                    local sanitized = sanitizeDisplay(name, display)
                    LUASQUARE_3D2D.ApplyGraphHistory(name, sanitized.lines)
                    table.insert(state.Displays, sanitized)
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
    CreateClientConVar('luasquare_3d2d_maxdistance', '2500', true, false)
    CreateClientConVar('luasquare_3d2d_fovcheck', '1', true, false)

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

    local function graphChartHeight(line)
        return tonumber(line.height) or 64
    end

    local function graphTotalHeight(line, lineHeight)
        local total = graphChartHeight(line) + 6
        if line.label or line.text then total = total + lineHeight end
        if line.legend then total = total + lineHeight end
        return total
    end

    local function graphValueFraction(line, value)
        local minValue = tonumber(line.min) or 0
        local maxValue = tonumber(line.max) or 1
        local range = maxValue - minValue
        if range == 0 then return 0 end
        return math.Clamp(((tonumber(value) or minValue) - minValue) / range, 0, 1)
    end

    local function graphPointToScreen(line, point, now, seconds, x, y, width, height)
        local age = math.Clamp((now - (point.t or now)) / math.max(seconds, 0.0001), 0, 1)
        local px = x + width * (1 - age)
        local py = y + height * (1 - graphValueFraction(line, point.v))
        return math.floor(px + 0.5), math.floor(py + 0.5)
    end

    local function drawGraphGrid(line, x, y, width, height)
        if line.grid == false then return end
        surface.SetDrawColor(Color(80, 130, 145, 55))
        for i = 1, 3 do
            local gx = x + math.floor(width * i / 4)
            local gy = y + math.floor(height * i / 4)
            surface.DrawRect(gx, y, 1, height)
            surface.DrawRect(x, gy, width, 1)
        end
    end

    local function drawGraphThresholds(display, line, x, y, width, height)
        for _, threshold in ipairs(line.thresholds or {}) do
            local value = tonumber(threshold.value)
            if value then
                local ty = y + height * (1 - graphValueFraction(line, value))
                local color = threshold.color or Color(255, 210, 70)
                if threshold.fill then
                    surface.SetDrawColor(threshold.fillColor or Color(color.r or 255, color.g or 210, color.b or 70, 22))
                    surface.DrawRect(x, y, width, math.Clamp(ty - y, 0, height))
                end

                surface.SetDrawColor(color)
                surface.DrawRect(x, math.floor(ty + 0.5), width, 1)
                if threshold.label then
                    draw.SimpleText(tostring(threshold.label), 'Luasquare3D2D_Small', x + width - 2, ty - 2, color, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
                end
            end
        end
    end

    local function drawGraphSeries(line, series, x, y, width, height, now, seconds)
        local points = series.points or {}
        if #points <= 0 then return end

        local color = series.lineColor or series.color or line.lineColor or line.color or Color(80, 220, 150)
        local fillColor = series.fillColor or line.fillColor or Color(color.r or 80, color.g or 220, color.b or 150, 38)
        local mode = series.mode or line.mode or 'line'
        local fill = line.fill or series.fill or mode == 'fill'
        local lastX, lastY

        surface.SetDrawColor(fillColor)
        if fill then
            for _, point in ipairs(points) do
                local px, py = graphPointToScreen(line, point, now, seconds, x, y, width, height)
                surface.DrawRect(px, py, 1, math.max(y + height - py, 0))
            end
        end

        surface.SetDrawColor(color)
        for _, point in ipairs(points) do
            local px, py = graphPointToScreen(line, point, now, seconds, x, y, width, height)
            if lastX then
                if mode == 'step' then
                    surface.DrawLine(lastX, lastY, px, lastY)
                    surface.DrawLine(px, lastY, px, py)
                else
                    surface.DrawLine(lastX, lastY, px, py)
                end
            else
                surface.DrawRect(px, py, 2, 2)
            end

            lastX = px
            lastY = py
        end
    end

    local function drawGraphLegend(display, line, x, y, width)
        if not line.legend then return end
        local cursorX = x
        for _, series in ipairs(line.series or {}) do
            local color = series.lineColor or series.color or line.lineColor or line.color or display.barColor
            surface.SetDrawColor(color or Color(80, 220, 150))
            surface.DrawRect(cursorX, y + 5, 10, 3)
            draw.SimpleText(tostring(series.label or series.id or ''), 'Luasquare3D2D_Small', cursorX + 14, y, color or display.textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            cursorX = cursorX + math.min(width, 14 + string.len(tostring(series.label or series.id or '')) * 8 + 12)
            if cursorX > x + width - 24 then break end
        end
    end

    local function drawGraphLine(display, line, x, y, width, lineHeight)
        local chartHeight = graphChartHeight(line)
        local chartY = y
        if line.label or line.text then
            draw.SimpleText(tostring(line.label or line.text), line.font or display.font, x, y, getLineColor(display, line), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            local firstSeries = (line.series or {})[1] or {}
            local currentValue = firstSeries.value or line.value
            if currentValue ~= nil then
                draw.SimpleText(formatValue(currentValue, line.decimals or firstSeries.decimals, line.unit or firstSeries.unit), line.font or display.font, x + width, y, firstSeries.lineColor or firstSeries.color or line.valueColor or display.textColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            end
            chartY = y + lineHeight
        end

        surface.SetDrawColor(line.backgroundColor or display.barBackgroundColor or Color(18, 32, 36, 240))
        surface.DrawRect(x, chartY, width, chartHeight)
        drawGraphGrid(line, x, chartY, width, chartHeight)
        drawGraphThresholds(display, line, x, chartY, width, chartHeight)

        local now = tonumber(line.now) or 0
        local seconds = tonumber(line.seconds) or 60
        for _, series in ipairs(line.series or {}) do
            drawGraphSeries(line, series, x, chartY, width, chartHeight, now, seconds)
        end

        surface.SetDrawColor(line.borderColor or display.borderColor or Color(80, 190, 220, 220))
        surface.DrawOutlinedRect(x, chartY, width, chartHeight, 1)
        draw.SimpleText(formatValue(line.min or 0, line.decimals, line.unit), 'Luasquare3D2D_Small', x + 2, chartY + chartHeight - 1, display.textColor or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        draw.SimpleText(formatValue(line.max or 1, line.decimals, line.unit), 'Luasquare3D2D_Small', x + 2, chartY + 1, display.textColor or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        drawGraphLegend(display, line, x, chartY + chartHeight + 2, width)
    end


    function LUASQUARE_3D2D.RenderLine(display, line, x, y, width, lineHeight)
        if line.type == 'value' then
            drawValueLine(display, line, x, y, width)
        elseif line.type == 'columns' then
            drawColumnsLine(display, line, x, y, width, lineHeight)
        elseif line.type == 'bar' then
            drawBarLine(display, line, x, y, width, lineHeight)
        elseif line.type == 'graph' then
            drawGraphLine(display, line, x, y, width, lineHeight)
        elseif line.type == 'phase' then
            drawPhaseLine(display, line, x, y, width, lineHeight)
        else
            drawTextLine(display, line, x, y, width)
        end
    end

    function LUASQUARE_3D2D.GetRenderAngle(display, ply)
        if display.facePlayer and IsValid(ply or LocalPlayer()) then
            local player = ply or LocalPlayer()
            return Angle(0, player:EyeAngles().y - 90, 90)
        end

        return display.ang or Angle(0, 0, 90)
    end

    function LUASQUARE_3D2D.GetDisplayCenterPos(display, ply)
        if not display.pos then return nil end

        local ang = LUASQUARE_3D2D.GetRenderAngle(display, ply)
        local scale = display.scale or 0.1
        local width = display.width or 256
        local height = display.height or 128
        local centerX = (0.5 - (display.anchorX or 0)) * width * scale
        local centerY = (0.5 - (display.anchorY or 0)) * height * scale

        return display.pos + ang:Right() * centerX - ang:Up() * centerY
    end

    function LUASQUARE_3D2D.GetDisplayCullRadius(display)
        local scale = display.scale or 0.1
        local width = (display.width or 256) * scale
        local height = (display.height or 128) * scale
        return math.sqrt(width * width + height * height) * 0.5
    end

    function LUASQUARE_3D2D.PointPassesDistance(eye, point, radius, maxDistance)
        if not point then return false end
        if maxDistance <= 0 then return true end
        local allowed = maxDistance + math.max(radius or 0, 0)
        return eye:DistToSqr(point) <= allowed * allowed
    end

    function LUASQUARE_3D2D.PointPassesFOV(eye, forward, point, radius, fov)
        if not point then return false end
        local toTarget = point - eye
        local distanceSqr = toTarget:LengthSqr()
        if distanceSqr <= 1 then return true end

        local distance = math.sqrt(distanceSqr)
        if distance <= math.max(radius or 0, 0) then return true end

        toTarget:Normalize()
        local angularRadius = math.deg(math.atan(math.max(radius or 0, 0) / distance))
        local threshold = math.cos(math.rad(math.Clamp(fov * 0.5 + 20 + angularRadius, 1, 160)))
        return forward:Dot(toTarget) >= threshold
    end

    function LUASQUARE_3D2D.ShouldRenderDisplay(display)
        if not display.visible or not display.pos then return false end
        local ply = LocalPlayer()
        if not IsValid(ply) then return true end

        local eye = ply:EyePos()
        local centerPos = LUASQUARE_3D2D.GetDisplayCenterPos(display, ply) or display.pos
        local radius = LUASQUARE_3D2D.GetDisplayCullRadius(display)
        local cullPoints = {
            {pos = centerPos, radius = radius},
            {pos = display.pos, radius = radius * 2}
        }
        local maxDistance = tonumber(display.renderDistance)
        if not maxDistance then
            local cvar = GetConVar('luasquare_3d2d_maxdistance')
            maxDistance = cvar and cvar:GetFloat() or 2500
        end
        local distancePass = false
        for _, point in ipairs(cullPoints) do
            if LUASQUARE_3D2D.PointPassesDistance(eye, point.pos, point.radius, maxDistance) then
                distancePass = true
                break
            end
        end
        if not distancePass then return false end

        local fovCvar = GetConVar('luasquare_3d2d_fovcheck')
        if not fovCvar or not fovCvar:GetBool() then return true end

        local fov = ply.GetFOV and ply:GetFOV() or 90
        local forward = ply:EyeAngles():Forward()
        for _, point in ipairs(cullPoints) do
            if LUASQUARE_3D2D.PointPassesFOV(eye, forward, point.pos, point.radius, fov) then return true end
        end
        return false
    end

    function LUASQUARE_3D2D.RenderDisplay(display)
        if not LUASQUARE_3D2D.ShouldRenderDisplay(display) then return end

        local ang = LUASQUARE_3D2D.GetRenderAngle(display, LocalPlayer())

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
                elseif line.type == 'graph' then
                    y = y + graphTotalHeight(line, lineHeight)
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
--         {
--             type = 'graph',
--             id = 'rpv_pressure',
--             label = 'Pressure Trend',
--             value = RBMK.RPVPressure or 0,
--             min = 0,
--             max = 140,
--             seconds = 60,
--             height = 64,
--             unit = 'bar',
--             color = Color(120, 220, 255),
--             thresholds = {
--                 { value = 70, label = 'MAX', color = Color(255, 210, 70) },
--                 { value = 85, label = 'VENT', color = Color(255, 130, 80) }
--             }
--         },
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
