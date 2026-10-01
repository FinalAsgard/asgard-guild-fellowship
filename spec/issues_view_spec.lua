local Harness = require("support.wow")

local IssuesView = Harness.new():load("Core/IssuesView.lua").IssuesView

local function nameFor(key)
    return (key:gsub("%-Forever$", ""))
end

describe("IssuesView.Build", function()
    it("reports an empty view when there are no issues", function()
        assert.are.same({ empty = true, count = 0, groups = {} }, IssuesView.Build({}, nameFor))
    end)

    it("groups issues by type in a fixed order with titles and explanations", function()
        local view = IssuesView.Build({
            { type = "cycle", characters = { "Anna-Forever", "Bert-Forever" }, fix = "Fix the loop." },
            { type = "ambiguous", characters = { "Malgen-Forever" }, ref = "Dresden", fix = "Use a full name." },
            { type = "ambiguous", characters = { "Kira-Forever" }, ref = "Dresden", fix = "Use a full name." },
            { type = "chain", characters = { "Kira-Forever", "Malgen-Forever", "Dresden Zelwindran-Forever" },
                ref = "Malgen", fix = "Point at Dresden." },
        }, nameFor)
        assert.is_false(view.empty)
        assert.are.equal(4, view.count)
        local types = {}
        for _, group in ipairs(view.groups) do
            table.insert(types, group.type)
            assert.is_string(group.title)
            assert.is_string(group.explanation)
        end
        assert.are.same({ "ambiguous", "chain", "cycle" }, types)
        assert.are.equal(2, #view.groups[1].items)
    end)

    it("shows each issue's characters, note reference, and suggested fix", function()
        local view = IssuesView.Build({
            { type = "chain", characters = { "Kira-Forever", "Malgen-Forever", "Dresden Zelwindran-Forever" },
                ref = "Malgen", fix = "Change the note to >Dresden." },
        }, nameFor)
        assert.are.same({
            names = "Kira, Malgen, Dresden Zelwindran",
            ref = ">Malgen",
            fix = "Change the note to >Dresden.",
            characters = { "Kira-Forever", "Malgen-Forever", "Dresden Zelwindran-Forever" },
        }, view.groups[1].items[1])
    end)

    it("leaves out the reference for issues without one", function()
        local view = IssuesView.Build({ { type = "cycle", characters = { "Anna-Forever" }, fix = "x" } }, nameFor)
        assert.is_nil(view.groups[1].items[1].ref)
    end)

    it("covers every issue type the resolver raises", function()
        for _, issueType in ipairs({ "ambiguous", "unresolved", "orphan", "chain", "cycle" }) do
            local view = IssuesView.Build({ { type = issueType, characters = { "A-Forever" }, fix = "x" } }, nameFor)
            assert.are.equal(1, #view.groups, issueType)
        end
    end)
end)
