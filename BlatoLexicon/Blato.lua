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
        { "Share quests now", I .. "INV_Scroll_03", "Starts a sync round: everybody shares the quests the others are missing.", cmd = "quests", arg = "sync" },
        { "Quest tracker test", I .. "INV_Misc_Note_02", "Shows the group quest tracker with a demo card, to see where it sits.", cmd = "qtrack", arg = "demo" },
        { "Follow key", I .. "Ability_Mount_RidingHorse", "The key that follows the closest friend. Set it with /blato follow <key>.", cmd = "follow" },
        { "Quest sync", I .. "INV_Scroll_03", "Exchange quest lists with the party; quests are shared when someone accepts them.", toggle = Option("questSync", true) },
        { "Auto share", I .. "INV_Letter_15", "A quest you accept is shared once with the party, shared quests are accepted silently (friends at most 5 levels apart).", toggle = Option("autoShare", true) },
        { "Alt: compare items", I .. "INV_Sword_04", "Hold Alt over an item: how it compares for every friend.", toggle = Option("compare", true) },
        { "Group quest tracker", I .. "INV_Misc_Note_01", "Everybody's progress on the shared quests, shown when anybody makes progress.", toggle = Option("qtrack", true) },
        { "Follow flights", I .. "Ability_Mount_Gryphon_01", "A friend took a flight: your flight master picks the same destination.", toggle = Qol("flight") },
    } },
    { key = "onemore", title = "One more quest?", items = {
        { "Start the vote", I .. "INV_Misc_Coin_17", "One more quest! or Bed time. If one more quest wins, the arrow leads the party to the next quest everybody has.", cmd = "sleep" },
        { "My title", I .. "INV_Misc_Head_Dragon_01", "Pick tonight's title from the offers after a Bed time vote.", cmd = "title", arg = "pick" },
    } },
    { key = "way", title = "Finding the way", items = {
        { "Meeting point here", I .. "INV_BannerPVP_02", "Sets a meeting point where you stand; the arrow of every friend leads here.", cmd = "go", arg = "here" },
        { "Class trainer", I .. "INV_Misc_Book_09", "Arrow to the nearest trainer of your class.", cmd = "go", arg = "trainer" },
        { "Vendor", I .. "INV_Misc_Bag_07", "Arrow to the nearest vendor.", cmd = "go", arg = "vendor" },
        { "Repair", I .. "Trade_BlackSmithing", "Arrow to the nearest repair NPC.", cmd = "go", arg = "repair" },
        { "Flight master", I .. "Ability_Mount_Gryphon_01", "Arrow to the nearest flight master.", cmd = "go", arg = "flight" },
        { "Inn", I .. "INV_Misc_Rune_01", "Arrow to the nearest innkeeper (hearthstone).", cmd = "go", arg = "inn" },
        { "Mailbox", I .. "INV_Letter_15", "Arrow to the nearest mailbox.", cmd = "go", arg = "mailbox" },
        { "Bank", I .. "INV_Misc_Bag_10", "Arrow to the nearest bank.", cmd = "go", arg = "bank" },
        { "Auction house", I .. "INV_Misc_Coin_01", "Arrow to the nearest auction house.", cmd = "go", arg = "auction" },
        { "Map pin", I .. "INV_Misc_Map_01", "Arrow to your map pin.", cmd = "go", arg = "pin" },
        { "My corpse", I .. "Spell_Holy_GuardianSpirit", "Arrow to your corpse.", cmd = "go", arg = "corpse" },
        { "Stop the arrow", I .. "Ability_Rogue_FeignDeath", "Cancels the guidance.", cmd = "go", arg = "off" },
        { "Arrow to friends", I .. "Ability_Tracking", "An arrow to the others when they are far away (or you are).",
          toggle = { get = function() local o = OMQ(); return o and o.db and o.db.arrow.enabled ~= false or false end,
                     set = function(v) local o = OMQ(); if o and o.db then o.db.arrow.enabled = v end end } },
        { "Guidance bar", I .. "INV_Misc_Map_01", "The icon bar with the meeting point and the places.",
          toggle = { get = function() local o = OMQ(); return o and o.db and o.db.guide.bar and true or false end,
                     set = function(v) local o = OMQ(); if o and o.GuideBar then o.GuideBar:SetShown(v) end end } },
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
        { "Dungeon quests to take", I .. "INV_Misc_Key_03", "Dungeon quests you could take now, and where.", cmd = "dquests" },
    } },
    { key = "dungeons", title = "Dungeons", items = {
        { "Group check", I .. "INV_Misc_Bandage_15", "Durability, bags, drinks, class items and dungeon quests of every friend, plus the best boss loot for you.", cmd = "ready" },
        { "Progress check", I .. "Spell_Holy_SealOfWisdom", "Your milestones by level: class spells, dungeons and quest zones.", cmd = "progress" },
        { "Threat report", I .. "Ability_Warrior_Titansgrip", "Everybody's threat on your target, once (in the chat).", cmd = "threat" },
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
        { "Sell grey items", I .. "INV_Misc_Bone_HumanSkull_01", "Sells grey items at every vendor.", toggle = Qol("junk") },
        { "Buy water", I .. "INV_Drink_07", "Mana classes from level 10: tops up to 20 of the best water.", toggle = Qol("water") },
        { "Buy ammo", I .. "INV_Ammo_Arrow_02", "Hunters: fills the quiver or ammo pouch.", toggle = Qol("ammo") },
    } },
    { key = "fun", title = "Fun and practice", items = {
        { "Make a bet", I .. "INV_Misc_Coin_02", "Bet with the friends: first to die, most damage, most yards... The losers pay by mail.", cmd = "bet" },
        { "Practice alone", I .. "INV_Misc_Head_Human_01", "Two pretend friends live on your client only, to try bets and the quest tracker alone.", cmd = "sim", arg = "2" },
        { "Stop practice", I .. "Spell_Shadow_RaiseDead", "The pretend friends go away with their bets.", cmd = "sim", arg = "off" },
    } },
    { key = "options", title = "Options and help", items = {
        { "Quick options", I .. "INV_Misc_Gear_01", "One switch per category and the snooze.", cmd = "options" },
        { "All options", I .. "INV_Misc_Gear_01", "Every option of the party side.", cmd = "settings" },
        { "Feature list", I .. "INV_Misc_Book_09", "Everything the party side does.", cmd = "features" },
        { "Move mode", I .. "INV_Gizmo_02", "Drag the arrow, the alert cards, the bars, the lists and the tracker; click again to lock.",
          toggle = { get = Call("Arrow", "IsMoveMode"), set = Call("Arrow", "ToggleMoveMode") } },
        { "Minimap icon", I .. "INV_Misc_Map_01", "Shows or hides the icon of the party side.", cmd = "minimap" },
        { "Sounds", I .. "INV_Misc_Note_01", "Soft sounds of the game for cards, tracker and bets.", toggle = Option("sound", false) },
        { "Hide quest tracker", I .. "INV_Scroll_03", "Hides the game's own objective tracker.",
          toggle = { get = Call("Tracker", "Wanted"), set = function(v) local o = OMQ(); if o and o.Tracker then o.Tracker:SetHidden(v) end end } },
        { "Commands in chat", I .. "INV_Misc_QuestionMark", "Every /blato command with a line about it.",
          hint = "/blato help", click = function() if SlashCmdList.BLATOPARTY then SlashCmdList.BLATOPARTY("help") end end },
        { "Errors", I .. "INV_Misc_Bone_HumanSkull_01", "Version and the last errors, for bug reports.", cmd = "debug" },
    } },
}
