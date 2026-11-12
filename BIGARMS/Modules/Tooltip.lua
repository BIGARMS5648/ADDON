local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Tooltips: anchor, unit extras, item extras, spell IDs
--------------------------------------------------------------------------

local Tooltip = ns:NewModule("Tooltip", {
    group = "TOOLTIP",
    needsReload = true,
    defaults = {
        enabled = true,
        anchor = "DEFAULT", -- DEFAULT | CURSOR | CURSOR_RIGHT | CURSOR_LEFT
        hideInCombat = "OFF", -- OFF | UNITS | ALL
        scale = 1,
        classColorName = true,
        classBorder = true,
        guildRank = true,
        target = true,
        hideHealthBar = false,
        itemID = false,
        itemLevel = true,
        sellPrice = true,
        itemCount = true,
        qualityBorder = true,
        spellID = false,
    },
    options = {
        { type = "header", text = "TT_HEADER_GENERAL" },
        { key = "anchor", type = "select", label = "TT_ANCHOR", choices = function()
            return {
                { "DEFAULT", L.CHOICE_KEEP }, { "CURSOR", L.TT_ANCHOR_CURSOR },
                { "CURSOR_RIGHT", L.TT_ANCHOR_CURSOR_RIGHT }, { "CURSOR_LEFT", L.TT_ANCHOR_CURSOR_LEFT },
            }
        end },
        { key = "hideInCombat", type = "select", label = "TT_HIDE_COMBAT", tooltip = "TT_HIDE_COMBAT_TT", choices = function()
            return { { "OFF", L.CHOICE_OFF }, { "UNITS", L.TT_HIDE_UNITS }, { "ALL", L.TT_HIDE_ALL } }
        end },
        { key = "scale", type = "range", label = "TT_SCALE", min = 0.6, max = 1.6, step = 0.05, format = "%.2f" },
        { type = "header", text = "TT_HEADER_UNITS" },
        { key = "classColorName", type = "toggle", label = "TT_CLASS_NAME" },
        { key = "classBorder", type = "toggle", label = "TT_CLASS_BORDER", tooltip = "TT_CLASS_BORDER_TT" },
        { key = "guildRank", type = "toggle", label = "TT_GUILD_RANK" },
        { key = "target", type = "toggle", label = "TT_TARGET" },
        { key = "hideHealthBar", type = "toggle", label = "TT_HIDE_HEALTH" },
        { type = "header", text = "TT_HEADER_ITEMS" },
        { key = "itemLevel", type = "toggle", label = "TT_ITEM_LEVEL" },
        { key = "sellPrice", type = "toggle", label = "TT_SELL_PRICE", tooltip = "TT_SELL_PRICE_TT" },
        { key = "itemCount", type = "toggle", label = "TT_ITEM_COUNT" },
        { key = "qualityBorder", type = "toggle", label = "TT_QUALITY_BORDER" },
        { key = "itemID", type = "toggle", label = "TT_ITEM_ID" },
        { key = "spellID", type = "toggle", label = "TT_SPELL_ID" },
    },
})

local function SetBorderColor(tooltip, r, g, b)
    if tooltip.NineSlice and tooltip.NineSlice.SetBorderColor then
        tooltip.NineSlice:SetBorderColor(r, g, b)
    elseif tooltip.SetBackdropBorderColor then
        tooltip:SetBackdropBorderColor(r, g, b)
    end
end

local function ResetBorder(tooltip)
    if tooltip.bigarmsColored then
        tooltip.bigarmsColored = nil
        SetBorderColor(tooltip, 1, 1, 1)
    end
end

-- Anchor -------------------------------------------------------------------

function Tooltip:OnDefaultAnchor(tooltip, parent)
    local db = self.db
    if db.hideInCombat ~= "OFF" and InCombatLockdown() and not IsShiftKeyDown() then
        tooltip.bigarmsHideCombat = true
    else
        tooltip.bigarmsHideCombat = nil
    end
    if db.anchor == "CURSOR" then
        tooltip:SetOwner(parent, "ANCHOR_CURSOR")
    elseif db.anchor == "CURSOR_RIGHT" then
        tooltip:SetOwner(parent, "ANCHOR_CURSOR_RIGHT", 16, -8)
    elseif db.anchor == "CURSOR_LEFT" then
        tooltip:SetOwner(parent, "ANCHOR_CURSOR_LEFT", -16, -8)
    end
end

