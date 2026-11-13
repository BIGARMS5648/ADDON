local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Cursor ring: a glowing ring that follows the mouse
--------------------------------------------------------------------------

local CursorRing = ns:NewModule("CursorRing", {
    group = "INTERFACE",
    defaults = { enabled = false, combatOnly = false, size = 40, alpha = 0.6 },
    options = {
        { key = "combatOnly", type = "toggle", label = "CR_COMBAT_ONLY" },
        { key = "size", type = "range", label = "CR_SIZE", min = 16, max = 128, step = 4, format = "%d" },
        { key = "alpha", type = "range", label = "CR_ALPHA", min = 0.1, max = 1, step = 0.1, format = "%.1f" },
    },
})

local ring

function CursorRing:GetRing()
    if ring then
        return ring
    end
    ring = CreateFrame("Frame", "BIGARMSCursorRing", UIParent)
    ring:SetFrameStrata("TOOLTIP")
    ring.texture = ring:CreateTexture(nil, "OVERLAY")
    ring.texture:SetAllPoints()
    ring.texture:SetTexture("Interface\\Cooldown\\ping4")
    ring.texture:SetVertexColor(1, 0.8, 0.2)
    ring:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end)
    return ring
end

function CursorRing:Apply()
    local frame = self:GetRing()
    frame:SetSize(tonumber(self.db.size) or 40, tonumber(self.db.size) or 40)
    frame:SetAlpha(tonumber(self.db.alpha) or 0.6)
    if self.db.combatOnly and not InCombatLockdown() then
        frame:Hide()
    else
        frame:Show()
    end
end

function CursorRing:OnEnable()
    self:Apply()
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "Apply")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "Apply")
end

function CursorRing:OnDisable()
    if ring then
        ring:Hide()
    end
end

function CursorRing:OnSettingChanged()
    self:Apply()
end

--------------------------------------------------------------------------
-- Performance: frame rate and latency text
--------------------------------------------------------------------------

local Performance = ns:NewModule("Performance", {
    group = "INTERFACE",
    defaults = { enabled = true, x = -20, y = 20, worldLatency = true },
    options = {
        { key = "worldLatency", type = "toggle", label = "PF_WORLD", tooltip = "PF_WORLD_TT" },
        { type = "description", text = "PF_HELP" },
    },
})

local perfFrame

function ns.PerformanceText(fps, home, world, showWorld)
    local fpsColor = fps >= 50 and "40ff40" or fps >= 25 and "ffd040" or "ff4040"
    local latency = showWorld and math.max(home or 0, world or 0) or (home or 0)
    local msColor = latency <= 100 and "40ff40" or latency <= 250 and "ffd040" or "ff4040"
    return ("|cff%s%d|r fps  |cff%s%d|r ms"):format(fpsColor, fps, msColor, latency)
end

function Performance:GetFrame()
    if perfFrame then
        return perfFrame
    end
    perfFrame = CreateFrame("Frame", "BIGARMSPerformance", UIParent)
    perfFrame:SetSize(120, 16)
    perfFrame:EnableMouse(true)
    perfFrame:SetMovable(true)
    perfFrame:RegisterForDrag("LeftButton")
    perfFrame:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    perfFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint(1)
        if x and y then
            Performance.db.x, Performance.db.y = math.floor(x), math.floor(y)
        end
    end)
    perfFrame.text = perfFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    perfFrame.text:SetAllPoints()
    perfFrame.text:SetJustifyH("RIGHT")
    perfFrame:ClearAllPoints()
    perfFrame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", tonumber(self.db.x) or -20, tonumber(self.db.y) or 20)
    return perfFrame
end

function Performance:Update()
    local frame = self:GetFrame()
    local fps = GetFramerate and math.floor(GetFramerate() + 0.5) or 0
    local home, world = 0, 0
    if GetNetStats then
        local _, _, h, w = GetNetStats()
        home, world = ns.Plain(h) or 0, ns.Plain(w) or 0
    end
    frame.text:SetText(ns.PerformanceText(fps, home, world, self.db.worldLatency))
end

function Performance:OnEnable()
    self:GetFrame():Show()
    self:Update()
    self:Ticker(1, self.Update)
end

function Performance:OnDisable()
    if perfFrame then
        perfFrame:Hide()
    end
end

