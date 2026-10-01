local Harness = require("support.wow")

local ns = Harness.new():loadAll({ "Core/NoteCodec.lua", "Core/IdentityResolver.lua", "Core/NoteHelper.lua" })
local NoteHelper = ns.NoteHelper

local function member(name, note, realm)
    realm = realm or "Forever"
    return { key = name .. "-" .. realm, name = name, note = note or "", guid = "G-" .. name .. "-" .. realm }
end

local function everyone()
    return true
end

local function refFor(roster, mainKey, altKey)
    local index = ns.IdentityResolver.Index(roster)
    return NoteHelper.ShortestRef(index, index.members[mainKey], index.members[altKey])
end

describe("NoteHelper.ShortestRef", function()
    it("uses the first name when it is unique", function()
        local roster = { member("Dresden Zelwindran"), member("Malgen") }
        assert.are.equal("Dresden", refFor(roster, "Dresden Zelwindran-Forever", "Malgen-Forever"))
    end)

    it("uses the full name when the first name is shared", function()
        local roster = { member("Dresden Zelwindran"), member("Dresden Other"), member("Malgen") }
        assert.are.equal("Dresden Zelwindran", refFor(roster, "Dresden Zelwindran-Forever", "Malgen-Forever"))
    end)

    it("ignores the alt itself when checking uniqueness", function()
        local roster = { member("Dresden Zelwindran"), member("Dresden Alt") }
        assert.are.equal("Dresden", refFor(roster, "Dresden Zelwindran-Forever", "Dresden Alt-Forever"))
    end)

    it("uses Name-Realm when the full name exists on two realms", function()
        local roster = {
            member("Thrall", "", "Area52"), member("Thrall", "", "Stormrage"), member("Jaina", "", "Area52"),
        }
        assert.are.equal("Thrall-Stormrage", refFor(roster, "Thrall-Stormrage", "Jaina-Area52"))
    end)

    it("avoids a first name that exactly matches someone else's full name", function()
        local roster = { member("Dresden"), member("Dresden Zelwindran"), member("Malgen") }
        assert.are.equal("Dresden Zelwindran", refFor(roster, "Dresden Zelwindran-Forever", "Malgen-Forever"))
        assert.are.equal("Dresden", refFor(roster, "Dresden-Forever", "Malgen-Forever"))
    end)
end)

describe("NoteHelper.Choices", function()
    it("lists everyone, and only editable characters as editable, by name", function()
        local roster = { member("Zed"), member("Anna"), member("Mike") }
        local choices = NoteHelper.Choices(roster, function(key)
            return key ~= "Mike-Forever"
        end)
        assert.are.same({ "Anna", "Mike", "Zed" }, { choices.all[1].name, choices.all[2].name, choices.all[3].name })
        assert.are.same({ { key = "Anna-Forever", name = "Anna" }, { key = "Zed-Forever", name = "Zed" } },
            choices.editable)
    end)
end)

describe("NoteHelper.Plan", function()
    local ROSTER = {
        member("Dresden Zelwindran", "Raid lead"),
        member("Malgen Zelwindran", "tank main: Old"),
        member("Kira", string.rep("x", 28)),
    }

    it("links an alt with the shortest ref and keeps other note text", function()
        local plan = NoteHelper.Plan({ mode = "link", alt = "Malgen Zelwindran-Forever",
            main = "Dresden Zelwindran-Forever" }, ROSTER, everyone)
        assert.are.equal("tank main: Old", plan.current)
        assert.are.equal("tank >Dresden", plan.text)
        assert.is_true(plan.fits)
        assert.is_true(plan.canWrite)
        assert.are.equal("Malgen Zelwindran-Forever", plan.member.key)
    end)

    it("sets, replaces, and removes a main's alias", function()
        local set = NoteHelper.Plan({ mode = "alias", main = "Dresden Zelwindran-Forever", alias = " Zel " }, ROSTER,
            everyone)
        assert.are.equal("Raid lead @Zel", set.text)
        local roster = { member("Dresden Zelwindran", "@Old note") }
        local replaced = NoteHelper.Plan({ mode = "alias", main = "Dresden Zelwindran-Forever", alias = "Zel" },
            roster, everyone)
        assert.are.equal("note @Zel", replaced.text)
        local removed = NoteHelper.Plan({ mode = "alias", main = "Dresden Zelwindran-Forever", alias = "" },
            roster, everyone)
        assert.are.equal("note", removed.text)
    end)

    it("warns and refuses when the note won't fit", function()
        local plan = NoteHelper.Plan({ mode = "link", alt = "Kira-Forever", main = "Dresden Zelwindran-Forever" },
            ROSTER, everyone)
        assert.is_false(plan.fits)
        assert.are.equal(6, plan.overflowBy)
        assert.is_false(plan.canWrite)
        assert.truthy(plan.reason:find("6 characters too long", 1, true))
    end)

    it("respects the note limit passed in", function()
        local plan = NoteHelper.Plan({ mode = "alias", main = "Dresden Zelwindran-Forever", alias = "Zel" }, ROSTER,
            everyone, 10)
        assert.is_false(plan.fits)
    end)

    it("only offers edits the player may make", function()
        local plan = NoteHelper.Plan({ mode = "link", alt = "Malgen Zelwindran-Forever",
            main = "Dresden Zelwindran-Forever" }, ROSTER, function()
            return false
        end)
        assert.is_false(plan.canWrite)
        assert.are.equal("You can't edit Malgen Zelwindran's note.", plan.reason)
    end)

    it("explains incomplete or pointless edits", function()
        assert.are.equal("Pick an alt.", NoteHelper.Plan({ mode = "link" }, ROSTER, everyone).reason)
        assert.are.equal("Pick a main.", NoteHelper.Plan({ mode = "alias" }, ROSTER, everyone).reason)
        assert.are.equal("Pick the main this alt belongs to.", NoteHelper.Plan({ mode = "link",
            alt = "Kira-Forever", main = "Kira-Forever" }, ROSTER, everyone).reason)
        local same = NoteHelper.Plan({ mode = "alias", main = "Kira-Forever", alias = "" }, ROSTER, everyone)
        assert.are.equal("The note already says this.", same.reason)
        assert.is_false(same.canWrite)
    end)

    it("rejects aliases that aren't one plain word", function()
        for _, alias in ipairs({ "Big Mike", "@Zel", ">Zel", "a:b", "x|y" }) do
            local plan = NoteHelper.Plan({ mode = "alias", main = "Kira-Forever", alias = alias }, ROSTER, everyone)
            assert.is_false(plan.canWrite, alias)
        end
    end)

    it("produces notes the resolver links as intended", function()
        local roster = { member("Dresden Zelwindran"), member("Dresden Other"), member("Malgen", "tank") }
        local plan = NoteHelper.Plan({ mode = "link", alt = "Malgen-Forever", main = "Dresden Zelwindran-Forever" },
            roster, everyone)
        roster[3] = member("Malgen", plan.text)
        local result = ns.IdentityResolver.resolve(roster)
        assert.are.equal("G-Dresden Zelwindran-Forever", result.charToPerson["Malgen-Forever"])
        assert.are.same({}, result.issues)
    end)
end)
