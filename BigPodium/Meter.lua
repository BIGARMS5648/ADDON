local ADDON, ns = ...

--------------------------------------------------------------------------
-- Reading the built-in damage meter (C_DamageMeter).
--
-- WoW Forever runs on the Midnight engine: addons can't read the combat log,
-- but the client keeps a damage meter of its own and lets addons read it.
-- Every fight is a "combat session" with an ID. During combat the numbers
-- are secret values (they can only be shown, not compared or added up), so
-- this addon only reads sessions once combat is over.
--------------------------------------------------------------------------

local Meter = {}
ns.Meter = Meter

local function IsSecret(value)
    return value ~= nil and issecretvalue ~= nil and issecretvalue(value) or false
end
ns.IsSecret = IsSecret

-- Drops values the client marks as secret.
local function Safe(value)
    if value == nil or IsSecret(value) then
        return nil
    end
    return value
end
ns.Safe = Safe

-- Enum.DamageMeterType values, in case the enum table is missing.
local TYPE_IDS = {
    DamageDone = 0,
    HealingDone = 2,
    Interrupts = 5,
    Dispels = 6,
    DamageTaken = 7,
    AvoidableDamageTaken = 8,
    Deaths = 9,
}

-- What we record for every player in every fight. HealingDone already
-- includes absorbs. Deaths lists one entry per death.
Meter.STATS = {
    { key = "dmg", type = "DamageDone" },
    { key = "heal", type = "HealingDone" },
    { key = "taken", type = "DamageTaken" },
    { key = "avoid", type = "AvoidableDamageTaken" },
    { key = "ints", type = "Interrupts" },
    { key = "disp", type = "Dispels" },
    { key = "deaths", type = "Deaths", count = true },
}

function Meter.TypeID(name)
    local enum = Enum and Enum.DamageMeterType
    return enum and enum[name] or TYPE_IDS[name]
end

function Meter.HasAPI()
    return C_DamageMeter ~= nil and C_DamageMeter.GetAvailableCombatSessions ~= nil
        and C_DamageMeter.GetCombatSessionFromID ~= nil
end

-- Returns available, reason
function Meter.IsAvailable()
    if not Meter.HasAPI() then
        return false, "C_DamageMeter"
    end
    if C_DamageMeter.IsDamageMeterAvailable then
        local ok, available, reason = pcall(C_DamageMeter.IsDamageMeterAvailable)
        if ok and Safe(available) == false then
            return false, Safe(reason) or "?"
        end
    end
    return true
end

-- The fights the meter currently keeps: { { id =, name =, duration = }, ... }
-- sorted from oldest to newest.
function Meter.Sessions()
    local list = {}
    if not Meter.HasAPI() then
        return list
    end
    local ok, sessions = pcall(C_DamageMeter.GetAvailableCombatSessions)
    if not ok or type(sessions) ~= "table" then
        return list
    end
    for _, session in ipairs(sessions) do
        local id = Safe(session.sessionID)
        if type(id) == "number" then
            local name = Safe(session.name)
            list[#list + 1] = {
                id = id,
                name = type(name) == "string" and name ~= "" and name or nil,
                duration = Safe(session.durationSeconds),
            }
        end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function SourceID(guid, name)
    if type(guid) == "string" and guid ~= "" then
        return guid
    elseif type(name) == "string" and name ~= "" then
        return "name:" .. name
    end
end

-- Reads every stat of one fight.
-- Returns { duration =, sources = { { guid =, name =, class =, isLocal =, dmg =, heal =, ... }, ... } }
-- or nil, "secret" while the client still hides the numbers, or nil, "error".
function Meter.ReadSession(sessionID)
    if not Meter.HasAPI() then
        return nil, "error"
    end
    local byID, sources = {}, {}
    local duration
    for _, stat in ipairs(Meter.STATS) do
        local ok, session = pcall(C_DamageMeter.GetCombatSessionFromID, sessionID, Meter.TypeID(stat.type))
        if not ok then
            return nil, "error"
        end
        if type(session) == "table" then
            if IsSecret(session.totalAmount) then
                return nil, "secret"
            end
            local length = Safe(session.durationSeconds)
            if type(length) == "number" and (duration == nil or length > duration) then
                duration = length
            end
            for _, source in ipairs(session.combatSources or {}) do
                local amount = source.totalAmount
                if IsSecret(amount) then
                    return nil, "secret"
                end
                local class = Safe(source.classFilename)
                local guid, name = Safe(source.sourceGUID), Safe(source.name)
                local id = SourceID(guid, name)
                -- Players only: creatures have no class.
                if id and type(class) == "string" and class ~= "" then
                    local entry = byID[id]
                    if not entry then
                        entry = {
                            guid = type(guid) == "string" and guid ~= "" and guid or nil,
                            name = type(name) == "string" and name ~= "" and name or nil,
                            class = class,
                        }
                        byID[id] = entry
                        sources[#sources + 1] = entry
                    end
                    if Safe(source.isLocalPlayer) then
                        entry.isLocal = true
                    end
                    if stat.count then
                        entry[stat.key] = (entry[stat.key] or 0) + 1
                    elseif type(amount) == "number" and amount > 0 then
                        entry[stat.key] = (entry[stat.key] or 0) + amount
                    end
                    if stat.key == "dmg" then
                        local perSecond = Safe(source.amountPerSecond)
                        entry.aps = type(perSecond) == "number" and perSecond or entry.aps
                    end
                end
            end
        end
    end
    return { duration = duration, sources = sources }
end

-- The ability that did the most of one player's damage or healing in a fight.
-- Returns spellID, amount, playerTotal
function Meter.TopSpell(sessionID, typeName, guid)
    if not (guid and Meter.HasAPI() and C_DamageMeter.GetCombatSessionSourceFromID) then
        return nil
    end
    local ok, source = pcall(C_DamageMeter.GetCombatSessionSourceFromID, sessionID, Meter.TypeID(typeName), guid)
    if not ok or type(source) ~= "table" then
        return nil
    end
    local best, bestAmount
    for _, spell in ipairs(source.combatSpells or {}) do
        local spellID, amount = Safe(spell.spellID), Safe(spell.totalAmount)
        if type(spellID) == "number" and spellID > 0 and type(amount) == "number"
            and (bestAmount == nil or amount > bestAmount) then
            best, bestAmount = spellID, amount
        end
    end
    if best then
        local total = Safe(source.totalAmount)
        return best, bestAmount, type(total) == "number" and total or nil
    end
end
