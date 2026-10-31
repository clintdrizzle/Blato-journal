-- BlatoJournal reminders: a note can carry a trigger ("when I enter Undercity", "at a vendor") and shows up
-- as a moment when it happens. Triggers are suggested from the note's text; the writer confirms or changes them.
local _, ns = ...
local J = ns.J
local DB, H = J.DB, J.H

-- Trigger kinds. state: true while the condition holds (fires when it becomes true);
-- event: fires when that game event happens.
local CAPITALS = {
    ["Orgrimmar"] = true, ["Undercity"] = true, ["Thunder Bluff"] = true, ["Silvermoon City"] = true,
    ["Stormwind City"] = true, ["Ironforge"] = true, ["Darnassus"] = true, ["The Exodar"] = true,
    ["Shattrath City"] = true, ["Dalaran"] = true,
}
local function InCity()
    local z, sub = J.Zone(), J.SubZone()
    return (z and CAPITALS[z]) or (sub and CAPITALS[sub]) or false
end
local function InDungeon()
    local inside, kind = IsInInstance()
    return inside and (kind == "party" or kind == "raid")
end
local function Here(name)
    name = name:lower()
    for _, place in ipairs({ J.Zone(), J.SubZone(), GetZoneText and GetZoneText(), GetMinimapZoneText and GetMinimapZoneText() }) do
        if type(place) == "string" and place:lower() == name then return true end
    end
    return false
end

J.TRIGGERS = {
    place = { state = function(t) return Here(t.target) end, label = function(t) return "When you enter " .. t.target end },
    city = { state = InCity, label = function() return "In any capital city" end },
    inn = { state = function() return IsResting() and not InCity() end, label = function() return "At an inn" end },
    rested = { state = function() return IsResting() end, label = function() return "In a rested area (inn or city)" end },
    dungeon = {
        state = function(t)
            if not InDungeon() then return false end
            return not t.target or (GetInstanceInfo() or ""):lower() == t.target:lower()
        end,
        label = function(t) return t.target and ("When you enter " .. t.target) or "In any dungeon" end,
    },
    merchant = { event = "MERCHANT_SHOW", label = function() return "At a vendor" end },
    mail = { event = "MAIL_SHOW", label = function() return "At a mailbox" end },
    bank = { event = "BANKFRAME_OPENED", label = function() return "At the bank" end },
    auction = { event = "AUCTION_HOUSE_SHOW", label = function() return "At the auction house" end },
    flight = { event = "TAXIMAP_OPENED", label = function() return "At a flight master" end },
    trainer = { event = "TRAINER_SHOW", label = function() return "At a trainer" end },
    profession = { event = "TRADE_SKILL_SHOW", label = function() return "When you open a profession" end },
    level = { label = function(t) return ("When you reach level %d"):format(t.level or 0) end },
    login = { label = function() return "Next time you log in" end },
}
-- Order in the trigger menu.
J.TRIGGER_ORDER = { "city", "inn", "rested", "merchant", "mail", "bank", "auction", "flight", "trainer", "profession", "level", "dungeon", "login" }

function J.TriggerLabel(t)
    local def = t and J.TRIGGERS[t.kind]
    return def and def.label(t) or "No reminder"
end
function J.TriggerKey(t)
    if not t then return "none" end
    return t.kind .. ":" .. tostring(t.target or t.level or "")
end

