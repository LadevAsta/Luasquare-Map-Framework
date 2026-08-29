if not SERVER then return end

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
local DISPLAY = LUASQUARE_3D2D

DISPLAY.DataProviders = DISPLAY.DataProviders or {}
DISPLAY.Actions = DISPLAY.Actions or {}
DISPLAY.ThemePacks = DISPLAY.ThemePacks or {}
DISPLAY.RegisteredThemePacks = DISPLAY.RegisteredThemePacks or {}
DISPLAY.ThemeState = DISPLAY.ThemeState or {}
DISPLAY.Sources = DISPLAY.Sources or {}
DISPLAY.Displays = DISPLAY.Displays or {}
DISPLAY.GraphHistory = DISPLAY.GraphHistory or {}
DISPLAY.ProviderValues = DISPLAY.ProviderValues or {}
DISPLAY.AnnunciatorValues = DISPLAY.AnnunciatorValues or {}
DISPLAY.EntityCache = DISPLAY.EntityCache or {}
DISPLAY.Previews = DISPLAY.Previews or {}
DISPLAY.Revision = DISPLAY.Revision or 0
DISPLAY.DeltaSequence = DISPLAY.DeltaSequence or 0

local UPDATE_TIMER = 'LUASQUARE_3D2D_SourceRuntime'
local SNAPSHOT_TIMER = 'LUASQUARE_3D2D_LayoutSnapshotRefresh'

local function log(message)
    print('[LUASQUARE_3D2D] ' .. tostring(message))
end

local function actorName(actor)
    if not actor then return nil end
    if type(actor) == 'string' then return actor end
    if actor.SteamID64 then return actor:SteamID64() end
    return tostring(actor)
end

local function now()
    if CurTime then return CurTime() end
    return os.clock()
end

local function scheduleSnapshot()
    if not DISPLAY.RuntimeStarted or not DISPLAY.BroadcastSnapshot then return end
    timer.Create(SNAPSHOT_TIMER, 0, 1, function()
        if LUASQUARE_3D2D and LUASQUARE_3D2D.BroadcastSnapshot then
            LUASQUARE_3D2D.BroadcastSnapshot()
        end
    end)
end

local function jsonSafe(value, depth, seen)
    depth = depth or 0
    if depth > 16 then return nil end
    local valueType = type(value)
    if valueType == 'nil' or valueType == 'number'
        or valueType == 'string' or valueType == 'boolean' then return value end
    if valueType ~= 'table' then return tostring(value) end
    seen = seen or {}
    if seen[value] then return nil end
    seen[value] = true
    local out = {}
    local count = 0
    for key, item in pairs(value) do
        count = count + 1
        if count > 2048 then break end
        local safeKey = type(key) == 'number' and key or tostring(key)
        out[safeKey] = jsonSafe(item, depth + 1, seen)
    end
    seen[value] = nil
    return out
end

local function normalizeProviderFields(fields)
    local normalized = {}
    for _, field in ipairs(type(fields) == 'table' and fields or {}) do
        if #normalized >= 512 then break end
        if type(field) == 'table' and type(field.path) == 'string' and field.path ~= '' then
            table.insert(normalized, {
                path = field.path,
                type = tostring(field.type or 'unknown'),
                label = field.label and tostring(field.label) or nil,
                notes = field.notes and tostring(field.notes) or nil
            })
        end
    end
    return normalized
end

function DISPLAY.RegisterDataProvider(id, getter, options)
    id = DISPLAY.NormalizeId(id)
    if not id or type(getter) ~= 'function' then return false end
    options = options or {}
    DISPLAY.DataProviders[id] = {
        id = id,
        getter = getter,
        interval = math.max(tonumber(options.interval) or DISPLAY.TickInterval or 0.1, 0.02),
        nextSample = 0,
        label = options.label or id,
        notes = options.notes,
        fields = jsonSafe(normalizeProviderFields(options.fields))
    }
    if DISPLAY.RuntimeStarted then
        DISPLAY.Revision = DISPLAY.Revision + 1
        scheduleSnapshot()
    end
    return true
end

function DISPLAY.UnregisterDataProvider(id)
    id = DISPLAY.NormalizeId(id)
    if not id then return false end
    DISPLAY.DataProviders[id] = nil
    DISPLAY.ProviderValues[id] = nil
    if DISPLAY.RuntimeStarted then
        DISPLAY.Revision = DISPLAY.Revision + 1
        scheduleSnapshot()
    end
    return true
end

