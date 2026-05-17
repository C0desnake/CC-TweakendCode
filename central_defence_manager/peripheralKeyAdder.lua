local ed25519 = require("ccryptolib.ed25519")
local random = require "ccryptolib.random"

local peripheralPublicKeys = {}


-- Init random
local postHandle = assert(http.post("https://krist.dev/ws/start", ""))
local data = textutils.unserializeJSON(postHandle.readAll())
postHandle.close()
random.init(data.url)
http.websocket(data.url).close()

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

--- Show Help menu
function ShowHelp()
    term.setTextColor(colors.blue)
    print("> pk [key]: add public key")
    print("> sk [key]: add public key (derived from private key)")
    print("> broadcast: update all defence systems")
    term.setTextColor(colors.white)
end

while true do
    local input = SplitString(io.read());

    if (input[1] ~= nil) then
        if input[1] == "pk" then
            peripheralPublicKeys[input[2]] = true
            local file = fs.open("pheripheralKeys.dat", "w")
            if file ~= nil then
                file.write(textutils.serialize(peripheralPublicKeys))
                file.close()
            end

        elseif input[1] == "sk" then
            peripheralPublicKeys[ed25519.publicKey(input[2])] = true
            local file = fs.open("pheripheralKeys.dat", "w")
            if file ~= nil then
                file.write(textutils.serialize(peripheralPublicKeys))
                file.close()
            end

        elseif input[1] == "help" then ShowHelp()
        else printError("Unrecognized command, type help for commands")
        end
    end
end
