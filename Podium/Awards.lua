local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Turning a run into a ceremony: MVP, Play of the Game and awards.
--
-- MVP "impact": each player is compared with what their role usually does
-- in a group like this one, so 100 = a typical tank / healer / damage
-- dealer and the winner is whoever did best for their role.
--   damage dealer: share of the party's damage
--   healer:        share of the party's healing (80%) + damage (20%)
--   tank:          share of damage taken (50%) + damage (50%)
--   +2 per interrupt or dispel (up to +20), -12 per death (up to -48),
--   up to -20 for the party's avoidable damage taken.
--
-- Play of the Game: the single most outstanding moment of one fight -
-- carrying a fight's damage, healing much harder than usual, holding a
-- big pull, or a string of interrupts. Boss fights count more.
--------------------------------------------------------------------------

local Awards = {}
ns.Awards = Awards

local STAT_KEYS = { "dmg", "heal", "taken", "avoid", "ints", "disp", "deaths" }

-- How much of each kind of work a role is expected to do, relative to the
-- others. A role's expected share = its weight / sum of everyone's weights.
-- In a usual 5-player group (tank, healer, 3 damage) that is: tank 15% of
-- the damage, healer 3%; healer 93% of the healing; tank 83% of the damage taken.
local DAMAGE_WEIGHT = { DAMAGER = 1, TANK = 0.55, HEALER = 0.1 }
local HEAL_WEIGHT = { HEALER = 1, TANK = 0.04, DAMAGER = 0.01 }
local TAKEN_WEIGHT = { TANK = 1, DAMAGER = 0.05, HEALER = 0.05 }

local POTG_KIND_WEIGHT = { damage = 1, heal = 0.95, tank = 0.85, interrupts = 0.9 }
local MIN_POTG_FIGHT = 8 -- seconds; shorter trash fights can't be the play of the game
local MAX_AWARDS = 7

Awards.ICONS = {
    DAMAGE = "Interface\\Icons\\Ability_DualWield",
    HEALING = "Interface\\Icons\\Spell_Holy_FlashHeal",
    TANK = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
    INTERRUPTS = "Interface\\Icons\\Ability_Kick",
    DISPELS = "Interface\\Icons\\Spell_Holy_DispelMagic",
    SURVIVOR = "Interface\\Icons\\Spell_Holy_PowerWordShield",
    FLOOR = "Interface\\Icons\\Spell_Fire_Fire",
    DEATHS = "Interface\\Icons\\Ability_Rogue_FeignDeath",
}

local floor, min, max = math.floor, math.min, math.max

local function Round(x)
    return floor(x + 0.5)
end

local function Num(value)
    return ns.FormatNumber(value)
end

-- "Name-Realm" -> "Name"
local function ShortName(name)
    return (tostring(name or L.UNKNOWN):gsub("%-.*$", ""))
end
Awards.ShortName = ShortName

-- value's share of total compared with the expected share for the role
-- (1 = exactly as expected), capped at 3.
local function Index(value, total, weight, weightSum)
    if not total or total <= 0 or weightSum <= 0 or weight <= 0 then
        return 0
    end
    return min(3, (value / total) / (weight / weightSum))
end

