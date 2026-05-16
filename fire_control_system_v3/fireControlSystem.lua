local radars = { peripheral.find("create_radar:monitor") }
local cannons = {}

local exclude = {["5947369d-40a8-4bc5-8ab2-15a3c7c777d8"]=true}
local tracks = {}
local activeTracks = {}
local warnedTargets = {}
local authorizedTargets = {}
local numTargets = 0

local velComp = 20.0
local forgetTime = 60
local attackRange = 1000.0
local warningRange = 1000.0

rednet.open(peripheral.getName(peripheral.find("modem")))

-- Initiate cannons
function Initiatecannons()
    if not fs.exists("settings.dat") then
        printError("Could not find settings for cannons")
        return false
    end

    local file = fs.open("settings.dat", "r");
    local settings = textutils.unserialize(file.readAll())
    file.close()

    if settings == nil then
        printError("Could not read settings")
        return false
    end

    if tonumber(settings.velComp) ~= nil then
        velComp = settings.velComp
    end
    if tonumber(settings.forgetTime) ~= nil then
        forgetTime = settings.forgetTime
    end
    if tonumber(settings.attackRange) ~= nil then
        attackRange = settings.attackRange
    end
    if tonumber(settings.attackRange) ~= nil then
        warningRange = settings.warningRange
    end


    for _, cs in pairs(settings.cannons) do
        if cs.position == nil then
            printError("No cannon position defined")
            return false
        end
        if cs.rotation == nil then
            printError("No cannon rotation defined")
            return false
        end
        if cs.firePower == nil then
            printError("No cannon fire Power defined")
            return false
        end
        if cs.dragComp == nil then
            printError("No cannon drag compensation defined")
            return false
        end
        if cs.yawCtr == nil then
            printError("No cannon yaw controler defined")
            return false
        end
        if cs.pitchCtr == nil then
            printError("No pitch controler defined")
            return false
        end
        if cs.fireCtr == nil then
            printError("No fire controler defined")
            return false
        end
        if cs.yawLimits == nil then
            printError("No yaw limits set")
            return false
        end
        if cs.pitchLimits == nil then
            printError("No pitch limits set")
            return false
        end
        if cs.minDistance == nil then
            printError("No minDistance set")
            return false
        end

        local cannon = {
            pos = {x=cs.position.x+0.5,y=cs.position.y+0.5,z=cs.position.z+0.5},
            rot = cs.rotation,
            fp = cs.firePower,
            dragComp = cs.dragComp,
            yawCtr = peripheral.wrap(cs.yawCtr),
            pitchCtr = peripheral.wrap(cs.pitchCtr),
            fireCtr = peripheral.wrap(cs.fireCtr),
            yawLimits = cs.yawLimits,
            pitchLimits = cs.pitchLimits,
            minDistance = cs.minDistance,
        }

        if cannon.yawCtr == nil then
            printError("Could not find yaw controler: "..cs.yawCtr)
            return false
        end
        if cannon.pitchCtr == nil then
            printError("Could not find pitch controler: "..cs.pitchCtr)
            return false
        end
        if cannon.fireCtr == nil then
            printError("Could not find fire controler: "..cs.fireCtr)
            return false
        end

        table.insert(cannons, cannon)
    end
    return true
end

-- Update the curent tracked entities
function UpdateTracks()
    for _, radar in pairs(radars) do
        for _, track in pairs(radar.getTracks()) do
            if tracks[track.id] == nil or tracks[track.id].scannedTime < track.scannedTime then
                local vel = track.velocity

                if tracks[track.id] ~= nil then
                    local dt = math.max(0.05, track.scannedTime - tracks[track.id].scannedTime)
                    vel.x = (track.position.x - tracks[track.id].pos.x) / dt
                    vel.y = (track.position.y - tracks[track.id].pos.y) / dt
                    vel.z = (track.position.z - tracks[track.id].pos.z) / dt
                end

                tracks[track.id] = {
                    pos = track.position,
                    vel = vel,
                    scannedTime = track.scannedTime,
                    t = os.clock(),
                }
            end
        end
    end

    local ct = os.clock()

    activeTracks = {}

    for id, track in pairs(tracks) do
        if ct - track.t > forgetTime then
            tracks[id] = nil
            if authorizedTargets[id] ~= nil then numTargets = numTargets-1 end
            authorizedTargets[id] = nil
        elseif ct - track.t < 1 then
            activeTracks[id] = true
        end
    end
end

