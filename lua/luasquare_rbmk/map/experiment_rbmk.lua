-- =========================================
-- MAP DEFINITION AND BOOTSTRAP
-- =========================================

-- This is orchestration script to set up map integration.
-- Deploy THIS SCRIPT using a lua_run in the map :
-- include('luasquare_rbmk/map/experiment_rbmk.lua')

local MAPNAME = 'experiment_rbmk'

-- =========================================
-- PRE-FLIGHT CHECKS
-- =========================================

-- Luasquare script's presence (This file)
-- As of now, Luasquare modules are impervious to 'Clean Up Everything'. Reload is the only option.
if LUASQUARE_FRAMEWORK_INITIALIZED then
    print('[LUASQUARE FRAMEWORK] BOOTSTRAP FAILED!\n[LUASQUARE FRAMEWORK] It already happened once in this session. Reload map.')
return end

-- Addon Dependencies
-- NYI.
-- Detect if the player (or server) has Luasquare Modules installed. if not, fire a map relay 'relay_NO_LUASQUARE' if mapper made a relay for it.
-- That relay intended to auto-configure the map into 'static' idle state where no Luasquare functions and simulations take place.

-- =========================================
-- CORE MODULES
-- =========================================

include('luasquare_module/seg7display.lua') -- Pseudo 7-Segments numeric display
include('luasquare_module/3d2display.lua') -- 3D2D Display
include('luasquare_module/annunciator/annunciator.lua') -- Alarm annunciator system
include('luasquare_module/gaugedisplay.lua') -- Gauge display
include('luasquare_module/keypad_controller.lua') -- Numeric Keypads
include('luasquare_module/rod_selector.lua') -- RBMK Control Rod Selector
include('luasquare_powerplant/init.lua') -- Balance of plant systems
include('luasquare_rbmk/init.lua') -- RBMK Core

-- =========================================
-- WORLD SETTINGS
-- =========================================

--Reactor position in the map. (TOP LEFT CORNER) Exactly where the [1,1] Column will be.
--See Hammer++'s Global axis gizmo. red and green arrows indicates columns extend direction.
RBMK.WorldOrigin = Vector(352, -672, 448)
RBMK.CellSpacing = 64

RBMK.TickInterval = 0.1
LUASQUARE_SEG7.TickInterval = 0.1
LUASQUARE_GAUGE.TickInterval = 0.2
LUASQUARE_3D2D.TickInterval = 0.2
LUASQUARE_ANNUNCIATOR.TickInterval = 0.5
LUASQUARE_FLUID.TickInterval = 0.1
LUASQUARE_VALVE.TickInterval = 0.1
LUASQUARE_PUMP.TickInterval = 0.1
LUASQUARE_TURBINE.TickInterval = 0.1
LUASQUARE_COOLINGTOWER.TickInterval = 0.1
LUASQUARE_POWERGRID.TickInterval = 0.1
LUASQUARE_POWERGENERATOR.TickInterval = 0.1
LUASQUARE_DIESELGENERATOR.TickInterval = 0.1

-- =========================================
-- REACTOR SETTINGS
-- =========================================

--Heat Diffusion FACTOR of Reactor Vessel. Diff is multiplied by this value 
--(Should NOT be 0 or higher than 1 Default : 0.05)
RBMK.RPVHeatDiffusion = 0.05

-- Set the form factor of each column (in inches/hammer unit, width, length, height, HollowPercentage).
RBMK.CalculateColumnVolume(64, 64, 256, 10)
-- Keep some vessel headspace so high water level naturally raises pressure.
RBMK.RPVMinSteamSpaceFraction = 0.05
RBMK.SteamExpansionRatio = 1600
RBMK.SteamPressureFactor = 1
RBMK.WaterBoilingPressureFactor = 2.6
RBMK.CoolingOptimalWaterFraction = 0.8
RBMK.CoolingLowWaterFraction = 0.1
RBMK.CoolingLowEfficiency = 0.08
RBMK.CoolingDryEfficiency = 0.02
RBMK.RPVMaxPressure = 70
RBMK.RPVHardPressure = 150
RBMK.BlowoutPressure = 85
RBMK.CatastrophicPressure = 140
-- Allow LRBMK to perform steam blowout when overpressured, it will cause column to jump and remove steam, canonically pollutes.
-- Disable for more historically-accurate RBMK whose rod does not jump(nor blowout).
RBMK.BlowoutEnabled = true
-- Global cadence for blowout events, then per-column recovery after its jump finishes.
RBMK.BlowoutCooldown = 0.05
RBMK.BlowoutColumnCooldown = 1.0
-- Each blowout pass randomly jump columns within this range, biased higher at higher overpressure.
RBMK.BlowoutMinColumnsPerPass = 1
RBMK.BlowoutMaxColumnsPerPass = 4
-- Name prefix of func_movelinear to be used as 'jumping rods' In Hammer it MUST be named [name]_0, [name]_1 etc.
-- Example : 'rbmk_blowout' is set here, In Hammer it must strictly be 'rbmk_blowout_0', 'rbmk_blowout_1', ...
RBMK.BlowoutValvePrefix = 'brush_rpv'
-- The amount of blowout valves there is, make sure to set this equal to the amount of func_movelinears you want to use.
RBMK.BlowoutFallbackValveCount = 89
-- How much steam is removed from the vessel for each jump. Set it weak to make it serve only dramatic purposes.
RBMK.BlowoutSteamLoss = 0.5
-- Register blowout func_movelinears
RBMK.ClearBlowoutValves()
RBMK.RegisterBlowoutValveRange(RBMK.BlowoutValvePrefix, RBMK.BlowoutFallbackValveCount)

RBMK.FuelLeakTemperature = 1500
RBMK.FuelMeltdownTemperature = 3000
RBMK.SteamOutletFlowRate = 1.2
RBMK.SteamOutletRatedPressureDelta = 5
RBMK.SteamOutletOpen = true
RBMK.FeedwaterInletOpen = true
RBMK.DrainValveOpen = false
RBMK.DrainFlowRate = 500

