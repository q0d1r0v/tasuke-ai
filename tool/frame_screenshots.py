#!/usr/bin/env python3
"""Frames the iPhone captures for the App Store listing.

    python3 tool/frame_screenshots.py <captures dir> <output dir>

Input: the PNGs from the "iOS Screenshots" workflow artifact (1320x2868).
Output: one 1284x2778 PNG per capture — the 6.5" size App Store Connect asks
for — with a caption over the brand gradient and the capture below it.

Captions come from store/store-listing.txt and must stay true to it: the
listing's honesty rules apply to screenshots too.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "assets/fonts/Inter-Variable.ttf"

W, H = 1284, 2778
# TasukeGradients.brand, sampled from the app icon's corners.
TOP, BOTTOM = (79, 166, 254), (43, 117, 250)

CAPTIONS = {
    "01_home_today": "Speak a sentence.\nGet tasks.",
    "02_upcoming": "Real dates,\nunderstood.",
    "03_completed": "Everything stays\non your phone.",
    "04_stats": "See your week\nat a glance.",
    "05_settings": "No account.\nNo tracking.",
}


def font(size: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), size)
    try:
        f.set_variation_by_name("Bold")
    except (OSError, ValueError):
        pass
    return f


def background() -> Image.Image:
    grad = Image.new("RGB", (1, H))
    for y in range(H):
        t = y / (H - 1)
        grad.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
    return grad.resize((W, H))


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *im.size), radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def frame(capture: Path, caption: str) -> Image.Image:
    canvas = background().convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    title = font(104)
    draw.multiline_text(
        (W // 2, 250), caption, font=title, fill="white", anchor="mm", align="center", spacing=18
    )

    # The capture, scaled to leave the caption room, bleeding off the bottom
    # edge the way a phone held up to the camera would.
    shot = Image.open(capture).convert("RGB")
    sw = 1060
    sh = round(shot.height * sw / shot.width)
    shot = rounded(shot.resize((sw, sh), Image.LANCZOS), 72)
    x, y = (W - sw) // 2, 470

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x, y + 24, x + sw, y + sh + 24), 72, fill=(10, 40, 110, 110)
    )
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(40)))
    canvas.alpha_composite(shot, (x, y))
    return canvas.convert("RGB")


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    dst.mkdir(parents=True, exist_ok=True)
    for capture in sorted(src.glob("*.png")):
        caption = CAPTIONS.get(capture.stem)
        if caption is None:
            print(f"skip {capture.name}: no caption")
            continue
        out = dst / capture.name
        frame(capture, caption).save(out, optimize=True)
        print(f"wrote {out}")


if __name__ == "__main__":
    main()
