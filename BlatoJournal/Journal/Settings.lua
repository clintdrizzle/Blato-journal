-- BlatoJournal settings page, key bindings and slash commands.
local _, ns = ...
local J, UI, Kit = ns.J, ns.UI, ns.Kit
local DB, H = J.DB, J.H

BINDING_HEADER_BLATOJOURNAL = "Bláto Journal"
BINDING_NAME_BLATOJOURNAL_TOGGLE = "Open or close the journal"
BINDING_NAME_BLATOJOURNAL_NOTE = "Take a quick note"
function BlatoJournal_Toggle() UI.Toggle() end
function BlatoJournal_Note() UI.NoteDialog() end

local function Get(k) return function() return DB[k] end end
local function Set(k) return function(v) DB[k] = v; UI.PlaceToast(); UI.PlaceTracker(); UI.ApplyStyle(); UI.UpdateMinimapButton() end end
local function Seconds(v) return Kit.FormatNumber(v, 0.5) .. "s" end
local function Percent(v) return ("%d%%"):format(v * 100 + 0.5) end

local page = Kit.NewPage("Bláto Journal")
page:Text("A journal of your character's journey: where each level was spent, the places you found, the dungeons you cleared together and the notes you took. "
    .. "No rates, no countdowns.", "GameFontHighlightSmall")
page:Button("Journal", "Open journal", function() UI.Show() end)

