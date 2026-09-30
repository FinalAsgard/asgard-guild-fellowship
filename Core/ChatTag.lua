local _, addon = ...

-- Tags chat lines with who is speaking: `[Guild] [Malgen Zelwindran]: [Zel] Hi`.
-- The tag goes at the start of the message, right after the clickable name. The
-- name and its link are left untouched, so whisper/invite/report keep working,
-- and a message filter is the supported, taint-free way to change chat text.
-- Only guildmates are tagged: the identity store only knows the guild roster.
local ChatTag = {}
addon.ChatTag = ChatTag

-- Chat event -> the settings channel that controls it. Whisper covers both
-- incoming whispers and the echo of ones you send (tagged with the recipient).
ChatTag.CHANNELS = {
    CHAT_MSG_GUILD = "guild",
    CHAT_MSG_OFFICER = "officer",
    CHAT_MSG_PARTY = "party",
    CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_RAID = "raid",
    CHAT_MSG_RAID_LEADER = "raid",
    CHAT_MSG_RAID_WARNING = "raid",
    CHAT_MSG_INSTANCE_CHAT = "instance",
    CHAT_MSG_INSTANCE_CHAT_LEADER = "instance",
    CHAT_MSG_WHISPER = "whisper",
    CHAT_MSG_WHISPER_INFORM = "whisper",
}

-- Settings channels in display order.
ChatTag.CHANNEL_ORDER = { "guild", "officer", "party", "raid", "instance", "whisper" }

ChatTag.BRACKETS = {
    square = { "[", "]" },
    round = { "(", ")" },
    angle = { "<", ">" },
    none = { "", "" },
}

-- Default settings, stored in the profile as `chatTag`.
ChatTag.DEFAULTS = {
    channels = { guild = true, officer = true, party = true, raid = true, instance = true, whisper = true },
    brackets = "square",
    colored = false,
    color = { r = 0.25, g = 0.78, b = 0.92 },
}

-- The pure tag rule: which name to show, or nil for no tag.
--   alt:                 alias, else the main's short name
--   main with alias:     alias
--   main without alias:  no tag
function ChatTag.Rule(speakerIsMain, alias, mainShortName)
    if speakerIsMain then
        return alias
    end
    return alias or mainShortName
end

-- Wraps a tag name in the configured brackets and color.
function ChatTag.Format(name, settings)
    local brackets = ChatTag.BRACKETS[settings.brackets] or ChatTag.BRACKETS.square
    local text = brackets[1] .. name .. brackets[2]
    if settings.colored and settings.color then
        local color = settings.color
        local function byte(value)
            return math.floor(value * 255 + 0.5)
        end
        text = ("|cff%02x%02x%02x%s|r"):format(byte(color.r), byte(color.g), byte(color.b), text)
    end
    return text
end

-- The tag name for a character, or nil for someone outside the guild. Constant
-- time: the store already indexes characters to people.
function ChatTag.ForCharacter(store, charKey)
    local person = charKey and store:GetPerson(charKey)
    if not person then
        return nil
    end
    return ChatTag.Rule(person.mainKey == charKey, person.alias, person.shortName)
end

-- `getSettings` returns the current chatTag settings. It is read on every
-- message, so settings changes apply immediately.
function ChatTag.Register(getSettings)
    local function filter(_, event, message, author, ...)
        local store = addon.identity
        local settings = getSettings()
        if not store or not settings.channels[ChatTag.CHANNELS[event]] then
            return false
        end
        -- Messages the client won't let add-ons read are left alone.
        if addon.Compat.IsSecret(message) or addon.Compat.IsSecret(author)
            or type(message) ~= "string" or type(author) ~= "string" then
            return false
        end
        local name = ChatTag.ForCharacter(store, addon.Compat.NormalizeName(author))
        if not name then
            return false
        end
        return false, ChatTag.Format(name, settings) .. " " .. message, author, ...
    end
    for event in pairs(ChatTag.CHANNELS) do
        addon.Compat.AddMessageEventFilter(event, filter)
    end
end
