-- table.getn doesn't return sizes on tables that
-- are using a named index on which setn is not updated
local function tablesize(tbl)
  local count = 0
  for _ in pairs(tbl) do count = count + 1 end
  return count
end

function modulo(val, by)
  return val - math.floor(val/by)*by;
end

local function GetNearest(xstart, ystart, db, blacklist)
  local nearest = nil
  local best = nil

  for id, data in pairs(db) do
    if data[1] and data[2] and not blacklist[id] then
      local x,y = xstart - data[1], ystart - data[2]
      local distance = ceil(math.sqrt(x*x+y*y)*100)/100

      if not nearest or distance < nearest then
        nearest = distance
        best = id
      end
    end
  end

  if not best then 
    if pfQuest.debug and pfQuest.debug.IsEnabled() then
      pfQuest.debug.AddLog("WARNING", "GetNearest found no valid points from (" .. xstart .. "," .. ystart .. ")")
    end
    return 
  end

  if pfQuest.debug and pfQuest.debug.IsEnabled() then
    pfQuest.debug.AddLog("DEBUG", "GetNearest selected point (" .. db[best][1] .. "," .. db[best][2] .. ") at distance " .. nearest)
  end
  blacklist[best] = true
  return db[best]
end

-- connection between objectives
local objectivepath = {}

-- connection between player and the first objective
local playerpath = {} -- worldmap
local mplayerpath = {} -- minimap

local function ClearPath(path)
  for id, tex in pairs(path) do
    tex.enable = nil
    tex:Hide()
  end
end

local function DrawLine(path,x,y,nx,ny,hl,minimap)
  local display = true
  local zoom = 1

  -- calculate minimap variables
  local xplayer, yplayer, xdraw, ydraw
  if minimap then
    -- player coords
    xplayer, yplayer = GetPlayerMapPosition("player")
    xplayer, yplayer = xplayer * 100, yplayer * 100

    -- query minimap zoom/size data
    local mZoom = pfMap.drawlayer:GetZoom()
    local mapID = pfMap:GetMapIDByName(GetRealZoneText())
    local mapZoom = pfMap.minimap_zoom[pfMap.minimap_indoor()][mZoom]
    local mapWidth = pfMap.minimap_sizes[mapID] and pfMap.minimap_sizes[mapID][1] or 0
    local mapHeight = pfMap.minimap_sizes[mapID] and pfMap.minimap_sizes[mapID][2] or 0

    -- calculate drawlayer size
    xdraw = pfMap.drawlayer:GetWidth() / (mapZoom / mapWidth) / 100
    ydraw = pfMap.drawlayer:GetHeight() / (mapZoom / mapHeight) / 100
    zoom = (((mapZoom / mapWidth))+((mapZoom / mapHeight))) * 3
  end

  -- general
  local dx, dy = x - nx, y - ny
  local dots = ceil(math.sqrt(dx*1.5*dx*1.5+dy*dy)) / zoom

  for i=(minimap and 1 or 2), dots-(minimap and 1 or 2) do
    local xpos = nx + dx/dots*i
    local ypos = ny + dy/dots*i

    if minimap then
      -- adjust values to minimap
      xpos = ( xplayer - xpos ) * xdraw
      ypos = ( yplayer - ypos ) * ydraw

      -- check if dot should be visible
      if pfUI.minimap then
        display = ( abs(xpos) + 1 < pfMap.drawlayer:GetWidth() / 2 and abs(ypos) + 1 < pfMap.drawlayer:GetHeight()/2 ) and true or nil
      else
        local distance = sqrt(xpos * xpos + ypos * ypos)
        display = ( distance + 1 < pfMap.drawlayer:GetWidth() / 2 ) and true or nil
      end
    else
      -- adjust values to worldmap
      xpos = xpos / 100 * WorldMapButton:GetWidth()
      ypos = ypos / 100 * WorldMapButton:GetHeight()
    end

    if display then
      local nline = tablesize(path) + 1
      for id, tex in pairs(path) do
        if not tex.enable then nline = id break end
      end

      path[nline] = path[nline] or (minimap and pfMap.drawlayer or WorldMapButton.routes):CreateTexture(nil, "OVERLAY")
      path[nline]:SetWidth(4)
      path[nline]:SetHeight(4)
      path[nline]:SetTexture(pfQuestConfig.path.."\\img\\route")
      if hl and minimap then
        path[nline]:SetVertexColor(.6,.4,.2,.5)
      elseif hl then
        path[nline]:SetVertexColor(1,.8,.4,1)
      else
        path[nline]:SetVertexColor(.6,.4,.2,1)
      end

      path[nline]:ClearAllPoints()

      if minimap then -- draw minimap
        path[nline]:SetPoint("CENTER", pfMap.drawlayer, "CENTER", -xpos, ypos)
      else -- draw worldmap
        path[nline]:SetPoint("CENTER", WorldMapButton, "TOPLEFT", xpos, -ypos)
      end

      path[nline]:Show()
      path[nline].enable = true
    end
  end
