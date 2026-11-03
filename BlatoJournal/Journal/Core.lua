-- BlatoJournal core: a per-character record of the journey (time per level and zone, kills, quests, deaths,
-- dungeons, firsts), plus goals and notes. UI.lua draws it, Settings.lua holds the options page.
-- The combat log is closed to addons on this client, so kills are counted from XP gains in or just after combat.
local _, ns = ...
local Kit = ns.Kit
local J = {}
ns.J = J

-- Settings are mirrored account-wide/per-character like the other Forever addons; the journal itself is per character.
local DB, H = {}, {}
J.DB, J.H = DB, H

function J.Defaults()
    local function D(k, v) if DB[k] == nil then DB[k] = v end end
    D("locked", true)
    D("moments", true); D("momentZone", true); D("momentLevel", true); D("momentDungeon", true)
    D("momentGoal", true); D("momentRested", true)
    D("momentSeconds", 5); D("toastX", 0); D("toastTop", -70); D("toastScale", 1.2)
    D("tracker", true); D("trackerMax", 5); D("trackerX", -40); D("trackerY", -40)
    D("trackerReminders", true); D("trackerReminderMax", 5)
    D("style", "moderndark"); D("minimap", true); D("minimapAngle", 200)
    -- Bláto Journal: three page styles, the Forever look (modern dark) the default; anything else becomes it
    if DB.style ~= "classic" and DB.style ~= "moderndark" and DB.style ~= "modernparchment" then DB.style = "moderndark" end
    D("sounds", true); D("soundMaster", false)
    DB.sound = DB.sound or {}
    D("reminderSeconds", 8)
    D("questGroup", "day")
    D("autoPin", false)
    D("shareNotes", true)   -- Bláto Journal: new notes go to the shared notepad of the party (Together.lua)
    D("detail", "story"); D("fleetingMinutes", 10); D("questRewards", true); D("foldChapters", true)
    D("archiveReminders", true)   -- finished one-time reminders go to the archive
    D("archiveGoals", false)      -- reached goals go to the archive
    for k, v in pairs({ goal = "bell", zone = "page", dungeon = "none", level = "none", rested = "none", note = "none", reminder = "chime" }) do
        if DB.sound[k] == nil then DB.sound[k] = v end
    end
    -- the goal default changed from the quest chime to the bell; move anyone still on the old default
    if (DB.soundDefaults or 0) < 2 then
        if DB.sound.goal == "quest" then DB.sound.goal = "bell" end
        DB.soundDefaults = 2
    end
    H.started = H.started or time()
    H.levels = H.levels or {}      -- level -> { time, kills, quests, deaths, zones = { zone -> seconds }, reached, reachedZone }
    H.zones = H.zones or {}        -- zone -> { time, kills, quests, deaths, first, firstLevel, subs = { name -> { time, first, level } } }
    H.dungeons = H.dungeons or {}  -- instance name -> { runs, first }
    H.events = H.events or {}      -- { t, kind, text, zone, level }
    H.loot = H.loot or {}          -- your own finds, uncommon and up: { t, link, icon, quality, zone, subzone, level, from }
    H.goals = H.goals or {}
    H.notes = H.notes or {}         -- { id, t, text, zone, subzone, level, mapID, x, y, trigger?, repeats?, done?, firedAt?, pinned?, archived? }
    H.quests = H.quests or {}       -- completed quests: { id, t, questID, title, kind, zone, subzone, level, mapID, x, y, xp, money }
    H.subzones = H.subzones or {}   -- subzone -> zone, for recognising place names in reminders
    H.totals = H.totals or {}
    for _, k in ipairs({ "kills", "quests", "deaths", "runs", "time", "xp", "money" }) do H.totals[k] = H.totals[k] or 0 end
    H.mobs = H.mobs or {}           -- creature name -> kills (best guess from your target; see RecordKill)
    H.nextId = H.nextId or 1
    -- archive: notes, goals and quests carry archived = time; the 1.3 test build called it deleted
    for _, n in ipairs(H.notes) do if n.deleted then n.archived, n.deleted = n.archived or time(), nil end end
    for _, q in ipairs(H.quests) do if not q.id then q.id = J.NewId and J.NewId() or nil end end
end
J.Defaults()

-- Hooks the UI fills in; the core only calls them.
J.Moment = function() end
J.Changed = function() end