function DISPLAY.RegisterAction(id, definition)
    id = DISPLAY.NormalizeId(id)
    if not id then return false end
    if type(definition) == 'function' then definition = {callback = definition} end
    definition = definition or {}
    if type(definition.callback) ~= 'function' then return false end
    DISPLAY.Actions[id] = {
        id = id,
        label = definition.label or id,
        callback = definition.callback,
        canUse = definition.canUse,
        cooldown = math.max(tonumber(definition.cooldown) or 0.25, 0),
        lastUse = setmetatable({}, {__mode = 'k'}),
        data = definition
    }
    if DISPLAY.RuntimeStarted then
        DISPLAY.Revision = DISPLAY.Revision + 1
        scheduleSnapshot()
    end
    return true
end

local function installThemePack(compiled)
    if DISPLAY.ThemePacks[compiled.group] then
        return false, {{level = 'error', path = '$.group', message = 'duplicate theme group: ' .. compiled.group}}
    end
    DISPLAY.ThemePacks[compiled.group] = DISPLAY.DeepCopy(compiled)
    DISPLAY.ThemeState[compiled.group] = compiled.defaultTheme
    return true
end

function DISPLAY.RegisterThemePack(definition)
    local compiled = definition
    local diagnostics = {}
    if not definition or not definition._compiled then
        local source = DISPLAY.DeepCopy(definition or {})
        source.schema = source.schema or DISPLAY.Schema
        source.kind = 'theme_pack'
        compiled, diagnostics = DISPLAY.CompileSource(source, source.origin or 'runtime')
    end
    if not compiled then
        log('Theme pack rejected:\n' .. DISPLAY.DiagnosticsText(diagnostics))
        return false, diagnostics
    end
    local ok, installDiagnostics = installThemePack(compiled)
    if not ok then return false, installDiagnostics end
    DISPLAY.RegisteredThemePacks[compiled.group] = DISPLAY.DeepCopy(compiled)
    if DISPLAY.RuntimeStarted then
        DISPLAY.Revision = DISPLAY.Revision + 1
        scheduleSnapshot()
    end
    return true
end

local function registerBuiltInTheme()
    if DISPLAY.ThemePacks.default then return end
    local compiled = DISPLAY.CompileSource({
        schema = DISPLAY.Schema,
        kind = 'theme_pack',
        group = 'default',
        defaultTheme = 'normal',
        themes = {
            normal = {
                text = {220, 245, 255, 255},
                title = {255, 255, 255, 255},
                background = {4, 12, 16, 220},
                panel = {8, 20, 24, 220},
                border = {80, 190, 220, 220},
                accent = {70, 220, 160, 255},
                bar_background = {18, 32, 36, 240},
                warning = {255, 210, 70, 255},
                critical = {255, 90, 90, 255},
                inactive = {90, 110, 115, 255}
            },
            emergency = {
                text = {255, 225, 220, 255},
                title = {255, 245, 240, 255},
                background = {28, 3, 3, 235},
                panel = {45, 7, 7, 230},
                border = {255, 75, 65, 245},
                accent = {255, 120, 70, 255},
                bar_background = {55, 12, 12, 245},
                warning = {255, 190, 55, 255},
                critical = {255, 255, 255, 255},
                inactive = {130, 75, 75, 255}
            }
        }
    }, 'built-in theme')
    if compiled then installThemePack(compiled) end
end

function DISPLAY.SetThemeGroup(groupId, themeId)
    groupId = DISPLAY.NormalizeId(groupId)
    themeId = DISPLAY.NormalizeId(themeId)
    local pack = groupId and DISPLAY.ThemePacks[groupId]
    if not pack or not themeId or not pack.themes[themeId] then return false end
    if DISPLAY.ThemeState[groupId] == themeId then return true end
    DISPLAY.ThemeState[groupId] = themeId
    DISPLAY.PendingThemes = DISPLAY.PendingThemes or {}
    DISPLAY.PendingThemes[groupId] = themeId
    return true
end

local function resolveEntity(name)
    if not name or not ents or not ents.FindByName then return nil end
    local cached = DISPLAY.EntityCache[name]
    if IsValid(cached) then return cached end
    local entity = ents.FindByName(name)[1]
    if IsValid(entity) then DISPLAY.EntityCache[name] = entity end
    return entity
end

local function asVector(value)
    if isvector and isvector(value) then return value end
    if type(value) == 'table' and value.x ~= nil then return Vector(value.x, value.y, value.z) end
    return nil
end

