local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Interface tweaks: hide clutter, filter error spam, camera, unit frames
--------------------------------------------------------------------------

local UI = ns:NewModule("Interface", {
    group = "INTERFACE",
    needsReload = true,
    defaults = {
        enabled = true,
        hideGryphons = false,
        errorFilter = true,
        hideZoneText = false,
        classColorFrames = true,
        hideHitIndicator = false,
        statusText = "KEEP", -- KEEP | NONE | NUMERIC | PERCENT | BOTH
        maxZoom = 2.6,
        actionCam = "KEEP", -- KEEP | OFF | BASIC | FULL
        questSparkle = true,
    },
    options = {
        { key = "hideGryphons", type = "toggle", label = "UI_GRYPHONS" },
        { key = "errorFilter", type = "toggle", label = "UI_ERROR_FILTER", tooltip = "UI_ERROR_FILTER_TT" },
        { key = "hideZoneText", type = "toggle", label = "UI_ZONE_TEXT", tooltip = "UI_ZONE_TEXT_TT" },
        { key = "classColorFrames", type = "toggle", label = "UI_CLASS_FRAMES", tooltip = "UI_CLASS_FRAMES_TT" },
        { key = "hideHitIndicator", type = "toggle", label = "UI_HIT_INDICATOR" },
        { key = "statusText", type = "select", label = "UI_STATUS_TEXT", tooltip = "UI_STATUS_TEXT_TT", choices = function()
            return {
                { "KEEP", L.CHOICE_KEEP }, { "NONE", L.CHOICE_OFF }, { "NUMERIC", L.UI_STATUS_NUMERIC },
                { "PERCENT", L.UI_STATUS_PERCENT }, { "BOTH", L.UI_STATUS_BOTH },
            }
        end },
        { key = "maxZoom", type = "range", label = "UI_MAX_ZOOM", tooltip = "UI_MAX_ZOOM_TT", min = 1, max = 4, step = 0.1, format = "%.1f" },
        { key = "actionCam", type = "select", label = "UI_ACTIONCAM", tooltip = "UI_ACTIONCAM_TT", choices = function()
            return { { "KEEP", L.CHOICE_KEEP }, { "OFF", L.CHOICE_OFF }, { "BASIC", L.UI_ACTIONCAM_BASIC }, { "FULL", L.UI_ACTIONCAM_FULL } }
        end },
        { key = "questSparkle", type = "toggle", label = "UI_QUEST_SPARKLE", tooltip = "UI_QUEST_SPARKLE_TT" },
    },
})

-- Gryphons --------------------------------------------------------------------

function UI:ApplyGryphons()
    local hide = self.db.hideGryphons
    for _, path in ipairs({ "MainMenuBar.EndCaps", "MainMenuBarArtFrame.LeftEndCap", "MainMenuBarArtFrame.RightEndCap", "MainMenuBar.ArtFrame.LeftEndCap", "MainMenuBar.ArtFrame.RightEndCap" }) do
        local frame = ns.Resolve(path)
        if frame and frame.SetAlpha then
            frame:SetAlpha(hide and 0 or 1)
        end
    end
end

-- Error message filter ---------------------------------------------------------

-- Messages that are noise in combat. Compared against the localized globals
-- so this works in every language.
local SPAM_GLOBALS = {
    "ERR_ABILITY_COOLDOWN", "ERR_SPELL_COOLDOWN", "ERR_ITEM_COOLDOWN", "ERR_OUT_OF_ENERGY", "ERR_OUT_OF_RAGE",
    "ERR_OUT_OF_MANA", "ERR_OUT_OF_FOCUS", "ERR_OUT_OF_RANGE", "ERR_BADATTACKFACING", "ERR_BADATTACKPOS",
    "ERR_NO_ATTACK_TARGET", "ERR_INVALID_ATTACK_TARGET", "ERR_SPELL_FAILED_ANOTHER_IN_PROGRESS",
    "SPELL_FAILED_SPELL_IN_PROGRESS", "SPELL_FAILED_NOT_READY", "SPELL_FAILED_NO_COMBO_POINTS",
    "SPELL_FAILED_TARGET_AURASTATE", "SPELL_FAILED_CASTER_AURASTATE", "SPELL_FAILED_BAD_TARGETS",
    "SPELL_FAILED_UNIT_NOT_INFRONT", "SPELL_FAILED_OUT_OF_RANGE", "SPELL_FAILED_TOO_CLOSE", "SPELL_FAILED_MOVING",
    "ERR_GENERIC_NO_TARGET", "ERR_NOEMOTEWHILERUNNING", "ERR_ATTACK_CHARMED", "ERR_ATTACK_CONFUSED",
    "ERR_ATTACK_DEAD", "ERR_ATTACK_FLEEING", "ERR_ATTACK_PACIFIED", "ERR_ATTACK_STUNNED",
    "SPELL_FAILED_NOT_BEHIND", "SPELL_FAILED_LINE_OF_SIGHT", "ERR_NOT_IN_COMBAT", "ERR_ITEM_LOCKED",
}

