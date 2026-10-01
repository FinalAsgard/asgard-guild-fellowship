local _, addon = ...

-- Guild Greet: when guildmates come online, or someone joins the guild, offers
-- this player a prompt to greet them. Greetings are only sent when the player
-- clicks a button, since the game only lets add-ons post chat in response to a
-- player action.
local Greeter = {}
Greeter.__index = Greeter
addon.Greeter = Greeter

-- Seconds an unanswered prompt stays up after its last new arrival.
Greeter.PROMPT_TIMEOUT = 120
-- How many players may greet the same arrival. Two feels friendly; more is spam.
Greeter.MAX_GREETERS = 2
-- Seconds a greeting announcement counts toward that limit for the arrival.
Greeter.CLAIM_WINDOW = 300

-- The two kinds of greeting, each with its own row in the prompt, button,
-- message list (a settings field), and built-in defaults.
Greeter.KINDS = {
    {
        kind = "back",
        line = "%s came online.",
        button = "Greet",
        messages = "messages",
        defaults = "DEFAULT_RETURN",
    },
    {
        kind = "new",
        line = "%s joined the guild.",
        button = "Welcome",
        messages = "newMessages",
        defaults = "DEFAULT_NEW",
    },
}

-- `deps`:
--   identity()   the current IdentityStore, or nil outside a guild
--   playerKey()  this character's key
--   settings()   the profile's greet settings
--                ({ enabled, welcomeNew, messages, newMessages, prompt })
--   send(text)   posts a line in guild chat
--   random(n)    an integer from 1 to n
--   now()        current time in seconds
--   after(s, fn) runs fn after s seconds
--   inCombat()   whether the player is in combat
--   announce(personIds)  tells other add-on users who this player greeted
--                        (a no-op when sync is off)
--   playSound()  plays the short alert sound
function Greeter.New(deps)
    local greeter = setmetatable({
        deps = deps,
        tracker = addon.GreetTracker.New(),
        -- pending[kind] = list of { personId, name, at } waiting in the prompt.
        pending = { back = {}, new = {} },
        lastTemplate = {},
        -- joined[charKey] = when they joined, so their first login isn't a return.
        joined = {},
        generation = 0,
        -- claims[personId][greeter] = when they announced greeting that person.
        claims = {},
    }, Greeter)
    greeter.prompt = addon.UI.Prompt({
        title = "Guild Greet",
        width = 320,
        height = 150,
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
    self.joined = {}
    self:Dismiss()
end

local function names(list)
    local result = {}
    for _, arrival in ipairs(list) do
        table.insert(result, arrival.name)
    end
    return result
end

function Greeter:HasPending()
    return #self.pending.back > 0 or #self.pending.new > 0
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
        local joinedAt = self.joined[arrival.member.key]
        local newMember = joinedAt and now - joinedAt < addon.GreetTracker.RETURN_WINDOW
        if not newMember and self:Greeters(arrival.personId) < Greeter.MAX_GREETERS then
            table.insert(self.pending.back, {
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

-- Someone joined the guild: offers a Welcome for them, once. `charKey` is
-- their normalized key and `name` how to call them.
function Greeter:OnMemberJoined(charKey, name)
    local settings = self.deps.settings()
    if not self.deps.identity() or not settings.enabled or settings.welcomeNew == false
        or charKey == self.deps.playerKey() or self.joined[charKey] then
        return
    end
    local now = self.deps.now()
    self.joined[charKey] = now
    if self:Greeters(charKey) >= Greeter.MAX_GREETERS then
        return
    end
    table.insert(self.pending.new, { personId = charKey, name = name, at = now })
    self:ShowPrompt()
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
    for kind, list in pairs(self.pending) do
        local kept = {}
        for _, arrival in ipairs(list) do
            if self:Greeters(arrival.personId) < Greeter.MAX_GREETERS then
                table.insert(kept, arrival)
            else
                changed = true
            end
        end
        self.pending[kind] = kept
    end
    if not changed then
        return
    end
    if not self:HasPending() then
        self:Dismiss()
    elseif self.prompt:IsShown() then
        self:ShowPrompt(true)
    end
end

-- Shows (or updates) the prompt for everyone waiting, unless the player is in
-- combat, in which case it waits for OnCombatEnded. Each update restarts the
-- timeout, except when `keepTimeout` (someone was removed, not added).
function Greeter:ShowPrompt(keepTimeout)
    if not self:HasPending() or self.deps.inCombat() then
        return
    end
    -- A short sound when the prompt opens, not on every update while it's open.
    if not self.prompt:IsShown() then
        self.deps.playSound()
    end
    local rows = {}
    for _, info in ipairs(Greeter.KINDS) do
        local list = self.pending[info.kind]
        if #list > 0 then
            table.insert(rows, {
                text = info.line:format(addon.GreetComposer.JoinNames(names(list))),
                buttons = { { text = info.button, onClick = function() self:Greet(info.kind) end } },
            })
        end
    end
    table.insert(rows, { buttons = { { text = "Dismiss", onClick = function() self:Dismiss() end } } })
    self.prompt:Show(rows)
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
    for kind, list in pairs(self.pending) do
        local fresh = {}
        for _, arrival in ipairs(list) do
            if now - arrival.at < Greeter.PROMPT_TIMEOUT then
                table.insert(fresh, arrival)
            end
        end
        self.pending[kind] = fresh
    end
    self:ShowPrompt()
end

-- Greets everyone waiting in one row ("back" or "new") from the player's
-- messages for that kind, in as few lines as fit. Runs from that row's button.
-- Other rows stay in the prompt.
function Greeter:Greet(kind)
    kind = kind or "back"
    local settings = self.deps.settings()
    local list = self.pending[kind]
    if not list or #list == 0 or not settings.enabled then
        return
    end
    local info
    for _, candidate in ipairs(Greeter.KINDS) do
        if candidate.kind == kind then
            info = candidate
        end
    end
    local lines
    lines, self.lastTemplate[kind] = addon.GreetComposer.Lines(names(list), settings[info.messages],
        self.deps.random, self.lastTemplate[kind], addon.GreetComposer[info.defaults])
    local personIds = {}
    for _, arrival in ipairs(list) do
        table.insert(personIds, arrival.personId)
    end
    self.deps.announce(personIds)
    for _, line in ipairs(lines) do
        self.deps.send(line)
    end
    self.pending[kind] = {}
    if self:HasPending() then
        self:ShowPrompt(true)
    else
        self:Dismiss()
    end
end

-- Clears the prompt without greeting.
function Greeter:Dismiss()
    self.pending = { back = {}, new = {} }
    self.generation = self.generation + 1
    self.prompt:Hide()
end
