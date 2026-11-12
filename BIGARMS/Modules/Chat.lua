local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- Chat helpers shared by the chat modules
--------------------------------------------------------------------------

function ns.AddChatFilter(event, fn)
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter(event, fn)
        return true
    elseif ChatFrame_AddMessageEventFilter then
        ChatFrame_AddMessageEventFilter(event, fn)
        return true
    end
    return false
end

function ns.RemoveChatFilter(event, fn)
    if ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter then
        ChatFrameUtil.RemoveMessageEventFilter(event, fn)
    elseif ChatFrame_RemoveMessageEventFilter then
        ChatFrame_RemoveMessageEventFilter(event, fn)
    end
end

-- Every chat window frame (ChatFrame1..N), including temporary ones.
function ns.ChatFrames()
    local frames = {}
    for i = 1, (NUM_CHAT_WINDOWS or 10) do
        local frame = _G["ChatFrame" .. i]
        if frame then
            frames[#frames + 1] = frame
        end
    end
    return frames
end

local function EscapePattern(text)
    return (text:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1"))
end
ns.EscapePattern = EscapePattern

--------------------------------------------------------------------------
-- Chat tweaks
--------------------------------------------------------------------------

local Chat = ns:NewModule("Chat", {
    group = "CHAT",
    needsReload = true,
    defaults = {
        enabled = true,
        timestamps = "KEEP", -- KEEP | none | "%H:%M " | "%H:%M:%S " | "%I:%M %p "
        urls = true,
        shortChannels = true,
        noFade = true,
        arrowKeys = true,
        hideButtons = false,
        classColors = true,
        sticky = false,
        fontSize = 0,
        wheelJump = true,
        copyButton = true,
        flashOnWhisper = true,
        history = true,
        historyLines = 60,
    },
    options = {
        { key = "timestamps", type = "select", label = "CHAT_TIMESTAMPS", choices = function()
            return {
                { "KEEP", L.CHOICE_KEEP }, { "none", L.CHOICE_OFF },
                { "%H:%M ", "14:05" }, { "%H:%M:%S ", "14:05:33" }, { "%I:%M %p ", "02:05 PM" },
            }
        end },
        { key = "urls", type = "toggle", label = "CHAT_URLS", tooltip = "CHAT_URLS_TT" },
        { key = "shortChannels", type = "toggle", label = "CHAT_SHORT", tooltip = "CHAT_SHORT_TT" },
        { key = "noFade", type = "toggle", label = "CHAT_NOFADE" },
        { key = "arrowKeys", type = "toggle", label = "CHAT_ARROWS", tooltip = "CHAT_ARROWS_TT" },
        { key = "hideButtons", type = "toggle", label = "CHAT_HIDE_BUTTONS", tooltip = "CHAT_HIDE_BUTTONS_TT" },
        { key = "classColors", type = "toggle", label = "CHAT_CLASS_COLORS" },
        { key = "sticky", type = "toggle", label = "CHAT_STICKY", tooltip = "CHAT_STICKY_TT" },
        { key = "fontSize", type = "range", label = "CHAT_FONT_SIZE", tooltip = "CHAT_FONT_SIZE_TT", min = 0, max = 24, step = 1, format = "%d" },
        { key = "wheelJump", type = "toggle", label = "CHAT_WHEEL", tooltip = "CHAT_WHEEL_TT" },
        { key = "copyButton", type = "toggle", label = "CHAT_COPY_BUTTON", tooltip = "CHAT_COPY_BUTTON_TT" },
        { key = "flashOnWhisper", type = "toggle", label = "CHAT_FLASH" },
        { key = "history", type = "toggle", label = "CHAT_HISTORY", tooltip = "CHAT_HISTORY_TT" },
        { key = "historyLines", type = "range", label = "CHAT_HISTORY_LINES", min = 10, max = 200, step = 10, format = "%d" },
    },
})
ns.Chat = Chat

-- URL detection ------------------------------------------------------------

local URL_PATTERNS = {
    "(%a[%w+.-]+://%S+)",
    "%f[%S](www%.[-%w_%%]+%.%S+)",
    "%f[%S]([-%w_%%.]+@[-%w_%%]+%.[-%w_%%.]+)",
    "%f[%S](%d%d?%d?%.%d%d?%d?%.%d%d?%d?%.%d%d?%d?:%d%d?%d?%d?%d?)",
}

local function LinkifyURL(url)
    -- trailing punctuation is almost never part of the address
    local tail = ""
    local trimmed = url:match("^(.-)([%.,;:!%?%)%]]*)$")
    if trimmed and trimmed ~= "" and trimmed ~= url then
        tail = url:sub(#trimmed + 1)
        url = trimmed
    end
    return ("|Haddon:BIGARMS:url:%s|h|cff4da6ff[%s]|r|h%s"):format(url, url, tail)
end

function ns.LinkifyURLs(text)
    if type(text) ~= "string" or text:find("|Haddon:BIGARMS:url:", 1, true) then
        return text
    end
    -- never touch existing hyperlinks: split around |H...|h...|h blocks
    local out, pos = {}, 1
    while true do
        local s, e = text:find("|H.-|h.-|h", pos)
        local plain = text:sub(pos, (s or 0) - 1)
        for _, pattern in ipairs(URL_PATTERNS) do
            plain = plain:gsub(pattern, LinkifyURL)
        end
        out[#out + 1] = plain
        if not s then
            break
        end
        out[#out + 1] = text:sub(s, e)
        pos = e + 1
    end
    return table.concat(out)
end

-- Short channel labels ------------------------------------------------------

local SHORT_LABELS = {
    SAY = "S", YELL = "Y", PARTY = "P", PARTY_LEADER = "PL", PARTY_GUIDE = "PG",
    RAID = "R", RAID_LEADER = "RL", RAID_WARNING = "RW", GUILD = "G", OFFICER = "O",
    INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL", BATTLEGROUND = "BG", BATTLEGROUND_LEADER = "BGL",
}

local shortReplacements -- { { pattern, replacement } }

local function BuildShortReplacements()
    shortReplacements = {}
    for chatType, short in pairs(SHORT_LABELS) do
        local format = _G["CHAT_" .. chatType .. "_GET"]
        local label = type(format) == "string" and format:match("%[(.-)%]")
        if label and label ~= "" then
            shortReplacements[#shortReplacements + 1] = {
                "|h%[" .. EscapePattern(label) .. "%]|h", "|h[" .. short .. "]|h",
            }
        end
    end
end

function ns.ShortenChannels(text)
    if type(text) ~= "string" then
        return text
    end
    if not shortReplacements then
        BuildShortReplacements()
    end
    -- "[1. General]" -> "[1]"
    text = text:gsub("|Hchannel:channel:(%d+)|h%[(%d+)%. [^%]]-%]|h", "|Hchannel:channel:%1|h[%2]|h")
    for _, pair in ipairs(shortReplacements) do
        text = text:gsub(pair[1], pair[2])
    end
    return text
end

-- AddMessage hook ----------------------------------------------------------

local whisperTypes -- [chatTypeID] = true

local function IsWhisperType(typeID)
    if not whisperTypes then
        whisperTypes = {}
        if GetChatTypeIndex then
            for _, name in ipairs({ "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "BN_WHISPER_INFORM" }) do
                local id = GetChatTypeIndex(name)
                if id then
                    whisperTypes[id] = true
                end
            end
        end
    end
    return typeID ~= nil and whisperTypes[typeID] == true
end

local replaying = false

function Chat:RecordHistory(frame, text, r, g, b, typeID)
    if replaying or not self.db.history or frame ~= ChatFrame1 then
        return
    end
    if IsWhisperType(typeID) or type(text) ~= "string" or text == "" then
        return
    end
    local history = ns.char.chatHistory
    history[#history + 1] = { text, r or 1, g or 1, b or 1 }
    local limit = tonumber(self.db.historyLines) or 60
    while #history > limit do
        table.remove(history, 1)
    end
end

function Chat:HookAddMessage(frame)
    if frame.bigarmsHooked then
        return
    end
    frame.bigarmsHooked = true
    local original = frame.AddMessage
    local module = self
    frame.AddMessage = function(self_, text, r, g, b, typeID, ...)
        if module.enabled and type(text) == "string" then
            if module.db.urls then
                text = ns.LinkifyURLs(text)
            end
            if module.db.shortChannels then
                text = ns.ShortenChannels(text)
            end
            module:RecordHistory(self_, text, r, g, b, typeID)
        end
        return original(self_, text, r, g, b, typeID, ...)
    end
end

function Chat:ReplayHistory()
    if not self.db.history or not ChatFrame1 then
        return
    end
    local history = ns.char.chatHistory
    if #history == 0 then
        return
    end
    replaying = true
    for _, line in ipairs(history) do
        ChatFrame1:AddMessage(line[1], line[2], line[3], line[4])
    end
    ChatFrame1:AddMessage("|cff888888" .. L.CHAT_HISTORY_END .. "|r", 0.6, 0.6, 0.6)
    replaying = false
end

-- URL copy box -------------------------------------------------------------

local urlBox

local function ShowURLBox(url)
    if not urlBox then
        urlBox = CreateFrame("Frame", "BIGARMSURLBox", UIParent, "BackdropTemplate")
        urlBox:SetSize(420, 60)
        urlBox:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
        urlBox:SetFrameStrata("DIALOG")
        urlBox:EnableMouse(true)
        urlBox:SetMovable(true)
        urlBox:RegisterForDrag("LeftButton")
        urlBox:SetScript("OnDragStart", urlBox.StartMoving)
        urlBox:SetScript("OnDragStop", urlBox.StopMovingOrSizing)
        if urlBox.SetBackdrop then
            urlBox:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 },
            })
        end
        local title = urlBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", urlBox, "TOP", 0, -10)
        title:SetText(L.CHAT_URL_COPY)
        local edit = CreateFrame("EditBox", nil, urlBox, "InputBoxTemplate")
        edit:SetSize(360, 20)
        edit:SetPoint("BOTTOM", urlBox, "BOTTOM", 0, 12)
        edit:SetAutoFocus(false)
        edit:SetScript("OnEscapePressed", function() urlBox:Hide() end)
        edit:SetScript("OnEnterPressed", function() urlBox:Hide() end)
        edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        urlBox.edit = edit
        local close = CreateFrame("Button", nil, urlBox, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", urlBox, "TOPRIGHT", 2, 2)
    end
    urlBox.edit:SetText(url)
    urlBox:Show()
    urlBox.edit:SetFocus()
    urlBox.edit:HighlightText()
end
ns.ShowURLBox = ShowURLBox

local function HandleAddonLink(link)
    if type(link) ~= "string" then
        return false
    end
    local url = link:match("^addon:BIGARMS:url:(.+)$")
    if url then
        ShowURLBox(url)
        return true
    end
    return false
end

function Chat:HookLinks()
    if self.linksHooked then
        return
    end
    self.linksHooked = true
    local lastLink, lastTime
    local function OnLink(link)
        -- both hooks can fire for one click
        local now = GetTime()
        if link == lastLink and lastTime == now then
            return
        end
        lastLink, lastTime = link, now
        HandleAddonLink(link)
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(_, link) OnLink(link) end, self)
    end
    ns.SecureHook("SetItemRef", function(link) OnLink(link) end)
end

-- Copy window ----------------------------------------------------------------

local copyFrame

local function CleanLine(text)
    text = text:gsub("|T.-|t", "") -- textures
    text = text:gsub("|A.-|a", "") -- atlases
    text = text:gsub("|H.-|h(.-)|h", "%1") -- links -> their text
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|n", "\n")
    return text
end
ns.CleanChatLine = CleanLine

function ns.GetChatText(frame)
    frame = frame or ChatFrame1
    local lines = {}
    if frame and frame.GetNumMessages and frame.GetMessageInfo then
        for i = 1, frame:GetNumMessages() do
            local text = frame:GetMessageInfo(i)
            if type(text) == "string" then
                lines[#lines + 1] = CleanLine(text)
            end
        end
    end
    return table.concat(lines, "\n")
end

function ns.ShowChatCopy(frame)
    if not copyFrame then
        copyFrame = CreateFrame("Frame", "BIGARMSChatCopy", UIParent, "BackdropTemplate")
        copyFrame:SetSize(560, 420)
        copyFrame:SetPoint("CENTER")
        copyFrame:SetFrameStrata("DIALOG")
        copyFrame:EnableMouse(true)
        copyFrame:SetMovable(true)
        copyFrame:RegisterForDrag("LeftButton")
        copyFrame:SetScript("OnDragStart", copyFrame.StartMoving)
        copyFrame:SetScript("OnDragStop", copyFrame.StopMovingOrSizing)
        if copyFrame.SetBackdrop then
            copyFrame:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 },
            })
        end
        local title = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", copyFrame, "TOP", 0, -12)
        title:SetText(L.CHAT_COPY_TITLE)
        local close = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", copyFrame, "TOPRIGHT", 2, 2)
        local scroll = CreateFrame("ScrollFrame", "BIGARMSChatCopyScroll", copyFrame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", copyFrame, "TOPLEFT", 16, -36)
        scroll:SetPoint("BOTTOMRIGHT", copyFrame, "BOTTOMRIGHT", -36, 16)
        local edit = CreateFrame("EditBox", nil, scroll)
        edit:SetMultiLine(true)
        edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal or GameFontHighlight)
        edit:SetWidth(500)
        edit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
        scroll:SetScrollChild(edit)
        copyFrame.edit = edit
        tinsert(UISpecialFrames, "BIGARMSChatCopy")
    end
    copyFrame.edit:SetText(ns.GetChatText(frame))
    copyFrame:Show()
    copyFrame.edit:SetFocus()
    copyFrame.edit:HighlightText(0, 0)
    copyFrame.edit:SetCursorPosition(0)
end

function Chat:CreateCopyButton(frame)
    if frame.bigarmsCopy or frame ~= ChatFrame1 then
        return
    end
    local button = CreateFrame("Button", nil, frame)
    button:SetSize(20, 20)
    button:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    button:SetAlpha(0.25)
    button:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    button:SetHighlightTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    button:SetScript("OnClick", function() ns.ShowChatCopy(frame) end)
    button:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText(L.CHAT_COPY_TITLE)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function(self)
        self:SetAlpha(0.25)
        GameTooltip:Hide()
    end)
    frame.bigarmsCopy = button
end

-- Per-frame setup --------------------------------------------------------------

local HIDDEN_BUTTONS = {
    "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
    "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton",
}

function Chat:ApplyToFrame(frame, index)
    local db = self.db
    self:HookAddMessage(frame)
    if db.noFade and frame.SetFading then
        frame:SetFading(false)
    elseif frame.SetFading then
        frame:SetFading(true)
    end
    if db.wheelJump and not frame.bigarmsWheel then
        frame.bigarmsWheel = true
        self:HookScript(frame, "OnMouseWheel", function(module, self_, delta)
            if not module.db.wheelJump or not IsControlKeyDown() then
                return
            end
            if delta > 0 then
                self_:ScrollToTop()
            else
                self_:ScrollToBottom()
            end
        end)
    end
    local editBox = frame.editBox or _G["ChatFrame" .. index .. "EditBox"]
    if editBox and editBox.SetAltArrowKeyMode then
        editBox:SetAltArrowKeyMode(not db.arrowKeys)
    end
    if (tonumber(db.fontSize) or 0) >= 8 and FCF_SetChatWindowFontSize then
        pcall(FCF_SetChatWindowFontSize, nil, frame, db.fontSize)
    end
    if db.hideButtons then
        local buttonFrame = _G["ChatFrame" .. index .. "ButtonFrame"]
        if buttonFrame and not buttonFrame.bigarmsHidden then
            buttonFrame.bigarmsHidden = true
            buttonFrame:Hide()
            self:HookScript(buttonFrame, "OnShow", function(module, self_)
                if module.db.hideButtons then
                    self_:Hide()
                end
            end)
        end
    end
    if db.copyButton then
        self:CreateCopyButton(frame)
    elseif frame.bigarmsCopy then
        frame.bigarmsCopy:Hide()
    end
    if frame.bigarmsCopy then
        frame.bigarmsCopy:SetShown(db.copyButton)
    end
end

function Chat:ApplyGlobal()
    local db = self.db
    if db.timestamps ~= "KEEP" then
        ns.SetCVar("showTimestamps", db.timestamps)
    end
    if db.classColors and SetChatColorNameByClass and ChatTypeInfo then
        for chatType in pairs(ChatTypeInfo) do
            pcall(SetChatColorNameByClass, chatType, true)
        end
    end
    if db.sticky and ChatTypeInfo then
        for _, chatType in ipairs({ "WHISPER", "BN_WHISPER", "OFFICER", "RAID_WARNING", "YELL", "EMOTE", "CHANNEL" }) do
            if ChatTypeInfo[chatType] then
                ChatTypeInfo[chatType].sticky = 1
            end
        end
    end
    if db.hideButtons then
        for _, name in ipairs(HIDDEN_BUTTONS) do
            local button = _G[name]
            if button and not button.bigarmsHidden then
                button.bigarmsHidden = true
                button:Hide()
                self:HookScript(button, "OnShow", function(module, self_)
                    if module.db.hideButtons then
                        self_:Hide()
                    end
                end)
            end
        end
    end
end

function Chat:ApplyAll()
    self:ApplyGlobal()
    for index, frame in ipairs(ns.ChatFrames()) do
        self:ApplyToFrame(frame, index)
    end
end

function Chat:OnEnable()
    if self.db.urls then
        self:HookLinks()
    end
    self:ApplyAll()
    self:RegisterEvent("CHAT_MSG_WHISPER", "OnWhisper")
    self:RegisterEvent("CHAT_MSG_BN_WHISPER", "OnWhisper")
    self:RegisterEvent("UPDATE_CHAT_WINDOWS", "ApplyAll")
    self:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS", "ApplyAll")
    if not self.replayed then
        self.replayed = true
        self:After(0.5, self.ReplayHistory)
    end
    -- new temporary windows (whisper tabs) get the same treatment
    if FCF_OpenTemporaryWindow and not self.tempHooked then
        self.tempHooked = true
        self:SecureHook("FCF_OpenTemporaryWindow", function(module)
            module:After(0, module.ApplyAll)
        end)
    end
end

function Chat:OnDisable()
    for _, frame in ipairs(ns.ChatFrames()) do
        if frame.SetFading then
            frame:SetFading(true)
        end
        if frame.bigarmsCopy then
            frame.bigarmsCopy:Hide()
        end
    end
end

function Chat:OnSettingChanged(key)
    if key == "urls" and self.db.urls then
        self:HookLinks()
    end
    self:ApplyAll()
end

function Chat:OnWhisper()
    if self.db.flashOnWhisper and FlashClientIcon then
        FlashClientIcon()
    end
end

--------------------------------------------------------------------------
-- Keyword invite: whisper "inv" to get a group invite
--------------------------------------------------------------------------

local KeywordInvite = ns:NewModule("KeywordInvite", {
    group = "CHAT",
    defaults = { enabled = false, keyword = "inv 초대 ㅊㄷ", who = "FRIENDS", reply = true },
    options = {
        { key = "keyword", type = "text", label = "KI_KEYWORD", tooltip = "KI_KEYWORD_TT" },
        { key = "who", type = "select", label = "KI_WHO", choices = function()
            return { { "FRIENDS", L.CHOICE_FRIENDS_GUILD }, { "ALL", L.CHOICE_EVERYONE } }
        end },
        { key = "reply", type = "toggle", label = "KI_REPLY", tooltip = "KI_REPLY_TT" },
    },
})

function KeywordInvite:OnEnable()
    self:RegisterEvent("CHAT_MSG_WHISPER", "OnWhisper")
    self:RegisterEvent("CHAT_MSG_BN_WHISPER", "OnBNWhisper")
end

function KeywordInvite:Matches(text)
    text = ns.Trim(text):lower()
    if text == "" then
        return false
    end
    for word in tostring(self.db.keyword or ""):gmatch("%S+") do
        if word:lower() == text then
            return true
        end
    end
    return false
end

local function CanInvite()
    if not IsInGroup or not IsInGroup() then
        return true
    end
    if UnitIsGroupLeader and UnitIsGroupLeader("player") then
        return true
    end
    if UnitIsGroupAssistant and UnitIsGroupAssistant("player") then
        return true
    end
    return false
end

function KeywordInvite:OnWhisper(_, text, sender, _, _, _, _, _, _, _, _, _, guid)
    if not self:Matches(text) or not CanInvite() then
        return
    end
    if self.db.who == "FRIENDS" and not ns.IsFriendOrGuild(sender, guid) then
        return
    end
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(sender)
    elseif InviteUnit then
        InviteUnit(sender)
    else
        return
    end
    self:Print(L.KI_INVITED:format(sender))
end

function KeywordInvite:OnBNWhisper(_, text, _, _, _, _, _, _, _, _, _, _, _, bnSenderID)
    if not self:Matches(text) or not CanInvite() or not bnSenderID then
        return
    end
    if not (C_BattleNet and C_BattleNet.GetAccountInfoByID) then
        return
    end
    local info = C_BattleNet.GetAccountInfoByID(bnSenderID)
    local game = info and info.gameAccountInfo
    if game and game.gameAccountID and BNInviteFriend then
        BNInviteFriend(game.gameAccountID)
        self:Print(L.KI_INVITED:format(game.characterName or info.accountName or "?"))
    end
end