-- Autherize tracked entities for trgeting
function AuthorizeTargets()
    for id, _ in pairs(activeTracks) do
        if authorizedTargets[id] == nil and exclude[id] == nil then
            local pos = vector.new(tracks[id].pos.x, tracks[id].pos.y, tracks[id].pos.z)

            if pos:length() < attackRange then
                print("Target authorized: "..id)
                numTargets = numTargets+1
                authorizedTargets[id] = true;
            end
        end
    end
end


-- Calcualte targeting balistics
function CalcBalist(pos, can)
  local yaw = math.deg(math.atan(pos.z,pos.x)) - can.rot

  local pd = math.sqrt(pos.x*pos.x+pos.z*pos.z)
  local D = can.fp*can.fp - pd*pd - 2*pos.y*can.fp

  if D <= 0 then
    return nil
  end

  local pitch = math.deg(math.atan((can.fp - math.sqrt(D)), pd) + can.dragComp * pos:length())

  return yaw, pitch
end

-- Aim and shoot autherize targets
function ShootTargets()
    local clockTime = os.clock()
    for _, can in pairs(cannons) do
        local foundTarget = false

        if numTargets > 0 then
            local rTargets = {}
            
            for id, _ in pairs(authorizedTargets) do
                if activeTracks[id] ~= nil and tracks[id] ~= nil then
                    local tPos = vector.new(
                        tracks[id].pos.x - can.pos.x,
                        tracks[id].pos.y - can.pos.y,
                        tracks[id].pos.z - can.pos.z)
                    if (tPos:length() > can.minDistance) then
                        table.insert(rTargets, {["dist"]=tPos:length(),["pos"]=tPos,["vel"]=tracks[id].vel})
                    end
                end
            end
            
            table.sort(rTargets, function(a, b) return a.dist > b.dist end)

            while #rTargets > 0 do
                local target = table.remove(rTargets)
                
                local adjTarget = vector.new(
                    target.pos.x + target.vel.x * velComp,
                    target.pos.y + target.vel.y * velComp * 0.5,
                    target.pos.z + target.vel.z * velComp
                )
                
                local yaw, pitch = CalcBalist(adjTarget, can)
                
                if yaw ~= nil then
                    yaw = yaw % 360
                    if yaw < 0 then yaw = yaw + 360 end

                    local allowedYaw = false
                    for _, lim in pairs(can.yawLimits) do
                        if lim.min < yaw and yaw < lim.max then
                            allowedYaw = true
                            break
                        end
                    end

                    
                    local allowedPitch = false
                    for _, lim in pairs(can.pitchLimits) do
                        if lim.min < pitch and pitch < lim.max then
                            allowedPitch = true
                            break
                        end
                    end

                    if allowedYaw and allowedPitch then
                        can.yawCtr.setAngle(yaw)
                        can.pitchCtr.setAngle(pitch)
                        foundTarget = true
                        break
                    end
                end
            end
        else
            can.fireCtr.fireOff()
        end

        if foundTarget then
            can.fireCtr.fireOn()
        else
            can.fireCtr.fireOff()
        end
    end
end

-- Warn targets
function WarnTargets()
    local ct = os.clock()

    for id, _ in pairs(activeTracks) do
        if exclude[id] == nil then
            local pos = vector.new(tracks[id].pos.x, tracks[id].pos.y, tracks[id].pos.z)

            if pos:length() < warningRange and (warnedTargets[id] == nil or warnedTargets[id] < ct) then
                warnedTargets[id] = ct + 30
                local msgData = {}
                msgData.msg = "YOU ARE ENTERING A RESTRICTED ZONE: LEAF IMMEDIATELY!"
                msgData.name = "Defence system"
                msgData.posX = pos.x
                msgData.posY = pos.y
                msgData.posZ = pos.z
                msgData.range = 25
                
                rednet.broadcast(msgData, "comMessage")
            end
        end
    end
end

function MainLoop()
    while true do
        UpdateTracks()
        AuthorizeTargets()
        ShootTargets()
        WarnTargets()

        os.sleep(0.05)
    end
end

function ExcludeUpdates()
    while true do
        local _, exclude = os.pullEvent("target_excludes")
        exclude = exclude

        for id,_ in pairs(exclude) do
            if authorizedTargets[id] ~= nil then
                print("Target de-authorized: "..id)
            end
        end
    end
end


if Initiatecannons() then
    print("Fire controler system started!")

    parallel.waitForAll(MainLoop, ExcludeUpdates)
end