local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Round minimap button (LibDBIcon look, no library) and an addon
-- compartment entry.
--------------------------------------------------------------------------

local ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon"
local BORDER = 136430 -- Interface\Minimap\MiniMap-TrackingBorder
local BACKGROUND = 136467 -- Interface\Minimap\UI-Minimap-Background
local HIGHLIGHT = 136477 -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
local RADIUS_PAD = 5

local rad, deg, cos, sin, sqrt, max, min = math.rad, math.deg, math.cos, math.sin, math.sqrt, math.max, math.min
local atan2 = math.atan2

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local button

local SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
    ["TRICORNER-TOPLEFT"] = { false, true, true, true },
    ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
    ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
    ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

function MinimapButton:UpdatePosition()
    if not button then
        return
    end
    local angle = rad(ns.db.minimap.angle or 215)
    local x, y, q = cos(angle), sin(angle), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local quads = SHAPES[shape] or SHAPES.ROUND
    local w = Minimap:GetWidth() / 2 + RADIUS_PAD
    local h = Minimap:GetHeight() / 2 + RADIUS_PAD
    if quads[q] then
        x, y = x * w, y * h
    else
        local dw, dh = sqrt(2 * w * w) - 10, sqrt(2 * h * h) - 10
        x = max(-w, min(x * dw, w))
        y = max(-h, min(y * dh, h))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function HandleClick(mouseButton)
    if mouseButton == "RightButton" then
        local gold = ns:GetModule("Gold")
        if gold then
            gold:Report()
        end
        local xp = ns:GetModule("XP")
        if xp and xp.enabled then
            xp:Report()
        end
    elseif mouseButton == "MiddleButton" then
        ns.ShowChatCopy()
    else
        ns:OpenOptions()
    end
end

local function ShowTooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
    GameTooltip:SetText("BIGARMS |cff888888" .. ns.VERSION .. "|r")
    local on, total = 0, #ns.modules
    for _, module in ipairs(ns.modules) do
        if module.enabled then
            on = on + 1
        end
    end
    GameTooltip:AddLine(L.MODULES_ACTIVE:format(on, total), 1, 1, 1)
    local gold = ns:GetModule("Gold")
    if gold and gold.enabled then
        gold:TooltipLines(GameTooltip)
    end
    local xp = ns:GetModule("XP")
    if xp and xp.enabled and not (IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel()) then
        local s = xp:Stats()
        GameTooltip:AddDoubleLine(L.XP_TOOLTIP, ("%.1f%% (%s/h, %s)"):format(s.percent, ns.FormatHours and ("%.1fk"):format(s.perHour / 1000) or "", ns.FormatHours(s.hoursLeft)), 1, 0.82, 0, 1, 1, 1)
    end
    local lowest = ns.GetDurability and ns.GetDurability()
    if lowest then
        GameTooltip:AddDoubleLine(L.DUR_TOOLTIP, ("%d%%"):format(lowest), 1, 0.82, 0, 1, 1, 1)
    end
    if GetBindLocation then
        GameTooltip:AddDoubleLine(L.HOME_TOOLTIP, GetBindLocation() or "?", 1, 0.82, 0, 1, 1, 1)
    end
    local volume = tonumber(ns.GetCVar("Sound_MasterVolume"))
    if volume then
        GameTooltip:AddDoubleLine(L.VOLUME_TOOLTIP, ("%d%%"):format(volume * 100 + 0.5), 1, 0.82, 0, 1, 1, 1)
    end
    local errors = ns.db.errors and #ns.db.errors or 0
    if errors > 0 then
        GameTooltip:AddDoubleLine(L.EC_TOOLTIP, tostring(errors), 1, 0.82, 0, 1, 0.4, 0.4)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.MINIMAP_LEFT, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L.MINIMAP_RIGHT, 0.8, 0.8, 0.8)
    GameTooltip:AddLine(L.MINIMAP_MIDDLE, 0.8, 0.8, 0.8)
    if owner == button then
        GameTooltip:AddLine(L.MINIMAP_DRAG, 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L.MINIMAP_WHEEL, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

local function OnDragUpdate(self)
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    local angle = deg(atan2(cy - my, cx - mx)) % 360
    ns.db.minimap.angle = angle
    MinimapButton:UpdatePosition()
end

function MinimapButton:Create()
    if button or not Minimap then
        return
    end
    button = CreateFrame("Button", "BIGARMSMinimapButton", Minimap)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetSize(31, 31)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(HIGHLIGHT)

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture(BACKGROUND)
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(ICON)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture(BORDER)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(_, mouseButton)
        HandleClick(mouseButton)
    end)
    button:SetScript("OnEnter", function(self)
        if not self.dragging then
            ShowTooltip(self, "ANCHOR_LEFT")
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        GameTooltip:Hide()
        self:LockHighlight()
        self:SetScript("OnUpdate", OnDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = nil
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)
    if button.EnableMouseWheel then
        button:EnableMouseWheel(true)
        button:SetScript("OnMouseWheel", function(self, delta)
            if ns.AdjustVolume then
                local percent = ns.AdjustVolume(delta > 0 and 0.05 or -0.05)
                ns.Print(L.VOLUME_NOW:format(percent))
                if GameTooltip:IsOwned(self) then
                    ShowTooltip(self, "ANCHOR_LEFT")
                end
            end
        end)
    end

    self:UpdatePosition()
    self:Refresh()
end

function MinimapButton:Refresh()
    if not button then
        return
    end
    if ns.db.minimap.hide then
        button:Hide()
    else
        button:Show()
        self:UpdatePosition()
    end
end

-- Addon compartment (the addon list button next to the minimap)
function BIGARMS_OnAddonCompartmentClick(_, mouseButton)
    HandleClick(mouseButton)
end

function BIGARMS_OnAddonCompartmentEnter(_, menuButton)
    ShowTooltip(menuButton, "ANCHOR_LEFT")
end

function BIGARMS_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
