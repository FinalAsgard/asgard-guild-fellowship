local _, addon = ...

-- The rest of the add-on asks this store who a character is. It holds the
-- current guild's resolved people and fires IdentityChanged after each update.
-- Register with store.RegisterCallback(owner, "IdentityChanged", handler).
local IdentityStore = {}
IdentityStore.__index = IdentityStore
addon.IdentityStore = IdentityStore

-- `guildData` is the current guild's saved table; resolutions persist there.
function IdentityStore.New(guildData)
    local store = setmetatable({
        data = guildData,
        persons = {},
        charToPerson = {},
        members = {},
        issues = {},
    }, IdentityStore)
    store.callbacks = LibStub("CallbackHandler-1.0"):New(store)
    return store
end

-- Re-resolves identity from a roster snapshot (see IdentityResolver). The
-- saved resolutions let ambiguous links keep what they resolved to before.
function IdentityStore:Update(snapshot)
    local result = addon.IdentityResolver.resolve(snapshot, self.data.resolutions)
    self.persons = result.persons
    self.charToPerson = result.charToPerson
    self.issues = result.issues
    self.members = {}
    for _, member in ipairs(snapshot) do
        self.members[member.key] = member
    end
    self.data.resolutions = result.resolutions
    self.callbacks:Fire("IdentityChanged")
end

-- The person playing `charKey` (a normalized Name-Realm key), or nil.
function IdentityStore:GetPerson(charKey)
    local id = self.charToPerson[charKey]
    return id and self.persons[id]
end

function IdentityStore:GetPersonById(personId)
    return self.persons[personId]
end

-- A character's roster entry (name, class, className, level, online, zone, ...),
-- or nil. Treat it as read-only.
function IdentityStore:GetCharacterInfo(charKey)
    return self.members[charKey]
end

-- The person's character keys, main first. Treat the list as read-only.
function IdentityStore:GetCharacters(personId)
    local person = self.persons[personId]
    return person and person.characters
end

function IdentityStore:GetDisplayName(personId)
    local person = self.persons[personId]
    return person and person.displayName
end

function IdentityStore:GetShortName(personId)
    local person = self.persons[personId]
    return person and person.shortName
end

-- Problems with the guild's notes: a list of { type, characters, ref, fix }
-- (see IdentityResolver). Treat it as read-only.
function IdentityStore:GetIssues()
    return self.issues
end

-- People matching `text`: a character's full name, Name-Realm, or first name,
-- or a person's alias. Case-insensitive; surrounding quotes and extra spaces
-- are ignored, so two-word names work quoted or not. Sorted by display name.
function IdentityStore:FindByQuery(text)
    local query = (text or ""):gsub('^%s*["\']', ""):gsub('["\']%s*$', ""):gsub("%s+", " ")
    query = query:gsub("^ ", ""):gsub(" $", ""):lower()
    if query == "" then
        return {}
    end
    local found, results = {}, {}
    local function add(personId)
        local person = personId and self.persons[personId]
        if person and not found[personId] then
            found[personId] = true
            table.insert(results, person)
        end
    end
    for key, member in pairs(self.members) do
        local name = member.name:lower()
        if name == query or key:lower() == query or name:match("^(%S+)") == query then
            add(self.charToPerson[key])
        end
    end
    for id, person in pairs(self.persons) do
        if person.alias and person.alias:lower() == query then
            add(id)
        end
    end
    table.sort(results, function(a, b)
        if a.displayName ~= b.displayName then
            return a.displayName < b.displayName
        end
        return a.id < b.id
    end)
    return results
end
