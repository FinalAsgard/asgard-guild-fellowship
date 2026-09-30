local _, addon = ...

-- Turns a roster snapshot into people. Pure and deterministic: no WoW API, and
-- the same snapshot always gives the same result.
local IdentityResolver = {}
addon.IdentityResolver = IdentityResolver

local function firstName(name)
    return name:match("^(%S+)")
end

local function addTo(index, key, member)
    local list = index[key]
    if not list then
        list = {}
        index[key] = list
    end
    table.insert(list, member)
end

-- The character `ref` names. An exact full-name match wins; otherwise the ref's
-- first word must match exactly one character's first name.
local function match(ref, byFullName, byFirstName)
    local lowered = ref:lower()
    local exact = byFullName[lowered]
    if exact then
        return #exact == 1 and exact[1] or nil
    end
    local candidates = byFirstName[firstName(lowered)]
    if candidates and #candidates == 1 then
        return candidates[1]
    end
end

-- resolve(snapshot) -> { persons, charToPerson, resolutions }
--   snapshot: list of { key, guid, name, note, ... } (name has no realm)
--   persons[id]: { id, mainKey, characters, alias, shortName, displayName }
--     id is the main's GUID; characters lists the main first, then alts by key.
--   charToPerson[key]: person id
--   resolutions[altKey]: { main = person id, ref = the note's main ref }
function IdentityResolver.resolve(snapshot)
    local byFullName, byFirstName, notes = {}, {}, {}
    for _, member in ipairs(snapshot) do
        local lowered = member.name:lower()
        addTo(byFullName, lowered, member)
        addTo(byFirstName, firstName(lowered), member)
        notes[member.key] = addon.NoteCodec.parse(member.note)
    end

    local targets = {}
    for _, member in ipairs(snapshot) do
        local ref = notes[member.key].mainRef
        local target = ref and match(ref, byFullName, byFirstName)
        if target and target ~= member then
            targets[member.key] = target
        end
    end

    local persons, charToPerson, resolutions = {}, {}, {}
    local function personFor(main)
        local id = main.guid or main.key
        local person = persons[id]
        if not person then
            local short = main.name
            if #byFirstName[firstName(main.name:lower())] == 1 then
                short = firstName(main.name)
            end
            local alias = notes[main.key].alias
            person = {
                id = id,
                mainKey = main.key,
                characters = { main.key },
                alias = alias,
                shortName = short,
                displayName = alias or short,
            }
            persons[id] = person
            charToPerson[main.key] = id
        end
        return person
    end

    for _, member in ipairs(snapshot) do
        local target = targets[member.key]
        -- A link to a character that is itself linked is a chain; it stays
        -- unlinked until chains are supported.
        if target and not targets[target.key] then
            local person = personFor(target)
            table.insert(person.characters, member.key)
            charToPerson[member.key] = person.id
            resolutions[member.key] = { main = person.id, ref = notes[member.key].mainRef }
        else
            personFor(member)
        end
    end

    for _, person in pairs(persons) do
        local main = table.remove(person.characters, 1)
        table.sort(person.characters)
        table.insert(person.characters, 1, main)
    end

    return { persons = persons, charToPerson = charToPerson, resolutions = resolutions }
end
