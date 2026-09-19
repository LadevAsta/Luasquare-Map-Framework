-- Source-facing fields are an allowlist. Runtime-only counters and functions are
-- deliberately absent. Constructors retain their existing defaults for omissions.
local MAP = LUASQUARE_MAP
local function fields(numbers, booleans, strings)
    local result = {}
    for name in (numbers or ''):gmatch('%S+') do
        local unit = name:find('MWh') and 'MWh' or name:find('MW') and 'MW' or name:lower():find('pressure') and 'bar'
            or name:lower():find('temperature') and 'C' or nil
        result[name] = {type = 'number', optional = true, min = unit == 'C' and -273.15 or 0, max = 1e12, unit = unit}
        if name:lower():find('fraction') or name == 'effectiveness' or name == 'separationEfficiency' then result[name].max = 1 end
    end
    for name in (booleans or ''):gmatch('%S+') do result[name] = {type = 'boolean', optional = true} end
    for name in (strings or ''):gmatch('%S+') do result[name] = {type = 'string', maxLength = 128, optional = true} end
    result.monitorPos = {optional = true, oneOf = {{type = 'string', maxLength = 128}, {type = 'vector'}}}
    result.monitorTarget = {type = 'string', maxLength = 128, optional = true}
    result.monitorOffset = {type = 'vector', optional = true}
    result.tickInterval = {type = 'number', min = 0.02, max = 10, optional = true, unit = 's'}
    return result
