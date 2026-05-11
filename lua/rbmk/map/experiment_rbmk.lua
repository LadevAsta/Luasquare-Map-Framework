if LITHOSQUARE_RBMK_BOOTSTRAPPED then
    print('[LITHOSQUARE RBMK] BOOTSTRAP FAILED!\n[LITHOSQUARE RBMK] It already happened once in this session. Reload map.')
return end
LITHOSQUARE_RBMK_BOOTSTRAPPED = true

-- =========================================
-- MAP DEFINITION AND BOOTSTRAP
-- =========================================

-- This is orchestration file to set up map integration.
-- Deploy with :
-- include('rbmk/map/experiment_rbmk.lua')
-- Using a lua_run in the map

-- =========================================
-- CORE MODULES
-- =========================================

include('lithos_module/7segdisplay_controller.lua') -- Pseudo 7-Segments numeric display
include('lithos_module/keypad_controller.lua') -- Numeric Keypads
include('lithos_module/rod_selector.lua') -- RBMK Control Rod Selector
include('rbmk/init.lua') -- RBMK Core

-- =========================================
-- WORLD SETTINGS
-- =========================================

--Reactor position in the map. (TOP LEFT CORNER)
--See Hammer++'s Global axis gizmo. red and green arrows indicates columns extend direction.
RBMK.WorldOrigin = Vector(328, -640, 420)
RBMK.CellSpacing = 64

--Amount of columns flux can go through without interaction.
RBMK.FluxRange = 5

--Control rod movespeed multiplier boost on SCRAM
RBMK.ControlrodScramBoost = 2

-- DEBUGS
RBMK.Debug.Enabled = true

RBMK.Debug.DrawHeat = true
RBMK.Debug.DrawFlux = true
RBMK.Debug.DrawXenon = true
RBMK.Debug.DrawFluxRays = true

-- =========================================
-- REACTOR LAYOUT
-- =========================================

include('rbmk/layouts/test.lua')

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

-- =========================================
-- KEYPADS
-- =========================================

-- Control
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
-- ROD SELECTOR
LITHOS_ROD_SELECTOR.RegisterIndicator('NS', 'sel_NS')
LITHOS_ROD_SELECTOR.RegisterIndicator('U1', 'sel_U1')
LITHOS_ROD_SELECTOR.RegisterIndicator('U2', 'sel_U2')
LITHOS_ROD_SELECTOR.RegisterIndicator('U3', 'sel_U3')
LITHOS_ROD_SELECTOR.RegisterIndicator('U4', 'sel_U4')


-- =========================================
-- START SYSTEMS
-- =========================================

RBMK.Start()

LITHOS_SEG7.Start()

print('[LITHOSQUARE RBMK] Map Bootstrap Finished.')