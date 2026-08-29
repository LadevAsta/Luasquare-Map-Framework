if not SERVER then return end
LUASQUARE_TIMELINE = LUASQUARE_TIMELINE or {}
local TIMELINE = LUASQUARE_TIMELINE

TIMELINE.Components = TIMELINE.Components or {}
TIMELINE.TargetResolvers = TIMELINE.TargetResolvers or {}
TIMELINE.LifecycleHandlers = TIMELINE.LifecycleHandlers or {}
TIMELINE.Bindings = TIMELINE.Bindings or {}
TIMELINE.Sources = TIMELINE.Sources or {}
TIMELINE.SourceIds = TIMELINE.SourceIds or {}
TIMELINE.Active = TIMELINE.Active or {}
TIMELINE.History = TIMELINE.History or {}
TIMELINE.RunSerial = TIMELINE.RunSerial or 0
TIMELINE.CatalogRevision = TIMELINE.CatalogRevision or 0
TIMELINE.TimerName = 'LUASQUARE_TIMELINE_RUNTIME'

local function log(message)
    print('[LUASQUARE_TIMELINE] ' .. tostring(message))
end

local function bumpCatalog()
    TIMELINE.CatalogRevision = (TIMELINE.CatalogRevision or 0) + 1
end

local function sanitizeParameter(parameter)
    if type(parameter) ~= 'table' then return nil end
    return {
        id = TIMELINE.NormalizeId(parameter.id or parameter.name),
        label = tostring(parameter.label or parameter.id or parameter.name or 'Value'),
        type = tostring(parameter.type or 'string'),
        default = TIMELINE.DeepCopy(parameter.default),
        min = tonumber(parameter.min),
        max = tonumber(parameter.max),
        decimals = tonumber(parameter.decimals),
        unit = parameter.unit and tostring(parameter.unit) or nil,
        choices = type(parameter.choices) == 'table' and TIMELINE.DeepCopy(parameter.choices) or nil
    }
end

local function normalizeAction(id, action)
    if type(action) ~= 'table' then return nil end
    local kind = string.lower(tostring(action.kind or 'marker'))
    if kind ~= 'marker' and kind ~= 'duration' and kind ~= 'number' then return nil end
    local parameters = {}
    for _, parameter in ipairs(action.parameters or {}) do
        local normalized = sanitizeParameter(parameter)
        if normalized and normalized.id then table.insert(parameters, normalized) end
    end
    return {
        id = TIMELINE.NormalizeId(id),
        label = tostring(action.label or id),
        kind = kind,
        parameters = parameters,
        resizable = action.resizable ~= false and kind ~= 'marker',
        min = tonumber(action.min),
        max = tonumber(action.max),
        decimals = tonumber(action.decimals),
        unit = action.unit and tostring(action.unit) or nil,
        seekPolicy = tostring(action.seekPolicy or 'reject'),
        execute = action.execute,
        start = action.start,
        finish = action.finish,
        cancel = action.cancel,
        set = action.set,
        seek = action.seek,
        simulate = action.simulate
    }
end

function TIMELINE.RegisterComponent(id, definition)
    id = TIMELINE.NormalizeId(id)
    if not id or type(definition) ~= 'table' then return false, 'invalid component' end
    local actions = {}
    for actionId, action in pairs(definition.actions or {}) do
        local normalizedId = TIMELINE.NormalizeId(actionId)
        local normalized = normalizedId and normalizeAction(normalizedId, action)
        if normalized then actions[normalizedId] = normalized end
    end
    local children = {}
    for childId, componentId in pairs(definition.children or {}) do
        local normalizedChild = TIMELINE.NormalizeId(childId)
        local normalizedComponent = TIMELINE.NormalizeId(componentId)
        if normalizedChild and normalizedComponent then children[normalizedChild] = normalizedComponent end
    end
    TIMELINE.Components[id] = {
        id = id,
        type = TIMELINE.NormalizeId(definition.type) or 'component',
        label = tostring(definition.label or id),
        parent = TIMELINE.NormalizeId(definition.parent),
        children = children,
        actions = actions,
        defaultTimelines = type(definition.defaultTimelines) == 'table'
            and TIMELINE.DeepCopy(definition.defaultTimelines) or {},
        context = definition.context,
        safeReset = definition.safeReset,
        available = definition.available,
        notes = definition.notes and tostring(definition.notes) or nil
    }
    bumpCatalog()
    return true, TIMELINE.Components[id]
end

function TIMELINE.UnregisterComponent(id)
    id = TIMELINE.NormalizeId(id)
    if not id or not TIMELINE.Components[id] then return false end
    TIMELINE.CancelOwner(id, 'component unregistered')
    TIMELINE.Components[id] = nil
    TIMELINE.Bindings[id] = nil
    bumpCatalog()
    return true
end

function TIMELINE.RegisterTargetResolver(id, resolver, metadata)
    id = TIMELINE.NormalizeId(id)
    if not id or type(resolver) ~= 'function' then return false end
    TIMELINE.TargetResolvers[id] = {
        id = id,
        resolve = resolver,
        label = tostring(metadata and metadata.label or id),
        notes = metadata and metadata.notes,
        componentType = metadata and TIMELINE.NormalizeId(metadata.componentType) or nil
    }
    bumpCatalog()
    return true
end