local spamMessages

local function BuildSpam()
    spamMessages = {}
    for _, name in ipairs(SPAM_GLOBALS) do
        local text = _G[name]
        if type(text) == "string" and text ~= "" then
            spamMessages[text] = true
        end
    end
end

function ns.IsErrorSpam(message)
    if not spamMessages then
        BuildSpam()
    end
    return type(message) == "string" and spamMessages[message] == true
end

function UI:ApplyErrorFilter()
    if not UIErrorsFrame then
        return
    end
    if self.db.errorFilter then
        if not self.errorsTaken then
            self.errorsTaken = true
            UIErrorsFrame:UnregisterEvent("UI_ERROR_MESSAGE")
            self:RegisterEvent("UI_ERROR_MESSAGE", "OnErrorMessage")
        end
    elseif self.errorsTaken then
        self.errorsTaken = nil
        self:UnregisterEvent("UI_ERROR_MESSAGE")
        ns.TryRegisterEvent(UIErrorsFrame, "UI_ERROR_MESSAGE")
    end
end

function UI:OnErrorMessage(_, errorType, message, voiceID, soundKitID)
    if ns.IsErrorSpam(message) then
        return
    end
    if UIErrorsFrame.TryDisplayMessage then
        UIErrorsFrame:TryDisplayMessage(errorType, message, 1, 0.1, 0.1, voiceID, soundKitID)
    else
        UIErrorsFrame:AddMessage(message, 1, 0.1, 0.1, 1)
    end
end

-- Zone text ---------------------------------------------------------------------

function UI:ApplyZoneText()
    for _, name in ipairs({ "ZoneTextFrame", "SubZoneTextFrame" }) do
        local frame = _G[name]
        if frame then
            if self.db.hideZoneText then
                frame:UnregisterAllEvents()
                frame.bigarmsMuted = true
            elseif frame.bigarmsMuted then
                frame.bigarmsMuted = nil
                ns.TryRegisterEvent(frame, "ZONE_CHANGED")
                ns.TryRegisterEvent(frame, "ZONE_CHANGED_INDOORS")
                ns.TryRegisterEvent(frame, "ZONE_CHANGED_NEW_AREA")
            end
        end
    end
end

-- Class colored unit frames ----------------------------------------------------------

