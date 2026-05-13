if LITHOS_SEG7_CORE_LOADED then return end
LITHOS_SEG7_CORE_LOADED = true
LITHOS_SEG7 = LITHOS_SEG7 or {}
LITHOS_SEG7.Displays = LITHOS_SEG7.Displays or {}
LITHOS_SEG7.Bindings = LITHOS_SEG7.Bindings or {}
LITHOS_SEG7.EntityCache = LITHOS_SEG7.EntityCache or {}
LITHOS_SEG7.BLANK = 10
LITHOS_SEG7.MINUS = 11

-- =========================================
-- ENTITY CACHE
-- =========================================
function LITHOS_SEG7.GetEnt(name)
    local cached = LITHOS_SEG7.EntityCache[name]
    if IsValid(cached) then return cached end
    local ent = ents.FindByName(name)[1]
    if IsValid(ent) then LITHOS_SEG7.EntityCache[name] = ent end
    return ent
end

-- =========================================
-- REGISTER DISPLAY
-- =========================================
function LITHOS_SEG7.RegisterDisplay(name, digits)
    LITHOS_SEG7.Displays[name] = digits
end

-- =========================================
-- SET SINGLE DIGIT
-- =========================================
function LITHOS_SEG7.SetDigit(entName, skin)
    local ent = LITHOS_SEG7.GetEnt(entName)
    if not IsValid(ent) then
        print('[LITHOS_SEG7] Missing entity: ' .. entName)
        return
    end

    ent:SetSkin(skin)
end

-- =========================================
-- MAIN DISPLAY FUNCTION
-- =========================================
function LITHOS_SEG7.SetDisplay(name, value)
    local digits = LITHOS_SEG7.Displays[name]
    if not digits then
        print('[LITHOS_SEG7] Unknown display: ' .. tostring(name))
        return
    end

    value = math.floor(tonumber(value) or 0)
    local negative = value < 0
    value = math.abs(value)
    local str = tostring(value)
    -- Clear display
    for i = 1, #digits do
        LITHOS_SEG7.SetDigit(digits[i], LITHOS_SEG7.BLANK)
    end

    local digitIndex = 1
    -- Right-to-left fill
    for i = #str, 1, -1 do
        local num = tonumber(str:sub(i, i))
        if digits[digitIndex] then LITHOS_SEG7.SetDigit(digits[digitIndex], num) end
        digitIndex = digitIndex + 1
    end

    -- Minus sign
    if negative and digits[digitIndex] then LITHOS_SEG7.SetDigit(digits[digitIndex], LITHOS_SEG7.MINUS) end
end

-- =========================================
-- BIND LIVE VALUE
-- =========================================
function LITHOS_SEG7.BindDisplay(name, getter)
    LITHOS_SEG7.Bindings[name] = getter
end

-- =========================================
-- AUTO UPDATE LOOP
-- =========================================
function LITHOS_SEG7.UpdateAll()
    for displayName, getter in pairs(LITHOS_SEG7.Bindings) do
        local ok, value = pcall(getter)
        if ok then
            LITHOS_SEG7.SetDisplay(displayName, value)
        else
            print('[LITHOS_SEG7] Getter failed for ' .. displayName)
            print(value)
        end
    end
end

-- =========================================
-- START UPDATE TIMER
-- =========================================
function LITHOS_SEG7.Start()
    if timer.Exists('LITHOS_SEG7_UpdateTimer') then timer.Remove('LITHOS_SEG7_UpdateTimer') end
    timer.Create('LITHOS_SEG7_UpdateTimer', 0.1, 0, function() LITHOS_SEG7.UpdateAll() end)
    print('[LITHOS_SEG7] Started')
end