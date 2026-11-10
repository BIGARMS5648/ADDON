local ADDON, ns = ...
local L, Data, Sparkle = ns.L, ns.Data, ns.Sparkle

--------------------------------------------------------------------------
-- How it works
--
-- Quest objects: the client already knows how to highlight every quest
-- object in the world (passive outlines, or "loot sparkles" when outline
-- mode is off). WoW Forever ships with that turned off and hides the
-- option, so we flip the CVars.
--
-- Herbs / ore / other objects: addons can't draw on 3D objects, but the
-- client gives the object you are facing (the "soft interact" target) a
-- nameplate when SoftTargetNameplateInteract is on. We attach an animated
-- sparkle to that nameplate. The kind of object is read from the interact
-- cursor the game would show for it (herb / mining / quest icon), with
-- object IDs, learned names and quest-objective names as fallbacks.
--------------------------------------------------------------------------

local DEFAULTS = {
    enabled = true,
    questStyle = "sparkle", -- "sparkle" | "outline" | "none"
    outlineMode = 1,
    softEnabled = true,
    show = { QUEST = true, HERB = true, ORE = true, LOOT = true, WATCH = true, OTHER = false },
    range = 20,
    arc = 2,
    size = 72,
    offsetY = -16,
    showLabel = false,
    hud = true,
    hudY = 160,
    sound = false,
    blizzIcon = true,
    questNameMatch = true,
    debug = false,
    watch = {}, -- [lowercase name] = name as typed
    learned = {}, -- [object name] = "HERB" | "ORE"
    savedCVars = {}, -- original values of CVars we changed
}
ns.DEFAULTS = DEFAULTS

-- Every CVar the addon may touch. Missing ones are skipped.
local MANAGED_CVARS = {
    "SoftTargetInteract",
    "SoftTargetNameplateInteract",
    "SoftTargetInteractRange",
    "SoftTargetInteractArc",
    "SoftTargetIconGameObject",
    "Outline",
    "outlineModeShowLootEffectWhenDisabled",
}
ns.MANAGED_CVARS = MANAGED_CVARS

local db
local plates = {} -- [nameplate unit] = true, for every nameplate currently shown
local active = {} -- [nameplate unit] = sparkle frame
local announced = {} -- [guid or name] = GetTime() of the last sound
local announcedCount = 0
local hudKey -- object the screen alert is currently showing
local questTexts = {} -- unfinished objective texts, lowercase
local gatherSpellNames = {} -- [localized spell name] = category
ns.unknownCursors = {}
local needApply = false
local probe

local function Print(...)
    print("|cffffd100Twinkle|r:", ...)
end
ns.Print = Print

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) or false
end