function TIMELINE.RegisterLifecycleHandler(id, definition)
    id = TIMELINE.NormalizeId(id)
    if not id then return false end
    if type(definition) == 'function' then definition = {callback = definition} end
    if type(definition) ~= 'table' or type(definition.callback) ~= 'function' then return false end
    TIMELINE.LifecycleHandlers[id] = {
        id = id,
        label = tostring(definition.label or id),
        phases = type(definition.phases) == 'table' and TIMELINE.DeepCopy(definition.phases) or nil,
        callback = definition.callback
    }
    bumpCatalog()
    return true
end

local function fireEndpoint(definition, inputName, value)
    local count = 0
    for _, entity in ipairs(ents.FindByName(tostring(definition.targetName)) or {}) do
        local matches = IsValid(entity)
            and (not definition.class or entity:GetClass() == definition.class)
        if matches then
            entity:Fire(inputName, tostring(value or ''))
            count = count + 1
        end
        if count > 0 and definition.all == false then break end
    end
    return count > 0
end

function TIMELINE.RegisterEntityEndpoint(id, definition)
    local targetName = type(definition) == 'table' and tostring(definition.targetName or '') or ''
    if type(definition) ~= 'table' or targetName == '' or string.find(targetName, '[%z\1-\31]') then
        return false, 'invalid endpoint'
    end
    local allowed = {}
    for actionId, action in pairs(definition.actions or {}) do
        if type(action) == 'string' then action = {input = action} end
        if type(action) == 'table' and action.input then
            local endpointAction = action
            local inputName = tostring(endpointAction.input)
            allowed[actionId] = {
                kind = 'marker',
                label = endpointAction.label or actionId,
                seekPolicy = endpointAction.seekPolicy or 'reject',
                parameters = endpointAction.parameters,
                execute = function(_, params)
                    return fireEndpoint(definition, inputName, (params or {}).value or endpointAction.value)
                end
            }
        end
    end
    return TIMELINE.RegisterComponent(id, {
        type = 'source_entity',
        label = definition.label or id,
        actions = allowed,
        safeReset = definition.safeReset,
        notes = definition.notes
    })
end

