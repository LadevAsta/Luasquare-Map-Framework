if LUASQUARE_MACHINERY_LOADED then return end
LUASQUARE_MACHINERY_LOADED = true

LUASQUARE_MACHINERY = LUASQUARE_MACHINERY or {}
LUASQUARE_MACHINERY.Registries = LUASQUARE_MACHINERY.Registries or {}

local Registry = {}
Registry.__index = Registry

local function normalizeId(value)
    if value == nil then return nil end
    value = tostring(value)
    if value == '' then return nil end
    return value
end

local function asNumber(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback end
    return value
end

local function copyRoute(route)
    local out = {}
    for i, node in ipairs(route or {}) do out[i] = node end
    return out
end

local function routeHasEdge(route, fromNode, toNode)
    for i = 1, #route - 1 do
        if route[i] == fromNode and route[i + 1] == toNode then return true end
    end

    return false
end

function LUASQUARE_MACHINERY.CreateRegistry(name, options)
    name = normalizeId(name) or 'default'
    options = options or {}

    local existing = LUASQUARE_MACHINERY.Registries[name]
    if existing then
        existing.Options = options
        return existing
    end

    local registry = setmetatable({
        Name = name,
        Options = options,
        Machines = {},
        Paths = {},
        NodeToPaths = {}
    }, Registry)

    LUASQUARE_MACHINERY.Registries[name] = registry
    return registry
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

    print('[' .. tostring(self.Name) .. ' MACHINERY] ' .. tostring(message))
end

function Registry:FireBinding(binding, inputName, value, options)
    if self.Options and self.Options.source and self.Options.source.Fire then
        return self.Options.source:Fire(binding, inputName, value, options)
    end

    if self.Options and self.Options.fire then
        return self.Options.fire(binding, inputName, value, options)
    end

    self:Log('No source binding layer available for ' .. tostring(binding))
    return false
end

function Registry:RegisterMachine(id, data)
    data = data or {}
    id = normalizeId(id)
    if not id then
        self:Log('Rejected machinery with missing id')
        return false
    end

    local speedInputScale = asNumber(data.speedInputScale, 1)
    local configuredSpeed = asNumber(data.configuredSpeed, asNumber(data.spinSpeed, nil))

    self.Machines[id] = {
        id = id,
        type = data.type or data.kind or 'generic',
        binding = data.binding or id,
        label = data.label or id,
        class = data.class,
        all = data.all and true or false,
        forwardInput = data.forwardInput or data.deployInput or 'StartForward',
        backwardInput = data.backwardInput or data.retractInput or 'StartBackward',
        deployInput = data.deployInput or data.forwardInput or 'StartForward',
        retractInput = data.retractInput or data.backwardInput or 'StartBackward',
        stopInput = data.stopInput or 'Stop',
        openInput = data.openInput or 'Open',
        closeInput = data.closeInput or 'Close',
        startInput = data.startInput or 'Start',
        setSpeedInput = data.setSpeedInput or 'SetSpeed',
        setPositionInput = data.setPositionInput or 'SetPosition',
        deploySpeed = data.deploySpeed,
        retractSpeed = data.retractSpeed,
        spinSpeed = data.spinSpeed,
        configuredSpeed = configuredSpeed,
        currentSpeed = asNumber(data.currentSpeed, configuredSpeed),
        sourceSpeed = configuredSpeed and configuredSpeed * speedInputScale or nil,
        speedInputScale = speedInputScale,
        debug = data.debug or {},
        path = data.path,
        currentNode = data.currentNode or data.initialNode,
        initialNode = data.initialNode or data.currentNode,
        deployNode = data.deployNode,
        retractNode = data.retractNode,
        destinationNode = nil,
        route = nil,
        direction = nil,
        state = data.state or 'idle',
        lastCommand = nil,
        lastCommandTime = nil,
        arrivedAt = nil
    }

    return true
end

function Registry:GetMachine(id)
    return self.Machines[id]
end

function Registry:Command(id, inputName, value)
    local machine = self:GetMachine(id)
    if not machine then
        self:Log('Unknown machinery: ' .. tostring(id))
        return false
    end

    local ok = self:FireBinding(machine.binding, inputName, value, { all = machine.all })
    if ok then
        machine.lastCommand = inputName
        machine.lastCommandTime = self:GetTime()
    end

    return ok
end

function Registry:SetSpeed(id, speed)
    local machine = self:GetMachine(id)
    if not machine then return false end

    speed = asNumber(speed, nil)
    if speed == nil then return false end

    local sourceSpeed = speed * (machine.speedInputScale or 1)
    machine.configuredSpeed = speed
    machine.sourceSpeed = sourceSpeed
    if machine.type == 'rotator' then machine.spinSpeed = speed end

    local ok = self:Command(id, machine.setSpeedInput, sourceSpeed)
    if ok then
        machine.currentSpeed = speed
    end

    return ok
end

function Registry:SetPosition(id, position)
    local machine = self:GetMachine(id)
    if not machine then return false end
    return self:Command(id, machine.setPositionInput, position)
end

function Registry:Start(id)
    local machine = self:GetMachine(id)
    if not machine then return false end
    if machine.spinSpeed ~= nil then self:SetSpeed(id, machine.spinSpeed) end
    local ok = self:Command(id, machine.startInput)
    if ok then machine.state = 'running' end
    return ok
end

function Registry:Stop(id)
    local machine = self:GetMachine(id)
    if not machine then return false end
    local ok = self:Command(id, machine.stopInput)
    if ok then
        machine.state = 'stopped'
        machine.direction = nil
        machine.destinationNode = nil
        machine.route = nil
    end
    return ok
end

function Registry:Open(id)
    local machine = self:GetMachine(id)
    if not machine then return false end
    local ok = self:Command(id, machine.openInput)
    if ok then machine.state = 'open' end
    return ok
end

function Registry:Close(id)
    local machine = self:GetMachine(id)
    if not machine then return false end
    local ok = self:Command(id, machine.closeInput)
    if ok then machine.state = 'closed' end
    return ok
end

function Registry:RegisterPath(id, data)
    data = data or {}
    id = normalizeId(id)
    if not id then
        self:Log('Rejected path with missing id')
        return false
    end

    local path = {
        id = id,
        nodes = {},
        edges = {},
        switches = {}
    }

    for _, node in ipairs(data.nodes or {}) do
        node = normalizeId(node)
        if node then
            table.insert(path.nodes, node)
            path.edges[node] = path.edges[node] or {}
            self.NodeToPaths[node] = self.NodeToPaths[node] or {}
            self.NodeToPaths[node][id] = true
        end
    end

    for i = 1, #path.nodes - 1 do
        local a = path.nodes[i]
        local b = path.nodes[i + 1]
        table.insert(path.edges[a], { to = b, direction = 'forward' })
        table.insert(path.edges[b], { to = a, direction = 'backward' })
    end

    for _, edge in ipairs(data.edges or {}) do
        local from = normalizeId(edge.from)
        local to = normalizeId(edge.to)
        if from and to then
            path.edges[from] = path.edges[from] or {}
            table.insert(path.edges[from], { to = to, direction = edge.direction or edge.dir or 'forward' })
        end
    end

    for _, switch in ipairs(data.switches or data.branches or {}) do
        local node = normalizeId(switch.node or switch.from)
        local to = normalizeId(switch.to or switch.branchTo or switch.alternateTo)
        if node and to then
            table.insert(path.switches, {
                node = node,
                to = to,
                binding = switch.binding or switch.id or node,
                enableInput = switch.enableInput or 'EnableAlternatePath',
                disableInput = switch.disableInput or 'DisableAlternatePath'
            })
        end
    end

    self.Paths[id] = path
    return true
end

function Registry:SetPathSwitchesForRoute(pathId, route)
    local path = self.Paths[pathId]
    if not path then return true end

    local ok = true
    for _, switch in ipairs(path.switches or {}) do
        local useAlternate = route and routeHasEdge(route, switch.node, switch.to)
        local inputName = useAlternate and switch.enableInput or switch.disableInput
        ok = self:FireBinding(switch.binding, inputName) and ok
    end

    return ok
end

function Registry:ResetPathSwitches(pathId)
    return self:SetPathSwitchesForRoute(pathId, nil)
end

function Registry:FindRoute(pathId, fromNode, toNode)
    local path = self.Paths[pathId]
    if not path or not fromNode or not toNode then return nil end
    if fromNode == toNode then return { fromNode }, nil end

    local queue = { fromNode }
    local cameFrom = { [fromNode] = false }
    local firstDir = {}
    local head = 1

    while queue[head] do
        local node = queue[head]
        head = head + 1

        for _, edge in ipairs(path.edges[node] or {}) do
            if cameFrom[edge.to] == nil then
                cameFrom[edge.to] = node
                firstDir[edge.to] = node == fromNode and edge.direction or firstDir[node]
                if edge.to == toNode then
                    local route = { toNode }
                    local cursor = node
                    while cursor do
                        table.insert(route, 1, cursor)
                        cursor = cameFrom[cursor]
                    end
                    return route, firstDir[edge.to]
                end
                table.insert(queue, edge.to)
            end
        end
    end

    return nil
end

function Registry:MoveTrackTrainTo(id, destinationNode)
    local machine = self:GetMachine(id)
    if not machine then return false end
    destinationNode = normalizeId(destinationNode)
    if not destinationNode then return false end

    local currentNode = machine.currentNode or machine.initialNode
    if not currentNode then
        self:Log('Tracktrain ' .. tostring(id) .. ' has no known current node')
        return false
    end

    local route, direction = self:FindRoute(machine.path, currentNode, destinationNode)
    if not route then
        self:Log('No path route for ' .. tostring(id) .. ' from ' .. tostring(currentNode) .. ' to ' .. tostring(destinationNode))
        return false
    end

    if currentNode == destinationNode then
        machine.state = 'arrived'
        machine.destinationNode = nil
        machine.route = copyRoute(route)
        machine.arrivedAt = self:GetTime()
        self:ResetPathSwitches(machine.path)
        self:Command(id, machine.stopInput)
        return true
    end

    self:SetPathSwitchesForRoute(machine.path, route)

    if direction == 'backward' then
        if machine.retractSpeed ~= nil then self:SetSpeed(id, machine.retractSpeed) end
        if not self:Command(id, machine.backwardInput) then return false end
    else
        if machine.deploySpeed ~= nil then self:SetSpeed(id, machine.deploySpeed) end
        if not self:Command(id, machine.forwardInput) then return false end
    end

    machine.state = 'moving'
    machine.destinationNode = destinationNode
    machine.route = copyRoute(route)
    machine.direction = direction or 'forward'
    return true
end

function Registry:Deploy(id)
    local machine = self:GetMachine(id)
    if not machine then return false end
    if machine.type == 'tracktrain' and machine.deployNode then
        return self:MoveTrackTrainTo(id, machine.deployNode)
    end

    if machine.deploySpeed ~= nil then self:SetSpeed(id, machine.deploySpeed) end
    local ok = self:Command(id, machine.deployInput)
    if ok then machine.state = 'deploying' end
    return ok
end

function Registry:Retract(id)
    local machine = self:GetMachine(id)
    if not machine then return false end
    if machine.type == 'tracktrain' and machine.retractNode then
        return self:MoveTrackTrainTo(id, machine.retractNode)
    end

    if machine.retractSpeed ~= nil then self:SetSpeed(id, machine.retractSpeed) end
    local ok = self:Command(id, machine.retractInput)
    if ok then machine.state = 'retracting' end
    return ok
end

function Registry:OnPathTrackPassed(nodeName, machineId)
    nodeName = normalizeId(nodeName)
    if not nodeName then return 0 end

    local count = 0
    for id, machine in pairs(self.Machines) do
        if (not machineId or id == machineId) and machine.type == 'tracktrain' then
            local path = self.Paths[machine.path]
            if path and path.edges[nodeName] then
                machine.currentNode = nodeName
                count = count + 1

                if machine.destinationNode == nodeName then
                    self:Command(id, machine.stopInput)
                    self:ResetPathSwitches(machine.path)
                    machine.state = 'arrived'
                    machine.arrivedAt = self:GetTime()
                    machine.destinationNode = nil
                    machine.direction = nil
                    machine.route = nil
                    self:Log('Tracktrain ' .. tostring(id) .. ' arrived at ' .. tostring(nodeName))
                end
            end
        end
    end

    if count <= 0 then self:Log('Path track pass had no matching train: ' .. tostring(nodeName)) end
    return count
end

function Registry:GetSnapshot()
    local out = {}
    for id, machine in pairs(self.Machines) do
        out[id] = {
            id = id,
            label = machine.label,
            type = machine.type,
            binding = machine.binding,
            state = machine.state,
            currentNode = machine.currentNode,
            destinationNode = machine.destinationNode,
            direction = machine.direction,
            configuredSpeed = machine.configuredSpeed,
            currentSpeed = machine.currentSpeed,
            sourceSpeed = machine.sourceSpeed,
            speedInputScale = machine.speedInputScale,
            debug = machine.debug,
            lastCommand = machine.lastCommand,
            lastCommandTime = machine.lastCommandTime
        }
    end

    return out
end
