-- This module contains system for powergrid.

-- Power Grids. (Site's Grid and Offsite's grid) Which allow going on-grid or off-grid.
-- Grid load.
-- Generator and Consumer. (eg. Turbines, Pumps/CoolingSystems/Auxiliary)
-- Bridge Transformers (We'll just make them on/off switches to connect between different grids)
-- Breakers (resetting them re-enable pump after they TRIP)
-- Actual electrical physic??? Adding a generator require them to be synced. Via API to this module. and callback if they did it or not.