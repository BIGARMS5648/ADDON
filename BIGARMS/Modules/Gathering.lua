local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Gathering map: remembers every herb, vein and fishing spot you gather
-- and shows them on the world map and the minimap.
--------------------------------------------------------------------------

local Gathering = ns:NewModule("Gathering", {
    group = "MAP",
    defaults = { enabled = true, worldMap = true, minimap = true, minimapRange = 1, edge = false },
    options = {
        { key = "worldMap", type = "toggle", label = "GM_WORLDMAP" },
        { key = "minimap", type = "toggle", label = "GM_MINIMAP" },
        { key = "edge", type = "toggle", label = "GM_EDGE", tooltip = "GM_EDGE_TT" },
        { type = "button", label = "GM_CLEAR", button = "RESET", func = function() ns:GetModule("Gathering"):Clear() end },
        { type = "description", text = "GM_HELP" },
    },
})
ns.Gathering = Gathering

local KIND_ICONS = {
    HERB = "Interface\\Icons\\INV_Misc_Flower_02",
    ORE = "Interface\\Icons\\INV_Ore_Copper_01",
    FISH = "Interface\\Icons\\INV_Misc_Fish_02",
    OTHER = "Interface\\Icons\\INV_Misc_Bag_10",
}

-- base spell IDs; ranks share the name
local GATHER_SPELLS = {
    HERB = { 2366, 2368, 3570, 11993 },
    ORE = { 2575, 2576, 3564, 10248 },
    FISH = { 7620, 7731, 7732, 18248 },
}

function Gathering:SpellKinds()
    if self.kinds then
        return self.kinds
    end
    self.kinds = {}
    if C_Spell and C_Spell.GetSpellName then
        for kind, ids in pairs(GATHER_SPELLS) do
            for _, id in ipairs(ids) do
                local name = C_Spell.GetSpellName(id)
                if name then
                    self.kinds[name] = kind
                end
            end
        end
    end
    return self.kinds
end

-- Data ----------------------------------------------------------------------

local MERGE_DISTANCE = 0.004 -- map units (about 2-4 yards on a zone map)

function ns.AddGatherNode(mapID, x, y, name, kind)
    local nodes = ns.db.nodes
    for _, node in ipairs(nodes) do
        if node.mapID == mapID and math.abs(node.x - x) < MERGE_DISTANCE and math.abs(node.y - y) < MERGE_DISTANCE then
            node.name, node.kind, node.time = name, kind, time()
            return node, false
        end
    end
    local node = { mapID = mapID, x = x, y = y, name = name, kind = kind, time = time() }
    nodes[#nodes + 1] = node
    while #nodes > 4000 do
        table.remove(nodes, 1)
    end
    return node, true
end

function Gathering:Record(name, kind)
    local mapID, x, y = ns.PlayerMapPosition()
    if not mapID then
        return
    end
    local _, new = ns.AddGatherNode(mapID, x, y, name, kind)
    if new then
        ns.Debug("node", name, kind, mapID, x, y)
    end
    self:RefreshWorldMap()
end

function Gathering:Clear()
    wipe(ns.db.nodes)
    self:RefreshWorldMap()
    self:Print(L.GM_CLEARED)
end

-- Spell tracking ------------------------------------------------------------------

function Gathering:OnSent(_, unit, target, _, spellID)
    if unit ~= "player" then
        return
    end
    spellID = ns.Plain(spellID)
    local name = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    local kind = name and self:SpellKinds()[name]
    if kind then
        self.pending = { kind = kind, target = ns.Plain(target), spell = name, time = GetTime() }
    end
end

function Gathering:OnSucceeded(_, unit, _, spellID)
    if unit ~= "player" or not self.pending then
        return
    end
    spellID = ns.Plain(spellID)
    local name = spellID and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if name ~= self.pending.spell or GetTime() - self.pending.time > 15 then
        return
    end
    local pending = self.pending
    self.pending = nil
    local nodeName = pending.target
    if not nodeName or nodeName == "" then
        nodeName = pending.kind == "FISH" and L.GM_FISHING or pending.spell
    end
    self:Record(nodeName, pending.kind)
end

-- World map pins ----------------------------------------------------------------------

BIGARMSGatherPinMixin = CreateFromMixins and CreateFromMixins(MapCanvasPinMixin or {}) or {}

function BIGARMSGatherPinMixin:OnLoad()
    if self.SetScalingLimits then
        self:SetScalingLimits(1, 1.0, 1.2)
    end
    if self.UseFrameLevelType then
        self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
    end
end

function BIGARMSGatherPinMixin:OnAcquired(node)
    self.node = node
    self.Icon:SetTexture(KIND_ICONS[node.kind] or KIND_ICONS.OTHER)
    if self.SetPosition then
        self:SetPosition(node.x, node.y)
    end
end

function BIGARMSGatherPinMixin:OnMouseEnter()
    if not self.node then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.node.name or "?")
    local age = (time() - (self.node.time or 0)) / 3600
    GameTooltip:AddLine(L.GM_SEEN:format(age < 1 and L.GM_RECENT or ns.FormatHours(age)), 0.8, 0.8, 0.8)
    GameTooltip:Show()
