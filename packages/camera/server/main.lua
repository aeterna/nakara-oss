-- aeterna_camera server: phone tiles, the shoot gate and upload tickets, photo files and index, the HTTP handler,
-- exports, the admin command and the server-side self-tests. Rules live in shared/logic/*.lua.

local Codec, Ids, Tickets, Store = CameraLogic.codec, CameraLogic.ids, CameraLogic.tickets, CameraLogic.store
local Service, Router, ST = CameraLogic.service, CameraLogic.router, CameraLogic.selftests

local RES = GetCurrentResourceName()
local PREFIX = RES .. '.'
local cfg = CameraLogic.settings.check(Config, AeternaCore.log.warn)

-- Lua 5.4 seeds math.random itself; mix the clock in without throwing that seed away.
math.randomseed(math.random(0, 0x7FFFFFFF) ~ os.time(), math.random(0, 0x7FFFFFFF) ~ GetGameTimer())

-- Tickets and photo ids come from two streams with their own seeds (ids.lua); every draw also mixes in
-- math.random, a counter, the game timer and os.clock. Hard to guess, not a secret.
local function rand(lo, hi) return math.random(lo, hi) end
local function newStream()
    return Ids.stream({ seed = math.random(0), rand = rand, now = GetGameTimer, clock = os.clock })
end
local ticketId = newStream()
local photoId = newStream()
local shootTests = {} -- src -> { runId, name } while shoot_and_view runs for that player

local function screenshotStarted()
    return GetResourceState('screenshot-basic') == 'started'
end

--------------------------------------------------------------------------------
-- Natives behind the pure logic
--------------------------------------------------------------------------------

local kv = {
    get = function(k) return GetResourceKvpString(k) end,
    set = function(k, v) SetResourceKvp(k, v) end,
    del = function(k) DeleteResourceKvp(k) end,
    keys = function(prefix)
        local out = {}
        local handle = StartFindKvp(prefix)
        if handle == nil or handle == -1 then return out end
        while true do
            local key = FindKvp(handle)
            if not key then break end
            out[#out + 1] = key
        end
        EndFindKvp(handle)
        return out
    end,
}

-- The only file writer. The path comes from an id that passed Ids.isId, inside photos/, which the package ships.
local function writePhoto(id, bytes)
    if not Ids.isId(id) or type(bytes) ~= 'string' then return false end
    -- FXServer Enhanced b177 returns the number 1 on success and false on failure (measured W3 2026-11-22).
    local wrote = SaveResourceFile(GetCurrentResourceName(), 'photos/' .. id .. '.jpg', bytes, #bytes)
    return wrote == true or wrote == 1
end

local function loadPhoto(id)
    if not Ids.isId(id) then return nil end
    return LoadResourceFile(RES, 'photos/' .. id .. '.jpg')
end

local function newService(perCharacter, maxTotalBytes)
    local store = Store.new({ kv = kv, json = json, perCharacter = perCharacter, maxTotalBytes = maxTotalBytes })
    local tickets = Tickets.new({ now = GetGameTimer, newId = ticketId })
    return Service.new({
        store = store,
        tickets = tickets,
        newId = photoId,
        now = GetGameTimer,
        clock = os.time,
        available = screenshotStarted,
        writePhoto = writePhoto,
        emit = function(name, ...) TriggerEvent(name, ...) end,
        warn = AeternaCore.log.warn,
        -- Only a photo taken inside shoot_and_view asks the self-test write guard.
        mayWrite = function(src)
            local t = shootTests[src]
            return t == nil or AeternaCore.selftest.mayWrite(t.runId, t.name)
        end,
    }, { cooldownMs = cfg.cooldownMs, maxBytes = cfg.maxBytes, perCharacter = perCharacter })
end

local svc = newService(cfg.perCharacter, cfg.maxTotalMB * 1024 * 1024)
local router = Router.new({
    now = GetGameTimer,
    has = function(id) return svc.deps.store:has(id) end,
    load = loadPhoto,
})

--------------------------------------------------------------------------------
-- Identity: cid:<citizenid> with qbx_core started, else lic:<license>. Server only.
--------------------------------------------------------------------------------

local function whoOf(src)
    if GetResourceState('qbx_core') == 'started' then
        local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        local cid = ok and type(player) == 'table' and type(player.PlayerData) == 'table' and player.PlayerData.citizenid
        if type(cid) == 'string' and cid ~= '' then return 'cid:' .. cid end
        return nil
    end
    local ok, license = pcall(GetPlayerIdentifierByType, src, 'license')
    if ok and type(license) == 'string' and license ~= '' then return 'lic:' .. license end
    return nil
end

local function toast(src, key, kind, vars)
    pcall(function()
        exports.aeterna_notify:notify(src, { title = AeternaCore.t(key, vars), type = kind })
    end)
end

local function sendShot(src, payload)
    TriggerClientEvent('aeterna_camera:cl:shot', src, payload)
end

local function sendGallery(src, who)
    TriggerClientEvent('aeterna_camera:cl:gallery', src, { items = svc:gallery(who) })
end

--------------------------------------------------------------------------------
-- Phone tiles (phonekit App API)
--------------------------------------------------------------------------------

local function addTiles()
    if GetResourceState('aeterna_phonekit') ~= 'started' then return end
    pcall(function()
        exports.aeterna_phonekit:addTile({ id = 'camera', label = AeternaCore.t('camera.app.camera'), icon = 'camera', order = 40 })
        exports.aeterna_phonekit:addTile({ id = 'gallery', label = AeternaCore.t('camera.app.gallery'), icon = 'image', order = 41 })
    end)
end

AddEventHandler('aeterna_phonekit:app', function(src, data)
    if type(data) ~= 'table' or data.owner ~= RES then return end
    local who = whoOf(src)
    if not who then return end
    if data.id == 'camera' then
        TriggerClientEvent('aeterna_camera:cl:viewfinder', src, svc:openViewfinder(src, who))
    elseif data.id == 'gallery' then
        sendGallery(src, who)
    end
end)

-- Dead battery or lost device: close the viewfinder and the gallery on that client.
AddEventHandler('aeterna_phonekit:power', function(src, data)
    if type(data) ~= 'table' or data.on ~= false then return end
    svc:close(src)
    svc.deps.tickets:drop(src)
    sendShot(src, { ok = false, reason = 'power_off' })
end)

--------------------------------------------------------------------------------
-- Net events
--------------------------------------------------------------------------------

local SHOOT_SCHEMA = { type = 'table', extra = false, fields = {
    mode = { type = 'string', enum = { 'back', 'selfie' } },
} }
local DELETE_SCHEMA = { type = 'table', extra = false, fields = {
    id = { type = 'string', minLen = 32, maxLen = 32, pattern = '^[0-9a-f]+$' },
} }

RegisterNetEvent('aeterna_camera:sv:shoot', function(payload)
    local src = source
    if not AeternaCore.rateLimit(src, 'camera:shoot', 1, 1000) then return end
    local ok, err, data = AeternaCore.validate(payload, SHOOT_SCHEMA)
    if not ok then
        AeternaCore.log.warn('dropped aeterna_camera:sv:shoot', { src = src, err = err })
        return
    end
    local who = whoOf(src)
    if not who then return end
    local allowed, ticketOrReason = svc:shoot(src, who, data.mode)
    if allowed then
        TriggerClientEvent('aeterna_camera:cl:capture', src, { ticket = ticketOrReason })
    else
        sendShot(src, { ok = false, reason = ticketOrReason })
        toast(src, ticketOrReason, 'warning')
    end
end)

RegisterNetEvent('aeterna_camera:sv:close', function()
    local src = source
    if not AeternaCore.rateLimit(src, 'camera:close', 4, 1000) then return end
    svc:close(src)
end)

RegisterNetEvent('aeterna_camera:sv:delete', function(payload)
    local src = source
    if not AeternaCore.rateLimit(src, 'camera:delete', 3, 1000) then return end
    local ok, err = AeternaCore.validate(payload, DELETE_SCHEMA)
    -- maxLen cuts a longer string before the pattern runs, so the raw id is checked too.
    if not ok or not Ids.isId(payload.id) then
        AeternaCore.log.warn('dropped aeterna_camera:sv:delete', { src = src, err = err or 'id: length' })
        return
    end
    local who = whoOf(src)
    if not who then return end
    local deleted, reason = svc:delete(src, who, payload.id)
    if deleted then
        sendGallery(src, who)
    elseif reason then
        toast(src, reason, 'warning')
    else
        AeternaCore.log.debug('dropped delete of a photo the character does not own', { src = src })
    end
end)

-- Latent upload from the client's own capture. The payload is checked in service.upload (shape, ticket first,
-- length cap before decoding); the image data never reaches a log line.
RegisterNetEvent('aeterna_camera:sv:upload', function(payload)
    local src = source
    if not AeternaCore.rateLimit(src, 'camera:upload', 1, 1000) then return end
    local who = whoOf(src)
    if not who then return end
    local status, a, b = svc:upload(src, who, payload)
    if status == 'saved' then
        sendShot(src, { ok = true, id = a.id })
        toast(src, 'camera.saved', 'success')
        if shootTests[src] then
            -- shoot_and_view: the person checks the new photo in the gallery.
            svc:close(src)
            sendGallery(src, who)
        end
    elseif status == 'refused' then
        AeternaCore.log.warn('refused photo upload', { src = src, reason = b })
        sendShot(src, { ok = false, reason = a })
        toast(src, a, 'error')
    else
        AeternaCore.log.warn('dropped photo upload', { src = src, reason = a })
    end
end)

AddEventHandler('playerDropped', function()
    shootTests[source] = nil
    svc:drop(source)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    svc:drop(src)
end)

--------------------------------------------------------------------------------
-- HTTP: GET /aeterna_camera/p/<id>.jpg (router.lua). writeHead always gets at least one header.
--------------------------------------------------------------------------------

local function serve(r, req, res)
    local answer = r:handle({ method = req.method, path = req.path, address = req.address })
    res.writeHead(answer.status, answer.headers)
    res.send(answer.body)
end

SetHttpHandler(function(req, res)
    serve(router, req, res)
end)

--------------------------------------------------------------------------------
-- Exports and the admin command
--------------------------------------------------------------------------------

exports('getPhoto', function(id)
    return svc:getPhoto(id)
end)

exports('listPhotos', function(who)
    return svc:listPhotos(who)
end)

exports('removePhoto', function(id, reason)
    if reason ~= nil then
        reason = type(reason) == 'string' and AeternaCore.text.clean(reason, 64) or nil
    end
    return svc:remove(id, reason)
end)

exports('available', function()
    return screenshotStarted()
end)

local function reply(src, key, vars)
    if src == 0 then
        print(AeternaCore.t(key, vars))
    else
        toast(src, key, 'info', vars)
    end
end

RegisterCommand('aeterna_camera_remove', function(src, args)
    if not AeternaCore.can(src, 'aeterna.camera.admin') then return end
    local id = args and args[1]
    if not Ids.isId(id) then
        reply(src, 'camera.admin.usage')
        return
    end
    if svc:remove(id, 'admin') then
        reply(src, 'camera.admin.removed', { id = id })
    else
        reply(src, 'camera.admin.unknown', { id = id })
    end
end, false)

--------------------------------------------------------------------------------
-- Self-tests (server side). Mocks write only under the fake key test:camera and put the total back.
--------------------------------------------------------------------------------

local function report(runId, name, ok, detail, extra)
    exports.aeterna_core:reportSelftest(runId, name, ok, detail, extra)
end

local function fakeState(store)
    local left = 0
    for _, key in ipairs(kv.keys(Store.PHOTO)) do
        local raw = kv.get(key)
        if type(raw) == 'string' and raw:find(ST.FAKE_WHO, 1, true) then left = left + 1 end
    end
    return { total = store:total(), count = store:count(ST.FAKE_WHO), left = left }
end

local function mockReport(runId, name, ok, detail, before)
    local after = fakeState(svc.deps.store)
    if not ST.restored(before, after) then
        report(runId, name, false, 'state not restored')
        return
    end
    report(runId, name, ok and 'mock' or false, detail, ok and { restored = true } or nil)
end

local function cleanFake()
    for _, p in ipairs(svc:listPhotos(ST.FAKE_WHO)) do svc:remove(p.id, 'selftest') end
end

local tests = {}

tests.id_and_path_guard = function()
    return ST.guard(Ids.isId, photoId)
end

tests.http_router = function()
    local id = photoId()
    local bytes = Codec.tinyJpeg()
    local r = Router.new({
        now = GetGameTimer,
        has = function(x) return x == id end,
        load = function(x) return x == id and bytes or nil end,
    })
    local cases, answers = ST.httpCases(id), {}
    for i, c in ipairs(cases) do
        local seen = {}
        serve(r, c.req, {
            writeHead = function(code, headers) seen.status, seen.headers = code, headers end,
            send = function() end,
        })
        answers[i] = seen
    end
    return ST.judgeHttp(cases, answers)
end

tests.screenshot_detect = function()
    return ST.screenshotDetail(screenshotStarted())
end

tests.store_roundtrip = function()
    local photo, why = svc:save(0, ST.FAKE_WHO, 'back', Codec.tinyJpeg())
    if not photo then return false, 'save refused: ' .. tostring(why) end
    local back = svc:getPhoto(photo.id)
    local list = svc:listPhotos(ST.FAKE_WHO)
    local file = loadPhoto(photo.id)
    local okRemove = svc:remove(photo.id, 'selftest')
    if not back or back.bytes ~= photo.bytes then return false, 'index read-back differs' end
    if not list[1] or list[1].id ~= photo.id then return false, 'list does not start with the new photo' end
    if file ~= Codec.tinyJpeg() then return false, 'file read-back differs' end
    if not okRemove or svc:getPhoto(photo.id) then return false, 'remove failed' end
    if loadPhoto(photo.id) ~= '' then return false, 'removed file is not empty' end
    return true, 'file, index and list written, read and removed'
end

tests.caps = function()
    local store = svc.deps.store
    local small = Store.new({ kv = kv, json = json, perCharacter = 1, maxTotalBytes = store:total() + 30 })
    local capped = Service.new(setmetatable({ store = small }, { __index = svc.deps }),
        { cooldownMs = cfg.cooldownMs, maxBytes = cfg.maxBytes, perCharacter = 1 })
    local jpeg = Codec.tinyJpeg()
    local first = capped:save(0, ST.FAKE_WHO, 'back', jpeg)
    if not first then return false, 'first photo refused' end
    local okFull, reasonFull = small:check(ST.FAKE_WHO, 0)
    local okDisk, reasonDisk = small:check('test:camera2', #jpeg)
    capped:remove(first.id, 'selftest')
    if okFull or reasonFull ~= 'camera.full' then return false, 'per-character cap did not refuse' end
    if okDisk or reasonDisk ~= 'camera.disk_full' then return false, 'total cap did not refuse' end
    return true, 'camera.full and camera.disk_full refused at their caps'
end

tests.saved_hook = function()
    local caught = {}
    local handle = AddEventHandler('aeterna_camera:saved', function(src, photo)
        if type(photo) == 'table' and photo.who == ST.FAKE_WHO then caught[#caught + 1] = { src, photo } end
    end)
    local photo = svc:save(0, ST.FAKE_WHO, 'selfie', Codec.tinyJpeg())
    RemoveEventHandler(handle)
    if not photo then return false, 'save refused' end
    svc:remove(photo.id, 'selftest')
    return ST.checkSaved(caught, photo.id)
end

local MOCKS = { store_roundtrip = true, caps = true, saved_hook = true }

-- Self-test events are trusted only from aeterna_core; any resource can fire a local event.
local function fromCore()
    return GetInvokingResource() == 'aeterna_core'
end

AddEventHandler('aeterna_core:selftest', function(runId, name, ctx)
    if not fromCore() then return end
    if type(name) ~= 'string' or name:sub(1, #PREFIX) ~= PREFIX then return end
    if type(ctx) == 'table' and ctx.side == 'client' then return end
    local short = name:sub(#PREFIX + 1)
    local fn = tests[short]
    if not fn then return end
    local before = MOCKS[short] and fakeState(svc.deps.store) or nil
    local okRun, ok, detail = pcall(fn)
    if MOCKS[short] then
        cleanFake()
        if not okRun then
            report(runId, name, false, 'error: ' .. tostring(ok))
            return
        end
        mockReport(runId, name, ok, detail, before)
        return
    end
    if not okRun then
        report(runId, name, false, 'error: ' .. tostring(ok))
        return
    end
    report(runId, name, ok and true or false, detail)
end)

-- shoot_and_view (eye, destructive): core announces the client test on the server first. Open the viewfinder for
-- player A so the client half can shoot; the photo passes the write guard before it is written (mayWrite above).
local SHOOT_TEST = PREFIX .. 'shoot_and_view'

AddEventHandler('aeterna_core:selftestStarted', function(runId, name, ctx)
    if not fromCore() then return end
    if name ~= SHOOT_TEST or type(ctx) ~= 'table' or type(ctx.a) ~= 'number' then return end
    local who = whoOf(ctx.a)
    if not who then return end
    shootTests[ctx.a] = { runId = runId, name = name }
    TriggerClientEvent('aeterna_camera:cl:viewfinder', ctx.a, svc:openViewfinder(ctx.a, who))
end)

local function endShootTests(runId)
    for src, t in pairs(shootTests) do
        if runId == nil or t.runId == runId then
            shootTests[src] = nil
            svc:close(src)
            svc.deps.tickets:drop(src)
        end
    end
end

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if not fromCore() or name ~= SHOOT_TEST then return end
    endShootTests(runId)
end)

-- A stopped core ends every run without a selftestEnd.
AddEventHandler('onResourceStop', function(resource)
    if resource == 'aeterna_core' then endShootTests(nil) end
end)

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

local function registerSelftests()
    for _, row in ipairs(ST.rows(AeternaCore.t)) do
        local okAdd, err = pcall(function() return exports.aeterna_core:addSelftest(row.name, row.meta) end)
        if not okAdd then AeternaCore.log.warn('selftest registration failed', { name = row.name, err = tostring(err) }) end
    end
end

AddEventHandler('onResourceStart', function(resource)
    if resource == 'aeterna_phonekit' then addTiles() end
end)

do
    local changed, before, after = svc.deps.store:repair()
    if changed then
        AeternaCore.log.warn('photo total did not match the index; corrected', { before = before, after = after })
    end
end
addTiles()
registerSelftests()
