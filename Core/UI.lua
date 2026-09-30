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

-- A top-level window. It is built when shown and released when closed, so a
-- closed window holds no frames. `options`: title, width, height.
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
    frame:SetLayout("Flow")
    frame:SetCallback("OnClose", function(widget)
        self.frame = nil
        aceGUI():Release(widget)
    end)
    self.frame = frame
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
