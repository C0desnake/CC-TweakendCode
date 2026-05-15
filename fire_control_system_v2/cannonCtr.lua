Args = {...}

ForgetTime = 60
Targets = {}
NumTargets = 0

VelAdj = 20.0

CPos = nil
CRot = nil
CFP = nil

YawCtr = nil
PitchCtr = nil
FireCtr = nil

YawLimits = {}
PitchLimits = {}
MinDistance = nil


function InitSetings()
  if Args[1] == nil then
    printError("arguments: [cannon]")
    return false
  end

  if not fs.exists("cannonSettings.dat") then
    printError("Could not find settings")
    return false
  end

  local cannonID = Args[1]

  local file = fs.open("cannonSettings.dat", "r");
  local settings = textutils.unserialize(file.readAll())
  file.close()

  if settings[cannonID] == nil then
    printError("Invalide cannonID")
    return false
  end

  if settings[cannonID].posX == nil or settings[cannonID].posY == nil or settings[cannonID].posZ == nil then
    printError("No cannon position set")
    return false
  end
  if settings[cannonID].rotation == nil then
    printError("No cannon rotation set")
    return false
  end
  if settings[cannonID].firePower == nil then
    printError("No cannon rotation set")
    return false
  end
  if settings[cannonID].yawCtr == nil then
    printError("No cannon yawCtr set")
    return false
  end
  if settings[cannonID].pitchCtr == nil then
    printError("No cannon pitchCtr set")
    return false
  end
  if settings[cannonID].fireCtr == nil then
    printError("No cannon fireCtr set")
    return false
  end
  if settings[cannonID].yawLimits == nil then
    printError("No cannon yawLimits set")
    return false
  end
  if settings[cannonID].pitchLimits == nil then
    printError("No cannon pitchLimits set")
    return false
  end
  if settings[cannonID].minDistance == nil then
    printError("No minDistance set")
    return false
  end

  CPos = vector.new(settings[cannonID].posX+0.5, settings[cannonID].posY+0.5, settings[cannonID].posZ+0.5)
  CRot = settings[cannonID].rotation
  CFP = settings[cannonID].firePower

  YawCtr = peripheral.wrap(settings[cannonID].yawCtr)
  PitchCtr = peripheral.wrap(settings[cannonID].pitchCtr)
  FireCtr = peripheral.wrap(settings[cannonID].fireCtr)

  YawLimits = settings[cannonID].yawLimits
  PitchLimits = settings[cannonID].pitchLimits
  MinDistance = settings[cannonID].minDistance

  if YawCtr == nil then
    printError("Could not find yaw controler: "..settings[cannonID].yawCtr)
    return false
  end
  if PitchCtr == nil then
    printError("Could not find pitch controler: "..settings[cannonID].pitchCtr)
    return false
  end
  if FireCtr == nil then
    printError("Could not find fire controler: "..settings[cannonID].fireCtr)
    return false
  end
  
  return true
end
 
function CalcBalist(pos)
  local yaw = math.deg(math.atan(pos.z,pos.x)) - CRot
  
  local pd = math.sqrt(pos.x*pos.x+pos.z*pos.z)
  local D = CFP*CFP - pd*pd - 2*pos.y*CFP
  
  if D <= 0 then
    return nil
  end
  
  local pitch = math.deg(math.atan((CFP - math.sqrt(D)), pd))
  
  return yaw, pitch
end
 
 
function FireLoop()
   while true do
    local foundTarget = false

    if NumTargets > 0 then
      local file = fs.open("trackingData.dat", "r")
      local tracked = textutils.unserialize(file.readAll())
      file.close()

      if tracked ~= nil then
        local clockTime = os.clock()
        
        local rTargets = {}
        
        for id, t in pairs(Targets) do
          if tracked[id] ~= nil then
            Targets[id] = clockTime
            local tPos = vector.new(tracked[id].pos.x,tracked[id].pos.y,tracked[id].pos.z):sub(CPos)
            
            if (tPos:length() > MinDistance) then
              table.insert(rTargets, {["dist"]=tPos:length(),["pos"]=tPos,["vel"]=tracked[id].vel})
            end
          elseif clockTime-t > ForgetTime then
            Targets[id] = nil
          end
        end
        
        table.sort(rTargets, function(a, b) return a.dist > b.dist end)

        while #rTargets > 0 do
          local target = table.remove(rTargets)
          
          print(target.vel.x,target.vel.y,target.vel.z)
          
          local adjTarget = {
              ["x"] = target.pos.x + target.vel.x * VelAdj,
              ["y"] = target.pos.y + target.vel.y * VelAdj * 0.5,
              ["z"] = target.pos.z + target.vel.z * VelAdj,
          }
          
          local yaw, pitch = CalcBalist(adjTarget)
          
          if yaw ~= nil then
            yaw = yaw % 360
            if yaw < 0 then yaw = yaw + 360 end

            local allowedYaw = false
            for _, lim in pairs(YawLimits) do
              if lim.min < yaw and yaw < lim.max then
                allowedYaw = true
                break
              end
            end

            
            local allowedPitch = false
            for _, lim in pairs(PitchLimits) do
              if lim.min < pitch and pitch < lim.max then
                allowedPitch = true
                break
              end
            end

            if allowedYaw and allowedPitch then
              YawCtr.setAngle(yaw)
              PitchCtr.setAngle(pitch)
              foundTarget = true
              break
            end
          end
        end
      end
    else
      FireCtr.fireOff()
      os.sleep(0.1)
    end

    if foundTarget then
      FireCtr.fireOn()
    else
      FireCtr.fireOff()
    end
    
    os.sleep(0.01)
  end
end
 
function AuthLoop()
  while true do
     local _, target = os.pullEvent("target_authorized")
     Targets[target] = os.clock()
     NumTargets = NumTargets + 1
  end
end
 
if InitSetings() and fs.exists("trackingData.dat") then
 print("Cannon Controler Started")
 parallel.waitForAll(FireLoop, AuthLoop)
end
