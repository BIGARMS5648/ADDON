local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Vendor: auto repair
--------------------------------------------------------------------------

local AutoRepair = ns:NewModule("AutoRepair", {
    group = "AUTOMATION",
    defaults = { enabled = true, useGuild = false, report = true },
    options = {
        { key = "useGuild", type = "toggle", label = "AUTOREPAIR_GUILD", tooltip = "AUTOREPAIR_GUILD_TT" },
        { key = "report", type = "toggle", label = "REPORT_IN_CHAT" },
    },
})

function AutoRepair:OnEnable()
    self:RegisterEvent("MERCHANT_SHOW", "OnMerchantShow")
end

function AutoRepair:OnMerchantShow()
    if not (CanMerchantRepair and CanMerchantRepair()) then
        return
    end
    local cost, canRepair = GetRepairAllCost()
    cost = ns.Plain(cost) or 0
    if not canRepair or cost <= 0 then
        return
    end
    local useGuild = self.db.useGuild and CanGuildBankRepair and CanGuildBankRepair()
    if useGuild then
        local allowed = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or -1
        if allowed ~= -1 and allowed < cost then
            useGuild = false
        end
    end
    if useGuild then
        RepairAllItems(true)
        if self.db.report then
            self:Print(L.REPAIRED_GUILD:format(ns.FormatMoney(cost)))
        end
        return
    end
    if GetMoney() < cost then
        self:Print(L.REPAIR_NO_MONEY:format(ns.FormatMoney(cost)))
        return
    end
    RepairAllItems(false)
    if self.db.report then
        self:Print(L.REPAIRED:format(ns.FormatMoney(cost)))
    end
end

--------------------------------------------------------------------------
-- Vendor: auto sell junk
--------------------------------------------------------------------------

local AutoSellJunk = ns:NewModule("AutoSellJunk", {
    group = "AUTOMATION",
    defaults = { enabled = true, report = true, perItem = false },
    options = {
        { key = "report", type = "toggle", label = "REPORT_IN_CHAT" },
        { key = "perItem", type = "toggle", label = "JUNK_PER_ITEM", tooltip = "JUNK_PER_ITEM_TT" },
        { type = "description", text = "JUNK_HELP" },
    },
})

local SELL_INTERVAL = 0.15
local MAX_SELL = 60

local function GetBagIDs()
    local first = (Enum and Enum.BagIndex and Enum.BagIndex.Backpack) or 0
    local last = first + (NUM_BAG_SLOTS or 4)
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag and Enum.BagIndex.ReagentBag > last then
        last = Enum.BagIndex.ReagentBag
    end
    return first, last
end
ns.GetBagIDs = GetBagIDs

local function GetItemIDFromLink(link)
    if type(link) ~= "string" then
        return nil
    end
    return tonumber(link:match("item:(%d+)"))
end
ns.GetItemIDFromLink = GetItemIDFromLink

local function GetSellPrice(link)
    if not (C_Item and C_Item.GetItemInfo) then
        return nil
    end
    local sellPrice = select(11, C_Item.GetItemInfo(link))
    return ns.Plain(sellPrice)
end
ns.GetSellPrice = GetSellPrice

-- Everything the module would sell right now: { {bag, slot, link, count, price} }
function AutoSellJunk:CollectJunk()
    local list = {}
    if not (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo) then
        return list
    end
    local ignore, always = ns.char.junkIgnore, ns.char.junkSell
    local first, last = GetBagIDs()
    for bag = first, last do
        local slots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.hyperlink and not info.isLocked then
                local itemID = info.itemID or GetItemIDFromLink(info.hyperlink)
                local quality = ns.Plain(info.quality)
                local wanted = false
                if itemID and always[itemID] then
                    wanted = true
                elseif itemID and ignore[itemID] then
                    wanted = false
                elseif quality == 0 and not info.hasNoValue then
                    wanted = true
                end
                if wanted then
                    local price = GetSellPrice(info.hyperlink)
                    if price and price > 0 then
                        list[#list + 1] = {
                            bag = bag, slot = slot, link = info.hyperlink,
                            count = info.stackCount or 1, price = price * (info.stackCount or 1),
                        }
                    end
                end
            end
        end
    end
    return list
