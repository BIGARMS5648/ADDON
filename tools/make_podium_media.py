#!/usr/bin/env python3
"""Generate the textures used by BIG PODIUM.

Light textures (rays, glow, star, ring, beam) are white with a shaped alpha
channel; the addon tints them gold with SetVertexColor() and draws them with
the ADD blend mode. The podium parts (front, top) are grayscale metal that the
addon tints gold / silver / bronze; shadow is black with a soft alpha; confetti
is a white flake tinted per piece. The icon is a colored podium. All are
uncompressed 32-bit TGA.

Usage:
    python3 tools/make_podium_media.py      # writes BigPodium/Media/*.tga
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_textures import glow, grid, ray, ring, star, write_tga  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "BigPodium", "Media")


def rays(size=256, count=14):
    """Sunburst behind the MVP: soft beams fading out before the edge, so the
    texture can spin without showing its square corners."""
    x, y = grid(size)
    r = np.sqrt(x * x + y * y)
    theta = np.arctan2(y, x)
    beams = (0.5 + 0.5 * np.cos(count * theta)) ** 3
    thin = 0.35 * (0.5 + 0.5 * np.cos(count * theta + math.pi)) ** 12  # faint beams in between
    fade = np.clip(1.0 - r, 0.0, 1.0) ** 1.4
    core = np.exp(-(r / 0.22) ** 2) * 0.6
    a = (beams + thin) * fade * np.clip(r / 0.12, 0.0, 1.0) + core
    return np.clip(a, 0.0, 1.0)


def icon(size=64, supersample=4):
    """Colored addon icon: gold / silver / bronze podium with a star on top."""
    n = size * supersample
    x, y = grid(n)
    rgb = np.zeros((n, n, 3))
    alpha = np.zeros((n, n))

    def paint(mask, color):
        nonlocal rgb, alpha
        m = mask.astype(np.float64)
        rgb = rgb * (1 - m[..., None]) + np.array(color) * m[..., None]
        alpha = np.maximum(alpha, m)

    def box(x0, x1, y0, y1):
        return (x >= x0) & (x <= x1) & (y >= y0) & (y <= y1)

    bottom = -0.92
    # blocks: shaded front with a lighter top strip
    for x0, x1, top, base, light in (
        (-0.92, -0.33, -0.12, (0.62, 0.66, 0.74), (0.85, 0.88, 0.95)),  # 2nd: silver
        (0.33, 0.92, -0.36, (0.66, 0.38, 0.16), (0.88, 0.58, 0.3)),  # 3rd: bronze
        (-0.36, 0.36, 0.14, (0.86, 0.6, 0.08), (1.0, 0.85, 0.3)),  # 1st: gold
    ):
        paint(box(x0, x1, bottom, top), base)
        paint(box(x0, x1, top - 0.1, top), light)
    # star above the winner
    cx, cy, outer, inner = 0.0, 0.55, 0.36, 0.15
    angles = np.arctan2(y - cy, x - cx)
    dist = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
    # radius of a 5-point star outline as a function of angle
    k = (angles - math.pi / 2) % (2 * math.pi / 5) / (2 * math.pi / 5)
    edge = inner + (outer - inner) * np.abs(1 - 2 * k) ** 1.5
    paint(dist <= edge, (1.0, 0.86, 0.25))
    paint(dist <= edge * 0.45, (1.0, 0.97, 0.75))
    # downsample (antialiasing): average premultiplied color, then unpremultiply
    a_small = alpha.reshape(size, supersample, size, supersample).mean(axis=(1, 3))
    premul = (rgb * alpha[..., None]).reshape(size, supersample, size, supersample, 3).mean(axis=(1, 3))
    safe = np.where(a_small > 0, a_small, 1)
    out = np.zeros((size, size, 4))
    out[..., :3] = premul / safe[..., None]
    out[..., 3] = a_small
    return out


def _rgba(lum, alpha):
    lum = np.clip(lum, 0.0, 1.0)
    return np.dstack([lum, lum, lum, np.clip(alpha, 0.0, 1.0)])


def podium_front(w=256, h=128, seed=3):
    """Front face of a podium step: brushed metal with a sheen, beveled edges
    and a dark engraved plaque for the name (grayscale, tinted in game)."""
    rng = np.random.default_rng(seed)
    v = (np.arange(h) + 0.5)[:, None] / h  # 0 top .. 1 bottom
    u = (np.arange(w) + 0.5)[None, :] / w
    lum = 0.95 - 0.4 * v + 0 * u
    lum += 0.16 * np.exp(-((v - 0.16) / 0.07) ** 2)  # light band under the top edge
    # brushed metal: faint horizontal streaks
    streaks = rng.normal(0, 1, (h, 1)) * 0.025
    lum += streaks + rng.normal(0, 0.006, (h, w))
    # bevels
    lum[:3] *= 1.25
    lum[3:5] *= 1.1
    lum[-5:] *= 0.6
    lum[:, :3] *= 0.82
    lum[:, -3:] *= 0.72
    # engraved plaque: dark inside, shadowed top/left rim, lit bottom/right rim
    x0, x1, y0, y1 = int(0.07 * w), int(0.93 * w), int(0.13 * h), int(0.9 * h)
    plaque = lum[y0:y1, x0:x1]
    plaque[...] = 0.36 + 0.06 * (1 - np.linspace(0, 1, y1 - y0))[:, None] + 0 * plaque
    lum[y0:y0 + 2, x0:x1] = 0.18
    lum[y0:y1, x0:x0 + 2] = 0.2
    lum[y1 - 2:y1, x0:x1] = 1.0
    lum[y0:y1, x1 - 2:x1] = 0.9
    return _rgba(lum, np.ones((h, w)))


def podium_top(w=256, h=32, ss=4):
    """Top face of a step seen from the front: a trapezoid (narrower at the
    back), lighter toward the front edge."""
    W, H = w * ss, h * ss
    v = (np.arange(H) + 0.5)[:, None] / H  # 0 back .. 1 front edge
    u = (np.arange(W) + 0.5)[None, :] / W
    inset = 0.045 * (1 - v)
    inside = ((u >= inset) & (u <= 1 - inset)) * 1.0
    lum = 0.8 + 0.18 * v + 0.08 * np.exp(-((u - 0.5) / 0.3) ** 2) + 0 * u
    lum = np.where(v > 1 - 2.5 / h, 1.05, lum)  # bright front edge
    lum = np.where(v < 1.5 / h, 0.6, lum)  # back edge
    a = inside.reshape(h, ss, w, ss).mean(axis=(1, 3))
    l = lum.reshape(h, ss, w, ss).mean(axis=(1, 3))
    return _rgba(l, a)


def shadow(w=128, h=64):
    """Soft contact shadow (black, alpha falls off from the middle)."""
    x, y = np.meshgrid((np.arange(w) + 0.5) / w * 2 - 1, (np.arange(h) + 0.5) / h * 2 - 1)
    r = np.sqrt(x * x + y * y)
    a = np.exp(-(r / 0.55) ** 2 * 1.6) * np.clip((1 - r) / 0.15, 0, 1)
    return np.dstack([np.zeros((h, w, 3)), a])


def beam(size=256):
    """Stage spotlight: a round lamp a little below the top middle of the
    texture (LAMP_AT of its height), and a cone from it down to the bottom
    middle, so the texture can be rotated about its center."""
    x, y = grid(size)
    t = (1 - y) / 2  # 0 at the top .. 1 at the bottom
    lamp_at = 0.06
    half = 0.015 + 0.28 * np.clip(t - lamp_at, 0, None)
    cone = np.exp(-(x / half) ** 2 * 2.2)
    along = np.clip((t - lamp_at) / 0.1, 0, 1) * np.clip((1 - t) / 0.25, 0, 1) * (1 - 0.55 * t)
    d = np.sqrt((x / 0.07) ** 2 + ((t - lamp_at) / 0.035) ** 2)
    lamp = np.exp(-d * d * 1.5)
    return np.clip(cone * along + lamp, 0, 1)


def confetti(size=32):
    """A small paper flake with a fold line, white (tinted per piece)."""
    x, y = grid(size)
    a = ((np.abs(x) < 0.45) & (np.abs(y) < 0.8)) * 1.0
    lum = 0.85 + 0.15 * (x > 0) - 0.1 * (np.abs(x) < 0.04)
    return _rgba(lum, a)


TEXTURES = {
    "rays.tga": rays,
    "glow.tga": glow,
    "star.tga": star,
    "ring.tga": ring,
    "icon.tga": icon,
    "podium_front.tga": podium_front,
    "podium_top.tga": podium_top,
    "shadow.tga": shadow,
    "beam.tga": beam,
    "confetti.tga": confetti,
}


def main():
    os.makedirs(MEDIA, exist_ok=True)
    for name, fn in TEXTURES.items():
        write_tga(os.path.join(MEDIA, name), fn())
        print("wrote", os.path.join("BigPodium", "Media", name))


if __name__ == "__main__":
    main()