local UNIT_BARS = {
    { unit = "player", paths = { "PlayerFrame.healthbar", "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar", "PlayerFrameHealthBar" } },
    { unit = "target", paths = { "TargetFrame.healthbar", "TargetFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar", "TargetFrameHealthBar" } },
    { unit = "focus", paths = { "FocusFrame.healthbar", "FocusFrame.TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar", "FocusFrameHealthBar" } },
    { unit = "targettarget", paths = { "TargetFrame.totFrame.healthbar", "TargetFrameToT.healthbar", "TargetFrameToTHealthBar" } },
    { unit = "pet", paths = { "PetFrame.healthbar", "PetFrameHealthBar" } },
}
for i = 1, 4 do
    UNIT_BARS[#UNIT_BARS + 1] = { unit = "party" .. i, paths = { "PartyFrame.MemberFrame" .. i .. ".HealthBar", "PartyFrame.MemberFrame" .. i .. ".healthbar", "PartyMemberFrame" .. i .. "HealthBar" } }
end

local function ColorBar(bar, unit)
    if not bar or not bar.SetStatusBarColor or not UnitExists(unit) then
        return
    end
    if bar.IsForbidden and bar:IsForbidden() then
        return
    end
    local r, g, b
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        if ns.IsSecret(class) then
            return
        end
        r, g, b = ns.ClassColor(class)
    else
        if UnitIsTapDenied and UnitIsTapDenied(unit) then
            r, g, b = 0.5, 0.5, 0.5
        else
            r, g, b = ns.ReactionColor(unit)
        end
    end
    if bar.SetStatusBarDesaturated then
        bar:SetStatusBarDesaturated(true)
    end
    if bar.lockColor ~= nil then
        bar.lockColor = false
    end
    bar:SetStatusBarColor(r, g, b)
    if bar.lockColor ~= nil then
        bar.lockColor = true
    end
end

function UI:ColorUnitFrames(_, unit)
    if not self.db.classColorFrames or InCombatLockdown() then
        return
    end
    for _, entry in ipairs(UNIT_BARS) do
        if not unit or entry.unit == unit then
            local bar = ns.FirstFrame(unpack(entry.paths))
            if bar then
                pcall(ColorBar, bar, entry.unit)
            end
        end
    end
end

function UI:HookUnitFrames()
    if self.unitHooked then
        return
    end
    self.unitHooked = true
    local module = self
    local function Recolor()
        module:ColorUnitFrames()
    end
    ns.SecureHook("UnitFrameHealthBar_Update", function()
        if module.enabled and module.db.classColorFrames then
            module:After(0, Recolor)
        end
    end)
    if HealthBarMixin and HealthBarMixin.UpdateHealthColor then
        -- modern health bars recolor themselves; recolor after them
        hooksecurefunc(HealthBarMixin, "UpdateHealthColor", function()
            if module.enabled and module.db.classColorFrames and not InCombatLockdown() then
                module:After(0, Recolor)
            end
        end)
    end
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function() self:After(0, Recolor) end)
    self:RegisterEvent("PLAYER_FOCUS_CHANGED", function() self:After(0, Recolor) end)
    self:RegisterEvent("UNIT_TARGET", function() self:After(0, Recolor) end)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", function() self:After(0.5, Recolor) end)
    self:RegisterEvent("UNIT_FACTION", function(_, _, unit) self:ColorUnitFrames(nil, unit) end)
    self:RegisterEvent("PLAYER_REGEN_ENABLED", function() self:After(0, Recolor) end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function() self:After(1, Recolor) end)
    self:RegisterEvent("UNIT_PET", function() self:After(0.2, Recolor) end)
end

-- Hit indicator, status text ---------------------------------------------------------

function UI:ApplyHitIndicator()
    local indicator = ns.FirstFrame("PlayerHitIndicator", "PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.HitIndicator",
        "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.HitIndicator")
    local petIndicator = ns.FirstFrame("PetHitIndicator", "PetFrame.HitIndicator")
    for _, frame in ipairs({ indicator, petIndicator }) do
        if frame and frame.SetAlpha then
            frame:SetAlpha(self.db.hideHitIndicator and 0 or 1)
        end
    end
end

local STATUS_VALUES = { NONE = "NONE", NUMERIC = "NUMERIC", PERCENT = "PERCENT", BOTH = "BOTH" }

function UI:ApplyStatusText()
    local mode = STATUS_VALUES[self.db.statusText]
    if not mode then
        return
    end
    if ns.CVarExists("statusTextDisplay") then
        ns.SetCVar("statusTextDisplay", mode)
    end
    if ns.CVarExists("statusText") then
        ns.SetCVar("statusText", mode == "NONE" and "0" or "1")
    end
end

-- Camera -------------------------------------------------------------------------------

