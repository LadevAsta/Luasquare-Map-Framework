DFR = DFR or {}
DFR.DirectorBeam = DFR.DirectorBeam or {}

-- Dark-Plasma Director Beam
-- This is the beam that can transfer photon energy and dark plasma from below to above.
-- Dark-Plasma Director Beam system is the kilometers-tall 'spinal cord' of the citadel and will constantly generate waste heat after entering Annihilation Stage.
-- It bring energy into core's influx, and receives energy from core's outflux AND a Dark Plasma Node that is used as feedback for the director beam itself.
-- After the reactor core, along the length of the Director Beam, there will be multiple Dark Plasma Turbines and Dark Plasma Nodes.
-- Dark Plasma Turbines generates conventional electricity for citadel's own demand and the excess will be exported as electrical power.
-- Dark Plasma Nodes acts as provider node for other systems that want to use Dark Plasma as energy.

local function clamp(value, minValue, maxValue)
    if math.Clamp then return math.Clamp(value, minValue, maxValue) end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

function DFR.ResetDirectorBeam()
    DFR.DirectorBeam.State = {
        active = false,
        precisionPercent = 0,
        imprecisionPercent = 100,
        lensXOffset = 0.5,
        lensYOffset = 0.5,
        lensZOffset = 0.5
    }
end

function DFR.GetDirectorBeamState()
    return DFR.DirectorBeam.State
end

function DFR.UpdateDirectorBeamPrecision()
    local state = DFR.DirectorBeam.State
    local dx = math.abs((state.lensXOffset or 0.5) - 0.5)
    local dy = math.abs((state.lensYOffset or 0.5) - 0.5)
    local dz = math.abs((state.lensZOffset or 0.5) - 0.5)
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local imprecision = clamp(distance / math.sqrt(0.5 * 0.5 * 3) * 100, 0, 100)
    state.imprecisionPercent = imprecision
    state.precisionPercent = 100 - imprecision
    return state.precisionPercent
end

function DFR.SetDirectorBeamActive(active)
    local stabilizer = DFR.Stabilizer and DFR.Stabilizer.State or {}
    if active and not stabilizer.active then
        DFR.Log('Director beam rejected: stabilizer is offline')
        return false
    end
    local state = DFR.DirectorBeam.State
    state.active = active and true or false
    DFR.UpdateDirectorBeamPrecision()
    if DFR.SetCoreBeamActive then DFR.SetCoreBeamActive('director', state.active) end
    if DFR.SetDirectorLensMachineryActive then DFR.SetDirectorLensMachineryActive(state.active) end
    DFR.Log('Director beam ' .. (state.active and 'active' or 'offline'))
    return true
end

function DFR.AdjustLens(axis, delta)
    local state = DFR.DirectorBeam.State
    axis = tostring(axis or ''):lower()
    local key = axis == 'x' and 'lensXOffset'
        or (axis == 'y' and 'lensYOffset' or (axis == 'z' and 'lensZOffset' or nil))
    if not key then return false end
    state[key] = clamp((state[key] or 0.5) + (tonumber(delta) or 0), 0, 1)
    DFR.UpdateDirectorBeamPrecision()
    DFR.Log(string.format(
        'Lens %s %.3f precision %.1f%%',
        string.upper(axis), state[key], state.precisionPercent or 0
    ))
    return true
end

function DFR.TickDirectorBeam(dt)
    local state = DFR.DirectorBeam.State
    if state.active then
        local drift = DFR.Config.DirectorBeamAutoDriftPerSecond or 0
        local now = DFR.GetTime()
        state.lensXOffset = clamp((state.lensXOffset or 0.5) + math.sin(now * 0.17) * drift * dt, 0, 1)
        state.lensYOffset = clamp((state.lensYOffset or 0.5) + math.sin(now * 0.23) * drift * dt, 0, 1)
        state.lensZOffset = clamp((state.lensZOffset or 0.5) + math.sin(now * 0.31) * drift * dt, 0, 1)
    end
    DFR.UpdateDirectorBeamPrecision()
end

DFR.ResetDirectorBeam()
