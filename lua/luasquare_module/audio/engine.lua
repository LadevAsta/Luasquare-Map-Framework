if LUASQUARE_AUDIO_CORE_LOADED then return end
LUASQUARE_AUDIO_CORE_LOADED = true

if SERVER then AddCSLuaFile() end

LUASQUARE_AUDIO = LUASQUARE_AUDIO or {}
local AUDIO = LUASQUARE_AUDIO

AUDIO.Schema = 'luasquare.audio/v1'
AUDIO.SourceRoot = 'data_static/luasquare/audio'
AUDIO.DraftRoot = 'luasquare/audio/drafts'
AUDIO.TickInterval = 0.05
AUDIO.NetChunkBytes = 48000
AUDIO.MaxCatalogBytes = 4 * 1024 * 1024

local sharedFiles = {
    'luasquare_module/audio/shared.lua',
    'luasquare_module/audio/compiler.lua'
}
local clientFiles = {
    'luasquare_module/editor_theme.lua',
    'luasquare_module/audio/network_client.lua',
    'luasquare_module/audio/music_client.lua',
    'luasquare_module/audio/subtitle_client.lua',
    'luasquare_module/audio/settings.lua',
    'luasquare_module/audio/editor_common.lua',
    'luasquare_module/audio/sound_editor.lua',
    'luasquare_module/audio/subtitle_editor.lua',
    'luasquare_module/audio/pa_editor.lua'
}

if SERVER then
    for _, path in ipairs(sharedFiles) do AddCSLuaFile(path) end
    for _, path in ipairs(clientFiles) do AddCSLuaFile(path) end
end
for _, path in ipairs(sharedFiles) do include(path) end

if SERVER then
    include('luasquare_module/audio/runtime.lua')
    include('luasquare_module/audio/network_server.lua')
    include('luasquare_module/audio/timeline_adapter.lua')
    AUDIO.LoadMapSources(game.GetMap())
else
    for _, path in ipairs(clientFiles) do include(path) end
end
