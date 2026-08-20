-- Transvacuum Fuel Synthesis Complex (TFSC)
-- The Transvacuum Fuel Synthesis Complex produces annihilation feedstock and enriches dark-fusion cells by establishing a controlled region of negative-energy spacetime.
-- This is the industrial grade production system that can produce both Matter-Antimatter Annihilation-Fuel (as piped resource) and Darkfusion-Fuel (as contained fuel cells).

-- AN-Fuel production is simple constant resource provision. Constantly consumes gigawatts of power and money because it imports large amount of hydrogen.
-- DF-Fuel production is more complicated. Enriches DF-Fuel cells. Requires inserted inactive fuel cell, electrical power and dark plasma power from nodes.
-- Production mechanics:
    -- Sustaining: Will be based on machine power and stress and waste heat management (This is connected to auxiliary thermal plant as well).
    -- Stat Manipulation: Presence of Fissile Booster in the special receptacle.

-- DF-Fuel production (XIT Cycle, Xen-Induced Transvacuum Cycle) Intended for creating first DF-Fuel cells or when dark plasma is unavailable, 
-- This mode this creates twice as much stress and ten-fold the electrical power consumption.
-- Requires strictly Fissile Xen Crystal RBMK Rods as Fission Booster to facilitate initial dark plasma generation.

-- System can work in one production mode at a time.

-- It have 2 receptacles, one for Darkfusion Fuelcell and one for Fission Booster.
-- Fission Booster are L-RBMK Fuel Rods. It will read the fuel stat and adapts them into production mechanic.
-- What attributes affects what are to be discussed later.