-- Place names the journal can recognise in a note: every zone and dungeon on the map, plus the places you've been.
local placeCache
local function PlaceNames()
    if placeCache then return placeCache end
    local seen, list = {}, {}
    local function Add(name, kind)
        if type(name) ~= "string" or #name < 4 or seen[name:lower()] then return end
        seen[name:lower()] = true
        list[#list + 1] = { name = name, lower = name:lower(), kind = kind }
    end
    for name in pairs(H.dungeons) do Add(name, "dungeon") end
    for name in pairs(H.zones) do Add(name, "place") end
    for name in pairs(H.subzones or {}) do Add(name, "place") end
    for name in pairs(CAPITALS) do Add(name, "place") end
    local T = Enum and Enum.UIMapType
    if C_Map and C_Map.GetMapChildrenInfo and T then
        local ok, maps = pcall(C_Map.GetMapChildrenInfo, 946, nil, true)   -- 946: the whole world
        if ok and type(maps) == "table" then
            for _, m in ipairs(maps) do
                if m.mapType == T.Dungeon then Add(m.name, "dungeon")
                elseif m.mapType == T.Zone or m.mapType == T.Micro then Add(m.name, "place") end
            end
        end
    end
    -- longest first, so "Undercity" wins over a shorter name inside it
    table.sort(list, function(a, b) return #a.lower > #b.lower end)
    placeCache = list
    return list
end
function J.ForgetPlaceNames() placeCache = nil end

-- Words that point at a kind of place or moment, checked after place names. Where-words come before
-- what-words: "sell next time in a city" is about the city, not the vendor.
local KEYWORDS = {
    { "%f[%a]city%f[%A]", "city" }, { "capital", "city" },
    { "%f[%a]inn%f[%A]", "inn" },
    { "rested", "rested" }, { "resting", "rested" }, { "%f[%a]town%f[%A]", "rested" },
    { "dungeon", "dungeon" },
    { "auction", "auction" }, { "%f[%a]ah%f[%A]", "auction" },
    { "flight", "flight" }, { "taxi", "flight" },
    { "mailbox", "mail" }, { "%f[%a]mail%f[%A]", "mail" },
    { "%f[%a]bank%f[%A]", "bank" },
    { "trainer", "trainer" },
    { "vendor", "merchant" }, { "merchant", "merchant" }, { "%f[%a]sell%f[%A]", "merchant" }, { "repair", "merchant" },
    { "smelt", "profession" }, { "craft", "profession" }, { "%f[%a]cook", "profession" }, { "profession", "profession" },
    { "log ?in", "login" }, { "next time i play", "login" },
}

-- Suggests a trigger for a note's text, or nil. Item links count only by their name.
function J.SuggestTrigger(text)
    if type(text) ~= "string" or not text:find("%S") then return end
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):lower()
    for _, p in ipairs(PlaceNames()) do
        local esc = p.lower:gsub("%p", "%%%0")
        if plain:find("%f[%w]" .. esc .. "%f[%W]") then return { kind = p.kind, target = p.name } end
    end
    local lvl = plain:match("level (%d+)")
    if lvl then return { kind = "level", level = tonumber(lvl) } end
    for _, k in ipairs(KEYWORDS) do
        if plain:find(k[1]) then return { kind = k[2] } end
    end
end

-- Firing ---------------------------------------------------------------------------------------------
local inside = {}         -- note id -> was the state true at the last check
local sessionStart = time()
local ready = false       -- nothing fires before login has settled

-- "Smelt [Copper Ore]" -> "(23 in your bags)" for each item linked in the note.
local function ItemCounts(text)
    local out, seen = {}, {}
    for id in text:gmatch("|Hitem:(%d+)") do
        id = tonumber(id)
        if not seen[id] then
            seen[id] = true
            local n = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id) or 0
            local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or "items"
            out[#out + 1] = ("%d %s"):format(n or 0, name)
        end
    end
    return #out > 0 and ("  |cffb0b0b0(in your bags: " .. table.concat(out, ", ") .. ")|r") or ""
end

local function Fire(n)
    n.firedAt, n.fired = time(), (n.fired or 0) + 1
    if not n.repeats then n.done = true; if DB.archiveReminders then n.archived = time() end end
    J.Moment(("|cffffd100Reminder|r  |cffb0b0b0·|r  %s%s"):format(n.text, ItemCounts(n.text)), "reminder", DB.reminderSeconds)
    J.Changed()
end

-- event: the game event that prompted the check (nil for place and resting changes).
function J.CheckReminders(event, arg)
    if not ready then return end
    for _, n in ipairs(H.notes) do
        local t = n.trigger
        local def = t and not n.done and not n.archived and J.TRIGGERS[t.kind]
        if def then
            local fire = false
            if def.state then
                local now = def.state(t) and true or false
                if now and not inside[n.id] then fire = true end
                inside[n.id] = now
            elseif def.event then
                fire = def.event == event
            elseif t.kind == "level" then
                fire = event == "PLAYER_LEVEL_UP" and (tonumber(arg) or J.Level()) >= (t.level or 0)
            elseif t.kind == "login" then
                fire = event == "LOGIN" and (n.armedAt or n.t) < sessionStart
            end
            if fire then Fire(n) end
        end
    end
end

-- A new or re-armed reminder only fires on the next change: writing "when I get to Undercity" while standing in
-- Undercity waits until you come back.
function J.ArmReminder(n)
    local def = n.trigger and J.TRIGGERS[n.trigger.kind]
    inside[n.id] = def and def.state and (def.state(n.trigger) and true or false) or nil
    n.armedAt = time()
end

function J.SetReminder(n, trigger, repeats)
    n.trigger = trigger
    n.repeats = trigger and repeats or nil
    n.done, n.firedAt = nil, nil
    if trigger then J.ArmReminder(n) end
    J.Changed()
end

function J.ReminderDone(id)
    for _, n in ipairs(H.notes) do
        if n.id == id then n.done = true; if DB.archiveReminders then n.archived = time() end end
    end
    J.Changed()
end
function J.RemindAgain(id)
    for _, n in ipairs(H.notes) do
        if n.id == id and n.trigger then n.done, n.archived = nil, nil; J.ArmReminder(n) end
    end
    J.Changed()
end

local ev = CreateFrame("Frame")
local WATCH = { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_UPDATE_RESTING", "PLAYER_LEVEL_UP" }
for _, def in pairs(J.TRIGGERS) do if def.event then WATCH[#WATCH + 1] = def.event end end
for _, e in ipairs(WATCH) do pcall(ev.RegisterEvent, ev, e) end   -- an event this client lacks is simply skipped
ev:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_LOGIN" then
        -- after login settles: places you log in at count as "entering" them, then "next time you log in"
        C_Timer.After(3, function()
            ready = true
            J.CheckReminders(nil)
            J.CheckReminders("LOGIN")
        end)
        return
    end
    if event:find("^ZONE_CHANGED") then
        local sub, zone = J.SubZone(), J.Zone()
        if sub and zone and sub ~= zone then
            H.subzones = H.subzones or {}
            if not H.subzones[sub] then H.subzones[sub] = zone; placeCache = nil end
        end
    end
    J.CheckReminders(event, arg)
end)
