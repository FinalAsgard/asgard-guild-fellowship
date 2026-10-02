local addonName, addon = ...

-- Wires the add-on into the game: saved variables, slash commands, the
-- launcher, the settings panel, and the current guild. Features start from here
-- only once the player is in a guild.
local Core = LibStub("AceAddon-3.0"):NewAddon(addonName, "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0")
addon.Core = Core

-- The one addon-message prefix every sync message uses (16 characters at most).
Core.COMM_PREFIX = "AGFellowship"

local DB_DEFAULTS = {
    profile = {
        -- LibDBIcon keeps the minimap button's position here.
        minimap = {},
        chatTag = addon.ChatTag.DEFAULTS,
        sync = { enabled = true },
        -- messages: the player's welcome-back lines (nil: built-in defaults);
        -- prompt: where the greet prompt was last dragged.
        -- newMessages: the player's new-member welcomes (nil: built-in defaults).
        greet = { enabled = false, welcomeNew = true, prompt = {} },
        -- share: whether guildmates see what this player is up for.
        availability = { share = true },
        -- Discovery's filters (status and role are nil for "any") and level range.
        discovery = { sameZone = false, showBusy = false, range = addon.Discovery.LEVEL_RANGE },
        -- The Guild Roster's "Show offline people" choice.
        roster = { showOffline = true },
    },
}
local LAUNCHER_ICON = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend"

function Core:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("AsgardsGuildFellowshipDB", DB_DEFAULTS, true)
    self.mainPanel = addon.UI.Window({
        title = addon.Options.TITLE,
        width = 600,
        height = 450,
        render = function(window)
            self:RenderMainPanel(window)
        end,
    })
    self.rosterWindow = addon.UI.Window({
        title = "Guild Roster",
        width = 560,
        height = 500,
        render = function(window)
            self:RenderRoster(window)
        end,
    })
    self.noteHelperState = { mode = "link" }
    self.noteHelper = addon.UI.Window({
        title = "Note Helper",
        width = 480,
        height = 420,
        render = function(window)
            self:RenderNoteHelper(window)
        end,
    })
    self.roster = addon.RosterAdapter.New(function(snapshot)
        if addon.identity then
            addon.identity:Update(snapshot)
            addon.availability:Prune()
            -- Logins, levels, and zones feed Discovery and the Guild Roster, and
            -- a rank change can turn officer tools on or off; none of them
            -- fires IdentityChanged.
            self.mainPanel:Refresh()
            self.rosterWindow:Refresh()
            self.greeter:OnSnapshot(snapshot)
            -- Sync starts once there is a roster to compare against.
            self.sync:Start()
        end
    end)
    addon.Options.Register(function()
        return self.db.profile
    end, {
        Settings = function()
            return addon.guildSettings
        end,
        Player = function()
            return self:PlayerKey()
        end,
        Publish = function(ranks)
            return self:PublishGuildSettings(ranks)
        end,
        MyProfile = function()
            local person = addon.identity and addon.identity:GetPerson(self:PlayerKey())
            if person then
                return addon.profiles:Get(person.id) or {}
            end
        end,
        SaveProfile = function(fields)
            return self:SaveProfile(fields)
        end,
        GreetToggled = function()
            self.greeter:Reset()
        end,
        DiscoveryChanged = function()
            self.mainPanel:Refresh()
        end,
    })
    self.greeter = addon.Greeter.New({
        identity = function()
            return addon.identity
        end,
        playerKey = function()
            return self:PlayerKey()
        end,
        settings = function()
            return self.db.profile.greet
        end,
        send = addon.Compat.SendGuildMessage,
        random = math.random,
        now = GetTime,
        after = C_Timer.After,
        inCombat = InCombatLockdown,
        playSound = addon.Compat.PlayAlertSound,
        announce = function(personIds)
            if self.sync then
                self.sync:Announce("greet", { persons = personIds })
            end
        end,
    })
    for _, command in ipairs(addon.Commands.ALWAYS) do
        self:RegisterChatCommand(command, "HandleCommand")
    end
    self:CreateLauncher()
    self:RegisterComm(Core.COMM_PREFIX, "OnCommReceived")
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
    self:RegisterEvent("CHAT_MSG_SYSTEM", "OnSystemMessage")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnded")
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
        clear = function(rest)
            self:ClearProfile(rest)
        end,
        notes = function()
            self:OpenNoteHelper()
        end,
        roster = function()
            self.rosterWindow:Show()
        end,
        status = function(rest)
            self:StatusCommand(rest)
        end,
        usage = function()
            self:Print("/fellowship opens the main panel. /fellowship version prints the version.")
            self:Print("/fellowship who <name> looks up a guildmate by character name, first name, or alias.")
            self:Print("/fellowship clear <bio|alias> <name> (addon officers) clears someone's bio or alias.")
            self:Print("/fellowship notes opens the Note Helper for linking alts and setting aliases.")
            self:Print("/fellowship roster opens the Guild Roster, grouped by person.")
            self:Print("/fellowship status <" .. table.concat(addon.Availability.STATUSES, "|")
                .. "|clear> sets what you're up for.")
        end,
    })