-- Automatic Regulator Rods. These are short control rods inserted from the bottom of Manual Control rod.
RBMK.AutoRegulatorEnabled = false
RBMK.AutoRegulatorUsePID = true
RBMK.AutoRegulatorTargetMW = 0
-- The length of auto regulator (0.0 - 1.0)
RBMK.AutoRegulatorMaxInsertion = 0.1
-- PID
RBMK.AutoRegulatorKp = 0.0002
RBMK.AutoRegulatorKi = 0.00001
RBMK.AutoRegulatorKd = 0.00005

RBMK.CatastrophicFailureRelay = 'explodetest'
RBMK.FuelLeakRelay = nil
RBMK.FuelMeltdownRelay = nil


--Amount of column jumps flux can go through, reflectors does not reset the count.
RBMK.FluxRange = 12
--Subtract reported total neutron flux with this value. Usually the constant output of all Neutron Source Columns that cannot be closed times 4.
RBMK.TotalFluxSubtractDefine = 26 * 0 -- The source can close via button.

--Control rod movespeed multiplier boost on SCRAM
RBMK.ControlrodScramBoost = 2
--Control rod func_movelinear's move distance you set in Hammer (inches)
RBMK.RodMoveDistance = 64


-- =========================================
-- REACTOR CONSTRUCTION
-- =========================================

-- Layout orchestrator
include('luasquare_rbmk/layouts/LRBMKP-400.lua')

--Starting Water inside the reactor pressure vessel (in PERCENTAGE)
RBMK.AddInitialWater(85)

-- =========================================
-- THERMAL PLANT SYSTEMS
-- =========================================

local MAPDEF_monitorZoffset = 128
local MAPDEF_feedwaterTargetPercent = 80
local MAPDEF_hotwellTargetPercent = 35
-- Debug monitor positions can be Vector(...) or monitorTarget = 'named_info_target'.

-- Power Grid

LUASQUARE_POWERGRID.RegisterGrid('offsite_grid', {
    type = 'offsite',
    nominalFrequency = 60,
    voltage = 230000,
    sourceCapacityMW = 1000,
    stiff = true,
    enabled = true,
    monitorPos = 'tar_grid_offsite'
})

LUASQUARE_POWERGRID.RegisterGrid('station_grid', {
    type = 'onsite',
    nominalFrequency = 60,
    voltage = 13800,
    sourceCapacityMW = 0,
    enabled = true,
    inertia = 6,
    droopHz = 1.5,
    tripRelay = 'grid_station_trip_relay',
    resetRelay = 'grid_station_reset_relay',
    monitorPos = 'tar_grid_station'
})

LUASQUARE_POWERGRID.RegisterTransformer('offsite_station_transformer', {
    from = 'offsite_grid',
    to = 'station_grid',
    maxMW = 40,
    closed = true,
    enabled = true,
    bidirectional = false,
    monitorPos = 'tar_transformer_offsite_station'
})

LUASQUARE_POWERGRID.RegisterTransformer('offsite_export_transformer', {
    from = 'station_grid',
    to = 'offsite_grid',
    maxMW = 160,
    closed = false,
    enabled = true,
    bidirectional = false,
    monitorPos = 'tar_transformer_offsite_station',
    monitorOffset = Vector(0,0,64)
})

-- Steam Turbine

LUASQUARE_TURBINE.RegisterTurbine('tg1', {
    input = 'main_steam',
    boiler = 'rbmk',
    cycleEfficiency = 0.32,
    condenserOutput = 'hotwell',
    bypassCondenserOutput = 'hotwell',
    condenserOutputTemperature = 80,
    bypassCondenserOutputTemperature = 95,
    maxSteamRate = 500000,
    ratedSteamRate = 300000,
    bypassMaxSteamRate = 500000,
    ratedInletPressure = 10,
    valve = 0,
    bypassValve = 0,
    enabled = true,
    soundEntity = 'tg1_turbine_sound',
    soundEntity2 = 'tg1_turbine_sound2',
    soundMinVolume = 4,
    soundMaxVolume = 10,
    soundMinPitch = 80,
    soundMaxPitch = 140,
    shakeEntity = 'tg1_turbine_shake',
    shakeMaxAmplitude = 16,
    shakeMaxFrequency = 255,
    tripVibration = 50,
    tripRelay = 'tg1_trip_relay',
    severeTripRelay = 'tg1_severe_trip_relay',
    severeTripStopRelay = 'tg1_severe_trip_stop_relay',
    extremeTripRelay = 'tg1_extreme_trip_relay',
    repairRelay = 'tg1_repair_relay',
    monitorPos = 'tar_turbine_a'
})

LUASQUARE_POWERGENERATOR.RegisterTurbineGenerator('tg1_generator', {
    turbine = 'tg1',
    grid = 'station_grid',
    breaker = 'tg1_generator_breaker',
    ratedMW = 160,
    maxMW = 480,
    gridRPM = 1800,
    autoSync = false,
    syncRPMTolerance = 8,
    syncPhaseTolerance = 8,
    syncFailureTrips = true,
    gridLossTrips = true,
    enabled = true,
    syncRelay = 'tg1_sync_relay',
    unsyncRelay = 'tg1_unsync_relay',
    monitorPos = 'tar_turbine_generator_a',
    breakerMonitorPos = 'tar_turbine_generator_a_breaker'
})

LUASQUARE_DIESELGENERATOR.RegisterDieselGenerator('edg1', {
    generator = 'edg1_generator',
    fuelNetwork = 'diesel_fuel',
    grid = 'station_grid',
    breaker = 'edg1_generator_breaker',
    ratedMW = 12,
    maxMW = 16,
    targetMW = 12,
    rampRateMW = 4,
    fuelTankCapacity = 200,
    fuelTankAmount = 25,
    refuelRate = 4,
    fuelConsumptionPerMWSecond = 0.02,
    idleFuelRate = 0.02,
    enabled = true,
    autoStart = true,
    breakerClosed = true,
    monitorPos = 'tar_diesel_generator_a',
    generatorMonitorOffset = Vector(0,0,-32),
    breakerMonitorOffset = Vector(0,0,-64)
})

