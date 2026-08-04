if not CLIENT then return end

local CATALOG_REQUEST = 'LUASQUARE_DFR_DebugCatalogRequest'
local CATALOG_RESPONSE = 'LUASQUARE_DFR_DebugCatalog'
local REFRESH_TIMER = 'LUASQUARE_DFR_DebugCatalogRefresh'
local CATALOG_TRANSFER_TIMEOUT = 10

local PAGES = {
    'Overview',
    'State & Controls',
    'Machinery',
    'Core Visuals',
    'Sequences & Catalyzers',
    'Bindings',
    'Advanced'
}

local menuState = {
    page = 'Overview',
    catalog = nil,
    panel = nil,
    control = nil,
    state = nil,
    machinery = nil,
    machineryNode = {},
    visual = nil,
    catalyzer = 1,
    catalyzerTimeline = {},
    reactorMachineTimeline = nil,
    binding = nil
}

local catalogTransfers = {}

local function requestCatalog()
    if not net then return end
    local started = pcall(net.Start, CATALOG_REQUEST)
    if not started then return end
    net.SendToServer()
end

local function scheduleRefresh()
    if timer.Exists(REFRESH_TIMER) then timer.Remove(REFRESH_TIMER) end
    timer.Create(REFRESH_TIMER, 0.35, 1, requestCatalog)
end

local function runCommand(command, ...)
    RunConsoleCommand(command, ...)
    scheduleRefresh()
end

local function addButton(panel, label, command, ...)
    local args = { ... }
    local button = panel:Button(label)
    button.DoClick = function()
        runCommand(command, unpack(args))
    end
    return button
end

local function addTextCommand(panel, label, fields, command)
    panel:Help(label)
    local entries = {}

    for _, field in ipairs(fields) do
        local entry = vgui.Create('DTextEntry', panel)
        entry:SetPlaceholderText(field.placeholder or field.label or '')
        entry:SetText(field.default or '')
        panel:AddItem(entry)
        table.insert(entries, entry)
    end

    local button = vgui.Create('DButton', panel)
    button:SetText(label)
    button.DoClick = function()
        local args = {}
        for _, entry in ipairs(entries) do table.insert(args, entry:GetValue()) end
        runCommand(command, unpack(args))
    end
    panel:AddItem(button)
end

local function addCombo(panel, label, items, selectedId, formatLabel, onSelect)
    panel:Help(label)
    local combo = vgui.Create('DComboBox', panel)
    combo:SetSortItems(false)

    local selected = nil
    for _, item in ipairs(items or {}) do
        local itemLabel = formatLabel and formatLabel(item) or tostring(item.label or item.id)
        combo:AddChoice(itemLabel, item)
        if item.id == selectedId then selected = item end
    end

    selected = selected or (items and items[1]) or nil
    if selected then
        combo:SetValue(formatLabel and formatLabel(selected) or tostring(selected.label or selected.id))
    else
        combo:SetValue('None registered')
        combo:SetEnabled(false)
    end

    combo.OnSelect = function(_, _, _, data)
        if data and onSelect then onSelect(data) end
    end
    panel:AddItem(combo)
    return combo, selected
end

local function addSlider(panel, label, descriptor, value)
    descriptor = descriptor or {}
    local slider = vgui.Create('DNumSlider', panel)
    slider:SetText(label)
    slider:SetMinMax(tonumber(descriptor.min) or 0, tonumber(descriptor.max) or 1)
    slider:SetDecimals(tonumber(descriptor.decimals) or 0)
    slider:SetValue(tonumber(value) or tonumber(descriptor.min) or 0)
    panel:AddItem(slider)
    return slider
end

local function componentLabel(item)
    local status = (item.foundCount or 0) > 0 and ('found x' .. tostring(item.foundCount)) or 'missing'
    return string.format('%s [%s] (%s)', tostring(item.label or item.id), tostring(item.type or item.kind or item.id), status)
end

local function bindingTargets(item)
    local names = item and item.targetNames or {}
    if #names <= 0 then return '(none)' end
    return table.concat(names, ', ')
end

local rebuildMenu

local function queueRebuild()
    timer.Simple(0, function()
        if IsValid(menuState.panel) and rebuildMenu then rebuildMenu(menuState.panel) end
    end)
