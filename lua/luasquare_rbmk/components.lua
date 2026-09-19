local MAP = LUASQUARE_MAP
include('luasquare_rbmk/schema.lua')
local fields = {
    model = {type = 'string', default = 'RBMK', maxLength = 128},
    origin = {type = 'vector', default = {0, 0, 0}, unit = 'HU'},
    spacing = {type = 'number', default = 64, min = 1, max = 4096, unit = 'HU'},
    width = {type = 'integer', min = 1, max = 128}, height = {type = 'integer', min = 1, max = 128},
    column = {type = 'vector', default = {64, 64, 256}, unit = 'HU'},
    hollowPercent = {type = 'number', min = 0.01, max = 100, default = 10},
    initialWaterPercent = {type = 'number', min = 0, max = 100, default = 0},
    tickInterval = {type = 'number', min = 0.02, max = 10, default = 0.1},
    separator = {type = 'id', optional = true}, steamNetwork = {type = 'id', optional = true}, drainNetwork = {type = 'id', optional = true},
    grid = {type = 'id', optional = true}, breaker = {type = 'id', optional = true},
    blowoutValvePrefix = {type = 'string', maxLength = 96, default = ''},
    blowoutValveCount = {type = 'integer', min = 0, max = 1024, default = 0},
    catastrophicRelay = {type = 'id', optional = true}, fuelLeakRelay = {type = 'id', optional = true}, fuelMeltdownRelay = {type = 'id', optional = true},
    cells = {type = 'array', maxItems = 16384, items = {type = 'object', fields = {
        x = {type = 'integer', min = 1, max = 128}, y = {type = 'integer', min = 1, max = 128},
        kind = {type = 'string', choices = {fuel = true, steam = true, control = true, reflector = true, blank = true, source = true, absorber = true, void = true}},
        fuel = {type = 'string', optional = true}, name = {type = 'string', maxLength = 128, optional = true},
        group = {type = 'string', maxLength = 128, optional = true}, indicator = {type = 'id', optional = true},
        visual = {type = 'id', optional = true}, insertion = {type = 'number', min = 0, max = 1, optional = true},
        graphiteTip = {type = 'boolean', optional = true}, reflector = {type = 'boolean', optional = true},
        sourceStrength = {type = 'number', min = 0, max = 1e9, optional = true}, closedSource = {type = 'boolean', optional = true},
        reflectorIn = {type = 'boolean', optional = true}, autoRegulator = {type = 'boolean', optional = true},
        autoMaxInsertion = {type = 'number', min = 0, max = 1, optional = true}}}},
    autofill = {type = 'object', optional = true, fields = {ignoreEdge = {type = 'boolean', default = true}, ignoreNearVoid = {type = 'boolean', default = true}}}
}
local numericSettings = 'RPVHeatDiffusion RPVMinSteamSpaceFraction SteamExpansionRatio SteamPressureFactor WaterBoilingPressureFactor CoolingOptimalWaterFraction CoolingLowWaterFraction CoolingLowEfficiency CoolingDryEfficiency RPVMaxPressure RPVHardPressure BlowoutPressure CatastrophicPressure BlowoutCooldown BlowoutColumnCooldown BlowoutMinColumnsPerPass BlowoutMaxColumnsPerPass BlowoutSteamLoss FuelLeakTemperature FuelMeltdownTemperature SteamOutletFlowRate SteamOutletRatedPressureDelta DrainFlowRate AutoRegulatorTargetMW AutoRegulatorMaxInsertion AutoRegulatorKp AutoRegulatorKi AutoRegulatorKd FluxRange TotalFluxSubtractDefine ControlrodScramBoost RodMoveDistance RecirculationRatedFlow NaturalCirculationFraction NaturalCirculationMinLevelFraction CoreHoldUpSeconds ControlRodMWPerRod IntegrityTemperatureDamageStart IntegrityTemperatureSevere IntegrityPressureDamageStart IntegrityPressureSevere ScramStuckBaseChance ScramStuckDamageChance ScramStuckMaxChance'
local settingFields, settingKeys = {}, {}
for name in numericSettings:gmatch('%S+') do
    local key = name:sub(1, 1):lower() .. name:sub(2)
    settingKeys[key] = name
    settingFields[key] = {type = 'number', min = 0, max = 1e12, optional = true}
    if name:find('Fraction') or name:find('Efficiency') or name:find('Chance') or name == 'AutoRegulatorMaxInsertion' then settingFields[key].max = 1 end
end
for name in ('BlowoutEnabled SteamOutletOpen FeedwaterInletOpen DrainValveOpen AutoRegulatorEnabled AutoRegulatorUsePID ControlRodPowerAllOrNothing'):gmatch('%S+') do
    local key = name:sub(1, 1):lower() .. name:sub(2)
    settingKeys[key] = name
    settingFields[key] = {type = 'boolean', optional = true}
