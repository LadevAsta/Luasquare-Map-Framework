if LITHOS_ROD_SELECTOR_CORE_LOADED then return end
LITHOS_ROD_SELECTOR_CORE_LOADED = true
LITHOS_ROD_SELECTOR = LITHOS_ROD_SELECTOR or {}
LITHOS_ROD_SELECTOR.Selected = LITHOS_ROD_SELECTOR.Selected or {}
LITHOS_ROD_SELECTOR.Indicators = LITHOS_ROD_SELECTOR.Indicators or {}
function LITHOS_ROD_SELECTOR.Toggle(name)
    local rod = RBMK.GetRod(name)
    if not rod then
        print('[LITHOS_ROD_SELECTOR] Unknown rod: ' .. tostring(name))
        return
    end

    if LITHOS_ROD_SELECTOR.Selected[name] then
        LITHOS_ROD_SELECTOR.Selected[name] = nil
    else
        LITHOS_ROD_SELECTOR.Selected[name] = true
    end

    LITHOS_ROD_SELECTOR.UpdateIndicators()
end

function LITHOS_ROD_SELECTOR.Clear()
    LITHOS_ROD_SELECTOR.Selected = {}
    LITHOS_ROD_SELECTOR.UpdateIndicators()
end

function LITHOS_ROD_SELECTOR.RegisterIndicator(rodName, spriteName)
    if not ents.FindByName(spriteName) then
        print('[LITHOS_ROD_SELECTOR] env_sprite Not found : ' .. spriteName)
        return
    end

    LITHOS_ROD_SELECTOR.Indicators[rodName] = spriteName
end

function LITHOS_ROD_SELECTOR.SelectGroup(group)
    for name, rod in pairs(RBMK.Rods) do
        if rod.group == group then LITHOS_ROD_SELECTOR.Selected[name] = true end
    end

    LITHOS_ROD_SELECTOR.UpdateIndicators()
end

function LITHOS_ROD_SELECTOR.ToggleGroup(group)
    local enable = false
    for name, rod in pairs(RBMK.Rods) do
        if rod.group == group and not LITHOS_ROD_SELECTOR.Selected[name] then
            enable = true
            break
        end
    end

    for name, rod in pairs(RBMK.Rods) do
        if rod.group == group then
            if enable then
                LITHOS_ROD_SELECTOR.Selected[name] = true
            else
                LITHOS_ROD_SELECTOR.Selected[name] = nil
            end
        end
    end

    LITHOS_ROD_SELECTOR.UpdateIndicators()
end

function LITHOS_ROD_SELECTOR.UpdateIndicators()
    for rodName, spriteName in pairs(LITHOS_ROD_SELECTOR.Indicators) do
        local ent = ents.FindByName(spriteName)[1]
        if not IsValid(ent) then
            print('[LITHOS_ROD_SELECTOR] Invalid ent_sprite???')
            continue
        end

        if LITHOS_ROD_SELECTOR.Selected[rodName] then
            ent:Fire('ShowSprite')
        else
            ent:Fire('HideSprite')
        end
    end
end

function LITHOS_ROD_SELECTOR.Apply(value)
    local insertion = math.Clamp(1 - (value / 100), 0, 1)
    if next(LITHOS_ROD_SELECTOR.Selected) == nil then
        print('[LITHOS_ROD_SELECTOR] No rods selected!')
        return
    end

    for rodName, _ in pairs(LITHOS_ROD_SELECTOR.Selected) do
        RBMK.SetRodInsertionByName(rodName, insertion)
    end
end

function LITHOS_ROD_SELECTOR.GetSelectionCount()
    local count = 0
    for _ in pairs(LITHOS_ROD_SELECTOR.Selected) do
        count = count + 1
    end
    return count
end

print('[LITHOS_ROD_SELECTOR] Loaded')