end

pfQuest.route = CreateFrame("Frame", "pfQuestRoute", WorldFrame)
pfQuest.route.firstnode = nil
pfQuest.route.coords = {}

pfQuest.route.Reset = function(self)
  self.coords = {}
  self.firstnode = nil
end

pfQuest.route.AddPoint = function(self, tbl)
  table.insert(self.coords, tbl)
  self.firstnode = nil
  if pfQuest.debug and pfQuest.debug.IsEnabled() then
    local questName = tbl[3] and tbl[3].title or "Unknown"
    local questLevel = tbl[3] and tbl[3].qlvl or "?"
    pfQuest.debug.AddLog("DEBUG", "AddPoint: Added coordinate for [" .. questLevel .. "] '" .. questName .. "'")
  end
end

local targetTitle, targetCluster, targetLayer, targetTexture = nil, nil, nil, nil
pfQuest.route.SetTarget = function(node, default)
  if node and ( node.title ~= targetTitle
    or node.cluster ~= targetCluster
    or node.layer ~= targetLayer
    or node.texture ~= targetTexture )
  then
    pfMap.queue_update = true
  end

  targetTitle = node and node.title or nil
  targetCluster = node and node.cluster or nil
  targetLayer = node and node.layer or nil
  targetTexture = node and node.texture or nil
end

pfQuest.route.IsTarget = function(node)
  if node then
    if targetTitle and targetTitle == node.title
      and targetCluster == node.cluster
      and targetLayer == node.layer
      and targetTexture == node.texture
    then
      return true
    end
  end
  return nil
end

local lastpos, completed = 0, 0
local manualQuestName = nil
local manualQuestLevel = nil
local function sortfunc(a,b) return a[4] < b[4] end

local function getQuestLevel(questid, questTitle)
  -- Try numeric quest ID first
  if tonumber(questid) then
    return pfDB["quests"]["data"][questid] and pfDB["quests"]["data"][questid]["lvl"]
  else
    -- Try to find quest by title for non-database quests
    for qid, qdata in pairs(pfDB["quests"]["loc"] or {}) do
      if qdata.T == questTitle then
        return pfDB["quests"]["data"][tonumber(qid)] and pfDB["quests"]["data"][tonumber(qid)]["lvl"]
      end
    end
  end
  return nil
end

local function sortfunc_level(a, b)
  -- Get quest levels (default to 999 for missing levels to sort to bottom)
  local alvl = a[3] and a[3].qlvl or 999
  local blvl = b[3] and b[3].qlvl or 999
  
  -- Sort by level first (lowest first)
  if alvl ~= blvl then
    return alvl < blvl
  end
  
  -- Same level: fallback to distance
  return a[4] < b[4]
