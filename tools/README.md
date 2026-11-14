# tools

Offline Python data pipeline (not shipped with the addon). Run everything from the repo root.

| Script | What it does |
| --- | --- |
| `build_recipes.py --build <build> --profession "<name>"` | Writes `ProfPlanner/Data/Recipes_<Profession>.lua` from the client's DB2 tables (downloaded once from wago.tools into `tools/db2/`), then applies the files in `tools/overrides/`. |
| `build_vendor_prices.py --build <build>` | Writes `ProfPlanner/Data/VendorPrices.lua` for the item IDs in `vendor_items.json`. |
| `import_zockify.py --profession "<name>"` | Fetches learn skills and recipe sources from Zockify into `overrides/<Profession>_zockify.json`. |
| `import_scans.py <SavedVariables/ProfPlanner.lua>` | Folds `/pp scan` trainer scans into `overrides/<Profession>_ingame.json`. In-game values win over web values. |

After a game patch: re-run `build_recipes.py` for each profession with the new build number
(`/pp debug` in game prints it), then `build_vendor_prices.py` with the same build.