local function FightKeys(run, request)
    if request.kind == "boss" then
        local boss = run.bosses[request.boss or #run.bosses]
        local fkey = boss and boss.fkey or run.order[#run.order]
        return { fkey }
    end
    return run.order
end

-- Adds up every fight per player.
local function Aggregate(run, keys)
    local players, list = {}, {}
    local combatTime = 0
    for _, fkey in ipairs(keys) do
        local fight = run.fights[fkey]
        if fight then
            local duration = fight.dur or 0
            combatTime = combatTime + duration
            for key, stats in pairs(fight.p or {}) do
                local p = players[key]
                if not p then
                    local info = run.roster[key] or {}
                    p = {
                        key = key,
                        name = info.name or L.UNKNOWN,
                        class = info.class,
                        role = info.role,
                        isLocal = info.isLocal,
                        time = 0,
                    }
                    for _, stat in ipairs(STAT_KEYS) do
                        p[stat] = 0
                    end
                    players[key] = p
                    list[#list + 1] = p
                end
                p.time = p.time + duration
                for _, stat in ipairs(STAT_KEYS) do
                    p[stat] = p[stat] + (stats[stat] or 0)
                end
            end
        end
    end
    return players, list, combatTime
end

local function Totals(list)
    local totals = {}
    for _, stat in ipairs(STAT_KEYS) do
        totals[stat] = 0
    end
    for _, p in ipairs(list) do
        for _, stat in ipairs(STAT_KEYS) do
            totals[stat] = totals[stat] + p[stat]
        end
    end
    return totals
end

-- Roles the group didn't assign are guessed: mostly healing = healer,
-- by far the most damage taken = tank, everyone else = damage.
function Awards.GuessRoles(list, totals)
    local count = #list
    local hasTank = false
    for _, p in ipairs(list) do
        if p.role == "TANK" then
            hasTank = true
        end
    end
    for _, p in ipairs(list) do
        if not p.role and totals.heal > 0 and p.heal > 0 and p.heal >= p.dmg and p.heal / totals.heal >= 0.25 then
            p.role = "HEALER"
        end
    end
    if not hasTank and count >= 3 and totals.taken > 0 then
        local threshold = min(0.35, max(0.12, 1.8 / count))
        local maxTanks = count <= 5 and 1 or (count <= 10 and 2 or 3)
        local candidates = {}
        for _, p in ipairs(list) do
            if not p.role and p.taken / totals.taken >= threshold then
                candidates[#candidates + 1] = p
            end
        end
        table.sort(candidates, function(a, b) return a.taken > b.taken end)
        for i = 1, min(maxTanks, #candidates) do
            candidates[i].role = "TANK"
        end
    end
    for _, p in ipairs(list) do
        p.role = p.role or "DAMAGER"
    end
end

local function WeightSums(list, roleOf)
    local damage, heal, taken = 0, 0, 0
    for _, p in ipairs(list) do
        local role = roleOf(p)
        damage = damage + DAMAGE_WEIGHT[role]
        heal = heal + HEAL_WEIGHT[role]
        taken = taken + TAKEN_WEIGHT[role]
    end
    return damage, heal, taken
end

local function SelfRole(p)
    return p.role
end

function Awards.Score(list, totals)
    local wDamage, wHeal, wTaken = WeightSums(list, SelfRole)
    for _, p in ipairs(list) do
        local role = p.role
        local damageIndex = Index(p.dmg, totals.dmg, DAMAGE_WEIGHT[role], wDamage)
        local healIndex = Index(p.heal, totals.heal, HEAL_WEIGHT[role], wHeal)
        local takenIndex = Index(p.taken, totals.taken, TAKEN_WEIGHT[role], wTaken)
        local base
        if role == "HEALER" and totals.heal > 0 then
            base = 0.8 * healIndex + 0.2 * min(damageIndex, 1.5)
        elseif role == "TANK" and totals.taken > 0 then
            base = 0.5 * min(takenIndex, 2) + 0.5 * damageIndex
        else
            base = damageIndex
        end
        local penalty = min(48, 12 * p.deaths)
        if totals.avoid > 0 and #list > 1 then
            penalty = penalty + 20 * p.avoid / totals.avoid
        end
        p.base = Round(100 * base)
        p.bonus = min(20, 2 * (p.ints + p.disp))
        p.penalty = Round(penalty)
        p.score = max(0, p.base + p.bonus - p.penalty)
        p.dmgShare = totals.dmg > 0 and p.dmg / totals.dmg or 0
        p.healShare = totals.heal > 0 and p.heal / totals.heal or 0
        p.takenShare = totals.taken > 0 and p.taken / totals.taken or 0
        p.dps = p.time > 0 and p.dmg / p.time or 0
        p.hps = p.time > 0 and p.heal / p.time or 0
    end
    table.sort(list, function(a, b)
        if a.score ~= b.score then
            return a.score > b.score
        end
        if a.dmg ~= b.dmg then
            return a.dmg > b.dmg
        end
        return tostring(a.key) < tostring(b.key)
    end)
    for rank, p in ipairs(list) do
        p.rank = rank
    end
end

local function FightTotals(fight)
    local totals = { count = 0 }
    for _, stat in ipairs(STAT_KEYS) do
        totals[stat] = 0
    end
    for _, stats in pairs(fight.p or {}) do
        totals.count = totals.count + 1
        for _, stat in ipairs(STAT_KEYS) do
            totals[stat] = totals[stat] + (stats[stat] or 0)
        end
    end
    return totals
end

local function SortedKeys(t)
    local keys = {}
    for key in pairs(t) do
        keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    return keys
end

-- Finds the play of the game. Returns nil if no fight qualifies.
function Awards.PlayOfTheGame(run, keys, players)
    local fightTotals, biggest = {}, 0
    for _, fkey in ipairs(keys) do
        local fight = run.fights[fkey]
        if fight then
            fightTotals[fkey] = FightTotals(fight)
            biggest = max(biggest, fightTotals[fkey].dmg)
        end
    end

    local best
    local function Consider(score, info)
        if score > 0 and (not best or score > best.score) then
            info.score = score
            best = info
        end
    end

    for index, fkey in ipairs(keys) do
        local fight = run.fights[fkey]
        local totals = fightTotals[fkey]
        local duration = fight and fight.dur or 0
        if fight and duration > 0 and (duration >= MIN_POTG_FIGHT or fight.boss) then
            local fighters = {}
            for key in pairs(fight.p) do
                if players[key] then
                    fighters[#fighters + 1] = players[key]
                end
            end
            local wDamage = WeightSums(fighters, SelfRole)
            local importance = fight.final and 1.5 or (fight.boss and 1.3 or 1)
            local size = biggest > 0 and (totals.dmg / biggest) ^ 0.25 or 1
            local length = min(1, duration / 15)
            local weight = importance * size * length

            for _, key in ipairs(SortedKeys(fight.p)) do
                local stats, p = fight.p[key], players[key]
                if p then
                    local function Info(kind, value)
                        return { kind = kind, value = value, key = key, fkey = fkey, index = index, player = p, stats = stats }
                    end
                    local dmg, heal, taken = stats.dmg or 0, stats.heal or 0, stats.taken or 0
                    if dmg > 0 and p.role ~= "HEALER" then
                        local value = Index(dmg, totals.dmg, DAMAGE_WEIGHT[p.role], wDamage)
                        Consider(weight * value * POTG_KIND_WEIGHT.damage, Info("damage", value))
                    end
                    if heal > 0 and p.role == "HEALER" and p.time > 0 and p.heal > 0 then
                        local burst = min(3, (heal / duration) / (p.heal / p.time))
                        local value = burst * (totals.deaths == 0 and 1 or 0.75)
                        local info = Info("heal", value)
                        info.burst = burst
                        Consider(weight * value * POTG_KIND_WEIGHT.heal, info)
                    end
                    if taken > 0 and p.role == "TANK" and p.time > 0 and p.taken > 0 then
                        local burst = min(3, (taken / duration) / (p.taken / p.time))
                        local value = burst * ((stats.deaths or 0) == 0 and 1 or 0.4)
                        Consider(weight * value * POTG_KIND_WEIGHT.tank, Info("tank", value))
                    end
                    if (stats.ints or 0) >= 3 then
                        local value = min(2.2, 0.6 + 0.2 * stats.ints)
                        Consider(weight * value * POTG_KIND_WEIGHT.interrupts, Info("interrupts", value))
                    end
                end
            end
        end
    end
    if not best then
        return nil
    end

    local fight = run.fights[best.fkey]
    local totals = fightTotals[best.fkey]
    local stats = best.stats
    local duration = fight.dur
    best.fightName = fight.boss or fight.name or L.FIGHT_N:format(best.index)
    best.boss = fight.boss ~= nil
    best.duration = duration
    local length = ns.FormatTime(duration)
    if best.kind == "damage" then
        best.text = L.POTG_DAMAGE:format(Round(100 * stats.dmg / totals.dmg))
        best.detail = ("%s %s  ·  %s"):format(L.STAT_DPS, Num(stats.dmg / duration), length)
        best.spellID, best.spellAmount, best.spellTotal = stats.dsp, stats.dspA, stats.dmg
    elseif best.kind == "heal" then
        local format = totals.deaths == 0 and L.POTG_HEAL_SAFE or L.POTG_HEAL
        best.text = format:format(Num(stats.heal / duration), best.burst)
        best.detail = ("%s %s  ·  %s"):format(L.STAT_HEALING, Num(stats.heal), length)
        best.spellID, best.spellAmount, best.spellTotal = stats.hsp, stats.hspA, stats.heal
    elseif best.kind == "tank" then
        local format = (stats.deaths or 0) == 0 and L.POTG_TANK or L.POTG_TANK_TOTAL
        best.text = format:format(Num(stats.taken / duration))
        best.detail = ("%s %s  ·  %s"):format(L.STAT_TAKEN, Num(stats.taken), length)
        best.spellID, best.spellAmount, best.spellTotal = stats.dsp, stats.dspA, stats.dmg
    else
        best.text = L.POTG_INTERRUPTS:format(stats.ints)
        best.detail = length
    end
    best.stats = nil
    return best
end

local function Times(count)
    return count == 1 and L.VALUE_ONCE or L.VALUE_TIMES:format(count)
end

local function Best(list, field, filter)
    local best
    for _, p in ipairs(list) do
        if p[field] > 0 and (not filter or filter(p)) and (not best or p[field] > best[field]) then
            best = p
        end
    end
    return best
end

function Awards.Categories(list, totals, fun)
    local awards = {}
    local function Add(id, p, value)
        if p and #awards < MAX_AWARDS then
            awards[#awards + 1] = { id = id, title = L["AWARD_" .. id], icon = Awards.ICONS[id], player = p, value = value }
        end
    end
    local p = Best(list, "dmg")
    Add("DAMAGE", p, p and ("%s  ·  %s %s"):format(Num(p.dmg), L.STAT_DPS, Num(p.dps)))
    p = Best(list, "heal", function(q) return q.role == "HEALER" or q.heal >= 0.2 * totals.taken end)
    Add("HEALING", p, p and ("%s  ·  %s %s"):format(Num(p.heal), L.STAT_HPS, Num(p.hps)))
    p = Best(list, "taken", function(q) return q.role == "TANK" end)
    Add("TANK", p, p and L.VALUE_TAKEN:format(Num(p.taken)))
    p = Best(list, "ints")
    Add("INTERRUPTS", p, p and Times(p.ints))
    p = Best(list, "disp")
    Add("DISPELS", p, p and Times(p.disp))
    if fun then
        p = Best(list, "avoid")
        Add("FLOOR", p, p and L.VALUE_FLOOR:format(Num(p.avoid)))
        p = Best(list, "deaths")
        Add("DEATHS", p, p and Times(p.deaths))
    end
    -- Nobody died and took the least avoidable damage (only when it means something).
    if #list >= 2 and (totals.deaths > 0 or totals.avoid > 0) then
        local survivor
        for _, q in ipairs(list) do
            if q.deaths == 0 and q.role ~= "TANK" then
                if not survivor or q.avoid < survivor.avoid
                    or (q.avoid == survivor.avoid and q.dmg + q.heal > survivor.dmg + survivor.heal) then
                    survivor = q
                end
            end
        end
        Add("SURVIVOR", survivor, survivor and (survivor.avoid > 0 and L.VALUE_SURVIVOR or L.VALUE_SURVIVOR_CLEAN))
    end
    return awards
end

local function Header(run, request, keys, combatTime)
    local tag, title
    local kind = request.kind
    if kind == "demo" then
        tag, title = L.TAG_DEMO, L.TITLE_DEMO
    elseif kind == "boss" then
        local fight = run.fights[keys[1]]
        local boss = run.bosses[request.boss or #run.bosses]
        tag, title = L.TAG_BOSS, L.TITLE_BOSS:format((boss and boss.name) or (fight and (fight.boss or fight.name)) or "?")
    elseif kind == "partial" then
        tag, title = L.TAG_RUN, L.TITLE_PARTIAL
    elseif run.complete == "leave" then
        tag, title = L.TAG_RUN, L.TITLE_LEAVE
    elseif run.instanceType == "raid" then
        tag, title = L.TAG_RAID, L.TITLE_RAID
    else
        tag, title = L.TAG_CLEAR, L.TITLE_CLEAR
    end
    local length
    if kind == "boss" then
        length = combatTime
    else
        length = (run.ended or run.leftAt or time()) - (run.started or time())
    end
    return tag, title, length
end

local function SubtitleParts(run, request, length, totals)
    local parts = { run.instance or L.UNKNOWN }
    if run.difficulty and run.difficulty ~= "" then
        parts[1] = parts[1] .. " (" .. run.difficulty .. ")"
    end
    parts[#parts + 1] = L.SUB_TIME:format(ns.FormatTime(length))
    if request.kind ~= "boss" and #run.bosses > 0 then
        parts[#parts + 1] = L.SUB_BOSSES:format(#run.bosses)
    end
    if totals.deaths == 0 then
        parts[#parts + 1] = L.SUB_NO_DEATHS
    else
        parts[#parts + 1] = totals.deaths == 1 and L.SUB_ONE_DEATH or L.SUB_DEATHS:format(totals.deaths)
    end
    return parts
end

-- Group chat lines (plain text, each under 255 characters).
local function ShareLines(report)
    local lines = {}
    lines[1] = L.SHARE_HEADER:format(("%s %s - %s"):format(report.title, report.subtitleParts[1], report.subtitleParts[2]))
    local mvp = report.mvp
    local second = L.SHARE_MVP:format(ShortName(mvp.name), mvp.score)
    lines[2] = second
    if report.potg then
        local potg = report.potg
        lines[3] = L.SHARE_POTG:format(ShortName(potg.player.name), potg.fightName, potg.text)
    end
    local line = ""
    for _, award in ipairs(report.awards) do
        local part = L.SHARE_AWARD:format(award.title, ShortName(award.player.name))
        if #line + #part + 5 > 240 then
            lines[#lines + 1] = line
            line = ""
        end
        line = line == "" and part or (line .. "  ·  " .. part)
    end
    if line ~= "" then
        lines[#lines + 1] = line
    end
    return lines
end

-- request.kind: "clear" (whole run), "partial" (run so far), "boss" (one
-- boss fight, request.boss = index into run.bosses) or "demo".
-- Returns nil when the run has no player data.
function Awards.Build(run, request)
    request = request or { kind = "clear" }
    local keys = FightKeys(run, request)
    local players, list, combatTime = Aggregate(run, keys)
    if #list == 0 then
        return nil
    end
    local totals = Totals(list)
    Awards.GuessRoles(list, totals)
    Awards.Score(list, totals)
    local tag, title, length = Header(run, request, keys, combatTime)
    local report = {
        kind = request.kind,
        tag = tag,
        title = title,
        length = length,
        combatTime = combatTime,
        instance = run.instance,
        players = list,
        mvp = list[1],
        totals = totals,
        bosses = #run.bosses,
        potg = Awards.PlayOfTheGame(run, keys, players),
        awards = Awards.Categories(list, totals, not ns.db or ns.db.fun),
        time = run.ended or time(),
    }
    report.subtitleParts = SubtitleParts(run, request, length, totals)
    report.subtitle = table.concat(report.subtitleParts, "  ·  ")
    report.shareLines = ShareLines(report)
    return report
end

--------------------------------------------------------------------------
-- Made-up run for /mvp test and the options preview
--------------------------------------------------------------------------

local DEMO_SPELLS = {
    WARRIOR = 78, ROGUE = 1752, HUNTER = 3044, MAGE = 133, WARLOCK = 686, PRIEST = 585, DRUID = 5176,
    SHAMAN = 403, PALADIN = 20271,
}
local DEMO_HEAL = 2061 -- Flash Heal

-- Group members, so the preview shows their real characters.
local function PartyMembers()
    local members = {}
    for i = 1, 4 do
        local unit = "party" .. i
        if ns.Safe(UnitExists(unit)) then
            local _, class = UnitClass(unit)
            local ok, role = pcall(UnitGroupRolesAssigned or function() end, unit)
            members[#members + 1] = {
                guid = ns.Safe(UnitGUID(unit)),
                name = ns.Safe(UnitName(unit)),
                class = ns.Safe(class),
                role = ok and ns.Safe(role) or nil,
            }
        end
    end
    return members
end

function Awards.DemoRun()
    local myName = ns.Safe(UnitName("player")) or "Podium"
    local _, myClass = UnitClass("player")
    myClass = ns.Safe(myClass) or "MAGE"
    -- dps / hps / damage taken per second, interrupts and dispels per minute
    local cast = {
        { key = "demo-tank", name = L.DEMO_TANK, class = "WARRIOR", role = "TANK", dps = 310, dtps = 760, ints = 1.2 },
        { key = "demo-heal", name = L.DEMO_HEALER, class = "PRIEST", role = "HEALER", dps = 35, hps = 640, dtps = 70, disp = 1.4 },
        { key = "demo-rogue", name = L.DEMO_ROGUE, class = "ROGUE", role = "DAMAGER", dps = 505, dtps = 95, ints = 1.6 },
        { key = "demo-hunter", name = L.DEMO_HUNTER, class = "HUNTER", role = "DAMAGER", dps = 470, dtps = 60, avoid = 18 },
        { key = "demo-me", name = myName, class = myClass, role = "DAMAGER", dps = 540, dtps = 80, isLocal = true },
    }
    cast[5].key = ns.Safe(UnitGUID("player")) or cast[5].key
    -- Real group members take the made-up parts (matching roles first).
    local free = { cast[1], cast[2], cast[3], cast[4] }
    local function Take(member, sameRole)
        for i, part in ipairs(free) do
            if not sameRole or part.role == member.role then
                table.remove(free, i)
                part.key = member.guid or part.key
                part.name = member.name or part.name
                part.class = member.class or part.class
                return true
            end
        end
    end
    local members = PartyMembers()
    local waiting = {}
    for _, member in ipairs(members) do
        if not Take(member, true) then
            waiting[#waiting + 1] = member
        end
    end
    for _, member in ipairs(waiting) do
        Take(member, false)
    end
    local plan = {
        { L.DEMO_TRASH, 31 }, { L.DEMO_TRASH, 26 }, { L.DEMO_BOSS1, 64, boss = true },
        { L.DEMO_TRASH, 42 }, { L.DEMO_TRASH, 23 }, { L.DEMO_BOSS2, 88, boss = true, star = "demo-me" },
        { L.DEMO_TRASH, 37, deaths = { ["demo-hunter"] = 1 } }, { L.DEMO_BOSS3, 121, boss = true, final = true, clutch = true },
    }
    local seed = 7
    local function Random()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed / 2147483648
    end
    local now = time()
    local run = {
        instance = L.DEMO_INSTANCE, instanceType = "party", started = now - 1421, ended = now, complete = "final",
        fights = {}, order = {}, roster = {}, bosses = {}, killed = {},
    }
    for _, member in ipairs(cast) do
        run.roster[member.key] = { name = member.name, class = member.class, role = member.role, isLocal = member.isLocal }
    end
    local parts = { "demo-tank", "demo-heal", "demo-rogue", "demo-hunter", "demo-me" }
    for i, member in ipairs(cast) do
        member.part = parts[i] -- the made-up role it plays in the plan below
    end
    for index, step in ipairs(plan) do
        local name, duration = step[1], step[2]
        local fight = { sid = index, name = name, dur = duration, p = {}, done = true }
        local pressure = (step.boss and 1.25 or 1) * (step.clutch and 1.7 or 1)
        for _, member in ipairs(cast) do
            local swing = 0.85 + 0.3 * Random()
            local stats = {}
            local damage = member.dps * duration * swing * (step.star == member.part and 1.9 or 1)
            stats.dmg = Round(damage)
            stats.dsp = DEMO_SPELLS[member.class] or 6603
            stats.dspA = Round(damage * (0.3 + 0.2 * Random()))
            if member.hps then
                local healing = member.hps * duration * pressure * (0.9 + 0.2 * Random())
                stats.heal = Round(healing)
                stats.hsp, stats.hspA = DEMO_HEAL, Round(healing * 0.46)
            end
            stats.taken = Round(member.dtps * duration * pressure * (0.8 + 0.4 * Random()))
            if member.avoid then
                stats.avoid = Round(member.avoid * duration * (0.5 + Random()))
            end
            if member.ints and Random() < member.ints * duration / 60 then
                stats.ints = 1 + floor(Random() * 2)
            end
            if member.disp and Random() < member.disp * duration / 60 then
                stats.disp = 1 + floor(Random() * 2)
            end
            stats.deaths = step.deaths and step.deaths[member.part] or nil
            fight.p[member.key] = stats
        end
        local fkey = "1:" .. index
        run.fights[fkey] = fight
        run.order[#run.order + 1] = fkey
        if step.boss then
            fight.boss, fight.final = name, step.final
            run.bosses[#run.bosses + 1] = { name = name, fkey = fkey, final = step.final }
            run.killed[name] = true
        end
    end
    return run
end
