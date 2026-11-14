# tools

Offline Python data pipeline (not shipped with the addon). Run everything from the repo root.

| Script | What it does |
| --- | --- |
| `build_recipes.py --build <build> --profession "<name>"` | Writes `Data/Recipes_<Profession>.lua` from the client's DB2 tables (downloaded once from wago.tools into `tools/db2/`), then applies the files in `tools/overrides/`. |
| `build_vendor_prices.py --build <build>` | Writes `Data/VendorPrices.lua` for the item IDs in `vendor_items.json`. |
| `import_zockify.py --profession "<name>"` | Fetches learn skills and recipe sources from Zockify into `overrides/<Profession>_zockify.json`. |
| `import_scans.py <file>` | Folds recorded trainer and vendor data into `overrides/<Profession>_ingame.json` and `overrides/npcs_ingame.json`. The file is either `SavedVariables/Craftinator.lua` or text copied from `/ci export`. In-game values win over web values. |
| `build_npcs.py` | Writes `Data/NPCs_Recorded.lua` from `overrides/npcs_ingame.json`: recorded trainer positions and skill caps, and vendors with what they sell. The addon merges it over `Data/NPCs.lua` at load. |

After importing new records: run `build_npcs.py`, `build_recipes.py` for the professions the
import named, and `build_vendor_prices.py` (it adds reagents seen at vendors in game).

After a game patch: re-run `build_recipes.py` for each profession with the new build number
(`/ci debug` in game prints it), then `build_vendor_prices.py` with the same build.

`install.sh <path to Interface/AddOns>` copies the addon files (the `.toc`, the Lua files in
the repo root, `Data/` and `UI/`) into the game for testing.
