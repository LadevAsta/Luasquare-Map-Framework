-- Minimal placeholder bootstrap for the future gm_darkfusion_v2 VMF pass.
-- Include this after luasquare_dfr/init.lua, then call DFR.Start().

include('luasquare_module/3d2display.lua')

DFR = DFR or {}
DFR.MapName = 'gm_darkfusion_v2'

DFR.RegisterBinding('reactor_core_visual', {
    targetName = 'dfr_core_visual',
    class = 'prop_dynamic',
    required = false,
    notes = 'Placeholder until final VMF targetnames are assigned.'
})

DFR.RegisterBinding('control_room_origin', {
    targetName = 'tar_dfr_control_room',
    class = 'info_target',
    required = false,
    notes = 'Optional anchor for early debug and future displays.'
})

DFR.RegisterBinding('decaos_speaker', {
    targetName = 'dfr_decaos_speaker',
    class = 'ambient_generic',
    required = false,
    notes = 'Presentation only for the foundation pass.'
})

DFR.RegisterBinding('core_status_panel', {
    targetName = 'tar_dfr_status_panel',
    class = 'info_target',
    required = false,
    notes = '3D2D telemetry anchor for core/facility status.'
})

DFR.RegisterBinding('startup_status_panel', {
    targetName = 'tar_dfr_startup_panel',
    class = 'info_target',
    required = false,
    notes = '3D2D telemetry anchor for manual startup status.'
})

DFR.RegisterBinding('reactor_shaft_train', {
    targetName = 'dfr_reactor_shaft_train',
    class = 'func_tracktrain',
    required = false,
    notes = 'Main reactor shaft deployment train.'
})

DFR.RegisterBinding('stabilizer_base_train', {
    targetName = 'dfr_stabilizer_base_train',
    class = 'func_tracktrain',
    required = false,
    notes = 'Stabilizer base deployment train.'
})

DFR.RegisterBinding('stabilizer_base_rotor', {
    targetName = 'dfr_stabilizer_base_rotor',
    class = 'func_rotating',
    required = false,
    notes = 'Rotating stabilizer base.'
})

for index = 1, 4 do
    DFR.RegisterBinding('stabilizer_arm_' .. index, {
        targetName = 'dfr_stabilizer_arm_' .. index,
        class = 'func_door_rotating',
        required = false,
        notes = 'Stabilizer arm ' .. tostring(index) .. ' deployment door/rotor.'
    })
end

DFR.RegisterMachinery('reactor_shaft_train', {
    binding = 'reactor_shaft_train',
    label = 'Reactor Shaft Train',
    class = 'func_tracktrain',
    deployInput = 'StartForward',
    retractInput = 'StartBackward',
    stopInput = 'Stop'
})

DFR.RegisterMachinery('stabilizer_base_train', {
    binding = 'stabilizer_base_train',
    label = 'Stabilizer Base Train',
    class = 'func_tracktrain',
    deployInput = 'StartForward',
    retractInput = 'StartBackward',
    stopInput = 'Stop'
})

DFR.RegisterMachinery('stabilizer_base_rotor', {
    binding = 'stabilizer_base_rotor',
    label = 'Stabilizer Base Rotor',
    class = 'func_rotating',
    startInput = 'Start',
    stopInput = 'Stop',
    setSpeedInput = 'SetSpeed',
    spinSpeed = 40
})

for index = 1, 4 do
    DFR.RegisterMachinery('stabilizer_arm_' .. index, {
        binding = 'stabilizer_arm_' .. index,
        label = 'Stabilizer Arm ' .. tostring(index),
        class = 'func_door_rotating',
        openInput = 'Open',
        closeInput = 'Close'
    })
end

DFR.RegisterStartupLever('startup_lever_1', 'Startup Lever 1')
DFR.RegisterStartupLever('startup_lever_2', 'Startup Lever 2')
DFR.RegisterStartupLever('startup_lever_3', 'Startup Lever 3')

DFR.RegisterStartupPrepControls()
DFR.RegisterManualStartupControls()
DFR.RegisterDefaultTelemetryDisplays()

if LUASQUARE_3D2D and LUASQUARE_3D2D.Start then
    LUASQUARE_3D2D.TickInterval = 0.2
    LUASQUARE_3D2D.Start()
end

DFR.Log('gm_darkfusion_v2 placeholder bootstrap registered')
