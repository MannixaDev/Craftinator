local function loadGathering()
  local ns = {}
  assert(loadfile("Gathering.lua"))("Craftinator", ns)
  return ns.Gathering
end

describe("Gathering", function()
  local G = loadGathering()

  local data = {
    nodes = {
      { name = "Copper Vein", skill = 1, itemID = 1 },
      { name = "Tin Vein", skill = 65, itemID = 2 },
      { name = "Silver Vein", skill = 75, itemID = 3 },
    },
    brackets = {
      { from = 1, to = 65, nodes = { "Copper Vein" }, Alliance = { "Elwynn Forest" }, Horde = { "Durotar" } },
      { from = 65, to = 125, nodes = { "Tin Vein", "Silver Vein" }, both = { "Wetlands" }, Horde = { "The Barrens" } },
    },
  }

  it("picks the bracket for a skill, and the last one above the top", function()
    assert.equals(1, G.Bracket(data, 1).from)
    assert.equals(1, G.Bracket(data, 64).from)
    assert.equals(65, G.Bracket(data, 65).from)
    assert.equals(65, G.Bracket(data, 300).from)
  end)

  it("lists a faction's zones before the shared ones", function()
    local bracket = G.Bracket(data, 70)
    assert.same({ "The Barrens", "Wetlands" }, G.Zones(bracket, "Horde"))
    assert.same({ "Wetlands" }, G.Zones(bracket, "Alliance"))
  end)

  it("colours nodes by how far above them the skill is", function()
    assert.equals("red", G.Difficulty(75, 74))
    assert.equals("orange", G.Difficulty(75, 75))
    assert.equals("yellow", G.Difficulty(75, 100))
    assert.equals("green", G.Difficulty(75, 125))
    assert.equals("grey", G.Difficulty(75, 175))
  end)

  it("values a crafted use per raw item, net of the other reagents", function()
    local index = G.UsesIndex({
      Mining = {
        [10] = { name = "Smelt Copper", output = { itemID = 100, qty = 1 }, reagents = { { itemID = 1, qty = 1 } } },
        [11] = { name = "Smelt Bronze", output = { itemID = 101, qty = 2 },
          reagents = { { itemID = 1, qty = 1 }, { itemID = 2, qty = 1 } } },
        [12] = { name = "Unpriced", output = { itemID = 102, qty = 1 }, reagents = { { itemID = 1, qty = 2 } } },
      },
      Enchanting = { [13] = { name = "An enchant", reagents = { { itemID = 1, qty = 1 } } } },
    })
    local prices = { [1] = 10, [2] = 20, [100] = 15, [101] = 40 }
    local uses = G.Uses(1, index, function(id) return prices[id] end)
    assert.equals(2, #uses)
    assert.equals("Smelt Bronze", uses[1].recipe.name) -- 2 x 40 - 20 = 60 per copper ore
    assert.equals(60, uses[1].value)
    assert.equals("Mining", uses[1].profession)
    assert.equals(15, uses[2].value)
  end)

  it("lists what can be gathered now by value, then locked nodes by skill", function()
    local prices = { [2] = 50, [3] = 80 }
    local entries, bracket = G.List({ data = data, skill = 70, faction = "Alliance",
      priceOf = function(id) return prices[id] end, index = {} })
    assert.equals(65, bracket.from)
    assert.equals(2, #entries)
    assert.equals("Tin Vein", entries[1].name)
    assert.equals("orange", entries[1].difficulty)
    assert.equals("Silver Vein", entries[2].name)
    assert.equals("red", entries[2].difficulty)
  end)

  it("lists every fish when there are no nodes", function()
    local fishing = { fish = { { itemID = 7 }, { itemID = 8, where = "Coastal" } }, brackets = { { from = 1, to = 75 } } }
    local prices = { [7] = 5, [8] = 9 }
    local entries = G.List({ data = fishing, skill = 10, faction = "Horde",
      priceOf = function(id) return prices[id] end, index = {} })
    assert.equals(8, entries[1].itemID)
    assert.equals("Coastal", entries[1].where)
    assert.equals(7, entries[2].itemID)
  end)
end)
