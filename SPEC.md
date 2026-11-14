# ProfPlanner — WoW Forever Profession Levelling Addon Spec

Spec date: 13 Nov 2026 · Owner: Jack Smith-Morse

## Overview

ProfPlanner is an in-game profession levelling planner for WoW Forever. It builds a route from your current skill to the cap, priced with live Auctionator data, so you can choose the cheapest or the quickest way to level.

- **Problem:** profession guides live on websites (Wowhead and others), use fixed routes, and know nothing about prices on your realm or what is already in your bags.
- **Solution:** a panel docked to the profession window. It shows the next craft, how many to make, the mats needed, and the cost of the route, and it updates as you skill up.
- **Users:** levelling players who want a profession done without alt-tabbing; gold-conscious players who want the cheapest route; players short on time who want the fewest crafts.
- **Working name:** ProfPlanner (placeholder; rename freely).

## Platform constraints

WoW Forever runs on the modern (Midnight-era) client, loads Retail-style addons, and applies Midnight's addon restrictions ([Icy Veins](https://www.icy-veins.com/wow-forever/news/addons-in-wow-forever-blizzard-devs-just-addressed-the-big-question/), [Warcraft Tavern](https://www.warcrafttavern.com/forever/news/wow-forever-loads-your-retail-addons-keybinds/)). Those restrictions mostly target combat data, so a crafting planner that runs out of combat should be unaffected. Confirm that before building.

**Verify these before writing the data layer (Phase 0):**

- [ ] **Forever's profession changes:** Forever changed professions, and guides mention "blueprints" ([Mobalytics](https://mobalytics.gg/wow-forever/guides/wow-forever-all-new-profession-changes), [GuildOrder](https://guildorder.com/games/wow_forever/wiki/professions-camping-and-blueprints)). Check skill caps, brackets (Apprentice/Journeyman/…), and how recipes are learned.
- [ ] **Skill-up colours:** do the orange/yellow/green/grey thresholds and the skill-up chance formula still apply?
- [ ] **TradeSkill API:** which `C_TradeSkillUI` calls exist on the Forever client, and do they return recipe difficulty?
- [ ] **Interface number:** read it from `/dump select(4, GetBuildInfo())` in game for the `.toc` file.
- [ ] **Auctionator:** is there a version updated for Forever, and does its `API.v1` work there?
- [ ] **Game data:** does wago.tools (or similar) publish data tables for the Forever build?

## Features and user flow

**User flow:**

1. Open a profession window. The ProfPlanner panel docks to its right.
2. Read the current skill and the target (the next bracket cap or the max).
3. Pick a mode: Cheapest, Fastest, or Balanced (a slider).
4. The panel shows the route as steps: skill range, recipe, number of crafts, mats, and cost.
5. The current step is highlighted. Click it to select that recipe in the profession window.
6. When you skill up, the step counter and remaining cost update on their own.
7. Shopping list: mats for the rest of the route, minus what's already in your bags and bank. A button sends it to Auctionator.

**Feature list:**

| Feature | Phase | Notes |
| --- | --- | --- |
| Route panel docked to the profession window | MVP | One profession first |
| Live Auctionator pricing + total route cost | MVP | Show scan age |
| Faction filter + current-city trainer lookup | MVP | See Location-aware QoL |
| Minimap button / slash command `/pp` | MVP | Open without the profession window |
| Cheapest / Fastest / Balanced modes | v2 | Optimiser re-runs on change |
| Auto-advance on skill-up | v2 | `SKILL_LINES_CHANGED` |
| Bag + bank aware shopping list | v2 | Bank cached when opened |
| Recipe source filters (trainer / vendor / drop) | v2 | Drops excluded by default |
| City toasts + supply vendor locations | v2 | Location-aware QoL |
| Send shopping list to Auctionator | v3 | `API.v1` shopping list call |
| Resale value offsets craft cost | v3 | Toggle; uses output AH price |
| Recipe vendors + craft-station hints | v3 | Location-aware QoL |
| All professions + secondary skills | v3 | Data-driven, no code change per profession |

### Location-aware QoL

The addon knows your faction and where you are, so it can tell you where to train, shop, and craft without a website.

