-- Blato Lexicon: what the Bláto page of the journal offers (UI.lua draws it, RenderBlato).
-- Every feature of the party side (Party/, from One More Quest) as a button, grouped like its feature list:
--   cmd   runs "/blato <cmd> <arg>" (the tooltip shows the command, so it can go on a macro too)
--   toggle  a switch: { get, set }; the button shows on or off
--   click   anything else: function(button)
--   hover   "stats": the group statistics of tonight while the mouse is over the button
-- The party side is ns.OMQ (Party/Core.lua); it is only touched on a click, when everything has loaded.
local _, ns = ...

local function OMQ() return ns.OMQ end
local function Opts() local o = OMQ(); return o and o.db and o.db.options end

-- OMQ.db.options[key]; a key that was never set counts as def (most options are on until switched off)
local function Option(key, def)
    return {
        get = function() local o = Opts(); if not o then return false end; if o[key] == nil then return def end; return o[key] and true or false end,
        set = function(v) local o = Opts(); if o then o[key] = v end end,
    }
end
local function Qol(key)
    return {
        get = function() local o = Opts(); return o and o.qol and o.qol[key] ~= false or false end,
        set = function(v) local o = Opts(); if o and o.qol then o.qol[key] = v end end,
    }
end
local function Call(path, method, ...)
    local args = { ... }
    return function()
        local m = OMQ() and OMQ()[path]
        if m and m[method] then return m[method](m, unpack(args)) end
    end
end

local I = "Interface\\Icons\\"

