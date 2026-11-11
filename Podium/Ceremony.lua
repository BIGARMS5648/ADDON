local ADDON, ns = ...
local L = ns.L

--------------------------------------------------------------------------
-- The ceremony window
--
--   header:  DUNGEON CLEAR / title / dungeon, time, bosses, deaths
--   stage:   the party's own characters on a podium, MVP in the middle on
--            the highest step, each playing an emote that fits their result
--            (MVP flexes, award winners cheer / roar / bow / salute, the
--            rest applaud, the joke-award winners cry or do the chicken)
--   bottom:  Play of the Game card
--
-- Characters are the players' real 3D models (DressUpModel:SetUnit). The
-- game only has a player's appearance while they're nearby, so Models.lua
-- keeps each group member's character from when they last were; anyone
-- never seen nearby (or a ceremony from the history after a /reload) gets
-- their class icon on the step instead.
--
-- Revealed in order like an end-of-match screen: title, play of the game,
-- the lineup from the outside in, then the MVP with light rays. Click to
-- skip, drag to move, Esc to close.
--------------------------------------------------------------------------

local Ceremony = {}
ns.Ceremony = Ceremony

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
local CLASS_ICONS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

local WIDTH, HEIGHT = 880, 680
local GOLD = { 1, 0.82, 0.25 }
local ORANGE = { 1, 0.55, 0.15 }
local STAGE_TOP, STAGE_BOTTOM = 92, 500 -- from the top of the window
local SLOT_GAP = 12
local MAX_SLOTS = 5
local POTG_W, POTG_H, POTG_TOP = 848, 104, 512

-- Podium steps by rank: width, height of the step (to the middle of its top
-- face, where the feet are), how tall the character stands (at 100% size),
-- metal color.
local STEPS = {
    { w = 200, step = 106, height = 340, color = { 1, 0.8, 0.36 } }, -- gold (the MVP stands out)
    { w = 150, step = 72, height = 232, color = { 0.84, 0.88, 0.96 } }, -- silver
    { w = 150, step = 62, height = 232, color = { 0.92, 0.6, 0.34 } }, -- bronze
    { w = 150, step = 52, height = 226, color = { 0.5, 0.53, 0.62 } }, -- steel
    { w = 150, step = 52, height = 226, color = { 0.5, 0.53, 0.62 } },
}
-- The game fits a character into its model frame with a little space
-- around it (about 90% of the height at camera distance 1). Moving the
-- camera back to CAMERA_DISTANCE leaves the character MODEL_FILL of the
-- frame's height, the rest split above and below: room above the head for
-- raised arms (a model is cut off at its frame's edge), and room below that
-- is sunk into the step so the feet land on its top. If that guess is off
-- in game, the "character height" option moves them.
local CAMERA_DISTANCE = 1.35
local MODEL_FILL = 0.67
-- Measured in game (characters looked right moved down 40 in 1.2.1, then
-- up 6 in 1.2.2): the empty space under the feet is about this share of the
-- frame's height, more than MODEL_FILL suggests. The frame is sunk into the
-- step by that much.
local FEET_MARGIN = 0.263
-- The top face of a step is seen from a little above: this deep, with the
-- feet in its middle.
local TOP_DEPTH = 16
-- Left to right: 4th, 2nd, MVP, 3rd, 5th.
local STAGE_ORDER = { 4, 2, 1, 3, 5 }

-- Emote animations (AnimationData IDs).
local ANIM = {
    STAND = 0, BOW = 66, WAVE = 67, CHEER = 68, DANCE = 69, ROAR = 74, CRY = 77, CHICKEN = 78,
    APPLAUD = 80, FLEX = 82, POINT = 84, SALUTE = 113,
}
-- What a player does on stage, by their headline title.
local EMOTES = {
    MVP = { ANIM.FLEX, ANIM.ROAR },
    POTG = { ANIM.CHEER, ANIM.DANCE },
    DAMAGE = { ANIM.ROAR, ANIM.CHEER },
    HEALING = { ANIM.BOW, ANIM.CHEER },
    TANK = { ANIM.SALUTE, ANIM.ROAR },
    INTERRUPTS = { ANIM.POINT, ANIM.CHEER },
    DISPELS = { ANIM.WAVE, ANIM.CHEER },
    SURVIVOR = { ANIM.SALUTE, ANIM.CHEER },
    FLOOR = { ANIM.CHICKEN },
    DEATHS = { ANIM.CRY },
    NONE = { ANIM.APPLAUD },
}
Ceremony.ANIM, Ceremony.EMOTES = ANIM, EMOTES
Ceremony.STEPS, Ceremony.MODEL_FILL, Ceremony.FEET_MARGIN = STEPS, MODEL_FILL, FEET_MARGIN

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
    lineup = { "UI_70_ARTIFACT_FORGE_TRAIT_RANKUP", 54129 },
}

local frame
local elements = {} -- animated parts: { frame =, kind =, start =, dur =, x =, y =, sound =, slot = }
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

-- A media texture drawn normally (not as light).
local function Img(parent, layer, sublevel, file)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetTexture(MEDIA .. file)
    return t
end

local function Solid(parent, layer, sublevel, r, g, b, a)
    local t = parent:CreateTexture(nil, layer, nil, sublevel)
    t:SetColorTexture(r, g, b, a)
    return t
end