end

local function buildOverview(panel, catalog)
    local overview = catalog.overview or {}
    panel:Help('Runtime')
    panel:Help('Version: ' .. tostring(overview.version or 'unknown'))
    panel:Help('State: ' .. tostring(overview.state or 'unavailable'))
    panel:Help('Running: ' .. tostring(overview.running) .. '    Halted: ' .. tostring(overview.halted))
    if overview.haltReason then panel:Help('Halt reason: ' .. tostring(overview.haltReason)) end
    panel:Help(string.format(
        'Controls: %d    Machinery: %d    Visuals: %d',
        overview.controlCount or 0,
        overview.machineCount or 0,
        overview.visualCount or 0
    ))
    panel:Help(string.format(
        'Bindings: %d    Missing: %d',
        overview.bindingCount or 0,
        overview.missingBindingCount or 0
    ))
    local stabilizer = catalog.stabilizer or {}
    local director = catalog.directorBeam or {}
    panel:Help(string.format(
        'Stabilizer: %s, %.2f GW    Director: %s, precision %.1f%%',
        stabilizer.active and 'active' or 'offline',
        tonumber(stabilizer.powerGW) or 0,
        director.active and 'active' or 'offline',
        tonumber(director.precisionPercent) or 0
    ))

    local refresh = panel:Button('Refresh Catalog')
    refresh.DoClick = requestCatalog
    addButton(panel, 'Start Simulation', 'luasquare_dfr_start')
    addButton(panel, 'Stop Simulation', 'luasquare_dfr_stop', 'spawnmenu')
    addButton(panel, 'Print Snapshot to Console', 'luasquare_dfr_snapshot')
end

local function buildStateControls(panel, catalog)
    local nextStates = {}
    for _, state in ipairs(catalog.states or {}) do
        if state.allowed and not state.current then table.insert(nextStates, state) end
    end

    local _, selectedState = addCombo(panel, 'Valid next state', nextStates, menuState.state, nil, function(item)
        menuState.state = item.id
    end)
    if selectedState then menuState.state = selectedState.id end

    local transition = panel:Button('Request Selected Transition')
    transition:SetEnabled(selectedState ~= nil)
    transition.DoClick = function()
        if menuState.state then runCommand('luasquare_dfr_transition', menuState.state, 'spawnmenu') end
    end

    local function controlLabel(item)
        return string.format('%s [%s]', tostring(item.label or item.id), item.available and 'available' or 'unavailable')
    end

    local _, selectedControl = addCombo(panel, 'Registered control', catalog.controls, menuState.control, controlLabel, function(item)
        menuState.control = item.id
        queueRebuild()
    end)
    if selectedControl then menuState.control = selectedControl.id end
    if selectedControl and selectedControl.unavailableReason then
        panel:Help('Unavailable: ' .. tostring(selectedControl.unavailableReason))
    end

    local useControl = panel:Button('Use Selected Control')
    useControl:SetEnabled(selectedControl and selectedControl.available or false)
    useControl.DoClick = function()
        if menuState.control then runCommand('luasquare_dfr_use_control', menuState.control) end
    end
end