end
local definitions = {
    fluid = {namespace = 'LUASQUARE_FLUID', register = 'RegisterNetwork', storage = 'Networks',
        fields = fields('amount maxAmount hardMaxAmount volume pressure maxPressure pressureFactor temperature thermalEnergyKJ steamQuality wetCarryover ambientTemperature thermalLossRate serviceRate overflowLevelFraction overflowRate ruptureLeakRate ruptureFlowMultiplier coolantHeatCapacityKJPerL coolantCoolingDelta coolantHighTemperature',
            'serviceEnabled overflowEnabled', 'type fluidType overflowTarget coolingTower'),
        references = {overflowTarget = 'fluid', coolingTower = 'cooling_tower'}},
    valve = {namespace = 'LUASQUARE_VALVE', register = 'RegisterValve', storage = 'Valves',
        fields = fields('maxFlow minFlowFraction', 'open bidirectional'), endpoints = {a = true, b = true}},
    pump = {namespace = 'LUASQUARE_PUMP', register = 'RegisterPump', storage = 'Pumps',
        fields = fields('rate headPressure flowMultiplier minFlowFraction regulationTarget regulationDeadband regulationGain regulationMinOutput peakMW',
            'enabled regulate', 'regulationMode grid breaker'), endpoints = {source = true, target = true, regulationSensor = true},
        references = {grid = 'grid', breaker = 'breaker'}},
    heat_exchanger = {namespace = 'LUASQUARE_HEATEXCHANGER', register = 'RegisterHeatExchanger', storage = 'HeatExchangers',
        fields = fields('effectiveness approachTemperature maxThermalMW heatCapacityKJPerL', 'enabled', 'hotNetwork coldNetwork hotPump coldPump'),
        references = {hotNetwork = 'fluid', coldNetwork = 'fluid', hotPump = 'pump', coldPump = 'pump'}},
    separator = {namespace = 'LUASQUARE_STEAMSEPARATOR', register = 'RegisterSteamSeparator', storage = 'Separators',
        fields = fields('waterAmount maxWaterAmount hardMaxWaterAmount waterTemperature steamAmount maxSteamAmount hardMaxSteamAmount steamVolume steamTemperature maxPressure hardMaxPressure outletValve outputMaxSteamRate ratedOutputPressure separationEfficiency highLevelFraction lowLevelFraction steamRatio steamLatentHeatKJPerL thermalEnergyKJ',
            'enabled', 'drySteamNetwork'), references = {drySteamNetwork = 'fluid'}},
    condenser = {namespace = 'LUASQUARE_CONDENSER', register = 'RegisterCondenser', storage = 'Condensers',
        fields = fields('ratio maxRate outputTemperature effectiveness approachTemperature steamLatentHeatKJPerL coolantHeatCapacityKJPerL maxThermalMW steamAmount steamMaxAmount steamHardMaxAmount steamVolume steamMaxPressure steamTemperature',
            'enabled godMode', 'input output coolantNetwork coolantPump'), references = {input = 'fluid', output = 'fluid', coolantNetwork = 'fluid', coolantPump = 'pump'}},
    deaerator = {namespace = 'LUASQUARE_DEAERATOR', register = 'RegisterDeaerator', storage = 'Deaerators',
        fields = fields('amount maxAmount hardMaxAmount temperature ambientTemperature thermalLossRate pressure maxPressure hardMaxPressure pressureFactor steamSpace steamAmount steamMaxAmount steamTemperature nonCondensibleAmount steamCondenseFraction floodLevelFraction targetTemperature targetPressure pressureDeadband temperatureDeadband highTemperature highPressure regulatorRate steamValve reliefValve overflowValve overflowLevelFraction overflowRate maxSteamRate maxReliefRate floodedReliefFactor steamToWaterRatio steamLatentHeatKJPerL waterHeatCapacityKJPerL',
            'enabled ruptured autoRegulator', 'tankNetwork steamInput steamSource overflowTarget'), references = {tankNetwork = 'fluid', steamInput = 'fluid', steamSource = 'turbine', overflowTarget = 'fluid'}},
    cooling_tower = {namespace = 'LUASQUARE_COOLINGTOWER', register = 'RegisterCoolingTower', storage = 'CoolingTowers',
        fields = fields('maxRate outputTemperature basinAmount basinMaxAmount basinTemperature basinMaxPressure evaporationFraction', 'enabled working', 'output coolantNetwork'),
        references = {output = 'fluid', coolantNetwork = 'fluid'}},
    grid = {namespace = 'LUASQUARE_POWERGRID', register = 'RegisterGrid', storage = 'Grids',
        fields = fields('nominalFrequency frequency voltage phase sourceCapacityMW baseGenerationMW baseLoadMW demandMW currentDemandMW minDemandMW maxDemandMW demandRampMWPerSecond batteryCapacityMWh batteryMWh batteryMaxDischargeMW batteryMaxChargeMW batteryChargeEfficiency batteryDischargeEfficiency inertia droopHz underFrequencyTrip overFrequencyTrip overloadTripFraction overloadTripHardFraction tripDelay',
            'enabled tripped stiff batteryTripOnEmpty', 'type')},
    breaker = {namespace = 'LUASQUARE_POWERGRID', register = 'RegisterBreaker', storage = 'Breakers',
        fields = fields('maxMW demandMW', 'closed tripped', 'grid owner kind'), references = {grid = 'grid'}},
    transformer = {namespace = 'LUASQUARE_POWERGRID', register = 'RegisterTransformer', storage = 'Transformers',
        fields = fields('maxMW', 'enabled closed bidirectional tripped', 'from to'), references = {from = 'grid', to = 'grid'}},
    generator = {namespace = 'LUASQUARE_POWERGENERATOR', register = 'RegisterGenerator', storage = 'Generators',
        fields = fields('ratedMW maxMW outputMW targetMW rampRateMW motoringMW reversePowerTripMW reversePowerTripDelay gridRPM syncRPMTolerance syncPhaseTolerance',
            'enabled tripped synced reversePowerTrips autoStart autoSync syncFailureTrips gridLossTrips', 'type grid breaker turbine'),
        references = {grid = 'grid', breaker = 'breaker', turbine = 'turbine'}},
    diesel = {namespace = 'LUASQUARE_DIESELGENERATOR', register = 'RegisterDieselGenerator', storage = 'Generators',
        fields = fields('fuelTankCapacity fuelTankAmount refuelRate fuelConsumptionPerMWSecond idleFuelRate targetMW ratedMW maxMW', 'enabled', 'generator fuelNetwork'),
        references = {generator = 'generator', fuelNetwork = 'fluid'}},
    turbine = {namespace = 'LUASQUARE_TURBINE', register = 'RegisterTurbine', storage = 'Turbines',
        fields = fields('condenserOutputTemperature bypassCondenserOutputTemperature condenserSteamTemperatureInfluence bypassSteamTemperatureInfluence valve bypassValve maxSteamRate ratedSteamRate bypassMaxSteamRate inletMaxSteamRate maxPressureFlowScale ratedInletPressure ratedPressureDelta steamRatio exhaustRatio condenserRatio exhaustAmount exhaustVolume exhaustMaxAmount exhaustHardMaxAmount exhaustTemperature exhaustTripPressure exhaustTripDelay exhaustHardMaxPressure designRPM gridRPM rpm inertia friction noLoadOverspeed tripRPM syncRPMTolerance syncPhaseTolerance phase efficiency cycleEfficiency mwPerSteamPerSecond loadMW maxMW tripVibration severeTripRPM severeTripBrakeRPM extremeTripRPM extremeTripFlowFraction extremeTripChance soundStopRPM soundMinVolume soundMaxVolume soundMinPitch soundMaxPitch soundStartRPMFraction soundOptimalRPMFraction shakeMaxAmplitude shakeMinAmplitude shakeMaxFrequency shakeMinFrequency shakeStartVibration shakeRepeatInterval',
            'enabled tripped synced autoSync syncFailureTrips useSteamEnergy catastrophicFailed', 'input output bypassOutput condenser bypassCondenser condenserOutput bypassCondenserOutput generator'),
        endpoints = {boiler = true}, references = {input = 'fluid', output = 'fluid', bypassOutput = 'fluid', condenser = 'condenser', bypassCondenser = 'condenser', condenserOutput = 'fluid', bypassCondenserOutput = 'fluid', generator = 'generator'}}
}
definitions.fluid.fields.type.choices = {simple = true, steamline = true, coolant = true}
definitions.fluid.fields.fluidType.choices = {water = true, steam = true, coolant = true, diesel = true}
definitions.grid.fields.type.choices = {offsite = true, onsite = true, auxiliary = true}
definitions.grid.fields.overloadTripFraction.max = 100
definitions.grid.fields.overloadTripHardFraction.max = 100
definitions.generator.fields.type.choices = {static = true, turbine = true}
definitions.pump.fields.regulationMode.choices = {fill = true, drain = true}
definitions.pump.fields.speedLevels = {type = 'array', minItems = 1, maxItems = 32, items = {type = 'number', min = 0, max = 10}, optional = true}
definitions.pump.fields.speedLevel = {type = 'integer', min = 1, max = 32, optional = true}
definitions.pump.fields.regulationTarget.max = 100
for _, kind in ipairs({'fluid', 'deaerator'}) do
    definitions[kind].fields.ruptureRelays = {type = 'array', optional = true, maxItems = 256, items = {type = 'id', reference = 'source.binding'}}
    definitions[kind].references.overflowTarget = nil
    definitions[kind].endpoints = {overflowTarget = true}
