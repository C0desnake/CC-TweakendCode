local ed25519 = require("ccryptolib.ed25519")
local random = require("ccryptolib.random")

rednet.open(peripheral.getName(peripheral.find("modem")))

local permissions = {}
local publicKey = ""

local securityLevel = 10

function Init()
    -- Permissions
    if fs.exists("grantedPermission.dat") then
        local file = fs.open("grantedPermission.dat", "r")
        permissions = textutils.unserialize(file.readAll())
        if permissions == nil then
            printError("Could not parse permissions")
            permissions = {}
        end
        file.close()
    end

    -- Public key
    if not fs.exists("publicKey.dat") then
        printError("Could not find publicKey")
        return false
    end

    local file2 = fs.open("publicKey.dat", "r")
    publicKey = file2.readAll():gsub("\n$", "")
    file2.close()

    if (#publicKey ~= 32) then
        printError("Invalide public key")
        return false
    end

    -- settings
    if not fs.exists("settings.dat") then
        printError("Could not find settings for cannons")
        return false
    end

    local file3 = fs.open("settings.dat", "r");
    local settings = textutils.unserialize(file3.readAll())
    file3.close()

    if settings == nil then
        printError("Could not read cannonSettings")
        return false
    end

    if settings.securityLevel == nil or tonumber(settings.securityLevel) == nil then
        printError("No securityLevel defined")
        return false
    end

    securityLevel = tonumber(settings.securityLevel)

    -- Init random
    local postHandle = assert(http.post("https://krist.dev/ws/start", ""))
    local data = textutils.unserializeJSON(postHandle.readAll())
    postHandle.close()
    random.init(data.url)
    http.websocket(data.url).close()

    if fs.exists("grantedPermission.dat") then
        local file = fs.open("grantedPermission.dat", "r")
        Permissions = textutils.unserialize(file.readAll())
        if Permissions == nil then
            printError("Could not parse permissions")
            Permissions = {}
        end
        file.close()
    end

    return true
end


if rednet.isOpen() then
    if Init() then
        print("Permission manager started")

        while true do
            local excludes = {}

            for k,v in pairs(Permissions) do
                if v.untilDay ~= nil and v.untilDay > os.day() then
                    Permissions[k] = nil
                elseif tonumber(v.lvl) >= securityLevel then
                    excludes[v.id] = true;
                end
            end

            os.queueEvent("target_excludes", excludes)

            local id, message = rednet.receive("authentication_broadcast", 1200)

            if id ~= nil and message.sign ~= nil and message.msg ~= nil then
                if ed25519.verify(publicKey, message.msg, message.sign) then
                    permissions = textutils.unserialize(message.msg)

                    local file = fs.open("grantedPermission.dat", "w")
                    if file ~= nil then
                        file.write(message.msg)
                        file.close()
                    end
                else
                    printError("Recived message whit incorect signature")
                end
            end
        end
    end
else
    printError("Could not open rednet")
end