local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Settings panel (Esc > Options > AddOns > BIGARMS)
--
-- One main page with an on/off switch for every module, plus one sub page
-- per group with each module's own options. Controls are generated from
-- the option declarations in the modules.
--------------------------------------------------------------------------

local VAR_PREFIX = "BIGARMS_"

ns.GROUPS = { "AUTOMATION", "CHAT", "TOOLTIP", "MINIMAP", "INTERFACE", "ITEMS", "QUEST", "COMBAT", "MAP", "SYSTEM" }

local function GroupTitle(group)
    return L["GROUP_" .. group] or group
end
ns.GroupTitle = GroupTitle

local function Text(key)
    if key == nil then
        return nil
    end
    return L[key] or key
end

-- "ONOFF" dropdowns share one choice list
local function ChoiceList(option)
    if option.choices == "ONOFF" then
        return { { "KEEP", L.CHOICE_KEEP }, { "ON", L.CHOICE_ON }, { "OFF", L.CHOICE_OFF } }
    elseif type(option.choices) == "function" then
        return option.choices()
    end
    return option.choices or {}
end

local function VarTypeFor(option, default)
    if option.type == "toggle" then
        return Settings.VarType.Boolean
    elseif option.type == "range" then
        return Settings.VarType.Number
    elseif type(default) == "number" then
        return Settings.VarType.Number
    elseif type(default) == "boolean" then
        return Settings.VarType.Boolean
    end
    return Settings.VarType.String
end

