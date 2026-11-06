-- BlatoLexicon fellowship: the friends you group with, the ones who run this addon. Per companion: when, where and at which levels you met,
-- time grouped (split into dungeons, fighting, travelling and time in town), the levels you gained side by side,
-- quests done together and dungeon runs together. Counted each second you share a group; names the game keeps
-- secret (inside some instances) are skipped rather than guessed.
local _, ns = ...
local J = ns.J
local DB, H = J.DB, J.H

local function Plain(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v ~= "" and v or nil end

-- The friends in the group as unit tokens (a stranger is no companion, Party/Comm.lua).
local function Units()
    local out, OMQ = {}, ns.OMQ
    local function add(unit)
        if not OMQ or OMQ:IsFriendUnit(unit) then out[#out + 1] = unit end
    end
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do if not UnitIsUnit("raid" .. i, "player") then add("raid" .. i) end end
    elseif IsInGroup and IsInGroup() then
        for i = 1, 4 do if UnitExists("party" .. i) then add("party" .. i) end end
    end
    return out
end
-- Forever gives characters a first and a last name (where other clients would give a realm): "First Last".
local function FullName(unit)
    local ok, name, last = pcall(UnitName, unit)
    name, last = ok and Plain(name), ok and Plain(last)
    if not name or name == UNKNOWNOBJECT then return nil end
    local realm = GetRealmName and Plain(GetRealmName())
    if last and last ~= realm and last ~= (realm or ""):gsub("%s", "") then return name .. " " .. last end
    return name
end
-- earlier builds stored "First-Last": rename those once (keys are collected first: a table can't gain keys mid-walk)
local function Rename(t, isSet)
    if type(t) ~= "table" then return end
    local old = {}
    for key in pairs(t) do if type(key) == "string" and key:find("-", 1, true) then old[#old + 1] = key end end
    for _, key in ipairs(old) do
        local v, new = t[key], key:gsub("%-", " ")
        t[key] = nil
        if t[new] == nil then
            if not isSet and type(v) == "table" then v.name = new end
            t[new] = v
        end
    end
end
local function Migrate()
    Rename(H.fellows)
    for _, q in ipairs(H.quests or {}) do Rename(q.with, true) end
    for _, s in pairs(H.questStart or {}) do Rename(s.with, true) end
end
-- after login, once the saved journal is in place
local login = CreateFrame("Frame")
login:RegisterEvent("PLAYER_LOGIN")
login:SetScript("OnEvent", function()
    local ok, err = pcall(Migrate)
    if not ok and DB.debug then print("|cffff6060BlatoLexicon fellowship:|r " .. tostring(err)) end
end)
J.FellowMigrate = Migrate   -- for the test harness
-- Group members on a quest: when the game can tell (C_QuestLog.IsUnitOnQuest), only those who have it too.
function J.QuestPartners(questID)
    local out = {}
    local check = C_QuestLog and C_QuestLog.IsUnitOnQuest
    for _, u in ipairs(Units()) do
        local n = FullName(u)
        if n then
            local ok, on = true, true
            if check then ok, on = pcall(check, u, questID) end
            if ok and on and not (issecretvalue and issecretvalue(on)) then out[#out + 1] = n end
        end
    end
    return out
end
function J.GroupNames()
    local out = {}
    for _, u in ipairs(Units()) do local n = FullName(u); if n then out[#out + 1] = n end end
    return out
end

-- What the second was spent on: inside an instance, fighting in the world, resting in town, or on the road.
local function Activity()
    local inside, kind = IsInInstance()
    if inside and (kind == "party" or kind == "raid") then return "dungeon" end
    if UnitAffectingCombat("player") then return "fight" end
    if IsResting and IsResting() then return "town" end
    return "travel"
end

local function Tick()
    local units = Units()
    if #units == 0 then return end
    local afk = UnitIsAFK and UnitIsAFK("player")
    if issecretvalue and issecretvalue(afk) then afk = false end
    if afk then return end
    H.fellows = H.fellows or {}
    local now, me, act = time(), J.Level(), Activity()
    local run = H.currentRun
    local inRun = run and run.t and not run.left and act == "dungeon"
    local names = {}
    for _, u in ipairs(units) do
        local name = FullName(u)
        if name then
            names[#names + 1] = name
            local f = H.fellows[name]
            if not f then
                f = { name = name, met = now, metLevel = me, metZone = J.Zone(), metSub = J.SubZone(), time = 0,
                    split = { dungeon = 0, fight = 0, travel = 0, town = 0 }, runs = {} }
                local ok, lvl = pcall(UnitLevel, u)
                f.theirMetLevel = ok and tonumber(lvl) or nil
                H.fellows[name] = f
            end
            -- who they are, kept fresh
            local ok1, _, class = pcall(UnitClass, u)
            local ok2, race = pcall(UnitRace, u)
            local ok3, lvl = pcall(UnitLevel, u)
            if ok1 and Plain(class) then f.class = class end
            if ok2 and Plain(race) then f.race = race end
            if ok3 and tonumber(lvl) and not (issecretvalue and issecretvalue(lvl)) and lvl > 0 then f.level = lvl end
            f.time = f.time + 1
            f.split[act] = (f.split[act] or 0) + 1
            f.last = now
            f.lowLevel, f.highLevel = math.min(f.lowLevel or me, me), math.max(f.highLevel or me, me)
            if inRun then
                local key = tostring(run.t)
                local r = f.runs[key]
                if not r then r = { name = run.name, t = run.t, time = 0 }; f.runs[key] = r end
                r.time, r.bosses = r.time + 1, run.bosses
            end
        end
    end
    -- Blato Lexicon: a second with both party mates in the group counts for the three of you
    local a, b = J.PartyMates()
    local here = {}
    for _, n in ipairs(names) do here[n] = true end
    if a and b and here[a.name] and here[b.name] then
        H.trio = H.trio or { time = 0, split = { dungeon = 0, fight = 0, travel = 0, town = 0 } }
        H.trio.time = H.trio.time + 1
        H.trio.split[act] = (H.trio.split[act] or 0) + 1
    end
end

-- The party of three (Blato Lexicon) -----------------------------------------------------------------------
-- Your two party mates are the two companions you have spent the most time grouped with.
function J.PartyMates()
    local list = {}
    for _, f in pairs(H.fellows or {}) do list[#list + 1] = f end
    table.sort(list, function(x, y) return (x.time or 0) > (y.time or 0) end)
    return list[1], list[2]
end

-- The last boss of each classic dungeon by the name the game gives its encounter (English client). A run where
-- one of them fell counts as cleared; so does a run the group finder reports as completed (LFG_COMPLETION_REWARD).
-- Instances with several wings list the last boss of every wing.
J.FINAL_BOSSES = {
    ["Ragefire Chasm"] = { "Bazzalan", "Taragaman the Hungerer" },
    ["Wailing Caverns"] = { "Mutanus the Devourer" },
    ["The Deadmines"] = { "Edwin VanCleef" },
    ["Shadowfang Keep"] = { "Archmage Arugal" },
    ["Blackfathom Deeps"] = { "Aku'mai" },
    ["The Stockade"] = { "Bazil Thredd", "Dextren Ward" },
    ["Gnomeregan"] = { "Mekgineer Thermaplugg" },
    ["Razorfen Kraul"] = { "Charlga Razorflank" },
    ["Scarlet Monastery"] = { "Bloodmage Thalnos", "Arcanist Doan", "Herod", "High Inquisitor Whitemane" },
    ["Razorfen Downs"] = { "Amnennar the Coldbringer" },
    ["Uldaman"] = { "Archaedas" },
    ["Zul'Farrak"] = { "Chief Ukorz Sandscalp" },
    ["Maraudon"] = { "Princess Theradras" },
    ["Sunken Temple"] = { "Shade of Eranikus" },
    ["The Temple of Atal'Hakkar"] = { "Shade of Eranikus" },
    ["Blackrock Depths"] = { "Emperor Dagran Thaurissan" },
    ["Blackrock Spire"] = { "Overlord Wyrmthalak", "General Drakkisath" },
    ["Lower Blackrock Spire"] = { "Overlord Wyrmthalak" },
    ["Upper Blackrock Spire"] = { "General Drakkisath" },
    ["Dire Maul"] = { "Alzzin the Wildshaper", "Prince Tortheldrin", "King Gordok" },
    ["Scholomance"] = { "Darkmaster Gandling" },
    ["Stratholme"] = { "Baron Rivendare", "Balnazzar" },
}
function J.RunCleared(dungeon, run)
    if run.cleared then return true end
    for _, last in ipairs(J.FINAL_BOSSES[dungeon] or {}) do
        for _, n in ipairs(run.names or {}) do if n == last then return true end end
    end
    return false
end
local lfg = CreateFrame("Frame")
pcall(lfg.RegisterEvent, lfg, "LFG_COMPLETION_REWARD")   -- only where the client has a group finder
lfg:SetScript("OnEvent", function()
    local run = H.currentRun
    local d = run and run.index and H.dungeons[run.name] and H.dungeons[run.name].history
    local line = d and d[run.index]
    if line then line.cleared = true; J.Changed() end
end)

-- What the three of you have done together, for the Journey page: nil without two party mates.
--   dungeons = { { name, runs = { run, ... }, cleared, bosses = { name = kills }, first, firstClear }, ... } (first run first)
--   quests = { quest, ... } (newest first), runs, cleared (counts), time (seconds with both in the group), since
function J.Together()
    local a, b = J.PartyMates()
    if not (a and b) then return nil end
    local t = { a = a, b = b, dungeons = {}, quests = {}, runs = 0, cleared = 0, time = H.trio and H.trio.time or 0,
        since = math.max(a.met or 0, b.met or 0) }
    for name, d in pairs(H.dungeons or {}) do
        local entry = { name = name, icon = d.icon, runs = {}, bosses = {}, cleared = 0 }
        for _, r in ipairs(d.history or {}) do
            local key = tostring(r.t)
            if a.runs and a.runs[key] and b.runs and b.runs[key] then
                entry.runs[#entry.runs + 1] = r
                entry.first = entry.first or r.t
                for _, n in ipairs(r.names or {}) do entry.bosses[n] = (entry.bosses[n] or 0) + 1 end
                if J.RunCleared(name, r) then
                    entry.cleared = entry.cleared + 1
                    entry.firstClear = entry.firstClear or r
                end
            end
        end
        if #entry.runs > 0 then
            t.dungeons[#t.dungeons + 1] = entry
            t.runs, t.cleared = t.runs + #entry.runs, t.cleared + entry.cleared
        end
    end
    table.sort(t.dungeons, function(x, y) return x.first < y.first end)
    for i = #(H.quests or {}), 1, -1 do
        local q = H.quests[i]
        if q.with and q.with[a.name] and q.with[b.name] then t.quests[#t.quests + 1] = q end
    end
    return t
end
C_Timer.NewTicker(1, function()
    if not (J.H and J.H.levels) then return end
    local ok, err = pcall(Tick)
    if not ok and DB.debug then print("|cffff6060BlatoLexicon fellowship:|r " .. tostring(err)) end
end)
J.FellowTick = Tick   -- for the test harness
