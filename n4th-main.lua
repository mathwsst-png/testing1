local G = (getgenv and getgenv()) or _G
for _, key in ipairs({ "__n4thOpus", "__GTFarm" }) do -- __GTFarm = nama versi lama
    if G[key] and G[key].Cleanup then pcall(G[key].Cleanup) end
    G[key] = nil
end
local Session = {}
Session.Build = "2026-11-14-route-drop-row-sweep"
G.__n4thOpus = Session
local function alive()
    return G.__n4thOpus == Session
end
-- Alias executor tetap lokal agar lingkungan game tidak ikut berubah.
local getgc = getgc or get_gc_objects
local getmodules = getmodules or get_modules
local gethui = gethui or get_hidden_gui
function Session.connectionFunction(connection)
    if type(connection) == "function" then return connection end
    local ok, fn = pcall(function() return connection.Function end)
    if ok and type(fn) == "function" then return fn end
    if type(getconnectionfunction) == "function" then
        ok, fn = pcall(getconnectionfunction, connection)
        if ok and type(fn) == "function" then return fn end
    end
end
function Session.scanStep(budget, visited)
    if visited % 64 ~= 0 or os.clock() < budget.next then return end
    task.wait()
    budget.next = os.clock() + 0.001
end
Session.InitStep = "layanan game"
function Session.download(url)
    local lastError = "respons kosong"
    local function checked(source)
        if type(source) ~= "string" or source:match("^%s*$") then return nil, "respons kosong" end
        if source:match("^%s*<") then return nil, "server mengirim HTML, bukan script/metadata" end
        if source:match("^%s*[45]%d%d[:%s]") then return nil, source:sub(1, 120) end
        return source
    end
    local ok, source = pcall(function() return game:HttpGet(url) end)
    if ok then
        local valid, reason = checked(source)
        if valid then return valid end
        lastError = reason
    else lastError = tostring(source) end
    local seen = {}
    for _, api in ipairs({ request or false, http_request or false, (syn and syn.request) or false, (http and http.request) or false }) do
        if type(api) == "function" and not seen[api] then
            seen[api] = true
            local sent, response = pcall(api, { Url = url, Method = "GET" })
            if sent and type(response) == "table" then
                local status = tonumber(response.StatusCode or response.Status)
                if status and (status < 200 or status >= 300) then
                    lastError = "HTTP " .. tostring(status)
                else
                    local valid, reason = checked(response.Body or response.body)
                    if valid then return valid end
                    lastError = reason
                end
            else lastError = tostring(response) end
        end
    end
    error("[n4th] Unduh gagal: " .. tostring(lastError), 0)
end
print("[n4th] Memuat build " .. Session.Build)
task.delay(45, function()
    if alive() and not Session.Ready then
        warn("[n4th] Masih memuat: " .. tostring(Session.InitStep)
            .. ". Kirim baris ini jika menu belum muncul.")
    end
end)

do
    local getId = getthreadidentity or get_thread_identity or getidentity or (syn and syn.get_thread_identity)
    if type(getId) == "function" then pcall(function() Session.Ident = getId() end) end
    Session.Exec = coroutine.create(function(job)
        while true do
            local ok, err = pcall(job)
            job = coroutine.yield(ok, err)
        end
    end)
end

---------------------------------------------------------------------
-- SERVICES & MODULE GAME
---------------------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local PlayerGui
local Shared, WorldRemotes, SetTileRemote
local ItemDB, InventoryModule, NetOk, Net
local GameGui, ParticlesOk, ParticlesModule, MenuModOk, MenuModule
local RolesOk, RolesModule, SfxOk, SfxModule
do
    local deadline = os.clock() + 15
    while not LocalPlayer and os.clock() < deadline do
        task.wait(0.1)
        LocalPlayer = Players.LocalPlayer
    end
    assert(LocalPlayer, "[n4th] LocalPlayer belum tersedia. Masuk ke game lalu execute ulang.")

    local function requiredChild(parent, name)
        Session.InitStep = parent:GetFullName() .. "/" .. name
        local child = parent:FindFirstChild(name) or parent:WaitForChild(name, 15)
        assert(child, "[n4th] Tidak menemukan " .. Session.InitStep .. " setelah 15 detik.")
        return child
    end
    PlayerGui = requiredChild(LocalPlayer, "PlayerGui")
    -- FIX: tunggu game benar-benar siap (GameReady + GameGui) sebelum memindai modul.
    -- Sebelumnya pemindaian jalan saat game masih loading -> kadang gagal, kadang bisa.
    do
        if not game:IsLoaded() then
            Session.InitStep = "menunggu game selesai dimuat"
            pcall(function() game.Loaded:Wait() end)
        end
        Session.InitStep = "menunggu GameReady / GameGui"
        local readyBy = os.clock() + 30
        while alive() and os.clock() < readyBy do
            if LocalPlayer:GetAttribute("GameReady") == true and PlayerGui:FindFirstChild("GameGui") then break end
            task.wait(0.25)
        end
        task.wait(0.5) -- beri waktu modul client selesai ter-require
    end
    Shared = ReplicatedStorage:FindFirstChild("Shared") or ReplicatedStorage
    GameGui = PlayerGui:FindFirstChild("GameGui")
    Session.Modules = {}
    local indexed, seen, loaded = {}, {}, {}
    local function isModule(object)
        local ok, yes = pcall(function() return object:IsA("ModuleScript") end)
        return ok and yes
    end
    local function add(object)
        if isModule(object) and not seen[object] then
            seen[object] = true
            indexed[#indexed + 1] = object
        end
    end
    local function refreshIndex()
        indexed, seen, loaded = {}, {}, {}
        for _, root in ipairs({ ReplicatedStorage, PlayerGui, LocalPlayer:FindFirstChild("PlayerScripts") or false }) do
            if root then
                local ok, descendants = pcall(root.GetDescendants, root)
                if ok and type(descendants) == "table" then for _, object in pairs(descendants) do add(object) end end
            end
        end
        local used = {}
        for _, api in ipairs({ getloadedmodules or false, getmodules or false }) do
            if type(api) == "function" and not used[api] then
                used[api] = true
                local ok, objects = pcall(api)
                if ok and type(objects) == "table" then
                    for key, value in pairs(objects) do
                        local object = isModule(value) and value or key
                        add(object)
                        if api == getloadedmodules and isModule(object) then loaded[object] = true end
                    end
                end
            end
        end
    end
    local function findModule(parent, name)
        if parent then
            local direct = parent:FindFirstChild(name)
            if isModule(direct) then return direct end
            local found
            for _, child in ipairs(parent:GetDescendants()) do
                if child.Name == name and isModule(child) then
                    if found then return nil, "lebih dari satu modul bernama " .. name .. " di " .. parent:GetFullName() end
                    found = child
                end
            end
            if found then return found end
        end
        local found
        for _, object in ipairs(indexed) do
            if object.Name == name then
                if found then return nil, "lebih dari satu modul bernama " .. name .. " dalam daftar client" end
                found = object
            end
        end
        return found
    end
    refreshIndex()
    local function report()
        local folders, names = {}, {}
        for _, child in ipairs(ReplicatedStorage:GetChildren()) do
            folders[#folders + 1] = child.Name .. ":" .. child.ClassName
        end
        for _, object in ipairs(indexed) do names[#names + 1] = object.Name end
        table.sort(folders)
        table.sort(names)
        return ("Place=%s | Version=%s | ReplicatedStorage=%s | Modules=%d [%s] | loadedmodules=%s | getmodules=%s"):format(
            tostring(game.PlaceId), tostring(game.PlaceVersion), table.concat(folders, ", "):sub(1, 900),
            #indexed, table.concat(names, ", "):sub(1, 1400), type(getloadedmodules), type(getmodules))
    end
    local moduleDeadline = os.clock() + 30
    local structuralNames = { "ItemDB", "Inventory", "Net", "WorldMenu", "Roles", "Sfx" }
    local runtimeMatches, exportMatches, triedModules = {}, {}, {}
    local lastGC, runtimeComplete, exportsComplete = -math.huge, false, false
    Session.ModuleScan = { Tables = 0, Loaded = 0, Errors = 0 }
    local function functions(value, names)
        for _, name in ipairs(names) do if type(rawget(value, name)) ~= "function" then return false end end
        return true
    end
    local function isItemDatabase(value)
        local checked, entries, named, metadata, seeds, solids = 0, 0, 0, 0, 0, 0
        for id, item in pairs(value) do
            checked += 1
            if type(id) == "number" and id >= 0 and id % 1 == 0 then
                entries += 1
                if type(item) == "table" and type(rawget(item, "name")) == "string" and rawget(item, "name") ~= "" then
                    named += 1
                    if type(rawget(item, "hits")) == "number" or type(rawget(item, "solid")) == "boolean" or rawget(item, "kind") == "seed" then metadata += 1 end
                    if rawget(item, "kind") == "seed" then seeds += 1 end
                    if rawget(item, "solid") == true then solids += 1 end
                end
            end
            if checked >= 160 or entries >= 64 then break end
        end
        return entries >= 12 and named / entries >= 0.85 and metadata >= 8 and (seeds > 0 or solids >= 4)
    end
    local function matches(name, value)
        if type(value) ~= "table" then return false end
        if name == "ItemDB" then return isItemDatabase(value) end
        if name == "Inventory" then
            return rawget(value, "capacity") == nil and functions(value, { "new", "add", "remove", "count", "used", "room", "select" })
        end
        if name == "Net" then
            return functions(value, { "call", "on", "worldTag" }) and type(rawget(value, "CALLS")) == "table"
                and type(rawget(value, "EVENTS")) == "table" and type(rawget(value, "punch")) == "table"
                and type(rawget(rawget(value, "punch"), "send")) == "function"
        end
        if name == "WorldMenu" then
            return functions(value, { "mount", "isDown" }) and type(rawget(value, "SKINS")) == "table"
                and type(rawget(value, "KEYS")) == "table" and type(rawget(value, "DEFAULT_SKIN")) == "number"
        end
        if name == "Roles" then return functions(value, { "isDeveloper", "isModerator", "isUndercover" }) end
        if name == "Sfx" then return functions(value, { "play", "playAt", "loop" }) end
        return false
    end
    local function rememberMatch(target, name, value, object)
        local previous = target[name]
        if not previous then
            target[name] = { Value = value, Object = object, Candidates = { { Value = value, Object = object } } }
        elseif not rawequal(previous.Value, value) then
            previous.Ambiguous = true
            for _, candidate in ipairs(previous.Candidates) do if rawequal(candidate.Value, value) then return end end
            if #previous.Candidates < 16 then previous.Candidates[#previous.Candidates + 1] = { Value = value, Object = object }
            else previous.Truncated = true end
        end
    end
    local function definitionEquals(a, b, visited, work, depth)
        if rawequal(a, b) then return true end
        if type(a) ~= "table" or type(b) ~= "table" or depth > 12 then return false end
        local paired = visited[a]
        if paired and paired[b] then return true end
        if not paired then paired = {}; visited[a] = paired end
        paired[b] = true
        for key, value in pairs(a) do
            work[1] += 1
            if work[1] > 200000 or not definitionEquals(value, rawget(b, key), visited, work, depth + 1) then return false end
        end
        for key in pairs(b) do if rawget(a, key) == nil then return false end end
        return true
    end
    local function containsDatabase(a, b)
        local visited, work, checked = {}, { 0 }, 0
        for id, definition in pairs(b) do
            if type(id) == "number" and id >= 0 and id % 1 == 0 then
                if not definitionEquals(rawget(a, id), definition, visited, work, 0) then return false end
                checked += 1
                if checked % 512 == 0 then
                    if not alive() or os.clock() >= moduleDeadline then return false end
                    task.wait()
                end
            end
        end
        return true
    end
    local function resolveDatabase(match)
        if match.Truncated then return nil end
        -- Pilih hanya jika semua definisi kandidat lain tercakup dan identik.
        -- Salinan tabel dan daftar subset yang koheren tidak dianggap konflik ID.
        for _, candidate in ipairs(match.Candidates) do
            local coherent = true
            for _, other in ipairs(match.Candidates) do
                if not containsDatabase(candidate.Value, other.Value) then coherent = false break end
            end
            if coherent then return candidate end
        end
    end
    local function readUpvalues(fn)
        for _, api in ipairs({ (debug and debug.getupvalues) or false, getupvalues or false }) do
            if type(api) == "function" then
                local ok, values = pcall(api, fn)
                if ok and type(values) == "table" and next(values) then return values end
            end
        end
        for _, api in ipairs({ (debug and debug.getupvalue) or false, getupvalue or false }) do
            if type(api) == "function" then
                local values = {}
                for index = 1, 80 do
                    local ok, first, second = pcall(api, fn, index)
                    if not ok then break end
                    if second ~= nil then values[index] = second else values[index] = first end
                end
                if next(values) then return values end
            end
        end
        return {}
    end
    local function actionFunction(fn)
        if fn == actionFunction then return false end
        for _, api in ipairs({ (debug and debug.getconstants) or false, getconstants or false }) do
            if type(api) == "function" then
                local ok, values = pcall(api, fn)
                if ok and type(values) == "table" then
                    local tile, placed, flips, vending, crack = false, false, false, false, false
                    for _, value in pairs(values) do
                        if value == "tile" or value == "SetTile" then tile = true
                        elseif value == "placedAt" then placed = true
                        elseif value == "flips" then flips = true
                        elseif value == "newCrack" or value == "HarvestProvider" then crack = true
                        elseif type(value) == "string" and value:lower():find("empty", 1, true) and value:lower():find("vending", 1, true) then vending = true end
                    end
                    if (tile and placed and flips) or (vending and crack) then return true end
                end
            end
        end
        return false
    end
    local bindingTried, boundDatabase = false, nil
    local function databaseFromActions()
        if bindingTried then return boundDatabase end
        bindingTried = true
        if type(getconnections) ~= "function" then return nil end
        local queue, seen, results = {}, {}, {}
        local function push(value)
            if (type(value) == "function" or type(value) == "table") and not seen[value] then
                seen[value] = true
                queue[#queue + 1] = value
            end
        end
        local function inspectAction(fn, depth, visited)
            if depth > 3 or visited[fn] then return end
            visited[fn] = true
            for _, value in pairs(readUpvalues(fn)) do
                if type(value) == "table" then
                    local ok, yes = pcall(isItemDatabase, value)
                    if ok and yes then rememberMatch(results, "ItemDB", value) end
                elseif type(value) == "function" then inspectAction(value, depth + 1, visited) end
            end
        end
        for _, entry in ipairs({ { RunService, { "RenderStepped", "Heartbeat", "PreRender", "Stepped" } },
            { UserInputService, { "InputBegan", "InputEnded", "TouchTap" } } }) do
            for _, name in ipairs(entry[2]) do
                local ok, signal = pcall(function() return entry[1][name] end)
                if ok and signal then
                    local got, connections = pcall(getconnections, signal)
                    if got and type(connections) == "table" then
                        for _, connection in pairs(connections) do
                            local read, fn = pcall(Session.connectionFunction, connection)
                            if read then push(fn) end
                        end
                    end
                end
            end
        end
        local index = 1
        while index <= #queue and index <= 900 and alive() and os.clock() < moduleDeadline do
            local value = queue[index]
            index += 1
            if type(value) == "function" then
                if actionFunction(value) then inspectAction(value, 0, {}) end
                for _, upvalue in pairs(readUpvalues(value)) do push(upvalue) end
            elseif not isItemDatabase(value) then
                for _, member in pairs(value) do if type(member) == "function" then push(member) end end
            end
            if index % 100 == 0 then task.wait() end
        end
        local found = results.ItemDB
        if found then
            local resolved = not found.Ambiguous and found or resolveDatabase(found)
            if resolved then
                boundDatabase = resolved.Value
                Session.ModuleScan.DatabaseResolution = "upvalue fungsi punch/place pada koneksi game aktif"
            end
        end
        return boundDatabase
    end
    local function inspectValue(target, value, object)
        if type(value) ~= "table" then return end
        for _, name in ipairs(structuralNames) do
            local ok, yes = pcall(matches, name, value)
            if ok and yes then rememberMatch(target, name, value, object) end
        end
    end
    local filteredMatches, filteredTried = {}, false
    local function scanFiltered()
        if filteredTried then return end
        filteredTried = true
        Session.ModuleScan.FilterAt = os.clock()
        local api = filtergc or filter_gc
        if type(api) ~= "function" then return end
        -- Filter native Arceus menghindari menyalin seluruh heap ke tabel Lua.
        -- Hasil tetap divalidasi dan konflik database tetap diperiksa.
        local filters = {
            ItemDB = { 2, 4 }, Inventory = { "new", "add", "remove", "count", "used", "room", "select" },
            Net = { "call", "on", "worldTag", "CALLS", "EVENTS", "punch" },
            WorldMenu = { "mount", "isDown", "SKINS", "KEYS", "DEFAULT_SKIN" },
            Roles = { "isDeveloper", "isModerator", "isUndercover" }, Sfx = { "play", "playAt", "loop" },
        }
        for _, name in ipairs(structuralNames) do
            if not alive() or os.clock() >= moduleDeadline then break end
            local ok, values = pcall(api, "table", { Keys = filters[name] }, false)
            if ok and type(values) == "table" then
                for _, value in pairs(values) do
                    local valid, yes = pcall(matches, name, value)
                    if valid and yes then rememberMatch(filteredMatches, name, value) end
                end
            else Session.ModuleScan.FilterError = tostring(values):sub(1, 160) end
            task.wait()
        end
        Session.ModuleScan.NativeFiltered = true
    end
    local function scanRuntime(retry)
        if runtimeComplete and not retry then return end
        if os.clock() - lastGC < 3 or type(getgc) ~= "function" then return end
        lastGC = os.clock()
        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then ok, objects = pcall(getgc) end
        if not ok or type(objects) ~= "table" then return end
        runtimeMatches = {}
        runtimeComplete = true
        local visited = 0
        for _, value in pairs(objects) do
            if not alive() or os.clock() >= moduleDeadline then runtimeComplete = false break end
            if type(value) == "table" then
                Session.ModuleScan.Tables += 1
                inspectValue(runtimeMatches, value)
            end
            visited += 1
            if visited % 1000 == 0 then task.wait() end
        end
        lastGC = os.clock()
    end
    local function clientModule(object)
        -- Jangan membaca export module CoreGui/engine atau menjalankan modul yang belum dimuat.
        local parent = object
        for _ = 1, 40 do
            if parent == ReplicatedStorage or parent == PlayerGui then return true end
            if not parent then break end
            parent = parent.Parent
        end
        return false
    end
    local function scanLoaded()
        exportsComplete = true
        for object in pairs(loaded) do
            if not alive() or os.clock() >= moduleDeadline then exportsComplete = false break end
            if not triedModules[object] and clientModule(object) then
                triedModules[object] = true
                Session.InitStep = "membaca export client " .. object:GetFullName()
                local done, ok, value = false, false, nil
                local worker = task.spawn(function()
                    ok, value = pcall(require, object)
                    done = true
                end)
                local untilTime = math.min(moduleDeadline, os.clock() + 1)
                while alive() and not done and os.clock() < untilTime do task.wait(0.05) end
                if done and ok then
                    Session.ModuleScan.Loaded += 1
                    inspectValue(exportMatches, value, object)
                else
                    Session.ModuleScan.Errors += 1
                    Session.ModuleScan.LastError = object:GetFullName() .. ": " .. (done and tostring(value):sub(1, 180) or "batas waktu membaca export")
                    if not done and task.cancel and worker then pcall(task.cancel, worker) end
                end
                task.wait()
            end
        end
    end
    local function structuralModule(name, retry)
        if not table.find(structuralNames, name) then return nil end
        -- filtergc hanya dipindai sekali pada versi lama. Saat retry, izinkan
        -- pemindaian ulang berkala agar modul yang terlambat muncul bisa ditemukan.
        if retry and os.clock() - (Session.ModuleScan.FilterAt or 0) > 3 then
            filteredTried, filteredMatches = false, {}
        end
        scanFiltered()
        local filtered = filteredMatches[name]
        if filtered then
            if not filtered.Ambiguous then return filtered.Value end
            if name == "ItemDB" then
                local resolved = resolveDatabase(filtered)
                if resolved then return resolved.Value end
                local bound = databaseFromActions()
                if bound then return bound end
            end
        end
        scanRuntime(retry)
        local found = runtimeMatches[name]
        if runtimeComplete and found and not found.Ambiguous then return found.Value, found.Object end
        if runtimeComplete and found and name == "ItemDB" then
            local resolved = resolveDatabase(found)
            if resolved then
                Session.ModuleScan.DatabaseResolution = "definisi identik/tercakup, kandidat=" .. #found.Candidates
                return resolved.Value, resolved.Object
            end
        end
        if name == "ItemDB" then
            local value = databaseFromActions()
            if value then return value end
        end
        scanLoaded()
        found = exportMatches[name]
        if exportsComplete and found then
            if found.Ambiguous and name == "ItemDB" then
                local resolved = resolveDatabase(found)
                if resolved then return resolved.Value, resolved.Object end
            end
            if found.Ambiguous then return nil, nil, "beberapa export cocok dengan bentuk " .. name end
            return found.Value, found.Object
        end
        if runtimeMatches[name] and runtimeMatches[name].Ambiguous then return nil, nil, "beberapa tabel runtime cocok dengan bentuk " .. name end
    end
    local function loadModule(parent, name, required)
        Session.InitStep = "mencari modul " .. name
        local object, reason = findModule(parent, name)
        local value, shapedObject
        if not object and not reason then value, shapedObject, reason = structuralModule(name) end
        while not object and not reason and required and alive() and os.clock() < moduleDeadline do
            if value then break end
            -- Satu batas waktu bersama; tidak menunggu folder Shared yang bisa sudah dipindah.
            if parent then parent:WaitForChild(name, math.min(1, moduleDeadline - os.clock()))
            else task.wait(0.25) end
            task.wait(0.1) -- child bernama sama bisa berupa Folder; jangan melakukan busy loop
            refreshIndex()
            object, reason = findModule(parent, name)
            if not object and not reason then value, shapedObject, reason = structuralModule(name, true) end
        end
        if value then
            Session.Modules[name] = shapedObject and shapedObject:GetFullName() or "runtime:" .. name
            print("[n4th] " .. name .. " dikenali dari data: " .. Session.Modules[name])
            return true, value, shapedObject
        end
        if object then
            Session.InitStep = "memuat " .. object:GetFullName()
            local ok, result = pcall(require, object)
            if ok and type(result) == "table" then
                Session.Modules[name] = object:GetFullName()
                return true, result, object
            end
            reason = ok and "hasil require bukan tabel" or tostring(result)
        end
        local message = "[n4th] Modul " .. name .. ": " .. (reason or (required and "tidak ditemukan setelah pencarian 30 detik" or "tidak ditemukan"))
        if required then
            Session.BootstrapReport = report()
            warn("[n4th] Struktur client: " .. Session.BootstrapReport)
            warn(("[n4th] Pemindaian data: tabel=%d | export=%d | gagal=%d | terakhir=%s"):format(
                Session.ModuleScan.Tables, Session.ModuleScan.Loaded, Session.ModuleScan.Errors, tostring(Session.ModuleScan.LastError)))
            error(message .. ". Jalankan n4th-diagnose.lua untuk membaca struktur client terbaru.", 0)
        end
        warn(message .. " (opsional, lanjut memuat menu)")
        return false, nil
    end
    function Session.findModule(name, parent)
        refreshIndex()
        return findModule(parent or Shared, name)
    end
    WorldRemotes = ReplicatedStorage:FindFirstChild("WorldRemotes")
    SetTileRemote = WorldRemotes and WorldRemotes:FindFirstChild("SetTile")
    -- FIX: ItemDB gagal ditemukan tidak lagi mematikan seluruh script (menu tetap muncul).
    local okDB, _, itemDB, itemModule = pcall(loadModule, Shared, "ItemDB", true)
    if okDB and type(itemDB) == "table" then
        ItemDB = itemDB
    else
        Session.ItemDBMissing = true
        warn("[n4th] ItemDB TIDAK ketemu (" .. tostring(_) .. "). Menu tetap dibuka, tapi fitur farming belum akan jalan. Tutup game, masuk lagi sampai benar-benar di dalam world, lalu execute ulang.")
        ItemDB = {}
    end
    -- Modul yang terpisah folder tetap bisa dicari melalui indeks client.
    Shared = (itemModule and itemModule.Parent) or Shared
    local _, inventory = loadModule(Shared, "Inventory", false)
    InventoryModule = inventory
    NetOk, Net = loadModule(Shared, "Net", false)
    ParticlesOk, ParticlesModule = loadModule(GameGui, "Particles", false)
    local menuObject
    MenuModOk, MenuModule, menuObject = loadModule(GameGui, "WorldMenu", false)
    if not GameGui and menuObject then GameGui = menuObject.Parent end
    RolesOk, RolesModule = loadModule(Shared, "Roles", false)
    SfxOk, SfxModule = loadModule(Shared, "Sfx", false)
    Session.InitStep = "modul game siap"
end

-- Metadata item bersifat tetap selama satu sesi. Salin hanya ID yang dipakai;
-- membaca tabel lintas VM untuk setiap tile jauh lebih mahal daripada cache lokal.
do
    Session.ItemDBSource = ItemDB
    ItemDB = setmetatable({}, { __index = function(cache, id)
        local source = Session.ItemDBSource
        if type(source) ~= "table" then return nil end
        local item = source[id]
        if type(item) ~= "table" then return item end
        local copy = {}
        for key, value in pairs(item) do copy[key] = value end
        rawset(cache, id, copy)
        return copy
    end })
end

Session.InitStep = "WindUI"
local WindUI
do
    -- File tag ini identik dengan release 1.6.66, tanpa redirect unduhan GitHub.
    local urls = {
        "https://raw.githubusercontent.com/Footagesus/WindUI/1.6.66/dist/main.lua",
        "https://github.com/Footagesus/WindUI/releases/download/1.6.66/main.lua",
    }

    local function downloadWindUI()
        local lastError = "respons kosong"
        for attempt = 1, 2 do
            for _, url in ipairs(urls) do
                local ok, source = pcall(Session.download, url)
                if not ok then
                    lastError = tostring(source)
                elseif type(source) ~= "string" or source:match("^%s*$") then
                    lastError = "respons kosong"
                elseif source:match("^%s*<") then
                    lastError = "server mengirim HTML, bukan Lua (mungkin 504 Gateway Time-out)"
                else
                    local compiled, fn, compileError = pcall(loadstring, source, "WindUI")
                    if compiled and type(fn) == "function" then return fn end
                    lastError = tostring(compiled and compileError or fn)
                end
                warn("[n4th] Unduh WindUI gagal: " .. url .. " | " .. lastError)
            end
            if attempt < 2 then task.wait(1) end
        end
        error("[n4th] WindUI gagal diunduh setelah mencoba kedua URL: " .. lastError, 0)
    end

    -- Inisialisasi hanya sekali, setelah respons berhasil dikompilasi.
    WindUI = downloadWindUI()()
end
Session.InitStep = "config dan referensi game"

---------------------------------------------------------------------
-- PENGATURAN & DATA
---------------------------------------------------------------------
local State = {
    Running = false,
    Mode = "Place + Break",       -- "Place + Break" | "Break saja" | "Place saja"
    PlaceMs = 250,                -- jeda setelah tiap place
    BreakMs = 220,                -- jeda tiap pukulan (normal 220)
    AfterBreakMs = 250,           -- jeda setelah block hancur
    HitsOverride = 0,             -- jumlah pukulan manual (0 = otomatis)
    BreakBackground = true,       -- selalu ikut pecah background (tanpa tombol)
    MultiTarget = 1,              -- jumlah tile dipukul bergantian (1 = biasa)
    SelectedId = nil,
    WorldBreakId = nil,           -- satu jenis block foreground dari world aktif
    WorldBreakCollect = false,    -- terpisah dari opsi collect Auto Farm / Clear World
    Offsets = {},                 -- tile yang dipilih di Grid
    CalibX = 0,
    CalibY = 0,
    AntiAfk = true,
    FastPunch = false,            -- 4x hit cepat saat pukul MANUAL (bukan Auto Farm)
    FastPunchHits = 12,
    FastPunchMs = 190,
    MutePunch = true,
    Visual = true,                -- animasi tangan saat break / place / tanam / panen (tampilan saja)
    LiteMode = false,
    AutoCollect = true,           -- ambil drop di tile yang dipilih
    CollectAround = false,        -- ambil drop di sekitar karakter (radius) kapan saja
    CollectRadius = 3,            -- jari-jari collect (tile), dipakai mode Remote
    CollectMode = "Sentuhan",     -- "Sentuhan" (badan, seperti main manual) / "Remote" (ambil dari jauh, cara lama)
    Override = nil,               -- Pabrik memakai tile & block sendiri
    Quiet = false,                -- tanpa notifikasi (dipakai Pabrik)
    Cycles = 0,
    Placed = 0,
    Broken = 0,
    Collected = 0,                -- jumlah drop yang diambil
    CollectFail = 0,              -- jumlah drop yang ditolak server
    LastAction = "-",
    SeedDrop = false,             -- seed hasil break sudah banyak -> drop ke titik drop
    SeedDropAt = 190,             -- drop kalau seed sudah sebanyak ini
    SeedKeep = 0,                 -- seed yang disisakan
    Dropped = 0,
    DropPause = false,            -- Auto Farm dijeda sementara (sedang pergi drop)
}

local Misc = {
    Speed = 100,      -- walkspeed % (100 = normal)
    InfJump = false,
    Ghost = false,    -- fly + tembus block
    UpHeld = false,   -- tombol ▲ di layar ditahan
    DownHeld = false, -- tombol ▼ di layar ditahan
    CustomName = true,          -- watermark nama (selalu aktif, mati hanya saat script ditutup)
    NameText = "n4th",  -- teks watermark
}

-- Auto Clear World
local Clear = {
    Why = { izin = 0, jurang = 0, nopath = 0, batas = 0, gagal = 0 }, -- DEBUG: alasan tile dilewati
    Learned = {},             -- id tile yang terbukti jadi lantai (karakter berdiri di atasnya)
    Dbg = "-",                -- DEBUG: info A* terakhir
    Running = false,
    IncludeBg = true,         -- ikut pecah background
    UseBlock = true,          -- taruh block kalau tidak ada pijakan
    ScaffoldId = nil,         -- block yang dipakai untuk pijakan
    Collect = true,           -- ambil drop tiap habis pecah
    Sweep = "Kiri → Kanan",   -- "Kiri → Kanan" atau "Zig-zag"
    Skip = {},                -- tile yang dilewati sementara
    TopRow = -1,              -- baris yang sedang dibersihkan
    DirRow = nil,             -- arah zig-zag untuk baris ini
    Dir = nil,
    Broken = 0,
    Remaining = -1,
    Status = "-",
}

-- Lahan (farm world): baris block dari atas ke bawah
local Land = {
    X0 = 0, X1 = 99,  -- kolom awal & akhir
    Y0 = 2,           -- baris block paling atas
    Gap = 2,          -- jarak antar baris (2 = ada 1 tile kosong untuk pohon)
    Rows = 10,        -- jumlah baris
    Stairs = true,    -- ujung baris dibuka bergantian kiri/kanan (jalan naik-turun seperti tangga)
}

-- Bangun Lahan
local Build = {
    Running = false,
    BlockId = nil,
    UseBlock = true,     -- boleh taruh block pijakan kalau baris pertama tidak terjangkau
    Produce = true,      -- block kurang -> produksi dulu (tanam & panen) sampai cukup
    ThenPabrik = false,  -- selesai -> langsung jalankan Pabrik
    Placed = 0,
    Phase = "-",
    Status = "-",
    Skip = {},
    FieldSkip = {},      -- tile panen / tanam yang dilewati sementara (produksi block)
    Row = {},            -- baris tanam produksi yang sedang dikerjakan
    Harvested = 0,
    Planted = 0,
    Dug = 0,             -- tile yang digali (block + background)
    Carved = {},         -- [idx] = true: block-nya digali Bangun Lahan (background ikut dipecah)
    Surface = nil,       -- y permukaan tanah asli (di bawahnya background ikut dipecah)
    Under = {},          -- [baris] = waktu: sementara pasang dari bawah (tidak bisa naik ke baris itu)
    BreakTimes = {},     -- tile yang terus balik lagi setelah digali
    Reserve = 0,         -- block yang tidak boleh dipasang (disisakan untuk bikin seed)
    RESERVE = 10,        -- sisakan block segini saat produksi
    BreakX = -1, BreakY = -1, -- posisi break produksi (belum diatur = otomatis di ujung kanan baris)
    Tiles = {},          -- tile break produksi, relatif ke posisi break ("dx,dy") (Grid mode Lahan)
}

-- Pabrik: break block -> tanam seed -> panen -> break lagi, seed lebihan di-drop
local Pabrik = {
    Running = false,
    SeedId = nil,
    BlockId = nil,
    WholeWorld = false,  -- tanam & panen di seluruh world (bukan hanya lahan)
    Tiles = {},          -- tile break, relatif ke posisi break ("dx,dy")
    BreakX = -1, BreakY = -1,
    BreakSec = 60,       -- lama 1 sesi break sebelum cek pohon lagi
    Drop = true,
    Keep = 50,           -- seed yang disisakan untuk ditanam lagi
    DropAt = 200,        -- drop kalau seed sudah sebanyak ini
    DropWorld = "",      -- "" = world ini | "WORLD" | "WORLD:ID"
    DropX = -1, DropY = -1,
    Harvested = 0,
    Planted = 0,
    Dropped = 0,
    Skip = {},
    Status = "-",
    Traveling = false,
    Home = "",
    Zone = nil,          -- tempat drop (tidak ikut di-collect), dipakai semua fitur drop
    Row = {},            -- baris tanam yang sedang dikerjakan
}

local AutoDrop = {
    On = false,
    Busy = false,
    Cancelled = false,
    Dropped = 0,
    Status = "Mati",
    Zones = {},
}

-- Auto Route Drop: susuri drop item di atas platform, lalu drop tiap 200 item.
local RouteDrop = {
    Running = false,
    TargetId = nil,
    PlatformId = nil,
    DropX = -1,
    DropY = -1,
    Direction = "Kiri → Kanan",
    Status = "Mati",
    CollectedStops = 0,
    Dropped = 0,
    Skip = {},
    CurrentRow = nil, -- baris pijakan yang sedang disapu, dari atas ke bawah
    World = nil,
}

-- Log diagnostik Auto Route Drop. Riwayat dibatasi agar tidak membebani game.
RouteDrop.Logs = {}
RouteDrop.LastLog = nil
RouteDrop.LastStatusLog = nil
local function routeDropLog(message, force)
    message = tostring(message or "-")
    if not force and RouteDrop.LastLog == message then return end
    RouteDrop.LastLog = message
    local stamp = os.date("%H:%M:%S")
    local line = ("[%s] %s"):format(stamp, message)
    table.insert(RouteDrop.Logs, line)
    while #RouteDrop.Logs > 150 do table.remove(RouteDrop.Logs, 1) end
    print("[n4th][RouteDrop] " .. line)
end

local function routeDropCopyLogs()
    local clip = setclipboard or toclipboard or (syn and syn.write_clipboard)
    local payload = table.concat(RouteDrop.Logs, "\\n")
    if payload == "" then payload = "[n4th][RouteDrop] Belum ada log." end
    if type(clip) ~= "function" then
        return false, "Fungsi clipboard tidak tersedia di executor ini. Log tetap ada di F9."
    end
    local ok, err = pcall(clip, payload)
    if not ok then return false, "Gagal menyalin log: " .. tostring(err) end
    return true, "Log berhasil disalin (" .. tostring(#RouteDrop.Logs) .. " baris)."
end


local Guard = {
    On = false,
    Who = "Staff (Mod/Dev)",   -- "Staff (Mod/Dev)" | "Semua pemain"
    StopAll = true,            -- diam semua aktivitas
    Leave = false,             -- keluar world
    AutoBack = true,           -- lanjut lagi setelah aman
    BackSec = 60,              -- (keluar world) tunggu sebelum masuk lagi
    CalmSec = 5,               -- (diam) tunggu sepi dulu sebelum lanjut
    Mode = "idle",             -- idle | pause | away | out | back
    Allow = {},                -- pemain biasa yang sudah ada saat Penjaga dinyalakan (diabaikan)
    Alerted = {},              -- sudah diberi peringatan
    Saved = nil,               -- aktivitas sebelum dihentikan
    Token = 0,
    BackAt = 0,
    CalmAt = nil,
    LeftFg = nil,
    BackText = nil,
    Status = "Mati",
    Detected = 0,
}

-- Farmer: panen & tanam otomatis
local Farmer = {
    Running = false,
    Harvest = true,
    Plant = true,
    Collect = true,
    UseBlock = false,   -- taruh block kalau tidak ada jalan
    ScaffoldId = nil,
    HarvestMs = 250,    -- jeda setelah tiap panen
    PlantMs = 250,      -- jeda setelah tiap tanam
    SeedId = nil,
    Focus = nil,        -- id seed yang difokuskan saat panen (nil = semua seed); dipilih di tab Auto Drop
    Tractor = false,    -- Mode Tractor: hanya jalan ke pohon siap (tanpa pukul / tanam); tractor yang memanen
    Skip = {},
    Harvested = 0,
    Planted = 0,
    Status = "-",
    Drop = false,       -- inventori hampir penuh -> drop hasil panen ke titik drop
    DropAt = 190,       -- drop kalau item hasil panen sudah sebanyak ini
    Keep = 50,          -- seed tanam yang disisakan
    Dropped = 0,
    Got = {},           -- seed pohon yang pernah dipanen (untuk cari item hasil panen)
    Row = {},           -- baris tanam yang sedang dikerjakan (tanam rapi per baris)
}

-- Tombol gerak buatan (dipakai Clear & Farmer)
local AutoInput = { active = false, left = false, right = false, jump = false, down = false }

local Refs = {
    World = nil,      -- data world (fg, bg, ukuran)
    Inv = nil,        -- inventori
    SetTile = nil,    -- fungsi place game
    State = nil,      -- posisi karakter
    Punch = nil,      -- fungsi pukul game
    Particles = {},   -- particle (untuk mode Lite)
    Menu = nil,       -- menu game (keluar / masuk world)
    Gems = nil,       -- update angka gems
    Hud = nil,        -- jangkauan pukul & place
    Trees = nil,      -- data pohon (waktu tanam)
    Others = nil,     -- daftar pemain lain di world (untuk Penjaga)
}
Session.References = Refs

-- Daftar drop di world (diambil dari game)
local Drops = { list = nil, update = nil, brokeAt = {} }
-- Animasi aksi: fungsi gambar tangan game + nomor upvalue "aksi terakhir" (diisi saat hubungkan)
local Anim = { fn = nil, idx = nil, set = nil }
local DropFailUntil = {}   -- drop yang ditolak, dicoba lagi nanti

local UI = { Tabs = {}, DropdownTabs = {}, PendingDropdowns = {} }
function UI.tabVisible(title)
    if not UI.Window then return true end
    if UI.Window.Closed then return false end
    local tab = title and UI.Tabs[title]
    return not title or (tab and tab.Selected == true) or false
end

-- Jalankan fn dengan izin penuh. Hasil: ok, err (seperti pcall)
function UI.ident()
    local getId = getthreadidentity or get_thread_identity or getidentity or (syn and syn.get_thread_identity)
    if type(getId) ~= "function" then return nil end
    local ok, v = pcall(getId)
    return ok and v or nil
end
function UI.exec(fn)
    local setId = setthreadidentity or set_thread_identity or setidentity or (syn and syn.set_thread_identity)
    local function elevate()
        if Session.Ident and type(setId) == "function" then pcall(setId, Session.Ident) end
    end
    local err1 = nil
    local co = Session.Exec
    if co and coroutine.status(co) == "suspended" then
        local okR, ok, err = coroutine.resume(co, function()
            elevate()
            fn()
        end)
        if okR and ok ~= false then return true end
        err1 = okR and err or ok
    end
    -- cadangan: jalankan di thread ini (setelah identitasnya dikembalikan)
    elevate()
    local ok2, err2 = pcall(fn)
    if ok2 then return true end
    return false, tostring(err2 or err1)
end
UI.Jobs = {}
function UI.later(key, fn, delay)
    UI.Jobs[key] = { fn = fn, at = os.clock() + (delay or 0) }
end
-- Jalankan pekerjaan UI yang sudah waktunya (dipanggil oleh thread INIT, lihat bagian INIT)
function UI.runJobs()
    if UI.flushInventory then UI.flushInventory() end
    local now = os.clock()
    local due = {}
    for key, job in pairs(UI.Jobs) do
        if now >= job.at then due[#due + 1] = key end
    end
    for _, key in ipairs(due) do
        local job = UI.Jobs[key]
        if job and now >= job.at then
            UI.Jobs[key] = nil
            local ok, err = pcall(job.fn)
            if not ok then warn("[n4th] UI job " .. tostring(key) .. ": " .. tostring(err)) end
        end
    end
end
local Connections = {}
local HitCount = {}   -- hitung pukulan (cadangan)
local PlacedAt = {}   -- kapan tile di-place

---------------------------------------------------------------------
-- BAHASA (Indonesia / English)
---------------------------------------------------------------------
-- Cara kerja:
--   - Semua teks script ditulis dalam Bahasa Indonesia.
--   - Kalau English dipilih, I18N.T(teks) menerjemahkan:
--       1. teks utuh (judul & deskripsi menu) dari daftar EN
--       2. teks yang berubah-ubah (status, notifikasi) per frasa dari daftar PH
--   - Menu WindUI dibungkus (I18N.wrap) supaya judul, deskripsi & isi status ikut diterjemahkan.
local I18N = { Lang = "id", Saved = "id", Ask = false, Chosen = false }

do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local

I18N.EN = {
    -- grup sidebar & tab
    ["Fitur"] = "Features", ["Keamanan"] = "Security", ["Setelan"] = "Setup",
    ["Pengaturan"] = "Settings", ["Penjaga"] = "Guard", ["Statistik"] = "Stats", ["Tas"] = "Bag",
    ["Lahan"] = "Land", ["Pabrik"] = "Factory", ["Koneksi"] = "Connection",
    -- kotak
    ["Kontrol"] = "Controls", ["Mode & Kecepatan"] = "Mode & Speed", ["Kecepatan"] = "Speed",
    ["Karakter"] = "Character", ["Opsi"] = "Options", ["Pesan"] = "Messages",
    ["Aksi saat terdeteksi"] = "Action when detected", ["Waktu"] = "Timing", ["Lainnya"] = "Other",
    ["Quest Harian"] = "Daily Quests", ["Pohon (siap panen)"] = "Trees (ready to harvest)",
    ["Auto Recycle (buang item)"] = "Auto Recycle (trash items)", ["Bentuk lahan"] = "Land shape",
    ["Pilihan"] = "Options", ["Posisi & tile break"] = "Break position & tiles",
    ["Koreksi posisi"] = "Position correction", ["Yang dikirim"] = "What to send",
    -- Farm
    ["Bisa juga lewat tombol START di Grid"] = "Can also use the START button in the Grid",
    ["Ambil drop di tile yang dipilih"] = "Pick up drops on the selected tiles",
    ["Collect di sekitar karakter"] = "Collect around character",
    ["Ambil semua drop dalam radius, kapan saja"] = "Pick up all drops within the radius, anytime",
    ["Radius collect (tile)"] = "Collect radius (tiles)",
    ["Dipakai juga Clear, Farmer, Splice & Pabrik. Terlalu jauh bisa ditolak server"] =
        "Also used by Clear, Farmer, Splice & Factory. Too far may be rejected by the server",
    ["Buka Grid Tile"] = "Open Tile Grid",
    ["Ambil drop otomatis"] = "Auto collect drops",
    ["Khusus Auto Break Block. Mati = tidak mengejar drop; item yang tersentuh tetap bisa terambil oleh game."] =
        "Auto Break Block only. Off stops chasing drops; the game can still collect items you touch.",
    ["Kotak 5x5, tengah = karakter"] = "5x5 grid, center = character",
    -- Clear
    ["Status Clear"] = "Clear Status",
    ["Bersihkan dari baris atas ke bawah"] = "Clear from the top row down",
    ["Arah sapu"] = "Sweep direction",
    ["Zig-zag lebih cepat (tidak balik ke kiri)"] = "Zig-zag is faster (no going back left)",
    ["Pakai block pijakan"] = "Use scaffold blocks",
    ["Taruh block untuk lewat jurang / naik ke block melayang"] = "Place blocks to cross gaps / reach floating blocks",
    ["Block pijakan"] = "Scaffold block",
    ["Block yang dipakai untuk pijakan"] = "Block used as scaffold",
    ["Auto collect tiap habis pecah"] = "Auto collect after each break",
    ["Ambil drop di sekitar karakter"] = "Pick up drops around the character",
    ["Reset tile yang dilewati"] = "Reset skipped tiles",
    ["Coba lagi tile yang tadi gagal"] = "Retry tiles that failed",
    -- Farmer
    ["Status Farmer"] = "Farmer Status",
    ["Jalankan Farmer"] = "Run Farmer",
    ["Panen pohon siap & tanam seed otomatis"] = "Harvest ready trees & plant seeds automatically",
    ["Seed untuk ditanam"] = "Seed to plant",
    ["Hanya seed yang ada di inventori"] = "Only seeds in your inventory",
    ["Refresh daftar seed"] = "Refresh seed list",
    ["Hanya pohon yang sudah siap"] = "Only trees that are ready",
    ["Tanam di atas block yang kosong"] = "Plant on top of empty blocks",
    ["Ambil hasil panen di sekitar karakter"] = "Pick up harvest drops around the character",
    ["Jeda setelah tiap panen"] = "Delay after each harvest",
    ["Jeda setelah tiap tanam seed"] = "Delay after each seed planted",
    ["Taruh block kalau tidak ada jalan (block tetap tertinggal)"] = "Place blocks when there is no path (blocks stay behind)",
    -- Speed & opsi
    ["Place semua tile dulu, lalu break"] = "Place all tiles first, then break",
    ["Jeda setelah tiap place"] = "Delay after each place",
    ["Jeda tiap pukulan (normal 220). Dipakai juga Clear"] = "Delay per hit (normal 220). Also used by Clear",
    ["Auto Farm: tile dipukul bergantian (seperti 2 jari). Pakai Rayman's Fist = 2-3 tile segaris sekali pukul"] =
        "Auto Farm: tiles are hit in turns (like 2 fingers). With Rayman's Fist = 2-3 tiles in a line per punch",
    ["Jeda setelah hancur (ms)"] = "Delay after break (ms)",
    ["Tunggu sebelum lanjut ke tile berikutnya"] = "Wait before moving to the next tile",
    ["Mode Lite"] = "Lite Mode",
    ["Matikan particle & suara (HP low-end)"] = "Turn off particles & sounds (low-end phones)",
    ["Mute suara pukulan"] = "Mute punch sounds",
    ["Pukulan per block (cadangan)"] = "Hits per block (fallback)",
    ["Dipakai kalau 'Pukul: TIDAK'. 0 = otomatis"] = "Used when 'Punch: NO'. 0 = automatic",
    ["Pilih Block"] = "Select Block",
    ["Hanya item yang bisa di-place"] = "Only placeable items",
    ["Refresh daftar"] = "Refresh list",
    ["Lompat di udara (bisa kena rollback)"] = "Jump mid-air (may get rolled back)",
    ["Fly + Tembus Block"] = "Fly + Noclip",
    ["Tembus block, pakai tombol ▲/▼ (bisa kena rollback)"] = "Pass through blocks, use the ▲/▼ buttons (may get rolled back)",
    ["Bahasa / Language"] = "Language / Bahasa",
    ["Titik Drop"] = "Drop Point", ["Atur titik drop"] = "Set drop point", ["Drop otomatis"] = "Auto drop",
    ["Pantau item penuh"] = "Monitor full stacks",
    ["Item mencapai 200 lalu dibawa ke tile drop. Setelah itu kembali dan lanjut farming."] =
        "At 200, selected items are taken to the drop tile. Then return and resume farming.",
    ["Item yang di-drop"] = "Items to drop",
    ["Pilih item inventori. Setiap item yang mencapai 200 di-drop sebanyak 200."] =
        "Select inventory items. Each selected item drops a full stack of 200 when full.",
    ["Pilih tile drop"] = "Select drop tile",
    ["Pilih satu tile di grid 5x5. Tile disimpan sebagai posisi berdiri di world ini."] =
        "Choose one tile on the 5x5 grid. It is saved as the standing position in this world.",
    ["Pilih posisi berdiri untuk drop"] = "Choose drop standing tile",
    ["Item jatuh di depan karakter sesuai arah drop."] = "Items land in front of the character in the selected direction.",
    ["Arah drop"] = "Drop direction", ["Kiri"] = "Left", ["Kanan"] = "Right",
    ["Pakai tile tempat berdiri sekarang"] = "Use current standing tile",
    ["Selesai"] = "Done",
    ["Warp manual"] = "Manual warp", ["Hunting world"] = "World hunting",
    ["Nama world atau /warp"] = "World name or /warp", ["Warp & cek lock"] = "Warp & check locks",
    ["Pindah ke nama yang diisi lalu periksa lock world"] = "Travel to the entered world and inspect its locks",
    ["Cek world sekarang"] = "Check current world", ["Sumber nama"] = "Name source",
    ["Campuran"] = "Mixed", ["3 Huruf"] = "3 letters", ["4 Huruf"] = "4 letters",
    ["Kata Indonesia"] = "Indonesian words", ["Daftar sendiri"] = "Custom list",
    ["Daftar nama sendiri"] = "Custom world names",
    ["Pisahkan dengan koma atau spasi. Dipakai mode Daftar sendiri dan Campuran."] =
        "Separate with commas or spaces. Used by Custom list and Mixed modes.",
    ["Maksimal world per hunting"] = "Worlds per search", ["Jeda antar world (detik)"] = "Delay between worlds (seconds)",
    ["Berhenti saat ketemu"] = "Stop when found", ["Tetap di world tanpa lock yang ditemukan"] = "Stay in the unlocked world that was found",
    ["Jalankan World Finder"] = "Run World Finder", ["Hentikan hunting"] = "Stop hunting",
    ["Menghentikan farming selama hunting. Cek WL, Small Lock, Big Lock, Huge Lock, dan lock lainnya."] =
        "Stops farming while hunting. Checks WL, Small Lock, Big Lock, Huge Lock, and other locks.",
    ["URL Webhook Discord"] = "Discord webhook URL", ["Memakai URL yang sama dengan tab Discord"] = "Uses the same URL as the Discord tab",
    ["Notifikasi World Finder"] = "World Finder notifications",
    ["Kirim world tanpa lock dan ringkasan hasil hunting"] = "Send unlocked worlds and search summaries",
    ["Notif setiap world"] = "Notify for every world", ["Sertakan hasil terkunci, belum pasti, dan gagal masuk"] = "Include locked, unknown, and failed results",
    ["Tes webhook World Finder"] = "Test World Finder webhook",
    ["Proses sekarang"] = "Current task", ["Log terbaru"] = "Latest logs", ["Belum ada proses"] = "No activity yet",
    ["Salin log"] = "Copy logs", ["Salin riwayat proses untuk dibaca atau dikirim"] = "Copy the activity history to review or share",
    ["Cari world tanpa lock"] = "Find unlocked worlds", ["Pengaturan pencarian"] = "Search settings",
    ["Pindah manual"] = "Manual travel", ["Jenis nama"] = "Name type",
    ["Pilih nama pendek, kata, BUY, atau daftar buatanmu"] = "Choose short names, words, BUY names, or your own list",
    ["Daftar world"] = "World list", ["Untuk mode Daftar sendiri. Pisahkan nama dengan koma."] = "For Custom list mode. Separate names with commas.",
    ["Mulai cari"] = "Start search", ["Berhenti"] = "Stop",
    ["Masuk ke kandidat untuk cek lock. Berhenti saat ketemu world tanpa lock."] = "Enter candidates to check locks. Stop when an unlocked world is found.",
    ["Selesaikan proses aktif lalu berhenti di world terakhir"] = "Finish the current operation and stop in the last world",
    ["Jumlah world"] = "World count", ["Batas nama yang dicek dalam satu pencarian"] = "Maximum names to check in one search",
    ["Jeda pencarian (detik)"] = "Search delay (seconds)", ["Waktu tunggu sebelum memeriksa kandidat berikutnya"] = "Wait before checking the next candidate",
    ["Nama world"] = "World name", ["Isi nama world. Format /warp BUYSEED juga bisa."] = "Enter a world name. You can also use /warp BUYSEED.",
    ["Pindah & cek"] = "Travel & check", ["Masuk ke nama yang kamu isi dan tampilkan hasil lock"] = "Enter the specified world and show its lock status",
    ["Cek world ini"] = "Check this world", ["Periksa lock di world tempat kamu berada"] = "Check locks in your current world",
    ["Link webhook"] = "Webhook URL", ["Tempel webhook channel Discord tujuan"] = "Paste the destination Discord channel webhook",
    ["Kirim hasil ke Discord"] = "Send results to Discord", ["Kirim world yang ditemukan dan ringkasan pencarian"] = "Send worlds found and the search summary",
    ["Kirim setiap hasil"] = "Send every result", ["Sertakan kandidat terkunci dan yang gagal diperiksa"] = "Include locked candidates and failed checks",
    ["Tes notifikasi"] = "Test notification", ["Kirim pesan percobaan ke Discord"] = "Send a test message to Discord",
    ["Seed sudah banyak: jeda, drop ke titik drop (tab Titik Drop), balik ke posisi farm"] =
        "Too many seeds: pause, drop at the drop point (Drop Point tab), return to farm position",
    ["Seed dari block yang dipilih"] = "Seeds of the selected block",
    ["Drop kalau hampir penuh"] = "Drop when almost full",
    ["Hasil panen (block & seed) dibawa ke titik drop (tab Titik Drop)"] =
        "Harvest items (blocks & seeds) are taken to the drop point (Drop Point tab)",
    ["Drop kalau item sudah"] = "Drop when an item reaches",
    ["Maksimal 200 per item"] = "Max 200 per item",
    ["Sisakan seed tanam"] = "Seeds to keep for planting",
    ["Seed yang dipilih untuk ditanam tidak di-drop semua"] = "The planting seed is not dropped completely",
    ["Ke titik drop (tab Titik Drop)"] = "To the drop point (Drop Point tab)",
    ["Block kurang diproduksi dulu, lalu dipasang dari atas seperti ular (tanpa pijakan)"] =
        "Missing blocks are produced first, then placed from the top like a snake (no scaffolding)",
    ["Gali dulu dari permukaan sampai bawah, lalu pasang baris naik sampai atas (baris jadi jembatan). Block habis: produksi 1 baris"] =
        "Digs from the surface down to the bottom first, then places rows upward to the top (each row is its own bridge). Out of blocks: produces on 1 row",
    ["Baris block paling atas. Baris di bawahnya otomatis sampai di atas bedrock (tanah digali)"] =
        "Top block row. Rows below go automatically down to just above bedrock (dirt is dug out)",
    ["Berdiri di atas block pertama baris paling atas, lalu tekan (tangga kiri di sebelah kirinya)"] =
        "Stand on the first block of the top row, then press (left stairs go to its left)",
    ["Baris block paling atas. Baris di bawahnya dibuat otomatis sampai tanah"] =
        "Top block row. Rows below are made automatically down to the ground",
    ["Ganti bahasa, lalu execute ulang"] = "Change language, then re-execute",
    ["Mode collect"] = "Collect mode", ["Sentuhan"] = "Touch",
    ["Berlaku untuk semua fitur. Sentuhan = seperti main manual. Remote = ambil dari jauh (cara lama, cepat)"] =
        "Applies to all features. Touch = like manual play. Remote = picks up from a distance (old method, fast)",
    ["Ambil drop di semua tile grid (caranya ikut Mode collect)"] = "Pick up drops on all grid tiles (method follows Collect mode)",
    ["Radius collect (mode Remote)"] = "Collect radius (Remote mode)",
    ["Jarak ambil drop di sekitar karakter (tile)"] = "Pickup distance around the character (tiles)",
    ["Animasi aksi"] = "Action animation",
    ["Tangan bergerak saat break / place / tanam / panen + efek place. Matikan untuk hemat FPS"] =
        "Arm moves on break / place / plant / harvest + place effect. Turn off to save FPS",
    ["Jenis item"] = "Item type",
    ["Berlaku untuk isi stock (drop yang dipungut) dan kosongkan (vending yang diambil)"] =
        "Applies to stock (drops picked up) and empty (vendings taken from)",
    ["Block saja"] = "Blocks only", ["Seed saja"] = "Seeds only",
    ["Item yang diambil"] = "Items to take",
    ["Bisa pilih banyak. Kosong = semua item. Daftar: isi vending, tas & drop yang terlihat"] =
        "Multi-select. Empty = all items. List: vending contents, backpack & seen drops",
    ["Muat ulang daftar item"] = "Reload item list",
    ["Pilih item"] = "Pick items",
    ["Tambah item yang dipegang"] = "Add the held item",
    ["Pilih item di tas game (dipegang), lalu tekan. Masuk ke daftar item yang diambil"] =
        "Select an item in the game backpack (held), then press. Adds it to the items to take",
    ["Hapus pilihan item"] = "Clear item selection",
    ["Kembali ke semua item"] = "Back to all items",
    ["Simpan posisi drop vending (posisi karakter)"] = "Save vending drop position (character position)",
    ["Berdiri di tempat drop (boleh di world titik drop), lalu tekan. Dipakai mode isi stock & kosongkan"] =
        "Stand at the drop spot (can be in the drop-point world), then press. Used by stock & empty modes",
    ["Hapus posisi drop vending"] = "Clear vending drop position",
    ["Drop / tunggu di titik kedatangan (pintu) saja"] = "Drop / wait at the arrival point (door) only",
    ["Ambil item dari vending, tas & drop di world ini"] = "Read items from vendings, backpack & drops in this world",
    ["Posisi break produksi = posisi karakter"] = "Production break position = character position",
    ["Berdiri di tempat break lalu tekan. Tekan lagi di tempat yang sama = kembali otomatis"] =
        "Stand at the break spot and press. Press again at the same spot = back to automatic",
    ["Pilih tile break produksi (Grid)"] = "Pick production break tiles (Grid)",
    ["Grid terbuka dalam mode Lahan (terpisah dari Auto Farm & Pabrik)"] =
        "Grid opens in Land mode (separate from Auto Farm & Factory)",
    ["Status Vending"] = "Vending Status",
    ["Jalankan Vending"] = "Run Vending",
    ["Jalankan di world vending milikmu"] = "Run it in your vending world",
    ["Titik drop vending"] = "Vending drop point",
    ["WORLD atau WORLD:ID (kosong = world ini). Isi stock: ambil drop di sini. Kosongkan: drop di sini"] =
        "WORLD or WORLD:ID (empty = this world). Stock: picks up drops here. Empty: drops here",
    ["Isi stock dari drop"] = "Stock from drops",
    ["Kosongkan sampai habis"] = "Empty until done",
    ["Drop di semua tile grid diambil dengan sentuhan badan (melangkah / lompat), tanpa remote"] =
        "Drops on every grid tile are picked up by body touch (step / jump), no remote",
    ["Drop di sekitar disusuri sampai tersentuh badan (tanpa remote)"] =
        "Nearby drops are walked over until the body touches them (no remote)",
    -- Chat
    ["Status Chat"] = "Chat Status",
    ["Daftar pesan"] = "Message list",
    ["Pisahkan dengan |   contoh: halo|jual dirt"] = "Separate with |   example: hi|selling dirt",
    ["pesan 1|pesan 2|pesan 3"] = "message 1|message 2|message 3",
    ["Interval (detik)"] = "Interval (seconds)",
    ["Jeda antar pesan (min 3 detik)"] = "Delay between messages (min 3 seconds)",
    ["Kirim pesan bergantian sesuai urutan"] = "Send messages in order, one after another",
    ["Kirim 1 pesan sekarang"] = "Send 1 message now",
    ["Tes kirim pesan berikutnya"] = "Test sending the next message",
    ["Isi daftar pesan dulu (tekan Enter setelah mengetik)"] = "Fill in the message list first (press Enter after typing)",
    -- Penjaga
    ["Status Penjaga"] = "Guard Status",
    ["Mati"] = "Off",
    ["Aktifkan Penjaga"] = "Enable Guard",
    ["Pantau Mod / Dev / pemain yang masuk world"] = "Watch for Mods / Devs / players entering the world",
    ["Yang dideteksi"] = "Detect",
    ["Semua pemain: yang sudah ada saat dinyalakan diabaikan"] = "All players: those already here when enabled are ignored",
    ["Diam semua aktivitas"] = "Pause all activities",
    ["Keluar world"] = "Leave world",
    ["Langsung keluar world saat terdeteksi"] = "Leave the world immediately when detected",
    ["Lanjut otomatis setelah aman"] = "Auto resume when safe",
    ["Keluar world: masuk lagi, cek, lalu lanjut aktivitas sebelumnya"] = "Leave world: rejoin, check, then resume previous activity",
    ["Masuk world lagi setelah (detik)"] = "Rejoin world after (seconds)",
    ["Untuk mode keluar world"] = "For leave-world mode",
    ["Tunggu aman (detik)"] = "Safe wait (seconds)",
    ["Untuk mode diam: jeda setelah mereka pergi"] = "For pause mode: delay after they leave",
    ["Abaikan pemain yang ada sekarang"] = "Ignore players here now",
    ["Untuk teman / akun sendiri (staff tetap dideteksi)"] = "For friends / alt accounts (staff are still detected)",
    ["Batalkan tunggu / lanjut"] = "Cancel wait / resume",
    ["Hentikan proses keluar-masuk & lanjut otomatis"] = "Stop the leave-rejoin process & auto resume",
    ["Dibatalkan"] = "Cancelled",
    -- Bonus
    ["Klaim hadiah quest yang sudah selesai"] = "Claim rewards for finished quests",
    ["Cek quest sekarang"] = "Check quests now",
    ["Tukar semua code aktif yang belum dipakai"] = "Redeem all active codes not used yet",
    ["Cek code sekarang"] = "Check codes now",
    ["Redeem code manual"] = "Redeem code manually",
    ["Ketik code lalu tekan Enter"] = "Type a code then press Enter",
    ["KODE"] = "CODE",
    -- Growscan
    ["Info World"] = "World Info",
    ["Tekan Scan sekarang"] = "Press Scan now",
    ["Update otomatis tiap 2 detik"] = "Auto update every 2 seconds",
    ["Scan sekarang"] = "Scan now",
    ["Cari item"] = "Search item",
    ["Saring nama item (kosongkan = semua)"] = "Filter item name (empty = all)",
    ["contoh: seed"] = "example: seed",
    ["Daftar"] = "List",
    -- Statistik
    ["Sesi ini"] = "This session",
    ["Reset statistik"] = "Reset stats",
    ["Mulai hitung dari nol"] = "Start counting from zero",
    ["Kirim ke Discord sekarang"] = "Send to Discord now",
    ["Perlu webhook di tab Discord"] = "Needs a webhook in the Discord tab",
    ["Aktifkan webhook Discord dulu"] = "Enable the Discord webhook first",
    ["Direset"] = "Reset",
    ["Masuk antrian kirim"] = "Added to send queue",
    -- Tas
    ["Item yang dipilih di-recycle otomatis"] = "Selected items are recycled automatically",
    ["Item yang di-recycle"] = "Items to recycle",
    ["Bisa pilih banyak. Tool & lock tidak ditampilkan"] = "Multiple allowed. Tools & locks are not shown",
    ["Recycle kalau jumlah >="] = "Recycle when amount >=",
    ["200 = hanya saat penuh 1 slot"] = "200 = only when a slot is full",
    ["Sisakan"] = "Keep",
    ["Jumlah yang tidak ikut di-recycle"] = "Amount not recycled",
    ["Refresh daftar item"] = "Refresh item list",
    ["100 WL -> 1 DL, 100 DL -> 1 BGL (sama seperti game)"] = "100 WL -> 1 DL, 100 DL -> 1 BGL (same as the game)",
    -- Splice
    ["Status Splice"] = "Splice Status",
    ["Tanam Seed A lalu splice Seed B"] = "Plant Seed A then splice Seed B",
    ["Seed A (ditanam)"] = "Seed A (planted)",
    ["Seed B (di-splice)"] = "Seed B (spliced)",
    ["Keliling world (A*)"] = "Roam world (A*)",
    ["Nyala: jalan ke seluruh world. Mati: hanya tile Grid 5x5"] = "On: walk the whole world. Off: only the 5x5 Grid tiles",
    ["Jeda tanam / splice (ms)"] = "Plant / splice delay (ms)",
    -- Lahan
    ["Status Lahan"] = "Land Status",
    ["Bangun Lahan"] = "Build Land",
    ["Hitung block, produksi kalau kurang, lalu pasang dari baris bawah"] = "Count blocks, produce if short, then place from the bottom row",
    ["Block lahan"] = "Land block",
    ["Block padat dari inventori"] = "Solid block from inventory",
    ["X awal"] = "Start X",
    ["Kolom paling kiri"] = "Leftmost column",
    ["X akhir"] = "End X",
    ["Kolom paling kanan (lebih dari lebar world = sampai ujung)"] = "Rightmost column (beyond world width = to the edge)",
    ["Y baris atas"] = "Top row Y",
    ["Baris block paling atas (minimal 1)"] = "Topmost block row (minimum 1)",
    ["Jarak antar baris"] = "Row spacing",
    ["2 = y1, y3, y5.. | 3 = y1, y4, y7.. (maks 3 supaya bisa lompat naik)"] = "2 = y1, y3, y5.. | 3 = y1, y4, y7.. (max 3 so you can jump up)",
    ["Jumlah baris"] = "Number of rows",
    ["Tangga di pojok kiri-kanan"] = "Stairs at left-right corners",
    ["Ujung baris dibuka bergantian, jadi bisa turun-naik zig-zag"] = "Row ends open alternately, so you can go up/down in a zig-zag",
    ["Pakai posisi karakter sebagai pojok kiri-atas"] = "Use character position as top-left corner",
    ["X awal = kolom karakter, Y baris atas = tile di bawah kaki"] = "Start X = character column, top row Y = tile under the feet",
    ["Produksi block kalau kurang"] = "Produce blocks if short",
    ["Tanam & panen seed block itu dulu sampai cukup"] = "Plant & harvest that block's seed first until enough",
    ["Boleh taruh block pijakan"] = "Allow scaffold blocks",
    ["Kalau baris paling bawah tidak terjangkau dari tanah"] = "If the bottom row can't be reached from the ground",
    ["Lanjut Pabrik setelah selesai"] = "Start Factory when finished",
    -- Pabrik
    ["Status Pabrik"] = "Factory Status",
    ["Jalankan Pabrik"] = "Run Factory",
    ["Break -> tanam -> panen -> break lagi, seed lebihan di-drop"] = "Break -> plant -> harvest -> break again, extra seeds are dropped",
    ["Seed pabrik"] = "Factory seed",
    ["Block-nya otomatis (contoh: Dirt Seed -> Dirt)"] = "Block is automatic (example: Dirt Seed -> Dirt)",
    ["Tanam di seluruh world"] = "Plant in the whole world",
    ["Mati = hanya di lahan (tab Lahan)"] = "Off = only on the land (Land tab)",
    ["Pakai posisi sekarang untuk break"] = "Use current position for breaking",
    ["Berdiri di tempat break, lalu tekan"] = "Stand at the break spot, then press",
    ["Pilih tile break (Grid)"] = "Select break tiles (Grid)",
    ["Grid terbuka dalam mode Pabrik (terpisah dari tile Auto Farm)"] = "Grid opens in Factory mode (separate from Auto Farm tiles)",
    ["Lama 1 sesi break (detik)"] = "Break session length (seconds)",
    ["Setelah ini cek pohon siap dulu"] = "After this, check for ready trees first",
    ["Sisakan seed"] = "Seeds to keep",
    ["Untuk ditanam lagi"] = "For replanting",
    ["Drop kalau seed sudah"] = "Drop when seeds reach",
    ["Contoh 200 & sisakan 50 = drop 150"] = "Example 200 & keep 50 = drop 150",
    ["World drop"] = "Drop world",
    ["Kosong = world ini | WORLD | WORLD:ID (masuk lewat pintu ID)"] = "Empty = this world | WORLD | WORLD:ID (enter via door ID)",
    ["Pakai posisi sekarang untuk drop"] = "Use current position for dropping",
    ["Berdiri di tempat drop (boleh di world lain), lalu tekan"] = "Stand at the drop spot (can be another world), then press",
    ["Hapus posisi drop"] = "Clear drop position",
    ["Drop di titik kedatangan (pintu) saja"] = "Drop at the arrival point (door) instead",
    ["Ada block tapi posisi / tile break belum diatur"] = "Has blocks but break position / tiles are not set",
    ["Gagal jalan ke posisi break, dicoba lagi nanti"] = "Failed to walk to break position, retrying later",
    -- Koneksi & config
    ["Referensi game"] = "Game references",
    ["Hubungkan ke game"] = "Connect to game",
    ["Pakai setelah pindah world"] = "Use after changing worlds",
    ["Simpan pengaturan otomatis, dimuat lagi saat execute"] = "Save settings automatically, loaded again on execute",
    ["Simpan config sekarang"] = "Save config now",
    ["Hapus file config, lalu execute ulang"] = "Delete the config file, then re-execute",
    ["Koreksi posisi X"] = "Position correction X",
    ["Isi 1 / -1 kalau tile meleset"] = "Enter 1 / -1 if tiles are off",
    ["Koreksi posisi Y"] = "Position correction Y",
    ["Masuk lagi & lanjut aktivitas kalau terlempar"] = "Rejoin & resume activity if kicked out",
    ["Terlempar dari world"] = "Kicked from world",
    ["World ditutup / di-kick: masuk lagi ke world yang sama"] = "World closed / kicked: rejoin the same world",
    ["Selalu kembali ke world"] = "Always return to world",
    ["Kalau berada di luar world (layar pilih world), masuk lagi otomatis"] = "If outside a world (world select screen), rejoin automatically",
    ["World tujuan"] = "Target world",
    ["Kosongkan = world terakhir yang kamu masuki"] = "Empty = the last world you entered",
    ["NAMAWORLD"] = "WORLDNAME",
    ["Rejoin world sekarang"] = "Rejoin world now",
    ["Keluar lalu masuk lagi, aktivitas dilanjutkan"] = "Leave and rejoin, activity resumes",
    ["Disconnect dari server"] = "Disconnected from server",
    ["Teleport ulang ke game lalu masuk world terakhir"] = "Teleport back to the game and enter the last world",
    ["Jeda sebelum masuk lagi (detik)"] = "Delay before rejoining (seconds)",
    ["URL script (untuk rejoin server)"] = "Script URL (for server rejoin)",
    ["Link raw script ini, supaya jalan lagi setelah teleport. Kosong = pakai autoexec"] =
        "Raw link of this script, so it runs again after teleport. Empty = use autoexec",
    ["Sedang proses masuk world, tunggu dulu"] = "Already entering a world, please wait",
    ["World tujuan belum ada. Isi 'World tujuan' atau masuk world dulu"] = "No target world yet. Fill in 'Target world' or enter a world first",
    -- Discord
    ["Notifikasi Discord"] = "Discord Notifications",
    ["Kirim kabar penting ke channel Discord kamu"] = "Send important updates to your Discord channel",
    ["URL Webhook"] = "Webhook URL",
    ["Channel Discord > Edit > Integrasi > Webhook > Salin URL"] = "Discord channel > Edit > Integrations > Webhook > Copy URL",
    ["Tes kirim"] = "Test send",
    ["Laporan statistik (menit)"] = "Stats report (minutes)",
    ["Kirim statistik sesi tiap X menit. 0 = mati"] = "Send session stats every X minutes. 0 = off",
    ["Mod / Dev / pemain masuk world"] = "Mod / Dev / player entered world",
    ["Aktivitas berhenti (block habis / error)"] = "Activity stopped (out of blocks / error)",
    ["Quest diklaim / redeem berhasil"] = "Quest claimed / redeem successful",
    ["Terlempar / disconnect / masuk lagi"] = "Kicked / disconnected / rejoined",
    ["Pabrik drop seed / lahan selesai / berhenti"] = "Factory dropped seeds / land done / stopped",
    ["Isi URL webhook dulu"] = "Fill in the webhook URL first",
    ["Pesan tes masuk antrian"] = "Test message queued",
    ["URL webhook tidak valid"] = "Invalid webhook URL",
    ["Tes notifikasi dari n4th"] = "Test notification from n4th",
    -- pilihan dropdown
    ["Kiri → Kanan"] = "Left → Right", ["Semua pemain"] = "All players", ["Semua"] = "All",
    ["Depan"] = "Front", ["Break saja"] = "Break only", ["Place saja"] = "Place only",
    ["(memuat...)"] = "(loading...)", ["(inventori kosong)"] = "(inventory empty)",
    ["(inventori belum terbaca)"] = "(inventory not read yet)",
    ["(inventori kosong / belum terbaca)"] = "(inventory empty / not read yet)",
    ["Channel chat world belum ada (masuk world dulu)"] = "World chat channel not found (enter a world first)",
    ["Daftar pesan kosong"] = "Message list is empty",
    ["Inventori penuh"] = "Inventory full",
    ["Tanya bahasa saat execute"] = "Ask language on execute",
    ["Execute ulang untuk ganti bahasa / Re-execute to apply"] = "Re-execute to apply the new language",
    ["Munculkan pilihan bahasa tiap execute"] = "Show the language choice on every execute",
    -- Grid
    ["Grid Tile"] = "Tile Grid", ["Bersihkan pilihan"] = "Clear selection",
    ["Tile Break Pabrik"] = "Factory Break Tiles", ["START PABRIK"] = "START FACTORY", ["STOP PABRIK"] = "STOP FACTORY",
}

-- Frasa untuk teks yang berubah-ubah (status, notifikasi, pesan Discord)
I18N.PH = {
    { "Data world belum ketemu", "World data not found" }, { "Data drop belum ketemu", "Drop data not found" },
    { "Data pohon belum ketemu", "Tree data not found" }, { "Data pohon tidak ketemu", "Tree data not found" },
    { "Tekan 'Hubungkan ke game'", "Press 'Connect to game'" }, { "Hubungkan ke game", "Connect to game" },
    { "Kamu belum masuk world", "You are not in a world yet" }, { "belum masuk world", "not in a world yet" },
    { "tidak di world", "not in a world" },
    { "Menunggu karakter / world...", "Waiting for character / world..." },
    { "Menunggu pohon siap", "Waiting for trees to be ready" }, { "Menunggu", "Waiting" },
    { "Dihentikan karena", "Stopped because" }, { "Dihentikan", "Stopped" }, { "dimulai", "started" },
    { "hubungkan ulang ke game", "reconnecting to game" },
    { "Dijeda Penjaga", "Paused by Guard" }, { "Dijeda", "Paused" }, { "Waspada", "Alert" }, { "Ada:", "Present:" },
    { "Aman", "Safe" }, { "Pemain di world", "Players in world" }, { "Staff online di server", "Staff online on server" },
    { "Terdeteksi", "Detected" }, { "kali", "times" }, { "tidak ada", "none" },
    { "pemain diabaikan", "players ignored" },
    { "Masuk world", "Entered world" }, { "Keluar world", "Leave world" },
    { "Masuk lagi dalam", "Rejoining in" }, { "Masuk lagi ke", "Rejoining" }, { "Masuk lagi berhasil", "Rejoined" },
    { "Masuk lagi", "Rejoin" }, { "Masuk ke", "Entering" }, { "Masih ada", "Still here:" }, { "Keluar lagi", "Leaving again" },
    { "Sudah keluar world", "Already left the world" }, { "lanjut otomatis mati", "auto resume off" },
    { "Di luar world", "Outside the world" }, { "Mereka sudah pergi", "They left" }, { "Lanjut dalam", "Resuming in" },
    { "Sudah aman", "Safe now" }, { "World aman", "World is safe" }, { "World sudah beda", "Different world" },
    { "aktivitas tidak dilanjutkan", "activity not resumed" }, { "aktivitas dilanjutkan", "activity resumed" },
    { "aktivitas hanya dijeda", "activity only paused" },
    { "lanjut aktivitas", "resuming activity" }, { "Lanjut aktivitas", "Resuming activity" },
    { "Gagal balik ke posisi farm", "Failed to return to farm position" },
    { "Auto Farm tidak dilanjutkan", "Auto Farm not resumed" },
    { "Jalan balik ke posisi farm", "Walking back to farm position" },
    { "Jalan ke posisi break", "Walking to break position" }, { "Jalan ke posisi drop", "Walking to drop position" },
    { "Cari jalan A* ke", "Finding A* path to" }, { "Jalan ke", "Walking to" }, { "Lompati lubang ke", "Jumping gap to" },
    { "Lompat ke", "Jumping to" }, { "Turun ke", "Dropping down to" }, { "Naik pakai block ke", "Climbing with block to" },
    { "Taruh block pijakan", "Placing scaffold block" },
    { "di bawahnya berbahaya", "dangerous below" }, { "di bawahnya jurang", "pit below" },
    { "Lewati pijakan", "Skip foothold" }, { "Lewati", "Skip" },
    { "Pukul", "Hit" }, { "Pecah", "Broke" }, { "Panen", "Harvest" }, { "Tanam", "Plant" },
    { "Pasang lahan: sisa", "Placing land: remaining" }, { "Pasang", "Place" },
    { "Gali: sisa", "Digging: remaining" }, { "Gali", "Dig" }, { "Pukul", "Punch" },
    { "Tile Break Lahan", "Land Break Tiles" }, { "START LAHAN", "START LAND" }, { "STOP LAHAN", "STOP LAND" },
    { "Semua vending item terpilih sudah kosong", "All vendings of the selected items are empty" },
    { "semua item yang bisa dijual", "all sellable items" },
    { " - coba lagi", " - retrying" }, { "Tambah stock gagal:", "Adding stock failed:" },
    { "Menjauh dari drop sendiri supaya bisa dipungut", "Stepping away from own drops so they can be picked up" },
    { "Item terpilih sudah habis. Tidak diambil (bukan item terpilih):", "Selected items are empty. Not taken (not selected):" },
    { "Hapus pilihan item untuk ambil semua", "Clear the item selection to take everything" }, { "Cek ulang isi vending...", "Re-checking vending contents..." },
    { "Daftar item gagal dimuat:", "Item list failed to load:" }, { "tidak terbaca", "not readable" },
    { "Vending milikmu di", "Your vendings in" },
    { "Jalan ke posisi drop vending", "Walking to the vending drop position" },
    { "Tidak bisa jalan ke posisi drop vending", "Can't reach the vending drop position" },
    { "Tas penuh: atur titik drop vending (WORLD / WORLD:ID / simpan posisi XY)", "Backpack full: set the vending drop point (WORLD / WORLD:ID / save XY position)" },
    { "Daftar item:", "Item list:" }, { "Item dipilih:", "Item selected:" },
    { "Pegang dulu block / seed di tas game (bukan tool)", "Hold a block / seed in the game backpack first (not a tool)" },
    { "Pilihan item dihapus: semua item", "Item selection cleared: all items" },
    { "Posisi drop vending", "Vending drop position" }, { "Posisi drop vending dihapus", "Vending drop position cleared" },
    { "(titik kedatangan)", "(arrival point)" }, { "dropdown belum dibuat", "dropdown not created yet" },
    { "refresh gagal", "refresh failed" }, { "tas", "bag" },
    { "Vending item terpilih penuh / belum ada yang menjual item terpilih", "Vendings of the selected items are full / none sells them yet" },
    { "Fungsi animasi game tidak ketemu (tekan 'Hubungkan ke game')", "Game animation function not found (press 'Connect to game')" },
    { "Animasi", "Animation" }, { "(belum ada item)", "(no items yet)" }, { "| jenis:", "| type:" },
    { ": semua |", ": all |" }, { "jenis: Semua", "type: All" },
    { "Block saja", "Blocks only" }, { "Seed saja", "Seeds only" },
    { "Posisi break produksi", "Production break position" }, { "otomatis", "automatic" },
    { "kanan karakter, dekat ujung baris", "right of the character, near the row end" },
    { "grid lahan", "land grid" }, { "posisi break lahan", "land break position" },
    { "Ke vending", "To vending" }, { "): tambah", "): add" }, { "): ambil", "): take" },
    { "Gagal tambah stock di", "Failed to add stock at" }, { "Tidak bisa ke vending", "Can't reach vending" },
    { "Semua vending penuh / belum ada vending yang menjual item", "All vendings full / none sells an item yet" },
    { "Menunggu drop baru di", "Waiting for new drops in" }, { "untuk isi stock", "to restock" },
    { "Pergi ke titik drop", "Going to drop point" }, { "Gagal ke titik drop", "Failed to reach drop point" },
    { "Semua vending sudah kosong", "All vendings are empty" }, { "Ambil", "Take" },
    { "Selesai, ada vending yang gagal diambil", "Done, some vendings could not be emptied" },
    { "Vending kosong, tapi drop gagal", "Vendings empty, but dropping failed" },
    { "Tas penuh oleh item lain, kosongkan tas dulu", "Backpack is full of other items, clear it first" },
    { "Drop gagal", "Drop failed" }, { "Tambah stock gagal terus", "Adding stock keeps failing" },
    { "Gagal pulang ke world vending", "Failed to return to the vending world" },
    { "ambil drop", "to pick drops" },
    { "Tas penuh: atur titik drop vending (WORLD atau WORLD:ID)", "Backpack full: set the vending drop point (WORLD or WORLD:ID)" },
    { "Tidak ada vending milikmu di world ini (jalankan di world vending)", "No vending of yours in this world (run it in the vending world)" },
    { "Fungsi vending game tidak ketemu", "Game vending function not found" },
    { "milikmu di world ini | isi", "yours in this world | stocked" }, { "kosong", "empty" },
    { "diambil", "taken" },
    { "tile gali belum terjangkau, dicoba lagi", "dig tiles not reachable yet, retrying" },
    { "tile gali dilewati", "dig tiles skipped" }, { "Bersihkan drop di lahan", "Cleaning up drops on the land" },
    { "Ambil drop block sisa galian", "Picking up leftover dug blocks" },
    { "Bersihkan drop sisa galian (per baris)", "Cleaning up leftover dug drops (row by row)" },
    { "Ambil drop sisa di lahan (per baris)", "Picking up leftover drops on the land (row by row)" },
    { "Bersihkan drop di lahan (per baris)", "Cleaning up drops on the land (row by row)" },
    { "Bersihkan drop baris y", "Cleaning drops on row y" },
    { "Block habis, produksi 1 baris dulu", "Out of blocks, producing on 1 row first" },
    { "lanjut pasang", "resuming placing" }, { "sisakan", "keep" }, { "baris y", "row y" },
    { "Jalan ke posisi pasang-pecah", "Walking to the place-break spot" },
    { "Naik tangga ke", "Climbing stairs to" }, { "belum terjangkau, dilewati sebentar", "not reachable yet, skipped for a while" },
    { "Tidak ada baris lahan (cek X awal / X akhir / Y baris atas)", "No land rows (check start X / end X / top row Y)" },
    { "Belum ada baris lengkap", "No complete row yet" }, { "seed-nya tidak ketemu", "its seed was not found" },
    { "celah, tangga, background", "gaps, stairs, background" }, { "selesai", "done" },
    { "Produksi block", "Producing blocks" }, { "total butuh", "total needed" },
    { "Lahan selesai", "Land finished" }, { "Block cukup", "Enough blocks" }, { "mulai pasang", "starting to place" },
    { "Block habis, masih kurang", "Out of blocks, still short" }, { "Seed & block habis", "Seeds & blocks used up" },
    { "tidak ada pohon tumbuh", "no trees growing" }, { "Butuh", "Need" }, { "Seed habis", "Out of seeds" },
    { "seed-nya tidak ketemu", "its seed was not found" }, { "Block kurang", "Blocks short" },
    { "Sisa tile belum terjangkau / terhalang, dicoba lagi", "Remaining tiles unreachable / blocked, retrying" },
    { "Lahan penuh, menunggu", "Land is full, waiting" }, { "Bukan di world pabrik", "Not in the factory world" },
    { "menunggu...", "waiting..." }, { "Pergi ke", "Going to" }, { "untuk drop", "to drop" }, { "Pulang ke", "Returning to" },
    { "Gagal pulang ke world pabrik", "Failed to return to factory world" }, { "Drop gagal", "Drop failed" },
    { "tidak bisa drop di posisi ini", "can't drop at this position" },
    { "tidak bisa jalan ke posisi drop", "can't walk to the drop position" },
    { "Posisi drop belum diatur", "Drop position not set" }, { "drop dilewati", "drop skipped" },
    { "Posisi drop dihapus", "Drop position cleared" }, { "Posisi drop", "Drop position" }, { "Posisi break", "Break position" },
    { "di posisi pabrik", "at the factory position" }, { "Pabrik berhenti", "Factory stopped" },
    { "Bangun Lahan", "Build Land" }, { "Pabrik", "Factory" }, { "Penjaga", "Guard" }, { "Lahan", "Land" },
    { "Gagal masuk lagi ke", "Failed to rejoin" }, { "Gagal masuk", "Failed to enter" }, { "Gagal keluar world", "Failed to leave world" },
    { "Dicoba lagi nanti", "Will retry later" }, { "dicoba lagi", "retrying" },
    { "Gagal splice", "Splice failed" }, { "ditolak server", "rejected by server" }, { "Splice jadi", "Spliced into" },
    { "Menunggu tile Grid kosong (panen dulu pohonnya)", "Waiting for empty Grid tiles (harvest the trees first)" },
    { "Seed A habis, tidak ada pohon A yang bisa di-splice", "Seed A used up, no A trees to splice" },
    { "tidak ada tempat tanam / pohon untuk di-splice", "no planting spot / tree to splice" },
    { "Karakter tidak ditemukan (keluar world?)", "Character not found (left the world?)" },
    { "di inventori habis", "in inventory is used up" }, { "Auto Farm berhenti", "Auto Farm stopped" },
    { "Auto Clear berhenti", "Auto Clear stopped" }, { "Farmer berhenti", "Farmer stopped" },
    { "Inventori penuh", "Inventory full" }, { "tidak bisa diambil lagi", "can't be picked up anymore" },
    { "Laporan statistik", "Stats report" }, { "Quest diklaim", "Quest claimed" }, { "Redeem berhasil", "Redeem successful" },
    { "Redeem gagal", "Redeem failed" }, { "Terlempar dari world", "Kicked from world" }, { "Terlempar dari", "Kicked from" },
    { "Kembali otomatis", "Auto return" }, { "berhasil", "succeeded" },
    { "Rejoin: menunggu masuk", "Rejoin: waiting to enter" }, { "Rejoin: gagal masuk", "Rejoin: failed to enter" },
    { "Disconnect dari server", "Disconnected from server" }, { "script tidak di-queue", "script not queued" },
    { "Berhasil masuk lagi", "Rejoined" }, { "World tujuan", "Target world" },
    { "Mode diganti, nyalakan lagi", "Mode changed, turn it on again" }, { "World sudah bersih!", "World is clean!" },
    { "Block pijakan belum dipilih / habis: jalan tanpa block pijakan", "Scaffold block not selected / empty: moving without scaffold" },
    { "Auto Harvest tidak bisa cek pohon siap", "Auto Harvest can't check ready trees" },
    { "Aktifkan Auto Harvest atau Auto Plant", "Enable Auto Harvest or Auto Plant" },
    { "Pilih seed dulu untuk Auto Plant", "Select a seed for Auto Plant first" },
    { "Pilih seed pabrik dulu", "Select a factory seed first" }, { "Block dari seed ini tidak ketemu", "Block for this seed not found" },
    { "Atur lahan dulu", "Set up the land first" }, { "Pilih block padat untuk lahan", "Select a solid block for the land" },
    { "Pilih Seed A dan Seed B dulu", "Select Seed A and Seed B first" }, { "Seed A dan Seed B harus beda", "Seed A and Seed B must differ" },
    { "Kombinasi ini tidak bisa di-splice", "This combination can't be spliced" },
    { "Pilih tile dulu di Grid Tile", "Select tiles in the Tile Grid first" }, { "Pilih block dari inventori", "Select a block from inventory" },
    { "Hentikan Auto Farm / Clear / Farmer dulu", "Stop Auto Farm / Clear / Farmer first" },
    { "atau nyalakan Keliling world", "or turn on Roam world" },
    { "Kontrol gerak game (WorldMenu.isDown) tidak ketemu", "Game movement control (WorldMenu.isDown) not found" },
    { "Fungsi pukul game belum ketemu", "Game punch function not found" },
    { "Seed habis: atur posisi & tile break di tab Pabrik supaya bisa dapat seed", "Out of seeds: set break position & tiles in the Factory tab to get seeds" },
    { "Config dihapus. Execute ulang untuk default", "Config deleted. Re-execute for defaults" },
    { "Config dimuat", "Config loaded" }, { "Belum ada config", "No config yet" }, { "Tersimpan", "Saved" },
    { "Executor tidak bisa simpan file", "Executor can't save files" }, { "Executor tidak bisa hapus file", "Executor can't delete files" },
    { "Executor tidak punya fungsi request", "Executor has no request function" },
    { "Gagal simpan file", "Failed to save file" }, { "Gagal hapus file", "Failed to delete file" },
    { "Gagal kirim", "Failed to send" }, { "Terkirim", "Sent" }, { "Antrian", "Queue" },
    { "Gagal buka", "Failed to open" }, { "Gagal", "Failed" },
    -- label status
    { "BERHENTI", "STOPPED" }, { "JALAN", "RUNNING" }, { "fase", "phase" }, { "PANEN", "HARVEST" }, { "TANAM", "PLANT" },
    { "TUNGGU", "WAIT" }, { "TIDAK terbaca (harvest mati)", "NOT readable (harvest off)" }, { "terbaca", "readable" },
    { "TIDAK", "NO" }, { "cadangan", "fallback" }, { "Inventori", "Inventory" }, { "Posisi", "Position" },
    { "Karakter", "Character" }, { "Aksi", "Action" }, { "Baris", "Row" }, { "Pohon", "Trees" }, { "Pijakan", "Scaffold" },
    { "Pemain", "Players" }, { "belum dipilih", "not selected" }, { "belum diatur", "not set" }, { "ditolak", "rejected" },
    { "Bentuk", "Shape" }, { "baris", "rows" }, { "jarak", "spacing" }, { "tangga", "stairs" }, { "punya", "have" },
    { "butuh", "need" }, { "kurang", "short" }, { "cukup", "enough" }, { "Terpasang", "Placed" },
    { "terhalang block lain", "blocked by other blocks" }, { "Celah tanam terisi block", "Planting gaps filled with blocks" },
    { "bersihkan dulu", "clear it first" }, { "Celah tanam: bersih", "Planting gaps: clear" }, { "Seed block", "Block seed" },
    { "Hasil", "Result" }, { "panen", "harvest" }, { "tanam", "plant" }, { "di-drop", "dropped" }, { "sisakan", "keep" },
    { "drop saat", "drop at" }, { "world ini", "this world" }, { "pintu", "door" }, { "Lama sesi", "Session time" },
    { "Block pecah", "Blocks broken" }, { "Block di-place", "Blocks placed" }, { "Drop diambil", "Drops collected" },
    { "Item terbanyak", "Top items" }, { "Selesai", "Done" }, { "diklaim script", "claimed by script" },
    { "Quest baru dalam", "New quests in" }, { "Quest belum bisa diambil", "Quests not available yet" },
    { "Gagal ambil quest", "Failed to get quests" }, { "Gagal ambil daftar code", "Failed to get code list" },
    { "Pesan terakhir", "Last message" }, { "Cek lagi dalam", "Checking again in" }, { "detik", "seconds" },
    { "Auto klaim mati", "Auto claim off" }, { "Code aktif", "Active codes" }, { "sudah ditukar", "redeemed" },
    { "ditukar script", "redeemed by script" }, { "Auto redeem mati", "Auto redeem off" },
    { "Redeem sedang ditutup", "Redeem is closed" }, { "Block depan", "Front blocks" }, { "tumpukan", "piles" },
    { "siap panen", "ready" }, { "tumbuh", "growing" }, { "Scan terakhir", "Last scan" }, { "siap", "ready" },
    { "berikut", "next" }, { "Tidak ada yang cocok", "No matches" }, { "Kosong", "Empty" }, { "Tidak ada pohon", "No trees" },
    { "item lain", "more items" }, { "jenis lain", "more types" }, { "pakai Cari item", "use Search item" },
    { "(pohon)", "(tree)" }, { "Di-recycle", "Recycled" }, { "Item dipilih", "Items selected" }, { "Ditanam", "Planted" },
    { "tidak bisa di-splice", "can't be spliced" }, { "Pilih Seed A dan Seed B", "Select Seed A and Seed B" },
    { "Menghitung...", "Calculating..." }, { "Mulai...", "Starting..." }, { "Lanjut aktivitas...", "Resuming activity..." },
    { "data pemain belum ketemu", "player data not found" }, { "belum ketemu", "not found" },
    { "tidak ketemu", "not found" }, { "ketemu", "found" }, { "tekan", "press" },
    { "tidak ada block padat di inventori", "no solid blocks in inventory" },
    { "tidak ada seed di inventori", "no seeds in inventory" }, { "tidak ada pohon", "no trees" },
    { "tidak ada tempat tanam", "no planting spot" },
    { "Y baris atas", "top row Y" }, { "baris atas", "top row" }, { "Y awal", "start Y" }, { "X awal", "start X" },
    { "jumlah baris", "row count" }, { "masuk lagi dalam", "rejoining in" }, { "masuk ke", "entering" },
    { "dalam", "in" }, { "Executor tidak punya", "Executor has no" },
    { "tidak bisa dijangkau / dipecah", "can't be reached / broken" }, { "Sisa", "Remaining" },
    { "dilewati, coba ulang", "skipped, retrying" }, { "Gagal membaca pengaturan", "Failed to read settings" },
    { "balasan kosong", "empty reply" }, { "fungsi drop game tidak ketemu", "game drop function not found" },
    { "fungsi masuk world tidak ketemu", "game enter-world function not found" },
    { "fungsi splice game tidak ketemu", "game splice function not found" },
    { "gagal masuk", "failed to enter" }, { "nama world tidak diketahui", "unknown world name" },
    { "tidak bisa ke server", "can't reach the server" }, { "tunggu", "wait" },
    { "world penuh / dikunci / gagal", "world full / locked / failed" }, { "aman", "safe" }, { "Fase", "Phase" },
    { "Titik drop belum diatur (tab Titik Drop), drop dilewati", "Drop point not set (Drop Point tab), drop skipped" },
    { "Ambil hasil panen...", "Picking up harvest..." }, { "Lanjut Auto Farm", "Resuming Auto Farm" },
    { "Auto Farm dihentikan", "Auto Farm stopped" }, { "Gagal pulang ke world farmer", "Failed to return to farmer world" },
    { "Gagal pulang ke world farm", "Failed to return to farm world" },
    { "Sesi break tanpa aksi: cek posisi & tile break (dicoba lagi 1 menit)",
        "Break session had no action: check break position & tiles (retry in 1 minute)" },
    { "pohon siap belum terjangkau, dicoba lagi", "ready trees not reachable yet, retrying" },
    { "Seed hampir penuh", "Seeds almost full" },
    { "atur titik drop & nyalakan Auto drop seed", "set a drop point & turn on Auto drop seed" },
    { "Pasang & pecah", "Place & break" }, { "untuk dapat seed", "to get seeds" },
    { "Seed habis & tidak ada tempat pasang-pecah di samping karakter",
        "Out of seeds & no spot beside the character to place and break" },
    { "Tidak ada tempat tanam, menunggu", "No planting spot, waiting" },
    { "drop di titik ini tidak di-collect lagi", "drops at this point are not collected again" },
    { "titik kedatangan", "arrival point" }, { "hasil panen", "harvest" }, { "sisakan seed", "keep seeds" },
    { "Dipakai", "Used by" }, { "Di-drop", "Dropped" }, { "Catatan", "Note" }, { "Titik", "Point" },
    { "Produksi", "Production" }, { "Drop seed", "Seed drop" },
    { "Tidak ada baris yang muat (Y atas terlalu bawah). Berdiri di pojok kiri-ATAS lahan lalu tekan 'Pakai posisi karakter'",
        "No rows fit (top Y too low). Stand at the TOP-LEFT corner of the land, then press 'Use character position'" },
    { "tidak ada baris yang muat (Y atas terlalu bawah)", "no rows fit (top Y too low)" },
    { "berdiri di pojok kiri-atas lalu tekan 'Pakai posisi karakter'", "stand at the top-left corner, then press 'Use character position'" },
    { "Tidak bisa ke awal lahan", "Can't reach the land start" }, { "Pecah anak tangga", "Breaking stair step" },
    { "Pasang anak tangga", "Placing stair step" }, { "Turun ke anak tangga", "Stepping down to stair step" },
    { "Bersihkan tile lahan", "Clearing land tile" }, { "Ambil drop", "Picking up drop" },
    { "1 kosong per baris, tangga kiri & kanan", "1 gap per row, stairs on left & right" },
    { "titik drop belum diatur", "drop point not set" }, { "otomatis saat", "automatic at" },
    { "Dipakai: Pabrik (seed), Farmer & Auto Farm (otomatis saat item ~190)",
        "Used by: Factory (seeds), Farmer & Auto Farm (automatic when an item reaches ~190)" },
    { "saat", "at" },
    { "Mati", "Off" }, { "mati", "off" }, { "pohon siap", "trees ready" }, { "pohon", "trees" },
    { "di-recycle", "recycled" }, { "di-splice", "spliced" }, { "di-place", "placed" }, { "di-queue", "queued" }, { "habis", "used up" }, { "dan", "and" }, { "atau", "or" }, { "dari", "from" }, { "untuk", "for" },
    { "sudah", "already" }, { "belum", "not yet" }, { "lagi", "again" }, { "di", "at" }, { "ke", "to" },
}

-- Pola tambahan (format waktu "1j 2m 3d" -> "1h 2m 3s", "/jam" -> "/hour")
I18N.RAW = {
    { "(%d+)j (%d+)m (%d+)d", "%1h %2m %3s" },
    { "(%d+)m (%d+)d", "%1m %2s" },
    { "(%d+)j (%d+)m", "%1h %2m" },
    { "/jam", "/hour" },
    { "(%d+) dtk", "%1 s" },
}

function I18N.prep()
    local list = {}
    for _, p in ipairs(I18N.PH) do
        if p[1] ~= p[2] then
            local pat = p[1]:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
            if p[1]:match("^%w") then pat = "%f[%w]" .. pat end
            if p[1]:match("%w$") then pat = pat .. "%f[%W]" end
            list[#list + 1] = { pat, (p[2]:gsub("%%", "%%%%")), #p[1] }
        end
    end
    table.sort(list, function(a, b) return a[3] > b[3] end)
    I18N.list = list
end

-- Terjemahkan teks (kalau bahasa = English)
function I18N.T(s)
    if I18N.Lang ~= "en" or type(s) ~= "string" or s == "" then return s end
    local e = I18N.EN[s]
    if e then return e end
    if not I18N.list then I18N.prep() end
    for _, r in ipairs(I18N.list) do s = s:gsub(r[1], r[2]) end
    for _, r in ipairs(I18N.RAW) do s = s:gsub(r[1], r[2]) end
    return s
end

-- Teks pilihan dropdown: hanya terjemahan utuh (nama item game tidak diubah)
function I18N.V(s)
    if I18N.Lang ~= "en" or type(s) ~= "string" then return s end
    return I18N.EN[s] or s
end

-- Bungkus objek WindUI: judul, deskripsi, pilihan dropdown & isi status ikut diterjemahkan
I18N.Backs = setmetatable({}, { __mode = "k" })

local function mapList(list, back)
    local out = {}
    for i, val in ipairs(list) do
        local tr = I18N.V(val)
        out[i] = tr
        if type(tr) == "string" then back[tr] = val end
    end
    return out
end

function I18N.wrap(obj)
    if I18N.Lang ~= "en" or type(obj) ~= "table" then return obj end
    return setmetatable({}, {
        __index = function(_, k)
            local v = obj[k]
            if type(v) ~= "function" then return v end
            return function(_, cfg, ...)
                local back
                if k == "Dropdown" and type(cfg) == "table" then
                    back = {}
                    if type(cfg.Values) == "table" then cfg.Values = mapList(cfg.Values, back) end
                    if type(cfg.Value) == "string" then
                        cfg.Value = I18N.V(cfg.Value)
                    elseif type(cfg.Value) == "table" then
                        cfg.Value = mapList(cfg.Value, back)
                    end
                    local cb = cfg.Callback
                    if cb then
                        -- tampil dalam English, callback tetap terima teks asli
                        cfg.Callback = function(opt, ...)
                            if type(opt) == "string" then
                                opt = back[opt] or opt
                            elseif type(opt) == "table" then
                                local o2 = {}
                                for i, x in ipairs(opt) do o2[i] = back[x] or x end
                                opt = o2
                            end
                            return cb(opt, ...)
                        end
                    end
                elseif (k == "Refresh" or k == "Select") and I18N.Backs[obj] then
                    local b = I18N.Backs[obj]
                    if type(cfg) == "table" then
                        cfg = mapList(cfg, b)
                    elseif type(cfg) == "string" then
                        cfg = I18N.V(cfg)
                    end
                end
                if type(cfg) == "table" and k ~= "Refresh" and k ~= "Select" and cfg[1] == nil then
                    for _, f in ipairs({ "Title", "Desc", "Placeholder", "Content" }) do
                        if type(cfg[f]) == "string" then cfg[f] = I18N.T(cfg[f]) end
                    end
                elseif type(cfg) == "string" and (k == "SetDesc" or k == "SetTitle") then
                    cfg = I18N.T(cfg)
                end
                local r = v(obj, cfg, ...)
                if back and type(r) == "table" then I18N.Backs[r] = back end
                if type(r) == "table" and r ~= obj then return I18N.wrap(r) end
                return r
            end
        end,
    })
end
end)() end

local function notify(title, content, dur)
    task.defer(function()
        pcall(function()
            WindUI:Notify({ Title = I18N.T(title), Content = I18N.T(content), Duration = dur or 3, Icon = "info" })
        end)
    end)
end

---------------------------------------------------------------------
-- CONFIG: simpan & muat pengaturan otomatis
---------------------------------------------------------------------
-- Cara kerja:
--   1. Saat execute, file config dibaca lalu nilainya dipasang ke pengaturan
--      SEBELUM UI dibuat, jadi tombol & slider langsung tampil sesuai config.
--   2. Tiap 3 detik pengaturan sekarang dibandingkan dengan yang terakhir disimpan.
--      Ada yang berubah -> langsung disimpan (auto save).
--   3. File per akun: workspace/n4thOpus/config_<UserId>.json
--   Yang tidak disimpan: tombol jalan (Auto Farm / Clear / Farmer / Chat), fly & inf jump.
local Config = {
    AutoSave = true,
    Paused = false,      -- true setelah reset (supaya file tidak dibuat lagi)
    Folder = "n4thOpus",
    Data = {},           -- isi file saat execute
    List = {},           -- tabel pengaturan yang disimpan
    LastJson = nil,
    Status = "-",
}

do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local HttpService = game:GetService("HttpService")
    local canFile = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
    Config.CanFile = canFile
    Config.Path = Config.Folder .. "/config_" .. tostring(LocalPlayer.UserId) .. ".json"

    local function read()
        if not canFile then return nil end
        local okE, exists = pcall(isfile, Config.Path)
        if not okE or not exists then return nil end
        local okR, raw = pcall(readfile, Config.Path)
        if not okR or type(raw) ~= "string" then return nil end
        local okD, data = pcall(HttpService.JSONDecode, HttpService, raw)
        if okD and type(data) == "table" then return data end
        return nil
    end

    local loaded = read()
    Config.Found = loaded ~= nil
    Config.Data = loaded or {}
    if Config.Data.AutoSave == false then Config.AutoSave = false end
    Config.Status = Config.Found and "Config dimuat" or (canFile and "Belum ada config" or "Executor tidak bisa simpan file")

    -- Daftarkan tabel pengaturan. Nilai dari file langsung dipasang
    -- (kecuali key di 'later', dipasang sendiri setelah terhubung ke game).
    function Config.add(name, tbl, keys, later)
        table.insert(Config.List, { name = name, tbl = tbl, keys = keys })
        local saved = Config.Data[name]
        if type(saved) ~= "table" then return end
        for _, k in ipairs(keys) do
            local v, cur = saved[k], tbl[k]
            if v ~= nil and not (later and later[k]) and (cur == nil or type(v) == type(cur)) then
                tbl[k] = v
            end
        end
    end

    function Config.saved(name, key)
        local t = Config.Data[name]
        return type(t) == "table" and t[key] or nil
    end

    local function collect()
        local out = { AutoSave = Config.AutoSave, Version = 2 }
        for _, e in ipairs(Config.List) do
            local t = {}
            for _, k in ipairs(e.keys) do t[k] = e.tbl[k] end
            out[e.name] = t
        end
        return out
    end

    local function copy(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local result = {}
        seen[value] = result
        for key, entry in pairs(value) do result[key] = copy(entry, seen) end
        return result
    end
    local function equal(value, saved, seen)
        if rawequal(value, saved) then return true end
        if type(value) ~= "table" or type(saved) ~= "table" then return false end
        seen = seen or {}
        if seen[value] == saved then return true end
        seen[value] = saved
        for key, entry in pairs(value) do if not equal(entry, saved[key], seen) then return false end end
        for key in pairs(saved) do if value[key] == nil then return false end end
        return true
    end

    function Config.save(force)
        if not canFile then
            Config.Status = "Executor tidak bisa simpan file"
            return false
        end
        if Config.Paused and not force then return false end
        local current = collect()
        -- Bandingkan snapshot sebelum encode: config yang diam tidak membuat JSON
        -- baru tiap tiga detik. Salinan dalam juga mendeteksi edit grid di tempat.
        if not force and equal(current, Config.LastSnapshot) then return true end
        local okJ, json = pcall(HttpService.JSONEncode, HttpService, current)
        if not okJ then
            Config.Status = "Gagal membaca pengaturan"
            return false
        end
        if not force and json == Config.LastJson then
            Config.LastSnapshot = copy(current)
            return true
        end
        if type(isfolder) == "function" and type(makefolder) == "function" then
            local okF, has = pcall(isfolder, Config.Folder)
            if okF and not has then pcall(makefolder, Config.Folder) end
        end
        local ok = pcall(writefile, Config.Path, json)
        if ok then
            Config.LastJson = json
            Config.LastSnapshot = copy(current)
            Config.Paused = false
            Config.Status = "Tersimpan " .. os.date("%H:%M:%S")
        else
            Config.Status = "Gagal simpan file"
        end
        return ok
    end

    -- Hapus file config (execute ulang = kembali ke default)
    function Config.reset()
        if I18N.forget then I18N.forget() end
        Config.Paused = true
        Config.LastJson = nil
        Config.LastSnapshot = nil
        if canFile and type(delfile) == "function" then
            local ok = pcall(delfile, Config.Path)
            Config.Status = ok and "Config dihapus. Execute ulang untuk default" or "Gagal hapus file"
            return ok
        end
        Config.Status = "Executor tidak bisa hapus file"
        return false
    end

    function Config.start()
        -- Gunakan isi file sebagai snapshot, bukan menganggap default baru sudah tersimpan.
        if Config.Found then Config.LastSnapshot = copy(Config.Data) end
        task.spawn(function()
            while alive() do
                task.wait(10)
                if Config.AutoSave and alive() then Config.save(false) end
            end
        end)
    end
end)() end

Config.add("Farm", State, {
    "Mode", "PlaceMs", "BreakMs", "AfterBreakMs", "HitsOverride", "SelectedId", "Offsets",
    "CalibX", "CalibY", "AntiAfk", "MutePunch", "Visual", "LiteMode", "AutoCollect", "MultiTarget",
    "CollectAround", "CollectRadius", "CollectMode", "FastPunch", "FastPunchHits", "FastPunchMs",
    "WorldBreakId", "WorldBreakCollect",
})
Config.add("RouteDrop", RouteDrop, { "TargetId", "PlatformId", "DropX", "DropY", "Direction" })
-- Pindahkan nilai default lama. Nilai yang dipilih di versi baru tetap berlaku.
if (Config.Data.Version == nil or Config.Data.Version == 1) and State.AfterBreakMs == 300 then
    State.AfterBreakMs = 250
end
Config.add("Clear", Clear, { "UseBlock", "ScaffoldId", "Collect", "Sweep" })
Config.add("Farmer", Farmer, {
    "Harvest", "Plant", "Collect", "UseBlock", "ScaffoldId", "HarvestMs", "PlantMs", "SeedId", "Focus", "Tractor",
})
-- update 1084: game memberi jeda minimal antar aksi (place ~0.135 dtk, pukul ~0.19 dtk)
State.PlaceMs = math.max(State.PlaceMs, 140)
State.BreakMs = math.max(State.BreakMs, 200)
Farmer.HarvestMs = math.max(Farmer.HarvestMs, 140)
Farmer.PlantMs = math.max(Farmer.PlantMs, 140)
Config.add("Misc", Misc, { "Speed" })
Config.add("Lahan", Land, { "X0", "X1", "Y0" })
Config.add("Bangun", Build, { "BlockId", "ThenPabrik", "BreakX", "BreakY", "Tiles" })
Config.add("Pabrik", Pabrik, {
    "SeedId", "WholeWorld", "Tiles", "BreakX", "BreakY",
    "Drop", "Keep", "DropAt", "DropWorld", "DropX", "DropY",
})
Config.add("Bahasa", I18N, { "Saved", "Ask", "Chosen" })
do
    local teleport = game:GetService("TeleportService")
    local key = "n4th.language.v1"
    local function valid(lang) return lang == "id" or lang == "en" end
    local saved = Config.Data.Bahasa
    if type(saved) == "table" and valid(saved.Saved) and saved.Chosen == nil then
        -- Config lama memakai Ask=true sebagai default, bukan pilihan khusus pengguna.
        I18N.Chosen, I18N.Ask = true, false
    end
    local ok, preference = pcall(teleport.GetTeleportSetting, teleport, key)
    if ok and type(preference) == "table" and preference.User == LocalPlayer.UserId
        and preference.Chosen == true and valid(preference.Saved) then
        I18N.Saved, I18N.Chosen, I18N.Ask = preference.Saved, true, preference.Ask == true
    end
    I18N.Lang = valid(I18N.Saved) and I18N.Saved or "id"
    function I18N.remember()
        pcall(teleport.SetTeleportSetting, teleport, key, {
            User = LocalPlayer.UserId, Saved = I18N.Saved, Ask = I18N.Ask, Chosen = I18N.Chosen,
        })
        if Session.Ready then Config.save(true) else I18N.SavePending = true end
    end
    function I18N.forget()
        pcall(teleport.SetTeleportSetting, teleport, key, false)
    end
end

---------------------------------------------------------------------
-- STATISTIK SESI & NOTIFIKASI DISCORD (data; tampilan ada di tab Statistik / Discord)
---------------------------------------------------------------------
local Stats = { T0 = os.clock(), Gems0 = nil, Items = {}, Base = {} }

-- Cara kerja webhook:
--   Hook.send(jenis, teks) memasukkan pesan ke antrian.
--   Antrian dikirim satu per satu tiap 2.5 detik (supaya tidak kena batas Discord).
local Hook = {
    On = false,
    Url = "",
    Penjaga = true,   -- mod / dev / pemain masuk world
    Stop = true,      -- aktivitas berhenti (block habis, error)
    Full = true,      -- inventori penuh
    Rejoin = true,    -- terlempar / masuk lagi
    Pabrik = true,    -- pabrik drop / lahan selesai / berhenti
    ReportMin = 0,    -- laporan statistik tiap X menit (0 = mati)
    Queue = {},
    LastFull = {},
    Status = "-",
}

do (function()
    local HttpService = game:GetService("HttpService")

    local function requester()
        return (syn and syn.request) or (http and http.request) or http_request or request
            or (fluxus and fluxus.request)
    end

    function Hook.valid(url)
        url = tostring(url or "")
        for _, host in ipairs({ "discord.com", "discordapp.com", "ptb.discord.com", "canary.discord.com" }) do
            if string.sub(url, 1, #host + 22) == "https://" .. host .. "/api/webhooks/" then return true end
        end
        return false
    end

    -- jenis: "penjaga" | "stop" | "full" | "bonus" | "rejoin" | "report" | "test"
    function Hook.send(kind, text)
        -- Pengujian lokal tidak mengirim notifikasi ke Discord; config pengguna tetap utuh.
        if G.__n4thLiveTest and G.__n4thLiveTest.Running then return end
        if not Hook.On or not Hook.valid(Hook.Url) then return end
        local allow = kind == "test" or kind == "report"
            or (kind == "penjaga" and Hook.Penjaga) or (kind == "stop" and Hook.Stop)
            or (kind == "full" and Hook.Full)
            or (kind == "rejoin" and Hook.Rejoin) or (kind == "pabrik" and Hook.Pabrik)
        if not allow or #Hook.Queue >= 20 then return end
        table.insert(Hook.Queue, I18N.T(tostring(text)))
    end

    task.spawn(function()
        while alive() do
            local text = table.remove(Hook.Queue, 1)
            if not text then
                task.wait(1)
            else
                local req = requester()
                if not req then
                    Hook.Status = "Executor tidak punya fungsi request"
                else
                    local body = HttpService:JSONEncode({
                        username = "n4th",
                        content = ("**[%s]** %s"):format(LocalPlayer.Name, text),
                    })
                    local ok, res = pcall(req, {
                        Url = Hook.Url, Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" }, Body = body,
                    })
                    local code = ok and type(res) == "table" and tonumber(res.StatusCode or res.Status) or nil
                    if ok and (code == nil or code < 300) then
                        Hook.Status = "Terkirim " .. os.date("%H:%M:%S")
                    else
                        Hook.Status = "Gagal kirim (" .. tostring(code or res) .. ")"
                    end
                end
                task.wait(2.5)
            end
        end
    end)
end)() end

---------------------------------------------------------------------
-- CARI DATA & FUNGSI GAME (getgc)
---------------------------------------------------------------------
local function getconsts(fn)
    -- Beberapa executor memasang API debug yang ada tetapi hanya mengembalikan tabel kosong.
    local previous
    for _, api in ipairs({ (debug and debug.getconstants) or false, getconstants or false }) do
        if type(api) == "function" and api ~= previous then
            previous = api
            local ok, values = pcall(api, fn)
            if ok and type(values) == "table" and next(values) ~= nil then return values end
        end
    end
    return {}
end

local function getUpvalues(fn)
    for _, api in ipairs({ (debug and debug.getupvalues) or false, getupvalues or false }) do
        if type(api) == "function" then
            local ok, values = pcall(api, fn)
            if ok and type(values) == "table" and next(values) ~= nil then return values end
        end
    end
    for _, api in ipairs({ (debug and debug.getupvalue) or false, getupvalue or false }) do
        if type(api) == "function" then
            local out = {}
            for i = 1, 80 do
                local ok, first, second = pcall(api, fn, i)
                if not ok then break end
                -- Executor umumnya mengembalikan nilai; API Lua juga bisa mengembalikan nama, nilai.
                local value = first
                if second ~= nil then value = second end
                if value ~= nil then out[i] = value end
            end
            if next(out) ~= nil then return out end
        end
    end
    return {}
end

-- Sesudah update, require executor dapat menghasilkan tabel kelas yang berbeda
-- dari metatable instance inventori aktif. Validasi API dan bentuk slot-nya.
local function isInventory(value)
    if type(value) ~= "table" or type(rawget(value, "slots")) ~= "table"
        or type(rawget(value, "capacity")) ~= "number" then return false end
    if type(value.count) ~= "function" or type(value.remove) ~= "function"
        or type(value.add) ~= "function" or type(value.used) ~= "function"
        or type(value.select) ~= "function" or type(value.room) ~= "function" then return false end
    for _, slot in pairs(rawget(value, "slots")) do
        if type(slot) ~= "table" or type(slot.id) ~= "number" or type(slot.n) ~= "number" then return false end
    end
    return true
end

-- Fungsi place game: satu-satunya yang memakai "placedAt" + "flips" sekaligus.
-- Kirimnya "tile" (game baru, ByteNet) atau "SetTile" (game lama).
local function isSetTileFn(fn)
    if not getconsts then return false end
    local ok, consts = pcall(getconsts, fn)
    if not ok or type(consts) ~= "table" then return false end
    local hasSend, hasPlaced, hasFlips = false, false, false
    for _, c in pairs(consts) do
        if c == "tile" or c == "SetTile" then hasSend = true
        elseif c == "placedAt" then hasPlaced = true
        elseif c == "flips" then hasFlips = true end
    end
    return hasSend and hasPlaced and hasFlips
end

-- Fungsi pukul game: teks "Empty the Vending Machine first!" + "newCrack"
-- (game lama: "HarvestProvider")
local function isPunchFn(fn)
    if not getconsts then return false end
    local ok, consts = pcall(getconsts, fn)
    if not ok or type(consts) ~= "table" then return false end
    local hasVend, hasMark = false, false
    for _, c in pairs(consts) do
        if type(c) == "string" then
            local lc = c:lower()
            if lc:find("vending", 1, true) and (lc:find("empty", 1, true) or lc:find("first", 1, true)) then hasVend = true
            elseif c == "newCrack" or c == "HarvestProvider" or lc:find("crack", 1, true) then hasMark = true end
        end
    end
    return hasVend and hasMark
end

-- Fungsi game yang menggambar tangan karakter saat memukul / memasang
function Anim.isArmFn(fn)
    if not getconsts then return false end
    local ok, consts = pcall(getconsts, fn)
    if not ok or type(consts) ~= "table" then return false end
    local a, b, c = false, false, false
    for _, k in pairs(consts) do
        if k == "forearm" then a = true
        elseif k == "heldReach" then b = true
        elseif k == "punchReach" then c = true end
    end
    return a and b and c
end

-- Cari nomor upvalue "aksi terakhir" (tabel {t, x, y, facing} atau nil) di fungsi tangan.
-- Upvalue ini dipakai bersama oleh kode input & gambar karakter game, jadi cukup diganti sekali.
function Anim.bind(fn)
    local gu = (debug and debug.getupvalue) or getupvalue
    local su = (debug and debug.setupvalue) or setupvalue
    if not (gu and su) then return false end
    local vals, last = {}, 0
    for i = 1, 16 do
        local ok, v = pcall(gu, fn, i)
        if not ok then break end
        vals[i] = v
        if v ~= nil then last = i end
    end
    for i = 1, last - 1 do
        local v = vals[i]
        if v == nil or (type(v) == "table" and rawget(v, "t") ~= nil and rawget(v, "facing") ~= nil) then
            Anim.fn, Anim.idx, Anim.set = fn, i, su
            return true
        end
    end
    return false
end

local function isStateHolder(v)
    local fn = rawget(v, "state")
    if type(fn) ~= "function" then return false end
    local ok, s = pcall(fn)
    return ok and type(s) == "table" and type(s.x) == "number" and type(s.y) == "number"
        and s.facing ~= nil and s.vx ~= nil
end

-- Pastikan fungsi milik game, bukan milik script ini
local function isGameFn(fn)
    if fn == isSetTileFn or fn == isPunchFn then return false end
    local sources = {}
    if debug and type(debug.info) == "function" then
        local ok, src = pcall(debug.info, fn, "s")
        if ok and type(src) == "string" then sources[#sources + 1] = src end
    end
    if debug and type(debug.getinfo) == "function" then
        local ok, info = pcall(debug.getinfo, fn, "S")
        if ok and type(info) == "table" then
            if type(info.source) == "string" then sources[#sources + 1] = info.source end
            if type(info.short_src) == "string" then sources[#sources + 1] = info.short_src end
        end
    end
    for _, src in ipairs(sources) do
        if src:find("GameGui", 1, true) or src:find("PlayerScripts", 1, true)
            or src:find("ReplicatedStorage", 1, true) then return true end
    end
    if isexecutorclosure then
        local ok, res = pcall(isexecutorclosure, fn)
        if ok and res then return false end
    end
    for _, src in ipairs(sources) do
        if src:find("n4th-main", 1, true) or src == "executor" or src == "[C]" or src == "=[C]" then return false end
    end
    return true
end

function Anim.consider(v, trusted)
    local tv = type(v)
    if tv == "table" then
        if not Refs.World then
            local ok, isWorld = pcall(function()
                return type(rawget(v, "fg")) == "table" and type(rawget(v, "bg")) == "table"
                    and type(rawget(v, "w")) == "number" and type(rawget(v, "h")) == "number"
                    and rawget(v, "spawn") ~= nil
            end)
            if ok and isWorld then Refs.World = v end
        end
        if not Refs.Inv then
            local ok, isInv = pcall(function()
                return isInventory(v)
            end)
            if ok and isInv then Refs.Inv = v end
        end
        if not Refs.State then
            local ok, isHolder = pcall(isStateHolder, v)
            if ok and isHolder then Refs.State = rawget(v, "state") end
        end
        if not Refs.Menu then
            local ok, isMenu = pcall(function()
                return type(rawget(v, "openBackpack")) == "function" and type(rawget(v, "ui")) == "table"
            end)
            if ok and isMenu then Refs.Menu = v end
        end
        if not Refs.Gems then
            local ok, isG = pcall(function() return type(rawget(v, "addGems")) == "function" end)
            if ok and isG then Refs.Gems = v end
        end
        if not Refs.Hud then
            local ok, isH = pcall(function()
                return type(rawget(v, "punchRange")) == "function" and type(rawget(v, "handPower")) == "function"
            end)
            if ok and isH then Refs.Hud = v end
        end
        if not Refs.Others then
            -- data pemain lain: punya list(), where(), playerAt()
            local ok, isO = pcall(function()
                return type(rawget(v, "list")) == "function" and type(rawget(v, "where")) == "function"
                    and type(rawget(v, "playerAt")) == "function"
            end)
            if ok and isO then Refs.Others = v end
        end
        if ParticlesOk then
            local ok, isP = pcall(function()
                return getmetatable(v) == ParticlesModule and type(rawget(v, "live")) == "table"
                    and type(rawget(v, "free")) == "table"
            end)
            if ok and isP and not table.find(Refs.Particles, v) then table.insert(Refs.Particles, v) end
        end
    elseif tv == "function" and (not Refs.SetTile or not Refs.Punch) and v ~= isPunchFn and v ~= isSetTileFn and (trusted or isGameFn(v)) then
        if not Refs.SetTile and isSetTileFn(v) then
            Refs.SetTile = v
        elseif not Refs.Punch and isPunchFn(v) then
            Refs.Punch = v
        end
    end
end

local function findRefs()
    -- Reconnect sudah mengosongkan referensi lama. Pertahankan hasil koneksi input aktif.
    Refs.ScanCount, Refs.ScanError = 0, nil
    if type(getgc) ~= "function" then
        Refs.ScanError = "Executor tidak punya getgc()"
        return Refs.World ~= nil, Refs.ScanError
    end
    local gcOk, objects = pcall(getgc, true)
    if not gcOk or type(objects) ~= "table" then gcOk, objects = pcall(getgc) end
    if not gcOk or type(objects) ~= "table" then
        Refs.ScanError = "getgc gagal: " .. tostring(objects)
        return Refs.World ~= nil, Refs.ScanError
    end
    -- Hasil getgc executor dapat berlubang atau memakai key non-urutan.
    -- ipairs berhenti di lubang pertama dan melewatkan objek yang masih valid.
    for _, v in pairs(objects) do
        Refs.ScanCount += 1
        Anim.consider(v)
        if Refs.World and Refs.Inv and Refs.SetTile and Refs.State and Refs.Punch
            and Refs.Menu and Refs.Gems and Refs.Hud and Refs.Others then break end
        if Refs.ScanCount % 2000 == 0 then task.wait() end
    end
    return Refs.World ~= nil
end

local function refsText()
    return "World: " .. (Refs.World and "OK" or "TIDAK")
        .. " | Inventori: " .. (Refs.Inv and "OK" or "TIDAK")
        .. " | setTile: " .. (Refs.SetTile and "OK" or "cadangan")
        .. " | Posisi: " .. (Refs.State and "OK" or "cadangan")
        .. " | Pukul: " .. (Refs.Punch and "OK" or "TIDAK")
        .. " | Drop: " .. (Drops.list and "OK" or "TIDAK")
        .. " | Pohon: " .. (Refs.Trees and "OK" or "TIDAK")
        .. " | Pemain: " .. (Refs.Others and "OK" or "TIDAK")
        .. " | Animasi: " .. (Anim.fn and "OK" or "TIDAK")
        .. " | Dropdown: " .. (UI.DropErr and ("ERROR " .. tostring(UI.DropErr)) or (UI.DropOk and "OK" or "-"))
end

---------------------------------------------------------------------
-- ITEM & INVENTORI
---------------------------------------------------------------------
local NAME_KEYS = { "name", "Name", "displayName", "DisplayName", "display_name", "title", "Title", "label", "Label", "itemName", "ItemName", "n", "nm", "dn" }
local NAME_SKIP = { icon = true, image = true, texture = true, sound = true, sfx = true, desc = true, description = true, tip = true,
    kind = true, type = true, category = true, rarity = true, tag = true, tags = true, anim = true, model = true, id = true }
local itemNameCache = {}
local function itemName(id)
    local cached = itemNameCache[id]
    if cached then return cached end
    local it = ItemDB[id]
    local found
    if type(it) == "string" and it ~= "" then
        found = it
    elseif type(it) == "table" then
        for _, k in ipairs(NAME_KEYS) do
            local v = it[k]
            if type(v) == "string" and v ~= "" then found = v break end
        end
        if not found then
            -- Fallback: string pertama yang tampak seperti nama (bukan URL/aset, bukan deskripsi panjang).
            local best
            for k, v in pairs(it) do
                if type(v) == "string" and #v >= 2 and #v <= 40 and not v:find("rbxasset") and not v:find("://")
                    and v:find("%a") and not NAME_SKIP[tostring(k):lower()] then
                    if not best or tostring(k) < best.k then best = { k = tostring(k), v = v } end
                end
            end
            found = best and best.v
        end
    end
    if found then itemNameCache[id] = found return found end
    return "Item #" .. tostring(id)
end

local function invCount(id)
    if not Refs.Inv then return 0 end
    local ok, n = pcall(function() return Refs.Inv:count(id) end)
    return ok and n or 0
end

local function isPlaceable(id)
    local it = ItemDB[id]
    if not it then return false end
    if it.kind == "tool" or it.kind == "cloth" or it.kind == "clothes" or it.kind == "consumable" then
        return false
    end
    if it.lock or it.area then return false end
    return true
end

local function placeableIds()
    local ids = {}
    if Refs.Inv then
        for _, slot in ipairs(Refs.Inv.slots) do
            if slot.id and (slot.n or 0) > 0 and isPlaceable(slot.id) then
                ids[#ids + 1] = slot.id
            end
        end
    end
    table.sort(ids)
    return ids
end

local function inventoryLabels(ids)
    local out = {}
    for _, id in ipairs(ids or placeableIds()) do
        out[#out + 1] = string.format("%s [%d]", itemName(id), id)
    end
    if #out == 0 then out = { "(inventori kosong / belum terbaca)" } end
    return out
end

-- Dropdown cuma di-refresh kalau jenis item berubah (biar tidak lag)
local lastInvSig = nil
local invRefreshPending = false

local lastSeedSig = nil
local lastBlockSig = nil

-- Seed di inventori (untuk Farmer)
local function seedIds()
    local ids = {}
    if Refs.Inv then
        for _, slot in ipairs(Refs.Inv.slots) do
            local it = slot.id and ItemDB[slot.id]
            if it and it.kind == "seed" and (slot.n or 0) > 0 then
                ids[#ids + 1] = slot.id
            end
        end
    end
    table.sort(ids)
    return ids
end

-- Setelah daftar di-refresh, pilih lagi item yang sedang dipakai (dari config / pilihan lama)
local function selectSaved(dd, labels, id)
    if not dd or not id then return end
    local pending = UI.PendingDropdowns[dd]
    if pending then pending.id = id return end
    local want = "[" .. tostring(id) .. "]"
    for _, label in ipairs(labels) do
        if string.sub(label, -#want) == want then
            UI.exec(function() dd:Select(label) end)
            return
        end
    end
end

-- Refresh 1 dropdown; error dicatat (tampil di tab Koneksi)
function UI.ddRefresh(dd, labels)
    if not dd then return end
    if not UI.tabVisible(UI.DropdownTabs[dd]) then
        UI.PendingDropdowns[dd] = { labels = labels }
        return
    end
    UI.PendingDropdowns[dd] = nil
    local ok, err = UI.exec(function() dd:Refresh(labels) end)
    if ok then
        UI.DropOk = os.clock()
    else
        UI.DropErr = ("%s (id %s/%s)"):format(tostring(err), tostring(UI.ident()), tostring(Session.Ident))
        UI.DropErrAt = os.clock()
    end
end

local function doInvRefresh(force)
    if not force and UI.Window and UI.Window.Closed then UI.InvDirty = true return end
    UI.DropErr = nil
    local ids = placeableIds()
    local sig = table.concat(ids, ",")
    if force or sig ~= lastInvSig then
        lastInvSig = sig
        local labels = inventoryLabels(ids)
        UI.ddRefresh(UI.InvDropdown, labels)
        selectSaved(UI.InvDropdown, labels, State.SelectedId)
    end
    local sids = seedIds()
    local ssig = table.concat(sids, ",")
    if force or ssig ~= lastSeedSig then
        lastSeedSig = ssig
        local labels = {}
        for _, id in ipairs(sids) do
            labels[#labels + 1] = string.format("%s [%d]", itemName(id), id)
        end
        if #labels == 0 then labels = { "(tidak ada seed di inventori)" } end
        UI.ddRefresh(UI.SeedDropdown, labels)
        selectSaved(UI.SeedDropdown, labels, Farmer.SeedId)
        if UI.PabrikSeedDropdown then
            UI.ddRefresh(UI.PabrikSeedDropdown, labels)
            selectSaved(UI.PabrikSeedDropdown, labels, Pabrik.SeedId)
        end
    end
    -- block padat untuk pijakan
    local bids = {}
    for _, id in ipairs(ids) do
        local it = ItemDB[id]
        if it and it.solid and it.kind ~= "seed" then bids[#bids + 1] = id end
    end
    local bsig = table.concat(bids, ",")
    if force or bsig ~= lastBlockSig then
        lastBlockSig = bsig
        local labels = {}
        for _, id in ipairs(bids) do
            labels[#labels + 1] = string.format("%s [%d]", itemName(id), id)
        end
        if #labels == 0 then labels = { "(tidak ada block padat di inventori)" } end
        UI.ddRefresh(UI.ClearBlockDropdown, labels)
        UI.ddRefresh(UI.FarmerBlockDropdown, labels)
        selectSaved(UI.ClearBlockDropdown, labels, Clear.ScaffoldId)
        selectSaved(UI.FarmerBlockDropdown, labels, Farmer.ScaffoldId)
        if UI.BuildBlockDropdown then
            UI.ddRefresh(UI.BuildBlockDropdown, labels)
            selectSaved(UI.BuildBlockDropdown, labels, Build.BlockId)
        end
    end
    -- daftar Tas (dibuat di bagian bawah script)
    if UI.TrashRefresh then pcall(UI.TrashRefresh, force) end
    if UI.AutoDropRefresh then pcall(UI.AutoDropRefresh, force) end
end

local function refreshInvDropdown(force)
    if force then UI.InvForce = true end
    if not force and invRefreshPending then return end
    invRefreshPending = true
    UI.later("inv", function()
        invRefreshPending = false
        local f = UI.InvForce == true
        UI.InvForce = false
        if alive() then doInvRefresh(f) end
    end, force and 0 or 0.3)
end

-- Dropdown tersembunyi tidak perlu dibangun ulang tiap inventori berubah.
-- Saat tab dibuka, baca data terbaru lalu kerjakan maksimal satu daftar tertunda.
function UI.flushInventory()
    if not UI.Window or UI.Window.Closed then return end
    local tab = UI.Window.CurrentTab
    if UI.InvDirty or UI.LastInventoryTab ~= tab then
        UI.InvDirty, UI.LastInventoryTab = false, tab
        refreshInvDropdown(false)
    end
    if invRefreshPending then return end
    for dd, pending in pairs(UI.PendingDropdowns) do
        if UI.tabVisible(UI.DropdownTabs[dd]) then
            UI.PendingDropdowns[dd] = nil
            UI.ddRefresh(dd, pending.labels)
            selectSaved(dd, pending.labels, pending.id)
            break
        end
    end
end

local invConn
local function watchInventory()
    if invConn then pcall(function() invConn:Disconnect() end) end
    if Refs.Inv and typeof(Refs.Inv.changed) == "Instance" then
        invConn = Refs.Inv.changed.Event:Connect(function()
            if alive() then refreshInvDropdown(false) end
        end)
        table.insert(Connections, invConn)
    end
end

---------------------------------------------------------------------
-- WORLD: tile & posisi karakter
---------------------------------------------------------------------
local function tileAt(layer, x, y)
    local w = Refs.World
    if not w or x < 0 or y < 0 or x >= w.w or y >= w.h then return nil end
    local grid = w[layer]
    local row = grid and grid[y]
    return row and (row[x] or 0) or nil
end

local function getView()
    local gg = PlayerGui:FindFirstChild("GameGui")
    local cam = gg and gg:FindFirstChild("World") and gg.World:FindFirstChild("Camera")
    local tiles = cam and cam:FindFirstChild("Tiles")
    local pv = cam and cam:FindFirstChild("PlayerView")
    if not (tiles and pv) then return nil end
    local sample = tiles:FindFirstChildWhichIsA("ImageLabel")
    if not sample or sample.AbsoluteSize.X <= 0 then return nil end
    return { tiles = tiles, pv = pv, ts = sample.AbsoluteSize.X }
end

local function getPlayerTile()
    if Refs.State then
        local ok, s = pcall(Refs.State)
        if ok and type(s) == "table" and type(s.x) == "number" then
            if s.active == false then return nil end
            return math.floor(s.x) + State.CalibX, math.floor(s.y - 0.475) + State.CalibY
        end
    end
    local v = getView()
    if not v then return nil end
    local center = v.pv.AbsolutePosition + v.pv.AbsoluteSize / 2
    local rel = center - v.tiles.AbsolutePosition
    return math.floor(rel.X / v.ts) + State.CalibX, math.floor(rel.Y / v.ts) + State.CalibY
end

-- Tile, block & mode Auto Farm yang dipakai sekarang (Pabrik memakai miliknya sendiri)
local function farmOffsets()
    local o = State.Override
    return (o and o.offsets) or State.Offsets
end
local function farmBlock()
    local o = State.Override
    if o then return o.block end
    return State.SelectedId
end
local function farmMode()
    local o = State.Override
    return (o and o.mode) or State.Mode
end

local function sortedOffsets()
    local list = {}
    for key in pairs(farmOffsets()) do
        local dx, dy = string.match(key, "^(-?%d+),(-?%d+)$")
        table.insert(list, { dx = tonumber(dx), dy = tonumber(dy) })
    end
    table.sort(list, function(a, b)
        if a.dy ~= b.dy then return a.dy < b.dy end
        return a.dx < b.dx
    end)
    return list
end

---------------------------------------------------------------------
-- AKSI DASAR: place & pukul
---------------------------------------------------------------------
local function sendSetTile(layer, x, y, id)
    if id ~= 0 and State.Visual and Anim.place then Anim.place(x, y, id) end
    if Refs.SetTile then
        local ok, err = pcall(Refs.SetTile, layer, x, y, id, false, false)
        if ok then return true end
        warn("[n4th] setTile game gagal, pakai remote langsung: " .. tostring(err))
    end
    if NetOk and type(Net) == "table" and type(Net.tile) == "table" then
        -- sama seperti game: layer 1 = fg, 2 = bg
        local ok = pcall(Net.tile.send, {
            layer = (layer == "bg") and 2 or 1, x = x, y = y, id = id, flip = false,
        })
        if not ok then return false end
    elseif SetTileRemote then
        SetTileRemote:FireServer(layer, x, y, id, false)
    else
        return false
    end
    local grid = Refs.World and Refs.World[layer]
    if grid and grid[y] then grid[y][x] = id end
    return true
end

-- ===== FAST PUNCH (burst saat pukul manual di block apa pun) =====
-- Hook dipasang SEKALI dan dibagi lintas eksekusi (getgenv), supaya re-execute tidak
-- menumpuk hook lama / memasang hook di fungsi yang salah (klon orig).
Session.FastPunch = Session.FastPunch or { Hooked = nil }
function Session.FastPunch.install()
    local G = (type(getgenv) == "function" and getgenv()) or _G
    G.__n4thFP = G.__n4thFP or {}
    local FP = G.__n4thFP
    -- referensi "hidup" -> selalu menunjuk eksekusi script terbaru
    FP.State, FP.alive, FP.tileAt = State, alive, tileAt
    local fn = Refs.Punch
    if not fn then return false, "Fungsi pukul game belum ketemu" end
    if FP.fn and (rawequal(FP.fn, fn) or rawequal(FP.orig, fn)) then
        Session.FastPunch.Hooked = { fn = FP.fn }
        return true
    end
    if type(hookfunction) ~= "function" then return false, "Executor tidak punya hookfunction" end
    FP.Bursting, FP.Queue = false, {}
    -- antrian auto-break: tiap block yang kena pukul manual diselesaikan sampai hancur,
    -- walau kamu sudah pindah arah. Hanya aktif selama toggle Fast Punch ON.
    local function work()
        pcall(function()
            while true do
                local job = table.remove(FP.Queue, 1)
                if not job then break end
                local st, tAt = FP.State, FP.tileAt
                if not (st and st.FastPunch and FP.alive and FP.alive()) then
                    table.clear(FP.Queue)
                    break
                end
                FP.Key = job.key
                for _ = 2, math.clamp(st.FastPunchHits or 12, 2, 40) do
                    -- pacing global: jarak antar SEMUA pukulan (punyamu + burst) >= jeda,
                    -- supaya tidak saling bertabrakan dan ditolak server
                    local gap = math.max(st.FastPunchMs or 190, 50) / 1000
                    while os.clock() - (FP.Last or 0) < gap and FP.alive() and st.FastPunch do
                        task.wait()
                    end
                    if not (FP.alive() and st.FastPunch) then
                        table.clear(FP.Queue)
                        break
                    end
                    local fg, bg = tAt("fg", job.x, job.y), tAt("bg", job.x, job.y)
                    if (fg or 0) == 0 and (bg or 0) == 0 then break end
                    if job.fg0 ~= 0 and fg ~= job.fg0 then break end
                    FP.Last = os.clock()
                    pcall(FP.orig, job.x, job.y, table.unpack(job.extra, 1, job.extra.n))
                end
                FP.Key = nil
            end
        end)
        FP.Bursting, FP.Key = false, nil
    end
    local function wrapper(x, y, ...)
        local extra = table.pack(...)
        local st, tAt = FP.State, FP.tileAt
        local isXY = type(x) == "number" and type(y) == "number"
        local fg0 = (isXY and tAt) and tAt("fg", x, y) or nil
        local orig = FP.orig
        FP.Last = os.clock()
        local res = table.pack(orig(x, y, ...))
        if isXY and st and st.FastPunch and not st.ScriptPunch and fg0 ~= nil
            and FP.alive and FP.alive() then
            local key = x .. "," .. y
            if key ~= FP.Key then
                local dup = false
                for _, j in ipairs(FP.Queue) do
                    if j.key == key then dup = true break end
                end
                if not dup and #FP.Queue < 30 then
                    table.insert(FP.Queue, { key = key, x = x, y = y, fg0 = fg0, extra = extra })
                end
            end
            if not FP.Bursting then
                FP.Bursting = true
                task.spawn(work)
            end
        end
        return table.unpack(res, 1, res.n)
    end
    local ok, res = pcall(hookfunction, fn, wrapper)
    if not ok then return false, tostring(res) end
    FP.orig, FP.fn = res, fn
    Session.FastPunch.Hooked = { fn = fn }
    return true
end

local function sendHitFx(x, y)
    if NetOk and type(Net) == "table" and Net.act then
        pcall(Net.act.send, { x = x + 0.5, y = y + 0.5 })
    end
end

local function hitsNeeded(id)
    if State.HitsOverride > 0 then return State.HitsOverride end
    local it = ItemDB[id]
    if not it then return 4 end
    local h = (it.kind == "seed") and 20 or it.hits
    return tonumber(h) or 4
end

local function canBreak(id)
    if id == 0 then return false end
    local it = ItemDB[id]
    if not it then return true end
    if it.lock or it.area or it.vend or it.display then return false end
    local h = (it.kind == "seed") and 20 or it.hits
    return h == nil or h > 0
end

-- Game abaikan pukulan ke tile yang baru di-place (< 0.3 detik)
local PLACE_GUARD = 0.32

-- Place 1 tile kalau kosong. Hasil: "place" / "habis" / nil
local function tryPlace(x, y)
    local sel = farmBlock()
    if not sel then return nil end
    local fg = tileAt("fg", x, y)
    if fg == nil then return nil end
    local bg = tileAt("bg", x, y)
    local it = ItemDB[sel]
    local layer = (it and it.background) and "bg" or "fg"
    local cur = (layer == "bg") and bg or fg
    if not (cur == 0 and (layer == "bg" or fg == 0)) then return nil end
    if invCount(sel) <= 0 then return "habis" end

    sendSetTile(layer, x, y, sel)
    if Refs.Inv then pcall(function() Refs.Inv:remove(sel, 1) end) end
    local key = x .. "," .. y
    HitCount[key] = nil
    PlacedAt[key] = os.clock()
    State.Placed += 1
    State.LastAction = "Place " .. itemName(sel) .. " (" .. x .. "," .. y .. ")"
    return "place"
end

-- Masih ada yang bisa dipecah di tile ini? (block depan / background)
local function breakableAt(x, y)
    local fg = tileAt("fg", x, y)
    if fg == nil then return false end
    if fg ~= 0 then return canBreak(fg) end
    local bg = tileAt("bg", x, y)
    return State.BreakBackground and bg ~= nil and bg ~= 0 and canBreak(bg)
end

-- Pukul 1 kali. Hasil: "hit" / "broke" / nil
-- includeBg = ikut pecah background
local function tryBreak(x, y, includeBg, onlyId, onlyLayer)
    if includeBg == nil then includeBg = State.BreakBackground end
    local key = x .. "," .. y
    local fg = tileAt("fg", x, y)
    if fg == nil then return nil end
    local bg = tileAt("bg", x, y)
    local layer, id
    if fg ~= 0 then
        layer, id = "fg", fg
    elseif includeBg and bg ~= 0 then
        layer, id = "bg", bg
    end
    if not layer or not canBreak(id) then return nil end
    if onlyId and (layer ~= (onlyLayer or "fg") or id ~= onlyId) then return nil end

    -- tunggu sebentar kalau tile baru di-place
    local t = PlacedAt[key]
    if t then
        local age = os.clock() - t
        if age < PLACE_GUARD then task.wait(PLACE_GUARD - age) end
        PlacedAt[key] = nil
    end

    if onlyId and (not Clear.Running or Clear.TargetId ~= onlyId or not Refs.Punch
        or not Refs.World or Refs.World.fg ~= Clear.TargetGrid or Refs.World.name ~= Clear.TargetWorld
        or tileAt(onlyLayer or "fg", x, y) ~= onlyId) then return nil end
    if onlyId then
        local ray = rawget(Refs.World, "raymanOn")
        if type(ray) == "function" then
            local ok, on = pcall(ray)
            if not ok or on then return nil end
        end
    end
    if Refs.Punch then
        State.ScriptPunch = true
        local ok, err = pcall(Refs.Punch, x, y, State.MutePunch or nil, nil)
        State.ScriptPunch = false
        if not ok then
            State.LastAction = "Error pukul: " .. tostring(err)
            return nil
        end
        if State.Visual then Anim.swing(x, y, "punch") end
        if tileAt(layer, x, y) ~= id then
            Drops.brokeAt[key] = os.clock()
            State.Broken += 1
            State.LastAction = "Break " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
            return "broke"
        end
        State.LastAction = "Pukul " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
        return "hit"
    end

    -- Cadangan: hitung pukulan sendiri
    local hc = HitCount[key]
    if not hc or hc.id ~= id or hc.layer ~= layer then
        hc = { id = id, layer = layer, n = 0 }
        HitCount[key] = hc
    end
    hc.n += 1
    sendHitFx(x, y)
    if State.Visual then Anim.swing(x, y, "punch") end
    local need = hitsNeeded(id)
    if hc.n >= need then
        sendSetTile(layer, x, y, 0)
        HitCount[key] = nil
        Drops.brokeAt[key] = os.clock()
        State.Broken += 1
        State.LastAction = "Break " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
        return "broke"
    end
    State.LastAction = "Pukul " .. itemName(id) .. " " .. hc.n .. "/" .. need
    return "hit"
end

---------------------------------------------------------------------
-- AUTO COLLECT
---------------------------------------------------------------------
-- Cara game: World.takeDrop(uid, jumlah) -> server balas jumlahnya -> masuk inventori.
-- Game cuma ambil drop yang disentuh badan; di sini drop diambil langsung.
local TakeDropRemote = WorldRemotes and WorldRemotes:FindFirstChild("TakeDrop") -- game lama saja

-- Fungsi tangan game dipanggil dari fungsi gambar yang terhubung ke RenderStepped:
-- cukup periksa upvalue fungsi-fungsi itu (jauh lebih ringan dari scan getgc).
function Anim.findFast()
    if not getconnections or Anim.fn then return Anim.fn ~= nil end
    for _, name in ipairs({ "RenderStepped", "Heartbeat", "PreRender", "Stepped" }) do
        local okS, sig = pcall(function() return RunService[name] end)
        if okS and sig then
            local ok, conns = pcall(getconnections, sig)
            if ok and type(conns) == "table" then
                for _, c in pairs(conns) do
                    local okf, fn = pcall(Session.connectionFunction, c)
                    if okf and type(fn) == "function" then
                        for _, u in pairs(getUpvalues(fn)) do
                            if type(u) == "function" and Anim.isArmFn(u) then
                                Refs.Arm = u
                                return Anim.bind(u)
                            end
                        end
                    end
                end
            end
        end
    end
    return false
end

-- Cari data world & isi tas cepat: telusuri upvalue fungsi game yang terhubung ke RunService
-- (fungsi gambar / update game memegang tabel-tabel itu). Maks 400 fungsi, tanpa getgc.
function Anim.quickRefs()
    if type(getconnections) ~= "function" then return false end
    local queue, seen, n = {}, {}, 0
    local function push(value)
        local kind = type(value)
        if (kind == "function" or kind == "table") and not seen[value] then
            seen[value] = true
            queue[#queue + 1] = value
        end
    end
    for _, entry in ipairs({
        { RunService, { "RenderStepped", "Heartbeat", "PreRender", "Stepped" } },
        { UserInputService, { "InputBegan", "InputEnded", "TouchTap" } },
    }) do
        for _, name in ipairs(entry[2]) do
            local okS, sig = pcall(function() return entry[1][name] end)
            if okS and sig then
                local ok, conns = pcall(getconnections, sig)
                if ok and type(conns) == "table" then
                    for _, connection in pairs(conns) do
                        local okf, fn = pcall(Session.connectionFunction, connection)
                        if okf then push(fn) end
                    end
                end
            end
        end
    end
    -- World/tas bisa ditemukan lebih dulu; tetap lanjut sampai fungsi aksi juga ditemukan.
    local i = 1
    while i <= #queue and n < 900 do
        local value = queue[i]
        i, n = i + 1, n + 1
        Anim.consider(value, true)
        if Refs.Inv and Refs.World and Refs.Punch and Refs.SetTile and Refs.State and Refs.Menu then break end
        if type(value) == "function" then
            for _, upvalue in pairs(getUpvalues(value)) do push(upvalue) end
        elseif value ~= ItemDB and value ~= Session.ItemDBSource and value ~= InventoryModule then
            -- Fungsi game kadang tersimpan sebagai field controller, bukan langsung di GC.
            for _, member in pairs(value) do
                if type(member) == "function" then push(member) end
            end
        end
        if n % 100 == 0 then task.wait() end
    end
    Refs.ConnectionCount = n
    return Refs.Inv ~= nil
end

-- Cek apakah tabel ini daftar drop game
local function isDropList(t)
    if type(t) ~= "table" or t == Refs.World then return false end
    local first = rawget(t, 1)
    if first == nil then return next(t) == nil end
    return type(first) == "table" and rawget(first, "uid") ~= nil and rawget(first, "frame") ~= nil
end

-- deep = true: boleh pakai getgc (berat, bisa bikin lag / crash di HP) -> hanya dari tombol "Hubungkan ke game"
local function findDropRefs(deep)
    -- 0) fungsi game World.dropList(): daftar drop yang sama untuk semua world (paling ringan)
    local w0 = Refs.World
    local dl = w0 and rawget(w0, "dropList")
    if type(dl) == "function" then
        local okl, l = pcall(dl)
        if okl and isDropList(l) then
            if Drops.list ~= l then Drops.update = nil end
            Drops.list = l
            -- v5.9.0: fungsi update (kurangi / hapus drop) juga wajib dicari. Dulu langsung
            -- return di sini, jadi Drops.update kosong -> drop hasil mode Remote tidak dihapus.
            if not Drops.update then Drops.findUpdate() end
            return true
        end
    end
    if Drops.list and not deep then return true end -- yang lama masih dipakai
    Drops.list, Drops.update = nil, nil
    -- 1) dari fungsi World.dropTaken (isinya: daftar drop + fungsi update)
    local wd = Refs.World and rawget(Refs.World, "dropTaken")
    if type(wd) == "function" then
        for _, u in pairs(getUpvalues(wd)) do
            if not Drops.list and isDropList(u) then
                Drops.list = u
            elseif not Drops.update and type(u) == "function" then
                Drops.update = u
            end
        end
    end
    -- 2) dari handler DropTaken game
    local ev = WorldRemotes and WorldRemotes:FindFirstChild("DropTaken")
    if not Drops.list and ev and getconnections then
        local ok, conns = pcall(getconnections, ev.OnClientEvent)
        if ok and type(conns) == "table" then
            for _, c in pairs(conns) do
                local okf, fn = pcall(Session.connectionFunction, c)
                if okf and type(fn) == "function" then
                    for _, u in pairs(getUpvalues(fn)) do
                        if not Drops.list and isDropList(u) then
                            Drops.list = u
                        elseif not Drops.update and type(u) == "function" then
                            Drops.update = u
                        end
                    end
                end
                if Drops.list then break end
            end
        end
    end
    -- 3) cadangan: cari lewat getgc (hanya kalau diminta: berat)
    if not Drops.list and deep and type(getgc) == "function" then
        local ok, objects = pcall(getgc, true)
        if not ok or type(objects) ~= "table" then ok, objects = pcall(getgc) end
        for _, v in pairs(ok and type(objects) == "table" and objects or {}) do
            if type(v) == "table" then
                local e = rawget(v, 1)
                if type(e) == "table" and rawget(e, "uid") ~= nil and rawget(e, "frame") ~= nil
                    and rawget(e, "born") ~= nil then
                    Drops.list = v
                    break
                end
            end
        end
    end
    return Drops.list ~= nil
end

-- Cari fungsi game yang mengurangi / menghapus drop (dipakai World.dropTaken).
-- Ciri: upvalue World.dropTaken, dan fungsi itu sendiri memegang daftar drop yang sama.
function Drops.findUpdate()
    local w, list = Refs.World, Drops.list
    local wd = w and rawget(w, "dropTaken")
    if type(wd) ~= "function" or not list then return false end
    for _, u in pairs(getUpvalues(wd)) do
        if type(u) == "function" then
            for _, uu in pairs(getUpvalues(u)) do
                if rawequal(uu, list) then
                    Drops.update = u
                    return true
                end
            end
        end
    end
    return false
end

-- Terapkan hasil ambil drop ke tampilan, sama seperti game:
--   sisa > 0 -> angka drop dikurangi; sisa 0 -> keluar dari daftar + frame dihapus.
-- Tanpa ini, loop gambar game menampilkan drop lagi (flown di-reset saat badan tidak menyentuh).
function Drops.applyTaken(d, left)
    local list = Drops.list
    if not list or not table.find(list, d) then return end
    if not Drops.update then Drops.findUpdate() end
    if Drops.update then
        local ok = pcall(Drops.update, d, left)
        if ok then
            if left > 0 then
                d.flown = nil
                if typeof(d.frame) == "Instance" then pcall(function() d.frame.Visible = not d.culled end) end
            end
            return
        end
    end
    -- cadangan manual (fungsi game tidak ketemu)
    d.n = left
    if left > 0 then
        pcall(function()
            if d.setGem then d.setGem(left) elseif d.count then d.count:set(left > 1 and tostring(left) or "") end
        end)
        d.flown = nil
        if typeof(d.frame) == "Instance" then pcall(function() d.frame.Visible = not d.culled end) end
    else
        local i = table.find(list, d)
        if i then table.remove(list, i) end
        if typeof(d.frame) == "Instance" then pcall(function() d.frame:Destroy() end) end
    end
end

local function takeDrop(d)
    local worldTake = Refs.World and rawget(Refs.World, "takeDrop")
    if type(worldTake) ~= "function" and not TakeDropRemote then return false end
    if d.taking or d.pending or d.display or (d.n or 0) <= 0 then return false end
    -- drop yang kamu buang sendiri belum boleh dipungut lagi (aturan game), kecuali gems
    if d.armed == false and d.id ~= 112 then return false end
    local now = os.clock()
    if DropFailUntil[d.uid] and now < DropFailUntil[d.uid] then return false end

    local amount = d.n
    if d.id ~= 112 and Refs.Inv then -- 112 = gems, tidak makan slot
        local okr, room = pcall(function() return Refs.Inv:room(d.id) end)
        if okr and type(room) == "number" then amount = math.min(amount, room) end
    end
    if amount <= 0 then -- inventori penuh: coba lagi 1 detik lagi
        DropFailUntil[d.uid] = now + 1
        local last = Hook.LastFull[d.id]
        if not last or now - last > 120 then
            Hook.LastFull[d.id] = now
            Hook.send("full", "Inventori penuh: " .. itemName(d.id) .. " tidak bisa diambil lagi")
        end
        return false
    end

    d.taking = true -- cegah diambil dobel
    -- langsung hilang dari layar selama menunggu jawaban server.
    -- Tidak pakai d.flown: loop gambar game me-reset flown + memunculkan drop lagi
    -- tiap frame kalau badan tidak menyentuhnya (mode Remote = ambil dari jauh).
    if typeof(d.frame) == "Instance" then pcall(function() d.frame.Visible = false end) end
    local ok, taken
    if type(worldTake) == "function" then
        ok, taken = pcall(worldTake, d.uid, amount) -- cara game baru
    else
        ok, taken = pcall(TakeDropRemote.InvokeServer, TakeDropRemote, d.uid, amount)
    end
    d.taking = false

    if not (ok and type(taken) == "number" and taken > 0) then
        State.CollectFail += 1
        d.refused = os.clock() -- tanda ditolak, sama seperti game
        d.failN = (d.failN or 0) + 1
        DropFailUntil[d.uid] = os.clock() + math.min(8, d.failN) -- 1, 2, 3.. detik (yang terus ditolak makin jarang)
        d.flown = nil
        if typeof(d.frame) == "Instance" then pcall(function() d.frame.Visible = not d.culled end) end
        return false
    end
    DropFailUntil[d.uid] = nil

    if d.id == 112 then
        if Refs.Gems then pcall(Refs.Gems.addGems, taken) end
    elseif Refs.Inv then
        pcall(function() Refs.Inv:add(d.id, taken) end)
    end
    Drops.applyTaken(d, math.max(0, (d.n or 0) - taken)) -- kurangi / hapus drop seperti game
    State.Collected += taken
    Stats.Items[d.id] = (Stats.Items[d.id] or 0) + taken
    State.LastAction = "Collect " .. itemName(d.id) .. " x" .. taken
    return true
end

local function inTile(t, x, y)
    return x >= t.x - 0.15 and x < t.x + 1.15 and y >= t.y - 0.15 and y < t.y + 1.15
end

-- ---------- Collector cepat ----------
-- Periksa drop di worker tunggal dengan anggaran waktu kecil. Pengambilan tetap
-- paralel, tetapi satu tumpukan besar tidak membuat ribuan task dalam satu frame.
--   Auto Farm  : drop di tile yang dipilih di Grid
--   Clear / Farmer : drop di sekitar karakter
local OffsetParse = {}
local nextDropScan = 0

local function canTry(d, now)
    if type(d) ~= "table" or d.taking or (d.n or 0) <= 0 or type(d.x) ~= "number" then return false end
    if d.armed == false and d.id ~= 112 then return false end
    for _, zone in ipairs(AutoDrop.Zones) do
        if zone.world == (Refs.World and rawget(Refs.World, "name")) and zone.id == d.id
            and math.abs(d.x - zone.x) <= 2.5 and math.abs(d.y - zone.y) <= 2.5 then return false end
    end
    local fail = DropFailUntil[d.uid]
    return not (fail and now < fail)
end

-- Drop TIDAK diambil lewat remote oleh script: drop terambil oleh game sendiri saat badan
-- menyentuhnya (fisika game, seperti main manual). Di sini cuma cari daftar drop & hitung
-- drop yang terambil di dekat badan (untuk status).
-- Mode Remote (cara lama): drop di tile grid / di sekitar karakter diambil lewat fungsi ambil-drop game
function Drops.remoteTick(list, s)
    if Clear.Running and Clear.TargetId and not State.WorldBreakCollect then return end
    local offs = farmOffsets()
    local farmArea = (State.AutoCollect or State.Override ~= nil) and next(offs) ~= nil
    local nearArea = (Clear.Running and (Clear.TargetId and State.WorldBreakCollect or not Clear.TargetId and Clear.Collect)) or (Farmer.Running and Farmer.Collect)
        or Pabrik.Running or Build.Running
    if not farmArea and not nearArea then return end
    local cx, cy = s.x, s.y - 0.475
    local ptx, pty = getPlayerTile()
    local now = os.clock()
    local R = (State.CollectRadius or 3) + 0.2
    local world, budget, targets, scheduled = Refs.World, { next = os.clock() + 0.001 }, {}, 0
    if farmArea and ptx then
        for key in pairs(offs) do
            local o = OffsetParse[key]
            if not o then
                local dx, dy = string.match(key, "^(-?%d+),(-?%d+)$")
                o = { tonumber(dx), tonumber(dy) }
                OffsetParse[key] = o
            end
            if o[1] and o[2] then targets[#targets + 1] = { x = ptx + o[1], y = pty + o[2] } end
        end
    end
    local z = Pabrik.Zone -- tempat drop pabrik tidak ikut diambil lagi
    if z and z.world ~= (Refs.World and rawget(Refs.World, "name")) then z = nil end
    for i = #list, 1, -1 do
        local d = list[i]
        if canTry(d, now) and not (z and math.abs(d.x - z.x) <= 2.5 and math.abs(d.y - z.y) <= 2.5) then
            local hit = nearArea and math.abs(d.x - cx) <= R and math.abs(d.y - cy) <= R
            if not hit and farmArea and ptx then
                for _, tile in ipairs(targets) do
                    if inTile(tile, d.x, d.y) then
                        hit = true
                        break
                    end
                end
            end
            if hit then
                task.spawn(takeDrop, d)
                scheduled += 1
                if scheduled >= 8 then break end
            end
        end
        Session.scanStep(budget, #list - i + 1)
        if not alive() or Drops.list ~= list or Refs.World ~= world or AutoDrop.Busy
            or (Clear.Running and Clear.TargetId and not State.WorldBreakCollect) then return end
    end
end

local function collectTick()
    if AutoDrop.Busy then return end
    if Clear.Running and Clear.TargetId and not State.WorldBreakCollect then
        Drops.seen = nil
        return
    end
    local busy = State.AutoCollect or State.Override ~= nil or (Clear.Running and Clear.Collect)
        or (Clear.Running and Clear.TargetId and State.WorldBreakCollect)
        or (Farmer.Running and Farmer.Collect) or Pabrik.Running or Build.Running
    if not busy then return end
    local tnow = os.clock()
    if tnow < (Drops.nextTick or 0) then return end -- 5-10x per detik cukup (hemat FPS)
    Drops.nextTick = tnow + ((State.CollectMode == "Remote") and 0.1 or 0.2)
    local list = Drops.list
    if not list then
        local now = os.clock()
        if now >= nextDropScan then -- cari daftar drop paling sering tiap 5 detik
            nextDropScan = now + 5
            findDropRefs()
        end
        return
    end
    local ok, s = false, nil
    if Refs.State then ok, s = pcall(Refs.State) end
    if not (ok and type(s) == "table" and type(s.x) == "number") then return end
    if State.CollectMode == "Remote" then
        Drops.remoteTick(list, s) -- jumlah terambil dihitung oleh takeDrop
        return
    end
    local cx, cy = s.x, s.y - 0.475
    local seen = {}
    local previous = Drops.seen
    local membership = previous and next(previous) and {} or nil
    local world, budget = Refs.World, { next = os.clock() + 0.001 }
    for index, d in ipairs(list) do
        if membership then membership[d] = true end
        if type(d) == "table" and type(d.x) == "number" and math.abs(d.x - cx) <= 1.5 and math.abs(d.y - cy) <= 1.5 then
            seen[d] = d.n or 0
        end
        Session.scanStep(budget, index)
        if not alive() or Drops.list ~= list or Refs.World ~= world then Drops.seen = nil return end
    end
    for d, n in pairs(previous or {}) do
        if seen[d] == nil and not membership[d] and d.id and n > 0 then -- hilang di dekat badan = terambil
            State.Collected += n
            Stats.Items[d.id] = (Stats.Items[d.id] or 0) + n
        end
    end
    Drops.seen = seen
end

task.spawn(function()
    while alive() do
        local ok, err = pcall(collectTick)
        if not ok and os.clock() - (Drops.LastErrorAt or -10) >= 10 then
            Drops.LastErrorAt = os.clock()
            warn("[n4th] Collect: " .. tostring(err))
        end
        task.wait(0.1)
    end
end)

-- Tunggu sebentar sampai drop di tile ini terambil (supaya tidak tertimpa block baru)
local function waitTileDrops(t, maxSec)
    local list = Drops.list
    if not list then return end
    local t0 = os.clock()
    while os.clock() - t0 < maxSec and alive() do
        local now, busy = os.clock(), false
        for _, d in ipairs(list) do
            if type(d) == "table" and type(d.x) == "number" and (d.n or 0) > 0 and inTile(t, d.x, d.y)
                and (d.taking or canTry(d, now)) then
                busy = true
                break
            end
        end
        if not busy then return end
        task.wait()
    end
end

-- Tunggu sampai drop yang menempel badan selesai dipungut game (sentuhan, bukan remote)
local function waitNearDrops(maxSec)
    local list = Drops.list
    if not list then return end
    task.wait(0.15) -- drop baru muncul sedikit terlambat
    local t0 = os.clock()
    while os.clock() - t0 < maxSec and alive() do
        local ok, s = false, nil
        if Refs.State then ok, s = pcall(Refs.State) end
        if not (ok and type(s) == "table" and type(s.x) == "number") then return end
        local cx, cy = s.x, s.y - 0.475
        local busy = false
        for _, d in ipairs(list) do
            -- sama dengan aturan game: < 0.6 tile mendatar & setinggi badan (kaki s.y, kepala s.y - 0.95)
            if type(d) == "table" and type(d.x) == "number" and (d.n or 0) > 0 and d.armed ~= false
                and math.abs(d.x - s.x) < 0.6 and d.y + 0.3 > s.y - 0.95 and d.y - 0.3 < s.y then
                local room = true
                if d.id ~= 112 and Refs.Inv then -- inventori penuh: tidak akan terpungut
                    local okr, r = pcall(function() return Refs.Inv:room(d.id) end)
                    if okr and type(r) == "number" and r <= 0 then room = false end
                end
                if room then
                    busy = true
                    break
                end
            end
        end
        if not busy then return end
        task.wait()
    end
end

---------------------------------------------------------------------
-- STATUS
---------------------------------------------------------------------
local function offsetsText()
    local list = {}
    for _, o in ipairs(sortedOffsets()) do
        table.insert(list, "(" .. o.dx .. "," .. o.dy .. ")")
    end
    return #list > 0 and table.concat(list, " ") or "-"
end

local lastStatusText = nil

local function updateStatus()
    if not UI.Status then return end
    local px, py = getPlayerTile()
    local sel = State.SelectedId
    local txt = "Status   : " .. (State.Running and "JALAN" or "BERHENTI")
        .. "\nBlock    : " .. (sel and (itemName(sel) .. " x" .. invCount(sel)) or "-")
        .. "\nKarakter : " .. (px and ("(" .. px .. "," .. py .. ")") or "tidak di world")
        .. "\nTile     : " .. offsetsText()
        .. "\nPlace/Break/Collect : " .. State.Placed .. " / " .. State.Broken .. " / " .. State.Collected
        .. (State.CollectFail > 0 and (" (ditolak " .. State.CollectFail .. ")") or "")
        .. (State.Dropped > 0 and ("\nDrop seed: di-drop " .. State.Dropped) or "")
        .. "\nAksi     : " .. State.LastAction
    if txt == lastStatusText then return end
    lastStatusText = txt
    task.defer(function()
        pcall(function() UI.Status:SetDesc(txt) end)
    end)
end

---------------------------------------------------------------------
-- MODE LITE (matikan particle + suara)
---------------------------------------------------------------------
local DummyLabel = setmetatable({}, { __index = function() return 0 end, __newindex = function() end })
local DummyParticle = setmetatable({ l = DummyLabel, k = {} }, { __index = function() return 0 end, __newindex = function() end })
local NullSound
NullSound = setmetatable({}, {
    __index = function() return NullSound end,
    __newindex = function() end,
    __call = function() return NullSound end,
})
local LiteSaved = {}

local function liteOverride(tbl, key, repl)
    if type(tbl) == "table" and type(rawget(tbl, key)) == "function" then
        table.insert(LiteSaved, { tbl, key, rawget(tbl, key) })
        tbl[key] = repl
    end
end

local function setLite(on)
    State.LiteMode = on
    if on then
        if #LiteSaved == 0 then
            if ParticlesOk then liteOverride(ParticlesModule, "spawn", function() return DummyParticle end) end
            if SfxOk then
                liteOverride(SfxModule, "play", function() return NullSound end)
                liteOverride(SfxModule, "playAt", function() return NullSound end)
            end
        end
        for _, p in ipairs(Refs.Particles) do
            pcall(function()
                for _, e in ipairs(p.live) do
                    if typeof(e.l) == "Instance" then e.l.Visible = false end
                end
            end)
        end
    else
        for _, s in ipairs(LiteSaved) do
            pcall(function() s[1][s[2]] = s[3] end)
        end
        table.clear(LiteSaved)
    end
end

---------------------------------------------------------------------
-- MISC: walkspeed, infinite jump, fly + tembus block
---------------------------------------------------------------------
-- Infinite jump: game dibuat mengira ada Antigravity Generator, jadi bisa lompat di udara
local OrigJammerOn = nil
local function infJumpWrapper(id, ...)
    -- dimatikan saat Clear / Farmer jalan (lompat harus normal)
    if Misc.InfJump and id == 4992 and not AutoInput.active then
        return true
    end
    if OrigJammerOn then return OrigJammerOn(id, ...) end
    return false
end

local function hookJammer()
    local w = Refs.World
    if not w then return end
    local cur = rawget(w, "jammerOn")
    if cur == infJumpWrapper or type(cur) ~= "function" then return end
    OrigJammerOn = cur
    w.jammerOn = infJumpWrapper
end

local function unhookJammer()
    local w = Refs.World
    if w and rawget(w, "jammerOn") == infJumpWrapper and OrigJammerOn then
        w.jammerOn = OrigJammerOn
    end
end

local function setInfJump(on)
    Misc.InfJump = on
    if on then hookJammer() else unhookJammer() end
end

local function setGhost(on)
    Misc.Ghost = on
    if not on then
        Misc.UpHeld, Misc.DownHeld = false, false
        if Refs.World then Refs.World.ghost = false end
    end
    if UI.FlyPad then UI.FlyPad.Enabled = on end
end

local function setSpeed(pct)
    Misc.Speed = math.clamp(math.floor(tonumber(pct) or 100), 50, 500)
    if Misc.Speed == 100 and Refs.World then Refs.World.speedScale = 1 end
end

-- Tombol gerak game dibaca dari WorldMenu.isDown. Dibungkus supaya
-- tombol ▲/▼ Fly bisa dipakai, dan Clear / Farmer bisa "menekan" tombol sendiri.
local OrigIsDown = nil
local function isDownWrapper(saved, key, ...)
    if AutoInput.active then
        if key == "keyLeft" then return AutoInput.left end
        if key == "keyRight" then return AutoInput.right end
        if key == "keyJump" then return AutoInput.jump end
        if key == "keyDown" then return AutoInput.down end
    end
    if Misc.Ghost then
        if key == "keyDown" and Misc.DownHeld then return true end
        if key == "keyJump" and Misc.UpHeld then return true end
    end
    return OrigIsDown(saved, key, ...)
end

if MenuModOk and type(MenuModule) == "table" and type(rawget(MenuModule, "isDown")) == "function" then
    OrigIsDown = rawget(MenuModule, "isDown")
    MenuModule.isDown = isDownWrapper
end

-- Pasang walkspeed & fly tiap frame (game bisa menimpanya)
table.insert(Connections, RunService.Heartbeat:Connect(function()
    local w = Refs.World
    if not w or not alive() then return end
    if Misc.Speed ~= 100 then w.speedScale = Misc.Speed / 100 end
    if Misc.Ghost and w.ghost ~= true then w.ghost = true end
end))

---------------------------------------------------------------------
-- FARM LOOP: place semua dulu, baru break satu per satu
---------------------------------------------------------------------
local stopFarm

local function waitMs(ms)
    task.wait(math.max(ms or 0, 10) / 1000)
    return State.Running and alive()
end

local function validate()
    local doPlace = farmMode() ~= "Break saja"
    if not Refs.World then return "Data world belum ketemu. Tekan 'Hubungkan ke game'" end
    if next(farmOffsets()) == nil then return "Pilih tile dulu di Grid Tile" end
    if not getPlayerTile() then return "Kamu belum masuk world" end
    if doPlace and not farmBlock() then return "Pilih block dari inventori" end
    return nil
end

-- Rayman's Fist sedang dipakai? (fungsi asli game)
local function raymanOn()
    local w = Refs.World
    local f = w and rawget(w, "raymanOn")
    if type(f) ~= "function" then return false end
    local ok, on = pcall(f)
    return ok and on == true
end

-- Cari 2-3 tile target yang segaris dari karakter (8 arah, jarak 1-3),
-- sama seperti pukulan Rayman di game.
local RAY_DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local function raymanLine(px, py, active)
    local byKey = {}
    for _, a in ipairs(active) do byKey[a.x .. "," .. a.y] = a end
    local best, bestDir = nil, nil
    for _, d in ipairs(RAY_DIRS) do
        local line = {}
        for i = 1, 3 do
            local a = byKey[(px + d[1] * i) .. "," .. (py + d[2] * i)]
            if a then line[#line + 1] = a end
        end
        if #line >= 2 and #line > (best and #best or 0) then best, bestDir = line, d end
    end
    return best, bestDir
end

-- Kabarkan gerakan Rayman ke server (paket yang sama dengan game saat pukulan Rayman)
local function raymanAct(dir)
    local ok, s = pcall(Refs.State)
    if not ok or type(s) ~= "table" or not s.x then return end
    if NetOk and type(Net) == "table" and Net.act then
        pcall(Net.act.send, { kind = 4, x = s.x + dir[1], y = s.y - 0.475 + dir[2] })
    end
end

local function farmLoop(runId)
    local lastStatus = 0
    while State.Running and alive() and State.RunId == runId do
        if State.DropPause then -- sedang pergi drop seed
            task.wait(0.2)
            continue
        end
        local doPlace = farmMode() ~= "Break saja"
        local doBreak = farmMode() ~= "Place saja"

        local px, py = getPlayerTile()
        if not px then
            stopFarm("Karakter tidak ditemukan (keluar world?)")
            return
        end

        local tiles = {}
        for _, o in ipairs(sortedOffsets()) do
            tiles[#tiles + 1] = { x = px + o.dx, y = py + o.dy }
        end

        local acted, outOfBlock = false, false

        -- 0) Ambil drop di semua tile grid dengan sentuhan badan (sekali sapu), lalu balik ke posisi
        if (State.AutoCollect or State.Override) and not State.DropPause then
            Drops.waitSpawn(tiles) -- drop pecahan barusan datang dari server: tunggu muncul dulu
            if State.CollectMode == "Remote" then
                for _, t in ipairs(tiles) do waitTileDrops(t, 0.4) end -- diambil lewat remote (collectTick)
            elseif Drops.touchAll then
                Drops.touchAll(tiles, px, py)
            end
        end

        -- 1) Place semua tile kosong
        if doPlace then
            for _, t in ipairs(tiles) do
                if not State.Running or State.DropPause then break end
                local r = tryPlace(t.x, t.y)
                if r == "habis" then
                    outOfBlock = true
                    break
                elseif r == "place" then
                    acted = true
                    if not waitMs(State.PlaceMs) then break end
                end
            end
        end

        -- 2) Pukul tile sampai habis (block depan lalu background).
        --    Server hanya terima 1 pukulan tiap ~0.22 detik (tangan biasa), jadi multi target
        --    = beberapa tile dipukul BERGANTIAN (sama seperti 2 jari). Semua tile benar-benar pecah.
        --    Pakai Rayman's Fist: 2-3 tile segaris dipukul sekali jalan (seperti Rayman asli).
        if doBreak then
            local K = math.clamp(math.floor(State.MultiTarget or 1), 1, 5)
            local nextI, active = 1, {}
            while State.Running and alive() and not State.DropPause do
                while #active < K and nextI <= #tiles do
                    local t = tiles[nextI]
                    nextI += 1
                    active[#active + 1] = { x = t.x, y = t.y, n = 0 }
                end
                if #active == 0 then break end

                -- pilih tile yang dipukul sekarang
                local hits, rayDir = nil, nil
                if K > 1 and raymanOn() then
                    hits, rayDir = raymanLine(px, py, active)
                end
                if not rayDir then hits = { active[1] } end -- giliran depan antrian

                local t0 = os.clock()
                if rayDir then raymanAct(rayDir) end
                local hit, broke = false, false
                for i, a in ipairs(hits) do
                    if not State.Running then break end
                    if i > 1 then task.wait(0.05) end -- jarak antar tile seperti animasi Rayman
                    local r = tryBreak(a.x, a.y)
                    a.n += 1
                    if r then hit, acted = true, true end
                    if r == "broke" then broke = true end
                    -- selesai kalau kosong / tidak bisa dipecah / sudah habis sampai background
                    if r == nil or a.n > 80 or (r == "broke" and not breakableAt(a.x, a.y)) then
                        a.done = true
                    end
                    a.used = true
                end

                -- tile yang barusan dipukul pindah ke belakang antrian (bergantian)
                local nextActive = {}
                for _, a in ipairs(active) do
                    if not a.done and not a.used then nextActive[#nextActive + 1] = a end
                end
                for _, a in ipairs(hits) do
                    a.used = nil
                    if not a.done then nextActive[#nextActive + 1] = a end
                end
                active = nextActive

                if hit then
                    local gap = State.BreakMs / 1000
                    if rayDir then gap = math.max(gap, 0.35) end -- jeda Rayman asli
                    local rest = gap - (os.clock() - t0)
                    if rest > 0.005 then task.wait(rest) end
                    if not (State.Running and alive()) then break end
                end
                -- drop diambil otomatis oleh collector cepat
                if broke and State.AfterBreakMs > 0 then task.wait(State.AfterBreakMs / 1000) end
            end
        end

        if not State.Running or not alive() then break end
        if State.DropPause then continue end

        if not acted then
            local sel = farmBlock()
            if outOfBlock or (doPlace and sel and invCount(sel) <= 0) then
                stopFarm("Block " .. itemName(sel) .. " di inventori habis")
                return
            end
            if not waitMs(State.BreakMs) then break end
        end

        State.Cycles += 1
        if os.clock() - lastStatus > 1 then
            lastStatus = os.clock()
            updateStatus()
        end
    end
    updateStatus()
end

local function setRunningVisual()
    if State.Override then return end -- dijalankan Pabrik: tombol Auto Farm tidak diubah
    if UI.FarmToggle then pcall(function() UI.FarmToggle:Set(State.Running) end) end
    if UI.GridStart and UI.GridMode == "farm" then
        UI.GridStart.Text = State.Running and "STOP" or "START"
        UI.GridStart.BackgroundColor3 = State.Running and Color3.fromRGB(200, 60, 60) or Color3.fromRGB(46, 160, 90)
    end
end

stopFarm = function(reason)
    State.Running = false
    setRunningVisual()
    if reason and not State.Quiet then
        notify("Auto Farm berhenti", reason, 4)
        Hook.send("stop", "Auto Farm berhenti: " .. reason)
    end
    updateStatus()
end

-- Auto Farm, Clear & Farmer tidak boleh jalan bersamaan
local stopClear, stopFarmer

local function startFarm()
    if State.Running then return end
    if AutoDrop.Busy then notify("Auto Drop", "Tunggu perjalanan drop selesai", 3) return end
    local err = validate()
    if err then
        stopFarm(err)
        return
    end
    if Pabrik.Running and Pabrik.stop then Pabrik.stop("Dihentikan karena Auto Farm dimulai") end
    if Build.Running and Build.stop then Build.stop("Dihentikan karena Auto Farm dimulai") end
    if Clear.Running and stopClear then stopClear("Dihentikan karena Auto Farm dimulai") end
    if Farmer.Running and stopFarmer then stopFarmer("Dihentikan karena Auto Farm dimulai") end
    table.clear(HitCount)
    table.clear(PlacedAt)
    State.DropPause = false
    State.Running = true
    State.RunId = (State.RunId or 0) + 1
    setRunningVisual()
    updateStatus()
    task.spawn(farmLoop, State.RunId)
end


-- Fungsi untuk UI dikumpulkan di sini (Luau batasi 200 variabel per file)
local Auto = {}
do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
---------------------------------------------------------------------
-- GERAK OTOMATIS (dipakai Clear World & Farmer)
---------------------------------------------------------------------
-- Cara kerja:
--   - Jalan dicari pakai A* sesuai fisika game (jalan, jatuh, lompat naik 1-3 tile).
--   - Karakter digerakkan dengan "menekan" tombol, sama seperti main biasa.
--   - Tidak pakai fly / noclip karena server me-rollback.
--   - Kalau tidak ada pijakan, taruh block dari inventori (jembatan / tangga).
local floor, abs = math.floor, math.abs

local Move = { Placed = 0 }  -- jumlah block pijakan yang dipasang
local BadEdge = {}           -- jalur yang barusan gagal (dihindari dulu)
local ClearFail, FarmerFail = {}, {}
local BreakTimes = {}        -- tile yang terus balik lagi setelah pecah
local Reach = nil            -- daftar tile yang bisa dijangkau (cache)

local function autoOn()
    if Move.Homing and Move.HomingLive and not Move.HomingLive() then return false end
    return (Clear.Running or Farmer.Running or Pabrik.Running or Build.Running or Move.Homing) and alive()
end

local function setMoveStatus(text)
    if AutoDrop.Busy then
        AutoDrop.Status = text
    elseif Clear.Running then
        Clear.Status = text
    elseif Farmer.Running then
        Farmer.Status = text
    elseif Build.Running then
        Build.Status = text
    elseif Pabrik.Running then
        Pabrik.Status = text
    end
end

local function skipTile(tbl, idx, sec)
    tbl[idx] = os.clock() + (sec or 30)
end

local function skipped(tbl, idx, now)
    local t = tbl[idx]
    if not t then return false end
    if (now or os.clock()) >= t then
        tbl[idx] = nil
        return false
    end
    return true
end

local function skippedCount(tbl)
    local n, now = 0, os.clock()
    for _, t in pairs(tbl) do
        if t > now then n += 1 end
    end
    return n
end

local function hudRange(name, def)
    local f = Refs.Hud and Refs.Hud[name]
    if type(f) == "function" then
        local ok, r = pcall(f)
        if ok and type(r) == "number" and r > 0 then return r end
    end
    return def
end

local function punchReach() return hudRange("punchRange", 2.5) end
local function buildReach() return hudRange("buildRange", 2.5) end

local function playerState()
    if not Refs.State then return nil end
    local ok, s = pcall(Refs.State)
    if ok and type(s) == "table" and type(s.x) == "number" and type(s.y) == "number" and s.active ~= false then
        return s
    end
    return nil
end

local function fgIdAt(x, y)
    local w = Refs.World
    local row = w and w.fg[y]
    return (row and row[x]) or 0
end

local function fgItemAt(x, y)
    local id = fgIdAt(x, y)
    if id ~= 0 then return ItemDB[id] end
    return nil
end

-- Tile padat? (sama dengan cek tabrakan game)
local function solidAt(x, y)
    local w = Refs.World
    if not w then return true end
    if x < 0 or x >= w.w or y >= w.h then return true end
    if y < 0 then return false end
    local it = fgItemAt(x, y)
    if not it then return false end
    if it.combiner then
        local ok, shut = pcall(w.combinerShut, x, y)
        return (not ok) or (shut and true or false)
    end
    if it.vip then -- pintu VIP: padat kalau kamu tidak punya akses
        local ok, may = pcall(w.vipMay, x, y)
        return not (ok and may)
    end
    if it.entrance then
        local sw = w.switches and w.switches[y * w.w + x]
        if it.gate then
            return not (sw and sw.off == true)
        end
        if sw and sw.public then return false end
        local ok, may = pcall(function() return w.areas.mayBuild(w.lock, x, y) end)
        return not (ok and may)
    end
    return it.solid and true or false
end

-- Tile berbahaya (lava, duri, laser)
local function hazardAt(x, y)
    local it = fgItemAt(x, y)
    return it ~= nil and (it.deadly or it.hurts or it.laser) and true or false
end

local function platformAt(x, y)
    local it = fgItemAt(x, y)
    return it ~= nil and it.platform and true or false
end

local function openAt(x, y)
    return not solidAt(x, y) and not hazardAt(x, y)
end

-- Ada pijakan aman di bawah tile ini?
local function realSupport(x, y)
    if hazardAt(x, y + 1) then return false end
    if solidAt(x, y + 1) or platformAt(x, y + 1) then return true end
    -- FIX: tile yang terbukti dipijak karakter (grounded) dianggap lantai, walau data item
    -- tidak menandainya solid (mis. Dirt / rumput permanen di world ini).
    local lid = fgIdAt(x, y + 1)
    return lid ~= 0 and Clear.Learned[lid] == true
end

-- Target kelihatan dari badan? (tidak terhalang lantai / atap padat di antaranya)
-- Panen lewat block bisa, tapi drop-nya jatuh di balik block dan tidak terambil.
function Move.los(nx, ny, tx, ty)
    if ty - ny >= 2 then
        for y = ny + 1, ty - 1 do
            if solidAt(tx, y) then return false end
        end
    elseif ny - ty >= 2 then
        for y = ty + 1, ny - 1 do
            if solidAt(tx, y) then return false end
        end
    end
    return true
end

-- Tile masuk jangkauan? (bentuk kotak di sekitar badan)
local function stateReaches(s, tx, ty, R)
    return abs(tx + 0.5 - s.x) <= R and abs(ty + 0.5 - (s.y - 0.475)) <= R
end

-- Boleh pecah di sini? (cek lock)
local function canWorkAt(x, y)
    local w = Refs.World
    local ok, res = pcall(function()
        if w.areas and type(w.areas.mayBuild) == "function" and not w.areas.mayBuild(w.lock, x, y) then
            return false
        end
        if type(w.builderOk) == "function" and not w.builderOk(x, y, false) then
            return false
        end
        return true
    end)
    return (not ok) or res
end

-- ---------- Block pijakan ----------
local function scaffoldId()
    local id, use
    if Clear.Running then
        id, use = Clear.ScaffoldId, Clear.UseBlock and not Clear.TargetId
    elseif Farmer.Running then
        id, use = Farmer.ScaffoldId, Farmer.UseBlock
    end -- Bangun Lahan tidak pakai pijakan (jalan di atas baris yang sedang dibangun)
    if use and id and invCount(id) > 0 then return id end
    return nil
end

-- Boleh taruh block di sini? (kosong + izin bangun)
local function placeOk(x, y)
    local w = Refs.World
    if not w or x < 0 or y < 0 or x >= w.w or y >= w.h then return false end
    if fgIdAt(x, y) ~= 0 then return false end
    local ok, res = pcall(function()
        if w.areas and type(w.areas.canEdit) == "function" and not w.areas.canEdit(x, y) then return false end
        if type(w.builderOk) == "function" and not w.builderOk(x, y, true) then return false end
        return true
    end)
    return (not ok) or res
end

local function placeScaffold(x, y)
    local id = scaffoldId()
    if not id or not placeOk(x, y) then return false end
    local s = playerState()
    if not s or not stateReaches(s, x, y, buildReach() - 0.05) then return false end
    sendSetTile("fg", x, y, id) -- place lewat fungsi game
    if Refs.Inv then pcall(function() Refs.Inv:remove(id, 1) end) end
    Move.Placed += 1
    return true
end

local function worldVersion()
    -- berubah tiap ada block / pohon yang berubah, supaya cache jangkauan tidak basi
    return Clear.Broken + Farmer.Harvested + Farmer.Planted + Move.Placed
        + Pabrik.Harvested + Pabrik.Planted + Build.Placed + Build.Harvested + Build.Planted + Build.Dug
        + State.Placed + State.Broken
end

local function startNode(s)
    local ny = floor(s.y - 0.475)
    local nx = floor(s.x)
    if realSupport(nx, ny) then return nx, ny end
    local a, b = floor(s.x - 0.3), floor(s.x + 0.3 - 0.0001)
    for _, c in ipairs({ a, b }) do
        if c ~= nx and realSupport(c, ny) then return c, ny end
    end
    return nx, ny
end

-- ---------- Antrian prioritas untuk A* ----------
local function heapPush(hf, hi, n, f, i)
    n += 1
    local k = n
    while k > 1 do
        local p = k // 2
        if hf[p] <= f then break end
        hf[k], hi[k] = hf[p], hi[p]
        k = p
    end
    hf[k], hi[k] = f, i
    return n
end

local function heapPop(hf, hi, n)
    local top = hi[1]
    local lf, li = hf[n], hi[n]
    hf[n], hi[n] = nil, nil
    n -= 1
    if n > 0 then
        local k = 1
        while true do
            local c = k * 2
            if c > n then break end
            if c < n and hf[c + 1] < hf[c] then c += 1 end
            if lf <= hf[c] then break end
            hf[k], hi[k] = hf[c], hi[c]
            k = c
        end
        hf[k], hi[k] = lf, li
    end
    return top, n
end

-- ---------- A* ----------
-- Cari jalan termurah ke tempat yang bisa memukul salah satu target.
-- Langkah yang bisa dipakai:
--   walk   : geser 1 tile (+ taruh block kalau perlu)
--   fall   : jalan ke pinggir lalu jatuh
--   jump   : lompat naik 1-3 tile
--   gap    : lompati lubang 1-2 tile
--   stair  : tangga lahan: lompat naik 2 lewat lubang ke lorong setinggi 1 tile
--   pillar : lompat lalu taruh block di bawah kaki (naik 1)
local MAX_EXPAND = 8000
local BLOCK_COST = 2

local function reachOffsets(R)
    return floor(R), math.ceil(-R + 0.025), floor(R + 0.025)
end

local function astar(sx, sy, goals, gx, gy, R, useBlock, route)
    local w = Refs.World
    if not w then return nil, false, {} end
    local W, H = w.w, w.h
    local grid, worldName = w.fg, w.name
    local WH = W * H
    local dxm, dyLo, dyHi = reachOffsets(R)
    local oC, sC, bC = {}, {}, {}

    local function open(x, y)
        if x < 0 or x >= W or y >= H then return false end
        if y < 0 then return true end
        local i = y * W + x
        local v = oC[i]
        if v == nil then
            v = openAt(x, y)
            oC[i] = v
        end
        return v
    end

    local function sup(x, y)
        if x < 0 or x >= W or y < 0 or y >= H then return false end
        local i = y * W + x
        local v = sC[i]
        if v == nil then
            v = realSupport(x, y)
            sC[i] = v
        end
        return v
    end

    local function buildable(x, y)
        if not useBlock or x < 0 or x >= W or y < 0 or y >= H then return false end
        local i = y * W + x
        local v = bC[i]
        if v == nil then
            v = placeOk(x, y)
            bC[i] = v
        end
        return v
    end

    local function h(x, y)
        local dx = abs(gx - x) - R
        local dyRaw = gy - y
        local dy = abs(dyRaw) - R
        local vw = (dyRaw < 0) and 1.5 or 0.5
        return (dx > 0 and dx or 0) + vw * (dy > 0 and dy or 0)
    end

    local function isGoal(nx, ny)
        if route and not route.point(nx, ny) then return false end
        -- goals.maxY: tempat berdiri tidak boleh lebih bawah dari ini (Bangun Lahan)
        if goals.maxY and ny > goals.maxY then return false end
        for ty = ny + dyLo, ny + dyHi do
            if ty >= 0 and ty < H then
                local base = ty * W
                for tx = nx - dxm, nx + dxm do
                    -- jangan berdiri tepat di atas target (noSelf: juga jangan di dalam tile target)
                    if tx >= 0 and tx < W and goals[base + tx] and not (tx == nx and ty == ny + 1)
                        and not (goals.noSelf and tx == nx and ty == ny)
                        and not (goals.los and ty - ny >= 2 and not open(tx, ny + 1))
                        and not (goals.los and ny - ty >= 2 and not open(tx, ny - 1)) then
                        return true
                    end
                end
            end
        end
        return false
    end

    local ex, ey, ek, ec, eb = {}, {}, {}, {}, {}
    local n, fromX, fromY = 0, sx, sy
    local function add(x, y, kind, cost, build)
        if route and not route.edge(fromX, fromY, x, y, kind) then return end
        n += 1
        ex[n], ey[n], ek[n], ec[n], eb[n] = x, y, kind, cost, build
    end

    local function expand(x, y)
        n = 0
        fromX, fromY = x, y
        for s = -1, 1, 2 do
            local ax = x + s
            if open(ax, y) then
                if sup(ax, y) then
                    add(ax, y, "walk", 1, false)
                else
                    if buildable(ax, y + 1) then
                        add(ax, y, "walk", 1 + BLOCK_COST, true)
                    end
                    -- jatuh sampai ketemu pijakan
                    local fy = y + 1
                    while fy < H and fy - y <= 40 and open(ax, fy) and not sup(ax, fy) do
                        fy += 1
                    end
                    if fy < H and open(ax, fy) and sup(ax, fy) then
                        add(ax, fy, "fall", 1 + 0.5 * (fy - y), false)
                    end
                    -- lompati lubang 1-2 tile
                    if open(x, y - 1) and open(x, y - 2) then
                        for dist = 2, 3 do
                            local mx = x + (dist - 1) * s
                            if not (open(mx, y) and open(mx, y - 1) and open(mx, y - 2)) then break end
                            if dist == 3 and sup(mx, y) then break end
                            local bx = x + dist * s
                            if open(bx, y - 1) and open(bx, y - 2) then
                                for k = 0, 2 do
                                    if not open(bx, y + k) then break end
                                    if sup(bx, y + k) then
                                        add(bx, y + k, "gap", dist + 0.5 + 0.5 * k, false)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
            -- lompat naik (atas kepala harus kosong)
            for dy = 1, 3 do
                if not open(x, y - dy) then break end
                if open(x, y - dy - 1) and open(ax, y - dy) and sup(ax, y - dy) and open(ax, y - dy - 1) then
                    add(ax, y - dy, "jump", 1 + 1.5 * dy, false)
                end
            end
            -- tangga lahan: naik 1-2 tile ke lorong setinggi 1 tile (atapnya pas di atas kepala,
            -- jadi lompat biasa tidak muat). Rapat ke dinding, lompat, geser masuk di puncak.
            for dy = 1, 2 do
                if open(x, y - 1) and (dy == 1 or open(x, y - 2)) and open(ax, y - dy) and sup(ax, y - dy)
                    and not (open(x, y - dy - 1) and open(ax, y - dy - 1)) then
                    add(ax, y - dy, "stair", 3 + 1.5 * dy, false)
                end
            end
        end
        -- naik 1 pakai block
        if useBlock and open(x, y - 1) and open(x, y - 2) and open(x, y - 3) and buildable(x, y) then
            add(x, y - 1, "pillar", 2 + BLOCK_COST, true)
        end
        return n
    end

    local startI = sy * W + sx
    local g, came, kind, buildOf, closed = { [startI] = 0 }, {}, {}, {}, {}
    local hf, hi, hn = {}, {}, 0
    hn = heapPush(hf, hi, hn, h(sx, sy), startI)
    local expanded = 0
    local now = os.clock()
    local nextSlice, popped = now + 0.001, 0

    while hn > 0 do
        popped += 1
        -- Biaya satu titik berbeda-beda (collision, lock, dan lompatan).
        -- Batasi waktu CPU, bukan menunggu 400 titik selesai sekaligus.
        if popped % 8 == 0 and os.clock() >= nextSlice then
            task.wait()
            if not autoOn() or Refs.World ~= w or w.fg ~= grid or w.name ~= worldName then return nil, false, closed end
            nextSlice = os.clock() + 0.001
        end
        local cur
        cur, hn = heapPop(hf, hi, hn)
        if not closed[cur] then
            closed[cur] = true
            local cx, cy = cur % W, cur // W
            if isGoal(cx, cy) then
                local path = {}
                local i = cur
                while i ~= startI do
                    local p = came[i]
                    path[#path + 1] = {
                        fx = p % W, fy = p // W, x = i % W, y = i // W,
                        kind = kind[i], build = buildOf[i], key = p * WH + i,
                    }
                    i = p
                end
                for left = 1, #path // 2 do
                    local right = #path - left + 1
                    path[left], path[right] = path[right], path[left]
                end
                return path, false, closed
            end
            expanded += 1
            if expanded > MAX_EXPAND then return nil, false, closed end
            local gc = g[cur]
            local cnt = expand(cx, cy)
            for k = 1, cnt do
                local ni = ey[k] * W + ex[k]
                if not closed[ni] then
                    local bad = BadEdge[cur * WH + ni]
                    if not (bad and bad > now) then
                        local ng = gc + ec[k]
                        local old = g[ni]
                        if old == nil or ng < old then
                            g[ni], came[ni], kind[ni], buildOf[ni] = ng, cur, ek[k], eb[k]
                            hn = heapPush(hf, hi, hn, ng + h(ex[k], ey[k]), ni)
                        end
                    end
                end
            end
        end
    end
    return nil, true, closed -- tidak ada jalan sama sekali
end

-- Semua tile yang bisa dijangkau dari area ini
local function reachableTileSet(closed, W, R)
    local set = {}
    local dxm, dyLo, dyHi = reachOffsets(R)
    local n = 0
    local w, grid = Refs.World, Refs.World and Refs.World.fg
    local budget = { next = os.clock() + 0.001 }
    for i in pairs(closed) do
        local x, y = i % W, i // W
        for dy = dyLo, dyHi do
            local ty = y + dy
            if ty >= 0 then
                local base = ty * W
                for dx = -dxm, dxm do
                    local tx = x + dx
                    if tx >= 0 and tx < W then set[base + tx] = true end
                end
            end
        end
        n += 1
        Session.scanStep(budget, n * 8)
        if not autoOn() or Refs.World ~= w or (w and w.fg ~= grid) then return {} end
    end
    return set
end

-- Simpan daftar tile terjangkau, supaya tile di seberang jurang langsung dilewati
-- (tidak cari jalan berulang yang bikin karakter diam).
local function reachFilter(startI, R, useBlock)
    local c = Reach
    if c and c.world == Refs.World and c.start == startI and c.R == R and c.block == useBlock
        and c.ver == worldVersion() and os.clock() - c.at < 30 then
        return c.set
    end
    return nil
end

local function storeReach(startI, R, useBlock, closed)
    Reach = {
        world = Refs.World, start = startI, R = R, block = useBlock, ver = worldVersion(), at = os.clock(),
        set = reachableTileSet(closed, Refs.World.w, R),
    }
end

-- ---------- Gerakkan karakter ----------
local function releaseInput()
    AutoInput.left, AutoInput.right, AutoInput.jump, AutoInput.down = false, false, false, false
end

local function frame()
    task.wait()
    if Move.HomingRoute and not Move.HomingRoute.safe(playerState()) then
        releaseInput()
        Move.Homing = false
        return false
    end
    return autoOn()
end

local function waitAuto(ms)
    task.wait(math.max(ms or 0, 30) / 1000)
    return autoOn()
end

-- ===== ANIMASI AKSI (hanya tampilan di layar sendiri, tidak mengirim apa pun ke server) =====
-- Tangan karakter mengarah ke tile (sama seperti saat pemain memukul / memasang sendiri).
function Anim.swing(x, y, kind)
    if not (Anim.fn and Anim.idx and Anim.set) then return end
    local s = playerState()
    local facing = (s and x + 0.5 < s.x) and -1 or 1
    pcall(Anim.set, Anim.fn, Anim.idx, { t = os.clock(), x = x + 0.5, y = y + 0.5, facing = facing, kind = kind })
end

-- Efek asap kecil saat block dipasang (pakai efek "place" game)
function Anim.puff(x, y)
    local list = Refs.Particles
    if not list or #list == 0 then return end
    local pick = Anim.Particles
    if not pick then
        local worldGui = PlayerGui:FindFirstChild("GameGui")
        worldGui = worldGui and worldGui:FindFirstChild("World")
        for _, p in ipairs(list) do
            local ok, inWorld = pcall(function()
                return worldGui ~= nil and typeof(p.parent) == "Instance" and p.parent:IsDescendantOf(worldGui)
            end)
            if ok and inWorld then
                pick = p
                break
            end
        end
        pick = pick or list[1]
        Anim.Particles = pick
    end
    pcall(function() pick:place(x + 0.5, y + 0.5) end)
end

function Anim.place(x, y, id)
    local it = ItemDB[id]
    local seed = it and it.kind == "seed"
    Anim.swing(x, y, "build")
    if not seed then Anim.puff(x, y) end
end

-- Jalan ke targetX, lepas tombol saat sudah cukup dekat untuk berhenti
local function steerX(s, targetX, tol)
    local dx = targetX - s.x
    local vx = s.vx or 0
    local decel = s.grounded and 48 or 17
    local dir = 0
    if abs(dx) > tol then
        dir = dx > 0 and 1 or -1
        if vx * dir > 0 and (vx * vx) / (2 * decel) >= abs(dx) - tol * 0.5 then
            dir = 0
        end
    end
    AutoInput.left = dir < 0
    AutoInput.right = dir > 0
end

-- Jalan sampai berdiri di tengah tile tujuan
local function execWalk(tx, ty, tolerance)
    tolerance = tolerance or 0.2
    local cx = tx + 0.5
    local s0 = playerState()
    if not s0 then return false end
    local limit = 1.5 + abs(cx - s0.x) * 0.35
    local t0 = os.clock()
    while frame() do
        local s = playerState()
        if not s or s.dead then return false end
        local nx, ny = floor(s.x), floor(s.y - 0.475)
        if s.grounded and ny ~= ty then return false end
        steerX(s, cx, math.min(0.1, tolerance * 0.5))
        if nx == tx and abs(s.x - cx) <= tolerance and s.grounded and abs(s.vx or 0) < 2 then
            AutoInput.left, AutoInput.right = false, false
            return true
        end
        if os.clock() - t0 > limit then return false end
    end
    return false
end

-- Jalan ke pinggir lalu jatuh ke tile tujuan
local function execFall(e)
    local cx = e.x + 0.5
    local limit = 1.5 + 0.3 * (e.y - e.fy)
    local t0 = os.clock()
    while frame() do
        local s = playerState()
        if not s or s.dead then return false end
        steerX(s, cx, 0.1)
        if s.grounded then
            local nx, ny = floor(s.x), floor(s.y - 0.475)
            if ny == e.y then
                if nx == e.x and abs(s.x - cx) <= 0.25 then return true end
            elseif ny ~= e.fy then
                return false
            end
        end
        if os.clock() - t0 > limit then return false end
    end
    return false
end

-- Lompat naik ke tile sebelah
local function execJump(e)
    if not execWalk(e.fx, e.fy) then return false end
    local dy = e.fy - e.y
    local top = e.y + 1                               -- tinggi kaki di tujuan
    local releaseY = top - ((dy == 1) and 0 or 0.4)   -- lepas lompat di sini (kepala tidak kebentur)
    local cx = e.x + 0.5
    releaseInput()
    if not frame() then return false end              -- lepas 1 frame supaya lompat terbaca
    AutoInput.jump = true
    local t0 = os.clock()
    local airborne = false
    while frame() do
        local s = playerState()
        if not s or s.dead then return false end
        if not s.grounded then airborne = true end
        if AutoInput.jump and (s.y <= releaseY or (airborne and (s.vy or 0) >= 0)) then
            AutoInput.jump = false
        end
        if s.y <= top + 0.25 then
            steerX(s, cx, 0.1)
        else
            steerX(s, e.fx + 0.5, 0.15)
        end
        if airborne and s.grounded then
            local nx, ny = floor(s.x), floor(s.y - 0.475)
            if ny == e.y then
                if nx == e.x and abs(s.x - cx) <= 0.25 then
                    AutoInput.jump = false
                    return true
                end
            else
                return false
            end
        end
        if not airborne and os.clock() - t0 > 0.35 then return false end
        if os.clock() - t0 > 1.8 then return false end
    end
    return false
end

-- Lompati lubang: ancang-ancang, lompat di ujung, rem di udara
local function execGap(e)
    if not execWalk(e.fx, e.fy) then return false end
    local s0 = playerState()
    if not s0 then return false end
    local dir = (e.x > e.fx) and 1 or -1
    local takeoff = e.fx + 0.5 + dir * 0.6
    local startY = s0.y
    local cx = e.x + 0.5
    releaseInput()
    local t0 = os.clock()
    local jumped, airborne, jumpAt = false, false, 0
    while frame() do
        local s = playerState()
        if not s or s.dead then return false end
        if not jumped then
            AutoInput.left, AutoInput.right = dir < 0, dir > 0
            if (s.x - takeoff) * dir >= 0 or not s.grounded then
                jumped, jumpAt = true, os.clock()
                AutoInput.jump = s.grounded
            end
        else
            if not s.grounded then airborne = true end
            if AutoInput.jump and (s.y <= startY - 1 or (airborne and (s.vy or 0) >= 0)) then
                AutoInput.jump = false
            end
            steerX(s, cx, 0.1)
            if airborne and s.grounded then
                local nx, ny = floor(s.x), floor(s.y - 0.475)
                if ny == e.y then
                    if nx == e.x and abs(s.x - cx) <= 0.25 then return true end
                else
                    return false
                end
            end
            if not airborne and os.clock() - jumpAt > 0.35 then return false end
        end
        if os.clock() - t0 > 2.2 then return false end
    end
    return false
end

-- Tangga lahan: naik 1-2 tile ke lorong setinggi 1 tile (lewat lubang tangga / keluar dari lubang).
-- Cara main manual: berdiri rapat ke sisi tujuan, lompat, tekan arah tujuan SETELAH badan naik
-- (kalau ditekan terlalu cepat badan masuk ke bawah block tujuan -> kepala kebentur -> jatuh),
-- saat kepala menempel atap lorong kaki sudah di atas block tujuan -> geser masuk. 3 cara dicoba.
function Move.execStair(e)
    if not execWalk(e.fx, e.fy) then return false end
    local dir = (e.x > e.fx) and 1 or -1
    local top = e.y + 1 -- tinggi kaki di tujuan (atas block pijakan)
    local hug = e.fx + 0.5 + dir * 0.17
    for try = 1, 3 do
        -- rapat ke dinding sisi tujuan
        local t0 = os.clock()
        while frame() do
            local s = playerState()
            if not s or s.dead then return false end
            steerX(s, hug, 0.03)
            if abs(s.x - hug) <= 0.06 and abs(s.vx or 0) < 1 then break end
            if os.clock() - t0 > 0.8 then break end
        end
        releaseInput()
        if not frame() then return false end
        local s0 = playerState()
        if not s0 then return false end
        local y0 = s0.y
        AutoInput.jump = true
        t0 = os.clock()
        local airborne, landed = false, nil
        while frame() do
            local s = playerState()
            if not s or s.dead then return false end
            if not s.grounded then airborne = true end
            if AutoInput.jump and (s.y <= top - 0.1 or (airborne and (s.vy or 0) >= 0)) then
                AutoInput.jump = false -- sudah setinggi tujuan / kena atap
            end
            -- Saat lompat di bawah atap lorong, kepala menempel di atap +-0.18 dtk dan kaki sudah di atas block
            -- tujuan: tekan arah di saat itu -> badan langsung masuk lorong (tidak perlu diangkat game).
            -- Tombol arah JANGAN ditekan di lantai: badan masuk ke bawah block tujuan -> kepala kebentur -> jatuh.
            -- coba 1: saat kaki sudah setinggi atas block tujuan (menempel atap)
            -- coba 2: setelah naik 0.15 tile (menempel sisi block, game mengangkat badan s/d 0.3 tile)
            -- coba 3: saat kaki 0.25 tile di bawah atas block
            local press = (try == 1 and s.y <= top + 0.02) or (try == 2 and s.y <= y0 - 0.15) or (try == 3 and s.y <= top + 0.25)
            if airborne and press then
                AutoInput.right, AutoInput.left = dir > 0, dir < 0
            else
                steerX(s, hug, 0.03)
            end
            if airborne and s.grounded then
                landed = floor(s.y - 0.475)
                break
            end
            if not airborne and os.clock() - t0 > 0.35 then break end
            if os.clock() - t0 > 1.8 then break end
        end
        releaseInput()
        if landed == e.y then
            return execWalk(e.x, e.y) -- sudah di lorong atas: ke tengah tile tujuan
        end
        if landed ~= nil and landed ~= e.fy then return false end -- jatuh ke tempat lain
        if not execWalk(e.fx, e.fy) then return false end
    end
    return false
end

-- Naik 1 tile: lompat, taruh block di bawah kaki, lalu mendarat di atasnya.
-- Block ditaruh agak telat supaya posisi di server sudah ikut naik.
local function execPillar(e)
    if not execWalk(e.fx, e.fy) then return false end
    if fgIdAt(e.fx, e.fy) ~= 0 then return false end
    releaseInput()
    if not frame() then return false end
    AutoInput.jump = true
    local t0 = os.clock()
    local placed, airborne = false, false
    while frame() do
        local s = playerState()
        if not s or s.dead then return false end
        if not s.grounded then airborne = true end
        steerX(s, e.fx + 0.5, 0.12)
        if AutoInput.jump and (s.y < e.fy - 0.9 or (airborne and (s.vy or 0) >= 0)) then
            AutoInput.jump = false
        end
        if not placed and airborne and s.y < e.fy - 0.25 and ((s.vy or 0) > -6 or s.y < e.fy - 0.8) then
            placed = placeScaffold(e.fx, e.fy)
            if not placed then return false end
        end
        if s.grounded and airborne then
            local nx, ny = floor(s.x), floor(s.y - 0.475)
            return placed and nx == e.x and ny == e.y
        end
        if not airborne and os.clock() - t0 > 0.35 then return false end
        if os.clock() - t0 > 1.8 then return false end
    end
    return false
end

local function followPath(path)
    local i = 1
    while i <= #path do
        if not autoOn() then return false end
        local e = path[i]
        local last, ok = i, false
        if e.kind == "walk" then
            -- langkah searah digabung jadi satu gerakan
            local dir = e.x - e.fx
            while path[last + 1] and path[last + 1].kind == "walk" and (path[last + 1].x - path[last + 1].fx) == dir do
                last += 1
            end
            local anyBuild = false
            for j = i, last do
                if path[j].build then
                    anyBuild = true
                    break
                end
            end
            if anyBuild then
                -- perlu block: taruh block di depan, lalu melangkah
                ok = true
                for j = i, last do
                    local st = path[j]
                    if st.build and not realSupport(st.x, st.y) then
                        setMoveStatus(("Taruh block pijakan (%d,%d)"):format(st.x, st.y + 1))
                        if not placeScaffold(st.x, st.y + 1) or not waitAuto(120) then
                            ok = false
                            break
                        end
                    end
                    if not execWalk(st.x, st.y) then
                        ok = false
                        break
                    end
                end
            else
                setMoveStatus(("Jalan ke (%d,%d)"):format(path[last].x, path[last].y))
                ok = execWalk(path[last].x, path[last].y)
            end
        elseif e.kind == "pillar" then
            setMoveStatus(("Naik pakai block ke (%d,%d)"):format(e.x, e.y))
            ok = execPillar(e)
        elseif e.kind == "fall" then
            setMoveStatus(("Turun ke (%d,%d)"):format(e.x, e.y))
            ok = execFall(e)
        elseif e.kind == "jump" then
            setMoveStatus(("Lompat ke (%d,%d)"):format(e.x, e.y))
            ok = execJump(e)
        elseif e.kind == "gap" then
            setMoveStatus(("Lompati lubang ke (%d,%d)"):format(e.x, e.y))
            ok = execGap(e)
        elseif e.kind == "stair" then
            setMoveStatus(("Naik tangga ke (%d,%d)"):format(e.x, e.y))
            ok = Move.execStair(e)
        end
        releaseInput()
        if not ok then
            -- hindari jalur ini sementara (tangga cuma sebentar, supaya tidak memutar jauh ke tangga lain)
            BadEdge[e.key] = os.clock() + ((e.kind == "stair") and 5 or 20)
            return false
        end
        i = last + 1
    end
    return true
end

-- Cari jalan ke grup target, lalu jalan ke sana
local function travelGroup(sx, sy, group, R, useBlock, skipTbl, failTbl, route)
    local w = Refs.World
    local goals = {}
    goals.maxY = group.maxY
    goals.los = group.los
    for _, t in ipairs(group) do goals[t.idx] = true end
    local first = group[1]
    setMoveStatus(("Cari jalan A* ke (%d,%d)"):format(first.x, first.y))
    local path, exhausted, closed = astar(sx, sy, goals, first.x, first.y, R, useBlock, route)
    if path then
        if #path == 0 then
            -- FIX: A* menganggap sudah cukup dekat (hitungan per-tile), tapi posisi asli karakter
            -- mepet tepi tile sehingga target belum masuk jangkauan pukul. Jangan langsung di-skip
            -- (bikin karakter diam): geser dulu ke tengah tile, baru skip kalau sudah di tengah.
            local cs = playerState()
            if cs and abs(cs.x - (sx + 0.5)) > 0.2 then
                execWalk(sx, sy)
            else
                for _, t in ipairs(group) do skipTile(skipTbl, t.idx, 20) end
            end
        elseif not followPath(path) then
            failTbl[first.idx] = (failTbl[first.idx] or 0) + 1
            if failTbl[first.idx] >= 3 then
                if Clear.Running then Clear.Why.gagal += #group end
                for _, t in ipairs(group) do skipTile(skipTbl, t.idx, 40) end
            end
        end
        releaseInput()
        return true
    end
    -- tidak ada jalan ke grup ini
    if Clear.Running then
        local nc = 0
        for _ in pairs(closed or {}) do nc += 1 end
        Clear.Dbg = ("start=(%d,%d) lantai=%s jelajah=%d titik, tujuan=(%d,%d)"):format(
            sx, sy, tostring(realSupport(sx, sy)), nc, first.x, first.y)
        if exhausted then Clear.Why.nopath += #group else Clear.Why.batas += #group end
    end
    for _, t in ipairs(group) do skipTile(skipTbl, t.idx, exhausted and 60 or 30) end
    if exhausted and w then storeReach(sy * w.w + sx, R, useBlock, closed) end
    releaseInput()
    return false
end

-- ---------- Datangi drop yang belum terambil ----------
-- Hasil panen kadang jatuh di luar jangkauan collect. Drop dicari dari daftar drop game
-- (sama seperti Growscan), lalu karakter jalan mendekat (A*, tanpa pijakan) sampai drop
-- itu benar-benar terambil. Drop yang tidak ada jalannya dilewati sebentar.
-- Ambil drop di tile kerja dengan sentuhan badan (Auto Farm, Pabrik, bibit Bangun Lahan), tanpa remote.
-- Aturan game: drop terpungut kalau jaraknya < 0.6 tile dari tengah badan (mendatar) dan setinggi badan.
--   - tile sebaris (kiri / kanan, sampai 3 tile): disusuri sampai tile terjauh tiap sisi
--   - tile baris atas (kiri, tengah, kanan): berdiri di bawahnya lalu lompat kecil (tap); selama di udara
--     geser ke tile atas berikutnya yang masih ada drop-nya (bisa kena 2 sekaligus)
-- lalu balik lagi ke posisi kerja (hx, hy). Hasil: true = sudah balik ke posisi kerja.
function Drops.touchAll(tiles, hx, hy)
    local list = Drops.list
    if not list or not OrigIsDown then return false end
    local function dropsAt(t)
        for _, d in ipairs(list) do
            if type(d) == "table" and type(d.x) == "number" and (d.n or 0) > 0 and d.armed ~= false
                and not d.taking and canTry(d, os.clock()) and inTile(t, d.x, d.y) then
                return true
            end
        end
        return false
    end
    local has = {}
    for _, t in ipairs(tiles) do
        if not solidAt(t.x, t.y) and dropsAt(t) then has[#has + 1] = t end
    end
    if #has == 0 then return false end
    local s0 = playerState()
    if not s0 or s0.dead or not s0.grounded then return false end
    local function ground(c) return openAt(c, hy) and realSupport(c, hy) end
    local function walkable(a, b)
        local st = (b >= a) and 1 or -1
        for c = a, b, st do
            if not ground(c) then return false end
        end
        return true
    end
    local was = AutoInput.active
    AutoInput.active = true
    local function moveTo(cx, maxT)
        local t0 = os.clock()
        while alive() and os.clock() - t0 < (maxT or 1.2) do
            task.wait()
            local c = playerState()
            if not c or c.dead then break end
            steerX(c, cx, 0.1)
            if c.grounded and abs(c.x - cx) <= 0.15 and abs(c.vx or 0) < 1.5 then
                AutoInput.left, AutoInput.right = false, false
                return true
            end
        end
        AutoInput.left, AutoInput.right = false, false
        return false
    end
    -- lompat kecil (tap = naik +-1.4 tile, tidak sampai naik ke atas baris block), di udara geser ke toX
    local function hop(toX)
        AutoInput.left, AutoInput.right = false, false
        local c0 = playerState()
        if not c0 then return end
        local y0 = c0.y
        AutoInput.jump = true
        local t0, air = os.clock(), false
        while alive() and os.clock() - t0 < 1.4 do
            task.wait()
            local c = playerState()
            if not c or c.dead then break end
            if not c.grounded then
                air = true
                AutoInput.jump = false -- tap: lepas begitu lepas dari tanah
            end
            if toX and air and c.y <= y0 - 0.25 then steerX(c, toX, 0.1) else AutoInput.left, AutoInput.right = false, false end
            if air and c.grounded then break end
            if not air and os.clock() - t0 > 0.35 then break end
        end
        AutoInput.jump, AutoInput.left, AutoInput.right = false, false, false
    end
    -- baris badan: susuri sampai tile terjauh tiap sisi
    local lo, hi = hx, hx
    for _, t in ipairs(has) do
        if t.y == hy and abs(t.x - hx) <= 3 then
            if t.x < lo then lo = t.x end
            if t.x > hi then hi = t.x end
        end
    end
    if lo < hx and walkable(hx - 1, lo) then moveTo(lo + 0.5) end
    if hi > hx and walkable(hx + 1, hi) then moveTo(hi + 0.5) end
    -- baris atas: lompat di bawah tile yang masih ada drop-nya (maks 4 lompatan)
    for _ = 1, 4 do
        local cs = playerState()
        if not cs or not alive() then break end
        local cur = floor(cs.x)
        local cols = {}
        for _, t in ipairs(has) do
            if t.y == hy - 1 and abs(t.x - hx) <= 1 and ground(t.x) and walkable(cur, t.x)
                and not solidAt(t.x, t.y) and dropsAt(t) then
                cols[#cols + 1] = t.x
            end
        end
        if #cols == 0 then break end
        table.sort(cols, function(p, q) return abs(p - cur) < abs(q - cur) end)
        local a = cols[1]
        if a ~= cur then moveTo(a + 0.5) end
        hop(cols[2] and (cols[2] + 0.5) or nil) -- sambil geser ke tile berikutnya
    end
    -- balik ke posisi kerja
    local ok = moveTo(hx + 0.5, 2)
    AutoInput.left, AutoInput.right, AutoInput.jump = false, false, false
    AutoInput.active = was
    waitNearDrops(0.2)
    return ok
end

function Drops.touch(t, hx, hy)
    return Drops.touchAll({ t }, hx, hy)
end

-- Tile yang barusan pecah: drop-nya datang dari server (sesuai ping). Tunggu sampai drop baru
-- muncul di tile itu (atau batas waktu), supaya tidak keburu ketimpa block baru / tidak tersentuh.
function Drops.waitSpawn(tiles)
    local ping = 0.1
    pcall(function() ping = LocalPlayer:GetNetworkPing() end)
    local limit = math.clamp(0.15 + 2.5 * ping, 0.25, 0.8)
    local newest = nil
    for _, t in ipairs(tiles) do
        local b = Drops.brokeAt[t.x .. "," .. t.y]
        if b and os.clock() - b < limit and (not newest or b > newest) then newest = b end
    end
    if not newest then return end
    local list = Drops.list
    while os.clock() - newest < limit and alive() do
        if list then
            for _, d in ipairs(list) do
                if type(d) == "table" and type(d.x) == "number" and (d.born or 0) >= newest then
                    for _, t in ipairs(tiles) do
                        if inTile(t, d.x, d.y) then
                            task.wait(0.05) -- drop lain dari pecahan yang sama
                            return
                        end
                    end
                end
            end
        end
        task.wait()
    end
end

-- Datangi 1 drop sampai terambil (berdiri di tile drop-nya; kalau tile itu tidak bisa dipijak,
-- misal lubang tangga: berdiri tepat di bawahnya lalu lompat sekali). Hasil: true = terambil.
function Move.visitDrop(d)
    local w = Refs.World
    local s = playerState()
    if not w or not s then return false, "nopath" end
    local W = w.w
    local tx, ty = floor(d.x), floor(d.y)
    if solidAt(tx, ty) then return false, "nopath" end -- terkubur di dalam block: tidak bisa disentuh
    local sx, sy = startNode(s)
    local goal = { [ty * W + tx] = true }
    local path = astar(sx, sy, goal, tx, ty, 0.5, false)
    if not path and ty + 1 < w.h then
        path = astar(sx, sy, { [(ty + 1) * W + tx] = true }, tx, ty + 1, 0.5, false)
    end
    if not path then path = astar(sx, sy, goal, tx, ty, 1.2, false) end
    if not path then return false, "nopath" end
    if #path > 0 then
        local ok = followPath(path)
        releaseInput()
        if not ok then return false, "nopath" end
    end
    local ping = 0.1
    pcall(function() ping = LocalPlayer:GetNetworkPing() end)
    waitNearDrops(math.clamp(0.6 + 3 * ping, 1, 2.5))
    local function left() return (d.n or 0) > 0 and table.find(Drops.list or {}, d) ~= nil end
    local cur = playerState()
    if left() and cur and cur.grounded and abs(d.x - cur.x) <= 0.9 and d.y < cur.y - 0.9 and d.y > cur.y - 2.6 then
        -- drop di atas kepala: lompat sekali supaya kena badan
        AutoInput.active = true
        AutoInput.jump = true
        task.wait(0.25)
        AutoInput.jump = false
        local t0 = os.clock()
        repeat
            task.wait(0.05)
            local c = playerState()
        until not c or c.grounded or os.clock() - t0 > 1.5
        waitNearDrops(0.5)
    end
    if left() then return false, "left" end
    return true
end

-- Susuri 1 baris (tile badan ry) dari kolom xa ke xb tanpa berhenti di tiap drop:
-- drop di jalan terambil sambil lewat, sama seperti main manual.
function Move.walkRow(ry, xa, xb)
    local w = Refs.World
    if not w then return false end
    for _, tx in ipairs({ xa, xb }) do
        local s = playerState()
        if not s or s.dead then return false end
        local sx, sy = startNode(s)
        if not (sx == tx and sy == ry) then
            local goal = { [ry * w.w + tx] = true }
            local path = astar(sx, sy, goal, tx, ry, 0.5, false) or astar(sx, sy, goal, tx, ry, 1.2, false)
            if not path then
                releaseInput()
                return false
            end
            if #path > 0 and not followPath(path) then
                releaseInput()
                return false
            end
        end
    end
    releaseInput()
    return true
end

-- Ambil drop yang belum terambil, PER BARIS (seperti main manual):
--   pilih drop terdekat (baris sendiri didahulukan), lalu susuri baris itu dari ujung terdekat
--   ke ujung lainnya tanpa berhenti. Yang masih tertinggal (mis. di lubang tangga) baru didatangi
--   satu-satu, dan yang tetap tidak terambil tidak dicoba lagi sebentar.
-- filter(d) = true: drop ini boleh diambil (nil = semua). maxSec = batas waktu (20 dtk).
Move.FetchFail = {}
function Move.fetchDrops(live, maxDist, filter, maxSec)
    local list = Drops.list
    local w = Refs.World
    if not list or not w then return 0 end
    maxDist = maxDist or 8
    local got, t0 = 0, os.clock()
    local function want(d, now)
        if not (canTry(d, now) and d.id) then return false end
        if Move.FetchFail[d.uid] and now < Move.FetchFail[d.uid] then return false end
        if solidAt(floor(d.x), floor(d.y)) then -- terkubur di dalam block: tidak bisa disentuh
            Move.FetchFail[d.uid] = now + 300
            return false
        end
        local z = Pabrik.Zone
        if z and not Move.NoZone and z.world == rawget(w, "name") and abs(d.x - z.x) <= 2.5 and abs(d.y - z.y) <= 2.5 then
            return false
        end
        if filter and not filter(d) then return false end
        if d.id ~= 112 and Refs.Inv then -- inventori penuh: tidak usah diambil
            local okr, r = pcall(function() return Refs.Inv:room(d.id) end)
            if okr and type(r) == "number" and r <= 0 then return false end
        end
        return true
    end
    while live() and alive() and os.clock() - t0 < (maxSec or 20) do
        local s = playerState()
        if not s or s.dead then break end
        if not s.grounded then
            task.wait(0.05)
            continue
        end
        local cx, cy = s.x, s.y - 0.475
        local now = os.clock()
        local best, bd = nil, nil
        for _, d in ipairs(list) do
            if want(d, now) then
                local dx, dy = d.x - cx, d.y - cy
                if abs(dx) <= maxDist and abs(dy) <= maxDist and (abs(dx) >= 0.6 or abs(dy) >= 0.75) then
                    local dd = dx * dx + 9 * dy * dy -- baris sendiri didahulukan
                    if not bd or dd < bd then best, bd = d, dd end
                end
            end
        end
        if not best then break end
        local ry = floor(best.y)
        if best.x < 0 or ry < 0 or best.x >= w.w or ry >= w.h then
            Move.FetchFail[best.uid] = now + 30
        else
            -- semua drop di baris itu: susuri dari ujung terdekat ke ujung lainnya
            local inRow, lo, hi = {}, best.x, best.x
            for _, d in ipairs(list) do
                if floor(d.y) == ry and abs(d.x - cx) <= maxDist and want(d, now) then
                    inRow[#inRow + 1] = d
                    if d.x < lo then lo = d.x end
                    if d.x > hi then hi = d.x end
                end
            end
            local xa, xb = floor(lo), floor(hi)
            if abs(hi - cx) < abs(lo - cx) then xa, xb = xb, xa end
            setMoveStatus(("Ambil drop baris y %d (x %d-%d)"):format(ry, math.min(xa, xb), math.max(xa, xb)))
            local ok = Move.walkRow(ry, xa, xb)
            -- pungutan dikirim ke server: tunggu balasannya (ping) sebelum menilai drop tertinggal
            local ping = 0.1
            pcall(function() ping = LocalPlayer:GetNetworkPing() end)
            local tw = os.clock()
            repeat
                task.wait(0.05)
                local busy = false
                for _, d in ipairs(inRow) do
                    if d.taking then
                        busy = true
                        break
                    end
                end
            until not busy or os.clock() - tw > math.clamp(0.3 + 3 * ping, 0.5, 2.5)
            got += 1
            Move.FetchTry = Move.FetchTry or {}
            for _, d in ipairs(inRow) do
                if (d.n or 0) > 0 and table.find(list, d) then
                    local okv, why = false, "nopath"
                    if ok then okv, why = Move.visitDrop(d) end
                    if not okv then
                        local tries = (Move.FetchTry[d.uid] or 0) + 1
                        Move.FetchTry[d.uid] = tries
                        if why == "left" and tries < 4 then
                            Move.FetchFail[d.uid] = os.clock() + 1.5 -- sudah didatangi (balasan server telat / sisa sebagian): coba lagi sebentar lagi
                        else
                            Move.FetchFail[d.uid] = os.clock() + 30 -- tidak ada jalan / tetap tidak terambil
                        end
                    else
                        Move.FetchTry[d.uid] = nil
                    end
                end
            end
        end
    end
    releaseInput()
    return got
end

local function autoBegin()
    AutoInput.active = true
    releaseInput()
    Reach = nil
    if Misc.Ghost then
        setGhost(false) -- fly dimatikan (kena rollback)
        if UI.GhostToggle then pcall(function() UI.GhostToggle:Set(false) end) end
    end
end

local function autoEnd()
    if Clear.Running or Farmer.Running or Pabrik.Running or Build.Running or Move.Homing then
        return
    end
    AutoInput.active = false
    releaseInput()
end

local function blockText(useBlock, id)
    if not useBlock then return "mati" end
    if not id then return "belum dipilih" end
    local n = invCount(id)
    return itemName(id) .. " x" .. n .. (n <= 0 and " (habis)" or "")
end

---------------------------------------------------------------------
-- CLEAR WORLD: bersihkan dari baris atas ke bawah, 2 baris sekali sapu
---------------------------------------------------------------------
-- Boleh dipecah? (lock, vending, display tidak disentuh)
local function clearCanBreak(id)
    if not id or id == 0 then return false end
    local it = ItemDB[id]
    if not it then return false end
    if it.lock or it.area or it.guildLock or it.vend or it.display then return false end
    local h = (it.kind == "seed") and 20 or it.hits
    if type(h) == "number" and h > 0 then return true end
    local w = Refs.World
    if (it.staffHits and w and w.areas and w.areas.staff) then return true end
    -- FIX: setelah update game, field `hits` bisa tidak ada / berganti nama. Anggap bisa dipecah
    -- kecuali jelas tidak (hits <= 0, bedrock, unbreakable), sama seperti canBreak() milik Auto Farm.
    if h == nil then
        local nm = type(it.name) == "string" and it.name:lower() or ""
        if nm:find("bedrock", 1, true) or it.unbreakable or it.indestructible or it.invincible then return false end
        return true
    end
    return false
end

function Auto.worldBreakOptions(background)
    local w, counts, ids = Refs.World, {}, {}
    local layers, bgCounts, bgEligible = {}, {}, {}
    if not w or type(w.fg) ~= "table" then return ids, counts, layers end
    local spawn, grid, eligible = w.spawn, w.fg, {}
    local budget = { next = os.clock() + 0.001 }
    local sx, sy
    if spawn and (typeof(spawn) == "Vector2" or type(spawn) == "table") then sx, sy = spawn.X, spawn.Y end
    for y = 0, (w.h or 0) - 1 do
        local row = grid[y]
        local bgRow = type(w.bg) == "table" and w.bg[y] or nil
        for x = 0, (w.w or 0) - 1 do
            local id = row and row[x]
            if id and id ~= 0 then
                if eligible[id] == nil then
                    local item = ItemDB[id]
                    eligible[id] = item ~= nil and item.kind ~= "seed" and clearCanBreak(id) or false
                end
                if eligible[id] and not (sx == x and sy == y) then counts[id] = (counts[id] or 0) + 1 end
            end
            -- FIX: background (wallpaper dll) ikut dihitung sebagai pilihan target
            local bid = bgRow and bgRow[x]
            if bid and bid ~= 0 then
                if bgEligible[bid] == nil then
                    local item = ItemDB[bid]
                    bgEligible[bid] = item ~= nil and clearCanBreak(bid) or false
                end
                if bgEligible[bid] then bgCounts[bid] = (bgCounts[bid] or 0) + 1 end
            end
            if background then
                Session.scanStep(budget, y * w.w + x + 1)
                if not alive() or Refs.World ~= w or w.fg ~= grid then return {}, {}, {} end
            end
        end
    end
    for id in pairs(counts) do layers[id] = "fg" end
    for id, n in pairs(bgCounts) do
        if not counts[id] then counts[id], layers[id] = n, "bg" end
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local an, bn = itemName(a):lower(), itemName(b):lower()
        return an == bn and a < b or an < bn
    end)
    return ids, counts, layers
end

-- Layer yang dipecah: fg dulu, lalu bg
local function clearLayerAt(x, y)
    local w = Refs.World
    if Clear.TargetId and (not w or w.fg ~= Clear.TargetGrid or w.name ~= Clear.TargetWorld) then return nil end
    local sp = w and w.spawn
    if sp ~= nil and (typeof(sp) == "Vector2" or type(sp) == "table") and x == sp.X and y == sp.Y then
        return nil
    end
    local fg = tileAt("fg", x, y)
    if fg == nil then return nil end
    if Clear.TargetId and Clear.TargetLayer == "bg" then
        -- target background (wallpaper): hanya bisa dipukul kalau block depannya kosong
        if fg ~= 0 then return nil end
        local bgId = tileAt("bg", x, y)
        if bgId == Clear.TargetId and clearCanBreak(bgId) then return "bg", bgId end
        return nil
    end
    if fg ~= 0 then
        if Clear.TargetId and fg ~= Clear.TargetId then return nil end
        if clearCanBreak(fg) then return "fg", fg end
        return nil -- fg tidak bisa dipecah, bg juga tidak
    end
    if Clear.IncludeBg and not Clear.TargetId then
        local bg = tileAt("bg", x, y)
        if bg and bg ~= 0 and clearCanBreak(bg) then return "bg", bg end
    end
    return nil
end

-- Cari baris paling atas yang masih ada block
local function scanTopRow()
    local w = Refs.World
    local W, H = w.w, w.h
    local now = os.clock()
    local grid, budget = w.fg, { next = now + 0.001 }
    for y = 0, H - 1 do
        local frow, brow = w.fg[y], w.bg[y]
        for x = 0, W - 1 do
            local fid = frow and frow[x] or 0
            local bid = brow and brow[x] or 0
            if (fid ~= 0 or ((Clear.IncludeBg or Clear.TargetLayer == "bg") and bid ~= 0)) and clearLayerAt(x, y)
                and not skipped(Clear.Skip, y * W + x, now) then
                return y
            end
            Session.scanStep(budget, y * W + x + 1)
            if not Clear.Running or not alive() or Refs.World ~= w or w.fg ~= grid then return nil end
        end
    end
    return nil
end

local function countRemaining()
    local w = Refs.World
    if not w then return -1 end
    local W, H = w.w, w.h
    local n, scanned = 0, 0
    local grid, budget = w.fg, { next = os.clock() + 0.001 }
    for y = 0, H - 1 do
        local frow, brow = w.fg[y], w.bg[y]
        for x = 0, W - 1 do
            local fid = frow and frow[x] or 0
            local bid = brow and brow[x] or 0
            if (fid ~= 0 or ((Clear.IncludeBg or Clear.TargetLayer == "bg") and bid ~= 0)) and clearLayerAt(x, y) then n += 1 end
            scanned += 1
            Session.scanStep(budget, scanned)
            if not alive() or not Clear.Running or Refs.World ~= w or w.fg ~= grid then return -1 end
        end
    end
    return n
end

-- Arah sapu. Zig-zag: arah dipilih sekali per baris (dari ujung terdekat),
-- lalu dipegang sampai baris selesai supaya tidak bolak-balik.
local function bandDir(topRow, s)
    if Clear.Sweep ~= "Zig-zag" then return 1 end
    if Clear.DirRow == topRow and Clear.Dir then return Clear.Dir end
    local w = Refs.World
    local now = os.clock()
    local minX, maxX
    for y = topRow, math.min(topRow + 1, w.h - 1) do
        for x = 0, w.w - 1 do
            if clearLayerAt(x, y) and not skipped(Clear.Skip, y * w.w + x, now) then
                if not minX or x < minX then minX = x end
                if not maxX or x > maxX then maxX = x end
            end
        end
    end
    local dir = 1
    if minX and maxX and abs(s.x - maxX) < abs(s.x - minX) then dir = -1 end
    Clear.DirRow, Clear.Dir = topRow, dir
    return dir
end

-- Semua target di baris ini, urut sesuai arah sapu.
-- Tile yang tidak terjangkau langsung dilewati.
local function bandTargets(top, bottom, dir, filter)
    local w = Refs.World
    local W = w.w
    local list = {}
    local now = os.clock()
    local grid, budget, visited = w.fg, { next = now + 0.001 }, 0
    for y = top, math.min(bottom, w.h - 1) do
        for x = 0, W - 1 do
            local idx = y * W + x
            if clearLayerAt(x, y) and not skipped(Clear.Skip, idx, now) then
                if filter and not filter[idx] then
                    skipTile(Clear.Skip, idx, 60) -- di seberang jurang / tidak ada jalan
                    Clear.Why.jurang += 1
                elseif canWorkAt(x, y) then
                    list[#list + 1] = { x = x, y = y, idx = idx }
                else
                    skipTile(Clear.Skip, idx, 300) -- tidak ada izin
                    Clear.Why.izin += 1
                end
            end
            visited += 1
            Session.scanStep(budget, visited * 8)
            if not Clear.Running or not alive() or Refs.World ~= w or w.fg ~= grid then return {} end
        end
    end
    table.sort(list, function(a, b)
        if a.x ~= b.x then return a.x * dir < b.x * dir end
        return a.y < b.y
    end)
    return list
end

-- Tile yang bisa dipukul dari sini. Pijakan kaki dipecah paling akhir.
local function clearInReach(s, bottom, dir)
    local w = Refs.World
    local W = w.w
    local R = punchReach() - 0.08
    local cx, cy = s.x, s.y - 0.475
    local footRow = floor(s.y + 0.01)
    local colA, colB = floor(s.x - 0.3), floor(s.x + 0.3 - 0.0001)
    local now = os.clock()
    local list = {}
    for ty = math.max(0, floor(cy - R - 0.5)), math.min(floor(cy + R + 0.5), bottom, w.h - 1) do
        for tx = math.max(0, floor(cx - R - 0.5)), math.min(floor(cx + R + 0.5), W - 1) do
            if stateReaches(s, tx, ty, R) then
                local idx = ty * W + tx
                if not skipped(Clear.Skip, idx, now) and clearLayerAt(tx, ty) then
                    if canWorkAt(tx, ty) then
                        list[#list + 1] = {
                            x = tx, y = ty, idx = idx,
                            support = (ty == footRow and tx >= colA and tx <= colB),
                        }
                    else
                        skipTile(Clear.Skip, idx, 300)
                        Clear.Why.izin += 1
                    end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.support ~= b.support then return not a.support end
        if a.x ~= b.x then return a.x * dir < b.x * dir end
        return a.y < b.y
    end)
    return list
end

-- Kalau pijakan dipecah, jatuh berapa tile? (nil = jatuh ke lava/duri)
local function fallAfterBreak(s, x, footRow)
    local colA, colB = floor(s.x - 0.3), floor(s.x + 0.3 - 0.0001)
    for c = colA, colB do
        if c ~= x and (solidAt(c, footRow) or platformAt(c, footRow)) then return 0 end -- masih menapak kolom lain
    end
    local w = Refs.World
    for y = footRow + 1, math.min(w.h - 1, footRow + 60) do
        if hazardAt(x, y) then return nil end
        if solidAt(x, y) or platformAt(x, y) then return y - footRow end
    end
    return 60
end

-- Pukul satu tile sampai bersih (fg lalu bg)
local function clearBreakTile(t)
    local x, y, idx = t.x, t.y, t.idx
    local layer, id = clearLayerAt(x, y)
    if not layer then return end
    local hits, maxHits = 0, hitsNeeded(id) * 3 + 6
    -- Auto Break Block (target 1 jenis): multi-hit beruntun sampai hancur, jeda = slider Fast Punch;
    -- tile yang terlewat dicoba lagi cepat (bukan dilewati lama)
    local pace = Clear.TargetId and math.max(State.FastPunchMs or 190, 50) or nil
    while Clear.Running and alive() do
        if Clear.TargetId and raymanOn() then
            stopClear("Lepas Rayman's Fist dulu agar block lain tidak ikut terkena.")
            return
        end
        layer, id = clearLayerAt(x, y)
        if not layer then return end
        local r = tryBreak(x, y, (not Clear.TargetId and Clear.IncludeBg) or (Clear.TargetLayer == "bg"), Clear.TargetId, Clear.TargetLayer)
        if r == nil then
            skipTile(Clear.Skip, idx, pace and 8 or 60)
            return
        end
        if r == "broke" then
            Clear.Broken += 1
            Clear.Status = "Pecah " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
            BreakTimes[idx] = (BreakTimes[idx] or 0) + 1
            if BreakTimes[idx] > 6 then -- server terus mengembalikan tile ini
                skipTile(Clear.Skip, idx, 120)
                return
            end
            hits = 0
            local _, nid = clearLayerAt(x, y)
            if nid then maxHits = hitsNeeded(nid) * 3 + 6 end
        else
            hits += 1
            Clear.Status = "Pukul " .. itemName(id) .. " (" .. x .. "," .. y .. ")"
            if hits > maxHits then
                skipTile(Clear.Skip, idx, pace and 5 or 45)
                return
            end
        end
        if not waitAuto(pace or State.BreakMs) then return end
        if r == "broke" then
            local s = playerState()
            if not s or not s.grounded then return end -- jatuh, cek ulang posisi
        end
    end
end

local function clearBreakList(list, s0)
    local footY = floor(s0.y - 0.475)
    local R = punchReach() - 0.08
    local done = 0
    for _, t in ipairs(list) do
        if not Clear.Running or not alive() then break end
        local s = playerState()
        if not s or s.dead or not stateReaches(s, t.x, t.y, R) then break end
        if not s.grounded or floor(s.y - 0.475) ~= footY then break end
        local skipIt = false
        if t.support then
            local d = fallAfterBreak(s, t.x, floor(s.y + 0.01))
            if d == nil then
                skipIt = true
                Clear.Status = ("Lewati (%d,%d): di bawahnya berbahaya"):format(t.x, t.y)
            elseif d > 3 then
                -- di bawahnya jurang: pecah nanti dari samping
                skipIt = true
                Clear.Status = ("Lewati pijakan (%d,%d): di bawahnya jurang"):format(t.x, t.y)
            end
        end
        if skipIt then
            skipTile(Clear.Skip, t.idx, 20)
        else
            clearBreakTile(t)
            done += 1
        end
    end
    return done
end

local lastClearText = nil
local function updateClearStatus()
    if not UI.ClearStatus and not UI.WorldBreakStatus then return end
    local txt = "Status   : " .. (Clear.Running and "JALAN" or "BERHENTI")
        .. "\nBaris    : " .. (Clear.TopRow >= 0 and (Clear.TopRow .. "-" .. (Clear.TopRow + 1)) or "-")
        .. "  | arah: " .. ((Clear.Dir == -1 and Clear.Sweep == "Zig-zag") and "kanan→kiri" or "kiri→kanan")
        .. "\nDipecah  : " .. Clear.Broken .. "  | collect: " .. State.Collected
        .. "\nSisa     : " .. (Clear.Remaining >= 0 and tostring(Clear.Remaining) or "-")
        .. "  | dilewati: " .. skippedCount(Clear.Skip)
        .. (Clear.TargetId and ("\nTarget   : " .. itemName(Clear.TargetId) .. (Clear.TargetLayer == "bg" and " (background)" or "")) or "")
        .. "\nPijakan  : " .. blockText(Clear.UseBlock and not Clear.TargetId, Clear.ScaffoldId) .. "  | dipasang: " .. Move.Placed
        .. ("\nAlasan skip: izin=%d jurang=%d tanpa-jalan=%d batas-A*=%d gagal-jalan=%d"):format(
            Clear.Why.izin, Clear.Why.jurang, Clear.Why.nopath, Clear.Why.batas, Clear.Why.gagal)
        .. "\nA*       : " .. Clear.Dbg
        .. "\nAksi     : " .. Clear.Status
    if txt == lastClearText then return end
    lastClearText = txt
    task.defer(function()
        if UI.ClearStatus then pcall(function() UI.ClearStatus:SetDesc(txt) end) end
        if UI.WorldBreakStatus and Clear.TargetId then pcall(function() UI.WorldBreakStatus:SetDesc(txt) end) end
    end)
end

local function clearLoop()
    local idle, lastUi, lastCount = 0, 0, -10
    while Clear.Running and alive() do
        task.wait()
        if Clear.TargetId and (not Refs.World or Refs.World.fg ~= Clear.TargetGrid or Refs.World.name ~= Clear.TargetWorld) then
            stopClear("World berubah. Auto Break Block dihentikan.")
            return
        end
        local now = os.clock()
        if now - lastCount > 3 then
            lastCount = now
            Clear.Remaining = countRemaining()
            if not Clear.Running or not alive() then break end
        end
        if now - lastUi > 0.5 then
            lastUi = now
            updateClearStatus()
        end
        local w = Refs.World
        local s = playerState()
        if not w or not s or s.dead then
            releaseInput()
            Clear.Status = "Menunggu karakter / world..."
            task.wait(0.5)
            continue
        end
        if not s.grounded then
            releaseInput() -- masih di udara, tunggu mendarat
            continue
        end
        releaseInput()
        do -- pelajari tile lantai dari posisi karakter yang benar-benar menapak
            local lfoot = floor(s.y + 0.01)
            for _, lc in ipairs({ floor(s.x - 0.3), floor(s.x + 0.3 - 0.0001) }) do
                local lid = fgIdAt(lc, lfoot)
                if lid ~= 0 and not hazardAt(lc, lfoot) then Clear.Learned[lid] = true end
            end
        end

        local topRow = scanTopRow()
        if not Clear.Running or not alive() then break end
        if Refs.World ~= w then continue end
        if not topRow then
            local remaining = countRemaining()
            Clear.Remaining = remaining
            if remaining == 0 then
                stopClear(Clear.TargetId and ("Selesai. Semua " .. itemName(Clear.TargetId) .. " yang bisa dipecah sudah habis.") or "World sudah bersih!")
                return
            end
            idle += 1
            if idle >= 3 then
                stopClear(("Selesai. Sisa %d tile tidak bisa dijangkau / dipecah"):format(remaining))
                return
            end
            Clear.Status = ("Sisa %d tile dilewati, coba ulang (%d/3)..."):format(remaining, idle)
            updateClearStatus()
            table.clear(Clear.Skip)
            table.clear(ClearFail)
            table.clear(BadEdge)
            Reach = nil
            if not waitAuto(2000) then break end
            continue
        end

        Clear.TopRow = topRow
        local bottom = topRow + 1 -- 2 baris dibersihkan dulu sebelum turun
        local dir = bandDir(topRow, s)

        -- 1) Pecahkan yang terjangkau
        local list = clearInReach(s, bottom, dir)
        if #list > 0 then
            if clearBreakList(list, s) > 0 then idle = 0 end
            continue
        end

        -- 2) Ambil drop di sekitar dengan menyusurinya (sentuhan badan), lalu jalan ke bagian berikutnya
        if (Clear.TargetId and State.WorldBreakCollect) or (not Clear.TargetId and Clear.Collect) then
            local band0 = topRow - 1
            if Move.fetchDrops(function() return Clear.Running end, 5, function(d)
                return d.y >= band0 and d.y < bottom + 2
            end, 8) > 0 then
                continue
            end
        end
        local R = punchReach() - 0.35
        local useBlock = scaffoldId() ~= nil
        local sx, sy = startNode(s)
        local band = bandTargets(topRow, bottom, dir, reachFilter(sy * w.w + sx, R, useBlock))
        if #band > 0 then
            -- tujuan: 5 kolom berikutnya sesuai arah sapu
            local group = {}
            for _, t in ipairs(band) do
                if (t.x - band[1].x) * dir <= 4 then group[#group + 1] = t end
            end
            travelGroup(sx, sy, group, R, useBlock, Clear.Skip, ClearFail)
        end
    end
    releaseInput()
end

local function setClearVisual()
    if UI.ClearVisualSync then return end
    UI.ClearVisualSync = true
    if UI.ClearToggle then pcall(function() UI.ClearToggle:Set(Clear.Running and not Clear.TargetId) end) end
    if UI.WorldBreakToggle then pcall(function() UI.WorldBreakToggle:Set(Clear.Running and Clear.TargetId ~= nil) end) end
    UI.ClearVisualSync = false
end

stopClear = function(reason)
    Clear.Running = false
    autoEnd()
    setClearVisual()
    Clear.Status = reason or "Dihentikan"
    if reason then
        notify("Auto Clear", reason, 5)
        if not string.find(reason, "^Dihentikan") then Hook.send("stop", "Auto Clear berhenti: " .. reason) end
    end
    updateClearStatus()
end

local function checkAutoStart()
    if not Refs.World then return "Data world belum ketemu. Tekan 'Hubungkan ke game'" end
    if not Refs.Punch then return "Fungsi pukul game belum ketemu. Tekan 'Hubungkan ke game'" end
    if not OrigIsDown then return "Kontrol gerak game (WorldMenu.isDown) tidak ketemu" end
    if not playerState() then return "Kamu belum masuk world" end
    return nil
end

local function startClear(targetId)
    if Clear.Running then setClearVisual() return end
    if AutoDrop.Busy then notify("Auto Drop", "Tunggu perjalanan drop selesai", 3) return end
    local err = checkAutoStart()
    if err then
        notify("Auto Clear", err, 4)
        setClearVisual()
        return
    end
    if targetId ~= nil then
        if type(targetId) ~= "number" or not clearCanBreak(targetId) or (ItemDB[targetId] and ItemDB[targetId].kind == "seed") then
            notify("Auto Break Block", "Pilih jenis block dari world dulu", 4)
            setClearVisual()
            return
        end
        local _, counts, layers = Auto.worldBreakOptions()
        Clear.TargetLayer = layers and layers[targetId] or "fg"
        if not counts[targetId] then
            notify("Auto Break Block", "Block pilihan tidak ada di world ini. Refresh daftar block.", 4)
            setClearVisual()
            return
        end
        if raymanOn() then
            notify("Auto Break Block", "Lepas Rayman's Fist dulu agar block lain tidak ikut terkena.", 5)
            setClearVisual()
            return
        end
    end
    if not targetId and Clear.UseBlock and (not Clear.ScaffoldId or invCount(Clear.ScaffoldId) <= 0) then
        notify("Auto Clear", "Block pijakan belum dipilih / habis: jalan tanpa block pijakan", 5)
    end
    if Pabrik.Running and Pabrik.stop then Pabrik.stop("Dihentikan karena Auto Clear dimulai") end
    if Build.Running and Build.stop then Build.stop("Dihentikan karena Auto Clear dimulai") end
    if State.Running then stopFarm("Dihentikan karena Auto Clear dimulai") end
    if Farmer.Running then stopFarmer("Dihentikan karena Auto Clear dimulai") end
    table.clear(Clear.Skip)
    table.clear(ClearFail)
    table.clear(BadEdge)
    table.clear(BreakTimes)
    Clear.Broken = 0
    for k in pairs(Clear.Why) do Clear.Why[k] = 0 end
    Clear.Remaining = -1
    Clear.TopRow = -1
    Clear.DirRow, Clear.Dir = nil, nil
    Clear.Status = "Mulai..."
    if not targetId then Clear.TargetLayer = nil end
    Clear.TargetId = targetId
    Clear.TargetGrid = targetId and Refs.World.fg or nil
    Clear.TargetWorld = targetId and Refs.World.name or nil
    Clear.Running = true
    autoBegin()
    setClearVisual()
    updateClearStatus()
    task.spawn(function()
        local ok, e = pcall(clearLoop)
        if not ok then
            warn("[n4th] Auto Clear error: " .. tostring(e))
            if Clear.Running then stopClear("Error: " .. tostring(e)) end
        end
    end)
end

---------------------------------------------------------------------
-- Auto Break memakai penelusuran Clear, dengan target foreground tunggal yang terkunci selama proses.
function Auto.startWorldBreak()
    if type(State.WorldBreakId) ~= "number" then
        notify("Auto Break Block", "Pilih block dari daftar world dulu", 4)
        setClearVisual()
        return
    end
    startClear(State.WorldBreakId)
    setClearVisual()
end

-- FARMER: panen pohon yang siap + tanam seed
---------------------------------------------------------------------
-- Pohon siap kalau: waktu server >= waktu tanam + lama tumbuh (sama dengan game).
-- Seed ditanam di tile kosong yang di bawahnya ada block.
local function findTreeRefs()
    Refs.Trees, Refs.TreeMode, Refs.TreeP = nil, nil, nil
    -- 1) cara utama (game v1159+): ikuti fungsi World.tileChanged -> fungsi simpan pohon.
    --    Tetap jalan walau world belum punya pohon (tabel kosong).
    local okS, foundS = pcall(function() return Auto.findTreesStruct and Auto.findTreesStruct() end)
    if okS and foundS == true then return true end
    Refs.Trees, Refs.TreeMode, Refs.TreeP = nil, nil, nil
    -- 2) game lama: handler remote WorldRemotes.TreeChanged
    local ev = WorldRemotes and WorldRemotes:FindFirstChild("TreeChanged")
    if ev and ev:IsA("RemoteEvent") and getconnections then
        local ok, conns = pcall(getconnections, ev.OnClientEvent)
        if ok and type(conns) == "table" then
            for _, c in pairs(conns) do
                local okf, fn = pcall(Session.connectionFunction, c)
                if okf and type(fn) == "function" then
                    for _, u in pairs(getUpvalues(fn)) do
                        if type(u) == "table" and u ~= Refs.World and rawget(u, "fg") == nil then
                            local _, v = next(u)
                            if type(v) == "table" and type(rawget(v, "p")) == "number" then
                                Refs.Trees, Refs.TreeMode, Refs.TreeP = u, "idx", "p"
                                break
                            end
                        end
                    end
                end
                if Refs.Trees then return true end
            end
        end
    end
    -- 3) cadangan: telusuri upvalue lebih dalam (butuh world yang sudah ada pohonnya)
    if Auto.findTreesDeep then pcall(Auto.findTreesDeep) end
    return Refs.Trees ~= nil
end

-- Tabel ini cocok jadi data pohon? Kosong = boleh (world tanpa pohon).
-- Isi = [y*W+x] -> { p = waktu tanam (waktu server), f = buah, s = sudah di-splice }
function Auto.treeTableOk(t)
    local w = Refs.World
    if type(t) ~= "table" or t == w or getmetatable(t) ~= nil or rawget(t, "fg") ~= nil then return false end
    local n = 0
    for k, v in pairs(t) do
        n += 1
        if n > 6 then break end
        if type(k) ~= "number" or type(v) ~= "table" or type(rawget(v, "p")) ~= "number" then return false end
        if w and type(w.w) == "number" and type(w.h) == "number" and (k < 0 or k >= w.w * w.h) then return false end
    end
    return true
end

-- Cari data pohon dari struktur kode game (tanpa getgc, tanpa remote):
--   World.tileChanged memegang (upvalue) tabel pohon + fungsi simpan pohon.
--   Fungsi simpan pohon memegang World + tabel pohon + tabel gambar pohon.
--   Tabel yang dipegang KEDUANYA = tabel pohon.
function Auto.findTreesStruct()
    local w = Refs.World
    if not w or not getUpvalues then return false end
    local roots = {}
    for _, name in ipairs({ "tileChanged", "treeChanged", "setTree" }) do
        local f = rawget(w, name)
        if type(f) == "function" then roots[#roots + 1] = f end
    end
    for _, root in ipairs(roots) do
        local ups = getUpvalues(root)
        local tset = {}
        for _, u in pairs(ups) do
            if type(u) == "table" and u ~= w then tset[u] = true end
        end
        for _, g in pairs(ups) do
            if type(g) == "function" then
                local gu = getUpvalues(g)
                local hasW, nT, shared = false, 0, {}
                for _, v in pairs(gu) do
                    if rawequal(v, w) then
                        hasW = true
                    elseif type(v) == "table" then
                        nT += 1
                        if tset[v] then shared[#shared + 1] = v end
                    end
                end
                -- fungsi simpan pohon: upvalue sedikit (World + 2 tabel), satu tabel sama dengan tileChanged
                if hasW and nT <= 3 and #shared == 1 and Auto.treeTableOk(shared[1]) then
                    Refs.Trees, Refs.TreeMode, Refs.TreeP = shared[1], "idx", "p"
                    return true
                end
            end
        end
        -- cadangan: tabel milik tileChanged yang isinya jelas data pohon
        for t in pairs(tset) do
            if next(t) ~= nil and Auto.treeTableOk(t) and Auto.treeShape(t) == "idx" then
                Refs.Trees, Refs.TreeMode, Refs.TreeP = t, "idx", "p"
                return true
            end
        end
    end
    return false
end

-- Data pohon di tile (x,y): { p = waktu tanam (waktu server), s = sudah di-splice }.
-- Bentuk tabel bisa beda tergantung versi game (lihat Auto.findTreesDeep).
function Auto.treeEntry(x, y)
    local t, w = Refs.Trees, Refs.World
    if not t or not w then return nil end
    local mode = Refs.TreeMode or "idx"
    local e
    if mode == "xy" then
        e = t[x .. "," .. y]
    elseif mode == "rows" then
        local r = t[y]
        e = type(r) == "table" and r[x] or nil
    else
        e = t[y * w.w + x]
    end
    if type(e) == "number" then return { p = e } end
    if type(e) ~= "table" then return nil end
    local pk = Refs.TreeP or "p"
    if pk ~= "p" then return { p = rawget(e, pk), s = rawget(e, "s") } end
    return e
end

-- Tabel ini data pohon? Hasil: mode ("idx" / "xy" / "rows"), nama field waktu tanam
function Auto.treeShape(t)
    local w = Refs.World
    if type(t) ~= "table" or not w or t == w or rawget(t, "fg") ~= nil then return nil end
    local W, H = w.w, w.h
    local okT, st = pcall(function() return workspace:GetServerTimeNow() end)
    if not okT then st = os.time() end
    local function timeKey(e)
        if type(e) == "number" then
            return (math.abs(e - st) < 86400 * 90) and "#" or nil
        end
        if type(e) ~= "table" then return nil end
        local pv = rawget(e, "p")
        if type(pv) == "number" and math.abs(pv - st) < 86400 * 90 then return "p" end
        for fk, fv in pairs(e) do
            if type(fv) == "number" and math.abs(fv - st) < 86400 * 90 then return fk end
        end
        return nil
    end
    local function seedAt(x, y)
        local row = w.fg[y]
        local id = row and row[x]
        local it = id and ItemDB[id]
        return it ~= nil and it.kind == "seed"
    end
    local checked, good, bad, mode, pk = 0, 0, 0, nil, nil
    for k, v in pairs(t) do
        checked += 1
        if checked > 10 then break end
        local x, y, e, m = nil, nil, nil, nil
        if type(k) == "number" and k % 1 == 0 and k >= 0 then
            if type(v) == "table" and k < H and timeKey(v) == nil then
                -- baris: t[y][x]
                local kx, ve = next(v)
                if type(kx) == "number" and kx >= 0 and kx < W then x, y, e, m = kx, k, ve, "rows" end
            elseif k < W * H then
                x, y, e, m = k % W, k // W, v, "idx"
            end
        elseif type(k) == "string" then
            local a, b = string.match(k, "^(%d+),(%d+)$")
            if a then x, y, e, m = tonumber(a), tonumber(b), v, "xy" end
        end
        if not x then return nil end
        if mode and mode ~= m then return nil end
        mode = m
        local tk = timeKey(e)
        if tk and seedAt(x, y) then
            good += 1
            pk = (tk == "#") and "p" or tk
        else
            bad += 1 -- data lama (pohon sudah dipanen) masih tersimpan: boleh sedikit
        end
    end
    if good == 0 or bad > good then return nil end
    return mode, pk
end

-- Cari data pohon lewat upvalue fungsi game (remote world, fungsi World, RunService, Net). Tanpa getgc.
function Auto.findTreesDeep()
    local w = Refs.World
    if not w or not getUpvalues then return false end
    local queue, seenF, seenT, nF = {}, {}, {}, 0
    local function addFn(fn)
        if type(fn) == "function" and not seenF[fn] then queue[#queue + 1] = fn end
    end
    local function tryTable(t)
        if seenT[t] then return false end
        seenT[t] = true
        local mode, pk = Auto.treeShape(t)
        if mode then
            Refs.Trees, Refs.TreeMode, Refs.TreeP = t, mode, pk
            return true
        end
        return false
    end
    -- 1) isi World langsung (tabel & fungsi)
    for _, v in pairs(w) do
        if type(v) == "table" then
            if tryTable(v) then return true end
        elseif type(v) == "function" then
            addFn(v)
        end
    end
    -- 2) handler remote world
    if getconnections then
        for _, ev in ipairs(WorldRemotes and WorldRemotes:GetChildren() or {}) do
            if ev:IsA("RemoteEvent") then
                local ok, conns = pcall(getconnections, ev.OnClientEvent)
                if ok and type(conns) == "table" then
                    for _, c in pairs(conns) do
                        local okf, fn = pcall(Session.connectionFunction, c)
                        if okf then addFn(fn) end
                    end
                end
            end
        end
        for _, name in ipairs({ "RenderStepped", "Heartbeat", "Stepped" }) do
            local okS, sig = pcall(function() return RunService[name] end)
            local ok, conns = pcall(getconnections, sig)
            if okS and ok and type(conns) == "table" then
                for _, c in pairs(conns) do
                    local okf, fn = pcall(Session.connectionFunction, c)
                    if okf then addFn(fn) end
                end
            end
        end
    end
    -- 3) telusuri upvalue (maks 1500 fungsi)
    local i = 1
    while i <= #queue and nF < 1500 do
        local fn = queue[i]
        i += 1
        if not seenF[fn] then
            seenF[fn] = true
            nF += 1
            for _, u in pairs(getUpvalues(fn)) do
                if type(u) == "table" then
                    if tryTable(u) then return true end
                elseif type(u) == "function" then
                    addFn(u)
                end
            end
        end
    end
    return false
end

local function farmReach()
    return math.min(punchReach(), buildReach())
end

local function seedCount()
    return Farmer.SeedId and invCount(Farmer.SeedId) or 0
end

-- Kapan pohon ini siap panen (nil = bukan pohon)
local function treeReadyAt(x, y, id)
    if not Refs.Trees or not Refs.World then return nil end
    local it = ItemDB[id]
    if not (it and it.kind == "seed") then return nil end
    local t = Auto.treeEntry(x, y)
    if type(t) ~= "table" or type(t.p) ~= "number" then return nil end
    return t.p + (it.grow or 0)
end

-- Bisa tanam seed di sini? (seedId kosong = seed Farmer)
local function plantSpotOk(x, y, seedId)
    local w = Refs.World
    if not w or x < 0 or y < 0 or x >= w.w or y + 1 >= w.h then return false end
    if fgIdAt(x, y) ~= 0 then return false end
    local below = fgIdAt(x, y + 1)
    if below == 0 then return false end
    local it = ItemDB[below]
    if not it or it.kind == "seed" then return false end
    if not (solidAt(x, y + 1) or it.platform) then return false end
    local ok, res = pcall(function()
        if w.areas and type(w.areas.canEdit) == "function" and not w.areas.canEdit(x, y) then return false end
        if type(w.builderOk) == "function" and not w.builderOk(x, y, true) then return false end
        local sid = seedId or Farmer.SeedId
        local seed = sid and ItemDB[sid]
        if seed and type(w.needsWay) == "function" and w.needsWay(seed)
            and type(w.wayBlocked) == "function" and w.wayBlocked(x, y) then
            return false
        end
        return true
    end)
    return (not ok) or res
end

-- Mesin panen & tanam dipakai bersama oleh Farmer dan Pabrik.
-- FC = pengaturan yang sedang dipakai (seed, area, kecepatan, dll).
local FC = nil
local function farmerCfg()
    return {
        run = function() return Farmer.Running end,
        harvest = Farmer.Harvest or Farmer.Tractor,
        plant = Farmer.Plant and not Farmer.Tractor,
        tractor = Farmer.Tractor,
        seed = Farmer.SeedId,
        only = Farmer.Focus, -- hanya panen pohon seed fokus (nil = semua)
        skip = Farmer.Skip,
        hms = Farmer.HarvestMs,
        pms = Farmer.PlantMs,
        area = nil,      -- function(x, y): boleh panen di sini?
        plantSet = nil,  -- [idx] = true: hanya tanam di tile ini
        exclude = nil,   -- [idx] = true: jangan tanam di tile ini
        row = Farmer.Row,        -- tanam rapi per baris
        collect = Farmer.Collect, -- ambil drop panen dulu sebelum lanjut
        status = function(t) Farmer.Status = t end,
        onHarvest = function(id)
            Farmer.Harvested += 1
            if id then Farmer.Got[id] = true end
        end,
        onPlant = function() Farmer.Planted += 1 end,
    }
end

local function fcSeeds()
    return FC.seed and invCount(FC.seed) or 0
end

local function fcHarvestOk(x, y)
    return FC.harvest and (not FC.area or FC.area(x, y))
end

local function fcPlantOk(idx)
    return (not FC.plantSet or FC.plantSet[idx]) and not (FC.exclude and FC.exclude[idx])
end

local function plantSeed(x, y)
    local id = FC.seed
    if not id or invCount(id) <= 0 then return false end
    sendSetTile("fg", x, y, id)
    if Refs.Inv then pcall(function() Refs.Inv:remove(id, 1) end) end
    FC.onPlant()
    FC.status("Tanam " .. itemName(id) .. " (" .. x .. "," .. y .. ")")
    return true
end

-- Panen & tanam semua yang terjangkau dari sini
local function farmerWorkInReach(s)
    local w = Refs.World
    local W = w.w
    local R = farmReach() - 0.08
    local cx, cy = s.x, s.y - 0.475
    local now = os.clock()
    local st = workspace:GetServerTimeNow()
    local doPlant = FC.plant and fcSeeds() > 0
    local harvest, plant = {}, {}
    local bx, by = floor(s.x), floor(cy)
    for ty = math.max(0, floor(cy - R - 0.5)), math.min(floor(cy + R + 0.5), w.h - 1) do
        for tx = math.max(0, floor(cx - R - 0.5)), math.min(floor(cx + R + 0.5), W - 1) do
            if stateReaches(s, tx, ty, R) then
                local idx = ty * W + tx
                if not skipped(FC.skip, idx, now) then
                    local id = fgIdAt(tx, ty)
                    if id ~= 0 and fcHarvestOk(tx, ty) and (not FC.only or id == FC.only) then
                        local ra = treeReadyAt(tx, ty, id)
                        if ra and st >= ra and Move.los(bx, by, tx, ty) then
                            if canWorkAt(tx, ty) then
                                harvest[#harvest + 1] = { x = tx, y = ty, idx = idx }
                            else
                                skipTile(FC.skip, idx, 120)
                            end
                        end
                    elseif doPlant and id == 0 and fcPlantOk(idx) and (not FC.row or FC.row.y == ty)
                        and plantSpotOk(tx, ty, FC.seed) then
                        plant[#plant + 1] = { x = tx, y = ty, idx = idx }
                    end
                end
            end
        end
    end
    local function byX(a, b)
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end
    table.sort(harvest, byX)
    table.sort(plant, byX)

    local done, got = 0, 0
    for _, t in ipairs(harvest) do
        if not FC.run() or not alive() then return done end
        local cur = playerState()
        if not cur or not stateReaches(cur, t.x, t.y, R) then break end
        local id = fgIdAt(t.x, t.y)
        local r = tryBreak(t.x, t.y, false) -- pohon siap: 1 pukulan = panen
        if r == "broke" then
            FC.onHarvest(id)
            got += 1
            FC.status("Panen " .. itemName(id) .. " (" .. t.x .. "," .. t.y .. ")")
        else
            skipTile(FC.skip, t.idx, 30)
        end
        done += 1
        if not waitAuto(FC.hms) then return done end
    end
    -- ambil hasil panen dulu sebelum pindah / tanam
    if got > 0 and FC.collect then
        FC.status("Ambil hasil panen...")
        task.wait(0.25) -- drop panen muncul sedikit terlambat
        if not FC.run() or not alive() then return done end
        -- susuri baris ini sampai drop terjauh (terambil sambil lewat, tanpa berhenti)
        if Move.fetchDrops(FC.run, 8, function(d) return abs(d.y - cy) <= 1.6 end, 10) > 0 then return done end
    end
    for _, t in ipairs(plant) do
        if not FC.run() or not alive() then return done end
        if fcSeeds() <= 0 then break end
        local cur = playerState()
        if not cur or not stateReaches(cur, t.x, t.y, R) then return done end
        if fgIdAt(t.x, t.y) == 0 then
            if not plantSeed(t.x, t.y) then break end
            done += 1
            if not waitAuto(FC.pms) then return done end
        end
    end
    return done
end

-- Cari target + kapan pohon berikutnya siap.
--   Panen : pohon siap terdekat (didahulukan).
--   Tanam : rapi per baris. Selesaikan 1 baris dulu (baris yang sedang dikerjakan,
--           atau baris terdekat dengan karakter), dari tile paling kiri ke kanan.
local function farmerScan(px, py, maxN, filter)
    local w = Refs.World
    local W, H = w.w, w.h
    local best = {}
    local now = os.clock()
    local st = workspace:GetServerTimeNow()
    local nextReady = nil
    local doPlant = FC.plant and fcSeeds() > 0
    local rows = {} -- [y] = daftar tempat tanam di baris itu
    local scanned = 0
    for y = 0, H - 1 do
        local frow, below = w.fg[y], w.fg[y + 1]
        for x = 0, W - 1 do
            local id = frow and frow[x] or 0
            if id ~= 0 then
                if fcHarvestOk(x, y) and (not FC.only or id == FC.only) then
                    local ra = treeReadyAt(x, y, id)
                    if ra and st >= ra then
                        local idx = y * W + x
                        if not skipped(FC.skip, idx, now) then
                            if filter and not filter[idx] then
                                skipTile(FC.skip, idx, 60)
                            else
                                local dx, dy = x - px, (y - py) * 1.3
                                local d = dx * dx + dy * dy
                                if #best < maxN or d < best[#best].d then
                                    if canWorkAt(x, y) then
                                        local pos = #best + 1
                                        while pos > 1 and best[pos - 1].d > d do pos -= 1 end
                                        table.insert(best, pos, { x = x, y = y, idx = idx, d = d, kind = "harvest" })
                                        if #best > maxN then best[#best] = nil end
                                    else
                                        skipTile(FC.skip, idx, 120)
                                    end
                                end
                            end
                        end
                    elseif ra and (not nextReady or ra - st < nextReady) then
                        nextReady = ra - st
                    end
                end
            elseif doPlant then
                local b = below and below[x] or 0
                local idx = y * W + x
                if b ~= 0 and fcPlantOk(idx) and not skipped(FC.skip, idx, now) then
                    if filter and not filter[idx] then
                        skipTile(FC.skip, idx, 60)
                    else
                        local r = rows[y]
                        if not r then
                            r = {}
                            rows[y] = r
                        end
                        r[#r + 1] = { x = x, y = y, idx = idx, kind = "plant" }
                    end
                end
            end
        end
        scanned += W
        if scanned >= 6000 then
            scanned = 0
            task.wait()
            if not FC.run() or not alive() then break end
        end
    end
    if #best > 0 or not doPlant then return best, nextReady end

    -- tanam rapi: baris yang sedang dikerjakan dulu, lalu baris terdekat
    local lock = FC.row and FC.row.y
    local order = {}
    for y in pairs(rows) do order[#order + 1] = y end
    local function rowKey(y) return (y == lock) and -1 or math.abs(y - py) end
    table.sort(order, function(a, b)
        local ka, kb = rowKey(a), rowKey(b)
        if ka ~= kb then return ka < kb end
        return a < b
    end)
    for _, y in ipairs(order) do
        local list = rows[y]
        table.sort(list, function(a, b) return a.x < b.x end) -- dari kiri ke kanan
        for _, t in ipairs(list) do
            if plantSpotOk(t.x, t.y, FC.seed) then
                if FC.row then FC.row.y = y end
                return { t }, nextReady
            end
            skipTile(FC.skip, t.idx, 120)
        end
    end
    if FC.row then FC.row.y = nil end
    return best, nextReady
end

local lastFarmerText = nil
local function updateFarmerStatus()
    if Refs.World and not Refs.Trees and os.clock() >= (Auto.nextTreeScan or 0) then
        Auto.nextTreeScan = os.clock() + 15
        pcall(findTreeRefs)
    end
    if not UI.FarmerStatus then return end
    local seed = Farmer.SeedId
    local txt = "Status  : " .. (Farmer.Running and "JALAN" or "BERHENTI")
        .. "\nPanen   : " .. Farmer.Harvested .. "  | tanam: " .. Farmer.Planted .. "  | collect: " .. State.Collected
        .. "\nSeed    : " .. (seed and (itemName(seed) .. " x" .. invCount(seed)) or "-")
        .. "\nFokus   : " .. (Farmer.Focus and itemName(Farmer.Focus) or "semua seed") .. (Farmer.Tractor and "  | MODE TRACTOR" or "")
        .. "\nPohon   : " .. (Refs.Trees and "terbaca" or "TIDAK terbaca (harvest mati)")
        .. "\nPijakan : " .. blockText(Farmer.UseBlock, Farmer.ScaffoldId)
        .. "\nDrop    : " .. ((Pabrik.pointSet and Pabrik.pointSet()) and ("otomatis saat >= " .. Farmer.DropAt
            .. " | di-drop " .. Farmer.Dropped) or "titik drop belum diatur")
        .. "\nAksi    : " .. Farmer.Status
    if txt == lastFarmerText then return end
    lastFarmerText = txt
    task.defer(function()
        pcall(function() UI.FarmerStatus:SetDesc(txt) end)
    end)
end

-- 1 langkah mesin panen/tanam (pakai FC):
--   kerjakan yang terjangkau, atau jalan ke target terdekat.
-- Hasil: "work" | "move" | "wait" | "idle" (+ detik ke pohon siap berikutnya)
-- Tersangkut lama di udara / pinggir block (bikin karakter diam): dorong sedikit ke samping
function Move.airCheck(s)
    if s.grounded then
        Move.AirAt = nil
        return
    end
    if not Move.AirAt then
        Move.AirAt = os.clock()
    elseif os.clock() - Move.AirAt > 3 then
        Move.AirAt = nil
        local right = (s.facing or 1) < 0 -- ke arah sebaliknya
        AutoInput.active = true
        AutoInput.right, AutoInput.left = right, not right
        task.wait(0.2)
        AutoInput.right, AutoInput.left = false, false
    end
end

local function fieldStep()
    local w = Refs.World
    local s = playerState()
    if not w or not s or s.dead then
        releaseInput()
        task.wait(0.5)
        return "wait"
    end
    if not s.grounded then
        releaseInput()
        Move.airCheck(s)
        task.wait()
        return "wait"
    end
    Move.AirAt = nil
    releaseInput()
    if FC.tractor then
        -- Mode Tractor: hanya berdiri di tile pohon siap (seed fokus). Tractor yang memanen saat dilewati.
        local R = 0.6
        local sx, sy = startNode(s)
        local px, py = floor(s.x), floor(s.y - 0.475)
        local targets, nextReady = farmerScan(px, py, 8, reachFilter(sy * w.w + sx, R, false))
        if not FC.run() or not alive() then return "wait" end
        if #targets == 0 then return "idle", nextReady end
        targets.los = false
        travelGroup(sx, sy, targets, R, false, FC.skip, FarmerFail, Farmer.dropRoute())
        return "move"
    end
    if farmerWorkInReach(s) > 0 then return "work" end
    local R = farmReach() - 0.35
    local useBlock = scaffoldId() ~= nil
    local sx, sy = startNode(s)
    local px, py = floor(s.x), floor(s.y - 0.475)
    local targets, nextReady = farmerScan(px, py, 8, reachFilter(sy * w.w + sx, R, useBlock))
    if not FC.run() or not alive() then return "wait" end
    if #targets == 0 then return "idle", nextReady end
    targets.los = targets[1].kind == "harvest" -- panen: berdiri di baris pohon (drop terambil)
    travelGroup(sx, sy, targets, R, useBlock, FC.skip, FarmerFail, Farmer.dropRoute())
    return "move"
end

-- Rute penghindar tumpukan yang baru di-drop Auto Drop (supaya tidak terambil lagi)
function Farmer.dropRoute()
    if AutoDrop.On and #AutoDrop.Zones > 0 and AutoDrop.route then return AutoDrop.route() end
    return nil
end

-- Item hasil panen yang sudah hampir penuh: seed pohon & block-nya
function Farmer.dropList()
    local out = {}
    for sid in pairs(Farmer.Got) do
        for _, id in ipairs({ sid, sid - 1 }) do
            local it = ItemDB[id]
            if it and (id == sid or it.kind ~= "seed") and not (AutoDrop.On and AutoDrop.owns and AutoDrop.owns(id)) then
                local n = invCount(id)
                local keep = (id == Farmer.SeedId) and Farmer.Keep or 0
                if n >= Farmer.DropAt and n > keep then
                    out[#out + 1] = { id = id, n = n - keep }
                end
            end
        end
    end
    return out
end

local function farmerLoop()
    local lastUi = 0
    while Farmer.Running and alive() do
        task.wait()
        if os.clock() - lastUi > 0.5 then
            lastUi = os.clock()
            updateFarmerStatus()
        end
        FC = farmerCfg()
        if not Refs.World then
            Farmer.Status = "Menunggu karakter / world..."
            task.wait(0.5)
            continue
        end
        -- inventori hampir penuh -> drop hasil panen ke titik drop
        if Pabrik.pointSet and Pabrik.pointSet() and Auto.dropTrip and os.clock() >= (Farmer.DropOffUntil or 0)
            and os.clock() - (Farmer.DropCheck or 0) > 2 then
            Farmer.DropCheck = os.clock()
            local items = Farmer.dropList()
            if #items > 0 then
                releaseInput()
                local ok, why = Auto.dropTrip(items, function() return Farmer.Running and alive() end,
                    function(t) Farmer.Status = t end)
                for _, it in ipairs(items) do Farmer.Dropped += it.got or 0 end
                if why == "home" then
                    stopFarmer("Gagal pulang ke world farmer")
                    break
                end
                if not ok then Farmer.DropOffUntil = os.clock() + ((why == "nopoint") and 60 or 120) end
                continue
            end
        end
        local r, nextReady = fieldStep()
        if r == "wait" and not playerState() then
            Farmer.Status = "Menunggu karakter / world..."
        end
        if r == "idle" then
            local parts = {}
            if Farmer.Harvest or Farmer.Tractor then
                parts[#parts + 1] = nextReady and ("pohon siap ±" .. math.ceil(nextReady) .. " dtk") or "tidak ada pohon"
            end
            if Farmer.Plant and not Farmer.Tractor then
                parts[#parts + 1] = (seedCount() <= 0) and "seed habis / belum dipilih" or "tidak ada tempat tanam"
            end
            Farmer.Status = "Menunggu: " .. table.concat(parts, ", ")
            if not waitAuto(1000) then break end
        end
    end
    releaseInput()
end

local function setFarmerVisual()
    if UI.FarmerToggle then pcall(function() UI.FarmerToggle:Set(Farmer.Running) end) end
end

stopFarmer = function(reason)
    Farmer.Running = false
    autoEnd()
    setFarmerVisual()
    Farmer.Status = reason or "Dihentikan"
    if reason then
        notify("Farmer", reason, 5)
        if not string.find(reason, "^Dihentikan") then Hook.send("stop", "Farmer berhenti: " .. reason) end
    end
    updateFarmerStatus()
end

local function startFarmer()
    if Farmer.Running then return end
    if AutoDrop.Busy then notify("Auto Drop", "Tunggu perjalanan drop selesai", 3) return end
    local err = checkAutoStart()
    if not err and not Farmer.Tractor and not Farmer.Harvest and not Farmer.Plant then
        err = "Aktifkan Auto Harvest atau Auto Plant"
    end
    if not err and not Farmer.Tractor and not Farmer.Harvest and not Farmer.SeedId then
        err = "Pilih seed dulu untuk Auto Plant"
    end
    if err then
        notify("Farmer", err, 4)
        setFarmerVisual()
        return
    end
    if (Farmer.Harvest or Farmer.Tractor) and not Refs.Trees and not findTreeRefs() then
        notify("Farmer", "Data pohon tidak ketemu: Auto Harvest tidak bisa cek pohon siap", 5)
    end
    if Pabrik.Running and Pabrik.stop then Pabrik.stop("Dihentikan karena Farmer dimulai") end
    if Build.Running and Build.stop then Build.stop("Dihentikan karena Farmer dimulai") end
    if State.Running then stopFarm("Dihentikan karena Farmer dimulai") end
    if Clear.Running then stopClear("Dihentikan karena Farmer dimulai") end
    table.clear(Farmer.Skip)
    table.clear(FarmerFail)
    table.clear(BadEdge)
    table.clear(Farmer.Row)
    Farmer.DropOffUntil = 0
    Farmer.Status = "Mulai..."
    Farmer.Running = true
    autoBegin()
    setFarmerVisual()
    updateFarmerStatus()
    task.spawn(function()
        local ok, e = pcall(farmerLoop)
        if not ok then
            warn("[n4th] Farmer error: " .. tostring(e))
            if Farmer.Running then stopFarmer("Error: " .. tostring(e)) end
        end
    end)
end

---------------------------------------------------------------------
-- Jalan ke 1 tile tertentu (dipakai Penjaga: balik ke posisi Auto Farm).
-- Pakai A* yang sama, tanpa taruh block.
local function walkTo(tx, ty, maxSec, live, route)
    local w = Refs.World
    if not w or not OrigIsDown then return false end
    if tx < 0 or ty < 0 or tx >= w.w or ty >= w.h then return false end
    if route and not route.point(tx, ty) then return false end
    Move.Homing = true
    Move.HomingLive = live
    Move.HomingRoute = route
    autoBegin()
    local goal = { [ty * w.w + tx] = true }
    local t0, ok = os.clock(), false
    while alive() and Move.Homing and (not live or live()) and os.clock() - t0 < (maxSec or 30) do
        local s = playerState()
        if not s or s.dead then
            task.wait(0.3) -- tunggu respawn / world selesai dimuat
        else
            local sx, sy = startNode(s)
            if sx == tx and sy == ty and s.grounded then
                ok = not route or execWalk(tx, ty, 0.08)
                break
            end
            local path = astar(sx, sy, goal, tx, ty, 0.5, false, route)
            if not path then break end -- tidak ada jalan
            if #path > 0 then followPath(path) end
            releaseInput()
            task.wait(0.15)
        end
    end
    Move.Homing = false
    Move.HomingLive = nil
    Move.HomingRoute = nil
    autoEnd()
    return ok
end

---------------------------------------------------------------------
-- LAHAN: bentuk farm world
---------------------------------------------------------------------
-- Baris block dari Y atas ke bawah, selalu 1 tile kosong di antaranya (tempat pohon & jalan).
-- Jumlah baris otomatis: turun terus menembus tanah sampai bedrock. Kalau bedrock jatuh di baris
-- lahan, bedrock itu jadi lantai baris terakhir (tanah tepat di atas bedrock ikut digali).
-- (tanah di celah baris digali Bangun Lahan, tanah di baris lahan dipakai sebagai lahan).
-- Kedua ujung baris dibuat tangga (lihat landCols).
-- Hasil disimpan sebentar (dipanggil sangat sering oleh Pabrik / status).
local function landRows()
    local w = Refs.World
    if not w then return {} end
    local x0 = math.clamp(math.floor(math.min(Land.X0, Land.X1)), 0, w.w - 1)
    local x1 = math.clamp(math.floor(math.max(Land.X0, Land.X1)), 0, w.w - 1)
    local y0 = math.max(1, math.floor(Land.Y0))
    local c = Land.Cache
    local now = os.clock()
    if c and c.w == w and c.x0 == x0 and c.x1 == x1 and c.y0 == y0 and now - c.at < 2 then
        return c.rows
    end
    local rows = {}
    local span = x1 - x0 + 1
    -- block yang tidak bisa dipecah (bedrock dll)
    local function hard(x, y)
        local id = fgIdAt(x, y)
        if id == 0 then return false end
        local it = ItemDB[id]
        return it ~= nil and it.solid == true and not canBreak(id)
    end
    local y = y0
    while y <= w.h - 2 and #rows < 40 do
        local hg, hr = 0, 0
        for x = x0, x1 do
            if hard(x, y - 1) then hg += 1 end
            if hard(x, y) then hr += 1 end
        end
        if hg * 2 > span then break end -- celahnya bedrock: berhenti
        rows[#rows + 1] = y
        if hr * 2 > span then break end -- baris ini bedrock: jadi lantai paling bawah
        y += 2
    end
    Land.Cache = { w = w, x0 = x0, x1 = x1, y0 = y0, at = now, rows = rows }
    return rows
end

-- Tile lahan sudah jadi? (block padat apa saja, bukan pohon / lava / duri)
function Build.done(x, y)
    local id = fgIdAt(x, y)
    if id == 0 then return false end
    local it = ItemDB[id]
    if not it or it.kind == "seed" or not it.solid then return false end
    return not (it.deadly or it.hurts or it.laser)
end

-- Kolom block baris ke-k (0 = paling atas). Tangga 2 kolom di KIRI dan KANAN:
--   baris ke-1, 3, 5.. : x0+1 .. x1-1              (kolom x0 & x1 kosong)
--   baris ke-2, 4, 6.. : x0, x0+2 .. x1-2, x1      (kolom x0+1 & x1-1 kosong)
-- Jadi dari ujung mana saja bisa turun (jatuh 2 tile ke anak tangga di bawahnya)
-- dan naik (lompat 2 tile), selang-seling seperti tangga.
local function landCols(k)
    local w = Refs.World
    local x0 = math.clamp(math.floor(math.min(Land.X0, Land.X1)), 0, w.w - 1)
    local x1 = math.clamp(math.floor(math.max(Land.X0, Land.X1)), 0, w.w - 1)
    local cols = {}
    if x1 - x0 < 4 then -- terlalu sempit untuk tangga
        for x = x0, x1 do cols[#cols + 1] = x end
    elseif k % 2 == 0 then
        for x = x0 + 1, x1 - 1 do cols[#cols + 1] = x end
    else
        cols[#cols + 1] = x0
        for x = x0 + 2, x1 - 2 do cols[#cols + 1] = x end
        cols[#cols + 1] = x1
    end
    return cols
end

local function inLandRect(x, y)
    local rows = landRows()
    if #rows == 0 then return false end
    local x0 = math.min(Land.X0, Land.X1)
    local x1 = math.max(Land.X0, Land.X1)
    return x >= x0 and x <= x1 and y >= rows[1] - 1 and y <= rows[#rows]
end

-- Tile block lahan: [idx] = true
local function landBlockSet()
    local set = {}
    local w = Refs.World
    if not w then return set end
    for k, y in ipairs(landRows()) do
        for _, x in ipairs(landCols(k - 1)) do set[y * w.w + x] = true end
    end
    return set
end

-- Tile tanam lahan (di atas block yang sudah terpasang): [idx] = true
local function landPlantSet()
    local set = {}
    local w = Refs.World
    if not w then return set end
    for k, y in ipairs(landRows()) do
        for _, x in ipairs(landCols(k - 1)) do
            if fgIdAt(x, y) ~= 0 and y - 1 >= 0 then set[(y - 1) * w.w + x] = true end
        end
    end
    return set
end

-- Hitung kebutuhan block lahan (+ sisa tile yang harus digali)
local function landInfo(blockId, P0, carve0)
    local info = { rows = 0, total = 0, need = 0, done = 0, blocked = 0, carve = 0 }
    local w = Refs.World
    if not w then return info end
    local rows = landRows()
    info.rows = #rows
    for k, y in ipairs(rows) do
        for _, x in ipairs(landCols(k - 1)) do
            info.total += 1
            if Build.done(x, y) then
                info.done += 1
            else
                info.need += 1
                if fgIdAt(x, y) ~= 0 then info.blocked += 1 end -- pohon / lava dll: dipecah dulu lalu dipasang
            end
        end
    end
    if carve0 then
        info.carve = #carve0
    else
        local P = P0 or (Build.plan and Build.plan())
        if P then info.carve = #Build.carveList(P) end
    end
    return info
end

-- Seed <-> block (seed biasanya id block + 1, kecuali item khusus yang punya seedId)
local function seedOfBlock(block)
    local it = block and ItemDB[block]
    if not it then return nil end
    local sid = it.seedId or (block + 1)
    local sd = ItemDB[sid]
    if sd and sd.kind == "seed" then return sid end
    return nil
end

local function blockOfSeed(seed)
    if not seed then return nil end
    local b = seed - 1
    local it = ItemDB[b]
    if it and it.kind ~= "seed" and (it.seedId == nil or it.seedId == seed) then return b end
    return nil
end

local function readyTreeCount(whole, only)
    local w = Refs.World
    if not w then return 0 end
    local st = workspace:GetServerTimeNow()
    local x0, x1, y0, y1 = 0, w.w - 1, 0, w.h - 1
    if not whole then
        local rows = landRows()
        if #rows == 0 then return 0 end
        x0 = math.max(0, math.min(Land.X0, Land.X1))
        x1 = math.min(w.w - 1, math.max(Land.X0, Land.X1))
        y0, y1 = math.max(0, rows[1] - 1), rows[#rows]
    end
    local n, nxt = 0, nil
    for y = y0, y1 do
        for x = x0, x1 do
            local id = fgIdAt(x, y)
            if id ~= 0 and (not only or id == only) then
                local ra = treeReadyAt(x, y, id)
                if ra then
                    if st >= ra then
                        n += 1
                    elseif not nxt or ra - st < nxt then
                        nxt = ra - st
                    end
                end
            end
        end
    end
    return n, nxt
end

---------------------------------------------------------------------
-- PABRIK
---------------------------------------------------------------------
-- Fase (berputar terus):
--   PANEN : panen semua pohon siap di lahan (berhenti kalau block / seed hampir 200)
--   TANAM : tanam seed di semua tile lahan yang kosong
--   BREAK : jalan ke posisi break, Auto Farm (place + break) di tile pabrik sampai block HABIS
--           (tidak diselingi cek pohon; berhenti hanya kalau seed harus di-drop / penuh / macet)
--   TUNGGU: tunggu pohon siap, lalu kembali ke PANEN
--   Kapan saja seed >= batas drop -> pergi drop (seed - sisakan), lalu pulang.
-- Inventori maksimal 200 per item, jadi semua fase dijaga supaya tidak penuh.
-- Drop yang jatuh di tempat drop tidak di-collect lagi.
local BOOT_SEEDS = 10 -- (mode produksi) cukup seed segini untuk mulai tanam
local CAP = 190       -- batas aman jumlah item (maksimal 200 per item)

local function pabrikCfg(o, harvest, plant)
    local plantSet, area = nil, nil
    if not o.whole then
        plantSet = landPlantSet()
        area = inLandRect
    end
    return {
        run = o.live,
        harvest = harvest,
        plant = plant and invCount(o.seed) > 0,
        seed = o.seed,
        skip = Pabrik.Skip,
        hms = Farmer.HarvestMs,
        pms = Farmer.PlantMs,
        area = area,
        plantSet = plantSet,
        exclude = o.exclude,
        row = Pabrik.Row,
        collect = true,
        status = function(t) Pabrik.Status = t end,
        onHarvest = function() Pabrik.Harvested += 1 end,
        onPlant = function() Pabrik.Planted += 1 end,
    }
end

-- Break block di posisi pabrik (pakai Auto Farm dengan tile & block pabrik)
local function pabrikBreak(o)
    if os.clock() < (Pabrik.BreakFailUntil or 0) then return false end
    local s = playerState()
    if not s then return false end
    local hx, hy = startNode(s)
    if hx ~= Pabrik.BreakX or hy ~= Pabrik.BreakY then
        Pabrik.Status = ("Jalan ke posisi break (%d,%d)"):format(Pabrik.BreakX, Pabrik.BreakY)
        if not walkTo(Pabrik.BreakX, Pabrik.BreakY, 45) then
            Pabrik.Status = "Gagal jalan ke posisi break, dicoba lagi nanti"
            Pabrik.BreakFailUntil = os.clock() + 30
            return false
        end
    end
    if not o.live() then return false end
    State.Override = { offsets = Pabrik.Tiles, block = o.block, mode = "Place + Break" }
    State.Quiet = true
    table.clear(HitCount)
    table.clear(PlacedAt)
    State.Running = true
    State.RunId = (State.RunId or 0) + 1
    local id = State.RunId
    local acts0 = State.Placed + State.Broken
    local lastActs, lastActAt = acts0, os.clock()
    task.spawn(function() -- pengawas sesi break
        while State.Running and State.RunId == id do
            task.wait(1)
            local sd = invCount(o.seed)
            local acts = State.Placed + State.Broken
            if acts ~= lastActs then lastActs, lastActAt = acts, os.clock() end
            -- break terus sampai block habis (tanpa batas waktu sesi)
            if not o.live() or sd >= CAP
                or (o.drop and Pabrik.Drop and sd >= Pabrik.DropAt)
                or (o.breakMode ~= "always" and sd >= BOOT_SEEDS)
                or os.clock() - lastActAt > 8 then -- 8 detik tidak ada place / pukul: jangan diam di sini
                State.Running = false
            end
        end
    end)
    Pabrik.Status = "Break " .. itemName(o.block) .. " di posisi pabrik"
    local ok, e = pcall(farmLoop, id)
    if not ok then warn("[n4th] Pabrik break error: " .. tostring(e)) end
    State.Running = false
    State.Override = nil
    State.Quiet = false
    if State.Placed + State.Broken == acts0 and invCount(o.block) > 0 then
        Pabrik.BreakFailUntil = os.clock() + 60
        Pabrik.Status = "Sesi break tanpa aksi: cek posisi & tile break (dicoba lagi 1 menit)"
    end
    return true
end

-- "WORLD" / "WORLD:ID" / ":ID" -> nama world, id pintu
local function parseDropTarget()
    local raw = tostring(Pabrik.DropWorld or ""):gsub("%s", "")
    local name, door = string.match(raw, "^([^:]*):(.+)$")
    if not name then name = raw end
    name = string.upper(name):gsub("[^A-Z0-9]", "")
    if door == "" then door = nil end
    return name, door
end

-- Pindah world (lewat menu game), bisa langsung ke pintu tertentu
local function goWorld(name, door)
    if Guard.worldName() ~= "" then
        Guard.leaveWorld()
        task.wait(2)
    end
    if door and Refs.World then rawset(Refs.World, "arriveDoor", door) end
    local ok, err = Guard.enterWorld(name)
    if ok then
        task.wait(1.5)
        Guard.afterEnter()
    end
    return ok, err
end

-- Drop pakai fungsi drop game (item jatuh di depan karakter)
local function dropItems(id, n, live, allowFlip)
    local hud = Refs.Hud
    local f = hud and rawget(hud, "onDrop")
    if type(f) ~= "function" then return 0, "fungsi drop game tidak ketemu" end
    local left, flipped = n, false
    while left > 0 and live() do
        local before = invCount(id)
        local amount = math.min(left, 200, before)
        if amount <= 0 then return n - left, "item sudah habis" end
        local ok, err = pcall(f, id, amount)
        if not ok then return n - left, tostring(err) end
        task.wait(0.7) -- game menolak drop yang terlalu cepat (0.3 dtk)
        local got = before - invCount(id)
        if got > 0 then
            left -= got
        elseif not flipped and allowFlip ~= false then
            -- di depan tembok / tidak boleh drop: hadap ke arah lain lalu coba lagi
            flipped = true
            local st = playerState()
            local right = st and (st.facing or 1) < 0
            AutoInput.active = true
            AutoInput.right, AutoInput.left = right, not right
            task.wait(0.06)
            AutoInput.right, AutoInput.left = false, false
            task.wait(0.3)
        else
            return n - left, "tidak bisa drop di posisi ini"
        end
    end
    return n - left, nil
end

-- Titik drop bersama (dipakai Pabrik, Farmer, Auto Farm):
-- pergi ke titik drop (bisa world lain / WORLD:ID), drop item, lalu pulang ke world asal.
-- items = { { id =, n = }, ... }  -> it.got diisi jumlah yang berhasil di-drop
-- Hasil: ok, alasan ("nopoint" | "home" | teks error)
local function dropTrip(items, live, say)
    say = say or function() end
    local name, door = parseDropTarget()
    local home = Guard.worldName()
    if name == "" then name = home end
    if Pabrik.DropX < 0 and not door and name == home then
        say("Titik drop belum diatur (tab Titik Drop), drop dilewati")
        return false, "nopoint"
    end
    Pabrik.Traveling = true
    local away = name ~= home
    local ok, why = true, nil
    if away or door then
        say("Pergi ke " .. name .. (door and (":" .. door) or "") .. " untuk drop")
        local okw, err = goWorld(name, door)
        if not okw then ok, why = false, "gagal masuk " .. name .. " (" .. tostring(err) .. ")" end
    end
    if ok and live() and Pabrik.DropX >= 0 then
        say(("Jalan ke posisi drop (%d,%d)"):format(Pabrik.DropX, Pabrik.DropY))
        if not walkTo(Pabrik.DropX, Pabrik.DropY, 60) then ok, why = false, "tidak bisa jalan ke posisi drop" end
    end
    if ok and live() then
        local s = playerState()
        if s then Pabrik.Zone = { world = Guard.worldName(), x = s.x, y = s.y - 0.475 } end
        for _, it in ipairs(items) do
            if not live() then break end
            local got, err = dropItems(it.id, it.n, live)
            it.got = got
            if got > 0 then
                local msg = ("Drop %s x%d di %s"):format(itemName(it.id), got, Guard.worldName())
                say(msg)
                notify("Drop", msg, 4)
                Hook.send("pabrik", msg)
            end
            if err then
                ok, why = false, err
                break
            end
        end
    end
    if not ok then
        say("Drop gagal: " .. tostring(why))
        notify("Drop", "Drop gagal: " .. tostring(why), 5)
        Hook.send("pabrik", "Drop gagal: " .. tostring(why))
    end
    -- pulang ke world asal
    if away and home ~= "" and live() then
        say("Pulang ke " .. home)
        local okh = goWorld(home, nil)
        if not okh and live() then
            task.wait(5)
            okh = goWorld(home, nil)
        end
        if not okh then
            Pabrik.Traveling = false
            autoEnd()
            return false, "home"
        end
    end
    Pabrik.Traveling = false
    autoEnd()
    return ok, why
end
Auto.dropTrip = dropTrip

-- Auto Drop instan: seed fokus & block-nya yang mencapai 200 langsung di-drop di posisi karakter berada.
-- Tidak jalan ke tile khusus dan tidak balik lagi, jadi cocok dipakai bersama tractor.
do
    local ALL_LABEL = "(Semua seed)"

    -- Item milik Auto Drop = seed fokus + block-nya.
    function AutoDrop.owns(id)
        local seed = Farmer.Focus
        if not seed or type(id) ~= "number" then return false end
        return id == seed or id == blockOfSeed(seed)
    end

    function AutoDrop.targets()
        local out, seed = {}, Farmer.Focus
        if not seed then return out end
        out[1] = { id = seed, kind = "Seed" }
        local block = blockOfSeed(seed)
        if block then out[2] = { id = block, kind = "Block" } end
        return out
    end

    function AutoDrop.targetError()
        if not Refs.World or not Refs.Inv or not playerState() then return "Masuk world dan hubungkan referensi game dulu" end
        if not Refs.Hud or type(rawget(Refs.Hud, "onDrop")) ~= "function" then return "Fungsi drop game belum ketemu" end
        return nil
    end

    -- Syarat menyalakan toggle: seed fokus sudah dipilih.
    function AutoDrop.startError()
        if not Farmer.Focus then return "Pilih seed fokus dulu" end
        return AutoDrop.targetError()
    end

    -- Id seed / block fokus yang sudah mencapai 200.
    function AutoDrop.fullItems()
        local items = {}
        for _, t in ipairs(AutoDrop.targets()) do
            if invCount(t.id) >= 200 then items[#items + 1] = t.id end
        end
        return items
    end

    -- Hitung pohon siap panen per seed di seluruh world.
    function AutoDrop.scanReady()
        local w, counts = Refs.World, {}
        if not w or not Refs.Trees then return counts end
        local st = workspace:GetServerTimeNow()
        for y = 0, w.h - 1 do
            local row = w.fg[y]
            if row then
                for x = 0, w.w - 1 do
                    local id = row[x] or 0
                    if id ~= 0 then
                        local ra = treeReadyAt(x, y, id)
                        if ra and st >= ra then counts[id] = (counts[id] or 0) + 1 end
                    end
                end
            end
        end
        return counts
    end

    -- Daftar pilihan seed fokus: seed yang punya pohon siap panen sekarang.
    function AutoDrop.focusLabels(force)
        if force or not AutoDrop.ReadyCounts or os.clock() - (AutoDrop.ScanAt or 0) > 6 then
            AutoDrop.ReadyCounts = AutoDrop.scanReady()
            AutoDrop.ScanAt = os.clock()
        end
        local counts, ids = AutoDrop.ReadyCounts, {}
        for id in pairs(counts) do ids[#ids + 1] = id end
        if Farmer.Focus and not counts[Farmer.Focus] then ids[#ids + 1] = Farmer.Focus end
        table.sort(ids)
        local labels, selected = { ALL_LABEL }, ALL_LABEL
        for _, id in ipairs(ids) do
            local label = ("%s [%d] - %d siap"):format(itemName(id), id, counts[id] or 0)
            labels[#labels + 1] = label
            if id == Farmer.Focus then selected = label end
        end
        return labels, selected
    end

    function AutoDrop.focusFromLabel(label)
        if type(label) == "table" then label = label[1] end
        return tonumber(tostring(label or ""):match("%[(%d+)%] %- %d+ siap$"))
    end

    -- Tandai tumpukan yang baru di-drop supaya tidak diambil lagi oleh collect / jalur jalan.
    local function protectDrop(id, x, y, world, facing)
        AutoDrop.Zones[#AutoDrop.Zones + 1] = {
            id = id, x = x, y = y, world = world, dropX = x + facing, dropY = y, at = os.clock(),
        }
        while #AutoDrop.Zones > 60 do table.remove(AutoDrop.Zones, 1) end
    end

    -- Buang zona yang tumpukannya sudah tidak ada (sudah diambil / hilang).
    function AutoDrop.prune()
        if not Drops.list then return end
        local now = os.clock()
        for i = #AutoDrop.Zones, 1, -1 do
            local zone = AutoDrop.Zones[i]
            if now - (zone.at or 0) > 10 then
                local found = false
                for _, drop in pairs(Drops.list) do
                    if type(drop) == "table" and drop.id == zone.id and (drop.n or 0) > 0
                        and type(drop.x) == "number" and type(drop.y) == "number"
                        and abs(drop.x - zone.x) <= 2.5 and abs(drop.y - zone.y) <= 2.5 then
                        found = true
                        break
                    end
                end
                if not found then table.remove(AutoDrop.Zones, i) end
            end
        end
    end

    -- Hindari koordinat item asli, dengan cadangan arah drop selama replikasi.
    function AutoDrop.route()
        local obstacles, current = {}, playerState()
        for _, zone in ipairs(AutoDrop.Zones) do
            if zone.world == Guard.worldName() then
                local found = false
                for _, drop in pairs(Drops.list or {}) do
                    if type(drop) == "table" and drop.id == zone.id and (drop.n or 0) > 0
                        and type(drop.x) == "number" and type(drop.y) == "number"
                        and abs(drop.x - zone.x) <= 2.5 and abs(drop.y - zone.y) <= 2.5 then
                        obstacles[#obstacles + 1] = { x = drop.x, y = drop.y }
                        found = true
                    end
                end
                if os.clock() - (zone.at or 0) < 5 or (not found and not Drops.list) then
                    obstacles[#obstacles + 1] = { x = zone.dropX or zone.x, y = zone.dropY or zone.y }
                end
            end
        end
        local radius = 0.85 -- jarak sentuh game sekitar 0.6 tile, ditambah ruang berhenti
        local function inside(x, y, item) return abs(x - item.x) < radius and abs(y - item.y) < radius end
        for _, item in ipairs(obstacles) do
            item.escaping = current and inside(current.x, current.y - 0.475, item) or false
            item.startDistance = current and abs(current.x - item.x) or 0
        end
        local route = {}
        function route.point(x, y)
            for _, item in ipairs(obstacles) do if inside(x + 0.5, y + 0.5, item) then return false end end
            return true
        end
        function route.edge(fx, fy, tx, ty, kind)
            local x0, y0, x1, y1 = fx + 0.5, fy + 0.5, tx + 0.5, ty + 0.5
            for _, item in ipairs(obstacles) do
                if inside(x0, y0, item) then
                    -- Keluar dari radius drop hanya dengan berjalan menjauh.
                    if kind ~= "walk" or fy ~= ty or (x0 - item.x) * (x1 - item.x) <= 0
                        or abs(x1 - item.x) <= abs(x0 - item.x) then return false end
                else
                    local top = math.min(y0, y1)
                    if kind == "jump" or kind == "gap" or kind == "stair" then top -= 3 end
                    if math.max(x0, x1) > item.x - radius and math.min(x0, x1) < item.x + radius
                        and math.max(y0, y1) > item.y - radius and top < item.y + radius then return false end
                end
            end
            return true
        end
        function route.safe(s)
            if not s then return false end
            for _, item in ipairs(obstacles) do
                if inside(s.x, s.y - 0.475, item) then
                    if not item.escaping or abs(s.x - item.x) < item.startDistance - 0.02 then return false end
                else item.escaping = false end
            end
            return true
        end
        return route
    end

    -- Drop sekarang juga di posisi karakter, tanpa berhenti / pindah.
    function AutoDrop.dropNow(items)
        AutoDrop.Busy = true
        local world, failure = Guard.worldName(), nil
        local refWorld = Refs.World
        local function live() return alive() and AutoDrop.On and Refs.World == refWorld end
        local ok, err = pcall(function()
            for _, id in ipairs(items) do
                if not live() then break end
                if invCount(id) >= 200 then
                    local s = playerState()
                    if not s or s.dead then failure = "Karakter belum siap" break end
                    local facing = (s.facing or 1) < 0 and -1 or 1
                    AutoDrop.Status = "Drop " .. itemName(id) .. " x200"
                    protectDrop(id, s.x, s.y - 0.475, world, facing) -- ditandai sebelum item muncul
                    local got, reason = dropItems(id, 200, live, true)
                    AutoDrop.Dropped += got
                    if reason then failure = reason break end
                end
            end
        end)
        if not ok then failure = tostring(err) end
        AutoDrop.Busy = false
        AutoDrop.NextTry = os.clock() + (failure and 2 or 0.5)
        AutoDrop.Status = failure and ("Drop gagal: " .. failure)
            or (AutoDrop.On and "Menunggu seed / block fokus mencapai 200" or "Mati")
        if failure and os.clock() - (AutoDrop.NotifyAt or 0) > 30 then
            AutoDrop.NotifyAt = os.clock()
            notify("Auto Drop", "Drop gagal: " .. failure, 4)
        end
    end

    task.spawn(function()
        while alive() do
            task.wait(0.25)
            if AutoDrop.On then pcall(AutoDrop.prune) end
            if Session.Ready and AutoDrop.On and not AutoDrop.Busy and Guard.Mode == "idle"
                and not Pabrik.Traveling and os.clock() >= (AutoDrop.NextTry or 0) then
                local ok, err = pcall(function()
                    local reason = AutoDrop.targetError()
                    if reason then AutoDrop.Status = reason return end
                    if not Farmer.Focus then AutoDrop.Status = "Pilih seed fokus dulu" return end
                    local items = AutoDrop.fullItems()
                    if #items > 0 then
                        AutoDrop.dropNow(items)
                    else
                        AutoDrop.Status = "Menunggu seed / block fokus mencapai 200"
                    end
                end)
                if not ok then
                    AutoDrop.Status = tostring(err)
                    AutoDrop.NextTry = os.clock() + 5
                    warn("[n4th] Auto Drop: " .. tostring(err))
                end
            end
        end
    end)
end

---------------------------------------------------------------------
-- AUTO ROUTE DROP
-- Menelusuri drop terpilih yang berada di atas platform pilihan. Setelah inventori
-- mencapai 200, pergi ke Drop Point, drop 200, lalu kembali ke jalur terakhir.
---------------------------------------------------------------------
local function routeDropLive()
    return alive() and RouteDrop.Running and Refs.World == RouteDrop.World
        and Guard.Mode == "idle" and not AutoDrop.Busy and not Pabrik.Traveling
end

local function routeDropPlatformRow(d)
    if not d or type(d.x) ~= "number" or type(d.y) ~= "number" or not RouteDrop.PlatformId then return nil end
    -- Ambil baris Y pijakan Wooden Platform terdekat di bawah/sekitar drop.
    -- Koordinat world bertambah ke bawah, sehingga urutan Y menaik = atas ke bawah.
    local xs = { math.floor(d.x), math.floor(d.x + 0.5), math.floor(d.x - 0.5) }
    local baseY = math.floor(d.y + 0.5)
    local ys = { baseY - 1, baseY, baseY + 1, baseY + 2 }
    local bestY, bestDist
    for _, x in ipairs(xs) do
        for _, y in ipairs(ys) do
            if fgIdAt(x, y) == RouteDrop.PlatformId then
                local dist = math.abs(y - (d.y + 0.5))
                if not bestDist or dist < bestDist then bestY, bestDist = y, dist end
            end
        end
    end
    return bestY
end

local function routeDropOnPlatform(d)
    return routeDropPlatformRow(d) ~= nil
end

local function routeDropAtPoint(d)
    return math.abs(d.x - (RouteDrop.DropX + 0.5)) <= 2.5
        and math.abs(d.y - (RouteDrop.DropY + 0.5)) <= 2.5
end

local function routeDropTargets()
    local list, out = Drops.list, {}
    if not list then return out end
    local now = os.clock()
    local diag = { total = 0, item = 0, position = 0, armed = 0, platform = 0, ready = 0 }
    -- pairs dipakai agar drop tetap terbaca jika daftar game memiliki index yang berlubang.
    for _, d in pairs(list) do
        if type(d) == "table" then
            diag.total += 1
            if d.id == RouteDrop.TargetId and (d.n or 0) > 0 then
                diag.item += 1
                if type(d.x) == "number" and type(d.y) == "number" then
                    diag.position += 1
                    if d.armed ~= false and not routeDropAtPoint(d) then
                        diag.armed += 1
                        if routeDropOnPlatform(d) then
                            diag.platform += 1
                            local key = d.uid or d
                            if not (RouteDrop.Skip[key] and now < RouteDrop.Skip[key]) then
                                out[#out + 1] = d
                                diag.ready += 1
                            end
                        end
                    end
                end
            end
        end
    end
    RouteDrop.LastScanDiag = diag
    -- Urutan tetap: satu baris pijakan penuh dahulu, kanan ke kiri;
    -- setelah habis baru turun ke baris berikutnya.
    table.sort(out, function(a, b)
        local ay, by = routeDropPlatformRow(a) or math.huge, routeDropPlatformRow(b) or math.huge
        if ay ~= by then return ay < by end
        return a.x > b.x
    end)
    return out
end

local function routeDropDoDrop(resumeX, resumeY)
    if invCount(RouteDrop.TargetId) < 200 then return true end
    local live = routeDropLive
    local dx, dy = RouteDrop.DropX, RouteDrop.DropY
    -- Jangan memaksa kembali ke spawn world. Spawn dapat berada di area yang
    -- tidak terhubung dengan pijakan aktif, sehingga walkTo akan gagal berulang.
    -- Gunakan rute A* langsung dari posisi karakter saat ini ke Drop Point pilihan.
    RouteDrop.Status = ("Langsung menuju Drop Point (%d,%d)"):format(dx, dy)
    routeDropLog(("Item mencapai 200; melewati Spawn world dan langsung menuju Drop Point (%d,%d)."):format(dx, dy), true)
    if not live() then return false end
    RouteDrop.Status = ("Menuju Drop Point (%d,%d)"):format(dx, dy)
    routeDropLog("Melanjutkan perjalanan ke Drop Point " .. dx .. "," .. dy, true)
    if not walkTo(dx, dy, 60, live) then
        RouteDrop.Status = "Gagal mencapai Drop Point"
        routeDropLog("ERROR: walkTo gagal mencapai Drop Point. Periksa pijakan/jalur dan koordinat.", true)
        return false
    end
    if not live() then return false end
    local st = playerState()
    if not st then RouteDrop.Status = "Posisi karakter tidak terbaca" return false end
    local facing = (st.facing or 1) < 0 and -1 or 1
    local zoneX, zoneY = st.x + facing, st.y - 0.475
    -- Zona drop dikecualikan dari tracking dan collector untuk item target ini.
    AutoDrop.Zones[#AutoDrop.Zones + 1] = {
        id = RouteDrop.TargetId, x = zoneX, y = zoneY,
        dropX = zoneX, dropY = zoneY, world = Guard.worldName(), at = os.clock(),
    }
    while #AutoDrop.Zones > 60 do table.remove(AutoDrop.Zones, 1) end
    RouteDrop.Status = "Drop " .. itemName(RouteDrop.TargetId) .. " x200"
    local beforeDrop = invCount(RouteDrop.TargetId)
    routeDropLog(("Memanggil dropItems: item=%d, jumlah inventori=%d, diminta=200"):format(RouteDrop.TargetId, beforeDrop), true)
    local got, err = dropItems(RouteDrop.TargetId, 200, live, true)
    RouteDrop.Dropped += got
    if err or got <= 0 then
        RouteDrop.Status = "Drop gagal: " .. tostring(err or "tidak ada item yang ter-drop")
        routeDropLog("ERROR: proses drop gagal: " .. tostring(err or "jumlah drop 0"), true)
        return false
    end
    routeDropLog(("DROP BERHASIL: %s x%d; sisa inventori=%d"):format(itemName(RouteDrop.TargetId), got, invCount(RouteDrop.TargetId)), true)
    if not live() then return false end
    RouteDrop.Status = "Kembali ke jalur farming"
    if resumeX and resumeY then
        if not walkTo(resumeX, resumeY, 60, live) then
            RouteDrop.Status = "Drop berhasil, tetapi gagal kembali ke jalur"
            routeDropLog("WARNING: drop berhasil tetapi walkTo gagal kembali ke posisi farming.", true)
            return false
        end
        routeDropLog(("Kembali ke jalur berhasil di (%d,%d)"):format(resumeX, resumeY), true)
    end
    return true
end

-- Jalan lurus satu baris pijakan (xa -> xb) tanpa berhenti di tiap drop.
-- Berhenti sendiri kalau item target sudah 200.
local function routeDropSweep(rowY, xa, xb)
    local w = Refs.World
    if not w then return false end
    local standY = rowY - 1 -- badan berdiri di atas platform
    if standY < 0 then return false end
    local target = RouteDrop.TargetId
    local function live()
        return routeDropLive() and invCount(target) < 200
    end
    Move.Homing = true
    Move.HomingLive = live
    Move.HomingRoute = nil
    autoBegin()
    local ok = true
    for _, tx in ipairs({ xa, xb }) do
        if not live() then ok = false break end
        local s = playerState()
        if not s or s.dead then ok = false break end
        local sx, sy = startNode(s)
        if not (sx == tx and sy == standY) then
            local goal = { [standY * w.w + tx] = true }
            local path = astar(sx, sy, goal, tx, standY, 0.5, false)
                or astar(sx, sy, goal, tx, standY, 1.2, false)
            if not path then ok = false break end
            if #path > 0 and not followPath(path) then ok = false break end
        end
    end
    Move.Homing = false
    Move.HomingLive = nil
    releaseInput()
    autoEnd()
    return ok
end

--------------------------- BLOK B ----------------------------------
local function routeDropStep()
    if RouteDrop.World and Refs.World ~= RouteDrop.World then
        RouteDrop.Running = false
        RouteDrop.Status = "World berubah; Auto Route Drop dihentikan untuk keamanan"
        routeDropLog("ERROR: referensi world berubah; fitur dihentikan.", true)
        releaseInput()
        return
    end
    if not RouteDrop.TargetId or not RouteDrop.PlatformId then
        RouteDrop.Status = "Pilih item target dan platform pijakan"
        routeDropLog("Menunggu konfigurasi: TargetId=" .. tostring(RouteDrop.TargetId) .. ", PlatformId=" .. tostring(RouteDrop.PlatformId))
        return
    end
    if RouteDrop.DropX < 0 or RouteDrop.DropY < 0 then
        RouteDrop.Status = "Tentukan Drop Point terlebih dahulu"
        return
    end
    if not Refs.World or type(Refs.State) ~= "function" then
        RouteDrop.Status = "Masuk world dan tunggu data karakter"
        routeDropLog("MENUNGGU: referensi world/state belum siap.")
        return
    end
    if not playerState() then
        RouteDrop.Status = "Menunggu data karakter dari Refs.State"
        return
    end
    if not Drops.list then
        findDropRefs()
        RouteDrop.Status = "Mencari daftar drop di world"
        return
    end

    -- Sudah penuh: ke Drop Point, drop, lalu balik ke posisi terakhir
    if invCount(RouteDrop.TargetId) >= 200 then
        local s = playerState()
        local x, y
        if s then x, y = startNode(s) end
        routeDropDoDrop(x, y)
        return
    end

    local targets = routeDropTargets() -- sudah urut: baris paling atas dulu
    if #targets == 0 then
        RouteDrop.Status = "Menunggu drop target di platform"
        return
    end

    -- Ambil satu baris pijakan (paling atas), cari ujung kiri & kanan drop-nya
    local rowY = routeDropPlatformRow(targets[1])
    local lo, hi, count = math.huge, -math.huge, 0
    for _, d in ipairs(targets) do
        if routeDropPlatformRow(d) == rowY then
            local x = math.floor(d.x)
            if x < lo then lo = x end
            if x > hi then hi = x end
            count += 1
        end
    end
    local xa, xb = lo, hi
    if RouteDrop.Direction == "Kanan → Kiri" then xa, xb = hi, lo end

    RouteDrop.Status = ("Sweep baris y %d: x %d → %d (%d drop)"):format(rowY, xa, xb, count)
    routeDropLog(("Sweep lurus baris pijakan y=%d dari x=%d ke x=%d, drop=%d"):format(rowY, xa, xb, count), true)

    local ok = routeDropSweep(rowY, xa, xb)
    task.wait(0.25) -- tunggu balasan server untuk drop terakhir yang tersentuh
    RouteDrop.CollectedStops += 1

    -- Penuh di tengah jalan: ke Drop Point lalu balik ke titik berhenti tadi
    if invCount(RouteDrop.TargetId) >= 200 then
        table.clear(BadEdge) -- jalur yang terputus karena penuh bukan jalur buruk
        local s = playerState()
        local rx, ry
        if s then rx, ry = startNode(s) end
        routeDropLog(("Penuh di tengah sweep; resume di (%s,%s)"):format(tostring(rx), tostring(ry)), true)
        routeDropDoDrop(rx, ry)
        return
    end

    -- Drop yang masih tersisa di baris ini (tidak tersentuh) dilewati sebentar
    -- supaya tidak mengulang baris yang sama terus
    for _, d in ipairs(routeDropTargets()) do
        if routeDropPlatformRow(d) == rowY then
            RouteDrop.Skip[d.uid or d] = os.clock() + (ok and 8 or 15)
        end
    end
    if not ok then
        routeDropLog("Sweep baris y=" .. rowY .. " gagal/terputus; baris dilewati sementara.", true)
    end
end


task.spawn(function()
    local lastBlockedLog = 0
    while alive() do
        if RouteDrop.Running then
            if AutoDrop.Busy or Pabrik.Traveling then
                if os.clock() - lastBlockedLog > 5 then
                    lastBlockedLog = os.clock()
                    routeDropLog("MENUNGGU: fitur lain sedang memakai gerakan (AutoDrop.Busy=" .. tostring(AutoDrop.Busy) .. ", Pabrik.Traveling=" .. tostring(Pabrik.Traveling) .. ")", true)
                end
            else
                local ok, err = pcall(routeDropStep)
                if not ok then
                    RouteDrop.Status = "Error: " .. tostring(err)
                    routeDropLog("EXCEPTION routeDropStep: " .. tostring(err), true)
                    warn("[n4th] Auto Route Drop: " .. tostring(err))
                    task.wait(1)
                end
            end
        end
        task.wait(0.2)
    end
end)

-- Titik drop sudah diatur? (posisi, WORLD:ID, atau world lain)
function Pabrik.pointSet()
    if Pabrik.DropX >= 0 then return true end
    local name, door = parseDropTarget()
    if door then return true end
    return name ~= "" and name ~= Guard.worldName()
end

local function pabrikDrop(seed, n, live)
    local items = { { id = seed, n = n } }
    local ok, why = dropTrip(items, live, function(t) Pabrik.Status = t end)
    Pabrik.Dropped += items[1].got or 0
    if why == "home" then
        if Pabrik.stop then Pabrik.stop("Gagal pulang ke world pabrik " .. tostring(Pabrik.Home)) end
    elseif not ok then
        Pabrik.DropOffUntil = os.clock() + ((why == "nopoint") and 60 or 120)
    end
end

-- Auto Farm: seed hasil break sudah banyak -> jeda, drop seed ke titik drop,
-- balik ke posisi farm, lalu lanjut lagi (dicek tiap 2 detik)
task.spawn(function()
    while alive() do
        task.wait(2)
        local seed = State.SelectedId and seedOfBlock(State.SelectedId)
        if State.Running and not State.Override and Pabrik.pointSet() and not State.DropPause and seed
            and not AutoDrop.Busy and not (AutoDrop.On and AutoDrop.owns and AutoDrop.owns(seed))
            and os.clock() >= (State.DropOffUntil or 0) then
            local n = invCount(seed)
            local s = playerState()
            if s and n >= State.SeedDropAt and n > State.SeedKeep then
                local hx, hy = startNode(s)
                local runId = State.RunId
                local function live() return State.Running and alive() and State.RunId == runId end
                State.DropPause = true
                task.wait(0.8) -- tunggu pukulan terakhir selesai
                local items = { { id = seed, n = n - State.SeedKeep } }
                local ok, why = dropTrip(items, live, function(t) State.LastAction = t end)
                State.Dropped += items[1].got or 0
                if not ok then State.DropOffUntil = os.clock() + ((why == "nopoint") and 60 or 120) end
                if why == "home" then
                    stopFarm("Gagal pulang ke world farm")
                elseif live() then
                    State.LastAction = ("Jalan balik ke posisi farm (%d,%d)"):format(hx, hy)
                    if not walkTo(hx, hy, 60) then
                        stopFarm("Gagal balik ke posisi farm, Auto Farm dihentikan")
                    else
                        State.LastAction = "Lanjut Auto Farm"
                    end
                end
                State.DropPause = false
            end
        end
    end
end)

local PHASE_NAME = { panen = "PANEN", tanam = "TANAM", ["break"] = "BREAK", tunggu = "TUNGGU" }

local function breakReady()
    return Pabrik.BreakX >= 0 and next(Pabrik.Tiles) ~= nil and os.clock() >= (Pabrik.BreakFailUntil or 0)
end

-- 1 langkah pabrik. o = { seed, block, drop, breakMode, whole, exclude, live, phase }
-- Hasil: "drop" | "work" | "move" | "wait" | "break" | "next" | "idle" (+ detik ke pohon siap)
local function pabrikStep(o)
    local seeds, blocks = invCount(o.seed), invCount(o.block)
    o.phase = o.phase or "panen"
    Pabrik.Phase = PHASE_NAME[o.phase]
    -- drop seed lebihan (kapan saja)
    if o.drop and Pabrik.Drop and seeds >= Pabrik.DropAt and seeds > Pabrik.Keep
        and os.clock() >= (Pabrik.DropOffUntil or 0) then
        pabrikDrop(o.seed, seeds - Pabrik.Keep, o.live)
        return "drop"
    end

    if o.phase == "panen" then
        -- 1x panen bisa kena beberapa pohon, jadi sisakan ruang ~20 item
        if blocks >= CAP - 20 or seeds >= CAP - 20 then
            o.phase = "tanam"
            return "next"
        end
        FC = pabrikCfg(o, true, false)
        local r = fieldStep()
        if r == "idle" then
            o.idleAt = os.clock()
            o.phase = "tanam"
            return "next"
        end
        return r
    end

    if o.phase == "tanam" then
        if seeds > 0 then
            FC = pabrikCfg(o, false, true)
            local r = fieldStep()
            if r ~= "idle" then return r end
        end
        o.phase = "break"
        return "next"
    end

    if o.phase == "break" then
        local want
        if o.breakMode == "always" then
            want = blocks > 0
        else -- mode produksi: break hanya untuk dapat seed awal
            local _, nxt = readyTreeCount(o.whole)
            want = blocks > 0 and seeds < BOOT_SEEDS and nxt == nil
        end
        if want and breakReady() and pabrikBreak(o) then
            -- block masih ada: lanjut break (habiskan dulu), block habis: tanam
            o.phase = (o.breakMode == "always" and invCount(o.block) > 0) and "break" or "tanam"
            return "break"
        end
        o.phase = "tunggu"
        return "next"
    end

    -- tunggu
    local n, nxt = readyTreeCount(o.whole)
    if n > 0 and os.clock() - (o.idleAt or 0) > 5 then
        o.phase = "panen"
        return "next"
    end
    if o.breakMode == "always" and blocks > 0 and breakReady() then
        o.phase = "break"
        return "next"
    end
    if seeds > 0 and os.clock() - (o.plantAt or 0) > 10 then
        o.plantAt = os.clock() -- sesekali cek tile kosong (misal pohon dipanen orang lain)
        o.phase = "tanam"
        return "next"
    end
    return "idle", nxt, n
end

local function waitText(sec)
    sec = math.max(0, math.ceil(sec or 0))
    if sec >= 60 then return ("%dm %dd"):format(sec // 60, sec % 60) end
    return sec .. " dtk"
end

local function pabrikLoop(runId)
    local function live() return Pabrik.Running and alive() and Pabrik.RunId == runId end
    local o = { seed = Pabrik.SeedId, block = Pabrik.BlockId, drop = true, breakMode = "always", live = live }
    while live() do
        task.wait()
        o.whole = Pabrik.WholeWorld
        local here = Guard.worldName()
        if not Pabrik.Traveling and Pabrik.Home ~= "" and here ~= Pabrik.Home then
            Pabrik.Status = "Bukan di world pabrik (" .. Pabrik.Home .. "), menunggu..."
            task.wait(2)
            continue
        end
        local r, nextReady, nReady = pabrikStep(o)
        if r ~= "idle" then o.stuckAt = nil end
        if r == "idle" then
            local seeds, blocks = invCount(o.seed), invCount(o.block)
            if not nextReady and (nReady or 0) == 0 and seeds <= 0 and blocks <= 0 then
                if Pabrik.stop then Pabrik.stop("Seed & block habis, tidak ada pohon tumbuh") end
                break
            end
            if (nReady or 0) > 0 then
                -- ada pohon siap tapi tidak terjangkau: lama-lama reset daftar lewati & jalur
                o.stuckAt = o.stuckAt or os.clock()
                if os.clock() - o.stuckAt > 30 then
                    o.stuckAt = nil
                    table.clear(Pabrik.Skip)
                    table.clear(BadEdge)
                    Reach = nil
                end
            end
            if seeds >= CAP - 20 and not (Pabrik.Drop and Pabrik.pointSet()) then
                Pabrik.Status = ("Seed hampir penuh (%d): atur titik drop & nyalakan Auto drop seed"):format(seeds)
            elseif (nReady or 0) > 0 then
                Pabrik.Status = nReady .. " pohon siap belum terjangkau, dicoba lagi"
            elseif nextReady then
                Pabrik.Status = "Menunggu pohon siap ±" .. waitText(nextReady)
            elseif blocks > 0 and (Pabrik.BreakX < 0 or next(Pabrik.Tiles) == nil) then
                Pabrik.Status = "Ada block tapi posisi / tile break belum diatur"
            elseif seeds > 0 then
                Pabrik.Status = "Lahan penuh, menunggu"
            else
                Pabrik.Status = "Menunggu..."
            end
            if not waitAuto(1000) then break end
        end
    end
    releaseInput()
end

function Pabrik.stop(reason)
    Pabrik.Running = false
    Pabrik.Traveling = false
    if State.Override then State.Running = false end
    autoEnd()
    releaseInput()
    Pabrik.Status = reason or "Dihentikan"
    if UI.PabrikToggle then pcall(function() UI.PabrikToggle:Set(false) end) end
    if reason then
        notify("Pabrik", reason, 5)
        if not string.find(reason, "^Dihentikan") then Hook.send("pabrik", "Pabrik berhenti: " .. reason) end
    end
end

function Pabrik.start()
    if Pabrik.Running then return end
    if AutoDrop.Busy then notify("Auto Drop", "Tunggu perjalanan drop selesai", 3) return end
    local err
    local block = blockOfSeed(Pabrik.SeedId)
    if not Refs.World then
        err = "Data world belum ketemu. Tekan 'Hubungkan ke game'"
    elseif not OrigIsDown then
        err = "Kontrol gerak game (WorldMenu.isDown) tidak ketemu"
    elseif not playerState() then
        err = "Kamu belum masuk world"
    elseif not Pabrik.SeedId then
        err = "Pilih seed pabrik dulu"
    elseif not block then
        err = "Block dari seed ini tidak ketemu"
    elseif not Pabrik.WholeWorld and #landRows() == 0 then
        err = "Atur lahan dulu (tab Lahan)"
    end
    if err then
        notify("Pabrik", err, 4)
        if UI.PabrikToggle then pcall(function() UI.PabrikToggle:Set(false) end) end
        return
    end
    if State.Running and not State.Override then stopFarm("Dihentikan karena Pabrik dimulai") end
    if Clear.Running then stopClear("Dihentikan karena Pabrik dimulai") end
    if Farmer.Running then stopFarmer("Dihentikan karena Pabrik dimulai") end
    if not Refs.Trees then findTreeRefs() end
    Pabrik.BlockId = block
    Pabrik.Home = Guard.worldName()
    table.clear(Pabrik.Skip)
    table.clear(Pabrik.Row)
    table.clear(BadEdge)
    Pabrik.DropOffUntil, Pabrik.BreakFailUntil = 0, 0
    Pabrik.Running = true
    Pabrik.RunId = (Pabrik.RunId or 0) + 1
    Pabrik.Status = "Mulai..."
    autoBegin()
    if UI.PabrikToggle then pcall(function() UI.PabrikToggle:Set(true) end) end
    local id = Pabrik.RunId
    task.spawn(function()
        local ok, e = pcall(pabrikLoop, id)
        if not ok then
            warn("[n4th] Pabrik error: " .. tostring(e))
            if Pabrik.Running then Pabrik.stop("Error: " .. tostring(e)) end
        end
    end)
end

---------------------------------------------------------------------
---------------------------------------------------------------------
-- BANGUN LAHAN
---------------------------------------------------------------------
-- Cara kerja (sama seperti bikin farm manual di world baru yang penuh tanah):
--   1. GALI    : dari permukaan sampai bawah (tepat di atas bedrock), seperti ular.
--                Celah 1 tile di atas tiap baris digali (tempat pohon & jalan), ujung kiri
--                & kanan dibuka bergantian jadi tangga, background tanah ikut dipecah.
--                Tanah di baris lahan dibiarkan = sudah jadi lahan.
--   2. PASANG  : baris yang masih kosong (di atas permukaan) dipasang dari BAWAH ke atas.
--                Block pertama dipasang dari ujung tangga, lalu baris itu jadi jembatan:
--                berdiri di ujungnya, pasang block ke depan satu-satu, maju, sampai ujung.
--   3. PRODUKSI: block habis -> ambil dulu drop block sisa galian di lahan, lalu tanam 1 baris,
--                pasang-pecah block di KANAN karakter untuk dapat seed (seperti Pabrik),
--                collect, panen. Sampai 190 block -> lanjut pasang, sisakan 10 block.
--   4. BERSIH  : semua drop yang tertinggal di lahan dicari (scan) lalu didatangi pakai A*.
local BuildFail = {}

local function overlapsPlayer(x, y, s)
    return x + 1 > s.x - 0.3 and x < s.x + 0.3 and y + 1 > s.y - 0.95 and y < s.y
end

local function placeBuild(t, s)
    local id = Build.BlockId
    if invCount(id) <= (Build.Reserve or 0) or overlapsPlayer(t.x, t.y, s) then return false end
    if not placeOk(t.x, t.y) then
        skipTile(Build.Skip, t.idx, 120)
        return false
    end
    sendSetTile("fg", t.x, t.y, id)
    pcall(function() Refs.Inv:remove(id, 1) end)
    Build.Placed += 1
    Build.Status = ("Pasang %s (%d,%d)"):format(itemName(id), t.x, t.y)
    return true
end

-- Rencana lahan: baris, kolom block & lubang tangga tiap baris
function Build.plan()
    local w = Refs.World
    if not w then return nil end
    local rows = landRows()
    if #rows == 0 then return nil end
    local W = w.w
    local P = {
        rows = rows, K = #rows, W = W,
        x0 = math.clamp(math.floor(math.min(Land.X0, Land.X1)), 0, W - 1),
        x1 = math.clamp(math.floor(math.max(Land.X0, Land.X1)), 0, W - 1),
        cols = {}, isLand = {}, holes = {},
    }
    for k = 1, #rows do
        local cols = landCols(k - 1)
        local set = {}
        for _, x in ipairs(cols) do set[x] = true end
        local holes = {}
        for x = P.x0, P.x1 do
            if not set[x] then holes[#holes + 1] = x end
        end
        P.cols[k], P.isLand[k], P.holes[k] = cols, set, holes
    end
    return P
end

-- Permukaan tanah asli: baris pertama yang dia & baris bawahnya sebagian besar padat
function Build.findSurface(P)
    local w = Refs.World
    local span = P.x1 - P.x0 + 1
    local function full(y)
        local n = 0
        for x = P.x0, P.x1 do
            local it = ItemDB[fgIdAt(x, y)]
            if it and it.solid and it.kind ~= "seed" then n += 1 end
        end
        return n * 2 > span
    end
    for y = math.max(0, P.rows[1] - 1), w.h - 2 do
        if full(y) and full(y + 1) then return y end
    end
    return math.huge
end

-- Yang masih harus digali di tile ini: "fg" (tanah / batu / lava), "bg" (background tanah), nil = beres.
-- Pohon & benda tidak padat dibiarkan.
function Build.carveLayer(x, y, W)
    local fg = fgIdAt(x, y)
    if fg ~= 0 then
        local it = ItemDB[fg]
        if it and it.kind ~= "seed" and (it.solid or it.deadly or it.hurts) and canBreak(fg) then return "fg" end
        return nil
    end
    if y >= (Build.Surface or math.huge) or Build.Carved[y * W + x] then
        local bg = tileAt("bg", x, y)
        if bg and bg ~= 0 and canBreak(bg) then return "bg" end
    end
    return nil
end

-- Urutan gali seperti ular, dari atas ke bawah (hanya tile yang masih perlu digali):
--   celah baris ke-1 kiri -> kanan, turun lewat lubang ujung kanan,
--   celah baris ke-2 kanan -> kiri, turun lewat lubang ujung kiri, dst.
--   Lubang di ujung awal dibuka dari celah di bawahnya (supaya tidak terperosok).
--   Lantai lahan di dalam tanah yang bolong (gua) / lava ditambal block sambil lewat.
function Build.carveList(P)
    local W, list = P.W, {}
    local function add(x, y, kind)
        if y >= 0 and Build.carveLayer(x, y, W) then
            list[#list + 1] = { x = x, y = y, idx = y * W + x, kind = kind }
        end
    end
    local surf = Build.Surface or math.huge
    local canFill = Build.BlockId ~= nil and invCount(Build.BlockId) > 0
    local function fill(x, y)
        if y < surf then return end
        local id = fgIdAt(x, y)
        local need = false
        if id == 0 then
            need = canFill
        elseif not Build.done(x, y) then
            local it = ItemDB[id]
            need = it ~= nil and it.kind ~= "seed" and (it.deadly or it.hurts) and canBreak(id) and true or false
        end
        if need then list[#list + 1] = { x = x, y = y, idx = y * W + x, kind = "fill" } end
    end
    for k = 1, P.K do
        local y = P.rows[k]
        local d = ((k - 1) % 2 == 0) and 1 or -1
        local up = nil -- lubang ujung awal baris di atasnya, dibuka dari celah ini
        if k > 1 and #P.holes[k - 1] > 0 then
            local ph = P.holes[k - 1]
            up = (d == -1) and ph[1] or ph[#ph]
        end
        local a, b = P.x0, P.x1
        if d == -1 then a, b = P.x1, P.x0 end
        local L = P.isLand[k]
        for x = a, b, d do
            if L[x] then fill(x, y) end -- lantai dulu, baru celah di atasnya
            add(x, y - 1, "gap")
            if x == up then add(x, P.rows[k - 1], "hole") end
        end
        -- lubang ujung akhir baris ini = jalan turun ke celah baris bawahnya
        if k < P.K and #P.holes[k] > 0 then
            local h = P.holes[k]
            add((d == 1) and h[#h] or h[1], y, "hole")
        end
    end
    return list
end

-- Jalan (A*) ke tempat yang menjangkau salah satu target.
-- maxY = tempat berdiri tidak boleh lebih bawah dari ini, noSelf = jangan berdiri di tile target.
-- Hasil: "move" | "nopath" | "wait"
function Build.goNear(targets, R, maxY, noSelf)
    local w = Refs.World
    local s = playerState()
    if not w or not s then return "wait" end
    local sx, sy = startNode(s)
    local goals = { maxY = maxY, noSelf = noSelf }
    for _, t in ipairs(targets) do goals[t.idx] = true end
    local f = targets[1]
    setMoveStatus(("Cari jalan A* ke (%d,%d)"):format(f.x, f.y))
    local path = astar(sx, sy, goals, f.x, f.y, R, false)
    if not path then
        releaseInput()
        return "nopath"
    end
    local fails = BuildFail[f.idx] or 0
    if #path == 0 then
        execWalk(sx, sy) -- sudah di tempat tapi belum terjangkau: rapikan ke tengah tile
        fails += 1
    elseif not followPath(path) then
        fails += 1
    else
        fails = 0
    end
    releaseInput()
    if fails >= 4 then
        fails = 0
        for _, t in ipairs(targets) do skipTile(Build.Skip, t.idx, 30) end
    end
    BuildFail[f.idx] = (fails > 0) and fails or nil
    return "move"
end

-- Pukul 1 tile sampai bersih (block dulu, lalu background).
-- Hasil: "done" | "fall" (karakter jatuh) | "skip" | "stop"
function Build.carveTile(t, live)
    local hits, maxHits = 0, nil
    while live() and alive() do
        local layer = Build.carveLayer(t.x, t.y, Refs.World.w)
        if not layer then return "done" end
        local id = (layer == "fg") and fgIdAt(t.x, t.y) or (tileAt("bg", t.x, t.y) or 0)
        maxHits = maxHits or (hitsNeeded(id) * 3 + 6)
        local r = tryBreak(t.x, t.y, layer == "bg")
        if r == nil then
            skipTile(Build.Skip, t.idx, 60)
            return "skip"
        end
        if r == "broke" then
            if layer == "fg" then Build.Carved[t.idx] = true end
            Build.Dug += 1
            Build.Status = ("Gali %s (%d,%d)"):format(itemName(id), t.x, t.y)
            local bt = (Build.BreakTimes[t.idx] or 0) + 1
            Build.BreakTimes[t.idx] = bt
            if bt > 8 then -- server terus mengembalikan tile ini
                skipTile(Build.Skip, t.idx, 120)
                return "skip"
            end
            hits, maxHits = 0, nil
            local s = playerState()
            if not s or not s.grounded then
                waitAuto(State.BreakMs)
                return "fall"
            end
        else
            hits += 1
            Build.Status = ("Pukul %s (%d,%d)"):format(itemName(id), t.x, t.y)
            if hits > maxHits then
                skipTile(Build.Skip, t.idx, 45)
                return "skip"
            end
        end
        if not waitAuto(State.BreakMs) then return "stop" end
    end
    return "stop"
end

-- Lantai lahan bolong / lava: pecah dulu kalau perlu, lalu pasang block.
-- Hasil: "done" | "fall" | "skip" | "stop"
function Build.fillTile(t)
    local id = fgIdAt(t.x, t.y)
    if id ~= 0 and not Build.done(t.x, t.y) then
        Build.Status = ("Pecah %s di lantai (%d,%d)"):format(itemName(id), t.x, t.y)
        for _ = 1, 40 do
            local r = tryBreak(t.x, t.y, false)
            if r == nil then
                skipTile(Build.Skip, t.idx, 60)
                return "skip"
            end
            if r == "broke" then break end
            if not waitAuto(State.BreakMs) then return "stop" end
        end
        local cur = playerState()
        if not cur or not cur.grounded then return "fall" end
    end
    if fgIdAt(t.x, t.y) == 0 then
        local cur = playerState()
        if not cur or invCount(Build.BlockId) <= 0 or not placeBuild(t, cur) then
            skipTile(Build.Skip, t.idx, 30)
            return "skip"
        end
        Build.Status = ("Tambal lantai lahan (%d,%d)"):format(t.x, t.y)
        if not waitAuto(State.PlaceMs) then return "stop" end
    end
    return "done"
end

-- 1 langkah gali. Hasil: "work" | "move" | "wait" | "none"
function Build.carveStep(P, list, live)
    local w = Refs.World
    local s = playerState()
    if not w or not s or s.dead then
        releaseInput()
        task.wait(0.5)
        return "wait"
    end
    if not s.grounded then
        releaseInput()
        Move.airCheck(s)
        task.wait()
        return "wait"
    end
    Move.AirAt = nil
    releaseInput()
    local R = punchReach() - 0.08
    local now = os.clock()
    local fi = nil
    for i, t in ipairs(list) do
        if not skipped(Build.Skip, t.idx, now) then
            fi = i
            break
        end
    end
    if not fi then return "none" end
    -- pecah yang terjangkau dari sini sesuai urutan (berhenti di tile pertama yang tidak terjangkau)
    local did = 0
    for j = fi, math.min(#list, fi + 5) do
        local t = list[j]
        if not skipped(Build.Skip, t.idx, now) then
            local cur = playerState()
            if not cur or cur.dead or not cur.grounded or not stateReaches(cur, t.x, t.y, R) then break end
            if t.kind == "fill" and overlapsPlayer(t.x, t.y, cur) then break end -- berdiri di lubangnya: pindah dulu
            if not canWorkAt(t.x, t.y) then
                skipTile(Build.Skip, t.idx, 300) -- dikunci orang lain
            elseif t.kind == "fill" then
                did += 1
                if Build.fillTile(t) ~= "done" then break end
            else
                -- block pijakan sendiri: pecah hanya kalau jatuhnya pendek & aman
                local foot = floor(cur.y + 0.01)
                if t.y == foot and t.x >= floor(cur.x - 0.3) and t.x <= floor(cur.x + 0.3 - 0.0001) then
                    local d = fallAfterBreak(cur, t.x, foot)
                    if d == nil or d > 3 then
                        skipTile(Build.Skip, t.idx, 20)
                        break
                    end
                end
                did += 1
                if Build.carveTile(t, live) ~= "done" then break end
            end
        end
    end
    if did > 0 then return "work" end
    local F = list[fi]
    local r = Build.goNear({ F }, math.min(punchReach(), buildReach()) - 0.35, nil, F.kind == "fill")
    if r == "nopath" then
        -- belum ada jalan ke sini: lewati sebaris dulu (tidak cari jalan berulang per tile)
        for _, t in ipairs(list) do
            if t.y == F.y then skipTile(Build.Skip, t.idx, 30) end
        end
        return "move"
    end
    return r
end

-- Tile masuk baris: block di samping lubang tangga (block pertama baris dipasang dari sini)
function Build.entries(P, k)
    local e = {}
    local holes, L = P.holes[k], P.isLand[k]
    if #holes == 0 then
        e[P.x0], e[P.x1] = true, true
    else
        for _, h in ipairs(holes) do
            if L[h - 1] and L[h - 2] then e[h - 1] = true end
            if L[h + 1] and L[h + 2] then e[h + 1] = true end
        end
    end
    return e
end

-- 1 langkah pasang: baris paling BAWAH yang belum lengkap dulu, naik ke atas.
-- Baris yang sedang dipasang jadi jembatan: berdiri di atasnya lalu pasang ke depan.
-- Hasil: "work" | "move" | "wait" | "none"
function Build.placeStep(P)
    local w = Refs.World
    local s = playerState()
    if not w or not s or s.dead then
        releaseInput()
        task.wait(0.5)
        return "wait"
    end
    if not s.grounded then
        releaseInput()
        Move.airCheck(s)
        task.wait()
        return "wait"
    end
    Move.AirAt = nil
    releaseInput()
    local W = P.W
    local R = buildReach() - 0.08
    local now = os.clock()
    local k, T = nil, nil
    for kk = P.K, 1, -1 do
        local y = P.rows[kk]
        local list = {}
        for _, x in ipairs(P.cols[kk]) do
            local idx = y * W + x
            if not Build.done(x, y) and not skipped(Build.Skip, idx, now) then
                list[#list + 1] = { x = x, y = y, idx = idx }
            end
        end
        if #list > 0 then
            k, T = kk, list
            break
        end
    end
    if not k then return "none" end
    local y = P.rows[k]
    local px = s.x
    table.sort(T, function(a, b) return abs(a.x + 0.5 - px) < abs(b.x + 0.5 - px) end)
    local _, sy = startNode(s)
    local onRow = sy <= y - 1 -- berdiri di atas baris ini (jembatan)
    local under = Build.Under[k] ~= nil and now < Build.Under[k]
    local entry = Build.entries(P, k)
    local hasAny = false
    for _, x in ipairs(P.cols[k]) do
        if Build.done(x, y) then
            hasAny = true
            break
        end
    end

    -- pasang yang terjangkau, yang paling dekat dulu (maks 2 per langkah)
    local done = 0
    for _, t in ipairs(T) do
        if done >= 2 then break end
        local cur = playerState()
        if not cur or not cur.grounded then break end
        if stateReaches(cur, t.x, t.y, R) and (onRow or under or entry[t.x]) then
            if fgIdAt(t.x, t.y) ~= 0 then
                -- tile lahan berisi pohon / lava / hiasan: pecah dulu
                if not canWorkAt(t.x, t.y) then
                    skipTile(Build.Skip, t.idx, 300)
                else
                    Build.Status = ("Bersihkan tile lahan (%d,%d)"):format(t.x, t.y)
                    local broke = false
                    for _ = 1, 40 do
                        local r = tryBreak(t.x, t.y, false)
                        if r == nil then break end -- tidak bisa dipecah (lock, pintu, dll)
                        if r == "broke" then
                            broke = true
                            break
                        end
                        if not waitAuto(State.BreakMs) then return "wait" end
                    end
                    -- tidak bisa dibersihkan: jangan didatangi ulang terus (bikin bolak-balik jauh)
                    if not broke then skipTile(Build.Skip, t.idx, 1800) end
                    waitNearDrops(0.5)
                end
                return "work"
            end
            if placeBuild(t, cur) then
                done += 1
                if entry[t.x] then Build.Under[k] = nil end
                if not waitAuto(State.PlaceMs) then return "wait" end
            elseif invCount(Build.BlockId) <= (Build.Reserve or 0) then
                break
            end
        end
    end
    if done > 0 then return "work" end
    if invCount(Build.BlockId) <= (Build.Reserve or 0) then return "none" end

    local RR = buildReach() - 0.35
    -- naik ke baris ini lalu pasang ke depan (baris jadi jembatan)
    if hasAny and not under then
        local r = Build.goNear(T, RR, y - 1, true)
        if r ~= "nopath" then return r end
        Build.Under[k] = now + 60 -- tidak bisa naik ke baris ini: sementara pasang dari bawah
        under = true
    end
    -- belum ada pijakan: ke ujung tangga, pasang block pertama baris dari sana
    if not under then
        local E = {}
        for _, t in ipairs(T) do
            if entry[t.x] then E[#E + 1] = t end
        end
        if #E > 0 then
            local r = Build.goNear(E, RR, nil, true)
            if r ~= "nopath" then return r end
        end
        Build.Under[k] = now + 60
    end
    local r = Build.goNear(T, RR, nil, true)
    if r == "nopath" then
        for _, t in ipairs(T) do skipTile(Build.Skip, t.idx, 30) end
        Build.Status = ("Baris y %d belum terjangkau, dilewati sebentar"):format(y)
        return "none"
    end
    return r
end

-- ---------- Produksi block (1 baris, seperti Pabrik) ----------
function Build.cfg(o, harvest, plant)
    return {
        run = o.live,
        harvest = harvest,
        plant = plant and invCount(o.seed) > 0,
        seed = o.seed,
        only = o.seed,           -- hanya panen pohon seed block ini
        skip = Build.FieldSkip,
        hms = Farmer.HarvestMs,
        pms = Farmer.PlantMs,
        area = inLandRect,       -- hanya pohon di lahan (baris per baris)
        plantSet = o.plantSet,   -- tanam hanya di baris produksi
        exclude = o.exclude,
        row = Build.Row,
        collect = true,
        status = function(t) Build.Status = t end,
        onHarvest = function() Build.Harvested += 1 end,
        onPlant = function() Build.Planted += 1 end,
    }
end

-- Baris produksi: baris lengkap tepat di bawah baris yang sedang dipasang
-- (kalau tidak ada: baris lengkap terdekat dengan karakter)
function Build.prodRow(P)
    local function complete(k)
        local y = P.rows[k]
        for _, x in ipairs(P.cols[k]) do
            if not Build.done(x, y) then return false end
        end
        return true
    end
    for k = P.K, 1, -1 do
        if not complete(k) then
            if k < P.K then return k + 1 end
            break
        end
    end
    local s = playerState()
    local best, bd = nil, nil
    for k = 1, P.K do
        if complete(k) then
            local d = s and abs(P.rows[k] - s.y) or k
            if not bd or d < bd then best, bd = k, d end
        end
    end
    return best
end

-- Tempat tanam baris produksi + posisi pasang-pecah.
-- Posisi break & grid lahan diatur (tab Lahan / Grid mode Lahan): pakai itu.
-- Belum diatur: otomatis berdiri dekat ujung kanan baris, block di KANAN karakter.
function Build.prodSpots(P, k)
    local W, y = P.W, P.rows[k]
    local gy = y - 1
    local o = { set = {} }
    local L = P.isLand[k]
    local skip = {}
    if Build.BreakX >= 0 and next(Build.Tiles) ~= nil then
        skip[Build.BreakY * W + Build.BreakX] = true -- jangan tanam di tempat berdiri & tile break
        for key in pairs(Build.Tiles) do
            local dx, dy = string.match(key, "^(-?%d+),(-?%d+)$")
            if dx then skip[(Build.BreakY + tonumber(dy)) * W + Build.BreakX + tonumber(dx)] = true end
        end
    else
        local bx = P.x1 - 3
        if gy >= 0 and bx > P.x0 and L[bx] and L[bx + 1] and Build.done(bx, y) and Build.done(bx + 1, y) then
            o.stand = { x = bx, y = gy }
            o.tile = { x = bx + 1, y = gy }
            skip[gy * W + bx], skip[gy * W + bx + 1] = true, true
        end
    end
    if gy >= 0 then
        for _, x in ipairs(P.cols[k]) do
            local idx = gy * W + x
            if not skip[idx] then o.set[idx] = true end
        end
    end
    return o
end

-- Sesi break produksi di posisi & grid lahan (mesin Auto Farm: multi tile, sentuh drop tiap putaran).
-- Berhenti kalau seed sudah cukup untuk mengisi baris, block habis, atau 8 dtk tidak ada aksi.
function Build.breakSession(o)
    local s = playerState()
    if not s then return false end
    local hx, hy = startNode(s)
    if hx ~= Build.BreakX or hy ~= Build.BreakY then
        Build.Status = ("Jalan ke posisi break lahan (%d,%d)"):format(Build.BreakX, Build.BreakY)
        if not walkTo(Build.BreakX, Build.BreakY, 45) then
            Build.Status = "Gagal jalan ke posisi break lahan, pakai posisi otomatis"
            return nil
        end
    end
    if not o.live() then return false end
    local before = invCount(o.seed)
    local want = math.max(1, Build.freeSpots(o))
    State.Override = { offsets = Build.Tiles, block = o.block, mode = "Place + Break" }
    State.Quiet = true
    table.clear(HitCount)
    table.clear(PlacedAt)
    State.Running = true
    State.RunId = (State.RunId or 0) + 1
    local id = State.RunId
    local lastActs, lastActAt = State.Placed + State.Broken, os.clock()
    task.spawn(function() -- pengawas sesi break
        while State.Running and State.RunId == id do
            task.wait(0.5)
            local acts = State.Placed + State.Broken
            if acts ~= lastActs then lastActs, lastActAt = acts, os.clock() end
            if not o.live() or invCount(o.seed) >= before + want or invCount(o.block) <= 0
                or os.clock() - lastActAt > 8 then
                State.Running = false
            end
        end
    end)
    Build.Status = ("Break %s di posisi break lahan (%d,%d)"):format(itemName(o.block), Build.BreakX, Build.BreakY)
    local ok, e = pcall(farmLoop, id)
    if not ok then warn("[n4th] Break lahan error: " .. tostring(e)) end
    State.Running = false
    State.Override = nil
    State.Quiet = false
    return invCount(o.seed) > before
end

-- Tempat tanam yang masih kosong di baris produksi
function Build.freeSpots(o)
    local w = Refs.World
    if not w then return 0 end
    if not o.plantSet then
        local n, nxt = readyTreeCount(true, o.seed)
        return (n == 0 and nxt == nil) and 1 or 0
    end
    local n = 0
    for idx in pairs(o.plantSet) do
        local x, y = idx % w.w, idx // w.w
        if fgIdAt(x, y) == 0 and plantSpotOk(x, y, o.seed) then n += 1 end
    end
    return n
end

-- Pasang lalu pecah block di KANAN karakter untuk dapat seed (seperti Pabrik)
function Build.bootstrap(o)
    local w = Refs.World
    if not w or invCount(o.block) <= 0 then return false end
    if Build.BreakX >= 0 and next(Build.Tiles) ~= nil then
        local r = Build.breakSession(o)
        if r ~= nil then return r end -- nil = tidak bisa ke posisi break: pakai cara otomatis
    end
    local spot = nil
    if o.stand then
        local s0 = playerState()
        local hx, hy = nil, nil
        if s0 then hx, hy = startNode(s0) end
        if hx ~= o.stand.x or hy ~= o.stand.y then
            Build.Status = ("Jalan ke posisi pasang-pecah (%d,%d)"):format(o.stand.x, o.stand.y)
            if not walkTo(o.stand.x, o.stand.y, 45) then o.stand = nil end
        end
        if o.stand and o.tile then
            local id = fgIdAt(o.tile.x, o.tile.y)
            if id == o.block or (id == 0 and placeOk(o.tile.x, o.tile.y)) then spot = o.tile end
        end
    end
    local s = playerState()
    if not s or not s.grounded then return false end
    if not spot then
        local R = farmReach() - 0.08
        local ty = floor(s.y - 0.475)
        for _, dx in ipairs({ 1, 2, -1, -2 }) do -- kanan dulu
            local tx = floor(s.x) + dx
            local idx = ty * w.w + tx
            if tx >= 0 and tx < w.w and ty >= 0 and fgIdAt(tx, ty) == 0
                and not (o.plantSet and o.plantSet[idx]) and not (o.exclude and o.exclude[idx])
                and stateReaches(s, tx, ty, R) and not overlapsPlayer(tx, ty, s) and placeOk(tx, ty) then
                spot = { x = tx, y = ty }
                break
            end
        end
    end
    if not spot then return false end
    -- 1 sesi panjang (seperti Pabrik): pasang-pecah terus sampai seed cukup untuk mengisi
    -- semua tempat kosong di baris produksi, atau block habis. Tidak diselingi panen / tanam.
    local before = invCount(o.seed)
    local want = math.max(1, Build.freeSpots(o))
    for _ = 1, 300 do
        if not o.live() or (invCount(o.block) <= 0 and fgIdAt(spot.x, spot.y) == 0) then break end
        if invCount(o.seed) >= before + want then break end
        if fgIdAt(spot.x, spot.y) == 0 then
            sendSetTile("fg", spot.x, spot.y, o.block)
            pcall(function() Refs.Inv:remove(o.block, 1) end)
            PlacedAt[spot.x .. "," .. spot.y] = os.clock()
            Build.Status = ("Pasang & pecah %s untuk dapat seed (%d,%d)"):format(itemName(o.block), spot.x, spot.y)
            if not waitAuto(State.PlaceMs) then break end
        end
        for _ = 1, 40 do
            if not o.live() then break end
            local r = tryBreak(spot.x, spot.y, false)
            if r == nil or r == "broke" then break end
            if not waitAuto(State.BreakMs) then break end
        end
        -- tunggu drop muncul (datang dari server), lalu ambil dengan sentuhan: melangkah masuk lalu balik
        Drops.waitSpawn({ spot })
        local s2 = playerState()
        if s2 and s2.grounded then
            local hx, hy = startNode(s2)
            if not Drops.touch(spot, hx, hy) then waitNearDrops(0.3) end
        end
    end
    return invCount(o.seed) > before
end

-- 1 langkah produksi. Hasil: "work" | "move" | "wait" | "next" | "idle" (+ detik pohon siap, jumlah pohon siap)
-- Siklus berurutan (seperti Pabrik), tiap fase diselesaikan dulu, tidak saling potong:
--   PANEN : panen SEMUA pohon siap di lahan (baris per baris), hasilnya diambil   -> TANAM
--   TANAM : isi semua tempat kosong di baris produksi                              -> BREAK / TUNGGU
--   BREAK : seed habis & baris belum penuh: pasang-pecah di kanan karakter sampai
--           seed cukup untuk mengisi baris (atau block habis)                      -> TANAM
--   TUNGGU: tunggu pohon siap SEKALIGUS (tidak ada lagi yang siap dalam 20 dtk)   -> PANEN
function Build.produceStep(o)
    o.phase = o.phase or "panen"
    if o.phase == "panen" then
        FC = Build.cfg(o, true, false)
        local r = fieldStep()
        if r == "idle" then
            o.phase = "tanam"
            return "next"
        end
        return r
    end
    if o.phase == "tanam" then
        if invCount(o.seed) > 0 and Build.freeSpots(o) > 0 then
            FC = Build.cfg(o, false, true)
            local r = fieldStep()
            if r ~= "idle" then return r end
        end
        if not o.broke and Build.freeSpots(o) > 0 and invCount(o.seed) <= 0 and invCount(o.block) > 0 then
            o.phase = "break"
        else
            o.phase, o.broke = "tunggu", nil
        end
        return "next"
    end
    if o.phase == "break" then
        o.broke = true -- 1 sesi break tiap putaran
        o.bootAt = os.clock()
        Build.bootstrap(o)
        o.phase = "tanam"
        return "work"
    end
    -- TUNGGU
    local n, nxt = readyTreeCount(false, o.seed)
    if n > 0 and (nxt == nil or nxt > 20) then
        o.phase = "panen" -- pohon siap sekaligus
        return "next"
    end
    if n == 0 and nxt == nil and Build.freeSpots(o) > 0 and os.clock() - (o.retryAt or 0) > 10 then
        -- tidak ada pohon tumbuh sama sekali (break tadi tidak dapat seed): tanam / break lagi
        if invCount(o.seed) > 0 or (invCount(o.block) > 0 and os.clock() - (o.bootAt or 0) > 5) then
            o.retryAt = os.clock()
            o.phase = "tanam"
            return "next"
        end
    end
    return "idle", nxt, n
end

-- Bersihkan drop di dalam lahan PER BARIS (scan daftar drop game), seperti main manual:
--   baris terdekat dulu, disusuri dari ujung ke ujung tanpa berhenti (terambil sambil lewat),
--   lalu pindah ke baris sebelahnya. ids = nil (semua) atau { [id] = true }
function Build.sweep(P, live, ids, maxSec)
    if not Drops.list then return 0 end
    local x0, x1 = P.x0, P.x1 + 1
    local y0, y1 = math.max(0, P.rows[1] - 1), P.rows[P.K] + 1
    return Move.fetchDrops(live, 999, function(d)
        return d.x >= x0 and d.x < x1 and d.y >= y0 and d.y < y1 and (not ids or ids[d.id] == true)
    end, maxSec or 60)
end

function Build.stop(reason)
    Build.Running = false
    if Pabrik.Running == false and State.Override then State.Running = false end
    autoEnd()
    releaseInput()
    Build.Phase = reason or "Dihentikan"
    if UI.BuildToggle then pcall(function() UI.BuildToggle:Set(false) end) end
    if reason then
        notify("Bangun Lahan", reason, 5)
        if not string.find(reason, "^Dihentikan") then Hook.send("pabrik", "Bangun Lahan: " .. reason) end
    end
end

local function buildLoop(runId)
    local function live() return Build.Running and alive() and Build.RunId == runId end
    local seed = seedOfBlock(Build.BlockId)
    local o = { seed = seed, block = Build.BlockId, live = live }
    local phase = nil
    local noneAt = nil
    while live() do
        task.wait()
        local P = Build.plan()
        if not P then
            Build.stop("Tidak ada baris lahan (cek X awal / X akhir / Y baris atas)")
            break
        end
        if Build.Surface == nil then Build.Surface = Build.findSurface(P) end
        local carve = Build.carveList(P)
        local info = landInfo(Build.BlockId, P, carve)
        Build.Info = info
        Build.InfoAt = os.clock()

        -- 1) GALI dulu sampai bawah
        local r = "none"
        if #carve > 0 then
            Build.Reserve = 0
            Build.Phase = ("Gali: sisa %d tile"):format(#carve)
            r = Build.carveStep(P, carve, live)
            if r ~= "none" then noneAt = nil end
        end
        if r == "none" and #carve == 0 and not o.dugSwept then
            -- gali selesai: ambil dulu semua drop sisa galian, per baris
            o.dugSwept, o.sweptAt = true, os.clock()
            Build.Phase = "Bersihkan drop sisa galian (per baris)"
            Build.sweep(P, live, nil, 600)
            continue
        end
        if r == "none" then
            local have = invCount(Build.BlockId)
            if info.need == 0 then
                -- tinggal tile gali yang dilewati: coba lagi sebentar
                if #carve > 0 then
                    noneAt = noneAt or os.clock()
                    local waited = os.clock() - noneAt
                    if waited < 45 then
                        Build.Status = #carve .. " tile gali belum terjangkau, dicoba lagi"
                        if waited > 20 and not o.carveReset then
                            o.carveReset = true
                            table.clear(Build.Skip)
                            table.clear(BuildFail)
                            table.clear(BadEdge)
                            Reach = nil
                        end
                        if not waitAuto(1000) then break end
                        continue
                    end
                end
                -- 4) BERSIH: ambil semua drop yang tertinggal di lahan
                Build.Phase = "Bersihkan drop di lahan (per baris)"
                Build.sweep(P, live, nil, 900)
                if not live() then break end
                local note = (#carve > 0) and (", " .. #carve .. " tile gali dilewati") or ""
                Build.stop("Lahan selesai (" .. info.done .. " block" .. note .. ")")
                if Build.ThenPabrik then
                    if not Pabrik.SeedId then Pabrik.SeedId = seed end
                    Pabrik.start()
                end
                break
            end
            local reserve = (have >= info.need or not seed) and 0 or Build.RESERVE
            if phase ~= "produksi" and have > reserve then
                -- 2) PASANG (sisakan block untuk produksi kalau masih kurang)
                phase = "pasang"
                Build.Reserve = reserve
                Build.Phase = ("Pasang lahan: sisa %d tile"):format(info.need)
                    .. ((reserve > 0) and (" (sisakan " .. reserve .. " block)") or "")
                local pr = Build.placeStep(P)
                if pr == "none" and invCount(Build.BlockId) > reserve then
                    Build.Status = "Sisa tile belum terjangkau / terhalang, dicoba lagi"
                    noneAt = noneAt or os.clock()
                    if os.clock() - noneAt > 20 then -- lama tidak ada yang bisa dipasang: reset & coba lagi
                        noneAt = nil
                        table.clear(Build.Skip)
                        table.clear(BuildFail)
                        table.clear(BadEdge)
                        table.clear(Build.Under)
                        Reach = nil
                    end
                    if not waitAuto(1500) then break end
                elseif pr ~= "none" then
                    noneAt = nil
                end
            elseif not seed then
                Build.stop(("Block habis, masih kurang %d (seed-nya tidak ketemu)"):format(info.need))
                break
            else
                -- 3) PRODUKSI
                if phase ~= "produksi" then
                    if os.clock() - (o.sweptAt or -1e9) > 120 then
                        -- ambil dulu drop yang tertinggal di lahan (block, seed & lainnya), per baris
                        o.sweptAt = os.clock()
                        Build.Phase = "Ambil drop sisa di lahan (per baris)"
                        Build.sweep(P, live, nil, 300)
                        continue
                    end
                    phase = "produksi"
                    o.phase, o.rowK = nil, nil
                    notify("Bangun Lahan", "Block habis, produksi 1 baris dulu", 4)
                end
                local target = math.min(CAP, info.need + Build.RESERVE)
                if have >= target then
                    phase = "pasang"
                    notify("Bangun Lahan", "Block cukup (" .. have .. "), lanjut pasang", 4)
                else
                    if o.rowK and not P.rows[o.rowK] then o.rowK = nil end
                    if o.rowK == nil then
                        o.rowK = Build.prodRow(P) or false
                        table.clear(Build.Row)
                        if o.rowK then
                            local sp = Build.prodSpots(P, o.rowK)
                            o.plantSet, o.stand, o.tile, o.exclude = sp.set, sp.stand, sp.tile, nil
                        else -- belum ada baris lengkap: tanam di mana saja di luar tile lahan
                            o.plantSet, o.stand, o.tile, o.exclude = nil, nil, nil, landBlockSet()
                        end
                    end
                    Build.Phase = ("Produksi %s: block %d / %d"):format(PHASE_NAME[o.phase or "panen"] or "-", have, target)
                        .. (o.rowK and (" | baris y " .. P.rows[o.rowK]) or "")
                    local pr, nextReady, nReady = Build.produceStep(o)
                    if pr ~= "idle" then o.stuckAt = nil end
                    if pr == "idle" then
                        if not nextReady and (nReady or 0) == 0 and invCount(seed) <= 0 and have <= 0 then
                            Build.stop("Seed & block habis. Butuh " .. info.need .. " block")
                            break
                        end
                        if (nReady or 0) > 0 then
                            Build.Status = nReady .. " pohon siap belum terjangkau, dicoba lagi"
                            o.stuckAt = o.stuckAt or os.clock()
                            if os.clock() - o.stuckAt > 30 then -- reset daftar lewati & jalur
                                o.stuckAt = nil
                                table.clear(Build.FieldSkip)
                                table.clear(BadEdge)
                                Reach = nil
                            end
                        elseif nextReady then
                            Build.Status = "Menunggu pohon siap ±" .. waitText(nextReady)
                        elseif invCount(seed) <= 0 then
                            Build.Status = "Seed habis & tidak ada tempat pasang-pecah di samping karakter"
                        else
                            Build.Status = "Tidak ada tempat tanam, menunggu"
                        end
                        if not waitAuto(1000) then break end
                    end
                end
            end
        end
    end
    releaseInput()
end

function Build.start()
    if Build.Running then return end
    if AutoDrop.Busy then notify("Auto Drop", "Tunggu perjalanan drop selesai", 3) return end
    local err
    local it = Build.BlockId and ItemDB[Build.BlockId]
    if not Refs.World then
        err = "Data world belum ketemu. Tekan 'Hubungkan ke game'"
    elseif not OrigIsDown then
        err = "Kontrol gerak game (WorldMenu.isDown) tidak ketemu"
    elseif not playerState() then
        err = "Kamu belum masuk world"
    elseif not (it and it.solid) then
        err = "Pilih block padat untuk lahan"
    elseif #landRows() == 0 then
        err = "Tidak ada baris yang muat (Y atas terlalu bawah). Berdiri di pojok kiri-ATAS lahan lalu tekan 'Pakai posisi karakter'"
    end
    if err then
        notify("Bangun Lahan", err, 4)
        if UI.BuildToggle then pcall(function() UI.BuildToggle:Set(false) end) end
        return
    end
    if State.Running and not State.Override then stopFarm("Dihentikan karena Bangun Lahan dimulai") end
    if Clear.Running then stopClear("Dihentikan karena Bangun Lahan dimulai") end
    if Farmer.Running then stopFarmer("Dihentikan karena Bangun Lahan dimulai") end
    if Pabrik.Running then Pabrik.stop("Dihentikan karena Bangun Lahan dimulai") end
    if not Refs.Trees then findTreeRefs() end
    table.clear(Build.Skip)
    table.clear(BuildFail)
    table.clear(Build.FieldSkip)
    table.clear(Build.Row)
    table.clear(Build.Under)
    table.clear(Build.BreakTimes)
    table.clear(BadEdge)
    Build.Surface = nil -- dihitung ulang (permukaan tanah asli)
    Build.Reserve = 0
    Land.Cache = nil
    Pabrik.BreakFailUntil = 0
    Build.Running = true
    Build.RunId = (Build.RunId or 0) + 1
    Build.Phase = "Menghitung..."
    autoBegin()
    if UI.BuildToggle then pcall(function() UI.BuildToggle:Set(true) end) end
    local id = Build.RunId
    task.spawn(function()
        local ok, e = pcall(buildLoop, id)
        if not ok then
            warn("[n4th] Bangun Lahan error: " .. tostring(e))
            if Build.Running then Build.stop("Error: " .. tostring(e)) end
        end
    end)
end

Auto.landInfo = landInfo
Auto.landRows = landRows
Auto.seedOfBlock = seedOfBlock
Auto.blockOfSeed = blockOfSeed
Auto.parseDropTarget = parseDropTarget

Auto.walkTo = walkTo
Auto.treeReadyAt = treeReadyAt
Auto.plantSpotOk = plantSpotOk
Auto.stopWalk = function() Move.Homing = false end
Auto.here = function()
    local s = playerState()
    if s then return startNode(s) end
    return nil
end
Auto.startClear = startClear
Auto.startFarmer = startFarmer
Auto.updateClearStatus = updateClearStatus
Auto.updateFarmerStatus = updateFarmerStatus
Auto.findTreeRefs = findTreeRefs
Auto.releaseInput = releaseInput
Auto.BadEdge = BadEdge
Auto.ClearFail = ClearFail
Auto.resetReach = function() Reach = nil end
end)() end -- do (gerak otomatis)

---------------------------------------------------------------------
-- AUTO CHAT
---------------------------------------------------------------------
-- Pesan dikirim ke chat world, bergantian sesuai urutan
local TextChatService = game:GetService("TextChatService")

local function worldChannel()
    local folder = TextChatService:FindFirstChild("WorldChannels")
    if not folder then return nil end
    local name = Refs.World and Refs.World.name
    if type(name) == "string" and name ~= "" then
        local ch = folder:FindFirstChild(name)
        if ch then return ch end
    end
    -- cadangan: cari channel yang ada kita
    for _, ch in ipairs(folder:GetChildren()) do
        if ch:IsA("TextChannel") then
            for _, src in ipairs(ch:GetChildren()) do
                if src:IsA("TextSource") and src.UserId == LocalPlayer.UserId then return ch end
            end
        end
    end
    return nil
end

---------------------------------------------------------------------
-- WATERMARK NAMA n4th (hanya di layar sendiri)
---------------------------------------------------------------------
-- Nama asli (huruf gambar "BitmapText") disembunyikan, diganti teks beranimasi:
-- warna gradient mengalir + denyut halus. Pemain lain tetap melihat nama asli.
-- Selalu aktif sebagai penanda script (tidak ada tombol on/off).
local TextService = game:GetService("TextService")
local NameFx = { t0 = os.clock() }

local NAME_COLORS = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, Color3.fromRGB(170, 90, 255)),  -- ungu
    ColorSequenceKeypoint.new(0.25, Color3.fromRGB(60, 205, 255)),  -- biru muda
    ColorSequenceKeypoint.new(0.50, Color3.fromRGB(255, 110, 210)), -- pink
    ColorSequenceKeypoint.new(0.75, Color3.fromRGB(60, 205, 255)),
    ColorSequenceKeypoint.new(1.00, Color3.fromRGB(170, 90, 255)),
})
local NAME_FONT = Enum.Font.FredokaOne

-- Tempat nama: di atas karakter & panel kiri atas
local function nameHolders()
    local gg = PlayerGui:FindFirstChild("GameGui")
    local world = gg and gg:FindFirstChild("World")
    local cam = world and world:FindFirstChild("Camera")
    local chat = PlayerGui:FindFirstChild("ChatGui")
    local hud = chat and chat:FindFirstChild("HUD")
    local panel = hud and hud:FindFirstChild("PlayerPanel")
    return cam and cam:FindFirstChild("NameTag"), panel and panel:FindFirstChild("Name")
end

local function textWidth(text, size)
    local ok, v = pcall(TextService.GetTextSize, TextService, text, size, NAME_FONT, Vector2.new(2000, 200))
    return (ok and v.X or #text * size * 0.55) + 6 -- +6 untuk garis tepi
end

local function makeLabel(holder, size, isTag)
    local lb = Instance.new("TextLabel")
    lb.Name = "n4thName"
    lb.BackgroundTransparency = 1
    lb.Font = NAME_FONT
    lb.TextSize = size
    lb.TextColor3 = Color3.new(1, 1, 1)
    lb.Text = Misc.NameText
    lb.ZIndex = isTag and 1017 or 10
    if isTag then
        lb.AnchorPoint = Vector2.new(0.5, 0.5) -- denyut dari tengah
        lb.Position = UDim2.fromScale(0.5, 0.5)
    else
        lb.AnchorPoint = Vector2.new(0, 0.5)
        lb.Position = UDim2.new(0, 3, 0.5, 0)
        lb.TextXAlignment = Enum.TextXAlignment.Left
    end
    local st = Instance.new("UIStroke")
    st.Thickness = 2
    st.Color = Color3.fromRGB(25, 12, 40)
    st.Transparency = 0.1
    st.Parent = lb
    local gr = Instance.new("UIGradient")
    gr.Color = NAME_COLORS
    gr.Rotation = 12
    gr.Parent = lb
    local sc = Instance.new("UIScale")
    sc.Parent = lb
    lb.Parent = holder
    return { holder = holder, bitmap = holder:FindFirstChild("BitmapText"), label = lb, gr = gr, sc = sc,
        size = size, isTag = isTag, text = nil, w = 0 }
end

local function dropEntry(e)
    if not e then return end
    pcall(function() e.label:Destroy() end)
    if e.bitmap then pcall(function() e.bitmap.Visible = true end) end
    if e.isTag and e.bitmap then
        -- kembalikan ukuran tag & posisi wrench sesuai nama asli
        pcall(function()
            local bw = e.bitmap.Size.X.Offset
            e.holder.Size = UDim2.fromOffset(bw, e.holder.Size.Y.Offset)
            local wr = e.holder:FindFirstChild("Wrench")
            if wr then wr.Position = UDim2.fromOffset(bw + 4, wr.Position.Y.Offset) end
        end)
    end
end

local function nameRestore()
    dropEntry(NameFx.tag)
    dropEntry(NameFx.panel)
    NameFx.tag, NameFx.panel = nil, nil
end

-- Pastikan label ada, nama asli tersembunyi, ukuran tag pas dengan teks
local function nameKeep(e, holder, size, isTag)
    if not holder then
        dropEntry(e)
        return nil
    end
    if not e or e.holder ~= holder or not e.label.Parent then
        dropEntry(e)
        e = makeLabel(holder, size, isTag)
    end
    if e.text ~= Misc.NameText then
        e.text = Misc.NameText
        e.label.Text = Misc.NameText
        e.w = textWidth(Misc.NameText, size)
    end
    if e.bitmap and e.bitmap.Visible then e.bitmap.Visible = false end
    if isTag then
        local h = math.max(holder.Size.Y.Offset, size + 6)
        if e.label.Size.X.Offset ~= e.w or e.label.Size.Y.Offset ~= h then
            e.label.Size = UDim2.fromOffset(e.w, h)
        end
        if holder.Size.X.Offset ~= e.w then
            holder.Size = UDim2.fromOffset(e.w, holder.Size.Y.Offset) -- bendera tetap di kiri nama
        end
        local wr = holder:FindFirstChild("Wrench")
        if wr and wr.Position.X.Offset ~= e.w + 4 then
            wr.Position = UDim2.fromOffset(e.w + 4, wr.Position.Y.Offset)
        end
    else
        e.label.Size = UDim2.new(1, -6, 1, 0)
    end
    return e
end

-- Animasi tiap frame: gradient mengalir + denyut halus
local holderAt, animAt = 0, 0
table.insert(Connections, RunService.RenderStepped:Connect(function()
    if not alive() or not Misc.CustomName then return end
    local now = os.clock()
    if now - holderAt > 0.5 then -- cari holder cukup 2x per detik
        holderAt = now
        local tag, panelName = nameHolders()
        NameFx.tag = nameKeep(NameFx.tag, tag, 22, true)
        NameFx.panel = nameKeep(NameFx.panel, panelName, 21, false)
    end
    if now - animAt < 1 / 30 then return end -- animasi cukup 30 fps
    animAt = now
    local t = now - NameFx.t0
    local offset = Vector2.new(((t * 0.45) % 2) - 1, 0)
    local pulse = 1 + 0.045 * math.sin(t * 3.2)
    local tg, pn = NameFx.tag, NameFx.panel
    if tg then
        tg.gr.Offset = offset
        tg.sc.Scale = pulse
    end
    if pn then
        pn.gr.Offset = offset
        pn.sc.Scale = pulse
    end
end))

---------------------------------------------------------------------
-- ANTI AFK
---------------------------------------------------------------------
table.insert(Connections, LocalPlayer.Idled:Connect(function()
    if State.AntiAfk and alive() then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end))

---------------------------------------------------------------------
-- GUI TAMBAHAN: Grid Tile 5x5 + tombol Fly ▲/▼
---------------------------------------------------------------------
local guiParent
if type(gethui) == "function" then
    local ok, parent = pcall(gethui)
    if ok and typeof(parent) == "Instance" then guiParent = parent end
end
guiParent = guiParent or game:GetService("CoreGui")

local function newScreenGui(name)
    local sg = Instance.new("ScreenGui")
    sg.Name = name
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    sg.DisplayOrder = 999
    sg.Enabled = false
    if syn and syn.protect_gui then pcall(syn.protect_gui, sg) end
    local ok = pcall(function() sg.Parent = guiParent end)
    if not ok then sg.Parent = PlayerGui end
    return sg
end

local GRID_RADIUS = 2
local CELL = 38
local GAP = 4

local GridGui = newScreenGui("n4thGrid")
UI.GridGui = GridGui

local side = GRID_RADIUS * 2 + 1
local gridSize = side * CELL + (side - 1) * GAP

local Panel = Instance.new("Frame")
Panel.Size = UDim2.fromOffset(gridSize + 20, gridSize + 96)
Panel.Position = UDim2.fromOffset(20, 80)
Panel.BackgroundColor3 = Color3.fromRGB(22, 22, 28)
Panel.BorderSizePixel = 0
Panel.Parent = GridGui
Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 10)
local pStroke = Instance.new("UIStroke", Panel)
pStroke.Color = Color3.fromRGB(70, 70, 90)

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -40, 0, 28)
Title.Position = UDim2.fromOffset(10, 4)
Title.BackgroundTransparency = 1
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.TextColor3 = Color3.fromRGB(235, 235, 245)
Title.Text = I18N.T("Grid Tile")
Title.Parent = Panel

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.fromOffset(24, 24)
CloseBtn.Position = UDim2.new(1, -30, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75)
CloseBtn.Text = "X"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.TextColor3 = Color3.new(1, 1, 1)
CloseBtn.Parent = Panel
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 6)
CloseBtn.MouseButton1Click:Connect(function()
    GridGui.Enabled = false
end)

local GridHolder = Instance.new("Frame")
GridHolder.Size = UDim2.fromOffset(gridSize, gridSize)
GridHolder.Position = UDim2.fromOffset(10, 36)
GridHolder.BackgroundTransparency = 1
GridHolder.Parent = Panel

local COLOR_OFF = Color3.fromRGB(48, 48, 60)
local COLOR_ON = Color3.fromRGB(46, 160, 90)
local COLOR_ME = Color3.fromRGB(60, 110, 220)
local CellButtons = {}

-- Grid berbagi mode Farm, Pabrik, dan Lahan.
UI.GridMode = "farm"
UI.gridTarget = function()
    if UI.GridMode == "pabrik" then return Pabrik.Tiles end
    if UI.GridMode == "lahan" then return Build.Tiles end
    return State.Offsets
end

local function paintCell(key)
    local b = CellButtons[key]
    if b then
        b.BackgroundColor3 = UI.gridTarget()[key] and COLOR_ON
            or (key == "0,0" and COLOR_ME or COLOR_OFF)
    end
end

for row = 0, side - 1 do
    for col = 0, side - 1 do
        local dx, dy = col - GRID_RADIUS, row - GRID_RADIUS
        local key = dx .. "," .. dy
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.fromOffset(CELL, CELL)
        btn.Position = UDim2.fromOffset(col * (CELL + GAP), row * (CELL + GAP))
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 12
        btn.TextColor3 = Color3.new(1, 1, 1)
        btn.Parent = GridHolder
        Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

        if dx == 0 and dy == 0 then
            btn.Text = "ME"
            btn.BackgroundColor3 = COLOR_ME
            btn.AutoButtonColor = false
            CellButtons[key] = btn
        else
            btn.Text = ""
            btn.BackgroundColor3 = UI.gridTarget()[key] and COLOR_ON or COLOR_OFF
            CellButtons[key] = btn
            btn.MouseButton1Click:Connect(function()
                local tgt = UI.gridTarget()
                tgt[key] = (not tgt[key]) or nil
                paintCell(key)
                updateStatus()
            end)
        end
    end
end

local GridStart = Instance.new("TextButton")
GridStart.Size = UDim2.new(1, -20, 0, 30)
GridStart.Position = UDim2.new(0, 10, 1, -54)
GridStart.BackgroundColor3 = COLOR_ON
GridStart.Font = Enum.Font.GothamBold
GridStart.TextSize = 14
GridStart.TextColor3 = Color3.new(1, 1, 1)
GridStart.Text = "START"
GridStart.Parent = Panel
Instance.new("UICorner", GridStart).CornerRadius = UDim.new(0, 8)
UI.GridStart = GridStart
GridStart.MouseButton1Click:Connect(function()
    if UI.GridMode == "lahan" then
        if Build.Running then Build.stop() elseif Build.start then Build.start() end
    elseif UI.GridMode == "pabrik" then
        if Pabrik.Running then Pabrik.stop() else Pabrik.start() end
    elseif State.Running and not State.Override then
        stopFarm()
    else
        startFarm()
    end
end)

local ClearBtn = Instance.new("TextButton")
ClearBtn.Size = UDim2.new(1, -20, 0, 18)
ClearBtn.Position = UDim2.new(0, 10, 1, -22)
ClearBtn.BackgroundTransparency = 1
ClearBtn.Font = Enum.Font.Gotham
ClearBtn.TextSize = 12
ClearBtn.TextColor3 = Color3.fromRGB(180, 180, 195)
ClearBtn.Text = I18N.T("Bersihkan pilihan")
ClearBtn.Parent = Panel
ClearBtn.MouseButton1Click:Connect(function()
    local tgt = UI.gridTarget()
    for key in pairs(tgt) do
        tgt[key] = nil
        paintCell(key)
    end
    updateStatus()
end)

-- Tombol ganti mode Grid: Farm (tile Auto Farm) / Pabrik (tile break pabrik)
do (function()
    local ModeBtn = Instance.new("TextButton")
    ModeBtn.Size = UDim2.fromOffset(62, 22)
    ModeBtn.Position = UDim2.new(1, -98, 0, 7)
    ModeBtn.Font = Enum.Font.GothamBold
    ModeBtn.TextSize = 11
    ModeBtn.TextColor3 = Color3.new(1, 1, 1)
    ModeBtn.Parent = Panel
    Instance.new("UICorner", ModeBtn).CornerRadius = UDim.new(0, 6)
    Title.Size = UDim2.new(1, -106, 0, 28)

    local function apply()
        local pab = UI.GridMode == "pabrik"
        local lah = UI.GridMode == "lahan"
        ModeBtn.Text = lah and I18N.T("Lahan") or (pab and I18N.T("Pabrik") or "Farm")
        ModeBtn.BackgroundColor3 = lah and Color3.fromRGB(60, 140, 200)
            or (pab and Color3.fromRGB(200, 120, 40) or Color3.fromRGB(60, 60, 75))
        Title.Text = I18N.T(lah and "Tile Break Lahan" or (pab and "Tile Break Pabrik" or "Grid Tile"))
        for key in pairs(CellButtons) do paintCell(key) end
        if lah then
            GridStart.Text = I18N.T(Build.Running and "STOP LAHAN" or "START LAHAN")
            GridStart.BackgroundColor3 = Build.Running and Color3.fromRGB(200, 60, 60) or COLOR_ON
        elseif pab then
            GridStart.Text = I18N.T(Pabrik.Running and "STOP PABRIK" or "START PABRIK")
            GridStart.BackgroundColor3 = Pabrik.Running and Color3.fromRGB(200, 60, 60) or COLOR_ON
        else
            local run = State.Running and not State.Override
            GridStart.Text = run and "STOP" or "START"
            GridStart.BackgroundColor3 = run and Color3.fromRGB(200, 60, 60) or COLOR_ON
        end
    end

    UI.setGridMode = function(m)
        UI.GridMode = m
        apply()
        return true
    end
    UI.applyGrid = apply
    ModeBtn.MouseButton1Click:Connect(function() -- Farm -> Pabrik -> Lahan -> Farm
        local nxt = { farm = "pabrik", pabrik = "lahan", lahan = "farm" }
        UI.setGridMode(nxt[UI.GridMode] or "farm")
    end)
    apply()
end)() end

-- Panel bisa digeser lewat judul
do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local dragging, dragStart, startPos
    Title.Active = true
    Title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Panel.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    table.insert(Connections, UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local d = input.Position - dragStart
            Panel.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end))
end)() end

task.spawn(function()
    while alive() do
        if GridGui.Enabled then
            local px, py = getPlayerTile()
            local t = px and ("ME (" .. px .. "," .. py .. ")") or I18N.T("Grid Tile | tidak di world")
            if Title.Text ~= t then Title.Text = t end
        end
        task.wait(0.5)
    end
end)

-- Tombol ▲/▼ untuk Fly (muncul saat Fly aktif)
local FlyPad = newScreenGui("n4thFlyPad")
UI.FlyPad = FlyPad

local function flyButton(text, yOffset, onHold)
    local b = Instance.new("TextButton")
    b.Size = UDim2.fromOffset(64, 64)
    b.AnchorPoint = Vector2.new(1, 0.5)
    b.Position = UDim2.new(1, -24, 0.5, yOffset)
    b.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    b.BackgroundTransparency = 0.2
    b.Text = text
    b.Font = Enum.Font.GothamBold
    b.TextSize = 28
    b.TextColor3 = Color3.new(1, 1, 1)
    b.AutoButtonColor = true
    b.Parent = FlyPad
    Instance.new("UICorner", b).CornerRadius = UDim.new(1, 0)
    local st = Instance.new("UIStroke", b)
    st.Color = Color3.fromRGB(90, 90, 120)
    st.Thickness = 2
    -- dilepas saat jari diangkat (walau sudah geser keluar), supaya tidak nyangkut
    local heldInput = nil
    b.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            heldInput = input
            onHold(true)
        end
    end)
    table.insert(Connections, UserInputService.InputEnded:Connect(function(input)
        if heldInput and (input == heldInput
            or (input.UserInputType == Enum.UserInputType.MouseButton1
                and heldInput.UserInputType == Enum.UserInputType.MouseButton1)) then
            heldInput = nil
            onHold(false)
        end
    end))
    return b
end

flyButton("▲", -40, function(v) Misc.UpHeld = v end)
flyButton("▼", 40, function(v) Misc.DownHeld = v end)

---------------------------------------------------------------------
-- UI WINDUI
---------------------------------------------------------------------
-- Pilih bahasa saat execute (sebelum menu dibuat, karena teks menu dipasang sekali)
do (function()
    if I18N.Chosen and not I18N.Ask then
        I18N.remember()
        return
    end
    local chosen, late = false, false
    local function pick(lang)
        I18N.Saved, I18N.Chosen = lang, true
        I18N.remember()
        if late then
            notify("Bahasa / Language", "Execute ulang untuk ganti bahasa / Re-execute to apply", 5)
            return
        end
        I18N.Lang, I18N.Saved, chosen = lang, lang, true
    end
    local ok = pcall(function()
        WindUI:Popup({
            Title = "n4th",
            Icon = "languages",
            Content = "Pilih bahasa menu\nChoose menu language",
            Buttons = {
                { Title = "Indonesia", Variant = I18N.Lang == "id" and "Primary" or "Secondary",
                    Callback = function() pick("id") end },
                { Title = "English", Variant = I18N.Lang == "en" and "Primary" or "Secondary",
                    Callback = function() pick("en") end },
            },
        })
    end)
    if not ok then return end
    local t0 = os.clock()
    while not chosen and os.clock() - t0 < 30 and alive() do task.wait(0.1) end
    late = not chosen -- tidak dipilih dalam 30 detik: pakai bahasa terakhir
    if chosen then I18N.remember() end
end)() end

Session.InitStep = "membuat menu WindUI"
local Window = I18N.wrap(WindUI:CreateWindow({
    Title = "n4th",
    Icon = "sprout",
    Author = "v5.9.0 | Tester",
    Folder = "n4thOpus",
    Size = UDim2.fromOffset(640, 380),
    Theme = "Dark",
    Transparent = true,
    SideBarWidth = 150,
    ToggleKey = Enum.KeyCode.Insert,  -- PC: tekan Insert untuk buka/tutup menu
}))
UI.Window = Window
-- Tombol minimize muncul di mobile DAN PC (OnlyMobile=false), bisa digeser.
-- Cadangan PC: kalau tombol susah dicari, tekan Insert.
pcall(function()
    Window:EditOpenButton({
        Title = "n4th",
        Icon = "sprout",
        Draggable = true,
        OnlyMobile = false,
    })
end)

-- Kalau 1 elemen error, tab lain tetap dibuat
local function safe(fn)
    local ok, err = pcall(fn)
    if not ok then warn("[n4th] UI error: " .. tostring(err)) end
end

-- Sidebar dikelompokkan: grup utama bisa dibuka / ditutup (isinya tab-tab)
local Groups = {}
for _, g in ipairs({
    { key = "farm", title = "Farming", icon = "sprout", opened = true },
    { key = "aman", title = "Keamanan", icon = "shield" },
    { key = "setel", title = "Setelan", icon = "settings" },
}) do
    local ok, sec = pcall(function()
        return Window:Section({ Title = g.title, Icon = g.icon, Opened = g.opened == true })
    end)
    if ok and type(sec) == "table" and type(sec.Tab) == "function" then Groups[g.key] = sec end
end

-- Tab yang tidak dipilih sengaja tidak dibuat. NullTab menjaga kode pendukung
-- tetap aman tanpa menampilkan fitur Auto Drop, Clear World, Farmer, Lahan, Pabrik,
-- maupun tab Fitur lainnya pada UI.
local HiddenTab
HiddenTab = setmetatable({}, {
    __index = function()
        return function()
            return HiddenTab
        end
    end,
})
local HiddenTabs = {
    ["Auto Drop"] = true,
    ["Clear World"] = true,
    ["Farmer"] = true,
    ["Growscan"] = true,
    ["Statistik"] = true,
    ["Tas"] = true,
    ["Lahan"] = true,
    ["Pabrik"] = true,
    ["Titik Drop"] = true,
}
local function makeTab(title, icon, group)
    if HiddenTabs[title] or group == "fitur" then
        return HiddenTab
    end
    local parent = (group and Groups[group]) or Window
    local ok, tab = pcall(function() return parent:Tab({ Title = title, Icon = icon }) end)
    if not ok or not tab then tab = Window:Tab({ Title = title }) end
    UI.Tabs[title] = tab
    return tab
end

-- Kotak di dalam tab yang bisa dibuka / ditutup (supaya tab tidak terlihat penuh).
-- WindUI lama tanpa fitur ini: cuma judul, elemen tetap di tab.
local function box(tab, title, opened)
    local ok, sec = pcall(function()
        return tab:Section({ Title = title, Box = true, BoxBorder = true, Opened = opened == true })
    end)
    if ok and type(sec) == "table" and type(sec.Toggle) == "function" then return sec end
    pcall(function() tab:Section({ Title = title }) end)
    return tab
end
local Box = {}

-- Angka pakai Slider; kalau gagal, pakai kotak input
local function addNumber(tab, o)
    local ok = pcall(function()
        tab:Slider({
            Title = o.Title,
            Desc = o.Desc,
            Step = o.Step or 1,
            Value = { Min = o.Min, Max = o.Max, Default = o.Default },
            Callback = function(v)
                v = tonumber(v)
                if v then o.Callback(v) end
            end,
        })
    end)
    if ok then return end
    safe(function()
        tab:Input({
            Title = o.Title,
            Desc = (o.Desc and (o.Desc .. " ") or "") .. "(" .. o.Min .. "-" .. o.Max .. ")",
            Value = tostring(o.Default),
            Placeholder = tostring(o.Default),
            Callback = function(text)
                local v = tonumber(text)
                if v then o.Callback(math.clamp(v, o.Min, o.Max)) end
            end,
        })
    end)
end

-- ===== TAB: FARM =====
local FarmTab = makeTab("Farm", "pickaxe", "farm")

safe(function()
    UI.Status = FarmTab:Paragraph({ Title = "Status", Desc = "-" })
end)

Box.FarmCtl = box(FarmTab, "Kontrol", true)
Box.FarmBlock = box(FarmTab, "Block", true)
Box.FarmSpeed = box(FarmTab, "Mode & Kecepatan", false)
Box.FastPunch = box(FarmTab, "Fast Punch (pukul manual)", true)
safe(function()
    Box.FastPunch:Toggle({
        Title = "Fast Punch / Flamethrower",
        Desc = "Jika aktif, setiap block yang kamu pukul manual (apa pun) langsung dipukul berturut-turut sampai hancur, dan tetap diselesaikan walau kamu pindah arah. Tidak terkait Auto Farm.",
        Value = State.FastPunch,
        Callback = function(on)
            State.FastPunch = on and true or false
            if on then
                local ok, err = Session.FastPunch.install()
                if not ok then
                    State.FastPunch = false
                    notify("Fast Punch", tostring(err), 4)
                end
            end
        end,
    })
end)
addNumber(Box.FastPunch, {
    Title = "Jumlah Hit",
    Desc = "Maks pukulan per block; berhenti otomatis begitu block hancur (default 12)",
    Min = 2, Max = 40, Step = 1, Default = State.FastPunchHits,
    Callback = function(v) State.FastPunchHits = math.floor(v) end,
})
addNumber(Box.FastPunch, {
    Title = "Jeda antar Hit (ms)",
    Desc = "Default 190 = batas server (~0,19 dtk). Turunkan pelan-pelan (170, 150, ...) selama block tetap hancur",
    Min = 50, Max = 400, Step = 5, Default = State.FastPunchMs,
    Callback = function(v) State.FastPunchMs = math.floor(v) end,
})
if State.FastPunch then safe(function() pcall(Session.FastPunch.install) end) end


safe(function()
    UI.FarmToggle = Box.FarmCtl:Toggle({
        Title = "Auto Farm",
        Desc = "Bisa juga lewat tombol START di Grid",
        Value = false,
        Callback = function(on)
            if on then startFarm() elseif State.Running then stopFarm() end
        end,
    })
end)

safe(function()
    Box.FarmCtl:Toggle({
        Title = "Auto Collect",
        Desc = "Ambil drop di semua tile grid (caranya ikut Mode collect)",
        Value = State.AutoCollect,
        Callback = function(on) State.AutoCollect = on end,
    })
end)

safe(function()
    Box.FarmCtl:Dropdown({
        Title = "Mode collect",
        Desc = "Berlaku untuk semua fitur. Sentuhan = seperti main manual. Remote = ambil dari jauh (cara lama, cepat)",
        Values = { "Sentuhan", "Remote" },
        Value = State.CollectMode,
        Callback = function(v)
            if type(v) == "table" then v = v[1] end
            if v == "Sentuhan" or v == "Remote" then State.CollectMode = v end
        end,
    })
end)

addNumber(Box.FarmCtl, {
    Title = "Radius collect (mode Remote)",
    Desc = "Jarak ambil drop di sekitar karakter (tile)",
    Min = 1, Max = 5, Step = 1, Default = State.CollectRadius,
    Callback = function(v) State.CollectRadius = math.floor(v) end,
})


safe(function()
    Box.FarmCtl:Button({
        Title = "Buka Grid Tile",
        Desc = "Kotak 5x5, tengah = karakter",
        Callback = function() UI.setGridMode("farm") GridGui.Enabled = true end,
    })
end)

-- ===== TAB: AUTO ROUTE DROP (fitur baru di bawah FARM) =====
do (function()
    local tab = makeTab("Auto Route Drop", "route", "farm")
    safe(function() UI.RouteDropStatus = tab:Paragraph({ Title = "Status", Desc = "Mati" }) end)
    local setup = box(tab, "Pengaturan Target & Jalur", true)
    local control = box(tab, "Kontrol", true)

    local function itemOptions(platformOnly)
        local ids = {}
        if platformOnly then
            -- Platform adalah tile pijakan, jadi daftar platform tetap berasal dari ItemDB.
            for id, it in pairs(ItemDB) do
                if type(id) == "number" and type(it) == "table" and it.platform == true then
                    ids[#ids + 1] = id
                end
            end
        else
            -- Target harus berasal dari objek DROP yang benar-benar ada di world.
            -- Jangan mengambil daftar dari tile foreground/background yang sedang terpasang.
            -- Item seed dan item placeable (termasuk background/wallpaper) boleh dipilih,
            -- tetapi hanya jika ada entitas drop aktif dengan jumlah dan koordinat valid.
            if not Drops.list then findDropRefs() end
            local seen = {}
            for _, d in pairs(Drops.list or {}) do
                if type(d) == "table"
                    and type(d.id) == "number"
                    and (d.n or 0) > 0
                    and type(d.x) == "number"
                    and type(d.y) == "number" then
                    local it = ItemDB[d.id]
                    if it and (it.kind == "seed" or isPlaceable(d.id)) then
                        seen[d.id] = true
                    end
                end
            end
            for id in pairs(seen) do ids[#ids + 1] = id end
        end
        table.sort(ids)
        local labels = {}
        for _, id in ipairs(ids) do labels[#labels + 1] = ("%s [%d]"):format(itemName(id), id) end
        if #labels == 0 and not platformOnly then
            labels = { "(belum ada seed/block/bg yang sedang ter-drop; refresh setelah harvest)" }
        end
        return labels
    end
    local function idFromLabel(value, platformOnly)
        local options = itemOptions(platformOnly)
        if type(value) == "table" then
            -- Beberapa versi dropdown mengirim object pilihan, bukan string label.
            local candidate = value.Value or value.value or value.Name or value.name
                or value.Text or value.text or value[1]
            if candidate ~= nil then value = candidate end
        end
        if type(value) == "number" then
            -- Jika angka adalah ID valid, gunakan langsung; jika bukan, anggap index dropdown.
            if ItemDB[value] then return value end
            local label = options[value]
            return label and tonumber(tostring(label):match("%[(%d+)%]")) or nil
        end
        local str = tostring(value or "")
        local id = tonumber(str:match("%[(%d+)%]"))
        if id and ItemDB[id] then return id end
        -- Fallback untuk callback dropdown yang mengirim label tanpa akhiran ID.
        for _, label in ipairs(options) do
            if str == label then return tonumber(label:match("%[(%d+)%]")) end
        end
        return nil
    end

    safe(function()
        UI.RouteDropTarget = setup:Dropdown({
            Title = "Seed / Block / BG yang sedang ter-drop",
            Desc = "Hanya menampilkan item yang benar-benar sedang ter-drop di world (hasil harvest/drop), bukan tile yang sedang terpasang. Refresh setelah hasil harvest muncul.",
            Values = itemOptions(false),
            Callback = function(v)
                local id = idFromLabel(v, false)
                if id then
                    RouteDrop.TargetId = id
                    routeDropLog(("Target dipilih: %s [%d]"):format(itemName(id), id), true)
                    if Session.Ready then Config.save(true) end
                else
                    routeDropLog("ERROR: gagal membaca ID dari pilihan Target.", true)
                end
            end,
        })
    end)
    safe(function()
        UI.RouteDropPlatform = setup:Dropdown({
            Title = "Pijakan / Platform",
            Desc = "Pilih platform tempat drop berada; Wooden Platform bisa dipilih jika tersedia.",
            Values = itemOptions(true),
            Callback = function(v)
                local id = idFromLabel(v, true)
                if id then
                    RouteDrop.PlatformId = id
                    routeDropLog(("Platform dipilih: %s [%d]"):format(itemName(id), id), true)
                    if Session.Ready then Config.save(true) end
                else
                    routeDropLog("ERROR: gagal membaca ID dari pilihan Platform.", true)
                end
            end,
        })
    end)
    safe(function()
        setup:Button({ Title = "Refresh daftar DROP & platform", Desc = "Scan ulang item yang benar-benar ter-drop di world setelah harvest.", Callback = function()
            UI.later("routeDropRefresh", function()
                findDropRefs()
                if UI.RouteDropTarget then pcall(function() UI.RouteDropTarget:Refresh(itemOptions(false)) end) end
                if UI.RouteDropPlatform then pcall(function() UI.RouteDropPlatform:Refresh(itemOptions(true)) end) end
            end)
        end })
    end)
    safe(function()
        setup:Dropdown({
            Title = "Arah tracking", Desc = "Mode sweep baris menggunakan urutan tetap: kanan ke kiri, lalu turun ke baris berikutnya.",
            Values = { "Kiri → Kanan", "Kanan → Kiri" }, Value = RouteDrop.Direction,
            Callback = function(v)
                if type(v) == "table" then v = v[1] end
                if v == "Kiri → Kanan" or v == "Kanan → Kiri" then
                    RouteDrop.Direction = v
                    if Session.Ready then Config.save(true) end
                end
            end,
        })
    end)
    safe(function()
        setup:Button({
            Title = "Tandai Drop Point di posisi sekarang",
            Desc = "Berdiri di lokasi tujuan, lalu klik satu kali untuk menyimpan koordinatnya.",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    routeDropLog("ERROR: klik tandai Drop Point gagal; Auto.here() tidak memberi koordinat.", true)
                    notify("Auto Route Drop", "Kamu belum masuk world", 3)
                    return
                end
                RouteDrop.DropX, RouteDrop.DropY = x, y
                RouteDrop.World = Refs.World
                if Session.Ready then Config.save(true) end
                routeDropLog(("Drop Point tersimpan di (%d,%d), world=%s"):format(x, y, tostring(Guard.worldName())), true)
                notify("Auto Route Drop", ("Drop Point tersimpan: (%d,%d)"):format(x, y), 4)
            end,
        })
    end)
    local function startRouteDrop(source)
        routeDropLog("PERMINTAAN START diterima dari " .. tostring(source), true)
        local ok, result = pcall(function()
            -- Catat kondisi satu per satu agar titik penolakan terlihat jelas.
            -- Jangan panggil Refs.State/playerState saat callback UI masih berjalan.
            -- Pada beberapa versi client, fungsi state dapat yield; itu membuat log Start
            -- terlihat berhenti tepat setelah "PERMINTAAN START diterima".
            routeDropLog(("DIAG START PRECHECK: worldRef=%s stateFn=%s target=%s platform=%s dropX=%s dropY=%s guard=%s stateRun=%s clear=%s farmer=%s pabrik=%s build=%s"):
                format(tostring(Refs.World ~= nil), tostring(type(Refs.State) == "function"), tostring(RouteDrop.TargetId),
                    tostring(RouteDrop.PlatformId), tostring(RouteDrop.DropX), tostring(RouteDrop.DropY),
                    tostring(Guard.Mode), tostring(State.Running), tostring(Clear.Running),
                    tostring(Farmer.Running), tostring(Pabrik.Running), tostring(Build.Running)), true)

            local reason
            if not Refs.World or type(Refs.State) ~= "function" then reason = "Masuk world dan tunggu data karakter"
            elseif not RouteDrop.TargetId then reason = "Pilih Seed / Block target"
            elseif not RouteDrop.PlatformId then reason = "Pilih platform pijakan"
            elseif type(RouteDrop.DropX) ~= "number" or type(RouteDrop.DropY) ~= "number" or RouteDrop.DropX < 0 or RouteDrop.DropY < 0 then reason = "Tentukan Drop Point terlebih dahulu"
            elseif type(Refs.Hud) ~= "table" or type(rawget(Refs.Hud, "onDrop")) ~= "function" then reason = "Fungsi drop game belum tersedia"
            elseif State.Running or Clear.Running or Farmer.Running or Pabrik.Running or Build.Running then reason = "Hentikan aktivitas farming lain terlebih dahulu"
            elseif Guard.Mode ~= "idle" then reason = "Penjaga sedang aktif; tunggu sampai idle" end
            if reason then
                RouteDrop.Running = false
                RouteDrop.Status = "Start ditolak: " .. reason
                routeDropLog("START DITOLAK: " .. reason, true)
                notify("Auto Route Drop", reason, 4)
                if UI.RouteDropToggle then UI.later("routeDropToggleOff", function() UI.RouteDropToggle:Set(false) end) end
                return false
            end
            RouteDrop.World = Refs.World
            RouteDrop.Running = true
            table.clear(RouteDrop.Skip)
            RouteDrop.CurrentRow = nil
            RouteDrop.Status = "Memulai tracking dari baris paling atas (kanan ke kiri)"
            routeDropLog(("START BERHASIL: target=%s [%s], platform=%s [%s], drop=(%d,%d), world=%s, inv=%d"):format(
                itemName(RouteDrop.TargetId), tostring(RouteDrop.TargetId),
                itemName(RouteDrop.PlatformId), tostring(RouteDrop.PlatformId),
                RouteDrop.DropX, RouteDrop.DropY, tostring(Guard.worldName()), invCount(RouteDrop.TargetId)), true)
            AutoDrop.On = false
            return true
        end)
        if not ok then
            RouteDrop.Running = false
            RouteDrop.Status = "Error saat Start: " .. tostring(result)
            routeDropLog("EXCEPTION startRouteDrop: " .. tostring(result), true)
            warn("[n4th] EXCEPTION startRouteDrop: " .. tostring(result))
            return false
        end
        return result
    end

    safe(function()
        UI.RouteDropToggle = control:Toggle({
            Title = "Jalankan Auto Route Drop",
            Desc = "Tracking drop di platform, kumpulkan item pilihan, drop saat mencapai 200, lalu kembali ke jalur terakhir. Jika toggle tidak merespons, gunakan tombol Mulai di bawah.",
            Value = false,
            Callback = function(on)
                routeDropLog("CALLBACK TOGGLE diterima; value=" .. tostring(on) .. ", type=" .. typeof(on), true)
                if on then
                    startRouteDrop("toggle")
                else
                    RouteDrop.Running = false
                    RouteDrop.Status = "Dihentikan"
                    routeDropLog("Auto Route Drop dihentikan dari toggle.", true)
                    releaseInput()
                end
            end,
        })
    end)
    safe(function()
        control:Button({
            Title = "MULAI Auto Route Drop (Fallback)",
            Desc = "Gunakan tombol ini jika toggle tidak memanggil fungsi start.",
            Callback = function()
                routeDropLog("TOMBOL MULAI diklik.", true)
                startRouteDrop("tombol fallback")
            end,
        })
    end)
    safe(function()
        control:Button({ Title = "Hentikan Auto Route Drop", Callback = function()
            RouteDrop.Running = false
            RouteDrop.Status = "Dihentikan"
            routeDropLog("Auto Route Drop dihentikan lewat tombol Stop.", true)
            releaseInput()
        end })
    end)
    safe(function()
        control:Button({
            Title = "Salin Log Auto Route Drop",
            Desc = "Salin catatan berhasil/gagal ke clipboard untuk dikirim ke ChatGPT.",
            Callback = function()
                local ok, message = routeDropCopyLogs()
                notify("Log Auto Route Drop", message, 5)
                if ok then print("[n4th][RouteDrop] Log disalin ke clipboard.") end
            end,
        })
    end)
    safe(function()
        control:Button({
            Title = "Hapus Log",
            Desc = "Kosongkan riwayat diagnostik sebelum pengujian baru.",
            Callback = function()
                table.clear(RouteDrop.Logs)
                RouteDrop.LastLog = nil
                routeDropLog("Log dibersihkan; sesi pengujian baru.", true)
                notify("Log Auto Route Drop", "Riwayat log dibersihkan.", 3)
            end,
        })
    end)

    task.spawn(function()
        while alive() do
            local dropPoint = RouteDrop.DropX >= 0 and ("(" .. RouteDrop.DropX .. "," .. RouteDrop.DropY .. ")") or "belum ditentukan"
            local txt = table.concat({
                RouteDrop.Status,
                "Target: " .. (RouteDrop.TargetId and itemName(RouteDrop.TargetId) or "belum dipilih"),
                "Pijakan: " .. (RouteDrop.PlatformId and itemName(RouteDrop.PlatformId) or "belum dipilih"),
                "Arah: " .. RouteDrop.Direction,
                "Drop Point: " .. dropPoint,
                ("Terkumpul (kunjungan): %d | Ter-drop: %d"):format(RouteDrop.CollectedStops, RouteDrop.Dropped),
                ("Log diagnostik: %d baris (klik Salin Log untuk menyalin)"):format(#RouteDrop.Logs),
                "Drop Point dikecualikan dari tracking / collect target.",
            }, "\n")
            if UI.RouteDropStatus and txt ~= RouteDrop.Shown then
                RouteDrop.Shown = txt
                pcall(function() UI.RouteDropStatus:SetDesc(txt) end)
            end
            task.wait(0.5)
        end
    end)
end)() end

-- ===== AUTO BREAK BLOCK: jenis block dari foreground world aktif =====
do (function()
    local controls = box(FarmTab, "Auto Break Block", true)
    local signature, lastWorld, lastGrid, lastName, lastWidth, lastHeight, refreshedAt
    safe(function() UI.WorldBreakStatus = controls:Paragraph({ Title = "Status Auto Break", Desc = "Pilih block dari world, lalu nyalakan Auto Break Block." }) end)
    safe(function()
        UI.WorldBreakItems = controls:Dropdown({
            Title = "Block di world",
            Desc = "Pilih satu jenis block atau wallpaper (BG). Angka x menunjukkan jumlah di world aktif. Wallpaper hanya bisa dipecah kalau block depannya kosong.",
            Values = { "(memuat block world...)" },
            Callback = function(value)
                if UI.WorldBreakRefreshing then return end
                if type(value) == "table" then value = value[1] end
                local id = type(value) == "string" and tonumber(value:match("%[(%d+)%]$"))
                if not id then return end
                if Clear.Running and Clear.TargetId then
                    notify("Auto Break Block", "Hentikan Auto Break sebelum mengganti target", 3)
                    UI.later("worldBreakItems", function() UI.WorldBreakRefresh(true) end)
                    return
                end
                State.WorldBreakId = id
                if Session.Ready then Config.save(true) end
            end,
        })
    end)
    function UI.WorldBreakRefresh(force)
        local w = Refs.World
        local grid, name = w and w.fg, w and w.name
        local width, height = w and w.w, w and w.h
        local sameWorld = w == lastWorld and grid == lastGrid and name == lastName and width == lastWidth and height == lastHeight
        -- Jangan scan dunia pada tab tersembunyi atau selama target break terkunci.
        if not force and signature and sameWorld then
            if Clear.Running or Window.Closed or not FarmTab.Selected or os.clock() - (refreshedAt or 0) < 15 then return end
        end
        local ids, counts, layers = Auto.worldBreakOptions(true)
        if Refs.World ~= w or (w and w.fg ~= grid) then return end
        lastWorld, lastGrid, lastName, lastWidth, lastHeight, refreshedAt = w, grid, name, width, height, os.clock()
        local labels = {}
        for _, id in ipairs(ids) do labels[#labels + 1] = ("%s%s x%d [%d]"):format(itemName(id), layers[id] == "bg" and " (BG)" or "", counts[id], id) end
        if #labels == 0 then labels = { "(belum ada block / wallpaper yang bisa dipecah di world ini)" } end
        local current = tostring(Refs.World) .. ":" .. tostring(Refs.World and Refs.World.name) .. ":" .. table.concat(labels, "|")
        if not force and current == signature then return end
        local ok, err = UI.exec(function()
            UI.WorldBreakRefreshing = true
            local refreshed, message = pcall(function()
                UI.WorldBreakItems:Refresh(labels)
                selectSaved(UI.WorldBreakItems, labels, State.WorldBreakId)
            end)
            UI.WorldBreakRefreshing = false
            if not refreshed then error(message, 0) end
        end)
        if ok then signature = current else warn("[n4th] Daftar block world: " .. tostring(err)) end
    end
    safe(function()
        controls:Button({ Title = "Refresh block world", Desc = "Baca ulang jenis dan jumlah block dari world aktif.",
            Callback = function() UI.later("worldBreakItems", function() UI.WorldBreakRefresh(true) end) end })
    end)
    safe(function()
        UI.WorldBreakCollect = controls:Toggle({
            Title = "Ambil drop otomatis",
            Desc = "Khusus Auto Break Block. Mati = tidak mengejar drop; item yang tersentuh tetap bisa terambil oleh game.",
            Value = State.WorldBreakCollect,
            Callback = function(on)
                State.WorldBreakCollect = on
                Drops.seen = nil
                if Session.Ready then Config.save(true) end
            end,
        })
    end)
    safe(function()
        UI.WorldBreakToggle = controls:Toggle({
            Title = "Auto Break Block",
            Desc = "Jalan mencari block pilihan dan pecahkan hanya jenis itu. Target yang tidak terjangkau dilewati.",
            Value = false,
            Callback = function(on)
                if UI.ClearVisualSync then return end
                if on then Auto.startWorldBreak()
                elseif Clear.Running and Clear.TargetId then stopClear("Dihentikan: Auto Break Block") end
            end,
        })
    end)
    task.spawn(function()
        while alive() do
            UI.later("worldBreakItems", function() UI.WorldBreakRefresh(false) end)
            task.wait(6)
        end
    end)
end)() end

-- ===== TAB: AUTO DROP =====
do (function()
    local tab = makeTab("Auto Drop", "package-open", "farm")
    safe(function() UI.AutoDropStatus = tab:Paragraph({ Title = "Status", Desc = "-" }) end)
    local controls = box(tab, "Kontrol", true)
    local focusBox = box(tab, "Fokus panen", true)

    safe(function()
        UI.AutoDropToggle = controls:Toggle({
            Title = "Auto Drop instan",
            Desc = "Seed fokus atau block-nya mencapai 200 langsung di-drop di posisi karakter sekarang, tanpa jalan ke mana-mana.",
            Value = false,
            Callback = function(on)
                if on then
                    local reason = AutoDrop.startError()
                    if reason then
                        AutoDrop.On = false
                        notify("Auto Drop", reason, 4)
                        UI.later("autoDropOff", function() UI.AutoDropToggle:Set(false) end)
                        return
                    end
                end
                AutoDrop.On = on
                AutoDrop.NextTry = 0
                AutoDrop.Status = on and "Menunggu seed / block fokus mencapai 200" or "Mati"
            end,
        })
    end)

    safe(function()
        UI.TractorToggle = controls:Toggle({
            Title = "Mode Tractor",
            Desc = "Farmer hanya berjalan menyusuri pohon siap panen (seed fokus), tanpa memukul dan tanpa menanam. Tractor yang memanen saat melewatinya. Jalankan lewat tombol Farmer.",
            Value = Farmer.Tractor,
            Callback = function(on)
                Farmer.Tractor = on and true or false
                table.clear(Farmer.Skip)
                pcall(Auto.updateFarmerStatus)
                if Session.Ready then Config.save(true) end
            end,
        })
    end)

    safe(function()
        controls:Button({
            Title = "Jalankan / hentikan Farmer",
            Desc = "Sama dengan toggle di tab Farmer.",
            Callback = function()
                if Farmer.Running then stopFarmer() else Auto.startFarmer() end
            end,
        })
    end)

    -- Fokus panen: seed yang punya pohon siap panen. Yang dipilih dipanen Farmer dan dipantau untuk drop.
    safe(function()
        local labels, selected = AutoDrop.focusLabels(true)
        UI.AutoDropFocus = focusBox:Dropdown({
            Title = "Seed fokus",
            Desc = "Seed yang ada di pohon siap panen. Yang dipilih jadi satu-satunya yang dipanen Farmer, dan seed + block-nya yang di-drop.",
            Values = labels,
            Value = selected,
            Callback = function(option)
                if UI.AutoDropRefreshing then return end
                if type(option) == "table" then option = option[1] end
                local id = AutoDrop.focusFromLabel(option)
                if id == Farmer.Focus then return end
                Farmer.Focus = id
                table.clear(Farmer.Skip)
                pcall(Auto.updateFarmerStatus)
                if Session.Ready then Config.save(true) end
                UI.later("autoDropFocus", function() UI.AutoDropRefresh(true) end)
            end,
        })
    end)

    local lastSig
    UI.AutoDropRefresh = function(force)
        if not UI.AutoDropFocus then return end
        if not force and not UI.tabVisible("Auto Drop") then return end
        local labels, selected = AutoDrop.focusLabels(force)
        local signature = table.concat(labels, "|") .. "/" .. selected
        if not force and signature == lastSig then return end
        local ok = UI.exec(function()
            UI.AutoDropRefreshing = true
            local refreshed, refreshError = pcall(function()
                UI.AutoDropFocus:Refresh(labels)
                UI.AutoDropFocus:Select(selected)
            end)
            UI.AutoDropRefreshing = false
            if not refreshed then error(refreshError, 0) end
        end)
        if ok then lastSig = signature end
    end
    safe(function()
        focusBox:Button({
            Title = "Refresh daftar seed siap panen",
            Callback = function() UI.later("autoDropFocus", function() UI.AutoDropRefresh(true) end) end,
        })
    end)

    task.spawn(function()
        while alive() do
            local counts = {}
            for _, t in ipairs(AutoDrop.targets()) do
                counts[#counts + 1] = ("%s %s %d/200"):format(t.kind, itemName(t.id), invCount(t.id))
            end
            local text = table.concat({
                I18N.T(AutoDrop.Status),
                "Fokus: " .. (Farmer.Focus and itemName(Farmer.Focus) or "belum dipilih (semua seed)"),
                "Mode: " .. (Farmer.Tractor and "Tractor (jalan saja)" or "Normal (pukul & tanam)"),
                #counts > 0 and table.concat(counts, " | ") or "-",
                ("Dropped: %d"):format(AutoDrop.Dropped),
            }, "\n")
            if UI.AutoDropStatus and text ~= AutoDrop.Shown then
                AutoDrop.Shown = text
                UI.later("autoDropStatus", function() UI.AutoDropStatus:SetDesc(text) end)
            end
            if UI.AutoDropRefresh then pcall(UI.AutoDropRefresh, false) end
            task.wait(0.5)
        end
    end)
end)() end

-- ===== TAB: CLEAR WORLD =====
local ClearTab = makeTab("Clear World", "eraser", "farm")

safe(function()
    UI.ClearStatus = ClearTab:Paragraph({ Title = "Status Clear", Desc = "-" })
end)

Box.ClearCtl = box(ClearTab, "Kontrol", true)
Box.ClearSet = box(ClearTab, "Pengaturan", false)

safe(function()
    UI.ClearToggle = Box.ClearCtl:Toggle({
        Title = "Auto Clear World",
        Desc = "Bersihkan dari baris atas ke bawah",
        Value = false,
        Callback = function(on)
            if UI.ClearVisualSync then return end
            if on then Auto.startClear() elseif Clear.Running and not Clear.TargetId then stopClear() end
        end,
    })
end)

safe(function()
    Box.ClearSet:Dropdown({
        Title = "Arah sapu",
        Desc = "Zig-zag lebih cepat (tidak balik ke kiri)",
        Values = { "Kiri → Kanan", "Zig-zag" },
        Value = Clear.Sweep,
        Callback = function(opt) Clear.Sweep = opt end,
    })
end)

safe(function()
    Box.ClearSet:Toggle({
        Title = "Pakai block pijakan",
        Desc = "Taruh block untuk lewat jurang / naik ke block melayang",
        Value = Clear.UseBlock,
        Callback = function(on)
            Clear.UseBlock = on
            Auto.resetReach()
        end,
    })
end)

safe(function()
    UI.ClearBlockDropdown = Box.ClearSet:Dropdown({
        Title = "Block pijakan",
        Desc = "Block yang dipakai untuk pijakan",
        Values = { "(memuat...)" },
        Callback = function(opt)
            local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
            if id then
                Clear.ScaffoldId = id
                Auto.resetReach()
            end
        end,
    })
end)

safe(function()
    Box.ClearSet:Toggle({
        Title = "Auto collect tiap habis pecah",
        Desc = "Drop di sekitar disusuri sampai tersentuh badan (tanpa remote)",
        Value = Clear.Collect,
        Callback = function(on) Clear.Collect = on end,
    })
end)

safe(function()
    Box.ClearCtl:Button({
        Title = "Reset tile yang dilewati",
        Desc = "Coba lagi tile yang tadi gagal",
        Callback = function()
            table.clear(Clear.Skip)
            table.clear(Auto.BadEdge)
            table.clear(Auto.ClearFail)
            Auto.updateClearStatus()
        end,
    })
end)

-- ===== TAB: FARMER =====
local FarmerTab = makeTab("Farmer", "leaf", "farm")

safe(function()
    UI.FarmerStatus = FarmerTab:Paragraph({ Title = "Status Farmer", Desc = "-" })
end)

Box.FarmerCtl = box(FarmerTab, "Kontrol", true)
Box.FarmerSeed = box(FarmerTab, "Seed", true)
Box.FarmerSpeed = box(FarmerTab, "Kecepatan", false)
Box.FarmerBlock = box(FarmerTab, "Block pijakan", false)

safe(function()
    UI.FarmerToggle = Box.FarmerCtl:Toggle({
        Title = "Jalankan Farmer",
        Desc = "Panen pohon siap & tanam seed otomatis",
        Value = false,
        Callback = function(on)
            if on then Auto.startFarmer() elseif Farmer.Running then stopFarmer() end
        end,
    })
end)

safe(function()
    UI.SeedDropdown = Box.FarmerSeed:Dropdown({
        Title = "Seed untuk ditanam",
        Desc = "Hanya seed yang ada di inventori",
        Values = { "(memuat...)" },
        Callback = function(opt)
            local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
            if id then
                Farmer.SeedId = id
                table.clear(Farmer.Skip)
                Auto.updateFarmerStatus()
            end
        end,
    })
end)

safe(function()
    Box.FarmerSeed:Button({
        Title = "Refresh daftar seed",
        Callback = function() UI.later("invForce", function() doInvRefresh(true) end) end,
    })
end)

safe(function()
    Box.FarmerCtl:Toggle({
        Title = "Auto Harvest",
        Desc = "Hanya pohon yang sudah siap",
        Value = Farmer.Harvest,
        Callback = function(on) Farmer.Harvest = on end,
    })
end)

safe(function()
    Box.FarmerCtl:Toggle({
        Title = "Auto Plant",
        Desc = "Tanam di atas block yang kosong",
        Value = Farmer.Plant,
        Callback = function(on) Farmer.Plant = on end,
    })
end)

safe(function()
    Box.FarmerCtl:Toggle({
        Title = "Auto Collect",
        Desc = "Ambil hasil panen di sekitar karakter",
        Value = Farmer.Collect,
        Callback = function(on) Farmer.Collect = on end,
    })
end)

addNumber(Box.FarmerSpeed, {
    Title = "Speed Harvest (ms)",
    Desc = "Jeda setelah tiap panen",
    Min = 140, Max = 2000, Step = 10, Default = Farmer.HarvestMs,
    Callback = function(v) Farmer.HarvestMs = math.floor(v) end,
})

addNumber(Box.FarmerSpeed, {
    Title = "Speed Plant (ms)",
    Desc = "Jeda setelah tiap tanam seed",
    Min = 140, Max = 2000, Step = 10, Default = Farmer.PlantMs,
    Callback = function(v) Farmer.PlantMs = math.floor(v) end,
})

safe(function()
    Box.FarmerBlock:Toggle({
        Title = "Pakai block pijakan",
        Desc = "Taruh block kalau tidak ada jalan (block tetap tertinggal)",
        Value = Farmer.UseBlock,
        Callback = function(on)
            Farmer.UseBlock = on
            Auto.resetReach()
        end,
    })
end)

safe(function()
    UI.FarmerBlockDropdown = Box.FarmerBlock:Dropdown({
        Title = "Block pijakan",
        Desc = "Block yang dipakai untuk pijakan",
        Values = { "(memuat...)" },
        Callback = function(opt)
            local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
            if id then
                Farmer.ScaffoldId = id
                Auto.resetReach()
            end
        end,
    })
end)

-- ===== FARM: MODE & KECEPATAN =====
local SpeedTab = Box.FarmSpeed -- digabung ke tab Farm

safe(function()
    SpeedTab:Dropdown({
        Title = "Mode",
        Desc = "Place semua tile dulu, lalu break",
        Values = { "Place + Break", "Break saja", "Place saja" },
        Value = State.Mode,
        Callback = function(opt) State.Mode = opt end,
    })
end)

addNumber(SpeedTab, {
    Title = "Speed Place (ms)",
    Desc = "Jeda setelah tiap place",
    Min = 140, Max = 1000, Step = 10, Default = State.PlaceMs,
    Callback = function(v) State.PlaceMs = math.floor(v) end,
})

addNumber(SpeedTab, {
    Title = "Speed Break (ms)",
    Desc = "Jeda tiap pukulan (normal 220). Dipakai juga Clear",
    Min = 200, Max = 1000, Step = 10, Default = State.BreakMs,
    Callback = function(v) State.BreakMs = math.floor(v) end,
})

addNumber(SpeedTab, {
    Title = "Multi target break",
    Desc = "Auto Farm: tile dipukul bergantian (seperti 2 jari). Pakai Rayman's Fist = 2-3 tile segaris sekali pukul",
    Min = 1, Max = 5, Step = 1, Default = State.MultiTarget,
    Callback = function(v) State.MultiTarget = math.clamp(math.floor(v), 1, 5) end,
})

addNumber(SpeedTab, {
    Title = "Jeda setelah hancur (ms)",
    Desc = "Tunggu sebelum lanjut ke tile berikutnya",
    Min = 0, Max = 1500, Step = 50, Default = State.AfterBreakMs,
    Callback = function(v) State.AfterBreakMs = math.floor(v) end,
})

-- ===== TAB: PENGATURAN (Opsi + Misc digabung) =====
local SetTab = makeTab("Pengaturan", "sliders-horizontal", "setel")
Box.SetChar = box(SetTab, "Karakter", true)
Box.SetOpt = box(SetTab, "Opsi", true)
local OptTab = Box.SetOpt

safe(function()
    OptTab:Toggle({
        Title = "Mode Lite",
        Desc = "Matikan particle & suara (HP low-end)",
        Value = State.LiteMode,
        Callback = function(on) setLite(on) end,
    })
end)

safe(function()
    OptTab:Toggle({
        Title = "Mute suara pukulan",
        Value = State.MutePunch,
        Callback = function(on) State.MutePunch = on end,
    })
end)

safe(function()
    OptTab:Toggle({
        Title = "Animasi aksi",
        Desc = "Tangan bergerak saat break / place / tanam / panen + efek place. Matikan untuk hemat FPS",
        Value = State.Visual,
        Callback = function(on)
            State.Visual = on
            if on and not Anim.fn and Refs.World then
                notify("Animasi", "Fungsi animasi game tidak ketemu (tekan 'Hubungkan ke game')", 4)
            end
        end,
    })
end)

safe(function()
    OptTab:Toggle({
        Title = "Anti AFK",
        Value = State.AntiAfk,
        Callback = function(on) State.AntiAfk = on end,
    })
end)

addNumber(OptTab, {
    Title = "Pukulan per block (cadangan)",
    Desc = "Dipakai kalau 'Pukul: TIDAK'. 0 = otomatis",
    Min = 0, Max = 20, Step = 1, Default = State.HitsOverride,
    Callback = function(v) State.HitsOverride = math.floor(v) end,
})

-- ===== FARM: PILIH BLOCK =====
local InvTab = Box.FarmBlock -- digabung ke tab Farm

safe(function()
    UI.InvDropdown = InvTab:Dropdown({
        Title = "Pilih Block",
        Desc = "Hanya item yang bisa di-place",
        Values = { "(memuat...)" },
        Callback = function(opt)
            local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
            if id then
                State.SelectedId = id
                updateStatus()
            end
        end,
    })
end)

safe(function()
    InvTab:Button({
        Title = "Refresh daftar",
        Callback = function() UI.later("invForce", function() doInvRefresh(true) end) end,
    })
end)

-- ===== PENGATURAN: KARAKTER =====
local MiscTab = Box.SetChar

addNumber(MiscTab, {
    Title = "Walkspeed (%)",
    Desc = "100 = normal",
    Min = 50, Max = 500, Step = 10, Default = Misc.Speed,
    Callback = function(v) setSpeed(v) end,
})

safe(function()
    MiscTab:Toggle({
        Title = "Infinite Jump",
        Desc = "Lompat di udara (bisa kena rollback)",
        Value = false,
        Callback = function(on) setInfJump(on) end,
    })
end)

safe(function()
    UI.GhostToggle = MiscTab:Toggle({
        Title = "Fly + Tembus Block",
        Desc = "Tembus block, pakai tombol ▲/▼ (bisa kena rollback)",
        Value = false,
        Callback = function(on) setGhost(on) end,
    })
end)

---------------------------------------------------------------------
-- PENJAGA: deteksi Mod / Dev / pemain yang masuk world
---------------------------------------------------------------------
-- Cara kerja:
--   1. Tiap 0.5 detik baca daftar pemain di world (data game "Others").
--   2. Role dicek pakai modul Roles game (Developer / Moderator, undercover juga ketahuan).
--   3. Ada yang dicari -> semua aktivitas dihentikan, bisa juga langsung keluar world.
--   4. Setelah aman -> aktivitas sebelumnya dilanjutkan.
--      Mode keluar: tunggu X detik, masuk world lagi, cek lagi.
--      Masih ada orangnya -> keluar lagi. Sudah aman -> lanjut (Auto Farm jalan balik ke posisi awal).

do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local function strip(s) return (tostring(s or ""):gsub("`.", "")) end

    local function roleOf(uid)
        if not (RolesOk and type(RolesModule) == "table") then return nil end
        local okD, dev = pcall(RolesModule.isDeveloper, uid)
        if okD and dev then return "Developer" end
        local okM, mod = pcall(RolesModule.isModerator, uid)
        if okM and mod then return "Moderator" end
        return nil
    end

    local function worldName()
        local n = Refs.World and rawget(Refs.World, "name")
        return type(n) == "string" and n or ""
    end

    -- Pemain lain di world ini: { id, name, role }
    local function playersHere()
        local out = {}
        local o = Refs.Others
        if not o or type(rawget(o, "list")) ~= "function" then return out end
        local ok, list = pcall(o.list)
        if not ok or type(list) ~= "table" then return out end
        for _, e in ipairs(list) do
            local uid = type(e) == "table" and tonumber(e[1] or e.userId)
            if uid and uid ~= LocalPlayer.UserId then
                out[#out + 1] = { id = uid, name = strip(e[2] or e.name or uid), role = roleOf(uid) }
            end
        end
        return out
    end
    Guard.playersHere = playersHere

    local function threatsOf(list)
        local out = {}
        for _, p in ipairs(list) do
            if p.role or (Guard.Who == "Semua pemain" and not Guard.Allow[p.id]) then
                out[#out + 1] = p
            end
        end
        return out
    end

    local function label(p)
        local under = false
        if p.role and type(RolesModule.isUndercover) == "function" then
            local ok, u = pcall(RolesModule.isUndercover, p.id)
            under = ok and u == true
        end
        return p.name .. " (" .. (p.role or "Pemain") .. (under and ", undercover" or "") .. ")"
    end

    local function names(list, max)
        local t = {}
        for i, p in ipairs(list) do
            if i > (max or 4) then
                t[#t + 1] = "+" .. (#list - i + 1) .. " lagi"
                break
            end
            t[#t + 1] = label(p)
        end
        return table.concat(t, ", ")
    end

    local function anyRunning()
        return State.Running or Clear.Running or Farmer.Running
            or Pabrik.Running or Build.Running or AutoDrop.On or AutoDrop.Busy
    end

    -- Catat aktivitas yang sedang jalan (untuk dilanjutkan nanti)
    local function snapshot()
        if AutoDrop.Busy and AutoDrop.Saved then return AutoDrop.Saved end
        local tx, ty = Auto.here()
        return {
            farm = State.Running and not State.Override, clear = Clear.Running, farmer = Farmer.Running,
            clearTarget = Clear.TargetId,
            pabrik = Pabrik.Running, build = Build.Running,
            world = worldName(), tx = tx, ty = ty,
        }
    end

    local function stopAll(forAutoDrop)
        if AutoDrop.Busy and not forAutoDrop then AutoDrop.Cancelled = true end
        Auto.stopWalk()
        if Pabrik.Running then Pabrik.stop() end
        if Build.Running then Build.stop() end
        if State.Running then stopFarm() end
        if Clear.Running then
            stopClear()
            Clear.Status = "Dijeda Penjaga"
        end
        if Farmer.Running then
            stopFarmer()
            Farmer.Status = "Dijeda Penjaga"
        end
        Auto.releaseInput()
    end

    -- Keluar world = sama seperti tombol "Exit World" game
    local function leaveWorld()
        local m = Refs.Menu
        if m and type(rawget(m, "openPicker")) == "function" and pcall(m.openPicker) then
            return true
        end
        local w = Refs.World
        if w and type(rawget(w, "call")) == "function" then
            return (pcall(w.call, "LeaveWorld"))
        end
        return false
    end

    -- Masuk world lewat menu game (sama seperti ketik nama world lalu Enter)
    local function enterWorld(name)
        local w = Refs.World
        if not w or name == "" then return false, "nama world tidak diketahui" end
        local oldFg = rawget(w, "fg")
        local m = Refs.Menu
        if m and type(rawget(m, "enter")) == "function" then
            local ok, res, msg, hopping = pcall(m.enter, name)
            if not ok then return false, strip(res) end
            if hopping == true then return false, strip(msg), true end
            if res == false then return false, strip(msg) end
        elseif type(rawget(w, "enter")) == "function" then
            local ok, res, msg, hopping = pcall(w.enter, name)
            if not ok then return false, strip(res) end
            -- Game v1225: false, pesan, true berarti server sedang memindahkan pemain.
            if hopping == true then return false, strip(msg), true end
            if not res then return false, strip(msg) end
        else
            return false, "fungsi masuk world tidak ketemu"
        end
        -- berhasil kalau data world sudah diganti yang baru
        local t0 = os.clock()
        while alive() and os.clock() - t0 < 8 do
            if rawget(w, "fg") ~= oldFg then return true end
            task.wait(0.25)
        end
        return false, "world penuh / dikunci / gagal"
    end

    local function stillBack(token)
        return alive() and Guard.Token == token and Guard.Mode == "back"
    end

    -- Lanjutkan aktivitas yang tadi dihentikan
    local function resumeAll(saved, token, live)
        if not saved then return end
        local function active()
            if live then return live() end
            return stillBack(token)
        end
        if saved.world ~= "" and worldName() ~= saved.world then
            notify("Penjaga", "World sudah beda, aktivitas tidak dilanjutkan", 5)
            return
        end
        if saved.build then
            if active() then Build.start() end
        elseif saved.pabrik then
            if active() then Pabrik.start() end
        elseif saved.farm then
            -- Auto Farm memakai tile di sekitar karakter, jadi harus balik ke posisi awal
            local hx, hy = Auto.here()
            if saved.tx and (hx ~= saved.tx or hy ~= saved.ty) then
                Guard.BackText = ("Jalan balik ke posisi farm (%d,%d)"):format(saved.tx, saved.ty)
                local ok = Auto.walkTo(saved.tx, saved.ty, 45)
                if not ok and active() then ok = Auto.walkTo(saved.tx, saved.ty, 30) end
                if not ok then
                    if active() then
                        notify("Penjaga", "Gagal balik ke posisi farm. Auto Farm tidak dilanjutkan", 6)
                    end
                    return
                end
            end
            if active() then startFarm() end
        elseif saved.clear then
            if active() then Auto.startClear(saved.clearTarget) end
        elseif saved.farmer then
            if active() then Auto.startFarmer() end
        end
    end

    local function beginResume()
        local saved = Guard.Saved
        Guard.Token += 1
        local token = Guard.Token
        Guard.Mode = "back"
        Guard.BackText = nil
        task.spawn(function()
            local ok, err = pcall(resumeAll, saved, token)
            if not ok then warn("[n4th] Penjaga lanjut error: " .. tostring(err)) end
            if Guard.Token == token and Guard.Mode == "back" then
                Guard.Mode, Guard.Saved, Guard.BackText = "idle", nil, nil
            end
        end)
    end

    local function goAway()
        if not leaveWorld() then
            notify("Penjaga", "Gagal keluar world, aktivitas hanya dijeda", 5)
            Guard.Mode = "pause"
            return
        end
        task.wait(0.3)
        Guard.LeftFg = Refs.World and rawget(Refs.World, "fg")
        Guard.BackAt = os.clock() + Guard.BackSec
        Guard.Mode = Guard.AutoBack and "away" or "out"
        Guard.Status = "Keluar world"
    end

    -- Ada orang baru yang dicari masuk world
    local function trigger(fresh)
        Guard.Detected += #fresh
        notify("Penjaga", "Masuk world: " .. names(fresh), 6)
        Hook.send("penjaga", "Masuk world " .. worldName() .. ": " .. names(fresh))
        if not Guard.StopAll and not Guard.Leave then return end -- hanya peringatan
        -- simpan aktivitas (kalau sedang jalan balik, pakai catatan lama)
        if Guard.Mode ~= "back" and (anyRunning() or not Guard.Saved) then
            Guard.Saved = snapshot()
        end
        Guard.Token += 1
        stopAll()
        Guard.CalmAt = nil
        if Guard.Leave then
            goAway()
            if Guard.Mode == "away" then
                notify("Penjaga", "Keluar world. Masuk lagi dalam " .. Guard.BackSec .. " detik", 5)
                Hook.send("penjaga", "Keluar world, masuk lagi dalam " .. Guard.BackSec .. " detik")
            elseif Guard.Mode == "out" then
                notify("Penjaga", "Keluar world", 4)
            end
        else
            Guard.Mode = "pause"
        end
    end

    -- Setelah masuk world lagi: cek dulu, masih ada orangnya atau tidak
    local function checkAfterEnter()
        Auto.resetReach()
        pcall(findDropRefs)
        pcall(Auto.findTreeRefs)
        table.clear(DropFailUntil)
        task.wait(1.5) -- tunggu daftar pemain terisi
        local th = threatsOf(playersHere())
        if #th > 0 then
            for _, p in ipairs(th) do Guard.Alerted[p.id] = true end
            notify("Penjaga", "Masih ada " .. names(th) .. ". Keluar lagi", 5)
            goAway()
            return
        end
        notify("Penjaga", "World aman, lanjut aktivitas", 4)
        Hook.send("penjaga", "World " .. worldName() .. " aman, lanjut aktivitas")
        beginResume()
    end

    -- Staff yang online di server (bukan hanya di world ini)
    local lastScan, staffText = -10, "-"
    local function serverStaff()
        if os.clock() - lastScan < 3 then return staffText end
        lastScan = os.clock()
        local t = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local r = roleOf(plr.UserId)
                if r then t[#t + 1] = (plr.DisplayName or plr.Name) .. " (" .. r .. ")" end
            end
        end
        staffText = (#t > 0) and table.concat(t, ", ") or "tidak ada"
        return staffText
    end

    function Guard.tick(here)
        if not Guard.On then
            Guard.Status = "Mati"
            return
        end
        local now = os.clock()
        local mode = Guard.Mode

        -- ===== sedang di luar world =====
        if mode == "away" or mode == "out" then
            local fgNow = Refs.World and rawget(Refs.World, "fg")
            if Guard.LeftFg and fgNow ~= Guard.LeftFg then
                -- sudah masuk world lagi secara manual
                if mode == "away" and Guard.Saved and worldName() == Guard.Saved.world then
                    checkAfterEnter()
                else
                    Guard.Mode, Guard.Saved = "idle", nil
                end
                return
            end
            local name = Guard.Saved and Guard.Saved.world or ""
            if mode == "out" or name == "" then
                Guard.Status = "Sudah keluar world (lanjut otomatis mati)"
                return
            end
            local left = Guard.BackAt - now
            if left > 0 then
                Guard.Status = ("Di luar world. Masuk lagi ke %s dalam %d detik"):format(name, math.ceil(left))
                return
            end
            Guard.Status = "Masuk lagi ke " .. name .. "..."
            Guard.updateStatus({})
            local ok, err = enterWorld(name)
            if not ok then
                Guard.BackAt = os.clock() + math.max(15, Guard.BackSec)
                notify("Penjaga", "Gagal masuk " .. name .. ": " .. tostring(err) .. ". Dicoba lagi nanti", 5)
                return
            end
            checkAfterEnter()
            return
        end

        -- ===== di dalam world =====
        local present = {}
        for _, p in ipairs(here) do present[p.id] = true end
        for id in pairs(Guard.Alerted) do
            if not present[id] then Guard.Alerted[id] = nil end -- sudah pergi
        end
        local threats = threatsOf(here)
        local fresh = {}
        for _, p in ipairs(threats) do
            if not Guard.Alerted[p.id] then
                Guard.Alerted[p.id] = true
                fresh[#fresh + 1] = p
            end
        end
        if #fresh > 0 then
            trigger(fresh)
            if Guard.Mode == "away" or Guard.Mode == "out" then return end
        end

        if #threats > 0 then
            Guard.CalmAt = nil
            Guard.Status = (Guard.Mode == "pause" and "Dijeda. Ada: " or "Waspada. Ada: ") .. names(threats)
            return
        end

        if Guard.Mode == "pause" then
            Guard.CalmAt = Guard.CalmAt or now
            local wait = Guard.CalmSec - (now - Guard.CalmAt)
            if wait > 0 then
                Guard.Status = ("Mereka sudah pergi. Lanjut dalam %d detik"):format(math.ceil(wait))
                return
            end
            Guard.CalmAt = nil
            if Guard.AutoBack and Guard.Saved then
                notify("Penjaga", "Sudah aman, lanjut aktivitas", 4)
                beginResume()
            else
                Guard.Mode, Guard.Saved = "idle", nil
            end
            return
        end

        if Guard.Mode == "back" then
            Guard.Status = Guard.BackText or "Lanjut aktivitas..."
            return
        end
        Guard.Status = "Aman"
    end

    function Guard.updateStatus(here)
        local txt = table.concat({
            "Status: " .. Guard.Status .. (Refs.Others and "" or " (data pemain belum ketemu: tekan 'Hubungkan ke game')"),
            "Pemain di world: " .. ((#here == 0) and "tidak ada" or names(here, 6)),
            "Staff online di server: " .. serverStaff(),
            "Terdeteksi: " .. Guard.Detected .. " kali",
        }, "\n")
        if txt ~= Guard.LastTxt then
            Guard.LastTxt = txt
            if UI.GuardStatus then pcall(function() UI.GuardStatus:SetDesc(txt) end) end
        end
    end

    -- Nyalakan / matikan Penjaga
    function Guard.set(on)
        Guard.On = on
        Guard.Token += 1
        Auto.stopWalk()
        Guard.Mode, Guard.Saved, Guard.CalmAt, Guard.BackText = "idle", nil, nil, nil
        table.clear(Guard.Alerted)
        table.clear(Guard.Allow)
        if on then
            -- pemain biasa yang sudah ada sekarang diabaikan (teman / akun sendiri)
            for _, p in ipairs(playersHere()) do
                if not p.role then Guard.Allow[p.id] = true end
            end
        end
    end

    -- dipakai fitur lain (Auto Reconnect)
    Guard.snapshot = snapshot
    Guard.resumeActivities = function(saved, live) return resumeAll(saved, nil, live) end
    Guard.stopAll = stopAll
    Guard.enterWorld = enterWorld
    Guard.leaveWorld = leaveWorld
    Guard.worldName = worldName
    Guard.anyRunning = anyRunning
    function Guard.afterEnter()
        Auto.resetReach()
        pcall(findDropRefs)
        pcall(Auto.findTreeRefs)
        table.clear(DropFailUntil)
    end
    function Guard.resumeSaved(saved)
        Guard.Saved = saved
        beginResume()
    end

    function Guard.allowNow()
        local n = 0
        for _, p in ipairs(playersHere()) do
            if not p.role then
                Guard.Allow[p.id] = true
                n += 1
            end
        end
        return n
    end

    task.spawn(function()
        while alive() do
            if not Guard.On and Guard.Mode == "idle" then
                Guard.Status = "Mati"
                task.wait(2)
            else
                local here = (Guard.Mode ~= "away" and Guard.Mode ~= "out") and playersHere() or {}
                local ok, err = pcall(Guard.tick, here)
                if not ok then warn("[n4th] Penjaga error: " .. tostring(err)) end
                if UI.tabVisible("Penjaga") then Guard.updateStatus(here) end
                task.wait(Guard.On and 0.75 or 2)
            end
        end
    end)
end)() end

Config.add("Penjaga", Guard, { "On", "Who", "StopAll", "Leave", "AutoBack", "BackSec", "CalmSec" }, { On = true })

-- ===== TAB: PENJAGA =====
do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local GuardTab = makeTab("Penjaga", "eye", "aman")

    safe(function()
        UI.GuardStatus = GuardTab:Paragraph({ Title = "Status Penjaga", Desc = "Mati" })
    end)

    local gCtl = box(GuardTab, "Kontrol", true)
    local gAct = box(GuardTab, "Aksi saat terdeteksi", true)
    local gTime = box(GuardTab, "Waktu", false)
    local gMore = box(GuardTab, "Lainnya", false)

    safe(function()
        UI.GuardToggle = gCtl:Toggle({
            Title = "Aktifkan Penjaga",
            Desc = "Pantau Mod / Dev / pemain yang masuk world",
            Value = false,
            Callback = function(on) Guard.set(on) end,
        })
    end)

    safe(function()
        gCtl:Dropdown({
            Title = "Yang dideteksi",
            Desc = "Semua pemain: yang sudah ada saat dinyalakan diabaikan",
            Values = { "Staff (Mod/Dev)", "Semua pemain" },
            Value = Guard.Who,
            Callback = function(opt) Guard.Who = opt end,
        })
    end)

    safe(function()
        gAct:Toggle({
            Title = "Diam semua aktivitas",
            Desc = "Stop Auto Farm, Clear, Farmer & Auto Chat",
            Value = Guard.StopAll,
            Callback = function(on) Guard.StopAll = on end,
        })
    end)

    safe(function()
        gAct:Toggle({
            Title = "Keluar world",
            Desc = "Langsung keluar world saat terdeteksi",
            Value = Guard.Leave,
            Callback = function(on) Guard.Leave = on end,
        })
    end)

    safe(function()
        gAct:Toggle({
            Title = "Lanjut otomatis setelah aman",
            Desc = "Keluar world: masuk lagi, cek, lalu lanjut aktivitas sebelumnya",
            Value = Guard.AutoBack,
            Callback = function(on) Guard.AutoBack = on end,
        })
    end)

    addNumber(gTime, {
        Title = "Masuk world lagi setelah (detik)",
        Desc = "Untuk mode keluar world",
        Min = 20, Max = 600, Step = 5, Default = Guard.BackSec,
        Callback = function(v) Guard.BackSec = math.floor(v) end,
    })

    addNumber(gTime, {
        Title = "Tunggu aman (detik)",
        Desc = "Untuk mode diam: jeda setelah mereka pergi",
        Min = 2, Max = 60, Step = 1, Default = Guard.CalmSec,
        Callback = function(v) Guard.CalmSec = math.floor(v) end,
    })

    safe(function()
        gMore:Button({
            Title = "Abaikan pemain yang ada sekarang",
            Desc = "Untuk teman / akun sendiri (staff tetap dideteksi)",
            Callback = function()
                notify("Penjaga", Guard.allowNow() .. " pemain diabaikan", 3)
            end,
        })
    end)

    safe(function()
        gMore:Button({
            Title = "Batalkan tunggu / lanjut",
            Desc = "Hentikan proses keluar-masuk & lanjut otomatis",
            Callback = function()
                Guard.set(Guard.On)
                notify("Penjaga", "Dibatalkan", 3)
            end,
        })
    end)
end)() end

---------------------------------------------------------------------
---------------------------------------------------------------------
-- GROWSCAN: Floating Items & World Blocks (seperti Growscan 9000 di Growtopia)
---------------------------------------------------------------------
-- Cara kerja:
--   - Floating Items: daftar drop di world (data drop game), dijumlah per item.
--   - World Blocks: semua tile world dihitung per item (block depan + background).
--     Seed yang tertanam di block depan = pohon.
--   - Auto Scan: diulang tiap 2 detik. Hasil diurutkan dari jumlah terbanyak.
local Scan = {
    Auto = false,
    Layer = "Semua",      -- "Semua" | "Depan" | "Background"
    Filter = "",          -- cari nama item
    Every = 5,
    Limit = 60,           -- maksimal baris per daftar
    Last = nil,
}

do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local function fmtNum(n)
        local str = tostring(math.floor(n))
        local out = str:reverse():gsub("(%d%d%d)", "%1."):reverse()
        return (out:gsub("^%.", ""))
    end

    local function blockName(id)
        local it = ItemDB[id]
        local nm = itemName(id)
        if it and it.kind == "seed" then nm = nm .. " (pohon)" end
        return nm
    end

    -- Ubah hitungan {id = jumlah} jadi teks, urut dari terbanyak
    local function listText(counts, nameFn)
        local list = {}
        for id, n in pairs(counts) do list[#list + 1] = { id = id, n = n } end
        table.sort(list, function(a, b)
            if a.n ~= b.n then return a.n > b.n end
            return a.id < b.id
        end)
        local filter = string.lower(Scan.Filter or "")
        local lines, total = {}, 0
        for _, e in ipairs(list) do
            local name = nameFn(e.id)
            if filter == "" or string.find(string.lower(name), filter, 1, true) then
                total += 1
                if total <= Scan.Limit then
                    lines[#lines + 1] = name .. "  x" .. fmtNum(e.n)
                end
            end
        end
        if total > Scan.Limit then lines[#lines + 1] = ("... +%d item lain (pakai Cari item)"):format(total - Scan.Limit) end
        if #lines == 0 then lines[1] = (filter ~= "") and "Tidak ada yang cocok" or "Kosong" end
        return table.concat(lines, "\n"), total
    end

    local function scanFloating()
        local counts, total, piles = {}, 0, 0
        local list = Drops.list
        if type(list) ~= "table" then return nil end
        for _, d in pairs(list) do
            if type(d) == "table" and type(d.id) == "number" then
                local n = tonumber(d.n) or 1
                if n > 0 then
                    counts[d.id] = (counts[d.id] or 0) + n
                    total += n
                    piles += 1
                end
            end
        end
        return counts, total, piles
    end

    local function scanBlocks()
        local w = Refs.World
        if not w or type(w.fg) ~= "table" or type(w.w) ~= "number" then return nil end
        local grid, budget = w.fg, { next = os.clock() + 0.001 }
        local fgC, bgC, nf, nb = {}, {}, 0, 0
        local trees = {} -- [seed] = { r = siap, g = tumbuh, nxt = detik ke panen berikutnya }
        local st = workspace:GetServerTimeNow()
        local readyAt = Auto.treeReadyAt
        for y = 0, w.h - 1 do
            local rf = w.fg[y]
            local rb = w.bg and w.bg[y]
            for x = 0, w.w - 1 do
                local a = rf and rf[x] or 0
                if a ~= 0 then
                    fgC[a] = (fgC[a] or 0) + 1
                    nf += 1
                    local it = ItemDB[a]
                    if readyAt and it and it.kind == "seed" then
                        local ra = readyAt(x, y, a)
                        if ra then
                            local e = trees[a]
                            if not e then
                                e = { r = 0, g = 0 }
                                trees[a] = e
                            end
                            if st >= ra then
                                e.r += 1
                            else
                                e.g += 1
                                if not e.nxt or ra - st < e.nxt then e.nxt = ra - st end
                            end
                        end
                    end
                end
                local b = rb and rb[x] or 0
                if b ~= 0 then
                    bgC[b] = (bgC[b] or 0) + 1
                    nb += 1
                end
                Session.scanStep(budget, y * w.w + x + 1)
                if not alive() or Refs.World ~= w or w.fg ~= grid then return nil end
            end
        end
        return fgC, bgC, nf, nb, trees
    end

    local function waitText(sec)
        sec = math.max(0, math.floor(sec or 0))
        if sec >= 3600 then return ("%dj %dm"):format(sec // 3600, sec % 3600 // 60) end
        return ("%dm %dd"):format(sec // 60, sec % 60)
    end

    -- Daftar pohon: siap panen dulu, lalu yang paling cepat siap
    local function treeText(trees)
        local list, totalR, totalG = {}, 0, 0
        local filter = string.lower(Scan.Filter or "")
        for id, e in pairs(trees) do
            totalR += e.r
            totalG += e.g
            local name = itemName(id)
            if filter == "" or string.find(string.lower(name), filter, 1, true) then
                list[#list + 1] = { name = name, e = e }
            end
        end
        table.sort(list, function(a, b)
            if a.e.r ~= b.e.r then return a.e.r > b.e.r end
            return (a.e.nxt or math.huge) < (b.e.nxt or math.huge)
        end)
        local lines = {}
        for i, v in ipairs(list) do
            if i > Scan.Limit then
                lines[#lines + 1] = ("... +%d jenis lain"):format(#list - Scan.Limit)
                break
            end
            local line = ("%s: %d siap | %d tumbuh"):format(v.name, v.e.r, v.e.g)
            if v.e.nxt then line = line .. " (berikut " .. waitText(v.e.nxt) .. ")" end
            lines[#lines + 1] = line
        end
        if #lines == 0 then lines[1] = (filter ~= "") and "Tidak ada yang cocok" or "Tidak ada pohon" end
        return table.concat(lines, "\n"), totalR, totalG
    end

    local function setDesc(el, txt, key)
        if Scan[key] == txt then return end
        Scan[key] = txt
        if el then pcall(function() el:SetDesc(txt) end) end
    end

    function Scan.run()
        if Scan.Busy then return end
        Scan.Busy = true
        local w = Refs.World
        local fl, flTotal, piles = scanFloating()
        local fgC, bgC, nf, nb, trees = scanBlocks()
        local treeTxt, treeR, treeG = "Data pohon belum ketemu", nil, nil
        if trees then treeTxt, treeR, treeG = treeText(trees) end

        local floatText = fl and select(1, listText(fl, itemName)) or "Data drop belum ketemu. Tekan 'Hubungkan ke game'"
        local blockText = "Data world belum ketemu. Tekan 'Hubungkan ke game'"
        if fgC then
            local pick
            if Scan.Layer == "Depan" then
                pick = fgC
            elseif Scan.Layer == "Background" then
                pick = bgC
            else
                pick = {}
                for id, n in pairs(fgC) do pick[id] = (pick[id] or 0) + n end
                for id, n in pairs(bgC) do pick[id] = (pick[id] or 0) + n end
            end
            blockText = select(1, listText(pick, blockName))
        end

        local name = w and rawget(w, "name")
        local info = table.concat({
            "World: " .. ((type(name) == "string" and name ~= "") and name or "-")
                .. (w and type(w.w) == "number" and (" (" .. w.w .. "x" .. w.h .. ")") or ""),
            "Block depan: " .. (nf and fmtNum(nf) or "-") .. " | Background: " .. (nb and fmtNum(nb) or "-"),
            "Floating: " .. (flTotal and (fmtNum(flTotal) .. " item (" .. piles .. " tumpukan)") or "-"),
            "Pohon: " .. (treeR and (fmtNum(treeR) .. " siap panen | " .. fmtNum(treeG) .. " tumbuh") or "-"),
            "Scan terakhir: " .. os.date("%H:%M:%S"),
        }, "\n")

        setDesc(UI.ScanInfo, info, "_info")
        setDesc(UI.ScanFloat, floatText, "_float")
        setDesc(UI.ScanBlocks, blockText, "_blocks")
        setDesc(UI.ScanTrees, treeTxt, "_trees")
        Scan.Busy = false
    end

    task.spawn(function()
        local last = 0
        while alive() do
            if Scan.Auto and os.clock() - last >= Scan.Every then
                last = os.clock()
                pcall(Scan.run)
            end
            task.wait(0.5)
        end
    end)
end)() end

Config.add("Growscan", Scan, { "Auto", "Layer" })

-- ===== TAB: GROWSCAN =====
do (function() -- fungsi sendiri: variabel di dalam tidak ikut batas 200 local
    local ScanTab = makeTab("Growscan", "scan-search", "fitur")

    safe(function()
        UI.ScanInfo = ScanTab:Paragraph({ Title = "Info World", Desc = "Tekan Scan sekarang" })
    end)

    local sCtl = box(ScanTab, "Kontrol", true)
    local sFloat = box(ScanTab, "Floating Items", true)
    local sBlock = box(ScanTab, "World Blocks", false)
    local sTree = box(ScanTab, "Pohon (siap panen)", true)

    safe(function()
        sCtl:Toggle({
            Title = "Auto Scan",
            Desc = "Update otomatis tiap 2 detik",
            Value = Scan.Auto,
            Callback = function(on)
                Scan.Auto = on
                if on then task.spawn(Scan.run) end
            end,
        })
    end)

    safe(function()
        sCtl:Button({
            Title = "Scan sekarang",
            Callback = function() task.spawn(Scan.run) end,
        })
    end)

    safe(function()
        sCtl:Input({
            Title = "Cari item",
            Desc = "Saring nama item (kosongkan = semua)",
            Value = "",
            Placeholder = "contoh: seed",
            Callback = function(text)
                Scan.Filter = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                task.spawn(Scan.run)
            end,
        })
    end)

    safe(function()
        UI.ScanFloat = sFloat:Paragraph({ Title = "Daftar", Desc = "-" })
    end)

    safe(function()
        sBlock:Dropdown({
            Title = "Layer",
            Values = { "Semua", "Depan", "Background" },
            Value = Scan.Layer,
            Callback = function(opt)
                Scan.Layer = opt
                task.spawn(Scan.run)
            end,
        })
    end)

    safe(function()
        UI.ScanBlocks = sBlock:Paragraph({ Title = "Daftar", Desc = "-" })
    end)

    safe(function()
        UI.ScanTrees = sTree:Paragraph({ Title = "Daftar", Desc = "-" })
    end)
end)() end

---------------------------------------------------------------------
-- STATISTIK SESI
---------------------------------------------------------------------
-- Cara kerja:
--   - Saat execute (atau tombol Reset), angka awal dicatat.
--   - Tiap detik: angka sekarang - angka awal = hasil sesi. Dibagi lama sesi = per jam.
--   - Gems dibaca dari angka gems di HUD game (nilai di dalam fungsi addGems).
do (function()
    local function gemsNow()
        local g = Refs.Gems
        local f = g and rawget(g, "addGems")
        if type(f) ~= "function" then return nil end
        for _, v in pairs(getUpvalues(f)) do
            if type(v) == "number" then return v end
        end
        return nil
    end
    Stats.gemsNow = gemsNow

    local function fmt(n)
        local str = tostring(math.floor(n or 0))
        local neg = string.sub(str, 1, 1) == "-"
        if neg then str = string.sub(str, 2) end
        local out = str:reverse():gsub("(%d%d%d)", "%1."):reverse()
        out = out:gsub("^%.", "")
        return (neg and "-" or "") .. out
    end

    local function dur(sec)
        sec = math.max(0, math.floor(sec))
        return ("%dj %dm %dd"):format(sec // 3600, sec % 3600 // 60, sec % 60)
    end

    -- angka yang dihitung (semuanya naik terus selama script jalan)
    local function counters()
        return {
            broken = State.Broken, placed = State.Placed, collected = State.Collected,
            harvested = Farmer.Harvested, planted = Farmer.Planted,
        }
    end

    function Stats.reset()
        Stats.T0 = os.clock()
        Stats.Gems0 = gemsNow()
        Stats.Items = {}
        Stats.Base = counters()
    end
    Stats.Base = counters()

    function Stats.text()
        local hours = math.max((os.clock() - Stats.T0) / 3600, 1 / 3600)
        local now, base = counters(), Stats.Base
        local function line(label, key)
            local v = now[key] - (base[key] or 0)
            return ("%s: %s  (%s/jam)"):format(label, fmt(v), fmt(v / hours))
        end
        local g = gemsNow()
        if g and not Stats.Gems0 then Stats.Gems0 = g end
        local gemLine = "Gems: -"
        if g and Stats.Gems0 then
            local d = g - Stats.Gems0
            gemLine = ("Gems: %s  (%s%s, %s/jam)"):format(fmt(g), d >= 0 and "+" or "", fmt(d), fmt(d / hours))
        end
        -- 5 item terbanyak yang terkumpul
        local top = {}
        for id, n in pairs(Stats.Items) do top[#top + 1] = { id = id, n = n } end
        table.sort(top, function(a, b) return a.n > b.n end)
        local tops = {}
        for i = 1, math.min(5, #top) do tops[i] = itemName(top[i].id) .. " x" .. fmt(top[i].n) end
        return table.concat({
            "Lama sesi: " .. dur(os.clock() - Stats.T0),
            gemLine,
            line("Block pecah", "broken"),
            line("Block di-place", "placed"),
            line("Drop diambil", "collected"),
            line("Panen", "harvested"),
            line("Tanam", "planted"),
            "Item terbanyak: " .. ((#tops > 0) and table.concat(tops, ", ") or "-"),
        }, "\n")
    end

    task.spawn(function()
        local lastReport = os.clock()
        while alive() do
            local need = Hook.ReportMin > 0 or (UI.Window and not UI.Window.Closed and UI.tabVisible("Statistik"))
            if not need then
                lastReport = os.clock()
                task.wait(3)
                continue
            end
            local ok, txt = pcall(Stats.text)
            if ok and UI.StatsText and txt ~= Stats.Shown then
                Stats.Shown = txt
                pcall(function() UI.StatsText:SetDesc(txt) end)
            end
            -- laporan berkala ke Discord
            if Hook.ReportMin > 0 and os.clock() - lastReport >= Hook.ReportMin * 60 then
                lastReport = os.clock()
                if ok then Hook.send("report", "Laporan statistik\n```\n" .. txt .. "\n```") end
            elseif Hook.ReportMin <= 0 then
                lastReport = os.clock()
            end
            task.wait(Hook.ReportMin > 0 and 3 or 1)
        end
    end)
end)() end

-- ===== TAB: STATISTIK =====
do (function()
    local StatTab = makeTab("Statistik", "bar-chart-3", "fitur")

    safe(function()
        UI.StatsText = StatTab:Paragraph({ Title = "Sesi ini", Desc = "-" })
    end)

    safe(function()
        StatTab:Button({
            Title = "Reset statistik",
            Desc = "Mulai hitung dari nol",
            Callback = function()
                Stats.reset()
                notify("Statistik", "Direset", 2)
            end,
        })
    end)

    safe(function()
        StatTab:Button({
            Title = "Kirim ke Discord sekarang",
            Desc = "Perlu webhook di tab Discord",
            Callback = function()
                local ok, txt = pcall(Stats.text)
                if not (Hook.On and Hook.valid(Hook.Url)) then
                    notify("Statistik", "Aktifkan webhook Discord dulu", 3)
                elseif ok then
                    Hook.send("report", "Laporan statistik\n```\n" .. txt .. "\n```")
                    notify("Statistik", "Masuk antrian kirim", 2)
                end
            end,
        })
    end)
end)() end

---------------------------------------------------------------------
-- TAS: auto recycle item sampah & auto convert lock
---------------------------------------------------------------------
-- Cara kerja (sama seperti tombol di inventori game):
--   Recycle : hapus dari inventori lalu World.call("Recycle", id, jumlah)
--   Convert : 100 World Lock -> 1 Diamond Lock, 100 Diamond Lock -> 1 Blue Gem Lock
--             lewat World.call("ConvertLock", dari, ke)
-- Tool & lock tidak bisa dipilih untuk recycle (supaya tidak terbuang tidak sengaja).
local Bag = {
    TrashOn = false,
    TrashList = {},    -- daftar id item yang di-recycle
    TrashAt = 150,     -- recycle kalau jumlahnya sudah segini
    Keep = 0,          -- sisakan sebanyak ini
    LockOn = false,
    Recycled = 0,
    Converted = 0,
    Status = "-",
}

do (function()
    local LOCK_IDS = { [242] = true, [1796] = true, [7188] = true }
    local LOCK_STEPS = {
        { from = 242, to = 1796, name = "Diamond Lock" },
        { from = 1796, to = 7188, name = "Blue Gem Lock" },
    }

    local function worldCall(...)
        local w = Refs.World
        local f = w and rawget(w, "call")
        if type(f) ~= "function" then return false end
        return pcall(f, ...)
    end

    local function trashable(id)
        local it = ItemDB[id]
        return it ~= nil and it.kind ~= "tool" and not LOCK_IDS[id]
    end

    function Bag.recycle(id, n)
        if not Refs.Inv or n <= 0 or not trashable(id) then return false end
        n = math.min(n, invCount(id))
        if n <= 0 then return false end
        pcall(function() Refs.Inv:remove(id, n) end)
        local ok = worldCall("Recycle", id, n)
        if ok then
            Bag.Recycled += n
            Bag.Status = ("Recycle %s x%d"):format(itemName(id), n)
        end
        return ok
    end

    -- sama seperti cek tombol convert di game (muat atau tidak)
    local function convertLock(step)
        local inv = Refs.Inv
        if not inv or invCount(step.from) < 100 then return false end
        local okU, used = pcall(function() return inv:used() end)
        local okC, cap = pcall(function() return inv.capacity end)
        if invCount(step.to) + 1 > 200 then return false end
        if invCount(step.to) == 0 and invCount(step.from) ~= 100 and okU and okC
            and type(used) == "number" and type(cap) == "number" and used >= cap then
            return false
        end
        pcall(function()
            inv:remove(step.from, 100)
            inv:add(step.to, 1)
        end)
        local ok = worldCall("ConvertLock", step.from, step.to)
        if ok then
            Bag.Converted += 1
            Bag.Status = "Convert ke " .. step.name
        end
        return ok
    end

    function Bag.tick()
        if AutoDrop.Busy then return end
        if Bag.TrashOn then
            for _, id in ipairs(Bag.TrashList) do
                local n = invCount(id)
                if n >= Bag.TrashAt and n > Bag.Keep then
                    Bag.recycle(id, n - Bag.Keep)
                    task.wait(0.5)
                end
            end
        end
        if Bag.LockOn then
            for _, step in ipairs(LOCK_STEPS) do
                if convertLock(step) then task.wait(0.5) end
            end
        end
    end

    -- label dropdown: item di inventori yang boleh di-recycle
    function Bag.labels()
        local out, seen = {}, {}
        if Refs.Inv then
            for _, slot in ipairs(Refs.Inv.slots) do
                local id = slot.id
                if id and not seen[id] and (slot.n or 0) > 0 and trashable(id) then
                    seen[id] = true
                    out[#out + 1] = { id = id, label = ("%s [%d]"):format(itemName(id), id) }
                end
            end
        end
        -- item yang sudah dipilih tetap tampil walau sedang habis
        for _, id in ipairs(Bag.TrashList) do
            if not seen[id] then
                seen[id] = true
                out[#out + 1] = { id = id, label = ("%s [%d]"):format(itemName(id), id) }
            end
        end
        table.sort(out, function(a, b) return a.id < b.id end)
        local labels, picked = {}, {}
        for _, e in ipairs(out) do
            labels[#labels + 1] = e.label
            if table.find(Bag.TrashList, e.id) then picked[#picked + 1] = e.label end
        end
        return labels, picked
    end

    task.spawn(function()
        while alive() do
            pcall(Bag.tick)
            if UI.BagStatus then
                local txt = ("Status: %s\nDi-recycle: %d item | Convert lock: %d kali\nItem dipilih: %d"):format(
                    Bag.Status, Bag.Recycled, Bag.Converted, #Bag.TrashList)
                if txt ~= Bag.Shown then
                    Bag.Shown = txt
                    pcall(function() UI.BagStatus:SetDesc(txt) end)
                end
            end
            task.wait(3)
        end
    end)
end)() end

Config.add("Tas", Bag, { "TrashOn", "TrashList", "TrashAt", "Keep", "LockOn" })

-- ===== TAB: TAS =====
do (function()
    local BagTab = makeTab("Tas", "backpack", "fitur")

    safe(function()
        UI.BagStatus = BagTab:Paragraph({ Title = "Status", Desc = "-" })
    end)

    local bTrash = box(BagTab, "Auto Recycle (buang item)", true)
    local bLock = box(BagTab, "Auto Convert Lock", false)

    safe(function()
        bTrash:Toggle({
            Title = "Auto Recycle",
            Desc = "Item yang dipilih di-recycle otomatis",
            Value = Bag.TrashOn,
            Callback = function(on) Bag.TrashOn = on end,
        })
    end)

    safe(function()
        local labels, picked = Bag.labels()
        UI.TrashDropdown = bTrash:Dropdown({
            Title = "Item yang di-recycle",
            Desc = "Bisa pilih banyak. Tool & lock tidak ditampilkan",
            Values = (#labels > 0) and labels or { "(inventori belum terbaca)" },
            Value = picked,
            Multi = true,
            AllowNone = true,
            Callback = function(opts)
                local list = {}
                for _, label in ipairs(type(opts) == "table" and opts or { opts }) do
                    local id = tonumber(string.match(tostring(label), "%[(%d+)%]$"))
                    if id then list[#list + 1] = id end
                end
                Bag.TrashList = list
            end,
        })
    end)

    -- dipanggil saat inventori berubah
    local lastSig = nil
    UI.TrashRefresh = function(force)
        if not force and not UI.tabVisible("Tas") then return end
        local labels, picked = Bag.labels()
        local sig = table.concat(labels, "|")
        if not force and sig == lastSig then return end
        lastSig = sig
        if not UI.TrashDropdown then return end
        UI.exec(function() UI.TrashDropdown:Refresh((#labels > 0) and labels or { "(inventori kosong)" }) end)
        if #picked > 0 then UI.exec(function() UI.TrashDropdown:Select(picked) end) end
    end

    addNumber(bTrash, {
        Title = "Recycle kalau jumlah >=",
        Desc = "200 = hanya saat penuh 1 slot",
        Min = 1, Max = 200, Step = 1, Default = Bag.TrashAt,
        Callback = function(v) Bag.TrashAt = math.floor(v) end,
    })

    addNumber(bTrash, {
        Title = "Sisakan",
        Desc = "Jumlah yang tidak ikut di-recycle",
        Min = 0, Max = 199, Step = 1, Default = Bag.Keep,
        Callback = function(v) Bag.Keep = math.floor(v) end,
    })

    safe(function()
        bTrash:Button({
            Title = "Refresh daftar item",
            Callback = function() UI.later("trash", function() UI.TrashRefresh(true) end) end,
        })
    end)

    safe(function()
        bLock:Toggle({
            Title = "Auto Convert Lock",
            Desc = "100 WL -> 1 DL, 100 DL -> 1 BGL (sama seperti game)",
            Value = Bag.LockOn,
            Callback = function(on) Bag.LockOn = on end,
        })
    end)
end)() end

---------------------------------------------------------------------
-- ===== TAB: LAHAN (bangun farm world) =====
do (function()
    local LTab = makeTab("Lahan", "layout-grid", "farm")

    safe(function()
        UI.LahanStatus = LTab:Paragraph({ Title = "Status Lahan", Desc = "-" })
    end)

    local lCtl = box(LTab, "Bangun Lahan", true)
    local lShape = box(LTab, "Bentuk lahan", true)

    safe(function()
        UI.BuildToggle = lCtl:Toggle({
            Title = "Bangun Lahan",
            Desc = "Gali dulu dari permukaan sampai bawah, lalu pasang baris naik sampai atas (baris jadi jembatan). Block habis: produksi 1 baris",
            Value = false,
            Callback = function(on)
                if on then Build.start() elseif Build.Running then Build.stop() end
            end,
        })
    end)

    safe(function()
        UI.BuildBlockDropdown = lCtl:Dropdown({
            Title = "Block lahan",
            Desc = "Block padat dari inventori",
            Values = { "(memuat...)" },
            Callback = function(opt)
                local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
                if id then Build.BlockId = id end
            end,
        })
    end)

    local function num(text, def)
        local v = tonumber(tostring(text or ""):match("%-?%d+"))
        return v or def
    end

    safe(function()
        lShape:Input({
            Title = "X awal",
            Desc = "Kolom paling kiri",
            Value = tostring(Land.X0),
            Placeholder = "0",
            Callback = function(t) Land.X0 = math.max(0, num(t, Land.X0)) end,
        })
    end)

    safe(function()
        lShape:Input({
            Title = "X akhir",
            Desc = "Kolom paling kanan (lebih dari lebar world = sampai ujung)",
            Value = tostring(Land.X1),
            Placeholder = "99",
            Callback = function(t) Land.X1 = math.max(0, num(t, Land.X1)) end,
        })
    end)

    safe(function()
        lShape:Input({
            Title = "Y baris atas",
            Desc = "Baris block paling atas. Baris di bawahnya otomatis sampai di atas bedrock (tanah digali)",
            Value = tostring(Land.Y0),
            Placeholder = "2",
            Callback = function(t) Land.Y0 = math.max(1, num(t, Land.Y0)) end,
        })
    end)

    safe(function()
        lShape:Button({
            Title = "Pakai posisi karakter sebagai pojok kiri-atas",
            Desc = "Berdiri di atas block pertama baris paling atas, lalu tekan (tangga kiri di sebelah kirinya)",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Lahan", "Kamu belum masuk world", 3)
                    return
                end
                -- block yang dipijak = block pertama baris atas, kolom tangga kiri di sebelah kirinya
                Land.X0, Land.Y0 = math.max(0, x - 1), y + 1
                notify("Lahan", ("X awal %d, Y baris atas %d"):format(Land.X0, Land.Y0), 4)
            end,
        })
    end)

    safe(function()
        lCtl:Toggle({
            Title = "Lanjut Pabrik setelah selesai",
            Value = Build.ThenPabrik,
            Callback = function(on) Build.ThenPabrik = on end,
        })
    end)

    safe(function()
        lCtl:Button({
            Title = "Posisi break produksi = posisi karakter",
            Desc = "Berdiri di tempat break lalu tekan. Tekan lagi di tempat yang sama = kembali otomatis",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Lahan", "Kamu belum masuk world", 3)
                    return
                end
                if Build.BreakX == x and Build.BreakY == y then
                    Build.BreakX, Build.BreakY = -1, -1
                    notify("Lahan", "Posisi break produksi: otomatis", 3)
                else
                    Build.BreakX, Build.BreakY = x, y
                    if next(Build.Tiles) == nil then Build.Tiles["1,0"] = true end
                    notify("Lahan", ("Posisi break produksi (%d,%d)"):format(x, y), 3)
                end
            end,
        })
    end)

    safe(function()
        lCtl:Button({
            Title = "Pilih tile break produksi (Grid)",
            Desc = "Grid terbuka dalam mode Lahan (terpisah dari Auto Farm & Pabrik)",
            Callback = function()
                if UI.setGridMode then UI.setGridMode("lahan") end
                if UI.GridGui then UI.GridGui.Enabled = true end
            end,
        })
    end)

    task.spawn(function()
        while alive() do
            if not Build.Running and (Window.Closed or not LTab.Selected) then task.wait(1) continue end
            local txt
            if Refs.World then
                local info = Build.Info
                if not (Build.Running and info) then
                    local key = tostring(Build.BlockId) .. "|" .. Land.X0 .. "|" .. Land.X1 .. "|" .. Land.Y0
                    if not info or not Build.InfoAt or os.clock() - Build.InfoAt > 5 or Build.InfoKey ~= key then
                        info = Auto.landInfo(Build.BlockId)
                        Build.Info, Build.InfoAt, Build.InfoKey = info, os.clock(), key
                    end
                end
                local rows = Auto.landRows()
                local have = Build.BlockId and invCount(Build.BlockId) or 0
                local seed = Auto.seedOfBlock(Build.BlockId)
                txt = table.concat({
                    "Status   : " .. (Build.Running and "JALAN" or "BERHENTI") .. " - " .. Build.Phase,
                    (#rows > 0) and ("Bentuk   : %d baris (y %d-%d), x %d-%d, 1 kosong per baris, tangga kiri & kanan"):format(
                        #rows, rows[1], rows[#rows], math.min(Land.X0, Land.X1), math.max(Land.X0, Land.X1))
                        or "Bentuk   : tidak ada baris yang muat (Y atas terlalu bawah)",
                    ("Block    : %s | punya %d | butuh %d%s"):format(Build.BlockId and itemName(Build.BlockId) or "-",
                        have, info.need, (info.need > have) and (" (kurang " .. (info.need - have) .. ")") or " (cukup)"),
                    ("Terpasang: %d / %d%s"):format(info.done, info.total,
                        info.blocked > 0 and (" | terhalang block lain: " .. info.blocked) or ""),
                    (info.carve > 0) and ("Gali     : sisa " .. info.carve .. " tile (celah, tangga, background)")
                        or "Gali     : selesai",
                    "Seed block: " .. (seed and (itemName(seed) .. " x" .. invCount(seed)) or "-"),
                    ("Produksi : panen %d | tanam %d"):format(Build.Harvested, Build.Planted),
                    "Break    : " .. ((Build.BreakX >= 0 and next(Build.Tiles) ~= nil)
                        and ("(" .. Build.BreakX .. "," .. Build.BreakY .. ") | grid lahan")
                        or "otomatis (kanan karakter, dekat ujung baris)"),
                    "Aksi     : " .. Build.Status,
                }, "\n")
            else
                txt = "Data world belum ketemu"
            end
            if UI.LahanStatus and txt ~= Build.Shown then
                Build.Shown = txt
                pcall(function() UI.LahanStatus:SetDesc(txt) end)
            end
            -- tombol START di Grid (mode lahan)
            if UI.GridMode == "lahan" and UI.GridStart then
                UI.GridStart.Text = I18N.T(Build.Running and "STOP LAHAN" or "START LAHAN")
                UI.GridStart.BackgroundColor3 = Build.Running and Color3.fromRGB(200, 60, 60) or Color3.fromRGB(46, 160, 90)
            end
            task.wait(1)
        end
    end)
end)() end

-- ===== TAB: PABRIK =====
do (function()
    local PTab = makeTab("Pabrik", "factory", "farm")

    safe(function()
        UI.PabrikStatus = PTab:Paragraph({ Title = "Status Pabrik", Desc = "-" })
    end)

    local pCtl = box(PTab, "Kontrol", true)
    local pBreak = box(PTab, "Posisi & tile break", true)
    local pDrop = box(PTab, "Drop seed", true)

    safe(function()
        UI.PabrikToggle = pCtl:Toggle({
            Title = "Jalankan Pabrik",
            Desc = "Break -> tanam -> panen -> break lagi, seed lebihan di-drop",
            Value = false,
            Callback = function(on)
                if on then Pabrik.start() elseif Pabrik.Running then Pabrik.stop() end
            end,
        })
    end)

    safe(function()
        UI.PabrikSeedDropdown = pCtl:Dropdown({
            Title = "Seed pabrik",
            Desc = "Block-nya otomatis (contoh: Dirt Seed -> Dirt)",
            Values = { "(memuat...)" },
            Callback = function(opt)
                local id = tonumber(string.match(opt or "", "%[(%d+)%]$"))
                if id then Pabrik.SeedId = id end
            end,
        })
    end)

    safe(function()
        pCtl:Toggle({
            Title = "Tanam di seluruh world",
            Desc = "Mati = hanya di lahan (tab Lahan)",
            Value = Pabrik.WholeWorld,
            Callback = function(on) Pabrik.WholeWorld = on end,
        })
    end)

    safe(function()
        pBreak:Button({
            Title = "Pakai posisi sekarang untuk break",
            Desc = "Berdiri di tempat break, lalu tekan",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Pabrik", "Kamu belum masuk world", 3)
                    return
                end
                Pabrik.BreakX, Pabrik.BreakY = x, y
                notify("Pabrik", ("Posisi break (%d,%d)"):format(x, y), 3)
            end,
        })
    end)

    safe(function()
        pBreak:Button({
            Title = "Pilih tile break (Grid)",
            Desc = "Grid terbuka dalam mode Pabrik (terpisah dari tile Auto Farm)",
            Callback = function()
                if UI.setGridMode then UI.setGridMode("pabrik") end
                if UI.GridGui then UI.GridGui.Enabled = true end
            end,
        })
    end)

    safe(function()
        pDrop:Toggle({
            Title = "Auto drop seed",
            Desc = "Ke titik drop (tab Titik Drop)",
            Value = Pabrik.Drop,
            Callback = function(on) Pabrik.Drop = on end,
        })
    end)

    addNumber(pDrop, {
        Title = "Sisakan seed",
        Desc = "Untuk ditanam lagi",
        Min = 0, Max = 199, Step = 1, Default = Pabrik.Keep,
        Callback = function(v) Pabrik.Keep = math.floor(v) end,
    })

    addNumber(pDrop, {
        Title = "Drop kalau seed sudah",
        Desc = "Contoh 200 & sisakan 50 = drop 150",
        Min = 2, Max = 200, Step = 1, Default = Pabrik.DropAt,
        Callback = function(v) Pabrik.DropAt = math.floor(v) end,
    })

    local function countKeys(t)
        local n = 0
        for _ in pairs(t) do n += 1 end
        return n
    end

    task.spawn(function()
        while alive() do
            local seed, block = Pabrik.SeedId, Auto.blockOfSeed(Pabrik.SeedId)
            local name, door = Auto.parseDropTarget()
            local dropAt = (name ~= "" and name or "world ini") .. (door and (" pintu " .. door) or "")
                .. (Pabrik.DropX >= 0 and (" (" .. Pabrik.DropX .. "," .. Pabrik.DropY .. ")") or "")
            local txt = table.concat({
                "Status : " .. (Pabrik.Running and ("JALAN - fase " .. tostring(Pabrik.Phase or "-")) or "BERHENTI"),
                ("Seed   : %s x%d | block %s x%d"):format(seed and itemName(seed) or "-", seed and invCount(seed) or 0,
                    block and itemName(block) or "-", block and invCount(block) or 0),
                ("Break  : %s | tile %d"):format(Pabrik.BreakX >= 0 and ("(" .. Pabrik.BreakX .. "," .. Pabrik.BreakY .. ")")
                    or "belum diatur", countKeys(Pabrik.Tiles)),
                ("Drop   : %s | sisakan %d, drop saat >= %d"):format(Pabrik.Drop and dropAt or "mati", Pabrik.Keep, Pabrik.DropAt),
                ("Hasil  : panen %d | tanam %d | di-drop %d"):format(Pabrik.Harvested, Pabrik.Planted, Pabrik.Dropped),
                "Aksi   : " .. Pabrik.Status,
            }, "\n")
            if UI.PabrikStatus and txt ~= Pabrik.Shown then
                Pabrik.Shown = txt
                pcall(function() UI.PabrikStatus:SetDesc(txt) end)
            end
            -- tombol START di Grid (mode pabrik)
            if UI.GridMode == "pabrik" and UI.GridStart then
                UI.GridStart.Text = I18N.T(Pabrik.Running and "STOP PABRIK" or "START PABRIK")
                UI.GridStart.BackgroundColor3 = Pabrik.Running and Color3.fromRGB(200, 60, 60) or Color3.fromRGB(46, 160, 90)
            end
            task.wait(1)
        end
    end)
end)() end

---------------------------------------------------------------------
-- AUTO RECONNECT
---------------------------------------------------------------------
-- Cara kerja:
--   Terlempar dari world (event WorldClosed dari server):
--     catat aktivitas -> tunggu -> masuk world yang sama lagi -> lanjut aktivitas.
--   Disconnect dari server Roblox (layar error muncul):
--     catat aktivitas ke file -> teleport ulang ke game dengan data world
--     (game otomatis masuk world itu) -> script jalan lagi -> lanjut aktivitas.
--     Supaya script jalan lagi setelah teleport: isi URL script (queue_on_teleport)
--     atau taruh script di folder autoexec executor.
local Rejoin = {
    On = false,
    World = true,       -- masuk lagi kalau terlempar dari world
    Server = true,      -- rejoin kalau disconnect dari server
    DelaySec = 5,
    ScriptUrl = "https://raw.githubusercontent.com/ZennJxD/n4th/refs/heads/main/n4th",
    Keep = false,       -- selalu kembali ke world tujuan kalau berada di luar world
    Target = "",        -- world tujuan (kosong = world terakhir)
    LastWorld = "",     -- world terakhir yang dimasuki
    Last = nil,         -- catatan aktivitas terakhir
    LastAt = 0,
    Busy = false,
    Count = 0,
    Status = "-",
}

do (function()
    local HttpService = game:GetService("HttpService")
    local TeleportService = game:GetService("TeleportService")
    local GuiService = game:GetService("GuiService")
    local canFile = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
    local PENDING = "n4thOpus/rejoin_" .. tostring(LocalPlayer.UserId) .. ".json"

    -- catat aktivitas selagi masih jalan
    task.spawn(function()
        while alive() do
            local now = os.clock()
            local wn = Guard.worldName and Guard.worldName() or ""
            if wn ~= "" and not Pabrik.Traveling then Rejoin.LastWorld = wn end
            if Guard.anyRunning and Guard.anyRunning() and Guard.Mode == "idle" then
                Rejoin.Last = Guard.snapshot()
                Rejoin.LastAt = now
            elseif now - Rejoin.LastAt > 3 and Guard.Mode == "idle" and wn ~= "" then
                -- masih di world tapi aktivitas dihentikan sendiri: jangan dilanjutkan
                Rejoin.Last = nil
            end
            task.wait(1)
        end
    end)

    local function resume(saved, reason)
        Guard.afterEnter()
        Rejoin.Count += 1
        Rejoin.Status = "Masuk lagi berhasil, lanjut aktivitas"
        notify("Auto Reconnect", reason .. ": lanjut aktivitas", 4)
        Hook.send("rejoin", reason .. " ke " .. tostring(saved.world) .. ", aktivitas dilanjutkan")
        Guard.resumeSaved(saved)
    end

    -- ===== terlempar dari world =====
    local function onWorldClosed(msg)
        if not (Rejoin.On and Rejoin.World) or Rejoin.Busy or Pabrik.Traveling then return end
        if Guard.Mode == "away" or Guard.Mode == "out" then return end -- Penjaga yang keluar
        local saved = Rejoin.Last
        if not saved or saved.world == "" or os.clock() - Rejoin.LastAt > 10 then return end
        Rejoin.Busy = true
        task.spawn(function()
            Guard.stopAll()
            local text = tostring(msg or ""):gsub("`.", "")
            Rejoin.Status = "Terlempar dari " .. saved.world .. ". Masuk lagi..."
            Hook.send("rejoin", "Terlempar dari world " .. saved.world .. (text ~= "" and (" (" .. text .. ")") or ""))
            task.wait(Rejoin.DelaySec + 1.5) -- tunggu animasi pintu selesai
            for try = 1, 3 do
                if not (alive() and Rejoin.On) then break end
                local ok, err = Guard.enterWorld(saved.world)
                if ok then
                    task.wait(1.5)
                    resume(saved, "Masuk lagi")
                    Rejoin.Busy = false
                    return
                end
                Rejoin.Status = ("Gagal masuk (%d/3): %s"):format(try, tostring(err))
                task.wait(10)
            end
            Rejoin.Status = "Gagal masuk lagi ke " .. saved.world
            notify("Auto Reconnect", Rejoin.Status, 5)
            Hook.send("rejoin", Rejoin.Status)
            Rejoin.Busy = false
        end)
    end

    -- game v1159+: WorldClosed lewat paket Net (ByteNet), bukan RemoteEvent bernama lagi.
    -- Net.on hanya MENDENGAR (tidak kirim apa pun ke server). Listener tidak bisa dilepas,
    -- jadi dicek alive() supaya script lama yang sudah ditutup tidak ikut jalan.
    local closedHooked = false
    if NetOk and type(Net) == "table" and type(Net.on) == "function"
        and type(Net.EVENTS) == "table" and Net.EVENTS.WorldClosed then
        closedHooked = pcall(Net.on, "WorldClosed", function(msg)
            if alive() then onWorldClosed(msg) end
        end, function()
            local w = Refs.World
            return w and rawget(w, "name") or ""
        end)
    end
    if not closedHooked then
        local closed = WorldRemotes and WorldRemotes:FindFirstChild("WorldClosed")
        if closed and closed:IsA("RemoteEvent") then
            table.insert(Connections, closed.OnClientEvent:Connect(function(msg)
                if alive() then onWorldClosed(msg) end
            end))
        end
    end

    -- ===== rejoin manual & selalu kembali ke world =====
    -- Cara kerja:
    --   Rejoin manual : catat aktivitas -> keluar world -> masuk lagi -> lanjut aktivitas.
    --   Selalu kembali: tiap 2 detik cek, kalau kamu di luar world (layar pilih world)
    --                   lebih lama dari jeda -> masuk ke world tujuan -> lanjut aktivitas.
    function Rejoin.targetWorld()
        local t = tostring(Rejoin.Target or ""):upper():gsub("[^A-Z0-9]", "")
        if t ~= "" then return t end
        return Rejoin.LastWorld or ""
    end

    local function enterAndResume(world, saved, reason)
        for try = 1, 3 do
            if not alive() then return false end
            local ok, err = Guard.enterWorld(world)
            if ok then
                task.wait(1.5)
                if saved and saved.world == world then
                    resume(saved, reason)
                else
                    Guard.afterEnter()
                    Rejoin.Count += 1
                    Rejoin.Status = reason .. " ke " .. world .. " berhasil"
                    Hook.send("rejoin", reason .. " ke " .. world)
                end
                return true
            end
            Rejoin.Status = ("Gagal masuk %s (%d/3): %s"):format(world, try, tostring(err))
            task.wait(8)
        end
        notify("Auto Rejoin", "Gagal masuk " .. world, 5)
        Hook.send("rejoin", "Gagal masuk " .. world)
        return false
    end

    function Rejoin.now()
        if Rejoin.Busy then
            notify("Auto Rejoin", "Sedang proses masuk world, tunggu dulu", 3)
            return
        end
        local world = Rejoin.targetWorld()
        if world == "" then
            notify("Auto Rejoin", "World tujuan belum ada. Isi 'World tujuan' atau masuk world dulu", 4)
            return
        end
        Rejoin.Busy = true
        task.spawn(function()
            local saved = nil
            if Guard.worldName() ~= "" then
                if Guard.anyRunning() then saved = Guard.snapshot() end
                Guard.stopAll()
                Rejoin.Status = "Keluar world..."
                if not Guard.leaveWorld() then
                    Rejoin.Status = "Gagal keluar world"
                    notify("Auto Rejoin", Rejoin.Status, 4)
                    Rejoin.Busy = false
                    return
                end
                task.wait(math.max(2, Rejoin.DelaySec))
            end
            if saved and saved.world ~= world then saved = nil end -- world lain: aktivitas tidak dilanjutkan
            Rejoin.Status = "Masuk ke " .. world .. "..."
            enterAndResume(world, saved, "Rejoin")
            Rejoin.Busy = false
        end)
    end

    task.spawn(function()
        local outSince = nil
        while alive() do
            task.wait(2)
            local out = Guard.worldName() == ""
            local free = Rejoin.On and Rejoin.Keep and not Rejoin.Busy and not Rejoin.Leaving and not Pabrik.Traveling
                and Guard.Mode == "idle"
            if not (out and free) then
                outSince = nil
            else
                outSince = outSince or os.clock()
                local world = Rejoin.targetWorld()
                if world ~= "" and os.clock() - outSince >= Rejoin.DelaySec then
                    outSince = nil
                    Rejoin.Busy = true
                    local saved = Rejoin.Last
                    if saved and (saved.world ~= world or os.clock() - Rejoin.LastAt > 600) then saved = nil end
                    Rejoin.Status = "Di luar world, masuk ke " .. world .. "..."
                    enterAndResume(world, saved, "Kembali otomatis")
                    Rejoin.Busy = false
                end
            end
        end
    end)

    -- ===== disconnect dari server =====
    local function queueScript()
        local q = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
        local url = tostring(Rejoin.ScriptUrl or "")
        if type(q) == "function" and string.sub(url, 1, 8) == "https://" then
            return pcall(q, ("loadstring(game:HttpGet(%q))()"):format(url))
        end
        return false
    end

    local function onDisconnect(msg)
        if not (Rejoin.On and Rejoin.Server) or Rejoin.Leaving then return end
        Rejoin.Leaving = true
        local saved = Rejoin.Last or (Guard.anyRunning() and Guard.snapshot()) or nil
        local world = saved and saved.world or Guard.worldName()
        if canFile and saved then
            local data = {
                world = saved.world, farm = saved.farm, clear = saved.clear, farmer = saved.farmer,
                clearTarget = saved.clearTarget,
                pabrik = saved.pabrik, build = saved.build,
                tx = saved.tx, ty = saved.ty, at = os.time(),
            }
            pcall(function() writefile(PENDING, HttpService:JSONEncode(data)) end)
        end
        local queued = queueScript()
        Rejoin.Status = "Disconnect: rejoin..." .. (queued and "" or " (script tidak di-queue)")
        Hook.send("rejoin", "Disconnect dari server (" .. tostring(msg) .. "). Rejoin ke " .. (world ~= "" and world or "game"))
        task.spawn(function()
            task.wait(Rejoin.DelaySec)
            while alive() do
                pcall(function()
                    TeleportService:Teleport(game.PlaceId, LocalPlayer, (world ~= "") and { world = world } or nil)
                end)
                task.wait(15) -- belum pindah: coba lagi
            end
        end)
    end

    pcall(function()
        table.insert(Connections, GuiService.ErrorMessageChanged:Connect(function(msg)
            if alive() and type(msg) == "string" and msg ~= "" then onDisconnect(msg) end
        end))
    end)

    -- ===== setelah execute: lanjutkan dari catatan rejoin =====
    function Rejoin.startup(reconnectFn)
        if not canFile then return end
        local okE, has = pcall(isfile, PENDING)
        if not okE or not has then return end
        local okR, raw = pcall(readfile, PENDING)
        if type(delfile) == "function" then pcall(delfile, PENDING) end
        if not okR or type(raw) ~= "string" then return end
        local okD, saved = pcall(HttpService.JSONDecode, HttpService, raw)
        if not okD or type(saved) ~= "table" or type(saved.world) ~= "string" or saved.world == "" then return end
        if os.time() - (tonumber(saved.at) or 0) > 15 * 60 then return end -- terlalu lama
        Rejoin.Busy = true
        Rejoin.Status = "Rejoin: menunggu masuk " .. saved.world
        -- tunggu game masuk world (lewat data teleport); kalau tidak, masuk sendiri
        local t0 = os.clock()
        local tried = false
        while alive() and os.clock() - t0 < 60 do
            if Refs.World and Guard.worldName() == saved.world and Auto.here() then break end
            if not Refs.World then pcall(reconnectFn) end
            if Refs.World and not tried and os.clock() - t0 > 12 then
                tried = true
                Guard.enterWorld(saved.world)
            end
            task.wait(2)
        end
        if alive() and Guard.worldName() == saved.world then
            pcall(reconnectFn)
            task.wait(1)
            resume(saved, "Rejoin server")
        else
            Rejoin.Status = "Rejoin: gagal masuk " .. saved.world
            Hook.send("rejoin", Rejoin.Status)
        end
        Rejoin.Busy = false
    end
end)() end

Config.add("Reconnect", Rejoin, { "On", "World", "Server", "DelaySec", "ScriptUrl", "Keep", "Target" })
Config.add("Discord", Hook, { "On", "Url", "Penjaga", "Stop", "Full", "Rejoin", "Pabrik", "ReportMin" })

-- ===== TAB: TITIK DROP (dipakai Pabrik, Farmer, Auto Farm) =====
do (function()
    local DTab = makeTab("Titik Drop", "map-pin", "farm")

    safe(function()
        UI.DropPointStatus = DTab:Paragraph({ Title = "Titik Drop", Desc = "-" })
    end)

    local dBox = box(DTab, "Atur titik drop", true)

    safe(function()
        UI.DropWorldInput = dBox:Input({
            Title = "World drop",
            Desc = "Kosong = world ini | WORLD | WORLD:ID (masuk lewat pintu ID)",
            Value = Pabrik.DropWorld,
            Placeholder = "STORAGE:1",
            Callback = function(t) Pabrik.DropWorld = tostring(t or "") end,
        })
    end)

    safe(function()
        dBox:Button({
            Title = "Pakai posisi sekarang untuk drop",
            Desc = "Berdiri di tempat drop (boleh di world lain), lalu tekan",
            Callback = function()
                local x, y = Auto.here()
                if not x then
                    notify("Titik Drop", "Kamu belum masuk world", 3)
                    return
                end
                Pabrik.DropX, Pabrik.DropY = x, y
                -- world ikut diisi, kecuali sudah pakai format WORLD:ID
                if not string.find(Pabrik.DropWorld or "", ":", 1, true) then
                    Pabrik.DropWorld = Guard.worldName()
                    if UI.DropWorldInput then pcall(function() UI.DropWorldInput:Set(Pabrik.DropWorld) end) end
                end
                notify("Titik Drop", ("Posisi drop (%d,%d) di %s"):format(x, y, Pabrik.DropWorld), 4)
            end,
        })
    end)

    safe(function()
        dBox:Button({
            Title = "Hapus posisi drop",
            Desc = "Drop di titik kedatangan (pintu) saja",
            Callback = function()
                Pabrik.DropX, Pabrik.DropY = -1, -1
                notify("Titik Drop", "Posisi drop dihapus", 3)
            end,
        })
    end)

    task.spawn(function()
        while alive() do
            local name, door = Auto.parseDropTarget()
            local here = Guard.worldName()
            local point
            if Pabrik.DropX < 0 and not door and (name == "" or name == here) then
                point = "belum diatur"
            else
                point = (name ~= "" and name or "world ini") .. (door and (" pintu " .. door) or "")
                    .. (Pabrik.DropX >= 0 and (" (" .. Pabrik.DropX .. "," .. Pabrik.DropY .. ")") or " (titik kedatangan)")
            end
            local txt = table.concat({
                "Titik  : " .. point,
                "Dipakai: Pabrik (seed), Farmer & Auto Farm (otomatis saat item ~190)",
                ("Di-drop: Pabrik %d | Farmer %d | Auto Farm %d"):format(Pabrik.Dropped, Farmer.Dropped, State.Dropped),
                "Catatan: drop di titik ini tidak di-collect lagi",
            }, "\n")
            if UI.DropPointStatus and txt ~= UI.DropPointShown then
                UI.DropPointShown = txt
                pcall(function() UI.DropPointStatus:SetDesc(txt) end)
            end
            task.wait(1)
        end
    end)
end)() end

-- ===== TAB: KONEKSI =====
local ConnTab = makeTab("Koneksi", "plug", "setel")

safe(function()
    UI.RefInfo = ConnTab:Paragraph({ Title = "Referensi game", Desc = "-" })
end)

Box.ConnMain = box(ConnTab, "Koneksi", true)
Box.ConnCfg = box(ConnTab, "Config", true)
Box.ConnCalib = box(ConnTab, "Koreksi posisi", false)
Box.ConnLang = box(ConnTab, "Bahasa / Language", false)

-- FIX: validasi ItemDB berdasarkan bentuk data item, bukan sekadar tabel berisi ID.
-- Ini mencegah tabel terjemahan I18N.PH (array {teks_id, teks_en}) terpilih.
function Session.entryName(entry)
    if type(entry) ~= "table" then return nil end
    -- ItemDB yang dipakai script ini mengakses field `name` secara langsung.
    -- Jangan menerima label terjemahan / displayName sebagai pengganti.
    local value = rawget(entry, "name")
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

function Session.isRealItemDB(db)
    if type(db) ~= "table" or db == I18N.PH or db == I18N.EN or db == I18N.list or db == I18N.RAW then
        return false
    end
    local count, named, metadata = 0, 0, 0
    for id, entry in pairs(db) do
        if type(id) == "number" and id >= 0 and id % 1 == 0 and type(entry) == "table" then
            -- Array {teks_id, teks_en} adalah tabel bahasa, bukan record item.
            if type(rawget(entry, 1)) == "string" or type(rawget(entry, 2)) == "string" then
                return false
            end
            count += 1
            if type(rawget(entry, "name")) == "string" and rawget(entry, "name") ~= "" then named += 1 end
            if type(rawget(entry, "hits")) == "number"
                or type(rawget(entry, "solid")) == "boolean"
                or type(rawget(entry, "kind")) == "string"
                or type(rawget(entry, "seedId")) == "number"
                or type(rawget(entry, "deadly")) == "boolean"
                or type(rawget(entry, "hurts")) == "boolean" then
                metadata += 1
            end
        end
    end
    -- Wajib memiliki nama dan metadata yang memang dibaca oleh fitur farming.
    return count >= 20 and named >= 20 and named / count >= 0.85
        and metadata >= math.max(8, math.ceil(count * 0.25))
end

-- Cara pertama: cari database pada upvalue fungsi milik data world aktif.
function Session.itemDBFromWorld()
    local world = Refs.World
    if type(world) ~= "table" or type(getUpvalues) ~= "function" then
        return nil, "world / getUpvalues belum siap"
    end
    local seen = {}
    local function inspect(fn, depth)
        if depth > 3 or seen[fn] then return nil end
        seen[fn] = true
        local ok, ups = pcall(getUpvalues, fn)
        if not ok or type(ups) ~= "table" then return nil end
        for _, value in pairs(ups) do
            if type(value) == "table" and value ~= world and Session.isRealItemDB(value) then
                return value
            elseif type(value) == "function" then
                local found = inspect(value, depth + 1)
                if found then return found end
            end
        end
    end
    for _, value in pairs(world) do
        if type(value) == "function" then
            local found = inspect(value, 0)
            if found then return found, "upvalue fungsi World" end
        end
    end
    return nil, "ItemDB tidak ditemukan pada upvalue World"
end

-- Cara kedua: cocokkan ID foreground/background, tetapi setiap entri wajib
-- memiliki nama dan ciri metadata database item yang valid.
function Session.fingerprintItemDB()
    local world = Refs.World
    if type(world) ~= "table" or type(getgc) ~= "function" then
        return nil, "world / getgc belum siap"
    end
    local ids, seen = {}, {}
    for _, layer in ipairs({ "fg", "bg" }) do
        local grid = world[layer]
        if type(grid) == "table" then
            for y = 0, math.min((world.h or 1) - 1, 80) do
                local row = grid[y]
                if type(row) == "table" then
                    for x = 0, (world.w or 1) - 1 do
                        local id = row[x]
                        if type(id) == "number" and id > 0 and not seen[id] and #ids < 20 then
                            seen[id] = true
                            ids[#ids + 1] = id
                        end
                    end
                end
                if #ids >= 20 then break end
            end
        end
        if #ids >= 20 then break end
    end
    if #ids < 3 then return nil, "world terlalu kosong untuk dicocokkan" end

    local ok, objects = pcall(getgc, true)
    if not ok or type(objects) ~= "table" then
        ok, objects = pcall(getgc)
    end
    if not ok or type(objects) ~= "table" then return nil, "getgc gagal" end

    local best, bestScore, visited = nil, 0, 0
    for _, candidate in pairs(objects) do
        visited += 1
        if visited % 2500 == 0 then task.wait() end
        if type(candidate) == "table" and candidate ~= world and candidate ~= world.fg
            and candidate ~= world.bg and candidate ~= ItemDB and Session.isRealItemDB(candidate) then
            local score = 0
            for _, id in ipairs(ids) do
                local entry = rawget(candidate, id)
                if type(entry) == "table" and Session.entryName(entry)
                    and (type(rawget(entry, "hits")) == "number"
                        or type(rawget(entry, "solid")) == "boolean"
                        or type(rawget(entry, "kind")) == "string"
                        or type(rawget(entry, "seedId")) == "number"
                        or type(rawget(entry, "deadly")) == "boolean"
                        or type(rawget(entry, "hurts")) == "boolean") then
                    score += 1
                end
            end
            if score > bestScore then
                best, bestScore = candidate, score
            end
        end
    end
    local required = math.max(3, math.ceil(#ids * 0.9))
    if best and bestScore >= required then
        return best, bestScore .. "/" .. #ids
    end
    return nil, ("tidak ada tabel valid (skor terbaik %d/%d; perlu %d)"):format(bestScore, #ids, required)
end

function Session.fixItemDB()
    if Session.isRealItemDB(Session.ItemDBSource) then
        Session.ItemDBMissing = false
        return true
    end
    Session.ItemDBMissing = true

    local db, info = Session.itemDBFromWorld()
    if not db then db, info = Session.fingerprintItemDB() end
    if not db or not Session.isRealItemDB(db) then
        Session.ItemDBMissing = true
        Session.ItemDBLastError = tostring(info or "kandidat tidak lolos validasi")
        return false, Session.ItemDBLastError
    end

    Session.ItemDBSource = db
    table.clear(ItemDB) -- kosongkan cache proxy agar ID dibaca ulang dari database baru
    table.clear(itemNameCache)
    lastInvSig, lastSeedSig, lastBlockSig = nil, nil, nil
    Session.ItemDBMissing = false
    Session.ItemDBLastError = nil
    print("[n4th] ItemDB valid (" .. tostring(info) .. ")")
    return true
end

-- DIAGNOSA: kumpulkan data untuk mencari tahu kenapa fungsi pukul / daftar block tidak ketemu.
function Session.diagnose()
    local out = {}
    local function add(t) out[#out + 1] = t end
    add("== n4th diagnosa == build " .. tostring(Session.Build))
    add("ItemDB hilang saat start: " .. tostring(Session.ItemDBMissing == true))
    add("Validasi sumber ItemDB: " .. tostring(Session.isRealItemDB and Session.isRealItemDB(Session.ItemDBSource) or false))
    add("Referensi: " .. refsText())
    local src = Session.ItemDBSource
    if type(src) == "table" then
        local n, withHits, noHits, samples = 0, 0, 0, {}
        for id, it in pairs(src) do
            if type(id) == "number" and type(it) == "table" then
                n += 1
                if type(rawget(it, "hits")) == "number" then withHits += 1 else noHits += 1 end
                if #samples < 3 and rawget(it, "solid") == true and rawget(it, "kind") ~= "seed" then
                    local keys = {}
                    for k, v in pairs(it) do
                        if type(v) ~= "table" and type(v) ~= "function" then keys[#keys + 1] = tostring(k) .. "=" .. tostring(v) end
                    end
                    table.sort(keys)
                    samples[#samples + 1] = "#" .. id .. " " .. table.concat(keys, ",", 1, math.min(#keys, 16))
                end
            end
        end
        add(("ItemDB: %d item | hits angka=%d | tanpa hits=%d"):format(n, withHits, noHits))
        for _, line in ipairs(samples) do add("  contoh block: " .. line) end
    else
        add("ItemDB sumber: tidak ada")
    end
    do
        local db, info = Session.fingerprintItemDB()
        add("Sidik jari ItemDB: " .. (db and ("COCOK " .. tostring(info)) or ("tidak ketemu: " .. tostring(info))))
        if db then
            local w0, shown = Refs.World, 0
            local function dump(id)
                local e = rawget(db, id)
                if type(e) ~= "table" then return end
                local keys = {}
                for k, v in pairs(e) do
                    local tv = type(v)
                    keys[#keys + 1] = tostring(k) .. "=" .. ((tv == "table" or tv == "function") and tv or tostring(v))
                end
                table.sort(keys)
                add("  entri #" .. id .. ": " .. table.concat(keys, ", ", 1, math.min(#keys, 24)))
            end
            local want = {}
            for _, layer in ipairs({ "fg", "bg" }) do
                local grid = w0 and w0[layer]
                if type(grid) == "table" then
                    for y = 0, math.min((w0.h or 1) - 1, 60) do
                        local row = grid[y]
                        for x = 0, (w0.w or 1) - 1 do
                            local id = row and row[x]
                            if type(id) == "number" and id > 0 and not want[id] and shown < 5 then
                                want[id] = true
                                shown += 1
                                dump(id)
                            end
                        end
                    end
                end
            end
        end
    end
    local ok, ids = pcall(function() return (Auto.worldBreakOptions(false)) end)
    local w = Refs.World
    add(("World: %s %sx%s | block yang bisa dipilih Auto Break: %s"):format(tostring(w and w.name), tostring(w and w.w),
        tostring(w and w.h), ok and tostring(#ids) or ("error " .. tostring(ids))))
    local fgTypes = {}
    if w and type(w.fg) == "table" then
        local seen = {}
        for y = 0, math.min(w.h - 1, 60) do
            local row = w.fg[y]
            for x = 0, w.w - 1 do
                local id = row and row[x]
                if id and id ~= 0 and not seen[id] and #fgTypes < 6 then
                    seen[id] = true
                    local it = ItemDB[id]
                    fgTypes[#fgTypes + 1] = ("#%d %s hits=%s kind=%s"):format(id, tostring(it and it.name), tostring(it and it.hits), tostring(it and it.kind))
                end
            end
        end
    end
    for _, line in ipairs(fgTypes) do add("  fg: " .. line) end
    add("Executor: getgc=" .. type(getgc) .. " filtergc=" .. type(filtergc) .. " getconnections=" .. type(getconnections)
        .. " hookfunction=" .. type(hookfunction) .. " getconstants=" .. type((debug and debug.getconstants) or getconstants)
        .. " getupvalues=" .. type((debug and debug.getupvalues) or getupvalues))
    -- kandidat fungsi pukul: konstanta mengandung vending / crack / punch
    local cands = 0
    if type(getgc) == "function" then
        local okg, objs = pcall(getgc, true)
        if okg and type(objs) == "table" then
            local visited = 0
            for _, f in pairs(objs) do
                visited += 1
                if visited % 3000 == 0 then task.wait() end
                if type(f) == "function" and cands < 8 then
                    local consts = getconsts(f)
                    local hit = false
                    for _, c in pairs(consts) do
                        if type(c) == "string" then
                            local lc = c:lower()
                            if lc:find("vending", 1, true) or lc:find("crack", 1, true) or lc:find("harvestprovider", 1, true) then hit = true break end
                        end
                    end
                    if hit then
                        cands += 1
                        local list = {}
                        for _, c in pairs(consts) do
                            if type(c) == "string" and #c < 50 then list[#list + 1] = c end
                            if #list >= 30 then break end
                        end
                        local src2 = "?"
                        if debug and type(debug.info) == "function" then
                            local oks, sv = pcall(debug.info, f, "s")
                            if oks then src2 = tostring(sv) end
                        end
                        add(("  kandidat pukul #%d [%s]: %s"):format(cands, src2, table.concat(list, " | ")))
                    end
                end
            end
        end
    end
    if cands == 0 then add("  kandidat pukul: tidak ada fungsi dengan konstanta vending/crack") end
    local text = table.concat(out, "\n")
    print(text)
    local clip = setclipboard or toclipboard or (syn and syn.write_clipboard)
    if type(clip) == "function" then pcall(clip, text) end
    return text
end

local function reconnect(show)
    -- Jangan pernah mempertahankan sumber ItemDB yang gagal validasi.
    if not Session.isRealItemDB(Session.ItemDBSource) then Session.ItemDBMissing = true end
    -- hentikan Clear / Farmer dulu
    if Clear.Running then stopClear("Dihentikan: hubungkan ulang ke game") end
    if Farmer.Running then stopFarmer("Dihentikan: hubungkan ulang ke game") end
    Auto.resetReach()
    -- Jangan pakai objek world atau fungsi dari dunia sebelumnya.
    Refs.World, Refs.Inv = nil, nil
    Refs.SetTile, Refs.State, Refs.Punch, Refs.Menu = nil, nil, nil, nil
    Refs.Gems, Refs.Hud, Refs.Others, Refs.Arm = nil, nil, nil, nil
    Refs.Particles, Anim.Particles = {}, nil
    -- 1) cari isi tas cepat lalu langsung isi dropdown (tidak menunggu scan getgc yang lama)
    if pcall(Anim.quickRefs) and Refs.Inv then
        pcall(doInvRefresh, true)
        task.wait() -- biar dropdown tampil dulu sebelum scan lengkap (scan menahan layar sebentar)
    end
    -- 2) scan lengkap
    do local h = Session.FastPunch and Session.FastPunch.Hooked
        if h and not Refs.Punch then Refs.Punch = h.fn end end
    if not (Refs.World and Refs.Inv and Refs.Punch and Refs.SetTile and Refs.State and Refs.Menu
        and Refs.Gems and Refs.Hud and Refs.Others) then
        findRefs()
    end
    if Refs.ScanError then warn("[n4th] " .. Refs.ScanError) end
    watchInventory()
    if Session.ItemDBMissing then pcall(Session.fixItemDB) end
    pcall(doInvRefresh, true) -- langsung di thread ini (thread INIT / antrian UI), bukan thread tombol
    findDropRefs(true)
    Auto.findTreeRefs()
    table.clear(DropFailUntil)
    Anim.fn, Anim.idx = nil, nil
    pcall(Anim.findFast)
    if State.LiteMode then setLite(true) end
    if Misc.InfJump then hookJammer() end
    pcall(function() UI.RefInfo:SetDesc(refsText()) end)
    updateStatus()
    print("[n4th] " .. Session.Build .. " | scanned=" .. tostring(Refs.ScanCount) .. " | " .. refsText())
    if show then notify(show, refsText(), 5) end
end

safe(function()
    Box.ConnMain:Button({
        Title = "Diagnosa (salin ke clipboard)",
        Desc = "Kumpulkan info kenapa Pukul / daftar block tidak ketemu, lalu tempel ke chat",
        Callback = function()
            task.spawn(function()
                local ok, res = pcall(Session.diagnose)
                notify("Diagnosa", ok and "Selesai: sudah disalin ke clipboard & dicetak di console (F9)" or tostring(res), 6)
            end)
        end,
    })
end)

safe(function()
    Box.ConnMain:Button({
        Title = "Hubungkan ke game",
        Desc = "Pakai setelah pindah world",
        Callback = function()
            UI.later("reconnect", function() reconnect("Koneksi") end)
        end,
    })
end)

safe(function()
    UI.ConfigStatus = Box.ConnCfg:Paragraph({ Title = "Status", Desc = Config.Status })
end)

safe(function()
    Box.ConnCfg:Toggle({
        Title = "Auto Save Config",
        Desc = "Simpan pengaturan otomatis, dimuat lagi saat execute",
        Value = Config.AutoSave,
        Callback = function(on)
            Config.AutoSave = on
            Config.save(true) -- simpan pilihan ini juga
        end,
    })
end)

safe(function()
    Box.ConnCfg:Button({
        Title = "Simpan config sekarang",
        Callback = function()
            local ok = Config.save(true)
            notify("Config", ok and "Tersimpan" or Config.Status, 3)
        end,
    })
end)

safe(function()
    Box.ConnCfg:Button({
        Title = "Reset config (default)",
        Desc = "Hapus file config, lalu execute ulang",
        Callback = function()
            Config.reset()
            notify("Config", Config.Status, 4)
        end,
    })
end)

safe(function()
    Box.ConnLang:Dropdown({
        Title = "Bahasa / Language",
        Desc = "Ganti bahasa, lalu execute ulang",
        Values = { "Indonesia", "English" },
        Value = I18N.Saved == "en" and "English" or "Indonesia",
        Callback = function(v)
            local lang = (v == "English") and "en" or "id"
            if lang == I18N.Saved then return end
            I18N.Saved, I18N.Chosen = lang, true
            I18N.remember()
            notify("Bahasa / Language", "Execute ulang untuk ganti bahasa / Re-execute to apply", 5)
        end,
    })
end)

safe(function()
    Box.ConnLang:Toggle({
        Title = "Tanya bahasa saat execute",
        Desc = "Tanya saat execute manual.",
        Value = I18N.Ask,
        Callback = function(on) I18N.Ask = on I18N.remember() end,
    })
end)

safe(function()
    Box.ConnCalib:Input({
        Title = "Koreksi posisi X",
        Desc = "Isi 1 / -1 kalau tile meleset",
        Value = tostring(State.CalibX),
        Callback = function(text) State.CalibX = tonumber(text) or 0 end,
    })
end)

safe(function()
    Box.ConnCalib:Input({
        Title = "Koreksi posisi Y",
        Value = tostring(State.CalibY),
        Callback = function(text) State.CalibY = tonumber(text) or 0 end,
    })
end)

-- ===== KONEKSI: AUTO RECONNECT =====
do (function()
    local rBox = box(ConnTab, "Auto Reconnect", false)

    safe(function()
        UI.RejoinStatus = rBox:Paragraph({ Title = "Status", Desc = Rejoin.Status })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Auto Reconnect",
            Desc = "Masuk lagi & lanjut aktivitas kalau terlempar",
            Value = Rejoin.On,
            Callback = function(on) Rejoin.On = on end,
        })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Terlempar dari world",
            Desc = "World ditutup / di-kick: masuk lagi ke world yang sama",
            Value = Rejoin.World,
            Callback = function(on) Rejoin.World = on end,
        })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Selalu kembali ke world",
            Desc = "Kalau berada di luar world (layar pilih world), masuk lagi otomatis",
            Value = Rejoin.Keep,
            Callback = function(on) Rejoin.Keep = on end,
        })
    end)

    safe(function()
        rBox:Input({
            Title = "World tujuan",
            Desc = "Kosongkan = world terakhir yang kamu masuki",
            Value = Rejoin.Target,
            Placeholder = "NAMAWORLD",
            Callback = function(text) Rejoin.Target = tostring(text or "") end,
        })
    end)

    safe(function()
        rBox:Button({
            Title = "Rejoin world sekarang",
            Desc = "Keluar lalu masuk lagi, aktivitas dilanjutkan",
            Callback = function() Rejoin.now() end,
        })
    end)

    safe(function()
        rBox:Toggle({
            Title = "Disconnect dari server",
            Desc = "Teleport ulang ke game lalu masuk world terakhir",
            Value = Rejoin.Server,
            Callback = function(on) Rejoin.Server = on end,
        })
    end)

    addNumber(rBox, {
        Title = "Jeda sebelum masuk lagi (detik)",
        Min = 2, Max = 60, Step = 1, Default = Rejoin.DelaySec,
        Callback = function(v) Rejoin.DelaySec = math.floor(v) end,
    })

    safe(function()
        rBox:Input({
            Title = "URL script (untuk rejoin server)",
            Desc = "Link raw script ini, supaya jalan lagi setelah teleport. Kosong = pakai autoexec",
            Value = Rejoin.ScriptUrl,
            Placeholder = "https://...",
            Callback = function(text)
                Rejoin.ScriptUrl = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
            end,
        })
    end)
end)() end

-- ===== TAB: DISCORD =====
do (function()
    local DcTab = makeTab("Discord", "bell", "setel")

    safe(function()
        UI.HookStatus = DcTab:Paragraph({ Title = "Status", Desc = Hook.Status })
    end)

    local dMain = box(DcTab, "Webhook", true)
    local dWhat = box(DcTab, "Yang dikirim", false)

    safe(function()
        dMain:Toggle({
            Title = "Notifikasi Discord",
            Desc = "Kirim kabar penting ke channel Discord kamu",
            Value = Hook.On,
            Callback = function(on) Hook.On = on end,
        })
    end)

    safe(function()
        dMain:Input({
            Title = "URL Webhook",
            Desc = "Channel Discord > Edit > Integrasi > Webhook > Salin URL",
            Value = Hook.Url,
            Placeholder = "https://discord.com/api/webhooks/...",
            Callback = function(text)
                text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
                Hook.Url = text
                if text ~= "" and not Hook.valid(text) then
                    notify("Discord", "URL webhook tidak valid", 4)
                end
            end,
        })
    end)

    safe(function()
        dMain:Button({
            Title = "Tes kirim",
            Callback = function()
                if not Hook.valid(Hook.Url) then
                    notify("Discord", "Isi URL webhook dulu", 3)
                    return
                end
                local was = Hook.On
                Hook.On = true
                Hook.send("test", "Tes notifikasi dari n4th")
                Hook.On = was
                notify("Discord", "Pesan tes masuk antrian", 3)
            end,
        })
    end)

    addNumber(dMain, {
        Title = "Laporan statistik (menit)",
        Desc = "Kirim statistik sesi tiap X menit. 0 = mati",
        Min = 0, Max = 180, Step = 5, Default = Hook.ReportMin,
        Callback = function(v) Hook.ReportMin = math.floor(v) end,
    })

    for _, item in ipairs({
        { "Penjaga", "Mod / Dev / pemain masuk world" },
        { "Stop", "Aktivitas berhenti (block habis / error)" },
        { "Full", "Inventori penuh" },
        { "Rejoin", "Terlempar / disconnect / masuk lagi" },
        { "Pabrik", "Pabrik drop seed / lahan selesai / berhenti" },
    }) do
        safe(function()
            dWhat:Toggle({
                Title = item[2],
                Value = Hook[item[1]],
                Callback = function(on) Hook[item[1]] = on end,
            })
        end)
    end
end)() end


---------------------------------------------------------------------
-- INIT
---------------------------------------------------------------------
for field, title in pairs({ InvDropdown = "Farm", SeedDropdown = "Farmer", PabrikSeedDropdown = "Pabrik",
    ClearBlockDropdown = "Clear World", FarmerBlockDropdown = "Farmer", BuildBlockDropdown = "Lahan" }) do
    if UI[field] then UI.DropdownTabs[UI[field]] = title end
end
-- Thread pekerjaan UI: dibuat di sini (sama seperti thread status yang terbukti bisa mengubah UI).
-- Callback tombol / event game di sebagian executor tidak punya izin mengubah dropdown.
do
    task.spawn(function()
        while alive() do
            local ok, err = pcall(UI.runJobs)
            if not ok then warn("[n4th] UI runner: " .. tostring(err)) end
            task.wait(0.1)
        end
    end)
end

task.spawn(function()
    local readyDeadline = os.clock() + 12
    while alive() and LocalPlayer:GetAttribute("GameReady") ~= true and os.clock() < readyDeadline do task.wait(0.25) end
    if not alive() then return end
    reconnect("n4th v5.2")
    -- Retry ItemDB sampai 120 detik untuk kasus data game baru tersedia setelah reconnect.
    task.spawn(function()
        local startedAt = os.clock()
        while alive() and os.clock() - startedAt < 120 do
            if Refs.World then
                local okDB = Session.fixItemDB()
                if okDB then
                    if os.clock() - startedAt > 3 then
                        UI.later("invForce", function() doInvRefresh(true) end)
                        if UI.WorldBreakRefresh then
                            UI.later("worldBreakItems", function() UI.WorldBreakRefresh(true) end)
                        end
                        notify("ItemDB", "Data block berhasil dimuat", 3)
                    end
                    return
                end
            end
            task.wait(2.5)
        end
        if alive() and Session.ItemDBMissing then
            warn("[n4th] ItemDB belum ditemukan setelah 120 detik. Masuk ke world lalu tekan 'Hubungkan ke game'. Terakhir: " .. tostring(Session.ItemDBLastError))
        end
    end)
    -- FIX: kalau WorldMenu.isDown belum terpasang saat start, coba lagi sampai ketemu
    if not OrigIsDown then
        task.spawn(function()
            for _ = 1, 10 do
                if not alive() or OrigIsDown then return end
                task.wait(2)
                local obj = Session.findModule("WorldMenu", PlayerGui:FindFirstChild("GameGui"))
                if obj then
                    local ok, mod = pcall(require, obj)
                    if ok and type(mod) == "table" and type(rawget(mod, "isDown")) == "function" then
                        MenuModOk, MenuModule = true, mod
                        OrigIsDown = rawget(mod, "isDown")
                        mod.isDown = isDownWrapper
                        print("[n4th] WorldMenu.isDown terpasang (retry)")
                        return
                    end
                end
            end
            if alive() and not OrigIsDown then
                warn("[n4th] WorldMenu.isDown tetap tidak ketemu: Clear/Farmer/Pabrik/Lahan tidak bisa jalan.")
            end
        end)
    end
    -- Input dapat tersambung belakangan pada executor yang mulai sebelum client game selesai.
    if not Refs.Punch then
        task.spawn(function()
            for attempt = 1, 5 do
                task.wait(2)
                if not alive() or Refs.Punch then return end
                pcall(Anim.quickRefs)
                if attempt == 3 and not Refs.Punch then pcall(findRefs) end
                if Refs.Inv then pcall(watchInventory) end
                pcall(function() UI.RefInfo:SetDesc(refsText()) end)
                if Refs.Punch then
                    print("[n4th] Fungsi pukul ditemukan setelah input game siap.")
                    return
                end
            end
            if alive() and not Refs.Punch then
                warn("[n4th] Pukul belum ditemukan setelah mencoba GC dan koneksi input. Jalankan n4th-diagnose.lua untuk laporan API executor.")
            end
        end)
    end
    -- Penjaga dari config dinyalakan setelah data pemain ketemu
    -- (supaya pemain yang sudah ada dicatat dulu)
    if Config.saved("Penjaga", "On") == true and alive() then
        if UI.GuardToggle then pcall(function() UI.GuardToggle:Set(true) end) end
        if not Guard.On then Guard.set(true) end
    end
    Config.start()
    if I18N.SavePending then
        I18N.SavePending = nil
        Config.save(true)
    end
    Rejoin.startup(reconnect)
end)

task.spawn(function()
    while alive() do
        if UI.Window and UI.Window.Closed then task.wait(2) continue end
        if not State.Running then updateStatus() end
        Auto.updateClearStatus()
        Auto.updateFarmerStatus()
        if UI.ConfigStatus and Config.Status ~= Config.Shown then
            Config.Shown = Config.Status
            pcall(function() UI.ConfigStatus:SetDesc(Config.Status) end)
        end
        local rj = ("%s\nWorld tujuan: %s\nBerhasil masuk lagi: %d kali"):format(
            Rejoin.Status, (Rejoin.targetWorld and Rejoin.targetWorld() ~= "") and Rejoin.targetWorld() or "-", Rejoin.Count)
        if UI.RejoinStatus and rj ~= Rejoin.Shown then
            Rejoin.Shown = rj
            pcall(function() UI.RejoinStatus:SetDesc(rj) end)
        end
        local hk = ("%s\nAntrian: %d pesan"):format(Hook.Status, #Hook.Queue)
        if UI.HookStatus and hk ~= Hook.Shown then
            Hook.Shown = hk
            pcall(function() UI.HookStatus:SetDesc(hk) end)
        end
        task.wait(1)
    end
end)

---------------------------------------------------------------------
-- CLEANUP (otomatis saat script dijalankan ulang)
---------------------------------------------------------------------
Session.Cleanup = function()
    AutoDrop.On, AutoDrop.Cancelled = false, true
    State.Running = false
    Clear.Running = false
    Farmer.Running = false
    if Config.AutoSave then pcall(Config.save, false) end -- simpan sebelum ditutup
    Guard.On = false
    Scan.Auto = false
    Rejoin.On = false
    Pabrik.Running = false
    Build.Running = false
    State.Override = nil
    pcall(Auto.stopWalk)
    AutoInput.active = false
    pcall(Auto.releaseInput)
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    -- kembalikan nama asli (watermark dilepas)
    Misc.CustomName = false
    pcall(nameRestore)
    -- kembalikan fungsi game ke asal
    pcall(setLite, false)
    pcall(unhookJammer)
    if OrigIsDown and MenuModOk and rawget(MenuModule, "isDown") == isDownWrapper then
        MenuModule.isDown = OrigIsDown
    end
    if Refs.World then
        if Misc.Ghost then pcall(function() Refs.World.ghost = false end) end
        if Misc.Speed ~= 100 then pcall(function() Refs.World.speedScale = 1 end) end
    end
    pcall(function() GridGui:Destroy() end)
    pcall(function() FlyPad:Destroy() end)
    pcall(function() Window:Destroy() end)
end

Session.InitStep = "siap"
Session.Ready = true
print("[n4th] Menu siap (build " .. Session.Build .. ")")
