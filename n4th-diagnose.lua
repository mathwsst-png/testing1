-- Pemeriksaan baca-saja: tidak memukul, memasang, atau mengirim remote game.
local lines = {}
local function emit(message) lines[#lines + 1] = tostring(message) end
local function keysOf(value, limit)
    if type(value) ~= "table" then return type(value) end
    local keys = {}
    for key, child in pairs(value) do
        if type(key) == "string" then keys[#keys + 1] = key .. ":" .. type(child) end
    end
    table.sort(keys)
    while #keys > (limit or 45) do table.remove(keys) end
    return table.concat(keys, ", ")
end
local function info(fn, option)
    if debug and type(debug.info) == "function" then
        local ok, result = pcall(debug.info, fn, option)
        if ok then return result end
    end
    if option == "s" and debug and type(debug.getinfo) == "function" then
        local ok, result = pcall(debug.getinfo, fn, "S")
        if ok and type(result) == "table" then return result.source or result.short_src or "?" end
    end
    return "?"
end
local constants
if type(debug and debug.getconstants) == "function" or type(getconstants) == "function" then
    constants = function(fn)
        for _, api in ipairs({ (debug and debug.getconstants) or false, getconstants or false }) do
            if type(api) == "function" then
                local ok, values = pcall(api, fn)
                if ok and type(values) == "table" and next(values) ~= nil then return values end
            end
        end
        return {}
    end
end
local function describeFunction(fn)
    local result = "name=" .. tostring(info(fn, "n")) .. " | parameters=" .. tostring(info(fn, "a"))
        .. " | source=" .. tostring(info(fn, "s"))
    if type(constants) == "function" then
        local ok, data = pcall(constants, fn)
        if ok and type(data) == "table" then
            local count, fields = 0, {}
            for _, value in pairs(data) do
                count += 1
                if type(value) == "string" and #value < 50 and value:match("^[%a_][%w_%.]*$") and #fields < 18 then
                    fields[#fields + 1] = value
                end
            end
            result ..= " | constants=" .. count .. " | fields=" .. table.concat(fields, ",")
        else result ..= " | constants failed=" .. tostring(data) end
    end
    return result
end
emit("n4th diagnosis v7 | Place=" .. tostring(game.PlaceId) .. " | Version=" .. tostring(game.PlaceVersion))
do
    local identify = identifyexecutor or getexecutorname
    if type(identify) == "function" then
        local ok, name, version = pcall(identify)
        if ok then emit("Executor=" .. tostring(name) .. " | ExecutorVersion=" .. tostring(version)) end
    end
    local actors = getactors or get_actors or (actor and actor.getactors)
    if type(actors) == "function" then
        local ok, values = pcall(actors)
        if ok and type(values) == "table" then local n=0;for _ in pairs(values) do n+=1 end;emit("Actor states=" .. n) end
    end
    emit("Native filter=" .. type(filtergc or filter_gc) .. " | actor execution=" .. type(run_on_actor or (actor and actor.run)))
    local began = game:GetService("UserInputService").InputBegan
    if type(getconnections) == "function" then
        local ok, values = pcall(getconnections, began)
        if ok and type(values) == "table" then
            local total, readable, foreign=0,0,0
            for _, connection in pairs(values) do
                total+=1
                local got, fn=pcall(function() return connection.Function end)
                if got and type(fn)=="function" then readable+=1 end
                local gotForeign, other=pcall(function() return connection.ForeignState end)
                if gotForeign and other then foreign+=1 end
            end
            emit(("Input connections=%d readable=%d foreign=%d"):format(total,readable,foreign))
        end
    end
end
emit("API getgc=" .. type(getgc) .. " | constants=" .. type(constants) .. " | getconnections=" .. type(getconnections))
emit("Raw API constants debug=" .. type(debug and debug.getconstants) .. " global=" .. type(getconstants)
    .. " | upvalues debug=" .. type(debug and debug.getupvalues) .. " global=" .. type(getupvalues))
local globals = (getgenv and getgenv()) or _G
local session = globals.__n4thOpus
emit("Session build=" .. tostring(session and session.Build) .. " | ready=" .. tostring(session and session.Ready))
if session and session.BootstrapReport then emit("Startup structure: " .. session.BootstrapReport) end
if session and type(session.ModuleScan) == "table" then
    local scan = session.ModuleScan
    emit("Module data scan tables=" .. tostring(scan.Tables) .. " exports=" .. tostring(scan.Loaded)
        .. " failed=" .. tostring(scan.Errors) .. " last=" .. tostring(scan.LastError))
    if scan.DatabaseResolution then emit("Database resolution: " .. tostring(scan.DatabaseResolution)) end
end
if session and type(session.Modules) == "table" then
    for name, path in pairs(session.Modules) do emit("Resolved module " .. name .. "=" .. tostring(path)) end
end
local player = game:GetService("Players").LocalPlayer
local playerGui = player and player:FindFirstChild("PlayerGui")
local gameGui = playerGui and playerGui:FindFirstChild("GameGui")
emit("GameGui=" .. tostring(gameGui ~= nil) .. " | World GUI=" .. tostring(gameGui and gameGui:FindFirstChild("World") ~= nil))
do
    local replicated = game:GetService("ReplicatedStorage")
    local roots = {}
    local ok, children = pcall(replicated.GetChildren, replicated)
    if ok and type(children) == "table" then
        for _, child in pairs(children) do roots[#roots + 1] = child.Name .. ":" .. child.ClassName end
        table.sort(roots)
    end
    emit("ReplicatedStorage children: " .. table.concat(roots, ", "))
    local seen, count = {}, 0
    local function show(object, source)
        local valid, path = pcall(function()
            if not object:IsA("ModuleScript") then return nil end
            return object:GetFullName()
        end)
        if valid and path and not seen[object] then
            seen[object], count = true, count + 1
            if count <= 140 then emit("CLIENT MODULE [" .. source .. "] " .. path) end
        end
    end
    local valid, descendants = pcall(replicated.GetDescendants, replicated)
    if valid and type(descendants) == "table" then for _, object in pairs(descendants) do show(object, "tree") end end
    for _, entry in ipairs({ { "getloadedmodules", getloadedmodules }, { "getmodules", getmodules } }) do
        emit("Module API " .. entry[1] .. "=" .. type(entry[2]))
        if type(entry[2]) == "function" then
            local got, values = pcall(entry[2])
            if got and type(values) == "table" then
                for _, object in pairs(values) do show(object, entry[1]) end
            else emit(entry[1] .. " failed: " .. tostring(values)) end
        end
    end
    emit("Unique client modules=" .. count .. (count > 140 and " (paths limited to 140)" or ""))
end
if session and type(session.References) == "table" then
    local refs = session.References
    emit("Session World=" .. type(refs.World) .. " | Inventory=" .. type(refs.Inv) .. " | Hit=" .. type(refs.Punch)
        .. " | setTile=" .. type(refs.SetTile) .. " | GC visited=" .. tostring(refs.ScanCount))
    emit("Connection objects visited=" .. tostring(refs.ConnectionCount))
    if type(refs.Punch) == "function" then emit("Bound punch: " .. describeFunction(refs.Punch)) end
    if refs.ScanError then emit("Session scan error=" .. tostring(refs.ScanError)) end
    if type(refs.World) == "table" then
        emit("Session World keys: " .. keysOf(refs.World, 350))
        for key, fn in pairs(refs.World) do
            if type(key) == "string" and type(fn) == "function" then
                local lower = key:lower()
                if lower:find("tile", 1, true) or lower:find("punch", 1, true) or lower:find("hit", 1, true)
                    or lower:find("backpack", 1, true) then emit("Session World." .. key .. ": " .. describeFunction(fn)) end
            end
        end
    end
end

local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
if shared then
    local inventory = shared:FindFirstChild("Inventory", true)
    if inventory and inventory:IsA("ModuleScript") then
        local ok, value = pcall(require, inventory)
        emit("Inventory module=" .. inventory:GetFullName() .. " | require=" .. tostring(ok))
        if ok then
            emit("Inventory module keys: " .. keysOf(value))
            if type(value) == "table" and type(value.new) == "function" then emit("Inventory.new: " .. describeFunction(value.new)) end
        end
    else
        emit("Inventory module: missing")
    end
end

if type(getgc) ~= "function" then
    emit("STOP: executor tidak menyediakan getgc")
else
    local ok, objects = pcall(getgc, true)
    if not ok or type(objects) ~= "table" then ok, objects = pcall(getgc) end
    if not ok or type(objects) ~= "table" then
        emit("STOP: getgc gagal: " .. tostring(objects))
    else
        local worlds, bags, candidates, examined, readable, constantCount = 0, 0, {}, 0, 0, 0
        local visited, types, sources, prefix = 0, {}, {}, 0
        for _ in ipairs(objects) do
            prefix += 1
            if prefix >= 10000 then break end
        end
        emit("GC length (#)=" .. #objects .. " | ipairs prefix=" .. prefix .. (prefix == 10000 and "+" or ""))
        for _, value in pairs(objects) do
            visited += 1
            types[type(value)] = (types[type(value)] or 0) + 1
            if type(value) == "table" then
                local slots = rawget(value, "slots")
                local capacity = rawget(value, "capacity")
                if worlds < 2 and type(rawget(value, "fg")) == "table" and type(rawget(value, "bg")) == "table"
                    and type(rawget(value, "w")) == "number" then
                    worlds += 1
                    emit("World #" .. worlds .. " keys: " .. keysOf(value, 350))
                    for key, fn in pairs(value) do
                        if type(key) == "string" and type(fn) == "function" then
                            local lower = key:lower()
                            if lower:find("tile", 1, true) or lower:find("punch", 1, true)
                                or lower:find("hit", 1, true) or lower:find("backpack", 1, true) then
                                emit("World." .. key .. ": " .. describeFunction(fn))
                            end
                        end
                    end
                    local mt = getmetatable(value)
                    emit("World meta: " .. keysOf(mt))
                    if type(mt) == "table" then emit("World __index: " .. keysOf(rawget(mt, "__index"))) end
                end
                if bags < 6 and (type(slots) == "table" or capacity ~= nil) then
                    local countType, removeType = "?", "?"
                    pcall(function() countType, removeType = type(value.count), type(value.remove) end)
                    if type(slots) == "table" or countType == "function" then
                        bags += 1
                        emit("Inventory candidate #" .. bags .. ": " .. keysOf(value, 65))
                        emit("  slots=" .. type(slots) .. " capacity=" .. type(capacity) .. " count=" .. countType .. " remove=" .. removeType)
                        local mt = getmetatable(value)
                        emit("  meta: " .. keysOf(mt))
                        if type(mt) == "table" then emit("  __index: " .. keysOf(rawget(mt, "__index"))) end
                        if type(slots) == "table" then
                            for _, slot in pairs(slots) do
                                if type(slot) == "table" then emit("  slot keys: " .. keysOf(slot, 20)); break end
                            end
                        end
                    end
                end
            elseif type(value) == "function" and type(constants) == "function" then
                local source = tostring(info(value, "s"))
                sources[source] = (sources[source] or 0) + 1
                local functionName = tostring(info(value, "n")):lower()
                do -- source metadata bisa kosong/generik pada executor tertentu
                    examined += 1
                    local got, data = pcall(constants, value)
                    if got and type(data) == "table" then
                        readable += 1
                        local marks, score, action = {}, 0, false
                        for _, text in pairs(data) do
                            constantCount += 1
                            if type(text) == "string" then
                                local lower = text:lower()
                                if lower:find("punch", 1, true) or lower:find("crack", 1, true)
                                    or lower:find("harvest", 1, true) or lower:find("placedat", 1, true)
                                    or lower:find("settile", 1, true) or lower:find("vending", 1, true)
                                    or lower == "flips" or lower == "tile" or lower == "handpower" then
                                    score += 1
                                    if lower == "newcrack" or lower == "harvestprovider" or lower == "placedat" or lower == "flips" then action = true end
                                    if #marks < 16 then marks[#marks + 1] = text:sub(1, 100) end
                                end
                            end
                        end
                        if action or score >= 3 or functionName == "punch" or functionName == "settile" or functionName == "hittile" then
                            candidates[#candidates + 1] = {fn=value, source=source, marks=marks, score=score}
                        end
                    end
                end
            end
            if visited % 2000 == 0 then task.wait() end
        end
        table.sort(candidates, function(a, b) return a.score > b.score end)
        emit("Actually visited=" .. visited .. " | tables=" .. tostring(types.table or 0) .. " | functions=" .. tostring(types["function"] or 0))
        emit("Scanned functions=" .. examined .. " | constants readable=" .. readable .. " | constant values=" .. constantCount)
        local sourceList = {}
        for source, count in pairs(sources) do sourceList[#sourceList + 1] = {source=source, count=count} end
        table.sort(sourceList, function(a, b) return a.count > b.count end)
        for index = 1, math.min(#sourceList, 8) do
            emit("Source group: " .. sourceList[index].source .. " | count=" .. sourceList[index].count)
        end
        for index = 1, math.min(#candidates, 12) do
            local candidate = candidates[index]
            emit("Action candidate #" .. index .. " name=" .. tostring(info(candidate.fn, "n"))
                .. " | parameters=" .. tostring(info(candidate.fn, "a")) .. " | source=" .. candidate.source)
            emit("  markers: " .. table.concat(candidate.marks, " | "))
        end
    end
end

local report = table.concat(lines, "\n")
print(report)
if type(setclipboard) == "function" then
    local ok = pcall(setclipboard, report)
    if ok then print("[n4th] Laporan diagnosis sudah disalin. Paste ke chat ini.") end
end
return report
