local Harness = require("support.wow")
local FakeLibs = require("support.fake_libs")

-- Rank 0 guild master, 1 officer (can edit officer notes), 2 member.
local RANKS = {
    { index = 0, name = "Guild Master", canEditOfficerNote = true },
    { index = 1, name = "Officer", canEditOfficerNote = true },
    { index = 2, name = "Veteran", canEditOfficerNote = false },
    { index = 3, name = "Member", canEditOfficerNote = false },
}

local function member(name, rankIndex)
    return { key = name .. "-Forever", name = name, note = "", guid = "G-" .. name, rankIndex = rankIndex }
end

local ROSTER = { member("Leader", 0), member("Officer", 1), member("Veteran", 2), member("Member", 3) }

local function load()
    local LibStub = FakeLibs.new()
    return Harness.new({ globals = { LibStub = LibStub } }):loadAll({
        "Core/NoteCodec.lua",
        "Core/IdentityResolver.lua",
        "Core/IdentityStore.lua",
        "Core/GuildSettings.lua",
        "Core/SyncMerge.lua",
    })
end

local function newSettings(guildData)
    local ns = load()
    local store = ns.IdentityStore.New(guildData or {})
    store:Update(ROSTER)
    local settings = ns.GuildSettings.New(store.data, store, function()
        return RANKS
    end)
    return settings, ns
end

local function membersByKey()
    local members = {}
    for _, m in ipairs(ROSTER) do
        members[m.key] = m
    end
    return members
end

describe("GuildSettings", function()
    local ns = load()

    it("defaults to the guild master's rank plus ranks that can edit officer notes", function()
        assert.are.same({ [0] = true, [1] = true }, ns.GuildSettings.DefaultOfficerRanks(RANKS))
        assert.are.same({ [0] = true }, ns.GuildSettings.DefaultOfficerRanks({}))
    end)

    it("uses the record's officer ranks when there is one", function()
        assert.are.same({ [2] = true }, ns.GuildSettings.OfficerRanks({ officerRanks = { [2] = true } }, RANKS))
        assert.are.same({ [0] = true, [1] = true }, ns.GuildSettings.OfficerRanks(nil, RANKS))
    end)

    it("knows who is an addon officer by their current rank", function()
        local settings = newSettings()
        assert.is_true(settings:IsAddonOfficer("Leader-Forever"))
        assert.is_true(settings:IsAddonOfficer("Officer-Forever"))
        assert.is_false(settings:IsAddonOfficer("Member-Forever"))
        assert.is_false(settings:IsAddonOfficer("Stranger-Forever"))
        assert.is_false(settings:IsAddonOfficer(nil))
    end)

    it("lets an officer publish new officer ranks", function()
        local settings = newSettings()
        local fired = 0
        settings.RegisterCallback({}, "GuildSettingsChanged", function()
            fired = fired + 1
        end)
        assert.is_true(settings:Publish({ [0] = true, [2] = true, [3] = false }, "Officer-Forever"))
        assert.are.same({ version = 1, officerRanks = { [0] = true, [2] = true }, publisher = "Officer-Forever" },
            settings:Record())
        assert.are.equal(1, fired)
        assert.is_true(settings:IsAddonOfficer("Veteran-Forever"))
        assert.is_false(settings:IsAddonOfficer("Officer-Forever"))
    end)

    it("refuses a publish from a non-officer", function()
        local settings = newSettings()
        assert.is_false(settings:Publish({ [3] = true }, "Member-Forever"))
        assert.is_nil(settings:Record())
    end)

    it("increments the version on each publish", function()
        local settings = newSettings()
        settings:Publish({ [0] = true, [1] = true }, "Leader-Forever")
        settings:Publish({ [0] = true }, "Leader-Forever")
        assert.are.equal(2, settings:Record().version)
    end)

    it("shares its record through the sync handler and accepts valid newer ones", function()
        local settings = newSettings()
        local handler = settings:SyncHandler()
        assert.are.same({}, handler.Versions())
        local record = { version = 3, officerRanks = { [0] = true, [3] = true }, publisher = "Leader-Forever" }
        assert.is_true(handler.Receive("guild", record, "Officer-Forever"))
        local fired = 0
        settings.RegisterCallback({}, "GuildSettingsChanged", function()
            fired = fired + 1
        end)
        handler.Commit()
        assert.are.equal(1, fired)
        assert.are.same({ guild = 3 }, handler.Versions())
        assert.are.same(record, handler.Get("guild"))
        assert.is_true(settings:IsAddonOfficer("Member-Forever"))
        assert.is_false(handler.Receive("other", record, "Officer-Forever"))
    end)
end)

describe("SyncMerge.GuildSettings", function()
    local ns = load()
    -- The third argument is who relayed the record; it never affects the decision.
    local function check(record, current)
        return { ns.SyncMerge.GuildSettings(record, current, membersByKey(), RANKS) }
    end
    local function record(version, publisher, ranks)
        return { version = version, publisher = publisher, officerRanks = ranks or { [0] = true } }
    end

    it("accepts a newer record from an officer", function()
        assert.are.same({ true }, check(record(1, "Officer-Forever"), nil, "Officer-Forever"))
        local current = record(1, "Leader-Forever", { [0] = true, [1] = true })
        assert.are.same({ true }, check(record(2, "Leader-Forever"), current, "Officer-Forever"))
    end)

    it("rejects a record published by a non-officer", function()
        assert.are.same({ false, "not an officer" }, check(record(1, "Member-Forever"), nil, "Member-Forever"))
        assert.are.same({ false, "not an officer" }, check(record(1, "Stranger-Forever"), nil, "Officer-Forever"))
    end)

    it("accepts an officer's record relayed by any guildmate", function()
        assert.are.same({ true }, check(record(1, "Leader-Forever"), nil, "Member-Forever"))
    end)

    it("rejects records that aren't newer", function()
        assert.are.same({ false, "not newer" }, check(record(2, "Leader-Forever"), record(2, "Leader-Forever"),
            "Leader-Forever"))
        assert.are.same({ false, "not newer" }, check(record(1, "Leader-Forever"), record(2, "Leader-Forever"),
            "Leader-Forever"))
    end)

    it("judges authority by the receiver's current record", function()
        local current = record(1, "Leader-Forever", { [0] = true, [3] = true })
        assert.are.same({ true }, check(record(2, "Member-Forever"), current, "Member-Forever"))
        assert.are.same({ false, "not an officer" }, check(record(2, "Officer-Forever"), current, "Officer-Forever"))
    end)

    it("rejects malformed records", function()
        for _, bad in ipairs({
            "text", {}, { version = "1", publisher = "Leader-Forever", officerRanks = {} },
            { version = 1, officerRanks = {} }, { version = 1, publisher = "Leader-Forever" },
            { version = 1, publisher = "Leader-Forever", officerRanks = { a = true } },
            { version = 1, publisher = "Leader-Forever", officerRanks = { [1] = "yes" } },
        }) do
            assert.are.same({ false, "malformed" }, check(bad, nil, "Leader-Forever"))
        end
    end)
end)
