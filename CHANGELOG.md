# Changelog

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
