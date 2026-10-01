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
        order = 2,
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

-- `profile` returns the current AceDB profile; `guild` is described above
-- guildSettingsGroup.
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
            guildSettings = guildSettingsGroup(guild),
        },
    }
end

function Options.Register(profile, guild)
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, Options.Build(profile, guild))
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, Options.TITLE)
end
