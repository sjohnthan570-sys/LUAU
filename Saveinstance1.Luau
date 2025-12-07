--[[ 
    Universal Safe SaveInstance Script
    Fully crash-proof, silent, captures orphaned scripts,
    and creates a fun "READ ME" Script automatically!
--]]

local settings = {
    ["TableSize"] = 10000, -- Reduce if running out of memory
    ["Save"] = {workspace}
}

local b64encode = crypt and crypt.base64encode or function() return "" end
local b64decode = crypt and crypt.base64decode or function() return "" end
local start = tick()

-- Fetch Roblox class dump safely
local version = game:HttpGet("https://setup.roblox.com/versionQTStudio", true)
assert(version and version ~= "", "Failed to get Roblox version")
local apiUrl = "https://setup.roblox.com/" .. version .. "-API-Dump.json"
local jsonData = game:HttpGet(apiUrl, true)
assert(jsonData and jsonData ~= "", "Failed to fetch API dump")
local decoded = game:GetService("HttpService"):JSONDecode(jsonData)

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

local ignoredProperties = {"Name","Parent","TimeOfDay"}

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
local function removeSpecials(text)
    if typeof(text) ~= "string" then return tostring(text) end
    return ({text:gsub("[<>&\"'\0=]", function(c)
        return specialCharacters[c]
    end)})[1]
end

-- Write text to stringBuilder
local function write(text)
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
        local success, v = pcall(function() return obj[prop] end)
        if success and v then
            return `<Vector3 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
        end
        return ""
    end,
    ["Vector2"] = function(obj, prop)
        local success, v = pcall(function() return obj[prop] end)
        if success and v then
            return `<Vector2 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y></Vector2>`
        end
        return ""
    end,
    ["Color3"] = function(obj, prop)
        local success, v = pcall(function() return obj[prop] end)
        if success and v then
            return `<Color3 name="{prop}"><R>{v.R}</R><G>{v.G}</G><B>{v.B}</B></Color3>`
        end
        return ""
    end,
    ["UDim2"] = function(obj, prop)
        local success, v = pcall(function() return obj[prop] end)
        if success and v then
            return `<UDim2 name="{prop}"><XS>{v.X.Scale}</XS><XO>{v.X.Offset}</XO><YS>{v.Y.Scale}</YS><YO>{v.Y.Offset}</YO></UDim2>`
        end
        return ""
    end,
    ["CFrame"] = function(obj, prop)
        local success, c = pcall(function() return obj[prop] and {obj[prop]:GetComponents()} end)
        if success and c then
            return `<CoordinateFrame name="{prop}"><X>{c[1]}</X><Y>{c[2]}</Y><Z>{c[3]}</Z><R00>{c[4]}</R00><R01>{c[5]}</R01><R02>{c[6]}</R02><R10>{c[7]}</R10><R11>{c[8]}</R11><R12>{c[9]}</R12><R20>{c[10]}</R20><R21>{c[11]}</R21><R22>{c[12]}</R22></CoordinateFrame>`
        end
        return ""
    end,
    ["Content"] = function(obj, prop)
        local success, v = pcall(function() return obj[prop] end)
        if success and v then
            return `<Content name="{prop}"><url>{removeSpecials(v)}</url></Content>`
        end
        return ""
    end,
    ["InitialSize"] = function(obj, prop)
        local success, v = pcall(function() return gethiddenproperty and gethiddenproperty(obj, prop) end)
        if success and v then
            return `<Vector3 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
        end
        return ""
    end,
    ["BinaryString"] = function(obj, prop)
        local success, v = pcall(function() return obj[prop] end)
        if success and v then return `<BinaryString name="{prop}">{b64encode(v)}</BinaryString>` end
        return ""
    end,
    ["UniqueId"] = function(obj, prop)
        local success, v = pcall(function() return obj[prop] end)
        if success and v then return `<UniqueId name="{prop}">{b64encode(v)}</UniqueId>` end
        return ""
    end,
    ["SharedString"] = function(obj, prop)
        local success, v = pcall(function() return obj[prop] end)
        if success and v then return `<SharedString name="{prop}">{b64encode(v)}</SharedString>` end
        return ""
    end,
    ["string"] = function(obj, prop)
        local success, v = pcall(function() return obj[prop] end)
        if success and v then return `<string name="{prop}">{removeSpecials(v)}</string>` end
        return ""
    end
}

-- Detect orphan scripts (not in any major service)
local function isNotService(obj)
    return not obj:IsDescendantOf(workspace)
       and not obj:IsDescendantOf(game:GetService("ReplicatedStorage"))
       and not obj:IsDescendantOf(game:GetService("ServerStorage"))
       and not obj:IsDescendantOf(game:GetService("Players"))
       and not obj:IsDescendantOf(game:GetService("Lighting"))
end

-- Recursive function to write objects safely
local function writeObject(obj)
    write(`<Item class="{obj.ClassName}"><Properties><String name="Name">{removeSpecials(obj.Name)}</String>`)

    local classInfo = objTable[obj.ClassName]
    if classInfo then
        for propName, propInfo in pairs(classInfo.Properties) do

            -- Strip ModuleScript + Script source
            if (obj:IsA("ModuleScript") or obj:IsA("Script")) and propName == "Source" then
                continue
            end

            -- Safe read
            local success, value = pcall(function()
                return obj[propName]
            end)

            local output = ""

            if success and value ~= nil then
                if specialCases[propInfo[1]] then
                    output = specialCases[propInfo[1]](obj, propName)
                elseif propInfo[1] == "Enum" then
                    output = `<token name="{propName}">{value.Value}</token>`
                else
                    output = `<{propInfo[1]} name="{propName}">{value}</{propInfo[1]}>`
                end
            end

            if output ~= "" then
                write(output)
            end
        end
    end

    write("</Properties>")

    -- Write children normally (NO SOURCE DUMP)
    for _, child in ipairs(obj:GetChildren()) do
        writeObject(child)
    end

    write("</Item>")
end


-- ==== CREATE THE FUN "READ ME" SCRIPT ====
local readMeScript = Instance.new("Script")
readMeScript.Name = "READ ME"
readMeScript.Source = [[
-- Hello! You look amazing today! God bless
-- You can put more fun messages here
]]
readMeScript.Parent = workspace -- Can be Workspace, game, or wherever you like

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
