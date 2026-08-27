DFR = DFR or {}
DFR.Telemetry = DFR.Telemetry or {}

local function clamp01(value)
    value = tonumber(value) or 0
    if math.Clamp then return math.Clamp(value, 0, 1) end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end

local function boolText(value)
    return value and 'YES' or 'NO'
end

local function onlineText(value)
    return value and 'ONLINE' or 'OFFLINE'
end

local function pctFraction(value)
    return clamp01((tonumber(value) or 0) / 100)
end

function DFR.TelemetryCoreLines()
    local resources = DFR.Resources or {}
    local validation = DFR.LastBindingValidation or {}
    local state = DFR.GetState and DFR.GetState() or 'UNKNOWN'
    local requiredFuel = DFR.Config.StartupRequiredFuelReceptacles or 3
    local fuelReady = DFR.RefreshFuelReadiness and DFR.RefreshFuelReadiness() or false

    return {
        { type = 'value', label = 'STATE', value = state },
        { type = 'value', label = 'RUNNING', value = boolText(DFR.Running and not DFR.Halted) },
        { type = 'value', label = 'HALTED', value = boolText(DFR.Halted) },
        { type = 'value', label = 'FUEL READY', value = boolText(fuelReady), warn = not fuelReady },
        { type = 'value', label = 'MATTER', value = resources.matterReservePercent or 0, decimals = 1, unit = '%' },
        { type = 'bar', fraction = pctFraction(resources.matterReservePercent), height = 5 },
        { type = 'value', label = 'ANTIMATTER', value = resources.antimatterReservePercent or 0, decimals = 1, unit = '%' },
        { type = 'bar', fraction = pctFraction(resources.antimatterReservePercent), height = 5 },
        { type = 'value', label = 'RECEPTACLES', value = tostring(resources.fuelReceptacleCount or 0) .. '/' .. tostring(requiredFuel) },
        { type = 'value', label = 'DECAOS', value = onlineText(resources.decaosOnline) },
        { type = 'value', label = 'INTEGRITY', value = resources.superstructureIntegrityPercent or 0, decimals = 1, unit = '%' },
        { type = 'bar', fraction = pctFraction(resources.superstructureIntegrityPercent), height = 5, warn = (resources.superstructureIntegrityPercent or 100) < 75 },
        { type = 'value', label = 'OUTPUT', value = resources.reactorOutputGW or 0, decimals = 2, unit = 'GW' },
        { type = 'value', label = 'BINDINGS', value = tostring(validation.missingRequired or 0) .. ' CRIT / ' .. tostring(validation.missingOptional or 0) .. ' OPT' }
    }
end

function DFR.TelemetryStartupLines()
    local startup = DFR.GetStartupSnapshot and DFR.GetStartupSnapshot() or {}
    local containmentLimit = DFR.Config.ContainmentFieldStartupLimitPercent or 35

    return {
        { type = 'value', label = 'STATE', value = DFR.GetState and DFR.GetState() or 'UNKNOWN' },
        { type = 'value', label = 'STABILIZER', value = onlineText(startup.stabilizerActive) },
        { type = 'value', label = 'STAB LOAD', value = startup.stabilizerPowerGW or 0, decimals = 2, unit = 'GW' },
        { type = 'value', label = 'FIELD CMD', value = startup.containmentFieldStrengthPercent or 0, decimals = 1, unit = '%' },
        { type = 'bar', fraction = clamp01((startup.containmentFieldStrengthPercent or 0) / containmentLimit), height = 5 },
        { type = 'value', label = 'FIELD STABLE', value = startup.containmentFieldStabilityPercent or 0, decimals = 1, unit = '%' },
        { type = 'bar', fraction = pctFraction(startup.containmentFieldStabilityPercent), height = 5 },
        { type = 'value', label = 'DIR BEAM', value = onlineText(startup.directorBeamActive) },
        { type = 'value', label = 'PRECISION', value = startup.directorBeamPrecisionPercent or 0, decimals = 1, unit = '%' },
        { type = 'bar', fraction = pctFraction(startup.directorBeamPrecisionPercent), height = 5, warn = (startup.directorBeamPrecisionPercent or 0) < 95 },
        { type = 'value', label = 'IMPRECISION', value = startup.directorBeamImprecisionPercent or 100, decimals = 2, unit = '%' },
        { type = 'value', label = 'LENS X', value = startup.lensXOffset or 0, decimals = 3 },
        { type = 'value', label = 'LENS Y', value = startup.lensYOffset or 0, decimals = 3 },
        { type = 'value', label = 'LENS Z', value = startup.lensZOffset or 0, decimals = 3 }
    }
