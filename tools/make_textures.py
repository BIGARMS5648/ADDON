#!/usr/bin/env python3
"""Generate the sparkle textures used by Twinkle (and an animated preview).

The textures are white with a shaped alpha channel so the addon can tint
them per category with SetVertexColor() and draw them with the ADD blend mode.
They are written as uncompressed 32-bit TGA files, which WoW loads directly.

Usage:
    python3 tools/make_textures.py            # writes Twinkle/Media/*.tga
    python3 tools/make_textures.py --preview  # also writes docs/preview.gif
"""

import argparse
import math
import os
import struct

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "Twinkle", "Media")


def grid(size):
    """Return x, y coordinate grids in [-1, 1] (pixel centers)."""
    c = (np.arange(size) + 0.5) / size * 2.0 - 1.0
    x, y = np.meshgrid(c, -c)
    return x, y


def glow(size=128):
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    a = np.exp(-(r / 0.42) ** 2 * 1.6)
    a *= np.clip((1.0 - r) / 0.12, 0.0, 1.0)  # fade to zero before the edge
    return a


def ray(along, across, width, length=1.0):
    """A tapered light ray along one axis."""
    t = np.clip(1.0 - np.abs(along) / length, 0.0, 1.0)
    w = width * (0.15 + 0.85 * t)
    return (t ** 1.6) * np.exp(-(across / np.maximum(w, 1e-4)) ** 2)


def star(size=128):
    """Four long rays plus four short diagonal rays and a bright core."""
    x, y = grid(size)
    d1 = (x + y) / math.sqrt(2.0)
    d2 = (x - y) / math.sqrt(2.0)
    main = np.maximum(ray(x, y, 0.07), ray(y, x, 0.07))
    diag = 0.45 * np.maximum(ray(d1, d2, 0.05, 0.55), ray(d2, d1, 0.05, 0.55))
    r = np.sqrt(x * x + y * y)
    core = np.exp(-(r / 0.16) ** 2)
    a = np.clip(np.maximum.reduce([main, diag, core]), 0.0, 1.0)
    a *= np.clip((1.0 - r) / 0.08, 0.0, 1.0)  # fade to zero before the edge
    return a


def spark(size=64):
    """Small, crisp four-point twinkle."""
    x, y = grid(size)
    main = np.maximum(ray(x, y, 0.09, 0.95), ray(y, x, 0.09, 0.95))
    r = np.sqrt(x * x + y * y)
    core = np.exp(-(r / 0.2) ** 2)
    return np.clip(np.maximum(main, core), 0.0, 1.0)


def ring(size=128):
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    a = np.exp(-((r - 0.82) / 0.07) ** 2)
    a += 0.35 * np.exp(-((r - 0.82) / 0.2) ** 2)  # soft halo around the ring
    return np.clip(a, 0.0, 1.0)


