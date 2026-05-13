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

--Starting Water inside the reactor pressure vessel
RBMK.Water = 5000

-- =========================================
-- DISPLAYS
-- =========================================

LITHOS_SEG7.RegisterDisplay('core_temp', {
    'core_temp_0',
    'core_temp_1',
    'core_temp_2',
    'core_temp_3'
})
LITHOS_SEG7.BindDisplay('core_temp', function()
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

print('[LITHOSQUARE RBMK] RBMK Reactor Initialization Finished.')
LITHOSQUARE_RBMK_INITIALIZED = true
SetGlobal2Bool('LITHOSQUARE_RBMK_INITIALIZED_GLOBAL', LITHOSQUARE_RBMK_INITIALIZED)