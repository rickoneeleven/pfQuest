-- Ensure pfQuest exists before creating debug module
pfQuest = pfQuest or {}
pfQuest.debug = CreateFrame("Frame")
pfQuest.debug.enabled = false
local maxLogEntries = 1000

local function GetTimestamp()
  local dt = date("*t")
  local gameTime = GetTime()
  local ms = math.floor((gameTime - math.floor(gameTime)) * 1000)
  return string.format("[%04d-%02d-%02d %02d:%02d:%02d.%03d]", 
    dt.year, dt.month, dt.day, dt.hour, dt.min, dt.sec, ms)
end

function pfQuest.debug.AddLog(level, message)
  -- Initialize table if somehow it became nil
  if not pfQuest_debuglog then
    pfQuest_debuglog = {}
  end
  
  -- Always log startup/shutdown messages even if not enabled
  if not pfQuest.debug.enabled and level ~= "INFO" then return end
  
  local timestamp = GetTimestamp()
  local logEntry = timestamp .. " [" .. level .. "] " .. message
  
  table.insert(pfQuest_debuglog, logEntry)
  
  if table.getn(pfQuest_debuglog) > maxLogEntries then
    table.remove(pfQuest_debuglog, 1)
  end
end

function pfQuest.debug.IsEnabled()
  return pfQuest.debug.enabled
end

function pfQuest.debug.SetEnabled(enabled)
  pfQuest.debug.enabled = enabled
  
  if enabled then
    pfQuest.debug.AddLog("INFO", "Debug logging enabled")
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfQuest Debug:|r Logging enabled - check WTF/Account/[Account]/SavedVariables/pfQuest.lua")
  else
    pfQuest.debug.AddLog("INFO", "Debug logging disabled")
  end
end

function pfQuest.debug.OnConfigChanged()
  if pfQuest_config and pfQuest_config["debuglog"] then
    pfQuest.debug.SetEnabled(pfQuest_config["debuglog"] == "1")
  end
end

pfQuest.debug:RegisterEvent("ADDON_LOADED")
pfQuest.debug:RegisterEvent("VARIABLES_LOADED")
pfQuest.debug:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    -- Initialize SavedVariables now that they're definitely loaded
    if not pfQuest_debuglog then
      pfQuest_debuglog = {}
    end
    
    -- Always add a startup message to ensure table is never empty
    local timestamp = GetTimestamp()
    table.insert(pfQuest_debuglog, timestamp .. " [INFO] pfQuest debug system initialized")
    
    -- Trim logs if too many
    if table.getn(pfQuest_debuglog) > maxLogEntries then
      local excess = table.getn(pfQuest_debuglog) - maxLogEntries
      for i = 1, excess do
        table.remove(pfQuest_debuglog, 1)
      end
    end
    
  elseif event == "ADDON_LOADED" and (arg1 == "pfQuest" or arg1 == "pfQuest-tbc" or arg1 == "pfQuest-wotlk") then
    -- Enable debug if configured
    if pfQuest_config and pfQuest_config["debuglog"] == "1" then
      pfQuest.debug.SetEnabled(true)
    end
  end
end)