local MAP = LUASQUARE_MAP
local number = {type = 'number', min = 0, max = 1e9}
local boolean = {type = 'boolean'}
local percent = {type = 'number', min = 0, max = 100}
local adjustment = {type = 'number', min = -100, max = 100}
local startOrder = {fluid = 30, valve = 31, pump = 32, separator = 33, turbine = 34, condenser = 35,
    heat_exchanger = 36, deaerator = 37, cooling_tower = 38, grid = 39, breaker = 39, transformer = 39, diesel = 40, generator = 41}
local function endpointFluid(compiled, ref)
    local node = ref and compiled.nodes[ref.component]
    local port = node and (MAP.Types[node.type].ports or {})[ref.port]
    if not port then return nil end
    if port.fluid then return port.fluid end
    if node.type == 'plant.fluid' or node.type == 'plant.boundary' then
        local fluid = node.config.fluidType or 'water'
        -- Existing coolant networks contain water; preserve tower/makeup links.
        return fluid == 'coolant' and 'water' or fluid
    end
    if node.type == 'plant.separator' or node.type == 'plant.deaerator' or node.type == 'plant.cooling_tower' then return 'water' end
end
local actions = {
    pump = {speed = {'SetPumpSpeed', {type = 'integer', min = 1, max = 32}, 'speedLevel'}, enabled = {'SetPump', boolean, 'enabled'}, target = {'SetRegulationTarget', percent, 'regulationTarget'}},
    valve = {enabled = {'SetValve', boolean, 'open'}},
    heat_exchanger = {enabled = {'SetHeatExchanger', boolean, 'enabled'}},
    cooling_tower = {enabled = {'SetCoolingTower', boolean, 'enabled'}},
    grid = {enabled = {'SetGridEnabled', boolean, 'enabled'}, reset = {'ResetGrid'}, demand = {'SetGridDemand', number, 'demandMW'}},
    breaker = {closed = {'SetBreaker', boolean, 'closed'}, reset = {'ResetBreaker'}},
    transformer = {enabled = {'SetTransformer', boolean, 'closed'}},
    generator = {sync = {'Sync'}, reset = {'ResetTrip'}, auto_sync = {'SetAutoSync', boolean, 'autoSync'}, trip = {'Trip', critical = true}},
    diesel = {enabled = {'SetEnabled', boolean, 'enabled'}, target = {'SetTargetMW', number, 'targetMW'}},
    turbine = {valve = {'AdjustValvePercent', adjustment, 'valve'}, bypass = {'AdjustBypassValvePercent', adjustment, 'bypassValve'}, repair = {'Repair'}, extreme_trip = {'TestExtremeTrip', critical = true}},
    deaerator = {steam = {'AdjustSteamValvePercent', adjustment, 'steamValve'}, relief = {'AdjustReliefValvePercent', adjustment, 'reliefValve'}, overflow = {'SetOverflowValvePercent', percent, 'overflowValve'}, auto = {'SetAutoRegulator', boolean, 'autoRegulator'}}
}
local function convertPositions(config)
    local result = MAP.Copy(config)
    for key, value in pairs(result) do
        if (key:match('Pos$') or key:match('Offset$')) and type(value) == 'table' then result[key] = Vector(value[1], value[2], value[3]) end
    end
    result.tickInterval = nil
    return result
