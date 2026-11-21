-- aeterna_camera client: viewfinder (focus, base-game phone camera, overlay, capture and latent upload),
-- gallery panel, NUI bridge and the client side of the viewfinder self-test.

local Ids, ST, V = CameraLogic.ids, CameraLogic.selftests, CameraViewfinder
local RES = GetCurrentResourceName()
local cfg = CameraLogic.settings.check(Config, AeternaCore.log.warn)

local LOCALE_KEYS = {
    'camera.app.gallery', 'camera.hint.shutter', 'camera.hint.switch', 'camera.hint.close',
    'camera.gallery.empty', 'camera.gallery.delete', 'camera.gallery.delete_confirm', 'camera.gallery.cancel',
}
local RESTORE_MS = 10000
local UPLOAD_BPS = 200000
local VIEWFINDER_TEST = 'aeterna_camera.viewfinder'

local vf = nil       -- { token, mode, count, cap, paused, capture = { ticket, hud, radar }?, session, test? }
local gallery = nil  -- { token, ids = { [id] = true }, paused }
local session = 0
local lastShot = nil
local pendingDelete = nil

local function send(msg)
    SendNUIMessage(msg)
end

local function sendSetup()
    local strings = {}
    for i = 1, #LOCALE_KEYS do strings[LOCALE_KEYS[i]] = AeternaCore.t(LOCALE_KEYS[i]) end
    send(AeternaCore.themeMessage())
    send({ type = 'locale', strings = strings })
end

local function media(on)
    pcall(function() exports.aeterna_phonekit:activity('media', on) end)
end

local function hints()
    return {
        { bind = V.keyText('+aeterna_camera_shutter', V.CONTROL_SELECT), label = AeternaCore.t('camera.hint.shutter') },
        { bind = V.keyText('+aeterna_camera_switch', V.CONTROL_SELFIE), label = AeternaCore.t('camera.hint.switch') },
        { bind = V.keyText(nil, V.CONTROL_CANCEL), label = AeternaCore.t('camera.hint.close') },
    }
end

local function showOverlay()
    send({ type = 'vf:show', count = vf.count, cap = vf.cap, mode = vf.mode, hints = hints() })
end

--------------------------------------------------------------------------------
-- Viewfinder
--------------------------------------------------------------------------------

local function restoreAfterCapture()
    if not vf or not vf.capture then return end
    local c = vf.capture
    vf.capture = nil
    if not c.hudHidden then DisplayHud(true) end
    if not c.radarHidden then DisplayRadar(true) end
    showOverlay()
end

local function closeViewfinder()
    if not vf then return end
    local v = vf
    restoreAfterCapture()
    vf = nil
    V.stop()
    media(false)
    send({ type = 'vf:hide' })
    if v.token then AeternaCore.releaseFocus(v.token) end
    if not v.test then TriggerServerEvent('aeterna_camera:sv:close') end
end

local function shutter()
    if not vf or vf.paused or vf.capture or vf.test then return end
    local now = GetGameTimer()
    if lastShot and now - lastShot < cfg.cooldownMs then return end
    lastShot = now
    TriggerServerEvent('aeterna_camera:sv:shoot', { mode = vf.mode })
end

local function switchCamera()
    if not vf or vf.paused or vf.capture then return end
    vf.mode = vf.mode == 'back' and 'selfie' or 'back'
    V.setSelfie(vf.mode == 'selfie')
    send({ type = 'vf:mode', mode = vf.mode })
end

local function frameLoop(s)
    while vf and vf.session == s do
        V.frame()
        if not vf.paused and not vf.capture and not vf.test then
            local input = V.read()
            if input.close then
                closeViewfinder()
            elseif input.shutter then
                shutter()
            elseif input.switch then
                switchCamera()
            end
        end
        Wait(0)
    end
end

local function closeGallery()
    if not gallery then return end
    local g = gallery
    gallery = nil
    pendingDelete = nil
    send({ type = 'gallery:hide' })
    if g.token then AeternaCore.releaseFocus(g.token) end
end

-- opts = { count, cap, test }
local function openViewfinder(opts)
    if vf then
        vf.count, vf.cap = opts.count, opts.cap
        showOverlay()
        return true
    end
    closeGallery()
    local token = AeternaCore.requestFocus({ cursor = false, keyboard = true, keepGameInput = true })
    if not token then
        if not opts.test then TriggerServerEvent('aeterna_camera:sv:close') end
        return false
    end
    session = session + 1
    vf = { token = token, mode = 'back', count = opts.count, cap = opts.cap, session = session, test = opts.test }
    V.start()
    media(true)
    sendSetup()
    showOverlay()
    local s = session
    CreateThread(function() frameLoop(s) end)
    return true
