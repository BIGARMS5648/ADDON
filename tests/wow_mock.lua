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

return mock
