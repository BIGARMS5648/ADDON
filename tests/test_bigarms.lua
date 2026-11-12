-- Behavior tests for BIGARMS against tests/bigarms_mock.lua.
-- Run with: python3 tests/run_bigarms_tests.py

local mock = _G.mock
local ns = _G.ns
local tests = {}

local function test(name, fn)
    tests[#tests + 1] = { name = name, fn = fn }
end

local function eq(actual, expected, msg)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(msg or "value", tostring(expected), tostring(actual)), 2)
    end
end

local function printed(pattern)
    for _, line in ipairs(mock.printed) do
        if line:find(pattern) then
            return line
        end
    end
    return nil
end

local function noErrors()
    local line = printed("|cffff4040")
    if line then
        error("module error reported: " .. line, 2)
    end
end

local function item(id, quality, sellPrice, extra)
    mock.items[id] = { name = "Item" .. id, quality = quality, sellPrice = sellPrice }
    for k, v in pairs(extra or {}) do mock.items[id][k] = v end
    return ("|cffffffff|Hitem:%d::::::::60:::::|h[Item%d]|h|r"):format(id, id)
end

local function bagItem(bag, slot, id, count, hasNoValue)
    mock.bags[bag] = mock.bags[bag] or {}
    local link = ("|cffffffff|Hitem:%d::::::::60:::::|h[Item%d]|h|r"):format(id, id)
    mock.bags[bag][slot] = { hyperlink = link, itemID = id, quality = mock.items[id].quality, stackCount = count or 1, hasNoValue = hasNoValue or false, isLocked = false }
end

-- boot --------------------------------------------------------------------------

