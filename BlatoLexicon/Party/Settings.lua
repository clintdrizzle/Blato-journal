-- One More Quest: settings registry
-- One list of everything that can be switched or adjusted. The full options
-- window is drawn from it, and the quick options can be built from it as well.
-- Item types: check (get/set), step (get/set/min/max/by), button (label/click).
local ADDON, OMQ = ...
OMQ = _G.BlatoParty

local S = {}
OMQ.Settings = S

local function qolGet(k) return function() return OMQ.db.options.qol[k] ~= false end end
local function qolSet(k) return function(v) OMQ.db.options.qol[k] = v and true or false end end

local LABEL = {
    train = "Train skills (even levels, in a city)",
    drink = "Drink (mana below 30%)",
    repair = "Repair (gear below 30%)",
    rank = "Spells not on a bar",
    prof = "Profession training",
    tools = "Profession tools (buy hammer, pick, knife...)",
    tracking = "Profession tracking (Find Minerals, Find Herbs)",
    groupdrink = "A friend is drinking (mana break)",
    pet = "Pet basics (call, revive, feed, summon)",
    flightfollow = "A friend took a flight: follow him",
    buff = "Missing buffs",
    talent = "Unspent talent points",
    ammo = "Ammo below 200",
}

local function alertItems()
    local out = {}
    for _, id in ipairs(OMQ.Alerts.ruleOrder) do
        local rule = OMQ.Alerts.rules[id]
        if id == "consumable" then
            -- decision 266: when to remind of the bought buff items, and a reset for the cards clicked away
            out[#out + 1] = { type = "segment", label = "Consumable reminders",
                tip = "Never: no reminders. Always: whenever you are out in the world (not in a city or an inn) and in dungeons. Dungeons: only in dungeons. A right click hides a reminder for good; in dungeons that counts separately, for every future dungeon.",
                options = { "Never", "Always", "Dungeons" },
                get = function()
                    local m = OMQ.db.options.consumeMode or "dungeon"
                    return (m == "never" and 1) or (m == "always" and 2) or 3
                end,
                set = function(i)
                    OMQ.db.options.consumeMode = ({ "never", "always", "dungeon" })[i] or "dungeon"
                    OMQ.Alerts:Evaluate()
                end }
            out[#out + 1] = { type = "button", indent = true, label = "Reset consumable reminders",
                done = "Done - consumable reminders are back",
                click = function() OMQ.Alerts:ResetConsumables() end }
        else
        out[#out + 1] = {
            type = "check",
            label = LABEL[id] or rule.name or id,
            get = function() return OMQ.Alerts:IsRuleSet(id) end,
            set = function(v) OMQ.db.alerts.enabled[id] = v and true or false; OMQ.Alerts:Evaluate() end,
        }
        if id == "rank" then
            out[#out + 1] = { type = "check", indent = true, label = "Spell not max rank",
                tip = "Checked: the highest learned rank of a spell has to be on a bar. Unchecked: any rank is fine.",
                get = function() return not OMQ.db.alerts.lenientRank end,
                set = function(v) OMQ.db.alerts.lenientRank = not v; OMQ.Alerts:Evaluate() end }
        elseif id == "buff" then
            out[#out + 1] = { type = "check", indent = true, label = "Buff tracking for players without the addon",
                tip = "Checked: missing buffs are shown for every group member. Unchecked: only for players with the addon.",
                get = function() return not OMQ.db.options.buffOnlyAddon end,
                set = function(v) OMQ.db.options.buffOnlyAddon = not v; OMQ.Alerts:Evaluate() end }
        end
        end
    end
    return out
end

S._AlertItems = function() return alertItems() end

-- Master switches: one per category, they override the fine grained options.
S.masters = {
    { id = "alerts", label = "Alerts" },
    { id = "group", label = "Group" },
    { id = "guidance", label = "Guidance" },
    { id = "vendor", label = "Automations" },   -- shown as "Automations" since decision 319; the id stays
}

function S:MasterGet(id) return OMQ:Master(id) end
function S:MasterSet(id, v)
    OMQ.db.options.master = OMQ.db.options.master or {}
    OMQ.db.options.master[id] = v and true or false
    if id == "alerts" and OMQ.Alerts then OMQ.Alerts:Evaluate()
    elseif id == "guidance" then
        if not v and OMQ.Guide then OMQ.Guide:Clear() end
        if OMQ.GuideBar then OMQ.GuideBar:Refresh() end
    end