def write_tga(path, alpha):
    """Write a white 32-bit uncompressed TGA (bottom-left origin)."""
    h, w = alpha.shape
    a = (np.clip(alpha, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[..., 0:3] = 255  # B, G, R
    rgba[..., 3] = a
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0,  # id length
        0,  # no color map
        2,  # uncompressed true-color
        0, 0, 0,  # color map spec
        0, 0,  # origin
        w, h,
        32,  # bits per pixel
        8,  # 8 alpha bits, bottom-left origin
    )
    with open(path, "wb") as f:
        f.write(header)
        f.write(rgba[::-1].tobytes())  # rows bottom to top


TEXTURES = {
    "glow.tga": glow,
    "star.tga": star,
    "spark.tga": spark,
    "ring.tga": ring,
}


# --- preview -----------------------------------------------------------------
# Mirrors the animation math in Twinkle/Sparkle.lua so the GIF matches the game.

COLORS = {
    "QUEST": (1.00, 0.82, 0.10),
    "HERB": (0.35, 1.00, 0.35),
    "ORE": (0.45, 0.80, 1.00),
}


def resize(alpha, size):
    from PIL import Image

    img = Image.fromarray((alpha * 255).astype(np.uint8), "L")
    return np.asarray(img.resize((max(1, int(size)), max(1, int(size))), Image.BILINEAR)) / 255.0


def rotate(alpha, radians):
    from PIL import Image

    img = Image.fromarray((alpha * 255).astype(np.uint8), "L")
    return np.asarray(img.rotate(math.degrees(radians), Image.BILINEAR)) / 255.0


def add(canvas, alpha, color, cx, cy, strength):
    h, w = alpha.shape
    x0, y0 = int(cx - w / 2), int(cy - h / 2)
    H, W, _ = canvas.shape
    xs, ys = max(0, x0), max(0, y0)
    xe, ye = min(W, x0 + w), min(H, y0 + h)
    if xs >= xe or ys >= ye:
        return
    a = alpha[ys - y0:ye - y0, xs - x0:xe - x0] * strength
    for i in range(3):
        canvas[ys:ye, xs:xe, i] += a * color[i]


def render_preview(path):
    from PIL import Image

    rng = np.random.default_rng(7)
    tex = {name: fn() for name, fn in TEXTURES.items()}
    size = 96
    W, H = 3 * 170, 190
    frames = []
    sparks = {}
    for cat in COLORS:
        sparks[cat] = [dict(age=-rng.random() * 0.5, life=0.0) for _ in range(7)]
    dt = 1 / 20
    for n in range(60):
        t = n * dt
        canvas = np.zeros((H, W, 3), dtype=np.float32)
        canvas[...] = (0.07, 0.08, 0.10)
        for i, (cat, color) in enumerate(COLORS.items()):
            cx, cy = 85 + i * 170, 95
            p = 0.5 + 0.5 * math.sin(t * 3.2)
            g = resize(tex["glow.tga"], size * (1.15 + 0.15 * p))
            add(canvas, g, color, cx, cy, 0.30 + 0.35 * p)
            rt = (t % 2.4)
            if rt <= 1.0:
                r = resize(tex["ring.tga"], size * (0.4 + 1.4 * rt))
                add(canvas, r, color, cx, cy, (1 - rt) ** 1.5 * 0.8)
            sp = 0.5 + 0.5 * math.sin(t * 4.4 + 1)
            s = resize(rotate(tex["star.tga"], t * 0.7), size * (0.75 + 0.2 * sp))
            add(canvas, s, color, cx, cy, 0.55 + 0.45 * sp)
            add(canvas, s, (1, 1, 1), cx, cy, 0.25 * sp)
            for spk in sparks[cat]:
                spk["age"] += dt
                if spk["age"] >= spk["life"]:
                    ang = rng.random() * 2 * math.pi
                    dist = (0.18 + rng.random() * 0.42) * size
                    spk.update(x=math.cos(ang) * dist, y=math.sin(ang) * dist * 0.8,
                               life=0.55 + rng.random() * 0.6, age=-rng.random() * 0.5,
                               peak=(0.16 + rng.random() * 0.14) * size)
                if spk["age"] > 0:
                    e = math.sin(spk["age"] / spk["life"] * math.pi)
                    k = resize(tex["spark.tga"], max(2, spk["peak"] * e))
                    add(canvas, k, color, cx + spk["x"], cy - spk["y"], e)
                    add(canvas, k, (1, 1, 1), cx + spk["x"], cy - spk["y"], 0.5 * e)
        img = Image.fromarray((np.clip(canvas, 0, 1) * 255).astype(np.uint8), "RGB")
        frames.append(img)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=50, loop=0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preview", action="store_true", help="also render docs/preview.gif")
    args = parser.parse_args()

    os.makedirs(MEDIA, exist_ok=True)
    for name, fn in TEXTURES.items():
        write_tga(os.path.join(MEDIA, name), fn())
        print("wrote", os.path.join("Twinkle", "Media", name))
    if args.preview:
        out = os.path.join(ROOT, "docs", "preview.gif")
        render_preview(out)
        print("wrote", os.path.relpath(out, ROOT))


if __name__ == "__main__":
    main()
