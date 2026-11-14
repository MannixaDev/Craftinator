-- Run from the repo root: busted

local function loadOptimiser()
  local ns = {}
  local chunk = assert(loadfile("Craftinator/Optimiser.lua"))
  chunk("Craftinator", ns)
  return ns.Optimiser
end

-- Fake profession. Item 1 costs 10c, item 2 costs 100c, item 3 costs 1c.
local RECIPES = {
  [101] = { name = "A", output = { itemID = 11, qty = 1 }, reagents = { { itemID = 1, qty = 1 } },
            learn = 1, orange = 1, yellow = 10, green = 15, grey = 20, source = "trainer", sourceCost = 0 },
  [102] = { name = "B", output = { itemID = 12, qty = 1 }, reagents = { { itemID = 1, qty = 2 } },
            learn = 5, orange = 5, yellow = 15, green = 20, grey = 25, source = "trainer", sourceCost = 0 },
  [103] = { name = "C", output = { itemID = 13, qty = 1 }, reagents = { { itemID = 2, qty = 1 } },
            learn = 10, orange = 10, yellow = 25, green = 30, grey = 35, source = "vendor", sourceCost = 500 },
  [104] = { name = "D", output = { itemID = 14, qty = 1 }, reagents = { { itemID = 3, qty = 1 } },
            learn = 1, orange = 1, yellow = 30, green = 35, grey = 40, source = "trainer", sourceCost = 0,
            faction = "Horde" },
}

local PRICES = { [1] = 10, [2] = 100, [3] = 1 }
local function priceOf(itemID) return PRICES[itemID] end

local function opts(extra)
  local o = { from = 1, to = 20, priceOf = priceOf, faction = "Alliance", lambda = 0 }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

local function summary(route)
  local out = {}
  for i, step in ipairs(route.steps) do
    out[i] = ("%d:%d-%d"):format(step.spellID, step.fromSkill, step.toSkill)
  end
  return table.concat(out, " ")
end

