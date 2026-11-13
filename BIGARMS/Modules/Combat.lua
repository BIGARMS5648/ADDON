local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Combat alert: "+Combat" / "-Combat" text with a combat timer
--------------------------------------------------------------------------

local CombatAlert = ns:NewModule("CombatAlert", {
    group = "COMBAT",
    defaults = { enabled = true, sound = false, timer = true, size = 24, y = 180 },
    options = {
        { key = "sound", type = "toggle", label = "CA_SOUND" },
        { key = "timer", type = "toggle", label = "CA_TIMER", tooltip = "CA_TIMER_TT" },
        { key = "size", type = "range", label = "CA_SIZE", min = 12, max = 48, step = 2, format = "%d" },
        { key = "y", type = "range", label = "CA_Y", min = -300, max = 400, step = 10, format = "%d" },
    },
})

local alertFrame, timerText

function CombatAlert:GetFrame()
    if alertFrame then
        return alertFrame
    end
    alertFrame = CreateFrame("Frame", "BIGARMSCombatAlert", UIParent)
    alertFrame:SetSize(300, 40)
    alertFrame:SetFrameStrata("HIGH")
    alertFrame.text = alertFrame:CreateFontString(nil, "OVERLAY")
    alertFrame.text:SetPoint("CENTER")
    alertFrame:SetAlpha(0)
    alertFrame.anim = alertFrame:CreateAnimationGroup()
    local fadeIn = alertFrame.anim:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.2)
    fadeIn:SetOrder(1)
    local hold = alertFrame.anim:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(1.2)
    hold:SetOrder(2)
    local fadeOut = alertFrame.anim:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.6)
    fadeOut:SetOrder(3)
    alertFrame.anim:SetScript("OnFinished", function() alertFrame:SetAlpha(0) end)

    local timerHolder = CreateFrame("Frame", "BIGARMSCombatTimer", UIParent)
    timerHolder:SetSize(80, 20)
    timerText = timerHolder:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timerText:SetPoint("CENTER")
    timerText:SetTextColor(1, 0.4, 0.4)
    timerHolder:Hide()
    alertFrame.timerHolder = timerHolder
    self:Layout()
    return alertFrame
end

function CombatAlert:Layout()
    if not alertFrame then
        return
    end
    local y = tonumber(self.db.y) or 180
    alertFrame:ClearAllPoints()
    alertFrame:SetPoint("CENTER", UIParent, "CENTER", 0, y)
    local font = (GameFontNormalHuge and GameFontNormalHuge:GetFont()) or (GameFontNormal and GameFontNormal:GetFont()) or STANDARD_TEXT_FONT
    alertFrame.text:SetFont(font, tonumber(self.db.size) or 24, "OUTLINE")
    alertFrame.timerHolder:ClearAllPoints()
    alertFrame.timerHolder:SetPoint("CENTER", UIParent, "CENTER", 0, y - 30)
end

function CombatAlert:Flash(text, r, g, b)
    local frame = self:GetFrame()
    frame.text:SetText(text)
    frame.text:SetTextColor(r, g, b)
    frame.anim:Stop()
    frame:SetAlpha(0)
    frame.anim:Play()
end

function CombatAlert:OnEnable()
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnEnterCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnLeaveCombat")
end

function CombatAlert:OnEnterCombat()
    self:Flash(L.CA_ENTER, 1, 0.3, 0.3)
    if self.db.sound then
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    end
    self.started = GetTime()
    if self.db.timer then
        local frame = self:GetFrame()
        frame.timerHolder:Show()
        if self.timerTicker then
            self.timerTicker:Cancel()
        end
        self.timerTicker = self:Ticker(1, self.UpdateTimer)
        self:UpdateTimer()
    end
end

function CombatAlert:UpdateTimer()
    if not self.started or not timerText then
        return
    end
    local elapsed = math.floor(GetTime() - self.started)
    timerText:SetText(("%d:%02d"):format(math.floor(elapsed / 60), elapsed % 60))
end

function CombatAlert:OnLeaveCombat()
    local duration = self.started and (GetTime() - self.started) or 0
    self.started = nil
    if self.timerTicker then
        self.timerTicker:Cancel()
        self.timerTicker = nil
    end
    if alertFrame then
        alertFrame.timerHolder:Hide()
    end
    if duration >= 5 and self.db.timer then
        self:Flash(("%s  (%d:%02d)"):format(L.CA_LEAVE, math.floor(duration / 60), math.floor(duration) % 60), 0.4, 1, 0.4)
    else
        self:Flash(L.CA_LEAVE, 0.4, 1, 0.4)
    end
end

