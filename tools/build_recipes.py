#!/usr/bin/env python3
"""Build Data/Recipes_<Profession>.lua from DB2 exports.

Usage (from the repo root):
    python tools/build_recipes.py --build 1.60.1.70938 --profession Tailoring

Tables are downloaded once from wago.tools into tools/db2/<build>/ and reused.

What DB2 does and does not give us on the Forever client:
  - yellow / grey thresholds: SkillLineAbility.TrivialSkillLineRankLow / High.
    green is the midpoint (the classic rule), rounded down.
  - reagents: SpellReagents. Output item and quantity: SpellEffect (effect 24).
  - craft station (anvil, forge, cooking fire): SpellCastingRequirements.RequiresSpellFocus,
    named by SpellFocusObject.
  - recipes taught by an item (Pattern:/Blueprint:): the item's RequiredSkillRank
    is the skill needed to learn it.
  - NOT available: the skill needed for trainer-taught recipes, trainer costs,
    and whether a recipe item is sold by a vendor or only drops. Those are
    server-side. Such fields are written as nil / "item" and must come from
    another source (an in-game trainer scan or hand curation).
"""

import argparse
import csv
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TABLES = ["SkillLine", "SkillLineAbility", "SpellName", "SpellReagents",
          "SpellEffect", "ItemEffect", "ItemXItemEffect", "ItemSparse",
          "SpellCastingRequirements", "SpellFocusObject"]
EFFECT_CREATE_ITEM = "24"
TRIGGER_ON_LEARN = "6"
# ItemSparse.Flags_1 bits
FLAG_HORDE_ONLY = 0x1
FLAG_ALLIANCE_ONLY = 0x2


