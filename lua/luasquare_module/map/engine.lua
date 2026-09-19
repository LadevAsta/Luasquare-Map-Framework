if LUASQUARE_MAP_CORE_LOADED then return end
LUASQUARE_MAP_CORE_LOADED = true
LUASQUARE_MAP = LUASQUARE_MAP or {}
local MAP = LUASQUARE_MAP
MAP.Schema = 'luasquare.map/v1'
MAP.ComponentSchema = 'luasquare.components/v1'
MAP.Types = MAP.Types or {}
MAP.Packages = MAP.Packages or {}
MAP.Instances = MAP.Instances or {}
MAP.Limits = {bytes = 1024 * 1024, totalBytes = 8 * 1024 * 1024, nodes = 2048,
    links = 8192, packs = 128, depth = 24, values = 131072, string = 4096}
local shared = {'shared.lua', 'json.lua', 'compiler.lua', 'document.lua'}
local client = {'network_client.lua', 'editor.lua'}
if SERVER then
    AddCSLuaFile('luasquare_module/map/engine.lua')
    for _, name in ipairs(shared) do AddCSLuaFile('luasquare_module/map/' .. name) end
    AddCSLuaFile('luasquare_module/editor_theme.lua')
    for _, name in ipairs(client) do AddCSLuaFile('luasquare_module/map/' .. name) end
end
for _, name in ipairs(shared) do include('luasquare_module/map/' .. name) end
if SERVER then
    include('luasquare_module/cleanup.lua')
    include('luasquare_module/map/runtime.lua')
    include('luasquare_module/map/capabilities.lua')
    include('luasquare_module/map/packages.lua')
    include('luasquare_module/map/network_server.lua')
else
    include('luasquare_module/editor_theme.lua')
    for _, name in ipairs(client) do include('luasquare_module/map/' .. name) end
end
