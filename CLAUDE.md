# Craftinator: notes for Claude

Craftinator is a World of Warcraft addon for the **WoW Forever** client (Midnight-era client,
Interface 16001, build 1.60.1.70938). It docks a panel to the profession window and builds a
levelling route priced with Auctionator data. Owner: Jack Smith-Morse (GitHub `MannixaDev`).
The addon was first called ProfPlanner; `SPEC.md` is the original spec and still uses that name.

Current version: **0.6.4** (see `## Version` in `Craftinator.toc`).

## How the owner wants to work

- Ask before making design decisions the spec does not cover. Where a decision was made
  without asking, it is listed under "Decisions made without sign-off" below.
- Don't guess game or addon APIs. Check the installed addons' source, warcraft.wiki.gg, or
  ask for an in-game check. Facts confirmed in game are under "Client facts".
- He prefers data from the web or from playing normally over chores in game. In-game checks
  are fine when they are quick.
- Never create, paste or handle API tokens or passwords; he does those steps himself.
- Releases and anything public (tags, CurseForge, repo settings) need his go-ahead each time.
- Write to him in plain language; he is not reading the code.

## Layout

The repository root **is** the addon folder (CurseForge's packager needs the `.toc` at the top).

| Path | What it is |
| --- | --- |
| `Craftinator.toc` | Load order, version, saved variables (`CraftinatorDB`, `CraftinatorCharDB`) |
| `Core.lua` | Namespace, events, settings defaults, `ns.BuildPlan()`, Auctionator list, slash commands |
| `Optimiser.lua`, `Pricing.lua`, `Gathering.lua` | **Plain Lua, no WoW API.** Unit-tested in `spec/`. Keep them that way |
| `Player.lua`, `Inventory.lua`, `Navigation.lua` | Thin adapters over the WoW API; Navigation also merges recorded NPCs |
| `Capture.lua` | Records trainers and vendors when their windows open; `/ci export` |
| `UI/Panel.lua`, `UI/Settings.lua` | Docked panel; options panel and addon-menu entry |
| `Data/Recipes_*.lua`, `Data/VendorPrices.lua`, `Data/NPCs_Recorded.lua`, `Data/Gathering.lua` | **Generated. Never edit by hand** |
| `Data/NPCs.lua` | Hand-written: capital trainers, supply vendors (no positions), rank books |
| `tools/` | Python data pipeline (not shipped). See `tools/README.md` |
| `tools/overrides/` | Data the client lacks: `*_zockify.json` (web), `*_ingame.json` and `npcs_ingame.json` (recorded in game; these win) |
| `spec/` | busted tests |
| `.pkgmeta` | Keeps tests, tools and docs out of CurseForge packages. Add new dev-only files to its `ignore` list |
| `media/`, `dist/` | Logo and CurseForge description; downloaded release zips (git-ignored) |

Slash commands: `/ci` (also `/craftinator`, and `/pp` kept from the old name), with
`config`, `route`, `list`, `send`, `export`, `balance <silver>`, `resale`, `toasts`, `debug`, `scan`.

## Commands

Run from the repo root. On the owner's Windows machine the Lua tools need this first (Git Bash):

```
export PATH="$LOCALAPPDATA/Programs/LuaJIT/bin:$HOME/.luarocks/bin:$PATH"
cmd //c busted.bat          # 48 tests
cmd //c luacheck.bat .      # must be 0 warnings
```

- Install into the game for testing: `bash tools/install.sh "<WoW>/_forever_/Interface/AddOns"`.
  It replaces the `Craftinator` folder there. Lua changes load with `/reload`; a new file or a
  `.toc` change needs a full game restart.
- Rebuild data: `python tools/build_recipes.py --build 1.60.1.70938 --profession "<name>"`,
  `python tools/build_vendor_prices.py --build 1.60.1.70938`, `python tools/build_npcs.py`,
  `python tools/build_gathering.py --build 1.60.1.70938` (from `tools/overrides/gathering_zockify.json`).
- Import player data: `python tools/import_scans.py <file>`, where the file is either the
  game's `SavedVariables/Craftinator.lua` or text copied from `/ci export`. Then rebuild the
  professions it names, the vendor prices and the NPCs.
- Bash heredocs that contain mixed quotes have failed on this machine. For multi-line patches,
  write a small Python script with the Write tool and run it.

## Releasing

1. Bump `## Version` in `Craftinator.toc` and add a `## <version>` section to `CHANGELOG.md`
   (plain language, for players), commit, push to `main`.
2. Push a matching tag, e.g. `v0.6.2`.
3. GitHub Actions (`.github/workflows/release.yml`) builds `Craftinator-<tag>.zip` and makes a
   GitHub release with that version's changelog section. It fails if the tag and the `.toc`
   version differ, or the changelog has no section for it. CurseForge shows the whole
   `CHANGELOG.md` (`manual-changelog` in `.pkgmeta`).
4. A GitHub webhook tells CurseForge (project **1804469**, slug `craftinator`), which packages
   the tag itself. CurseForge is set to package **tagged commits only**. It reads the game
   version (shown as 1.60.1) from the `.toc`.

The CurseForge project was created on 14 Nov 2026 and approved by moderators on 15 Nov 2026.

## Client facts confirmed in game

- Only the modern `C_TradeSkillUI` and `ProfessionsFrame` exist; the old `GetTradeSkill*` API does not.
- `C_TradeSkillUI.GetBaseProfessionInfo()` returns zeros until a profession is selected, so the
  panel polls every 0.5 s for a profession or skill change.
- `C_TradeSkillUI.OpenRecipe` is protected. Select a recipe with
  `ProfessionsFrame.CraftingPage.RecipeList:SelectRecipe(info, true)`.
- Every recipe spell shares one generic icon; rows use the crafted item's icon.
- Map IDs are Classic-style: Stormwind 1453, Orgrimmar 1454, Ironforge 1455, Thunder Bluff 1456,
  Darnassus 1457, Undercity 1458.
- Auctionator `API.v1`: `GetAuctionPriceByItemID`, `GetAuctionAgeByItemID` (days),
  `RegisterForDBUpdate`, `CreateShoppingList`, `ConvertToSearchString` all work.
- Trainer API (`GetNumTrainerServices`, `GetTrainerServiceInfo`, `...SkillReq`, `...Cost`) works;
  vendors use `C_MerchantFrame.GetItemInfo` with `GetMerchantItemInfo` as fallback.
- Trainers on Forever stop a rank lower than their Classic titles suggest: Stormwind's "Artisan"
  tailor teaches up to Expert (225), the "Expert" one up to Journeyman (150). Cooking and First Aid
  trainers stop at 150; the next rank is a book (see `ns.Data.RankBooks` in `Data/NPCs.lua`).
- Forever adds craft stations for professions that had none in Classic (Loom, Tanning Rack and so on).

## Data sources and gaps

- Recipes, reagents, thresholds, stations and tools come from the client tables via wago.tools.
- The skill needed to learn a trainer recipe is **not** in the client. Sources, in order of trust:
  recorded in game, then Zockify, then an estimate equal to the yellow threshold
  (`learnEstimated = true`, shown in the tooltip). Estimates remaining: Alchemy 25, Blacksmithing 29,
  Cooking 4, Enchanting 57, Engineering 55, First Aid 3, Leatherworking 18, Tailoring 17.
- Recorded in game so far. Stormwind: trainers for Tailoring x2, Cooking, First Aid and
  Leatherworking (Simon Tanner, cap 150); vendors Edna Mullby, Jillian Tanner, Erika Tate.
  Southshore: three vendors and the innkeeper. Horde (owner's character): Leatherworking trainers
  Waldor (Wailing Caverns, cap 75), Mak (Thunder Bluff, cap 75) and Tarn (Thunder Bluff, cap 150);
  Pand Stonebinder (Thunder Bluff First Aid, cap 150); vendors Mahu (leatherworking supplies),
  Boramu and Taur Stonehoof in Thunder Bluff; vendors and innkeepers at Sun Rock Retreat and Camp
  Taurajo. No Orgrimmar or Undercity NPC yet.
- Alliance characters so far see vendor prices and trainer fees 10% below the client's `BuyPrice`;
  the Horde character pays the full price, so it is a reputation discount. The data keeps the full
  price: imports keep the highest fee seen, and vendor recipe prices never go below `BuyPrice`.
- `ItemSparse.BuyPrice` is the price of the vendor's bundle (`VendorStackCount` items, e.g. 5 vials);
  `build_vendor_prices.py` divides it down to one item. Before 0.6.2 it did not.
- Every other trainer in `Data/NPCs.lua` has a Classic position and an assumed Classic skill cap,
  so the "train here" hint can be wrong until that trainer is recorded.
- Zockify has not been asked for permission to use its data. The owner knows; it is credited in
  the README and on CurseForge.
- Cooking and First Aid past 225 are quests in `RankBooks` (Clamlette Surprise from Dirge Quikcleave in
  Tanaris, seen in game 18 Nov 2026 with Giant Egg, Zesty Clam Meat, Alterac Swiss; Triage unchecked), from web guides.
- Not covered: Poisons, camping recipes, Skinning.
- Gathering view (Herbalism, Mining, Fishing; owner chose docked, web data only, raw vs crafted):
  herbs, veins, zones per skill band and a partial fish list are transcribed from Zockify's Forever
  guides. Gaps: the three new Forever herbs, Silver/Gold/Truesilver zones (shown with the band's
  zones), fish per zone and the skill each fishing zone needs. Mining's smelting recipes
  (`Recipes_Mining.lua`) feed only the "smelt it" values; the panel never plans a Mining route.
  Node colours assume the Classic rule (yellow +25, green +50, grey +100); not checked on Forever.
  Fish skill is guessed (owner chose this, 15 Nov 2026): the lowest start of a Cooking recipe using
  the fish, else the first fishing band whose zones match its location; fish from a later band are
  listed as "later" (`Gathering.FishSkill`).
- Gathering cap hint (within 5 of the cap): capital Herbalism/Mining trainers (to Artisan) and Fishing
  trainers (to 150) in `Data/NPCs.lua`, positions from warcraft.wiki.gg, unchecked. Fishing 150 is the
  book from Old Man Heming (Booty Bay; the owner bought it in game, 16 Nov 2026), 225 is Nat Pagle's quest (`RankBooks.Fishing`, `quest` entry;
  the owner did it at level 35 and reached cap 300, Nov 2026). Both shown correctly in game.

- Vendor recipes: the tooltip lists Zockify's vendors with zones (`vendors` in the recipe data). The route
  plans with the vendor price; the auction price is only shown (owner chose this, 18 Nov 2026).
- Cooking Fire: no web source lists fire positions, so the tooltip suggests a Basic Campfire and notes that
  inns and Cooking trainers usually have one. Stations are recorded where you craft (owner chose this,
  18 Nov 2026): `CraftinatorDB.stations`, skipped for 5 min after making your own campfire; the tooltip
  names the nearest. Also recorded with the window open next to one, via `C_TradeSkillUI.GetRecipeRequirements`
  (`met`); not yet confirmed to work on Forever. The owner wants no manual marking (no `/ci fire`).
  Account-local only, not in `/ci export`. Uses `C_Map.GetWorldPosFromMapPos` (works on Forever).

## Decisions made without sign-off

These work, but the owner never explicitly agreed to them. Raise them if they become relevant.

- Fastest mode treats each extra kind of reagent as 5% slower and a craft station as 10% slower.
- Resale uses the raw auction price with no auction-house cut, and a route's net cost can go negative.
- Recipes with an unknown reagent price are still usable but always lose to fully priced ones.
- Recipes the character already knows ignore the source filters.
- Trainer fees that are unknown count as zero; vendor recipes sold for a currency are never planned.
- Intermediate materials (bolts, bars) are priced at auction, never as "craft it yourself".
- The route is built by picking which paid recipes are worth buying (`BuildBestRoute`), not by
  literal dynamic programming as the spec describes.

## Not built yet

- Spec items: step-detail pane, "what you can do in this city" list, nearest-station hints,
  a price-source choice in options.
- Never tested: the panel on a Horde character (its data has been imported).
- BugGrabber ran for several sessions (to 18 Nov 2026): 75 errors logged, none from Craftinator.
- Recorded vendors (pins, "seen for sale" lines) have not been checked in game yet.
- Faction-specific recipes are mostly not flagged. The client marks only the two Faction Banners
  (`SkillLineAbility.RaceMasks`); recipe items have no race limits, and Zockify only mentions
  factions in prose (which vendors sell a manual, a Horde quest reward). Checked 15 Nov 2026.
  Recorded vendor sightings are the likely way forward, but seeing a recipe at one side's vendor
  does not prove the other side lacks it.

## What is likely to come next

- Friends are installing the addon. Their `/ci export` text arrives pasted in chat or as
  "Submit data" issues on GitHub. Import it, rebuild, check the output, and cut a release.
- A friend levelling Leatherworking on Alliance was the first outside tester.
- If CurseForge moderators reject the project, they say why (usually description or logo);
  the description text is kept in `media/curseforge-description.md`.
