if LUASQUARE_TIMELINE_LOADED then return end
LUASQUARE_TIMELINE_LOADED = true

LUASQUARE_TIMELINE = LUASQUARE_TIMELINE or {}
LUASQUARE_TIMELINE.Registries = LUASQUARE_TIMELINE.Registries or {}

local Registry = {}
Registry.__index = Registry

local Owner = {}
Owner.__index = Owner

local function normalizeId(value)
    if value == nil then return nil end
    value = tostring(value)
    if value == '' then return nil end
    return value
end

local function safeName(value)
    return string.gsub(string.upper(tostring(value or 'DEFAULT')), '[^A-Z0-9_]', '_')
end

local function shallowCopy(source)
    local out = {}
    for key, value in pairs(source or {}) do out[key] = value end
    return out
end

local function asActions(step)
    if type(step.actions) == 'table' then return step.actions end
    if step.action ~= nil then return { step.action } end
    return {}
end

local function isRunning(instance)
    return instance and (instance.status == 'running' or instance.status == 'paused')
end

function LUASQUARE_TIMELINE.CreateRegistry(name, options)
    name = normalizeId(name) or 'default'
    options = options or {}

    local existing = LUASQUARE_TIMELINE.Registries[name]
    if existing then
        existing.Options = options
        return existing
    end

    local registry = setmetatable({
        Name = name,
        Options = options,
        Definitions = {},
        Active = {},
        Owners = {},
        History = {},
        RunSerial = 0,
        Ticking = false,
        TimerName = 'LUASQUARE_TIMELINE_' .. safeName(name)
    }, Registry)

    LUASQUARE_TIMELINE.Registries[name] = registry
    return registry
end

function LUASQUARE_TIMELINE.CreateOwner(registry, ownerId, options)
    if not registry or not registry.CreateOwner then return nil end
    return registry:CreateOwner(ownerId, options)
end

function Registry:GetTime()
    if self.Options and self.Options.time then return self.Options.time() end
    if CurTime then return CurTime() end
    return os.clock()
end

function Registry:Log(message)
    if self.Options and self.Options.log then
        self.Options.log(message)
        return
    end
    print('[' .. tostring(self.Name) .. ' TIMELINE] ' .. tostring(message))
end

function Registry:Register(id, definition)
    id = normalizeId(id)
    definition = definition or {}
    if not id then
        self:Log('Rejected timeline with missing id')
        return false
    end

    local steps = {}
    for index, source in ipairs(definition.steps or {}) do
        local step = shallowCopy(source)
        step.id = normalizeId(step.id) or ('step_' .. tostring(index))
        step.at = math.max(tonumber(step.at) or 0, 0)
        step.order = index
        table.insert(steps, step)
    end
    table.sort(steps, function(a, b)
        if a.at == b.at then return a.order < b.order end
        return a.at < b.at
    end)

    local duration = tonumber(definition.duration)
    if duration == nil and #steps > 0 then duration = steps[#steps].at end
    self.Definitions[id] = {
        id = id,
        localId = definition.localId or id,
        ownerId = definition.ownerId,
        label = definition.label or definition.localId or id,
        channel = definition.channel or 'default',
        conflictPolicy = definition.conflictPolicy or 'reject',
        steps = steps,
        duration = math.max(duration or 0, 0),
        restartPolicy = definition.restartPolicy or 'reject',
        guard = definition.guard,
        onStart = definition.onStart,
        onCancel = definition.onCancel,
        onComplete = definition.onComplete,
        lockOwner = definition.lockOwner,
        cancelChildrenOnComplete = definition.cancelChildrenOnComplete ~= false,
        data = definition.data
    }
    return true
end

function Registry:GetDefinition(id)
    return self.Definitions[id]
end

function Registry:GetActive(id)
    return self.Active[id]
end

function Registry:IsActive(id)
    return isRunning(self.Active[id])
end

function Registry:HasActive()
    for _, instance in pairs(self.Active) do
        if isRunning(instance) then return true end
    end
    return false
end

