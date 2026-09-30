local Harness = require("support.wow")

local NoteCodec = Harness.new():load("Core/NoteCodec.lua").NoteCodec

describe("NoteCodec.parse", function()
    local function parse(note)
        return NoteCodec.parse(note)
    end

    it("reads a first-name main ref", function()
        assert.are.same({ mainRef = "Dresden", rest = "" }, parse(">Dresden"))
    end)

    it("reads a two-word full-name main ref", function()
        assert.are.same({ mainRef = "Dresden Zelwindran", rest = "" }, parse(">Dresden Zelwindran"))
    end)

    it("reads an alias", function()
        assert.are.same({ alias = "Zel", rest = "" }, parse("@Zel"))
    end)

    it("reads a ref and an alias together in either order", function()
        assert.are.same({ mainRef = "Dresden", alias = "Zel", rest = "" }, parse(">Dresden @Zel"))
        assert.are.same({ mainRef = "Dresden", alias = "Zel", rest = "" }, parse("@Zel >Dresden"))
        assert.are.same({ mainRef = "Dresden Zelwindran", alias = "Zel", rest = "" },
            parse(">Dresden Zelwindran @Zel"))
    end)

    it("keeps other text as rest", function()
        assert.are.same({ mainRef = "Dresden", rest = "tank lvl 30" }, parse("tank >Dresden lvl 30"))
        assert.are.same({ alias = "Zel", rest = "Raid lead" }, parse("Raid lead @Zel"))
    end)

    it("does not take a lowercase word as a last name", function()
        assert.are.same({ mainRef = "Dresden", rest = "tank" }, parse(">Dresden tank"))
    end)

    it("takes at most two words for a ref", function()
        assert.are.same({ mainRef = "Dresden Zelwindran", rest = "Tank" }, parse(">Dresden Zelwindran Tank"))
    end)

    it("only treats markers at the start of a word as tokens", function()
        assert.are.same({ rest = "a>b me@home" }, parse("a>b me@home"))
    end)

    it("ignores bare markers", function()
        assert.are.same({ rest = "> @" }, parse("> @"))
    end)

    describe("legacy format", function()
        it("reads main: and alias:", function()
            assert.are.same({ mainRef = "Dresden", alias = "Zel", rest = "" }, parse("main: Dresden alias: Zel"))
        end)

        it("is case-insensitive", function()
            assert.are.same({ mainRef = "Dresden", alias = "Zel", rest = "" }, parse("MAIN:Dresden Alias: Zel"))
        end)

        it("reads a two-word legacy main", function()
            assert.are.same({ mainRef = "Dresden Zelwindran", rest = "" }, parse("main: Dresden Zelwindran"))
        end)

        it("keeps disc: in rest and never links it", function()
            assert.are.same({ mainRef = "Dresden", rest = "disc: zel#1234" }, parse("main: Dresden disc: zel#1234"))
            assert.are.same({ rest = "disc: Zel" }, parse("disc: Zel"))
        end)

        it("does not read the next label as a value", function()
            assert.are.same({ rest = "main: disc: zel" }, parse("main: disc: zel"))
        end)

        it("prefers the compact form when both are present", function()
            assert.are.same({ mainRef = "Dresden", rest = "main: Other" }, parse(">Dresden main: Other"))
        end)
    end)

    it("treats a missing note as empty", function()
        assert.are.same({ rest = "" }, parse(nil))
        assert.are.same({ rest = "" }, parse(""))
    end)
end)

describe("NoteCodec.compose", function()
    it("writes rest, alias, then ref", function()
        local result = NoteCodec.compose({ mainRef = "Dresden", alias = "Zel", rest = "tank" })
        assert.are.equal("tank @Zel >Dresden", result.text)
    end)

    it("writes only what is present", function()
        assert.are.equal(">Dresden", NoteCodec.compose({ mainRef = "Dresden", rest = "" }).text)
        assert.are.equal("@Zel", NoteCodec.compose({ alias = "Zel" }).text)
        assert.are.equal("", NoteCodec.compose({}).text)
    end)

    it("fits at exactly the limit", function()
        local result = NoteCodec.compose({ rest = string.rep("x", 31) })
        assert.is_true(result.fits)
        assert.are.equal(0, result.overflowBy)
    end)

    it("reports overflow without truncating", function()
        local long = string.rep("x", 30)
        local result = NoteCodec.compose({ mainRef = "Dresden", rest = long })
        assert.are.equal(long .. " >Dresden", result.text)
        assert.is_false(result.fits)
        assert.are.equal(8, result.overflowBy)
    end)

    it("uses the NOTE_LIMIT constant by default and accepts another limit", function()
        assert.are.equal(31, NoteCodec.NOTE_LIMIT)
        local result = NoteCodec.compose({ rest = "12345" }, 4)
        assert.is_false(result.fits)
        assert.are.equal(1, result.overflowBy)
    end)

    describe("round-trips through parse", function()
        local cases = {
            { mainRef = "Dresden", rest = "" },
            { mainRef = "Dresden Zelwindran", rest = "" },
            { alias = "Zel", rest = "" },
            { mainRef = "Dresden", alias = "Zel", rest = "" },
            { mainRef = "Dresden", rest = "Tank" },
            { mainRef = "Dresden Zelwindran", alias = "Zel", rest = "Raid Lead disc: zel" },
            { rest = "just a note" },
        }
        for _, parts in ipairs(cases) do
            it(NoteCodec.compose(parts).text, function()
                assert.are.same(parts, NoteCodec.parse(NoteCodec.compose(parts).text))
            end)
        end
    end)

    it("converts a legacy note to the compact form", function()
        local parts = NoteCodec.parse("main: Dresden alias: Zel")
        assert.are.equal("@Zel >Dresden", NoteCodec.compose(parts).text)
    end)
end)