-- Drops values the client marks as secret (they can't be compared or stored).
local function Safe(value)
    if value == nil or IsSecret(value) then
        return nil
    end
    return value
end

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

local function GetSpellName(spellID)
    if C_Spell and C_Spell.GetSpellName then
        return C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        return (GetSpellInfo(spellID))
    end
end

-- "GameObject-0-1-0-12-1731-0000ABCDEF" -> "GameObject", 1731
local function ParseGUID(guid)
    if type(guid) ~= "string" then
        return nil
    end
    local kind = guid:match("^(%a+)%-")
    local id = guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    return kind, tonumber(id)
end
ns.ParseGUID = ParseGUID

local function IsGameObject(unit)
    if UnitIsGameObject then
        local ok, result = pcall(UnitIsGameObject, unit)
        if ok and Safe(result) then
            return true
        end
    end
    local kind = ParseGUID(Safe(UnitGUID(unit)))
    return kind == "GameObject"
end
ns.IsGameObject = IsGameObject

--------------------------------------------------------------------------
-- CVars
--------------------------------------------------------------------------

local function GetCVarValue(name)
    local ok, value = pcall(C_CVar.GetCVar, name)
    if ok then
        return value
    end
end

local function SameValue(a, b)
    if a == b then
        return true
    end
    local na, nb = tonumber(a), tonumber(b)
    return na ~= nil and na == nb
end

local function DesiredCVars()
    local want = {}
    if not db.enabled then
        return want
    end
    if db.softEnabled then
        want.SoftTargetInteract = "3" -- always (not only with a gamepad)
        want.SoftTargetNameplateInteract = "1"
        want.SoftTargetInteractRange = tostring(db.range)
        want.SoftTargetInteractArc = tostring(db.arc)
        if db.blizzIcon then
            want.SoftTargetIconGameObject = "1"
        end
    end
    if db.questStyle == "sparkle" then
        want.Outline = "0"
        want.outlineModeShowLootEffectWhenDisabled = "1"
    elseif db.questStyle == "outline" then
        want.Outline = tostring(db.outlineMode)
        want.outlineModeShowLootEffectWhenDisabled = "0"
    end
    return want
end

-- Records original values (safe at any time) and returns the CVars that
-- actually need SetCVar: { { name =, value =, restore = }, ... }
local function PendingCVarChanges()
    local want = DesiredCVars()
    local changes = {}
    for _, name in ipairs(MANAGED_CVARS) do
        local current = GetCVarValue(name)
        if current ~= nil then
            local target = want[name]
            if target ~= nil then
                if db.savedCVars[name] == nil then
                    db.savedCVars[name] = current
                end
                if not SameValue(current, target) then
                    changes[#changes + 1] = { name = name, value = target }
                end
            elseif db.savedCVars[name] ~= nil then
                if SameValue(current, db.savedCVars[name]) then
                    db.savedCVars[name] = nil
                else
                    changes[#changes + 1] = { name = name, value = db.savedCVars[name], restore = true }
                end
            end
        end
    end
    return changes
end

function ns:ApplyCVars()
    if not db then
        return
    end
    if C_CVar.AreCVarsLoaded and not C_CVar.AreCVarsLoaded() then
        needApply = true
        return
    end
    local changes = PendingCVarChanges()
    if #changes == 0 then
        needApply = false
        return
    end
    -- Some of these are "secure" CVars that addons can't change in combat.
    if InCombatLockdown() then
        if not needApply then
            Print(L.COMBAT_DEFERRED)
        end
        needApply = true
        return
    end
    needApply = false
    for _, change in ipairs(changes) do
        C_CVar.SetCVar(change.name, change.value)
        if change.restore then
            db.savedCVars[change.name] = nil
        end
    end
end

--------------------------------------------------------------------------
-- What kind of object is this?
--------------------------------------------------------------------------

local function MatchKeywords(text)
    if type(text) ~= "string" then
        return nil
    end
    local lower = text:lower()
    for _, entry in ipairs(Data.CURSOR_KEYWORDS) do
        if lower:find(entry[1], 1, true) then
            return entry[2]
        end
    end
end

-- Asks the client which interact cursor it would show for this unit.
local function CursorCategory(unit)
    if not SetUnitCursorTexture or not probe then
        return nil
    end
    probe:SetTexture(nil)
    local ok, hasCursor = pcall(SetUnitCursorTexture, probe, unit, nil, true)
    if not ok or not Safe(hasCursor) then
        return nil
    end
    local fileID = Safe(probe:GetTextureFileID())
    if fileID and Data.CURSOR_FILEIDS[fileID] then
        return Data.CURSOR_FILEIDS[fileID], fileID
    end
    local path = Safe(probe:GetTextureFilePath())
    local pathID = tonumber(path)
    if pathID and Data.CURSOR_FILEIDS[pathID] then
        return Data.CURSOR_FILEIDS[pathID], pathID
    end
    local atlas = probe.GetAtlas and Safe(probe:GetAtlas())
    local category = MatchKeywords(path) or MatchKeywords(atlas)
    local key = fileID or path or atlas or "?"
    if category then
        return category, key
    end
    ns.unknownCursors[tostring(key)] = Safe(UnitName(unit)) or "?"
    return "OTHER", key
end

local function NormalizeObjective(text)
    text = text:gsub("%s*:?%s*%d+%s*/%s*%d+%s*$", "") -- "Bundle of Wood: 3/8"
    text = text:gsub("^%s*%d+%s*/%s*%d+%s*", "") -- "3/8 Bundle of Wood"
    return (text:match("^%s*(.-)%s*$") or text):lower()
end

function ns:RebuildQuestCache()
    wipe(questTexts)
    if not (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo) then
        return
    end
    for i = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID then
            local objectives = C_QuestLog.GetQuestObjectives(info.questID)
            for _, objective in ipairs(objectives or {}) do
                local text = Safe(objective.text)
                if type(text) == "string" and not objective.finished then
                    local normalized = NormalizeObjective(text)
                    if normalized ~= "" then
                        questTexts[#questTexts + 1] = normalized
                    end
                end
            end
        end
    end
end

local function MatchesQuestObjective(name)
    local lower = name:lower()
    if #lower < 4 then
        return false
    end
    for _, text in ipairs(questTexts) do
        if text:find(lower, 1, true) or (#text >= 6 and lower:find(text, 1, true)) then
            return true
        end
    end
    return false
end

-- Returns category, info (info is for /tw debug).
function ns:Classify(unit)
    local name = Safe(UnitName(unit))
    local guid = Safe(UnitGUID(unit))
    local info = { name = name, guid = guid }

    if name and db.watch[name:lower()] then
        info.source = "watch"
        return "WATCH", info
    end

    local cursorCategory, cursorKey = CursorCategory(unit)
    info.cursor = cursorKey
    if cursorCategory and cursorCategory ~= "OTHER" then
        info.source = "cursor"
        return cursorCategory, info
    end

    local _, id = ParseGUID(guid)
    info.id = id
    if id and Data.NODE_IDS[id] then
        info.source = "id"
        return Data.NODE_IDS[id], info
    end

    if name and db.learned[name] then
        info.source = "learned"
        return db.learned[name], info
    end

    if name and db.questNameMatch and MatchesQuestObjective(name) then
        info.source = "quest objective"
        return "QUEST", info
    end

    info.source = cursorCategory and "cursor" or "none"
    return "OTHER", info
end

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

local function CategoryLabel(category, name)
    local label = L["CAT_" .. category]
    if name then
        return label .. ": " .. name
    end
    return label
end

function ns:Announce(category, info)
    local key = info.guid or info.name
    local now = GetTime()
    if db.debug then
        Print(("%s |cffaaaaaa(%s, %s, cursor %s, id %s)|r"):format(
            CategoryLabel(category, info.name), info.source or "?", tostring(info.guid),
            tostring(info.cursor), tostring(info.id)))
    end
    if not key or (announced[key] and now - announced[key] < 30) then
        return
    end
    announcedCount = announcedCount + 1
    if announcedCount > 500 then
        wipe(announced)
        announcedCount = 0
    end
    announced[key] = now
    if category == "WATCH" then
        PlaySound(SOUNDKIT.RAID_WARNING)
    elseif db.sound then
        PlaySound(SOUNDKIT.MAP_PING)
    end
end

local function SoftEnabled()
    return db and db.enabled and db.softEnabled
end

local function GetPlate(unit)
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if ok then
        return plate
    end
end

local function ReleaseUnit(unit)
    if active[unit] then
        Sparkle.Release(active[unit])
        active[unit] = nil
    end
end

-- Adds, updates or removes the sparkle on one nameplate.
function ns:UpdatePlate(unit)
    if not SoftEnabled() or not IsGameObject(unit) then
        ReleaseUnit(unit)
        return
    end
    local category, info = self:Classify(unit)
    local plate = db.show[category] and GetPlate(unit)
    if not plate then
        ReleaseUnit(unit)
        return
    end
    local fx = active[unit]
    if not fx then
        fx = Sparkle.Acquire()
        active[unit] = fx
        self:Announce(category, info)
    end
    fx:Play(plate, category, db.showLabel and L["CAT_" .. category] or nil, db.size, 0, db.offsetY)
end

local function IsSameUnit(a, b)
    local ok, same = pcall(UnitIsUnit, a, b)
    return ok and Safe(same) and true or false
end

-- Screen alert for when the object in front of us has no nameplate.
function ns:UpdateHud()
    if SoftEnabled() and db.hud and IsGameObject("softinteract") then
        for unit in pairs(active) do
            if IsSameUnit(unit, "softinteract") then
                Sparkle.HideHud()
                return
            end
        end
        local category, info = self:Classify("softinteract")
        if db.show[category] then
            local key = info.guid or info.name
            if not Sparkle.IsHudShown() or key ~= hudKey then
                hudKey = key
                self:Announce(category, info)
            end
            Sparkle.ShowHud(category, CategoryLabel(category, info.name), db.size, db.hudY)
            return
        end
    end
    Sparkle.HideHud()
end

function ns:RefreshAll()
    for unit in pairs(active) do
        if not plates[unit] then
            ReleaseUnit(unit)
        end
    end
    for unit in pairs(plates) do
        self:UpdatePlate(unit)
    end
    self:UpdateHud()
end

-- Collapses bursts of events into one refresh.
local refreshQueued = false
function ns:QueueRefresh(delay)
    if refreshQueued then
        return
    end
    refreshQueued = true
    C_Timer.After(delay or 0.1, function()
        refreshQueued = false
        ns:RefreshAll()
    end)
end

function ns:OnSettingsChanged()
    self:ApplyCVars()
    self:RefreshAll()
end

function ns:SetEnabled(enabled)
    db.enabled = enabled and true or false
    self:OnSettingsChanged()
end

function ns:ShowTest()
    local labels = {}
    for _, category in ipairs({ "QUEST", "HERB", "ORE" }) do
        labels[category] = L["CAT_" .. category]
    end
    Sparkle.ShowTest(db.size, labels)
end

--------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, ...)
    ns[event](ns, ...)
end)

local function Register(event, unit)
    -- pcall: don't break the whole addon if a client lacks an event
    if unit then
        pcall(events.RegisterUnitEvent, events, event, unit)
    else
        pcall(events.RegisterEvent, events, event)
    end
end

function ns:ADDON_LOADED(name)
    if name ~= ADDON then
        return
    end
    events:UnregisterEvent("ADDON_LOADED")
    TwinkleDB = TwinkleDB or {}
    db = CopyDefaults(DEFAULTS, TwinkleDB)
    ns.db = db

    Register("PLAYER_LOGIN")
    Register("PLAYER_ENTERING_WORLD")
    Register("VARIABLES_LOADED")
    Register("PLAYER_REGEN_ENABLED")
    Register("NAME_PLATE_UNIT_ADDED")
    Register("NAME_PLATE_UNIT_REMOVED")
    Register("PLAYER_SOFT_INTERACT_CHANGED")
    Register("QUEST_LOG_UPDATE")
    Register("UNIT_SPELLCAST_SENT", "player")
end

function ns:PLAYER_LOGIN()
    local probeFrame = CreateFrame("Frame", nil, UIParent)
    probeFrame:Hide()
    probe = probeFrame:CreateTexture()

    for spellID, category in pairs(Data.GATHER_SPELLS) do
        local name = GetSpellName(spellID)
        if name then
            gatherSpellNames[name] = category
        end
    end

    self:RebuildQuestCache()
    self:ApplyCVars()
    if self.CreateOptions then
        self:CreateOptions()
    end
    if not db.welcomed then
        db.welcomed = true
        Print(L.LOADED)
    end
end

function ns:VARIABLES_LOADED()
    self:ApplyCVars()
end

function ns:PLAYER_ENTERING_WORLD()
    self:ApplyCVars()
    self:QueueRefresh(0.5)
end

function ns:PLAYER_REGEN_ENABLED()
    if needApply then
        self:ApplyCVars()
    end
end

function ns:NAME_PLATE_UNIT_ADDED(unit)
    plates[unit] = true
    self:UpdatePlate(unit)
    if active[unit] then
        Sparkle.HideHud()
    end
end

function ns:NAME_PLATE_UNIT_REMOVED(unit)
    plates[unit] = nil
    ReleaseUnit(unit)
end

function ns:PLAYER_SOFT_INTERACT_CHANGED()
    -- The new target's nameplate usually arrives right after this event,
    -- so wait a moment before deciding a screen alert is needed.
    self:QueueRefresh(0.15)
end

local questQueued = false
function ns:QUEST_LOG_UPDATE()
    if questQueued then
        return
    end
    questQueued = true
    C_Timer.After(1, function()
        questQueued = false
        ns:RebuildQuestCache()
        ns:RefreshAll()
    end)
end

-- Learn node names from our own gathering casts (works in every language).
function ns:UNIT_SPELLCAST_SENT(unit, target, _, spellID)
    if unit ~= "player" then
        return
    end
    target, spellID = Safe(target), Safe(spellID)
    if type(target) ~= "string" or target == "" or not spellID then
        return
    end
    local category = Data.GATHER_SPELLS[spellID]
    if not category then
        local spellName = GetSpellName(spellID)
        category = spellName and gatherSpellNames[spellName]
    end
    if category and db.learned[target] ~= category then
        db.learned[target] = category
        self:QueueRefresh()
    end
end

events:RegisterEvent("ADDON_LOADED")

--------------------------------------------------------------------------
-- Debug helpers (used by /tw debug)
--------------------------------------------------------------------------

function ns:DebugReport()
    local function cvars()
        local parts = {}
        for _, name in ipairs(MANAGED_CVARS) do
            parts[#parts + 1] = name .. "=" .. tostring(GetCVarValue(name))
        end
        return table.concat(parts, ", ")
    end

    if IsGameObject("softinteract") then
        local category, info = self:Classify("softinteract")
        local hasPlate = GetPlate("softinteract") ~= nil
        Print(("softinteract: %s -> |cffffd100%s|r (%s)"):format(tostring(info.name), category, info.source or "?"))
        Print(("  guid %s, object id %s, cursor %s, nameplate %s"):format(
            tostring(info.guid), tostring(info.id), tostring(info.cursor), tostring(hasPlate)))
    else
        Print(L.NO_SOFT_TARGET)
    end
    local count = 0
    for unit, fx in pairs(active) do
        count = count + 1
        Print(("  %s: %s"):format(unit, tostring(fx.category)))
    end
    Print(("  sparkles on nameplates: %d, screen alert: %s"):format(count, tostring(Sparkle.IsHudShown())))
    Print("  " .. cvars())
    local unknown = {}
    for key, name in pairs(ns.unknownCursors) do
        unknown[#unknown + 1] = key .. " (" .. name .. ")"
    end
    if #unknown > 0 then
        Print("  unknown cursors: " .. table.concat(unknown, ", "))
    end
end
