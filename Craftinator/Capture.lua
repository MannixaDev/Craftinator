-- Capture.lua: records what trainers teach and what vendors sell as you visit them, and
-- turns the records into text to share (/ci export). Recipe learn skills, trainer fees and
-- NPC positions are not in the client data, so this is how the addon's data gets corrected.
-- Nothing about the character is recorded beyond its faction.

local addonName, ns = ...

local Capture = {}
ns.Capture = Capture

local EXPORT_HEADER = "Craftinator export v1"

local function say(text)
  print("|cff33ff99Craftinator|r: " .. tostring(text))
end

-- Where the player is standing and who they are talking to.
local function npcContext()
  local mapID = C_Map.GetBestMapForUnit("player")
  local position = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
  local guid = UnitGUID("npc")
  return {
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
  }
end
Capture.NpcContext = npcContext

-- Trainers -------------------------------------------------------------------

ns.RegisterEvent("TRAINER_SHOW", function()
  if not (CraftinatorDB and CraftinatorDB.capture) then return end
  if type(IsTradeskillTrainer) == "function" and not IsTradeskillTrainer() then return end
  -- The list is not always filled in yet when the window opens.
  C_Timer.After(0.3, function()
    local ok, scan, isNew = pcall(ns.ScanTrainer, true)
    if ok and scan and isNew then
      say(("recorded what %s teaches. /ci export shares it."):format(tostring(scan.npcName)))
    end
  end)
end)

-- Vendors --------------------------------------------------------------------

local relevant -- item IDs worth recording: every reagent and every recipe item in the data

local function relevantItems()
  if relevant then return relevant end
  relevant = {}
  for _, recipes in pairs(ns.Data.Recipes) do
    for _, recipe in pairs(recipes) do
      for _, reagent in ipairs(recipe.reagents or {}) do relevant[reagent.itemID] = true end
      if recipe.recipeItem then relevant[recipe.recipeItem] = true end
    end
  end
  return relevant
end

-- price, stack size, number in stock (-1 = unlimited), sold for something other than gold
local function merchantItem(index)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
    if ok and type(info) == "table" then
      return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
    end
  end
  if GetMerchantItemInfo then
    local ok, _, _, price, stack, available, _, _, extended = pcall(GetMerchantItemInfo, index)
    if ok then return price, stack, available, extended end
  end
end

--- Record the open vendor window. Returns the record and whether the vendor is new,
-- or nil when the vendor sells nothing the recipe data uses.
function Capture.ScanVendor()
  local count = (C_MerchantFrame and C_MerchantFrame.GetNumItems and C_MerchantFrame.GetNumItems())
    or (GetMerchantNumItems and GetMerchantNumItems()) or 0
  local wanted, items = relevantItems(), {}
  for index = 1, count do
    local itemID = GetMerchantItemID and GetMerchantItemID(index)
    if itemID and wanted[itemID] then
      local price, stack, available, extended = merchantItem(index)
      items[#items + 1] = {
        itemID = itemID, price = price or 0, stack = stack or 1,
        available = available or -1, extended = extended and true or false,
      }
    end
  end
  if #items == 0 then return nil end
  local scan = npcContext()
  scan.items = items
  CraftinatorDB.vendorScans = CraftinatorDB.vendorScans or {}
  local key = tostring(scan.npcID or scan.npcName or "unknown")
  local isNew = CraftinatorDB.vendorScans[key] == nil
  CraftinatorDB.vendorScans[key] = scan
  return scan, isNew
end

