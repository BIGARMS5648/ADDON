local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- The ceremony window
--
--   header:  DUNGEON CLEAR / title / dungeon, time, bosses, deaths
--   row 1:   [Play of the Game]   [   MVP   ]   [impact scoreboard]
--   row 2:   award cards (top damage, top healer, iron wall, ...)
--
-- Revealed in order like an end-of-match screen: title, play of the game,
-- MVP (with light rays), scoreboard, then the awards one by one. Click to
-- skip, drag to move, Esc to close.
--------------------------------------------------------------------------

local Ceremony = {}
ns.Ceremony = Ceremony

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local WIDTH, HEIGHT = 800, 540
local GOLD = { 1, 0.82, 0.25 }
local ORANGE = { 1, 0.55, 0.15 }
local SIDE_CARD_W, SIDE_CARD_H = 230, 236
local MVP_W, MVP_H = 270, 268
local SIDE_MARGIN = 20
local AWARD_H = 100
local MAX_ROWS = 8

local ROLE_ATLAS = {
    TANK = "UI-LFG-RoleIcon-Tank",
    HEALER = "UI-LFG-RoleIcon-Healer",
    DAMAGER = "UI-LFG-RoleIcon-DPS",
}

-- Sound kits (numbers in case SOUNDKIT doesn't have the name).
local SOUNDS = {
    title = { "LFG_REWARDS", 17316 },
    potg = { "UI_EPICLOOT_TOAST", 31578 },
    mvp = { "UI_LEGENDARY_LOOT_TOAST", 63971 },
    award = { "UI_70_ARTIFACT_FORGE_TRAIT_RANKUP", 54129 },
}

local frame
local elements = {} -- animated parts: { frame =, kind =, start =, dur =, x =, y =, sound = }
local clock, finishTime, closeIn = 0, 0, nil
local currentReport

local min, max, sin = math.min, math.max, math.sin

--------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------

local function PlayCue(name)
    if not (ns.db and ns.db.sound) then
        return
    end
    local cue = SOUNDS[name]
    local kit = (SOUNDKIT and SOUNDKIT[cue[1]]) or cue[2]
    pcall(PlaySound, kit, "Master")
end

local function ClassColor(class)
    local color
    if class then
        if C_ClassColor and C_ClassColor.GetClassColor then
            color = C_ClassColor.GetClassColor(class)
        end
        color = color or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    end
    if color then
        return color.r, color.g, color.b
    end
    return 0.9, 0.9, 0.9
end
Ceremony.ClassColor = ClassColor

local function HasAtlas(name)
    if not (C_Texture and C_Texture.GetAtlasInfo) then
        return false
    end
    local ok, info = pcall(C_Texture.GetAtlasInfo, name)
    return ok and info ~= nil
end

local function SetClassIcon(texture, class)
    texture:SetTexCoord(0, 1, 0, 1)
    -- Same atlas the built-in damage meter uses for its bars.
    local atlas = class and (GetClassAtlas and GetClassAtlas(class) or ("classicon-" .. class))
    if atlas and not HasAtlas(atlas) then
        atlas = "classicon-" .. class:lower()
    end
    if atlas and HasAtlas(atlas) then
        texture:SetAtlas(atlas)
    elseif class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
        texture:SetTexture(CLASS_ICONS)
        texture:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
    else
        texture:SetTexture(QUESTION_MARK)
    end
end

local function SetRoleIcon(texture, role)
    local atlas = ROLE_ATLAS[role]
    if atlas and HasAtlas(atlas) then
        texture:SetAtlas(atlas)
        texture:Show()
    else
        texture:Hide()
    end
end

local function SpellInfo(spellID)
    if not spellID then
        return nil
    end
    local name, icon
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellID)
        icon = C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
    elseif GetSpellInfo then
        local _
        name, _, icon = GetSpellInfo(spellID)
    end
    return ns.Safe(name), ns.Safe(icon)
end

local function RoleName(role)
    return L["ROLE_" .. (role or "DAMAGER")]
end

-- "DUNGEON CLEAR" -> "D U N G E O N   C L E A R" (ASCII only)
local function Spaced(text)
    if text:find("[\128-\255]") then
        return text
    end
    return (text:gsub("(.)", "%1 "):gsub(" $", ""))
