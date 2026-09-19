local MAP = LUASQUARE_MAP

local function invoke(instance, definition, method, node, object)
    local callback = definition[method]
    if not callback then return true end
    local ok, result, reason = pcall(callback, instance, node, object)
    if not ok or result == false then return false, tostring(not ok and result or reason or method .. ' rejected') end
    return true, result
end

function MAP.Destroy(id, reason)
    local instance = type(id) == 'table' and id or MAP.Instances[id]
    if not instance or instance.destroyed then return true end
    instance.running, instance.destroyed = false, true
    instance.reason = reason or 'destroy'
    local function release(phase)
        for index = #instance.releases, 1, -1 do
            local entry = instance.releases[index]
            if entry.phase == phase then
                local ok, err = pcall(entry.callback)
                if not ok then instance.diagnostics[#instance.diagnostics + 1] = {path = 'release.' .. phase, message = tostring(err)} end
            end
        end
    end
    -- Consumers stop while their owners exist. Stop callbacks may still need
    -- entity registries and core state; release those only after all stops.
    release('consumers')
    for _, method in ipairs({'stop', 'destroy'}) do
        for index = #instance.created, 1, -1 do
            local node = instance.nodes[instance.created[index]] or instance.compiled.nodes[instance.created[index]]
            local ok, err = invoke(instance, MAP.Types[node.type], method, node, instance.objects[node.id])
            if not ok then instance.diagnostics[#instance.diagnostics + 1] = {source = node.source, path = node.id .. '.' .. method, message = err} end
        end
        if method == 'stop' then release('resources') end
    end
    instance.objects = {}
    if MAP.Instances[instance.id] == instance then MAP.Instances[instance.id] = nil end
    if MAP.ResetInspection then MAP.ResetInspection() end
    return #instance.diagnostics == 0, instance.diagnostics
end

function MAP.StopAll(reason)
    local instances = {}
    for _, instance in pairs(MAP.Instances) do instances[#instances + 1] = instance end
    for _, instance in ipairs(instances) do MAP.Destroy(instance, reason) end
end

-- Constructors register rollback resources before allocating anything that can
-- outlive a failed constructor. Release callbacks run even if construction throws.
function MAP.Create(compiled)
    if type(compiled) ~= 'table' or not MAP.IsId(compiled.id) then return nil, 'compiled map required' end
    if next(MAP.Instances) then return nil, 'a map instance already exists; reload the map to replace it' end
    local instance = {id = compiled.id, compiled = compiled, nodes = {}, objects = {}, created = {}, releases = {}, diagnostics = {}, running = false}
    function instance:Own(release, phase)
        assert(type(release) == 'function', 'release callback required')
        phase = phase or 'resources'
        assert(phase == 'resources' or phase == 'consumers', 'invalid release phase')
        self.releases[#self.releases + 1] = {callback = release, phase = phase}
    end
    function instance:Get(id) return self.objects[id] end
    MAP.Instances[instance.id] = instance
    local function failed(node, phase, err)
        instance.diagnostics[#instance.diagnostics + 1] = {source = node and node.source, path = (node and node.id or instance.id) .. '.' .. phase, message = err}
        MAP.Destroy(instance, 'startup failed')
        MAP.LastDiagnostics = instance.diagnostics
        return nil, MAP.DiagnosticsText(instance.diagnostics)
    end
    for _, id in ipairs(compiled.order) do
        local node = MAP.Copy(compiled.nodes[id])
        instance.nodes[id] = node
        for field, ref in pairs(node.derived or {}) do
            local object = instance:Get(ref.component)
            local value = object and object[ref.field]
            if not MAP.Finite(value) then return failed(node, 'derive', 'capacity unavailable: ' .. ref.component .. '.' .. ref.field) end
            local result, err = MAP.ValidateValue(MAP.Types[node.type].fields[field], value * ref.scale + ref.offset, field)
            if err then return failed(node, 'derive', err) end
            node.config[field] = result
        end
        instance.created[#instance.created + 1] = id
        local ok, object = invoke(instance, MAP.Types[node.type], 'create', node)
        if not ok then return failed(node, 'create', object) end
        instance.objects[id] = type(object) == 'table' and object or {}
    end
    for _, phase in ipairs({'link', 'initialize', 'register', 'validate'}) do
        for _, id in ipairs(compiled.order) do
            local node = instance.nodes[id]
            local ok, err = invoke(instance, MAP.Types[node.type], phase, node, instance.objects[id])
            if not ok then return failed(node, phase, err) end
        end
    end
    if MAP.DescribeTelemetry then
        for id in pairs(instance.telemetry or {}) do
            for _, namespace in pairs({display = LUASQUARE_3D2D, annunciator = LUASQUARE_ANNUNCIATOR}) do
                local provider = namespace and namespace.DataProviders and namespace.DataProviders[id]
                if provider then provider.fields = MAP.DescribeTelemetry(instance, id) end
            end
        end
    end
    if MAP.ActivateSources then
        local ok, result, err = pcall(MAP.ActivateSources, instance)
        if not ok or result == false then return failed(nil, 'sources', tostring(not ok and result or err)) end
    elseif next(compiled.sources) then return failed(nil, 'sources', 'source adapters unavailable') end
    local activation = MAP.Copy(compiled.order)
    table.sort(activation, function(a, b)
        local first, second = MAP.Types[instance.nodes[a].type].startOrder or 20, MAP.Types[instance.nodes[b].type].startOrder or 20
        if first == second then return a < b end
        return first < second
    end)
    for _, id in ipairs(activation) do
        local node = instance.nodes[id]
        local ok, err = invoke(instance, MAP.Types[node.type], 'start', node, instance.objects[id])
        if not ok then return failed(node, 'start', err) end
    end
    instance.running = true
    if LUASQUARE_POWERPLANT and LUASQUARE_POWERPLANT.Debug and LUASQUARE_POWERPLANT.Debug.Start then
        instance:Own(function() timer.Remove('LUASQUARE_POWERPLANT_DebugTimer') end, 'consumers')
        local ok, err = pcall(LUASQUARE_POWERPLANT.Debug.Start)
        if not ok then return failed(nil, 'debug', tostring(err)) end
    end
    MAP.LastDiagnostics = {}
    if MAP.ResetInspection then MAP.ResetInspection() end
    return instance
end

function MAP.ReadSource(family, path, budget)
    local fullPath = MAP.SourcePath(family, path)
    if not fullPath then return nil, 'invalid source path' end
    local bytes = file.Size(fullPath, 'GAME')
    if not bytes or bytes < 0 or bytes > MAP.Limits.bytes then return nil, fullPath .. ': missing or excessive source' end
    if budget then
        budget.bytes = (budget.bytes or 0) + bytes
        if budget.bytes > MAP.Limits.totalBytes then return nil, 'total source size exceeded' end
    end
    local text = file.Read(fullPath, 'GAME')
    if not text or #text > MAP.Limits.bytes then return nil, fullPath .. ': read failed' end
    local source, err = MAP.DecodeJSON(text)
    if not source then return nil, fullPath .. ': ' .. tostring(err) end
    return source
end

function MAP.Load(path)
    local budget = {}
    local manifest, err = MAP.ReadSource('map', path, budget)
    if not manifest then return nil, err end
    if not MAP.IsArray(manifest.packages) or #manifest.packages > MAP.Limits.packs then return nil, 'invalid package list' end
    local selected, loading = {}, {}
    for _, entry in ipairs(manifest.packages) do
        local id = type(entry) == 'string' and entry or type(entry) == 'table' and entry.id
        if not MAP.IsId(id) or selected[id] then return nil, 'invalid or duplicate package ID' end
        if not MAP.Packages[id] and not (type(entry) == 'table' and entry.optional == true) then return nil, 'required package unavailable: ' .. id end
        selected[id] = true
    end
    local function loadPackage(id)
        local package = MAP.Packages[id]
        if package and not package.loaded then
            if loading[id] then return false, 'trusted package dependency cycle: ' .. id end
            loading[id] = true
            for _, dependency in ipairs(package.requires or {}) do
                if not selected[dependency] then return false, id .. ': required package not selected: ' .. dependency end
                local ok, err = loadPackage(dependency)
                if not ok then return false, err end
            end
            MAP.LoadingPackages = true
            local ok, result = pcall(package.load or function() end)
            MAP.LoadingPackages = nil
            if not ok or result == false then return false, 'package load failed: ' .. tostring(id) .. ': ' .. tostring(result) end
            package.loaded = true
            loading[id] = nil
        end
        return true
    end
    for _, entry in ipairs(manifest.packages) do
        local ok, err = loadPackage(type(entry) == 'string' and entry or entry.id)
        if not ok then return nil, err end
    end
    if not MAP.IsArray(manifest.packs) or #manifest.packs > MAP.Limits.packs then return nil, 'invalid component pack list' end
    local packs = {}
    for _, packPath in ipairs(manifest.packs) do
        if packs[packPath] then return nil, 'duplicate source: ' .. packPath end
        local pack, problem = MAP.ReadSource('components', packPath, budget)
        if not pack then return nil, problem end
        packs[packPath] = pack
    end
    local compiled, diagnostics = MAP.Compile(manifest, packs, MAP.SourcePath('map', path))
    MAP.LastDiagnostics = diagnostics
    if not compiled then return nil, MAP.DiagnosticsText(diagnostics) end
    return MAP.Create(compiled)
end