end
pfQuest.route:SetScript("OnUpdate", function()
  -- Debug: log route function activity (throttled)
  if pfQuest.debug and pfQuest.debug.IsEnabled() and (not this.debug_throttle or this.debug_throttle < GetTime()) then
    pfQuest.debug.AddLog("DEBUG", "Route OnUpdate function called")
    this.debug_throttle = GetTime() + 10  -- Only log every 10 seconds to avoid spam
  end

  local xplayer, yplayer = GetPlayerMapPosition("player")
  local wrongmap = xplayer == 0 and yplayer == 0 and true or nil
  local curpos = xplayer + yplayer

  -- limit distance and route updates to once per .1 seconds
  if ( this.tick or 5) > GetTime() and lastpos == curpos then return else this.tick = GetTime() + 1 end

  -- limit to a maxium of each .05 seconds even on position change
  if ( this.throttle or .2) > GetTime() then return else this.throttle = GetTime() + .05 end

  -- save current position
  lastpos = curpos

  -- update distances to player
  for id, data in pairs(this.coords) do
    if data[1] and data[2] then
      local x, y = (xplayer*100 - data[1])*1.5, yplayer*100 - data[2]
      this.coords[id][4] = ceil(math.sqrt(x*x+y*y)*100)/100
    end
  end

  -- Debug: always log when route calculation is called
  if pfQuest.debug and pfQuest.debug.IsEnabled() then
    pfQuest.debug.AddLog("DEBUG", "Route calculation called with " .. table.getn(this.coords) .. " total coordinates")
  end

  -- sort all coords by distance only once per second
  if not this.recalculate or this.recalculate < GetTime() then
    if pfQuest.debug and pfQuest.debug.IsEnabled() then
      pfQuest.debug.AddLog("DEBUG", "Starting route recalculation with " .. table.getn(this.coords) .. " coordinates")
      
      -- Log quest information and zone context
      local currentZone = GetRealZoneText()
      if currentZone then
        pfQuest.debug.AddLog("INFO", "Player in zone: " .. currentZone)
      end
      
      -- Get all quests from quest log first
      local allQuests = {}
      for questid, questdata in pairs(pfQuest.questlog or {}) do
        local questTitle = questdata.title or tostring(questid)
        allQuests[questTitle] = {
          id = questid,
          hasNodes = false,
          nodeCount = 0,
          zones = {},
          reason = "No routable objectives found"
        }
      end
      
      -- Analyze coordinates by quest
      local questCoords = {}
      local zonesFound = {}
      for id, data in pairs(this.coords) do
        if data[3] and data[3].title then
          local questName = data[3].title
          local questZone = data[3].zone or "Unknown"
          
          if not questCoords[questName] then
            questCoords[questName] = {count = 0, zones = {}}
          end
          questCoords[questName].count = questCoords[questName].count + 1
          questCoords[questName].zones[questZone] = true
          zonesFound[questZone] = (zonesFound[questZone] or 0) + 1
          
          -- Mark quest as having nodes
          if allQuests[questName] then
            allQuests[questName].hasNodes = true
            allQuests[questName].nodeCount = questCoords[questName].count
            allQuests[questName].zones = questCoords[questName].zones
            allQuests[questName].reason = nil
          end
        end
      end
      
      -- Complete quest log analysis
      local routingMode = pfQuest_config["routebyquestlevel"] == "1" and "LEVEL-BASED" or "DISTANCE-BASED"
      pfQuest.debug.AddLog("INFO", "========== COMPLETE QUEST LOG ANALYSIS (" .. routingMode .. ") ==========")
      
      -- Count totals
      local routableCount = 0
      local skippedCount = 0
      for _, info in pairs(allQuests) do
        if info.hasNodes then 
          routableCount = routableCount + 1
        else 
          skippedCount = skippedCount + 1 
        end
      end
      
      pfQuest.debug.AddLog("INFO", "Total quests: " .. (routableCount + skippedCount) .. " (" .. routableCount .. " routable, " .. skippedCount .. " skipped)")
      
      -- Log routable quests
      if routableCount > 0 then
        pfQuest.debug.AddLog("INFO", "--- ROUTABLE QUESTS ---")
        for questName, info in pairs(allQuests) do
          if info.hasNodes then
            local zones = ""
            for zone, _ in pairs(info.zones) do
              zones = zones .. zone .. " "
            end
            local questLevel = getQuestLevel(info.id, questName) or "?"
            pfQuest.debug.AddLog("INFO", "[✓] [" .. questLevel .. "] '" .. questName .. "' - " .. info.nodeCount .. " objectives in " .. zones)
          end
        end
      end
      
      -- Log skipped quests with reasons
      if skippedCount > 0 then
        pfQuest.debug.AddLog("INFO", "--- SKIPPED QUESTS (No Routing) ---")
        for questName, info in pairs(allQuests) do
          if not info.hasNodes then
            local questLevel = getQuestLevel(info.id, questName) or "?"
            pfQuest.debug.AddLog("INFO", "[✗] [" .. questLevel .. "] '" .. questName .. "' - " .. info.reason)
          end
        end
      end
      
      -- Log zones summary
      local otherZones = ""
      for zone, count in pairs(zonesFound) do
        if zone ~= currentZone then
          otherZones = otherZones .. zone .. "(" .. count .. ") "
        end
      end
      if otherZones ~= "" then
        pfQuest.debug.AddLog("INFO", "Cross-zone objectives found in: " .. otherZones)
      end
    end
    -- Choose sort function based on config
    if pfQuest_config["routebyquestlevel"] == "1" then
      table.sort(this.coords, sortfunc_level)
    else
      table.sort(this.coords, sortfunc)
    end
    
    -- When level routing is enabled, verify we're routing to the absolute lowest quest
    if pfQuest_config["routebyquestlevel"] == "1" then
      -- Find the absolute lowest level quest in questlog
      local absoluteLowestQuest = nil
      local absoluteLowestLevel = 999
      local absoluteLowestQuestId = nil
      
      for questid, questdata in pairs(pfQuest.questlog or {}) do
        local qlvl = getQuestLevel(questid, questdata.title)
        if qlvl and qlvl < absoluteLowestLevel then
          absoluteLowestLevel = qlvl
          absoluteLowestQuest = questdata.title
          absoluteLowestQuestId = questid
        end
      end
      
      -- Capture routable quest info before any clearing
      local routableQuestCount = 0
      local routableQuests = {}
      for id, data in pairs(this.coords) do
        if data[3] and data[3].title then
          local questLevel = data[3].qlvl or "?"
          routableQuests[data[3].title] = questLevel
          routableQuestCount = routableQuestCount + 1
        end
      end
      
      -- Check if we have coords for the absolute lowest quest
      local hasRoutingForLowest = false
      if this.coords[1] and this.coords[1][3] then
        local routedLevel = this.coords[1][3].qlvl or 999
        if routedLevel == absoluteLowestLevel then
          hasRoutingForLowest = true
        end
      end
      
      -- If the absolute lowest quest has no routing, set state for manual completion
      if absoluteLowestQuest and not hasRoutingForLowest then
        if pfQuest.debug and pfQuest.debug.IsEnabled() then
          pfQuest.debug.AddLog("INFO", "Level routing: Found " .. routableQuestCount .. " routable quests, but forcing manual completion of lowest quest [" .. absoluteLowestLevel .. "] '" .. absoluteLowestQuest .. "'")
          
          -- Show what we're bypassing
          if routableQuestCount > 0 then
            pfQuest.debug.AddLog("INFO", "--- BYPASSED ROUTABLE QUESTS ---")
            for questName, questLevel in pairs(routableQuests) do
              pfQuest.debug.AddLog("INFO", "  Bypassing: [" .. questLevel .. "] '" .. questName .. "' - has routing but not lowest level")
            end
          end
        end
        
        -- Set persistent state for manual completion
        manualQuestName = absoluteLowestQuest
        manualQuestLevel = absoluteLowestLevel
        
        -- Clear coords to prevent normal routing
        this.coords = {}
        ClearPath(objectivepath)
        ClearPath(playerpath) 
        ClearPath(mplayerpath)
        return
      else
        -- Clear manual state if we have routing for lowest quest
        manualQuestName = nil
        manualQuestLevel = nil
      end
    end
    
    -- Log routing decision after sorting
    if pfQuest.debug and pfQuest.debug.IsEnabled() and this.coords[1] then
      local selectedQuest = this.coords[1][3] and this.coords[1][3].title or "Unknown Quest"
      local selectedLevel = this.coords[1][3] and this.coords[1][3].qlvl or "?"
      local distance = this.coords[1][4] or 0
      local routingBy = pfQuest_config["routebyquestlevel"] == "1" and "level" or "distance"
      pfQuest.debug.AddLog("INFO", "Auto-routing (" .. routingBy .. "): [" .. selectedLevel .. "] '" .. selectedQuest .. "' at " .. string.format("%.1f", distance) .. " units")
      
      -- Show alternatives for context
      if this.coords[2] then
        local altQuest = this.coords[2][3] and this.coords[2][3].title or "Unknown Quest"
        local altLevel = this.coords[2][3] and this.coords[2][3].qlvl or "?"
        local altDistance = this.coords[2][4] or 0
        pfQuest.debug.AddLog("DEBUG", "Next option: [" .. altLevel .. "] '" .. altQuest .. "' at " .. string.format("%.1f", altDistance) .. " units")
      end
    end

    -- order list on custom targets
    if targetTitle and this.coords[1] and not pfQuest.route.IsTarget(this.coords[1][3]) then
      local target = nil

      -- check for the old index of the target
      for id, data in pairs(this.coords) do
        if pfQuest.route.IsTarget(data[3]) then
          target = id
          break
        end
      end

      -- rearrange coordinates
      if target then
        if pfQuest.debug and pfQuest.debug.IsEnabled() then
          local targetQuest = this.coords[target][3] and this.coords[target][3].title or "Unknown Quest"
          pfQuest.debug.AddLog("INFO", "Manual target prioritized: '" .. targetQuest .. "' (was index " .. target .. ")")
        end
        local tmp = {}
        table.insert(tmp, this.coords[target])

        for id, data in pairs(this.coords) do
          if id ~= target then
            table.insert(tmp, this.coords[id])
          end
        end

        this.coords = tmp
      end
    end

    this.recalculate = GetTime() + 1
  end

  -- show arrow when route exists and is stable
  if not wrongmap and this.coords[1] and this.coords[1][4] and not this.arrow:IsShown() and pfQuest_config["arrow"] == "1" and GetTime() > completed + 1 then
    this.arrow:Show()
  end

  -- Handle manual completion display outside recalculation
  if manualQuestName and manualQuestLevel and pfQuest_config["arrow"] == "1" then
    local color = pfMap:HexDifficultyColor(manualQuestLevel) or "|cffff5555"
    pfQuest.route.arrow.title:SetText(color .. "[" .. manualQuestLevel .. "] " .. manualQuestName .. "|r")
    pfQuest.route.arrow.description:SetText("|cffffcc00Complete manually - no route available|r")
    pfQuest.route.arrow.texture:SetTexture(pfQuestConfig.path.."\\img\\node")
    pfQuest.route.arrow.texture:SetVertexColor(1, 0.5, 0.5, 1)
    pfQuest.route.arrow:Show()
    if pfQuest.debug and pfQuest.debug.IsEnabled() then
      pfQuest.debug.AddLog("DEBUG", "Manual completion arrow displayed for [" .. manualQuestLevel .. "] '" .. manualQuestName .. "'")
    end
  end


  -- abort without any nodes or distances
  if not this.coords[1] or not this.coords[1][4] or pfQuest_config["routes"] == "0" then
    if pfQuest.debug and pfQuest.debug.IsEnabled() then
      if not this.coords[1] then
        pfQuest.debug.AddLog("WARNING", "No routing available - no quest coordinates found")
      elseif not this.coords[1][4] then
        pfQuest.debug.AddLog("WARNING", "No routing available - coordinates have no calculated distance")
      elseif pfQuest_config["routes"] == "0" then
        pfQuest.debug.AddLog("INFO", "Routing disabled in configuration")
      end
    end
    ClearPath(objectivepath)
    ClearPath(playerpath)
    ClearPath(mplayerpath)
    return
  end

  -- check first node for changes
  if this.firstnode ~= tostring(this.coords[1][1]..this.coords[1][2]) then
    this.firstnode = tostring(this.coords[1][1]..this.coords[1][2])

    -- recalculate objective paths
    if pfQuest.debug and pfQuest.debug.IsEnabled() then
      pfQuest.debug.AddLog("DEBUG", "Recalculating objective paths starting from (" .. this.coords[1][1] .. "," .. this.coords[1][2] .. ")")
    end
    local route = { [1] = this.coords[1] }
    local blacklist = { [1] = true }
    for i=2, table.getn(this.coords) do
      if route[i-1] then -- make sure the route was not blacklisted
        route[i] = GetNearest(route[i-1][1],route[i-1][2],this.coords, blacklist)
        if pfQuest.debug and pfQuest.debug.IsEnabled() and route[i] then
          pfQuest.debug.AddLog("DEBUG", "Route step " .. i .. ": nearest point (" .. route[i][1] .. "," .. route[i][2] .. ")")
        end
      end

      -- remove other item requirement gameobjects of same type from route
      if route[i] and route[i][3] and route[i][3].itemreq then
        for id, data in pairs(this.coords) do
          if not blacklist[id] and data[1] and data[2] and data[3]
            and data[3].itemreq and data[3].itemreq == route[i][3].itemreq
          then
            blacklist[id] = true
          end
        end
      end
    end

    ClearPath(objectivepath)
    for i, data in pairs(route) do
      if i > 1 then
        DrawLine(objectivepath, route[i-1][1],route[i-1][2],route[i][1],route[i][2])
      end
    end

    -- route calculation timestamp
    completed = GetTime()
  end

  if wrongmap then
    if pfQuest.debug and pfQuest.debug.IsEnabled() then
      pfQuest.debug.AddLog("WARNING", "No routing displayed - player position not available (wrong map or zone change)")
    end
    -- hide player-to-object path
    ClearPath(playerpath)
    ClearPath(mplayerpath)
  else
    -- draw player-to-object path
    ClearPath(playerpath)
    ClearPath(mplayerpath)
    if pfQuest.debug and pfQuest.debug.IsEnabled() then
      pfQuest.debug.AddLog("DEBUG", "Drawing player path from (" .. (xplayer*100) .. "," .. (yplayer*100) .. ") to (" .. this.coords[1][1] .. "," .. this.coords[1][2] .. ")")
    end
    DrawLine(playerpath,xplayer*100,yplayer*100,this.coords[1][1],this.coords[1][2],true)

    -- also draw minimap path if enabled
    if pfQuest_config["routeminimap"] == "1" then
      DrawLine(mplayerpath,xplayer*100,yplayer*100,this.coords[1][1],this.coords[1][2],true,true)
    end
  end
end)