--------------------------------------------------------------------------
-- Compass bar at the top of the screen
--------------------------------------------------------------------------

local Compass = ns:NewModule("Compass", {
    group = "MAP",
    defaults = { enabled = false, width = 400, y = -20, fov = 180 },
    options = {
        { key = "width", type = "range", label = "CP_WIDTH", min = 200, max = 1000, step = 20, format = "%d" },
        { key = "y", type = "range", label = "CP_Y", min = -300, max = 0, step = 5, format = "%d" },
        { key = "fov", type = "range", label = "CP_FOV", tooltip = "CP_FOV_TT", min = 90, max = 360, step = 10, format = "%d°" },
    },
})

-- compass directions as facing angles (0 = north, counter clockwise)
local DIRECTIONS = {
    { "N", 0 }, { "NW", math.pi / 4 }, { "W", math.pi / 2 }, { "SW", 3 * math.pi / 4 },
    { "S", math.pi }, { "SE", 5 * math.pi / 4 }, { "E", 3 * math.pi / 2 }, { "NE", 7 * math.pi / 4 },
}

-- Horizontal position (pixels from center) of a direction, nil when outside the field of view.
function ns.CompassOffset(directionAngle, facing, width, fovDegrees)
    local relative = directionAngle - facing
    while relative > math.pi do relative = relative - 2 * math.pi end
    while relative < -math.pi do relative = relative + 2 * math.pi end
    local half = math.rad(fovDegrees) / 2
    if math.abs(relative) > half then
        return nil
    end
    -- west (positive relative angle) is on the left of the screen
    return -relative / half * (width / 2)
end

local compass

function Compass:GetFrame()
    if compass then
        return compass
    end
    compass = CreateFrame("Frame", "BIGARMSCompass", UIParent)
    compass:SetHeight(24)
    compass.line = compass:CreateTexture(nil, "BACKGROUND")
    compass.line:SetHeight(1)
    compass.line:SetPoint("BOTTOMLEFT")
    compass.line:SetPoint("BOTTOMRIGHT")
    compass.line:SetColorTexture(1, 1, 1, 0.4)
    compass.center = compass:CreateTexture(nil, "ARTWORK")
    compass.center:SetSize(2, 10)
    compass.center:SetPoint("BOTTOM", compass, "BOTTOM", 0, 0)
    compass.center:SetColorTexture(1, 0.8, 0.2, 1)
    compass.labels = {}
    for i, direction in ipairs(DIRECTIONS) do
        local label = compass:CreateFontString(nil, "OVERLAY", #direction[1] == 1 and "GameFontNormal" or "GameFontHighlightSmall")
        label:SetText(direction[1])
        compass.labels[i] = label
    end
    compass.waypoint = compass:CreateTexture(nil, "OVERLAY")
    compass.waypoint:SetSize(12, 12)
    compass.waypoint:SetTexture("Interface\\Minimap\\MiniMap-QuestArrow")
    compass.waypoint:Hide()
    return compass
end

function Compass:Layout()
    local frame = self:GetFrame()
    frame:SetWidth(tonumber(self.db.width) or 400)
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "TOP", 0, tonumber(self.db.y) or -20)
end

function Compass:Update()
    local frame = self:GetFrame()
    local facing = GetPlayerFacing and ns.Plain(GetPlayerFacing())
    if not facing then
        frame:Hide()
        return
    end
    frame:Show()
    local width, fov = tonumber(self.db.width) or 400, tonumber(self.db.fov) or 180
    for i, direction in ipairs(DIRECTIONS) do
        local offset = ns.CompassOffset(direction[2], facing, width, fov)
        local label = frame.labels[i]
        if offset then
            label:ClearAllPoints()
            label:SetPoint("BOTTOM", frame, "BOTTOM", offset, 4)
            label:Show()
        else
            label:Hide()
        end
    end
    local waypoint = ns.Waypoint and ns.Waypoint.enabled and ns.Waypoint:Bearing()
    if waypoint then
        local offset = ns.CompassOffset(waypoint + facing, facing, width, fov)
        if offset then
            frame.waypoint:ClearAllPoints()
            frame.waypoint:SetPoint("BOTTOM", frame, "BOTTOM", offset, 14)
            frame.waypoint:Show()
            return
        end
    end
    frame.waypoint:Hide()
end

function Compass:OnEnable()
    self:Layout()
    self:Ticker(0.05, self.Update)
