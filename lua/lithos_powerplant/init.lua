if LITHOS_POWERPLANT_CORE_LOADED then return end
LITHOS_POWERPLANT_CORE_LOADED = true
LITHOS_POWERPLANT = LITHOS_POWERPLANT or {}

if true then
    util.AddNetworkString('LITHOS_PowerplantDebugState')
end

include('lithos_powerplant/fluidnetwork.lua')
include('lithos_powerplant/fluidvalve.lua')
include('lithos_powerplant/fluidpump.lua')
include('lithos_powerplant/condenser.lua')
include('lithos_powerplant/debug.lua')
