RBMK = RBMK or {}

function RBMK.DoSteamStep()
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type ~= RBMK.CELL_STEAM then continue end
            if cell.heat <= 100 then continue end
            if RBMK.Water <= 0 then continue end
            -- Heat above boiling
            local excessHeat = cell.heat - 100
            -- Cooling capability
            local cooling = excessHeat * (cell.coolingRate or 0.05)
            -- Water needed
            local waterNeeded = cooling * (cell.waterUseRate or 0.01)
            -- Clamp by available water
            local waterUsed = math.min(waterNeeded, RBMK.Water)
            -- Dryout scaling
            local scale = 1
            if waterNeeded > 0 then scale = waterUsed / waterNeeded end
            cooling = cooling * scale
            -- Steam production
            local steamMade = waterUsed * 1600
            -- Steam capacity clamp
            local freeSteam = RBMK.MaxSteam - RBMK.Steam
            if steamMade > freeSteam then
                steamMade = freeSteam
                waterUsed = steamMade / 1600
                cooling = cooling * (steamMade / math.max(steamMade, 0.0001))
            end

            -- Apply
            cell.heat = cell.heat - cooling
            RBMK.Water = RBMK.Water - waterUsed
            RBMK.Steam = RBMK.Steam + steamMade
        end
    end
end