-- One More Quest: Core
-- Namespace, event bus, saved variables, player identity.
-- Blato Lexicon: the party features get a table of their own, so they never share fields with the journal
-- (ns.J, ns.UI, ns.Kit); the journal reaches them as ns.OMQ.
local ADDON, ns = ...
local OMQ = {}
ns.OMQ = OMQ
_G.BlatoParty = OMQ

OMQ.name = "Bláto"
OMQ.version = "0.54.42"

-- the last bag to look into for what I carry: the reagent bag too, if the client has one (decision 272)
function OMQ.LastBag()
    local n = NUM_BAG_SLOTS or 4
    local reagent = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
    if type(reagent) == "number" and reagent > n then n = reagent end
    if type(NUM_TOTAL_EQUIPPED_BAG_SLOTS) == "number" and NUM_TOTAL_EQUIPPED_BAG_SLOTS > n then n = NUM_TOTAL_EQUIPPED_BAG_SLOTS end
    return n
end
OMQ.protocol = 1

----------------------------------------------------------------------
-- Defaults and saved variables
----------------------------------------------------------------------
local DEFAULTS = {
    minimap = { angle = 150, hidden = false },     -- default layout (decision 190)
    options = {
        questSync = true,
        autoShare = true,
        snoozeUntil = 0,
        buffOnlyAddon = false,
        compare = true,
        needs = true,
        sound = false,               -- soft sounds, off by default (decision 185)
        master = { alerts = true, group = true, guidance = true, vendor = true, chat = true },
        chatWords = "",
        qol = { repair = true, water = true, ammo = true, flight = true, openmail = true, closemail = false },
    },
    alerts = { enabled = {}, lenientRank = false },
    arrow = { threshold = 120, enabled = true, style = 1 },     -- style: decision 192
    guide = { sharePlaces = true },   -- learned places feed the alert cards (Guide/Places.lua)
    quests = { ignored = {}, titles = {} },
}

local function copyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

function OMQ:InitDB()
    BlatoPartyDB = BlatoPartyDB or {}
    copyDefaults(DEFAULTS, BlatoPartyDB)
    self.db = BlatoPartyDB
end

----------------------------------------------------------------------
-- Small event bus: modules talk through this, not through each other
----------------------------------------------------------------------
local handlers = {}

