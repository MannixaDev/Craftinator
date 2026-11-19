-- Core.lua: namespace, event dispatcher, slash commands.

local addonName, ns = ...

Craftinator = ns
ns.name = addonName
ns.Data = ns.Data or {}
ns.Data.Recipes = ns.Data.Recipes or {}

-- Event dispatcher ---------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

function ns.RegisterEvent(event, handler)
  if not handlers[event] then
    -- RegisterEvent raises an error for an event name this client does not have.
    if not pcall(frame.RegisterEvent, frame, event) then return false end
    handlers[event] = {}
  end
  table.insert(handlers[event], handler)
  return true
end

frame:SetScript("OnEvent", function(_, event, ...)
  for _, handler in ipairs(handlers[event] or {}) do
    handler(...)
  end
end)

ns.RegisterEvent("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  CraftinatorDB = CraftinatorDB or {}
  CraftinatorCharDB = CraftinatorCharDB or {}
  local db, char = CraftinatorDB, CraftinatorCharDB
  if db.mode == nil then db.mode = "cheapest" end                   -- cheapest | balanced | fastest
  if db.balanceCopper == nil then db.balanceCopper = 1000 end       -- Balanced: what one craft's time is worth
  if db.useOwned == nil then db.useOwned = true end                 -- count mats in bags and bank as free
  if db.toasts == nil then db.toasts = true end
  if db.capture == nil then db.capture = true end                   -- record trainers and vendors you visit
  if db.useResale == nil then db.useResale = false end              -- subtract what the crafted item sells for
  db.sources = db.sources or { trainer = true, vendor = true, drop = false }
  char.bank = char.bank or {}
  char.dismissedToasts = char.dismissedToasts or {}
end)

local function say(text)
  print("|cff33ff99Craftinator|r: " .. tostring(text))
end

-- Prices -------------------------------------------------------------------
-- Auctionator and TSM are other addons, wrapped here so Pricing.lua stays plain Lua.

local function auctionatorAPI()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

function ns.HasAuctionator()
  return auctionatorAPI() ~= nil
end

function ns.HasPriceAddon()
  return auctionatorAPI() ~= nil or TSM_API ~= nil
end

local priceBook

function ns.GetPricing()
  if priceBook then return priceBook end
  priceBook = ns.Pricing.New({
    vendorPrices = ns.Data.VendorPrices,
    sources = {
      {
        name = "Auctionator",
        price = function(itemID)
          local api = auctionatorAPI()
          if not api then return nil end
          local ok, price = pcall(api.GetAuctionPriceByItemID, addonName, itemID)
          return ok and price or nil
        end,
        age = function(itemID)
          local api = auctionatorAPI()
          if not api then return nil end
          local ok, age = pcall(api.GetAuctionAgeByItemID, addonName, itemID)
          return ok and age or nil
        end,
      },
      {
        name = "TSM",
        price = function(itemID)
          if not (TSM_API and TSM_API.GetCustomPriceValue) then return nil end
          local ok, price = pcall(TSM_API.GetCustomPriceValue, "dbmarket", "i:" .. itemID)
          return ok and price or nil
        end,
      },
    },
  })
  return priceBook
end

ns.RegisterEvent("PLAYER_LOGIN", function()
  local api = auctionatorAPI()
  if api and api.RegisterForDBUpdate then
    pcall(api.RegisterForDBUpdate, addonName, function()
      if priceBook then priceBook.Clear() end
      if ns.Panel then ns.Panel.RequestRefresh() end
    end)
  end
end)

-- Route planning -------------------------------------------------------------

-- A recipe pattern with no auction price cannot be planned for.
local function recipeCostOf(book)
  return function(_, recipe)
    if recipe.sourceCost then return recipe.sourceCost end
    if recipe.source == "trainer" then return 0 end      -- trainer fee not known: counted as free
    if recipe.source == "vendor" then return math.huge end -- sold for a currency, not gold: not planned
    if recipe.source == "quest" then return 0 end
    -- Drops and patterns of unknown origin: what the pattern costs on the auction house.
    return recipe.recipeItem and book.PriceOf(recipe.recipeItem) or math.huge
  end