-- Cooling Tower

LUASQUARE_COOLINGTOWER.RegisterCoolingTower('main_cooling_tower', {
    output = 'feedwater',
    basinMaxAmount = RBMK.MaxWater,
    basinMaxPressure = 20,
    basinTemperature = 40,
    maxRate = 1000,
    enabled = true,
    outputTemperature = 20,
    startRelay = 'cooling_tower_on',
    stopRelay = 'cooling_tower_off',
    monitorPos = 'tar_coolingtower_a'
})

-- Fluid Network

LUASQUARE_FLUID.RegisterNetwork('main_steam', {
    type = LUASQUARE_FLUID.TYPE_STEAMLINE,
    fluidType = 'steam',
    amount = 0,
    volume = RBMK.SteamSpace / 2,
    maxAmount = RBMK.MaxSteam / 2,
    hardMaxAmount = RBMK.HardMaxSteam / 2,
    maxPressure = 150,
    temperature = 100,
    thermalLossRate = 0.002,
    monitorPos = RBMK.WorldOrigin + Vector(0, 0, 96 + MAPDEF_monitorZoffset)
})
RBMK.SetSteamNetwork('main_steam')

LUASQUARE_FLUID.RegisterNetwork('feedwater', {
    type = LUASQUARE_FLUID.TYPE_STEAMLINE,
    fluidType = 'water',
    amount = 100000,
    maxAmount = RBMK.MaxWater,
    hardMaxAmount = RBMK.MaxWater,
    maxPressure = 150,
    temperature = 40,
    thermalLossRate = 0.005,
    serviceRate = 0,
    monitorPos = RBMK.WorldOrigin + Vector(0, 96, 96 + MAPDEF_monitorZoffset)
})

LUASQUARE_FLUID.RegisterNetwork('hotwell', {
    type = LUASQUARE_FLUID.TYPE_STEAMLINE,
    fluidType = 'water',
    amount = 20000,
    maxAmount = RBMK.MaxWater,
    hardMaxAmount = RBMK.MaxWater,
    maxPressure = 20,
    temperature = 80,
    thermalLossRate = 0.001,
    serviceRate = 0,
    monitorPos = 'tar_hotwell'
})

LUASQUARE_FLUID.RegisterNetwork('drain_tank', {
    type = LUASQUARE_FLUID.TYPE_STEAMLINE,
    fluidType = 'water',
    amount = 0,
    maxAmount = RBMK.MaxWater,
    hardMaxAmount = RBMK.MaxWater,
    maxPressure = 5,
    temperature = 40,
    thermalLossRate = 0.01,
    serviceRate = 0,
    monitorPos = RBMK.WorldOrigin + Vector(0, 96, 128 + MAPDEF_monitorZoffset)
})
RBMK.SetDrainNetwork('drain_tank')

LUASQUARE_FLUID.RegisterNetwork('diesel_fuel', {
    type = LUASQUARE_FLUID.TYPE_SIMPLE,
    fluidType = 'diesel',
    amount = 500,
    maxAmount = 1000,
    serviceRate = 0,
    monitorPos = 'tar_diesel_fuel'
})

-- Fluid Valve

LUASQUARE_VALVE.RegisterValve('rpv_drain_valve', {
    a = 'rbmk_water',
    b = 'drain_tank',
    maxFlow = 500,
    minFlowFraction = 0.2,
    open = false,
    bidirectional = false,
    monitorPos = RBMK.WorldOrigin + Vector(0, 384, 96 + MAPDEF_monitorZoffset)
})

LUASQUARE_VALVE.RegisterValve('hotwell_drain_valve', {
    a = 'hotwell',
    b = 'void',
    maxFlow = 500,
    open = false,
    bidirectional = false,
    monitorPos = 'tar_hotwell_drain'
})

-- Pumps

LUASQUARE_PUMP.RegisterPump('feedwater_pump_a', {
    source = 'feedwater',
    target = 'rbmk',
    rate = 500,
    headPressure = 120,
    minFlowFraction = 0.25,
    regulate = true,
    regulationMode = 'fill',
    regulationSensor = 'rbmk_water_percent',
    regulationTarget = MAPDEF_feedwaterTargetPercent,
    regulationDeadband = 0.5,
    regulationGain = 0.3,
    regulationMinOutput = 0.1,
    speedLevels = {0, 0.25, 0.5, 1},
    speedLevel = 3,
    enabled = true,
    grid = 'station_grid',
    peakMW = 30,
    breaker = 'feedwater_pump_a_breaker',
    breakerClosed = true,
    monitorPos = RBMK.WorldOrigin + Vector(0, 192, 96 + MAPDEF_monitorZoffset),
    breakerMonitorPos = RBMK.WorldOrigin + Vector(0, 256, 96 + MAPDEF_monitorZoffset)
})

LUASQUARE_PUMP.RegisterPump('feedwater_pump_b', {
    source = 'feedwater',
    target = 'rbmk',
    rate = 500,
    headPressure = 120,
    minFlowFraction = 0.25,
    regulate = true,
    regulationMode = 'fill',
    regulationSensor = 'rbmk_water_percent',
    regulationTarget = MAPDEF_feedwaterTargetPercent,
    regulationDeadband = 0.5,
    regulationGain = 0.3,
    regulationMinOutput = 0.1,
    speedLevels = {0, 0.25, 0.5, 1},
    speedLevel = 1,
    enabled = false,
    grid = 'station_grid',
    peakMW = 30,
    breaker = 'feedwater_pump_b_breaker',
    breakerClosed = true,
    monitorPos = RBMK.WorldOrigin + Vector(0, 192, 128 + MAPDEF_monitorZoffset),
    breakerMonitorPos = RBMK.WorldOrigin + Vector(0, 256, 128 + MAPDEF_monitorZoffset)
})

