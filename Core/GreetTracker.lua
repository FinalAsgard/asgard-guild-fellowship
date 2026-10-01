local _, addon = ...

-- Works out who just came online, per person rather than per character. Pure:
-- the caller passes in roster snapshots, how to find a character's person,
-- and the time.
local GreetTracker = {}
GreetTracker.__index = GreetTracker
addon.GreetTracker = GreetTracker

-- Seconds someone must have been offline before coming back counts as a new arrival.
GreetTracker.RETURN_WINDOW = 1800

function GreetTracker.New()
    local tracker = setmetatable({}, GreetTracker)
    tracker:Reset()
    return tracker
end

-- Forgets who was online, so the next snapshot is a fresh baseline (after
-- login, a guild change, or turning greeting on).
function GreetTracker:Reset()
    self.baselined = false
    self.online = {}
    self.lastSeen = {}
end

-- Observes a roster snapshot taken at time `now` and returns the arrivals: a
-- list of { personId, member } for people who came online, in roster order.
--   personOf(charKey) -> person id, or nil for a character identity doesn't know
--     (it is then tracked under its own key)
--   selfPersonId: this player's person, never an arrival
-- Nobody arrives in the first snapshot after a reset, nobody arrives by
-- switching alts, and nobody arrives within RETURN_WINDOW of last being online.
function GreetTracker:Observe(snapshot, personOf, now, selfPersonId)
    local online, order = {}, {}
    for _, member in ipairs(snapshot) do
        if member.online then
            local personId = personOf(member.key) or member.key
            if not online[personId] then
                online[personId] = member
                table.insert(order, personId)
            end
        end
    end

    local arrivals = {}
    if self.baselined then
        for _, personId in ipairs(order) do
            local lastSeen = self.lastSeen[personId]
            if not self.online[personId] and personId ~= selfPersonId
                and (not lastSeen or now - lastSeen >= GreetTracker.RETURN_WINDOW) then
                table.insert(arrivals, { personId = personId, member = online[personId] })
            end
        end
    end

    for personId in pairs(online) do
        self.lastSeen[personId] = now
    end
    self.online = online
    self.baselined = true
    return arrivals
end
