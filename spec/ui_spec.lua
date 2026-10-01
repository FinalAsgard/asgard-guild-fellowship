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
    end)
end)
