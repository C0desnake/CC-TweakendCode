local Radar = peripheral.find("create_radar:monitor")

local ed25519 = require("ccryptolib.ed25519")
local random = require "ccryptolib.random"

local permissions = {}

local publicKey = ""
local privateKey = ""

local cdmKey = ""

rednet.open(peripheral.getName(peripheral.find("modem")))

function Init()
    -- Init random
    local postHandle = assert(http.post("https://krist.dev/ws/start", ""))
    local data = textutils.unserializeJSON(postHandle.readAll())
    postHandle.close()
    random.init(data.url)
    http.websocket(data.url).close()
    
    -- Get saved permissions
    if fs.exists("grantedPermission.dat") then
        local file = fs.open("grantedPermission.dat", "r")
        permissions = textutils.unserialize(file.readAll())
        if permissions == nil then
            printError("Could not parse permissions")
            permissions = {}
        end
        file.close()
    end
    
    -- Get public key from of central defence manager
    if fs.exists("cdmKey.dat") then
        local file = fs.open("cdmKey.dat", "r")
        cdmKey = file.readAll():gsub("\n$", "");
        if cdmKey == nil then
            printError("Could not parse central defence manager key")
            return false
        end
        file.close()
    else
        printError("Could not find central defence manager key")
        return false
    end

    -- enter password
    print("Please enter password")
    while true do
        privateKey = io.read():gsub("\n$", "");
        term.clear()
        term.setCursorPos(1,1)

        if #privateKey ~= 32 then
            printError("Invalide password: please try again")
        else
            break
        end
    end

    publicKey = ed25519.publicKey(privateKey)

    return true
end

--- Split as string using spaces as deliminators
--- @param input string the string to split
--- @return table result split string as an array
function SplitString(input)
    if not input then return {} end
    local result = {}
    for w in input:gmatch("%S+") do
        table.insert(result, w)
    end
    return result
end

--- grant permission
--- @param inp table the split input
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

    permissions[inp[2]] = perms
    SendPermissions(inp[2])
end

--- Revoke given permissions
--- @param inp table the split input
function RevokePermissions(inp)
    if inp[2] == nil then
        printError("Name of permissions to revoke requiered")
        return
    end
    if permissions[inp[2]] == nil then
        printError("No permissions whit given name known")
        return
    end

    permissions[inp[2]] = nil
    SendPermissions(inp[2])
end

--- Revoke given permissions
--- @param name string the name of the permission to send to central defence manager
function SendPermissions(name)
    for k,v in pairs(permissions) do
        if v.untilDay ~= nil and v.untilDay > os.day() then
            permissions[k] = nil
        end
    end

    local msg = textutils.serialize({
        name=name,
        perms=permissions[name]
    })

    local sign = ed25519.sign(privateKey, publicKey, msg)

    local sendMsg = {
        sign = sign,
        pk = publicKey,
        msg = msg
    }

    rednet.broadcast(sendMsg, "authentication_update")
end

--- Show Help menu
function ShowHelp()
    term.setTextColor(colors.blue)
    print("> grant [name] [lvl] [*uuid (requierd if no radar connected)] [*forDays]: grants (temporary) permissions to an entity")
    print("> revoke [name]: revoke permissions")
    term.setTextColor(colors.white)
end

--- Main loop
function MainLoop()
    while true do
        local input = SplitString(io.read());

        if (input[1] ~= nil) then
            if input[1] == "grant" then GrantedPermission(input)
            elseif input[1] == "revoke" then RevokePermissions(input)
            elseif input[1] == "help" then ShowHelp()
            else printError("Unrecognized command, type help for commands")
            end
        end
    end
end

--- Recive update from the main system
function ReciveLoop()
    while true do
        for k,v in pairs(permissions) do
            if v.untilDay ~= nil and v.untilDay > os.day() then
                permissions[k] = nil
            end
        end

        local id, message = rednet.receive("authentication_broadcast", 1200)

        if id ~= nil and message.sign ~= nil and message.msg ~= nil then
            if ed25519.verify(cdmKey, message.msg, message.sign) then
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


if rednet.isOpen() then
    if Init() then
        print("Started authentication system")

        parallel.waitForAll(MainLoop, ReciveLoop)
    end
else
    printError("An attacked modem is requiered")
end
