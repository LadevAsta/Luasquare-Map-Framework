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
local allowedConditionEffectFields = {
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
    critical = true,
    flashEnabled = true,
    frameAnimationEnabled = true,
    rotationAnimationEnabled = true,
    rotationDegrees = true,
    rotationSpeedDegreesPerSecond = true
}
local booleanConditionEffects = {
    visible = true, loop = true, flashEnabled = true,
    frameAnimationEnabled = true, rotationAnimationEnabled = true
}
local numberConditionEffects = {
    frameSeconds = true, animationEpoch = true, flashSeconds = true,
    flashMinimum = true, rotationDegrees = true, rotationSpeedDegreesPerSecond = true
}
local colorConditionEffects = {
    tint = true, color = true, textColor = true, titleColor = true,
    valueColor = true, backgroundColor = true, borderColor = true,
    barColor = true, barBackgroundColor = true, fillColor = true,
    warnColor = true, criticalColor = true
}
local currentVariableDefinitions

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
    if binding.variable ~= nil and binding.provider ~= nil then
        addDiagnostic(diagnostics, 'error', path, 'binding cannot reference both a provider and a display variable')
        return
    end
    if binding.variable ~= nil then
        local name = DISPLAY.NormalizeId(binding.variable)
        if not name then
            addDiagnostic(diagnostics, 'error', path, 'variable binding requires a non-empty name')
        elseif not currentVariableDefinitions or not currentVariableDefinitions[name] then
            addDiagnostic(diagnostics, 'error', path, 'unknown display variable: ' .. tostring(binding.variable))
        end
        if binding.path ~= nil and type(binding.path) ~= 'string' then
            addDiagnostic(diagnostics, 'error', path .. '.path', 'binding path must be a string')
        end
        return
    end
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

local function dynamicNumber(value, fallback, minimum, maximum, path, diagnostics)
    if DISPLAY.IsBinding(value) then
        validateBinding(value, path, diagnostics)
        return DISPLAY.DeepCopy(value)
    end
    return number(value, fallback, minimum, maximum)
end

local walkDynamic

local function validateCondition(condition, path, diagnostics)
    if condition == nil or type(condition) == 'boolean' then return end
    if type(condition) ~= 'table' then
        addDiagnostic(diagnostics, 'error', path, 'condition must be an object or boolean')
        return
    end
    local compositeCount = (condition.all ~= nil and 1 or 0)
        + (condition.any ~= nil and 1 or 0)
        + (condition['not'] ~= nil and 1 or 0)
    if compositeCount > 1 then
        addDiagnostic(diagnostics, 'error', path, 'condition may use only one of all, any, or not')
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
    if condition.value ~= nil then
        walkDynamic(condition.value, path .. '.value', diagnostics)
    end
end

walkDynamic = function(value, path, diagnostics, seen)
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

