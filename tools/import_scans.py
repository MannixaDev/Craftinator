#!/usr/bin/env python3
"""Fold recorded trainer and vendor data into tools/overrides/.

Usage (from the repo root), with either kind of file:
    python tools/import_scans.py "<WoW>/_forever_/WTF/Account/<account>/SavedVariables/Craftinator.lua"
    python tools/import_scans.py export.txt        (text copied from /ci export, e.g. out of an issue)

Trainers: each entry gives a recipe's spell ID, the skill needed to learn it and the fee.
These go into overrides/<Profession>_ingame.json; existing values are kept unless a record
says otherwise. Then re-run tools/build_recipes.py for the professions it names.
Trainer and vendor positions, ranks taught and items sold go into overrides/npcs_ingame.json,
keyed by NPC id, for correcting Data/NPCs.lua and vendor_items.json.
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
    for path in (ROOT / "Craftinator" / "Data").glob("Recipes_*.lua"):
        text = path.read_text(encoding="utf-8")
        profession = re.search(r'ns\.Data\.Recipes\["([^"]+)"\]', text).group(1)
        for spell in re.findall(r"^  \[(\d+)\] = \{", text, re.M):
            spells[int(spell)] = profession
    return spells


def parse_export(text):
    """Text from /ci export -> (trainer scans, vendor scans) in the SavedVariables shape."""
    trainers, vendors, current = [], [], None
    for line in text.splitlines():
        fields = line.strip().split(";")
        kind = fields[0]
        if kind in ("T", "V") and len(fields) >= 10:
            current = {
                "npcID": int(fields[1]) if fields[1].isdigit() else None, "npcName": fields[2],
                "faction": fields[3], "mapID": int(fields[4]) if fields[4].isdigit() else None,
                "x": float(fields[5]) if fields[5] else None, "y": float(fields[6]) if fields[6] else None,
                "zone": fields[7], "subzone": fields[8], "build": fields[9],
                "services": [], "items": [],
            }
            (trainers if kind == "T" else vendors).append(current)
        elif kind == "S" and current and len(fields) >= 5:
            current["services"].append({
                "spellID": int(fields[1]) if fields[1].isdigit() else None,
                "skillRank": int(fields[2] or 0), "cost": int(fields[3] or 0), "name": fields[4],
            })
        elif kind == "I" and current and len(fields) >= 6:
            current["items"].append({
                "itemID": int(fields[1]), "price": int(fields[2] or 0), "stack": int(fields[3] or 1),
                "available": int(fields[4] or -1), "extended": fields[5] == "1",
            })
    return trainers, vendors


def as_list(table):
    """A Lua array read by parse_saved_variables is a list, or a dict with integer keys."""
    if isinstance(table, dict):
        return [table[k] for k in sorted(k for k in table if isinstance(k, int))]
    return table or []


def npc_record(scan, role):
    return {
        "name": scan.get("npcName"), "role": role, "faction": scan.get("faction"), "mapID": scan.get("mapID"),
        "zone": scan.get("zone"), "subzone": scan.get("subzone"),
        "x": round(scan["x"], 4) if scan.get("x") else None, "y": round(scan["y"], 4) if scan.get("y") else None,
        "build": str(scan.get("build") or ""),
    }


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    text = Path(sys.argv[1]).read_text(encoding="utf-8-sig")
    if "Craftinator export v1" in text or "ProfPlanner export v1" in text:   # ProfPlanner: the first name
        trainers, vendors = parse_export(text)
    else:
        saved = parse_saved_variables(text).get("CraftinatorDB") or {}
        trainers = list((saved.get("trainerScans") or {}).values())
        vendors = list((saved.get("vendorScans") or {}).values())
    if not trainers and not vendors:
        sys.exit("Nothing recorded in that file. Visit a profession trainer or supply vendor, then /reload or /ci export.")

    spells = recipe_spells()
    found, npcs = {}, {}
    for scan in trainers:
        services = as_list(scan.get("services"))
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
        print(f"trainer {scan.get('npcName')} (npc {scan.get('npcID')}), {scan.get('zone')} {scan.get('faction')}, "
              f"at {100 * (scan.get('x') or 0):.1f}, {100 * (scan.get('y') or 0):.1f}: "
              f"{', '.join(sorted(professions)) or 'no known recipes'}; teaches ranks {ranks or 'none'} "
              f"(skill cap {top}); {len(services)} entries, {unmatched} not in the recipe data")
        if scan.get("npcID") and professions:
            record = npc_record(scan, "trainer")
            record.update({"professions": sorted(professions), "ranks": ranks, "maxSkill": top})
            npcs[str(scan["npcID"])] = record

    for scan in vendors:
        items = as_list(scan.get("items"))
        print(f"vendor {scan.get('npcName')} (npc {scan.get('npcID')}), {scan.get('zone')} {scan.get('faction')}, "
              f"at {100 * (scan.get('x') or 0):.1f}, {100 * (scan.get('y') or 0):.1f}: {len(items)} reagent or recipe items")
        if scan.get("npcID") and items:
            record = npc_record(scan, "vendor")
            record["items"] = [{"itemID": i["itemID"], "price": i.get("price", 0), "stack": i.get("stack", 1),
                                "limited": i.get("available", -1) >= 0, "notGold": bool(i.get("extended"))}
                               for i in items]
            npcs[str(scan["npcID"])] = record

    for profession, recipes in sorted(found.items()):
        path = ROOT / "tools" / "overrides" / f"{profession.replace(' ', '')}_ingame.json"
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {
            "credit": "Read from trainer windows in game with /ci scan", "recipes": {}}
        changed = sum(1 for spell, seen in recipes.items() if data["recipes"].get(spell) != seen)
        data["recipes"].update(recipes)
        data["recipes"] = dict(sorted(data["recipes"].items(), key=lambda item: int(item[0])))
        path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8", newline="\n")
        print(f"{path.relative_to(ROOT)}: {len(recipes)} recipes scanned, {changed} new or changed, "
              f"{len(data['recipes'])} in total")

    if npcs:
        path = ROOT / "tools" / "overrides" / "npcs_ingame.json"
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {
            "credit": "Recorded in game by the addon when trainer and vendor windows were opened", "npcs": {}}
        added = sum(1 for key in npcs if key not in data["npcs"])
        data["npcs"].update(npcs)
        data["npcs"] = dict(sorted(data["npcs"].items(), key=lambda item: int(item[0])))
        path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8", newline="\n")
        print(f"{path.relative_to(ROOT)}: {len(npcs)} NPCs in this file, {added} new, {len(data['npcs'])} in total")


if __name__ == "__main__":
    main()
