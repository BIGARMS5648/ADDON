#!/usr/bin/env python3
"""Render a picture of Podium's ceremony window from the addon's own code.

The addon is loaded into the mocked WoW API from tests/, the preview ceremony
(/mvp test) is opened and skipped to its end, and the resulting frame tree
(anchors, sizes, colors, textures, text) is laid out and drawn with Pillow.
Game art (class, role, spell and award icons) isn't available outside the
game, so those are drawn as simple stand-ins.

Requires lupa, numpy, Pillow and a Korean font (fonts-nanum).
    python3 tools/render_podium_preview.py [koKR|enUS] [output.png]
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
import run_tests  # noqa: E402

FONT_DIRS = ["/usr/share/fonts/truetype/nanum", "/usr/share/fonts/opentype/nanum"]
SCALE = 2.0  # output pixels per UI unit
MARGIN = 36  # UI units around the window

CLASS_LETTERS = {"WARRIOR": "W", "PRIEST": "P", "ROGUE": "R", "HUNTER": "H", "MAGE": "M"}
ROLE_COLORS = {"Tank": ((0.25, 0.45, 0.9), "T"), "Healer": ((0.2, 0.75, 0.3), "+"), "DPS": ((0.8, 0.2, 0.2), "D")}
ICON_COLORS = {
    "DualWield": (0.75, 0.2, 0.15), "FlashHeal": (0.95, 0.85, 0.35), "DefensiveStance": (0.55, 0.4, 0.25),
    "Kick": (0.5, 0.5, 0.55), "DispelMagic": (0.3, 0.5, 0.95), "PowerWordShield": (0.55, 0.8, 1.0),
    "Fire_Fire": (1.0, 0.45, 0.1), "FeignDeath": (0.55, 0.3, 0.65),
}


def font_path(bold):
    for d in FONT_DIRS:
        p = os.path.join(d, "NanumGothicBold.ttf" if bold else "NanumGothic.ttf")
        if os.path.exists(p):
            return p
    raise SystemExit("Korean font not found: install fonts-nanum")


_fonts = {}


def get_font(size, bold=True):
    key = (round(size * SCALE), bold)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(font_path(bold), key[0])
    return _fonts[key]


def text_width(text, size):
    """Width in UI units."""
    return get_font(size).getlength(str(text)) / SCALE


def wrap(text, size, width):
    """Splits text into lines no wider than width (UI units)."""
    words = str(text).split(" ")
    lines, line = [], ""
    for word in words:
        test = word if not line else line + " " + word
        if text_width(test, size) <= width or not line:
            line = test
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    # very long single words (no spaces) are cut by characters
    out = []
    for line in lines:
        while text_width(line, size) > width and len(line) > 1:
            cut = len(line)
            while cut > 1 and text_width(line[:cut], size) > width:
                cut -= 1
            out.append(line[:cut])
            line = line[cut:]
        out.append(line)
    return out


LAYOUT_LUA = r"""
local measure, wrapCount = ...
local LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }
local EDGES = {
    TOPLEFT = { "l", "t" }, TOP = { "cx", "t" }, TOPRIGHT = { "r", "t" },
    LEFT = { "l", "cy" }, CENTER = { "cx", "cy" }, RIGHT = { "r", "cy" },
    BOTTOMLEFT = { "l", "b" }, BOTTOM = { "cx", "b" }, BOTTOMRIGHT = { "r", "b" },
}
local rects = {}

local function isRegion(r) return r.kind == "Texture" or r.kind == "FontString" end

local function scaleOf(r)
    local s, f = 1, isRegion(r) and r.parent or r
    while f do s = s * (f.scale or 1); f = f.parent end
    return s
end

local function alphaOf(r)
    local a, f = r.alpha or 1, r.parent
    while f do a = a * (f.alpha or 1); f = f.parent end
    return a
end

local function pointPos(rc, point)
    local e = EDGES[point]
    local x = e[1] == "l" and rc.l or e[1] == "r" and rc.r or (rc.l + rc.r) / 2
    local y = e[2] == "t" and rc.t or e[2] == "b" and rc.b or (rc.t + rc.b) / 2
    return x, y
end

