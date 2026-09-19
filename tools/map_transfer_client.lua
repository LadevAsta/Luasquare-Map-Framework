LUASQUARE_MAP = {
    Limits = {bytes = 1048576, values = 131072, depth = 24, string = 4096}
}
dofile('lua/luasquare_module/map/shared.lua')
dofile('lua/luasquare_module/map/json.lua')

local envelope = assert(LUASQUARE_MAP.DecodeJSON(TRANSFER_ENVELOPE, nil, LUASQUARE_MAP.Limits.bytes))
local source = assert(LUASQUARE_MAP.DecodeJSON(envelope.sourceText))
for _, key in ipairs({'fuelPresets', 'tags', 'links'}) do
    assert(LUASQUARE_MAP.IsArray(source[key]) and next(source[key]) == nil, key .. ' must remain an empty array')
end
for _, key in ipairs({'defaults', 'overrides'}) do
    assert(type(source[key]) == 'table' and not LUASQUARE_MAP.IsArray(source[key]) and next(source[key]) == nil,
        key .. ' must remain an empty object')
end
TRANSFER_RESULT = assert(LUASQUARE_MAP.CanonicalJSON(source))
