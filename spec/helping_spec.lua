local Harness = require("support.wow")
local FakeLibs = require("support.fake_libs")

local function load()
    return Harness.new({ globals = { LibStub = FakeLibs.new() } }):loadAll({
        "Core/NoteCodec.lua",
        "Core/IdentityResolver.lua",
        "Core/IdentityStore.lua",
        "Core/Profiles.lua",
        "Core/Helping.lua",
        "Core/SyncMerge.lua",
    })
end

describe("Helping", function()
    it("parses known topics, deduplicated, in display order", function()
        local Helping = load().Helping
        assert.are.same({ "tanking", "quests" }, Helping.Parse("quests,tanking,quests"))
        assert.are.same({ "healing" }, Helping.Parse(" healing , someFutureTopic "))
        assert.are.same({}, Helping.Parse(""))
        assert.are.same({}, Helping.Parse(nil))
    end)

    it("formats a list for storage", function()
        local Helping = load().Helping
        assert.are.equal("newPlayers,pvp", Helping.Format({ "pvp", "newPlayers", "pvp", "bogus" }))
        assert.are.equal("", Helping.Format({}))
        assert.are.equal("", Helping.Format(nil))
    end)

    it("checks and labels a stored value", function()
        local Helping = load().Helping
        assert.is_true(Helping.Has("tanking,quests", "quests"))
        assert.is_false(Helping.Has("tanking", "quests"))
        assert.is_false(Helping.Has(nil, "quests"))
        assert.are.same({ "Class questions", "General mentoring" }, Helping.Labels("mentoring,classQuestions"))
        assert.are.same({}, Helping.Labels(nil))
    end)

    it("fits every topic within the profile field limit", function()
        local ns = load()
        assert.is_true(#ns.Helping.Format(ns.Helping.TOPICS) <= ns.Profiles.LIMITS.helps)
        for _, topic in ipairs(ns.Helping.TOPICS) do
            assert.is_string(ns.Helping.LABELS[topic])
        end
    end)
end)

describe("Profiles helps field", function()
    local ROSTER = {
        { key = "Kira-Forever", name = "Kira", note = "", guid = "G-Kira" },
        { key = "Malgen-Forever", name = "Malgen", note = "", guid = "G-Malgen" },
    }

    local function setup()
        local ns = load()
        local store = ns.IdentityStore.New({})
        store:Update(ROSTER)
        local profiles = ns.Profiles.New(store.data, store, function()
            return 0
        end, function()
            return false
        end)
        return profiles, ns
    end

    it("saves and clears the topics like any profile field", function()
        local profiles = setup()
        assert.is_true(profiles:Save("Kira-Forever", { helps = "tanking,quests" }))
        assert.are.equal("tanking,quests", profiles:Get("G-Kira").helps)
        assert.is_true(profiles:Save("Kira-Forever", { helps = "" }))
        assert.is_nil(profiles:Get("G-Kira").helps)
    end)

    it("refuses an over-long value", function()
        local profiles = setup()
        assert.are.same({ false, "helps is too long" },
            { profiles:Save("Kira-Forever", { helps = string.rep("x", 121) }) })
    end)

    it("only accepts topics from the person's own characters when synced", function()
        local profiles = setup()
        local handler = profiles:SyncHandler()
        assert.is_false(handler.Receive("G-Kira", { version = 5, author = "Malgen-Forever", helps = "pvp" }))
        assert.is_nil(profiles:Get("G-Kira"))
        assert.is_true(handler.Receive("G-Kira", { version = 5, author = "Kira-Forever", helps = "pvp" }))
        assert.are.equal("pvp", profiles:Get("G-Kira").helps)
        assert.is_false(handler.Receive("G-Kira",
            { version = 6, author = "Kira-Forever", helps = string.rep("x", 121) }))
    end)
end)
