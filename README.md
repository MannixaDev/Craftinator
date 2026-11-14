# Craftinator

A profession levelling planner for WoW Forever. It docks a panel to the profession
window and builds a route from your current skill to your cap, priced with live
auction data from your realm, so you can pick the cheapest or the quickest way to level.

## What it does

- **Route:** the recipe to craft at each skill range, how many crafts to expect, and the cost.
- **Three modes:** Cheapest, Fastest (fewest crafts), and Balanced (a slider sets what one craft's time is worth).
- **Live prices:** Auctionator first, then TSM. Vendor-sold reagents always use the vendor price.
- **Your mats:** reagents in your bags and bank count as free (the bank is read when you open it).
- **Shopping list:** hover the footer to see what is left to buy; one click sends it to Auctionator.
- **Where to go:** names the trainer and supply vendors in your city and places a map pin on the trainer (TomTom if installed).
- **Recipe filters:** trainer, vendor and dropped recipes can each be switched on or off.

Professions covered: Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, First Aid,
Leatherworking and Tailoring.

## Install

1. Download the latest `Craftinator-v*.zip` from [Releases](https://github.com/MannixaDev/Craftinator/releases).
   (Do not use Code > Download ZIP: that is the development copy, with tests and tools mixed in.)
2. Unzip it and copy the `Craftinator` folder into
   `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game. [Auctionator](https://www.curseforge.com/wow/addons/auctionator) is
   optional but strongly recommended: without it only vendor prices are known.

## Use

Open a profession and the panel appears beside it. Click a step to select that recipe.

| Command | What it does |
| --- | --- |
| `/ci` | Show or hide the panel |
| `/ci config` | Open the options panel |
| `/ci send` | Send the shopping list to Auctionator |
| `/ci route`, `/ci list` | Print the route or the shopping list in chat |
| `/ci balance <silver>` | Set the Balanced value beyond the slider's range |
| `/ci export` | Show the trainer and vendor data recorded so far, ready to copy and share |

## Known limits

- Tested on an Alliance character only so far.
- The skill needed to learn some trainer recipes is not in the game files. Where no source
  has it, the addon assumes the recipe's yellow threshold and says so in the tooltip.
  Visiting a trainer records the real values (see Helping with data).
- Trainer positions are the Classic ones; most have not been checked on Forever.
- Supply vendors are named but cannot be pinned (no position data).
- Smelting (Mining) is not covered.

## Helping with data

The addon quietly records what profession trainers teach and what supply vendors sell
whenever you open their windows, along with where they stand. Nothing about your character
is recorded beyond its faction, and it can be switched off in `/ci config`.

To share it: type `/ci export`, press Ctrl+C, and paste the text into a
[Submit data](https://github.com/MannixaDev/Craftinator/issues/new/choose) issue.
Horde trainers and vendors are the biggest gap.

## Data and credits

- Recipes, reagents and skill thresholds are generated from the game client's data tables
  (via [wago.tools](https://wago.tools)) by the scripts in `tools/`.
- Learn skills and recipe sources that the client does not hold come from
  [Zockify](https://www.zockify.com/forever/professions/) and from trainers scanned in game.
- Trainer locations and vendor names come from [foreverdb.net](https://foreverdb.net).

## Development

`Optimiser.lua` and `Pricing.lua` are plain Lua with no game API calls and are unit-tested.

```
busted
luacheck .
```

See `tools/README.md` for regenerating the data after a game patch, and `SPEC.md` for the design.

## Licence

MIT. See `LICENSE`.
