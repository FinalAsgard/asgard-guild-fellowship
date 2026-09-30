local Harness = require("support.wow")
local FakeLibs = require("support.fake_libs")

local function newStore(guildData)
    local LibStub = FakeLibs.new()
    local ns = Harness.new({ globals = { LibStub = LibStub } }):loadAll({
        "Core/NoteCodec.lua",
        "Core/IdentityResolver.lua",
        "Core/IdentityStore.lua",
    })
    return ns.IdentityStore.New(guildData or {})
end

local ROSTER = {
    { key = "Dresden Zelwindran-Forever", name = "Dresden Zelwindran", guid = "G-D", note = "@Zel" },
    { key = "Malgen Zelwindran-Forever", name = "Malgen Zelwindran", guid = "G-M", note = ">Dresden" },
    { key = "Solo Player-Forever", name = "Solo Player", guid = "G-S", note = "" },
}

describe("IdentityStore", function()
    it("knows nobody before the first update", function()
        local store = newStore()
        assert.is_nil(store:GetPerson("Malgen Zelwindran-Forever"))
        assert.is_nil(store:GetPersonById("G-D"))
        assert.is_nil(store:GetCharacters("G-D"))
        assert.is_nil(store:GetDisplayName("G-D"))
        assert.is_nil(store:GetShortName("G-D"))
    end)

    describe("after an update", function()
        local store
        before_each(function()
            store = newStore()
            store:Update(ROSTER)
        end)

        it("finds a character's person", function()
            assert.are.equal("G-D", store:GetPerson("Malgen Zelwindran-Forever").id)
            assert.are.equal(store:GetPerson("Malgen Zelwindran-Forever"), store:GetPersonById("G-D"))
        end)

        it("lists a person's characters, main first", function()
            assert.are.same({ "Dresden Zelwindran-Forever", "Malgen Zelwindran-Forever" }, store:GetCharacters("G-D"))
        end)

        it("gives display and short names", function()
            assert.are.equal("Zel", store:GetDisplayName("G-D"))
            assert.are.equal("Dresden", store:GetShortName("G-D"))
            assert.are.equal("Solo", store:GetDisplayName("G-S"))
        end)

        it("returns nil for unknown characters", function()
            assert.is_nil(store:GetPerson("Stranger-Forever"))
        end)
    end)

    it("persists resolutions in the guild's data", function()
        local guildData = {}
        newStore(guildData):Update(ROSTER)
        assert.are.same({ ["Malgen Zelwindran-Forever"] = { main = "G-D", ref = "Dresden" } }, guildData.resolutions)
    end)

    it("fires IdentityChanged after each update", function()
        local store = newStore()
        local fired = 0
        store.RegisterCallback({}, "IdentityChanged", function()
            fired = fired + 1
        end)
        store:Update(ROSTER)
        store:Update(ROSTER)
        assert.are.equal(2, fired)
    end)
end)