local function normalizeConditions(source, path, diagnostics)
    local conditions = {}
    local conditionIds = {}
    if source ~= nil and not isArray(source) then
        addDiagnostic(diagnostics, 'error', path, 'conditions must be an array')
        return conditions
    end
    for index, condition in ipairs(source or {}) do
        if type(condition) ~= 'table' or type(condition.apply) ~= 'table' then
            addDiagnostic(diagnostics, 'error', path .. '[' .. index .. ']', 'condition requires when and apply objects')
        else
            if condition.when == nil then
                addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].when', 'condition requires a when object')
            else
                validateCondition(condition.when, path .. '[' .. index .. '].when', diagnostics)
            end
            walkDynamic(condition.apply, path .. '[' .. index .. '].apply', diagnostics)
            if condition.otherwise ~= nil and type(condition.otherwise) ~= 'table' then
                addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].otherwise', 'otherwise must be an object')
            else
                walkDynamic(condition.otherwise, path .. '[' .. index .. '].otherwise', diagnostics)
            end
            local normalized = DISPLAY.DeepCopy(condition)
            normalized.id = DISPLAY.NormalizeId(normalized.id or ('condition_' .. index))
            if not normalized.id then
                addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].id', 'condition requires a stable id')
            elseif conditionIds[normalized.id] then
                addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].id', 'duplicate condition id: ' .. normalized.id)
            else
                conditionIds[normalized.id] = true
            end
            for branchName, branch in pairs({apply = normalized.apply, otherwise = normalized.otherwise}) do
                for field, value in pairs(branch or {}) do
                    if not allowedConditionEffectFields[field] or field == 'animationDisabled' then
                        addDiagnostic(
                            diagnostics,
                            'error',
                            path .. '[' .. index .. '].' .. branchName .. '.' .. tostring(field),
                            'condition cannot override this field'
                        )
                    elseif booleanConditionEffects[field] and not DISPLAY.IsBinding(value)
                        and type(value) ~= 'boolean' then
                        addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].' .. branchName .. '.' .. field,
                            'condition effect must be boolean')
                    elseif numberConditionEffects[field] and not DISPLAY.IsBinding(value)
                        and type(value) ~= 'number' then
                        addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].' .. branchName .. '.' .. field,
                            'condition effect must be numeric')
                    elseif colorConditionEffects[field] and not DISPLAY.IsBinding(value)
                        and type(value) ~= 'string' and type(value) ~= 'table' then
                        addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].' .. branchName .. '.' .. field,
                            'condition color must be a theme token or RGBA value')
                    elseif colorConditionEffects[field] and type(value) == 'string'
                        and string.sub(value, 1, 1) ~= '@' then
                        addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].' .. branchName .. '.' .. field,
                            'condition color string must be a theme token')
                    end
                end
            end
            for _, branchName in ipairs({'apply', 'otherwise'}) do
                local branch = normalized[branchName]
                for _, field in ipairs({'material', 'backgroundMaterial'}) do
                    if branch and branch[field] ~= nil and not DISPLAY.IsBinding(branch[field]) then
                        branch[field] = normalizeMaterialPath(
                            branch[field],
                            path .. '[' .. index .. '].' .. branchName .. '.' .. field,
                            diagnostics
                        )
                    end
                end
                if branch and branch.frames ~= nil then
                    if DISPLAY.IsBinding(branch.frames) then
                        addDiagnostic(diagnostics, 'error', path .. '[' .. index .. '].' .. branchName .. '.frames', 'material frames must be source literals')
                    else
                        branch.frames = normalizeMaterialArray(
                            branch.frames,
                            path .. '[' .. index .. '].' .. branchName .. '.frames',
                            diagnostics
                        )
                    end
                end
            end
            table.insert(conditions, normalized)
        end
    end
    return conditions
end

local function migratedConditions(source, path, diagnostics)
    local conditions = DISPLAY.DeepCopy(source.conditions or {})
    if source.variants ~= nil then
        addDiagnostic(diagnostics, 'warning', path .. '.variants', 'legacy variants migrated to ordered conditions')
        for index, variant in ipairs(source.variants or {}) do
            if type(variant) == 'table' then
                table.insert(conditions, {
                    id = variant.id or ('legacy_variant_' .. index),
                    when = DISPLAY.DeepCopy(variant.when),
                    apply = DISPLAY.DeepCopy(variant.set or {})
                })
            end
        end
    end
    if source.visibleWhen ~= nil then
        addDiagnostic(diagnostics, 'warning', path .. '.visibleWhen', 'legacy visibleWhen migrated to a visibility condition')
        table.insert(conditions, 1, {
            id = 'legacy_visibility',
            when = DISPLAY.DeepCopy(source.visibleWhen),
            apply = {visible = true},
            otherwise = {visible = false}
        })
    end
    return normalizeConditions(conditions, path .. '.conditions', diagnostics)
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
    line.fontScale = nil
    line.conditions = migratedConditions(line, path, diagnostics)
    line.variants = nil
    line.visibleWhen = nil
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
            if DISPLAY.IsBinding(value) then validateBinding(value, path .. '.' .. field, diagnostics)
            else element[field] = normalizeMaterialPath(value, path .. '.' .. field, diagnostics) end
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
    element.frameSeconds = dynamicNumber(element.frameSeconds, nil, 0, 60, path .. '.frameSeconds', diagnostics)
    if not element.frameSeconds and tonumber(element.fps) then
        element.frameSeconds = 1 / number(element.fps, 1, 0.01, 50)
    end
    element.flashSeconds = dynamicNumber(element.flashSeconds, nil, 0, 60, path .. '.flashSeconds', diagnostics)
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
    element.animationDisabled = element.animationDisabled and true or false
    element.rotationDegrees = dynamicNumber(element.rotationDegrees, 0, -360000, 360000,
        path .. '.rotationDegrees', diagnostics)
    element.rotationSpeedDegreesPerSecond = dynamicNumber(element.rotationSpeedDegreesPerSecond, 0, -10000, 10000,
        path .. '.rotationSpeedDegreesPerSecond', diagnostics)
    element.animationEpoch = dynamicNumber(element.animationEpoch, 0, nil, nil, path .. '.animationEpoch', diagnostics)
    element.fontScale = nil
    element.titleFontScale = nil
    element.order = order
    element.conditions = migratedConditions(element, path, diagnostics)
    element.variants = nil
    element.visibleWhen = nil
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