LUASQUARE_PUMP.RegisterPump('condensate_pump_a1', {
    source = 'hotwell',
    target = 'main_cooling_tower',
    rate = 1000,
    headPressure = 150,
    regulate = true,
    regulationMode = 'drain',
    regulationSensor = 'hotwell',
    regulationTarget = MAPDEF_hotwellTargetPercent,
    regulationDeadband = 1,
    regulationGain = 0.08,
    regulationMinOutput = 0.1,
    speedLevels = {0, 0.25, 0.5, 1},
    speedLevel = 4,
    enabled = true,
    grid = 'station_grid',
    peakMW = 30,
    breaker = 'condensate_pump_a1_breaker',
    breakerClosed = true,
    monitorPos = 'tar_condpump_a1',
    breakerMonitorPos = 'tar_condpump_a1_breaker'
})

-- =========================================
-- SEG7 DISPLAYS
-- =========================================

LUASQUARE_SEG7.RegisterDisplay('reactor_mwth', {
    'reactor_mwth_0',
    'reactor_mwth_1',
    'reactor_mwth_2',
    'reactor_mwth_3',
    'reactor_mwth_4'
})
LUASQUARE_SEG7.BindDisplay('reactor_mwth', function()
    return math.floor(RBMK.LastThermalMW + RBMK.LastFlashBoilMW)
end)

LUASQUARE_SEG7.RegisterDisplay('f1_coretemp', {
    'f1_coretemp_0',
    'f1_coretemp_1',
    'f1_coretemp_2',
    'f1_coretemp_3',
    'f1_coretemp_4'
})
LUASQUARE_SEG7.BindDisplay('f1_coretemp', function()
    return math.floor(RBMK.GetCoreHeat(5, 5))
end)

LUASQUARE_SEG7.RegisterDisplay('f1_skintemp', {
    'f1_skintemp_0',
    'f1_skintemp_1',
    'f1_skintemp_2',
    'f1_skintemp_3'
})
LUASQUARE_SEG7.BindDisplay('f1_skintemp', function()
    return math.floor(RBMK.GetSkinHeat(5, 5))
end)

LUASQUARE_SEG7.RegisterDisplay('f1_coltemp', {
    'f1_coltemp_0',
    'f1_coltemp_1',
    'f1_coltemp_2',
    'f1_coltemp_3'
})
LUASQUARE_SEG7.BindDisplay('f1_coltemp', function()
    return math.floor(RBMK.GetHeat(5, 5))
end)


LUASQUARE_SEG7.RegisterDisplay('totalflux', {
        'flux_0',
        'flux_1',
        'flux_2',
        'flux_3',
        'flux_4'
    }
)
LUASQUARE_SEG7.BindDisplay(
    'totalflux',
    function() return math.floor(RBMK.TotalFluxSubtracted) end
)

LUASQUARE_SEG7.RegisterDisplay('averageXenon', {
        'xenon_0',
        'xenon_1',
        'xenon_2'
    }
)
LUASQUARE_SEG7.BindDisplay(
    'averageXenon',
    function() return math.floor(RBMK.AverageXenon) end
)

LUASQUARE_SEG7.RegisterDisplay('aprinsertion', {
        'aprinsertion_0',
        'aprinsertion_1',
        'aprinsertion_2'
    }
)
LUASQUARE_SEG7.BindDisplay(
    'aprinsertion',
    function() return math.floor((RBMK.AutoRegulatorTargetInsertion / RBMK.AutoRegulatorMaxInsertion) * 100) end
)

-- =========================================
-- GAUGE DISPLAYS
-- =========================================

LUASQUARE_GAUGE.RegisterGauge('gauge_maxtemp', {
    entity = 'gauge_maxtemp',
    min = 0,
    max = 1600,
    speed = 18
})
LUASQUARE_GAUGE.BindGauge('gauge_maxtemp', function()
    if not RBMK or not RBMK.MaxHeat or RBMK.MaxHeat <= 0 then return 0 end
    return RBMK.MaxHeat or 0
end)

LUASQUARE_GAUGE.RegisterGauge('gauge_waterlevel', {
    entity = 'gauge_waterlevel',
    min = 0,
    max = 100,
    speed = 18
})
LUASQUARE_GAUGE.BindGauge('gauge_waterlevel', function()
    if not RBMK or not RBMK.Water or RBMK.Water <= 0 then return 0 end
    return (RBMK.Water / RBMK.MaxWater) * 100 or 0
end)

LUASQUARE_GAUGE.RegisterGauge('gauge_steamlevel', {
    entity = 'gauge_steamlevel',
    min = 0,
    max = 100,
    speed = 18
})
LUASQUARE_GAUGE.BindGauge('gauge_steamlevel', function()
    if not RBMK or not RBMK.Steam or RBMK.Steam <= 0 then return 0 end
    return (RBMK.Steam / RBMK.MaxSteam) * 100 or 0
end)

LUASQUARE_GAUGE.RegisterGauge('gauge_rpvpressure', {
    entity = 'gauge_rpvpressure',
    min = 0,
    max = 100,
    speed = 18
})
LUASQUARE_GAUGE.BindGauge('gauge_rpvpressure', function()
    if not RBMK or not RBMK.RPVPressure or RBMK.RPVPressure <= 0 then return 0 end
    return (RBMK.RPVPressure / RBMK.RPVMaxPressure) * 100 or 0
end)

LUASQUARE_GAUGE.RegisterGauge('gauge_hotwell', {
    entity = 'gauge_hotwell',
    min = 0,
    max = 100,
    speed = 18
})
LUASQUARE_GAUGE.BindGauge('gauge_hotwell', function()
    local network = LUASQUARE_FLUID.GetNetwork('hotwell')
    return (network.amount / network.maxAmount) * 100 or 0
end)