function TIMELINE.LoadSource(path)
    path = tostring(path or '')
    if not TIMELINE.IsSafePath(path) or string.sub(string.lower(path), -5) ~= '.json' then
        return nil, {{severity = 'error', path = '$', message = 'unsafe timeline source path'}}
    end
    local searchPath = 'GAME'
    local readPath = path
    if string.sub(readPath, 1, 5) == 'data/' then
        readPath = string.sub(readPath, 6)
        searchPath = 'DATA'
    elseif string.sub(readPath, 1, #TIMELINE.DraftRoot) == TIMELINE.DraftRoot then
        searchPath = 'DATA'
    end
    local json = file.Read(readPath, searchPath)
    if not json then
        return nil, {{severity = 'error', path = '$', message = 'timeline source not found: ' .. path}}
    end
    local compiled, diagnostics = TIMELINE.DecodeSource(json, path)
    if not compiled then return nil, diagnostics end
    local previous = TIMELINE.SourceIds[compiled.id]
    if previous and previous ~= path then
        TIMELINE.AddDiagnostic(diagnostics, 'error', 'id',
            'duplicate timeline id already loaded from ' .. previous)
        return nil, diagnostics
    end
    TIMELINE.Sources[path] = compiled
    TIMELINE.SourceIds[compiled.id] = path
    bumpCatalog()
    return compiled, diagnostics
end

local function loadDirectory(root)
    local loaded = 0
    local files, directories = file.Find(root .. '/*', 'GAME')
    for _, name in ipairs(files or {}) do
        if string.sub(string.lower(name), -5) == '.json'
            and TIMELINE.LoadSource(root .. '/' .. name) then
            loaded = loaded + 1
        end
    end
    for _, directory in ipairs(directories or {}) do
        loaded = loaded + loadDirectory(root .. '/' .. directory)
    end
    return loaded
end

function TIMELINE.LoadMapSources(mapName)
    local loaded = loadDirectory(TIMELINE.SourceRoot .. '/_components')
    local normalizedMap = string.lower(tostring(mapName or (game and game.GetMap and game.GetMap()) or ''))
    if normalizedMap ~= '' then loaded = loaded + loadDirectory(TIMELINE.SourceRoot .. '/' .. normalizedMap) end
    return loaded
end

function TIMELINE.ReloadSources()
    TIMELINE.CancelAll('timeline sources reloaded')
    local rebind = {}
    for ownerId, bindings in pairs(TIMELINE.Bindings) do
        for localName, binding in pairs(bindings) do
            if binding.sourcePath then
                table.insert(rebind, {
                    ownerId = ownerId,
                    localName = localName,
                    sourcePath = binding.sourcePath,
                    options = binding.options
                })
            end
        end
    end
    TIMELINE.Sources = {}
    TIMELINE.SourceIds = {}
    TIMELINE.LoadMapSources(game.GetMap())
    local rebound = 0
    for _, item in ipairs(rebind) do
        if TIMELINE.BindTimeline(item.ownerId, item.localName, item.sourcePath, item.options) then
            rebound = rebound + 1
        end
    end
    return rebound
end

local function validateTarget(target, ownerId, diagnostics, path)
    if target.kind == 'self' then
        if not TIMELINE.Components[ownerId] then
            TIMELINE.AddDiagnostic(diagnostics, 'error', path, 'owner component is not registered: ' .. ownerId)
        end
        return
    end
    if target.kind == 'component' and not TIMELINE.Components[target.id] then
        TIMELINE.AddDiagnostic(diagnostics, 'error', path, 'unknown component: ' .. tostring(target.id))
    elseif target.kind == 'child' then
        local owner = TIMELINE.Components[ownerId]
        local childId = owner and owner.children and owner.children[target.id]
        if not childId or not TIMELINE.Components[TIMELINE.NormalizeId(childId)] then
            TIMELINE.AddDiagnostic(diagnostics, 'error', path, 'unknown child component: ' .. tostring(target.id))
        end
    elseif target.kind == 'resolver' and not TIMELINE.TargetResolvers[target.id] then
        TIMELINE.AddDiagnostic(diagnostics, 'error', path, 'unknown target resolver: ' .. tostring(target.id))
    end
end

local function staticTargets(target, ownerId)
    if target.kind == 'self' then return {TIMELINE.Components[ownerId]} end
    if target.kind == 'component' then return {TIMELINE.Components[target.id]} end
    if target.kind == 'child' then
        local owner = TIMELINE.Components[ownerId]
        local childId = owner and owner.children and TIMELINE.NormalizeId(owner.children[target.id])
        return {childId and TIMELINE.Components[childId] or nil}
    end
    if target.kind == 'resolver' then
        local resolver = TIMELINE.TargetResolvers[target.id]
        if not resolver or not resolver.componentType then return nil end
        local targets = {}
        for _, component in pairs(TIMELINE.Components) do
            if component.type == resolver.componentType then table.insert(targets, component) end
        end
        return targets
    end
    return nil
end

local function normalizeParameters(action, values)
    local out = TIMELINE.DeepCopy(values or {})
    for _, definition in ipairs(action.parameters or {}) do
        local id = definition.id
        local value = out[id]
        if value == nil then value = TIMELINE.DeepCopy(definition.default) end
        if definition.type == 'number' then
            value = tonumber(value)
            if value == nil then return nil, 'parameter ' .. id .. ' must be a number' end
            if definition.min ~= nil then value = math.max(value, definition.min) end
            if definition.max ~= nil then value = math.min(value, definition.max) end
            if definition.decimals ~= nil then
                local factor = 10 ^ math.max(math.floor(definition.decimals), 0)
                value = math.floor(value * factor + 0.5) / factor
            end
        elseif definition.type == 'boolean' then
            if type(value) ~= 'boolean' then return nil, 'parameter ' .. id .. ' must be a boolean' end
        elseif definition.type == 'enum' then
            local allowed = false
            for _, choice in ipairs(definition.choices or {}) do
                if value == choice then allowed = true break end
            end
            if not allowed then return nil, 'parameter ' .. id .. ' is not an allowed enum value' end
        elseif definition.type == 'string' then
            if value == nil then value = '' end
            value = tostring(value)
        end
        out[id] = value
    end
    return out
end

function TIMELINE.ValidateBinding(ownerId, compiled)
    local diagnostics = {}
    ownerId = TIMELINE.NormalizeId(ownerId)
    if not ownerId or not TIMELINE.Components[ownerId] then
        TIMELINE.AddDiagnostic(diagnostics, 'error', 'owner', 'unknown owner component: ' .. tostring(ownerId))
    end
    for phase, handlerId in pairs(compiled.lifecycle or {}) do
        if not TIMELINE.LifecycleHandlers[handlerId] then
            TIMELINE.AddDiagnostic(diagnostics, 'error', 'lifecycle.' .. phase, 'unknown handler: ' .. handlerId)
        end
    end
    for _, clip in ipairs(compiled.clips or {}) do
        local path = 'clip.' .. clip.id
        validateTarget(clip.target, ownerId, diagnostics, path .. '.target')
        if clip.kind ~= 'timeline' then
            local targets = staticTargets(clip.target, ownerId)
            for _, component in ipairs(targets or {}) do
                local action = component and component.actions[clip.action]
                if not action then
                    TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.action',
                        'component does not expose action: ' .. tostring(clip.action))
                elseif action.kind ~= clip.kind and not (clip.kind == 'marker' and action.kind == 'number') then
                    TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.kind',
                        'clip kind does not match action capability')
                else
                    local _, parameterError = normalizeParameters(action, clip.params)
                    if parameterError then
                        TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.params', parameterError)
                    end
                end
            end
        else
            local targets = staticTargets(clip.target, ownerId)
            for _, component in ipairs(targets or {}) do
                local bindings = component and TIMELINE.Bindings[component.id]
                if component and (not bindings or not bindings[clip.timeline]) then
                    TIMELINE.AddDiagnostic(diagnostics, 'error', path .. '.timeline',
                        'target component has no bound timeline: ' .. tostring(clip.timeline))
                end
            end
        end
    end
    return not TIMELINE.HasErrors(diagnostics), diagnostics
end

