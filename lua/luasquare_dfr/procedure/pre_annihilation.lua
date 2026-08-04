DFR = DFR or {}
DFR.PreAnnihilation = DFR.PreAnnihilation or {}

local TIMELINE_NAME = 'run'
local LOCK_OWNER = 'timeline:pre_annihilation'
local CONFLICTING_CONTROLS = {
    'stabilizer_enable',
    'stabilizer_disable',
    'containment_raise',
    'containment_lower',
    'director_beam_enable',
    'director_beam_disable',
    'lens_x_plus',
    'lens_x_minus',
    'lens_y_plus',
    'lens_y_minus',
    'lens_z_plus',
    'lens_z_minus',
    'pre_annihilation_begin'
}

local function stabilizerArmsResolve()
    for i = 1, 4 do
        if not DFR.ResolveBinding('stabilizer_arm_' .. i) then return false end
    end
    return true
end

local function availableCatalyzers()
    local ids = {}
    for id = 1, 6 do
        if DFR.IsCatalyzerAvailable(id) then table.insert(ids, id) end
    end
    return ids
end

local function lockConflictingControls()
    for _, id in ipairs(CONFLICTING_CONTROLS) do
        DFR.LockControl(id, LOCK_OWNER, 'pre-annihilation procedure active')
    end
end

local function healthyCatalyzerChildren(instance)
    local count = 0
    for _, child in ipairs(instance.children or {}) do
        if child.metadata and child.metadata.role == 'catalyzer'
            and child.status ~= 'failed' and child.status ~= 'cancelled' then
            count = count + 1
        end
    end
    return count
end

local function cleanupPresentation()
    if DFR.CancelCoreVisualPulse then
        DFR.CancelCoreVisualPulse('core_sphere', 0.25)
        DFR.CancelCoreVisualPulse('core_shield', 0.25)
    end
    DFR.PreAnnihilation.Phase = nil
    DFR.PreAnnihilation.Actor = nil
    if DFR.SetCoreBeamActive then DFR.SetCoreBeamActive('annihilation', false) end
end

function DFR.GetPreAnnihilationUnavailableReason()
    if DFR.GetState() ~= DFR.STATE_MANUAL_STARTUP then return 'manual startup state required' end
    local stabilizer = DFR.Stabilizer and DFR.Stabilizer.State or {}
    local director = DFR.DirectorBeam and DFR.DirectorBeam.State or {}
    if not stabilizer.active then return 'stabilizer must be active' end
    if not director.active then return 'director beam must be active' end
    if DFR.IsReactorMachineDeployed and not DFR.IsReactorMachineDeployed() then
        return 'reactor machinery must be fully deployed'
    end
    if not stabilizerArmsResolve() then return 'all four stabilizer arms must resolve' end
    local procedureOwner = DFR.PreAnnihilation.TimelineOwner
    if procedureOwner and procedureOwner:IsActive(TIMELINE_NAME) then
        return 'pre-annihilation is already active'
    end
    local machineOwner = DFR.ReactorMachine and DFR.ReactorMachine.TimelineOwner
    if machineOwner and machineOwner:GetActiveInChannel('stabilizer') then
        return 'stabilizer machinery animation is active'
    end
    local count = #availableCatalyzers()
    local minimum = DFR.Config.MinimumAvailableCatalyzers or 1
    if count < minimum then
        return string.format('%d available catalyzer(s) required; %d found', minimum, count)
    end
    return nil
end

function DFR.StartPreAnnihilation(actor)
    local reason = DFR.GetPreAnnihilationUnavailableReason()
    if reason then
        DFR.Log('Pre-annihilation rejected: ' .. reason)
        return false
    end
    return DFR.PreAnnihilation.TimelineOwner:Start(TIMELINE_NAME, {
        actor = actor,
        catalyzerIds = availableCatalyzers(),
        childrenStarted = false
    })
end

function DFR.CancelPreAnnihilation(reason)
    local owner = DFR.PreAnnihilation.TimelineOwner
    return owner and owner:Cancel(TIMELINE_NAME, reason or 'manual cancellation') or false
end

function DFR.GetPreAnnihilationSnapshot()
    local owner = DFR.PreAnnihilation.TimelineOwner
    return owner and owner:GetSnapshot()
        or { ownerId = 'procedure:pre_annihilation', definitions = {}, runs = {} }
