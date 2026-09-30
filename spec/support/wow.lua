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
--   globals    extra globals, e.g. another add-on's SLASH_ entries or a fake LibStub
function Harness.new(options)
    options = options or {}
    local self = setmetatable({ namespace = {}, options = options }, Harness)
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

-- Loads several files in order.
function Harness:loadAll(paths)
    for _, path in ipairs(paths) do
        self:load(path)
    end
    return self.namespace
end

return Harness
