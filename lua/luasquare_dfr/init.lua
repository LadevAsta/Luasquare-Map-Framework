include('luasquare_module/cleanup.lua')

if LUASQUARE_DFR_CORE_LOADED then return end
LUASQUARE_DFR_CORE_LOADED = true

DFR = DFR or {}
DFR.Version = DFR.Version or 'foundation-0.1'

include('luasquare_module/sourcebinding.lua')
include('luasquare_module/controlbinding.lua')
include('luasquare_module/machinery.lua')
include('luasquare_module/timeline.lua')

include('luasquare_dfr/config.lua')
include('luasquare_dfr/runtime/debug.lua')
include('luasquare_dfr/runtime/state.lua')
include('luasquare_dfr/runtime/binding.lua')
include('luasquare_dfr/runtime/machinery.lua')
include('luasquare_dfr/runtime/control.lua')
include('luasquare_dfr/runtime/timeline.lua')

include('luasquare_dfr/reactor/corevisual.lua')
include('luasquare_dfr/reactor/reactormachine.lua')
include('luasquare_dfr/reactor/directorbeam.lua')
include('luasquare_dfr/reactor/stabilizer.lua')
include('luasquare_dfr/superstructure/catalyzer.lua')

include('luasquare_dfr/procedure/startup.lua')
include('luasquare_dfr/procedure/pre_annihilation.lua')
include('luasquare_dfr/presentation/telemetry.lua')
include('luasquare_dfr/runtime/simulation.lua')

DFR.Log('Core loaded')
