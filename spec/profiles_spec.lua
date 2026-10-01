local Harness = require("support.wow")
local FakeLibs = require("support.fake_libs")

local function member(name, note)
    return { key = name .. "-Forever", name = name, note = note or "", guid = "G-" .. name }
end

-- Dresden's person: Dresden Zelwindran (main) + Malgen. Kira is someone else.
local ROSTER = { member("Dresden Zelwindran"), member("Malgen", ">Dresden"), member("Kira"), member("Officer") }

local function load()
    local LibStub = FakeLibs.new()
    return Harness.new({ globals = { LibStub = LibStub } }):loadAll({
        "Core/NoteCodec.lua",
        "Core/IdentityResolver.lua",
        "Core/IdentityStore.lua",
        "Core/Profiles.lua",
        "Core/SyncMerge.lua",
    })
end

local function setup(roster, guildData)
    local ns = load()
    local store = ns.IdentityStore.New(guildData or {})
    store:Update(roster or ROSTER)
    local profiles = ns.Profiles.New(store.data, store, function(key)
        return key == "Officer-Forever"
    end, function()
        return 0
    end)
    return profiles, store, ns
end

describe("Profiles", function()
    it("cleans field values", function()
        local Profiles = load().Profiles
        assert.are.equal("Zel cff #1", Profiles.Clean("  Zel\n|cff #1  "))
        assert.is_nil(Profiles.Clean("   "))
        assert.is_nil(Profiles.Clean(nil))
    end)

    it("saves a profile for the person, editable from any of their characters", function()
        local profiles, store = setup()
        assert.is_true(profiles:Save("Malgen-Forever", { discord = "zel", bio = "Hi there" }))
        assert.is_true(profiles:Save("Dresden Zelwindran-Forever", { bio = "Updated" }))
        local profile = profiles:Get(store:GetPerson("Malgen-Forever").id)
        assert.are.same({ version = 2, author = "Dresden Zelwindran-Forever", discord = "zel", bio = "Updated" },
            profile)
    end)

    it("clears a field saved as empty", function()
        local profiles = setup()
        profiles:Save("Malgen-Forever", { discord = "zel" })
        profiles:Save("Malgen-Forever", { discord = "" })
        assert.is_nil(profiles:Get("G-Dresden Zelwindran").discord)
    end)

    it("refuses unknown characters and over-long fields", function()
        local profiles = setup()
        assert.are.same({ false, "unknown character" }, { profiles:Save("Stranger-Forever", { bio = "x" }) })
        assert.are.same({ false, "bio is too long" }, { profiles:Save("Kira-Forever", { bio = string.rep("x", 201) }) })
        assert.is_true(profiles:Save("Kira-Forever", { bio = string.rep("x", 200) }))
    end)

    it("stores profiles in the guild's data and fires ProfileChanged", function()
        local guildData = {}
        local profiles = setup(nil, guildData)
        local seen
        profiles.RegisterCallback({}, "ProfileChanged", function(_, personId)
            seen = personId
        end)
        profiles:Save("Kira-Forever", { bio = "x" })
        assert.are.equal("G-Kira", seen)
        assert.are.equal("x", guildData.profiles["G-Kira"].bio)
    end)

    describe("alias precedence", function()
        it("uses the profile alias fallback when the note has no @Alias", function()
            local profiles, store = setup()
            profiles:Save("Malgen-Forever", { aliasFallback = "Zel" })
            local person = store:GetPerson("Malgen-Forever")
            assert.are.equal("Zel", person.alias)
            assert.are.equal("Zel", person.displayName)
        end)

        it("lets the note's @Alias win over the profile", function()
            local roster = { member("Dresden Zelwindran", "@Drez"), member("Malgen", ">Dresden") }
            local profiles, store = setup(roster)
            profiles:Save("Malgen-Forever", { aliasFallback = "Zel" })
            assert.are.equal("Drez", store:GetPerson("Malgen-Forever").displayName)
        end)

        it("has no alias without either", function()
            local _, store = setup()
            assert.is_nil(store:GetPerson("Malgen-Forever").alias)
        end)
    end)

    describe("Discord name is contact info only", function()
        it("is never the alias, display name, or short name", function()
            local profiles, store = setup()
            profiles:Save("Malgen-Forever", { discord = "zelly" })
            local person = store:GetPerson("Malgen-Forever")
            assert.is_nil(person.alias)
            assert.are.equal("Dresden", person.displayName)
            assert.are.equal("Dresden", person.shortName)
        end)

        it("is not a search key", function()
            local profiles, store = setup()
            profiles:Save("Malgen-Forever", { discord = "zelly" })
            assert.are.same({}, store:FindByQuery("zelly"))
        end)

        it("is not used for matching notes", function()
            local roster = { member("Dresden Zelwindran"), member("Malgen", ">zelly") }
            local profiles, store = setup(roster)
            profiles:Save("Dresden Zelwindran-Forever", { discord = "zelly" })
            assert.are.equal("G-Malgen", store:GetPerson("Malgen-Forever").id)
        end)
    end)

    describe("sync handler", function()
        it("shares profiles by person and accepts a newer one from the person's own character", function()
            local profiles, store = setup()
            local handler = profiles:SyncHandler()
            assert.are.same({}, handler.Versions())
            local changed
            profiles.RegisterCallback({}, "ProfileChanged", function(_, personId)
                changed = personId
            end)
            assert.is_true(handler.Receive("G-Dresden Zelwindran",
                { version = 4, author = "Malgen-Forever", aliasFallback = "Zel|r" }, "Malgen-Forever"))
            handler.Commit()
            assert.are.equal("G-Dresden Zelwindran", changed)
            assert.are.same({ ["G-Dresden Zelwindran"] = 4 }, handler.Versions())
            assert.are.equal("Zel r", store:GetPerson("Malgen-Forever").displayName)
        end)

        it("rejects an impersonation attempt", function()
            local profiles = setup()
            local handler = profiles:SyncHandler()
            assert.is_false(handler.Receive("G-Dresden Zelwindran",
                { version = 1, author = "Kira-Forever", bio = "I am Dresden" }, "Kira-Forever"))
            assert.is_nil(profiles:Get("G-Dresden Zelwindran"))
        end)
    end)
end)

