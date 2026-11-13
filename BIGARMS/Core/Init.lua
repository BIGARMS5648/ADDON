local ADDON, ns = ...

--------------------------------------------------------------------------
-- BIGARMS: an all-in-one quality of life suite for WoW Forever.
--
-- Every feature is a module (ns:NewModule). Modules declare their saved
-- settings and option controls, and get a small set of helpers: safe
-- event registration, secure hooks, timers, printing. Module code runs in
-- pcall so one broken feature never takes the rest of the addon down.
--
-- WoW Forever runs the modern (Midnight era) client API on Classic
-- content, so: C_* namespaces, Settings API, secret values in combat, and
-- registering an event the client does not know throws an error.
--------------------------------------------------------------------------

ns.ADDON = ADDON
ns.VERSION = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version")) or "dev"
ns.PREFIX = "|cffff7d0aBIGARMS|r: "

local modules = {} -- ordered list of modules
local modulesByName = {}
ns.modules = modules
ns.modulesByName = modulesByName

local DB_VERSION = 1

-- Defaults for the account-wide saved table (BIGARMSDB).
ns.DB_DEFAULTS = {
    dbVersion = DB_VERSION,
    modules = {}, -- [module name] = settings table
    minimap = { hide = false, angle = 215 },
    positions = {}, -- [frame key] = { point, x, y }
    gold = {}, -- [realm .. " - " .. name] = { copper =, class =, level =, played =, time = }
    auction = {}, -- [itemID] = { price = copper per unit, time = }
    flights = {}, -- ["origin|destination"] = seconds
    nodes = {}, -- gathering nodes: { mapID =, x =, y =, name =, kind =, time = }
    errors = {}, -- caught Lua errors: { message =, count =, time = }
    debug = false,
}

-- Defaults for the per-character saved table (BIGARMSCharDB).
ns.CHAR_DEFAULTS = {
    junkIgnore = {}, -- [itemID] = true, never sell these
    junkSell = {}, -- [itemID] = true, always sell these
    questBlock = {}, -- [questID] = true, never auto-accept
    waypoint = nil, -- { mapID =, x =, y =, title = }
    chatHistory = {},
    buffs = {}, -- buff reminder: [spell name] = true
    recentMail = {}, -- last recipients
    xp = {}, -- session helpers
}

--------------------------------------------------------------------------
-- Small utilities
--------------------------------------------------------------------------

function ns.Print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring((select(i, ...)))
    end
    print(ns.PREFIX .. table.concat(parts, " "))
end

function ns.Printf(fmt, ...)
    ns.Print(fmt:format(...))
end

function ns.Debug(...)
    if ns.db and ns.db.debug then
        ns.Print("|cff999999[debug]|r", ...)
    end
end

-- true when the value is one of the client's combat-restricted secrets
function ns.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value) == true
end

-- A plain copy of a value, or nil when it is secret. Use before doing math
-- or comparisons on anything that came from a unit / aura / cooldown API.
function ns.Plain(value)
    if value == nil or ns.IsSecret(value) then
        return nil
    end
    return value
end

function ns.Trim(text)
    return (tostring(text or ""):match("^%s*(.-)%s*$"))
end

-- Deep-copy defaults into a saved table, keeping anything the player set.
function ns.ApplyDefaults(saved, defaults)
    if type(saved) ~= "table" then
        saved = {}
    end
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            saved[key] = ns.ApplyDefaults(saved[key], value)
        elseif saved[key] == nil then
            saved[key] = value
        end
    end
    return saved
end

function ns.CopyTable(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = type(value) == "table" and ns.CopyTable(value) or value
    end
    return copy
end

-- Walk a dotted path of fields starting from a global ("PlayerFrame.healthbar").
function ns.Resolve(path)
    local current = _G
    for field in path:gmatch("[^%.]+") do
        if type(current) ~= "table" then
            return nil
        end
        current = rawget(current, field) or current[field]
        if current == nil then
            return nil
        end
    end
    return current
end

-- First of several dotted paths that resolves to a value.
function ns.FirstFrame(...)
    for i = 1, select("#", ...) do
        local frame = ns.Resolve((select(i, ...)))
        if frame then
            return frame
        end
    end
end

-- Run a function right away and swallow errors (printed in debug mode).
function ns.SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        ns.Debug("error:", err)
    end
    return ok, err
end

function ns.After(delay, fn)
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, fn)
    else
        fn()
    end
end

-- A repeating ticker; returns an object with :Cancel().
function ns.NewTicker(interval, fn, iterations)
    if C_Timer and C_Timer.NewTicker then
        return C_Timer.NewTicker(interval, fn, iterations)
    end
    return { Cancel = function() end }
