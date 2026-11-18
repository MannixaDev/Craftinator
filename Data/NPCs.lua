-- Data/NPCs.lua: trainers, supply vendors, recipe vendors (per faction).
-- Hand-curated: spawn positions are not in the client data.
-- Capital-city profession trainers. Names and coordinates are the Classic locations as
-- listed by foreverdb.net. Checked in game: Georgio Bolero, Sellandus, Stephen Ryback, Shaina Fuller.
-- maxSkill is the Classic cap each rank trains to (Journeyman 150, Expert 225, Artisan 300).
-- Cooking and First Aid trainers are listed at 150: in Classic the higher ranks come from books.
-- Specialisation trainers (armoursmith, weaponsmith, gnomish/goblin engineering) are left out.
-- Supply vendors: names and titles as listed for Forever by foreverdb.net (vendors by zone).
-- That list has no positions, so these have no x/y and cannot be pinned on the map.

local _, ns = ...

ns.Data.Cities = {
  [1453] = "Stormwind City",
  [1455] = "Ironforge",
  [1457] = "Darnassus",
  [1454] = "Orgrimmar",
  [1456] = "Thunder Bluff",
  [1458] = "Undercity",
}

local CITY = {
  SW = { 1453, "Alliance" }, IF = { 1455, "Alliance" }, DN = { 1457, "Alliance" },
  OG = { 1454, "Horde" }, TB = { 1456, "Horde" }, UC = { 1458, "Horde" },
}
local RANK = { J = { "Journeyman", 150 }, E = { "Expert", 225 }, A = { "Artisan", 300 }, T = { "Trainer", 150 } }

ns.Data.NPCs = {}