LUASQUARE_GAUGE.RegisterGauge('gauge_hotwell_temp', {
    entity = 'gauge_hotwell_temp',
    min = 0,
    max = 140,
    speed = 18
})
LUASQUARE_GAUGE.BindGauge('gauge_hotwell_temp', function()
    local network = LUASQUARE_FLUID.GetNetwork('hotwell')
    return network.temperature or 0
end)

-- =========================================
-- 3D2D PANEL DISPLAYS FUNCTION
-- =========================================

-- width/height are Hammer units. At scale 0.1, a 44x22 HU panel gets a 440x220 pixel canvas.
local MAPDEF_panelScale = 0.1

local function MAPDEF_panelBase(title, pos, width, height, angle)
    local data
    if type(title) == 'table' then
        data = title
    else
        data = {
            title = title,
            pos = pos,
            width = width,
            height = height,
            ang = angle
        }
    end

    local displayWidth = data.width or 1
    local displayHeight = data.height or 1
    local displayAngle = data.ang or data.angle
    local target = data.target or data.infoTarget
    local posTarget = data.posTarget or data.positionTarget
    local angleTarget = data.angleTarget or data.angTarget
    local useTargetAngle = data.useTargetAngle
    if useTargetAngle == nil then useTargetAngle = data.targetAngle end
    if useTargetAngle == nil and (target or posTarget or (type(data.pos) == 'string' and not displayAngle)) then useTargetAngle = true end

    local compact = displayHeight <= 16
    return {
        target = target,
        posTarget = posTarget,
        angleTarget = angleTarget,
        useTargetAngle = useTargetAngle,
        pos = data.pos,
        ang = displayAngle,
        offset = data.offset,
        angleOffset = data.angleOffset or data.angOffset,
        anchorX = data.anchorX or 0.5,
        anchorY = data.anchorY or 0.5,
        scale = data.scale or MAPDEF_panelScale,
        width = displayWidth,
        height = displayHeight,
        padding = data.padding or (compact and 6 or 10),
        lineHeight = data.lineHeight or (compact and 13 or 18),
        titleHeight = data.titleHeight or (compact and 18 or 28),
        font = data.font or (compact and 'Luasquare3D2D_Small' or nil),
        titleFont = data.titleFont or (compact and 'Luasquare3D2D_Line' or nil),
        title = data.title,
        backgroundColor = data.backgroundColor or Color(3, 10, 12, 235),
        borderColor = data.borderColor or Color(30, 163, 216, 230),
        textColor = data.textColor or Color(205, 235, 240),
        titleColor = data.titleColor or Color(255, 255, 255),
        barColor = data.barColor or Color(80, 220, 160)
    }
end

local function MAPDEF_powerState(enabled)
    if enabled then return 'ON', Color(110, 255, 150) end
    return 'OFF', Color(255, 95, 95)
end

local function MAPDEF_pumpColumn(label, pumpName)
    local pump = LUASQUARE_PUMP.GetPump(pumpName) or {}
    local state, color = MAPDEF_powerState(pump.enabled)
    local speed = 0
    if pump.speedLevels and LUASQUARE_PUMP.GetPumpSpeedMultiplier then speed = LUASQUARE_PUMP.GetPumpSpeedMultiplier(pump) * 100 end
    local sub = string.format('%.0f%% %.0f/s', speed, pump.lastFlow or 0)
    if pump.regulate then sub = string.format('R %.0f/%.0f %.0f/s', pump.regulationLevel or 0, pump.regulationTarget or 0, pump.lastFlow or 0) end

    return {
        label = label,
        value = state,
        sub = sub,
        color = Color(205, 235, 240),
        valueColor = color
    }
end

local function MAPDEF_valveColumn(label, valveName)
    local valve = LUASQUARE_VALVE.GetValve(valveName) or {}
    local open = valve.open and true or false
    return {
        label = label,
        value = open and 'OPEN' or 'SHUT',
        sub = string.format('%.0f/s', valve.lastFlow or 0),
        color = Color(205, 235, 240),
        valueColor = open and Color(110, 255, 150) or Color(255, 210, 80)
    }
end

local function MAPDEF_coolingTowerColumn(label, towerName)
    local tower = LUASQUARE_COOLINGTOWER and LUASQUARE_COOLINGTOWER.GetCoolingTower(towerName) or {}
    local state, color = MAPDEF_powerState(tower.enabled)
    local basinPercent = 0
    if tower.basinMaxAmount and tower.basinMaxAmount > 0 then basinPercent = math.Clamp((tower.basinAmount or 0) / tower.basinMaxAmount, 0, 1) * 100 end
    return {
        label = label,
        value = state,
        sub = string.format('I%.0f O%.0f %.0f%% %.0fC', tower.lastWaterReceived or 0, tower.lastWaterCooled or 0, basinPercent, tower.basinTemperature or 20),
        color = Color(205, 235, 240),
        valueColor = color
    }
end

local function MAPDEF_levelTargetColumn(label, current, target)
    return {
        label = label,
        value = string.format('%.0f%%', target or 0),
        sub = string.format('LVL %.0f%%', current or 0),
        color = Color(205, 235, 240),
        valueColor = Color(110, 255, 150)
    }
end

local function MAPDEF_gridColumn(label, gridName)
    local grid = LUASQUARE_POWERGRID.GetGrid(gridName) or {}
    local online = grid.enabled and not grid.tripped and grid.energized
    local value = online and string.format('%.2fHz', grid.frequency or 0) or 'DEAD'
    local sub = string.format('G%.1f L%.1f I%.1f', grid.lastGenerationMW or 0, grid.lastLoadMW or 0, grid.lastImportMW or 0)
    if grid.tripped then sub = 'TRIP ' .. tostring(grid.tripReason or '') end

    return {
        label = label,
        value = value,
        sub = sub,
        color = Color(205, 235, 240),
        valueColor = online and Color(110, 255, 150) or Color(255, 95, 95)
    }
