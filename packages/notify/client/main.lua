-- aeterna_notify client: toasts, announcement banner queue, MOTD with KVP and focus lock, and aeterna_layout protocol.

local L = NotifyLogic

local toastQueue = nil
local announceQueue = nil
local announceTimer = nil
local motdController = nil
local motdOpen = false
local focusToken = nil
local localeReady = false
local layoutPlaces = {
    toasts = nil,
    announce = nil,
}

local LOCALE_KEYS = {
    'notify.motd.dismiss',
    'notify.motd.continue',
    'notify.announce.title',
    'notify.announce.by',
    'notify.announce.console',
    'notify.announce.usage',
    'notify.announce.denied',
}

local function selfName()
    if type(GetCurrentResourceName) == 'function' then
        local n = GetCurrentResourceName()
        if type(n) == 'string' and n ~= '' then
            return n
        end
    end
    return 'aeterna_notify'
end

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local function translate(key, vars)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key, vars)
    end
    if Locales and Locales.en and Locales.en[key] then
        return Locales.en[key]
    end
    return key
end

local function sendUi(msg)
    if type(SendNUIMessage) == 'function' then
        SendNUIMessage(msg)
    end
end

local function currentToastPosition()
    local pos = type(Config) == 'table' and type(Config.toast) == 'table' and Config.toast.position or 'top-left'
    return L.normalizePosition(pos)
end

local function syncThemeAndLocale()
    if not localeReady then
        local strings = {}
        for i = 1, #LOCALE_KEYS do
            local k = LOCALE_KEYS[i]
            strings[k] = translate(k)
        end
        sendUi({ type = 'locale', strings = strings })
        local ok, href = pcall(function()
            return exports.aeterna_core:themeHref()
        end)
        if ok then
            sendUi({ type = 'aeterna:theme', href = href })
        end
        localeReady = true
    end
end

local function acquireFocus()
    local ok, tok = pcall(function()
        return exports.aeterna_core:requestFocus({
            cursor = true,
            keyboard = true,
            keepGameInput = false,
        })
    end)
    if ok and type(tok) == 'string' and tok ~= '' then
        focusToken = tok
        return tok
    end
    focusToken = nil
    return nil
end

local function dropFocus()
    if not focusToken then return end
    local tok = focusToken
    focusToken = nil
    pcall(function()
        exports.aeterna_core:releaseFocus(tok)
    end)
end

local function getToastQueue()
    if not toastQueue then
        local cfg = type(Config) == 'table' and Config.toast or nil
        toastQueue = L.createToastQueue(cfg)
    end
    return toastQueue
end

local function getAnnounceQueue()
    if announceQueue then
        return announceQueue
    end
    local maxWaiting = 5
    if type(Config) == 'table' and type(Config.announce) == 'table' and tonumber(Config.announce.queue) then
        maxWaiting = math.max(0, math.floor(tonumber(Config.announce.queue)))
    end

    local function scheduleNext(durationMs)
        if type(SetTimeout) ~= 'function' then
            return
        end
        if announceTimer and type(ClearTimeout) == 'function' then
            ClearTimeout(announceTimer)
        end
        announceTimer = SetTimeout(durationMs, function()
            announceTimer = nil
            if announceQueue then
                announceQueue:next()
            end
        end)
    end

    announceQueue = L.createAnnounceQueue({
        max = maxWaiting,
        warn = logWarn,
        onShow = function(item)
            syncThemeAndLocale()
            sendUi({
                type = 'announce:show',
                announce = item,
                place = layoutPlaces.announce,
            })
            scheduleNext(item.duration)
        end,
    })
    return announceQueue
end

local function getSeenMotdVersion()
    local raw = nil
    if type(GetResourceKvpString) == 'function' then
        raw = GetResourceKvpString('aeterna_notify:motd_seen:v1')
    end
    if type(raw) == 'string' and raw ~= '' and raw:sub(1, 1) ~= '"' then
        return L.textClean(raw, 40)
    end
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.get) == 'function' then
        local val = AeternaCore.kvp.get('motd_seen', 1, nil)
        if type(val) == 'string' then
            return L.textClean(val, 40)
        end
        return nil
    end
    if type(raw) == 'string' and raw ~= '' and type(json) == 'table' and type(json.decode) == 'function' then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'string' then
            return L.textClean(decoded, 40)
        end
    end
    return nil
end

local function setSeenMotdVersion(version)
    if type(version) ~= 'string' then return end
    local cleanVer = L.textClean(version, 40)
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.set) == 'function' then
        AeternaCore.kvp.set('motd_seen', 1, cleanVer)
    elseif type(SetResourceKvp) == 'function' then
        local encoded = (type(json) == 'table' and type(json.encode) == 'function') and json.encode(cleanVer) or cleanVer
        SetResourceKvp('aeterna_notify:motd_seen:v1', encoded)
    end
end

local function getMotdController()
    if motdController then
        return motdController
    end
    local enabled = true
    if type(Config) == 'table' and type(Config.motd) == 'table' and Config.motd.enabled == false then
        enabled = false
    end
    local rawJson = nil
    if enabled and type(LoadResourceFile) == 'function' then
        rawJson = LoadResourceFile(selfName(), 'config/motd.json')
    end
    motdController = L.createMotdController({
        enabled = enabled,
        rawJson = rawJson,
        decode = type(json) == 'table' and json.decode or nil,
        warn = logWarn,
    })
    return motdController