local function TooltipUnit(tooltip)
    local unit
    if TooltipUtil and TooltipUtil.GetDisplayedUnit then
        local ok, _, u = pcall(TooltipUtil.GetDisplayedUnit, tooltip)
        if ok then
            unit = u
        end
    end
    if not unit and tooltip.GetUnit then
        local ok, _, u = pcall(tooltip.GetUnit, tooltip)
        if ok then
            unit = u
        end
    end
    if unit and ns.IsSecret(unit) then
        return nil, true
    end
    return unit, false
end

function Tooltip:OnTooltipShow(tooltip)
    if tooltip.bigarmsHideCombat and InCombatLockdown() then
        local unit, secret = TooltipUnit(tooltip)
        if self.db.hideInCombat == "ALL" or unit or secret then
            tooltip:Hide()
            return
        end
    end
end

-- Units ------------------------------------------------------------------------

local function Colorize(text, r, g, b)
    return ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, text)
end

function Tooltip:OnUnitTooltip(tooltip, data)
    if tooltip ~= GameTooltip then
        return
    end
    local unit = TooltipUnit(tooltip)
    if not unit or not UnitExists or not UnitExists(unit) then
        return
    end
    local db = self.db
    local isPlayer = UnitIsPlayer(unit)
    local r, g, b = ns.UnitColor(unit)

    if db.classColorName and isPlayer then
        local line = _G[tooltip:GetName() .. "TextLeft1"]
        local name = UnitName(unit)
        if line and name and not ns.IsSecret(name) then
            local text = line:GetText()
            if type(text) == "string" and not ns.IsSecret(text) then
                line:SetText(Colorize(text, r, g, b))
            end
        end
    end

    if db.guildRank and isPlayer and GetGuildInfo then
        local guild, rank = GetGuildInfo(unit)
        if guild and rank and not ns.IsSecret(rank) then
            local line = _G[tooltip:GetName() .. "TextLeft2"]
            local text = line and line:GetText()
            if type(text) == "string" and text:find(guild, 1, true) then
                line:SetText(("<%s> |cffaaaaaa%s|r"):format(guild, rank))
            end
        end
    end

    if db.target then
        local targetUnit = unit .. "target"
        if UnitExists(targetUnit) then
            local targetName = UnitName(targetUnit)
            if targetName and not ns.IsSecret(targetName) then
                if UnitIsUnit(targetUnit, "player") then
                    targetName = Colorize(L.TT_YOU, 1, 0.3, 0.3)
                else
                    local tr, tg, tb = ns.UnitColor(targetUnit)
                    targetName = Colorize(targetName, tr, tg, tb)
                end
                tooltip:AddLine(L.TT_TARGET_LINE:format(targetName), 1, 1, 1)
            end
        end
    end

    if db.classBorder then
        SetBorderColor(tooltip, r, g, b)
        tooltip.bigarmsColored = true
    end

    if db.hideHealthBar and GameTooltipStatusBar then
        GameTooltipStatusBar:Hide()
    end
end

-- Items --------------------------------------------------------------------------

local function ItemLinkFromTooltip(tooltip, data)
    if data and data.hyperlink and not ns.IsSecret(data.hyperlink) then
        return data.hyperlink
    end
    if tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        if ok and link and not ns.IsSecret(link) then
            return link
        end
    end
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local ok, _, link = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if ok and link and not ns.IsSecret(link) then
            return link
        end
    end
end

local function TooltipStackCount(tooltip)
    -- bag item tooltips know their slot; use its stack size for the price
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    if owner and owner.count and type(owner.count) == "number" then
        return owner.count
    end
    if owner and owner.GetBagID and owner.GetID and C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, owner:GetBagID(), owner:GetID())
        if ok and info and info.stackCount then
            return info.stackCount
        end
    end
    return 1
end

