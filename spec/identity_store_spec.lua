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
        assert.are.same({ ["Malgen Zelwindran-Forever"] = { main = "G-D", target = "G-D", ref = "Dresden" } },
            guildData.resolutions)
    end)

    describe("IdentityChanged", function()
        local function counting()
            local store = newStore()
            local fired = { n = 0 }
            store.RegisterCallback({}, "IdentityChanged", function()
                fired.n = fired.n + 1
            end)
            return store, fired
        end

        local function with(changes)
            local roster = {}
            for index, member in ipairs(ROSTER) do
                local copy = {}
                for key, value in pairs(member) do
                    copy[key] = value
                end
                for key, value in pairs(changes[index] or {}) do
                    copy[key] = value
                end
                roster[index] = copy
            end
            return roster
        end

        it("fires on the first update and when identity changes", function()
            local store, fired = counting()
            store:Update(ROSTER)
            assert.are.equal(1, fired.n)
            store:Update(with({ [1] = { note = "@Drez" } }))
            assert.are.equal(2, fired.n)
        end)

        it("fires when a note changes even if identity stays the same", function()
            local store, fired = counting()
            store:Update(ROSTER)
            store:Update(with({ [3] = { note = "loves fishing" } }))
            assert.are.equal(2, fired.n)
        end)

        it("stays quiet for roster churn that doesn't touch identity", function()
            local store, fired = counting()
            store:Update(ROSTER)
            store:Update(with({ [1] = { online = true, zone = "Stormwind", level = 61 } }))
            store:Update(ROSTER)
            assert.are.equal(1, fired.n)
        end)
    end)

    it("reports note issues", function()
        local store = newStore()
        store:Update({
            { key = "Malgen-Forever", name = "Malgen", guid = "G-M", note = ">Nobody" },
        })
        local issues = store:GetIssues()
        assert.are.equal(1, #issues)
        assert.are.equal("unresolved", issues[1].type)
        assert.are.same({ "Malgen-Forever" }, issues[1].characters)
        assert.are.equal("Nobody", issues[1].ref)
        assert.is_string(issues[1].fix)
    end)

    it("keeps a saved link when a new character makes the note ambiguous", function()
        local guildData = {}
        local store = newStore(guildData)
        store:Update(ROSTER)
        local grown = { ROSTER[1], ROSTER[2], ROSTER[3],
            { key = "Dresden Newcomer-Forever", name = "Dresden Newcomer", guid = "G-N", note = "" } }
        store:Update(grown)
        assert.are.equal("G-D", store:GetPerson("Malgen Zelwindran-Forever").id)
        assert.are.equal("ambiguous", store:GetIssues()[1].type)

        local fresh = newStore({})
        fresh:Update(grown)
        assert.are.equal("G-M", fresh:GetPerson("Malgen Zelwindran-Forever").id)
    end)
end)
