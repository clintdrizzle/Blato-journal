-- One More Quest: dad simulator (decision 177), /blato sim
-- Up to three fake dads that live only on this client, to try Bet Check alone. While the simulator runs, every addon message goes to the fake dads instead of
-- the party (Comm.lua), so real players never see simulated data. The fake dads answer like real
-- clients: they join or skip bets, report values, pay or get paid.
-- Blato Lexicon: their full names are made up and Bet/Mail.lua never mails a fake dad (the original sent
-- real mail to the author's alts). The default is 2 fake dads: you and two friends, the Bláto party of three.
--   /blato sim [1-3]                   start with 1 to 3 fake dads (default 2); again: status
--   /blato sim off                     stop; fake dads, their bets and their ledger entries are removed
--   /blato sim bet <kind> [name]       a fake dad starts a bet (death dmg run near npc player fall kb loot roll)
--   /blato sim die|kb|near|target <name>   the event for a running "first" bet
--   /blato sim fight                   the fake dads report their damage for "top damage in the next fight"
local ADDON, OMQ = ...
OMQ = _G.BlatoParty

local S = { active = false }
OMQ.Sim = S

local ROSTER = {
    { name = "Karle",     full = "Sim Karle",     class = "WARRIOR" },
    { name = "Melchior",  full = "Sim Melchior",  class = "MAGE" },
    { name = "Sieglinde", full = "Sim Sieglinde", class = "PRIEST" },
}
S.ROSTER = ROSTER
local JOIN_CHANCE = 0.8

local dads = {}                          -- { guid, name, full, class }
local byGuid = {}
local guids = {}
local ticker
local paidNote = {}
local compareAnswer                      -- defined below (gear of Sim Karle)

local function now() return GetTime() end
local function say(t) OMQ:Print("|cff9fd3ffsim|r " .. t) end
local function rnd(a, b) return math.random(a, b) end

function S:IsSim(guid) return self.active and byGuid[guid] ~= nil or false end
function S:Guids() return guids end
function S:Dads() return dads end

local function deliver(d, msgType, ...)
    local text = OMQ.Encode(msgType, OMQ.protocol, ...)
    if text then OMQ:SimDeliver(text, d.name) end
end

local function later(sec, fn)
    C_Timer.After(sec, function()
        if not S.active then return end
        local ok, err = pcall(fn)
        if not ok then OMQ:Error("sim", err) end
    end)
end
S._later = later

local function hello(d) deliver(d, "H", d.guid, d.name, OMQ.version .. "-sim", d.class, d.full) end

local function find(name)
    if not name or name == "" then return nil end
    name = name:lower()
    for _, d in ipairs(dads) do
        if d.name:lower():sub(1, #name) == name or d.full:lower() == name then return d end
    end
end

local function randomDad() return dads[rnd(1, #dads)] end

----------------------------------------------------------------------
-- Bets
----------------------------------------------------------------------
local function B() return OMQ.Bets end

local function pickFor()
    local list = B().Dads()
    return list[rnd(1, #list)].guid
end

local function joinLater(d, id, pick)
    later(rnd(20, 60) / 10, function()
        local b = B():Get(id)
        if not b or b.state ~= "join" or b.answers[d.guid] ~= nil then return end
        if pick or math.random() < JOIN_CHANCE then
            deliver(d, "BJ", id, d.guid, pick or pickFor(), "1")
        else
            deliver(d, "BJ", id, d.guid, "-", "0")
        end
    end)
end

local function value(d, id, v) deliver(d, "BV", id, d.guid, string.format("%.0f", v)) end

local function bettor(b, d) return b.answers[d.guid] and true or false end

-- value bets: the fake dads report when a real client would
local function scheduleValues(b)
    local k = B().KIND[b.kind]
    for _, d in ipairs(dads) do
        if bettor(b, d) then
            if k.roll then
                later(rnd(10, 30) / 10, function() value(d, b.id, rnd(1, 100)) end)
            elseif k.seconds and k.mode == "value" then
                local v
                if b.kind == "run" then v = rnd(40, 600)
                elseif b.kind == "loot" then v = rnd(0, 3000)
                elseif b.kind == "fall" then v = (math.random() < 0.2) and -1 or rnd(0, 450) end
                later(k.seconds - rnd(5, 20) / 10, function()
                    local cur = B():Get(b.id)
                    if cur and cur.state == "active" then value(d, b.id, v) end
                end)
            end
        end
    end
end

local function fightValues(id)
    local b = B():Get(id)
    if not b or b.state ~= "active" or b.simFought then return end
    b.simFought = true
    for _, d in ipairs(dads) do
        if bettor(b, d) then later(rnd(5, 25) / 10, function() value(d, id, rnd(100, 2500)) end) end
    end
end

-- what my client sends, seen by the fake dads
function S:Outgoing(text)
    local msgType, _, f = OMQ.Decode(text)
    if not msgType then return end
    later(0.1, function()
        if msgType == "BS" then
            for _, d in ipairs(dads) do joinLater(d, f[1]) end
        elseif msgType == "BA" and f[2] == "on" then
            local b = B():Get(f[1])
            if b then scheduleValues(b) end
        elseif msgType == "BV" then
            local b = B():Get(f[1])
            if b and b.kind == "dmg" then fightValues(b.id) end
        elseif msgType == "BR" then
            local b = B():Get(f[1])
            local m = OMQ:GetSelf()
            for _, p in ipairs((b and b.pays) or {}) do
                local d = byGuid[p.from]
                if d and m and p.to == m.guid and not paidNote[b.id .. p.from] then
                    paidNote[b.id .. p.from] = true
                    later(5, function()
                        deliver(d, "BP", b.id, d.guid, m.guid, tostring(p.amount))
                        say(string.format("%s paid %s by mail (simulated: no real mail arrives)", d.name, B().Money(p.amount)))
                    end)
                end
            end
        elseif msgType == "IQ" then
            -- Alt on an item: every fake dad compares it with what he wears
            if f[1] and f[3] then
                for i, d in ipairs(dads) do later(0.2 + i * 0.1, function() compareAnswer(d, f[1], f[3], 0) end) end
            end
        end
    end)
end

-- a fake dad starts a bet; my client decides it for him (Bets.lua isJudge)
function S:StartBet(d, kind)
    local k = B().KIND[kind]
    if not k then return false, "unknown bet kind: " .. tostring(kind) end
    local n, running = 0, false
    for _, b in ipairs(B():Running()) do
        n = n + 1
        if b.kind == kind then running = true end
    end
    if n >= B().MAX_RUNNING then return false, "three bets are running already" end
    if running then return false, "a bet of this kind is running already" end
    local letter = ""
    if k.letter then
        local L = "ABDEFGHKLMNPRST"
        local i = rnd(1, #L)
        letter = L:sub(i, i)
    end
    local id = tostring(time()) .. "sim" .. rnd(100, 999)
    local stake = math.min(1000, B().MaxStake())
    deliver(d, "BS", id, d.guid, kind, tostring(stake), letter)
    deliver(d, "BJ", id, d.guid, pickFor(), "1")
    for _, o in ipairs(dads) do if o ~= d then joinLater(o, id) end end
    return true, id
end

-- the event of a "first" bet happens to a fake dad
function S:Event(d, what)
    local kinds = { die = "death", kb = "kb", near = "near", target = "letter" }
    local want = kinds[what]
    local hit = false
    for _, b in ipairs(B():Running()) do
        if b.state == "active" and (b.kind == want or (want == "letter" and b.letter)) then
            value(d, b.id, 1)
            hit = true
        end
    end
    return hit
end

----------------------------------------------------------------------
-- Gear: every fake dad wears real items, so Alt on an item can be tried alone (decisions 194, 198).
-- Karle wears something in every slot; Melchior and Sieglinde wear cloth with a few empty slots.
----------------------------------------------------------------------
S.KARLE_GEAR = {
    [1] = 4385,  [2] = 4614,  [3] = 6461,  [4] = 2575,  [5] = 6627,  [6] = 6460,  [7] = 10410, [8] = 10411,
    [9] = 1974,  [10] = 10413, [11] = 6463, [12] = 1156, [13] = 4381, [14] = 4397, [15] = 6629, [16] = 5191, [17] = 6320,
    [18] = 6469,
}
S.GEAR = {
    Karle = S.KARLE_GEAR,
    Melchior = { [2] = 20442, [3] = 12998, [5] = 6465, [6] = 4785, [7] = 3563, [8] = 2232, [9] = 14402, [10] = 7047,
                 [11] = 2039, [12] = 20429, [16] = 2226 },
    Sieglinde = { [2] = 20442, [3] = 12998, [5] = 2292, [6] = 4827, [7] = 4723, [8] = 3065, [9] = 1351, [10] = 3074,
                  [11] = 5001, [12] = 12996, [16] = 3415 },
}
S.LEVEL_OFFSET = { Karle = 0, Melchior = -1, Sieglinde = 1 }
local function linkOf(id)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if info then
        local ok, name, link = pcall(info, id)
        if ok and type(link) == "string" then return link end
    end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    return "item:" .. id
end
function S.WornOf(d)
    local gear = S.GEAR[d.name] or {}
    return function(slot)
        local id = gear[slot]
        return id and linkOf(id) or nil
    end
end
function S.KarleWorn(slot) return S.WornOf({ name = "Karle" })(slot) end
local function levelOf(d)
    return math.max(1, math.min(60, (UnitLevel("player") or 1) + (S.LEVEL_OFFSET[d.name] or 0)))
end

-- a fake dad sends his gear like a real client (Gear.lua)
local function sendGear(d)
    if not OMQ.Gear then return end
    for _, data in ipairs(OMQ.Gear.Chunks(OMQ.Gear.SLOTS, function(slot)
        local gear = S.GEAR[d.name] or {}
        return gear[slot] and ("item:" .. gear[slot]) or nil
    end)) do
        deliver(d, "EQ", d.guid, tostring(levelOf(d)), data, d.name == "Sieglinde" and "heal" or "")
    end
end
S._sendGear = sendGear

compareAnswer = function(d, reqId, link, tries)
    if not (OMQ.Compare and OMQ.Compare.Evaluate) then return end
    local status, eqIlvl, eqName, st = OMQ.Compare.Evaluate(link, S.WornOf(d), levelOf(d))
    if not status and (tries or 0) < 2 then
        later(0.7, function() compareAnswer(d, reqId, link, (tries or 0) + 1) end)
        return
    end
    if not status then status, eqIlvl, eqName, st = "?", "-", "-", "-" end
    deliver(d, "IR", reqId, d.guid, status, eqIlvl, eqName, st, d.name, d.class)
end

----------------------------------------------------------------------
-- Start and stop
----------------------------------------------------------------------
local function tick()
    for _, d in ipairs(dads) do
        if now() - (d.helloAt or 0) > 60 then d.helloAt = now(); hello(d) end
    end
end

function S:Start(count)
    count = math.max(1, math.min(#ROSTER, tonumber(count) or 2))
    if self.active then self:Stop(true) end
    dads, byGuid, guids, paidNote = {}, {}, {}, {}
    for i = 1, count do
        local r = ROSTER[i]
        local d = { index = i, guid = string.format("Player-0-SIM%05d", i), name = r.name, full = r.full,
                    class = r.class }
        dads[i], byGuid[d.guid], guids[i] = d, d, d.guid
    end
    self.active = true
    if OMQ.ResetGroupCache then OMQ:ResetGroupCache() end
    for _, d in ipairs(dads) do d.helloAt = now(); hello(d) end
    for _, d in ipairs(dads) do sendGear(d) end
    if not ticker then ticker = C_Timer.NewTicker(1, function() if S.active then pcall(tick) end end) end
    local names = {}
    for _, d in ipairs(dads) do names[#names + 1] = d.full end
    say("on: " .. table.concat(names, ", ") .. ". Messages go to the fake friends only. /blato sim off ends it.")
    OMQ:Fire("ROSTER_CHANGED")
    OMQ:Fire("BETS_CHANGED")
    return true
end

function S:Stop(quiet)
    if not self.active then return end
    -- bets with fake dads are off, their ledger entries go
    if OMQ.Bets then
        for _, b in ipairs(B():List()) do
            local involved = byGuid[b.starter] ~= nil
            for g in pairs(b.answers or {}) do if byGuid[g] then involved = true end end
            if involved and (b.state == "join" or b.state == "active") then b.state, b.reason = "off", "simulation ended" end
        end
        local l = B().Ledger()
        for _, side in ipairs({ "owe", "get" }) do
            local keep = {}
            for _, e in ipairs(l[side]) do
                if not (byGuid[e.to] or byGuid[e.from]) then keep[#keep + 1] = e end
            end
            l[side] = keep
        end
    end
    for g in pairs(byGuid) do OMQ.users[g] = nil end
    self.active = false
    dads, byGuid, guids = {}, {}, {}
    if OMQ.ResetGroupCache then OMQ:ResetGroupCache() end
    OMQ:Fire("ROSTER_CHANGED")
    OMQ:Fire("BETS_CHANGED")
    if not quiet then say("off: fake friends, their bets and their debts are gone.") end
end

local function status()
    if not S.active then say("off. /blato sim [1-3] starts it."); return end
    for _, d in ipairs(dads) do say(string.format("%s (%s)", d.full, d.class)) end
    say("Commands: bet <kind> [name], die|kb|near|target <name>, fight, off")
end

OMQ:RegisterCommand("sim", function(arg)
    local cmd, rest = (arg or ""):match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()
    if cmd == "" or tonumber(cmd) then
        if S.active and cmd == "" then status() else S:Start(tonumber(cmd)) end
        return
    end
    if cmd == "off" then S:Stop(); return end
    if not S.active then say("start it first: /blato sim [1-3]"); return end
    if cmd == "bet" then
        local kind, who = rest:match("^(%S*)%s*(.-)$")
        local d = find(who) or randomDad()
        local ok, why = S:StartBet(d, (kind or ""):lower())
        say(ok and (d.name .. " starts a bet: " .. B().KIND[kind:lower()].name) or why)
    elseif cmd == "die" or cmd == "kb" or cmd == "near" or cmd == "target" then
        local d = find(rest)
        if not d then say("which fake friend? " .. cmd .. " Karle"); return end
        if not S:Event(d, cmd) then say("no running bet for that") end
    elseif cmd == "fight" then
        for _, b in ipairs(B():Running()) do if b.kind == "dmg" and b.state == "active" then fightValues(b.id) end end
    else
        status()
    end
end, "friend simulator: /blato sim [1-3] | off | bet <kind> [name] | die|kb|near|target <name> | fight")