pfQuest.route.drawlayer = CreateFrame("Frame", "pfQuestRouteDrawLayer", WorldMapButton)
pfQuest.route.drawlayer:SetFrameLevel(113)
pfQuest.route.drawlayer:SetAllPoints()

WorldMapButton.routes = CreateFrame("Frame", "pfQuestRouteDisplay", pfQuest.route.drawlayer)
WorldMapButton.routes:SetAllPoints()

pfQuest.route.arrow = CreateFrame("Frame", "pfQuestRouteArrow", UIParent)
pfQuest.route.arrow:SetPoint("CENTER", 0, -100)
pfQuest.route.arrow:SetWidth(48)
pfQuest.route.arrow:SetHeight(36)
pfQuest.route.arrow:SetClampedToScreen(true)
pfQuest.route.arrow:SetMovable(true)
pfQuest.route.arrow:EnableMouse(true)
pfQuest.route.arrow:RegisterForDrag('LeftButton')
pfQuest.route.arrow:SetScript("OnDragStart", function()
  if IsShiftKeyDown() then
    this:StartMoving()
  end
end)

pfQuest.route.arrow:SetScript("OnDragStop", function()
  this:StopMovingOrSizing()
end)

local invalid, lasttarget
local xplayer, yplayer, wrongmap, wrongmap
local xDelta, yDelta, dir, angle
local player, perc, column, row, xstart, ystart, xend, yend
local area, alpha, texalpha, color
local defcolor = "|cffffcc00"
local r, g, b

