if not CLIENT then return end
RBMK = RBMK or {}
RBMK.Debug = RBMK.Debug or {}
hook.Add('PopulateToolMenu', 'LITHOS_RBMK_Menu', function()
    spawnmenu.AddToolMenuOption('Options', 'Lithos', 'LithosRBMK', 'RBMK Framework', '', '', function(panel)
        panel:Clear()
        panel:Help('Lithos RBMK Debug Options')
        -- =========================================
        -- MASTER
        -- =========================================
        panel:CheckBox('Enable Debug', 'lithos_rbmk_debug_enabled')
        panel:NumSlider('Infos', 'lithos_rbmk_debug_textscale', 0.1, 2.0, 2)
        panel:NumSlider('Channels', 'lithos_rbmk_debug_textscale_cell', 0.1, 2.0, 2)
        panel:NumSlider('Flux', 'lithos_rbmk_debug_textscale_flux', 0.1, 2.0, 2)
        -- =========================================
        -- CELL VISUALS
        -- =========================================
        panel:CheckBox('Draw Flux Rays', 'lithos_rbmk_draw_flux_rays')
        -- =========================================
        -- CELL FILTERS
        -- =========================================
        panel:CheckBox('Show Fuel Channels', 'lithos_rbmk_show_fuel')
        panel:CheckBox('Show Control Channels', 'lithos_rbmk_show_control')
        panel:CheckBox('Show Autorod Channels', 'lithos_rbmk_show_autorod')
        panel:CheckBox('Show Reflector Channels', 'lithos_rbmk_show_reflector')
        panel:CheckBox('Show Absorber Channels', 'lithos_rbmk_show_absorber')
        panel:CheckBox('Show Blank Channels', 'lithos_rbmk_show_blank')
        panel:CheckBox('Show Steam Channels', 'lithos_rbmk_show_steam')
        panel:CheckBox('Show Neutron Sources', 'lithos_rbmk_show_neutronsource')
    end)
end)

-- =========================================
-- CLIENT CONVARS
-- =========================================
CreateClientConVar('lithos_rbmk_debug_enabled', '0', true, false)
CreateClientConVar('lithos_rbmk_debug_textscale', '0.2', true, false)
CreateClientConVar('lithos_rbmk_debug_textscale_cell', '0.2', true, false)
CreateClientConVar('lithos_rbmk_debug_textscale_flux', '0.1', true, false)
CreateClientConVar('lithos_rbmk_draw_flux_rays', '1', true, false)

CreateClientConVar('lithos_rbmk_show_fuel', '1', true, false)
CreateClientConVar('lithos_rbmk_show_control', '1', true, false)
CreateClientConVar('lithos_rbmk_show_autorod', '1', true, false)
CreateClientConVar('lithos_rbmk_show_reflector', '1', true, false)
CreateClientConVar('lithos_rbmk_show_absorber', '1', true, false)
CreateClientConVar('lithos_rbmk_show_blank', '0', true, false)
CreateClientConVar('lithos_rbmk_show_steam', '1', true, false)
CreateClientConVar('lithos_rbmk_show_neutronsource', '1', true, false)