local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Vendor: Alt-click buys a full stack
--------------------------------------------------------------------------

local Vendor = ns:NewModule("Vendor", {
    group = "ITEMS",
    defaults = { enabled = true, altStack = true },
    options = {
        { key = "altStack", type = "toggle", label = "VD_ALT_STACK", tooltip = "VD_ALT_STACK_TT" },
    },
})

-- How many of merchant item `index` one Alt-click buys.
function ns.MerchantStackSize(index)
    local maxStack
    if GetMerchantItemMaxStack then
        maxStack = ns.Plain(GetMerchantItemMaxStack(index))
    end
    if not maxStack or maxStack < 1 then
        local link = GetMerchantItemLink and GetMerchantItemLink(index)
        local stack = link and ns.Plain(select(8, C_Item.GetItemInfo(link)))
        maxStack = stack or 1
    end
    local numAvailable
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        numAvailable = info and ns.Plain(info.numAvailable)
    elseif GetMerchantItemInfo then
        numAvailable = ns.Plain(select(5, GetMerchantItemInfo(index)))
    end
    if numAvailable and numAvailable >= 0 and numAvailable < maxStack then
        maxStack = numAvailable
    end
    return math.max(maxStack, 1)
end

function Vendor:OnModifiedClick(button, mouseButton)
    if not self.db.altStack or not IsAltKeyDown() or mouseButton ~= "LeftButton" then
        return
    end
    if not button.GetID or not BuyMerchantItem then
        return
    end
    if MerchantFrame and MerchantFrame.selectedTab and MerchantFrame.selectedTab ~= 1 then
        return -- buyback tab
    end
    local index = button:GetID()
    local count = ns.MerchantStackSize(index)
    if count > 1 then
        BuyMerchantItem(index, count)
    end
end

function Vendor:OnEnable()
    if self.hooked then
        return
    end
    self.hooked = true
    self:SecureHook("MerchantItemButton_OnModifiedClick", function(module, button, mouseButton)
        module:OnModifiedClick(button, mouseButton)
    end)
end

--------------------------------------------------------------------------
-- Trainer: "Train all" button
--------------------------------------------------------------------------

local Trainer = ns:NewModule("Trainer", {
    group = "ITEMS",
    defaults = { enabled = true },
    options = {
        { type = "description", text = "TR_HELP" },
    },
})