end

local function MAPDEF_transformerColumn(label, transformerName)
    local transformer = LUASQUARE_POWERGRID.GetTransformer(transformerName) or {}
    local online = transformer.enabled and transformer.closed and not transformer.tripped and transformer.available
    local value = online and 'CLOSED' or 'OPEN'
    if transformer.tripped then value = 'TRIP' end

    return {
        label = label,
        value = value,
        sub = string.format('%.1f/%.1fMW', transformer.lastMW or 0, transformer.maxMW or 0),
        color = Color(205, 235, 240),
        valueColor = online and Color(110, 255, 150) or Color(255, 210, 80)
    }
end

local function MAPDEF_generatorColumn(label, generatorName)
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator(generatorName) or {}
    local breaker = generator.breaker and LUASQUARE_POWERGRID.GetBreaker(generator.breaker) or {}
    local online = generator.enabled and not generator.tripped and breaker and breaker.closed
    local value = generator.tripped and 'TRIP' or (online and 'ON' or 'OFF')

    return {
        label = label,
        value = value,
        sub = string.format('%.1f/%.1fMW', generator.lastAcceptedMW or 0, generator.maxMW or 0),
        color = Color(205, 235, 240),
        valueColor = online and Color(110, 255, 150) or Color(255, 210, 80)
    }
end

local function MAPDEF_dieselColumn(label, dieselName)
    local diesel = LUASQUARE_DIESELGENERATOR.GetDieselGenerator(dieselName) or {}
    local fuelPercent = 0
    if diesel.fuelTankCapacity and diesel.fuelTankCapacity > 0 then fuelPercent = math.Clamp((diesel.fuelTankAmount or 0) / diesel.fuelTankCapacity, 0, 1) * 100 end
    local state, color = MAPDEF_powerState(diesel.enabled)

    return {
        label = label,
        value = state,
        sub = string.format('%.1fMW %.0f%%F', diesel.lastAvailableMW or 0, fuelPercent),
        color = Color(205, 235, 240),
        valueColor = color
    }
end

local function MAPDEF_pumpLoadMW(...)
    local total = 0
    for _, pumpName in ipairs({...}) do
        local pump = LUASQUARE_PUMP.GetPump(pumpName)
        if pump then total = total + (pump.lastPowerAcceptedMW or 0) end
    end
    return total
end

-- =========================================
-- 3D2D PANEL DISPLAYS REGISTER
-- =========================================

LUASQUARE_3D2D.RegisterDisplay('aux_flow_status_panel', MAPDEF_panelBase(
    'AUX FLOW STATUS',
    Vector(91, -535, 598), 44, 22,
    Angle(0, -90, 90)
))
LUASQUARE_3D2D.BindDisplay('aux_flow_status_panel', function()
    return {
        {
            type = 'columns',
            height = 120,
            columns = {
                MAPDEF_pumpColumn('FW PUMP A', 'feedwater_pump_a'),
                MAPDEF_pumpColumn('FW PUMP B', 'feedwater_pump_b'),
                MAPDEF_levelTargetColumn('RPV TARGET', RBMK.MaxWater > 0 and ((RBMK.Water or 0) / RBMK.MaxWater) * 100 or 0, MAPDEF_feedwaterTargetPercent),
                MAPDEF_valveColumn('DRAIN VLV', 'rpv_drain_valve')
            }
        }
    }
end)

LUASQUARE_3D2D.RegisterDisplay('condensate_pump_status_panel', MAPDEF_panelBase({
    title = 'COOLING LOOP',
    target = 'tar_display_coolingloop',
    width = 44,
    height = 22
}))
LUASQUARE_3D2D.BindDisplay('condensate_pump_status_panel', function()
    return {
        {
            type = 'columns',
            height = 120,
            columns = {
                MAPDEF_pumpColumn('COND PUMP A1', 'condensate_pump_a1'),
                MAPDEF_coolingTowerColumn('COOLING TWR A', 'main_cooling_tower'),
                MAPDEF_valveColumn('HOTWELL DRN', 'hotwell_drain_valve')
            }
        }
    }
end)

LUASQUARE_3D2D.RegisterDisplay('rpv_status_panel', MAPDEF_panelBase(
    'RPV STATUS',
    Vector(91, -461, 598), 24, 22,
    Angle(0, -90, 90)
))
LUASQUARE_3D2D.BindDisplay('rpv_status_panel', function()
    local waterFraction = 0
    if RBMK.MaxWater and RBMK.MaxWater > 0 then waterFraction = math.Clamp((RBMK.Water or 0) / RBMK.MaxWater, 0, 1) end
    local pressureFraction = 0
    if RBMK.RPVMaxPressure and RBMK.RPVMaxPressure > 0 then pressureFraction = math.Clamp((RBMK.RPVPressure or 0) / RBMK.RPVMaxPressure, 0, 1) end

    return {
        { type = 'value', label = 'MWth', value = RBMK.LastThermalMW or 0, decimals = 0 },
        { type = 'value', label = 'RPV Pressure', value = RBMK.RPVPressure or 0, decimals = 1, unit = 'bar', warn = pressureFraction > 0.85 },
        { type = 'bar', fraction = pressureFraction, height = 5 },
        { type = 'bar', label = 'Water Level', fraction = waterFraction, height = 5 },
        { type = 'value', label = 'Water Temp.', value = RBMK.WaterTemperature or 0, decimals = 0, unit = 'C' },
        { type = 'value', label = 'Steam Temp.', value = RBMK.SteamTemperature or 0, decimals = 0, unit = 'C' },
        { type = 'value', label = 'Cooling Eff.', value = (RBMK.LastCoolingEfficiency or 0) * 100, decimals = 0, unit = '%' }
    }
end)