end
local relayFields = {
    grid = 'tripRelay resetRelay',
    breaker = 'tripRelay closeRelay openRelay resetRelay demandMetRelay demandUnmetRelay',
    transformer = 'tripRelay resetRelay', generator = 'startRelay stopRelay syncRelay unsyncRelay tripRelay resetRelay',
    turbine = 'startRelay stopRelay syncRelay tripRelay severeTripRelay severeTripStopRelay extremeTripRelay repairRelay resetRelay',
    condenser = 'startRelay stopRelay', cooling_tower = 'startRelay stopRelay workRelay idleRelay'
}
for kind, names in pairs(relayFields) do
    definitions[kind].bindings = {}
    for name in names:gmatch('%S+') do definitions[kind].bindings[name] = 'relay' end
end
definitions.turbine.bindings.soundEntity = 'sound'
definitions.turbine.bindings.soundEntity2 = 'sound'
definitions.turbine.bindings.shakeEntity = 'shake'
for _, definition in pairs(definitions) do
    for name in pairs(definition.bindings or {}) do definition.fields[name] = {type = 'id', optional = true, reference = 'source.binding'} end
    for name, kind in pairs(definition.references or {}) do
        definition.fields[name] = {type = 'id', optional = true, reference = 'plant.' .. kind}
    end
    for name in pairs(definition.endpoints or {}) do
        definition.fields[name] = {type = 'object', optional = true, fields = {component = {type = 'id'}, port = {type = 'port'}}}
    end
end
MAP.PlantDefinitions = definitions
definitions.pump.generation = {{field = 'breaker', type = 'plant.breaker', whenPresent = 'peakMW', owner = true,
    defaults = {kind = 'pump', closed = true}, copy = {grid = {'grid'}, maxMW = {'peakMW'}}}}
definitions.generator.generation = {{field = 'breaker', type = 'plant.breaker', owner = true,
    defaults = {kind = 'generator', closed = false, maxMW = 1}, copy = {grid = {'grid'}, maxMW = {'maxMW', 'ratedMW'}}}}
definitions.diesel.fields.grid = {type = 'id', optional = true, reference = 'plant.grid'}
definitions.diesel.references.grid = 'grid'
definitions.diesel.generation = {{field = 'generator', type = 'plant.generator',
    defaults = {type = 'static', ratedMW = 1, maxMW = 1, outputMW = 0, targetMW = 0, enabled = false},
    copy = {grid = {'grid'}, ratedMW = {'ratedMW', 'maxMW'}, maxMW = {'maxMW', 'ratedMW'}, rampRateMW = {'maxMW', 'ratedMW'}, enabled = {'enabled'}}}}