ns.RegisterEvent("MERCHANT_SHOW", function()
  if not (CraftinatorDB and CraftinatorDB.capture) then return end
  local ok, scan, isNew = pcall(Capture.ScanVendor)
  if ok and scan and isNew then
    say(("recorded what %s sells (%d reagent or recipe item%s). /ci export shares it."):format(
      tostring(scan.npcName), #scan.items, #scan.items == 1 and "" or "s"))
  end
end)

-- Export -----------------------------------------------------------------------
-- One record per line, fields separated by ";". Read by tools/import_scans.py.

local function clean(value)
  return (tostring(value == nil and "" or value):gsub("[;\r\n|]", " "))
end

local function npcLine(kind, scan)
  return table.concat({
    kind, clean(scan.npcID), clean(scan.npcName), clean(scan.faction), clean(scan.mapID),
    scan.x and ("%.4f"):format(scan.x) or "", scan.y and ("%.4f"):format(scan.y) or "",
    clean(scan.zone), clean(scan.subzone), clean(scan.build),
  }, ";")
end

local function sortedKeys(tbl)
  local keys = {}
  for key in pairs(tbl or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

--- Everything recorded so far as text, plus how many trainers and vendors it covers.
function Capture.ExportText()
  local version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")
  local lines = { ("%s;%s;%s"):format(EXPORT_HEADER, clean(version or "?"), clean((select(2, GetBuildInfo())))) }
  local trainers, vendors = 0, 0
  for _, key in ipairs(sortedKeys(CraftinatorDB.trainerScans)) do
    local scan = CraftinatorDB.trainerScans[key]
    trainers = trainers + 1
    lines[#lines + 1] = npcLine("T", scan)
    for _, service in ipairs(scan.services or {}) do
      lines[#lines + 1] = table.concat({
        "S", clean(service.spellID), clean(service.skillRank or 0), clean(service.cost or 0), clean(service.name),
      }, ";")
    end
  end
  for _, key in ipairs(sortedKeys(CraftinatorDB.vendorScans)) do
    local scan = CraftinatorDB.vendorScans[key]
    vendors = vendors + 1
    lines[#lines + 1] = npcLine("V", scan)
    for _, item in ipairs(scan.items or {}) do
      lines[#lines + 1] = table.concat({
        "I", clean(item.itemID), clean(item.price), clean(item.stack), clean(item.available), item.extended and "1" or "0",
      }, ";")
    end
  end
  lines[#lines + 1] = "END"
  return table.concat(lines, "\n"), trainers, vendors
end

local window

local function createWindow()
  window = CreateFrame("Frame", "CraftinatorExport", UIParent, "BasicFrameTemplateWithInset")
  window:SetSize(520, 380)
  window:SetPoint("CENTER")
  window:SetFrameStrata("DIALOG")
  window:EnableMouse(true)
  window:Hide()
  table.insert(UISpecialFrames, "CraftinatorExport")
  local title = window.TitleText or (window.TitleContainer and window.TitleContainer.TitleText)
  if title then title:SetText("Craftinator export") end

  window.help = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  window.help:SetPoint("TOPLEFT", 14, -30)
  window.help:SetPoint("RIGHT", -14, 0)
  window.help:SetJustifyH("LEFT")

  local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -64)
  scroll:SetPoint("BOTTOMRIGHT", -34, 14)
  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject("ChatFontNormal")
  box:SetWidth(460)
  box:SetScript("OnEscapePressed", function() window:Hide() end)
  -- Keep the text as exported: typing in the box puts it back.
  box:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
      self:SetText(window.text or "")
      self:HighlightText()
    end
  end)
  scroll:SetScrollChild(box)
  window.box = box
end

--- /ci export: show everything recorded so far, selected and ready to copy.
function Capture.ShowExport()
  local text, trainers, vendors = Capture.ExportText()
  if trainers + vendors == 0 then
    say("nothing recorded yet. Open a profession trainer or a supply vendor first, then try again.")
    return
  end
  if not window then createWindow() end
  window.text = text
  window.help:SetText(("%d trainer%s and %d vendor%s recorded. Press Ctrl+C to copy, then paste it into a"
    .. " \"Submit data\" issue at github.com/MannixaDev/Craftinator, or send it to whoever gave you the addon.")
    :format(trainers, trainers == 1 and "" or "s", vendors, vendors == 1 and "" or "s"))
  window.box:SetText(text)
  window:Show()
  window.box:SetFocus()
  window.box:HighlightText()
end
