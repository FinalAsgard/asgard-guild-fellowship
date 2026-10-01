local _, addon = ...

-- Turns a roster snapshot into people. Pure and deterministic: no WoW API, and
-- the same inputs always give the same result.
local IdentityResolver = {}
addon.IdentityResolver = IdentityResolver

-- How many alt-to-alt hops are followed before a chain is given up on.
IdentityResolver.MAX_CHAIN = 5

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

local function keysOf(members)
    local keys = {}
    for _, member in ipairs(members) do
        table.insert(keys, member.key)
    end
    return keys
end

local function sortedKeys(members)
    local keys = keysOf(members)
    table.sort(keys)
    return keys
end

-- Lookup tables over a snapshot, shared by resolve and SyncMerge:
--   members[key], byKey[lowered key], byFullName[lowered name], byFirstName[lowered first name],
--   notes[key] (parsed notes)
function IdentityResolver.Index(snapshot)
    local index = { members = {}, byKey = {}, byFullName = {}, byFirstName = {}, notes = {} }
    for _, member in ipairs(snapshot) do
        local lowered = member.name:lower()
        index.members[member.key] = member
        index.byKey[member.key:lower()] = { member }
        addTo(index.byFullName, lowered, member)
        addTo(index.byFirstName, firstName(lowered), member)
        index.notes[member.key] = addon.NoteCodec.parse(member.note)
    end
    return index
end

-- Everyone `ref` could mean, other than `exclude`. `Name-Realm` names one
-- character exactly; otherwise an exact full name wins over a first-name match.
-- The second result counts matches before `exclude` was removed.
function IdentityResolver.Candidates(index, ref, exclude)
    local lowered = ref:lower()
    local matches = index.byKey[lowered] or index.byFullName[lowered] or index.byFirstName[firstName(lowered)] or {}
    local candidates = {}
    for _, candidate in ipairs(matches) do
        if candidate ~= exclude then
            table.insert(candidates, candidate)
        end
    end
    return candidates, #matches
end

