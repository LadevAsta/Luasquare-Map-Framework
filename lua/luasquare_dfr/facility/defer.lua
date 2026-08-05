-- Deranged Energy Fuel Enrichment Reactor
-- (Industrial Particle Accelerator & Negative Energy Reactor)
-- This is the production system that can produce both AN-Fuel and DF-Fuel cells.

-- AN-Fuel production is simple constant resource provision. Constantly consumes gigawatts of power and money because it imports large amount of hydrogen.
-- DF-Fuel production is more complicated. Enriches DF-Fuel cells.
-- Production mechanics:
    -- Sustaining: Will be based on machine power and stress and heat management (This is connected to auxiliary thermal plant as well).
    -- Stat Manipulation: Presence of Fissile Booster in the special receptacle.

-- DEFER can work in one production mode at a time.

-- It have 2 receptacles, one for Darkfusion Fuelcell and one for Fission Booster.
-- Fission Booster is RBMK Fuel Rod. It will read the fuel stat and adapts them into production mechanic.
-- What attributes affects what are to be discussed later.