-- UI/Panel.lua: docked panel, route list, step tooltip.

local _, ns = ...

local Panel = {}
ns.Panel = Panel

local Pricing, Optimiser = ns.Pricing, ns.Optimiser

local COLOURS = {
  orange = { 1.00, 0.50, 0.25 },
  yellow = { 1.00, 1.00, 0.00 },
  green = { 0.25, 0.75, 0.25 },
  grey = { 0.50, 0.50, 0.50 },
  red = { 1.00, 0.25, 0.25 },
  white = { 1.00, 1.00, 1.00 },
}
local ROW_HEIGHT = 38
local WIDTH, HEIGHT = 360, 500
local DOCK_OFFSET = 50   -- clears the profession tabs on the window's right edge
local LIST_TOP, SLIDER_ROW = -172, 22 -- top of the route list; extra room the Balanced slider takes
local POLL_SECONDS = 0.5 -- how often the open panel checks for a profession or skill change

local frame
local docked = false
local hookedProfessionFrame = false

local function say(text)
  print("|cff33ff99Craftinator|r: " .. tostring(text))
end

-- Rows -----------------------------------------------------------------------

local function showStepTooltip(row)
  local entry = row.entry
  if not entry then return end
  local step, plan = entry.step, entry.plan
  local recipe = plan.recipes[step.spellID]
  local colour = COLOURS[step.difficulty] or COLOURS.orange

  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(recipe.name, colour[1], colour[2], colour[3])
  GameTooltip:AddLine(("Skill %d to %d"):format(step.fromSkill, step.toSkill), 1, 1, 1)
  GameTooltip:AddLine(("Skill-up chance at %d: %d%%"):format(
    step.fromSkill, math.floor(Optimiser.SkillUpChance(recipe, step.fromSkill) * 100 + 0.5)), 1, 1, 1)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(("Reagents for about %d crafts:"):format(step.crafts))
  for _, reagent in ipairs(recipe.reagents) do
    local price, source = plan.book.Get(reagent.itemID)
    local need = reagent.qty * step.crafts
    GameTooltip:AddDoubleLine(
      ("%d x %s"):format(need, ns.Inventory.ItemName(reagent.itemID)),
      price and ("%s (%s)"):format(Pricing.FormatMoney(price * need), source) or "price unknown",
      1, 1, 1, 1, 1, 1)
  end
  if recipe.station then
    GameTooltip:AddLine("Craft at: " .. recipe.station, 1, 0.82, 0)
  end
  for _, itemID in ipairs(recipe.tools or {}) do
    local have = ns.Inventory.Count(itemID) > 0
    GameTooltip:AddLine(("Needs tool: %s%s"):format(ns.Inventory.ItemName(itemID), have and " (you have it)" or ""),
      1, 0.82, 0)
  end
  if plan.useResale and recipe.output then
    local price = plan.book.PriceOf(recipe.output.itemID)
    GameTooltip:AddLine(price and ("Each craft sells for about %s."):format(
      Pricing.FormatMoney(price * (recipe.output.qty or 1))) or "No auction price for the crafted item.", 0.6, 0.6, 0.6)
  end
  if not plan.known[step.spellID] then
    GameTooltip:AddLine(" ")
    local how = recipe.sourceNote or (recipe.source == "trainer" and "Trainer" or recipe.source)
    GameTooltip:AddLine(("Not learned yet. Source: %s"):format(how), 1, 0.82, 0, true)
    if step.oneOffCost > 0 then
      GameTooltip:AddLine("Recipe cost: " .. Pricing.FormatMoney(step.oneOffCost), 1, 1, 1)
    end
    local vendor, price, limited = nil, nil, false
    if recipe.recipeItem then vendor, price, limited = ns.Navigation.VendorFor(recipe.recipeItem, ns.Player.Faction()) end
    if vendor then
      GameTooltip:AddLine(("Seen for sale: %s in %s, %s%s."):format(vendor.name, vendor.zone or ns.Navigation.CityName(vendor.mapID),
        Pricing.FormatMoney(price), limited and ", limited stock" or ""), 1, 1, 1, true)
    end
    -- Vendors from Zockify: { name, zone, mapID }. Your zone first; the other side's capitals left out.
    if recipe.vendors then
      local here, faction = ns.Player.Location(), ns.Player.Faction()
      local enemyCapital = faction == "Alliance" and { [1454] = true, [1456] = true, [1458] = true }
        or faction == "Horde" and { [1453] = true, [1455] = true, [1457] = true } or {}
      local near, far = {}, {}
      for _, v in ipairs(recipe.vendors) do
        if v[3] == here.mapID or v[2] == here.mapName or v[2] == here.zone then
          near[#near + 1] = ("|cff40ff40%s (%s, you are here)|r"):format(v[1], v[2])
        elseif not enemyCapital[v[3]] then
          far[#far + 1] = ("%s (%s)"):format(v[1], v[2])
        end
      end
      for _, line in ipairs(far) do near[#near + 1] = line end
      if #near > 0 then
        GameTooltip:AddLine("Sold by:", 1, 0.82, 0)
        for index = 1, math.min(6, #near) do GameTooltip:AddLine("  " .. near[index], 1, 1, 1) end
        if #near > 6 then GameTooltip:AddLine(("  and %d more"):format(#near - 6), 0.6, 0.6, 0.6) end
      end
    end
  end
  if recipe.learnEstimated and not plan.known[step.spellID] then
    GameTooltip:AddLine(("The skill needed to learn this is not known; assumed %d. It may be available earlier.")
      :format(recipe.learn), 0.6, 0.6, 0.6, true)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Click to select this recipe in the profession window.", 0.6, 0.6, 0.6, true)
  GameTooltip:Show()
end

-- Gathering rows: one herb, ore or fish, with what it sells for raw or crafted.
local function showGatherTooltip(row)
  local item, plan = row.entry.gather, row.entry.plan
  local colour = COLOURS[item.difficulty] or COLOURS.white
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine(ns.Inventory.ItemName(item.itemID), colour[1], colour[2], colour[3])
  if item.estimated then
    GameTooltip:AddLine(item.skill and ("Probably caught from about skill %d. This is a guess from its cooking"
      .. " recipe or where it is found."):format(item.skill) or "The skill needed to catch it is not known.",
      0.6, 0.6, 0.6, true)
  elseif item.skill then
    GameTooltip:AddLine(("%s: needs skill %d."):format(item.name, item.skill), 1, 1, 1)
  end
  if item.where then GameTooltip:AddLine("Where: " .. item.where, 1, 1, 1, true) end
  local price, source, age = plan.book.Get(item.itemID)
  GameTooltip:AddLine(price and ("Sells for %s each (%s%s)."):format(Pricing.FormatMoney(price), source,
    age and age > 0 and (", %d day%s old"):format(age, age == 1 and "" or "s") or "")
    or "No auction price.", 1, 1, 1)
  if #item.uses > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Worth per item when crafted into:")
    for index = 1, math.min(4, #item.uses) do
      local use = item.uses[index]
      GameTooltip:AddDoubleLine(("%s (%s)"):format(use.recipe.name, use.profession),
        Pricing.FormatMoney(use.value), 1, 1, 1, 1, 1, 1)
    end
    GameTooltip:AddLine("Other reagents are bought at their current price. You need the profession and recipe.",
      0.6, 0.6, 0.6, true)
  end
  GameTooltip:Show()
end

local function initGatherRow(row, entry)
  local item = entry.gather
  local colour = COLOURS[item.difficulty] or COLOURS.white
  row.icon:SetTexture(ns.Inventory.ItemIcon(item.itemID) or "Interface\\Icons\\INV_Misc_QuestionMark")
  local name = ns.Inventory.ItemName(item.itemID)
  if item.estimated then
    if item.difficulty == "red" then name = ("%s  (later, about %d)"):format(name, item.skill) end
  elseif item.skill then
    name = item.difficulty == "red" and ("%s  (at %d)"):format(name, item.skill) or ("%d  %s"):format(item.skill, name)
  end
  row.title:SetText(name)
  row.title:SetTextColor(colour[1], colour[2], colour[3])
  local detail = item.price and ("Sells %s"):format(Pricing.FormatMoney(item.price)) or "No auction price"
  local best = item.uses[1]
  if best and best.value > (item.price or 0) then
    detail = detail .. ("  -  %s as %s"):format(Pricing.FormatMoney(best.value), best.recipe.name)
  end
  row.detail:SetText(detail)
  row.current:SetShown(false)
end

local function initRow(row, entry)
  if not row.title then
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(30, 30)
    row.icon:SetPoint("LEFT", 4, 0)
    row.title = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 6, -1)
    row.title:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.title:SetJustifyH("LEFT")
    row.title:SetWordWrap(false)
    row.detail = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 6, 1)
    row.detail:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.detail:SetJustifyH("LEFT")
    row.detail:SetWordWrap(false)
    row.current = row:CreateTexture(nil, "BACKGROUND")
    row.current:SetAllPoints()
    row.current:SetColorTexture(1, 0.82, 0, 0.12)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnEnter", function(self)
      if not self.entry then return end
      if self.entry.gather then showGatherTooltip(self) else showStepTooltip(self) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
      if self.entry and self.entry.step and not ns.Player.SelectRecipe(self.entry.step.spellID) then
        say("could not select that recipe. Is the profession window open, and is the recipe learned?")
      end
    end)
  end

  row.entry = entry
  if entry.gather then return initGatherRow(row, entry) end
  local step, plan = entry.step, entry.plan
  local recipe = plan.recipes[step.spellID]
  local colour = COLOURS[step.difficulty] or COLOURS.orange

  -- The crafted item's icon: on Forever every recipe spell shares one generic icon.
  row.icon:SetTexture((recipe.output and ns.Inventory.ItemIcon(recipe.output.itemID))
    or ns.Player.SpellIcon(step.spellID) or "Interface\\Icons\\INV_Misc_QuestionMark")
  row.title:SetText(("%d-%d  %s"):format(step.fromSkill, step.toSkill, recipe.name))
  row.title:SetTextColor(colour[1], colour[2], colour[3])

  local detail = ("Craft about %d  -  %s"):format(step.crafts, Pricing.FormatMoney(step.cost))
  if step.unknown then detail = detail .. " + ?" end -- short, so "(learn first)" still fits; the footer explains
  if not plan.known[step.spellID] then detail = detail .. "  (learn first)" end
  row.detail:SetText(detail)
  row.current:SetShown(entry.index == 1)
end

-- Balanced slider ------------------------------------------------------------
-- A plain Slider (no template), so it does not depend on which templates this client has.

local SLIDER_MAX_SILVER, SLIDER_STEP_SILVER = 200, 5

--- Slider for what one craft's time is worth in Balanced mode. Call slider:Sync() to show the saved value.
function Panel.CreateBalanceSlider(parent)
  local slider = CreateFrame("Slider", nil, parent)
  slider:SetOrientation("HORIZONTAL")
  slider:SetSize(130, 16)
  slider:SetMinMaxValues(0, SLIDER_MAX_SILVER)
  slider:SetValueStep(SLIDER_STEP_SILVER)
  slider:SetObeyStepOnDrag(true)
  slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
  local thumb = slider:GetThumbTexture()
  if thumb then thumb:SetSize(24, 24) end
  local track = slider:CreateTexture(nil, "BACKGROUND")
  track:SetPoint("LEFT")
  track:SetPoint("RIGHT")
  track:SetHeight(4)
  track:SetColorTexture(0, 0, 0, 0.6)
  slider.label = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  slider.label:SetPoint("LEFT", slider, "RIGHT", 8, 0)

  local syncing = false
  local function describe()
    slider.label:SetText("One craft's time: " .. Pricing.FormatMoney(CraftinatorDB.balanceCopper))
  end
  function slider:Sync()
    syncing = true
    self:SetValue(math.min(SLIDER_MAX_SILVER, CraftinatorDB.balanceCopper / 100))
    syncing = false
    describe()
  end
  slider:SetScript("OnValueChanged", function(_, value)
    if syncing then return end
    local copper = math.floor(value / SLIDER_STEP_SILVER + 0.5) * SLIDER_STEP_SILVER * 100
    if copper == CraftinatorDB.balanceCopper then return end
    CraftinatorDB.balanceCopper = copper
    describe()
    Panel.RequestRefresh()
  end)
  slider:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Balanced mode")
    GameTooltip:AddLine("How much you would pay to skip one craft. At 0 the route is the cheapest one; the higher"
      .. " the value, the fewer crafts it uses. /ci balance <silver> sets a value beyond the slider.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  slider:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return slider
end

-- Frame ------------------------------------------------------------------------

local function create()
  if frame then return end
  frame = CreateFrame("Frame", "CraftinatorPanel", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not docked then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:SetScript("OnHide", function() docked = false end)
  -- Events for "a profession was picked" are not confirmed on Forever, so the open panel
  -- also watches for the profession or skill changing and refreshes when it does.
  local sinceCheck = 0
  frame:SetScript("OnUpdate", function(self, elapsed)
    sinceCheck = sinceCheck + elapsed
    if sinceCheck < POLL_SECONDS then return end
    sinceCheck = 0
    local profession = ns.Player.OpenProfession()
    local signature = profession and (profession.id .. ":" .. profession.skill .. ":" .. profession.max) or "none"
    if signature ~= self.signature then
      self.signature = signature
      Panel.Refresh()
    end
  end)
  frame:Hide()
  table.insert(UISpecialFrames, "CraftinatorPanel") -- Escape closes it

  local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
  if title then title:SetText("Craftinator") end

  -- Header: profession, skill, progress bar
  frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.header:SetPoint("TOPLEFT", 14, -32)
  frame.bar = CreateFrame("StatusBar", nil, frame)
  frame.bar:SetPoint("TOPLEFT", 14, -54)
  frame.bar:SetPoint("TOPRIGHT", -14, -54)
  frame.bar:SetHeight(10)
  frame.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  frame.bar:SetStatusBarColor(0.2, 0.6, 1)
  local barBackground = frame.bar:CreateTexture(nil, "BACKGROUND")
  barBackground:SetAllPoints()
  barBackground:SetColorTexture(0, 0, 0, 0.5)

  -- Location strip: where you are and the trainer to visit; click for a map pin
  frame.location = CreateFrame("Button", nil, frame)
  frame.location:SetPoint("TOPLEFT", 14, -68)
  frame.location:SetPoint("TOPRIGHT", -14, -68)
  frame.location:SetHeight(44)
  frame.location.text = frame.location:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.location.text:SetAllPoints()
  frame.location.text:SetJustifyH("LEFT")
  frame.location.text:SetJustifyV("TOP")
  frame.location:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  frame.location:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- Left click pins the trainer, right click the supply vendor.
  frame.location:SetScript("OnClick", function(self, button)
    local npc = self.npc
    if button == "RightButton" then npc = self.vendor end
    if not npc then return end
    if not npc.x then
      say(("%s is in %s; no map position is known for a pin."):format(npc.name, ns.Navigation.CityName(npc.mapID)))
      return
    end
    local ok, reason = ns.Navigation.SetWaypoint(npc)
    if ok then
      say(("map pin placed on %s in %s."):format(npc.name, ns.Navigation.CityName(npc.mapID)))
    else
      say(("could not place a pin: %s. %s is at %.1f, %.1f in %s."):format(
        tostring(reason), npc.name, npc.x * 100, npc.y * 100, ns.Navigation.CityName(npc.mapID)))
    end
  end)

  -- Mode buttons: Cheapest / Balanced / Fastest
  frame.modeButtons = {}
  local modes = { { "cheapest", "Cheapest" }, { "balanced", "Balanced" }, { "fastest", "Fastest" } }
  for index, mode in ipairs(modes) do
    local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(108, 22)
    button:SetPoint("TOPLEFT", 14 + (index - 1) * 112, -116)
    button:SetText(mode[2])
    button.mode = mode[1]
    button:SetScript("OnClick", function(self)
      CraftinatorDB.mode = self.mode
      Panel.Refresh()
    end)
    frame.modeButtons[index] = button
  end
  frame.modeButtons[2]:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Balanced")
    GameTooltip:AddLine(("Values the time of one craft at %s.\nA slider to change it appears in this mode."):format(
      Pricing.FormatMoney(CraftinatorDB.balanceCopper)), 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame.modeButtons[2]:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Filters: which recipe sources the route may use, and whether owned mats count as free
  frame.checks = {}
  local checks = {
    { "Trainer", "Use recipes taught by trainers.",
      function() return CraftinatorDB.sources.trainer end, function(on) CraftinatorDB.sources.trainer = on end },
    { "Vendor", "Use recipes sold by vendors for gold. Their price is added to the route once.",
      function() return CraftinatorDB.sources.vendor end, function(on) CraftinatorDB.sources.vendor = on end },
    { "Drops", "Use dropped, quest and other patterns, priced from the auction house."
        .. " Patterns with no auction price are left out.",
      function() return CraftinatorDB.sources.drop end, function(on) CraftinatorDB.sources.drop = on end },
    { "Owned", "Count reagents in your bags and bank as free. The bank is read when you open it.",
      function() return CraftinatorDB.useOwned end, function(on) CraftinatorDB.useOwned = on end },
    { "Resale", "Subtract the auction price of what you craft from each recipe's cost. Items that do not"
        .. " really sell can make a route look cheaper than it is.",
      function() return CraftinatorDB.useResale end, function(on) CraftinatorDB.useResale = on end },
  }
  for index, spec in ipairs(checks) do
    local check = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("TOPLEFT", 12 + (index - 1) * 67, -142)
    local label = check.Text or check.text
    if not label then
      label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      label:SetPoint("LEFT", check, "RIGHT", 0, 1)
    end
    label:SetFontObject("GameFontHighlightSmall")
    label:SetText(spec[1])
    check.get, check.set = spec[3], spec[4]
    check:SetScript("OnClick", function(self)
      self.set(self:GetChecked() and true or false)
      Panel.Refresh()
    end)
    check:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(spec[1])
      GameTooltip:AddLine(spec[2], 1, 1, 1, true)
      GameTooltip:Show()
    end)
    check:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.checks[index] = check
  end

  -- Balanced slider: only shown in Balanced mode, between the filters and the route
  frame.slider = Panel.CreateBalanceSlider(frame)
  frame.slider:SetPoint("TOPLEFT", 18, -170)

  -- Route list
  frame.scrollBox = CreateFrame("Frame", nil, frame, "WowScrollBoxList")
  frame.scrollBox:SetPoint("TOPLEFT", 12, LIST_TOP)
  frame.scrollBox:SetPoint("BOTTOMRIGHT", -30, 56)
  frame.scrollBar = CreateFrame("EventFrame", nil, frame, "MinimalScrollBar")
  frame.scrollBar:SetPoint("TOPLEFT", frame.scrollBox, "TOPRIGHT", 6, 0)
  frame.scrollBar:SetPoint("BOTTOMLEFT", frame.scrollBox, "BOTTOMRIGHT", 6, 0)
  local view = CreateScrollBoxListLinearView()
  view:SetElementExtent(ROW_HEIGHT)
  view:SetElementInitializer("Button", initRow)
  ScrollUtil.InitScrollBoxListWithScrollBar(frame.scrollBox, frame.scrollBar, view)

  frame.message = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.message:SetPoint("TOPLEFT", frame.scrollBox, "TOPLEFT", 8, -8)
  frame.message:SetPoint("RIGHT", frame.scrollBox, "RIGHT", -8, 0)
  frame.message:SetJustifyH("LEFT")

  -- Footer: route cost and price information
  frame.total = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.total:SetPoint("BOTTOMLEFT", 14, 32)
  frame.total:SetPoint("RIGHT", -14, 0)
  frame.total:SetJustifyH("LEFT")
  frame.shopping = CreateFrame("Button", nil, frame)
  frame.shopping:SetPoint("BOTTOMLEFT", 12, 28)
  frame.shopping:SetPoint("BOTTOMRIGHT", -12, 28)
  frame.shopping:SetHeight(22)
  frame.shopping:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  frame.shopping:SetScript("OnEnter", function(self) Panel.ShowShoppingTooltip(self) end)
  frame.shopping:SetScript("OnLeave", function() GameTooltip:Hide() end)
  frame.prices = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.prices:SetPoint("BOTTOMLEFT", 14, 14)
  frame.prices:SetPoint("RIGHT", -14, 0)
  frame.prices:SetJustifyH("LEFT")
  frame.prices:SetWordWrap(false)

  frame.send = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.send:SetSize(104, 20)
  frame.send:SetPoint("BOTTOMRIGHT", -10, 8)
  frame.send:SetText("To Auctionator")
  frame.send:SetScript("OnClick", function()
    if not frame.plan then return end
    say((select(2, ns.SendShoppingList(frame.plan))))
  end)
  frame.send:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Send to Auctionator")
    GameTooltip:AddLine("Creates an Auctionator shopping list of everything still to buy from the auction"
      .. " house. Vendor-sold reagents are left out.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame.send:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- The slider row only exists in Balanced mode; the route list moves down to make room.
local function layoutFor(mode, hasPlan, gathering)
  -- Gathering has no route options: the zone list takes their place.
  for _, button in ipairs(frame.modeButtons) do button:SetShown(not gathering) end
  for _, check in ipairs(frame.checks) do check:SetShown(not gathering) end
  frame.location:SetHeight(gathering and 96 or 44)
  hasPlan = hasPlan and not gathering
  local balanced = hasPlan and mode == "balanced"
  frame.slider:SetShown(balanced)
  if balanced then frame.slider:Sync() end
  frame.scrollBox:SetPoint("TOPLEFT", 12, LIST_TOP - (balanced and SLIDER_ROW or 0))
  local canSend = hasPlan and ns.HasAuctionator()
  frame.send:SetShown(canSend)
  frame.prices:SetPoint("RIGHT", frame, "RIGHT", canSend and -118 or -14, 0)
end

local function setRows(entries)
  frame.scrollBox:SetDataProvider(CreateDataProvider(entries))
end

local function priceLine(book)
  local summary = book.Summary()
  if not summary.sources.Auctionator and not summary.sources.TSM then
    if not ns.HasPriceAddon() then
      return "Auctionator not found: only vendor prices are known, so this route is a rough guess."
    end
    return "No auction prices found yet. Scan the auction house with Auctionator."
  end
  local age = summary.oldestAge
  local when = age == nil and "age unknown" or age == 0 and "scanned today" or
    ("oldest price %d day%s old"):format(age, age == 1 and "" or "s")
  return ("Prices: %s, %s%s"):format(
    summary.sources.Auctionator and "Auctionator" or "TSM", when, summary.stale and " (stale)" or "")
end

local function locationLine(plan)
  local location, faction = ns.Player.Location(), ns.Player.Faction()
  local here, elsewhere = ns.Navigation.Trainers(plan.profession, faction, location.mapID)
  local where = ("%s, %s"):format(tostring(location.mapName), tostring(faction))
  local left = plan.target - plan.skill
  if left <= 5 then
    where = where .. (left <= 0 and ". At your cap."
      or (". %d point%s from your cap."):format(left, left == 1 and "" or "s"))
  end
  local shops, pinnable = {}, nil
  local vendors = plan.kind == "gathering" and {} or ns.Navigation.Supplies(plan.profession, faction, location.mapID)
  for _, vendor in ipairs(vendors) do
    if #shops < 2 then shops[#shops + 1] = vendor.name end
    if vendor.x and not pinnable then pinnable = vendor end
  end
  frame.location.vendor = pinnable
  local supplies = #shops > 0 and ("\nSupplies here: " .. table.concat(shops, ", ") .. "."
    .. (pinnable and (" Right-click to pin %s."):format(pinnable.name) or "")) or ""
  -- A trainer only helps with the cap if they train past it.
  local cap = plan.target
  local npc = ns.Navigation.BestTrainer(here, cap)
  local away = ns.Navigation.BestTrainer(elsewhere, cap)
  if npc and npc.maxSkill > cap then
    return ("%s\nTrainer here: %s (%s). Click for a map pin.%s"):format(where, npc.name, npc.rank, supplies), npc
  end
  if away and away.maxSkill > cap then
    local lead = npc and (npc.name .. " here cannot raise your cap.") or ("No %s trainer listed here."):format(plan.profession)
    return ("%s\n%s Try %s in %s. Click for a pin.%s"):format(
      where, lead, away.name, ns.Navigation.CityName(away.mapID), supplies), away
  end
  if not npc and not away then
    return where .. "\nNo trainer data for this profession and faction." .. supplies, nil
  end
  -- No listed trainer goes past this cap: some ranks come from a book instead.
  local book = ns.Data.RankBooks and ns.Data.RankBooks[plan.profession] and ns.Data.RankBooks[plan.profession][cap]
  local seller = book and book[faction]
  if seller and book.quest then
    return ("%s\nPast %d: do the quest \"%s\" from %s in %s (level %d).%s"):format(where, cap, book.quest,
      seller[1], seller[2], book.needsLevel or 1, supplies), nil
  end
  if seller then
    return ("%s\nPast %d: buy %s (%s) from %s in %s.%s"):format(where, cap, book.item,
      Pricing.FormatMoney(book.cost), seller[1], seller[2], supplies), nil
  end
  return ("%s\nNo trainer is known to raise your cap past %d.%s"):format(where, cap, supplies), nil
end

function Panel.Refresh()
  if not frame or not frame:IsShown() then return end
  local plan, problem = ns.BuildPlan()
  if not plan then
    frame.header:SetText("Craftinator")
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(0)
    frame.location.text:SetText("")
    frame.location.npc = nil
    frame.location.vendor = nil
    frame.plan = nil
    frame.message:SetText(problem)
    frame.total:SetText("")
    frame.prices:SetText("")
    layoutFor(nil, false)
    setRows({})
    return
  end

  if plan.kind == "gathering" then return Panel.RefreshGathering(plan) end

  frame.plan = plan
  layoutFor(plan.mode, true)
  for _, button in ipairs(frame.modeButtons) do button:SetEnabled(button.mode ~= plan.mode) end
  for _, check in ipairs(frame.checks) do check:SetChecked(check.get()) end
  frame.header:SetText(("%s  %d / %d"):format(plan.displayName, plan.skill, plan.target))
  frame.bar:SetMinMaxValues(0, math.max(1, plan.target))
  frame.bar:SetValue(plan.skill)
  local text, npc = locationLine(plan)
  frame.location.text:SetText(text)
  frame.location.npc = npc

  local route = plan.route
  local entries = {}
  for index, step in ipairs(route.steps) do
    entries[index] = { index = index, step = step, plan = plan }
  end
  setRows(entries)

  if plan.skill >= plan.target then
    frame.message:SetText(("You are at your skill cap (%d). The line above says how to raise it."):format(plan.target))
  elseif #route.steps == 0 then
    frame.message:SetText("No usable recipe found for your current skill.")
  else
    frame.message:SetText("")
  end

  local total = ("To buy for %d: %s"):format(route.reachedSkill, Pricing.FormatMoney(plan.toBuy))
  if route.incomplete or plan.unpriced > 0 then total = total .. " + unknown prices" end
  total = total .. ("  (%d crafts)"):format(route.crafts)
  if not route.complete and #route.steps > 0 then
    total = total .. ("\n|cffff4040Route stops at %d: no usable recipe beyond that.|r"):format(route.reachedSkill)
  end
  frame.total:SetText(total)
  frame.prices:SetText(priceLine(plan.book) .. (plan.fromCache and "  (skill from your last visit)" or ""))
end

function Panel.RefreshGathering(plan)
  frame.plan = nil
  layoutFor(nil, false, true)
  frame.header:SetText(("%s  %d / %d"):format(plan.displayName, plan.skill, plan.target))
  frame.bar:SetMinMaxValues(0, math.max(1, plan.target))
  frame.bar:SetValue(plan.skill)
  frame.location.npc, frame.location.vendor = nil, nil

  local here = ns.Player.Location()
  local zones, inZone = {}, false
  for index, zone in ipairs(plan.zones) do
    if zone == here.mapName or zone == here.zone then
      inZone = true
      zone = "|cff40ff40" .. zone .. "|r"
    end
    zones[index] = zone
  end
  local text = ("Where to go for skill %d-%d:\n%s."):format(plan.bracket.from, plan.bracket.to,
    #zones > 0 and table.concat(zones, ", ") or "no zones listed")
  if inZone then text = text .. "\nYou are in one of them." end
  -- Near the cap, how to raise it comes first (trainer, book or quest).
  if plan.target - plan.skill <= 5 and plan.target < 300 then
    local capText, npc = locationLine(plan)
    text = capText .. "\n" .. text
    frame.location.npc = npc
  end
  frame.location.text:SetText(text)
  -- Fit the zone box to its text and start the list just below it.
  local height = math.min(120, math.max(30, math.ceil(frame.location.text:GetStringHeight()) + 4))
  frame.location:SetHeight(height)
  frame.scrollBox:SetPoint("TOPLEFT", 12, -68 - height - 6)

  local entries = {}
  for index, item in ipairs(plan.entries) do
    entries[index] = { index = index, gather = item, plan = plan }
  end
  setRows(entries)
  frame.message:SetText(#entries == 0 and "Nothing listed for this skill." or "")
  frame.total:SetText(plan.profession == "Fishing" and "Fish known to the addon, most valuable first."
    or "What you can gather at your skill, most valuable first.")
  frame.prices:SetText(priceLine(plan.book) .. (plan.fromCache and "  (skill from your last visit)" or ""))
end

--- Tooltip listing what still has to be bought for the route.
function Panel.ShowShoppingTooltip(owner)
  local plan = frame and frame.plan
  if not plan then return end
  GameTooltip:SetOwner(owner, "ANCHOR_TOPLEFT")
  GameTooltip:AddLine("Shopping list")
  local lines = 0
  for _, line in ipairs(plan.shopping) do
    if line.buy > 0 then
      lines = lines + 1
      local left = ("%d x %s"):format(line.buy, ns.Inventory.ItemName(line.itemID))
      if line.owned > 0 then left = left .. (" (have %d)"):format(line.owned) end
      GameTooltip:AddDoubleLine(left, line.cost and Pricing.FormatMoney(line.cost) or "price unknown", 1, 1, 1, 1, 1, 1)
    end
  end
  if lines == 0 then GameTooltip:AddLine("You already own every reagent.", 1, 1, 1) end
  if plan.recipeCosts > 0 then
    GameTooltip:AddDoubleLine("Recipes to buy", Pricing.FormatMoney(plan.recipeCosts), 1, 0.82, 0, 1, 1, 1)
  end
  if plan.useResale then
    GameTooltip:AddDoubleLine("What you craft sells for about", Pricing.FormatMoney(plan.resale), 0.25, 0.75, 0.25, 1, 1, 1)
  end
  local vendorLines = 0
  for _, line in ipairs(plan.shopping) do
    if line.buy > 0 and select(2, plan.book.Get(line.itemID)) == "Vendor" then vendorLines = vendorLines + 1 end
  end
  if vendorLines > 0 then
    GameTooltip:AddLine(("%d of these %s sold by supply vendors, not the auction house."):format(
      vendorLines, vendorLines == 1 and "is" or "are"), 0.6, 0.6, 0.6, true)
  end
  if not plan.useOwned then
    GameTooltip:AddLine("Mats you own are not subtracted (Owned is off).", 0.6, 0.6, 0.6, true)
  end
  GameTooltip:Show()
end

local refreshQueued = false
function Panel.RequestRefresh()
  if refreshQueued or not frame or not frame:IsShown() then return end
  refreshQueued = true
  C_Timer.After(0.2, function()
    refreshQueued = false
    Panel.Refresh()
  end)
end

-- Showing, docking -----------------------------------------------------------

local function show(dock)
  create()
  local professionFrame = ns.Player.ProfessionFrame()
  frame:ClearAllPoints()
  if dock and professionFrame then
    frame:SetPoint("TOPLEFT", professionFrame, "TOPRIGHT", DOCK_OFFSET, 0)
  else
    frame:SetPoint("CENTER")
  end
  frame:Show()
  docked = dock and professionFrame ~= nil
  ns.GetPricing().Clear()
  Panel.Refresh()
end

local function onProfessionShown()
  show(true)
end

local function onProfessionHidden()
  if frame and docked then frame:Hide() end
end

local function hookProfessionFrame()
  local professionFrame = ns.Player.ProfessionFrame()
  if hookedProfessionFrame or not professionFrame then return end
  hookedProfessionFrame = true
  professionFrame:HookScript("OnShow", onProfessionShown)
  professionFrame:HookScript("OnHide", onProfessionHidden)
  if professionFrame:IsShown() then onProfessionShown() end
end

--- /ci: show or hide the panel, docked if the profession window is open.
function Panel.Toggle()
  if frame and frame:IsShown() then
    frame:Hide()
  else
    show(ns.Player.IsProfessionWindowShown())
  end
end

-- Events ---------------------------------------------------------------------

ns.RegisterEvent("ADDON_LOADED", function(name)
  if name == "Blizzard_Professions" then hookProfessionFrame() end
end)
ns.RegisterEvent("PLAYER_LOGIN", hookProfessionFrame)
ns.RegisterEvent("TRADE_SKILL_SHOW", function()
  hookProfessionFrame()
  Panel.RequestRefresh()
end)
for _, event in ipairs({
  "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "SKILL_LINES_CHANGED", "NEW_RECIPE_LEARNED",
  "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED",
}) do
  ns.RegisterEvent(event, Panel.RequestRefresh)
end
