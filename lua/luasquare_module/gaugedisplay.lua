if LUASQUARE_GAUGE_CORE_LOADED then return end
LUASQUARE_GAUGE_CORE_LOADED = true
LUASQUARE_GAUGE = LUASQUARE_GAUGE or {}
LUASQUARE_GAUGE.Gauges = LUASQUARE_GAUGE.Gauges or {}
LUASQUARE_GAUGE.Bindings = LUASQUARE_GAUGE.Bindings or {}
LUASQUARE_GAUGE.EntityCache = LUASQUARE_GAUGE.EntityCache or {}

LUASQUARE_GAUGE.TickInterval = 0.1

-- =========================================
-- ENTITY CACHE
-- =========================================
function LUASQUARE_GAUGE.GetEnt(name)
    local cached = LUASQUARE_GAUGE.EntityCache[name]
    if IsValid(cached) then return cached end
    local ent = ents.FindByName(name)[1]
    if IsValid(ent) then LUASQUARE_GAUGE.EntityCache[name] = ent end
    return ent
end

-- =========================================
-- REGISTER
-- =========================================
function LUASQUARE_GAUGE.RegisterGauge(name, data)
    if not data then
        print('[LUASQUARE_GAUGE] Missing data for gauge: ' .. tostring(name))
        return
    end

    LUASQUARE_GAUGE.Gauges[name] = {
        entity = data.entity,
        min = tonumber(data.min) or 0,
        max = tonumber(data.max) or 100,
        invert = data.invert and true or false,
        speed = data.speed
    }
end

-- =========================================
-- SET GAUGE
-- =========================================
function LUASQUARE_GAUGE.SetGauge(name, value)
    local gauge = LUASQUARE_GAUGE.Gauges[name]
    if not gauge then
        print('[LUASQUARE_GAUGE] Unknown gauge: ' .. tostring(name))
        return
    end

    if not gauge.entity then
        print('[LUASQUARE_GAUGE] Missing entity for gauge: ' .. tostring(name))
        return
    end

    local ent = LUASQUARE_GAUGE.GetEnt(gauge.entity)
    if not IsValid(ent) then
        print('[LUASQUARE_GAUGE] Missing entity: ' .. tostring(gauge.entity))
        return
    end

    value = tonumber(value) or 0
    local range = gauge.max - gauge.min
    local position = 0
    if range ~= 0 then position = (value - gauge.min) / range end
    position = math.Clamp(position, 0, 1)
    if gauge.invert then position = 1 - position end

    if gauge.speed ~= nil then ent:Fire('SetSpeed', tostring(gauge.speed)) end
    ent:Fire('SetPosition', tostring(position))
end

-- =========================================
-- BIND LIVE VALUE
-- =========================================
function LUASQUARE_GAUGE.BindGauge(name, getter)
    LUASQUARE_GAUGE.Bindings[name] = getter
end

-- =========================================
-- AUTO UPDATE LOOP
-- =========================================
function LUASQUARE_GAUGE.UpdateAll()
    for gaugeName, getter in pairs(LUASQUARE_GAUGE.Bindings) do
        local ok, value = pcall(getter)
        if ok then
            LUASQUARE_GAUGE.SetGauge(gaugeName, value)
        else
            print('[LUASQUARE_GAUGE] Getter failed for ' .. tostring(gaugeName))
            print(value)
        end
    end
end

-- =========================================
-- START UPDATE TIMER
-- =========================================
function LUASQUARE_GAUGE.Start()
    if timer.Exists('LUASQUARE_GAUGE_UpdateTimer') then timer.Remove('LUASQUARE_GAUGE_UpdateTimer') end
    timer.Create('LUASQUARE_GAUGE_UpdateTimer', LUASQUARE_GAUGE.TickInterval, 0, function() LUASQUARE_GAUGE.UpdateAll() end)
    print('[LUASQUARE_GAUGE] Started')
end

print('[LUASQUARE_GAUGE] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- include('luasquare_module/gaugedisplay.lua')
--
-- LUASQUARE_GAUGE.RegisterGauge('rpv_water', {
--     entity = 'gauge_rpv_water',
--     min = 0,
--     max = 100,
--     speed = 64
-- })
-- LUASQUARE_GAUGE.BindGauge('rpv_water', function()
--     if not RBMK or not RBMK.MaxWater or RBMK.MaxWater <= 0 then return 0 end
--     return (RBMK.Water / RBMK.MaxWater) * 100
-- end)
--
-- LUASQUARE_GAUGE.RegisterGauge('rpv_steam', {
--     entity = 'gauge_rpv_steam',
--     min = 0,
--     max = 100,
--     speed = 64
-- })
-- LUASQUARE_GAUGE.BindGauge('rpv_steam', function()
--     if not RBMK or not RBMK.MaxSteam or RBMK.MaxSteam <= 0 then return 0 end
--     return (RBMK.Steam / RBMK.MaxSteam) * 100
-- end)
--
-- LUASQUARE_GAUGE.RegisterGauge('reactor_flux', {
--     entity = 'gauge_reactor_flux',
--     min = 0,
--     max = 1000,
--     speed = 64
-- })
-- LUASQUARE_GAUGE.BindGauge('reactor_flux', function()
--     if not RBMK then return 0 end
--     return RBMK.TotalFluxSubtracted or 0
-- end)
--
-- LUASQUARE_GAUGE.Start()