- **Faction:** read with `UnitFactionGroup("player")`. It filters recipes, trainers, and vendors to your side.
- **Current city and zone:** read with `C_Map.GetBestMapForUnit("player")`, plus `GetZoneText()` / `GetSubZoneText()`. Refresh on `ZONE_CHANGED_NEW_AREA` and `ZONE_CHANGED`.
- **Trainer finder:** "Your Tailoring trainer in Stormwind is <name>, Trade District". Clicking it places a map pin (`C_Map.SetUserWaypoint` + `C_SuperTrack`), or uses TomTom if it's installed.
- **Nearest option first:** if your city has no trainer for that profession, list the closest cities on your faction.
- **Training reminders:** "You're 5 points from the cap. Train Journeyman at <trainer>." Show a toast when you enter a city with a trainer you need.
- **Supply vendors:** where to buy vendor-only reagents (thread, vials, flux) in your current city.
- **Recipe vendors:** for vendor-bought recipes on the route, show the NPC, the zone, a pin, and the cost; flag limited-supply recipes.
- **Route stops:** when you're in a city, list everything you can do there for the current route: train, buy supplies, buy a recipe, AH, bank.
- **Craft-station checks:** flag recipes that need a forge or anvil and point to the nearest one.

**Extra data this needs** (hand-curated or from a community data source, per faction):

```lua
ProfPlanner.Data.NPCs = {
  { npcID = 1234, name = "Trainer Name", role = "trainer", profession = "Tailoring",
    maxSkill = 150, faction = "Alliance", mapID = 84, x = 0.43, y = 0.73, subzone = "Trade District" },
  { npcID = 5678, role = "supplies", sells = { 2320, 2321 }, faction = "Alliance", mapID = 84, x = 0.41, y = 0.71 },
}
```

*IDs and coordinates above are placeholders. Spawn positions aren't in DB2 exports, so this table will probably need hand-curating.*

## Data model and offline pipeline

Recipe data ships with the addon as generated Lua tables. Build it offline from game data tables, not by scraping guide sites: their routes are copyrighted, and the optimiser should produce the route itself.

**Pipeline (a Python script in `tools/`, not shipped):**

1. Pull DB2 exports for the Forever build (for example from wago.tools): SkillLineAbility, SpellReagents, the crafted item output, and trainer and vendor recipe sources.
2. Join them into one record per recipe and per profession.
3. Write `Data/Recipes_<Profession>.lua`. Commit the generated files and add a version stamp.
4. Re-run whenever the game patches.

**Recipe record:**

```lua
ProfPlanner.Data.Recipes["Engineering"] = {
  [spellID] = {
    name = "Rough Blasting Powder",
    output = { itemID = 4357, qty = 1 },
    reagents = { { itemID = 2835, qty = 1 } },
    learn = 1,   -- skill required to learn
    orange = 1, yellow = 20, green = 30, grey = 40,
    source = "trainer",  -- trainer | vendor | drop | quest
    sourceCost = 0,      -- copper, if bought
    faction = nil,       -- "Alliance" | "Horde" | nil
  },
}
```

**Other tables:**

- `Data.VendorPrices[itemID]`: vendor-sold reagents (thread, vials, flux) and their buy price. These items are never priced from the AH.
- `Data.Brackets[profession]`: skill caps and where you train.
- *Example values above are placeholders. Real numbers come from the pipeline.*

## Pricing integration

Prices come from Auctionator's public API when it's installed, with fallbacks so the addon still works without it. Mark Auctionator as `## OptionalDeps: Auctionator` in the `.toc`.

**Price lookup order for each reagent:**

1. Vendor-sold item: use `Data.VendorPrices` (always the cheapest and most reliable).
2. Auctionator: `Auctionator.API.v1.GetAuctionPriceByItemID("ProfPlanner", itemID)`.
3. TSM (optional): `TSM_API.GetCustomPriceValue("dbmarket", "i:" .. itemID)`.
4. Unknown: mark it "?" and leave it out of the total, with a warning that the total is incomplete.

**Other pricing rules:**

