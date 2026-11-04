-- One More Quest: Main
-- Glue code.
local ADDON, OMQ = ...
OMQ = _G.BlatoParty

OMQ:On("READY", function()
    local me = OMQ:GetSelf()
    if me then
        -- Blato Lexicon: the version of the addon, not OMQ.version (that one stays the protocol's, see Comm.lua)
        local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        local v = getMeta and getMeta(ADDON, "Version") or "?"
        OMQ:Print("Lexicon v" .. tostring(v) .. " loaded for " .. me.name .. ". /blato opens the Commands page, /blato help lists the commands.")
    end
end)