local rect
rect = function(r)
    if rects[r] then return rects[r] end
    if r == UIParent then
        rects[r] = { l = 0, b = 0, r = UIParent.width, t = UIParent.height }
        return rects[r]
    end
    local s = scaleOf(r)
    local w, h = (r.width or 0) * s, (r.height or 0) * s
    if r.kind == "FontString" and r.font then
        local size = r.font.size * s
        local text = r.text and tostring(r.text) or ""
        if (r.width or 0) == 0 then w = measure(text, size) end
        if (r.height or 0) == 0 then
            local lines = 1
            if (r.width or 0) > 0 and r.wordWrap ~= false then
                lines = wrapCount(text, size, w)
                if r.maxLines then lines = math.min(lines, r.maxLines) end
            end
            h = lines * size * 1.3
        end
    end
    local c = {}
    for _, p in ipairs(r.points) do
        local point, rel, relPoint, x, y = p[1], p[2], p[3], p[4], p[5]
        if type(rel) == "number" then
            rel, relPoint, x, y = r.parent, point, p[2], p[3]
        elseif rel == nil then
            rel, relPoint = r.parent, point
        end
        relPoint = relPoint or point
        local rx, ry = pointPos(rect(rel), relPoint)
        rx, ry = rx + (x or 0) * s, ry + (y or 0) * s
        local e = EDGES[point]
        c[e[1]], c[e[2]] = rx, ry
    end
    local rc = {}
    if c.l and c.r then rc.l, rc.r = c.l, c.r
    elseif c.l then rc.l, rc.r = c.l, c.l + w
    elseif c.r then rc.l, rc.r = c.r - w, c.r
    else local cx = c.cx or 0; rc.l, rc.r = cx - w / 2, cx + w / 2 end
    if c.t and c.b then rc.t, rc.b = c.t, c.b
    elseif c.t then rc.t, rc.b = c.t, c.t - h
    elseif c.b then rc.t, rc.b = c.b + h, c.b
    else local cy = c.cy or 0; rc.t, rc.b = cy + h / 2, cy - h / 2 end
    rects[r] = rc
    return rc
end