- **Scan age:** show it using `Auctionator.API.v1.GetAuctionAgeByItemID`. Prices older than 3 days get a stale marker.
- **Owned mats:** count at zero cost toward what you need (a toggle, since some players value them at market price).
- **Recipe purchases:** add the vendor recipe cost once, not per craft.
- **Caching:** cache prices per route calculation, not per frame. Recalculate when Auctionator finishes a scan or when the panel opens.
- **Shopping list:** `Auctionator.API.v1.CreateShoppingList("ProfPlanner", "ProfPlanner - Tailoring", searchStrings)`.

*Check the exact Auctionator API function names against the current Auctionator source before implementing.*

## Route optimiser

The optimiser picks, for each skill point, the recipe with the lowest expected cost to gain that point, then merges runs of the same recipe into steps.

**Chance of a skill-up at skill `s`** (orange = 100%, grey = 0%):

```
P(s) = 1                                   if s < yellow
P(s) = (grey - s) / (grey - yellow)        if yellow <= s < grey
P(s) = 0                                   if s >= grey
```

**Expected cost of one skill point with recipe `r` at skill `s`:**

```
C(r, s) = (matCost(r) - resale(r) * k) / P(s)  +  lambda / P(s)
```

- `matCost` = the sum of reagent prices. `resale` = the AH price of the output. `k` = 0 or 1 (the resale toggle).
- `lambda` = the time weight in copper per craft. Cheapest mode: 0. Fastest mode: very large, so it minimises crafts. Balanced: set by a slider.
- One-off costs (buying a recipe) are added the first time that recipe is chosen.

**Algorithm:**

1. For `s` from the current skill to the target, list the recipes that are known or learnable at `s` and that match your faction and source filters.
2. Dynamic programming over `s`: `best[s] = min over r of C(r, s) + best[s+1]`, including the one-off recipe cost if `r` is new. A greedy pass is fine for the MVP; DP handles recipe-cost trade-offs.
3. Merge consecutive points with the same recipe into steps: "Craft ~14 × Bolt of Linen Cloth (skill 1 → 10)".
4. Round the expected crafts up and show a range, since skill-ups are random.
5. Recalculate after each skill-up, so the route corrects itself after lucky or unlucky streaks.

**Fastest-mode extras:** penalise recipes with many distinct reagents or a craft station, and prefer reagents you already own.

## UI design

One panel docked to the profession window, styled like the default UI so it looks native.

**Panel layout, top to bottom:**

1. **Header:** profession icon, current/target skill with a progress bar, and the mode toggle (Cheapest · Balanced · Fastest).
2. **Location strip:** "Stormwind · Alliance" plus the things you can do here: trainer, supplies, AH. Each is clickable to place a map pin.
3. **Route list:** a scrolling list of steps. Each row shows the skill range, recipe icon and name, crafts needed, and step cost. The current step is highlighted; done steps are dimmed.
4. **Step detail:** the selected step's reagents, with have/need counts and prices. A "Select recipe" button jumps to it in the profession window.
5. **Footer:** remaining route cost, price scan age, and "Shopping list" / "Send to Auctionator" buttons.

**UI rules:**

- Tooltips on recipes: skill-up colour now and the chance of a skill-up.
- Colour each step by the recipe's difficulty at that skill (orange/yellow/green), matching the game.
- Also openable on its own with `/pp` or a minimap button, for planning away from the trainer.
- Settings panel: price source, resale toggle, owned-mats toggle, source filters, Balanced slider, and toast on/off.
- Build with frame templates and `ScrollBox` (the modern list API), not old FauxScrollFrame.

## File structure, events, SavedVariables

```
ProfPlanner/
  ProfPlanner.toc        -- Interface number, OptionalDeps: Auctionator, TomTom
  Core.lua               -- namespace, event dispatcher, slash commands
  Player.lua             -- faction, location, skill levels, known recipes
  Inventory.lua          -- bag + bank counts (bank cached on BANKFRAME_OPENED)
  Pricing.lua            -- price lookup chain + cache
  Optimiser.lua          -- skill-up chance, cost model, DP, step merging
  Navigation.lua         -- trainer/vendor lookup, map pins, city toasts
  UI/Panel.lua           -- docked panel, route list, step detail
  UI/Settings.lua        -- options panel
  Data/Recipes_*.lua     -- generated, one per profession
  Data/NPCs.lua          -- trainers, supply + recipe vendors
  Data/VendorPrices.lua
tools/                   -- offline Python data pipeline (not shipped)
spec/                    -- busted unit tests for Optimiser and Pricing
```

