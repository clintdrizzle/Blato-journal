-- BlatoJournal UI: moments, the on-screen goal tracker, the journal window (Journey, Places, Goals, Notes)
-- and the quick-note box. Built from Blizzard templates so it reads like a native window.
local _, ns = ...
local J, Kit = ns.J, ns.Kit
local DB, H = J.DB, J.H
local UI = {}
ns.UI = UI

-- Dragging --------------------------------------------------------------------------------
-- Offsets are saved relative to an anchor point of the screen (CENTER, TOP, RIGHT...), so spots survive resolution changes.
local function Draggable(frame, xKey, yKey, anchor, canMove)
    anchor = anchor or "CENTER"
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if not DB.locked and (not canMove or canMove()) then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local scale = self:GetScale()
        local x, y = self:GetCenter()
        x, y = x * scale, y * scale
        local l, b, w, h = UIParent:GetRect()
        local ax = anchor:find("LEFT") and l or anchor:find("RIGHT") and (l + w) or (l + w / 2)
        local ay = anchor:find("TOP") and (b + h) or anchor:find("BOTTOM") and b or (b + h / 2)
        DB[xKey], DB[yKey] = x - ax, y - ay
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, anchor, DB[xKey] / scale, DB[yKey] / scale)
    end)
end

-- Moments -----------------------------------------------------------------------------------
local toast = CreateFrame("Frame", "BlatoJournalToast", UIParent)
toast:SetSize(460, 24)
toast:SetFrameStrata("HIGH")
toast:Hide()
toast.t = 0
toast.text = toast:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
toast.text:SetPoint("CENTER")
toast.text:SetShadowOffset(1, -1)
local FADE_IN, FADE_OUT = 0.4, 1.2
local ShowSample
toast:SetScript("OnUpdate", function(self, dt)
    if self.sample then self:SetAlpha(1); return end
    self.t = self.t + dt
    local hold = self.hold or DB.momentSeconds
    if self.t < FADE_IN then self:SetAlpha(self.t / FADE_IN)
    elseif self.t < FADE_IN + hold then self:SetAlpha(1)
    elseif self.t < FADE_IN + hold + FADE_OUT then self:SetAlpha(1 - (self.t - FADE_IN - hold) / FADE_OUT)
    else
        -- next queued moment, or rest
        local nextOne = table.remove(self.queue, 1)
        if nextOne then self.text:SetText(nextOne.text); self.hold = nextOne.hold; self.t = 0
        else self:Hide(); if not DB.locked then ShowSample() end end
    end
end)
toast.queue = {}

function ShowSample()
    toast.sample = true
    toast.text:SetText("|cffb0b0b0Journal moments show here. Drag to move, lock in settings.|r")
    toast:SetAlpha(1)
    toast:Show()
end

-- Sounds a moment can play; only the ones this client knows are offered.
local SOUNDS = {
    { "none", "None" },
    { "quest", "Quest complete", "IG_QUEST_LIST_COMPLETE" },
    { "page", "Page turn", "IG_QUEST_LOG_OPEN" },
    { "book", "Book opening", "IG_SPELLBOOK_OPEN" },
    { "chime", "Soft chime", "IG_PLAYER_INVITE" },
    { "ping", "Map ping", "MAP_PING" },
    { "coins", "Coins", "LOOT_WINDOW_COIN_SOUND" },
    { "loot", "Epic loot", "UI_EPICLOOT_TOAST" },
    { "ready", "Ready check", "READY_CHECK" },
    { "warning", "Raid warning", "RAID_WARNING" },
    { "whisper", "Whisper", "TELL_MESSAGE" },
    { "bell", "Bell", "ALARM_CLOCK_WARNING_3" },
}
function UI.SoundOptions()
    local out = {}
    for _, s in ipairs(SOUNDS) do
        if not s[3] or (SOUNDKIT and SOUNDKIT[s[3]]) then out[#out + 1] = { s[1], s[2] } end
    end
    return out
end
function UI.PlaySound(key, force)
    if not (DB.sounds or force) then return end
    -- a client without the bell gets the quest chime instead
    if key == "bell" and not (SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3) then key = "quest" end
    for _, s in ipairs(SOUNDS) do
        if s[1] == key and s[3] and SOUNDKIT and SOUNDKIT[s[3]] then
            PlaySound(SOUNDKIT[s[3]], DB.soundMaster and "Master" or "SFX")
        end
    end
end

-- Moments are rare, so they queue instead of replacing each other.
-- event: which sound setting applies; hold: seconds on screen (default: the Moments setting).
function J.Moment(text, event, hold)
    if event then UI.PlaySound(DB.sound[event]) end
    -- reminders show even with moments turned off: you asked for them
    if not DB.moments and event ~= "reminder" then return end
    if toast.sample then toast.sample = nil; toast:Hide() end
    if toast:IsShown() then table.insert(toast.queue, { text = text, hold = hold }); return end
    toast.text:SetText(text)
    toast.hold = hold
    toast.t = 0
    toast:Show()
end

function UI.PlaceToast()
    toast:SetScale(DB.toastScale)
    toast:ClearAllPoints()
    toast:SetPoint("CENTER", UIParent, "TOP", DB.toastX / DB.toastScale, DB.toastTop / DB.toastScale)
    toast:EnableMouse(not DB.locked)
    if not DB.locked then ShowSample()
    elseif toast.sample then toast.sample = nil; toast:Hide() end
end
Draggable(toast, "toastX", "toastTop", "TOP")

-- Journal tracker -------------------------------------------------------------------------------
-- Text only, in the objective tracker's style, so it sits in the UI like part of it.
-- Two sections: active goals, and reminders still waiting for their trigger.
local TRACKER_W = 230
local HEADER_FONT = _G.GameFontNormalMed2 and "GameFontNormalMed2" or "GameFontNormal"
local tracker = CreateFrame("Frame", "BlatoJournalTracker", UIParent)
tracker:SetSize(TRACKER_W, 20)
tracker.headers, tracker.lines = {}, {}
Draggable(tracker, "trackerX", "trackerY", "RIGHT")

local function ActiveGoals()
    local out = {}
    for _, g in ipairs(H.goals) do if not g.done and not g.archived then out[#out + 1] = g end end
    return out
end
local function PendingReminders()
    local out = {}
    for i = #H.notes, 1, -1 do
        local n = H.notes[i]
        if n.trigger and not n.done and not n.archived then out[#out + 1] = n end
    end
    return out
end

-- right-click opens the journal on the tab of the section under the mouse
tracker:SetScript("OnMouseUp", function(self, button)
    if button ~= "RightButton" then return end
    local tab = "notes"   -- Bláto Journal: no Goals page; reminders live with the notes
    local rh = self.reminderHeader
    if rh and rh:IsShown() then
        local _, cy = GetCursorPosition()
        if cy / self:GetEffectiveScale() <= (rh:GetTop() or 0) then tab = "notes" end
    end
    UI.Toggle(tab)
end)

function UI.UpdateTracker()
    local goals = DB.tracker and ActiveGoals() or {}
    local reminders = DB.trackerReminders and PendingReminders() or {}
    local anything = #goals > 0 or #reminders > 0
    local show = (DB.tracker or DB.trackerReminders) and (anything or not DB.locked or Kit.editMode)
    tracker:SetShown(show)
    if not show then return end
    tracker:EnableMouse(anything or not DB.locked)
    if Kit.editMode and not anything then tracker:SetWidth(TRACKER_W) end

    local h, l, y = 0, 0, 0
    local function Header(text)
        h = h + 1
        local fs = tracker.headers[h]
        if not fs then fs = tracker:CreateFontString(nil, "OVERLAY", HEADER_FONT); tracker.headers[h] = fs end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", 0, y)
        fs:SetText(text)
        fs:Show()
        y = y - fs:GetStringHeight() - 4
        return fs
    end
    local function Line(text, indent, dim)
        l = l + 1
        local fs = tracker.lines[l]
        if not fs then
            fs = tracker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)   -- one line each; long text ends in "..."
            tracker.lines[l] = fs
        end
        fs:SetWidth(TRACKER_W - indent)
        if dim then fs:SetTextColor(0.62, 0.62, 0.62) else fs:SetTextColor(1, 1, 1) end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", indent, y)
        fs:SetText(text)
        fs:Show()
        y = y - fs:GetStringHeight() - 2
    end

    tracker.reminderHeader = nil
    if #goals > 0 then
        Header("Goals")
        for i = 1, math.min(#goals, DB.trackerMax) do
            local g = goals[i]
            local have, need = J.GoalProgress(g)
            local count = (need > 1) and ("%d/%d  "):format(have, need) or ""
            Line(("- %s%s"):format(count, g.kind == "item" and g.name or g.label), 8)
        end
        y = y - 8
    end
    if #reminders > 0 then
        tracker.reminderHeader = Header("Reminders")
        for i = 1, math.min(#reminders, DB.trackerReminderMax) do
            local n = reminders[i]
            Line("- " .. n.text:gsub("[\r\n]+", " "), 8)
            Line(J.TriggerLabel(n.trigger) .. (n.repeats and ", every time" or ""), 18, true)
            y = y - 3
        end
    end
    if not anything then Header(Kit.editMode and "Journal tracker" or "|cff808080Journal tracker (drag to move)|r") end
    for i = h + 1, #tracker.headers do tracker.headers[i]:Hide() end
    for i = l + 1, #tracker.lines do tracker.lines[i]:Hide() end
    tracker:SetHeight(-y + 2)
end

-- Blizzard's Edit Mode: both frames get Edit Mode's overlay and can be dragged there, per layout.
local editRegistered = false
function UI.RegisterEditMode()
    if editRegistered then return end
    editRegistered = true
    Kit.EditMode({
        frame = tracker, label = "Journal tracker", key = "tracker", db = DB,
        get = function() return DB.trackerX, DB.trackerY end,
        set = function(x, y) DB.trackerX, DB.trackerY = x, y; UI.PlaceTracker() end,
        onToggle = function() UI.UpdateTracker() end,
    })
    Kit.EditMode({
        frame = toast, label = "Journal moments", key = "moments", db = DB,
        get = function() return DB.toastX, DB.toastTop end,
        set = function(x, y) DB.toastX, DB.toastTop = x, y; UI.PlaceToast() end,
        onToggle = function(active) if active then ShowSample() else UI.PlaceToast() end end,
    })
end

function UI.PlaceTracker()
    tracker:ClearAllPoints()
    tracker:SetPoint("CENTER", UIParent, "RIGHT", DB.trackerX, DB.trackerY)
    if DB.trackerX == -40 and DB.trackerY == -40 then
        -- first run: under the objective tracker if there is one, else on the right edge
        local ot = ObjectiveTrackerFrame
        if ot and ot:GetBottom() then
            tracker:ClearAllPoints()
            tracker:SetPoint("TOPLEFT", ot, "BOTTOMLEFT", 0, -12)
        else
            tracker:SetPoint("TOPRIGHT", UIParent, "RIGHT", -40, 120)
        end
    end
    UI.UpdateTracker()
end


-- Journal window -----------------------------------------------------------------------------
-- A Blizzard ButtonFrame: portrait, title, tabs underneath, action buttons in the bottom bar.
-- The page itself is parchment with dark ink; text stays inside the page's own margins.
local W, HGT = 620, 580
local win = CreateFrame("Frame", "BlatoJournalFrame", UIParent, "ButtonFrameTemplate")
win:SetSize(W, HGT)
win:SetPoint("CENTER")
win:SetToplevel(true)
win:SetMovable(true)
win:EnableMouse(true)
win:SetClampedToScreen(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", win.StopMovingOrSizing)
win:Hide()
tinsert(UISpecialFrames, "BlatoJournalFrame")
-- template children differ between client versions; only use the ones that are really there
local function Child(f, key) local c = f[key]; return type(c) == "table" and c or nil end
UI.Child = Child
if win.SetTitle then win:SetTitle("Bláto Journal") elseif Child(win, "TitleText") then win.TitleText:SetText("Bláto Journal") end
local ICON = "Interface/Icons/INV_Misc_Book_09"
UI.ICON = ICON
if win.SetPortraitToAsset then win:SetPortraitToAsset(ICON)
elseif Child(win, "portrait") and SetPortraitToTexture then SetPortraitToTexture(win.portrait, ICON)
elseif Child(win, "PortraitContainer") and Child(win.PortraitContainer, "portrait") and SetPortraitToTexture then
    SetPortraitToTexture(win.PortraitContainer.portrait, ICON)
end
-- no empty band under the title: the page starts right below it
if ButtonFrameTemplate_HideAttic then ButtonFrameTemplate_HideAttic(win) end
local inset = Child(win, "Inset") or win

-- Page art --------------------------------------------------------------------------------------
-- Modern styles use the art of the new windows on this client (group finder, professions, spellbook); see
-- .harness/forever-art.txt for where each atlas comes from. Modern dark is the default ("auto" tries them in order).
-- Bláto Journal: the look of WoW Forever's own windows is the default (Forever runs on the modern client).
-- Classic is an extra: a parchment page (Media/Parchment ships with the addon) in the old game's dialog frame
-- (UI.Chrome below).
local STYLES = {
    { key = "moderndark", label = "Forever", atlases = { "groupfinder-background" }, dark = true },
    { key = "modernparchment", label = "Forever parchment", atlases = { "spellbook-Page-Left-C60" } },
    { key = "classic", label = "Classic", files = { "Interface\\AddOns\\BlatoJournal\\Media\\Parchment" } },
}
UI.STYLES = STYLES
local function TryStyle(tex, s)
    tex:SetTexCoord(0, 1, 0, 1)
    for _, a in ipairs(s.atlases or {}) do
        if C_Texture.GetAtlasInfo(a) then tex:SetAtlas(a); return true end
    end
    for _, f in ipairs(s.files or {}) do
        if tex:SetTexture(f) then return true end
    end
end
local DARK_STYLE = {}
for _, s in ipairs(STYLES) do if s.dark then DARK_STYLE[s.key] = true end end
-- Paints the chosen page art onto a texture; returns the style used, or nil for the plain dark look.
local function PaintPage(tex)
    local style = STYLES[1]
    for _, s in ipairs(STYLES) do if s.key == DB.style then style = s end end
    if TryStyle(tex, style) then tex:Show(); return style.key end
    tex:Hide()   -- art missing on this client: the window's own dark inset
end

local page = inset:CreateTexture(nil, "BACKGROUND", nil, 7)   -- above the inset's own dark background
page:SetPoint("TOPLEFT", inset, "TOPLEFT", 2, -2)
page:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -2, 2)
local parchment   -- the paper style in use (dark ink), or nil on a dark page
local function Paper(used) return used and not DARK_STYLE[used] and used or nil end

-- Ink: dark brown on parchment; the usual gold and white on the dark inset.
local INK = {
    body = { 0.11, 0.07, 0.02 }, head = { 0.23, 0.10, 0.02 }, dim = { 0.29, 0.20, 0.09 },
    link = { 0.29, 0.09, 0.01 }, linkHover = { 0.55, 0.18, 0.02 }, bad = { 0.55, 0.05, 0.02 },
}
local DARK = {
    body = { 0.94, 0.89, 0.75 }, head = { 0.85, 0.71, 0.42 }, dim = { 0.70, 0.64, 0.51 }, faint = { 0.49, 0.43, 0.32 },
    link = { 0.91, 0.78, 0.44 }, linkHover = { 1, 0.94, 0.69 }, bad = { 0.85, 0.54, 0.42 },
}
INK.faint = { 0.35, 0.24, 0.12 }
local function Ink(role) return (parchment and INK or DARK)[role] or (parchment and INK or DARK).body end
-- Page fonts: a size up from the stock ones, because thin text disappears into busy parchment.
local FONTS = {}
local function PageFont(key, base, extra)
    local src = _G[base] or GameFontHighlight
    local f = CreateFont("BlatoJournalFont_" .. key)
    if src then
        f:SetFontObject(src)
        local path, size, flags = src:GetFont()
        if path and size then f:SetFont(path, size + extra, flags or "") end
    end
    FONTS[key] = f
end
-- whole-point sizes only: fractional sizes render soft
PageFont("title", "GameFontNormalHuge", 0)
PageFont("head", "GameFontNormalLarge", 0)
PageFont("body", "GameFontHighlight", 1)
PageFont("dim", "GameFontHighlight", 0)
PageFont("small", "GameFontHighlightSmall", 1)
-- Display faces for the journal look: Morpheus is the game's own storybook face (quest titles, mail).
local function DisplayFont(key, size, fallback)
    local f = CreateFont("BlatoJournalFont_" .. key)
    f:SetFontObject(_G[fallback] or GameFontNormalLarge)
    if not pcall(f.SetFont, f, "Fonts\\MORPHEUS.TTF", size, "") or not f:GetFont() then f:SetFontObject(_G[fallback] or GameFontNormalLarge) end
    FONTS[key] = f
end
DisplayFont("hero", 30, "GameFontNormalHuge")
DisplayFont("chapter", 19, "GameFontNormalLarge")
DisplayFont("ink", 14, "GameFontHighlight")
DisplayFont("stat", 18, "GameFontNormalLarge")
DisplayFont("keep", 24, "GameFontNormalLarge")
UI.FONTS = FONTS
local ROLE_FONT = { title = "title", head = "head", body = "body", dim = "dim", small = "small", date = "small", link = "dim", bad = "small",
    hero = "hero", chapter = "chapter", ink = "ink", stat = "stat", gold = "chapter", faint = "small", keep = "keep" }
-- which ink each role uses
local ROLE_INK = { title = "head", head = "head", date = "head", small = "dim", hero = "body", chapter = "body", ink = "dim", keep = "body",
    stat = "body", gold = "head", faint = "faint" }

-- Ink on parchment has no shadow (any shadow doubles the letter edges); the dark style keeps the usual one.
local function Shadow(fs)
    if parchment then fs:SetShadowOffset(0, 0)
    else fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1) end
end
UI.Shadow = Shadow
local function Style(fs, role)
    fs:SetFontObject(FONTS[ROLE_FONT[role] or "body"])
    local c = Ink(ROLE_INK[role] or role)
    fs:SetTextColor(c[1], c[2], c[3])
    Shadow(fs)
end
UI.Style, UI.Ink = Style, Ink

-- Scrolling page area, inside the page's decorated border.
local scroll = Kit.Make("ScrollFrame", inset, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(W - 110, 10)
scroll:SetScrollChild(content)
-- item links in notes show their tooltip on hover and open like chat links on click
if content.SetHyperlinksEnabled then
    content:SetHyperlinksEnabled(true)
    content:SetScript("OnHyperlinkEnter", function(self, link)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
    end)
    content:SetScript("OnHyperlinkLeave", GameTooltip_Hide)
    content:SetScript("OnHyperlinkClick", function(_, link, text, button) if SetItemRef then SetItemRef(link, text, button) end end)
end
UI.content = content
local CW = W - 110   -- text width
local function PlaceScroll()
    local l, t, r, b = 22, 24, 30, 10   -- dark: clear of the round portrait in the top-left corner
    if UI.usedStyle == "classic" then l, t, r, b = 20, 16, 34, 12   -- the classic page has plain edges
    elseif UI.usedStyle == "moderndark" then l, t, r, b = 22, 24, 30, 14
    elseif parchment then l, t, r, b = 34, 30, 50, 34 end   -- inside the spellbook page's curled edges
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", l, -t)
    scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -r, b)
    local bar = Child(scroll, "ScrollBar")
    if bar then
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 0)
        bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, 0)
    end
    CW = W - l - r - 26
    content:SetWidth(CW + 4)
end

-- Bláto Journal's own page code lives in the table BJ: this file's main chunk is close to Lua's limit of 200
-- local variables, so the additions take one.
local BJ = {}

-- Classic chrome (Bláto Journal) ------------------------------------------------------------------------
-- The classic style swaps the modern window art for the old game's dialog frame: dark marble, the grey-gold
-- border (the client's own BACKDROP_DIALOG_32_32 files) and the title on the header plate. The page inset moves
-- inside that border. Picking another style brings the modern art and the old positions back.
BJ.MODERN_ART = { "NineSlice", "Bg", "TopTileStreaks", "PortraitContainer", "portrait", "TitleContainer", "TitleBg" }
function BJ.SavePoints(f)
    local pts = {}
    for i = 1, f:GetNumPoints() do pts[i] = { f:GetPoint(i) } end
    return pts
end
function BJ.RestorePoints(f, pts)
    if not (f and pts and #pts > 0) then return end
    f:ClearAllPoints()
    for _, p in ipairs(pts) do f:SetPoint(unpack(p)) end
end
function UI.Chrome(on)
    if on and not BJ.classic then
        BJ.classic = CreateFrame("Frame", nil, win, BackdropTemplateMixin and "BackdropTemplate" or nil)
        BJ.classic:SetAllPoints(win)
        BJ.classic:SetFrameLevel(win:GetFrameLevel())   -- under the inset and the buttons
        if BJ.classic.SetBackdrop then
            BJ.classic:SetBackdrop(BACKDROP_DIALOG_32_32 or { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileEdge = true, tileSize = 32, edgeSize = 32,
                insets = { left = 11, right = 12, top = 12, bottom = 11 } })
        end
        local plate = BJ.classic:CreateTexture(nil, "ARTWORK")
        plate:SetSize(300, 64)
        plate:SetPoint("TOP", 0, 12)
        local hasPlate = plate:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
        plate:SetShown(hasPlate and true or false)
        BJ.classic.title = BJ.classic:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        BJ.classic.title:SetPoint("TOP", BJ.classic, "TOP", 0, hasPlate and -2 or -16)
        BJ.classic.title:SetText("Bláto Journal")
        local close = Child(win, "CloseButton")
        BJ.savedPoints = { inset = inset ~= win and BJ.SavePoints(inset), close = close and BJ.SavePoints(close),
            back = UI.backButton and BJ.SavePoints(UI.backButton) }
    end
    if not BJ.classic then return end   -- never was classic: nothing to undo
    BJ.classic:SetShown(on)
    for _, key in ipairs(BJ.MODERN_ART) do local c = Child(win, key); if c then c:SetShown(not on) end end
    if inset ~= win then for _, key in ipairs({ "NineSlice", "Bg" }) do local c = Child(inset, key); if c then c:SetShown(not on) end end end
    local close = Child(win, "CloseButton")
    if on then
        if inset ~= win then
            inset:ClearAllPoints()
            inset:SetPoint("TOPLEFT", win, "TOPLEFT", 12, -30)
            inset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -12, 32)
        end
        if close then close:ClearAllPoints(); close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -5, -5) end
        if UI.backButton then UI.backButton:ClearAllPoints(); UI.backButton:SetPoint("TOPLEFT", win, "TOPLEFT", 14, -7) end
    else
        BJ.RestorePoints(inset ~= win and inset or nil, BJ.savedPoints.inset)
        BJ.RestorePoints(close, BJ.savedPoints.close)
        BJ.RestorePoints(UI.backButton, BJ.savedPoints.back)
    end
end

function UI.ApplyStyle()
    local used = PaintPage(page)
    parchment = Paper(used)
    UI.usedStyle = used or "dark"
    UI.Chrome(used == "classic")
    -- the spellbook page has an empty margin above its top edge: pull it up under the title bar
    page:ClearAllPoints()
    if used == "classic" then
        page:SetAllPoints(inset)
    elseif parchment then
        page:SetPoint("TOPLEFT", inset, "TOPLEFT", -6, 34)
        page:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 6, -4)
    else
        page:SetPoint("TOPLEFT", inset, "TOPLEFT", 2, -2)
        page:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -2, 2)
    end
    PlaceScroll()
    if UI.StyleDialog then UI.StyleDialog() end
    if win:IsShown() then UI.Render() end
