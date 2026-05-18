if LUASQUARE_SEG7_CORE_LOADED then return end
LUASQUARE_SEG7_CORE_LOADED = true
LUASQUARE_SEG7 = LUASQUARE_SEG7 or {}
LUASQUARE_SEG7.Displays = LUASQUARE_SEG7.Displays or {}
LUASQUARE_SEG7.Bindings = LUASQUARE_SEG7.Bindings or {}
LUASQUARE_SEG7.EntityCache = LUASQUARE_SEG7.EntityCache or {}
LUASQUARE_SEG7.BLANK = 10
LUASQUARE_SEG7.MINUS = 11

LUASQUARE_SEG7.TickInterval = 0.1

-- =========================================
-- ENTITY CACHE
-- =========================================
function LUASQUARE_SEG7.GetEnt(name)
    local cached = LUASQUARE_SEG7.EntityCache[name]
    if IsValid(cached) then return cached end
    local ent = ents.FindByName(name)[1]
    if IsValid(ent) then LUASQUARE_SEG7.EntityCache[name] = ent end
    return ent
end

-- =========================================
-- REGISTER DISPLAY
-- =========================================
function LUASQUARE_SEG7.RegisterDisplay(name, digits)
    LUASQUARE_SEG7.Displays[name] = digits
end

-- =========================================
-- SET SINGLE DIGIT
-- =========================================
function LUASQUARE_SEG7.SetDigit(entName, skin)
    local ent = LUASQUARE_SEG7.GetEnt(entName)
    if not IsValid(ent) then
        print('[LUASQUARE_SEG7] Missing entity: ' .. entName)
        return
    end

    ent:SetSkin(skin)
end

-- =========================================
-- MAIN DISPLAY FUNCTION
-- =========================================
function LUASQUARE_SEG7.SetDisplay(name, value)
    local digits = LUASQUARE_SEG7.Displays[name]
    if not digits then
        print('[LUASQUARE_SEG7] Unknown display: ' .. tostring(name))
        return
    end

    value = math.floor(tonumber(value) or 0)
    local negative = value < 0
    value = math.abs(value)
    local str = tostring(value)
    -- Clear display
    for i = 1, #digits do
        LUASQUARE_SEG7.SetDigit(digits[i], LUASQUARE_SEG7.BLANK)
    end

    local digitIndex = 1
    -- Right-to-left fill
    for i = #str, 1, -1 do
        local num = tonumber(str:sub(i, i))
        if digits[digitIndex] then LUASQUARE_SEG7.SetDigit(digits[digitIndex], num) end
        digitIndex = digitIndex + 1
    end

    -- Minus sign
    if negative and digits[digitIndex] then LUASQUARE_SEG7.SetDigit(digits[digitIndex], LUASQUARE_SEG7.MINUS) end
end

-- =========================================
-- BIND LIVE VALUE
-- =========================================
function LUASQUARE_SEG7.BindDisplay(name, getter)
    LUASQUARE_SEG7.Bindings[name] = getter
end

-- =========================================
-- AUTO UPDATE LOOP
-- =========================================
function LUASQUARE_SEG7.UpdateAll()
    for displayName, getter in pairs(LUASQUARE_SEG7.Bindings) do
        local ok, value = pcall(getter)
        if ok then
            LUASQUARE_SEG7.SetDisplay(displayName, value)
        else
            print('[LUASQUARE_SEG7] Getter failed for ' .. displayName)
            print(value)
        end
    end
end

-- =========================================
-- START UPDATE TIMER
-- =========================================
function LUASQUARE_SEG7.Start()
    if timer.Exists('LUASQUARE_SEG7_UpdateTimer') then timer.Remove('LUASQUARE_SEG7_UpdateTimer') end
    timer.Create('LUASQUARE_SEG7_UpdateTimer', LUASQUARE_SEG7.TickInterval, 0, function() LUASQUARE_SEG7.UpdateAll() end)
    print('[LUASQUARE_SEG7] Started')
end