-- Behavior tests for Podium against tests/wow_mock.lua.
-- Run with: python3 tests/run_tests.py Podium

local mock = _G.mock
local ns = _G.ns
local L = ns.L
local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(msg or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function printed(text)
    for _, line in ipairs(mock.printed) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end

-- party ---------------------------------------------------------------------------

local ME, TANK, HEALER, ROGUE, HUNTER = 1, 2, 3, 4, 5
local PARTY = {
    { unit = "player", guid = "Player-1-0001", name = "나", class = "MAGE", role = "DAMAGER" },
    { unit = "party1", guid = "Player-1-0002", name = "탱커", class = "WARRIOR", role = "TANK" },
    { unit = "party2", guid = "Player-1-0003", name = "힐러-아즈샤라", class = "PRIEST", role = "HEALER" },
    { unit = "party3", guid = "Player-1-0004", name = "도적", class = "ROGUE", role = "DAMAGER" },
    { unit = "party4", guid = "Player-1-0005", name = "사냥꾼", class = "HUNTER", role = "DAMAGER" },
}

local function joinParty(withRoles)
    for _, m in ipairs(PARTY) do
        mock.units[m.unit] = { name = m.name, guid = m.guid, class = m.class, role = withRoles and m.role or nil }
    end
end

local function solo()
    mock.units = { player = { name = PARTY[1].name, guid = PARTY[1].guid, class = "MAGE" } }
end

-- A typical pull: me 32% of the damage, rogue 27, hunter 26, tank 13, healer 2.
local function typical(scale, changes)
    scale = scale or 1
    local stats = {
        [ME] = { dmg = 320000, taken = 20000, spells = { dmg = { { 133, 150000 }, { 116, 90000 } } } },
        [TANK] = { dmg = 130000, taken = 700000, heal = 20000, ints = 1 },
        [HEALER] = { dmg = 20000, heal = 600000, taken = 30000, disp = 1, spells = { heal = { { 2061, 280000 } } } },
        [ROGUE] = { dmg = 270000, taken = 40000, ints = 1, spells = { dmg = { { 1752, 120000 } } } },
        [HUNTER] = { dmg = 260000, taken = 25000 },
    }
    for _, s in pairs(stats) do
        for k, v in pairs(s) do
            if type(v) == "number" and k ~= "ints" and k ~= "disp" and k ~= "deaths" then
                s[k] = v * scale
            end
        end
    end
    for index, change in pairs(changes or {}) do
        for k, v in pairs(change) do
            stats[index][k] = v
        end
    end
    return stats
end

local nextSession = 100
local function session(name, duration, stats, creature)
    nextSession = nextSession + 1
    local sources = {}
    for i, m in ipairs(PARTY) do
        local s = stats[i]
        if s then
            sources[#sources + 1] = {
                guid = m.guid, name = m.name, class = m.class, isLocal = m.unit == "player",
                dmg = s.dmg, heal = s.heal, taken = s.taken, avoid = s.avoid, ints = s.ints,
                disp = s.disp, deaths = s.deaths, spells = s.spells,
            }
        end
    end
    if creature then
        sources[#sources + 1] = { guid = "Creature-0-1-2-3-4-5", name = "Totem", class = "", dmg = 999999, creature = 5 }
    end
    return mock.addSession({ id = nextSession, name = name, duration = duration, sources = sources })
end

-- One pull: combat starts, the meter records the fight, combat ends.
local function pull(name, duration, stats, during)
    mock.inCombat = true
    mock.fire("PLAYER_REGEN_DISABLED")
    local s = session(name, duration, stats)
    if during then
        during(s)
    end
    mock.inCombat = false
    mock.fire("PLAYER_REGEN_ENABLED")
    mock.flushTimers()
    return s
end

local function killBoss(name, id, duration, stats)
    return pull(name, duration or 90, stats or typical(1.5), function()
        mock.fire("ENCOUNTER_END", id, name, 1, 5, 1)
    end)
end

local mapCounter = 500
local function enter(instance)
    mapCounter = mapCounter + 1
    mock.instance = instance or { name = "죽음의 폐광", type = "party", mapID = mapCounter, difficulty = "일반" }
    mock.fire("PLAYER_ENTERING_WORLD", false, false)
    mock.flushTimers()
    return mock.instance
end

local function leave()
    mock.instance = nil
    mock.fire("PLAYER_ENTERING_WORLD", false, false)
    mock.flushTimers()
end

local function journal(instance, bosses)
    local list = {}
    for i, b in ipairs(bosses) do
        list[i] = { name = b[1], id = b[2] }
    end
    mock.journal[instance.mapID] = { journalID = instance.mapID + 10000, bosses = list }
end

local function run()
    return PodiumDB.current
end

local function shown()
    return ns.Ceremony:IsShown()
end

local function report()
    return ns.Ceremony:GetReport()
end

local function playerIn(rep, index)
    for _, p in ipairs(rep.players) do
        if p.name == PARTY[index].name then
            return p
        end
    end
end

local function reset()
    assert(not ns:IsQueued(), "a ceremony was left waiting")
    ns.Ceremony:Hide()
    for k, v in pairs(ns.DEFAULTS) do
        PodiumDB[k] = v
    end
    PodiumDB.current = nil
    PodiumDB.history = {}
    mock.meter.sessions = {}
    mock.meter.secret = false
    mock.meter.available = true
    mock.inCombat = false
    mock.dead = false
    mock.instance = nil
    mock.journal = {}
    mock.chat = {}
    mock.printed = {}
    mock.sounds = {}
    mock.timers = {}
    mock.raid = false
    ns.lastReport = nil
    joinParty(true)
end

-- boot ----------------------------------------------------------------------------

test("loads with defaults, options and slash commands", function()
    mock.fire("ADDON_LOADED", "Podium")
    mock.fire("PLAYER_LOGIN")
    mock.fire("PLAYER_ENTERING_WORLD", true, false)
    mock.flushTimers()
    assert(PodiumDB and PodiumDB.enabled, "db")
    eq(PodiumDB.autoClose, 60, "auto close default")
    assert(mock.registeredCategory, "settings category")
    assert(mock.settings.PODIUM_everyBoss and mock.settings.PODIUM_scale, "settings registered")
    eq(mock.settings.PODIUM_autoClose.options.formatter(0), L.NEVER, "slider label")
    assert(SlashCmdList.PODIUM and SLASH_PODIUM1 == "/mvp", "slash")
    assert(printed(L.LOADED), "welcome message")
    eq(run(), nil, "no run outside dungeons")
end)

-- runs ----------------------------------------------------------------------------

test("entering a dungeon starts a run that ignores earlier fights", function()
    reset()
    session("Kobold", 20, typical())
    enter()
    local r = run()
    assert(r, "run started")
    eq(r.instance, "죽음의 폐광", "instance name")
    eq(r.difficulty, "일반", "difficulty")
    assert(r.skip[nextSession], "older session skipped")
    eq(#r.order, 0, "no fights yet")
end)

test("fights are copied after combat, never during it", function()
    reset()
    enter()
    local inCombatResult
    pull("Defias Thug", 30, typical(), function()
        inCombatResult = ns:Harvest()
    end)
    eq(inCombatResult, false, "harvest waits in combat")
    local r = run()
    eq(#r.order, 1, "one fight")
    local fight = r.fights[r.order[1]]
    eq(fight.name, "Defias Thug", "fight name")
    eq(fight.dur, 30, "duration")
    local me = fight.p[PARTY[ME].guid]
    eq(me.dmg, 320000, "damage")
    eq(me.taken, 20000, "damage taken")
    eq(me.dsp, 133, "key ability")
    eq(me.dspA, 150000, "key ability amount")
    eq(fight.p[PARTY[HEALER].guid].hsp, 2061, "healer key ability")
    eq(r.roster[PARTY[ME].guid].isLocal, true, "local player")
    eq(r.roster[PARTY[TANK].guid].role, "TANK", "role from group")
end)

test("creatures on the meter are ignored", function()
    reset()
    enter()
    mock.inCombat = true
    session("Pack", 20, typical(), true)
    mock.inCombat = false
    ns:Harvest()
    local fight = run().fights[run().order[1]]
    local count = 0
    for _ in pairs(fight.p) do
        count = count + 1
    end
    eq(count, 5, "five players, no totem")
end)

test("secret numbers are read once the client shows them", function()
    reset()
    enter()
    mock.meter.secret = true
    pull("Pack", 20, typical())
    eq(#run().order, 0, "nothing read while secret")
    mock.meter.secret = false
    mock.fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, nextSession)
    mock.flushTimers()
    eq(#run().order, 1, "read later")
end)

test("an unfinished fight is read again until a newer one starts", function()
    reset()
    enter()
    local s = pull("Long fight", 30, typical())
    -- The player died and dropped out of combat; the party kept fighting.
    s.sources[1].dmg = 500000
    s.duration = 45
    mock.fire("DAMAGE_METER_COMBAT_SESSION_UPDATED", 0, s.id)
    mock.flushTimers()
    local r = run()
    eq(r.fights[r.order[1]].p[PARTY[ME].guid].dmg, 500000, "updated")
    pull("Next", 20, typical())
    assert(r.fights[r.order[1]].done, "older fight is final")
    local reads = mock.meter.reads
    ns:Harvest()
    eq(mock.meter.reads - reads, 7, "only the newest fight is read again")
end)

-- completion ------------------------------------------------------------------------

test("the last boss in the guide opens the ceremony after combat", function()
    reset()
    local inst = enter()
    journal(inst, { { "Rhahk'Zor", 201 }, { "Edwin VanCleef", 202 } })
    pull("Defias Thug", 30, typical())
    killBoss("Rhahk'Zor", 201, 60)
    assert(not shown(), "not after the first boss")
    eq(run().complete, nil, "not complete")
    pull("Defias Pirate", 25, typical())
    killBoss("Edwin VanCleef", 202, 95, typical(1.6))
    assert(shown(), "shown after the last boss")
    mock.inCombat = true
    mock.fire("PLAYER_REGEN_DISABLED")
    local stillShown = shown()
    mock.inCombat = false
    eq(stillShown, false, "closes when combat starts")
    local rep = ns.lastReport
    assert(rep, "ceremony built")
    eq(run().complete, "final", "complete")
    eq(rep.title, L.TITLE_CLEAR, "title")
    eq(rep.tag, L.TAG_CLEAR, "tag")
    eq(rep.bosses, 2, "bosses")
    eq(rep.mvp.name, "나", "top damage dealer is MVP")
    assert(rep.potg, "play of the game")
    local r = run()
    local tagged = 0
    for _, fkey in ipairs(r.order) do
        if r.fights[fkey].boss then
            tagged = tagged + 1
        end
    end
    eq(tagged, 2, "boss fights tagged")
    eq(r.fights[r.order[#r.order]].final, true, "last boss fight marked")
    eq(r.shown, true, "run marked shown")
    assert(#mock.sounds > 0, "fanfare played")
end)

test("the ceremony waits for combat to end", function()
    reset()
    local inst = enter()
    journal(inst, { { "Boss", 301 } })
    mock.inCombat = true
    session("Boss", 80, typical())
    mock.fire("ENCOUNTER_END", 301, "Boss", 1, 5, 1)
    mock.flushTimers()
    assert(not shown(), "not in combat")
    assert(ns:IsQueued(), "waiting")
    mock.inCombat = false
    mock.fire("PLAYER_REGEN_ENABLED")
    mock.flushTimers()
    assert(shown(), "shown after combat")
end)

test("BOSS_KILL and ENCOUNTER_END count one kill; wipes don't count", function()
    reset()
    local inst = enter()
    journal(inst, { { "A", 401 }, { "B", 402 } })
    pull("A", 60, typical(), function()
        mock.fire("ENCOUNTER_END", 401, "A", 1, 5, 0)
    end)
    eq(#run().bosses, 0, "wipe")
    pull("A", 60, typical(), function()
        mock.fire("BOSS_KILL", 401, "A")
        mock.fire("ENCOUNTER_END", 401, "A", 1, 5, 1)
    end)
    eq(#run().bosses, 1, "one kill")
    assert(not shown(), "first boss isn't the last")
end)

test("dungeon finder completion opens the ceremony", function()
    reset()
    enter()
    pull("Trash", 30, typical())
    mock.fire("LFG_COMPLETION_REWARD")
    mock.flushTimers()
    assert(shown(), "shown")
    eq(run().complete, "lfg", "reason")
end)

test("unknown dungeon: ceremony when leaving after a boss", function()
    reset()
    enter()
    pull("Trash", 30, typical())
    killBoss("Mystery Boss", 501)
    assert(not shown(), "not known to be the last boss")
    leave()
    assert(shown(), "shown when leaving")
    eq(report().title, L.TITLE_LEAVE, "title")
    eq(run().complete, "leave", "reason")
end)

test("running out as a ghost isn't leaving; the run continues", function()
    reset()
    local inst = enter()
    killBoss("Mystery Boss", 601)
    mock.dead = true
    leave()
    assert(not shown(), "no ceremony for a corpse run")
    session("Graveyard wolf", 10, typical()) -- a fight outside
    mock.dead = false
    mock.instance = inst
    mock.fire("PLAYER_ENTERING_WORLD", false, false)
    mock.flushTimers()
    local r = run()
    eq(r.leftAt, nil, "back inside")
    eq(#r.bosses, 1, "same run")
    pull("Trash", 20, typical())
    eq(#r.order, 2, "outside fight skipped")
end)

test("leaving without a boss kill: no ceremony; next dungeon archives the run", function()
    reset()
    enter()
    pull("Trash", 30, typical())
    leave()
    assert(not shown(), "no ceremony")
    local old = run()
    session("Outside", 10, typical())
    ns:Harvest()
    eq(#old.order, 1, "fights outside don't count")
    enter()
    eq(PodiumDB.history[1], old, "archived")
    assert(run() ~= old, "new run")
end)

test("a fight right before zoning out still counts", function()
    reset()
    enter()
    killBoss("Mystery Boss", 551)
    session("Last pull", 25, typical()) -- not read yet when the loading screen starts
    leave()
    eq(#run().order, 2, "last fight kept")
    assert(shown(), "ceremony")
    eq(report().combatTime, 90 + 25, "both fights in the ceremony")
end)

test("every-boss option shows a ceremony per boss fight", function()
    reset()
    PodiumDB.everyBoss = true
    local inst = enter()
    journal(inst, { { "First", 701 }, { "Last", 702 } })
    pull("Trash", 30, typical())
    killBoss("First", 701, 64)
    assert(shown(), "boss ceremony")
    local rep = report()
    eq(rep.tag, L.TAG_BOSS, "tag")
    eq(rep.title, L.TITLE_BOSS:format("First"), "title")
    eq(rep.combatTime, 64, "only the boss fight")
    ns.Ceremony:Hide()
    killBoss("Last", 702, 90)
    eq(report().title, L.TITLE_CLEAR, "full ceremony at the end")
    eq(report().combatTime, 30 + 64 + 90, "whole run")
end)

test("a damage meter reset keeps recorded fights", function()
    reset()
    enter()
    pull("One", 30, typical())
    pull("Two", 30, typical())
    C_DamageMeter.ResetAllCombatSessions()
    mock.fire("DAMAGE_METER_RESET")
    nextSession = 100 -- the meter numbers sessions again
    pull("Three", 30, typical())
    local r = run()
    eq(#r.order, 3, "kept and added")
    eq(r.order[3], "2:101", "new epoch")
end)

test("logging back in inside the dungeon continues the run", function()
    reset()
    local inst = enter()
    pull("One", 30, typical())
    local r = run()
    mock.meter.sessions = {}
    nextSession = 100
    mock.instance = inst
    mock.fire("PLAYER_ENTERING_WORLD", true, false)
    eq(run(), r, "same run")
    eq(r.epoch, 2, "new numbering")
    pull("Two", 30, typical())
    eq(#r.order, 2, "both fights")
end)

test("reload after the ceremony keeps the run; a new visit starts a new one", function()
    reset()
    local inst = enter()
    journal(inst, { { "Boss", 801 } })
    killBoss("Boss", 801)
    local r = run()
    mock.fire("PLAYER_ENTERING_WORLD", false, true)
    eq(run(), r, "kept after reload")
    leave()
    mock.instance = inst
    mock.fire("PLAYER_ENTERING_WORLD", false, false)
    assert(run() ~= r, "new run after a clear")
    eq(PodiumDB.history[1], r, "old run archived")
end)

test("raids can be left out", function()
    reset()
    PodiumDB.raids = false
    enter({ name = "Molten Core", type = "raid", mapID = 409 })
    eq(run(), nil, "no run")
    PodiumDB.raids = true
    enter({ name = "Molten Core", type = "raid", mapID = 409 })
    assert(run(), "run")
end)

test("disabled: no ceremony, still recorded", function()
    reset()
    SlashCmdList.PODIUM("off")
    eq(PodiumDB.enabled, false, "off")
    enter()
    pull("Trash", 30, typical())
    mock.fire("LFG_COMPLETION_REWARD")
    mock.flushTimers()
    assert(not shown(), "nothing shown")
    eq(#run().order, 1, "recorded")
    SlashCmdList.PODIUM("on")
    eq(PodiumDB.enabled, true, "on")
end)

test("damage meter unavailable", function()
    reset()
    mock.meter.available = false
    mock.meter.reason = "level"
    enter()
    pull("Trash", 30, typical())
    mock.fire("LFG_COMPLETION_REWARD")
    mock.flushTimers()
    assert(not shown(), "nothing to show")
    assert(printed("level"), "reason printed")
end)

-- scoring ---------------------------------------------------------------------------

local function build(fights, roles)
    local r = ns.NewRun({ name = "Test", type = "party", mapID = 1 })
    for i, m in ipairs(PARTY) do
        r.roster[m.guid] = { name = m.name, class = m.class, role = roles ~= false and m.role or nil, isLocal = i == 1 }
    end
    for i, f in ipairs(fights) do
        local p = {}
        for index, stats in pairs(f.stats) do
            local copy = {}
            for k, v in pairs(stats) do
                if k ~= "spells" then
                    copy[k] = v
                end
            end
            p[PARTY[index].guid] = copy
        end
        local key = "1:" .. i
        r.fights[key] = { name = f.name, dur = f.dur, p = p, boss = f.boss, final = f.final }
        r.order[#r.order + 1] = key
        if f.boss then
            r.bosses[#r.bosses + 1] = { name = f.boss, fkey = key }
        end
    end
    return ns.Awards.Build(r, { kind = "clear" })
end

test("impact: a typical party scores around 100, the best performer wins", function()
    reset()
    local rep = build({ { name = "Pull", dur = 40, stats = typical() } })
    for _, p in ipairs(rep.players) do
        assert(p.score >= 85 and p.score <= 125, p.name .. " score " .. p.score)
    end
    eq(rep.mvp.name, "나", "top dps")
    eq(rep.players[1].rank, 1, "ranked")
end)

test("impact: interrupts, dispels and deaths can swing the MVP", function()
    reset()
    local even = typical(1, { [ME] = { dmg = 283000 }, [ROGUE] = { dmg = 283000 }, [HUNTER] = { dmg = 283000 } })
    even[HEALER].disp = 10
    local rep = build({ { name = "Pull", dur = 40, stats = even } })
    eq(rep.mvp.name, PARTY[HEALER].name, "healer with many dispels")
    eq(rep.mvp.bonus, 20, "bonus capped")
    local deaths = typical(1, { [ME] = { deaths = 3 } })
    rep = build({ { name = "Pull", dur = 40, stats = deaths } })
    assert(rep.mvp.name ~= "나", "dying three times costs the MVP")
    eq(playerIn(rep, ME).penalty, 36, "death penalty")
end)

test("roles are guessed when the group has none", function()
    reset()
    local rep = build({ { name = "Pull", dur = 40, stats = typical() } }, false)
    eq(playerIn(rep, TANK).role, "TANK", "tank")
    eq(playerIn(rep, HEALER).role, "HEALER", "healer")
    eq(playerIn(rep, ROGUE).role, "DAMAGER", "rogue")
    eq(playerIn(rep, ME).role, "DAMAGER", "me")
end)

test("play of the game: carrying a boss fight", function()
    reset()
    local boss = typical(1.4, { [ROGUE] = { dmg = 900000 } })
    local rep = build({
        { name = "Trash", dur = 30, stats = typical() },
        { name = "Boss", dur = 80, stats = boss, boss = "Boss" },
    })
    local potg = rep.potg
    eq(potg.player.name, "도적", "rogue")
    eq(potg.kind, "damage", "kind")
    eq(potg.fightName, "Boss", "fight")
    eq(potg.boss, true, "boss fight")
    assert(potg.text:find("47", 1, true), "share in text: " .. potg.text) -- 900k of 1.92M
end)

test("play of the game: a healer saving the last boss", function()
    reset()
    local final = typical(1)
    final[HEALER].heal = 2400000
    final[TANK].taken = 1800000
    local rep = build({
        { name = "Trash", dur = 40, stats = typical() },
        { name = "Trash", dur = 40, stats = typical() },
        { name = "Captain", dur = 60, stats = final, boss = "Captain", final = true },
    })
    eq(rep.potg.kind, "heal", "kind")
    eq(rep.potg.player.name, PARTY[HEALER].name, "healer")
    assert(rep.potg.text:find(ns.FormatNumber(40000), 1, true), "healing per second in text: " .. rep.potg.text)
end)

test("short trash fights can't be the play of the game", function()
    reset()
    local burst = typical(1, { [HUNTER] = { dmg = 2000000 } })
    local rep = build({
        { name = "Blip", dur = 3, stats = burst },
        { name = "Pull", dur = 40, stats = typical() },
    })
    eq(rep.potg.fightName, "Pull", "only the real fight")
end)

test("award categories", function()
    reset()
    local stats = typical(1, { [HUNTER] = { avoid = 50000, deaths = 2 }, [ROGUE] = { ints = 6 } })
    stats[HEALER].disp = 4
    local rep = build({ { name = "Pull", dur = 40, stats = stats } })
    local byID = {}
    for _, award in ipairs(rep.awards) do
        byID[award.id] = award.player.name
    end
    eq(byID.DAMAGE, "나", "top damage")
    eq(byID.HEALING, PARTY[HEALER].name, "top healer")
    eq(byID.TANK, "탱커", "tank")
    eq(byID.INTERRUPTS, "도적", "interrupts")
    eq(byID.DISPELS, PARTY[HEALER].name, "dispels")
    eq(byID.FLOOR, "사냥꾼", "floor")
    eq(byID.DEATHS, "사냥꾼", "deaths")
    eq(#rep.awards, 7, "capped at seven")
    PodiumDB.fun = false
    rep = build({ { name = "Pull", dur = 40, stats = stats } })
    for _, award in ipairs(rep.awards) do
        assert(award.id ~= "FLOOR" and award.id ~= "DEATHS", "no joke awards")
    end
    eq(rep.awards[#rep.awards].id, "SURVIVOR", "survivor instead")
end)

test("a solo run works", function()
    reset()
    local rep = build({ { name = "Pull", dur = 40, stats = { [ME] = { dmg = 100000, taken = 5000 } } } })
    eq(#rep.players, 1, "one player")
    eq(rep.mvp.score, 100, "score")
    eq(rep.potg.player.name, "나", "potg")
end)

test("number formatting", function()
    local fmt = ns.FormatNumber
    eq(fmt(999), "999", "small")
    eq(fmt(1234), "1,234", "thousands")
    if GetLocale() == "koKR" then
        eq(fmt(12345), "1.2만", "만")
        eq(fmt(1234567), "123만", "백만")
        eq(fmt(123456789), "1.23억", "억")
    else
        eq(fmt(12345), "12.3K", "K")
        eq(fmt(1234567), "1.23M", "M")
    end
    eq(ns.FormatTime(83), "1:23", "time")
    eq(ns.FormatTime(3725), "1:02:05", "hours")
    eq(ns.Awards.ShortName("힐러-아즈샤라"), "힐러", "realm removed")
end)

-- window --------------------------------------------------------------------------

local function frame()
    return ns.Ceremony:GetFrame()
end

local function update(seconds, step)
    step = step or 0.05
    local f = frame()
    for _ = 1, math.floor(seconds / step + 0.5) do
        if not f.shown then
            return
        end
        f.scripts.OnUpdate(f, step)
    end
end

local ANIM = ns.Ceremony.ANIM

local function slotFor(name)
    for _, slot in ipairs(frame().slots) do
        if slot.player and slot.player.name == name then
            return slot
        end
    end
end

test("preview: reveal, skip and contents", function()
    reset()
    mock.units.player.name = "나"
    SlashCmdList.PODIUM("test")
    assert(shown(), "shown")
    local f = frame()
    local mvp = f.slots[1]
    eq(mvp.alpha, 0, "MVP hidden at first")
    update(1)
    eq(mvp.alpha, 0, "MVP not yet")
    assert(f.potg.alpha > 0, "play of the game revealed first")
    f.scripts.OnMouseUp(f)
    for rank = 1, 5 do
        eq(f.slots[rank].alpha, 1, "slot " .. rank .. " shown")
        eq(f.slots[rank].scale, 1, "slot " .. rank .. " scale")
        eq(f.slots[rank].model.modelAlpha, 1, "model " .. rank .. " faded in")
    end
    local rep = report()
    eq(rep.mvp.name, "나", "you are the MVP of the preview")
    eq(mvp.model.unit, "player", "your own character")
    eq(mvp.model.animation, ANIM.FLEX, "MVP flexes")
    eq(mvp.badge.text, L.MVP, "MVP badge")
    -- the rest of the party plays the other parts with their own characters
    for i = 2, 5 do
        local slot = slotFor(PARTY[i].name)
        assert(slot, PARTY[i].name .. " on the podium")
        eq(slot.model.unit, PARTY[i].unit, PARTY[i].name .. "'s character")
        eq(slot.model.shown, true, "model shown")
        eq(slot.icon.shown, false, "no icon")
        assert(slot.model.animation and slot.model.animation ~= ANIM.STAND, "emoting")
    end
    eq(rep.title, L.TITLE_DEMO, "title")
    assert(f.potg.text.text and f.potg.text.text ~= "", "POTG text")
    eq(f.header.title.text, L.TITLE_DEMO, "header")
    assert(#mock.sounds >= 2, "sounds")
    assert(f.width <= 900 and f.height <= 620, "window fits a small screen")
end)

test("preview when alone: stand-ins for the made-up party", function()
    reset()
    solo()
    ns:ShowDemo()
    ns.Ceremony:Skip()
    local shownModels, icons = 0, 0
    for _, slot in ipairs(frame().slots) do
        if slot.player then
            if slot.model.shown then
                shownModels = shownModels + 1
                eq(slot.model.unit, "player", "only your character")
            else
                icons = icons + 1
                eq(slot.icon.shown, true, "class icon")
            end
        end
    end
    eq(shownModels, 1, "one character")
    eq(icons, 4, "four icons")
end)

test("each player's own character emotes for their result", function()
    reset()
    PodiumDB.fun = false
    local inst = enter()
    journal(inst, { { "Boss", 901 } })
    -- 3 interrupts in total make the rogue interrupt king, but no single
    -- fight has the 3 a play of the game needs
    local stats = typical(1.5, { [ROGUE] = { ints = 2 } })
    pull("Trash", 30, typical())
    killBoss("Boss", 901, 90, stats)
    assert(shown(), "ceremony")
    ns.Ceremony:Skip()
    local f = frame()
    local titles = ns.Ceremony.Titles(report())
    for _, slot in ipairs(f.slots) do
        local p = slot.player
        if p then
            local member
            for _, m in ipairs(PARTY) do
                if m.guid == p.key then
                    member = m
                end
            end
            eq(slot.model.unit, member.unit, p.name .. " matched to their unit")
            eq(slot.model.animation, ns.Ceremony.EmotesFor(titles[p])[1], p.name .. " emote")
        end
    end
    eq(f.slots[1].model.animation, ANIM.FLEX, "MVP flexes")
    eq(slotFor("도적").model.animation, ANIM.POINT, "interrupt king points")
    eq(slotFor("도적").badge.text, L.AWARD_INTERRUPTS, "badge above the head")
    eq(slotFor("사냥꾼").model.animation, ANIM.APPLAUD, "no award: applauds the MVP")
    eq(slotFor("사냥꾼").badge.text, "", "no badge")
end)

test("emote choice", function()
    local E, emotes = ns.Ceremony.EMOTES, ns.Ceremony.EmotesFor
    eq(emotes(nil), E.NONE, "nothing")
    eq(emotes({ { id = "MVP" }, { id = "DEATHS" } }), E.MVP, "MVP wins")
    eq(emotes({ { id = "POTG" }, { id = "FLOOR" } }), E.POTG, "POTG wins")
    eq(emotes({ { id = "DAMAGE" }, { id = "DEATHS" } }), E.DEATHS, "joke award over a category")
    eq(emotes({ { id = "TANK" } }), E.TANK, "category")
    eq(E.DEATHS[1], ANIM.CRY, "cry")
    eq(E.FLOOR[1], ANIM.CHICKEN, "chicken")
end)

test("emotes repeat after a short pause", function()
    reset()
    ns:ShowDemo()
    ns.Ceremony:Skip()
    local model = frame().slots[1].model
    eq(model.animation, ANIM.FLEX, "first emote")
    model.scripts.OnAnimFinished(model)
    eq(model.animation, ANIM.STAND, "stands for a moment")
    update(3)
    eq(model.animation, ANIM.ROAR, "next emote")
    model.scripts.OnAnimFinished(model)
    update(3)
    eq(model.animation, ANIM.FLEX, "and around again")
end)

test("characters out of range or gone show their class icon", function()
    reset()
    mock.hidden.party2 = true
    mock.noModel.party3 = true
    ns:ShowDemo()
    ns.Ceremony:Skip()
    local hidden, broken = slotFor(PARTY[3].name), slotFor(PARTY[4].name)
    eq(hidden.model.shown, false, "too far: no model")
    eq(hidden.icon.shown, true, "icon instead")
    eq(broken.model.shown, false, "model failed")
    eq(broken.icon.shown, true, "icon instead")
    eq(slotFor(PARTY[2].name).model.shown, true, "others still shown")
    mock.hidden, mock.noModel = {}, {}
    -- an old ceremony after the group broke up
    ns.Ceremony:Hide()
    eq(frame().slots[1].model.unit, nil, "models released on close")
    solo()
    ns:ShowDemo()
    ns.Ceremony:Skip()
    eq(slotFor(PARTY[2].name), nil, "party gone from the preview")
end)

test("characters can be turned off", function()
    reset()
    PodiumDB.models = false
    ns:ShowDemo()
    ns.Ceremony:Skip()
    for _, slot in ipairs(frame().slots) do
        if slot.player then
            eq(slot.model.shown, false, "no model")
            eq(slot.icon.shown, true, "icon")
        end
    end
    assert(mock.settings.PODIUM_models, "option in the settings")
end)

test("characters turn toward the MVP", function()
    reset()
    ns:ShowDemo()
    ns.Ceremony:Skip()
    local mvpX = frame().slots[1].baseX
    for _, slot in ipairs(frame().slots) do
        if slot.player then
            if slot.baseX < mvpX then
                assert(slot.model.facing > 0, "left side turns right")
            elseif slot.baseX > mvpX then
                assert(slot.model.facing < 0, "right side turns left")
            else
                eq(slot.model.facing, 0, "MVP faces front")
            end
        end
    end
    eq(frame().slots[2].baseX < mvpX, true, "2nd place left of the MVP")
    eq(frame().slots[3].baseX > mvpX, true, "3rd place right of the MVP")
end)

test("big groups: top five on the podium", function()
    reset()
    local r = ns.NewRun({ name = "Raid", type = "raid", mapID = 2 })
    local p = {}
    for i = 1, 8 do
        local key = "Player-1-01" .. i
        r.roster[key] = { name = "R" .. i, class = "MAGE", role = "DAMAGER" }
        p[key] = { dmg = 1000 * i, taken = 10 }
    end
    r.fights["1:1"] = { name = "Pull", dur = 30, p = p }
    r.order[1] = "1:1"
    ns.Ceremony:Show(ns.Awards.Build(r, { kind = "clear" }))
    ns.Ceremony:Skip()
    local count = 0
    for _, slot in ipairs(frame().slots) do
        if slot.shown then
            count = count + 1
        end
    end
    eq(count, 5, "five places")
    eq(frame().slots[1].player.name, "R8", "best in the middle")
    assert(frame().more.text:find("3", 1, true), "the rest counted: " .. tostring(frame().more.text))
end)

test("auto close counts down, pauses under the mouse", function()
    reset()
    PodiumDB.autoClose = 5
    ns:ShowDemo()
    local f = frame()
    ns.Ceremony:Skip()
    f.mouseOver = true
    update(8)
    assert(shown(), "paused while hovered")
    f.mouseOver = false
    update(3)
    assert(shown(), "still counting")
    assert(f.hint.text:find("2", 1, true) or f.hint.text:find("3", 1, true), "countdown shown: " .. f.hint.text)
    update(3)
    assert(not shown(), "closed")
end)

test("animation runs many frames without errors; scale and dim options", function()
    reset()
    PodiumDB.scale = 80
    PodiumDB.dim = false
    ns:ShowDemo()
    update(12, 1 / 60)
    eq(frame().scale, 0.8, "scale")
    eq(frame().dim.shown, false, "no dim")
    eq(#UISpecialFrames, 1, "Esc closes it")
end)

test("share posts to group chat, or prints when alone", function()
    reset()
    ns:ShowDemo()
    frame().shareButton.scripts.OnClick(frame().shareButton)
    assert(#mock.chat >= 3, "lines sent")
    eq(mock.chat[1].channel, "PARTY", "party chat")
    assert(mock.chat[1].msg:find(L.TITLE_DEMO, 1, true), "title in first line")
    solo()
    mock.chat = {}
    SlashCmdList.PODIUM("share")
    eq(#mock.chat, 0, "nothing sent alone")
    assert(printed(L.SHARE_SOLO), "printed instead")
end)

test("slash commands and history", function()
    reset()
    SlashCmdList.PODIUM("")
    assert(printed(L.NO_RUN:sub(1, 10)), "no run yet")
    SlashCmdList.PODIUM("help")
    assert(printed("/mvp test"), "help")
    PodiumDB.keep = 3
    for i = 1, 5 do
        enter()
        pull("Trash " .. i, 30, typical())
        leave()
    end
    enter()
    eq(#PodiumDB.history, 3, "history capped")
    mock.printed = {}
    SlashCmdList.PODIUM("history")
    assert(printed("죽음의 폐광"), "history listed")
    SlashCmdList.PODIUM("history 2")
    assert(shown(), "old run shown")
    SlashCmdList.PODIUM("debug")
    assert(printed("damage meter:"), "debug")
    SlashCmdList.PODIUM("history clear")
    eq(#PodiumDB.history, 0, "cleared")
    Podium_OnAddonCompartmentClick(nil, "RightButton")
    eq(mock.openedCategory, 42, "options opened")
    Podium_OnAddonCompartmentEnter(nil, UIParent)
    Podium_OnAddonCompartmentLeave()
end)

-- run ----------------------------------------------------------------------------

local passed, failed = 0, 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        passed = passed + 1
        io.write("  ok   ", t.name, "\n")
    else
        failed = failed + 1
        io.write("  FAIL ", t.name, "\n       ", tostring(err), "\n")
    end
end
io.write(("\n%d passed, %d failed\n"):format(passed, failed))
return failed