function TIMELINE.BindTimeline(ownerId, localName, sourceOrPath, options)
    ownerId = TIMELINE.NormalizeId(ownerId)
    localName = TIMELINE.NormalizeId(localName)
    if not ownerId or not localName then return false, 'invalid owner or timeline id' end
    local compiled, diagnostics
    if type(sourceOrPath) == 'string' then
        compiled = TIMELINE.Sources[sourceOrPath]
        if not compiled then compiled, diagnostics = TIMELINE.LoadSource(sourceOrPath) end
    elseif type(sourceOrPath) == 'table' and sourceOrPath.schema == TIMELINE.Schema and sourceOrPath.clips then
        compiled = sourceOrPath
    elseif type(sourceOrPath) == 'table' then
        compiled, diagnostics = TIMELINE.CompileSource(sourceOrPath, options and options.origin or 'runtime')
    end
    if not compiled then return false, TIMELINE.DiagnosticsText(diagnostics) end
    local valid, bindingDiagnostics = TIMELINE.ValidateBinding(ownerId, compiled)
    if not valid then return false, TIMELINE.DiagnosticsText(bindingDiagnostics) end
    TIMELINE.Bindings[ownerId] = TIMELINE.Bindings[ownerId] or {}
    TIMELINE.Bindings[ownerId][localName] = {
        ownerId = ownerId,
        localName = localName,
        definition = TIMELINE.DeepCopy(compiled),
        sourcePath = type(sourceOrPath) == 'string' and sourceOrPath or nil,
        options = options or {}
    }
    bumpCatalog()
    return true, TIMELINE.Bindings[ownerId][localName]
end

function TIMELINE.UnbindTimeline(ownerId, localName)
    ownerId = TIMELINE.NormalizeId(ownerId)
    localName = TIMELINE.NormalizeId(localName)
    local owner = ownerId and TIMELINE.Bindings[ownerId]
    if not owner or not owner[localName] then return false end
    TIMELINE.Cancel(ownerId, localName, 'timeline unbound')
    owner[localName] = nil
    bumpCatalog()
    return true
end

local function qualifiedId(ownerId, localName)
    return tostring(ownerId) .. '::' .. tostring(localName)
end

local function getTime()
    if CurTime then return CurTime() end
    return os.clock()
end

local function resolveTargets(run, target)
    if target.kind == 'self' then return {TIMELINE.Components[run.ownerId]} end
    if target.kind == 'component' then return {TIMELINE.Components[target.id]} end
    if target.kind == 'child' then
        local owner = TIMELINE.Components[run.ownerId]
        local id = owner and owner.children and TIMELINE.NormalizeId(owner.children[target.id])
        return {id and TIMELINE.Components[id] or nil}
    end
    if target.kind == 'resolver' then
        local resolver = TIMELINE.TargetResolvers[target.id]
        local ok, result = pcall(resolver.resolve, run.context, run)
        if not ok or type(result) ~= 'table' then return {} end
        local out = {}
        for _, value in ipairs(result) do
            local id = type(value) == 'table' and value.id or TIMELINE.NormalizeId(value)
            if id and TIMELINE.Components[id] then table.insert(out, TIMELINE.Components[id]) end
        end
        return out
    end
    return {}
end

local function touch(run, component)
    if component and component.id then run.touched[component.id] = true end
end

local function callLifecycle(run, phase, reason)
    local id = run.definition.lifecycle and run.definition.lifecycle[phase]
    if not id then return true end
    local handler = TIMELINE.LifecycleHandlers[id]
    if not handler then return false, 'missing lifecycle handler: ' .. id end
    local ok, result = pcall(handler.callback, run.context, run, phase, reason)
    if not ok then return false, result end
    if result == false then return false, 'lifecycle handler rejected: ' .. id end
    return true, result
end

local function callAction(run, component, clip, phase, value)
    if not component then return false, 'missing component' end
    local action = component.actions[clip.action]
    if not action then return false, 'missing action ' .. tostring(clip.action) end
    if run.seeking then
        if action.seekPolicy == 'skip' then return true end
        if action.seekPolicy ~= 'apply' then return false, 'action cannot seek: ' .. action.id end
    end
    local params, parameterError = normalizeParameters(action, clip.params)
    if not params then return false, parameterError end
    if clip.kind == 'number' then
        if action.min ~= nil then value = math.max(value, action.min) end
        if action.max ~= nil then value = math.min(value, action.max) end
        if action.decimals ~= nil then
            local factor = 10 ^ math.max(math.floor(action.decimals), 0)
            value = math.floor(value * factor + 0.5) / factor
        end
    end
    local callback
    if run.seeking and action.seek then
        callback = action.seek
    elseif clip.kind == 'marker' then
        callback = action.execute or action.set
    elseif clip.kind == 'duration' then
        callback = phase == 'start' and action.start
            or (phase == 'cancel' and (action.cancel or action.finish)) or action.finish
    elseif clip.kind == 'number' then
        callback = action.set
    end
    if type(callback) ~= 'function' then return false, 'action phase is not implemented' end
    touch(run, component)
    local ok, result = pcall(callback, component.context, params, value, run, clip, phase)
    if not ok then return false, result end
    return result ~= false, result == false and 'action returned false' or nil
end

local function requiredSuccess(clip, total)
    if clip.minimumSuccess > 0 then return clip.minimumSuccess end
    return clip.required and math.max(total, 1) or 0
end

