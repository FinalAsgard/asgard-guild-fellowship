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

-- Me: Brokk (level 34, online). Mike: Magus (60 Mage, online) with an offline
-- alt Tanky (34 Warrior). Kira: online at 36. Zed: online at 50. Olaf: offline
-- at 34. Busy Bea: online at 34.
local function roster()
    return {
        member("Brokk", { level = 34, online = true, zone = "Duskwood" }),
        member("Magus", { level = 60, class = "MAGE", className = "Mage", online = true, zone = "Orgrimmar" }),
        member("Tanky", { level = 34, note = ">Magus" }),
        member("Kira", { level = 36, class = "PRIEST", className = "Priest", online = true, zone = "Duskwood" }),
        member("Zed", { level = 50, online = true }),
        member("Olaf", { level = 34 }),
        member("Bea", { level = 34, online = true }),
    }
end

local function load()
    local LibStub = FakeLibs.new()
    return Harness.new({ globals = { LibStub = LibStub } }):loadAll({
        "Core/Compat.lua",
        "Core/NoteCodec.lua",
        "Core/IdentityResolver.lua",
        "Core/IdentityStore.lua",
        "Core/Availability.lua",
        "Core/SyncMerge.lua",
        "Core/Discovery.lua",
    })
end

local function setup(snapshot)
    local ns = load()
    local store = ns.IdentityStore.New({})
    store:Update(snapshot or roster())
    local availability = ns.Availability.New(store, function()
        return 1000
    end)
    return ns, store, availability
end

local ME = { personId = "G-Brokk", level = 34 }

local function names(people)
    local result = {}
    for _, entry in ipairs(people) do
        table.insert(result, entry.name)
    end
    return result
end

describe("Discovery.Matches", function()
    it("matches levels within the range either side", function()
        local Discovery = load().Discovery
        assert.is_true(Discovery.Matches(31, 34, 3))
        assert.is_true(Discovery.Matches(37, 34, 3))
        assert.is_false(Discovery.Matches(38, 34, 3))
        assert.is_false(Discovery.Matches(nil, 34, 3))
    end)

    it("only matches capped characters at the level cap", function()
        local Discovery = load().Discovery
        assert.is_true(Discovery.Matches(80, 80, 3, 80))
        assert.is_false(Discovery.Matches(79, 80, 3, 80))
        assert.is_true(Discovery.Matches(77, 78, 3, 80))
    end)
end)

