local _, addon = ...

-- Each person's synced profile, keyed by person ID (the main's GUID) and kept
-- per guild in `guildData.profiles`:
--   { discord?, aliasFallback?, bio?, version = number, author = charKey,
--     clearedBy?, cleared? }
-- `discord` is contact info only: it is shown labelled as Discord and is never a
-- display name, tag, search key, or alias.
--
-- Addon officers can clear (never rewrite) a person's bio or alias. A clear is
-- its own update, synced as { version, author = officer, clear = { fields } }
-- with no content. Applied, it blanks those fields of the profile; the result
-- remembers `clearedBy`/`cleared` so it is passed on as the same clear. The
-- owner's next save replaces it as usual.
local Profiles = {}
Profiles.__index = Profiles
addon.Profiles = Profiles

Profiles.FIELDS = { "discord", "aliasFallback", "bio" }
-- Maximum length of each field, in bytes.
Profiles.LIMITS = { discord = 32, aliasFallback = 24, bio = 200 }
-- Fields an officer may clear.
Profiles.CLEARABLE = { bio = true, aliasFallback = true }

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
-- the local copy. `isOfficer(charKey)`: whether a character may clear profiles.
-- Fires ProfileChanged(personId); register with
-- profiles.RegisterCallback(owner, "ProfileChanged", handler).
function Profiles.New(guildData, store, now, isOfficer)
    guildData.profiles = guildData.profiles or {}
    local profiles = setmetatable({
        data = guildData,
        store = store,
        now = now,
        isOfficer = isOfficer,
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

-- `profile` with `fields` blanked by officer `officerKey`, at `version`.
local function cleared(profile, fields, officerKey, version)
    local result = { version = version, author = profile.author, clearedBy = officerKey, cleared = fields }
    local blank = {}
    for _, field in ipairs(fields) do
        blank[field] = true
    end
    for _, field in ipairs(Profiles.FIELDS) do
        if not blank[field] then
            result[field] = profile[field]
        end
    end
    return result
end

-- Clears `fields` (bio and/or aliasFallback) of person `personId`'s profile as
-- officer `officerKey`. Returns true, or false and a reason ("not an officer",
-- "nothing to clear").
function Profiles:Clear(personId, fields, officerKey)
    if not self.isOfficer(officerKey) then
        return false, "not an officer"
    end
    local current = self.data.profiles[personId]
    local hasContent = false
    for _, field in ipairs(fields) do
        assert(Profiles.CLEARABLE[field], "not a clearable field: " .. tostring(field))
        hasContent = hasContent or (current and current[field] ~= nil)
    end
    if not hasContent then
        return false, "nothing to clear"
    end
    local version = math.max(current.version + 1, self.now())
    self.data.profiles[personId] = cleared(current, fields, officerKey, version)
    self:Changed(personId)
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
            local profile = self.data.profiles[personId]
            if profile and profile.clearedBy then
                return { version = profile.version, author = profile.clearedBy, clear = profile.cleared }
            end
            return profile
        end,
        Receive = function(personId, record)
            local current = self.data.profiles[personId]
            if not addon.SyncMerge.Profile(personId, record, current, personOf, self.isOfficer) then
                return false
            end
            if record.clear then
                self.data.profiles[personId] = cleared(current or {}, record.clear, record.author, record.version)
            else
                local clean = { version = record.version, author = record.author }
                for _, field in ipairs(Profiles.FIELDS) do
                    clean[field] = Profiles.Clean(record[field])
                end
                self.data.profiles[personId] = clean
            end
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