end

-- /gf status [status|clear]: prints, sets, or clears what this player is up for.
function Core:StatusCommand(input)
    local word = (input or ""):lower()
    if not addon.availability then
        self:Print("Availability works once you're in a guild.")
        return
    end
    if word == "" then
        local person = addon.identity:GetPerson(self:PlayerKey())
        local status = addon.availability:Get(person and person.id)
        self:Print(status == "none" and "You haven't set a status."
            or ("Your status: %s."):format(addon.Availability.LABELS[status]))
        return
    end
    local status = word == "clear" and "none" or word
    if status == "none" or addon.Availability.LABELS[status] then
        local ok = self:SetStatus(status)
        if not ok then
            self:Print("Your character isn't in the guild roster yet. Try again in a moment.")
        elseif status == "none" then
            self:Print("Status cleared.")
        else
            self:Print(("Status set: %s."):format(addon.Availability.LABELS[status]))
        end
        return
    end
    self:Print("Usage: /fellowship status <" .. table.concat(addon.Availability.STATUSES, "|") .. "|clear>")
end

-- Sets (or, with "none", clears) this player's status and sends it to the guild
-- right away when sync and sharing are on. Returns true, or false and a reason.
function Core:SetStatus(status)
    if not addon.availability then
        return false, "not in a guild"
    end
    local personId, reason = addon.availability:Set(self:PlayerKey(), status)
    if not personId then
        return false, reason
    end
    if self.sync and self.db.profile.sync.enabled and self.db.profile.availability.share then
        self.sync:SendRecords("availability", { personId })
    end
    return true
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
    end, function(personId)
        return addon.profiles and addon.profiles:Get(personId)
    end)
    for _, line in ipairs(lines) do
        self:Print(line)
    end
end

