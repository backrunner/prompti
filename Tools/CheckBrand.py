#!/usr/bin/env python3
"""Check the documented brand contract with Python's standard library.

Run from any directory. This catches resource and style drift; it is not a visual test.
"""
from pathlib import Path
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
errors = []


def check(condition, message):
    if not condition:
        errors.append(message)


theme = (ROOT / "Prompti/DesignSystem/PromptiTheme.swift").read_text()
roles = {
    name: (int(light, 16), int(dark, 16))
    for name, light, dark in re.findall(
        r"static let (prompt\w+) = adaptive\(light: 0x([\dA-F]+), dark: 0x([\dA-F]+)\)", theme
    )
}

# Keep the human-readable contract aligned with the runtime palette.
guidelines = (ROOT / ".agents/13-brand-and-ui-guidelines.md").read_text()
for line in guidelines.splitlines():
    if not line.startswith("| `prompt"):
        continue
    columns = line.split("|")
    name = re.search(r"`(prompt\w+)`", columns[1]).group(1)
    light = re.findall(r"#([\dA-F]{6})", columns[2])
    dark = re.findall(r"#([\dA-F]{6})", columns[3])
    check(len(light) == len(dark) and len(light) in (1, 2),
          f"Invalid documented palette row: {name}")
    for index, (light_hex, dark_hex) in enumerate(zip(light, dark)):
        role = name if index == 0 else name + "Surface"
        check(roles.get(role) == (int(light_hex, 16), int(dark_hex, 16)),
              f"Documented palette differs from PromptiTheme: {role}")


def luminance(value):
    rgb = [(value >> shift & 255) / 255 for shift in (16, 8, 0)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in rgb]
    return sum(v * weight for v, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def contrast(a, b):
    a, b = sorted((luminance(a), luminance(b)))
    return (b + 0.05) / (a + 0.05)


pairs = [("promptOnAction", "promptAction")]
pairs += [(fg, bg) for fg in ("promptText", "promptMuted", "promptAction")
          for bg in ("promptCanvas", "promptSurface", "promptSurfaceRaised", "promptHero")]
pairs += [("promptText", "promptSelection")]
pairs += [(f"prompt{state}", f"prompt{state}Surface") for state in ("Success", "Warning", "Error")]
minimum = 100.0
for fg, bg in pairs:
    check(fg in roles and bg in roles, f"Missing semantic pair: {fg}/{bg}")
    if fg not in roles or bg not in roles:
        continue
    for appearance in (0, 1):
        ratio = contrast(roles[fg][appearance], roles[bg][appearance])
        minimum = min(minimum, ratio)
        check(ratio >= 4.5, f"Text contrast below 4.5: {fg}/{bg}, appearance {appearance}: {ratio:.2f}")

accent = json.loads((ROOT / "Prompti/Assets.xcassets/AccentColor.colorset/Contents.json").read_text())
for entry in accent["colors"]:
    appearance = 1 if entry.get("appearances") else 0
    components = entry["color"]["components"]
    rgb = tuple(round(float(components[channel]) * 255) for channel in ("red", "green", "blue"))
    check(rgb == tuple(roles["promptAction"][appearance] >> shift & 255 for shift in (16, 8, 0)),
          "AccentColor and promptAction have drifted")

for folder in ("Prompti/Features", "Prompti/App", "Prompti/DesignSystem"):
    for path in (ROOT / folder).rglob("*.swift"):
        source = path.read_text()
        check(not re.search(r"\b(promptSky|promptSun|promptCoral|promptMintDeep|FlightRouteVisual|LandingJourney)\b", source),
              f"Retired visual role in {path.relative_to(ROOT)}")
        check(not re.search(r'"airplane(?:\.[\w.]+)?"', source),
              f"Retired airplane brand treatment in {path.relative_to(ROOT)}")
        if path.name != "PromptiTheme.swift":
            check(not re.search(r"(?:UI)?Color\s*\(\s*(?:red:|hex:|\.sRGB|\.displayP3)", source),
                  f"Hard-coded page color in {path.relative_to(ROOT)}; define a semantic role")
        check(".foregroundStyle(.secondary)" not in source,
              f"Use promptMuted for readable secondary text over branded foregrounds: {path.relative_to(ROOT)}")
        check(not re.search(r"\bColor\.(?:red|green|blue|orange|yellow|purple|white)\b|"
                            r"\.(?:foregroundStyle|tint|background)\(\.(?:red|green|blue|orange|yellow|purple|white)\b", source),
              f"Use a paired semantic foreground/background role: {path.relative_to(ROOT)}")

ns = {"svg": "http://www.w3.org/2000/svg"}
source_mark = ROOT / "Prompti/AppIcon.icon/Assets/Prompti.svg"
contour = ET.parse(source_mark).getroot().find("svg:path", ns).attrib["d"]
for path in (ROOT / "Documentation/Brand").glob("Prompti-Mark*.svg"):
    check(ET.parse(path).getroot().find("svg:path", ns).attrib["d"] == contour,
          f"Brand contour differs from icon: {path.name}")

mark = ROOT / "Prompti/Assets.xcassets/BrandMark.imageset"
properties = json.loads((mark / "Contents.json").read_text())["properties"]
check(properties == {"preserves-vector-representation": True, "template-rendering-intent": "template"},
      "In-app brand asset must remain a vector template")
check((mark / "BrandMark.pdf").read_bytes().startswith(b"%PDF"), "Brand template PDF missing")

catalog = ROOT / "Prompti/Assets.xcassets/AppIcon.appiconset"
for entry in json.loads((catalog / "Contents.json").read_text())["images"]:
    path = catalog / entry["filename"]
    data = path.read_bytes()
    check(data[:8] == b"\x89PNG\r\n\x1a\n", f"Invalid PNG: {path.name}")
    width, height, depth, color_type = struct.unpack(">IIBB", data[16:26])
    check((width, height, depth, color_type) == (1024, 1024, 8, 2),
          f"App icon must be 1024×1024, 8-bit RGB without alpha: {path.name}")
    chunks = []
    offset = 8
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        chunks.append(data[offset + 4:offset + 8])
        offset += length + 12
    check(b"sRGB" in chunks, f"App icon must carry an sRGB tag: {path.name}")

if errors:
    print("Brand check failed:\n" + "\n".join(f"- {error}" for error in errors))
    sys.exit(1)
print(f"Brand check passed: shared vector marks, opaque icons, semantic roles; minimum text contrast {minimum:.2f}:1.")
