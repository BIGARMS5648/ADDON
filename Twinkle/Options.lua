local ADDON, ns = ...
local L, Data = ns.L, ns.Data

local VAR_PREFIX = "TWINKLE_"

-- Settings panel (Esc > Options > AddOns > Twinkle) ------------------------

function ns:CreateOptions()
    if self.settingsCategory or not (Settings and Settings.RegisterVerticalLayoutCategory) then
        return
    end
    local db = self.db
    local defaults = self.DEFAULTS
    local category, layout = Settings.RegisterVerticalLayoutCategory(L.TITLE)
    self.settingsCategory = category

    local function Changed()
        ns:OnSettingsChanged()
    end

    local function Proxy(key, varType, label, default, get, set)
        return Settings.RegisterProxySetting(category, VAR_PREFIX .. key, varType, label, default, get, set)
    end

    -- setting bound to db[key]
    local function Bound(key, varType, label)
        return Proxy(key, varType, label, defaults[key],
            function() return db[key] end,
            function(value)
                db[key] = value
                Changed()
            end)
    end

    local function Checkbox(key, label, tooltip)
        Settings.CreateCheckbox(category, Bound(key, Settings.VarType.Boolean, label), tooltip)
    end

    local function Slider(key, label, tooltip, minValue, maxValue, step, format)
        local setting = Bound(key, Settings.VarType.Number, label)
        local options = Settings.CreateSliderOptions(minValue, maxValue, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return format:format(value)
        end)
        Settings.CreateSlider(category, setting, options, tooltip)
    end

    local function Dropdown(key, varType, label, tooltip, choices)
        local function GetOptions()
            local container = Settings.CreateControlTextContainer()
            for _, choice in ipairs(choices) do
                container:Add(choice[1], choice[2])
            end
            return container:GetData()
        end
        Settings.CreateDropdown(category, Bound(key, varType, label), GetOptions, tooltip)
    end

    local function Header(text)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end

    local function Button(label, buttonText, onClick, tooltip)
        layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
    end

    Checkbox("enabled", L.ENABLE)

    Header(L.HEADER_QUEST)
    Dropdown("questStyle", Settings.VarType.String, L.QUEST_STYLE, L.QUEST_STYLE_TT, {
        { "sparkle", L.QUEST_STYLE_SPARKLE },
        { "outline", L.QUEST_STYLE_OUTLINE },
        { "none", L.QUEST_STYLE_NONE },
    })
    Dropdown("outlineMode", Settings.VarType.Number, L.OUTLINE_MODE, L.OUTLINE_MODE_TT, {
        { 1, L.OUTLINE_MODE_1 },
        { 2, L.OUTLINE_MODE_2 },
        { 3, L.OUTLINE_MODE_3 },
    })

    Header(L.HEADER_NEARBY)
    Checkbox("softEnabled", L.SOFT_ENABLED, L.SOFT_ENABLED_TT)
    for _, cat in ipairs(Data.CATEGORIES) do
        local setting = Proxy("SHOW_" .. cat, Settings.VarType.Boolean, L.SHOW_CATEGORY:format(L["CAT_" .. cat]),
            defaults.show[cat],
            function() return db.show[cat] end,
            function(value)
                db.show[cat] = value
                Changed()
            end)
        Settings.CreateCheckbox(category, setting)
    end
    Slider("range", L.RANGE, L.RANGE_TT, 5, 45, 1, "%d")
    Dropdown("arc", Settings.VarType.Number, L.ARC, L.ARC_TT, {
        { 0, L.ARC_0 },
        { 1, L.ARC_1 },
        { 2, L.ARC_2 },
    })
    Checkbox("radar", L.RADAR, L.RADAR_TT)
    Slider("size", L.SIZE, nil, 32, 160, 4, "%d")
    Slider("offsetY", L.OFFSET, nil, -100, 100, 2, "%d")
    Checkbox("showLabel", L.SHOW_LABEL)
    Checkbox("hud", L.HUD, L.HUD_TT)
    Checkbox("sound", L.SOUND)
    Checkbox("blizzIcon", L.BLIZZ_ICON, L.BLIZZ_ICON_TT)
    Checkbox("questNameMatch", L.QUEST_NAME_MATCH, L.QUEST_NAME_MATCH_TT)

    local minimapSetting = Proxy("minimap", Settings.VarType.Boolean, L.MINIMAP_SHOW, true,
        function() return not db.minimap.hide end,
        function(value)
            db.minimap.hide = not value
            Changed()
        end)
    Settings.CreateCheckbox(category, minimapSetting)

    Button(L.TEST, L.TEST_BUTTON, function() ns:ShowTest() end)
    Button(L.RESTORE, L.RESTORE_BUTTON, function()
        ns:SetEnabled(false)
        Settings.NotifyUpdate(VAR_PREFIX .. "enabled")
        ns.Print(L.RESTORED)
    end, L.RESTORE_TT)

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

