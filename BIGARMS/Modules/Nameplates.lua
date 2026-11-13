local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Nameplates: game settings, combat-only enemy plates, quest icons and
-- a glow on your target's plate. Everything anchors to the plate's
-- UnitFrame (never the base NamePlate frame) and never measures it.
--------------------------------------------------------------------------

local Nameplates = ns:NewModule("Nameplates", {
    group = "NAMEPLATES",
    defaults = {
        enabled = true,
        showEnemies = "KEEP", showFriends = "KEEP", showAll = "KEEP", classColor = "KEEP", friendlyNamesOnly = "KEEP",
        combatOnly = false, questIcon = true, targetGlow = true,
    },
    options = {
        { key = "showEnemies", type = "select", label = "NP_ENEMIES", cvar = "nameplateShowEnemies", choices = "ONOFF" },
        { key = "showFriends", type = "select", label = "NP_FRIENDS", cvar = "nameplateShowFriends", choices = "ONOFF" },
        { key = "showAll", type = "select", label = "NP_ALL", tooltip = "NP_ALL_TT", cvar = "nameplateShowAll", choices = "ONOFF" },
        { key = "classColor", type = "select", label = "NP_CLASS_COLOR", cvar = "ShowClassColorInNameplate", choices = "ONOFF" },
        { key = "friendlyNamesOnly", type = "select", label = "NP_NAMES_ONLY", tooltip = "NP_NAMES_ONLY_TT", cvar = "nameplateShowOnlyNameForFriendlyPlayerUnits", choices = "ONOFF" },
        { key = "combatOnly", type = "toggle", label = "NP_COMBAT_ONLY", tooltip = "NP_COMBAT_ONLY_TT" },
        { key = "questIcon", type = "toggle", label = "NP_QUEST", tooltip = "NP_QUEST_TT" },
        { key = "targetGlow", type = "toggle", label = "NP_TARGET_GLOW" },
    },
})

-- Forever renamed some nameplate CVars; try both spellings
local CVAR_ALIASES = {
    nameplateShowFriends = { "nameplateShowFriends", "nameplateShowFriendlyPlayers" },
    nameplateShowOnlyNameForFriendlyPlayerUnits = { "nameplateShowOnlyNameForFriendlyPlayerUnits", "nameplateShowOnlyNames" },
}

function Nameplates:ApplyCVars()
    for _, option in ipairs(self.options) do
        if option.cvar then
            local names = CVAR_ALIASES[option.cvar] or { option.cvar }
            for _, name in ipairs(names) do
                if ns.CVarExists(name) then
                    ns.ApplyCVarOption(self, { key = option.key, cvar = name, choices = option.choices, type = option.type })
                    break
                end
            end
        end
    end
end

-- Quest progress --------------------------------------------------------------

-- "Boars slain: 3/5" or "Something: 40%" from a unit tooltip
function ns.QuestProgressFromTooltip(lines)
    if type(lines) ~= "table" then
        return nil
    end
    local questType = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.QuestObjective
    for _, line in ipairs(lines) do
        local text = line.leftText
        if type(text) == "string" and not ns.IsSecret(text) then
            local isObjective = questType ~= nil and line.type == questType
            local current, total = text:match("(%d+)%s*/%s*(%d+)%s*$")
            if current and total then
                if tonumber(current) < tonumber(total) then
                    return current .. "/" .. total
                end
            elseif isObjective then
                local percent = text:match("(%d+)%%")
                if percent and tonumber(percent) < 100 then
                    return percent .. "%"
                end
                return "!"
            else
                local percent = text:match("^.-:%s*(%d+)%%$")
                if percent and tonumber(percent) < 100 then
                    return percent .. "%"
                end
            end
        end
    end
    return nil
end

