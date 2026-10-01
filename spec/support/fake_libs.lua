-- Fake embedded libraries for the harness. Each records how the add-on used it,
-- so specs can check the wiring without loading the real Ace3 stack (which
-- needs frames). Only the calls the add-on makes are faked.

local realLibs = require("support.real_libs")

local FakeLibs = {}

local function newAceGUI(log)
    local gui = { created = {}, released = {} }
    function gui.Create(_, kind)
        local widget = { kind = kind, callbacks = {} }
        function widget:SetTitle(title) self.title = title end
        function widget:SetWidth(width) self.width = width end
        function widget:SetHeight(height) self.height = height end
        function widget:SetLayout(layout) self.layout = layout end
        function widget:SetCallback(name, fn) self.callbacks[name] = fn end
        function widget:SetText(text) self.text = text end
        function widget:SetFullWidth(full) self.fullWidth = full end
        function widget:SetColor(r, g, b) self.color = { r, g, b } end
        function widget:SetDisabled(disabled) self.disabled = disabled end
        function widget:AddChild(child)
            self.children = self.children or {}
            table.insert(self.children, child)
        end
        function widget:ReleaseChildren() self.children = {} end
        function widget:SetLabel(label) self.label = label end
        function widget:SetList(list, order) self.list, self.order = list, order end
        function widget:SetValue(value) self.value = value end
        function widget:SetStatusTable(status) self.status = status end
        function widget:Hide()
            -- Like AceGUI's Frame, hiding fires OnClose.
            if self.callbacks.OnClose then
                self.callbacks.OnClose(self)
            end
        end
        table.insert(gui.created, widget)
        return widget
    end
    function gui.Release(_, widget)
        table.insert(gui.released, widget)
    end
    log.AceGUI = gui
    return gui
end

local function newAceAddon(log)
    local aceAddon = {}
    function aceAddon.NewAddon(_, name)
        local object = { name = name, commands = {}, events = {}, printed = {} }
        function object:RegisterChatCommand(command, method)
            self.commands[command] = method
        end
        object.comms, object.sent = {}, {}
        function object:RegisterComm(prefix, method)
            self.comms[prefix] = method
        end
        function object:SendCommMessage(prefix, message, distribution, target, priority)
            table.insert(self.sent, {
                prefix = prefix, message = message, distribution = distribution, target = target, priority = priority,
            })
        end
        function object:RegisterEvent(event, method)
            self.events[event] = method
        end
        function object:UnregisterEvent(event)
            self.events[event] = nil
        end
        function object:Print(message)
            table.insert(self.printed, message)
        end
        log.addon = object
        return object
    end
    return aceAddon
end

-- Like CallbackHandler-1.0: embeds RegisterCallback/UnregisterCallback in the
-- target and returns a registry with Fire. Handlers are a function, or a
-- method name on the registering owner.
local CallbackHandler = {}
function CallbackHandler.New(_, target)
    local handlers = {}
    local registry = {}
    function registry.Fire(_, event, ...)
        for owner, handler in pairs(handlers[event] or {}) do
            if type(handler) == "string" then
                owner[handler](owner, event, ...)
            else
                handler(event, ...)
            end
        end
    end
    function target.RegisterCallback(owner, event, handler)
        handlers[event] = handlers[event] or {}
        handlers[event][owner] = handler or event
    end
    function target.UnregisterCallback(owner, event)
        if handlers[event] then
            handlers[event][owner] = nil
        end
    end
    return registry
end

-- Returns a LibStub stand-in and the log it records into. `log.addon` is the
-- object AceAddon created, `log.db` the AceDB instance, and so on.
function FakeLibs.new()
    local log = { options = {}, launchers = {}, icons = {} }
    local libs = {
        ["AceAddon-3.0"] = newAceAddon(log),
        ["AceGUI-3.0"] = newAceGUI(log),
        ["CallbackHandler-1.0"] = CallbackHandler,
        -- The serializer and compressor are pure Lua, so specs use the real ones.
        ["AceSerializer-3.0"] = realLibs()["AceSerializer-3.0"],
        LibDeflate = realLibs().LibDeflate,
        ["AceDB-3.0"] = {
            New = function(_, savedVariable, defaults)
                -- A deep copy, like the fresh profile AceDB builds from defaults.
                local function copy(value)
                    if type(value) ~= "table" then
                        return value
                    end
                    local result = {}
                    for key, inner in pairs(value) do
                        result[key] = copy(inner)
                    end
                    return result
                end
                log.db = {
                    savedVariable = savedVariable,
                    profile = copy(defaults.profile),
                    global = {},
                }
                return log.db
            end,
        },
        ["AceConfig-3.0"] = {
            RegisterOptionsTable = function(_, name, options)
                log.options.registered = { name = name, table = options }
            end,
        },
        ["AceConfigDialog-3.0"] = {
            AddToBlizOptions = function(_, name, title)
                log.options.blizzard = { name = name, title = title }
            end,
        },
        ["LibDataBroker-1.1"] = {
            NewDataObject = function(_, name, object)
                log.launchers[name] = object
                return object
            end,
        },
        ["LibDBIcon-1.0"] = {
            Register = function(_, name, object, settings)
                log.icons[name] = { object = object, settings = settings }
            end,
        },
    }
    local LibStub = setmetatable({}, {
        __call = function(_, name)
            return assert(libs[name], "library not faked: " .. name)
        end,
    })
    return LibStub, log
end

return FakeLibs