function Registry:CreateOwner(ownerId, options)
    ownerId = normalizeId(ownerId)
    if not ownerId then return nil end
    local existing = self.Owners[ownerId]
    if existing then
        existing.Options = options or existing.Options
        return existing
    end
    local owner = setmetatable({
        Id = ownerId,
        Registry = self,
        Options = options or {},
        Definitions = {},
        LastRuns = {}
    }, Owner)
    self.Owners[ownerId] = owner
    return owner
end

function Registry:EnsureTimer()
    if not timer or not timer.Create then return false end
    if timer.Exists(self.TimerName) then return true end
    local interval = math.max(tonumber(self.Options.tickInterval) or 0.05, 0.01)
    timer.Create(self.TimerName, interval, 0, function()
        local registries = LUASQUARE_TIMELINE and LUASQUARE_TIMELINE.Registries
        local registry = registries and registries[self.Name]
        if registry then registry:Tick() end
    end)
    return true
end

function Registry:StopTimerIfIdle()
    if self:HasActive() then return end
    if timer and timer.Exists and timer.Exists(self.TimerName) then timer.Remove(self.TimerName) end
end

function Registry:RunAction(instance, action)
    if type(action) == 'function' then return action(instance.context, instance) ~= false end
    if type(action) ~= 'table' then return false end
    local actionType = action.type or 'call'
    if actionType == 'call' or actionType == 'callback' then
        local callback = action.callback or action.fn
        return type(callback) == 'function' and callback(instance.context, instance, action) ~= false
    end
    if actionType == 'fire' or actionType == 'sound' then
        local targetName = normalizeId(action.targetName or action.target)
        if not targetName or not ents or not ents.FindByName then return false end
        local inputName = action.input
        if actionType == 'sound' then inputName = action.play == false and 'StopSound' or 'PlaySound' end
        inputName = normalizeId(inputName) or 'Trigger'
        local entities = ents.FindByName(targetName) or {}
        local fired = 0
        for _, ent in ipairs(entities) do
            if IsValid(ent) and ent.Fire then
                local ok
                if action.value ~= nil then
                    ok = pcall(ent.Fire, ent, inputName, tostring(action.value))
                else
                    ok = pcall(ent.Fire, ent, inputName)
                end
                if ok then fired = fired + 1 end
                if action.all == false then break end
            end
        end
        return fired > 0
    end
    local handler = self.Options and self.Options.actions and self.Options.actions[actionType]
    return handler and handler(action, instance.context, instance) ~= false or false
end

function Registry:RunStep(instance, step)
    instance.currentStep = step.id
    instance.currentStepIndex = instance.nextStep
    for _, action in ipairs(asActions(step)) do
        local ok, result = pcall(function() return self:RunAction(instance, action) end)
        local required = step.required and true
            or (type(action) == 'table' and action.required and true or false)
        if not ok then
            self:Log('Timeline ' .. tostring(instance.id) .. ' step ' .. tostring(step.id)
                .. ' failed: ' .. tostring(result))
            if required then return false, result end
        elseif result == false and required then
            return false, 'required action returned false'
        end
    end
    return true
end

function Registry:Start(id, context, runOptions)
    local definition = self:GetDefinition(id)
    if not definition then
        self:Log('Unknown timeline: ' .. tostring(id))
        return false
    end
    local active = self.Active[id]
    if isRunning(active) then
        if definition.restartPolicy == 'restart' then
            self:Cancel(id, 'restarted')
        elseif definition.restartPolicy == 'ignore' then
            return true, active
        else
            return false
        end
    end

    runOptions = runOptions or {}
    self.RunSerial = self.RunSerial + 1
    local now = self:GetTime()
    local instance = {
        id = id,
        runId = id .. '#' .. tostring(self.RunSerial),
        localId = runOptions.localId or definition.localId or id,
        ownerId = runOptions.ownerId or definition.ownerId,
        channel = runOptions.channel or definition.channel or 'default',
        label = definition.label,
        definition = definition,
        context = context or {},
        metadata = runOptions.metadata or {},
        status = 'running',
        startedAt = now,
        pausedAt = nil,
        totalPaused = 0,
        nextStep = 1,
        currentStep = nil,
        currentStepIndex = 0,
        cancelReason = nil,
        failureReason = nil,
        parent = runOptions.parent,
        children = {}
    }
    instance.lockOwner = definition.lockOwner or instance.context.lockOwner
    self.Active[id] = instance

    if definition.onStart then
        local ok, result = pcall(definition.onStart, instance.context, instance)
        if not ok or result == false then
            self:Fail(id, ok and 'start rejected' or tostring(result))
            return false, instance
        end
    end
    self:EnsureTimer()
    if not self.Ticking then self:Tick() end
    return instance.status ~= 'failed', instance
