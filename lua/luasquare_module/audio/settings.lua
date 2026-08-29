if not CLIENT then return end

CreateClientConVar('luasquare_audio_music_volume', '1', true, false, 'Luasquare music volume', 0, 1)
CreateClientConVar('luasquare_audio_subtitles_enabled', '1', true, false, 'Show Luasquare subtitles')
CreateClientConVar('luasquare_audio_subtitle_max', '3', true, false, 'Maximum Luasquare subtitle groups', 1, 3)
CreateClientConVar('luasquare_audio_ducking_enabled', '1', true, false, 'Duck Luasquare music for subtitles')

hook.Add('PopulateToolMenu', 'LUASQUARE_AUDIO_Settings', function()
    spawnmenu.AddToolMenuOption('Options', 'Luasquare', 'LuasquareAudio', 'Audio System', '', '', function(panel)
        panel:Clear()
        panel:Help('Client-side Luasquare audio and subtitle settings')
        panel:NumSlider('Music volume', 'luasquare_audio_music_volume', 0, 1, 2)
        panel:CheckBox('Show subtitles', 'luasquare_audio_subtitles_enabled')
        panel:NumSlider('Maximum subtitle groups', 'luasquare_audio_subtitle_max', 1, 3, 0)
        panel:CheckBox('Duck music during subtitles', 'luasquare_audio_ducking_enabled')
    end)
end)
