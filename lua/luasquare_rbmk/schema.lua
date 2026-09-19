-- Shared structural validation. No entities, simulation or gameplay callbacks.
local MAP = LUASQUARE_MAP
MAP.Validators = MAP.Validators or {}
MAP.Validators['rbmk.core'] = function(node, compiled)
    local config, coordinates, names = node.config, {}, {}
    local fuels = {EMPTY = true, MEU = true, MOX = true, HEU = true, WGU = true, XEN = true, YME = true, YMX = true}
    for _, preset in ipairs(config.fuelPresets) do
        if preset.id == '' or fuels[preset.id] then return false, 'empty or duplicate fuel preset ID' end
        fuels[preset.id] = true
    end
    local function binding(id, profile)
        if not id then return true end
        local target = compiled.nodes[id]
        return target and target.type == 'source.binding' and target.config.profile == profile and #target.config.targets == 1
    end
    if config.blowoutValveCount > 0 and config.blowoutValvePrefix == '' then return false, 'blowout valve prefix is required' end
    for _, field in ipairs({'catastrophicRelay', 'fuelLeakRelay', 'fuelMeltdownRelay'}) do
        if not binding(config[field], 'relay') then return false, field .. ': expected relay Source binding' end
    end
    for _, cell in ipairs(config.cells) do
        local key = cell.x .. '/' .. cell.y
        if cell.x > config.width or cell.y > config.height or coordinates[key] then return false, 'duplicate or out-of-range cell: ' .. key end
        coordinates[key] = true
        if not binding(cell.indicator, 'sprite') or not binding(cell.visual, 'mover') then return false, 'cell visual/indicator requires matching Source binding' end
        if cell.kind == 'fuel' and not fuels[cell.fuel or 'MEU'] then return false, 'unknown fuel preset' end
        if cell.kind == 'control' then
            if not cell.name or names[cell.name] then return false, 'missing or duplicate rod name' end
            names[cell.name] = true
        end
    end
    for key, typeId in pairs({separator = 'plant.separator', steamNetwork = 'plant.fluid', drainNetwork = 'plant.fluid', grid = 'plant.grid', breaker = 'plant.breaker'}) do
        local id = config[key]
        if id and (not compiled.nodes[id] or compiled.nodes[id].type ~= typeId) then return false, key .. ': invalid plant reference' end
    end
    return true
end
