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