end

local VF_SCHEMA = { type = 'table', extra = false, fields = {
    count = { type = 'number', integer = true, min = 0, max = 100000 },
    cap = { type = 'number', integer = true, min = 1, max = 500 },
} }

RegisterNetEvent('aeterna_camera:cl:viewfinder', function(payload)
    local ok, err, data = AeternaCore.validate(payload, VF_SCHEMA)
    if not ok then
        AeternaCore.log.warn('dropped aeterna_camera:cl:viewfinder', { err = err })
        return
    end
    openViewfinder({ count = data.count, cap = data.cap })
end)

RegisterNetEvent('aeterna_camera:cl:capture', function(payload)
    if type(payload) ~= 'table' or not Ids.isId(payload.ticket) then return end
    if not vf or vf.capture or vf.test then return end
    local ticket = payload.ticket
    local s = vf.session
    vf.capture = { ticket = ticket, hudHidden = IsHudHidden(), radarHidden = IsRadarHidden() }
    send({ type = 'vf:hide' })
    DisplayHud(false)
    DisplayRadar(false)
    CreateThread(function()
        Wait(0)
        Wait(0)
        if not vf or vf.session ~= s or not vf.capture or vf.capture.ticket ~= ticket then return end
        local ok = pcall(function()
            exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = cfg.quality }, function(data)
                if type(data) ~= 'string' then return end
                TriggerLatentServerEvent('aeterna_camera:sv:upload', UPLOAD_BPS, { ticket = ticket, data = data })
            end)
        end)
        if not ok then restoreAfterCapture() end
    end)
    SetTimeout(RESTORE_MS, function()
        if vf and vf.session == s and vf.capture and vf.capture.ticket == ticket then restoreAfterCapture() end
    end)
end)

local SHOT_SCHEMA = { type = 'table', extra = false, fields = {
    ok = { type = 'boolean' },
    id = { type = 'string', maxLen = 32, optional = true },
    reason = { type = 'string', maxLen = 32, optional = true },
} }

RegisterNetEvent('aeterna_camera:cl:shot', function(payload)
    local ok, _, data = AeternaCore.validate(payload, SHOT_SCHEMA)
    if not ok then return end
    if data.reason == 'power_off' then
        closeViewfinder()
        closeGallery()
        return
    end
    if not vf then return end
    restoreAfterCapture()
    if data.ok then
        vf.count = vf.count + 1
        showOverlay()
    end
end)

RegisterCommand('+aeterna_camera_shutter', function() shutter() end, false)
RegisterCommand('-aeterna_camera_shutter', function() end, false)
RegisterCommand('+aeterna_camera_switch', function() switchCamera() end, false)
RegisterCommand('-aeterna_camera_switch', function() end, false)
AeternaCore.key('+aeterna_camera_shutter', 'camera.key.shutter')
AeternaCore.key('+aeterna_camera_switch', 'camera.key.switch')

--------------------------------------------------------------------------------
-- Gallery
--------------------------------------------------------------------------------

-- '<host>' from GetCurrentServerEndpoint() with any scheme:// and trailing / removed.
local function photoBase()
    local ok, endpoint = pcall(GetCurrentServerEndpoint)
    if not ok or type(endpoint) ~= 'string' or endpoint == '' then return nil end
    local host = endpoint:gsub('^%a[%w+.-]*://', ''):gsub('/+$', '')
    if host == '' or host:find('[%s/]') then return nil end
    return 'http://' .. host .. '/aeterna_camera/p/'
end

local ITEM_SCHEMA = { type = 'table', extra = false, fields = {
    id = { type = 'string', minLen = 32, maxLen = 32, pattern = '^[0-9a-f]+$' },
    ts = { type = 'number', min = 0 },
    mode = { type = 'string', enum = { 'back', 'selfie' } },
    bytes = { type = 'number', integer = true, min = 0 },
} }
local GALLERY_SCHEMA = { type = 'table', extra = false, fields = {
    items = { type = 'array', maxItems = 500, items = ITEM_SCHEMA },
} }

local function idSet(items)
    local set = {}
    for _, it in ipairs(items) do set[it.id] = true end
    return set
end

