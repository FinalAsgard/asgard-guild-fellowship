local _, addon = ...

-- Formats `/gf who` results as chat lines. Pure: no WoW API.
local WhoFormatter = {}
addon.WhoFormatter = WhoFormatter

local function characterLine(info, isMain)
    local parts = { info.name .. (isMain and " (main)" or "") }
    local details = {}
    if info.level then
        table.insert(details, tostring(info.level))
    end
    if info.className then
        table.insert(details, info.className)
    end
    if #details > 0 then
        table.insert(parts, table.concat(details, " "))
    end
    if info.online then
        table.insert(parts, (info.zone and info.zone ~= "") and ("online in " .. info.zone) or "online")
    else
        table.insert(parts, "offline")
    end
    return "  " .. table.concat(parts, " - ")
end

-- Lines describing `persons` (from IdentityStore:FindByQuery) for `query`.
-- `infoFor(key)` returns a character's roster entry; `profileFor(personId)`
-- returns the person's profile or nil.
function WhoFormatter.Lines(query, persons, infoFor, profileFor)
    if #persons == 0 then
        return { ('No guildmate matches "%s". Try a character name, first name, or alias.'):format(query) }
    end
    local lines = {}
    if #persons > 1 then
        table.insert(lines, ('%d people match "%s":'):format(#persons, query))
    end
    for _, person in ipairs(persons) do
        local main = infoFor(person.mainKey)
        table.insert(lines, ("%s (main: %s)"):format(person.displayName, main and main.name or person.mainKey))
        for _, key in ipairs(person.characters) do
            local info = infoFor(key)
            if info then
                table.insert(lines, characterLine(info, key == person.mainKey))
            end
        end
        local profile = profileFor and profileFor(person.id)
        if profile and profile.discord then
            table.insert(lines, "  Discord: " .. profile.discord)
        end
        if profile and profile.bio then
            table.insert(lines, "  Bio: " .. profile.bio)
        end
        local helps = profile and addon.Helping.Labels(profile.helps) or {}
        if #helps > 0 then
            table.insert(lines, "  Helps with: " .. table.concat(helps, ", "))
        end
    end
    return lines
end
