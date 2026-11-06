-- Blato Lexicon: the score of an item against what I wear (item score of my class and preferred role, Score.lua,
-- decision 200). What is left of One More Quest's boss loot preview: Alt on an item and the auction and vendor
-- helpers use it.
local ADDON, OMQ = ...
OMQ = _G.BlatoParty

local LP = {}
OMQ.LootPreview = LP

local function SC() return OMQ.Score end

-- the score of an item against my gear: the best slot it can go into (for rings and trinkets the
-- weaker one is replaced, an empty slot counts the full value); a two-hander replaces both hands
function LP.Gain(link, equipLoc, class, role, wornOf)
    local S = SC()
    local slots = OMQ.Compare and OMQ.Compare.SLOTS and OMQ.Compare.SLOTS[equipLoc or ""]
    if not (S and slots) then return nil end
    -- without a class the score knows no weights and every item scored 0 (decision 294): mine by default
    class = class or (S.MyClass and S.MyClass())
    role = role or (S.MyRole and S.MyRole())
    wornOf = wornOf or function(slot) return GetInventoryItemLink and GetInventoryItemLink("player", slot) end
    -- two-hander against both hands, no off-hand next to a two-hander (decision 285)
    local best
    for _, slot in ipairs(slots) do
        local d = S.HandDelta(link, equipLoc, wornOf(slot), wornOf(16), wornOf(17), class, role)
        if d and (not best or d > best) then best = d end
    end
    return best
end
