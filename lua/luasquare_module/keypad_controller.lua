if LUASQUARE_KEYPAD_CORE_LOADED then return end
LUASQUARE_KEYPAD_CORE_LOADED = true
LUASQUARE_KEYPAD = LUASQUARE_KEYPAD or {}
LUASQUARE_KEYPAD.Pads = {}
-- REGISTER
function LUASQUARE_KEYPAD.RegisterKeypad(name, data)
    LUASQUARE_KEYPAD.Pads[name] = {
        value = data.initialValue and tostring(math.Clamp(math.floor(tonumber(data.initialValue) or 0), 0, data.maxValue or 10000)) or '',
        maxDigits = data.maxDigits or 3,
        maxValue = data.maxValue or 10000,
        display = data.display,
        onSubmit = data.onSubmit,
        clearOnSubmit = data.clearOnSubmit ~= false
    }

    LUASQUARE_KEYPAD.UpdateDisplay(name)
end

-- UPDATE DISPLAY
function LUASQUARE_KEYPAD.UpdateDisplay(name)
    local pad = LUASQUARE_KEYPAD.Pads[name]
    if not pad then return end
    local num = tonumber(pad.value) or 0
    if pad.display then LUASQUARE_SEG7.SetDisplay(pad.display, num) end
end

-- PRESS DIGIT
function LUASQUARE_KEYPAD.Press(name, digit)
    local pad = LUASQUARE_KEYPAD.Pads[name]
    if not pad then return end
    digit = tostring(digit)
    if #pad.value >= pad.maxDigits then return end
    pad.value = pad.value .. digit
    local num = tonumber(pad.value) or 0
    if num >= pad.maxValue then pad.value = tostring(pad.maxValue) end
    LUASQUARE_KEYPAD.UpdateDisplay(name)
end

-- BACKSPACE
function LUASQUARE_KEYPAD.Backspace(name)
    local pad = LUASQUARE_KEYPAD.Pads[name]
    if not pad then return end
    pad.value = string.sub(pad.value, 1, -2)
    LUASQUARE_KEYPAD.UpdateDisplay(name)
end

-- Get value
function LUASQUARE_KEYPAD.GetValue(name)
    local pad = LUASQUARE_KEYPAD.Pads[name]
    if not pad then return 0 end
    return tonumber(pad.value) or 0
end

-- CLEAR
function LUASQUARE_KEYPAD.Clear(name)
    local pad = LUASQUARE_KEYPAD.Pads[name]
    if not pad then return end
    pad.value = ''
    LUASQUARE_KEYPAD.UpdateDisplay(name)
end

-- SUBMIT
function LUASQUARE_KEYPAD.Submit(name)
    local pad = LUASQUARE_KEYPAD.Pads[name]
    if not pad then return end
    local value = tonumber(pad.value) or 0
    if pad.onSubmit then
        local ok, err = pcall(pad.onSubmit, value)
        if not ok then
            print('[LUASQUARE_KEYPAD] Submit failed:')
            print(err)
        end
    end

    if pad.clearOnSubmit then
        LUASQUARE_KEYPAD.Clear(name)
    else
        pad.value = tostring(math.Clamp(math.floor(value), 0, pad.maxValue))
        LUASQUARE_KEYPAD.UpdateDisplay(name)
    end
end

print('[LUASQUARE_KEYPAD] Loaded')