end

function Compass:OnDisable()
    if compass then
        compass:Hide()
    end
end

function Compass:OnSettingChanged()
    self:Layout()
end

--------------------------------------------------------------------------
-- Flight timer: learns how long each flight path takes
--------------------------------------------------------------------------

local FlightTimer = ns:NewModule("FlightTimer", {
    group = "MAP",
    defaults = { enabled = true, y = 200 },
    options = {
        { key = "y", type = "range", label = "FT_Y", min = -300, max = 400, step = 10, format = "%d" },
        { type = "description", text = "FT_HELP" },
    },
})

local flightBar

function FlightTimer:GetBar()
    if flightBar then
        return flightBar
    end
    flightBar = CreateFrame("StatusBar", "BIGARMSFlightTimer", UIParent)
    flightBar:SetSize(260, 18)
    flightBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    flightBar:SetStatusBarColor(0.3, 0.6, 1)
    flightBar:SetMinMaxValues(0, 1)
    flightBar.bg = flightBar:CreateTexture(nil, "BACKGROUND")
    flightBar.bg:SetAllPoints()
    flightBar.bg:SetColorTexture(0, 0, 0, 0.6)
    flightBar.text = flightBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    flightBar.text:SetPoint("CENTER")
    flightBar:Hide()
    self:Layout()
    return flightBar
end

function FlightTimer:Layout()
    if flightBar then
        flightBar:ClearAllPoints()
        flightBar:SetPoint("CENTER", UIParent, "CENTER", 0, tonumber(self.db.y) or 200)
    end
end

local function CurrentNode()
    if not (NumTaxiNodes and TaxiNodeGetType and TaxiNodeName) then
        return nil
    end
    for i = 1, NumTaxiNodes() do
        if TaxiNodeGetType(i) == "CURRENT" then
            return TaxiNodeName(i)
        end
    end
end

function FlightTimer:OnTakeTaxi(index)
    local destination = TaxiNodeName and TaxiNodeName(index)
    local origin = CurrentNode()
    if not destination then
        return
    end
    self.pending = { origin = origin, destination = destination, time = GetTime() }
    self:After(1, self.Begin)
end

function FlightTimer:Begin()
    if not self.pending then
        return
    end
    if not (UnitOnTaxi and UnitOnTaxi("player")) then
        if GetTime() - self.pending.time < 10 then
            self:After(0.5, self.Begin)
        else
            self.pending = nil
        end
        return
    end
    local flight = self.pending
    self.pending = nil
    flight.start = GetTime()
    flight.key = (flight.origin or "?") .. "|" .. flight.destination
    flight.known = ns.db.flights[flight.key]
    self.flight = flight
    local bar = self:GetBar()
    bar:Show()
    self.ticker = self:Ticker(0.2, self.Update)
end

function FlightTimer:Update()
    local flight = self.flight
    if not flight then
        return
    end
    local elapsed = GetTime() - flight.start
    if not (UnitOnTaxi and UnitOnTaxi("player")) then
        self:Land(elapsed)
        return
    end
    local bar = self:GetBar()
    if flight.known and flight.known > 0 then
        bar:SetMinMaxValues(0, flight.known)
        bar:SetValue(math.min(elapsed, flight.known))
        local left = math.max(flight.known - elapsed, 0)
        bar.text:SetText(("%s  %d:%02d"):format(flight.destination, math.floor(left / 60), math.floor(left) % 60))
    else
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(1)
        bar.text:SetText(("%s  %d:%02d"):format(flight.destination, math.floor(elapsed / 60), math.floor(elapsed) % 60))
    end
end

function FlightTimer:Land(elapsed)
    local flight = self.flight
    self.flight = nil
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if flightBar then
        flightBar:Hide()
    end
    if flight and elapsed > 5 then
        ns.db.flights[flight.key] = math.floor(elapsed)
    end
end

function FlightTimer:OnEnable()
    if not self.hooked then
        self.hooked = true
        self:SecureHook("TakeTaxiNode", function(module, index)
            module:OnTakeTaxi(index)
        end)
    end
end

function FlightTimer:OnDisable()
    self:Land(0)
end

function FlightTimer:OnSettingChanged()
    self:Layout()
end

--------------------------------------------------------------------------
-- Error catcher: keeps Lua errors quietly, /ba errors shows them
--------------------------------------------------------------------------

