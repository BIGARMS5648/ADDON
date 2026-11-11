-- Minimal stand-in for the WoW client API, enough to load and drive Twinkle.
-- Loaded by tests/run_tests.py into a Lua 5.1 runtime.

local mock = {}
_G.mock = mock

mock.printed = {}
mock.sounds = {}
mock.timers = {}
mock.time = 1000
mock.inCombat = false
mock.units = {} -- [unit] = { name=, guid=, gameObject=, cursor = fileID|false, plate = frame|nil }
mock.frames = {}
mock.events = {}

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
mock.SECRET = SECRET

function issecretvalue(v)
    return v == SECRET
end

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    mock.printed[#mock.printed + 1] = table.concat(parts, " ")
end

function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

function GetLocale() return mock.locale or "koKR" end
function GetTime() return mock.time end
function InCombatLockdown() return mock.inCombat end
function PlaySound(id) mock.sounds[#mock.sounds + 1] = id end
SOUNDKIT = { MAP_PING = 3175, RAID_WARNING = 8959 }

C_Timer = {
    After = function(delay, fn)
        mock.timers[#mock.timers + 1] = fn
    end,
}

function mock.flushTimers()
    local guard = 0
    while #mock.timers > 0 do
        guard = guard + 1
        assert(guard < 100, "timer loop")
        local list = mock.timers
        mock.timers = {}
        for _, fn in ipairs(list) do
            fn()
        end
    end
end

-- CVars --------------------------------------------------------------------
mock.cvars = {
    SoftTargetInteract = "1",
    SoftTargetNameplateInteract = "0",
    SoftTargetInteractRange = "10.000000",
    SoftTargetInteractArc = "0",
    SoftTargetIconGameObject = "0",
    SoftTargetIconInteract = "1",
    interactKeyWarningTutorial = "0",
    softTargetInteractionTutorialTotalInteractions = "0",
    cameraFov = "90.000000",
    Outline = "0",
    outlineModeShowLootEffectWhenDisabled = "0",
}
mock.cvarWrites = 0
mock.secureCVars = { SoftTargetInteract = true, SoftTargetInteractRange = true }

C_CVar = {
    GetCVar = function(name) return mock.cvars[name] end,
    SetCVar = function(name, value)
        if mock.cvars[name] == nil then return false end
        if mock.secureCVars[name] and mock.inCombat then return nil end
        mock.cvars[name] = tostring(value)
        mock.cvarWrites = mock.cvarWrites + 1
        return true
    end,
    AreCVarsLoaded = function() return true end,
}

-- Regions / frames ---------------------------------------------------------
local Region = {}
Region.__index = Region

local function newRegion(kind, parent)
    local r = setmetatable({
        kind = kind, parent = parent, shown = true, points = {}, alpha = 1,
        width = 0, height = 0, frameLevel = 1, scripts = {},
    }, Region)
    return r
end

function Region:SetParent(p) self.parent = p end
function Region:GetParent() return self.parent end
function Region:Show() self.shown = true end
function Region:Hide() self.shown = false end
function Region:IsShown() return self.shown end
function Region:ClearAllPoints() self.points = {} end
function Region:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Region:SetSize(w, h)
    assert(type(w) == "number" and w > 0 and type(h) == "number" and h > 0, "bad size")
    self.width, self.height = w, h
end
function Region:SetAlpha(a)
    assert(type(a) == "number" and a >= -1e-9 and a <= 1 + 1e-9, "bad alpha " .. tostring(a))
    self.alpha = a
end
function Region:SetFrameLevel(l) self.frameLevel = l end
function Region:GetFrameLevel() return self.frameLevel end
function Region:SetIgnoreParentAlpha(v) self.ignoreParentAlpha = v end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:GetScript(name) return self.scripts[name] end
function Region:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end
function Region:GetCenter() return self.centerX, self.centerY end
function Region:GetEffectiveScale() return 1 end
function Region:SetFrameStrata(s) self.strata = s end
function Region:RegisterForClicks(...) self.clicks = { ... } end
function Region:RegisterForDrag(...) self.drag = { ... } end
function Region:SetHighlightTexture(t) self.highlight = t end
function Region:LockHighlight() self.highlightLocked = true end
function Region:UnlockHighlight() self.highlightLocked = false end
function Region:SetDesaturated(v) self.desaturated = v end

-- textures
function Region:SetTexture(t)
    self.texture = t
    self.fileID = nil
end
function Region:SetBlendMode(m) self.blend = m end
function Region:SetRotation(r) self.rotation = r end
function Region:SetVertexColor(r, g, b) self.color = { r, g, b } end
function Region:GetTextureFileID() return self.fileID end
function Region:GetTextureFilePath()
    if self.fileID then return tostring(self.fileID) end
    return self.texture
end
function Region:GetAtlas() return nil end

-- font strings
function Region:SetText(t) self.text = t end
function Region:SetTextColor(r, g, b) self.textColor = { r, g, b } end

-- frames
function Region:CreateTexture()
    return newRegion("Texture", self)
end
function Region:CreateFontString()
    return newRegion("FontString", self)
end
function Region:RegisterEvent(e)
    mock.events[e] = mock.events[e] or {}
    mock.events[e][self] = true
end
function Region:RegisterUnitEvent(e)
    self:RegisterEvent(e)
end
function Region:UnregisterEvent(e)
    if mock.events[e] then mock.events[e][self] = nil end
end

function CreateFrame(kind, name, parent)
    local f = newRegion(kind or "Frame", parent)
    mock.frames[#mock.frames + 1] = f
    return f
end

UIParent = CreateFrame("Frame")
UIParent.width, UIParent.height = 1366, 768

Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap.width, Minimap.height = 140, 140
Minimap.centerX, Minimap.centerY = 1250, 650

mock.cursor = { 0, 0 }
function GetCursorPosition() return mock.cursor[1], mock.cursor[2] end

GameTooltip = CreateFrame("Frame")
GameTooltip.lines = {}
function GameTooltip:SetOwner(owner) self.owner = owner; self.lines = {}; self.shown = false end
function GameTooltip:SetText(t) self.lines = { t } end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function GameTooltip:IsOwned(f) return self.owner == f and self.shown end
function GameTooltip:Show() self.shown = true end
function GameTooltip:Hide() self.shown = false; self.owner = nil end

function mock.fire(event, ...)
    for frame in pairs(mock.events[event] or {}) do
        local handler = frame.scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

-- Units ----------------------------------------------------------------------
local function unit(u) return mock.units[u] end

function UnitName(u)
    local d = unit(u)
    return d and d.name or nil
end
function UnitGUID(u)
    local d = unit(u)
    return d and d.guid or nil
end
function UnitIsGameObject(u)
    local d = unit(u)
    return d and d.gameObject or false
end
function UnitIsUnit(a, b)
    local da, db = unit(a), unit(b)
    return da ~= nil and db ~= nil and da.guid == db.guid
end
function SetUnitCursorTexture(tex, u)
    local d = unit(u)
    if d and d.cursor then
        tex.fileID = d.cursor
        return true
    end
    return false
end

C_NamePlate = {
    GetNamePlateForUnit = function(u)
        local d = unit(u)
        return d and d.plate or nil
    end,
}

function mock.addPlate(token, data)
    data.plate = CreateFrame("Frame", nil, UIParent)
    mock.units[token] = data
    mock.fire("NAME_PLATE_UNIT_ADDED", token)
    return data.plate
end

function mock.removePlate(token)
    mock.fire("NAME_PLATE_UNIT_REMOVED", token)
    mock.units[token] = nil
end

function mock.setSoftInteract(data)
    mock.units.softinteract = data
    mock.fire("PLAYER_SOFT_INTERACT_CHANGED", nil, data and data.guid or nil)
end

-- World positions ------------------------------------------------------------
-- world x points north, y points west; facing is radians counterclockwise from north
mock.player = { x = 0, y = 0, facing = 0 }
function UnitPosition(u)
    if u ~= "player" then return nil end
    return mock.player.x, mock.player.y, 0, 0
end
function GetPlayerFacing() return mock.player.facing end

-- Spells / quests ------------------------------------------------------------
mock.spellNames = { [2366] = "약초 채집", [2575] = "채광" }
C_Spell = { GetSpellName = function(id) return mock.spellNames[id] end }

mock.quests = {}
C_QuestLog = {
    GetNumQuestLogEntries = function() return #mock.quests end,
    GetInfo = function(i) return mock.quests[i] and mock.quests[i].info end,
    GetQuestObjectives = function(questID)
        for _, q in ipairs(mock.quests) do
            if q.info.questID == questID then return q.objectives end
        end
    end,
}

-- Settings -------------------------------------------------------------------
mock.settings = {}
mock.initializers = {}
Settings = {
    VarType = { Boolean = "boolean", String = "string", Number = "number" },
    RegisterVerticalLayoutCategory = function(name)
        local category = { name = name, GetID = function() return 42 end }
        local layout = { AddInitializer = function(_, init) mock.initializers[#mock.initializers + 1] = init end }
        return category, layout
    end,
    RegisterProxySetting = function(category, variable, varType, name, default, get, set)
        local s = { variable = variable, varType = varType, name = name, default = default, get = get, set = set }
        assert(mock.settings[variable] == nil, "duplicate setting " .. variable)
        mock.settings[variable] = s
        return s
    end,
    CreateCheckbox = function(category, setting) setting.control = "checkbox" end,
    CreateSlider = function(category, setting, options) setting.control = "slider"; setting.options = options end,
    CreateDropdown = function(category, setting, getOptions)
        setting.control = "dropdown"
        setting.choices = getOptions()
    end,
    CreateSliderOptions = function(minValue, maxValue, step)
        return { minValue = minValue, maxValue = maxValue, step = step,
                 SetLabelFormatter = function(self, label, fn) self.formatter = fn end }
    end,
    CreateControlTextContainer = function()
        local data = {}
        return { Add = function(_, value, label) data[#data + 1] = { value = value, label = label } end,
                 GetData = function() return data end }
    end,
    RegisterAddOnCategory = function(category) mock.registeredCategory = category end,
    OpenToCategory = function(id) mock.openedCategory = id end,
    NotifyUpdate = function() end,
}
MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
function CreateSettingsListSectionHeaderInitializer(text) return { header = text } end
function CreateSettingsButtonInitializer(name, text, onClick, tooltip, addSearchTags)
    assert(addSearchTags ~= nil)
    return { button = name, onClick = onClick }
end

SlashCmdList = {}

--------------------------------------------------------------------------------
-- More widget API (Podium's ceremony window). Layout data is kept so
-- tools/render_podium_preview.py can draw the window.
--------------------------------------------------------------------------------

function Region:CreateTexture(name, layer, template, sublevel)
    local t = newRegion("Texture", self)
    t.layer, t.sublevel = layer or "ARTWORK", sublevel or 0
    self.regions = self.regions or {}
    self.regions[#self.regions + 1] = t
    return t
end
function Region:CreateFontString(name, layer)
    local fs = newRegion("FontString", self)
    fs.layer, fs.sublevel = layer or "ARTWORK", 0
    self.regions = self.regions or {}
    self.regions[#self.regions + 1] = fs
    return fs
end
local baseSetTexture = Region.SetTexture
function Region:SetTexture(t)
    baseSetTexture(self, t)
    self.atlas, self.colorTexture = nil, nil
end
function Region:SetWidth(w)
    assert(type(w) == "number" and w >= 0, "bad width")
    self.width = w
end
function Region:SetHeight(h)
    assert(type(h) == "number" and h >= 0, "bad height")
    self.height = h
end
function Region:SetAllPoints(rel)
    rel = rel or self.parent
    self.points = { { "TOPLEFT", rel, "TOPLEFT" }, { "BOTTOMRIGHT", rel, "BOTTOMRIGHT" } }
end
function Region:SetScale(s)
    assert(type(s) == "number" and s > 0, "bad scale")
    self.scale = s
end
function Region:GetScale() return self.scale or 1 end
function Region:SetShown(v) self.shown = v and true or false end
function Region:SetToplevel() end
function Region:SetClampedToScreen() end
function Region:SetMovable() end
function Region:EnableMouse(v) self.mouseEnabled = v end
function Region:StartMoving() end
function Region:StopMovingOrSizing() end
function Region:IsMouseOver() return self.mouseOver or false end
function Region:SetFont(path, size, flags)
    assert(type(path) == "string", "font path")
    assert(type(size) == "number" and size > 0, "font size")
    assert(type(flags) == "string", "font flags must be a string")
    self.font = { path = path, size = size, flags = flags }
end
function Region:SetJustifyH(j) self.justifyH = j end
function Region:SetJustifyV(j) self.justifyV = j end
function Region:SetShadowOffset() end
function Region:SetShadowColor() end
function Region:SetWordWrap(v) self.wordWrap = v end
function Region:SetMaxLines(n) self.maxLines = n end
function Region:GetText() return self.text end
function Region:SetColorTexture(r, g, b, a)
    self.colorTexture = { r, g, b, a or 1 }
    self.texture, self.atlas = nil, nil
end
function Region:SetGradient(orientation, minColor, maxColor)
    assert(type(minColor) == "table" and type(maxColor) == "table", "SetGradient takes color objects")
    self.gradient = { orientation, minColor, maxColor }
end
function Region:SetAtlas(name)
    assert(type(name) == "string")
    self.atlas = name
    self.texture, self.colorTexture = nil, nil
end
function Region:SetTexCoord(...) self.texCoord = { ... } end

local baseCreateFrame = CreateFrame
function CreateFrame(kind, name, parent, template)
    local f = baseCreateFrame(kind, name, parent)
    f.name, f.template = name, template
    if parent then
        parent.children = parent.children or {}
        parent.children[#parent.children + 1] = f
        f.frameLevel = (parent.frameLevel or 1) + 1
    end
    return f
end

function GameTooltip:AddDoubleLine(left, right) self.lines[#self.lines + 1] = tostring(left) .. " = " .. tostring(right) end

--------------------------------------------------------------------------------
-- Game state for Podium
--------------------------------------------------------------------------------

mock.now = 1762800000
function time() return mock.now end
date = os.date
STANDARD_TEXT_FONT = "Fonts\\2002.TTF"
UISpecialFrames = {}
LE_PARTY_CATEGORY_INSTANCE = 2
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end

RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PRIEST = { r = 1, g = 1, b = 1 },
    ROGUE = { r = 1, g = 0.96, b = 0.41 }, HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
    MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
    DRUID = { r = 1, g = 0.49, b = 0.04 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    SHAMAN = { r = 0, g = 0.44, b = 0.87 },
}
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
C_Texture = {
    GetAtlasInfo = function(name)
        if name:find("^classicon%-") or name:find("^UI%-LFG%-RoleIcon") then
            return { width = 64, height = 64 }
        end
    end,
}

mock.spellNames[133] = "화염구"
mock.spellNames[1752] = "사악한 일격"
mock.spellNames[2061] = "순간 치유"
C_Spell.GetSpellTexture = function(id) return 130000 + id end

function UnitAffectingCombat(u) return u == "player" and mock.inCombat or false end
mock.dead = false
function UnitIsDeadOrGhost(u) return u == "player" and mock.dead or false end
function UnitExists(u) return mock.units[u] ~= nil end
function UnitClass(u)
    local d = mock.units[u]
    if d and d.class then return d.class, d.class end
end
function UnitGroupRolesAssigned(u)
    local d = mock.units[u]
    return d and d.role or "NONE"
end
mock.raid = false
mock.instanceGroup = false
function IsInRaid() return mock.raid end
function IsInGroup(category)
    if category == LE_PARTY_CATEGORY_INSTANCE then return mock.instanceGroup end
    return mock.units.party1 ~= nil or mock.raid
end

mock.chat = {}
C_ChatInfo = {
    SendChatMessage = function(msg, channel)
        assert(type(msg) == "string" and #msg <= 255, "chat message too long")
        assert(not msg:find("|", 1, true), "escape codes in chat message")
        mock.chat[#mock.chat + 1] = { msg = msg, channel = channel }
    end,
}

-- Instances ------------------------------------------------------------------
mock.instance = nil -- { name =, type = "party" | "raid", mapID =, difficulty = }
function IsInInstance()
    if mock.instance then return true, mock.instance.type end
    return false, "none"
end
function GetInstanceInfo()
    local i = mock.instance
    if not i then return "Elwynn Forest", "none", 0, "", 0, 0, false, 0 end
    return i.name, i.type, i.difficultyID or 1, i.difficulty or "", 5, 0, false, i.mapID
end

mock.journal = {} -- [instance map ID] = { journalID =, bosses = { { name =, id = } } }
C_EncounterJournal = {
    GetInstanceForGameMap = function(mapID)
        local j = mock.journal[mapID]
        return j and j.journalID or nil
    end,
}
function EJ_GetInstanceForMap() return nil end
function EJ_GetEncounterInfoByIndex(index, journalID)
    for _, j in pairs(mock.journal) do
        if j.journalID == journalID and j.bosses[index] then
            local b = j.bosses[index]
            return b.name, "", 1000 + index, 0, "", journalID, b.id, 0
        end
    end
end
C_Map = { GetBestMapForUnit = function() return nil end }

-- Damage meter ---------------------------------------------------------------
-- session = { id =, name =, duration =, sources = { { guid =, name =, class =,
--   isLocal =, dmg =, heal =, taken =, avoid =, ints =, disp =, deaths =,
--   spells = { dmg = { { id, amount } }, heal = ... } } } }
mock.meter = { sessions = {}, secret = false, available = true, reason = "", reads = 0 }
Enum = Enum or {}
Enum.DamageMeterType = {
    DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4, Interrupts = 5, Dispels = 6,
    DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9, EnemyDamageTaken = 10,
}
local FIELD = { [0] = "dmg", [2] = "heal", [5] = "ints", [6] = "disp", [7] = "taken", [8] = "avoid", [9] = "deaths" }

local function findSession(id)
    for _, s in ipairs(mock.meter.sessions) do
        if s.id == id then return s end
    end
end

local function hidden()
    return mock.meter.secret or mock.inCombat -- SecretWhenInCombat
end

C_DamageMeter = {
    IsDamageMeterAvailable = function() return mock.meter.available, mock.meter.reason end,
    GetAvailableCombatSessions = function()
        local list = {}
        for _, s in ipairs(mock.meter.sessions) do
            list[#list + 1] = { sessionID = s.id, name = s.name or "", durationSeconds = s.duration }
        end
        return list
    end,
    GetCombatSessionFromID = function(id, meterType)
        mock.meter.reads = mock.meter.reads + 1
        local field = assert(FIELD[meterType], "unexpected meter type " .. tostring(meterType))
        local s = findSession(id)
        local session = { combatSources = {}, maxAmount = 0, totalAmount = 0, durationSeconds = s and s.duration }
        if not s then return session end
        local total = 0
        for _, src in ipairs(s.sources) do
            local function entry(amount)
                local e = {
                    sourceGUID = src.guid, name = src.name, classFilename = src.class or "",
                    isLocalPlayer = src.isLocal or false, totalAmount = amount, specIconID = SECRET,
                    amountPerSecond = amount / math.max(1, s.duration or 1), deathRecapID = 0,
                    sourceCreatureID = src.creature,
                }
                if hidden() then
                    e.totalAmount, e.amountPerSecond = SECRET, SECRET
                end
                session.combatSources[#session.combatSources + 1] = e
                return e
            end
            if field == "deaths" then
                for n = 1, src.deaths or 0 do
                    entry(0).deathRecapID = n
                end
            elseif (src[field] or 0) > 0 then
                entry(src[field])
                total = total + src[field]
            end
        end
        session.totalAmount = hidden() and SECRET or total
        return session
    end,
    GetCombatSessionSourceFromID = function(id, meterType, guid)
        local field = FIELD[meterType]
        local s = findSession(id)
        local result = { combatSpells = {}, maxAmount = 0, totalAmount = 0 }
        for _, src in ipairs(s and s.sources or {}) do
            if src.guid == guid then
                result.totalAmount = src[field] or 0
                for _, spell in ipairs(src.spells and src.spells[field] or {}) do
                    result.combatSpells[#result.combatSpells + 1] = { spellID = spell[1], totalAmount = spell[2] }
                end
            end
        end
        return result
    end,
    ResetAllCombatSessions = function() mock.meter.sessions = {} end,
}

function mock.addSession(s)
    mock.meter.sessions[#mock.meter.sessions + 1] = s
    return s
end

return mock
