local MAP = LUASQUARE_MAP

-- Decode strict JSON ourselves: preserve empty arrays versus objects and never
-- silently discard null values, as util.JSONToTable does.
local null = {}
function MAP.ValidateJSON(text, byteLimit, stringLimit)
    if type(text) ~= 'string' or #text > (byteLimit or MAP.Limits.bytes or 1048576) then return false, 'source exceeds byte limit' end
    local cursor, values, length = 1, 0, #text
    local function problem(message) error('byte ' .. cursor .. ': ' .. message, 0) end
    local function skip()
        while text:sub(cursor, cursor):match('[ \t\r\n]') do cursor = cursor + 1 end
    end
    local function utf8(code)
        if code < 128 then return string.char(code) end
        if code < 2048 then return string.char(192 + math.floor(code / 64), 128 + code % 64) end
        if code < 65536 then return string.char(224 + math.floor(code / 4096), 128 + math.floor(code / 64) % 64, 128 + code % 64) end
        return string.char(240 + math.floor(code / 262144), 128 + math.floor(code / 4096) % 64, 128 + math.floor(code / 64) % 64, 128 + code % 64)
    end
    local function stringToken()
        local start = cursor
        cursor = cursor + 1
        local pieces = {}
        while cursor <= length do
            local byte = text:byte(cursor)
            if byte == 34 then
                cursor = cursor + 1
                if cursor - start > (stringLimit or MAP.Limits.string) * 6 + 2 then problem('string exceeds limit') end
                return table.concat(pieces)
            elseif byte == 92 then
                local escaped = text:sub(cursor + 1, cursor + 1)
                local escapes = {['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
                if escaped == 'u' then
                    local digits = text:sub(cursor + 2, cursor + 5)
                    if #digits ~= 4 or digits:find('[^%da-fA-F]') then problem('invalid Unicode escape') end
                    local code = tonumber(digits, 16)
                    cursor = cursor + 6
                    if code >= 55296 and code <= 56319 then
                        if text:sub(cursor, cursor + 1) ~= '\\u' then problem('missing low surrogate') end
                        local lowDigits = text:sub(cursor + 2, cursor + 5)
                        local low = #lowDigits == 4 and not lowDigits:find('[^%da-fA-F]') and tonumber(lowDigits, 16)
                        if not low or low < 56320 or low > 57343 then problem('invalid low surrogate') end
                        code = 65536 + (code - 55296) * 1024 + low - 56320
                        cursor = cursor + 6
                    elseif code >= 56320 and code <= 57343 then problem('unexpected low surrogate') end
                    pieces[#pieces + 1] = utf8(code)
                elseif escapes[escaped] then pieces[#pieces + 1] = escapes[escaped]; cursor = cursor + 2
                else problem('invalid escape') end
            elseif byte < 32 then problem('unescaped control character')
            elseif byte >= 128 then
                local count = byte >= 194 and byte <= 223 and 2 or byte >= 224 and byte <= 239 and 3 or byte >= 240 and byte <= 244 and 4
                if not count then problem('invalid UTF-8') end
                local second = text:byte(cursor + 1)
                if not second or (byte == 224 and second < 160) or (byte == 237 and second >= 160)
                    or (byte == 240 and second < 144) or (byte == 244 and second >= 144) then problem('invalid UTF-8') end
                for offset = 1, count - 1 do
                    local continuation = text:byte(cursor + offset)
                    if not continuation or continuation < 128 or continuation > 191 then problem('invalid UTF-8') end
                end
                pieces[#pieces + 1] = text:sub(cursor, cursor + count - 1); cursor = cursor + count
            else pieces[#pieces + 1] = string.char(byte); cursor = cursor + 1 end
        end
        problem('unterminated string')
    end
    local parse
    parse = function(depth)
        values = values + 1
        if depth > MAP.Limits.depth or values > MAP.Limits.values then problem('source tree exceeds limits') end
        skip()
        local token = text:sub(cursor, cursor)
        if token == '"' then return stringToken()
        elseif token == '{' then
            cursor = cursor + 1; skip()
            local keys, result = {}, MAP.Object()
            if text:sub(cursor, cursor) == '}' then cursor = cursor + 1; return result end
            while true do
                if text:sub(cursor, cursor) ~= '"' then problem('expected object key') end
                local key = stringToken()
                if keys[key] then problem('duplicate object key') end
                keys[key] = true
                skip()
                if text:sub(cursor, cursor) ~= ':' then problem('expected colon') end
                cursor = cursor + 1; result[key] = parse(depth + 1); skip()
                local separator = text:sub(cursor, cursor)
                cursor = cursor + 1
                if separator == '}' then return result end
                if separator ~= ',' then problem('expected comma or closing brace') end
                skip()
            end
        elseif token == '[' then
            cursor = cursor + 1; skip()
            local result = MAP.Array()
            if text:sub(cursor, cursor) == ']' then cursor = cursor + 1; return result end
            while true do
                result[#result + 1] = parse(depth + 1); skip()
                local separator = text:sub(cursor, cursor)
                cursor = cursor + 1
                if separator == ']' then return result end
                if separator ~= ',' then problem('expected comma or closing bracket') end
            end
        elseif token == '-' or token:match('%d') then
            local start = cursor
            if token == '-' then cursor = cursor + 1 end
            if text:sub(cursor, cursor) == '0' then cursor = cursor + 1
            else
                if not text:sub(cursor, cursor):match('[1-9]') then problem('invalid number') end
                repeat cursor = cursor + 1 until not text:sub(cursor, cursor):match('%d')
            end
            if text:sub(cursor, cursor) == '.' then
                cursor = cursor + 1
                if not text:sub(cursor, cursor):match('%d') then problem('fraction requires digits') end
                repeat cursor = cursor + 1 until not text:sub(cursor, cursor):match('%d')
            end
            if text:sub(cursor, cursor):match('[eE]') then
                cursor = cursor + 1
                if text:sub(cursor, cursor):match('[+-]') then cursor = cursor + 1 end
                if not text:sub(cursor, cursor):match('%d') then problem('exponent requires digits') end
                repeat cursor = cursor + 1 until not text:sub(cursor, cursor):match('%d')
            end
            local number = tonumber(text:sub(start, cursor - 1))
            if not MAP.Finite(number) then problem('nonfinite number') end
            return number
        else
            for _, literal in ipairs({'true', 'false', 'null'}) do
                if text:sub(cursor, cursor + #literal - 1) == literal then
                    cursor = cursor + #literal
                    if literal == 'null' then return null end
                    return literal == 'true'
                end
            end
            problem('unexpected token')
        end
    end
    local ok, result = pcall(function()
        local value = parse(0); skip(); if cursor <= length then problem('trailing content') end
        return value
    end)
    if not ok then return false, result end
    return true, nil, result
end

function MAP.DecodeJSON(text, byteLimit, stringLimit)
    local valid, err, source = MAP.ValidateJSON(text, byteLimit, stringLimit)
    if not valid then return nil, err end
    local function hasNull(value)
        if value == null then return true end
        if type(value) == 'table' then for _, child in pairs(value) do if hasNull(child) then return true end end end
        return false
    end
    if hasNull(source) then return nil, 'null is not a source value; omit optional fields instead' end
    if type(source) ~= 'table' or not MAP.SafeTree(source, stringLimit) then return nil, 'invalid or excessive source tree' end
    return source
end
