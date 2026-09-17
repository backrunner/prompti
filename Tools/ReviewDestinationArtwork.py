#!/usr/bin/env python3
"""Render SVG review sheets at large and actual DestinationArtwork badge sizes.

Requires Pillow and CairoSVG (on macOS, DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib).
These are asset previews, never App screenshots. No network/model calls.
"""
import argparse
from io import BytesIO
import json
from pathlib import Path

import cairosvg
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Tools/DestinationArtwork"
BEFORE = ROOT / "output/imagegen/destinations/bold-v2/before"
PALETTES = {
    "light": ("#f5f6f0", "#eaf0e6", "#08765d", "#173d33"),
    "dark": ("#101c18", "#263b32", "#a3f2ce", "#edf4eb"),
}


def artwork(path, size, ink):
    svg = path.read_text().replace('fill="#000"', f'fill="{ink}"')
    return Image.open(BytesIO(cairosvg.svg2png(bytestring=svg.encode(),
                                              output_width=size, output_height=size))).convert("RGBA")


def badge(path, size, theme="light"):
    _, raised, ink, _ = PALETTES[theme]
    result = Image.new("RGBA", (size, size))
    ImageDraw.Draw(result).rounded_rectangle((0, 0, size-1, size-1), radius=14, fill=raised)
    # DestinationArtwork adds 8% padding on each side inside its fixed frame.
    drawing = artwork(path, round(size * .84), ink)
    result.alpha_composite(drawing, ((size-drawing.width)//2, (size-drawing.height)//2))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cities", nargs="*")
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, default=ROOT / "Documentation/Brand/DestinationArtwork/Review")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    keys = args.cities or [entry["id"] for entry in json.loads((SOURCE / "manifest.json").read_text())["destinations"]]
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 17)
    small = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 12)
    for offset in range(0, len(keys), 18):
        page = keys[offset:offset+18]
        canvas = Image.new("RGB", (1200, 840), PALETTES["light"][0])
        draw = ImageDraw.Draw(canvas)
        for index, key in enumerate(page):
            x, y = (index % 6)*200, (index // 6)*280
            path = args.source / f"{key}.svg"
            large = artwork(path, 156, PALETTES["light"][2])
            canvas.paste(large, (x+22, y+8), large)
            draw.text((x+12, y+168), key, font=font, fill=PALETTES["light"][3])
            for j, (size, theme) in enumerate(((40, "light"), (40, "dark"), (64, "light"))):
                icon = badge(path, size, theme)
                canvas.paste(icon, (x+12+j*58, y+198), icon)
                draw.text((x+12+j*58, y+263), f"{size}pt", font=small, fill=PALETTES["light"][3])
        canvas.save(args.output / f"sheet-{offset//18+1}.png")

    samples = [key for key in ("tokyo", "osaka", "chengdu", "london", "sydney", "moscow") if key in keys]
    if samples:
        canvas = Image.new("RGB", (1200, 580), PALETTES["light"][0])
        draw = ImageDraw.Draw(canvas)
        for i, key in enumerate(samples):
            x = i*200
            draw.text((x+15, 15), key, font=font, fill=PALETTES["light"][3])
            for j, (source, label) in enumerate(((BEFORE, "Before"), (args.source, "Bold / simple"))):
                path=source/f"{key}.svg"
                icon = artwork(path, 136, PALETTES["light"][2])
                y=55+j*255
                canvas.paste(icon, (x+32, y), icon)
                draw.text((x+15, y+140), label, font=font, fill=PALETTES["light"][3])
                for k, theme in enumerate(("light", "dark")):
                    icon=badge(path, 40, theme)
                    canvas.paste(icon, (x+35+k*75, y+178), icon)
                draw.text((x+40, y+223), "40pt badges", font=small, fill=PALETTES["light"][3])
        canvas.save(args.output / "Comparison.png")
    print(f"Rendered {len(keys)} SVGs; previews are not App screenshots.")


if __name__ == "__main__":
    main()
