local _, addon = ...

-- Each person's synced profile, keyed by person ID (the main's GUID) and kept
-- per guild in `guildData.profiles`:
--   { discord?, aliasFallback?, bio?, version = number, author = charKey }
-- `discord` is contact info only: it is shown labelled as Discord and is never a
-- display name, tag, search key, or alias.
local Profiles = {}
Profiles.__index = Profiles
addon.Profiles = Profiles

Profiles.FIELDS = { "discord", "aliasFallback", "bio" }
-- Maximum length of each field, in bytes.
Profiles.LIMITS = { discord = 32, aliasFallback = 24, bio = 200 }

-- Normalizes a field value: control characters and "|" (WoW's escape
-- character) become spaces, whitespace collapses, and an empty value is nil.
-- Does not shorten: callers reject values over the limit instead.
function Profiles.Clean(value)
    if type(value) ~= "string" then
        return nil
    end
    value = value:gsub("[%c|]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    if value == "" then
        return nil
    end
    return value
end

-- `store`: IdentityStore (who a character is). `now()`: the server time in
-- seconds, so a saved version beats any older one even after a reinstall wiped
-- the local copy.
-- Fires ProfileChanged(personId); register with
-- profiles.RegisterCallback(owner, "ProfileChanged", handler).
function Profiles.New(guildData, store, now)
    guildData.profiles = guildData.profiles or {}
    local profiles = setmetatable({
        data = guildData,
        store = store,
        now = now,
    }, Profiles)
    profiles.callbacks = LibStub("CallbackHandler-1.0"):New(profiles)
    return profiles
end

function Profiles:Get(personId)
    return personId and self.data.profiles[personId]
end

function Profiles:Changed(personId)
    -- The profile alias feeds display names, so identity is re-resolved.
    self.store:Refresh()
    self.callbacks:Fire("ProfileChanged", personId)
end

-- Saves `fields` (any of discord, aliasFallback, bio; "" clears one) to the
-- profile of whoever `charKey` is. Returns true, or false and a reason
-- ("unknown character" or "<field> is too long").
function Profiles:Save(charKey, fields)
    local person = charKey and self.store:GetPerson(charKey)
    if not person then
        return false, "unknown character"
    end
    local current = self.data.profiles[person.id] or { version = 0 }
    local record = { version = math.max(current.version + 1, self.now()), author = charKey }
    for _, field in ipairs(Profiles.FIELDS) do
        local value = current[field]
        if fields[field] ~= nil then
            value = Profiles.Clean(fields[field])
        end
        if value and #value > Profiles.LIMITS[field] then
            return false, field .. " is too long"
        end
        record[field] = value
    end
    self.data.profiles[person.id] = record
    self:Changed(person.id)
    return true
end

-- The Sync record-type handler ("profile"), keyed by person ID.
function Profiles:SyncHandler()
    local changed = {}
    local function personOf(charKey)
        local person = charKey and self.store:GetPerson(charKey)
        return person and person.id
    end
    return {
        Versions = function()
            local versions = {}
            for personId, record in pairs(self.data.profiles) do
                versions[personId] = record.version
            end
            return versions
        end,
        Get = function(personId)
            return self.data.profiles[personId]
        end,
        Receive = function(personId, record)
            local accepted = addon.SyncMerge.Profile(personId, record, self.data.profiles[personId], personOf)
            if not accepted then
                return false
            end
            local clean = { version = record.version, author = record.author }
            for _, field in ipairs(Profiles.FIELDS) do
                clean[field] = Profiles.Clean(record[field])
            end
            self.data.profiles[personId] = clean
            changed[personId] = true
            return true
        end,
        Commit = function()
            local ids = {}
            for personId in pairs(changed) do
                table.insert(ids, personId)
            end
            changed = {}
            table.sort(ids)
            self.store:Refresh()
            for _, personId in ipairs(ids) do
                self.callbacks:Fire("ProfileChanged", personId)
            end
        end,
    }
end