end

function BIGARMSGatherPinMixin:OnMouseLeave()
    GameTooltip:Hide()
end

BIGARMSGatherDataProvider = CreateFromMixins and CreateFromMixins(MapCanvasDataProviderMixin or {}) or {}

function BIGARMSGatherDataProvider:RemoveAllData()
    local map = self:GetMap()
    if map and map.RemoveAllPinsByTemplate then
        map:RemoveAllPinsByTemplate("BIGARMSGatherPinTemplate")
    end
end

function BIGARMSGatherDataProvider:RefreshAllData()
    self:RemoveAllData()
    local module = ns:GetModule("Gathering")
    if not module or not module.enabled or not module.db.worldMap then
        return
    end
    local map = self:GetMap()
    local mapID = map and map.GetMapID and map:GetMapID()
    if not mapID or not map.AcquirePin then
        return
    end
    for _, node in ipairs(ns.db.nodes) do
        if node.mapID == mapID then
            map:AcquirePin("BIGARMSGatherPinTemplate", node)
        end
    end
end

function Gathering:RegisterProvider()
    if self.provider or not WorldMapFrame or not WorldMapFrame.AddDataProvider then
        return
    end
    if not (CreateFromMixins and MapCanvasDataProviderMixin) then
        return
    end
    local ok, provider = pcall(CreateFromMixins, BIGARMSGatherDataProvider)
    if ok and provider then
        local added = pcall(WorldMapFrame.AddDataProvider, WorldMapFrame, provider)
        if added then
            self.provider = provider
        end
    end
end

function Gathering:RefreshWorldMap()
    if self.provider and WorldMapFrame and WorldMapFrame:IsShown() then
        pcall(self.provider.RefreshAllData, self.provider)
    end
end

-- Minimap pins --------------------------------------------------------------------------

-- minimap diameter in yards per zoom level (from HereBeDragons)
local MINIMAP_YARDS = {
    outdoor = { 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 6, 200, 133 + 1 / 3 },
    indoor = { 300, 240, 180, 120, 80, 50 },
}

local function MinimapYards()
    local zoom = Minimap and Minimap.GetZoom and Minimap:GetZoom() or 0
    local inside = tonumber(ns.GetCVar("minimapInsideZoom"))
    local outside = tonumber(ns.GetCVar("minimapZoom"))
    local indoors = inside ~= nil and inside == zoom and outside ~= zoom
    local table_ = indoors and MINIMAP_YARDS.indoor or MINIMAP_YARDS.outdoor
    return (table_[zoom + 1] or table_[1]) / 2
end

