local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Pull timer: /pull 10
--------------------------------------------------------------------------

local PullTimer = ns:NewModule("PullTimer", {
    group = "GROUP",
    defaults = { enabled = true, seconds = 10, sound = true, screen = true, builtin = true },
    options = {
        { key = "seconds", type = "range", label = "PT_SECONDS", min = 3, max = 30, step = 1, format = "%ds" },
        { key = "builtin", type = "toggle", label = "PT_BUILTIN", tooltip = "PT_BUILTIN_TT" },
        { key = "sound", type = "toggle", label = "PT_SOUND" },
        { key = "screen", type = "toggle", label = "PT_SCREEN" },
        { type = "description", text = "PT_HELP" },
    },
})
ns.PullTimer = PullTimer

local function AnnounceChannel()
    if IsInRaid and IsInRaid() and ((UnitIsGroupLeader and UnitIsGroupLeader("player")) or (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))) then
        return "RAID_WARNING"
    end
    return ns.GroupChannel()
end

function PullTimer:Say(text)
    local channel = AnnounceChannel()
    if channel and SendChatMessage then
        SendChatMessage(text, channel)
    else
        self:Print(text)
    end
end

function PullTimer:Flash(text)
    if not self.db.screen then
        return
    end
    local alert = ns:GetModule("CombatAlert")
    if alert and alert.Flash then
        alert:Flash(text, 1, 0.8, 0.2)
    end
end

function PullTimer:Start(seconds)
    seconds = math.floor(tonumber(seconds) or tonumber(self.db.seconds) or 10)
    if seconds <= 0 then
        self:Cancel()
        return
    end
    if self.db.builtin and C_PartyInfo and C_PartyInfo.DoCountdown and IsInGroup and IsInGroup() then
        local ok = pcall(C_PartyInfo.DoCountdown, seconds)
        if ok then
            return
        end
    end
    self:Cancel()
    self.remaining = seconds
    self:Say(L.PT_START:format(seconds))
    self:Flash(tostring(seconds))
    self.ticker = self:Ticker(1, self.Tick)
end

function PullTimer:Tick()
    if not self.remaining then
        return
    end
    self.remaining = self.remaining - 1
    local left = self.remaining
    if left <= 0 then
        self:Say(L.PT_GO)
        self:Flash(L.PT_GO)
        if self.db.sound then
            PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959)
        end
        self:Cancel()
        return
    end
    if left <= 5 or left % 5 == 0 then
        self:Say(L.PT_COUNT:format(left))
    end
    if left <= 5 then
        self:Flash(tostring(left))
        if self.db.sound and left <= 3 then
            PlaySound(SOUNDKIT and SOUNDKIT.MAP_PING or 3175)
        end
    end
end

function PullTimer:Cancel()
    if self.ticker then
        self.ticker:Cancel()
        self.ticker = nil
    end
    if self.remaining and self.remaining > 0 then
        self:Say(L.PT_CANCELLED)
    end
    self.remaining = nil
end

function PullTimer:OnEnable()
    if not self.slashRegistered and not ns.IsSlashTaken("/pull") then
        self.slashRegistered = true
        SLASH_BIGARMS_PULL1 = "/pull"
        SlashCmdList["BIGARMS_PULL"] = function(msg)
            if PullTimer.enabled then
                PullTimer:Start(ns.Trim(msg) ~= "" and tonumber(msg) or nil)
            end
        end
    end
end

function PullTimer:OnDisable()
    self:Cancel()
end

--------------------------------------------------------------------------
-- Group tools: ready checks, battleground entry, role prompts
--------------------------------------------------------------------------

local GroupTools = ns:NewModule("GroupTools", {
    group = "GROUP",
    defaults = { enabled = true, readyCheck = false, bgQueue = false, readySound = true, joinLeaveChat = true },
    options = {
        { key = "readyCheck", type = "toggle", label = "GT_READY", tooltip = "GT_READY_TT" },
        { key = "readySound", type = "toggle", label = "GT_READY_SOUND" },
        { key = "bgQueue", type = "toggle", label = "GT_BG", tooltip = "GT_BG_TT" },
        { key = "joinLeaveChat", type = "toggle", label = "GT_ROSTER", tooltip = "GT_ROSTER_TT" },
    },
})