describe("Profiles versions", function()
    it("uses the server time so a fresh install's edit beats older versions", function()
        local ns = load()
        local store = ns.IdentityStore.New({})
        store:Update(ROSTER)
        local clock = 1000
        local profiles = ns.Profiles.New(store.data, store, function()
            return false
        end, function()
            return clock
        end)
        profiles:Save("Kira-Forever", { bio = "a" })
        assert.are.equal(1000, profiles:Get("G-Kira").version)
        profiles:Save("Kira-Forever", { bio = "b" })
        assert.are.equal(1001, profiles:Get("G-Kira").version)
        clock = 5000
        profiles:Save("Kira-Forever", { bio = "c" })
        assert.are.equal(5000, profiles:Get("G-Kira").version)
    end)
end)

describe("SyncMerge.Profile", function()
    local ns = load()
    local PEOPLE = {
        ["Dresden Zelwindran-Forever"] = "G-D", ["Malgen-Forever"] = "G-D", ["Kira-Forever"] = "G-K",
        ["Officer-Forever"] = "G-O",
    }
    local function personOf(key)
        return PEOPLE[key]
    end
    local function trusted(key)
        return key == "Officer-Forever"
    end
    local function check(record, sender, current)
        return { ns.SyncMerge.Profile("G-D", record, current, sender, personOf, trusted) }
    end

    it("accepts a newer profile written and sent by the person's own characters", function()
        assert.are.same({ true }, check({ version = 1, author = "Malgen-Forever", bio = "hi" }, "Malgen-Forever"))
        assert.are.same({ true }, check({ version = 2, author = "Malgen-Forever" }, "Dresden Zelwindran-Forever",
            { version = 1 }))
    end)

    it("rejects an impersonation attempt by another person", function()
        assert.are.same({ false, "not their character" },
            check({ version = 1, author = "Kira-Forever", bio = "I am Dresden" }, "Kira-Forever"))
    end)

    it("rejects a profile relayed by someone who isn't trusted", function()
        assert.are.same({ false, "untrusted relay" }, check({ version = 1, author = "Malgen-Forever" }, "Kira-Forever"))
    end)

    it("accepts a profile relayed by an addon officer", function()
        assert.are.same({ true }, check({ version = 1, author = "Malgen-Forever" }, "Officer-Forever"))
    end)

    it("rejects a profile that isn't newer", function()
        assert.are.same({ false, "not newer" },
            check({ version = 2, author = "Malgen-Forever" }, "Malgen-Forever", { version = 2 }))
    end)

    it("rejects an author who has since left the person", function()
        assert.are.same({ false, "not their character" },
            check({ version = 1, author = "Gone-Forever" }, "Officer-Forever"))
    end)

    it("rejects malformed records and over-long fields", function()
        for _, record in ipairs({
            "text", {}, { version = "1", author = "Malgen-Forever" }, { version = 1 },
            { version = 1, author = "Malgen-Forever", bio = 5 },
            { version = 1, author = "Malgen-Forever", discord = string.rep("x", 33) },
        }) do
            assert.are.same({ false, "malformed" }, check(record, "Malgen-Forever"))
        end
        assert.are.same({ false, "malformed" },
            { ns.SyncMerge.Profile(nil, { version = 1, author = "Malgen-Forever" }, nil, "Malgen-Forever", personOf,
                trusted) })
    end)
end)
