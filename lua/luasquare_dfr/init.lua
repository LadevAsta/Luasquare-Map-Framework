include('luasquare_module/cleanup.lua')

if LUASQUARE_DFR_CORE_LOADED then return end
LUASQUARE_DFR_CORE_LOADED = true

DFR = DFR or {}
DFR.Version = DFR.Version or 'foundation-0.1'

include('luasquare_module/sourcebinding.lua')
include('luasquare_module/controlbinding.lua')
include('luasquare_module/machinery.lua')

include('luasquare_dfr/config.lua')
include('luasquare_dfr/debug.lua')
include('luasquare_dfr/state.lua')
include('luasquare_dfr/mapbinding.lua')
include('luasquare_dfr/machinery.lua')
include('luasquare_dfr/control.lua')
include('luasquare_dfr/reactormachine.lua')
include('luasquare_dfr/corevisual.lua')
include('luasquare_dfr/startup.lua')
include('luasquare_dfr/telemetry.lua')
include('luasquare_dfr/sim.lua')

DFR.Log('Core loaded')
