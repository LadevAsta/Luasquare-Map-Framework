RBMK = RBMK or {}
-- 8-direction offsets
local dirs8 = {{-1, -1}, {0, -1}, {1, -1}, {-1, 0}, {1, 0}, {-1, 1}, {0, 1}, {1, 1}}
-- Delta buffer
function RBMK.DoHeatStep()
    local delta = {}
    for x = 1, RBMK.Width do
        delta[x] = {}
        for y = 1, RBMK.Height do
            delta[x][y] = 0
        end
    end

    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            for _, dir in ipairs(dirs8) do
                local nx = x + dir[1]
                local ny = y + dir[2]
                local other = RBMK.GetCell(nx, ny)
                if other and cell.type ~= RBMK.CELL_VOID and other.type ~= RBMK.CELL_VOID then
                    local diff = cell.heat - other.heat
                    local transfer = diff * RBMK.RPVHeatDiffusion
                    delta[x][y] = delta[x][y] - transfer
                    delta[nx][ny] = delta[nx][ny] + transfer
                end
            end
        end
    end

    for x = 1, RBMK.Width do
        for y = 1, RBMK.Height do
            local cell = RBMK.Matrix[x][y]
            if cell.type ~= RBMK.CELL_VOID then cell.heat = cell.heat + delta[x][y] end
        end
    end
end