local function rgbaChannelsNumeric(value)
    if (value[1] == nil and value.r == nil) or (value[2] == nil and value.g == nil)
        or (value[3] == nil and value.b == nil) then return false end
    for index = 1, 4 do
        if value[index] ~= nil and type(value[index]) ~= 'number' then return false end
    end
    for _, channel in ipairs({'r', 'g', 'b', 'a'}) do
        if value[channel] ~= nil and type(value[channel]) ~= 'number' then return false end
    end
    return true
end

local function normalizeVariableDefinitions(source, diagnostics)
    local definitions = {}
    if source ~= nil and type(source) ~= 'table' then
        addDiagnostic(diagnostics, 'error', '$.variables', 'variables must be an object')
        return definitions
    end
    if source ~= nil and isArray(source) and #source > 0 then
        addDiagnostic(diagnostics, 'error', '$.variables', 'variables must be keyed by name, not an array')
        return definitions
    end
    local supported = {number = true, boolean = true, string = true, enum = true, color = true}
    for sourceName, sourceDefinition in pairs(source or {}) do
        local name = DISPLAY.NormalizeId(sourceName)
        local path = '$.variables.' .. tostring(sourceName)
        if not name then
            addDiagnostic(diagnostics, 'error', path, 'variable requires a stable name')
        elseif definitions[name] then
            addDiagnostic(diagnostics, 'error', path, 'duplicate normalized variable name: ' .. name)
        elseif type(sourceDefinition) ~= 'table' then
            addDiagnostic(diagnostics, 'error', path, 'variable definition must be an object')
        else
            local definition = DISPLAY.DeepCopy(sourceDefinition)
            definition.type = string.lower(tostring(definition.type or ''))
            definition.name = name
            if not supported[definition.type] then
                addDiagnostic(diagnostics, 'error', path .. '.type', 'unsupported variable type: ' .. definition.type)
            elseif definition.type == 'number' then
                if definition.default ~= nil and type(definition.default) ~= 'number' then
                    addDiagnostic(diagnostics, 'error', path .. '.default', 'number default must be numeric')
                end
                if definition.min ~= nil and type(definition.min) ~= 'number' then
                    addDiagnostic(diagnostics, 'error', path .. '.min', 'number min must be numeric')
                end
                if definition.max ~= nil and type(definition.max) ~= 'number' then
                    addDiagnostic(diagnostics, 'error', path .. '.max', 'number max must be numeric')
                end
                definition.min = number(definition.min, nil)
                definition.max = number(definition.max, nil)
                definition.decimals = math.floor(number(definition.decimals, 3, 0, 8))
                if definition.min and definition.max and definition.min > definition.max then
                    addDiagnostic(diagnostics, 'error', path, 'number min cannot exceed max')
                end
                definition.default = number(definition.default, 0, definition.min, definition.max)
                local power = 10 ^ definition.decimals
                if definition.default >= 0 then
                    definition.default = math.floor(definition.default * power + 0.5) / power
                else
                    definition.default = math.ceil(definition.default * power - 0.5) / power
                end
            elseif definition.type == 'boolean' then
                if definition.default ~= nil and type(definition.default) ~= 'boolean' then
                    addDiagnostic(diagnostics, 'error', path .. '.default', 'boolean default must be true or false')
                end
                definition.default = definition.default and true or false
            elseif definition.type == 'string' then
                if definition.default ~= nil and type(definition.default) ~= 'string' then
                    addDiagnostic(diagnostics, 'error', path .. '.default', 'string default must be text')
                end
                definition.default = tostring(definition.default or '')
            elseif definition.type == 'enum' then
                if not isArray(definition.choices) or #definition.choices == 0 then
                    addDiagnostic(diagnostics, 'error', path .. '.choices', 'enum requires at least one choice')
                    definition.choices = {}
                end
                for choiceIndex, choice in ipairs(definition.choices) do
                    if type(choice) ~= 'string' and type(choice) ~= 'number' and type(choice) ~= 'boolean' then
                        addDiagnostic(diagnostics, 'error', path .. '.choices[' .. choiceIndex .. ']',
                            'enum choices must be strings, numbers, or booleans')
                    end
                end
                if definition.default == nil then definition.default = definition.choices[1] end
                local found = false
                for _, choice in ipairs(definition.choices) do
                    if choice == definition.default then found = true break end
                end
                if not found then addDiagnostic(diagnostics, 'error', path .. '.default', 'enum default must be one of its choices') end
            elseif definition.type == 'color' then
                if type(definition.default) == 'string' then
                    if string.sub(definition.default, 1, 1) ~= '@' then
                        addDiagnostic(diagnostics, 'error', path .. '.default', 'color string must be a theme token')
                    end
                elseif type(definition.default) == 'table' then
                    if not rgbaChannelsNumeric(definition.default) then
                        addDiagnostic(diagnostics, 'error', path .. '.default', 'RGBA channels must be numeric')
                    end
                    local color = DISPLAY.ColorTable(definition.default)
                    definition.default = {color.r, color.g, color.b, color.a}
                else
                    addDiagnostic(diagnostics, 'error', path .. '.default', 'color default must be a theme token or RGBA')
                    definition.default = {255, 255, 255, 255}
                end
            end
            definitions[name] = definition
        end
    end
    return definitions
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
    local variableDefinitions = normalizeVariableDefinitions(source.variables, diagnostics)
    currentVariableDefinitions = variableDefinitions
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
        title = DISPLAY.DeepCopy(source.title),
        padding = number(source.padding, 8, 0, 4096),
        lineHeight = number(source.lineHeight, 16, 1, 4096),
        titleHeight = number(source.titleHeight, 28, 0, 4096),
        tabHeight = number(source.tabHeight, 24, 8, 4096),
        showPageTabs = source.showPageTabs ~= false,
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
        variables = variableDefinitions,
        lines = {},
        pages = {}
    }
    for _, key in ipairs({'title', 'textColor', 'titleColor', 'backgroundColor', 'borderColor',
        'barColor', 'barBackgroundColor'}) do
        walkDynamic(compiled[key], '$.' .. key, diagnostics)
    end
    local knownThemes = DISPLAY.ThemePacks or {}
    if not next(knownThemes) and DISPLAY.ClientState then
        knownThemes = DISPLAY.ClientState.ThemePacks or knownThemes
    end
    if compiled.themeGroup ~= 'default' and not knownThemes[compiled.themeGroup] then
        addDiagnostic(diagnostics, 'error', '$.themeGroup', 'unknown theme group: ' .. tostring(compiled.themeGroup))
    end
    local themePack = knownThemes[compiled.themeGroup]
    if themePack then
        for name, definition in pairs(variableDefinitions) do
            local token = definition.type == 'color' and type(definition.default) == 'string'
                and string.sub(definition.default, 2) or nil
            if token then
                local found = false
                for _, theme in pairs(themePack.themes or {}) do
                    local tokens = theme.tokens or theme.colors or theme
                    if tokens[token] ~= nil then found = true break end
                end
                if not found then
                    addDiagnostic(diagnostics, 'error', '$.variables.' .. name .. '.default',
                        'unknown theme token: @' .. token)
                end
            end
        end
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
    currentVariableDefinitions = nil
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
