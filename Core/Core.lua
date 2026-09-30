local addonName, addon = ...

-- Wires the add-on into the game: saved variables, slash commands, the
-- launcher, the settings panel, and the current guild. Features start from here
-- only once the player is in a guild.
local Core = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0")
addon.Core = Core

local DB_DEFAULTS = {
    profile = {
        -- LibDBIcon keeps the minimap button's position here.
        minimap = {},
    },
}
local LAUNCHER_ICON = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"

function Core:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("AsgardsGuildFellowshipDB", DB_DEFAULTS, true)
    self.mainPanel = addon.UI.Window({ title = addon.Options.TITLE, width = 600, height = 450 })
    addon.Options.Register()
    for _, command in ipairs(addon.Commands.ALWAYS) do
        self:RegisterChatCommand(command, "HandleCommand")
    end
    self:CreateLauncher()
end

-- Runs at login, after every add-on has loaded, so any other owner of /gf is known.
function Core:OnEnable()
    if not addon.Commands.IsTaken(_G, addon.Commands.SHORT) then
        self:RegisterChatCommand(addon.Commands.SHORT, "HandleCommand")
    end
    self:RegisterEvent("PLAYER_GUILD_UPDATE", "UpdateGuild")
    self:UpdateGuild()
end

function Core:HandleCommand(input)
    addon.Commands.Dispatch(input, {
        [""] = function()
            self.mainPanel:Show()
        end,
        version = function()
            self:Print("version " .. tostring(addon.version))
        end,
        usage = function()
            self:Print("/fellowship opens the main panel. /fellowship version prints the version.")
        end,
    })
end

function Core:CreateLauncher()
    local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
        type = "launcher",
        text = addon.Options.TITLE,
        icon = LAUNCHER_ICON,
        OnClick = function()
            self.mainPanel:Toggle()
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(addon.Options.TITLE)
            tooltip:AddLine("Click to open or close.", 1, 1, 1)
        end,
    })
    LibStub("LibDBIcon-1.0"):Register(addonName, launcher, self.db.profile.minimap)
end

-- Points `addon.guildData` at the current guild's saved data, or nil outside a
-- guild. GetGuildInfo can be empty right after login; PLAYER_GUILD_UPDATE
-- follows once it is known.
function Core:UpdateGuild()
    local guildKey
    if IsInGuild() then
        local guildName, _, _, guildRealm = GetGuildInfo("player")
        if guildName then
            guildKey = addon.Compat.NormalizeName(guildName, guildRealm)
        end
    end
    if guildKey == self.guildKey then
        return
    end
    self.guildKey = guildKey
    addon.guildData = addon.GuildData.ForGuild(self.db.global, guildKey)
end
