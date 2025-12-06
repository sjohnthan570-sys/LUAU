local settings = {
    ["TableSize"] = 10000, -- If you're running out of memory then reduce this number!
    ["Save"] = {workspace}
}

local b64encode = crypt and crypt.base64encode or function() return "" end
local b64decode = crypt and crypt.base64decode or function() return "" end
local start = tick()

local decoded = game:GetService('HttpService'):JSONDecode(game:HttpGet("http://setup.roblox.com/"..game:HttpGet('http://setup.roblox.com/versionQTStudio',true).."-API-Dump.json",true))

local sizeCounter = 0
local stringBuilder = {}

local specialCharacters = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&apos;",
    ["\0"] = "",
    ["="] = ""
}

local ignoredProperties = {"Name","Parent","TimeOfDay"} --TimeOfDay causes a weird glitch i cba to fix

-- init
local objTable = {}
for _,obj in pairs(decoded.Classes) do
    local propTable = {}
    for _,member in pairs(obj.Members) do
        if not table.find((member.Tags or {}), "NotScriptable") --[[and member.Security.Read == "None"]] and member.MemberType == "Property" and not table.find(ignoredProperties,member.Name) and member.Serialization["CanLoad"] then
            propTable[member.Name] = member.ValueType.Category == "Enum" and {"Enum",member.ValueType.Name} or {member.ValueType.Name}
        end
    end
    objTable[obj.Name] = {}
    objTable[obj.Name]["Properties"] = propTable
    objTable[obj.Name]["Superclass"] = obj.Superclass
end

function getAllProps(objName)
    if objTable[objName].Superclass ~= "<<<ROOT>>>" then
        local props = objTable[objName].Properties
        for propName,propInfo in getAllProps(objTable[objName].Superclass) do
            props[propName] = propInfo
        end
        return props
    else
        return objTable[objName].Properties
    end
end

for objName,objData in objTable do
    objData.Properties = getAllProps(objName)
end

objTable["UnionOperation"]["Properties"]["InitialSize"] = {"InitialSize"}
objTable["MeshPart"]["Properties"]["InitialSize"] = {"InitialSize"}

print(`Initalized! Took {tick()-start}s`)
start = tick()

function removeSpecials(text)
    return ({text:gsub("[<>&\"'\0]", function(c)
        return specialCharacters[c]
    end)})[1]
end

function write(text)
    sizeCounter += 1
    table.insert(stringBuilder,text)
    if sizeCounter >= settings.TableSize then
        appendfile(`{game.PlaceId}.rbxlx`,table.concat(stringBuilder))
        stringBuilder = {}
        sizeCounter = 0
        task.wait()
    end
end

local specialCases = {
    ["Vector3"] = function(obj,prop)
        local currentProp = obj[prop]
        return `<Vector3 name="{prop}"><X>{currentProp.X}</X><Y>{currentProp.Y}</Y><Z>{currentProp.Z}</Z></Vector3>`
    end,
    ["Vector2"] = function(obj,prop)
        local currentProp = obj[prop]
        return `<Vector2 name="{prop}"><X>{currentProp.X}</X><Y>{currentProp.Y}</Y></Vector2>`
    end,
    ["Color3"] = function(obj,prop)
        local currentProp = obj[prop]
        return `<Color3 name="{prop}"><R>{currentProp.R}</R><G>{currentProp.G}</G><B>{currentProp.B}</B></Color3>`
    end,
    ["UDim2"] = function(obj,prop)
        local currentProp = obj[prop]
        return `<UDim2 name="{prop}"><XS>{currentProp.X.Scale}</XS><XO>{currentProp.X.Offset}</XO><YS>{currentProp.Y.Scale}</YS><YO>{currentProp.Y.Offset}</YO></UDim2>`
    end,
    ["CFrame"] = function(obj,prop)
        local currentProp = {obj[prop]:GetComponents()}
        return `<CoordinateFrame name="{prop}"><X>{currentProp[1]}</X><Y>{currentProp[2]}</Y><Z>{currentProp[3]}</Z><R00>{currentProp[4]}</R00><R01>{currentProp[5]}</R01><R02>{currentProp[6]}</R02><R10>{currentProp[7]}</R10><R11>{currentProp[8]}</R11><R12>{currentProp[9]}</R12><R20>{currentProp[10]}</R20><R21>{currentProp[11]}</R21><R22>{currentProp[12]}</R22></CoordinateFrame>`
    end,
    ["Content"] = function(obj,prop)
        return `<Content name="{prop}"><url>{removeSpecials(obj[prop])}</url></Content>`
    end,
    ["InitialSize"] = function(obj,prop)
        local currentProp = gethiddenproperty and gethiddenproperty(obj,prop) or Vector3.one
        return `<Vector3 name="{prop}"><X>{currentProp.X}</X><Y>{currentProp.Y}</Y><Z>{currentProp.Z}</Z></Vector3>`
    end,
    ["BinaryString"] = function(obj,prop)
        return `<BinaryString name="{prop}">{b64encode(obj[prop])}</BinaryString>`
    end,
    ["UniqueId"] = function(object,prop)
        return `<UniqueId name="{prop}>{b64encode(obj[prop])}</UniqueId>`
    end,
    ["SharedString"] = function(object,prop)
        return `<SharedString name="{prop}">{b64encode(obj[prop])}</SharedString>`
    end,
    ["string"] = function(object,prop)
        return `<string name="{prop}">removeSpecials(obj[prop])</string>`
    end
}

local function writeObject(obj)
    -- Start the item with class and Name
    write(`<Item class="{obj.ClassName}"><Properties><String name="Name">{removeSpecials(obj.Name)}</String>`)

    -- Check if this object's class exists in objTable
    local classInfo = objTable[obj.ClassName]
    if classInfo then
        for propName, propInfo in pairs(classInfo.Properties) do
            local value = obj[propName]  -- safely get the property

            if value ~= nil then
                -- Check if this property has a special case handler
                if specialCases[propInfo[1]] then
                    write(specialCases[propInfo[1]](obj, propName))
                else
                    -- Handle enums differently from other property types
                    if propInfo[1] == "Enum" then
                        write(`<token name="{propName}">{value.Value}</token>`)
                    else
                        write(`<{propInfo[1]} name="{propName}">{value}</{propInfo[1]}>`)
                    end
                end
            else
                -- Optional: warn about missing property but continue
                print(`Warning: {propName} does not exist on {obj.ClassName}`)
            end
        end
    end

    write("</Properties>")

    -- Recursively write all children
    for _, child in ipairs(obj:GetChildren()) do
        writeObject(child)
    end

    -- Close the Item tag
    write("</Item>")
end

writefile(`{game.PlaceId}.rbxlx`,'<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')

for _,mainObj in settings.Save do
    writeObject(mainObj)
end

write("</roblox>")
appendfile(`{game.PlaceId}.rbxlx`,table.concat(stringBuilder))
stringBuilder = {}
print(`Finished! Took {tick()-start}s`)
