include('luasquare_module/cleanup.lua')

if LUASQUARE_RBMK_CORE_LOADED then return end
LUASQUARE_RBMK_CORE_LOADED = true

if true then
    util.AddNetworkString('RBMK_DebugState')
end

include('luasquare_rbmk/defs.lua')
include('luasquare_rbmk/fueltypes.lua')
include('luasquare_rbmk/channels.lua')
include('luasquare_rbmk/reactor.lua')
include('luasquare_rbmk/flux.lua')
include('luasquare_rbmk/heat.lua')
include('luasquare_rbmk/fuel.lua')
include('luasquare_rbmk/control.lua')
include('luasquare_rbmk/steam.lua')
include('luasquare_rbmk/debug.lua')
