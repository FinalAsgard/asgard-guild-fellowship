local addonName, addon = ...

-- The settings panel, registered with AceConfig and shown in the standard
-- options panel. Features add their toggles to the "features" group.
local Options = {}
addon.Options = Options

Options.TITLE = "Asgard's Guild Fellowship"

local CHANNEL_NAMES = {
    guild = "Guild",
    officer = "Officer",
    party = "Party",
    raid = "Raid",
    instance = "Instance",
    whisper = "Whispers",
}

-- The chat tag group. `getSettings` returns the live chatTag settings table, so
-- every change applies to the next chat line without a reload.
local function chatTagGroup(getSettings)
    local channels = {
        type = "group",
        name = "Tag guildmates in",
        inline = true,
        order = 2,
        args = {},
    }
    for index, channel in ipairs(addon.ChatTag.CHANNEL_ORDER) do
        channels.args[channel] = {
            type = "toggle",
            name = CHANNEL_NAMES[channel],
            order = index,
            get = function()
                return getSettings().channels[channel]
            end,
            set = function(_, value)
                getSettings().channels[channel] = value
            end,
        }
    end
    return {
        type = "group",
        name = "Chat tag",
        inline = true,
        order = 1,
        args = {
            description = {
                type = "description",
                name = "Shows who a guildmate is, e.g. [Zel], at the start of their chat lines.",
                order = 1,
            },
            channels = channels,
            brackets = {
                type = "select",
                name = "Brackets",
                order = 3,
                values = { square = "[Zel]", round = "(Zel)", angle = "<Zel>", none = "Zel" },
                sorting = { "square", "round", "angle", "none" },
                get = function()
                    return getSettings().brackets
                end,
                set = function(_, value)
                    getSettings().brackets = value
                end,
            },
            colored = {
                type = "toggle",
                name = "Color the tag",
                order = 4,
                get = function()
                    return getSettings().colored
                end,
                set = function(_, value)
                    getSettings().colored = value
                end,
            },
            color = {
                type = "color",
                name = "Tag color",
                order = 5,
                disabled = function()
                    return not getSettings().colored
                end,
                get = function()
                    local color = getSettings().color
                    return color.r, color.g, color.b
                end,
                set = function(_, r, g, b)
                    getSettings().color = { r = r, g = g, b = b }
                end,
            },
        },
    }
end

-- The guild settings group. `guild` provides:
--   Settings()      the current guild's GuildSettings, or nil outside a guild
--   Player()        this character's key
--   Publish(ranks)  publishes officer ranks ({ [rankIndex] = true }) to the guild
-- Officers edit a draft of the officer ranks and publish it; everyone else sees
-- the ranks in force, read-only.
local function guildSettingsGroup(guild)
    local draft
    local function isOfficer()
        local settings = guild.Settings()
        return settings ~= nil and settings:IsAddonOfficer(guild.Player())
    end
    local function selected()
        if draft then
            return draft
        end
        local settings = guild.Settings()
        return settings and settings:GetOfficerRanks() or {}
    end
    return {
        type = "group",
        name = "Guild settings",
        inline = true,
        order = 3,
        args = {
            status = {
                type = "description",
                order = 1,
                name = function()
                    local settings = guild.Settings()
                    if not settings then
                        return "Join a guild to see its add-on settings."
                    end
                    local record = settings:Record()
                    local source = record
                        and ("Published by %s (version %d)."):format(record.publisher, record.version)
                        or "Using the default: the guild master's rank plus ranks that can edit officer notes."
                    if isOfficer() then
                        return "Choose which ranks count as officers for the add-on, then publish to every member. "
                            .. source
                    end
                    return "Set by your guild's add-on officers (read-only). " .. source
                end,
            },
            officerRanks = {
                type = "multiselect",
                name = "Officer ranks",
                order = 2,
                hidden = function()
                    return guild.Settings() == nil
                end,
                disabled = function()
                    return not isOfficer()
                end,
                values = function()
                    local values = {}
                    for _, rank in ipairs(addon.Compat.GuildRanks()) do
                        values[rank.index] = rank.name
                    end
                    return values
                end,
                get = function(_, index)
                    return selected()[index] == true
                end,
                set = function(_, index, value)
                    -- The guild master's rank always counts (see GuildSettings).
                    if index == 0 then
                        return
                    end
                    local ranks = {}
                    for rankIndex in pairs(selected()) do
                        ranks[rankIndex] = true
                    end
                    ranks[index] = value or nil
                    draft = ranks
                end,
            },
            publish = {
                type = "execute",
                name = "Publish to guild",
                order = 3,
                hidden = function()
                    return not isOfficer()
                end,
                func = function()
                    if guild.Publish(selected()) then
                        draft = nil
                    end
                end,
            },
        },
    }
