local _, addon = ...

-- Keeps records in step between add-on users in one guild. Transport-agnostic:
-- `deps.send` delivers a message to the guild channel. Record types plug in
-- through RegisterType without touching the exchange:
--
--   1. digest   (broadcast) one hash per record type, sent after login and
--               occasionally afterwards, jittered and rate-limited.
--   2. versions (reply)     a peer whose hash differs lists its record versions
--               for that type. Replies wait a random backoff, and a peer that
--               sees someone else answer the same need stays quiet.
--   3. records / want       the digest sender sends records the peer lacks or
--               has older, and asks ("want") for the ones it lacks itself.
--
-- Every message goes to the guild channel and carries `to` when it is meant
-- for one peer, so other peers can see a need was answered and also merge any
-- records they overhear.
local Sync = {}
Sync.__index = Sync
addon.Sync = Sync

-- Seconds after Start before the first digest, as { min, max }.
Sync.FIRST_DIGEST_DELAY = { 5, 15 }
-- Seconds between later digests, as { min, max }.
Sync.DIGEST_INTERVAL = { 1500, 2100 }
-- Never send digests closer together than this many seconds.
Sync.MIN_DIGEST_GAP = 300
-- Backoff before answering someone's digest, as { min, max } seconds.
Sync.ANSWER_DELAY = { 1, 4 }

-- `deps`:
--   send(message, priority)  send to the guild; priority "NORMAL" or "BULK"
--   after(seconds, fn)       run fn later
--   random()                 a number in [0, 1)
--   now()                    current time in seconds
--   player                   this character's key
--   enabled()                whether sync is turned on
function Sync.New(deps)
    return setmetatable({ deps = deps, types = {}, typeOrder = {}, pending = {} }, Sync)
end

-- `handler`:
--   Versions() -> { id = version }  records this client can share
--   Get(id) -> record
--   Receive(id, record, sender) -> accepted
--   Commit()                         optional; runs after a batch with accepted records
function Sync:RegisterType(name, handler)
    self.types[name] = handler
    table.insert(self.typeOrder, name)
    table.sort(self.typeOrder)
end

local function between(deps, range)
    return range[1] + deps.random() * (range[2] - range[1])
end

-- An order-independent hash of a versions table.
function Sync.Hash(versions)
    local ids = {}
    for id in pairs(versions) do
        table.insert(ids, id)
    end
    table.sort(ids)
    local hash = 5381
    for _, id in ipairs(ids) do
        local text = id .. "=" .. tostring(versions[id]) .. ";"
        for i = 1, #text do
            hash = (hash * 33 + text:byte(i)) % 4294967296
        end
    end
    return hash
end

function Sync:Digest()
    local hashes = {}
    for _, name in ipairs(self.typeOrder) do
        hashes[name] = Sync.Hash(self.types[name].Versions())
    end
    return hashes
end

function Sync:Send(kind, data, priority)
    self.deps.send(addon.Protocol.Encode(kind, data), priority)
end

-- Sends a digest unless sync is off or one went out recently.
function Sync:SendDigest()
    local now = self.deps.now()
    if not self.deps.enabled() or (self.lastDigest and now - self.lastDigest < Sync.MIN_DIGEST_GAP) then
        return
    end
    self.lastDigest = now
    self:Send("digest", { h = self:Digest() }, "NORMAL")
end

-- Starts the digest schedule: one shortly after, then periodically.
function Sync:Start()
    if self.started then
        return
    end
    self.started = true
    local function tick()
        if self.stopped then
            return
        end
        self:SendDigest()
        self.deps.after(between(self.deps, Sync.DIGEST_INTERVAL), tick)
    end
    self.deps.after(between(self.deps, Sync.FIRST_DIGEST_DELAY), tick)
end

-- Stops all sending, e.g. after leaving the guild.
function Sync:Stop()
    self.stopped = true
end

function Sync:SendRecords(typeName, ids)
    local handler = self.types[typeName]
    local records = {}
    for _, id in ipairs(ids) do
        local record = handler.Get(id)
        if record then
            records[id] = record
        end
    end
    for _, batch in ipairs(addon.Protocol.Batch(records)) do
        self:Send("records", { t = typeName, r = batch }, "BULK")
    end
end

function Sync:OnDigest(data, sender)
    if type(data.h) ~= "table" then
        return
    end
    for _, name in ipairs(self.typeOrder) do
        local theirs = data.h[name]
        if theirs ~= nil and theirs ~= Sync.Hash(self.types[name].Versions()) then
            local need = sender .. "\0" .. name
            if not self.pending[need] then
                self.pending[need] = true
                self.deps.after(between(self.deps, Sync.ANSWER_DELAY), function()
                    if self.pending[need] and not self.stopped and self.deps.enabled() then
                        self.pending[need] = nil
                        self:Send("versions", { to = sender, t = name, v = self.types[name].Versions() }, "NORMAL")
                    end
                end)
            end
        end
    end
end

function Sync:OnVersions(data, sender)
    local handler = type(data.t) == "string" and self.types[data.t]
    if not handler or type(data.to) ~= "string" or type(data.v) ~= "table" then
        return
    end
    -- Someone answered this need; don't answer it too.
    self.pending[data.to .. "\0" .. data.t] = nil
    if data.to ~= self.deps.player then
        return
    end
    local mine = handler.Versions()
    local give, want = {}, {}
    for id, version in pairs(mine) do
        local theirs = data.v[id]
        if type(theirs) ~= "number" or version > theirs then
            table.insert(give, id)
        end
    end
    for id, theirs in pairs(data.v) do
        if type(theirs) == "number" and (mine[id] == nil or theirs > mine[id]) then
            table.insert(want, id)
        end
    end
    table.sort(give)
    table.sort(want)
    self:SendRecords(data.t, give)
    if #want > 0 then
        self:Send("want", { to = sender, t = data.t, ids = want }, "NORMAL")
    end
end

function Sync:OnWant(data)
    if data.to ~= self.deps.player or type(data.t) ~= "string" or not self.types[data.t]
        or type(data.ids) ~= "table" then
        return
    end
    local ids = {}
    for _, id in ipairs(data.ids) do
        if type(id) == "string" then
            table.insert(ids, id)
        end
    end
    self:SendRecords(data.t, ids)
end

function Sync:OnRecords(data, sender)
    local handler = type(data.t) == "string" and self.types[data.t]
    if not handler or type(data.r) ~= "table" then
        return
    end
    local accepted = false
    for id, record in pairs(data.r) do
        if handler.Receive(id, record, sender) then
            accepted = true
        end
    end
    if accepted and handler.Commit then
        handler.Commit()
    end
end

-- Handles one message from the guild channel. `sender` is the sender's key.
-- Our own messages, unknown kinds or types, and anything while sync is off are
-- ignored.
function Sync:OnMessage(message, sender)
    if self.stopped or not self.deps.enabled() or sender == self.deps.player then
        return
    end
    local kind, data = addon.Protocol.Decode(message)
    if kind == "digest" then
        self:OnDigest(data, sender)
    elseif kind == "versions" then
        self:OnVersions(data, sender)
    elseif kind == "want" then
        self:OnWant(data)
    elseif kind == "records" then
        self:OnRecords(data, sender)
    end
end