function CombatAlert:OnDisable()
    if alertFrame then
        alertFrame.anim:Stop()
        alertFrame:SetAlpha(0)
        alertFrame.timerHolder:Hide()
    end
end

function CombatAlert:OnSettingChanged()
    self:Layout()
end

--------------------------------------------------------------------------
-- Swing timer (main hand / ranged), driven by the client's PLAYER_SWING
-- events. If the client hands us secret durations the bar stays hidden.
--------------------------------------------------------------------------

local SwingTimer = ns:NewModule("SwingTimer", {
    group = "COMBAT",
    defaults = { enabled = false, width = 220, height = 14, y = -160, hideOutOfCombat = true },
    options = {
        { key = "width", type = "range", label = "ST_WIDTH", min = 100, max = 500, step = 10, format = "%d" },
        { key = "height", type = "range", label = "ST_HEIGHT", min = 6, max = 40, step = 2, format = "%d" },
        { key = "y", type = "range", label = "ST_Y", min = -400, max = 400, step = 10, format = "%d" },
        { key = "hideOutOfCombat", type = "toggle", label = "ST_HIDE_OOC" },
        { type = "description", text = "ST_HELP" },
    },
})

local bars = {}

local function SwingColor(swingType)
    if swingType == 1 then
        return 0.5, 0.6, 1
    elseif swingType == 2 then
        return 0.3, 1, 0.5
    end
    return 1, 0.75, 0.2
end

function SwingTimer:GetBar(swingType)
    local bar = bars[swingType]
    if bar then
        return bar
    end
    bar = CreateFrame("StatusBar", nil, UIParent)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(0)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.6)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    bar:SetStatusBarColor(SwingColor(swingType))
    bar:Hide()
    bars[swingType] = bar
    self:Layout()
    return bar
end

function SwingTimer:Layout()
    local width, height = tonumber(self.db.width) or 220, tonumber(self.db.height) or 14
    local y = tonumber(self.db.y) or -160
    local index = 0
    for _, swingType in ipairs({ 0, 1, 2 }) do
        local bar = bars[swingType]
        if bar then
            bar:SetSize(width, height)
            bar:ClearAllPoints()
            bar:SetPoint("CENTER", UIParent, "CENTER", 0, y - index * (height + 2))
            index = index + 1
        end
    end
end

function SwingTimer:OnSwing(_, duration, swingType)
    duration = ns.Plain(duration)
    swingType = ns.Plain(swingType) or 0
    if not duration or duration <= 0 then
        return
    end
    local bar = self:GetBar(swingType)
    bar.start = GetTime()
    bar.duration = duration
    bar:SetMinMaxValues(0, duration)
    bar:Show()
    if not self.ticker then
        self.ticker = self:Ticker(0.03, self.Update)
    end
end

function SwingTimer:Update()
    local now = GetTime()
    local anyShown = false
    for _, bar in pairs(bars) do
        if bar.start then
            local elapsed = now - bar.start
            if elapsed >= bar.duration then
                bar.start = nil
                bar:SetValue(bar.duration)
                bar.text:SetText("")
                if self.db.hideOutOfCombat and not InCombatLockdown() then
                    bar:Hide()
                end
            else
                bar:SetValue(elapsed)
                bar.text:SetText(("%.1f"):format(bar.duration - elapsed))
                anyShown = true
            end
        end
    end
    if not anyShown and self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function SwingTimer:OnEnable()
    if not self:RegisterEvent("PLAYER_SWING", "OnSwing") then
        self:Print(L.ST_UNAVAILABLE)
        return
    end
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function(module)
        if module.db.hideOutOfCombat then
            module:After(2, function()
                for _, bar in pairs(bars) do
                    if not bar.start then
                        bar:Hide()
                    end
                end
            end)
        end
    end)
end

function SwingTimer:OnDisable()
    for _, bar in pairs(bars) do
        bar.start = nil
        bar:Hide()
    end
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
end

function SwingTimer:OnSettingChanged()
    self:Layout()
end

--------------------------------------------------------------------------
-- Buff reminder: icons for self buffs you are missing (out of combat),
-- and a warning when your weapon has no temporary enchant.
--------------------------------------------------------------------------

local BuffReminder = ns:NewModule("BuffReminder", {
    group = "COMBAT",
    defaults = { enabled = true, weapon = false, y = 120, size = 36 },
    options = {
        { key = "weapon", type = "toggle", label = "BR_WEAPON", tooltip = "BR_WEAPON_TT" },
        { key = "size", type = "range", label = "BR_SIZE", min = 20, max = 64, step = 4, format = "%d" },
        { key = "y", type = "range", label = "BR_Y", min = -300, max = 400, step = 10, format = "%d" },
        { type = "description", text = "BR_HELP" },
    },
})
ns.BuffReminder = BuffReminder