-- resolve(snapshot, cachedResolutions, profiles) -> { persons, charToPerson, resolutions, issues }
--   snapshot: list of { key, guid, name, note, ... } (key is Name-Realm, name has no realm)
--   cachedResolutions: the `resolutions` from an earlier run, or nil
--   profiles: person id -> profile, or nil; only `aliasFallback` is used. The
--     alias is the main's note @Alias, else the profile's aliasFallback.
--   persons[id]: { id, mainKey, characters, alias, shortName, displayName }
--     id is the main's GUID; characters lists the main first, then alts by key.
--   charToPerson[key]: person id
--   resolutions[altKey]: { main = person id, target = linked character's GUID, ref = note ref }
--     for each linked alt, plus the last known link of each orphaned alt
--   issues: list of { type, characters, ref, fix }, where type is one of
--     ambiguous, chain, cycle, orphan, unresolved
function IdentityResolver.resolve(snapshot, cachedResolutions, profiles)
    cachedResolutions = cachedResolutions or {}
    profiles = profiles or {}
    local index = IdentityResolver.Index(snapshot)
    local byFullName, byFirstName, notes = index.byFullName, index.byFirstName, index.notes

    -- The shortest name that picks out one character: the first name, then the
    -- full name, then Name-Realm (only needed for same-name cross-realm members).
    local function shortestName(member)
        local first = firstName(member.name)
        if #byFirstName[first:lower()] == 1 then
            return first
        end
        if #byFullName[member.name:lower()] == 1 then
            return member.name
        end
        return member.key
    end

    local issues = {}
    local function raise(issueType, characters, ref, fix)
        table.insert(issues, { type = issueType, characters = characters, ref = ref, fix = fix })
    end

    -- Step 1: each alt's direct target.
    local targets, orphaned = {}, {}
    for _, member in ipairs(snapshot) do
        local ref = notes[member.key].mainRef
        if ref then
            local candidates, matchCount = IdentityResolver.Candidates(index, ref, member)
            local cached = cachedResolutions[member.key]
            local cachedStillFits = cached and cached.ref and cached.ref:lower() == ref:lower()
            if #candidates == 1 then
                targets[member.key] = candidates[1]
            elseif #candidates > 1 then
                local names = {}
                for _, candidate in ipairs(candidates) do
                    if cachedStillFits and candidate.guid == cached.target then
                        targets[member.key] = candidate
                    end
                    table.insert(names, shortestName(candidate))
                end
                table.sort(names)
                raise("ambiguous", { member.key }, ref, ("%s's note >%s matches %s. Use one of those names instead.")
                    :format(member.name, ref, table.concat(names, ", ")))
            elseif matchCount == 0 then
                if cachedStillFits then
                    -- Keep the old link on record so the alt stays an orphan
                    -- rather than turning "unresolved" on the next update.
                    orphaned[member.key] = cached
                    local fix = "%s's main %s is no longer in the guild. Update or clear the note."
                    raise("orphan", { member.key }, ref, fix:format(member.name, ref))
                else
                    local fix = "No guild member matches %s in %s's note. Check the spelling."
                    raise("unresolved", { member.key }, ref, fix:format(ref, member.name))
                end
            end
        end
    end

    -- Step 2: follow alt-to-alt links to the terminal main.
    local mains, cycles = {}, {}
    for _, member in ipairs(snapshot) do
        local current = targets[member.key]
        if current then
            local path, seen, status = { member }, { [member] = true }, "ok"
            while targets[current.key] do
                if seen[current] then
                    status = "cycle"
                    break
                end
                if #path > IdentityResolver.MAX_CHAIN then
                    status = "too long"
                    break
                end
                seen[current] = true
                table.insert(path, current)
                current = targets[current.key]
            end
            local ref = notes[member.key].mainRef
            if status == "ok" then
                mains[member.key] = current
                if #path > 1 then
                    local chain = keysOf(path)
                    table.insert(chain, current.key)
                    raise("chain", chain, ref, ("%s points to %s, who is an alt of %s. Change the note to >%s.")
                        :format(member.name, path[2].name, current.name, shortestName(current)))
                end
            elseif status == "cycle" then
                -- Collect the loop itself so each cycle is reported once.
                local loop, walker = { current }, targets[current.key]
                while walker ~= current do
                    table.insert(loop, walker)
                    walker = targets[walker.key]
                end
                local loopKeys = sortedKeys(loop)
                cycles[table.concat(loopKeys, "|")] = loopKeys
            else
                raise("chain", keysOf(path), ref, ("%s's chain of main links is longer than %d. Point it at the main.")
                    :format(member.name, IdentityResolver.MAX_CHAIN))
            end
        end
    end
    for _, loopKeys in pairs(cycles) do
        raise("cycle", loopKeys, nil, ("These notes point at each other: %s. Remove the > link from the main's note.")
            :format(table.concat(loopKeys, ", ")))
    end

    -- Step 3: build people.
    local persons, charToPerson = {}, {}
    local resolutions = orphaned
    local function personFor(main)
        local id = main.guid or main.key
        local person = persons[id]
        if not person then
            local short = shortestName(main)
            local alias = notes[main.key].alias or (profiles[id] and profiles[id].aliasFallback)
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
        local main = mains[member.key]
        if main then
            local person = personFor(main)
            table.insert(person.characters, member.key)
            charToPerson[member.key] = person.id
            resolutions[member.key] = {
                main = person.id,
                target = targets[member.key].guid,
                ref = notes[member.key].mainRef,
            }
        else
            personFor(member)
        end
    end
    for _, person in pairs(persons) do
        local mainKey = table.remove(person.characters, 1)
        table.sort(person.characters)
        table.insert(person.characters, 1, mainKey)
    end

    table.sort(issues, function(a, b)
        if a.type ~= b.type then
            return a.type < b.type
        end
        return a.characters[1] < b.characters[1]
    end)

    return { persons = persons, charToPerson = charToPerson, resolutions = resolutions, issues = issues }
end