function OMQ:On(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
end

function OMQ:Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then self:Error(event, err) end
    end
end

----------------------------------------------------------------------
-- Output helpers
----------------------------------------------------------------------
function OMQ:Print(msg)
    print("|cffe2b64bBláto:|r " .. tostring(msg))
end

function OMQ:Error(where, err)
    -- in the log that survives a reload (ErrorLog.lua), first: the lines below can fail on a secret value
    if ns.ErrorLog then ns.ErrorLog.Add("party", where, err) end
    -- Never spam; keep the last errors for /blato debug
    self.errors = self.errors or {}
    table.insert(self.errors, tostring(where) .. ": " .. tostring(err))
    if #self.errors > 20 then table.remove(self.errors, 1) end
end

----------------------------------------------------------------------
-- Identity. Characters have two-part names on WoW Forever, so players
-- are always identified by GUID, never by name.
----------------------------------------------------------------------
function OMQ:GetSelf()
    if self.me then return self.me end
    local guid = UnitGUID("player")
    if not guid then return nil end
    local first, second = UnitName("player")
    local _, classToken = UnitClass("player")
    self.me = {
        guid = guid,
        name = first or "?",
        fullName = second and second ~= "" and (first .. " " .. second) or first,
        class = classToken,
        version = self.version,
        isSelf = true,
    }
    return self.me
end

----------------------------------------------------------------------
-- Slash commands. "/blato" alone is reserved for the vote (step 8).
----------------------------------------------------------------------
local commands = {}

function OMQ:RegisterCommand(name, fn, help)
    commands[name] = { fn = fn, help = help }
end

-- Master switches of the option categories (alerts, group, guidance, vendor)
function OMQ:Master(name)
    local m = OMQ.db and OMQ.db.options and OMQ.db.options.master
    return not m or m[name] ~= false
end

function OMQ:QuestSyncOn()
    return OMQ:Master("group") and OMQ.db.options.questSync and true or false
end

-- automatic sharing (the leader pushes, the others accept silently) needs quest sync too
function OMQ:QuestShareOn()
    return OMQ:QuestSyncOn() and OMQ.db.options.autoShare ~= false
end

-- Runs a registered command from code (used by the options windows)
function OMQ:RunCommand(name, arg)
    local c = commands[name]
    if c then
        local ok, err = pcall(c.fn, arg or "")
        if not ok then OMQ:Error("/blato " .. name, err) end
    end
end

SLASH_BLATOPARTY1 = "/blato"
SlashCmdList["BLATOPARTY"] = function(input)
    input = (input or ""):match("^%s*(.-)%s*$")
    local cmd, rest = input:match("^(%S+)%s*(.*)$")
    if not cmd then
        -- Blato Lexicon: "/blato" alone opens the journal on the Commands page; the vote is "/blato sleep"
        if ns.UI and ns.UI.Show then ns.UI.Show("commands") else OMQ:Fire("SLASH_EMPTY") end
        return
    end
    cmd = cmd:lower()
    if cmd == "help" then
        OMQ:Print("commands:")
        local names = {}
        for n in pairs(commands) do names[#names + 1] = n end
        table.sort(names)
        for _, n in ipairs(names) do
            print("  /blato " .. n .. " - " .. (commands[n].help or ""))
        end
        return
    end
    local c = commands[cmd]
    if c then
        local ok, err = pcall(c.fn, rest)
        if not ok then OMQ:Error("/blato " .. cmd, err); OMQ:Print("error: " .. tostring(err)) end
    else
        OMQ:Print("unknown command. Type /blato help")
    end
end

OMQ:RegisterCommand("debug", function()
    local me = OMQ:GetSelf()
    OMQ:Print("version " .. OMQ.version .. ", protocol " .. OMQ.protocol)
    if me then print("  me: " .. me.name .. " (" .. tostring(me.class) .. ") " .. me.guid) end
    local n = 0
    for _ in pairs(OMQ.users or {}) do n = n + 1 end
    print("  addon users known: " .. n)
    print("  errors: " .. #(OMQ.errors or {}))
    for _, e in ipairs(OMQ.errors or {}) do print("   " .. e) end
    print("  saved errors: " .. #ns.ErrorLog.List() .. " (/blato errors)")
end, "show internal state")

-- Blato Lexicon: the log of ErrorLog.lua
OMQ:RegisterCommand("errors", function(arg)
    local Log = ns.ErrorLog
    arg = (arg or ""):lower()
    if arg == "clear" then
        Log.Clear()
        OMQ:Print("the error log is empty now")
    elseif arg == "test" then
        OMQ:Print("a test error follows, nothing is wrong. /blato errors should list it then.")
        C_Timer.After(0, function() error("BlatoLexicon: a test of the error log, nothing is wrong") end)
    else
        local list = Log.List()
        OMQ:Print(#list .. " errors saved on this computer" .. (#list > 0 and ", the last ones:" or "."))
        for i = #list, math.max(1, #list - 4), -1 do
            local e = list[i]
            local tag = e.where and (e.kind .. " " .. e.where) or e.kind
            print(string.format("  %s x%d [%s] %s", e.last or "?", e.count or 1, tag, e.message))
        end
    end
end, "errors saved on this computer: the last five | clear | test")

OMQ:RegisterCommand("sleep", function() OMQ:Fire("SLASH_EMPTY") end, "One more quest? or Bed time: start the group vote")

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        OMQ:InitDB()
        OMQ:Fire("DB_READY")
    elseif event == "PLAYER_LOGIN" then
        OMQ:GetSelf()
        OMQ:Fire("READY")
    end
end)
