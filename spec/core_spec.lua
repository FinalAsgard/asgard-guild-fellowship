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
            assert.are.equal(1, #log.addon.printed)
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
end)
