local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Minimap: square shape, hidden bits, coordinates, auto zoom out, pings
--------------------------------------------------------------------------

local MinimapMod = ns:NewModule("Minimap", {
    group = "MINIMAP",
    needsReload = true,
    defaults = {
        enabled = true,
        square = false,
        hideZoneText = false,
        hideClock = false,
        hideCalendar = false,
        hideZoomButtons = true,
        hideTracking = false,
        coords = true,
        coordsDecimals = 1,
        autoZoomOut = 15,
        pingChat = true,
        collectButtons = false,
    },
    options = {
        { key = "square", type = "toggle", label = "MM_SQUARE", tooltip = "MM_SQUARE_TT" },
        { key = "hideZoneText", type = "toggle", label = "MM_HIDE_ZONE" },
        { key = "hideClock", type = "toggle", label = "MM_HIDE_CLOCK" },
        { key = "hideCalendar", type = "toggle", label = "MM_HIDE_CALENDAR" },
        { key = "hideZoomButtons", type = "toggle", label = "MM_HIDE_ZOOM", tooltip = "MM_HIDE_ZOOM_TT" },
        { key = "hideTracking", type = "toggle", label = "MM_HIDE_TRACKING" },
        { key = "coords", type = "toggle", label = "MM_COORDS", tooltip = "MM_COORDS_TT" },
        { key = "coordsDecimals", type = "range", label = "MM_COORDS_DECIMALS", min = 0, max = 2, step = 1, format = "%d" },
        { key = "autoZoomOut", type = "range", label = "MM_AUTO_ZOOM", tooltip = "MM_AUTO_ZOOM_TT", min = 0, max = 60, step = 5, format = "%ds" },
        { key = "pingChat", type = "toggle", label = "MM_PING_CHAT" },
        { key = "collectButtons", type = "toggle", label = "MM_COLLECT", tooltip = "MM_COLLECT_TT" },
    },
})

local function Toggle(frame, hide)
    if not frame then
        return
    end
    if hide then
        frame:Hide()
        if not frame.bigarmsHideHook then
            frame.bigarmsHideHook = true
            MinimapMod:HookScript(frame, "OnShow", function(module, self_)
                if self_.bigarmsWantHidden then
                    self_:Hide()
                end
            end)
        end
        frame.bigarmsWantHidden = true
    else
        frame.bigarmsWantHidden = nil
        frame:Show()
    end
end

-- Square shape ---------------------------------------------------------------

local squareBorder

