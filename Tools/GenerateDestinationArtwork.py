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
OUTPUT = ROOT / "output/imagegen/destinations/bold-v2"
ART = runpy.run_path(str(ROOT / "Tools/DrawDestinationArtwork.py"))["ART"]

STYLE = """Use case: logo-brand. Asset: ONE exceptionally simple bold outline city pictogram for a native iOS app, displayed at only 32 pixels.
Subject: {subject}, {city}.
Essential silhouette: {simplification}
Design: a compact, iconic symbol, with the economy of a well-designed semibold UI symbol. ONE isolated subject. Front-facing or the simplest recognizable view. A few large geometric shapes, generous open counters. Rounded line caps and joins. Uniform HEAVY black strokes, 60 pixels thick on a 1024 pixel canvas, including every interior mark. Same weight everywhere, no delicate secondary lines. About 6-12 simple strokes in total; maximum THREE interior detail marks, only if needed for identity. Let the outline do the work. Interior gaps at least 70 pixels. Preserve the landmark's defining shape while radically reducing architectural detail. Centered, filling 78 percent of a square canvas, large clean margins. Pure black ink on a perfectly plain white background. White open interiors, no solid background shape.
Avoid: thin lines, architectural illustration, realistic detail, complex facade, repeated windows, roof tiles, brickwork, lattice, hatching, perspective depth, hairlines, ornamental flourishes, multiple landmarks, landscape, scenery, ground lines, clouds, sun, stars, people, text, letters, numbers, labels, border, enclosing badge, color, shadows, gradients, texture, mockup, contact sheet. Do not add tiny marks or decorative details. The result must stay unmistakably clear as a very small app icon."""