local ErrorCatcher = ns:NewModule("ErrorCatcher", {
    group = "SYSTEM",
    defaults = { enabled = true, announce = true },
    options = {
        { key = "announce", type = "toggle", label = "EC_ANNOUNCE", tooltip = "EC_ANNOUNCE_TT" },
        { type = "button", label = "EC_SHOW", button = "SHOW", func = function() ns:GetModule("ErrorCatcher"):ShowWindow() end },
    },
})
ns.ErrorCatcher = ErrorCatcher

local MAX_ERRORS = 50

function ErrorCatcher:Record(message)
    message = tostring(message)
    local list = ns.db.errors
    for _, entry in ipairs(list) do
        if entry.message == message then
            entry.count = (entry.count or 1) + 1
            entry.time = time()
            return entry, false
        end
    end
    local entry = { message = message, count = 1, time = time() }
    list[#list + 1] = entry
    while #list > MAX_ERRORS do
        table.remove(list, 1)
    end
    self.session = (self.session or 0) + 1
    if self.db.announce and self.session <= 3 then
        self:Print(L.EC_CAUGHT:format(message:sub(1, 120)))
    end
    return entry, true
end

function ErrorCatcher:Install()
    if self.installed or not seterrorhandler or not geterrorhandler then
        return
    end
    self.installed = true
    local previous = geterrorhandler()
    local module = self
    seterrorhandler(function(message, ...)
        if module.enabled then
            pcall(module.Record, module, message)
        end
        if type(previous) == "function" then
            return previous(message, ...)
        end
    end)
end

local errorWindow

function ErrorCatcher:ShowWindow()
    if not errorWindow then
        errorWindow = CreateFrame("Frame", "BIGARMSErrors", UIParent, "BackdropTemplate")
        errorWindow:SetSize(600, 400)
        errorWindow:SetPoint("CENTER")
        errorWindow:SetFrameStrata("DIALOG")
        errorWindow:EnableMouse(true)
        errorWindow:SetMovable(true)
        errorWindow:RegisterForDrag("LeftButton")
        errorWindow:SetScript("OnDragStart", errorWindow.StartMoving)
        errorWindow:SetScript("OnDragStop", errorWindow.StopMovingOrSizing)
        if errorWindow.SetBackdrop then
            errorWindow:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 },
            })
        end
        local title = errorWindow:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", errorWindow, "TOP", 0, -12)
        title:SetText(L.EC_TITLE)
        local close = CreateFrame("Button", nil, errorWindow, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", errorWindow, "TOPRIGHT", 2, 2)
        local clear = CreateFrame("Button", nil, errorWindow, "UIPanelButtonTemplate")
        clear:SetSize(80, 20)
        clear:SetPoint("BOTTOMRIGHT", errorWindow, "BOTTOMRIGHT", -12, 10)
        clear:SetText(L.EC_CLEAR)
        clear:SetScript("OnClick", function()
            wipe(ns.db.errors)
            ErrorCatcher:ShowWindow()
        end)
        local scroll = CreateFrame("ScrollFrame", "BIGARMSErrorsScroll", errorWindow, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", errorWindow, "TOPLEFT", 16, -36)
        scroll:SetPoint("BOTTOMRIGHT", errorWindow, "BOTTOMRIGHT", -36, 36)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal or GameFontHighlight)
        edit:SetWidth(540)
        edit:SetScript("OnEscapePressed", function() errorWindow:Hide() end)
        scroll:SetScrollChild(edit)
        errorWindow.edit = edit
        tinsert(UISpecialFrames, "BIGARMSErrors")
    end
    local lines = {}
    for i = #ns.db.errors, 1, -1 do
        local entry = ns.db.errors[i]
        lines[#lines + 1] = ("[%s] x%d\n%s\n"):format(date and date("%m-%d %H:%M", entry.time) or "?", entry.count or 1, entry.message)
    end
    errorWindow.edit:SetText(#lines > 0 and table.concat(lines, "\n") or L.EC_NONE)
    errorWindow:Show()
end

function ErrorCatcher:HandleCommand(args)
    if ns.Trim(args):lower() == "clear" then
        wipe(ns.db.errors)
        self:Print(L.EC_CLEARED)
        return
    end
    self:ShowWindow()
end

function ErrorCatcher:OnEnable()
    self:Install()
end