end

function Registry:StartChild(parent, owner, localId, context, metadata)
    if not isRunning(parent) or not owner or not owner.Start then return false end
    local ok, child = owner:Start(localId, context, {
        parent = parent,
        metadata = metadata or {}
    })
    if not ok or not child then return false, child end
    table.insert(parent.children, child)
    child.parent = parent
    return true, child
end

function Registry:ReleaseLocks(instance)
    if not instance or not instance.lockOwner then return end
    local release = self.Options and self.Options.releaseLocks
    if release then
        local ok, err = pcall(release, instance.lockOwner, instance)
        if not ok then self:Log('Timeline lock release failed: ' .. tostring(err)) end
    end
end

function Registry:CancelChildren(instance, reason)
    for _, child in ipairs(instance and instance.children or {}) do
        if isRunning(child) then self:Cancel(child.id, reason or 'parent terminated') end
    end
end

function Registry:RecordTerminal(instance)
    instance.endedAt = self:GetTime()
    table.insert(self.History, instance)
    if #self.History > 100 then table.remove(self.History, 1) end
    local owner = instance.ownerId and self.Owners[instance.ownerId]
    if owner then owner.LastRuns[instance.localId] = instance end
end

function Registry:RunCancellationCallback(instance, reason)
    local callback = instance.definition and instance.definition.onCancel
    if not callback then return end
    local ok, err = pcall(callback, instance.context, instance, reason)
    if not ok then
        self:Log('Timeline ' .. tostring(instance.id) .. ' cancellation cleanup failed: ' .. tostring(err))
    end
end

function Registry:Cancel(id, reason)
    local instance = self.Active[id]
    if not isRunning(instance) then return false end
    self.Active[id] = nil
    instance.status = 'cancelled'
    instance.cancelReason = tostring(reason or 'cancelled')
    self:CancelChildren(instance, 'parent cancelled: ' .. instance.cancelReason)
    self:ReleaseLocks(instance)
    self:RunCancellationCallback(instance, instance.cancelReason)
    self:RecordTerminal(instance)
    self:StopTimerIfIdle()
    self:Log('Timeline ' .. tostring(id) .. ' cancelled: ' .. instance.cancelReason)
    return true
end

function Registry:Fail(id, reason)
    local instance = self.Active[id]
    if not isRunning(instance) then return false end
    self.Active[id] = nil
    instance.status = 'failed'
    instance.failureReason = tostring(reason or 'failed')
    self:CancelChildren(instance, 'parent failed: ' .. instance.failureReason)
    self:ReleaseLocks(instance)
    self:RunCancellationCallback(instance, instance.failureReason)
    self:RecordTerminal(instance)
    self:StopTimerIfIdle()
    self:Log('Timeline ' .. tostring(id) .. ' failed: ' .. instance.failureReason)
    return true
end

function Registry:CancelAll(reason)
    local ids = {}
    for id, instance in pairs(self.Active) do
        if isRunning(instance) then table.insert(ids, id) end
    end
    for _, id in ipairs(ids) do self:Cancel(id, reason) end
end

function Registry:Pause(id)
    local instance = self.Active[id]
    if not instance or instance.status ~= 'running' then return false end
    instance.status = 'paused'
    instance.pausedAt = self:GetTime()
    return true
end

function Registry:Resume(id)
    local instance = self.Active[id]
    if not instance or instance.status ~= 'paused' then return false end
    local now = self:GetTime()
    instance.totalPaused = instance.totalPaused + math.max(now - (instance.pausedAt or now), 0)
    instance.pausedAt = nil
    instance.status = 'running'
    return true
end

function Registry:GetElapsed(instance, now)
    now = now or self:GetTime()
    if instance.status == 'paused' then now = instance.pausedAt or now end
    if instance.endedAt then now = instance.endedAt end
    return math.max(now - instance.startedAt - (instance.totalPaused or 0), 0)
