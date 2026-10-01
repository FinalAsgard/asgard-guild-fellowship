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

    local function lines(names, templates, random, previous)
        return (GreetComposer.Lines(names, templates, random or first, previous))
    end

    it("fills {name} with the person's name", function()
        assert.are.same({ "Welcome back, Zel!" }, lines({ "Zel" }, { "Welcome back, {name}!" }))
    end)

    it("appends the names to a template without {name}", function()
        assert.are.same({ "Welcome back! Zel and Kira" }, lines({ "Zel", "Kira" }, { "Welcome back!" }))
    end)

    it("joins names naturally", function()
        assert.are.equal("Zel", GreetComposer.JoinNames({ "Zel" }))
        assert.are.equal("Zel and Kira", GreetComposer.JoinNames({ "Zel", "Kira" }))
        assert.are.equal("Zel, Kira and Mike", GreetComposer.JoinNames({ "Zel", "Kira", "Mike" }))
        assert.are.same({ "Hi Zel, Kira and Mike!" }, lines({ "Zel", "Kira", "Mike" }, { "Hi {name}!" }))
    end)

    it("falls back to the built-in templates when none are usable", function()
        assert.are.same({ "Welcome back, Zel!" }, lines({ "Zel" }, nil))
        assert.are.same({ "Welcome back, Zel!" }, lines({ "Zel" }, {}))
        assert.are.same({ "Welcome back, Zel!" }, lines({ "Zel" }, { "   ", "|" }))
        assert.is_true(#GreetComposer.DEFAULT_RETURN > 1)
    end)

    it("cleans templates", function()
        assert.are.same({ "Hi {name}!", "Yo", "ab" },
            GreetComposer.Clean({ "  Hi {name}!  ", "", "|cff00ff00Yo|r\n", 5, "\t", "a|b" }))
    end)

    it("drops messages too long to leave room for names under the chat limit", function()
        local long = string.rep("x", GreetComposer.MAX_TEMPLATE + 1)
        local fits = string.rep("y", GreetComposer.MAX_TEMPLATE)
        assert.are.same({ fits }, GreetComposer.Clean({ long, fits }))
        assert.are.same({ "Welcome back, Zel!" }, lines({ "Zel" }, { long }))
        local result = lines({ "Dresden Zelwindran" }, { fits .. " {name}" })
        assert.are.same({ "Welcome back, Dresden Zelwindran!" }, result)
        local maxed = lines({ "Dresden Zelwindran" }, { string.rep("z", GreetComposer.MAX_TEMPLATE - 7) .. " {name}" })
        assert.is_true(#maxed[1] <= GreetComposer.MAX_LINE)
    end)

    it("drops messages that use {name} more than once", function()
        local repeated = string.rep("{name} ", 20)
        assert.are.equal("Use {name} at most once per message.", GreetComposer.Problem(repeated))
        assert.is_nil(GreetComposer.Problem("Hi {name}!"))
        assert.are.same({ "Hi {name}!" }, GreetComposer.Clean({ repeated, "Hi {name}!" }))
        local result = lines({ "Dresden Zelwindran" }, { repeated })
        assert.is_true(#result[1] <= GreetComposer.MAX_LINE)
    end)

    it("keeps % signs in names literal", function()
        assert.are.same({ "Hi 100%!" }, lines({ "100%" }, { "Hi {name}!" }))
    end)

    describe("variety", function()
        local templates = { "A {name}", "B {name}", "C {name}" }

        it("never repeats the previous template", function()
            for previous = 1, 3 do
                for roll = 1, 2 do
                    local _, index = GreetComposer.Lines({ "Zel" }, templates, function()
                        return roll
                    end, previous)
                    assert.are_not.equal(previous, index)
                end
            end
        end)

        it("can pick every other template", function()
            local seen = {}
            for roll = 1, 2 do
                local _, index = GreetComposer.Lines({ "Zel" }, templates, function()
                    return roll
                end, 2)
                seen[index] = true
            end
            assert.are.same({ [1] = true, [3] = true }, seen)
        end)

        it("allows a single template to repeat", function()
            local result, index = GreetComposer.Lines({ "Zel" }, { "Only {name}" }, first, 1)
            assert.are.same({ "Only Zel" }, result)
            assert.are.equal(1, index)
        end)
    end)

    describe("long batches", function()
        local function many(count)
            local names = {}
            for i = 1, count do
                names[i] = ("Adventurer%02d"):format(i)
            end
            return names
        end

        it("splits into several lines within the chat limit, keeping every name whole", function()
            local names = many(30)
            local result = lines(names, { "Welcome back, {name}!" })
            assert.is_true(#result > 1)
            local found = {}
            for _, line in ipairs(result) do
                assert.is_true(#line <= GreetComposer.MAX_LINE, line)
                assert.are.equal("Welcome back, ", line:sub(1, 14))
                for name in line:gmatch("Adventurer%d%d") do
                    table.insert(found, name)
                end
            end
            assert.are.same(names, found)
        end)

        it("uses one template for every line of a batch", function()
            local result = lines(many(30), { "Hi {name}!", "Hey {name}!" }, function()
                return 2
            end)
            for _, line in ipairs(result) do
                assert.are.equal("Hey ", line:sub(1, 4))
            end
        end)
    end)
end)
