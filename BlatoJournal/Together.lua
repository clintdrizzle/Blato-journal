-- Bláto Journal: who of the three of you has done a quest, for the Quests page. Each game only knows its own
-- quests (IsQuestFlaggedCompleted), so the journals tell each other over the party's addon channel (Party/Comm.lua):
--   JQD|proto|name|questID|title       I handed this quest in just now
--   JQH|proto|reqId|name|id,id,...     have you done these? (up to ASK_CHUNK ids)
--   JQA|proto|reqId|name|marks         the answer, one mark per asked id: "1" done, "0" not done, "?" unknown
-- What the others answered is kept in the journal (H.questsBy[name][questID] = true or false), so it shows while
-- they are offline too. name is the full "First Last", the way the fellowship (Journal/Fellowship.lua) keys people.
-- Quests a friend handed in that you have not done are kept in H.partyQuests[questID] = { t, title, by = { name = t } }.
local _, ns = ...
local J, OMQ = ns.J, ns.OMQ
local H = J.H

local ASK_CHUNK, ASK_MAX, ASK_EVERY = 25, 120, 60   -- ids per question, ids per round, seconds between rounds
local TITLE_MAX = 60
local T = { asked = {}, lastAsk = 0 }
ns.Together = T

local function Me() return J.PlayerName() end
local function Plain(v) return type(v) == "string" and not (issecretvalue and issecretvalue(v)) and v ~= "" and v or nil end

-- true / false, or nil when the game does not say
local function Done(id)
    local f = (C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted) or IsQuestFlaggedCompleted
    if not (f and id) then return nil end
    local ok, v = pcall(f, id)
    if not ok or (issecretvalue and issecretvalue(v)) then return nil end
    return v and true or false
end
T.Done = Done

local function By(name)
    H.questsBy = H.questsBy or {}
    H.questsBy[name] = H.questsBy[name] or {}
    return H.questsBy[name]
end

-- One party member and a quest: true (done), false (not done) or nil (not known). with: the quest's partners
-- at hand-in (Journal/Chronicle.lua); somebody who had the quest with you then counts as done until they answer.
function T.Status(name, questID, with)
    if not questID then return nil end
    if name == Me() then return Done(questID) end
    local known = H.questsBy and H.questsBy[name] and H.questsBy[name][questID]
    if known ~= nil then return known end
    if with and with[name] then return true end
    return nil
end

-- Ask the party about the newest quests of the journal, at most once every ASK_EVERY seconds.
function T.AskRecent()
    if not (OMQ and OMQ:GetChannel()) or time() - T.lastAsk < ASK_EVERY then return end
    T.lastAsk = time()
    local ids, seen = {}, {}
    for i = #H.quests, 1, -1 do
        local id = H.quests[i].questID
        if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end
        if #ids >= ASK_MAX then break end
    end
    for id in pairs(H.partyQuests or {}) do
        if not seen[id] and #ids < ASK_MAX then seen[id] = true; ids[#ids + 1] = id end
    end
    for first = 1, #ids, ASK_CHUNK do
        local chunk = {}
        for i = first, math.min(first + ASK_CHUNK - 1, #ids) do chunk[#chunk + 1] = ids[i] end
        local reqId = tostring(math.random(100000, 999999))
        T.asked[reqId] = chunk
        OMQ:Send("JQH", reqId, Me(), table.concat(chunk, ","))
    end
end

if OMQ then
    OMQ:RegisterMessage("JQD", function(f)
        local name, id, title = f[1], tonumber(f[2]), f[3]
        if not (name and id) or name == Me() then return end
        By(name)[id] = true
        if Done(id) == false then
            H.partyQuests = H.partyQuests or {}
            local p = H.partyQuests[id] or { t = time(), by = {} }
            p.title = p.title or Plain(title)
            p.by[name] = p.by[name] or time()
            H.partyQuests[id] = p
        end
        J.Changed()
    end)
    OMQ:RegisterMessage("JQH", function(f)
        local reqId, name, list = f[1], f[2], f[3]
        if not (reqId and name and list) or name == Me() then return end
        local marks = {}
        for id in list:gmatch("%d+") do
            local d = Done(tonumber(id))
            marks[#marks + 1] = d == nil and "?" or (d and "1" or "0")
        end
        OMQ:Send("JQA", reqId, Me(), table.concat(marks))
    end)
    OMQ:RegisterMessage("JQA", function(f)
        local reqId, name, marks = f[1], f[2], f[3]
        local asked = T.asked[reqId]
        if not (asked and name and marks) or name == Me() then return end
        local by = By(name)
        for i, id in ipairs(asked) do
            local c = marks:sub(i, i)
            if c == "1" then by[id] = true elseif c == "0" then by[id] = false end
        end
        J.Changed()
    end)
end

-- Tell the party about each quest you hand in.
local ev = CreateFrame("Frame")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:SetScript("OnEvent", function(_, _, questID)
    questID = tonumber(questID)
    if not (questID and OMQ and OMQ:GetChannel()) then return end
    local ok, title = pcall(C_QuestLog.GetTitleForQuestID, questID)
    title = ok and Plain(title) or ""
    OMQ:Send("JQD", Me(), questID, title:sub(1, TITLE_MAX))
    if H.partyQuests then H.partyQuests[questID] = nil end   -- done by you now as well
end)
