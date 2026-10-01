local Harness = require("support.wow")

local ns = Harness.new():loadAll({ "Core/NoteCodec.lua", "Core/IdentityResolver.lua", "Core/SyncMerge.lua" })
local accept = ns.SyncMerge.Resolution

local function member(name, note)
    return { key = name .. "-Forever", name = name, note = note or "", guid = "G-" .. name }
end

-- Malgen's ">Dresden" is ambiguous between two Dresdens.
local ROSTER = {
    member("Dresden Zelwindran"),
    member("Dresden Other"),
    member("Malgen", ">Dresden"),
    member("Kira"),
    member("Solo", ">Kira"),
}

local function check(altKey, record, cache)
    return { accept(altKey, record, ROSTER, cache) }
end

describe("SyncMerge.Resolution", function()
    it("accepts a link that fills an ambiguous ref consistently", function()
        assert.are.same({ true }, check("Malgen-Forever", { target = "G-Dresden Zelwindran", ref = "Dresden" }))
        assert.are.same({ true }, check("Malgen-Forever", { target = "G-Dresden Other", ref = "dresden" }))
    end)

    it("rejects a forged link to someone the note doesn't name", function()
        assert.are.same({ false, "inconsistent" }, check("Malgen-Forever", { target = "G-Kira", ref = "Dresden" }))
    end)

    it("rejects a link to a character who isn't in the roster", function()
        assert.are.same({ false, "inconsistent" }, check("Malgen-Forever", { target = "G-Ghost", ref = "Dresden" }))
    end)

    it("rejects a link that lies about the note's ref", function()
        assert.are.same({ false, "note changed" }, check("Malgen-Forever", { target = "G-Kira", ref = "Kira" }))
        assert.are.same({ false, "note changed" }, check("Kira-Forever", { target = "G-Solo", ref = "Solo" }))
    end)

    it("rejects a link that conflicts with an unambiguous local resolution", function()
        assert.are.same({ false, "conflict" }, check("Solo-Forever", { target = "G-Dresden Other", ref = "Kira" }))
        assert.are.same({ true }, check("Solo-Forever", { target = "G-Kira", ref = "Kira" }))
    end)

    it("rejects a link to the alt itself", function()
        local roster = { member("Dresden"), member("Dresden Two", ">Dresden") }
        assert.are.same({ false, "conflict" },
            { accept("Dresden Two-Forever", { target = "G-Dresden Two", ref = "Dresden" }, roster) })
    end)

    it("keeps a different local link that still fits the note", function()
        local cache = { ["Malgen-Forever"] = { target = "G-Dresden Other", ref = "Dresden" } }
        assert.are.same({ false, "keeping local" },
            check("Malgen-Forever", { target = "G-Dresden Zelwindran", ref = "Dresden" }, cache))
        assert.are.same({ true }, check("Malgen-Forever", { target = "G-Dresden Other", ref = "Dresden" }, cache))
    end)

    it("replaces a stale local link", function()
        local stale = { ["Malgen-Forever"] = { target = "G-Gone", ref = "Dresden" } }
        assert.are.same({ true }, check("Malgen-Forever", { target = "G-Dresden Zelwindran", ref = "Dresden" }, stale))
    end)

    it("rejects unknown alts and malformed records", function()
        assert.are.same({ false, "unknown alt" }, check("Nobody-Forever", { target = "G-Kira", ref = "Kira" }))
        for _, record in ipairs({ nil, "text", {}, { target = 1, ref = "Dresden" }, { target = "G-Kira" } }) do
            assert.are.same({ false, "malformed" }, check("Malgen-Forever", record))
        end
        assert.are.same({ false, "malformed" }, check(nil, { target = "G-Kira", ref = "Kira" }))
    end)
end)