local function asAngle(value)
    if isangle and isangle(value) then return value end
    if type(value) == 'table' and value.p ~= nil then return Angle(value.p, value.y, value.r) end
    return nil
end

function DISPLAY.ResolvePlacement(definition)
    local targetName = definition.posTarget or definition.target
    local target = resolveEntity(targetName)
    local pos = asVector(definition.pos)
    local ang = asAngle(definition.ang)
    if not pos and IsValid(target) then pos = target:GetPos() end
    if not ang and definition.useTargetAngle ~= false then
        local angleEntity = resolveEntity(definition.angleTarget) or target
        if IsValid(angleEntity) then ang = angleEntity:GetAngles() end
    end
    pos = pos or Vector(0, 0, 0)
    ang = ang or Angle(0, 0, 90)
    local offset = asVector(definition.offset)
    if offset then pos = pos + offset end
    local angleOffset = asAngle(definition.angleOffset)
    if angleOffset then
        ang = Angle(ang.p + angleOffset.p, ang.y + angleOffset.y, ang.r + angleOffset.r)
    end
    local surfaceOffset = tonumber(definition.surfaceOffset) or 0
    if surfaceOffset ~= 0 and ang.Up then pos = pos + ang:Up() * surfaceOffset end
    return pos, ang, IsValid(target)
end

local function collectGraphsInLines(displayId, pageId, elementId, lines, target)
    for lineIndex, line in ipairs(lines or {}) do
        if line.type == 'graph' then
            local graphId = DISPLAY.NormalizeId(line.id or ('graph_' .. lineIndex))
            local series = line.series
            if type(series) ~= 'table' or #series == 0 then series = {{id = 'value', value = line.value}} end
            for seriesIndex, item in ipairs(series) do
                local binding = item.value
                if DISPLAY.IsBinding(binding) then
                    local key = table.concat({displayId, pageId or 'simple', elementId or 'lines', graphId, item.id or seriesIndex}, ':')
                    target[key] = {
                        key = key,
                        displayId = displayId,
                        pageId = pageId,
                        elementId = elementId,
                        graphId = graphId,
                        seriesId = tostring(item.id or seriesIndex),
                        binding = DISPLAY.DeepCopy(binding),
                        seconds = math.max(tonumber(line.seconds) or 60, 1),
                        sampleInterval = math.max(tonumber(line.sampleInterval) or DISPLAY.TickInterval or 0.1, 0.02),
                        nextSample = 0
                    }
                end
            end
        end
    end
end

local function collectDisplayGraphs(definition)
    local graphs = {}
    if definition.buildMode == 'simple' then
        collectGraphsInLines(definition.id, nil, nil, definition.lines, graphs)
    else
        for _, page in ipairs(definition.pages or {}) do
            for _, element in ipairs(page.elements or {}) do
                if element.type == 'line_panel' then
                    collectGraphsInLines(definition.id, page.id, element.id, element.lines, graphs)
                end
            end
        end
    end
    return graphs
end

function DISPLAY.BuildDisplay(compiledDefinition, overrides)
    if not compiledDefinition or not compiledDefinition._compiled
        or compiledDefinition.kind ~= 'display' then return false end
    local definition = DISPLAY.DeepCopy(compiledDefinition)
    for key, value in pairs(overrides or {}) do definition[key] = DISPLAY.DeepCopy(value) end
    local id = DISPLAY.NormalizeId(definition.id)
    if not id then return false end
    definition.id = id
    for key, history in pairs(DISPLAY.GraphHistory) do
        if history.displayId == id then DISPLAY.GraphHistory[key] = nil end
    end
    local variableValues = {}
    for name, variable in pairs(definition.variables or {}) do
        variableValues[name] = DISPLAY.DeepCopy(variable.default)
    end
    DISPLAY.Displays[id] = {
        id = id,
        definition = definition,
        activePage = definition.defaultPage,
        graphs = collectDisplayGraphs(definition),
        variables = variableValues,
        builtAt = now()
    }
    DISPLAY.PendingPages = DISPLAY.PendingPages or {}
    DISPLAY.PendingPages[id] = definition.defaultPage
    if next(variableValues) then
        DISPLAY.PendingVariables = DISPLAY.PendingVariables or {}
        DISPLAY.PendingVariables[id] = DISPLAY.DeepCopy(variableValues)
    end
    DISPLAY.Revision = DISPLAY.Revision + 1
    scheduleSnapshot()
    hook.Run('LUASQUARE_3D2D_DisplayBuilt', id, DISPLAY.Displays[id])
    return true, DISPLAY.Displays[id]