local function buildMachinery(panel, catalog)
    local _, selected = addCombo(panel, 'Registered machinery', catalog.machinery, menuState.machinery, componentLabel, function(item)
        menuState.machinery = item.id
        queueRebuild()
    end)
    if not selected then return end
    menuState.machinery = selected.id

    panel:Help('ID: ' .. tostring(selected.id))
    panel:Help('Binding: ' .. tostring(selected.binding) .. ' -> ' .. bindingTargets(selected))
    panel:Help('Logical state: ' .. tostring(selected.state or 'unknown'))
    if selected.currentNode then panel:Help('Current node: ' .. tostring(selected.currentNode)) end
    if selected.destinationNode then panel:Help('Destination: ' .. tostring(selected.destinationNode)) end

    local actions = selected.actions or {}
    if actions.deploy then addButton(panel, 'Deploy', 'luasquare_dfr_machine_deploy', selected.id) end
    if actions.retract then addButton(panel, 'Retract', 'luasquare_dfr_machine_retract', selected.id) end
    if actions.start then addButton(panel, 'Start', 'luasquare_dfr_machine_start', selected.id) end
    if actions.stop then addButton(panel, 'Stop', 'luasquare_dfr_machine_stop', selected.id) end
    if actions.open then addButton(panel, 'Open', 'luasquare_dfr_machine_open', selected.id) end
    if actions.close then addButton(panel, 'Close', 'luasquare_dfr_machine_close', selected.id) end

    if actions.move and #(selected.nodes or {}) > 0 then
        local nodeItems = {}
        for _, node in ipairs(selected.nodes) do table.insert(nodeItems, { id = node, label = node }) end
        local savedNode = menuState.machineryNode[selected.id]
        local _, selectedNode = addCombo(panel, 'Destination node', nodeItems, savedNode, nil, function(item)
            menuState.machineryNode[selected.id] = item.id
        end)
        if selectedNode then menuState.machineryNode[selected.id] = selectedNode.id end

        local move = panel:Button('Move to Selected Node')
        move.DoClick = function()
            local node = menuState.machineryNode[selected.id]
            if node then runCommand('luasquare_dfr_machine_move', selected.id, node) end
        end
    end

    if actions.speed and selected.speed then
        local speed = addSlider(panel, 'Configured speed (' .. tostring(selected.speed.unit or '%') .. ')', selected.speed, selected.configuredSpeed)
        panel:Help('Source ratio: ' .. string.format('%.3f', tonumber(selected.sourceSpeed) or ((tonumber(selected.configuredSpeed) or 0) * 0.01)))
        local apply = panel:Button('Apply Speed')
        apply.DoClick = function()
            runCommand('luasquare_dfr_machine_speed', selected.id, tostring(speed:GetValue()))
        end
    end
end

