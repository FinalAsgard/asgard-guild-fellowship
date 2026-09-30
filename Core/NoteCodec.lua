local _, addon = ...

-- Reads and writes the guild note convention. Pure: no WoW API.
--   >Ref     this character is an alt of Ref (a first name or a two-word full name)
--   @Alias   what this person wants to be called (one word)
--   main: Ref / alias: Name   legacy forms, any case
-- Everything else in the note is kept as `rest`.
local NoteCodec = {}
addon.NoteCodec = NoteCodec

-- The public note limit, in bytes. Unconfirmed in game; see the verification checklist.
NoteCodec.NOTE_LIMIT = 31

-- Position of the first `marker` that starts a word, searching `haystack`.
local function findAtWordStart(haystack, marker)
    local init = 1
    while true do
        local start = haystack:find(marker, init, true)
        if not start then
            return nil
        end
        if start == 1 or haystack:sub(start - 1, start - 1):match("%s") then
            return start
        end
        init = start + 1
    end
end

-- Reads a main reference at `pos`: one word, plus a second word when it starts
-- with a capital letter (a Forever last name). Returns the ref and the position
-- just past it.
local function readWord(text, pos)
    local word, after = text:match("^([^%s@>:][^%s:]*)()", pos)
    -- A word followed by ":" is the next legacy label, not a value.
    if word and text:sub(after, after) ~= ":" then
        return word, after
    end
end

local function readRef(text, pos)
    local first, after = readWord(text, pos)
    if not first then
        return nil
    end
    local second, afterSecond = text:match("^%s+([%u\192-\255][^%s:]*)()", after)
    if second and not text:sub(afterSecond, afterSecond):match("%S") then
        return first .. " " .. second, afterSecond
    end
    return first, after
end

-- Finds `prefix` (compact, case-sensitive) or `legacy` (case-insensitive,
-- optional spaces before the value) and reads its value with `reader`.
-- Returns value, span start, span end.
local function findToken(text, lower, prefix, legacy, reader)
    local start = findAtWordStart(text, prefix)
    if start then
        local value, after = reader(text, start + #prefix)
        if value then
            return value, start, after - 1
        end
    end
    start = findAtWordStart(lower, legacy)
    if start then
        local valueStart = text:match("^%s*()", start + #legacy)
        local value, after = reader(text, valueStart)
        if value then
            return value, start, after - 1
        end
    end
end

-- parse(note) -> { mainRef?, alias?, rest }
function NoteCodec.parse(note)
    if type(note) ~= "string" then
        note = ""
    end
    local lower = note:lower()
    local result = {}
    local spans = {}

    local mainRef, mainStart, mainEnd = findToken(note, lower, ">", "main:", readRef)
    if mainRef then
        result.mainRef = mainRef
        table.insert(spans, { mainStart, mainEnd })
    end
    local alias, aliasStart, aliasEnd = findToken(note, lower, "@", "alias:", readWord)
    if alias and not (mainStart and aliasStart <= mainEnd and aliasEnd >= mainStart) then
        result.alias = alias
        table.insert(spans, { aliasStart, aliasEnd })
    end

    table.sort(spans, function(a, b)
        return a[1] > b[1]
    end)
    local rest = note
    for _, span in ipairs(spans) do
        rest = rest:sub(1, span[1] - 1) .. " " .. rest:sub(span[2] + 1)
    end
    result.rest = rest:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return result
end

-- compose({ mainRef?, alias?, rest }, limit) -> { text, fits, overflowBy }
-- Writes `rest @Alias >Ref`. The ref goes last so no following word can be
-- mistaken for its second name. Never truncates.
function NoteCodec.compose(parts, limit)
    limit = limit or NoteCodec.NOTE_LIMIT
    local pieces = {}
    if parts.rest and parts.rest ~= "" then
        table.insert(pieces, parts.rest)
    end
    if parts.alias then
        table.insert(pieces, "@" .. parts.alias)
    end
    if parts.mainRef then
        table.insert(pieces, ">" .. parts.mainRef)
    end
    local text = table.concat(pieces, " ")
    return {
        text = text,
        fits = #text <= limit,
        overflowBy = math.max(0, #text - limit),
    }
end
