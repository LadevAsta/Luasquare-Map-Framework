-- This is scripted entity (SENT) for Dark Fusion Fuel Cell and other cell types.
-- They appears as a physics prop.

-- Dark-Fusion Fuel Cell (DF-Fuel Cell)
-- Exotic matter required in Annihilation-Catalyzed Dark Fusion Reactor, mainly used in extreme environment that is the Antimatter Reactor Core to generate and feed a singularity.
-- Attributes
    -- Yield - Current yield, Reactor catalyzers will take this value away when they work to transfer fuel into the core.
    -- maxYield (varies)
    -- Enrichment (0-100%) - how much fuel is left (Yield in percentage)
    -- Purity - (0-100%) - Integrity of non-standard spacetime inside the cell. Purity below 50% is considered impure and fails to excite.
    -- Purity Half-life (10 minutes - 8 hours) - The time it takes to reduce purity to half the current amount.
    -- Reactivity (multiplier 0.8-5.0) - the power multiplier it tells reactor and catalyzers.
    -- Excited (True/False) - Whether or not the cell is excited in fuel receptacle. If it is, pause purity loss.
    -- Explosion power (Source explosive Magnitude?) - How strong the explosion will be if the cell is destroyed.

-- Meta-Positive Stasis Cell (Stasis Cell)
-- Exotic matter required during meltdown stage 2 for emergency reactor purge.
-- Special cell, no attributes.
-- Brought from delivery system.