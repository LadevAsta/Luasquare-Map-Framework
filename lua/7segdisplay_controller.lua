if SEG7_CORE_LOADED then return end
SEG7_CORE_LOADED = true

SEG7 = SEG7 or {}

SEG7.Displays = SEG7.Displays or {}
SEG7.Bindings = SEG7.Bindings or {}
SEG7.EntityCache = SEG7.EntityCache or {}

SEG7.BLANK = 10
SEG7.MINUS = 11

-- =========================================
-- ENTITY CACHE
-- =========================================

function SEG7.GetEnt(name)

    local cached = SEG7.EntityCache[name]

    if IsValid(cached) then
        return cached
    end

    local ent = ents.FindByName(name)[1]

    if IsValid(ent) then
        SEG7.EntityCache[name] = ent
    end

    return ent

end

-- =========================================
-- REGISTER DISPLAY
-- =========================================

function SEG7.RegisterDisplay(name, digits)

    SEG7.Displays[name] = digits

end

-- =========================================
-- SET SINGLE DIGIT
-- =========================================

function SEG7.SetDigit(entName, skin)

    local ent = SEG7.GetEnt(entName)

    if not IsValid(ent) then
        print('[SEG7] Missing entity: ' .. entName)
        return
    end

    ent:SetSkin(skin)

end

-- =========================================
-- MAIN DISPLAY FUNCTION
-- =========================================

function SEG7.SetDisplay(name, value)

    local digits = SEG7.Displays[name]

    if not digits then
        print('[SEG7] Unknown display: ' .. tostring(name))
        return
    end

    value = math.floor(tonumber(value) or 0)

    local negative = value < 0

    value = math.abs(value)

    local str = tostring(value)

    -- Clear display
    for i = 1, #digits do
        SEG7.SetDigit(digits[i], SEG7.BLANK)
    end

    local digitIndex = 1

    -- Right-to-left fill
    for i = #str, 1, -1 do

        local num = tonumber(str:sub(i, i))

        if digits[digitIndex] then
            SEG7.SetDigit(digits[digitIndex], num)
        end

        digitIndex = digitIndex + 1

    end

    -- Minus sign
    if negative and digits[digitIndex] then
        SEG7.SetDigit(digits[digitIndex], SEG7.MINUS)
    end

end

-- =========================================
-- BIND LIVE VALUE
-- =========================================

function SEG7.BindDisplay(name, getter)

    SEG7.Bindings[name] = getter

end

-- =========================================
-- AUTO UPDATE LOOP
-- =========================================

function SEG7.UpdateAll()

    for displayName, getter in pairs(SEG7.Bindings) do

        local ok, value = pcall(getter)

        if ok then
            SEG7.SetDisplay(displayName, value)
        else
            print('[SEG7] Getter failed for ' .. displayName)
            print(value)
        end

    end

end

-- =========================================
-- START UPDATE TIMER
-- =========================================

function SEG7.Start()

    if timer.Exists('SEG7_UpdateTimer') then
        timer.Remove('SEG7_UpdateTimer')
    end

    timer.Create(
        'SEG7_UpdateTimer',
        0.1,
        0,
        function()

            SEG7.UpdateAll()

        end
    )

    print('[SEG7] Started')

end