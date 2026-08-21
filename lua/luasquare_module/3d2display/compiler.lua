LUASQUARE_3D2D = LUASQUARE_3D2D or {}

local DISPLAY = LUASQUARE_3D2D
local allowedLineTypes = {
    text = true,
    value = true,
    columns = true,
    bar = true,
    graph = true,
    phase = true
}
local allowedElementTypes = {
    linepanel = 'line_panel',
    line_panel = 'line_panel',
    material = 'material',
    solidrectangle = 'solid_rectangle',
    solid_rectangle = 'solid_rectangle',
    annunciator = 'annunciator'
}
local allowedConditionOps = {
    eq = true, ne = true, gt = true, gte = true,
    lt = true, lte = true, truthy = true
}
local allowedVariantFields = {
    visible = true,
    material = true,
    backgroundMaterial = true,
    frames = true,
    frameSeconds = true,
    loop = true,
    animationEpoch = true,
    flashSeconds = true,
    flashMinimum = true,
    tint = true,
    color = true,
    textColor = true,
    titleColor = true,
    valueColor = true,
    backgroundColor = true,
    borderColor = true,
    barColor = true,
    barBackgroundColor = true,
    fillColor = true,
    warnColor = true,
    criticalColor = true,
    warn = true,
    critical = true
}

local function addDiagnostic(diagnostics, level, path, message)
    table.insert(diagnostics, {
        level = level,
        path = path or '$',
        message = tostring(message)
    })
end

local function number(value, fallback, minimum, maximum)
    value = tonumber(value)
    if value == nil then value = fallback end
    if value == nil then return nil end
    if minimum and value < minimum then value = minimum end
    if maximum and value > maximum then value = maximum end
    return value
end

local function isArray(value)
    if type(value) ~= 'table' then return false end
    local maximum = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key ~= math.floor(key) then return false end
        maximum = math.max(maximum, key)
    end
    for index = 1, maximum do if value[index] == nil then return false end end
    return true
end

local function safeMaterialPath(path)
    if path == nil or path == '' then return nil end
    path = string.lower(string.gsub(tostring(path), '\\', '/'))
    path = string.gsub(path, '^materials/', '')
    path = string.gsub(path, '%.vmt$', '')
    if string.find(path, '..', 1, true) or string.find(path, '://', 1, true) then return nil end
    if string.find(path, '[^%w_/%.-]') then return nil end
    if string.sub(path, 1, 1) == '/' then return nil end
    return path
end

local function normalizeMaterialPath(value, path, diagnostics)
    if DISPLAY.IsBinding(value) then
        addDiagnostic(diagnostics, 'error', path, 'material paths must be source literals')
        return nil
    end
    local material = safeMaterialPath(value)
    if not material then addDiagnostic(diagnostics, 'error', path, 'unsafe material path') end
    return material
end

local function registryHas(registry, id)
    return registry and registry[id] ~= nil
end

local function knownProvider(id)
    return registryHas(DISPLAY.DataProviders, id)
        or registryHas(DISPLAY.KnownProviders, id)
end

local function knownAction(id)
    return registryHas(DISPLAY.Actions, id)
        or registryHas(DISPLAY.KnownActions, id)
end

local function validateBinding(binding, path, diagnostics)
    if type(binding.provider) ~= 'string' or binding.provider == '' then
        addDiagnostic(diagnostics, 'error', path, 'binding provider must be a non-empty string')
        return
    end
    if not knownProvider(binding.provider) then
        addDiagnostic(diagnostics, 'error', path, 'unknown data provider: ' .. binding.provider)
    end
    if binding.path ~= nil and type(binding.path) ~= 'string' then
        addDiagnostic(diagnostics, 'error', path .. '.path', 'binding path must be a string')
    end
end

