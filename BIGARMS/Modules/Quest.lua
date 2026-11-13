local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Quests: levels in the log, auto track, completion alert, party announce
--------------------------------------------------------------------------

local Quest = ns:NewModule("Quest", {
    group = "QUEST",
    needsReload = true,
    defaults = { enabled = true, levels = true, autoTrack = true, completeAlert = true, completeSound = true, announce = false, trackerScale = 1 },
    options = {
        { key = "trackerScale", type = "range", label = "Q_TRACKER_SCALE", tooltip = "Q_TRACKER_SCALE_TT", min = 0.5, max = 1.5, step = 0.05, format = "%.2f" },
        { key = "levels", type = "toggle", label = "Q_LEVELS", tooltip = "Q_LEVELS_TT" },
        { key = "autoTrack", type = "toggle", label = "Q_AUTOTRACK" },
        { key = "completeAlert", type = "toggle", label = "Q_COMPLETE_ALERT", tooltip = "Q_COMPLETE_ALERT_TT" },
        { key = "completeSound", type = "toggle", label = "Q_COMPLETE_SOUND" },
        { key = "announce", type = "toggle", label = "Q_ANNOUNCE", tooltip = "Q_ANNOUNCE_TT" },
    },
})

-- Quest log levels ------------------------------------------------------------------

local function QuestLevelColor(level)
    if GetQuestDifficultyColor then
        local color = GetQuestDifficultyColor(level)
        if color then
            return color.r, color.g, color.b
        end
    end
    return 1, 0.82, 0
end

function Quest:UpdateQuestLogTitles()
    if not self.db.levels then
        return
    end
    local pool = QuestScrollFrame and QuestScrollFrame.titleFramePool
    if not pool or not pool.EnumerateActive or not C_QuestLog or not C_QuestLog.GetInfo then
        return
    end
    for frame in pool:EnumerateActive() do
        local index = frame.questLogIndex
        local info = index and C_QuestLog.GetInfo(index)
        local text = frame.Text or frame.Title
        if info and text and info.level and info.title then
            local current = text:GetText()
            if type(current) == "string" and not current:find("^%[") then
                local r, g, b = QuestLevelColor(info.level)
                text:SetText(("|cff%02x%02x%02x[%d]|r %s"):format(r * 255, g * 255, b * 255, info.level, info.title))
            end
        end
    end
end

function Quest:HookQuestLog()
    if self.logHooked then
        return
    end
    self.logHooked = true
    local module = self
    if QuestLogQuests_Update then
        hooksecurefunc("QuestLogQuests_Update", function()
            if module.enabled then
                module:After(0, module.UpdateQuestLogTitles)
            end
        end)
    end
    if QuestMapFrame and QuestMapFrame.UpdateAll then
        hooksecurefunc(QuestMapFrame, "UpdateAll", function()
            if module.enabled then
                module:After(0, module.UpdateQuestLogTitles)
            end
        end)
    end
end

-- Auto track -----------------------------------------------------------------------------

function Quest:ApplyAutoTrack()
    if ns.CVarExists("autoQuestWatch") then
        ns.SetCVar("autoQuestWatch", self.db.autoTrack and 1 or 0)
    end
end

function Quest:OnQuestAccepted(_, questID)
    if not self.db.autoTrack or not questID or not C_QuestLog or not C_QuestLog.AddQuestWatch then
        return
    end
    if C_QuestLog.GetQuestWatchType and C_QuestLog.GetQuestWatchType(questID) then
        return
    end
    pcall(C_QuestLog.AddQuestWatch, questID)
end

-- Completion alert ---------------------------------------------------------------------------

local function QuestTitle(questID)
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
        return C_QuestLog.GetTitleForQuestID(questID)
    end
    return nil
end

function Quest:OnWatchUpdate(_, questID)
    if not self.db.completeAlert or not questID or not C_QuestLog or not C_QuestLog.IsComplete then
        return
    end
    self.completed = self.completed or {}
    self:After(0.5, function(module)
        if not C_QuestLog.IsComplete(questID) then
            module.completed[questID] = nil
            return
        end
        if module.completed[questID] then
            return
        end
        module.completed[questID] = true
        local title = QuestTitle(questID) or ("#" .. questID)
        local text = L.Q_COMPLETE_TEXT:format(title)
        if RaidNotice_AddMessage and RaidWarningFrame then
            RaidNotice_AddMessage(RaidWarningFrame, text, { r = 1, g = 0.82, b = 0 })
        end
        module:Print(text)
        if module.db.completeSound then
            PlaySound(SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE or 6199)
        end
    end)
end

function Quest:OnQuestRemoved(_, questID)
    if self.completed then
        self.completed[questID] = nil
    end
end

-- Party announce -----------------------------------------------------------------------------

function Quest:OnInfoMessage(_, _, message)
    if not self.db.announce or type(message) ~= "string" or ns.IsSecret(message) then
        return
    end
    if not (IsInGroup and IsInGroup()) then
        return
    end
    -- objective progress lines look like "Name: 3/5" or end with "(Complete)"
    if not message:find(": ?%d+ ?/ ?%d+") and not message:find("%(") then
        return
    end
    local now = GetTime()
    if self.lastAnnounce == message and now - (self.lastAnnounceTime or 0) < 5 then
        return
    end
    self.lastAnnounce, self.lastAnnounceTime = message, now
    local channel = (IsInRaid and IsInRaid()) and "RAID" or "PARTY"
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then
        channel = "INSTANCE_CHAT"
    end
    if SendChatMessage then
        SendChatMessage(message, channel)
    end
end

-- Setup -----------------------------------------------------------------------------------

function Quest:OnEnable()
    self:HookQuestLog()
    self:ApplyAutoTrack()
    self:ApplyTrackerScale()
    self:RegisterEvent("QUEST_ACCEPTED", "OnQuestAccepted")
    self:RegisterEvent("QUEST_WATCH_UPDATE", "OnWatchUpdate")
    self:RegisterEvent("UNIT_QUEST_LOG_CHANGED", function(module, _, unit)
        if unit == "player" then
            module:After(0.2, module.UpdateQuestLogTitles)
        end
    end)
    self:RegisterEvent("QUEST_REMOVED", "OnQuestRemoved")
    self:RegisterEvent("UI_INFO_MESSAGE", "OnInfoMessage")
end

function Quest:ApplyTrackerScale()
    local tracker = ObjectiveTrackerFrame
    if tracker and tracker.SetScale and not InCombatLockdown() then
        tracker:SetScale(tonumber(self.db.trackerScale) or 1)
    end
end

function Quest:OnSettingChanged()
    self:ApplyAutoTrack()
    self:ApplyTrackerScale()
end
