local addonName, addon = ...

-- Entry point. Modules attach themselves to this shared namespace as they are
-- added; this file only records what the running build is.
local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
addon.name = addonName
addon.version = getMetadata(addonName, "Version")
-- Which client's manifest loaded us ("Forever" or "Retail"). Only Compat reads it.
addon.client = getMetadata(addonName, "X-Client")
