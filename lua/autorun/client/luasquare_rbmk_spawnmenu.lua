if not CLIENT then return end
RBMK = RBMK or {}
RBMK.Debug = RBMK.Debug or {}
hook.Add('PopulateToolMenu', 'LUASQUARE_RBMK_Menu', function()
    spawnmenu.AddToolMenuOption('Options', 'Luasquare', 'LuasquareRBMK', 'RBMK Framework', '', '', function(panel)
        panel:Clear()
        panel:Help('Luasquare RBMK Debug Options')
        -- =========================================
        -- MASTER
        -- =========================================
        panel:CheckBox('Enable Debug', 'luasquare_rbmk_debug_enabled')
        panel:NumSlider('Infos', 'luasquare_rbmk_debug_textscale', 0.1, 2.0, 2)
        panel:NumSlider('Channels', 'luasquare_rbmk_debug_textscale_cell', 0.1, 2.0, 2)
        panel:NumSlider('Flux', 'luasquare_rbmk_debug_textscale_flux', 0.1, 2.0, 2)
        panel:NumSlider('Render Distance', 'luasquare_rbmk_debug_maxdistance', 0, 8000, 0)
        panel:CheckBox('FOV Culling', 'luasquare_rbmk_debug_fovcheck')
        -- =========================================
        -- CELL VISUALS
        -- =========================================
        panel:CheckBox('Draw Flux Rays', 'luasquare_rbmk_draw_flux_rays')
        -- =========================================
        -- CELL FILTERS
        -- =========================================
        panel:CheckBox('Show Fuel Channels', 'luasquare_rbmk_show_fuel')
        panel:CheckBox('Show Control Channels', 'luasquare_rbmk_show_control')
        panel:CheckBox('Show Autorod Channels', 'luasquare_rbmk_show_autorod')
        panel:CheckBox('Show Reflector Channels', 'luasquare_rbmk_show_reflector')
        panel:CheckBox('Show Absorber Channels', 'luasquare_rbmk_show_absorber')
        panel:CheckBox('Show Blank Channels', 'luasquare_rbmk_show_blank')
        panel:CheckBox('Show Steam Channels', 'luasquare_rbmk_show_steam')
        panel:CheckBox('Show Neutron Sources', 'luasquare_rbmk_show_neutronsource')
    end)
end)

-- =========================================
-- CLIENT CONVARS
-- =========================================
CreateClientConVar('luasquare_rbmk_debug_enabled', '0', true, false)
CreateClientConVar('luasquare_rbmk_debug_textscale', '0.2', true, false)
CreateClientConVar('luasquare_rbmk_debug_textscale_cell', '0.2', true, false)
CreateClientConVar('luasquare_rbmk_debug_textscale_flux', '0.1', true, false)
CreateClientConVar('luasquare_rbmk_debug_maxdistance', '2500', true, false)
CreateClientConVar('luasquare_rbmk_debug_fovcheck', '1', true, false)
CreateClientConVar('luasquare_rbmk_draw_flux_rays', '1', true, false)

CreateClientConVar('luasquare_rbmk_show_fuel', '1', true, false)
CreateClientConVar('luasquare_rbmk_show_control', '1', true, false)
CreateClientConVar('luasquare_rbmk_show_autorod', '1', true, false)
CreateClientConVar('luasquare_rbmk_show_reflector', '1', true, false)
CreateClientConVar('luasquare_rbmk_show_absorber', '1', true, false)
CreateClientConVar('luasquare_rbmk_show_blank', '0', true, false)
CreateClientConVar('luasquare_rbmk_show_steam', '1', true, false)
CreateClientConVar('luasquare_rbmk_show_neutronsource', '1', true, false)
