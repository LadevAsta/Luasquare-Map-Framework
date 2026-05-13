if not CLIENT then return end
RBMK = RBMK or {}
RBMK.Debug = RBMK.Debug or {}
hook.Add('PopulateToolMenu', 'LITHOS_RBMK_Menu', function()
    spawnmenu.AddToolMenuOption('Options', 'Lithos', 'LithosRBMK', 'RBMK Framework', '', '', function(panel)
        panel:ClearControls()
        panel:Help('Lithos RBMK Debug Options')
        -- =========================================
        -- MASTER
        -- =========================================
        panel:CheckBox('Enable Debug', 'lithos_rbmk_debug_enabled')
        panel:NumSlider('Text Scale', 'lithos_rbmk_debug_textscale', 0.1, 2.0, 2)
        panel:NumSlider('Text Scale', 'lithos_rbmk_debug_textscale_cell', 0.1, 2.0, 2)
        -- =========================================
        -- CELL VISUALS
        -- =========================================
        panel:CheckBox('Draw Heat', 'lithos_rbmk_draw_heat')
        panel:CheckBox('Draw Flux', 'lithos_rbmk_draw_flux')
        panel:CheckBox('Draw Xenon', 'lithos_rbmk_draw_xenon')
        panel:CheckBox('Draw Flux Rays', 'lithos_rbmk_draw_flux_rays')
        -- =========================================
        -- CELL FILTERS
        -- =========================================
        panel:CheckBox('Show Blank Cells', 'lithos_rbmk_show_blank')
        panel:CheckBox('Show Steam Channels', 'lithos_rbmk_show_steam')
    end)
end)

-- =========================================
-- CLIENT CONVARS
-- =========================================
CreateClientConVar('lithos_rbmk_debug_enabled', '1', true, false)
CreateClientConVar('lithos_rbmk_debug_textscale', '0.2', true, false)
CreateClientConVar('lithos_rbmk_debug_textscale_cell', '0.2', true, false)
CreateClientConVar('lithos_rbmk_draw_heat', '1', true, false)
CreateClientConVar('lithos_rbmk_draw_flux', '1', true, false)
CreateClientConVar('lithos_rbmk_draw_xenon', '1', true, false)
CreateClientConVar('lithos_rbmk_draw_flux_rays', '1', true, false)
CreateClientConVar('lithos_rbmk_show_blank', '0', true, false)
CreateClientConVar('lithos_rbmk_show_steam', '1', true, false)