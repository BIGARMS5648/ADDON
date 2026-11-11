#!/usr/bin/env python3
"""Generate the textures used by Podium.

Light textures (rays, glow, star, ring) are white with a shaped alpha channel;
the addon tints them gold with SetVertexColor() and draws them with the ADD
blend mode. The icon is a colored podium. All are uncompressed 32-bit TGA.

Usage:
    python3 tools/make_podium_media.py      # writes Podium/Media/*.tga
"""

import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_textures import glow, grid, ray, ring, star, write_tga  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEDIA = os.path.join(ROOT, "Podium", "Media")


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


TEXTURES = {
    "rays.tga": rays,
    "glow.tga": glow,
    "star.tga": star,
    "ring.tga": ring,
    "icon.tga": icon,
}


def main():
    os.makedirs(MEDIA, exist_ok=True)
    for name, fn in TEXTURES.items():
        write_tga(os.path.join(MEDIA, name), fn())
        print("wrote", os.path.join("Podium", "Media", name))


if __name__ == "__main__":
    main()
