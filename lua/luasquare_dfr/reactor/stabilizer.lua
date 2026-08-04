DFR = DFR or {}
DFR.Stabilizer = DFR.Stabilizer or {}

local function clamp(value, minValue, maxValue)
    if math.Clamp then return math.Clamp(value, minValue, maxValue) end
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function moveTowards(value, target, amount)
    if value < target then return math.min(value + amount, target) end
    return math.max(value - amount, target)
end

local function smoothstep(value)
    value = clamp(value, 0, 1)
    return value * value * (3 - 2 * value)
end

function DFR.ResetStabilizer()
    DFR.Stabilizer.State = {
        active = false,
        requested = false,
        powerGW = 0,
        fieldStrengthPercent = 0,
        fieldStabilityPercent = 0
    }
end

function DFR.GetStabilizerState()
    return DFR.Stabilizer.State
end

function DFR.SetStabilizerActive(active)
    active = active and true or false
    local state = DFR.Stabilizer.State
    if active then
        if DFR.IsReactorMachineDeployed and not DFR.IsReactorMachineDeployed() then
            DFR.Log('Stabilizer rejected: reactor machinery is not fully deployed')
            return false
        end
        local ok = DFR.StartReactorMachineTimeline
            and DFR.StartReactorMachineTimeline('stabilizer_warmup', {})
        if ok == false then
            DFR.Log('Stabilizer rejected: machinery warm-up could not start')
            return false
        end
        state.active = true
        state.requested = true
    else
        state.active = false
        state.requested = false
        if DFR.DirectorBeam and DFR.DirectorBeam.State.active then DFR.SetDirectorBeamActive(false) end
        if DFR.StartReactorMachineTimeline then
            DFR.StartReactorMachineTimeline('stabilizer_shutdown', {})
        end
    end
    DFR.Log('Stabilizer ' .. (state.active and 'active' or 'offline'))
    return true
end

function DFR.AdjustContainmentField(deltaPercent)
    local state = DFR.Stabilizer.State
    if not state.active then
        DFR.Log('Containment command rejected: stabilizer is offline')
        return false
    end
    local limit = DFR.Config.ContainmentFieldStartupLimitPercent or 35
    state.fieldStrengthPercent = clamp(
        (state.fieldStrengthPercent or 0) + (tonumber(deltaPercent) or 0), 0, limit
    )
    DFR.Log(string.format('Containment field %.1f%%', state.fieldStrengthPercent))
    return true
end

function DFR.TickStabilizer(dt)
    local state = DFR.Stabilizer.State
    local maximumPower = DFR.Config.StabilizerStartupPowerGW or 8
    local targetPower = state.requested and maximumPower or 0
    local rampSeconds = state.requested
        and (DFR.Config.StabilizerRampUpSeconds or 5)
        or (DFR.Config.StabilizerRampDownSeconds or 3)
    state.powerGW = moveTowards(
        state.powerGW or 0,
        targetPower,
        maximumPower / math.max(rampSeconds, 0.01) * dt
    )

    local fraction = maximumPower > 0 and state.powerGW / maximumPower or 0
    local threshold = clamp(DFR.Config.CoreFormationThresholdFraction or 0.15, 0, 0.99)
    local inflation = smoothstep((fraction - threshold) / (1 - threshold))
    local sphereRadius = (DFR.Config.StartupCoreSphereRadiusMeters or 2.6) * inflation
    local shieldRadius = (DFR.Config.StartupCoreShieldRadiusMeters or 3.0) * inflation
    if DFR.SetCoreVisualTargets then
        if DFR.CoreState then DFR.CoreState.preset = 'manual_startup_dynamic' end
        DFR.SetCoreVisualTargets({
            core_sphere = sphereRadius,
            core_stellar = 0,
            core_blackhole = 0,
            core_shield = shieldRadius,
            shieldVisible = shieldRadius > 0
        }, math.min(math.max(dt * 1.5, 0.05), 0.25))
    end

    if state.active then
        local target = state.fieldStrengthPercent or 0
        local stability = state.fieldStabilityPercent or 0
        local rate = target > stability and 8 or 4
        state.fieldStabilityPercent = moveTowards(stability, target, rate * dt)
    else
        state.fieldStabilityPercent = math.max((state.fieldStabilityPercent or 0) - 10 * dt, 0)
    end
end

DFR.ResetStabilizer()