describe("Discovery.Build", function()
    it("lists online people other than me, with their characters in level range", function()
        local ns, store, availability = setup()
        local people = ns.Discovery.Build(store, availability, ME)
        assert.are.same({ "Bea", "Kira", "Magus", "Zed" }, names(people))
        local mike = people[3]
        assert.are.equal("G-Magus", mike.personId)
        assert.are.equal("Magus", mike.character.name)
        assert.are.equal("Orgrimmar", mike.zone)
        assert.are.equal(1, #mike.matching)
        assert.are.same({ key = "Tanky-Forever", name = "Tanky", level = 34, class = "WARRIOR",
            className = "Warrior", online = false, zone = "", roles = {} }, mike.matching[1])
        assert.are.same({}, people[4].matching)
    end)

    it("leaves out people with nobody online and me", function()
        local ns, store, availability = setup()
        for _, entry in ipairs(ns.Discovery.Build(store, availability, ME)) do
            assert.are_not.equal("G-Olaf", entry.personId)
            assert.are_not.equal("G-Brokk", entry.personId)
        end
    end)

    it("hides people who set Busy unless asked to show them", function()
        local ns, store, availability = setup()
        availability:Set("Bea-Forever", "busy")
        assert.are.same({ "Kira", "Magus", "Zed" }, names(ns.Discovery.Build(store, availability, ME)))
        local shown = ns.Discovery.Build(store, availability, ME, { showBusy = true })
        assert.are.same({ "Kira", "Magus", "Zed", "Bea" }, names(shown))
    end)

    it("puts people up for something first and Busy last, then level matches, then names", function()
        local ns, store, availability = setup()
        availability:Set("Zed-Forever", "anything")
        availability:Set("Tanky-Forever", "dungeons")
        local people = ns.Discovery.Build(store, availability, ME)
        assert.are.same({ "Magus", "Zed", "Bea", "Kira" }, names(people))
        assert.are.equal("dungeons", people[1].status)
        assert.are.equal("none", people[3].status)
    end)

    it("uses the range it is given and the level cap", function()
        local ns, store, availability = setup()
        local wide = ns.Discovery.Build(store, availability, ME, { range = 20 })
        assert.are.equal(1, #wide[#wide].matching)
        local capped = ns.Discovery.Build(store, availability, { personId = "G-Brokk", level = 60 },
            { maxLevel = 60 })
        local magus
        for _, entry in ipairs(capped) do
            if entry.personId == "G-Magus" then
                magus = entry
            end
        end
        assert.are.equal(1, #magus.matching)
        assert.are.equal("Magus", magus.matching[1].name)
    end)

    it("shows the person's display name from identity", function()
        local snapshot = roster()
        snapshot[2].note = "@Mike"
        local ns, store, availability = setup(snapshot)
        local names_ = names(ns.Discovery.Build(store, availability, ME))
        assert.are.same({ "Bea", "Kira", "Mike", "Zed" }, names_)
    end)

    it("works without availability", function()
        local ns, store = setup()
        assert.are.equal(4, #ns.Discovery.Build(store, nil, ME))
    end)
end)

describe("Discovery filters and roles", function()
    local function rolesOf(ns)
        return function(class)
            return ns.Compat.ClassRoles(class)
        end
    end

    it("hints each character's roles from its class", function()
        local ns, store, availability = setup()
        local people = ns.Discovery.Build(store, availability, ME, { rolesOf = rolesOf(ns) })
        local kira = people[2]
        assert.are.equal("G-Kira", kira.personId)
        assert.are.same({ tank = false, heal = true }, kira.character.roles)
        assert.are.same({ tank = true, heal = false }, people[3].matching[1].roles)
    end)

    it("keeps only people with the chosen status", function()
        local ns, store, availability = setup()
        availability:Set("Kira-Forever", "dungeons")
        availability:Set("Zed-Forever", "pvp")
        assert.are.same({ "Kira" }, names(ns.Discovery.Build(store, availability, ME, { status = "dungeons" })))
        availability:Set("Bea-Forever", "busy")
        assert.are.same({ "Bea" }, names(ns.Discovery.Build(store, availability, ME, { status = "busy" })))
    end)

    it("keeps only people in my zone", function()
        local ns, store, availability = setup()
        assert.are.same({ "Kira" }, names(ns.Discovery.Build(store, availability, ME, { zone = "Duskwood" })))
    end)

    it("keeps only people with a character in level range that can fill the role", function()
        local ns, store, availability = setup()
        local options = { rolesOf = rolesOf(ns), role = "heal" }
        assert.are.same({ "Kira" }, names(ns.Discovery.Build(store, availability, ME, options)))
        options.role = "tank"
        -- Bea and Tanky (Mike's alt) are warriors at 34; Zed is a warrior out of range.
        assert.are.same({ "Bea", "Magus" }, names(ns.Discovery.Build(store, availability, ME, options)))
    end)

    it("combines filters", function()
        local ns, store, availability = setup()
        availability:Set("Bea-Forever", "busy")
        local options = { rolesOf = rolesOf(ns), role = "tank", showBusy = true, status = "busy" }
        assert.are.same({ "Bea" }, names(ns.Discovery.Build(store, availability, ME, options)))
        options.zone = "Duskwood"
        assert.are.same({}, names(ns.Discovery.Build(store, availability, ME, options)))
    end)
end)

describe("Discovery.Lines", function()
    it("labels characters that can tank or heal", function()
        local ns, store, availability = setup()
        local options = { rolesOf = function(class) return ns.Compat.ClassRoles(class) end }
        local mike = ns.Discovery.Build(store, availability, ME, options)[3]
        assert.are.same({
            "Magus — Magus, Mage 60 · Orgrimmar",
            "    At your level: Tanky, Warrior 34 [Tank] (offline)",
        }, ns.Discovery.Lines(mike))
    end)

    it("describes the character they're on, their status, zone, and level matches", function()
        local ns, store, availability = setup()
        availability:Set("Magus-Forever", "dungeons")
        local mike = ns.Discovery.Build(store, availability, ME)[1]
        assert.are.same({
            "Magus — Magus, Mage 60 · Up for Dungeons · Orgrimmar",
            "    At your level: Tanky, Warrior 34 (offline)",
        }, ns.Discovery.Lines(mike))
    end)

    it("leaves out what isn't known", function()
        local ns, store, availability = setup()
        local zed
        for _, entry in ipairs(ns.Discovery.Build(store, availability, ME)) do
            if entry.personId == "G-Zed" then
                zed = entry
            end
        end
        assert.are.same({ "Zed — Zed, Warrior 50" }, ns.Discovery.Lines(zed))
    end)

    it("labels Busy without 'Up for'", function()
        local ns, store, availability = setup()
        availability:Set("Bea-Forever", "busy")
        local bea = ns.Discovery.Build(store, availability, ME, { showBusy = true })[4]
        assert.are.equal("Bea — Bea, Warrior 34 · Busy", ns.Discovery.Lines(bea)[1])
    end)
end)
