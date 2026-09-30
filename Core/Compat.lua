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
