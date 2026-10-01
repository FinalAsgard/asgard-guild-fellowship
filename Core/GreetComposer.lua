local _, addon = ...

-- Turns arrivals into a greeting line. Pure: the caller passes the names, the
-- player's templates, and a random function.
local GreetComposer = {}
addon.GreetComposer = GreetComposer

-- Used until the player writes their own.
GreetComposer.DEFAULT_RETURN = {
    "Welcome back, {name}!",
    "Hey {name}, welcome back!",
    "Good to see you, {name}!",
    "Hi {name}!",
}

-- "Zel" or "Zel and Kira".
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

-- A greeting for `names` from `templates` (DEFAULT_RETURN when empty or nil).
-- `random(n)` returns an integer from 1 to n.
function GreetComposer.Compose(names, templates, random)
    if not templates or #templates == 0 then
        templates = GreetComposer.DEFAULT_RETURN
    end
    return GreetComposer.Fill(templates[random(#templates)], names)
end
