local ed25519 = require("ccryptolib.ed25519")
local random = require "ccryptolib.random"

local permissions = {}

local privateKey = ""
local publicKey = ""

local peripheralPublicKeys = {}

rednet.open(peripheral.getName(peripheral.find("modem")))

--- Initate the defence manager
--- @return boolean success 
function Init()
    -- Init random
    local postHandle = assert(http.post("https://krist.dev/ws/start", ""))
    local data = textutils.unserializeJSON(postHandle.readAll())
    postHandle.close()
    random.init(data.url)
    http.websocket(data.url).close()

    -- Get saved permissions
    if fs.exists("grantedAutentication.dat") then
        local file = fs.open("grantedAutentication.dat", "r")
        permissions = textutils.unserialize(file.readAll())
        if permissions == nil then
            printError("Could not parse permissions")
            permissions = {}
        end
        file.close()
    end

    -- Get privateKey
    if not fs.exists("privateKey.dat") then
        printError("Could not find privateKey")
        return false
    end

    local file2 = fs.open("privateKey.dat", "r")
    privateKey = file2.readAll():gsub("\n$", "")
    file2.close()

    -- Calcualte publicKey
    publicKey = ed25519.publicKey(privateKey)

    local file3 = fs.open("publicKey.dat", "w")
    if file3 ~= nil then
        file3.write(publicKey)
        file3.close()
    end

    -- Get pheripheral public keys
    if fs.exists("pheripheralKeys.dat") then
        local file = fs.open("pheripheralKeys.dat", "r")
        peripheralPublicKeys = textutils.unserialize(file.readAll())
        if peripheralPublicKeys == nil then
            printError("Could not parse pheripheral keys")
            peripheralPublicKeys = {}
        end
        file.close()
    end

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
    BroadcastPermissions()
end

--- Update given permissions
--- @param inp table the split input
function UpdatePermissions(inp)
    if inp[2] == nil then
        printError("Name of permissions to update requiered")
        return
    end
    if permissions[inp[2]] == nil then
        printError("No permissions whit given name known")
        return
    end
    if tonumber(inp[3]) == nil then
        printError("permissions level requiered")
        return
    end

    local perms = {
        id=permissions[inp[2]].id,
        lvl=tonumber(inp[3])
    }

    local offset = 0
    if inp[4] ~= nil then
        local forDays = tonumber(inp[4]);

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
    BroadcastPermissions()
end

--- Broadcast current permissions to update defence systems
function BroadcastPermissions()
    for k,v in pairs(permissions) do
        if v.untilDay ~= nil and v.untilDay > os.day() then
            permissions[k] = nil
        end
    end

    local msg = textutils.serialize(permissions)

    local file = fs.open("grantedAutentication.dat", "w")
    if file ~= nil then
        file.write(msg)
        file.close()
    end

    local sign = ed25519.sign(privateKey, publicKey, msg)

    local sendMsg = {
        sign = sign,
        msg = msg
    }

    rednet.broadcast(sendMsg, "authentication_broadcast")
end

--- Show Help menu
function ShowHelp()
    term.setTextColor(colors.blue)
    print("> revoke [name]: revoke permissions")
    print("> update [name] [lvl] [*forDays]: update given permissions")
    print("> broadcast: update all defence systems")
    term.setTextColor(colors.white)
end

--- Recive update from authentication systems
function ReceiveUpdates()
    while true do
        for k,v in pairs(permissions) do
            if v.untilDay ~= nil and v.untilDay > os.day() then
                permissions[k] = nil
            end
        end

        local id, message = rednet.receive("authentication_update", 1200)

        if message.sign == nil or message.pk == nil or message.msg == nil or #message.pk ~= 32 then
            printError("Received invalide message")
        elseif peripheralPublicKeys[message.pk] == nil or not ed25519.verify(message.pk, message.msg, message.sign) then
            printError("Recived message whit invlaide authentication")
        else
            local msg = textutils.unserialize(message.msg)

            if msg.name == nil then
                printError("Received invalide message")
            else
                permissions[msg.name] = msg.perms
                BroadcastPermissions()
            end
        end
    end
end

--- Main loop
function MainLoop()
    while true do
        local input = SplitString(io.read());

        if (input[1] ~= nil) then
            if input[1] == "revoke" then RevokePermissions(input)
            elseif input[1] == "update" then UpdatePermissions(input)
            elseif input[1] == "broadcast" then BroadcastPermissions()
            elseif input[1] == "help" then ShowHelp()
            else printError("Unrecognized command, type help for commands")
            end
        end
    end
end


if rednet.isOpen() then
    if Init() then
        print("Started central defence managment system")

        parallel.waitForAll(MainLoop, ReceiveUpdates)
    end
else
    printError("The central defence manager requiers a modem to be attached")
end
