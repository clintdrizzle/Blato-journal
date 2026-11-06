-- Blato Lexicon: what is left of One More Quest's guidance. The arrows to places are gone; the alert cards still
-- need to know where the fixed places are (Data/Places.lua: "your trainer is 40 yards away") and the name of a
-- profession (the tool cards).
local ADDON, OMQ = ...
OMQ = _G.BlatoParty

local G = {}
OMQ.Guide = G

-- Professions are identified by their skill line id (language independent) and,
-- as a fallback, by their English or German name.
local PROF_LINE = {
    [171] = "Alchemy", [164] = "Blacksmithing", [333] = "Enchanting", [202] = "Engineering",
    [182] = "Herbalism", [165] = "Leatherworking", [186] = "Mining", [393] = "Skinning",
    [197] = "Tailoring", [185] = "Cooking", [129] = "First Aid", [356] = "Fishing",
}
local PROF_NAME = {
    alchemy = "Alchemy", alchemie = "Alchemy",
    blacksmithing = "Blacksmithing", schmiedekunst = "Blacksmithing",
    enchanting = "Enchanting", verzauberkunst = "Enchanting",
    engineering = "Engineering", ingenieurskunst = "Engineering",
    herbalism = "Herbalism", ["kräuterkunde"] = "Herbalism",
    leatherworking = "Leatherworking", lederverarbeitung = "Leatherworking",
    mining = "Mining", bergbau = "Mining",
    skinning = "Skinning", ["kürschnerei"] = "Skinning",
    tailoring = "Tailoring", schneiderei = "Tailoring",
    cooking = "Cooking", kochkunst = "Cooking", kochen = "Cooking",
    ["first aid"] = "First Aid", ["erste hilfe"] = "First Aid",
    fishing = "Fishing", angeln = "Fishing",
}
function G.ProfKey(skillLine, name)
    if skillLine and PROF_LINE[skillLine] then return PROF_LINE[skillLine] end
    if type(name) == "string" then return PROF_NAME[name:lower()] end
end

local function xyOf(v)
    if type(v) ~= "table" then return nil end
    if v.GetXY then local ok, x, y = pcall(v.GetXY, v); if ok then return x, y end end
    return v.x, v.y
end

-- map percent (0-100) -> world coordinates, instance
local function worldFromMap(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local ok, inst, vec = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x, y))
    if not ok then return nil end
    local a, b = xyOf(vec)
    if type(a) ~= "number" or type(b) ~= "number" then return nil end
    return a, b, inst
end

-- world positions of the fixed places, worked out once (there are more than 1500 of them)
local worldCache = {}
function G.WorldOf(p)
    local w = worldCache[p]
    if w == nil then
        local a, b, inst = worldFromMap(p[3], p[4] / 100, p[5] / 100)
        w = a and { a, b, inst } or false
        if a or not (C_Map and C_Map.GetWorldPosFromMapPos) then worldCache[p] = w end
    end
    return w or nil
end

-- name as this client shows it, and the NPC's function ("Druidenlehrer" on a German client)
function G.Title(name)
    local t = OMQ.placeTitles and OMQ.placeTitles[name]
    if not t then return name, nil end
    if GetLocale and GetLocale() == "deDE" then return t[2] or name, t[3] or t[1] end
    return name, t[1]
end
