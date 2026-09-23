#!/usr/bin/env python3
"""Frames the iPhone captures for the store listings, and draws the Play
feature graphic.

    python3 tool/frame_screenshots.py <captures dir> <output dir>

Input: the PNGs from the "iOS Screenshots" workflow artifact (1320x2868). The
captures are the Flutter surface only — no status bar — so the same set serves
both stores.

Output, under <output dir>:
  app-store/  1284x2778, the 6.5" size App Store Connect asks for
  play/       1080x1920; Play rejects anything longer than 2:1
  play/feature_graphic.png  1024x500

Captions come from store/store-listing.txt and must stay true to it: the
listing's honesty rules apply to screenshots too.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "assets/fonts/Inter-Variable.ttf"
ICON = ROOT / "assets/images/icon.png"

# TasukeGradients.brand, sampled from the app icon's corners.
TOP, BOTTOM = (79, 166, 254), (43, 117, 250)

SIZES = {"app-store": (1284, 2778), "play": (1080, 1920)}

CAPTIONS = {
    "01_home_today": "Speak a sentence.\nGet tasks.",
    "02_upcoming": "Real dates,\nunderstood.",
    "03_completed": "Everything stays\non your phone.",
    "04_stats": "See your week\nat a glance.",
    "05_settings": "No account.\nNo tracking.",
}


def font(size: int, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONT), size)
    try:
        f.set_variation_by_name(weight)
    except (OSError, ValueError):
        pass
    return f


def gradient(w: int, h: int, vertical: bool = True) -> Image.Image:
    n = h if vertical else w
    strip = Image.new("RGB", (1, n) if vertical else (n, 1))
    for i in range(n):
        t = i / (n - 1)
        px = tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM))
        strip.putpixel((0, i) if vertical else (i, 0), px)
    return strip.resize((w, h))


def rounded(im: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *im.size), radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def frame(capture: Path, caption: str, w: int, h: int) -> Image.Image:
    canvas = gradient(w, h).convert("RGBA")
    ImageDraw.Draw(canvas).multiline_text(
        (w // 2, round(h * 0.09)),
        caption,
        font=font(round(w * 0.081)),
        fill="white",
        anchor="mm",
        align="center",
        spacing=round(w * 0.014),
    )

    # The capture sits below the caption and runs to the bottom edge; on the
    # squatter Play canvas that makes it narrower, never cropped.
    shot = Image.open(capture).convert("RGB")
    top = round(h * 0.17)
    sw = min(round(w * 0.825), round((h - top) * shot.width / shot.height))
    sh = round(shot.height * sw / shot.width)
    radius = round(sw * 0.068)
    shot = rounded(shot.resize((sw, sh), Image.LANCZOS), radius)
    x = (w - sw) // 2

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    lift = round(w * 0.019)
    ImageDraw.Draw(shadow).rounded_rectangle(
        (x, top + lift, x + sw, top + sh + lift), radius, fill=(10, 40, 110, 110)
    )
    canvas = Image.alpha_composite(
        canvas, shadow.filter(ImageFilter.GaussianBlur(round(w * 0.031)))
    )
    canvas.alpha_composite(shot, (x, top))
    return canvas.convert("RGB")


def feature_graphic() -> Image.Image:
    w, h = 1024, 500
    canvas = gradient(w, h, vertical=False).convert("RGBA")

    # The icon is the full-bleed tile; round it here, since this is not an
    # icon slot and nothing will mask it.
    icon = rounded(Image.open(ICON).convert("RGB").resize((220, 220), Image.LANCZOS), 50)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((90, 152, 310, 372), 50, fill=(10, 40, 110, 120))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(18)))
    # A white ring separates the blue tile from the blue background.
    ring = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle((84, 134, 316, 366), 56, fill=(255, 255, 255, 90))
    canvas = Image.alpha_composite(canvas, ring)
    canvas.alpha_composite(icon, (90, 140))

    draw = ImageDraw.Draw(canvas)
    draw.text((370, 200), "Tasuke AI", font=font(92), fill="white", anchor="ls")
    draw.text(
        (372, 272), "Speak it. It becomes a task.", font=font(40, "Medium"), fill="white", anchor="ls"
    )
    draw.text(
        (372, 330),
        "On-device · Offline · No account",
        font=font(30, "Medium"),
        fill=(225, 238, 255),
        anchor="ls",
    )
    return canvas.convert("RGB")


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    for store, (w, h) in SIZES.items():
        (dst / store).mkdir(parents=True, exist_ok=True)
        for capture in sorted(src.glob("*.png")):
            caption = CAPTIONS.get(capture.stem)
            if caption is None:
                print(f"skip {capture.name}: no caption")
                continue
            out = dst / store / capture.name
            frame(capture, caption, w, h).save(out, optimize=True)
            print(f"wrote {out}")
    out = dst / "play" / "feature_graphic.png"
    feature_graphic().save(out, optimize=True)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
