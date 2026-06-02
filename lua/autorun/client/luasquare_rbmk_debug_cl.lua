RBMK = RBMK or {}
RBMK.Debug = RBMK.Debug or {}
RBMK.Debug.ClientState = {
    Cells = {},
    FluxLines = {},
    VesselInfo = {}
}

local DEBUG_WIRE_VERSION = 2
local DEBUG_PACKET_VESSEL = 1
local DEBUG_PACKET_CELLS = 2
local DEBUG_PACKET_FLUX = 3
local DEBUG_PACKET_END = 4

local function emptyClientState()
    return {
        Cells = {},
        FluxLines = {},
        VesselInfo = {}
    }
end

local function readOptionalString()
    if not net.ReadBool() then return nil end
    return net.ReadString()
end

local function readPoint()
    if not net.ReadBool() then return nil end
    return {
        x = net.ReadUInt(16),
        y = net.ReadUInt(16)
    }
end

local function readVesselInfo()
    return {
        worldOrigin = net.ReadVector(),
        cellSpacing = net.ReadFloat(),
        cellSymbols = RBMK.CellSymbols,
        model = net.ReadString(),
        averageHeat = net.ReadFloat(),
        maxHeat = net.ReadFloat(),
        totalFlux = net.ReadFloat(),
        averageXenon = net.ReadFloat(),
        lastThermalMW = net.ReadFloat(),
        lastFlashBoilMW = net.ReadFloat(),
        lastSteamGenerated = net.ReadFloat(),
        lastFlashSteamGenerated = net.ReadFloat(),
        autoRegulatorEnabled = net.ReadBool(),
        autoRegulatorUsePID = net.ReadBool(),
        autoRegulatorTargetMW = net.ReadFloat(),
        autoRegulatorTargetInsertion = net.ReadFloat(),
        autoRegulatorLastError = net.ReadFloat(),
        controlRodPowerGrid = readOptionalString(),
        controlRodPowerBreaker = readOptionalString(),
        controlRodPowerDemandMW = net.ReadFloat(),
        controlRodPowerAcceptedMW = net.ReadFloat(),
        controlRodPowered = net.ReadBool(),
        controlRodMovingCount = net.ReadUInt(16),
        controlRodBlockedCount = net.ReadUInt(16),
        controlRodStuckCount = net.ReadUInt(16),
        integrityScore = net.ReadFloat(),
        integrityDamage = net.ReadFloat(),
        integrityLastDamage = net.ReadFloat(),
        integrityLastDamageReason = readOptionalString(),
        waterTemperature = net.ReadFloat(),
        steamTemperature = net.ReadFloat(),
        boilingTemperature = net.ReadFloat(),
        coolingEfficiency = net.ReadFloat(),
        water = net.ReadFloat(),
        maxWater = net.ReadFloat(),
        steam = net.ReadFloat(),
        maxSteam = net.ReadFloat(),
        hardMaxSteam = net.ReadFloat(),
        totalVolume = net.ReadFloat(),
        steamSpace = net.ReadFloat(),
        minSteamSpace = net.ReadFloat(),
        rpvPressure = net.ReadFloat(),
        pressureUnit = net.ReadString(),
        steamOutletOpen = net.ReadBool(),
        feedwaterInletOpen = net.ReadBool(),
        drainValveOpen = net.ReadBool(),
        lastSteamExportFlow = net.ReadFloat(),
        lastDrainFlow = net.ReadFloat(),
        blowoutPressure = net.ReadFloat(),
        catastrophicPressure = net.ReadFloat(),
        eventFailed = net.ReadBool(),
        failureReason = readOptionalString(),
        lastBlowoutSteamLoss = net.ReadFloat(),
        lastBlowoutPressure = net.ReadFloat(),
        lastBlowoutValve = readOptionalString(),
        lastBlowoutCount = net.ReadUInt(16),
        lastBlowoutDuration = net.ReadFloat(),
        blowoutEnabled = net.ReadBool(),
        blowoutValveCount = net.ReadUInt(16),
        lastFuelLeak = readPoint(),
        lastMeltdown = readPoint()
    }
end

