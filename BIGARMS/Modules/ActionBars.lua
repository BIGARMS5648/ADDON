local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Action bars: hide key / macro text, cooldown numbers, lock, key down
--------------------------------------------------------------------------

local ActionBars = ns:NewModule("ActionBars", {
    group = "INTERFACE",
    needsReload = true,
    defaults = { enabled = true, hideHotkeys = false, hideNames = false, cooldownNumbers = "KEEP", lock = "KEEP", alwaysShow = "KEEP", keyDown = "KEEP", rangeColor = true },
    options = {
        { key = "hideHotkeys", type = "toggle", label = "AB_HIDE_HOTKEYS" },
        { key = "hideNames", type = "toggle", label = "AB_HIDE_NAMES" },
        { key = "rangeColor", type = "toggle", label = "AB_RANGE_COLOR", tooltip = "AB_RANGE_COLOR_TT" },
        { key = "cooldownNumbers", type = "select", label = "AB_COOLDOWN_NUMBERS", tooltip = "AB_COOLDOWN_NUMBERS_TT", cvar = "countdownForCooldowns", choices = "ONOFF" },
        { key = "lock", type = "select", label = "AB_LOCK", cvar = "lockActionBars", choices = "ONOFF" },
        { key = "alwaysShow", type = "select", label = "AB_ALWAYS_SHOW", cvar = "alwaysShowActionBars", choices = "ONOFF" },
        { key = "keyDown", type = "select", label = "SYS_KEYDOWN", tooltip = "SYS_KEYDOWN_TT", cvar = "ActionButtonUseKeyDown", choices = "ONOFF" },
    },
})

local BUTTON_PREFIXES = {
    { "ActionButton", 12 }, { "MultiBarBottomLeftButton", 12 }, { "MultiBarBottomRightButton", 12 },
    { "MultiBarRightButton", 12 }, { "MultiBarLeftButton", 12 }, { "MultiBar5Button", 12 },
    { "MultiBar6Button", 12 }, { "MultiBar7Button", 12 }, { "PetActionButton", 10 }, { "StanceButton", 10 },
}

function ns.ActionButtons()
    local buttons = {}
    for _, entry in ipairs(BUTTON_PREFIXES) do
        for i = 1, entry[2] do
            local button = _G[entry[1] .. i]
            if button then
                buttons[#buttons + 1] = button
            end
        end
    end
    return buttons
end

function ActionBars:ApplyText()
    for _, button in ipairs(ns.ActionButtons()) do
        local hotkey = button.HotKey or _G[button:GetName() .. "HotKey"]
        local name = button.Name or _G[button:GetName() .. "Name"]
        if hotkey and hotkey.SetAlpha then
            hotkey:SetAlpha(self.db.hideHotkeys and 0 or 1)
        end
        if name and name.SetAlpha then
            name:SetAlpha(self.db.hideNames and 0 or 1)
        end
    end
end

-- Out-of-range buttons turn red (the game only tints the hotkey text).
function ActionBars:HookRange()
    if self.rangeHooked or not ActionButton_UpdateRangeIndicator then
        return
    end
    self.rangeHooked = true
    local module = self
    hooksecurefunc("ActionButton_UpdateRangeIndicator", function(button, checksRange, inRange)
        if not module.enabled or not module.db.rangeColor or not button.icon then
            return
        end
        if checksRange and inRange == false then
            button.icon:SetVertexColor(0.9, 0.2, 0.2)
            button.bigarmsRangeTint = true
        elseif button.bigarmsRangeTint then
            button.bigarmsRangeTint = nil
            button.icon:SetVertexColor(1, 1, 1)
        end
    end)
end

function ActionBars:OnEnable()
    self:ApplyText()
    ns.ApplyCVarOptions(self)
    self:HookRange()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function(module) module:After(1, module.ApplyText) end)
end

function ActionBars:OnDisable()
    local hotkeys, names = self.db.hideHotkeys, self.db.hideNames
    self.db.hideHotkeys, self.db.hideNames = false, false
    self:ApplyText()
    self.db.hideHotkeys, self.db.hideNames = hotkeys, names
end

function ActionBars:OnSettingChanged()
    self:ApplyText()
    ns.ApplyCVarOptions(self)
end