end

local function Text(parent, size, color, flags, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags or "")
    fs:SetTextColor(color[1], color[2], color[3])
    fs:SetJustifyH(justify or "CENTER")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.8)
    return fs
end

local function Tex(parent, layer, sublevel, file, size)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    if file then
        t:SetTexture(MEDIA .. file)
        t:SetBlendMode("ADD")
    end
    if size then
        t:SetSize(size, size)
    end
    return t
end

local function Solid(parent, layer, sublevel, r, g, b, a)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetColorTexture(r, g, b, a)
    return t
end

-- Dark card with a colored top edge and a thin border.
local function Card(parent, w, h, accent, alpha)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(w, h)
    local bg = Solid(card, "BACKGROUND", -7, 0.06, 0.06, 0.09, alpha or 0.93)
    bg:SetAllPoints()
    local shine = Solid(card, "BACKGROUND", -6, 1, 1, 1, 1)
    shine:SetPoint("TOPLEFT")
    shine:SetPoint("TOPRIGHT")
    shine:SetHeight(min(70, h * 0.45))
    if shine.SetGradient and CreateColor then
        pcall(shine.SetGradient, shine, "VERTICAL",
            CreateColor(accent[1], accent[2], accent[3], 0), CreateColor(accent[1], accent[2], accent[3], 0.16))
    else
        shine:SetColorTexture(accent[1], accent[2], accent[3], 0.08)
    end
    local top = Solid(card, "BORDER", 0, accent[1], accent[2], accent[3], 0.95)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(2)
    local edges = {
        { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 1 },
        { "TOPLEFT", "BOTTOMLEFT", 1, nil },
        { "TOPRIGHT", "BOTTOMRIGHT", 1, nil },
    }
    for _, e in ipairs(edges) do
        local line = Solid(card, "BORDER", 0, accent[1], accent[2], accent[3], 0.35)
        line:SetPoint(e[1])
        line:SetPoint(e[2])
        if e[3] then
            line:SetWidth(e[3])
        else
            line:SetHeight(e[4])
        end
    end
    return card
end

local function EaseOut(p)
    return 1 - (1 - p) ^ 3
end

local function EaseOutBack(p)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
end

--------------------------------------------------------------------------
-- Building the window
--------------------------------------------------------------------------

local function CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(WIDTH, 96)
    header.glow = Tex(header, "BACKGROUND", 0, "glow")
    header.glow:SetSize(520, 150)
    header.glow:SetPoint("CENTER", 0, -6)
    header.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    header.glow:SetAlpha(0.22)
    header.tag = Text(header, 11, { 0.85, 0.66, 0.3 })
    header.tag:SetPoint("TOP", 0, -16)
    header.title = Text(header, 30, GOLD, "OUTLINE")
    header.title:SetPoint("TOP", 0, -32)
    header.sub = Text(header, 13, { 0.82, 0.82, 0.82 })
    header.sub:SetPoint("TOP", 0, -72)
    header.sub:SetWidth(WIDTH - 60)
    header.sub:SetWordWrap(false)
    header.starL = Tex(header, "ARTWORK", 1, "star", 40)
    header.starL:SetPoint("RIGHT", header.title, "LEFT", -12, 0)
    header.starL:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    header.starR = Tex(header, "ARTWORK", 1, "star", 40)
    header.starR:SetPoint("LEFT", header.title, "RIGHT", 12, 0)
    header.starR:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    return header
end

