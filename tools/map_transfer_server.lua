LUASQUARE_MAP = {
    Limits = {bytes = 1048576, values = 131072, depth = 24, string = 4096}
}
dofile('lua/luasquare_module/map/shared.lua')
dofile('lua/luasquare_module/map/json.lua')

local source = assert(LUASQUARE_MAP.DecodeJSON(TRANSFER_SOURCE))
local sourceText = assert(LUASQUARE_MAP.CanonicalJSON(source))
TRANSFER_ENVELOPE = assert(LUASQUARE_MAP.CanonicalJSON({sourceText = sourceText}, LUASQUARE_MAP.Limits.bytes))
