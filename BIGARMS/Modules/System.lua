local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- System: handy game settings (CVars) in one place
--------------------------------------------------------------------------

local System = ns:NewModule("System", {
    group = "SYSTEM",
    defaults = {
        enabled = true,
        autoLoot = "KEEP", -- KEEP | ON | OFF
        scriptErrors = "KEEP",
        spellQueue = -1, -- -1 keep
        screenshotQuality = -1,
        chatBubbles = "KEEP",
        rawMouse = "KEEP",
        nameplateDistance = -1,
        floatingCombatText = "KEEP",
        combinedBags = "KEEP",
        errorSpeech = "KEEP",
        mapFade = "KEEP",
    },
    options = {
        { type = "description", text = "SYS_HELP" },
        { key = "autoLoot", type = "select", label = "SYS_AUTOLOOT", cvar = "autoLootDefault", choices = "ONOFF" },
        { key = "combinedBags", type = "select", label = "SYS_COMBINED_BAGS", tooltip = "SYS_COMBINED_BAGS_TT", cvar = "combinedBags", choices = "ONOFF" },
        { key = "errorSpeech", type = "select", label = "SYS_ERROR_SPEECH", tooltip = "SYS_ERROR_SPEECH_TT", cvar = "Sound_EnableErrorSpeech", choices = "ONOFF" },
        { key = "mapFade", type = "select", label = "SYS_MAP_FADE", tooltip = "SYS_MAP_FADE_TT", cvar = "mapFade", choices = "ONOFF" },
        { key = "spellQueue", type = "range", label = "SYS_SPELL_QUEUE", tooltip = "SYS_SPELL_QUEUE_TT", cvar = "SpellQueueWindow", min = -1, max = 400, step = 25, format = "%d" },
        { key = "nameplateDistance", type = "range", label = "SYS_NAMEPLATE_DISTANCE", cvar = "nameplateMaxDistance", min = -1, max = 60, step = 1, format = "%d" },
        { key = "chatBubbles", type = "select", label = "SYS_CHAT_BUBBLES", cvar = "chatBubbles", choices = "ONOFF" },
        { key = "floatingCombatText", type = "select", label = "SYS_FCT", tooltip = "SYS_FCT_TT", cvar = "floatingCombatTextCombatDamage", choices = "ONOFF" },
        { key = "scriptErrors", type = "select", label = "SYS_SCRIPT_ERRORS", tooltip = "SYS_SCRIPT_ERRORS_TT", cvar = "scriptErrors", choices = "ONOFF" },
        { key = "screenshotQuality", type = "range", label = "SYS_SCREENSHOT", cvar = "screenshotQuality", min = -1, max = 10, step = 1, format = "%d" },
        { key = "rawMouse", type = "select", label = "SYS_RAW_MOUSE", cvar = "rawMouseEnable", choices = "ONOFF" },
    },
})

function System:ApplyAll()
    ns.ApplyCVarOptions(self)
end

function System:ApplyOption(option)
    ns.ApplyCVarOption(self, option)
end

-- /ba cvar <name> [value]
function System:HandleCVar(args)
    local name, value = args:match("^(%S+)%s*(.*)$")
    if not name then
        self:Print(L.CVAR_USAGE)
        return
    end
    value = ns.Trim(value or "")
    if not ns.CVarExists(name) then
        self:Print(L.CVAR_UNKNOWN:format(name))
        return
    end
    if value ~= "" then
        if ns.SetCVar(name, value) then
            self:Print(("%s = %s"):format(name, ns.GetCVar(name)))
        else
            self:Print(L.CVAR_FAILED:format(name))
        end
    else
        self:Print(("%s = %s"):format(name, tostring(ns.GetCVar(name))))
    end
end

-- /ba volume [0-100]
function System:HandleVolume(args)
    local value = tonumber(ns.Trim(args))
    if value then
        value = math.max(0, math.min(100, value))
        ns.SetCVar("Sound_MasterVolume", ("%.2f"):format(value / 100))
    end
    local current = tonumber(ns.GetCVar("Sound_MasterVolume")) or 0
    self:Print(L.VOLUME_NOW:format(math.floor(current * 100 + 0.5)))
end

