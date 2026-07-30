include('luasquare_module/cleanup.lua')

if LUASQUARE_POWERPLANT_CORE_LOADED then return end
LUASQUARE_POWERPLANT_CORE_LOADED = true
LUASQUARE_POWERPLANT = LUASQUARE_POWERPLANT or {}
LUASQUARE_POWERPLANT.EntityCache = LUASQUARE_POWERPLANT.EntityCache or {}

if true then
    util.AddNetworkString('LUASQUARE_PowerplantDebugState')
end

function LUASQUARE_POWERPLANT.GetNamedEntity(name)
    if not name or name == '' then return nil end
    local cached = LUASQUARE_POWERPLANT.EntityCache[name]
    if IsValid(cached) then return cached end

    local ent = ents.FindByName(name)[1]
    if IsValid(ent) then
        LUASQUARE_POWERPLANT.EntityCache[name] = ent
        return ent
    end

    return nil
end

function LUASQUARE_POWERPLANT.ResolveMapPosition(value, fallback)
    if isvector and isvector(value) then return value end
    if isstring and isstring(value) then
        local ent = LUASQUARE_POWERPLANT.GetNamedEntity(value)
        if IsValid(ent) then return ent:GetPos() end
        return fallback
    end

    return fallback
end

function LUASQUARE_POWERPLANT.ResolveMonitorPos(data)
    if not data then return nil end

    local target = data.monitorTarget or data.monitorEntity or data.monitorName
    local pos = LUASQUARE_POWERPLANT.ResolveMapPosition(target, nil)
    pos = pos or LUASQUARE_POWERPLANT.ResolveMapPosition(data.monitorPos, nil)
    if not pos then return nil end

    return pos + (data.monitorOffset or Vector(0, 0, 0))
end

include('luasquare_powerplant/fluidnetwork.lua')
include('luasquare_powerplant/fluidvalve.lua')
include('luasquare_powerplant/fluidpump.lua')
include('luasquare_powerplant/heatexchanger.lua')
include('luasquare_powerplant/powergrid.lua')
include('luasquare_powerplant/condenser.lua')
include('luasquare_powerplant/deaerator.lua')
include('luasquare_powerplant/steamseparator.lua')
include('luasquare_powerplant/turbine.lua')
include('luasquare_powerplant/powergenerator.lua')
include('luasquare_powerplant/dieselgenerator.lua')
include('luasquare_powerplant/coolingtower.lua')
include('luasquare_powerplant/debug.lua')
