local ADDON, ns = ...

--------------------------------------------------------------------------
-- What the damage meter doesn't record
--
-- Read from unit state and events the game still gives addons (no combat
-- log), per group member, for the current dungeon run:
--   threat:   time holding a mob's attention (tanks), times a mob turned on
--             a non-tank (UnitThreatSituation, sampled)
--   health:   dropping to 10% or less and living through the fight
--   casts:    spells cast per minute in combat, casts cut off
--             (UNIT_SPELLCAST_SUCCEEDED / _INTERRUPTED)
--   loot:     items received and loot rolls (loot chat messages)
--   group:    party chat, emotes, ready check answers, disconnects, AFK, wipes
-- Numbers the game hides (secret values) are skipped, so an award that
-- needs them just doesn't appear.
--------------------------------------------------------------------------

local Tracker = {}
ns.Tracker = Tracker

local Safe = ns.Safe
local SAMPLE_EVERY = 0.5 -- seconds
local CLOSE_CALL = 0.1 -- health share

-- Repeating attacks that fire a "spell cast" on every swing or shot.
local AUTO_REPEAT = { [75] = true, [5019] = true, [6603] = true } -- Auto Shot, Shoot (wand), Auto Attack

local state = {} -- [GUID] = { fighting =, low =, tanking =, afk =, cast = } (not saved)
local readyStart, readyBy

local function CurrentRun()
    local run = ns.db and ns.db.current
    if run and not run.leftAt then
        return run
    end
end

local function GroupUnit(unit)
    return unit == "player" or (type(unit) == "string" and (unit:match("^party%d$") or unit:match("^raid%d+$"))) or false
end

local function FullName(unit)
    local name, realm = UnitName(unit)
    name, realm = Safe(name), Safe(realm)
    if name and realm and realm ~= "" then
        return name .. "-" .. realm, name
    end
    return name, name
end

-- The run's record for a group member (by GUID).
local function Entry(run, guid, name)
    run.extra = run.extra or {}
    local entry = run.extra[guid]
    if not entry then
        entry = {}
        run.extra[guid] = entry
    end
    entry.name = entry.name or name
    return entry
end

local function ForUnit(run, unit)
    local guid = Safe(UnitGUID(unit))
    if not guid then
        return nil
    end
    local _, short = FullName(unit)
    return Entry(run, guid, short), guid
end

-- A group member by the name a chat or loot message shows.
local function ForName(run, name)
    if type(name) ~= "string" or name == "" then
        return nil
    end
    if name == (rawget(_G, "YOU") or "You") then
        return ForUnit(run, "player")
    end
    local short = name:gsub("%-.*$", "")
    for _, unit in ipairs(ns.Models.Units()) do
        if Safe(UnitExists(unit)) then
            local full, plain = FullName(unit)
            if full == name or plain == name or plain == short then
                return ForUnit(run, unit)
            end
        end
    end
end

local function Add(entry, field, amount)
    entry[field] = (entry[field] or 0) + (amount or 1)
end

local function InCombat(unit)
    local ok, fighting = pcall(UnitAffectingCombat, unit)
    return ok and Safe(fighting) and true or false
end

--------------------------------------------------------------------------
-- Sampling threat and health
--------------------------------------------------------------------------

function Tracker:Sample(dt)
    local run = CurrentRun()
    if not run then
        return
    end
    for _, unit in ipairs(ns.Models.Units()) do
        if Safe(UnitExists(unit)) then
            local entry, guid = ForUnit(run, unit)
            if entry then
                local s = state[guid] or {}
                state[guid] = s
                if InCombat(unit) then
                    Add(entry, "combat", dt)
                    local ok, threat = pcall(UnitThreatSituation, unit)
                    threat = ok and Safe(threat)
                    if type(threat) == "number" then
                        Add(entry, "threatTime", dt)
                        if threat >= 3 then
                            Add(entry, "holding", dt)
                        end
                        -- a mob is attacking them: counts once it lasts two samples
                        if threat >= 2 then
                            s.tanking = (s.tanking or 0) + 1
                            if s.tanking == 2 then
                                Add(entry, "aggro")
                            end
                        else
                            s.tanking = 0
                        end
                    end
                    local okH, health = pcall(UnitHealth, unit)
                    local okM, maxHealth = pcall(UnitHealthMax, unit)
                    health, maxHealth = okH and Safe(health), okM and Safe(maxHealth)
                    if type(health) == "number" and type(maxHealth) == "number" and maxHealth > 0 and health > 0 then
                        s.low = math.min(s.low or 1, health / maxHealth)
                    end
                    s.fighting = true
                elseif s.fighting then
                    -- their fight is over: did they make it?
                    if s.low and s.low <= CLOSE_CALL and not Safe(UnitIsDeadOrGhost(unit)) then
                        Add(entry, "clutch")
                    end
                    s.fighting, s.low, s.tanking = false, nil, 0
                end
            end
        end
    end