local function CreatePotgCard(parent)
    local card = Card(parent, SIDE_CARD_W, SIDE_CARD_H, ORANGE)
    card.flash = Tex(card, "BACKGROUND", -5, "glow")
    card.flash:SetSize(320, 300)
    card.flash:SetPoint("CENTER")
    card.flash:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3])
    card.flash:SetAlpha(0)
    card.tag = Text(card, 9, { 1, 0.62, 0.3 })
    card.tag:SetPoint("TOP", 0, -12)
    card.label = Text(card, 18, { 1, 0.62, 0.22 }, "OUTLINE")
    card.label:SetPoint("TOP", 0, -26)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(44, 44)
    card.icon:SetPoint("TOPLEFT", 16, -60)
    card.name = Text(card, 16, GOLD, "OUTLINE", "LEFT")
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 10, -3)
    card.name:SetWidth(SIDE_CARD_W - 86)
    card.name:SetWordWrap(false)
    card.role = Text(card, 11, { 0.7, 0.7, 0.7 }, nil, "LEFT")
    card.role:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -4)
    card.fight = Text(card, 12, GOLD, nil, "LEFT")
    card.fight:SetPoint("TOPLEFT", 16, -116)
    card.fight:SetWidth(SIDE_CARD_W - 32)
    card.fight:SetWordWrap(false)
    card.text = Text(card, 13, { 1, 1, 1 }, nil, "LEFT")
    card.text:SetPoint("TOPLEFT", card.fight, "BOTTOMLEFT", 0, -6)
    card.text:SetWidth(SIDE_CARD_W - 32)
    card.text:SetJustifyV("TOP")
    card.text:SetMaxLines(3)
    card.detail = Text(card, 11, { 0.75, 0.75, 0.75 }, nil, "LEFT")
    card.detail:SetPoint("BOTTOMLEFT", 16, 44)
    card.detail:SetWidth(SIDE_CARD_W - 32)
    card.detail:SetWordWrap(false)
    card.spellIcon = card:CreateTexture(nil, "ARTWORK")
    card.spellIcon:SetSize(22, 22)
    card.spellIcon:SetPoint("BOTTOMLEFT", 16, 14)
    card.spell = Text(card, 12, { 0.9, 0.9, 0.9 }, nil, "LEFT")
    card.spell:SetPoint("LEFT", card.spellIcon, "RIGHT", 8, 0)
    card.spell:SetWidth(SIDE_CARD_W - 62)
    card.spell:SetWordWrap(false)
    card.empty = Text(card, 12, { 0.6, 0.6, 0.6 })
    card.empty:SetPoint("CENTER", 0, -10)
    return card
end

local function ShowStatTooltip(owner, p)
    if not (GameTooltip and p) then
        return
    end
    local r, g, b = ClassColor(p.class)
    local Num = ns.FormatNumber
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.Awards.ShortName(p.name), r, g, b)
    GameTooltip:AddLine(("%s  ·  %s"):format(RoleName(p.role), L.SCORE:format(p.score)), GOLD[1], GOLD[2], GOLD[3])
    local lines = {
        { L.STAT_DAMAGE, L.STAT_SHARE:format(Num(p.dmg), math.floor(p.dmgShare * 100 + 0.5)) },
        { L.STAT_DPS, Num(p.dps) },
        { L.STAT_HEALING, L.STAT_SHARE:format(Num(p.heal), math.floor(p.healShare * 100 + 0.5)) },
        { L.STAT_HPS, Num(p.hps) },
        { L.STAT_TAKEN, L.STAT_SHARE:format(Num(p.taken), math.floor(p.takenShare * 100 + 0.5)) },
        { L.STAT_AVOIDABLE, Num(p.avoid) },
        { L.STAT_INTERRUPTS, L.STAT_COUNT:format(p.ints) },
        { L.STAT_DISPELS, L.STAT_COUNT:format(p.disp) },
        { L.STAT_DEATHS, L.STAT_COUNT:format(p.deaths) },
    }
    for _, line in ipairs(lines) do
        GameTooltip:AddDoubleLine(line[1], line[2], 0.8, 0.8, 0.8, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(L.SCORE_BASE, ("%d"):format(p.base), 0.8, 0.8, 0.8, 1, 1, 1)
    GameTooltip:AddDoubleLine(L.SCORE_BONUS, ("+%d"):format(p.bonus), 0.8, 0.8, 0.8, 0.4, 1, 0.4)
    GameTooltip:AddDoubleLine(L.SCORE_PENALTY, ("-%d"):format(p.penalty), 0.8, 0.8, 0.8, 1, 0.45, 0.45)
    GameTooltip:Show()
end

local function HideTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function CreateMvpCard(parent)
    local card = Card(parent, MVP_W, MVP_H, GOLD, 0.78)
    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        ShowStatTooltip(self, self.player)
    end)
    card:SetScript("OnLeave", HideTooltip)
    card:SetScript("OnMouseUp", function()
        Ceremony:Skip()
    end)
    card.glow = Tex(card, "BACKGROUND", -5, "glow", 230)
    card.glow:SetPoint("CENTER", card, "TOP", 0, -98)
    card.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    card.label = Text(card, 40, GOLD, "OUTLINE")
    card.label:SetPoint("TOP", 0, -10)
    card.laurelL = Tex(card, "ARTWORK", 1, "star", 34)
    card.laurelL:SetPoint("RIGHT", card.label, "LEFT", -6, 0)
    card.laurelL:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    card.laurelR = Tex(card, "ARTWORK", 1, "star", 34)
    card.laurelR:SetPoint("LEFT", card.label, "RIGHT", 6, 0)
    card.laurelR:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    card.ring = Tex(card, "ARTWORK", 0, "ring", 96)
    card.ring:SetPoint("CENTER", card, "TOP", 0, -98)
    card.ring:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    card.icon = card:CreateTexture(nil, "ARTWORK", nil, 1)
    card.icon:SetSize(64, 64)
    card.icon:SetPoint("CENTER", card, "TOP", 0, -98)
    card.roleIcon = card:CreateTexture(nil, "OVERLAY")
    card.roleIcon:SetSize(24, 24)
    card.roleIcon:SetPoint("CENTER", card.icon, "BOTTOMRIGHT", -2, 2)
    card.name = Text(card, 22, GOLD, "OUTLINE")
    card.name:SetPoint("TOP", 0, -142)
    card.name:SetWidth(MVP_W - 20)
    card.name:SetWordWrap(false)
    card.score = Text(card, 16, GOLD)
    card.score:SetPoint("TOP", 0, -172)
    card.stat1 = Text(card, 12, { 1, 1, 1 })
    card.stat1:SetPoint("TOP", 0, -200)
    card.stat1:SetWidth(MVP_W - 20)
    card.stat1:SetWordWrap(false)
    card.stat2 = Text(card, 12, { 0.75, 0.75, 0.75 })
    card.stat2:SetPoint("TOP", 0, -220)
    card.stat2:SetWidth(MVP_W - 20)
    card.stat2:SetWordWrap(false)
    card.stat3 = Text(card, 11, { 0.6, 0.6, 0.6 })
    card.stat3:SetPoint("TOP", 0, -240)
    card.stat3:SetWidth(MVP_W - 20)
    card.stat3:SetWordWrap(false)
    return card
