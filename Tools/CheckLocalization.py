#!/usr/bin/env python3
"""Check Chinese coverage, interpolation types, and dynamically localized catalog text.

Use --stringsdata <DerivedData> after a build with SWIFT_EMIT_LOC_STRINGS=YES to
include compiler-extracted SwiftUI strings, which are not visible to source grep.
"""
import argparse
from collections import Counter
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def units(value):
    if "stringUnit" in value:
        yield value["stringUnit"]
    for group in value.get("variations", {}).values():
        for variation in group.values():
            yield from units(variation)


def placeholders(value):
    return Counter(re.findall(r"%(?:\d+\$)?(lld|ld|d|@|f)", value.replace("%%", "")))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stringsdata", type=Path)
    args = parser.parse_args()
    failures = []
    tables = {}
    for path in (ROOT / "Prompti/Resources").glob("*.xcstrings"):
        catalog = json.loads(path.read_text())
        tables[path.stem] = catalog["strings"]
        for key, entry in catalog["strings"].items():
            if entry.get("shouldTranslate") is False:
                continue
            localized = list(units(entry.get("localizations", {}).get("zh-Hans", {})))
            if not localized or any(unit.get("state") != "translated" or not unit.get("value") for unit in localized):
                failures.append(f"{path.name}: missing Chinese: {key}")
            source = list(units(entry.get("localizations", {}).get("en", {})))
            expected = placeholders(source[0]["value"] if source else key)
            for unit in localized:
                if placeholders(unit["value"]) != expected:
                    failures.append(f"{path.name}: placeholder mismatch: {key}")

    source = (ROOT / "Prompti/Domain/DestinationModels.swift").read_text()
    required = set(re.findall(r'(?:city|country|landmarkName|name|title): "([^"\\]+)"', source))
    for match in re.finditer(r'\.init\("[^"]+", "([^"]+)", "([^"]+)", [^\n]+?, \[[^\]]+\], "([^"]+)"', source):
        required.update(match.groups())
    required.add("Around %@")
    for key in sorted(required - tables["Localizable"].keys()):
        failures.append(f"Dynamic catalog text missing: {key}")

    extracted = 0
    if args.stringsdata:
        paths = list(args.stringsdata.rglob("*.stringsdata"))
        if not paths:
            failures.append("No compiler stringsdata found; build with SWIFT_EMIT_LOC_STRINGS=YES")
        for path in paths:
            data = json.loads(path.read_text())
            if "/Prompti/" not in data.get("source", ""):
                continue
            for table, entries in data.get("tables", {}).items():
                for entry in entries:
                    extracted += 1
                    if entry["key"] not in tables.get(table, {}):
                        failures.append(f"{Path(data['source']).name}: missing extracted key: {entry['key']}")
    if failures:
        raise SystemExit("\n".join(sorted(set(failures))))
    print(f"Localization passed: {sum(map(len, tables.values()))} catalog entries, {len(required)} dynamic labels, {extracted} compiler-extracted uses.")


if __name__ == "__main__":
    main()
