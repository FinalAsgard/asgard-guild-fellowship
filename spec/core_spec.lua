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
            assert.are.equal(2, #log.addon.printed)
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
end)
