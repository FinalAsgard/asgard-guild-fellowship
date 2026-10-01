local _, addon = ...

-- Slash command names and parsing. Registration itself happens in Core.
local Commands = {}
addon.Commands = Commands

-- Always registered.
Commands.ALWAYS = { "fellowship", "agf" }
-- Registered at login only when no other add-on owns it.
Commands.SHORT = "gf"

-- True when something other than us already registered `/command`. `env` is the
-- global table: every slash command lives in a `SLASH_<KEY><n>` global, and the
-- chat frame's `hash_SlashCmdList` holds ones already used this session.
function Commands.IsTaken(env, command)
    local wanted = "/" .. command:lower()
    local hashed = env.hash_SlashCmdList
    if type(hashed) == "table" and hashed[wanted:upper()] then
        return true
    end
    for key, value in pairs(env) do
        if type(key) == "string" and key:sub(1, 6) == "SLASH_" and type(value) == "string"
            and value:lower() == wanted then
            return true
        end
    end
    return false
end

-- Runs the handler for the first word of `input`. An empty input runs
-- `handlers[""]`; an unknown word runs `handlers.usage`.
function Commands.Dispatch(input, handlers)
    local word, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    local handler = handlers[word:lower()] or handlers.usage
    return handler(rest)
end