end

-- Secure post-hook with existence checks. Works for globals ("Name") and
-- methods (table, "Name").
function ns.SecureHook(target, method, fn)
    if not hooksecurefunc then
        return false
    end
    if fn == nil then
        if type(_G[target]) ~= "function" then
            return false
        end
        hooksecurefunc(target, method)
        return true
    end
    if type(target) ~= "table" or type(target[method]) ~= "function" then
        return false
    end
    hooksecurefunc(target, method, fn)
    return true
end

-- Does the client know this event? (Registering an unknown one throws.)
function ns.IsEventValid(event)
    if C_EventUtils and C_EventUtils.IsEventValid then
        return C_EventUtils.IsEventValid(event) == true
    end
    return true
end

-- Register an event on a frame without ever throwing.
function ns.TryRegisterEvent(frame, event, unit)
    if not ns.IsEventValid(event) then
        return false
    end
    local ok
    if unit then
        ok = pcall(frame.RegisterUnitEvent, frame, event, unit)
    else
        ok = pcall(frame.RegisterEvent, frame, event)
    end
    return ok == true
end

function ns.GetCVar(name)
    if C_CVar and C_CVar.GetCVar then
        return C_CVar.GetCVar(name)
    end
end

function ns.CVarExists(name)
    return ns.GetCVar(name) ~= nil
end

function ns.SetCVar(name, value)
    if not ns.CVarExists(name) then
        return false
    end
    local ok, result = pcall(C_CVar.SetCVar, name, tostring(value))
    return ok and result ~= false
end

function ns.GetCVarBool(name)
    local value = ns.GetCVar(name)
    return value == "1" or value == "true"
end

-- Money -------------------------------------------------------------------

local GOLD_ICON = "|cffffd700%d|r"
local SILVER_ICON = "|cffc7c7cf%d|r"
local COPPER_ICON = "|cffeda55f%d|r"