def load(build, table):
    folder = ROOT / "tools" / "db2" / build
    path = folder / f"{table}.csv"
    if not path.exists():
        folder.mkdir(parents=True, exist_ok=True)
        url = f"https://wago.tools/db2/{table}/csv?build={build}"
        print(f"downloading {url}", file=sys.stderr)
        request = urllib.request.Request(url, headers={"User-Agent": "db2-pipeline"})
        with urllib.request.urlopen(request, timeout=300) as response:
            path.write_bytes(response.read())
    with open(path, encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def item_faction(item):
    flags = int(item["Flags_1"])
    if flags & FLAG_HORDE_ONLY:
        return "Horde"
    if flags & FLAG_ALLIANCE_ONLY:
        return "Alliance"
    return None


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_value(value):
    if value is None:
        return "nil"
    if isinstance(value, str):
        return lua_string(value)
    return str(value)


def match_name(name):
    """Recipe name reduced for matching across sources: dashes, spacing and case vary."""
    name = re.sub(r"[‐-―−]", "-", name)
    return re.sub(r"\s+", " ", name).strip().casefold()


def load_overrides(profession, kind):
    path = ROOT / "tools" / "overrides" / f"{profession.replace(' ', '')}_{kind}.json"
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def apply_overrides(profession, recipes):
    """Fill in what DB2 lacks. In-game trainer values win over website values."""
    stats = {"zockify learn": 0, "zockify source": 0, "ingame learn": 0, "learn mismatches": [], "unmatched": 0}

    web = load_overrides(profession, "zockify")
    if web:
        # The site names some recipes after the spell and some after the item made.
        by_key = {(match_name(r["name"]), r["yellow"], r["grey"]): r for r in web["recipes"]}
        for r in recipes:
            match = by_key.get((match_name(r["name"]), r["yellow"], r["grey"]))
            if not match and r["output"]:
                match = by_key.get((match_name(r["output"][2]), r["yellow"], r["grey"]))
            if not match:
                stats["unmatched"] += 1
                continue
            if match["orange"] is not None:
                if r["learn"] is None:
                    r["learn"] = match["orange"]
                    stats["zockify learn"] += 1
                elif r["learn"] != match["orange"]:
                    stats["learn mismatches"].append((r["name"], r["learn"], match["orange"]))
            kinds = match["source"].split()
            known = [k for k in ("vendor", "quest", "drop", "trainer") if k in kinds]
            if known and r["source"] in ("item", "unknown"):
                r["source"] = known[0]   # a recipe that is both sold and dropped counts as vendor
                stats["zockify source"] += 1
            note = re.sub(r"^(Pattern|Blueprint): .*? (?=Vendor|World drop|Drop:|Quest:|\d+ vendors)", "",
                          match["sourceText"])
            if known and note not in ("Trainer", "With the profession"):
                r["sourceNote"] = note if len(note) <= 100 else note[:97] + "..."

    ingame = load_overrides(profession, "ingame")
    if ingame:
        for r in recipes:
            seen = ingame["recipes"].get(str(r["spell"]))
            if seen:
                if r["learn"] not in (None, seen["learn"]):
                    stats["learn mismatches"].append((r["name"], r["learn"], seen["learn"]))
                r["learn"] = seen["learn"]
                r["sourceCost"] = seen.get("cost")
                stats["ingame learn"] += 1

    # Trainer recipes whose learn skill no source gives: a recipe is never learned later than
    # the skill where it turns yellow, so use that. It may really be available earlier.
    stats["estimated"] = 0
    for r in recipes:
        if r["learn"] is None and r["source"] == "trainer":
            r["learn"] = r["yellow"]
            r["learnEstimated"] = True
            stats["estimated"] += 1

    for r in recipes:
        if "sourceCost" not in r:
            priced_in_gold = r["source"] == "vendor" and "Favor" not in r.get("sourceNote", "")
            r["sourceCost"] = r["recipeBuyPrice"] if priced_in_gold else None
    return stats


def build_recipes(build, profession):
    skill_lines = [r for r in load(build, "SkillLine") if r["DisplayName_lang"] == profession]
    if not skill_lines:
        sys.exit(f"No SkillLine named {profession!r} in build {build}")
    # A profession can have several rows (e.g. per-expansion children); the base one has no parent.
    skill_line = next((r for r in skill_lines if r["ParentSkillLineID"] == "0"), skill_lines[0])["ID"]

    names = {r["ID"]: r["Name_lang"] for r in load(build, "SpellName")}
    items = {r["ID"]: r for r in load(build, "ItemSparse")}
    reagents = {r["SpellID"]: r for r in load(build, "SpellReagents")}

    outputs = {}
    for effect in load(build, "SpellEffect"):
        if effect["Effect"] == EFFECT_CREATE_ITEM and effect["EffectItemType"] != "0":
            outputs.setdefault(effect["SpellID"], effect)

    focus_names = {r["ID"]: r["Name_lang"] for r in load(build, "SpellFocusObject")}
    stations = {r["SpellID"]: focus_names.get(r["RequiresSpellFocus"])
                for r in load(build, "SpellCastingRequirements") if r["RequiresSpellFocus"] != "0"}

    item_effects = {r["ID"]: r for r in load(build, "ItemEffect")}
    taught_by = {}
    for link in load(build, "ItemXItemEffect"):
        effect = item_effects.get(link["ItemEffectID"])
        if effect and effect["TriggerType"] == TRIGGER_ON_LEARN:
            taught_by.setdefault(effect["SpellID"], []).append(link["ItemID"])

    recipes, skipped = [], []
    for row in load(build, "SkillLineAbility"):
        if row["SkillLine"] != skill_line:
            continue
        spell = row["Spell"]
        yellow, grey = int(row["TrivialSkillLineRankLow"]), int(row["TrivialSkillLineRankHigh"])
        name = names.get(spell)
        output = outputs.get(spell)
        reagent_row = reagents.get(spell)
        if grey == 0 or not (output or reagent_row):
            continue  # the profession rank spells themselves, not recipes
        if not name:
            skipped.append((spell, "?", "no spell name"))
            continue
        mats = []
        if reagent_row:
            for i in range(8):
                item_id = reagent_row[f"Reagent_{i}"]
                if item_id != "0":
                    mats.append((item_id, int(reagent_row[f"ReagentCount_{i}"])))
        missing = [i for i, _ in mats if i not in items]
        if output and output["EffectItemType"] not in items:
            missing.append(output["EffectItemType"])
        if missing:
            skipped.append((spell, name, "items not in this build: " + ", ".join(missing)))
            continue

        recipe_items = [i for i in taught_by.get(spell, []) if i in items]
        recipe_item = items[recipe_items[0]] if recipe_items else None
        if recipe_item:
            source = "item"            # vendor or drop: not knowable from DB2
            learn = int(recipe_item["RequiredSkillRank"]) or 1
        elif spell in taught_by:
            source, learn = "unknown", None   # taught by an item that is not in this build
        elif row["AcquireMethod"] == "1":
            source, learn = "trainer", 1      # learned automatically with the profession
        else:
            source, learn = "trainer", None   # trainer skill requirement is server-side

        output_item = items[output["EffectItemType"]] if output else None   # enchants make no item
        faction = (output_item and item_faction(output_item)) or (recipe_item and item_faction(recipe_item))
        recipes.append({
            "spell": int(spell),
            "name": name,
            "ability": int(row["ID"]),
            "output": output and (int(output["EffectItemType"]), max(1, int(float(output["EffectBasePointsF"]))),
                                  output_item["Display_lang"]),
            "reagents": [(int(i), q, items[i]["Display_lang"]) for i, q in mats],
            "learn": learn,
            "yellow": yellow,
            "green": (yellow + grey) // 2,
            "grey": grey,
            "source": source,
            "recipeItem": int(recipe_items[0]) if recipe_item else None,
            "recipeBuyPrice": int(recipe_item["BuyPrice"]) if recipe_item else None,
            "faction": faction or None,
            "station": stations.get(spell),
        })
    recipes.sort(key=lambda r: (r["yellow"], r["grey"], r["spell"]))
    stats = apply_overrides(profession, recipes)
    stats["skillLine"] = int(skill_line)
    return recipes, skipped, stats


def write_lua(build, profession, recipes, skipped, skill_line):
    lines = [
        f"-- Data/Recipes_{profession}.lua",
        f"-- GENERATED by tools/build_recipes.py from DB2 build {build}. Do not edit by hand.",
        "-- Learn skills for trainer recipes and vendor/drop/quest sources are not in the client data.",
        "-- They come from tools/overrides/: values read from trainers in game, then Zockify (zockify.com).",
        "-- learnEstimated = true: a trainer recipe whose learn skill is unknown, set to its yellow threshold.",
        "-- learn = nil: still unknown. source = \"item\" / \"unknown\": taught by an item, origin unknown.",
        "-- sourceCost (copper) = trainer fee seen in game, or the vendor price; nil when unknown or not gold.",
        "-- station = the object you must stand next to (Anvil, Forge, Cooking Fire), when there is one.",
        "",
        "local _, ns = ...",
        "",
        f"ns.Data.RecipesBuild = ns.Data.RecipesBuild or {{}}",
        f"ns.Data.RecipesBuild[{lua_string(profession)}] = {lua_string(build)}",
        "ns.Data.SkillLines = ns.Data.SkillLines or {}",
        f"ns.Data.SkillLines[{skill_line}] = {lua_string(profession)} -- C_TradeSkillUI professionID",
        "",
        f"ns.Data.Recipes[{lua_string(profession)}] = {{",
    ]
    for r in recipes:
        output = "{ itemID = %d, qty = %d }" % r["output"][:2] if r["output"] else "nil"
        mats = ", ".join(f"{{ itemID = {i}, qty = {q} }}" for i, q, _ in r["reagents"])
        mat_names = ", ".join(f"{q}x {n}" for _, q, n in r["reagents"])
        lines += [
            f"  [{r['spell']}] = {{ -- {mat_names}",
            f"    name = {lua_string(r['name'])}, skillLineAbilityID = {r['ability']},",
            f"    output = {output},",
            f"    reagents = {{ {mats} }},",
            f"    learn = {lua_value(r['learn'])}, orange = {lua_value(r['learn'])}, "
            f"yellow = {r['yellow']}, green = {r['green']}, grey = {r['grey']},",
            f"    source = {lua_string(r['source'])}, sourceCost = {lua_value(r['sourceCost'])}, "
            f"recipeItem = {lua_value(r['recipeItem'])}, faction = {lua_value(r['faction'])},",
        ]
        if r.get("learnEstimated"):
            lines.append("    learnEstimated = true, -- learn skill unknown: assumed to be the yellow threshold")
        if r.get("station"):
            lines.append(f"    station = {lua_string(r['station'])},")
        if r.get("sourceNote"):
            lines.append(f"    sourceNote = {lua_string(r['sourceNote'])},")
        lines += [
            "  },",
        ]
    lines.append("}")
    if skipped:
        lines += ["", "-- Skipped:"] + [f"--   {spell} {name}: {why}" for spell, name, why in skipped]
    path = ROOT / "Data" / f"Recipes_{profession.replace(' ', '')}.lua"
    path.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--build", required=True, help="client build, e.g. 1.60.1.70938")
    parser.add_argument("--profession", required=True, help="profession name, e.g. Tailoring")
    args = parser.parse_args()

    recipes, skipped, stats = build_recipes(args.build, args.profession)
    path = write_lua(args.build, args.profession, recipes, skipped, stats["skillLine"])

    by_source = {}
    for r in recipes:
        by_source[r["source"]] = by_source.get(r["source"], 0) + 1
    print(f"wrote {path.relative_to(ROOT)}: {len(recipes)} recipes, {len(skipped)} skipped")
    print("  by source:", ", ".join(f"{k} {v}" for k, v in sorted(by_source.items())))
    print("  faction-specific:", sum(1 for r in recipes if r["faction"]))
    print(f"  overrides: {stats['zockify learn']} learn skills and {stats['zockify source']} sources from Zockify, "
          f"{stats['ingame learn']} recipes confirmed in game")
    print(f"  learn skill estimated from yellow: {stats['estimated']}; still unknown:",
          sum(1 for r in recipes if r["learn"] is None),
          f"| recipes with no Zockify match: {stats['unmatched']}")
    for name, ours, theirs in stats["learn mismatches"]:
        print(f"  MISMATCH {name}: had {ours}, override says {theirs}")


if __name__ == "__main__":
    main()
