local _, addon = ...

-- Plans guild note edits for the Note Helper: link an alt to a main, or set a
-- main's alias. Pure: works on a roster snapshot and never writes anything.
local NoteHelper = {}
addon.NoteHelper = NoteHelper

-- The shortest reference to `main` that the resolver links unambiguously from
-- `alt`'s note: the first name, else the full name, else Name-Realm.
function NoteHelper.ShortestRef(index, main, alt)
    local Resolver = addon.IdentityResolver
    for _, ref in ipairs({ main.name:match("^(%S+)"), main.name, main.key }) do
        local candidates = Resolver.Candidates(index, ref, alt)
        if #candidates == 1 and candidates[1] == main then
            return ref
        end
    end
    return main.key
end

-- Roster choices for the pickers, sorted by name: { all, editable }, each a
-- list of { key, name }. `canEdit(charKey)` says whose note this player may edit.
function NoteHelper.Choices(snapshot, canEdit)
    local all, editable = {}, {}
    for _, member in ipairs(snapshot) do
        local choice = { key = member.key, name = member.name }
        table.insert(all, choice)
        if canEdit(member.key) then
            table.insert(editable, choice)
        end
    end
    local function byName(a, b)
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.key < b.key
    end
    table.sort(all, byName)
    table.sort(editable, byName)
    return { all = all, editable = editable }
end

-- Plans the edit described by `state`:
--   { mode = "link", alt = charKey, main = charKey }   alt's note gets >Ref
--   { mode = "alias", main = charKey, alias = text }   main's note gets @Alias ("" removes it)
-- Returns { member, current, text, fits, overflowBy, limit, canWrite, reason }.
-- `member` is the character whose note changes. Other text in the note is kept.
-- `reason` explains why canWrite is false.
function NoteHelper.Plan(state, snapshot, canEdit, limit)
    limit = limit or addon.NoteCodec.NOTE_LIMIT
    local index = addon.IdentityResolver.Index(snapshot)
    local plan = { limit = limit, canWrite = false }
    local member = index.members[state.mode == "alias" and state.main or state.alt]
    if not member then
        plan.reason = state.mode == "alias" and "Pick a main." or "Pick an alt."
        return plan
    end
    plan.member = member
    plan.current = member.note or ""
    local parts = addon.NoteCodec.parse(plan.current)
    if state.mode == "alias" then
        local alias = (state.alias or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if alias:find("[%s@>:|]") then
            plan.reason = "An alias is one word without @, >, :, or |."
            return plan
        end
        parts.alias = alias ~= "" and alias or nil
    else
        local main = index.members[state.main]
        if not main or main == member then
            plan.reason = "Pick the main this alt belongs to."
            return plan
        end
        parts.mainRef = NoteHelper.ShortestRef(index, main, member)
    end
    local composed = addon.NoteCodec.compose(parts, limit)
    plan.text, plan.fits, plan.overflowBy = composed.text, composed.fits, composed.overflowBy
    if not canEdit(member.key) then
        plan.reason = "You can't edit " .. member.name .. "'s note."
    elseif not plan.fits then
        plan.reason = ("The note would be %d characters too long. Shorten its other text first."):format(
            plan.overflowBy)
    elseif plan.text == plan.current then
        plan.reason = "The note already says this."
    else
        plan.canWrite = true
    end
    return plan
end