pfQuest.route.arrow:SetScript("OnUpdate", function()
  -- abort if the frame is not initialized yet
  if not this.parent then return end

  xplayer, yplayer = GetPlayerMapPosition("player")
  wrongmap = xplayer == 0 and yplayer == 0 and true or nil
  target = this.parent.coords and this.parent.coords[1] and this.parent.coords[1][4] and this.parent.coords[1] or nil

  -- disable arrow on invalid map/route
  if not target or wrongmap or pfQuest_config["arrow"] == "0" then
    if invalid and invalid < GetTime() then
      this:Hide()
    elseif not invalid then
      invalid = GetTime() + 1
    end

    return
  else
    invalid = nil
  end

  -- arrow positioning stolen from TomTomVanilla.
  -- all credits to the original authors:
  -- https://github.com/cralor/TomTomVanilla
  xDelta = (target[1] - xplayer*100)*1.5
  yDelta = (target[2] - yplayer*100)
  dir = atan2(xDelta, -(yDelta))
  dir = dir > 0 and (math.pi*2) - dir or -dir
  if dir < 0 then dir = dir + 360 end
  angle = math.rad(dir)

  player = pfQuestCompat.GetPlayerFacing()
  angle = angle - player
  perc = math.abs(((math.pi - math.abs(angle)) / math.pi))
  r, g, b = pfUI.api.GetColorGradient(floor(perc*100)/100)
  cell = modulo(floor(angle / (math.pi*2) * 108 + 0.5), 108)
  column = modulo(cell, 9)
  row = floor(cell / 9)
  xstart = (column * 56) / 512
  ystart = (row * 42) / 512
  xend = ((column + 1) * 56) / 512
  yend = ((row + 1) * 42) / 512

  -- guess area based on node count
  area = target[3].priority and target[3].priority or 1
  area = max(1, area)
  area = min(20, area)
  area = (area / 10) + 1

  alpha = target[4] - area
  alpha = alpha > 1 and 1 or alpha
  alpha = alpha < .5 and .5 or alpha

  texalpha = (1 - alpha) * 2
  texalpha = texalpha > 1 and 1 or texalpha
  texalpha = texalpha < 0 and 0 or texalpha

  r, g, b = r + texalpha, g + texalpha, b + texalpha

  -- update arrow
  this.model:SetTexCoord(xstart,xend,ystart,yend)
  this.model:SetVertexColor(r,g,b)

  -- recalculate values on target change
  if target ~= lasttarget then
    -- calculate difficulty color
    color = defcolor
    if tonumber(target[3]["qlvl"]) then
      color = pfMap:HexDifficultyColor(tonumber(target[3]["qlvl"]))
    end

    -- update node texture
    if target[3].texture then
      this.texture:SetTexture(target[3].texture)

      if target[3].vertex and ( target[3].vertex[1] > 0
        or target[3].vertex[2] > 0
        or target[3].vertex[3] > 0 )
      then
        this.texture:SetVertexColor(unpack(target[3].vertex))
      else
        this.texture:SetVertexColor(1,1,1,1)
      end
    else
      this.texture:SetTexture(pfQuestConfig.path.."\\img\\node")
      this.texture:SetVertexColor(pfMap.str2rgb(target[3].title))
    end

    -- update arrow texts
    local level = target[3].qlvl and "[" .. target[3].qlvl .. "] " or ""
    this.title:SetText(color..level..target[3].title.."|r")
    local desc = target[3].description or ""
    if not pfUI or not pfUI.uf then
      this.description:SetTextColor(1,.9,.7,1)
      desc = string.gsub(desc, "ff33ffcc", "ffffffff")
    end
    this.description:SetText(desc.."|r.")
  end

  -- only refresh distance text on change
  local distance = floor(target[4]*10)/10
  if distance ~= this.distance.number then
    this.distance:SetText("|cffaaaaaa" .. pfQuest_Loc["Distance"] .. ": "..string.format("%.1f", distance))
    this.distance.number = distance
  end

  -- update transparencies
  this.texture:SetAlpha(texalpha)
  this.model:SetAlpha(alpha)
end)

