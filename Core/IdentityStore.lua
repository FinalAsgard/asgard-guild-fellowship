local _, addon = ...

-- The rest of the add-on asks this store who a character is. It holds the
-- current guild's resolved people and fires IdentityChanged after each update.
-- Register with store.RegisterCallback(owner, "IdentityChanged", handler).
local IdentityStore = {}
IdentityStore.__index = IdentityStore
addon.IdentityStore = IdentityStore

-- `guildData` is the current guild's saved table; resolutions persist there.
function IdentityStore.New(guildData)
    local store = setmetatable({ data = guildData, persons = {}, charToPerson = {} }, IdentityStore)
    store.callbacks = LibStub("CallbackHandler-1.0"):New(store)
    return store
end

-- Re-resolves identity from a roster snapshot (see IdentityResolver).
function IdentityStore:Update(snapshot)
    local result = addon.IdentityResolver.resolve(snapshot)
    self.persons = result.persons
    self.charToPerson = result.charToPerson
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