function GroupTools:OnEnable()
    self:RegisterEvent("READY_CHECK", "OnReadyCheck")
    self:RegisterEvent("UPDATE_BATTLEFIELD_STATUS", "OnBattlefield")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnRoster")
    self.roster = self:Roster()
end

function GroupTools:OnReadyCheck(_, initiator)
    if self.db.readySound then
        PlaySound(SOUNDKIT and SOUNDKIT.READY_CHECK or 8960)
    end
    if not self.db.readyCheck or ns.IsMe(initiator) then
        return
    end
    if UnitIsAFK and UnitIsAFK("player") then
        return
    end
    if ConfirmReadyCheck then
        ConfirmReadyCheck(true)
        if ReadyCheckFrame and ReadyCheckFrame.Hide then
            ReadyCheckFrame:Hide()
        end
        self:Print(L.GT_READY_DONE:format(initiator or "?"))
    end
end

function GroupTools:OnBattlefield(_, index)
    if not self.db.bgQueue or not index or not GetBattlefieldStatus then
        return
    end
    local status, mapName = GetBattlefieldStatus(index)
    if status == "confirm" and AcceptBattlefieldPort then
        AcceptBattlefieldPort(index, true)
        if StaticPopup_Hide then
            StaticPopup_Hide("CONFIRM_BATTLEFIELD_ENTRY")
        end
        self:Print(L.GT_BG_JOINED:format(mapName or "?"))
    end
end

-- names currently in the group
function GroupTools:Roster()
    local names = {}
    if not (IsInGroup and IsInGroup()) then
        return names
    end
    local prefix = (IsInRaid and IsInRaid()) and "raid" or "party"
    local count = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, count do
        local unit = prefix .. i
        if prefix == "party" and i == count then
            break
        end
        local name = ns.Plain(UnitName(unit))
        if name then
            names[name] = true
        end
    end
    return names
end

function GroupTools:OnRoster()
    local now = self:Roster()
    if self.db.joinLeaveChat and self.roster then
        for name in pairs(now) do
            if not self.roster[name] then
                self:Print(L.GT_JOINED:format(name))
            end
        end
        for name in pairs(self.roster) do
            if not now[name] then
                self:Print(L.GT_LEFT:format(name))
            end
        end
    end
    self.roster = now
end

--------------------------------------------------------------------------
-- Interrupt announce
--------------------------------------------------------------------------

local InterruptAnnounce = ns:NewModule("InterruptAnnounce", {
    group = "GROUP",
    defaults = { enabled = false, channel = "GROUP" },
    options = {
        { key = "channel", type = "select", label = "IA_CHANNEL", choices = function()
            return { { "GROUP", L.CHANNEL_GROUP }, { "SAY", L.CHANNEL_SAY }, { "YELL", L.CHANNEL_YELL }, { "PRINT", L.CHANNEL_PRINT } }
        end },
    },
})

-- Base spell IDs of interrupts; ranks share the name
local INTERRUPT_IDS = { 1766, 6552, 72, 2139, 8042, 19244, 19647, 16979, 2649 }

function InterruptAnnounce:Names()
    if self.names then
        return self.names
    end
    self.names = {}
    if C_Spell and C_Spell.GetSpellName then
        for _, id in ipairs(INTERRUPT_IDS) do
            local name = C_Spell.GetSpellName(id)
            if name then
                self.names[name] = true
            end
        end
    end
    return self.names
end

function InterruptAnnounce:OnEnable()
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnCast")
end

function InterruptAnnounce:OnCast(_, unit, _, spellID)
    if unit ~= "player" and unit ~= "pet" then
        return
    end
    spellID = ns.Plain(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellName) then
        return
    end
    local name = C_Spell.GetSpellName(spellID)
    if not name or not self:Names()[name] then
        return
    end
    local targetUnit = unit .. "target"
    if not UnitExists(targetUnit) or (UnitCanAttack and not UnitCanAttack("player", targetUnit)) then
        return
    end
    local targetName = ns.Plain(UnitName(targetUnit)) or "?"
    local message = L.IA_MESSAGE:format(name, targetName)
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
