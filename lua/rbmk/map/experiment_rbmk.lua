if LITHOSQUARE_RBMK_BOOTSTRAPPED then
    print('[LITHOSQUARE RBMK] BOOTSTRAP FAILED!\n[LITHOSQUARE RBMK] It already happened once in this session. Reload map.')
return end
LITHOSQUARE_RBMK_BOOTSTRAPPED = true

-- =========================================
-- MAP DEFINITION AND BOOTSTRAP
-- =========================================

-- DEPLOY WITH:
-- include('rbmk/map/experiment_rbmk.lua')
-- USING lua_run

-- =========================================
-- CORE SYSTEMS
-- =========================================

include('7segdisplay_controller.lua')
include('rbmk/init.lua')

-- =========================================
-- WORLD SETTINGS
-- =========================================

RBMK.WorldOrigin = Vector(328, -640, 420)
RBMK.CellSpacing = 64

RBMK.FluxRange = 5

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

SEG7.RegisterDisplay('core_temp', {
    'core_temp_0',
    'core_temp_1',
    'core_temp_2',
    'core_temp_3'
})

SEG7.BindDisplay('core_temp', function()
    return math.floor(RBMK.GetHeat(5, 5))
end)

-- =========================================
-- START SYSTEMS
-- =========================================

RBMK.Start()

SEG7.Start()

print('[LITHOSQUARE RBMK] Map Bootstrap Finished.')