local function validateCondition(condition, path, diagnostics)
    if condition == nil or type(condition) == 'boolean' then return end
    if type(condition) ~= 'table' then
        addDiagnostic(diagnostics, 'error', path, 'condition must be an object or boolean')
        return
    end
    if condition.all or condition.any then
        local children = condition.all or condition.any
        if not isArray(children) or #children == 0 then
            addDiagnostic(diagnostics, 'error', path, 'all/any must contain conditions')
            return
        end
        for index, child in ipairs(children) do
            validateCondition(child, path .. '[' .. index .. ']', diagnostics)
        end
        return
    end
    if condition['not'] ~= nil then
        validateCondition(condition['not'], path .. '.not', diagnostics)
        return
    end
    validateBinding(condition, path, diagnostics)
    local operation = string.lower(tostring(condition.op or 'truthy'))
    if not allowedConditionOps[operation] then
        addDiagnostic(diagnostics, 'error', path .. '.op', 'unsupported condition operator: ' .. operation)
    end
end

local function walkDynamic(value, path, diagnostics, seen)
    if type(value) ~= 'table' then return end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    if DISPLAY.IsBinding(value) then
        validateBinding(value, path, diagnostics)
        return
    end
    for key, child in pairs(value) do
        if key == 'visibleWhen' or key == 'when' then
            validateCondition(child, path .. '.' .. tostring(key), diagnostics)
        else
            walkDynamic(child, path .. '.' .. tostring(key), diagnostics, seen)
        end
    end
end

local forbiddenSourceFields = {
    lua = true,
    code = true,
    command = true,
    consolecommand = true,
    concommand = true,
    runstring = true
}

local function rejectExecutableFields(value, path, diagnostics, seen)
    if type(value) ~= 'table' then return end
    seen = seen or {}
    if seen[value] then return end
    seen[value] = true
    for key, child in pairs(value) do
        local name = type(key) == 'string' and string.lower(key) or nil
        if name and forbiddenSourceFields[name] then
            addDiagnostic(diagnostics, 'error', path .. '.' .. key, 'executable fields are prohibited')
        else
            rejectExecutableFields(child, path .. '.' .. tostring(key), diagnostics, seen)
        end
    end
end

local function normalizeMaterialArray(frames, path, diagnostics)
    if not isArray(frames) then
        addDiagnostic(diagnostics, 'error', path, 'frames must be an array')
        return frames
    end
    for frameIndex, frame in ipairs(frames) do
        if DISPLAY.IsBinding(frame) then
            addDiagnostic(diagnostics, 'error', path .. '[' .. frameIndex .. ']', 'material paths must be source literals')
        else
            local material = safeMaterialPath(frame)
            if not material then
                addDiagnostic(diagnostics, 'error', path .. '[' .. frameIndex .. ']', 'unsafe material path')
            end
            frames[frameIndex] = material
        end
    end
    return frames
end

local function normalizeVariants(source, path, diagnostics)
    local variants = {}
    if source ~= nil and not isArray(source) then
        addDiagnostic(diagnostics, 'error', path, 'variants must be an array')
        return variants
    end
    for index, variant in ipairs(source or {}) do
        if type(variant) ~= 'table' or type(variant.set) ~= 'table' then
            addDiagnostic(diagnostics, 'error', path .. '[' .. index .. ']', 'variant requires when and set objects')
        else
            validateCondition(variant.when, path .. '[' .. index .. '].when', diagnostics)
            walkDynamic(variant.set, path .. '[' .. index .. '].set', diagnostics)
            local normalized = DISPLAY.DeepCopy(variant)
            for field in pairs(normalized.set) do
                if not allowedVariantFields[field] then
                    addDiagnostic(
                        diagnostics,
                        'error',
                        path .. '[' .. index .. '].set.' .. tostring(field),
                        'variant cannot override this field'
                    )
                end
            end
            for _, field in ipairs({'material', 'backgroundMaterial'}) do
                if normalized.set[field] ~= nil then
                    normalized.set[field] = normalizeMaterialPath(
                        normalized.set[field],
                        path .. '[' .. index .. '].set.' .. field,
                        diagnostics
                    )
                end
            end
            if normalized.set.frames ~= nil then
                if DISPLAY.IsBinding(normalized.set.frames) then
                    addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].set.frames', 'material frames must be source literals')
                else
                    normalized.set.frames = normalizeMaterialArray(
                        normalized.set.frames,
                        path .. '[' .. index .. '].set.frames',
                        diagnostics
                    )
                end
            end
            table.insert(variants, normalized)
        end
    end
    return variants
