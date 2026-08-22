LUASQUARE_3D2D = LUASQUARE_3D2D or {}

local DISPLAY = LUASQUARE_3D2D

function DISPLAY.NormalizeId(value)
    if value == nil then return nil end
    value = string.lower(tostring(value))
    value = string.gsub(value, '[^%w_%.%-:]', '_')
    if value == '' then return nil end
    return value
end

function DISPLAY.DeepCopy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, item in pairs(value) do
        out[DISPLAY.DeepCopy(key, seen)] = DISPLAY.DeepCopy(item, seen)
    end
    return out
end

function DISPLAY.DeepEqual(a, b, seen)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    seen = seen or {}
    if seen[a] == b then return true end
    seen[a] = b
    for key, value in pairs(a) do
        if not DISPLAY.DeepEqual(value, b[key], seen) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

function DISPLAY.Clamp(value, minimum, maximum)
    value = tonumber(value) or minimum
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function DISPLAY.ParseTargetMetrics(targetName)
    if not targetName then return nil end
    local width, height = string.match(
        tostring(targetName), '^DISPLAY([%d%.]+)[xX]([%d%.]+)_'
    )
    width = tonumber(width)
    height = tonumber(height)
    if not width or not height or width <= 0 or height <= 0 then return nil end
    return { unitWidth = width, unitHeight = height }
end

function DISPLAY.GetPath(root, path)
    if path == nil or path == '' then return root end
    local value = root
    for segment in string.gmatch(tostring(path), '[^%.]+') do
        if type(value) ~= 'table' then return nil end
        value = value[segment]
        if value == nil then return nil end
    end
    return value
end

function DISPLAY.IsBinding(value)
    return type(value) == 'table' and value.provider ~= nil
end

function DISPLAY.ResolveBinding(binding, providerValues)
    if not DISPLAY.IsBinding(binding) then return binding end
    local provider = providerValues and providerValues[tostring(binding.provider)]
    local value = DISPLAY.GetPath(provider, binding.path)
    if value == nil then value = binding.default end
    return value
end

function DISPLAY.ResolveDynamic(value, providerValues)
    if DISPLAY.IsBinding(value) then
        return DISPLAY.DeepCopy(DISPLAY.ResolveBinding(value, providerValues))
    end
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, item in pairs(value) do
        out[key] = DISPLAY.ResolveDynamic(item, providerValues)
    end
    return out
end

local conditionOperators = {
    eq = function(a, b) return a == b end,
    ne = function(a, b) return a ~= b end,
    gt = function(a, b) return tonumber(a) and tonumber(b) and tonumber(a) > tonumber(b) or false end,
    gte = function(a, b) return tonumber(a) and tonumber(b) and tonumber(a) >= tonumber(b) or false end,
    lt = function(a, b) return tonumber(a) and tonumber(b) and tonumber(a) < tonumber(b) or false end,
    lte = function(a, b) return tonumber(a) and tonumber(b) and tonumber(a) <= tonumber(b) or false end,
    truthy = function(a) return a and true or false end
}

function DISPLAY.EvaluateCondition(condition, providerValues)
    if condition == nil then return true end
    if type(condition) == 'boolean' then return condition end
    if type(condition) ~= 'table' then return false end

    if type(condition.all) == 'table' then
        for _, child in ipairs(condition.all) do
            if not DISPLAY.EvaluateCondition(child, providerValues) then return false end
        end
        return true
    end
    if type(condition.any) == 'table' then
        for _, child in ipairs(condition.any) do
            if DISPLAY.EvaluateCondition(child, providerValues) then return true end
        end
        return false
    end
    if condition['not'] ~= nil then
        return not DISPLAY.EvaluateCondition(condition['not'], providerValues)
    end

    local value = DISPLAY.ResolveBinding(condition, providerValues)
    local operation = string.lower(tostring(condition.op or 'truthy'))
    local callback = conditionOperators[operation]
    if not callback then return false end
    return callback(value, condition.value)
end

function DISPLAY.ApplyVariants(item, providerValues)
    local out = DISPLAY.ResolveDynamic(item, providerValues)
    out.variants = nil
    if item.visibleWhen ~= nil then
        out.visible = DISPLAY.EvaluateCondition(item.visibleWhen, providerValues)
    end
    for _, variant in ipairs(item.variants or {}) do
        if DISPLAY.EvaluateCondition(variant.when, providerValues) then
            for key, value in pairs(variant.set or {}) do
                out[key] = DISPLAY.ResolveDynamic(value, providerValues)
            end
            break
        end
    end
    return out
end

function DISPLAY.ColorTable(value, fallback)
    fallback = fallback or {r = 255, g = 255, b = 255, a = 255}
    if type(value) ~= 'table' then return DISPLAY.DeepCopy(fallback) end
    return {
        r = DISPLAY.Clamp(value.r or value[1] or fallback.r, 0, 255),
        g = DISPLAY.Clamp(value.g or value[2] or fallback.g, 0, 255),
        b = DISPLAY.Clamp(value.b or value[3] or fallback.b, 0, 255),
        a = DISPLAY.Clamp(value.a or value[4] or fallback.a or 255, 0, 255)
    }
