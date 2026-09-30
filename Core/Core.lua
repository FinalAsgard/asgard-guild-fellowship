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
        chatTag = addon.ChatTag.DEFAULTS,
    },
}
local LAUNCHER_ICON = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"

function Core:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("AsgardsGuildFellowshipDB", DB_DEFAULTS, true)
    self.mainPanel = addon.UI.Window({ title = addon.Options.TITLE, width = 600, height = 450 })
    self.roster = addon.RosterAdapter.New(function(snapshot)
        if addon.identity then
            addon.identity:Update(snapshot)
        end
    end)
    addon.Options.Register(function()
        return self.db.profile
    end)
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
    addon.ChatTag.Register(function()
        return self.db.profile.chatTag
    end)
    addon.Tooltip.Register()
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
        who = function(query)
            self:Who(query)
        end,
        usage = function()
            self:Print("/fellowship opens the main panel. /fellowship version prints the version.")
            self:Print("/fellowship who <name> looks up a guildmate by character name, first name, or alias.")
        end,
    })
end

-- /gf who <query>
function Core:Who(query)
    if query == "" then
        self:Print("Usage: /fellowship who <character name, first name, or alias>")
        return
    end
    local store = addon.identity
    if not store then
        self:Print("You're not in a guild, or the roster hasn't loaded yet.")
        return
    end
    local lines = addon.WhoFormatter.Lines(query, store:FindByQuery(query), function(key)
        return store:GetCharacterInfo(key)
    end)
    for _, line in ipairs(lines) do
        self:Print(line)
    end
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

-- Points `addon.guildData` at the current guild's saved data and
-- `addon.identity` at its IdentityStore, or both at nil outside a guild. The
-- roster is only watched while in a guild. GetGuildInfo can be empty right
-- after login; PLAYER_GUILD_UPDATE follows once it is known.
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
    if guildKey then
        addon.identity = addon.IdentityStore.New(addon.guildData)
        self:RegisterEvent("GUILD_ROSTER_UPDATE", "OnGuildRosterUpdate")
        self.roster:Request()
    else
        addon.identity = nil
        self:UnregisterEvent("GUILD_ROSTER_UPDATE")
    end
end

function Core:OnGuildRosterUpdate(_, canRequestRosterUpdate)
    self.roster:OnRosterUpdate(canRequestRosterUpdate)
end
