--[[ 
    Universal Safe SaveInstance Script (Optimized)
    - Mesh/Texture export fixes
    - Major performance improvements (caching + buffering)
    - Attributes, CollectionService tags
    - ModuleScript stubs (no source)
    - Defensive: avoids NumberSequence/ColorSequence/InitialSize/Enum crashes
--]]

-- === CONFIG ===
local settings = {
    TableSize = 60000,           -- larger buffer = fewer writes (increase if you have memory)
    Save = { workspace },        -- roots to save
    ShowProgressEvery = 200      -- show progress every N objects
}

-- === SERVICES / LOCALS ===
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Game = game
local PlaceId = Game.PlaceId

local start = tick()

-- === FETCH API DUMP (same as before) ===
local version = Game:HttpGet("https://setup.roblox.com/versionQTStudio", true)
assert(version and version ~= "", "Failed to get Roblox version")
local apiUrl = "https://setup.roblox.com/" .. version .. "-API-Dump.json"
local apiJson = Game:HttpGet(apiUrl, true)
assert(apiJson and apiJson ~= "", "Failed to fetch API dump")
local apiData = HttpService:JSONDecode(apiJson)

-- === XML escape helper (fast) ===
local esc = {
    ["&"] = "&amp;",
    ["<"] = "&lt;",
    [">"] = "&gt;",
    ['"'] = "&quot;",
    ["'"] = "&apos;"
}
local function xml(s)
    if typeof(s) ~= "string" then s = tostring(s) end
    -- faster single-pass replace
    return (s:gsub("[&<>'\"]", esc))
end

-- === write buffer / flush ===
local bufferCount = 0
local buffer = {}

local function flush()
    if bufferCount > 0 then
        appendfile(("%s.rbxlx"):format(PlaceId), table.concat(buffer))
        buffer = {}
        bufferCount = 0
    end
end

