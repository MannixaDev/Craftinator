std = "lua51"
max_line_length = 140
exclude_files = { ".luarocks", "lua_modules" }

-- Globals the addon defines.
globals = {
  "ProfPlanner",
  "ProfPlannerDB",
  "ProfPlannerCharDB",
  "SlashCmdList",
  "SLASH_PROFPLANNER1",
  "SLASH_PROFPLANNER2",
  "ProfPlanner_OnAddonCompartmentClick", "ProfPlanner_OnAddonCompartmentEnter", "ProfPlanner_OnAddonCompartmentLeave",
}

-- WoW API and other addons' globals the addon reads. Add to this as adapters are written.
read_globals = {
  "CreateFrame", "GetBuildInfo", "WOW_PROJECT_ID", "WOW_PROJECT_CAMELOT", "date",
  "UnitFactionGroup", "C_Map", "GetZoneText", "GetSubZoneText", "GetRealZoneText",
  "C_TradeSkillUI", "Enum",
  "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillLine", "GetProfessions", "GetNumSkillLines",
  "Auctionator", "TSM_API",
  "GetNumTrainerServices", "GetTrainerServiceInfo", "GetTrainerServiceSkillReq", "GetTrainerServiceCost",
  "GetTrainerServiceLevelReq", "GetTrainerServiceTypeFilter", "SetTrainerServiceTypeFilter",
  "UIParent", "UnitGUID", "UnitName", "strsplit",
  "ProfessionsFrame", "C_Spell", "C_Item", "TomTom", "UiMapPoint", "C_SuperTrack", "debugprofilestop",
  "GetItemCount", "UIErrorsFrame",
  "GameTooltip", "C_Timer", "UISpecialFrames", "CreateScrollBoxListLinearView", "ScrollUtil", "CreateDataProvider",
  "Settings",
}

files["spec"] = { std = "+busted" }

-- Pure-Lua modules: no WoW globals allowed, so an API call here fails the lint.
files["ProfPlanner/Optimiser.lua"] = { new_read_globals = {}, new_globals = {} }
files["ProfPlanner/Pricing.lua"] = { new_read_globals = {}, new_globals = {} }

-- Generated data: long lines are fine.
files["ProfPlanner/Data/Recipes_*.lua"] = { max_line_length = false }
