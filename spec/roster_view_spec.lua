local Harness = require("support.wow")
local FakeLibs = require("support.fake_libs")

local function member(name, fields)
    local entry = { key = name .. "-Forever", name = name, note = "", guid = "G-" .. name, online = false,
        level = 60, class = "WARRIOR", className = "Warrior", zone = "" }
    for key, value in pairs(fields or {}) do
        entry[key] = value
    end
    return entry
end

-- Final: Dresden (main, offline) + Shiro (online in Elwynn) + Malgen (offline).
-- Bob: Bob (main) + Bobadin, all offline. Sarah: online on her main.
local function roster()
    return {
        member("Dresden", { className = "Mage", note = "@Final" }),
        member("Shiro", { level = 34, className = "Paladin", note = ">Dresden", online = true,
            zone = "Elwynn Forest" }),
        member("Malgen", { level = 20, note = ">Dresden" }),
        member("Bob", { className = "Hunter" }),
        member("Bobadin", { level = 45, className = "Paladin", note = ">Bob" }),
        member("Sarah", { className = "Priest", online = true }),
    }
end

local function setup(snapshot)
    local ns = Harness.new({ globals = { LibStub = FakeLibs.new() } }):loadAll({
        "Core/Compat.lua",
        "Core/NoteCodec.lua",
        "Core/IdentityResolver.lua",
        "Core/IdentityStore.lua",
        "Core/Availability.lua",
        "Core/Helping.lua",
        "Core/RosterView.lua",
    })
    local store = ns.IdentityStore.New({})
    store:Update(snapshot or roster())
    local availability = ns.Availability.New(store, function()
        return 1000
    end)
    return ns, store, availability
end

local function names(view)
    local result = {}
    for _, entry in ipairs(view.people) do
        table.insert(result, entry.name)
    end
    return result
end

describe("RosterView.Build", function()
    it("groups characters by person, main first, online people first then by name", function()
        local ns, store, availability = setup()
        local view = ns.RosterView.Build(store, availability)
        assert.are.same({ "Final", "Sarah", "Bob" }, names(view))
        local final = view.people[1]
        assert.are.equal("G-Dresden", final.personId)
        assert.are.equal("Final", final.alias)
        assert.is_true(final.online)
        assert.are.equal("Shiro", final.current.name)
        assert.are.equal(3, #final.characters)
        assert.are.equal("Dresden", final.characters[1].name)
        assert.is_true(final.characters[1].isMain)
        assert.is_false(final.characters[2].isMain)
        assert.is_false(view.people[3].online)
        assert.is_nil(view.people[3].current)
    end)

    it("counts people and characters online", function()
        local ns, store, availability = setup()
        local view = ns.RosterView.Build(store, availability)
        assert.are.equal(2, view.onlinePeople)
        assert.are.equal(3, view.totalPeople)
        assert.are.equal(2, view.onlineCharacters)
        assert.are.equal("2 of 3 people online (2 characters)", ns.RosterView.Summary(view))
        assert.are.equal("0 of 1 person online (1 character)", ns.RosterView.Summary({ onlinePeople = 0,
            totalPeople = 1, onlineCharacters = 1 }))
    end)

    it("shows each person's availability", function()
        local ns, store, availability = setup()
        availability:Set("Shiro-Forever", "dungeons")
        local view = ns.RosterView.Build(store, availability)
        assert.are.equal("dungeons", view.people[1].status)
        assert.are.equal("none", view.people[2].status)
        assert.are.equal("none", ns.RosterView.Build(store, nil).people[1].status)
    end)
end)

describe("RosterView options", function()
    it("searches by character name, first name, Name-Realm, or alias, like /gf who", function()
        local ns, store, availability = setup()
        local function search(query)
            return names(ns.RosterView.Build(store, availability, { query = query }))
        end
        assert.are.same({ "Final" }, search("malgen"))
        assert.are.same({ "Final" }, search("  FINAL "))
        assert.are.same({ "Bob" }, search("Bobadin-Forever"))
        assert.are.same({ "Bob" }, search('"bob"'))
        assert.are.same({}, search("nobody"))
        assert.are.same({ "Final", "Sarah", "Bob" }, search(""))
        assert.are.same({ "Final", "Sarah", "Bob" }, search("   "))
    end)

    it("hides offline people when asked, keeping whole-guild counts", function()
        local ns, store, availability = setup()
        local view = ns.RosterView.Build(store, availability, { showOffline = false })
        assert.are.same({ "Final", "Sarah" }, names(view))
        assert.are.equal(3, view.totalPeople)
        assert.are.equal(2, view.onlinePeople)
        local searched = ns.RosterView.Build(store, availability, { query = "bob", showOffline = false })
        assert.are.same({}, names(searched))
        assert.are.equal(3, searched.totalPeople)
    end)
end)

describe("RosterView helping topics", function()
    local PROFILES = { ["G-Dresden"] = { helps = "tanking,quests" }, ["G-Bob"] = { helps = "quests" } }
    local function profileOf(personId)
        return PROFILES[personId]
    end

    it("shows what each person helps with", function()
        local ns, store, availability = setup()
        local view = ns.RosterView.Build(store, availability, { profileOf = profileOf })
        assert.are.same({ "Tanking", "Quests" }, view.people[1].helps)
        assert.are.same({}, view.people[2].helps)
        assert.are.equal("Final · online as Shiro (Elwynn Forest) · Helps with: Tanking, Quests",
            ns.RosterView.Lines(view.people[1])[1])
    end)

    it("keeps only people who help with a topic, online or not, with whole-guild counts", function()
        local ns, store, availability = setup()
        local view = ns.RosterView.Build(store, availability, { profileOf = profileOf, helps = "quests" })
        assert.are.same({ "Final", "Bob" }, names(view))
        assert.are.equal(3, view.totalPeople)
        local online = ns.RosterView.Build(store, availability,
            { profileOf = profileOf, helps = "quests", showOffline = false })
        assert.are.same({ "Final" }, names(online))
        assert.are.same({}, names(ns.RosterView.Build(store, availability, { profileOf = profileOf, helps = "pvp" })))
        assert.are.same({}, names(ns.RosterView.Build(store, availability, { helps = "quests" })))
    end)
end)

describe("RosterView.Lines", function()
    it("describes an online person, marking the characters they're not on", function()
        local ns, store, availability = setup()
        availability:Set("Shiro-Forever", "dungeons")
        local final = ns.RosterView.Build(store, availability).people[1]
        assert.are.same({
            "Final · online as Shiro (Elwynn Forest) · Up for Dungeons",
            "    Dresden — Mage 60 (main, offline) · Malgen — Warrior 20 (offline) · Shiro — Paladin 34",
        }, ns.RosterView.Lines(final))
    end)

    it("describes an offline person without marking every character", function()
        local ns, store, availability = setup()
        local bob = ns.RosterView.Build(store, availability).people[3]
        assert.are.same({ "Bob · offline", "    Bob — Hunter 60 (main) · Bobadin — Paladin 45" },
            ns.RosterView.Lines(bob))
    end)

    it("leaves out an empty zone and labels Busy", function()
        local ns, store, availability = setup()
        availability:Set("Sarah-Forever", "busy")
        local sarah = ns.RosterView.Build(store, availability).people[2]
        assert.are.equal("Sarah · online as Sarah · Busy", ns.RosterView.Lines(sarah)[1])
    end)
end)