function ns.AdjustVolume(delta)
    local current = tonumber(ns.GetCVar("Sound_MasterVolume")) or 0
    current = math.max(0, math.min(1, current + delta))
    ns.SetCVar("Sound_MasterVolume", ("%.2f"):format(current))
    return math.floor(current * 100 + 0.5)
end

function System:OnEnable()
    self:ApplyAll()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyAll")
end

function System:OnSettingChanged(key)
    for _, option in ipairs(self.options) do
        if option.key == key and option.cvar then
            self:ApplyOption(option)
        end
    end
end

--------------------------------------------------------------------------
-- Gold tracker: every character's gold, session gain, gold per hour
--------------------------------------------------------------------------

local Gold = ns:NewModule("Gold", {
    group = "SYSTEM",
    defaults = { enabled = true, tooltip = true },
    options = {
        { key = "tooltip", type = "toggle", label = "GOLD_TOOLTIP", tooltip = "GOLD_TOOLTIP_TT" },
        { type = "button", label = "GOLD_SHOW", button = "SHOW", func = function() ns:GetModule("Gold"):Report() end },
    },
})
ns.Gold = Gold

local function CharacterKey()
    local name, realm = UnitName("player"), GetRealmName and GetRealmName() or ""
    return ("%s - %s"):format(name or "?", realm or "?")
end

function Gold:Record()
    local money = ns.Plain(GetMoney())
    if not money then
        return
    end
    local key = CharacterKey()
    local entry = ns.db.gold[key] or {}
    local _, class = UnitClass("player")
    entry.copper = money
    entry.class = ns.Plain(class)
    entry.time = time()
    entry.realm = GetRealmName and GetRealmName() or "?"
    entry.name = UnitName("player")
    entry.level = ns.Plain(UnitLevel("player")) or entry.level
    entry.zone = GetRealZoneText and GetRealZoneText() or entry.zone
    if self.played then
        entry.played = self.played
    end
    ns.db.gold[key] = entry
    if not self.sessionStart then
        self.sessionStart = money
        self.sessionTime = GetTime()
    end
end

function Gold:SessionInfo()
    local money = ns.Plain(GetMoney()) or 0
    local gain = money - (self.sessionStart or money)
    local hours = (GetTime() - (self.sessionTime or GetTime())) / 3600
    local perHour = hours > 0.01 and gain / hours or 0
    return gain, perHour
end