local buffFrame

-- Names of the player's current helpful auras, or nil when the client keeps them secret.
function ns.PlayerBuffNames()
    if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then
        return nil
    end
    local names = {}
    local ok = pcall(function()
        if AuraUtil and AuraUtil.ForEachAura then
            AuraUtil.ForEachAura("player", "HELPFUL", nil, function(aura)
                local name = type(aura) == "table" and aura.name or aura
                if type(name) == "string" and not ns.IsSecret(name) then
                    names[name] = true
                end
            end, true)
        elseif C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
            for i = 1, 60 do
                local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not aura then
                    break
                end
                if type(aura.name) == "string" and not ns.IsSecret(aura.name) then
                    names[aura.name] = true
                end
            end
        end
    end)
    if not ok then
        return nil
    end
    return names
end

function BuffReminder:Missing()
    local missing = {}
    local wanted = ns.char.buffs
    if next(wanted) then
        local have = ns.PlayerBuffNames()
        if have then
            for name in pairs(wanted) do
                if not have[name] then
                    missing[#missing + 1] = name
                end
            end
        end
    end
    if self.db.weapon and GetWeaponEnchantInfo then
        local hasMainHand = ns.Plain((GetWeaponEnchantInfo()))
        if hasMainHand == false and GetInventoryItemID and GetInventoryItemID("player", 16) then
            missing[#missing + 1] = L.BR_WEAPON_MISSING
        end
    end
    table.sort(missing)
    return missing
end

function BuffReminder:GetFrame()
    if buffFrame then
        return buffFrame
    end
    buffFrame = CreateFrame("Frame", "BIGARMSBuffReminder", UIParent)
    buffFrame:SetSize(200, 40)
    buffFrame.icons = {}
    return buffFrame
end

function BuffReminder:Icon(i)
    local frame = self:GetFrame()
    local icon = frame.icons[i]
    if not icon then
        icon = CreateFrame("Frame", nil, frame)
        icon.texture = icon:CreateTexture(nil, "ARTWORK")
        icon.texture:SetAllPoints()
        icon.label = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        icon.label:SetPoint("TOP", icon, "BOTTOM", 0, -1)
        frame.icons[i] = icon
    end
    return icon
end

local function SpellIcon(name)
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, name)
        if ok and type(info) == "table" and info.iconID then
            return info.iconID
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

function BuffReminder:Update()
    local frame = self:GetFrame()
    if InCombatLockdown() or (UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")) or (UnitOnTaxi and UnitOnTaxi("player")) then
        frame:Hide()
        return
    end
    local missing = self:Missing()
    if #missing == 0 then
        frame:Hide()
        return
    end
    local size = tonumber(self.db.size) or 36
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, tonumber(self.db.y) or 120)
    frame:SetSize(#missing * (size + 4), size)
    for i, name in ipairs(missing) do
        local icon = self:Icon(i)
        icon:SetSize(size, size)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", frame, "LEFT", (i - 1) * (size + 4), 0)
        icon.texture:SetTexture(name == L.BR_WEAPON_MISSING and "Interface\\Icons\\INV_Sword_04" or SpellIcon(name))
        icon.label:SetText(name)
        icon:Show()
    end
    for i = #missing + 1, #frame.icons do
        frame.icons[i]:Hide()
    end
    frame:Show()
end

function BuffReminder:HandleCommand(args)
    local action, name = args:match("^(%S+)%s*(.*)$")
    action = action and action:lower() or ""
    name = ns.Trim(name or "")
    if (action == "add" or action == "추가") and name ~= "" then
        ns.char.buffs[name] = true
        self:Print(L.BR_ADDED:format(name))
    elseif (action == "del" or action == "remove" or action == "삭제") and name ~= "" then
        ns.char.buffs[name] = nil
        self:Print(L.BR_REMOVED:format(name))
    else
        local names = {}
        for buff in pairs(ns.char.buffs) do
            names[#names + 1] = buff
        end
        table.sort(names)
        self:Print(L.BR_LIST .. " " .. (#names > 0 and table.concat(names, ", ") or "-"))
        self:Print(L.BR_USAGE)
    end
    self:Update()
end

function BuffReminder:OnEnable()
    self:Ticker(3, self.Update)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function(module) module:After(1, module.Update) end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "Update")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function(module) module:After(2, module.Update) end)
    self:Update()
end

function BuffReminder:OnDisable()
    if buffFrame then
        buffFrame:Hide()
    end
end

function BuffReminder:OnSettingChanged()
    self:Update()
end
