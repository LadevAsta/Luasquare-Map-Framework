if LITHOS_GAUGE_CORE_LOADED then return end
LITHOS_GAUGE_CORE_LOADED = true
LITHOS_GAUGE = LITHOS_GAUGE or {}
LITHOS_GAUGE.Gauges = LITHOS_GAUGE.Gauges or {}
LITHOS_GAUGE.Bindings = LITHOS_GAUGE.Bindings or {}
LITHOS_GAUGE.EntityCache = LITHOS_GAUGE.EntityCache or {}

LITHOS_GAUGE.TickInterval = 0.1

-- =========================================
-- ENTITY CACHE
-- =========================================
function LITHOS_GAUGE.GetEnt(name)
    local cached = LITHOS_GAUGE.EntityCache[name]
    if IsValid(cached) then return cached end
    local ent = ents.FindByName(name)[1]
    if IsValid(ent) then LITHOS_GAUGE.EntityCache[name] = ent end
    return ent
end

-- =========================================
-- REGISTER
-- =========================================
function LITHOS_GAUGE.RegisterGauge(name, data)
    if not data then
        print('[LITHOS_GAUGE] Missing data for gauge: ' .. tostring(name))
        return
    end

    LITHOS_GAUGE.Gauges[name] = {
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
function LITHOS_GAUGE.SetGauge(name, value)
    local gauge = LITHOS_GAUGE.Gauges[name]
    if not gauge then
        print('[LITHOS_GAUGE] Unknown gauge: ' .. tostring(name))
        return
    end

    if not gauge.entity then
        print('[LITHOS_GAUGE] Missing entity for gauge: ' .. tostring(name))
        return
    end

    local ent = LITHOS_GAUGE.GetEnt(gauge.entity)
    if not IsValid(ent) then
        print('[LITHOS_GAUGE] Missing entity: ' .. tostring(gauge.entity))
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
function LITHOS_GAUGE.BindGauge(name, getter)
    LITHOS_GAUGE.Bindings[name] = getter
end

-- =========================================
-- AUTO UPDATE LOOP
-- =========================================
function LITHOS_GAUGE.UpdateAll()
    for gaugeName, getter in pairs(LITHOS_GAUGE.Bindings) do
        local ok, value = pcall(getter)
        if ok then
            LITHOS_GAUGE.SetGauge(gaugeName, value)
        else
            print('[LITHOS_GAUGE] Getter failed for ' .. tostring(gaugeName))
            print(value)
        end
    end
end

-- =========================================
-- START UPDATE TIMER
-- =========================================
function LITHOS_GAUGE.Start()
    if timer.Exists('LITHOS_GAUGE_UpdateTimer') then timer.Remove('LITHOS_GAUGE_UpdateTimer') end
    timer.Create('LITHOS_GAUGE_UpdateTimer', LITHOS_GAUGE.TickInterval, 0, function() LITHOS_GAUGE.UpdateAll() end)
    print('[LITHOS_GAUGE] Started')
end

print('[LITHOS_GAUGE] Loaded')

-- =========================================
-- EXAMPLES
-- =========================================
-- include('lithos_module/gaugedisplay.lua')
--
-- LITHOS_GAUGE.RegisterGauge('rpv_water', {
--     entity = 'gauge_rpv_water',
--     min = 0,
--     max = 100,
--     speed = 64
-- })
-- LITHOS_GAUGE.BindGauge('rpv_water', function()
--     if not RBMK or not RBMK.MaxWater or RBMK.MaxWater <= 0 then return 0 end
--     return (RBMK.Water / RBMK.MaxWater) * 100
-- end)
--
-- LITHOS_GAUGE.RegisterGauge('rpv_steam', {
--     entity = 'gauge_rpv_steam',
--     min = 0,
--     max = 100,
--     speed = 64
-- })
-- LITHOS_GAUGE.BindGauge('rpv_steam', function()
--     if not RBMK or not RBMK.MaxSteam or RBMK.MaxSteam <= 0 then return 0 end
--     return (RBMK.Steam / RBMK.MaxSteam) * 100
-- end)
--
-- LITHOS_GAUGE.RegisterGauge('reactor_flux', {
--     entity = 'gauge_reactor_flux',
--     min = 0,
--     max = 1000,
--     speed = 64
-- })
-- LITHOS_GAUGE.BindGauge('reactor_flux', function()
--     if not RBMK then return 0 end
--     return RBMK.TotalFluxSubtracted or 0
-- end)
--
-- LITHOS_GAUGE.Start()