end

function DFR.RegisterPreAnnihilationProcedure()
    local owner = DFR.CreateTimelineOwner('procedure:pre_annihilation', {
        defaultChannel = 'procedure',
        defaultConflictPolicy = 'reject'
    })
    DFR.PreAnnihilation.TimelineOwner = owner
    owner:Register(TIMELINE_NAME, {
        label = 'Pre-Annihilation Procedure',
        channel = 'procedure',
        conflictPolicy = 'reject',
        lockOwner = LOCK_OWNER,
        duration = 15,
        guard = function(context, instance)
            local stabilizer = DFR.Stabilizer and DFR.Stabilizer.State or {}
            local director = DFR.DirectorBeam and DFR.DirectorBeam.State or {}
            if DFR.GetState() ~= DFR.STATE_MANUAL_STARTUP
                or not stabilizer.active or not director.active then return false end
            if context.childrenStarted then
                for _, child in ipairs(instance.children or {}) do
                    if child.metadata and child.metadata.required
                        and (child.status == 'failed' or child.status == 'cancelled') then
                        return false
                    end
                end
                return healthyCatalyzerChildren(instance)
                    >= (DFR.Config.MinimumAvailableCatalyzers or 1)
            end
            return true
        end,
        onStart = function(context)
            DFR.PreAnnihilation.Phase = 'PRE_ANNIHILATION'
            DFR.PreAnnihilation.Actor = DFR.GetActorName(context.actor)
            lockConflictingControls()
            if DFR.SetCoreBeamActive then DFR.SetCoreBeamActive('annihilation', false) end
            return true
        end,
        steps = {
            {
                id = 'start_catalyzers',
                at = 0,
                required = true,
                action = function(context, instance)
                    local started = 0
                    for _, id in ipairs(context.catalyzerIds or {}) do
                        local unit = DFR.GetCatalyzer(id)
                        local ok = unit and DFR.TimelineRegistry:StartChild(
                            instance,
                            unit.timelineOwner,
                            'annihilation_fire',
                            { procedureRunId = instance.runId },
                            { role = 'catalyzer', unitId = id }
                        )
                        if ok then started = started + 1 end
                    end
                    context.childrenStarted = true
                    return started >= (DFR.Config.MinimumAvailableCatalyzers or 1)
                end
            },
            {
                id = 'core_impact_and_stabilizer_gate',
                at = 8,
                required = true,
                actions = {
                    function(context, instance)
                        local machineOwner = DFR.ReactorMachine.TimelineOwner
                        return DFR.TimelineRegistry:StartChild(
                            instance,
                            machineOwner,
                            'pre_annihilation_gate',
                            { procedureRunId = instance.runId },
                            { role = 'reactor_machine', required = true }
                        )
                    end,
                    function()
                        if DFR.PulseCoreVisual then
                            DFR.PulseCoreVisual('core_sphere')
                            DFR.PulseCoreVisual('core_shield')
                        end
                        return true
                    end
                }
            }
        },
        onCancel = function() cleanupPresentation() end,
        onComplete = function(context)
            cleanupPresentation()
            local transitioned = DFR.RequestTransition(
                DFR.STATE_ANNIHILATION_STAGE,
                'pre-annihilation procedure complete',
                context.actor
            )
            if not transitioned then return false end
            if DFR.ApplyCoreVisualPreset then DFR.ApplyCoreVisualPreset('annihilation_entry', 0.5) end
            return true
        end
    })

    DFR.RegisterControl('pre_annihilation_begin', {
        label = 'Begin Pre-Annihilation',
        allowedStates = {[DFR.STATE_MANUAL_STARTUP] = true},
        canUse = function()
            local reason = DFR.GetPreAnnihilationUnavailableReason()
            return reason == nil, reason
        end,
        callback = function(actor) return DFR.StartPreAnnihilation(actor) end
    })
    DFR.RegisterControl('pre_annihilation_cancel', {
        label = 'Cancel Pre-Annihilation',
        allowedStates = {[DFR.STATE_MANUAL_STARTUP] = true},
        canUse = function()
            local active = owner:IsActive(TIMELINE_NAME)
            return active, active and nil or 'pre-annihilation is not active'
        end,
        callback = function() return DFR.CancelPreAnnihilation('operator cancellation') end
    })
    return true
end
