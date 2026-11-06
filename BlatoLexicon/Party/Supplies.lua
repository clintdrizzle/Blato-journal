-- Blato Lexicon: what I carry on purpose. What is left of One More Quest's Group Check (decision 140): the drink
-- alerts read the drinks in my bags, and the auction and vendor helpers never offer these items.
local ADDON, OMQ = ...
OMQ = _G.BlatoParty

local SP = {}
OMQ.Supplies = SP

local NO_MANA = { WARRIOR = true, ROGUE = true }

-- item ids from memory, not checked in the game
local DRINKS = { 159, 1179, 1205, 1708, 1645, 8766, 5350, 2288, 2136, 3772, 8077, 8078, 8079, 4791, 19300, 18300 }
local POISONS = { 6947, 6949, 6950, 8926, 8927, 8928, 2892, 2893, 8984, 8985, 20844, 3775, 3776, 5237, 6951,
                  10918, 10920, 10921, 10922 }
local SOUL_SHARD = 6265
local SEEDS = { 17034, 17035, 17036, 17037, 17038, 22147 }
local ANKH = 17030
-- what the auction helper never posts: drinks and class supplies carried on purpose (decision 260)
SP.KEEP = {}
for _, list in ipairs({ DRINKS, POISONS, SEEDS, { SOUL_SHARD, ANKH } }) do
    for _, id in ipairs(list) do SP.KEEP[id] = true end
end

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function bagCounts()
    local counts = {}
    local C = C_Container
    if not (C and C.GetContainerNumSlots) then return counts end
    for bag = 0, OMQ.LastBag() do
        for slot = 1, C.GetContainerNumSlots(bag) or 0 do
            local info = C.GetContainerItemInfo and C.GetContainerItemInfo(bag, slot)
            if info and type(info.itemID) == "number" and not isSecret(info.itemID) then
                counts[info.itemID] = (counts[info.itemID] or 0) + (info.stackCount or 1)
            end
        end
    end
    return counts
end

-- Required level of an item. WoW Forever has no global GetItemInfo any more (section 13.1), so
-- C_Item.GetItemInfo comes first. It returns nothing until the item is in the client cache: then
-- the item is loaded and nil is returned.
local function minLevelOf(id)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if info then
        local ok, name, _, _, _, minLevel = pcall(info, id)
        if ok and name and type(minLevel) == "number" and not isSecret(minLevel) then return minLevel end
    end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return nil
end

local function usable(id, level)
    local minLevel = minLevelOf(id)
    if minLevel then return minLevel <= level end
    return true                          -- not in the cache yet: count it until the next check
end

-- usable drinks in the bags, nil for classes without mana (the drink alert, decision 189)
local drinkCache, drinkAt = nil, -100
function SP.Drinks()
    local _, class = UnitClass("player")
    if NO_MANA[class] then return nil end
    if GetTime() - drinkAt < 3 then return drinkCache end
    local level = UnitLevel("player") or 1
    local counts = bagCounts()
    local n = 0
    for _, id in ipairs(DRINKS) do
        if (counts[id] or 0) > 0 and usable(id, level) then n = n + counts[id] end
    end
    drinkCache, drinkAt = n, GetTime()
    return n
end

-- the best usable drink in the bags (the highest required level), as an item id, or nil (decision 219)
function SP.BestDrink()
    local level = UnitLevel("player") or 1
    local counts = bagCounts()
    local best, bestLvl
    for _, id in ipairs(DRINKS) do
        if (counts[id] or 0) > 0 and usable(id, level) then
            local lvl = minLevelOf(id) or 0
            if not best or lvl > bestLvl then best, bestLvl = id, lvl end
        end
    end
    return best
end
