--[[ 
    Universal Safe SaveInstance Script
    Fully crash-proof, silent, captures orphaned scripts,
    saves ModuleScript stubs, attributes, materials, CollectionService tags,
    properly handles MeshParts/SpecialMeshes, and shows a progress bar
--]]

local settings = {
    TableSize = 10000,
    Save = {workspace}
}

local b64encode = crypt and crypt.base64encode or function() return "" end
local b64decode = crypt and crypt.base64decode or function() return "" end
local start = tick()

-- Fetch Roblox class dump
local version = game:HttpGet("https://setup.roblox.com/versionQTStudio", true)
assert(version and version ~= "", "Failed to get Roblox version")
local apiUrl = "https://setup.roblox.com/" .. version .. "-API-Dump.json"
local jsonData = game:HttpGet(apiUrl, true)
assert(jsonData and jsonData ~= "", "Failed to fetch API dump")
local decoded = game:GetService("HttpService"):JSONDecode(jsonData)

-- String builder
local sizeCounter = 0
local stringBuilder = {}

-- Characters to escape
local specialCharacters = {["&"]="&amp;",["<"]="&lt;",[">"]="&gt;",['"']="&quot;",["'"]="&apos;",["\0"]="",["="]=""}
local ignoredProperties = {"Name","Parent","TimeOfDay"}

-- Build object table
local objTable = {}
for _, obj in pairs(decoded.Classes) do
    local propTable = {}
    for _, member in pairs(obj.Members) do
        if not table.find(member.Tags or {}, "NotScriptable") and member.MemberType == "Property" 
        and not table.find(ignoredProperties, member.Name) and member.Serialization["CanLoad"] then
            propTable[member.Name] = member.ValueType.Category=="Enum" and {"Enum", member.ValueType.Name} or {member.ValueType.Name}
        end
    end
    objTable[obj.Name] = {Properties=propTable, Superclass=obj.Superclass}
end

-- Recursive inheritance
local function getAllProps(objName)
    local props = {}
    local classInfo = objTable[objName]
    if classInfo.Superclass~="<<<ROOT>>>" then
        for k,v in pairs(getAllProps(classInfo.Superclass)) do props[k]=v end
    end
    for k,v in pairs(classInfo.Properties) do props[k]=v end
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
    if typeof(text)~="string" then return tostring(text) end
    return ({text:gsub("[<>&\"'\0=]", function(c) return specialCharacters[c] end)})[1]
end

-- Write helper
local function write(text)
    sizeCounter += 1
    table.insert(stringBuilder,text)
    if sizeCounter>=settings.TableSize then
        appendfile(`{game.PlaceId}.rbxlx`, table.concat(stringBuilder))
        stringBuilder={}
        sizeCounter=0
        task.wait()
    end
end

-- Special cases
local specialCases = {
    Vector3=function(obj,prop) local ok,v=pcall(function() return obj[prop] end) if not ok or v==nil or typeof(v)~="Vector3" then return "" end return `<Vector3 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>` end,
    Vector2=function(obj,prop) local ok,v=pcall(function() return obj[prop] end) if not ok or v==nil or typeof(v)~="Vector2" then return "" end return `<Vector2 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y></Vector2>` end,
    Color3=function(obj,prop) local ok,v=pcall(function() return obj[prop] end) if not ok or v==nil or typeof(v)~="Color3" then return "" end return `<Color3 name="{prop}"><R>{v.R}</R><G>{v.G}</G><B>{v.B}</B></Color3>` end,
    CFrame=function(obj,prop) local ok,c=pcall(function() local cf=obj[prop] if typeof(cf)~="CFrame" then return nil end return {cf:GetComponents()} end) if not ok or c==nil then return "" end return `<CoordinateFrame name="{prop}"><X>{c[1]}</X><Y>{c[2]}</Y><Z>{c[3]}</Z><R00>{c[4]}</R00><R01>{c[5]}</R01><R02>{c[6]}</R02><R10>{c[7]}</R10><R11>{c[8]}</R11><R12>{c[9]}</R12><R20>{c[10]}</R20><R21>{c[11]}</R21><R22>{c[12]}</R22></CoordinateFrame>` end,
    InitialSize=function(obj) local ok,v=pcall(function() return gethiddenproperty and gethiddenproperty(obj,"InitialSize") end) if not ok or v==nil or typeof(v)~="Vector3" then return "" end return `<Vector3 name="InitialSize"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>` end
}

-- Non-service check
local function isNotService(obj)
    return not obj:IsDescendantOf(workspace) and not obj:IsDescendantOf(game:GetService("ReplicatedStorage"))
       and not obj:IsDescendantOf(game:GetService("ServerStorage")) and not obj:IsDescendantOf(game:GetService("Players"))
       and not obj:IsDescendantOf(game:GetService("Lighting"))
