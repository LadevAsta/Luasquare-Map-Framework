-- Reactor-specific capabilities are installed against an explicit core, never a
-- process-global current reactor. Source-defined graphs use {component, port}.
return function(core)
    local ENDPOINT = LUASQUARE_ENDPOINT
    if not ENDPOINT then return {} end
    local releases, ports = core.EndpointReleases, {}
    local function register(port, definition)
        ports[port] = definition
        releases[#releases + 1] = ENDPOINT.Register(core.Id, port, definition)
    end
    local function fluid(amountKey, temperatureKey, capacityKey, defaultTemperature)
        local function restore(amount, temperature)
            local moved = math.min(math.max(amount, 0), math.max((core[capacityKey] or 0) - (core[amountKey] or 0), 0))
            core[temperatureKey] = core.MixTemperature(core[amountKey], core[temperatureKey], moved, temperature or defaultTemperature)
            core[amountKey] = core[amountKey] + moved
            core.UpdateRPVPressure()
            return moved
        end
        return {
            snapshot = function()
                return {amount = core[amountKey], temperature = core[temperatureKey], pressure = core.GetRPVPressure(),
                    levelPercent = math.Clamp((core[amountKey] or 0) / math.max(core[capacityKey] or 0, 0.0001) * 100, 0, 100)}
            end,
            remove = function(amount)
                local moved = math.min(math.max(amount, 0), core[amountKey] or 0)
                core[amountKey] = core[amountKey] - moved
                core.UpdateRPVPressure()
                return moved
            end,
            restore = restore,
            add = function(amount, _, temperature) return restore(amount, temperature) end
        }
    end
    local water = fluid('Water', 'WaterTemperature', 'MaxWater', 20)
    water.add = core.AddWaterFromPump
    register('water', water)
    register('steam', fluid('Steam', 'SteamTemperature', 'HardMaxSteam', 100))
    register('recirculation', {snapshot = water.snapshot, add = core.AddRecirculationWater})
    register('thermal', {snapshot = function() return {thermalMW = (core.LastThermalMW or 0) + (core.LastFlashBoilMW or 0)} end})
    core.EndpointPorts = ports
    return releases
end
