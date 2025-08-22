-- Ensure pfQuest exists before creating debug module
pfQuest = pfQuest or {}
pfQuest.debug = CreateFrame("Frame")
pfQuest.debug.enabled = false
local maxLogEntries = 1000
local testTimer = nil

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
  
  -- Also output to default chat for immediate feedback
  if level == "INFO" or level == "TEST" then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ffccpfQuest Debug:|r " .. logEntry)
  end
  
  if table.getn(pfQuest_debuglog) > maxLogEntries then
    table.remove(pfQuest_debuglog, 1)
  end
end

function pfQuest.debug.IsEnabled()
  return pfQuest.debug.enabled
end

function pfQuest.debug.SetEnabled(enabled)
  print("pfQuest debug: SetEnabled called with " .. tostring(enabled))
  pfQuest.debug.enabled = enabled
  
  if enabled and not testTimer then
    print("pfQuest debug: Creating test timer")
    testTimer = CreateFrame("Frame")
    testTimer.elapsed = 0
    testTimer:SetScript("OnUpdate", function()
      this.elapsed = this.elapsed + arg1
      if this.elapsed >= 5 then
        pfQuest.debug.AddLog("TEST", "Test debug text")
        this.elapsed = 0
      end
    end)
    pfQuest.debug.AddLog("INFO", "Debug logging enabled")
    -- Force an immediate test entry
    pfQuest.debug.AddLog("TEST", "Debug system activated - test entry")
    print("pfQuest debug: Debug system is now active")
  elseif not enabled and testTimer then
    print("pfQuest debug: Disabling debug system")
    testTimer:SetScript("OnUpdate", nil)
    testTimer = nil
    pfQuest.debug.AddLog("INFO", "Debug logging disabled")
  end
end

function pfQuest.debug.OnConfigChanged()
  print("pfQuest debug: OnConfigChanged called")
  if pfQuest_config and pfQuest_config["debuglog"] then
    print("pfQuest debug: Config debuglog = " .. tostring(pfQuest_config["debuglog"]))
    pfQuest.debug.SetEnabled(pfQuest_config["debuglog"] == "1")
  else
    print("pfQuest debug: No config or debuglog setting found")
  end
end

-- Add print for immediate feedback that module is loading
print("pfQuest debug.lua loading...")

pfQuest.debug:RegisterEvent("ADDON_LOADED")
pfQuest.debug:RegisterEvent("VARIABLES_LOADED")
pfQuest.debug:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    print("pfQuest debug: VARIABLES_LOADED event")
    -- Initialize SavedVariables now that they're definitely loaded
    if not pfQuest_debuglog then
      pfQuest_debuglog = {}
      print("pfQuest debug: Created new debuglog table")
    else
      print("pfQuest debug: Found existing debuglog with " .. table.getn(pfQuest_debuglog) .. " entries")
    end
    
    -- Always add a startup message to ensure table is never empty
    local timestamp = GetTimestamp()
    table.insert(pfQuest_debuglog, timestamp .. " [INFO] pfQuest debug system initialized")
    print("pfQuest debug: Added startup message")
    
    -- Trim logs if too many
    if table.getn(pfQuest_debuglog) > maxLogEntries then
      local excess = table.getn(pfQuest_debuglog) - maxLogEntries
      for i = 1, excess do
        table.remove(pfQuest_debuglog, 1)
      end
      print("pfQuest debug: Trimmed " .. excess .. " old log entries")
    end
    
  elseif event == "ADDON_LOADED" and (arg1 == "pfQuest" or arg1 == "pfQuest-tbc" or arg1 == "pfQuest-wotlk") then
    print("pfQuest debug: ADDON_LOADED event for " .. arg1)
    
    -- Enable debug if configured
    if pfQuest_config and pfQuest_config["debuglog"] == "1" then
      print("pfQuest debug: Auto-enabling debug from config")
      pfQuest.debug.SetEnabled(true)
    else
      print("pfQuest debug: Debug not enabled in config")
    end
  end
end)