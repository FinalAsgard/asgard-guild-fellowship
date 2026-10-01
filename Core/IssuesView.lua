local _, addon = ...

-- Builds the officers' Identity Issues view from IdentityStore:GetIssues().
-- Pure: returns plain data that Core renders through the UI layer.
local IssuesView = {}
addon.IssuesView = IssuesView

-- Issue types in display order, with a heading and a plain-language explanation.
IssuesView.TYPES = {
    {
        type = "ambiguous",
        title = "Ambiguous links",
        explanation = "The main named in these notes matches more than one character, so the link can't be "
            .. "trusted. A link synced from another user may be filling in for now.",
    },
    {
        type = "unresolved",
        title = "Unresolved links",
        explanation = "Nobody in the guild matches the main named in these notes.",
    },
    {
        type = "orphan",
        title = "Orphaned links",
        explanation = "The main these notes point to has left the guild.",
    },
    {
        type = "chain",
        title = "Alt-to-alt links",
        explanation = "These notes point to another alt instead of the main. They still work, but break easily.",
    },
    {
        type = "cycle",
        title = "Circular links",
        explanation = "These notes point at each other, so none of them can be linked.",
    },
}

-- build(issues, nameFor) -> { empty, count, groups }
--   issues:  IdentityStore:GetIssues()
--   nameFor: function(charKey) -> name to show
--   groups:  non-empty groups in TYPES order:
--     { type, title, explanation, items = { { names, ref, fix, characters } } }
--   names is the affected characters' names joined with ", "; ref is the note's
--   main reference as written (">Dresden"), or nil.
function IssuesView.Build(issues, nameFor)
    local byType = {}
    for _, issue in ipairs(issues) do
        local names = {}
        for _, key in ipairs(issue.characters) do
            table.insert(names, nameFor(key))
        end
        byType[issue.type] = byType[issue.type] or {}
        table.insert(byType[issue.type], {
            names = table.concat(names, ", "),
            ref = issue.ref and (">" .. issue.ref) or nil,
            fix = issue.fix,
            characters = issue.characters,
        })
    end
    local groups = {}
    for _, info in ipairs(IssuesView.TYPES) do
        if byType[info.type] then
            table.insert(groups, {
                type = info.type,
                title = info.title,
                explanation = info.explanation,
                items = byType[info.type],
            })
        end
    end
    return { empty = #issues == 0, count = #issues, groups = groups }
end
