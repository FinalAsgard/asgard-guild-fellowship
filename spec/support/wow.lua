-- A minimal stand-in for the WoW client. It loads add-on files the way the game
-- does (called with the add-on name and a shared namespace table) inside an
-- isolated global environment holding only the APIs the add-on actually calls.
-- Add a stub here only when add-on code starts calling that API.

local ADDON = "AsgardsGuildFellowship"

local Harness = {}
Harness.__index = Harness

-- `options`:
--   client     manifest X-Client value ("Forever" or "Retail"), default "Retail"
--   version    manifest Version value
--   realm      what GetNormalizedRealmName returns
--   guild      { name = ..., realm = ... } when the player is in a guild
--   roster     guild members: { name, guid, rankIndex, level, class, zone, note, online }
--              (name as GetGuildRosterInfo reports it, with or without realm)
--   globals    extra globals, e.g. another add-on's SLASH_ entries or a fake LibStub
--
-- The harness also keeps a clock (`advance`), records roster requests
-- (`rosterRequests`), and runs registered chat filters (`chat`).
function Harness.new(options)
    options = options or {}
    local self = setmetatable({
        namespace = {},
        options = options,
        now = 0,
        timers = {},
        rosterRequests = 0,
        chatFilters = {},
    }, Harness)
    local metadata = {
        Version = options.version or "1.2.3",
        ["X-Client"] = options.client or "Retail",
    }
    local env = {
        C_AddOns = {
            GetAddOnMetadata = function(addonName, field)
                if addonName == ADDON then
                    return metadata[field]
                end
            end,
        },
        GetNormalizedRealmName = function()
            return options.realm
        end,
        IsInGuild = function()
            return options.guild ~= nil
        end,
        GetGuildInfo = function(unit)
            if unit == "player" and options.guild then
                return options.guild.name, "Member", 3, options.guild.realm
            end
        end,
        GetTime = function()
            return self.now
        end,
        C_Timer = {
            After = function(delay, callback)
                table.insert(self.timers, { at = self.now + delay, callback = callback })
            end,
        },
        C_GuildInfo = {
            GuildRoster = function()
                self.rosterRequests = self.rosterRequests + 1
            end,
        },
        GetNumGuildMembers = function()
            return #(options.roster or {})
        end,
        GetGuildRosterInfo = function(index)
            local m = (options.roster or {})[index]
            if m then
                return m.name, "Rank", m.rankIndex, m.level, m.class, m.zone, m.note, "", m.online, 0, m.class,
                    0, 0, false, false, 0, m.guid
            end
        end,
        ChatFrame_AddMessageEventFilter = function(event, filter)
            self.chatFilters[event] = self.chatFilters[event] or {}
            table.insert(self.chatFilters[event], filter)
        end,
    }
    for name, value in pairs(options.globals or {}) do
        env[name] = value
    end
    -- Lua built-ins (pairs, type, setmetatable, ...) still resolve.
    setmetatable(env, { __index = _G })
    env._G = env
    self.env = env
    return self
end

-- Loads one add-on file, e.g. "Core/Compat.lua", and returns the namespace.
function Harness:load(path)
    local chunk = assert(loadfile(path))
    setfenv(chunk, self.env)
    chunk(ADDON, self.namespace)
    return self.namespace
end

-- Moves the clock forward, running every timer that comes due.
function Harness:advance(seconds)
    self.now = self.now + seconds
    local due, waiting = {}, {}
    for _, timer in ipairs(self.timers) do
        table.insert(timer.at <= self.now and due or waiting, timer)
    end
    self.timers = waiting
    for _, timer in ipairs(due) do
        timer.callback()
    end
end

-- Delivers a chat event through the registered filters the way the chat frame
-- does. Returns the message and author as displayed, or nil if a filter hid it.
function Harness:chat(event, message, author, ...)
    local args = { message, author, ... }
    for _, filter in ipairs(self.chatFilters[event] or {}) do
        local results = { filter({}, event, unpack(args)) }
        if results[1] then
            return nil
        end
        if results[2] ~= nil then
            args = { unpack(results, 2) }
        end
    end
    return args[1], args[2]
end

-- Loads several files in order.
function Harness:loadAll(paths)
    for _, path in ipairs(paths) do
        self:load(path)
    end
    return self.namespace
end

return Harness
