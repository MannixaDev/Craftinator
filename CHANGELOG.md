# Changelog

## 0.6.7

- New: below a skill cap of 300, a line above the total shows roughly what it costs to go all the
  way to 300. Hover it to see the cost for each rank, the crafts and the recipes to buy on the way.
  It is a rough guide: later materials may have old or no auction prices, and training fees for the
  next ranks are not included.
- Fixed: Enchanting trainers in the cities (such as Lucan Cordell in Stormwind) only teach up to
  150 on Forever. Past 150 the panel now sends you to an Expert trainer: Kitta Firewind in Elwynn
  Forest, Vanessa Sellers in Dalaran or Melanie Sable in Riverglades for Alliance, Hgarth above
  Sun Rock Retreat for Horde.
- More trainers, vendors and recipe details recorded in game.

## 0.6.6

- New: at skill 300 the panel lists the 10 most profitable crafts you know. Materials in your bags
  and bank count as free, so each row shows what one craft earns and how many your materials cover.
  Hover a row for the profit if you bought everything, and the materials with what you have.
  Click it to select the recipe.
- Resale and the new profit list take off the auction house's 5% cut, so they show what a sale
  really pays you.

## 0.6.5

- Cooking and First Aid past 225: at the cap, the panel names the quest that raises it (Clamlette
  Surprise from Dirge Quikcleave in Tanaris for Cooking, Triage for First Aid) and what to bring.
- The skill cap hint is now readable in full: it shows in the message area at the cap and in a
  tooltip when you hover it. Left-click it to put a map pin on the trainer, book seller or quest
  giver, where their position is known. At 300 it no longer shows.
- Enchanting: when a step needs a rod you do not have (such as a Runed Copper Rod), the route adds
  a "Make first" step for it.
- Recipes sold only by vendors of the other faction are planned with their auction house price
  instead, or skipped if none is listed, and those vendors are hidden from the tooltip.
- Fires and other crafting stations are also remembered when you open the profession window
  next to one, not only when you craft there.

## 0.6.4

- Fixed: with "Owned" ticked, materials already in your bags could stretch a recipe far into its
  grey range (for example Bristle Whisker Catfish all the way to 180 in 138 crafts). The route now
  uses what you own, then switches to the next recipe when that really is cheaper.
- Hovering a recipe you have not learned lists the vendors who sell it and their zones, yours first
  in green, and shows its auction house price, marked when it is cheaper than the vendor.
- Recipes cooked at a fire suggest making a Basic Campfire, and name the nearest fire or other
  crafting station you have used before, with the distance. The addon remembers where you craft
  (not fires you build yourself).
- Herbalism, Mining and Fishing: near your skill cap, the panel says how to raise it: the trainer,
  or for Fishing the book from Old Man Heming in Booty Bay (past 150) and Nat Pagle's quest in
  Dustwallow Marsh (past 225, level 35). Both checked in game.

## 0.6.3

- New: Herbalism, Mining and Fishing get their own view in the panel. It lists the zones to go to
  at your skill, what you can gather there (colour shows how well it still levels you), and what
  each item sells for, raw or crafted into something (a bar, a cooked fish, a potion).
  Zones and skill levels come from Zockify's guides. For fish, the skill is a rough guess from
  their cooking recipes; fish for later skill bands are listed as "later".
- Thunder Bluff recorded: Leatherworking trainers (Tarn teaches up to 150), the First Aid
  trainer and the leatherworking supplies vendor, so Horde "train here" hints point to the
  right place.
- Elemental Flux is priced at the vendor instead of the auction house.

## 0.6.2

- Fixed: reagents that vendors sell in bundles of five (vials, spices, Refreshing Spring Water,
  Ice Cold Milk, Shiny Red Apples) were priced as if each one cost the whole bundle. Routes using them,
  mostly Alchemy, are now cheaper and more accurate.
- The first Horde trainers and vendors recorded by players: Waldor in Wailing Caverns, and vendors at
  Sun Rock Retreat and Camp Taurajo. More Alliance vendors in Stormwind and Southshore.
- Leatherworking: real learn skills and fees for 46 recipes from Stormwind's trainer, who teaches up
  to 150.
- More reagents get a vendor price instead of an auction price, such as Simple Flour, Maple Seed and
  Nightcrawlers.
- Tailoring: you are only offered your own faction's Faction Banner.
- Prices and fees always use the full price, even when the character who recorded them had a
  reputation discount.

## 0.6.1

- First release packaged on CurseForge. No changes in game.

## 0.6.0

- Recipes that need a tool (hammer, rod, spanner) say so in the step tooltip.
- Trainers and vendors recorded by players replace the old guesses: correct positions and skill caps.
- Right-click the location line to put a map pin on a recorded vendor.
- Recipe tooltips show which vendor a recipe was seen for sale at.

## 0.5.0

- Renamed from ProfPlanner to Craftinator. Settings start fresh under the new name. Use `/ci` or
  `/craftinator`; `/pp` still works.
- Cooking and First Aid past 150 point you to the book you need, not a trainer who can't teach it.
- First Aid learn skills and fees recorded in game.

## 0.4.0

- Records the trainers and vendors you visit (can be turned off in options). Share them with
  `/ci export` to improve the data for everyone.

## 0.3.0

- First public release: a panel beside the profession window plans the cheapest or fastest route to
  your target skill, priced with Auctionator, and can send the shopping list to Auctionator.
