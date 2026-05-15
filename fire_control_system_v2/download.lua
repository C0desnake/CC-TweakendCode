local base = "https://raw.githubusercontent.com/C0desnake/CC-TweakendCode/0396adbb677510f0ab5bd5b86c7761b4347d239b/fire_control_system_v2/"

local files = {
    "cannonCtr.lua",
    "cannonSettings.dat",
    "fireAuthentication.lua",
    "startup.lua",
    "trackingData.dat",
    "trackingSystem.lua",
}

for _, file in ipairs(files) do
    print("Downloading " .. file)
    shell.run("wget", "-f", base .. file, file)
end

print("Done.")