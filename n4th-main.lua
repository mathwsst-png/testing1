--=====================================================================
-- PATCH Auto Route Drop: sweep 1 baris lurus (tanpa berhenti per drop)
--
-- LANGKAH 1: cari baris ini di script:   local function routeDropStep()
--            Hapus SELURUH fungsi routeDropStep lama (dari "local function routeDropStep()"
--            sampai "end" penutupnya, tepat sebelum blok task.spawn(function() ... RouteDrop.Running ...).
--            Lalu tempel BLOK A + BLOK B di bawah ini di posisi tersebut.
--=====================================================================

--------------------------- BLOK A ----------------------------------
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
