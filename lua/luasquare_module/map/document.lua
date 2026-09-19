local MAP = LUASQUARE_MAP
local Document = {}
Document.__index = Document

function MAP.NewDocument(manifest, packs)
    return setmetatable({manifest = MAP.Copy(manifest), packs = MAP.Copy(packs), undo = {}, redo = {}, revision = 0}, Document)
end

function Document:Snapshot() return {manifest = MAP.Copy(self.manifest), packs = MAP.Copy(self.packs)} end

local function trimHistory(history)
    local bytes = 0
    for index = #history, 1, -1 do
        local encoded = MAP.CanonicalJSON(history[index])
        bytes = bytes + (encoded and #encoded or 8 * 1024 * 1024)
        if #history > 64 or bytes > 16 * 1024 * 1024 then table.remove(history, index) end
    end
end

function Document:Edit(callback)
    local before = self:Snapshot()
    local ok, result, err = pcall(callback, self)
    if not ok or result == false then
        self.manifest, self.packs = before.manifest, before.packs
        return false, tostring(not ok and result or err)
    end
    self.undo[#self.undo + 1] = before
    trimHistory(self.undo)
    self.redo = {}
    self.revision = self.revision + 1
    return true
end

function Document:History(reverse)
    local from, to = reverse and self.redo or self.undo, reverse and self.undo or self.redo
    local state = table.remove(from)
    if not state then return false end
    to[#to + 1] = self:Snapshot()
    trimHistory(to)
    self.manifest, self.packs = state.manifest, state.packs
    self.revision = self.revision + 1
    return true
end

function Document:Find(id)
    for path, pack in pairs(self.packs) do
        for index, node in ipairs(pack.components or {}) do if node.id == id then return node, pack, index, path end end
    end
end

function Document:Compile() return MAP.Compile(self.manifest, self.packs, 'local structural preview') end

-- Authoring must remain possible while another field has a diagnostic.
-- This resolves precedence only; activation always uses the strict compiler.
function Document:Resolve(id)
    local node = self:Find(id)
    if not node then
        local compiled = self:Compile()
        return compiled and compiled.nodes[id]
    end
    local preset = {}
    for _, pack in pairs(self.packs) do
        if pack.presets and pack.presets[node.preset] then preset = pack.presets[node.preset]; break end
    end
    local typeId = node.type or preset.type
    local config = MAP.Merge(preset.config or {}, node.config or {})
    config = MAP.Merge(config, (self.manifest.overrides or {})[id] or {})
    for field, definition in pairs((MAP.Types[typeId] or {}).fields or {}) do
        if config[field] == nil then config[field] = MAP.Copy(definition.default) end
    end
    return {id = id, type = typeId, config = config}
end

local function remap(value, descriptor, ids)
    if descriptor.type == 'id' and descriptor.asset ~= 'name' then return ids[value] or value end
    if type(value) ~= 'table' then return value end
    local result = MAP.Copy(value)
    if descriptor.type == 'object' then
        for key, field in pairs(descriptor.fields or {}) do
            if key ~= 'port' and value[key] ~= nil then result[key] = remap(value[key], field, ids) end
        end
    elseif descriptor.type == 'array' then
        for index, item in ipairs(value) do result[index] = remap(item, descriptor.items, ids) end
    end
    return result
end

function Document:Duplicate(selection, destination)
    local pack = self.packs[destination]
    if not pack then return false, 'select a destination pack' end
    local ids, copies = {}, {}
    for id in pairs(selection) do
        local node = self:Find(id)
        if not node then return false, 'unknown component ' .. id end
        local suffix, candidate = 1, id .. '_copy'
        while self:Find(candidate) or copies[candidate] do suffix = suffix + 1; candidate = id .. '_copy' .. suffix end
        if not MAP.IsId(candidate) then return false, 'duplicated ID exceeds limit' end
        ids[id], copies[candidate] = candidate, MAP.Copy(node)
    end
    return self:Edit(function()
        local compiled, diagnostics = self:Compile()
        if not compiled then return false, MAP.DiagnosticsText(diagnostics) end
        for _, id in ipairs(compiled.order) do
            local generated = compiled.nodes[id]
            if generated.generatedBy and ids[generated.generatedBy] then
                ids[id] = ids[generated.generatedBy] .. id:sub(#generated.generatedBy + 1)
            end
        end
        -- Dependencies are sorted child-first; repeat to include nested children.
        for _ = 1, 8 do
            for id, generated in pairs(compiled.nodes) do
                if generated.generatedBy and ids[generated.generatedBy] then ids[id] = ids[generated.generatedBy] .. id:sub(#generated.generatedBy + 1) end
            end
        end
        for id, newId in pairs(ids) do if copies[newId] then
            local node, resolved = copies[newId], compiled.nodes[id]
            node.id, node.preset = newId, nil
            node.type = resolved.type
            node.config = remap(resolved.config, {type = 'object', fields = MAP.Types[resolved.type].fields}, ids)
            for _, rule in ipairs(MAP.Types[resolved.type].generation or {}) do
                local child = compiled.nodes[resolved.config[rule.field]]
                if child and child.generatedBy == id then node.config[rule.field] = nil end
            end
            for _, ref in pairs(node.derived or {}) do ref.component = ids[ref.component] or ref.component end
            for index, dependency in ipairs(node.dependsOn or {}) do node.dependsOn[index] = ids[dependency] or dependency end
            node.editor = node.editor or {}
            node.editor.x, node.editor.y = (node.editor.x or 0) + 32, (node.editor.y or 0) + 32
            pack.components[#pack.components + 1] = node
        elseif self.manifest.overrides and self.manifest.overrides[id] then
            self.manifest.overrides[newId] = remap(self.manifest.overrides[id], {type = 'object', fields = MAP.Types[compiled.nodes[id].type].fields}, ids)
        end end
        pack.links = pack.links or {}
        -- Copy internal connections, including those originally authored in a
        -- different pack. External connections remain explicit author decisions.
        for _, link in ipairs(compiled.links) do
            if ids[link.from.component] and ids[link.to.component] then
                local copy = MAP.Copy(link)
                copy.from.component, copy.to.component = ids[copy.from.component], ids[copy.to.component]
                for _, bend in ipairs(copy.editor and copy.editor.bends or {}) do bend.x, bend.y = bend.x + 32, bend.y + 32 end
                pack.links[#pack.links + 1] = copy
            end
        end
        return true
    end)
end

function Document:Connect(from, to, destination, editor)
    local pack = self.packs[destination]
    if not pack then return false, 'select a destination pack' end
    return self:Edit(function()
        pack.links = pack.links or {}
        pack.links[#pack.links + 1] = {from = MAP.Copy(from), to = MAP.Copy(to), editor = editor and MAP.Copy(editor) or nil}
        local compiled, diagnostics = self:Compile()
        if not compiled then return false, MAP.DiagnosticsText(diagnostics) end
        return true
    end)
end

function Document:Remove(selection)
    for id in pairs(selection) do if not self:Find(id) then return false, 'remove the owning declaration for generated component ' .. id end end
    return self:Edit(function()
        for _, pack in pairs(self.packs) do
            for index = #(pack.components or {}), 1, -1 do
                if selection[pack.components[index].id] then table.remove(pack.components, index) end
            end
            for index = #(pack.links or {}), 1, -1 do
                local link = pack.links[index]
                if selection[link.from.component] or selection[link.to.component] then table.remove(pack.links, index) end
            end
        end
        for id in pairs(selection) do if self.manifest.overrides then self.manifest.overrides[id] = nil end end
        local referenceBends = self.manifest.editor and self.manifest.editor.referenceBends
        for key in pairs(referenceBends or {}) do
            local owner, target = key:match('^([^>]+)>([^>]+)$')
            if selection[owner] or selection[target] then referenceBends[key] = nil end
        end
        -- References from surviving nodes are intentionally left visible as
        -- diagnostics instead of silently rewiring the plant.
        return true
    end)
end

function Document:Group(selection, name)
    if type(name) ~= 'string' or #name > 128 then return false, 'invalid group name' end
    return self:Edit(function()
        for id in pairs(selection) do
            local node = self:Find(id)
            if node then node.editor = node.editor or {}; node.editor.group = name end
        end
        return true
    end)
end

function Document:MakePreset(id, name, destination)
    if not MAP.IsId(name) or not self.packs[destination] then return false, 'invalid preset ID or pack' end
    return self:Edit(function()
        local compiled, diagnostics = self:Compile()
        if not compiled then return false, MAP.DiagnosticsText(diagnostics) end
        local resolved, node = compiled.nodes[id], self:Find(id)
        if not node then return false, 'select a component' end
        for _, pack in pairs(self.packs) do if pack.presets and pack.presets[name] then return false, 'preset ID already exists' end end
        local pack = self.packs[destination]
        pack.presets = pack.presets or {}
        pack.presets[name] = {type = resolved.type, config = MAP.Copy(resolved.config)}
        for _, rule in ipairs(MAP.Types[resolved.type].generation or {}) do
            local child = compiled.nodes[resolved.config[rule.field]]
            if child and child.generatedBy == id then pack.presets[name].config[rule.field] = nil end
        end
        node.preset, node.config = name, MAP.Object()
        if self.manifest.overrides then self.manifest.overrides[id] = nil end
        return true
    end)
end

function Document:SetOverride(id, field, value)
    return self:Edit(function()
        if not self:Resolve(id) then return false, 'unknown component' end
        self.manifest.overrides = self.manifest.overrides or MAP.Object()
        self.manifest.overrides[id] = self.manifest.overrides[id] or MAP.Object()
        self.manifest.overrides[id][field] = MAP.Copy(value)
        return true
    end)
end

function Document:SetCell(id, x, y, cell)
    return self:Edit(function()
        local node = self:Find(id)
        local resolved = self:Resolve(id)
        if not node or resolved.type ~= 'rbmk.core' or not MAP.Finite(resolved.config.width) or not MAP.Finite(resolved.config.height)
            or x < 1 or y < 1 or x > resolved.config.width or y > resolved.config.height then return false, 'invalid core coordinate' end
        local cells = MAP.Copy(resolved.config.cells or {})
        for index = #cells, 1, -1 do if cells[index].x == x and cells[index].y == y then table.remove(cells, index) end end
        if cell then
            cell = MAP.Copy(cell); cell.x, cell.y = x, y
            cells[#cells + 1] = cell
        end
        self.manifest.overrides = self.manifest.overrides or MAP.Object()
        self.manifest.overrides[id] = self.manifest.overrides[id] or MAP.Object()
        self.manifest.overrides[id].cells = cells
        return true
    end)
end
