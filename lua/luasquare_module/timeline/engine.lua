if LUASQUARE_TIMELINE_CORE_LOADED then return end
LUASQUARE_TIMELINE_CORE_LOADED = true

if SERVER then AddCSLuaFile() end

LUASQUARE_TIMELINE = LUASQUARE_TIMELINE or {}
local TIMELINE = LUASQUARE_TIMELINE

TIMELINE.Schema = 'luasquare.timeline/v1'
TIMELINE.SourceRoot = 'data_static/luasquare_timeline'
TIMELINE.DraftRoot = 'luasquare_timeline/drafts'
TIMELINE.TickInterval = TIMELINE.TickInterval or 0.05
TIMELINE.MaxPreviewBytes = 512 * 1024
TIMELINE.NetChunkBytes = 48000

local sharedFiles = {
    'luasquare_module/timeline/shared.lua',
    'luasquare_module/timeline/compiler.lua'
}

local clientFiles = {
    'luasquare_module/editor_theme.lua',
    'luasquare_module/timeline/network_client.lua',
    'luasquare_module/timeline/audio_preview.lua',
    'luasquare_module/timeline/editor.lua'
}

if SERVER then
    for _, path in ipairs(sharedFiles) do AddCSLuaFile(path) end
    for _, path in ipairs(clientFiles) do AddCSLuaFile(path) end
end

for _, path in ipairs(sharedFiles) do include(path) end

if SERVER then
    include('luasquare_module/timeline/runtime.lua')
    include('luasquare_module/timeline/network_server.lua')
else
    for _, path in ipairs(clientFiles) do include(path) end
end