end

-- Page building blocks (pooled; the page is rebuilt on every change) ------------------------------
local pools = {}
local function Pool(name, make)
    pools[name] = pools[name] or { list = {}, n = 0, make = make }
    return pools[name]
end
local y
local persistent = {}   -- form widgets that live on the page and are placed during a render
local function Reset()
    for _, p in pairs(pools) do for _, f in ipairs(p.list) do f:Hide() end; p.n = 0 end
    for _, f in ipairs(persistent) do f:Hide(); f:ClearAllPoints() end
    y = -2
end
local function Next(name, make)
    local p = Pool(name, make)
    p.n = p.n + 1
    local f = p.list[p.n]
    if not f then f = p.make(); p.list[p.n] = f end
    f:ClearAllPoints()
    f:Show()
    return f
end
local function MakeFS() local f = content:CreateFontString(nil, "OVERLAY"); f:SetJustifyH("LEFT"); f:SetWordWrap(true); return f end

-- A line of text at the cursor; moves the cursor down unless keep is set.
-- Item quality colours are made for dark backgrounds; on parchment, links get darker versions of the same hues.
local PAPER_HEX = { ffffffff = "ff4a2c10", ff9d9d9d = "ff5a5a5a", ff1eff00 = "ff1f6e00", ff0070dd = "ff0a4a9a",
    ffa335ee = "ff6a1fa0", ffff8000 = "ff9a4a00", ffe6cc80 = "ff7a6420", ff00ccff = "ff006a88" }
local PAPER_QUALITY = { [0] = "ff5a5a5a", "ff4a2c10", "ff1f6e00", "ff0a4a9a", "ff6a1fa0", "ff9a4a00", "ff7a6420", "ff006a88" }
local function InkLinks(str)
    if not parchment or type(str) ~= "string" or not str:find("|H", 1, true) then return str end
    str = str:gsub("|c(%x%x%x%x%x%x%x%x)|H", function(c) return "|c" .. (PAPER_HEX[c:lower()] or c) .. "|H" end)
    str = str:gsub("|cnIQ(%d):|H", function(q) return "|c" .. (PAPER_QUALITY[tonumber(q)] or "ff4a2c10") .. "|H" end)
    return str
end

local function Text(str, role, indent, rightPad, keep)
    local fs = Next("fs", MakeFS)
    Style(fs, role)
    indent = indent or 0
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetWidth(CW - indent - (rightPad or 0))
    fs:SetPoint("TOPLEFT", indent, y)
    fs:SetText(InkLinks(str))
    if not keep then y = y - fs:GetStringHeight() - ((role == "title" or role == "hero") and 10 or role == "head" and 6 or 4) end
    return fs
end
local function Gap(h) y = y - (h or 8) end
-- A small ink dot, for lists of events.
local function Dot(x, top)
    local t = Next("dot", function() return content:CreateTexture(nil, "ARTWORK") end)
    local c = Ink("head")
    t:SetColorTexture(c[1], c[2], c[3], 0.8)
    t:SetSize(4, 4)
    t:SetPoint("TOPLEFT", x, top)
    return t
end
local function IsModern() return UI.usedStyle == "moderndark" or UI.usedStyle == "modernparchment" end
local function Divider()
    Gap(4)
    local t = Next("line", function() return content:CreateTexture(nil, "ARTWORK") end)
    if IsModern() and C_Texture.GetAtlasInfo("spellbook-divider") then
        t:SetAtlas("spellbook-divider")
        t:SetVertexColor(1, 1, 1, parchment and 1 or 0.7)
        t:SetSize(CW, 8)
        t:SetPoint("TOPLEFT", 0, y + 3)
    else
        local c = Ink("head")
        t:SetColorTexture(c[1], c[2], c[3], parchment and 0.35 or 0.4)
        t:SetSize(CW, 1)
        t:SetPoint("TOPLEFT", 0, y)
    end
    Gap(10)
