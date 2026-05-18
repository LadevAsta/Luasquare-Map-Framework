if LUASQUARE_ROD_SELECTOR_CORE_LOADED then return end
LUASQUARE_ROD_SELECTOR_CORE_LOADED = true
LUASQUARE_ROD_SELECTOR = LUASQUARE_ROD_SELECTOR or {}
LUASQUARE_ROD_SELECTOR.Selected = LUASQUARE_ROD_SELECTOR.Selected or {}
LUASQUARE_ROD_SELECTOR.Indicators = LUASQUARE_ROD_SELECTOR.Indicators or {}
function LUASQUARE_ROD_SELECTOR.Toggle(name)
    local rod = RBMK.GetRod(name)
    if not rod then
        print('[LUASQUARE_ROD_SELECTOR] Unknown rod: ' .. tostring(name))
        return
    end

    if LUASQUARE_ROD_SELECTOR.Selected[name] then
        LUASQUARE_ROD_SELECTOR.Selected[name] = nil
    else
        LUASQUARE_ROD_SELECTOR.Selected[name] = true
    end

    LUASQUARE_ROD_SELECTOR.UpdateIndicators()
end

function LUASQUARE_ROD_SELECTOR.Clear()
    LUASQUARE_ROD_SELECTOR.Selected = {}
    LUASQUARE_ROD_SELECTOR.UpdateIndicators()
end

function LUASQUARE_ROD_SELECTOR.RegisterIndicator(rodName, spriteName)
    if not ents.FindByName(spriteName) then
        print('[LUASQUARE_ROD_SELECTOR] env_sprite Not found : ' .. spriteName)
        return
    end

    LUASQUARE_ROD_SELECTOR.Indicators[rodName] = spriteName
end

function LUASQUARE_ROD_SELECTOR.SelectGroup(group)
    for name, rod in pairs(RBMK.Rods) do
        if rod.group == group then LUASQUARE_ROD_SELECTOR.Selected[name] = true end
    end

    LUASQUARE_ROD_SELECTOR.UpdateIndicators()
end

function LUASQUARE_ROD_SELECTOR.ToggleGroup(group)
    local enable = false
    for name, rod in pairs(RBMK.Rods) do
        if rod.group == group and not LUASQUARE_ROD_SELECTOR.Selected[name] then
            enable = true
            break
        end
    end

    for name, rod in pairs(RBMK.Rods) do
        if rod.group == group then
            if enable then
                LUASQUARE_ROD_SELECTOR.Selected[name] = true
            else
                LUASQUARE_ROD_SELECTOR.Selected[name] = nil
            end
        end
    end

    LUASQUARE_ROD_SELECTOR.UpdateIndicators()
end

function LUASQUARE_ROD_SELECTOR.UpdateIndicators()
    for rodName, spriteName in pairs(LUASQUARE_ROD_SELECTOR.Indicators) do
        local ent = ents.FindByName(spriteName)[1]
        if not IsValid(ent) then
            print('[LUASQUARE_ROD_SELECTOR] Invalid ent_sprite???')
            continue
        end

        if LUASQUARE_ROD_SELECTOR.Selected[rodName] then
            ent:Fire('ShowSprite')
        else
            ent:Fire('HideSprite')
        end
    end
end

function LUASQUARE_ROD_SELECTOR.Apply(value)
    local insertion = math.Clamp(1 - (value / 100), 0, 1)
    if next(LUASQUARE_ROD_SELECTOR.Selected) == nil then
        print('[LUASQUARE_ROD_SELECTOR] No rods selected!')
        return
    end

    for rodName, _ in pairs(LUASQUARE_ROD_SELECTOR.Selected) do
        RBMK.SetRodInsertionByName(rodName, insertion)
    end
end

function LUASQUARE_ROD_SELECTOR.GetSelectionCount()
    local count = 0
    for _ in pairs(LUASQUARE_ROD_SELECTOR.Selected) do
        count = count + 1
    end
    return count
end

print('[LUASQUARE_ROD_SELECTOR] Loaded')