end

local function normalizeLine(source, path, diagnostics)
    if type(source) == 'string' then source = {type = 'text', text = source} end
    if type(source) ~= 'table' then
        addDiagnostic(diagnostics, 'error', path, 'line must be an object or string')
        return {type = 'text', text = ''}
    end
    local line = DISPLAY.DeepCopy(source)
    line.type = string.lower(tostring(line.type or (line.label and 'value' or 'text')))
    if not allowedLineTypes[line.type] then
        addDiagnostic(diagnostics, 'error', path .. '.type', 'unknown line type: ' .. line.type)
    end
    line.id = DISPLAY.NormalizeId(line.id or string.gsub(path, '[^%w]+', '_'))
    line.variants = normalizeVariants(line.variants, path .. '.variants', diagnostics)
    if line.visibleWhen ~= nil then validateCondition(line.visibleWhen, path .. '.visibleWhen', diagnostics) end
    walkDynamic(line, path, diagnostics)
    return line
end

local function normalizeLines(lines, path, diagnostics)
    local out = {}
    local ids = {}
    if not isArray(lines) then
        addDiagnostic(diagnostics, 'error', path, 'lines must be an array')
        return out
    end
    for index, line in ipairs(lines) do
        local normalized = normalizeLine(line, path .. '[' .. index .. ']', diagnostics)
        if ids[normalized.id] then
            addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].id', 'duplicate line id: ' .. normalized.id)
        end
        ids[normalized.id] = true
        table.insert(out, normalized)
    end
    return out
end

local function normalizeMaterialFields(element, path, diagnostics)
    for _, field in ipairs({'material', 'backgroundMaterial'}) do
        local value = element[field]
        if value then
            element[field] = normalizeMaterialPath(value, path .. '.' .. field, diagnostics)
        end
    end
    if element.frames ~= nil then
        if not isArray(element.frames) then
            addDiagnostic(diagnostics, 'error', path .. '.frames', 'frames must be an array')
            element.frames = {}
        else
            normalizeMaterialArray(element.frames, path .. '.frames', diagnostics)
        end
    end
    element.frameSeconds = number(element.frameSeconds, nil, 0.02, 60)
    if not element.frameSeconds and tonumber(element.fps) then
        element.frameSeconds = 1 / number(element.fps, 1, 0.01, 50)
    end
    element.flashSeconds = number(element.flashSeconds, nil, 0.02, 60)
end

local function normalizeElement(source, path, order, diagnostics)
    if type(source) ~= 'table' then
        addDiagnostic(diagnostics, 'error', path, 'element must be an object')
        return nil
    end
    local element = DISPLAY.DeepCopy(source)
    local elementType = string.lower(tostring(element.type or ''))
    element.type = allowedElementTypes[elementType]
    if not element.type then
        addDiagnostic(diagnostics, 'error', path .. '.type', 'unknown element type: ' .. elementType)
        return nil
    end
    element.id = DISPLAY.NormalizeId(element.id or ('element_' .. order))
    element.x = number(element.x, 0, -100000, 100000)
    element.y = number(element.y, 0, -100000, 100000)
    element.width = number(element.width or element.w, 64, 1, 100000)
    element.height = number(element.height or element.h, 32, 1, 100000)
    element.z = math.floor(number(element.z, 0, -10000, 10000))
    element.order = order
    element.variants = normalizeVariants(element.variants, path .. '.variants', diagnostics)
    if element.visibleWhen ~= nil then validateCondition(element.visibleWhen, path .. '.visibleWhen', diagnostics) end
    if element.action then
        element.action = DISPLAY.NormalizeId(element.action)
        if not knownAction(element.action) then
            addDiagnostic(diagnostics, 'error', path .. '.action', 'unknown action: ' .. tostring(element.action))
        end
    end
    if element.type == 'line_panel' then
        element.lines = normalizeLines(element.lines or {}, path .. '.lines', diagnostics)
        normalizeMaterialFields(element, path, diagnostics)
    elseif element.type == 'material' then
        normalizeMaterialFields(element, path, diagnostics)
        if not element.material and #(element.frames or {}) == 0 then
            addDiagnostic(diagnostics, 'error', path, 'material element requires material or frames')
        end
    elseif element.type == 'annunciator' then
        element.alarm = DISPLAY.NormalizeId(element.alarm)
        if not element.alarm then
            addDiagnostic(diagnostics, 'error', path .. '.alarm', 'annunciator requires an alarm id')
        end
    end
    walkDynamic(element, path, diagnostics)
    return element
