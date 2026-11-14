-- Pricing.lua: price lookup chain + cache.
-- Plain Lua only: price sources are injected, no WoW API calls here.
-- All money values are in copper.

local _, ns = ...

local Pricing = {}
if type(ns) == "table" then ns.Pricing = Pricing end

Pricing.STALE_DAYS = 3

--- Create a price book.
-- config.vendorPrices: { [itemID] = copper } for vendor-sold reagents (always used first)
-- config.sources: ordered list of { name = "Auctionator", price = function(itemID) -> copper or nil,
--                                   age = function(itemID) -> days or nil (optional) }
function Pricing.New(config)
  config = config or {}
  local vendorPrices = config.vendorPrices or {}
  local sources = config.sources or {}
  local cache = {}
  local book = {}

  local function lookup(itemID)
    local vendor = vendorPrices[itemID]
    if vendor then return { price = vendor, source = "Vendor" } end
    for _, source in ipairs(sources) do
      local price = source.price(itemID)
      if type(price) == "number" and price > 0 then
        return { price = price, source = source.name, age = source.age and source.age(itemID) or nil }
      end
    end
    return { source = "Unknown" }
  end

  --- Returns price (or nil when unknown), source name, age in days (or nil).
  function book.Get(itemID)
    local entry = cache[itemID]
    if not entry then
      entry = lookup(itemID)
      cache[itemID] = entry
    end
    return entry.price, entry.source, entry.age
  end

  --- Price only: the shape the optimiser expects for priceOf.
  function book.PriceOf(itemID)
    return (book.Get(itemID))
  end

  --- Forget cached prices (call when a scan finishes or the panel opens).
  function book.Clear()
    cache = {}
  end

  --- Summary of everything looked up since the last Clear.
  -- Returns { oldestAge = days or nil, stale = bool, unknown = count, sources = { [name] = count } }
  function book.Summary()
    local summary = { stale = false, unknown = 0, sources = {} }
    for _, entry in pairs(cache) do
      summary.sources[entry.source] = (summary.sources[entry.source] or 0) + 1
      if not entry.price then summary.unknown = summary.unknown + 1 end
      if entry.age and (not summary.oldestAge or entry.age > summary.oldestAge) then
        summary.oldestAge = entry.age
      end
    end
    summary.stale = summary.oldestAge ~= nil and summary.oldestAge > Pricing.STALE_DAYS
    return summary
  end

  return book
end

--- "12g 34s 56c" from copper. Rounds up to whole copper.
function Pricing.FormatMoney(copper)
  copper = math.ceil(copper or 0)
  local sign = ""
  if copper < 0 then sign, copper = "-", -copper end
  local gold = math.floor(copper / 10000)
  local silver = math.floor(copper / 100) % 100
  local rest = copper % 100
  if gold > 0 then return ("%s%dg %ds %dc"):format(sign, gold, silver, rest) end
  if silver > 0 then return ("%s%ds %dc"):format(sign, silver, rest) end
  return ("%s%dc"):format(sign, rest)
end

return Pricing
