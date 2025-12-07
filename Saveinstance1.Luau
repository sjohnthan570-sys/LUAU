--[[ 
    UNIVERSAL SAVEINSTANCE (CLEAN VERSION)
    --------------------------------------
    ✔ Crash-proof
    ✔ RBXLX export
    ✔ Script source export
    ✔ ModuleScript stubs (no content)
    ✔ Materials, Attributes, Tags
    ✔ Hidden properties (InitialSize, etc.)
    ✔ Progress bar
]]

local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

local settings = {
    TableSize = 12000,
    Save = { workspace }
}

local start = tick()

---------------------------------------------------------------------
-- FETCH ROBLOX API DUMP
---------------------------------------------------------------------
local version = game:HttpGet("https://setup.roblox.com/versionQTStudio", true)
assert(version ~= "", "Failed to get Roblox version")

local apiData = HttpService:JSONDecode(
    game:HttpGet("https://setup.roblox.com/" .. version .. "-API-Dump.json", true)
)

---------------------------------------------------------------------
-- STRING BUILDER
---------------------------------------------------------------------
local sizeCounter = 0
local stringBuilder = {}

local function write(text)
    sizeCounter += 1
    table.insert(stringBuilder, text)

    if sizeCounter >= settings.TableSize then
        appendfile(`${game.PlaceId}.rbxlx`, table.concat(stringBuilder))
        stringBuilder = {}
        sizeCounter = 0
        task.wait()
    end
end

---------------------------------------------------------------------
-- XML ESCAPING
---------------------------------------------------------------------
local xmlEscape = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&apos;",
    ["="] = "",
    ["\0"] = ""
}

local function clean(str)
    if typeof(str) ~= "string" then return tostring(str) end
    return (str:gsub("[<>&\"'=\0]", xmlEscape))
end

---------------------------------------------------------------------
-- BUILD CLASS PROPERTY TABLE
---------------------------------------------------------------------
local objTable = {}

for _, class in pairs(apiData.Classes) do
    local props = {}

    for _, member in pairs(class.Members) do
        if member.MemberType == "Property"
        and not table.find(member.Tags or {}, "NotScriptable")
        and member.Serialization.CanLoad
        and member.Name ~= "Name"
        and member.Name ~= "Parent" then

            if member.ValueType.Category == "Enum" then
                props[member.Name] = { "Enum", member.ValueType.Name }
            else
                props[member.Name] = { member.ValueType.Name }
            end
        end
    end

    objTable[class.Name] = {
        Properties = props,
        Superclass = class.Superclass
    }
end

-- Inheritance
local function applyInheritance(name)
    local info = objTable[name]
    if not info then return {} end
    if info.Superclass == "<<<ROOT>>>" then return info.Properties end

    local inherited = applyInheritance(info.Superclass)
    for k, v in pairs(info.Properties) do inherited[k] = v end
    return inherited
end

for name, data in pairs(objTable) do
    data.Properties = applyInheritance(name)
end

-- Add hidden props (InitialSize)
for _, className in ipairs({ "UnionOperation", "MeshPart" }) do
    if objTable[className] then
        objTable[className].Properties["InitialSize"] = { "InitialSize" }
    end
end