local function buildVisuals(panel, catalog)
    local coreState = catalog.coreState or {}
    panel:Help(string.format(
        'Targets — sphere %.3f m, stellar %.3f m, horizon %.3f m, shield %.3f m',
        tonumber(coreState.sphereRadiusMeters) or 0,
        tonumber(coreState.stellarRadiusMeters) or 0,
        tonumber(coreState.eventHorizonRadiusMeters) or 0,
        tonumber(coreState.shieldRadiusMeters) or 0
    ))
    local _, selected = addCombo(panel, 'Registered core visual', catalog.visuals, menuState.visual, componentLabel, function(item)
        menuState.visual = item.id
        queueRebuild()
    end)
    if not selected then return end
    menuState.visual = selected.id

    panel:Help('ID: ' .. tostring(selected.id))
    panel:Help('Binding: ' .. tostring(selected.binding) .. ' -> ' .. bindingTargets(selected))
    panel:Help('Last commanded visibility: ' .. (selected.lastCommandedEnabled == nil and 'unknown' or tostring(selected.lastCommandedEnabled)))
    if selected.basisRadiusHammer then
        panel:Help(string.format('Measured unscaled radius: %.3f HU', tonumber(selected.basisRadiusHammer) or 0))
    end
    local factors = selected.axisFactors or {}
    local scales = selected.axisScales or {}
    panel:Help(string.format(
        'Commanded axes: X %.4f / %.4f    Y %.4f / %.4f    Z %.4f / %.4f',
        tonumber(factors.x) or 1,
        tonumber(scales.x) or 0,
        tonumber(factors.y) or 1,
        tonumber(scales.y) or 0,
        tonumber(factors.z) or 1,
        tonumber(scales.z) or 0
    ))
    panel:Help('Animation: wobble ' .. tostring(selected.wobble and selected.wobble.enabled or false)
        .. '    pulse ' .. tostring(selected.pulse and ('stage ' .. tostring(selected.pulse.stage)) or 'idle'))

    addButton(panel, 'Enable', 'luasquare_dfr_visual_enable', selected.id, '1')
    addButton(panel, 'Disable', 'luasquare_dfr_visual_enable', selected.id, '0')
    addButton(panel, 'Synchronize All Visuals', 'luasquare_dfr_visual_sync')

    if selected.actions and selected.actions.radius and selected.radius then
        local radius = addSlider(panel, 'Radius (' .. tostring(selected.radius.unit or 'm') .. ')', selected.radius, selected.radiusMeters)
        local transition = addSlider(panel, 'Transition (' .. tostring((selected.transition and selected.transition.unit) or 's') .. ')', selected.transition, 0)
        local measurement = panel:Help('')

        local function updateMeasurement(value)
            value = tonumber(value) or 0
            local basisScale = tonumber(selected.basisScale) or 1
            local unscaledRadiusHammer = tonumber(selected.basisRadiusHammer)
            local modelScale
            if unscaledRadiusHammer and unscaledRadiusHammer > 0 then
                modelScale = value / (unscaledRadiusHammer * 0.0254)
            else
                local basisRadius = tonumber(selected.basisRadiusMeters) or 1
                modelScale = basisRadius > 0 and value / basisRadius * basisScale or 0
            end
            local multiplier = basisScale ~= 0 and modelScale / basisScale or 0
            measurement:SetText(string.format('Radius: %.3f m    Multiplier: %.4f    Source model scale: %.4f', value, multiplier, modelScale))
        end

        radius.OnValueChanged = function(_, value) updateMeasurement(value) end
        updateMeasurement(radius:GetValue())

        local apply = panel:Button('Apply Radius')
        apply.DoClick = function()
            runCommand(
                'luasquare_dfr_visual_radius',
                selected.id,
                tostring(radius:GetValue()),
                tostring(transition:GetValue())
            )
        end

        if selected.wobbleAmplitude and selected.wobbleInterval then
            local wobble = selected.wobble or {}
            local amplitude = addSlider(
                panel,
                'Wobble amplitude (' .. tostring(selected.wobbleAmplitude.unit or '%') .. ')',
                selected.wobbleAmplitude,
                wobble.amplitudePercent or 2
            )
            local minimum = addSlider(
                panel,
                'Minimum wobble interval (s)',
                selected.wobbleInterval,
                wobble.minIntervalSeconds or 0.8
            )
            local maximum = addSlider(
                panel,
                'Maximum wobble interval (s)',
                selected.wobbleInterval,
                wobble.maxIntervalSeconds or 1.4
            )
            local function applyWobble(enabled)
                runCommand(
                    'luasquare_dfr_visual_wobble',
                    selected.id,
                    enabled and '1' or '0',
                    tostring(amplitude:GetValue()),
                    tostring(minimum:GetValue()),
                    tostring(maximum:GetValue())
                )
            end
            local wobbleApply = panel:Button('Apply Wobble Tuning')
            wobbleApply.DoClick = function()
                applyWobble(wobble.enabled)
            end
            local wobbleEnable = panel:Button('Enable Wobble')
            wobbleEnable.DoClick = function() applyWobble(true) end
            local wobbleDisable = panel:Button('Disable Wobble')
            wobbleDisable.DoClick = function() applyWobble(false) end
        end

        if selected.pulseAmplitude then
            local pulseAmplitude = addSlider(
                panel,
                'Pulse amplitude (' .. tostring(selected.pulseAmplitude.unit or '%') .. ')',
                selected.pulseAmplitude,
                selected.pulse and selected.pulse.amplitudePercent or 10
            )
            local pulse = panel:Button('Trigger Pulse')
            pulse.DoClick = function()
                runCommand('luasquare_dfr_visual_pulse', selected.id, tostring(pulseAmplitude:GetValue()))
            end
        end
    end
end

