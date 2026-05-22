if LUASQUARE_RBMK_INITIALIZED then
    print('[LUASQUARE RBMK] BOOTSTRAP FAILED!\n[LUASQUARE RBMK] It already happened once in this session. Reload map.')
return end

-- =========================================
-- MAP DEFINITION AND BOOTSTRAP
-- =========================================

-- This is orchestration script to set up map integration.
-- Deploy THIS SCRIPT using a lua_run in the map :
-- include('luasquare_rbmk/map/experiment_rbmk.lua')

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
RBMK.BlowoutFallbackValveCount = 77
-- How much steam is removed from the vessel for each jump. Set it weak to make it serve only dramatic purposes.
RBMK.BlowoutSteamLoss = 0.5
-- Register blowout func_movelinears
RBMK.ClearBlowoutValves()
RBMK.RegisterBlowoutValveRange(RBMK.BlowoutValvePrefix, RBMK.BlowoutFallbackValveCount)

RBMK.FuelLeakTemperature = 1500
RBMK.FuelMeltdownTemperature = 3000
RBMK.SteamOutletFlowRate = 0.5
RBMK.SteamOutletOpen = true
RBMK.FeedwaterInletOpen = true
RBMK.DrainValveOpen = false
RBMK.DrainFlowRate = 500

-- Automatic Regulator Rods. These are short control rods inserted from the bottom of Manual Control rod.
RBMK.AutoRegulatorEnabled = false
RBMK.AutoRegulatorUsePID = false
RBMK.AutoRegulatorTargetMW = 0
-- The length of auto regulator (0.0 - 1.0)
RBMK.AutoRegulatorMaxInsertion = 0.1
-- PID
RBMK.AutoRegulatorKp = 0.00002
RBMK.AutoRegulatorKi = 0.000001
RBMK.AutoRegulatorKd = 0.000005

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
-- FLUID NETWORKS
-- =========================================

local MAPDEF_monitorZoffset = 128
-- Debug monitor positions can be Vector(...) or monitorTarget = 'named_info_target'.

