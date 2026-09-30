local Harness = require("support.wow")

local DRESDEN = {
    name = "Dresden Zelwindran", guid = "G-D", rankIndex = 1, level = 60, class = "WARRIOR",
    zone = "Stormwind", note = "@Zel", online = true,
}
local MALGEN = {
    name = "Malgen Zelwindran", guid = "G-M", rankIndex = 4, level = 34, class = "MAGE",
    zone = "", note = ">Dresden", online = false,
}

local function setup(options)
    local harness = Harness.new(options)
    local ns = harness:loadAll({ "AsgardsGuildFellowship.lua", "Core/Compat.lua", "Core/RosterAdapter.lua" })
    local snapshots = {}
    local adapter = ns.RosterAdapter.New(function(snapshot)
        table.insert(snapshots, snapshot)
    end)
    return adapter, snapshots, harness
end

describe("RosterAdapter", function()
    it("builds a snapshot entry per member", function()
        local adapter = setup({ client = "Forever", roster = { DRESDEN, MALGEN } })
        assert.are.same({
            {
                key = "Dresden Zelwindran-Forever", name = "Dresden Zelwindran", guid = "G-D", rankIndex = 1,
                class = "WARRIOR", level = 60, online = true, zone = "Stormwind", note = "@Zel",
            },
            {
                key = "Malgen Zelwindran-Forever", name = "Malgen Zelwindran", guid = "G-M", rankIndex = 4,
                class = "MAGE", level = 34, online = false, zone = "", note = ">Dresden",
            },
        }, adapter.BuildSnapshot())
    end)

    it("normalizes Retail names with realms", function()
        local adapter = setup({
            client = "Retail",
            realm = "Stormrage",
            roster = { { name = "Thrall-Area52", guid = "G-T", note = "" }, { name = "Jaina", guid = "G-J" } },
        })
        local snapshot = adapter.BuildSnapshot()
        assert.are.equal("Thrall-Area52", snapshot[1].key)
        assert.are.equal("Thrall", snapshot[1].name)
        assert.are.equal("Jaina-Stormrage", snapshot[2].key)
        assert.are.equal("", snapshot[2].note)
    end)

    it("debounces a burst of roster updates into one snapshot", function()
        local adapter, snapshots, harness = setup({ client = "Forever", roster = { DRESDEN } })
        adapter:OnRosterUpdate(false)
        adapter:OnRosterUpdate(false)
        adapter:OnRosterUpdate(false)
        assert.are.equal(0, #snapshots)
        harness:advance(1)
        assert.are.equal(1, #snapshots)
        adapter:OnRosterUpdate(false)
        harness:advance(1)
        assert.are.equal(2, #snapshots)
    end)

    it("skips an empty roster", function()
        local adapter, snapshots, harness = setup({ client = "Forever", roster = {} })
        adapter:OnRosterUpdate(false)
        harness:advance(1)
        assert.are.equal(0, #snapshots)
    end)

    it("throttles roster requests", function()
        local adapter, _, harness = setup({ client = "Forever", roster = { DRESDEN } })
        adapter:Request()
        adapter:Request()
        assert.are.equal(1, harness.rosterRequests)
        harness:advance(15)
        adapter:Request()
        assert.are.equal(2, harness.rosterRequests)
    end)

    it("requests fresh data when the server says it has changes", function()
        local adapter, _, harness = setup({ client = "Forever", roster = { DRESDEN } })
        adapter:OnRosterUpdate(true)
        assert.are.equal(1, harness.rosterRequests)
        adapter:OnRosterUpdate(false)
        assert.are.equal(1, harness.rosterRequests)
    end)
end)