local function buildSequences(panel, catalog)
    panel:Help('Timeline phase: ' .. tostring(catalog.timelinePhase or 'idle'))
    local active = catalog.timelines or {}
    if #active == 0 then
        panel:Help('Active timeline: none')
    else
        for _, timeline in ipairs(active) do
            panel:Help(string.format(
                '%s [%s/%s] - step %s - %.2f / %.2f s%s - parent %s - children %d',
                tostring(timeline.label or timeline.id),
                tostring(timeline.ownerId or 'global'),
                tostring(timeline.channel or 'default'),
                tostring(timeline.currentStep or 'waiting'),
                tonumber(timeline.elapsed) or 0,
                tonumber(timeline.duration) or 0,
                timeline.paused and ' (paused)' or '',
                tostring(timeline.parentRunId or 'none'),
                #(timeline.children or {})
            ))
            for _, child in ipairs(timeline.children or {}) do
                panel:Help(string.format(
                    '  child %s [%s/%s]: %s',
                    tostring(child.localId or child.runId),
                    tostring(child.ownerId or 'global'),
                    tostring(child.channel or 'default'),
                    tostring(child.status or 'unknown')
                ))
            end
        end
    end

    local function showLastRun(run)
        if not run then return end
        panel:Help(string.format(
            'Last terminal run %s: %s; parent %s; children %d',
            tostring(run.runId or 'unknown'),
            tostring(run.status or 'unknown'),
            tostring(run.parentRunId or 'none'),
            #(run.children or {})
        ))
        for _, child in ipairs(run.children or {}) do
            panel:Help(string.format(
                '  terminal child %s [%s]: %s',
                tostring(child.localId or child.runId),
                tostring(child.ownerId or 'global'),
                tostring(child.status or 'unknown')
            ))
        end
    end

    addButton(panel, 'Begin Pre-Annihilation', 'luasquare_dfr_pre_annihilation_start')
    addButton(panel, 'Cancel Pre-Annihilation', 'luasquare_dfr_pre_annihilation_cancel')
    local refresh = panel:Button('Refresh Timeline and Catalyzers')
    refresh.DoClick = requestCatalog

    local machineTimeline = catalog.reactorMachineTimeline or {}
    local _, selectedMachineTimeline = addCombo(
        panel,
        'Reactor-machine timeline',
        machineTimeline.definitions or {},
        menuState.reactorMachineTimeline,
        function(item)
            return string.format('%s [%s, %.1fs]%s%s',
                tostring(item.label or item.id), tostring(item.channel or 'default'),
                tonumber(item.duration) or 0, item.active and ' ACTIVE' or '',
                item.lastRun and (' last=' .. tostring(item.lastRun.status)) or '')
        end,
        function(item) menuState.reactorMachineTimeline = item.id end
    )
    if selectedMachineTimeline then
        menuState.reactorMachineTimeline = selectedMachineTimeline.id
        showLastRun(selectedMachineTimeline.lastRun)
        addButton(
            panel, 'Start Machine Timeline', 'luasquare_dfr_reactor_machine_timeline',
            selectedMachineTimeline.id
        )
        addButton(
            panel, 'Cancel Machine Timeline', 'luasquare_dfr_reactor_machine_timeline_cancel',
            selectedMachineTimeline.id
        )
    end

    local items = {}
    for id, unit in pairs(catalog.catalyzers or {}) do
        unit.id = tonumber(unit.id) or tonumber(id)
        unit.label = 'Catalyzer ' .. tostring(unit.id)
        table.insert(items, unit)
    end
    table.sort(items, function(a, b) return (tonumber(a.id) or 0) < (tonumber(b.id) or 0) end)

    local function catalyzerLabel(unit)
        return string.format(
            'Catalyzer %d [%s] (%s)',
            tonumber(unit.id) or 0,
            unit.available and 'available' or 'missing beam',
            tostring(unit.mode or 'OFFLINE')
        )
    end

    local _, selected = addCombo(panel, 'Catalyzer slot', items, menuState.catalyzer, catalyzerLabel, function(item)
        menuState.catalyzer = item.id
        queueRebuild()
    end)
    if not selected then return end
    menuState.catalyzer = selected.id
    panel:Help('Actual prefix: ' .. (selected.prefix == '' and '(unprefixed paste source)' or tostring(selected.prefix)))
    panel:Help(string.format(
        'Groups: %d    Resolved entities: %d    Missing groups: %d',
        tonumber(selected.logicalGroupCount) or 0,
        tonumber(selected.entityCount) or 0,
        #(selected.missing or {})
    ))
    if #(selected.missing or {}) > 0 then panel:Help('Missing: ' .. table.concat(selected.missing, ', ')) end

    local timeline = selected.timeline or {}
    local selectedTimelineId = menuState.catalyzerTimeline[selected.id]
    local _, selectedTimeline = addCombo(
        panel,
        'Owned catalyzer timeline',
        timeline.definitions or {},
        selectedTimelineId,
        function(item)
            return string.format('%s [%s, %.1fs]%s%s',
                tostring(item.label or item.id), tostring(item.channel or 'default'),
                tonumber(item.duration) or 0, item.active and ' ACTIVE' or '',
                item.lastRun and (' last=' .. tostring(item.lastRun.status)) or '')
        end,
        function(item) menuState.catalyzerTimeline[selected.id] = item.id end
    )
    if selectedTimeline then
        menuState.catalyzerTimeline[selected.id] = selectedTimeline.id
        showLastRun(selectedTimeline.lastRun)
        addButton(
            panel, 'Start Catalyzer Timeline', 'luasquare_dfr_catalyzer_timeline',
            tostring(selected.id), selectedTimeline.id
        )
        addButton(
            panel, 'Cancel Catalyzer Timeline', 'luasquare_dfr_catalyzer_timeline_cancel',
            tostring(selected.id), selectedTimeline.id
        )
    end

    panel:Help('Immediate presentation modes (debug only)')
    for _, mode in ipairs({'OFFLINE', 'CHARGING_LOW', 'CHARGING_HIGH', 'FIRING', 'CHARGED'}) do
        addButton(panel, 'Set ' .. mode, 'luasquare_dfr_catalyzer_mode', tostring(selected.id), mode)
    end