end

local function CreateScoreboard(parent)
    local card = Card(parent, SIDE_CARD_W, SIDE_CARD_H, { 0.45, 0.65, 1 })
    card.label = Text(card, 14, GOLD, nil, "LEFT")
    card.label:SetPoint("TOPLEFT", 14, -13)
    card.hint = Text(card, 10, { 0.6, 0.6, 0.6 }, nil, "RIGHT")
    card.hint:SetPoint("TOPRIGHT", -12, -16)
    card.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, card)
        row:SetSize(SIDE_CARD_W - 24, 22)
        row:SetPoint("TOPLEFT", 12, -38 - (i - 1) * 24)
        row.bar = Solid(row, "BACKGROUND", 0, 1, 1, 1, 0.2)
        row.bar:SetPoint("TOPLEFT")
        row.bar:SetPoint("BOTTOMLEFT")
        row.rank = Text(row, 12, { 0.7, 0.7, 0.7 }, nil, "RIGHT")
        row.rank:SetPoint("LEFT", 0, 0)
        row.rank:SetWidth(14)
        row.role = row:CreateTexture(nil, "ARTWORK")
        row.role:SetSize(15, 15)
        row.role:SetPoint("LEFT", 19, 0)
        row.name = Text(row, 12, GOLD, nil, "LEFT")
        row.name:SetPoint("LEFT", 38, 0)
        row.name:SetWidth(SIDE_CARD_W - 24 - 38 - 40)
        row.name:SetWordWrap(false)
        row.score = Text(row, 12, { 1, 1, 1 }, nil, "RIGHT")
        row.score:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnEnter", function(self)
            ShowStatTooltip(self, self.player)
        end)
        row:SetScript("OnLeave", HideTooltip)
        card.rows[i] = row
    end
    -- party totals, shown when the rows leave room for them
    card.totals = {}
    for i = 1, 3 do
        local line = Text(card, 11, { 0.72, 0.72, 0.72 }, nil, "LEFT")
        line:SetPoint("BOTTOMLEFT", 16, 12 + (3 - i) * 17)
        line:SetWidth(SIDE_CARD_W - 32)
        line:SetWordWrap(false)
        card.totals[i] = line
    end
    return card
