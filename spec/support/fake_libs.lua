-- Fake embedded libraries for the harness. Each records how the add-on used it,
-- so specs can check the wiring without loading the real Ace3 stack (which
-- needs frames). Only the calls the add-on makes are faked.

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
        function object:RegisterEvent(event, method)
            self.events[event] = method
        end
        function object:Print(message)
            table.insert(self.printed, message)
        end
        log.addon = object
        return object
    end
    return aceAddon
end

-- Returns a LibStub stand-in and the log it records into. `log.addon` is the
-- object AceAddon created, `log.db` the AceDB instance, and so on.
function FakeLibs.new()
    local log = { options = {}, launchers = {}, icons = {} }
    local libs = {
        ["AceAddon-3.0"] = newAceAddon(log),
        ["AceGUI-3.0"] = newAceGUI(log),
        ["AceDB-3.0"] = {
            New = function(_, savedVariable, defaults)
                log.db = {
                    savedVariable = savedVariable,
                    profile = { minimap = defaults.profile.minimap },
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
