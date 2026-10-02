local Harness = require("support.wow")
local FakeLibs = require("support.fake_libs")

local function loadUI()
    local LibStub, log = FakeLibs.new()
    local ns = Harness.new({ globals = { LibStub = LibStub } }):load("Core/UI.lua")
    return ns.UI, log.AceGUI
end

describe("UI.Window", function()
    it("builds nothing until shown", function()
        local UI, gui = loadUI()
        local window = UI.Window({ title = "Test", width = 300, height = 200 })
        assert.is_false(window:IsShown())
        assert.are.equal(0, #gui.created)
    end)

    it("builds a titled, sized frame when shown", function()
        local UI, gui = loadUI()
        UI.Window({ title = "Test", width = 300, height = 200 }):Show()
        local frame = gui.created[1]
        assert.are.equal("Test", frame.title)
        assert.are.equal(300, frame.width)
        assert.are.equal(200, frame.height)
    end)

    it("shows only one frame at a time", function()
        local UI, gui = loadUI()
        local window = UI.Window({ title = "Test", width = 300, height = 200 })
        window:Show()
        window:Show()
        local frames = 0
        for _, widget in ipairs(gui.created) do
            if widget.kind == "Frame" then
                frames = frames + 1
            end
        end
        assert.are.equal(1, frames)
    end)

    it("releases the frame when hidden", function()
        local UI, gui = loadUI()
        local window = UI.Window({ title = "Test", width = 300, height = 200 })
        window:Show()
        window:Hide()
        assert.is_false(window:IsShown())
        assert.are.equal(gui.created[1], gui.released[1])
    end)

    it("releases the frame when the player closes it", function()
        local UI, gui = loadUI()
        local window = UI.Window({ title = "Test", width = 300, height = 200 })
        window:Show()
        gui.created[1].callbacks.OnClose(gui.created[1])
        assert.is_false(window:IsShown())
        assert.are.equal(1, #gui.released)
    end)

    it("toggles", function()
        local UI = loadUI()
        local window = UI.Window({ title = "Test", width = 300, height = 200 })
        window:Toggle()
        assert.is_true(window:IsShown())
        window:Toggle()
        assert.is_false(window:IsShown())
    end)

    describe("content", function()
        local function rendered(render)
            local UI, gui = loadUI()
            local window = UI.Window({ title = "Test", width = 300, height = 200, render = render })
            window:Show()
            local scroll = gui.created[2]
            return window, scroll, gui
        end

        it("renders into a scrolling column when shown", function()
            local _, scroll = rendered(function(window)
                window:AddHeading("Title")
                window:AddText("Plain")
                window:AddText("Grey", { 0.5, 0.5, 0.5 })
            end)
            assert.are.equal("ScrollFrame", scroll.kind)
            assert.are.equal("List", scroll.layout)
            assert.are.same({ "Heading", "Label", "Label" },
                { scroll.children[1].kind, scroll.children[2].kind, scroll.children[3].kind })
            assert.are.equal("Title", scroll.children[1].text)
            assert.are.same({ 0.5, 0.5, 0.5 }, scroll.children[3].color)
            assert.is_nil(scroll.children[2].color)
        end)

        it("adds buttons that can be disabled", function()
            local clicked = false
            local _, scroll = rendered(function(window)
                window:AddButton("Go", function()
                    clicked = true
                end)
                window:AddButton("Later", function() end, true)
            end)
            assert.is_false(scroll.children[1].disabled)
            assert.is_true(scroll.children[2].disabled)
            scroll.children[1].callbacks.OnClick()
            assert.is_true(clicked)
        end)

        it("re-renders on Refresh and ignores Refresh while closed", function()
            local count = 0
            local window, scroll = rendered(function(w)
                count = count + 1
                w:AddText("Line " .. count)
            end)
            window:Refresh()
            assert.are.equal(2, count)
            assert.are.equal(1, #scroll.children)
            assert.are.equal("Line 2", scroll.children[1].text)
            window:Hide()
            window:Refresh()
            assert.are.equal(2, count)
        end)

        it("adds dropdowns and inputs that report changes", function()
            local picked, typed
            local _, scroll = rendered(function(window)
                window:AddDropdown("Pick", { { value = "a", text = "Apple" }, { value = "b", text = "Banana" } }, "b",
                    function(value) picked = value end)
                window:AddInput("Name", "Zel", function(text) typed = text end)
            end)
            local dropdown, input = scroll.children[1], scroll.children[2]
            assert.are.same({ a = "Apple", b = "Banana" }, dropdown.list)
            assert.are.same({ "a", "b" }, dropdown.order)
            assert.are.equal("b", dropdown.value)
            dropdown.callbacks.OnValueChanged(dropdown, "OnValueChanged", "a")
            assert.are.equal("a", picked)
            assert.are.equal("Zel", input.text)
            input.callbacks.OnEnterPressed(input, "OnEnterPressed", "Drez")
            assert.are.equal("Drez", typed)
        end)

        it("holds off redraws while the player is typing, and gives up focus on Enter", function()
            local count, entered = 0, nil
            local window, scroll = rendered(function(w)
                count = count + 1
                w:AddInput("Search", "", function(text) entered = text end)
            end)
            local input = scroll.children[1]
            input.editbox = { focused = true, HasFocus = function(self) return self.focused end }
            window:Refresh()
            assert.are.equal(1, count)
            assert.are.equal(input, scroll.children[1])
            input.callbacks.OnEnterPressed(input, "OnEnterPressed", "zel")
            assert.are.equal("zel", entered)
            assert.is_true(input.focusCleared)
            window:Refresh()
            assert.are.equal(2, count)
        end)

        it("forgets its text boxes when closed, so a reused widget can't block reopening", function()
            local count = 0
            local window, scroll = rendered(function(w)
                count = count + 1
                w:AddInput("Search", "", function() end)
            end)
            local input = scroll.children[1]
            window:Hide()
            -- AceGUI hands the released box to some other window, where it gets focus.
            input.editbox = { HasFocus = function() return true end }
            window:Show()
            assert.are.equal(2, count)
        end)

        it("adds checkboxes that report changes", function()
            local checked
            local _, scroll = rendered(function(window)
                window:AddCheckBox("Same zone", true, function(value) checked = value end)
            end)
            local checkbox = scroll.children[1]
            assert.are.equal("CheckBox", checkbox.kind)
            assert.are.equal("Same zone", checkbox.label)
            assert.is_true(checkbox.value)
            checkbox.callbacks.OnValueChanged(checkbox, "OnValueChanged", false)
            assert.is_false(checked)
        end)
    end)
end)

describe("UI.Prompt", function()
    local function newPrompt(onClose)
        local UI, gui = loadUI()
        return UI.Prompt({ title = "Hello", width = 200, height = 100, onClose = onClose }), gui
    end

    it("shows rows of text and buttons, and replaces them on the next Show", function()
        local prompt, gui = newPrompt()
        local clicked
        prompt:Show({
            {
                text = "Kira came online.",
                buttons = { { text = "Greet", onClick = function() clicked = "greet" end } },
            },
            { text = "Mike joined the guild.", buttons = { { text = "Welcome", onClick = function() end } } },
            { buttons = { { text = "Dismiss", onClick = function() end } } },
        })
        local window = gui.created[1]
        assert.are.equal("Window", window.kind)
        assert.are.equal("Hello", window.title)
        local kinds = {}
        for _, child in ipairs(window.children) do
            table.insert(kinds, child.kind .. ":" .. child.text)
        end
        assert.are.same({ "Label:Kira came online.", "Button:Greet", "Label:Mike joined the guild.",
            "Button:Welcome", "Button:Dismiss" }, kinds)
        window.children[2].callbacks.OnClick()
        assert.are.equal("greet", clicked)
        prompt:Show({ { text = "Zel and Kira came online." } })
        assert.are.equal(1, #window.children)
        assert.are.equal("Zel and Kira came online.", window.children[1].text)
        assert.is_true(prompt:IsShown())
    end)

    it("runs onClose when the player closes it, but not when hidden by code", function()
        local closed = 0
        local prompt, gui = newPrompt(function() closed = closed + 1 end)
        prompt:Show({ { text = "x" } })
        prompt:Hide()
        assert.are.equal(0, closed)
        assert.is_false(prompt:IsShown())
        prompt:Show({ { text = "y" } })
        local window
        for _, widget in ipairs(gui.created) do
            if widget.kind == "Window" then
                window = widget
            end
        end
        window.callbacks.OnClose(window)
        assert.are.equal(1, closed)
        assert.is_false(prompt:IsShown())
    end)
end)
