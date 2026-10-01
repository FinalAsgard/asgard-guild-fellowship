local Harness = require("support.wow")
local FakeLibs = require("support.fake_libs")

local FILES = {
    "Core/NoteCodec.lua",
    "Core/IdentityResolver.lua",
    "Core/SyncMerge.lua",
    "Core/IdentityStore.lua",
    "Core/Protocol.lua",
    "Core/Sync.lua",
}

local function member(name, note)
    return { key = name .. "-Forever", name = name, note = note or "", guid = "G-" .. name }
end

-- Back when Malgen's ">Dresden" had only one match.
local EARLY_ROSTER = { member("Dresden Zelwindran", "@Zel"), member("Malgen", ">Dresden") }
-- Now a second Dresden has joined, so ">Dresden" is ambiguous.
local ROSTER = { member("Dresden Zelwindran", "@Zel"), member("Malgen", ">Dresden"), member("Dresden Other") }

-- A guild channel shared by simulated clients. Messages are queued and
-- delivered to everyone but the sender on flush, like the addon channel.
local function newBus()
    local bus = { clients = {}, queue = {}, log = {} }
    function bus.flush()
        while #bus.queue > 0 do
            local item = table.remove(bus.queue, 1)
            for _, client in ipairs(bus.clients) do
                if client ~= item.from then
                    client.sync:OnMessage(item.message, item.from.name)
                end
            end
        end
    end
    -- Runs every client's clock forward second by second, delivering messages.
    function bus.settle(seconds)
        for _ = 1, seconds do
            for _, client in ipairs(bus.clients) do
                client.harness:advance(1)
            end
            bus.flush()
        end
    end
    return bus
end

local function newClient(bus, name, roster, options)
    options = options or {}
    local LibStub = FakeLibs.new()
    local harness = Harness.new({ globals = { LibStub = LibStub } })
    local ns = harness:loadAll(FILES)
    local client = { name = name, harness = harness, ns = ns, enabled = true, data = options.data or {} }
    client.store = ns.IdentityStore.New(client.data)
    for _, earlier in ipairs(options.history or {}) do
        client.store:Update(earlier)
    end
    client.store:Update(roster)
    client.sync = ns.Sync.New({
        send = function(message, priority)
            local kind, data = ns.Protocol.Decode(message)
            table.insert(bus.log, { from = name, kind = kind, data = data, priority = priority })
            table.insert(bus.queue, { from = client, message = message })
        end,
        after = function(seconds, fn)
            harness.env.C_Timer.After(seconds, fn)
        end,
        random = function()
            return options.random or 0.5
        end,
        now = function()
            return harness.now
        end,
        player = name,
        enabled = function()
            return client.enabled
        end,
    })
    client.sync:RegisterType("resolution", client.store:ResolutionSyncHandler())
    table.insert(bus.clients, client)
    return client
end

local function kinds(bus)
    local result = {}
    for _, entry in ipairs(bus.log) do
        table.insert(result, entry.from .. ":" .. entry.kind)
    end
    return result
end

local function linkOf(client, altKey)
    return client.store:GetPerson(altKey).id
end

