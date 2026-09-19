-- Existing Hammer lua_run entry point. Keep Run Code on Spawn enabled.
if not SERVER then return end
include('luasquare_module/cleanup.lua')
if LUASQUARE_FRAMEWORK_INITIALIZED then return end

-- Brush buttons finish initializing after run-on-spawn lua_run entities.
if not LUASQUARE_RBMK_BOOTSTRAP_READY then
    if not timer.Exists('LUASQUARE_RBMK_BOOTSTRAP_DEFER') then
        timer.Create('LUASQUARE_RBMK_BOOTSTRAP_DEFER', 0, 1, function()
            LUASQUARE_RBMK_BOOTSTRAP_READY = true
            local ok, err = pcall(include, 'luasquare_rbmk/bootstrapper/experiment_rbmk.lua')
            LUASQUARE_RBMK_BOOTSTRAP_READY = nil
            if not ok then ErrorNoHalt('[LUASQUARE MAP] Bootstrap failed: ' .. tostring(err) .. '\n') end
        end)
    end
    return
end

include('luasquare_module/map/engine.lua')
local selection = GetConVar('luasquare_map_manifest') or CreateConVar('luasquare_map_manifest', '', FCVAR_ARCHIVE,
    'Packed manifest path relative to data_static/luasquare/map; empty selects experiment_rbmk/main.json. Map reload required.')
local path = selection:GetString()
if path == '' then path = 'experiment_rbmk/main.json' end
local instance, err = LUASQUARE_MAP.Load(path)
if not instance then
    ErrorNoHalt('[LUASQUARE MAP] Plant inactive: ' .. tostring(err) .. '\nCorrect packed sources and reload the map.\n')
    return
end
LUASQUARE_FRAMEWORK_INITIALIZED = true
SetGlobal2Bool('LUASQUARE_FRAMEWORK_INITIALIZED_GLOBAL', true)
print('[LUASQUARE MAP] Activated ' .. instance.id .. ' from ' .. path)
