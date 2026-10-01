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
        assert.are.same({
            ["Malgen-Forever"] = {
                main = "GUID:Dresden Zelwindran", target = "GUID:Dresden Zelwindran", ref = "Dresden",
            },
        }, result.resolutions)
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

    describe("edge cases", function()
        local function issuesOf(result, issueType)
            local found = {}
            for _, issue in ipairs(result.issues) do
                if issue.type == issueType then
                    table.insert(found, issue)
                end
            end
            return found
        end

        it("has no issues for clean notes", function()
            local result = resolve({ member("Dresden Zelwindran", "@Zel"), member("Malgen", ">Dresden") })
            assert.are.same({}, result.issues)
        end)

        describe("chains", function()
            it("follows an alt of an alt to the terminal main and flags it", function()
                local result = resolve({
                    member("Dresden Zelwindran"),
                    member("Malgen", ">Dresden"),
                    member("Kira", ">Malgen"),
                })
                assert.are.equal("GUID:Dresden Zelwindran", personOf(result, "Kira").id)
                assert.are.same({ "Dresden Zelwindran-Forever", "Kira-Forever", "Malgen-Forever" },
                    personOf(result, "Kira").characters)
                local chains = issuesOf(result, "chain")
                assert.are.equal(1, #chains)
                assert.are.same({ "Kira-Forever", "Malgen-Forever", "Dresden Zelwindran-Forever" },
                    chains[1].characters)
                assert.are.equal("Malgen", chains[1].ref)
                assert.truthy(chains[1].fix:find(">Dresden", 1, true))
            end)

            it("gives up on chains longer than the limit", function()
                local roster = { member("M0") }
                for i = 1, 7 do
                    table.insert(roster, member("M" .. i, ">M" .. (i - 1)))
                end
                local result = resolve(roster)
                assert.are.equal("GUID:M0", personOf(result, "M5").id)
                assert.are.equal("GUID:M7", personOf(result, "M7").id)
                assert.is_true(#issuesOf(result, "chain") > 0)
            end)
        end)

        describe("cycles", function()
            it("leaves every member of a cycle unlinked and reports it once", function()
                local result = resolve({ member("Anna", ">Bert"), member("Bert", ">Anna") })
                assert.are.equal("GUID:Anna", personOf(result, "Anna").id)
                assert.are.equal("GUID:Bert", personOf(result, "Bert").id)
                local cycles = issuesOf(result, "cycle")
                assert.are.equal(1, #cycles)
                assert.are.same({ "Anna-Forever", "Bert-Forever" }, cycles[1].characters)
            end)

            it("handles longer cycles and characters pointing into them", function()
                local result = resolve({
                    member("Anna", ">Bert"),
                    member("Bert", ">Cara"),
                    member("Cara", ">Anna"),
                    member("Tail", ">Anna"),
                })
                for _, name in ipairs({ "Anna", "Bert", "Cara", "Tail" }) do
                    assert.are.equal("GUID:" .. name, personOf(result, name).id)
                end
                assert.are.same({ "Anna-Forever", "Bert-Forever", "Cara-Forever" },
                    issuesOf(result, "cycle")[1].characters)
                assert.are.equal(1, #issuesOf(result, "cycle"))
            end)
        end)

        describe("missing mains", function()
            it("reports a ref that never matched as unresolved", function()
                local result = resolve({ member("Malgen", ">Nobody") })
                local issue = issuesOf(result, "unresolved")[1]
                assert.are.same({ "Malgen-Forever" }, issue.characters)
                assert.are.equal("Nobody", issue.ref)
            end)

            it("reports a main who left the guild as an orphan, and keeps doing so", function()
                local first = resolve({ member("Dresden Zelwindran"), member("Malgen", ">Dresden") })
                local second = resolve({ member("Malgen", ">Dresden") }, first.resolutions)
                assert.are.equal("GUID:Malgen", personOf(second, "Malgen").id)
                assert.are.equal(1, #issuesOf(second, "orphan"))
                local third = resolve({ member("Malgen", ">Dresden") }, second.resolutions)
                assert.are.equal(1, #issuesOf(third, "orphan"))
            end)

            it("does not call a changed note an orphan", function()
                local first = resolve({ member("Dresden Zelwindran"), member("Malgen", ">Dresden") })
                local second = resolve({ member("Dresden Zelwindran"), member("Malgen", ">Other") }, first.resolutions)
                assert.are.equal(1, #issuesOf(second, "unresolved"))
                assert.are.equal(0, #issuesOf(second, "orphan"))
            end)
        end)

        describe("ambiguity", function()
            local roster = { member("Dresden Zelwindran"), member("Dresden Other"), member("Malgen", ">Dresden") }

            it("leaves an ambiguous ref unlinked without a cached resolution", function()
                local result = resolve(roster)
                assert.are.equal("GUID:Malgen", personOf(result, "Malgen").id)
                local issue = issuesOf(result, "ambiguous")[1]
                assert.are.same({ "Malgen-Forever" }, issue.characters)
                assert.truthy(issue.fix:find("Dresden Other, Dresden Zelwindran", 1, true))
            end)

            it("keeps a cached resolution that still fits the note, and still flags it", function()
                local cache = { ["Malgen-Forever"] = { main = "GUID:Dresden Zelwindran",
                    target = "GUID:Dresden Zelwindran", ref = "Dresden" } }
                local result = resolve(roster, cache)
                assert.are.equal("GUID:Dresden Zelwindran", personOf(result, "Malgen").id)
                assert.are.equal(1, #issuesOf(result, "ambiguous"))
            end)

            it("drops a cached resolution when the note's ref changed", function()
                local cache = { ["Malgen-Forever"] = { main = "GUID:Dresden Zelwindran",
                    target = "GUID:Dresden Zelwindran", ref = "Dres" } }
                assert.are.equal("GUID:Malgen", personOf(resolve(roster, cache), "Malgen").id)
            end)

            it("drops a cached resolution whose target no longer matches the ref", function()
                local cache = {
                    ["Malgen-Forever"] = { main = "GUID:Someone", target = "GUID:Someone", ref = "Dresden" },
                }
                assert.are.equal("GUID:Malgen", personOf(resolve(roster, cache), "Malgen").id)
            end)
        end)

        it("keeps alts with a renamed main once the alt's note is updated", function()
            local first = resolve({ member("Dresden Zelwindran", "", "G-1"), member("Malgen", ">Dresden") })
            local renamed = resolve({ member("Drez Zelwindran", "", "G-1"), member("Malgen", ">Drez") },
                first.resolutions)
            assert.are.equal("G-1", personOf(renamed, "Malgen").id)
            assert.are.same({ "Drez Zelwindran-Forever", "Malgen-Forever" }, personOf(renamed, "Malgen").characters)
            assert.are.same({}, renamed.issues)
        end)

        describe("Retail cross-realm", function()
            local function retail(name, realm, note)
                local key = name .. "-" .. realm
                return { key = key, name = name, note = note or "", guid = "G-" .. key }
            end

            it("treats the same name on two realms as two people", function()
                local result = resolve({ retail("Thrall", "Area52"), retail("Thrall", "Stormrage") })
                assert.are_not.equal(result.charToPerson["Thrall-Area52"], result.charToPerson["Thrall-Stormrage"])
            end)

            it("disambiguates with >Name-Realm", function()
                local result = resolve({
                    retail("Thrall", "Area52"),
                    retail("Thrall", "Stormrage"),
                    retail("Jaina", "Area52", ">Thrall-Stormrage"),
                })
                assert.are.equal("G-Thrall-Stormrage", result.charToPerson["Jaina-Area52"])
                assert.are.same({}, result.issues)
            end)

            it("flags a plain name that exists on two realms as ambiguous", function()
                local result = resolve({
                    retail("Thrall", "Area52"), retail("Thrall", "Stormrage"), retail("Jaina", "Area52", ">Thrall"),
                })
                assert.are.equal("G-Jaina-Area52", result.charToPerson["Jaina-Area52"])
                local issue = result.issues[1]
                assert.are.equal("ambiguous", issue.type)
                assert.truthy(issue.fix:find("Thrall-Area52, Thrall-Stormrage", 1, true))
            end)

            it("ignores the realm when matching otherwise", function()
                local result = resolve({ retail("Thrall", "Area52"), retail("Jaina", "Stormrage", ">Thrall") })
                assert.are.equal("G-Thrall-Area52", result.charToPerson["Jaina-Stormrage"])
            end)

            it("adds the realm to a short name only when the name is still ambiguous", function()
                local result = resolve({
                    retail("Thrall", "Area52"), retail("Thrall", "Stormrage"), retail("Jaina Proudmoore", "Area52"),
                })
                assert.are.equal("Thrall-Area52", result.persons["G-Thrall-Area52"].shortName)
                assert.are.equal("Jaina", result.persons["G-Jaina Proudmoore-Area52"].shortName)
            end)
        end)

        it("never shows a realm on Forever", function()
            local result = resolve({ member("Dresden Zelwindran"), member("Dresden Other"), member("Solo") })
            for _, person in pairs(result.persons) do
                assert.is_nil(person.shortName:find("Forever", 1, true))
                assert.is_nil(person.displayName:find("Forever", 1, true))
            end
        end)

        it("gives the same issues regardless of roster order", function()
            local roster = {
                member("Anna", ">Bert"), member("Bert", ">Anna"), member("Malgen", ">Nobody"), member("X", ">Y"),
            }
            local reversed = { roster[4], roster[3], roster[2], roster[1] }
            assert.are.same(resolve(roster), resolve(reversed))
        end)
    end)
end)
