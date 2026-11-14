-- Inventory.lua: item info, bag + bank counts (bank cached on BANKFRAME_OPENED).

local _, ns = ...

local Inventory = {}
ns.Inventory = Inventory

local bankOpen = false

--- Icon for an item, or nil.
function Inventory.ItemIcon(itemID)
  if C_Item and C_Item.GetItemIconByID then
    return (C_Item.GetItemIconByID(itemID))
  end
  return nil
end

--- Item name, or "item <id>" while the client has not loaded it yet.
function Inventory.ItemName(itemID)
  local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID)
  if not name and C_Item and C_Item.RequestLoadItemDataByID then
    C_Item.RequestLoadItemDataByID(itemID) -- so it is there next time
  end
  return name or ("item " .. itemID)
end

local function rawCount(itemID, includeBank)
  local get = (C_Item and C_Item.GetItemCount) or GetItemCount
  if not get then return 0 end
  local ok, count = pcall(get, itemID, includeBank)
  return ok and tonumber(count) or 0
end

--- How many of an item the character owns: bags plus bank.
-- The bank part comes from the game when it knows it, else from the snapshot
-- taken the last time the bank was open. Returns total, inBags, inBank.
function Inventory.Count(itemID)
  local bags = rawCount(itemID, false)
  local bank = math.max(0, rawCount(itemID, true) - bags)
  local snapshot = ProfPlannerCharDB and ProfPlannerCharDB.bank
  if snapshot then
    if bankOpen then
      snapshot[itemID] = bank > 0 and bank or nil
    elseif bank == 0 and snapshot[itemID] then
      bank = snapshot[itemID]
    end
  end
  return bags + bank, bags, bank
end

-- Snapshot every reagent the recipe data mentions while the bank is open.
local function snapshotBank()
  for _, recipes in pairs(ns.Data.Recipes) do
    for _, recipe in pairs(recipes) do
      for _, reagent in ipairs(recipe.reagents or {}) do
        Inventory.Count(reagent.itemID)
      end
    end
  end
end

ns.RegisterEvent("BANKFRAME_OPENED", function()
  bankOpen = true
  snapshotBank()
  if ns.Panel then ns.Panel.RequestRefresh() end
end)
ns.RegisterEvent("BANKFRAME_CLOSED", function()
  bankOpen = false
end)
ns.RegisterEvent("BAG_UPDATE_DELAYED", function()
  if bankOpen then snapshotBank() end -- catch items moved while the bank is open
  if ns.Panel then ns.Panel.RequestRefresh() end
end)
