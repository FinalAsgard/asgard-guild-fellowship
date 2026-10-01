local _, addon = ...

-- Guild Greet: when guildmates come online, offers this player a prompt to
-- greet them. Greetings are only sent when the player clicks Greet, since the
-- game only lets add-ons post chat in response to a player action.
local Greeter = {}
Greeter.__index = Greeter
addon.Greeter = Greeter

-- `deps`:
--   identity()   the current IdentityStore, or nil outside a guild
--   playerKey()  this character's key
--   settings()   the profile's greet settings ({ enabled })
--   send(text)   posts a line in guild chat
--   random(n)    an integer from 1 to n
--   now()        current time in seconds
function Greeter.New(deps)
    local greeter = setmetatable({ deps = deps, tracker = addon.GreetTracker.New(), pending = {} }, Greeter)
    greeter.prompt = addon.UI.Prompt({
        title = "Guild Greet",
        width = 320,
        height = 120,
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

-- Feeds a roster snapshot. New arrivals are added to the prompt.
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
    local arrivals = self.tracker:Observe(snapshot, personOf, self.deps.now(), personOf(playerKey) or playerKey)
    for _, arrival in ipairs(arrivals) do
        table.insert(self.pending, {
            personId = arrival.personId,
            name = store:GetDisplayName(arrival.personId) or arrival.member.name,
        })
    end
    if #self.pending > 0 then
        self.prompt:Show(("%s came online."):format(addon.GreetComposer.JoinNames(names(self.pending))), {
            { text = "Greet", onClick = function() self:Greet() end },
            { text = "Dismiss", onClick = function() self:Dismiss() end },
        })
    end
end

-- Greets everyone in the prompt with one line. Runs from the Greet click.
function Greeter:Greet()
    if #self.pending == 0 or not self.deps.settings().enabled then
        return
    end
    self.deps.send(addon.GreetComposer.Compose(names(self.pending), nil, self.deps.random))
    self:Dismiss()
end

-- Clears the prompt without greeting.
function Greeter:Dismiss()
    self.pending = {}
    self.prompt:Hide()
end
