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
            for _, module in ipairs({ "Compat", "GuildData", "Commands", "UI", "Options" }) do
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
end)
