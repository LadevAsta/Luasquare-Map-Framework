-- This is where operator point (money) is spent.
-- The money is one shared pool called facility balance.
-- It may be used with existing in-map trains.

-- It is used to acquire some resources such as inactive dark fusion fuel cells, RBMK Fuel rods and other.
-- Some item are progress-mandatory, so it will allow ordering if shared facility's balance is not enough and but rather that in negative. This is to prevent soft-lock.

-- Workflow
    -- 1. Player select item from 3D2D displaying catalog.
    -- 2. Selected items are put into orders, can be more than one.
    -- 3. If this is multiplayer, at least 51% of the player in the server must agree to this order before confirming payment, then lock the display and call func_tracktrain to move.
    -- 4. This func_tracktrain should be the one to callback to this module. This callback would tell the module to start spawning item at defined position.
    -- 5. This module spawns SENTs (or collectible SWEPs) in sequence (1 spawn per second)
    -- 6. When spawn is finished, callback to func_tracktrain to move again.
    -- 7. The func_tracktrain should move to its resting point and callback to this module telling it that it has returned, this module would start cooldown before next order can be placed.

-- As for 3D2D display for catalog. We might have to expand 3D2D to somehow have input detection, scrollbar, multiple tab or pages.