function UI:ApplyCamera()
    local zoom = tonumber(self.db.maxZoom)
    if zoom then
        ns.SetCVar("cameraDistanceMaxZoomFactor", ("%.1f"):format(zoom))
    end
    local cam = self.db.actionCam
    if cam == "KEEP" then
        return
    end
    -- stop the "experimental features" dialog from popping up on login
    if UIParent and UIParent.UnregisterEvent then
        pcall(UIParent.UnregisterEvent, UIParent, "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
    end
    if cam == "OFF" then
        ns.SetCVar("test_cameraDynamicPitch", 0)
        ns.SetCVar("test_cameraOverShoulder", 0)
        ns.SetCVar("test_cameraHeadMovementStrength", 0)
        ns.SetCVar("test_cameraTargetFocusEnemyEnable", 0)
        ns.SetCVar("test_cameraTargetFocusInteractEnable", 0)
    elseif cam == "BASIC" then
        ns.SetCVar("test_cameraDynamicPitch", 1)
        ns.SetCVar("test_cameraOverShoulder", 0)
        ns.SetCVar("test_cameraHeadMovementStrength", 0)
        ns.SetCVar("test_cameraTargetFocusEnemyEnable", 0)
        ns.SetCVar("test_cameraTargetFocusInteractEnable", 0)
    elseif cam == "FULL" then
        ns.SetCVar("test_cameraDynamicPitch", 1)
        ns.SetCVar("test_cameraOverShoulder", 1)
        ns.SetCVar("test_cameraHeadMovementStrength", 0.5)
        ns.SetCVar("test_cameraTargetFocusEnemyEnable", 1)
        ns.SetCVar("test_cameraTargetFocusInteractEnable", 1)
    end
end

-- Built-in quest object sparkle (Twinkle does the fancy version) -----------------------

function UI:ApplyQuestSparkle()
    if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Twinkle") then
        return
    end
    if not self.db.questSparkle then
        return
    end
    if ns.CVarExists("outlineModeShowLootEffectWhenDisabled") then
        ns.SetCVar("outlineModeShowLootEffectWhenDisabled", 1)
    end
end

-- Setup ---------------------------------------------------------------------------------

function UI:ApplyAll()
    self:ApplyGryphons()
    self:ApplyErrorFilter()
    self:ApplyZoneText()
    self:ApplyHitIndicator()
    self:ApplyStatusText()
    self:ApplyCamera()
    self:ApplyQuestSparkle()
    if self.db.classColorFrames then
        self:HookUnitFrames()
        self:ColorUnitFrames()
    end
end

function UI:OnEnable()
    self:ApplyAll()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        self:After(1, function(module)
            module:ApplyGryphons()
            module:ApplyHitIndicator()
        end)
    end)
end

function UI:OnDisable()
    local saved = {}
    for _, key in ipairs({ "hideGryphons", "errorFilter", "hideZoneText", "hideHitIndicator" }) do
        saved[key] = self.db[key]
        self.db[key] = false
    end
    self:ApplyGryphons()
    self:ApplyErrorFilter()
    self:ApplyZoneText()
    self:ApplyHitIndicator()
    for key, value in pairs(saved) do
        self.db[key] = value
    end
end

function UI:OnSettingChanged()
    self:ApplyAll()
end

--------------------------------------------------------------------------
-- Durability warning and repair cost
--------------------------------------------------------------------------

local Durability = ns:NewModule("Durability", {
    group = "INTERFACE",
    defaults = { enabled = true, threshold = 20, sound = true, slotText = true },
    options = {
        { key = "threshold", type = "range", label = "DUR_THRESHOLD", tooltip = "DUR_THRESHOLD_TT", min = 5, max = 60, step = 5, format = "%d%%" },
        { key = "sound", type = "toggle", label = "DUR_SOUND" },
        { key = "slotText", type = "toggle", label = "DUR_SLOT_TEXT", tooltip = "DUR_SLOT_TEXT_TT" },
    },
})

local SLOT_NAMES = {
    [1] = "Head", [3] = "Shoulder", [5] = "Chest", [6] = "Waist", [7] = "Legs", [8] = "Feet",
    [9] = "Wrist", [10] = "Hands", [16] = "MainHand", [17] = "SecondaryHand", [18] = "Ranged",
}

-- Lowest and average durability percent across worn gear (nil if unknown).
function ns.GetDurability()
    if not GetInventoryItemDurability then
        return nil
    end
    local lowest, total, count = nil, 0, 0
    local perSlot = {}
    for slot in pairs(SLOT_NAMES) do
        local current, maximum = GetInventoryItemDurability(slot)
        current, maximum = ns.Plain(current), ns.Plain(maximum)
        if current and maximum and maximum > 0 then
            local percent = current / maximum * 100
            perSlot[slot] = percent
            total = total + percent
            count = count + 1
            if not lowest or percent < lowest then
                lowest = percent
            end
        end
    end
    if count == 0 then
        return nil
    end
    return lowest, total / count, perSlot
end

function Durability:OnEnable()
    self:RegisterEvent("UPDATE_INVENTORY_DURABILITY", "Check")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Check")
    self:RegisterEvent("MERCHANT_SHOW", "OnMerchant")
    if CharacterFrame and not self.charHooked then
        self.charHooked = true
        self:HookScript(CharacterFrame, "OnShow", function(module) module:UpdateSlotText() end)
    end
    self:Check()
