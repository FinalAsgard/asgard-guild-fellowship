local _, addon = ...

-- The guild as people rather than characters, for the Guild Roster window.
-- Pure: it only reads the stores it is given.
local RosterView = {}
addon.RosterView = RosterView

-- The roster: { people, onlinePeople, totalPeople, onlineCharacters }. Each
-- person: { personId, name, alias, status, online, current (the character
-- they're on, or nil), characters = { main first: { key, name, level, class,
-- className, online, zone, isMain } }, helps = { topic labels } }. Online people come first, then by name.
-- `store`: IdentityStore. `availability`: Availability (or nil: everyone "none").
-- `options`:
--   query        keep only people matching it the way /gf who does (character
--                name, Name-Realm, first name, or alias); empty keeps everyone
--   showOffline  false hides people with no character online (default true)
--   profileOf    personId -> profile or nil, for what they help with (`helps`)
--   helps        a Helping topic: only people who help with it (nil: any)
-- The counts always describe the whole guild, whatever the options keep.
function RosterView.Build(store, availability, options)
    options = options or {}
    local matches
    local query = options.query and options.query:match("^%s*(.-)%s*$") or ""
    if query ~= "" then
        matches = {}
        for _, person in ipairs(store:FindByQuery(query)) do
            matches[person.id] = true
        end
    end
    local people = {}
    local onlinePeople, totalPeople, onlineCharacters = 0, 0, 0
    for _, personId in ipairs(store:GetPersonIds()) do
        local person = store:GetPersonById(personId)
        local characters, current = {}, nil
        for _, charKey in ipairs(store:GetCharacters(personId) or {}) do
            local info = store:GetCharacterInfo(charKey)
            if info then
                local char = {
                    key = charKey,
                    name = info.name or addon.Compat.NameFromKey(charKey),
                    level = info.level,
                    class = info.class,
                    className = info.className,
                    online = info.online == true,
                    zone = info.zone,
                    isMain = charKey == person.mainKey,
                }
                table.insert(characters, char)
                if char.online then
                    onlineCharacters = onlineCharacters + 1
                    current = current or char
                end
            end
        end
        if #characters > 0 then
            if current then
                onlinePeople = onlinePeople + 1
            end
            totalPeople = totalPeople + 1
        end
        local profile = options.profileOf and options.profileOf(personId)
        local helps = profile and profile.helps
        if #characters > 0 and (not matches or matches[personId])
            and (current or options.showOffline ~= false)
            and (not options.helps or addon.Helping.Has(helps, options.helps)) then
            table.insert(people, {
                personId = personId,
                name = store:GetDisplayName(personId) or characters[1].name,
                alias = person.alias,
                status = availability and availability:Get(personId) or "none",
                online = current ~= nil,
                current = current,
                characters = characters,
                helps = addon.Helping.Labels(helps),
            })
        end
    end
    table.sort(people, function(a, b)
        if a.online ~= b.online then
            return a.online
        end
        if a.name:lower() ~= b.name:lower() then
            return a.name:lower() < b.name:lower()
        end
        return a.personId < b.personId
    end)
    return { people = people, onlinePeople = onlinePeople, totalPeople = totalPeople,
        onlineCharacters = onlineCharacters }
end

-- "12 of 40 people online (15 characters)".
function RosterView.Summary(roster)
    return ("%d of %d %s online (%d %s)"):format(roster.onlinePeople, roster.totalPeople,
        roster.totalPeople == 1 and "person" or "people", roster.onlineCharacters,
        roster.onlineCharacters == 1 and "character" or "characters")
end

-- Display lines for one person: a headline, then their characters.
--   "Final · online as Shiro (Elwynn Forest) · Up for Dungeons"
--   "    Dresden — Mage 60 (main, offline) · Shiro — Paladin 34"
--   "Bob · offline"
--   "    Bob — Hunter 60 (main) · Bobadin — Paladin 45"
-- Characters are marked offline only while their person is online, to show
-- which one they're on.
function RosterView.Lines(entry)
    local headline = { entry.name }
    if entry.current then
        local zone = entry.current.zone
        table.insert(headline, ("online as %s%s"):format(entry.current.name,
            (zone and zone ~= "") and (" (" .. zone .. ")") or ""))
    else
        table.insert(headline, "offline")
    end
    if entry.status ~= "none" then
        local label = addon.Availability.LABELS[entry.status]
        table.insert(headline, entry.status == "busy" and label or ("Up for " .. label))
    end
    if entry.helps and #entry.helps > 0 then
        table.insert(headline, "Helps with: " .. table.concat(entry.helps, ", "))
    end
    local characters = {}
    for _, char in ipairs(entry.characters) do
        local notes = {}
        if char.isMain then
            table.insert(notes, "main")
        end
        if entry.online and not char.online then
            table.insert(notes, "offline")
        end
        local text = ("%s — %s %s"):format(char.name, char.className or char.class or "?",
            tostring(char.level or "?"))
        if #notes > 0 then
            text = ("%s (%s)"):format(text, table.concat(notes, ", "))
        end
        table.insert(characters, text)
    end
    return { table.concat(headline, " · "), "    " .. table.concat(characters, " · ") }
end
