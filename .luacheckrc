std = "lua51"
max_line_length = 120
exclude_files = { ".release/", "Libs/", ".luarocks/", "lua_modules/" }

-- WoW API globals the add-on reads. Add names here as modules start using them.
read_globals = {
    "C_AddOns",
    "C_GuildInfo",
    "C_Timer",
    "ChatFrame_AddMessageEventFilter",
    "ChatFrameUtil",
    "Enum",
    "GameTooltip",
    "GetAddOnMetadata",
    "GetGuildInfo",
    "GetGuildRosterInfo",
    "GetNormalizedRealmName",
    "GetNumGuildMembers",
    "GetTime",
    "GuildRoster",
    "hooksecurefunc",
    "IsInGuild",
    "issecretvalue",
    "LibStub",
    "TooltipDataProcessor",
    "UnitIsPlayer",
    "UnitName",
}

files["spec/"] = { std = "+busted" }
