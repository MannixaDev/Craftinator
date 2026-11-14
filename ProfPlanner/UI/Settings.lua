-- UI/Settings.lua: options panel (Game Menu > Options > AddOns > ProfPlanner, or /pp config)
-- and the entry in the addon menu next to the minimap.

local addonName, ns = ...

local Settings_ = {}
ns.Settings = Settings_

local panel, category
local controls = {}

local function refreshPanel()
  if ns.Panel then ns.Panel.RequestRefresh() end
end

local function addCheck(parent, y, label, tip, get, set)
  local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  check:SetSize(26, 26)
  check:SetPoint("TOPLEFT", 16, y)
  local text = check.Text or check.text
  if not text then
    text = check:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 2, 1)
  end
  text:SetFontObject("GameFontHighlight")
  text:SetText(label)
  check:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    refreshPanel()
  end)
  check:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(label)
    GameTooltip:AddLine(tip, 1, 1, 1, true)
    GameTooltip:Show()
  end)
  check:SetScript("OnLeave", function() GameTooltip:Hide() end)
  check.Sync = function(self) self:SetChecked(get()) end
  controls[#controls + 1] = check
  return check
end

local function addHeading(parent, y, text)
  local heading = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  heading:SetPoint("TOPLEFT", 16, y)
  heading:SetText(text)
end

local function build()
  panel = CreateFrame("Frame")
  panel.name = "ProfPlanner"
  panel:Hide()

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("ProfPlanner")

  local db = function() return ProfPlannerDB end

  addHeading(panel, -50, "Route")
  local modes = { { "cheapest", "Cheapest" }, { "balanced", "Balanced" }, { "fastest", "Fastest" } }
  for index, mode in ipairs(modes) do
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(100, 22)
    button:SetPoint("TOPLEFT", 16 + (index - 1) * 104, -68)
    button:SetText(mode[2])
    button:SetScript("OnClick", function()
      db().mode = mode[1]
      Settings_.Sync()
      refreshPanel()
    end)
    button.Sync = function(self) self:SetEnabled(db().mode ~= mode[1]) end
    controls[#controls + 1] = button
  end
  local slider = ns.Panel.CreateBalanceSlider(panel)
  slider:SetPoint("TOPLEFT", 20, -100)
  controls[#controls + 1] = slider

  addHeading(panel, -134, "Recipes the route may use")
  addCheck(panel, -150, "Trainer recipes", "Use recipes taught by trainers.",
    function() return db().sources.trainer end, function(on) db().sources.trainer = on end)
  addCheck(panel, -176, "Vendor recipes", "Use recipes sold by vendors for gold. Their price is added to the route once.",
    function() return db().sources.vendor end, function(on) db().sources.vendor = on end)
  addCheck(panel, -202, "Drops, quest rewards and other patterns",
    "Priced from the auction house. Patterns with no auction price are left out.",
    function() return db().sources.drop end, function(on) db().sources.drop = on end)

  addHeading(panel, -240, "Costs")
  addCheck(panel, -256, "Count reagents I own as free",
    "Reagents in your bags and bank cost nothing. The bank is read when you open it.",
    function() return db().useOwned end, function(on) db().useOwned = on end)
  addCheck(panel, -282, "Subtract what the crafted items sell for",
    "Uses the auction price of each crafted item. Items that do not really sell can make a route look cheaper than it is.",
    function() return db().useResale end, function(on) db().useResale = on end)

  addHeading(panel, -320, "Reminders")
  addCheck(panel, -336, "Remind me when I enter a city with a trainer I need",
    "Shown when you are within 5 points of your skill cap, once per city.",
    function() return db().toasts end, function(on) db().toasts = on end)

  local prices = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  prices:SetPoint("TOPLEFT", 16, -376)
  prices:SetText("Prices: vendor price first, then Auctionator, then TSM.")

  panel:SetScript("OnShow", Settings_.Sync)
end

function Settings_.Sync()
  for _, control in ipairs(controls) do control:Sync() end
end

--- Open the options panel.
function Settings_.Open()
  if category and Settings and Settings.OpenToCategory then
    if pcall(Settings.OpenToCategory, category:GetID()) then return end
  end
  print("|cff33ff99ProfPlanner|r: could not open the options panel. The same switches are on the /pp panel.")
end

ns.RegisterEvent("PLAYER_LOGIN", function()
  if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
  local ok = pcall(function()
    build()
    category = Settings.RegisterCanvasLayoutCategory(panel, "ProfPlanner")
    Settings.RegisterAddOnCategory(category)
  end)
  if not ok then category = nil end
end)

-- Addon menu next to the minimap (named in the .toc). Left click: panel. Right click: options.
function ProfPlanner_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then
    Settings_.Open()
  else
    ns.Panel.Toggle()
  end
end

function ProfPlanner_OnAddonCompartmentEnter(_, menuButton)
  GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
  GameTooltip:AddLine(addonName)
  GameTooltip:AddLine("Left click: show or hide the route panel.", 1, 1, 1)
  GameTooltip:AddLine("Right click: options.", 1, 1, 1)
  GameTooltip:Show()
end

function ProfPlanner_OnAddonCompartmentLeave()
  GameTooltip:Hide()
end
