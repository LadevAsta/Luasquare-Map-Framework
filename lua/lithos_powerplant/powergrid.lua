-- This module contains system for powergrid.

-- Power Grids. (Site's Grid and Offsite's grid) Which allow going on-grid or off-grid.
-- Bridge between grids.
-- Grid load.
-- Generator and Consumer. (eg. Turbines and Pumps)
-- Transformers (We'll just make them on/off switches.)
-- Breakers (reseting them re-enable pump after they TRIP)
-- Actual electrical physic??? Adding a generator require them to be synced. Via API to this module. and callback if they did it or not.