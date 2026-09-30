local _, addon = ...

-- Builds the identity section of a guildmate's tooltip. Pure: returns lines as
-- data, and Tooltip turns them into tooltip rows.
local TooltipFormatter = {}
addon.TooltipFormatter = TooltipFormatter

-- Characters listed before the rest are summed up as "+N more".
TooltipFormatter.MAX_LISTED = 5

TooltipFormatter.COLORS = {
    identity = { 1, 0.82, 0 },
    text = { 1, 1, 1 },
    online = { 0.25, 1, 0.25 },
    offline = { 0.5, 0.5, 0.5 },
}

local function details(info)
    local parts = {}
    if info.level then
        table.insert(parts, tostring(info.level))
    end
    if info.className then
        table.insert(parts, info.className)
    end
    return table.concat(parts, " ")
end

local function characterLine(prefix, info)
    local color = info.online and TooltipFormatter.COLORS.online or TooltipFormatter.COLORS.offline
    return { left = prefix .. info.name, right = details(info), color = color }
end

-- Lines for `charKey`, or nil when there is nothing to add: an unknown
-- character, or someone with a single character and no alias.
--   person:  the character's person from IdentityStore (may be nil)
--   infoFor: function(key) -> roster entry { name, level, className, online }
-- Each line is { left, right?, color = { r, g, b } }.
function TooltipFormatter.Lines(person, charKey, infoFor)
    if not person then
        return nil
    end
    local others = {}
    for _, key in ipairs(person.characters) do
        if key ~= charKey and key ~= person.mainKey and infoFor(key) then
            table.insert(others, infoFor(key))
        end
    end
    local isMain = charKey == person.mainKey
    local mainInfo = infoFor(person.mainKey)
    if isMain and #others == 0 and not person.alias then
        return nil
    end

    local current = infoFor(charKey)
    local lines = { { left = person.displayName, color = TooltipFormatter.COLORS.identity } }
    if current then
        local playing = "Playing " .. current.name .. (isMain and " (main)" or "")
        table.insert(lines, { left = playing, color = TooltipFormatter.COLORS.text })
    end
    if not isMain and mainInfo then
        table.insert(lines, characterLine("Main: ", mainInfo))
    end
    for index, info in ipairs(others) do
        if index > TooltipFormatter.MAX_LISTED then
            local more = ("+%d more"):format(#others - TooltipFormatter.MAX_LISTED)
            table.insert(lines, { left = more, color = TooltipFormatter.COLORS.offline })
            break
        end
        table.insert(lines, characterLine("  ", info))
    end
    return lines
end