end

local function normalizePage(source, path, index, diagnostics)
    if type(source) ~= 'table' then
        addDiagnostic(diagnostics, 'error', path, 'page must be an object')
        return nil
    end
    local page = {
        id = DISPLAY.NormalizeId(source.id or ('page_' .. index)),
        label = tostring(source.label or source.title or source.id or ('Page ' .. index)),
        elements = {}
    }
    local ids = {}
    if source.elements ~= nil and not isArray(source.elements) then
        addDiagnostic(diagnostics, 'error', path .. '.elements', 'elements must be an array')
    end
    for elementIndex, elementSource in ipairs(source.elements or {}) do
        local element = normalizeElement(
            elementSource,
            path .. '.elements[' .. elementIndex .. ']',
            elementIndex,
            diagnostics
        )
        if element then
            if ids[element.id] then
                addDiagnostic(diagnostics, 'error', path, 'duplicate element id: ' .. element.id)
            else
                ids[element.id] = true
                table.insert(page.elements, element)
            end
        end
    end
    table.sort(page.elements, function(a, b)
        if a.z == b.z then return a.order < b.order end
        return a.z < b.z
    end)
    return page
end

local function resolveMetrics(source, diagnostics)
    for _, field in ipairs({'scale', 'pixelScale', 'unitWidth', 'hammerWidth', 'unitHeight', 'hammerHeight', 'width', 'height'}) do
        if source[field] ~= nil and (not tonumber(source[field]) or tonumber(source[field]) <= 0) then
            addDiagnostic(diagnostics, 'error', '$.' .. field, field .. ' must be a positive number')
        end
    end
    local parsed = DISPLAY.ParseTargetMetrics(source.target or source.entity or source.infoTarget) or {}
    local scale = number(source.scale or source.pixelScale, DISPLAY.DefaultScale or 0.1, 0.001, 100)
    local unitWidth = number(source.unitWidth or source.hammerWidth, parsed.unitWidth, 0.01, 100000)
    local unitHeight = number(source.unitHeight or source.hammerHeight, parsed.unitHeight, 0.01, 100000)
    local width = number(source.width, unitWidth and math.floor(unitWidth / scale + 0.5) or nil, 1, 32768)
    local height = number(source.height, unitHeight and math.floor(unitHeight / scale + 0.5) or nil, 1, 32768)
    if not width or not height then
        addDiagnostic(diagnostics, 'error', '$.metrics', 'display dimensions are missing and targetname has no DISPLAY dimensions')
        width = width or 256
        height = height or 128
    end
    unitWidth = unitWidth or width * scale
    unitHeight = unitHeight or height * scale
    return {
        scale = scale,
        width = math.floor(width + 0.5),
        height = math.floor(height + 0.5),
        unitWidth = unitWidth,
        unitHeight = unitHeight
    }
end

local function resolveAnchor(source)
    if type(source.anchor) == 'table' then
        return number(source.anchor.x or source.anchor[1], 0, -10, 10),
            number(source.anchor.y or source.anchor[2], 0, -10, 10)
    end
    local anchors = {
        top_left = {0, 0}, top_center = {0.5, 0}, top_right = {1, 0},
        center_left = {0, 0.5}, center = {0.5, 0.5}, center_right = {1, 0.5},
        bottom_left = {0, 1}, bottom_center = {0.5, 1}, bottom_right = {1, 1}
    }
    local preset = anchors[string.lower(tostring(source.anchor or 'top_left'))] or anchors.top_left
    return preset[1], preset[2]
end