RegisterNetEvent('aeterna_camera:cl:gallery', function(payload)
    local ok, err, data = AeternaCore.validate(payload, GALLERY_SCHEMA)
    if not ok then
        AeternaCore.log.warn('dropped aeterna_camera:cl:gallery', { err = err })
        return
    end
    local items = data.items
    if gallery then
        -- A refresh after a delete: tell the page which ids left.
        local now = idSet(items)
        for id in pairs(gallery.ids) do
            if not now[id] then send({ type = 'gallery:removed', id = id }) end
        end
        gallery.ids = now
        pendingDelete = nil
        return
    end
    if pendingDelete then
        pendingDelete = nil
        return
    end
    closeViewfinder()
    local token = AeternaCore.requestFocus({ cursor = true, keyboard = true })
    if not token then return end
    gallery = { token = token, ids = idSet(items) }
    sendSetup()
    send({ type = 'gallery:show', items = items, base = photoBase() })
end)

--------------------------------------------------------------------------------
-- NUI callbacks: close {}, open {id}, delete {id}, escape {}. Ids must be in the list last sent.
--------------------------------------------------------------------------------

local EMPTY_SCHEMA = { type = 'table', extra = false, fields = {} }
local ID_SCHEMA = { type = 'table', extra = false, fields = {
    id = { type = 'string', minLen = 32, maxLen = 32, pattern = '^[0-9a-f]+$' },
} }

local function knownId(data)
    local ok = AeternaCore.validate(data, ID_SCHEMA)
    return ok and gallery and not gallery.paused and Ids.isId(data.id) and gallery.ids[data.id] == true
end

local function closeAny()
    if gallery and not gallery.paused then closeGallery() end
    if vf and not vf.paused and not vf.capture and not vf.test then closeViewfinder() end
end

RegisterNUICallback('close', function(data, cb)
    cb({})
    if AeternaCore.validate(data, EMPTY_SCHEMA) then closeAny() end
end)

RegisterNUICallback('escape', function(data, cb)
    cb({})
    if AeternaCore.validate(data, EMPTY_SCHEMA) then closeAny() end
end)

RegisterNUICallback('open', function(data, cb)
    cb({ ok = knownId(data) and true or false })
end)

RegisterNUICallback('delete', function(data, cb)
    local ok = knownId(data)
    cb({ ok = ok and true or false })
    if not ok then return end
    pendingDelete = data.id
    TriggerServerEvent('aeterna_camera:sv:delete', { id = data.id })
end)

--------------------------------------------------------------------------------
-- Focus: lost closes; an overlay pauses (input ignored, screen kept) until it resumes.
--------------------------------------------------------------------------------

AddEventHandler('aeterna_core:focusLost', function(owner, token)
    if owner ~= RES then return end
    if vf and vf.token == token then
        vf.token = nil
        closeViewfinder()
    end
    if gallery and gallery.token == token then
        gallery.token = nil
        closeGallery()
    end
end)

AddEventHandler('aeterna_core:focusPaused', function(owner)
    if owner ~= RES then return end
    if vf then vf.paused = true end
    if gallery then gallery.paused = true end
end)

AddEventHandler('aeterna_core:focusResumed', function(owner, token)
    if owner ~= RES then return end
    if vf and vf.token == token then vf.paused = false end
    if gallery and gallery.token == token then gallery.paused = false end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RES then return end
    if vf then
        restoreAfterCapture()
        V.stop()
        media(false)
    end
end)

--------------------------------------------------------------------------------
-- Self-test (client): the viewfinder eye test opens, switches and closes the viewfinder, then asks the person.
--------------------------------------------------------------------------------

local testRun = nil

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if name ~= VIEWFINDER_TEST then return end
    if vf or gallery then
        exports.aeterna_core:reportSelftest(runId, name, false, 'viewfinder or gallery already open')
        return
    end
    testRun = runId
    CreateThread(function()
        local started = GetGameTimer()
        for _, step in ipairs(ST.VIEWFINDER_STEPS) do
            local waitMs = step.at - (GetGameTimer() - started)
            if waitMs > 0 then Wait(waitMs) end
            if testRun ~= runId then return end
            if step.action == 'open' then
                if not openViewfinder({ count = 0, cap = cfg.perCharacter, test = true }) then
                    exports.aeterna_core:reportSelftest(runId, name, false, 'focus refused')
                    testRun = nil
                    return
                end
            elseif step.action == 'selfie' then
                if vf then
                    vf.mode = 'selfie'
                    V.setSelfie(true)
                    send({ type = 'vf:mode', mode = 'selfie' })
                end
            elseif step.action == 'close' then
                closeViewfinder()
            end
        end
        if testRun == runId then
            exports.aeterna_core:reportSelftest(runId, name, 'ready', 'viewfinder opened, switched and closed')
        end
    end)
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if name ~= VIEWFINDER_TEST or testRun ~= runId then return end
    testRun = nil
    if vf and vf.test then closeViewfinder() end
end)