local function Gradient(texture, r, g, b, bottomAlpha, topAlpha)
    if texture.SetGradient and CreateColor then
        texture:SetColorTexture(1, 1, 1, 1)
        pcall(texture.SetGradient, texture, "VERTICAL", CreateColor(r, g, b, bottomAlpha), CreateColor(r, g, b, topAlpha))
    else
        texture:SetColorTexture(r, g, b, (bottomAlpha + topAlpha) / 2)
    end
end

local function EaseOut(p)
    return 1 - (1 - p) ^ 3
end

local function EaseOutBack(p)
    local c1 = 1.70158
    local c3 = c1 + 1
    return 1 + c3 * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
end

local function HideTooltip()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

local function ShowStatTooltip(owner, p, titles)
    if not (GameTooltip and p) then
        return
    end
    local r, g, b = ClassColor(p.class)
    local Num = ns.FormatNumber
    local function Share(value, share)
        return L.STAT_SHARE:format(Num(value), math.floor(share * 100 + 0.5))
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(ns.Awards.ShortName(p.name), r, g, b)
    GameTooltip:AddLine(("%s  ·  %s"):format(RoleName(p.role), L.SCORE:format(p.score)), GOLD[1], GOLD[2], GOLD[3])
    GameTooltip:AddLine(L.SCORE_HINT, 0.6, 0.6, 0.6)
    for _, title in ipairs(titles or {}) do
        GameTooltip:AddDoubleLine(title.text, title.value or "", 1, 0.82, 0.25, 1, 1, 1)
    end
    GameTooltip:AddLine(" ")
    local lines = {
        { L.STAT_DAMAGE, Share(p.dmg, p.dmgShare) },
        { L.STAT_DPS, Num(p.dps) },
        { L.STAT_HEALING, Share(p.heal, p.healShare) },
        { L.STAT_HPS, Num(p.hps) },
        { L.STAT_TAKEN, Share(p.taken, p.takenShare) },
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

--------------------------------------------------------------------------
-- Characters
--------------------------------------------------------------------------

-- Where a slot's character stands, from the size and height settings.
local function Geometry(slot)
    local step = STEPS[slot.rank]
    local db = ns.db or {}
    local size = (db.modelSize or 100) / 100
    local height = step.height * size
    local frameHeight = height / MODEL_FILL
    -- how tall the character really looks (the same space above as below)
    local visible = frameHeight * (1 - 2 * FEET_MARGIN)
    -- the head must stay below the header
    local room = (STAGE_BOTTOM - STAGE_TOP) - step.step - (slot.rank == 1 and 6 or 40)
    if visible > room then
        local shrink = room / visible
        height, frameHeight, visible = height * shrink, frameHeight * shrink, room
    end
    return {
        feet = step.step, -- from the bottom of the slot
        height = height,
        visible = visible,
        frameHeight = frameHeight,
        frameWidth = max(step.w + 40, frameHeight * 0.75),
        bottom = step.step - frameHeight * FEET_MARGIN + (db.modelOffset or 0),
    }
end
Ceremony.Geometry = Geometry

local function PlaceRegions(slot)
    local g = Geometry(slot)
    slot.geometry = g
    slot.beam:SetSize(STEPS[slot.rank].w * 1.15, g.height * 1.25)
    slot.ring:ClearAllPoints()
    slot.ring:SetPoint("CENTER", slot, "BOTTOM", 0, g.feet + g.visible * 0.55)
    -- above the head, high enough for raised arms
    slot.extra:ClearAllPoints()
    if slot.rank == 1 then
        slot.extra:SetPoint("BOTTOM", slot, "BOTTOM", 0, g.feet + g.visible * 1.1)
    else
        slot.extra:SetPoint("BOTTOM", slot, "BOTTOM", 0, g.feet + g.height * 1.12)
    end
end

local function PlayEmote(slot)
    local model = slot.model
    slot.emoteIndex = slot.emoteIndex % #slot.emotes + 1
    local anim = slot.emotes[slot.emoteIndex]
    if model.HasAnimation then
        local ok, has = pcall(model.HasAnimation, model, anim)
        if ok and has == false then
            anim = ANIM.CHEER
        end
    end
    pcall(model.SetAnimation, model, anim)
    slot.animation = anim
    slot.playing = true
    -- Without an "animation finished" event, start over now and then.
    slot.nextEmote = not slot.hasFinishScript and clock + 5 or nil
end

-- Emote finished: stand for a moment, then the next one.
local function OnAnimFinished(model)
    local slot = model.slot
    if not (slot and slot.playing) then
        return
    end
    slot.playing = false
    pcall(model.SetAnimation, model, ANIM.STAND)
    slot.animation = ANIM.STAND
    slot.nextEmote = clock + 1.2 + (slot.position * 0.37) % 1.3
end

-- Emotes asked for before the model finished loading are lost.
local function OnModelLoaded(model)
    local slot = model.slot
    if slot and slot.playing then
        pcall(model.SetAnimation, model, slot.animation)
    end
end

-- Puts the player's character (loaded now or kept from earlier) on the step.
local function BorrowCharacter(slot, p)
    -- (made-up players of the preview are played by your own character)
    local entry = p.standIn and ns.Models:StandIn() or ns.Models:Get(p)
    if not entry then
        return false
    end
    local model = entry.model
    entry.inUse = true
    slot.entry, slot.model = entry, model
    model.slot = slot
    model:SetParent(slot)
    if model.SetFrameStrata then
        model:SetFrameStrata(slot:GetFrameStrata())
    end
    model:SetFrameLevel(slot:GetFrameLevel() + 2)
    local g = slot.geometry
    model:ClearAllPoints()
    model:SetSize(g.frameWidth, g.frameHeight)
    model:SetPoint("BOTTOM", slot, "BOTTOM", 0, g.bottom)
    slot.hasFinishScript = model.HasScript and model:HasScript("OnAnimFinished") or false
    if slot.hasFinishScript then
        model:SetScript("OnAnimFinished", OnAnimFinished)
    end
    if model.HasScript and model:HasScript("OnModelLoaded") then
        model:SetScript("OnModelLoaded", OnModelLoaded)
    end
    model:Show()
    pcall(model.SetPortraitZoom, model, 0)
    pcall(model.SetCamDistanceScale, model, CAMERA_DISTANCE)
    pcall(model.SetPosition, model, 0, 0, 0)
    pcall(model.SetFacing, model, 0)
    if model.SetSheathed then
        pcall(model.SetSheathed, model, true) -- empty hands look better while emoting
    end
    pcall(model.SetAnimation, model, ANIM.STAND)
    return true
end

local function ReleaseCharacters()
    for _, slot in ipairs(frame and frame.slots or {}) do
        if slot.entry then
            ns.Models:Release(slot.entry)
        end
        slot.entry, slot.model = nil, nil
        slot.playing, slot.nextEmote = false, nil
    end
end

--------------------------------------------------------------------------
-- Spotlights and confetti
--------------------------------------------------------------------------

local SPOT_SIZE = 640
local CONFETTI_COUNT = 44
local CONFETTI_COLORS = {
    { 1, 0.82, 0.25 }, { 1, 1, 1 }, { 1, 0.45, 0.2 }, { 0.45, 0.8, 1 }, { 1, 0.5, 0.78 }, { 0.55, 1, 0.5 },
}

-- Points a spotlight from its lamp (x, y from the window's top middle)
-- along angle (counterclockwise from straight down).
local function AimSpot(spot, angle)
    local s, c = math.sin(angle), math.cos(angle)
    spot:SetRotation(angle)
    spot:ClearAllPoints()
    -- the beam runs from the texture's top middle through its center
    spot:SetPoint("CENTER", frame, "TOP", spot.lampX + SPOT_SIZE / 2 * s, spot.lampY - SPOT_SIZE / 2 * c)
end

local function CreateConfetti(parent)
    local layer = CreateFrame("Frame", nil, parent)
    layer:SetAllPoints()
    layer:SetFrameLevel(parent:GetFrameLevel() + 40) -- in front of the characters
    layer.pieces = {}
    for i = 1, CONFETTI_COUNT do
        local tex = layer:CreateTexture(nil, "OVERLAY")
        tex:SetTexture(MEDIA .. "confetti")
        tex:Hide()
        layer.pieces[i] = { tex = tex, color = CONFETTI_COLORS[(i - 1) % #CONFETTI_COLORS + 1] }
    end
    return layer
end

local function StopConfetti()
    frame.confettiOn = false
    for _, piece in ipairs(frame.confetti.pieces) do
        piece.active = false
        piece.tex:Hide()
    end
end

local function StartConfetti()
    local seed = 11
    local function Random()
        seed = (seed * 1103515245 + 12345) % 2147483648
        return seed / 2147483648
    end
    for _, piece in ipairs(frame.confetti.pieces) do
        piece.x = (Random() - 0.5) * (WIDTH - 60)
        piece.y = -8 - Random() * 70 -- just under the top edge
        piece.delay = Random() * 1.8
        piece.speed = 65 + Random() * 70
        piece.sway = 8 + Random() * 22
        piece.swaySpeed = 1.5 + Random() * 2
        piece.phase = Random() * 6.28
        piece.spin = (Random() - 0.5) * 7
        piece.flip = 3 + Random() * 5
        piece.size = 9 + Random() * 6
        piece.age = 0
        piece.active = true
        piece.tex:SetSize(piece.size, piece.size)
    end
    frame.confettiOn = true
end

local function UpdateConfetti(elapsed)
    if not frame.confettiOn then
        return
    end
    local floorY = -(STAGE_BOTTOM - 10)
    local any = false
    for _, piece in ipairs(frame.confetti.pieces) do
        if piece.active then
            any = true
            piece.age = piece.age + elapsed
            local t = piece.age - piece.delay
            local y = piece.y - piece.speed * max(0, t)
            local tex = piece.tex
            if t < 0 then
                tex:Hide()
            elseif y < floorY then
                piece.active = false
                tex:Hide()
            else
                -- tumbling paper: turns, and catches the light as it flips
                local flip = math.abs(math.cos(t * piece.flip))
                local color, shade = piece.color, 0.55 + 0.45 * flip
                tex:SetVertexColor(color[1] * shade, color[2] * shade, color[3] * shade)
                tex:SetRotation(piece.phase + piece.spin * t)
                tex:ClearAllPoints()
                tex:SetPoint("CENTER", frame, "TOP", piece.x + piece.sway * sin(piece.phase + t * piece.swaySpeed), y)
                tex:SetAlpha(max(0, min(1, t / 0.3, (y - floorY) / 60)))
                tex:Show()
            end
        end
    end
    frame.confettiOn = any
end

--------------------------------------------------------------------------
-- Building the window
--------------------------------------------------------------------------

local function CreateHeader(parent)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(WIDTH, 92)
    header.glow = Tex(header, "BACKGROUND", 0, "glow")
    header.glow:SetSize(520, 150)
    header.glow:SetPoint("CENTER", 0, -6)
    header.glow:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])
    header.glow:SetAlpha(0.22)
    header.tag = Text(header, 11, { 0.85, 0.66, 0.3 })
    header.tag:SetPoint("TOP", 0, -14)
    header.title = Text(header, 30, GOLD, "OUTLINE")
    header.title:SetPoint("TOP", 0, -30)
    header.sub = Text(header, 13, { 0.82, 0.82, 0.82 })
    header.sub:SetPoint("TOP", 0, -70)
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

-- One place on the podium: badge, character (or class icon), step with name.
local function CreateSlot(parent, rank)
    local step = STEPS[rank]
    local mvp = rank == 1
    local slot = CreateFrame("Button", nil, parent)
    slot:SetSize(step.w, STAGE_BOTTOM - STAGE_TOP)
    slot.rank = rank
    slot:SetScript("OnEnter", function(self)
        ShowStatTooltip(self, self.player, self.titles)
    end)
    slot:SetScript("OnLeave", HideTooltip)
    slot:SetScript("OnClick", function()
        Ceremony:Skip()
    end)

    -- light cone from above and a pool of light at the feet
    slot.beam = Tex(slot, "BACKGROUND", 1, "glow")
    slot.beam:SetSize(step.w * 1.15, step.height * 1.25)
    slot.beam:SetPoint("BOTTOM", 0, step.step - 10)
    slot.beam:SetAlpha(mvp and 0.35 or 0.16)
    slot.pool = Tex(slot, "ARTWORK", -2, "glow")
    slot.pool:SetSize(step.w * 0.9, TOP_DEPTH * 1.6)
    slot.pool:SetPoint("CENTER", slot, "BOTTOM", 0, step.step)

    -- the step: a metal block, touching its neighbors like one podium
    local c = step.color
    local half = SLOT_GAP / 2
    slot.front = Img(slot, "BORDER", 0, "podium_front")
    slot.front:SetVertexColor(c[1], c[2], c[3])
    slot.front:SetPoint("BOTTOMLEFT", -half, 0)
    slot.front:SetPoint("BOTTOMRIGHT", half, 0)
    slot.front:SetHeight(step.step - TOP_DEPTH / 2)
    slot.top = Img(slot, "BORDER", 1, "podium_top")
    slot.top:SetVertexColor(min(1, c[1] * 1.12), min(1, c[2] * 1.12), min(1, c[3] * 1.12))
    slot.top:SetPoint("BOTTOMLEFT", slot.front, "TOPLEFT")
    slot.top:SetPoint("BOTTOMRIGHT", slot.front, "TOPRIGHT")
    slot.top:SetHeight(TOP_DEPTH)
    -- shade on the top face next to a taller neighbor (placed by FillStage)
    slot.ao = Solid(slot, "BORDER", 2, 0, 0, 0, 0.4)
    slot.ao:SetSize(26, TOP_DEPTH)
    -- contact shadow under the feet
    slot.shadow = Img(slot, "BORDER", 3, "shadow")
    slot.shadow:SetSize(step.w * 0.62, TOP_DEPTH * 0.9)
    slot.shadow:SetPoint("CENTER", slot, "BOTTOM", 0, step.step)
    slot.shadow:SetAlpha(0.75)
    -- dark seams where the blocks meet
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local seam = Solid(slot, "BORDER", 4, 0, 0, 0, 0.55)
        seam:SetWidth(1)
        seam:SetPoint("TOP" .. side, slot.top, "TOP" .. side, side == "LEFT" and 1 or -1, 0)
        seam:SetPoint("BOTTOM" .. side, slot.front, "BOTTOM" .. side)
    end

    -- stand-in when the character can't be shown (the character itself is
    -- borrowed from ns.Models when the ceremony opens)
    slot.ring = Tex(slot, "ARTWORK", 0, "ring", mvp and 104 or 84)
    slot.ring:SetPoint("CENTER", slot, "BOTTOM", 0, step.step + step.height * 0.45)
    slot.icon = slot:CreateTexture(nil, "ARTWORK", nil, 1)
    slot.icon:SetSize(mvp and 70 or 56, mvp and 70 or 56)
    slot.icon:SetPoint("CENTER", slot.ring, "CENTER")

    -- the front of the step: (MVP) name, score, centered on the engraved plaque
    local frontHeight = step.step - TOP_DEPTH / 2
    local top = -max(8, math.floor((frontHeight - 31) / 2))
    if mvp then
        slot.badge = Text(slot, 26, { 1, 0.95, 0.75 }, "OUTLINE")
        slot.badge:SetPoint("TOP", slot.front, "TOP", 0, -16)
        slot.laurelL = Tex(slot, "ARTWORK", 2, "star", 26)
        slot.laurelL:SetPoint("RIGHT", slot.badge, "LEFT", -4, 0)
        slot.laurelL:SetVertexColor(1, 0.95, 0.7)
        slot.laurelR = Tex(slot, "ARTWORK", 2, "star", 26)
        slot.laurelR:SetPoint("LEFT", slot.badge, "RIGHT", 4, 0)
        slot.laurelR:SetVertexColor(1, 0.95, 0.7)
        top = -48
    end
    slot.name = Text(slot, mvp and 16 or 13, GOLD, "OUTLINE")
    slot.name:SetPoint("TOP", slot.front, "TOP", 0, top)
    slot.name:SetWidth(step.w - 18)
    slot.name:SetWordWrap(false)
    slot.roleIcon = slot:CreateTexture(nil, "OVERLAY")
    slot.roleIcon:SetSize(mvp and 15 or 13, mvp and 15 or 13)
    slot.score = Text(slot, mvp and 12 or 10, { 1, 1, 1 })
    slot.score:SetPoint("TOP", slot.name, "BOTTOM", 7, mvp and -4 or -3)
    slot.roleIcon:SetPoint("RIGHT", slot.score, "LEFT", -3, 0)

    -- other titles, above the head (placed by PlaceRegions)
    slot.extra = Text(slot, mvp and 11 or 10, mvp and { 1, 0.86, 0.45 } or { 0.85, 0.75, 0.5 })
    slot.extra:SetWidth(mvp and step.w + 40 or step.w - 10)
    slot.extra:SetWordWrap(false)
    if mvp then
        slot.extra:SetPoint("BOTTOM", slot, "BOTTOM", 0, step.step + step.height)
    else
        slot.extra:SetPoint("BOTTOM", slot, "BOTTOM", 0, step.step + step.height * 1.12)
        slot.badge = Text(slot, 13, GOLD, "OUTLINE")
        slot.badge:SetPoint("BOTTOM", slot.extra, "TOP", 8, 1)
        slot.badge:SetWordWrap(false)
        slot.badgeIcon = slot:CreateTexture(nil, "OVERLAY")
        slot.badgeIcon:SetSize(16, 16)
        slot.badgeIcon:SetPoint("RIGHT", slot.badge, "LEFT", -4, 0)
    end
    return slot
end

local function CreatePotgCard(parent)
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(POTG_W, POTG_H)
    local bg = Solid(card, "BACKGROUND", -7, 0.06, 0.06, 0.09, 0.93)
    bg:SetAllPoints()
    local shine = Solid(card, "BACKGROUND", -6, 1, 1, 1, 1)
    shine:SetPoint("TOPLEFT")
    shine:SetPoint("TOPRIGHT")
    shine:SetHeight(50)
    Gradient(shine, ORANGE[1], ORANGE[2], ORANGE[3], 0, 0.14)
    local top = Solid(card, "BORDER", 0, ORANGE[1], ORANGE[2], ORANGE[3], 0.95)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(2)
    for _, e in ipairs({ { "BOTTOMLEFT", "BOTTOMRIGHT", "H" }, { "TOPLEFT", "BOTTOMLEFT", "W" }, { "TOPRIGHT", "BOTTOMRIGHT", "W" } }) do
        local line = Solid(card, "BORDER", 0, ORANGE[1], ORANGE[2], ORANGE[3], 0.35)
        line:SetPoint(e[1])
        line:SetPoint(e[2])
        if e[3] == "H" then
            line:SetHeight(1)
        else
            line:SetWidth(1)
        end
    end
    for _, x in ipairs({ 228, 640 }) do
        local divider = Solid(card, "BORDER", 0, ORANGE[1], ORANGE[2], ORANGE[3], 0.25)
        divider:SetPoint("TOPLEFT", x, -14)
        divider:SetPoint("BOTTOMLEFT", x, 14)
        divider:SetWidth(1)
    end
    card.flash = Tex(card, "BACKGROUND", -5, "glow")
    card.flash:SetSize(POTG_W * 1.1, POTG_H * 2.2)
    card.flash:SetPoint("CENTER")
    card.flash:SetVertexColor(ORANGE[1], ORANGE[2], ORANGE[3])
    card.flash:SetAlpha(0)

    -- left: label and who
    card.tag = Text(card, 9, { 1, 0.62, 0.3 }, nil, "LEFT")
    card.tag:SetPoint("TOPLEFT", 16, -12)
    card.label = Text(card, 18, { 1, 0.62, 0.22 }, "OUTLINE", "LEFT")
    card.label:SetPoint("TOPLEFT", 16, -26)
    card.icon = card:CreateTexture(nil, "ARTWORK")
    card.icon:SetSize(34, 34)
    card.icon:SetPoint("BOTTOMLEFT", 16, 14)
    card.name = Text(card, 15, GOLD, "OUTLINE", "LEFT")
    card.name:SetPoint("TOPLEFT", card.icon, "TOPRIGHT", 8, -1)
    card.name:SetWidth(160)
    card.name:SetWordWrap(false)
    card.role = Text(card, 10, { 0.7, 0.7, 0.7 }, nil, "LEFT")
    card.role:SetPoint("TOPLEFT", card.name, "BOTTOMLEFT", 0, -3)

    -- middle: the moment
    card.fight = Text(card, 12, GOLD, nil, "LEFT")
    card.fight:SetPoint("TOPLEFT", 244, -14)
    card.fight:SetWidth(380)
    card.fight:SetWordWrap(false)
    card.text = Text(card, 14, { 1, 1, 1 }, nil, "LEFT")
    card.text:SetPoint("TOPLEFT", card.fight, "BOTTOMLEFT", 0, -6)
    card.text:SetWidth(380)
    card.text:SetJustifyV("TOP")
    card.text:SetMaxLines(2)
    card.detail = Text(card, 11, { 0.75, 0.75, 0.75 }, nil, "LEFT")
    card.detail:SetPoint("BOTTOMLEFT", 244, 13)
    card.detail:SetWidth(380)
    card.detail:SetWordWrap(false)

    -- right: key ability
    card.spellLabel = Text(card, 10, { 0.7, 0.7, 0.7 }, nil, "LEFT")
    card.spellLabel:SetPoint("TOPLEFT", 656, -16)
    card.spellIcon = card:CreateTexture(nil, "ARTWORK")
    card.spellIcon:SetSize(36, 36)
    card.spellIcon:SetPoint("TOPLEFT", 656, -38)
    card.spell = Text(card, 12, { 0.95, 0.95, 0.95 }, nil, "LEFT")
    card.spell:SetPoint("TOPLEFT", card.spellIcon, "TOPRIGHT", 8, -2)
    card.spell:SetWidth(POTG_W - 656 - 36 - 8 - 14)
    card.spell:SetMaxLines(2)
    card.spellShare = Text(card, 11, { 1, 0.62, 0.3 }, nil, "LEFT")
    card.spellShare:SetPoint("BOTTOMLEFT", card.spellIcon, "BOTTOMRIGHT", 8, 1)

    card.empty = Text(card, 12, { 0.6, 0.6, 0.6 })
    card.empty:SetPoint("CENTER", 110, 0)
    return card
end

function Ceremony:Create()
    if frame then
        return frame
    end
    frame = CreateFrame("Frame", "PodiumCeremonyFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 20)
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
    frame:SetScript("OnHide", function()
        HideTooltip()
        ReleaseCharacters() -- (also runs once while being created)
    end)
    frame:Hide()
    -- Esc closes it.
    if UISpecialFrames then
        table.insert(UISpecialFrames, "PodiumCeremonyFrame")
    end

    -- Darkens the rest of the screen (doesn't catch the mouse).
    frame.dim = Solid(frame, "BACKGROUND", -8, 0, 0, 0, 0.55)
    frame.dim:SetPoint("TOPLEFT", UIParent, "TOPLEFT")
    frame.dim:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT")

    local bg = Solid(frame, "BACKGROUND", -7, 0.025, 0.025, 0.04, 0.96)
    bg:SetAllPoints()
    local top = Solid(frame, "BACKGROUND", -6, 1, 1, 1, 1)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(220)
    Gradient(top, 0.35, 0.24, 0.05, 0, 0.4)
    -- stage floor
    local floor = Solid(frame, "BACKGROUND", -5, 1, 1, 1, 1)
    floor:SetPoint("TOPLEFT", 2, -(STAGE_BOTTOM - 70))
    floor:SetPoint("TOPRIGHT", -2, -(STAGE_BOTTOM - 70))
    floor:SetHeight(70)
    Gradient(floor, 0.4, 0.3, 0.12, 0.28, 0)
    local edge = Solid(frame, "BORDER", 0, GOLD[1], GOLD[2], GOLD[3], 0.35)
    edge:SetPoint("TOPLEFT", 16, -STAGE_BOTTOM)
    edge:SetPoint("TOPRIGHT", -16, -STAGE_BOTTOM)
    edge:SetHeight(1)
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

    -- Light rays behind the MVP (drawn under the characters).
    frame.rays = Tex(frame, "ARTWORK", 0, "rays", 480)
    frame.rays:SetPoint("CENTER", frame, "TOP", 0, -(STAGE_BOTTOM - STEPS[1].step - STEPS[1].height / 2))
    frame.rays:SetVertexColor(GOLD[1], GOLD[2], GOLD[3])

    -- Two stage lights from the sides, aimed at the MVP.
    frame.spots = {}
    for i, side in ipairs({ -1, 1 }) do
        local spot = Tex(frame, "ARTWORK", 1, "beam", SPOT_SIZE)
        spot:SetVertexColor(1, 0.92, 0.7)
        spot:SetAlpha(0)
        spot.lampX, spot.lampY = side * (WIDTH / 2 - 40), -(STAGE_TOP + 10) -- side lights, below the header
        frame.spots[i] = spot
    end

    frame.header = CreateHeader(frame)
    frame.potg = CreatePotgCard(frame)
    frame.slots = {}
    for rank = 1, MAX_SLOTS do
        frame.slots[rank] = CreateSlot(frame, rank)
    end

    frame.confetti = CreateConfetti(frame)

    frame.more = Text(frame, 11, { 0.6, 0.6, 0.6 }, nil, "RIGHT")
    frame.more:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", -18, -(STAGE_BOTTOM - 4))

    frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    frame.close:SetPoint("TOPRIGHT", -4, -4)
    frame.close:SetScript("OnClick", function()
        Ceremony:Hide()
    end)

    frame.closeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.closeButton:SetSize(100, 24)
    frame.closeButton:SetPoint("BOTTOMRIGHT", -16, 14)
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
    frame.hint:SetPoint("BOTTOMLEFT", 18, 20)
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
    for _, region in ipairs({ card.icon, card.name, card.role, card.fight, card.text, card.detail,
        card.spellLabel, card.spellIcon, card.spell, card.spellShare }) do
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
        card.spellLabel:SetText(L.KEY_ABILITY)
        card.spellIcon:SetTexture(icon or QUESTION_MARK)
        card.spell:SetText(name)
        local share = potg.spellTotal and potg.spellTotal > 0 and potg.spellAmount and potg.spellAmount / potg.spellTotal
        card.spellShare:SetText(share and L.KEY_ABILITY_SHARE:format(Percent(share)) or "")
    else
        card.spellLabel:Hide()
        card.spellIcon:Hide()
        card.spell:Hide()
        card.spellShare:Hide()
    end
end

-- Titles won by each player: MVP, play of the game, then category awards.
local function Titles(report)
    local titles = {}
    local function Add(p, title)
        titles[p] = titles[p] or {}
        table.insert(titles[p], title)
    end
    if report.mvp then
        Add(report.mvp, { id = "MVP", text = L.MVP, value = L.SCORE:format(report.mvp.score) })
    end
    if report.potg then
        Add(report.potg.player, { id = "POTG", text = L.POTG, value = report.potg.fightName })
    end
    for _, award in ipairs(report.awards) do
        Add(award.player, { id = award.id, text = award.title, value = award.value, icon = award.icon })
    end
    return titles
end
Ceremony.Titles = Titles

-- The emotes for a player: from their headline title, but the joke awards
-- win over an ordinary category award.
local function EmotesFor(titles)
    local headline = titles and titles[1]
    if not headline then
        return EMOTES.NONE
    end
    if headline.id ~= "MVP" and headline.id ~= "POTG" then
        for _, title in ipairs(titles) do
            if title.id == "DEATHS" or title.id == "FLOOR" then
                return EMOTES[title.id]
            end
        end
    end
    return EMOTES[headline.id] or EMOTES.NONE
end
Ceremony.EmotesFor = EmotesFor

local function FillSlot(slot, p, titles)
    slot.player, slot.titles = p, titles
    local r, g, b = ClassColor(p.class)
    slot.name:SetText(ns.Awards.ShortName(p.name))
    slot.name:SetTextColor(r, g, b)
    slot.score:SetText(L.SCORE:format(p.score))
    SetRoleIcon(slot.roleIcon, p.role)
    slot.beam:SetVertexColor(slot.rank == 1 and GOLD[1] or r, slot.rank == 1 and GOLD[2] or g, slot.rank == 1 and GOLD[3] or b)
    slot.pool:SetVertexColor(r, g, b)

    -- headline above the head, the rest in small print
    local headline = titles and titles[1]
    local rest = {}
    for i = 2, titles and #titles or 0 do
        rest[#rest + 1] = titles[i].text
    end
    if slot.rank == 1 then
        slot.badge:SetText(L.MVP)
        slot.extra:SetText(table.concat(rest, "  ·  "))
    else
        slot.badge:SetText(headline and headline.text or "")
        if headline and headline.id == "POTG" then
            slot.badge:SetTextColor(1, 0.62, 0.22)
        else
            slot.badge:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
        end
        local icon = headline and headline.icon
        slot.badgeIcon:SetShown(icon ~= nil)
        if icon then
            slot.badgeIcon:SetTexture(icon)
        end
        -- keep icon + text centered together
        slot.badge:ClearAllPoints()
        slot.badge:SetPoint("BOTTOM", slot.extra, "TOP", icon and 10 or 0, 1)
        slot.extra:SetText(table.concat(rest, "  ·  "))
    end

    -- the character
    slot.emotes, slot.emoteIndex = EmotesFor(titles), 0
    slot.playing, slot.nextEmote, slot.animation = false, nil, nil
    PlaceRegions(slot)
    local hasModel = BorrowCharacter(slot, p)
    slot.icon:SetShown(not hasModel)
    slot.ring:SetShown(not hasModel)
    if not hasModel then
        SetClassIcon(slot.icon, p.class)
        slot.ring:SetVertexColor(r, g, b)
    end
end

-- Places the top players on the podium. Returns the slots in reveal order.
local function FillStage(report)
    local titles = Titles(report)
    local used = {}
    for rank = 1, MAX_SLOTS do
        local p = report.players[rank]
        local slot = frame.slots[rank]
        if p then
            FillSlot(slot, p, titles[p])
            used[#used + 1] = slot
            slot:Show()
        else
            slot.player = nil
            slot:Hide()
        end
    end
    -- left to right: 4th, 2nd, MVP, 3rd, 5th (only the ones present)
    local row, width = {}, 0
    for _, rank in ipairs(STAGE_ORDER) do
        if report.players[rank] then
            row[#row + 1] = frame.slots[rank]
            width = width + STEPS[rank].w
        end
    end
    width = width + (#row - 1) * SLOT_GAP
    local x = -width / 2
    local mvpX = 0
    for position, slot in ipairs(row) do
        local w = STEPS[slot.rank].w
        slot.baseX = x + w / 2
        slot.position = position
        if slot.rank == 1 then
            mvpX = slot.baseX
        end
        x = x + w + SLOT_GAP
    end
    -- shade on a step's top face where a taller step rises next to it
    for i, slot in ipairs(row) do
        slot.ao:Hide()
        for _, j in ipairs({ i - 1, i + 1 }) do
            local other = row[j]
            if other and STEPS[other.rank].step > STEPS[slot.rank].step then
                local right = j > i
                slot.ao:ClearAllPoints()
                slot.ao:SetPoint(right and "TOPRIGHT" or "TOPLEFT", slot.top, right and "TOPRIGHT" or "TOPLEFT")
                slot.ao:SetColorTexture(1, 1, 1, 1)
                if slot.ao.SetGradient and CreateColor then
                    local dark, clear = CreateColor(0, 0, 0, 0.45), CreateColor(0, 0, 0, 0)
                    pcall(slot.ao.SetGradient, slot.ao, "HORIZONTAL", right and clear or dark, right and dark or clear)
                else
                    slot.ao:SetColorTexture(0, 0, 0, 0.25)
                end
                slot.ao:Show()
            end
        end
    end
    -- turn slightly toward the middle
    for _, slot in ipairs(used) do
        slot.facing = slot.baseX < mvpX and 0.35 or (slot.baseX > mvpX and -0.35 or 0)
        if slot.model then
            pcall(slot.model.SetFacing, slot.model, slot.facing)
        end
    end
    frame.rays:ClearAllPoints()
    frame.rays:SetPoint("CENTER", frame, "TOP", mvpX, -(STAGE_BOTTOM - STEPS[1].step - frame.slots[1].geometry.visible / 2))
    -- stage lights aimed at the MVP's chest
    local mvpSlot = frame.slots[1]
    local targetY = -(STAGE_BOTTOM - STEPS[1].step - mvpSlot.geometry.visible * 0.55)
    for _, spot in ipairs(frame.spots) do
        spot.aim = math.atan2(mvpX - spot.lampX, -(targetY - spot.lampY))
        AimSpot(spot, spot.aim)
    end
    local hidden = #report.players - #used
    frame.more:SetText(hidden > 0 and L.MORE_PLAYERS:format(hidden) or "")
    -- reveal from the outside in, MVP last
    table.sort(used, function(a, b)
        return a.rank > b.rank
    end)
    return used
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

local function SetSlotAlpha(slot, alpha)
    slot:SetAlpha(alpha)
    if slot.model and slot.model.SetModelAlpha then
        pcall(slot.model.SetModelAlpha, slot.model, alpha)
    end
end

local function Apply(element, p)
    local x, y = element.x, element.y
    local alpha
    if element.kind == "pop" then
        local from = element.from or 1.4
        Place(element, x, y, max(0.5, from - (from - 1) * EaseOutBack(p)))
        alpha = min(1, p * 1.6)
    elseif element.kind == "rise" then
        Place(element, x, y - 40 * (1 - EaseOut(p)), 1)
        alpha = p
    end
    if element.slot then
        SetSlotAlpha(element.frame, alpha)
    else
        element.frame:SetAlpha(alpha)
    end
    if p >= 1 and element.slot and element.frame.model and not element.frame.playing
        and not element.frame.nextEmote then
        PlayEmote(element.frame)
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

local function BuildTimeline(slots)
    wipe(elements)
    frame.mvpStart = nil
    local cy = HEIGHT / 2
    local stageY = cy - (STAGE_TOP + STAGE_BOTTOM) / 2
    AddElement(frame.header, "pop", 0, 0.45, 0, cy - 46, "title", { from = 1.25 })
    AddElement(frame.potg, "rise", 0.6, 0.45, 0, cy - POTG_TOP - POTG_H / 2, "potg")
    local start = 1.3
    for _, slot in ipairs(slots) do
        local mvp = slot.rank == 1
        if mvp then
            start = start + 0.2
        end
        AddElement(slot, "pop", start, mvp and 0.55 or 0.35, slot.baseX, stageY,
            mvp and "mvp" or (start == 1.3 and "lineup" or nil), { from = mvp and 1.5 or 1.3, slot = true })
        frame.mvpStart = mvp and start or frame.mvpStart
        start = start + (mvp and 0.55 or 0.25)
    end
    finishTime = start + 0.2
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
    -- Emotes: the next one after a short pause.
    for _, slot in ipairs(frame.slots) do
        if slot.player and slot.model and slot.nextEmote and clock >= slot.nextEmote then
            PlayEmote(slot)
        end
    end
    -- Ongoing effects.
    local mvpStart = frame.mvpStart or 0
    local mvpIn = min(1, max(0, (clock - mvpStart) / 0.7))
    frame.rays:SetRotation(clock * 0.22)
    frame.rays:SetAlpha(mvpIn * (0.4 + 0.08 * sin(clock * 1.7)))
    local twinkle = 0.6 + 0.4 * sin(clock * 3)
    frame.header.starL:SetAlpha(twinkle)
    frame.header.starR:SetAlpha(1.2 - twinkle)
    frame.header.starL:SetRotation(clock * 0.8)
    frame.header.starR:SetRotation(-clock * 0.8)
    local mvp = frame.slots[1]
    mvp.laurelL:SetAlpha(twinkle)
    mvp.laurelR:SetAlpha(1.2 - twinkle)
    mvp.beam:SetAlpha(0.28 + 0.1 * sin(clock * 2.4))
    for _, slot in ipairs(frame.slots) do
        slot.pool:SetAlpha(0.45 + 0.15 * sin(clock * 2 + slot.rank))
    end
    local flash = clock - 0.6
    frame.potg.flash:SetAlpha(flash > 0 and max(0, 0.6 * (1 - flash / 1.2)) or 0)
    -- stage lights come on with the MVP and sweep a little
    for i, spot in ipairs(frame.spots) do
        if spot.aim then
            AimSpot(spot, spot.aim + 0.06 * sin(clock * 0.7 + i * 2.1))
            spot:SetAlpha(mvpIn * (0.42 + 0.06 * sin(clock * 1.3 + i)))
        end
    end
    if not frame.confettiStarted and frame.mvpStart and clock >= frame.mvpStart then
        frame.confettiStarted = true
        if not (ns.db and ns.db.confetti == false) then
            StartConfetti()
        end
    end
    UpdateConfetti(elapsed)

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
    frame.hint:SetText(L.HINT)

    local db = ns.db or {}
    frame:SetScale((db.scale or 100) / 100)
    frame.dim:SetShown(db.dim ~= false)
    closeIn = (db.autoClose or 0) > 0 and db.autoClose or nil

    ReleaseCharacters() -- a ceremony that was still open
    frame:Show() -- models load only while shown
    local slots = FillStage(report)
    BuildTimeline(slots)
    StopConfetti()
    frame.confettiStarted = false
    clock = 0
    for _, element in ipairs(elements) do
        Apply(element, 0)
    end
    frame.rays:SetAlpha(0)
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