**Events:**

| Event | Used for |
| --- | --- |
| `ADDON_LOADED` / `PLAYER_LOGIN` | Init, load SavedVariables, read faction |
| `TRADE_SKILL_SHOW` / `TRADE_SKILL_CLOSE` | Dock and undock the panel |
| `TRADE_SKILL_LIST_UPDATE` | Refresh known recipes |
| `SKILL_LINES_CHANGED` | Skill-up: advance the step, recalculate |
| `BAG_UPDATE_DELAYED` | Recount owned mats |
| `BANKFRAME_OPENED` | Cache bank contents |
| `ZONE_CHANGED_NEW_AREA` / `ZONE_CHANGED` | Update the location strip, city toasts |
| Auctionator scan-complete callback | Clear the price cache, recalculate |

**SavedVariables:**

- `ProfPlannerDB` (account-wide): settings, panel position, mode.
- `ProfPlannerCharDB` (per character): bank snapshot, last route, and dismissed toasts.

## Roadmap and acceptance criteria

Build in four phases. Each phase is playable on its own before the next starts.

| Phase | Scope | Done when |
| --- | --- | --- |
| 0. Spike | Confirm the open questions in Platform constraints; prototype the data pipeline for one profession | The `.toc` loads on Forever, recipe difficulty is readable in game, and the Auctionator call returns a price |
| 1. MVP | One profession, greedy route, Auctionator prices, docked panel, faction filter, current-city trainer lookup, `/pp` | A route from 1 to the first cap shows with a total cost, and the trainer pin works in your faction's capital |
| 2. v2 | Cheapest/Fastest/Balanced + DP, auto-advance, bag/bank-aware mats, source filters, city toasts, supply vendors | Switching modes changes the route; a skill-up advances the step without a reload |
| 3. v3 | All professions, shopping list to Auctionator, resale offset, recipe vendors, craft-station hints, settings panel | Every profession has generated data; one click creates an Auctionator list |

**Test checklist for each phase:**

- [ ] No Lua errors with BugSack/BugGrabber over a full levelling session.
- [ ] Works with Auctionator missing (falls back, warns).
- [ ] Tested on both an Alliance and a Horde character.
- [ ] No frame-rate drop from recalculating (profile the optimiser; keep it under 50 ms).

## Engineering rules for Claude Code

- **Keep logic testable outside the game:** `Optimiser.lua` and `Pricing.lua` must be plain Lua with no WoW API calls, so they can be unit-tested with `busted` and a stubbed price table.
- **Wrap the WoW API:** put every WoW API call behind small adapter functions in `Player.lua` / `Inventory.lua` / `Navigation.lua`. Forever-specific API differences are then fixed in one place.
- **Linting:** use `luacheck` with WoW globals, and add a GitHub Actions workflow that runs it and the tests.
- **Releases:** the BigWigs packager can publish to CurseForge/Wago later.
- **Data first:** don't hand-write recipe tables; get the pipeline working early, even for one profession.
- **Don't guess APIs:** where an API name in this spec is uncertain (Auctionator, `C_TradeSkillUI`), check the source or warcraft.wiki.gg and ask before assuming.
- **Install path for testing:** `World of Warcraft/<Forever client folder>/Interface/AddOns/ProfPlanner`. Check the exact client folder name on the machine.

## Sources

- [Icy Veins: Addons in WoW Forever](https://www.icy-veins.com/wow-forever/news/addons-in-wow-forever-blizzard-devs-just-addressed-the-big-question/)
- [Warcraft Tavern: WoW Forever loads your Retail addons](https://www.warcrafttavern.com/forever/news/wow-forever-loads-your-retail-addons-keybinds/)
- [Mobalytics: WoW Forever profession changes](https://mobalytics.gg/wow-forever/guides/wow-forever-all-new-profession-changes)
- [GuildOrder: Professions, camping and blueprints](https://guildorder.com/games/wow_forever/wiki/professions-camping-and-blueprints)
