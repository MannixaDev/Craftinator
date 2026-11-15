Craftinator is a profession levelling planner for WoW Forever. It docks a panel to the profession window and builds a route from your current skill to your cap, priced with live auction data from your realm, so you can pick the cheapest or the quickest way to level.

## What it does

**Route:** the recipe to craft at each skill range, how many crafts to expect, and what it costs.

**Three modes:** Cheapest, Fastest (fewest crafts) and Balanced, with a slider for what one craft's time is worth to you.

**Live prices:** Auctionator first, then TSM. Vendor-sold reagents always use the vendor price.

**Your mats:** reagents already in your bags and bank count as free.

**Shopping list:** see what is left to buy, and send it to Auctionator with one click.

**Where to go:** names the trainer and supply vendors in your city and puts a map pin on the trainer.

**Recipe filters:** trainer, vendor and dropped recipes can each be switched on or off.

**Gathering:** for Herbalism, Mining and Fishing the panel lists where to go at your skill, what you can gather there, and what each item sells for raw or crafted (a bar, a cooked fish, a potion).

Professions covered: Alchemy, Blacksmithing, Cooking, Enchanting, Engineering, First Aid, Leatherworking and Tailoring, plus Herbalism, Mining and Fishing for gathering.

## How to use it

Open a profession and the panel appears beside it. Click a step to select that recipe. Type /ci to show or hide the panel, and /ci config for options.

Auctionator is optional but strongly recommended: without it only vendor prices are known.

## Known limits

This is an early release, tested on Alliance and Horde. The skill needed to learn some trainer recipes is not in the game files, so a few are estimates (the tooltip says when). The skill each fish needs is a rough guess, and Skinning is not covered yet.

## Helping with data

The addon notes what profession trainers teach and what supply vendors sell when you open their windows. Nothing about your character is recorded beyond its faction, and it can be switched off in the options. Type /ci export to copy that data and share it on the GitHub page, which is also the place for bug reports: https://github.com/MannixaDev/Craftinator

## Made with AI help

I develop Craftinator with help from AI: much of the code was written by Claude, an AI assistant made by Anthropic, working under my direction. I decide what goes in and test it in game.

## Credits

Recipe data is generated from the game client's data tables via wago.tools. Some learn skills and recipe sources come from Zockify, and trainer and vendor names from foreverdb.net.