end

local function coreVisualSnapshot()
    local out = {}
    for id, label in pairs({
        core_sphere = 'CORE SPHERE',
        core_stellar = 'STELLAR SHELL',
        core_blackhole = 'EVENT HORIZON',
        core_shield = 'CORE SHIELD'
    }) do
        local measurement = DFR.GetCoreVisualMeasurement and DFR.GetCoreVisualMeasurement(id) or {}
        local visual = DFR.CoreVisual and DFR.CoreVisual[id] or {}
        out[id] = {
            label = label,
            radius = measurement.targetRadiusMeters or measurement.radiusMeters or 0,
            scaleX = measurement.axisScales and measurement.axisScales.x or 0,
            scaleY = measurement.axisScales and measurement.axisScales.y or 0,
            scaleZ = measurement.axisScales and measurement.axisScales.z or 0,
            visible = visual.drawEnabled ~= false,
            wobble = visual.wobble and visual.wobble.enabled or false,
            pulse = visual.pulse ~= nil
        }
    end
    return out
end

local function facilityProvider()
    local resources = DFR.Resources or {}
    local validation = DFR.LastBindingValidation or {}
    local requiredFuel = DFR.Config.StartupRequiredFuelReceptacles or 3
    local fuelReady = DFR.RefreshFuelReadiness and DFR.RefreshFuelReadiness() or false
    return {
        state = DFR.GetState and DFR.GetState() or 'UNKNOWN',
        running = DFR.Running and not DFR.Halted and true or false,
        halted = DFR.Halted and true or false,
        fuelReady = fuelReady,
        matter = resources.matterReservePercent or 0,
        matterFraction = pctFraction(resources.matterReservePercent),
        antimatter = resources.antimatterReservePercent or 0,
        antimatterFraction = pctFraction(resources.antimatterReservePercent),
        receptacles = tostring(resources.fuelReceptacleCount or 0) .. '/' .. tostring(requiredFuel),
        decaos = onlineText(resources.decaosOnline),
        integrity = resources.superstructureIntegrityPercent or 0,
        integrityFraction = pctFraction(resources.superstructureIntegrityPercent),
        integrityWarn = (resources.superstructureIntegrityPercent or 100) < 75,
        outputGW = resources.reactorOutputGW or 0,
        bindingStatus = tostring(validation.missingRequired or 0) .. ' CRIT / '
            .. tostring(validation.missingOptional or 0) .. ' OPT'
    }
end

local function startupProvider()
    local startup = DFR.GetStartupSnapshot and DFR.GetStartupSnapshot() or {}
    local containmentLimit = DFR.Config.ContainmentFieldStartupLimitPercent or 35
    local procedure = DFR.GetPreAnnihilationSnapshot and DFR.GetPreAnnihilationSnapshot() or {}
    local activeRun
    for _, run in pairs(procedure.runs or {}) do activeRun = run break end
    return {
        state = DFR.GetState and DFR.GetState() or 'UNKNOWN',
        stabilizer = onlineText(startup.stabilizerActive),
        stabilizerActive = startup.stabilizerActive and true or false,
        stabilizerPowerGW = startup.stabilizerPowerGW or 0,
        containment = startup.containmentFieldStrengthPercent or 0,
        containmentFraction = clamp01((startup.containmentFieldStrengthPercent or 0) / containmentLimit),
        stability = startup.containmentFieldStabilityPercent or 0,
        stabilityFraction = pctFraction(startup.containmentFieldStabilityPercent),
        director = onlineText(startup.directorBeamActive),
        directorActive = startup.directorBeamActive and true or false,
        precision = startup.directorBeamPrecisionPercent or 0,
        precisionFraction = pctFraction(startup.directorBeamPrecisionPercent),
        precisionWarn = (startup.directorBeamPrecisionPercent or 0) < 95,
        imprecision = startup.directorBeamImprecisionPercent or 100,
        lensX = startup.lensXOffset or 0,
        lensY = startup.lensYOffset or 0,
        lensZ = startup.lensZOffset or 0,
        procedure = activeRun and (activeRun.status or activeRun.timelineName) or 'IDLE'
    }
