local Harness = require("support.wow")
local FakeLibs = require("support.fake_libs")

local function load()
    local LibStub = FakeLibs.new()
    return Harness.new({ globals = { LibStub = LibStub } }):loadAll({
        "Core/NoteCodec.lua",
        "Core/IdentityResolver.lua",
        "Core/IdentityStore.lua",
        "Core/WhoFormatter.lua",
    })
end

local ROSTER = {
    { key = "Dresden Zelwindran-Forever", name = "Dresden Zelwindran", guid = "G-D", note = "@Zel",
        level = 60, className = "Warrior", online = true, zone = "Stormwind" },
    { key = "Malgen Zelwindran-Forever", name = "Malgen Zelwindran", guid = "G-M", note = ">Dresden Zelwindran",
        level = 34, className = "Mage", online = false, zone = "" },
    { key = "Dresden Other-Forever", name = "Dresden Other", guid = "G-O", note = "",
        level = 20, className = "Rogue", online = true, zone = "" },
}

local function store()
    local ns = load()
    local s = ns.IdentityStore.New({})
    s:Update(ROSTER)
    return s, ns
end

local function ids(persons)
    local result = {}
    for _, person in ipairs(persons) do
        table.insert(result, person.id)
    end
    return result
end

describe("IdentityStore:FindByQuery", function()
    it("matches a full character name, case-insensitively", function()
        assert.are.same({ "G-D" }, ids(store():FindByQuery("malgen zelwindran")))
    end)

    it("matches a two-word name with quotes and extra spaces", function()
        assert.are.same({ "G-D" }, ids(store():FindByQuery(' "Malgen   Zelwindran" ')))
        assert.are.same({ "G-D" }, ids(store():FindByQuery("'Malgen Zelwindran'")))
    end)

    it("matches Name-Realm", function()
        assert.are.same({ "G-D" }, ids(store():FindByQuery("Malgen Zelwindran-Forever")))
    end)

    it("matches a first name", function()
        assert.are.same({ "G-D" }, ids(store():FindByQuery("Malgen")))
    end)

    it("matches an alias", function()
        assert.are.same({ "G-D" }, ids(store():FindByQuery("ZEL")))
    end)

    it("returns every person a shared first name matches", function()
        assert.are.same({ "G-O", "G-D" }, ids(store():FindByQuery("Dresden")))
    end)

    it("returns nothing for no match or an empty query", function()
        assert.are.same({}, store():FindByQuery("Nobody"))
        assert.are.same({}, store():FindByQuery("  "))
        assert.are.same({}, store():FindByQuery(nil))
    end)
end)

describe("WhoFormatter.Lines", function()
    local function lines(query)
        local s, ns = store()
        return ns.WhoFormatter.Lines(query, s:FindByQuery(query), function(key)
            return s:GetCharacterInfo(key)
        end)
    end

    it("lists the identity, main, and every character", function()
        assert.are.same({
            "Zel (main: Dresden Zelwindran)",
            "  Dresden Zelwindran (main) - 60 Warrior - online in Stormwind",
            "  Malgen Zelwindran - 34 Mage - offline",
        }, lines("Zel"))
    end)

    it("says online without a zone when none is known", function()
        assert.are.same({
            "Dresden Other (main: Dresden Other)",
            "  Dresden Other (main) - 20 Rogue - online",
        }, lines("Dresden Other"))
    end)

    it("lists each matching person for an ambiguous query", function()
        local result = lines("Dresden")
        assert.are.equal('2 people match "Dresden":', result[1])
        assert.are.equal("Dresden Other (main: Dresden Other)", result[2])
        assert.are.equal("Zel (main: Dresden Zelwindran)", result[4])
    end)

    it("explains when nothing matches", function()
        assert.are.same({ 'No guildmate matches "Nobody". Try a character name, first name, or alias.' },
            lines("Nobody"))
    end)

    it("adds the person's Discord name and bio", function()
        local s2, ns = store()
        local result = ns.WhoFormatter.Lines("Zel", s2:FindByQuery("Zel"), function(key)
            return s2:GetCharacterInfo(key)
        end, function(personId)
            return personId == "G-D" and { discord = "zelly", bio = "Tank and healer" } or nil
        end)
        assert.are.equal("  Discord: zelly", result[4])
        assert.are.equal("  Bio: Tank and healer", result[5])
    end)
end)
