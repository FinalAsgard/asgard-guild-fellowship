local Harness = require("support.wow")
local FakeLibs = require("support.fake_libs")

local function member(name, note, online)
    return { key = name .. "-Forever", name = name, note = note or "", guid = "G-" .. name, online = online }
end

-- Dresden's person: Dresden Zelwindran (main, offline) + Malgen (online). Kira
-- is someone else, online. Lonely is offline.
local function roster()
    return {
        member("Dresden Zelwindran", "", false),
        member("Malgen", ">Dresden", true),
        member("Kira", "", true),
        member("Lonely", "", false),
    }
end

local function load()
    local LibStub = FakeLibs.new()
    return Harness.new({ globals = { LibStub = LibStub } }):loadAll({
        "Core/NoteCodec.lua",
        "Core/IdentityResolver.lua",
        "Core/IdentityStore.lua",
        "Core/Profiles.lua",
        "Core/Availability.lua",
        "Core/SyncMerge.lua",
    })
end

local function setup(shared)
    local ns = load()
    local clock = { now = 1000 }
    local store = ns.IdentityStore.New({})
    store:Update(roster())
    local availability = ns.Availability.New(store, function()
        return clock.now
    end, shared)
    return availability, store, clock, ns
end

local TTL = 2 * 60 * 60

describe("Availability", function()
    it("sets a status for the person, from any of their characters", function()
        local availability = setup()
        assert.are.equal("G-Dresden Zelwindran", availability:Set("Malgen-Forever", "dungeons"))
        assert.are.equal("dungeons", availability:Get("G-Dresden Zelwindran"))
        assert.are.same({ status = "dungeons", version = 1000, setAt = 1000, expiresAt = 1000 + TTL,
            author = "Malgen-Forever" }, availability.records["G-Dresden Zelwindran"])
    end)

    it("clears a status with none", function()
        local availability = setup()
        availability:Set("Kira-Forever", "pvp")
        availability:Set("Kira-Forever", "none")
        assert.are.equal("none", availability:Get("G-Kira"))
        assert.are.equal(1001, availability.records["G-Kira"].version)
    end)

    it("refuses unknown statuses and characters", function()
        local availability = setup()
        assert.are.same({ false, "unknown status" }, { availability:Set("Kira-Forever", "raiding") })
        assert.are.same({ false, "unknown character" }, { availability:Set("Stranger-Forever", "pvp") })
        assert.are.equal("none", availability:Get("G-Kira"))
        assert.are.equal("none", availability:Get(nil))
    end)

    it("expires a status after two hours", function()
        local availability, _, clock = setup()
        availability:Set("Kira-Forever", "questing")
        clock.now = 1000 + TTL - 1
        assert.are.equal("questing", availability:Get("G-Kira"))
        clock.now = 1000 + TTL
        assert.are.equal("none", availability:Get("G-Kira"))
    end)

    it("clears a status once none of the person's characters are online", function()
        local availability, store = setup()
        availability:Set("Malgen-Forever", "helping")
        local snapshot = roster()
        snapshot[2].online = false
        store:Update(snapshot)
        assert.are.equal("none", availability:Get("G-Dresden Zelwindran"))
        assert.are.same({}, availability:SyncHandler().Versions())
        -- Pruned on the roster update, so logging back in doesn't revive it.
        availability:Prune()
        store:Update(roster())
        assert.are.equal("none", availability:Get("G-Dresden Zelwindran"))
    end)

    it("reports when the next live status lapses", function()
        local availability, _, clock = setup()
        assert.is_nil(availability:NextExpiry())
        availability:Set("Kira-Forever", "pvp")
        clock.now = 1500
        availability:Set("Malgen-Forever", "busy")
        assert.are.equal(1000 + TTL, availability:NextExpiry())
        clock.now = 1000 + TTL
        assert.are.equal(1500 + TTL, availability:NextExpiry())
    end)

    it("fires AvailabilityChanged when pruning a status that was set", function()
        local availability, _, clock = setup()
        availability:Set("Kira-Forever", "pvp")
        local fired = {}
        availability.RegisterCallback({}, "AvailabilityChanged", function(_, personId)
            table.insert(fired, personId)
        end)
        availability:Prune()
        assert.are.same({}, fired)
        clock.now = 1000 + TTL
        availability:Prune()
        assert.are.same({ "G-Kira" }, fired)
        assert.is_nil(availability.records["G-Kira"])
    end)

    it("fires AvailabilityChanged when a status is set", function()
        local availability = setup()
        local seen
        availability.RegisterCallback({}, "AvailabilityChanged", function(_, personId)
            seen = personId
        end)
        availability:Set("Kira-Forever", "anything")
        assert.are.equal("G-Kira", seen)
    end)

    describe("sync handler", function()
        it("offers only live statuses", function()
            local availability, _, clock = setup()
            availability:Set("Kira-Forever", "pvp")
            availability:Set("Malgen-Forever", "busy")
            local handler = availability:SyncHandler()
            assert.are.same({ ["G-Kira"] = 1000, ["G-Dresden Zelwindran"] = 1000 }, handler.Versions())
            assert.are.equal("pvp", handler.Get("G-Kira").status)
            clock.now = 1000 + TTL
            assert.are.same({}, handler.Versions())
            assert.is_nil(handler.Get("G-Kira"))
        end)

        it("withholds statuses the player doesn't share", function()
            local availability = setup(function(personId)
                return personId ~= "G-Kira"
            end)
            availability:Set("Kira-Forever", "pvp")
            availability:Set("Malgen-Forever", "busy")
            local handler = availability:SyncHandler()
            assert.are.same({ ["G-Dresden Zelwindran"] = 1000 }, handler.Versions())
            assert.is_nil(handler.Get("G-Kira"))
            assert.are.equal("pvp", availability:Get("G-Kira"))
        end)

        it("accepts a newer status from the person's own character and fires once per batch", function()
            local availability = setup()
            local handler = availability:SyncHandler()
            local fired = {}
            availability.RegisterCallback({}, "AvailabilityChanged", function(_, personId)
                table.insert(fired, personId)
            end)
            assert.is_true(handler.Receive("G-Kira", { status = "dungeons", version = 990, setAt = 990,
                expiresAt = 990 + TTL, author = "Kira-Forever" }))
            assert.are.same({}, fired)
            handler.Commit()
            assert.are.same({ "G-Kira" }, fired)
            assert.are.equal("dungeons", availability:Get("G-Kira"))
        end)

        it("refuses a status for someone who is offline", function()
            local availability = setup()
            local handler = availability:SyncHandler()
            assert.is_false(handler.Receive("G-Lonely", { status = "pvp", version = 990, setAt = 990,
                expiresAt = 990 + TTL, author = "Lonely-Forever" }))
            assert.is_nil(availability.records["G-Lonely"])
        end)

        it("refuses impersonation, stale and expired records", function()
            local availability = setup()
            local handler = availability:SyncHandler()
            availability:Set("Kira-Forever", "pvp")
            local function record(fields)
                local result = { status = "busy", version = 2000, setAt = 990, expiresAt = 990 + TTL,
                    author = "Kira-Forever" }
                for key, value in pairs(fields) do
                    result[key] = value
                end
                return result
            end
            assert.is_false(handler.Receive("G-Kira", record({ author = "Malgen-Forever" })))
            assert.is_false(handler.Receive("G-Kira", record({ version = 999 })))
            assert.is_false(handler.Receive("G-Kira", record({ setAt = 0, expiresAt = 1000 })))
            assert.are.equal("pvp", availability:Get("G-Kira"))
        end)
    end)
end)

