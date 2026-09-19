return function(core)
    local SELECTOR = {Selected = {}, Indicators = {}}
    core.Selector = SELECTOR

    function SELECTOR.UpdateIndicators()
        for name, target in pairs(SELECTOR.Indicators) do
            for _, entity in ipairs(ents.FindByName(target)) do
                if IsValid(entity) and entity:GetClass() == 'env_sprite' then
                    entity:Fire(SELECTOR.Selected[name] and 'ShowSprite' or 'HideSprite')
                end
            end
        end
    end

    function SELECTOR.RegisterIndicator(name, target) SELECTOR.Indicators[name] = target end

    function SELECTOR.Toggle(name)
        if not core.GetRod(name) then return false, 'unknown rod' end
        SELECTOR.Selected[name] = not SELECTOR.Selected[name] or nil
        SELECTOR.UpdateIndicators()
        return true
    end

    function SELECTOR.Clear()
        SELECTOR.Selected = {}
        SELECTOR.UpdateIndicators()
    end

    function SELECTOR.SelectGroup(group)
        for name, rod in pairs(core.Rods) do if rod.group == group then SELECTOR.Selected[name] = true end end
        SELECTOR.UpdateIndicators()
    end

    function SELECTOR.ToggleGroup(group)
        local enable = false
        for name, rod in pairs(core.Rods) do
            if rod.group == group and not SELECTOR.Selected[name] then enable = true end
        end
        for name, rod in pairs(core.Rods) do if rod.group == group then SELECTOR.Selected[name] = enable or nil end end
        SELECTOR.UpdateIndicators()
    end

    function SELECTOR.Apply(percent)
        if next(SELECTOR.Selected) == nil then return false, 'no rods selected' end
        local insertion = math.Clamp(1 - percent / 100, 0, 1)
        for name in pairs(SELECTOR.Selected) do core.SetRodInsertionByName(name, insertion) end
        return true
    end

    function SELECTOR.GetSelectionCount()
        local count = 0
        for _ in pairs(SELECTOR.Selected) do count = count + 1 end
        return count
    end
end
