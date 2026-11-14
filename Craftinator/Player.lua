-- Player.lua: faction, location, skill levels, known recipes (WoW API adapters).
-- Forever-specific API differences are handled here, not in the callers.

local _, ns = ...

local Player = {}
ns.Player = Player

--- "Alliance" | "Horde" | nil
function Player.Faction()
  return (UnitFactionGroup("player"))
end

--- { mapID, mapName, zone, subzone }
function Player.Location()
  local mapID = C_Map.GetBestMapForUnit("player")
  local info = mapID and C_Map.GetMapInfo(mapID)
  return {
    mapID = mapID,
    mapName = info and info.name or GetZoneText(),
    zone = GetZoneText(),
    subzone = GetSubZoneText(),
  }
end

--- The profession shown in the open profession window:
-- { id = professionID, name = localised name, skill = current, max = current cap }, or nil.
function Player.OpenProfession()
  local info = C_TradeSkillUI.GetBaseProfessionInfo()
  if not info or not info.professionID or info.professionID == 0 then return nil end
  return {
    id = info.professionID,
    name = info.professionName,
    skill = info.skillLevel or 0,
    max = info.maxSkillLevel or 0,
  }
end

--- Set of recipe spell IDs the player has learned in the open profession window.
function Player.KnownRecipes()
  local known = {}
  for _, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
    local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
    if info and info.learned then known[recipeID] = true end
  end
  return known
end

--- The Blizzard profession window, or nil when it has not been loaded yet.
function Player.ProfessionFrame()
  return ProfessionsFrame
end

function Player.IsProfessionWindowShown()
  local frame = ProfessionsFrame
  return frame ~= nil and frame:IsShown()
end

--- Select a recipe in the open profession window. Returns true when it worked.
-- C_TradeSkillUI.OpenRecipe is protected on Forever, so this goes through the window's own list.
function Player.SelectRecipe(spellID)
  local frame = ProfessionsFrame
  local list = frame and frame:IsShown() and frame.CraftingPage and frame.CraftingPage.RecipeList
  if not list or type(list.SelectRecipe) ~= "function" then return false end
  local info = C_TradeSkillUI.GetRecipeInfo(spellID)
  if type(info) ~= "table" then return false end
  return (pcall(list.SelectRecipe, list, info, true))
end

--- Icon for a recipe spell, or nil.
function Player.SpellIcon(spellID)
  if C_Spell and C_Spell.GetSpellTexture then
    return (C_Spell.GetSpellTexture(spellID))
  end
  return nil
end