end

--------------------------------------------------------------------------
-- Chat and loot messages
--------------------------------------------------------------------------

-- Turns a game format string ("%s receives loot: %s.", or with positional
-- arguments like "%2$s ... %1$s") into a Lua pattern. Returns the pattern
-- and, for each capture, which format argument it is.
function Tracker.FormatToPattern(format)
    local pattern, order, sequential = { "^" }, {}, 0
    local i = 1
    while i <= #format do
        local c = format:sub(i, i)
        if c == "%" then
            local position, kind, length = format:match("^%%(%d+)%$([sd])()", i)
            if position then
                order[#order + 1] = tonumber(position)
                pattern[#pattern + 1] = kind == "d" and "(%-?%d+)" or "(.-)"
                i = length
            else
                kind = format:sub(i + 1, i + 1)
                if kind == "s" or kind == "d" then
                    sequential = sequential + 1
                    order[#order + 1] = sequential
                    pattern[#pattern + 1] = kind == "d" and "(%-?%d+)" or "(.-)"
                    i = i + 2
                else -- "%%" or anything else: a literal
                    pattern[#pattern + 1] = "%" .. (kind ~= "" and kind or "%")
                    i = i + 2
                end
            end
        else
            pattern[#pattern + 1] = c:match("[%(%)%.%+%-%*%?%[%]%^%$]") and ("%" .. c) or c
            i = i + 1
        end
    end
    pattern[#pattern + 1] = "$"
    return table.concat(pattern), order
end

-- Matches a message against a format string; returns the arguments in
-- their format order, or nil.
local function Match(message, format)
    local pattern, order = Tracker.FormatToPattern(format)
    local captures = { message:match(pattern) }
    if #captures == 0 then
        return nil
    end
    local args = {}
    for i, value in ipairs(captures) do
        args[order[i]] = value
    end
    return args
end

local HEX_QUALITY = {
    ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6,
}

function Tracker.LinkQuality(link)
    if type(link) ~= "string" then
        return nil
    end
    local quality = link:match("|cnIQ(%d+):")
    if quality then
        return tonumber(quality)
    end
    local hex = link:match("|c%x%x(%x%x%x%x%x%x)")
    return hex and HEX_QUALITY[hex:lower()] or nil
end

-- name, link, count arguments in each loot message (nil = you)
local LOOT_MESSAGES = {
    { "LOOT_ITEM_SELF_MULTIPLE", nil, 1, 2 },
    { "LOOT_ITEM_SELF", nil, 1 },
    { "LOOT_ITEM_MULTIPLE", 1, 2, 3 },
    { "LOOT_ITEM", 1, 2 },
}
-- roll, link, name arguments in each roll message
local ROLL_MESSAGES = {
    "LOOT_ROLL_ROLLED_NEED_ROLE_BONUS", "LOOT_ROLL_ROLLED_NEED", "LOOT_ROLL_ROLLED_GREED",
    "LOOT_ROLL_ROLLED_DE", "LOOT_ROLL_ROLLED_TRANSMOG",
}

function Tracker:OnLoot(message)
    local run = CurrentRun()
    message = Safe(message)
    if not run or type(message) ~= "string" then
        return
    end
    for _, name in ipairs(ROLL_MESSAGES) do
        local format = rawget(_G, name)
        local args = type(format) == "string" and Match(message, format)
        if args then
            local roll, who = tonumber(args[1]), args[3]
            local entry = roll and ForName(run, who)
            if entry then
                Add(entry, "rolls")
                entry.bestRoll = math.max(entry.bestRoll or roll, roll)
                entry.worstRoll = math.min(entry.worstRoll or roll, roll)
                run.rolls = (run.rolls or 0) + 1
            end
            return
        end
    end
    for _, spec in ipairs(LOOT_MESSAGES) do
        local format = rawget(_G, spec[1])
        local args = type(format) == "string" and Match(message, format)
        if args then
            local entry = spec[2] and ForName(run, args[spec[2]]) or (not spec[2] and ForUnit(run, "player"))
            local quality = Tracker.LinkQuality(args[spec[3]])
            if entry and quality and quality >= 2 then
                Add(entry, "loot")
                if quality >= 4 then
                    Add(entry, "epics")
                end
            end
            return
        end
    end
end

function Tracker:OnChat(message, sender, field)
    local run = CurrentRun()
    message, sender = Safe(message), Safe(sender)
    if not run or type(message) ~= "string" then
        return
    end
    -- our own result lines don't count
    if field == "chats" and message:find(ns.L.SHARE_HEADER:format(""), 1, true) == 1 then
        return
    end
    local entry = ForName(run, sender)
    if entry then
        Add(entry, field)
    end
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local events = CreateFrame("Frame")
Tracker.frame = events
local pending = 0
events:SetScript("OnUpdate", function(_, elapsed)
    pending = pending + elapsed
    if pending >= SAMPLE_EVERY then
        local dt = pending
        pending = 0
        Tracker:Sample(dt)
    end
end)

local handlers = {}

function handlers.UNIT_SPELLCAST_SUCCEEDED(unit, castGUID, spellID)
    local run = CurrentRun()
    if not (run and GroupUnit(unit) and InCombat(unit)) then
        return
    end
    spellID = Safe(spellID)
    if spellID and AUTO_REPEAT[spellID] then
        return
    end
    local entry, guid = ForUnit(run, unit)
    if not entry then
        return
    end
    -- the same cast can arrive as "player" and as "raidN"
    castGUID = Safe(castGUID)
    local s = state[guid] or {}
    state[guid] = s
    if castGUID and s.cast == castGUID then
        return
    end
    s.cast = castGUID
    Add(entry, "casts")
end

function handlers.UNIT_SPELLCAST_INTERRUPTED(unit, castGUID)
    local run = CurrentRun()
    if not (run and GroupUnit(unit) and InCombat(unit)) then
        return
    end
    local entry, guid = ForUnit(run, unit)
    castGUID = Safe(castGUID)
    local s = guid and state[guid] or {}
    if entry and not (castGUID and s.cut == castGUID) then
        s.cut = castGUID
        Add(entry, "fumbles")
    end
end

function handlers.CHAT_MSG_LOOT(message)
    Tracker:OnLoot(message)
end

for _, event in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    handlers[event] = function(message, sender)
        Tracker:OnChat(message, sender, "chats")
    end
end
for _, event in ipairs({ "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_EMOTE" }) do
    handlers[event] = function(message, sender)
        Tracker:OnChat(message, sender, "emotes")
    end
end

function handlers.READY_CHECK(initiator)
    readyStart, readyBy = GetTime(), Safe(initiator)
end

function handlers.READY_CHECK_CONFIRM(unit, isReady)
    local run = CurrentRun()
    if not (run and readyStart and GroupUnit(unit) and Safe(isReady)) then
        return
    end
    local entry = ForUnit(run, unit)
    local full, short = FullName(unit)
    if entry and readyBy ~= full and readyBy ~= short then -- whoever asked is ready already
        Add(entry, "readySum", GetTime() - readyStart)
        Add(entry, "readyCount")
    end
end

function handlers.READY_CHECK_FINISHED()
    readyStart, readyBy = nil, nil
end

function handlers.UNIT_CONNECTION(unit, isConnected)
    local run = CurrentRun()
    if run and GroupUnit(unit) and Safe(isConnected) == false then
        local entry = ForUnit(run, unit)
        if entry then
            Add(entry, "dc")
        end
    end
end

function handlers.PLAYER_FLAGS_CHANGED(unit)
    local run = CurrentRun()
    if not (run and GroupUnit(unit) and UnitIsAFK) then
        return
    end
    local entry, guid = ForUnit(run, unit)
    if not entry then
        return
    end
    local ok, afk = pcall(UnitIsAFK, unit)
    afk = ok and Safe(afk) and true or false
    local s = state[guid] or {}
    state[guid] = s
    if afk and not s.afk then
        Add(entry, "afk")
    end
    s.afk = afk
end

function handlers.ENCOUNTER_END(_, _, _, _, success)
    local run = CurrentRun()
    success = Safe(success)
    if run and (success == 0 or success == false) then
        run.wipes = (run.wipes or 0) + 1
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)
for event in pairs(handlers) do
    pcall(events.RegisterEvent, events, event)
end

-- For tests.
function Tracker:Reset()
    wipe(state)
    readyStart, readyBy, pending = nil, nil, 0
end
