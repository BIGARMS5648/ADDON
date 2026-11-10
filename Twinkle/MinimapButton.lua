local ADDON, ns = ...
local L = ns.L

-- Round minimap button (same look and placement rules as LibDBIcon buttons,
-- written without the library), plus an entry in the addon compartment menu.

local ICON = "Interface\\AddOns\\" .. ADDON .. "\\Media\\icon"
local GLOW = "Interface\\AddOns\\" .. ADDON .. "\\Media\\glow"
local BORDER = 136430 -- Interface\Minimap\MiniMap-TrackingBorder
local BACKGROUND = 136467 -- Interface\Minimap\UI-Minimap-Background
local HIGHLIGHT = 136477 -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
local RADIUS_PAD = 5 -- how far outside the minimap edge the button sits

local rad, deg, cos, sin, sqrt, max, min = math.rad, math.deg, math.cos, math.sin, math.sqrt, math.max, math.min
local atan2 = math.atan2

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local button

-- Which quadrants are rounded, for addons that reshape the minimap.
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

local function UpdatePosition()
    local angle = rad(ns.db.minimap.angle or 225)
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

-- Shared by the minimap button and the addon compartment entry.
local function HandleClick(mouseButton)
    if mouseButton == "RightButton" then
        ns:SetEnabled(not ns.db.enabled)
        ns.Print(ns.db.enabled and L.ENABLED or L.DISABLED)
    elseif mouseButton == "MiddleButton" then
        ns:ShowTest()
    else
        ns:OpenOptions()
    end
end

local function ShowTooltip(owner, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_LEFT")
    GameTooltip:SetText(L.TITLE)
    GameTooltip:AddLine(ns.db.enabled and L.STATUS_ON or L.STATUS_OFF)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.MINIMAP_LEFT, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_RIGHT, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_MIDDLE, 1, 1, 1)
    if owner == button then
        GameTooltip:AddLine(L.MINIMAP_DRAG, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function OnUpdate(self, elapsed)
    self.t = self.t + elapsed
    if self.dragging then
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        ns.db.minimap.angle = deg(atan2(py - my, px - mx)) % 360
        UpdatePosition()
    end
    if self.glow:IsShown() then
        self.glow:SetAlpha(0.35 + 0.35 * sin(self.t * 2.5))
    end
end

local function Create()
    button = CreateFrame("Button", "TwinkleMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("AnyUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture(HIGHLIGHT)
    button.t = 0

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(BACKGROUND)
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)

    local glow = button:CreateTexture(nil, "BACKGROUND", nil, 1)
    glow:SetTexture(GLOW)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.8, 0.2)
    glow:SetSize(26, 26)
    glow:SetPoint("CENTER", background, "CENTER")
    button.glow = glow

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    button.icon = icon

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(BORDER)
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(self, mouseButton)
        HandleClick(mouseButton)
        if GameTooltip:IsOwned(self) then
            ShowTooltip(self)
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not self.dragging then
            ShowTooltip(self)
        end
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetScript("OnMouseDown", function(self)
        self.icon:SetPoint("TOPLEFT", 8, -7)
    end)
    button:SetScript("OnMouseUp", function(self)
        self.icon:SetPoint("TOPLEFT", 7, -6)
    end)
    button:SetScript("OnDragStart", function(self)
        self.dragging = true
        self:LockHighlight()
        GameTooltip:Hide()
    end)
    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        self:UnlockHighlight()
        self.icon:SetPoint("TOPLEFT", 7, -6)
    end)
    button:SetScript("OnUpdate", OnUpdate)

    Minimap:HookScript("OnSizeChanged", function()
        if button:IsShown() then
            UpdatePosition()
        end
    end)
end

-- Creates the button if needed and syncs it with the saved settings.
function MinimapButton:Update()
    if not Minimap then
        return
    end
    if not button then
        if ns.db.minimap.hide then
            return
        end
        Create()
    end
    if ns.db.minimap.hide then
        button:Hide()
        return
    end
    local enabled = ns.db.enabled
    button.icon:SetDesaturated(not enabled)
    if enabled then
        button.icon:SetVertexColor(1, 1, 1)
        button.glow:Show()
    else
        button.icon:SetVertexColor(0.6, 0.6, 0.6)
        button.glow:Hide()
    end
    UpdatePosition()
    button:Show()
end

function MinimapButton:GetFrame()
    return button
end

function MinimapButton:Toggle()
    ns.db.minimap.hide = not ns.db.minimap.hide
    self:Update()
    ns.Print(ns.db.minimap.hide and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
end

-- Addon compartment (the addon list button next to the minimap).
-- Wired up through the AddonCompartmentFunc* lines in Twinkle.toc.
function Twinkle_OnAddonCompartmentClick(_, mouseButton)
    HandleClick(mouseButton)
end

function Twinkle_OnAddonCompartmentEnter(_, menuButton)
    ShowTooltip(menuButton, "ANCHOR_LEFT")
end

function Twinkle_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