test("loads, creates the database and enables default modules", function()
    mock.fire("ADDON_LOADED", "BIGARMS")
    mock.fire("PLAYER_LOGIN")
    mock.flushTimers()
    assert(BIGARMSDB and BIGARMSDB.modules, "account db")
    assert(BIGARMSCharDB and BIGARMSCharDB.junkIgnore, "character db")
    eq(#ns.modules, 28, "module count")
    local on, off = 0, 0
    for _, module in ipairs(ns.modules) do
        assert(module.db, "module db " .. module.name)
        if module.enabled then on = on + 1 else off = off + 1 end
        eq(module.enabled, module.db.enabled, "enabled matches db " .. module.name)
    end
    assert(on >= 20, "most modules on by default: " .. on)
    assert(not ns:GetModule("SwingTimer").enabled, "swing timer off by default")
    assert(not ns:GetModule("SkipCinematics").enabled, "skip cinematics off by default")
    assert(printed("/ba"), "loaded message")
    noErrors()
end)

test("settings panel has a control for every option", function()
    assert(mock.registeredCategory, "category registered")
    local controls = 0
    for _, s in pairs(mock.settings) do
        if s.control then controls = controls + 1 end
    end
    local expected = 0
    for _, module in ipairs(ns.modules) do
        expected = expected + 1 -- enable switch
        for _, option in ipairs(module.options) do
            if option.type == "toggle" or option.type == "range" or option.type == "select" then
                expected = expected + 1
            end
        end
    end
    expected = expected + 2 -- minimap button, debug
    eq(controls, expected, "controls")
    for _, s in pairs(mock.settings) do
        assert(s.name and s.name ~= "" and not s.name:find("^[A-Z_]+$"), "label is a translated string: " .. tostring(s.name))
    end
end)

test("money formatting", function()
    local L = ns.L
    eq(ns.FormatMoney(0), "|cffeda55f0|r" .. L.COPPER_SHORT, "zero")
    assert(ns.FormatMoney(123456):find("12|r" .. L.GOLD_SHORT), "gold")
    assert(ns.FormatMoney(123456):find("34|r" .. L.SILVER_SHORT), "silver")
    assert(ns.FormatMoney(123456):find("56|r" .. L.COPPER_SHORT), "copper")
    assert(ns.FormatMoney(-5):sub(1, 1) == "-", "negative")
    assert(ns.FormatMoney(10000, true) == "|cffffd7001|r" .. L.GOLD_SHORT, "short drops zero parts")
end)

test("secret values are treated as unknown", function()
    assert(ns.IsSecret(mock.SECRET), "secret detected")
    eq(ns.Plain(mock.SECRET), nil, "plain of secret")
    eq(ns.Plain(5), 5, "plain of number")
end)

-- automation ------------------------------------------------------------------------

test("auto repair pays with own gold and reports", function()
    mock.reset()
    mock.money = 100000
    mock.merchant.repairCost = 2500
    mock.fire("MERCHANT_SHOW")
    eq(mock.count("RepairAllItems"), 1, "repaired")
    eq(mock.calls.RepairAllItems[1][1], false, "own gold")
    assert(printed("25|r"), "cost reported")
    mock.reset()
    mock.money = 100
    mock.fire("MERCHANT_SHOW")
    eq(mock.count("RepairAllItems"), 0, "no repair without gold")
    assert(printed(ns.L.REPAIR_NO_MONEY:sub(1, 5)), "told about missing gold")
    mock.money = 100000
    noErrors()
end)

test("junk selling sells grey items only and honours keep / always lists", function()
    mock.reset()
    mock.merchant.repairCost = 0
    item(1001, 0, 50) -- grey
    item(1002, 1, 500) -- white
    item(1003, 0, 0) -- grey, worthless
    item(1004, 0, 70) -- grey but kept
    item(1005, 2, 900) -- green, always sell
    bagItem(0, 1, 1001, 3)
    bagItem(0, 2, 1002)
    bagItem(1, 1, 1003, 1, true)
    bagItem(1, 2, 1004)
    bagItem(1, 3, 1005)
    BIGARMSCharDB.junkIgnore[1004] = true
    BIGARMSCharDB.junkSell[1005] = true
    local list = ns:GetModule("AutoSellJunk"):CollectJunk()
    eq(#list, 2, "two items to sell")
    mock.fire("MERCHANT_SHOW")
    mock.flushTimers()
    eq(mock.count("UseContainerItem"), 2, "sold two stacks")
    assert(printed("2"), "summary printed")
    assert(printed("10|r"), "total 150c + 900c = 10s 50c")
    mock.bags = {}
    noErrors()
end)

test("junk slash commands manage the lists", function()
    local module = ns:GetModule("AutoSellJunk")
    mock.reset()
    module:HandleCommand("keep |cffffffff|Hitem:777::::::::60:::::|h[Thing]|h|r")
    assert(BIGARMSCharDB.junkIgnore[777], "kept")
    module:HandleCommand("add 778")
    assert(BIGARMSCharDB.junkSell[778], "always sell")
    module:HandleCommand("list")
    assert(printed("777"), "list shows kept")
    module:HandleCommand("unkeep 777")
    assert(not BIGARMSCharDB.junkIgnore[777], "unkept")
end)

test("auto quest turns in, accepts and skips lonely gossip options", function()
    mock.reset()
    mock.gossip.active = { { questID = 1, title = "A", isComplete = false }, { questID = 2, title = "B", isComplete = true } }
    mock.gossip.available = { { questID = 3, title = "C", isTrivial = false } }
    mock.fire("GOSSIP_SHOW")
    eq(mock.count("SelectActiveQuest"), 1, "complete quest turned in first")
    eq(mock.calls.SelectActiveQuest[1][1], 2, "the complete one")
    eq(mock.count("SelectAvailableQuest"), 0, "one action per window")

    mock.reset()
    mock.gossip.active = {}
    mock.gossip.available = { { questID = 4, title = "Grey", isTrivial = true }, { questID = 5, title = "Daily", repeatable = true }, { questID = 6, title = "OK" } }
    mock.fire("GOSSIP_SHOW")
    eq(mock.calls.SelectAvailableQuest[1][1], 6, "trivial and repeatable skipped")

    mock.reset()
    mock.gossip.available = {}
    mock.gossip.options = { { gossipOptionID = 50, name = "Browse", status = 0 } }
    mock.fire("GOSSIP_SHOW")
    eq(mock.count("SelectOption"), 1, "single option picked")
    mock.gossip.options = { { gossipOptionID = 50 }, { gossipOptionID = 51 } }
    mock.reset()
    mock.fire("GOSSIP_SHOW")
    eq(mock.count("SelectOption"), 0, "two options left alone")
    mock.gossip.options = {}

    mock.reset()
    mock.fire("QUEST_DETAIL")
    eq(mock.count("AcceptQuest"), 1, "accepted")
    mock.quest.trivial = true
    mock.reset()
    mock.fire("QUEST_DETAIL")
    eq(mock.count("AcceptQuest"), 0, "trivial not accepted")
    mock.quest.trivial = false

    mock.reset()
    mock.fire("QUEST_PROGRESS")
    eq(mock.count("CompleteQuest"), 1, "completed")
    mock.quest.choices = 0
    mock.fire("QUEST_COMPLETE")
    mock.flushTimers()
    eq(mock.calls.GetQuestReward[1][1], 0, "no choice reward")
    mock.quest.choices = 1
    mock.reset()
    mock.fire("QUEST_COMPLETE")
    mock.flushTimers()
    eq(mock.calls.GetQuestReward[1][1], 1, "single choice reward")

    mock.quest.choices = 2
    mock.quest.choiceLinks = { item(2001, 2, 100), item(2002, 2, 5000) }
    mock.reset()
    mock.fire("QUEST_COMPLETE")
    mock.flushTimers()
    eq(mock.count("GetQuestReward"), 0, "never chooses between rewards")
    eq(ns:GetModule("AutoQuest").bestChoice, 2, "best reward marked")
    assert(printed("Item2002"), "best reward reported")
    mock.quest.choices = 0

    mock.shift = true
    mock.reset()
    mock.fire("QUEST_DETAIL")
    eq(mock.count("AcceptQuest"), 0, "pause key pauses")
    mock.shift = false

    BIGARMSCharDB.questBlock[100] = true
    mock.reset()
    mock.fire("QUEST_DETAIL")
    eq(mock.count("AcceptQuest"), 0, "blocked quest")
    BIGARMSCharDB.questBlock[100] = nil
    noErrors()
end)

test("auto accept: invites from friends, resurrections, summons", function()
    mock.reset()
    mock.fire("PARTY_INVITE_REQUEST", "Stranger", false, false, false, true, false, "Player-1-STRANGER")
    eq(mock.count("AcceptGroup"), 0, "stranger ignored")
    mock.fire("PARTY_INVITE_REQUEST", "Friend", false, false, false, true, false, "Player-1-FRIEND")
    eq(mock.count("AcceptGroup"), 1, "friend accepted")
    ns:GetModule("AutoAccept").db.invites = "ALL"
    mock.fire("PARTY_INVITE_REQUEST", "Stranger", false, false, false, true, false, "Player-1-STRANGER")
    eq(mock.count("AcceptGroup"), 2, "everyone accepted")
    ns:GetModule("AutoAccept").db.invites = "FRIENDS"

    mock.fire("RESURRECT_REQUEST", "Healer")
    eq(mock.count("AcceptResurrect"), 1, "resurrect accepted")
    mock.inCombat = true
    mock.fire("RESURRECT_REQUEST", "Healer")
    eq(mock.count("AcceptResurrect"), 1, "not in combat")
    mock.inCombat = false

    mock.fire("CONFIRM_SUMMON")
    mock.flushTimers()
    eq(mock.count("ConfirmSummon"), 1, "summon accepted")
    noErrors()
end)

test("auto decline: duels but not from friends", function()
    mock.reset()
    mock.fire("DUEL_REQUESTED", "Stranger")
    eq(mock.count("CancelDuel"), 1, "duel declined")
    mock.fire("DUEL_REQUESTED", "Friend")
    eq(mock.count("CancelDuel"), 1, "friend may duel")
    mock.fire("GUILD_INVITE_REQUEST", "Stranger", "Guild")
    eq(mock.count("DeclineGuild"), 0, "guild invites not declined by default")
    noErrors()
end)

test("auto release in battlegrounds only", function()
    mock.reset()
    mock.units.player.dead = true
    mock.fire("PLAYER_DEAD")
    mock.flushTimers()
    eq(mock.count("RepopMe"), 0, "not in the world")
    mock.inBattleground = true
    mock.fire("PLAYER_DEAD")
    mock.flushTimers()
    eq(mock.count("RepopMe"), 1, "released in battleground")
    mock.inBattleground = false
    mock.units.player.dead = false
end)

test("fast loot loots every slot once", function()
    mock.reset()
    mock.lootItems = 3
    mock.fire("LOOT_READY", true)
    eq(mock.count("LootSlot"), 3, "all slots")
    mock.fire("LOOT_READY", true)
    eq(mock.count("LootSlot"), 3, "not twice within 0.3s")
    mock.time = mock.time + 1
    mock.fire("LOOT_READY", false)
    eq(mock.count("LootSlot"), 3, "manual loot respected")
end)

test("easy delete fills in DELETE", function()
    mock.reset()
    local dialog = StaticPopup_Show("DELETE_GOOD_ITEM")
    eq(dialog.editBox:GetText(), "DELETE", "filled")
end)

test("auto stand and dismount react to error messages", function()
    mock.reset()
    mock.mounted = true
    mock.fire("UI_ERROR_MESSAGE", 1, ERR_ATTACK_MOUNTED)
    eq(mock.count("Dismount"), 1, "dismounted")
    mock.fire("UI_ERROR_MESSAGE", 2, SPELL_FAILED_NOT_STANDING)
    eq(mock.count("DoEmote"), 1, "stood up")
    mock.mounted = false
end)

test("keep tracking turns the chosen tracking back on", function()
    mock.reset()
    mock.tracking[1].active = true
    mock.fire("MINIMAP_UPDATE_TRACKING")
    eq(BIGARMSCharDB.tracking, "약초 찾기", "remembered")
    mock.tracking[1].active = false
    mock.fire("PLAYER_UNGHOST")
    mock.flushTimers()
    eq(mock.count("SetTracking"), 1, "restored")
    eq(mock.tracking[1].active, true, "active again")
    noErrors()
end)

test("skip cinematics is off by default and works when on", function()
    mock.reset()
    mock.fire("CINEMATIC_START")
    eq(mock.count("CinematicFrame_CancelCinematic"), 0, "off")
    ns:SetModuleEnabled("SkipCinematics", true)
    mock.fire("CINEMATIC_START")
    eq(mock.count("CinematicFrame_CancelCinematic"), 1, "skipped")
    mock.shift = true
    mock.fire("CINEMATIC_START")
    eq(mock.count("CinematicFrame_CancelCinematic"), 1, "shift watches")
    mock.shift = false
    ns:SetModuleEnabled("SkipCinematics", false)
end)

-- chat --------------------------------------------------------------------------------

test("urls become clickable links and existing links are untouched", function()
    local out = ns.LinkifyURLs("see https://example.com/a?b=1, and www.foo.com. ok")
    assert(out:find("|Haddon:BIGARMS:url:https://example.com/a?b=1|h", 1, true), "https link: " .. out)
    assert(out:find("|Haddon:BIGARMS:url:www.foo.com|h", 1, true), "www link")
    assert(out:find("|h,", 1, true) and out:find("|h%. ok"), "punctuation kept outside")
    local itemLink = "|cffffffff|Hitem:1:0:0:0|h[Thing]|h|r http://x.io"
    local out2 = ns.LinkifyURLs(itemLink)
    assert(out2:find("|Hitem:1:0:0:0|h[Thing]|h", 1, true), "item link intact")
    assert(out2:find("|Haddon:BIGARMS:url:http://x.io|h", 1, true), "url after link")
    eq(ns.LinkifyURLs(out2), out2, "no double wrapping")
    eq(ns.LinkifyURLs("plain text 1.5 gold"), "plain text 1.5 gold", "no false positives")
end)

test("channel names are shortened language independently", function()
    local out = ns.ShortenChannels("|Hchannel:PARTY|h[파티]|h |Hplayer:A|h[A]|h: hi")
    assert(out:find("|h[P]|h", 1, true), "party shortened: " .. out)
    local out2 = ns.ShortenChannels("|Hchannel:channel:1|h[1. 공개]|h |Hplayer:A|h[A]|h: hi")
    assert(out2:find("|Hchannel:channel:1|h[1]|h", 1, true), "channel number only: " .. out2)
    local out3 = ns.ShortenChannels("|Hchannel:RAID|h[공격대장]|h x")
    assert(out3:find("[RL]", 1, true), "raid leader")
end)

test("chat frame AddMessage hook rewrites and records history", function()
    local chat = ns:GetModule("Chat")
    ChatFrame1:AddMessage("|Hchannel:PARTY|h[파티]|h A: http://a.b", 1, 1, 1, 1)
    local last = ChatFrame1.messages[#ChatFrame1.messages]
    assert(last.text:find("[P]", 1, true) and last.text:find("addon:BIGARMS:url", 1, true), "rewritten")
    local history = BIGARMSCharDB.chatHistory
    assert(#history >= 1 and history[#history][1] == last.text, "recorded")
    ChatFrame1:AddMessage("secret whisper", 1, 1, 1, 7)
    assert(history[#history][1] ~= "secret whisper", "whispers not recorded")
    eq(ns.CleanChatLine("|cff00ff00|Hitem:1|h[Thing]|h|r |TInterface\\x:0|t text"), "[Thing]  text", "cleaned")
end)

test("clicking an addon url link opens the copy box", function()
    SetItemRef("addon:BIGARMS:url:https://wow.example", "", "LeftButton")
    assert(BIGARMSURLBox and BIGARMSURLBox:IsShown(), "box shown")
    eq(BIGARMSURLBox.edit:GetText(), "https://wow.example", "url in box")
end)

test("keyword invite invites friends who whisper the keyword", function()
    ns:SetModuleEnabled("KeywordInvite", true)
    mock.reset()
    mock.fire("CHAT_MSG_WHISPER", "inv", "Friend", "", "", "Friend", "", 0, 0, "", 0, 1, "Player-1-FRIEND")
    eq(mock.count("InviteUnit"), 1, "invited")
    mock.fire("CHAT_MSG_WHISPER", "inv", "Stranger", "", "", "Stranger", "", 0, 0, "", 0, 1, "Player-1-STRANGER")
    eq(mock.count("InviteUnit"), 1, "strangers not invited by default")
    mock.fire("CHAT_MSG_WHISPER", "hello inv", "Friend", "", "", "Friend", "", 0, 0, "", 0, 1, "Player-1-FRIEND")
    eq(mock.count("InviteUnit"), 1, "whole message must be the keyword")
    mock.fire("CHAT_MSG_WHISPER", " 초대 ", "Friend", "", "", "Friend", "", 0, 0, "", 0, 1, "Player-1-FRIEND")
    eq(mock.count("InviteUnit"), 2, "korean keyword with spaces")
    ns:SetModuleEnabled("KeywordInvite", false)
    noErrors()
end)

-- tooltips ---------------------------------------------------------------------------------

test("item tooltips get level, price and count; secrets are skipped", function()
    local link = item(3001, 3, 1234, { equipLoc = "INVTYPE_CHEST", level = 45 })
    local post = mock.tooltipPostCalls[Enum.TooltipDataType.Item]
    assert(post, "item post call registered")
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    post(GameTooltip, { id = 3001, hyperlink = link })
    local joined = table.concat(GameTooltip.lines, "\n")
    assert(joined:find("45"), "item level: " .. joined)
    assert(joined:find("12|r"), "sell price")
    assert(joined:find("3"), "count")
    assert(GameTooltip.NineSlice.border, "quality border")
    GameTooltip:Hide()
    assert(not GameTooltip.NineSlice.border or GameTooltip.bigarmsColored == nil, "border reset on hide")

    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    post(GameTooltip, { id = mock.SECRET, hyperlink = mock.SECRET })
    eq(#GameTooltip.lines, 0, "nothing added for secret data")
    GameTooltip:Hide()
    noErrors()
end)

test("unit tooltips show target and guild rank", function()
    mock.units.mouseover = { name = "Bob", class = "MAGE", isPlayer = true, guid = "Player-1-BOB", guild = "Guild", guildRank = "Officer" }
    mock.units.mouseovertarget = { name = "빅암", class = "WARRIOR", isPlayer = true, guid = "Player-1-0000000A" }
    GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    GameTooltip.unitName, GameTooltip.unit = "Bob", "mouseover"
    GameTooltipTextLeft1:SetText("Bob")
    GameTooltipTextLeft2:SetText("Guild")
    local post = mock.tooltipPostCalls[Enum.TooltipDataType.Unit]
    post(GameTooltip, {})
    local joined = table.concat(GameTooltip.lines, "\n")
    assert(joined:find(ns.L.TT_YOU, 1, true), "target is you: " .. joined)
    assert(GameTooltipTextLeft2:GetText():find("Officer"), "guild rank")
    assert(GameTooltipTextLeft1:GetText():find("|cff"), "class colored name")
    GameTooltip.unit = nil
    GameTooltip:Hide()
    noErrors()
end)

test("tooltip anchor follows the setting", function()
    local tt = ns:GetModule("Tooltip")
    tt.db.anchor = "CURSOR"
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    eq(GameTooltip.anchor, "ANCHOR_CURSOR", "cursor anchor")
    tt.db.anchor = "DEFAULT"
    GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
    eq(GameTooltip.anchor, "ANCHOR_NONE", "default anchor")
end)

-- interface ------------------------------------------------------------------------------------

test("error filter hides spam and shows real errors", function()
    UIErrorsFrame.displayed = {}
    assert(not UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE"), "blizzard handler detached")
    mock.fire("UI_ERROR_MESSAGE", 1, ERR_OUT_OF_RANGE)
    mock.fire("UI_ERROR_MESSAGE", 1, ERR_OUT_OF_RAGE)
    mock.fire("UI_ERROR_MESSAGE", 1, "Inventory is full.")
    eq(#UIErrorsFrame.displayed, 1, "only the real one")
    eq(UIErrorsFrame.displayed[1], "Inventory is full.", "real error shown")
    ns:GetModule("Interface").db.errorFilter = false
    ns:GetModule("Interface"):SettingChanged("errorFilter", false)
    assert(UIErrorsFrame:IsEventRegistered("UI_ERROR_MESSAGE"), "handler given back")
    ns:GetModule("Interface").db.errorFilter = true
    ns:GetModule("Interface"):SettingChanged("errorFilter", true)
end)

test("camera and status text settings write cvars", function()
    local ui = ns:GetModule("Interface")
    ui.db.maxZoom = 2.6
    ui.db.statusText = "BOTH"
    ui.db.actionCam = "BASIC"
    ui:SettingChanged("maxZoom", 2.6)
    eq(mock.cvars.cameraDistanceMaxZoomFactor, "2.6", "zoom")
    eq(mock.cvars.statusTextDisplay, "BOTH", "status text")
    eq(mock.cvars.test_cameraDynamicPitch, "1", "action cam basic")
    eq(mock.cvars.test_cameraOverShoulder, "0", "no shoulder in basic")
    ui.db.actionCam = "KEEP"
    ui.db.statusText = "KEEP"
    eq(mock.cvars.outlineModeShowLootEffectWhenDisabled, "1", "quest sparkle on")
end)

test("unit frames are colored by class and reaction", function()
    mock.units.target = { name = "Mob", reaction = 2, isPlayer = false, guid = "Creature-1" }
    mock.fire("PLAYER_TARGET_CHANGED")
    mock.flushTimers()
    local c = TargetFrame.healthbar.barColor
    assert(c and c[1] > 0.8 and c[2] < 0.3, "hostile red")
    local p = PlayerFrame.healthbar.barColor
    assert(p and math.abs(p[1] - 0.78) < 0.01, "warrior tan")
    eq(PlayerFrame.healthbar.lockColor, true, "lock restored")
    mock.units.target = nil
    noErrors()
end)

test("durability warning fires below the threshold", function()
    mock.reset()
    mock.raidNotices = {}
    mock.durability[1] = { 10, 100 }
    mock.fire("UPDATE_INVENTORY_DURABILITY")
    assert(#mock.raidNotices == 1 and mock.raidNotices[1]:find("10"), "warned at 10%")
    mock.fire("UPDATE_INVENTORY_DURABILITY")
    eq(#mock.raidNotices, 1, "not repeated right away")
    mock.durability[1] = { 50, 100 }
    local lowest, average = ns.GetDurability()
    eq(lowest, 50, "lowest")
    assert(average > 50, "average")
    CharacterFrame:Show()
    assert(CharacterHeadSlot.bigarmsDurability and CharacterHeadSlot.bigarmsDurability:GetText() == "50%", "slot text")
    CharacterFrame:Hide()
    noErrors()
end)

test("reputation changes are printed with progress", function()
    mock.reset()
    mock.factions[1].currentStanding = 3350
    mock.fire("UPDATE_FACTION")
    local line = printed("Stormwind")
    assert(line and line:find("+250") and line:find("350/6000"), "rep line: " .. tostring(line))
    noErrors()
end)

test("movable frames remember their position", function()
    local movers = ns:GetModule("Movers")
    assert(CharacterFrame.bigarmsMovable, "prepared")
    mock.alt = true
    CharacterFrame.scripts.OnDragStart(CharacterFrame)
    CharacterFrame.scripts.OnDragStop(CharacterFrame)
    mock.alt = false
    assert(BIGARMSDB.positions.CharacterFrame, "saved")
    movers:ResetAll()
    assert(not BIGARMSDB.positions.CharacterFrame, "reset")
end)

-- items / quests ----------------------------------------------------------------------------------

test("gear item level helper", function()
    local link = item(4001, 2, 10, { equipLoc = "INVTYPE_HEAD", level = 30 })
    local level, quality = ns.GearItemLevel(link)
    eq(level, 30, "level")
    eq(quality, 2, "quality")
    local potion = item(4002, 1, 10, { equipLoc = "", level = 20 })
    eq(ns.GearItemLevel(potion), nil, "not gear")
    mock.equipped = { [1] = link }
    ns:GetModule("Items"):UpdateCharacter()
    eq(CharacterHeadSlot.bigarmsLevel:GetText(), 30, "character slot level")
end)

test("quest completion alert and auto track", function()
    mock.reset()
    mock.raidNotices = {}
    mock.fire("QUEST_ACCEPTED", 555)
    eq(mock.count("AddQuestWatch"), 1, "tracked")
    mock.quest.complete = { [555] = true }
    mock.fire("QUEST_WATCH_UPDATE", 555)
    mock.flushTimers()
    assert(mock.raidNotices[1] and mock.raidNotices[1]:find("Quest 555"), "alert")
    mock.fire("QUEST_WATCH_UPDATE", 555)
    mock.flushTimers()
    eq(#mock.raidNotices, 1, "once")
    noErrors()
end)

test("party announce sends objective progress only when on", function()
    mock.reset()
    mock.inGroup = true
    mock.fire("UI_INFO_MESSAGE", 1, "Boars slain: 3/5")
    eq(mock.count("SendChatMessage"), 0, "off by default")
    ns:GetModule("Quest").db.announce = true
    mock.fire("UI_INFO_MESSAGE", 1, "Boars slain: 3/5")
    eq(mock.count("SendChatMessage"), 1, "announced")
    eq(mock.calls.SendChatMessage[1][2], "PARTY", "to party")
    ns:GetModule("Quest").db.announce = false
    mock.inGroup = false
end)

-- combat / map / system -----------------------------------------------------------------------------

test("combat alert shows enter and leave text with timer", function()
    mock.fire("PLAYER_REGEN_DISABLED")
    assert(BIGARMSCombatAlert.text:GetText() == ns.L.CA_ENTER, "enter text")
    assert(BIGARMSCombatTimer:IsShown(), "timer shown")
    mock.time = mock.time + 65
    mock.fire("PLAYER_REGEN_ENABLED")
    assert(BIGARMSCombatAlert.text:GetText():find("1:05"), "duration shown: " .. BIGARMSCombatAlert.text:GetText())
    assert(not BIGARMSCombatTimer:IsShown(), "timer hidden")
end)

test("swing timer ignores secret durations", function()
    ns:SetModuleEnabled("SwingTimer", true)
    mock.fire("PLAYER_SWING", mock.SECRET, 0)
    mock.fire("PLAYER_SWING", 2.4, 0)
    mock.tick()
    local st = ns:GetModule("SwingTimer")
    assert(st.ticker, "ticking")
    ns:SetModuleEnabled("SwingTimer", false)
    noErrors()
end)

test("waypoint parsing", function()
    local mapID, x, y, note = ns.ParseWaypoint("45.2 67.8 Some herb")
    eq(mapID, nil, "no map")
    eq(x, 45.2, "x")
    eq(y, 67.8, "y")
    eq(note, "Some herb", "note")
    mapID, x, y = ns.ParseWaypoint("#1429 10, 20")
    eq(mapID, 1429, "map id")
    eq(x, 10, "x2")
    eq(y, 20, "y2")
    local _
    _, x, y = ns.ParseWaypoint("12,3 45,6")
    eq(x, 12.3, "decimal comma x")
    eq(y, 45.6, "decimal comma y")
    eq(ns.ParseWaypoint("hello"), nil, "garbage")
    eq(ns.ParseWaypoint("150 20"), nil, "out of range")
end)

test("/way sets, points and clears a waypoint", function()
    mock.reset()
    SlashCmdList["BIGARMS_WAY"]("60 50 Cave")
    local wp = BIGARMSCharDB.waypoint
    assert(wp and wp.mapID == 1429 and math.abs(wp.x - 0.6) < 1e-9, "stored")
    eq(mock.count("SetUserWaypoint"), 1, "game pin")
    mock.map.x, mock.map.y = 0.5, 0.5
    mock.facing = 0
    local relative, distance = ns.Waypoint:Bearing()
    -- target is 100 yd east (map x grows east); facing north -> arrow points right (clockwise)
    assert(math.abs(distance - 100) < 1, "distance " .. tostring(distance))
    assert(math.abs(math.abs(relative) - math.pi / 2) < 0.01, "right angle " .. tostring(relative))
    mock.tick()
    assert(BIGARMSWaypointArrow:IsShown(), "arrow shown")
    assert(BIGARMSWaypointArrow.distance:GetText():find("100"), "distance text")
    mock.map.x = 0.598
    mock.tick()
    assert(BIGARMSCharDB.waypoint == nil, "auto cleared on arrival")
    eq(mock.count("ClearUserWaypoint"), 1, "pin cleared")
    assert(not BIGARMSWaypointArrow:IsShown(), "arrow hidden")
    noErrors()
end)

test("system cvars only change when asked", function()
    local sys = ns:GetModule("System")
    eq(mock.cvars.autoLootDefault, "0", "untouched")
    sys.db.autoLoot = "ON"
    sys:SettingChanged("autoLoot", "ON")
    eq(mock.cvars.autoLootDefault, "1", "turned on")
    sys.db.spellQueue = 100
    sys:SettingChanged("spellQueue", 100)
    eq(mock.cvars.SpellQueueWindow, "100", "spell queue")
    sys.db.autoLoot = "KEEP"
end)

test("gold and xp reports", function()
    mock.reset()
    mock.money = 223456
    mock.fire("PLAYER_MONEY")
    ns.Gold:Report()
    assert(printed("22|r"), "gold listed")
    mock.xp = mock.SECRET
    mock.reset()
    mock.fire("PLAYER_XP_UPDATE")
    noErrors()
    mock.xp = 5000
    mock.fire("PLAYER_XP_UPDATE")
    ns.XP:Report()
    assert(printed("50%.0"), "xp percent")
    noErrors()
end)

-- slash / framework --------------------------------------------------------------------------------------

test("slash commands toggle modules and set options", function()
    mock.reset()
    ns:HandleSlash("off AutoRepair")
    assert(not ns:GetModule("AutoRepair").enabled, "off")
    assert(not BIGARMSDB.modules.AutoRepair.enabled, "saved")
    ns:HandleSlash("on autorepair")
    assert(ns:GetModule("AutoRepair").enabled, "on, case insensitive")
    ns:HandleSlash("set AutoAccept invites ALL")
    eq(ns:GetModule("AutoAccept").db.invites, "ALL", "set string")
    ns:HandleSlash("set AutoAccept invites FRIENDS")
    ns:HandleSlash("set Durability threshold 30")
    eq(ns:GetModule("Durability").db.threshold, 30, "set number")
    ns:HandleSlash("set Durability sound off")
    eq(ns:GetModule("Durability").db.sound, false, "set boolean")
    ns:HandleSlash("set Durability threshold abc")
    eq(ns:GetModule("Durability").db.threshold, 30, "bad value rejected")
    mock.reset()
    ns:HandleSlash("list")
    assert(printed("AutoRepair"), "list")
    mock.reset()
    ns:HandleSlash("nonsense")
    assert(printed(ns.L.HELP_HEADER), "help on unknown")
    ns:HandleSlash("")
    assert(mock.openedCategory, "options opened")
    ns:HandleSlash("minimap")
    assert(BIGARMSDB.minimap.hide, "minimap hidden")
    ns:HandleSlash("minimap")
end)

test("a failing module handler is reported once and does not stop others", function()
    local module = ns:NewModule("Broken", { group = "SYSTEM", defaults = {} })
    module.db = {}
    module.enabled = true
    module:RegisterEvent("PLAYER_MONEY", function() error("boom") end)
    mock.reset()
    mock.fire("PLAYER_MONEY")
    mock.fire("PLAYER_MONEY")
    local count = 0
    for _, line in ipairs(mock.printed) do
        if line:find("boom") then count = count + 1 end
    end
    eq(count, 1, "reported once")
    assert(BIGARMSDB.gold["빅암 - Forever"], "gold module still ran")
    module:Disable()
    table.remove(ns.modules)
    ns.modulesByName.Broken = nil
end)

test("disabling and re-enabling modules out of combat, deferred in combat", function()
    mock.inCombat = true
    ns:SetModuleEnabled("Reputation", false)
    assert(ns:GetModule("Reputation").enabled, "still enabled during combat")
    eq(BIGARMSDB.modules.Reputation.enabled, false, "but saved")
    mock.inCombat = false
    mock.fire("PLAYER_REGEN_ENABLED")
    assert(not ns:GetModule("Reputation").enabled, "disabled after combat")
    ns:SetModuleEnabled("Reputation", true)
    assert(ns:GetModule("Reputation").enabled, "enabled again")
end)

test("reset puts everything back to defaults", function()
    mock.reset()
    ns:GetModule("Durability").db.threshold = 55
    ns:ResetSettings()
    eq(ns:GetModule("Durability").db.threshold, 20, "default restored")
    assert(ns:GetModule("AutoRepair").enabled, "default modules on")
    noErrors()
end)

-- run -----------------------------------------------------------------------------------------------------

local failed = 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        io.write("  ok   " .. t.name .. "\n")
    else
        failed = failed + 1
        io.write("  FAIL " .. t.name .. "\n       " .. tostring(err) .. "\n")
    end
end
io.write(("\n%d passed, %d failed\n"):format(#tests - failed, failed))
return failed > 0
