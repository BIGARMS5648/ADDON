local ADDON, ns = ...
local Data = ns.Data

-- Animated "sparkle" drawn on top of a nameplate (or on the screen).
-- Everything is animated by hand in OnUpdate so it looks the same on every
-- client build; only a couple of these exist at any time, so it's cheap.

local MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

local NUM_SPARKS = 7
local RING_PERIOD = 2.4 -- seconds between pulses of the expanding ring
local RING_LIFE = 1.0
local INTRO = 0.3 -- pop-in time when a sparkle first appears

local sin, cos, random, max, pi = math.sin, math.cos, math.random, math.max, math.pi
local TWO_PI = pi * 2

local Sparkle = {}
ns.Sparkle = Sparkle

local FxMixin = {}

local function CreateTex(fx, file, sublevel)
    local tex = fx:CreateTexture(nil, "OVERLAY", nil, sublevel)
    tex:SetTexture(MEDIA .. file)
    tex:SetBlendMode("ADD")
    tex:SetPoint("CENTER")
    return tex
end

function FxMixin:ResetSpark(spark)
    local size = self.size
    local angle = random() * TWO_PI
    local dist = (0.18 + random() * 0.42) * size
    spark.life = 0.55 + random() * 0.6
    spark.age = -random() * 0.5
    spark.peak = (0.16 + random() * 0.14) * size
    spark.tex:ClearAllPoints()
    spark.tex:SetPoint("CENTER", self, "CENTER", cos(angle) * dist, sin(angle) * dist * 0.8)
    spark.tex:SetRotation(random() * 0.6 - 0.3)
    spark.tex:SetAlpha(0)
end

function FxMixin:Restart()
    self.t = 0
    for i = 1, NUM_SPARKS do
        self:ResetSpark(self.sparks[i])
    end
end

local function OnUpdate(self, elapsed)
    local t = self.t + elapsed
    self.t = t
    local size = self.size

    -- pop in with a small overshoot
    local pop = 1
    if t < INTRO then
        local k = t / INTRO
        pop = (1 - (1 - k) ^ 3) * (1 + 0.25 * sin(k * pi))
    end

    -- soft glow, breathing
    local p = 0.5 + 0.5 * sin(t * 3.2)
    local gs = max(1, size * (1.15 + 0.15 * p) * pop)
    self.glow:SetSize(gs, gs)
    self.glow:SetAlpha(0.30 + 0.35 * p)

    -- big rotating star with a white-hot core
    local sp = 0.5 + 0.5 * sin(t * 4.4 + 1)
    local ss = max(1, size * (0.75 + 0.2 * sp) * pop)
    local rot = t * 0.7
    self.star:SetSize(ss, ss)
    self.star:SetRotation(rot)
    self.star:SetAlpha(0.55 + 0.45 * sp)
    self.core:SetSize(ss, ss)
    self.core:SetRotation(rot)
    self.core:SetAlpha(0.25 * sp)

    -- expanding ring every few seconds, so it can be spotted from afar
    local rt = t % RING_PERIOD
    if rt < RING_LIFE then
        local k = rt / RING_LIFE
        local rs = max(1, size * (0.4 + 1.4 * k))
        self.ring:SetSize(rs, rs)
        self.ring:SetAlpha((1 - k) ^ 1.5 * 0.8)
    else
        self.ring:SetAlpha(0)
    end

    -- small twinkles popping in and out around the object
    for i = 1, NUM_SPARKS do
        local spark = self.sparks[i]
        local age = spark.age + elapsed
        spark.age = age
        if age >= spark.life then
            self:ResetSpark(spark)
        elseif age > 0 then
            local e = sin(age / spark.life * pi)
            local sz = max(1, spark.peak * e)
            spark.tex:SetSize(sz, sz)
            spark.tex:SetAlpha(e)
        end
    end
end

