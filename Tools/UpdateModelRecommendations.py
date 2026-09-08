#!/usr/bin/env python3
"""Refresh the reviewed shortlist from OpenRouter's public weekly request data.

No API key or inference call. The public page's hydration format is not a stable
API contract: fail without changing the snapshot if it changes. Keep missing
models unranked; the token leaderboard is not a request-count leaderboard.
"""
import argparse
import datetime
import json
from pathlib import Path
import re
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "Prompti/Resources/OpenRouterRecommendations.json"
SOURCE = "https://openrouter.ai/rankings"


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": "Prompti-catalog-maintenance/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(8_000_001)
    if len(data) > 8_000_000:
        raise ValueError("Unexpected response size")
    return data.decode()


def weekly_rows(html):
    chunks = []
    for match in re.finditer(r'self\.__next_f\.push\((\[1,.*?\])\)</script>', html):
        chunks.append(json.loads(match[1])[1])

    def walk(value):
        if isinstance(value, dict):
            if value.get("queryKey") == ["rankings", "models", {"view": "week"}]:
                return value["state"]["data"]
            children = value.values()
        elif isinstance(value, list):
            children = value
        else:
            return None
        for child in children:
            result = walk(child)
            if result is not None:
                return result

    for line in "".join(chunks).splitlines():
        try:
            value = json.loads(line.split(":", 1)[1])
        except (ValueError, IndexError):
            continue
        rows = walk(value)
        if rows:
            for row in rows:
                if not isinstance(row.get("count"), int) or row["count"] < 0:
                    raise ValueError("Missing weekly request count; refusing to substitute tokens")
                if not row.get("variant_permaslug") or not row.get("date"):
                    raise ValueError("Missing variant/date metadata")
            return rows
    raise ValueError("Public weekly rankings format changed; snapshot left untouched")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rankings-file", type=Path, help="Previously fetched public rankings HTML")
    parser.add_argument("--models-file", type=Path, help="Previously fetched /api/v1/models JSON")
    args = parser.parse_args()
    html = args.rankings_file.read_text() if args.rankings_file else fetch(SOURCE)
    catalog = json.loads(args.models_file.read_text() if args.models_file else fetch("https://openrouter.ai/api/v1/models"))
    rows = weekly_rows(html)
    dates = {row["date"][:10] for row in rows}
    if len(dates) != 1:
        raise ValueError("Expected one weekly snapshot date")
    as_of = dates.pop()
    datetime.date.fromisoformat(as_of)
    counts = {row["variant_permaslug"]: row["count"] for row in rows}
    models = {model["id"]: model for model in catalog["data"]}
    snapshot = json.loads(TARGET.read_text())
    for recommendation in snapshot["models"]:
        model = models[recommendation["id"]]
        if "text" not in model["architecture"]["output_modalities"]:
            raise ValueError("Recommendation does not produce text: " + model["id"])
        recommendation["weeklyRequests"] = counts.get(model["canonical_slug"])
    snapshot.update(source=SOURCE, asOf=as_of,
                    license="CC BY 4.0", metric="requests", windowDays=7)
    snapshot["models"].sort(key=lambda model: (model["weeklyRequests"] is None,
        -(model["weeklyRequests"] or 0), model["name"]))
    if not any(model["weeklyRequests"] is not None for model in snapshot["models"]):
        raise ValueError("No shortlist models matched; snapshot left untouched")
    temporary = TARGET.with_suffix(".tmp")
    temporary.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(TARGET)
    print(f"Updated {len(snapshot['models'])} models; weekly requests through {as_of}.")


if __name__ == "__main__":
    main()
