local _, addon = ...

-- Reads the guild roster into plain snapshots for IdentityStore. Event-driven:
-- Core forwards GUILD_ROSTER_UPDATE here. Bursts of updates are debounced into
-- one snapshot, and roster requests to the server are throttled.
local RosterAdapter = {}
RosterAdapter.__index = RosterAdapter
addon.RosterAdapter = RosterAdapter

-- Minimum seconds between roster requests to the server.
RosterAdapter.REQUEST_INTERVAL = 15
-- Seconds to wait for more roster updates before building a snapshot.
RosterAdapter.DEBOUNCE = 1

-- `onSnapshot(snapshot)` receives each new snapshot.
function RosterAdapter.New(onSnapshot)
    return setmetatable({ onSnapshot = onSnapshot }, RosterAdapter)
end

-- Requests fresh roster data unless one was requested recently.
function RosterAdapter:Request()
    local now = GetTime()
    if self.lastRequest and now - self.lastRequest < RosterAdapter.REQUEST_INTERVAL then
        return
    end
    self.lastRequest = now
    addon.Compat.RequestGuildRoster()
end

-- GUILD_ROSTER_UPDATE. `canRequestRosterUpdate` means the server has changes
-- (such as an edited note) to send when asked.
function RosterAdapter:OnRosterUpdate(canRequestRosterUpdate)
    if canRequestRosterUpdate then
        self:Request()
    end
    if self.pending then
        return
    end
    self.pending = true
    C_Timer.After(RosterAdapter.DEBOUNCE, function()
        self.pending = false
        local snapshot = RosterAdapter.BuildSnapshot()
        -- An empty roster means the data hasn't arrived yet, not that everyone left.
        if #snapshot > 0 then
            self.onSnapshot(snapshot)
        end
    end)
end

-- One entry per member: key, name (no realm), guid, rankIndex, class (token),
-- className (localized), level, online, zone, note (the public note).
function RosterAdapter.BuildSnapshot()
    local snapshot = {}
    for index = 1, GetNumGuildMembers() do
        local fullName, _, rankIndex, level, className, zone, publicNote, _, isOnline, _, class,
            _, _, _, _, _, guid = GetGuildRosterInfo(index)
        local key = fullName and addon.Compat.NormalizeName(fullName)
        if key then
            table.insert(snapshot, {
                key = key,
                name = addon.Compat.NameFromKey(key),
                guid = guid,
                rankIndex = rankIndex,
                class = class,
                className = className,
                level = level,
                online = isOnline and true or false,
                zone = zone,
                note = publicNote or "",
            })
        end
    end
    return snapshot
end
