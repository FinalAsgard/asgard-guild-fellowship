local Harness = require("support.wow")
local FakeLibs = require("support.fake_libs")
-- XML entries load the embedded libraries, which the harness replaces with fakes.
local manifestLuaFiles = require("support.manifest")

-- Loads the whole add-on as the client would and runs its login sequence.
local function boot(options)
    options = options or {}
    local LibStub, log = FakeLibs.new()
    options.globals = options.globals or {}
    options.globals.LibStub = LibStub
    local harness = Harness.new(options)
    local ns = harness:loadAll(manifestLuaFiles(options.manifest or "AsgardsGuildFellowship_Mainline.toc"))
    local core = ns.Core
    core:OnInitialize()
    if not options.skipEnable then
        core:OnEnable()
    end
    return ns, log, harness
end

describe("the add-on in the stub harness", function()
    for _, manifest in ipairs({ "AsgardsGuildFellowship_Camelot.toc", "AsgardsGuildFellowship_Mainline.toc" }) do
        it("loads every file " .. manifest .. " lists", function()
            local ns, log = boot({ manifest = manifest, client = manifest:match("Camelot") and "Forever" or "Retail" })
            assert.are.equal("AsgardsGuildFellowship", log.addon.name)
            assert.are.equal(ns.Core, log.addon)
            for _, module in ipairs({
                "Compat", "GuildData", "Commands", "NoteCodec", "IdentityResolver", "IdentityStore",
                "RosterAdapter", "ChatTag", "UI", "Options",
            }) do
                assert.is_table(ns[module], module .. " did not attach to the namespace")
            end
        end)
    end
end)