end

local function tryShowMotd()
    if motdOpen then
        return false
    end
    local ctrl = getMotdController()
    local seen = getSeenMotdVersion()
    if not ctrl:shouldShow(seen) then
        return false
    end
    local motd = ctrl:getMotd()
    syncThemeAndLocale()
    if not acquireFocus() then
        return false
    end
    motdOpen = true
    sendUi({
        type = 'motd:show',
        motd = motd,
    })
    return true
end

local function closeMotd(dismiss)
    if not motdOpen then return end
    motdOpen = false
    local ctrl = getMotdController()
    ctrl:markClosed(dismiss == true, setSeenMotdVersion)
    sendUi({ type = 'motd:hide' })
    dropFocus()
end

local function addToast(opts, sourceLabel)
    local q = getToastQueue()
    local ok, err, res = q:push(opts)
    if not ok then
        logWarn((sourceLabel or 'notify') .. ' dropped invalid toast opts', { err = err })
        return false, err
    end
    syncThemeAndLocale()
    sendUi({
        type = 'toast:add',
        toast = res.toast,
        replaced = res.replaced,
        max = q.max,
        position = currentToastPosition(),
        place = layoutPlaces.toasts,
    })
    return true, nil, res.toast
end

local function isQbxStarted()
    return type(GetResourceState) == 'function' and GetResourceState('qbx_core') == 'started'
end

local function registerLayoutElements()
    local defs = L.buildLayoutDefs(currentToastPosition(), translate('notify.announce.title'))
    for i = 1, #defs do
        defs[i].owner = GetCurrentResourceName()
        TriggerEvent('aeterna_layout:add', defs[i])
    end
end

-- Client Exports
exports('notify', function(opts)
    local ok, err = addToast(opts, 'notify')
    return ok, err
end)

exports('clear', function(id)
    if id ~= nil and not L.isValidId(id, 32) then
        logWarn('clear refused invalid toast id', { id = tostring(id) })
        return false
    end
    getToastQueue():clear(id)
    sendUi({
        type = 'toast:clear',
        id = id,
    })
    return true
end)

exports('showMotd', function()
    return tryShowMotd()
end)

-- Server -> Client Net Events
RegisterNetEvent('aeterna_notify:cl:toast', function(opts)
    addToast(opts, 'aeterna_notify:cl:toast')
end)

RegisterNetEvent('aeterna_notify:cl:announce', function(opts)
    local ok, err, clean = L.validateAnnounceOpts(opts)
    if not ok then
        logWarn('aeterna_notify:cl:announce dropped', { err = err })
        return
    end
    getAnnounceQueue():push(clean)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    tryShowMotd()
end)

-- Base-game spawn & focus loss handlers
AddEventHandler('playerSpawned', function()
    if isQbxStarted() then return end
    tryShowMotd()
end)

AddEventHandler('aeterna_core:focusLost', function(owner, token)
    if owner ~= nil and owner ~= selfName() then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    focusToken = nil
    if motdOpen then
        motdOpen = false
        local ctrl = getMotdController()
        ctrl:markClosed(false)
        sendUi({ type = 'motd:hide' })
    end
end)

-- Optional aeterna_layout protocol (local client events only)
AddEventHandler('aeterna_layout:hello', function()
    registerLayoutElements()
end)

AddEventHandler('aeterna_layout:apply', function(owner, id, place)
    if owner ~= selfName() then return end
    if id ~= 'toasts' and id ~= 'announce' then return end
    local ok, err, cleanPlace = L.validateLayoutPlace(place)
    if not ok then
        logWarn('aeterna_layout:apply dropped invalid place', { id = id, err = err })
        return
    end
    layoutPlaces[id] = cleanPlace
    sendUi({
        type = 'layout:apply',
        id = id,
        place = cleanPlace,
        position = currentToastPosition(),
    })
end)

AddEventHandler('onResourceStop', function(resName)
    if resName == 'aeterna_layout' then
        layoutPlaces.toasts = nil
        layoutPlaces.announce = nil
        sendUi({
            type = 'layout:apply',
            id = 'toasts',
            place = nil,
            position = currentToastPosition(),
        })
        sendUi({
            type = 'layout:apply',
            id = 'announce',
            place = nil,
        })
    end
end)

-- NUI Callbacks
RegisterNUICallback('motdClose', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if type(data) ~= 'table' or type(data.dismiss) ~= 'boolean' then
        logWarn('motdClose invalid payload', { field = 'dismiss' })
        return
    end
    for k in pairs(data) do
        if k ~= 'dismiss' then
            logWarn('motdClose extra field', { field = tostring(k) })
            return
        end
    end
    closeMotd(data.dismiss)
end)

RegisterNUICallback('escape', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if data ~= nil and type(data) ~= 'table' then
        logWarn('escape invalid payload')
        return
    end
    closeMotd(false)
end)

registerLayoutElements()
