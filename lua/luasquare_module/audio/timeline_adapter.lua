if not SERVER then return end

LUASQUARE_AUDIO = LUASQUARE_AUDIO or {}
local AUDIO = LUASQUARE_AUDIO

AUDIO.TimelineComponents = AUDIO.TimelineComponents or {}

local function sortedChoices(definitions, predicate)
    local choices = {}
    for id, definition in pairs(definitions or {}) do
        if not predicate or predicate(definition) then table.insert(choices, id) end
    end
    table.sort(choices)
    return choices
end

local function enumParameter(id, label, choices)
    return {id = id, label = label, type = 'enum', choices = choices, default = choices[1]}
end

local function ownerFor(run)
    return 'timeline:' .. tostring(run and run.runId or 'audio')
end

local function musicAvailableFor(run, busId)
    local state = AUDIO.MusicStates[busId]
    return not run or not run.preview or not state or state.ownerId == ownerFor(run)
end

local function unregisterOld(active)
    if not LUASQUARE_TIMELINE then return end
    for id in pairs(AUDIO.TimelineComponents) do
        if not active[id] then LUASQUARE_TIMELINE.UnregisterComponent(id) end
    end
    AUDIO.TimelineComponents = active
end

local function registerMusic(active)
    for busId, bus in pairs(AUDIO.Catalog.musicBuses or {}) do
        local musicChoices = sortedChoices(AUDIO.Catalog.sounds, function(sound)
            return sound.mode == 'music' and (#(sound.musicBuses or {}) == 0
                or table.HasValue(sound.musicBuses, busId))
        end)
        local componentId = 'audio.music:' .. busId
        local actions = {
            pause = {
                kind = 'marker', label = 'Pause', seekPolicy = 'apply',
                execute = function(_, _, _, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.PauseMusic(busId)
                end,
                seek = function(_, _, _, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.PauseMusic(busId)
                end
            },
            resume = {
                kind = 'marker', label = 'Resume', seekPolicy = 'apply',
                execute = function(_, _, _, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.ResumeMusic(busId)
                end,
                seek = function(_, _, _, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.ResumeMusic(busId)
                end
            },
            seek = {
                kind = 'marker', label = 'Seek', seekPolicy = 'apply',
                parameters = {{id = 'seconds', label = 'Seconds', type = 'number', default = 0,
                    min = 0, max = 86400, decimals = 3, unit = 's'}},
                execute = function(_, params, _, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.SeekMusic(busId, params.seconds)
                end,
                seek = function(_, params, _, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.SeekMusic(busId, params.seconds)
                end
            },
            stop = {
                kind = 'marker', label = 'Stop', seekPolicy = 'apply',
                parameters = {{id = 'fade', label = 'Fade', type = 'number', default = 0,
                    min = 0, max = 30, decimals = 2, unit = 's'}},
                execute = function(_, params, _, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.StopMusic(busId, params.fade)
                end,
                seek = function(_, params, _, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.StopMusic(busId, params.fade)
                end
            },
            volume = {
                kind = 'number', label = 'Bus volume', seekPolicy = 'apply',
                min = 0, max = 1, decimals = 3, unit = 'ratio',
                set = function(_, _, value, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.SetMusicBusVolume(busId, value)
                end,
                seek = function(_, _, value, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.SetMusicBusVolume(busId, value)
                end
            }
        }
        if #musicChoices > 0 then
            actions.play = {
                kind = 'marker', label = 'Play', seekPolicy = 'apply',
                parameters = {
                    enumParameter('sound', 'Music', musicChoices),
                    {id = 'loop', label = 'Loop', type = 'boolean', default = false},
                    {id = 'volume', label = 'Volume', type = 'number', default = 1,
                        min = 0, max = 1, decimals = 3}
                },
                execute = function(_, params, _, run)
                    if not musicAvailableFor(run, busId) then return false end
                    return AUDIO.PlayMusic(busId, params.sound, {
                        loop = params.loop, volume = params.volume, ownerId = ownerFor(run)
                    })
                end,
                seek = function(_, params, _, run, clip)
                    local offset = math.max((tonumber(run and run.seekTo) or 0) - (tonumber(clip and clip.at) or 0), 0)
                    return AUDIO.PlayMusic(busId, params.sound, {
                        loop = params.loop, volume = params.volume, offset = offset, ownerId = ownerFor(run)
                    })
                end
            }
        end
        LUASQUARE_TIMELINE.RegisterComponent(componentId, {
            type = 'audio.music', label = 'Music: ' .. tostring(bus.label or busId), actions = actions,
            context = {busId = busId},
            safeReset = function(_, _, run)
                local state = AUDIO.MusicStates[busId]
                if state and state.ownerId == ownerFor(run) then AUDIO.StopMusic(busId, 0) end
                AUDIO.SetMusicBusVolume(busId, bus.volume)
                return true
            end,
            notes = 'Server-authoritative synchronized music bus.'
        })
        active[componentId] = true
    end
end

local function registerPA(active, lineChoices)
    for channelId, channel in pairs(AUDIO.Catalog.paChannels or {}) do
        local componentId = 'audio.pa:' .. channelId
        local actions = {
            clear = {
                kind = 'marker', label = 'Clear channel', seekPolicy = 'reject',
                execute = function(_, _, _, run)
                    local state = AUDIO.PAStates[channelId]
                    if run and run.preview and state and state.phase ~= 'idle'
                        and state.activeOwner ~= ownerFor(run) then return false end
                    return AUDIO.ClearPAChannel(channelId, 'timeline')
                end
            }
        }
        if #lineChoices > 0 then
            actions.enqueue = {
                kind = 'marker', label = 'Enqueue announcement', seekPolicy = 'reject',
                parameters = {
                    enumParameter('line', 'Line', lineChoices),
                    {id = 'priority', label = 'Priority', type = 'number', default = 0,
                        min = -1000, max = 1000, decimals = 0}
                },
                execute = function(_, params, _, run)
                    local state = AUDIO.PAStates[channelId]
                    if run and run.preview and state and state.phase ~= 'idle'
                        and state.activeOwner ~= ownerFor(run) then return false end
                    return AUDIO.EnqueuePA(channelId, params.line, {
                        priority = params.priority, ownerId = ownerFor(run)
                    })
                end
            }
        end
        LUASQUARE_TIMELINE.RegisterComponent(componentId, {
            type = 'audio.pa', label = 'PA: ' .. tostring(channel.label or channelId), actions = actions,
            context = {channelId = channelId},
            safeReset = function(_, _, run)
                AUDIO.ClearPAOwner(channelId, ownerFor(run), 'timeline preview reset')
                return true
            end,
            notes = 'Registered PA-line queue. Live preview cannot reconstruct a nonzero playhead.'
        })
        active[componentId] = true
    end
end

local function registerSoundscapes(active)
    for groupId, group in pairs(AUDIO.Catalog.soundscapeGroups or {}) do
        local componentId = 'audio.soundscape:' .. groupId
        local states = sortedChoices(group.states)
        local actions = {}
        if #states > 0 then
            actions.set_state = {
                kind = 'marker', label = 'Set state', seekPolicy = 'apply',
                parameters = {enumParameter('state', 'State', states)},
                execute = function(_, params) return AUDIO.SetSoundscapeState(groupId, params.state) end,
                seek = function(_, params) return AUDIO.SetSoundscapeState(groupId, params.state) end
            }
        end
        actions.reset = {
            kind = 'marker', label = 'Reset group', seekPolicy = 'apply',
            execute = function() return AUDIO.ResetSoundscapeGroup(groupId) end,
            seek = function() return AUDIO.ResetSoundscapeGroup(groupId) end
        }
        LUASQUARE_TIMELINE.RegisterComponent(componentId, {
            type = 'audio.soundscape', label = 'Soundscape: ' .. tostring(group.label or groupId),
            actions = actions, context = {groupId = groupId},
            safeReset = function() AUDIO.ResetSoundscapeGroup(groupId) return true end
        })
        active[componentId] = true
    end
end

local function registerAmbient(active, globalChoices)
    local componentId = 'audio.ambient'
    local actions = {
        stop_owner = {
            kind = 'marker', label = 'Stop timeline sounds', seekPolicy = 'reject',
            execute = function(_, _, _, run) AUDIO.StopOwnerSounds(ownerFor(run)) return true end
        }
    }
    if #globalChoices > 0 then
        actions.play = {
            kind = 'marker', label = 'Play global sound', seekPolicy = 'reject',
            parameters = {enumParameter('sound', 'Sound', globalChoices)},
            execute = function(_, params, _, run)
                return AUDIO.PlaySound(params.sound, {ownerId = ownerFor(run)})
            end
        }
        actions.stop = {
            kind = 'marker', label = 'Stop registered sound', seekPolicy = 'reject',
            parameters = {enumParameter('sound', 'Sound', globalChoices)},
            execute = function(_, params, _, run)
                return AUDIO.StopSound(params.sound, {ownerId = ownerFor(run)})
            end
        }
    end
    LUASQUARE_TIMELINE.RegisterComponent(componentId, {
        type = 'audio.ambient', label = 'Global Source audio', actions = actions,
        safeReset = function(_, _, run) AUDIO.StopOwnerSounds(ownerFor(run)) return true end,
        notes = 'Source audio cannot safely reconstruct playback from a nonzero playhead.'
    })
    active[componentId] = true
end

function AUDIO.RegisterTimelineComponents()
    if not LUASQUARE_TIMELINE or not LUASQUARE_TIMELINE.RegisterComponent then return 0 end
    local active = {}
    local globalChoices = sortedChoices(AUDIO.Catalog.sounds,
        function(sound) return sound.mode == 'global' end)
    local lineChoices = sortedChoices(AUDIO.Catalog.paLines)
    registerMusic(active)
    registerPA(active, lineChoices)
    registerSoundscapes(active)
    registerAmbient(active, globalChoices)
    unregisterOld(active)
    return table.Count(active)
end
