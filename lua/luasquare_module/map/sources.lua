local MAP = LUASQUARE_MAP

MAP.RegisterType('timeline.owner', {package = 'presentation', label = 'Timeline procedure owner', fields = {
    targets = {type = 'array', default = MAP.Array(), maxItems = 128, items = {type = 'object', fields = {alias = {type = 'id', asset = 'name'}, component = {type = 'id', asset = 'timeline_component'}}}},
    timelines = {type = 'array', maxItems = 128, items = {type = 'object', fields = {slot = {type = 'id', asset = 'name'}, source = {type = 'string', maxLength = 240, asset = 'timeline_source'}}}}},
    validateDefinition = function(node, compiled)
        local slots, aliases, selected = {}, {}, {}
        for _, path in ipairs(compiled.sources.timeline or {}) do selected[path] = true end
        for _, item in ipairs(node.config.targets) do
            if aliases[item.alias] then return false, 'duplicate timeline child alias' end
            aliases[item.alias] = true
        end
        for _, item in ipairs(node.config.timelines) do
            if slots[item.slot] or not selected[MAP.SourcePath('timeline', item.source)] then return false, 'duplicate slot or timeline source not selected by manifest' end
            slots[item.slot] = true
        end
        return true
    end,
    register = function(instance, node)
        local children, slots = {}, {}
        for _, item in ipairs(node.config.targets) do children[item.alias] = item.component end
        for _, item in ipairs(node.config.timelines) do slots[item.slot] = true end
        if LUASQUARE_TIMELINE.Components[node.id] then return false, 'timeline owner ID collision' end
        LUASQUARE_TIMELINE.RegisterComponent(node.id, {type = 'map.procedure', label = node.id, children = children, actions = {}})
        instance:Own(function() LUASQUARE_TIMELINE.CancelOwner(node.id, 'map owner stopped') end, 'consumers')
        instance:Own(function() LUASQUARE_TIMELINE.UnregisterComponent(node.id) end)
        for suffix, method in pairs({start = 'Start', cancel = 'Cancel'}) do
            MAP.RegisterControlAction(instance, node, suffix, {label = node.id .. ' ' .. suffix, parameters = {slot = {type = 'string'}},
                callback = function(actor, params)
                    if not slots[params.slot] then return false, 'unknown timeline slot' end
                    if suffix == 'cancel' then return LUASQUARE_TIMELINE.Cancel(node.id, params.slot, 'operator cancel') end
                    return LUASQUARE_TIMELINE[method](node.id, params.slot, {actor = actor})
                end})
        end
    end})

MAP.RegisterType('annunciator.console', {package = 'presentation', label = 'Alarm operator controls', fields = {
    scope = {type = 'string', optional = true, maxLength = 128}},
    register = function(instance, node)
        for suffix, method in pairs({ack = 'Acknowledge', reset = 'Reset', mute = 'Mute', test = 'Test'}) do
            MAP.RegisterControlAction(instance, node, suffix, {label = node.id .. ' ' .. suffix, parameters = {}, callback = function()
                LUASQUARE_ANNUNCIATOR[method](node.config.scope)
                return true
            end})
        end
    end})

