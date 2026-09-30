local _, addon = ...

-- Tags guild chat lines with who is speaking: `[Guild] [Malgen Zelwindran]: [Zel] Hi`.
-- The tag goes at the start of the message, right after the clickable name. The
-- name and its link are left untouched, so whisper/invite/report keep working,
-- and a message filter is the supported, taint-free way to change chat text.
local ChatTag = {}
addon.ChatTag = ChatTag

ChatTag.EVENTS = { "CHAT_MSG_GUILD" }

-- The pure tag rule.
--   alt:                 [alias or mainShortName]
--   main with alias:     [alias]
--   main without alias:  no tag
function ChatTag.Rule(speakerIsMain, alias, mainShortName)
    if speakerIsMain then
        return alias and ("[" .. alias .. "]") or nil
    end
    return "[" .. (alias or mainShortName) .. "]"
end

-- The tag for a character, or nil for an unknown one. Constant time: the store
-- already indexes characters to people.
function ChatTag.ForCharacter(store, charKey)
    local person = charKey and store:GetPerson(charKey)
    if not person then
        return nil
    end
    return ChatTag.Rule(person.mainKey == charKey, person.alias, person.shortName)
end

-- Chat message filter. Returns false plus the changed arguments to decorate a
-- line, or false alone to leave it as is.
function ChatTag.Filter(_, _, message, author, ...)
    local store = addon.identity
    if not store or addon.Compat.IsSecret(message) or addon.Compat.IsSecret(author) then
        return false
    end
    local tag = ChatTag.ForCharacter(store, addon.Compat.NormalizeName(author))
    if not tag then
        return false
    end
    return false, tag .. " " .. message, author, ...
end

function ChatTag.Register()
    for _, event in ipairs(ChatTag.EVENTS) do
        addon.Compat.AddMessageEventFilter(event, ChatTag.Filter)
    end
end
