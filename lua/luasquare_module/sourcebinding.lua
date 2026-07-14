if LUASQUARE_SOURCEBINDING_LOADED then return end
LUASQUARE_SOURCEBINDING_LOADED = true

LUASQUARE_SOURCEBINDING = LUASQUARE_SOURCEBINDING or {}
LUASQUARE_SOURCEBINDING.Registries = LUASQUARE_SOURCEBINDING.Registries or {}

local Registry = {}
Registry.__index = Registry

local function isValidEnt(ent)
    if IsValid then return IsValid(ent) end
    return ent ~= nil
end

local function defaultLog(prefix, message)
    print('[' .. tostring(prefix or 'SOURCEBINDING') .. '] ' .. tostring(message))
end

local function asList(value)
    if value == nil then return {} end
    if istable and istable(value) then return value end
    if type(value) == 'table' then return value end
    return { value }
end

local function normalizeString(value)
    if value == nil then return nil end
    value = tostring(value)
    if value == '' then return nil end
    return value
end

function LUASQUARE_SOURCEBINDING.CreateRegistry(name, options)
    name = normalizeString(name) or 'default'
    options = options or {}

    local existing = LUASQUARE_SOURCEBINDING.Registries[name]
    if existing then
        existing.Options = options
        return existing
    end

    local registry = setmetatable({
        Name = name,
        Options = options,
        Bindings = {},
        EntityCache = {},
        LastValidation = nil
    }, Registry)

    LUASQUARE_SOURCEBINDING.Registries[name] = registry
    return registry
end

function Registry:Log(message)
    if self.Options and self.Options.log then
        self.Options.log(message)
        return
    end

    defaultLog(self.Name, message)
end

function Registry:ClearCache(targetName)
    if targetName then
        self.EntityCache[targetName] = nil
        return
    end

    self.EntityCache = {}
end

function Registry:Register(id, data)
    data = data or {}
    id = normalizeString(id)
    if not id then
        self:Log('Rejected binding with missing id')
        return false
    end

    local targetNames = data.targetNames or data.targets
    if not targetNames then
        targetNames = data.targetName or data.target or data.entity
    end

    self.Bindings[id] = {
        id = id,
        targetName = normalizeString(data.targetName or data.target or data.entity),
        targetNames = asList(targetNames),
        class = data.class or data.entityClass,
        required = data.required and true or false,
        all = data.all and true or false,
        notes = data.notes,
        missing = false,
        entity = nil,
        entities = {}
    }

    return true
end

function Registry:Get(id)
    return self.Bindings[id]
end

function Registry:GetTargetNames(binding)
    local names = {}
    if not binding then return names end

    for _, name in ipairs(binding.targetNames or {}) do
        name = normalizeString(name)
        if name then table.insert(names, name) end
    end

    if #names == 0 and binding.targetName then
        table.insert(names, binding.targetName)
    end

    return names
end

function Registry:GetEntitiesByName(targetName)
    targetName = normalizeString(targetName)
    if not targetName then return {} end

    local cached = self.EntityCache[targetName]
    if cached then
        local valid = {}
        for _, ent in ipairs(cached) do
            if isValidEnt(ent) then table.insert(valid, ent) end
        end

        if #valid > 0 then
            self.EntityCache[targetName] = valid
            return valid
        end
    end

    if not ents or not ents.FindByName then return {} end

    local found = ents.FindByName(targetName) or {}
    local valid = {}
    for _, ent in ipairs(found) do
        if isValidEnt(ent) then table.insert(valid, ent) end
    end

    if #valid > 0 then self.EntityCache[targetName] = valid end
    return valid
end

function Registry:ResolveAll(id)
    local binding = self:Get(id)
    if not binding then return {} end

    local out = {}
    for _, targetName in ipairs(self:GetTargetNames(binding)) do
        local entities = self:GetEntitiesByName(targetName)
        for _, ent in ipairs(entities) do
            table.insert(out, ent)
        end
    end

    binding.entities = out
    binding.entity = out[1]
    binding.missing = #out == 0
    return out
end

function Registry:ResolveFirst(id)
    local entities = self:ResolveAll(id)
    return entities[1]
end

function Registry:Validate()
    local ok = true
    local missingRequired = 0
    local missingOptional = 0

    for id, binding in pairs(self.Bindings) do
        local entities = self:ResolveAll(id)
        if #entities == 0 then
            if binding.required then
                ok = false
                missingRequired = missingRequired + 1
                self:Log('Missing required binding ' .. tostring(id) .. ' target=' .. table.concat(self:GetTargetNames(binding), ',') .. ' class=' .. tostring(binding.class))
            else
                missingOptional = missingOptional + 1
                self:Log('Missing optional binding ' .. tostring(id) .. ' target=' .. table.concat(self:GetTargetNames(binding), ',') .. ' class=' .. tostring(binding.class))
            end
        end
    end

    self.LastValidation = {
        ok = ok,
        missingRequired = missingRequired,
        missingOptional = missingOptional,
        time = self.Options and self.Options.time and self.Options.time() or (CurTime and CurTime() or os.clock())
    }

    return ok
end

function Registry:Each(id, callback, options)
    options = options or {}
    local binding = self:Get(id)
    if not binding then
        self:Log('Unknown binding ' .. tostring(id))
        return 0
    end

    local entities = self:ResolveAll(id)
    local count = 0
    local useAll = options.all
    if useAll == nil then useAll = binding.all end

    for _, ent in ipairs(entities) do
        if isValidEnt(ent) then
            callback(ent, binding)
            count = count + 1
            if not useAll then break end
        end
    end

    return count
end

function Registry:Fire(id, inputName, value, options)
    inputName = inputName or 'Trigger'
    local fired = 0
    local count = self:Each(id, function(ent)
        if ent.Fire then
            local ok, err
            if value ~= nil then
                ok, err = pcall(ent.Fire, ent, inputName, tostring(value))
            else
                ok, err = pcall(ent.Fire, ent, inputName)
            end

            if ok then
                fired = fired + 1
            else
                self:Log('Fire failed for binding ' .. tostring(id) .. ' input=' .. tostring(inputName) .. ': ' .. tostring(err))
            end
        end
    end, options)

    if count <= 0 then
        self:Log('Cannot fire missing binding ' .. tostring(id))
        return false
    end

    if fired <= 0 then
        self:Log('Binding ' .. tostring(id) .. ' has no Fire method')
        return false
    end

    return true
end

function Registry:Call(id, methodName, options, ...)
    options = options or {}
    methodName = normalizeString(methodName)
    if not methodName then
        self:Log('Cannot call missing method name on binding ' .. tostring(id))
        return false
    end

    local args = { ... }
    local calls = 0
    local count = self:Each(id, function(ent)
        local method = ent[methodName]
        if method then
            local ok, err = pcall(method, ent, unpack(args))
            if ok then
                calls = calls + 1
            else
                self:Log('Method call failed for binding ' .. tostring(id) .. ' method=' .. tostring(methodName) .. ': ' .. tostring(err))
            end
        end
    end, options)

    if count <= 0 then
        self:Log('Cannot call missing binding ' .. tostring(id))
        return false
    end

    if calls <= 0 then
        self:Log('Binding ' .. tostring(id) .. ' has no method ' .. tostring(methodName))
        return false
    end

    return true
end
