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

-- The shared notepad --------------------------------------------------------------------------------------
-- A note marked shared (n.shared) goes to the party; theirs come back to you and are kept in
-- H.partyNotes[key] = { key, author, t, text, zone, level, hidden }. key = "<author>#<note id>", t = the note's
-- last change. A note is cut into parts that fit an addon message; "|" (item links) and new lines travel as
-- bytes the message channel keeps (\31 and \30).
--   JN|proto|key|part|parts|t|author|level|zone|text    one part of a shared note (sent again after an edit)
--   JNX|proto|key                                       the note is no longer shared (unshared, archived, deleted)
--   JNQ|proto|name                                      send me your shared notes (when the Notes page opens)
local NOTE_ASK_EVERY, NOTES_SENT, ZONE_MAX = 60, 40, 40
T.incoming, T.lastNoteAsk = {}, 0

local function NoteKey(n) return Me() .. "#" .. n.id end
local function Escape(s) return (s:gsub("|", "\31"):gsub("\r?\n", "\30")) end
local function Unescape(s) return (s:gsub("\31", "|"):gsub("\30", "\n")) end
-- the text in parts of at most max bytes, never splitting a letter (UTF-8)
local function Parts(text, max)
    local out, cur = {}, ""
    for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if #cur + #ch > max then out[#out + 1] = cur; cur = "" end
        cur = cur .. ch
    end
    out[#out + 1] = cur
    return out
end

function T.SendNote(n, bulk)
    if not (OMQ and OMQ:GetChannel() and n.shared and not n.archived) then return end
    local key, t, zone = NoteKey(n), tostring(n.edited or n.t), (n.subzone or n.zone or ""):sub(1, ZONE_MAX)
    local head = #"JN|1|" + #key + #t + #Me() + #tostring(n.level or 0) + #zone + 7 + 4   -- separators, part and parts
    local parts = Parts(Escape(n.text or ""), 250 - head)
    for i, chunk in ipairs(parts) do
        local send = bulk and OMQ.SendBulk or OMQ.Send
        send(OMQ, "JN", key, i, #parts, t, Me(), n.level or 0, zone, chunk)
    end
end
function T.WithdrawNote(n)
    if OMQ and OMQ:GetChannel() then OMQ:Send("JNX", NoteKey(n)) end
end
-- all your shared notes, newest first (an answer to JNQ)
function T.SendAllNotes()
    local sent = 0
    for i = #H.notes, 1, -1 do
        local n = H.notes[i]
        if n.shared and not n.archived then T.SendNote(n, true); sent = sent + 1 end
        if sent >= NOTES_SENT then break end
    end
end
-- ask the party for their shared notes, at most once every NOTE_ASK_EVERY seconds
function T.AskNotes()
    if not (OMQ and OMQ:GetChannel()) or time() - T.lastNoteAsk < NOTE_ASK_EVERY then return end
    T.lastNoteAsk = time()
    OMQ:Send("JNQ", Me())
end
-- the notepad of the party, newest first: { note, mine = true } for yours, { note } for theirs
function T.SharedNotes()
    local out = {}
    for _, n in ipairs(H.notes) do
        if n.shared and not n.archived then out[#out + 1] = { note = n, mine = true, t = n.edited or n.t } end
    end
    for _, p in pairs(H.partyNotes or {}) do
        if not p.hidden then out[#out + 1] = { note = p, t = p.t } end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end
function T.SetShared(id, on)
    for _, n in ipairs(H.notes) do
        if n.id == id then
            n.shared = on or nil
            if on then T.SendNote(n) else T.WithdrawNote(n) end
        end
    end
    J.Changed()
end
function T.HidePartyNote(key)
    if H.partyNotes and H.partyNotes[key] then H.partyNotes[key].hidden = true end
    J.Changed()
end

-- The journal's own note functions (Journal/Core.lua) learn about sharing: a new note follows the "Share new
-- notes" option unless told otherwise, and an edit, archive or delete of a shared note goes to the party too.
local function FindNote(id) for _, n in ipairs(H.notes) do if n.id == id then return n end end end
local addNote, editNote, setArchived, deleteItem = J.AddNote, J.EditNote, J.SetArchived, J.DeleteItem
function J.AddNote(text, trigger, repeats, pinned, shared)
    local n = addNote(text, trigger, repeats, pinned)
    if n then
        if shared == nil then shared = J.DB.shareNotes ~= false end
        if shared then n.shared = true; T.SendNote(n) end
    end
    return n
end
function J.EditNote(id, text)
    local n = FindNote(id)
    local was = n and n.shared and { id = n.id }
    editNote(id, text)
    local now = FindNote(id)
    if now and now.shared then now.edited = time(); T.SendNote(now)
    elseif was then T.WithdrawNote(was) end   -- an empty edit deletes the note
end
function J.SetArchived(kind, id, on)
    setArchived(kind, id, on)
    local n = kind == "note" and FindNote(id)
    if n and n.shared then if on then T.WithdrawNote(n) else T.SendNote(n) end end
end
function J.DeleteItem(kind, id)
    local n = kind == "note" and FindNote(id)
    if n and n.shared then T.WithdrawNote(n) end
    deleteItem(kind, id)
end

if OMQ then
    OMQ:RegisterMessage("JN", function(f)
        local key, part, parts, t, author, level, zone, chunk = f[1], tonumber(f[2]), tonumber(f[3]), tonumber(f[4]), f[5], f[6], f[7], f[8]
        if not (key and part and parts and t and author and chunk) or author == Me() or parts > 30 then return end
        local id = key .. "@" .. t
        local inc = T.incoming[id] or { got = 0, parts = {} }
        T.incoming[id] = inc
        if not inc.parts[part] then inc.parts[part] = chunk; inc.got = inc.got + 1 end
        if inc.got < parts then return end
        T.incoming[id] = nil
        H.partyNotes = H.partyNotes or {}
        local old = H.partyNotes[key]
        if old and old.t > t then return end   -- an older version arrived late
        H.partyNotes[key] = { key = key, author = author, t = t, level = tonumber(level), zone = Plain(zone),
            text = Unescape(table.concat(inc.parts)), hidden = old and old.hidden or nil }
        J.Changed()
    end)
    OMQ:RegisterMessage("JNX", function(f)
        local key = f[1]
        if key and H.partyNotes and H.partyNotes[key] then H.partyNotes[key] = nil; J.Changed() end
    end)
    OMQ:RegisterMessage("JNQ", function(f)
        if f[1] and f[1] ~= Me() then T.SendAllNotes() end
    end)
end