end

local function CreateAwardCard(parent)
    local card = Card(parent, 112, AWARD_H, GOLD)
    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        ShowStatTooltip(self, self.player)
    end)
    card:SetScript("OnLeave", HideTooltip)
    card:SetScript("OnMouseUp", function()
        Ceremony:Skip()
    end)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(34, 34)
    card.icon:SetPoint("TOP", 0, -10)
    card.title = Text(card, 12, GOLD)
    card.title:SetPoint("TOP", 0, -50)
    card.name = Text(card, 13, GOLD, "OUTLINE")
    card.name:SetPoint("TOP", 0, -66)
    card.value = Text(card, 10, { 0.85, 0.85, 0.85 })
    card.value:SetPoint("TOP", 0, -84)
    for _, fs in ipairs({ card.title, card.name, card.value }) do
        fs:SetWordWrap(false)
    end
    return card
end

function Ceremony:Create()
    if frame then
        return frame
    end
    frame = CreateFrame("Frame", "PodiumCeremonyFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 30)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)
    frame:SetScript("OnMouseUp", function()
        Ceremony:Skip()
    end)
    frame:SetScript("OnUpdate", function(_, elapsed)
        Ceremony:OnUpdate(elapsed)
    end)
    frame:SetScript("OnHide", HideTooltip)
    frame:Hide()
    -- Esc closes it.
    if UISpecialFrames then
        table.insert(UISpecialFrames, "PodiumCeremonyFrame")
    end

    -- Darkens the rest of the screen (doesn't catch the mouse).
    frame.dim = Solid(frame, "BACKGROUND", -8, 0, 0, 0, 0.55)
    frame.dim:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
    frame.dim:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT")

    local bg = Solid(frame, "BACKGROUND", -7, 0.025, 0.025, 0.04, 0.95)
    bg:SetAllPoints()
    local top = Solid(frame, "BACKGROUND", -6, 1, 1, 1, 1)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(200)
    if top.SetGradient and CreateColor then
        pcall(top.SetGradient, top, "VERTICAL", CreateColor(0.3, 0.2, 0.04, 0), CreateColor(0.35, 0.24, 0.05, 0.4))
    else
        top:SetColorTexture(0.35, 0.24, 0.05, 0.15)
    end
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", "H" }, { "BOTTOMLEFT", "BOTTOMRIGHT", "H" },
        { "TOPLEFT", "BOTTOMLEFT", "W" }, { "TOPRIGHT", "BOTTOMRIGHT", "W" } }) do
        local line = Solid(frame, "BORDER", 0, GOLD[1], GOLD[2], GOLD[3], 0.75)
        line:SetPoint(e[1])
        line:SetPoint(e[2])
        if e[3] == "H" then
            line:SetHeight(2)
        else
            line:SetWidth(2)
        end
    end

    -- Light rays behind the MVP card (drawn under the cards).
    frame.rays = Tex(frame, "ARTWORK", 0, "rays", 440)
    frame.rays:SetPoint("CENTER", frame, "CENTER", 0, 270 - 100 - 98)
    frame.rays:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])

    frame.header = CreateHeader(frame)
    frame.potg = CreatePotgCard(frame)
    frame.mvp = CreateMvpCard(frame)
    frame.board = CreateScoreboard(frame)
    frame.awards = {}
    frame.awardCount = 0

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", -4, -4)
    frame.close:SetScript("OnClick", function()
        Ceremony:Hide()
    end)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.closeButton:SetSize(100, 24)
    frame.closeButton:SetPoint("BOTTOMRIGHT", -18, 14)
    frame.closeButton:SetText(L.CLOSE)
    frame.closeButton:SetScript("OnClick", function()
        Ceremony:Hide()
    end)

    frame.shareButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.shareButton:SetSize(120, 24)
    frame.shareButton:SetPoint("RIGHT", frame.closeButton, "LEFT", -8, 0)
    frame.shareButton:SetText(L.SHARE)
    frame.shareButton:SetScript("OnClick", function()
        Ceremony:Share()
    end)

    frame.hint = Text(frame, 11, { 0.55, 0.55, 0.55 }, nil, "LEFT")
    frame.hint:SetPoint("BOTTOMLEFT", 20, 20)
    return frame
