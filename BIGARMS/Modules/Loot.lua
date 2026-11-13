local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Auto roll on group loot
--------------------------------------------------------------------------

local AutoRoll = ns:NewModule("AutoRoll", {
    group = "LOOT",
    defaults = { enabled = false, common = "GREED", uncommon = "KEEP", rare = "KEEP", epic = "KEEP", skipBoP = true, delay = 1 },
    options = {
        { key = "common", type = "select", label = "ROLL_COMMON", choices = function()
            return { { "KEEP", L.CHOICE_KEEP }, { "GREED", L.ROLL_GREED }, { "PASS", L.ROLL_PASS } }
        end },
        { key = "uncommon", type = "select", label = "ROLL_UNCOMMON", choices = function()
            return { { "KEEP", L.CHOICE_KEEP }, { "NEED", L.ROLL_NEED }, { "GREED", L.ROLL_GREED }, { "PASS", L.ROLL_PASS } }
        end },
        { key = "rare", type = "select", label = "ROLL_RARE", choices = function()
            return { { "KEEP", L.CHOICE_KEEP }, { "GREED", L.ROLL_GREED }, { "PASS", L.ROLL_PASS } }
        end },
        { key = "epic", type = "select", label = "ROLL_EPIC", choices = function()
            return { { "KEEP", L.CHOICE_KEEP }, { "GREED", L.ROLL_GREED }, { "PASS", L.ROLL_PASS } }
        end },
        { key = "skipBoP", type = "toggle", label = "ROLL_SKIP_BOP", tooltip = "ROLL_SKIP_BOP_TT" },
        { key = "delay", type = "range", label = "ROLL_DELAY", min = 0, max = 10, step = 1, format = "%ds" },
    },
})

local ROLL_TYPES = { PASS = 0, NEED = 1, GREED = 2 }

-- Decide what to roll for an item of this quality (nil = leave it to the player).
function AutoRoll:Decide(quality, bindOnPickUp, canNeed, canGreed)
    local db = self.db
    if db.skipBoP and bindOnPickUp then
        return nil
    end
    local choice
    if quality <= 1 then
        choice = db.common
    elseif quality == 2 then
        choice = db.uncommon
    elseif quality == 3 then
        choice = db.rare
    else
        choice = db.epic
    end
    if choice == "KEEP" then
        return nil
    end
    if choice == "NEED" and canNeed == false then
        choice = canGreed ~= false and "GREED" or "PASS"
    elseif choice == "GREED" and canGreed == false then
        choice = "PASS"
    end
    return ROLL_TYPES[choice]
end

function AutoRoll:OnEnable()
    self:RegisterEvent("START_LOOT_ROLL", "OnRoll")
end

function AutoRoll:OnRoll(_, rollID)
    if not rollID or not GetLootRollItemInfo then
        return
    end
    local _, name, _, quality, bindOnPickUp, canNeed, canGreed = GetLootRollItemInfo(rollID)
    quality = ns.Plain(quality)
    if not quality then
        return
    end
    local rollType = self:Decide(quality, bindOnPickUp, canNeed, canGreed)
    if rollType == nil then
        return
    end
    self:After(tonumber(self.db.delay) or 0, function()
        if RollOnLoot then
            RollOnLoot(rollID, rollType)
            local label = rollType == 1 and L.ROLL_NEED or rollType == 2 and L.ROLL_GREED or L.ROLL_PASS
            self:Print(L.ROLL_DONE:format(label, name or "?"))
        end
    end)
end

--------------------------------------------------------------------------
-- Loot confirmations (bind on pickup, roll warnings)
--------------------------------------------------------------------------

local LootConfirm = ns:NewModule("LootConfirm", {
    group = "LOOT",
    defaults = { enabled = false },
    options = {
        { type = "description", text = "LOOTCONFIRM_HELP" },
    },
})

function LootConfirm:OnEnable()
    self:RegisterEvent("LOOT_BIND_CONFIRM", "OnBind")
    self:RegisterEvent("CONFIRM_LOOT_ROLL", "OnRollConfirm")
    self:RegisterEvent("CONFIRM_DISENCHANT_ROLL", "OnRollConfirm")
end

function LootConfirm:OnBind(_, slot)
    if slot and ConfirmLootSlot then
        ConfirmLootSlot(slot)
        if StaticPopup_Hide then
            StaticPopup_Hide("LOOT_BIND")
        end
    end
end