end

local function buildBindings(panel, catalog)
    local validation = catalog.validation
    if validation then
        panel:Help(string.format(
            'Last validation: %s    Required missing: %d    Optional missing: %d',
            validation.ok and 'passed' or 'failed',
            validation.missingRequired or 0,
            validation.missingOptional or 0
        ))
    else
        panel:Help('Last validation: not run')
    end

    local function bindingLabel(item)
        local status = (item.foundCount or 0) > 0 and ('found x' .. tostring(item.foundCount)) or 'missing'
        return string.format('%s (%s)', tostring(item.id), status)
    end

    local _, selected = addCombo(panel, 'Registered binding', catalog.bindings, menuState.binding, bindingLabel, function(item)
        menuState.binding = item.id
        queueRebuild()
    end)
    if selected then
        menuState.binding = selected.id
        panel:Help('Target: ' .. bindingTargets(selected))
        panel:Help('Expected class: ' .. tostring(selected.class or 'any'))
        panel:Help('Requirement: ' .. (selected.required and 'required' or 'optional'))
        panel:Help('Resolved entities: ' .. tostring(selected.foundCount or 0))
        if selected.notes then panel:Help('Notes: ' .. tostring(selected.notes)) end
    end

    addButton(panel, 'Validate All Bindings', 'luasquare_dfr_validate_bindings')
    addButton(panel, 'Clear Binding Cache', 'luasquare_dfr_clear_binding_cache')
    local refresh = panel:Button('Refresh Catalog')
    refresh.DoClick = requestCatalog
end

local function buildAdvanced(panel)
    panel:Help('Advanced raw tools bypass the typed menu. Invalid commands can halt the DFR simulation.')
    addButton(panel, 'Register V2 Default Bindings', 'luasquare_dfr_register_v2_defaults')
    addButton(panel, 'Force Debug Halt', 'luasquare_dfr_halt', 'spawnmenu debug halt')

    addTextCommand(panel, 'Move Tracktrain To Node', {
        { placeholder = 'machine id', default = 'upper_shaft_train' },
        { placeholder = 'destination path_track', default = 'dfr_pt_upper_1' }
    }, 'luasquare_dfr_machine_move')

    addTextCommand(panel, 'Simulate path_track Pass', {
        { placeholder = 'path_track targetname', default = 'dfr_pt_upper_1' },
        { placeholder = 'optional machine id', default = '' }
    }, 'luasquare_dfr_path_pass')

    addTextCommand(panel, 'Fire Machinery Input', {
        { placeholder = 'machine id', default = 'stabilizer_rotator' },
        { placeholder = 'input', default = 'Start' },
        { placeholder = 'value', default = '' }
    }, 'luasquare_dfr_machine_command')

    addTextCommand(panel, 'Start Machinery', {
        { placeholder = 'machine id', default = 'stabilizer_rotator' }
    }, 'luasquare_dfr_machine_start')

    addTextCommand(panel, 'Stop Machinery', {
        { placeholder = 'machine id', default = 'stabilizer_rotator' }
    }, 'luasquare_dfr_machine_stop')

    addTextCommand(panel, 'Open Door Machinery', {
        { placeholder = 'machine id', default = 'stabilizer_arm_1' }
    }, 'luasquare_dfr_machine_open')

    addTextCommand(panel, 'Close Door Machinery', {
        { placeholder = 'machine id', default = 'stabilizer_arm_1' }
    }, 'luasquare_dfr_machine_close')

    addTextCommand(panel, 'Enable Visual', {
        { placeholder = 'visual id', default = 'core_sphere' },
        { placeholder = '1 or 0', default = '1' }
    }, 'luasquare_dfr_visual_enable')

    addTextCommand(panel, 'Set Visual Scale Multiplier', {
        { placeholder = 'visual id', default = 'core_sphere' },
        { placeholder = 'multiplier', default = '1' },
        { placeholder = 'seconds', default = '0' }
    }, 'luasquare_dfr_visual_scale')

    addTextCommand(panel, 'Request Transition', {
        { placeholder = 'state', default = 'STARTUP_PREP' },
        { placeholder = 'reason', default = 'spawnmenu' }
    }, 'luasquare_dfr_transition')
