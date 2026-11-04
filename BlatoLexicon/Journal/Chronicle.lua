-- BlatoLexicon chronicle: the smaller moments of a journey, caught as they happen and written into the
-- Journey page. Spells and recipes, professions and skill caps, reputation, epic finds, bosses, mounts and pets,
-- talent re-specs, and where each quest came from. The big ones (first boss kills, epic finds, Honored and up)
-- are marked keep = true and show as keepsakes.
local _, ns = ...
local J = ns.J
local DB, H = J.DB, J.H

-- Text the game hands us can be secret inside instances; only plain strings are kept.
local function Plain(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v ~= "" and v or nil end
local function NPC()
    if not UnitExists("npc") then return nil end
    local ok, name = pcall(UnitName, "npc")
    return ok and Plain(name) or nil
end
-- A game format string ("You have learned a new spell: %s.") as a Lua pattern that captures its %s parts.
local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    fmt = fmt:gsub("%%%d%$", "%%"):gsub("%%s", "\1"):gsub("%%d", "\2")
    fmt = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1"):gsub("\1", "(.+)"):gsub("\2", "(%%d+)")
    return "^" .. fmt .. "$"
end

-- Nothing is written in the first seconds after logging in: the game replays spells and skills then.
local ready = false
local recent = {}   -- name -> the entry logged for it in the last seconds (a spell that turns out to be a recipe)
local function Fresh(name) local r = recent[name]; return r and time() - r.t < 6 and r or nil end

local function SpellInfo(id)
    local name, rank, icon
    if C_Spell and C_Spell.GetSpellName then name, icon = C_Spell.GetSpellName(id), C_Spell.GetSpellTexture(id)
    elseif GetSpellInfo then local n, _, ic = GetSpellInfo(id); name, icon = n, ic end
    if C_Spell and C_Spell.GetSpellSubtext then rank = C_Spell.GetSpellSubtext(id) elseif GetSpellSubtext then rank = GetSpellSubtext(id) end
    return Plain(name), Plain(rank), icon
end
local function LearnSpell(name, rank, icon)
    if not name or Fresh(name) then return end
    local e = J.Log("spell", ("Learned %s%s"):format(name, rank and (" (" .. rank .. ")") or ""), { icon = icon })
    recent[name] = e
    J.Changed()
end
local function LearnRecipe(name)
    local e = Fresh(name)
    if e then e.kind, e.text = "recipe", "Recipe: " .. name
    else recent[name] = J.Log("recipe", "Recipe: " .. name) end
    J.Changed()
end

-- Professions and skills: a new one learned, a profession at its trainer cap, a weapon skill at 300.
local skills
local PRO_CAPS = { [75] = true, [150] = true, [225] = true, [300] = true }
local function CheckSkills()
    local now = J.Skills()
    if not skills then skills = now; return end
    local pros = {}
    pcall(function() for _, idx in pairs({ GetProfessions() }) do local n = GetProfessionInfo(idx); if n then pros[n:lower()] = true end end end)
    for key, s in pairs(now) do
        local was = skills[key]
        if not was then
            if pros[key] then J.Log("profession", "Became a student of " .. s.name, { sub = "Starting out at " .. (s.level or 1) }) end
        elseif (was.level or 0) < (s.level or 0) and s.max and s.level == s.max then
            if pros[key] and PRO_CAPS[s.max] and s.max < 300 then
                J.Log("skill", ("%s reached %d"):format(s.name, s.level), { sub = "Time to visit a trainer" })
            elseif s.max >= 300 then
                J.Log("skill", ("Mastered %s"):format(s.name), { sub = ("%d of %d"):format(s.level, s.max), keep = pros[key] or nil })
            end
        end
    end
    skills = now
    J.Changed()
end

-- Reputation: every new standing is a line; Honored and up is a keepsake.
local KEEP_STANDING = {}
for i = 6, 8 do local l = _G["FACTION_STANDING_LABEL" .. i]; if l then KEEP_STANDING[l] = true end end
local STANDING = Pattern(FACTION_STANDING_CHANGED)   -- "You are now %s with %s."
local function Reputation(msg)
    local standing, faction = msg:match(STANDING or "^$")
    if not standing then return end
    J.Log("rep", ("%s now counts you as %s"):format(faction, standing), { faction = faction, standing = standing, keep = KEEP_STANDING[standing] or nil })
    J.Changed()
end

-- Bosses: every kill is a line; the first kill of each boss is a keepsake, and an epic that drops soon after
-- is tied to it instead of getting its own.
local lastBoss   -- { boss, t, keepsake = the first-kill entry if this was it }
-- What each boss is, read from the boss frames while the fight is on: its creature type and, for beasts, family.
-- The icon follows from it (the Adventure Guide's portraits don't cover Forever's own dungeons).
local BOSS_TYPE_ICON = {
    Beast = "Interface/Icons/Ability_Hunter_BeastTaming", Undead = "Interface/Icons/Spell_Shadow_RaiseDead",
    Demon = "Interface/Icons/Spell_Shadow_Metamorphosis", Dragonkin = "Interface/Icons/INV_Misc_Head_Dragon_01",
    Elemental = "Interface/Icons/Spell_Nature_EarthElemental_Totem", Giant = "Interface/Icons/Ability_Warrior_Titansgrip",
    Mechanical = "Interface/Icons/INV_Gizmo_02", Humanoid = "Interface/Icons/INV_Misc_Head_Human_01",
    Aberration = "Interface/Icons/Spell_Shadow_Charm", Critter = "Interface/Icons/INV_Misc_Rabbit_2",
}
local BOSS_FAMILY_ICON = {
    Wolf = "Interface/Icons/Ability_Hunter_Pet_Wolf", Spider = "Interface/Icons/Ability_Hunter_Pet_Spider",
    Bear = "Interface/Icons/Ability_Hunter_Pet_Bear", Boar = "Interface/Icons/Ability_Hunter_Pet_Boar",
    Cat = "Interface/Icons/Ability_Hunter_Pet_Cat", Raptor = "Interface/Icons/Ability_Hunter_Pet_Raptor",
    Crocolisk = "Interface/Icons/Ability_Hunter_Pet_Crocolisk", Bat = "Interface/Icons/Ability_Hunter_Pet_Bat",
    Gorilla = "Interface/Icons/Ability_Hunter_Pet_Gorilla", Hyena = "Interface/Icons/Ability_Hunter_Pet_Hyena",
    Scorpid = "Interface/Icons/Ability_Hunter_Pet_Scorpid", Turtle = "Interface/Icons/Ability_Hunter_Pet_Turtle",
    ["Carrion Bird"] = "Interface/Icons/Ability_Hunter_Pet_Vulture", Owl = "Interface/Icons/Ability_Hunter_Pet_Owl",
    ["Wind Serpent"] = "Interface/Icons/Ability_Hunter_Pet_WindSerpent", Crab = "Interface/Icons/Ability_Hunter_Pet_Crab",
    Tallstrider = "Interface/Icons/Ability_Hunter_Pet_TallStrider",
}
local HUMANOID_RACE_ICON = { Murloc = "Interface/Icons/INV_Misc_Head_Murloc_01", Gnoll = "Interface/Icons/INV_Misc_MonsterHead_02",
    Kobold = "Interface/Icons/INV_Misc_Head_Kobold_01", Troll = "Interface/Icons/INV_Misc_Head_Troll_01",
    Orc = "Interface/Icons/INV_Misc_Head_Orc_01", Tauren = "Interface/Icons/INV_Misc_Head_Tauren_01" }
-- The Adventure Guide's portrait of the boss, where the guide has this dungeon (Blizzard's, not Forever's own).
local function GuideIcon(encounterID, name)
    if not (EJ_GetInstanceForMap and EJ_GetEncounterInfoByIndex and EJ_GetCreatureInfo) then return nil end
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local journal = mapID and EJ_GetInstanceForMap(mapID)
    if not journal or journal == 0 then return nil end
    for i = 1, 40 do
        local ename, _, jEncounter, _, _, _, dEncounter = EJ_GetEncounterInfoByIndex(i, journal)
        if not ename then break end
        if (encounterID and dEncounter == encounterID) or ename == name then
            local _, _, _, _, image = EJ_GetCreatureInfo(1, jEncounter)
            return image
        end
    end
end
-- The dungeon's own icon from the group finder (Interface/LFGFrame/LFGIcon-*), kept per dungeon name. Inside an
-- instance the boss's name and kind are secret to addons, but the dungeon is known.
local function DungeonIcon()
    local ok, name, _, _, _, _, _, _, _, _, lfgID = pcall(GetInstanceInfo)
    name = ok and Plain(name)
    if not name or not lfgID or lfgID == 0 or not GetLFGDungeonInfo then return nil, name end
    local ok2, texture = pcall(function() return select(11, GetLFGDungeonInfo(lfgID)) end)
    texture = ok2 and Plain(texture)
    if not texture then return nil, name end
    local icon = "Interface\\LFGFrame\\LFGIcon-" .. texture
    H.dungeons[name] = H.dungeons[name] or { runs = 0, first = time(), time = 0 }
    H.dungeons[name].icon = icon
    return icon, name
end
J.DungeonIcon = DungeonIcon
-- The boss's model: a hidden model frame takes a unit and reports its display ID, from which the game can draw
-- the creature's portrait later (SetPortraitTextureFromCreatureDisplayID). Inside an instance the boss's name is
-- secret, so the boss is picked as the elite you (or your group) are fighting, dead at the end of the fight.
local probe = CreateFrame("PlayerModel", nil, UIParent)
probe:SetSize(2, 2); probe:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -50, 50); probe:SetAlpha(0)
local function DisplayOf(unit)
    if not UnitExists(unit) then return nil end
    local ok = pcall(probe.SetUnit, probe, unit)
    if not ok then return nil end
    local ok2, id = pcall(probe.GetDisplayInfo, probe)
    if not ok2 or (issecretvalue and issecretvalue(id)) then return nil end
    id = tonumber(id)
    return id and id > 0 and id or nil
end
J.DisplayOf = DisplayOf
local function IsElite(u)
    local ok, c = pcall(UnitClassification, u)
    return ok and not (issecretvalue and issecretvalue(c)) and (c == "elite" or c == "worldboss" or c == "rareelite") or false
end
local function IsDead(u)
    local ok, d = pcall(UnitIsDead, u)
    return ok and not (issecretvalue and issecretvalue(d)) and d or false
end
local fightModel   -- display ID of the elite being fought, from the fight's start
local function FightUnits()
    local out = { "boss1", "target", "focus" }
    for i = 1, 4 do out[#out + 1] = "party" .. i .. "target" end
    return out
end
local function ModelAtStart()
    for _, u in ipairs(FightUnits()) do
        if UnitExists(u) and IsElite(u) and not IsDead(u) then local id = DisplayOf(u); if id then return id end end
    end
end
local function ModelAtEnd()
    -- the elite lying dead as the fight ends is the boss
    for _, u in ipairs(FightUnits()) do
        if UnitExists(u) and IsElite(u) and IsDead(u) then local id = DisplayOf(u); if id then return id end end
    end
    return fightModel
end
local seenBosses = {}
local encounterName
local lastModel   -- set as a fight ends, read by Boss()
-- Where a boss can be seen: the boss frames (not every dungeon has them), your target and focus, your group's
-- targets, and the nameplates. want: only record the unit with this name (the encounter's).
local function BossUnits()
    local out = {}
    for i = 1, 8 do out[#out + 1] = "boss" .. i end
    for _, u in ipairs({ "target", "focus", "mouseover" }) do out[#out + 1] = u end
    for i = 1, 4 do out[#out + 1] = "party" .. i .. "target" end
    for i = 1, 40 do out[#out + 1] = "nameplate" .. i end
    return out
end
local function ReadBosses(want)
    for _, u in ipairs(BossUnits()) do
        local isBoss = u:find("^boss")
        if UnitExists(u) and (isBoss or want) then
            local ok, name = pcall(UnitName, u)
            name = ok and Plain(name)
            if name and (isBoss or name == want) then
                local ok1, ctype = pcall(UnitCreatureType, u)
                local ok2, family = pcall(UnitCreatureFamily, u)
                ctype, family = ok1 and Plain(ctype) or nil, ok2 and Plain(family) or nil
                local icon = family and BOSS_FAMILY_ICON[family] or ctype and BOSS_TYPE_ICON[ctype]
                for race, ic in pairs(HUMANOID_RACE_ICON) do if name:find(race) then icon = ic end end
                seenBosses[name] = { type = ctype, family = family, icon = icon }
            end
        end
    end
end
local function Boss(name, success, encounterID)
    name = Plain(name)
    if not name or success ~= 1 then return end
    H.bosses = H.bosses or {}
    local first = not H.bosses[name]
    H.bosses[name] = (H.bosses[name] or 0) + 1
    local run = H.currentRun
    if run then
        run.bosses = (run.bosses or 0) + 1
        local d = run.index and H.dungeons[run.name] and H.dungeons[run.name].history
        local line = d and d[run.index]
        if line then line.bosses = (line.bosses or 0) + 1; line.names = line.names or {}; table.insert(line.names, name) end
    end
    if first then
        local instance = Plain((GetInstanceInfo()))
        -- the encounter's name usually is the boss's; when it isn't (a council, a boss on a mount), a lone boss seen is it
        local what = seenBosses[name]
        if not what then local only; for _, w in pairs(seenBosses) do only = only == nil and w or false end; what = only or nil end
        what = what or {}
        -- the guide's portrait first, then the dungeon's own icon, then the creature's kind (where it isn't secret)
        local ok, portrait = pcall(GuideIcon, tonumber(encounterID), name)
        if ok and portrait then what = { type = what.type, family = what.family, icon = portrait, portrait = true }
        else
            local ok2, dicon = pcall(DungeonIcon)
            if ok2 and dicon then what = { type = what.type, family = what.family, icon = dicon, dungeonIcon = true } end
        end
        local e = J.Log("boss", "Defeated " .. name, { boss = name, instance = instance, first = true, keep = true, runBosses = run and run.bosses,
            icon = what.icon, portrait = what.portrait, creatureType = what.type, family = what.family, model = lastModel })
        lastBoss = { boss = name, t = time(), keepsake = e }
    else
        -- a later kill is counted on the first one instead of adding a row
        for i = #H.events, 1, -1 do
            local e = H.events[i]
            if e.kind == "boss" and e.boss == name then e.kills = (e.kills or 1) + 1; e.lastKill = time() break end
        end
        lastBoss = { boss = name, t = time() }
    end
    J.Changed()
end

-- Loot: epic and better. The link's colour gives the quality even before the item data has loaded.
local QUALITY_BY_COLOR = { ff1eff00 = 2, ff0070dd = 3, ffa335ee = 4, ffff8000 = 5, ffe6cc80 = 6, ff00ccff = 7 }
local MAX_LOOT = 5000
local LOOT = {}
for _, g in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF" }) do
    local p = Pattern(_G[g]); if p then LOOT[#LOOT + 1] = p end
end
local function Loot(msg)
    if not Plain(msg) then return end
    local mine = false
    for _, p in ipairs(LOOT) do if msg:match(p) then mine = true break end end
    -- "[Loot]: [Item]" is Forever announcing an item up for a roll to the whole group: not yours (yet). A roll you
    -- win still ends in "You receive loot: ..." like any other.
    if not mine then return end
    -- older links carry a colour (|cffa335ee), newer ones the quality itself (|cnIQ4:)
    local color, body = msg:match("|c(%x%x%x%x%x%x%x%x)(|Hitem:.-|h.-|h)|r")
    local q = color and QUALITY_BY_COLOR[color:lower()]
    local link = color and ("|c" .. color .. body .. "|r")
    if not color then
        local iq, body2 = msg:match("|cnIQ(%d):(|Hitem:.-|h.-|h)|r")
        q = tonumber(iq)
        link = iq and ("|cnIQ" .. iq .. ":" .. body2 .. "|r")
    end
    if not q or q < 2 then return end
    local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(link) or (GetItemIcon and GetItemIcon(link))
    local ok, _, _, _, _, _, itemType, subType = pcall(C_Item and C_Item.GetItemInfo or GetItemInfo, link)
    local recentBoss = lastBoss and time() - lastBoss.t < 180 and lastBoss.boss or nil
    -- every find of uncommon and up goes in the loot log (the pages choose which qualities they show)
    table.insert(H.loot, { t = time(), link = link, icon = icon, quality = q, itemKind = ok and Plain(subType) or nil,
        zone = J.Zone(), subzone = J.SubZone(), level = J.Level(), from = recentBoss })
    while #H.loot > MAX_LOOT do table.remove(H.loot, 1) end
    if q < 4 then J.Changed(); return end
    local find = { link = link, icon = icon, quality = q, kind = ok and Plain(subType) or nil }
    if lastBoss and lastBoss.keepsake and time() - lastBoss.t < 180 then
        local card = lastBoss.keepsake   -- the loot hangs from the first-kill card
        find.from = card.boss
        card.loot = card.loot or {}
        table.insert(card.loot, find)
    else
        J.Log("loot", "Found " .. link, { link = link, icon = icon, quality = q, itemKind = find.kind,
            from = recentBoss, keep = true })
    end
    J.Changed()
end

-- Mounts and pets, where the client announces them.
local function Mount(id)
    if not (C_MountJournal and C_MountJournal.GetMountInfoByID) then return end
    local name, _, icon = C_MountJournal.GetMountInfoByID(id)
    if Plain(name) then J.Log("mount", "New mount: " .. name, { icon = icon }); J.Changed() end
end
local function Pet(guid)
    if not (C_PetJournal and C_PetJournal.GetPetInfoByPetID) then return end
    local _, custom, _, _, _, _, _, name, icon = C_PetJournal.GetPetInfoByPetID(guid)
    name = Plain(custom) or Plain(name)
    if name then J.Log("pet", "New companion: " .. name, { icon = icon }); J.Changed() end
end

-- Talents: all points coming back at once is a re-spec.
local RESPEC_LINES = { "A fresh start.", "Second thoughts.", "Third time's the charm.", "The trainer knows you by name now.",
    "At this point it's a hobby." }
local freePoints, lastLevelUp = nil, 0
local function Talents()
    local ok, now = pcall(UnitCharacterPoints, "player")
    now = ok and tonumber(now) or nil
    if not now then return end
    if freePoints and now >= freePoints + 2 and GetTime() - lastLevelUp > 3 then
        H.respecs = (H.respecs or 0) + 1
        J.Log("respec", ("Re-specced %d talent points"):format(now - freePoints),
            { sub = RESPEC_LINES[math.min(H.respecs, #RESPEC_LINES)] })
        J.Changed()
    end
    freePoints = now
end

-- Quests: who gave it, where and when, and the first sentence of what it asked; joined to the hand-in record.
local turnInNPC
local offered = {}   -- the NPC who showed you a quest's text (QUEST_DETAIL): the giver, even if the window is gone by acceptance
local function Objective(questID)
    local text
    pcall(function()
        local index = C_QuestLog and C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
        if not index then return end
        if SelectQuestLogEntry then SelectQuestLogEntry(index) end
        local _, objectives = GetQuestLogQuestText(index)
        text = Plain(objectives)
    end)
    if text then text = text:match("^(.-[%.!?])%s") or text end
    return text
end
local function Accepted(a1, a2)
    local id = tonumber(a2) or tonumber(a1)
    if not id then return end
    H.questStart = H.questStart or {}
    local mapID, x, y = J.Position()
    local giver = NPC() or (offered.t and GetTime() - offered.t < 120 and offered.name) or nil
    H.questStart[id] = { t = time(), giver = giver, zone = J.Zone(), subzone = J.SubZone(), x = x, y = y, level = J.Level() }
    -- the log entry may not be filled in yet
    C_Timer.After(0.5, function() local s = H.questStart[id]; if s and not s.objective then s.objective = Objective(id) end end)
end
local function TurnedIn(id)
    id = tonumber(id)
    if not id then return end
    local q = H.quests[#H.quests]
    if not q or q.questID ~= id then return end
    local s = H.questStart and H.questStart[id]
    if s then
        q.started, q.giver, q.fromZone, q.fromSub, q.objective = s.t, s.giver, s.zone, s.subzone, s.objective
        H.questStart[id] = nil
    end
    q.taker = turnInNPC
    -- who did it with you: anyone in your group, on the same quest, while one of its objectives moved forward
    -- (H.questWith), and anyone on it with you as you hand it in
    local with = {}
    for name in pairs(s and s.with or {}) do with[name] = true end
    for name in pairs(H.questWith and H.questWith[id] or {}) do with[name] = true end
    for _, name in ipairs(J.QuestPartners and J.QuestPartners(id) or {}) do with[name] = true end
    if H.questWith then H.questWith[id] = nil end
    if next(with) then q.with = with end
end

-- The quests in your log right now, with what the journal saw when you took them (start: nil if taken before).
function J.OpenQuests()
    local out = {}
    pcall(function()
        local n = C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries() or GetNumQuestLogEntries()
        for i = 1, n or 0 do
            local title, level, isHeader, id
            if C_QuestLog and C_QuestLog.GetInfo then
                local info = C_QuestLog.GetInfo(i)
                if info then title, level, isHeader, id = info.title, info.level, info.isHeader, info.questID end
            else
                local t, l, _, h, _, _, _, qid = GetQuestLogTitle(i)
                title, level, isHeader, id = t, l, h, qid
            end
            title = Plain(title)
            if title and not isHeader and id then
                local have, need = 0, 0
                local objs = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id) or {}
                for _, o in ipairs(objs) do have, need = have + (o.numFulfilled or 0), need + (o.numRequired or 0) end
                local ready = C_QuestLog.IsComplete and C_QuestLog.IsComplete(id) or false
                local start = H.questStart and H.questStart[id]
                if start and not start.objective then start.objective = Objective(id) end
                out[#out + 1] = { questID = id, title = title, level = level, have = have, need = need, ready = ready and true or false,
                    start = start, objective = start and start.objective or Objective(id) }
            end
        end
    end)
    return out
end

-- Objective progress: when a quest's count goes up while you are grouped, everyone in the group who is on
-- that quest too did it with you.
local progress = {}
local function WatchProgress()
    local seen = {}
    for _, q in ipairs(J.OpenQuests()) do
        seen[q.questID] = true
        local before = progress[q.questID]
        local now = q.ready and math.max(q.have, q.need) + 1 or q.have
        if before and now > before then
            local partners = J.QuestPartners and J.QuestPartners(q.questID) or {}
            if #partners > 0 then
                H.questWith = H.questWith or {}
                H.questWith[q.questID] = H.questWith[q.questID] or {}
                for _, n in ipairs(partners) do H.questWith[q.questID][n] = true end
            end
        end
        progress[q.questID] = now
    end
    for id in pairs(progress) do if not seen[id] then progress[id] = nil end end
end
J.WatchProgress = WatchProgress

local f = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "LEARNED_SPELL_IN_TAB", "LEARNED_SPELL_IN_SKILL_LINE", "CHAT_MSG_SYSTEM", "SKILL_LINES_CHANGED",
    "CHAT_MSG_SKILL", "CHAT_MSG_COMBAT_FACTION_CHANGE", "PLAYER_ENTERING_WORLD", "ENCOUNTER_START", "ENCOUNTER_END", "INSTANCE_ENCOUNTER_ENGAGE_UNIT", "CHAT_MSG_LOOT", "NEW_MOUNT_ADDED", "NEW_PET_ADDED",
    "CHARACTER_POINTS_CHANGED", "PLAYER_TALENT_UPDATE", "PLAYER_LEVEL_UP", "QUEST_ACCEPTED", "QUEST_COMPLETE", "QUEST_DETAIL", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED", "QUEST_TURNED_IN" }) do
    pcall(f.RegisterEvent, f, e)   -- not every client has every event
end
local LEARN = { Pattern(ERR_LEARN_SPELL_S), Pattern(ERR_LEARN_ABILITY_S) }
local RECIPE = Pattern(ERR_LEARN_RECIPE_S)
f:SetScript("OnEvent", function(_, event, a1, a2, a3, a4, a5)
    -- /bl events (debug mode): print what the client sends, to see which of these it supports
    if DB.debug and DB.logEvents and (event ~= "CHAT_MSG_SYSTEM" or Plain(a1)) and event ~= "QUEST_LOG_UPDATE" and event ~= "UNIT_QUEST_LOG_CHANGED" then
        print(("|cff8888ffFJ event|r %s %s %s"):format(event, tostring(Plain(a1) or a1), tostring(Plain(a2) or a2)))
    end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(10, function()
            ready = true
            pcall(DungeonIcon)   -- a reload inside a dungeon
            skills = J.Skills()
            local ok, p = pcall(UnitCharacterPoints, "player"); freePoints = ok and tonumber(p) or nil
        end)
        return
    end
    -- quest bookkeeping runs from the start; everything else waits until the login replay is over
    if event == "QUEST_LOG_UPDATE" or (event == "UNIT_QUEST_LOG_CHANGED" and a1 == "player") then return pcall(WatchProgress)
    elseif event == "QUEST_ACCEPTED" then return Accepted(a1, a2)
    elseif event == "QUEST_COMPLETE" then turnInNPC = NPC(); return
    elseif event == "QUEST_DETAIL" then offered.name, offered.t = NPC(), GetTime(); return
    elseif event == "QUEST_TURNED_IN" then return C_Timer.After(0, function() TurnedIn(a1) end)
    elseif event == "PLAYER_LEVEL_UP" then lastLevelUp = GetTime(); return end
    if not ready then return end
    if event == "LEARNED_SPELL_IN_TAB" or event == "LEARNED_SPELL_IN_SKILL_LINE" then
        LearnSpell(SpellInfo(a1))
    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = Plain(a1)
        if not msg then return end
        local recipe = RECIPE and msg:match(RECIPE)
        if recipe then return LearnRecipe(recipe:gsub("|c[^|]+|H.-|h%[?(.-)%]?|h|r", "%1")) end
        for _, p in ipairs(LEARN) do
            local name = p and msg:match(p)
            if name then return LearnSpell(name:gsub("|c[^|]+|H.-|h%[?(.-)%]?|h|r", "%1"), nil, nil) end
        end
        Reputation(msg)
    elseif event == "CHAT_MSG_COMBAT_FACTION_CHANGE" then
        if Plain(a1) then Reputation(a1) end
    elseif event == "SKILL_LINES_CHANGED" or event == "CHAT_MSG_SKILL" then
        CheckSkills()
    elseif event == "PLAYER_ENTERING_WORLD" then
        pcall(DungeonIcon)
    elseif event == "ENCOUNTER_START" or event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
        if event == "ENCOUNTER_START" then
            wipe(seenBosses); encounterName = Plain(a2)
            local ok, id = pcall(ModelAtStart); fightModel = ok and id or nil
        end
        pcall(ReadBosses, encounterName)
    elseif event == "ENCOUNTER_END" then
        pcall(ReadBosses, Plain(a2))
        local okm, model = pcall(ModelAtEnd)
        lastModel = okm and model or nil
        if DB.debug then
            print(("BlatoLexicon boss model: %s (start %s)"):format(tostring(lastModel), tostring(fightModel)))
            local w = seenBosses[Plain(a2) or ""]
            print(("BlatoLexicon boss: %s, start seen: %s, type %s, family %s, icon %s"):format(tostring(Plain(a2)), tostring(encounterName),
                tostring(w and w.type), tostring(w and w.family), tostring(w and w.icon)))
        end
        Boss(a2, a5, a1)
    elseif event == "CHAT_MSG_LOOT" then
        Loot(a1)
    elseif event == "NEW_MOUNT_ADDED" then Mount(a1)
    elseif event == "NEW_PET_ADDED" then Pet(a1)
    elseif event == "CHARACTER_POINTS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        Talents()
    end
end)
J.ChronicleTest = { Loot = Loot, Boss = Boss, Reputation = Reputation, LearnSpell = LearnSpell, LearnRecipe = LearnRecipe }
