-- Navigation.lua: trainer/vendor lookup, map pins, city toasts.

local _, ns = ...

local Navigation = {}
ns.Navigation = Navigation

-- Recorded NPCs ---------------------------------------------------------------
-- Data/NPCs_Recorded.lua holds what players recorded in game. It is merged over the
-- hand-written list once, here: a recorded position or skill cap replaces the guess.

local RANK_FOR_CAP = { [75] = "Apprentice", [150] = "Journeyman", [225] = "Expert", [300] = "Artisan" }

local function applyRecord(npc, seen)
  npc.npcID, npc.mapID, npc.x, npc.y, npc.zone = seen.npcID, seen.mapID, seen.x, seen.y, seen.zone
  if seen.faction and seen.faction ~= "" then npc.faction = seen.faction end
  npc.verified = true
end

local function mergeRecorded()
  local npcs = ns.Data.NPCs
  for _, seen in ipairs(ns.Data.RecordedNPCs or {}) do
    if seen.role == "trainer" then
      for _, profession in ipairs(seen.professions or {}) do
        local found
        for _, npc in ipairs(npcs) do
          if npc.role == "trainer" and npc.name == seen.name and npc.profession == profession then
            found = npc
            break
          end
        end
        if not found then
          found = { name = seen.name, role = "trainer", profession = profession, maxSkill = seen.maxSkill or 0 }
          npcs[#npcs + 1] = found
        end
        applyRecord(found, seen)
        if seen.maxSkill then found.maxSkill = seen.maxSkill end
        found.rank = RANK_FOR_CAP[found.maxSkill] or found.rank or "Trainer"
      end
    else
      local matched = false
      for _, npc in ipairs(npcs) do
        if npc.role == "supplies" and npc.name == seen.name then
          matched = true
          applyRecord(npc, seen)
          npc.sells, npc.limited = seen.sells, seen.limited
        end
      end
      if not matched then
        local npc = { name = seen.name, role = "supplies", title = "Vendor", sells = seen.sells, limited = seen.limited }
        applyRecord(npc, seen)
        npcs[#npcs + 1] = npc
      end
    end
  end
end
mergeRecorded()

local reagentSets = {}

-- Does this vendor sell any reagent the profession's recipes use?
local function sellsReagentFor(npc, profession)
  local set = reagentSets[profession]
  if not set then
    set = {}
    for _, recipe in pairs(ns.Data.Recipes[profession] or {}) do
      for _, reagent in ipairs(recipe.reagents or {}) do set[reagent.itemID] = true end
    end
    reagentSets[profession] = set
  end
  for itemID in pairs(npc.sells) do
    if set[itemID] then return true end
  end
  return false
end

--- Who sells an item (a recipe pattern, say) to the player's faction, from recorded vendors.
-- Returns the vendor, the price for one, and whether the stock is limited; or nil.
function Navigation.VendorFor(itemID, faction)
  for _, npc in ipairs(ns.Data.NPCs or {}) do
    if npc.sells and npc.sells[itemID] and (not npc.faction or npc.faction == faction) then
      return npc, npc.sells[itemID], npc.limited and npc.limited[itemID] or false
    end
  end
end

--- Can the player's faction buy from a Zockify vendor entry { name, zone, mapID }?
-- False only when the vendor's zone belongs wholly to the other side (Data/NPCs.lua ZoneFaction).
function Navigation.VendorServes(vendor, faction)
  local side = ns.Data.ZoneFaction and ns.Data.ZoneFaction[vendor[3]]
  return not side or not faction or side == faction
end

--- True when every known vendor of a recipe serves only the other side, so buying it means the
-- auction house. A vendor recorded in game for the player's own faction counts against it.
function Navigation.OtherSideOnly(recipe, faction)
  if not recipe.vendors or #recipe.vendors == 0 then return false end
  if recipe.recipeItem and Navigation.VendorFor(recipe.recipeItem, faction) then return false end
  for _, vendor in ipairs(recipe.vendors) do
    if Navigation.VendorServes(vendor, faction) then return false end
  end
  return true
end

--- Trainers for a profession on the player's faction.
-- Returns here, elsewhere: trainers on the given map, and the rest.
function Navigation.Trainers(profession, faction, mapID)
  local here, elsewhere = {}, {}
  for _, npc in ipairs(ns.Data.NPCs or {}) do
    if npc.role == "trainer" and npc.profession == profession and (not npc.faction or npc.faction == faction) then
      if npc.mapID == mapID then
        here[#here + 1] = npc
      else
        elsewhere[#elsewhere + 1] = npc
      end
    end
  end
  return here, elsewhere
end

--- Supply vendors on the given map for the player's faction: the profession's own
-- supplier first, then general trade goods vendors.
function Navigation.Supplies(profession, faction, mapID)
  local own, general = {}, {}
  for _, npc in ipairs(ns.Data.NPCs or {}) do
    if npc.role == "supplies" and npc.mapID == mapID and (not npc.faction or npc.faction == faction) then
      if npc.profession == profession then
        own[#own + 1] = npc
      elseif not npc.profession and (not npc.sells or sellsReagentFor(npc, profession)) then
        general[#general + 1] = npc -- a general goods vendor; a recorded one must stock something useful
      end
    end
  end
  for _, npc in ipairs(general) do own[#own + 1] = npc end
  return own
end

--- From a list of trainers, the one to visit when the player's current cap is `cap`:
-- the lowest rank that trains past the cap, else the highest rank in the list.
function Navigation.BestTrainer(trainers, cap)
  local best
  for _, npc in ipairs(trainers) do
    if not best then
      best = npc
    else
      local npcPast, bestPast = npc.maxSkill > cap, best.maxSkill > cap
      if npcPast ~= bestPast then
        if npcPast then best = npc end
      elseif npcPast then
        if npc.maxSkill < best.maxSkill then best = npc end
      elseif npc.maxSkill > best.maxSkill then
        best = npc
      end
    end
  end
  return best
end

--- The nearest recorded station of a kind (see Capture.lua) on the player's continent.
-- Returns the record and its distance in yards, or nil.
function Navigation.NearestStation(station)
  local list = CraftinatorDB and CraftinatorDB.stations and CraftinatorDB.stations[station]
  if not list or not ns.Capture then return nil end
  local instance, wx, wy = ns.Capture.WorldPosition()
  if not instance then return nil end
  local best, bestDistance
  for _, seen in ipairs(list) do
    if seen.instance == instance then
      local distance = math.sqrt((seen.wx - wx) ^ 2 + (seen.wy - wy) ^ 2)
      if not bestDistance or distance < bestDistance then best, bestDistance = seen, distance end
    end
  end
  return best, bestDistance
end

function Navigation.CityName(mapID)
  local info = C_Map.GetMapInfo(mapID)
  return info and info.name or (ns.Data.Cities and ns.Data.Cities[mapID]) or ("map " .. tostring(mapID))
end

--- Reminder when you enter a city with a trainer you need: shown when the character is
-- within 5 points of the skill cap, once per city and cap.
function Navigation.CheckCityToast()
  local last = CraftinatorCharDB and CraftinatorCharDB.last
  if not (CraftinatorDB and CraftinatorDB.toasts and last) then return end
  local profession = ns.Data.SkillLines and ns.Data.SkillLines[last.id]
  if not profession or last.max - last.skill > 5 then return end
  local mapID = C_Map.GetBestMapForUnit("player")
  local here = Navigation.Trainers(profession, (UnitFactionGroup("player")), mapID)
  local npc = Navigation.BestTrainer(here, last.max)
  if not npc or npc.maxSkill <= last.max then return end
  local key = profession .. ":" .. tostring(mapID) .. ":" .. last.max
  if CraftinatorCharDB.dismissedToasts[key] then return end
  CraftinatorCharDB.dismissedToasts[key] = true
  local text = ("Craftinator: %s %d/%d. %s (%s) here can train the next rank."):format(
    profession, last.skill, last.max, npc.name, npc.rank)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
  print("|cff33ff99" .. text .. "|r  Type /ci for a map pin.")
end

ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() pcall(Navigation.CheckCityToast) end)

--- Place a map pin on an NPC. Uses TomTom when installed, else the built-in waypoint.
-- Returns true, or false and a reason.
function Navigation.SetWaypoint(npc)
  if TomTom and TomTom.AddWaypoint then
    local ok = pcall(TomTom.AddWaypoint, TomTom, npc.mapID, npc.x, npc.y,
      { title = npc.name, from = "Craftinator" })
    if ok then return true end
  end
  if not (C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates) then
    return false, "this client has no map pin API"
  end
  if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(npc.mapID) then
    return false, "the game does not allow a pin on that map"
  end
  local ok, err = pcall(function()
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(npc.mapID, npc.x, npc.y))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
      C_SuperTrack.SetSuperTrackedUserWaypoint(true)
    end
  end)
  if not ok then return false, tostring(err) end
  return true
end
