local ADDON, ns = ...
local L = ns.L

local VAR_PREFIX = "PODIUM_"

-- Settings panel (Esc > Options > AddOns > Podium) --------------------------

function ns:CreateOptions()
    if self.settingsCategory or not (Settings and Settings.RegisterVerticalLayoutCategory) then
        return
    end
    local db = self.db
    local defaults = self.DEFAULTS
    local category, layout = Settings.RegisterVerticalLayoutCategory(L.TITLE)
    self.settingsCategory = category

    local function Bound(key, varType, label)
        return Settings.RegisterProxySetting(category, VAR_PREFIX .. key, varType, label, defaults[key],
            function() return db[key] end,
            function(value) db[key] = value end)
    end

    local function Checkbox(key, label, tooltip)
        Settings.CreateCheckbox(category, Bound(key, Settings.VarType.Boolean, label), tooltip)
    end

    local function Slider(key, label, tooltip, minValue, maxValue, step, formatter)
        local options = Settings.CreateSliderOptions(minValue, maxValue, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, formatter)
        Settings.CreateSlider(category, Bound(key, Settings.VarType.Number, label), options, tooltip)
    end

    local function Header(text)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end

    local function Button(label, buttonText, onClick, tooltip)
        layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
    end

    Checkbox("enabled", L.ENABLE)

    Header(L.HEADER_WHEN)
    Checkbox("onLeave", L.ON_LEAVE, L.ON_LEAVE_TT)
    Checkbox("raids", L.RAIDS)

    Header(L.HEADER_LOOK)
    Checkbox("models", L.MODELS, L.MODELS_TT)
    Slider("modelSize", L.MODEL_SIZE, nil, 80, 120, 5, function(value)
        return ("%d%%"):format(value)
    end)
    Slider("modelOffset", L.MODEL_OFFSET, L.MODEL_OFFSET_TT, -40, 40, 2, function(value)
        return ("%+d"):format(value)
    end)
    Checkbox("confetti", L.CONFETTI)
    Checkbox("dim", L.DIM)
    Checkbox("sound", L.SOUND)
    Checkbox("fun", L.FUN)
    Checkbox("hideInCombat", L.HIDE_IN_COMBAT)
    Slider("autoClose", L.AUTO_CLOSE_OPT, L.AUTO_CLOSE_TT, 0, 180, 5, function(value)
        return value == 0 and L.NEVER or L.SECONDS:format(value)
    end)
    Slider("scale", L.SCALE, nil, 60, 140, 5, function(value)
        return ("%d%%"):format(value)
    end)

    Button(L.TEST, L.TEST_BUTTON, function() ns:ShowDemo() end)
    Button(L.LAST, L.LAST_BUTTON, function() ns:ShowLast() end)

    Settings.RegisterAddOnCategory(category)
end

function ns:OpenOptions()
    if InCombatLockdown() then
        self.Print(L.OPTIONS_IN_COMBAT)
        return
    end
    if self.settingsCategory then
        Settings.OpenToCategory(self.settingsCategory:GetID())
    end
end

-- Slash commands -------------------------------------------------------------

local function Trim(text)
    return (text:match("^%s*(.-)%s*$"))
end

local function ListHistory()
    local runs = ns:Runs()
    if #runs == 0 then
        ns.Print(L.HISTORY_EMPTY)
        return
    end
    ns.Print(L.HISTORY)
    for i, run in ipairs(runs) do
        local report = ns.Awards.Build(run, { kind = run.complete and "clear" or "partial" })
        local mvp = report and report.mvp and ns.Awards.ShortName(report.mvp.name) or "-"
        local when = date and date("%m/%d %H:%M", run.started or 0) or ""
        ns.Print(L.HISTORY_LINE:format(i, when, run.instance or L.UNKNOWN, mvp))
    end
end

function ns:HandleSlash(msg)
    msg = Trim(msg or "")
    local command, args = msg:match("^(%S*)%s*(.*)$")
    command = (command or ""):lower()
    args = Trim(args or "")

    if command == "" or command == "show" or command == "last" or command == "보기" then
        self:ShowLast()
    elseif command == "test" or command == "demo" or command == "테스트" or command == "미리보기" then
        self:ShowDemo()
    elseif command == "options" or command == "config" or command == "설정" then
        self:OpenOptions()
    elseif command == "history" or command == "기록" then
        local index = tonumber(args)
        if index then
            self:ShowLast(index)
        elseif args == "clear" or args == "지우기" then
            wipe(self.db.history)
            self.Print(L.HISTORY_CLEARED)
        else
            ListHistory()
        end
    elseif command == "share" or command == "공유" then
        ns.Ceremony:Share()
    elseif command == "on" or command == "켜기" then
        self:SetEnabled(true)
        self.Print(L.ENABLED)
    elseif command == "off" or command == "끄기" then
        self:SetEnabled(false)
        self.Print(L.DISABLED)
    elseif command == "debug" or command == "디버그" then
        if args == "on" then
            self.db.debug = true
        elseif args == "off" then
            self.db.debug = false
        end
        self:DebugReport()
    else
        for _, line in ipairs(L.HELP) do
            self.Print(line)
        end
    end
end

SLASH_PODIUM1 = "/mvp"
SLASH_PODIUM2 = "/podium"
SLASH_PODIUM3 = "/시상식"
SlashCmdList.PODIUM = function(msg)
    ns:HandleSlash(msg)
end

-- Addon compartment (the addon list button by the minimap) ------------------

function Podium_OnAddonCompartmentClick(_, mouseButton)
    if mouseButton == "RightButton" then
        ns:OpenOptions()
    else
        ns:ShowLast()
    end
end

function Podium_OnAddonCompartmentEnter(_, menuButtonFrame)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(menuButtonFrame or UIParent, "ANCHOR_LEFT")
    GameTooltip:SetText(L.TITLE)
    GameTooltip:AddLine(ns.db and ns.db.enabled and L.STATUS_ON or L.STATUS_OFF)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.COMPARTMENT_LEFT, 1, 1, 1)
    GameTooltip:AddLine(L.COMPARTMENT_RIGHT, 1, 1, 1)
    GameTooltip:Show()
end

function Podium_OnAddonCompartmentLeave()
    if GameTooltip then
        GameTooltip:Hide()
    end
end
