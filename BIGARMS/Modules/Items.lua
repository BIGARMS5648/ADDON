local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Items: item levels in bags and on the character, already-known marks,
-- free bag slot counter
--------------------------------------------------------------------------

local Items = ns:NewModule("Items", {
    group = "ITEMS",
    needsReload = true,
    defaults = { enabled = true, bagItemLevel = true, characterItemLevel = true, alreadyKnown = true, freeSlots = true, minLevel = 1 },
    options = {
        { key = "bagItemLevel", type = "toggle", label = "IT_BAG_ILVL" },
        { key = "characterItemLevel", type = "toggle", label = "IT_CHAR_ILVL" },
        { key = "alreadyKnown", type = "toggle", label = "IT_KNOWN", tooltip = "IT_KNOWN_TT" },
        { key = "freeSlots", type = "toggle", label = "IT_FREE_SLOTS", tooltip = "IT_FREE_SLOTS_TT" },
    },
})

local EQUIP_LOCS = {
    INVTYPE_HEAD = true, INVTYPE_NECK = true, INVTYPE_SHOULDER = true, INVTYPE_BODY = false, INVTYPE_CHEST = true,
    INVTYPE_ROBE = true, INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true,
    INVTYPE_HAND = true, INVTYPE_FINGER = true, INVTYPE_TRINKET = true, INVTYPE_CLOAK = true, INVTYPE_WEAPON = true,
    INVTYPE_SHIELD = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true, INVTYPE_WEAPONOFFHAND = true,
    INVTYPE_HOLDABLE = true, INVTYPE_RANGED = true, INVTYPE_THROWN = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_RELIC = true,
}

-- Item level of a gear link, nil for anything that is not gear.
function ns.GearItemLevel(link)
    if not link or not C_Item or not C_Item.GetItemInfo then
        return nil
    end
    local _, _, quality, baseLevel, _, _, _, _, equipLoc = C_Item.GetItemInfo(link)
    if not EQUIP_LOCS[equipLoc] then
        return nil
    end
    local level = baseLevel
    if C_Item.GetDetailedItemLevelInfo then
        level = ns.Plain(C_Item.GetDetailedItemLevelInfo(link)) or baseLevel
    end
    level = ns.Plain(level)
    if not level or level <= 1 then
        return nil
    end
    return level, ns.Plain(quality)
end

local function LevelText(button)
    if not button.bigarmsLevel then
        local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        text:SetPoint("TOPLEFT", button, "TOPLEFT", 2, -2)
        text:SetJustifyH("LEFT")
        button.bigarmsLevel = text
    end
    return button.bigarmsLevel
end

local function SetLevel(button, link)
    local level, quality = link and ns.GearItemLevel(link)
    if level then
        local text = LevelText(button)
        local r, g, b = 1, 1, 1
        if quality and C_Item.GetItemQualityColor then
            local qr, qg, qb = C_Item.GetItemQualityColor(quality)
            if qr then
                r, g, b = qr, qg, qb
            end
        end
        text:SetTextColor(r, g, b)
        text:SetText(level)
        text:Show()
    elseif button.bigarmsLevel then
        button.bigarmsLevel:Hide()
    end
end

-- Bags ------------------------------------------------------------------------

function Items:UpdateBagButton(button)
    if not self.db.bagItemLevel then
        if button.bigarmsLevel then
            button.bigarmsLevel:Hide()
        end
        return
    end
    local bag = button.GetBagID and button:GetBagID() or (button:GetParent() and button:GetParent().GetID and button:GetParent():GetID())
    local slot = button.GetID and button:GetID()
    if not bag or not slot or not C_Container or not C_Container.GetContainerItemInfo then
        return
    end
    local info = C_Container.GetContainerItemInfo(bag, slot)
    SetLevel(button, info and info.hyperlink)
end

function Items:UpdateContainer(frame)
    if not frame then
        return
    end
    if frame.EnumerateValidItems then
        for _, button in frame:EnumerateValidItems() do
            pcall(self.UpdateBagButton, self, button)
        end
    elseif frame.Items then
        for _, button in ipairs(frame.Items) do
            pcall(self.UpdateBagButton, self, button)
        end
    end
end