-- Note Helper state that fixes an issue: the first affected character is the
-- alt; for a chain, the terminal main (listed last) is the main.
function Core.NoteHelperPrefill(issueType, characters)
    local state = { mode = "link", alt = characters[1] }
    if issueType == "chain" then
        state.main = characters[#characters]
    end
    return state
end

-- Opens the Note Helper, optionally with `state` ({ mode, alt, main, alias }).
function Core:OpenNoteHelper(state)
    if state then
        self.noteHelperState = state
    end
    self.noteHelper:Show()
    self.noteHelper:Refresh()
end

-- Whose public note this player may edit: their own, or anyone's when their
-- rank can edit public notes.
function Core:CanEditNote(charKey)
    return charKey == self:PlayerKey() or addon.Compat.CanEditPublicNote()
end

function Core:NoteHelperPlan()
    return addon.NoteHelper.Plan(self.noteHelperState, addon.identity.snapshot, function(charKey)
        return self:CanEditNote(charKey)
    end)
end

function Core:RenderNoteHelper(window)
    local store = addon.identity
    if not store or not store.snapshot then
        window:AddText("The Note Helper works once you're in a guild and the roster has loaded.")
        return
    end
    local state = self.noteHelperState
    local function update(field)
        return function(value)
            state[field] = value
            window:Refresh()
        end
    end
    local choices = addon.NoteHelper.Choices(store.snapshot, function(charKey)
        return self:CanEditNote(charKey)
    end)
    local function options(list)
        local result = {}
        for _, choice in ipairs(list) do
            table.insert(result, { value = choice.key, text = choice.name })
        end
        return result
    end
    window:AddDropdown("What to do", {
        { value = "link", text = "Link an alt to its main" },
        { value = "alias", text = "Set a main's alias" },
    }, state.mode, update("mode"))
    if state.mode == "alias" then
        window:AddDropdown("Main", options(choices.editable), state.main, update("main"))
        window:AddInput("Alias (one word; leave empty to remove)", state.alias, update("alias"))
    else
        window:AddDropdown("Alt", options(choices.editable), state.alt, update("alt"))
        window:AddDropdown("Main", options(choices.all), state.main, update("main"))
    end
    local plan = self:NoteHelperPlan()
    local muted = { 0.7, 0.7, 0.7 }
    if plan.member then
        window:AddText(("Current note: %s"):format(plan.current ~= "" and plan.current or "(empty)"), muted)
    end
    if plan.text then
        window:AddText(("New note: %s"):format(plan.text ~= "" and plan.text or "(empty)"))
        if plan.fits then
            window:AddText(("Fits: %d of %d characters."):format(#plan.text, plan.limit), { 0.25, 1, 0.25 })
        else
            window:AddText(("Too long by %d characters."):format(plan.overflowBy), { 1, 0.3, 0.3 })
        end
    end
    if plan.reason then
        window:AddText(plan.reason, muted)
    end
    window:AddButton("Write note", function()
        self:WriteNote()
    end, not plan.canWrite)
end

-- Writes the planned note through the game, then asks for fresh roster data so
-- identity updates right away.
function Core:WriteNote()
    local plan = self:NoteHelperPlan()
    if not plan.canWrite then
        return
    end
    if not addon.Compat.SetPublicNote(plan.member, plan.text) then
        self:Print("This client didn't let the add-on write the note.")
        return
    end
    self:Print(("Updated %s's note: %s"):format(plan.member.name, plan.text ~= "" and plan.text or "(empty)"))
    self.roster:Request(true)
end

-- /gf clear words -> profile fields.
local CLEAR_FIELDS = { bio = "bio", alias = "aliasFallback" }

-- /gf clear <bio|alias> <name>: an addon officer clears an inappropriate bio or
-- profile alias. The name must pick out exactly one person.
function Core:ClearProfile(input)
    local word, query = input:match("^(%S+)%s+(.-)%s*$")
    local field = word and CLEAR_FIELDS[word:lower()]
    if not field or query == "" then
        self:Print("Usage: /fellowship clear <bio|alias> <character name, first name, or alias>")
        return
    end
    if not addon.profiles then
        self:Print("You're not in a guild, or the roster hasn't loaded yet.")
        return
    end
    local persons = addon.identity:FindByQuery(query)
    if #persons ~= 1 then
        self:Print(#persons == 0 and ('No guildmate matches "%s".'):format(query)
            or ('"%s" matches more than one person. Use a full character name.'):format(query))
        return
    end
    local person = persons[1]
    local ok, reason = addon.profiles:Clear(person.id, { field }, self:PlayerKey())
    if not ok then
        self:Print(reason == "not an officer" and "Only addon officers can clear profiles."
            or ("%s has no %s to clear."):format(person.shortName, word:lower()))
        return
    end
    if self.sync and self.db.profile.sync.enabled then
        self.sync:SendRecords("profile", { person.id })
    end
    self:Print(("Cleared %s's %s."):format(person.shortName, word:lower()))
end

function Core:CreateLauncher()
    local launcher = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
        type = "launcher",
        text = addon.Options.TITLE,
        icon = LAUNCHER_ICON,
        OnClick = function(frame, button)
            if button == "RightButton" then
                self:ShowStatusMenu(frame)
            else
                self.mainPanel:Toggle()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine(addon.Options.TITLE)
            tooltip:AddLine("Click to open or close.", 1, 1, 1)
            tooltip:AddLine("Right-click to set what you're up for.", 1, 1, 1)
        end,
    })
    LibStub("LibDBIcon-1.0"):Register(addonName, launcher, self.db.profile.minimap)
end

-- Points `addon.guildData` at the current guild's saved data and
-- `addon.identity` at its IdentityStore, or both at nil outside a guild. The
-- roster is only watched, and sync only runs, while in a guild. GetGuildInfo can be empty right
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
    if self.sync then
        self.sync:Stop()
        self.sync = nil
    end
    if guildKey then
        addon.identity = addon.IdentityStore.New(addon.guildData)
        addon.guildSettings = addon.GuildSettings.New(addon.guildData, addon.identity, addon.Compat.GuildRanks)
        self.sync = self:NewSync()
        self.sync:RegisterType("resolution", addon.identity:ResolutionSyncHandler())
        self.sync:RegisterType("guildSettings", addon.guildSettings:SyncHandler())
        addon.profiles = addon.Profiles.New(addon.guildData, addon.identity, GetServerTime, function(charKey)
            return addon.guildSettings:IsAddonOfficer(charKey)
        end)
        self.sync:RegisterType("profile", addon.profiles:SyncHandler())
        addon.availability = addon.Availability.New(addon.identity, GetServerTime, function(personId)
            local me = addon.identity:GetPerson(self:PlayerKey())
            return self.db.profile.availability.share or not me or me.id ~= personId
        end)
        self.sync:RegisterType("availability", addon.availability:SyncHandler())
        self.sync:Listen("greet", function(data, sender)
            self.greeter:OnClaim(type(data) == "table" and data.persons, sender)
        end)
        -- Keep the main panel current as identity and officer ranks change.
        addon.identity.RegisterCallback(self, "IdentityChanged", "RefreshMainPanel")
        addon.guildSettings.RegisterCallback(self, "GuildSettingsChanged", "RefreshMainPanel")
        addon.availability.RegisterCallback(self, "AvailabilityChanged", "OnAvailabilityChanged")
        -- What people help with is on their profile, and a profile change that
        -- doesn't touch names fires no IdentityChanged.
        addon.profiles.RegisterCallback(self, "ProfileChanged", "RefreshMainPanel")
        self:RegisterEvent("GUILD_ROSTER_UPDATE", "OnGuildRosterUpdate")
        self.roster:Request()
    else
        addon.identity = nil
        addon.guildSettings = nil
        addon.profiles = nil
        addon.availability = nil
        self:UnregisterEvent("GUILD_ROSTER_UPDATE")
    end
    self.greeter:Reset()
    self:RefreshMainPanel()
end

-- A "has come online" message means the roster has news; ask for it so Guild
-- Greet notices the arrival within seconds rather than at the next update.
-- A "has joined the guild" message offers Guild Greet's welcome.
function Core:OnSystemMessage(_, message)
    -- Retail can hand add-ons secret values (e.g. in instances); leave those alone.
    if not addon.identity or not self.db.profile.greet.enabled or type(message) ~= "string"
        or addon.Compat.IsSecret(message) then
        return
    end
    local joined = addon.Compat.JoinedGuildName(message)
    if joined then
        local key = addon.Compat.NormalizeName(joined)
        if key then
            self.greeter:OnMemberJoined(key, addon.Compat.NameFromKey(key))
        end
        self.roster:Request()
    elseif addon.Compat.OnlineMessageName(message) then
        self.roster:Request()
    end
end

function Core:OnCombatEnded()
    self.greeter:OnCombatEnded()
end

function Core:OnAvailabilityChanged()
    self:RefreshMainPanel()
    self:SchedulePrune()
end

-- A status that simply times out fires no event, so prune when the next one
-- lapses; pruning fires AvailabilityChanged, which redraws and reschedules.
function Core:SchedulePrune()
    local availability = addon.availability
    local expiry = availability and availability:NextExpiry()
    if not expiry or (self.pruneAt and self.pruneAt <= expiry) then
        return
    end
    self.pruneAt = expiry
    C_Timer.After(math.max(expiry - GetServerTime(), 0) + 1, function()
        if self.pruneAt ~= expiry then
            return
        end
        self.pruneAt = nil
        if addon.availability == availability then
            availability:Prune()
        end
        -- Also covers a guild change while waiting: schedule for the current one.
        self:SchedulePrune()
    end)
end

function Core:RefreshMainPanel()
    self.mainPanel:Refresh()
    self.noteHelper:Refresh()
    self.rosterWindow:Refresh()
end

-- The main panel: Discovery and the Note Helper for everyone, plus the
-- Identity Issues view for addon officers.
function Core:RenderMainPanel(window)
    local store = addon.identity
    self:RenderDiscovery(window)
    window:AddButton("Open Guild Roster", function()
        self.rosterWindow:Show()
    end, store == nil)
    window:AddButton("Open Note Helper", function()
        self:OpenNoteHelper()
    end, store == nil)
    if not store or not addon.guildSettings:IsAddonOfficer(self:PlayerKey()) then
        window:AddText("Officer tools appear here for your guild's addon officers.")
        return
    end
    local view = addon.IssuesView.Build(store:GetIssues(), function(charKey)
        local info = store:GetCharacterInfo(charKey)
        return info and info.name or charKey
    end)
    window:AddHeading(("Identity Issues (%d)"):format(view.count))
    if view.empty then
        window:AddText("No problems with your guild's notes. Every link resolves cleanly.")
        return
    end
    local muted = { 0.7, 0.7, 0.7 }
    for _, group in ipairs(view.groups) do
        window:AddHeading(("%s (%d)"):format(group.title, #group.items))
        window:AddText(group.explanation, muted)
        for _, item in ipairs(group.items) do
            window:AddText(item.ref and ("%s: %s"):format(item.names, item.ref) or item.names)
            window:AddText(item.fix, muted)
            window:AddButton("Fix in Note Helper", function()
                self:OpenNoteHelper(Core.NoteHelperPrefill(group.type, item.characters))
            end)
        end
    end
end

-- Discovery: online guildmates to play with, with their characters near this
-- character's level.
function Core:RenderDiscovery(window)
    local store = addon.identity
    local playerKey = self:PlayerKey()
    local person = store and store:GetPerson(playerKey)
    local info = store and store:GetCharacterInfo(playerKey)
    if not person or not info then
        window:AddHeading("Discovery")
        window:AddText("Discovery shows who you could play with once you're in a guild and the roster has loaded.")
        return
    end
    local filters = self.db.profile.discovery
    local people = addon.Discovery.Build(store, addon.availability, { personId = person.id, level = info.level }, {
        range = filters.range,
        maxLevel = addon.Compat.MaxLevel(),
        rolesOf = addon.Compat.ClassRoles,
        showBusy = filters.showBusy,
        status = filters.status,
        zone = filters.sameZone and (info.zone or "") or nil,
        role = filters.role,
        helps = filters.helps,
        profileOf = Core.ProfileOf,
    })
    window:AddHeading(("Discovery (%d)"):format(#people))
    window:AddDropdown("My status", self:StatusChoices(), addon.availability:Get(person.id), function(value)
        -- Redraw on the next frame, so the dropdown isn't released inside its own callback.
        C_Timer.After(0, function()
            self:SetStatus(value)
        end)
    end)
    self:RenderDiscoveryFilters(window, filters)
    if #people == 0 then
        local filtered = filters.status or filters.role or filters.sameZone or filters.helps
        window:AddText(filtered and "Nobody online matches these filters right now."
            or "Nobody else is online who's free to play right now.")
        return
    end
    for _, entry in ipairs(people) do
        for index, line in ipairs(addon.Discovery.Lines(entry)) do
            window:AddText(line, index > 1 and { 0.7, 0.7, 0.7 } or nil)
        end
        local target = entry.character.key
        window:AddButton("Whisper " .. entry.character.name, function()
            addon.Compat.OpenWhisper(target)
        end)
    end
end

-- The Guild Roster: everyone in the guild, grouped by person. The search lasts
-- for the session; "Show offline people" is saved.
function Core:RenderRoster(window)
    local store = addon.identity
    local settings = self.db.profile.roster
    local query = self.rosterQuery or ""
    local roster = store and addon.RosterView.Build(store, addon.availability,
        { query = query, showOffline = settings.showOffline, helps = self.rosterHelps, profileOf = Core.ProfileOf })
    if not roster or roster.totalPeople == 0 then
        window:AddText("The Guild Roster shows your guild once you're in a guild and the roster has loaded.")
        return
    end
    -- Changes redraw on the next frame, so the widget that fired isn't
    -- released inside its own callback.
    local function redraw()
        C_Timer.After(0, function()
            self.rosterWindow:Refresh()
        end)
    end
    window:AddHeading(addon.RosterView.Summary(roster))
    window:AddInput("Search (name or alias)", query, function(text)
        self.rosterQuery = text
        redraw()
    end)
    window:AddDropdown("Can help with", Core.HelpChoices(), self.rosterHelps or "any", function(value)
        self.rosterHelps = value ~= "any" and value or nil
        redraw()
    end)
    window:AddCheckBox("Show offline people", settings.showOffline, function(value)
        settings.showOffline = value
        redraw()
    end)
    if #roster.people == 0 then
        if query:match("%S") then
            window:AddText(("Nobody matches \"%s\"."):format(query))
            window:AddButton("Clear search", function()
                self.rosterQuery = nil
                redraw()
            end)
        elseif self.rosterHelps then
            window:AddText(("Nobody has said they can help with %s yet."):format(
                addon.Helping.LABELS[self.rosterHelps]))
        else
            window:AddText("Nobody is online right now.")
        end
        return
    end
    local me = store:GetPerson(self:PlayerKey())
    for _, entry in ipairs(roster.people) do
        local lines = addon.RosterView.Lines(entry)
        window:AddText(lines[1], not entry.online and { 0.6, 0.6, 0.6 } or nil)
        window:AddText(lines[2], { 0.7, 0.7, 0.7 })
        if entry.current and not (me and me.id == entry.personId) then
            local target = entry.current.key
            window:AddButton("Whisper " .. entry.current.name, function()
                addon.Compat.OpenWhisper(target)
            end)
        end
    end
end

-- A person's synced profile, or nil.
function Core.ProfileOf(personId)
    return addon.profiles and addon.profiles:Get(personId)
end

-- The helping topics as { value, text } choices, "any" (Anyone) first.
function Core.HelpChoices()
    local choices = { { value = "any", text = "Anyone" } }
    for _, topic in ipairs(addon.Helping.TOPICS) do
        table.insert(choices, { value = topic, text = addon.Helping.LABELS[topic] })
    end
    return choices
end

-- The statuses as { value, text } choices, "none" (Clear) last.
function Core.StatusChoices()
    local choices = {}
    for _, status in ipairs(addon.Availability.STATUSES) do
        table.insert(choices, { value = status, text = addon.Availability.LABELS[status] })
    end
    table.insert(choices, { value = "none", text = "Clear" })
    return choices
end

-- The status menu on the minimap button's right-click.
function Core:ShowStatusMenu(anchor)
    if not addon.availability then
        self:Print("Availability works once you're in a guild.")
        return
    end
    local person = addon.identity:GetPerson(self:PlayerKey())
    local current = addon.availability:Get(person and person.id)
    local items = {}
    for _, choice in ipairs(self:StatusChoices()) do
        table.insert(items, {
            text = choice.text,
            checked = choice.value == current,
            func = function()
                self:SetStatus(choice.value)
            end,
        })
    end
    if not addon.Compat.ShowMenu(anchor, "What are you up for?", items) then
        self:Print("Use /fellowship status to set what you're up for.")
    end
end

-- Discovery's filters, saved in the profile. A change redraws the panel on the
-- next frame, so the widget that fired isn't released inside its own callback.
function Core:RenderDiscoveryFilters(window, filters)
    local function changed(field, value)
        filters[field] = value
        C_Timer.After(0, function()
            self.mainPanel:Refresh()
        end)
    end
    local statuses = { { value = "any", text = "Any status" } }
    for _, status in ipairs(addon.Availability.STATUSES) do
        table.insert(statuses, { value = status, text = addon.Availability.LABELS[status] })
    end
    window:AddDropdown("Up for", statuses, filters.status or "any", function(value)
        changed("status", value ~= "any" and value or nil)
    end)
    window:AddDropdown("Can fill", {
        { value = "any", text = "Any role" },
        { value = "tank", text = "Tank" },
        { value = "heal", text = "Healer" },
    }, filters.role or "any", function(value)
        changed("role", value ~= "any" and value or nil)
    end)
    window:AddDropdown("Can help with", Core.HelpChoices(), filters.helps or "any", function(value)
        changed("helps", value ~= "any" and value or nil)
    end)
    window:AddCheckBox("Same zone as me", filters.sameZone, function(value)
        changed("sameZone", value)
    end)
    window:AddCheckBox("Show Busy", filters.showBusy, function(value)
        changed("showBusy", value)
    end)
end

function Core:OnGuildRosterUpdate(_, canRequestRosterUpdate)
    self.roster:OnRosterUpdate(canRequestRosterUpdate)
end

function Core.PlayerKey()
    local name, realm = UnitName("player")
    return addon.Compat.NormalizeName(name, realm)
end

-- Publishes new officer ranks as this character and sends them to the guild
-- right away (when sync is on). Returns false unless this character is an
-- addon officer.
function Core:PublishGuildSettings(officerRanks)
    if not addon.guildSettings or not addon.guildSettings:Publish(officerRanks, self:PlayerKey()) then
        return false
    end
    if self.sync and self.db.profile.sync.enabled then
        self.sync:SendRecords("guildSettings", { addon.GuildSettings.RECORD_ID })
    end
    return true
end

-- Saves this character's person's profile fields and sends the result to the
-- guild right away (when sync is on). Returns true, or false and a reason.
function Core:SaveProfile(fields)
    if not addon.profiles then
        return false, "not in a guild"
    end
    local key = self:PlayerKey()
    local ok, reason = addon.profiles:Save(key, fields)
    if ok and self.sync and self.db.profile.sync.enabled then
        self.sync:SendRecords("profile", { addon.identity:GetPerson(key).id })
    end
    return ok, reason
end

function Core:NewSync()
    return addon.Sync.New({
        send = function(message, priority)
            self:SendCommMessage(Core.COMM_PREFIX, message, "GUILD", nil, priority)
        end,
        after = C_Timer.After,
        random = math.random,
        now = GetTime,
        player = self:PlayerKey(),
        enabled = function()
            return self.db.profile.sync.enabled
        end,
    })
end

function Core:OnCommReceived(prefix, message, distribution, sender)
    if prefix ~= Core.COMM_PREFIX or distribution ~= "GUILD" or not self.sync or type(sender) ~= "string" then
        return
    end
    self.sync:OnMessage(message, addon.Compat.NormalizeName(sender))
end
