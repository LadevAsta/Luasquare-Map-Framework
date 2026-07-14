DFR = DFR or {}
if not LUASQUARE_SOURCEBINDING then include('luasquare_module/sourcebinding.lua') end

DFR.SourceBindings = LUASQUARE_SOURCEBINDING.CreateRegistry('DFR', {
    log = function(message) DFR.Log(message) end,
    time = function() return DFR.GetTime() end
})

DFR.Bindings = DFR.SourceBindings.Bindings
DFR.EntityCache = DFR.SourceBindings.EntityCache

function DFR.RegisterBinding(id, data)
    return DFR.SourceBindings:Register(id, data)
end

function DFR.GetBinding(id)
    return DFR.SourceBindings:Get(id)
end

function DFR.GetEntByName(targetName)
    local entities = DFR.SourceBindings:GetEntitiesByName(targetName)
    return entities[1]
end

function DFR.GetEntsByName(targetName)
    return DFR.SourceBindings:GetEntitiesByName(targetName)
end

function DFR.ResolveBinding(id)
    return DFR.SourceBindings:ResolveFirst(id)
end

function DFR.ResolveBindingAll(id)
    return DFR.SourceBindings:ResolveAll(id)
end

function DFR.ValidateBindings()
    local ok = DFR.SourceBindings:Validate()
    DFR.LastBindingValidation = DFR.SourceBindings.LastValidation
    return ok
end

function DFR.FireBinding(id, inputName, value)
    return DFR.SourceBindings:Fire(id, inputName, value, { all = false })
end

function DFR.FireBindingAll(id, inputName, value)
    return DFR.SourceBindings:Fire(id, inputName, value, { all = true })
end

function DFR.EachBinding(id, callback, all)
    return DFR.SourceBindings:Each(id, callback, { all = all ~= false })
end