local function compileDisplay(source, origin, diagnostics)
    local id = DISPLAY.NormalizeId(source.id)
    if not id then addDiagnostic(diagnostics, 'error', '$.id', 'display requires a stable id') end
    local mode = string.lower(tostring(source.buildMode or source.mode or 'simple'))
    if mode ~= 'simple' and mode ~= 'complex' then
        addDiagnostic(diagnostics, 'error', '$.buildMode', 'buildMode must be simple or complex')
        mode = 'simple'
    end
    local metrics = resolveMetrics(source, diagnostics)
    local anchorX, anchorY = resolveAnchor(source)
    local compiled = {
        kind = 'display',
        _compiled = true,
        schema = DISPLAY.Schema,
        id = id,
        origin = origin,
        buildMode = mode,
        target = source.target or source.entity or source.infoTarget,
        posTarget = source.posTarget,
        angleTarget = source.angleTarget,
        useTargetAngle = source.useTargetAngle ~= false,
        pos = DISPLAY.DeepCopy(source.pos),
        ang = DISPLAY.DeepCopy(source.ang or source.angle),
        offset = DISPLAY.DeepCopy(source.offset),
        angleOffset = DISPLAY.DeepCopy(source.angleOffset),
        surfaceOffset = number(source.surfaceOffset, DISPLAY.DefaultSurfaceOffset or 0.05, -100, 100),
        scale = metrics.scale,
        width = metrics.width,
        height = metrics.height,
        unitWidth = metrics.unitWidth,
        unitHeight = metrics.unitHeight,
        anchorX = number(source.anchorX, anchorX, -10, 10),
        anchorY = number(source.anchorY, anchorY, -10, 10),
        visible = source.visible ~= false,
        facePlayer = source.facePlayer and true or false,
        renderDistance = number(source.renderDistance, nil, 0, 1000000),
        title = source.title,
        padding = number(source.padding, 8, 0, 4096),
        lineHeight = number(source.lineHeight, 16, 1, 4096),
        titleHeight = number(source.titleHeight, 28, 0, 4096),
        tabHeight = number(source.tabHeight, 24, 8, 4096),
        drawBackground = source.drawBackground ~= false,
        drawBorder = source.drawBorder ~= false,
        font = source.font,
        titleFont = source.titleFont,
        textColor = DISPLAY.DeepCopy(source.textColor or '@text'),
        titleColor = DISPLAY.DeepCopy(source.titleColor or '@title'),
        backgroundColor = DISPLAY.DeepCopy(source.backgroundColor or '@background'),
        borderColor = DISPLAY.DeepCopy(source.borderColor or '@border'),
        barColor = DISPLAY.DeepCopy(source.barColor or '@accent'),
        barBackgroundColor = DISPLAY.DeepCopy(source.barBackgroundColor or '@bar_background'),
        themeGroup = DISPLAY.NormalizeId(source.themeGroup or 'default'),
        interaction = DISPLAY.DeepCopy(source.interaction or {}),
        lines = {},
        pages = {}
    }
    local knownThemes = DISPLAY.ThemePacks or {}
    if not next(knownThemes) and DISPLAY.ClientState then
        knownThemes = DISPLAY.ClientState.ThemePacks or knownThemes
    end
    if compiled.themeGroup ~= 'default' and not knownThemes[compiled.themeGroup] then
        addDiagnostic(diagnostics, 'error', '$.themeGroup', 'unknown theme group: ' .. tostring(compiled.themeGroup))
    end
    compiled.interaction.enabled = compiled.interaction.enabled and true or false
    compiled.interaction.distance = number(compiled.interaction.distance, 128, 16, 4096)
    compiled.interaction.fov = number(compiled.interaction.fov, 30, 1, 180)
    compiled.interaction.lineOfSight = compiled.interaction.lineOfSight ~= false

    if mode == 'simple' then
        compiled.lines = normalizeLines(source.lines or {}, '$.lines', diagnostics)
    else
        local pageIds = {}
        if source.pages ~= nil and not isArray(source.pages) then
            addDiagnostic(diagnostics, 'error', '$.pages', 'pages must be an array')
        end
        for index, pageSource in ipairs(source.pages or {}) do
            local page = normalizePage(pageSource, '$.pages[' .. index .. ']', index, diagnostics)
            if page then
                if pageIds[page.id] then
                    addDiagnostic(diagnostics, 'error', '$.pages', 'duplicate page id: ' .. page.id)
                else
                    pageIds[page.id] = true
                    table.insert(compiled.pages, page)
                end
            end
        end
        if #compiled.pages == 0 then
            addDiagnostic(diagnostics, 'error', '$.pages', 'complex display requires at least one page')
        end
        compiled.defaultPage = DISPLAY.NormalizeId(source.defaultPage)
            or (compiled.pages[1] and compiled.pages[1].id)
        if compiled.defaultPage and not pageIds[compiled.defaultPage] then
            addDiagnostic(diagnostics, 'error', '$.defaultPage', 'default page does not exist')
        end
        -- Multiple pages and named actions do not implicitly make a physical
        -- display interactive. Raycasting remains explicitly opt-in through
        -- interaction.enabled; pages can still be driven through server APIs.
    end
    return compiled