end

local function queueVariableDelta(displayId, values)
    if not next(values or {}) then return end
    DISPLAY.PendingVariables = DISPLAY.PendingVariables or {}
    local pending = DISPLAY.PendingVariables[displayId] or {}
    DISPLAY.PendingVariables[displayId] = pending
    for name, value in pairs(values or {}) do pending[name] = DISPLAY.DeepCopy(value) end
end

local function themeHasToken(display, token)
    if type(token) ~= 'string' or string.sub(token, 1, 1) ~= '@' then return false end
    local pack = DISPLAY.ThemePacks[display.definition.themeGroup or 'default']
    local key = string.sub(token, 2)
    for _, theme in pairs(pack and pack.themes or {}) do
        local tokens = theme.tokens or theme.colors or theme
        if tokens[key] ~= nil then return true end
    end
    return false
end

local function validateVariableValue(display, name, value)
    local definition = display.definition.variables and display.definition.variables[name]
    if not definition then return false, 'undeclared display variable: ' .. tostring(name) end
    if definition.type == 'number' then
        if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then
            return false, 'variable ' .. name .. ' requires a finite number'
        end
        if definition.min then value = math.max(value, definition.min) end
        if definition.max then value = math.min(value, definition.max) end
        local power = 10 ^ math.max(math.floor(tonumber(definition.decimals) or 3), 0)
        if value >= 0 then value = math.floor(value * power + 0.5) / power
        else value = math.ceil(value * power - 0.5) / power end
    elseif definition.type == 'boolean' then
        if type(value) ~= 'boolean' then return false, 'variable ' .. name .. ' requires a boolean' end
    elseif definition.type == 'string' then
        if type(value) ~= 'string' then return false, 'variable ' .. name .. ' requires a string' end
    elseif definition.type == 'enum' then
        local found = false
        for _, choice in ipairs(definition.choices or {}) do
            if DISPLAY.DeepEqual(choice, value) then found = true break end
        end
        if not found then return false, 'variable ' .. name .. ' is not an allowed enum choice' end
    elseif definition.type == 'color' then
        if type(value) == 'string' then
            if not themeHasToken(display, value) then return false, 'variable ' .. name .. ' references an unknown theme token' end
        elseif type(value) == 'table' then
            if (value[1] == nil and value.r == nil) or (value[2] == nil and value.g == nil)
                or (value[3] == nil and value.b == nil) then
                return false, 'variable ' .. name .. ' requires RGB or RGBA channels'
            end
            for index = 1, 4 do
                if value[index] ~= nil and type(value[index]) ~= 'number' then
                    return false, 'variable ' .. name .. ' requires numeric RGBA channels'
                end
            end
            for _, channel in ipairs({'r', 'g', 'b', 'a'}) do
                if value[channel] ~= nil and type(value[channel]) ~= 'number' then
                    return false, 'variable ' .. name .. ' requires numeric RGBA channels'
                end
            end
            local color = DISPLAY.ColorTable(value)
            value = {color.r, color.g, color.b, color.a}
        else
            return false, 'variable ' .. name .. ' requires a theme token or RGBA value'
        end
    else
        return false, 'variable ' .. name .. ' has an unsupported declaration type'
    end
    return true, DISPLAY.DeepCopy(value)
end

function DISPLAY.SetDisplayVariables(displayId, values)
    displayId = DISPLAY.NormalizeId(displayId)
    local display = displayId and DISPLAY.Displays[displayId]
    if not display then return false, 'display not found' end
    if type(values) ~= 'table' then return false, 'values must be a table' end
    local validated = {}
    for sourceName, value in pairs(values) do
        local name = DISPLAY.NormalizeId(sourceName)
        local ok, result = validateVariableValue(display, name, value)
        if not ok then return false, result end
        validated[name] = result
    end
    local changed = false
    local delta = {}
    for name, value in pairs(validated) do
        if not DISPLAY.DeepEqual(display.variables[name], value) then
            display.variables[name] = value
            delta[name] = DISPLAY.DeepCopy(value)
            changed = true
        end
    end
    if changed then
        queueVariableDelta(displayId, delta)
    end
    return true
end

function DISPLAY.SetDisplayVariable(displayId, name, value)
    return DISPLAY.SetDisplayVariables(displayId, {[tostring(name or '')] = value})
end

