RBMK = RBMK or {}

function RBMK.DoSteamStep()
    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type == RBMK.CELL_STEAM and cell.heat > 100 and RBMK.Water > 0 then
                local removable = math.min(cell.heat - 100, RBMK.Water)
                cell.heat = cell.heat - removable
                RBMK.Water = RBMK.Water - removable
                RBMK.Steam = RBMK.Steam + removable * 1600
            end
        end
    end
end