function MAP.ActivateSources(instance)
    for _, name in ipairs({'LUASQUARE_3D2D', 'LUASQUARE_ANNUNCIATOR'}) do
        local engine = _G[name]
        local interval = (instance.compiled.startup.intervals or {})[name]
        if engine and interval then
            local previous = engine.TickInterval
            instance:Own(function() engine.TickInterval = previous end, 'consumers')
            engine.TickInterval = interval
        end
    end
    local engines = {audio = LUASQUARE_AUDIO, control = LUASQUARE_CONTROL, timeline = LUASQUARE_TIMELINE,
        annunciator = LUASQUARE_ANNUNCIATOR, ['3d2display'] = LUASQUARE_3D2D}
    local decoded, totalBytes = {}, 0
    for _, paths in pairs(instance.compiled.sources) do
        for _, path in ipairs(paths) do
            local bytes = file.Size(path, 'GAME')
            if not bytes or bytes < 0 or bytes > MAP.Limits.bytes then return false, path .. ': missing or excessive source' end
            totalBytes = totalBytes + bytes
            if totalBytes > MAP.Limits.totalBytes then return false, 'combined subsystem sources exceed size limit' end
            local source, err = MAP.DecodeJSON(file.Read(path, 'GAME'))
            if not source then return false, path .. ': ' .. tostring(err) end
            decoded[path] = source
        end
    end
    for family, engine in pairs(engines) do
        engine.ManifestSources = MAP.Copy(instance.compiled.sources[family] or {})
    end
    -- Owned before any activation: failed compilation or binding resolution must
    -- also release adapters, visuals and partial catalogs.
    instance:Own(function()
        LUASQUARE_TIMELINE.CancelAll('map instance stopped')
        LUASQUARE_CONTROL.Stop()
        LUASQUARE_ANNUNCIATOR.Stop()
        LUASQUARE_3D2D.Stop()
        LUASQUARE_AUDIO.Reset('map instance stopped')
        timer.Remove(LUASQUARE_AUDIO.TimerName)
        LUASQUARE_TIMELINE.Sources, LUASQUARE_TIMELINE.SourceIds, LUASQUARE_TIMELINE.Bindings = {}, {}, {}
        LUASQUARE_CONTROL.Controls, LUASQUARE_CONTROL.Sources = {}, {}
        LUASQUARE_ANNUNCIATOR.Alarms, LUASQUARE_ANNUNCIATOR.Groups, LUASQUARE_ANNUNCIATOR.Sources, LUASQUARE_ANNUNCIATOR.PackIds = {}, {}, {}, {}
        LUASQUARE_3D2D.Displays, LUASQUARE_3D2D.Sources, LUASQUARE_3D2D.GraphHistory = {}, {}, {}
        LUASQUARE_AUDIO.Sources = {}
        LUASQUARE_AUDIO.RebuildCatalog()
        if LUASQUARE_3D2D.BroadcastSnapshot then LUASQUARE_3D2D.BroadcastSnapshot() end
        if LUASQUARE_ANNUNCIATOR.BroadcastSnapshot then LUASQUARE_ANNUNCIATOR.BroadcastSnapshot() end
        for _, engine in pairs(engines) do engine.ManifestSources = nil end
    end, 'consumers')
    local ok, err = LUASQUARE_AUDIO.LoadMapSources(game.GetMap(), true)
    if ok == false then return false, err end
    local controls, definitions = LUASQUARE_CONTROL.Start(game.GetMap(), true)
    if not controls then return false, definitions end
    -- Publish trusted request adapters from compiled controls for cross-source
    -- validation; no physical movement or initializer runs here.
    LUASQUARE_CONTROL.Controls = definitions
    LUASQUARE_CONTROL.RegisterAdapters()
    local savedThemes = LUASQUARE_3D2D.ThemePacks
    LUASQUARE_3D2D.ThemePacks = MAP.Copy(savedThemes)
    instance:Own(function() LUASQUARE_3D2D.ThemePacks = savedThemes end, 'consumers')
    -- Compile theme definitions first, without building displays or running hooks.
    for _, path in ipairs(engines['3d2display'].ManifestSources) do
        local source = decoded[path]
        if source.kind == 'theme_pack' or source.kind == 'themepack' then
            local compiled, diagnostics = LUASQUARE_3D2D.CompileSource(source, path)
            if not compiled then return false, path .. ': ' .. LUASQUARE_3D2D.DiagnosticsText(diagnostics) end
            LUASQUARE_3D2D.ThemePacks[compiled.group] = compiled
        end
    end
    for _, family in ipairs({'annunciator', 'timeline', '3d2display'}) do
        local engine, ids = engines[family], {}
        for _, path in ipairs(engine.ManifestSources) do
            local source = decoded[path]
            local compiled, diagnostics = engine.CompileSource(source, path)
            if not compiled then return false, path .. ': ' .. engine.DiagnosticsText(diagnostics) end
            local id = compiled.id or compiled.group
            if id and ids[id] then return false, path .. ': duplicate source ID ' .. id end
            if id then ids[id] = true end
            if family == 'annunciator' then
                for provider in pairs(compiled.providers or {}) do
                    if not engine.DataProviders[provider] then return false, path .. ': unknown provider ' .. provider end
                end
                for _, alarm in pairs(compiled.alarms or {}) do
                    if alarm.audio and not LUASQUARE_AUDIO.Catalog.sounds[alarm.audio.sound] then return false, path .. ': unknown alarm sound' end
                end
            end
        end
    end
    LUASQUARE_3D2D.ThemePacks = savedThemes
    local bindings = {}
    for _, node in pairs(instance.nodes) do if node.type == 'timeline.owner' then
        for _, target in ipairs(node.config.targets) do
            if not LUASQUARE_TIMELINE.Components[target.component] then return false, node.id .. ': unknown timeline target ' .. target.component end
        end
        LUASQUARE_TIMELINE.Bindings[node.id] = {}
        for _, item in ipairs(node.config.timelines) do
            local path = MAP.SourcePath('timeline', item.source)
            local compiled, diagnostics = LUASQUARE_TIMELINE.CompileSource(decoded[path], path)
            if not compiled then return false, LUASQUARE_TIMELINE.DiagnosticsText(diagnostics) end
            LUASQUARE_TIMELINE.Bindings[node.id][item.slot] = {definition = compiled}
            bindings[#bindings + 1] = {owner = node.id, slot = item.slot, definition = compiled}
        end
    end end
    for _, binding in ipairs(bindings) do
        local valid, reason = LUASQUARE_TIMELINE.BindTimeline(binding.owner, binding.slot, binding.definition)
        if not valid then return false, binding.owner .. '.' .. binding.slot .. ': ' .. tostring(reason) end
    end
    LUASQUARE_CONTROL.Controls = {}
    LUASQUARE_AUDIO.Start()
    ok, err = LUASQUARE_CONTROL.Start(game.GetMap())
    if not ok then return false, err end
    ok, err = LUASQUARE_ANNUNCIATOR.Start()
    if not ok then return false, err end
    ok, err = LUASQUARE_TIMELINE.LoadMapSources(game.GetMap())
    if ok == false then return false, err end
    return LUASQUARE_3D2D.Start()
end
