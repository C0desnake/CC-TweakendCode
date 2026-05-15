Exclude = {["5947369d-40a8-4bc5-8ab2-15a3c7c777d8-"]=true}
HandledTargets = {}

ForgetTime = 1000

print("Started FireAutenticator")

while true do
  if fs.exists("trackingData.dat") then
    local file = fs.open("trackingData.dat", "r")
    local targets = textutils.unserialize(file.readAll())
    file.close()
    
    for id, data in pairs(targets) do
      if HandledTargets[id] == nil or data.t - HandledTargets[id] > ForgetTime then
        if Exclude[id] == nil then
          os.queueEvent("target_authorized", id)
          print("Target authorized: "..id)
        end
      end
      HandledTargets[id] = data.t
    end
  end

  os.sleep(0.5)
end