local function WorldXY(mapID, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then
        return nil
    end
    local ok, _, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
    if ok and pos then
        local wx, wy = pos:GetXY()
        return ns.Plain(wx), ns.Plain(wy)
    end
end

-- Screen offset (pixels from the minimap center) of a node, or nil when off the map.
function ns.MinimapOffset(playerWX, playerWY, nodeWX, nodeWY, radiusYards, pixelRadius, facing, clampToEdge, square)
    local dx = -(nodeWY - playerWY) -- east is -y in world space
    local dy = nodeWX - playerWX -- north is +x
    if facing then
        local cosF, sinF = math.cos(facing), math.sin(facing)
        dx, dy = dx * cosF - dy * sinF, dx * sinF + dy * cosF
    end
    local scale = pixelRadius / radiusYards
    local px, py = dx * scale, dy * scale
    local distance = math.sqrt(px * px + py * py)
    if square then
        if math.max(math.abs(px), math.abs(py)) > pixelRadius then
            if not clampToEdge then
                return nil
            end
            local factor = pixelRadius / math.max(math.abs(px), math.abs(py))
            px, py = px * factor, py * factor
        end
    elseif distance > pixelRadius then
        if not clampToEdge then
            return nil
        end
        px, py = px / distance * pixelRadius, py / distance * pixelRadius
    end
    return px, py
end

function Gathering:MinimapPin(i)
    self.pins = self.pins or {}
    local pin = self.pins[i]
    if not pin then
        pin = CreateFrame("Frame", nil, Minimap)
        pin:SetSize(12, 12)
        pin:SetFrameLevel((Minimap.GetFrameLevel and Minimap:GetFrameLevel() or 1) + 3)
        pin.icon = pin:CreateTexture(nil, "OVERLAY")
        pin.icon:SetAllPoints()
        pin:EnableMouse(true)
        pin:SetScript("OnEnter", function(self_)
            if self_.node then
                GameTooltip:SetOwner(self_, "ANCHOR_LEFT")
                GameTooltip:SetText(self_.node.name or "?")
                GameTooltip:Show()
            end
        end)
        pin:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self.pins[i] = pin
    end
    return pin
end

function Gathering:UpdateMinimap()
    if not self.db.minimap or not Minimap then
        self:HideMinimapPins()
        return
    end
    local mapID, px, py = ns.PlayerMapPosition()
    if not mapID then
        self:HideMinimapPins()
        return
    end
    local playerWX, playerWY = WorldXY(mapID, px, py)
    if not playerWX then
        self:HideMinimapPins()
        return
    end
    local radiusYards = MinimapYards()
    local pixelRadius = Minimap:GetWidth() / 2
    local facing = nil
    if ns.GetCVarBool("rotateMinimap") and GetPlayerFacing then
        facing = ns.Plain(GetPlayerFacing())
    end
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    local used = 0
    for _, node in ipairs(ns.db.nodes) do
        if node.mapID == mapID then
            if not node.wx then
                node.wx, node.wy = WorldXY(mapID, node.x, node.y)
            end
            if node.wx then
                local ox, oy = ns.MinimapOffset(playerWX, playerWY, node.wx, node.wy, radiusYards, pixelRadius, facing, self.db.edge, square)
                if ox then
                    used = used + 1
                    local pin = self:MinimapPin(used)
                    pin.node = node
                    pin.icon:SetTexture(KIND_ICONS[node.kind] or KIND_ICONS.OTHER)
                    pin:ClearAllPoints()
                    pin:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
                    pin:Show()
                    if used >= 60 then
                        break
                    end
                end
            end
        end
    end
    for i = used + 1, #(self.pins or {}) do
        self.pins[i]:Hide()
    end
end

function Gathering:HideMinimapPins()
    for _, pin in ipairs(self.pins or {}) do
        pin:Hide()
    end
end

-- Setup ----------------------------------------------------------------------------------

function Gathering:OnEnable()
    self:RegisterProvider()
    self:RegisterEvent("UNIT_SPELLCAST_SENT", "OnSent")
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSucceeded")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function(module)
        for _, node in ipairs(ns.db.nodes) do
            node.wx, node.wy = nil, nil
        end
    end)
    self:Ticker(0.5, self.UpdateMinimap)
    if WorldMapFrame and not self.mapHooked then
        self.mapHooked = true
        self:HookScript(WorldMapFrame, "OnShow", function(module) module:RefreshWorldMap() end)
    end
end

function Gathering:OnDisable()
    self:HideMinimapPins()
    if self.provider then
        pcall(self.provider.RemoveAllData, self.provider)
    end
end

function Gathering:OnSettingChanged()
    self:RefreshWorldMap()
    self:UpdateMinimap()
end