end

function Durability:Check()
    local lowest = ns.GetDurability()
    if not lowest then
        return
    end
    local threshold = tonumber(self.db.threshold) or 20
    local now = GetTime()
    if lowest <= threshold then
        if not self.warned or (now - self.warned) > 300 then
            self.warned = now
            local text = L.DUR_WARNING:format(math.floor(lowest))
            if RaidNotice_AddMessage and RaidWarningFrame then
                RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo.RAID_WARNING or { r = 1, g = 0.5, b = 0 })
            end
            self:Print(text)
            if self.db.sound then
                PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
            end
        end
    else
        self.warned = nil
    end
    if CharacterFrame and CharacterFrame:IsShown() then
        self:UpdateSlotText()
    end
end

function Durability:UpdateSlotText()
    local _, _, perSlot = ns.GetDurability()
    for slot, name in pairs(SLOT_NAMES) do
        local button = _G["Character" .. name .. "Slot"]
        if button then
            if not button.bigarmsDurability then
                local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
                text:SetPoint("BOTTOM", button, "BOTTOM", 0, 2)
                button.bigarmsDurability = text
            end
            local percent = perSlot and perSlot[slot]
            if self.db.slotText and percent then
                local r, g, b = 0.2, 1, 0.2
                if percent < 25 then
                    r, g, b = 1, 0.2, 0.2
                elseif percent < 50 then
                    r, g, b = 1, 0.8, 0.2
                end
                button.bigarmsDurability:SetTextColor(r, g, b)
                button.bigarmsDurability:SetText(("%d%%"):format(percent))
                button.bigarmsDurability:Show()
            else
                button.bigarmsDurability:Hide()
            end
        end
    end
end

function Durability:OnMerchant()
    if not (CanMerchantRepair and CanMerchantRepair()) then
        return
    end
    local repair = ns:GetModule("AutoRepair")
    if repair and repair.enabled then
        return -- AutoRepair reports the cost itself
    end
    local cost = ns.Plain((GetRepairAllCost()))
    if cost and cost > 0 then
        self:Print(L.DUR_REPAIR_COST:format(ns.FormatMoney(cost)))
    end
end

function Durability:OnDisable()
    for _, name in pairs(SLOT_NAMES) do
        local button = _G["Character" .. name .. "Slot"]
        if button and button.bigarmsDurability then
            button.bigarmsDurability:Hide()
        end
    end
end

function Durability:OnSettingChanged()
    self:Check()
end

--------------------------------------------------------------------------
-- Movable windows: Alt-drag Blizzard windows and remember where they go
--------------------------------------------------------------------------

local Movers = ns:NewModule("Movers", {
    group = "INTERFACE",
    needsReload = true,
    defaults = { enabled = true, key = "ALT" },
    options = {
        { key = "key", type = "select", label = "MV_KEY", tooltip = "MV_KEY_TT", choices = function()
            return { { "ALT", L.KEY_ALT }, { "SHIFT", L.KEY_SHIFT }, { "CTRL", L.KEY_CTRL }, { "NONE", L.MV_KEY_ALWAYS } }
        end },
        { type = "button", label = "MV_RESET", button = "RESET", func = function() ns:GetModule("Movers"):ResetAll() end },
        { type = "description", text = "MV_HELP" },
    },
})

local MOVABLE = {
    "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "TalentFrame", "QuestLogFrame", "MerchantFrame",
    "MailFrame", "GossipFrame", "QuestFrame", "TradeFrame", "DressUpFrame", "FriendsFrame", "LootFrame",
    "TaxiFrame", "BankFrame", "TradeSkillFrame", "ProfessionsFrame", "PVEFrame", "MacroFrame", "HelpFrame",
    "GameMenuFrame", "ItemTextFrame", "TabardFrame", "GuildRegistrarFrame", "PetitionFrame", "PetStableFrame",
    "InspectFrame", "AuctionHouseFrame", "GuildFrame", "CommunitiesFrame", "AddonList", "ClassTrainerFrame",
    "ItemSocketingFrame", "WorldMapFrame", "LegacySystemFrame", "GuildBankFrame", "OpenMailFrame", "QuestMapFrame",
}

