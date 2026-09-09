#!/usr/bin/env python3
"""Generate city line-art sources through the user's local Replicate CLI.

Paid generation is explicit: `--generate`; the default only writes input files.
Existing predictions are resumed, never silently submitted a second time.
No API credentials are read or persisted by this script.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import runpy
import subprocess

ROOT = Path(__file__).resolve().parents[1]
MODEL = "openai/gpt-image-2.5-flare"
OUTPUT = ROOT / "output/imagegen/destinations"
ART = runpy.run_path(str(ROOT / "Tools/DrawDestinationArtwork.py"))["ART"]

STYLE = """Use case: logo-brand. Asset: a single refined travel landmark outline icon for Prompti, a warm, calm native iOS language-learning app.
Subject: {subject}, {city}. Depict the actual distinctive local landmark or representative object with recognizable, accurate proportions.
Style: polished architectural line icon, careful geometric construction, smooth round caps and joins, understated friendly precision. Mostly front elevation; use a slight three-quarter view only when essential to recognize the subject. One subject only, centered, occupying 80 percent of a square canvas, with generous clear margins. Pure black outlines on a perfectly plain white background. All enclosed areas remain white. Consistent confident primary contours about 24 pixels and secondary structural lines about 18 pixels at 1024px. Include selected meaningful local details, about 20-35 clear structural strokes, with balanced open negative space. It must read at 40-64px. Simplify repeating windows and lattice into a few well-spaced marks, never dense hatching.
No words, letters, numerals, labels, logo, border, badge, enclosing circle, extra scenery, skyline, clouds, stars, people, airplane, map pin, shadows, gradients, color fills, texture, sketch marks or 3D render. This is finished standalone outline icon artwork, not a mockup or contact sheet."""


def cli(*args):
    result = subprocess.run(["replicate", "--json", *args], capture_output=True, text=True)
    envelope = json.loads(result.stdout)
    if not envelope.get("ok"):
        raise RuntimeError(json.dumps(envelope.get("error"), ensure_ascii=False))
    return envelope


def generate(key, quality, live):
    folder = OUTPUT / "sources" / key
    folder.mkdir(parents=True, exist_ok=True)
    input_path = folder / "input.json"
    if not input_path.exists():
        inputs = dict(prompt=STYLE.format(subject=ART[key][0], city=key.replace("-", " ").title()),
                      quality=quality, aspect_ratio="1:1", background="opaque",
                      output_format="png", number_of_images=1)
        input_path.write_text(json.dumps(inputs, ensure_ascii=False, indent=2) + "\n")
    if not live:
        print(f"Prepared {key}", flush=True)
        return
    prediction_path = folder / "prediction.json"
    if prediction_path.exists():
        result = json.loads(prediction_path.read_text())
        if (result["data"]["status"] == "succeeded" and result.get("artifacts")
                and all((folder / Path(item["path"]).name).exists() for item in result["artifacts"])):
            print(f"Already saved {key}", flush=True)
            return
    else:
        cli("run", MODEL, "--input-json", str(input_path), "--dry-run")
        result = cli("run", MODEL, "--input-json", str(input_path), "--async")
        prediction_path.write_text(json.dumps(result, indent=2) + "\n")
    identifier = result["data"]["id"]
    if result["data"]["status"] in ("failed", "canceled"):
        raise RuntimeError(f"{key}: prediction {identifier} {result['data']['status']}; review before retry")
    result = cli("predictions", "wait", identifier, "--timeout", "10m", "--output", str(folder))
    prediction_path.write_text(json.dumps(result, indent=2) + "\n")
    if result["data"]["status"] != "succeeded" or not result.get("artifacts"):
        raise RuntimeError(f"{key}: no successful image output")
    print(f"Saved {key}: {identifier}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cities", nargs="*", help="Stable city IDs; defaults to all 65")
    parser.add_argument("--quality", choices=["low", "medium"], default="medium")
    parser.add_argument("--generate", action="store_true", help="Create paid predictions and download results")
    parser.add_argument("--jobs", type=int, choices=[1, 2, 3], default=2)
    args = parser.parse_args()
    cities = args.cities or list(ART)
    if set(cities) - ART.keys():
        parser.error(f"Unknown cities: {set(cities) - ART.keys()}")
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(lambda key: generate(key, args.quality, args.generate), cities))


if __name__ == "__main__":
    main()
