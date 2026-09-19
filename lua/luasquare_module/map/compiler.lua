local MAP = LUASQUARE_MAP
local families = {control = true, ['3d2display'] = true, timeline = true, audio = true, annunciator = true}

-- Pure compilation: the caller supplies already-read packs. No constructors, entity
-- discovery, package includes or gameplay callbacks run during editor validation.
function MAP.Compile(manifest, packs, origin)
    local diagnostics = {}
    local function fail(path, message, source)
        diagnostics[#diagnostics + 1] = {source = source or origin, path = path, message = message}
    end
    if type(manifest) ~= 'table' or not MAP.SafeTree(manifest) or not MAP.SafeTree(packs) then
        fail('', 'invalid or excessive source tree'); return nil, diagnostics
    end
    if manifest.schema ~= MAP.Schema then fail('schema', 'unsupported manifest schema') end
    if not MAP.IsId(manifest.id) then fail('id', 'invalid map instance ID') end
    local manifestFields = {schema = true, id = true, packages = true, packs = true, overrides = true,
        sources = true, startup = true, editor = true}
    for key in pairs(manifest) do if not manifestFields[key] then fail(tostring(key), 'unknown manifest field') end end
    if manifest.editor ~= nil then
        if type(manifest.editor) ~= 'table' or MAP.IsArray(manifest.editor) then fail('editor', 'expected object')
        else
            for key in pairs(manifest.editor) do
                if key ~= 'generatedPositions' and key ~= 'referenceBends' then fail('editor.' .. tostring(key), 'unknown editor field') end
            end
            local positions = manifest.editor.generatedPositions
            if positions ~= nil then
                if type(positions) ~= 'table' or MAP.IsArray(positions) then fail('editor.generatedPositions', 'expected object')
                else for id, position in pairs(positions) do
                    local _, err = MAP.ValidateValue({type = 'object', fields = {
                        x = {type = 'number', min = -1e6, max = 1e6}, y = {type = 'number', min = -1e6, max = 1e6}}}, position, 'position')
                    if not MAP.IsId(id) or err then fail('editor.generatedPositions.' .. tostring(id), err or 'invalid generated component ID') end
                end end
            end
            local referenceBends = manifest.editor.referenceBends
            if referenceBends ~= nil then
                local bendCount = 0
                if type(referenceBends) == 'table' then for _ in pairs(referenceBends) do bendCount = bendCount + 1 end end
                if type(referenceBends) ~= 'table' or MAP.IsArray(referenceBends) or bendCount > MAP.Limits.links then
                    fail('editor.referenceBends', 'expected bounded object')
                else for key, point in pairs(referenceBends) do
                    local owner, target
                    if type(key) == 'string' then owner, target = key:match('^([^>]+)>([^>]+)$') end
                    local _, err = MAP.ValidateValue({type = 'object', fields = {
                        x = {type = 'number', min = -1e6, max = 1e6}, y = {type = 'number', min = -1e6, max = 1e6}}}, point, 'point')
                    if not owner or not MAP.IsId(owner) or not MAP.IsId(target) or err then
                        fail('editor.referenceBends.' .. tostring(key), err or 'invalid reference key')
                    end
                end end
            end
        end
    end
    local compiled = {id = manifest.id, nodes = {}, order = {}, links = {}, sources = {}, packages = {},
        startup = MAP.Copy(manifest.startup or {}), origin = origin}
    local selectedPackages = {}
    if not MAP.IsArray(manifest.packages) or #manifest.packages > MAP.Limits.packs then fail('packages', 'expected bounded package array') else
        for index, item in ipairs(manifest.packages) do
            local id = type(item) == 'string' and item or type(item) == 'table' and item.id
            local optional = type(item) == 'table' and item.optional == true
            if type(item) == 'table' then
                for key in pairs(item) do if key ~= 'id' and key ~= 'optional' then fail('packages.' .. index, 'unknown package field') end end
                if item.optional ~= nil and type(item.optional) ~= 'boolean' then fail('packages.' .. index, 'optional must be boolean') end
            end
            if not MAP.IsId(id) then fail('packages.' .. index, 'invalid package ID')
            elseif selectedPackages[id] then fail('packages.' .. index, 'duplicate package')
            elseif not MAP.Packages[id] and not optional then fail('packages.' .. index, 'required package unavailable: ' .. id)
            else
                selectedPackages[id] = true
                if MAP.Packages[id] then compiled.packages[#compiled.packages + 1] = id end
            end
        end
    end
    for id in pairs(selectedPackages) do
        for _, dependency in ipairs((MAP.Packages[id] or {}).requires or {}) do
            if not selectedPackages[dependency] then fail('packages.' .. id, 'required package not selected: ' .. dependency) end
        end
    end
    local seenPacks, packIds, presets, declarations = {}, {}, {}, {}
    if not MAP.IsArray(manifest.packs) or #manifest.packs > MAP.Limits.packs then fail('packs', 'invalid pack list') else
        for _, path in ipairs(manifest.packs) do
            local fullPath = MAP.SourcePath('components', path)
            if not fullPath then fail('packs', 'invalid component source path')
            elseif seenPacks[path] then fail('packs', 'duplicate source: ' .. path)
            else
                seenPacks[path] = true
                local pack = type(packs) == 'table' and packs[path]
                if type(pack) ~= 'table' or pack.schema ~= MAP.ComponentSchema then fail('', 'missing pack or unsupported schema', fullPath)
                else
                    for key in pairs(pack) do
                        if not ({schema = true, id = true, components = true, links = true, presets = true, editor = true})[key] then
                            fail(tostring(key), 'unknown pack field', fullPath)
                        end
                    end
                    if not MAP.IsId(pack.id) then fail('id', 'invalid pack ID', fullPath)
                    elseif packIds[pack.id] then fail('id', 'duplicate pack ID', fullPath)
                    else packIds[pack.id] = true end
                    if pack.presets ~= nil and type(pack.presets) ~= 'table' then fail('presets', 'expected object', fullPath) else
                        for id, preset in pairs(pack.presets or {}) do
                            if not MAP.IsId(id) or presets[id] or type(preset) ~= 'table'
                                or not MAP.IsId(preset.type) or type(preset.config) ~= 'table' then
                                fail('presets.' .. tostring(id), 'invalid or duplicate preset', fullPath)
                            else
                                for key in pairs(preset) do if key ~= 'type' and key ~= 'config' then fail('presets.' .. id, 'unknown preset field', fullPath) end end
                                presets[id] = preset
                            end
                        end
                    end
                    if not MAP.IsArray(pack.components) then fail('components', 'expected array', fullPath) else
                        for index, node in ipairs(pack.components) do
                            declarations[#declarations + 1] = {value = MAP.Copy(node), source = fullPath, path = 'components.' .. index}
                        end
                    end
                    if pack.links ~= nil and not MAP.IsArray(pack.links) then fail('links', 'expected array', fullPath) else
                        for index, link in ipairs(pack.links or {}) do
                            compiled.links[#compiled.links + 1] = {value = MAP.Copy(link), source = fullPath, path = 'links.' .. index}
                        end
                    end
                end
            end
        end
    end
    -- Trusted, catalogued generation rules expose legacy automatic breakers and
    -- diesel generators as ordinary collision-checked graph nodes before sorting.
    local cursor = 1
    while declarations[cursor] and cursor <= MAP.Limits.nodes do
        local entry = declarations[cursor]
        local node = entry.value
        if type(node) == 'table' and MAP.IsId(node.id) and (node.config == nil or type(node.config) == 'table') then
            local preset = presets[node.preset] or {}
            local definition = MAP.Types[node.type or preset.type]
            local override = type(manifest.overrides) == 'table' and manifest.overrides[node.id] or {}
            if type(override) == 'table' then
                local config = MAP.Merge(MAP.Merge(preset.config, node.config), override)
                for _, rule in ipairs(definition and definition.generation or {}) do
                    if config[rule.field] == nil and (not rule.whenPresent or config[rule.whenPresent] ~= nil) then
                        local id, child = node.id .. '.' .. rule.field, MAP.Copy(rule.defaults or {})
                        for field, choices in pairs(rule.copy or {}) do
                            for _, source in ipairs(choices) do if config[source] ~= nil then child[field] = MAP.Copy(config[source]); break end end
                        end
                        if rule.owner then child.owner = node.id end
                        node.config = node.config or {}; node.config[rule.field] = id
                        node.dependsOn = node.dependsOn or {}
                        if MAP.IsArray(node.dependsOn) then node.dependsOn[#node.dependsOn + 1] = id end
                        declarations[#declarations + 1] = {value = {id = id, type = rule.type, config = child}, generatedBy = node.id,
                            source = entry.source, path = entry.path .. '.generated.' .. rule.field}
                    end
                end
            end
        end
        cursor = cursor + 1
    end
    if #declarations > MAP.Limits.nodes then fail('components', 'too many components'); return nil, diagnostics end
    if #compiled.links > MAP.Limits.links then fail('links', 'too many links'); return nil, diagnostics end
    local overrides = manifest.overrides or {}
    if type(overrides) ~= 'table' then fail('overrides', 'expected object'); overrides = {} end
    for _, entry in ipairs(declarations) do
        local node, source, path = entry.value, entry.source, entry.path
        if type(node) ~= 'table' or not MAP.IsId(node.id) then fail(path, 'invalid component ID', source)
        elseif compiled.nodes[node.id] then fail(path, 'duplicate component ID: ' .. node.id, source)
        else
            for key in pairs(node) do
                if not ({id = true, type = true, preset = true, config = true, derived = true, dependsOn = true, editor = true})[key] then
                    fail(path .. '.' .. tostring(key), 'unknown component field', source)
                end
            end
            if node.editor ~= nil then
                local _, err = MAP.ValidateValue({type = 'object', fields = {
                    x = {type = 'number', min = -1e6, max = 1e6, optional = true}, y = {type = 'number', min = -1e6, max = 1e6, optional = true},
                    group = {type = 'string', maxLength = 128, optional = true}, label = {type = 'string', maxLength = 128, optional = true}}}, node.editor, 'editor')
                if err then fail(path .. '.editor', err, source) end
            end
            local preset = node.preset and presets[node.preset]
            if node.preset and not preset then fail(path .. '.preset', 'unknown preset', source) end
            local typeId = node.type or (preset and preset.type)
            local definition = typeId and MAP.Types[typeId]
            if not definition then fail(path .. '.type', 'unknown component type', source)
            elseif definition.package and not selectedPackages[definition.package] then fail(path .. '.type', 'package not selected', source)
            elseif preset and preset.type ~= typeId then fail(path .. '.preset', 'preset type mismatch', source)
            elseif (node.config ~= nil and type(node.config) ~= 'table') or (overrides[node.id] ~= nil and type(overrides[node.id]) ~= 'table') then
                fail(path .. '.config', 'configuration and overrides must be objects', source)
            else
                local config = MAP.Merge(MAP.Merge(preset and preset.config, node.config), overrides[node.id])
                local valid, err = MAP.ValidateValue({type = 'object', fields = definition.fields}, config, 'config')
                if err then fail(path .. '.' .. err, 'invalid configuration', source) else
                    local dependencies = node.dependsOn or {}
                    if not MAP.IsArray(dependencies) then fail(path .. '.dependsOn', 'expected array', source); dependencies = {} end
                    compiled.nodes[node.id] = {id = node.id, type = typeId, config = valid, dependsOn = MAP.Copy(dependencies),
                        derived = MAP.Copy(node.derived or {}), editor = MAP.Copy(node.editor or {}), source = source, generatedBy = entry.generatedBy}
                end
            end
        end
    end
    for id in pairs(((manifest.editor or {}).generatedPositions or {})) do
        if not compiled.nodes[id] or not compiled.nodes[id].generatedBy then fail('editor.generatedPositions.' .. id, 'unknown generated component') end
    end
    for key in pairs(((manifest.editor or {}).referenceBends or {})) do
        local owner, target = key:match('^([^>]+)>([^>]+)$')
        if not compiled.nodes[owner] or not compiled.nodes[target] then fail('editor.referenceBends.' .. key, 'unknown reference endpoint') end
    end
    for id in pairs(overrides) do if not compiled.nodes[id] then fail('overrides.' .. tostring(id), 'unknown component') end end
    local derivedSchema = {type = 'object', fields = {component = {type = 'id'}, field = {type = 'string', maxLength = 128},
        scale = {type = 'number', default = 1}, offset = {type = 'number', default = 0}, unit = {type = 'string'}}}
    for id, node in pairs(compiled.nodes) do
        if type(node.derived) ~= 'table' then fail(id .. '.derived', 'expected object'); node.derived = {} end
        for field, ref in pairs(node.derived) do
            local descriptor = MAP.Types[node.type].fields[field]
            local valid, err = MAP.ValidateValue(derivedSchema, ref, id .. '.derived.' .. tostring(field))
            local target = valid and compiled.nodes[valid.component]
            local capacity = target and (MAP.Types[target.type].capacities or {})[valid.field]
            if not descriptor or descriptor.type ~= 'number' then fail(id .. '.derived', 'derived destination must be a numeric configuration field')
            elseif err then fail(id .. '.derived', err)
            elseif not capacity or capacity.unit ~= valid.unit or (descriptor.unit and descriptor.unit ~= valid.unit) then fail(id .. '.derived', 'unknown capacity or incompatible units')
            elseif overrides[id] and overrides[id][field] ~= nil then node.derived[field] = nil
            else
                node.derived[field] = valid
                node.dependsOn[#node.dependsOn + 1] = valid.component
            end
        end
    end
    local visited, visiting = {}, {}
    local function visit(id)
        if visited[id] then return end
        if visiting[id] then fail('dependsOn', 'construction cycle at ' .. id); return end
        local node = compiled.nodes[id]
        if not node then fail('dependsOn', 'missing component: ' .. tostring(id)); return end
        visiting[id] = true
        for _, dependency in ipairs(node.dependsOn) do
            if MAP.IsId(dependency) then visit(dependency) else fail(id .. '.dependsOn', 'invalid dependency ID', node.source) end
        end
        visiting[id], visited[id] = nil, true
        compiled.order[#compiled.order + 1] = id
    end
    local ids = {}
    for id in pairs(compiled.nodes) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do visit(id) end
    local connected, links = {}, {}
    local function endpoint(ref, entry)
        if type(ref) ~= 'table' or not MAP.IsId(ref.component) or not MAP.IsPort(ref.port) then
            fail(entry.path, 'endpoint requires component and port', entry.source); return
        end
        local node = compiled.nodes[ref.component]
        local port = node and (MAP.Types[node.type].ports or {})[ref.port]
        if not port then fail(entry.path, 'unknown endpoint ' .. ref.component .. '.' .. ref.port, entry.source); return end
        local key = ref.component .. '/' .. ref.port
        connected[key] = (connected[key] or 0) + 1
        if port.maxLinks and connected[key] > port.maxLinks then fail(entry.path, 'port cardinality exceeded: ' .. key, entry.source) end
        return port
    end
    local duplicateLinks = {}
    for _, entry in ipairs(compiled.links) do
        local link = entry.value
        if type(link) ~= 'table' then fail(entry.path, 'expected link object', entry.source) else
            for key in pairs(link) do if key ~= 'from' and key ~= 'to' and key ~= 'editor' then fail(entry.path, 'unknown link field', entry.source) end end
            if link.editor ~= nil then
                local valid, err = MAP.ValidateValue({type = 'object', fields = {bends = {type = 'array', optional = true, maxItems = 8,
                    items = {type = 'object', fields = {x = {type = 'number', min = -1e6, max = 1e6}, y = {type = 'number', min = -1e6, max = 1e6}}}}}}, link.editor, 'editor')
                if err then fail(entry.path .. '.editor', err, entry.source) else link.editor = valid end
            end
            for _, ref in pairs({link.from, link.to}) do
                if type(ref) == 'table' then
                    for key in pairs(ref) do if key ~= 'component' and key ~= 'port' then fail(entry.path, 'unknown endpoint field', entry.source) end end
                end
            end
            local from, to = endpoint(link.from, entry), endpoint(link.to, entry)
            if from and to then
                local key = link.from.component .. '/' .. link.from.port .. '>' .. link.to.component .. '/' .. link.to.port
                if duplicateLinks[key] then fail(entry.path, 'duplicate link', entry.source) end
                duplicateLinks[key] = true
                if from.direction == 'in' or to.direction == 'out' or from.kind ~= to.kind
                    or (from.unit and to.unit and from.unit ~= to.unit)
                    or (from.fluid and to.fluid and from.fluid ~= to.fluid) then
                    fail(entry.path, 'incompatible port direction, capability, unit or fluid', entry.source)
                end
                links[#links + 1] = link
            end
        end
    end
    compiled.links = links
    for id, node in pairs(compiled.nodes) do
        for name, port in pairs(MAP.Types[node.type].ports or {}) do
            if (connected[id .. '/' .. name] or 0) < (port.minLinks or 0) then fail(id .. '.' .. name, 'required port is unconnected', node.source) end
        end
    end
    if manifest.sources ~= nil and type(manifest.sources) ~= 'table' then fail('sources', 'expected object') else
        local seen = {}
        for family, paths in pairs(manifest.sources or {}) do
            if not families[family] or not MAP.IsArray(paths) or #paths > MAP.Limits.packs then fail('sources', 'unknown family or invalid source list') else
                compiled.sources[family] = {}
                for _, path in ipairs(paths) do
                    local fullPath = MAP.SourcePath(family, path)
                    if not fullPath or seen[fullPath] then fail('sources.' .. family, 'invalid or duplicate source path') else
                        seen[fullPath] = true
                        compiled.sources[family][#compiled.sources[family] + 1] = fullPath
                    end
                end
            end
        end
    end
    local startup = manifest.startup or {}
    if type(startup) ~= 'table' then fail('startup', 'expected object') else
        for key in pairs(startup) do if key ~= 'intervals' then fail('startup.' .. tostring(key), 'unknown startup setting') end end
        if startup.intervals ~= nil and type(startup.intervals) ~= 'table' then fail('startup.intervals', 'expected object') else
            local allowed = {LUASQUARE_3D2D = true, LUASQUARE_ANNUNCIATOR = true}
            for _, namespace in ipairs(MAP.StartupNamespaces or {}) do allowed[namespace] = true end
            for _, definition in pairs(MAP.PlantDefinitions or {}) do allowed[definition.namespace] = true end
            for namespace, interval in pairs(startup.intervals or {}) do
                if not allowed[namespace] or not MAP.Finite(interval) or interval < 0.02 or interval > 10 then fail('startup.intervals.' .. tostring(namespace), 'invalid namespace or tick interval') end
            end
        end
    end
    for id, node in pairs(compiled.nodes) do
        local validate = MAP.Types[node.type].validateDefinition or (MAP.Validators or {})[node.type]
        if validate then
            local ok, result, message = pcall(validate, node, compiled)
            if not ok or result == false then fail(id, tostring(not ok and result or message or 'invalid component'), node.source) end
        end
    end
    if #diagnostics > 0 then return nil, diagnostics end
    return compiled, diagnostics
end
