-- Blato Lexicon: a log of this addon's errors that survives a /reload. The game writes Lua errors nowhere, and the
-- party side only held them in memory. They go to the saved variable BlatoLexiconErrors, in
-- WTF/Account/<account>/SavedVariables/BlatoLexicon.lua, which the game writes on logout and /reload.
-- Nothing leaves this computer. /blato errors shows the last ones (Party/Core.lua).
-- First in the TOC, so that it also sees errors in the files that load after it.
local ADDON, ns = ...

local MAX_ENTRIES, MAX_MESSAGE, MAX_STACK = 100, 600, 1800

local Log = {}
ns.ErrorLog = Log

local entries, index = {}, {}   -- only in memory until the saved variable is there (ADDON_LOADED)
local busy = false              -- an error while logging must not be logged again

local function isSecret(v) return issecretvalue and issecretvalue(v) end

local function text(v, max)
    if isSecret(v) then return "<secret value>" end
    local s = tostring(v)
    if #s > max then s = s:sub(1, max) .. "..." end
    return s
end

local function character()
    local name = UnitName and UnitName("player")
    if isSecret(name) or not name then return "?" end
    return name
end

local function version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return get and get(ADDON, "Version") or "?"
end

local function keyOf(e) return e.kind .. "|" .. (e.where or "") .. "|" .. e.message end

-- the same error again only counts up; beyond the limit the oldest one goes
local function merge(e)
    local key = keyOf(e)
    local known = index[key]
    if known then
        known.count = (known.count or 1) + (e.count or 1)
        known.last, known.char, known.version = e.last, e.char, e.version
        return
    end
    e.count = e.count or 1
    index[key] = e
    entries[#entries + 1] = e
    while #entries > MAX_ENTRIES do
        index[keyOf(table.remove(entries, 1))] = nil
    end
end

local function remember(kind, where, message, stack)
    local now = date and date("%Y-%m-%d %H:%M:%S") or "?"
    merge({ kind = kind, where = where, message = message, stack = stack, count = 1, first = now, last = now,
            char = character(), version = version() })
end

local function add(kind, where, message)
    remember(kind, where and text(where, 120) or nil, text(message, MAX_MESSAGE))
end

-- kind: "party" (an error the party side caught), "warning" or "blocked"; where: what it was doing, or nil
function Log.Add(kind, where, message)
    if busy then return end
    busy = true
    pcall(add, kind, where, message)
    busy = false
end

function Log.List() return entries end

function Log.Clear()
    for i = #entries, 1, -1 do entries[i] = nil end
    index = {}
end

local function ours(s) return s:find("BlatoLexicon", 1, true) or s:find("BlatoParty", 1, true) end

-- every Lua error of the game passes here; only the ones of this addon are kept. The frames of this file are taken
-- out of the stack first, or every error would look like one of ours.
local function caught(msg)
    local message = text(msg, MAX_MESSAGE)
    local stack = debugstack and debugstack(1, 30, 5) or ""
    stack = stack:gsub("[^\n]*ErrorLog%.lua[^\n]*\n?", "")
    if ours(message) or ours(stack) then remember("lua", nil, message, text(stack, MAX_STACK)) end
end

-- the game's own handler stays behind this one, so the Lua error window works as before. No installed addon replaces
-- the handler on this client, so pcall: if the client refuses, the events below and Log.Add still work.
if type(geterrorhandler) == "function" and type(seterrorhandler) == "function" then
    local previous = geterrorhandler()
    pcall(seterrorhandler, function(msg, ...)
        if not busy then
            busy = true
            pcall(caught, msg)
            busy = false
        end
        if previous then return previous(msg, ...) end
    end)
end

local function loaded()
    local early = entries
    entries, index = {}, {}
    if type(_G.BlatoLexiconErrors) == "table" then
        for _, e in ipairs(_G.BlatoLexiconErrors) do
            if type(e) == "table" and type(e.kind) == "string" and type(e.message) == "string" then merge(e) end
        end
    end
    for _, e in ipairs(early) do merge(e) end
    _G.BlatoLexiconErrors = entries
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "LUA_WARNING" }) do
    pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(self, event, a, b)
    if event == "ADDON_LOADED" then
        if a == ADDON then
            loaded()
            self:UnregisterEvent("ADDON_LOADED")
        end
    elseif event == "LUA_WARNING" then
        -- (type, text): a file that does not load, for example
        if not isSecret(b) and type(b) == "string" and ours(b) then Log.Add("warning", nil, b) end
    else
        -- (addon, function): "Interface action failed because of an AddOn"; every addon, to see whether it was ours
        Log.Add("blocked", a, b)
    end
end)