-- Ranks that are learned from a book, not a trainer: [profession][cap the book raises you from].
-- Sellers as listed for Forever by foreverdb.net ("seen in WoW Forever"); cost in copper.
-- Each seller: name, zone, map ID, and x, y (map percentages) where a source gives them:
-- Dirge Quikcleave from wow-professions.com, Nat Pagle and Doctor Gregory Victor from
-- warcraft.wiki.gg. A position recorded in game for the same name is used first.
ns.Data.RankBooks = {
  Cooking = {
    [150] = { item = "Expert Cookbook", itemID = 16072, cost = 10000, needsSkill = 125,
              Alliance = { "Shandrina", "Ashenvale", 1440 }, Horde = { "Wulan", "Desolace", 1443 } },
    -- Artisan: a quest in the Gadgetzan inn (wow-professions.com, icy-veins guides). Quest and giver seen in game, Nov 2026.
    [225] = { quest = "Clamlette Surprise", needsSkill = 225, needsLevel = 35,
              note = "Bring 12 Giant Eggs, 10 Zesty Clam Meat and 20 Alterac Swiss.",
              Alliance = { "Dirge Quikcleave", "Tanaris", 1446, 52.6, 28.0 },
              Horde = { "Dirge Quikcleave", "Tanaris", 1446, 52.6, 28.0 } },
  },
  ["First Aid"] = {
    [150] = { item = "Expert First Aid - Under Wraps", itemID = 16084, cost = 10000, needsSkill = 125,
              Alliance = { "Deneb Walker", "Arathi Highlands", 1417 },
              Horde = { "Balai Lok'Wein", "Dustwallow Marsh", 1445 } },
    -- Artisan: the Triage quest (Classic givers; the Forever guide had not tested it).
    [225] = { quest = "Triage", needsSkill = 225, needsLevel = 35,
              Alliance = { "Doctor Gustaf VanHowzen", "Dustwallow Marsh", 1445 },
              Horde = { "Doctor Gregory Victor", "Arathi Highlands", 1417, 73.0, 36.0 } },
  },
  -- Fishing trainers stop at Journeyman (wow-professions.com's Forever guide). Expert is a book
  -- sold in Booty Bay; Artisan is Nat Pagle's quest (level 35). Both confirmed in game, Nov 2026.
  Fishing = {
    [150] = { item = "Expert Fishing - The Bass and You", itemID = 16083, cost = 10000, needsSkill = 125,
              Alliance = { "Old Man Heming", "Stranglethorn Vale", 1434 },
              Horde = { "Old Man Heming", "Stranglethorn Vale", 1434 } },
    [225] = { quest = "Nat Pagle, Angler Extreme", needsSkill = 225, needsLevel = 35,
              Alliance = { "Nat Pagle", "Dustwallow Marsh", 1445, 58.6, 60.2 },
              Horde = { "Nat Pagle", "Dustwallow Marsh", 1445, 58.6, 60.2 } },
  },
}

-- Each entry: name, rank letter, city code, x, y (map percentages), and optionally the skill
-- cap the trainer was seen to train to in game, which on Forever can be lower than the rank suggests.
local function trainers(profession, list)
  for _, t in ipairs(list) do
    local rank, city = RANK[t[2]], CITY[t[3]]
    ns.Data.NPCs[#ns.Data.NPCs + 1] = {
      name = t[1], role = "trainer", profession = profession, rank = rank[1], maxSkill = t[6] or rank[2],
      faction = city[2], mapID = city[1], x = t[4] / 100, y = t[5] / 100,
    }
  end
end

trainers("Tailoring", {
  { "Lawrence Schneider", "J", "SW", 53.5, 81.6 }, { "Sellandus", "E", "SW", 52.3, 83.3, 150 },
  { "Georgio Bolero", "A", "SW", 53.2, 81.4, 225 },
  { "Uthrar Threx", "J", "IF", 43.6, 27.9 }, { "Jormund Stonebrow", "E", "IF", 43.2, 29.0 },
  { "Trianna", "J", "DN", 63.5, 21.2 }, { "Me'lynn", "E", "DN", 63.6, 22.4 },
  { "Snang", "J", "OG", 63.0, 49.7 }, { "Magar", "E", "OG", 63.4, 50.0 },
  { "Vhan", "J", "TB", 44.1, 45.1 }, { "Tepa", "E", "TB", 44.1, 45.1 },
  { "Victor Ward", "J", "UC", 70.4, 29.7 }, { "Rhiannon Davis", "E", "UC", 70.2, 30.1 },
  { "Josef Gregorian", "A", "UC", 70.8, 30.7 },
})

trainers("Alchemy", {
  { "Tel'Athir", "J", "SW", 55.6, 85.7 }, { "Lilyssia Nightbreeze", "E", "SW", 55.6, 85.8 },
  { "Vosur Brakthel", "J", "IF", 66.3, 55.5 }, { "Tally Berryfizz", "E", "IF", 66.5, 55.3 },
  { "Milla Fairancora", "J", "DN", 55.2, 23.0 }, { "Sylvanna Forestmoon", "E", "DN", 56.3, 24.1 },
  { "Ainethil", "A", "DN", 55.0, 24.0 },
  { "Whuut", "J", "OG", 56.1, 33.0 }, { "Yelmak", "E", "OG", 56.7, 33.5 },
  { "Kray", "J", "TB", 46.9, 34.1 }, { "Bena Winterhoof", "E", "TB", 46.7, 33.6 },
  { "Doctor Martin Felben", "J", "UC", 46.7, 74.5 }, { "Doctor Marsh", "E", "UC", 51.5, 74.3 },
  { "Doctor Herbert Halsey", "A", "UC", 47.9, 73.0 },
})

trainers("Blacksmithing", {
  { "Dane Lindgren", "J", "SW", 64.0, 37.2 }, { "Therum Deepforge", "E", "SW", 63.7, 37.3 },
  { "Groum Stonebeard", "J", "IF", 52.0, 41.9 }, { "Rotgath Stonebeard", "E", "IF", 52.1, 42.5 },
  { "Bengus Deepforge", "A", "IF", 52.5, 41.5 },
  { "Ug'thok", "J", "OG", 80.6, 23.3 }, { "Snarl", "E", "OG", 79.9, 23.3 },
  { "Saru Steelfury", "A", "OG", 82.3, 23.0 },
  { "Thrag Stonehoof", "J", "TB", 39.3, 56.5 }, { "Karn Stonehoof", "E", "TB", 39.4, 55.1 },
  { "Basil Frye", "J", "UC", 60.1, 28.7 }, { "James Van Brunt", "E", "UC", 61.1, 30.2 },
})

trainers("Enchanting", {
  { "Betty Quin", "J", "SW", 53.0, 73.8 }, { "Lucan Cordell", "E", "SW", 53.1, 74.3 },
  { "Thonys Pillarstone", "J", "IF", 60.5, 44.8 }, { "Gimble Thistlefuzz", "E", "IF", 59.8, 45.4 },
  { "Lalina Summermoon", "J", "DN", 59.0, 12.9 }, { "Taladan", "E", "DN", 58.4, 13.1 },
  { "Jhag", "J", "OG", 53.6, 38.3 }, { "Godan", "E", "OG", 53.7, 38.3 },
  { "Mot Dawnstrider", "J", "TB", 45.2, 38.7 }, { "Teg Dawnstrider", "E", "TB", 44.9, 37.5 },
  { "Malcomb Wynn", "J", "UC", 62.1, 60.3 }, { "Lavinia Crowe", "E", "UC", 62.3, 61.7 },
})

trainers("Engineering", {
  { "Sprite Jumpsprocket", "J", "SW", 61.9, 30.9 }, { "Lilliam Sparkspindle", "E", "SW", 62.1, 30.6 },
  { "Jemma Quikswitch", "J", "IF", 68.1, 44.4 }, { "Trixie Quikswitch", "E", "IF", 67.8, 43.2 },
  { "Springspindle Fizzlegear", "A", "IF", 68.5, 43.5 },
  { "Thund", "J", "OG", 76.0, 24.1 }, { "Nogg", "E", "OG", 76.0, 25.0 }, { "Roxxik", "A", "OG", 76.2, 25.2 },
  { "Graham Van Talen", "J", "UC", 75.3, 73.1 }, { "Franklin Lloyd", "E", "UC", 76.1, 74.0 },
})

trainers("Leatherworking", {
  { "Randal Worth", "J", "SW", 72.2, 62.7 }, { "Simon Tanner", "E", "SW", 71.9, 62.8 },
  { "Gretta Finespindle", "J", "IF", 39.2, 33.4 }, { "Fimble Finespindle", "E", "IF", 39.8, 33.5 },
  { "Darianna", "J", "DN", 64.5, 21.0 }, { "Faldron", "E", "DN", 64.4, 21.8 }, { "Telonis", "A", "DN", 64.2, 21.6 },
  { "Kamari", "J", "OG", 63.0, 44.9 }, { "Karolek", "E", "OG", 62.8, 44.4 },
  { "Mak", "J", "TB", 42.3, 43.2 }, { "Tarn", "E", "TB", 42.3, 42.9 }, { "Una", "A", "TB", 41.5, 42.6 },
  { "Dan Golthas", "J", "UC", 70.8, 58.5 }, { "Arthur Moore", "E", "UC", 70.3, 57.8 },
})

trainers("Cooking", {
  { "Stephen Ryback", "T", "SW", 78.2, 53.2, 150 }, { "Daryl Riknussun", "T", "IF", 60.0, 36.6 },
  { "Alegorn", "T", "DN", 48.8, 21.5 },
  { "Zamja", "T", "OG", 57.4, 53.9 }, { "Aska Mistrunner", "T", "TB", 50.8, 52.2 },
  { "Eunice Burch", "T", "UC", 62.2, 44.8 },
})

trainers("First Aid", {
  { "Shaina Fuller", "T", "SW", 53.0, 44.7, 150 }, { "Nissa Firestone", "T", "IF", 54.8, 58.5 },
  { "Dannelor", "T", "DN", 51.7, 12.5 },
  { "Arnok", "T", "OG", 34.3, 84.5 }, { "Pand Stonebinder", "T", "TB", 29.5, 21.6 },
  { "Mary Edras", "T", "UC", 73.4, 55.8 },
})

-- Gathering trainers. Names: Zockify and wow-professions.com Forever guides; positions:
-- warcraft.wiki.gg (unchecked on Forever). City trainers teach Herbalism and Mining to Artisan.
trainers("Herbalism", {
  { "Tannysa", "A", "SW", 54.5, 84.0 }, { "Reyna Stonebranch", "A", "IF", 55.7, 58.8 },
  { "Firodren Mooncaller", "A", "DN", 48.0, 68.4 },
  { "Jandi", "A", "OG", 34.7, 63.1 }, { "Komin Winterhoof", "A", "TB", 49.9, 39.9 },
  { "Martha Alliestar", "A", "UC", 54.2, 49.8 },
})

trainers("Mining", {
  { "Gelman Stonehand", "A", "SW", 59.2, 37.7 }, { "Geofram Bouldertoe", "A", "IF", 53.0, 26.0 },
  { "Foreman Pernic", "A", "DN", 50.6, 33.8 },
  { "Makaru", "A", "OG", 73.1, 26.5 }, { "Brek Stonehoof", "A", "TB", 34.0, 57.0 },
  { "Brom Killian", "A", "UC", 55.8, 37.0 },
})

trainers("Fishing", {
  { "Arnold Leland", "J", "SW", 55.1, 69.5 }, { "Grimnur Stonebrand", "J", "IF", 48.5, 6.5 },
  { "Astaia", "J", "DN", 47.6, 56.7 },
  { "Lumak", "J", "OG", 66.6, 41.6 }, { "Kah Mistrunner", "J", "TB", 56.1, 47.0 },
  { "Armand Cromwell", "J", "UC", 80.9, 31.2 },
})

-- Each entry: name, title, city code, profession (nil = general trade goods).
local function supplies(list)
  for _, v in ipairs(list) do
    local city = CITY[v[3]]
    ns.Data.NPCs[#ns.Data.NPCs + 1] = {
      name = v[1], role = "supplies", title = v[2], profession = v[4], faction = city[2], mapID = city[1],
    }
  end
end

supplies({
  { "Edna Mullby", "Trade Supplier", "SW" },
  { "Alexandra Bolero", "Tailoring Supplies", "SW", "Tailoring" },
  { "Jillian Tanner", "Leatherworking Supplies", "SW", "Leatherworking" },
  { "Kaita Deepforge", "Blacksmithing Supplies", "SW", "Blacksmithing" },
  { "Maria Lumere", "Alchemy Supplies", "SW", "Alchemy" },
  { "Jessara Cordell", "Enchanting Supplies", "SW", "Enchanting" },
  { "Billibub Cogspinner", "Engineering Supplier", "SW", "Engineering" },
  { "Erika Tate", "Cooking Supplier", "SW", "Cooking" },

  { "Burbik Gearspanner", "Trade Supplier", "IF" }, { "Fillius Fizzlespinner", "Trade Supplier", "IF" },
  { "Poranna Snowbraid", "Tailoring Supplies", "IF", "Tailoring" },
  { "Bombus Finespindle", "Leatherworking Supplies", "IF", "Leatherworking" },
  { "Thurgrum Deepforge", "Blacksmithing Supplies", "IF", "Blacksmithing" },
  { "Soolie Berryfizz", "Alchemy Supplies", "IF", "Alchemy" },
  { "Tilli Thistlefuzz", "Enchanting Supplies", "IF", "Enchanting" },
  { "Gearcutter Cogspinner", "Engineering Supplies", "IF", "Engineering" },
  { "Emrul Riknussun", "Cooking Supplier", "IF", "Cooking" },

  { "Mythrin'dir", "General Trade Supplier", "DN" },
  { "Elynna", "Tailoring Supplies", "DN", "Tailoring" },
  { "Saenorion", "Leatherworking Supplies", "DN", "Leatherworking" },
  { "Ulthir", "Alchemy Supplies", "DN", "Alchemy" },
  { "Vaean", "Enchanting Supplies", "DN", "Enchanting" },
  { "Fyldan", "Cooking Supplier", "DN", "Cooking" },

  { "Felika", "General Trade Goods Merchant", "OG" }, { "Shimra", "General Trade Goods Merchant", "OG" },
  { "Borya", "Tailoring Supplies", "OG", "Tailoring" },
  { "Tamar", "Leatherworking Supplies", "OG", "Leatherworking" },
  { "Sumi", "Blacksmithing Supplier", "OG", "Blacksmithing" },
  { "Kor'geld", "Alchemy Supplies", "OG", "Alchemy" },
  { "Kithas", "Enchanting Supplies", "OG", "Enchanting" },
  { "Sovik", "Engineering Supplies", "OG", "Engineering" },
  { "Xen'to", "Cooking Supplier", "OG", "Cooking" },

  { "Shadi Mistrunner", "Trade Goods Supplier", "TB" },
  { "Mahu", "Leatherworking & Tailoring Supplies", "TB", "Tailoring" },
  { "Mahu", "Leatherworking & Tailoring Supplies", "TB", "Leatherworking" },
  { "Taur Stonehoof", "Blacksmithing Supplies", "TB", "Blacksmithing" },
  { "Mani Winterhoof", "Alchemy Supplies", "TB", "Alchemy" },
  { "Nata Dawnstrider", "Enchanting Supplies", "TB", "Enchanting" },
  { "Naal Mistrunner", "Cooking Supplier", "TB", "Cooking" },

  { "Daniel Bartlett", "General Trade Supplier", "UC" }, { "Felicia Doan", "General Trade Goods Vendor", "UC" },
  { "Millie Gregorian", "Tailoring Supplies", "UC", "Tailoring" },
  { "Joseph Moore", "Leatherworking Supplies", "UC", "Leatherworking" },
  { "Samuel Van Brunt", "Blacksmithing Supplier", "UC", "Blacksmithing" },
  { "Algernon", "Alchemy Supplies", "UC", "Alchemy" },
  { "Thaddeus Webb", "Enchanting Supplies", "UC", "Enchanting" },
  { "Elizabeth Van Talen", "Engineering Supplier", "UC", "Engineering" },
  { "Ronald Burch", "Cooking Supplier", "UC", "Cooking" },
})
