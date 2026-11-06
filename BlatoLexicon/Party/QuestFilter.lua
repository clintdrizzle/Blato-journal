-- Blato Lexicon: could a friend accept this quest? What is left of One More Quest's "One more quest" search
-- (decisions 295, 297): QuestSync asks the group before a sync round, and Data/Cities.lua finds quest hubs.
-- Quest IDs travel in base 36, separated by commas. The data is Data/QuestPlaces.lua.
local ADDON, OMQ = ...
OMQ = _G.BlatoParty

local QF = {}
OMQ.QuestFilter = QF

local function data(id) return OMQ.QuestPlaces and OMQ.QuestPlaces[id] end

local function xyOf(v)
    if type(v) ~= "table" then return nil end
    if v.GetXY then local ok, x, y = pcall(v.GetXY, v); if ok then return x, y end end
    return v.x, v.y
end
-- world position of a spot { map, x%, y% }: cached on the spot
function QF.World(spot)
    local w = rawget(spot, "w")
    if w == nil then
        w = false
        if C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
            local ok, inst, vec = pcall(C_Map.GetWorldPosFromMapPos, spot[1], CreateVector2D(spot[2] / 100, spot[3] / 100))
            if ok then
                local a, b = xyOf(vec)
                if type(a) == "number" and type(b) == "number" then w = { a, b, inst } end
            end
        end
        spot.w = w
    end
    return w or nil
end

local function everDone(id)
    local CQ = C_QuestLog
    if CQ and CQ.IsQuestFlaggedCompleted then return CQ.IsQuestFlaggedCompleted(id) and true or false end
    if IsQuestFlaggedCompleted then return IsQuestFlaggedCompleted(id) and true or false end
    return false
end

local RACE_ID = { Human = 1, Orc = 2, Dwarf = 3, NightElf = 4, Scourge = 5, Undead = 5, Tauren = 6, Gnome = 7, Troll = 8, Goblin = 9,
                  BloodElf = 10, Draenei = 11 }
local function me()
    local level = UnitLevel and tonumber((UnitLevel("player"))) or 1
    local f = UnitFactionGroup and UnitFactionGroup("player")
    -- not "UnitRace and UnitRace()": "and" keeps only the first value (decision 305 found it)
    local raceFile, raceID, classID
    if UnitRace then raceFile, raceID = select(2, UnitRace("player")) end
    if UnitClass then classID = select(3, UnitClass("player")) end
    return { level = level, fac = (f == "Alliance" and "A") or (f == "Horde" and "H") or nil,
             race = raceID or RACE_ID[raceFile or ""], class = classID }
end
local function contains(list, v)
    for _, x in ipairs(list or {}) do if x == v then return true end end
    return false
end

-- could I accept this quest if somebody shares it? (decision 297, the sync round of QuestSync)
-- Not in my log, never done, required level, faction, race, class, pre-quests done, no excluding quest done.
-- A quest the data does not know only has to be not done yet.
function QF.Acceptable(id, who, log)
    if (log and log[id]) or everDone(id) then return false end
    local d = data(id)
    if not d then return true end
    who = who or me()
    if (d[2] or 0) > who.level then return false end
    if d[4] and who.fac and d[4] ~= who.fac then return false end
    if d[5] and who.race and not contains(d[5], who.race) then return false end
    if d[6] and who.class and not contains(d[6], who.class) then return false end
    for _, p in ipairs(d[10] or {}) do if not everDone(p) then return false end end
    if d[11] then
        local any = false
        for _, p in ipairs(d[11]) do if everDone(p) then any = true; break end end
        if not any then return false end
    end
    for _, p in ipairs(d[12] or {}) do if everDone(p) or (log and log[p]) then return false end end
    return true
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
    n = math.floor(n)
    if n == 0 then return "0" end
    local t = ""
    while n > 0 do local r = n % 36; t = DIGITS:sub(r + 1, r + 1) .. t; n = math.floor(n / 36) end
    return t
end
function QF._ids(list, max)
    local t = {}
    for i, x in ipairs(list) do
        if max and i > max then break end
        t[#t + 1] = b36(type(x) == "table" and x.id or x)
    end
    return table.concat(t, ",")
end
function QF._set(text)
    local s = {}
    for w in tostring(text or ""):gmatch("[%w]+") do local n = tonumber(w, 36); if n then s[n] = true end end
    return s
end
