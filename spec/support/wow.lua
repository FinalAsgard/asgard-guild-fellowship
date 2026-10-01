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
--   roster     guild members: { name, guid, rankIndex, level, class, className, zone, note, online }
--              (name as GetGuildRosterInfo reports it, with or without realm)
--   canEditPublicNote  whether CanEditPublicNote() is true
--   ranks      guild ranks in order (guild master first): { name, canEditOfficerNote }
--   units      unit tokens the client knows: { mouseover = { name = ..., realm = ..., player = true } }
--   globals    extra globals, e.g. another add-on's SLASH_ entries or a fake LibStub
--
-- The harness also keeps a clock (`advance`), records roster requests
-- (`rosterRequests`), runs registered chat filters (`chat`), and fakes
-- GameTooltip (`hoverUnit`, `hoverRosterRow`).
function Harness.new(options)
    options = options or {}
    local self = setmetatable({
        namespace = {},
        options = options,
        now = 0,
        timers = {},
        rosterRequests = 0,
        notesWritten = {},
        chatSent = {},
        chatFilters = {},
        unitTooltipPostCalls = {},
    }, Harness)
    local tooltip = self:newTooltip()
    self.tooltip = tooltip
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
        GetServerTime = function()
            return 0
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
            -- Writes a public note into the stub roster, as the server would.
            SetNote = function(guid, text, isPublic)
                table.insert(self.notesWritten, { guid = guid, text = text, isPublic = isPublic })
                for _, m in ipairs(options.roster or {}) do
                    if m.guid == guid and isPublic then
                        m.note = text
                    end
                end
            end,
            GuildControlGetRankFlags = function(order)
                local rank = (options.ranks or {})[order]
                return rank and { [12] = rank.canEditOfficerNote == true }
            end,
        },
        ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online.",
        SendChatMessage = function(text, channel)
            table.insert(self.chatSent, { text = text, channel = channel })
        end,
        CanEditPublicNote = function()
            return options.canEditPublicNote == true
        end,
        GuildControlGetNumRanks = function()
            return #(options.ranks or {})
        end,
        GuildControlGetRankName = function(order)
            local rank = (options.ranks or {})[order]
            return rank and rank.name
        end,
        GetNumGuildMembers = function()
            return #(options.roster or {})
        end,
        GetGuildRosterInfo = function(index)
            local m = (options.roster or {})[index]
            if m then
                return m.name, "Rank", m.rankIndex, m.level, m.className or m.class, m.zone, m.note, "", m.online, 0,
                    m.class,
                    0, 0, false, false, 0, m.guid
            end
        end,
        Enum = { TooltipDataType = { Unit = 2 } },
        TooltipDataProcessor = {
            AddTooltipPostCall = function(dataType, callback)
                if dataType == 2 then
                    table.insert(self.unitTooltipPostCalls, callback)
                end
            end,
        },
        GameTooltip = tooltip,
        hooksecurefunc = function(target, method, hook)
            local original = target[method]
            target[method] = function(...)
                local results = { original(...) }
                hook(...)
                return unpack(results)
            end
        end,
        UnitIsPlayer = function(unit)
            local info = (options.units or {})[unit]
            return info ~= nil and info.player == true
        end,
        UnitName = function(unit)
            local info = (options.units or {})[unit]
            if info then
                return info.name, info.realm
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

-- A fake tooltip that records its lines. Show and OnTooltipCleared behave like
-- GameTooltip's: Show can be hooked, and clearing runs OnTooltipCleared scripts.
function Harness.newTooltip()
    local tooltip = { lines = {}, scripts = {}, shows = 0 }
    function tooltip:AddLine(text, r, g, b)
        table.insert(self.lines, { left = text, color = { r, g, b } })
    end
    function tooltip:AddDoubleLine(left, right, r, g, b)
        table.insert(self.lines, { left = left, right = right, color = { r, g, b } })
    end
    function tooltip:Show()
        self.shows = self.shows + 1
    end
    function tooltip:GetOwner()
        return self.owner
    end
    function tooltip:GetUnit()
        return self.unit and "name", self.unit
    end
    function tooltip:HookScript(script, handler)
        self.scripts[script] = self.scripts[script] or {}
        table.insert(self.scripts[script], handler)
    end
    function tooltip:SetOwner(owner)
        self.owner = owner
        self.unit = nil
        self.lines = {}
        for _, handler in ipairs(self.scripts.OnTooltipCleared or {}) do
            handler(self)
        end
    end
    return tooltip
end

-- Shows GameTooltip for `unit` the way the client does, running unit
-- post-calls. Returns the tooltip's lines.
function Harness:hoverUnit(unit)
    local tooltip = self.tooltip
    tooltip:SetOwner({})
    tooltip.unit = unit
    for _, callback in ipairs(self.unitTooltipPostCalls) do
        callback(tooltip, {})
    end
    tooltip:Show()
    return tooltip.lines
end

-- Shows GameTooltip for a guild roster row whose member info is `memberInfo`,
-- the way the row's OnEnter does. Returns the tooltip's lines.
function Harness:hoverRosterRow(memberInfo)
    local tooltip = self.tooltip
    tooltip:SetOwner({
        GetMemberInfo = function()
            return memberInfo
        end,
    })
    tooltip:AddLine(memberInfo.name)
    tooltip:Show()
    return tooltip.lines
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