describe("SyncMerge.Availability", function()
    local function check(record, current, now)
        local ns = load()
        local function personOf(key)
            return ({ ["Kira-Forever"] = "G-Kira", ["Malgen-Forever"] = "G-D" })[key]
        end
        return { ns.SyncMerge.Availability("G-Kira", record, current, personOf, now or 1000) }
    end
    local function record(fields)
        local result = { status = "pvp", version = 1000, setAt = 1000, expiresAt = 1000 + TTL,
            author = "Kira-Forever" }
        for key, value in pairs(fields or {}) do
            result[key] = value
        end
        return result
    end

    it("accepts a live status from the person's own character, relayed by anyone", function()
        assert.are.same({ true }, check(record()))
        assert.are.same({ true }, check(record({ status = "none" })))
    end)

    it("refuses another person's character", function()
        assert.are.same({ false, "not their character" }, check(record({ author = "Malgen-Forever" })))
    end)

    it("refuses statuses it doesn't know, without raising", function()
        assert.are.same({ false, "unknown status" }, check(record({ status = "raiding" })))
    end)

    it("refuses records that aren't newer", function()
        assert.are.same({ false, "not newer" }, check(record(), { version = 1000 }))
        assert.are.same({ true }, check(record(), { version = 999 }))
    end)

    it("refuses expired records and ones that claim to last too long", function()
        assert.are.same({ false, "expired" }, check(record(), nil, 1000 + TTL))
        assert.are.same({ false, "malformed" }, check(record({ expiresAt = 1000 + TTL + 1 })))
    end)

    it("refuses malformed records", function()
        assert.are.same({ false, "malformed" }, check("pvp"))
        assert.are.same({ false, "malformed" }, check(record({ version = "1" })))
        assert.are.same({ false, "malformed" }, check(record({ status = 5 })))
        assert.are.same({ false, "malformed" }, check(record({ author = false })))
    end)
end)