end

function AutoSellJunk:OnEnable()
    self:RegisterEvent("MERCHANT_SHOW", "OnMerchantShow")
    self:RegisterEvent("MERCHANT_CLOSED", "OnMerchantClosed")
end

function AutoSellJunk:OnMerchantClosed()
    self.selling = nil
end

function AutoSellJunk:OnMerchantShow()
    local list = self:CollectJunk()
    if #list == 0 then
        return
    end
    local total, index, sold = 0, 0, 0
    self.selling = list
    local module = self
    local function SellNext()
        if module.selling ~= list or not module.enabled then
            return
        end
        index = index + 1
        local item = list[index]
        if not item or index > MAX_SELL then
            module.selling = nil
            if module.db.report and sold > 0 then
                module:Print(L.JUNK_SOLD:format(sold, ns.FormatMoney(total)))
            end
            return
        end
        if C_Container.UseContainerItem then
            C_Container.UseContainerItem(item.bag, item.slot)
            sold = sold + 1
            total = total + item.price
            if module.db.perItem and module.db.report then
                module:Print(L.JUNK_SOLD_ITEM:format(item.link, item.count, ns.FormatMoney(item.price)))
            end
        end
        ns.After(SELL_INTERVAL, SellNext)
    end
    SellNext()
end

-- /ba junk add|del <item link or id>, /ba junk keep|unkeep <item>
function AutoSellJunk:HandleCommand(args)
    local action, rest = args:match("^(%S+)%s*(.*)$")
    action = action and action:lower() or ""
    local itemID = GetItemIDFromLink(rest) or tonumber(rest)
    local db = ns.char
    if action == "add" and itemID then
        db.junkSell[itemID] = true
        db.junkIgnore[itemID] = nil
        self:Print(L.JUNK_ADDED:format(rest))
    elseif (action == "del" or action == "remove") and itemID then
        db.junkSell[itemID] = nil
        self:Print(L.JUNK_REMOVED:format(rest))
    elseif action == "keep" and itemID then
        db.junkIgnore[itemID] = true
        db.junkSell[itemID] = nil
        self:Print(L.JUNK_KEPT:format(rest))
    elseif action == "unkeep" and itemID then
        db.junkIgnore[itemID] = nil
        self:Print(L.JUNK_UNKEPT:format(rest))
    elseif action == "list" or action == "" then
        local sell, keep = {}, {}
        for id in pairs(db.junkSell) do sell[#sell + 1] = tostring(id) end
        for id in pairs(db.junkIgnore) do keep[#keep + 1] = tostring(id) end
        table.sort(sell)
        table.sort(keep)
        self:Print(L.JUNK_LIST_SELL .. " " .. (#sell > 0 and table.concat(sell, ", ") or "-"))
        self:Print(L.JUNK_LIST_KEEP .. " " .. (#keep > 0 and table.concat(keep, ", ") or "-"))
    else
        self:Print(L.JUNK_USAGE)
    end
end

--------------------------------------------------------------------------
-- Auto quest: accept, turn in, skip single gossip options
--------------------------------------------------------------------------

local AutoQuest = ns:NewModule("AutoQuest", {
    group = "AUTOMATION",
    defaults = {
        enabled = true, accept = true, turnIn = true, gossip = true, trivial = false,
        repeatable = false, escort = true, pauseKey = "SHIFT", bestReward = true, reportReward = true,
    },
    options = {
        { key = "accept", type = "toggle", label = "AQ_ACCEPT" },
        { key = "turnIn", type = "toggle", label = "AQ_TURNIN", tooltip = "AQ_TURNIN_TT" },
        { key = "gossip", type = "toggle", label = "AQ_GOSSIP", tooltip = "AQ_GOSSIP_TT" },
        { key = "trivial", type = "toggle", label = "AQ_TRIVIAL" },
        { key = "repeatable", type = "toggle", label = "AQ_REPEATABLE" },
        { key = "escort", type = "toggle", label = "AQ_ESCORT", tooltip = "AQ_ESCORT_TT" },
        { key = "bestReward", type = "toggle", label = "AQ_BEST_REWARD", tooltip = "AQ_BEST_REWARD_TT" },
        { key = "pauseKey", type = "select", label = "PAUSE_KEY", tooltip = "PAUSE_KEY_TT", choices = ns.MODIFIER_CHOICES },
        { type = "description", text = "AQ_HELP" },
    },
})

function AutoQuest:Paused()
    return ns.IsModifierDown(self.db.pauseKey)
end

function AutoQuest:OnEnable()
    self:RegisterEvent("GOSSIP_SHOW", "OnGossipShow")
    self:RegisterEvent("QUEST_GREETING", "OnQuestGreeting")
    self:RegisterEvent("QUEST_DETAIL", "OnQuestDetail")
    self:RegisterEvent("QUEST_PROGRESS", "OnQuestProgress")
    self:RegisterEvent("QUEST_COMPLETE", "OnQuestComplete")
    self:RegisterEvent("QUEST_ACCEPT_CONFIRM", "OnQuestAcceptConfirm")
end

local function QuestBlocked(questID)
    return questID and ns.char.questBlock[questID] == true
end

-- gossip window: quests first, then the lonely option
function AutoQuest:OnGossipShow()
    if self:Paused() or not C_GossipInfo then
        return
    end
    local db = self.db
    if db.turnIn and C_GossipInfo.GetActiveQuests then
        for _, quest in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
            if quest.isComplete and not QuestBlocked(quest.questID) then
                C_GossipInfo.SelectActiveQuest(quest.questID)
                return
            end
        end
    end
    if db.accept and C_GossipInfo.GetAvailableQuests then
        for _, quest in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
            local trivialOK = db.trivial or not quest.isTrivial
            local repeatableOK = db.repeatable or not (quest.repeatable or (quest.frequency and quest.frequency > 0))
            if trivialOK and repeatableOK and not QuestBlocked(quest.questID) then
                C_GossipInfo.SelectAvailableQuest(quest.questID)
                return
            end
        end
    end
    if db.gossip and C_GossipInfo.GetOptions then
        local options = C_GossipInfo.GetOptions() or {}
        local numActive = C_GossipInfo.GetNumActiveQuests and C_GossipInfo.GetNumActiveQuests() or 0
        local numAvailable = C_GossipInfo.GetNumAvailableQuests and C_GossipInfo.GetNumAvailableQuests() or 0
        if #options == 1 and numActive == 0 and numAvailable == 0 then
            local option = options[1]
            -- status 0 = available; skip options the game itself marks as needing a choice
            if (option.status == nil or option.status == 0) and option.gossipOptionID then
                C_GossipInfo.SelectOption(option.gossipOptionID)
            end
        end
    end
end

-- old style greeting window (no gossip)
function AutoQuest:OnQuestGreeting()
    if self:Paused() then
        return
    end
    local db = self.db
    if db.turnIn and GetNumActiveQuests then
        for i = 1, GetNumActiveQuests() do
            local _, isComplete = GetActiveTitle(i)
            if isComplete then
                SelectActiveQuest(i)
                return
            end
        end
    end
    if db.accept and GetNumAvailableQuests then
        for i = 1, GetNumAvailableQuests() do
            local trivial = IsAvailableQuestTrivial and IsAvailableQuestTrivial(i)
            if db.trivial or not trivial then
                SelectAvailableQuest(i)
                return
            end
        end
    end
end

function AutoQuest:OnQuestDetail()
    if self:Paused() or not self.db.accept then
        return
    end
    local questID = GetQuestID and GetQuestID()
    if QuestBlocked(questID) then
        return
    end
    if not self.db.trivial and questID and C_QuestLog and C_QuestLog.IsQuestTrivial and C_QuestLog.IsQuestTrivial(questID) then
        return
    end
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        if AcknowledgeAutoAcceptQuest then
            AcknowledgeAutoAcceptQuest()
        end
    else
        AcceptQuest()
    end
end

function AutoQuest:OnQuestProgress()
    if self:Paused() or not self.db.turnIn then
        return
    end
    if IsQuestCompletable and IsQuestCompletable() then
        CompleteQuest()
    end
end

-- Value of a reward choice in copper (for picking the best one to vendor).
local function ChoiceValue(index)
    if not GetQuestItemLink then
        return nil
    end
    local link = GetQuestItemLink("choice", index)
    if not link then
        return nil
    end
    local price = GetSellPrice(link)
    if not price then
        return nil
    end
    local _, _, count = GetQuestItemInfo("choice", index)
    return price * (ns.Plain(count) or 1), link
end

function AutoQuest:HighlightBestReward()
    if not self.db.bestReward or not GetNumQuestChoices then
        return
    end
    local numChoices = GetNumQuestChoices()
    if numChoices < 2 then
        return
    end
    local best, bestValue, bestLink = nil, -1, nil
    for i = 1, numChoices do
        local value, link = ChoiceValue(i)
        if value and value > bestValue then
            best, bestValue, bestLink = i, value, link
        end
    end
    if not best then
        return
    end
    self.bestChoice = best
    local button = QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons and QuestInfoRewardsFrame.RewardButtons[best]
    if button then
        if not button.bigarmsGlow then
            local glow = button:CreateTexture(nil, "OVERLAY")
            glow:SetPoint("TOPLEFT", button, "TOPLEFT", -6, 6)
            glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 6, -6)
            glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
            glow:SetBlendMode("ADD")
            glow:SetVertexColor(1, 0.85, 0.1, 0.9)
            button.bigarmsGlow = glow
        end
        button.bigarmsGlow:Show()
        self.glowButton = button
    end
    if self.db.reportReward and bestLink then
        self:Print(L.AQ_BEST_IS:format(bestLink, ns.FormatMoney(bestValue)))
    end
end

function AutoQuest:OnQuestComplete()
    if self.glowButton and self.glowButton.bigarmsGlow then
        self.glowButton.bigarmsGlow:Hide()
    end
    self.bestChoice = nil
    local numChoices = GetNumQuestChoices and GetNumQuestChoices() or 0
    if numChoices > 1 then
        -- never choose for the player; just show which one vendors best
        self:After(0.2, self.HighlightBestReward)
        return
    end
    if self:Paused() or not self.db.turnIn then
        return
    end
    if QuestBlocked(GetQuestID and GetQuestID()) then
        return
    end
    GetQuestReward(numChoices == 1 and 1 or 0)
end

function AutoQuest:OnQuestAcceptConfirm()
    if self:Paused() or not self.db.escort then
        return
    end
    if ConfirmAcceptQuest then
        ConfirmAcceptQuest()
    end
    if StaticPopup_Hide then
        StaticPopup_Hide("QUEST_ACCEPT_CONFIRM")
    end
end

-- /ba quest block|unblock <questID>, /ba quest list
function AutoQuest:HandleCommand(args)
    local action, rest = args:match("^(%S+)%s*(.*)$")
    action = action and action:lower() or ""
    local questID = tonumber(rest)
    if action == "block" and questID then
        ns.char.questBlock[questID] = true
        self:Print(L.AQ_BLOCKED:format(questID))
    elseif action == "unblock" and questID then
        ns.char.questBlock[questID] = nil
        self:Print(L.AQ_UNBLOCKED:format(questID))
    else
        local ids = {}
        for id in pairs(ns.char.questBlock) do ids[#ids + 1] = tostring(id) end
        table.sort(ids)
        self:Print(L.AQ_BLOCK_LIST .. " " .. (#ids > 0 and table.concat(ids, ", ") or "-"))
    end
end

--------------------------------------------------------------------------
-- Auto accept: group invites, resurrection, summons
--------------------------------------------------------------------------

local AutoAccept = ns:NewModule("AutoAccept", {
    group = "AUTOMATION",
    defaults = { enabled = true, invites = "FRIENDS", resurrect = true, summon = true, summonDelay = 5 },
    options = {
        { key = "invites", type = "select", label = "AA_INVITES", tooltip = "AA_INVITES_TT", choices = function()
            return { { "FRIENDS", L.CHOICE_FRIENDS_GUILD }, { "ALL", L.CHOICE_EVERYONE }, { "OFF", L.CHOICE_OFF } }
        end },
        { key = "resurrect", type = "toggle", label = "AA_RESURRECT", tooltip = "AA_RESURRECT_TT" },
        { key = "summon", type = "toggle", label = "AA_SUMMON" },
        { key = "summonDelay", type = "range", label = "AA_SUMMON_DELAY", min = 0, max = 30, step = 1, format = "%ds" },
    },
})

function AutoAccept:OnEnable()
    self:RegisterEvent("PARTY_INVITE_REQUEST", "OnPartyInvite")
    self:RegisterEvent("RESURRECT_REQUEST", "OnResurrect")
    self:RegisterEvent("CONFIRM_SUMMON", "OnSummon")
end

function AutoAccept:OnPartyInvite(_, name, _, _, _, _, _, inviterGUID)
    local mode = self.db.invites
    if mode == "OFF" then
        return
    end
    if mode == "FRIENDS" and not ns.IsFriendOrGuild(name, inviterGUID) then
        return
    end
    if AcceptGroup then
        AcceptGroup()
    end
    if StaticPopup_Hide then
        StaticPopup_Hide("PARTY_INVITE")
    end
    self:Print(L.AA_ACCEPTED_INVITE:format(name or "?"))
end

function AutoAccept:OnResurrect(_, caster)
    if not self.db.resurrect then
        return
    end
    -- never steal a battle res the player may want to time
    if UnitAffectingCombat and UnitAffectingCombat("player") then
        return
    end
    if AcceptResurrect then
        AcceptResurrect()
    end
    if StaticPopup_Hide then
        StaticPopup_Hide("RESURRECT")
        StaticPopup_Hide("RESURRECT_NO_SICKNESS")
        StaticPopup_Hide("RESURRECT_NO_TIMER")
    end
    self:Print(L.AA_ACCEPTED_RES:format(caster or "?"))
end

function AutoAccept:OnSummon()
    if not self.db.summon or not (C_SummonInfo and C_SummonInfo.ConfirmSummon) then
        return
    end
    local delay = tonumber(self.db.summonDelay) or 0
    self:After(delay, function()
        if InCombatLockdown() then
            return
        end
        if C_SummonInfo.GetSummonConfirmTimeLeft and (C_SummonInfo.GetSummonConfirmTimeLeft() or 0) <= 0 then
            return
        end
        C_SummonInfo.ConfirmSummon()
        if StaticPopup_Hide then
            StaticPopup_Hide("CONFIRM_SUMMON")
        end
    end)
end

--------------------------------------------------------------------------
-- Auto decline: duels, guild invites, petitions, trades
--------------------------------------------------------------------------

local AutoDecline = ns:NewModule("AutoDecline", {
    group = "AUTOMATION",
    defaults = { enabled = true, duels = true, guild = false, petition = false, trade = false, allowFriends = true },
    options = {
        { key = "duels", type = "toggle", label = "AD_DUELS" },
        { key = "guild", type = "toggle", label = "AD_GUILD" },
        { key = "petition", type = "toggle", label = "AD_PETITION" },
        { key = "trade", type = "toggle", label = "AD_TRADE" },
        { key = "allowFriends", type = "toggle", label = "AD_ALLOW_FRIENDS", tooltip = "AD_ALLOW_FRIENDS_TT" },
    },
})

function AutoDecline:OnEnable()
    self:RegisterEvent("DUEL_REQUESTED", "OnDuel")
    self:RegisterEvent("GUILD_INVITE_REQUEST", "OnGuildInvite")
    self:RegisterEvent("PETITION_SHOW", "OnPetition")
    self:RegisterEvent("TRADE_SHOW", "OnTrade")
end

function AutoDecline:OnDuel(_, name)
    if not self.db.duels then
        return
    end
    if self.db.allowFriends and ns.IsFriendOrGuild(name) then
        return
    end
    if CancelDuel then
        CancelDuel()
    end
    if StaticPopup_Hide then
        StaticPopup_Hide("DUEL_REQUESTED")
    end
    self:Print(L.AD_DECLINED_DUEL:format(name or "?"))
end

function AutoDecline:OnGuildInvite(_, inviter, guild)
    if not self.db.guild then
        return
    end
    if self.db.allowFriends and ns.IsFriendOrGuild(inviter) then
        return
    end
    if DeclineGuild then
        DeclineGuild()
    end
    if StaticPopup_Hide then
        StaticPopup_Hide("GUILD_INVITE")
    end
    self:Print(L.AD_DECLINED_GUILD:format(inviter or "?", guild or "?"))
end

function AutoDecline:OnPetition()
    if not self.db.petition or not GetPetitionInfo then
        return
    end
    local _, _, _, _, originator, isOriginator = GetPetitionInfo()
    if isOriginator then
        return
    end
    if self.db.allowFriends and ns.IsFriendOrGuild(originator) then
        return
    end
    if ClosePetition then
        ClosePetition()
    end
    self:Print(L.AD_DECLINED_PETITION:format(originator or "?"))
end

function AutoDecline:OnTrade()
    if not self.db.trade then
        return
    end
    local name = UnitName and UnitName("npc")
    if self.db.allowFriends and ns.IsFriendOrGuild(name) then
        return
    end
    if CancelTrade then
        CancelTrade()
    end
    self:Print(L.AD_DECLINED_TRADE:format(name or "?"))
end

--------------------------------------------------------------------------
-- Auto release spirit in battlegrounds
--------------------------------------------------------------------------

local AutoRelease = ns:NewModule("AutoRelease", {
    group = "AUTOMATION",
    defaults = { enabled = true, delay = 1 },
    options = {
        { key = "delay", type = "range", label = "AR_DELAY", min = 0, max = 10, step = 1, format = "%ds" },
    },
})

function AutoRelease:OnEnable()
    self:RegisterEvent("PLAYER_DEAD", "OnDead")
end

local function InBattleground()
    if C_PvP and C_PvP.IsBattleground and C_PvP.IsBattleground() then
        return true
    end
    local _, instanceType = IsInInstance()
    return instanceType == "pvp"
end

local function HasSelfResurrect()
    if C_DeathInfo and C_DeathInfo.GetSelfResurrectOptions then
        local options = C_DeathInfo.GetSelfResurrectOptions()
        return options and #options > 0
    end
    return false
end

function AutoRelease:OnDead()
    if not InBattleground() or HasSelfResurrect() then
        return
    end
    self:After(tonumber(self.db.delay) or 0, function()
        if UnitIsDead and UnitIsDead("player") and not (UnitIsGhost and UnitIsGhost("player")) and not HasSelfResurrect() then
            if RepopMe then
                pcall(RepopMe)
            end
            if StaticPopup_Hide then
                StaticPopup_Hide("DEATH")
            end
        end
    end)
end

--------------------------------------------------------------------------
-- Fast loot
--------------------------------------------------------------------------

local FastLoot = ns:NewModule("FastLoot", {
    group = "AUTOMATION",
    defaults = { enabled = true },
    options = {
        { type = "description", text = "FASTLOOT_HELP" },
    },
})

function FastLoot:OnEnable()
    self:RegisterEvent("LOOT_READY", "OnLootReady")
end

function FastLoot:OnLootReady(_, autoLoot)
    local now = GetTime()
    if self.lastLoot and now - self.lastLoot < 0.3 then
        return
    end
    self.lastLoot = now
    local wantAuto = autoLoot
    if wantAuto == nil then
        local setting = ns.GetCVarBool("autoLootDefault")
        local toggled = IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE")
        wantAuto = setting ~= (toggled and true or false)
    end
    if not wantAuto or not GetNumLootItems then
        return
    end
    for slot = GetNumLootItems(), 1, -1 do
        LootSlot(slot)
    end
end

--------------------------------------------------------------------------
-- Easy delete: fill in "DELETE" for you
--------------------------------------------------------------------------

local EasyDelete = ns:NewModule("EasyDelete", {
    group = "AUTOMATION",
    defaults = { enabled = true },
})

local DELETE_POPUPS = { DELETE_GOOD_ITEM = true, DELETE_GOOD_QUEST_ITEM = true }

function EasyDelete:OnEnable()
    if self.hooked then
        return
    end
    self.hooked = self:SecureHook("StaticPopup_Show", function(module, which)
        if not DELETE_POPUPS[which] then
            return
        end
        local dialog = StaticPopup_FindVisible and StaticPopup_FindVisible(which)
        local editBox = dialog and (dialog.editBox or dialog.EditBox)
        if editBox and DELETE_ITEM_CONFIRM_STRING then
            editBox:SetText(DELETE_ITEM_CONFIRM_STRING)
        end
    end)
end

--------------------------------------------------------------------------
-- Skip cinematics and movies (hold the pause key to watch)
--------------------------------------------------------------------------

local SkipCinematics = ns:NewModule("SkipCinematics", {
    group = "AUTOMATION",
    defaults = { enabled = false, pauseKey = "SHIFT" },
    options = {
        { key = "pauseKey", type = "select", label = "PAUSE_KEY", tooltip = "SKIP_PAUSE_TT", choices = ns.MODIFIER_CHOICES },
    },
})

function SkipCinematics:OnEnable()
    self:RegisterEvent("CINEMATIC_START", "OnCinematic")
    self:RegisterEvent("PLAY_MOVIE", "OnMovie")
end

function SkipCinematics:OnCinematic()
    if ns.IsModifierDown(self.db.pauseKey) then
        return
    end
    if CinematicFrame_CancelCinematic then
        CinematicFrame_CancelCinematic()
    elseif StopCinematic then
        StopCinematic()
    end
end

function SkipCinematics:OnMovie()
    if ns.IsModifierDown(self.db.pauseKey) then
        return
    end
    self:After(0, function()
        if MovieFrame and MovieFrame:IsShown() then
            if MovieFrame_OnMovieFinished then
                MovieFrame_OnMovieFinished(MovieFrame)
            elseif GameMovieFinished then
                GameMovieFinished()
            end
        end
    end)
end

--------------------------------------------------------------------------
-- Keep gathering tracking (find herbs / minerals) after death and zoning
--------------------------------------------------------------------------

local KeepTracking = ns:NewModule("KeepTracking", {
    group = "AUTOMATION",
    defaults = { enabled = true },
    options = {
        { type = "description", text = "KEEPTRACKING_HELP" },
    },
})

local function TrackingInfo(index)
    if not (C_Minimap and C_Minimap.GetTrackingInfo) then
        return nil
    end
    local info = C_Minimap.GetTrackingInfo(index)
    if type(info) == "table" then
        return info.name, info.active, info.type, info.spellID
    end
    -- older signature: name, texture, active, category
    local name, _, active, category = C_Minimap.GetTrackingInfo(index)
    return name, active, category, nil
end

function KeepTracking:OnEnable()
    self:RegisterEvent("MINIMAP_UPDATE_TRACKING", "Remember")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "Restore")
    self:RegisterEvent("PLAYER_UNGHOST", "Restore")
    self:RegisterEvent("PLAYER_ALIVE", "Restore")
    self:After(2, self.Remember)
end

-- Note which spell tracking (herbs, minerals, ...) the player has on.
function KeepTracking:Remember()
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes) then
        return
    end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
        return
    end
    local found = nil
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local name, active, kind = TrackingInfo(i)
        if active and (kind == "spell" or kind == 1) then
            found = name
        end
    end
    if found then
        ns.char.tracking = found
    elseif self.sawActive then
        ns.char.tracking = nil
    end
    self.sawActive = found ~= nil
end

function KeepTracking:Restore()
    local wanted = ns.char.tracking
    if not wanted or not (C_Minimap and C_Minimap.GetNumTrackingTypes) then
        return
    end
    self:After(3, function()
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
            return
        end
        for i = 1, C_Minimap.GetNumTrackingTypes() do
            local name, active = TrackingInfo(i)
            if name == wanted then
                if not active and C_Minimap.SetTracking then
                    C_Minimap.SetTracking(i, true)
                    self:Print(L.TRACKING_RESTORED:format(name))
                end
                return
            end
        end
    end)
end

--------------------------------------------------------------------------
-- Auto stand / dismount when an action fails because of it
--------------------------------------------------------------------------

local AutoStand = ns:NewModule("AutoStand", {
    group = "AUTOMATION",
    defaults = { enabled = true, dismount = true, stand = true },
    options = {
        { key = "dismount", type = "toggle", label = "AS_DISMOUNT" },
        { key = "stand", type = "toggle", label = "AS_STAND" },
    },
})

function AutoStand:OnEnable()
    self:RegisterEvent("UI_ERROR_MESSAGE", "OnError")
end

local function MessageMatches(message, ...)
    for i = 1, select("#", ...) do
        local text = _G[(select(i, ...))]
        if text and text == message then
            return true
        end
    end
    return false
end

function AutoStand:OnError(_, _, message)
    if type(message) ~= "string" then
        return
    end
    if self.db.dismount and MessageMatches(message, "ERR_ATTACK_MOUNTED", "SPELL_FAILED_NOT_MOUNTED", "ERR_NOT_WHILE_MOUNTED", "ERR_TAXIPLAYERALREADYMOUNTED") then
        if IsMounted and IsMounted() and Dismount then
            pcall(Dismount)
        end
    elseif self.db.stand and MessageMatches(message, "SPELL_FAILED_NOT_STANDING", "ERR_CANTATTACK_NOTSTANDING", "ERR_LOOT_NOTSTANDING", "ERR_TAXINOTSTANDING") then
        if DoEmote then
            pcall(DoEmote, "STAND")
        end
    end
end

--------------------------------------------------------------------------
-- Auto screenshot on level up
--------------------------------------------------------------------------

local AutoScreenshot = ns:NewModule("AutoScreenshot", {
    group = "AUTOMATION",
    defaults = { enabled = false, levelUp = true },
    options = {
        { key = "levelUp", type = "toggle", label = "SS_LEVELUP" },
    },
})

function AutoScreenshot:OnEnable()
    self:RegisterEvent("PLAYER_LEVEL_UP", "OnLevelUp")
end

function AutoScreenshot:OnLevelUp()
    if self.db.levelUp and Screenshot then
        self:After(1.5, function() Screenshot() end)
    end
end
