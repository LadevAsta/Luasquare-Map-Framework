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
    local startup = DFR.Startup or {}
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

function DFR.RegisterTelemetryDisplay(name, data, getter)
    if not LUASQUARE_3D2D or not LUASQUARE_3D2D.RegisterDisplay or not LUASQUARE_3D2D.BindDisplay then
        DFR.Log('Telemetry display rejected, LUASQUARE_3D2D is not loaded: ' .. tostring(name))
        return false
    end

    data = data or {}
    LUASQUARE_3D2D.RegisterDisplay(name, {
        target = data.target or data.entity or data.infoTarget,
        posTarget = data.posTarget,
        angleTarget = data.angleTarget,
        useTargetAngle = data.useTargetAngle ~= false,
        width = data.width,
        height = data.height,
        scale = data.scale or 0.1,
        title = data.title or name,
        padding = data.padding or 6,
        lineHeight = data.lineHeight or 14,
        titleHeight = data.titleHeight or 22,
        drawBackground = data.drawBackground ~= false,
        drawBorder = data.drawBorder ~= false,
        backgroundColor = data.backgroundColor,
        borderColor = data.borderColor,
        textColor = data.textColor,
        titleColor = data.titleColor
    })

    LUASQUARE_3D2D.BindDisplay(name, getter)
    return true
end

function DFR.RegisterDefaultTelemetryDisplays()
    if not LUASQUARE_3D2D then
        DFR.Log('Default telemetry displays skipped, LUASQUARE_3D2D is not loaded')
        return false
    end

    DFR.RegisterTelemetryDisplay('dfr_core_status_panel', {
        target = 'tar_dfr_status_panel',
        title = 'DFR CORE STATUS',
        width = 42,
        height = 26
    }, DFR.TelemetryCoreLines)

    DFR.RegisterTelemetryDisplay('dfr_startup_status_panel', {
        target = 'tar_dfr_startup_panel',
        title = 'DFR MANUAL STARTUP',
        width = 42,
        height = 30
    }, DFR.TelemetryStartupLines)

    DFR.Log('Default telemetry displays registered')
    return true
end