page:Section("Journal")
page:Check("Minimap button", Get("minimap"), Set("minimap"), "Left-click opens the journal, right-click writes a quick note. Drag it around the minimap's edge.")
local styles = {}
for _, s in ipairs(UI.STYLES) do styles[#styles + 1] = { s.key, s.label } end
page:Dropdown("Page style", styles, Get("style"), Set("style"))
page:Check("Pin new notes to the Journey", Get("autoPin"), Set("autoPin"),
    "New notes also show on the Journey page, under the level you wrote them. The quick note slip has its own tick box for each note.")
page:Text(function()
    local used = UI.usedStyle or "dark"
    for _, s in ipairs(UI.STYLES) do if s.key == used then return "In use: " .. s.label .. "." end end
    return ""
end, "GameFontDisableSmall")

page:Section("Journal detail")
page:Text("Everything is always written down; this only chooses what the pages show. Change it any time, and the journal "
    .. "shows its whole history the new way.", "GameFontDisableSmall")
local function Render() if UI.Render then UI.Render() end end
local presets = {}
for _, p in ipairs(J.DETAIL_ORDER) do presets[#presets + 1] = p end
presets[#presets + 1] = { "custom", "Custom" }
page:Dropdown("How much to show", presets, Get("detail"), function(v)
    if v == "custom" and DB.detail ~= "custom" then J.SetShows("keepsakes", J.Shows("keepsakes")) else DB.detail = v end
    page:Refresh(); Render()
end, "Essentials: only the big moments. Storyteller: the whole story (the default). Chronicler: everything, for the data lovers.")
page:Text(function()
    return ({ essentials = "Essentials: levels, deaths, notes and keepsakes. Clean and short.",
        story = "Storyteller: adds spells, recipes, professions, reputation, re-specs and new places.",
        chronicler = "Chronicler: everything, rare (blue) finds too.",
        custom = "Custom: your own mix, below." })[DB.detail] or ""
end, "GameFontHighlightSmall")
local function Show(key, label, tip)
    page:Check(label, function() return J.Shows(key) end, function(v) J.SetShows(key, v and true or false); page:Refresh(); Render() end, tip)
end
Show("keepsakes", "Big moments as keepsakes", "First boss kills, epic finds and Honored and up get their ribbon, tag or seal. Off: they are plain rows.")
Show("spells", "Spells and ranks")
Show("recipes", "Recipes")
Show("professions", "Professions and skill caps")
Show("respecs", "Talent re-specs")
Show("bosses", "Boss kills", "One row per boss; later kills are counted on it.")
Show("mounts", "Mounts and pets")
Show("deaths", "Deaths")
Show("zones", "New places and dungeons", "The first time you enter a zone or a dungeon.")
page:Dropdown("Finds from", { { 2, "Uncommon (green)" }, { 3, "Rare (blue)" }, { 4, "Epic (purple)" }, { 5, "Legendary (orange)" } },
    function() return J.Shows("lootMin") end, function(v) J.SetShows("lootMin", v); page:Refresh(); Render() end,
    "The lowest quality of your own loot shown on the Journey page. Every find from uncommon up is kept either way.")
page:Dropdown("Reputation from", { { "all", "Every new standing" }, { "honored", "Honored and up" } },
    function() return J.Shows("repMin") end, function(v) J.SetShows("repMin", v); page:Refresh(); Render() end)

page:Section("Pages")
page:Check("Fold older chapters", Get("foldChapters"), function(v) DB.foldChapters = v; Render() end,
    "On the Journey page, chapters older than the last two start folded. Off: every chapter starts open.")
page:Check("Rewards on the Quests page", Get("questRewards"), function(v) DB.questRewards = v; Render() end,
    "Experience and money for each quest, in a column on the right.")
page:Slider("Fleeting company under", 1, 60, 1, Get("fleetingMinutes"), function(v) DB.fleetingMinutes = v; Render() end,
    function(v) return ("%d min"):format(v) end,
    "In Fellowship, people you grouped with for less than this are folded away under Fleeting company.")

page:Section("Archive")
page:Text("Archived notes and quests are hidden from their page but kept until you delete them. Open them from the Archive link at the top of each page.", "GameFontDisableSmall")
page:Check("Archive finished reminders", Get("archiveReminders"), Set("archiveReminders"),
    "A reminder that has fired (or that you mark done) moves to the archive instead of staying among your notes.")

page:Section("Moments")
page:Text("Short lines at the top of the screen for things worth remembering. They fade out on their own.", "GameFontDisableSmall")
page:Check("Show moments", Get("moments"), Set("moments"))
page:Check("New places", Get("momentZone"), Set("momentZone"), "The first time you enter a zone.")
page:Check("Level reached", Get("momentLevel"), Set("momentLevel"), "How long the last level took, and where you spent it.")
page:Check("First dungeon visits", Get("momentDungeon"), Set("momentDungeon"))
page:Check("Well rested", Get("momentRested"), Set("momentRested"), "When you log in with a good amount of rested XP from your break.")
page:Slider("Stay on screen", 2, 12, 0.5, Get("momentSeconds"), Set("momentSeconds"), Seconds)
page:Slider("Size", 0.8, 2, 0.05, Get("toastScale"), Set("toastScale"), Percent)
page:Slider("Reminders stay on screen", 3, 20, 1, Get("reminderSeconds"), Set("reminderSeconds"), Seconds,
    "Reminders from your notes show even when other moments are turned off.")

page:Section("Sounds")
page:Check("Play sounds", Get("sounds"), Set("sounds"), "Sounds play even when the moment's text is turned off.")
page:Check("Play when game effects are muted", Get("soundMaster"), Set("soundMaster"),
    "Use the master volume channel, so journal sounds are heard with sound effects turned off.")
for _, ev in ipairs({
    { "zone", "New place" }, { "dungeon", "First dungeon visit" },
    { "level", "Level summary" }, { "rested", "Well rested" }, { "note", "Note saved" }, { "reminder", "Reminder" },
}) do
    page:Dropdown(ev[2], UI.SoundOptions, function() return DB.sound[ev[1]] end, function(v)
        DB.sound[ev[1]] = v
        UI.PlaySound(v, true)   -- let you hear what you picked
    end)
end

page:Section("Journal tracker")
page:Text("A short list under the objective tracker. Right-click it to open the journal. With ForeverImmersion, choose when it "
    .. "shows on the Elements page.", "GameFontDisableSmall")
page:Check("Show pending reminders", Get("trackerReminders"), Set("trackerReminders"),
    "Reminders still waiting for their trigger, with the trigger underneath.")
page:Slider("Reminders shown", 1, 10, 1, Get("trackerReminderMax"), Set("trackerReminderMax"))

page:Section("Positions")
page:Check("Lock positions", Get("locked"), Set("locked"),
    "Unlock to drag the moments line and the journal tracker. You can also move them in Blizzard's Edit Mode, per layout.")

page:Section("Keys")
page:Text(function()
    local function Key(b) local k = GetBindingKey and GetBindingKey(b); return k and ("|cffffd100" .. (GetBindingText and GetBindingText(k) or k) .. "|r") or "|cff808080not bound|r" end
    return ("Open journal: %s.   Quick note: %s.\nBind them in Options > Keybindings > AddOns. The minimap button does both, and |cffffd100/bj|r and |cffffd100/note|r work too.")
        :format(Key("BLATOJOURNAL_TOGGLE"), Key("BLATOJOURNAL_NOTE"))
end, "GameFontHighlightSmall")

page:SaveStatus()
page:Section("Other")
StaticPopupDialogs.BLATOJOURNAL_CLEAR = {
    text = "Clear this character's whole journal? Levels, places, quests and notes are all forgotten.",
    button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function()
        wipe(H)
        J.Defaults()
        J.Changed()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}
page:Button("Clear journal", "Clear", function() StaticPopup_Show("BLATOJOURNAL_CLEAR") end, "Start this character's journal from a blank page.")
Kit.Register(page)

function BlatoJournal_OpenSettings() Kit.Open(page) end

-- Place things once saved positions are known.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
    UI.ApplyStyle()
    UI.PlaceToast()
    UI.UpdateMinimapButton()
    UI.RegisterEditMode()
    C_Timer.After(1, UI.PlaceTracker)   -- the objective tracker settles its size a moment after login
end)

SLASH_BLATOJOURNAL1 = "/bj"
SLASH_BLATOJOURNAL2 = "/journal"
SlashCmdList.BLATOJOURNAL = function(msg)
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    -- Developer commands (design checks, API probes) only answer in debug mode: /bj debug turns it on or off.
    local DEV = { icons = true, art = true, name = true, tour = true, blank = true, corners = true, events = true, target = true, boss = true }
    if cmd == "debug" then
        J.DB.debug = not J.DB.debug or nil
        print("BlatoJournal: debug mode " .. (J.DB.debug and "on. Extra commands: art, icons, name, tour, blank, corners, events." or "off."))
        return
    end
    if DEV[cmd] and not J.DB.debug then cmd = "" end
    if cmd == "note" then
        if rest ~= "" then if J.AddNote(rest) then J.Moment("|cffb0b0b0Noted.|r", "note") end else UI.NoteDialog() end
    elseif cmd == "settings" or cmd == "config" then Kit.Open(page)
    elseif cmd == "icons" then
        -- which art each journal icon resolved to on this client
        local tex = UIParent:CreateTexture()
        for key in pairs(UI.ICONSET) do
            local used, atlas = UI.PaintIcon(tex, key)
            print(("%s: %s%s"):format(key, tostring(used), atlas and " (atlas)" or ""))
        end
    elseif cmd == "art" then
        -- Design research: record every texture (atlas or file) used by the window under the mouse, into the
        -- saved settings (BJ_DB._art), so it can be read from the SavedVariables file after a /reload.
        local f = GetMouseFoci and GetMouseFoci()[1] or GetMouseFocus and GetMouseFocus()
        while f and f:GetParent() and f:GetParent() ~= UIParent do f = f:GetParent() end
        local root = f and f.GetName and f:GetName()
        if type(root) ~= "string" then print("BlatoJournal: hover a window first, then type /bj art") return end
        local seen, out = {}, {}
        local function PK(o) local k = o.GetParentKey and o:GetParentKey(); return type(k) == "string" and k or nil end
        local function Walk(frame, path, depth)
            if depth > 12 then return end
            for _, r in ipairs({ frame:GetRegions() }) do
                if r.GetObjectType and r:GetObjectType() == "Texture" then
                    local atlas = r.GetAtlas and r:GetAtlas()
                    local file = r.GetTexture and r:GetTexture()
                    local key = atlas and ("atlas " .. atlas) or file and ("file " .. tostring(file))
                    if key and not seen[key] then
                        seen[key] = true
                        local w, h = r:GetSize()
                        out[#out + 1] = ("%s  %dx%d  %s%s"):format(key, w or 0, h or 0, path, PK(r) and ("." .. PK(r)) or "")
                    end
                end
            end
            for _, c in ipairs({ frame:GetChildren() }) do
                Walk(c, path .. "/" .. (PK(c) or (c.GetName and type(c:GetName()) == "string" and c:GetName()) or c:GetObjectType()), depth + 1)
            end
        end
        Walk(f, root, 0)
        DB._art = DB._art or {}
        DB._art[root] = out
        print(("BlatoJournal: recorded %d textures from %s. Do this for each window, then /reload."):format(#out, root))
    elseif cmd == "name" then
        -- which call gives the full (first + last) name on this client
        local function show(label, f, ...)
            local ok, a, b = pcall(f, ...)
            if not ok then return end
            if issecretvalue and (issecretvalue(a) or issecretvalue(b)) then print(label, "<secret>") return end
            print(label, tostring(a), b ~= nil and tostring(b) or "")
        end
        print("|cffffd100BlatoJournal names:|r")
        show("UnitName:", UnitName, "player")
        if UnitFullName then show("UnitFullName:", UnitFullName, "player") end
        if GetUnitName then show("GetUnitName:", GetUnitName, "player", true) end
        if UnitPVPName then show("UnitPVPName:", UnitPVPName, "player") end
        if C_TooltipInfo and C_TooltipInfo.GetUnit then
            show("Tooltip line 1:", function() return C_TooltipInfo.GetUnit("player").lines[1].leftText end)
        end
        for _, api in ipairs({ "C_PlayerInfo", "C_CharacterNames", "C_Character" }) do
            for k, f in pairs(_G[api] or {}) do
                if type(f) == "function" and k:lower():find("name") then print(api .. "." .. k) end
            end
        end
    elseif cmd == "why" then UI.Why()
    elseif cmd == "commands" or cmd == "dungeons" or cmd == "journey" or cmd == "places" or cmd == "notes" or cmd == "quests" then UI.Show(cmd)
    elseif cmd == "place" and rest ~= "" then UI.OpenPlace(rest)
    elseif cmd == "tour" then
        -- Design check: shows every page for a few seconds, in modern dark then modern parchment, then puts the
        -- style back. Each step prints its name, so screenshots can be matched to pages.
        local J2 = J
        local zone
        for z, r in pairs(J2.H.zones) do if not zone or r.time > J2.H.zones[zone].time then zone = z end end
        local dungeon
        for name, d in pairs(J2.H.dungeons or {}) do if not dungeon or (d.time or 0) > (J2.H.dungeons[dungeon].time or 0) then dungeon = name end end
        local pages = { "commands", "dungeons", "journey", "places", "place", "dungeon", "quests", "questsopen", "notes" }
        local steps, keep = {}, DB.style
        for _, style in ipairs({ "classic", "moderndark", "modernparchment" }) do
            for _, pg in ipairs(pages) do steps[#steps + 1] = { style, pg } end
        end
        local i = 0
        local function Step()
            i = i + 1
            local st = steps[i]
            if not st then DB.style = keep; J.DB.questView = "done"; UI.ApplyStyle(); print("BlatoJournal tour: done"); return end
            if DB.style ~= st[1] then DB.style = st[1]; UI.ApplyStyle() end
            J.DB.questView = st[2] == "questsopen" and "open" or "done"
            if st[2] == "place" then UI.OpenPlace(zone or "")
            elseif st[2] == "dungeon" then UI.OpenPlace(dungeon and ("dungeon:" .. dungeon) or "")
            elseif st[2] == "questsopen" then UI.Show("quests")
            else UI.Show(st[2]) end
            print(("BlatoJournal tour %d: %s %s"):format(i, st[1], st[2]))
            C_Timer.After(4, Step)
        end
        Step()
    elseif cmd == "corners" then
        -- Dev probe: what does this client know about a zone's subzones? Prints to chat.
        local mapID = C_Map.GetBestMapForUnit("player")
        local info = mapID and C_Map.GetMapInfo(mapID)
        local zone = info and info.name or GetZoneText()
        print(("BlatoJournal corners: map %s (%s)"):format(tostring(mapID), tostring(zone)))
        -- 1) exploration achievement ("Explore <zone>") criteria
        local found
        if GetCategoryList and GetCategoryNumAchievements and GetAchievementInfo then
            for _, cat in ipairs(GetCategoryList() or {}) do
                for i = 1, (GetCategoryNumAchievements(cat, true) or 0) do
                    local id, name = GetAchievementInfo(cat, i)
                    if name and name == ("Explore " .. zone) then found = id end
                end
            end
        end
        if found then
            local n = GetAchievementNumCriteria(found)
            local done, names = 0, {}
            for c = 1, n do
                local cname, _, completed = GetAchievementCriteriaInfo(found, c)
                if completed then done = done + 1 end
                if c <= 6 then names[#names + 1] = cname .. (completed and "+" or "-") end
            end
            print(("  achievement %d: %d/%d  %s"):format(found, done, n, table.concat(names, ", ")))
        else
            print("  achievement: none found (API " .. tostring(GetCategoryList ~= nil) .. ")")
        end
        -- 2) explored overlay textures
        if C_MapExplorationInfo and C_MapExplorationInfo.GetExploredMapTextures and mapID then
            local t = C_MapExplorationInfo.GetExploredMapTextures(mapID)
            print("  explored textures: " .. tostring(t and #t))
        else
            print("  explored textures: API missing")
        end
        -- 3) area IDs at the player's position
        if C_MapExplorationInfo and C_MapExplorationInfo.GetExploredAreaIDsAtPosition and mapID then
            local pos = C_Map.GetPlayerMapPosition(mapID, "player")
            local ids = pos and C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, pos)
            local names = {}
            for _, id in ipairs(ids or {}) do names[#names + 1] = (C_Map.GetAreaInfo(id) or "?") .. "#" .. id end
            print("  areas here: " .. (#names > 0 and table.concat(names, ", ") or "none"))
        end
    elseif cmd == "events" then
        J.DB.logEvents = not J.DB.logEvents or nil
        print("BlatoJournal: event log " .. (J.DB.logEvents and "on" or "off"))
    elseif cmd == "boss" then
        -- Dev probe: find a boss by name in the Adventure Guide's data, browsing every tier, dungeon and raid
        local want = rest ~= "" and rest:lower() or "rath'mael"
        print(("BlatoJournal boss search: %s"):format(want))
        if not (EJ_GetNumTiers and EJ_SelectTier and EJ_GetInstanceByIndex and EJ_GetEncounterInfoByIndex) then
            print("  the Adventure Guide API is missing"); return
        end
        local found, dungeons, bosses = 0, 0, 0
        for tier = 1, EJ_GetNumTiers() do
            pcall(EJ_SelectTier, tier)
            for _, raid in ipairs({ false, true }) do
                for i = 1, 200 do
                    local ok, inst, iname = pcall(EJ_GetInstanceByIndex, i, raid)
                    if not ok or not inst then break end
                    dungeons = dungeons + 1
                    if iname and iname:lower():find(want, 1, true) then print(("  dungeon: %s (#%d, tier %d)"):format(iname, inst, tier)) end
                    for j = 1, 40 do
                        local ok2, ename, _, jEnc, _, _, _, dEnc = pcall(EJ_GetEncounterInfoByIndex, j, inst)
                        if not ok2 or not ename then break end
                        bosses = bosses + 1
                        if ename:lower():find(want, 1, true) then
                            local _, _, _, _, image = EJ_GetCreatureInfo(1, jEnc)
                            print(("  boss: %s in %s  journal #%d  encounter #%s  portrait %s"):format(ename, iname or "?", jEnc, tostring(dEnc), tostring(image)))
                            found = found + 1
                        end
                    end
                end
            end
        end
        print(("  searched %d dungeons and raids, %d bosses: %d found"):format(dungeons, bosses, found))
    elseif cmd == "target" then
        -- Dev probe: what the game tells an addon about your target (plain or secret)
        local function show(label, ok, v)
            local txt = not ok and ("error: " .. tostring(v)) or (issecretvalue and issecretvalue(v)) and "|cffff6060secret|r" or tostring(v)
            print(("  %s: %s"):format(label, txt))
        end
        print("BlatoJournal target:")
        show("name", pcall(UnitName, "target"))
        show("type", pcall(UnitCreatureType, "target"))
        show("family", pcall(UnitCreatureFamily, "target"))
        show("classification", pcall(UnitClassification, "target"))
        show("dead", pcall(UnitIsDead, "target"))
        show("boss1 exists", pcall(UnitExists, "boss1"))
        show("model (display ID)", pcall(J.DisplayOf, "target"))
        -- a model can take a moment to load: read again shortly, on a visible model frame, in every way it offers
        local m = J.ProbeModel or CreateFrame("PlayerModel", nil, UIParent)
        J.ProbeModel = m
        m:SetSize(64, 64); m:ClearAllPoints(); m:SetPoint("CENTER", UIParent, "CENTER", 0, 200); m:SetAlpha(1); m:Show()
        pcall(m.SetUnit, m, "target")
        C_Timer.After(0.6, function()
            show("  later, display ID", pcall(m.GetDisplayInfo, m))
            show("  later, model file", pcall(m.GetModelFileID, m))
            show("  creature ID from GUID", pcall(function()
                local g = UnitGUID("target"); if issecretvalue and issecretvalue(g) then return g end
                return g and select(6, strsplit("-", g))
            end))
            m:Hide()
        end)
        local ok, inside, kind = pcall(IsInInstance)
        print(("  in instance: %s %s"):format(tostring(inside), tostring(kind)))
    elseif cmd == "blank" then
        -- Design check: the empty window (no page content) in each style, for mockup backgrounds.
        local keep = DB.style
        UI.Show("notes"); UI.content:Hide()
        local function Style(st, n, nxt)
            DB.style = st; UI.ApplyStyle(); UI.content:Hide()
            print("BlatoJournal blank " .. n .. ": " .. st)
            C_Timer.After(5, nxt)
        end
        Style("moderndark", 1, function() Style("modernparchment", 2, function()
            DB.style = keep; UI.ApplyStyle(); UI.content:Show(); print("BlatoJournal blank: done") end) end)
    else UI.Toggle() end
end
SLASH_BLATOJOURNALNOTE1 = "/note"
SlashCmdList.BLATOJOURNALNOTE = function(msg)
    if msg:match("%S") then if J.AddNote(msg) then J.Moment("|cffb0b0b0Noted.|r", "note") end else UI.NoteDialog() end
end
