local Harness = require("support.wow")

local TooltipFormatter = Harness.new():load("Core/TooltipFormatter.lua").TooltipFormatter
local COLORS = TooltipFormatter.COLORS

local INFO = {
    ["Dresden-F"] = { name = "Dresden Zelwindran", level = 60, className = "Warrior", online = false },
    ["Malgen-F"] = { name = "Malgen Zelwindran", level = 34, className = "Mage", online = true },
    ["Kira-F"] = { name = "Kira Zelwindran", level = 12, className = "Priest", online = false },
}
local function infoFor(key)
    return INFO[key]
end

local function person(characters, alias, shortName)
    return {
        mainKey = characters[1],
        characters = characters,
        alias = alias,
        shortName = shortName or "Dresden",
        displayName = alias or shortName or "Dresden",
    }
end

describe("TooltipFormatter.Lines", function()
    it("adds nothing for an unknown character", function()
        assert.is_nil(TooltipFormatter.Lines(nil, "Stranger-F", infoFor))
    end)

    it("adds nothing for a lone main without an alias", function()
        assert.is_nil(TooltipFormatter.Lines(person({ "Dresden-F" }), "Dresden-F", infoFor))
    end)

    it("shows identity for a lone main with an alias", function()
        assert.are.same({
            { left = "Zel", color = COLORS.identity },
            { left = "Playing Dresden Zelwindran (main)", color = COLORS.text },
        }, TooltipFormatter.Lines(person({ "Dresden-F" }, "Zel"), "Dresden-F", infoFor))
    end)

    it("shows identity, current character, main, and other characters for an alt", function()
        local lines = TooltipFormatter.Lines(person({ "Dresden-F", "Kira-F", "Malgen-F" }, "Zel"), "Malgen-F", infoFor)
        assert.are.same({
            { left = "Zel", color = COLORS.identity },
            { left = "Playing Malgen Zelwindran", color = COLORS.text },
            { left = "Main: Dresden Zelwindran", right = "60 Warrior", color = COLORS.offline },
            { left = "  Kira Zelwindran", right = "12 Priest", color = COLORS.offline },
        }, lines)
    end)

    it("lists alts when hovering the main", function()
        local lines = TooltipFormatter.Lines(person({ "Dresden-F", "Malgen-F" }), "Dresden-F", infoFor)
        assert.are.same({
            { left = "Dresden", color = COLORS.identity },
            { left = "Playing Dresden Zelwindran (main)", color = COLORS.text },
            { left = "  Malgen Zelwindran", right = "34 Mage", color = COLORS.online },
        }, lines)
    end)

    it("caps the listed characters with +N more", function()
        local characters, info = { "Main-F" }, { ["Main-F"] = { name = "Main", level = 60, online = true } }
        for i = 1, 8 do
            local key = "Alt" .. i .. "-F"
            table.insert(characters, key)
            info[key] = { name = "Alt" .. i, level = i, online = false }
        end
        local lines = TooltipFormatter.Lines(person(characters), "Main-F", function(key)
            return info[key]
        end)
        assert.are.equal(2 + TooltipFormatter.MAX_LISTED + 1, #lines)
        assert.are.equal("  Alt5", lines[#lines - 1].left)
        assert.are.same({ left = "+3 more", color = COLORS.offline }, lines[#lines])
    end)

    it("skips characters with no roster info", function()
        local lines = TooltipFormatter.Lines(person({ "Dresden-F", "Gone-F", "Malgen-F" }), "Dresden-F", infoFor)
        assert.are.equal(3, #lines)
    end)

    it("leaves out missing level or class", function()
        local lines = TooltipFormatter.Lines(person({ "Main-F", "Alt-F" }), "Main-F", function(key)
            return ({ ["Main-F"] = { name = "Main" }, ["Alt-F"] = { name = "Alt", level = 5 } })[key]
        end)
        assert.are.equal("5", lines[3].right)
    end)

    describe("profile", function()
        it("adds Discord as a labelled contact line and the bio", function()
            local lines = TooltipFormatter.Lines(person({ "Dresden-F", "Malgen-F" }), "Dresden-F", infoFor,
                { discord = "zel", bio = "Loves dungeons" })
            assert.are.same({ left = "Discord", right = "zel", color = COLORS.text }, lines[4])
            assert.are.same({ left = "Loves dungeons", color = COLORS.offline }, lines[5])
            assert.are.equal("Dresden", lines[1].left)
        end)

        it("shows a lone main's section when they have a profile", function()
            local lines = TooltipFormatter.Lines(person({ "Dresden-F" }), "Dresden-F", infoFor, { discord = "zel" })
            assert.are.equal(3, #lines)
        end)

        it("truncates a long bio", function()
            local bio = string.rep("a", 58) .. "éé"
            local lines = TooltipFormatter.Lines(person({ "Dresden-F" }), "Dresden-F", infoFor, { bio = bio })
            assert.are.equal(string.rep("a", 58) .. "...", lines[3].left)
            local short = TooltipFormatter.Lines(person({ "Dresden-F" }), "Dresden-F", infoFor, { bio = "short" })
            assert.are.equal("short", short[3].left)
        end)
    end)
end)