function LootConfirm:OnRollConfirm(_, rollID, rollType)
    if rollID and ConfirmLootRoll then
        ConfirmLootRoll(rollID, rollType)
        if StaticPopup_Hide then
            StaticPopup_Hide("CONFIRM_LOOT_ROLL")
        end
    end
end

--------------------------------------------------------------------------
-- Loot announce: tell the group about your good drops
--------------------------------------------------------------------------

local LootAnnounce = ns:NewModule("LootAnnounce", {
    group = "LOOT",
    defaults = { enabled = false, quality = 3, channel = "GROUP" },
    options = {
        { key = "quality", type = "select", label = "LA_QUALITY", choices = function()
            return { { 2, L.QUALITY_2 }, { 3, L.QUALITY_3 }, { 4, L.QUALITY_4 } }
        end },
        { key = "channel", type = "select", label = "LA_CHANNEL", choices = function()
            return { { "GROUP", L.CHANNEL_GROUP }, { "SAY", L.CHANNEL_SAY }, { "PRINT", L.CHANNEL_PRINT } }
        end },
    },
})

local function ItemLinkIn(text)
    return type(text) == "string" and text:match("(|c%x+|Hitem:.-|h%[.-%]|h|r)") or nil
end
ns.ItemLinkIn = ItemLinkIn

function LootAnnounce:OnEnable()
    self:RegisterEvent("CHAT_MSG_LOOT", "OnLoot")
end

function LootAnnounce:OnLoot(_, text, _, _, _, looter)
    if not ns.IsMe(looter) then
        return
    end
    local link = ItemLinkIn(text)
    if not link then
        return
    end
    local quality = ns.Plain(select(3, C_Item.GetItemInfo(link)))
    if not quality or quality < (tonumber(self.db.quality) or 3) then
        return
    end
    local message = L.LA_MESSAGE:format(link)
    local channel = self.db.channel
    if channel == "PRINT" then
        self:Print(message)
        return
    end
    if channel == "GROUP" then
        channel = ns.GroupChannel()
        if not channel then
            return
        end
    end
    if SendChatMessage then
        SendChatMessage(message, channel)
    end
end

--------------------------------------------------------------------------
-- Rare alert: shout when a rare or elite boss shows up around you
--------------------------------------------------------------------------

local RareAlert = ns:NewModule("RareAlert", {
    group = "LOOT",
    defaults = { enabled = true, sound = true, elites = false, cooldown = 10 },
    options = {
        { key = "sound", type = "toggle", label = "RA_SOUND" },
        { key = "elites", type = "toggle", label = "RA_ELITES", tooltip = "RA_ELITES_TT" },
        { key = "cooldown", type = "range", label = "RA_COOLDOWN", min = 1, max = 60, step = 1, format = "%dm" },
    },
})

local RARE_TYPES = { rare = true, rareelite = true, worldboss = true }

function RareAlert:OnEnable()
    self.seen = {}
    self:RegisterEvent("NAME_PLATE_UNIT_ADDED", "Check")
    self:RegisterEvent("PLAYER_TARGET_CHANGED", function(module) module:Check(nil, "target") end)
    self:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function(module) module:Check(nil, "mouseover") end)
end

function RareAlert:Check(_, unit)
    if not unit or not UnitExists(unit) or UnitIsPlayer(unit) then
        return
    end
    if UnitIsDead and UnitIsDead(unit) then
        return
    end
    local classification = ns.Plain(UnitClassification and UnitClassification(unit))
    if not classification then
        return
    end
    if not RARE_TYPES[classification] and not (self.db.elites and classification == "elite") then
        return
    end
    local guid = ns.Plain(UnitGUID(unit)) or ns.Plain(UnitName(unit))
    if not guid then
        return
    end
    local now = GetTime()
    local last = self.seen[guid]
    if last and now - last < (tonumber(self.db.cooldown) or 10) * 60 then
        return
    end
    self.seen[guid] = now
    local name = ns.Plain(UnitName(unit)) or "?"
    local level = ns.Plain(UnitLevel(unit))
    local text = L.RA_FOUND:format(name, level and level > 0 and (" (" .. level .. ")") or "")
    local _, x, y = ns.PlayerMapPosition()
    if x then
        text = text .. (" [%.1f, %.1f]"):format(x * 100, y * 100)
    end
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, { r = 1, g = 0.5, b = 1 })
    end
    self:Print(text)
    if self.db.sound then
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
    end
end