end

function Registry:Complete(id)
    local instance = self.Active[id]
    if not isRunning(instance) then return false end
    self.Active[id] = nil
    instance.status = 'completed'
    if instance.definition.cancelChildrenOnComplete then
        self:CancelChildren(instance, 'parent completed')
    end
    self:ReleaseLocks(instance)

    local callback = instance.definition and instance.definition.onComplete
    if callback then
        local ok, result = pcall(callback, instance.context, instance)
        if not ok or result == false then
            instance.status = 'failed'
            instance.failureReason = ok and 'completion rejected' or tostring(result)
            self:RunCancellationCallback(instance, instance.failureReason)
        end
    end
    self:RecordTerminal(instance)
    self:StopTimerIfIdle()
    if instance.status == 'failed' then
        self:Log('Timeline ' .. tostring(id) .. ' completion failed: ' .. instance.failureReason)
        return false
    end
    self:Log('Timeline ' .. tostring(id) .. ' completed')
    return true
end

function Registry:Tick()
    if self.Ticking then return end
    self.Ticking = true
    local now = self:GetTime()
    local ids = {}
    for id, instance in pairs(self.Active) do
        if isRunning(instance) then table.insert(ids, id) end
    end
    local function depth(instance)
        local value = 0
        local parent = instance and instance.parent
        while parent do
            value = value + 1
            parent = parent.parent
        end
        return value
    end
    table.sort(ids, function(a, b)
        local aDepth = depth(self.Active[a])
        local bDepth = depth(self.Active[b])
        if aDepth == bDepth then return tostring(a) < tostring(b) end
        return aDepth < bDepth
    end)

    for _, id in ipairs(ids) do
        local instance = self.Active[id]
        if instance and instance.status == 'running' then
            local definition = instance.definition
            if definition.guard then
                local ok, allowed = pcall(definition.guard, instance.context, instance)
                if not ok or allowed == false then
                    self:Cancel(id, ok and 'guard rejected' or tostring(allowed))
                    instance = nil
                end
            end
            if instance then
                local elapsed = self:GetElapsed(instance, now)
                while instance and instance.nextStep <= #definition.steps do
                    local step = definition.steps[instance.nextStep]
                    if elapsed < step.at then break end
                    local ok, reason = self:RunStep(instance, step)
                    if not ok then
                        self:Fail(id, 'step ' .. tostring(step.id) .. ': ' .. tostring(reason))
                        instance = nil
                    else
                        instance.nextStep = instance.nextStep + 1
                    end
                end
                if instance and instance.nextStep > #definition.steps and elapsed >= definition.duration then
                    self:Complete(id)
                end
            end
        end
    end
    self.Ticking = false
    self:StopTimerIfIdle()
end

local function childSnapshot(instance)
    local children = {}
    for _, child in ipairs(instance.children or {}) do
        table.insert(children, {
            runId = child.runId,
            ownerId = child.ownerId,
            localId = child.localId,
            channel = child.channel,
            status = child.status,
            metadata = shallowCopy(child.metadata)
        })
    end
    return children
end

function Registry:SnapshotInstance(instance)
    return {
        id = instance.id,
        runId = instance.runId,
        ownerId = instance.ownerId,
        localId = instance.localId,
        channel = instance.channel,
        label = instance.label,
        status = instance.status,
        elapsed = self:GetElapsed(instance),
        duration = instance.definition.duration,
        currentStep = instance.currentStep,
        currentStepIndex = instance.currentStepIndex,
        nextStepIndex = instance.nextStep,
        paused = instance.status == 'paused',
        parentRunId = instance.parent and instance.parent.runId or nil,
        children = childSnapshot(instance),
        metadata = shallowCopy(instance.metadata),
        cancelReason = instance.cancelReason,
        failureReason = instance.failureReason
    }
end

