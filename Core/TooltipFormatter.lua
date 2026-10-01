local _, addon = ...

-- Builds the identity section of a guildmate's tooltip. Pure: returns lines as
-- data, and Tooltip turns them into tooltip rows.
local TooltipFormatter = {}
addon.TooltipFormatter = TooltipFormatter

-- Characters listed before the rest are summed up as "+N more".
TooltipFormatter.MAX_LISTED = 5
-- Longest bio shown, in bytes, before it is cut with "...".
TooltipFormatter.MAX_BIO = 60

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

-- Cuts `text` to `limit` bytes without splitting a UTF-8 character.
local function shorten(text, limit)
    if #text <= limit then
        return text
    end
    return (text:sub(1, limit):gsub("[\192-\255][\128-\191]*$", "")) .. "..."
end

-- Lines for `charKey`, or nil when there is nothing to add: an unknown
-- character, or someone with a single character, no alias, and no profile.
--   person:  the character's person from IdentityStore (may be nil)
--   infoFor: function(key) -> roster entry { name, level, className, online }
--   profile: the person's profile (discord, bio), or nil
-- Each line is { left, right?, color = { r, g, b } }.
function TooltipFormatter.Lines(person, charKey, infoFor, profile)
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
    local discord = profile and profile.discord
    local bio = profile and profile.bio
    if isMain and #others == 0 and not person.alias and not discord and not bio then
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
    if discord then
        table.insert(lines, { left = "Discord", right = discord, color = TooltipFormatter.COLORS.text })
    end
    if bio then
        table.insert(lines, { left = shorten(bio, TooltipFormatter.MAX_BIO), color = TooltipFormatter.COLORS.offline })
    end
    return lines
end