end

-- 30 minute snooze, shared by both option windows
function S:SnoozeToggle()
    if OMQ.Alerts:IsSnoozed() then OMQ.db.options.snoozeUntil = 0
    else OMQ.db.options.snoozeUntil = time() + 30 * 60 end
    OMQ.Alerts:Evaluate()
end
function S:SnoozeLabel(idle)
    if OMQ.Alerts:IsSnoozed() then
        local left = math.max(1, math.ceil((OMQ.db.options.snoozeUntil - time()) / 60))
        return "Snoozed (" .. left .. " min) - resume"
    end
    return idle
end

local function append(dst, src) for _, v in ipairs(src) do dst[#dst + 1] = v end end

function S:Sections()
    local alerts = alertItems()
    append(alerts, {
        { type = "button",
          label = function() return S:SnoozeLabel("Snooze all alerts 30 min") end,
          click = function() S:SnoozeToggle() end },
        { type = "button", label = "Bring back dismissed alerts", done = "Done - dismissed alerts are back",
          click = function() OMQ.Alerts:ResetDismissed() end },
    })

    return {
        { title = "ALERTS", master = "alerts", col = 1, items = alerts },
        { title = "GROUP", master = "group", col = 1, items = {
            { type = "check", label = "Quest sync with the group",
              tip = "Exchange quest lists with the group. Quests are shared when someone accepts them.",
              get = function() return OMQ.db.options.questSync end,
              set = function(v) OMQ.db.options.questSync = v and true or false end },
            { type = "check", indent = true, label = "Share and accept quests automatically",
              tip = "A quest you accept is shared once with the group after a second; shared quests are accepted silently. Only between friends at most 5 levels apart. A new member starts one sync round.",
              get = function() return OMQ.db.options.autoShare ~= false end,
              set = function(v) OMQ.db.options.autoShare = v and true or false end },
            { type = "check", label = "Alt on an item: compare with the group",
              tip = "Hold Alt while hovering an item to see how it compares for every group member.",
              get = function() return OMQ.db.options.compare ~= false end,
              set = function(v) OMQ.db.options.compare = v and true or false end },
            { type = "check", label = "Show who needs a crafting material",
              tip = "Tooltip line on green or better materials a group member needs for a recipe.",
              get = function() return OMQ.db.options.needs ~= false end,
              set = function(v) OMQ.db.options.needs = v and true or false end },
            { type = "check", label = "Show Quest Tracker",
              tip = "Shows the quest progress of every friend when anyone in the group makes progress. Hides 60 seconds after the last progress; right click closes it. Your own progress is always sent to the others.",
              get = function() return OMQ.db.options.qtrack ~= false end,
              set = function(v) OMQ.db.options.qtrack = v and true or false end },
            -- decision 209: three-way toggle for the tracker background
            { type = "segment", indent = true, label = "Tracker background",
              tip = "None: only the text, with a shadow. Light: a see-through card. Full: the dark card.",
              options = { "None", "Light", "Full" },
              get = function()
                  local f = OMQ.QTrackFrame
                  local cur = f and f:Background() or "none"
                  for i, b in ipairs(f and f.BACKGROUNDS or { "none" }) do if b == cur then return i end end
                  return 1
              end,
              set = function(i)
                  local f = OMQ.QTrackFrame
                  if f and f.BACKGROUNDS[i] then f:SetBackground(f.BACKGROUNDS[i]) end
              end },
            -- decisions 334, 335: the threat meter
            { type = "segment", label = "Threat meter",
              tip = "A small frame with the threat of everyone in your group on your target, in percent (100 = he is the target). In group: whenever you are in a group. Dungeons: only inside a dungeon or raid. Place it in the move mode; /blato threat reset puts it back.",
              options = { "In group", "Dungeons", "Never" },
              get = function()
                  local m = OMQ.ThreatMeter and OMQ.ThreatMeter.Mode() or "group"
                  return (m == "group" and 1) or (m == "dungeon" and 2) or 3
              end,
              set = function(i)
                  OMQ.db.options.threatMode = ({ "group", "dungeon", "never" })[i] or "group"
                  OMQ.db.options.threat = nil
                  if OMQ.ThreatMeter then OMQ.ThreatMeter.Refresh() end
              end },
            { type = "check", label = "Follow group members on flights",
              tip = "If a member flies somewhere, your flight master picks the same destination.",
              get = qolGet("flight"), set = qolSet("flight") },
            -- decision 203: the role for the item score, as spec icons
            { type = "choice", label = "Preferred Role", names = true,
              tip = "Your role for the item score the other friends see on Alt. The stats of an item are weighted for your class and this role. Damage is the default.",
              options = (function()
                  local out = {}
                  for i, r in ipairs(OMQ.Score and OMQ.Score.RoleChoices() or {}) do
                      out[i] = { label = r.short, tipText = r.label, icon = r.icon }
                  end
                  return out
              end)(),
              get = function()
                  if not OMQ.Score then return 1 end
                  local cur = OMQ.Score.MyRole()
                  for i, r in ipairs(OMQ.Score.RoleChoices()) do if r.id == cur then return i end end
                  return 1
              end,
              set = function(v)
                  local r = OMQ.Score and OMQ.Score.RoleChoices()[v]
                  if r then OMQ.Score.SetMyRole(r.id) end
              end },
        } },
        { title = "GUIDANCE", master = "guidance", col = 2, items = {
            { type = "check", label = "Arrow to far away group members",
              get = function() return OMQ.db.arrow.enabled ~= false end,
              set = function(v) OMQ.db.arrow.enabled = v and true or false end },
            { type = "step", label = "Arrow appears beyond", unit = "yd", min = 20, max = 500, by = 10,
              get = function() return OMQ.db.arrow.threshold or 120 end,
              set = function(v) OMQ.Arrow:SetThreshold(v) end },
            { type = "check", label = "Show the icon bar",
              get = function() return OMQ.db.guide.bar end,
              set = function(v) OMQ.GuideBar:SetShown(v) end },
            { type = "check", label = "Follow pin and meeting point of the group",
              get = function() return OMQ.db.guide.receive ~= false end,
              set = function(v) OMQ.db.guide.receive = v and true or false end },
            { type = "check", label = "Share learned places with the group",
              tip = "Vendors, trainers, mailboxes and other places you have used are sent to group members with the addon, and theirs are added to your arrow targets.",
              get = function() return OMQ.db.guide.sharePlaces ~= false end,
              set = function(v) OMQ.db.guide.sharePlaces = v and true or false end },
            { type = "check", label = "Send Location Marker",
              tip = "Your map pin is sent to group members with the addon. Switched off, your pin is not sent and nobody's navigation gets it (useful with pin addons such as TomTom or Azimuth). The meeting point is still sent when you set it.",
              get = function() return OMQ.db.guide.share ~= false end,
              set = function(v) OMQ.db.guide.share = v and true or false end },
            { type = "button",
              label = function()
                  return OMQ.Arrow:IsMoveMode() and "Move mode ON - click to lock" or "Move arrow, alerts, bars, lists, tracker"
              end,
              click = function() OMQ.Arrow:ToggleMoveMode() end },
            { type = "choice", label = "Arrow style",
              tip = "Click the arrow you want: war arrowhead (default), rune chevrons, compass needle or crystal.",
              options = (OMQ.Arrow and OMQ.Arrow.StyleChoices) and OMQ.Arrow:StyleChoices() or {},
              get = function() return OMQ.Arrow and OMQ.Arrow:Style() or 1 end,
              set = function(v) if OMQ.Arrow then OMQ.Arrow:SetStyle(v) end end },
            { type = "button", label = "Recalibrate arrow", done = "Run in a few directions",
              click = function() OMQ:RunCommand("arrow", "recalibrate") end },
        } },
        { title = "AUTOMATIONS", master = "vendor", col = 2, items = {
            { type = "check", label = "Repair gear automatically", get = qolGet("repair"), set = qolSet("repair") },
            { type = "check", label = "Sell grey items automatically", get = qolGet("junk"), set = qolSet("junk"),
              tip = "Also sells what the auction helper found not worth the auction house (under +5%), unless it can be worn." },
            -- decision 259
            { type = "check", label = "Auction helper at the auction house",
              tip = "Lists what in your bags brings at least 5% more on the auction house than at the vendor and posts it with one click per auction. Fast mode: one button. Select mode: one row per item. Buy: weapon upgrades and the buff items of your class, stock up with one click per item.",
              get = function() return OMQ.db.options.ahHelper ~= false end,
              set = function(v) OMQ.db.options.ahHelper = v and true or false end },
            -- decision 341: auction prices of everything and the crafting profit
            { type = "check", label = "Scan all auction prices when the auction house opens",
              tip = "Reads the whole auction house once an hour (it gives way to the auction helper) and keeps the lowest price of every item. The crafting profit uses these prices. /blato prices scan starts a scan by hand.",
              get = function() return OMQ.db.options.priceScan ~= false end,
              set = function(v) OMQ.db.options.priceScan = v and true or false end },
            { type = "check", label = "Crafting profit in the profession window",
              tip = "Shows next to every recipe what it earns on the auction house (product price minus 5% cut minus the materials, from the scanned prices and the vendor prices you have seen) and a block with the numbers under the materials of the selected recipe.",
              get = function() return OMQ.db.options.craftProfit ~= false end,
              set = function(v) OMQ.db.options.craftProfit = v and true or false end },
            -- decision 292
            { type = "check", label = "Vendor helper at the vendor",
              tip = "A window next to the vendor lists what you should sell there: grey items, gear not worth the auction house or unsold twice, white items worth no more there than here, and bound gear worse than what you wear. A click sells one item, a button sells all.",
              get = function() return OMQ.db.options.vendorHelper ~= false end,
              set = function(v) OMQ.db.options.vendorHelper = v and true or false end },
            { type = "check", label = "Buy water (mana classes)", get = qolGet("water"), set = qolSet("water"),
              tip = "From level 10: tops the bags up to 20 of the best water the merchant sells. Before level 10 it costs too much." },
            { type = "check", label = "Buy ammo (hunters)", get = qolGet("ammo"), set = qolSet("ammo"),
              tip = "Fills the free room of the quiver or ammo pouch: arrows for a bow or crossbow, bullets for a gun. Never more than fits." },
            { type = "check", label = "Open all mail at the mailbox",
              tip = "When you open a mailbox, money and items of every mail are taken (not cash on delivery). Switched off, only the Bláto bet mails are opened. Bet mails are always deleted once empty.",
              get = qolGet("openmail"), set = qolSet("openmail") },
            { type = "check", label = "Close the mailbox after bet mail",
              tip = "After bet earnings are collected or bet debts are paid, the mailbox closes by itself.",
              get = function() return OMQ.db.options.qol.closemail == true end, set = qolSet("closemail") },
        } },
        { title = "INTERFACE", col = 2, items = {
            { type = "check", label = "Minimap icon",
              tip = "If hidden: /blato options opens the quick options, /blato minimap brings the icon back.",
              get = function() return not OMQ.db.minimap.hidden end,
              set = function(v) OMQ.Minimap:SetHidden(not v) end },
            { type = "check", label = "Sounds",
              tip = "Soft sounds of the game when something changes: a new alert card or popup, quest tracker progress, a stamp, a milestone or a won bet, and when a bet or vote starts. They follow your effects volume.",
              get = function() return OMQ.db.options.sound == true end,
              set = function(v) OMQ.db.options.sound = v and true or false end },
            { type = "check", label = "Hide Objective Tracker",
              tip = "Hides the quest tracker on the screen. The game shows it again after login, reload and quest changes; the addon hides it each time. Switch off to see it again.",
              get = function() return OMQ.Tracker:Wanted() end,
              set = function(v) OMQ.Tracker:SetHidden(v) end },
            { type = "button", label = "Open lifetime statistics", closeOptions = true,
              click = function() OMQ:Fire("MINIMAP_LEFT_CLICK") end },
            { type = "button", label = "Reset all positions", done = "Positions reset",
              click = function()
                  OMQ:RunCommand("arrow", "reset"); OMQ:RunCommand("bar", "reset"); OMQ:RunCommand("alerts", "position"); OMQ:RunCommand("qtrack", "position")
              end },
        } },
    }
end

-- tells both option windows to redraw
function S:Changed(source)
    if source ~= "quick" and OMQ.Options then OMQ.Options:Refresh() end
    if source ~= "full" and OMQ.OptionsFull then OMQ.OptionsFull:Refresh() end
end

OMQ:On("SETTINGS_CHANGED", function(source) S:Changed(source) end)