end

--------------------------------------------------------------------------
-- Filling it in
--------------------------------------------------------------------------

local function Percent(share)
    return math.floor((share or 0) * 100 + 0.5)
end

local function FillPotg(card, potg)
    local shown = potg ~= nil
    for _, region in ipairs({ card.icon, card.name, card.role, card.fight, card.text, card.detail, card.spellIcon, card.spell }) do
        region:SetShown(shown)
    end
    card.tag:SetText(Spaced(L.POTG_TAG))
    card.label:SetText(L.POTG)
    card.empty:SetShown(not shown)
    card.empty:SetText(shown and "" or "-")
    if not shown then
        return
    end
    local p = potg.player
    SetClassIcon(card.icon, p.class)
    card.name:SetText(ns.Awards.ShortName(p.name))
    card.name:SetTextColor(ClassColor(p.class))
    card.role:SetText(RoleName(p.role))
    card.fight:SetText(potg.fightName)
    if potg.boss then
        card.fight:SetTextColor(ORANGE[1], ORANGE[2] + 0.15, ORANGE[3] + 0.15)
    else
        card.fight:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    end
    card.text:SetText(potg.text)
    card.detail:SetText(potg.detail or "")
    local name, icon = SpellInfo(potg.spellID)
    if name then
        card.spellIcon:SetTexture(icon or QUESTION_MARK)
        local share = potg.spellTotal and potg.spellTotal > 0 and potg.spellAmount and potg.spellAmount / potg.spellTotal
        card.spell:SetText(share and L.KEY_ABILITY:format(name, Percent(share)) or name)
    else
        card.spellIcon:Hide()
        card.spell:Hide()
    end
end

local function FillMvp(card, p)
    card.player = p
    card.label:SetText(L.MVP)
    SetClassIcon(card.icon, p.class)
    SetRoleIcon(card.roleIcon, p.role)
    card.name:SetText(ns.Awards.ShortName(p.name))
    card.name:SetTextColor(ClassColor(p.class))
    card.score:SetText(L.SCORE:format(p.score))
    local Num = ns.FormatNumber
    if p.role == "HEALER" then
        card.stat1:SetText(("%s %s (%d%%)  ·  %s %s"):format(L.STAT_HEALING, Num(p.heal), Percent(p.healShare), L.STAT_HPS, Num(p.hps)))
    elseif p.role == "TANK" then
        card.stat1:SetText(("%s %s (%d%%)  ·  %s %s"):format(L.STAT_TAKEN, Num(p.taken), Percent(p.takenShare), L.STAT_DPS, Num(p.dps)))
    else
        card.stat1:SetText(("%s %s (%d%%)  ·  %s %s"):format(L.STAT_DAMAGE, Num(p.dmg), Percent(p.dmgShare), L.STAT_DPS, Num(p.dps)))
    end
    card.stat2:SetText(("%s  ·  %s  ·  %s"):format(L.STAT_LINE_INTERRUPTS:format(p.ints),
        L.STAT_LINE_DISPELS:format(p.disp), L.STAT_LINE_DEATHS:format(p.deaths)))
    card.stat3:SetText(RoleName(p.role))
end

