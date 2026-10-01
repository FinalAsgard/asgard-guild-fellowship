local _, addon = ...

-- Turns arrivals into greeting lines. Pure: the caller passes the names, the
-- player's templates, and a random function.
local GreetComposer = {}
addon.GreetComposer = GreetComposer

-- The longest line guild chat accepts.
GreetComposer.MAX_LINE = 255

-- Used until the player writes their own.
GreetComposer.DEFAULT_RETURN = {
    "Welcome back, {name}!",
    "Hey {name}, welcome back!",
    "Good to see you, {name}!",
    "Hi {name}!",
}

-- "Zel", "Zel and Kira", "Zel, Kira and Mike".
function GreetComposer.JoinNames(names)
    if #names <= 1 then
        return names[1] or ""
    end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- Fills `template` with the names. A template without {name} gets them appended.
function GreetComposer.Fill(template, names)
    local joined = GreetComposer.JoinNames(names)
    if template:find("{name}", 1, true) then
        return (template:gsub("{name}", function()
            return joined
        end))
    end
    return template .. " " .. joined
end

-- The usable templates: color codes (|cAARRGGBB ... |r) and any other "|"
-- (WoW's escape character) or control characters removed, surrounding space
-- trimmed, blank entries dropped.
function GreetComposer.Clean(templates)
    local result = {}
    for _, template in ipairs(templates or {}) do
        if type(template) == "string" then
            local clean = template:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("[%c|]", "")
            clean = clean:gsub("^%s+", ""):gsub("%s+$", "")
            if clean ~= "" then
                table.insert(result, clean)
            end
        end
    end
    return result
end

-- A random index from 1 to `count` that isn't `previous` (when count > 1).
-- `random(n)` returns an integer from 1 to n.
function GreetComposer.Pick(count, previous, random)
    if count <= 1 then
        return 1
    end
    local index = random(count - 1)
    if previous and index >= previous then
        index = index + 1
    end
    return index
end

-- Greeting lines for `names`, from the player's `templates` (cleaned; the
-- defaults when none are usable), never reusing template `previous` back to
-- back. Names that don't fit in one MAX_LINE line spill into further lines
-- with the same template; nothing is cut. Returns the lines and the template
-- index used.
function GreetComposer.Lines(names, templates, random, previous)
    templates = GreetComposer.Clean(templates)
    if #templates == 0 then
        templates = GreetComposer.DEFAULT_RETURN
    end
    local index = GreetComposer.Pick(#templates, previous, random)
    local template = templates[index]
    local lines, batch = {}, {}
    for _, name in ipairs(names) do
        table.insert(batch, name)
        if #batch > 1 and #GreetComposer.Fill(template, batch) > GreetComposer.MAX_LINE then
            table.remove(batch)
            table.insert(lines, GreetComposer.Fill(template, batch))
            batch = { name }
        end
    end
    if #batch > 0 then
        table.insert(lines, GreetComposer.Fill(template, batch))
    end
    return lines, index
end