-- "12g 34s 56c" style with the usual colors; short drops zero parts.
function ns.FormatMoney(copper, short)
    copper = tonumber(copper) or 0
    local negative = copper < 0
    copper = math.abs(math.floor(copper))
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local bronze = copper % 100
    local parts = {}
    local L = ns.L
    if gold > 0 then
        parts[#parts + 1] = GOLD_ICON:format(gold) .. L.GOLD_SHORT
    end
    if silver > 0 or (not short and gold > 0) then
        parts[#parts + 1] = SILVER_ICON:format(silver) .. L.SILVER_SHORT
    end
    if bronze > 0 or #parts == 0 or not short then
        parts[#parts + 1] = COPPER_ICON:format(bronze) .. L.COPPER_SHORT
    end
    return (negative and "-" or "") .. table.concat(parts, " ")
end

-- Colors ------------------------------------------------------------------

local FALLBACK_CLASS_COLORS = {
    WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
    ROGUE = { 1.00, 0.96, 0.41 }, PRIEST = { 1.00, 1.00, 1.00 }, SHAMAN = { 0.00, 0.44, 0.87 },
    MAGE = { 0.25, 0.78, 0.92 }, WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1.00, 0.49, 0.04 },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 }, MONK = { 0.00, 1.00, 0.59 }, DEMONHUNTER = { 0.64, 0.19, 0.79 },
    EVOKER = { 0.20, 0.58, 0.50 },
}

function ns.ClassColor(classToken)
    local colors = (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)
    local color = colors and classToken and colors[classToken]
    if color then
        return color.r, color.g, color.b
    end
    local fallback = FALLBACK_CLASS_COLORS[classToken]
    if fallback then
        return fallback[1], fallback[2], fallback[3]
    end
    return 1, 1, 1
end

function ns.ClassColorHex(classToken)
    local r, g, b = ns.ClassColor(classToken)
    return ("%02x%02x%02x"):format(r * 255, g * 255, b * 255)
end

-- Reaction color for a unit (green friendly, yellow neutral, red hostile).
function ns.ReactionColor(unit)
    local reaction = UnitReaction and UnitReaction(unit, "player")
    reaction = ns.Plain(reaction)
    if not reaction then
        return 1, 1, 1
    end
    if reaction >= 5 then
        return 0.1, 0.9, 0.1
    elseif reaction == 4 then
        return 1, 0.9, 0.1
    end
    return 0.9, 0.15, 0.15
end

function ns.UnitColor(unit)
    if UnitIsPlayer and UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if class and not ns.IsSecret(class) then
            return ns.ClassColor(class)
        end
    end
    return ns.ReactionColor(unit)
end

-- Turn a Blizzard format string ("%s has come online.") into a Lua pattern
-- with captures, so localized system messages can be parsed.
function ns.PatternFromFormat(format)
    if type(format) ~= "string" then
        return nil
    end
    local pattern = format:gsub("%%%d?%$?([sd])", "\1%1") -- mark %s / %d / %1$s
    pattern = pattern:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
    pattern = pattern:gsub("\1s", "(.-)"):gsub("\1d", "(%%d+)")
    return "^" .. pattern .. "$"
end

-- Does another addon already own this slash command ("/pull")?
function ns.IsSlashTaken(command)
    command = command:lower()
    for key, value in pairs(_G) do
        if type(key) == "string" and type(value) == "string" and key:find("^SLASH_") and value:lower() == command then
            return true
        end
    end
    return false
end

-- Apply one "cvar" option of a module: "ONOFF" selects write 1/0 unless KEEP,
-- ranges write their value unless negative.
function ns.ApplyCVarOption(module, option)
    if not option.cvar then
        return
    end
    local value = module.db[option.key]
    if option.choices == "ONOFF" then
        if value == "ON" then
            ns.SetCVar(option.cvar, 1)
        elseif value == "OFF" then
            ns.SetCVar(option.cvar, 0)
        end
    elseif option.type == "range" then
        value = tonumber(value) or -1
        if value >= 0 then
            ns.SetCVar(option.cvar, value)
        end
    end
end

function ns.ApplyCVarOptions(module)
    for _, option in ipairs(module.options) do
        ns.ApplyCVarOption(module, option)
    end
end

-- Strip "-Realm" from a character name.
function ns.ShortName(name)
    if type(name) ~= "string" then
        return name
    end
    return (name:match("^([^%-]+)")) or name
end

function ns.IsMe(name)
    local me = UnitName("player")
    return name ~= nil and me ~= nil and ns.ShortName(name) == me
end

-- Group chat channel for announcements, nil when solo.
function ns.GroupChannel()
    if not (IsInGroup and IsInGroup()) then
        return nil
    end
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then
        return "INSTANCE_CHAT"
    end
    if IsInRaid and IsInRaid() then
        return "RAID"
    end
    return "PARTY"
end

-- Is this guid / name one of my friends or guild mates?
function ns.IsFriendOrGuild(name, guid)
    if guid and C_FriendList and C_FriendList.IsFriend and C_FriendList.IsFriend(guid) then
        return true
    end
    if guid and IsGuildMember and IsGuildMember(guid) then
        return true
    end
    if guid and C_BattleNet and C_BattleNet.GetGameAccountInfoByGUID then
        local info = C_BattleNet.GetGameAccountInfoByGUID(guid)
        if info then
            return true
        end
    end
    if name and C_FriendList and C_FriendList.GetFriendInfo then
        local short = name:match("^([^%-]+)")
        if C_FriendList.GetFriendInfo(name) or (short and C_FriendList.GetFriendInfo(short)) then
            return true
        end
    end
    if name and IsInGuild and IsInGuild() and GetNumGuildMembers then
        local short = (name:match("^([^%-]+)") or name):lower()
        for i = 1, GetNumGuildMembers() do
            local member = GetGuildRosterInfo(i)
            if member and (member:match("^([^%-]+)") or member):lower() == short then
                return true
            end
        end
    end
    return false
end

-- Is the player holding the configured modifier key? ("SHIFT"/"CTRL"/"ALT"/"NONE")
function ns.IsModifierDown(which)
    if which == "SHIFT" then
        return IsShiftKeyDown()
    elseif which == "CTRL" then
        return IsControlKeyDown()
    elseif which == "ALT" then
        return IsAltKeyDown()
    end
    return false
end

ns.MODIFIER_CHOICES = function()
    local L = ns.L
    return {
        { "SHIFT", L.KEY_SHIFT },
        { "CTRL", L.KEY_CTRL },
        { "ALT", L.KEY_ALT },
        { "NONE", L.KEY_NONE },
    }
end

--------------------------------------------------------------------------
-- Combat-safe deferral
--------------------------------------------------------------------------

local afterCombat = {}

function ns.RunOutOfCombat(fn)
    if InCombatLockdown() then
        afterCombat[#afterCombat + 1] = fn
        return false
    end
    fn()
    return true
end

--------------------------------------------------------------------------
-- Module system
--------------------------------------------------------------------------

local Module = {}
Module.__index = Module

local eventFrame = CreateFrame("Frame")
local eventHandlers = {} -- [event] = { [module] = handler }
ns.eventFrame = eventFrame

local function DispatchEvent(_, event, ...)
    if event == "PLAYER_REGEN_ENABLED" and #afterCombat > 0 then
        local queue = afterCombat
        afterCombat = {}
        for _, fn in ipairs(queue) do
            ns.SafeCall(fn)
        end
    end
    local handlers = eventHandlers[event]
    if not handlers then
        return
    end
    for module, handler in pairs(handlers) do
        if module.enabled then
            local ok, err = pcall(handler, module, event, ...)
            if not ok then
                module:ReportError(err)
            end
        end
    end
end
eventFrame:SetScript("OnEvent", DispatchEvent)
ns.TryRegisterEvent(eventFrame, "PLAYER_REGEN_ENABLED")

function ns:NewModule(name, info)
    assert(modulesByName[name] == nil, "duplicate module " .. name)
    local defaults = info.defaults or {}
    if defaults.enabled == nil then
        defaults.enabled = true
    end
    local module = setmetatable({
        name = name,
        group = info.group or "MISC",
        defaults = defaults,
        options = info.options or {},
        enabled = false,
        needsReload = info.needsReload or false,
        order = #modules + 1,
        events = {},
        tickers = {},
        errors = {},
    }, Module)
    modules[#modules + 1] = module
    modulesByName[name] = module
    return module
end

function Module:GetTitle()
    return ns.L["MOD_" .. self.name] or self.name
end

function Module:GetDescription()
    return ns.L["MOD_" .. self.name .. "_DESC"]
end

function Module:IsEnabled()
    return self.enabled
end

function Module:Print(...)
    ns.Print(...)
end

function Module:ReportError(err)
    local text = tostring(err)
    if not self.errors[text] then
        self.errors[text] = true
        ns.Print(("|cffff4040%s|r %s"):format(self:GetTitle(), text))
    end
end

-- handler may be a function or the name of a method on the module
function Module:RegisterEvent(event, handler, unit)
    handler = handler or "OnEvent"
    if type(handler) == "string" then
        local method = handler
        handler = function(module, ...)
            return module[method](module, ...)
        end
    end
    if not eventHandlers[event] then
        if not ns.TryRegisterEvent(eventFrame, event, unit) then
            ns.Debug("unknown event", event, "(" .. self.name .. ")")
            return false
        end
        eventHandlers[event] = {}
    end
    eventHandlers[event][self] = handler
    self.events[event] = true
    return true
end

function Module:UnregisterEvent(event)
    if eventHandlers[event] then
        eventHandlers[event][self] = nil
    end
    self.events[event] = nil
end

function Module:UnregisterAllEvents()
    for event in pairs(self.events) do
        self:UnregisterEvent(event)
    end
end

-- Ticker that is cancelled when the module is disabled.
function Module:Ticker(interval, fn, iterations)
    local module = self
    local ticker = ns.NewTicker(interval, function(...)
        if module.enabled then
            local ok, err = pcall(fn, module, ...)
            if not ok then
                module:ReportError(err)
            end
        end
    end, iterations)
    self.tickers[#self.tickers + 1] = ticker
    return ticker
end

function Module:CancelTickers()
    local cancelled = {}
    for _, ticker in ipairs(self.tickers) do
        ticker:Cancel()
        cancelled[ticker] = true
    end
    self.tickers = {}
    -- forget handles the module kept ("self.ticker"), so a re-enable starts fresh
    for key, value in pairs(self) do
        if cancelled[value] then
            self[key] = nil
        end
    end
end

-- Secure hook that only runs while the module is enabled. Hooks can never
-- be removed, so this is how a disabled module steps aside.
function Module:SecureHook(target, method, fn)
    local module = self
    if fn == nil then
        -- (globalName, fn)
        target, method, fn = target, nil, method
    end
    local function wrapper(...)
        if module.enabled then
            local ok, err = pcall(fn, module, ...)
            if not ok then
                module:ReportError(err)
            end
        end
    end
    if method == nil then
        return ns.SecureHook(target, wrapper)
    end
    return ns.SecureHook(target, method, wrapper)
end

-- HookScript that only runs while the module is enabled.
function Module:HookScript(frame, script, fn)
    if not frame or not frame.HookScript then
        return false
    end
    local module = self
    frame:HookScript(script, function(...)
        if module.enabled then
            local ok, err = pcall(fn, module, ...)
            if not ok then
                module:ReportError(err)
            end
        end
    end)
    return true
end

function Module:After(delay, fn)
    local module = self
    ns.After(delay, function()
        if module.enabled then
            local ok, err = pcall(fn, module)
            if not ok then
                module:ReportError(err)
            end
        end
    end)
end

-- Called by the options panel when a value changed.
function Module:SettingChanged(key, value)
    if self.OnSettingChanged and self.enabled then
        local ok, err = pcall(self.OnSettingChanged, self, key, value)
        if not ok then
            self:ReportError(err)
        end
    end
end

function Module:Enable()
    if self.enabled then
        return
    end
    self.enabled = true
    if self.OnEnable then
        local ok, err = pcall(self.OnEnable, self)
        if not ok then
            self:ReportError(err)
        end
    end
end

function Module:Disable()
    if not self.enabled then
        return
    end
    self.enabled = false
    self:UnregisterAllEvents()
    self:CancelTickers()
    if self.OnDisable then
        local ok, err = pcall(self.OnDisable, self)
        if not ok then
            self:ReportError(err)
        end
    end
end

function ns:GetModule(name)
    return modulesByName[name]
end

function ns:SetModuleEnabled(name, enabled)
    local module = modulesByName[name]
    if not module then
        return false
    end
    module.db.enabled = enabled and true or false
    ns.RunOutOfCombat(function()
        if module.db.enabled then
            module:Enable()
        else
            module:Disable()
            if module.needsReload then
                ns.Print(ns.L.NEEDS_RELOAD:format(module:GetTitle()))
            end
        end
    end)
    return true
end

--------------------------------------------------------------------------
-- Keybindings (Bindings.xml)
--------------------------------------------------------------------------

BINDING_HEADER_BIGARMS = "BIGARMS"
BINDING_NAME_BIGARMS_OPTIONS = ns.L.BIND_OPTIONS
BINDING_NAME_BIGARMS_CHATCOPY = ns.L.BIND_CHATCOPY
BINDING_NAME_BIGARMS_PULL = ns.L.BIND_PULL
BINDING_NAME_BIGARMS_WAYCLEAR = ns.L.BIND_WAYCLEAR
BINDING_NAME_BIGARMS_ERRORS = ns.L.BIND_ERRORS
BINDING_NAME_BIGARMS_MINIMAP = ns.L.BIND_MINIMAP

function BIGARMS_Keybind(action)
    if action == "options" then
        ns:OpenOptions()
    elseif action == "chatcopy" and ns.ShowChatCopy then
        ns.ShowChatCopy()
    elseif action == "pull" and ns.HandleSlash then
        ns:HandleSlash("pull")
    elseif action == "wayclear" and ns.HandleSlash then
        ns:HandleSlash("way clear")
    elseif action == "errors" and ns.HandleSlash then
        ns:HandleSlash("errors")
    elseif action == "minimap" and ns.HandleSlash then
        ns:HandleSlash("minimap")
    end
end

--------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------

local function LoadDatabase()
    BIGARMSDB = ns.ApplyDefaults(BIGARMSDB, ns.DB_DEFAULTS)
    BIGARMSCharDB = ns.ApplyDefaults(BIGARMSCharDB, ns.CHAR_DEFAULTS)
    ns.db = BIGARMSDB
    ns.char = BIGARMSCharDB
    if ns.Migrate then
        ns.Migrate(ns.db, ns.char)
    end
    ns.db.dbVersion = DB_VERSION
    for _, module in ipairs(modules) do
        ns.db.modules[module.name] = ns.ApplyDefaults(ns.db.modules[module.name], module.defaults)
        module.db = ns.db.modules[module.name]
    end
end

function ns:ResetSettings()
    for _, module in ipairs(modules) do
        module:Disable()
    end
    wipe(ns.db.modules)
    ns.db.positions = {}
    for _, module in ipairs(modules) do
        ns.db.modules[module.name] = ns.ApplyDefaults({}, module.defaults)
        module.db = ns.db.modules[module.name]
    end
    for _, module in ipairs(modules) do
        if module.db.enabled then
            module:Enable()
        end
    end
end

local booted = false
local function Boot()
    if booted then
        return
    end
    booted = true
    for _, module in ipairs(modules) do
        if module.db.enabled then
            module:Enable()
        end
    end
    if ns.CreateOptions then
        ns.SafeCall(ns.CreateOptions, ns)
    end
    if ns.MinimapButton and ns.MinimapButton.Create then
        ns.SafeCall(ns.MinimapButton.Create, ns.MinimapButton)
    end
    ns.Print(ns.L.LOADED)
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        LoadDatabase()
        self:UnregisterEvent("ADDON_LOADED")
        if IsLoggedIn and IsLoggedIn() then
            Boot()
        end
    elseif event == "PLAYER_LOGIN" then
        if not ns.db then
            LoadDatabase()
        end
        Boot()
    end
end)
