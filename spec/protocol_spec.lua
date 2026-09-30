local Harness = require("support.wow")
local realLibs = require("support.real_libs")

local function load()
    local libs = realLibs()
    local LibStub = function(name)
        return assert(libs[name], name)
    end
    return Harness.new({ globals = { LibStub = LibStub } }):load("Core/Protocol.lua").Protocol, libs
end

local Protocol, libs = load()

-- Encodes an arbitrary envelope, for testing how Decode treats it.
local function raw(envelope)
    local deflate = libs.LibDeflate
    return deflate:EncodeForWoWAddonChannel(deflate:CompressDeflate(libs["AceSerializer-3.0"]:Serialize(envelope)))
end

describe("Protocol", function()
    it("round-trips a message", function()
        local data = { t = "resolution", r = { ["Malgen Zelwindran-Forever"] = { target = "G-D", ref = "Dresden" } } }
        local kind, decoded = Protocol.Decode(Protocol.Encode("records", data))
        assert.are.equal("records", kind)
        assert.are.same(data, decoded)
    end)

    it("produces text safe for the addon channel", function()
        local message = Protocol.Encode("digest", { h = { resolution = 123456789 } })
        assert.is_nil(message:find("[%z\n\r|]"))
    end)

    it("ignores messages from a newer protocol version", function()
        assert.are.same({ nil, "newer" }, { Protocol.Decode(raw({ v = Protocol.VERSION + 1, k = "digest", d = {} })) })
    end)

    it("ignores unknown message kinds", function()
        assert.are.same({ nil, "unknown" }, { Protocol.Decode(raw({ v = 1, k = "dance", d = {} })) })
    end)

    it("still accepts known kinds from an older version", function()
        assert.are.equal("digest", (Protocol.Decode(raw({ v = 0, k = "digest", d = {}, extra = true }))))
    end)

    it("rejects malformed input without raising", function()
        for _, message in ipairs({ nil, 42, "", "not encoded at all", "\0\1\2", raw("just a string"),
            raw({ k = "digest", d = {} }), raw({ v = 1, k = "digest", d = "text" }), raw({ v = 1, d = {} }) }) do
            local kind, reason = Protocol.Decode(message)
            assert.is_nil(kind)
            assert.are.equal("malformed", reason)
        end
    end)

    describe("Batch", function()
        local function records(count)
            local result = {}
            for i = 1, count do
                result[("Character %03d-Forever"):format(i)] = { target = "Player-0000-" .. i, ref = "Someone" }
            end
            return result
        end

        it("keeps a small set in one batch", function()
            local batches = Protocol.Batch(records(3))
            assert.are.equal(1, #batches)
            assert.are.same(records(3), batches[1])
        end)

        it("splits a large set into batches under the size limit that together hold every record", function()
            local all = records(200)
            local batches = Protocol.Batch(all, 1000)
            assert.is_true(#batches > 1)
            local joined = {}
            for _, batch in ipairs(batches) do
                assert.is_true(#libs["AceSerializer-3.0"]:Serialize(batch) <= 1100)
                for id, record in pairs(batch) do
                    assert.is_nil(joined[id])
                    joined[id] = record
                end
                -- Each batch decodes on its own.
                local _, decoded = Protocol.Decode(Protocol.Encode("records", { t = "resolution", r = batch }))
                assert.are.same(batch, decoded.r)
            end
            assert.are.same(all, joined)
        end)

        it("gives an oversized record a batch of its own", function()
            local batches = Protocol.Batch({ a = { note = string.rep("x", 50) }, b = { note = "y" } }, 10)
            assert.are.equal(2, #batches)
        end)

        it("returns no batches for no records", function()
            assert.are.same({}, Protocol.Batch({}))
        end)
    end)
end)
