local Harness = require("support.wow")

local ns = Harness.new():loadAll({ "Core/NoteCodec.lua", "Core/IdentityResolver.lua" })
local resolve = ns.IdentityResolver.resolve

-- A roster member on Forever. GUIDs are derived from the name so tests can
-- refer to people by their main's name.
local function member(name, note, guid)
    return { key = name .. "-Forever", name = name, note = note or "", guid = guid or ("GUID:" .. name) }
end

local function personOf(result, name)
    return result.persons[result.charToPerson[name .. "-Forever"]]
end

describe("IdentityResolver.resolve", function()
    it("links an alt to its main by unique first name", function()
        local result = resolve({
            member("Dresden Zelwindran", "@Zel"),
            member("Malgen Zelwindran", ">Dresden"),
        })
        local person = personOf(result, "Malgen Zelwindran")
        assert.are.equal("GUID:Dresden Zelwindran", person.id)
        assert.are.equal("Dresden Zelwindran-Forever", person.mainKey)
        assert.are.same({ "Dresden Zelwindran-Forever", "Malgen Zelwindran-Forever" }, person.characters)
        assert.are.equal(person, personOf(result, "Dresden Zelwindran"))
    end)

    it("links by exact full name when the first name is shared", function()
        local result = resolve({
            member("Dresden Zelwindran"),
            member("Dresden Other"),
            member("Malgen Zelwindran", ">Dresden Zelwindran"),
        })
        assert.are.equal("GUID:Dresden Zelwindran", personOf(result, "Malgen Zelwindran").id)
    end)

    it("lets an exact one-word name win over first-name matches", function()
        local result = resolve({
            member("Dresden"),
            member("Dresden Zelwindran"),
            member("Malgen", ">Dresden"),
        })
        assert.are.equal("GUID:Dresden", personOf(result, "Malgen").id)
    end)

    it("falls back to the first name when a two-word ref has no exact match", function()
        local result = resolve({ member("Dresden Zelwindran"), member("Malgen", ">Dresden Tank") })
        assert.are.equal("GUID:Dresden Zelwindran", personOf(result, "Malgen").id)
    end)

    it("matches names case-insensitively", function()
        local result = resolve({ member("Dresden Zelwindran"), member("Malgen", ">dresden") })
        assert.are.equal("GUID:Dresden Zelwindran", personOf(result, "Malgen").id)
    end)

    it("reads the legacy main: format", function()
        local result = resolve({ member("Dresden Zelwindran", "alias: Zel"), member("Malgen", "main: Dresden") })
        assert.are.equal("Zel", personOf(result, "Malgen").displayName)
    end)

    it("leaves an ambiguous first name unlinked", function()
        local result = resolve({ member("Dresden Zelwindran"), member("Dresden Other"), member("Malgen", ">Dresden") })
        assert.are.equal("GUID:Malgen", personOf(result, "Malgen").id)
    end)

    it("makes a character with no note its own person", function()
        local result = resolve({ member("Lonely Wanderer") })
        local person = personOf(result, "Lonely Wanderer")
        assert.are.equal("GUID:Lonely Wanderer", person.id)
        assert.are.same({ "Lonely Wanderer-Forever" }, person.characters)
        assert.is_nil(person.alias)
    end)

    it("makes a character whose ref matches nobody its own person", function()
        local result = resolve({ member("Malgen", ">Nobody") })
        assert.are.equal("GUID:Malgen", personOf(result, "Malgen").id)
    end)

    it("ignores a note that points at itself", function()
        local result = resolve({ member("Dresden Zelwindran", ">Dresden") })
        assert.are.same({ "Dresden Zelwindran-Forever" }, personOf(result, "Dresden Zelwindran").characters)
    end)

    describe("names", function()
        it("uses the main's note alias as the display name", function()
            local result = resolve({ member("Dresden Zelwindran", "@Zel"), member("Malgen", ">Dresden") })
            local person = personOf(result, "Malgen")
            assert.are.equal("Zel", person.alias)
            assert.are.equal("Zel", person.displayName)
        end)

        it("ignores an alias in an alt's note", function()
            local result = resolve({ member("Dresden Zelwindran"), member("Malgen", ">Dresden @Mal") })
            assert.is_nil(personOf(result, "Malgen").alias)
        end)

        it("uses a unique first name as the short and display name", function()
            local result = resolve({ member("Dresden Zelwindran"), member("Malgen", ">Dresden") })
            local person = personOf(result, "Malgen")
            assert.are.equal("Dresden", person.shortName)
            assert.are.equal("Dresden", person.displayName)
        end)

        it("uses the full name when the first name is shared", function()
            local result = resolve({ member("Dresden Zelwindran"), member("Dresden Other") })
            assert.are.equal("Dresden Zelwindran", personOf(result, "Dresden Zelwindran").shortName)
        end)
    end)

    it("keeps the person id when the main is renamed", function()
        local before = resolve({ member("Dresden Zelwindran", "", "GUID-1"), member("Malgen", ">Dresden") })
        local after = resolve({ member("Dresden Renamed", "", "GUID-1"), member("Malgen", ">Dresden") })
        assert.are.equal("GUID-1", personOf(before, "Malgen").id)
        assert.are.equal("GUID-1", personOf(after, "Malgen").id)
    end)

    it("records how each alt was resolved", function()
        local result = resolve({ member("Dresden Zelwindran"), member("Malgen", ">Dresden") })
        assert.are.same({ ["Malgen-Forever"] = { main = "GUID:Dresden Zelwindran", ref = "Dresden" } },
            result.resolutions)
    end)

    it("lists a person's alts in a stable order", function()
        local result = resolve({
            member("Zed", ">Dresden"),
            member("Dresden Zelwindran"),
            member("Anna", ">Dresden"),
        })
        assert.are.same({ "Dresden Zelwindran-Forever", "Anna-Forever", "Zed-Forever" },
            personOf(result, "Anna").characters)
    end)

    it("is deterministic regardless of roster order", function()
        local roster = { member("Dresden Zelwindran", "@Zel"), member("Malgen", ">Dresden"), member("Solo") }
        local reversed = { roster[3], roster[2], roster[1] }
        assert.are.same(resolve(roster), resolve(reversed))
    end)
end)
