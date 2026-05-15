Radars = { peripheral.find("create_radar:monitor") }
Cannons = {}

Exclude = {["5947369d-40a8-4bc5-8ab2-15a3c7c777d8"]=true}
Tracks = {}
ActiveTracks = {}
AuthorizedTargets = {}
NumTargets = 0

VelAdj = 20.0
ForgetTime = 60

-- Initiate cannons
function InitiateCannons()
    if not fs.exists("cannonSettings.dat") then
        printError("Could not find settings for cannons")
        return false
    end

    local file = fs.open("cannonSettings.dat", "r");
    local settings = textutils.unserialize(file.readAll())
    file.close()

    if settings == nil then
        printError("Could not read cannonSettings")
        return false
    end

    for _, cs in pairs(settings) do
        if cs.position == nil then
            printError("No cannon position defined")
            return false
        end
        if cs.rotation == nil then
            printError("No cannon rotation defined")
            return false
        end
        if cs.firePower == nil then
            printError("No cannon fire firePower defined")
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

        table.insert(Cannons, cannon)
    end
    return true
end

-- Update the curent tracked entities
function UpdateTracks()
    for _, radar in pairs(Radars) do
        for _, track in pairs(radar.getTracks()) do
            if Tracks[track.id] == nil or Tracks[track.id].scannedTime < track.scannedTime then
                local vel = track.velocity

                if Tracks[track.id] ~= nil then
                    local dt = math.max(0.05, track.scannedTime - Tracks[track.id].scannedTime)
                    vel.x = (track.position.x - Tracks[track.id].pos.x) / dt
                    vel.y = (track.position.y - Tracks[track.id].pos.y) / dt
                    vel.z = (track.position.z - Tracks[track.id].pos.z) / dt
                end

                Tracks[track.id] = {
                    pos = track.position,
                    vel = vel,
                    scannedTime = track.scannedTime,
                    t = os.clock(),
                }
            end
        end
    end

    local ct = os.clock()

    ActiveTracks = {}

    for id, track in pairs(Tracks) do
        if ct - track.t > ForgetTime then
            Tracks[id] = nil
            if AuthorizedTargets[id] ~= nil then NumTargets = NumTargets-1 end
            AuthorizedTargets[id] = nil
        elseif ct - track.t < 1 then
            ActiveTracks[id] = true
        end
    end
end

-- Autherize tracked entities for trgeting
function AuthorizeTargets()
    for id, _ in pairs(ActiveTracks) do
        if AuthorizedTargets[id] == nil and Exclude[id] == nil then
            print("Target authorized: "..id)
            NumTargets = NumTargets+1
            AuthorizedTargets[id] = true;
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

  local pitch = math.deg(math.atan((can.fp - math.sqrt(D)), pd))

  return yaw, pitch
end

-- Aim and shoot autherize targets
function ShootTargets()
    local clockTime = os.clock()
    for _, can in pairs(Cannons) do
        local foundTarget = false

        if NumTargets > 0 then
            local rTargets = {}
            
            for id, _ in pairs(AuthorizedTargets) do
                if ActiveTracks[id] ~= nil and Tracks[id] ~= nil then
                    local tPos = vector.new(
                        Tracks[id].pos.x - can.pos.x,
                        Tracks[id].pos.y - can.pos.y,
                        Tracks[id].pos.z - can.pos.z)
                    if (tPos:length() > can.minDistance) then
                        table.insert(rTargets, {["dist"]=tPos:length(),["pos"]=tPos,["vel"]=Tracks[id].vel})
                    end
                end
            end
            
            table.sort(rTargets, function(a, b) return a.dist > b.dist end)

            while #rTargets > 0 do
                local target = table.remove(rTargets)
                
                local adjTarget = {
                    ["x"] = target.pos.x + target.vel.x * VelAdj,
                    ["y"] = target.pos.y + target.vel.y * VelAdj * 0.5,
                    ["z"] = target.pos.z + target.vel.z * VelAdj,
                }
                
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


if InitiateCannons() then
    print("Fire controler system started!")

    while true do
        UpdateTracks()
        AuthorizeTargets()
        ShootTargets()

        os.sleep(0.05)
    end
end