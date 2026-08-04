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

local function shallowCopy(source)
    local out = {}
    for key, value in pairs(source or {}) do
        out[key] = value
    end
    return out
end

local function mergeInto(target, source)
    for key, value in pairs(source or {}) do
        target[key] = value
    end
    return target
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

function DFR.RegisterTelemetryDisplay(name, data, getter)
    if not LUASQUARE_3D2D or not LUASQUARE_3D2D.RegisterDisplay or not LUASQUARE_3D2D.BindDisplay then
        DFR.Log('Telemetry display rejected, LUASQUARE_3D2D is not loaded: ' .. tostring(name))
        return false
    end

    data = data or {}
    local displayData = shallowCopy(data)
    displayData.target = data.target or data.targetName or data.entity or data.infoTarget
    displayData.posTarget = data.posTarget
    displayData.angleTarget = data.angleTarget
    displayData.useTargetAngle = data.useTargetAngle ~= false
    displayData.scale = data.scale or data.pixelScale or 0.1
    displayData.title = data.title or name
    displayData.padding = data.padding or 6
    displayData.lineHeight = data.lineHeight or 14
    displayData.titleHeight = data.titleHeight or 22
    displayData.drawBackground = data.drawBackground ~= false
    displayData.drawBorder = data.drawBorder ~= false

    LUASQUARE_3D2D.RegisterDisplay(name, displayData)

    LUASQUARE_3D2D.BindDisplay(name, getter)
    return true
end

local function displayTargetFromBinding(bindingId, fallback)
    local binding = DFR.GetBinding and DFR.GetBinding(bindingId) or nil
    return (binding and binding.targetName) or fallback
end

local function targetUsesAutoDimensions(targetName)
    return targetName and string.match(tostring(targetName), '^DISPLAY[%d%.]+[xX][%d%.]+_') ~= nil
end

local function withFallbackSize(data, width, height)
    if targetUsesAutoDimensions(data.target or data.targetName or data.entity or data.infoTarget) then return data end
    if data.width == nil then data.width = width end
    if data.height == nil then data.height = height end
    return data
end

local function displayDataFromBinding(bindingId, fallbackTarget, fallbackTitle, overrides)
    local binding = DFR.GetBinding and DFR.GetBinding(bindingId) or nil
    local data = {}

    if binding and type(binding.display) == 'table' then
        mergeInto(data, binding.display)
    elseif binding and binding.metadata and type(binding.metadata.display) == 'table' then
        mergeInto(data, binding.metadata.display)
    end

    if not data.target and not data.targetName and not data.entity and not data.infoTarget then
        data.target = (binding and binding.targetName) or fallbackTarget
    end

    data.title = data.title or fallbackTitle
    mergeInto(data, overrides)

    if not data.target and not data.targetName and not data.entity and not data.infoTarget then
        data.target = (binding and binding.targetName) or fallbackTarget
    end

    data.title = data.title or fallbackTitle
    return data
end

function DFR.RegisterDefaultTelemetryDisplays(options)
    if not LUASQUARE_3D2D then
        DFR.Log('Default telemetry displays skipped, LUASQUARE_3D2D is not loaded')
        return false
    end

    options = options or {}

    local coreData = displayDataFromBinding(
        'core_status_panel',
        displayTargetFromBinding('core_status_panel', 'tar_dfr_status_panel'),
        'DFR CORE STATUS',
        options.core
    )
    DFR.RegisterTelemetryDisplay('dfr_core_status_panel', withFallbackSize(coreData, 42, 26), DFR.TelemetryCoreLines)

    local startupData = displayDataFromBinding(
        'startup_status_panel',
        displayTargetFromBinding('startup_status_panel', 'tar_dfr_startup_panel'),
        'DFR MANUAL STARTUP',
        options.startup
    )
    DFR.RegisterTelemetryDisplay('dfr_startup_status_panel', withFallbackSize(startupData, 42, 30), DFR.TelemetryStartupLines)

    DFR.Log('Default telemetry displays registered')
    return true
end