local function readCell()
    local cell = {
        x = net.ReadUInt(16),
        y = net.ReadUInt(16),
        type = net.ReadUInt(4),
        heat = net.ReadFloat()
    }
    cell.symbol = RBMK.CellSymbols[cell.type] or '?'

    if cell.type == RBMK.CELL_FUEL then
        cell.fuelType = net.ReadString()
        cell.skinHeat = net.ReadFloat()
        cell.coreHeat = net.ReadFloat()
        cell.flux = net.ReadFloat()
        cell.lastFlux = net.ReadFloat()
        cell.xenon = net.ReadFloat()
        cell.leaking = net.ReadBool()
        cell.meltingDown = net.ReadBool()
    elseif cell.type == RBMK.CELL_CONTROL then
        cell.name = net.ReadString()
        cell.group = net.ReadString()
        cell.insertion = net.ReadFloat()
        cell.targetInsertion = net.ReadFloat()
        cell.lastInsertion = net.ReadFloat()
        cell.inserting = net.ReadBool()
        cell.stationaryTime = net.ReadFloat()
        cell.movingTime = net.ReadFloat()
        cell.moveSpeed = net.ReadFloat()
        cell.autoRegulator = net.ReadBool()
        cell.autoInsertion = net.ReadFloat()
        cell.autoTargetInsertion = net.ReadFloat()
        cell.autoMaxInsertion = net.ReadFloat()
        cell.graphiteTip = net.ReadBool()
        cell.reflector = net.ReadBool()
        cell.visualEnt = net.ReadEntity()
        cell.powerBlocked = net.ReadBool()
        cell.stuck = net.ReadBool()
        cell.scramStuck = net.ReadBool()
        cell.scramStuckPending = net.ReadBool()
        cell.stuckInsertion = net.ReadFloat()
        cell.lastStuckReason = readOptionalString()
    elseif cell.type == RBMK.CELL_REFLECTOR then
        cell.reflectorIn = net.ReadBool()
    elseif cell.type == RBMK.CELL_SOURCE then
        cell.flux = net.ReadFloat()
        cell.lastFlux = net.ReadFloat()
        cell.sourceStrength = net.ReadFloat()
        cell.closedSource = net.ReadBool()
    end

    return cell
end

local function readFluxLine()
    return {
        start = net.ReadVector(),
        finish = net.ReadVector(),
        flux = net.ReadFloat(),
        dx = net.ReadInt(4),
        dy = net.ReadInt(4)
    }
end

function RBMK.Debug.ReceiveStatePacket()
    local version = net.ReadUInt(8)
    if version ~= DEBUG_WIRE_VERSION then return end

    local packetType = net.ReadUInt(4)
    local sequence = net.ReadUInt(16)

    if packetType == DEBUG_PACKET_VESSEL then
        RBMK.Debug.PendingState = emptyClientState()
        RBMK.Debug.PendingState.Sequence = sequence
        RBMK.Debug.PendingState.VesselInfo = readVesselInfo()
        return
    end

    local pending = RBMK.Debug.PendingState
    if not pending or pending.Sequence ~= sequence then return end

    if packetType == DEBUG_PACKET_CELLS then
        local count = net.ReadUInt(16)
        for _ = 1, count do
            table.insert(pending.Cells, readCell())
        end
    elseif packetType == DEBUG_PACKET_FLUX then
        local count = net.ReadUInt(16)
        for _ = 1, count do
            table.insert(pending.FluxLines, readFluxLine())
        end
    elseif packetType == DEBUG_PACKET_END then
        RBMK.Debug.ClientState = pending
        RBMK.Debug.PendingState = nil
    end
end

RBMK.CELL_FUEL = RBMK.CELL_FUEL or 1
RBMK.CELL_STEAM = RBMK.CELL_STEAM or 2
RBMK.CELL_CONTROL = RBMK.CELL_CONTROL or 3
RBMK.CELL_REFLECTOR = RBMK.CELL_REFLECTOR or 4
RBMK.CELL_BLANK = RBMK.CELL_BLANK or 5
RBMK.CELL_AUTOROD = RBMK.CELL_AUTOROD or 6
RBMK.CELL_SOURCE = RBMK.CELL_SOURCE or 7
RBMK.CELL_ABSORBER = RBMK.CELL_ABSORBER or 8
RBMK.CELL_VOID = RBMK.CELL_VOID or 9

RBMK.CellSymbols = RBMK.CellSymbols or {
    [RBMK.CELL_BLANK] = 'B',
    [RBMK.CELL_FUEL] = 'F',
    [RBMK.CELL_STEAM] = 'S',
    [RBMK.CELL_CONTROL] = 'C',
    [RBMK.CELL_REFLECTOR] = 'RF',
    [RBMK.CELL_AUTOROD] = 'CA',
    [RBMK.CELL_SOURCE] = 'NS',
    [RBMK.CELL_ABSORBER] = 'AB',
    [RBMK.CELL_VOID] = 'X'
}

