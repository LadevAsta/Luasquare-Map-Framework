if LUASQUARE_CONTROLBINDING_LOADED then return end
LUASQUARE_CONTROLBINDING_LOADED = true

LUASQUARE_CONTROLBINDING = LUASQUARE_CONTROLBINDING or {}
LUASQUARE_CONTROLBINDING.Registries = LUASQUARE_CONTROLBINDING.Registries or {}

local Registry = {}
Registry.__index = Registry

local function normalizeId(value)
    if value == nil then return nil end
    value = tostring(value)
    if value == '' then return nil end
    return value
end

local function isEmptyTable(value)
    if not value then return true end
    for _ in pairs(value) do return false end
    return true
end

local function stateAllowed(control, state)
    local allowed = control.allowedStates
    if isEmptyTable(allowed) then return true end
    if allowed[state] then return true end

    for _, allowedState in ipairs(allowed) do
        if allowedState == state then return true end
    end

    return false
end

function LUASQUARE_CONTROLBINDING.CreateRegistry(name, options)
    name = normalizeId(name) or 'default'
    options = options or {}

    local existing = LUASQUARE_CONTROLBINDING.Registries[name]
    if existing then
        existing.Options = options
        return existing
    end

    local registry = setmetatable({
        Name = name,
        Options = options,
        Controls = {}
    }, Registry)

    LUASQUARE_CONTROLBINDING.Registries[name] = registry
    return registry
end

function Registry:GetTime()
    if self.Options and self.Options.time then return self.Options.time() end
    if CurTime then return CurTime() end
    return os.clock()
end

function Registry:GetState()
    if self.Options and self.Options.getState then return self.Options.getState() end
    return nil
end

function Registry:IsHalted()
    if self.Options and self.Options.isHalted then return self.Options.isHalted() end
    return false
end

function Registry:Log(message)
    if self.Options and self.Options.log then
        self.Options.log(message)
        return
    end

    print('[' .. tostring(self.Name) .. ' CONTROL] ' .. tostring(message))
end

function Registry:Halt(reason)
    if self.Options and self.Options.halt then
        self.Options.halt(reason)
        return
    end

    self:Log(reason)
end

function Registry:GetActorName(actor)
    if self.Options and self.Options.actorName then return self.Options.actorName(actor) end
    if not actor then return nil end
    if type(actor) == 'string' then return actor end
    if actor.Nick then return actor:Nick() end
    if actor.GetName then return actor:GetName() end
    return tostring(actor)
end

function Registry:Register(id, data)
    data = data or {}
    id = normalizeId(id)
    if not id then
        self:Log('Rejected control with missing id')
        return false
    end

    self.Controls[id] = {
        id = id,
        label = data.label or id,
        allowedStates = data.allowedStates or {},
        lockSeconds = tonumber(data.lockSeconds) or tonumber(self.Options.defaultLockSeconds) or 0.25,
        callback = data.callback or data.onUse,
        lockedUntil = 0,
        lastUseTime = nil,
        lastActor = nil,
        data = data
    }

    return true
end

function Registry:Get(id)
    return self.Controls[id]
end

function Registry:IsAvailable(id)
    local control = self:Get(id)
    if not control then return false end
    if self:IsHalted() then return false end
    if not stateAllowed(control, self:GetState()) then return false end
    return self:GetTime() >= (control.lockedUntil or 0)
end

function Registry:Use(id, activator, value)
    local control = self:Get(id)
    if not control then
        self:Log('Unknown control: ' .. tostring(id))
        return false
    end

    local now = self:GetTime()
    if self:IsHalted() then
        self:Log('Rejected control ' .. tostring(id) .. ': simulation halted')
        return false
    end

    if now < (control.lockedUntil or 0) then
        return false
    end

    if not stateAllowed(control, self:GetState()) then
        self:Log('Rejected control ' .. tostring(id) .. ' in state ' .. tostring(self:GetState()))
        return false
    end

    if control.callback then
        local ok, result = pcall(control.callback, activator, value, control)
        if not ok then
            self:Halt('Control ' .. tostring(id) .. ' failed: ' .. tostring(result))
            return false
        end
        if result == false then return false end
    end

    control.lockedUntil = now + (tonumber(control.lockSeconds) or tonumber(self.Options.defaultLockSeconds) or 0.25)
    control.lastUseTime = now
    control.lastActor = self:GetActorName(activator)
    return true
end

function Registry:GetSnapshot()
    local out = {}
    for id, control in pairs(self.Controls) do
        out[id] = {
            id = id,
            label = control.label,
            lockedUntil = control.lockedUntil or 0,
            available = self:IsAvailable(id),
            lastUseTime = control.lastUseTime,
            lastActor = control.lastActor
        }
    end

    return out
end