function Registry:GetSnapshot(options)
    options = options or {}
    local out = {}
    for _, instance in pairs(self.Active) do
        if isRunning(instance) then table.insert(out, self:SnapshotInstance(instance)) end
    end
    if options.includeHistory then
        local count = math.max(math.floor(tonumber(options.historyCount) or 20), 0)
        local first = math.max(#self.History - count + 1, 1)
        for index = first, #self.History do
            table.insert(out, self:SnapshotInstance(self.History[index]))
        end
    end
    table.sort(out, function(a, b) return tostring(a.runId) < tostring(b.runId) end)
    return out
end

function Owner:QualifiedId(localId)
    localId = normalizeId(localId)
    if not localId then return nil end
    return self.Id .. '::' .. localId
end

function Owner:Register(localId, definition)
    localId = normalizeId(localId)
    if not localId then return false end
    definition = shallowCopy(definition)
    definition.localId = localId
    definition.ownerId = self.Id
    definition.channel = definition.channel or self.Options.defaultChannel or 'default'
    definition.conflictPolicy = definition.conflictPolicy
        or self.Options.defaultConflictPolicy or 'reject'
    local qualifiedId = self:QualifiedId(localId)
    if not self.Registry:Register(qualifiedId, definition) then return false end
    self.Definitions[localId] = self.Registry:GetDefinition(qualifiedId)
    return true
end

function Owner:GetDefinition(localId)
    return self.Definitions[localId]
end

function Owner:GetActiveInChannel(channel)
    channel = channel or 'default'
    for _, instance in pairs(self.Registry.Active) do
        if isRunning(instance) and instance.ownerId == self.Id and instance.channel == channel then
            return instance
        end
    end
    return nil
end

function Owner:Start(localId, context, runOptions)
    local definition = self:GetDefinition(localId)
    if not definition then return false end
    local active = self:GetActiveInChannel(definition.channel)
    if active then
        local policy = definition.conflictPolicy or 'reject'
        if active.localId == localId and definition.restartPolicy == 'ignore' then return true, active end
        if policy == 'replace' then
            self.Registry:Cancel(active.id, 'replaced by ' .. tostring(localId))
        elseif policy == 'ignore' then
            return true, active
        else
            return false, active
        end
    end
    runOptions = shallowCopy(runOptions)
    runOptions.ownerId = self.Id
    runOptions.localId = localId
    runOptions.channel = definition.channel
    return self.Registry:Start(self:QualifiedId(localId), context, runOptions)
end

function Owner:Cancel(localId, reason)
    return self.Registry:Cancel(self:QualifiedId(localId), reason)
end

function Owner:CancelChannel(channel, reason)
    local active = self:GetActiveInChannel(channel)
    if not active then return false end
    return self.Registry:Cancel(active.id, reason)
end

function Owner:CancelAll(reason)
    local ids = {}
    for id, instance in pairs(self.Registry.Active) do
        if isRunning(instance) and instance.ownerId == self.Id then table.insert(ids, id) end
    end
    for _, id in ipairs(ids) do self.Registry:Cancel(id, reason) end
    return #ids > 0
end

function Owner:IsActive(localId)
    return self.Registry:IsActive(self:QualifiedId(localId))
end

function Owner:GetSnapshot()
    local definitions = {}
    for localId, definition in pairs(self.Definitions) do
        local lastRun = self.LastRuns[localId]
        table.insert(definitions, {
            id = localId,
            label = definition.label,
            channel = definition.channel,
            conflictPolicy = definition.conflictPolicy,
            duration = definition.duration,
            active = self:IsActive(localId),
            lastRun = lastRun and {
                runId = lastRun.runId,
                status = lastRun.status,
                parentRunId = lastRun.parent and lastRun.parent.runId or nil,
                children = childSnapshot(lastRun),
                cancelReason = lastRun.cancelReason,
                failureReason = lastRun.failureReason,
                endedAt = lastRun.endedAt
            } or nil
        })
    end
    table.sort(definitions, function(a, b) return tostring(a.id) < tostring(b.id) end)
    local runs = {}
    for _, instance in pairs(self.Registry.Active) do
        if isRunning(instance) and instance.ownerId == self.Id then
            table.insert(runs, self.Registry:SnapshotInstance(instance))
        end
    end
    table.sort(runs, function(a, b) return tostring(a.runId) < tostring(b.runId) end)
    return { ownerId = self.Id, definitions = definitions, runs = runs }
end
