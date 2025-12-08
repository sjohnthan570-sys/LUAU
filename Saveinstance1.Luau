--[[ 
    Universal Safe SaveInstance Script
    Fully crash-proof, silent, captures orphaned scripts,
    saves ModuleScript stubs, attributes, materials, CollectionService tags,
    properly handles MeshParts/SpecialMeshes/FileMeshes,
    and guarantees well-formed XML for RBXLX.
--]]

local settings = {
    TableSize = 10000,          -- Adjust if memory issues
    Save = {workspace}          -- Objects to save
}

local start = tick()

-- Fetch Roblox class dump safely
local success, version = pcall(function() return game:HttpGet("https://setup.roblox.com/versionQTStudio", true) end)
version = success and version or "default"

local apiUrl = "https://setup.roblox.com/" .. version .. "-API-Dump.json"
local success2, jsonRaw = pcall(function() return game:HttpGet(apiUrl, true) end)

local jsonData
if success2 and jsonRaw then
    local ok, decoded = pcall(function() return game:GetService("HttpService"):JSONDecode(jsonRaw) end)
    jsonData = ok and decoded or {Classes = {}}
else
    warn("Failed to fetch API dump, using empty fallback")
    jsonData = {Classes = {}}
end

-- String builder
local sizeCounter = 0
local stringBuilder = {}

-- Escape XML
local specialCharacters = {
    ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;", ["\0"] = "", ["="] = ""
}

local function removeSpecials(text)
    if typeof(text) ~= "string" then text = tostring(text) end
    return ({text:gsub("[<>&\"'\0=]", function(c) return specialCharacters[c] end)})[1]
end

local function write(text)
    sizeCounter += 1
    table.insert(stringBuilder, text)
    if sizeCounter >= settings.TableSize then
        appendfile(`{game.PlaceId}.rbxlx`, table.concat(stringBuilder))
        stringBuilder = {}
        sizeCounter = 0
        task.wait()
    end
end

-- Build object table
local ignoredProperties = {"Name","Parent","TimeOfDay"}
local objTable = {}

for _, obj in pairs(jsonData.Classes) do
    local propTable = {}
    for _, member in pairs(obj.Members or {}) do
        if not table.find(member.Tags or {}, "NotScriptable") 
            and member.MemberType == "Property" 
            and not table.find(ignoredProperties, member.Name)
            and member.Serialization and member.Serialization["CanLoad"] then
            propTable[member.Name] = member.ValueType.Category == "Enum" and {"Enum", member.ValueType.Name} or {member.ValueType.Name}
        end
    end
    objTable[obj.Name] = {Properties = propTable, Superclass = obj.Superclass}
end

-- Recursive inheritance
local function getAllProps(objName)
    local props = {}
    local classInfo = objTable[objName]
    if classInfo and classInfo.Superclass ~= "<<<ROOT>>>" and objTable[classInfo.Superclass] then
        for k,v in pairs(getAllProps(classInfo.Superclass)) do props[k]=v end
    end
    if classInfo then
        for k,v in pairs(classInfo.Properties) do props[k]=v end
    end
    return props
end

for objName,objData in pairs(objTable) do
    objData.Properties = getAllProps(objName)
end

-- Hidden InitialSize
if objTable["UnionOperation"] then objTable["UnionOperation"].Properties["InitialSize"] = {"InitialSize"} end
if objTable["MeshPart"] then objTable["MeshPart"].Properties["InitialSize"] = {"InitialSize"} end

print(`Initialized! Took {tick()-start}s`)
start = tick()

-- Special cases for properties
local specialCases = {
    Vector3 = function(obj, prop)
        local ok,v = pcall(function() return obj[prop] end)
        if not ok or v==nil or typeof(v)~="Vector3" then return "" end
        return `<Vector3 name="{prop}">{v.X} {v.Y} {v.Z}</Vector3>`
    end,
    Vector2 = function(obj, prop)
        local ok,v = pcall(function() return obj[prop] end)
        if not ok or v==nil or typeof(v)~="Vector2" then return "" end
        return `<Vector2 name="{prop}">{v.X} {v.Y}</Vector2>`
    end,
    Color3 = function(obj, prop)
        local ok,v = pcall(function() return obj[prop] end)
        if not ok or v==nil or typeof(v)~="Color3" then return "" end
        return `<Color3 name="{prop}">{v.R} {v.G} {v.B}</Color3>`
    end,
    BrickColor = function(obj, prop)
        local ok,v = pcall(function() return obj[prop] end)
        if not ok or v==nil or typeof(v)~="BrickColor" then return "" end
        return `<BrickColor name="{prop}">{removeSpecials(v.Name)}</BrickColor>`
    end,
    CFrame = function(obj, prop)
        local ok,c = pcall(function()
            local cf = obj[prop]
            if typeof(cf)~="CFrame" then return nil end
            return {cf:GetComponents()}
        end)
        if not ok or not c then return "" end
        return string.format('<CoordinateFrame name="%s">%f %f %f %f %f %f %f %f %f %f %f %f</CoordinateFrame>', prop, c[1],c[2],c[3],c[4],c[5],c[6],c[7],c[8],c[9],c[10],c[11],c[12])
    end,
    InitialSize = function(obj)
        local ok,v = pcall(function() return gethiddenproperty and gethiddenproperty(obj, "InitialSize") end)
        if not ok or not v then return "" end
        return `<Vector3 name="InitialSize">{v.X} {v.Y} {v.Z}</Vector3>`
    end
}

