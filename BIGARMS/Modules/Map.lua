local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Waypoints: /way x y [note], an on-screen arrow and the game's own
-- map pin when the client offers one.
--------------------------------------------------------------------------

local Waypoint = ns:NewModule("Waypoint", {
    group = "MAP",
    defaults = { enabled = true, arrow = true, arrowY = 220, arriveDistance = 15, autoClear = true, gamePin = true },
    options = {
        { key = "arrow", type = "toggle", label = "WP_ARROW" },
        { key = "arrowY", type = "range", label = "WP_ARROW_Y", min = -300, max = 400, step = 10, format = "%d" },
        { key = "gamePin", type = "toggle", label = "WP_PIN", tooltip = "WP_PIN_TT" },
        { key = "autoClear", type = "toggle", label = "WP_AUTOCLEAR" },
        { key = "arriveDistance", type = "range", label = "WP_ARRIVE", min = 5, max = 50, step = 5, format = "%dm" },
        { type = "description", text = "WP_HELP" },
    },
})
ns.Waypoint = Waypoint

-- Parse "12.3 45,6", "12,3 45,6", "12.3, 45.6", "#1429 12 34", "12 34 Some note"
function ns.ParseWaypoint(text)
    text = ns.Trim(text or "")
    if text == "" then
        return nil
    end
    local mapID
    local hash, rest = text:match("^#(%d+)%s+(.*)$")
    if hash then
        mapID, text = tonumber(hash), rest
    end
    local x, y, note
    -- "12,3 45,6" with decimal commas comes first: it is the more specific shape
    local a, b, c, d, rest2 = text:match("^(%d+),(%d+)%s+(%d+),(%d+)%s*(.*)$")
    if a then
        x, y, note = a .. "." .. b, c .. "." .. d, rest2
    else
        x, y, note = text:match("^(%d+%.?%d*)[%s,]+(%d+%.?%d*)%s*(.*)$")
    end
    x, y = tonumber(x), tonumber(y)
    if not x or not y or x < 0 or x > 100 or y < 0 or y > 100 then
        return nil
    end
    note = ns.Trim(note or "")
    return mapID, x, y, note ~= "" and note or nil
end

-- World coordinates (yards) of a map position, when the client can tell us.
local function WorldPos(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
        return nil
    end
    local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and pos then
        local wx, wy = pos:GetXY()
        wx, wy = ns.Plain(wx), ns.Plain(wy)
        if wx and wy then
            return wx, wy
        end
    end
    return nil
end

-- Angle (radians, 0 = north, counter clockwise) and distance to the waypoint.
function Waypoint:Bearing()
    local wp = ns.char.waypoint
    if not wp then
        return nil
    end
    local mapID, px, py = ns.PlayerMapPosition()
    if not mapID then
        return nil
    end
    local pwx, pwy = WorldPos(mapID, px, py)
    local twx, twy = WorldPos(wp.mapID, wp.x, wp.y)
    local dx, dy, distance
    if pwx and twx then
        -- world: x = north, y = west
        dx, dy = twx - pwx, twy - pwy
        distance = math.sqrt(dx * dx + dy * dy)
    elseif mapID == wp.mapID then
        -- fall back to map units scaled to a rough yard estimate
        local width, height = 1000, 667
        if C_Map.GetMapWorldSize then
            local ok, w, h = pcall(C_Map.GetMapWorldSize, mapID)
            if ok and w and h then
                width, height = w, h
            end
        end
        dx, dy = -(wp.y - py) * height, -(wp.x - px) * width
        distance = math.sqrt(dx * dx + dy * dy)
    else
        return nil
    end
    local facing = GetPlayerFacing and GetPlayerFacing()
    facing = ns.Plain(facing)
    if not facing then
        return nil, distance
    end
    local bearing = math.atan2(dy, dx) -- angle of the target from north, counter clockwise
    local relative = bearing - facing
    return relative, distance
end

-- Arrow frame ---------------------------------------------------------------

local arrow

function Waypoint:GetArrow()
    if arrow then
        return arrow
    end
    arrow = CreateFrame("Frame", "BIGARMSWaypointArrow", UIParent)
    arrow:SetSize(56, 56)
    arrow:SetFrameStrata("MEDIUM")
    arrow:EnableMouse(true)
    arrow:SetMovable(true)
    arrow:RegisterForDrag("LeftButton")
    arrow:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    arrow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, _, y = self:GetPoint(1)
        if y then
            Waypoint.db.arrowY = math.floor(y)
        end
    end)
    arrow:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            Waypoint:Clear()
        end
    end)
    arrow.texture = arrow:CreateTexture(nil, "ARTWORK")
    arrow.texture:SetAllPoints()
    arrow.texture:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
    arrow.title = arrow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arrow.title:SetPoint("TOP", arrow, "BOTTOM", 0, -2)
    arrow.distance = arrow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow.distance:SetPoint("TOP", arrow.title, "BOTTOM", 0, -2)
    self:LayoutArrow()
    return arrow
