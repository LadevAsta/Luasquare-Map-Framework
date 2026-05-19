-- This module is the Turbine system.

-- Use whatever math or physics to turn steam from steamline into rotational power.
-- The turbine runs at 1800 RPM. Because it is large af.
-- Actually start generating power as grid load when they are Synced to the powergrid. Trips if it fails.
-- Returns low-pressure-steam into fluidnetwork (The Not-Simple Network kind) which then probably will be taken to condenser.
-- Steam:LPS ratio = 1600:400

-- Sync process for Powerplant Steam Turbine
-- Operator adjust Turbine Valve and Bypass Valve which control how much steam is fed to the turbine blade or bypassed to turbine condenser immediately.
-- I am not sure how will we implement synchroscope technically and visually, one good brush entity for this is func_rotating.
-- Pressing SYNC button will make it attempt syncing to the grid.
-- If AUTO Sync is enabled Turbine Syncs itself automatically when the phase aligns and RPM change is stable.
-- Adjustment of turbine valves involves 4 buttons. precises(+-0.1) and rough(+-1) as percentage adjustments for both.

-- Simple turbine is a varient that is more straightforward. Generates power right away as it receives steam according to it's rate.

-- Turbine can TRIP! Sync failure or High Vibration causes it.
-- It can also fail catastrophically and destroy the blades. not sure what will factor into this happening yet.