LUASQUARE_FLUID.RegisterNetwork('main_steam', {
    type = LUASQUARE_FLUID.TYPE_STEAMLINE,
    fluidType = 'steam',
    amount = 0,
    volume = RBMK.SteamSpace,
    maxAmount = RBMK.MaxSteam,
    hardMaxAmount = RBMK.HardMaxSteam,
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

LUASQUARE_FLUID.RegisterNetwork('turbine_hotwell', {
    type = LUASQUARE_FLUID.TYPE_STEAMLINE,
    fluidType = 'water',
    amount = 0,
    maxAmount = RBMK.MaxWater,
    hardMaxAmount = RBMK.MaxWater,
    maxPressure = 20,
    temperature = 80,
    thermalLossRate = 0.01,
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

LUASQUARE_VALVE.RegisterValve('rpv_drain_valve', {
    a = 'rbmk_water',
    b = 'drain_tank',
    maxFlow = 500,
    open = false,
    bidirectional = false,
    monitorPos = RBMK.WorldOrigin + Vector(0, 384, 96 + MAPDEF_monitorZoffset)
})

LUASQUARE_PUMP.RegisterPump('feedwater_pump_a', {
    source = 'feedwater',
    target = 'rbmk',
    rate = 500,
    headPressure = 90,
    speedLevels = {0, 0.25, 0.5, 1},
    speedLevel = 3,
    enabled = true,
    monitorPos = RBMK.WorldOrigin + Vector(0, 192, 96 + MAPDEF_monitorZoffset)
})

LUASQUARE_PUMP.RegisterPump('feedwater_pump_b', {
    source = 'feedwater',
    target = 'rbmk',
    rate = 500,
    headPressure = 90,
    speedLevels = {0, 0.25, 0.5, 1},
    speedLevel = 1,
    enabled = false,
    monitorPos = RBMK.WorldOrigin + Vector(0, 192, 128 + MAPDEF_monitorZoffset)
})

LUASQUARE_PUMP.RegisterPump('condensate_pump_a1', {
    source = 'turbine_hotwell',
    target = 'main_cooling_tower',
    rate = 1000,
    headPressure = 150,
    speedLevels = {0, 0.25, 0.5, 1},
    speedLevel = 4,
    enabled = true,
    monitorPos = 'tar_condpump_a1'
})

LUASQUARE_TURBINE.RegisterTurbine('tg1', {
    input = 'main_steam',
    condenserOutput = 'turbine_hotwell',
    bypassCondenserOutput = 'turbine_hotwell',
    condenserOutputTemperature = 80,
    bypassCondenserOutputTemperature = 95,
    maxSteamRate = 700000,
    ratedSteamRate = 350000,
    bypassMaxSteamRate = 700000,
    valve = 0,
    bypassValve = 0,
    enabled = true,
    autoSync = false,
    soundEntity = 'tg1_turbine_sound',
    soundEntity2 = 'tg1_turbine_sound2',
    soundMinVolume = 1,
    soundMaxVolume = 10,
    soundMinPitch = 80,
    soundMaxPitch = 140,
    shakeEntity = 'tg1_turbine_shake',
    shakeMaxAmplitude = 4,
    shakeMaxFrequency = 80,
    tripRelay = 'tg1_trip_relay',
    monitorPos = 'tar_turbine_generator_a'
})

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

-- =========================================
-- 3D2D PANEL DISPLAYS FUNCTION
-- =========================================

-- width/height are Hammer units. At scale 0.1, a 44x22 HU panel gets a 440x220 pixel canvas.
local MAPDEF_panelScale = 0.1

local function MAPDEF_panelBase(title, pos, width, height, angle)
    local compact = height <= 16
    return {
        pos = pos,
        ang = angle,
        anchorX = 0.5,
        anchorY = 0.5,
        scale = MAPDEF_panelScale,
        width = width,
        height = height,
        padding = compact and 6 or 10,
        lineHeight = compact and 13 or 18,
        titleHeight = compact and 18 or 28,
        font = compact and 'Luasquare3D2D_Small' or nil,
        titleFont = compact and 'Luasquare3D2D_Line' or nil,
        title = title,
        backgroundColor = Color(3, 10, 12, 235),
        borderColor = Color(30, 163, 216, 230),
        textColor = Color(205, 235, 240),
        titleColor = Color(255, 255, 255),
        barColor = Color(80, 220, 160)
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

    return {
        label = label,
        value = state,
        sub = string.format('%.0f%% %.0f/s', speed, pump.lastFlow or 0),
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
                MAPDEF_valveColumn('DRAIN VLV', 'rpv_drain_valve')
            }
        }
    }
end)

LUASQUARE_3D2D.RegisterDisplay('condensate_pump_status_panel', MAPDEF_panelBase(
    'COOLING LOOP',
    Vector(91, -749, 598), 44, 22,
    Angle(0, -90, 90)
))
LUASQUARE_3D2D.BindDisplay('condensate_pump_status_panel', function()
    return {
        {
            type = 'columns',
            height = 120,
            columns = {
                MAPDEF_pumpColumn('COND PUMP A1', 'condensate_pump_a1'),
                MAPDEF_coolingTowerColumn('COOLING TWR A', 'main_cooling_tower')
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
        { type = 'value', label = 'MWt', value = RBMK.LastThermalMW or 0, decimals = 0 },
        { type = 'value', label = 'RPV Pressure', value = RBMK.RPVPressure or 0, decimals = 1, unit = 'bar', warn = pressureFraction > 0.85 },
        { type = 'bar', fraction = pressureFraction, height = 5 },
        { type = 'bar', label = 'Water Level', fraction = waterFraction, height = 5 },
        { type = 'value', label = 'Water Temp.', value = RBMK.WaterTemperature or 0, decimals = 0, unit = 'C' },
        { type = 'value', label = 'Steam Temp.', value = RBMK.SteamTemperature or 0, decimals = 0, unit = 'C' },
        { type = 'value', label = 'Cooling Eff.', value = (RBMK.LastCoolingEfficiency or 0) * 100, decimals = 0, unit = '%' }
    }
end)

LUASQUARE_3D2D.RegisterDisplay('tg1_status_panel', MAPDEF_panelBase(
    'TURBINE A',
    Vector(91, -624, 598), 44, 22,
    Angle(0, -90, 90)
))
LUASQUARE_3D2D.BindDisplay('tg1_status_panel', function()
    local data = LUASQUARE_TURBINE.GetTurbine('tg1')
    return {
        { type = 'value', label = 'RPM', value = data.rpm or 0, decimals = 2 , unit = 'RPM'},
        { type = 'value', label = 'Turbine Valve', value = data.valve * 100 or 0, decimals = 1 },
        { type = 'bar', fraction = data.valve, height = 5 },
        { type = 'value', label = 'Bypass Valve', value = data.bypassValve * 100 or 0, decimals = 1 },
        { type = 'bar', fraction = data.bypassValve, height = 5 },
        { type = 'value', label = 'Vibration', value = data.vibration or 0, decimals = 2, unit = '%'},
        { type = 'bar', fraction = data.vibration / 100, height = 5 },
        { type = 'value', label = 'Load', value = data.loadMW or 0, decimals = 2 },
    }
end)

-- =========================================
-- OPERATOR INTERFACES
-- =========================================

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
LUASQUARE_ANNUNCIATOR.SetUnmuteCue('buttons/button17.wav', 90, 1, 100)

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
LUASQUARE_POWERPLANT.Debug.Start()

print('[LUASQUARE RBMK] RBMK Reactor Initialization Finished.')
LUASQUARE_RBMK_INITIALIZED = true
SetGlobal2Bool('LUASQUARE_RBMK_INITIALIZED_GLOBAL', LUASQUARE_RBMK_INITIALIZED)