function MinimapMod:ApplyShape()
    if not Minimap or not Minimap.SetMaskTexture then
        return
    end
    if self.db.square then
        self.wasSquare = true
        Minimap:SetMaskTexture("Interface\\BUTTONS\\WHITE8X8")
        if not squareBorder then
            squareBorder = CreateFrame("Frame", nil, Minimap, "BackdropTemplate")
            squareBorder:SetPoint("TOPLEFT", Minimap, "TOPLEFT", -1, 1)
            squareBorder:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", 1, -1)
            squareBorder:SetFrameLevel(Minimap:GetFrameLevel() + 1)
            if squareBorder.SetBackdrop then
                squareBorder:SetBackdrop({ edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
                squareBorder:SetBackdropBorderColor(0, 0, 0, 1)
            end
        end
        squareBorder:Show()
        local compass = ns.FirstFrame("MinimapCompassTexture", "MinimapCluster.MinimapContainer.MinimapCompassTexture")
        if compass then
            compass:Hide()
        end
        if not self.shapeDefined then
            self.shapeDefined = true
            if GetMinimapShape == nil then
                GetMinimapShape = function() return "SQUARE" end
                self.ownsShape = true
            end
        end
    elseif self.wasSquare then
        self.wasSquare = nil
        Minimap:SetMaskTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        if squareBorder then
            squareBorder:Hide()
        end
        local compass = ns.FirstFrame("MinimapCompassTexture", "MinimapCluster.MinimapContainer.MinimapCompassTexture")
        if compass then
            compass:Show()
        end
    end
    if ns.MinimapButton and ns.MinimapButton.UpdatePosition then
        ns.MinimapButton:UpdatePosition()
    end
end

-- Hidden elements --------------------------------------------------------------

function MinimapMod:ApplyHidden()
    local db = self.db
    Toggle(ns.FirstFrame("MinimapCluster.ZoneTextButton", "MinimapZoneTextButton"), db.hideZoneText)
    Toggle(ns.FirstFrame("MinimapCluster.BorderTop"), db.hideZoneText)
    Toggle(ns.FirstFrame("TimeManagerClockButton"), db.hideClock)
    Toggle(ns.FirstFrame("GameTimeFrame"), db.hideCalendar)
    Toggle(ns.FirstFrame("Minimap.ZoomIn", "MinimapZoomIn"), db.hideZoomButtons)
    Toggle(ns.FirstFrame("Minimap.ZoomOut", "MinimapZoomOut"), db.hideZoomButtons)
    Toggle(ns.FirstFrame("MinimapCluster.Tracking", "MiniMapTrackingButton", "MiniMapTracking"), db.hideTracking)
end

-- Coordinates --------------------------------------------------------------------

local coordText

function ns.PlayerMapPosition()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then
        return nil
    end
    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then
        return nil
    end
    local ok, position = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if not ok or not position then
        return nil
    end
    local x, y = position:GetXY()
    x, y = ns.Plain(x), ns.Plain(y)
    if not x or not y or (x == 0 and y == 0) then
        return nil
    end
    return mapID, x, y
end

function MinimapMod:UpdateCoords()
    if not coordText then
        return
    end
    local _, x, y = ns.PlayerMapPosition()
    if not x then
        coordText:SetText("")
        return
    end
    local decimals = tonumber(self.db.coordsDecimals) or 1
    local format = ("%%.%df, %%.%df"):format(decimals, decimals)
    coordText:SetText(format:format(x * 100, y * 100))
end

function MinimapMod:ApplyCoords()
    if self.db.coords then
        if not coordText then
            local holder = CreateFrame("Frame", "BIGARMSMinimapCoords", Minimap)
            holder:SetSize(90, 14)
            holder:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 3)
            holder:SetFrameLevel(Minimap:GetFrameLevel() + 5)
            coordText = holder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            coordText:SetAllPoints(holder)
            coordText:SetJustifyH("CENTER")
            coordText:SetTextColor(1, 0.9, 0.5)
            holder.text = coordText
        end
        coordText:GetParent():Show()
        if not self.coordTicker then
            self.coordTicker = self:Ticker(0.25, self.UpdateCoords)
        end
        self:UpdateCoords()
    elseif coordText then
        coordText:GetParent():Hide()
        if self.coordTicker then
            self.coordTicker:Cancel()
            self.coordTicker = nil
        end
    end
end

-- Auto zoom out ------------------------------------------------------------------

function MinimapMod:ScheduleZoomOut()
    local delay = tonumber(self.db.autoZoomOut) or 0
    if delay <= 0 or not Minimap or not Minimap.GetZoom then
        return
    end
    self.zoomToken = (self.zoomToken or 0) + 1
    local token = self.zoomToken
    self:After(delay, function(module)
        if module.zoomToken == token and Minimap:GetZoom() > 0 then
            Minimap:SetZoom(0)
        end
    end)
end

-- Button collector -----------------------------------------------------------------

local BLIZZARD_BUTTONS = {
    MinimapBackdrop = true, MinimapZoomIn = true, MinimapZoomOut = true, MiniMapTracking = true,
    MiniMapTrackingButton = true, GameTimeFrame = true, TimeManagerClockButton = true, MiniMapMailFrame = true,
    MinimapZoneTextButton = true, MiniMapWorldMapButton = true, MiniMapBattlefieldFrame = true, MiniMapLFGFrame = true,
    QueueStatusButton = true, ExpansionLandingPageMinimapButton = true, BIGARMSMinimapButton = true,
    MinimapCompassTexture = true, BIGARMSMinimapCoords = true, AddonCompartmentFrame = true,
}

local bar

function MinimapMod:CollectButtons()
    if not self.db.collectButtons or not Minimap then
        return
    end
    if not bar then
        bar = CreateFrame("Frame", "BIGARMSButtonBar", UIParent, "BackdropTemplate")
        bar:SetSize(32, 32)
        bar:SetPoint("TOPRIGHT", Minimap, "BOTTOMRIGHT", 0, -8)
        bar:SetFrameStrata("MEDIUM")
        if bar.SetBackdrop then
            bar:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8", edgeFile = "Interface\\BUTTONS\\WHITE8X8", edgeSize = 1 })
            bar:SetBackdropColor(0, 0, 0, 0.5)
            bar:SetBackdropBorderColor(0, 0, 0, 1)
        end
        bar.buttons = {}
    end
    local function Consider(child)
        if type(child) ~= "table" or not child.GetObjectType or child:GetObjectType() ~= "Button" then
            return
        end
        local name = child.GetName and child:GetName()
        if name and BLIZZARD_BUTTONS[name] then
            return
        end
        if child.bigarmsCollected or (child.IsForbidden and child:IsForbidden()) then
            return
        end
        local looksLikeAddonButton = (name and (name:find("LibDBIcon", 1, true) or name:find("MinimapButton", 1, true)))
            or (not name and child:GetWidth() <= 40)
        if not looksLikeAddonButton then
            return
        end
        child.bigarmsCollected = true
        child:SetParent(bar)
        child:ClearAllPoints()
        child:SetSize(26, 26)
        bar.buttons[#bar.buttons + 1] = child
        local index = #bar.buttons
        child:SetPoint("RIGHT", bar, "RIGHT", -3 - (index - 1) * 28, 0)
        bar:SetWidth(6 + index * 28)
    end
    for _, parent in ipairs({ Minimap, MinimapBackdrop, MinimapCluster }) do
        if parent and parent.GetChildren then
            for _, child in ipairs({ parent:GetChildren() }) do
                pcall(Consider, child)
            end
        end
    end
    bar:SetShown(#bar.buttons > 0)
end

-- Ping to chat ---------------------------------------------------------------------

function MinimapMod:OnPing(_, unit)
    if not self.db.pingChat or not unit then
        return
    end
    local name = UnitName(unit)
    if not name or ns.IsSecret(name) or UnitIsUnit(unit, "player") then
        return
    end
    local now = GetTime()
    if self.lastPing and self.lastPing.name == name and now - self.lastPing.time < 3 then
        return
    end
    self.lastPing = { name = name, time = now }
    local r, g, b = ns.UnitColor(unit)
    self:Print(L.MM_PINGED:format(("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name)))
end

-- Setup ------------------------------------------------------------------------------

function MinimapMod:ApplyAll()
    self:ApplyShape()
    self:ApplyHidden()
    self:ApplyCoords()
    if self.db.collectButtons then
        self:After(1, self.CollectButtons)
    end
end

function MinimapMod:OnEnable()
    self:ApplyAll()
    self:RegisterEvent("MINIMAP_PING", "OnPing")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "ApplyAll")
    if Minimap and not self.zoomHooked then
        self.zoomHooked = true
        self:SecureHook(Minimap, "SetZoom", function(module)
            module:ScheduleZoomOut()
        end)
    end
end

function MinimapMod:OnDisable()
    if coordText then
        coordText:GetParent():Hide()
    end
    -- show everything again without forgetting the player's choices
    local saved = {}
    for _, key in ipairs({ "hideZoneText", "hideClock", "hideCalendar", "hideZoomButtons", "hideTracking", "square" }) do
        saved[key] = self.db[key]
        self.db[key] = false
    end
    self:ApplyHidden()
    self:ApplyShape()
    for key, value in pairs(saved) do
        self.db[key] = value
    end
end

function MinimapMod:OnSettingChanged()
    self:ApplyAll()
end
