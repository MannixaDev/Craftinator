local function loadPricing()
  local ns = {}
  assert(loadfile("Craftinator/Pricing.lua"))("Craftinator", ns)
  return ns.Pricing
end

describe("Pricing", function()
  local P = loadPricing()

  local function source(name, prices, ages, calls)
    return {
      name = name,
      price = function(itemID)
        if calls then calls[name] = (calls[name] or 0) + 1 end
        return prices[itemID]
      end,
      age = ages and function(itemID) return ages[itemID] end or nil,
    }
  end

  it("uses the vendor price first, even when the auction house has one", function()
    local book = P.New({ vendorPrices = { [1] = 10 }, sources = { source("Auctionator", { [1] = 5 }) } })
    local price, from = book.Get(1)
    assert.equals(10, price)
    assert.equals("Vendor", from)
  end)

  it("falls through the sources in order", function()
    local book = P.New({ sources = {
      source("Auctionator", { [1] = 50 }, { [1] = 2 }),
      source("TSM", { [1] = 70, [2] = 80 }),
    } })
    local price, from, age = book.Get(1)
    assert.equals(50, price)
    assert.equals("Auctionator", from)
    assert.equals(2, age)
    price, from = book.Get(2)
    assert.equals(80, price)
    assert.equals("TSM", from)
  end)

  it("treats zero and missing prices as unknown", function()
    local book = P.New({ sources = { source("Auctionator", { [1] = 0 }) } })
    local price, from = book.Get(1)
    assert.is_nil(price)
    assert.equals("Unknown", from)
    assert.is_nil(book.PriceOf(2))
  end)

  it("works with no sources at all", function()
    local book = P.New()
    assert.is_nil(book.PriceOf(1))
    assert.equals(1, book.Summary().unknown)
  end)

  it("caches until cleared", function()
    local calls = {}
    local prices = { [1] = 50 }
    local book = P.New({ sources = { source("Auctionator", prices, nil, calls) } })
    book.Get(1)
    book.Get(1)
    assert.equals(1, calls.Auctionator)
    prices[1] = 60
    assert.equals(50, book.PriceOf(1))
    book.Clear()
    assert.equals(60, book.PriceOf(1))
  end)

  it("summarises age, staleness and unknowns", function()
    local book = P.New({
      vendorPrices = { [9] = 1 },
      sources = { source("Auctionator", { [1] = 50, [2] = 60 }, { [1] = 0, [2] = 5 }) },
    })
    book.Get(1)
    book.Get(9)
    local summary = book.Summary()
    assert.equals(0, summary.oldestAge)
    assert.is_false(summary.stale)
    book.Get(2)
    book.Get(3)
    summary = book.Summary()
    assert.equals(5, summary.oldestAge)
    assert.is_true(summary.stale)
    assert.equals(1, summary.unknown)
    assert.equals(2, summary.sources.Auctionator)
    assert.equals(1, summary.sources.Vendor)
  end)

  it("formats money", function()
    assert.equals("56c", P.FormatMoney(56))
    assert.equals("34s 56c", P.FormatMoney(3456))
    assert.equals("12g 34s 56c", P.FormatMoney(123456))
    assert.equals("1g 0s 0c", P.FormatMoney(9999.2))
    assert.equals("0c", P.FormatMoney(nil))
    assert.equals("-1s 5c", P.FormatMoney(-105))
  end)
end)
