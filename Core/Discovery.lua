local _, addon = ...

-- Who could I play with right now? Builds the Discovery list from identity and
-- availability. Pure: it only reads the stores it is given.
local Discovery = {}
addon.Discovery = Discovery

-- Levels either side of the player's current character that count as a match.
Discovery.LEVEL_RANGE = 3

-- Whether `level` suits playing with a character of `myLevel`. At the level cap
-- (`maxLevel`, nil when unknown) only other capped characters match.
function Discovery.Matches(level, myLevel, range, maxLevel)
    if type(level) ~= "number" or type(myLevel) ~= "number" then
        return false
    end
    if maxLevel and myLevel >= maxLevel then
        return level >= maxLevel
    end
    return math.abs(level - myLevel) <= range
end

local function character(charKey, info)
    return {
        key = charKey,
        name = info.name or addon.Compat.NameFromKey(charKey),
        level = info.level,
        class = info.class,
        className = info.className,
        online = info.online == true,
        zone = info.zone,
    }
end

-- Sort order by status: up for something, then no status, then Busy.
local function rank(status)
    if status == "busy" then
        return 3
    end
    return status == "none" and 2 or 1
end

-- The people to show, sorted: those up for something first and Busy last, then
-- those with a character in level range, then by name. Each entry:
--   { personId, name, status, character (the one they're on), zone,
--     matching = { characters in level range, online or not } }
-- `store`: IdentityStore. `availability`: Availability (or nil: everyone "none").
-- `me`: { personId, level } for the player's current character.
-- `options`: { range = levels, maxLevel = level cap or nil, showBusy = boolean }.
-- Only people with a character online are listed; the player is left out, and
-- people who set Busy are too unless showBusy.
function Discovery.Build(store, availability, me, options)
    options = options or {}
    local range = options.range or Discovery.LEVEL_RANGE
    local people = {}
    for _, personId in ipairs(store:GetPersonIds()) do
        if personId ~= me.personId then
            local status = availability and availability:Get(personId) or "none"
            local current
            local matching = {}
            for _, charKey in ipairs(store:GetCharacters(personId) or {}) do
                local info = store:GetCharacterInfo(charKey)
                if info then
                    if info.online and not current then
                        current = character(charKey, info)
                    end
                    if Discovery.Matches(info.level, me.level, range, options.maxLevel) then
                        table.insert(matching, character(charKey, info))
                    end
                end
            end
            if current and (status ~= "busy" or options.showBusy) then
                table.insert(people, {
                    personId = personId,
                    name = store:GetDisplayName(personId) or current.name,
                    status = status,
                    character = current,
                    zone = current.zone,
                    matching = matching,
                })
            end
        end
    end
    table.sort(people, function(a, b)
        local aRank, bRank = rank(a.status), rank(b.status)
        if aRank ~= bRank then
            return aRank < bRank
        end
        local aMatch, bMatch = #a.matching > 0, #b.matching > 0
        if aMatch ~= bMatch then
            return aMatch
        end
        if a.name:lower() ~= b.name:lower() then
            return a.name:lower() < b.name:lower()
        end
        return a.personId < b.personId
    end)
    return people
end

-- "Mage 60" or "Warrior 34 (offline)".
local function describe(char)
    local text = ("%s %s"):format(char.className or char.class or "?", tostring(char.level or "?"))
    if not char.online then
        text = text .. " (offline)"
    end
    return text
end

-- Display lines for one entry: a headline and, when they have any, their
-- characters in level range.
--   "Mike — Malgen, Mage 60 · Up for Dungeons · Elwynn Forest"
--   "    At your level: Brokk, Warrior 34 (offline)" (only when one matches)
function Discovery.Lines(entry)
    local parts = { ("%s — %s, %s"):format(entry.name, entry.character.name, describe(entry.character)) }
    if entry.status ~= "none" then
        local label = addon.Availability.LABELS[entry.status]
        table.insert(parts, entry.status == "busy" and label or ("Up for " .. label))
    end
    if entry.zone and entry.zone ~= "" then
        table.insert(parts, entry.zone)
    end
    local lines = { table.concat(parts, " · ") }
    local matches = {}
    for _, char in ipairs(entry.matching) do
        table.insert(matches, ("%s, %s"):format(char.name, describe(char)))
    end
    if #matches > 0 then
        table.insert(lines, "    At your level: " .. table.concat(matches, "; "))
    end
    return lines
end
