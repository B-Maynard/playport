#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Render app/Icon/AppIcon-source.png to the two committed 1024 px PNGs that xtool.yml's
# iconPath names: AppIcon-dev.png (with the dev badge) for the dev app and AppIcon.png
# (without it) for the release app. The source is the artwork as supplied: a rounded
# square with transparent corners on a black surround. iOS applies its own rounded mask
# to a full-bleed square, so the artwork is centred on a navy square of its own colour and
# the corners become that navy: no transparency reaches the icon (App Store rule for icons).
#
#   python3 app/Icon/render.py        # run after replacing AppIcon-source.png, then commit the PNGs
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
SOURCE = HERE / "AppIcon-source.png"
SIZE = 1024
NAVY = (0x06, 0x1E, 0x49)        # the artwork's background
LIGHT = (0x92, 0xCD, 0xFC)       # the artwork's glyph colour, also the badge
BADGE_TEXT = NAVY


def artwork() -> Image.Image:
    src = Image.open(SOURCE).convert("RGBA")
    alpha = src.split()[3].point(lambda v: 255 if v > 128 else 0)
    left, top, right, bottom = alpha.getbbox()
    side = max(right - left, bottom - top)
    cx, cy = (left + right) // 2, (top + bottom) // 2
    square = src.crop((cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side))
    canvas = Image.new("RGB", (side, side), NAVY)
    canvas.paste(square, (0, 0), square)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def dev_badge(icon: Image.Image) -> Image.Image:
    """The dev variant's pill, at the bottom centre as the old icon had it, labelled 'dev'."""
    out = icon.copy()
    draw = ImageDraw.Draw(out)
    draw.rounded_rectangle((396, 894, 628, 970), radius=38, fill=LIGHT)
    text = "dev"
    try:
        from PIL import ImageFont
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", 46)
    except OSError:
        from PIL import ImageFont
        font = ImageFont.load_default(size=46)
    x0, y0, x1, y1 = draw.textbbox((0, 0), text, font=font)
    draw.text((512 - (x1 - x0) / 2 - x0, 932 - (y1 - y0) / 2 - y0), text, font=font, fill=BADGE_TEXT)
    return out


def main() -> None:
    release = artwork()
    release.save(HERE / "AppIcon.png", optimize=True)
    dev_badge(release).save(HERE / "AppIcon-dev.png", optimize=True)
    print("wrote", HERE / "AppIcon.png", "and", HERE / "AppIcon-dev.png")


if __name__ == "__main__":
    main()