function Gold:Report()
    local total = 0
    local lines = {}
    for _, entry in pairs(ns.db.gold) do
        lines[#lines + 1] = entry
        total = total + (entry.copper or 0)
    end
    table.sort(lines, function(a, b) return (a.copper or 0) > (b.copper or 0) end)
    self:Print(L.GOLD_HEADER)
    for _, entry in ipairs(lines) do
        local color = entry.class and ns.ClassColorHex(entry.class) or "ffffff"
        self:Print(("  |cff%s%s|r (%s): %s"):format(color, entry.name or "?", entry.realm or "?", ns.FormatMoney(entry.copper or 0)))
    end
    self:Print(L.GOLD_TOTAL:format(ns.FormatMoney(total)))
    local gain, perHour = self:SessionInfo()
    self:Print(L.GOLD_SESSION:format(ns.FormatMoney(gain), ns.FormatMoney(perHour)))
end

-- Lines for the minimap button tooltip.
function Gold:TooltipLines(tooltip)
    if not self.db.tooltip then
        return
    end
    local gain, perHour = self:SessionInfo()
    tooltip:AddLine(" ")
    tooltip:AddDoubleLine(L.GOLD_NOW, ns.FormatMoney(ns.Plain(GetMoney()) or 0), 1, 0.82, 0, 1, 1, 1)
    tooltip:AddDoubleLine(L.GOLD_SESSION_SHORT, ns.FormatMoney(gain), 1, 0.82, 0, 1, 1, 1)
    tooltip:AddDoubleLine(L.GOLD_PER_HOUR, ns.FormatMoney(perHour), 1, 0.82, 0, 1, 1, 1)
    local total = 0
    for _, entry in pairs(ns.db.gold) do
        total = total + (entry.copper or 0)
    end
    tooltip:AddDoubleLine(L.GOLD_ALL_CHARS, ns.FormatMoney(total), 1, 0.82, 0, 1, 1, 1)
end

-- /played, quietly: the two system lines are hidden for a moment
local playedPatterns

function Gold:RequestPlayed()
    if not RequestTimePlayed then
        return
    end
    if not playedPatterns then
        playedPatterns = {}
        for _, name in ipairs({ "TIME_PLAYED_TOTAL", "TIME_PLAYED_LEVEL" }) do
            local pattern = ns.PatternFromFormat(_G[name])
            if pattern then
                playedPatterns[#playedPatterns + 1] = pattern
            end
        end
        local module = self
        ns.AddChatFilter("CHAT_MSG_SYSTEM", function(_, _, message)
            if module.quietPlayedUntil and GetTime() < module.quietPlayedUntil and type(message) == "string" then
                for _, pattern in ipairs(playedPatterns) do
                    if message:find(pattern) then
                        return true
                    end
                end
            end
            return false
        end)
    end
    self.quietPlayedUntil = GetTime() + 3
    pcall(RequestTimePlayed)
end

function Gold:OnTimePlayed(_, total)
    total = ns.Plain(total)
    if total then
        self.played = total
        self.playedAt = GetTime()
        self:Record()
    end
end

local function FormatPlayed(seconds)
    seconds = tonumber(seconds) or 0
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    if days > 0 then
        return ("%dd %dh"):format(days, hours)
    end
    return ("%dh %02dm"):format(hours, math.floor((seconds % 3600) / 60))
end
ns.FormatPlayed = FormatPlayed

-- /ba alts: every character this account has logged in with BIGARMS
function Gold:ReportCharacters()
    local list = {}
    for _, entry in pairs(ns.db.gold) do
        list[#list + 1] = entry
    end
    table.sort(list, function(a, b) return (a.time or 0) > (b.time or 0) end)
    self:Print(L.ALTS_HEADER)
    for _, entry in ipairs(list) do
        local color = entry.class and ns.ClassColorHex(entry.class) or "ffffff"
        local played = entry.played and FormatPlayed(entry.played + (entry == ns.db.gold[CharacterKey()] and self.playedAt and (GetTime() - self.playedAt) or 0)) or "-"
        self:Print(("  |cff%s%s|r %s %s  %s  %s  %s"):format(color, entry.name or "?", entry.level and ("Lv" .. entry.level) or "",
            entry.realm or "", ns.FormatMoney(entry.copper or 0, true), played, entry.zone or ""))
    end
end

-- /ba session: what happened since login
function Gold:ReportSession()
    local gain, perHour = self:SessionInfo()
    local elapsed = GetTime() - (self.sessionTime or GetTime())
    self:Print(L.SESSION_LINE:format(FormatPlayed(elapsed), ns.FormatMoney(gain), ns.FormatMoney(perHour)))
    local xp = ns:GetModule("XP")
    if xp and xp.enabled and not (IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()) then
        local s = xp:Stats()
        self:Print(L.SESSION_XP:format(s.gained, s.perHour, ns.FormatHours(s.hoursLeft)))
    end
end

function Gold:OnEnable()
    self:RegisterEvent("PLAYER_MONEY", "Record")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Record")
    self:RegisterEvent("PLAYER_LOGOUT", "Record")
    self:RegisterEvent("PLAYER_LEVEL_UP", function(module) module:After(1, module.Record) end)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "Record")
    self:RegisterEvent("TIME_PLAYED_MSG", "OnTimePlayed")
    self:Record()
    self:After(5, self.RequestPlayed)
end

--------------------------------------------------------------------------
-- Experience: XP per hour, time to level, rested, as a movable text line
--------------------------------------------------------------------------

local XP = ns:NewModule("XP", {
    group = "SYSTEM",
    defaults = { enabled = true, text = true, y = -200, chat = false },
    options = {
        { key = "text", type = "toggle", label = "XP_TEXT", tooltip = "XP_TEXT_TT" },
        { key = "y", type = "range", label = "XP_Y", min = -500, max = 500, step = 10, format = "%d" },
        { key = "chat", type = "toggle", label = "XP_CHAT", tooltip = "XP_CHAT_TT" },
        { type = "button", label = "XP_SHOW", button = "SHOW", func = function() ns:GetModule("XP"):Report() end },
    },
})
ns.XP = XP

local xpFrame

function XP:Stats()
    local current = ns.Plain(UnitXP("player")) or 0
    local maximum = ns.Plain(UnitXPMax("player")) or 1
    local rested = ns.Plain(GetXPExhaustion and GetXPExhaustion()) or 0
    local level = ns.Plain(UnitLevel("player")) or 1
    local elapsed = GetTime() - (self.sessionTime or GetTime())
    local gained = self.sessionGained or 0
    local perHour = elapsed > 60 and gained / (elapsed / 3600) or 0
    local remaining = maximum - current
    local hoursLeft = perHour > 0 and remaining / perHour or nil
    return {
        current = current, max = maximum, rested = rested, level = level,
        percent = current / math.max(maximum, 1) * 100, restedPercent = rested / math.max(maximum, 1) * 100,
        perHour = perHour, hoursLeft = hoursLeft, gained = gained,
    }
end

local function FormatHours(hours)
    if not hours then
        return "--"
    end
    if hours < 1 then
        return ("%dm"):format(math.floor(hours * 60 + 0.5))
    end
    return ("%dh %02dm"):format(math.floor(hours), math.floor((hours % 1) * 60))
end
ns.FormatHours = FormatHours

function XP:Report()
    local s = self:Stats()
    if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then
        self:Print(L.XP_MAX_LEVEL)
        return
    end
    self:Print(L.XP_LINE:format(s.level, s.percent, s.restedPercent, s.perHour, FormatHours(s.hoursLeft)))
end

function XP:GetFrame()
    if xpFrame then
        return xpFrame
    end
    xpFrame = CreateFrame("Frame", "BIGARMSXP", UIParent)
    xpFrame:SetSize(360, 16)
    xpFrame:EnableMouse(true)
    xpFrame:SetMovable(true)
    xpFrame:RegisterForDrag("LeftButton")
    xpFrame:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    xpFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, _, y = self:GetPoint(1)
        if y then
            XP.db.y = math.floor(y)
        end
    end)
    xpFrame.text = xpFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xpFrame.text:SetAllPoints()
    xpFrame.text:SetJustifyH("CENTER")
    self:Layout()
    return xpFrame
end

function XP:Layout()
    if xpFrame then
        xpFrame:ClearAllPoints()
        xpFrame:SetPoint("CENTER", UIParent, "CENTER", 0, tonumber(self.db.y) or -200)
    end
end

function XP:UpdateText()
    if not self.db.text or (IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()) then
        if xpFrame then
            xpFrame:Hide()
        end
        return
    end
    local s = self:Stats()
    local frame = self:GetFrame()
    frame:Show()
    local rested = s.rested > 0 and (" |cff6fa8ff+%.0f%%|r"):format(s.restedPercent) or ""
    frame.text:SetText(L.XP_SHORT:format(s.level, s.percent, rested, s.perHour / 1000, FormatHours(s.hoursLeft)))
end

function XP:OnXPUpdate()
    local current = ns.Plain(UnitXP("player")) or 0
    local level = ns.Plain(UnitLevel("player")) or 1
    if self.lastXP then
        local gained
        if level > (self.lastLevel or level) then
            gained = ((self.lastMax or 0) - self.lastXP) + current
        else
            gained = current - self.lastXP
        end
        if gained > 0 then
            self.sessionGained = (self.sessionGained or 0) + gained
            if self.db.chat then
                local s = self:Stats()
                self:Print(L.XP_GAIN:format(gained, s.percent, FormatHours(s.hoursLeft)))
            end
        end
    end
    self.lastXP = current
    self.lastLevel = level
    self.lastMax = ns.Plain(UnitXPMax("player")) or 1
    self:UpdateText()
end

function XP:OnEnable()
    self.sessionTime = self.sessionTime or GetTime()
    self.lastXP = ns.Plain(UnitXP("player")) or 0
    self.lastLevel = ns.Plain(UnitLevel("player")) or 1
    self.lastMax = ns.Plain(UnitXPMax("player")) or 1
    self:RegisterEvent("PLAYER_XP_UPDATE", "OnXPUpdate")
    self:RegisterEvent("PLAYER_LEVEL_UP", function(module) module:After(1, module.OnXPUpdate) end)
    self:RegisterEvent("UPDATE_EXHAUSTION", "UpdateText")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateText")
    self:Ticker(60, self.UpdateText)
    self:UpdateText()
end

function XP:OnDisable()
    if xpFrame then
        xpFrame:Hide()
    end
end

function XP:OnSettingChanged()
    self:Layout()
    self:UpdateText()
end
