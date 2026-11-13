local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- World map: coordinates and a few hidden map settings
--------------------------------------------------------------------------

local WorldMap = ns:NewModule("WorldMap", {
    group = "MAP",
    defaults = { enabled = true, playerCoords = "ON", cursorCoords = "ON", dungeonEntrances = "KEEP", ownCoords = true },
    options = {
        { key = "playerCoords", type = "select", label = "WM_PLAYER_COORDS", cvar = "worldMapShowPlayerCoords", choices = "ONOFF" },
        { key = "cursorCoords", type = "select", label = "WM_CURSOR_COORDS", cvar = "worldMapShowCursorCoords", choices = "ONOFF" },
        { key = "dungeonEntrances", type = "select", label = "WM_ENTRANCES", cvar = "showDungeonEntrancesOnMap", choices = "ONOFF" },
        { key = "ownCoords", type = "toggle", label = "WM_OWN_COORDS", tooltip = "WM_OWN_COORDS_TT" },
    },
})

local coordText

function WorldMap:CreateText()
    if coordText or not WorldMapFrame then
        return
    end
    local parent = WorldMapFrame.BorderFrame or WorldMapFrame
    local holder = CreateFrame("Frame", "BIGARMSWorldMapCoords", parent)
    holder:SetSize(220, 16)
    holder:SetPoint("TOP", parent, "TOP", 0, -4)
    holder:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 10)
    coordText = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    coordText:SetAllPoints()
    coordText:SetJustifyH("CENTER")
    holder.text = coordText
end

-- Cursor position on the map canvas in map coordinates (0-1), or nil.
local function CursorMapPosition()
    local canvas = WorldMapFrame and WorldMapFrame.ScrollContainer
    if not canvas or not canvas.GetNormalizedCursorPosition then
        return nil
    end
    local ok, x, y = pcall(canvas.GetNormalizedCursorPosition, canvas)
    if ok and x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 then
        return x, y
    end
    return nil
end

function WorldMap:Update()
    if not coordText or not WorldMapFrame or not WorldMapFrame:IsShown() then
        return
    end
    if not self.db.ownCoords or ns.CVarExists("worldMapShowPlayerCoords") then
        coordText:GetParent():Hide()
        return
    end
    coordText:GetParent():Show()
    local parts = {}
    local mapID, px, py = ns.PlayerMapPosition()
    if px and mapID == (WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()) then
        parts[#parts + 1] = L.WM_PLAYER:format(px * 100, py * 100)
    end
    local cx, cy = CursorMapPosition()
    if cx then
        parts[#parts + 1] = L.WM_CURSOR:format(cx * 100, cy * 100)
    end
    coordText:SetText(table.concat(parts, "   "))
end

function WorldMap:OnEnable()
    ns.ApplyCVarOptions(self)
    self:CreateText()
    if WorldMapFrame and not self.hooked then
        self.hooked = true
        self:HookScript(WorldMapFrame, "OnShow", function(module)
            module:Update()
            if not module.ticker then
                module.ticker = module:Ticker(0.2, module.Update)
            end
        end)
        self:HookScript(WorldMapFrame, "OnHide", function(module)
            if module.ticker then
                module.ticker:Cancel()
                module.ticker = nil
            end
        end)
    end
end

function WorldMap:OnDisable()
    if coordText then
        coordText:GetParent():Hide()
    end
end

function WorldMap:OnSettingChanged()
    ns.ApplyCVarOptions(self)
    self:Update()
end