local function runMarker(run, clip)
    local targets = resolveTargets(run, clip.target)
    local success = 0
    for _, component in ipairs(targets) do
        local ok = callAction(run, component, clip, 'execute')
        if ok then success = success + 1 end
    end
    return success >= requiredSuccess(clip, #targets), success
end

local function runDurationStart(run, clip, state)
    local targets = resolveTargets(run, clip.target)
    state.targets = targets
    local success = 0
    for _, component in ipairs(targets) do
        local ok = callAction(run, component, clip, 'start')
        if ok then success = success + 1 end
    end
    state.started = true
    return success >= requiredSuccess(clip, #targets)
end

local function runDurationEnd(run, clip, state, phase)
    local success = 0
    for _, component in ipairs(state.targets or {}) do
        local ok = callAction(run, component, clip, phase or 'finish')
        if ok then success = success + 1 end
    end
    state.finished = true
    return success >= requiredSuccess(clip, #(state.targets or {}))
end

local function runNumber(run, clip, elapsed, state)
    if not state.targets then state.targets = resolveTargets(run, clip.target) end
    local fraction = clip.duration <= 0 and 1 or TIMELINE.Clamp((elapsed - clip.at) / clip.duration, 0, 1)
    local eased = TIMELINE.Ease(clip.curve, fraction)
    local value = clip.from + (clip.to - clip.from) * eased
    local success = 0
    for _, component in ipairs(state.targets) do
        local ok = callAction(run, component, clip, 'set', value)
        if ok then success = success + 1 end
    end
    state.started = true
    state.value = value
    if fraction >= 1 then state.finished = true end
    return success >= requiredSuccess(clip, #state.targets)
end

local function startChildClip(run, clip)
    local targets = resolveTargets(run, clip.target)
    local success = 0
    for _, component in ipairs(targets) do
        local childSeek = run.seeking and math.max((run.seekTo or 0) - clip.at, 0) or 0
        local ok, child = TIMELINE.StartChild(run, component.id, clip.timeline, {
            parentContext = run.context,
            sourceClip = clip.id
        }, clip.metadata, childSeek)
        if ok and child then success = success + 1 end
    end
    return success >= requiredSuccess(clip, #targets), success
end

local function elapsed(run, now)
    now = now or getTime()
    if run.status == 'paused' then now = run.pausedAt or now end
    if run.endedAt then now = run.endedAt end
    return math.max(now - run.startedAt - (run.totalPaused or 0), 0)
end

local function ensureTimer()
    if timer.Exists(TIMELINE.TimerName) then return end
    timer.Create(TIMELINE.TimerName, math.max(TIMELINE.TickInterval, 0.01), 0, function()
        if LUASQUARE_TIMELINE and LUASQUARE_TIMELINE.Tick then LUASQUARE_TIMELINE.Tick() end
    end)
end

local function stopTimerIfIdle()
    for _, run in pairs(TIMELINE.Active) do
        if TIMELINE.IsRunning(run) then return end
    end
    if timer.Exists(TIMELINE.TimerName) then timer.Remove(TIMELINE.TimerName) end
end

local function activeInChannel(ownerId, channel)
    for _, run in pairs(TIMELINE.Active) do
        if TIMELINE.IsRunning(run) and run.ownerId == ownerId and run.channel == channel then return run end
    end
end

local function bindingFor(ownerId, localName)
    return TIMELINE.Bindings[ownerId] and TIMELINE.Bindings[ownerId][localName]
end

function TIMELINE.Start(ownerId, localName, context, options)
    ownerId = TIMELINE.NormalizeId(ownerId)
    localName = TIMELINE.NormalizeId(localName)
    local binding = ownerId and localName and bindingFor(ownerId, localName)
    if not binding then return false, 'unknown bound timeline' end
    return TIMELINE.StartCompiled(ownerId, localName, binding.definition, context, options)
end

function TIMELINE.CanSeek(ownerId, definition, seekTo, visited)
    seekTo = math.max(tonumber(seekTo) or 0, 0)
    if seekTo <= 0 then return true end
    visited = visited or {}
    local visitKey = tostring(ownerId) .. '::' .. tostring(definition.id)
    if visited[visitKey] then return true end
    visited[visitKey] = true
    local fakeRun = {ownerId = ownerId, context = {}, definition = definition, preview = true}
    for _, clip in ipairs(definition.clips or {}) do
        if clip.at <= seekTo and clip.required then
            local targets = resolveTargets(fakeRun, clip.target)
            if clip.kind == 'timeline' then
                for _, component in ipairs(targets) do
                    local childBinding = bindingFor(component.id, clip.timeline)
                    if not childBinding then return false, 'missing child timeline: ' .. clip.timeline end
                    local ok, reason = TIMELINE.CanSeek(component.id, childBinding.definition,
                        math.max(seekTo - clip.at, 0), visited)
                    if not ok then return false, reason end
                end
            else
                for _, component in ipairs(targets) do
                    local action = component.actions[clip.action]
                    if not action or (action.seekPolicy ~= 'apply' and action.seekPolicy ~= 'skip') then
                        return false, 'required action cannot reconstruct from the playhead: '
                            .. tostring(clip.action)
                    end
                end
            end
        end
    end
    return true
end

function TIMELINE.StartCompiled(ownerId, localName, definition, context, options)
    options = options or {}
    if options.preview then
        local previewComponent = TIMELINE.Components[ownerId]
        if not previewComponent or type(previewComponent.safeReset) ~= 'function' then
            return false, 'owner component does not provide a safe live-preview reset'
        end
        local seekOk, seekReason = TIMELINE.CanSeek(ownerId, definition, options.seekTo)
        if not seekOk then return false, seekReason end
    end
    local key = qualifiedId(ownerId, localName)
    local existing = TIMELINE.Active[key]
    if TIMELINE.IsRunning(existing) then
        if definition.restartPolicy == 'restart' then
            TIMELINE.Cancel(ownerId, localName, 'restarted')
        elseif definition.restartPolicy == 'ignore' then
            return true, existing
        else
            return false, 'timeline already active'
        end
    end
    local conflict = activeInChannel(ownerId, options.channel or definition.channel)
    if conflict then
        if definition.conflictPolicy == 'replace' and not options.preview then
            TIMELINE.Cancel(conflict.ownerId, conflict.localName, 'replaced by ' .. localName)
        elseif definition.conflictPolicy == 'ignore' then
            return true, conflict
        else
            return false, 'timeline channel is busy'
        end
    end
    if options.preview and not options.parent and TIMELINE.LivePreviewRun
        and TIMELINE.IsRunning(TIMELINE.LivePreviewRun) then
        return false, 'another live preview is active'
    end
    TIMELINE.RunSerial = TIMELINE.RunSerial + 1
    local seekTo = math.max(tonumber(options.seekTo) or 0, 0)
    local now = getTime()
    local run = {
        id = key,
        runId = key .. '#' .. TIMELINE.RunSerial,
        ownerId = ownerId,
        localName = localName,
        channel = options.channel or definition.channel,
        label = definition.label,
        definition = definition,
        context = context or {},
        metadata = options.metadata or {},
        status = 'running',
        startedAt = now - seekTo,
        pausedAt = nil,
        totalPaused = 0,
        clipStates = {},
        currentClip = nil,
        parent = options.parent,
        children = {},
        touched = {},
        preview = options.preview and true or false,
        mutedTracks = options.mutedTracks or {},
        seekTo = seekTo,
        seeking = seekTo > 0
    }
    TIMELINE.Active[key] = run
    if run.preview and not run.parent then TIMELINE.LivePreviewRun = run end
    local ok, reason = callLifecycle(run, 'startGuard')
    if not ok then
        TIMELINE.FailRun(run, reason)
        return false, reason
    end
    ok, reason = callLifecycle(run, 'onStart')
    if not ok then
        TIMELINE.FailRun(run, reason)
        return false, reason
    end
    ensureTimer()
    TIMELINE.Tick()
    return run.status ~= 'failed' and run.status ~= 'cancelled', run
end

function TIMELINE.StartChild(parent, ownerId, localName, context, metadata, seekTo)
    if not TIMELINE.IsRunning(parent) then return false, 'parent is not active' end
    local ok, child = TIMELINE.Start(ownerId, localName, context, {
        parent = parent,
        metadata = metadata,
        preview = parent.preview,
        seekTo = seekTo or 0,
        mutedTracks = parent.mutedTracks
    })
    if ok and child then
        child.parent = parent
        table.insert(parent.children, child)
    end
    return ok, child
end

local function resetTouched(run, reason)
    if not run.preview then return end
    for componentId in pairs(run.touched or {}) do
        local component = TIMELINE.Components[componentId]
        if component and type(component.safeReset) == 'function' then
            local ok, err = pcall(component.safeReset, component.context, reason, run)
            if not ok then log('Safe reset failed for ' .. componentId .. ': ' .. tostring(err)) end
        end
    end
end

local function cancelClipStates(run)
    for _, clip in ipairs(run.definition.clips or {}) do
        local state = run.clipStates[clip.id]
        if state and state.started and not state.finished and clip.kind == 'duration' then
            runDurationEnd(run, clip, state, 'cancel')
        end
    end
end

local function cancelChildren(run, reason)
    for _, child in ipairs(run.children or {}) do
        if TIMELINE.IsRunning(child) then TIMELINE.CancelRun(child, reason or 'parent ended') end
    end
end

local function record(run)
    run.endedAt = getTime()
    table.insert(TIMELINE.History, run)
    if #TIMELINE.History > 100 then table.remove(TIMELINE.History, 1) end
    if TIMELINE.LivePreviewRun == run then TIMELINE.LivePreviewRun = nil end
    hook.Run('LUASQUARE_TIMELINE_RunTerminal', run)
end

function TIMELINE.CancelRun(run, reason)
    if not TIMELINE.IsRunning(run) then return false end
    TIMELINE.Active[run.id] = nil
    run.status = 'cancelled'
    run.cancelReason = tostring(reason or 'cancelled')
    cancelClipStates(run)
    cancelChildren(run, 'parent cancelled: ' .. run.cancelReason)
    callLifecycle(run, 'onCancel', run.cancelReason)
    resetTouched(run, run.cancelReason)
    record(run)
    stopTimerIfIdle()
    return true
end

function TIMELINE.FailRun(run, reason)
    if not TIMELINE.IsRunning(run) then return false end
    TIMELINE.Active[run.id] = nil
    run.status = 'failed'
    run.failureReason = tostring(reason or 'failed')
    cancelClipStates(run)
    cancelChildren(run, 'parent failed: ' .. run.failureReason)
    callLifecycle(run, 'onCancel', run.failureReason)
    resetTouched(run, run.failureReason)
    record(run)
    stopTimerIfIdle()
    log('Timeline failed: ' .. run.id .. ': ' .. run.failureReason)
    return true
end

function TIMELINE.CompleteRun(run)
    if not TIMELINE.IsRunning(run) then return false end
    TIMELINE.Active[run.id] = nil
    run.status = 'completed'
    if run.definition.cancelChildrenOnComplete then cancelChildren(run, 'parent completed') end
    local ok, reason = callLifecycle(run, 'onComplete')
    if not ok then
        run.status = 'failed'
        run.failureReason = tostring(reason)
        callLifecycle(run, 'onCancel', reason)
    end
    resetTouched(run, run.status)
    record(run)
    stopTimerIfIdle()
    return run.status == 'completed'
end

function TIMELINE.Cancel(ownerId, localName, reason)
    local run = TIMELINE.Active[qualifiedId(TIMELINE.NormalizeId(ownerId), TIMELINE.NormalizeId(localName))]
    return run and TIMELINE.CancelRun(run, reason) or false
end

function TIMELINE.CancelOwner(ownerId, reason)
    ownerId = TIMELINE.NormalizeId(ownerId)
    local runs = {}
    for _, run in pairs(TIMELINE.Active) do
        if run.ownerId == ownerId then table.insert(runs, run) end
    end
    for _, run in ipairs(runs) do TIMELINE.CancelRun(run, reason) end
    return #runs > 0
end

function TIMELINE.CancelAll(reason)
    local runs = {}
    for _, run in pairs(TIMELINE.Active) do table.insert(runs, run) end
    for _, run in ipairs(runs) do TIMELINE.CancelRun(run, reason) end
    return true
end

function TIMELINE.Pause(ownerId, localName)
    local run = TIMELINE.Active[qualifiedId(TIMELINE.NormalizeId(ownerId), TIMELINE.NormalizeId(localName))]
    if not run or run.status ~= 'running' then return false end
    run.status = 'paused'
    run.pausedAt = getTime()
    return true
end

function TIMELINE.Resume(ownerId, localName)
    local run = TIMELINE.Active[qualifiedId(TIMELINE.NormalizeId(ownerId), TIMELINE.NormalizeId(localName))]
    if not run or run.status ~= 'paused' then return false end
    local now = getTime()
    run.totalPaused = run.totalPaused + math.max(now - (run.pausedAt or now), 0)
    run.pausedAt = nil
    run.status = 'running'
    return true
end

local function isTrackMuted(run, clip)
    local track = run.definition.tracks[clip.trackIndex]
    return run.mutedTracks[clip.trackIndex]
        or run.mutedTracks[tostring(clip.trackIndex)]
        or (track and run.mutedTracks[track.id])
end

local function processDueClip(run, clip, current)
    local state = run.clipStates[clip.id] or {}
    run.clipStates[clip.id] = state
    if isTrackMuted(run, clip) or current < clip.at then return true end

    local clipOk = true
    if clip.kind == 'marker' and not state.started then
        state.started = true
        state.finished = true
        clipOk = runMarker(run, clip)
    elseif clip.kind == 'duration' then
        if not state.started then
            clipOk = runDurationStart(run, clip, state)
        end
        if clipOk and not state.finished and current >= clip.endsAt then
            clipOk = runDurationEnd(run, clip, state, 'finish')
        end
    elseif clip.kind == 'number' and not state.finished then
        clipOk = runNumber(run, clip, current, state)
    elseif clip.kind == 'timeline' and not state.started then
        state.started = true
        state.finished = true
        clipOk = startChildClip(run, clip)
    end
    if state.started then run.currentClip = clip.id end
    if clipOk or not clip.required then return true end
    return false, 'required clip failed: ' .. clip.id
end

local function hasPendingClips(run)
    for _, clip in ipairs(run.definition.clips) do
        local state = run.clipStates[clip.id]
        if clip.at <= run.definition.duration and (not state or not state.finished) then
            return true
        end
    end
    return false
end

function TIMELINE.Tick()
    if TIMELINE.Ticking then return end
    TIMELINE.Ticking = true
    local now = getTime()
    local runs = {}
    for _, run in pairs(TIMELINE.Active) do
        if run.status == 'running' then table.insert(runs, run) end
    end
    local function depth(run)
        local count = 0
        local parent = run.parent
        while parent do
            count = count + 1
            parent = parent.parent
        end
        return count
    end
    table.sort(runs, function(a, b)
        local ad, bd = depth(a), depth(b)
        return ad == bd and a.runId < b.runId or ad < bd
    end)
    for _, run in ipairs(runs) do
        if run.status == 'running' then
            local ok, reason = callLifecycle(run, 'runGuard')
            if not ok then
                TIMELINE.FailRun(run, reason)
            else
                local current = elapsed(run, now)
                for _, clip in ipairs(run.definition.clips) do
                    if run.status ~= 'running' then break end
                    local clipOk, clipReason = processDueClip(run, clip, current)
                    if not clipOk then
                        TIMELINE.FailRun(run, clipReason)
                        break
                    end
                end
                run.seeking = false
                if run.status == 'running' and current >= run.definition.duration
                    and not hasPendingClips(run) then
                    TIMELINE.CompleteRun(run)
                end
            end
        end
    end
    TIMELINE.Ticking = false
    stopTimerIfIdle()
end

local function childSnapshot(run)
    local out = {}
    for _, child in ipairs(run.children or {}) do
        table.insert(out, {
            runId = child.runId,
            ownerId = child.ownerId,
            localName = child.localName,
            channel = child.channel,
            status = child.status,
            metadata = TIMELINE.DeepCopy(child.metadata)
        })
    end
    return out
end

function TIMELINE.SnapshotRun(run)
    return {
        id = run.id,
        runId = run.runId,
        ownerId = run.ownerId,
        localId = run.localName,
        channel = run.channel,
        label = run.label,
        status = run.status,
        elapsed = elapsed(run),
        duration = run.definition.duration,
        currentClip = run.currentClip,
        currentStep = run.currentClip,
        paused = run.status == 'paused',
        parentRunId = run.parent and run.parent.runId or nil,
        children = childSnapshot(run),
        metadata = TIMELINE.DeepCopy(run.metadata),
        cancelReason = run.cancelReason,
        failureReason = run.failureReason,
        preview = run.preview
    }
end

function TIMELINE.GetSnapshot(options)
    options = options or {}
    local out = {}
    for _, run in pairs(TIMELINE.Active) do table.insert(out, TIMELINE.SnapshotRun(run)) end
    if options.includeHistory then
        local count = math.max(math.floor(tonumber(options.historyCount) or 20), 0)
        for index = math.max(#TIMELINE.History - count + 1, 1), #TIMELINE.History do
            table.insert(out, TIMELINE.SnapshotRun(TIMELINE.History[index]))
        end
    end
    table.sort(out, function(a, b) return a.runId < b.runId end)
    return out
end

function TIMELINE.GetOwnerSnapshot(ownerId)
    ownerId = TIMELINE.NormalizeId(ownerId)
    local definitions = {}
    for localName, binding in pairs(TIMELINE.Bindings[ownerId] or {}) do
        local run = TIMELINE.Active[qualifiedId(ownerId, localName)]
        local lastRun
        for index = #TIMELINE.History, 1, -1 do
            local candidate = TIMELINE.History[index]
            if candidate.ownerId == ownerId and candidate.localName == localName then
                lastRun = TIMELINE.SnapshotRun(candidate)
                break
            end
        end
        table.insert(definitions, {
            id = localName,
            label = binding.definition.label,
            channel = binding.definition.channel,
            conflictPolicy = binding.definition.conflictPolicy,
            duration = binding.definition.duration,
            sourcePath = binding.sourcePath,
            active = TIMELINE.IsRunning(run),
            lastRun = lastRun
        })
    end
    table.sort(definitions, function(a, b) return a.id < b.id end)
    local runs = {}
    for _, run in pairs(TIMELINE.Active) do
        if run.ownerId == ownerId then table.insert(runs, TIMELINE.SnapshotRun(run)) end
    end
    return {ownerId = ownerId, definitions = definitions, runs = runs}
end

function TIMELINE.GetActiveInChannel(ownerId, channel)
    return activeInChannel(TIMELINE.NormalizeId(ownerId), TIMELINE.NormalizeId(channel) or 'default')
end

function TIMELINE.GetDefinition(ownerId, localName)
    local binding = bindingFor(TIMELINE.NormalizeId(ownerId), TIMELINE.NormalizeId(localName))
    return binding and TIMELINE.DeepCopy(binding.definition) or nil
end

function TIMELINE.GetComponentCatalog()
    local catalog = {revision = TIMELINE.CatalogRevision, components = {}, handlers = {}, resolvers = {}, sources = {}}
    for id, component in pairs(TIMELINE.Components) do
        local actions = {}
        for actionId, action in pairs(component.actions) do
            table.insert(actions, {
                id = actionId,
                label = action.label,
                kind = action.kind,
                parameters = TIMELINE.DeepCopy(action.parameters),
                resizable = action.resizable,
                min = action.min,
                max = action.max,
                decimals = action.decimals,
                unit = action.unit,
                seekPolicy = action.seekPolicy
            })
        end
        table.sort(actions, function(a, b) return a.label < b.label end)
        table.insert(catalog.components, {
            id = id,
            type = component.type,
            label = component.label,
            parent = component.parent,
            children = TIMELINE.DeepCopy(component.children),
            actions = actions,
            timelines = TIMELINE.GetOwnerSnapshot(id).definitions,
            livePreview = type(component.safeReset) == 'function',
            notes = component.notes
        })
    end
    for id, handler in pairs(TIMELINE.LifecycleHandlers) do
        table.insert(catalog.handlers, {id = id, label = handler.label, phases = TIMELINE.DeepCopy(handler.phases)})
    end
    for id, resolver in pairs(TIMELINE.TargetResolvers) do
        table.insert(catalog.resolvers, {id = id, label = resolver.label, notes = resolver.notes, componentType = resolver.componentType})
    end
    for path, source in pairs(TIMELINE.Sources) do
        table.insert(catalog.sources, {
            id = source.id,
            label = source.label,
            path = path,
            duration = source.duration,
            source = TIMELINE.DeepCopy(source.source)
        })
    end
    table.sort(catalog.components, function(a, b) return a.label < b.label end)
    table.sort(catalog.handlers, function(a, b) return a.id < b.id end)
    table.sort(catalog.resolvers, function(a, b) return a.id < b.id end)
    table.sort(catalog.sources, function(a, b) return a.path < b.path end)
    return catalog
end
