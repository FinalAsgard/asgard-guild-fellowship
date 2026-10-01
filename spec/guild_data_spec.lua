local Harness = require("support.wow")

local GuildData = Harness.new():load("Core/GuildData.lua").GuildData

describe("GuildData.ForGuild", function()
    it("returns nil outside a guild", function()
        assert.is_nil(GuildData.ForGuild({}, nil))
    end)

    it("returns the same table for the same guild", function()
        local store = {}
        local first = GuildData.ForGuild(store, "Asgard-Forever")
        first.marker = true
        assert.are.equal(first, GuildData.ForGuild(store, "Asgard-Forever"))
    end)

    it("keeps each guild's data separate", function()
        local store = {}
        GuildData.ForGuild(store, "Asgard-Forever").marker = "asgard"
        local other = GuildData.ForGuild(store, "Midgard-Forever")
        assert.is_nil(other.marker)
    end)

    it("reuses data already in saved variables", function()
        local store = { guilds = { ["Asgard-Forever"] = { marker = "saved" } } }
        assert.are.equal("saved", GuildData.ForGuild(store, "Asgard-Forever").marker)
    end)
end)