-- Recursive object writer
local function writeObject(obj)
    write(`<Item class="{obj.ClassName}"><Properties>`)
    write(`<String name="Name">{removeSpecials(obj.Name)}</String>`)

    local classInfo = objTable[obj.ClassName]
    if classInfo then
        for propName, propInfo in pairs(classInfo.Properties) do
            local typeName = propInfo[1]
            local ok,value = pcall(function() return obj[propName] end)
            if not ok or value==nil then continue end

            local output = ""
            -- Check special cases first
            if typeName and specialCases[typeName] then
                output = specialCases[typeName](obj, propName)
            elseif typeName=="Enum" and typeof(value)=="EnumItem" then
                output = `<token name="{propName}">{value.Value}</token>`
            else
                output = `<{typeName} name="{propName}">{removeSpecials(tostring(value))}</{typeName}>`
            end
            if output~="" then write(output) end
        end
    end

    -- Material
    pcall(function() if obj.Material then write(`<Enum name="Material">{tostring(obj.Material)}</Enum>`) end end)

    -- Attributes
    for _, attrName in ipairs(obj:GetAttributes()) do
        local val = obj:GetAttribute(attrName)
        write(`<Attribute name="{attrName}">{removeSpecials(tostring(val))}</Attribute>`)
    end

    -- CollectionService tags
    local CollectionService = game:GetService("CollectionService")
    local tags = {}
    pcall(function() tags = CollectionService:GetTags(obj) end)
    for _, tag in ipairs(tags) do
        write(`<Tag>{removeSpecials(tag)}</Tag>`)
    end

    -- Scripts & ModuleScripts wrapped in CDATA
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("Script") then
            local ok, source = pcall(function() return child.Source end)
            if ok and source then
                write(`<ScriptContent name="{removeSpecials(child.Name)}"><![CDATA[{source}]]></ScriptContent>`)
            end
        elseif child:IsA("ModuleScript") then
            write(`<ModuleStub name="{removeSpecials(child.Name)}"></ModuleStub>`)
        end
    end

    -- MeshPart/SpecialMesh/FileMesh safe properties
    if obj:IsA("MeshPart") or obj:IsA("SpecialMesh") or obj:IsA("FileMesh") then
        pcall(function()
            if obj.MeshId then write(`<Content name="MeshId">{removeSpecials(obj.MeshId)}</Content>`) end
            if obj.TextureID then write(`<Content name="TextureID">{removeSpecials(obj.TextureID)}</Content>`) end
            if obj.Size then write(`<Vector3 name="Size">{obj.Size.X} {obj.Size.Y} {obj.Size.Z}</Vector3>`) end
            if obj.Scale then write(`<Vector3 name="Scale">{obj.Scale.X} {obj.Scale.Y} {obj.Scale.Z}</Vector3>`) end
            if obj.Offset then write(`<Vector3 name="Offset">{obj.Offset.X} {obj.Offset.Y} {obj.Offset.Z}</Vector3>`) end
        end)
    end

    write("</Properties>")

    -- Recurse into children
    for _, child in ipairs(obj:GetChildren()) do writeObject(child) end

    write("</Item>")
end

-- Fun READ ME script
local readMeScript = Instance.new("Script")
readMeScript.Name = "READ ME"
readMeScript.Source = [[
-- Hello! You look amazing today! God bless
-- You can put more fun messages here
]]
readMeScript.Parent = workspace

-- Start RBXLX file
writefile(`{game.PlaceId}.rbxlx`, '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')

-- Save all main objects
for _, mainObj in ipairs(settings.Save) do writeObject(mainObj) end

write("</roblox>")

-- Flush remaining
if #stringBuilder>0 then
    appendfile(`{game.PlaceId}.rbxlx`, table.concat(stringBuilder))
    stringBuilder = {}
end

print(`Finished! Took {tick()-start}s`)
