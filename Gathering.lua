-- Gathering.lua: what to gather at your skill, where, and what it is worth.
-- Plain Lua only: data, prices and recipes are passed in, no WoW API calls here.

local _, ns = ...

local Gathering = {}
if type(ns) == "table" then ns.Gathering = Gathering end

-- A node turns yellow 25 points above its skill, green at 50 and grey at 100 (as in Classic).
local YELLOW, GREEN, GREY = 25, 50, 100

--- The bracket for a skill: the last one starting at or below it.
function Gathering.Bracket(data, skill)
  local found = data.brackets[1]
  for _, bracket in ipairs(data.brackets) do
    if skill >= bracket.from then found = bracket end
  end
  return found
end

--- Zones of a bracket for a faction: that faction's zones, then the shared ones.
function Gathering.Zones(bracket, faction)
  local zones = {}
  for _, key in ipairs({ faction, "both" }) do
    for _, zone in ipairs(bracket[key] or {}) do zones[#zones + 1] = zone end
  end
  return zones
end

--- "red" (cannot gather yet), "orange", "yellow", "green" or "grey".
function Gathering.Difficulty(nodeSkill, skill)
  local above = skill - nodeSkill
  if above < 0 then return "red" end
  if above < YELLOW then return "orange" end
  if above < GREEN then return "yellow" end
  if above < GREY then return "green" end
  return "grey"
end

--- Index of recipes by reagent: { [itemID] = { { profession, spellID, recipe, qty }, ... } }.
function Gathering.UsesIndex(recipesByProfession)
  local index = {}
  for profession, recipes in pairs(recipesByProfession) do
    for spellID, recipe in pairs(recipes) do
      if recipe.output then
        for _, reagent in ipairs(recipe.reagents or {}) do
          local list = index[reagent.itemID] or {}
          index[reagent.itemID] = list
          list[#list + 1] = { profession = profession, spellID = spellID, recipe = recipe, qty = reagent.qty }
        end
      end
    end
  end
  return index
end

--- Crafted uses of an item, best first: what one raw item is worth when crafted.
-- value = (crafted item price x output count - other reagents' cost) / raw items used.
-- Uses whose crafted item or other reagents have no price are left out.
function Gathering.Uses(itemID, index, priceOf)
  local uses = {}
  for _, use in ipairs(index[itemID] or {}) do
    local recipe = use.recipe
    local outPrice = priceOf(recipe.output.itemID)
    if outPrice then
      local value = outPrice * (recipe.output.qty or 1)
      for _, reagent in ipairs(recipe.reagents) do
        if reagent.itemID ~= itemID then
          local price = priceOf(reagent.itemID)
          if not price then value = nil break end
          value = value - price * reagent.qty
        end
      end
      if value and value > 0 then
        uses[#uses + 1] = { value = value / use.qty, profession = use.profession, spellID = use.spellID, recipe = recipe }
      end
    end
  end
  table.sort(uses, function(a, b) return a.value > b.value end)
  return uses
end

--- Entries for the gathering list.
-- opts: { profession, data, skill, faction, priceOf, index }
-- Herbalism and Mining list the bracket's nodes; Fishing lists every known fish.
-- Each entry: { itemID, name, skill, difficulty, price, uses, where, worth }.
function Gathering.List(opts)
  local data, entries = opts.data, {}
  local function add(item)
    item.price = opts.priceOf(item.itemID)
    item.uses = Gathering.Uses(item.itemID, opts.index, opts.priceOf)
    local best = item.uses[1] and item.uses[1].value
    item.worth = math.max(item.price or 0, best or 0)
    entries[#entries + 1] = item
  end
  local bracket = Gathering.Bracket(data, opts.skill)
  if data.nodes then
    local byName = {}
    for _, node in ipairs(data.nodes) do byName[node.name] = node end
    for _, name in ipairs(bracket.nodes or {}) do
      local node = byName[name]
      if node then
        add({ itemID = node.itemID, name = node.name, skill = node.skill,
          difficulty = Gathering.Difficulty(node.skill, opts.skill) })
      end
    end
  else
    for _, fish in ipairs(data.fish or {}) do
      add({ itemID = fish.itemID, where = fish.where })
    end
  end
  -- What you can gather now first, most valuable first; locked nodes after, by skill.
  table.sort(entries, function(a, b)
    local aLocked, bLocked = a.difficulty == "red", b.difficulty == "red"
    if aLocked ~= bLocked then return bLocked end
    if aLocked then return a.skill < b.skill end
    if a.worth ~= b.worth then return a.worth > b.worth end
    return a.itemID < b.itemID
  end)
  return entries, bracket
end

return Gathering