local function UnitFrameOf(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then
        return nil
    end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or not plate then
        return nil
    end
    local frame = plate.UnitFrame
    if not frame or (frame.IsForbidden and frame:IsForbidden()) then
        return nil
    end
    return frame, plate
end

function Nameplates:QuestWidget(frame)
    if frame.bigarmsQuest then
        return frame.bigarmsQuest
    end
    local holder = CreateFrame("Frame", nil, frame)
    holder:SetSize(22, 22)
    holder:SetPoint("RIGHT", frame, "LEFT", -2, 0)
    holder.icon = holder:CreateTexture(nil, "OVERLAY")
    holder.icon:SetAllPoints()
    holder.icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    holder.text = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    holder.text:SetPoint("TOP", holder, "BOTTOM", 0, 2)
    holder:Hide()
    frame.bigarmsQuest = holder
    return holder
end

function Nameplates:UpdateQuest(unit)
    local frame = UnitFrameOf(unit)
    if not frame then
        return
    end
    local widget = self:QuestWidget(frame)
    if not self.db.questIcon or not (C_TooltipInfo and C_TooltipInfo.GetUnit) or (UnitIsPlayer and UnitIsPlayer(unit)) then
        widget:Hide()
        return
    end
    local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
    local progress = ok and data and ns.QuestProgressFromTooltip(data.lines) or nil
    if progress then
        widget.text:SetText(progress ~= "!" and progress or "")
        widget:Show()
    else
        widget:Hide()
    end
end

function Nameplates:RefreshAllQuests()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then
        return
    end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or not plates then
        return
    end
    for _, plate in ipairs(plates) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if unit then
            pcall(self.UpdateQuest, self, unit)
        end
    end
end

-- Target glow ----------------------------------------------------------------------

function Nameplates:Glow(frame)
    if frame.bigarmsGlow then
        return frame.bigarmsGlow
    end
    local anchor = frame.healthBar or frame
    local glow = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -3, 3)
    glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 3, -3)
    glow:SetFrameLevel(math.max((frame.GetFrameLevel and frame:GetFrameLevel() or 1) - 1, 0))
    if glow.SetBackdrop then
        glow:SetBackdrop({ edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 2 })
        glow:SetBackdropBorderColor(1, 1, 1, 0.9)
    end
    glow:Hide()
    frame.bigarmsGlow = glow
    return glow
end

function Nameplates:UpdateTargetGlow()
    if self.glowing then
        self.glowing:Hide()
        self.glowing = nil
    end
    if not self.db.targetGlow or not UnitExists("target") then
        return
    end
    local frame = UnitFrameOf("target")
    if frame then
        local glow = self:Glow(frame)
        glow:Show()
        self.glowing = glow
    end
end

-- Combat-only enemy plates -----------------------------------------------------------

function Nameplates:OnCombat(event)
    if not self.db.combatOnly then
        return
    end
    ns.SetCVar("nameplateShowEnemies", event == "PLAYER_REGEN_DISABLED" and 1 or 0)
end

-- Setup --------------------------------------------------------------------------------

function Nameplates:OnEnable()
    self:ApplyCVars()
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(module, _, unit)
        module:UpdateQuest(unit)
        if UnitIsUnit(unit, "target") then
            module:UpdateTargetGlow()
        end
    end)
    self:RegisterEvent("NAME_PLATE_UNIT_REMOVED", function(module, _, unit)
        local frame = UnitFrameOf(unit)
        if frame then
            if frame.bigarmsQuest then
                frame.bigarmsQuest:Hide()
            end
            if frame.bigarmsGlow and frame.bigarmsGlow == module.glowing then
                frame.bigarmsGlow:Hide()
                module.glowing = nil
            end
        end
    end)
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "UpdateTargetGlow")
    self:RegisterEvent("QUEST_LOG_UPDATE", function(module)
        if module.questRefreshQueued then
            return
        end
        module.questRefreshQueued = true
        module:After(0.5, function(m)
            m.questRefreshQueued = nil
            m:RefreshAllQuests()
        end)
    end)
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombat")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombat")
    if self.db.combatOnly and not InCombatLockdown() then
        ns.SetCVar("nameplateShowEnemies", 0)
    end
end

function Nameplates:OnDisable()
    if self.glowing then
        self.glowing:Hide()
        self.glowing = nil
    end
end

function Nameplates:OnSettingChanged(key)
    self:ApplyCVars()
    self:UpdateTargetGlow()
    self:RefreshAllQuests()
    if key == "combatOnly" and not self.db.combatOnly and ns.CVarExists("nameplateShowEnemies") then
        -- hand the setting back to the player's normal value
        ns.ApplyCVarOption(self, self.options[1])
    end
end
