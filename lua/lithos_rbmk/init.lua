if LITHOS_RBMK_CORE_LOADED then return end
LITHOS_RBMK_CORE_LOADED = true

if true then
    util.AddNetworkString('RBMK_DebugState')
end

include('lithos_rbmk/defs.lua')
include('lithos_rbmk/fueltypes.lua')
include('lithos_rbmk/channels.lua')
include('lithos_rbmk/reactor.lua')
include('lithos_rbmk/flux.lua')
include('lithos_rbmk/heat.lua')
include('lithos_rbmk/fuel.lua')
include('lithos_rbmk/control.lua')
include('lithos_rbmk/steam.lua')
include('lithos_rbmk/debug.lua')