# The same subject inventory, reduced to the few features visible in a 40pt badge.
SIMPLIFICATION = {
    "tokyo": "Tokyo Tower: tapered four-foot tower, one broad observation deck, short antenna, one arch opening and just one cross brace. No lattice.",
    "osaka": "Osaka Castle: compact three-tier castle silhouette with three sweeping Japanese roofs and one doorway. No stone blocks, windows or roof tiles.",
    "kyoto": "ONE Fushimi Inari torii gate: two stout uprights, curved upper lintel and single lower crossbar. No corridor of receding gates.",
    "sapporo": "Sapporo Clock Tower: small gable-roof building with a central square clock turret. One large clock circle and two hands, no windows or siding.",
    "fukuoka": "ONE Hakata yatai food stall: little roof, two posts, broad counter and two simple stools. No wheels, utensils, bottles or menu.",
    "naha": "Shureimon, the Chinese-style Okinawan ceremonial gate, NOT a Japanese torii. TWO distinct broad tiled-roof silhouettes, each shaped as a shallow trapezoid with slightly upturned eaves, the upper roof narrower than the lower. FOUR clearly separated straight columns under the lower roof form three open passages. No lintel-only torii shape. Omit all tile pattern, plaque and ornament.",
    "seoul": "Gyeongbokgung gate: two wide curved Korean roof tiers above a single broad arched gateway. No windows, railing or stone pattern.",
    "busan": "Gwangan suspension bridge: two plain rectangular pylons, one sweeping suspension cable, straight deck and two hangers. No trusses, water or distant buildings.",
    "jeju": "Dol hareubang: rounded stone guardian with mushroom-shaped cap, two eyes, broad nose and two simple curved arms. No fingers or stone texture.",
    "beijing": "Forbidden City hall: one wide Chinese hipped roof with upturned tips, stout base and three plain columns. No stacked roofs, stairs, tiles or ornaments.",
    "shanghai": "Oriental Pearl Tower: two very large round observation spheres on one central shaft, two splayed legs and a short antenna. No windows, extra rings or lattice.",
    "guangzhou": "Canton Tower: distinctive slender hourglass body, broad top rim and straight antenna. At most two sweeping diagonal structural curves, no lattice mesh.",
    "shenzhen": "Ping An Finance Centre: tall tapered skyscraper with faceted pointed crown and just one vertical center division. No floors or windows.",
    "chengdu": "A friendly front-facing giant panda HEAD only: round head, two ears, two large eye patches with white eyes, tiny nose. No body, paws or bamboo.",
    "xian": "Xi'an gate: stout trapezoid city wall, one large arched opening and one small curved-roof gatehouse on top. No bricks, windows or repeated battlements.",
    "hangzhou": "ONE iconic Three Pools Mirroring the Moon stone pagoda: round belly with one circular opening, small curved cap, pointed finial and short foot. No pavilion, lake or multiple pagodas.",
    "chongqing": "ONE Hongya Cave stilt house: two compact curved roof tiers and three long visible stilts underneath. No cluster of houses, windows, balconies or diagonal braces.",
    "berlin": "Brandenburg Gate: a broad simple entablature on four columns, with a tiny abstract quadriga crest made from one broad shape. No horse details, stairs or side wings.",
    "munich": "Frauenkirche: two matching stout square towers topped by large onion domes, joined by a low central nave. No windows or brick texture.",
    "hamburg": "Elbphilharmonie: broad rectangular base topped by its distinctive sweeping peaked glass roof outline. One horizontal separation, no facade grid.",
    "frankfurt": "Romer: THREE joined stepped-gable house outlines, the middle tallest, one central arched door. No window grid or clocks.",
    "vienna": "Schonbrunn: one compact symmetrical palace facade with broad low wings, taller central pediment and one central arched door. No window rows, gardens or fountains.",
    "salzburg": "Hohensalzburg Fortress: one compact castle outline with two squat square towers and a central wall on a single sloping rock contour. No tiny buildings or windows.",
    "zurich": "Grossmunster: two stout square towers with rounded caps and a simple central roof connecting them. No river, bridge or surrounding houses.",
    "cologne": "Cologne Cathedral: twin sharply pointed spires above a broad shared facade, one large central Gothic doorway. No tracery, windows or flying buttresses.",
    "madrid": "Puerta de Alcala: one compact classical gate with three large open arches and a simple raised central pediment. No statues or decorative columns.",
    "barcelona": "Sagrada Familia: four tall tapered spires with rounded tips, two taller in the middle, rising from a single compact base with one doorway. No cranes, tracery or windows.",
    "seville": "Plaza de Espana: one shallow sweeping curved arcade with three broad arches and one square tower at either end. No water, bridge, tiles or tiny windows.",
    "valencia": "L'Hemisferic: a single large eye-shaped building profile with an arched upper shell and one curved interior rib. No reflections or repeating ribs.",
    "mexico-city": "Palacio de Bellas Artes: one prominent broad central dome above a low symmetrical body and single central entrance. No statues, columns or window rows.",
    "cancun": "El Rey Maya ruins: ONE simple stepped Maya pyramid with three broad terraces and a small square temple at the summit. No palm, vegetation or staircase stripes.",
    "buenos-aires": "Obelisco: one tall slender obelisk outline with a pyramidal tip and one short vertical facet line. No surroundings or pedestal decoration.",
    "lima": "Lima Cathedral: two compact square bell towers with small caps and a single curved central facade, one central door. No ornate carving or window rows.",
    "santiago": "San Cristobal: simple upright Virgin Mary statue with a broad robe silhouette on one low rounded hill contour. No face, fingers, rays or landscape.",
    "bogota": "Monserrate sanctuary: tiny church silhouette with two square bell towers on one steep rounded hill contour. One door, no windows or vegetation.",
    "cartagena": "Cartagena Clock Tower: one tall square tower with pointed roof, one large clock circle and a single open arch at its foot. No surrounding walls or windows.",
    "havana": "ONE classic 1950s Havana car seen from the side: long rounded hood and trunk, curved cabin, two large wheels and one window division. No street or chrome details.",
    "san-juan": "El Morro sentry box: stout rounded turret with a domed cap, one narrow slit and a short projecting support. No ocean or fortress panorama.",
    "london": "Tower Bridge: two stout matching towers with pointed caps, one high horizontal walkway, one lower deck and two simple outer suspension curves. No windows or trusses.",
    "new-york": "Statue of Liberty: compact bust with three bold crown rays and one raised arm holding a large simple torch. No face, robe folds, tablet details or pedestal.",
    "los-angeles": "Griffith Observatory: one broad central dome above a low symmetrical building with two small end domes. One doorway. No stars, telescope, skyline or lettering.",
    "san-francisco": "Golden Gate Bridge: two tall rectangular towers with one crossbar each, one sweeping main cable and a flat deck. No trusses, water or tiny suspenders.",
    "edinburgh": "Edinburgh Castle: compact connected fortress with one rounded tower and one square tower atop a simple sloping rock outline. No masonry or panorama.",
    "dublin": "Irish harp: strong sweeping triangular harp frame with exactly THREE widely spaced strings. No carved scrollwork.",
    "toronto": "CN Tower: single tapering shaft, one broad saucer observation deck and short straight needle. No rings, windows or skyline.",
    "vancouver": "Canada Place: THREE large overlapping triangular sail outlines sharing one short straight base. No rigging, water or skyline.",
    "sydney": "Sydney Opera House: THREE large expressive overlapping shell shapes on one short low base. No shell ribs, windows, water or reflections.",
    "melbourne": "Melbourne W-class tram seen head-on: broad rounded rectangular body, two large front windows, one headlamp and simple roof trolley pole. No numbers or destination sign.",
    "singapore": "Marina Bay Sands: three stout upright towers supporting one long curved boat-shaped skypark. No facade grids, windows, water or trees.",
    "moscow": "Saint Basil's: THREE large onion domes of different heights over three stout connected stems. One central doorway. No patterns, stripes, stars or tiny domes.",
    "saint-petersburg": "Winter Palace: one symmetrical low facade with a taller central pediment, short side wings and one large arched entrance. No statues, columns or window rows.",
    "kazan": "Kul Sharif Mosque: one broad pointed central dome between TWO tall slim minarets with pointed caps. One entrance, no ornament or multiple smaller towers.",
    "sochi": "Sochi Maritime Terminal: compact stepped central tower, long clear spire and two low wings. One central arch. No statues, windows or water.",
    "vladivostok": "Golden Bridge: two V-shaped pylons, flat deck and just TWO wide diagonal stay cables. No suspension curves, tiny cables or water.",
    "paris": "Eiffel Tower: broad tapering curved legs, one large open arch, two horizontal platforms and a short pointed top. No lattice or diagonal mesh.",
    "rome": "Colosseum: one curved elliptical amphitheatre outline with a sloping broken top, one horizontal band and just THREE broad arch openings. No multiple rows of windows or masonry.",
    "amsterdam": "TWO adjacent Amsterdam canal houses, one stepped gable and one bell gable, each with one tall doorway. No canal, bicycle, bridge or window grid.",
    "prague": "Charles Bridge tower: one compact square gate tower with a steep hipped roof and one large Gothic arch. No statues, bridge panorama or masonry.",
    "lisbon": "Lisbon vintage tram seen in a simple three-quarter view: compact rounded carriage, one broad windshield, one side window and a short roof trolley arm. No route number, signs or street.",
    "athens": "Parthenon: one broad triangular pediment supported by FOUR stout columns on one simple flat base. No fluting, broken stones or stairs.",
    "istanbul": "Hagia Sophia: one broad low dome over a compact body, one small half-dome and two plain slender minarets. No windows, ornament or extra domes.",
    "dubai": "Burj Khalifa: distinctive asymmetrical telescoping stepped silhouette with three major setbacks and a needle tip. One short vertical facet, no floor lines or windows.",
    "bangkok": "Wat Arun: ONE tall central prang outline built from three broad tapering tiers with a pointed top and simple wide base. No small surrounding towers, carvings or patterns.",
    "bali": "Balinese split gate: two symmetrical stepped stone halves facing across a wide vertical gap. Three broad steps per half, no carvings or temple behind.",
    "honolulu": "ONE upright surfboard with a softly pointed top and rounded bottom, a single sweeping wave curl crossing its lower third. No mountain panorama, stripes or flowers.",
}