end

local PROFILE_FIELDS = {
    { key = "discord", name = "Discord name",
        desc = "Contact info only, so guildmates know who to message on Discord. Never used as your name." },
    { key = "aliasFallback", name = "What to call me",
        desc = "Your alias, if your main's guild note doesn't set one with @Alias (the note wins)." },
    { key = "bio", name = "About me", desc = "A short bio guildmates see in tooltips and /gf who.", multiline = 3 },
}

-- The My Profile group. `guild` (see guildSettingsGroup) also provides:
--   MyProfile()          this character's person's profile ({} if none), or nil
--                        when the add-on doesn't know who this character is yet
--   SaveProfile(fields)  saves fields; returns true, or false and a reason
local function myProfileGroup(guild)
    local args = {
        status = {
            type = "description",
            order = 1,
            name = function()
                if guild.MyProfile() then
                    return "Shared with guildmates who use the add-on. You can edit it from any of your characters."
                end
                return "Your profile is available once you're in a guild and the roster has loaded."
            end,
        },
    }
    for index, field in ipairs(PROFILE_FIELDS) do
        local limit = addon.Profiles.LIMITS[field.key]
        args[field.key] = {
            type = "input",
            name = field.name,
            desc = ("%s Up to %d characters."):format(field.desc, limit),
            order = index + 1,
            width = "full",
            multiline = field.multiline,
            disabled = function()
                return guild.MyProfile() == nil
            end,
            get = function()
                local profile = guild.MyProfile()
                return profile and profile[field.key] or ""
            end,
            validate = function(_, value)
                local clean = addon.Profiles.Clean(value)
                if clean and #clean > limit then
                    return ("%s can be at most %d characters."):format(field.name, limit)
                end
                return true
            end,
            set = function(_, value)
                guild.SaveProfile({ [field.key] = value })
            end,
        }
    end
    return { type = "group", name = "My profile", inline = true, order = 2, args = args }
end

-- `profile` returns the current AceDB profile; `guild` is described above
-- guildSettingsGroup and myProfileGroup.
function Options.Build(profile, guild)
    return {
        type = "group",
        name = Options.TITLE,
        args = {
            features = {
                type = "group",
                name = "Feature toggles",
                inline = true,
                order = 1,
                args = {
                    chatTag = chatTagGroup(function()
                        return profile().chatTag
                    end),
                    greet = {
                        type = "toggle",
                        name = "Guild Greet",
                        desc = "When guildmates come online, show a prompt to greet them in guild chat. "
                            .. "Nothing is posted unless you click Greet.",
                        width = "full",
                        order = 3,
                        get = function()
                            return profile().greet.enabled
                        end,
                        set = function(_, value)
                            profile().greet.enabled = value
                            guild.GreetToggled()
                        end,
                    },
                    sync = {
                        type = "toggle",
                        name = "Sync with other add-on users",
                        desc = "Share identity links with guildmates who use the add-on, and receive theirs. "
                            .. "Turn off to stop sending and receiving.",
                        width = "full",
                        order = 2,
                        get = function()
                            return profile().sync.enabled
                        end,
                        set = function(_, value)
                            profile().sync.enabled = value
                        end,
                    },
                },
            },
            myProfile = myProfileGroup(guild),
            guildSettings = guildSettingsGroup(guild),
        },
    }
end

function Options.Register(profile, guild)
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, Options.Build(profile, guild))
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, Options.TITLE)
end