---------------------------------------------------------------------
-- SPECIAL PROPERTY SERIALIZATION
---------------------------------------------------------------------
local specialCases = {
    Vector3 = function(obj, prop)
        local ok, v = pcall(function() return obj[prop] end)
        if ok and v then
            return `<Vector3 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
        end
    end,

    Vector2 = function(obj, prop)
        local ok, v = pcall(function() return obj[prop] end)
        if ok and v then
            return `<Vector2 name="{prop}"><X>{v.X}</X><Y>{v.Y}</Y></Vector2>`
        end
    end,

    Color3 = function(obj, prop)
        local ok, v = pcall(function() return obj[prop] end)
        if ok and v then
            return `<Color3 name="{prop}"><R>{v.R}</R><G>{v.G}</G><B>{v.B}</B></Color3>`
        end
    end,

    CFrame = function(obj, prop)
        local ok, c = pcall(function() return { obj[prop]:GetComponents() } end)
        if ok and c then
            return `<CoordinateFrame name="{prop}">` ..
            `<X>{c[1]}</X><Y>{c[2]}</Y><Z>{c[3]}</Z>` ..
            `<R00>{c[4]}</R00><R01>{c[5]}</R01><R02>{c[6]}</R02>` ..
            `<R10>{c[7]}</R10><R11>{c[8]}</R11><R12>{c[9]}</R12>` ..
            `<R20>{c[10]}</R20><R21>{c[11]}</R21><R22>{c[12]}</R22>` ..
            `</CoordinateFrame>`
        end
    end,

    InitialSize = function(obj)
        local ok, v = pcall(function()
            return gethiddenproperty and gethiddenproperty(obj, "InitialSize")
        end)
        if ok and v then
            return `<Vector3 name="InitialSize"><X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`
        end
    end
}

---------------------------------------------------------------------
-- ATTRIBUTE EXPORT
---------------------------------------------------------------------
local function writeAttributes(obj)
    for _, attrName in ipairs(obj:GetAttributes()) do
        local v = obj:GetAttribute(attrName)
        local t = typeof(v)

        if t == "string" then
            write(`<string name="{attrName}">{clean(v)}</string>`)
        elseif t == "number" then
            write(`<double name="{attrName}">{v}</double>`)
        elseif t == "boolean" then
            write(`<bool name="{attrName}">{tostring(v)}</bool>`)
        elseif t == "Vector3" then
            write(`<Vector3 name="{attrName}">` ..
                `<X>{v.X}</X><Y>{v.Y}</Y><Z>{v.Z}</Z></Vector3>`)
        elseif t == "Color3" then
            write(`<Color3 name="{attrName}">` ..
                `<R>{v.R}</R><G>{v.G}</G><B>{v.B}</B></Color3>`)
        end
    end
end

---------------------------------------------------------------------
-- TAG EXPORT
---------------------------------------------------------------------
local function writeTags(obj)
    local tags = CollectionService:GetTags(obj)
    if #tags > 0 then
        write(`<Tags>{table.concat(tags, ";")}</Tags>`)
    end
end

---------------------------------------------------------------------
-- PROGRESS BAR
---------------------------------------------------------------------
local totalObjects = 0

local function countObjects(root)
    totalObjects += 1
    for _, child in pairs(root:GetChildren()) do
        countObjects(child)
    end
end

for _, root in ipairs(settings.Save) do countObjects(root) end

local processed = 0
local function progress()
    processed += 1
    if processed % 230 == 0 then
        local pct = math.floor((processed / totalObjects) * 100)
        rconsoleprint(`@|white|[SAVE] {pct}%  ({processed}/{totalObjects})\n`)
    end
end

---------------------------------------------------------------------
-- MAIN OBJECT WRITER
---------------------------------------------------------------------
local function writeObject(obj)
    progress()

    write(`<Item class="{obj.ClassName}">`)
    write("<Properties>")

    write(`<String name="Name">{clean(obj.Name)}</String>`)

    local props = objTable[obj.ClassName] and objTable[obj.ClassName].Properties
    if props then
        for propName, info in pairs(props) do
            local ok, val = pcall(function() return obj[propName] end)
            if ok and val ~= nil then
                local typeName = info[1]

                if specialCases[typeName] then
                    local xml = specialCases[typeName](obj, propName)
                    if xml then write(xml) end

                elseif typeName == "Enum" then
                    write(`<token name="{propName}">{val.Value}</token>`)

                else
                    write(`<{typeName} name="{propName}">{clean(val)}</{typeName}>`)
                end
            end
        end
    end

    writeAttributes(obj)
    writeTags(obj)

    write("</Properties>")

    -- Script exporting
    for _, child in ipairs(obj:GetChildren()) do
        if child:IsA("Script") then
            local ok, src = pcall(function() return child.Source end)
            if ok and src and src ~= "" then
                write(`<ScriptSource name="{clean(child.Name)}">{clean(src)}</ScriptSource>`)
            end
        elseif child:IsA("ModuleScript") then
            write(`<ModuleStub name="{clean(child.Name)}"/>`)
        end
    end

    -- Recurse into non-services
    for _, child in ipairs(obj:GetChildren()) do
        if not child.ClassName:match("Service$") then
            writeObject(child)
        end
    end

    write("</Item>")
end

---------------------------------------------------------------------
-- BEGIN FILE
---------------------------------------------------------------------
writefile(`${game.PlaceId}.rbxlx`,
    '<roblox xmlns:xmime="http://www.roblox.com/2005/05/xmlmime" ' ..
    'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' ..
    'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
)

for _, root in ipairs(settings.Save) do
    writeObject(root)
end

write("</roblox>")

if #stringBuilder > 0 then
    appendfile(`${game.PlaceId}.rbxlx`, table.concat(stringBuilder))
end

print("FINISHED in", tick() - start, "seconds")
