-- Stand-in for the WoW Forever client API, broad enough to load and drive
-- BIGARMS. Loaded by tests/run_bigarms_tests.py into a Lua 5.1 runtime.
--
-- Unknown globals read by the addon are recorded (mock.unknownGlobals) and
-- checked against tests/bigarms_api_whitelist.txt by the runner, so a typo
-- in an API name fails the tests. Unknown events are recorded too.

local mock = {}
_G.mock = mock

mock.printed = {}
mock.sounds = {}
mock.timers = {}
mock.time = 1000
mock.inCombat = false
mock.frames = {}
mock.events = {}
mock.calls = {} -- [api name] = { {args}, ... }
mock.unknownGlobals = {}
mock.unknownEvents = {}

local function record(name, ...)
    mock.calls[name] = mock.calls[name] or {}
    mock.calls[name][#mock.calls[name] + 1] = { ... }
end
mock.record = record

function mock.count(name)
    return mock.calls[name] and #mock.calls[name] or 0
end

function mock.reset()
    mock.printed = {}
    mock.sounds = {}
    mock.calls = {}
end

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
mock.SECRET = SECRET

function issecretvalue(v) return v == SECRET end
function canaccessvalue(v) return v ~= SECRET end

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    mock.printed[#mock.printed + 1] = table.concat(parts, " ")
end

function wipe(t)
    for k in pairs(t) do t[k] = nil end
    return t
end
tinsert = table.insert
tremove = table.remove
function strsplit(sep, text)
    local out = {}
    for piece in (text .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = piece end
    return unpack(out)
end
function GetLocale() return mock.locale or "koKR" end
function GetTime() return mock.time end
function time() return os.time() end
function InCombatLockdown() return mock.inCombat end
function IsLoggedIn() return mock.loggedIn or false end
function PlaySound(id) mock.sounds[#mock.sounds + 1] = id end
function hooksecurefunc(a, b, c)
    if c == nil then
        local name, fn = a, b
        local orig = _G[name]
        assert(type(orig) == "function", "hooksecurefunc of missing global " .. tostring(name))
        _G[name] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpack(r)
        end
    else
        local tbl, name, fn = a, b, c
        local orig = tbl[name]
        assert(type(orig) == "function", "hooksecurefunc of missing method " .. tostring(name))
        tbl[name] = function(...)
            local r = { orig(...) }
            fn(...)
            return unpack(r)
        end
    end
end
SOUNDKIT = { MAP_PING = 3175, RAID_WARNING = 8959, IG_QUEST_LIST_COMPLETE = 6199, TELL_MESSAGE = 3081 }
STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
UISpecialFrames = {}
OKAY, CANCEL, YES, NO = "Okay", "Cancel", "Yes", "No"
DELETE_ITEM_CONFIRM_STRING = "DELETE"
ITEM_SPELL_KNOWN = "Already known"
SELL_PRICE = "Sell Price"
NUM_CHAT_WINDOWS = 3
NUM_BAG_SLOTS = 4
NUM_CONTAINER_FRAMES = 3
MERCHANT_ITEMS_PER_PAGE = 10
LE_PARTY_CATEGORY_INSTANCE = 2

RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 },
    PRIEST = { r = 1, g = 1, b = 1 }, DRUID = { r = 1, g = 0.49, b = 0.04 },
}
FACTION_STANDING_LABEL4 = "Neutral"
FACTION_STANDING_LABEL5 = "Friendly"
-- localized chat labels (Korean client)
CHAT_SAY_GET = "|Hchannel:SAY|h[대화]|h %s: "
CHAT_YELL_GET = "|Hchannel:YELL|h[외치기]|h %s: "
CHAT_PARTY_GET = "|Hchannel:PARTY|h[파티]|h %s: "
CHAT_PARTY_LEADER_GET = "|Hchannel:PARTY|h[파티장]|h %s: "
CHAT_RAID_GET = "|Hchannel:RAID|h[공격대]|h %s: "
CHAT_RAID_LEADER_GET = "|Hchannel:RAID|h[공격대장]|h %s: "
CHAT_RAID_WARNING_GET = "[공격대 경보] %s: "
CHAT_GUILD_GET = "|Hchannel:GUILD|h[길드]|h %s: "
CHAT_OFFICER_GET = "|Hchannel:OFFICER|h[임원]|h %s: "
CHAT_INSTANCE_CHAT_GET = "|Hchannel:INSTANCE_CHAT|h[인스턴스]|h %s: "
CHAT_INSTANCE_CHAT_LEADER_GET = "|Hchannel:INSTANCE_CHAT|h[인스턴스 지휘관]|h %s: "
-- error strings
ERR_OUT_OF_RANGE = "Out of range."
ERR_OUT_OF_RAGE = "Not enough rage"
ERR_ABILITY_COOLDOWN = "Ability is not ready yet."
SPELL_FAILED_NOT_STANDING = "You must be standing to do that"
ERR_ATTACK_MOUNTED = "Can't attack while mounted."
ERR_LOOT_NOTSTANDING = "You must be standing to loot."

-- Timers -------------------------------------------------------------------
C_Timer = {
    After = function(delay, fn) mock.timers[#mock.timers + 1] = { delay = delay, fn = fn } end,
    NewTicker = function(interval, fn, iterations)
        local ticker = { interval = interval, fn = fn, cancelled = false }
        function ticker:Cancel() self.cancelled = true end
        mock.tickers = mock.tickers or {}
        mock.tickers[#mock.tickers + 1] = ticker
        return ticker
    end,
}

function mock.flushTimers()
    local guard = 0
    while #mock.timers > 0 do
        guard = guard + 1
        assert(guard < 200, "timer loop")
        local list = mock.timers
        mock.timers = {}
        for _, t in ipairs(list) do t.fn() end
    end
end

function mock.tick()
    for _, ticker in ipairs(mock.tickers or {}) do
        if not ticker.cancelled then ticker.fn() end
    end
end

-- CVars --------------------------------------------------------------------
mock.cvars = {
    autoLootDefault = "0", showTimestamps = "none", cameraDistanceMaxZoomFactor = "1.9",
    statusTextDisplay = "NUMERIC", statusText = "1", outlineModeShowLootEffectWhenDisabled = "0",
    displayFreeBagSlots = "0", autoQuestWatch = "1", SpellQueueWindow = "400", scriptErrors = "0",
    test_cameraDynamicPitch = "0", test_cameraOverShoulder = "0", test_cameraHeadMovementStrength = "0",
    test_cameraTargetFocusEnemyEnable = "0", test_cameraTargetFocusInteractEnable = "0",
    nameplateMaxDistance = "41", chatBubbles = "1", ActionButtonUseKeyDown = "1",
    floatingCombatTextCombatDamage = "1", screenshotQuality = "3", rawMouseEnable = "0",
}
C_CVar = {
    GetCVar = function(name) return mock.cvars[name] end,
    SetCVar = function(name, value)
        if mock.cvars[name] == nil then return false end
        mock.cvars[name] = tostring(value)
        return true
    end,
    GetCVarBool = function(name) return mock.cvars[name] == "1" end,
}

-- Events the client knows (anything else is an unknown event) ----------------
local KNOWN_EVENTS = {}
for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
    "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS",
    "QUEST_COMPLETE", "QUEST_ACCEPT_CONFIRM", "QUEST_ACCEPTED", "QUEST_WATCH_UPDATE", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
    "UNIT_QUEST_LOG_CHANGED", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE", "PARTY_INVITE_REQUEST", "RESURRECT_REQUEST",
    "CONFIRM_SUMMON", "DUEL_REQUESTED", "GUILD_INVITE_REQUEST", "PETITION_SHOW", "TRADE_SHOW", "PLAYER_DEAD",
    "PLAYER_ALIVE", "PLAYER_UNGHOST", "LOOT_READY", "CINEMATIC_START", "PLAY_MOVIE", "MINIMAP_UPDATE_TRACKING",
    "PLAYER_LEVEL_UP", "CHAT_MSG_WHISPER", "CHAT_MSG_BN_WHISPER", "UPDATE_CHAT_WINDOWS", "UPDATE_FLOATING_CHAT_WINDOWS",
    "MINIMAP_PING", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "UNIT_TARGET", "GROUP_ROSTER_UPDATE", "UNIT_FACTION",
    "UNIT_PET", "UPDATE_INVENTORY_DURABILITY", "PLAYER_EQUIPMENT_CHANGED", "UPDATE_FACTION", "PLAYER_SWING",
    "PLAYER_MONEY", "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
    "ZONE_CHANGED_NEW_AREA", "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED", "PLAYER_SOFT_INTERACT_CHANGED",
}) do KNOWN_EVENTS[e] = true end
mock.knownEvents = KNOWN_EVENTS

C_EventUtils = {
    IsEventValid = function(event)
        if not KNOWN_EVENTS[event] then
            mock.unknownEvents[event] = true
        end
        return KNOWN_EVENTS[event] == true
    end,
}

-- Regions / frames -------------------------------------------------------------
local Region = {}
Region.__index = Region

local function newRegion(kind, parent, name)
    local r = setmetatable({
        kind = kind, parent = parent, name = name, shown = true, points = {}, alpha = 1, scale = 1,
        width = 10, height = 10, frameLevel = 1, scripts = {}, children = {}, texts = {}, id = 0,
        textures = {}, registered = {},
    }, Region)
    if parent and parent.children then
        parent.children[#parent.children + 1] = r
    end
    return r
end
mock.newRegion = newRegion

local function noop() end
for _, m in ipairs({
    "SetFrameStrata", "SetMovable", "SetClampedToScreen", "RegisterForDrag", "RegisterForClicks", "SetUserPlaced",
    "SetHighlightTexture", "SetNormalTexture", "LockHighlight", "UnlockHighlight", "SetBackdrop", "SetBackdropColor",
    "SetBackdropBorderColor", "StartMoving", "StopMovingOrSizing", "SetBlendMode", "SetRotation", "SetTexCoord",
    "SetAtlas", "SetDesaturated", "SetJustifyH", "SetFontObject", "SetAutoFocus", "SetFocus", "HighlightText",
    "SetMultiLine", "SetCursorPosition", "SetAltArrowKeyMode", "SetScrollChild", "SetFading", "ScrollToTop",
    "ScrollToBottom", "SetIgnoreParentAlpha", "SetStatusBarTexture", "SetStatusBarDesaturated", "SetAttribute",
    "SetMaskTexture", "SetColorTexture", "SetFormattedText", "SetUsingParentLevel", "EnableMouseWheel",
}) do Region[m] = noop end

function Region:GetObjectType() return self.kind end
function Region:GetName() return self.name end
function Region:SetParent(p) self.parent = p end
function Region:GetParent() return self.parent end
function Region:GetChildren() return unpack(self.children) end
function Region:Show() self.shown = true; if self.scripts.OnShow then self.scripts.OnShow(self) end end
function Region:Hide() self.shown = false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
function Region:IsShown() return self.shown end
function Region:IsVisible() return self.shown end
function Region:SetShown(v) if v then self:Show() else self:Hide() end end
function Region:IsForbidden() return false end
function Region:IsProtected() return false end
function Region:ClearAllPoints() self.points = {} end
function Region:SetPoint(...) self.points[#self.points + 1] = { ... } end
function Region:SetAllPoints() self.points = { { "ALL" } } end
function Region:GetPoint(i)
    local p = self.points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Region:SetSize(w, h) self.width, self.height = w, h end
function Region:SetWidth(w) self.width = w end
function Region:SetHeight(h) self.height = h end
function Region:GetWidth() return self.width end
function Region:GetHeight() return self.height end
function Region:GetSize() return self.width, self.height end
function Region:SetAlpha(a) self.alpha = a end
function Region:GetAlpha() return self.alpha end
function Region:SetScale(s) self.scale = s end
function Region:GetScale() return self.scale end
function Region:GetEffectiveScale() return self.scale end
function Region:SetFrameLevel(l) self.frameLevel = l end
function Region:GetFrameLevel() return self.frameLevel end
function Region:GetCenter() return self.centerX or 0, self.centerY or 0 end
function Region:GetLeft() return 100 end
function Region:GetBottom() return 200 end
function Region:EnableMouse(v) self.mouse = v end
function Region:SetID(id) self.id = id end
function Region:GetID() return self.id end
function Region:SetScript(name, fn) self.scripts[name] = fn end
function Region:GetScript(name) return self.scripts[name] end
function Region:HookScript(name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...)
        if old then old(...) end
        fn(...)
    end
end
function Region:Click() if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton") end end
-- textures
function Region:SetTexture(t) self.texture = t end
function Region:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
function Region:GetVertexColor() local c = self.color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
-- font strings
function Region:SetText(t) self.text = t; if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self) end end
function Region:GetText() return self.text end
function Region:SetTextColor(r, g, b) self.textColor = { r, g, b } end
function Region:SetFont(font, size, flags) self.font = { font, size, flags } end
function Region:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
-- status bars
function Region:SetMinMaxValues(a, b) self.minValue, self.maxValue = a, b end
function Region:SetValue(v) self.value = v end
function Region:GetValue() return self.value end
function Region:SetStatusBarColor(r, g, b) self.barColor = { r, g, b } end
-- scrolling message frames
function Region:AddMessage(text, r, g, b, typeID)
    self.messages = self.messages or {}
    self.messages[#self.messages + 1] = { text = text, r = r, g = g, b = b, typeID = typeID }
end
function Region:GetNumMessages() return self.messages and #self.messages or 0 end
function Region:GetMessageInfo(i)
    local m = self.messages and self.messages[i]
    if m then return m.text, m.r, m.g, m.b end
end
function Region:Clear() self.messages = {} end
-- minimap
function Region:GetZoom() return self.zoom or 0 end
function Region:SetZoom(z) self.zoom = z end
-- children
function Region:CreateTexture(name, layer)
    local t = newRegion("Texture", self, name)
    self.textures[#self.textures + 1] = t
    return t
end
function Region:CreateFontString(name)
    local t = newRegion("FontString", self, name)
    self.texts[#self.texts + 1] = t
    return t
end
function Region:CreateAnimationGroup()
    local group = { anims = {}, scripts = {} }
    function group:CreateAnimation()
        local anim = {}
        for _, m in ipairs({ "SetFromAlpha", "SetToAlpha", "SetDuration", "SetOrder", "SetStartDelay" }) do anim[m] = noop end
        self.anims[#self.anims + 1] = anim
        return anim
    end
    function group:Play() self.playing = true end
    function group:Stop() self.playing = false end
    function group:SetScript(name, fn) self.scripts[name] = fn end
    return group
end
function Region:RegisterEvent(e)
    if not KNOWN_EVENTS[e] then
        mock.unknownEvents[e] = true
        error("Attempt to register unknown event \"" .. tostring(e) .. "\"")
    end
    mock.events[e] = mock.events[e] or {}
    mock.events[e][self] = true
    self.registered[e] = true
end
function Region:RegisterUnitEvent(e) self:RegisterEvent(e) end
function Region:UnregisterEvent(e)
    if mock.events[e] then mock.events[e][self] = nil end
    self.registered[e] = nil
end
function Region:UnregisterAllEvents()
    for e in pairs(self.registered) do self:UnregisterEvent(e) end
end
function Region:IsEventRegistered(e) return self.registered[e] == true end

function CreateFrame(kind, name, parent, template)
    local f = newRegion(kind or "Frame", parent, name)
    f.template = template
    if name then _G[name] = f end
    mock.frames[#mock.frames + 1] = f
    return f
end

function mock.fire(event, ...)
    for frame in pairs(mock.events[event] or {}) do
        local handler = frame.scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent.width, UIParent.height = 1366, 768
Minimap = CreateFrame("Frame", "Minimap", UIParent)
Minimap.width, Minimap.height = 140, 140
Minimap.centerX, Minimap.centerY = 1250, 650
MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop", Minimap)
MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
MinimapCluster.ZoneTextButton = CreateFrame("Button", nil, MinimapCluster)
MinimapCluster.Tracking = CreateFrame("Button", nil, MinimapCluster)
Minimap.ZoomIn = CreateFrame("Button", nil, Minimap)
Minimap.ZoomOut = CreateFrame("Button", nil, Minimap)
TimeManagerClockButton = CreateFrame("Button", "TimeManagerClockButton", Minimap)
GameTimeFrame = CreateFrame("Button", "GameTimeFrame", Minimap)
MinimapCompassTexture = Minimap:CreateTexture("MinimapCompassTexture")
UIErrorsFrame = CreateFrame("Frame", "UIErrorsFrame", UIParent)
UIErrorsFrame:RegisterEvent("UI_ERROR_MESSAGE")
UIErrorsFrame.displayed = {}
function UIErrorsFrame:TryDisplayMessage(errorType, message) self.displayed[#self.displayed + 1] = message end
RaidWarningFrame = CreateFrame("Frame", "RaidWarningFrame", UIParent)
mock.raidNotices = {}
function RaidNotice_AddMessage(frame, text) mock.raidNotices[#mock.raidNotices + 1] = text end
ZoneTextFrame = CreateFrame("Frame", "ZoneTextFrame", UIParent)
ZoneTextFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
SubZoneTextFrame = CreateFrame("Frame", "SubZoneTextFrame", UIParent)
CharacterFrame = CreateFrame("Frame", "CharacterFrame", UIParent)
CharacterFrame.shown = false
for _, slotName in ipairs({ "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet", "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged" }) do
    local b = CreateFrame("Button", "Character" .. slotName .. "Slot", CharacterFrame)
end
CharacterHeadSlot:SetID(1)
CharacterChestSlot:SetID(5)
CharacterMainHandSlot:SetID(16)
MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
MerchantFrame.shown = false
PlayerFrame = CreateFrame("Frame", "PlayerFrame", UIParent)
PlayerFrame.healthbar = CreateFrame("StatusBar", nil, PlayerFrame)
PlayerFrame.healthbar.lockColor = true
TargetFrame = CreateFrame("Frame", "TargetFrame", UIParent)
TargetFrame.healthbar = CreateFrame("StatusBar", nil, TargetFrame)
MainMenuBar = CreateFrame("Frame", "MainMenuBar", UIParent)
MainMenuBar.EndCaps = CreateFrame("Frame", nil, MainMenuBar)
QuestFrame = CreateFrame("Frame", "QuestFrame", UIParent)
GossipFrame = CreateFrame("Frame", "GossipFrame", UIParent)
MailFrame = CreateFrame("Frame", "MailFrame", UIParent)
QuestInfoRewardsFrame = { RewardButtons = { CreateFrame("Button"), CreateFrame("Button"), CreateFrame("Button") } }
CinematicFrame = CreateFrame("Frame", "CinematicFrame", UIParent)
MovieFrame = CreateFrame("Frame", "MovieFrame", UIParent)
MovieFrame.shown = false

-- chat frames
ChatTypeInfo = {
    SAY = { r = 1, g = 1, b = 1 }, WHISPER = { r = 1, g = 0.5, b = 1, sticky = 1 }, PARTY = {}, RAID = {},
    GUILD = {}, YELL = {}, EMOTE = {}, OFFICER = {}, RAID_WARNING = { r = 1, g = 0.5, b = 0 }, CHANNEL = {}, BN_WHISPER = {},
}
local chatTypeIndex = { WHISPER = 7, WHISPER_INFORM = 8, BN_WHISPER = 40, BN_WHISPER_INFORM = 41, SAY = 1 }
function GetChatTypeIndex(name) return chatTypeIndex[name] end
function SetChatColorNameByClass(chatType, v) record("SetChatColorNameByClass", chatType, v) end
function FCF_SetChatWindowFontSize(_, frame, size) record("FCF_SetChatWindowFontSize", frame, size) end
for i = 1, NUM_CHAT_WINDOWS do
    local f = CreateFrame("ScrollingMessageFrame", "ChatFrame" .. i, UIParent)
    f.editBox = CreateFrame("EditBox", "ChatFrame" .. i .. "EditBox", f)
    CreateFrame("Frame", "ChatFrame" .. i .. "ButtonFrame", f)
end
ChatFrameMenuButton = CreateFrame("Button", "ChatFrameMenuButton", UIParent)
ChatFrameChannelButton = CreateFrame("Button", "ChatFrameChannelButton", UIParent)
QuickJoinToastButton = CreateFrame("Button", "QuickJoinToastButton", UIParent)
mock.chatFilters = {}
function ChatFrame_AddMessageEventFilter(event, fn)
    mock.chatFilters[event] = mock.chatFilters[event] or {}
    table.insert(mock.chatFilters[event], fn)
end
function ChatFrame_RemoveMessageEventFilter() end
function SetItemRef(link, text, button) record("SetItemRef", link) end
function FlashClientIcon() record("FlashClientIcon") end

-- tooltips
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
GameTooltip.lines = {}
GameTooltip.NineSlice = { SetBorderColor = function(self, r, g, b) self.border = { r, g, b } end }
function GameTooltip:SetOwner(owner, anchor) self.owner = owner; self.anchor = anchor; self.lines = {} end
function GameTooltip:GetOwner() return self.owner end
function GameTooltip:SetText(t) self.lines = { t } end
function GameTooltip:AddLine(t) self.lines[#self.lines + 1] = t end
function GameTooltip:AddDoubleLine(a, b) self.lines[#self.lines + 1] = tostring(a) .. " | " .. tostring(b) end
function GameTooltip:IsOwned(f) return self.owner == f and self.shown end
function GameTooltip:GetUnit() return self.unitName, self.unit end
function GameTooltip:GetItem() return self.itemName, self.itemLink end
GameTooltipTextLeft1 = GameTooltip:CreateFontString("GameTooltipTextLeft1")
GameTooltipTextLeft2 = GameTooltip:CreateFontString("GameTooltipTextLeft2")
GameTooltipStatusBar = CreateFrame("StatusBar", "GameTooltipStatusBar", GameTooltip)
function GameTooltip_SetDefaultAnchor(tooltip, parent) tooltip:SetOwner(parent, "ANCHOR_NONE") end
mock.tooltipPostCalls = {}
TooltipDataProcessor = {
    AddTooltipPostCall = function(kind, fn) mock.tooltipPostCalls[kind] = fn end,
}
Enum = {
    TooltipDataType = { Unit = 2, Item = 0, Spell = 1, UnitAura = 7, Macro = 11, Object = 20 },
    BagIndex = { Backpack = 0, ReagentBag = 5 },
    PlayerSwingType = { MainHand = 0, OffHand = 1, Ranged = 2 },
}

-- Static popups
StaticPopupDialogs = {}
mock.popups = {}
function StaticPopup_Show(which, text, _, data)
    mock.popups[which] = { text = text, data = data, shown = true }
    record("StaticPopup_Show", which)
    local dialog = mock.popups[which]
    dialog.editBox = CreateFrame("EditBox")
    local info = StaticPopupDialogs[which]
    if info and info.OnShow then info.OnShow(dialog, data) end
    return dialog
end
function StaticPopup_Hide(which) record("StaticPopup_Hide", which); if mock.popups[which] then mock.popups[which].shown = false end end
function StaticPopup_FindVisible(which) local p = mock.popups[which]; return p and p.shown and p or nil end

-- Settings ------------------------------------------------------------------
mock.settings = {}
mock.initializers = {}
mock.categories = {}
local function newCategory(name)
    local category = { name = name, GetID = function() return #mock.categories + 1 end }
    mock.categories[#mock.categories + 1] = category
    local layout = { AddInitializer = function(_, init) mock.initializers[#mock.initializers + 1] = init end }
    return category, layout
end
Settings = {
    VarType = { Boolean = "boolean", String = "string", Number = "number" },
    RegisterVerticalLayoutCategory = newCategory,
    RegisterVerticalLayoutSubcategory = function(parent, name) return newCategory(name) end,
    RegisterProxySetting = function(category, variable, varType, name, default, get, set)
        local s = { variable = variable, varType = varType, name = name, default = default, get = get, set = set }
        assert(mock.settings[variable] == nil, "duplicate setting " .. variable)
        assert(type(default) == varType, ("setting %s: default %s is not a %s"):format(variable, tostring(default), varType))
        mock.settings[variable] = s
        return s
    end,
    CreateCheckbox = function(category, setting) setting.control = "checkbox" end,
    CreateSlider = function(category, setting, options) setting.control = "slider"; setting.options = options end,
    CreateDropdown = function(category, setting, getOptions)
        setting.control = "dropdown"
        setting.choices = getOptions()
        local found = false
        for _, c in ipairs(setting.choices) do
            if c.value == setting.get() then found = true end
        end
        assert(found, "dropdown " .. setting.variable .. " current value " .. tostring(setting.get()) .. " is not a choice")
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
    return { button = name, onClick = onClick }
end
SlashCmdList = {}

-- Units ------------------------------------------------------------------------
mock.units = {
    player = { name = "빅암", class = "WARRIOR", isPlayer = true, level = 23, guid = "Player-1-0000000A" },
}
local function unit(u) return mock.units[u] end
function UnitName(u) local d = unit(u); return d and d.name end
function UnitGUID(u) local d = unit(u); return d and d.guid end
function UnitClass(u) local d = unit(u); return d and d.class, d and d.class end
function UnitLevel(u) local d = unit(u); return d and d.level or 1 end
function UnitExists(u) return unit(u) ~= nil end
function UnitIsPlayer(u) local d = unit(u); return d and d.isPlayer or false end
function UnitIsUnit(a, b) return a == b or (unit(a) and unit(b) and unit(a).guid == unit(b).guid) end
function UnitReaction(u) local d = unit(u); return d and d.reaction or 5 end
function UnitIsTapDenied() return false end
function UnitAffectingCombat() return mock.inCombat end
function UnitIsDead(u) local d = unit(u); return d and d.dead or false end
function UnitIsGhost(u) local d = unit(u); return d and d.ghost or false end
function UnitIsDeadOrGhost(u) return UnitIsDead(u) or UnitIsGhost(u) end
function UnitXP() return mock.xp or 1200 end
function UnitXPMax() return mock.xpMax or 10000 end
function GetXPExhaustion() return mock.rested or 500 end
function IsPlayerAtEffectiveMaxLevel() return false end
function GetGuildInfo(u) local d = unit(u); if d and d.guild then return d.guild, d.guildRank, 1 end end
function GetMoney() return mock.money or 123456 end
function GetRealmName() return "Forever" end
function IsShiftKeyDown() return mock.shift or false end
function IsControlKeyDown() return mock.ctrl or false end
function IsAltKeyDown() return mock.alt or false end
function IsInGroup(category)
    if category then return mock.inInstanceGroup or false end
    return mock.inGroup or false
end
function IsInRaid() return false end
function UnitIsGroupLeader() return true end
function IsInInstance() return false, "none" end
function IsMounted() return mock.mounted or false end
function Dismount() record("Dismount") end
function DoEmote(e) record("DoEmote", e) end
function IsModifiedClick() return false end
function GetPlayerFacing() return mock.facing or 0 end
function Screenshot() record("Screenshot") end
function ReloadUI() error("blocked") end
function FlashClientIcon() record("FlashClientIcon") end
function GetCursorPosition() return 0, 0 end
function SendChatMessage(msg, channel) record("SendChatMessage", msg, channel) end
function InviteUnit(name) record("InviteUnit", name) end
C_PartyInfo = { InviteUnit = function(name) record("InviteUnit", name) end }

-- friends / guild
mock.friends = { ["Friend"] = true }
C_FriendList = {
    IsFriend = function(guid) return guid == "Player-1-FRIEND" end,
    GetFriendInfo = function(name) return mock.friends[name] and { name = name } or nil end,
}
function IsGuildMember(guid) return guid == "Player-1-GUILDIE" end
function IsInGuild() return false end
C_BattleNet = { GetGameAccountInfoByGUID = function() return nil end, GetAccountInfoByID = function() return nil end }

-- vendor
mock.merchant = { canRepair = true, repairCost = 2500 }
function CanMerchantRepair() return mock.merchant.canRepair end
function GetRepairAllCost() return mock.merchant.repairCost, mock.merchant.repairCost > 0 end
function CanGuildBankRepair() return false end
function RepairAllItems(guild) record("RepairAllItems", guild) end

-- bags
mock.bags = {} -- [bag] = { [slot] = info }
mock.items = {} -- [itemID] = { name, quality, sellPrice, equipLoc, level }
local function itemFromLink(link)
    local id = tonumber(tostring(link):match("item:(%d+)"))
    return id, mock.items[id]
end
C_Container = {
    GetContainerNumSlots = function(bag) return mock.bags[bag] and 16 or 0 end,
    GetContainerItemInfo = function(bag, slot) return mock.bags[bag] and mock.bags[bag][slot] end,
    UseContainerItem = function(bag, slot)
        record("UseContainerItem", bag, slot)
        if mock.bags[bag] then mock.bags[bag][slot] = nil end
    end,
}
C_Item = {
    GetItemInfo = function(link)
        local id, item = itemFromLink(link)
        if not item then return nil end
        return item.name, link, item.quality, item.level, 1, "Armor", "Cloth", 20, item.equipLoc or "", 134, item.sellPrice, 4, 1
    end,
    GetDetailedItemLevelInfo = function(link) local _, item = itemFromLink(link); return item and item.level end,
    GetItemCount = function(itemID, bank) return bank and 5 or 3 end,
    GetItemQualityColor = function(q) return 1, 1, 1 end,
}
function GetInventoryItemLink(unit, slot) return mock.equipped and mock.equipped[slot] end
mock.durability = { [1] = { 50, 100 }, [5] = { 90, 100 }, [16] = { 60, 120 } }
function GetInventoryItemDurability(slot)
    local d = mock.durability[slot]
    if d then return d[1], d[2] end
end

-- quests / gossip
mock.gossip = { active = {}, available = {}, options = {} }
C_GossipInfo = {
    GetActiveQuests = function() return mock.gossip.active end,
    GetAvailableQuests = function() return mock.gossip.available end,
    GetOptions = function() return mock.gossip.options end,
    GetNumActiveQuests = function() return #mock.gossip.active end,
    GetNumAvailableQuests = function() return #mock.gossip.available end,
    SelectActiveQuest = function(id) record("SelectActiveQuest", id) end,
    SelectAvailableQuest = function(id) record("SelectAvailableQuest", id) end,
    SelectOption = function(id) record("SelectOption", id) end,
}
mock.quest = { id = 100, trivial = false, completable = true, choices = 0, autoAccept = false }
function GetQuestID() return mock.quest.id end
function QuestGetAutoAccept() return mock.quest.autoAccept end
function AcknowledgeAutoAcceptQuest() record("AcknowledgeAutoAcceptQuest") end
function AcceptQuest() record("AcceptQuest") end
function IsQuestCompletable() return mock.quest.completable end
function CompleteQuest() record("CompleteQuest") end
function GetNumQuestChoices() return mock.quest.choices end
function GetQuestReward(i) record("GetQuestReward", i) end
function GetQuestItemLink(kind, i) return mock.quest.choiceLinks and mock.quest.choiceLinks[i] end
function GetQuestItemInfo() return "x", 1, 1 end
function ConfirmAcceptQuest() record("ConfirmAcceptQuest") end
function GetNumActiveQuests() return 0 end
function GetNumAvailableQuests() return 0 end
C_QuestLog = {
    IsQuestTrivial = function(id) return mock.quest.trivial end,
    AddQuestWatch = function(id) record("AddQuestWatch", id) end,
    GetQuestWatchType = function() return nil end,
    IsComplete = function(id) return mock.quest.complete and mock.quest.complete[id] or false end,
    GetTitleForQuestID = function(id) return "Quest " .. id end,
    GetInfo = function() return nil end,
}

-- group / social actions
function AcceptGroup() record("AcceptGroup") end
function AcceptResurrect() record("AcceptResurrect") end
function CancelDuel() record("CancelDuel") end
function DeclineGuild() record("DeclineGuild") end
function CancelTrade() record("CancelTrade") end
function GetPetitionInfo() return "guild", "Guild", "G", 10, "Stranger", false end
function ClosePetition() record("ClosePetition") end
C_SummonInfo = { ConfirmSummon = function() record("ConfirmSummon") end, GetSummonConfirmTimeLeft = function() return 100 end }
C_DeathInfo = { GetSelfResurrectOptions = function() return {} end }
C_PvP = { IsBattleground = function() return mock.inBattleground or false end }
function RepopMe() record("RepopMe") end

-- loot
mock.lootItems = 0
function GetNumLootItems() return mock.lootItems end
function LootSlot(i) record("LootSlot", i) end

-- cinematics
function CinematicFrame_CancelCinematic() record("CinematicFrame_CancelCinematic") end
function MovieFrame_OnMovieFinished() record("MovieFrame_OnMovieFinished") end

-- tracking
mock.tracking = { { name = "약초 찾기", active = false, type = "spell", spellID = 2383 }, { name = "광물 찾기", active = false, type = "spell", spellID = 2580 } }
C_Minimap = {
    GetNumTrackingTypes = function() return #mock.tracking end,
    GetTrackingInfo = function(i) return mock.tracking[i] end,
    SetTracking = function(i, v) mock.tracking[i].active = v; record("SetTracking", i, v) end,
}

-- map
mock.map = { id = 1429, x = 0.5, y = 0.5 }
C_Map = {
    GetBestMapForUnit = function() return mock.map.id end,
    GetPlayerMapPosition = function(mapID)
        if mock.map.hidden then return nil end
        return { GetXY = function() return mock.map.x, mock.map.y end }
    end,
    GetWorldPosFromMapPos = function(mapID, pos)
        local x, y = pos:GetXY()
        -- 1000 yd wide, 700 yd tall map: world x = north, y = west
        return mapID, { GetXY = function() return -(y * 700), -(x * 1000) end }
    end,
    SetUserWaypoint = function(point) record("SetUserWaypoint", point) end,
    ClearUserWaypoint = function() record("ClearUserWaypoint") end,
    CanSetUserWaypointOnMap = function() return true end,
}
function CreateVector2D(x, y) return { GetXY = function() return x, y end } end
UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { mapID = mapID, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) record("SetSuperTrackedUserWaypoint", v) end }

-- reputation
mock.factions = { { factionID = 72, name = "Stormwind", reaction = 5, currentStanding = 3100, currentReactionThreshold = 3000, nextReactionThreshold = 9000 } }
C_Reputation = {
    GetNumFactions = function() return #mock.factions end,
    GetFactionDataByIndex = function(i) return mock.factions[i] end,
}

C_AddOns = {
    GetAddOnMetadata = function(addon, field) return field == "Version" and "1.0.0-test" or nil end,
    IsAddOnLoaded = function(name) return mock.loadedAddons and mock.loadedAddons[name] or false end,
}

return mock