function FxMixin:SetCategory(category)
    local c = Data.COLORS[category] or Data.COLORS.OTHER
    local r, g, b = c[1], c[2], c[3]
    self.glow:SetVertexColor(r, g, b)
    self.star:SetVertexColor(r, g, b)
    self.ring:SetVertexColor(r, g, b)
    -- sparks a little whiter so they read as glints
    local lr, lg, lb = (r + 1) / 2, (g + 1) / 2, (b + 1) / 2
    for i = 1, NUM_SPARKS do
        self.sparks[i].tex:SetVertexColor(lr, lg, lb)
    end
    self.label:SetTextColor(r, g, b)
end

-- anchor: frame to sit on (a nameplate, or UIParent for screen alerts)
-- label: optional text shown under the sparkle
function FxMixin:Play(anchor, category, label, size, offsetX, offsetY)
    local restart = not self:IsShown() or self.anchor ~= anchor or self.category ~= category
    if self.anchor ~= anchor then
        self:SetParent(anchor)
        self.anchor = anchor
    end
    self:ClearAllPoints()
    self:SetPoint("CENTER", anchor, "CENTER", offsetX or 0, offsetY or 0)
    self:SetFrameLevel((anchor:GetFrameLevel() or 0) + 20)
    self:SetSize(size, size)
    if self.size ~= size then
        self.size = size
        restart = true
    end
    if self.category ~= category then
        self.category = category
        self:SetCategory(category)
    end
    if label and label ~= "" then
        self.label:SetText(label)
        self.label:Show()
    else
        self.label:Hide()
    end
    if restart then
        self:Restart()
    end
    self:Show()
end

function FxMixin:Stop()
    self:Hide()
    self:ClearAllPoints()
    self:SetParent(UIParent)
    self.anchor = nil
    self.category = nil
end

local function CreateFx()
    local fx = CreateFrame("Frame", nil, UIParent)
    for k, v in pairs(FxMixin) do
        fx[k] = v
    end
    fx:Hide()
    fx.size = 64
    fx.t = 0
    -- Keep the sparkle fully visible even when the nameplate fades
    -- (distance / occlusion): being visible through walls is the point.
    if fx.SetIgnoreParentAlpha then
        fx:SetIgnoreParentAlpha(true)
    end

    fx.ring = CreateTex(fx, "ring", 0)
    fx.glow = CreateTex(fx, "glow", 1)
    fx.star = CreateTex(fx, "star", 2)
    fx.core = CreateTex(fx, "star", 3)
    fx.core:SetVertexColor(1, 1, 1)
    fx.sparks = {}
    for i = 1, NUM_SPARKS do
        fx.sparks[i] = { tex = CreateTex(fx, "spark", 4) }
    end

    fx.label = fx:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
    fx.label:SetPoint("TOP", fx, "BOTTOM", 0, 2)
    fx.label:Hide()

    fx:SetScript("OnUpdate", OnUpdate)
    return fx
end

-- pool --------------------------------------------------------------------

local pool = {}

function Sparkle.Acquire()
    return table.remove(pool) or CreateFx()
end

function Sparkle.Release(fx)
    if not fx then
        return
    end
    fx:Stop()
    pool[#pool + 1] = fx
end

-- screen alert (used when the object has no nameplate) -------------------

local hud

function Sparkle.ShowHud(category, label, size, offsetY)
    hud = hud or CreateFx()
    hud:Play(UIParent, category, label, size, 0, offsetY)
end

function Sparkle.HideHud()
    if hud and hud:IsShown() then
        hud:Stop()
    end
end

function Sparkle.IsHudShown()
    return hud ~= nil and hud:IsShown()
end

-- preview -------------------------------------------------------------------

local tests = {}
local testToken = 0

function Sparkle.ShowTest(size, labels)
    local order = { "QUEST", "HERB", "ORE" }
    testToken = testToken + 1
    local token = testToken
    for i, category in ipairs(order) do
        tests[i] = tests[i] or CreateFx()
        local x = (i - 2) * (size * 2 + 40)
        tests[i]:Play(UIParent, category, labels and labels[category], size, x, 120)
    end
    C_Timer.After(6, function()
        if token ~= testToken then
            return
        end
        for _, fx in ipairs(tests) do
            fx:Stop()
        end
    end)
end
