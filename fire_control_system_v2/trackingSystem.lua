Radars = { peripheral.find("create_radar:monitor") }
Tracks = {}

ForgetTime = 30

print("Started Tracking System")

while true do
  for _, radar in pairs(Radars) do
    for _, track in pairs(radar.getTracks()) do
      if Tracks[track.id] == nil or Tracks[track.id].t < track.scannedTime then
        local vel = track.velocity

        if Tracks[track.id] ~= nil then
          local dt = math.max(0.05, track.scannedTime - Tracks[track.id].t)
          vel.x = (track.position.x - Tracks[track.id].pos.x) / dt
          vel.y = (track.position.y - Tracks[track.id].pos.y) / dt
          vel.z = (track.position.z - Tracks[track.id].pos.z) / dt
        end

        Tracks[track.id] = {
          ["pos"]=track.position,
          ["vel"]=vel,
          ["t"]=track.scannedTime,
          ["ct"]=os.clock(),
          ["cat"]=track.category
        }
      end
    end
  end

  local ct = os.clock()

  for id, track in pairs(Tracks) do
    if ct - track.ct > ForgetTime then
      Tracks[id] = nil
    end
  end

  local file = io.open("trackingData.dat", "w")
  if file ~= nil then
    file:write(textutils.serialise(Tracks))
    file:close()
  end

  os.sleep(0.05)
end