RBMK.Debug.CellFilterSettings = {
    [RBMK.CELL_BLANK] = {'show_blank', false},
    [RBMK.CELL_FUEL] = {'show_fuel', true},
    [RBMK.CELL_STEAM] = {'show_steam', true},
    [RBMK.CELL_CONTROL] = {'show_control', true},
    [RBMK.CELL_AUTOROD] = {'show_autorod', true},
    [RBMK.CELL_REFLECTOR] = {'show_reflector', true},
    [RBMK.CELL_ABSORBER] = {'show_absorber', true},
    [RBMK.CELL_SOURCE] = {'show_neutronsource', true}
}

-- Client Debug module
timer.Simple(10, function()
    if not GetGlobal2Bool('LUASQUARE_FRAMEWORK_INITIALIZED_GLOBAL', false) then
        print('[Luasquare RBMK Debug Client] No RBMK detected after 10 seconds, terminating')
        return
    end

    net.Receive('RBMK_DebugState', function()
        RBMK = RBMK or {}
        RBMK.Debug = RBMK.Debug or {}
        RBMK.Debug.ReceiveStatePacket()
    end)

    hook.Add('PostDrawTranslucentRenderables', 'luasquareRBMK_DebugRender', function()
        if not RBMK.Debug then return end
        if not RBMK.Debug.ClientState then return end
        RBMK.Debug.RenderCells()
        RBMK.Debug.RenderFluxLines()
        RBMK.Debug.RenderVesselInfo()
    end)
    print('[Luasquare RBMK Debug Client] Client initialized')
end)

function RBMK.Debug.GetSetting(name, default)
    local cvar = GetConVar('luasquare_rbmk_' .. name)
    if not cvar then return default end
    return cvar:GetBool()
end

function RBMK.Debug.GetSettingNumber(name, default)
    local cvar = GetConVar('luasquare_rbmk_' .. name)
    if not cvar then return default end
    return cvar:GetFloat()
end

function RBMK.Debug.ShouldRenderPos(pos)
    if not pos then return false end
    local ply = LocalPlayer()
    if not IsValid(ply) then return true end

    local eye = ply:EyePos()
    local maxDistance = RBMK.Debug.GetSettingNumber('debug_maxdistance', 2500)
    if maxDistance > 0 and eye:DistToSqr(pos) > maxDistance * maxDistance then return false end

    if RBMK.Debug.GetSetting('debug_fovcheck', true) then
        local toTarget = pos - eye
        if toTarget:LengthSqr() > 1 then
            toTarget:Normalize()
            local fov = ply.GetFOV and ply:GetFOV() or 90
            local threshold = math.cos(math.rad(math.Clamp(fov * 0.5 + 20, 1, 120)))
            if ply:EyeAngles():Forward():Dot(toTarget) < threshold then return false end
        end
    end

    return true
end

function RBMK.Debug.GetCellWorldPos(x, y)
    if RBMK.CellToWorld then
        return RBMK.CellToWorld(x, y)
    end

    local info = RBMK.Debug.ClientState.VesselInfo or {}
    local origin = info.worldOrigin or Vector(0, 0, 0)
    local spacing = info.cellSpacing or 64
    return origin + Vector((x - 1) * spacing, (y - 1) * spacing, 0)
end

function RBMK.Debug.DrawWorldText(pos, text, color, sizeOverride)
    if not RBMK.Debug.ShouldRenderPos(pos) then return end
    sizeOverride = sizeOverride or RBMK.Debug.GetSettingNumber('debug_textscale', 1.0)
    cam.Start3D2D(pos, Angle(0, LocalPlayer():EyeAngles().y - 90, 90), sizeOverride)
    draw.SimpleTextOutlined(text, 'DermaDefault', -10, 0, color or color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1.2, color_black)
    cam.End3D2D()
end

function RBMK.Debug.ShouldRenderCell(cell)
    if not cell or cell.type == RBMK.CELL_VOID then return false end
    local filter = RBMK.Debug.CellFilterSettings[cell.type]
    if not filter then return true end
    return RBMK.Debug.GetSetting(filter[1], filter[2])
end