function Tooltip:OnItemTooltip(tooltip, data)
    if tooltip.bigarmsItemDone then
        return
    end
    local db = self.db
    local link = ItemLinkFromTooltip(tooltip, data)
    if not link then
        return
    end
    local itemID = (data and ns.Plain(data.id)) or ns.GetItemIDFromLink(link)
    local name, _, quality, _, _, itemType, _, _, equipLoc, _, sellPrice, classID = C_Item.GetItemInfo(link)
    quality = ns.Plain(quality)
    sellPrice = ns.Plain(sellPrice)

    if db.itemLevel and equipLoc and equipLoc ~= "" and C_Item.GetDetailedItemLevelInfo then
        local level = ns.Plain(C_Item.GetDetailedItemLevelInfo(link))
        if level and level > 1 then
            tooltip:AddLine(L.TT_ITEM_LEVEL_LINE:format(level), 1, 0.82, 0)
        end
    end

    if db.itemCount and itemID and C_Item.GetItemCount then
        local bags = ns.Plain(C_Item.GetItemCount(itemID, false)) or 0
        local total = ns.Plain(C_Item.GetItemCount(itemID, true)) or bags
        if total > 0 then
            if total > bags then
                tooltip:AddDoubleLine(L.TT_HAVE, ("%d (%s %d)"):format(bags, L.TT_BANK, total - bags), 0.7, 0.7, 0.7, 1, 1, 1)
            else
                tooltip:AddDoubleLine(L.TT_HAVE, tostring(bags), 0.7, 0.7, 0.7, 1, 1, 1)
            end
        end
    end

    if db.sellPrice and sellPrice and sellPrice > 0 and not (MerchantFrame and MerchantFrame:IsShown()) then
        local count = TooltipStackCount(tooltip)
        local total = sellPrice * math.max(count, 1)
        local text = ns.FormatMoney(total)
        if count > 1 then
            text = text .. (" |cff888888(%s x%d)|r"):format(ns.FormatMoney(sellPrice), count)
        end
        tooltip:AddDoubleLine(L.TT_SELL_PRICE_LINE, text, 0.7, 0.7, 0.7, 1, 1, 1)
    end

    if db.itemID and itemID then
        tooltip:AddDoubleLine(L.TT_ITEM_ID_LINE, tostring(itemID), 0.5, 0.5, 0.5, 0.8, 0.8, 0.8)
    end

    if db.qualityBorder and quality and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if r then
            SetBorderColor(tooltip, r, g, b)
            tooltip.bigarmsColored = true
        end
    end
    tooltip.bigarmsItemDone = true
end

-- Spells / auras ------------------------------------------------------------------

function Tooltip:OnSpellTooltip(tooltip, data)
    if not self.db.spellID then
        return
    end
    local id = data and ns.Plain(data.id)
    if not id and tooltip.GetSpell then
        local ok, _, spellID = pcall(tooltip.GetSpell, tooltip)
        if ok then
            id = ns.Plain(spellID)
        end
    end
    if id then
        tooltip:AddDoubleLine(L.TT_SPELL_ID_LINE, tostring(id), 0.5, 0.5, 0.5, 0.8, 0.8, 0.8)
    end
end

-- Setup --------------------------------------------------------------------------

function Tooltip:OnEnable()
    local db = self.db
    if GameTooltip and GameTooltip.SetScale then
        GameTooltip:SetScale(tonumber(db.scale) or 1)
    end
    if self.hooked then
        return
    end
    self.hooked = true

    self:SecureHook("GameTooltip_SetDefaultAnchor", function(module, tooltip, parent)
        module:OnDefaultAnchor(tooltip, parent)
    end)

    if GameTooltip then
        self:HookScript(GameTooltip, "OnShow", function(module, tooltip)
            module:OnTooltipShow(tooltip)
        end)
        self:HookScript(GameTooltip, "OnHide", function(_, tooltip)
            tooltip.bigarmsItemDone = nil
            tooltip.bigarmsHideCombat = nil
            ResetBorder(tooltip)
        end)
        self:HookScript(GameTooltip, "OnTooltipCleared", function(_, tooltip)
            tooltip.bigarmsItemDone = nil
            ResetBorder(tooltip)
        end)
    end
    for _, name in ipairs({ "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "EmbeddedItemTooltip" }) do
        local tip = _G[name]
        if tip then
            self:HookScript(tip, "OnHide", function(_, tooltip)
                tooltip.bigarmsItemDone = nil
                ResetBorder(tooltip)
            end)
            self:HookScript(tip, "OnTooltipCleared", function(_, tooltip)
                tooltip.bigarmsItemDone = nil
                ResetBorder(tooltip)
            end)
        end
    end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        local module = self
        local function Post(kind, handler)
            if Enum.TooltipDataType[kind] ~= nil then
                TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType[kind], function(tooltip, data)
                    if module.enabled and tooltip and not (tooltip.IsForbidden and tooltip:IsForbidden()) then
                        local ok, err = pcall(handler, module, tooltip, data)
                        if not ok then
                            module:ReportError(err)
                        end
                    end
                end)
            end
        end
        Post("Unit", self.OnUnitTooltip)
        Post("Item", self.OnItemTooltip)
        Post("Spell", self.OnSpellTooltip)
        Post("UnitAura", self.OnSpellTooltip)
        Post("Macro", self.OnSpellTooltip)
    end
end

function Tooltip:OnDisable()
    if GameTooltip and GameTooltip.SetScale then
        GameTooltip:SetScale(1)
    end
end

function Tooltip:OnSettingChanged(key, value)
    if key == "scale" and GameTooltip then
        GameTooltip:SetScale(tonumber(value) or 1)
    end
end
