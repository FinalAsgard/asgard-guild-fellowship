local _, addon = ...

-- Decides whether to accept records received from other add-on users. Pure:
-- decisions depend only on the record and the receiver's own roster view, so
-- nobody can change another person's identity against the guild notes.
local SyncMerge = {}
addon.SyncMerge = SyncMerge

-- A resolution record says "the alt `altKey` links to the character whose GUID
-- is `record.target`, from the note ref `record.ref`". Returns true, or false
-- and a reason:
--   malformed     the record isn't shaped like a resolution
--   unknown alt   the alt isn't in the receiver's roster
--   note changed  the alt's current note has a different (or no) main ref
--   conflict      the receiver's notes resolve the ref to someone else, unambiguously
--   inconsistent  the target's name doesn't match the ref (a forged link)
--   keeping local the receiver already holds a different link that still fits
function SyncMerge.Resolution(altKey, record, snapshot, cachedResolutions)
    if type(altKey) ~= "string" or type(record) ~= "table" or type(record.ref) ~= "string"
        or type(record.target) ~= "string" then
        return false, "malformed"
    end
    local Resolver = addon.IdentityResolver
    local index = Resolver.Index(snapshot)
    local alt = index.members[altKey]
    if not alt then
        return false, "unknown alt"
    end
    local ref = index.notes[altKey].mainRef
    if not ref or ref:lower() ~= record.ref:lower() then
        return false, "note changed"
    end
    local candidates = Resolver.Candidates(index, ref, alt)
    if #candidates == 1 and candidates[1].guid ~= record.target then
        return false, "conflict"
    end
    local isCandidate = {}
    for _, candidate in ipairs(candidates) do
        isCandidate[candidate.guid] = true
    end
    if not isCandidate[record.target] then
        return false, "inconsistent"
    end
    local existing = (cachedResolutions or {})[altKey]
    if existing and existing.target ~= record.target and isCandidate[existing.target]
        and type(existing.ref) == "string" and existing.ref:lower() == ref:lower() then
        return false, "keeping local"
    end
    return true
end

-- A guildSettings record (see GuildSettings). Accepted only when it is newer
-- than the receiver's and both its publisher and the peer relaying it hold an
-- addon-officer rank in the receiver's roster, judged by the receiver's current
-- record (or the default). A relayed record can't prove who published it, so
-- the relaying peer must be trusted too: only officers can spread settings.
-- `members`: key -> roster entry. `ranks`: the guild's ranks (Compat.GuildRanks).
-- Returns true, or false and one of: malformed, not newer, not an officer,
-- untrusted relay.
function SyncMerge.GuildSettings(record, current, senderKey, members, ranks)
    if type(record) ~= "table" or type(record.version) ~= "number" or type(record.publisher) ~= "string"
        or type(record.officerRanks) ~= "table" then
        return false, "malformed"
    end
    for index, enabled in pairs(record.officerRanks) do
        if type(index) ~= "number" or enabled ~= true then
            return false, "malformed"
        end
    end
    if current and type(current.version) == "number" and record.version <= current.version then
        return false, "not newer"
    end
    local officerRanks = addon.GuildSettings.OfficerRanks(current, ranks)
    local function isOfficer(key)
        local member = members[key]
        return member ~= nil and member.rankIndex ~= nil and officerRanks[member.rankIndex] == true
    end
    if not isOfficer(record.publisher) then
        return false, "not an officer"
    end
    if not isOfficer(senderKey) then
        return false, "untrusted relay"
    end
    return true
end
