local Harness = require("support.wow")

local Commands = Harness.new():load("Core/Commands.lua").Commands

describe("Commands", function()
    describe("IsTaken", function()
        it("is false when nothing registered the command", function()
            assert.is_false(Commands.IsTaken({ SLASH_OTHER1 = "/other" }, "gf"))
        end)

        it("finds another add-on's SLASH_ global, ignoring case", function()
            assert.is_true(Commands.IsTaken({ SLASH_GUILDFRIENDS2 = "/GF" }, "gf"))
        end)

        it("finds a command already in the chat frame's hash", function()
            assert.is_true(Commands.IsTaken({ hash_SlashCmdList = { ["/GF"] = function() end } }, "gf"))
        end)

        it("ignores non-slash globals holding the same text", function()
            assert.is_false(Commands.IsTaken({ SOME_TEXT = "/gf" }, "gf"))
        end)
    end)

    describe("Dispatch", function()
        local calls
        local handlers = {
            [""] = function(rest) table.insert(calls, { "open", rest }) end,
            version = function(rest) table.insert(calls, { "version", rest }) end,
            usage = function(rest) table.insert(calls, { "usage", rest }) end,
        }

        before_each(function()
            calls = {}
        end)

        it("runs the empty handler for no input", function()
            Commands.Dispatch("", handlers)
            Commands.Dispatch(nil, handlers)
            Commands.Dispatch("   ", handlers)
            assert.are.same({ { "open", "" }, { "open", "" }, { "open", "" } }, calls)
        end)

        it("matches the first word case-insensitively and passes the rest", function()
            Commands.Dispatch("  Version  now please ", handlers)
            assert.are.same({ { "version", "now please" } }, calls)
        end)

        it("runs usage for an unknown word", function()
            Commands.Dispatch("dance", handlers)
            assert.are.same({ { "usage", "" } }, calls)
        end)
    end)
end)
