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

-- A labelled dropdown. `choices` is a list of { value, text } in display order;
-- `onChange(value)` runs when the selection changes.
function Window:AddDropdown(label, choices, selected, onChange)
    local dropdown = aceGUI():Create("Dropdown")
    local list, order = {}, {}
    for _, choice in ipairs(choices) do
        list[choice.value] = choice.text
        table.insert(order, choice.value)
    end
    dropdown:SetLabel(label)
    dropdown:SetList(list, order)
    if selected ~= nil then
        dropdown:SetValue(selected)
    end
    dropdown:SetCallback("OnValueChanged", function(_, _, value)
        onChange(value)
    end)
    self.content:AddChild(dropdown)
end

-- A labelled checkbox. `onChange(checked)` runs when the player ticks or unticks it.
function Window:AddCheckBox(label, checked, onChange)
    local checkbox = aceGUI():Create("CheckBox")
    checkbox:SetLabel(label)
    checkbox:SetValue(checked == true)
    checkbox:SetCallback("OnValueChanged", function(_, _, value)
        onChange(value == true)
    end)
    self.content:AddChild(checkbox)
end

-- A labelled one-line text box. `onChange(text)` runs when the player presses
-- Enter or the Okay button.
function Window:AddInput(label, text, onChange)
    local input = aceGUI():Create("EditBox")
    input:SetLabel(label)
    input:SetText(text or "")
    input:SetCallback("OnEnterPressed", function(_, _, value)
        onChange(value)
    end)
    self.content:AddChild(input)
end

local Prompt = {}
Prompt.__index = Prompt

-- A small pop-up with a line of text and buttons, e.g. a greeting prompt.
-- `options`: title, width, height, and optionally status() returning a saved
-- table where the prompt keeps its position. Closing it with its X counts as
-- dismissing, and runs options.onClose.
function UI.Prompt(options)
    return setmetatable({ options = options }, Prompt)
end

-- Shows (or replaces) the prompt's content: a list of rows, each with an
-- optional line of text and a list of buttons ({ text, onClick }).
function Prompt:Show(rows)
    if not self.frame then
        local frame = aceGUI():Create("Window")
        frame:SetTitle(self.options.title)
        if self.options.status then
            frame:SetStatusTable(self.options.status())
        end
        frame:SetWidth(self.options.width)
        frame:SetHeight(self.options.height)
        frame:SetLayout("Flow")
        frame:SetCallback("OnClose", function(widget)
            self.frame = nil
            aceGUI():Release(widget)
            if self.options.onClose and not self.hiding then
                self.options.onClose()
            end
        end)
        self.frame = frame
    end
    self.frame:ReleaseChildren()
    for _, row in ipairs(rows) do
        if row.text then
            local label = aceGUI():Create("Label")
            label:SetText(row.text)
            label:SetFullWidth(true)
            self.frame:AddChild(label)
        end
        for _, spec in ipairs(row.buttons or {}) do
            local button = aceGUI():Create("Button")
            button:SetText(spec.text)
            button:SetCallback("OnClick", function()
                spec.onClick()
            end)
            self.frame:AddChild(button)
        end
    end
end

-- Hides the prompt without running onClose.
function Prompt:Hide()
    if self.frame then
        self.hiding = true
        self.frame:Hide()
        self.hiding = false
    end
end

function Prompt:IsShown()
    return self.frame ~= nil
end