describe("Optimiser", function()
  local O = loadOptimiser()
  local A, B, C = RECIPES[101], RECIPES[102], RECIPES[103]

  describe("SkillUpChance", function()
    it("is 1 below yellow", function()
      assert.equals(1, O.SkillUpChance(A, 1))
      assert.equals(1, O.SkillUpChance(A, 9))
    end)
    it("falls linearly from yellow to grey", function()
      assert.equals(1, O.SkillUpChance(A, 10))
      assert.near(0.5, O.SkillUpChance(A, 15), 1e-9)
      assert.near(0.1, O.SkillUpChance(A, 19), 1e-9)
    end)
    it("is 0 at grey and above", function()
      assert.equals(0, O.SkillUpChance(A, 20))
      assert.equals(0, O.SkillUpChance(A, 300))
    end)
    it("does not divide by zero when yellow equals grey", function()
      local r = { yellow = 10, grey = 10 }
      assert.equals(1, O.SkillUpChance(r, 9))
      assert.equals(0, O.SkillUpChance(r, 10))
    end)
  end)

  describe("Difficulty", function()
    it("matches the colour thresholds", function()
      assert.equals("orange", O.Difficulty(A, 9))
      assert.equals("yellow", O.Difficulty(A, 10))
      assert.equals("green", O.Difficulty(A, 15))
      assert.equals("grey", O.Difficulty(A, 20))
    end)
  end)

  describe("cost model", function()
    it("sums reagent prices", function()
      local cost, unknown = O.MatCost(B, priceOf)
      assert.equals(20, cost)
      assert.is_nil(unknown)
    end)
    it("reports reagents with no price and leaves them out", function()
      local cost, unknown = O.MatCost(C, function() return nil end)
      assert.equals(0, cost)
      assert.same({ 2 }, unknown)
    end)
    it("subtracts resale only when the toggle is on", function()
      local resaleOf = function(itemID) return itemID == 11 and 4 or nil end
      assert.equals(10, (O.CraftCost(A, { priceOf = priceOf, resaleOf = resaleOf })))
      assert.equals(6, (O.CraftCost(A, { priceOf = priceOf, resaleOf = resaleOf, useResale = true })))
    end)
    it("divides craft cost plus lambda by the chance", function()
      assert.equals(10, O.PointCost(A, 5, { priceOf = priceOf }))
      assert.near(20, O.PointCost(A, 15, { priceOf = priceOf }), 1e-9)
      assert.near(40, O.PointCost(A, 15, { priceOf = priceOf, lambda = 10 }), 1e-9)
      assert.equals(math.huge, O.PointCost(A, 20, { priceOf = priceOf }))
    end)
    it("scales the time weight of a craft by timeFactorOf", function()
      local slow = function(spellID) return spellID == 101 and 1.5 or 1 end
      assert.equals(15, O.TimeCost(101, A, { lambda = 10, timeFactorOf = slow }))
      assert.equals(10, O.TimeCost(102, B, { lambda = 10, timeFactorOf = slow }))
      assert.equals(0, O.TimeCost(101, A, { timeFactorOf = slow }))            -- no lambda: no time cost
      assert.near(25, O.PointCost(A, 5, { priceOf = priceOf, lambda = 10, timeFactorOf = slow }, 101), 1e-9)
    end)
  end)

  describe("MergeSteps", function()
    it("merges only consecutive points with the same recipe", function()
      local steps = O.MergeSteps({
        { skill = 1, spellID = 101, chance = 1, craftCost = 10 },
        { skill = 2, spellID = 101, chance = 0.5, craftCost = 10 },
        { skill = 3, spellID = 102, chance = 1, craftCost = 20, oneOff = 7 },
        { skill = 4, spellID = 101, chance = 1, craftCost = 10 },
      })
      assert.equals(3, #steps)
      assert.equals(1, steps[1].fromSkill)
      assert.equals(3, steps[1].toSkill)
      assert.equals(2, steps[1].points)
      assert.equals(2, steps[1].craftsMin)
      assert.equals(3, steps[1].crafts)   -- 1/1 + 1/0.5
      assert.equals(30, steps[1].cost)
      assert.equals(27, steps[2].cost)    -- 20 + one-off 7
      assert.equals(4, steps[3].fromSkill)
      assert.equals(5, steps[3].toSkill)
    end)
  end)

  describe("BuildBestRoute", function()
    -- Free recipe at 10c a point, and paid recipes that are cheaper per point.
    local function shop(extra)
      local recipes = {
        [301] = { name = "Free", reagents = { { itemID = 1, qty = 1 } }, learn = 1, yellow = 30, green = 35, grey = 40,
                  source = "trainer", sourceCost = 0 },
        [302] = { name = "Paid", reagents = { { itemID = 4, qty = 1 } }, learn = 1, yellow = 30, green = 35, grey = 40,
                  source = "vendor", sourceCost = 50 },
      }
      for id, recipe in pairs(extra or {}) do recipes[id] = recipe end
      return recipes
    end
    local prices = { [1] = 10, [4] = 5, [5] = 9 }
    local function o(extra)
      return opts({ priceOf = function(itemID) return prices[itemID] end, faction = nil, extra = nil, to = 20,
                    from = extra and extra.from or 1, known = extra and extra.known, sources = extra and extra.sources })
    end

    it("buys a recipe when it saves more than it costs (greedy does not)", function()
      local greedy = O.BuildRoute(shop(), o())
      assert.equals("301:1-20", summary(greedy))
      assert.equals(190, greedy.cost)
      local best = O.BuildBestRoute(shop(), o())
      assert.equals("302:1-20", summary(best))
      assert.equals(145, best.cost)               -- 19 x 5 + 50
      assert.equals(50, best.steps[1].oneOffCost)
    end)

    it("does not buy a recipe that cannot pay for itself", function()
      local best = O.BuildBestRoute(shop(), o({ from = 12 }))   -- 8 points x 5c saved = 40 < 50
      assert.equals("301:12-20", summary(best))
    end)

    it("does not charge for a known recipe", function()
      local best = O.BuildBestRoute(shop(), o({ from = 12, known = { [302] = true } }))
      assert.equals("302:12-20", summary(best))
      assert.equals(40, best.cost)
    end)

    it("buys a recipe when nothing else can give the points", function()
      local recipes = shop()
      recipes[301].grey = 10                      -- the free recipe stops at 10
      recipes[301].yellow = 10
      local best = O.BuildBestRoute(recipes, o())
      assert.is_true(best.complete)
      assert.equals("302:1-20", summary(best))
    end)

    it("lets the caller price or rule out a recipe purchase", function()
      local cheap = o()
      cheap.recipeCostOf = function(spellID) if spellID == 302 then return 10 end end
      assert.equals(19 * 5 + 10, O.BuildBestRoute(shop(), cheap).cost)
      local never = o()
      never.recipeCostOf = function(spellID) if spellID == 302 then return math.huge end end
      assert.equals("301:1-20", summary(O.BuildBestRoute(shop(), never)))
      assert.equals("301:1-20", summary(O.BuildRoute(shop(), never)))
    end)

    it("drops a purchase that a later pick made redundant", function()
      -- 303 is slightly cheaper than 302 and also costs 50: only one of them should be bought.
      local recipes = shop({ [303] = { name = "Paid2", reagents = { { itemID = 5, qty = 1 } }, learn = 1, yellow = 30,
                                       green = 35, grey = 40, source = "vendor", sourceCost = 50 } })
      prices[5] = 4
      local best = O.BuildBestRoute(recipes, o())
      prices[5] = 9
      assert.equals("303:1-20", summary(best))
      assert.equals(19 * 4 + 50, best.cost)
    end)

    it("matches the greedy route when no purchase is worth it", function()
      assert.equals("101:1-15 102:15-20", summary(O.BuildBestRoute(RECIPES, opts())))
      assert.equals("101:1-11 102:11-16 103:16-20",
        summary(O.BuildBestRoute(RECIPES, opts({ lambda = O.LAMBDA.fastest }))))
    end)

    it("stops where no recipe can give a point, and prefers priced recipes", function()
      local route = O.BuildBestRoute(RECIPES, opts({ to = 40, sources = { trainer = true } }))
      assert.is_false(route.complete)
      assert.equals(25, route.reachedSkill)
      local noItem2 = function(itemID) if itemID ~= 2 then return PRICES[itemID] end end
      route = O.BuildBestRoute(RECIPES, opts({ to = 27, priceOf = noItem2, lambda = O.LAMBDA.fastest }))
      assert.equals("101:1-11 102:11-25 103:25-27", summary(route))
      assert.is_true(route.incomplete)
    end)
  end)

  describe("Materials and ShoppingList", function()
    it("totals reagents over the route using rounded-up crafts", function()
      local route = O.BuildRoute(RECIPES, opts())      -- A x16, B x7 (2 of item 1 each)
      assert.same({ [1] = 16 + 14 }, O.Materials(RECIPES, route))
    end)

    it("subtracts what is owned and prices the rest", function()
      local needs = { [1] = 30, [2] = 5, [3] = 4, [9] = 2 }
      local owned = { [1] = 12, [3] = 10 }
      local list, total, unknown = O.ShoppingList(needs, function(id) return owned[id] end, priceOf)
      assert.equals(4, #list)
      assert.same({ itemID = 1, need = 30, owned = 12, buy = 18, price = 10, cost = 180 }, list[1])
      assert.same({ itemID = 3, need = 4, owned = 4, buy = 0, price = 1, cost = 0 }, list[3])
      assert.is_nil(list[4].cost)                       -- item 9 has no price
      assert.equals(180 + 500, total)
      assert.equals(1, unknown)
    end)
  end)

  describe("BuildRoute (greedy)", function()
    it("cheapest mode picks the lowest expected cost per point", function()
      local route = O.BuildRoute(RECIPES, opts())
      -- A is cheaper until skill 15, where its 50% chance makes B (100%) equal; ties go to the higher chance.
      assert.equals("101:1-15 102:15-20", summary(route))
      assert.equals(16, route.steps[1].crafts)   -- 10 + 1/.9 + 1/.8 + 1/.7 + 1/.6 = 15.46
      assert.equals(14, route.steps[1].craftsMin)
      assert.equals(155, route.steps[1].cost)
      assert.equals(7, route.steps[2].crafts)    -- 1 + 1/.9 + 1/.8 + 1/.7 + 1/.6 = 6.46
      assert.equals(130, route.steps[2].cost)
      assert.equals(285, route.cost)
      assert.equals(23, route.crafts)
      assert.is_true(route.complete)
      assert.is_false(route.incomplete)
      assert.equals(20, route.reachedSkill)
      assert.equals("orange", route.steps[1].difficulty)
    end)

    it("fastest mode minimises crafts and pays the one-off recipe cost once", function()
      local route = O.BuildRoute(RECIPES, opts({ lambda = O.LAMBDA.fastest }))
      assert.equals("101:1-11 102:11-16 103:16-20", summary(route))
      assert.equals(19, route.crafts)              -- one craft per point
      assert.equals(500, route.steps[3].oneOffCost)
      assert.equals(900, route.steps[3].cost)      -- 4 x 100 + 500
    end)

    it("does not charge the one-off cost for a known recipe", function()
      local route = O.BuildRoute(RECIPES, opts({ lambda = O.LAMBDA.fastest, known = { [103] = true } }))
      assert.equals(0, route.steps[3].oneOffCost)
      assert.equals(400, route.steps[3].cost)
    end)

    it("applies the source filter, except to known recipes", function()
      local trainerOnly = { trainer = true }
      local route = O.BuildRoute(RECIPES, opts({ lambda = O.LAMBDA.fastest, sources = trainerOnly }))
      assert.equals("101:1-11 102:11-20", summary(route))
      route = O.BuildRoute(RECIPES, opts({ lambda = O.LAMBDA.fastest, sources = trainerOnly, known = { [103] = true } }))
      assert.equals("101:1-11 102:11-16 103:16-20", summary(route))
    end)

    it("skips recipes with an unknown learn skill unless they are known", function()
      local recipes = {
        [201] = { name = "X", reagents = { { itemID = 1, qty = 1 } }, yellow = 10, green = 15, grey = 20, source = "trainer" },
      }
      local route = O.BuildRoute(recipes, opts({ to = 5 }))
      assert.is_false(route.complete)
      assert.equals(1, route.reachedSkill)
      route = O.BuildRoute(recipes, opts({ to = 5, known = { [201] = true } }))
      assert.equals("201:1-5", summary(route))
    end)

    it("applies the faction filter", function()
      local route = O.BuildRoute(RECIPES, opts({ faction = "Horde" }))
      assert.equals("104:1-20", summary(route))
      assert.equals(19, route.cost)
    end)

    it("starts from the current skill", function()
      local route = O.BuildRoute(RECIPES, opts({ from = 12 }))
      assert.equals("101:12-15 102:15-20", summary(route))
      assert.equals(12, route.fromSkill)
    end)

    it("stops and reports when no recipe can give a point", function()
      local route = O.BuildRoute(RECIPES, opts({ to = 40, sources = { trainer = true } }))
      assert.is_false(route.complete)
      assert.equals(25, route.reachedSkill)        -- B goes grey at 25
    end)

    it("prefers fully priced recipes and flags unknown prices", function()
      local noItem2 = function(itemID) if itemID ~= 2 then return PRICES[itemID] end end
      local route = O.BuildRoute(RECIPES, opts({ to = 27, priceOf = noItem2, lambda = O.LAMBDA.fastest }))
      -- C would be fastest from 16, but its reagent has no price, so B is used until it goes grey.
      assert.equals("101:1-11 102:11-25 103:25-27", summary(route))
      assert.is_true(route.incomplete)
      assert.same({ 2 }, route.unknownItems)
      assert.equals(500, route.steps[3].cost)      -- only the recipe purchase is counted
    end)

    it("fastest mode avoids a slower recipe when both give a point per craft", function()
      -- At skill 5 to 9 both A and B are orange; A is cheaper, so it wins ties on cost.
      local fast = opts({ to = 10, lambda = O.LAMBDA.fastest })
      assert.equals("101:1-10", summary(O.BuildBestRoute(RECIPES, fast)))
      assert.equals("101:1-10", summary(O.BuildRoute(RECIPES, fast)))
      -- Mark A as slow (say it needs a forge): B takes over as soon as it can be learned.
      fast.timeFactorOf = function(spellID) return spellID == 101 and 1.1 or 1 end
      assert.equals("101:1-5 102:5-10", summary(O.BuildBestRoute(RECIPES, fast)))
      assert.equals("101:1-5 102:5-10", summary(O.BuildRoute(RECIPES, fast)))
    end)

    it("returns an empty route when already at the target (best route too)", function()
      local route = O.BuildBestRoute(RECIPES, opts({ from = 20 }))
      assert.equals(0, #route.steps)
      assert.is_true(route.complete)
    end)

    it("returns an empty route when already at the target", function()
      local route = O.BuildRoute(RECIPES, opts({ from = 20 }))
      assert.equals(0, #route.steps)
      assert.equals(0, route.cost)
      assert.is_true(route.complete)
    end)
  end)
end)
