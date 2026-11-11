local ADDON, ns = ...
local L, Meter, Safe = ns.L, ns.Meter, ns.Safe

--------------------------------------------------------------------------
-- How it works
--
-- Entering a dungeon starts a "run". After every fight (once combat is over
-- and the meter's numbers are no longer secret) the new damage meter
-- sessions are copied into the run: damage, healing, damage taken,
-- avoidable damage, interrupts, dispels and deaths per player, plus each
-- top player's key ability. Keeping our own copy means nothing is lost when
-- the meter drops old fights or is reset.
--
-- The run is complete when the last boss dies (Adventure Guide boss list),
-- when the dungeon finder / scenario / keystone says so, or - for dungeons
-- the guide doesn't know - when you leave after killing a boss. Then the
-- ceremony is built from the run (Awards.lua) and shown (Ceremony.lua).
--------------------------------------------------------------------------

local DEFAULTS = {
    enabled = true,
    onLeave = true,
    raids = true,
    models = true, -- players' characters with emotes on the podium
    modelSize = 100, -- %
    modelOffset = 0, -- move the characters up (+) or down (-) on their step
    confetti = true,
    dim = true,
    sound = true,
    fun = true,
    hideInCombat = true,
    autoClose = 60,
    scale = 100,
    keep = 5, -- finished runs kept for /mvp history
    debug = false,
}
ns.DEFAULTS = DEFAULTS

local RESUME_WINDOW = 30 * 60 -- a run left this long ago (wipe, corpse run) is picked up again
local STALE_INSIDE = 2 * 3600 -- logged out inside a dungeon longer than this: start over
local SHOW_DELAY = 2 -- seconds after combat before the ceremony opens
local MAX_RETRIES = 10

local db
local queued -- ceremony waiting for combat to end: { kind =, boss = }
local retries = 0
local harvestQueued = false
local encounterCache = {} -- [instance map ID] = Adventure Guide boss list

local function Print(...)
    print("|cffffd100Podium|r:", ...)
end
ns.Print = Print

local function Debug(...)
    if db and db.debug then
        Print("|cffaaaaaa[debug]|r", ...)
    end
end
ns.Debug = Debug

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
            end
            CopyDefaults(v, dst[k])
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

-- Saved settings from older versions.
function ns.Migrate(saved)
    saved.everyBoss = nil -- removed option (1.2)
    -- Character height: the placement found right in game is built in, so
    -- that setting is 0 now. A saved 0 (never moved) stays 0; anything else
    -- keeps its look.
    local function Shift(by)
        local offset = saved.modelOffset or 0
        saved.modelOffset = offset == 0 and 0 or math.max(-40, math.min(40, offset + by))
    end
    if (saved.dbVersion or 1) < 2 then
        Shift(40) -- 1.2.1 looked right at -40
    end
    if (saved.dbVersion or 1) < 3 then
        Shift(-6) -- 1.2.2 looked right at +6
    end
    saved.dbVersion = 3
    return saved
end

local function InCombat()
    if InCombatLockdown() then
        return true
    end
    local ok, affecting = pcall(UnitAffectingCombat, "player")
    return ok and Safe(affecting) and true or false
end
ns.InCombat = InCombat

-- The dungeon or raid we are in, or nil.
local function CurrentInstance()
    local inInstance, instanceType = IsInInstance()
    if not Safe(inInstance) then
        return nil
    end
    local name, kind, difficultyID, difficultyName, _, _, _, mapID = GetInstanceInfo()
    kind = Safe(kind) or Safe(instanceType)
    if kind ~= "party" and kind ~= "raid" then
        return nil
    end
    return {
        name = Safe(name),
        type = kind,
        difficulty = Safe(difficultyName),
        difficultyID = Safe(difficultyID),
        mapID = Safe(mapID),
    }
end

--------------------------------------------------------------------------
-- Runs
--------------------------------------------------------------------------

-- Ignore the meter's sessions that already exist (fights from before).
local function SkipExistingSessions(run)
    for _, session in ipairs(Meter.Sessions()) do
        if not run.fights[run.epoch .. ":" .. session.id] then
            run.skip[session.id] = true
        end
    end
end

local function NewRun(info)
    local run = {
        instance = info.name or L.UNKNOWN,
        instanceType = info.type,
        difficulty = info.difficulty,
        mapID = info.mapID,
        started = time(),
        lastSeen = time(),
        epoch = 1,
        skip = {}, -- [sessionID] = true for sessions that aren't part of this run
        fights = {}, -- [epoch:sessionID] = fight
        order = {}, -- fight keys, oldest first
        roster = {}, -- [player key] = { name =, class =, role =, isLocal = }
        byGuid = {},
        byName = {},
        bosses = {}, -- { id =, name =, time =, final =, fkey = }
        killed = {}, -- [encounterID or name] = true
        pending = {}, -- indexes into bosses not yet matched to a fight
    }
    SkipExistingSessions(run)
    return run
end
ns.NewRun = NewRun

local function CanResume(run, info)
    if not run or run.mapID ~= info.mapID then
        return false
    end
    if not run.leftAt then
        -- /reload or logging back in inside the dungeon
        return time() - (run.lastSeen or run.started or 0) < STALE_INSIDE
    end
    return not run.complete and time() - run.leftAt < RESUME_WINDOW
end

-- Moves a run into the history (only if something was recorded).
function ns:FinishRun(run)
    if run and #run.order > 0 then
        run.skip, run.byGuid, run.byName, run.pending = nil, nil, nil, nil
        table.insert(db.history, 1, run)
        while #db.history > db.keep do
            table.remove(db.history)
        end
    end
    if db.current == run then
        db.current = nil
    end
end

-- Current run first (if it has fights), then finished runs.
function ns:Runs()
    local list = {}
    if db.current and #db.current.order > 0 then
        list[1] = db.current
    end
    for _, run in ipairs(db.history) do
        list[#list + 1] = run
    end
    return list
end

--------------------------------------------------------------------------
-- Copying fights from the damage meter
--------------------------------------------------------------------------

-- One key per player for the whole run, by GUID or (if hidden) by name.
local function ResolvePlayer(run, source)
    local key = source.guid and run.byGuid[source.guid]
    if not key and source.name then
        key = run.byName[source.name]
    end
    if not key then
        key = source.guid or ("name:" .. source.name)
        run.roster[key] = { class = source.class }
    end
    local info = run.roster[key]
    if source.guid then
        run.byGuid[source.guid] = key
    end
    if source.name then
        run.byName[source.name] = key
        info.name = info.name or source.name
    end
    info.class = info.class or source.class
    if source.isLocal then
        info.isLocal = true
    end
    return key
end

-- Looks up each player's key ability for the top `count` players of a stat.
local function TopSpells(players, sessionID, stat, typeName, field, count)
    local list = {}
    for _, p in pairs(players) do
        if (p[stat] or 0) > 0 and p.guid then
            list[#list + 1] = p
        end
    end
    table.sort(list, function(a, b) return a[stat] > b[stat] end)
    for i = 1, math.min(count, #list) do
        local p = list[i]
        local spellID, amount = Meter.TopSpell(sessionID, typeName, p.guid)
        if spellID then
            p[field] = spellID
            p[field .. "A"] = amount
        end
    end
end

function ns:StoreFight(run, fkey, session, data)
    local fight = run.fights[fkey]
    if not fight then
        fight = { sid = session.id }
        run.fights[fkey] = fight
        run.order[#run.order + 1] = fkey
    end
    fight.name = session.name or fight.name
    local players = {}
    local estimated = 0
    for _, source in ipairs(data.sources) do
        local p = {}
        local any = false
        for _, stat in ipairs(Meter.STATS) do
            local value = source[stat.key]
            if value and value > 0 then
                p[stat.key] = value
                any = true
            end
        end
        if any then
            local key = ResolvePlayer(run, source)
            p.guid = source.guid
            players[key] = p
            if source.aps and source.aps > 0 and p.dmg then
                estimated = math.max(estimated, p.dmg / source.aps)
            end
        end
    end
    TopSpells(players, session.id, "dmg", "DamageDone", "dsp", 3)
    TopSpells(players, session.id, "heal", "HealingDone", "hsp", 2)
    for _, p in pairs(players) do
        p.guid = nil
    end
    fight.p = players
    local duration = session.duration or data.duration
    if not duration or duration <= 0 then
        duration = estimated > 0 and estimated or nil
    end
    fight.dur = duration or fight.dur or 0
end

local function GroupUnits()
    local units = { "player" }
    if IsInRaid() then
        for i = 1, 40 do
            units[#units + 1] = "raid" .. i
        end
    else
        for i = 1, 4 do
            units[#units + 1] = "party" .. i
        end
    end
    return units
end

-- Roles from the group (dungeon finder / role check). Missing roles are
-- guessed later from the numbers.
function ns:UpdateRoles(run)
    if not UnitGroupRolesAssigned then
        return
    end
    for _, unit in ipairs(GroupUnits()) do
        if Safe(UnitExists(unit)) then
            local guid = Safe(UnitGUID(unit))
            local name, realm = UnitName(unit)
            name, realm = Safe(name), Safe(realm)
            local key = guid and run.byGuid[guid]
            if not key and name then
                key = run.byName[name] or (realm and realm ~= "" and run.byName[name .. "-" .. realm])
            end
            if key and run.roster[key] then
                local ok, role = pcall(UnitGroupRolesAssigned, unit)
                role = ok and Safe(role)
                if role == "TANK" or role == "HEALER" or role == "DAMAGER" then
                    run.roster[key].role = role
                end
            end
        end
    end
end

-- Ties boss kills to the fight they happened in: the newest fight named
-- after the boss, otherwise the newest fight.
function ns:MatchBosses(run)
    for i = #run.pending, 1, -1 do
        local boss = run.bosses[run.pending[i]]
        local fkey
        for j = #run.order, 1, -1 do
            local fight = run.fights[run.order[j]]
            if boss and boss.name and fight.name == boss.name and not fight.boss then
                fkey = run.order[j]
                break
            end
        end
        fkey = fkey or run.order[#run.order]
        if boss and fkey and not run.fights[fkey].boss then
            local fight = run.fights[fkey]
            fight.boss = boss.name or fight.name
            fight.final = boss.final or nil
            boss.fkey = fkey
            table.remove(run.pending, i)
        elseif not boss then
            table.remove(run.pending, i)
        end
    end
end

-- Copies finished fights from the damage meter into the current run.
-- Returns false if it has to wait (combat, or the numbers are still secret).
function ns:Harvest()
    local run = db and db.current
    if not run then
        return true
    end
    if InCombat() then
        return false
    end
    if not Meter.IsAvailable() then
        return true
    end
    local sessions = Meter.Sessions()
    local newest = sessions[#sessions] and sessions[#sessions].id
    for _, session in ipairs(sessions) do
        local fkey = run.epoch .. ":" .. session.id
        local fight = run.fights[fkey]
        -- After leaving the dungeon only fights we already know are updated.
        local wanted = not run.skip[session.id] and (fight or not run.leftAt)
        if wanted and not (fight and fight.done) then
            local data, err = Meter.ReadSession(session.id)
            if not data then
                if err == "secret" then
                    Debug("session", session.id, "is still secret")
                    return false
                end
            else
                self:StoreFight(run, fkey, session, data)
                -- An older session can't change any more.
                run.fights[fkey].done = session.id ~= newest or nil
            end
        end
    end
    self:UpdateRoles(run)
    self:MatchBosses(run)
    if not run.leftAt then
        run.lastSeen = time()
    end
    return true
end

function ns:RequestHarvest(delay)
    if harvestQueued then
        return
    end
    harvestQueued = true
    C_Timer.After(delay or 1, function()
        harvestQueued = false
        ns:Harvest()
    end)
end

--------------------------------------------------------------------------
-- Is the dungeon done?
--------------------------------------------------------------------------

-- Boss list of the current instance from the Adventure Guide, in order:
-- { { id = encounterID, name = }, ... } or nil when the guide doesn't know it.
function ns:EncounterList(run)
    local mapID = run and run.mapID
    if not mapID then
        return nil
    end
    if encounterCache[mapID] then
        return encounterCache[mapID]
    end
    local journalID
    if C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap then
        local ok, id = pcall(C_EncounterJournal.GetInstanceForGameMap, mapID)
        journalID = ok and Safe(id) or nil
    end
    if not journalID and EJ_GetInstanceForMap and C_Map and C_Map.GetBestMapForUnit then
        local ok, uiMapID = pcall(C_Map.GetBestMapForUnit, "player")
        uiMapID = ok and Safe(uiMapID)
        if uiMapID then
            local ok2, id = pcall(EJ_GetInstanceForMap, uiMapID)
            journalID = ok2 and Safe(id) or nil
        end
    end
    if not journalID or journalID == 0 or not EJ_GetEncounterInfoByIndex then
        return nil
    end
    local list = {}
    for index = 1, 40 do
        -- name, description, journalEncounterID, rootSectionID, link, journalInstanceID, dungeonEncounterID
        local ok, name, _, _, _, _, _, encounterID = pcall(EJ_GetEncounterInfoByIndex, index, journalID)
        name = ok and Safe(name)
        if not name then
            break
        end
        encounterID = Safe(encounterID)
        list[#list + 1] = { id = encounterID ~= 0 and encounterID or nil, name = name }
    end
    if #list == 0 then
        return nil
    end
    encounterCache[mapID] = list
    return list
end

local function Killed(run, entry)
    return (entry.id and run.killed[entry.id]) or (entry.name and run.killed[entry.name]) or false
end

-- The last boss in the guide died, or every boss in the guide is dead.
function ns:IsFinalBoss(run, id, name)
    local list = self:EncounterList(run)
    if not list then
        return false
    end
    local last = list[#list]
    if (id and last.id == id) or (name and last.name == name) then
        return true
    end
    for _, entry in ipairs(list) do
        if not Killed(run, entry) then
            return false
        end
    end
    return true
end

function ns:OnBossKilled(id, name)
    local run = db.current
    if not run or run.leftAt then
        return
    end
    local key = id or name
    -- ENCOUNTER_END and BOSS_KILL both report the same kill.
    if not key or run.killed[key] or (name and run.killed[name]) then
        return
    end
    run.killed[key] = true
    if name then
        run.killed[name] = true
    end
    local final = self:IsFinalBoss(run, id, name)
    run.bosses[#run.bosses + 1] = { id = id, name = name, time = time(), final = final or nil }
    run.pending[#run.pending + 1] = #run.bosses
    Debug("boss killed:", tostring(name), tostring(id), final and "(last boss)" or "")
    if final then
        self:Complete(run, "final")
    end
    self:RequestHarvest(1)
end

function ns:Complete(run, reason)
    if not run or run.complete then
        return
    end
    run.complete = reason
    run.ended = time()
    Debug("run complete:", reason)
    if db.enabled then
        self:QueueCeremony({ kind = "clear" })
    end
end

function ns:OnLeftInstance(run)
    if run.complete or not db.enabled or not db.onLeave or #run.bosses == 0 then
        return
    end
    -- Released spirit: running back, not leaving.
    if Safe(UnitIsDeadOrGhost("player")) then
        return
    end
    run.complete = "leave"
    run.ended = run.leftAt
    self:QueueCeremony({ kind = "clear" })
end

--------------------------------------------------------------------------
-- Showing ceremonies
--------------------------------------------------------------------------

function ns:QueueCeremony(request)
    queued = request
    retries = 0
    self:ScheduleQueued(SHOW_DELAY)
end

function ns:ScheduleQueued(delay)
    if not queued or InCombat() then
        return -- PLAYER_REGEN_ENABLED tries again
    end
    C_Timer.After(delay, function()
        ns:TryShowQueued()
    end)
end

function ns:TryShowQueued()
    if not queued or InCombat() then
        return
    end
    if not self:Harvest() then
        retries = retries + 1
        if retries > MAX_RETRIES then
            Print(L.METER_SECRET)
            retries = 0
            return -- the next combat end tries again
        end
        C_Timer.After(2, function()
            ns:TryShowQueued()
        end)
        return
    end
    local request = queued
    queued = nil
    self:ShowRun(db.current, request)
end

function ns:IsQueued()
    return queued ~= nil
end

-- Builds the ceremony for a run and shows it. Returns the report.
function ns:ShowRun(run, request)
    if not run then
        Print(L.NO_RUN)
        return
    end
    local report = ns.Awards.Build(run, request)
    if not report then
        local available, reason = Meter.IsAvailable()
        Print(available and L.NO_DATA or L.METER_UNAVAILABLE:format(tostring(reason)))
        return
    end
    self.lastReport = report
    if request.kind ~= "demo" then
        run.shown = true
    end
    if ns.Ceremony then
        ns.Ceremony:Show(report)
    end
    return report
end

-- Last ceremony, or the current run so far.
function ns:ShowLast(index)
    local runs = self:Runs()
    local run = runs[index or 1]
    if not run then
        Print(index and L.HISTORY_EMPTY or L.NO_RUN)
        return
    end
    if run == db.current then
        self:Harvest()
    end
    local kind = run.complete and "clear" or "partial"
    return self:ShowRun(run, { kind = kind })
end

function ns:ShowDemo()
    return self:ShowRun(ns.Awards.DemoRun(), { kind = "demo" })
end

function ns:SetEnabled(enabled)
    db.enabled = enabled and true or false
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    ns[event](ns, ...)
end)

local function Register(event)
    -- pcall: a client without one of these events shouldn't break the addon
    pcall(events.RegisterEvent, events, event)
end

function ns:ADDON_LOADED(name)
    if name ~= ADDON then
        return
    end
    events:UnregisterEvent("ADDON_LOADED")
    PodiumDB = PodiumDB or {}
    db = CopyDefaults(DEFAULTS, PodiumDB)
    if type(db.history) ~= "table" then
        db.history = {}
    end
    ns.Migrate(db)
    ns.db = db

    Register("PLAYER_LOGIN")
    Register("PLAYER_ENTERING_WORLD")
    Register("PLAYER_LOGOUT")
    Register("PLAYER_REGEN_DISABLED")
    Register("PLAYER_REGEN_ENABLED")
    Register("ENCOUNTER_END")
    Register("BOSS_KILL")
    Register("LFG_COMPLETION_REWARD")
    Register("SCENARIO_COMPLETED")
    Register("CHALLENGE_MODE_COMPLETED")
    Register("DAMAGE_METER_RESET")
    Register("DAMAGE_METER_COMBAT_SESSION_UPDATED")
end

function ns:PLAYER_LOGIN()
    if self.CreateOptions then
        self:CreateOptions()
    end
    if not db.welcomed then
        db.welcomed = true
        Print(L.LOADED)
    end
end

function ns:PLAYER_ENTERING_WORLD(isInitialLogin)
    local run = db.current
    if run and Safe(isInitialLogin) then
        -- The meter numbers its sessions from scratch after logging in.
        run.epoch = run.epoch + 1
        run.skip = {}
        SkipExistingSessions(run)
    end
    local info = CurrentInstance()
    local tracked = info and (info.type == "party" or db.raids)
    if tracked then
        if CanResume(run, info) then
            if run.leftAt then
                run.leftAt = nil
                SkipExistingSessions(run) -- fights outside while we were gone
            end
            Debug("continuing run:", run.instance)
        else
            self:FinishRun(run)
            db.current = NewRun(info)
            Debug("new run:", db.current.instance)
        end
        db.current.lastSeen = time()
    elseif run and not run.leftAt then
        self:Harvest() -- fights from just before zoning out still count
        run.leftAt = time()
        self:OnLeftInstance(run)
    end
end

function ns:PLAYER_LOGOUT()
    if db.current and not db.current.leftAt then
        db.current.lastSeen = time()
    end
end

function ns:PLAYER_REGEN_DISABLED()
    if db.hideInCombat and ns.Ceremony then
        ns.Ceremony:Hide()
    end
end

function ns:PLAYER_REGEN_ENABLED()
    if queued then
        self:ScheduleQueued(SHOW_DELAY)
    else
        self:RequestHarvest(1)
    end
end

function ns:ENCOUNTER_END(encounterID, encounterName, _, _, success)
    success = Safe(success)
    if success == 1 or success == true then
        self:OnBossKilled(Safe(encounterID), Safe(encounterName))
    end
end

function ns:BOSS_KILL(encounterID, encounterName)
    self:OnBossKilled(Safe(encounterID), Safe(encounterName))
end

function ns:LFG_COMPLETION_REWARD()
    self:Complete(db.current, "lfg")
end

function ns:SCENARIO_COMPLETED()
    if db.current and not db.current.leftAt and CurrentInstance() then
        self:Complete(db.current, "scenario")
    end
end

function ns:CHALLENGE_MODE_COMPLETED()
    self:Complete(db.current, "keystone")
end

function ns:DAMAGE_METER_RESET()
    local run = db.current
    if run then
        -- New sessions after a reset belong to the run; old ones are kept.
        run.epoch = run.epoch + 1
        run.skip = {}
        Debug("damage meter reset")
    end
end

-- Catches fights that go on while we are out of combat (dead, or not pulled).
function ns:DAMAGE_METER_COMBAT_SESSION_UPDATED()
    if db.current and not db.current.leftAt and not InCombat() then
        self:RequestHarvest(3)
    end
end

events:RegisterEvent("ADDON_LOADED")

--------------------------------------------------------------------------
-- /mvp debug
--------------------------------------------------------------------------

function ns:DebugReport()
    local available, reason = Meter.IsAvailable()
    local cvar = C_CVar and C_CVar.GetCVar and C_CVar.GetCVar("damageMeterEnabled")
    local sessions = Meter.Sessions()
    Print(("damage meter: available %s%s, window %s, sessions %d, in combat %s"):format(
        tostring(available), reason and (" (" .. tostring(reason) .. ")") or "", tostring(cvar),
        #sessions, tostring(InCombat())))
    local run = db.current
    if not run then
        Print("no current run; history " .. #db.history)
        return
    end
    local fights, done = #run.order, 0
    for _, fkey in ipairs(run.order) do
        if run.fights[fkey].done then
            done = done + 1
        end
    end
    local players = 0
    for _ in pairs(run.roster) do
        players = players + 1
    end
    Print(("run: %s (%s, map %s), fights %d (%d final), players %d, bosses %d, complete %s, left %s"):format(
        tostring(run.instance), tostring(run.instanceType), tostring(run.mapID), fights, done, players,
        #run.bosses, tostring(run.complete), tostring(run.leftAt ~= nil)))
    local list = self:EncounterList(run)
    if list then
        local names = {}
        for _, entry in ipairs(list) do
            names[#names + 1] = ("%s%s"):format(entry.name, Killed(run, entry) and "*" or "")
        end
        Print("guide bosses (* = killed): " .. table.concat(names, ", "))
    else
        Print("guide bosses: unknown (ceremony opens when you leave)")
    end
    Print(("queued ceremony: %s"):format(queued and queued.kind or "none"))
end
