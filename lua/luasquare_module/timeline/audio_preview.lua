if not CLIENT then return end
LUASQUARE_TIMELINE = LUASQUARE_TIMELINE or {}
local TIMELINE = LUASQUARE_TIMELINE

local Audio = {}
Audio.__index = Audio

function TIMELINE.CreateAudioPreview()
    return setmetatable({
        channel = nil,
        path = nil,
        volume = 1,
        timelineStartSeconds = 0,
        pendingTime = 0,
        playing = false,
        channelPlaying = false,
        loading = false,
        error = nil
    }, Audio)
end

function Audio:IsValid()
    return self.channel and self.channel.IsValid and self.channel:IsValid()
end

function Audio:Load(definition, callback)
    self:Stop()
    definition = definition or {}
    local path = tostring(definition.path or '')
    if not TIMELINE.IsSafePath(path) then
        self.error = 'Unsafe or empty audio path.'
        if callback then callback(false, self.error) end
        return false
    end
    self.path = path
    self.volume = TIMELINE.Clamp(definition.volume or 1, 0, 1)
    self.timelineStartSeconds = tonumber(definition.timelineStartSeconds) or 0
    self.loading = true
    sound.PlayFile(path, 'noplay noblock', function(channel, errorId, errorName)
        self.loading = false
        if not channel or not channel.IsValid or not channel:IsValid() then
            self.error = tostring(errorName or errorId or 'Unable to load audio.')
            if callback then callback(false, self.error) end
            return
        end
        self.channel = channel
        self.error = nil
        channel:SetVolume(self.volume)
        self:SeekTimeline(self.pendingTime)
        if self.playing then channel:Play() end
        if callback then callback(true) end
    end)
    return true
end

function Audio:SeekTimeline(playhead)
    self.pendingTime = tonumber(playhead) or 0
    if not self:IsValid() then return false end
    local audioTime = math.max(self.pendingTime - self.timelineStartSeconds, 0)
    local length = tonumber(self.channel:GetLength()) or 0
    if length > 0 then audioTime = math.min(audioTime, length) end
    self.channel:SetTime(audioTime)
    self.channel:SetVolume(self.pendingTime < self.timelineStartSeconds and 0 or self.volume)
    return true
end

function Audio:SetVolume(volume)
    self.volume = TIMELINE.Clamp(volume or 1, 0, 1)
    if self:IsValid() then self.channel:SetVolume(self.volume) end
end

function Audio:Play(playhead)
    self.playing = true
    if playhead ~= nil then self:SeekTimeline(playhead) end
    if self:IsValid() and self.pendingTime >= self.timelineStartSeconds then
        self.channel:SetVolume(self.volume)
        self.channel:Play()
        self.channelPlaying = true
        return true
    end
    return false
end

function Audio:Pause()
    self.playing = false
    self.channelPlaying = false
    if self:IsValid() then self.channel:Pause() return true end
    return false
end

function Audio:Stop()
    self.playing = false
    self.loading = false
    self.channelPlaying = false
    if self:IsValid() then self.channel:Stop() end
    self.channel = nil
end

function Audio:Update(playhead, playing)
    self.pendingTime = tonumber(playhead) or 0
    self.playing = playing and true or false
    if not self:IsValid() then return false end
    if self.pendingTime < self.timelineStartSeconds then
        if self.channelPlaying then self.channel:Pause() end
        self.channelPlaying = false
        self.channel:SetVolume(0)
        self.channel:SetTime(0)
        return true
    end
    local target = math.max(self.pendingTime - self.timelineStartSeconds, 0)
    local current = tonumber(self.channel:GetTime()) or 0
    if math.abs(current - target) > 0.25 then self.channel:SetTime(target) end
    self.channel:SetVolume(self.volume)
    if self.playing and not self.channelPlaying then
        self.channel:Play()
        self.channelPlaying = true
    elseif not self.playing and self.channelPlaying then
        self.channel:Pause()
        self.channelPlaying = false
    end
    return true
end

function Audio:GetLength()
    return self:IsValid() and (tonumber(self.channel:GetLength()) or 0) or 0
end
