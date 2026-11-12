#!/usr/bin/env python3
"""Draw the BIG PODIUM project logo (square PNG for CurseForge).

A gold / silver / bronze podium with a trophy on the winner's step, light
rays, stage lights, confetti and the name. Drawn at 3x and scaled down.

Usage:
    python3 tools/make_curseforge_logo.py [output.png] [size]
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIRS = ["/usr/share/fonts/opentype/inter", "/usr/share/fonts/truetype/nanum"]
FONT_NAMES = ["Inter-Black.otf", "Inter-ExtraBold.otf", "InterDisplay-Bold.otf", "NanumSquareB.ttf"]

W = 800  # design size
SS = 3  # supersampling

GOLD = (1.0, 0.78, 0.30)
SILVER = (0.82, 0.86, 0.94)
BRONZE = (0.88, 0.55, 0.30)


def font(size):
    for d in FONT_DIRS:
        for name in FONT_NAMES:
            path = os.path.join(d, name)
            if os.path.exists(path):
                return ImageFont.truetype(path, int(size * SS))
    raise SystemExit("no bold font found")


def px(v):
    return int(round(v * SS))


def grid(n):
    y, x = np.mgrid[0:n, 0:n].astype(np.float64)
    return x / SS, y / SS  # in design units


class Canvas:
    def __init__(self):
        n = W * SS
        self.n = n
        self.rgb = np.zeros((n, n, 3))

    def over(self, color, alpha):
        """Paints a color through an alpha mask (float array or scalar)."""
        a = np.clip(alpha, 0, 1)[..., None] if np.ndim(alpha) else alpha
        self.rgb = self.rgb * (1 - a) + np.array(color) * a

    def add(self, color, alpha):
        self.rgb = self.rgb + np.array(color) * np.clip(alpha, 0, 1)[..., None]

    def paste_image(self, img):
        """Composites an RGBA PIL image the size of the canvas."""
        arr = np.asarray(img).astype(np.float64) / 255.0
        a = arr[..., 3:4]
        self.rgb = self.rgb * (1 - a) + arr[..., :3] * a


def mask_from(draw_fn):
    img = Image.new("L", (W * SS, W * SS), 0)
    draw_fn(ImageDraw.Draw(img))
    return np.asarray(img).astype(np.float64) / 255.0


def background(c, x, y):
    # warm glow behind the podium, dark stage around it
    r = np.sqrt(((x - 400) / 430) ** 2 + ((y - 360) / 400) ** 2)
    t = np.clip(r, 0, 1)
    warm = np.array([0.22, 0.14, 0.05])
    dark = np.array([0.03, 0.03, 0.06])
    c.rgb = warm * (1 - t[..., None]) ** 1.6 + dark * (1 - (1 - t[..., None]) ** 1.6)


def rays(c, x, y):
    cx, cy = 400, 330
    dx, dy = x - cx, y - cy
    r = np.sqrt(dx * dx + dy * dy)
    theta = np.arctan2(dy, dx)
    beams = (0.5 + 0.5 * np.cos(18 * theta)) ** 4
    fade = np.exp(-(r / 300) ** 2) * np.clip(r / 40, 0, 1)
    c.add((1.0, 0.8, 0.35), 0.55 * beams * fade + 0.35 * np.exp(-(r / 120) ** 2))


def spotlights(c, x, y):
    for lx in (40, 760):
        ly = 30
        tx, ty = 400, 330
        ax, ay = tx - lx, ty - ly
        length = math.hypot(ax, ay)
        ux, uy = ax / length, ay / length
        px_, py_ = x - lx, y - ly
        along = px_ * ux + py_ * uy
        across = np.abs(-px_ * uy + py_ * ux)
        width = 8 + along * 0.32
        cone = np.exp(-(across / np.maximum(width, 1)) ** 2 * 2) * np.clip(along / 30, 0, 1) * np.clip(1 - along / 620, 0, 1)
        lamp = np.exp(-((px_ ** 2 + py_ ** 2) / 20 ** 2))
        c.add((1.0, 0.93, 0.75), 0.22 * cone + 0.8 * lamp)


def metal_front(c, x, y, x0, x1, top, bottom, color, numeral):
    inside = ((x >= x0) & (x < x1) & (y >= top) & (y < bottom)) * 1.0
    v = np.clip((y - top) / (bottom - top), 0, 1)
    lum = 0.95 - 0.42 * v + 0.2 * np.exp(-((v - 0.12) / 0.07) ** 2)
    # bevels
    lum = np.where(y < top + 3, lum * 1.25, lum)
    lum = np.where(y > bottom - 4, lum * 0.55, lum)
    lum = np.where((x < x0 + 3) | (x > x1 - 3), lum * 0.75, lum)
    # engraved plaque
    pad_x, pad_top, pad_bottom = (x1 - x0) * 0.1, (bottom - top) * 0.12, (bottom - top) * 0.1
    px0, px1, py0, py1 = x0 + pad_x, x1 - pad_x, top + pad_top, bottom - pad_bottom
    plaque = (x >= px0) & (x < px1) & (y >= py0) & (y < py1)
    lum = np.where(plaque, 0.42 + 0.08 * (1 - (y - py0) / (py1 - py0)), lum)
    rim_dark = plaque & ((y < py0 + 2.5) | (x < px0 + 2.5))
    rim_light = plaque & ((y > py1 - 2.5) | (x > px1 - 2.5))
    lum = np.where(rim_dark, 0.2, lum)
    lum = np.where(rim_light, 1.05, lum)
    shade = np.clip(lum, 0, 1.2)[..., None] * np.array(color)
    c.rgb = c.rgb * (1 - inside[..., None]) + shade * inside[..., None]
    # raised numeral: bright metal with a dark edge below-right
    size = (py1 - py0) * 0.95
    f = font(size)
    cx, cy = (x0 + x1) / 2, (py0 + py1) / 2
    for dx, dy, col, alpha in ((2.2, 2.2, tuple(k * 0.18 for k in color), 0.9),
                               (0, 0, tuple(min(1, k * 1.08) for k in color), 1.0)):
        img = Image.new("L", (W * SS, W * SS), 0)
        ImageDraw.Draw(img).text((px(cx + dx), px(cy + dy)), numeral, font=f, fill=255, anchor="mm")
        m = np.asarray(img).astype(np.float64) / 255.0 * alpha
        c.over(col, m)


def metal_top(c, x, y, x0, x1, top, depth, color):
    # trapezoid: narrower at the back
    v = np.clip((y - (top - depth)) / depth, 0, 1)
    inset = (x1 - x0) * 0.05 * (1 - v)
    inside = ((y >= top - depth) & (y < top) & (x >= x0 + inset) & (x < x1 - inset)) * 1.0
    lum = 0.82 + 0.2 * v
    lum = np.where(y > top - 2.5, 1.12, lum)
    shade = np.clip(lum, 0, 1.2)[..., None] * np.minimum(1, np.array(color) * 1.1)
    c.rgb = c.rgb * (1 - inside[..., None]) + shade * inside[..., None]


def trophy(c, x, y):
    cx = 400
    gold_dark = (0.55, 0.36, 0.06)

    def shape(d, grow=0):
        g = px(grow)
        # base plinth and foot
        d.rounded_rectangle([px(cx - 62) - g, px(388) - g, px(cx + 62) + g, px(424) + g], radius=px(6), fill=255)
        d.rounded_rectangle([px(cx - 40) - g, px(372) - g, px(cx + 40) + g, px(392) + g], radius=px(5), fill=255)
        # stem and knot
        d.rectangle([px(cx - 13) - g, px(318) - g, px(cx + 13) + g, px(376) + g], fill=255)
        d.ellipse([px(cx - 26) - g, px(332) - g, px(cx + 26) + g, px(352) + g], fill=255)
        # cup: a bowl
        d.pieslice([px(cx - 88) - g, px(150) - g, px(cx + 88) + g, px(330) + g], 0, 180, fill=255)
        d.rectangle([px(cx - 88) - g, px(198) - g, px(cx + 88) + g, px(240) + g], fill=255)
        # handles: loops joined to the side of the cup
        for side in (-1, 1):
            bx = cx + side * 74
            box = [px(min(bx, bx + side * 62)) - g, px(204) - g, px(max(bx, bx + side * 62)) + g, px(296) + g]
            d.arc(box, 0, 360, fill=255, width=px(16) + 2 * g)

    outline = mask_from(lambda d: shape(d, 4))
    body = mask_from(lambda d: shape(d, 0))
    c.over((0.12, 0.07, 0.01), outline)
    # metallic gold: light from the upper left, a bright vertical streak
    lum = 0.75 + 0.35 * np.exp(-((x - (cx - 38)) / 16) ** 2) - 0.25 * np.clip((x - cx) / 90, 0, 1)
    lum = lum + 0.15 * np.clip((240 - y) / 80, 0, 1)
    gold = np.clip(lum, 0, 1.25)[..., None] * np.array(GOLD)
    c.rgb = c.rgb * (1 - body[..., None]) + gold * body[..., None]
    # rim of the cup and the shadow inside it
    rim = mask_from(lambda d: d.ellipse([px(cx - 88), px(186), px(cx + 88), px(212)], fill=255))
    inner = mask_from(lambda d: d.ellipse([px(cx - 80), px(190), px(cx + 80), px(208)], fill=255))
    c.over((1.0, 0.92, 0.6), rim)
    c.over(gold_dark, inner)
    # a star on the cup
    star = mask_from(lambda d: d.polygon(star_points(cx, 262, 30, 12), fill=255))
    c.over((1.0, 0.97, 0.8), star * 0.95)


def star_points(cx, cy, outer, inner, points=5):
    pts = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = -math.pi / 2 + i * math.pi / points
        pts.append((px(cx + r * math.cos(a)), px(cy + r * math.sin(a))))
    return pts


def sparkles(c, x, y):
    for sx, sy, size in ((300, 190, 22), (505, 168, 16), (560, 270, 12), (250, 290, 11)):
        d = np.sqrt((x - sx) ** 2 + (y - sy) ** 2)
        cross = (np.exp(-(np.abs(x - sx) / 1.6) ** 2) * np.exp(-(np.abs(y - sy) / size) ** 2)
                 + np.exp(-(np.abs(y - sy) / 1.6) ** 2) * np.exp(-(np.abs(x - sx) / size) ** 2))
        c.add((1.0, 0.95, 0.75), 0.9 * cross + 0.6 * np.exp(-(d / 4) ** 2))


def confetti(c):
    rng = np.random.default_rng(5)
    colors = [(1, 0.82, 0.25), (1, 1, 1), (1, 0.45, 0.2), (0.45, 0.8, 1), (1, 0.5, 0.78), (0.55, 1, 0.5)]
    img = Image.new("RGBA", (W * SS, W * SS), (0, 0, 0, 0))
    count = 0
    while count < 46:
        x, y = rng.uniform(30, 770), rng.uniform(40, 560)
        if 300 < x < 500 and 140 < y < 430:  # keep the trophy clear
            continue
        if 90 < x < 710 and y > 470:  # and the steps
            continue
        w, h = rng.uniform(7, 11), rng.uniform(12, 18)
        a = rng.uniform(0, math.pi)
        col = colors[count % len(colors)]
        shade = rng.uniform(0.6, 1.0)
        pts = []
        for ox, oy in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)):
            pts.append((px(x + ox * math.cos(a) - oy * math.sin(a)), px(y + ox * math.sin(a) + oy * math.cos(a))))
        fill = tuple(int(255 * k * shade) for k in col) + (int(255 * rng.uniform(0.75, 1.0)),)
        ImageDraw.Draw(img).polygon(pts, fill=fill)
        count += 1
    c.paste_image(img)


def title(c):
    text = "BIG PODIUM"
    size = 120
    f = font(size)
    while f.getlength(text) > px(730):
        size -= 2
        f = font(size)
    cx, cy = 400, 708
    # drop shadow
    shadow = Image.new("L", (W * SS, W * SS), 0)
    ImageDraw.Draw(shadow).text((px(cx + 4), px(cy + 6)), text, font=f, fill=255, anchor="mm",
                                stroke_width=px(7), stroke_fill=255)
    shadow = shadow.filter(ImageFilter.GaussianBlur(px(5)))
    c.over((0, 0, 0), np.asarray(shadow).astype(np.float64) / 255.0 * 0.85)
    # dark outline, then gold letters with a vertical gradient
    outline = mask_from(lambda d: d.text((px(cx), px(cy)), text, font=f, fill=255, anchor="mm",
                                         stroke_width=px(6), stroke_fill=255))
    c.over((0.16, 0.08, 0.0), outline)
    letters = mask_from(lambda d: d.text((px(cx), px(cy)), text, font=f, fill=255, anchor="mm"))
    _, y = grid(W * SS)
    t = np.clip((y - (cy - size * 0.38)) / (size * 0.76), 0, 1)
    top_col, mid_col, bot_col = np.array([1.0, 0.97, 0.75]), np.array([1.0, 0.8, 0.28]), np.array([0.78, 0.48, 0.08])
    col = np.where(t[..., None] < 0.45, top_col + (mid_col - top_col) * (t / 0.45)[..., None],
                   mid_col + (bot_col - mid_col) * ((t - 0.45) / 0.55)[..., None])
    c.rgb = c.rgb * (1 - letters[..., None]) + col * letters[..., None]
    # thin highlight line through the upper part of the letters
    shine = letters * np.exp(-((y - (cy - size * 0.18)) / 3) ** 2) * 0.5
    c.add((1, 1, 1), shine)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "docs", "curseforge_logo.png")
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 800
    c = Canvas()
    x, y = grid(W * SS)
    background(c, x, y)
    rays(c, x, y)
    spotlights(c, x, y)
    # floor shadow under the podium
    d = np.sqrt(((x - 400) / 360) ** 2 + ((y - 612) / 22) ** 2)
    c.over((0, 0, 0), 0.6 * np.exp(-d * d * 1.5))
    # steps: silver (2), gold (1), bronze (3), touching like one podium
    metal_top(c, x, y, 95, 290, 500, 26, SILVER)
    metal_front(c, x, y, 95, 290, 500, 612, SILVER, "2")
    metal_top(c, x, y, 510, 705, 528, 26, BRONZE)
    metal_front(c, x, y, 510, 705, 528, 612, BRONZE, "3")
    metal_top(c, x, y, 290, 510, 430, 28, GOLD)
    metal_front(c, x, y, 290, 510, 430, 612, GOLD, "1")
    # shade on the lower steps next to the winner's
    for x0, x1, top, side in ((262, 290, 500, 1), (510, 538, 528, -1)):
        t = np.clip((x - x0) / (x1 - x0), 0, 1)
        t = t if side > 0 else 1 - t
        band = ((x >= x0) & (x < x1) & (y >= top - 26) & (y < top)) * t * 0.45
        c.over((0, 0, 0), band)
    trophy(c, x, y)
    sparkles(c, x, y)
    confetti(c)
    title(c)
    rgb = np.clip(c.rgb, 0, 1)
    img = Image.fromarray((rgb * 255).astype(np.uint8), "RGB")
    img = img.resize((size, size), Image.LANCZOS)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    img.save(out, optimize=True)
    print("wrote", os.path.relpath(out, ROOT), img.size)


if __name__ == "__main__":
    main()
