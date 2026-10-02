std = "lua51"
max_line_length = 120
exclude_files = { ".release/", "Libs/", ".luarocks/", "lua_modules/" }

-- WoW API globals the add-on reads. Add names here as modules start using them.
read_globals = {
    "C_AddOns",
    "C_GuildInfo",
    "C_Timer",
    "CanEditPublicNote",
    "ChatFrame_AddMessageEventFilter",
    "ChatFrameUtil",
    "Enum",
    "ERR_FRIEND_ONLINE_SS",
    "ERR_GUILD_JOIN_S",
    "GameTooltip",
    "GetAddOnMetadata",
    "GetGuildInfo",
    "GetGuildRosterInfo",
    "GetNormalizedRealmName",
    "GetNumGuildMembers",
    "GetServerTime",
    "GetTime",
    "GuildControlGetNumRanks",
    "GuildControlGetRankName",
    "GuildRoster",
    "GuildRosterSetPublicNote",
    "hooksecurefunc",
    "InCombatLockdown",
    "IsInGuild",
    "issecretvalue",
    "LibStub",
    "PlaySound",
    "SendChatMessage",
    "SOUNDKIT",
    "GetMaxLevelForPlayerExpansion",
    "MAX_PLAYER_LEVEL",
    "ChatFrameUtil",
    "ChatFrame_SendTell",
    "MenuUtil",
    "EasyMenu",
    "CreateFrame",
    "UIParent",
    "TooltipDataProcessor",
    "UnitIsPlayer",
    "UnitName",
}

files["spec/"] = { std = "+busted" }
