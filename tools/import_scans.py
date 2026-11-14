#!/usr/bin/env python3
"""Fold /pp scan results into tools/overrides/<Profession>_ingame.json.

Usage (from the repo root), after /pp scan at a trainer and a /reload:
    python tools/import_scans.py "<WoW>/_forever_/WTF/Account/<account>/SavedVariables/ProfPlanner.lua"

Each scanned trainer entry gives a recipe's spell ID, the skill needed to learn it and the
trainer's fee. Existing override values are kept unless a scan says otherwise. Then re-run
tools/build_recipes.py for the professions it names. It also prints what each trainer
teaches (ranks, position) so Data/NPCs.lua can be corrected by hand.
"""

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RANK_CAPS = {"Apprentice": 75, "Journeyman": 150, "Expert": 225, "Artisan": 300}

TOKEN = re.compile(r'\s*(?:(--[^\n]*)|([{}=,\[\]])|"((?:[^"\\]|\\.)*)"|(-?\d+\.?\d*(?:e[-+]?\d+)?)|(\w+))', re.I)


def parse_saved_variables(text):
    """Parse the simple Lua table syntax the game writes. Returns {global name: value}."""
    tokens = []
    position = 0
    while position < len(text):
        match = TOKEN.match(text, position)
        if not match:
            if text[position:].strip():
                raise ValueError(f"cannot parse at {position}: {text[position:position + 40]!r}")
            break
        position = match.end()
        comment, symbol, string, number, word = match.groups()
        if comment is not None:
            continue
        if symbol:
            tokens.append(("sym", symbol))
        elif string is not None:
            tokens.append(("val", string.replace('\\"', '"').replace("\\\\", "\\")))
        elif number is not None:
            tokens.append(("val", float(number) if re.search(r"[.e]", number, re.I) else int(number)))
        else:
            tokens.append(("val", {"true": True, "false": False, "nil": None}.get(word, word)))
    index = 0

    def value():
        nonlocal index
        kind, token = tokens[index]
        index += 1
        if (kind, token) != ("sym", "{"):
            return token
        table, array = {}, []
        while tokens[index] != ("sym", "}"):
            if tokens[index] == ("sym", "["):
                index += 1
                key = value()
                index += 2          # ] =
                table[key] = value()
            else:
                array.append(value())
            if tokens[index] == ("sym", ","):
                index += 1
        index += 1
        if array and not table:
            return array
        for i, item in enumerate(array, 1):
            table[i] = item
        return table

    result = {}
    while index < len(tokens):
        name = tokens[index][1]
        index += 2                  # name =
        result[name] = value()
    return result


def recipe_spells():
    """{spell ID: profession} from the generated data files."""
    spells = {}
    for path in (ROOT / "ProfPlanner" / "Data").glob("Recipes_*.lua"):
        text = path.read_text(encoding="utf-8")
        profession = re.search(r'ns\.Data\.Recipes\["([^"]+)"\]', text).group(1)
        for spell in re.findall(r"^  \[(\d+)\] = \{", text, re.M):
            spells[int(spell)] = profession
    return spells


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    saved = parse_saved_variables(Path(sys.argv[1]).read_text(encoding="utf-8"))
    scans = (saved.get("ProfPlannerDB") or {}).get("trainerScans") or {}
    if not scans:
        sys.exit("No trainer scans in that file. Run /pp scan at a trainer, then /reload.")

    spells = recipe_spells()
    found = {}
    for scan in scans.values():
        services = scan.get("services") or []
        ranks, professions, unmatched = [], set(), 0
        for service in services:
            name = service.get("name") or ""
            rank = name.split(" ")[0]
            if rank in RANK_CAPS and service.get("spellID") not in spells:
                ranks.append(rank)
                continue
            profession = spells.get(service.get("spellID"))
            if not profession:
                unmatched += 1
                continue
            professions.add(profession)
            found.setdefault(profession, {})[str(service["spellID"])] = {
                "learn": service.get("skillRank") or 1, "cost": service.get("cost") or 0,
            }
        top = max((RANK_CAPS[r] for r in ranks), default=None)
        print(f"{scan.get('npcName')} (npc {scan.get('npcID')}), {scan.get('zone')} {scan.get('faction')}, "
              f"at {100 * (scan.get('x') or 0):.1f}, {100 * (scan.get('y') or 0):.1f}: "
              f"{', '.join(sorted(professions)) or 'no known recipes'}; teaches ranks {ranks or 'none'} "
              f"(skill cap {top}); {len(services)} entries, {unmatched} not in the recipe data")

    for profession, recipes in sorted(found.items()):
        path = ROOT / "tools" / "overrides" / f"{profession.replace(' ', '')}_ingame.json"
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {
            "credit": "Read from trainer windows in game with /pp scan", "recipes": {}}
        changed = sum(1 for spell, seen in recipes.items() if data["recipes"].get(spell) != seen)
        data["recipes"].update(recipes)
        data["recipes"] = dict(sorted(data["recipes"].items(), key=lambda item: int(item[0])))
        path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8", newline="\n")
        print(f"{path.relative_to(ROOT)}: {len(recipes)} recipes scanned, {changed} new or changed, "
              f"{len(data['recipes'])} in total")


if __name__ == "__main__":
    main()