local function FillBoard(card, players, report)
    card.label:SetText(L.SCOREBOARD)
    card.hint:SetText(L.SCOREBOARD_HINT)
    local top = players[1] and max(1, players[1].score) or 1
    for i, row in ipairs(card.rows) do
        local p = players[i]
        row.player = p
        if p then
            local r, g, b = ClassColor(p.class)
            row.rank:SetText(tostring(i))
            row.rank:SetTextColor(i == 1 and GOLD[1] or 0.7, i == 1 and GOLD[2] or 0.7, i == 1 and GOLD[3] or 0.7)
            SetRoleIcon(row.role, p.role)
            row.name:SetText(ns.Awards.ShortName(p.name))
            row.name:SetTextColor(r, g, b)
            row.score:SetText(tostring(p.score))
            row.bar:SetColorTexture(r, g, b, p.isLocal and 0.32 or 0.2)
            row.bar:SetWidth(max(1, (SIDE_CARD_W - 24) * min(1, p.score / top)))
            row:Show()
        else
            row:Hide()
        end
    end
    local Num = ns.FormatNumber
    local totals, time = report.totals, report.combatTime or 0
    local perSecond = function(value)
        return Num(time > 0 and value / time or 0)
    end
    local lines = {
        L.BOARD_DAMAGE:format(Num(totals.dmg), perSecond(totals.dmg)),
        L.BOARD_HEALING:format(Num(totals.heal), perSecond(totals.heal)),
        L.BOARD_TIME:format(ns.FormatTime(time)),
    }
    for i, line in ipairs(card.totals) do
        line:SetText(lines[i])
        line:SetShown(#players <= 5)
    end
end

local function FillAwards(awards)
    local count = #awards
    local gap = 8
    local width = count > 0 and min(120, math.floor((WIDTH - 2 * SIDE_MARGIN - (count - 1) * gap) / count)) or 0
    local total = count * width + max(0, count - 1) * gap
    for i = 1, max(count, #frame.awards) do
        local card = frame.awards[i]
        local award = awards[i]
        if award and not card then
            card = CreateAwardCard(frame)
            frame.awards[i] = card
        end
        if card then
            if award then
                card:SetWidth(width)
                card.title:SetWidth(width - 8)
                card.name:SetWidth(width - 8)
                card.value:SetWidth(width - 8)
                card.player = award.player
                card.icon:SetTexture(award.icon or QUESTION_MARK)
                card.title:SetText(award.title)
                card.name:SetText(ns.Awards.ShortName(award.player.name))
                card.name:SetTextColor(ClassColor(award.player.class))
                card.value:SetText(award.value or "")
                card.baseX = -total / 2 + width / 2 + (i - 1) * (width + gap)
                card:Show()
            else
                card:Hide()
            end
        end
    end
    frame.awardCount = count
end

--------------------------------------------------------------------------
-- Animation
--------------------------------------------------------------------------

local function Place(element, x, y, scale)
    local f = element.frame
    f:SetScale(scale)
    f:ClearAllPoints()
    -- Offsets are in the child's scale, so divide to keep the center put.
    f:SetPoint("CENTER", frame, "CENTER", x / scale, y / scale)
end

local function Apply(element, p)
    local x, y = element.x, element.y
    if element.kind == "pop" then
        local from = element.from or 1.4
        Place(element, x, y, max(0.5, from - (from - 1) * EaseOutBack(p)))
        element.frame:SetAlpha(min(1, p * 1.6))
    elseif element.kind == "left" or element.kind == "right" then
        local dx = (element.kind == "left" and -60 or 60) * (1 - EaseOut(p))
        Place(element, x + dx, y, 1)
        element.frame:SetAlpha(p)
    end
end

local function AddElement(f, kind, start, dur, x, y, sound, extra)
    local element = { frame = f, kind = kind, start = start, dur = dur, x = x, y = y, sound = sound }
    for k, v in pairs(extra or {}) do
        element[k] = v
    end
    elements[#elements + 1] = element
    return element
end

local function BuildTimeline()
    wipe(elements)
    local cy = HEIGHT / 2
    AddElement(frame.header, "pop", 0, 0.45, 0, cy - 48, "title", { from = 1.25 })
    AddElement(frame.potg, "left", 0.7, 0.45, -(WIDTH / 2) + SIDE_MARGIN + SIDE_CARD_W / 2, cy - 108 - SIDE_CARD_H / 2, "potg")
    AddElement(frame.mvp, "pop", 1.7, 0.55, 0, cy - 100 - MVP_H / 2, "mvp", { from = 1.6 })
    AddElement(frame.board, "right", 2.6, 0.4, WIDTH / 2 - SIDE_MARGIN - SIDE_CARD_W / 2, cy - 108 - SIDE_CARD_H / 2)
    local start = 3.1
    for i = 1, frame.awardCount do
        local card = frame.awards[i]
        AddElement(card, "pop", start, 0.3, card.baseX, cy - 384 - AWARD_H / 2, i == 1 and "award" or nil, { from = 1.5 })
        start = start + 0.15
    end
    finishTime = start + 0.35
end

function Ceremony:OnUpdate(elapsed)
    clock = clock + elapsed
    for _, element in ipairs(elements) do
        if not element.done and clock >= element.start then
            if not element.played then
                element.played = true
                if element.sound then
                    PlayCue(element.sound)
                end
            end
            local p = min(1, (clock - element.start) / element.dur)
            Apply(element, p)
            element.done = p >= 1
        end
    end
    -- Ongoing effects.
    frame.rays:SetRotation(clock * 0.22)
    local mvpIn = min(1, max(0, (clock - 1.7) / 0.7))
    frame.rays:SetAlpha(mvpIn * (0.42 + 0.08 * sin(clock * 1.7)))
    frame.mvp.glow:SetAlpha(mvpIn * (0.55 + 0.25 * sin(clock * 2.4)))
    frame.mvp.ring:SetAlpha(mvpIn * (0.6 + 0.3 * sin(clock * 2.4 + 1)))
    local twinkle = 0.6 + 0.4 * sin(clock * 3)
    frame.header.starL:SetAlpha(twinkle)
    frame.header.starR:SetAlpha(1.2 - twinkle)
    frame.header.starL:SetRotation(clock * 0.8)
    frame.header.starR:SetRotation(-clock * 0.8)
    frame.mvp.laurelL:SetAlpha(mvpIn * twinkle)
    frame.mvp.laurelR:SetAlpha(mvpIn * (1.2 - twinkle))
    local flash = clock - 0.7
    frame.potg.flash:SetAlpha(flash > 0 and max(0, 0.7 * (1 - flash / 1.2)) or 0)

    if clock >= finishTime and closeIn then
        if not frame:IsMouseOver() then
            closeIn = closeIn - elapsed
        end
        if closeIn <= 0 then
            self:Hide()
            return
        end
        frame.hint:SetText(L.HINT .. "  ·  " .. L.AUTO_CLOSE:format(math.ceil(closeIn)))
    end
end

-- Jumps to the end of the reveal.
function Ceremony:Skip()
    if not frame or clock >= finishTime then
        return
    end
    for _, element in ipairs(elements) do
        element.played = true -- no sounds for skipped parts
    end
    clock = finishTime
    self:OnUpdate(0)
end

--------------------------------------------------------------------------
-- Public
--------------------------------------------------------------------------

function Ceremony:Show(report)
    self:Create()
    currentReport = report
    local header = frame.header
    header.tag:SetText(Spaced(report.tag))
    header.title:SetText(report.title)
    header.sub:SetText(report.subtitle)
    FillPotg(frame.potg, report.potg)
    FillMvp(frame.mvp, report.mvp)
    FillBoard(frame.board, report.players, report)
    FillAwards(report.awards)
    frame.hint:SetText(L.HINT)

    local db = ns.db or {}
    frame:SetScale((db.scale or 100) / 100)
    frame.dim:SetShown(db.dim ~= false)
    closeIn = (db.autoClose or 0) > 0 and db.autoClose or nil

    BuildTimeline()
    clock = 0
    for _, element in ipairs(elements) do
        Apply(element, 0)
        element.frame:SetAlpha(0)
    end
    frame.rays:SetAlpha(0)
    frame:Show()
    self:OnUpdate(0)
end

function Ceremony:Hide()
    if frame and frame:IsShown() then
        frame:Hide()
    end
end

function Ceremony:IsShown()
    return frame ~= nil and frame:IsShown()
end

function Ceremony:GetReport()
    return currentReport
end

function Ceremony:Share(report)
    report = report or currentReport or ns.lastReport
    if not report then
        ns.Print(L.NO_RUN)
        return
    end
    local channel
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) then
        channel = "INSTANCE_CHAT"
    elseif IsInRaid() then
        channel = "RAID"
    elseif IsInGroup() then
        channel = "PARTY"
    end
    if not channel then
        for _, line in ipairs(report.shareLines) do
            ns.Print(line)
        end
        ns.Print(L.SHARE_SOLO)
        return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, line in ipairs(report.shareLines) do
        if not pcall(send, line, channel) then
            ns.Print(L.SHARE_FAILED)
            return
        end
    end
end

-- For tests and the layout preview.
function Ceremony:GetFrame()
    return frame
end

function Ceremony:Finish()
    self:Skip()
end