-- Text input through a popup, since the Settings API has no text control.
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["BIGARMS_TEXT_INPUT"] = {
    text = "%s",
    button1 = OKAY or "OK",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    editBoxWidth = 260,
    OnShow = function(self, data)
        local editBox = self.editBox or self.EditBox
        if editBox and data then
            editBox:SetText(tostring(data.module.db[data.key] or ""))
            editBox:HighlightText()
        end
    end,
    OnAccept = function(self, data)
        local editBox = self.editBox or self.EditBox
        if editBox and data then
            data.module.db[data.key] = editBox:GetText()
            data.module:SettingChanged(data.key, data.module.db[data.key])
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent.button1 then
            parent.button1:Click()
        end
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns:CreateOptions()
    if self.settingsCategory or not (Settings and Settings.RegisterVerticalLayoutCategory) then
        return
    end
    local mainCategory, mainLayout = Settings.RegisterVerticalLayoutCategory("BIGARMS")
    self.settingsCategory = mainCategory
    self.subCategories = {}

    local function Header(layout, text)
        layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
    end

    local function Button(layout, label, buttonText, onClick, tooltip)
        layout:AddInitializer(CreateSettingsButtonInitializer(label, buttonText, onClick, tooltip, true))
    end

    local enableSettings = {}

    -- the on/off switch of a module, created once and shown on both pages
    local function EnableSetting(module)
        if enableSettings[module.name] then
            return enableSettings[module.name]
        end
        local setting = Settings.RegisterProxySetting(mainCategory, VAR_PREFIX .. module.name .. "_enabled",
            Settings.VarType.Boolean, module:GetTitle(), module.defaults.enabled and true or false,
            function() return module.db.enabled end,
            function(value) ns:SetModuleEnabled(module.name, value) end)
        enableSettings[module.name] = setting
        return setting
    end

    local function AddOption(category, layout, module, option)
        local kind = option.type
        if kind == "header" then
            Header(layout, Text(option.text))
            return
        elseif kind == "description" then
            Header(layout, "|cffaaaaaa" .. (Text(option.text) or "") .. "|r")
            return
        elseif kind == "button" then
            Button(layout, Text(option.label), Text("BUTTON_" .. (option.button or "GO")), function()
                if option.func then
                    ns.SafeCall(option.func, module)
                end
            end, Text(option.tooltip))
            return
        elseif kind == "text" then
            Button(layout, Text(option.label), L.BUTTON_CHANGE, function()
                if StaticPopup_Show then
                    StaticPopup_Show("BIGARMS_TEXT_INPUT", Text(option.label), nil, { module = module, key = option.key })
                end
            end, Text(option.tooltip))
            return
        end
        local default = module.defaults[option.key]
        local setting = Settings.RegisterProxySetting(category, VAR_PREFIX .. module.name .. "_" .. option.key,
            VarTypeFor(option, default), Text(option.label), default,
            function() return module.db[option.key] end,
            function(value)
                module.db[option.key] = value
                module:SettingChanged(option.key, value)
            end)
        if kind == "toggle" then
            Settings.CreateCheckbox(category, setting, Text(option.tooltip))
        elseif kind == "range" then
            local sliderOptions = Settings.CreateSliderOptions(option.min, option.max, option.step)
            local format = option.format or "%d"
            sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
                if format == "%d" or format:find("%%d") then
                    return format:format(math.floor(value + 0.5))
                end
                return format:format(value)
            end)
            Settings.CreateSlider(category, setting, sliderOptions, Text(option.tooltip))
        elseif kind == "select" then
            local function GetOptions()
                local container = Settings.CreateControlTextContainer()
                for _, choice in ipairs(ChoiceList(option)) do
                    container:Add(choice[1], choice[2])
                end
                return container:GetData()
            end
            Settings.CreateDropdown(category, setting, GetOptions, Text(option.tooltip))
        end
    end

    -- main page: every module switch, grouped
    Header(mainLayout, L.OPTIONS_INTRO)
    for _, group in ipairs(ns.GROUPS) do
        local members = {}
        for _, module in ipairs(ns.modules) do
            if module.group == group then
                members[#members + 1] = module
            end
        end
        if #members > 0 then
            Header(mainLayout, GroupTitle(group))
            for _, module in ipairs(members) do
                Settings.CreateCheckbox(mainCategory, EnableSetting(module), module:GetDescription())
            end
        end
    end

    local minimapSetting = Settings.RegisterProxySetting(mainCategory, VAR_PREFIX .. "minimapButton", Settings.VarType.Boolean,
        L.MINIMAP_SHOW, true,
        function() return not ns.db.minimap.hide end,
        function(value)
            ns.db.minimap.hide = not value
            if ns.MinimapButton and ns.MinimapButton.Refresh then
                ns.MinimapButton:Refresh()
            end
        end)
    Header(mainLayout, L.OPTIONS_GENERAL)
    Settings.CreateCheckbox(mainCategory, minimapSetting)
    local debugSetting = Settings.RegisterProxySetting(mainCategory, VAR_PREFIX .. "debug", Settings.VarType.Boolean,
        L.DEBUG, false,
        function() return ns.db.debug end,
        function(value) ns.db.debug = value end)
    Settings.CreateCheckbox(mainCategory, debugSetting, L.DEBUG_TT)
    Button(mainLayout, L.RESET_ALL, L.BUTTON_RESET, function()
        if StaticPopup_Show then
            StaticPopup_Show("BIGARMS_RESET")
        else
            ns:ResetSettings()
        end
    end, L.RESET_ALL_TT)

    -- sub pages
    for _, group in ipairs(ns.GROUPS) do
        local members = {}
        for _, module in ipairs(ns.modules) do
            if module.group == group then
                members[#members + 1] = module
            end
        end
        if #members > 0 and Settings.RegisterVerticalLayoutSubcategory then
            local category, layout = Settings.RegisterVerticalLayoutSubcategory(mainCategory, GroupTitle(group))
            self.subCategories[group] = category
            for _, module in ipairs(members) do
                Header(layout, module:GetTitle())
                Settings.CreateCheckbox(category, EnableSetting(module), module:GetDescription())
                for _, option in ipairs(module.options) do
                    AddOption(category, layout, module, option)
                end
            end
        end
    end

    Settings.RegisterAddOnCategory(mainCategory)
end

StaticPopupDialogs["BIGARMS_RESET"] = {
    text = "BIGARMS",
    button1 = YES or "Yes",
    button2 = NO or "No",
    OnShow = function(self)
        if self.text and self.text.SetText then
            self.text:SetText(L.RESET_CONFIRM)
        end
    end,
    OnAccept = function()
        ns:ResetSettings()
        ns.Print(L.RESET_DONE)
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns:OpenOptions(group)
    if InCombatLockdown() then
        self.Print(L.OPTIONS_IN_COMBAT)
        return
    end
    if not self.settingsCategory then
        self:CreateOptions()
    end
    local category = (group and self.subCategories and self.subCategories[group]) or self.settingsCategory
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
    end
end

-- Tell the settings panel a value changed from a slash command.
function ns:NotifySetting(moduleName, key)
    if Settings and Settings.NotifyUpdate then
        pcall(Settings.NotifyUpdate, VAR_PREFIX .. moduleName .. "_" .. key)
    end
end