LUASQUARE_3D2D.RegisterDisplay('tg1_status_panel', MAPDEF_panelBase({
    title = 'TURBINE A',
    target = 'tar_display_tg1',
    width = 44,
    height = 32
}))
LUASQUARE_3D2D.BindDisplay('tg1_status_panel', function()
    local data = LUASQUARE_TURBINE.GetTurbine('tg1')
    local generator = LUASQUARE_POWERGENERATOR.GetGenerator('tg1_generator') or {}
    local grid = LUASQUARE_POWERGRID.GetGrid('station_grid') or {}
    return {
        { type = 'value', label = 'RPM', value = data.rpm or 0, decimals = 2 , unit = 'RPM'},
        { type = 'value', label = 'Grid Frequency', value = grid.frequency or 0, decimals = 2, unit = 'Hz' },
        { type = 'value', label = 'Sync Error', value = generator.lastPhaseError or 0, decimals = 1, unit = 'deg' },
        { type = 'value', label = 'Turbine Valve', value = data.valve * 100 or 0, decimals = 1 },
        { type = 'bar', fraction = data.valve, height = 5 },
        { type = 'value', label = 'Bypass Valve', value = data.bypassValve * 100 or 0, decimals = 1 },
        { type = 'bar', fraction = data.bypassValve, height = 5 },
        { type = 'value', label = 'Vibration', value = (data.vibration / data.tripVibration) * 100 or 0, decimals = 2, unit = '%'},
        { type = 'bar', fraction = data.vibration / data.tripVibration, height = 5 },
        { type = 'value', label = 'Generator Output', value = generator.lastAcceptedMW or data.lastMW or 0, decimals = 2, unit = 'MW' },
    }
end)

LUASQUARE_3D2D.RegisterDisplay('electrical_status_panel', MAPDEF_panelBase({
    title = 'ELECTRICALS',
    target = 'tar_display_electricals',
    width = 58,
    height = 38,
    lineHeight = 16
}))
LUASQUARE_3D2D.BindDisplay('electrical_status_panel', function()
    local stationGrid = LUASQUARE_POWERGRID.GetGrid('station_grid') or {}
    local load = stationGrid.lastLoadMW or 0
    local available = stationGrid.lastAvailableMW or 0
    local loadFraction = 0
    if available > 0 then loadFraction = math.Clamp(load / available, 0, 1.5) end
    local overload = load > math.max(available, 0.0001) * (stationGrid.overloadTripFraction or 1.15)

    return {
        {
            type = 'columns',
            height = 120,
            columns = {
                MAPDEF_gridColumn('STATION', 'station_grid'),
                MAPDEF_gridColumn('OFFSITE', 'offsite_grid'),
                MAPDEF_transformerColumn('IMPORT XFMR', 'offsite_station_transformer'),
                MAPDEF_transformerColumn('EXPORT XFMR', 'offsite_export_transformer')
            }
        },
        { type = 'value', label = 'Station Load', value = load, decimals = 1, unit = 'MW', warn = overload },
        { type = 'bar', label = 'Load / Capacity', fraction = loadFraction, height = 5, warn = overload },
        {
            type = 'columns',
            height = 112,
            columns = {
                MAPDEF_generatorColumn('TG1 GEN', 'tg1_generator'),
                MAPDEF_generatorColumn('EDG1 GEN', 'edg1_generator'),
                MAPDEF_dieselColumn('EDG1', 'edg1'),
                {
                    label = 'PUMP LOAD',
                    value = string.format('%.1fMW', MAPDEF_pumpLoadMW('feedwater_pump_a', 'feedwater_pump_b', 'condensate_pump_a1')),
                    sub = 'FW A/B + COND',
                    color = Color(205, 235, 240),
                    valueColor = Color(110, 255, 150)
                }
            }
        }
    }
end)

-- =========================================
-- OPERATOR INTERFACES
-- =========================================

local function MAPDEF_setFeedwaterTarget(percent)
    MAPDEF_feedwaterTargetPercent = math.Clamp(tonumber(percent) or 0, 0, 100)
    LUASQUARE_PUMP.SetRegulationTarget('feedwater_pump_a', MAPDEF_feedwaterTargetPercent)
    LUASQUARE_PUMP.SetRegulationTarget('feedwater_pump_b', MAPDEF_feedwaterTargetPercent)
end

local function MAPDEF_setHotwellTarget(percent)
    MAPDEF_hotwellTargetPercent = math.Clamp(tonumber(percent) or 0, 0, 100)
    LUASQUARE_PUMP.SetRegulationTarget('condensate_pump_a1', MAPDEF_hotwellTargetPercent)
end

-- Feedwater pump regulator target keypad, value is RPV water level percent.
LUASQUARE_SEG7.RegisterDisplay('fwlevelctrl', {
    'fwlevelctrl_0',
    'fwlevelctrl_1',
    'fwlevelctrl_2'
})
LUASQUARE_KEYPAD.RegisterKeypad('fwlevelctrl',
    {
        maxDigits = 3,
        maxValue = 100,
        display = 'fwlevelctrl',
        initialValue = MAPDEF_feedwaterTargetPercent,
        clearOnSubmit = false,
        onSubmit = function(value)
            MAPDEF_setFeedwaterTarget(value)
        end
    }
)

-- Condensate pump regulator target keypad, value is hotwell level percent.
LUASQUARE_SEG7.RegisterDisplay('hotwellctrl', {
    'hotwellctrl_0',
    'hotwellctrl_1',
    'hotwellctrl_2'
})
LUASQUARE_KEYPAD.RegisterKeypad('hotwellctrl',
    {
        maxDigits = 3,
        maxValue = 100,
        display = 'hotwellctrl',
        initialValue = MAPDEF_hotwellTargetPercent,
        clearOnSubmit = false,
        onSubmit = function(value)
            MAPDEF_setHotwellTarget(value)
        end
    }
)

