if RBMK_CORE_LOADED then return end
RBMK_CORE_LOADED = true

include('rbmk/defs.lua')
include('rbmk/fueltypes.lua')
include('rbmk/channels.lua')
include('rbmk/reactor.lua')
include('rbmk/flux.lua')
include('rbmk/heat.lua')
include('rbmk/fuel.lua')
include('rbmk/steam.lua')
include('rbmk/debug.lua')
