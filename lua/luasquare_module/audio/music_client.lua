if not CLIENT then return end
LUASQUARE_AUDIO = LUASQUARE_AUDIO or {}
local AUDIO = LUASQUARE_AUDIO

AUDIO.MusicChannels = AUDIO.MusicChannels or {}
local function valid(channel) return channel and channel.IsValid and channel:IsValid() end

local function stopRecord(record)
    if record and valid(record.channel) then record.channel:Stop() end
    if record then record.channel = nil end
end

local function desiredPosition(state, sound)
    local position = math.max(tonumber(state.offset) or 0, 0)
    local rate = math.max(tonumber(state.playbackRate) or 1, 0.001)
    if state.status == 'playing' then
        position = position + math.max(CurTime() - (tonumber(state.startedAt) or CurTime()), 0) * rate
    end
    local duration = sound and tonumber(sound.duration) or 0
    if duration > 0 then position = state.loop and position % duration or math.min(position, duration) end
    return position
end

local function loadBus(busId, state)
    local definition = AUDIO.ClientCatalog.sounds and AUDIO.ClientCatalog.sounds[state.soundId]
    if not definition or definition.mode ~= 'music' then return end
    local old = AUDIO.MusicChannels[busId]
    if old then stopRecord(old) end
    local record = {
        busId = busId, state = state, sound = definition,
        token = tostring({}), loading = true, volume = 0
    }
    AUDIO.MusicChannels[busId] = record
    local token = record.token
    sound.PlayFile('sound/' .. definition.path, 'noplay noblock', function(channel, errorId, errorName)
        if AUDIO.MusicChannels[busId] ~= record or record.token ~= token then
            if valid(channel) then channel:Stop() end
            return
        end
        record.loading = false
        if not valid(channel) then
            record.error = tostring(errorName or errorId or 'unable to load music')
            return
        end
        record.channel = channel
        channel:EnableLooping(state.loop and true or false)
        channel:SetTime(desiredPosition(state, definition))
        channel:SetVolume(0)
    end)
end

function AUDIO.ApplyMusicState(busId, state, fadeSeconds)
    busId = AUDIO.NormalizeId(busId)
    if not busId then return end
    local record = AUDIO.MusicChannels[busId]
    if type(state) ~= 'table' then
        AUDIO.ClientMusicStates[busId] = nil
        if record and (tonumber(fadeSeconds) or 0) > 0 then
            record.fading = true record.fadeStarted = RealTime()
            record.fadeDuration = tonumber(fadeSeconds) record.fadeFrom = record.volume or 0
        elseif record then stopRecord(record) AUDIO.MusicChannels[busId] = nil end
        return
    end
    AUDIO.ClientMusicStates[busId] = state
    if not record or record.sound.id ~= state.soundId then loadBus(busId, state) return end
    record.state, record.fading = state, false
    if valid(record.channel) then
        record.channel:EnableLooping(state.loop and true or false)
        record.channel:SetTime(desiredPosition(state, record.sound))
    end
end

function AUDIO.ApplyMusicSnapshot(states)
    for busId in pairs(AUDIO.MusicChannels) do
        if not states[busId] then AUDIO.ApplyMusicState(busId, nil, 0) end
    end
    for busId, state in pairs(states) do AUDIO.ApplyMusicState(busId, state, 0) end
end

local lastCurTime, lastRealTime = CurTime(), RealTime()
local clockFrozen = false
local function updateClock()
    local currentCur, currentReal = CurTime(), RealTime()
    local realDelta, curDelta = currentReal - lastRealTime, currentCur - lastCurTime
    if realDelta > 0.12 then clockFrozen = math.abs(curDelta) < 0.001 end
    lastCurTime, lastRealTime = currentCur, currentReal
end

local function userMusicVolume()
    local own = GetConVar('luasquare_audio_music_volume')
    local gameMusic = GetConVar('snd_musicvolume')
    return math.Clamp(own and own:GetFloat() or 1, 0, 1)
        * math.Clamp(gameMusic and gameMusic:GetFloat() or 1, 0, 1)
end

local function targetVolume(record)
    local state = record.state
    local duck = AUDIO.GetSubtitleDuckFactor and AUDIO.GetSubtitleDuckFactor() or 1
    return math.Clamp((record.sound.volume or 1) * (state.volume or 1)
        * (state.busVolume or 1) * userMusicVolume() * duck, 0, 1)
end

hook.Add('Think', 'LUASQUARE_AUDIO_UpdateMusic', function()
    updateClock()
    for busId, record in pairs(AUDIO.MusicChannels) do
        if not record.loading and not valid(record.channel) then
            AUDIO.MusicChannels[busId] = nil
        elseif valid(record.channel) then
            if record.fading then
                local fraction = math.Clamp((RealTime() - record.fadeStarted) / math.max(record.fadeDuration, 0.01), 0, 1)
                record.volume = Lerp(fraction, record.fadeFrom, 0)
                record.channel:SetVolume(record.volume)
                if fraction >= 1 then stopRecord(record) AUDIO.MusicChannels[busId] = nil end
            else
                local state = record.state
                local shouldPlay = state.status == 'playing' and not clockFrozen
                local rate = math.Clamp(tonumber(state.playbackRate) or 1, 0.001, 8)
                if record.playbackRate ~= rate then
                    local ok = pcall(record.channel.SetPlaybackRate, record.channel, rate)
                    record.playbackRate = ok and rate or 1
                end
                local desired = desiredPosition(state, record.sound)
                local actual = tonumber(record.channel:GetTime()) or 0
                if math.abs(actual - desired) > 0.25 then pcall(record.channel.SetTime, record.channel, desired) end
                local volume = targetVolume(record)
                if volume < (record.volume or 0) then record.volume = volume
                else record.volume = math.Approach(record.volume or 0, volume, FrameTime() * 4) end
                record.channel:SetVolume(record.volume)
                if shouldPlay and not record.playing then record.channel:Play() record.playing = true
                elseif not shouldPlay and record.playing then record.channel:Pause() record.playing = false end
            end
        end
    end
end)

function AUDIO.ClientReset()
    for _, record in pairs(AUDIO.MusicChannels) do stopRecord(record) end
    AUDIO.MusicChannels, AUDIO.ClientMusicStates = {}, {}
    if AUDIO.ClientClearSubtitles then AUDIO.ClientClearSubtitles() end
end
