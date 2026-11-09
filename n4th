-- Loader tetap: cek commit terbaru, lalu ambil script dari URL commit tersebut.
assert(type(loadstring) == "function", "[n4th] Executor tidak menyediakan loadstring setelah update.")
local repository = "ZennJxD/n4th"
local httpService = game:GetService("HttpService")
local lastError = "respons kosong"

local function download(url)
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

local function latestSource()
    local refUrl = "https://api.github.com/repos/" .. repository .. "/git/ref/heads/main?update=" .. httpService:GenerateGUID(false)
    local ref = httpService:JSONDecode(download(refUrl))
    local commit = type(ref) == "table" and type(ref.object) == "table" and ref.object.sha
    if type(commit) ~= "string" or #commit ~= 40 or not commit:match("^%x+$") then
        local reason = type(ref) == "table" and ref.message or "respons metadata tidak valid"
        error("Gagal mengecek update GitHub: " .. tostring(reason), 0)
    end
    return download("https://raw.githubusercontent.com/" .. repository .. "/" .. commit .. "/n4th-main.lua"), commit
end

for attempt = 1, 3 do
    local ok, source, commit = pcall(latestSource)
    if ok then
        local fn, compileError = loadstring(source, "n4th-main")
        if not fn then error("[n4th] Script terbaru gagal dikompilasi: " .. tostring(compileError), 0) end
        print("[n4th] Menjalankan commit " .. commit:sub(1, 8))
        -- Error runtime tidak memicu eksekusi ulang atau aksi game ganda.
        local ran, result = xpcall(fn, function(err)
            if debug and type(debug.traceback) == "function" then return debug.traceback(tostring(err), 2) end
            return tostring(err)
        end)
        if not ran then
            local globals = (getgenv and getgenv()) or _G
            local session = globals.__n4thOpus
            local step = session and session.InitStep or "inisialisasi script"
            error("[n4th] Gagal saat " .. tostring(step) .. ":\n" .. tostring(result), 0)
        end
        return result
    end
    lastError = tostring(source)
    if attempt < 3 then task.wait(1) end
end
error("[n4th] Gagal mengambil update setelah 3 percobaan: " .. lastError, 0)
