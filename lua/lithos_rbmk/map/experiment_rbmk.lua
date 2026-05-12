if LITHOSQUARE_RBMK_BOOTSTRAPPED then
    print('[LITHOSQUARE RBMK] BOOTSTRAP FAILED!\n[LITHOSQUARE RBMK] It already happened once in this session. Reload map.')
return end
LITHOSQUARE_RBMK_BOOTSTRAPPED = true

-- =========================================
-- MAP DEFINITION AND BOOTSTRAP
-- =========================================

-- This is orchestration script to set up map integration.
-- Deploy using a lua_run in the map :
-- include('rbmk/map/experiment_rbmk.lua')

-- =========================================
-- CORE MODULES
-- =========================================

include('lithos_module/7segdisplay_controller.lua') -- Pseudo 7-Segments numeric display
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

-- DEBUGS
RBMK.Debug.Enabled = true

RBMK.Debug.DrawHeat = true
RBMK.Debug.DrawFlux = true
RBMK.Debug.DrawXenon = true
RBMK.Debug.DrawFluxRays = true
RBMK.Debug.ShowBlank = false

-- =========================================
-- REACTOR LAYOUT
-- =========================================

include('lithos_rbmk/layouts/test.lua')

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
LITHOS_ROD_SELECTOR.RegisterIndicator('NS', 'sel_NS')
LITHOS_ROD_SELECTOR.RegisterIndicator('U1', 'sel_U1')
LITHOS_ROD_SELECTOR.RegisterIndicator('U2', 'sel_U2')
LITHOS_ROD_SELECTOR.RegisterIndicator('U3', 'sel_U3')
LITHOS_ROD_SELECTOR.RegisterIndicator('U4', 'sel_U4')
LITHOS_ROD_SELECTOR.RegisterIndicator('R1', 'sel_R1')
LITHOS_ROD_SELECTOR.RegisterIndicator('R2', 'sel_R2')
LITHOS_ROD_SELECTOR.RegisterIndicator('R3', 'sel_R3')
LITHOS_ROD_SELECTOR.RegisterIndicator('R4', 'sel_R4')
LITHOS_ROD_SELECTOR.RegisterIndicator('R5', 'sel_R5')
LITHOS_ROD_SELECTOR.RegisterIndicator('R6', 'sel_R6')
LITHOS_ROD_SELECTOR.RegisterIndicator('R7', 'sel_R7')
LITHOS_ROD_SELECTOR.RegisterIndicator('R8', 'sel_R8')


-- =========================================
-- END DEFINITION
-- =========================================

RBMK.Start()

LITHOS_SEG7.Start()

print('[LITHOSQUARE RBMK] Map Bootstrap Finished.')