local function HandleWatch(args)
    local db = ns.db
    local action, name = args:match("^(%S+)%s*(.*)$")
    action = action and action:lower()
    name = name and Trim(name) or ""
    if (action == "add" or action == "추가") and name ~= "" then
        db.watch[name:lower()] = name
        ns.Print(L.WATCH_ADDED:format(name))
        ns:RefreshAll()
    elseif (action == "del" or action == "remove" or action == "삭제") and name ~= "" then
        db.watch[name:lower()] = nil
        ns.Print(L.WATCH_REMOVED:format(name))
        ns:RefreshAll()
    else
        local names = {}
        for _, display in pairs(db.watch) do
            names[#names + 1] = display
        end
        table.sort(names)
        if #names == 0 then
            ns.Print(L.WATCH_EMPTY)
        else
            ns.Print(L.WATCH_LIST .. " " .. table.concat(names, ", "))
        end
    end
end

local function HandleLearned(args)
    local db = ns.db
    if args:lower() == "clear" then
        wipe(db.learned)
        ns.Print(L.LEARNED_CLEARED)
        return
    end
    local lines = {}
    for name, cat in pairs(db.learned) do
        lines[#lines + 1] = ("%s (%s)"):format(name, L["CAT_" .. cat])
    end
    table.sort(lines)
    ns.Print(L.LEARNED_LIST .. " " .. (#lines > 0 and table.concat(lines, ", ") or "-"))
end

function ns:HandleSlash(msg)
    msg = Trim(msg or "")
    local command, args = msg:match("^(%S*)%s*(.*)$")
    command = (command or ""):lower()
    args = args or ""

    if command == "" or command == "options" or command == "config" or command == "설정" then
        self:OpenOptions()
    elseif command == "on" or command == "켜기" then
        self:SetEnabled(true)
        self.Print(L.ENABLED)
    elseif command == "off" or command == "끄기" then
        self:SetEnabled(false)
        self.Print(L.DISABLED)
    elseif command == "test" or command == "테스트" then
        self:ShowTest()
    elseif command == "minimap" or command == "미니맵" then
        self.MinimapButton:Toggle()
        if Settings.NotifyUpdate and self.settingsCategory then
            Settings.NotifyUpdate(VAR_PREFIX .. "minimap")
        end
    elseif command == "watch" or command == "관심" then
        HandleWatch(args)
    elseif command == "learned" or command == "학습" then
        HandleLearned(args)
    elseif command == "debug" or command == "디버그" then
        if args == "on" then
            self.db.debug = true
            self.Print(L.DEBUG_ON)
        elseif args == "off" then
            self.db.debug = false
            self.Print(L.DEBUG_OFF)
        else
            self:DebugReport()
        end
    else
        for _, line in ipairs(L.HELP) do
            self.Print(line)
        end
    end
end

SLASH_TWINKLE1 = "/tw"
SLASH_TWINKLE2 = "/twinkle"
SLASH_TWINKLE3 = "/반짝"
SlashCmdList.TWINKLE = function(msg)
    ns:HandleSlash(msg)
end
