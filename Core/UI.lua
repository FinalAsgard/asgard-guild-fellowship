local _, addon = ...

-- The internal UI layer. It is the only code that talks to AceGUI: feature code
-- builds screens through it, so a future custom skin replaces just this file.
-- Settings are not built here; they stay in AceConfig (see Options).
local UI = {}
addon.UI = UI

local function aceGUI()
    return LibStub("AceGUI-3.0")
end

local Window = {}
Window.__index = Window

-- A top-level window with a scrolling column of content. It is built when
-- shown and released when closed, so a closed window holds no frames.
-- `options`: title, width, height, and render(window), which fills the window
-- each time it is shown or refreshed.
function UI.Window(options)
    return setmetatable({ options = options }, Window)
end

function Window:Show()
    if self.frame then
        return
    end
    local frame = aceGUI():Create("Frame")
    frame:SetTitle(self.options.title)
    frame:SetWidth(self.options.width)
    frame:SetHeight(self.options.height)
    frame:SetLayout("Fill")
    frame:SetCallback("OnClose", function(widget)
        self.frame = nil
        self.content = nil
        aceGUI():Release(widget)
    end)
    local content = aceGUI():Create("ScrollFrame")
    content:SetLayout("List")
    frame:AddChild(content)
    self.frame = frame
    self.content = content
    self:Refresh()
end

-- Rebuilds the content with `render`, if the window is open.
function Window:Refresh()
    if self.content and self.options.render then
        self.content:ReleaseChildren()
        self.options.render(self)
    end
end

function Window:Hide()
    if self.frame then
        -- Hiding fires OnClose, which releases the frame.
        self.frame:Hide()
    end
end

function Window:IsShown()
    return self.frame ~= nil
end

function Window:Toggle()
    if self:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function Window:AddHeading(text)
    local heading = aceGUI():Create("Heading")
    heading:SetText(text)
    heading:SetFullWidth(true)
    self.content:AddChild(heading)
end

-- A full-width line of text. `color` is { r, g, b } or nil for the default.
function Window:AddText(text, color)
    local label = aceGUI():Create("Label")
    label:SetText(text)
    label:SetFullWidth(true)
    if color then
        label:SetColor(color[1], color[2], color[3])
    end
    self.content:AddChild(label)
end

-- A button. `onClick` runs when pressed; a disabled button can't be pressed.
function Window:AddButton(text, onClick, disabled)
    local button = aceGUI():Create("Button")
    button:SetText(text)
    button:SetDisabled(disabled == true)
    button:SetCallback("OnClick", function()
        onClick()
    end)
    self.content:AddChild(button)
end