describe("Sync", function()
    it("fills a new user's ambiguous link from a mature user", function()
        local bus = newBus()
        local veteran = newClient(bus, "Veteran-Forever", ROSTER, { history = { EARLY_ROSTER } })
        local newcomer = newClient(bus, "Newcomer-Forever", ROSTER)
        assert.are.equal("G-Dresden Zelwindran", linkOf(veteran, "Malgen-Forever"))
        assert.are.equal("G-Malgen", linkOf(newcomer, "Malgen-Forever"))

        newcomer.sync:SendDigest()
        bus.settle(10)

        assert.are.same({ "Newcomer-Forever:digest", "Veteran-Forever:versions", "Newcomer-Forever:want",
            "Veteran-Forever:records" }, kinds(bus))
        assert.are.equal("G-Dresden Zelwindran", linkOf(newcomer, "Malgen-Forever"))
        assert.are.equal("Zel", newcomer.store:GetDisplayName(linkOf(newcomer, "Malgen-Forever")))
        assert.are.equal("ambiguous", newcomer.store:GetIssues()[1].type)
        assert.are.same(veteran.sync:Digest(), newcomer.sync:Digest())
    end)

    it("converges when the mature user is the one sending the digest", function()
        local bus = newBus()
        local veteran = newClient(bus, "Veteran-Forever", ROSTER, { history = { EARLY_ROSTER } })
        local newcomer = newClient(bus, "Newcomer-Forever", ROSTER)
        veteran.sync:SendDigest()
        bus.settle(10)
        assert.are.equal("G-Dresden Zelwindran", linkOf(newcomer, "Malgen-Forever"))
        assert.are.same(veteran.sync:Digest(), newcomer.sync:Digest())
    end)

    it("starts on its own and converges through scheduled digests", function()
        local bus = newBus()
        local veteran = newClient(bus, "Veteran-Forever", ROSTER, { history = { EARLY_ROSTER } })
        local newcomer = newClient(bus, "Newcomer-Forever", ROSTER)
        veteran.sync:Start()
        newcomer.sync:Start()
        bus.settle(30)
        assert.are.equal("G-Dresden Zelwindran", linkOf(newcomer, "Malgen-Forever"))
    end)

    it("stays quiet when everyone already agrees", function()
        local bus = newBus()
        newClient(bus, "A-Forever", ROSTER, { history = { EARLY_ROSTER } })
        local b = newClient(bus, "B-Forever", ROSTER, { history = { EARLY_ROSTER } })
        b.sync:SendDigest()
        bus.settle(10)
        assert.are.same({ "B-Forever:digest" }, kinds(bus))
    end)

    it("lets only one peer answer a given need", function()
        local bus = newBus()
        newClient(bus, "Fast-Forever", ROSTER, { history = { EARLY_ROSTER }, random = 0.1 })
        newClient(bus, "Slow-Forever", ROSTER, { history = { EARLY_ROSTER }, random = 0.9 })
        local newcomer = newClient(bus, "Newcomer-Forever", ROSTER)
        newcomer.sync:SendDigest()
        bus.settle(10)
        local answers = 0
        for _, entry in ipairs(bus.log) do
            if entry.kind == "versions" then
                answers = answers + 1
                assert.are.equal("Fast-Forever", entry.from)
            end
        end
        assert.are.equal(1, answers)
        assert.are.equal("G-Dresden Zelwindran", linkOf(newcomer, "Malgen-Forever"))
    end)

    it("rejects forged links from another user", function()
        local bus = newBus()
        local victim = newClient(bus, "Victim-Forever", { member("Dresden Zelwindran"), member("Dresden Other"),
            member("Malgen", ">Dresden"), member("Mallory") })
        local forger = newClient(bus, "Mallory-Forever", {})
        forger.sync:Send("records", { t = "resolution", r = {
            ["Malgen-Forever"] = { target = "G-Mallory", ref = "Dresden" },
        } }, "BULK")
        bus.flush()
        assert.are.equal("G-Malgen", linkOf(victim, "Malgen-Forever"))
        assert.is_nil(victim.data.resolutions["Malgen-Forever"])
    end)

    it("ignores unknown record types, unknown kinds, and garbage", function()
        local bus = newBus()
        local client = newClient(bus, "A-Forever", ROSTER)
        local other = newClient(bus, "B-Forever", {})
        other.sync:Send("records", { t = "profile", r = { x = {} } }, "BULK")
        table.insert(bus.queue, { from = other, message = "garbage" })
        bus.flush()
        assert.are.equal("G-Malgen", linkOf(client, "Malgen-Forever"))
    end)

    it("does nothing while sync is turned off", function()
        local bus = newBus()
        newClient(bus, "Veteran-Forever", ROSTER, { history = { EARLY_ROSTER } })
        local newcomer = newClient(bus, "Newcomer-Forever", ROSTER)
        newcomer.enabled = false
        newcomer.sync:SendDigest()
        assert.are.same({}, kinds(bus))
        newcomer.enabled = true
        newcomer.sync:SendDigest()
        newcomer.enabled = false
        bus.settle(10)
        assert.are.equal("G-Malgen", linkOf(newcomer, "Malgen-Forever"))
    end)

    it("rate-limits digests", function()
        local bus = newBus()
        local client = newClient(bus, "A-Forever", ROSTER)
        client.sync:SendDigest()
        client.sync:SendDigest()
        assert.are.equal(1, #bus.log)
        client.harness:advance(client.ns.Sync.MIN_DIGEST_GAP)
        client.sync:SendDigest()
        assert.are.equal(2, #bus.log)
    end)

    it("sends records at bulk priority and control messages at normal priority", function()
        local bus = newBus()
        newClient(bus, "Veteran-Forever", ROSTER, { history = { EARLY_ROSTER } })
        local newcomer = newClient(bus, "Newcomer-Forever", ROSTER)
        newcomer.sync:SendDigest()
        bus.settle(10)
        for _, entry in ipairs(bus.log) do
            assert.are.equal(entry.kind == "records" and "BULK" or "NORMAL", entry.priority)
        end
    end)

    it("stops sending after Stop", function()
        local bus = newBus()
        local client = newClient(bus, "A-Forever", ROSTER)
        client.sync:Start()
        client.sync:Stop()
        bus.settle(60)
        assert.are.same({}, kinds(bus))
    end)

    it("hashes versions independently of order", function()
        local Sync = newClient(newBus(), "A-Forever", {}).ns.Sync
        assert.are.equal(Sync.Hash({ a = 1, b = 2 }), Sync.Hash({ b = 2, a = 1 }))
        assert.are_not.equal(Sync.Hash({ a = 1 }), Sync.Hash({ a = 2 }))
    end)

    it("ignores non-string ids in a peer's versions without erroring", function()
        local bus = newBus()
        local client = newClient(bus, "A-Forever", ROSTER, { history = { EARLY_ROSTER } })
        local peer = newClient(bus, "B-Forever", {})
        peer.sync:Send("versions", { to = "A-Forever", t = "resolution", v = { [1] = 5, a = 5, b = "x" } }, "NORMAL")
        assert.has_no.errors(function()
            bus.flush()
        end)
        local wants
        for _, entry in ipairs(bus.log) do
            if entry.kind == "want" then
                wants = entry.data.ids
            end
        end
        assert.are.same({ "a" }, wants)
        assert.are.equal("G-Dresden Zelwindran", client.store:GetPerson("Malgen-Forever").id)
    end)
end)
