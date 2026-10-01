local _, addon = ...

-- The guild-wide settings record that addon officers publish to every member:
-- for now, which ranks count as addon officers. Without a record, officers are
-- the guild master's rank plus any rank that can edit officer notes.
--
-- Record: { version = number, officerRanks = { [rankIndex] = true }, publisher = charKey }
-- rankIndex is the roster's 0-based rank (0 = guild master).
local GuildSettings = {}
GuildSettings.__index = GuildSettings
addon.GuildSettings = GuildSettings

-- The sync record id; a guild has one settings record.
GuildSettings.RECORD_ID = "guild"

-- Default officer ranks from `ranks` (list of { index, name, canEditOfficerNote }).
function GuildSettings.DefaultOfficerRanks(ranks)
    local officerRanks = { [0] = true }
    for _, rank in ipairs(ranks) do
        if rank.canEditOfficerNote then
            officerRanks[rank.index] = true
        end
    end
    return officerRanks
end

-- The officer ranks in force: the record's, or the default. The guild master's
-- rank always counts, so a published record can never lock everyone out of
-- correcting it.
function GuildSettings.OfficerRanks(record, ranks)
    if record and type(record.officerRanks) == "table" then
        local officerRanks = { [0] = true }
        for index, enabled in pairs(record.officerRanks) do
            officerRanks[index] = enabled
        end
        return officerRanks
    end
    return GuildSettings.DefaultOfficerRanks(ranks)
end

-- `guildData`: the guild's saved table (the record lives in `guildSettings`).
-- `store`: IdentityStore, for members' current ranks.
-- `getRanks`: returns the guild's ranks (Compat.GuildRanks).
-- Fires GuildSettingsChanged when the record changes; register with
-- settings.RegisterCallback(owner, "GuildSettingsChanged", handler).
function GuildSettings.New(guildData, store, getRanks)
    local settings = setmetatable({ data = guildData, store = store, getRanks = getRanks }, GuildSettings)
    settings.callbacks = LibStub("CallbackHandler-1.0"):New(settings)
    return settings
end

function GuildSettings:Record()
    return self.data.guildSettings
end

function GuildSettings:GetOfficerRanks()
    return GuildSettings.OfficerRanks(self:Record(), self.getRanks())
end

-- Whether `charKey`'s current roster rank makes them an addon officer.
function GuildSettings:IsAddonOfficer(charKey)
    local member = charKey and self.store:GetCharacterInfo(charKey)
    return member ~= nil and member.rankIndex ~= nil and self:GetOfficerRanks()[member.rankIndex] == true
end

-- Publishes a new record with `officerRanks` as `publisherKey`. Returns false
-- unless the publisher is an addon officer right now.
function GuildSettings:Publish(officerRanks, publisherKey)
    if not self:IsAddonOfficer(publisherKey) then
        return false
    end
    local ranks = { [0] = true }
    for index, enabled in pairs(officerRanks) do
        if enabled then
            ranks[index] = true
        end
    end
    local current = self:Record()
    self.data.guildSettings = {
        version = (current and current.version or 0) + 1,
        officerRanks = ranks,
        publisher = publisherKey,
    }
    self.callbacks:Fire("GuildSettingsChanged")
    return true
end

-- The Sync record-type handler ("guildSettings").
function GuildSettings:SyncHandler()
    local id = GuildSettings.RECORD_ID
    return {
        Versions = function()
            local record = self:Record()
            return record and { [id] = record.version } or {}
        end,
        Get = function(recordId)
            return recordId == id and self:Record() or nil
        end,
        Receive = function(recordId, record)
            if recordId ~= id then
                return false
            end
            local members = {}
            for _, member in ipairs(self.store.snapshot or {}) do
                members[member.key] = member
            end
            if not addon.SyncMerge.GuildSettings(record, self:Record(), members, self.getRanks()) then
                return false
            end
            self.data.guildSettings = {
                version = record.version,
                officerRanks = record.officerRanks,
                publisher = record.publisher,
            }
            return true
        end,
        Commit = function()
            self.callbacks:Fire("GuildSettingsChanged")
        end,
    }
end
