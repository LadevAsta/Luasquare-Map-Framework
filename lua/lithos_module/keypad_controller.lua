if LITHOS_KEYPAD_CORE_LOADED then return end
LITHOS_KEYPAD_CORE_LOADED = true
LITHOS_KEYPAD = LITHOS_KEYPAD or {}
LITHOS_KEYPAD.Pads = {}
-- REGISTER
function LITHOS_KEYPAD.RegisterKeypad(name, data)
    LITHOS_KEYPAD.Pads[name] = {
        value = '',
        maxDigits = data.maxDigits or 3,
        maxValue = data.maxValue or 10000,
        display = data.display,
        onSubmit = data.onSubmit
    }

    LITHOS_KEYPAD.UpdateDisplay(name)
end

-- UPDATE DISPLAY
function LITHOS_KEYPAD.UpdateDisplay(name)
    local pad = LITHOS_KEYPAD.Pads[name]
    if not pad then return end
    local num = tonumber(pad.value) or 0
    if pad.display then LITHOS_SEG7.SetDisplay(pad.display, num) end
end

-- PRESS DIGIT
function LITHOS_KEYPAD.Press(name, digit)
    local pad = LITHOS_KEYPAD.Pads[name]
    if not pad then return end
    digit = tostring(digit)
    if #pad.value >= pad.maxDigits then return end
    pad.value = pad.value .. digit
    local num = tonumber(pad.value) or 0
    if num >= pad.maxValue then pad.value = tostring(pad.maxValue) end
    LITHOS_KEYPAD.UpdateDisplay(name)
end

-- BACKSPACE
function LITHOS_KEYPAD.Backspace(name)
    local pad = LITHOS_KEYPAD.Pads[name]
    if not pad then return end
    pad.value = string.sub(pad.value, 1, -2)
    LITHOS_KEYPAD.UpdateDisplay(name)
end

-- Get value
function LITHOS_KEYPAD.GetValue(name)
    local pad = LITHOS_KEYPAD.Pads[name]
    if not pad then return 0 end
    return tonumber(pad.value) or 0
end

-- CLEAR
function LITHOS_KEYPAD.Clear(name)
    local pad = LITHOS_KEYPAD.Pads[name]
    if not pad then return end
    pad.value = ''
    LITHOS_KEYPAD.UpdateDisplay(name)
end

-- SUBMIT
function LITHOS_KEYPAD.Submit(name)
    local pad = LITHOS_KEYPAD.Pads[name]
    if not pad then return end
    local value = tonumber(pad.value) or 0
    if pad.onSubmit then
        local ok, err = pcall(pad.onSubmit, value)
        if not ok then
            print('[LITHOS_KEYPAD] Submit failed:')
            print(err)
        end
    end

    LITHOS_KEYPAD.Clear(name)
end

print('[LITHOS_KEYPAD] Loaded')