# Changelog

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
