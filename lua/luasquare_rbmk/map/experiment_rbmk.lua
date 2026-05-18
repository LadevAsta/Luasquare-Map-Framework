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
LUASQUARE_FLUID.TickInterval = 0.1
LUASQUARE_VALVE.TickInterval = 0.1
LUASQUARE_PUMP.TickInterval = 0.1

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

LUASQUARE_FLUID.RegisterNetwork('main_steam', {
    type = LUASQUARE_FLUID.TYPE_STEAMLINE,
    fluidType = 'steam',
    amount = 0,
    maxAmount = RBMK.MaxSteam,
    hardMaxAmount = RBMK.HardMaxSteam,
    maxPressure = 150,
    temperature = 280,
    monitorPos = RBMK.WorldOrigin + Vector(0, 0, 96 + MAPDEF_monitorZoffset)
})
RBMK.SetSteamNetwork('main_steam')

LUASQUARE_FLUID.RegisterNetwork('feedwater', {
    type = LUASQUARE_FLUID.TYPE_STEAMLINE,
    fluidType = 'water',
    amount = 0,
    maxAmount = RBMK.MaxWater,
    hardMaxAmount = RBMK.MaxWater,
    maxPressure = 150,
    temperature = 40,
    serviceRate = 0,
    monitorPos = RBMK.WorldOrigin + Vector(0, 96, 96 + MAPDEF_monitorZoffset)
})

LUASQUARE_FLUID.RegisterNetwork('drain_tank', {
    type = LUASQUARE_FLUID.TYPE_STEAMLINE,
    fluidType = 'water',
    amount = 0,
    maxAmount = RBMK.MaxWater,
    hardMaxAmount = RBMK.MaxWater,
    maxPressure = 5,
    temperature = 40,
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

LUASQUARE_CONDENSER.RegisterCondenser('god_condenser', {
    input = 'main_steam',
    output = 'feedwater',
    ratio = 1600,
    maxRate = math.huge,
    enabled = true,
    godMode = true,
    monitorPos = RBMK.WorldOrigin + Vector(0, 288, 96 + MAPDEF_monitorZoffset)
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
    return math.floor(RBMK.LastThermalMW)
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
-- END DEFINITION
-- =========================================

RBMK.Start()

LUASQUARE_SEG7.Start()
LUASQUARE_GAUGE.Start()
LUASQUARE_FLUID.Start()
LUASQUARE_VALVE.Start()
LUASQUARE_PUMP.Start()
LUASQUARE_CONDENSER.Start()
LUASQUARE_POWERPLANT.Debug.Start()

print('[LUASQUARE RBMK] RBMK Reactor Initialization Finished.')
LUASQUARE_RBMK_INITIALIZED = true
SetGlobal2Bool('LUASQUARE_RBMK_INITIALIZED_GLOBAL', LUASQUARE_RBMK_INITIALIZED)