end

local function compileThemePack(source, origin, diagnostics)
    local group = DISPLAY.NormalizeId(source.group or source.id)
    if not group then addDiagnostic(diagnostics, 'error', '$.group', 'theme pack requires a group id') end
    local themes = {}
    for name, data in pairs(source.themes or {}) do
        local themeId = DISPLAY.NormalizeId(name)
        if type(data) ~= 'table' then
            addDiagnostic(diagnostics, 'error', '$.themes.' .. tostring(name), 'theme must be an object')
        else
            local tokens = data.tokens or data.colors or data
            local normalized = {}
            for token, color in pairs(tokens) do
                normalized[DISPLAY.NormalizeId(token)] = DISPLAY.ColorTable(color)
            end
            themes[themeId] = {tokens = normalized}
        end
    end
    local defaultTheme = DISPLAY.NormalizeId(source.defaultTheme or source.default)
    if not defaultTheme then for name in pairs(themes) do defaultTheme = name break end end
    if not defaultTheme or not themes[defaultTheme] then
        addDiagnostic(diagnostics, 'error', '$.defaultTheme', 'default theme does not exist')
    end
    return {
        kind = 'theme_pack',
        _compiled = true,
        schema = DISPLAY.Schema,
        group = group,
        origin = origin,
        defaultTheme = defaultTheme,
        themes = themes
    }
end

function DISPLAY.CompileSource(source, origin)
    local diagnostics = {}
    if type(source) ~= 'table' then
        addDiagnostic(diagnostics, 'error', '$', 'source must be a JSON object')
        return nil, diagnostics
    end
    if source.schema ~= DISPLAY.Schema then
        addDiagnostic(diagnostics, 'error', '$.schema', 'unsupported schema: ' .. tostring(source.schema))
        return nil, diagnostics
    end
    rejectExecutableFields(source, '$', diagnostics)
    local kind = string.lower(tostring(source.kind or 'display'))
    local compiled
    if kind == 'display' then
        compiled = compileDisplay(source, origin, diagnostics)
    elseif kind == 'theme_pack' or kind == 'themepack' then
        compiled = compileThemePack(source, origin, diagnostics)
    else
        addDiagnostic(diagnostics, 'error', '$.kind', 'source kind must be display or theme_pack')
    end
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.level == 'error' then return nil, diagnostics end
    end
    return compiled, diagnostics
end

function DISPLAY.DecodeSource(json, origin)
    if type(json) ~= 'string' or json == '' then
        return nil, {{level = 'error', path = '$', message = 'source file is empty'}}
    end
    local source = util.JSONToTable(json)
    if type(source) ~= 'table' then
        return nil, {{level = 'error', path = '$', message = 'invalid JSON'}}
    end
    return DISPLAY.CompileSource(source, origin)
end

function DISPLAY.DiagnosticsText(diagnostics)
    local lines = {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        table.insert(lines, string.format(
            '%s %s: %s',
            string.upper(diagnostic.level or 'error'),
            diagnostic.path or '$',
            diagnostic.message or 'unknown error'
        ))
    end
    return table.concat(lines, '\n')
end
