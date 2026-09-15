if LUASQUARE_ANNUNCIATOR_CORE_LOADED then return end
LUASQUARE_ANNUNCIATOR_CORE_LOADED = true

if SERVER then AddCSLuaFile() end

LUASQUARE_ANNUNCIATOR = LUASQUARE_ANNUNCIATOR or {}
local ANN = LUASQUARE_ANNUNCIATOR

ANN.Schema = 'luasquare.annunciator/v1'
ANN.SourceRoot = 'data_static/luasquare/annunciator'
ANN.DraftRoot = 'luasquare/annunciator/drafts'
ANN.TickInterval = 0.25
ANN.NetChunkBytes = 48000
ANN.MaxSnapshotBytes = 512 * 1024
ANN.MaxSourceBytes = 2 * 1024 * 1024
ANN.MaxGroups = 64
ANN.MaxAlarms = 512
ANN.VolumeConVar = 'luasquare_audio_annunciator_volume'

local sharedFiles = {
    'luasquare_module/annunciator/shared.lua',
    'luasquare_module/annunciator/compiler.lua'
}
local clientFiles = {
    'luasquare_module/editor_theme.lua',
    'luasquare_module/annunciator/network_client.lua',
    'luasquare_module/annunciator/editor.lua'
}

if SERVER then
    for _, path in ipairs(sharedFiles) do AddCSLuaFile(path) end
    for _, path in ipairs(clientFiles) do AddCSLuaFile(path) end
end
for _, path in ipairs(sharedFiles) do include(path) end

if SERVER then
    include('luasquare_module/annunciator/runtime.lua')
    include('luasquare_module/annunciator/network_server.lua')
else
    for _, path in ipairs(clientFiles) do include(path) end
end