end
-- Icons: rounded corners and a thin metal rim like the profession book, from the addon's own art (Art/*.tga).
local ART = "Interface/AddOns/BlatoJournal/Art/"
function UI.DressIcon(holder, icon, under)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    if holder.CreateMaskTexture and icon.AddMaskTexture then
        local mask = holder:CreateMaskTexture()
        mask:SetTexture(ART .. "IconMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
        if under and under.AddMaskTexture then under:AddMaskTexture(mask) end
    end
    local rim = holder:CreateTexture(nil, "OVERLAY", nil, 6)
    rim:SetTexture(ART .. "IconRim")
    rim:SetAllPoints(icon)
    holder.iconBorder = rim
end
-- Icons by purpose. Each is a list tried in order: atlases from the newer UI, then a classic icon file.
local ICONSET = {
    commands = { "Interface/Icons/Spell_Nature_EarthElemental_Totem" },   -- Bláto Journal: mud
    dungeons = { "UI-HUD-MicroMenu-Groupfinder-Up", "Interface/Icons/INV_Misc_Key_03" },
    journey = { "UI-HUD-MicroMenu-SpellbookAbilities-Up", "Interface/Icons/INV_Misc_Book_09" },
    places = { "Waypoint-MapPin-Tracked", "UI-HUD-MicroMenu-Collections-Up", "Interface/Icons/INV_Misc_Map_01" },
    goals = { "UI-HUD-MicroMenu-Achievements-Up", "Interface/Icons/Ability_Tracking" },
    notes = { "common-icon-chatlink", "Interface/Icons/INV_Feather_05" },
    quests = { "QuestTurnin", "QuestRepeatableTurnin", "Interface/GossipFrame/ActiveQuestIcon", "Interface/Icons/INV_Scroll_03" },
    fellowship = { "UI-HUD-MicroMenu-GuildCommunities-Up", "Interface/Icons/Spell_Holy_PrayerOfHealing" },
    time = { "Interface/Icons/INV_Misc_PocketWatch_01" },
    kills = { "UI-HUD-MicroMenu-PvP-Up", "Interface/Icons/Ability_DualWield" },
    falls = { "Interface/Icons/Ability_Rogue_FeignDeath" },
    xp = { "UI-HUD-MicroMenu-SpecTalents-Up", "Interface/Icons/Spell_Holy_SealOfWisdom" },
    gold = { "Interface/Icons/INV_Misc_Coin_02" },
}
UI.ICONSET = ICONSET
-- Paints an icon spec (a file, or an ICONSET key/list) on a texture; returns what it used and whether it is an atlas.
local function PaintIcon(tex, spec)
    if type(spec) == "string" and ICONSET[spec] then spec = ICONSET[spec] end
    if type(spec) ~= "table" then tex:SetTexture(spec); tex:SetTexCoord(0.07, 0.93, 0.07, 0.93); return spec, false end
    for _, name in ipairs(spec) do
        if not name:find("[/\\]") then
            if C_Texture.GetAtlasInfo(name) then tex:SetAtlas(name); return name, true end
        else
            tex:SetTexture(name); tex:SetTexCoord(0.07, 0.93, 0.07, 0.93); return name, false
        end
    end
end
UI.PaintIcon = PaintIcon
local function Icon(tex, x, top, size)
    local f = Next("icon", function()
        local h = CreateFrame("Frame", nil, content)
        h.icon = h:CreateTexture(nil, "ARTWORK")
        h.icon:SetAllPoints()
        UI.DressIcon(h, h.icon)
        return h
    end)
    local _, atlas = PaintIcon(f.icon, tex)
    if f.iconBorder then f.iconBorder:SetShown(not atlas) end
    f:SetSize(size, size)
    f:SetPoint("TOPLEFT", x, top)
    return f
end
-- Quiet text link (instead of heavy red buttons on the page). right: distance from the right edge.
local function Link(label, right, top, onClick)
    local b = Next("link", function()
        local l = CreateFrame("Button", nil, content)
        l.fs = l:CreateFontString(nil, "OVERLAY")
        l.fs:SetPoint("CENTER")
        l:SetScript("OnEnter", function(self) local c = Ink("linkHover"); self.fs:SetTextColor(c[1], c[2], c[3]) end)
        l:SetScript("OnLeave", function(self) local c = Ink("link"); self.fs:SetTextColor(c[1], c[2], c[3]) end)
        return l
    end)
    Style(b.fs, "link")
    b.fs:SetText(label)
    b:SetSize(b.fs:GetStringWidth() + 6, 16)
    b:SetPoint("TOPRIGHT", content, "TOPLEFT", CW - (right or 0), top)
    b:SetScript("OnClick", onClick)
    return b
end
-- Progress bar like the profession skill bar: dark track, frame, "have / need" written inside.
local function Atlas(tex, name) if C_Texture.GetAtlasInfo(name) then tex:SetAtlas(name); return true end end
-- Collapsible section header, like the category bars in a profession's recipe list. key remembers the
-- state (DB.collapsed); extra is a short line after the label (a summary while collapsed). Returns true when open.
local Hotspot   -- defined with the field-journal pieces below
local function Header(key, label, extra, closedByDefault)
    DB.collapsed = DB.collapsed or {}
    local closed = DB.collapsed[key]
    if closed == nil then closed = closedByDefault and true or false end
    Gap(4)
    local top = y
    local fs = Text(label, "gold", 0, 0, true)
    local w = fs:GetStringWidth()
    if extra and extra ~= "" then
        Text(extra, "ink", w + 10, 0, true):SetPoint("TOPLEFT", w + 10, top - 4)
        w = w + 10 + math.min(260, (#extra) * 6)
    end
    local line = Next("line", function() return content:CreateTexture(nil, "ARTWORK") end)
    local c = parchment and { 0.45, 0.30, 0.12, 0.4 } or { 0.24, 0.19, 0.13, 1 }
    line:SetColorTexture(unpack(c))
    line:SetSize(math.max(10, CW - w - 40), 1)
    line:SetPoint("TOPLEFT", w + 12, top - 11)
    Text(closed and "+" or "–", "gold", CW - 16, 0, true):SetPoint("TOPLEFT", CW - 14, top - 1)
    Hotspot(0, top + 2, CW, 26, function() DB.collapsed[key] = not closed; UI.Render() end)
    y = top - 30
    return not closed
end

local function Check(x, top, checked, onClick)
    local c = Next("check", function() local cb = Kit.Make("CheckButton", content, "UICheckButtonTemplate"); cb:SetSize(24, 24); return cb end)
    c:SetPoint("TOPLEFT", x, top + 3)
    c:SetChecked(checked)
    c:SetScript("OnClick", onClick)
    return c
end
local function Persist(f) persistent[#persistent + 1] = f; f:Hide(); return f end
-- A soft panel behind an entry, from top to the current y (pinned notes on the Journey page).
local function Card(top)
    local t = Next("card", function() return content:CreateTexture(nil, "BACKGROUND", nil, 1) end)
    if parchment then t:SetColorTexture(1, 0.97, 0.9, 0.35) else t:SetColorTexture(1, 0.9, 0.7, 0.06) end
    t:SetPoint("TOPLEFT", 0, top)
    t:SetSize(CW, math.max(1, top - y))
end
-- A red wax seal: the note is pinned to the Journey page.
local function Seal(x, top)
    local outer = Next("seal", function() local t = content:CreateTexture(nil, "ARTWORK", nil, 4); t:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask"); return t end)
    local inner = Next("sealin", function() local t = content:CreateTexture(nil, "ARTWORK", nil, 5); t:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask"); return t end)
    outer:SetVertexColor(0.55, 0.10, 0.06, 1); outer:SetSize(20, 20); outer:SetPoint("TOPLEFT", x, top)
    inner:SetVertexColor(0.70, 0.18, 0.11, 1); inner:SetSize(12, 12); inner:SetPoint("TOPLEFT", x + 4, top - 4)
end
-- A thin ink line down the left of an entry, from top to the current y (reminders, pinned notes).
local function Accent(x, top)
    local t = Next("accent", function() return content:CreateTexture(nil, "ARTWORK") end)
    local c = Ink("head")
    t:SetColorTexture(c[1], c[2], c[3], parchment and 0.55 or 0.8)
    t:SetPoint("TOPLEFT", x, top)
    t:SetSize(2, math.max(1, top - y - 2))
end

-- Field-journal pieces ---------------------------------------------------------------------------
-- The journal's own textures (Media/*.tga, drawn by .harness/textures.py): one shape per piece, a Dark and a
-- Light version, so both styles share one look. Pieces that stretch are cut 9-slice: fixed corners, stretched edges.
local MEDIA = "Interface\\AddOns\\BlatoJournal\\Media\\"
local KIT = {   -- name = { width, height, edge }
    Card = { 32, 32, 10 }, Chip = { 16, 16, 5 }, Field = { 32, 32, 8 }, Paper = { 256, 64, 12 },
    Track = { 64, 16, 7 }, Fill = { 64, 16, 7 }, Badge = { 32, 32, 5 }, Tag = { 128, 48, 20 },
}
local function KitFile(name, mode) return MEDIA .. name .. (mode or "") end
-- Builds the 9-slice of texture file (w x h, corners of edge px) as textures of owner around anchor.
local function NineSlice(owner, anchor, layer, sub, extra, file, w, h, edge, scale)
    local pieces = {}
    local du, dv = edge / w, edge / h
    local function piece(u1, u2, v1, v2)
        local t = owner:CreateTexture(nil, layer, nil, sub)
        t:SetTexture(file)
        t:SetTexCoord(u1, u2, v1, v2)
        pieces[#pieces + 1] = t
        if extra then extra[#extra + 1] = t end
        return t
    end
    local e, a = math.max(1, math.floor(edge * (scale or 1) + 0.5)), anchor
    local tl = piece(0, du, 0, dv); tl:SetSize(e, e); tl:SetPoint("TOPLEFT", a)
    local tr = piece(1 - du, 1, 0, dv); tr:SetSize(e, e); tr:SetPoint("TOPRIGHT", a)
    local bl = piece(0, du, 1 - dv, 1); bl:SetSize(e, e); bl:SetPoint("BOTTOMLEFT", a)
    local br = piece(1 - du, 1, 1 - dv, 1); br:SetSize(e, e); br:SetPoint("BOTTOMRIGHT", a)
    local top = piece(du, 1 - du, 0, dv); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    local bot = piece(du, 1 - du, 1 - dv, 1); bot:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local lef = piece(0, du, dv, 1 - dv); lef:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lef:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    local rig = piece(1 - du, 1, dv, 1 - dv); rig:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rig:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    local mid = piece(du, 1 - du, dv, 1 - dv); mid:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); mid:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    return pieces
end
-- A kit piece in both modes around anchor; call the returned function to show the one for the current style.
-- both: the piece has a Dark and a Light file (most do); pieces in SINGLE have one file for both styles.
local SINGLE = { Fill = true, Badge = true, Tag = true }
local function KitPiece(owner, anchor, layer, sub, extra, name, both, scale)
    if both == nil then both = not SINGLE[name] end
    local k = KIT[name]
    local sets = {}
    for _, mode in ipairs(both and { "Dark", "Light" } or { "" }) do
        sets[mode] = NineSlice(owner, anchor, layer, sub, extra, KitFile(name, mode), k[1], k[2], k[3], scale)
    end
    return function(show)
        for mode, set in pairs(sets) do
            local on = show ~= false and (mode == "" or (mode == "Light") == (parchment ~= nil))
            for _, t in ipairs(set) do t:SetShown(on) end
        end
    end
end
-- A card on a frame of its own (the note composer); returns the switch.
UI.BuildCard = function(owner) return KitPiece(owner, owner, "BORDER", 3, nil, "Card") end
UI.KitPiece = KitPiece
-- A piece of an atlas as a plain texture: crop keeps the middle part (0.1 = drop 10% on every side).
local function AtlasCrop(tex, name, crop)
    local i = C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
    if not i or not (i.file or i.filename) then return false end
    local du, dv = (i.rightTexCoord - i.leftTexCoord) * crop, (i.bottomTexCoord - i.topTexCoord) * crop
    tex:SetTexture(i.file or i.filename)
    tex:SetTexCoord(i.leftTexCoord + du, i.rightTexCoord - du, i.topTexCoord + dv, i.bottomTexCoord - dv)
    return true
end
UI.AtlasCrop = AtlasCrop
-- A panel: textures on the page itself (BACKGROUND layers), so the page's text, which sits on the same frame
-- in the OVERLAY layer, always draws on top. (A child frame would cover it.) Plain boxes wear the kit card;
-- a custom fill or edge gives a flat panel instead. kind picks another kit piece ("Paper").
local BoxMethods = {
    ClearAllPoints = function(self) self.box:ClearAllPoints() end,
    SetPoint = function(self, ...) self.box:SetPoint(...) end,
    SetSize = function(self, w, h) self.box:SetSize(w, h) end,
    Show = function(self) for _, t in ipairs(self.all) do t:Show() end end,
    Hide = function(self) for _, t in ipairs(self.all) do t:Hide() end end,
}
local function Box(x, top, w, h, fill, edge, kind)
    kind = type(kind) == "string" and kind or "Card"
    local f = Next("box", function()
        local b = setmetatable({ all = {}, kits = {} }, { __index = BoxMethods })
        b.box = content:CreateTexture(nil, "BACKGROUND", nil, 0)
        b.box:SetColorTexture(0, 0, 0, 0)
        b.bg = content:CreateTexture(nil, "BACKGROUND", nil, 1)
        b.bg:SetAllPoints(b.box)
        b.edges = {}
        for i = 1, 4 do b.edges[i] = content:CreateTexture(nil, "BACKGROUND", nil, 2) end
        local a = b.box
        b.edges[1]:SetPoint("TOPLEFT", a); b.edges[1]:SetPoint("TOPRIGHT", a); b.edges[1]:SetHeight(1)
        b.edges[2]:SetPoint("BOTTOMLEFT", a); b.edges[2]:SetPoint("BOTTOMRIGHT", a); b.edges[2]:SetHeight(1)
        b.edges[3]:SetPoint("TOPLEFT", a); b.edges[3]:SetPoint("BOTTOMLEFT", a); b.edges[3]:SetWidth(1)
        b.edges[4]:SetPoint("TOPRIGHT", a); b.edges[4]:SetPoint("BOTTOMRIGHT", a); b.edges[4]:SetWidth(1)
        b.all = { b.box, b.bg, b.edges[1], b.edges[2], b.edges[3], b.edges[4] }
        return b
    end)
    f:SetPoint("TOPLEFT", x, top)
    f:SetSize(w, h)
    local framed = not fill and not edge
    if framed and not f.kits[kind] then f.kits[kind] = KitPiece(content, f.box, "BACKGROUND", kind == "Fill" and 4 or 3, f.all, kind, not SINGLE[kind]) end
    for k, show in pairs(f.kits) do show(framed and k == kind) end
    f.bg:SetShown(not framed)
    for _, e in ipairs(f.edges) do e:SetShown(not framed) end
    if not framed then
        f.bg:SetColorTexture(unpack(fill or (parchment and { 1, 0.97, 0.9, 0.25 } or { 1, 0.9, 0.7, 0.035 })))
        edge = edge or (parchment and { 0.45, 0.30, 0.12, 0.45 } or { 0.30, 0.24, 0.15, 1 })
        for _, e in ipairs(f.edges) do e:SetColorTexture(unpack(edge)) end
    end
    return f
end
-- A clickable area over part of the page (cards, chapter rows); highlights on hover.
Hotspot = function(x, top, w, h, onClick, tip)
    local b = Next("hot", function()
        local h2 = CreateFrame("Button", nil, content)
        h2.hl = h2:CreateTexture(nil, "HIGHLIGHT")
        h2.hl:SetAllPoints()
        h2.hl:SetColorTexture(1, 0.85, 0.5, 0.06)
        return h2
    end)
    b:SetPoint("TOPLEFT", x, top)
    b:SetSize(w, h)
    b:SetFrameLevel(content:GetFrameLevel() + 1)
    b:SetScript("OnClick", function() PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON); onClick() end)
    b:SetScript("OnEnter", tip and function(self) GameTooltip:SetOwner(self, "ANCHOR_CURSOR"); GameTooltip:SetText(tip); GameTooltip:Show() end or nil)
    b:SetScript("OnLeave", tip and GameTooltip_Hide or nil)
    return b
end
-- A round medallion (Media/Ring*): bronze rim, a face that matches the style, and a number or an icon in it.
local CIRCLE = "Interface/CHARACTERFRAME/TempPortraitAlphaMask"
-- portrait: an Adventure Guide boss portrait (128x64, the bust on its left half): cropped to a square
-- model: a creature display ID; its portrait is drawn instead of the icon
local function Ring(x, top, size, label, bright, icon, portrait, model)
    local r = Next("ring", function()
        local f = CreateFrame("Frame", nil, content)
        f.ring = f:CreateTexture(nil, "ARTWORK", nil, 1)
        f.ring:SetAllPoints()
        f.icon = f:CreateTexture(nil, "ARTWORK", nil, 3)
        if f.CreateMaskTexture and f.icon.AddMaskTexture then
            f.mask = f:CreateMaskTexture()
            f.mask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            f.mask:SetAllPoints(f.icon)
            f.icon:AddMaskTexture(f.mask)
        end
        f.text = f:CreateFontString(nil, "OVERLAY")
        f.text:SetPoint("CENTER", 0, 1)
        return f
    end)
    r:SetPoint("TOPLEFT", x, top)
    r:SetSize(size, size)
    r:SetFrameLevel(content:GetFrameLevel() + 2)
    r.ring:SetTexture(KitFile("Ring", parchment and "Light" or "Dark"))
    local inset = math.floor(size * 0.14 + 0.5)
    r.icon:ClearAllPoints()
    r.icon:SetPoint("TOPLEFT", inset, -inset); r.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    r.icon:SetTexture(icon)
    if model and SetPortraitTextureFromCreatureDisplayID then
        r.icon:SetTexCoord(0, 1, 0, 1)
        if not pcall(SetPortraitTextureFromCreatureDisplayID, r.icon, model) then r.icon:SetTexture(icon) end
    elseif portrait then r.icon:SetTexCoord(0.0, 0.5, 0.0, 1.0) else r.icon:SetTexCoord(0, 1, 0, 1) end
    r.icon:SetShown(icon ~= nil)
    r.text:SetFontObject(size >= 38 and FONTS.chapter or FONTS.ink)
    local c = parchment and Ink("head") or { 0.91, 0.77, 0.42 }
    r.text:SetTextColor(c[1], c[2], c[3])
    Shadow(r.text)
    r.text:SetText(label or "")
    return r
end
-- A thin vertical line (the journey's timeline), drawn behind the rings.
local function VLine(x, top, bottom)
    local t = Next("vline", function() return content:CreateTexture(nil, "BACKGROUND", nil, 2) end)
    local c = parchment and { 0.45, 0.30, 0.12, 0.5 } or { 0.35, 0.28, 0.19, 1 }
    t:SetColorTexture(unpack(c))
    t:SetPoint("TOPLEFT", x, top)
    t:SetSize(2, math.max(1, top - bottom))
end
-- A progress track (Media/Track* with the gold Media/Fill); h 8 on cards, 16 with a label for goals.
local function Track(x, top, w, frac, h, label)
    h = h or 8
    local t = Next("track", function()
        local f = CreateFrame("Frame", nil, content)
        f.fillAnchor = f:CreateTexture(nil, "ARTWORK")
        f.fillAnchor:SetPoint("TOPLEFT"); f.fillAnchor:SetPoint("BOTTOMLEFT")
        f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        f.text:SetPoint("CENTER", 0, 0)
        f.text:SetShadowColor(0, 0, 0, 1); f.text:SetShadowOffset(1, -1)
        f.sets = {}
        return f
    end)
    if not t.sets[h] then
        local sc = h / 16
        t.sets[h] = { KitPiece(t, t, "ARTWORK", 1, nil, "Track", nil, sc), KitPiece(t, t.fillAnchor, "ARTWORK", 2, nil, "Fill", false, sc) }
    end
    for hh, set in pairs(t.sets) do set[1](hh == h); set[2](hh == h and frac > 0) end
    t:SetPoint("TOPLEFT", x, top)
    t:SetSize(w, h)
    t:SetFrameLevel(content:GetFrameLevel() + 2)
    t.fillAnchor:SetWidth(math.max(h, w * math.min(1, math.max(0, frac))))
    t.text:SetText(label or "")
    return t
end
local function Bar(x, top, width, have, need)
    return Track(x, top, width, have / math.max(1, need), 16, ("%d / %d"):format(have, need))
end
-- A small pill of text on the kit chip (quest filters), or the gold badge (NOW).
local function Chip(label, x, top, kind)
    local f = Next("chip", function()
        local c = CreateFrame("Frame", nil, content)
        c.text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        c.text:SetPoint("CENTER", 0, 0)
        c.kits = {}
        return c
    end)
    kind = kind or "Chip"
    if not f.kits[kind] then f.kits[kind] = KitPiece(f, f, "ARTWORK", 1, nil, kind, not SINGLE[kind]) end
    for k, show in pairs(f.kits) do show(k == kind) end
    f.text:SetText(label)
    if kind == "Badge" then
        f.text:SetTextColor(0.16, 0.09, 0.02); f.text:SetShadowOffset(0, 0)
    else
        local c = Ink("body"); f.text:SetTextColor(c[1], c[2], c[3]); Shadow(f.text)
    end
    f:SetSize(f.text:GetStringWidth() + 16, 20)
    f:SetPoint("TOPLEFT", x, top)
    f:SetFrameLevel(content:GetFrameLevel() + 2)
    return f
end
-- Page head: big storybook title, a line of ink under it, and a thin rule with a diamond.
local function PageHead(title, sub, rightPad, subRole, ruleGap)   -- ruleGap: keep the rule clear of something on the right
    local top = y
    local hero = Text(title, "hero", 2, rightPad)
    if sub then Text(sub, subRole or "ink", 2, rightPad) end
    Gap(8)
    local l = Next("line", function() return content:CreateTexture(nil, "ARTWORK") end)
    local c = parchment and { 0.45, 0.30, 0.12, 0.5 } or { 0.29, 0.23, 0.15, 1 }
    l:SetColorTexture(unpack(c)); l:SetSize(CW - (ruleGap or 0), 1); l:SetPoint("TOPLEFT", 0, y)
    Gap(16)
    return top, hero
end
-- A stat tile: icon, a big number and a line under it.
local TILE_H = 66
local function StatTile(x, top, w, icon, big, small, onClick, tip)
    Box(x, top, w, TILE_H, nil, nil, true)
    if onClick then Hotspot(x, top, w, TILE_H, onClick, tip) end
    Icon(icon, x + 12, top - 15, 36)
    local b = Text(big, "stat", x + 58, 0, true)
    b:SetPoint("TOPLEFT", x + 58, top - 14)
    b:SetWidth(w - 66)
    b:SetWordWrap(false)
    local fs = Text(small, "small", x + 58, 0, true)
    fs:SetPoint("TOPLEFT", x + 58, top - 38)
    fs:SetWidth(w - 66)
    fs:SetWordWrap(false)
    if parchment then
        b:SetTextColor(unpack(Ink("body"))); b:SetShadowOffset(0, 0)
        fs:SetTextColor(unpack(Ink("dim"))); fs:SetShadowOffset(0, 0)
    else
        b:SetTextColor(1, 0.97, 0.9); b:SetShadowColor(0, 0, 0, 1); b:SetShadowOffset(1, -1)
        fs:SetTextColor(0.80, 0.74, 0.62); fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
    end
end
local function Tiles(list)
    local w = math.floor((CW - 12 * (#list - 1)) / #list)
    local top = y
    for i, t in ipairs(list) do StatTile((i - 1) * (w + 12), top, w, t[1], t[2], t[3], t[4], t[5]) end
    y = top - TILE_H - 14
end
-- An event line: a small round icon, the text, and its date on the right.
local function EventLine(x, icon, text, date)
    local top = y
    Ring(x, top + 2, 20, nil, false, icon)
    local fs = Text(text, "body", x + 28, 60, true)
    fs:SetPoint("TOPLEFT", x + 28, top)
    Text(date, "ink", CW - 52, 0, true):SetPoint("TOPLEFT", CW - 52, top + 1)
    y = top - math.max(24, fs:GetStringHeight() + 8)
end
local EVENT_ICON = { death = "Interface/Icons/Ability_Rogue_FeignDeath", level = "Interface/Icons/Spell_Holy_HolyBolt",
    zone = "Interface/Icons/INV_Misc_Map_01", dungeon = "Interface/Icons/INV_Misc_Key_03", goal = "Interface/Icons/Ability_Tracking" }
UI.EVENT_ICON = EVENT_ICON

-- Bottom bar buttons, set per view.
local barButtons = {}
local function BarButtons(list)
    for i = 1, math.max(#barButtons, #list) do
        local b = barButtons[i]
        if not b then
            b = Kit.Make("Button", win, "UIPanelButtonTemplate")
            b:SetSize(120, 22)
            barButtons[i] = b
        end
        local def = list[i]
        b:ClearAllPoints()
        if def then
            if i == 1 then b:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, 4)
            else b:SetPoint("RIGHT", barButtons[i - 1], "LEFT", -4, 0) end
            b:SetText(def[1])
            b:SetScript("OnClick", def[2])
            b:Show()
        else
            b:Hide()
        end
    end
end

-- Settings button beside the close button (Options > AddOns > BlatoJournal).
do
    local close = Child(win, "CloseButton")
    local gear = CreateFrame("Button", nil, win)
    gear:SetSize(18, 18)
    if close then gear:SetPoint("RIGHT", close, "LEFT", -4, 0) else gear:SetPoint("TOPRIGHT", -30, -4) end
    gear:SetFrameLevel((close or win):GetFrameLevel() + 2)   -- above the title bar art
    local icon = gear:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface/Icons/INV_Misc_Gear_01")
    UI.DressIcon(gear, icon)
    local hl = gear:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.2)
    gear:SetScript("OnClick", function() if BlatoJournal_OpenSettings then BlatoJournal_OpenSettings() end end)
    gear:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText("Settings"); GameTooltip:Show() end)
    gear:SetScript("OnLeave", GameTooltip_Hide)
end

-- Archive link in the top-right corner of Notes, Goals and Quests: "Archive (n)" opens that page's archive,
-- "Back" closes it. The archive view itself is RenderArchive, below the notes (it uses their hover links).
local archiveOpen = {}
local RenderArchive
local Entry     -- hover links (defined with the notes)
local entries = {}   -- hover areas on the page this render: { frame, links }
local function ArchiveLink(kind, top)
    local n = #J.Archived(kind)
    Link(archiveOpen[kind] and "Back" or n > 0 and ("Archive (%d)"):format(n) or "Archive", 0, top - 4, function()
        archiveOpen[kind] = not archiveOpen[kind]
        UI.Render()
    end)
end

-- Tabs -------------------------------------------------------------------------------------
-- Bláto Journal: Commands (the party's buttons) first, the page the journal opens on, then the Dungeon Journal.
-- No Goals and no Fellowship page (the fellowship is still counted: the Journey and the Quests pages use it).
local TABS = { { "commands", "Commands" }, { "dungeons", "Dungeons" }, { "journey", "Journey" }, { "places", "Places" },
    { "quests", "Quests" }, { "notes", "Notes" } }
local current = "commands"
-- Icon tabs down the right edge, like the professions and group finder windows.
-- Tabs hang under the window: icon and name, the open one a little longer and lit.
local tabs = {}
for i, t in ipairs(TABS) do
    local tab = CreateFrame("Button", "BlatoJournalFrameTab" .. i, win)
    tab.l = tab:CreateTexture(nil, "BACKGROUND")
    tab.r = tab:CreateTexture(nil, "BACKGROUND")
    tab.m = tab:CreateTexture(nil, "BACKGROUND")
    tab.l:SetPoint("TOPLEFT"); tab.l:SetPoint("BOTTOMLEFT"); tab.l:SetWidth(35)
    tab.r:SetPoint("TOPRIGHT"); tab.r:SetPoint("BOTTOMRIGHT"); tab.r:SetWidth(37)
    tab.m:SetPoint("TOPLEFT", tab.l, "TOPRIGHT"); tab.m:SetPoint("BOTTOMRIGHT", tab.r, "BOTTOMLEFT")
    tab.icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon:SetSize(20, 20)
    tab.icon:SetPoint("LEFT", 13, 3)
    local _, atlas = PaintIcon(tab.icon, t[1])
    if not atlas then UI.DressIcon(tab, tab.icon) end
    tab.label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tab.label:SetPoint("LEFT", tab.icon, "RIGHT", 5, 0)
    tab.label:SetText(t[2])
    tab:SetSize(tab.label:GetStringWidth() + 52, 35)
    local hl = tab:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 8, -2); hl:SetPoint("BOTTOMRIGHT", -8, 6)
    hl:SetColorTexture(1, 0.85, 0.5, 0.08)
    if i == 1 then tab:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 10, 2)
    else tab:SetPoint("TOPLEFT", tabs[i - 1], "TOPRIGHT", -8, 0) end
    tab:SetScript("OnClick", function() PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB); UI.Show(t[1]) end)
    tab.key = t[1]
    tabs[i] = tab
end
-- Bláto Journal: in the classic style the tabs are the old character window's tabs (one texture cut in three),
-- text only, gold and white; where the client lacks that art they keep the modern look.
BJ.CLASSIC_TAB = { [true] = "Interface\\PaperDollInfoFrame\\UI-Character-ActiveTab",
    [false] = "Interface\\PaperDollInfoFrame\\UI-Character-InactiveTab" }
function BJ.ClassicTab(tab, on)
    if not tab.l:SetTexture(BJ.CLASSIC_TAB[on]) then return false end
    tab.m:SetTexture(BJ.CLASSIC_TAB[on]); tab.r:SetTexture(BJ.CLASSIC_TAB[on])
    tab.l:SetTexCoord(0, 0.15625, 0, 1); tab.m:SetTexCoord(0.15625, 0.84375, 0, 1); tab.r:SetTexCoord(0.84375, 1, 0, 1)
    return true
end
local function SelectTab()
    local wantClassic = UI.usedStyle == "classic"
    for i, tab in ipairs(tabs) do
        local on = tab.key == current
        local old = wantClassic and BJ.ClassicTab(tab, on)
        tab.l:SetWidth(old and 20 or 35); tab.r:SetWidth(old and 20 or 37)
        tab.icon:SetShown(not old)
        tab.label:ClearAllPoints()
        if old then tab.label:SetPoint("CENTER", 0, on and 3 or 1) else tab.label:SetPoint("LEFT", tab.icon, "RIGHT", 5, 0) end
        tab:SetSize(tab.label:GetStringWidth() + (old and 40 or 52), old and 32 or (on and 42 or 35))
        tab:ClearAllPoints()
        if i == 1 then tab:SetPoint("TOPLEFT", win, "BOTTOMLEFT", old and 14 or 10, old and 6 or 2)
        else tab:SetPoint("TOPLEFT", tabs[i - 1], "TOPRIGHT", old and -14 or -8, 0) end
        if not old then
            for _, t in ipairs({ tab.l, tab.m, tab.r }) do t:SetTexCoord(0, 1, 0, 1) end
            local pre = on and "uiframe-activetab-" or "uiframe-tab-"
            local ok = Atlas(tab.l, pre .. "left") and Atlas(tab.r, pre .. "right") and Atlas(tab.m, "_" .. pre .. "center")
            if not ok then
                for _, t in ipairs({ tab.l, tab.m, tab.r }) do t:SetColorTexture(on and 0.23 or 0.12, on and 0.16 or 0.09, on and 0.09 or 0.06, 0.97) end
            end
        end
        tab:SetFrameLevel(win:GetFrameLevel() + (on and 3 or 1))
        if old then tab.label:SetTextColor(1, on and 1 or 0.82, on and 1 or 0)
        else tab.label:SetTextColor(on and 1 or 0.72, on and 0.9 or 0.65, on and 0.63 or 0.5) end
        tab.icon:SetDesaturated(not on)
    end
end

-- Journey ----------------------------------------------------------------------------------
-- Race and class for the line under your name ("Gnome Mage").
local function Who()
    local ok, race = pcall(UnitRace, "player")
    local ok2, class = pcall(UnitClass, "player")
    local parts = {}
    if ok and type(race) == "string" and not (issecretvalue and issecretvalue(race)) then parts[#parts + 1] = race end
    if ok2 and type(class) == "string" and not (issecretvalue and issecretvalue(class)) then parts[#parts + 1] = class end
    return table.concat(parts, " ")
end

-- A pinned note on the Journey page: a parchment scrap in the chapter, dark ink whatever the page style.
local function Scrap(x, n)
    local top = y
    local w = CW - x
    local fs = Text(n.text, "body", x + 16, 16, true)
    fs:SetPoint("TOPLEFT", x + 16, top - 14)
    fs:SetTextColor(0.18, 0.11, 0.05)
    fs:SetShadowOffset(0, 0)
    local where = Text(("%s  ·  %s"):format(J.NoteWhere(n), J.Date(n.t)), "small", x + 16, 16, true)
    where:SetPoint("TOPLEFT", x + 16, top - 20 - fs:GetStringHeight())
    where:SetTextColor(0.42, 0.31, 0.17)
    where:SetShadowOffset(0, 0)
    local h = fs:GetStringHeight() + where:GetStringHeight() + 30
    -- a soft shadow, then the paper (Media/Paper*) and a strip of tape (Media/Tape) across the top
    local shadow = Next("scrapshadow", function() return content:CreateTexture(nil, "BACKGROUND", nil, 2) end)
    shadow:SetColorTexture(0, 0, 0, 0.28)
    shadow:SetSize(w - 4, h - 4)
    shadow:SetPoint("TOPLEFT", x + 5, top - 6)
    Box(x, top, w, h, nil, nil, "Paper")
    local tape = Next("tape", function() return content:CreateTexture(nil, "ARTWORK", nil, 3) end)
    tape:SetTexture(KitFile("Tape"))
    tape:SetSize(88, 18)
    tape:SetPoint("TOPLEFT", x + w / 2 - 44, top + 9)
    y = top - h - 12
end

-- Journey ------------------------------------------------------------------------------------
-- Every moment of the journey in one place: shown by level (chapters on a timeline), by day or by zone, with a
-- search and a filter. Ordinary moments are rows in ledger cards; the big ones are keepsakes that sit in the
-- page like objects: pinned notes on paper, reputation under a wax seal, first boss kills under a ribbon, and
-- epic finds on a paper tag (tied to the boss card when they dropped right after it).
local KIND_ICON = {
    spell = "Interface/Icons/INV_Misc_Book_11", recipe = "Interface/Icons/INV_Scroll_03", profession = "Interface/Icons/INV_Misc_Note_01",
    skill = "Interface/Icons/INV_Sword_04", respec = "Interface/Icons/Spell_Nature_Polymorph_Cow", rep = "Interface/Icons/INV_Misc_Note_02",
    boss = "Interface/TargetingFrame/UI-TargetingFrame-Skull",   -- the "??" boss skull, for a kill without a portrait or icon
    loot = "Interface/Icons/INV_Misc_Bag_10", mount = "Interface/Icons/Ability_Mount_RidingHorse",
    pet = "Interface/Icons/INV_Box_PetCarrier_01",
}
local KIND_GROUP = { spell = "growth", recipe = "growth", profession = "growth", skill = "growth", respec = "growth", level = "growth",
    loot = "gear", mount = "gear", pet = "gear", boss = "deeds", rep = "deeds", goal = "deeds", death = "deeds",
    zone = "places", dungeon = "places" }
-- which detail setting shows each kind of moment (J.Shows); kinds not listed always show
local TAG = {}   -- Journey constants (one table: the main chunk is out of locals)
TAG.KIND_SHOW = { spell = "spells", recipe = "recipes", profession = "professions", skill = "professions", respec = "respecs",
    mount = "mounts", pet = "mounts", boss = "bosses", death = "deaths", zone = "zones", dungeon = "zones", goal = "goals" }
TAG.LOOT_WORD = { [2] = "Uncommon", [3] = "Rare", [4] = "Epic", [5] = "Legendary" }
local FILTERS = { { "all", "All" }, { "growth", "Growth" }, { "gear", "Gear" }, { "deeds", "Deeds" }, { "places", "Places" }, { "notes", "Notes" } }
local FILTERS_NAME = {}
for _, f in ipairs(FILTERS) do FILTERS_NAME[f[1]] = f[2] end
local SHOW_BY = { { "level", "Level" }, { "day", "Day" }, { "zone", "Zone" } }
-- quality colours that stay readable on the paper tag
TAG.QUALITY = { [4] = { 0.42, 0.11, 0.69 }, [5] = { 0.70, 0.35, 0.0 }, [6] = { 0.55, 0.45, 0.2 }, [7] = { 0.0, 0.45, 0.6 } }
TAG.EDGE = { [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 } }

local filterOpen = false
local search = Persist(CreateFrame("EditBox", nil, content))
search:SetAutoFocus(false)
search:SetFontObject(FONTS.small)
search:SetHeight(20)
search.hint = search:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
search.hint:SetFontObject(FONTS.small)
search.hint:SetPoint("LEFT", 2, 0)
search.hint:SetText("Search the journal")
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
-- one search field, placed on whichever page is open; each page keeps its own search
local openQuest = {}   -- quest rows opened to show their details
local Find = { queries = {} }   -- the search: one table, the main chunk is out of locals
-- The group for things the journal has no day, level or place for (from before it kept track): always last.
Find.OTHER = "\255other"
search:SetScript("OnTextChanged", function(self, typed)
    search.hint:SetShown(self:GetText() == "")
    if typed then Find.queries[Find.key or ""] = self:GetText(); UI.Render() end
end)
UI.journeySearch = search
function Find.Field(key, x, top, w, hint)
    if Find.key ~= key then Find.key = key; search:SetText(Find.queries[key] or "") end
    Box(x, top, w, 28, nil, nil, "Field")
    search:SetParent(content)
    search:ClearAllPoints()
    search:SetPoint("TOPLEFT", x + 10, top - 4)
    search:SetWidth(w - 20)
    local ink = Ink("body"); search:SetTextColor(ink[1], ink[2], ink[3]); Shadow(search)
    Style(search.hint, "dim")
    search.hint:SetText(hint or "Search")
    search.hint:SetShown(search:GetText() == "")
    search:Show()
end
function Find.Query() return (Find.queries[Find.key or ""] or ""):lower() end
-- true when the search is empty or any of the texts contains it
function Find.Match(...)
    local q = Find.Query()
    if q == "" then return true end
    for i = 1, select("#", ...) do
        local t = select(i, ...)
        if type(t) == "string" and t:lower():find(q, 1, true) then return true end
    end
    return false
end

-- A switch of options in one chip, the active one in gold; returns its width.
local function Switch(options, active, x, top, onPick)
    local labels, widths, total = {}, {}, 6
    for i, o in ipairs(options) do
        labels[i] = Text(o[2], "small", 0, 0, true)
        widths[i] = labels[i]:GetStringWidth() + 24
        total = total + widths[i] + 2
    end
    Box(x, top, total, 28, nil, nil, "Chip")
    local cx = x + 3
    for i, o in ipairs(options) do
        labels[i]:SetPoint("TOPLEFT", cx + 12, top - 8)
        if o[1] == active then
            labels[i]:Hide()
            Chip(o[2], cx, top - 3, "Badge"):SetSize(widths[i], 22)
        end
        Hotspot(cx, top - 3, widths[i], 22, function() onPick(o[1]) end)
        cx = cx + widths[i] + 2
    end
    return total
end
local function LinkSpot(x, top, w, h, link)
    local b = Hotspot(x, top, w, h, function() if SetItemRef then SetItemRef(link, link, "LeftButton") end end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
end

local function Where(e)
    local w = e.subzone and e.zone and e.subzone ~= e.zone and (e.subzone .. ", " .. e.zone) or e.zone or "the road"
    return e.level and ("%s  ·  level %d"):format(w, e.level) or w
end

-- A paper tag with an item on it, tied on with a bit of twine; returns its height.
local function LootTag(x, top, find, from)
    local w = math.min(CW - x, 360)
    local icon = find.icon or KIND_ICON.loot
    local name = Text(find.link or find.text or "?", "body", x + 72, 0, true)
    name:SetPoint("TOPLEFT", x + 72, top - 10)
    name:SetWidth(w - 90); name:SetWordWrap(false)
    local c = TAG.QUALITY[find.quality or 4] or TAG.QUALITY[4]
    name:SetText((find.link or ""):gsub("|c[^|]+(|H.-|h.-|h)|r", "%1"):gsub("|H.-|h(.-)|h", "%1"))
    name:SetTextColor(c[1], c[2], c[3]); name:SetShadowOffset(0, 0)
    local kind = (find.itemKind or find.kind) and ((find.quality == 5 and "Legendary " or "Epic ") .. (find.itemKind or find.kind)) or (find.quality == 5 and "Legendary find" or "Epic find")
    local sub = Text(kind .. ((from or find.from) and ("  ·  from " .. (from or find.from)) or ""), "small", x + 72, 0, true)
    sub:SetPoint("TOPLEFT", x + 72, top - 30)
    sub:SetWidth(w - 90); sub:SetWordWrap(false)
    sub:SetTextColor(0.37, 0.27, 0.15); sub:SetShadowOffset(0, 0)
    local h = 54
    Box(x + 24, top, w - 24, h, nil, nil, "Tag")
    local str = Next("twine", function() return content:CreateTexture(nil, "BACKGROUND", nil, 5) end)
    str:SetTexture(KitFile("String")); str:SetSize(40, 20); str:SetPoint("TOPLEFT", x, top - h / 2 + 10)
    local edge = Next("qedge", function() return content:CreateTexture(nil, "ARTWORK", nil, 1) end)
    local q = TAG.EDGE[find.quality or 4] or TAG.EDGE[4]
    edge:SetColorTexture(q[1], q[2], q[3], 1); edge:SetSize(36, 36); edge:SetPoint("TOPLEFT", x + 30, top - 9)
    local ic = Next("tagicon", function() return content:CreateTexture(nil, "ARTWORK", nil, 2) end)
    ic:SetTexture(icon); ic:SetTexCoord(0.08, 0.92, 0.08, 0.92); ic:SetSize(32, 32); ic:SetPoint("TOPLEFT", x + 32, top - 11)
    if find.link then LinkSpot(x + 24, top, w - 24, h, find.link) end
    return h
end

local function Keepsake(x, e, sameRun)   -- sameRun: the other first kills of the same run, drawn in the same card
    local top, w = y, CW - x
    if e.note then
        Scrap(x, e.note)
        return
    end
    if e.kind == "loot" then
        y = top - LootTag(x, top, e) - 12
        return
    end
    if e.kind == "rep" then
        local seal = Next("seal2", function() return content:CreateTexture(nil, "ARTWORK", nil, 1) end)
        seal:SetTexture(KitFile("Seal")); seal:SetSize(64, 64); seal:SetPoint("TOPLEFT", x + 14, top - 10)
        local crest = Next("crest", function() return content:CreateTexture(nil, "ARTWORK", nil, 2) end)
        crest:SetTexture(KIND_ICON.rep); crest:SetTexCoord(0.1, 0.9, 0.1, 0.9); crest:SetSize(26, 26); crest:SetPoint("TOPLEFT", x + 33, top - 29)
        Text(("%s now counts you as"):format(e.faction or "A faction"), "small", x + 92, 0, true):SetPoint("TOPLEFT", x + 92, top - 16)
        Text(e.standing or "", "keep", x + 92, 0, true):SetPoint("TOPLEFT", x + 92, top - 34)
        Text(J.Date(e.t), "ink", 0, 0, true):SetPoint("TOPLEFT", x + w - 60, top - 14)
        Box(x, top, w, 84)
        y = top - 84 - 12
        return
    end
    if e.kind == "boss" then
        -- one card under one ribbon for every boss of the run (sameRun: the rest of them), newest first
        local bosses = { e }
        for _, b in ipairs(sameRun or {}) do bosses[#bosses + 1] = b end
        top = top - 12   -- room for the ribbon above the card
        local ribbonText = Text(e.instance or "A victory", "chapter", 0, 0, true)
        local rw = math.max(200, ribbonText:GetStringWidth() + 70)
        local rx = x + (w - rw) / 2
        ribbonText:SetPoint("TOPLEFT", rx + (rw - ribbonText:GetStringWidth()) / 2, top + 7)
        ribbonText:SetTextColor(1, 0.89, 0.66); ribbonText:SetShadowColor(0.2, 0.03, 0.01, 1); ribbonText:SetShadowOffset(1, -1)
        ribbonText:SetDrawLayer("OVERLAY", 7)
        for i, part in ipairs({ { 0, 24 / 256 }, { 24 / 256, 232 / 256 }, { 232 / 256, 1 } }) do
            local t = Next("ribbon" .. i, function() return content:CreateTexture(nil, "OVERLAY", nil, 1) end)
            t:SetTexture(KitFile("Ribbon")); t:SetTexCoord(part[1], part[2], 0, 1)
            t:SetHeight(30)
            if i == 1 then t:SetWidth(24); t:SetPoint("TOPLEFT", rx, top + 12)
            elseif i == 2 then t:SetWidth(rw - 48); t:SetPoint("TOPLEFT", rx + 24, top + 12)
            else t:SetWidth(24); t:SetPoint("TOPLEFT", rx + rw - 24, top + 12) end
        end
        local h = 22
        for n, b in ipairs(bosses) do
            local bt = top - h
            if n > 1 then
                local rule = Next("line", function() return content:CreateTexture(nil, "ARTWORK") end)
                local c = Ink("dim"); rule:SetColorTexture(c[1], c[2], c[3], 0.25)
                rule:SetSize(w - 28, 1); rule:SetPoint("TOPLEFT", x + 14, bt + 6)
            end
            -- kills recorded without an icon take their dungeon's (known once you have been inside since)
            local dicon = b.instance and H.dungeons[b.instance] and H.dungeons[b.instance].icon
            Ring(x + 16, bt, 52, nil, true, b.icon or dicon or KIND_ICON.boss, b.portrait, b.model)
            Text(b.boss or b.text, "keep", x + 84, 0, true):SetPoint("TOPLEFT", x + 84, bt - 4)
            local bits = { b.first and "First kill" or "Another kill" }
            if (b.kills or 1) > 1 then bits[#bits + 1] = ("killed %d times since"):format(b.kills - 1) end
            Text(table.concat(bits, "  ·  "), "small", x + 84, 0, true):SetPoint("TOPLEFT", x + 84, bt - 32)
            Text(n == 1 and J.Date(b.t) or date("%H:%M", b.t), "ink", 0, 0, true):SetPoint("TOPLEFT", x + w - 60, bt - 2)
            h = h + 64
            for _, find in ipairs(b.loot or {}) do h = h + LootTag(x + 50, top - h, find, find.from) + 8 end
        end
        if #bosses > 1 then
            local foot = Text(("%d bosses down this run"):format(#bosses), "small", x + 16, 0, true)
            foot:SetPoint("TOPLEFT", x + 16, top - h - 2)
            h = h + 20
        end
        Box(x, top, w, h + 4)
        y = top - h - 4 - 12
        return
    end
end

-- The moments of one group: rows gather in ledger cards; keepsakes interrupt them.
local shownAll = {}   -- groups opened past their first rows
local function Body(list, x, timeOnly, key)
    -- a very long group shows its newest rows first, with a link for the rest
    local LIMIT = 120
    if key and #list > LIMIT and not shownAll[key] then
        local cut = {}
        for i = 1, LIMIT do cut[i] = list[i] end
        Body(cut, x, timeOnly)
        Link(("Show all %d"):format(#list), 0, y + 4, function() shownAll[key] = true; UI.Render() end)
        Gap(18)
        return
    end
    local cardTop, rows = nil, 0
    local function Close()
        if cardTop then Gap(3); Box(x, cardTop, CW - x, cardTop - y); Gap(10); cardTop, rows = nil, 0 end
    end
    local i = 1
    while i <= #list do
        local e = list[i]
        if e.note or e.keep then
            Close()
            -- first kills from the same run that follow each other share one card
            local run
            if e.kind == "boss" then
                run = {}
                while list[i + 1] and list[i + 1].kind == "boss" and list[i + 1].keep and list[i + 1].instance == e.instance
                    and math.abs((list[i + 1].t or 0) - (e.t or 0)) < 4 * 3600 do
                    i = i + 1; run[#run + 1] = list[i]
                end
            end
            Keepsake(x, e, run)
        else
            if not cardTop then cardTop = y; Gap(3) end
            local top = y
            if rows > 0 then
                local rule = Next("line", function() return content:CreateTexture(nil, "ARTWORK") end)
                local c = Ink("dim"); rule:SetColorTexture(c[1], c[2], c[3], 0.25)
                rule:SetSize(CW - x - 28, 1); rule:SetPoint("TOPLEFT", x + 14, top + 1)
            end
            Ring(x + 12, top - 7, 30, nil, false, e.icon or KIND_ICON[e.kind] or EVENT_ICON[e.kind] or EVENT_ICON.zone, e.portrait, e.model)
            local title = Text(e.link or e.text, "body", x + 54, 70, true)
            title:SetPoint("TOPLEFT", x + 54, top - 6)
            title:SetWidth(CW - x - 54 - 70)
            local subText = e.sub or Where(e)
            if e.kind == "boss" and (e.kills or 1) > 1 then subText = ("Killed %d times  ·  %s"):format(e.kills, subText) end
            local sub = Text(subText, "small", x + 54, 70, true)
            sub:SetPoint("TOPLEFT", x + 54, top - 9 - title:GetStringHeight())
            sub:SetWidth(CW - x - 54 - 70); sub:SetWordWrap(false)
            local when = Text(date(timeOnly and "%H:%M" or "%b %d", e.t), "ink", 0, 0, true)
            when:SetWidth(56); when:SetJustifyH("RIGHT"); when:SetPoint("TOPLEFT", CW - 70, top - 12)
            y = top - math.max(44, title:GetStringHeight() + sub:GetStringHeight() + 16)
            rows = rows + 1
        end
        i = i + 1
    end
    Close()
end

-- Bláto Journal: your own path, under the party's part of the Journey page (RenderJourney below)
function BJ.RenderMyPath()
    local levels = {}
    for l in pairs(H.levels) do levels[#levels + 1] = l end
    table.sort(levels, function(a, b) return a > b end)

    local who = Who()
    Text(("%s%s%slevel %d. A journal kept since %s."):format(J.PlayerName(), who ~= "" and (", " .. who) or "", ", ", J.Level(), J.Date(H.started)), "ink")
    Gap(6)
    if #levels == 0 then Text("The first page is still blank. Go and explore.", "ink") return end

    -- controls: show by, search, filter
    local by = DB.journeyBy or "level"
    local filter = DB.journeyFilter or "all"
    local top = y
    local sw = Switch(SHOW_BY, by, 0, top, function(k) DB.journeyBy = k; UI.Render() end)
    local fw = 78
    local sx = sw + 10
    Find.Field("journey", sx, top, CW - sx - fw - 10, "Search the journal")
    -- the Filter button: a chip like the switch (gold while the filters are open, or one is in use)
    local label = filter ~= "all" and (FILTERS_NAME[filter] or filter) or "Filter"
    local lit = filterOpen or filter ~= "all"
    Box(CW - fw, top, fw, 28, nil, nil, lit and "Badge" or "Chip")
    local fl = Text(label, "small", 0, 0, true)
    fl:SetWidth(fw); fl:SetJustifyH("CENTER"); fl:SetPoint("TOPLEFT", CW - fw, top - 8)
    if lit then fl:SetTextColor(0.16, 0.09, 0.02); fl:SetShadowOffset(0, 0) end
    Hotspot(CW - fw, top, fw, 28, function() filterOpen = not filterOpen; UI.Render() end, "Show only some kinds of moments")
    y = top - 36
    if filterOpen then
        local cx = 0
        for _, f in ipairs(FILTERS) do
            local c = Chip(f[2], cx, y, f[1] == filter and "Badge" or nil)
            Hotspot(cx, y, c:GetWidth(), 20, function() DB.journeyFilter = f[1]; UI.Render() end)
            cx = cx + c:GetWidth() + 6
        end
        y = y - 30
    end
    Gap(6)

    -- the moments that pass the filter and the search, newest first
    local q = Find.Query()
    local lootMin, repMin, keepsakes = J.Shows("lootMin") or 4, J.Shows("repMin"), J.Shows("keepsakes")
    local function Pass(e)
        -- the detail settings: what this journal shows at all
        if e.kind and TAG.KIND_SHOW[e.kind] and not J.Shows(TAG.KIND_SHOW[e.kind]) then return false end
        if e.kind == "rep" and repMin == "honored" and not e.keep then return false end
        if e.kind == "loot" and (e.quality or 4) < lootMin then return false end
        if filter ~= "all" then
            if e.note then if filter ~= "notes" then return false end
            elseif KIND_GROUP[e.kind] ~= filter then return false end
        end
        if q == "" then return true end
        local hay = ((e.note and e.note.text or e.text or "") .. " " .. (e.sub or "") .. " " .. (e.zone or "") .. " " .. (e.subzone or "")):lower()
        return hay:find(q, 1, true) ~= nil
    end
    local items = {}
    for _, e in ipairs(H.events) do
        if e.kind ~= "goalset" and Pass(e) then
            items[#items + 1] = keepsakes and e or setmetatable({ keep = false }, { __index = e })
        end
    end
    -- finer loot (below epic) from the loot log, when the journal is set to show it
    if lootMin < 4 then
        for _, l in ipairs(H.loot or {}) do
            if l.quality and l.quality < 4 then
                local e = { t = l.t, kind = "loot", text = "Found " .. (l.link or "?"), link = l.link, icon = l.icon, quality = l.quality,
                    zone = l.zone, subzone = l.subzone, level = l.level,
                    sub = ("%s%s%s"):format(TAG.LOOT_WORD[l.quality] or "", l.itemKind and (" " .. l.itemKind) or "", l.from and ("  ·  from " .. l.from) or "") }
                if Pass(e) then items[#items + 1] = e end
            end
        end
    end
    for _, n in ipairs(H.notes) do
        local e = { t = n.t, note = n, level = n.level, zone = n.zone, subzone = n.subzone }
        if n.pinned and Pass(e) then items[#items + 1] = e end
    end
    table.sort(items, function(a, b) return a.t > b.t end)
    if #items == 0 and (q ~= "" or filter ~= "all") then
        Text("Nothing in the journal matches that.", "ink")
        return
    end

    local searching = q ~= "" or filter ~= "all"
    if by == "day" or by == "zone" then
        local groups, byKey = {}, {}
        for _, e in ipairs(items) do
            local key = by == "day" and date("%Y%m%d", e.t) or (e.zone or Find.OTHER)
            local g = byKey[key]
            if not g then
                g = { key = key, title = by == "day" and (date("%A, %B ", e.t) .. tonumber(date("%d", e.t))) or (key == Find.OTHER and "Other" or key), list = {} }
                byKey[key] = g; groups[#groups + 1] = g
            end
            table.insert(g.list, e)
        end
        for i, g in ipairs(groups) do if g.key == Find.OTHER then table.remove(groups, i); groups[#groups + 1] = g; break end end
        -- only the newest few groups start open: a long journal would otherwise draw thousands of rows
        for gi, g in ipairs(groups) do
            if Header("journey:" .. by .. ":" .. g.key, g.title, J.Count(#g.list, "moment"), gi > 3 and not searching) then
                Body(g.list, 0, by == "day", by .. g.key)
            end
        end
        return
    end

    -- by level: chapters along a timeline; the current level and the one before start open
    local byLevel = {}
    for _, e in ipairs(items) do if e.level then byLevel[e.level] = byLevel[e.level] or {}; table.insert(byLevel[e.level], e) end end
    local lineTop = y - 20
    local TX = 58
    DB.collapsed = DB.collapsed or {}
    for _, l in ipairs(levels) do
        local r = H.levels[l]
        local list = byLevel[l] or {}
        if not (searching and #list == 0) then
            local zone = J.MainZone(r) or (l == J.Level() and J.Zone()) or "the road"
            local key = "level:" .. l
            local closed = DB.collapsed[key]
            if closed == nil then closed = DB.foldChapters ~= false and l < J.Level() - 1 end
            if searching then closed = false end
            local toggle = function() DB.collapsed[key] = not closed; UI.Render() end
            local ctop = y
            if closed then
                Ring(5, ctop - 4, 32, tostring(l), false)
                local fs = Text(zone, "chapter", TX, 0, true)
                fs:SetPoint("TOPLEFT", TX, ctop - 10)
                fs:SetWidth(200); fs:SetWordWrap(false)
                local meta = Text(("%s  ·  %s"):format(J.Count(r.kills, "kill"), J.Count(#list, "moment")), "small", TX + 210, 0, true)
                meta:SetPoint("TOPLEFT", TX + 210, ctop - 14)
                Text(J.Dur(r.time), "small", CW - 72, 0, true):SetPoint("TOPLEFT", CW - 72, ctop - 14)
                Text("+", "gold", CW - 16, 0, true):SetPoint("TOPLEFT", CW - 14, ctop - 10)
                Hotspot(0, ctop, CW, 40, toggle, "Open this chapter")
                y = ctop - 44
            else
                Ring(0, ctop, 42, tostring(l), true)
                local title = Text(("Chapter %d  ·  %s"):format(l, zone), "chapter", TX, 30, true)
                title:SetPoint("TOPLEFT", TX, ctop - 4)
                if l == J.Level() then Chip("NOW", TX + title:GetStringWidth() + 12, ctop - 5, "Badge") end
                Text("–", "gold", CW - 16, 0, true):SetPoint("TOPLEFT", CW - 14, ctop - 4)
                Hotspot(0, ctop, CW, 28, toggle)
                y = ctop - 30
                Text(("%s%s  ·  %s  ·  %s%s"):format(J.Dur(r.time), l == J.Level() and " so far" or "", J.Count(r.kills, "kill"),
                    J.Count(r.quests, "quest"), r.deaths > 0 and ("  ·  " .. J.Count(r.deaths, "death")) or ""), "small", TX)
                Gap(8)
                if #list == 0 then Text("A quiet chapter.", "ink", TX) end
                Body(list, TX, nil, "level" .. l)
                y = math.min(y, ctop - 48)
                Gap(6)
            end
        end
    end
    VLine(20, lineTop, y + 20)
end

-- Bláto Journal: the Journey page is about the three of you first: time, quests and dungeons together (runs,
-- clears, bosses) and the firsts you shared. Your own path follows, as the journal kept it before.
BJ.DUNGEON_ICON = "Interface/Icons/INV_Misc_Key_03"
local function RenderJourney()
    BarButtons({})
    local t = J.Together()
    if not t then
        PageHead("Bláto", "Group up with your two friends: what the three of you do together is written here.")
    else
        PageHead("Bláto", ("%s, %s and %s. Together since %s."):format(J.PlayerName(), t.a.name, t.b.name, J.Date(t.since)))
        Tiles({
            { "time", J.Dur(t.time), "all three grouped" },
            { "Interface/Icons/INV_Scroll_03", tostring(#t.quests), "quests together" },
            { BJ.DUNGEON_ICON, tostring(t.runs), "dungeon runs" },
            { "kills", tostring(t.cleared), "dungeons cleared" },
        })

        if Header("together:dungeons", "Dungeons together", #t.dungeons > 0 and tostring(#t.dungeons) or nil) then
            if #t.dungeons == 0 then Text("No dungeon run with all three of you yet.", "ink") end
            for _, d in ipairs(t.dungeons) do
                local top, h = y, 62
                Box(0, top, CW, h)
                Hotspot(0, top, CW, h, function() UI.OpenPlace("dungeon:" .. d.name) end, "Open " .. d.name)
                Icon(d.icon or BJ.DUNGEON_ICON, 12, top - 13, 36)
                local title = Text(d.name, "chapter", 58, 0, true)
                title:SetPoint("TOPLEFT", 58, top - 8)
                if d.cleared > 0 then Chip("CLEARED", 58 + title:GetStringWidth() + 10, top - 9, "Badge") end
                local bosses = {}
                for n in pairs(d.bosses) do bosses[#bosses + 1] = n end
                table.sort(bosses)
                local s1 = Text(("%s together, %d cleared  ·  first %s"):format(J.Count(#d.runs, "run"), d.cleared, J.Date(d.first)), "small", 58, 0, true)
                s1:SetPoint("TOPLEFT", 58, top - 32); s1:SetWidth(CW - 70); s1:SetWordWrap(false)
                local s2 = Text(#bosses > 0 and ("Bosses: " .. table.concat(bosses, ", ")) or "No boss down yet", "small", 58, 0, true)
                s2:SetPoint("TOPLEFT", 58, top - 46); s2:SetWidth(CW - 70); s2:SetWordWrap(false)
                y = top - h - 8
            end
        end

        local moments = {}
        for _, f in ipairs({ t.a, t.b }) do
            if f.met then
                moments[#moments + 1] = { t = f.met, kind = "zone", icon = "Interface/Icons/Spell_Holy_PrayerOfHealing",
                    text = ("Met %s"):format(f.name), sub = ("%s  ·  level %d"):format(f.metSub or f.metZone or "?", f.metLevel or 0) }
            end
        end
        for _, d in ipairs(t.dungeons) do
            moments[#moments + 1] = { t = d.first, kind = "dungeon", icon = d.icon or BJ.DUNGEON_ICON,
                text = ("First time in %s together"):format(d.name), sub = ("level %d"):format(d.runs[1].level or 0) }
            local c = d.firstClear
            if c then
                moments[#moments + 1] = { t = c.t, kind = "dungeon", icon = "Interface/Icons/INV_Misc_Head_Dragon_01",
                    text = ("Cleared %s together"):format(d.name),
                    sub = ("%s inside  ·  %s"):format(J.Dur(c.time or 0), (J.Count(c.bosses or 0, "boss"):gsub("bosss", "bosses"))) }
            end
        end
        table.sort(moments, function(m1, m2) return m1.t > m2.t end)
        if Header("together:moments", "Done together", #moments > 0 and tostring(#moments) or nil) then
            if #moments == 0 then Text("The first shared page is still blank.", "ink") end
            Body(moments, 0)
        end

        local QUESTS_SHOWN = 25
        if Header("together:quests", "Quests together", tostring(#t.quests), true) then
            if #t.quests == 0 then Text("No quest done by all three of you yet.", "ink") end
            local list = {}
            for i = 1, math.min(#t.quests, QUESTS_SHOWN) do
                local q = t.quests[i]
                list[#list + 1] = { t = q.t, text = J.QuestName(q), icon = "Interface/GossipFrame/ActiveQuestIcon",
                    sub = ("%s  ·  level %d"):format(q.subzone or q.zone or "?", q.level or 0) }
            end
            Body(list, 0)
            if #t.quests > QUESTS_SHOWN then Text(("And %d more on the Quests page."):format(#t.quests - QUESTS_SHOWN), "ink") end
        end
    end
    if Header("journey:mine", "My own path") then BJ.RenderMyPath() end
end

-- Places -----------------------------------------------------------------------------------
-- A card per zone, largest share of your time first; a card opens that place's own page.
local openPlace   -- zone name whose page is open, or nil for the gallery
local function PlaceCard(x, top, w, h, name, r, total, isFirst)
    Box(x, top, w, h)
    local fs = Text(name, "chapter", x + 14, 0, true)
    fs:SetPoint("TOPLEFT", x + 14, top - 12)
    fs:SetWidth(w - 28); fs:SetWordWrap(false)
    local first = isFirst and "Where it began" or "First came here"
    Text(("%s %s, level %d"):format(first, J.Date(r.first), r.firstLevel or 0), "ink", x + 14, 0, true)
        :SetPoint("TOPLEFT", x + 14, top - 36)
    -- the bar shows corners explored where the game lists them; elsewhere this place's share of your time
    local ex, done = J.Explore(name), 0
    for _, c in ipairs(ex or {}) do if c.done then done = done + 1 end end
    Track(x + 14, top - 62, w - 90, ex and done / #ex or (total > 0 and r.time / total or 0))
    local label = Text(ex and ("%d / %d"):format(done, #ex) or J.Dur(r.time), "small", 0, 0, true)
    label:SetWidth(56); label:SetJustifyH("RIGHT"); label:SetPoint("TOPLEFT", x + w - 70, top - 60)
    local stats = Text(("%s%s  ·  %s"):format(ex and (J.Dur(r.time) .. "  ·  ") or "", J.Count(r.kills or 0, "kill"), J.Count(r.quests or 0, "quest")),
        "small", x + 14, 0, true)
    stats:SetPoint("TOPLEFT", x + 14, top - 76); stats:SetWidth(w - 28); stats:SetWordWrap(false)
    Hotspot(x, top, w, h, function() openPlace = name; UI.Render() end, "Open " .. name)
end

local function RenderPlaceList()
    BarButtons({})
    local list, total, earliest = {}, 0, nil
    for z, r in pairs(H.zones) do
        -- a dungeon has its own card below; one recorded as a place too (by an older version) is left out here
        if not H.dungeons[z] then
            local corners = {}
            for sub in pairs(r.subs or {}) do corners[#corners + 1] = sub end
            if Find.Match(z, table.concat(corners, " ")) then list[#list + 1] = { z, r } end
            total = math.max(total, r.time)
            if r.first and (not earliest or r.first < H.zones[earliest].first) then earliest = z end
        end
    end
    table.sort(list, function(a, b) return a[2].time > b[2].time end)
    local n = #list
    PageHead("Places", n == 0 and "Nowhere yet. The road is waiting." or
        ("%s so far, and the road goes on."):format(n == 1 and "One place" or (n .. " places")))
    Find.Field("places", 0, y, CW, "Search places and their corners")
    Gap(40)
    local w, h = math.floor((CW - 12) / 2), 98
    for i, it in ipairs(list) do
        local col = (i - 1) % 2
        local top = y - math.floor((i - 1) / 2) * (h + 12)
        PlaceCard(col * (w + 12), top, w, h, it[1], it[2], total, it[1] == earliest)
    end
    y = y - math.ceil(n / 2) * (h + 12)
    local dl = {}
    for name, d in pairs(H.dungeons) do dl[#dl + 1] = { name, d } end
    table.sort(dl, function(a, b) return a[2].first < b[2].first end)
    if Header("places:dungeons", "Dungeons", #dl > 0 and tostring(#dl) or nil) then
        if #dl == 0 then Text("None braved yet. Each dungeon gets a card of its own, with runs and time inside.", "ink") end
        for i, it in ipairs(dl) do
            local col = (i - 1) % 2
            local top = y - math.floor((i - 1) / 2) * 70
            Box(col * (w + 12), top, w, 60)
            local dname = it[1]
            Hotspot(col * (w + 12), top, w, 60, function() openPlace = "dungeon:" .. dname; UI.Render() end, "Open " .. dname)
            Icon(it[2].icon or "Interface/Icons/INV_Misc_Key_03", col * (w + 12) + 12, top - 12, 36)
            Text(it[1], "chapter", col * (w + 12) + 58, 0, true):SetPoint("TOPLEFT", col * (w + 12) + 58, top - 10)
            Text(("%s, %s inside. First %s."):format(J.Count(it[2].runs, "run"), J.Dur(it[2].time or 0), J.Date(it[2].first)), "small",
                col * (w + 12) + 58, 0, true):SetPoint("TOPLEFT", col * (w + 12) + 58, top - 34)
        end
        y = y - math.ceil(#dl / 2) * 70
    end
end

-- A dungeon in depth: the tally of your runs, the bosses you have beaten there, and each run with who came.
function Find.Dungeon(name)
    local d = H.dungeons[name]
    if not d then openPlace = nil; return RenderPlaceList() end
    BarButtons({})
    local crumb = Text("Places", "gold", 2, 0, true)
    local cw = crumb:GetStringWidth()
    Text("›  " .. name, "ink", cw + 10, 0, true):SetPoint("TOPLEFT", cw + 10, y - 4)
    Hotspot(0, y + 2, cw + 8, 24, function() openPlace = nil; UI.Render() end, "Back to all places")
    Gap(28)
    -- the bosses beaten here (first kills are moments; later kills are counted on them), and who came along
    local bosses, kills = {}, 0
    for i = #H.events, 1, -1 do
        local e = H.events[i]
        if e.kind == "boss" and e.instance == name then bosses[#bosses + 1] = e; kills = kills + (e.kills or 1) end
    end
    local companions = {}
    for fname, f in pairs(H.fellows or {}) do
        for _, r in pairs(f.runs or {}) do if r.name == name then companions[fname] = true end end
    end
    local nComp = 0
    for _ in pairs(companions) do nComp = nComp + 1 end
    local SW = 210
    local headTop = y
    PageHead(name, ("First came here %s. %s, %s inside."):format(J.Date(d.first), J.Count(d.runs or 0, "run"), J.Dur(d.time or 0)),
        SW + 20, nil, SW + 20)
    local rows = { { tostring(d.runs or 0), (d.runs or 0) == 1 and "run" or "runs" }, { J.Dur(d.time or 0), "inside" },
        { tostring(#bosses), #bosses == 1 and "boss beaten" or "bosses beaten" }, { tostring(nComp), nComp == 1 and "companion" or "companions" } }
    local sx, stop = CW - SW, headTop + 4
    local sh = 20 + #rows * 20
    local shadow = Next("scrapshadow", function() return content:CreateTexture(nil, "BACKGROUND", nil, 2) end)
    shadow:SetColorTexture(0, 0, 0, 0.28); shadow:SetSize(SW - 4, sh - 4); shadow:SetPoint("TOPLEFT", sx + 5, stop - 6)
    Box(sx, stop, SW, sh, nil, nil, "Paper")
    local tape = Next("tape", function() return content:CreateTexture(nil, "ARTWORK", nil, 3) end)
    tape:SetTexture(KitFile("Tape")); tape:SetSize(70, 16); tape:SetPoint("TOPLEFT", sx + SW / 2 - 35, stop + 8)
    for i, row in ipairs(rows) do
        local ry = stop - 10 - (i - 1) * 20
        local label = Text(row[2], "small", 0, 0, true)
        label:SetPoint("TOPLEFT", sx + 16, ry - 2); label:SetTextColor(0.37, 0.27, 0.15); label:SetShadowOffset(0, 0)
        local n = Text(row[1], "ink", 0, 0, true)
        n:SetWidth(70); n:SetJustifyH("RIGHT"); n:SetPoint("TOPLEFT", sx + SW - 86, ry)
        n:SetTextColor(0.14, 0.09, 0.04); n:SetShadowOffset(0, 0)
    end
    y = math.min(y, stop - sh - 16)

    if Header("dungeon:bosses", "Bosses", tostring(#bosses)) then
        if #bosses == 0 then Text("None beaten here yet.", "ink") end
        local list = {}
        for _, e in ipairs(bosses) do
            list[#list + 1] = { t = e.t, kind = "boss", text = e.boss or e.text, icon = e.icon, portrait = e.portrait, model = e.model,
                sub = (e.kills or 1) > 1 and ("First beaten %s  ·  %d kills"):format(J.Date(e.t), e.kills) or ("Beaten %s"):format(J.Date(e.t)) }
        end
        Body(list, 0)
    end
    local hist = d.history or {}
    if #hist > 0 and Header("dungeon:runs", "Runs", tostring(#hist)) then
        local list = {}
        for i = #hist, 1, -1 do
            local r = hist[i]
            local who = {}
            for fname, f in pairs(H.fellows or {}) do if f.runs and f.runs[tostring(r.t)] then who[#who + 1] = fname end end
            table.sort(who)
            list[#list + 1] = { t = r.t, kind = "dungeon", icon = d.icon or "Interface/Icons/INV_Misc_Key_03",
                text = ("Run %d  ·  %s inside  ·  %s"):format(i, J.Dur(r.time or 0), J.Count(r.bosses or 0, "boss"):gsub("bosss", "bosses")),
                sub = #who > 0 and ("With " .. table.concat(who, ", ")) or ("At level %d"):format(r.level or 0) }
        end
        Body(list, 0)
    end
end

-- One place in depth: its corners (subzones) with time spent, and the quests, notes and falls that happened there.
local function RenderPlace(zone)
    local r = H.zones[zone]
    if not r then openPlace = nil; return RenderPlaceList() end
    BarButtons({})
    -- breadcrumb: Places › this zone; the first part goes back
    local crumb = Text("Places", "gold", 2, 0, true)
    local cw = crumb:GetStringWidth()
    Text("›  " .. zone, "ink", cw + 10, 0, true):SetPoint("TOPLEFT", cw + 10, y - 4)
    Hotspot(0, y + 2, cw + 8, 24, function() openPlace = nil; UI.Render() end, "Back to all places")
    Gap(28)
    local first = r.first and J.Date(r.first) or "?"
    -- the place's tally is written on a scrap of paper taped beside the title
    local SW = 210
    local headTop = y
    PageHead(zone, ("First came here %s at level %d. %s here in all."):format(first, r.firstLevel or 0, J.Dur(r.time)), SW + 20, nil, SW + 20)
    local rows = {
        { tostring(r.kills or 0), "foes bested" },
        { tostring(r.quests or 0), "quests handed in", function()
            DB.questGroup = "zone"; DB.questView = "done"; DB.collapsed = DB.collapsed or {}; DB.collapsed["quests:zone:" .. zone] = false
            UI.Show("quests") end },
        { tostring(r.deaths or 0), (r.deaths or 0) == 1 and "fall" or "falls" },
    }
    local sx, stop = CW - SW, headTop + 4
    local sh = 20 + #rows * 20
    local shadow = Next("scrapshadow", function() return content:CreateTexture(nil, "BACKGROUND", nil, 2) end)
    shadow:SetColorTexture(0, 0, 0, 0.28); shadow:SetSize(SW - 4, sh - 4); shadow:SetPoint("TOPLEFT", sx + 5, stop - 6)
    Box(sx, stop, SW, sh, nil, nil, "Paper")
    local tape = Next("tape", function() return content:CreateTexture(nil, "ARTWORK", nil, 3) end)
    tape:SetTexture(KitFile("Tape")); tape:SetSize(70, 16); tape:SetPoint("TOPLEFT", sx + SW / 2 - 35, stop + 8)
    for i, row in ipairs(rows) do
        local ry = stop - 10 - (i - 1) * 20
        local label = Text(row[2], "small", 0, 0, true)
        label:SetPoint("TOPLEFT", sx + 16, ry - 2); label:SetTextColor(0.37, 0.27, 0.15); label:SetShadowOffset(0, 0)
        local n = Text(row[1], "ink", 0, 0, true)
        n:SetWidth(60); n:SetJustifyH("RIGHT"); n:SetPoint("TOPLEFT", sx + SW - 76, ry)
        n:SetTextColor(0.14, 0.09, 0.04); n:SetShadowOffset(0, 0)
        if row[3] then Hotspot(sx + 8, ry + 2, SW - 16, 20, row[3], "See them in Quests") end
    end
    y = math.min(y, stop - sh - 16)

    -- corners: the game's list for this zone (its Explore achievement) in two columns, explored with the time
    -- spent there and not yet explored; places without that list show the corners you have been to
    local subs, seen = {}, {}
    for name, sr in pairs(r.subs or {}) do subs[#subs + 1] = { name, sr }; seen[name] = true end
    for name, z in pairs(H.subzones or {}) do if z == zone and not seen[name] then subs[#subs + 1] = { name }; seen[name] = true end end
    local ex = J.Explore(zone)
    local notyet = {}
    if ex then
        local listed = {}
        for _, c in ipairs(ex) do
            listed[c.name] = true
            if c.done and not seen[c.name] then subs[#subs + 1] = { c.name }; seen[c.name] = true
            elseif not c.done and not seen[c.name] then notyet[#notyet + 1] = c.name end
        end
    end
    table.sort(subs, function(a, b)
        local ta, tb = a[2] and a[2].time or -1, b[2] and b[2].time or -1
        if ta ~= tb then return ta > tb end
        return a[1] < b[1]
    end)
    table.sort(notyet)
    local done = ex and (#ex - #notyet) or #subs
    local extra = ex and ("%d of %d explored"):format(done, #ex) or tostring(#subs)
    if Header("place:subs", "Corners of " .. zone, extra) then
        if #subs == 0 and #notyet == 0 then Text("No corners named yet. Wander a little and they appear here.", "ink") end
        if ex then Track(0, y + 2, CW, done / #ex); Gap(14) end
        local colW = #notyet > 0 and math.floor((CW - 26) / 2) or CW
        local function Row(x, top, name, on, time)
            local g = Next("gem", function() return content:CreateTexture(nil, "ARTWORK") end)
            g:SetTexture(KitFile(on and "Gem" or "GemOff"))
            local c = on and Ink("link") or Ink("dim")
            g:SetVertexColor(c[1], c[2], c[3], on and 1 or 0.7)
            g:SetSize(12, 12); g:SetPoint("TOPLEFT", x, top - 3)
            local fs = Text(name, on and "body" or "dim", x + 20, 0, true)
            fs:SetPoint("TOPLEFT", x + 20, top); fs:SetWidth(colW - 20 - (time and 56 or 0)); fs:SetWordWrap(false)
            if not on then fs:SetAlpha(0.85) end
            if time then
                local t = Text(J.Dur(time), "small", 0, 0, true)
                t:SetWidth(52); t:SetJustifyH("RIGHT"); t:SetPoint("TOPLEFT", x + colW - 56, top - 1)
            end
        end
        local top = y
        for i, it in ipairs(subs) do Row(0, top - (i - 1) * 24, it[1], true, it[2] and it[2].time) end
        if #notyet > 0 then
            local rx = colW + 26
            Text("Not yet explored", "ink", rx, 0, true):SetPoint("TOPLEFT", rx, top)
            for i, name in ipairs(notyet) do Row(rx, top - i * 24, name, false) end
        end
        y = top - math.max(#subs, #notyet > 0 and #notyet + 1 or 0) * 24 - 4
    end

    local quests = {}
    for i = #H.quests, 1, -1 do local q = H.quests[i]; if q.zone == zone and not q.archived then quests[#quests + 1] = q end end
    if Header("place:quests", "Quests handed in here", tostring(#quests)) then
        if #quests == 0 then Text("No quests handed in here yet.", "ink") end
        for _, q in ipairs(quests) do
            local top = y
            Text(J.Date(q.t), "ink", 0, 0, true):SetPoint("TOPLEFT", 0, top)
            Text(J.QuestName(q), "body", 58)
            Text(("%s%s"):format(q.subzone and q.subzone ~= zone and (q.subzone .. "  ·  ") or "", "level " .. (q.level or 0)), "small", 58)
            y = math.min(y, top - 36) - 6
            if q.questID then
                -- click: open this quest in Quests, found by its name and opened to its details
                local spot = Hotspot(0, top + 2, CW, top - y, function()
                    DB.questView, DB.questGroup = "done", "zone"
                    DB.collapsed = DB.collapsed or {}; DB.collapsed["quests:zone:" .. zone] = false
                    Find.queries.quests = J.QuestName(q); Find.key = nil
                    openQuest[q.id] = true
                    UI.Show("quests")
                end)
                spot:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                    if pcall(GameTooltip.SetHyperlink, GameTooltip, ("quest:%d:%d"):format(q.questID, q.level or 0)) then
                        GameTooltip:AddLine("Click to open in Quests", 0.6, 0.6, 0.6); GameTooltip:Show()
                    else GameTooltip:Hide() end
                end)
                spot:SetScript("OnLeave", GameTooltip_Hide)
            end
        end
    end

    local notes = {}
    for i = #H.notes, 1, -1 do local n = H.notes[i]; if n.zone == zone and not n.archived then notes[#notes + 1] = n end end
    if #notes > 0 and Header("place:notes", "Notes written here", tostring(#notes)) then
        for _, n in ipairs(notes) do
            local top = y
            Text(J.Date(n.t), "ink", 0, 0, true):SetPoint("TOPLEFT", 0, top)
            local fs = Text(n.text, "body", 58, 0, true)
            fs:SetPoint("TOPLEFT", 58, top)
            y = top - fs:GetStringHeight() - 4
            Text(J.NoteWhere(n), "small", 58)
            Gap(8)
        end
    end

    local moments = {}
    for i = #H.events, 1, -1 do local e = H.events[i]; if e.zone == zone and e.kind ~= "goalset" then moments[#moments + 1] = e end end
    if #moments > 0 and Header("place:moments", "What happened here", tostring(#moments)) then
        for _, e in ipairs(moments) do EventLine(0, EVENT_ICON[e.kind] or EVENT_ICON.zone, e.text, J.Date(e.t)) end
    end
end

local function RenderPlaces()
    if openPlace and openPlace:find("^dungeon:") then Find.Dungeon(openPlace:sub(9))
    elseif openPlace then RenderPlace(openPlace) else RenderPlaceList() end
end
function UI.OpenPlace(zone) openPlace = zone; UI.Show("places") end

-- Bláto Journal: no Goals page, its code is gone. Shift-clicked links still go into the note boxes.
-- Clients route shift-clicked links through different functions, so listen on every one that exists.
UI.linkBoxes = {}   -- note boxes that take shift-clicked links (added below)
local lastLink, lastLinkTime = nil, 0
local function OnLink(link)
    if type(link) ~= "string" then return end
    -- one click can arrive through two of the hooks below; insert it once
    local now = GetTime()
    if link == lastLink and now - lastLinkTime < 0.2 then return end
    for _, box in ipairs(UI.linkBoxes) do
        if box:HasFocus() then box:Insert(link); lastLink, lastLinkTime = link, now; return end
    end
end
if ChatEdit_InsertLink then hooksecurefunc("ChatEdit_InsertLink", OnLink) end
if ChatFrameUtil and ChatFrameUtil.InsertLink then hooksecurefunc(ChatFrameUtil, "InsertLink", OnLink) end
if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
        if not IsModifiedClick or IsModifiedClick("CHATLINK") then OnLink(link) end
    end)
end

-- Reminders -------------------------------------------------------------------------------
-- "Remind me" row under a note box: a trigger menu filled in from what you write, and "every time".
-- Once you pick something from the menu yourself, it stops following the text.
local function ReminderRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(26)
    row.label = row:CreateFontString(nil, "OVERLAY")
    row.label:SetPoint("LEFT", 0, 0)
    row.drop = Kit.Make("DropdownButton", row, "WowStyle1DropdownTemplate")
    row.drop:SetWidth(250)
    row.drop:SetPoint("LEFT", row.label, "RIGHT", 8, 0)
    row.every = Kit.Make("CheckButton", row, "UICheckButtonTemplate")
    row.every:SetSize(22, 22)
    row.every:SetPoint("LEFT", row.drop, "RIGHT", 10, 0)
    row.everyText = row:CreateFontString(nil, "OVERLAY")
    row.everyText:SetPoint("LEFT", row.every, "RIGHT", 2, 0)
    row.trigger, row.suggested, row.chosen = nil, nil, false
    function row:Options()
        local opts = { { nil, "No reminder" } }
        local s = self.suggested
        if s and (s.kind == "place" or (s.kind == "dungeon" and s.target)) then opts[#opts + 1] = { s, J.TriggerLabel(s) } end
        if self.trigger and (self.trigger.kind == "place" or self.trigger.target) and J.TriggerKey(self.trigger) ~= J.TriggerKey(s) then
            opts[#opts + 1] = { self.trigger, J.TriggerLabel(self.trigger) }
        end
        for _, kind in ipairs(J.TRIGGER_ORDER) do
            local t = { kind = kind }
            if kind == "level" then
                local cur = self.trigger and self.trigger.kind == "level" and self.trigger or s and s.kind == "level" and s
                t.level = cur and cur.level or J.Level() + 1
            end
            opts[#opts + 1] = { t, J.TriggerLabel(t) }
        end
        return opts
    end
    if row.drop.SetupMenu then
        row.drop:SetupMenu(function(_, root)
            for _, o in ipairs(row:Options()) do
                root:CreateRadio(o[2], function() return J.TriggerKey(row.trigger) == J.TriggerKey(o[1]) end,
                    function() row.trigger = o[1]; row.chosen = true; row:Update() end)
            end
        end)
    end
    function row:Update()
        if self.drop.GenerateMenu then self.drop:GenerateMenu() end
        self.every:SetShown(self.trigger ~= nil)
        self.everyText:SetShown(self.trigger ~= nil)
    end
    function row:Suggest(text)
        self.suggested = J.SuggestTrigger(text)
        if not self.chosen then self.trigger = self.suggested end
        self:Update()
    end
    function row:Reset(trigger, repeats)
        self.suggested, self.trigger, self.chosen = trigger, trigger, trigger ~= nil
        self.every:SetChecked(repeats and true or false)
        self:Update()
    end
    function row:Ink()
        Style(self.label, "dim"); self.label:SetText("Remind me:")
        Style(self.everyText, "small"); self.everyText:SetText("every time")
    end
    return row
end
-- Suggest from the text a moment after typing stops.
local function FollowText(box, row)
    local token = 0
    box:HookScript("OnTextChanged", function(self, user)
        token = token + 1
        local mine = token
        C_Timer.After(0.3, function() if mine == token then row:Suggest(self:GetText()) end end)
    end)
end

-- Notes ------------------------------------------------------------------------------------
-- A writing area at the top of the page, then the entries like a diary.
local composer = Persist(CreateFrame("Button", nil, content))
composer.bg = composer:CreateTexture(nil, "BACKGROUND")
composer.bg:SetAllPoints()
local noteEdit = CreateFrame("EditBox", nil, composer)
noteEdit:SetMultiLine(true)
noteEdit:SetAutoFocus(false)
noteEdit:SetMaxLetters(600)
noteEdit:SetFontObject(FONTS.body)
noteEdit:SetPoint("TOPLEFT", 20, -54)
noteEdit:SetPoint("TOPRIGHT", -20, -54)
noteEdit:SetHeight(60)
local placeholder = composer:CreateFontString(nil, "OVERLAY")
placeholder:SetPoint("TOPLEFT", 21, -54)
-- the sheet is a kit card; the writing sits in a kit field between the controls row and the Save row
composer.bg:Hide()
composer.frameArt = UI.BuildCard(composer)
composer.fieldAnchor = composer:CreateTexture(nil, "BACKGROUND")
composer.fieldAnchor:SetPoint("TOPLEFT", 12, -44)
composer.fieldAnchor:SetPoint("BOTTOMRIGHT", -12, 42)
composer.fieldArt = KitPiece(composer, composer.fieldAnchor, "BORDER", 4, nil, "Field")
composer.pinText = composer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
composer.pinText:SetText("Pin to Journey")
composer.pinText:SetPoint("TOPRIGHT", -14, -15)
composer.pin = Kit.Make("CheckButton", composer, "UICheckButtonTemplate")
composer.pin:SetSize(22, 22)
composer.pin:SetPoint("RIGHT", composer.pinText, "LEFT", -2, 0)
composer.save = Kit.Make("Button", composer, "UIPanelButtonTemplate")
composer.save:SetSize(110, 22)
composer.save:SetPoint("BOTTOMRIGHT", -12, 12)
-- Bláto Journal: the note goes to the party's shared notepad too (Together.lua)
composer.shareText = composer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
composer.shareText:SetText("Share with the party")
composer.shareText:SetPoint("RIGHT", composer.save, "LEFT", -12, 0)
composer.share = Kit.Make("CheckButton", composer, "UICheckButtonTemplate")
composer.share:SetSize(22, 22)
composer.share:SetPoint("RIGHT", composer.shareText, "LEFT", -2, 0)
composer.hint = composer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
composer.hint:SetPoint("BOTTOMLEFT", 14, 17)
composer.hint:SetText("Enter saves, Shift+Enter: new line.")
composer:SetScript("OnClick", function() noteEdit:SetFocus() end)
table.insert(UI.linkBoxes, noteEdit)
local noteRow = Persist(ReminderRow(content))
FollowText(noteEdit, noteRow)
local editingNote
local function SaveComposer()
    local text = noteEdit:GetText()
    local trigger, repeats = noteRow.trigger, noteRow.every:GetChecked()
    local pinned = composer.pin:GetChecked() and true or false
    if editingNote then
        local n = editingNote
        editingNote = nil
        J.EditNote(n.id, text)
        if J.TriggerKey(trigger) ~= J.TriggerKey(n.trigger) or (repeats and true or nil) ~= n.repeats then
            J.SetReminder(n, trigger, repeats)
        end
    elseif text:match("%S") and J.AddNote(text, trigger, repeats, pinned, composer.share:GetChecked() and true or false) then
        UI.PlaySound(DB.sound.note)
    end
    noteEdit:SetText("")
    noteEdit:ClearFocus()
    noteRow:Reset(nil)
    composer.pin:SetChecked(DB.autoPin)
    composer.share:SetChecked(DB.shareNotes ~= false)
    UI.Render()
end
composer.save:SetScript("OnClick", SaveComposer)
noteEdit:SetScript("OnEnterPressed", function(self)
    if IsShiftKeyDown() then self:Insert("\n") else SaveComposer() end
end)
noteEdit:SetScript("OnEscapePressed", function(self)
    if editingNote then editingNote = nil; self:SetText(""); noteRow:Reset(nil); UI.Render() end
    self:ClearFocus()
end)
-- HookScript, not SetScript: the reminder suggestion also listens to this box (FollowText above)
noteEdit:HookScript("OnTextChanged", function(self) placeholder:SetShown(self:GetText() == "") end)

local function StartEdit(n)
    editingNote = n
    noteEdit:SetText(n.text)
    noteRow:Reset(n.trigger, n.repeats)
    UI.Render()
    noteEdit:SetFocus()
end

-- Diary layout: reminders pinned on top with an accent line, then notes grouped by day, with the time in a
-- column on the left. Edit and Delete only appear while the mouse is over a note.
-- entries: hover areas on the page this render (declared with Entry, above)
local TIME_COL = 54
Entry = function(top, links, hide)   -- hide: shown only while the links are not (they take their place)
    local e = Next("entry", function() return CreateFrame("Frame", nil, content) end)   -- no mouse: only for IsMouseOver
    e:SetPoint("TOPLEFT", 0, top + 2)
    e:SetSize(CW, math.max(1, top - y + 6))
    e.links, e.hide = links, hide
    for _, l in ipairs(links) do l:Hide() end
    entries[#entries + 1] = e
end
local hoverTick = 0
win:HookScript("OnUpdate", function(_, dt)
    hoverTick = hoverTick + dt
    if hoverTick < 0.05 then return end
    hoverTick = 0
    for _, e in ipairs(entries) do
        if e:IsShown() then
            local over = e:IsMouseOver()
            for _, l in ipairs(e.links) do l:SetShown(over) end
            for _, r in ipairs(e.hide or {}) do r:SetShown(not over) end
        end
    end
end)
local function DayTitle(t)
    return date("%A, %B ", t) .. tonumber(date("%d", t))
end

local function RenderNotes()
    if archiveOpen.note then return RenderArchive("note") end
    BarButtons({})
    local titleTop = y
    local here = { zone = J.Zone(), subzone = J.SubZone() }
    PageHead("Notes", editingNote and "Editing a note from " .. J.NoteWhere(editingNote) or ("Here: %s"):format(J.NoteWhere(here)))
    ArchiveLink("note", titleTop)
    -- you write on a sheet of paper: parchment and dark ink whatever the page style
    composer:SetPoint("TOPLEFT", 0, y)
    composer:SetSize(CW, 164)
    composer.frameArt(); composer.fieldArt()
    local body, dim = Ink("body"), Ink("dim")
    noteEdit:SetTextColor(body[1], body[2], body[3])
    Shadow(noteEdit)
    Style(placeholder, "dim")
    placeholder:SetTextColor(dim[1], dim[2], dim[3], 0.8)
    placeholder:SetText("Write about this place, a reminder for later, or shift-click an item into it...")
    placeholder:SetShown(noteEdit:GetText() == "")
    composer:Show()
    for _, fs in ipairs({ composer.pinText, composer.hint, composer.shareText }) do fs:SetTextColor(dim[1], dim[2], dim[3]); Shadow(fs) end
    composer.save:SetText(editingNote and "Save changes" or "Save note")
    composer.pin:SetShown(not editingNote)
    composer.pinText:SetShown(not editingNote)
    composer.share:SetShown(not editingNote)
    composer.shareText:SetShown(not editingNote)
    if not editingNote and noteEdit:GetText() == "" then
        composer.pin:SetChecked(DB.autoPin)
        composer.share:SetChecked(DB.shareNotes ~= false)
    end
    -- the reminder picker sits on the sheet, under the writing lines
    noteRow:SetParent(composer)
    noteRow:Ink()
    for _, fs in ipairs({ noteRow.label, noteRow.everyText }) do fs:SetTextColor(dim[1], dim[2], dim[3]); Shadow(fs) end
    noteRow:ClearAllPoints()
    noteRow:SetPoint("TOPLEFT", composer, "TOPLEFT", 14, -8)
    noteRow:SetWidth(CW - 180)
    noteRow:Show()
    noteRow:Update()
    Gap(174)
    if editingNote then
        Link("Cancel editing", 0, y + 2, function() editingNote = nil; noteEdit:SetText(""); noteRow:Reset(nil); UI.Render() end)
        Gap(16)
    end

    Find.Field("notes", 0, y, CW, "Search notes")
    Gap(40)

    -- Bláto Journal: the party's shared notepad (Together.lua), your shared notes and your friends', newest first
    local T = ns.Together
    if T then
        T.AskNotes()
        local shared = {}
        for _, s in ipairs(T.SharedNotes()) do
            if Find.Match(s.note.text, s.note.zone, s.note.subzone, s.note.author) then shared[#shared + 1] = s end
        end
        if Header("notes:shared", "Shared notepad", tostring(#shared)) then
            if #shared == 0 then Text("Nothing shared yet. Tick \"Share with the party\" and your friends can read it too.", "ink") end
            for i = 1, math.min(#shared, 30) do
                local s, n, top = shared[i], shared[i].note, y
                local who = s.mine and "You" or ((n.author or "?"):match("^(%S+)") or n.author)
                Text(who, "ink", 0, 0, true):SetTextColor(unpack(Ink("head")))
                Text(date("%b %d", s.t), "small", 0, 0, true):SetPoint("TOPLEFT", 0, top - 17)
                Text(n.text, "body", TIME_COL + 10, 100)
                Text(("%s  ·  level %d"):format(s.mine and J.NoteWhere(n) or (n.zone or "Somewhere"), n.level or 0), "small", TIME_COL + 10, 100)
                Entry(top, { s.mine and Link("Unshare", 0, top, function() T.SetShared(n.id, false) end)
                    or Link("Hide", 0, top, function() T.HidePartyNote(n.key) end) })
                Gap(12)
            end
        end
    end

    local pending, others = {}, {}
    for i = #H.notes, 1, -1 do
        local n = H.notes[i]
        if n.archived then -- in the archive (a pinned one still shows on the Journey page)
        elseif not Find.Match(n.text, n.zone, n.subzone) then -- not what you searched for
        elseif n.trigger and not n.done then pending[#pending + 1] = n else others[#others + 1] = n end
    end

    if #pending > 0 then
        Header("notes:reminders", "Waiting to remind you", tostring(#pending))
        for _, n in ipairs(pending) do
            local top = y
            Ring(10, top - 8, 30, nil, true, "Interface/Icons/INV_Misc_PocketWatch_01")
            y = top - 8
            Text(J.TriggerLabel(n.trigger) .. (n.repeats and "  ·  every time" or ""), "ink", 52, 100)
            Text(n.text, "body", 52, 100)
            local fired = n.firedAt and ("  ·  last reminded " .. date("%b %d, %H:%M", n.firedAt)) or ""
            Text(J.NoteWhere(n) .. fired, "small", 52, 100)
            y = math.min(y, top - 44) - 6
            Box(0, top, CW, top - y)
            Accent(0, top)
            local done = Link("Done", 0, top, function() J.ReminderDone(n.id) end)
            local edit = Link("Edit", 44, top, function() StartEdit(n) end)
            Entry(top, { done, edit })
            Gap(12)
        end
    end

    if #others == 0 and #pending == 0 then
        Text("No notes yet. They remember where and when you wrote them.", "ink")
    end
    local function NoteRow(n)
        local top = y
        local tm = Text(date("%H:%M", n.t), "ink", 0, 0, true)
        if n.pinned then
            tm:SetTextColor(unpack(Ink("head")))
            Text("pinned", "ink", 0, 0, true):SetPoint("TOPLEFT", 0, top - 17)
        end
        if n.shared then Text("shared", "ink", 0, 0, true):SetPoint("TOPLEFT", 0, top - (n.pinned and 31 or 17)) end
        -- keep the text clear of the hover links on the right (Share, Unpin, Edit, Archive)
        Text(n.text, "body", TIME_COL, 190)
        Text(("%s  ·  level %d"):format(J.NoteWhere(n), n.level or 0), "small", TIME_COL, 190)
        local links = {}
        links[#links + 1] = Link("Archive", 0, top, function() J.SetArchived("note", n.id, true) end)
        links[#links + 1] = Link("Edit", 52, top, function() StartEdit(n) end)
        links[#links + 1] = Link(n.pinned and "Unpin" or "Pin", 88, top, function() J.TogglePin(n.id) end)
        if ns.Together then
            links[#links + 1] = Link(n.shared and "Unshare" or "Share", 130, top, function() ns.Together.SetShared(n.id, not n.shared) end)
        end
        if n.trigger and n.done then
            local rowTop = y
            Text(("Reminded you %s  ·  %s"):format(n.firedAt and date("%b %d, %H:%M", n.firedAt) or "", J.TriggerLabel(n.trigger)),
                "small", TIME_COL, 100)
            links[#links + 1] = Link("Remind again", 0, rowTop, function() J.RemindAgain(n.id) end)
        end
        if n.pinned then Accent(TIME_COL - 10, top) end
        Entry(top, links)
        Gap(12)
    end
    Gap(4)
    local lastDay, dayOpen
    for _, n in ipairs(others) do
        local day = DayTitle(n.t)
        if day ~= lastDay then
            dayOpen = Header("day:" .. date("%Y%m%d", n.t), day)
            lastDay = day
        end
        if dayOpen then NoteRow(n) end
    end
end

-- Quests ------------------------------------------------------------------------------------
-- Completed quests, newest first, grouped by day like the notes.
local function Money(copper)
    if not copper or copper <= 0 then return nil end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 and g == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- Ways to group the list: key, label, group key for a quest, and the order of groups.
local QUEST_GROUPS = {
    { "day", "Day", function(q) return date("%Y%m%d", q.t), DayTitle(q.t) end, function(a, b) return a.key > b.key end },
    { "level", "Level", function(q) return q.level or 0, ("Level %d"):format(q.level or 0) end, function(a, b) return a.key > b.key end },
    { "zone", "Zone", function(q) if q.zone then return q.zone, q.zone end return Find.OTHER, "Other" end, function(a, b) return a.latest > b.latest end },
    { "type", "Type", function(q) if q.kind then return q.kind, q.kind end return Find.OTHER, "Other" end, function(a, b) return a.latest > b.latest end },
}

-- Money with the game's coin icons (letters like "s" read badly in the display face).
local COIN = { "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t", "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t",
    "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" }
local function Coins(copper)
    copper = math.floor(copper or 0)
    local g, sv, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. COIN[1] end
    if sv > 0 or g > 0 then parts[#parts + 1] = sv .. COIN[2] end
    parts[#parts + 1] = c .. COIN[3]
    return table.concat(parts, " ")
end
-- Quests still in your log, grouped like the handed-in ones by when, at which level and where you took them;
-- each with how far along it is and how long you have had it.
local function RenderOpenQuests(list, by)
    local groups, byKey = {}, {}
    local now = time()
    for _, q in ipairs(list) do
        local s = q.start
        if Find.Match(q.title, q.objective, s and s.zone, s and s.subzone, s and s.giver) then
            local key, title
            if by ~= "type" and not (s and (by ~= "level" or s.level)) then
                key, title = Find.OTHER, "Other"   -- taken before the journal kept track: no day, level or place to go by
            elseif by == "day" then
                key, title = date("%Y%m%d", s.t), DayTitle(s.t)
            elseif by == "level" then
                key, title = s.level, ("Picked up at level %d"):format(s.level)
            elseif by == "zone" then
                key, title = s.zone or Find.OTHER, s.zone or "Other"
            else
                key = q.ready and "a" or "b"; title = q.ready and "Ready to hand in" or "Still to do"
            end
            local g = byKey[key]
            if not g then g = { key = key, title = title, list = {}, latest = 0 }; byKey[key] = g; groups[#groups + 1] = g end
            table.insert(g.list, q)
            g.latest = math.max(g.latest, s and s.t or 0)
        end
    end
    if #groups == 0 then
        Text(#list == 0 and "Your quest log is empty. Pick up a quest and it shows here until you hand it in." or "No quest in your log matches that.", "ink")
        return
    end
    table.sort(groups, function(a, b)
        if (a.key == Find.OTHER) ~= (b.key == Find.OTHER) then return b.key == Find.OTHER end
        if by == "type" then return a.key < b.key end
        return a.latest > b.latest
    end)
    for _, g in ipairs(groups) do
        table.sort(g.list, function(a, b) return (a.start and a.start.t or 0) > (b.start and b.start.t or 0) end)
        if Header("openquests:" .. by .. ":" .. tostring(g.key), g.title, J.Count(#g.list, "quest")) then
            local cardTop = y
            Gap(6)
            for n, q in ipairs(g.list) do
                local rowTop, s = y, q.start
                if n > 1 then
                    local rule = Next("line", function() return content:CreateTexture(nil, "ARTWORK") end)
                    local c = Ink("dim"); rule:SetColorTexture(c[1], c[2], c[3], 0.25)
                    rule:SetSize(CW - 28, 1); rule:SetPoint("TOPLEFT", 14, rowTop + 1)
                end
                Ring(14, rowTop - 8, 34, nil, false, "Interface/GossipFrame/AvailableQuestIcon")
                local title = Text(q.title, "body", 60, 110, true)
                title:SetPoint("TOPLEFT", 60, rowTop - 8)
                local where = s and ((s.subzone and s.zone and s.subzone ~= s.zone) and (s.subzone .. ", " .. s.zone) or s.zone) or nil
                local sub = Text(s and ("Picked up %s%s  ·  level %d"):format(where and ("in " .. where .. "  ·  ") or "", date("%b %d, %H:%M", s.t), s.level or q.level or 0)
                    or ("Quest level %d  ·  taken before the journal kept track"):format(q.level or 0), "small", 60, 110, true)
                sub:SetPoint("TOPLEFT", 60, rowTop - 12 - title:GetStringHeight())
                sub:SetWordWrap(false)
                -- right: how far along, and how long you have had it
                local prog = Text(q.ready and "Ready" or (q.need > 0 and ("%d / %d"):format(q.have, q.need) or "In progress"), "body", 0, 0, true)
                prog:SetWidth(100); prog:SetJustifyH("RIGHT"); prog:SetPoint("TOPLEFT", CW - 116, rowTop - 9)
                if q.ready then local c = Ink("link"); prog:SetTextColor(c[1], c[2], c[3]) end
                if s then
                    local age = Text(J.Dur(math.max(0, now - s.t)) .. " on it", "small", 0, 0, true)
                    age:SetWidth(100); age:SetJustifyH("RIGHT"); age:SetPoint("TOPLEFT", CW - 116, rowTop - 27)
                end
                y = rowTop - math.max(50, title:GetStringHeight() + sub:GetStringHeight() + 22)
                local key = "open" .. q.questID
                local spot = Hotspot(0, rowTop, CW, rowTop - y, function() openQuest[key] = not openQuest[key]; UI.Render() end)
                spot:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                    if pcall(GameTooltip.SetHyperlink, GameTooltip, ("quest:%d:%d"):format(q.questID, q.level or 0)) then
                        GameTooltip:AddLine("Click for details", 0.6, 0.6, 0.6); GameTooltip:Show()
                    else GameTooltip:Hide() end
                end)
                spot:SetScript("OnLeave", GameTooltip_Hide)
                if openQuest[key] then
                    Gap(-6)
                    if q.objective then local fs = Text(q.objective, "body", 60, 20) end
                    if s then
                        Text(s.giver and ("From %s%s"):format(s.giver, where and (", " .. where) or "") or "Started without a quest giver", "small", 60, 20)
                        Text(("Picked up %s  ·  %s ago"):format(date("%b %d, %H:%M", s.t), J.Dur(math.max(0, now - s.t))), "small", 60, 20)
                    end
                    Gap(8)
                end
            end
            Gap(4)
            Box(0, cardTop, CW, cardTop - y)
            Gap(12)
        end
    end
end
-- Bláto Journal: who of the three of you has done a quest (Together.lua): the game's ready-check marks, a tick
-- for done, a cross and red ink for not done, a question mark while nobody has said. mine: your own state, when
-- the quest is not one of yours (a friend's quest you have not done).
BJ.MARK = { [true] = "|TInterface\\RaidFrame\\ReadyCheck-Ready:13|t", [false] = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:13|t" }
BJ.MARK_UNKNOWN = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:13|t"
function BJ.PartyMarks(questID, with, mine)
    local T, a, b = ns.Together, J.PartyMates()
    if not (T and a) then return nil end
    local parts = {}
    for i, name in ipairs({ J.PlayerName(), a.name, b and b.name }) do
        local st
        if i == 1 then st = mine == nil and true or mine else st = T.Status(name, questID, with) end
        local short = name:match("^(%S+)") or name
        parts[#parts + 1] = (st == nil and BJ.MARK_UNKNOWN or BJ.MARK[st]) .. " " .. (st == false and ("|cffc0301a" .. short .. "|r") or short)
    end
    return table.concat(parts, "     ")
end

local function RenderQuests()
    if archiveOpen.quest then return RenderArchive("quest") end
    BarButtons({})
    if ns.Together then ns.Together.AskRecent() end
    local titleTop = y
    local headAt = y
    local visible, xp, money, byZone = 0, 0, 0, {}
    for _, q in ipairs(H.quests) do
        if not q.archived then
            visible = visible + 1
            xp, money = xp + (q.xp or 0), money + (q.money or 0)
            if q.zone then byZone[q.zone] = (byZone[q.zone] or 0) + 1 end
        end
    end
    local view = DB.questView or "done"
    if visible == 0 and view == "done" and #J.OpenQuests() == 0 then
        PageHead("Quests")
        ArchiveLink("quest", titleTop)
        Text("No quests handed in yet. Each one you finish is written down here, with where and when.", "ink")
        return
    end
    local zl = {}
    for z, n in pairs(byZone) do zl[#zl + 1] = { z, n } end
    table.sort(zl, function(a, b) return a[2] > b[2] end)
    local top2 = {}
    -- the totals as a sentence under the title, the numbers in stronger ink
    local hex = function(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
    local strong = hex(Ink("head"))
    local sentence = ("%s%s|r handed in, %s%s|r experience and %s earned."):format(strong, J.Count(visible, "quest"), strong,
        BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or tostring(xp), Coins(money))
    if zl[1] then sentence = sentence .. (" Most of them in %s%s|r."):format(strong, zl[1][1]) end
    y = headAt
    PageHead("Quests", visible > 0 and sentence or nil, 90, "body")
    ArchiveLink("quest", titleTop)
    local mode = QUEST_GROUPS[1]
    for _, g in ipairs(QUEST_GROUPS) do if g[1] == DB.questGroup then mode = g end end
    -- "Group by": one switch, the active part in gold
    local top = y
    local labels, widths, total = {}, {}, 6
    for i, g in ipairs(QUEST_GROUPS) do
        labels[i] = Text(g[2], "small", 0, 0, true)
        widths[i] = labels[i]:GetStringWidth() + 26
        total = total + widths[i] + 2
    end
    local sx = CW - total
    local open = J.OpenQuests()
    -- handed in, or still in your log
    Switch({ { "done", "Handed in" }, { "open", ("In progress (%d)"):format(#open) } }, view, 0, top,
        function(k) DB.questView = k; UI.Render() end)
    Box(sx, top, total, 28, nil, nil, "Chip")
    local x = sx + 3
    for i, g in ipairs(QUEST_GROUPS) do
        local on = g == mode
        labels[i]:SetPoint("TOPLEFT", x + 13, top - 8)
        if on then
            labels[i]:Hide()
            local c = Chip(g[2], x, top - 3, "Badge")
            c:SetSize(widths[i], 22)
        end
        Hotspot(x, top - 3, widths[i], 22, function() DB.questGroup = g[1]; UI.Render() end)
        x = x + widths[i] + 2
    end
    Gap(38)
    Find.Field("quests", 0, y, CW, view == "open" and "Search your quest log" or "Search quests")
    Gap(40)
    if view == "open" then return RenderOpenQuests(open, mode[1]) end

    -- Bláto Journal: quests your friends handed in that you have not done (yet)
    local behind = {}
    for id, p in pairs(H.partyQuests or {}) do
        if ns.Together and ns.Together.Done(id) ~= true and Find.Match(p.title or "") then
            behind[#behind + 1] = { t = p.t, text = p.title or ("Quest #%d"):format(id), icon = "Interface/GossipFrame/AvailableQuestIcon",
                sub = BJ.PartyMarks(id, nil, false) }
        end
    end
    table.sort(behind, function(a, b) return a.t > b.t end)
    if #behind > 0 and Header("quests:behind", "Done by your friends, not by you", tostring(#behind)) then Body(behind, 0) end

    local groups, byKey = {}, {}
    for i = #H.quests, 1, -1 do
        local q = H.quests[i]
        if not q.archived and Find.Match(J.QuestName(q), q.zone, q.subzone, q.objective, q.giver, q.taker, q.kind) then
            local key, title = mode[3](q)
            local grp = byKey[key]
            if not grp then grp = { key = key, title = title, list = {}, latest = 0 }; byKey[key] = grp; groups[#groups + 1] = grp end
            table.insert(grp.list, q)
            grp.latest = math.max(grp.latest, q.t or 0)
        end
    end
    table.sort(groups, function(a, b)
        if (a.key == Find.OTHER) ~= (b.key == Find.OTHER) then return b.key == Find.OTHER end
        return mode[4](a, b)
    end)
    for _, grp in ipairs(groups) do table.sort(grp.list, function(a, b) return (a.t or 0) > (b.t or 0) end) end
    -- each group is a ledger: one card, a row per quest with thin rules between, rewards in a column on the right
    for _, grp in ipairs(groups) do
        local gxp = 0
        for _, q in ipairs(grp.list) do gxp = gxp + (q.xp or 0) end
        local extra = J.Count(#grp.list, "quest") .. (gxp > 0 and ("  ·  " .. (BreakUpLargeNumbers and BreakUpLargeNumbers(gxp) or gxp) .. " xp") or "")
        local open = Header("quests:" .. mode[1] .. ":" .. tostring(grp.key), grp.title, extra)
        if open then
            local cardTop = y
            Gap(6)
            for n, q in ipairs(grp.list) do
                local rowTop = y
                if n > 1 then
                    local rule = Next("line", function() return content:CreateTexture(nil, "ARTWORK") end)
                    local c = Ink("dim"); rule:SetColorTexture(c[1], c[2], c[3], 0.25)
                    rule:SetSize(CW - 28, 1); rule:SetPoint("TOPLEFT", 14, rowTop + 1)
                end
                Ring(14, rowTop - 8, 34, nil, false, "Interface/GossipFrame/ActiveQuestIcon")
                local title = Text(J.QuestName(q), "body", 60, 110, true)
                title:SetPoint("TOPLEFT", 60, rowTop - 8)
                local when = date(mode[1] == "day" and "%H:%M" or "%b %d", q.t)
                local sub = Text(("%s  ·  level %d  ·  %s"):format(J.NoteWhere(q), q.level or 0, when), "small", 60, 110, true)
                sub:SetWordWrap(false)
                sub:SetPoint("TOPLEFT", 60, rowTop - 12 - title:GetStringHeight())
                local marksH = 0
                local marks = BJ.PartyMarks(q.questID, q.with)
                if marks then
                    local ml = Text(marks, "small", 60, 110, true)
                    ml:SetWordWrap(false)
                    ml:SetPoint("TOPLEFT", 60, rowTop - 16 - title:GetStringHeight() - sub:GetStringHeight())
                    marksH = ml:GetStringHeight() + 4
                end
                local ry = rowTop - 9
                local rewards = {}
                local showRewards = DB.questRewards ~= false
                if showRewards and q.xp and q.xp > 0 then
                    local fs = Text((BreakUpLargeNumbers and BreakUpLargeNumbers(q.xp) or q.xp) .. " xp", "body", 0, 0, true)
                    fs:SetWidth(100); fs:SetJustifyH("RIGHT"); fs:SetPoint("TOPLEFT", CW - 116, ry)
                    rewards[#rewards + 1] = fs
                    ry = ry - 18
                end
                if showRewards and q.money and q.money > 0 then
                    local fs = Text(Coins(q.money), "small", 0, 0, true)
                    fs:SetWidth(100); fs:SetJustifyH("RIGHT"); fs:SetPoint("TOPLEFT", CW - 116, ry)
                    rewards[#rewards + 1] = fs
                end
                y = rowTop - math.max(50, title:GetStringHeight() + sub:GetStringHeight() + marksH + 22)
                -- the row opens to show what the quest asked, who gave and took it, and how long it took;
                -- hovering shows the game's own quest tooltip
                local spot = Hotspot(0, rowTop, CW - 130, rowTop - y, function() openQuest[q.id] = not openQuest[q.id]; UI.Render() end)
                if q.questID then
                    spot:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                        if pcall(GameTooltip.SetHyperlink, GameTooltip, ("quest:%d:%d"):format(q.questID, q.level or 0)) then
                            GameTooltip:AddLine("Click for details", 0.6, 0.6, 0.6); GameTooltip:Show()
                        else GameTooltip:Hide() end
                    end)
                    spot:SetScript("OnLeave", GameTooltip_Hide)
                end
                if openQuest[q.id] then
                    local lines = {}
                    if q.objective then lines[#lines + 1] = { q.objective, "body", true } end
                    if q.giver or q.taker then
                        local from = q.giver and ("From %s%s"):format(q.giver, q.fromSub and (", " .. q.fromSub) or (q.fromZone and (", " .. q.fromZone) or "")) or "Started without a quest giver"
                        local to = q.taker and ("  →  to %s%s"):format(q.taker, q.subzone and (", " .. q.subzone) or "") or ""
                        lines[#lines + 1] = { from .. to, "small" }
                    end
                    if q.started then
                        lines[#lines + 1] = { ("Picked up %s  ·  handed in %s  ·  took %s"):format(date("%b %d, %H:%M", q.started), date("%H:%M", q.t),
                            J.Dur(math.max(0, q.t - q.started))), "small" }
                    end
                    if #lines == 0 then lines[1] = { "Handed in before the journal kept a quest's story.", "small" } end
                    Gap(-6)
                    for _, l in ipairs(lines) do
                        local fs = Text(l[1], l[2], 60, 20)
                        if l[3] then local f, sz = fs:GetFont(); pcall(fs.SetFont, fs, f, sz, "") end
                    end
                    Gap(8)
                end
                -- while hovered, Archive takes the rewards' place on the right
                Entry(rowTop, { Link("Archive", 16, rowTop - 16, function() J.SetArchived("quest", q.id, true) end) }, rewards)
            end
            Gap(4)
            Box(0, cardTop, CW, cardTop - y)
            Gap(12)
        end
    end
end

-- Archive ------------------------------------------------------------------------------------
local ARCHIVE_TITLE = { note = "Archived notes", goal = "Archived goals", quest = "Archived quests" }
RenderArchive = function(kind)
    BarButtons({})
    local titleTop = y
    Text(ARCHIVE_TITLE[kind], "title")
    ArchiveLink(kind, titleTop)
    Text("Hidden from the page until you restore them. Delete removes them for good."
        .. (kind == "note" and " Pinned notes stay on your Journey page until deleted." or ""), "dim")
    local all, list = J.Archived(kind), {}
    Find.Field("archive:" .. kind, 0, y - 6, CW, "Search the archive")
    Gap(44)
    for _, x in ipairs(all) do
        if Find.Match(x.text, x.label, x.title, x.zone, x.subzone, x.objective) then list[#list + 1] = x end
    end
    if #list == 0 and #all > 0 then Text("Nothing in the archive matches that.", "ink") return end
    if #list == 0 then
        Divider()
        Text("The archive is empty", "head")
        Text(({
            note = "Hover a note and click Archive to tidy it away. It leaves the Notes page but is kept here, and a pinned note "
                .. "still shows on your Journey page. Finished reminders land here on their own.",
            goal = "Hover a goal and click Archive to tidy it away, or use Archive all on the goals you have reached. "
                .. "You can also send reached goals here on their own in settings.",
            quest = "Hover a quest and click Archive to tidy it away. It leaves the Quests page but is kept here.",
        })[kind] .. " Restore brings anything back, Delete removes it for good.", "body")
        return
    end
    Divider()
    for _, x in ipairs(list) do
        local top = y
        Text(J.Date(x.t or x.created or x.archived), "date", 0, 0, true)
        local label, sub
        if kind == "note" then
            label = x.text
            sub = ("%s  ·  level %d%s"):format(J.NoteWhere(x), x.level or 0, x.pinned and "  ·  on your Journey page" or "")
        elseif kind == "goal" then
            label = x.label
            sub = x.done and ("Reached " .. J.Date(x.doneAt or x.archived)) or "Not reached"
        else
            label = J.QuestName(x)
            sub = ("%s  ·  level %d"):format(J.NoteWhere(x), x.level or 0)
        end
        Text(label, "body", TIME_COL, 120)
        Text(sub .. "  ·  archived " .. J.Date(x.archived), "small", TIME_COL, 120)
        Entry(top, {
            Link("Delete", 0, top, function() J.DeleteItem(kind, x.id) end),
            Link("Restore", 52, top, function() J.SetArchived(kind, x.id, false) end),
        })
        Gap(10)
    end
end

-- Rendering ---------------------------------------------------------------------------------
-- Fellowship ---------------------------------------------------------------------------------
-- Everyone you have grouped with, as cards; a companion's own page with your time together and what you did.
-- (One table: the main chunk has no locals to spare.)
local Fellow = {}
Fellow.SPLIT = { { "dungeon", "Dungeons", { 0.54, 0.24, 0.82 }, { 0.48, 0.17, 0.75 } }, { "fight", "Fighting", { 0.78, 0.27, 0.17 }, { 0.66, 0.20, 0.11 } },
    { "travel", "Travelling", { 0.85, 0.64, 0.25 }, { 0.72, 0.52, 0.11 } }, { "town", "In town", { 0.44, 0.58, 0.72 }, { 0.25, 0.42, 0.58 } } }
function Fellow.Fleeting() return (DB.fleetingMinutes or 10) * 60 end
function Fellow.Color(f)
    local c = f.class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[f.class]
    if not c then return Ink("head") end
    if parchment then return { c.r * 0.5, c.g * 0.5, c.b * 0.5 } end
    return { c.r, c.g, c.b }
end
function Fellow.Who(f)
    local cls = f.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[f.class] or (f.class and (f.class:sub(1, 1) .. f.class:sub(2):lower()))
    local bits = {}
    if f.race then bits[#bits + 1] = f.race end
    if cls then bits[#bits + 1] = cls end
    local who = table.concat(bits, " ")
    return f.level and (who ~= "" and ("%s, level %d"):format(who, f.level) or ("Level %d"):format(f.level)) or who
end
function Fellow.Short(name) return (name:gsub("%-", " ")) end   -- the full name, "First Last"
-- the time together as one bar split by what you did; returns nothing
function Fellow.Split(f, x, top, w, h)
    Track(x, top, w, 0, h)
    local total = math.max(1, f.time)
    local cx, inner = x + 3, w - 6
    for i, sp in ipairs(Fellow.SPLIT) do
        local v = (f.split or {})[sp[1]] or 0
        if v > 0 then
            -- the track is a frame above the page, so the segments ride on frames above it
            local seg = Next("fseg", function()
                local f = CreateFrame("Frame", nil, content)
                f.t = f:CreateTexture(nil, "OVERLAY"); f.t:SetAllPoints()
                return f
            end)
            seg:SetFrameLevel(content:GetFrameLevel() + 3)
            local c = parchment and sp[4] or sp[3]
            local sw = math.max(1, math.floor(inner * v / total + 0.5))
            seg.t:SetColorTexture(c[1], c[2], c[3], 1)
            seg:SetSize(sw, h - 4); seg:SetPoint("TOPLEFT", cx, top - 2)
            cx = cx + sw
        end
    end
end
-- the split explained in a tooltip: each part in its colour with its time
function Fellow.Tip(owner, f, footer)
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:SetText(Fellow.Short(f.name))
    for _, sp in ipairs(Fellow.SPLIT) do
        local v = (f.split or {})[sp[1]] or 0
        if v > 0 then GameTooltip:AddDoubleLine(sp[2], J.Dur(v), sp[3][1], sp[3][2], sp[3][3], 1, 1, 1) end
    end
    GameTooltip:AddDoubleLine("Together", J.Dur(f.time), 1, 0.82, 0, 1, 1, 1)
    if footer then GameTooltip:AddLine(footer, 0.6, 0.6, 0.6) end
    GameTooltip:Show()
end
function Fellow.Legend(x, top)
    local cx = x
    for _, sp in ipairs(Fellow.SPLIT) do
        local sq = Next("fleg", function() return content:CreateTexture(nil, "ARTWORK") end)
        local c = parchment and sp[4] or sp[3]
        sq:SetColorTexture(c[1], c[2], c[3], 1); sq:SetSize(10, 10); sq:SetPoint("TOPLEFT", cx, top - 3)
        local fs = Text(sp[2], "small", 0, 0, true)
        fs:SetPoint("TOPLEFT", cx + 15, top)
        cx = cx + 15 + fs:GetStringWidth() + 16
    end
end
function Fellow.Card(x, top, w, h, f)
    Box(x, top, w, h)
    Ring(x + 12, top - 10, 32, nil, false, f.class and ("Interface/Icons/ClassIcon_" .. f.class) or "Interface/Icons/INV_Misc_QuestionMark")
    local name = Text(Fellow.Short(f.name), "chapter", x + 52, 0, true)
    name:SetPoint("TOPLEFT", x + 52, top - 9); name:SetWidth(w - 64); name:SetWordWrap(false)
    local c = Fellow.Color(f); name:SetTextColor(c[1], c[2], c[3])
    local who = Text(Fellow.Who(f), "small", x + 52, 0, true)
    who:SetPoint("TOPLEFT", x + 52, top - 31); who:SetWidth(w - 64); who:SetWordWrap(false)
    local met = Text(("Met %s at level %d%s"):format(J.Date(f.met), f.metLevel or 0, (f.metSub or f.metZone) and (", " .. (f.metSub or f.metZone)) or ""),
        "ink", x + 14, 0, true)
    met:SetPoint("TOPLEFT", x + 14, top - 54); met:SetWidth(w - 28); met:SetWordWrap(false)
    Fellow.Split(f, x + 14, top - 78, w - 90, 8)
    local t = Text(J.Dur(f.time), "small", 0, 0, true)
    t:SetWidth(60); t:SetJustifyH("RIGHT"); t:SetPoint("TOPLEFT", x + w - 72, top - 75)
    local spot = Hotspot(x, top, w, h, function() Fellow.open = f.name; UI.Render() end)
    spot:SetScript("OnEnter", function(self) Fellow.Tip(self, f, "Click to open") end)
    spot:SetScript("OnLeave", GameTooltip_Hide)
end
function Fellow.Grid(list)
    local w, h = math.floor((CW - 12) / 2), 98
    for i, f in ipairs(list) do
        local col = (i - 1) % 2
        Fellow.Card(col * (w + 12), y - math.floor((i - 1) / 2) * (h + 12), w, h, f)
    end
    y = y - math.ceil(#list / 2) * (h + 12)
end
function Fellow.List()
    local all, total, most = {}, 0, nil
    for _, f in pairs(H.fellows or {}) do
        all[#all + 1] = f; total = total + f.time
        if not most or f.time > most.time then most = f end
    end
    local hex = function(c) return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255) end
    local strong = hex(Ink("head"))
    local sub = #all == 0 and "No one yet. Group up with someone and they join your fellowship here."
        or ("You have shared the road with %s%s|r, %s%s|r in all. Most often with %s%s|r."):format(strong, J.Count(#all, "adventurer"), strong,
            J.Dur(total), strong, Fellow.Short(most.name))
    PageHead("Fellowship", sub, nil, "body")
    if #all == 0 then return end
    local sort = DB.fellowSort or "time"
    local top = y
    local sw = Switch({ { "time", "Most time" }, { "recent", "Recent" }, { "met", "Met first" } }, sort, 0, top,
        function(k) DB.fellowSort = k; UI.Render() end)
    Find.Field("fellowship", sw + 10, top, CW - sw - 10, "Search your fellowship")
    y = top - 42
    local close, fleeting = {}, {}
    for _, f in ipairs(all) do
        if Find.Match(f.name, f.race, f.class, f.metZone, f.metSub) then
            if f.time >= Fellow.Fleeting() then close[#close + 1] = f else fleeting[#fleeting + 1] = f end
        end
    end
    local order = { time = function(a, b) return a.time > b.time end, recent = function(a, b) return (a.last or 0) > (b.last or 0) end,
        met = function(a, b) return (a.met or 0) < (b.met or 0) end }
    table.sort(close, order[sort]); table.sort(fleeting, order[sort])
    if #close == 0 and #fleeting == 0 then Text("No one in your fellowship matches that.", "ink") return end
    Fellow.Grid(close)
    if #fleeting > 0 and Header("fellowship:fleeting", "Fleeting company", ("%d  ·  under %d minutes together"):format(#fleeting, DB.fleetingMinutes or 10), true) then
        Fellow.Grid(fleeting)
    end
end
function Fellow.Page(f)
    local crumb = Text("Fellowship", "gold", 2, 0, true)
    local cw = crumb:GetStringWidth()
    Text("›  " .. Fellow.Short(f.name), "ink", cw + 10, 0, true):SetPoint("TOPLEFT", cw + 10, y - 4)
    Hotspot(0, y + 2, cw + 8, 24, function() Fellow.open = nil; UI.Render() end, "Back to your fellowship")
    Gap(28)
    local SW = 210
    local headTop = y
    local met = ("%s. You first met %s%s, you at level %d%s."):format(Fellow.Who(f):gsub(", level %d+$", ""), J.Date(f.met),
        (f.metSub or f.metZone) and (" in " .. (f.metSub or f.metZone)) or "", f.metLevel or 0,
        f.theirMetLevel and (" and " .. Fellow.Short(f.name) .. " at " .. f.theirMetLevel) or "")
    local _, hero = PageHead(Fellow.Short(f.name), met, SW + 20, nil, SW + 20)
    local c = Fellow.Color(f); hero:SetTextColor(c[1], c[2], c[3])
    -- what you did together, counted from the quests and runs that remember them
    local quests, runs = {}, {}
    for i = #H.quests, 1, -1 do local q = H.quests[i]; if q.with and q.with[f.name] then quests[#quests + 1] = q end end
    for _, r in pairs(f.runs or {}) do runs[#runs + 1] = r end
    table.sort(runs, function(a, b) return a.t > b.t end)
    local openTogether = 0
    for id, names in pairs(H.questWith or {}) do if names[f.name] then openTogether = openTogether + 1 end end
    local rows = { { J.Dur(f.time), "grouped together" }, { tostring(#quests + openTogether), "quests together" }, { tostring(#runs), #runs == 1 and "dungeon run" or "dungeon runs" } }
    if f.lowLevel and f.highLevel and f.highLevel > f.lowLevel then rows[#rows + 1] = { f.lowLevel .. " → " .. f.highLevel, "levels side by side" } end
    local sx, stop = CW - SW, headTop + 4
    local sh = 20 + #rows * 20
    local shadow = Next("scrapshadow", function() return content:CreateTexture(nil, "BACKGROUND", nil, 2) end)
    shadow:SetColorTexture(0, 0, 0, 0.28); shadow:SetSize(SW - 4, sh - 4); shadow:SetPoint("TOPLEFT", sx + 5, stop - 6)
    Box(sx, stop, SW, sh, nil, nil, "Paper")
    local tape = Next("tape", function() return content:CreateTexture(nil, "ARTWORK", nil, 3) end)
    tape:SetTexture(KitFile("Tape")); tape:SetSize(70, 16); tape:SetPoint("TOPLEFT", sx + SW / 2 - 35, stop + 8)
    for i, row in ipairs(rows) do
        local ry = stop - 10 - (i - 1) * 20
        local label = Text(row[2], "small", 0, 0, true)
        label:SetPoint("TOPLEFT", sx + 16, ry - 2); label:SetTextColor(0.37, 0.27, 0.15); label:SetShadowOffset(0, 0)
        local n = Text(row[1], "ink", 0, 0, true)
        n:SetWidth(70); n:SetJustifyH("RIGHT"); n:SetPoint("TOPLEFT", sx + SW - 86, ry)
        n:SetTextColor(0.14, 0.09, 0.04); n:SetShadowOffset(0, 0)
    end
    y = math.min(y, stop - sh - 16)
    Fellow.Split(f, 0, y, CW, 12)
    local spot = Hotspot(0, y + 4, CW, 20, function() end)
    spot:SetScript("OnEnter", function(self) Fellow.Tip(self, f) end)
    spot:SetScript("OnLeave", GameTooltip_Hide)
    Gap(30)
    if #runs > 0 and Header("fellow:runs", "Dungeons together", tostring(#runs)) then
        local list = {}
        for _, r in ipairs(runs) do
            list[#list + 1] = { t = r.t, text = r.name, icon = "Interface/Icons/INV_Misc_Head_Dragon_01",
                sub = J.Dur(r.time) .. ((r.bosses or 0) > 0 and ("  ·  " .. J.Count(r.bosses, "boss")):gsub("bosss", "bosses") or "") }
        end
        Body(list, 0)
    end
    -- quests still in your log that you have already worked on together
    local open = {}
    for _, oq in ipairs(J.OpenQuests()) do
        if H.questWith and H.questWith[oq.questID] and H.questWith[oq.questID][f.name] then open[#open + 1] = oq end
    end
    if Header("fellow:quests", "Quests together", tostring(#quests + #open)) then
        if #quests + #open == 0 then Text("None yet. A quest counts once you both have it and one of its objectives moves forward while you are grouped.", "ink") end
        local list = {}
        for _, oq in ipairs(open) do
            list[#list + 1] = { t = time(), text = oq.title, icon = "Interface/GossipFrame/AvailableQuestIcon",
                sub = oq.ready and "In progress  ·  ready to hand in" or ("In progress  ·  %d / %d"):format(oq.have, oq.need) }
        end
        for _, q in ipairs(quests) do
            list[#list + 1] = { t = q.t, text = J.QuestName(q), icon = "Interface/GossipFrame/ActiveQuestIcon",
                sub = ("%s  ·  level %d"):format(q.subzone or q.zone or "?", q.level or 0) }
        end
        Body(list, 0)
    end
end
function Fellow.Render()
    BarButtons({})
    local f = Fellow.open and H.fellows and H.fellows[Fellow.open]
    if f then return Fellow.Page(f) end
    Fellow.open = nil
    Fellow.List()
end

-- Bláto Journal: no Fellowship page; the three of you are on the Journey page
function UI.OpenFellow() UI.Show("journey") end

-- Bláto ---------------------------------------------------------------------------------------
-- Bláto Journal: the party side (Party/, from One More Quest) as buttons, grouped like its feature list. The
-- buttons come from ns.BlatoPage (Blato.lua); each section folds like the other headers of the journal.
-- A plain button runs its /blato command, a switch flips and shows on or off; the tooltip names the command.
BJ.COLS, BJ.ROW_H, BJ.GAP = 3, 30, 8
function BJ.Hint(item)
    if item.hint then return item.hint end
    if item.cmd then return "/blato " .. item.cmd .. (item.arg and (" " .. item.arg) or "") end
end
function BJ.Button(x, top, w, item)
    local toggle = item.toggle
    local on = toggle and toggle.get() and true or false
    local edge = parchment and { 0.45, 0.30, 0.12, 0.45 } or { 0.30, 0.24, 0.15, 1 }
    local lit = parchment and { 1, 0.85, 0.45, 0.45 } or { 1, 0.80, 0.35, 0.12 }
    Box(x, top, w, BJ.ROW_H, on and lit or nil, edge)
    Icon(item[2], x + 6, top - 5, 20)
    local label = Text(item[1], "body", x + 32, 0, true)
    label:SetPoint("TOPLEFT", x + 32, top - 8)
    label:SetWidth(w - (toggle and 64 or 38))
    label:SetWordWrap(false)
    local function press()
        local OMQ = ns.OMQ
        if toggle then toggle.set(not on)
        elseif item.click then item.click()
        elseif item.cmd and OMQ then OMQ:RunCommand(item.cmd, item.arg) end
        if OMQ then OMQ:Fire("SETTINGS_CHANGED", "journal") end   -- the party's option windows redraw
        UI.Render()
    end
    local spot = Hotspot(x, top, w, BJ.ROW_H, press)
    if toggle and UI.usedStyle == "classic" then
        -- the classic style shows a switch as the old game's check box
        Check(x + w - 28, top - 6, on, press):SetFrameLevel(spot:GetFrameLevel() + 1)
    elseif toggle then
        -- the Forever styles: the check box of the game's own options (Kit.Page:Check uses the same template)
        local c = Next("fcheck", function()
            local cb = Kit.Make("CheckButton", content, "SettingsCheckboxTemplate", "UICheckButtonTemplate")
            cb:SetScript("OnEnter", nil)   -- the template's handlers expect a Blizzard setting behind it
            cb:SetScript("OnLeave", nil)
            return cb
        end)
        c:SetSize(26, 26)
        c:SetPoint("TOPLEFT", x + w - 30, top - 2)
        c:SetChecked(on)
        c:SetScript("OnClick", press)
        c:SetFrameLevel(spot:GetFrameLevel() + 1)
    end
    spot:SetScript("OnEnter", function(self)
        if item.hover == "stats" and ns.OMQ and ns.OMQ.Tooltip then ns.OMQ.Tooltip:Show(self) return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(item[1], 1, 1, 1)
        GameTooltip:AddLine(item[3], nil, nil, nil, true)
        local hint = BJ.Hint(item)
        if hint then GameTooltip:AddLine(hint, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    spot:SetScript("OnLeave", function()
        GameTooltip_Hide()
        if item.hover == "stats" and ns.OMQ and ns.OMQ.Tooltip then ns.OMQ.Tooltip:Hide() end
    end)
end
function BJ.RenderCommands()
    BarButtons({})
    PageHead("Commands", "The party of three in one place. Hover a button for what it does and its /blato command.")
    if not ns.OMQ then Text("The party side did not load.", "ink") return end
    local w = math.floor((CW - BJ.GAP * (BJ.COLS - 1)) / BJ.COLS)
    for _, sec in ipairs(ns.BlatoPage or {}) do
        if Header("blato:" .. sec.key, sec.title) then
            local top = y
            for i, item in ipairs(sec.items) do
                local col, row = (i - 1) % BJ.COLS, math.floor((i - 1) / BJ.COLS)
                BJ.Button(col * (w + BJ.GAP), top - row * (BJ.ROW_H + 6), w, item)
            end
            y = top - math.ceil(#sec.items / BJ.COLS) * (BJ.ROW_H + 6) - 6
        end
    end
end

-- Dungeons ------------------------------------------------------------------------------------
-- Bláto Journal: the Dungeons tab is "Dungeon Journal" by Exehn (CurseForge), installed as its own addon: its
-- code is not ours to ship. While the tab is open its window sits exactly over the journal window, which takes its
-- size, so the journal's tabs hang under it; dragging it drags the journal, closing it closes the journal. Any
-- other tab, or closing the journal, puts it back where it was.
BJ.dock = { on = false }
function BJ.DungeonFrame()
    local f = _G.ForeverDungeonJournalFrame
    return type(f) == "table" and f.SetPoint and f or nil
end
function BJ.FitDock()
    local f = BJ.DungeonFrame()
    if not (BJ.dock.on and f) then return end
    local s = f:GetEffectiveScale() / win:GetEffectiveScale()
    win:SetSize(f:GetWidth() * s, f:GetHeight() * s)
end
function UI.Undock()
    if not BJ.dock.on then return end
    BJ.dock.on = false
    local f = BJ.DungeonFrame()
    if f then
        BJ.dock.leaving = true
        f:Hide()
        BJ.dock.leaving = false
        BJ.RestorePoints(f, BJ.dock.points)
        f:SetScript("OnDragStart", BJ.dock.dragStart)
        f:SetScript("OnDragStop", BJ.dock.dragStop)
    end
    win:SetSize(W, HGT)
    scroll:Show()
end
function BJ.Dock()
    local f = BJ.DungeonFrame()
    if not f then return false end
    if BJ.dock.on then BJ.FitDock(); f:Show(); return true end
    BJ.dock.on = true
    BJ.dock.points = BJ.SavePoints(f)
    BJ.dock.dragStart, BJ.dock.dragStop = f:GetScript("OnDragStart"), f:GetScript("OnDragStop")
    f:SetScript("OnDragStart", function() win:StartMoving() end)
    f:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
    if not BJ.dock.hooked then
        BJ.dock.hooked = true
        hooksecurefunc(f, "SetScale", BJ.FitDock)   -- its resize grip scales it: the journal follows
        f:HookScript("OnHide", function() if BJ.dock.on and not BJ.dock.leaving and win:IsShown() then win:Hide() end end)
    end
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", win, "TOPLEFT", 0, 0)
    BJ.FitDock()
    scroll:Hide()
    f:Show()
    return true
end
win:HookScript("OnHide", function() UI.Undock() end)

function BJ.RenderDungeons()
    BarButtons({})
    if BJ.Dock() then return end
    PageHead("Dungeons", "Bosses, loot, quests and maps of every dungeon, from the addon Dungeon Journal.")
    Text("Dungeon Journal is not installed. Get \"Dungeon Journal\" by Exehn, the edition for WoW Forever, from CurseForge, "
        .. "unzip it into Interface/AddOns and /reload: this tab then shows it.", "body")
    Gap(10)
    local list = {}
    for name, d in pairs(H.dungeons) do list[#list + 1] = { name, d } end
    table.sort(list, function(a, b) return (a[2].first or 0) < (b[2].first or 0) end)
    if Header("dungeons:mine", "Your dungeons", #list > 0 and tostring(#list) or nil) then
        if #list == 0 then Text("None braved yet.", "ink") end
        for _, it in ipairs(list) do
            local top = y
            local line = Text(("%s  ·  %s, first %s"):format(it[1], J.Count(it[2].runs or 0, "run"), J.Date(it[2].first)), "body")
            Hotspot(0, top + 2, CW, line:GetStringHeight() + 4, function() UI.OpenPlace("dungeon:" .. it[1]) end, "Open " .. it[1])
        end
    end
end

-- Bláto Journal: no Goals and no Fellowship page (their code above stays unused)
local RENDER = { commands = BJ.RenderCommands, dungeons = BJ.RenderDungeons, journey = RenderJourney, places = RenderPlaces,
    quests = RenderQuests, notes = RenderNotes }

-- Rebuilding the page hides and re-shows its edit boxes, and hiding one drops keyboard focus.
-- So the box being typed in gets its focus and cursor back afterwards.
local PAGE_BOXES = { noteEdit, UI.journeySearch }
for _, b in ipairs(PAGE_BOXES) do b:HookScript("OnMouseDown", function(self) self:SetFocus() end) end
local function FocusedBox() for _, b in ipairs(PAGE_BOXES) do if b:HasFocus() then return b end end end
local pendingRender = false

-- Back: beside the portrait in the title bar, while a page was opened from another (a place, an archive,
-- the new-goal steps).
local back = Kit.Make("Button", win, "UIPanelButtonTemplate")
back:SetSize(64, 20)
back:SetText("‹ Back")
back:SetPoint("TOPLEFT", win, "TOPLEFT", 64, -1)
-- above the frame art, like the settings gear: the title bar's art sits over plain child frames
local closeBtn = Child(win, "CloseButton")
back:SetFrameLevel((closeBtn or win):GetFrameLevel() + 2)
UI.backButton = back   -- the classic chrome moves it (UI.Chrome)
local function BackTarget()
    if current == "places" and openPlace then return function() openPlace = nil end end
    local kind = ({ notes = "note", quests = "quest" })[current]
    if kind and archiveOpen[kind] then return function() archiveOpen[kind] = false end end
end
back:SetScript("OnClick", function()
    local go = BackTarget()
    if go then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON); go(); UI.Render() end
end)

function UI.Render()
    if not win:IsShown() then return end
    SelectTab()   -- the tabs follow the style too (classic or modern)
    if current ~= "dungeons" then UI.Undock() end
    back:SetShown(BackTarget() ~= nil)
    pendingRender = false
    local focused = FocusedBox()
    local cursor = focused and focused:GetCursorPosition()
    Reset()
    wipe(entries)
    RENDER[current]()
    content:SetHeight(-y + 16)
    if focused and focused:IsVisible() then
        focused:SetFocus()
        if cursor then focused:SetCursorPosition(cursor) end
    end
    -- only show the scrollbar when the page is longer than the window
    local bar = Child(scroll, "ScrollBar")
    if bar then
        C_Timer.After(0, function() bar:SetShown((scroll:GetVerticalScrollRange() or 0) > 1) end)
    end
end

function UI.Show(tab)
    if tab and tab ~= current and tab ~= "places" then openPlace = nil end
    current = tab or current
    SelectTab()
    win:Show()
    UI.Render()
end

function UI.Toggle(tab)
    if win:IsShown() and (not tab or tab == current) then win:Hide() else UI.Show(tab) end
end

-- Quick note slip --------------------------------------------------------------------------------
-- A small parchment slip for writing on the move (keybind, minimap button right-click, /note).
local dlg = CreateFrame("Frame", "BlatoJournalNoteDialog", UIParent, "BasicFrameTemplateWithInset")
dlg:SetSize(500, 236)
dlg:SetPoint("TOP", 0, -160)
dlg:SetFrameStrata("DIALOG")
dlg:SetMovable(true)
dlg:EnableMouse(true)
dlg:RegisterForDrag("LeftButton")
dlg:SetScript("OnDragStart", dlg.StartMoving)
dlg:SetScript("OnDragStop", dlg.StopMovingOrSizing)
dlg:Hide()
tinsert(UISpecialFrames, "BlatoJournalNoteDialog")
dlg.title = Child(dlg, "TitleText") or dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
if not Child(dlg, "TitleText") then dlg.title:SetPoint("TOP", 0, -5) end
dlg.title:SetText("Quick note")
-- The paper sits below the title bar; everything written on it keeps clear of its decorated edge.
local slip = dlg:CreateTexture(nil, "BACKGROUND", nil, 7)
slip:SetPoint("TOPLEFT", 4, -24)
slip:SetPoint("BOTTOMRIGHT", -4, 4)
local where = dlg:CreateFontString(nil, "OVERLAY")
where:SetPoint("TOPLEFT", slip, "TOPLEFT", 26, -20)
where:SetPoint("RIGHT", slip, "RIGHT", -26, 0)
where:SetJustifyH("LEFT")
local slipEdit = CreateFrame("EditBox", nil, dlg)
slipEdit:SetMultiLine(true)
slipEdit:SetAutoFocus(false)
slipEdit:SetMaxLetters(600)
slipEdit:SetFontObject(FONTS.body)
slipEdit:SetPoint("TOPLEFT", where, "BOTTOMLEFT", 0, -10)
slipEdit:SetPoint("RIGHT", slip, "RIGHT", -26, 0)
slipEdit:SetHeight(70)
local slipHint = dlg:CreateFontString(nil, "OVERLAY")
slipHint:SetPoint("BOTTOMLEFT", slip, "BOTTOMLEFT", 26, 30)
local slipRow = ReminderRow(dlg)
slipRow:SetPoint("BOTTOMLEFT", slipHint, "TOPLEFT", 0, 8)
slipRow:SetPoint("RIGHT", slip, "RIGHT", -26, 0)
FollowText(slipEdit, slipRow)
table.insert(UI.linkBoxes, slipEdit)
local slipClick = CreateFrame("Button", nil, dlg)
slipClick:SetPoint("TOPLEFT", slipEdit, "TOPLEFT")
slipClick:SetPoint("BOTTOMRIGHT", slip, "BOTTOMRIGHT", -26, 84)
slipClick:SetFrameLevel(slipEdit:GetFrameLevel() - 1)
slipClick:SetScript("OnClick", function() slipEdit:SetFocus() end)
-- pin this note to the Journey page; starts from the "Pin new notes" setting each time the slip opens
local slipPin = Kit.Make("CheckButton", dlg, "UICheckButtonTemplate")
slipPin:SetSize(22, 22)
slipPin.label = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")   -- restyled in UI.StyleDialog
slipPin.label:SetPoint("RIGHT", slip, "BOTTOMRIGHT", -26, 36)
slipPin.label:SetText("Pin to Journey")
slipPin:SetPoint("RIGHT", slipPin.label, "LEFT", -2, 0)
slipPin:SetScript("OnClick", function() slipEdit:SetFocus() end)
-- Bláto Journal: share the note with the party (Together.lua); starts from the "Share new notes" option
dlg.shareText = dlg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
dlg.shareText:SetText("Share with the party")
dlg.shareText:SetPoint("RIGHT", slipPin, "LEFT", -12, 0)
dlg.share = Kit.Make("CheckButton", dlg, "UICheckButtonTemplate")
dlg.share:SetSize(22, 22)
dlg.share:SetPoint("RIGHT", dlg.shareText, "LEFT", -2, 0)
dlg.share:SetScript("OnClick", function() slipEdit:SetFocus() end)

function UI.StyleDialog()
    local used = Paper(PaintPage(slip))
    local saved = parchment
    parchment = used
    Style(where, "dim")
    Style(slipHint, "small")
    Style(slipPin.label, "small")
    Style(dlg.shareText, "small")
    slipRow:Ink()
    local c = Ink("body")
    slipEdit:SetTextColor(c[1], c[2], c[3])
    Shadow(slipEdit)
    parchment = saved
end

local function SaveSlip()
    local trigger = slipRow.trigger
    if J.AddNote(slipEdit:GetText(), trigger, slipRow.every:GetChecked(), slipPin:GetChecked(), dlg.share:GetChecked() and true or false) then
        J.Moment(trigger and ("|cffb0b0b0Noted. Reminder set: %s.|r"):format(J.TriggerLabel(trigger):gsub("^%u", string.lower)) or "|cffb0b0b0Noted in your journal.|r", "note")
    end
    slipEdit:SetText("")
    slipEdit:ClearFocus()
    dlg:Hide()
end
slipEdit:SetScript("OnEnterPressed", function(self) if IsShiftKeyDown() then self:Insert("\n") else SaveSlip() end end)
slipEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); dlg:Hide() end)

function UI.NoteDialog()
    UI.StyleDialog()
    local stamp = { zone = J.Zone(), subzone = J.SubZone() }
    where:SetText(("%s  ·  level %d"):format(J.NoteWhere(stamp), J.Level()))
    slipHint:SetText("Enter saves, Shift+Enter new line, Esc closes.")
    slipPin:SetChecked(DB.autoPin)
    dlg.share:SetChecked(DB.shareNotes ~= false)
    slipEdit:SetText("")
    slipRow:Reset(nil)
    dlg:Show()
    -- focus a frame later, so the key that opened the slip is not typed into it
    C_Timer.After(0, function() slipEdit:SetFocus() end)
end

-- /bj why: after the next click, report what was under the mouse and what has the keyboard.
function UI.Why()
    print("|cffffd100BlatoJournal:|r click the box that won't take typing.")
    local down = false
    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnUpdate", function(self)
        local pressed = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
        if pressed then down = true
        elseif down then
            self:SetScript("OnUpdate", nil)
            C_Timer.After(0.2, function()
                local function Name(f)
                    if not f then return "nothing" end
                    local n = f.GetName and f:GetName()
                    local parent = f.GetParent and f:GetParent()
                    local pn = parent and parent.GetName and parent:GetName()
                    return ("%s (%s%s)"):format(type(n) == "string" and n or tostring(f), f.GetObjectType and f:GetObjectType() or "?",
                        pn and (", in " .. pn) or "")
                end
                local foci = GetMouseFoci and GetMouseFoci() or { GetMouseFocus and GetMouseFocus() }
                print("Under the mouse: " .. Name(foci[1]))
                print("Keyboard focus: " .. Name(GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()))
            end)
        end
    end)
end

-- Refresh everything whenever the journal changes.
-- Background changes (loot, kills, quests) wait while you type; the page catches up when you leave the box.
function J.Changed()
    UI.UpdateTracker()
    if not win:IsShown() then return end
    if FocusedBox() then pendingRender = true else UI.Render() end
end
for _, b in ipairs(PAGE_BOXES) do
    b:HookScript("OnEditFocusLost", function()
        if pendingRender then C_Timer.After(0, function() if pendingRender and not FocusedBox() then UI.Render() end end) end
    end)
end
