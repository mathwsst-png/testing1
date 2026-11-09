-- Probe v2: membaca schema Net dan source pemanggil pencarian world.
-- Tidak mengirim packet, memanggil remote, atau mengubah world.
local output, size = {}, 0
local budget = 240000
local function emit(value)
    local text = tostring(value)
    if size >= budget then return end
    if #text > budget - size then text = text:sub(1, budget - size) .. "\n[REPORT LIMIT]" end
    output[#output + 1], size = text, size + #text + 1
end
local globals = (getgenv and getgenv()) or _G
local refs = globals.__n4thOpus and globals.__n4thOpus.References or {}
local constants = (debug and debug.getconstants) or getconstants
local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
local replicated = game:GetService("ReplicatedStorage")
local player = game:GetService("Players").LocalPlayer
local gui = player and player:FindFirstChild("PlayerGui")
local playerScripts = player and player:FindFirstChild("PlayerScripts")
local shared = replicated:FindFirstChild("Shared")
emit("n4th world API/source v2 | Place=" .. tostring(game.PlaceId) .. " | Version=" .. tostring(game.PlaceVersion))
emit("Queue=" .. type(queue) .. " | decompile=" .. type(decompile) .. " | constants=" .. type(constants))

local function keys(value)
    if type(value) ~= "table" then return type(value) end
    local list = {}
    for key, item in pairs(value) do
        if type(key) == "string" then list[#list + 1] = key .. ":" .. type(item) end
    end
    table.sort(list)
    return table.concat(list, ", ")
end

local candidates, seen, inventory = {}, {}, {}
local function scriptObject(value)
    return typeof(value) == "Instance" and (value:IsA("ModuleScript") or value:IsA("LocalScript"))
end
local function add(object, priority)
    if scriptObject(object) and not seen[object] then
        seen[object] = true
        candidates[#candidates + 1] = { object = object, priority = priority or 5 }
    end
end
local function sourceOf(label, fn)
    if type(fn) ~= "function" then return end
    local path
    if debug and type(debug.info) == "function" then
        local ok, result = pcall(debug.info, fn, "s")
        if ok then path = result end
    end
    emit(label .. " source=" .. tostring(path))
    if type(getfunctionscript) == "function" then
        local ok, script = pcall(getfunctionscript, fn)
        if ok then add(script, 1) end
    end
    if type(getfenv) == "function" then
        local ok, env = pcall(getfenv, fn)
        if ok and type(env) == "table" then add(rawget(env, "script"), 1) end
    end
    if type(path) == "string" then
        for _, script in ipairs(inventory) do
            if path == script:GetFullName() or path == "=" .. script:GetFullName() then add(script, 1) end
        end
    end
    if type(constants) == "function" then
        local ok, values = pcall(constants, fn)
        if ok and type(values) == "table" then
            local strings = {}
            for _, value in pairs(values) do
                if type(value) == "string" and #value < 150 and #strings < 80 then strings[#strings + 1] = value:gsub("\n", " ") end
            end
            emit(label .. " constants: " .. table.concat(strings, " | "))
        end
    end
end

-- Controller picker dapat berasal dari modul yang berbeda dari WorldMenu.
for _, root in ipairs({ gui or false, playerScripts or false }) do
    if root then
        for _, object in ipairs(root:GetDescendants()) do
            if scriptObject(object) then inventory[#inventory + 1] = object end
        end
    end
end
table.sort(inventory, function(a, b) return a:GetFullName() < b:GetFullName() end)
for _, object in ipairs(inventory) do emit("CLIENT SCRIPT " .. object:GetFullName() .. " [" .. object.ClassName .. "]") end

local netObject = shared and shared:FindFirstChild("Net")
add(netObject, 0)
local menu = refs.Menu
if not menu and type(getgc) == "function" then
    local ok, objects = pcall(getgc, true)
    if ok and type(objects) == "table" then
        local scanned = 0
        for _, value in pairs(objects) do
            scanned += 1
            if type(value) == "table" and type(rawget(value, "openBackpack")) == "function"
                and type(rawget(value, "ui")) == "table" then
                menu = value
                break
            end
            if scanned % 20000 == 0 then task.wait() end
        end
        emit("GC menu scanned=" .. scanned)
    end
end
emit("Active Menu keys: " .. keys(menu))
if type(menu) == "table" then
    for key, fn in pairs(menu) do
        if type(key) == "string" and type(fn) == "function" then
            local lower = key:lower()
            if lower:find("pick", 1, true) or lower:find("world", 1, true) or lower:find("search", 1, true) or lower == "enter" then
                sourceOf("Menu." .. key, fn)
            end
        end
    end
end

if scriptObject(netObject) then
    local ok, net = pcall(require, netObject)
    if ok and type(net) == "table" then
        for _, key in ipairs({ "ASK", "CALLS", "NOTE", "worldsAnswer", "list", "look" }) do
            local value = rawget(net, key)
            emit("Net." .. key .. " keys: " .. keys(value))
            if (key == "ASK" or key == "CALLS") and type(value) == "table" then
                for name, entry in pairs(value) do emit("  " .. tostring(name) .. " -> " .. keys(entry)) end
            end
        end
    else emit("Net require failed: " .. tostring(net)) end
end

for _, object in ipairs(inventory) do
    local name = object.Name:lower()
    if name:find("picker", 1, true) or name:find("worldlist", 1, true) then add(object, 2)
    elseif name == "menu" or name == "mainmenu" or name == "worldmenu" then add(object, 3)
    elseif name == "world" or object:IsA("LocalScript") then add(object, 4)
    elseif name == "client" or name == "main" or name == "game" then add(object, 5) end
end
table.sort(candidates, function(a, b)
    if a.priority == b.priority then return a.object:GetFullName() < b.object:GetFullName() end
    return a.priority < b.priority
end)

local terms = { "worldsanswer", "openpicker", "worldpicker", "worldlist", "worldinfo", "worldlookup", "searchworld", "getworld", '"worlds"', "'worlds'", "teleport", "net.call", "net.list", "net.look" }
for index, entry in ipairs(candidates) do
    if index > 12 or size >= budget then break end
    local object, label = entry.object, entry.object:GetFullName()
    print("[n4th source v2] Membaca " .. label)
    if type(decompile) ~= "function" then emit("decompile unavailable") break end
    local ok, source = pcall(decompile, object)
    if ok and type(source) == "string" then
        emit("SOURCE " .. label .. " | length=" .. #source)
        if object == netObject then
            -- Net v1 terpotong di awal; v2 membawa semua schema paket/RPC.
            emit(source)
        else
            local lower, ranges, matched = source:lower(), {}, {}
            for _, term in ipairs(terms) do
                local cursor, hits = 1, 0
                while hits < 5 do
                    local at = lower:find(term, cursor, true)
                    if not at then break end
                    ranges[#ranges + 1] = { first = math.max(1, at - 600), last = math.min(#source, at + 2000) }
                    matched[term], hits, cursor = true, hits + 1, at + #term
                end
            end
            table.sort(ranges, function(a, b) return a.first < b.first end)
            local merged = {}
            for _, range in ipairs(ranges) do
                local previous = merged[#merged]
                if previous and range.first <= previous.last + 1 then previous.last = math.max(previous.last, range.last)
                else merged[#merged + 1] = range end
            end
            local labels = {}
            for term in pairs(matched) do labels[#labels + 1] = term end
            table.sort(labels)
            emit("Matched: " .. table.concat(labels, ", "))
            local sent = 0
            for _, range in ipairs(merged) do
                if sent >= 45000 then emit("[MODULE EXCERPT LIMIT]") break end
                local snippet = source:sub(range.first, math.min(range.last, range.first + 45000 - sent - 1))
                emit("CHARS " .. range.first .. ".." .. (range.first + #snippet - 1) .. "\n" .. snippet)
                sent += #snippet
            end
        end
    else emit("decompile failed: " .. tostring(source)) end
    task.wait()
end
local report = table.concat(output, "\n")
if type(writefile) == "function" then pcall(writefile, "n4th-world-source-report.txt", report) end
local copied = type(setclipboard) == "function" and pcall(setclipboard, report)
if copied then print("[n4th] Source v2 sudah disalin (" .. #report .. " karakter). Paste ke chat ini.")
else print(report) end
return report