end

-- ==== PROGRESS GUI ====
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local progressGui = Instance.new("ScreenGui")
progressGui.Name = "SaveProgressGui"
progressGui.ResetOnSpawn=false
progressGui.Parent = playerGui

local progressText = Instance.new("TextLabel")
progressText.Size=UDim2.new(0,200,0,50)
progressText.Position=UDim2.new(0.5,-100,0,10)
progressText.BackgroundTransparency=0.5
progressText.BackgroundColor3=Color3.fromRGB(0,0,0)
progressText.TextColor3=Color3.fromRGB(255,255,255)
progressText.TextScaled=true
progressText.Text="0%"
progressText.Font=Enum.Font.SourceSansBold
progressText.Parent=progressGui

-- Count all objects
local totalObjects=0
local function countObjects(obj)
    totalObjects+=1
    for _,child in ipairs(obj:GetChildren()) do if isNotService(child) then countObjects(child) end end
end
for _,mainObj in ipairs(settings.Save) do countObjects(mainObj) end
local objectsWritten=0

-- Recursive writer
local function writeObjectRecursive(obj)
    -- Write object
    write(`<Item class="{obj.ClassName}"><Properties>`)
    write(`<String name="Name">{removeSpecials(obj.Name)}</String>`)

    local classInfo=objTable[obj.ClassName]
    if classInfo then
        for propName,propInfo in pairs(classInfo.Properties) do
            local typeName=propInfo[1]
            local ok,value=pcall(function() return obj[propName] end)
            if ok and value~=nil then
                local output=""
                if typeName and specialCases[typeName] then
                    output = specialCases[typeName](obj,propName)
                elseif typeName=="Enum" and typeof(value)=="EnumItem" then
                    output=`<token name="{propName}">{value.Value}</token>`
                else
                    output=`<{typeName} name="{propName}">{value}</{typeName}>`
                end
                if output~="" then write(output) end
            end
        end
    end

    -- Material
    if pcall(function() return obj.Material end) then
        write(`<Enum name="Material">{tostring(obj.Material)}</Enum>`)
    end

    -- Attributes
    for _,attrName in ipairs(obj:GetAttributes()) do
        local val=obj:GetAttribute(attrName)
        write(`<Attribute name="{attrName}">{removeSpecials(tostring(val))}</Attribute>`)
    end

    -- CollectionService Tags
    local CollectionService=game:GetService("CollectionService")
    local tags={}
    pcall(function() tags=CollectionService:GetTags(obj) end)
    for _,tag in ipairs(tags) do write(`<Tag>{removeSpecials(tag)}</Tag>`) end

    -- Scripts / ModuleScripts
    for _,child in ipairs(obj:GetChildren()) do
        if child:IsA("Script") then
            local ok,source=pcall(function() return child.Source end)
            if ok and source and source~="" then
                write(`<ScriptContent name="{removeSpecials(child.Name)}">{removeSpecials(source)}</ScriptContent>`)
            end
        elseif child:IsA("ModuleScript") then
            write(`<ModuleStub name="{removeSpecials(child.Name)}"></ModuleStub>`)
        end
    end

    -- MeshPart / SpecialMesh / FileMesh fix
    if obj:IsA("MeshPart") or obj:IsA("SpecialMesh") or obj:IsA("FileMesh") then
        local okMesh,meshId=pcall(function() return obj.MeshId end)
        if okMesh and meshId then write(`<Content name="MeshId">{meshId}</Content>`) end
        local okTex,texId=pcall(function() return obj.TextureID end)
        if okTex and texId then write(`<Content name="TextureID">{texId}</Content>`) end
        local okSize,size=pcall(function() return obj.Size end)
        if okSize and size then write(`<Vector3 name="Size">{size.X} {size.Y} {size.Z}</Vector3>`) end
        local okScale,scale=pcall(function() return obj.Scale end)
        if okScale and scale then write(`<Vector3 name="Scale">{scale.X} {scale.Y} {scale.Z}</Vector3>`) end
        local okOffset,offset=pcall(function() return obj.Offset end)
        if okOffset and offset then write(`<Vector3 name="Offset">{offset.X} {offset.Y} {offset.Z}</Vector3>`) end
    end

    write("</Properties>")

    -- Update progress
    objectsWritten+=1
    progressText.Text=math.floor(objectsWritten/totalObjects*100).."%"

    -- Recurse
    for _,child in ipairs(obj:GetChildren()) do if isNotService(child) then writeObjectRecursive(child) end end

    write("</Item>")
end

-- Fun ReadMe
local readMeScript=Instance.new("Script")
readMeScript.Name="READ ME"
readMeScript.Source=[[
-- Hello! You look amazin
