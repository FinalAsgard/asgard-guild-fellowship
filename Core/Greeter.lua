local _, addon = ...

-- Guild Greet: when guildmates come online, offers this player a prompt to
-- greet them. Greetings are only sent when the player clicks Greet, since the
-- game only lets add-ons post chat in response to a player action.
local Greeter = {}
Greeter.__index = Greeter
addon.Greeter = Greeter

-- Seconds an unanswered prompt stays up after its last new arrival.
Greeter.PROMPT_TIMEOUT = 120
-- How many players may greet the same arrival. Two feels friendly; more is spam.
Greeter.MAX_GREETERS = 2
-- Seconds a greeting announcement counts toward that limit for the arrival.
Greeter.CLAIM_WINDOW = 300

-- `deps`:
--   identity()   the current IdentityStore, or nil outside a guild
--   playerKey()  this character's key
--   settings()   the profile's greet settings ({ enabled, messages, prompt })
--   send(text)   posts a line in guild chat
--   random(n)    an integer from 1 to n
--   now()        current time in seconds
--   after(s, fn) runs fn after s seconds
--   inCombat()   whether the player is in combat
--   announce(personIds)  tells other add-on users who this player greeted
--                        (a no-op when sync is off)
function Greeter.New(deps)
    local greeter = setmetatable({
        deps = deps,
        tracker = addon.GreetTracker.New(),
        pending = {},
        generation = 0,
        -- claims[personId][greeter] = when they announced greeting that person.
        claims = {},
    }, Greeter)
    greeter.prompt = addon.UI.Prompt({
        title = "Guild Greet",
        width = 320,
        height = 120,
        -- Remembers where the player drags it.
        status = function()
            return deps.settings().prompt
        end,
        onClose = function()
            greeter:Dismiss()
        end,
    })
    return greeter
end

-- Starts over: the next snapshot is a baseline and any prompt is cleared.
-- Called on guild changes and when greeting is turned on or off.
function Greeter:Reset()
    self.tracker:Reset()
    self:Dismiss()
end

local function names(pending)
    local result = {}
    for _, arrival in ipairs(pending) do
        table.insert(result, arrival.name)
    end
    return result
end

-- Feeds a roster snapshot. New arrivals join the prompt.
function Greeter:OnSnapshot(snapshot)
    local store = self.deps.identity()
    if not store or not self.deps.settings().enabled then
        return
    end
    local function personOf(charKey)
        local person = store:GetPerson(charKey)
        return person and person.id
    end
    local playerKey = self.deps.playerKey()
    local now = self.deps.now()
    local arrivals = self.tracker:Observe(snapshot, personOf, now, personOf(playerKey) or playerKey)
    local added = false
    for _, arrival in ipairs(arrivals) do
        if self:Greeters(arrival.personId) < Greeter.MAX_GREETERS then
            table.insert(self.pending, {
                personId = arrival.personId,
                name = store:GetDisplayName(arrival.personId) or arrival.member.name,
                at = now,
            })
            added = true
        end
    end
    if added then
        self:ShowPrompt()
    end
end

-- How many players recently announced greeting `personId`.
function Greeter:Greeters(personId)
    local greeters = self.claims[personId]
    if not greeters then
        return 0
    end
    local now, count = self.deps.now(), 0
    for greeter, at in pairs(greeters) do
        if now - at < Greeter.CLAIM_WINDOW then
            count = count + 1
        else
            greeters[greeter] = nil
        end
    end
    return count
end

-- Another add-on user announced greeting `personIds`. People who now have
-- MAX_GREETERS greetings leave this player's prompt; an emptied prompt closes.
function Greeter:OnClaim(personIds, sender)
    if type(personIds) ~= "table" or type(sender) ~= "string" then
        return
    end
    local now, changed = self.deps.now(), false
    for index, personId in ipairs(personIds) do
        if index > 50 then
            break
        end
        if type(personId) == "string" then
            self.claims[personId] = self.claims[personId] or {}
            self.claims[personId][sender] = now
        end
    end
    local kept = {}
    for _, arrival in ipairs(self.pending) do
        if self:Greeters(arrival.personId) < Greeter.MAX_GREETERS then
            table.insert(kept, arrival)
        else
            changed = true
        end
    end
    if not changed then
        return
    end
    if #kept == 0 then
        self:Dismiss()
    else
        self.pending = kept
        if self.prompt:IsShown() then
            self:ShowPrompt(true)
        end
    end
end

-- Shows (or updates) the prompt for everyone waiting, unless the player is in
-- combat, in which case it waits for OnCombatEnded. Each update restarts the
-- timeout, except when `keepTimeout` (someone was removed, not added).
function Greeter:ShowPrompt(keepTimeout)
    if #self.pending == 0 or self.deps.inCombat() then
        return
    end
    self.prompt:Show(("%s came online."):format(addon.GreetComposer.JoinNames(names(self.pending))), {
        { text = "Greet", onClick = function() self:Greet() end },
        { text = "Dismiss", onClick = function() self:Dismiss() end },
    })
    if keepTimeout then
        return
    end
    self.generation = self.generation + 1
    local generation = self.generation
    self.deps.after(Greeter.PROMPT_TIMEOUT, function()
        if self.generation == generation then
            self:Dismiss()
        end
    end)
end

-- After combat, shows the prompt for arrivals that are still recent enough.
function Greeter:OnCombatEnded()
    local now = self.deps.now()
    local fresh = {}
    for _, arrival in ipairs(self.pending) do
        if now - arrival.at < Greeter.PROMPT_TIMEOUT then
            table.insert(fresh, arrival)
        end
    end
    self.pending = fresh
    self:ShowPrompt()
end

-- Greets everyone in the prompt from the player's messages, in as few lines as
-- fit. Runs from the Greet click.
function Greeter:Greet()
    local settings = self.deps.settings()
    if #self.pending == 0 or not settings.enabled then
        return
    end
    local lines
    lines, self.lastTemplate = addon.GreetComposer.Lines(names(self.pending), settings.messages,
        self.deps.random, self.lastTemplate)
    local personIds = {}
    for _, arrival in ipairs(self.pending) do
        table.insert(personIds, arrival.personId)
    end
    self.deps.announce(personIds)
    for _, line in ipairs(lines) do
        self.deps.send(line)
    end
    self:Dismiss()
end

-- Clears the prompt without greeting.
function Greeter:Dismiss()
    self.pending = {}
    self.generation = self.generation + 1
    self.prompt:Hide()
end