end

local function lambdaFor(mode)
  if mode == "fastest" then return ns.Optimiser.LAMBDA.fastest end
  if mode == "balanced" then return CraftinatorDB.balanceCopper end
  return ns.Optimiser.LAMBDA.cheapest
end

-- Fastest mode: how long one craft of a recipe takes compared with a plain one. Each extra
-- kind of reagent adds 5% (more to buy and carry) and a craft station adds 10% (a trip to it).
local REAGENT_PENALTY, STATION_PENALTY = 0.05, 0.10

local function fastestTimeFactor(_, recipe)
  local kinds = #(recipe.reagents or {})
  return 1 + REAGENT_PENALTY * math.max(0, kinds - 1) + (recipe.station and STATION_PENALTY or 0)
end

-- Gathering professions: what to gather at this skill, where, and what it is worth raw or crafted.
local usesIndex
local function buildGathering(profession, data, fromCache)
  usesIndex = usesIndex or ns.Gathering.UsesIndex(ns.Data.Recipes)
  local book = ns.GetPricing()
  local faction = ns.Player.Faction()
  local entries, bracket = ns.Gathering.List({
    data = data, skill = profession.skill, faction = faction, priceOf = book.PriceOf, index = usesIndex,
  })
  return {
    kind = "gathering",
    profession = profession.name,
    displayName = profession.name,
    skill = profession.skill,
    target = profession.max,
    entries = entries,
    bracket = bracket,
    zones = ns.Gathering.Zones(bracket, faction),
    book = book,
    fromCache = fromCache,
  }
end

