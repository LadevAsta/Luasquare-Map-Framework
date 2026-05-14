if LITHOSQUARE_RBMK_INITIALIZED then
    print('[LITHOSQUARE RBMK] BOOTSTRAP FAILED!\n[LITHOSQUARE RBMK] It already happened once in this session. Reload map.')
return end

-- =========================================
-- MAP DEFINITION AND BOOTSTRAP
-- =========================================

-- This is orchestration script to set up map integration.
-- Deploy THIS SCRIPT using a lua_run in the map :
-- include('lithos_rbmk/map/experiment_rbmk.lua')

-- =========================================
-- CORE MODULES
-- =========================================

include('lithos_module/seg7display.lua') -- Pseudo 7-Segments numeric display
include('lithos_module/gaugedisplay.lua') -- Gauge display
include('lithos_module/keypad_controller.lua') -- Numeric Keypads
include('lithos_module/rod_selector.lua') -- RBMK Control Rod Selector
include('lithos_rbmk/init.lua') -- RBMK Core

-- =========================================
-- WORLD SETTINGS
-- =========================================

--Reactor position in the map. (TOP LEFT CORNER) Exactly where the [1,1] Column will be.
--See Hammer++'s Global axis gizmo. red and green arrows indicates columns extend direction.
RBMK.WorldOrigin = Vector(352, -672, 448)
RBMK.CellSpacing = 64

RBMK.TickInterval = 0.1

--Heat Diffusion FACTOR of Reactor Vessel. Diff is multiplied by this value 
--(Should NOT be 0 or a lot higher than 1 Default : 0.05)
RBMK.RPVHeatDiffusion = 0.05

--Amount of column jumps flux can go through, reflectors does not reset the count.
RBMK.FluxRange = 12
--Subtract reported total neutron flux with this value. Usually the constant output of all Neutron Source Columns times 4.
RBMK.TotalFluxSubtractDefine = 26 * 4

--Control rod movespeed multiplier boost on SCRAM
RBMK.ControlrodScramBoost = 2
--Control rod func_movelinear's move distance you set in Hammer (inches)
RBMK.RodMoveDistance = 64


-- =========================================
-- REACTOR
-- =========================================

-- Layout orchestrator
include('lithos_rbmk/layouts/LRBMKP-400.lua')

--Starting Water inside the reactor pressure vessel (in PERCENTAGE)
RBMK.AddInitialWater(45)

-- =========================================
-- DISPLAYS
-- =========================================

LITHOS_SEG7.RegisterDisplay('reactor_avgtemp', {
    'reactor_avgtemp_0',
    'reactor_avgtemp_1',
    'reactor_avgtemp_2',
    'reactor_avgtemp_3',
    'reactor_avgtemp_4'
})
LITHOS_SEG7.BindDisplay('reactor_avgtemp', function()
    return math.floor(RBMK.MaxHeat)
end)

LITHOS_SEG7.RegisterDisplay('f1_coretemp', {
    'f1_coretemp_0',
    'f1_coretemp_1',
    'f1_coretemp_2',
    'f1_coretemp_3',
    'f1_coretemp_4'
})
LITHOS_SEG7.BindDisplay('f1_coretemp', function()
    return math.floor(RBMK.GetCoreHeat(5, 5))
end)

LITHOS_SEG7.RegisterDisplay('f1_skintemp', {
    'f1_skintemp_0',
    'f1_skintemp_1',
    'f1_skintemp_2',
    'f1_skintemp_3'
})
LITHOS_SEG7.BindDisplay('f1_skintemp', function()
    return math.floor(RBMK.GetSkinHeat(5, 5))
end)

LITHOS_SEG7.RegisterDisplay('f1_coltemp', {
    'f1_coltemp_0',
    'f1_coltemp_1',
    'f1_coltemp_2',
    'f1_coltemp_3'
})
LITHOS_SEG7.BindDisplay('f1_coltemp', function()
    return math.floor(RBMK.GetHeat(5, 5))
end)


LITHOS_SEG7.RegisterDisplay('totalflux', {
        'flux_0',
        'flux_1',
        'flux_2',
        'flux_3',
        'flux_4'
    }
)
LITHOS_SEG7.BindDisplay(
    'totalflux',
    function() return math.floor(RBMK.TotalFluxSubtracted) end
)

LITHOS_SEG7.RegisterDisplay('averageXenon', {
        'xenon_0',
        'xenon_1',
        'xenon_2'
    }
)
LITHOS_SEG7.BindDisplay(
    'averageXenon',
    function() return math.floor(RBMK.AverageXenon) end
)

LITHOS_GAUGE.RegisterGauge('gauge_maxtemp', {
    entity = 'gauge_maxtemp',
    min = 0,
    max = 2000,
    speed = 18
})
LITHOS_GAUGE.BindGauge('gauge_maxtemp', function()
    if not RBMK or not RBMK.MaxHeat or RBMK.MaxHeat <= 0 then return 0 end
    return RBMK.MaxHeat or 0
end)

-- =========================================
-- OPERATOR INTERFACES
-- =========================================

-- Manual Control Rod Keypad and Selector Panel
LITHOS_SEG7.RegisterDisplay('rodctrl', {
    'rodctrl_0',
    'rodctrl_1',
    'rodctrl_2',
})
LITHOS_KEYPAD.RegisterKeypad('rodctrl',
    {
        maxDigits = 3,
        maxValue = 100,
        display = 'rodctrl',
        onSubmit = function(value)
            LITHOS_ROD_SELECTOR.Apply(value)
        end
    }
)


-- =========================================
-- END DEFINITION
-- =========================================

RBMK.Start()

LITHOS_SEG7.Start()
LITHOS_GAUGE.Start()

print('[LITHOSQUARE RBMK] RBMK Reactor Initialization Finished.')
LITHOSQUARE_RBMK_INITIALIZED = true
SetGlobal2Bool('LITHOSQUARE_RBMK_INITIALIZED_GLOBAL', LITHOSQUARE_RBMK_INITIALIZED)