describe("Core", function()
    it("keeps saved variables in AsgardsGuildFellowshipDB", function()
        local _, log = boot()
        assert.are.equal("AsgardsGuildFellowshipDB", log.db.savedVariable)
    end)

    describe("slash commands", function()
        it("always registers /fellowship and /agf to one handler", function()
            local _, log = boot({ skipEnable = true })
            assert.are.equal("HandleCommand", log.addon.commands.fellowship)
            assert.are.equal("HandleCommand", log.addon.commands.agf)
            assert.is_nil(log.addon.commands.gf)
        end)

        it("registers /gf at login when nobody else owns it", function()
            local _, log = boot()
            assert.are.equal("HandleCommand", log.addon.commands.gf)
        end)

        it("leaves /gf alone when another add-on owns it", function()
            local _, log = boot({ globals = { SLASH_OTHERADDON1 = "/gf" } })
            assert.is_nil(log.addon.commands.gf)
            assert.are.equal("HandleCommand", log.addon.commands.fellowship)
        end)

        it("opens the main panel with no arguments", function()
            local ns, log = boot()
            ns.Core:HandleCommand("")
            assert.is_true(ns.Core.mainPanel:IsShown())
            assert.are.equal("Frame", log.AceGUI.created[1].kind)
        end)

        it("prints the version", function()
            local ns, log = boot({ version = "0.4.2" })
            ns.Core:HandleCommand("version")
            assert.are.same({ "version 0.4.2" }, log.addon.printed)
        end)

        it("prints usage for an unknown command", function()
            local ns, log = boot()
            ns.Core:HandleCommand("dance")
            assert.are.equal(6, #log.addon.printed)
            assert.are.equal("/fellowship status <questing|dungeons|pvp|helping|anything|busy|clear> sets what "
                .. "you're up for.", log.addon.printed[6])
            assert.is_false(ns.Core.mainPanel:IsShown())
        end)
    end)

    describe("launcher", function()
        it("registers an LDB launcher with a minimap icon", function()
            local _, log = boot()
            local launcher = log.launchers.AsgardsGuildFellowship
            assert.are.equal("launcher", launcher.type)
            assert.are.equal(launcher, log.icons.AsgardsGuildFellowship.object)
            assert.are.equal(log.db.profile.minimap, log.icons.AsgardsGuildFellowship.settings)
        end)

        it("opens the status menu on right-click, marking the current status", function()
            local shown
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" },
                roster = { { name = "Kira", guid = "G-K", note = "", online = true, level = 30 } },
                units = { player = { name = "Kira", player = true } },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            ns.Compat.ShowMenu = function(anchor, title, items)
                shown = { anchor = anchor, title = title, items = items }
                return true
            end
            ns.Core:SetStatus("pvp")
            local launcher = log.launchers.AsgardsGuildFellowship
            launcher.OnClick("button", "RightButton")
            assert.is_false(ns.Core.mainPanel:IsShown())
            assert.are.equal("button", shown.anchor)
            assert.are.equal("What are you up for?", shown.title)
            assert.are.equal(7, #shown.items)
            assert.are.equal("PvP", shown.items[3].text)
            assert.is_true(shown.items[3].checked)
            assert.is_false(shown.items[1].checked)
            assert.are.equal("Clear", shown.items[7].text)
            shown.items[2].func()
            assert.are.equal("dungeons", ns.availability:Get("G-K"))
        end)

        it("points to the slash command when the client has no menu, and needs a guild", function()
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" },
                roster = { { name = "Kira", guid = "G-K", note = "", online = true, level = 30 } },
                units = { player = { name = "Kira", player = true } },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            log.launchers.AsgardsGuildFellowship.OnClick("button", "RightButton")
            assert.are.same({ "Use /fellowship status to set what you're up for." }, log.addon.printed)
            local outside, outsideLog = boot()
            outside.Core:ShowStatusMenu("button")
            assert.are.same({ "Availability works once you're in a guild." }, outsideLog.addon.printed)
        end)

        it("toggles the main panel on click", function()
            local ns, log = boot()
            local launcher = log.launchers.AsgardsGuildFellowship
            launcher.OnClick()
            assert.is_true(ns.Core.mainPanel:IsShown())
            launcher.OnClick()
            assert.is_false(ns.Core.mainPanel:IsShown())
        end)
    end)

    it("registers the settings panel with the standard options panel", function()
        local _, log = boot()
        assert.are.equal("AsgardsGuildFellowship", log.options.registered.name)
        assert.is_table(log.options.registered.table.args.features)
        assert.are.equal("AsgardsGuildFellowship", log.options.blizzard.name)
    end)

    describe("guild data", function()
        it("has no guild data outside a guild", function()
            local ns = boot()
            assert.is_nil(ns.guildData)
            assert.is_nil(ns.Core.guildKey)
        end)

        it("selects the current guild's data at login", function()
            local ns, log = boot({ client = "Forever", guild = { name = "Asgard" } })
            assert.are.equal("Asgard-Forever", ns.Core.guildKey)
            assert.are.equal(log.db.global.guilds["Asgard-Forever"], ns.guildData)
        end)

        it("keys Retail guilds by realm", function()
            local ns = boot({ client = "Retail", realm = "Stormrage", guild = { name = "Asgard", realm = "Area 52" } })
            assert.are.equal("Asgard-Area52", ns.Core.guildKey)
        end)

        it("switches to the new guild's data when the guild changes", function()
            local ns, log, harness = boot({ client = "Forever", guild = { name = "Asgard" } })
            assert.are.equal("UpdateGuild", log.addon.events.PLAYER_GUILD_UPDATE)
            ns.guildData.marker = "asgard"

            harness.options.guild = { name = "Midgard" }
            ns.Core:UpdateGuild()
            assert.are.equal("Midgard-Forever", ns.Core.guildKey)
            assert.is_nil(ns.guildData.marker)

            harness.options.guild = nil
            ns.Core:UpdateGuild()
            assert.is_nil(ns.guildData)
        end)

        it("waits when the guild name isn't known yet", function()
            local ns, _, harness = boot({ client = "Forever", guild = { name = nil } })
            assert.is_nil(ns.guildData)
            harness.options.guild = { name = "Asgard" }
            ns.Core:UpdateGuild()
            assert.are.equal("Asgard-Forever", ns.Core.guildKey)
        end)
    end)

    describe("identity in guild chat", function()
        local ROSTER = {
            { name = "Dresden Zelwindran", guid = "G-D", note = "@Zel", online = true },
            { name = "Malgen Zelwindran", guid = "G-M", note = ">Dresden", online = true },
            { name = "Plain Main", guid = "G-P", note = "", online = true },
        }

        -- Boots into a Forever guild, then delivers the roster the way the
        -- client does: an event, then the debounce.
        local function bootWithRoster()
            local ns, log, harness = boot({ client = "Forever", guild = { name = "Asgard" }, roster = ROSTER })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            return ns, log, harness
        end

        it("requests the roster when the guild is known", function()
            local _, _, harness = boot({ client = "Forever", guild = { name = "Asgard" }, roster = ROSTER })
            assert.are.equal(1, harness.rosterRequests)
        end)

        it("does not watch the roster outside a guild", function()
            local ns, log, harness = boot({ roster = ROSTER })
            assert.is_nil(log.addon.events.GUILD_ROSTER_UPDATE)
            assert.is_nil(ns.identity)
            assert.are.equal(0, harness.rosterRequests)
        end)

        it("resolves people from the roster", function()
            local ns = bootWithRoster()
            assert.are.equal("Zel", ns.identity:GetDisplayName("G-D"))
            assert.are.equal("G-D", ns.identity:GetPerson("Malgen Zelwindran-Forever").id)
        end)

        it("tags an alt's guild chat line after the player name", function()
            local _, _, harness = bootWithRoster()
            local message, author = harness:chat("CHAT_MSG_GUILD", "Anyone want to run a dungeon?",
                "Malgen Zelwindran", "", "", "Malgen Zelwindran")
            assert.are.equal("[Zel] Anyone want to run a dungeon?", message)
            assert.are.equal("Malgen Zelwindran", author)
        end)

        it("tags a main with an alias", function()
            local _, _, harness = bootWithRoster()
            assert.are.equal("[Zel] hi", harness:chat("CHAT_MSG_GUILD", "hi", "Dresden Zelwindran"))
        end)

        it("leaves a main without alias and unknown speakers untagged", function()
            local _, _, harness = bootWithRoster()
            assert.are.equal("hi", harness:chat("CHAT_MSG_GUILD", "hi", "Plain Main"))
            assert.are.equal("hi", harness:chat("CHAT_MSG_GUILD", "hi", "Stranger"))
        end)

        it("passes the remaining chat arguments through unchanged", function()
            local _, _, harness = bootWithRoster()
            local seen
            harness.env.ChatFrame_AddMessageEventFilter("CHAT_MSG_GUILD", function(_, _, ...)
                seen = { ... }
                return false
            end)
            harness:chat("CHAT_MSG_GUILD", "hi", "Malgen Zelwindran", "Common", "", "", "", 0, 0, "", 0, 42, "GUID-M")
            assert.are.same({ "[Zel] hi", "Malgen Zelwindran", "Common", "", "", "", 0, 0, "", 0, 42, "GUID-M" }, seen)
        end)

        it("leaves secret chat values alone", function()
            local _, _, harness = bootWithRoster()
            harness.env.issecretvalue = function(value)
                return value == "secret"
            end
            assert.are.equal("secret", harness:chat("CHAT_MSG_GUILD", "secret", "Malgen Zelwindran"))
        end)

        it("tags guildmates in every supported channel", function()
            local _, _, harness = bootWithRoster()
            for _, event in ipairs({
                "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
                "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
                "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
            }) do
                local message, author = harness:chat(event, "hi", "Malgen Zelwindran")
                assert.are.equal("[Zel] hi", message, event)
                assert.are.equal("Malgen Zelwindran", author, event)
            end
        end)

        it("leaves non-guildmates untagged in group channels and whispers", function()
            local _, _, harness = bootWithRoster()
            local events = { "CHAT_MSG_PARTY", "CHAT_MSG_RAID", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_WHISPER" }
            for _, event in ipairs(events) do
                assert.are.equal("hi", harness:chat(event, "hi", "Random Stranger"), event)
            end
        end)

        it("leaves other channels alone", function()
            local _, _, harness = bootWithRoster()
            assert.are.equal("hi", harness:chat("CHAT_MSG_SAY", "hi", "Malgen Zelwindran"))
            assert.are.equal("hi", harness:chat("CHAT_MSG_CHANNEL", "hi", "Malgen Zelwindran"))
        end)

        it("applies channel toggles immediately", function()
            local _, log, harness = bootWithRoster()
            local channels = log.options.registered.table.args.features.args.chatTag.args.channels.args
            channels.officer.set(nil, false)
            assert.is_false(channels.officer.get())
            assert.are.equal("hi", harness:chat("CHAT_MSG_OFFICER", "hi", "Malgen Zelwindran"))
            assert.are.equal("[Zel] hi", harness:chat("CHAT_MSG_GUILD", "hi", "Malgen Zelwindran"))
            channels.whisper.set(nil, false)
            assert.are.equal("hi", harness:chat("CHAT_MSG_WHISPER", "hi", "Malgen Zelwindran"))
            assert.are.equal("hi", harness:chat("CHAT_MSG_WHISPER_INFORM", "hi", "Malgen Zelwindran"))
            channels.officer.set(nil, true)
            assert.are.equal("[Zel] hi", harness:chat("CHAT_MSG_OFFICER", "hi", "Malgen Zelwindran"))
        end)

        it("applies appearance changes immediately", function()
            local _, log, harness = bootWithRoster()
            local options = log.options.registered.table.args.features.args.chatTag.args
            options.brackets.set(nil, "angle")
            assert.are.equal("<Zel> hi", harness:chat("CHAT_MSG_GUILD", "hi", "Malgen Zelwindran"))
            assert.is_true(options.color.disabled())
            options.colored.set(nil, true)
            options.color.set(nil, 1, 0, 0)
            assert.are.same({ 1, 0, 0 }, { options.color.get() })
            assert.are.equal("|cffff0000<Zel>|r hi", harness:chat("CHAT_MSG_GUILD", "hi", "Malgen Zelwindran"))
        end)

        it("skips messages that aren't plain text", function()
            local _, _, harness = bootWithRoster()
            assert.is_nil(harness:chat("CHAT_MSG_GUILD", nil, "Malgen Zelwindran"))
            assert.are.equal("hi", harness:chat("CHAT_MSG_GUILD", "hi", nil))
        end)

        it("stops tagging after leaving the guild", function()
            local ns, _, harness = bootWithRoster()
            harness.options.guild = nil
            ns.Core:UpdateGuild()
            assert.are.equal("hi", harness:chat("CHAT_MSG_GUILD", "hi", "Malgen Zelwindran"))
        end)
    end)

    describe("tooltips", function()
        local ROSTER = {
            { name = "Dresden Zelwindran", guid = "G-D", note = "@Zel", online = true, level = 60,
                className = "Warrior" },
            { name = "Malgen Zelwindran", guid = "G-M", note = ">Dresden", online = false, level = 34,
                className = "Mage" },
            { name = "Plain Main", guid = "G-P", note = "", online = true, level = 10, className = "Rogue" },
        }
        local UNITS = {
            mouseover = { name = "Malgen Zelwindran", player = true },
            target = { name = "Plain Main", player = true },
            focus = { name = "Random Stranger", player = true },
            npc = { name = "Malgen Zelwindran", player = false },
        }

        local function bootWithRoster()
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = ROSTER, units = UNITS,
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            return harness
        end

        local function lefts(lines)
            local result = {}
            for _, line in ipairs(lines) do
                table.insert(result, line.left)
            end
            return result
        end

        it("adds the identity section to a guildmate's unit tooltip", function()
            local harness = bootWithRoster()
            assert.are.same({ "Zel", "Playing Malgen Zelwindran", "Main: Dresden Zelwindran" },
                lefts(harness:hoverUnit("mouseover")))
            assert.are.equal("60 Warrior", harness.tooltip.lines[3].right)
        end)

        it("adds nothing for non-guildmates, NPCs, or guildmates with nothing to add", function()
            local harness = bootWithRoster()
            assert.are.same({}, harness:hoverUnit("focus"))
            assert.are.same({}, harness:hoverUnit("npc"))
            assert.are.same({}, harness:hoverUnit("target"))
        end)

        it("skips units the client hides from add-ons", function()
            local harness = bootWithRoster()
            harness.env.issecretvalue = function(value)
                return value == "mouseover"
            end
            assert.are.same({}, harness:hoverUnit("mouseover"))
        end)

        it("adds the identity section to a guild roster row tooltip once", function()
            local harness = bootWithRoster()
            local lines = harness:hoverRosterRow({ name = "Malgen Zelwindran", guid = "G-M" })
            assert.are.same({ "Malgen Zelwindran", "Zel", "Playing Malgen Zelwindran", "Main: Dresden Zelwindran" },
                lefts(lines))
            assert.are.equal(2, harness.tooltip.shows)
            harness.tooltip:Show()
            assert.are.equal(4, #harness.tooltip.lines)
        end)

        it("adds the section again for the next roster row", function()
            local harness = bootWithRoster()
            harness:hoverRosterRow({ name = "Malgen Zelwindran" })
            assert.are.same({ "Dresden Zelwindran", "Zel", "Playing Dresden Zelwindran (main)", "  Malgen Zelwindran" },
                lefts(harness:hoverRosterRow({ name = "Dresden Zelwindran" })))
        end)

        it("adds the section once when a unit tooltip is also a roster row", function()
            local harness = bootWithRoster()
            local tooltip = harness.tooltip
            tooltip:SetOwner({
                GetMemberInfo = function()
                    return { name = "Malgen Zelwindran" }
                end,
            })
            tooltip.unit = "mouseover"
            for _, callback in ipairs(harness.unitTooltipPostCalls) do
                callback(tooltip, {})
            end
            tooltip:Show()
            assert.are.same({ "Zel", "Playing Malgen Zelwindran", "Main: Dresden Zelwindran" }, lefts(tooltip.lines))
        end)

        it("leaves other tooltips alone", function()
            local harness = bootWithRoster()
            harness.tooltip:SetOwner({})
            harness.tooltip:AddLine("Some item")
            harness.tooltip:Show()
            assert.are.same({ "Some item" }, lefts(harness.tooltip.lines))
        end)
    end)

    describe("/fellowship who", function()
        it("prints the matching person", function()
            local ns, log, harness = boot({
                client = "Forever",
                guild = { name = "Asgard" },
                roster = {
                    { name = "Dresden Zelwindran", guid = "G-D", note = "@Zel", online = false, level = 60,
                        className = "Warrior" },
                    { name = "Malgen Zelwindran", guid = "G-M", note = ">Dresden", online = false },
                },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            ns.Core:HandleCommand("who Malgen Zelwindran")
            assert.are.same({
                "Zel (main: Dresden Zelwindran)",
                "  Dresden Zelwindran (main) - 60 Warrior - offline",
                "  Malgen Zelwindran - offline",
            }, log.addon.printed)
        end)

        it("explains when not in a guild", function()
            local ns, log = boot()
            ns.Core:HandleCommand("who Zel")
            assert.are.same({ "You're not in a guild, or the roster hasn't loaded yet." }, log.addon.printed)
        end)

        it("prints usage without a query", function()
            local ns, log = boot()
            ns.Core:HandleCommand("who")
            assert.are.equal(1, #log.addon.printed)
            assert.truthy(log.addon.printed[1]:find("Usage", 1, true))
        end)
    end)

    describe("sync", function()
        local EARLY = {
            { name = "Dresden Zelwindran", guid = "G-D", note = "@Zel" },
            { name = "Malgen", guid = "G-M", note = ">Dresden" },
        }
        local FULL = { EARLY[1], EARLY[2], { name = "Dresden Other", guid = "G-O", note = "" } }

        local function client(name, rosters)
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = rosters[1],
                units = { player = { name = name, player = true } },
            })
            for index, roster in ipairs(rosters) do
                harness.options.roster = roster
                ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", index > 1)
                harness:advance(1)
            end
            return { name = name, ns = ns, log = log, harness = harness }
        end

        -- Delivers everything each client sent over AceComm to the other one.
        local function run(a, b, seconds)
            for _ = 1, seconds do
                for _, pair in ipairs({ { a, b }, { b, a } }) do
                    local from, to = pair[1], pair[2]
                    local sent = from.log.addon.sent
                    from.log.addon.sent = {}
                    for _, message in ipairs(sent) do
                        to.ns.Core:OnCommReceived(message.prefix, message.message, message.distribution, from.name)
                    end
                end
                a.harness:advance(1)
                b.harness:advance(1)
            end
        end

        it("registers one prefix and sends on the guild channel", function()
            local c = client("Veteran", { FULL })
            assert.are.equal("OnCommReceived", c.log.addon.comms.AGFellowship)
            c.harness:advance(20)
            local sent = c.log.addon.sent[1]
            assert.are.equal("AGFellowship", sent.prefix)
            assert.are.equal("GUILD", sent.distribution)
        end)

        it("fills a newcomer's ambiguous link from a veteran through the add-on channel", function()
            local veteran = client("Veteran", { EARLY, FULL })
            local newcomer = client("Newcomer", { FULL })
            assert.are.equal("G-M", newcomer.ns.identity:GetPerson("Malgen-Forever").id)
            run(veteran, newcomer, 40)
            assert.are.equal("G-D", newcomer.ns.identity:GetPerson("Malgen-Forever").id)
            assert.are.equal("G-D", veteran.ns.identity:GetPerson("Malgen-Forever").id)
        end)

        it("sends and accepts nothing when sync is turned off in settings", function()
            local veteran = client("Veteran", { EARLY, FULL })
            local newcomer = client("Newcomer", { FULL })
            local toggle = newcomer.log.options.registered.table.args.features.args.sync
            toggle.set(nil, false)
            assert.is_false(toggle.get())
            run(veteran, newcomer, 40)
            assert.are.equal("G-M", newcomer.ns.identity:GetPerson("Malgen-Forever").id)
            assert.are.same({}, newcomer.log.addon.sent)
        end)

        it("ignores other prefixes and non-guild distribution", function()
            local c = client("Newcomer", { FULL })
            c.ns.Core:OnCommReceived("OtherAddon", "x", "GUILD", "Someone")
            c.ns.Core:OnCommReceived("AGFellowship", "x", "WHISPER", "Someone")
            c.ns.Core:OnCommReceived("AGFellowship", "garbage", "GUILD", "Someone")
            assert.are.equal("G-M", c.ns.identity:GetPerson("Malgen-Forever").id)
        end)
    end)

    describe("guild settings", function()
        local RANKS = {
            { name = "Guild Master", canEditOfficerNote = true },
            { name = "Officer", canEditOfficerNote = true },
            { name = "Member", canEditOfficerNote = false },
        }
        local ROSTER = {
            { name = "Leader", guid = "G-L", note = "", rankIndex = 0 },
            { name = "Officer", guid = "G-O", note = "", rankIndex = 1 },
            { name = "Member", guid = "G-M", note = "", rankIndex = 2 },
        }

        local function client(name)
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = ROSTER, ranks = RANKS,
                units = { player = { name = name, player = true } },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            local group = log.options.registered.table.args.guildSettings.args
            return { name = name, ns = ns, log = log, harness = harness, options = group }
        end

        local function deliver(from, to)
            local sent = from.log.addon.sent
            from.log.addon.sent = {}
            for _, message in ipairs(sent) do
                to.ns.Core:OnCommReceived(message.prefix, message.message, message.distribution, from.name)
            end
        end

        it("reads the guild's ranks and officer-note permission through Compat", function()
            local c = client("Member")
            assert.are.same({
                { index = 0, name = "Guild Master", canEditOfficerNote = true },
                { index = 1, name = "Officer", canEditOfficerNote = true },
                { index = 2, name = "Member", canEditOfficerNote = false },
            }, c.ns.Compat.GuildRanks())
            assert.are.same({ [0] = "Guild Master", [1] = "Officer", [2] = "Member" }, c.options.officerRanks.values())
        end)

        it("lets officers edit and publish, and shows members the settings read-only", function()
            local officer = client("Officer")
            assert.is_false(officer.options.officerRanks.disabled())
            assert.is_false(officer.options.publish.hidden())
            local member = client("Member")
            assert.is_true(member.options.officerRanks.disabled())
            assert.is_true(member.options.publish.hidden())
            assert.is_false(member.options.officerRanks.hidden())
            assert.is_true(member.options.officerRanks.get(nil, 1))
            assert.truthy(member.options.status.name():find("read-only", 1, true))
        end)

        it("publishes an officer's choice to other members, who accept it and fire GuildSettingsChanged", function()
            local officer = client("Officer")
            local member = client("Member")
            local changed = 0
            member.ns.guildSettings.RegisterCallback({}, "GuildSettingsChanged", function()
                changed = changed + 1
            end)
            officer.options.officerRanks.set(nil, 2, true)
            officer.options.officerRanks.set(nil, 1, false)
            officer.options.publish.func()
            assert.are.same({ [0] = true, [2] = true }, officer.ns.guildSettings:Record().officerRanks)
            deliver(officer, member)
            assert.are.equal(1, changed)
            assert.is_true(member.ns.guildSettings:IsAddonOfficer("Member-Forever"))
            assert.is_false(member.ns.guildSettings:IsAddonOfficer("Officer-Forever"))
            assert.truthy(member.options.status.name():find("Published by Officer-Forever (version 1)", 1, true))
        end)

        it("ignores settings a non-officer tries to publish", function()
            local member = client("Member")
            local other = client("Officer")
            assert.is_false(member.ns.Core:PublishGuildSettings({ [2] = true }))
            member.ns.guildSettings.data.guildSettings = { version = 9, officerRanks = { [2] = true },
                publisher = "Member-Forever" }
            member.ns.Core.sync:SendRecords("guildSettings", { "guild" })
            deliver(member, other)
            assert.is_nil(other.ns.guildSettings:Record())
            assert.is_false(other.ns.guildSettings:IsAddonOfficer("Member-Forever"))
        end)
    end)

    describe("profiles", function()
        local ROSTER = {
            { name = "Dresden Zelwindran", guid = "G-D", note = "", rankIndex = 3 },
            { name = "Malgen Zelwindran", guid = "G-M", note = ">Dresden", rankIndex = 3 },
            { name = "Kira", guid = "G-K", note = "", rankIndex = 3 },
        }

        local function client(name)
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = ROSTER,
                units = { player = { name = name, player = true } },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            return { name = name, ns = ns, log = log, harness = harness,
                options = log.options.registered.table.args.myProfile.args }
        end

        local function deliver(from, to)
            local sent = from.log.addon.sent
            from.log.addon.sent = {}
            for _, message in ipairs(sent) do
                to.ns.Core:OnCommReceived(message.prefix, message.message, message.distribution, from.name)
            end
        end

        it("edits the person's profile from an alt through the My Profile panel", function()
            local alt = client("Malgen Zelwindran")
            assert.is_false(alt.options.discord.disabled())
            alt.options.discord.set(nil, "zelly")
            alt.options.aliasFallback.set(nil, "Zel")
            alt.options.bio.set(nil, "Tank and healer")
            assert.are.equal("zelly", alt.options.discord.get())
            assert.are.same({ version = 3, author = "Malgen Zelwindran-Forever", discord = "zelly",
                aliasFallback = "Zel", bio = "Tank and healer" }, alt.ns.profiles:Get("G-D"))
            assert.are.equal("Zel", alt.ns.identity:GetDisplayName("G-D"))
        end)

        it("rejects over-long values in the panel", function()
            local alt = client("Malgen Zelwindran")
            assert.is_true(alt.options.discord.validate(nil, "zelly"))
            assert.is_string(alt.options.discord.validate(nil, string.rep("x", 40)))
        end)

        it("disables the panel outside a guild", function()
            local _, log = boot({ units = { player = { name = "Nobody", player = true } } })
            local options = log.options.registered.table.args.myProfile.args
            assert.is_true(options.discord.disabled())
            assert.are.equal("", options.discord.get())
        end)

        it("reaches guildmates, who show the alias, Discord name, and bio", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            alt.options.aliasFallback.set(nil, "Zel")
            alt.options.discord.set(nil, "zelly")
            deliver(alt, friend)
            assert.are.equal("Zel", friend.ns.identity:GetDisplayName("G-D"))
            assert.are.equal("[Zel] hi", friend.harness:chat("CHAT_MSG_GUILD", "hi", "Malgen Zelwindran"))
            friend.ns.Core:HandleCommand("who Zel")
            assert.are.same({
                "Zel (main: Dresden Zelwindran)",
                "  Dresden Zelwindran (main) - offline",
                "  Malgen Zelwindran - offline",
                "  Discord: zelly",
            }, friend.log.addon.printed)
        end)

        it("ignores a profile someone sends for another person", function()
            local impostor = client("Kira")
            local victim = client("Malgen Zelwindran")
            impostor.ns.profiles.data.profiles["G-D"] = { version = 5, author = "Kira-Forever", bio = "fake" }
            impostor.ns.Core.sync:SendRecords("profile", { "G-D" })
            deliver(impostor, victim)
            assert.is_nil(victim.ns.profiles:Get("G-D"))
        end)
    end)

    describe("availability", function()
        local ROSTER = {
            { name = "Dresden Zelwindran", guid = "G-D", note = "", online = false, level = 60, className = "Mage" },
            { name = "Malgen Zelwindran", guid = "G-M", note = ">Dresden", online = true, level = 30,
                className = "Warrior", zone = "Duskwood" },
            { name = "Kira", guid = "G-K", note = "", online = true, level = 33, className = "Priest" },
        }

        local function client(name)
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = ROSTER,
                units = { player = { name = name, player = true } },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            log.addon.printed = {}
            return { name = name, ns = ns, log = log, harness = harness,
                share = log.options.registered.table.args.features.args.shareAvailability }
        end

        local function deliver(from, to)
            local sent = from.log.addon.sent
            from.log.addon.sent = {}
            for _, message in ipairs(sent) do
                to.ns.Core:OnCommReceived(message.prefix, message.message, message.distribution, from.name)
            end
        end

        it("sets a status for the person from /fellowship status and shares it with guildmates", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            alt.ns.Core:HandleCommand("status Dungeons")
            assert.are.same({ "Status set: Dungeons." }, alt.log.addon.printed)
            deliver(alt, friend)
            assert.are.equal("dungeons", friend.ns.availability:Get("G-D"))
            alt.ns.Core:HandleCommand("status")
            assert.are.equal("Your status: Dungeons.", alt.log.addon.printed[2])
        end)

        it("clears a status everywhere", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            alt.ns.Core:HandleCommand("status pvp")
            deliver(alt, friend)
            alt.harness:advance(1)
            alt.ns.Core:HandleCommand("status clear")
            deliver(alt, friend)
            assert.are.equal("none", friend.ns.availability:Get("G-D"))
            assert.are.same({ "Status set: PvP.", "Status cleared." }, alt.log.addon.printed)
            alt.ns.Core:HandleCommand("status")
            assert.are.equal("You haven't set a status.", alt.log.addon.printed[3])
        end)

        it("prints usage for an unknown status", function()
            local alt = client("Malgen Zelwindran")
            alt.ns.Core:HandleCommand("status raiding")
            assert.are.same({ "Usage: /fellowship status <questing|dungeons|pvp|helping|anything|busy|clear>" },
                alt.log.addon.printed)
            assert.are.equal("none", alt.ns.availability:Get("G-D"))
        end)

        it("explains that availability needs a guild", function()
            local ns, log = boot({ units = { player = { name = "Nobody", player = true } } })
            ns.Core:HandleCommand("status pvp")
            assert.are.same({ "Availability works once you're in a guild." }, log.addon.printed)
        end)

        it("keeps a status local when sharing is off", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            assert.is_true(alt.share.get())
            alt.share.set(nil, false)
            alt.ns.Core:HandleCommand("status helping")
            assert.are.same({}, alt.log.addon.sent)
            assert.are.equal("helping", alt.ns.availability:Get("G-D"))
            assert.is_nil(alt.ns.Core.sync.types.availability.Get("G-D"))
            deliver(alt, friend)
            assert.are.equal("none", friend.ns.availability:Get("G-D"))
        end)

        it("reaches a guildmate who logs in later, through the digest exchange", function()
            local alt = client("Malgen Zelwindran")
            alt.ns.Core:HandleCommand("status anything")
            alt.log.addon.sent = {}
            local friend = client("Kira")
            for _ = 1, 40 do
                deliver(alt, friend)
                deliver(friend, alt)
                alt.harness:advance(1)
                friend.harness:advance(1)
            end
            assert.are.equal("anything", friend.ns.availability:Get("G-D"))
        end)

        local function panel(c)
            local scroll
            for _, widget in ipairs(c.log.AceGUI.created) do
                if widget.kind == "ScrollFrame" then
                    scroll = widget
                end
            end
            -- Text only: the filter widgets come back separately, by label.
            local result, controls = {}, {}
            for _, child in ipairs(scroll.children) do
                if child.text == "Open Guild Roster" then
                    break
                end
                if child.label then
                    controls[child.label] = child
                else
                    table.insert(result, child.kind .. ":" .. tostring(child.text))
                end
            end
            return result, controls
        end

        it("lists guildmates in the main panel's Discovery section, live as statuses arrive", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            friend.ns.Core:HandleCommand("")
            assert.are.same({
                "Heading:Discovery (1)",
                "Label:Dresden — Malgen Zelwindran, Warrior 30 · Duskwood",
                "Label:    At your level: Malgen Zelwindran, Warrior 30",
                "Button:Whisper Malgen Zelwindran",
            }, panel(friend))
            alt.ns.Core:HandleCommand("status dungeons")
            deliver(alt, friend)
            assert.are.equal("Label:Dresden — Malgen Zelwindran, Warrior 30 · Up for Dungeons · Duskwood",
                panel(friend)[2])
        end)

        it("drops a status from an open panel when it times out, without a roster update", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            friend.ns.Core:HandleCommand("")
            alt.ns.Core:HandleCommand("status dungeons")
            deliver(alt, friend)
            assert.are.equal("Label:Dresden — Malgen Zelwindran, Warrior 30 · Up for Dungeons · Duskwood",
                panel(friend)[2])
            friend.harness:advance(2 * 60 * 60 - 10)
            assert.are.equal("Label:Dresden — Malgen Zelwindran, Warrior 30 · Up for Dungeons · Duskwood",
                panel(friend)[2])
            friend.harness:advance(20)
            assert.are.equal("Label:Dresden — Malgen Zelwindran, Warrior 30 · Duskwood", panel(friend)[2])
            assert.is_nil(friend.ns.availability.records["G-D"])
        end)

        it("updates Discovery when the roster changes and hides people set to Busy", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            friend.ns.Core:HandleCommand("")
            alt.ns.Core:HandleCommand("status busy")
            deliver(alt, friend)
            assert.are.same({ "Heading:Discovery (0)", "Label:Nobody else is online who's free to play right now." },
                panel(friend))
            alt.harness:advance(1)
            alt.ns.Core:HandleCommand("status clear")
            deliver(alt, friend)
            friend.harness.options.roster = { ROSTER[1], { name = "Malgen Zelwindran", guid = "G-M",
                note = ">Dresden", online = false, level = 30, className = "Warrior" }, ROSTER[3] }
            friend.ns.Core[friend.log.addon.events.GUILD_ROSTER_UPDATE](friend.ns.Core, "GUILD_ROSTER_UPDATE", false)
            friend.harness:advance(1)
            assert.are.equal("Heading:Discovery (0)", panel(friend)[1])
        end)

        it("filters Discovery from saved filters, redrawing on change", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            friend.ns.Core:HandleCommand("")
            local _, controls = panel(friend)
            assert.are.equal("any", controls["Up for"].value)
            assert.are.equal("any", controls["Can fill"].value)
            assert.is_false(controls["Same zone as me"].value)
            assert.is_false(controls["Show Busy"].value)
            controls["Up for"].callbacks.OnValueChanged(controls["Up for"], "OnValueChanged", "pvp")
            friend.harness:advance(0)
            assert.are.equal("pvp", friend.ns.Core.db.profile.discovery.status)
            assert.are.same({ "Heading:Discovery (0)", "Label:Nobody online matches these filters right now." },
                panel(friend))
            alt.ns.Core:HandleCommand("status pvp")
            deliver(alt, friend)
            assert.are.equal("Heading:Discovery (1)", panel(friend)[1])
            _, controls = panel(friend)
            assert.are.equal("pvp", controls["Up for"].value)
            controls["Same zone as me"].callbacks.OnValueChanged(controls["Same zone as me"], "OnValueChanged", true)
            friend.harness:advance(0)
            assert.are.equal("Heading:Discovery (0)", panel(friend)[1])
            controls = select(2, panel(friend))
            controls["Up for"].callbacks.OnValueChanged(controls["Up for"], "OnValueChanged", "any")
            controls["Same zone as me"].callbacks.OnValueChanged(controls["Same zone as me"], "OnValueChanged", false)
            controls["Can fill"].callbacks.OnValueChanged(controls["Can fill"], "OnValueChanged", "heal")
            friend.harness:advance(0)
            assert.is_nil(friend.ns.Core.db.profile.discovery.status)
            assert.are.equal("heal", friend.ns.Core.db.profile.discovery.role)
            assert.are.equal("Heading:Discovery (0)", panel(friend)[1])
        end)

        local function button(c, text)
            local scroll
            for _, widget in ipairs(c.log.AceGUI.created) do
                if widget.kind == "ScrollFrame" then
                    scroll = widget
                end
            end
            for _, child in ipairs(scroll.children) do
                if child.text == text then
                    return child
                end
            end
        end

        it("opens a pre-addressed whisper from Discovery and sends nothing", function()
            local told = {}
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = ROSTER,
                units = { player = { name = "Kira", player = true } },
                globals = { ChatFrame_SendTell = function(name) table.insert(told, name) end,
                    SendChatMessage = function() error("nothing may be sent") end },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            ns.Core:HandleCommand("")
            local friend = { log = log }
            button(friend, "Whisper Malgen Zelwindran").callbacks.OnClick()
            assert.are.same({ "Malgen Zelwindran" }, told)
            assert.are.same({}, log.addon.sent)
        end)

        it("sets my status from the Discovery view", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            alt.ns.Core:HandleCommand("")
            local _, controls = panel(alt)
            assert.are.equal("none", controls["My status"].value)
            controls["My status"].callbacks.OnValueChanged(controls["My status"], "OnValueChanged", "helping")
            alt.harness:advance(0)
            assert.are.equal("helping", select(2, panel(alt))["My status"].value)
            deliver(alt, friend)
            assert.are.equal("helping", friend.ns.availability:Get("G-D"))
        end)

        it("uses the level range from settings", function()
            local alt = client("Malgen Zelwindran")
            alt.ns.Core:HandleCommand("")
            assert.are.equal("Label:    At your level: Kira, Priest 33", panel(alt)[3])
            local range = alt.log.options.registered.table.args.features.args.discoveryRange
            assert.are.equal(3, range.get())
            assert.are.equal(1, range.min)
            assert.are.equal(10, range.max)
            range.set(nil, 2)
            assert.are.same({ "Heading:Discovery (1)", "Label:Kira — Kira, Priest 33", "Button:Whisper Kira" },
                panel(alt))
        end)

        it("explains Discovery outside a guild", function()
            local ns, log = boot({ units = { player = { name = "Nobody", player = true } } })
            ns.Core:HandleCommand("")
            local c = { log = log }
            assert.are.same({ "Heading:Discovery",
                "Label:Discovery shows who you could play with once you're in a guild and the roster has loaded." },
                panel(c))
        end)

        it("ends a status when the person logs off", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            alt.ns.Core:HandleCommand("status questing")
            deliver(alt, friend)
            assert.are.equal("questing", friend.ns.availability:Get("G-D"))
            local offline = {
                ROSTER[1],
                { name = "Malgen Zelwindran", guid = "G-M", note = ">Dresden", online = false },
                ROSTER[3],
            }
            friend.harness.options.roster = offline
            friend.ns.Core[friend.log.addon.events.GUILD_ROSTER_UPDATE](friend.ns.Core, "GUILD_ROSTER_UPDATE", true)
            friend.harness:advance(1)
            friend.harness.options.roster = ROSTER
            friend.ns.Core[friend.log.addon.events.GUILD_ROSTER_UPDATE](friend.ns.Core, "GUILD_ROSTER_UPDATE", true)
            friend.harness:advance(1)
            assert.are.equal("none", friend.ns.availability:Get("G-D"))
        end)
    end)

    describe("Guild Roster", function()
        local ROSTER = {
            { name = "Dresden Zelwindran", guid = "G-D", note = "", online = false, level = 60, className = "Mage" },
            { name = "Malgen Zelwindran", guid = "G-M", note = ">Dresden", online = true, level = 30,
                className = "Warrior", zone = "Duskwood" },
            { name = "Kira", guid = "G-K", note = "", online = true, level = 33, className = "Priest" },
            { name = "Olaf", guid = "G-O", note = "", online = false, level = 12, className = "Rogue" },
        }

        local function client(name)
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = ROSTER,
                units = { player = { name = name, player = true } },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            return { name = name, ns = ns, log = log, harness = harness }
        end

        -- The open Guild Roster window's lines, or nil when it isn't open.
        local function texts(c)
            local frame
            for _, widget in ipairs(c.log.AceGUI.created) do
                if widget.kind == "Frame" and widget.title == "Guild Roster" then
                    frame = widget
                end
            end
            if not frame or not c.ns.Core.rosterWindow:IsShown() then
                return nil
            end
            -- Text and buttons; the search box and checkbox come back separately.
            local result, controls = {}, {}
            for _, child in ipairs(frame.children[1].children) do
                if child.label then
                    controls[child.label] = child
                else
                    table.insert(result, child.kind .. ":" .. tostring(child.text))
                end
            end
            return result, controls
        end

        it("opens from /fellowship roster, listing the guild by person", function()
            local c = client("Kira")
            assert.is_nil(texts(c))
            c.ns.Core:HandleCommand("roster")
            assert.are.same({
                "Heading:2 of 3 people online (2 characters)",
                "Label:Dresden · online as Malgen Zelwindran (Duskwood)",
                "Label:    Dresden Zelwindran — Mage 60 (main, offline) · Malgen Zelwindran — Warrior 30",
                "Button:Whisper Malgen Zelwindran",
                "Label:Kira · online as Kira",
                "Label:    Kira — Priest 33 (main)",
                "Label:Olaf · offline",
                "Label:    Olaf — Rogue 12 (main)",
            }, texts(c))
        end)

        it("opens from the main panel's button", function()
            local c = client("Kira")
            c.ns.Core:HandleCommand("")
            local button
            for _, widget in ipairs(c.log.AceGUI.created) do
                if widget.kind == "Button" and widget.text == "Open Guild Roster" then
                    button = widget
                end
            end
            assert.is_false(button.disabled)
            button.callbacks.OnClick()
            assert.are.equal("Heading:2 of 3 people online (2 characters)", texts(c)[1])
        end)

        it("updates live on roster changes and synced statuses", function()
            local alt = client("Malgen Zelwindran")
            local friend = client("Kira")
            friend.ns.Core:HandleCommand("roster")
            alt.ns.Core:HandleCommand("status pvp")
            for _, message in ipairs(alt.log.addon.sent) do
                friend.ns.Core:OnCommReceived(message.prefix, message.message, message.distribution, alt.name)
            end
            assert.are.equal("Label:Dresden · online as Malgen Zelwindran (Duskwood) · Up for PvP", texts(friend)[2])
            friend.harness.options.roster = { ROSTER[1], ROSTER[2], ROSTER[3], { name = "Olaf", guid = "G-O",
                note = "", online = true, level = 12, className = "Rogue", zone = "Mulgore" } }
            friend.ns.Core[friend.log.addon.events.GUILD_ROSTER_UPDATE](friend.ns.Core, "GUILD_ROSTER_UPDATE", false)
            friend.harness:advance(1)
            assert.are.equal("Heading:3 of 3 people online (3 characters)", texts(friend)[1])
            assert.are.equal("Label:Olaf · online as Olaf (Mulgore)", texts(friend)[7])
        end)

        it("searches on Enter, says when nothing matches, and clears the search", function()
            local c = client("Kira")
            c.ns.Core:HandleCommand("roster")
            local _, controls = texts(c)
            local search = controls["Search (name or alias)"]
            assert.are.equal("", search.text)
            search.callbacks.OnEnterPressed(search, "OnEnterPressed", "malgen")
            c.harness:advance(0)
            local lines
            lines, controls = texts(c)
            assert.are.same({
                "Heading:2 of 3 people online (2 characters)",
                "Label:Dresden · online as Malgen Zelwindran (Duskwood)",
                "Label:    Dresden Zelwindran — Mage 60 (main, offline) · Malgen Zelwindran — Warrior 30",
                "Button:Whisper Malgen Zelwindran",
            }, lines)
            assert.are.equal("malgen", controls["Search (name or alias)"].text)
            controls["Search (name or alias)"].callbacks.OnEnterPressed(search, "OnEnterPressed", "nobody")
            c.harness:advance(0)
            lines = texts(c)
            assert.are.same({ "Heading:2 of 3 people online (2 characters)", 'Label:Nobody matches "nobody".',
                "Button:Clear search" }, lines)
            local clear
            for _, widget in ipairs(c.log.AceGUI.created) do
                if widget.kind == "Button" and widget.text == "Clear search" then
                    clear = widget
                end
            end
            clear.callbacks.OnClick()
            c.harness:advance(0)
            assert.are.equal(8, #texts(c))
        end)

        it("remembers whether to show offline people", function()
            local c = client("Kira")
            c.ns.Core:HandleCommand("roster")
            local _, controls = texts(c)
            local toggle = controls["Show offline people"]
            assert.is_true(toggle.value)
            toggle.callbacks.OnValueChanged(toggle, "OnValueChanged", false)
            c.harness:advance(0)
            assert.is_false(c.ns.Core.db.profile.roster.showOffline)
            local lines
            lines, controls = texts(c)
            assert.is_false(controls["Show offline people"].value)
            assert.are.equal("Heading:2 of 3 people online (2 characters)", lines[1])
            for _, line in ipairs(lines) do
                assert.is_nil(line:find("Olaf", 1, true))
            end
        end)

        it("whispers an online person without sending anything, and not yourself", function()
            local told = {}
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = ROSTER,
                units = { player = { name = "Kira", player = true } },
                globals = { ChatFrame_SendTell = function(name) table.insert(told, name) end,
                    SendChatMessage = function() error("nothing may be sent") end },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            ns.Core:HandleCommand("roster")
            local c = { ns = ns, log = log }
            local lines = texts(c)
            local whispers = {}
            for _, line in ipairs(lines) do
                if line:find("^Button:Whisper") then
                    table.insert(whispers, line)
                end
            end
            assert.are.same({ "Button:Whisper Malgen Zelwindran" }, whispers)
            for _, widget in ipairs(log.AceGUI.created) do
                if widget.kind == "Button" and widget.text == "Whisper Malgen Zelwindran" then
                    widget.callbacks.OnClick()
                end
            end
            assert.are.same({ "Malgen Zelwindran" }, told)
            assert.are.same({}, log.addon.sent)
        end)

        it("explains itself outside a guild and lists the command in usage", function()
            local ns, log = boot({ units = { player = { name = "Nobody", player = true } } })
            ns.Core:HandleCommand("roster")
            assert.are.same({
                "Label:The Guild Roster shows your guild once you're in a guild and the roster has loaded.",
            }, texts({ ns = ns, log = log }))
            ns.Core:HandleCommand("dance")
            assert.are.equal("/fellowship roster opens the Guild Roster, grouped by person.", log.addon.printed[5])
        end)
    end)

    describe("/fellowship clear", function()
        local RANKS = { { name = "Guild Master", canEditOfficerNote = true }, { name = "Member" } }
        local ROSTER = {
            { name = "Leader", guid = "G-L", note = "", rankIndex = 0 },
            { name = "Dresden Zelwindran", guid = "G-D", note = "", rankIndex = 1 },
            { name = "Malgen Zelwindran", guid = "G-M", note = ">Dresden", rankIndex = 1 },
        }

        local function client(name)
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = ROSTER, ranks = RANKS,
                units = { player = { name = name, player = true } },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            return { name = name, ns = ns, log = log }
        end

        local function deliver(from, to)
            local sent = from.log.addon.sent
            from.log.addon.sent = {}
            for _, message in ipairs(sent) do
                to.ns.Core:OnCommReceived(message.prefix, message.message, message.distribution, from.name)
            end
        end

        it("lets an officer clear someone's bio, and the clear reaches everyone", function()
            local owner = client("Malgen Zelwindran")
            local officer = client("Leader")
            owner.ns.Core:SaveProfile({ aliasFallback = "Zel", bio = "rude words" })
            deliver(owner, officer)
            officer.ns.Core:HandleCommand("clear bio Zel")
            assert.are.same({ "Cleared Dresden's bio." }, officer.log.addon.printed)
            assert.is_nil(officer.ns.profiles:Get("G-D").bio)
            deliver(officer, owner)
            assert.is_nil(owner.ns.profiles:Get("G-D").bio)
            assert.are.equal("Zel", owner.ns.profiles:Get("G-D").aliasFallback)
        end)

        it("clears an alias", function()
            local owner = client("Malgen Zelwindran")
            local officer = client("Leader")
            owner.ns.Core:SaveProfile({ aliasFallback = "Zel" })
            deliver(owner, officer)
            officer.ns.Core:HandleCommand("clear alias Malgen")
            assert.is_nil(officer.ns.profiles:Get("G-D").aliasFallback)
            assert.are.equal("Dresden", officer.ns.identity:GetDisplayName("G-D"))
        end)

        it("refuses non-officers", function()
            local member = client("Dresden Zelwindran")
            member.ns.Core:SaveProfile({ bio = "mine" })
            member.ns.Core:HandleCommand("clear bio Leader")
            assert.are.same({ "Only addon officers can clear profiles." }, member.log.addon.printed)
        end)

        it("explains usage, unknown names, and empty profiles", function()
            local officer = client("Leader")
            officer.ns.Core:HandleCommand("clear")
            officer.ns.Core:HandleCommand("clear discord Zel")
            officer.ns.Core:HandleCommand("clear bio Nobody")
            officer.ns.Core:HandleCommand("clear bio Malgen")
            local printed = officer.log.addon.printed
            assert.truthy(printed[1]:find("Usage", 1, true))
            assert.truthy(printed[2]:find("Usage", 1, true))
            assert.are.equal('No guildmate matches "Nobody".', printed[3])
            assert.are.equal("Dresden has no bio to clear.", printed[4])
        end)
    end)

    describe("Identity Issues view", function()
        local RANKS = { { name = "Guild Master", canEditOfficerNote = true }, { name = "Member" } }
        local MESSY = {
            { name = "Leader", guid = "G-L", note = "", rankIndex = 0 },
            { name = "Dresden Zelwindran", guid = "G-D", note = "", rankIndex = 1 },
            { name = "Dresden Other", guid = "G-O", note = "", rankIndex = 1 },
            { name = "Malgen", guid = "G-M", note = ">Dresden", rankIndex = 1 },
            { name = "Kira", guid = "G-K", note = ">Nobody", rankIndex = 1 },
        }
        local CLEAN = { MESSY[1], MESSY[2], { name = "Malgen", guid = "G-M", note = ">Dresden Zelwindran",
            rankIndex = 1 } }

        local function open(player, roster)
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = roster, ranks = RANKS,
                units = { player = { name = player, player = true } },
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            ns.Core:HandleCommand("")
            local function texts()
                local scroll
                for _, widget in ipairs(log.AceGUI.created) do
                    if widget.kind == "ScrollFrame" then
                        scroll = widget
                    end
                end
                -- From the Note Helper button on: the Discovery section above has its own tests.
                local result, children = {}, {}
                for _, child in ipairs(scroll.children) do
                    if #children > 0 or child.text == "Open Note Helper" then
                        table.insert(children, child)
                        table.insert(result, child.kind .. ":" .. tostring(child.text))
                    end
                end
                return result, { children = children }
            end
            return ns, texts, harness, log
        end

        it("lists issues grouped by type for an addon officer", function()
            local _, texts = open("Leader", MESSY)
            local lines, scroll = texts()
            assert.are.equal("Button:Open Note Helper", lines[1])
            assert.are.equal("Heading:Identity Issues (2)", lines[2])
            assert.are.equal("Heading:Ambiguous links (1)", lines[3])
            assert.are.equal("Label:Malgen: >Dresden", lines[5])
            assert.are.equal("Button:Fix in Note Helper", lines[7])
            assert.is_false(scroll.children[7].disabled)
            assert.are.equal("Heading:Unresolved links (1)", lines[8])
            assert.are.equal("Label:Kira: >Nobody", lines[10])
        end)

        it("shows an empty state when the notes are clean", function()
            local _, texts = open("Leader", CLEAN)
            assert.are.same({ "Button:Open Note Helper", "Heading:Identity Issues (0)",
                "Label:No problems with your guild's notes. Every link resolves cleanly." }, texts())
        end)

        it("hides the view from members", function()
            local _, texts = open("Kira", MESSY)
            assert.are.same({ "Button:Open Note Helper",
                "Label:Officer tools appear here for your guild's addon officers." }, texts())
        end)

        it("shows the officer view once the player is promoted, without reopening", function()
            local ns, texts, harness, log = open("Kira", MESSY)
            assert.are.equal("Label:Officer tools appear here for your guild's addon officers.", texts()[2])
            harness.options.roster[5].rankIndex = 0
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            assert.are.equal("Heading:Identity Issues (2)", texts()[2])
        end)

        it("updates live when identity changes", function()
            local ns, texts, harness, log = open("Leader", MESSY)
            harness.options.roster = CLEAN
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            assert.are.equal("Heading:Identity Issues (0)", texts()[2])
        end)
    end)

    describe("Note Helper", function()
        local RANKS = { { name = "Guild Master", canEditOfficerNote = true }, { name = "Member" } }

        local function roster()
            return {
                { name = "Leader", guid = "G-L", note = "", rankIndex = 0 },
                { name = "Dresden Zelwindran", guid = "G-D", note = "", rankIndex = 1 },
                { name = "Dresden Other", guid = "G-O", note = "", rankIndex = 1 },
                { name = "Malgen", guid = "G-M", note = "tank >Dresden", rankIndex = 1 },
            }
        end

        local function start(player, canEditPublicNote)
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = roster(), ranks = RANKS,
                units = { player = { name = player, player = true } }, canEditPublicNote = canEditPublicNote,
            })
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            return ns, log, harness
        end

        -- The Note Helper window's content (the last scroll frame created).
        local function helper(log)
            local scroll
            for _, widget in ipairs(log.AceGUI.created) do
                if widget.kind == "ScrollFrame" then
                    scroll = widget
                end
            end
            local byLabel = {}
            for _, child in ipairs(scroll.children) do
                byLabel[child.label or child.text] = child
            end
            return scroll, byLabel
        end

        local function lineStarting(scroll, prefix)
            for _, child in ipairs(scroll.children) do
                if child.text and child.text:sub(1, #prefix) == prefix then
                    return child.text
                end
            end
        end

        it("opens prefilled from an issue and writes the fixed note", function()
            local ns, log, harness = start("Leader", true)
            ns.Core:HandleCommand("")
            local panel = helper(log)
            for _, child in ipairs(panel.children) do
                if child.text == "Fix in Note Helper" then
                    child.callbacks.OnClick()
                    break
                end
            end
            local scroll, widgets = helper(log)
            assert.are.equal("Malgen-Forever", widgets.Alt.value)
            assert.are.equal("Current note: tank >Dresden", lineStarting(scroll, "Current note"))
            widgets.Main.callbacks.OnValueChanged(nil, nil, "Dresden Zelwindran-Forever")
            scroll, widgets = helper(log)
            assert.are.equal("New note: tank >Dresden Zelwindran", lineStarting(scroll, "New note"))
            assert.are.equal("Fits: 24 of 31 characters.", lineStarting(scroll, "Fits"))
            assert.is_false(widgets["Write note"].disabled)

            local requests = harness.rosterRequests
            widgets["Write note"].callbacks.OnClick()
            assert.are.same({ { guid = "G-M", text = "tank >Dresden Zelwindran", isPublic = true } },
                harness.notesWritten)
            assert.are.equal(requests + 1, harness.rosterRequests)
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            assert.are.equal("G-D", ns.identity:GetPerson("Malgen-Forever").id)
            assert.are.same({}, ns.identity:GetIssues())
        end)

        it("sets a main's alias", function()
            local ns, log, harness = start("Leader", true)
            ns.Core:OpenNoteHelper({ mode = "alias", main = "Dresden Zelwindran-Forever" })
            local _, widgets = helper(log)
            widgets["Alias (one word; leave empty to remove)"].callbacks.OnEnterPressed(nil, nil, "Zel")
            _, widgets = helper(log)
            widgets["Write note"].callbacks.OnClick()
            assert.are.equal("@Zel", harness.notesWritten[1].text)
        end)

        it("only offers the player's own note without public-note permission", function()
            local ns, log, harness = start("Malgen", false)
            ns.Core:HandleCommand("notes")
            local _, widgets = helper(log)
            assert.are.same({ "Malgen-Forever" }, widgets.Alt.order)
            assert.are.equal(4, #widgets.Main.order)
            ns.Core:OpenNoteHelper({ mode = "alias", main = "Dresden Zelwindran-Forever", alias = "Zel" })
            local scroll
            scroll, widgets = helper(log)
            assert.is_true(widgets["Write note"].disabled)
            assert.truthy(lineStarting(scroll, "You can't edit"))
            ns.Core:WriteNote()
            assert.are.same({}, harness.notesWritten)
        end)

        it("keeps the helper's state through roster updates that don't change identity", function()
            local ns, log, harness = start("Leader", true)
            ns.Core:OpenNoteHelper({ mode = "alias", main = "Dresden Zelwindran-Forever" })
            local _, before = helper(log)
            harness.options.roster[2].online = true
            harness.options.roster[2].zone = "Stormwind"
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            local _, after = helper(log)
            assert.are.equal(before["Alias (one word; leave empty to remove)"],
                after["Alias (one word; leave empty to remove)"])
        end)

        it("refuses to write a note that won't fit", function()
            local ns, log, harness = start("Leader", true)
            harness.options.roster[4].note = string.rep("x", 26) .. " >Dresden"
            ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
            harness:advance(1)
            ns.Core:OpenNoteHelper({ mode = "link", alt = "Malgen-Forever", main = "Dresden Zelwindran-Forever" })
            local scroll, widgets = helper(log)
            assert.are.equal("Too long by 15 characters.", lineStarting(scroll, "Too long"))
            assert.is_true(widgets["Write note"].disabled)
            ns.Core:WriteNote()
            assert.are.same({}, harness.notesWritten)
        end)
    end)

    describe("Guild Greet", function()
        local function roster()
            return {
                { name = "Me", guid = "G-ME", note = "", online = true },
                { name = "Dresden Zelwindran", guid = "G-D", note = "@Zel", online = false },
                { name = "Malgen", guid = "G-M", note = ">Dresden", online = false },
                { name = "Kira", guid = "G-K", note = "", online = false },
                { name = "Mine Alt", guid = "G-A", note = ">Me", online = false },
            }
        end

        local function start(enabled, initiallyOnline)
            local initial = roster()
            for _, index in ipairs(initiallyOnline or {}) do
                initial[index].online = true
            end
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = initial,
                units = { player = { name = "Me", player = true } },
            })
            if enabled then
                log.options.registered.table.args.features.args.greet.set(nil, true)
            end
            local function update()
                ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
                harness:advance(1)
            end
            update()
            local function online(index, value)
                harness.options.roster[index].online = value
                update()
            end
            -- The greet prompt's text and buttons, or nil when it isn't shown.
            local function prompt()
                local window
                for _, widget in ipairs(log.AceGUI.created) do
                    if widget.kind == "Window" and widget.shown ~= false and widget.children then
                        window = widget
                    end
                end
                if not window or not ns.Core.greeter.prompt:IsShown() then
                    return nil
                end
                local result = { buttons = {} }
                for _, child in ipairs(window.children) do
                    if child.kind == "Label" then
                        result.text = child.text
                    else
                        result.buttons[child.text] = child
                    end
                end
                return result
            end
            return ns, harness, online, prompt, log.options.registered.table.args.features.args.greet, log
        end

        it("is off by default and shows nothing", function()
            local _, harness, online, prompt = start(false)
            online(4, true)
            assert.is_nil(prompt())
            assert.are.same({}, harness.chatSent)
        end)

        it("offers a prompt when a guildmate comes online and greets only on click", function()
            local _, harness, online, prompt = start(true)
            online(4, true)
            local shown = prompt()
            assert.are.equal("Kira came online.", shown.text)
            assert.are.same({}, harness.chatSent)
            shown.buttons.Greet.callbacks.OnClick()
            assert.are.equal(1, #harness.chatSent)
            assert.are.equal("GUILD", harness.chatSent[1].channel)
            assert.truthy(harness.chatSent[1].text:find("Kira", 1, true))
            assert.is_nil(prompt())
        end)

        it("greets the person by their display name", function()
            local _, harness, online, prompt = start(true)
            online(3, true)
            assert.are.equal("Zel came online.", prompt().text)
            prompt().buttons.Greet.callbacks.OnClick()
            assert.truthy(harness.chatSent[1].text:find("Zel", 1, true))
        end)

        it("doesn't prompt for an alt switch, a quick relog, or the player's own alts", function()
            local _, _, online, prompt = start(true)
            online(2, true)
            prompt().buttons.Dismiss.callbacks.OnClick()
            online(2, false)
            online(3, true)
            assert.is_nil(prompt())
            online(3, false)
            online(3, true)
            assert.is_nil(prompt())
            online(5, true)
            assert.is_nil(prompt())
        end)

        it("doesn't prompt for anyone already online at login", function()
            local _, _, online, prompt = start(true, { 2, 4 })
            assert.is_nil(prompt())
            online(4, true)
            assert.is_nil(prompt())
        end)

        it("sends nothing when dismissed or closed", function()
            local ns, harness, online, prompt = start(true)
            online(4, true)
            prompt().buttons.Dismiss.callbacks.OnClick()
            assert.is_nil(prompt())
            online(2, true)
            ns.Core.greeter.prompt.frame.callbacks.OnClose(ns.Core.greeter.prompt.frame)
            assert.is_nil(prompt())
            assert.are.same({}, harness.chatSent)
        end)

        it("clears the prompt and starts a new baseline when turned off and on", function()
            local _, harness, online, prompt, toggle = start(true)
            online(4, true)
            toggle.set(nil, false)
            assert.is_false(toggle.get())
            assert.is_nil(prompt())
            online(2, true)
            assert.is_nil(prompt())
            toggle.set(nil, true)
            online(4, false)
            assert.is_nil(prompt())
            assert.are.same({}, harness.chatSent)
            harness:advance(1800)
            online(4, true)
            assert.are.equal("Kira came online.", prompt().text)
        end)

        it("ignores system messages the client hides from add-ons", function()
            local ns, harness = start(true)
            harness:advance(30)
            harness.env.issecretvalue = function(value)
                return type(value) == "string" and value:find("secret", 1, true) ~= nil
            end
            local before = harness.rosterRequests
            assert.has_no.errors(function()
                ns.Core:OnSystemMessage("CHAT_MSG_SYSTEM", "secret has joined the guild.")
                ns.Core:OnSystemMessage("CHAT_MSG_SYSTEM", nil)
            end)
            assert.are.equal(before, harness.rosterRequests)
            assert.is_false(ns.Core.greeter.prompt:IsShown())
        end)

        it("rejects over-long messages in settings", function()
            local _, _, _, _, _, log = start(true)
            local messages = log.options.registered.table.args.features.args.greetMessages
            assert.is_true(messages.validate(nil, "Hi {name}!\nHey {name}!"))
            assert.is_string(messages.validate(nil, "Hi {name}!\n" .. string.rep("x", 201)))
            assert.are.equal("Use {name} at most once per message.", messages.validate(nil, "{name} and {name}"))
        end)

        it("asks for the roster when the game announces someone came online", function()
            local ns, harness = start(true)
            harness:advance(30)
            local before = harness.rosterRequests
            ns.Core:OnSystemMessage("CHAT_MSG_SYSTEM", "|Hplayer:Kira|h[Kira]|h has come online.")
            assert.are.equal(before + 1, harness.rosterRequests)
            ns.Core:OnSystemMessage("CHAT_MSG_SYSTEM", "You are now AFK.")
            assert.are.equal(before + 1, harness.rosterRequests)
        end)

        describe("new members", function()
            -- Every row of the open prompt as "text" or "[button]".
            local function rows(ns)
                if not ns.Core.greeter.prompt:IsShown() then
                    return nil
                end
                local result = {}
                for _, child in ipairs(ns.Core.greeter.prompt.frame.children) do
                    table.insert(result, child.kind == "Label" and child.text or ("[" .. child.text .. "]"))
                end
                return result
            end

            local function button(ns, text)
                for _, child in ipairs(ns.Core.greeter.prompt.frame.children) do
                    if child.text == text then
                        return child
                    end
                end
            end

            local function join(ns, harness, name)
                ns.Core:OnSystemMessage("CHAT_MSG_SYSTEM", name .. " has joined the guild.")
                table.insert(harness.options.roster, { name = name, guid = "G-" .. name, note = "", online = true })
            end

            it("offers a Welcome when someone joins and posts one new-member line on click", function()
                local ns, harness = start(true)
                join(ns, harness, "Mike Newman")
                assert.are.same({ "Mike Newman joined the guild.", "[Welcome]", "[Dismiss]" }, rows(ns))
                button(ns, "Welcome").callbacks.OnClick()
                assert.are.equal(1, #harness.chatSent)
                local text = harness.chatSent[1].text
                local matched = false
                for _, template in ipairs(ns.GreetComposer.DEFAULT_NEW) do
                    matched = matched or text == template:gsub("{name}", "Mike Newman")
                end
                assert.is_true(matched, text)
                assert.is_nil(rows(ns))
            end)

            it("doesn't also offer the new member as a return when they show up online", function()
                local ns, harness, _, _, _, log = start(true)
                join(ns, harness, "Mike Newman")
                button(ns, "Dismiss").callbacks.OnClick()
                ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
                harness:advance(1)
                assert.is_nil(rows(ns))
            end)

            it("welcomes each new member once", function()
                local ns, harness = start(true)
                join(ns, harness, "Mike Newman")
                ns.Core:OnSystemMessage("CHAT_MSG_SYSTEM", "Mike Newman has joined the guild.")
                assert.are.same({ "Mike Newman joined the guild.", "[Welcome]", "[Dismiss]" }, rows(ns))
            end)

            it("keeps welcome-backs and welcomes in separate rows and lines", function()
                local ns, harness, online = start(true)
                online(4, true)
                join(ns, harness, "Mike Newman")
                assert.are.same({ "Kira came online.", "[Greet]", "Mike Newman joined the guild.", "[Welcome]",
                    "[Dismiss]" }, rows(ns))
                button(ns, "Greet").callbacks.OnClick()
                assert.are.same({ "Mike Newman joined the guild.", "[Welcome]", "[Dismiss]" }, rows(ns))
                assert.is_nil(harness.chatSent[1].text:find("Mike", 1, true))
                button(ns, "Welcome").callbacks.OnClick()
                assert.are.equal(2, #harness.chatSent)
                assert.is_nil(harness.chatSent[2].text:find("Kira", 1, true))
            end)

            it("uses the player's own new-member messages", function()
                local ns, harness, _, _, _, log = start(true)
                log.options.registered.table.args.features.args.newMessages.set(nil, "Glad you're here, {name}!")
                join(ns, harness, "Mike Newman")
                button(ns, "Welcome").callbacks.OnClick()
                assert.are.equal("Glad you're here, Mike Newman!", harness.chatSent[1].text)
            end)

            it("respects the Welcome new members toggle and Guild Greet being off", function()
                local ns, harness, _, _, toggle, log = start(true)
                local welcomeNew = log.options.registered.table.args.features.args.welcomeNew
                assert.is_true(welcomeNew.get())
                welcomeNew.set(nil, false)
                join(ns, harness, "Mike Newman")
                assert.is_nil(rows(ns))
                welcomeNew.set(nil, true)
                toggle.set(nil, false)
                join(ns, harness, "Ann Other")
                assert.is_nil(rows(ns))
            end)

            it("drops a new member other players already welcomed twice", function()
                local ns, harness = start(true)
                join(ns, harness, "Mike Newman")
                ns.Core.greeter:OnClaim({ "Mike Newman-Forever" }, "Anna-Forever")
                ns.Core.greeter:OnClaim({ "Mike Newman-Forever" }, "Bert-Forever")
                assert.is_nil(rows(ns))
            end)
        end)

        describe("prompt behavior", function()
            it("collects arrivals into one prompt and greets them in one line", function()
                local _, harness, online, prompt = start(true)
                online(2, true)
                online(4, true)
                assert.are.equal("Zel and Kira came online.", prompt().text)
                prompt().buttons.Greet.callbacks.OnClick()
                assert.are.equal(1, #harness.chatSent)
                assert.truthy(harness.chatSent[1].text:find("Zel and Kira", 1, true))
            end)

            it("hides an unanswered prompt after the timeout, restarting it for new arrivals", function()
                local ns, harness, online, prompt = start(true)
                local timeout = ns.Greeter.PROMPT_TIMEOUT
                online(4, true)
                harness:advance(timeout - 10)
                online(2, true)
                harness:advance(20)
                assert.are.equal("Kira and Zel came online.", prompt().text)
                harness:advance(timeout)
                assert.is_nil(prompt())
                assert.are.same({}, harness.chatSent)
            end)

            it("waits until combat ends to show the prompt", function()
                local ns, harness, online, prompt = start(true)
                harness.options.inCombat = true
                online(4, true)
                assert.is_nil(prompt())
                harness.options.inCombat = false
                ns.Core:OnCombatEnded()
                assert.are.equal("Kira came online.", prompt().text)
            end)

            it("drops arrivals that expired during combat", function()
                local ns, harness, online, prompt = start(true)
                harness.options.inCombat = true
                online(4, true)
                harness:advance(ns.Greeter.PROMPT_TIMEOUT)
                harness.options.inCombat = false
                ns.Core:OnCombatEnded()
                assert.is_nil(prompt())
            end)

            it("uses the player's own messages without repeating one back to back", function()
                local _, harness, online, prompt, _, log = start(true)
                local messages = log.options.registered.table.args.features.args.greetMessages
                assert.truthy(messages.get():find("Welcome back, {name}!", 1, true))
                messages.set(nil, "Hi {name}!\n\n  Hey {name}!  \n")
                assert.are.equal("Hi {name}!\nHey {name}!", messages.get())
                local sent = {}
                for _, index in ipairs({ 4, 2, 4 }) do
                    harness:advance(1800)
                    online(index, true)
                    prompt().buttons.Greet.callbacks.OnClick()
                    online(index, false)
                    table.insert(sent, harness.chatSent[#harness.chatSent].text)
                end
                for i, text in ipairs(sent) do
                    assert.truthy(text:match("^H[ie]y? "), text)
                    if i > 1 then
                        assert.are_not.equal(sent[i - 1]:match("^(%a+)"), text:match("^(%a+)"))
                    end
                end
                messages.set(nil, "   ")
                assert.truthy(messages.get():find("Welcome back, {name}!", 1, true))
            end)

            it("plays a short sound when the prompt opens, not on every update", function()
                local _, harness, online, prompt = start(true)
                online(4, true)
                assert.are.same({ 3081 }, harness.soundsPlayed)
                online(2, true)
                assert.are.equal(1, #harness.soundsPlayed)
                prompt().buttons.Dismiss.callbacks.OnClick()
                online(4, false)
                harness:advance(1800)
                online(4, true)
                assert.are.equal(2, #harness.soundsPlayed)
            end)

            it("plays no sound while combat holds the prompt back", function()
                local _, harness, online = start(true)
                harness.options.inCombat = true
                online(4, true)
                assert.are.same({}, harness.soundsPlayed)
            end)

            it("remembers where the prompt was dragged", function()
                local ns, _, online, prompt = start(true)
                online(4, true)
                assert.is_table(prompt())
                local frame = ns.Core.greeter.prompt.frame
                assert.are.equal(ns.Core.db.profile.greet.prompt, frame.status)
            end)
        end)
    end)

    describe("Guild Greet across add-on users", function()
        local function roster()
            return {
                { name = "Anna", guid = "G-A", note = "", online = true },
                { name = "Bert", guid = "G-B", note = "", online = true },
                { name = "Cara", guid = "G-C", note = "", online = true },
                { name = "Dresden Zelwindran", guid = "G-D", note = "@Zel", online = false },
                { name = "Malgen", guid = "G-M", note = ">Dresden", online = false },
                { name = "Kira", guid = "G-K", note = "", online = false },
            }
        end

        local function client(name)
            local ns, log, harness = boot({
                client = "Forever", guild = { name = "Asgard" }, roster = roster(),
                units = { player = { name = name, player = true } },
            })
            local features = log.options.registered.table.args.features.args
            features.greet.set(nil, true)
            local c = { name = name, ns = ns, log = log, harness = harness, features = features }
            function c.update()
                ns.Core[log.addon.events.GUILD_ROSTER_UPDATE](ns.Core, "GUILD_ROSTER_UPDATE", false)
                harness:advance(1)
            end
            function c.online(index)
                harness.options.roster[index].online = true
                c.update()
            end
            function c.prompt()
                if not ns.Core.greeter.prompt:IsShown() then
                    return nil
                end
                local frame = ns.Core.greeter.prompt.frame
                local result = { buttons = {} }
                for _, child in ipairs(frame.children) do
                    if child.kind == "Label" then
                        result.text = child.text
                    else
                        result.buttons[child.text] = child
                    end
                end
                return result
            end
            c.update()
            return c
        end

        -- Delivers each client's add-on messages to every other client.
        local function relay(clients)
            for _, from in ipairs(clients) do
                local sent = from.log.addon.sent
                from.log.addon.sent = {}
                for _, message in ipairs(sent) do
                    for _, to in ipairs(clients) do
                        if to ~= from then
                            to.ns.Core:OnCommReceived(message.prefix, message.message, message.distribution, from.name)
                        end
                    end
                end
            end
        end

        local function three()
            local clients = { client("Anna"), client("Bert"), client("Cara") }
            for _, c in ipairs(clients) do
                c.online(6)
            end
            relay(clients)
            return clients[1], clients[2], clients[3]
        end

        it("lets two players greet an arrival, then removes them from everyone else's prompt", function()
            local anna, bert, cara = three()
            assert.are.equal("Kira came online.", cara.prompt().text)
            anna.prompt().buttons.Greet.callbacks.OnClick()
            relay({ anna, bert, cara })
            assert.are.equal("Kira came online.", bert.prompt().text)
            assert.are.equal("Kira came online.", cara.prompt().text)
            bert.prompt().buttons.Greet.callbacks.OnClick()
            relay({ anna, bert, cara })
            assert.is_nil(cara.prompt())
            assert.are.equal(1, #anna.harness.chatSent)
            assert.are.equal(1, #bert.harness.chatSent)
            assert.are.equal(0, #cara.harness.chatSent)
        end)

        it("doesn't offer someone who already has two greetings when they reach a slower client", function()
            local anna, bert = client("Anna"), client("Bert")
            local cara = client("Cara")
            anna.online(6)
            bert.online(6)
            anna.prompt().buttons.Greet.callbacks.OnClick()
            bert.prompt().buttons.Greet.callbacks.OnClick()
            relay({ anna, bert, cara })
            cara.online(6)
            assert.is_nil(cara.prompt())
        end)

        it("only removes the people a greeting covered, and matches them by person", function()
            local _, _, cara = three()
            cara.online(5)
            assert.are.equal("Kira and Zel came online.", cara.prompt().text)
            cara.ns.Core.greeter:OnClaim({ "G-D" }, "Anna-Forever")
            cara.ns.Core.greeter:OnClaim({ "G-D" }, "Bert-Forever")
            assert.are.equal("Kira came online.", cara.prompt().text)
        end)

        it("counts each greeter once", function()
            local _, _, cara = three()
            cara.ns.Core.greeter:OnClaim({ "G-K" }, "Anna-Forever")
            cara.ns.Core.greeter:OnClaim({ "G-K" }, "Anna-Forever")
            assert.are.equal("Kira came online.", cara.prompt().text)
        end)

        it("ignores other players' greetings when sync is off", function()
            local anna, bert, cara = three()
            cara.features.sync.set(nil, false)
            anna.prompt().buttons.Greet.callbacks.OnClick()
            bert.prompt().buttons.Greet.callbacks.OnClick()
            relay({ anna, bert, cara })
            assert.are.equal("Kira came online.", cara.prompt().text)
        end)

        it("ignores malformed announcements", function()
            local _, _, cara = three()
            local greeter = cara.ns.Core.greeter
            for _, sender in ipairs({ "Anna-Forever", "Bert-Forever" }) do
                greeter:OnClaim(nil, sender)
                greeter:OnClaim("G-K", sender)
                greeter:OnClaim({ 5, {} }, sender)
            end
            greeter:OnClaim({ "G-K" }, nil)
            greeter:OnClaim({ "G-K" }, 42)
            assert.are.equal("Kira came online.", cara.prompt().text)
        end)
    end)
end)
