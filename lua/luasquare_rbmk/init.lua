include('luasquare_module/cleanup.lua')

if LUASQUARE_RBMK_CORE_LOADED then return end
LUASQUARE_RBMK_CORE_LOADED = true

util.AddNetworkString('RBMK_DebugState')
LUASQUARE_RBMK = {Instances = {}}
local REACTORS = LUASQUARE_RBMK
local installers = {}
local installEndpoints = include('luasquare_rbmk/endpoints.lua')
for _, name in ipairs({'defs', 'fueltypes', 'selector', 'channels', 'reactor', 'flux', 'heat', 'fuel', 'control', 'steam', 'debug'}) do
    installers[#installers + 1] = include('luasquare_rbmk/' .. name .. '.lua')
end

function REACTORS.Create(id)
    if type(id) ~= 'string' or #id > 128 or not id:match('^[a-z0-9_][a-z0-9_.%-]*$') then return nil, 'invalid core ID' end
    if REACTORS.Instances[id] then return nil, 'duplicate core ID' end
    local core = {Id = id, Timers = {}, EndpointReleases = {}}
    function core.TimerName(suffix)
        local name = 'RBMK_Instance_' .. #id .. '_' .. id .. '_' .. suffix
        core.Timers[name] = true
        return name
    end
    function core.Stop()
        for name in pairs(core.Timers) do timer.Remove(name) end
        core.Timers = {}
    end
    function core.Destroy()
        if core.Destroyed then return end
        core.Stop()
        for _, release in ipairs(core.EndpointReleases or {}) do release() end
        if core.Selector then core.Selector.Clear() end
        for _, valve in ipairs(core.BlowoutValves or {}) do
            if IsValid(valve.ent) then valve.ent:Fire('Close') end
        end
        for _, rod in pairs(core.Rods or {}) do if core.HoldRodVisual then core.HoldRodVisual(rod) end end
        core.Destroyed = true
        if core.ClearReactorData then core.ClearReactorData() end
        REACTORS.Instances[id] = nil
    end
    REACTORS.Instances[id] = core
    local ok, err = pcall(function()
        for _, install in ipairs(installers) do install(core) end
        installEndpoints(core)
    end)
    if not ok then
        core.Destroy()
        return nil, tostring(err)
    end
    return core
end

function REACTORS.Get(id) return REACTORS.Instances[id] end

function REACTORS.DestroyAll()
    local cores = {}
    for _, core in pairs(REACTORS.Instances) do cores[#cores + 1] = core end
    for _, core in ipairs(cores) do core.Destroy() end
end