function Items:HookBags()
    if self.bagsHooked then
        return
    end
    self.bagsHooked = true
    local module = self
    local function AfterUpdate(frame)
        if module.enabled then
            module:UpdateContainer(frame)
        end
    end
    local hookedAny = false
    for i = 1, (NUM_CONTAINER_FRAMES or 13) do
        local frame = _G["ContainerFrame" .. i]
        if frame and frame.UpdateItems then
            hooksecurefunc(frame, "UpdateItems", AfterUpdate)
            hookedAny = true
        end
    end
    if ContainerFrameCombinedBags and ContainerFrameCombinedBags.UpdateItems then
        hooksecurefunc(ContainerFrameCombinedBags, "UpdateItems", AfterUpdate)
        hookedAny = true
    end
    if not hookedAny and ContainerFrame_Update then
        hooksecurefunc("ContainerFrame_Update", AfterUpdate)
    end
end

-- Character frame ---------------------------------------------------------------

local CHARACTER_SLOTS = {
    "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged",
}

function Items:UpdateCharacter()
    for _, name in ipairs(CHARACTER_SLOTS) do
        local button = _G["Character" .. name .. "Slot"]
        if button then
            if self.db.characterItemLevel and GetInventoryItemLink then
                local slot = button.GetID and button:GetID()
                local link = slot and GetInventoryItemLink("player", slot)
                SetLevel(button, link)
            elseif button.bigarmsLevel then
                button.bigarmsLevel:Hide()
            end
        end
    end
end

function Items:HookCharacter()
    if self.charHooked then
        return
    end
    self.charHooked = true
    local module = self
    if CharacterFrame then
        self:HookScript(CharacterFrame, "OnShow", function() module:UpdateCharacter() end)
    end
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", function()
        if CharacterFrame and CharacterFrame:IsShown() then
            module:UpdateCharacter()
        end
    end)
end

-- Already known (merchant) ------------------------------------------------------------

local function MerchantItemKnown(index)
    if not (C_TooltipInfo and C_TooltipInfo.GetMerchantItem) then
        return false
    end
    local ok, data = pcall(C_TooltipInfo.GetMerchantItem, index)
    if not ok or not data or not data.lines then
        return false
    end
    local known = ITEM_SPELL_KNOWN
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and not ns.IsSecret(text) and (text == known) then
            return true
        end
    end
    return false
end

function Items:UpdateMerchant()
    if not MerchantFrame or not MerchantFrame:IsShown() then
        return
    end
    if MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then
        return
    end
    local perPage = MERCHANT_ITEMS_PER_PAGE or 10
    local page = MerchantFrame.page or 1
    for i = 1, perPage do
        local button = _G["MerchantItem" .. i .. "ItemButton"]
        local icon = button and (button.icon or _G["MerchantItem" .. i .. "ItemButtonIconTexture"])
        if button and icon and button:IsShown() then
            local index = (page - 1) * perPage + i
            if self.db.alreadyKnown and MerchantItemKnown(index) then
                icon:SetVertexColor(0.4, 1, 0.4)
                button.bigarmsKnown = true
            elseif button.bigarmsKnown then
                button.bigarmsKnown = nil
                icon:SetVertexColor(1, 1, 1)
            end
        end
    end
end

function Items:HookMerchant()
    if self.merchantHooked then
        return
    end
    self.merchantHooked = true
    local module = self
    if MerchantFrame_UpdateMerchantInfo then
        hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
            if module.enabled then
                module:UpdateMerchant()
            end
        end)
    end
    if MerchantFrame_Update then
        hooksecurefunc("MerchantFrame_Update", function()
            if module.enabled then
                module:UpdateMerchant()
            end
        end)
    end
end

-- Free bag slots ------------------------------------------------------------------------

function Items:ApplyFreeSlots()
    if ns.CVarExists("displayFreeBagSlots") then
        ns.SetCVar("displayFreeBagSlots", self.db.freeSlots and 1 or 0)
    end
end

-- Setup -------------------------------------------------------------------------------------

function Items:OnEnable()
    self:HookBags()
    self:HookCharacter()
    self:HookMerchant()
    self:ApplyFreeSlots()
end

function Items:OnSettingChanged()
    self:ApplyFreeSlots()
    self:UpdateCharacter()
    self:UpdateMerchant()
end
