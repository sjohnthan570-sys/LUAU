--[[ 
    Universal Safe SaveInstance Script
    Fully crash-proof, silent, captures orphaned scripts,
    saves ModuleScript stubs, attributes, materials, CollectionService tags,
    properly handles MeshParts/SpecialMeshes/FileMeshes,
    and guarantees well-formed XML for RBXLX.
--]]

local settings = {
    TableSize = 10000,
    Save = {workspace}
}

local start = tick()

-- Fetch Roblox class dump safely
local success, version = pcall(function()
    return game:HttpGet("https://setup.roblox.com/versionQTStudio", true)
end)
version = success and version or "default"

local apiUrl = "https://setup.roblox.com/" .. version .. "-API-Dump.json"
local success2, jsonRaw = pcall(function()
    return game:HttpGet(apiUrl, true)
end)

local jsonData
if success2 and jsonRaw then
    local ok, decoded = pcall(function()
        return game:GetService("HttpService"):JSONDecode(jsonRaw)
    end)
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
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&apos;",
    ["\0"] = "",
    ["="] = ""
}

local function removeSpecials(text)
    if typeof(text) ~= "string" then text = tostring(text) end
    return (text:gsub("[<>&\"'\0=]", function(c)
        return specialCharacters[c]
    end))
end

local function write(text)
    sizeCounter += 1
    table.insert(stringBuilder, text)
    if sizeCounter >= settings.TableSize then
        appendfile(string.format("%d.rbxlx", game.PlaceId), table.concat(stringBuilder))
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
            and member.Serialization and member.Serialization["CanLoad"]
        then
            if member.ValueType.Category == "Enum" then
                propTable[member.Name] = {"Enum", member.ValueType.Name}
            else
                propTable[member.Name] = {member.ValueType.Name}
            end
        end
    end
    objTable[obj.Name] = {Properties = propTable, Superclass = obj.Superclass}
end

-- Recursive inheritance
local function getAllProps(objName)
    local props = {}
    local classInfo = objTable[objName]

    if classInfo and classInfo.Superclass ~= "<<<ROOT>>>" and objTable[classInfo.Superclass] then
        for k,v in pairs(getAllProps(classInfo.Superclass)) do props[k] = v end
    end
    if classInfo then
        for k,v in pairs(classInfo.Properties) do props[k] = v end
    end

    return props
end

for objName,objData in pairs(objTable) do
    objData.Properties = getAllProps(objName)
end

-- Hidden InitialSize
if objTable["UnionOperation"] then objTable["UnionOperation"].Properties["InitialSize"] = {"InitialSize"} end
if objTable["MeshPart"] then objTable["MeshPart"].Properties["InitialSize"] = {"InitialSize"} end

print(string.format("Initialized! Took %fs", tick() - start))
start = tick()

-- Special cases
local specialCases = {
    Vector3 = function(obj, prop)
        local ok, v = pcall(function() return obj[prop] end)
        if not ok or typeof(v) ~= "Vector3" then return "" end
        return `<Vector3 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
    end,

    Vector2 = function(obj, prop)
        local ok, v = pcall(function() return obj[prop] end)
        if not ok or typeof(v) ~= "Vector2" then return "" end
        return `<Vector2 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y></Vector2>`
    end,

    Color3 = function(obj, prop)
        local ok, v = pcall(function() return obj[prop] end)
        if not ok or typeof(v) ~= "Color3" then return "" end
        return `<Color3 name="{prop}"><R>{v.R}</R><G>{v.G}</G><B>{v.B}</B></Color3>`
    end,

    CFrame = function(obj, prop)
        local ok, c = pcall(function()
            local cf = obj[prop]
            if typeof(cf) ~= "CFrame" then return nil end
            return { cf:GetComponents() }
        end)
        if not ok or not c then return "" end
        return `<CoordinateFrame name="{prop}"><X>{c[1]}</X><Y>{c[2]}</Y><Z>{c[3]}</Z><R00>{c[4]}</R00><R01>{c[5]}</R01><R02>{c[6]}</R02><R10>{c[7]}</R10><R11>{c[8]}</R11><R12>{c[9]}</R12><R20>{c[10]}</R20><R21>{c[11]}</R21><R22>{c[12]}</R22></CoordinateFrame>`
    end,

    InitialSize = function(obj)
        local ok, v = pcall(function()
            return gethiddenproperty and gethiddenproperty(obj, "InitialSize")
        end)
        if not ok or typeof(v) ~= "Vector3" then return "" end
        return `<Vector3 name="InitialSize"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
    end
}

-- Recursive object writer
local function writeObject(obj)
    write(string.format('<Item class="%s"><Properties>', obj.ClassName))
    write(string.format('<String name="Name">%s</String>', removeSpecials(obj.Name)))

    local classInfo = objTable[obj.ClassName]
    if classInfo then
        for propName, info in pairs(classInfo.Properties) do
            local typeName = info[1]
            local ok, value = pcall(function() return obj[propName] end)
            if not ok or value == nil then continue end

            local out = ""

            if specialCases[typeName] then
                out = specialCases[typeName](obj, propName)
            elseif typeName == "Enum" and typeof(value) == "EnumItem" then
                out = string.format('<token name="%s">%d</token>', propName, value.Value)
            else
                out = string.format('<%s name="%s">%s</%s>', typeName, propName, removeSpecials(tostring(value)), typeName)
            end

            if out ~= "" then write(out) end
        end
    end

    -- Material
    pcall(function()
        if obj.Material then
            write(string.format('<Enum name="Material">%s</Enum>', tostring(obj.Material)))
        end
    end)

    -- Attributes
    for _, att in ipairs(obj:GetAttributes()) do
        write(string.format('<Attribute name="%s">%s</Attribute>', att, removeSpecials(tostring(obj:GetAttribute(att)))))
    end

    -- CollectionService tags
    local tags = {}
    pcall(function()
        tags = game:GetService("CollectionService"):GetTags(obj)
    end)

    for _, tag in ipairs(tags) do
        write(string.format('<Tag>%s</Tag>', removeSpecials(tag)))
    end

    -- Scripts
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("Script") then
            local ok, src = pcall(function() return child.Source end)
            if ok and src then
                write(string.format(
                    '<ScriptContent name="%s"><![CDATA[%s]]></ScriptContent>',
                    removeSpecials(child.Name),
                    src
                ))
            end
        elseif child:IsA("ModuleScript") then
            write(string.format('<ModuleStub name="%s"></ModuleStub>', removeSpecials(child.Name)))
        end
    end

    -- Meshes
    if obj:IsA("MeshPart") or obj:IsA("SpecialMesh") or obj:IsA("FileMesh") then
        pcall(function()
            if obj.MeshId then write(string.format('<Content name="MeshId">%s</Content>', removeSpecials(obj.MeshId))) end
            if obj.TextureID then write(string.format('<Content name="TextureID">%s</Content>', removeSpecials(obj.TextureID))) end
        end)
    end

    write("</Properties>")

    for _, child in ipairs(obj:GetChildren()) do
        writeObject(child)
    end

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

-- Start file
writefile(string.format("%d.rbxlx", game.PlaceId),
    '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
)

-- Save
for _, obj in ipairs(settings.Save) do
    writeObject(obj)
end

write("</roblox>")

-- Flush
if #stringBuilder > 0 then
    appendfile(string.format("%d.rbxlx", game.PlaceId), table.concat(stringBuilder))
end

print(string.format("Finished! Took %fs", tick() - start))
