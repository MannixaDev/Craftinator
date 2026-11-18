#!/usr/bin/env python3
"""Import recipe learn skills and sources from Zockify's WoW Forever recipe list.

The client data (DB2) has no learn skill for trainer recipes and cannot tell a
vendor recipe from a drop. Zockify's public recipe table lists both. This script
saves just those facts to tools/overrides/<Profession>_zockify.json, which
build_recipes.py merges in.

Usage (from the repo root):
    python tools/import_zockify.py --profession Tailoring

The page is downloaded once to tools/sources/ and reused; delete it to refresh.
"""

import argparse
import codecs
import html
import json
import re
import sys
import urllib.request
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def _cp1252_fallback(error):
    bad = error.object[error.start:error.end]
    return bad.decode("cp1252", errors="replace"), error.end


codecs.register_error("cp1252_fallback", _cp1252_fallback)
URL = "https://www.zockify.com/forever/professions/{slug}/recipes/"

ROW = re.compile(r'<tr\b[^>]*data-filter-source="([^"]*)"[^>]*>(.*?)</tr>', re.S)
NAME = re.compile(r'z-icon-link__name">(.*?)</span>', re.S)
SKILL = re.compile(r'z-datatable__skill--(orange|yellow|green|grey)"[^>]*>(\d+)<')
CELL = re.compile(r"<td[^>]*>(.*?)</td>", re.S)
TAG = re.compile(r"<[^>]+>")
# A vendor in the source cell: its map preview (UiMap ID), zone name, then its name.
VENDOR = re.compile(r'data-z-wow-npc-map="[^"]*/preview/(\d+)\.webp[^"]*"[^>]*'
                    r'data-z-wow-npc-map-name="([^"]*)"[^>]*>([^<]+)</span>')


def fetch(profession):
    slug = profession.lower().replace(" ", "-")
    path = ROOT / "tools" / "sources" / f"zockify_{slug}.html"
    url = URL.format(slug=slug)
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        print(f"downloading {url}", file=sys.stderr)
        request = urllib.request.Request(url, headers={"User-Agent": "db2-pipeline"})
        with urllib.request.urlopen(request, timeout=120) as response:
            path.write_bytes(response.read())
    # The page is UTF-8 with a few stray Windows-1252 bytes (dashes in names).
    return url, path.read_bytes().decode("utf-8", errors="cp1252_fallback")


def text(fragment):
    return " ".join(html.unescape(TAG.sub(" ", fragment)).split())


def parse(page):
    recipes = []
    for source, body in ROW.findall(page):
        name = NAME.search(body)
        if not name:
            continue
        skills = {colour: int(value) for colour, value in SKILL.findall(body)}
        cells = CELL.findall(body)
        recipes.append({
            "name": text(name.group(1)),
            "orange": skills.get("orange"),
            "yellow": skills.get("yellow"),
            "green": skills.get("green"),
            "grey": skills.get("grey"),
            "source": source,                       # e.g. trainer, vendor, drop, "drop vendor"
            "sourceText": text(cells[-1]) if cells else "",
            "vendors": [{"name": html.unescape(n).strip(), "zone": html.unescape(z), "mapID": int(m)}
                        for m, z, n in VENDOR.findall(cells[-1])] if cells and "vendor" in source else [],
        })
    return recipes


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--profession", required=True)
    args = parser.parse_args()

    url, page = fetch(args.profession)
    title = re.search(r"<title>([^<]*)", page)
    if not title or args.profession.lower() not in title.group(1).lower():
        # The site serves another profession's page for names it does not have.
        sys.exit(f"The page at {url} is not a {args.profession} recipe list: {title and title.group(1)!r}")
    recipes = parse(page)
    if not recipes:
        sys.exit("No recipe rows found: the page layout may have changed.")
    out = ROOT / "tools" / "overrides" / f"{args.profession.replace(' ', '')}_zockify.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({
        "credit": "Learn skills and recipe sources from Zockify (zockify.com)",
        "url": url,
        "fetched": date.today().isoformat(),
        "recipes": recipes,
    }, indent=1, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")

    with_orange = sum(1 for r in recipes if r["orange"] is not None)
    print(f"wrote {out.relative_to(ROOT)}: {len(recipes)} recipes, {with_orange} with a learn skill")


if __name__ == "__main__":
    main()
