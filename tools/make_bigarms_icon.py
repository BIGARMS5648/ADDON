#!/usr/bin/env python3
"""Draw the BIGARMS minimap / addon list icon (a flexed arm) as a 64x64 TGA."""

import os
import struct

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "BIGARMS", "Media", "icon.tga")


def write_tga(path, image):
    image = image.convert("RGBA")
    width, height = image.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    r, g, b, a = image.split()
    data = Image.merge("RGBA", (b, g, r, a)).tobytes()
    with open(path, "wb") as f:
        f.write(header + data)


def draw(size=256):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size / 64.0
    # background disc
    d.ellipse((2 * s, 2 * s, 62 * s, 62 * s), fill=(40, 22, 10, 255))
    d.ellipse((4 * s, 4 * s, 60 * s, 60 * s), fill=(255, 125, 10, 255))
    d.ellipse((7 * s, 7 * s, 57 * s, 57 * s), fill=(60, 30, 12, 255))
    skin = (255, 205, 150, 255)
    dark = (200, 140, 90, 255)
    # upper arm (horizontal) and forearm (vertical) of a flexing arm
    d.rounded_rectangle((12 * s, 34 * s, 42 * s, 48 * s), radius=7 * s, fill=skin)
    d.rounded_rectangle((36 * s, 14 * s, 50 * s, 46 * s), radius=7 * s, fill=skin)
    # bicep bulge
    d.ellipse((17 * s, 22 * s, 39 * s, 42 * s), fill=skin)
    d.ellipse((21 * s, 25 * s, 33 * s, 34 * s), fill=(255, 230, 200, 255))
    # fist
    d.ellipse((34 * s, 9 * s, 52 * s, 25 * s), fill=skin)
    d.line((38 * s, 13 * s, 48 * s, 13 * s), fill=dark, width=int(2 * s))
    d.line((38 * s, 17 * s, 48 * s, 17 * s), fill=dark, width=int(2 * s))
    # shading
    d.arc((12 * s, 34 * s, 42 * s, 48 * s), 90, 270, fill=dark, width=int(2 * s))
    return img.resize((64, 64), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    write_tga(OUT, draw())
    print("wrote", OUT)
