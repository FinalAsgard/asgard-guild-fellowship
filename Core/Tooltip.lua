local _, addon = ...

-- Adds the identity section to guildmates' tooltips: unit tooltips (mouseover,
-- target, unit frames) and guild roster rows. Only appends lines through
-- post-hooks, so Blizzard's tooltip code stays untainted.
local Tooltip = {}
addon.Tooltip = Tooltip

-- Tooltips that already have our lines, kept here rather than as a field on
-- Blizzard's frames.
local added = setmetatable({}, { __mode = "k" })

-- Appends `charKey`'s identity lines. Returns true when anything was added.
function Tooltip.AddIdentity(tooltip, charKey)
    local store = addon.identity
    if not store or not charKey then
        return false
    end
    local person = store:GetPerson(charKey)
    local profile = person and addon.profiles and addon.profiles:Get(person.id)
    local lines = addon.TooltipFormatter.Lines(person, charKey, function(key)
        return store:GetCharacterInfo(key)
    end, profile)
    if not lines then
        return false
    end
    for _, line in ipairs(lines) do
        local r, g, b = unpack(line.color)
        if line.right and line.right ~= "" then
            tooltip:AddDoubleLine(line.left, line.right, r, g, b, r, g, b)
        else
            tooltip:AddLine(line.left, r, g, b)
        end
    end
    return true
end

-- Unit tooltips.
function Tooltip.OnUnit(tooltip, unit)
    local Compat = addon.Compat
    if not unit or Compat.IsSecret(unit) or not UnitIsPlayer(unit) then
        return
    end
    local name, realm = UnitName(unit)
    if not name or Compat.IsSecret(name) or Compat.IsSecret(realm) then
        return
    end
    -- Mark it so the Show post-hook doesn't add the section a second time.
    if Tooltip.AddIdentity(tooltip, Compat.NormalizeName(name, realm)) then
        added[tooltip] = true
    end
end

-- Guild roster rows (community member list entries) build their tooltip in
-- OnEnter and then call Show; this runs after that Show.
function Tooltip.OnShow(tooltip)
    if added[tooltip] then
        return
    end
    local owner = tooltip:GetOwner()
    local info = owner and owner.GetMemberInfo and owner:GetMemberInfo()
    if not info or type(info.name) ~= "string" then
        return
    end
    if Tooltip.AddIdentity(tooltip, addon.Compat.NormalizeName(info.name)) then
        -- Set before Show so the re-show that resizes the tooltip is a no-op here.
        added[tooltip] = true
        tooltip:Show()
    end
end

function Tooltip.Register()
    addon.Compat.HookUnitTooltip(Tooltip.OnUnit)
    hooksecurefunc(GameTooltip, "Show", Tooltip.OnShow)
    GameTooltip:HookScript("OnTooltipCleared", function(tooltip)
        added[tooltip] = nil
    end)
end
