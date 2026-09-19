local MAP = LUASQUARE_MAP
local roles = {core = 'rbmk.core', separator = 'plant.separator', turbine = 'plant.turbine', generator = 'plant.generator',
    grid = 'plant.grid', coolant = 'plant.fluid', deaerator = 'plant.deaerator'}
local fields = {}
for name, typeId in pairs(roles) do fields[name] = {type = 'id', reference = typeId} end
local function fraction(amount, capacity) return math.Clamp((amount or 0) / math.max(capacity or 0, 0.0001), 0, 1) end

MAP.RegisterType('rbmk.presentation', {package = 'rbmk', label = 'RBMK alarm telemetry', fields = fields,
    validateDefinition = function(node, compiled)
        for field, typeId in pairs(roles) do
            local target = compiled.nodes[node.config[field]]
            if not target or target.type ~= typeId then return false, field .. ': incompatible plant role' end
        end
        return true
    end,
    register = function(instance, node)
        local core = instance:Get(node.config.core)
        local separator, turbine, generator = instance:Get(node.config.separator), instance:Get(node.config.turbine), instance:Get(node.config.generator)
        local grid, coolant, deaerator = instance:Get(node.config.grid), instance:Get(node.config.coolant), instance:Get(node.config.deaerator)
        MAP.RegisterTelemetry(instance, node, function()
            local separatorLevel = fraction(separator.waterAmount, separator.maxWaterAmount) * 100
            local coolantLevel, deaeratorLevel = fraction(coolant.amount, coolant.maxAmount) * 100, fraction(deaerator.amount, deaerator.maxAmount) * 100
            local rodPower = core.GetControlRodPowerState()
            local leaks, lastLeak = core.GetFuelChannelLeakCount(), core.EventState and core.EventState.LastFuelLeak
            local recirculationThreshold = (core.RecirculationRatedFlow or 16000) * 0.25
            local availableMW = math.max(grid.lastAvailableMW or 0, 0.0001)
            local coolantThreshold = coolant.coolantHighTemperature or 60
            local deaeratorPressureThreshold = deaerator.highPressure or deaerator.maxPressure or 10
            local deaeratorTemperatureThreshold = deaerator.highTemperature or 120
            local messages = {
                fuel_channel_leak = lastLeak and string.format('%d CHANNEL(S), LAST %d,%d', leaks, lastLeak.x or 0, lastLeak.y or 0) or string.format('%d CHANNEL(S)', leaks),
                control_rods_unpowered = string.format('%.3f / %.3f MW', rodPower.acceptedMW or 0, rodPower.demandMW or 0),
                scram_rods_stuck = string.format('%d ROD(S)', rodPower.stuckCount or 0),
                rbmk_integrity_low = string.format('%.0f%%', (core.IntegrityScore or 1) * 100),
                recirculation_flow_low = string.format('%.0f / %.0f/s', core.LastEffectiveCoreFlow or 0, recirculationThreshold),
                rbmk_dryout_risk = string.format('%.0f%%', (core.LastDryoutRisk or 0) * 100),
                steam_separator_low_level = string.format('%.0f%%', separatorLevel), steam_separator_high_level = string.format('%.0f%%', separatorLevel),
                steam_separator_high_pressure = string.format('%.1f bar', separator.pressure or 0), steam_wet_carryover = string.format('%.1f/s', separator.lastCarryover or 0),
                station_grid_overload = string.format('%.1f / %.1f MW', grid.lastLoadMW or 0, availableMW),
                cooling_water_high_temperature = string.format('%.1f / %.1f C', coolant.temperature or 0, coolantThreshold),
                cooling_water_low_level = string.format('%.0f%%', coolantLevel),
                deaerator_high_pressure = string.format('%.1f / %.1f bar', deaerator.pressure or 0, deaeratorPressureThreshold),
                deaerator_high_temperature = string.format('%.1f / %.1f C', deaerator.temperature or 0, deaeratorTemperatureThreshold),
                deaerator_flooded = string.format('%.0f%%', deaeratorLevel)
            }
            return {
                alarms = {rpvPressure = core.RPVPressure or 0, rpvTemperature = core.MaxHeat or 0, fuelChannelLeakCount = leaks,
                    controlRodDemandMW = rodPower.demandMW or 0, controlRodsPowered = rodPower.powered == true, scramRodsStuck = rodPower.stuckCount or 0,
                    integrity = core.IntegrityScore or 1, recirculationFlow = core.LastEffectiveCoreFlow or 0, recirculationThreshold = recirculationThreshold,
                    thermalMW = core.LastThermalMW or 0, dryoutRisk = core.LastDryoutRisk or 0, separatorPresent = true, separatorLevel = separatorLevel,
                    separatorPressure = separator.pressure or 0, separatorCarryover = separator.lastCarryover or 0, turbineTripped = turbine.tripped or false,
                    reversePowerTimer = generator.reversePowerTimer or 0, gridPresent = true, gridLoadMW = grid.lastLoadMW or 0,
                    gridOverloadThreshold = availableMW * (grid.overloadTripFraction or 1.15), coolantPresent = true,
                    coolantTemperature = coolant.temperature or 0, coolantTemperatureThreshold = coolantThreshold, coolantLevel = coolantLevel,
                    deaeratorPresent = true, deaeratorPressure = deaerator.pressure or 0, deaeratorPressureThreshold = deaeratorPressureThreshold,
                    deaeratorTemperature = deaerator.temperature or 0, deaeratorTemperatureThreshold = deaeratorTemperatureThreshold,
                    deaeratorFlooded = deaerator.flooded or false, deaeratorLevel = deaeratorLevel, messages = messages}
            }
        end)
    end})