end
fields.settings = {type = 'object', fields = settingFields, default = MAP.Object()}
local fuelIds = {EMPTY = true, MEU = true, MOX = true, HEU = true, WGU = true, XEN = true, YME = true, YMX = true}
fields.fuelPresets = {type = 'array', default = MAP.Array(), maxItems = 128, items = {type = 'object', fields = {
    id = {type = 'string', maxLength = 128}, model = {type = 'string', choices = fuelIds},
    name = {type = 'string', maxLength = 128, optional = true},
    yield = {type = 'number', min = 0, max = 1e15, optional = true},
    depletion = {type = 'number', min = 0, max = 1, optional = true},
    meltingPoint = {type = 'number', min = 0, max = 1e6, optional = true, unit = 'C'},
    heatFactor = {type = 'number', min = 0, max = 1e6, optional = true},
    diffusion = {type = 'number', min = 0, max = 1, optional = true}}}}
MAP.RegisterType('rbmk.core', {
    package = 'rbmk', fields = fields, label = 'RBMK vessel', startOrder = 10,
    capacities = {MaxWater = {unit = 'L'}, MaxSteam = {unit = 'L'}, HardMaxSteam = {unit = 'L'}, SteamSpace = {unit = 'L'},
        RPVMaxPressure = {unit = 'bar'}, RPVHardPressure = {unit = 'bar'}, SteamExpansionRatio = {unit = 'ratio'}, WaterLatentHeatKJPerL = {unit = 'kJ/L'}},
    ports = {instance = {kind = 'rbmk.core', direction = 'both'},
        water = {kind = 'fluid', direction = 'both', fluid = 'water', unit = 'L'},
        steam = {kind = 'fluid', direction = 'both', fluid = 'steam', unit = 'L'},
        recirculation = {kind = 'fluid', direction = 'in', fluid = 'water', unit = 'L'},
        thermal = {kind = 'thermal', direction = 'out', unit = 'MW'}},
    validateDefinition = MAP.Validators['rbmk.core'],
    create = function(instance, node)
        local core, err = LUASQUARE_RBMK.Create(node.id)
        if not core then return false, err end
        instance:Own(core.Destroy)
        local config = node.config
        local function target(id) return id and instance.compiled.nodes[id].config.targets[1] end
        for _, preset in ipairs(config.fuelPresets) do
            local definition = {}
            for key, value in pairs(core.FuelTypes[preset.model]) do definition[key] = value end
            for key, value in pairs(preset) do if key ~= 'id' and key ~= 'model' then definition[key] = value end end
            core.FuelTypes[preset.id] = definition
        end
        core.ModelName, core.WorldOrigin, core.CellSpacing = config.model, Vector(unpack(config.origin)), config.spacing
        core.TickInterval = config.tickInterval
        for key, value in pairs(config.settings) do core[settingKeys[key]] = value end
        core.CalculateColumnVolume(config.column[1], config.column[2], config.column[3], config.hollowPercent)
        core.CreateMatrix(config.width, config.height)
        local constructors = {steam = core.CreateSteamChannel, blank = core.CreateBlank, void = core.CreateVoid, absorber = core.CreateAbsorber}
        for _, data in ipairs(config.cells) do
            local cell
            if data.kind == 'fuel' then cell = core.CreateFuelChannel(data.fuel)
            elseif data.kind == 'source' then cell = core.CreateNeutronSource(data.sourceStrength, data.closedSource)
            elseif data.kind == 'reflector' then cell = core.CreateReflector(data.reflectorIn)
            elseif data.kind == 'control' then
                cell = core.CreateControlRod(data.name, data.group, target(data.indicator), target(data.visual), data.graphiteTip, data.reflector, data.insertion)
                cell.autoRegulator = data.autoRegulator == true
                cell.autoMaxInsertion = data.autoMaxInsertion or core.AutoRegulatorMaxInsertion
            else cell = constructors[data.kind]() end
            core.SetCell(data.x, data.y, cell)
        end
        if config.autofill then core.FillBlanksWithSteam(config.autofill) else core.RecalculatePools() end
        core.AddInitialWater(config.initialWaterPercent)
        core.BlowoutFallbackValveCount = 0
        core.ClearBlowoutValves()
        for index = 0, config.blowoutValveCount - 1 do
            local name = config.blowoutValvePrefix .. '_' .. index
            local entities = ents.FindByName(name)
            if #entities ~= 1 or not IsValid(entities[1]) or entities[1]:GetClass() ~= 'func_movelinear' then
                return false, 'blowout mover must resolve to one func_movelinear: ' .. name
            end
            local valve = core.RegisterBlowoutValve(name)
            valve.ent, valve.resolved = entities[1], true
        end
        core.CatastrophicFailureRelay, core.FuelLeakRelay, core.FuelMeltdownRelay = target(config.catastrophicRelay), target(config.fuelLeakRelay), target(config.fuelMeltdownRelay)
        return core
    end,
    link = function(_, node, core)
        core.SetSteamSeparator(node.config.separator)
        core.SetSteamNetwork(node.config.steamNetwork)
        core.SetDrainNetwork(node.config.drainNetwork)
        core.ControlRodPowerGrid, core.ControlRodPowerBreaker = node.config.grid, node.config.breaker
    end,
    register = function(instance, node, core)
        MAP.RegisterTelemetry(instance, node, function()
            local snapshot = MAP.PrimitiveSnapshot(core)
            snapshot.thermalMW = (core.LastThermalMW or 0) + (core.LastFlashBoilMW or 0)
            snapshot.waterPercent = core.GetWaterFraction() * 100
            snapshot.pressurePercent = core.RPVPressure / math.max(core.RPVMaxPressure, 0.0001) * 100
            snapshot.waterFraction = core.GetWaterFraction()
            snapshot.pressureFraction = core.RPVPressure / math.max(core.RPVMaxPressure, 0.0001)
            snapshot.pressureWarn = snapshot.pressureFraction > 0.85
            snapshot.qualityPercent = (core.LastSteamQuality or 0) * 100
            snapshot.voidPercent = (core.LastVoidFraction or 0) * 100
            snapshot.dryoutWarn = (core.LastDryoutRisk or 0) > 0.6
            snapshot.aprPercent = core.AutoRegulatorTargetInsertion / math.max(core.AutoRegulatorMaxInsertion, 0.0001) * 100
            return snapshot
        end)
        local function action(id, parameters, callback, severity, initialize)
            MAP.RegisterControlAction(instance, node, id, {label = node.id .. ' ' .. id, parameters = parameters, callback = callback, severity = severity, initialize = initialize and callback or nil})
        end
        action('scram', {}, function() core.SCRAM(); return true end, 'critical')
        action('rod_toggle', {name = {type = 'string'}}, function(_, p) return core.Selector.Toggle(p.name) end)
        action('rod_group', {name = {type = 'string'}}, function(_, p) core.Selector.ToggleGroup(p.name); return true end)
        action('rod_clear', {}, function() core.Selector.Clear(); return true end)
        action('rod_target', {value = {type = 'number', min = 0, max = 100, optional = true}}, function(_, params, _, value)
            value = params.value == nil and value or params.value
            if not MAP.Finite(value) or value < 0 or value > 100 then return false, 'invalid rod percentage' end
            return core.Selector.Apply(value)
        end)
        action('apr_target', {value = {type = 'number', min = 0, max = 1e9, optional = true}}, function(_, params, _, value)
            value = params.value == nil and value or params.value
            if not MAP.Finite(value) or value < 0 or value > 1e9 then return false, 'invalid thermal power target' end
            core.SetAutoRegulatorTargetMW(value); core.SetAutoRegulatorEnabled(value > 0); return true
        end, nil, true)
        for suffix, callback in pairs({steam_outlet = core.SetSteamOutletOpen, feedwater_inlet = core.SetFeedwaterInletOpen}) do
            action(suffix, {enabled = {type = 'boolean'}}, function(_, p) callback(p.enabled); return true end)
        end
        for suffix, callback in pairs({neutron_source = core.SetNeutronSourceState, reflector = core.SetReflectorState}) do
            action(suffix, {x = {type = 'integer', min = 1, max = core.Width}, y = {type = 'integer', min = 1, max = core.Height}, enabled = {type = 'boolean'}}, function(_, p) return callback(p.x, p.y, p.enabled) end)
        end
    end,
    start = function(_, _, core) return core.Start() end,
    stop = function(_, _, core) if core then core.Stop() end end,
    destroy = function(_, _, core) if core then core.Destroy() end end
})

-- Instruments subscribe to individual cells; ordinary telemetry never serializes
-- a whole vessel matrix. Debug views have their own bounded instance protocol.
MAP.RegisterType('rbmk.cell', {package = 'rbmk', label = 'RBMK cell telemetry', fields = {
    core = {type = 'id'}, x = {type = 'integer', min = 1, max = 128}, y = {type = 'integer', min = 1, max = 128}},
    validateDefinition = function(node, compiled)
        local core = compiled.nodes[node.config.core]
        if not core or core.type ~= 'rbmk.core' then return false, 'unknown core' end
        if node.config.x > core.config.width or node.config.y > core.config.height then return false, 'cell outside core layout' end
        return true
    end,
    register = function(instance, node)
        local core = instance:Get(node.config.core)
        MAP.RegisterTelemetry(instance, node, function() return MAP.PrimitiveSnapshot(core.GetCell(node.config.x, node.config.y)) end)
    end})
