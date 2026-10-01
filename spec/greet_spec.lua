local Harness = require("support.wow")

local ns = Harness.new():loadAll({ "Core/GreetTracker.lua", "Core/GreetComposer.lua" })
local GreetTracker, GreetComposer = ns.GreetTracker, ns.GreetComposer

-- Dresden and Malgen are one person ("P-D"); Kira is "P-K"; Me is "P-ME".
local PEOPLE = { Dresden = "P-D", Malgen = "P-D", Kira = "P-K", Me = "P-ME" }
local function personOf(key)
    return PEOPLE[key]
end

local function roster(onlineNames)
    local online = {}
    for _, name in ipairs(onlineNames) do
        online[name] = true
    end
    local snapshot = {}
    for _, name in ipairs({ "Dresden", "Malgen", "Kira", "Me", "Stranger" }) do
        table.insert(snapshot, { key = name, name = name, online = online[name] == true })
    end
    return snapshot
end

local function ids(arrivals)
    local result = {}
    for _, arrival in ipairs(arrivals) do
        table.insert(result, arrival.personId)
    end
    return result
end

describe("GreetTracker", function()
    local tracker
    local function observe(onlineNames, now)
        return ids(tracker:Observe(roster(onlineNames), personOf, now, "P-ME"))
    end

    before_each(function()
        tracker = GreetTracker.New()
    end)

    it("treats the first snapshot as a baseline", function()
        assert.are.same({}, observe({ "Dresden", "Kira" }, 0))
    end)

    it("reports a person who comes online", function()
        observe({}, 0)
        assert.are.same({ "P-K" }, observe({ "Kira" }, 10))
    end)

    it("reports someone arriving on any of their characters once, as one person", function()
        observe({}, 0)
        assert.are.same({ "P-D" }, observe({ "Dresden", "Malgen" }, 10))
    end)

    it("ignores an alt switch", function()
        observe({ "Dresden" }, 0)
        assert.are.same({}, observe({ "Malgen" }, 10))
    end)

    it("ignores a relog within the return window", function()
        observe({ "Kira" }, 0)
        observe({}, 100)
        assert.are.same({}, observe({ "Kira" }, GreetTracker.RETURN_WINDOW - 1))
    end)

    it("reports a return after the window", function()
        observe({ "Kira" }, 0)
        observe({}, 100)
        assert.are.same({ "P-K" }, observe({ "Kira" }, 100 + GreetTracker.RETURN_WINDOW))
    end)

    it("measures the window from when they were last seen online", function()
        observe({ "Kira" }, 0)
        observe({ "Kira" }, 5000)
        observe({}, 5010)
        assert.are.same({}, observe({ "Kira" }, 5000 + GreetTracker.RETURN_WINDOW - 1))
    end)

    it("never reports the player themselves", function()
        observe({}, 0)
        assert.are.same({}, observe({ "Me" }, 10))
    end)

    it("tracks characters identity doesn't know by their own key", function()
        observe({}, 0)
        local arrivals = tracker:Observe(roster({ "Stranger" }), personOf, 10, "P-ME")
        assert.are.equal("Stranger", arrivals[1].personId)
        assert.are.equal("Stranger", arrivals[1].member.name)
    end)

    it("starts a new baseline after Reset", function()
        observe({}, 0)
        tracker:Reset()
        assert.are.same({}, observe({ "Kira" }, 10))
        assert.are.same({}, observe({ "Kira" }, 20))
    end)
end)

describe("GreetComposer", function()
    local function first()
        return 1
    end

    it("fills {name} with the person's name", function()
        assert.are.equal("Welcome back, Zel!", GreetComposer.Compose({ "Zel" }, { "Welcome back, {name}!" }, first))
    end)

    it("appends the name to a template without {name}", function()
        assert.are.equal("Welcome back! Zel", GreetComposer.Compose({ "Zel" }, { "Welcome back!" }, first))
    end)

    it("falls back to the built-in templates", function()
        assert.are.equal("Welcome back, Zel!", GreetComposer.Compose({ "Zel" }, nil, first))
        assert.are.equal("Welcome back, Zel!", GreetComposer.Compose({ "Zel" }, {}, first))
        assert.is_true(#GreetComposer.DEFAULT_RETURN > 1)
    end)

    it("uses the random function to pick a template", function()
        local templates = { "A {name}", "B {name}", "C {name}" }
        assert.are.equal("C Zel", GreetComposer.Compose({ "Zel" }, templates, function(n)
            return n
        end))
    end)

    it("keeps % signs in names literal", function()
        assert.are.equal("Hi 100%!", GreetComposer.Compose({ "100%" }, { "Hi {name}!" }, first))
    end)

    it("joins two names", function()
        assert.are.equal("Zel and Kira", GreetComposer.JoinNames({ "Zel", "Kira" }))
    end)
end)