local items = {}
local function add(r, kind)
    local rc = rect(r)
    local item = {
        kind = kind, l = rc.l, r = rc.r, t = rc.t, b = rc.b, alpha = alphaOf(r), scale = scaleOf(r),
        color = r.colorTexture, texture = r.texture, atlas = r.atlas, blend = r.blend,
        rotation = r.rotation, vertex = r.color, gradient = r.gradient, template = r.template,
        text = r.text ~= nil and tostring(r.text) or nil, font = r.font, textColor = r.textColor,
        justifyH = r.justifyH, justifyV = r.justifyV, wordWrap = r.wordWrap, maxLines = r.maxLines,
        width = r.width,
    }
    items[#items + 1] = item
end

local function draw(f)
    if f.shown == false then return end
    if f.template == "UIPanelButtonTemplate" or f.template == "UIPanelCloseButton" then
        add(f, f.template)
    end
    local regions = {}
    for i, r in ipairs(f.regions or {}) do regions[#regions + 1] = { r = r, i = i } end
    table.sort(regions, function(a, b)
        local la, lb = LAYERS[a.r.layer] or 3, LAYERS[b.r.layer] or 3
        if la ~= lb then return la < lb end
        if (a.r.sublevel or 0) ~= (b.r.sublevel or 0) then return (a.r.sublevel or 0) < (b.r.sublevel or 0) end
        return a.i < b.i
    end)
    for _, entry in ipairs(regions) do
        if entry.r.shown ~= false then add(entry.r, entry.r.kind) end
    end
    local children = {}
    for i, c in ipairs(f.children or {}) do children[#children + 1] = { c = c, i = i } end
    table.sort(children, function(a, b)
        if (a.c.frameLevel or 1) ~= (b.c.frameLevel or 1) then return (a.c.frameLevel or 1) < (b.c.frameLevel or 1) end
        return a.i < b.i
    end)
    for _, entry in ipairs(children) do draw(entry.c) end
end

local frame = ns.Ceremony:GetFrame()
draw(frame)
local fr = rect(frame)
return items, fr.l, fr.b, fr.r, fr.t
"""


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


class Canvas:
    def __init__(self, left, bottom, right, top):
        self.left, self.top = left - MARGIN, top + MARGIN
        w = (right - left + 2 * MARGIN) * SCALE
        h = (top - bottom + 2 * MARGIN) * SCALE
        self.w, self.h = int(round(w)), int(round(h))
        self.img = np.zeros((self.h, self.w, 3), dtype=np.float64)

    def box(self, item):
        x0 = (item["l"] - self.left) * SCALE
        x1 = (item["r"] - self.left) * SCALE
        y0 = (self.top - item["t"]) * SCALE
        y1 = (self.top - item["b"]) * SCALE
        return x0, y0, x1, y1

    def blend(self, rgba, x0, y0, additive=False):
        """Composite an (h, w, 4) float layer with its top-left corner at x0, y0."""
        h, w = rgba.shape[:2]
        x0, y0 = int(round(x0)), int(round(y0))
        xs, ys = max(0, x0), max(0, y0)
        xe, ye = min(self.w, x0 + w), min(self.h, y0 + h)
        if xs >= xe or ys >= ye:
            return
        part = rgba[ys - y0:ye - y0, xs - x0:xe - x0]
        a = part[..., 3:4]
        dst = self.img[ys:ye, xs:xe]
        if additive:
            dst += part[..., :3] * a
        else:
            dst *= 1 - a
            dst += part[..., :3] * a
        np.clip(dst, 0, 1, out=dst)


def solid(w, h, color, alpha):
    layer = np.zeros((max(1, h), max(1, w), 4))
    layer[..., :3] = color[:3]
    layer[..., 3] = alpha
    return layer


def load_media(path, cache={}):
    name = path.split("\\")[-1]
    if name not in cache:
        file = os.path.join(ROOT, "Podium", "Media", name + ".tga")
        cache[name] = Image.open(file).convert("RGBA") if os.path.exists(file) else None
    return cache[name]


def icon_layer(size, color, glyph=None, circle=False, kind=None):
    """Stand-in for game icons."""
    s = max(2, int(round(size)))
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = tuple(int(v * 255) for v in color)
    dark = tuple(int(v * 120) for v in color)
    if circle:
        d.ellipse([0, 0, s - 1, s - 1], fill=dark + (255,), outline=(20, 20, 20, 255), width=max(1, s // 16))
        d.ellipse([s * 0.1, s * 0.1, s * 0.9, s * 0.9], fill=c + (255,))
    else:
        d.rectangle([0, 0, s - 1, s - 1], fill=(15, 15, 18, 255))
        for i in range(s // 2):  # radial-ish gradient
            t = i / (s / 2)
            col = tuple(int(dark[k] + (c[k] - dark[k]) * t) for k in range(3))
            d.rectangle([i * 0.5 + 2, i * 0.5 + 2, s - 3 - i * 0.5, s - 3 - i * 0.5], fill=col + (255,))
        d.rectangle([0, 0, s - 1, s - 1], outline=(0, 0, 0, 255), width=max(1, s // 20))
    white = (255, 255, 255, 235)
    m, wdt = s * 0.25, max(2, s // 9)
    if kind == "DualWield":
        d.line([m, m, s - m, s - m], fill=white, width=wdt)
        d.line([s - m, m, m, s - m], fill=white, width=wdt)
    elif kind == "FlashHeal":
        d.line([s / 2, m, s / 2, s - m], fill=white, width=wdt + 2)
        d.line([m, s / 2, s - m, s / 2], fill=white, width=wdt + 2)
    elif kind == "DefensiveStance":
        d.polygon([(m, m), (s - m, m), (s - m, s * 0.55), (s / 2, s - m), (m, s * 0.55)], outline=white, width=wdt)
    elif kind == "Kick":
        d.ellipse([m, m, s - m, s - m], outline=white, width=wdt)
        d.line([m * 1.3, s - m * 1.3, s - m * 1.3, m * 1.3], fill=white, width=wdt)
    elif kind == "DispelMagic":
        for a in range(4):
            ang = a * math.pi / 4
            dx, dy = math.cos(ang) * (s / 2 - m), math.sin(ang) * (s / 2 - m)
            d.line([s / 2 - dx, s / 2 - dy, s / 2 + dx, s / 2 + dy], fill=white, width=max(1, wdt - 1))
    elif kind == "PowerWordShield":
        d.ellipse([m, m, s - m, s - m], outline=white, width=wdt)
    elif kind == "Fire_Fire":
        d.polygon([(s / 2, m), (s - m, s - m), (m, s - m)], fill=white)
    elif kind == "FeignDeath":
        d.ellipse([m, m, s - m, s * 0.7], fill=white)
        d.ellipse([s * 0.36, s * 0.38, s * 0.46, s * 0.5], fill=dark + (255,))
        d.ellipse([s * 0.54, s * 0.38, s * 0.64, s * 0.5], fill=dark + (255,))
    elif glyph:
        f = get_font(size / SCALE * 0.55)
        ink = (40, 40, 40, 235) if sum(color) > 2.4 else white
        d.text((s / 2, s / 2), glyph, font=f, fill=ink, anchor="mm")
    return np.asarray(img).astype(np.float64) / 255.0


def draw_texture(canvas, item):
    x0, y0, x1, y1 = canvas.box(item)
    w, h = int(round(x1 - x0)), int(round(y1 - y0))
    if w <= 0 or h <= 0 or item["alpha"] <= 0.003:
        return
    alpha = item["alpha"]
    if item["color"] is not None:
        r, g, b, a = (item["color"][i] for i in range(1, 5))
        grad = item["gradient"]
        if grad is not None:
            lo, hi = grad[2], grad[3]  # VERTICAL: min at the bottom, max at the top
            t = np.linspace(1, 0, h)[:, None]
            layer = np.zeros((h, w, 4))
            for k, key in enumerate("rgb"):
                layer[..., k] = (lo[key] + (hi[key] - lo[key]) * t) * (r, g, b)[k]
            layer[..., 3] = (lo["a"] + (hi["a"] - lo["a"]) * t) * a * alpha
        else:
            layer = solid(w, h, (r, g, b), a * alpha)
        canvas.blend(layer, x0, y0)
        return
    vertex = item["vertex"]
    tint = np.array([vertex[1], vertex[2], vertex[3]]) if vertex is not None else np.ones(3)
    tex = item["texture"]
    if isinstance(tex, str) and "AddOns\\Podium\\Media" in tex:
        img = load_media(tex)
        if img is None:
            return
        if item["rotation"]:
            img = img.rotate(math.degrees(item["rotation"]), Image.BILINEAR)
        img = img.resize((w, h), Image.BILINEAR)
        layer = np.asarray(img).astype(np.float64) / 255.0
        layer[..., :3] *= tint
        layer[..., 3] *= alpha
        canvas.blend(layer, x0, y0, additive=item["blend"] == "ADD")
        return
    atlas = item["atlas"]
    if atlas and atlas.startswith("classicon-"):
        cls = atlas.split("-", 1)[1].upper()
        color = {"WARRIOR": (0.78, 0.61, 0.43), "PRIEST": (0.9, 0.9, 0.9), "ROGUE": (1, 0.96, 0.41),
                 "HUNTER": (0.67, 0.83, 0.45), "MAGE": (0.25, 0.78, 0.92)}.get(cls, (0.6, 0.6, 0.6))
        layer = icon_layer(min(w, h), color, CLASS_LETTERS.get(cls, "?"), circle=True)
    elif atlas and atlas.startswith("UI-LFG-RoleIcon-"):
        color, glyph = ROLE_COLORS.get(atlas.split("-")[-1], ((0.5, 0.5, 0.5), "?"))
        layer = icon_layer(min(w, h), color, glyph, circle=True)
    elif isinstance(tex, str) and "Icons" in tex:
        kind = next((k for k in ICON_COLORS if k in tex), None)
        layer = icon_layer(min(w, h), ICON_COLORS.get(kind, (0.5, 0.5, 0.5)), "?", kind=kind)
    elif tex is not None:  # spell icon (file ID)
        palette = [(0.85, 0.35, 0.1), (0.3, 0.55, 0.95), (0.8, 0.75, 0.3)]
        layer = icon_layer(min(w, h), palette[int(tex) % 3], "*")
    else:
        return
    layer = layer.copy()
    layer[..., 3] *= alpha
    canvas.blend(layer, x0, y0)


def draw_text(canvas, item):
    text = item["text"]
    font = item["font"]
    if not text or font is None or item["alpha"] <= 0.003:
        return
    size = font["size"] * item["scale"]
    bold = size >= 12 or "OUTLINE" in font["flags"]
    f = get_font(size, bold)
    x0, y0, x1, y1 = canvas.box(item)
    width = (x1 - x0) / SCALE
    if item["width"] and item["wordWrap"] is not False:
        lines = wrap(text, size, width)
        if item["maxLines"]:
            lines = lines[: int(item["maxLines"])]
    else:
        lines = [text]
        if item["width"] and text_width(text, size) > width:
            while len(lines[0]) > 1 and text_width(lines[0] + "...", size) > width:
                lines[0] = lines[0][:-1]
            lines[0] += "..."
    color = item["textColor"]
    rgb = tuple(int(color[i] * 255) for i in (1, 2, 3)) if color is not None else (255, 210, 0)
    line_h = size * 1.3 * SCALE
    block_h = line_h * len(lines)
    if item["justifyV"] == "TOP":
        top = y0
    else:
        top = y0 + ((y1 - y0) - block_h) / 2
    pad = int(size * SCALE)
    layer = Image.new("RGBA", (int(x1 - x0) + 2 * pad, int(block_h) + 2 * pad), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    a = int(255 * min(1, item["alpha"]))
    justify = item["justifyH"] or "CENTER"
    for n, line in enumerate(lines):
        lw = f.getlength(line)
        if justify == "LEFT":
            lx = pad
        elif justify == "RIGHT":
            lx = pad + (x1 - x0) - lw
        else:
            lx = pad + ((x1 - x0) - lw) / 2
        ly = pad + n * line_h + line_h / 2
        outline = "OUTLINE" in font["flags"]
        d.text((lx + SCALE, ly + SCALE), line, font=f, fill=(0, 0, 0, int(a * 0.8)), anchor="lm")
        d.text((lx, ly), line, font=f, fill=rgb + (a,), anchor="lm",
               stroke_width=int(SCALE) if outline else 0, stroke_fill=(0, 0, 0, a))
    canvas.blend(np.asarray(layer).astype(np.float64) / 255.0, x0 - pad, top - pad)


def draw_button(canvas, item, kind):
    x0, y0, x1, y1 = canvas.box(item)
    w, h = int(x1 - x0), int(y1 - y0)
    if kind == "UIPanelCloseButton":
        w = h = int(28 * SCALE)
        x0, y0 = x1 - w, y0
    if w <= 0 or h <= 0:
        return
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if kind == "UIPanelCloseButton":
        d.rounded_rectangle([4, 4, w - 5, h - 5], radius=6, fill=(120, 20, 15, 255), outline=(200, 160, 60, 255), width=2)
        m = w * 0.33
        d.line([m, m, w - m, h - m], fill=(255, 220, 200, 255), width=4)
        d.line([w - m, m, m, h - m], fill=(255, 220, 200, 255), width=4)
    else:
        d.rounded_rectangle([0, 0, w - 1, h - 1], radius=6, fill=(110, 18, 12, 255), outline=(190, 150, 60, 255), width=2)
        d.rounded_rectangle([3, 3, w - 4, h // 2], radius=4, fill=(150, 35, 25, 255))
        if item["text"]:
            d.text((w / 2, h / 2), item["text"], font=get_font(12), fill=(255, 210, 0, 255), anchor="mm")
    canvas.blend(np.asarray(img).astype(np.float64) / 255.0 * [1, 1, 1, item["alpha"]], x0, y0)


def background(canvas):
    """Something game-like behind the darkened screen."""
    h, w = canvas.h, canvas.w
    y = np.linspace(0, 1, h)[:, None]
    x = np.linspace(0, 1, w)[None, :]
    sky = np.stack([0.25 + 0.2 * y + 0 * x, 0.35 + 0.15 * y + 0 * x, 0.45 - 0.15 * y + 0 * x], axis=-1)
    ground = (y > 0.62) * 1.0
    img = sky * (1 - ground[..., None]) + np.stack([0.22 + 0 * x + 0 * y, 0.3 + 0 * x + 0 * y, 0.16 + 0 * x + 0 * y], -1) * ground[..., None]
    canvas.img[...] = img


def main():
    locale = sys.argv[1] if len(sys.argv) > 1 else "koKR"
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "docs", "podium_preview.png")
    lua, run_chunk, mock = run_tests.load("Podium", locale)
    name = "모험가" if locale == "koKR" else "Adventurer"
    lua.execute(f"""
        mock.units.player = {{ name = "{name}", guid = "Player-1-0001", class = "MAGE" }}
        mock.fire("ADDON_LOADED", "Podium")
        mock.fire("PLAYER_LOGIN")
        ns:ShowDemo()
        ns.Ceremony:Skip()
        local f = ns.Ceremony:GetFrame()
        for _ = 1, 30 do f.scripts.OnUpdate(f, 0.05) end
    """)
    measure = lambda text, size: text_width(text, size)
    wrap_count = lambda text, size, width: len(wrap(text, size, width))
    items, left, bottom, right, top = run_chunk(LAYOUT_LUA, "layout", measure, wrap_count)
    canvas = Canvas(left, bottom, right, top)
    background(canvas)
    for item in lua_list(items):
        kind = item["kind"]
        if kind == "Texture":
            draw_texture(canvas, item)
        elif kind == "FontString":
            draw_text(canvas, item)
        elif kind in ("UIPanelButtonTemplate", "UIPanelCloseButton"):
            draw_button(canvas, item, kind)
    img = Image.fromarray((np.clip(canvas.img, 0, 1) * 255).astype(np.uint8), "RGB")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, optimize=True)
    print("wrote", os.path.relpath(out, ROOT), img.size)


if __name__ == "__main__":
    main()