function Trainer:Available()
    local list, cost = {}, 0
    if not (GetNumTrainerServices and GetTrainerServiceInfo) then
        return list, cost
    end
    for i = 1, GetNumTrainerServices() do
        local name, _, category = GetTrainerServiceInfo(i)
        if category == "available" then
            list[#list + 1] = { index = i, name = name }
            if GetTrainerServiceCost then
                cost = cost + (ns.Plain((GetTrainerServiceCost(i))) or 0)
            end
        end
    end
    return list, cost
end

function Trainer:TrainAll()
    local list, cost = self:Available()
    if #list == 0 then
        self:Print(L.TR_NOTHING)
        return
    end
    if cost > (ns.Plain(GetMoney()) or 0) then
        self:Print(L.TR_TOO_EXPENSIVE:format(ns.FormatMoney(cost)))
        return
    end
    -- buying shifts the indexes; go from the bottom up
    local module = self
    local i = #list
    local function Next()
        if i < 1 or not module.enabled or not (ClassTrainerFrame and ClassTrainerFrame:IsShown()) then
            return
        end
        local entry = list[i]
        i = i - 1
        if BuyTrainerService then
            BuyTrainerService(entry.index)
        end
        ns.After(0.4, Next)
    end
    Next()
    self:Print(L.TR_TRAINING:format(#list, ns.FormatMoney(cost)))
end

function Trainer:CreateButton()
    if self.button or not ClassTrainerFrame then
        return
    end
    local button = CreateFrame("Button", "BIGARMSTrainAll", ClassTrainerFrame, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    button:SetPoint("BOTTOMLEFT", ClassTrainerFrame, "BOTTOMLEFT", 8, 4)
    button:SetText(L.TR_BUTTON)
    button:SetScript("OnClick", function() Trainer:TrainAll() end)
    button:SetScript("OnEnter", function(self)
        local list, cost = Trainer:Available()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L.TR_BUTTON)
        GameTooltip:AddLine(L.TR_TOOLTIP:format(#list, ns.FormatMoney(cost)), 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.button = button
end

function Trainer:OnEnable()
    self:CreateButton()
    self:RegisterEvent("ADDON_LOADED", function(module, _, name)
        if name == "Blizzard_TrainerUI" then
            module:CreateButton()
        end
    end)
    self:RegisterEvent("TRAINER_SHOW", "CreateButton")
end

function Trainer:OnDisable()
    if self.button then
        self.button:Hide()
    end
end

--------------------------------------------------------------------------
-- Auction prices: remember what you see in the auction house and show it
-- in tooltips. Nothing is scanned on its own; browsing does the work.
--------------------------------------------------------------------------

local AuctionPrices = ns:NewModule("AuctionPrices", {
    group = "ITEMS",
    defaults = { enabled = true, tooltip = true, maxAge = 14 },
    options = {
        { key = "tooltip", type = "toggle", label = "AH_TOOLTIP" },
        { key = "maxAge", type = "range", label = "AH_MAX_AGE", tooltip = "AH_MAX_AGE_TT", min = 1, max = 60, step = 1, format = "%dd" },
        { type = "description", text = "AH_HELP" },
    },
})

function ns.RecordAuctionPrice(itemID, price)
    itemID, price = ns.Plain(itemID), ns.Plain(price)
    if not itemID or not price or price <= 0 then
        return
    end
    ns.db.auction[itemID] = { price = price, time = time() }
end

-- price per unit and its age in days, or nil
function ns.GetAuctionPrice(itemID)
    local module = ns:GetModule("AuctionPrices")
    if not module or not module.enabled then
        return nil
    end
    local entry = ns.db.auction[itemID]
    if not entry then
        return nil
    end
    local age = (time() - (entry.time or 0)) / 86400
    if age > (tonumber(module.db.maxAge) or 14) then
        return nil
    end
    return entry.price, age
end

function AuctionPrices:OnBrowse()
    if not (C_AuctionHouse and C_AuctionHouse.GetBrowseResults) then
        return
    end
    local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
    if not ok or not results then
        return
    end
    for _, result in ipairs(results) do
        local key = result.itemKey
        if key and key.itemID then
            ns.RecordAuctionPrice(key.itemID, result.minPrice)
        end
    end
end

function AuctionPrices:OnCommodity(_, itemID)
    if not (itemID and C_AuctionHouse and C_AuctionHouse.GetCommoditySearchResultInfo) then
        return
    end
    local ok, info = pcall(C_AuctionHouse.GetCommoditySearchResultInfo, itemID, 1)
    if ok and info then
        ns.RecordAuctionPrice(itemID, info.unitPrice)
    end
end

function AuctionPrices:OnItemSearch(_, itemKey)
    if not (itemKey and itemKey.itemID and C_AuctionHouse and C_AuctionHouse.GetItemSearchResultInfo) then
        return
    end
    local count = C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetNumItemSearchResults(itemKey) or 1
    for i = 1, math.min(count, 10) do
        local ok, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
        local buyout = ok and info and ns.Plain(info.buyoutAmount)
        if buyout and buyout > 0 then
            local quantity = ns.Plain(info.quantity) or 1
            ns.RecordAuctionPrice(itemKey.itemID, buyout / math.max(quantity, 1))
            return
        end
    end
end

function AuctionPrices:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", "OnBrowse")
    self:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", "OnBrowse")
    self:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED", "OnCommodity")
    self:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED", "OnItemSearch")
end

function AuctionPrices:HandleCommand(args)
    local itemID = ns.GetItemIDFromLink(args) or tonumber(args)
    if not itemID then
        self:Print(L.AH_USAGE)
        return
    end
    local price, age = ns.GetAuctionPrice(itemID)
    if price then
        self:Print(L.AH_LINE:format(ns.FormatMoney(price), age))
    else
        self:Print(L.AH_UNKNOWN)
    end
end

--------------------------------------------------------------------------
-- Mail: one-click recipients (your other characters and recent names)
--------------------------------------------------------------------------

local Mail = ns:NewModule("Mail", {
    group = "ITEMS",
    defaults = { enabled = true, alts = true, recent = true },
    options = {
        { key = "alts", type = "toggle", label = "ML_ALTS", tooltip = "ML_ALTS_TT" },
        { key = "recent", type = "toggle", label = "ML_RECENT" },
    },
})

local MAX_BUTTONS = 8

function Mail:Recipients()
    local list = {}
    local me = UnitName("player")
    local realm = GetRealmName and GetRealmName() or ""
    if self.db.alts then
        local alts = {}
        for _, entry in pairs(ns.db.gold) do
            if entry.name and entry.name ~= me and entry.realm == realm then
                alts[#alts + 1] = entry
            end
        end
        table.sort(alts, function(a, b) return (a.time or 0) > (b.time or 0) end)
        for _, entry in ipairs(alts) do
            list[#list + 1] = { name = entry.name, class = entry.class }
        end
    end
    if self.db.recent then
        for _, name in ipairs(ns.char.recentMail) do
            local dup = false
            for _, item in ipairs(list) do
                if item.name == name then
                    dup = true
                end
            end
            if not dup then
                list[#list + 1] = { name = name }
            end
        end
    end
    return list
end

function Mail:Layout()
    if not SendMailFrame or not SendMailNameEditBox then
        return
    end
    self.buttons = self.buttons or {}
    local list = self:Recipients()
    for i = 1, MAX_BUTTONS do
        local entry = list[i]
        local button = self.buttons[i]
        if entry and not button then
            button = CreateFrame("Button", nil, SendMailFrame, "UIPanelButtonTemplate")
            button:SetSize(90, 18)
            button:SetScript("OnClick", function(self_)
                SendMailNameEditBox:SetText(self_.recipient or "")
                if SendMailSubjectEditBox and SendMailSubjectEditBox.SetFocus then
                    SendMailSubjectEditBox:SetFocus()
                end
            end)
            self.buttons[i] = button
        end
        if button then
            if entry then
                button.recipient = entry.name
                local color = entry.class and ns.ClassColorHex(entry.class) or "ffffff"
                button:SetText(("|cff%s%s|r"):format(color, entry.name))
                button:ClearAllPoints()
                local column, row = (i - 1) % 4, math.floor((i - 1) / 4)
                button:SetPoint("TOPLEFT", SendMailFrame, "TOPLEFT", 8 + column * 92, -2 - row * 19)
                button:Show()
            else
                button:Hide()
            end
        end
    end
end

function Mail:RememberRecipient(name)
    name = ns.Trim(name or "")
    if name == "" or ns.IsMe(name) then
        return
    end
    local recent = ns.char.recentMail
    for i = #recent, 1, -1 do
        if recent[i] == name then
            table.remove(recent, i)
        end
    end
    table.insert(recent, 1, name)
    while #recent > 5 do
        table.remove(recent)
    end
end

function Mail:OnEnable()
    self:RegisterEvent("MAIL_SHOW", function(module) module:After(0, module.Layout) end)
    if not self.sendHooked then
        self.sendHooked = true
        self:SecureHook("SendMail", function(module, recipient)
            module:RememberRecipient(recipient)
        end)
    end
end

function Mail:OnDisable()
    for _, button in ipairs(self.buttons or {}) do
        button:Hide()
    end
end

function Mail:OnSettingChanged()
    if MailFrame and MailFrame:IsShown() then
        self:Layout()
    end
end