end

local function catalyzerColumn(unit)
    if not unit then return {label = 'CATALYZER', value = 'MISSING', sub = '0/32 GROUPS'} end
    local found = 32 - #(unit.missing or {})
    return {
        label = 'CATALYZER ' .. tostring(unit.id),
        value = unit.available and tostring(unit.mode or 'OFFLINE') or 'MISSING',
        sub = string.format('%d/32 GROUPS · %d ENT', found, unit.entityCount or 0),
        valueColor = unit.available and Color(110, 255, 150) or Color(255, 95, 95)
    }
end

local function catalyzerProvider()
    local snapshot = DFR.GetCatalyzerSnapshot and DFR.GetCatalyzerSnapshot() or {}
    return {
        row1 = {catalyzerColumn(snapshot[1]), catalyzerColumn(snapshot[2]), catalyzerColumn(snapshot[3])},
        row2 = {catalyzerColumn(snapshot[4]), catalyzerColumn(snapshot[5]), catalyzerColumn(snapshot[6])},
        available = (function()
            local count = 0
            for _, unit in pairs(snapshot) do if unit.available then count = count + 1 end end
            return count
        end)()
    }
end

function DFR.RegisterDefaultTelemetryDisplays(options)
    if not LUASQUARE_3D2D or not LUASQUARE_3D2D.RegisterDataProvider then
        DFR.Log('Default telemetry displays skipped, LUASQUARE_3D2D is not loaded')
        return false
    end
    options = options or {}
    local interval = tonumber(options.interval) or 0.2
    LUASQUARE_3D2D.RegisterDataProvider('dfr.facility', facilityProvider, {
        interval = interval,
        label = 'DFR Facility',
        fields = {
            {path = 'state', type = 'string', label = 'Reactor state'},
            {path = 'running', type = 'boolean', label = 'Runtime active'},
            {path = 'halted', type = 'boolean', label = 'Runtime halted'},
            {path = 'fuelReady', type = 'boolean', label = 'Fuel ready'},
            {path = 'matter', type = 'number', label = 'Matter reserve'},
            {path = 'antimatter', type = 'number', label = 'Antimatter reserve'},
            {path = 'integrity', type = 'number', label = 'Superstructure integrity'},
            {path = 'outputGW', type = 'number', label = 'Output (GW)'}
        }
    })
    LUASQUARE_3D2D.RegisterDataProvider('dfr.core_visuals', coreVisualSnapshot, {interval = interval})
    LUASQUARE_3D2D.RegisterDataProvider('dfr.startup', startupProvider, {
        interval = interval,
        label = 'DFR Startup',
        fields = {
            {path = 'stabilizerActive', type = 'boolean', label = 'Stabilizer active'},
            {path = 'stabilizerPowerGW', type = 'number', label = 'Stabilizer power (GW)'},
            {path = 'containment', type = 'number', label = 'Containment command'},
            {path = 'stability', type = 'number', label = 'Field stability'},
            {path = 'directorActive', type = 'boolean', label = 'Director active'},
            {path = 'precision', type = 'number', label = 'Director precision'},
            {path = 'procedure', type = 'string', label = 'Procedure status'}
        }
    })
    LUASQUARE_3D2D.RegisterDataProvider('dfr.catalyzers', catalyzerProvider, {
        interval = tonumber(options.catalyzerInterval) or 1
    })

    LUASQUARE_3D2D.RegisterAction('dfr.pre_annihilation_begin', {
        label = 'Begin pre-annihilation',
        cooldown = 1,
        callback = function(actor) return DFR.StartPreAnnihilation(actor) end
    })
    LUASQUARE_3D2D.RegisterAction('dfr.pre_annihilation_cancel', {
        label = 'Cancel pre-annihilation',
        cooldown = 0.5,
        callback = function() return DFR.CancelPreAnnihilation('3D2D operator action') end
    })
    LUASQUARE_3D2D.RegisterAction('dfr.core_pulse', {
        label = 'Pulse core presentation',
        cooldown = 0.5,
        callback = function()
            local sphere = DFR.PulseCoreVisual and DFR.PulseCoreVisual('core_sphere')
            local shield = DFR.PulseCoreVisual and DFR.PulseCoreVisual('core_shield')
            return sphere or shield
        end
    })

    DFR.Log('Default telemetry providers and display actions registered')
    return true
end
