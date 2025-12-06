--[[ 
    Universal Safe SaveInstance Script
    Saves Roblox instances to RBXLX without crashing on missing or hidden properties
--]]

local settings = {
    ["TableSize"] = 10000, -- Reduce if running out of memory
    ["Save"] = {workspace}
}

local b64encode = crypt and crypt.base64encode or function() return "" end
local b64decode = crypt and crypt.base64decode or function() return "" end
local start = tick()

-- Fetch Roblox class dump
local decoded = game:GetService('HttpService'):JSONDecode(game:HttpGet("http://setup.roblox.com/"..game:HttpGet('http://setup.roblox.com/versionQTStudio',true).."-API-Dump.json",true))

-- String builder for writing RBXLX
local sizeCounter = 0
local stringBuilder = {}

-- Characters to escape in XML
local specialCharacters = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&apos;",
    ["\0"] = "",
    ["="] = ""
}

local ignoredProperties = {"Name","Parent","TimeOfDay"} -- Skip these properties

-- Build object table from class dump
local objTable = {}
for _, obj in pairs(decoded.Classes) do
    local propTable = {}
    for _, member in pairs(obj.Members) do
        if not table.find((member.Tags or {}), "NotScriptable") and member.MemberType == "Property" 
        and not table.find(ignoredProperties, member.Name) and member.Serialization["CanLoad"] then
            propTable[member.Name] = member.ValueType.Category == "Enum" and {"Enum", member.ValueType.Name} or {member.ValueType.Name}
        end
    end
    objTable[obj.Name] = {
        Properties = propTable,
        Superclass = obj.Superclass
    }
end

-- Recursive inheritance
local function getAllProps(objName)
    local props = {}
    local classInfo = objTable[objName]
    if classInfo.Superclass ~= "<<<ROOT>>>" then
        local parentProps = getAllProps(classInfo.Superclass)
        for k,v in pairs(parentProps) do
            props[k] = v
        end
    end
    for k,v in pairs(classInfo.Properties) do
        props[k] = v
    end
    return props
end

for objName,objData in pairs(objTable) do
    objData.Properties = getAllProps(objName)
end

-- Add InitialSize manually for hidden properties
objTable["UnionOperation"]["Properties"]["InitialSize"] = {"InitialSize"}
objTable["MeshPart"]["Properties"]["InitialSize"] = {"InitialSize"}

print(`Initialized! Took {tick()-start}s`)
start = tick()

-- Helper: escape XML characters
function removeSpecials(text)
    if typeof(text) ~= "string" then return tostring(text) end
    return ({text:gsub("[<>&\"'\0=]", function(c)
        return specialCharacters[c]
    end)})[1]
end

-- Write text to stringBuilder
function write(text)
    sizeCounter += 1
    table.insert(stringBuilder,text)
    if sizeCounter >= settings.TableSize then
        appendfile(`{game.PlaceId}.rbxlx`, table.concat(stringBuilder))
        stringBuilder = {}
        sizeCounter = 0
        task.wait()
    end
end

-- Special cases for certain property types
local specialCases = {
    ["Vector3"] = function(obj, prop)
        local v = obj[prop]
        return `<Vector3 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
    end,
    ["Vector2"] = function(obj, prop)
        local v = obj[prop]
        return `<Vector2 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y></Vector2>`
    end,
    ["Color3"] = function(obj, prop)
        local v = obj[prop]
        return `<Color3 name="{prop}"><R>{v.R}</R><G>{v.G}</G><B>{v.B}</B></Color3>`
    end,
    ["UDim2"] = function(obj, prop)
        local v = obj[prop]
        return `<UDim2 name="{prop}"><XS>{v.X.Scale}</XS><XO>{v.X.Offset}</XO><YS>{v.Y.Scale}</YS><YO>{v.Y.Offset}</YO></UDim2>`
    end,
    ["CFrame"] = function(obj, prop)
        local c = {obj[prop]:GetComponents()}
        return `<CoordinateFrame name="{prop}"><X>{c[1]}</X><Y>{c[2]}</Y><Z>{c[3]}</Z><R00>{c[4]}</R00><R01>{c[5]}</R01><R02>{c[6]}</R02><R10>{c[7]}</R10><R11>{c[8]}</R11><R12>{c[9]}</R12><R20>{c[10]}</R20><R21>{c[11]}</R21><R22>{c[12]}</R22></CoordinateFrame>`
    end,
    ["Content"] = function(obj, prop)
        return `<Content name="{prop}"><url>{removeSpecials(obj[prop])}</url></Content>`
    end,
    ["InitialSize"] = function(obj, prop)
        local v = gethiddenproperty and gethiddenproperty(obj, prop) or Vector3.one
        return `<Vector3 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
    end,
    ["BinaryString"] = function(obj, prop)
        return `<BinaryString name="{prop}">{b64encode(obj[prop])}</BinaryString>`
    end,
    ["UniqueId"] = function(obj, prop)
        return `<UniqueId name="{prop}">{b64encode(obj[prop])}</UniqueId>`
    end,
    ["SharedString"] = function(obj, prop)
        return `<SharedString name="{prop}">{b64encode(obj[prop])}</SharedString>`
    end,
    ["string"] = function(obj, prop)
        return `<string name="{prop}">{removeSpecials(obj[prop])}</string>`
    end
}

-- Recursive function to write objects safely
local function writeObject(obj)
    write(`<Item class="{obj.ClassName}"><Properties><String name="Name">{removeSpecials(obj.Name)}</String>`)
    local classInfo = objTable[obj.ClassName]
    if classInfo then
        for propName, propInfo in pairs(classInfo.Properties) do
            local value = obj[propName]
            if value ~= nil then
                if specialCases[propInfo[1]] then
                    write(specialCases[propInfo[1]](obj, propName))
                else
                    if propInfo[1] == "Enum" then
                        write(`<token name="{propName}">{value.Value}</token>`)
                    else
                        write(`<{propInfo[1]} name="{propName}">{value}</{propInfo[1]}>`)
                    end
                end
            else
                print(`Warning: {propName} does not exist on {obj.ClassName}`)
            end
        end
    end
    write("</Properties>")
    for _, child in ipairs(obj:GetChildren()) do
        writeObject(child)
    end
    write("</Item>")
end

-- Start RBXLX file
writefile(`{game.PlaceId}.rbxlx`, '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')

-- Save all main objects
for _, mainObj in ipairs(settings.Save) do
    writeObject(mainObj)
end

-- Close root tag and flush remaining stringBuilder
write("</roblox>")
if #stringBuilder > 0 then
    appendfile(`{game.PlaceId}.rbxlx`, table.concat(stringBuilder))
    stringBuilder = {}
end

print(`Finished! Took {tick()-start}s`)
