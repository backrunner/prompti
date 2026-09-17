#!/usr/bin/env python3
"""Convert saved Replicate line-art PNGs into transparent, editable SVG paths.

Requires Pillow and potrace 1.16. No network or model calls are made.
The original PNGs and inputs stay in output/imagegen/destinations/bold-v2/sources.
"""
import argparse
import hashlib
import html
import json
from pathlib import Path
import re
import runpy
import subprocess
import tempfile
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "output/imagegen/destinations/bold-v2/sources"
SOURCE = ROOT / "Tools/DestinationArtwork"


def vectorize(image_path, subject):
    image = Image.open(image_path).convert("RGBA")
    white = Image.new("RGBA", image.size, "white")
    gray = Image.alpha_composite(white, image).convert("L")
    # Remove compression/background texture, retain only deliberate dark ink.
    ink = gray.point(lambda value: 255 if value < 170 else 0)
    bbox = ink.getbbox()
    if not bbox:
        raise ValueError(f"Empty image: {image_path}")
    if bbox[0] == 0 or bbox[1] == 0 or bbox[2] == gray.width or bbox[3] == gray.height:
        raise ValueError(f"Artwork touches the source boundary: {image_path}")
    cropped = gray.crop(bbox)
    scale = 896 / max(cropped.size)
    cropped = cropped.resize((round(cropped.width * scale), round(cropped.height * scale)), Image.Resampling.LANCZOS)
    normalized = Image.new("L", (1024, 1024), 255)
    normalized.paste(cropped, ((1024 - cropped.width) // 2, (1024 - cropped.height) // 2))
    bitmap = normalized.filter(ImageFilter.MedianFilter(3)).point(lambda value: 0 if value < 170 else 255, "1")
    with tempfile.TemporaryDirectory(prefix="prompti-trace-") as temp:
        pbm, svg = Path(temp) / "source.pbm", Path(temp) / "trace.svg"
        bitmap.save(pbm)
        subprocess.run(["potrace", str(pbm), "--svg", "--flat", "--turdsize", "12",
                        "--alphamax", "1", "--opttolerance", "0.15", "--output", str(svg)], check=True)
        traced = svg.read_text()
    body = traced[traced.index("<g "):traced.rindex("</svg>")].strip()
    body = re.sub(r"\s+", " ", body).replace('fill="#000000"', 'fill="#000"')
    # Contour fills describe the ink only; all counters and the canvas are transparent.
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">'
            f'<title>{html.escape(subject)}</title><g transform="scale(0.0625)">{body}</g></svg>\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cities", nargs="*")
    parser.add_argument("--raw", type=Path, default=RAW)
    parser.add_argument("--output", type=Path, default=SOURCE)
    args = parser.parse_args()
    args.raw = args.raw.resolve()
    args.output = args.output.resolve()
    catalog = json.loads((ROOT / "Documentation/Brand/DestinationArtwork/manifest.json").read_text())
    overrides = runpy.run_path(str(ROOT / "Tools/GenerateDestinationArtwork.py"))["SUBJECT_OVERRIDES"]
    args.output.mkdir(parents=True, exist_ok=True)
    entries = []
    for entry in catalog["destinations"]:
        key = entry["id"]
        if args.cities and key not in args.cities:
            continue
        prediction = json.loads((args.raw / key / "prediction.json").read_text())
        if prediction["data"]["status"] != "succeeded":
            raise ValueError(f"Unsuccessful generation: {key}")
        # Basename makes the checked-in generation record portable across checkouts.
        original = args.raw / key / Path(prediction["artifacts"][0]["path"]).name
        subject, subject_zh = overrides.get(key, (entry["subject"], entry["subject_zh"]))
        svg = vectorize(original, subject)
        (args.output / f"{key}.svg").write_text(svg)
        entries.append(dict(id=key, subject=subject, subject_zh=subject_zh,
                            source=str((args.output / f"{key}.svg").relative_to(ROOT)),
                            original=str(original.relative_to(ROOT)),
                            input=str((args.raw / key / "input.json").relative_to(ROOT)),
                            prediction_id=prediction["data"]["id"],
                            model=prediction["data"]["model"], version=prediction["data"]["version"],
                            quality=prediction["data"]["input"]["quality"],
                            created_at=prediction["data"]["created_at"],
                            original_sha256=hashlib.sha256(original.read_bytes()).hexdigest(),
                            svg_sha256=hashlib.sha256(svg.encode()).hexdigest()))
        print(f"Prepared {key}")
    if not args.cities:
        (args.output / "manifest.json").write_text(json.dumps(dict(
            model="openai/gpt-image-2.5-flare", generation="Tools/GenerateDestinationArtwork.py",
            preparation="Tools/PrepareDestinationArtwork.py", viewBox="0 0 64 64",
            provenance="AI-generated bold minimal pictograms; locally thresholded, normalized and traced with potrace 1.16.",
            destinations=entries), ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    main()
