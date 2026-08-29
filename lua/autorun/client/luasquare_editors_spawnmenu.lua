if not CLIENT then return end

hook.Add('PopulateToolMenu', 'LUASQUARE_EditorsMenu', function()
    spawnmenu.AddToolMenuOption('Options', 'Luasquare', 'LuasquareEditors', 'Editors', '', '', function(panel)
        panel:ClearControls()
        panel:Help('JSON-backed Luasquare authoring tools. Drafts are written under data/ for export.')

        panel:Button('3D2D Display Editor').DoClick = function()
            if LUASQUARE_3D2D and LUASQUARE_3D2D.Editor then LUASQUARE_3D2D.Editor.Open() end
        end
        panel:Button('3D2D Theme Editor').DoClick = function()
            if not LUASQUARE_3D2D or not LUASQUARE_3D2D.Editor then return end
            local displayEditor = LUASQUARE_3D2D.Editor.Open()
            if IsValid(displayEditor) and LUASQUARE_3D2D.Editor.OpenThemeEditor then
                LUASQUARE_3D2D.Editor.OpenThemeEditor(displayEditor)
            end
        end
        panel:Button('Timeline Editor').DoClick = function()
            if LUASQUARE_TIMELINE and LUASQUARE_TIMELINE.Editor then LUASQUARE_TIMELINE.Editor.Open() end
        end

        panel:Help('Audio registry editors use client-local previews and never enter the server playback queues.')
        panel:Button('Sound Registry Editor').DoClick = function()
            if LUASQUARE_AUDIO and LUASQUARE_AUDIO.OpenSoundRegistryEditor then LUASQUARE_AUDIO.OpenSoundRegistryEditor() end
        end
        panel:Button('Subtitle Sequence Editor').DoClick = function()
            if LUASQUARE_AUDIO and LUASQUARE_AUDIO.OpenSubtitleSequenceEditor then LUASQUARE_AUDIO.OpenSubtitleSequenceEditor() end
        end
        panel:Button('PA Editor').DoClick = function()
            if LUASQUARE_AUDIO and LUASQUARE_AUDIO.OpenPAEditor then LUASQUARE_AUDIO.OpenPAEditor() end
        end
    end)
end)