end

function Waypoint:LayoutArrow()
    if arrow then
        arrow:ClearAllPoints()
        arrow:SetPoint("CENTER", UIParent, "CENTER", 0, tonumber(self.db.arrowY) or 220)
    end
end

function Waypoint:UpdateArrow()
    local wp = ns.char.waypoint
    if not wp or not self.db.arrow then
        if arrow then
            arrow:Hide()
        end
        if self.ticker then
            self.ticker:Cancel()
            self.ticker = nil
        end
        return
    end
    local frame = self:GetArrow()
    local relative, distance = self:Bearing()
    frame:Show()
    frame.title:SetText(wp.title or ("%.1f, %.1f"):format(wp.x * 100, wp.y * 100))
    if relative then
        frame.texture:SetRotation(relative)
        frame.texture:SetVertexColor(1, 1, 1)
    else
        frame.texture:SetRotation(0)
        frame.texture:SetVertexColor(0.5, 0.5, 0.5)
    end
    if distance then
        frame.distance:SetText(L.WP_DISTANCE:format(distance))
        if self.db.autoClear and distance <= (tonumber(self.db.arriveDistance) or 15) then
            self:Print(L.WP_ARRIVED)
            PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
            self:Clear()
        end
    else
        frame.distance:SetText(L.WP_OTHER_MAP)
    end
end

-- Game pin -------------------------------------------------------------------------

function Waypoint:SetGamePin(wp)
    if not self.db.gamePin or not (C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
        return
    end
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(wp.mapID) then
        return
    end
    local ok = pcall(C_Map.SetUserWaypoint, UiMapPoint.CreateFromCoordinates(wp.mapID, wp.x, wp.y))
    if ok and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
end

function Waypoint:ClearGamePin()
    if C_Map and C_Map.ClearUserWaypoint then
        pcall(C_Map.ClearUserWaypoint)
    end
end

-- Commands -------------------------------------------------------------------------------

function Waypoint:Set(mapID, x, y, title)
    if not mapID then
        mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    end
    if not mapID then
        self:Print(L.WP_NO_MAP)
        return
    end
    ns.char.waypoint = { mapID = mapID, x = x / 100, y = y / 100, title = title }
    self:SetGamePin(ns.char.waypoint)
    self:Print(L.WP_SET:format(x, y, title or ""))
    self:Start()
end

function Waypoint:Clear()
    ns.char.waypoint = nil
    self:ClearGamePin()
    self:UpdateArrow()
end

function Waypoint:HandleCommand(args)
    local lower = ns.Trim(args):lower()
    if lower == "" or lower == "help" then
        self:Print(L.WP_USAGE)
        return
    end
    if lower == "clear" or lower == "reset" or lower == "off" or lower == "삭제" then
        self:Clear()
        self:Print(L.WP_CLEARED)
        return
    end
    local mapID, x, y, title = ns.ParseWaypoint(args)
    if not x then
        self:Print(L.WP_USAGE)
        return
    end
    self:Set(mapID, x, y, title)
end

function Waypoint:Start()
    if ns.char.waypoint and self.db.arrow and not self.ticker then
        self.ticker = self:Ticker(0.1, self.UpdateArrow)
    end
    self:UpdateArrow()
end

function Waypoint:OnEnable()
    if not self.slashRegistered then
        self.slashRegistered = true
        if not SlashCmdList["TOMTOM_WAY"] and not SlashCmdList["BIGARMS_WAY"] then
            SLASH_BIGARMS_WAY1 = "/way"
            SLASH_BIGARMS_WAY2 = "/좌표"
            SlashCmdList["BIGARMS_WAY"] = function(msg)
                if Waypoint.enabled then
                    Waypoint:HandleCommand(msg)
                end
            end
        end
    end
    self:Start()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function(module) module:After(1, module.Start) end)
end

function Waypoint:OnDisable()
    if arrow then
        arrow:Hide()
    end
end

function Waypoint:OnSettingChanged()
    self:LayoutArrow()
    self:Start()
end
