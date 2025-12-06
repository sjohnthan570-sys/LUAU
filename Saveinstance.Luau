local settings = {
    ["TableSize"] = 10000,
    ["Save"] = {workspace}
}

local b64encode = crypt and crypt.base64encode or function() return "" end
local b64decode = crypt and crypt.base64decode or function() return "" end

local start = tick()
local Http = game:GetService("HttpService")

-- Load API Dump
local version = game:HttpGet("http://setup.roblox.com/versionQTStudio", true)
local dumpUrl = "http://setup.roblox.com/" .. version .. "-API-Dump.json"

local decoded = Http:JSONDecode(game:HttpGet(dumpUrl, true))

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

local ignoredProperties = {"Name","Parent","TimeOfDay"}

---------------------------------------------------------------------

local objTable = {}

for _,obj in pairs(decoded.Classes) do
    local propTable = {}
    for _,member in pairs(obj.Members) do
        if member.MemberType == "Property"
        and not table.find((member.Tags or {}), "NotScriptable")
        and member.Serialization.CanLoad
        and not table.find(ignoredProperties, member.Name) then
            
            propTable[member.Name] =
                member.ValueType.Category == "Enum"
                and {"Enum", member.ValueType.Name}
                or {member.ValueType.Name}
        end
    end

    objTable[obj.Name] = {
        Properties = propTable,
        Superclass = obj.Superclass
    }
end

function getAllProps(className)
    if objTable[className].Superclass ~= "<<<ROOT>>>" then
        local props = objTable[className].Properties
        for pname, pinfo in pairs(getAllProps(objTable[className].Superclass)) do
            props[pname] = pinfo
        end
        return props
    else
        return objTable[className].Properties
    end
end

for cname,cinfo in pairs(objTable) do
    cinfo.Properties = getAllProps(cname)
end

-- Add InitialSize manually
objTable["UnionOperation"].Properties["InitialSize"] = {"InitialSize"}
objTable["MeshPart"].Properties["InitialSize"] = {"InitialSize"}

print("Initialized! Took " .. (tick()-start) .. "s")
start = tick()

---------------------------------------------------------------------

function removeSpecials(text)
    return ({text:gsub("[<>&\"'\0]", function(c)
        return specialCharacters[c]
    end)})[1]
end

function write(text)
    sizeCounter += 1
    table.insert(stringBuilder, text)

    if sizeCounter >= settings.TableSize then
        appendfile(tostring(game.PlaceId)..".rbxlx", table.concat(stringBuilder))
        stringBuilder = {}
        sizeCounter = 0
        task.wait()
    end
end

---------------------------------------------------------------------

local specialCases = {
    ["Vector3"] = function(obj,prop)
        local v = obj[prop]
        return `<Vector3 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
    end,

    ["Vector2"] = function(obj,prop)
        local v = obj[prop]
        return `<Vector2 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y></Vector2>`
    end,

    ["Color3"] = function(obj,prop)
        local v = obj[prop]
        return `<Color3 name="{prop}"><R>{v.R}</R><G>{v.G}</G><B>{v.B}</B></Color3>`
    end,

    ["UDim2"] = function(obj,prop)
        local v = obj[prop]
        return `<UDim2 name="{prop}"><XS>{v.X.Scale}</XS><XO>{v.X.Offset}</XO><YS>{v.Y.Scale}</YS><YO>{v.Y.Offset}</YO></UDim2>`
    end,

    ["CFrame"] = function(obj,prop)
        local c = {obj[prop]:GetComponents()}
        return `<CoordinateFrame name="{prop}">
            <X>{c[1]}</X><Y>{c[2]}</Y><Z>{c[3]}</Z>
            <R00>{c[4]}</R00><R01>{c[5]}</R01><R02>{c[6]}</R02>
            <R10>{c[7]}</R10><R11>{c[8]}</R11><R12>{c[9]}</R12>
            <R20>{c[10]}</R20><R21>{c[11]}</R21><R22>{c[12]}</R22>
        </CoordinateFrame>`
    end,

    ["Content"] = function(obj,prop)
        return `<Content name="{prop}"><url>{removeSpecials(obj[prop])}</url></Content>`
    end,

    ["InitialSize"] = function(obj,prop)
        local ok, value = pcall(function()
            return gethiddenproperty and gethiddenproperty(obj,prop)
        end)

        if not ok or not value then
            value = obj.Size
        end

        return `<Vector3 name="{prop}"><X>{value.X}</X><Y>{value.Y}</Y><Z>{value.Z}</Z></Vector3>`
    end,

    ["BinaryString"] = function(obj,prop)
        return `<BinaryString name="{prop}">{b64encode(obj[prop])}</BinaryString>`
    end,

    ["string"] = function(obj,prop)
        return `<string name="{prop}">{removeSpecials(obj[prop])}</string>`
    end,
}

---------------------------------------------------------------------

-- SAFE writeObject with pcall protection
local function writeObject(obj)
    write(`<Item class="{obj.ClassName}"><Properties><String name="Name">{removeSpecials(obj.Name)}</String>`)

    local classInfo = objTable[obj.ClassName]
    if classInfo then
        for propName, propInfo in pairs(classInfo.Properties) do

            local propType = propInfo[1]

            -- Try reading property safely
            local ok, value = pcall(function()
                return obj[propName]
            end)

            if not ok then
                continue
            end

            local text = ""

            if specialCases[propType] then
                text = specialCases[propType](obj, propName)

            elseif ok and value ~= nil then
                if propType == "Enum" then
                    text = `<token name="{propName}">{value.Value}</token>`
                else
                    text = `<{propType} name="{propName}">{value}</{propType}>`
                end
            end

            if text ~= "" then
                write(text)
            end
        end
    end

    write("</Properties>")

    -- Recurse children
    for _,child in ipairs(obj:GetChildren()) do
        writeObject(child)
    end

    write("</Item>")
end

---------------------------------------------------------------------
-- TERRAIN SAVE
---------------------------------------------------------------------

local function saveTerrain()
    local Terrain = workspace.Terrain

    local region = Region3int16.new(
        Vector3int16.new(-16000, 0, -16000),
        Vector3int16.new(16000, 2047, 16000)
    )

    local terrainRegion = Terrain:CopyRegion(region)
    if not terrainRegion then return end

    local raw = terrainRegion:Encode()
    local encoded = b64encode(raw)

    write(`<Item class="Terrain"><Properties>`)
    write(`<BinaryString name="TerrainData">{encoded}</BinaryString>`)

    write(`<Color3 name="WaterColor"><R>{Terrain.WaterColor.R}</R><G>{Terrain.WaterColor.G}</G><B>{Terrain.WaterColor.B}</B></Color3>`)
    write(`<float name="WaterReflectance">{Terrain.WaterReflectance}</float>`)
    write(`<float name="WaterTransparency">{Terrain.WaterTransparency}</float>`)
    write(`<float name="WaterWaveSize">{Terrain.WaterWaveSize}</float>`)
    write(`<float name="WaterWaveSpeed">{Terrain.WaterWaveSpeed}</float>`)

    write("</Properties></Item>")
end

---------------------------------------------------------------------

-- BEGIN FILE
writefile(tostring(game.PlaceId)..".rbxlx",
`<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">`
)

for _,mainObj in ipairs(settings.Save) do
    writeObject(mainObj)
end

-- SAVE TERRAIN NOW
saveTerrain()

write("</roblox>")
appendfile(tostring(game.PlaceId)..".rbxlx", table.concat(stringBuilder))

print("Finished! Took " .. (tick()-start) .. "s")