local function writeRaw(text)
    buffer[#buffer + 1] = text
    bufferCount = bufferCount + 1
    if bufferCount >= settings.TableSize then
        flush()
        task.wait()
    end
end

-- === build class property cache (writable props only) ===
local ignoredProperties = { Name = true, Parent = true, TimeOfDay = true }
local objTable = {}
local writableProps = {}  -- { className = { propName1, propName2, ... } }

for _, class in ipairs(apiData.Classes) do
    local propMap = {}
    for _, m in ipairs(class.Members) do
        if m.MemberType == "Property"
           and not ignoredProperties[m.Name]
           and not table.find(m.Tags or {}, "NotScriptable")
           and m.Serialization and m.Serialization.CanLoad then

            propMap[m.Name] = m.ValueType.Category == "Enum" and { "Enum", m.ValueType.Name } or { m.ValueType.Name }
        end
    end
    objTable[class.Name] = { Properties = propMap, Superclass = class.Superclass }
end

-- inheritance flatten
local function flattenProps(name, memo)
    memo = memo or {}
    local info = objTable[name]
    if not info then return memo end
    if info.Superclass and info.Superclass ~= "<<<ROOT>>>" then
        flattenProps(info.Superclass, memo)
    end
    for k, v in pairs(info.Properties) do memo[k] = v end
    return memo
end

for className, data in pairs(objTable) do
    local props = flattenProps(className)
    writableProps[className] = {}
    for propName, propInfo in pairs(props) do
        writableProps[className][#writableProps[className] + 1] = { propName, propInfo }
    end
end

-- add hidden InitialSize where relevant (defensive)
if writableProps["UnionOperation"] then table.insert(writableProps["UnionOperation"], 1, {"InitialSize", {"InitialSize"}}) end
if writableProps["MeshPart"] then table.insert(writableProps["MeshPart"], 1, {"InitialSize", {"InitialSize"}}) end

-- === special formatters keyed by runtime typeof(value) ===
local specialFormat = {}

specialFormat["Vector3"] = function(prop, v)
    return "<Vector3 name=\"" .. prop .. "\"><X>" .. v.X .. "</X><Y>" .. v.Y .. "</Y><Z>" .. v.Z .. "</Z></Vector3>"
end
specialFormat["Vector2"] = function(prop, v)
    return "<Vector2 name=\"" .. prop .. "\"><X>" .. v.X .. "</X><Y>" .. v.Y .. "</Y></Vector2>"
end
specialFormat["Color3"] = function(prop, v)
    return "<Color3 name=\"" .. prop .. "\"><R>" .. v.R .. "</R><G>" .. v.G .. "</G><B>" .. v.B .. "</B></Color3>"
end
specialFormat["CFrame"] = function(prop, v)
    local c = { v:GetComponents() }
    return "<CoordinateFrame name=\"" .. prop .. "\"><X>" .. c[1] .. "</X><Y>" .. c[2] .. "</Y><Z>" .. c[3] ..
        "</Z><R00>" .. c[4] .. "</R00><R01>" .. c[5] .. "</R01><R02>" .. c[6] ..
        "</R02><R10>" .. c[7] .. "</R10><R11>" .. c[8] .. "</R11><R12>" .. c[9] ..
        "</R12><R20>" .. c[10] .. "</R20><R21>" .. c[11] .. "</R21><R22>" .. c[12] .. "</R22></CoordinateFrame>"
end
specialFormat["EnumItem"] = function(prop, v)
    return "<token name=\"" .. prop .. "\">" .. xml(v.Value) .. "</token>"
end
-- InitialSize handled via gethiddenproperty below

-- === helpers for Mesh IDs / Texture IDs ===
local function looksLikeAsset(str)
    if not str or str == "" then return false end
    -- common formats: rbxassetid://12345, http(s)://, asset://, rbxasset://
    if typeof(str) ~= "string" then str = tostring(str) end
    str = str:lower()
    if str:match("^rbxassetid://%d+") or str:match("^http[s]?://") or str:match("^rbxasset://") or str:match("^asset://") then
        return true
    end
    -- some MeshId formats are "http://www.roblox.com/asset/?id=12345" - allow digits present
    if str:match("%d") then
        return true
    end
    return false
end

-- === count objects for progress ===
local total = 0
local function countAll(root)
    total = total + 1
    for _, c in ipairs(root:GetChildren()) do countAll(c) end
end
for _, r in ipairs(settings.Save) do countAll(r) end

local processed = 0
local function progressTick()
    processed = processed + 1
    if processed % settings.ShowProgressEvery == 0 then
        local pct = math.floor((processed / math.max(1, total)) * 100)
        rconsoleprint(("@@WHITE@@[SAVE] %d%% (%d/%d)\n"):format(pct, processed, total))
    end
end

-- === main writer (fast, defensive) ===
local function writeObject(root)
    -- iterative stack rather than deep recursion to avoid deep recursion overhead
    local stack = { root }
    while #stack > 0 do
        local obj = table.remove(stack) -- pop
        progressTick()

        -- open item + properties
        writeRaw("<Item class=\"" .. xml(obj.ClassName) .. "\">")
        writeRaw("<Properties>")
        writeRaw("<String name=\"Name\">" .. xml(obj.Name) .. "</String>")

        local propsList = writableProps[obj.ClassName]
        if propsList then
            for i = 1, #propsList do
                local pair = propsList[i]
                local propName = pair[1]
                local propInfo = pair[2]
                -- safe read
                local ok, v = pcall(function() return obj[propName] end)
                if not ok or v == nil then
                    -- special-case InitialSize via gethiddenproperty if propName == "InitialSize"
                    if propName == "InitialSize" then
                        local ok2, hidden = pcall(function() return gethiddenproperty and gethiddenproperty(obj, "InitialSize") end)
                        if ok2 and hidden and typeof(hidden) == "Vector3" then
                            writeRaw("<Vector3 name=\"InitialSize\"><X>" .. hidden.X .. "</X><Y>" .. hidden.Y .. "</Y><Z>" .. hidden.Z .. "</Z></Vector3>")
                        end
                    end
                    goto continue_prop -- continue
                end

                do
                    local vtype = typeof(v)
                    -- special runtime formatters
                    if specialFormat[vtype] then
                        local formatted = specialFormat[vtype](propName, v)
                        if formatted and formatted ~= "" then writeRaw(formatted) end
                        goto continue_prop
                    end

                    -- Enum metadata provided by api dump; but runtime type may be EnumItem
                    if vtype == "EnumItem" then
                        writeRaw("<token name=\"" .. propName .. "\">" .. xml(v.Value) .. "</token>")
                        goto continue_prop
                    end

                    -- default fallback: write simple scalar/string/number/bool
                    if vtype == "string" or vtype == "number" or vtype == "boolean" then
                        writeRaw("<" .. propInfo[1] .. " name=\"" .. propName .. "\">" .. xml(v) .. "</" .. propInfo[1] .. ">")
                    end
                end

                ::continue_prop::
            end
        end

        -- QUICK MESH FIXES: MeshPart, SpecialMesh, FileMesh
        -- MeshPart: write Size, MeshId, TextureId only if valid
        if obj:IsA("MeshPart") then
            local okSize, size = pcall(function() return obj.Size end)
            if okSize and typeof(size) == "Vector3" then
                writeRaw("<Vector3 name=\"Size\"><X>" .. size.X .. "</X><Y>" .. size.Y .. "</Y><Z>" .. size.Z .. "</Z></Vector3>")
            end
            local okMesh, meshId = pcall(function() return obj.MeshId end)
            if okMesh and meshId and looksLikeAsset(meshId) then
                writeRaw("<Content name=\"MeshId\">" .. xml(tostring(meshId)) .. "</Content>")
            end
            -- TextureID or TextureId normalization
            local okTex, tex = pcall(function() return obj.TextureID or obj.TextureId end)
            if okTex and tex and looksLikeAsset(tex) then
                writeRaw("<Content name=\"TextureId\">" .. xml(tostring(tex)) .. "</Content>")
            end
        end

        if obj:IsA("SpecialMesh") or obj:IsA("FileMesh") then
            local okScale, scale = pcall(function() return obj.Scale end)
            if okScale and typeof(scale) == "Vector3" then
                writeRaw("<Vector3 name=\"Scale\"><X>" .. scale.X .. "</X><Y>" .. scale.Y .. "</Y><Z>" .. scale.Z .. "</Z></Vector3>")
            end
            local okOffset, offset = pcall(function() return obj.Offset end)
            if okOffset and typeof(offset) == "Vector3" then
                writeRaw("<Vector3 name=\"Offset\"><X>" .. offset.X .. "</X><Y>" .. offset.Y .. "</Y><Z>" .. offset.Z .. "</Z></Vector3>")
            end
            local okMesh, meshId = pcall(function() return obj.MeshId end)
            if okMesh and meshId and looksLikeAsset(meshId) then
                writeRaw("<Content name=\"MeshId\">" .. xml(tostring(meshId)) .. "</Content>")
            end
            local okTex, tex = pcall(function() return obj.TextureId end)
            if okTex and tex and looksLikeAsset(tex) then
                writeRaw("<Content name=\"TextureId\">" .. xml(tostring(tex)) .. "</Content>")
            end
        end

        -- Material (fast)
        local okMat, mat = pcall(function() return obj.Material end)
        if okMat and mat then writeRaw("<token name=\"Material\">" .. xml(tostring(mat)) .. "</token>") end

        -- Attributes (fast local)
        local okAttrs, attrs = pcall(function() return obj:GetAttributes() end)
        if okAttrs and attrs and #attrs > 0 then
            for _, an in ipairs(attrs) do
                local val = obj:GetAttribute(an)
                writeRaw("<Attribute name=\"" .. xml(an) .. "\">" .. xml(tostring(val)) .. "</Attribute>")
            end
        end

        -- Tags
        local okTags, tges = pcall(function() return CollectionService:GetTags(obj) end)
        if okTags and tges and #tges > 0 then
            writeRaw("<Tags>" .. xml(table.concat(tges, ";")) .. "</Tags>")
        end

        -- Scripts + Module stubs + push children onto stack (single pass)
        local children = obj:GetChildren()
        for i = 1, #children do
            local ch = children[i]
            if ch:IsA("Script") then
                local okSrc, src = pcall(function() return ch.Source end)
                if okSrc and src and src ~= "" then
                    writeRaw("<ScriptContent name=\"" .. xml(ch.Name) .. "\">" .. xml(src) .. "</ScriptContent>")
                end
            elseif ch:IsA("ModuleScript") then
                -- stub only
                writeRaw("<ModuleStub name=\"" .. xml(ch.Name) .. "\"/>")
            end
            -- push into stack for recursion (skip services)
            if not ch.ClassName:match("Service$") then
                stack[#stack + 1] = ch
            end
        end

        writeRaw("</Properties>")
        writeRaw("</Item>")
    end
end

-- === begin file ===
writeRaw('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')

for _, root in ipairs(settings.Save) do
    writeObject(root)
end

writeRaw("</roblox>")
flush()

print(("Save finished in %.2fs — objects processed: %d"):format(tick() - start, processed))
