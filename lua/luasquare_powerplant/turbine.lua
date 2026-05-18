-- This module is the Turbine system.

-- Use whatever math or physics to turn steam from steamline into rotational power.
-- The turbine runs at 1800 RPM. Because it is large af.
-- Actually start generating power when they are Synced to the powergrid. Trips if it fails.
-- Returns low-pressure-steam into fluidnetwork (The Not-Simple Network kind) which then probably will be taken to condenser.
-- Steam:LPS ratio = 1600:400

-- Sync process for Powerplant Steam Turbine (Gamified)
-- Operator adjust Turbine Valve and Bypass Valve which control how it spins.
-- I am not sure how will we implement synchroscope technically and visually.
-- Pressing SYNC button will make it attempt syncing to the grid.
-- If AUTO Sync is enabled Turbine Syncs itself automatically when the phase aligns and RPM change is stable.

-- If server ConVar 'I hate Turbine Sync' is enabled all of this is skipped and turbine will spin and generate power right away as it receives steam.
-- While clamping it's RPM at 1800 once reached.

-- Turbine can TRIP! Sync failure or High Vibration causes it.
-- It can also fail catastrophically and destroy the blades. not sure what will factor into this happening yet.