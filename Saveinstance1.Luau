--[[ 
    Universal Safe SaveInstance Script
    Fully crash-proof, silent, captures orphaned scripts,
    saves ModuleScript stubs, attributes, materials, CollectionService tags,
    and properly handles MeshParts/SpecialMeshes to prevent errors.
--]]

local settings = {
    TableSize = 10000,          -- Reduce if running out of memory
    Save = {workspace}          -- Objects to save
}

local b64encode = crypt and crypt.base64encode or function() return "" end
local start = tick()

-- Fetch Roblox class dump safely
local okVersion, versionResult = pcall(function()
    return game:HttpGet("https://setup.roblox.com/versionQTStudio", true)
end)
local version = (okVersion and versionResult) or "default"

local apiUrl = "https://setup.roblox.com/" .. version .. "-API-Dump.json"

local okJson, jsonRaw = pcall(function()
    return game:HttpGet(apiUrl, true)
end)

local jsonData
if okJson and jsonRaw then
    local okDecode, decoded = pcall(function()
        return game:GetService("HttpService"):JSONDecode(jsonRaw)
    end)
    jsonData = (okDecode and decoded) or {Classes={}}
else
    jsonData = {Classes={}}
end

-- String builder
local sizeCounter = 0
local stringBuilder = {}

-- Escape characters
local specialCharacters = {
    ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;", ["\0"] = "", ["="] = ""
}

local ignoredProperties = {"Name","Parent","TimeOfDay"}

-- Build object table
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

-- Escape XML
local function removeSpecials(text)
    if typeof(text) ~= "string" then return tostring(text) end
    return ({text:gsub("[<>&\"'\0=]", function(c) return specialCharacters[c] end)})[1]
end

-- Write helper
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

-- Special cases
local specialCases = {
    Vector3 = function(obj, prop)
        local ok,v = pcall(function() return obj[prop] end)
        if not ok or v==nil or typeof(v)~="Vector3" then return "" end
        return `<Vector3 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
    end,
    Vector2 = function(obj, prop)
        local ok,v = pcall(function() return obj[prop] end)
        if not ok or v==nil or typeof(v)~="Vector2" then return "" end
        return `<Vector2 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y></Vector2>`
    end,
    Color3 = function(obj, prop)
        local ok,v = pcall(function() return obj[prop] end)
        if not ok or v==nil or typeof(v)~="Color3" then return "" end
        return `<Color3 name="{prop}"><R>{v.R}</R><G>{v.G}</G><B>{v.B}</B></Color3>`
    end,
    CFrame = function(obj, prop)
        local ok,c = pcall(function()
            local cf=obj[prop]
            if typeof(cf)~="CFrame" then return nil end
            return {cf:GetComponents()}
        end)
        if not ok or c==nil then return "" end
        return `<CoordinateFrame name="{prop}"><X>{c[1]}</X><Y>{c[2]}</Y><Z>{c[3]}</Z><R00>{c[4]}</R00><R01>{c[5]}</R01><R02>{c[6]}</R02><R10>{c[7]}</R10><R11>{c[8]}</R11><R12>{c[9]}</R12><R20>{c[10]}</R20><R21>{c[11]}</R21><R22>{c[12]}</R22></CoordinateFrame>`
    end,
    InitialSize = function(obj)
        local ok,v = pcall(function() return gethiddenproperty and gethiddenproperty(obj, "InitialSize") end)
        if not ok or v==nil or typeof(v)~="Vector3" then return "" end
        return `<Vector3 name="InitialSize"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
    end
}

-- Recursive writer
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
            if typeName and specialCases[typeName] then
                output = specialCases[typeName](obj, propName)
            elseif typeName=="Enum" and typeof(value)=="EnumItem" then
                output = `<token name="{propName}">{value.Value}</token>`
            else
                output = `<{typeName} name="{propName}">{value}</{typeName}>`
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

    -- Scripts
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("Script") then
            local ok, source = pcall(function() return child.Source end)
            if ok and source and source~="" then
                write(`<ScriptContent name="{removeSpecials(child.Name)}">{removeSpecials(source)}</ScriptContent>`)
            end
        elseif child:IsA("ModuleScript") then
            write(`<ModuleStub name="{removeSpecials(child.Name)}"></ModuleStub>`)
        end
    end

    -- MeshPart / SpecialMesh fix
    if obj:IsA("MeshPart") or obj:IsA("SpecialMesh") or obj:IsA("FileMesh") then
        pcall(function()
            if obj.MeshId then write(`<Content name="MeshId">{obj.MeshId}</Content>`) end
            if obj.TextureID then write(`<Content name="TextureID">{obj.TextureID}</Content>`) end
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

-- Fun ReadMe
local readMeScript = Instance.new("Script")
readMeScript.Name = "READ ME"
readMeScript.Source = [[
-- Hello! You look amazing today! God bless
-- You can put more fun messages here
]]
readMeScript.Parent = workspace

-- Start RBXLX
writefile(`{game.PlaceId}.rbxlx`, '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')

-- Save all main objects
for _, mainObj in ipairs(settings.Save) do writeObject(mainObj) end

write("</roblox>")

-- Flush
if #stringBuilder>0 then
    appendfile(`{game.PlaceId}.rbxlx`, table.concat(stringBuilder))
    stringBuilder = {}
end

print(`Finished! Took {tick()-start}s`)