pfQuest.route.arrow.texture = pfQuest.route.arrow:CreateTexture("pfQuestRouteNodeTexture", "OVERLAY")
pfQuest.route.arrow.texture:SetWidth(28)
pfQuest.route.arrow.texture:SetHeight(28)
pfQuest.route.arrow.texture:SetPoint("BOTTOM", 0, 0)

pfQuest.route.arrow.model = pfQuest.route.arrow:CreateTexture("pfQuestRouteArrow", "MEDIUM")
pfQuest.route.arrow.model:SetTexture(pfQuestConfig.path.."\\img\\arrow")
pfQuest.route.arrow.model:SetTexCoord(0,0,0.109375,0.08203125)
pfQuest.route.arrow.model:SetAllPoints()

pfQuest.route.arrow.title = pfQuest.route.arrow:CreateFontString("pfQuestRouteText", "HIGH", "GameFontWhite")
pfQuest.route.arrow.title:SetPoint("TOP", pfQuest.route.arrow.model, "BOTTOM", 0, -10)
pfQuest.route.arrow.title:SetFont(pfUI.font_default, pfUI_config.global.font_size+1, "OUTLINE")
pfQuest.route.arrow.title:SetTextColor(1,.8,0)
pfQuest.route.arrow.title:SetJustifyH("CENTER")

pfQuest.route.arrow.description = pfQuest.route.arrow:CreateFontString("pfQuestRouteText", "HIGH", "GameFontWhite")
pfQuest.route.arrow.description:SetPoint("TOP", pfQuest.route.arrow.title, "BOTTOM", 0, -2)
pfQuest.route.arrow.description:SetFont(pfUI.font_default, pfUI_config.global.font_size, "OUTLINE")
pfQuest.route.arrow.description:SetTextColor(1,1,1)
pfQuest.route.arrow.description:SetJustifyH("CENTER")

pfQuest.route.arrow.distance = pfQuest.route.arrow:CreateFontString("pfQuestRouteDistance", "HIGH", "GameFontWhite")
pfQuest.route.arrow.distance:SetPoint("TOP", pfQuest.route.arrow.description, "BOTTOM", 0, -2)
pfQuest.route.arrow.distance:SetFont(pfUI.font_default, pfUI_config.global.font_size-1, "OUTLINE")
pfQuest.route.arrow.distance:SetTextColor(.8,.8,.8)
pfQuest.route.arrow.distance:SetJustifyH("CENTER")

pfQuest.route.arrow.parent = pfQuest.route
