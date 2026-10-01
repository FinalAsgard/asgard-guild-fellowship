local Harness = require("support.wow")

local function loadCompat(options)
    local ns = Harness.new(options):loadAll({ "AsgardsGuildFellowship.lua", "Core/Compat.lua" })
    return ns.Compat
end

describe("Compat", function()
    describe("flavor detection", function()
        it("reads Forever from the manifest's X-Client", function()
            assert.are.equal("Forever", loadCompat({ client = "Forever" }).flavor)
        end)

        it("reads Retail from the manifest's X-Client", function()
            assert.are.equal("Retail", loadCompat({ client = "Retail" }).flavor)
        end)

        it("treats an unknown or missing client as Retail", function()
            local Compat = loadCompat()
            assert.are.equal("Retail", Compat.DetectFlavor(nil))
            assert.are.equal("Retail", Compat.DetectFlavor("Classic"))
        end)
    end)

    describe("BuildNameKey on Forever", function()
        local Compat = loadCompat({ client = "Forever" })
        local function key(name, realm, playerRealm)
            return Compat.BuildNameKey(Compat.FOREVER, name, realm, playerRealm)
        end

        it("adds the fixed realm to a bare name", function()
            assert.are.equal("Dresden Zelwindran-Forever", key("Dresden Zelwindran"))
        end)

        it("ignores a realm suffix from the API", function()
            assert.are.equal("Dresden Zelwindran-Forever", key("Dresden Zelwindran-Camelot"))
        end)

        it("ignores an explicit realm argument", function()
            assert.are.equal("Dresden Zelwindran-Forever", key("Dresden Zelwindran", "Camelot"))
        end)

        it("ignores the player's realm", function()
            assert.are.equal("Malgen-Forever", key("Malgen", nil, "SomeRealm"))
        end)

        it("keeps a one-word name", function()
            assert.are.equal("Malgen-Forever", key("Malgen"))
        end)

        it("trims and collapses whitespace in two-word names", function()
            assert.are.equal("Dresden Zelwindran-Forever", key("  Dresden   Zelwindran  "))
        end)

        it("returns nil for a missing or empty name", function()
            assert.is_nil(key(nil))
            assert.is_nil(key(""))
            assert.is_nil(key("   "))
            assert.is_nil(key("-Camelot"))
        end)
    end)

    describe("BuildNameKey on Retail", function()
        local Compat = loadCompat({ client = "Retail" })
        local function key(name, realm, playerRealm)
            return Compat.BuildNameKey(Compat.RETAIL, name, realm, playerRealm)
        end

        it("fills a missing realm with the player's realm", function()
            assert.are.equal("Thrall-Stormrage", key("Thrall", nil, "Stormrage"))
        end)

        it("keeps a realm suffix from the API", function()
            assert.are.equal("Thrall-Area52", key("Thrall-Area52", nil, "Stormrage"))
        end)

        it("uses an explicit realm argument", function()
            assert.are.equal("Thrall-Area52", key("Thrall", "Area52", "Stormrage"))
        end)

        it("prefers an explicit realm argument over a suffix", function()
            assert.are.equal("Thrall-Area52", key("Thrall-Stormrage", "Area52", "Stormrage"))
        end)

        it("normalizes realm names with spaces or hyphens", function()
            assert.are.equal("Thrall-Area52", key("Thrall", "Area 52", "Stormrage"))
            assert.are.equal("Thrall-AzjolNerub", key("Thrall-Azjol-Nerub", nil, "Stormrage"))
        end)

        it("treats an empty realm as missing", function()
            assert.are.equal("Thrall-Stormrage", key("Thrall", "", "Stormrage"))
            assert.are.equal("Thrall-Stormrage", key("Thrall-", nil, "Stormrage"))
        end)

        it("keeps the same name on different realms apart", function()
            assert.are_not.equal(key("Thrall", "Area52"), key("Thrall", "Stormrage"))
        end)

        it("preserves two-word names", function()
            assert.are.equal("Dresden Zelwindran-Stormrage", key("Dresden Zelwindran", nil, "Stormrage"))
        end)

        it("returns nil when no realm is known yet", function()
            assert.is_nil(key("Thrall", nil, nil))
        end)

        it("returns nil for a missing name", function()
            assert.is_nil(key(nil, "Area52", "Stormrage"))
        end)
    end)

    describe("NormalizeName", function()
        it("uses the fixed realm on Forever without asking the API", function()
            local Compat = loadCompat({ client = "Forever", realm = "Camelot" })
            assert.are.equal("Dresden Zelwindran-Forever", Compat.NormalizeName("Dresden Zelwindran", "Camelot"))
        end)

        it("uses the player's normalized realm on Retail", function()
            local Compat = loadCompat({ client = "Retail", realm = "Stormrage" })
            assert.are.equal("Thrall-Stormrage", Compat.NormalizeName("Thrall"))
            assert.are.equal("Thrall-Area52", Compat.NormalizeName("Thrall-Area52"))
        end)
    end)

    describe("client helpers", function()
        it("strips the realm from a key", function()
            local Compat = loadCompat()
            assert.are.equal("Dresden Zelwindran", Compat.NameFromKey("Dresden Zelwindran-Forever"))
            assert.are.equal("Thrall", Compat.NameFromKey("Thrall"))
        end)

        it("requests the roster through C_GuildInfo", function()
            local calls = 0
            local function count() calls = calls + 1 end
            local Compat = loadCompat({ globals = { C_GuildInfo = { GuildRoster = count } } })
            Compat.RequestGuildRoster()
            assert.are.equal(1, calls)
        end)

        it("falls back to the old GuildRoster global", function()
            local calls = 0
            local function count() calls = calls + 1 end
            local Compat = loadCompat({ globals = { C_GuildInfo = {}, GuildRoster = count } })
            Compat.RequestGuildRoster()
            assert.are.equal(1, calls)
        end)

        it("prefers ChatFrameUtil for chat filters", function()
            local added = {}
            local Compat = loadCompat({ globals = { ChatFrameUtil = { AddMessageEventFilter = function(event)
                table.insert(added, event)
            end } } })
            assert.is_true(Compat.AddMessageEventFilter("CHAT_MSG_GUILD", function() end))
            assert.are.same({ "CHAT_MSG_GUILD" }, added)
        end)

        it("reports when no chat filter API exists", function()
            local Compat = loadCompat({ globals = { ChatFrame_AddMessageEventFilter = false } })
            assert.is_false(Compat.AddMessageEventFilter("CHAT_MSG_GUILD", function() end))
        end)

        it("treats values as non-secret where the API doesn't exist", function()
            assert.is_false(loadCompat().IsSecret("text"))
            local Compat = loadCompat({ globals = { issecretvalue = function(value) return value == "s" end } })
            assert.is_true(Compat.IsSecret("s"))
            assert.is_false(Compat.IsSecret("t"))
        end)

        it("hooks unit tooltips through the tooltip-data API", function()
            local registered
            local Compat = loadCompat({ globals = {
                Enum = { TooltipDataType = { Unit = 2 } },
                TooltipDataProcessor = { AddTooltipPostCall = function(dataType, callback)
                    registered = { dataType = dataType, callback = callback }
                end },
            } })
            local seen
            Compat.HookUnitTooltip(function(_, unit) seen = unit end)
            assert.are.equal(2, registered.dataType)
            registered.callback({ GetUnit = function() return "Name", "mouseover" end })
            assert.are.equal("mouseover", seen)
        end)

        it("falls back to OnTooltipSetUnit without the tooltip-data API", function()
            local scripts = {}
            local tooltip = {
                HookScript = function(_, script, handler) scripts[script] = handler end,
                GetUnit = function() return "Name", "target" end,
            }
            local Compat = loadCompat({ globals = { GameTooltip = tooltip, TooltipDataProcessor = false } })
            local seen
            Compat.HookUnitTooltip(function(_, unit) seen = unit end)
            scripts.OnTooltipSetUnit(tooltip)
            assert.are.equal("target", seen)
        end)

        it("writes a public note by GUID where the client supports it", function()
            local written
            local Compat = loadCompat({ globals = { C_GuildInfo = { SetNote = function(guid, text, isPublic)
                written = { guid, text, isPublic }
            end } } })
            assert.is_true(Compat.SetPublicNote({ key = "A-Realm", guid = "G-A" }, ">B"))
            assert.are.same({ "G-A", ">B", true }, written)
        end)

        it("falls back to the roster index to write a public note", function()
            local written
            local Compat = loadCompat({ realm = "Realm", globals = {
                C_GuildInfo = {},
                GetNumGuildMembers = function() return 2 end,
                GetGuildRosterInfo = function(index) return ({ "Other-Realm", "A-Realm" })[index] end,
                GuildRosterSetPublicNote = function(index, text) written = { index, text } end,
            } })
            assert.is_true(Compat.SetPublicNote({ key = "A-Realm" }, ">B"))
            assert.are.same({ 2, ">B" }, written)
        end)

        it("reports when it can't write a note or check permission", function()
            local Compat = loadCompat({ globals = { C_GuildInfo = {}, CanEditPublicNote = false } })
            assert.is_false(Compat.SetPublicNote({ key = "A-Realm" }, ">B"))
            assert.is_false(Compat.CanEditPublicNote())
        end)
    end)
end)