function DISPLAY.ResetDisplayVariables(displayId)
    displayId = DISPLAY.NormalizeId(displayId)
    local display = displayId and DISPLAY.Displays[displayId]
    if not display then return false, 'display not found' end
    local values = {}
    for name, definition in pairs(display.definition.variables or {}) do
        values[name] = DISPLAY.DeepCopy(definition.default)
    end
    display.variables = values
    queueVariableDelta(displayId, values)
    return true
end

function DISPLAY.ResetDisplayVariable(displayId, name)
    displayId = DISPLAY.NormalizeId(displayId)
    name = DISPLAY.NormalizeId(name)
    local display = displayId and DISPLAY.Displays[displayId]
    local definition = display and display.definition.variables and display.definition.variables[name]
    if not definition then return false, display and ('undeclared display variable: ' .. tostring(name)) or 'display not found' end
    return DISPLAY.SetDisplayVariable(displayId, name, DISPLAY.DeepCopy(definition.default))
end

function DISPLAY.GetDisplayVariable(displayId, name)
    local display = DISPLAY.Displays[DISPLAY.NormalizeId(displayId)]
    if not display then return nil end
    return DISPLAY.DeepCopy(display.variables[DISPLAY.NormalizeId(name)])
end

function DISPLAY.GetDisplayVariables(displayId)
    local display = DISPLAY.Displays[DISPLAY.NormalizeId(displayId)]
    return display and DISPLAY.DeepCopy(display.variables) or nil
end

function DISPLAY.GetDisplayVariableDefinitions(displayId)
    local display = DISPLAY.Displays[DISPLAY.NormalizeId(displayId)]
    return display and DISPLAY.DeepCopy(display.definition.variables or {}) or nil
end

function DISPLAY.RemoveDisplay(id)
    id = DISPLAY.NormalizeId(id)
    if not id or not DISPLAY.Displays[id] then return false end
    DISPLAY.Displays[id] = nil
    for key, history in pairs(DISPLAY.GraphHistory) do
        if history.displayId == id then DISPLAY.GraphHistory[key] = nil end
    end
    DISPLAY.Previews[id] = nil
    DISPLAY.Revision = DISPLAY.Revision + 1
    scheduleSnapshot()
    return true
end

function DISPLAY.SetDisplayPage(displayId, pageId, actor)
    displayId = DISPLAY.NormalizeId(displayId)
    pageId = DISPLAY.NormalizeId(pageId)
    local display = displayId and DISPLAY.Displays[displayId]
    if not display or display.definition.buildMode ~= 'complex' then return false end
    local found = false
    for _, page in ipairs(display.definition.pages or {}) do
        if page.id == pageId then found = true break end
    end
    if not found then return false end
    if display.activePage == pageId then return true end
    display.activePage = pageId
    display.lastPageActor = actorName(actor)
    DISPLAY.PendingPages = DISPLAY.PendingPages or {}
    DISPLAY.PendingPages[displayId] = pageId
    return true
end

function DISPLAY.GetDisplayPage(displayId)
    displayId = DISPLAY.NormalizeId(displayId)
    local display = displayId and DISPLAY.Displays[displayId]
    if not display or display.definition.buildMode ~= 'complex' then return nil end
    return display.activePage
end