ns.BlatoPage = {
    { key = "together", title = "Playing together", items = {
        { "Tonight in numbers", I .. "INV_Misc_PocketWatch_01", "Hover: the statistics of tonight for the whole party (XP per hour, gold, yards, deaths...). Click: the lifetime window.",
          hover = "stats", cmd = "lifetime" },
        { "Lifetime stats", I .. "INV_Misc_Book_11", "Every friend's character over its whole life, also the ones offline right now.", cmd = "lifetime" },
        { "Who has the addon", I .. "INV_BannerPVP_02", "Lists the friends whose game runs Blato Lexicon.", cmd = "users" },
        { "Share quests now", I .. "INV_Scroll_03", "Starts a sync round: everybody shares the quests the others are missing. Not while somebody without this addon is in the group: the game would offer them every quest too.", cmd = "quests", arg = "sync" },
        { "Follow key", I .. "Ability_Mount_RidingHorse", "The key that follows the closest friend. Set it with /blato follow <key>.", cmd = "follow" },
        { "Quest sync", I .. "INV_Scroll_03", "Exchange quest lists with the party; quests are shared when someone accepts them.", toggle = Option("questSync", true) },
        { "Auto share", I .. "INV_Letter_15", "A quest you accept is shared once with the party, shared quests are accepted silently (friends at most 5 levels apart). Paused while somebody without this addon is in the group.", toggle = Option("autoShare", true) },
        { "Alt: compare items", I .. "INV_Sword_04", "Hold Alt over an item: how it compares for every friend.", toggle = Option("compare", true) },
        { "Follow flights", I .. "Ability_Mount_Gryphon_01", "A friend took a flight: your flight master picks the same destination.", toggle = Qol("flight") },
    } },
    { key = "way", title = "Finding the way", items = {
        { "Arrow to friends", I .. "Ability_Tracking", "An arrow points to a friend who ran off from the others. If you are the one who ran off, it points back to the nearest friend.",
          toggle = { get = function() local o = OMQ(); return o and o.db and o.db.arrow.enabled ~= false or false end,
                     set = function(v) local o = OMQ(); if o and o.db then o.db.arrow.enabled = v end end } },
    } },
    { key = "alerts", title = "Alert cards", items = {
        { "Alerts", I .. "Ability_Warrior_BattleShout", "All alert cards: training, repair, drinks, buffs, spells not on a bar, pets, talents, ammo...",
          toggle = { get = function() local o = OMQ(); return o and o:Master("alerts") or false end,
                     set = function(v) local o = OMQ(); if o and o.Settings then o.Settings:MasterSet("alerts", v) end end } },
        { "Snooze 30 min", I .. "INV_Misc_PocketWatch_01", "No alert cards for 30 minutes; click again to wake them.",
          toggle = { get = Call("Alerts", "IsSnoozed"), set = Call("Settings", "SnoozeToggle") } },
        { "Bring back dismissed", I .. "Spell_Holy_HolyBolt", "Cards you clicked away come back.", click = Call("Alerts", "ResetDismissed") },
        { "Alert status", I .. "INV_Misc_QuestionMark", "Which alerts are on, snooze, and what they see now (in the chat).", cmd = "alerts" },
        { "Buff items", I .. "Trade_Alchemy", "Why an elixir, scroll or food in your bags gets a reminder or not.", cmd = "consumables" },
    } },
    { key = "trade", title = "Crafting and trading", items = {
        { "Scan auction prices", I .. "INV_Misc_Coin_02", "Reads the whole auction house once (open it first). The crafting profit uses these prices.", cmd = "prices", arg = "scan" },
        { "Price status", I .. "INV_Misc_Coin_01", "When the prices were scanned and how many there are.", cmd = "prices" },
        { "Recipe profit", I .. "Trade_Engineering", "What the open recipe costs and brings (open a profession first).", cmd = "craft" },
        { "Known recipes", I .. "Trade_Tailoring", "Recipes the addon knows for the material tips (open your professions once).", cmd = "recipes" },
        { "Auction helper", I .. "INV_Misc_Coin_17", "At the auction house: what in your bags is worth posting, one click per auction; and a buy mode.", toggle = Option("ahHelper", true) },
        { "Vendor helper", I .. "INV_Misc_Bag_08", "At the vendor: what you should sell there.", toggle = Option("vendorHelper", true) },
        { "Crafting profit", I .. "Trade_Engraving", "Profit of every recipe in the profession window.", toggle = Option("craftProfit", true) },
        { "Who needs materials", I .. "Trade_Herbalism", "Tooltip line on a material a friend needs for a recipe.", toggle = Option("needs", true) },
        { "Auto repair", I .. "Trade_BlackSmithing", "Repairs everything at a vendor that can repair.", toggle = Qol("repair") },
        { "Buy water", I .. "INV_Drink_07", "Mana classes from level 10: tops up to 20 of the best water.", toggle = Qol("water") },
        { "Buy ammo", I .. "INV_Ammo_Arrow_02", "Hunters: fills the quiver or ammo pouch.", toggle = Qol("ammo") },
    } },
    { key = "fun", title = "Fun and practice", items = {
        { "Make a bet", I .. "INV_Misc_Coin_02", "Bet with the friends: first to die, most damage, most yards... The losers pay by mail.", cmd = "bet" },
        { "Practice alone", I .. "INV_Misc_Head_Human_01", "Two pretend friends live on your client only, to try bets alone.", cmd = "sim", arg = "2" },
        { "Stop practice", I .. "Spell_Shadow_RaiseDead", "The pretend friends go away with their bets.", cmd = "sim", arg = "off" },
    } },
    { key = "options", title = "Options and help", items = {
        { "Quick options", I .. "INV_Misc_Gear_01", "One switch per category and the snooze.", cmd = "options" },
        { "All options", I .. "INV_Misc_Gear_01", "Every option of the party side.", cmd = "settings" },
        { "Feature list", I .. "INV_Misc_Book_09", "Everything the party side does.", cmd = "features" },
        { "Move mode", I .. "INV_Gizmo_02", "Drag the arrow and the alert cards; click again to lock.",
          toggle = { get = Call("Arrow", "IsMoveMode"), set = Call("Arrow", "ToggleMoveMode") } },
        { "Minimap icon", I .. "INV_Misc_Map_01", "Shows or hides the icon of the party side.", cmd = "minimap" },
        { "Sounds", I .. "INV_Misc_Note_01", "Soft sounds of the game for cards and bets.", toggle = Option("sound", false) },
        { "Commands in chat", I .. "INV_Misc_QuestionMark", "Every /blato command with a line about it.",
          hint = "/blato help", click = function() if SlashCmdList.BLATOPARTY then SlashCmdList.BLATOPARTY("help") end end },
        { "Errors", I .. "INV_Misc_Bone_HumanSkull_01", "The last errors saved on this computer, for bug reports. Nothing is sent anywhere.", cmd = "errors" },
    } },
}
