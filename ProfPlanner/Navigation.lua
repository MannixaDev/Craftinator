-- Navigation.lua: trainer/vendor lookup, map pins, city toasts.

local _, ns = ...

local Navigation = {}
ns.Navigation = Navigation

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
      elseif not npc.profession then
        general[#general + 1] = npc
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

function Navigation.CityName(mapID)
  local info = C_Map.GetMapInfo(mapID)
  return info and info.name or (ns.Data.Cities and ns.Data.Cities[mapID]) or ("map " .. tostring(mapID))
end

--- Reminder when you enter a city with a trainer you need: shown when the character is
-- within 5 points of the skill cap, once per city and cap.
function Navigation.CheckCityToast()
  local last = ProfPlannerCharDB and ProfPlannerCharDB.last
  if not (ProfPlannerDB and ProfPlannerDB.toasts and last) then return end
  local profession = ns.Data.SkillLines and ns.Data.SkillLines[last.id]
  if not profession or last.max - last.skill > 5 then return end
  local mapID = C_Map.GetBestMapForUnit("player")
  local here = Navigation.Trainers(profession, (UnitFactionGroup("player")), mapID)
  local npc = Navigation.BestTrainer(here, last.max)
  if not npc or npc.maxSkill <= last.max then return end
  local key = profession .. ":" .. tostring(mapID) .. ":" .. last.max
  if ProfPlannerCharDB.dismissedToasts[key] then return end
  ProfPlannerCharDB.dismissedToasts[key] = true
  local text = ("ProfPlanner: %s %d/%d. %s (%s) here can train the next rank."):format(
    profession, last.skill, last.max, npc.name, npc.rank)
  if UIErrorsFrame and UIErrorsFrame.AddMessage then UIErrorsFrame:AddMessage(text, 1, 0.82, 0) end
  print("|cff33ff99" .. text .. "|r  Type /pp for a map pin.")
end

ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function() pcall(Navigation.CheckCityToast) end)

--- Place a map pin on an NPC. Uses TomTom when installed, else the built-in waypoint.
-- Returns true, or false and a reason.
function Navigation.SetWaypoint(npc)
  if TomTom and TomTom.AddWaypoint then
    local ok = pcall(TomTom.AddWaypoint, TomTom, npc.mapID, npc.x, npc.y,
      { title = npc.name, from = "ProfPlanner" })
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
