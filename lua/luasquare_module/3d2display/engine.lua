if LUASQUARE_3D2D_CORE_LOADED then return end
LUASQUARE_3D2D_CORE_LOADED = true

LUASQUARE_3D2D = LUASQUARE_3D2D or {}
LUASQUARE_3D2D.Schema = 'luasquare.3d2display/v1'
LUASQUARE_3D2D.TickInterval = LUASQUARE_3D2D.TickInterval or 0.1
LUASQUARE_3D2D.DefaultScale = LUASQUARE_3D2D.DefaultScale or 0.1
LUASQUARE_3D2D.DefaultSurfaceOffset = LUASQUARE_3D2D.DefaultSurfaceOffset or 0.05
LUASQUARE_3D2D.SourceRoot = 'data_static/luasquare/3d2display'
LUASQUARE_3D2D.DraftRoot = 'luasquare/3d2display/drafts'

local sharedFiles = {
    'luasquare_module/3d2display/shared.lua',
    'luasquare_module/3d2display/compiler.lua'
}

local clientFiles = {
    'luasquare_module/editor_theme.lua',
    'luasquare_module/3d2display/renderer.lua',
    'luasquare_module/3d2display/elements.lua',
    'luasquare_module/3d2display/network_client.lua',
    'luasquare_module/3d2display/interaction_client.lua',
    'luasquare_module/3d2display/editor.lua',
    'luasquare_module/3d2display/theme_editor.lua'
}

if SERVER then
    for _, path in ipairs(sharedFiles) do AddCSLuaFile(path) end
    for _, path in ipairs(clientFiles) do AddCSLuaFile(path) end
end

for _, path in ipairs(sharedFiles) do include(path) end

if SERVER then
    include('luasquare_module/3d2display/runtime.lua')
    include('luasquare_module/3d2display/network_server.lua')
    include('luasquare_module/3d2display/interaction_server.lua')
else
    for _, path in ipairs(clientFiles) do include(path) end
end