function Movers:Restore(frame)
    local key = frame:GetName()
    local saved = key and ns.db.positions[key]
    if not saved or InCombatLockdown() then
        return
    end
    if frame.IsProtected and frame:IsProtected() and InCombatLockdown() then
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
end

function Movers:Prepare(frame)
    if frame.bigarmsMovable then
        return
    end
    frame.bigarmsMovable = true
    local module = self
    local ok = pcall(function()
        frame:SetMovable(true)
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:RegisterForDrag("LeftButton")
    end)
    if not ok then
        return
    end
    frame:HookScript("OnDragStart", function(self_)
        if not module.enabled or InCombatLockdown() then
            return
        end
        if module.db.key ~= "NONE" and not ns.IsModifierDown(module.db.key) then
            return
        end
        self_.bigarmsDragging = true
        self_:StartMoving()
    end)
    frame:HookScript("OnDragStop", function(self_)
        if not self_.bigarmsDragging then
            return
        end
        self_.bigarmsDragging = nil
        self_:StopMovingOrSizing()
        local key = self_:GetName()
        if key then
            local point, _, _, x, y = self_:GetPoint(1)
            -- bottom left corner relative to the screen, in the frame's own scale
            local left, bottom = self_:GetLeft(), self_:GetBottom()
            if left and bottom then
                ns.db.positions[key] = { point = "BOTTOMLEFT", x = left, y = bottom }
            elseif point then
                ns.db.positions[key] = { point = point, x = x, y = y }
            end
        end
    end)
    frame:HookScript("OnShow", function(self_)
        if module.enabled then
            module:After(0, function() module:Restore(self_) end)
        end
    end)
    if frame:IsShown() then
        self:Restore(frame)
    end
end

function Movers:PrepareAll()
    for _, name in ipairs(MOVABLE) do
        local frame = _G[name]
        if type(frame) == "table" and frame.HookScript and not (frame.IsForbidden and frame:IsForbidden()) then
            pcall(self.Prepare, self, frame)
        end
    end
end

function Movers:ResetAll()
    wipe(ns.db.positions)
    self:Print(L.MV_RESET_DONE)
end

function Movers:OnEnable()
    self:PrepareAll()
    -- frames that load with their own addon (bank, auction house, professions...)
    self:RegisterEvent("ADDON_LOADED", function(module)
        module:After(0, module.PrepareAll)
    end)
end

--------------------------------------------------------------------------
-- Reputation gains with progress
--------------------------------------------------------------------------

local Reputation = ns:NewModule("Reputation", {
    group = "INTERFACE",
    defaults = { enabled = true },
    options = {
        { type = "description", text = "REP_HELP" },
    },
})

local function FactionList()
    local list = {}
    if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
        for i = 1, C_Reputation.GetNumFactions() do
            local data = C_Reputation.GetFactionDataByIndex(i)
            if data and data.factionID and (not data.isHeader or data.isHeaderWithRep) then
                list[data.factionID] = {
                    name = data.name, standing = data.reaction, value = data.currentStanding,
                    min = data.currentReactionThreshold, max = data.nextReactionThreshold,
                }
            end
        end
    elseif GetNumFactions and GetFactionInfo then
        for i = 1, GetNumFactions() do
            local name, _, standing, min, max, value, _, _, isHeader, _, hasRep, _, _, factionID = GetFactionInfo(i)
            if factionID and (not isHeader or hasRep) then
                list[factionID] = { name = name, standing = standing, value = value, min = min, max = max }
            end
        end
    end
    return list
end

function Reputation:OnEnable()
    self.snapshot = FactionList()
    self:RegisterEvent("UPDATE_FACTION", "OnUpdate")
end

function Reputation:OnUpdate()
    local before = self.snapshot or {}
    local now = FactionList()
    self.snapshot = now
    for factionID, info in pairs(now) do
        local old = before[factionID]
        if old and info.value and old.value and info.value ~= old.value then
            local change = info.value - old.value
            local standingText = (_G["FACTION_STANDING_LABEL" .. tostring(info.standing)]) or ""
            local progress = ""
            if info.min and info.max and info.max > info.min then
                progress = (" (%d/%d)"):format(info.value - info.min, info.max - info.min)
            end
            local color = change > 0 and "|cff40ff40+" or "|cffff4040"
            self:Print(L.REP_CHANGE:format(info.name or "?", color .. change .. "|r", standingText, progress))
        end
    end
end