function RBMK.Debug.RenderCell(x, y, cell)
    if not RBMK.Debug.ShouldRenderCell(cell) then return end
    local pos = RBMK.Debug.GetCellWorldPos(x, y)
    if not RBMK.Debug.ShouldRenderPos(pos) then return end
    local lines = {}
    local symbol = RBMK.CellSymbols[cell.type] or '?'
    table.insert(lines, symbol)
    table.insert(lines, string.format('H: %.1f', cell.heat or 0))
    if cell.type == RBMK.CELL_FUEL then
        table.insert(lines, string.format('sH: %.1f', cell.skinHeat or 0))
        table.insert(lines, string.format('cH: %.1f', cell.coreHeat or 0))
        table.insert(lines, tostring(cell.fuelType or '???'))
        table.insert(lines, string.format('F: %.1f', cell.flux or 0))
        table.insert(lines, string.format('X: %.1f', cell.xenon or 0))
        if cell.leaking then table.insert(lines, 'LEAK') end
        if cell.meltingDown then table.insert(lines, 'MELT') end
    elseif cell.type == RBMK.CELL_CONTROL then
        table.insert(lines, string.format('%s', cell.name or '???'))
        table.insert(lines, string.format('I: %.2f', cell.insertion or 0))
        table.insert(lines, string.format('> %.2f', cell.targetInsertion or 0))
        if cell.autoRegulator then
            table.insert(lines, string.format('A: %.3f', cell.autoInsertion or 0))
        end
        if cell.powerBlocked then table.insert(lines, 'NO PWR') end
        if cell.stuck then table.insert(lines, 'STUCK') end
        if cell.scramStuckPending then table.insert(lines, 'SPIKE') end
    elseif cell.type == RBMK.CELL_REFLECTOR then
        table.insert(lines, string.format('RE: %s', tostring(cell.reflectorIn)))
    elseif cell.type == RBMK.CELL_SOURCE then
        table.insert(lines, string.format('SRC: %.1f', cell.sourceStrength or 0))
        table.insert(lines, string.format('CLS: %s', tostring(cell.closedSource)))
    end

    local text = table.concat(lines, ' ')
    cam.Start3D2D(pos + Vector(0, 0, 20), Angle(0, LocalPlayer():EyeAngles().y - 90, 90), RBMK.Debug.GetSettingNumber('debug_textscale_cell', 1.0))
    draw.SimpleTextOutlined(text, 'DermaDefault', 0, 0, color_white, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
    draw.SimpleTextOutlined(string.format('[ %d,%d ]', x, y), 'DermaDefault', 0, -20, Color(255, 255, 0), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER, 1, color_black)
    cam.End3D2D()
end

function RBMK.Debug.RenderCells()
    if not RBMK.Debug.GetSetting('debug_enabled', true) then return end
    local state = RBMK.Debug.ClientState
    if not state.Cells then return end
    for _, cell in ipairs(state.Cells) do
        RBMK.Debug.RenderCell(cell.x, cell.y, cell)
    end
end

function RBMK.Debug.RenderFluxLines()
    if not RBMK.Debug.GetSetting('debug_enabled', true) then return end
    if not RBMK.Debug.GetSetting('draw_flux_rays', true)  then return end
    local state = RBMK.Debug.ClientState
    if not state.FluxLines then return end
    render.SetColorMaterial()
    for _, line in ipairs(state.FluxLines) do
        if line.flux >= 0.05 then
            local offset = Vector(0, 0, 0)
            local color = Color(0, 255, 0)
            -- HORIZONTAL
            if line.dx ~= 0 then
                -- East
                if line.dx > 0 then
                    offset = Vector(0, 6, 0)
                    color = Color(0, 255, 0)
                end

                -- West
                if line.dx < 0 then
                    offset = Vector(0, -6, 0)
                    color = Color(0, 167, 0)
                end
            end

            -- VERTICAL
            if line.dy ~= 0 then
                -- North
                if line.dy > 0 then
                    offset = Vector(-6, 0, 0)
                    color = Color(0, 255, 0)
                end

                -- South
                if line.dy < 0 then
                    offset = Vector(6, 0, 0)
                    color = Color(0, 167, 0)
                end
            end

            local startPos = line.start + offset
            local endPos = line.finish + offset
            if RBMK.Debug.ShouldRenderPos((startPos + endPos) * 0.5) then
                -- MAIN LINE
                render.DrawLine(startPos, endPos, color, true)
                -- ARROW
                local arrowDir = endPos - startPos
                arrowDir:Normalize()
                local back = arrowDir * -6
                local right = Vector(-arrowDir.y, arrowDir.x, 0)
                local arrowA = endPos + back + right * 3
                render.DrawLine(endPos, arrowA, color, true)
                -- FLUX TEXT
                local textPos = arrowA + offset * 0.5 + Vector(0, 0, -4)
                RBMK.Debug.DrawWorldText(textPos, string.format('%.1f', line.flux), color, RBMK.Debug.GetSettingNumber('debug_textscale_flux', 0.3))
            end
        end
    end
end

function RBMK.Debug.RenderVesselInfo()
    if not RBMK.Debug.GetSetting('debug_enabled', true) then return end
    local info = RBMK.Debug.ClientState.VesselInfo
    if not info then return end
    local origin = info.worldOrigin or Vector(0, 0, 0)
    local basePos = origin + Vector(0, 0, 128)
    if not RBMK.Debug.ShouldRenderPos(basePos) then return end
    local lines = {'MODEL: ' .. tostring(info.model),
    string.format('AVG H: %.1f', info.averageHeat or 0),
    string.format('MAX H: %.1f', info.maxHeat or 0),
    string.format('MWt: %.2f', info.lastThermalMW or 0),
    string.format('FLASH MW: %.2f', info.lastFlashBoilMW or 0),
    string.format('APR: %s %s %.1fMW %.3f', tostring(info.autoRegulatorEnabled), info.autoRegulatorUsePID and 'PID' or 'P', info.autoRegulatorTargetMW or 0, info.autoRegulatorTargetInsertion or 0),
    string.format('ROD PWR: %s %.3f/%.3fMW M%d B%d S%d', tostring(info.controlRodPowered), info.controlRodPowerAcceptedMW or 0, info.controlRodPowerDemandMW or 0, info.controlRodMovingCount or 0, info.controlRodBlockedCount or 0, info.controlRodStuckCount or 0),
    string.format('INTEGRITY: %.1f%% DMG %.3f %s', (info.integrityScore or 1) * 100, info.integrityLastDamage or 0, tostring(info.integrityLastDamageReason or '')),
    string.format('FLUX: %.1f', info.totalFlux or 0),
    string.format('XENON: %.1f', info.averageXenon or 0),
    string.format('--------------------------------'),
    string.format('WATER: %.1f / %.1f', info.water or 0, info.maxWater or 0),
    string.format('W TEMP: %.1f C / BOIL %.1f C', info.waterTemperature or 0, info.boilingTemperature or 0),
    string.format('STEAM: %.1f / %.1f', info.steam or 0, info.maxSteam or 0),
    string.format('GEN: %.1f/s FLASH %.1f/s', (info.lastSteamGenerated or 0) / math.max(RBMK.TickInterval or 0.1, 0.0001), (info.lastFlashSteamGenerated or 0) / math.max(RBMK.TickInterval or 0.1, 0.0001)),
    string.format('S TEMP: %.1f C / COOL %.2f', info.steamTemperature or 0, info.coolingEfficiency or 0),
    string.format('SPACE: %.1f / %.1f', info.steamSpace or 0, info.totalVolume or 0),
    string.format('RPV P: %.1f %s', info.rpvPressure or 0, info.pressureUnit or 'bar'),
    string.format('OUT: %s %.1f/s', tostring(info.steamOutletOpen), info.lastSteamExportFlow or 0),
    string.format('--------------------------------'),
    string.format('IN/DRAIN: %s / %s %.1f/s', tostring(info.feedwaterInletOpen), tostring(info.drainValveOpen), info.lastDrainFlow or 0),
    string.format('BLOWOUT: %s [%d]', tostring(info.blowoutEnabled), info.blowoutValveCount or 0),
    string.format('BLOW/CATA: %.1f / %.1f', info.blowoutPressure or 0, info.catastrophicPressure or 0)}
    if info.lastBlowoutSteamLoss and info.lastBlowoutSteamLoss > 0 then
        table.insert(lines, string.format('LAST BLOW: x%d %.1f @ %.1f %.1fs', info.lastBlowoutCount or 0, info.lastBlowoutSteamLoss or 0, info.lastBlowoutPressure or 0, info.lastBlowoutDuration or 0))
        table.insert(lines, string.format('BLOW COLS: %s', tostring(info.lastBlowoutValve or '?')))
    end
    if info.lastFuelLeak then table.insert(lines, string.format('LEAK: %d,%d', info.lastFuelLeak.x or 0, info.lastFuelLeak.y or 0)) end
    if info.lastMeltdown then table.insert(lines, string.format('MELT: %d,%d', info.lastMeltdown.x or 0, info.lastMeltdown.y or 0)) end
    if info.eventFailed then table.insert(lines, 'FAILED: ' .. tostring(info.failureReason or 'unknown')) end
    for i, line in ipairs(lines) do
        local pos = basePos + Vector(0, 0, -(i - 1) * 8)
        RBMK.Debug.DrawWorldText(pos, line, Color(0, 255, 255))
    end
end
