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
local function writeTerrainVoxels(terrain, opts)
    opts = opts or {}
    local resolution = opts.resolution or 4
    local chunkSize = opts.chunkSize or 32 -- number of voxels per axis in a chunk (tune as needed)

    -- Attempt to read global extents - these exist in Studio
    local successMinMax, minVec, maxVec = pcall(function()
        local me = terrain.MaxExtents
        return me.Min, me.Max
    end)

    if not successMinMax or (not minVec) or (not maxVec) then
        -- Fallback: try simple region around origin (small)
        minVec = Vector3.new(-512, 0, -512)
        maxVec = Vector3.new(512, 256, 512)
    end

    -- Convert world-space min/max to integer voxel coordinates for Region3int16.
    -- Region3int16 expects Vector3int16; we convert each component to integers.
    local function toInt16(v)
        return Vector3int16.new(math.floor(v.X), math.floor(v.Y), math.floor(v.Z))
    end

    -- Compute world extents as integers
    local minI = toInt16(minVec)
    local maxI = toInt16(maxVec)

    -- Helper to clamp chunk extents
    local function clamp(a, b, x) return math.max(a, math.min(b, x)) end

    -- Write a container tag for terrain
    write("<Terrain>")
    write(`<TerrainResolution>{resolution}</TerrainResolution>`)

    -- We will iterate by chunk in world coordinates. Each chunk will be chunkSize * resolution units,
    -- but Region3int16 uses voxel coordinates; using integer world coords is acceptable for chunking.
    local step = chunkSize * resolution

    local x0 = minI.X
    local y0 = minI.Y
    local z0 = minI.Z
    local x1 = maxI.X
    local y1 = maxI.Y
    local z1 = maxI.Z

    -- iterate through space in chunks
    for cx = x0, x1, step do
        for cy = y0, y1, step do
            for cz = z0, z1, step do
                -- compute chunk box (world coords)
                local chunkMin = Vector3.new(cx, cy, cz)
                local chunkMax = Vector3.new(math.min(cx + step - 1, x1),
                                             math.min(cy + step - 1, y1),
                                             math.min(cz + step - 1, z1))

                -- convert to Region3int16 (floor to integers)
                local regionMin = Vector3int16.new(math.floor(chunkMin.X), math.floor(chunkMin.Y), math.floor(chunkMin.Z))
                local regionMax = Vector3int16.new(math.floor(chunkMax.X), math.floor(chunkMax.Y), math.floor(chunkMax.Z))

                local ok, materials, occupancy = pcall(function()
                    return terrain:ReadVoxels(Region3int16.new(regionMin, regionMax), resolution)
                end)

                if ok and materials and occupancy then
                    -- materials and occupancy are 3D arrays with .Size property (Size.X, Size.Y, Size.Z).
                    -- We'll write only occupied voxels to save space.
                    local size = materials.Size
                    write(`<TerrainChunk minX="{regionMin.X}" minY="{regionMin.Y}" minZ="{regionMin.Z}" sizeX="{size.X}" sizeY="{size.Y}" sizeZ="{size.Z}">`)

                    for xi = 1, size.X do
                        for yi = 1, size.Y do
                            for zi = 1, size.Z do
                                local occ = occupancy[xi][yi][zi]
                                if occ and occ > 0 then
                                    local mat = materials[xi][yi][zi]
                                    -- material may be enum; tostring(mat) gives readable name
                                    write(("<Voxel><X>%d</X><Y>%d</Y><Z>%d</Z><Material>%s</Material><Occupancy>%.6f</Occupancy></Voxel>")
                                        :format(xi - 1 + regionMin.X, yi - 1 + regionMin.Y, zi - 1 + regionMin.Z, tostring(mat), occ))
                                end
                            end
                        end
                    end

                    write("</TerrainChunk>")
                end

                -- allow short pause so large maps don't stall studio/UI
                task.wait()
            end
        end
    end

    write("</Terrain>")
end
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

