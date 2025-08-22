pfQuest.debug = CreateFrame("Frame")

if not pfQuest_debuglog then
  pfQuest_debuglog = {}
end

local debugEnabled = false
local maxLogEntries = 1000
local testTimer = nil

local function GetTimestamp()
  local date = date("*t")
  local time = GetTime()
  local ms = math.floor((time - math.floor(time)) * 1000)
  return string.format("[%04d-%02d-%02d %02d:%02d:%02d.%03d]", 
    date.year, date.month, date.day, date.hour, date.min, date.sec, ms)
end

function pfQuest.debug.AddLog(level, message)
  if not debugEnabled then return end
  
  local timestamp = GetTimestamp()
  local logEntry = timestamp .. " [" .. level .. "] " .. message
  
  table.insert(pfQuest_debuglog, logEntry)
  
  if table.getn(pfQuest_debuglog) > maxLogEntries then
    table.remove(pfQuest_debuglog, 1)
  end
end

function pfQuest.debug.IsEnabled()
  return debugEnabled
end

function pfQuest.debug.SetEnabled(enabled)
  debugEnabled = enabled
  
  if enabled and not testTimer then
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
  elseif not enabled and testTimer then
    testTimer:SetScript("OnUpdate", nil)
    testTimer = nil
    pfQuest.debug.AddLog("INFO", "Debug logging disabled")
  end
end

function pfQuest.debug.OnConfigChanged()
  if pfQuest_config and pfQuest_config["debuglog"] then
    pfQuest.debug.SetEnabled(pfQuest_config["debuglog"] == "1")
  end
end

pfQuest.debug:RegisterEvent("ADDON_LOADED")
pfQuest.debug:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and (arg1 == "pfQuest" or arg1 == "pfQuest-tbc" or arg1 == "pfQuest-wotlk") then
    if pfQuest_config and pfQuest_config["debuglog"] == "1" then
      pfQuest.debug.SetEnabled(true)
      pfQuest.debug.AddLog("INFO", "Debug logging enabled at startup")
    end
  end
end)