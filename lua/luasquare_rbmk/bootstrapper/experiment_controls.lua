-- Trusted reference-map actions. Map instances and Hammer bindings are in control JSON.
local CONTROL = LUASQUARE_CONTROL
local function register(id, label, parameters, callback, severity)
    CONTROL.RegisterAction('rbmk.' .. id, {label = label, parameters = parameters, callback = callback, severity = severity})
end
local name = {type = 'string'}
local enabled = {type = 'boolean'}
local percent = {type = 'number', min = -100, max = 100}
register('pump_speed', 'SPEED', {name = name, level = {type = 'integer', min = 1, max = 4}}, function(_, p) return LUASQUARE_PUMP.SetPumpSpeed(p.name, p.level) end)
register('pump_enabled', 'PUMP', {name = name, enabled = enabled}, function(_, p) return LUASQUARE_PUMP.SetPump(p.name, p.enabled) end)
register('valve', 'VALVE', {name = name, enabled = enabled}, function(_, p) return LUASQUARE_VALVE.SetValve(p.name, p.enabled) end)
register('transformer', 'TRANSFORMER', {name = name, enabled = enabled}, function(_, p) return LUASQUARE_POWERGRID.SetTransformer(p.name, p.enabled) end)
register('grid_reset', 'RESET GRID', {name = name}, function(_, p) return LUASQUARE_POWERGRID.ResetGrid(p.name) end)
register('diesel', 'DIESEL', {name = name, enabled = enabled}, function(_, p) return LUASQUARE_DIESELGENERATOR.SetEnabled(p.name, p.enabled) end)
register('generator_trip', 'TRIP', {name = name}, function(_, p) return LUASQUARE_POWERGENERATOR.Trip(p.name, 'MANUAL_TRIP') end, 'critical')
register('generator_sync', 'SYNC', {name = name}, function(_, p) return LUASQUARE_POWERGENERATOR.Sync(p.name) end)
register('generator_reset', 'RESET TRIP', {name = name}, function(_, p) return LUASQUARE_POWERGENERATOR.ResetTrip(p.name) end)
register('generator_auto_sync', 'AUTO SYNC', {name = name, enabled = enabled}, function(_, p) return LUASQUARE_POWERGENERATOR.SetAutoSync(p.name, p.enabled) end)
register('turbine_valve', 'STEAM VALVE', {name = name, percent = percent}, function(_, p) return LUASQUARE_TURBINE.AdjustValvePercent(p.name, p.percent) end)
register('turbine_bypass', 'BYPASS', {name = name, percent = percent}, function(_, p) return LUASQUARE_TURBINE.AdjustBypassValvePercent(p.name, p.percent) end)
register('turbine_repair', 'REPAIR', {name = name}, function(_, p) return LUASQUARE_TURBINE.Repair(p.name) end)
register('turbine_extreme_trip', 'TEST EXTREME TRIP', {name = name}, function(_, p) return LUASQUARE_TURBINE.TestExtremeTrip(p.name) end, 'critical')
register('deaerator_steam', 'STEAM VALVE', {name = name, percent = percent}, function(_, p) return LUASQUARE_DEAERATOR.AdjustSteamValvePercent(p.name, p.percent) end)
register('deaerator_relief', 'RELIEF', {name = name, percent = percent}, function(_, p) return LUASQUARE_DEAERATOR.AdjustReliefValvePercent(p.name, p.percent) end)
register('deaerator_overflow', 'OVERFLOW', {name = name, percent = {type = 'number', min = 0, max = 100}}, function(_, p) return LUASQUARE_DEAERATOR.SetOverflowValvePercent(p.name, p.percent) end)
register('deaerator_auto', 'AUTO REGULATOR', {name = name, enabled = enabled}, function(_, p) return LUASQUARE_DEAERATOR.SetAutoRegulator(p.name, p.enabled) end)
register('neutron_source', 'NEUTRON SOURCE', {x = {type = 'integer', min = 1, max = 128}, y = {type = 'integer', min = 1, max = 128}, enabled = enabled}, function(_, p) return RBMK.SetNeutronSourceState(p.x, p.y, p.enabled) end)
register('reflector', 'REFLECTOR', {x = {type = 'integer', min = 1, max = 128}, y = {type = 'integer', min = 1, max = 128}, enabled = enabled}, function(_, p) return RBMK.SetReflectorState(p.x, p.y, p.enabled) end)
register('steam_outlet', 'STEAM OUTLET', {enabled = enabled}, function(_, p) return RBMK.SetSteamOutletOpen(p.enabled) end)
register('feedwater_inlet', 'FEEDWATER INLET', {enabled = enabled}, function(_, p) return RBMK.SetFeedwaterInletOpen(p.enabled) end)
register('scram', 'SCRAM', {}, function() return RBMK.SCRAM() end, 'critical')
register('rod_toggle', 'SELECT ROD', {name = name}, function(_, p) return LUASQUARE_ROD_SELECTOR.Toggle(p.name) end)
register('rod_group', 'SELECT GROUP', {name = name}, function(_, p) return LUASQUARE_ROD_SELECTOR.ToggleGroup(p.name) end)
register('rod_clear', 'CLEAR SELECTION', {}, function() return LUASQUARE_ROD_SELECTOR.Clear() end)
register('alarm_reset', 'RESET ALARMS', {}, function() return LUASQUARE_ANNUNCIATOR.Reset() end)
register('alarm_ack', 'ACK ALARMS', {}, function() return LUASQUARE_ANNUNCIATOR.Acknowledge() end)
register('alarm_mute', 'MUTE ALARMS', {}, function() return LUASQUARE_ANNUNCIATOR.Mute() end)
register('alarm_test', 'TEST ALARMS', {}, function() return LUASQUARE_ANNUNCIATOR.TestAll() end)
register('feedwater_target', 'TARGET %', {}, function(_, _, _, value)
    if not LUASQUARE_PUMP.GetPump('feedwater_pump_a') or not LUASQUARE_PUMP.GetPump('feedwater_pump_b') then return false, 'paired pumps missing' end
    LUASQUARE_PUMP.SetRegulationTarget('feedwater_pump_a', value)
    LUASQUARE_PUMP.SetRegulationTarget('feedwater_pump_b', value)
    return true
end)

CONTROL.Actions['rbmk.pump_speed'].getValue = function(params)
    local pump = LUASQUARE_PUMP.GetPump(params.name)
    return pump and pump.speedLevel
end
CONTROL.Actions['rbmk.pump_enabled'].getValue = function(params)
    local pump = LUASQUARE_PUMP.GetPump(params.name)
    return pump and pump.enabled
end


register('hotwell_target', 'TARGET %', {}, function(_, _, _, value) return LUASQUARE_PUMP.SetRegulationTarget('hotwell_makeup_pump', value) end)
register('rod_target', 'WITHDRAWAL %', {}, function(_, _, _, value)
    if LUASQUARE_ROD_SELECTOR.GetSelectionCount() == 0 then return false, 'no rods selected' end
    LUASQUARE_ROD_SELECTOR.Apply(value)
    return true
end)
register('apr_target', 'TARGET MW', {}, function(_, _, _, value)
    RBMK.SetAutoRegulatorTargetMW(value)
    RBMK.SetAutoRegulatorEnabled(value > 0)
    return true
end)

for _, id in ipairs({'feedwater_target', 'hotwell_target', 'apr_target'}) do
    local action = CONTROL.Actions['rbmk.' .. id]
    action.initialize = action.callback
end