-- Small helpers -----------------------------------------------------------------------
function J.Zone() local z = GetRealZoneText and GetRealZoneText() or ""; return z ~= "" and z or nil end
function J.SubZone() local z = GetSubZoneText and GetSubZoneText() or ""; return z ~= "" and z or nil end
function J.Level() return UnitLevel("player") end
-- First and last name. On this client UnitName returns the surname as its second value (where retail puts the
-- realm of a player from another server), so join the two unless the second is a realm name.
function J.PlayerName()
    local function usable(v) return type(v) == "string" and v ~= "" and not (issecretvalue and issecretvalue(v)) and v or nil end
    local first, last = UnitName("player")
    first, last = usable(first) or "", usable(last)
    local realm = GetRealmName and usable(GetRealmName())
    if last and last ~= realm and last ~= (realm or ""):gsub("%s", "") then return first .. " " .. last end
    return first
end

function J.Dur(s)
    if not s or s < 60 then return "<1m" end
    local h, m = math.floor(s / 3600), math.floor(s % 3600 / 60)
    return h > 0 and ("%dh %dm"):format(h, m) or ("%dm"):format(m)
end
function J.Count(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end
function J.Date(t) return date("%b %d", t) end

-- A zone's corners from its "Explore <zone>" achievement: a list of { name, done }, or nil where the game has
-- none (cities, the tram, dungeons). The achievement IDs are looked up by name once.
local exploreIDs
function J.Explore(zone)
    if not zone or not (GetCategoryList and GetAchievementInfo and GetAchievementCriteriaInfo) then return nil end
    if not exploreIDs then
        exploreIDs = {}
        for _, cat in ipairs(GetCategoryList() or {}) do
            for i = 1, (GetCategoryNumAchievements(cat, true) or 0) do
                local id, name = GetAchievementInfo(cat, i)
                local z = type(name) == "string" and name:match("^Explore (.+)$")
                if z and id then exploreIDs[z] = id end
            end
        end
    end
    local id = exploreIDs[zone]
    if not id then return nil end
    local out = {}
    for c = 1, (GetAchievementNumCriteria(id) or 0) do
        local name, _, done = GetAchievementCriteriaInfo(id, c)
        if type(name) == "string" and name ~= "" then out[#out + 1] = { name = name, done = done and true or false } end
    end
    return #out > 0 and out or nil
end

-- How much the journal shows. Everything is always recorded; these only choose what the pages show.
J.DETAIL = {
    essentials = { spells = false, recipes = false, professions = false, respecs = false, mounts = true, bosses = true, deaths = true,
        zones = false, goals = true, lootMin = 4, repMin = "honored", keepsakes = true },
    story = { spells = true, recipes = true, professions = true, respecs = true, mounts = true, bosses = true, deaths = true,
        zones = true, goals = true, lootMin = 4, repMin = "all", keepsakes = true },
    chronicler = { spells = true, recipes = true, professions = true, respecs = true, mounts = true, bosses = true, deaths = true,
        zones = true, goals = true, lootMin = 3, repMin = "all", keepsakes = true },
}
J.DETAIL_ORDER = { { "essentials", "Essentials" }, { "story", "Storyteller" }, { "chronicler", "Chronicler" } }
function J.Shows(key)
    local preset = J.DETAIL[DB.detail] or J.DETAIL.story
    if DB.detail == "custom" and DB.show and DB.show[key] ~= nil then return DB.show[key] end
    return (DB.detail == "custom" and J.DETAIL.story or preset)[key]
end
-- change one setting: the current preset becomes a custom one
function J.SetShows(key, value)
    if DB.detail ~= "custom" then
        local from = J.DETAIL[DB.detail] or J.DETAIL.story
        DB.show = {}
        for k, v in pairs(from) do DB.show[k] = v end
        DB.detail = "custom"
    end
    DB.show[key] = value
end

function J.NewId() local id = H.nextId; H.nextId = id + 1; return id end

-- The journal keeps up to MAX_EVENTS moments (a whole 1-60 journey is a few thousand). Should it ever fill up,
-- the least important go first: plain rows before deaths and arrivals, and never levels, goals, notes or keepsakes.
local MAX_EVENTS = 20000
local function Worth(e)
    if e.keep or e.kind == "level" or e.kind == "goal" or e.kind == "goalset" then return 3 end
    if e.kind == "death" or e.kind == "zone" or e.kind == "dungeon" or e.kind == "profession" then return 2 end
    return 1
end
local function Trim()
    while #H.events > MAX_EVENTS do
        local drop
        for worth = 1, 3 do
            for i, e in ipairs(H.events) do if Worth(e) == worth then drop = i break end end
            if drop then break end
        end
        table.remove(H.events, drop or 1)
    end
end
-- extra: more fields for the entry (icon, sub, link, quality, keep = shown as a keepsake, ...)
function J.Log(kind, text, extra)
    local e = { t = time(), kind = kind, text = text, zone = J.Zone(), subzone = J.SubZone(), level = J.Level() }
    for k, v in pairs(extra or {}) do e[k] = v end
    table.insert(H.events, e)
    Trim()
    return e
end

local function LevelRec(level)
    H.levels[level] = H.levels[level] or { time = 0, kills = 0, quests = 0, deaths = 0, zones = {} }
    return H.levels[level]
end
J.LevelRec = LevelRec

-- The zone this level was mostly spent in.
function J.MainZone(rec)
    local best, bestT
    for z, t in pairs(rec.zones or {}) do if not bestT or t > bestT then best, bestT = z, t end end
    return best, bestT
end

-- Goals -------------------------------------------------------------------------------
-- kind: item (target = itemID), quests, runs, dungeon (target = instance name), level (need = level), zone (target), todo
local function ItemCount(itemID)
    local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(itemID) or (GetItemCount and GetItemCount(itemID))
    return count or 0
end

function J.GoalProgress(g)
    if g.done then return g.need, g.need end
    if g.kind == "item" then return math.min(ItemCount(g.target), g.need), g.need
    elseif g.kind == "quests" then return math.min(H.totals.quests - g.base, g.need), g.need
    elseif g.kind == "runs" then return math.min(H.totals.runs - g.base, g.need), g.need
    elseif g.kind == "dungeon" then
        local d = H.dungeons[g.target]
        return math.min((d and d.runs or 0) - g.base, g.need), g.need
    elseif g.kind == "level" then return math.min(J.Level(), g.need), g.need
    elseif g.kind == "zone" then return g.visited and 1 or 0, 1
    elseif g.kind == "kills" then return math.min(H.totals.kills - g.base, g.need), g.need
    elseif g.kind == "creature" then return math.min((H.mobs[g.target] or 0) - g.base, g.need), g.need
    elseif g.kind == "xp" then return math.min(H.totals.xp - g.base, g.need), g.need
    elseif g.kind == "gold" then return math.min(math.floor((H.totals.money - g.base) / 10000), g.need), g.need
    elseif g.kind == "skill" then
        local s = J.Skills()[g.target:lower()]
        return math.min(s and s.level or 0, g.need), g.need
    end
    return 0, 1   -- todo
end

local function Complete(g)
    g.done, g.doneAt = true, time()
    if DB.archiveGoals then g.archived = time() end
    J.Log("goal", "Goal reached: " .. g.label)
    if DB.momentGoal then J.Moment(("|cffffd100Goal reached|r  |cffb0b0b0·|r  %s"):format(g.label), "goal") end
end

function J.CheckGoals()
    for _, g in ipairs(H.goals) do
        if not g.done and not g.archived and g.kind ~= "todo" then
            local have, need = J.GoalProgress(g)
            if have >= need then Complete(g) end
        end
    end
    J.Changed()
end

function J.TickTodo(id)
    for _, g in ipairs(H.goals) do
        if g.id == id and g.kind == "todo" then
            if g.done then g.done, g.doneAt = nil, nil else Complete(g) end
        end
    end
    J.Changed()
end

function J.RemoveGoal(id)
    for i, g in ipairs(H.goals) do if g.id == id then table.remove(H.goals, i); break end end
    J.Changed()
end

function J.ClearDoneGoals()
    for _, g in ipairs(H.goals) do if g.done and not g.archived then g.archived = time() end end
    J.Changed()
end

-- Archive ---------------------------------------------------------------------------------
-- Notes, goals and quests can be archived: gone from their page until restored or deleted. A pinned note stays on
-- the Journey page while archived; deleting it from the archive removes it there too.
local LISTS = { note = "notes", goal = "goals", quest = "quests" }
function J.SetArchived(kind, id, on)
    for _, x in ipairs(H[LISTS[kind]]) do if x.id == id then x.archived = on and time() or nil end end
    J.Changed()
end
function J.DeleteItem(kind, id)
    local list = H[LISTS[kind]]
    for i, x in ipairs(list) do if x.id == id then table.remove(list, i); break end end
    J.Changed()
end
function J.Archived(kind)
    local out = {}
    for _, x in ipairs(H[LISTS[kind]]) do if x.archived then out[#out + 1] = x end end
    table.sort(out, function(a, b) return a.archived > b.archived end)
    return out
end

-- Finds an item from a shift-clicked link, an item ID, or a name (bags first, then the client's item cache).
function J.ResolveItem(text)
    local id = tonumber(text:match("item:(%d+)")) or tonumber(text)
    if not id and C_Container then
        local want = text:lower()
        for bag = 0, (NUM_BAG_SLOTS or 4) do
            for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                local name = info and info.itemName or (info and info.hyperlink and info.hyperlink:match("%[(.-)%]"))
                if name and name:lower() == want then id = info.itemID; break end
            end
            if id then break end
        end
    end
    if not id and C_Item and C_Item.GetItemInfoInstant then id = C_Item.GetItemInfoInstant(text) end
    if not id then return end
    local name = (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or (GetItemInfo and GetItemInfo(id)) or text:match("%[(.-)%]") or text
    return id, name
end

-- Profession and secondary skill levels, keyed by lower-case name: { name, level, max }.
-- Retail-style GetProfessions first, then the classic skill list; whichever this client has.
function J.Skills()
    local out = {}
    pcall(function()
        if GetProfessions and GetProfessionInfo then
            for _, idx in pairs({ GetProfessions() }) do
                local name, _, level, max = GetProfessionInfo(idx)
                if type(name) == "string" then out[name:lower()] = { name = name, level = level or 0, max = max } end
            end
        end
    end)
    pcall(function()
        if GetNumSkillLines and GetSkillLineInfo then
            for i = 1, GetNumSkillLines() do
                local name, header, _, level, _, _, max = GetSkillLineInfo(i)
                if not header and type(name) == "string" and not out[name:lower()] then
                    out[name:lower()] = { name = name, level = level or 0, max = max }
                end
            end
        end
    end)
    return out
end

-- True when the place is the zone or subzone you are standing in.
local function IsHere(place)
    place = place:lower()
    local zone, sub = J.Zone(), J.SubZone()
    return (zone and zone:lower() == place) or (sub and sub:lower() == place) or false
end

function J.CheckPlaceGoals()
    local hit = false
    for _, g in ipairs(H.goals) do
        if g.kind == "zone" and not g.done and not g.visited and IsHere(g.target) then g.visited, hit = true, true end
    end
    if hit then J.CheckGoals() end
end

-- Returns the new goal, or nil and a message explaining what is missing.
function J.AddGoal(kind, text, need)
    text = text and text:match("^%s*(.-)%s*$") or ""
    need = math.max(1, math.floor(tonumber(need) or 1))
    local g = { id = J.NewId(), kind = kind, need = need, created = time() }
    if kind == "item" then
        local id, name = J.ResolveItem(text)
        if not id then return nil, "Shift-click the item into the box, or type its exact name while you carry one." end
        g.target, g.name = id, name
        g.label = need > 1 and ("%d %s"):format(need, name) or name
    elseif kind == "quests" then
        g.base, g.label = H.totals.quests, ("Complete %s"):format(J.Count(need, "quest"))
    elseif kind == "runs" then
        g.base, g.label = H.totals.runs, ("Run %s"):format(J.Count(need, "dungeon"))
    elseif kind == "dungeon" then
        if text == "" then return nil, "Type the dungeon's name, e.g. The Deadmines." end
        -- match an already visited dungeon regardless of case
        for name in pairs(H.dungeons) do if name:lower() == text:lower() then text = name end end
        g.target = text
        g.base = H.dungeons[text] and H.dungeons[text].runs or 0
        g.label = need > 1 and ("Run %s %d times"):format(text, need) or ("Run %s"):format(text)
    elseif kind == "level" then
        g.label = ("Reach level %d"):format(need)
    elseif kind == "zone" then
        if text == "" then return nil, "Type the place's name, e.g. Stranglethorn Vale or Frostmane Hold." end
        g.target, g.label = text, ("Visit %s"):format(text)
        g.need = 1
        if IsHere(text) then g.visited = true end
    elseif kind == "skill" then
        if text == "" then return nil, "Type the profession's name, e.g. First Aid." end
        local s = J.Skills()[text:lower()]
        if s then text = s.name end
        g.target, g.label = text, ("Reach %d in %s"):format(need, text)
    elseif kind == "kills" then
        g.base, g.label = H.totals.kills, ("Defeat %s"):format(J.Count(need, "enemy"):gsub("enemys", "enemies"))
    elseif kind == "creature" then
        if text == "" then return nil, "Type the creature's name, or use your target." end
        for name in pairs(H.mobs) do if name:lower() == text:lower() then text = name end end
        g.target, g.base = text, H.mobs[text] or 0
        g.label = ("Defeat %d %s"):format(need, text)
    elseif kind == "xp" then
        g.base, g.label = H.totals.xp, ("Gain %s experience"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(need) or need)
    elseif kind == "gold" then
        g.base, g.label = H.totals.money, ("Earn %d gold"):format(need)
    elseif kind == "todo" then
        if text == "" then return nil, "Write what you want to do." end
        g.target, g.label, g.need = text, text, 1
    else
        return nil, "Unknown goal type."
    end
    table.insert(H.goals, g)
    J.Log("goalset", "New goal: " .. g.label)
    J.CheckGoals()
    return g
end

-- Notes ---------------------------------------------------------------------------------
function J.Position()
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if ok and pos then
        local x, y = pos:GetXY()
        if x and x > 0 then return mapID, x * 100, y * 100 end
    end
    return mapID
end

-- trigger (optional): a reminder trigger (see Reminders.lua); repeats: fire every time instead of once.
-- pinned: show it on the Journey page too; nil follows the "Pin new notes" setting.
function J.AddNote(text, trigger, repeats, pinned)
    text = text and text:match("^%s*(.-)%s*$") or ""
    if text == "" then return end
    local mapID, x, y = J.Position()
    local n = { id = J.NewId(), t = time(), text = text, zone = J.Zone(), subzone = J.SubZone(), level = J.Level(), mapID = mapID, x = x, y = y }
    if pinned == nil then pinned = DB.autoPin end
    n.pinned = pinned or nil
    table.insert(H.notes, n)
    if trigger and J.SetReminder then J.SetReminder(n, trigger, repeats) end
    J.Changed()
    return n
end

function J.EditNote(id, text)
    for i, n in ipairs(H.notes) do
        if n.id == id then
            text = text and text:match("^%s*(.-)%s*$") or ""
            if text == "" then table.remove(H.notes, i) else n.text = text end
            break
        end
    end
    J.Changed()
end

function J.DeleteNote(id) J.EditNote(id, "") end

-- Pinned notes also show on the Journey page, under the level they were written at.
function J.TogglePin(id)
    for _, n in ipairs(H.notes) do if n.id == id then n.pinned = not n.pinned or nil end end
    J.Changed()
end

-- Completed quests ----------------------------------------------------------------------
-- The title can be secret on this client (e.g. in instances); fall back to the quest ID then.
local function QuestTitle(questID)
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(questID)
    if issecretvalue and issecretvalue(title) then title = nil end
    if type(title) ~= "string" or title == "" then return nil end
    return title
end

-- Kind of quest, read while it is still in the log: its tag (Dungeon, Elite, Group...), else daily/weekly, else Normal.
local function QuestType(questID)
    local ok, kind = pcall(function()
        local tag = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(questID)
        local name = tag and tag.tagName
        if type(name) == "string" and name ~= "" then return name end
        local idx = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
        local info = idx and C_QuestLog.GetInfo(idx)
        local freq = info and info.frequency
        if freq == 1 then return "Daily" elseif freq == 2 then return "Weekly" end
        return "Normal"
    end)
    if not ok or (issecretvalue and issecretvalue(kind)) or type(kind) ~= "string" then return nil end
    return kind
end

local MAX_QUESTS = 2000
function J.RecordQuest(questID, xp, money)
    local mapID, x, y = J.Position()
    local q = { id = J.NewId(), t = time(), questID = questID, title = questID and QuestTitle(questID), zone = J.Zone(), subzone = J.SubZone(),
        level = J.Level(), mapID = mapID, x = x, y = y, xp = tonumber(xp), money = tonumber(money),
        kind = questID and QuestType(questID) }
    table.insert(H.quests, q)
    while #H.quests > MAX_QUESTS do table.remove(H.quests, 1) end
    -- the title may only resolve a moment later once the quest data arrives
    if not q.title and questID then
        C_Timer.After(1, function() q.title = QuestTitle(questID); if q.title then J.Changed() end end)
    end
end

function J.QuestName(q) return q.title or (q.questID and ("Quest #%d"):format(q.questID)) or "A quest" end

function J.NoteWhere(n)
    local where = n.subzone and n.zone and n.subzone ~= n.zone and (n.subzone .. ", " .. n.zone) or n.zone or "Unknown place"
    if n.x then where = ("%s (%.1f, %.1f)"):format(where, n.x, n.y) end
    return where
end

-- Tracking ------------------------------------------------------------------------------
local lastCombat, lastQuestTime = 0, -10
local lastXP, lastMax, lastLevel
local lastMoney
local currentRun          -- { name, left } while a dungeon run may still continue

-- Which creature died? Without the combat log we can only guess: your target if it is dead, otherwise the
-- last enemy you had targeted in the past few seconds (targets are often cleared when they die).
local lastEnemy, lastEnemyTime = nil, 0
local function SafeName(unit)
    local ok, name = pcall(UnitName, unit)
    if not ok or type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then return end
    return name
end
local function NoteTarget()
    if UnitExists("target") and not UnitIsPlayer("target") and UnitCanAttack("player", "target") then
        local name = SafeName("target")
        if name then lastEnemy, lastEnemyTime = name, GetTime() end
    elseif lastEnemy then
        lastEnemyTime = GetTime()   -- target lost (often because it died): the last enemy stays the best guess for a moment
    end
end
local function KilledName()
    if UnitExists("target") and not UnitIsPlayer("target") and UnitIsDead("target") then
        local name = SafeName("target")
        if name then return name end
    end
    if lastEnemy and GetTime() - lastEnemyTime < 8 then return lastEnemy end
end

local function RecordKill(name)
    local lvl, zone = J.Level(), J.Zone()
    H.totals.kills = H.totals.kills + 1
    LevelRec(lvl).kills = LevelRec(lvl).kills + 1
    if zone and H.zones[zone] then H.zones[zone].kills = H.zones[zone].kills + 1 end
    if name then H.mobs[name] = (H.mobs[name] or 0) + 1 end
end

-- Kills from the game's own Statistics ("Creatures killed"), where the client has them: they count every kill,
-- also where you get no XP (at the level cap, grey mobs). Counted as the number goes up. Without them, kills are
-- guessed from XP gains in or just after combat (below).
local killStat, lastStatKills
local function StatValue(id)
    local ok, v = pcall(GetStatistic, id)
    if not ok or type(v) ~= "string" or (issecretvalue and issecretvalue(v)) then return nil end
    return tonumber((v:gsub("%D", ""))) or 0   -- "--" before the first kill
end
local function FindKillStat()
    if not GetStatistic then return nil end
    -- the usual ids first, then by name through the statistics categories
    for _, id in ipairs({ 107, 1197 }) do
        local ok, _, name = pcall(GetAchievementInfo, id)
        if ok and type(name) == "string" and name:lower():find("creatures killed") and StatValue(id) then return id end
    end
    local ok, cats = pcall(GetStatisticsCategoryList)
    for _, cat in ipairs(ok and cats or {}) do
        for i = 1, (GetCategoryNumAchievements(cat) or 0) do
            local id, name = GetAchievementInfo(cat, i)
            if type(name) == "string" and name:lower():find("creatures killed") and StatValue(id) then return id end
        end
    end
end
function J.KillStat() return killStat end
local function CheckStatKills()
    if not killStat then return end
    local now = StatValue(killStat)
    if not now then return end
    if lastStatKills and now > lastStatKills and now - lastStatKills < 100 then
        local name = KilledName()
        for i = 1, now - lastStatKills do RecordKill(i == 1 and name or nil) end
        J.CheckGoals()
    end
    lastStatKills = now
end
C_Timer.NewTicker(2, function() pcall(CheckStatKills) end)
J.CheckStatKills = CheckStatKills   -- for the test harness
function J.StartKillStat()
    killStat = FindKillStat()
    lastStatKills = killStat and StatValue(killStat) or nil
    if DB.debug then print("BlatoJournal: kills counted from " .. (killStat and ("the statistic #" .. killStat) or "XP gains")) end
end

local function OnXP()
    local ok, cur, max, lvl = pcall(function() return UnitXP("player") + 0, UnitXPMax("player") + 0, UnitLevel("player") + 0 end)
    if not ok then return end
    if not lastXP then lastXP, lastMax, lastLevel = cur, max, lvl; return end
    local gained = 0
    if lvl > lastLevel then gained = (lastMax - lastXP) + cur          -- across a level up
    elseif cur > lastXP then gained = cur - lastXP
    elseif cur < lastXP then return end                               -- XP reset before the level number caught up
    lastXP, lastMax, lastLevel = cur, max, lvl
    if gained <= 0 then return end
    H.totals.xp = H.totals.xp + gained
    local name = KilledName()
    local when = GetTime()
    -- decide a moment later, so a quest turn-in that arrives after the XP update is not counted as a kill
    C_Timer.After(0.3, function()
        if when - lastQuestTime < 1.5 or GetTime() - lastQuestTime < 0.5 then return end
        if not killStat and (UnitAffectingCombat("player") or when - lastCombat < 4) then RecordKill(name) end
        J.CheckGoals()
    end)
end

local function InDungeon()
    local inInstance, kind = IsInInstance()
    return inInstance and (kind == "party" or kind == "raid")
end

local function EnterZone()
    local zone = J.Zone()
    if not zone then return end
    -- dungeons are kept under their own heading, with their own moment, not as places
    if not InDungeon() and not H.zones[zone] then
        local first = next(H.zones) == nil
        H.zones[zone] = { time = 0, kills = 0, quests = 0, deaths = 0, first = time(), firstLevel = J.Level() }
        local text = first and ("The journal begins in %s"):format(zone) or ("New chapter: %s"):format(zone)
        J.Log("zone", text)
        if DB.momentZone then J.Moment(("|cffffd100%s|r"):format(text), "zone") end
    end
    J.CheckPlaceGoals()
    -- dungeon runs: entering again within 30 minutes of leaving the same instance is the same run
    if InDungeon() then
        local name = GetInstanceInfo()
        if name and not (currentRun and currentRun.name == name and (not currentRun.left or time() - currentRun.left < 1800)) then
            local d = H.dungeons[name]
            local firstTime = not d
            H.dungeons[name] = d or { runs = 0, first = time(), time = 0 }
            H.dungeons[name].runs = H.dungeons[name].runs + 1
            H.totals.runs = H.totals.runs + 1
            -- only the first visit is a moment; later runs are counted on the dungeon itself
            if firstTime then J.Log("dungeon", ("First time in %s"):format(name)) end
            if firstTime and DB.momentDungeon then J.Moment(("|cffffd100First time in %s|r"):format(name), "dungeon") end
            -- each run keeps a line of its own: when, how long inside, bosses down (Chronicle), who came (Fellowship)
            local dd = H.dungeons[name]
            dd.history = dd.history or {}
            table.insert(dd.history, { t = time(), time = 0, bosses = 0, level = J.Level() })
            currentRun = { name = name, t = time(), index = #dd.history }
        end
        if not (currentRun and currentRun.name == name and currentRun.t) then currentRun = { name = name, t = time() } end
        currentRun.left = nil
        H.currentRun = currentRun
    elseif currentRun and not currentRun.left then
        currentRun.left = time()
    end
    J.CheckGoals()
end

local function OnLevelUp(newLevel)
    local prev = H.levels[newLevel - 1]
    local rec = LevelRec(newLevel)
    rec.reached, rec.reachedZone = time(), J.Zone()
    J.Log("level", ("Reached level %d in %s"):format(newLevel, rec.reachedZone or "an unknown place"))
    if DB.momentLevel and prev and prev.time > 0 then
        -- the game announces the level itself; the journal adds how the last one went
        local zone = J.MainZone(prev)
        J.Moment(("|cffffd100Level %d|r took %s%s"):format(newLevel - 1, J.Dur(prev.time), zone and (" in " .. zone) or ""), "level")
    end
    J.CheckGoals()
end

-- Rested XP gained while logged out, as a share of a level.
local function RestedOnLogin()
    local now = GetXPExhaustion and GetXPExhaustion() or 0
    local max = UnitXPMax("player") or 0
    local before = H.lastRested
    H.lastRested = now
    if not (before and max > 0 and DB.momentRested) then return end
    local gained = (now - before) / max * 100
    if gained >= 5 then
        J.Moment(("|cff4da6ffWell rested|r  |cffb0b0b0·|r  %d%% of a level"):format(now / max * 100 + 0.5), "rested")
    end
end

-- Adopt saved variables. The newest copy wins (see Kit.lua, Saved data). The journal of each character is kept
-- twice: in the per-character file (BJ_Char) and in the account file (BJ_Chars), so the one !ForeverData link
-- to the account's SavedVariables folder covers every character.
-- The account copy is keyed by the character's GUID. Up to 1.2 it was keyed by name, but characters can share a
-- first name, and then shared one journal there (the newest one won for both).
local function CharKey()
    local guid = UnitGUID and UnitGUID("player")
    if type(guid) == "string" and guid ~= "" and not (issecretvalue and issecretvalue(guid)) then return guid end
end
local function OldKey()
    local name, realm = UnitName("player"), GetRealmName and GetRealmName()
    if type(name) == "string" and type(realm) == "string" and name ~= "" and realm ~= "" then return name .. "-" .. realm end
end
-- A saved journal only counts for this character if it is this character's: each is tagged with its owner's GUID.
local function Mine(t, key)
    if type(t) ~= "table" or not key then return t end
    if t._owner and t._owner ~= key then return nil end
    return t
end
local function AdoptSaved()
    local src = Kit.PickSaved(DB, BJ_DB, BJ_DBC)
    if src then Mixin(DB, src) end
    BJ_DB, BJ_DBC = DB, DB
    BJ_Chars = type(BJ_Chars) == "table" and BJ_Chars or {}
    local key = CharKey()
    local own = key and Mine(BJ_Chars[key], key)
    -- the old name-keyed account copy may belong to a namesake: only use it when nothing else is there
    local old = OldKey()
    local legacy = old and BJ_Chars[old]
    if type(legacy) == "table" and (legacy._owner and legacy._owner ~= key
        or (not legacy._owner and ((type(BJ_Char) == "table" and next(BJ_Char)) or own))) then legacy = nil end
    local hist = Kit.PickSaved(H, Mine(BJ_Char, key), own, Mine(legacy, key))
    if hist then Mixin(H, hist) end
    BJ_Char = H
    if key then BJ_Chars[key] = H; H._owner = key end
    J.Defaults()
    currentRun = H.currentRun
end
Kit.StampOnLogout(function() return DB end)
Kit.StampOnLogout(function() return H end)
J.AdoptSaved = AdoptSaved

local ev = CreateFrame("Frame")
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_XP_UPDATE",
    "PLAYER_LEVEL_UP", "QUEST_TURNED_IN", "PLAYER_DEAD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "BAG_UPDATE_DELAYED", "PLAYER_LOGOUT", "PLAYER_TARGET_CHANGED", "PLAYER_MONEY",
    "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "SKILL_LINES_CHANGED", "CHAT_MSG_SKILL" }) do
    pcall(ev.RegisterEvent, ev, e)   -- not every client has every event
end
local loggedIn = false
ev:SetScript("OnEvent", function(_, event, a1, a2, a3)
    if event == "ADDON_LOADED" then
        if a1 == "BlatoJournal" then AdoptSaved() end
    elseif event == "PLAYER_LOGIN" then
        AdoptSaved()
        lastXP, lastMax, lastLevel = UnitXP("player"), UnitXPMax("player"), UnitLevel("player")
        lastMoney = GetMoney()
        C_Timer.After(4, RestedOnLogin)
        C_Timer.After(3, function() pcall(J.StartKillStat) end)
        loggedIn = true
        J.Changed()
    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        if loggedIn then EnterZone() end
    elseif event == "PLAYER_XP_UPDATE" then
        OnXP()
    elseif event == "PLAYER_LEVEL_UP" then
        OnLevelUp(tonumber(a1) or J.Level())
    elseif event == "QUEST_TURNED_IN" then
        lastQuestTime = GetTime()
        J.RecordQuest(a1, a2, a3)
        local lvl, zone = J.Level(), J.Zone()
        H.totals.quests = H.totals.quests + 1
        LevelRec(lvl).quests = LevelRec(lvl).quests + 1
        if zone and H.zones[zone] then H.zones[zone].quests = H.zones[zone].quests + 1 end
        J.CheckGoals()
    elseif event == "PLAYER_DEAD" then
        local lvl, zone = J.Level(), J.Zone()
        H.totals.deaths = H.totals.deaths + 1
        LevelRec(lvl).deaths = LevelRec(lvl).deaths + 1
        if zone and H.zones[zone] then H.zones[zone].deaths = H.zones[zone].deaths + 1 end
        local sub = J.SubZone()
        J.Log("death", ("Died in %s"):format(sub and zone and sub ~= zone and (sub .. ", " .. zone) or zone or "an unknown place"))
        J.Changed()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        lastCombat = GetTime()
    elseif event == "PLAYER_TARGET_CHANGED" then
        NoteTarget()
    elseif event == "PLAYER_MONEY" then
        local now = GetMoney()
        if lastMoney and now > lastMoney then H.totals.money = H.totals.money + (now - lastMoney); J.CheckGoals() end
        lastMoney = now
    elseif event == "BAG_UPDATE_DELAYED" or event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        J.CheckGoals()
    elseif event == "ZONE_CHANGED" or event == "ZONE_CHANGED_INDOORS" then
        J.CheckPlaceGoals()
    elseif event == "PLAYER_LOGOUT" then
        H.lastRested = GetXPExhaustion and GetXPExhaustion() or 0
    end
end)

-- Time at each level and in each zone, counted while logged in and not AFK.
function J.Tick()
    if not loggedIn then return end
    -- UnitIsAFK can return a secret boolean (e.g. inside instances); testing it errors, so treat secret as not AFK.
    local afk = UnitIsAFK and UnitIsAFK("player")
    if issecretvalue and issecretvalue(afk) then afk = false end
    if afk then return end
    local lvl, zone = J.Level(), J.Zone()
    H.totals.time = H.totals.time + 1
    local rec = LevelRec(lvl)
    rec.time = rec.time + 1
    if zone then
        rec.zones[zone] = (rec.zones[zone] or 0) + 1
        local z = H.zones[zone]
        if z and not H.dungeons[zone] then   -- time inside a dungeon belongs to the dungeon
            z.time = z.time + 1
            -- time per subzone, for the place's own page: subs[name] = { time, first, level }
            local sub = J.SubZone()
            if sub and sub ~= zone then
                z.subs = z.subs or {}
                local sr = z.subs[sub]
                if not sr then sr = { time = 0, first = time(), level = lvl }; z.subs[sub] = sr end
                sr.time = sr.time + 1
            end
        end
    end
    if currentRun and not currentRun.left and H.dungeons[currentRun.name] then
        local d = H.dungeons[currentRun.name]
        d.time = (d.time or 0) + 1
        local run = currentRun.index and d.history and d.history[currentRun.index]
        if run then run.time = run.time + 1 end
    end
end
C_Timer.NewTicker(1, J.Tick)

-- Let ForeverImmersion fade the goal tracker like any other element (plain data; see ForeverImmersion).
ForeverUI = ForeverUI or {}
ForeverUI.elements = ForeverUI.elements or {}
table.insert(ForeverUI.elements, { key = "forever:journalgoals", label = "Journal tracker", frames = { "BlatoJournalTracker" },
    visible = { idle = true, resting = true, mounted = true, key = true } })
ForeverUI.revision = (ForeverUI.revision or 0) + 1
