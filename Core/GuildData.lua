local _, addon = ...

-- Saved data is kept per guild. The add-on only ever hands out the current
-- guild's table, so a character in another guild never sees this one's data.
local GuildData = {}
addon.GuildData = GuildData

-- Returns the saved table for `guildKey` inside `store`, creating it on first
-- use. Returns nil when there is no guild.
function GuildData.ForGuild(store, guildKey)
    if not guildKey then
        return nil
    end
    store.guilds = store.guilds or {}
    local data = store.guilds[guildKey]
    if not data then
        data = {}
        store.guilds[guildKey] = data
    end
    return data
end