end
local function fluidPort(kind, namespace, id, object)
    local amountKey, capacityKey, temperatureKey, pressureKey, remove, add
    if kind == 'fluid' then
        amountKey, capacityKey, temperatureKey, pressureKey = 'amount', 'maxAmount', 'temperature', 'pressure'
        remove = function(value) return namespace.RemoveFluid(id, value) end
        add = function(value, temperature) return namespace.AddFluid(id, value, temperature) end
    elseif kind == 'separator' then
        amountKey, capacityKey, temperatureKey, pressureKey = 'waterAmount', 'maxWaterAmount', 'waterTemperature', 'pressure'
        remove = function(value) return namespace.RemoveWater(id, value) end
        add = function(value, temperature) return namespace.AddWater(id, value, temperature) end
    elseif kind == 'deaerator' then
        amountKey, capacityKey, temperatureKey, pressureKey = 'amount', 'maxAmount', 'temperature', 'pressure'
        remove = function(value) return namespace.RemoveWater(id, value) end
        add = function(value, temperature) return namespace.AddWater(id, value, temperature) end
    elseif kind == 'cooling_tower' then
        amountKey, capacityKey, temperatureKey, pressureKey = 'basinAmount', 'basinMaxAmount', 'basinTemperature', 'basinPressure'
        add = function(value, temperature) return namespace.AddToBasin(id, value, temperature) end
    else return end
    return {snapshot = function()
        if kind == 'deaerator' then namespace.UpdatePressure(object)
        elseif kind == 'separator' then namespace.GetPressure(id)
        elseif kind == 'cooling_tower' then object.basinPressure = namespace.GetBasinPressure(id) end
        return {amount = object[amountKey], temperature = object[temperatureKey], pressure = object[pressureKey],
            levelPercent = math.Clamp((object[amountKey] or 0) / math.max(object[capacityKey] or 0, 0.0001) * 100, 0, 100)}
        end, remove = remove, restore = add, add = function(value, _, temperature) return add(value, temperature) end}
end

MAP.RegisterType('plant.boundary', {package = 'powerplant', label = 'External fluid supply or drain', fields = {
    mode = {type = 'string', choices = {supply = true, drain = true}},
    fluidType = {type = 'string', choices = {water = true, steam = true, diesel = true, coolant = true}, default = 'water'},
    temperature = {type = 'number', min = -273.15, max = 10000, default = 20, unit = 'C'},
    pressure = {type = 'number', min = 0, max = 1e6, default = 0, unit = 'bar'}},
    ports = {fluid = {kind = 'fluid', direction = 'both', unit = 'L'}},
    link = function(instance, node)
        local supply = node.config.mode == 'supply'
        instance:Own(LUASQUARE_ENDPOINT.Register(node.id, 'fluid', {
            snapshot = function() return {amount = supply and math.huge or 0, pressure = node.config.pressure,
                temperature = node.config.temperature, levelPercent = supply and 100 or 0} end,
            remove = function(amount) return supply and math.max(amount, 0) or 0 end,
            restore = function(amount) return math.max(amount, 0) end,
            add = function(amount) return not supply and math.max(amount, 0) or 0 end
        }))
    end})

