local _, addon = ...

-- What each person is up for right now, keyed by person ID (the main's GUID):
--   { status, version, setAt, expiresAt, author = charKey }
-- A status belongs to the person, so setting it on any character covers all of
-- them. It is short-lived: it lapses STATUS_TTL after it was set, or as soon as
-- none of the person's characters are online. Only live statuses are read,
-- shared, or accepted. Statuses are kept for the session only (not saved), so
-- they also end with it; a /reload gets live ones back from guildmates.
local Availability = {}
Availability.__index = Availability
addon.Availability = Availability

-- Statuses a player can set, in menu order. "none" (cleared) is also a record
-- status, so a clear replaces an older status on every client.
Availability.STATUSES = { "questing", "dungeons", "pvp", "helping", "anything", "busy" }
Availability.LABELS = {
    questing = "Questing",
    dungeons = "Dungeons",
    pvp = "PvP",
    helping = "Helping",
    anything = "Anything",
    busy = "Busy",
}
-- Seconds a status lasts after it was set.
Availability.STATUS_TTL = 2 * 60 * 60

local KNOWN = { none = true }
for _, status in ipairs(Availability.STATUSES) do
    KNOWN[status] = true
end

function Availability.IsKnown(status)
    return KNOWN[status] == true
end

-- `store`: IdentityStore (who a character is, and who is online). `now()`: the
-- server time in seconds, shared by every client so expiry agrees.
-- `shared(personId)`: whether this client may pass on `personId`'s status (off
-- for the player's own status when they don't share it).
-- Fires AvailabilityChanged(personId); register with
-- availability.RegisterCallback(owner, "AvailabilityChanged", handler).
function Availability.New(store, now, shared)
    local availability = setmetatable({
        records = {},
        store = store,
        now = now,
        shared = shared or function()
            return true
        end,
    }, Availability)
    availability.callbacks = LibStub("CallbackHandler-1.0"):New(availability)
    return availability
end

-- True while one of the person's characters is online in the roster.
function Availability:IsOnline(personId)
    for _, charKey in ipairs(self.store:GetCharacters(personId) or {}) do
        local info = self.store:GetCharacterInfo(charKey)
        if info and info.online then
            return true
        end
    end
    return false
end

-- Whether `record` for `personId` still applies: not expired and its person online.
function Availability:IsLive(personId, record)
    return record ~= nil and self.now() < record.expiresAt and self:IsOnline(personId)
end

-- Forgets statuses that lapsed or whose person went offline, so logging off
-- ends a status for good rather than until the next login. Run after each
-- roster update.
function Availability:Prune()
    local gone = {}
    for personId, record in pairs(self.records) do
        if not self:IsLive(personId, record) then
            table.insert(gone, personId)
        end
    end
    table.sort(gone)
    for _, personId in ipairs(gone) do
        local wasSet = self.records[personId].status ~= "none"
        self.records[personId] = nil
        if wasSet then
            self.callbacks:Fire("AvailabilityChanged", personId)
        end
    end
end

-- The person's live status ("questing", ..., "busy"), or "none".
function Availability:Get(personId)
    local record = personId and self.records[personId]
    if record and self:IsLive(personId, record) then
        return record.status
    end
    return "none"
end

-- Sets (or, with "none", clears) the status of whoever `charKey` is. Returns
-- the person ID, or false and a reason ("unknown character", "unknown status").
function Availability:Set(charKey, status)
    if not Availability.IsKnown(status) then
        return false, "unknown status"
    end
    local person = charKey and self.store:GetPerson(charKey)
    if not person then
        return false, "unknown character"
    end
    local now = self.now()
    local current = self.records[person.id]
    self.records[person.id] = {
        status = status,
        version = math.max(current and current.version + 1 or 0, now),
        setAt = now,
        expiresAt = now + Availability.STATUS_TTL,
        author = charKey,
    }
    self.callbacks:Fire("AvailabilityChanged", person.id)
    return person.id
end

-- The Sync record-type handler ("availability"), keyed by person ID. Only live
-- statuses the player may share are offered.
function Availability:SyncHandler()
    local changed = {}
    local function personOf(charKey)
        local person = charKey and self.store:GetPerson(charKey)
        return person and person.id
    end
    local function offered(personId, record)
        return self:IsLive(personId, record) and self.shared(personId)
    end
    return {
        Versions = function()
            local versions = {}
            for personId, record in pairs(self.records) do
                if offered(personId, record) then
                    versions[personId] = record.version
                end
            end
            return versions
        end,
        Get = function(personId)
            local record = self.records[personId]
            if not record or not offered(personId, record) then
                return nil
            end
            return {
                status = record.status,
                version = record.version,
                setAt = record.setAt,
                expiresAt = record.expiresAt,
                author = record.author,
            }
        end,
        Receive = function(personId, record)
            if not addon.SyncMerge.Availability(personId, record, self.records[personId], personOf, self.now()) then
                return false
            end
            if not self:IsOnline(personId) then
                return false
            end
            self.records[personId] = {
                status = record.status,
                version = record.version,
                setAt = record.setAt,
                expiresAt = record.expiresAt,
                author = record.author,
            }
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
            for _, personId in ipairs(ids) do
                self.callbacks:Fire("AvailabilityChanged", personId)
            end
        end,
    }
end
