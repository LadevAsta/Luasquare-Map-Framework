if LUASQUARE_CONTROL_CORE_LOADED then return end
LUASQUARE_CONTROL_CORE_LOADED = true
LUASQUARE_CONTROL = LUASQUARE_CONTROL or {}
local CONTROL = LUASQUARE_CONTROL
CONTROL.Schema = 'luasquare.control/v1'
CONTROL.MaxControls = 1024
CONTROL.MaxSourceBytes = 512 * 1024
CONTROL.MaxTransferBytes = 4 * 1024 * 1024
CONTROL.ChunkBytes = 48000
CONTROL.QueueSeconds = 2
CONTROL.AcknowledgementSeconds = 5
CONTROL.TickInterval = 0.05
CONTROL.Actions = CONTROL.Actions or {}
CONTROL.Predicates = CONTROL.Predicates or {}
CONTROL.Controls = CONTROL.Controls or {}
CONTROL.Operations = {'press', 'toggle', 'pressIn', 'pressOut', 'pressLock', 'pressInLock', 'pressOutLock', 'submitValue'}
local sharedFiles = {'shared.lua', 'compiler.lua', 'preview.lua'}
local clientFiles = {'network_client.lua', 'editor.lua'}
if SERVER then
    AddCSLuaFile('luasquare_module/control/engine.lua')
    AddCSLuaFile('luasquare_module/editor_theme.lua')
    for _, name in ipairs(sharedFiles) do AddCSLuaFile('luasquare_module/control/' .. name) end
    for _, name in ipairs(clientFiles) do AddCSLuaFile('luasquare_module/control/' .. name) end
end
for _, name in ipairs(sharedFiles) do include('luasquare_module/control/' .. name) end
if SERVER then
    include('luasquare_module/control/runtime.lua')
    include('luasquare_module/control/adapters.lua')
    include('luasquare_module/control/network_server.lua')
else
    include('luasquare_module/editor_theme.lua')
    for _, name in ipairs(clientFiles) do include('luasquare_module/control/' .. name) end
end
