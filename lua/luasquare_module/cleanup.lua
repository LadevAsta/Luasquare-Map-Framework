if not SERVER then return end
if LUASQUARE_CLEANUP_LOADED then return end
LUASQUARE_CLEANUP_LOADED = true

LUASQUARE_CLEANUP = LUASQUARE_CLEANUP or {}

local extraGlobals = {}
local timerPrefixes = {
    'LUASQUARE_',
    'RBMK_',
    'DFR_'
}

local function startsWith(value, prefix)
    return string.sub(value, 1, #prefix) == prefix
end

local function shouldRemoveTimer(name)
    name = tostring(name or '')
    for _, prefix in ipairs(timerPrefixes) do
        if startsWith(name, prefix) then return true end
    end
    return false
end

local function removeRuntimeTimers()
    if not timer or not timer.GetTable then return end

    local names = {}
    for name in pairs(timer.GetTable() or {}) do
        if shouldRemoveTimer(name) then table.insert(names, name) end
    end

    for _, name in ipairs(names) do timer.Remove(name) end
end

local function removeRuntimeCommands()
    if not concommand or not concommand.GetTable or not concommand.Remove then return end

    local names = {}
    for name in pairs(concommand.GetTable() or {}) do
        if startsWith(string.lower(tostring(name or '')), 'luasquare_') then
            table.insert(names, name)
        end
    end

    for _, name in ipairs(names) do concommand.Remove(name) end
end

local function cancelRuntimeTimelines(reason)
    local timeline = LUASQUARE_TIMELINE
    if not timeline then return end

    if timeline.CancelAll then
        local ok, err = pcall(timeline.CancelAll, reason)
        if not ok then
            print('[LUASQUARE CLEANUP] Timeline cancellation failed: ' .. tostring(err))
        end
        return
    end

    if not timeline.Registries then return end

    for name, registry in pairs(timeline.Registries) do
        if registry and registry.CancelAll then
            local ok, err = pcall(registry.CancelAll, registry, reason)
            if not ok then
                print('[LUASQUARE CLEANUP] Timeline registry ' .. tostring(name)
                    .. ' cancellation failed: ' .. tostring(err))
            end
        end
    end
end

local function resetRuntimeAudio(reason)
    local audio = LUASQUARE_AUDIO
    if not audio or not audio.Reset then return end

    local ok, err = pcall(audio.Reset, reason)
    if not ok then
        print('[LUASQUARE CLEANUP] Audio reset failed: ' .. tostring(err))
    end
end

local function shouldClearGlobal(name)
    if name == 'RBMK' or name == 'DFR' then return true end
    if startsWith(name, 'LUASQUARE_') or startsWith(name, 'RBMK_') or startsWith(name, 'DFR_') then return true end
    return extraGlobals[name] and true or false
end

local function clearRuntimeGlobals()
    local names = {}
    for name in pairs(_G) do
        if type(name) == 'string' and shouldClearGlobal(name) then
            table.insert(names, name)
        end
    end

    for _, name in ipairs(names) do _G[name] = nil end
end

function LUASQUARE_CLEANUP.RegisterGlobal(name)
    name = tostring(name or '')
    if name == '' then return false end
    extraGlobals[name] = true
    return true
end

function LUASQUARE_CLEANUP.RegisterTimerPrefix(prefix)
    prefix = tostring(prefix or '')
    if prefix == '' then return false end
    table.insert(timerPrefixes, prefix)
    return true
end

local function resetRuntime(reason)
    reason = tostring(reason or 'manual reset')
    print('[LUASQUARE CLEANUP] Resetting framework runtime: ' .. reason)

    -- Let timeline owners restore their own machinery and presentation while
    -- the component registries and map entities are still available.
    cancelRuntimeTimelines(reason)
    -- Stop client music, Source loops, PA queues, subtitles, and soundscapes
    -- before their catalog and cached entity references are discarded.
    resetRuntimeAudio(reason)
    removeRuntimeTimers()
    removeRuntimeCommands()
    if SetGlobal2Bool then SetGlobal2Bool('LUASQUARE_FRAMEWORK_INITIALIZED_GLOBAL', false) end
    clearRuntimeGlobals()

    print('[LUASQUARE CLEANUP] Runtime cleared; waiting for the map bootstrap.')
end

LUASQUARE_CLEANUP.Reset = resetRuntime

hook.Add('PreCleanupMap', 'LUASQUARE_ResetFrameworkRuntime', function()
    -- Keep using the captured reset function even if a broken map bootstrap
    -- fails to recreate the public LUASQUARE_CLEANUP table.
    resetRuntime('PreCleanupMap')
end)