end

rebuildMenu = function(panel)
    if not IsValid(panel) then return end
    panel:Clear()
    panel:Help('Dark Fusion Reactor Debug')

    local pageCombo = vgui.Create('DComboBox', panel)
    pageCombo:SetSortItems(false)
    for _, page in ipairs(PAGES) do pageCombo:AddChoice(page, page) end
    pageCombo:SetValue(menuState.page)
    pageCombo.OnSelect = function(_, _, _, page)
        menuState.page = page or 'Overview'
        requestCatalog()
        queueRebuild()
    end
    panel:AddItem(pageCombo)

    if menuState.page == 'Advanced' then
        buildAdvanced(panel)
        return
    end

    local catalog = menuState.catalog
    if not catalog then
        panel:Help('Requesting server catalog. The catalog is available only on a loaded DFR runtime and to admins or single-player clients.')
        local retry = panel:Button('Retry Catalog Request')
        retry.DoClick = requestCatalog
        return
    end

    if menuState.page == 'Overview' then buildOverview(panel, catalog) end
    if menuState.page == 'State & Controls' then buildStateControls(panel, catalog) end
    if menuState.page == 'Machinery' then buildMachinery(panel, catalog) end
    if menuState.page == 'Core Visuals' then buildVisuals(panel, catalog) end
    if menuState.page == 'Sequences & Catalyzers' then buildSequences(panel, catalog) end
    if menuState.page == 'Bindings' then buildBindings(panel, catalog) end
end

net.Receive(CATALOG_RESPONSE, function()
    local transferId = net.ReadUInt(32)
    local chunkIndex = net.ReadUInt(16)
    local chunkCount = net.ReadUInt(16)
    local chunkBytes = net.ReadUInt(16)
    if chunkIndex < 1 or chunkCount < 1 or chunkIndex > chunkCount or chunkBytes > 60000 then return end

    local transfer = catalogTransfers[transferId]
    if not transfer or transfer.count ~= chunkCount then
        transfer = { count = chunkCount, received = 0, chunks = {} }
        catalogTransfers[transferId] = transfer
        timer.Simple(CATALOG_TRANSFER_TIMEOUT, function()
            if catalogTransfers[transferId] == transfer then catalogTransfers[transferId] = nil end
        end)
    end

    if not transfer.chunks[chunkIndex] then
        transfer.chunks[chunkIndex] = net.ReadData(chunkBytes)
        transfer.received = transfer.received + 1
    else
        net.ReadData(chunkBytes)
    end
    if transfer.received < transfer.count then return end

    catalogTransfers[transferId] = nil
    local payload = table.concat(transfer.chunks)
    local json = util.Decompress(payload)
    local catalog = json and util.JSONToTable(json) or nil
    if type(catalog) ~= 'table' or catalog.wireVersion ~= 2 then return end
    menuState.catalog = catalog
    if IsValid(menuState.panel) then rebuildMenu(menuState.panel) end
end)

hook.Add('PopulateToolMenu', 'LUASQUARE_DFR_Menu', function()
    spawnmenu.AddToolMenuOption('Options', 'Luasquare', 'LuasquareDFR', 'Dark Fusion Reactor', '', '', function(panel)
        menuState.panel = panel
        rebuildMenu(panel)
        requestCatalog()
    end)
end)
