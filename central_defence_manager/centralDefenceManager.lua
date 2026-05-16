Radar = peripheral.find("create_radar:monitor")

local ed25519 = require("ccryptolib.ed25519")
local random = require "ccryptolib.random"

Permissions = {}

PrivateKey = ""
PublicKey = ""

rednet.open(peripheral.getName(peripheral.find("modem")))

function Init()
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

    if not fs.exists("privateKey.dat") then
        printError("Could not find privateKey")
        return false
    end

    local file2 = fs.open("privateKey.dat", "r")
    PrivateKey = file2.readAll():gsub("\n$", "")
    file2.close()

    PublicKey = ed25519.publicKey(PrivateKey)

    local file3 = fs.open("publicKey.dat", "w")
    if file3 ~= nil then
        file3.write(PublicKey)
        file3.close()
    end

    return true
end


function SplitString(input)
    if not input then return {} end
    local result = {}
    for w in input:gmatch("%S+") do
        table.insert(result, w)
    end
    return result
end


function GrantedPermission(inp)
    if inp[2] == nil or inp[3] == nil then
        printError("Both a level of permision and permision holders name is requiered")
        return
    end
    if tonumber(inp[3]) == nil then
        printError("Level of permision needs to be a number")
        return
    end

    local perms = {
        lvl=inp[3]
    }

    local offset = 0
    if inp[4] ~= nil and tonumber(inp[4]) == nil then
        offset = 1
        perms.id = inp[4]
    elseif Radar == nil then
        printError("No radar found: manual uuid requierd")
        return
    else
        local selected = Radar.getSelectedTrackId()

        if selected == nil or selected == "" then
            printError("No entity selected, please select and entity ont the radar monitor")
            return
        end
        perms.id = selected
    end

    if inp[4+offset] ~= nil then
        local forDays = tonumber(inp[4+offset]);

        if forDays == nil then
            printError("The forDays parameter needs to be a number")
            return
        end

        perms.untilDay = os.day() + forDays;
        offset = offset + 1
    end

    if inp[4+offset] ~= nil then
        printError("To many arguments")
        return
    end

    Permissions[inp[2]] = perms
    UpdatePermissions()
end

function RevokePermissions(inp)
    if inp[2] == nil then
        printError("Name of permissions to revoke requiered")
        return
    end
    if Permissions[inp[2]] == nil then
        printError("No permissions whit given name known")
        return
    end

    Permissions[inp[2]] = nil
    UpdatePermissions()
end

function UpdatePermissions()
    for k,v in pairs(Permissions) do
        if v.untilDay ~= nil and v.untilDay > os.day() then
            Permissions[k] = nil
        end
    end

    local msg = textutils.serialize(Permissions)

    local file = fs.open("grantedPermission.dat", "w")
    if file ~= nil then
        file.write(msg)
        file.close()
    end

    local sign = ed25519.sign(PrivateKey, PublicKey, msg)

    local sendMsg = {
        sign = sign,
        msg = msg
    }

    rednet.broadcast(sendMsg, "defence_permission_update")
end

function GetPublicKey()
    print("PublicKey: "..PublicKey)
end

function ShowHelp()
    term.setTextColor(colors.blue)
    print("> grant [name] [lvl] [*uuid (requierd if no radar connected)] [*forDays]: grants (temporary) permissions to an entity")
    print("> reveoke [name]: revoke permissions")
    print("> update: update all defence systems")
    print("> getKey: print the public key of this system")
    term.setTextColor(colors.white)
end


if rednet.isOpen() then
    if Init() then
        print("Started central defence managment system")

        while true do
            local input = SplitString(io.read());

            if (input[1] ~= nil) then
                if input[1] == "grant" then GrantedPermission(input)
                elseif input[1] == "revoke" then RevokePermissions(input)
                elseif input[1] == "update" then UpdatePermissions()
                elseif input[1] == "getKey" then GetPublicKey()
                elseif input[1] == "help" then ShowHelp()
                else printError("Unrecognized command, type help for commands")
                end
            end
        end
    end
else
    printError("The central defence manager requiers a modem to be attached")
end