for kind, specification in pairs(MAP.PlantDefinitions) do
    local typeId = 'plant.' .. kind
    local ports = {instance = {kind = typeId, direction = 'both'}}
    if kind == 'fluid' or kind == 'separator' or kind == 'deaerator' or kind == 'cooling_tower' then ports.fluid = {kind = 'fluid', direction = 'both', unit = 'L'} end
    for field, target in pairs(specification.references or {}) do ports[field] = {kind = 'plant.' .. target, direction = 'both', maxLinks = 1} end
    for field in pairs(specification.endpoints or {}) do ports[field] = {kind = field == 'boiler' and 'thermal' or 'fluid', direction = 'both', maxLinks = 1, unit = field == 'boiler' and 'MW' or 'L'} end
    if kind == 'pump' then ports.source.direction, ports.target.direction = 'in', 'out' end
    if kind == 'valve' then ports.a.direction, ports.b.direction = 'in', 'out' end
    if ports.boiler then ports.boiler.direction = 'in' end
    if ports.overflowTarget then ports.overflowTarget.direction = 'out' end
    MAP.RegisterType(typeId, {
        package = 'powerplant', label = kind, fields = specification.fields, ports = ports, startOrder = startOrder[kind], generation = specification.generation,
        validateDefinition = function(node, compiled)
            if kind == 'pump' or kind == 'valve' then
                local first, second = kind == 'pump' and 'source' or 'a', kind == 'pump' and 'target' or 'b'
                local from, to = MAP.Linked(compiled, node.id, first) or node.config[first], MAP.Linked(compiled, node.id, second) or node.config[second]
                local a, b = endpointFluid(compiled, from), endpointFluid(compiled, to)
                if a and b and a ~= b then return false, 'incompatible fluid capabilities: ' .. a .. ' to ' .. b end
                local source, target = from and compiled.nodes[from.component], to and compiled.nodes[to.component]
                if source and source.type == 'plant.boundary' and source.config.mode ~= 'supply' then return false, 'drain boundary cannot supply fluid' end
                if target and target.type == 'plant.boundary' and target.config.mode ~= 'drain' then return false, 'supply boundary cannot receive fluid' end
            end
            if node.config.ruptureRelays then
                for _, id in ipairs(node.config.ruptureRelays) do
                    local binding = compiled.nodes[id]
                    if not binding or binding.type ~= 'source.binding' or binding.config.profile ~= 'relay' or #binding.config.targets ~= 1 then return false, 'ruptureRelays requires relay bindings' end
                end
            end
            for field, profile in pairs(specification.bindings or {}) do
                local id = node.config[field]
                local binding = id and compiled.nodes[id]
                if id and (not binding or binding.type ~= 'source.binding' or binding.config.profile ~= profile or #binding.config.targets ~= 1) then
                    return false, field .. ': expected one ' .. profile .. ' Source binding'
                end
            end
            for field, target in pairs(specification.references or {}) do
                local linked = MAP.Linked(compiled, node.id, field)
                local id = linked and linked.component or node.config[field]
                if id and id ~= 'void' then
                    if not compiled.nodes[id] or compiled.nodes[id].type ~= 'plant.' .. target then return false, field .. ': missing or incompatible component ' .. id end
                end
            end
            for field in pairs(specification.endpoints or {}) do
                local ref = MAP.Linked(compiled, node.id, field) or node.config[field]
                if ref then
                    local other = compiled.nodes[ref.component]
                    local port = other and (MAP.Types[other.type].ports or {})[ref.port]
                    if not port or port.kind ~= (field == 'boiler' and 'thermal' or 'fluid') then return false, field .. ': missing or incompatible endpoint' end
                end
            end
            if kind == 'pump' and node.config.speedLevels and (node.config.speedLevel or 1) > #node.config.speedLevels then return false, 'speed level exceeds speed levels' end
            return true
        end,
        create = function(instance, node)
            local namespace = _G[specification.namespace]
            local storage = namespace[specification.storage]
            if storage[node.id] then return false, 'runtime ID collision' end
            instance:Own(function() storage[node.id] = nil end)
            local config = convertPositions(node.config)
            for field in pairs(specification.bindings or {}) do
                if config[field] then config[field] = instance.compiled.nodes[config[field]].config.targets[1] end
            end
            for field in pairs(specification.references or {}) do
                local ref = MAP.Linked(instance.compiled, node.id, field)
                if ref then config[field] = ref.component end
            end
            for field in pairs(specification.endpoints or {}) do config[field] = MAP.Linked(instance.compiled, node.id, field) or config[field] end
            if config.ruptureRelays then
                for index, id in ipairs(config.ruptureRelays) do config.ruptureRelays[index] = instance.compiled.nodes[id].config.targets[1] end
            end
            -- Explicit generator/breaker nodes are constructed first by dependsOn;
            -- do not let legacy constructors silently create unowned instances.
            if kind == 'pump' and config.peakMW and not LUASQUARE_POWERGRID.GetBreaker(config.breaker) then return false, 'pump requires constructed breaker' end
            if kind == 'generator' and not LUASQUARE_POWERGRID.GetBreaker(config.breaker) then return false, 'generator requires constructed breaker' end
            if kind == 'diesel' and not LUASQUARE_POWERGENERATOR.GetGenerator(config.generator) then return false, 'diesel requires constructed generator' end
            namespace[specification.register](node.id, config)
            local object = storage[node.id]
            if not object then return false, 'constructor did not produce component' end
            return object
        end,
        link = function(instance, node, object)
            local namespace = _G[specification.namespace]
            local endpoint = fluidPort(kind, namespace, node.id, object)
            if endpoint then instance:Own(LUASQUARE_ENDPOINT.Register(node.id, 'fluid', endpoint)) end
            if kind == 'generator' and object.turbine then
                local turbine = instance:Get(object.turbine)
                if turbine then turbine.generator = node.id end
            end
            return true
        end,
        register = function(instance, node, object)
            MAP.RegisterTelemetry(instance, node, function()
                local snapshot = MAP.PrimitiveSnapshot(object)
                if object.maxAmount then snapshot.levelPercent = (object.amount or 0) / math.max(object.maxAmount, 0.0001) * 100 end
                if object.maxWaterAmount then snapshot.levelPercent = (object.waterAmount or 0) / math.max(object.maxWaterAmount, 0.0001) * 100 end
                if object.maxSteamAmount then snapshot.steamPercent = (object.steamAmount or 0) / math.max(object.maxSteamAmount, 0.0001) * 100 end
                if object.maxPressure then snapshot.pressureFraction = (object.pressure or 0) / math.max(object.maxPressure, 0.0001) end
                if kind == 'turbine' then
                    snapshot.valvePercent = (object.valve or 0) * 100
                    snapshot.bypassPercent = (object.bypassValve or 0) * 100
                    snapshot.exhaustFraction = (object.exhaustPressure or 0) / math.max(object.exhaustHardMaxPressure or 1, 0.0001)
                    snapshot.exhaustWarn = (object.exhaustPressure or 0) >= (object.exhaustTripPressure or 0)
                    snapshot.vibrationFraction = (object.vibration or 0) / math.max(object.tripVibration or 1, 0.0001)
                    snapshot.vibrationPercent = snapshot.vibrationFraction * 100
                elseif kind == 'generator' then
                    snapshot.reverseFlow = (object.lastAcceptedMW or 0) < 0
                    snapshot.reverseWarn = (object.lastReverseMW or 0) > (object.reversePowerTripMW or 0)
                    snapshot.gridFrequency = (instance:Get(object.grid) or {}).frequency or 0
                elseif kind == 'deaerator' then
                    snapshot.mode = object.autoRegulator and 'AUTO' or 'MAN'
                    snapshot.levelFraction = (object.amount or 0) / math.max(object.maxAmount or 0, 0.0001)
                    snapshot.pressureHigh = (object.pressure or 0) >= (object.highPressure or 10)
                    snapshot.temperatureHigh = (object.temperature or 0) >= (object.highTemperature or 120)
                    snapshot.temperatureFraction = math.Clamp(((object.temperature or 20) - 20) / math.max((object.highTemperature or 120) - 20, 1), 0, 1)
                    snapshot.steamValvePercent = (object.steamValve or 0) * 100
                    snapshot.reliefValvePercent = (object.reliefValve or 0) * 100
                    snapshot.overflowValvePercent = (object.overflowValve or 0) * 100
                elseif kind == 'grid' then
                    local available = math.max(object.lastAvailableMW or object.sourceCapacityMW or 0, 0.0001)
                    snapshot.loadFraction = (object.lastLoadMW or 0) / available
                    snapshot.overload = snapshot.loadFraction > (object.overloadTripFraction or 1.15)
                end
                return snapshot
            end)
            MAP.BindPlantActions(instance, node, object, _G[specification.namespace], actions[kind] or {})
        end,
        start = function(instance, node)
            local namespace = _G[specification.namespace]
            instance.startedPlant = instance.startedPlant or {}
            if instance.startedPlant[specification.namespace] then return end
            instance.startedPlant[specification.namespace] = true
            local interval = (instance.compiled.startup.intervals or {})[specification.namespace] or node.config.tickInterval or namespace.TickInterval
            if not MAP.Finite(interval) or interval < 0.02 or interval > 10 then return false, 'invalid tick interval' end
            namespace.TickInterval = interval
            local timerName = 'LUASQUARE_MAP_' .. instance.id .. '_' .. specification.namespace
            instance:Own(function() timer.Remove(timerName) end)
            timer.Create(timerName, interval, 0, namespace.UpdateAll)
        end,
        stop = function(_, _, object)
            if not object then return end
            if kind == 'turbine' then
                for _, name in ipairs({object.soundEntity or '', object.soundEntity2 or ''}) do
                    if name ~= '' then LUASQUARE_TURBINE.FireEnt(name, 'StopSound') end
                end
                if object.shakeEntity then LUASQUARE_TURBINE.FireEnt(object.shakeEntity, 'StopShake') end
            end
        end,
        destroy = function(_, node, object)
            local storage = _G[specification.namespace][specification.storage]
            if object and storage[node.id] == object then storage[node.id] = nil end
        end
    })
end
