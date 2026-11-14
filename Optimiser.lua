-- Optimiser.lua: skill-up chance, cost model, greedy route builder, step merging.
-- Plain Lua only: no WoW API calls in this file, so busted can load it directly.
-- All money values are in copper.

local _, ns = ...

local Optimiser = {}
if type(ns) == "table" then ns.Optimiser = Optimiser end

local ceil, huge = math.ceil, math.huge
local EPSILON = 1e-9

-- Time weight (copper per craft) for the two fixed modes. Balanced uses a slider value.
Optimiser.LAMBDA = { cheapest = 0, fastest = 1e9 }

--- Chance (0..1) that crafting `recipe` at `skill` gives a skill point.
function Optimiser.SkillUpChance(recipe, skill)
  local yellow, grey = recipe.yellow, recipe.grey
  if skill >= grey then return 0 end
  if skill < yellow then return 1 end
  return (grey - skill) / (grey - yellow)
end

--- "orange" | "yellow" | "green" | "grey", matching the in-game recipe colour.
function Optimiser.Difficulty(recipe, skill)
  if skill >= recipe.grey then return "grey" end
  if skill >= recipe.green then return "green" end
  if skill >= recipe.yellow then return "yellow" end
  return "orange"
end

--- Sum of reagent prices for one craft.
-- priceOf(itemID) returns copper, or nil when the price is unknown.
-- Returns total, unknown: unknown is nil or a list of itemIDs that had no price
-- (those reagents are left out of the total).
function Optimiser.MatCost(recipe, priceOf)
  local total, unknown = 0, nil
  for _, reagent in ipairs(recipe.reagents or {}) do
    local price = priceOf and priceOf(reagent.itemID)
    if price then
      total = total + price * reagent.qty
    else
      unknown = unknown or {}
      unknown[#unknown + 1] = reagent.itemID
    end
  end
  return total, unknown
end

--- Net copper spent per craft: matCost - resale * k.
-- opts.priceOf, opts.resaleOf: function(itemID) -> copper or nil
-- opts.useResale: the resale toggle (k = 1 when true, else 0)
function Optimiser.CraftCost(recipe, opts)
  local cost, unknown = Optimiser.MatCost(recipe, opts.priceOf)
  if opts.useResale and opts.resaleOf and recipe.output then
    local resale = opts.resaleOf(recipe.output.itemID)
    if resale then
      cost = cost - resale * (recipe.output.qty or 1)
    end
  end
  return cost, unknown
end

--- Time weight of one craft of this recipe, in copper: lambda, scaled by
-- opts.timeFactorOf(spellID, recipe) when given (e.g. more for a recipe that needs
-- a forge or many different reagents). A factor of 1 means an ordinary craft.
function Optimiser.TimeCost(spellID, recipe, opts)
  local lambda = opts.lambda or 0
  if lambda == 0 or not opts.timeFactorOf then return lambda end
  return lambda * (opts.timeFactorOf(spellID, recipe) or 1)
end

--- Expected cost of one skill point: C(r, s) = (craftCost + lambda) / P(s).
-- Returns math.huge when the recipe is grey.
function Optimiser.PointCost(recipe, skill, opts, spellID)
  local chance = Optimiser.SkillUpChance(recipe, skill)
  if chance <= 0 then return huge end
  return (Optimiser.CraftCost(recipe, opts) + Optimiser.TimeCost(spellID, recipe, opts)) / chance
end

--- Can this recipe be used at `skill` with these filters?
-- opts.faction: "Alliance" | "Horde" | nil (nil = no faction filter)
-- opts.sources: set such as { trainer = true, vendor = true }, or nil for all sources
-- opts.known:   set of spellIDs the player already knows (these skip the source filter)
function Optimiser.IsAvailable(spellID, recipe, skill, opts)
  if recipe.faction and opts.faction and recipe.faction ~= opts.faction then return false end
  if opts.known and opts.known[spellID] then return true end
  if not recipe.learn or recipe.learn > skill then return false end -- learn = nil: skill needed is unknown
  if opts.sources and not opts.sources[recipe.source] then return false end
  return true
end

--- Merge consecutive points that use the same recipe into steps.
-- points: list of { skill, spellID, chance, craftCost, oneOff, unknown }, one per skill point.
function Optimiser.MergeSteps(points)
  local steps = {}
  local step
  for _, point in ipairs(points) do
    if not step or step.spellID ~= point.spellID then
      step = {
        spellID = point.spellID,
        fromSkill = point.skill,
        toSkill = point.skill,
        points = 0,
        expectedCrafts = 0,
        craftCost = point.craftCost or 0,
        oneOffCost = 0,
        unknown = point.unknown,
      }
      steps[#steps + 1] = step
    end
    step.points = step.points + 1
    step.toSkill = point.skill + 1
    step.expectedCrafts = step.expectedCrafts + 1 / point.chance
    step.oneOffCost = step.oneOffCost + (point.oneOff or 0)
  end
  for _, s in ipairs(steps) do
    s.craftsMin = s.points                          -- every craft gives a point
    s.crafts = ceil(s.expectedCrafts - EPSILON)     -- expected, rounded up
    s.cost = ceil(s.expectedCrafts * s.craftCost + s.oneOffCost - EPSILON)
  end
  return steps
end

-- Is candidate (a) better than the current best (b)?
-- Fully priced recipes beat ones with unknown reagent prices, then lower cost,
-- then higher skill-up chance, then lower spellID so the result is deterministic.
local function better(a, b)
  if not b then return true end
  if (a.unknown == nil) ~= (b.unknown == nil) then return a.unknown == nil end
  if a.cost ~= b.cost then return a.cost < b.cost end
  if a.chance ~= b.chance then return a.chance > b.chance end
  return a.spellID < b.spellID
end

local finishRoute -- defined below

-- One-off cost of getting a recipe the player does not know yet.
-- opts.recipeCostOf(spellID, recipe) can override the data (e.g. price a dropped pattern
-- from the auction house); returning math.huge means "cannot be obtained".
local function purchaseCost(spellID, recipe, opts)
  if opts.known and opts.known[spellID] then return 0 end
  if opts.recipeCostOf then
    local cost = opts.recipeCostOf(spellID, recipe)
    if cost then return cost end
  end
  return recipe.sourceCost or 0
end

--- Greedy route: for each skill point pick the recipe with the lowest expected cost.
-- recipes: { [spellID] = recipe record } for one profession.
-- opts: from, to, priceOf, resaleOf, useResale, lambda, timeFactorOf, faction, sources, known,
-- recipeCostOf.
-- Returns { steps, cost, crafts, fromSkill, reachedSkill, complete, incomplete, unknownItems }.
--   complete   = false when no usable recipe exists at reachedSkill (route stops short)
--   incomplete = true when some reagent had no price (cost leaves those out)
function Optimiser.BuildRoute(recipes, opts)
  opts = opts or {}
  local from, to = opts.from or 1, opts.to
  local bought = {}
  local craftCosts = {}
  local points = {}
  local reached = from

  for skill = from, to - 1 do
    local best
    for spellID, recipe in pairs(recipes) do
      if Optimiser.IsAvailable(spellID, recipe, skill, opts) then
        local chance = Optimiser.SkillUpChance(recipe, skill)
        if chance > 0 then
          local info = craftCosts[spellID]
          if not info then
            local cost, unknown = Optimiser.CraftCost(recipe, opts)
            info = { cost = cost, unknown = unknown, time = Optimiser.TimeCost(spellID, recipe, opts) }
            craftCosts[spellID] = info
          end
          local oneOff = bought[spellID] and 0 or purchaseCost(spellID, recipe, opts)
          local candidate = {
            spellID = spellID,
            skill = skill,
            chance = chance,
            craftCost = info.cost,
            unknown = info.unknown,
            oneOff = oneOff,
            cost = (info.cost + info.time) / chance + oneOff,
          }
          if oneOff < huge and better(candidate, best) then best = candidate end
        end
      end
    end
    if not best then break end
    bought[best.spellID] = true
    points[#points + 1] = best
    reached = skill + 1
  end

  return finishRoute(recipes, points, from, to, reached)
end

-- Stand-in costs used only while choosing recipes; never shown.
local UNCOVERED = 1e18 -- a skill point no chosen recipe can give yet
local UNPRICED = 1e13  -- added to recipes with an unknown reagent price, so priced ones win

--- Best route: like BuildRoute, but weighs one-off recipe costs against what they save
-- over the whole route, where the greedy pass only looks one skill point ahead.
--
-- Once the set of recipes is fixed, the best choice at each skill point is independent,
-- so the problem is choosing which recipes to pay for. Start with every free recipe
-- (known, or no purchase cost), then keep adding the paid recipe with the largest net
-- saving until none pays for itself, then drop any that stopped being worth it.
-- Same opts and return value as BuildRoute.
function Optimiser.BuildBestRoute(recipes, opts)
  opts = opts or {}
  local from, to = opts.from or 1, opts.to

  -- Candidates: for each usable recipe, its expected cost per point at each skill.
  local candidates, coverable = {}, {}
  for spellID, recipe in pairs(recipes) do
    local candidate
    local oneOff = purchaseCost(spellID, recipe, opts)
    for skill = from, to - 1 do
      if oneOff < huge and Optimiser.IsAvailable(spellID, recipe, skill, opts) then
        local chance = Optimiser.SkillUpChance(recipe, skill)
        if chance > 0 then
          if not candidate then
            local craftCost, unknown = Optimiser.CraftCost(recipe, opts)
            candidate = {
              spellID = spellID, craftCost = craftCost, unknown = unknown,
              oneOff = oneOff, time = Optimiser.TimeCost(spellID, recipe, opts),
              chance = {}, cost = {},
            }
            candidates[#candidates + 1] = candidate
          end
          candidate.chance[skill] = chance
          candidate.cost[skill] = (candidate.craftCost + candidate.time) / chance
            + (candidate.unknown and UNPRICED or 0)
          coverable[skill] = true
        end
      end
    end
  end
  table.sort(candidates, function(a, b) return a.spellID < b.spellID end)

  -- The route can only go as far as some recipe can give points.
  local reach = from
  while reach < to and coverable[reach] do reach = reach + 1 end

  local function bestCosts(chosen, without)
    local best = {}
    for skill = from, reach - 1 do best[skill] = UNCOVERED end
    for _, candidate in ipairs(candidates) do
      if chosen[candidate] and candidate ~= without then
        for skill = from, reach - 1 do
          local cost = candidate.cost[skill]
          if cost and cost < best[skill] then best[skill] = cost end
        end
      end
    end
    return best
  end

  local function saving(candidate, best)
    local total = 0
    for skill = from, reach - 1 do
      local cost = candidate.cost[skill]
      if cost and cost < best[skill] then total = total + best[skill] - cost end
    end
    return total
  end

  local chosen = {}
  for _, candidate in ipairs(candidates) do
    if candidate.oneOff == 0 then chosen[candidate] = true end
  end
  local best = bestCosts(chosen)
  while true do
    local pick, pickGain = nil, EPSILON
    for _, candidate in ipairs(candidates) do
      if not chosen[candidate] then
        local gain = saving(candidate, best) - candidate.oneOff
        if gain > pickGain then pick, pickGain = candidate, gain end
      end
    end
    if not pick then break end
    chosen[pick] = true
    best = bestCosts(chosen)
  end
  -- A recipe bought early can be made redundant by later picks.
  for _, candidate in ipairs(candidates) do
    if chosen[candidate] and candidate.oneOff > 0 then
      local without = bestCosts(chosen, candidate)
      if saving(candidate, without) <= candidate.oneOff then chosen[candidate] = nil end
    end
  end

  -- Assign each skill point to the best chosen recipe; charge a purchase on first use.
  local points, used = {}, {}
  for skill = from, reach - 1 do
    local pick
    for _, candidate in ipairs(candidates) do
      local chance = chosen[candidate] and candidate.chance[skill]
      if chance then
        local option = {
          spellID = candidate.spellID, skill = skill, chance = chance, candidate = candidate,
          craftCost = candidate.craftCost, unknown = candidate.unknown,
          cost = (candidate.craftCost + candidate.time) / chance,
        }
        if better(option, pick) then pick = option end
      end
    end
    if not pick then
      reach = skill
      break
    end
    pick.oneOff = used[pick.candidate] and 0 or pick.candidate.oneOff
    used[pick.candidate] = true
    pick.candidate = nil
    points[#points + 1] = pick
  end

  return finishRoute(recipes, points, from, to, reach)
end

--- Total reagents for a route: { [itemID] = quantity }, using each step's rounded-up craft count.
function Optimiser.Materials(recipes, route)
  local needs = {}
  for _, step in ipairs(route.steps) do
    for _, reagent in ipairs(recipes[step.spellID].reagents or {}) do
      needs[reagent.itemID] = (needs[reagent.itemID] or 0) + reagent.qty * step.crafts
    end
  end
  return needs
end

--- What still has to be bought.
-- needs: from Materials. ownedOf(itemID) -> count (or nil). priceOf(itemID) -> copper or nil.
-- Returns list, total, unknown: list of { itemID, need, owned, buy, price, cost } sorted by
-- itemID (cost is nil when the price is unknown), total copper, and how many lines had no price.
function Optimiser.ShoppingList(needs, ownedOf, priceOf)
  local list, total, unknown = {}, 0, 0
  for itemID, need in pairs(needs) do
    local owned = math.min(need, ownedOf and ownedOf(itemID) or 0)
    local buy = need - owned
    local price = priceOf and priceOf(itemID)
    local line = { itemID = itemID, need = need, owned = owned, buy = buy, price = price }
    if buy > 0 then
      if price then
        line.cost = buy * price
        total = total + line.cost
      else
        unknown = unknown + 1
      end
    else
      line.cost = 0
    end
    list[#list + 1] = line
  end
  table.sort(list, function(a, b) return a.itemID < b.itemID end)
  return list, total, unknown
end

--- Turn per-point picks into the route table (shared by both route builders).
function finishRoute(recipes, points, from, to, reached)
  local steps = Optimiser.MergeSteps(points)
  local route = {
    steps = steps,
    cost = 0,
    crafts = 0,
    fromSkill = from,
    reachedSkill = reached,
    complete = reached >= to,
    incomplete = false,
    unknownItems = {},
  }
  local seen = {}
  for _, step in ipairs(steps) do
    route.cost = route.cost + step.cost
    route.crafts = route.crafts + step.crafts
    step.difficulty = Optimiser.Difficulty(recipes[step.spellID], step.fromSkill)
    if step.unknown then
      route.incomplete = true
      for _, itemID in ipairs(step.unknown) do
        if not seen[itemID] then
          seen[itemID] = true
          route.unknownItems[#route.unknownItems + 1] = itemID
        end
      end
    end
  end
  table.sort(route.unknownItems)
  return route
end

return Optimiser