--- Build the route for the open profession (or the one last seen on this character).
-- Returns a plan table, or nil and a message to show.
function ns.BuildPlan()
  local profession = ns.Player.OpenProfession()
  local known
  local fromCache = false
  if profession then
    known = ns.Player.KnownRecipes()
    local knownList = {}
    for spellID in pairs(known) do knownList[#knownList + 1] = spellID end
    CraftinatorCharDB.last = {
      id = profession.id, name = profession.name, skill = profession.skill, max = profession.max, known = knownList,
    }
  elseif CraftinatorCharDB.last then
    profession, known, fromCache = CraftinatorCharDB.last, {}, true
    for _, spellID in ipairs(profession.known or {}) do known[spellID] = true end
  else
    return nil, "Click a profession (for example Tailoring) to see its route."
  end

  local gathering = ns.Data.Gathering and ns.Data.Gathering[profession.name]
  if gathering then return buildGathering(profession, gathering, fromCache) end

  local key = ns.Data.SkillLines and ns.Data.SkillLines[profession.id]
  local recipes = key and ns.Data.Recipes[key]
  if not recipes then
    return nil, ("No recipe data for %s. Gathering professions have nothing to craft."):format(tostring(profession.name))
  end

  local db = CraftinatorDB
  local book = ns.GetPricing()
  local Optimiser = ns.Optimiser
  local started = debugprofilestop()
  -- The "Drops" filter also covers quest rewards and patterns of unknown origin.
  local sources = {
    trainer = db.sources.trainer, vendor = db.sources.vendor,
    drop = db.sources.drop, quest = db.sources.drop, item = db.sources.drop, unknown = db.sources.drop,
  }
  local ownedOf = db.useOwned and function(itemID) return (ns.Inventory.Count(itemID)) end or nil
  local routeOpts = {
      from = profession.skill,
      to = profession.max,
      priceOf = book.PriceOf,
      recipeCostOf = recipeCostOf(book),
      faction = ns.Player.Faction(),
      sources = sources,
      known = known,
      lambda = lambdaFor(db.mode),
      timeFactorOf = db.mode == "fastest" and fastestTimeFactor or nil,
      useResale = db.useResale,
      resaleOf = book.PriceOf,
    }
  local route = Optimiser.BuildWithOwned(recipes, routeOpts, ownedOf)
  -- Tools the route needs but you lack (Enchanting rods) get a "make it first" step.
  route = Optimiser.AddToolSteps(recipes, route, routeOpts, function(itemID) return ns.Inventory.Count(itemID) > 0 end)

  local shopping, matsToBuy, unpriced = Optimiser.ShoppingList(Optimiser.Materials(recipes, route), ownedOf, book.PriceOf)
  local recipeCosts, resale = 0, 0
  for _, step in ipairs(route.steps) do
    recipeCosts = recipeCosts + step.oneOffCost
    local output = recipes[step.spellID].output
    local price = db.useResale and output and not step.tool and book.PriceOf(output.itemID) -- tools are kept
    if price then resale = resale + price * (output.qty or 1) * step.crafts end
  end

  return {
    mode = db.mode,
    shopping = shopping,
    toBuy = matsToBuy + recipeCosts,
    recipeCosts = recipeCosts,
    useResale = db.useResale,
    resale = resale,
    unpriced = unpriced,
    useOwned = db.useOwned,
    profession = key,
    displayName = profession.name,
    skill = profession.skill,
    target = profession.max,
    recipes = recipes,
    known = known,
    route = route,
    book = book,
    fromCache = fromCache,
    milliseconds = debugprofilestop() - started,
  }
end

--- Send what still has to be bought to Auctionator as a shopping list.
-- Vendor-sold reagents are left out. Returns true and a message, or false and a reason.
function ns.SendShoppingList(plan)
  local api = auctionatorAPI()
  if not (api and api.CreateShoppingList and api.ConvertToSearchString) then
    return false, "Auctionator is not loaded, so there is nowhere to send the list."
  end
  local terms, waiting = {}, 0
  for _, line in ipairs(plan.shopping) do
    local _, source = plan.book.Get(line.itemID)
    if line.buy > 0 and source ~= "Vendor" then
      local name = C_Item.GetItemNameByID(line.itemID)
      if name then
        terms[#terms + 1] = api.ConvertToSearchString(addonName, { searchString = name, isExact = true, quantity = line.buy })
      else
        C_Item.RequestLoadItemDataByID(line.itemID)
        waiting = waiting + 1
      end
    end
  end
  if waiting > 0 then
    return false, ("the game is still loading %d item name%s. Try again in a moment."):format(waiting, waiting == 1 and "" or "s")
  end
  if #terms == 0 then return false, "nothing to buy from the auction house for this route." end
  local listName = "Craftinator - " .. plan.profession
  local ok, err = pcall(api.CreateShoppingList, addonName, listName, terms)
  if not ok then return false, "Auctionator refused the list: " .. tostring(err) end
  return true, ('created the Auctionator shopping list "%s" with %d item%s.'):format(listName, #terms, #terms == 1 and "" or "s")
end

-- /ci debug (Phase 0 spike) --------------------------------------------------
-- Prints what the Forever client exposes. The full output is also saved to
-- CraftinatorDB.debug so it can be read from the SavedVariables file after a /reload.
-- This is throwaway probe code, so it calls the WoW API directly instead of
-- going through the Player/Inventory/Navigation adapters.

local function show(value)
  local ok, text = pcall(tostring, value)
  return ok and text or "<unprintable>"
end

-- Calls fn(...) safely and returns a one-line description of what came back.
local function probe(fn, ...)
  if type(fn) ~= "function" then return "MISSING" end
  local results = { pcall(fn, ...) }
  if not results[1] then return "ERROR: " .. show(results[2]) end
  local n = select("#", unpack(results)) -- trailing nils are dropped; good enough for a probe
  if n <= 1 then return "(nothing)" end
  local parts = {}
  for i = 2, n do parts[#parts + 1] = show(results[i]) end
  return table.concat(parts, ", ")
end

local function sortedKeys(tbl)
  local keys = {}
  for key in pairs(tbl) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  return keys
end

-- Adds "prefix.key = value" lines for every field, one nested level deep.
local function dumpTable(lines, prefix, tbl, depth)
  if type(tbl) ~= "table" then
    lines[#lines + 1] = prefix .. " = " .. show(tbl)
    return
  end
  for _, key in ipairs(sortedKeys(tbl)) do
    local value = tbl[key]
    local label = prefix .. "." .. tostring(key)
    if type(value) == "table" and (depth or 0) < 1 then
      dumpTable(lines, label, value, (depth or 0) + 1)
    else
      lines[#lines + 1] = label .. " = " .. show(value)
    end
  end
end

local function functionNames(tbl)
  local names = {}
  for _, key in ipairs(sortedKeys(tbl)) do
    if type(tbl[key]) == "function" then names[#names + 1] = tostring(key) end
  end
  return names
end

local function isShown(frameName)
  local f = _G[frameName]
  if type(f) ~= "table" or not f.IsShown then return "no such frame" end
  return f:IsShown() and "shown" or "hidden"
end

local TEST_ITEM = 2589 -- Linen Cloth

local function debugReport()
  local chat, saved = {}, {}
  local function both(text) chat[#chat + 1] = text; saved[#saved + 1] = text end
  local function fileOnly(text) saved[#saved + 1] = text end

  -- Client
  both("Build: " .. probe(GetBuildInfo))
  both("Interface: " .. show((select(4, GetBuildInfo()))))
  both("WOW_PROJECT_ID: " .. show(WOW_PROJECT_ID) .. " (WOW_PROJECT_CAMELOT = " .. show(WOW_PROJECT_CAMELOT) .. ")")

  -- Player
  both("Faction: " .. probe(UnitFactionGroup, "player"))
  local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local mapInfo = mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  both("mapID: " .. show(mapID) .. " (" .. show(mapInfo and mapInfo.name) .. ")")
  both("Zone: " .. probe(GetZoneText) .. " / subzone: " .. probe(GetSubZoneText) .. " / real zone: " .. probe(GetRealZoneText))

  -- Auctionator
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  both("Auctionator loaded: " .. show(Auctionator ~= nil) .. ", Auctionator.API.v1 exists: " .. show(api ~= nil))
  if api then
    both("  GetAuctionPriceByItemID(" .. TEST_ITEM .. "): " .. probe(api.GetAuctionPriceByItemID, addonName, TEST_ITEM))
    both("  GetAuctionAgeByItemID(" .. TEST_ITEM .. "): " .. probe(api.GetAuctionAgeByItemID, addonName, TEST_ITEM))
    both("  RegisterForDBUpdate: " .. type(api.RegisterForDBUpdate) .. ", CreateShoppingList: " .. type(api.CreateShoppingList))
    fileOnly("  Auctionator.API.v1 functions: " .. table.concat(functionNames(api), ", "))
  end
  both("TSM_API exists: " .. show(TSM_API ~= nil))

  -- Profession window
  both("Frames: ProfessionsFrame " .. isShown("ProfessionsFrame")
    .. ", TradeSkillFrame " .. isShown("TradeSkillFrame")
    .. ", CraftFrame " .. isShown("CraftFrame"))

  local ts = C_TradeSkillUI
  both("C_TradeSkillUI exists: " .. show(ts ~= nil))
  if ts then
    local names = functionNames(ts)
    both("  " .. #names .. " functions (full list in the saved log)")
    fileOnly("  C_TradeSkillUI functions: " .. table.concat(names, ", "))

    for _, fnName in ipairs({ "GetBaseProfessionInfo", "GetChildProfessionInfo" }) do
      local ok, info = pcall(function() return ts[fnName]() end)
      if ok and type(info) == "table" then
        dumpTable(saved, "  " .. fnName, info)
        both("  " .. fnName .. ": " .. show(info.professionName) .. " " .. show(info.skillLevel) .. "/" .. show(info.maxSkillLevel)
          .. " (professionID " .. show(info.professionID) .. ")")
      else
        both("  " .. fnName .. ": " .. (ts[fnName] and ("no table: " .. show(info)) or "MISSING"))
      end
    end

    local ok, ids = pcall(function() return ts.GetAllRecipeIDs() end)
    if ok and type(ids) == "table" and #ids > 0 then
      both("  GetAllRecipeIDs: " .. #ids .. " recipes")
      -- Dump the first recipe, and the first learned one if that is a different recipe.
      local firstInfo, learnedInfo
      for i, recipeID in ipairs(ids) do
        local okInfo, info = pcall(ts.GetRecipeInfo, recipeID)
        if okInfo and type(info) == "table" then
          if i == 1 then firstInfo = info end
          if info.learned then learnedInfo = info; break end
        elseif i == 1 then
          both("  GetRecipeInfo(" .. show(recipeID) .. "): " .. show(info))
        end
      end
      local toDump = { ["first recipe"] = firstInfo }
      if learnedInfo ~= firstInfo then toDump["first learned recipe"] = learnedInfo end
      for label, info in pairs(toDump) do
        both("  " .. label .. ": " .. show(info.name) .. " (recipeID " .. show(info.recipeID) .. ")"
          .. " relativeDifficulty=" .. show(info.relativeDifficulty)
          .. " numSkillUps=" .. show(info.numSkillUps)
          .. " canSkillUp=" .. show(info.canSkillUp)
          .. " learned=" .. show(info.learned))
        dumpTable(saved, "  " .. label, info)
      end
      if Enum and Enum.TradeskillRelativeDifficulty then
        dumpTable(saved, "  Enum.TradeskillRelativeDifficulty", Enum.TradeskillRelativeDifficulty)
      end
    else
      both("  GetAllRecipeIDs: " .. (ts.GetAllRecipeIDs and ("no recipes: " .. show(ids)) or "MISSING")
        .. " (is a profession window open?)")
    end
  end

  -- Old (Classic-style) trade skill API
  both("Old API: GetNumTradeSkills " .. type(GetNumTradeSkills) .. ", GetTradeSkillInfo " .. type(GetTradeSkillInfo)
    .. ", GetTradeSkillLine " .. type(GetTradeSkillLine) .. ", GetProfessions " .. type(GetProfessions)
    .. ", GetNumSkillLines " .. type(GetNumSkillLines))
  if type(GetTradeSkillLine) == "function" then
    both("  GetTradeSkillLine: " .. probe(GetTradeSkillLine))
  end
  if type(GetNumTradeSkills) == "function" and type(GetTradeSkillInfo) == "function" then
    local okNum, num = pcall(GetNumTradeSkills)
    both("  GetNumTradeSkills: " .. show(num))
    for i = 1, okNum and tonumber(num) or 0 do
      local okInfo, _, kind = pcall(GetTradeSkillInfo, i)
      if okInfo and kind ~= "header" and kind ~= "subheader" then
        both("  GetTradeSkillInfo(" .. i .. "): " .. probe(GetTradeSkillInfo, i))
        break
      end
    end
  end

  for _, line in ipairs(chat) do say(line) end
  if CraftinatorDB then
    CraftinatorDB.debug = { time = date and date("%Y-%m-%d %H:%M:%S") or nil, lines = saved }
    say("Full output saved. Type /reload to write it to WTF/.../SavedVariables/Craftinator.lua")
  end
end

-- /ci scan (data capture) ----------------------------------------------------
-- Run with a profession trainer window open. Records every recipe the trainer
-- teaches (spell ID, skill needed, cost) into CraftinatorDB.trainerScans, for
-- the offline pipeline: this data is server-side and not in the DB2 exports.

local scanTip

local function serviceSpellID(index)
  local id
  pcall(function()
    scanTip = scanTip or CreateFrame("GameTooltip", "CraftinatorScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:SetTrainerService(index)
    id = select(2, scanTip:GetSpell())
    scanTip:Hide()
  end)
  return tonumber(id)
end

-- Returns everything fn(...) gave back as a list, or nil if it is missing or errors.
local function results(fn, ...)
  if type(fn) ~= "function" then return nil end
  local packed = { pcall(fn, ...) }
  if not packed[1] then return nil end
  table.remove(packed, 1)
  return packed
end

-- silent = true: called when a trainer window opens; prints nothing and keeps only
-- profession trainers. Returns the record and whether this trainer is new.
local function trainerScan(silent)
  local count = type(GetNumTrainerServices) == "function" and GetNumTrainerServices() or 0
  if count == 0 then
    if not silent then say("no trainer list found. Open a profession trainer window first, then type /ci scan.") end
    return
  end

  -- Show learned and not-yet-available recipes too, then put the filters back.
  local switched = {}
  if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
    for _, kind in ipairs({ "available", "unavailable", "used" }) do
      local ok, on = pcall(GetTrainerServiceTypeFilter, kind)
      if ok and not (on == true or on == 1) and pcall(SetTrainerServiceTypeFilter, kind, true) then
        switched[#switched + 1] = kind
      end
    end
    count = GetNumTrainerServices()
  end

  local services = {}
  for i = 1, count do
    local info = results(GetTrainerServiceInfo, i) or {}
    local skillReq = results(GetTrainerServiceSkillReq, i) or {}
    local cost = results(GetTrainerServiceCost, i) or {}
    local levelReq = results(GetTrainerServiceLevelReq, i) or {}
    services[#services + 1] = {
      index = i,
      spellID = serviceSpellID(i),
      name = info[1],
      info = info,                 -- raw returns, in case their order differs on Forever
      skill = skillReq[1],
      skillRank = skillReq[2],
      cost = cost[1],
      levelReq = levelReq[1],
    }
  end

  for _, kind in ipairs(switched) do pcall(SetTrainerServiceTypeFilter, kind, false) end

  local mapID = C_Map.GetBestMapForUnit("player")
  local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
  local guid = UnitGUID("npc")
  local scan = {
    time = date("%Y-%m-%d %H:%M:%S"),
    build = (select(2, GetBuildInfo())),
    npcName = UnitName("npc"),
    npcID = guid and tonumber((select(6, strsplit("-", guid)))),
    faction = UnitFactionGroup("player"),
    mapID = mapID,
    zone = GetZoneText(),
    subzone = GetSubZoneText(),
    x = position and position.x,
    y = position and position.y,
    services = services,
  }
  local withSkill, withSpell = 0, 0
  for _, service in ipairs(services) do
    if service.skillRank then withSkill = withSkill + 1 end
    if service.spellID then withSpell = withSpell + 1 end
  end
  if silent and withSkill == 0 then return end -- a class trainer: nothing here needs a profession skill

  CraftinatorDB.trainerScans = CraftinatorDB.trainerScans or {}
  local key = tostring(scan.npcID or scan.npcName or "unknown")
  local isNew = CraftinatorDB.trainerScans[key] == nil
  CraftinatorDB.trainerScans[key] = scan
  if silent then return scan, isNew end
  say(("scanned %s: %d entries, %d with a skill requirement, %d with a spell ID."):format(
    tostring(scan.npcName), #services, withSkill, withSpell))
  local sample = services[math.min(2, #services)]
  say(("example: %s, needs %s %s, costs %s copper"):format(
    tostring(sample.name), tostring(sample.skill), tostring(sample.skillRank), tostring(sample.cost)))
  say("Saved. /ci export shows it as text to share.")
  return scan, isNew
end
ns.ScanTrainer = trainerScan

-- Slash commands -----------------------------------------------------------

SLASH_CRAFTINATOR1 = "/ci"
SLASH_CRAFTINATOR2 = "/craftinator"
SLASH_CRAFTINATOR3 = "/pp" -- the addon's first name was ProfPlanner; kept so the old command still works
SlashCmdList["CRAFTINATOR"] = function(msg)
  local command = (msg or ""):lower():match("^%s*(%S*)")
  if command == "debug" then
    local ok, err = pcall(debugReport)
    if not ok then say("debug failed: " .. tostring(err)) end
  elseif command == "scan" then
    local ok, err = pcall(trainerScan)
    if not ok then say("scan failed: " .. tostring(err)) end
  elseif command == "" then
    local ok, err = pcall(ns.Panel.Toggle)
    if not ok then say("could not open the panel: " .. tostring(err)) end
  elseif command == "route" then
    -- Text version of the route, useful when the panel misbehaves.
    local ok, plan, problem = pcall(ns.BuildPlan)
    if not ok or not plan then
      say(tostring(problem or plan))
      return
    end
    if plan.kind == "gathering" then
      say(("%s is a gathering profession: it has no route or shopping list."):format(plan.displayName))
      return
    end
    say(("%s %d/%d, %s mode: %d steps, %s to buy, built in %.1f ms"):format(plan.displayName, plan.skill,
      plan.target, plan.mode, #plan.route.steps, ns.Pricing.FormatMoney(plan.toBuy), plan.milliseconds))
    for _, step in ipairs(plan.route.steps) do
      say(("  %d-%d %s x%d, %s"):format(step.fromSkill, step.toSkill, plan.recipes[step.spellID].name,
        step.crafts, ns.Pricing.FormatMoney(step.cost)))
    end
  elseif command == "list" then
    local ok, plan, problem = pcall(ns.BuildPlan)
    if not ok or not plan then
      say(tostring(problem or plan))
      return
    end
    if plan.kind == "gathering" then
      say(("%s is a gathering profession: it has no route or shopping list."):format(plan.displayName))
      return
    end
    say(("shopping list, %s to buy:"):format(ns.Pricing.FormatMoney(plan.toBuy)))
    for _, line in ipairs(plan.shopping) do
      if line.buy > 0 then
        say(("  %d x %s (have %d of %d), %s"):format(line.buy, ns.Inventory.ItemName(line.itemID), line.owned,
          line.need, line.cost and ns.Pricing.FormatMoney(line.cost) or "price unknown"))
      end
    end
  elseif command == "export" then
    local ok, err = pcall(ns.Capture.ShowExport)
    if not ok then say("export failed: " .. tostring(err)) end
  elseif command == "send" then
    local ok, plan, problem = pcall(ns.BuildPlan)
    if not ok or not plan then
      say(tostring(problem or plan))
      return
    end
    if plan.kind == "gathering" then
      say(("%s is a gathering profession: it has no route or shopping list."):format(plan.displayName))
      return
    end
    say((select(2, ns.SendShoppingList(plan))))
  elseif command == "resale" then
    CraftinatorDB.useResale = not CraftinatorDB.useResale
    ns.Panel.RequestRefresh()
    say("the auction price of what you craft is now " .. (CraftinatorDB.useResale and "subtracted from" or "left out of")
      .. " each recipe's cost.")
  elseif command == "config" or command == "options" then
    ns.Settings.Open()
  elseif command == "balance" then
    local silver = tonumber((msg or ""):match("(%d+%.?%d*)%s*$"))
    if silver then
      CraftinatorDB.balanceCopper = math.floor(silver * 100)
      ns.Panel.RequestRefresh()
    end
    say(("Balanced mode values one craft's time at %s. Change it with /ci balance <silver>."):format(
      ns.Pricing.FormatMoney(CraftinatorDB.balanceCopper)))
  elseif command == "toasts" then
    CraftinatorDB.toasts = not CraftinatorDB.toasts
    say("city reminders are now " .. (CraftinatorDB.toasts and "on" or "off") .. ".")
  else
    say("commands: /ci (show or hide the panel), /ci config, /ci route, /ci list, /ci send (list to Auctionator),"
      .. " /ci balance <silver>, /ci resale, /ci toasts, /ci export (share recorded trainer and vendor data), /ci debug")
  end
end
