local _, addon = ...

-- Every difference between WoW: Forever and Retail lives here. Nothing else in
-- the add-on branches on the client.
local Compat = {}
addon.Compat = Compat

Compat.FOREVER = "Forever"
Compat.RETAIL = "Retail"
-- Forever is realmless, so every character key gets this realm whatever the API reports.
Compat.FOREVER_REALM = "Forever"

-- The client comes from the manifest's X-Client field. Anything unrecognized is
-- treated as Retail.
function Compat.DetectFlavor(client)
    if client == Compat.FOREVER then
        return Compat.FOREVER
    end
    return Compat.RETAIL
end

local function normalizeRealm(realm)
    if type(realm) ~= "string" then
        return nil
    end
    realm = realm:gsub("[%s%-]", "")
    if realm == "" then
        return nil
    end
    return realm
end

-- Builds the canonical `Name-Realm` key without touching the WoW API. `name` may
-- carry its own `-Realm` suffix; an explicit `realm` wins over it. Two-word names
-- keep a single space. On Retail a missing realm falls back to `playerRealm`.
-- Returns nil when no usable key can be made.
function Compat.BuildNameKey(flavor, name, realm, playerRealm)
    if type(name) ~= "string" then
        return nil
    end
    local base, suffix = name:match("^([^%-]*)%-(.*)$")
    if base then
        name = base
        if normalizeRealm(realm) == nil then
            realm = suffix
        end
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if name == "" then
        return nil
    end
    if flavor == Compat.FOREVER then
        return name .. "-" .. Compat.FOREVER_REALM
    end
    realm = normalizeRealm(realm) or normalizeRealm(playerRealm)
    if not realm then
        return nil
    end
    return name .. "-" .. realm
end

Compat.flavor = Compat.DetectFlavor(addon.client)

function Compat.IsForever()
    return Compat.flavor == Compat.FOREVER
end

-- The one name normalization function the rest of the add-on uses.
function Compat.NormalizeName(name, realm)
    local playerRealm
    if not Compat.IsForever() then
        playerRealm = GetNormalizedRealmName()
    end
    return Compat.BuildNameKey(Compat.flavor, name, realm, playerRealm)
end

-- The name part of a Name-Realm key.
function Compat.NameFromKey(key)
    return key:match("^(.*)%-[^%-]*$") or key
end

-- Asks the server for fresh roster data; GUILD_ROSTER_UPDATE follows.
function Compat.RequestGuildRoster()
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

-- Registers a chat message filter. Returns false when this client offers no
-- supported way to, so callers degrade to no decoration.
function Compat.AddMessageEventFilter(event, filter)
    local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
    if not add then
        return false
    end
    add(event, filter)
    return true
end

-- Retail can hand add-ons "secret" values (e.g. chat inside instances) that
-- must not be read or altered. Always false where the concept doesn't exist.
function Compat.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- Calls `callback(tooltip, unit)` after a unit tooltip is filled in. Uses the
-- tooltip-data post-call API where the client has it, else the older
-- OnTooltipSetUnit script. Both only append, so neither taints.
function Compat.HookUnitTooltip(callback)
    if TooltipDataProcessor and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
            local _, unit = tooltip:GetUnit()
            callback(tooltip, unit)
        end)
    elseif GameTooltip then
        GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
            local _, unit = tooltip:GetUnit()
            callback(tooltip, unit)
        end)
    end
end

-- Index of "edit officer note" in a rank's permission flags.
Compat.RANK_FLAG_EDIT_OFFICER_NOTE = 12

-- The guild's ranks as { index (0-based, 0 = guild master), name, canEditOfficerNote }.
-- canEditOfficerNote is false where the client won't report rank permissions.
function Compat.GuildRanks()
    local ranks = {}
    local count = GuildControlGetNumRanks and GuildControlGetNumRanks() or 0
    local getFlags = C_GuildInfo and C_GuildInfo.GuildControlGetRankFlags
    for order = 1, count do
        local flags = getFlags and getFlags(order)
        table.insert(ranks, {
            index = order - 1,
            name = GuildControlGetRankName(order),
            canEditOfficerNote = type(flags) == "table" and flags[Compat.RANK_FLAG_EDIT_OFFICER_NOTE] == true,
        })
    end
    return ranks
end

-- Whether this player's rank may edit other members' public notes.
function Compat.CanEditPublicNote()
    return type(CanEditPublicNote) == "function" and CanEditPublicNote() == true
end

-- Writes `member`'s public note (`member` is a roster snapshot entry). Uses the
-- GUID-based API where the client has it, else finds the roster index. Returns
-- false when the note couldn't be written.
function Compat.SetPublicNote(member, text)
    if C_GuildInfo and C_GuildInfo.SetNote and member.guid then
        C_GuildInfo.SetNote(member.guid, text, true)
        return true
    end
    if GuildRosterSetPublicNote then
        for index = 1, GetNumGuildMembers() do
            local name = GetGuildRosterInfo(index)
            if name and Compat.NormalizeName(name) == member.key then
                GuildRosterSetPublicNote(index, text)
                return true
            end
        end
    end
    return false
end
