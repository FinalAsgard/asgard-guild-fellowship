local addonName, addon = ...

-- The settings panel, registered with AceConfig and shown in the standard
-- options panel. Features add their toggles to the "features" group.
local Options = {}
addon.Options = Options

Options.TITLE = "Asgard's Guild Fellowship"

function Options.Build()
    return {
        type = "group",
        name = Options.TITLE,
        args = {
            features = {
                type = "group",
                name = "Feature toggles",
                inline = true,
                order = 1,
                args = {
                    empty = {
                        type = "description",
                        name = "Features you can turn on or off will be listed here.",
                        order = 1,
                    },
                },
            },
        },
    }
end

function Options.Register()
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, Options.Build())
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, Options.TITLE)
end