SUBJECT_OVERRIDES = {
    "los-angeles": ("Griffith Observatory", "格里菲斯天文台"),
    "cancun": ("El Rey Maya pyramid", "雷伊玛雅遗址金字塔"),
    "honolulu": ("Hawaiian surfboard and wave", "夏威夷冲浪板与海浪"),
}


def cli(*args):
    result = subprocess.run(["replicate", "--json", *args], capture_output=True, text=True)
    envelope = json.loads(result.stdout)
    if not envelope.get("ok"):
        raise RuntimeError(json.dumps(envelope.get("error"), ensure_ascii=False))
    return envelope


def generate(key, quality, live, output):
    folder = output / "sources" / key
    folder.mkdir(parents=True, exist_ok=True)
    input_path = folder / "input.json"
    inputs = dict(prompt=STYLE.format(subject=SUBJECT_OVERRIDES.get(key, ART[key])[0],
                                     city=key.replace("-", " ").title(), simplification=SIMPLIFICATION[key]),
                  quality=quality, aspect_ratio="1:1", background="opaque",
                  output_format="png", number_of_images=1)
    if input_path.exists():
        if json.loads(input_path.read_text()) != inputs:
            raise ValueError(f"{key}: saved input differs; use a new --output directory for a new revision")
    else:
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
    parser.add_argument("--output", type=Path, default=OUTPUT, help="Separate revision directory; never overwrite earlier generations")
    args = parser.parse_args()
    cities = args.cities or list(ART)
    if set(cities) - ART.keys():
        parser.error(f"Unknown cities: {set(cities) - ART.keys()}")
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        list(pool.map(lambda key: generate(key, args.quality, args.generate, args.output), cities))


if __name__ == "__main__":
    main()