end

function DISPLAY.ResolveThemeToken(display, value, fallback, clientState)
    if type(value) ~= 'string' or string.sub(value, 1, 1) ~= '@' then
        return DISPLAY.ColorTable(value, fallback)
    end
    local group = display.themeGroup or 'default'
    local state = clientState or DISPLAY.ClientState or {}
    local packs = state.ThemePacks or state.themePacks or {}
    local pack = packs[group] or {}
    local activeThemes = state.ThemeState or state.themeState or {}
    local themeName = activeThemes[group] or pack.defaultTheme or pack.default or 'normal'
    local theme = (pack.themes or {})[themeName] or {}
    local tokens = theme.tokens or theme.colors or theme
    return DISPLAY.ColorTable(tokens[string.sub(value, 2)], fallback)
end

function DISPLAY.VectorToTable(value)
    if not value then return nil end
    return {x = value.x or 0, y = value.y or 0, z = value.z or 0}
end

function DISPLAY.AngleToTable(value)
    if not value then return nil end
    return {p = value.p or 0, y = value.y or 0, r = value.r or 0}
end

function DISPLAY.TableToVector(value)
    if not value or value.x == nil then return nil end
    return Vector(value.x or 0, value.y or 0, value.z or 0)
end

function DISPLAY.TableToAngle(value)
    if not value or value.p == nil then return nil end
    return Angle(value.p or 0, value.y or 0, value.r or 0)
end

function DISPLAY.GetDisplayBasis(display)
    local ang = display.ang
    if not ang or not ang.Forward then return nil end
    -- cam.Start3D2D maps canvas +X to Angle:Forward(). Its built-in negative
    -- Y matrix scale turns the angle matrix's left axis into Angle:Right(),
    -- so positive canvas Y follows Right(). Interaction must use the same
    -- basis or its hitboxes are vertically mirrored on angled displays.
    local xAxis = ang:Forward()
    local yAxis = ang:Right()
    local normal = ang:Up()
    return xAxis, yAxis, normal
end

function DISPLAY.ProjectRayToCanvas(display, eye, direction)
    if not display or not display.pos or not display.ang then return nil end
    local xAxis, yAxis, normal = DISPLAY.GetDisplayBasis(display)
    if not xAxis then return nil end
    local denominator = direction:Dot(normal)
    if math.abs(denominator) < 0.00001 then return nil end
    local distance = (display.pos - eye):Dot(normal) / denominator
    if distance <= 0 then return nil end
    local point = eye + direction * distance
    local relative = point - display.pos
    local scale = math.max(tonumber(display.scale) or 0.1, 0.00001)
    local x = relative:Dot(xAxis) / scale + (display.anchorX or 0) * (display.width or 256)
    local y = relative:Dot(yAxis) / scale + (display.anchorY or 0) * (display.height or 128)
    if x < 0 or y < 0 or x > (display.width or 256) or y > (display.height or 128) then
        return nil
    end
    return {x = x, y = y, point = point, distance = distance}
end

function DISPLAY.PassesInteractionFOV(display, eye, direction)
    local xAxis, yAxis = DISPLAY.GetDisplayBasis(display)
    if not xAxis then return false end
    local scale = tonumber(display.scale) or 0.1
    local width = tonumber(display.width) or 256
    local height = tonumber(display.height) or 128
    local center = display.pos
        + xAxis * ((0.5 - (display.anchorX or 0)) * width * scale)
        + yAxis * ((0.5 - (display.anchorY or 0)) * height * scale)
    local toCenter = center - eye
    local distance = toCenter:Length()
    local radius = math.sqrt((width * scale) ^ 2 + (height * scale) ^ 2) * 0.5
    if distance <= radius then return true end
    toCenter:Normalize()
    local angularRadius = math.deg(math.atan(radius / math.max(distance, 0.001)))
    local fov = display.interaction and tonumber(display.interaction.fov) or 30
    local threshold = math.cos(math.rad(math.Clamp(fov * 0.5 + angularRadius, 1, 179)))
    return direction:Dot(toCenter) >= threshold
end

function DISPLAY.PointInRect(x, y, rect)
    return rect and x >= rect.x and y >= rect.y
        and x <= rect.x + rect.width and y <= rect.y + rect.height
end

function DISPLAY.GetTabRects(display)
    if not display or display.showPageTabs == false
        or display.buildMode ~= 'complex' or #(display.pages or {}) <= 1 then
        return {}
    end
    local tabs = {}
    local width = (display.width or 256) / #display.pages
    local height = display.tabHeight or 24
    for index, page in ipairs(display.pages) do
        tabs[index] = {
            id = page.id,
            label = page.label,
            x = (index - 1) * width,
            y = 0,
            width = width,
            height = height
        }
    end
    return tabs
end