-- Manual Control Rod Keypad and Selector Panel
LUASQUARE_SEG7.RegisterDisplay('rodctrl', {
    'rodctrl_0',
    'rodctrl_1',
    'rodctrl_2'
})
LUASQUARE_KEYPAD.RegisterKeypad('rodctrl',
    {
        maxDigits = 3,
        maxValue = 100,
        display = 'rodctrl',
        onSubmit = function(value)
            LUASQUARE_ROD_SELECTOR.Apply(value)
        end
    }
)

-- Automatic Power Regulator target keypad, value is MW thermal.
LUASQUARE_SEG7.RegisterDisplay('aprctrl', {
    'aprctrl_0',
    'aprctrl_1',
    'aprctrl_2',
    'aprctrl_3'
})
LUASQUARE_KEYPAD.RegisterKeypad('aprctrl',
    {
        maxDigits = 4,
        maxValue = 9999,
        display = 'aprctrl',
        clearOnSubmit = false,
        onSubmit = function(value)
            RBMK.SetAutoRegulatorTargetMW(value)
            RBMK.SetAutoRegulatorEnabled(value > 0)
        end
    }
)

-- =========================================
-- ANNUNCIATOR FUNCTION
-- =========================================

local MAPDEF_annunciatorCorePos = Vector(35, -433, 627)

LUASQUARE_ANNUNCIATOR.SetCorePosition(MAPDEF_annunciatorCorePos)
LUASQUARE_ANNUNCIATOR.SetUnmuteCue('buttons/button17.wav', 200, 10, 100)

-- =========================================
-- ANNUNCIATOR
-- =========================================

LUASQUARE_ANNUNCIATOR.RegisterAlarm('rpv_pressure_high', {
    label = 'RPV PRESSURE HIGH',
    soundEntity = 'ann_rpv_pressure_high_snd',
    getter = function()
        return RBMK.RPVPressure > 60
    end
})
LUASQUARE_ANNUNCIATOR.RegisterAlarm('rpv_temperature_high', {
    label = 'RPV TEMPERATURE HIGH',
    soundWav = 'ambient/alarms/combine_bank_alarm_loop4.wav',
    soundDistance = 100,
    soundVolume = 10,
    soundPitch = 100,
    getter = function()
        return RBMK.MaxHeat > 1100
    end
})
LUASQUARE_ANNUNCIATOR.RegisterAlarm('fuel_channel_leak', {
    label = 'FUEL CHANNEL LEAK',
    soundWav = 'bms_objects/alarms/alarm14.wav',
    soundDistance = 100,
    soundVolume = 10,
    soundPitch = 100,
    ackStopsSound = false,
    getter = function()
        local leakCount = RBMK.GetFuelChannelLeakCount()
        if leakCount <= 0 then return false end

        local lastLeak = RBMK.EventState and RBMK.EventState.LastFuelLeak
        if lastLeak then return true, string.format('%d CHANNEL(S), LAST %d,%d', leakCount, lastLeak.x or 0, lastLeak.y or 0) end
        return true, string.format('%d CHANNEL(S)', leakCount)
    end
})
LUASQUARE_ANNUNCIATOR.RegisterPropDisplay('reactor_panel', {
    indicators = {
        rpv_pressure_high = 'ann_rpv_pressure_high',
        rpv_temperature_high = 'ann_rpv_temperature_high',
        fuel_channel_leak = 'ann_fuel_channel_leak'
    }
})

LUASQUARE_ANNUNCIATOR.RegisterAlarm('tg1_trip', {
    label = 'TURBINE A TRIP',
    soundWav = 'bms_objects/alarms/alarm4.wav',
    soundDistance = 100,
    soundVolume = 10,
    soundPitch = 110,
    getter = function()
        return LUASQUARE_TURBINE.GetTurbine('tg1').tripped
    end
})

LUASQUARE_ANNUNCIATOR.RegisterPropDisplay('turbine_a_panel', {
    indicators = {
        tg1_trip = 'ann_turbine_a_trip'
    }
})

LUASQUARE_ANNUNCIATOR.RegisterAlarm('station_grid_overload', {
    label = 'STATION GRID OVERLOAD',
    soundWav = 'bms_objects/alarms/alarm6.wav',
    soundDistance = 100,
    soundVolume = 10,
    soundPitch = 115,
    getter = function()
        local grid = LUASQUARE_POWERGRID.GetGrid('station_grid')
        if not grid then return false end

        local available = math.max(grid.lastAvailableMW or 0, 0.0001)
        local load = grid.lastLoadMW or 0
        local overload = load > available * (grid.overloadTripFraction or 1.15)
        if overload then return true, string.format('%.1f / %.1f MW', load, available) end
        return false
    end
})

LUASQUARE_ANNUNCIATOR.RegisterPropDisplay('station_grid_panel', {
    indicators = {
        station_grid_overload = 'ann_station_grid_overload'
    }
})

-- =========================================
-- END DEFINITION
-- =========================================

RBMK.Start()

LUASQUARE_SEG7.Start()
LUASQUARE_GAUGE.Start()
LUASQUARE_3D2D.Start()
LUASQUARE_ANNUNCIATOR.Start()
LUASQUARE_FLUID.Start()
LUASQUARE_VALVE.Start()
LUASQUARE_PUMP.Start()
LUASQUARE_CONDENSER.Start()
LUASQUARE_TURBINE.Start()
LUASQUARE_COOLINGTOWER.Start()
LUASQUARE_POWERGRID.Start()
LUASQUARE_DIESELGENERATOR.Start()
LUASQUARE_POWERGENERATOR.Start()
LUASQUARE_POWERPLANT.Debug.Start()

print('[LUASQUARE FRAMEWORK] Initialization completed for ' .. MAPNAME)
LUASQUARE_FRAMEWORK_INITIALIZED = true
SetGlobal2Bool('LUASQUARE_FRAMEWORK_INITIALIZED_GLOBAL', LUASQUARE_FRAMEWORK_INITIALIZED)
