if not CLIENT then return end

local function addButton(panel, label, command, ...)
    local args = { ... }
    local button = panel:Button(label)
    button.DoClick = function()
        RunConsoleCommand(command, unpack(args))
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
        for _, entry in ipairs(entries) do
            table.insert(args, entry:GetValue())
        end
        RunConsoleCommand(command, unpack(args))
    end
    panel:AddItem(button)
end

hook.Add('PopulateToolMenu', 'LUASQUARE_DFR_Menu', function()
    spawnmenu.AddToolMenuOption('Options', 'Luasquare', 'LuasquareDFR', 'Dark Fusion Reactor', '', '', function(panel)
        panel:Clear()
        panel:Help('Dark Fusion Reactor Debug')

        addButton(panel, 'Register V2 Default Bindings', 'luasquare_dfr_register_v2_defaults')
        addButton(panel, 'Validate Bindings', 'luasquare_dfr_validate_bindings')
        addButton(panel, 'Clear Binding Cache', 'luasquare_dfr_clear_binding_cache')
        addButton(panel, 'Start Simulation', 'luasquare_dfr_start')
        addButton(panel, 'Stop Simulation', 'luasquare_dfr_stop', 'spawnmenu')
        addButton(panel, 'Print Snapshot', 'luasquare_dfr_snapshot')
        addButton(panel, 'Sync Core Visuals', 'luasquare_dfr_visual_sync')

        panel:Help('Startup Controls')
        addButton(panel, 'Arm Startup Lever 1', 'luasquare_dfr_use_control', 'startup_lever_1')
        addButton(panel, 'Arm Startup Lever 2', 'luasquare_dfr_use_control', 'startup_lever_2')
        addButton(panel, 'Arm Startup Lever 3', 'luasquare_dfr_use_control', 'startup_lever_3')
        addButton(panel, 'Begin Manual Startup', 'luasquare_dfr_use_control', 'manual_startup_begin')
        addButton(panel, 'Abort Startup Prep', 'luasquare_dfr_use_control', 'startup_prep_abort')

        panel:Help('Manual Startup')
        addButton(panel, 'Enable Stabilizer', 'luasquare_dfr_use_control', 'stabilizer_enable')
        addButton(panel, 'Disable Stabilizer', 'luasquare_dfr_use_control', 'stabilizer_disable')
        addButton(panel, 'Raise Containment', 'luasquare_dfr_use_control', 'containment_raise')
        addButton(panel, 'Lower Containment', 'luasquare_dfr_use_control', 'containment_lower')
        addButton(panel, 'Enable Director Beam', 'luasquare_dfr_use_control', 'director_beam_enable')
        addButton(panel, 'Disable Director Beam', 'luasquare_dfr_use_control', 'director_beam_disable')

        panel:Help('Reactor Machine')
        addButton(panel, 'Deploy Startup Machinery', 'luasquare_dfr_machine_deploy')
        addButton(panel, 'Retract Startup Machinery', 'luasquare_dfr_machine_retract')
        addButton(panel, 'Activate Stabilizer Machinery', 'luasquare_dfr_stabilizer_machine', '1')
        addButton(panel, 'Deactivate Stabilizer Machinery', 'luasquare_dfr_stabilizer_machine', '0')

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

        panel:Help('Core Visuals')
        addTextCommand(panel, 'Enable Visual', {
            { placeholder = 'visual id', default = 'core_sphere' },
            { placeholder = '1 or 0', default = '1' }
        }, 'luasquare_dfr_visual_enable')

        addTextCommand(panel, 'Set Visual Scale', {
            { placeholder = 'visual id', default = 'core_sphere' },
            { placeholder = 'scale', default = '1' },
            { placeholder = 'seconds', default = '0' }
        }, 'luasquare_dfr_visual_scale')

        panel:Help('State Debug')
        addTextCommand(panel, 'Request Transition', {
            { placeholder = 'state', default = 'STARTUP_PREP' },
            { placeholder = 'reason', default = 'spawnmenu' }
        }, 'luasquare_dfr_transition')
    end)
end)
