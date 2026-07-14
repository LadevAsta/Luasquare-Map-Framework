DFR = DFR or {}
DFR.Bindings = DFR.Bindings or {}
DFR.EntityCache = DFR.EntityCache or {}

function DFR.RegisterBinding(id, data)
    data = data or {}
    if not id or id == '' then
        DFR.Log('Rejected binding with missing id')
        return false
    end

    DFR.Bindings[id] = {
        id = id,
        targetName = data.targetName or data.target or data.entity,
        class = data.class or data.entityClass,
        required = data.required and true or false,
        notes = data.notes,
        missing = false,
        entity = nil
    }

    return true
end

function DFR.GetBinding(id)
    return DFR.Bindings[id]
end

function DFR.GetEntByName(targetName)
    if not targetName or targetName == '' then return nil end
    local cached = DFR.EntityCache[targetName]
    if IsValid and IsValid(cached) then return cached end
    if not ents or not ents.FindByName then return nil end

    local ent = ents.FindByName(targetName)[1]
    if IsValid and IsValid(ent) then
        DFR.EntityCache[targetName] = ent
        return ent
    end

    return nil
end

function DFR.ResolveBinding(id)
    local binding = DFR.GetBinding(id)
    if not binding then return nil end
    local ent = DFR.GetEntByName(binding.targetName)
    binding.entity = ent
    binding.missing = not (IsValid and IsValid(ent))
    return ent
end

function DFR.ValidateBindings()
    local ok = true
    local missingRequired = 0
    local missingOptional = 0

    for id, binding in pairs(DFR.Bindings) do
        DFR.ResolveBinding(id)
        if binding.missing then
            if binding.required then
                ok = false
                missingRequired = missingRequired + 1
                DFR.Log('Missing required binding ' .. tostring(id) .. ' target=' .. tostring(binding.targetName) .. ' class=' .. tostring(binding.class))
            else
                missingOptional = missingOptional + 1
                DFR.Log('Missing optional binding ' .. tostring(id) .. ' target=' .. tostring(binding.targetName) .. ' class=' .. tostring(binding.class))
            end
        end
    end

    DFR.LastBindingValidation = {
        ok = ok,
        missingRequired = missingRequired,
        missingOptional = missingOptional,
        time = DFR.GetTime()
    }

    return ok
end

function DFR.FireBinding(id, inputName, value)
    local ent = DFR.ResolveBinding(id)
    if not (IsValid and IsValid(ent)) then
        DFR.Log('Cannot fire missing binding ' .. tostring(id))
        return false
    end

    ent:Fire(inputName or 'Trigger', value)
    return true
end