function DISPLAY.CycleDisplayPage(displayId, direction, actor, wrap)
    displayId = DISPLAY.NormalizeId(displayId)
    local display = displayId and DISPLAY.Displays[displayId]
    if not display or display.definition.buildMode ~= 'complex' then return false end
    local pages = display.definition.pages or {}
    if #pages == 0 then return false end

    local currentIndex = 1
    for index, page in ipairs(pages) do
        if page.id == display.activePage then currentIndex = index break end
    end
    local step = math.floor(tonumber(direction) or 1)
    if step == 0 then return true end
    local nextIndex = currentIndex + step
    if wrap == false then
        nextIndex = math.Clamp(nextIndex, 1, #pages)
    else
        nextIndex = ((nextIndex - 1) % #pages) + 1
    end
    return DISPLAY.SetDisplayPage(displayId, pages[nextIndex].id, actor)
end

function DISPLAY.NextDisplayPage(displayId, actor, wrap)
    return DISPLAY.CycleDisplayPage(displayId, 1, actor, wrap)
end

function DISPLAY.PreviousDisplayPage(displayId, actor, wrap)
    return DISPLAY.CycleDisplayPage(displayId, -1, actor, wrap)
end

local function registerCompiledSource(compiled, source, origin, json)
    if compiled.kind == 'theme_pack' then
        if DISPLAY.ThemePacks[compiled.group] then
            log('Duplicate theme group rejected from ' .. tostring(origin) .. ': ' .. compiled.group)
            return false
        end
        return installThemePack(compiled)
    end
    if DISPLAY.Sources[compiled.id] or DISPLAY.Displays[compiled.id] then
        log('Duplicate display id rejected from ' .. tostring(origin) .. ': ' .. compiled.id)
        return false
    end
    DISPLAY.Sources[compiled.id] = {
        id = compiled.id,
        source = DISPLAY.DeepCopy(source),
        compiled = compiled,
        origin = origin,
        json = json
    }
    return DISPLAY.BuildDisplay(compiled)
end

function DISPLAY.LoadSource(path)
    path = tostring(path or '')
    local json = file.Read(path, 'GAME')
    if not json then
        log('Source not found: ' .. path)
        return false
    end
    local source = util.JSONToTable(json)
    local compiled, diagnostics = DISPLAY.CompileSource(source, path)
    if not compiled then
        log('Source rejected ' .. path .. ':\n' .. DISPLAY.DiagnosticsText(diagnostics))
        return false, diagnostics
    end
    return registerCompiledSource(compiled, source, path, json), diagnostics
end

local function loadSourceDirectory(path)
    local files = file.Find(path .. '/*.json', 'GAME') or {}
    table.sort(files)
    local loaded = 0
    for _, name in ipairs(files) do
        if DISPLAY.LoadSource(path .. '/' .. name) then loaded = loaded + 1 end
    end
    return loaded
end

function DISPLAY.LoadMapSources(mapName)
    registerBuiltInTheme()
    local root = DISPLAY.SourceRoot
    local themeCount = loadSourceDirectory(root .. '/_themes')
    for group, pack in pairs(DISPLAY.RegisteredThemePacks) do
        if not DISPLAY.ThemePacks[group] and installThemePack(pack) then themeCount = themeCount + 1 end
    end
    local displayCount = loadSourceDirectory(root .. '/' .. string.lower(tostring(mapName or game.GetMap() or 'unknown')))
    log(string.format('Loaded %d theme pack(s) and %d display source(s)', themeCount, displayCount))
    return displayCount
end

function DISPLAY.ClearPreview(displayId, reason)
    displayId = DISPLAY.NormalizeId(displayId)
    local preview = displayId and DISPLAY.Previews[displayId]
    if not preview then return false end
    DISPLAY.Previews[displayId] = nil
    DISPLAY.BuildDisplay(preview.original)
    if preview.originalVariables then DISPLAY.SetDisplayVariables(displayId, preview.originalVariables) end
    log('Cleared preview ' .. displayId .. ': ' .. tostring(reason or 'manual'))
    return true
end

function DISPLAY.ClearAllPreviews(reason, owner)
    local ids = {}
    for id, preview in pairs(DISPLAY.Previews) do
        if owner == nil or preview.owner == owner then table.insert(ids, id) end
    end
    for _, id in ipairs(ids) do DISPLAY.ClearPreview(id, reason) end
    return #ids
end

function DISPLAY.ApplyPreview(source, targetDisplayId, owner)
    targetDisplayId = DISPLAY.NormalizeId(targetDisplayId)
    local target = targetDisplayId and DISPLAY.Displays[targetDisplayId]
    if not target then return false, 'target display not found' end
    local compiled, diagnostics = DISPLAY.CompileSource(source, 'editor preview')
    if not compiled or compiled.kind ~= 'display' then
        return false, DISPLAY.DiagnosticsText(diagnostics)
    end
    local existing = DISPLAY.Previews[targetDisplayId]
    if existing and existing.owner ~= owner then return false, 'display is previewed by another admin' end
    if not existing then
        DISPLAY.Previews[targetDisplayId] = {
            owner = owner,
            original = DISPLAY.DeepCopy(target.definition),
            originalVariables = DISPLAY.DeepCopy(target.variables)
        }
    end
    local placement = target.definition
    local overrides = {
        id = targetDisplayId,
        target = placement.target,
        posTarget = placement.posTarget,
        angleTarget = placement.angleTarget,
        useTargetAngle = placement.useTargetAngle,
        pos = placement.pos,
        ang = placement.ang,
        offset = placement.offset,
        angleOffset = placement.angleOffset,
        surfaceOffset = placement.surfaceOffset,
        scale = placement.scale,
        width = placement.width,
        height = placement.height,
        unitWidth = placement.unitWidth,
        unitHeight = placement.unitHeight,
        anchorX = placement.anchorX,
        anchorY = placement.anchorY
    }
    DISPLAY.BuildDisplay(compiled, overrides)
    DISPLAY.Previews[targetDisplayId].owner = owner
    return true
end

function DISPLAY.ReloadSources()
    hook.Run('LUASQUARE_3D2D_DisplaysClearing')
    DISPLAY.ClearAllPreviews('source reload')
    DISPLAY.Sources = {}
    DISPLAY.Displays = {}
    DISPLAY.ThemePacks = {}
    DISPLAY.ThemeState = {}
    DISPLAY.GraphHistory = {}
    DISPLAY.AnnunciatorValues = {}
    DISPLAY.EntityCache = {}
    DISPLAY.PendingPages = {}
    DISPLAY.PendingThemes = {}
    DISPLAY.PendingVariables = {}
    DISPLAY.Revision = DISPLAY.Revision + 1
    return DISPLAY.LoadMapSources(game.GetMap())
end

local function serializeDisplay(display)
    local definition = DISPLAY.DeepCopy(display.definition)
    local explicitPosition = definition.pos ~= nil
    local expectsTarget = definition.target ~= nil or definition.posTarget ~= nil
    local pos, ang, targetFound = DISPLAY.ResolvePlacement(definition)
    definition.pos = DISPLAY.VectorToTable(pos)
    definition.ang = DISPLAY.AngleToTable(ang)
    definition.targetFound = targetFound
    definition.placementValid = explicitPosition or targetFound or not expectsTarget
    if not definition.placementValid then definition.visible = false end
    definition.activePage = display.activePage
    definition.variableValues = DISPLAY.DeepCopy(display.variables or {})
    return definition
end

local function providerCatalog()
    local providers = {}
    for id, provider in pairs(DISPLAY.DataProviders) do
        providers[id] = {id = id, label = provider.label, notes = provider.notes, fields = DISPLAY.DeepCopy(provider.fields or {})}
    end
    return providers
end

local function actionCatalog()
    local actions = {}
    for id, action in pairs(DISPLAY.Actions) do
        actions[id] = {id = id, label = action.label}
    end
    return actions
end

local function graphSnapshot()
    local out = {}
    for key, history in pairs(DISPLAY.GraphHistory) do
        out[key] = {
            key = key,
            displayId = history.displayId,
            pageId = history.pageId,
            elementId = history.elementId,
            graphId = history.graphId,
            seriesId = history.seriesId,
            seconds = history.seconds,
            points = DISPLAY.DeepCopy(history.points)
        }
    end
    return out
end

function DISPLAY.GetSnapshot()
    local displays = {}
    for _, display in pairs(DISPLAY.Displays) do table.insert(displays, serializeDisplay(display)) end
    table.sort(displays, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return {
        schema = DISPLAY.Schema,
        revision = DISPLAY.Revision,
        serverTime = now(),
        map = game.GetMap(),
        Displays = displays,
        Providers = DISPLAY.DeepCopy(DISPLAY.ProviderValues),
        ProviderCatalog = providerCatalog(),
        ActionCatalog = actionCatalog(),
        ThemePacks = DISPLAY.DeepCopy(DISPLAY.ThemePacks),
        ThemeState = DISPLAY.DeepCopy(DISPLAY.ThemeState),
        Annunciators = DISPLAY.DeepCopy(DISPLAY.AnnunciatorValues),
        Graphs = graphSnapshot()
    }
end

local function sampleProviders(currentTime, delta)
    for id, provider in pairs(DISPLAY.DataProviders) do
        if currentTime >= (provider.nextSample or 0) then
            provider.nextSample = currentTime + provider.interval
            local ok, value = pcall(provider.getter)
            if ok then
                value = jsonSafe(value)
                if not DISPLAY.DeepEqual(DISPLAY.ProviderValues[id], value) then
                    DISPLAY.ProviderValues[id] = value
                    delta.providers[id] = DISPLAY.DeepCopy(value)
                end
            else
                log('Provider ' .. id .. ' failed: ' .. tostring(value))
            end
        end
    end
end

local function sampleGraphs(currentTime, delta)
    for _, display in pairs(DISPLAY.Displays) do
        for key, graph in pairs(display.graphs or {}) do
            if currentTime >= (graph.nextSample or 0) then
                graph.nextSample = currentTime + graph.sampleInterval
                local owner = DISPLAY.Displays[graph.displayId]
                local value = tonumber(DISPLAY.ResolveBinding(
                    graph.binding,
                    DISPLAY.ProviderValues,
                    owner and owner.variables or nil
                ))
                if value then
                    local history = DISPLAY.GraphHistory[key]
                    if not history then
                        history = DISPLAY.DeepCopy(graph)
                        history.points = {}
                        DISPLAY.GraphHistory[key] = history
                    end
                    table.insert(history.points, {t = currentTime, v = value})
                    local cutoff = currentTime - graph.seconds
                    while history.points[1] and history.points[1].t < cutoff do table.remove(history.points, 1) end
                    table.insert(delta.graphSamples, {key = key, t = currentTime, v = value})
                end
            end
        end
    end
end

local function collectAnnunciatorIds()
    local ids = {}
    for _, display in pairs(DISPLAY.Displays) do
        for _, page in ipairs(display.definition.pages or {}) do
            for _, element in ipairs(page.elements or {}) do
                if element.type == 'annunciator' and element.alarm then ids[element.alarm] = true end
            end
        end
    end
    return ids
end

local function sampleAnnunciators(delta)
    if not LUASQUARE_ANNUNCIATOR or not LUASQUARE_ANNUNCIATOR.GetAlarm then return end
    for id in pairs(collectAnnunciatorIds()) do
        local alarm = LUASQUARE_ANNUNCIATOR.GetAlarm(id)
        local muted = alarm and LUASQUARE_ANNUNCIATOR.IsMuted and LUASQUARE_ANNUNCIATOR.IsMuted() or false
        local state = 'inactive'
        if alarm then
            if alarm.active then
                state = muted and 'muted' or (alarm.acknowledged and 'acknowledged' or 'active')
            elseif alarm.resolved then
                state = 'reset'
            end
        end
        local value = alarm and {
            active = alarm.active and true or false,
            acknowledged = alarm.acknowledged and true or false,
            muted = muted,
            state = state,
            rawState = LUASQUARE_ANNUNCIATOR.GetDisplayState and LUASQUARE_ANNUNCIATOR.GetDisplayState(alarm) or nil,
            message = alarm.message,
            label = alarm.label or id
        } or {state = 'missing', label = id}
        if not DISPLAY.DeepEqual(DISPLAY.AnnunciatorValues[id], value) then
            DISPLAY.AnnunciatorValues[id] = value
            delta.annunciators[id] = DISPLAY.DeepCopy(value)
        end
    end
end

function DISPLAY.Update()
    local currentTime = now()
    local delta = {
        revision = DISPLAY.Revision,
        sequence = DISPLAY.DeltaSequence + 1,
        serverTime = currentTime,
        providers = {},
        variables = DISPLAY.PendingVariables or {},
        pages = DISPLAY.PendingPages or {},
        themes = DISPLAY.PendingThemes or {},
        annunciators = {},
        graphSamples = {}
    }
    DISPLAY.PendingPages = {}
    DISPLAY.PendingThemes = {}
    DISPLAY.PendingVariables = {}
    sampleProviders(currentTime, delta)
    sampleGraphs(currentTime, delta)
    sampleAnnunciators(delta)
    DISPLAY.DeltaSequence = delta.sequence
    if DISPLAY.BroadcastDelta then DISPLAY.BroadcastDelta(delta) end
end

function DISPLAY.Start()
    DISPLAY.RuntimeStarted = false
    DISPLAY.ReloadSources()
    DISPLAY.Update()
    DISPLAY.RuntimeStarted = true
    if DISPLAY.BroadcastSnapshot then DISPLAY.BroadcastSnapshot() end
    if timer.Exists(UPDATE_TIMER) then timer.Remove(UPDATE_TIMER) end
    timer.Create(UPDATE_TIMER, math.max(DISPLAY.TickInterval or 0.1, 0.02), 0, function()
        if LUASQUARE_3D2D and LUASQUARE_3D2D.Update then LUASQUARE_3D2D.Update() end
    end)
    log('Source runtime started')
    return true
end

function DISPLAY.Stop()
    local restored = DISPLAY.ClearAllPreviews('runtime stopped')
    if restored > 0 and DISPLAY.BroadcastSnapshot then DISPLAY.BroadcastSnapshot() end
    if timer.Exists(UPDATE_TIMER) then timer.Remove(UPDATE_TIMER) end
    if timer.Exists(SNAPSHOT_TIMER) then timer.Remove(SNAPSHOT_TIMER) end
    DISPLAY.RuntimeStarted = false
    log('Source runtime stopped')
    return true
end
