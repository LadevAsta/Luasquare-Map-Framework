if LUASQUARE_POWERPLANT_CORE_LOADED then return end
LUASQUARE_POWERPLANT_CORE_LOADED = true
LUASQUARE_POWERPLANT = LUASQUARE_POWERPLANT or {}

if true then
    util.AddNetworkString('LUASQUARE_PowerplantDebugState')
end

include('luasquare_powerplant/fluidnetwork.lua')
include('luasquare_powerplant/fluidvalve.lua')
include('luasquare_powerplant/fluidpump.lua')
include('luasquare_powerplant/condenser.lua')
include('luasquare_powerplant/debug.lua')
