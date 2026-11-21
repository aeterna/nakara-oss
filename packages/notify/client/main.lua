-- aeterna_notify client: toasts (0.2: actions, merging, lifetime bar, sound), announcement and countdown banners,
-- history export, MOTD with KVP and focus lock (0.2: stays up while paused by a focus overlay), and aeterna_layout.

local L = NotifyLogic

local toastQueue = nil
local announceQueue = nil
local announceTimer = nil
local countdownView = nil
local history = nil
local motdController = nil
local motdOpen = false
local motdPaused = false
local focusToken = nil
local localeReady = false
local layoutPlaces = {
    toasts = nil,
    announce = nil,
}

local ACTION_COMMANDS = { '+aeterna_notify_action1', '+aeterna_notify_action2' }

local LOCALE_KEYS = {
    'notify.motd.dismiss',
    'notify.motd.continue',
    'notify.announce.title',
    'notify.announce.by',
    'notify.announce.console',
    'notify.announce.usage',
    'notify.announce.denied',
    'notify.action.unbound',
    'notify.countdown.title',
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

local function callerName()
    local n = GetInvokingResource()
    if type(n) == 'string' and n ~= '' then
        return n
    end
    return selfName()
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

local function nowMs()
    return GetGameTimer()
end

local function nowSeconds()
    if AeternaCore and type(AeternaCore.time) == 'table' and type(AeternaCore.time.now) == 'function' then
        return AeternaCore.time.now()
    end
    return 0
end

local function cfgSection(name)
    return type(Config) == 'table' and type(Config[name]) == 'table' and Config[name] or {}
end

local function currentToastPosition()
    return L.normalizePosition(cfgSection('toast').position or 'top-left')
end

--------------------------------------------------------------------------------
-- Sound setting (client KVP aeterna_notify:settings:v1)
--------------------------------------------------------------------------------

local function ownerAllowsSound()
    return cfgSection('sound').enabled == true
end

local function soundSettings()
    return L.createSettings({
        get = function()
            if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.get) == 'function' then
                return AeternaCore.kvp.get('settings', 1, nil)
            end
            return nil
        end,
        set = function(value)
            if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.set) == 'function' then
                AeternaCore.kvp.set('settings', 1, value)
            end
        end,
        playerDefault = cfgSection('sound').playerDefault == true,
    })
end

local function soundAllowed()
    return L.soundGate(ownerAllowsSound(), soundSettings():sound(), true)
end

local function playToastSound(toastType)
    local byType = cfgSection('sound').byType
    local entry = type(byType) == 'table' and byType[toastType] or nil
    if type(entry) ~= 'table' or type(entry.name) ~= 'string' or type(entry.set) ~= 'string' then
        return
    end
    if type(PlaySoundFrontend) == 'function' then
        PlaySoundFrontend(-1, entry.name, entry.set, true)
    end
end

--------------------------------------------------------------------------------
-- Theme, locale and focus
--------------------------------------------------------------------------------

local function themeMessage()
    if AeternaCore and type(AeternaCore.themeMessage) == 'function' then
        local ok, msg = pcall(AeternaCore.themeMessage)
        if ok and type(msg) == 'table' then
            return msg
        end
    end
    local ok, href = pcall(function()
        return exports.aeterna_core:themeHref()
    end)
    if ok then
        return { type = 'aeterna:theme', href = href }
    end
    return nil
end

local function syncThemeAndLocale()
    if not localeReady then
        local strings = {}
        for i = 1, #LOCALE_KEYS do
            local k = LOCALE_KEYS[i]
            strings[k] = translate(k)
        end
        sendUi({ type = 'locale', strings = strings })
        local theme = themeMessage()
        if theme then
            sendUi(theme)
        end
        sendUi({ type = 'settings', sound = soundAllowed() })
        localeReady = true
    end
end

local function acquireFocus()
    local ok, tok = pcall(function()
        return AeternaCore.requestFocus({
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
        AeternaCore.releaseFocus(tok)
    end)
end

--------------------------------------------------------------------------------
-- History (memory only)
--------------------------------------------------------------------------------

local function getHistory()
    if not history then
        history = L.createHistory(cfgSection('history').max)
    end
    return history
end

local function recordHistory(entry)
    local stored = getHistory():upsert(entry)
    if stored then
        TriggerEvent('aeterna_notify:added', stored)
    end
end

--------------------------------------------------------------------------------
-- Toasts
--------------------------------------------------------------------------------

local function getToastQueue()
    if not toastQueue then
        local t = cfgSection('toast')
        toastQueue = L.createToastQueue({
            max = t.max,
            defaultDuration = t.defaultDuration,
            actionDuration = t.actionDuration,
            merge = t.merge,
            warn = logWarn,
        })
    end
    return toastQueue
end

local function actionKeyLabels()
    local unbound = translate('notify.action.unbound')
    local labels = {}
    for i = 1, #ACTION_COMMANDS do
        local raw = nil
        if type(GetControlInstructionalButton) == 'function' and type(GetHashKey) == 'function' then
            local ok, res = pcall(function()
                return GetControlInstructionalButton(2, GetHashKey(ACTION_COMMANDS[i]) | 0x80000000, true)
            end)
            if ok then raw = res end
        end
        labels[i] = L.formatKeyLabel(raw, unbound)
    end
    return labels
end

local function nuiToast(item)
    return {
        id = item.key,
        toastId = item.toastId,
        title = item.title,
        description = item.description,
        type = item.type,
        duration = item.duration,
        icon = item.icon,
        actions = item.actions,
        count = item.count,
        countLabel = L.formatCount(item.count),
    }
end

-- ctx = { owner, origin = 'client'|'server', toastId? }
local function addToast(opts, ctx, sourceLabel)
    local c = type(ctx) == 'table' and ctx or {}
    local q = getToastQueue()
    local ok, err, res = q:push(opts, {
        now = nowMs(),
        owner = c.owner or selfName(),
        origin = c.origin,
        toastId = c.toastId,
        soundAllowed = soundAllowed(),
    })
    if not ok then
        logWarn((sourceLabel or 'notify') .. ' dropped invalid toast opts', { err = err })
        return false, err
    end
    syncThemeAndLocale()
    local item = res.toast
    if res.merged then
        sendUi({
            type = 'toast:merge',
            id = item.key,
            count = item.count,
            countLabel = L.formatCount(item.count),
        })
    else
        sendUi({
            type = 'toast:add',
            toast = nuiToast(item),
            toastId = item.toastId,
            lifetime = cfgSection('toast').lifetimeBar ~= false,
            keys = item.actions and actionKeyLabels() or nil,
            replaced = res.replaced,
            max = q.max,
            position = currentToastPosition(),
            place = layoutPlaces.toasts,
        })
    end
    if res.sound then
        playToastSound(item.type)
    end
    if item.history then
        recordHistory(L.historyFromToast(item, nowSeconds()))
    end
    return true, nil, item
end

-- Pressing an action closes the toast; the press goes to the resource that created it.
local function pressAction(item, actionId)
    getToastQueue():removeItem(item)
    sendUi({ type = 'toast:clear', id = item.key })
    if item.origin == 'server' then
        TriggerServerEvent('aeterna_notify:sv:action', { toastId = item.toastId, action = actionId })
    else
        TriggerEvent('aeterna_notify:action', { owner = item.owner, toastId = item.toastId, action = actionId })
    end
end

local function pressNewest(index)
    local item = getToastQueue():newestWithActions(nowMs())
    if not item or not item.actions[index] then
        return
    end
    pressAction(item, item.actions[index].id)
end

--------------------------------------------------------------------------------
-- Announcements and countdown banners
--------------------------------------------------------------------------------

local function clearAnnounceTimer()
    if announceTimer and type(ClearTimeout) == 'function' then
        ClearTimeout(announceTimer)
    end
    announceTimer = nil
end

local function getAnnounceQueue()
    if announceQueue then
        return announceQueue
    end
    local maxWaiting = 5
    if tonumber(cfgSection('announce').queue) then
        maxWaiting = math.max(0, math.floor(tonumber(cfgSection('announce').queue)))
    end

    local function scheduleNext(durationMs)
        if type(SetTimeout) ~= 'function' then
            return
        end
        clearAnnounceTimer()
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
            recordHistory(L.historyFromBanner('announce', item, selfName(), nowSeconds()))
        end,
    })
    return announceQueue
end

local function endCountdownView(countdownId)
    local view = countdownView
    if not view or (countdownId ~= nil and view.id ~= countdownId) then
        return
    end
    if view.timer and type(ClearTimeout) == 'function' then
        ClearTimeout(view.timer)
    end
    countdownView = nil
    sendUi({ type = 'countdown:hide', countdownId = view.id })
    getAnnounceQueue():resume()
end

local function showCountdown(clean)
    syncThemeAndLocale()
    local aq = getAnnounceQueue()
    if not aq:isPaused() then
        aq:pause()
        clearAnnounceTimer()
    end
    if countdownView and countdownView.timer and type(ClearTimeout) == 'function' then
        ClearTimeout(countdownView.timer)
    end
    local showMs = L.countdownShowMs(clean.remainingMs)
    local view = { id = clean.countdownId }
    countdownView = view
    if type(SetTimeout) == 'function' then
        view.timer = SetTimeout(showMs, function()
            if countdownView == view then
                view.timer = nil
                endCountdownView(view.id)
            end
        end)
    end
    sendUi({
        type = 'countdown:show',
        countdown = clean,
        showMs = showMs,
        place = layoutPlaces.announce,
    })
    recordHistory(L.historyFromBanner('countdown', clean, selfName(), nowSeconds()))
end

--------------------------------------------------------------------------------
-- MOTD
--------------------------------------------------------------------------------

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
    local enabled = cfgSection('motd').enabled ~= false
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
    motdPaused = false
    sendUi({
        type = 'motd:show',
        motd = motd,
    })
    return true
end

-- While another resource holds focus through core's overlay the card stays up and ignores input.
local function closeMotd(dismiss)
    if not motdOpen or motdPaused then return end
    motdOpen = false
    local ctrl = getMotdController()
    ctrl:markClosed(dismiss == true, setSeenMotdVersion)
    sendUi({ type = 'motd:hide' })
    dropFocus()
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

--------------------------------------------------------------------------------
-- Client exports
--------------------------------------------------------------------------------

exports('notify', function(opts)
    local ok, err, item = addToast(opts, { owner = callerName(), origin = 'client' }, 'notify')
    if not ok then
        return false, err
    end
    return item.toastId
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

exports('history', function(limit)
    return getHistory():list(limit)
end)

exports('clearHistory', function()
    getHistory():clear()
    return nil
end)

--------------------------------------------------------------------------------
-- Server -> client net events
--------------------------------------------------------------------------------

RegisterNetEvent('aeterna_notify:cl:toast', function(opts)
    local owner = nil
    local toastId = nil
    if type(opts) == 'table' then
        if type(opts.owner) == 'string' then
            owner = L.textClean(opts.owner, 64)
        end
        toastId = opts.toastId
    end
    addToast(opts, { owner = owner, origin = 'server', toastId = toastId }, 'aeterna_notify:cl:toast')
end)

RegisterNetEvent('aeterna_notify:cl:announce', function(opts)
    local ok, err, clean = L.validateAnnounceOpts(opts)
    if not ok then
        logWarn('aeterna_notify:cl:announce dropped', { err = err })
        return
    end
    getAnnounceQueue():push(clean)
end)

RegisterNetEvent('aeterna_notify:cl:countdown', function(msg)
    local ok, err, clean = L.validateCountdownMessage(msg)
    if not ok then
        logWarn('aeterna_notify:cl:countdown dropped', { err = err })
        return
    end
    if clean.hide then
        endCountdownView(clean.countdownId)
        return
    end
    showCountdown(clean)
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    tryShowMotd()
end)

--------------------------------------------------------------------------------
-- Commands and keys
--------------------------------------------------------------------------------

RegisterCommand('aeterna_notify_sound', function()
    if not ownerAllowsSound() then
        addToast({ title = translate('notify.sound.disabled'), type = 'info' }, { owner = selfName() }, 'aeterna_notify_sound')
        return
    end
    local on = soundSettings():toggle()
    sendUi({ type = 'settings', sound = on })
    addToast({
        title = translate(on and 'notify.sound.on' or 'notify.sound.off'),
        type = 'success',
    }, { owner = selfName() }, 'aeterna_notify_sound')
end, false)

RegisterCommand('+aeterna_notify_action1', function()
    pressNewest(1)
end, false)

RegisterCommand('-aeterna_notify_action1', function() end, false)

RegisterCommand('+aeterna_notify_action2', function()
    pressNewest(2)
end, false)

RegisterCommand('-aeterna_notify_action2', function() end, false)

if AeternaCore and type(AeternaCore.key) == 'function' then
    AeternaCore.key('+aeterna_notify_action1', 'notify.key.action1')
    AeternaCore.key('+aeterna_notify_action2', 'notify.key.action2')
end

--------------------------------------------------------------------------------
-- Base-game spawn and focus handlers
--------------------------------------------------------------------------------

AddEventHandler('playerSpawned', function()
    if isQbxStarted() then return end
    tryShowMotd()
end)

local function ownsFocusEvent(owner, token)
    if owner ~= selfName() then return false end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return false end
    return true
end

AddEventHandler('aeterna_core:focusPaused', function(owner, token)
    if not ownsFocusEvent(owner, token) then return end
    if motdOpen then
        motdPaused = true
    end
end)

AddEventHandler('aeterna_core:focusResumed', function(owner, token)
    if not ownsFocusEvent(owner, token) then return end
    motdPaused = false
end)

AddEventHandler('aeterna_core:focusLost', function(owner, token)
    if owner ~= nil and owner ~= selfName() then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    focusToken = nil
    motdPaused = false
    if motdOpen then
        motdOpen = false
        local ctrl = getMotdController()
        ctrl:markClosed(false)
        sendUi({ type = 'motd:hide' })
    end
end)

--------------------------------------------------------------------------------
-- Optional aeterna_layout protocol (local client events only)
--------------------------------------------------------------------------------

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

--------------------------------------------------------------------------------
-- NUI callbacks
--------------------------------------------------------------------------------

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

-- Validated against the toast on screen before it is forwarded.
RegisterNUICallback('toastAction', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    local ok, err, press = L.validateActionPress(data)
    if not ok then
        logWarn('toastAction invalid payload', { err = err })
        return
    end
    local item = getToastQueue():findAction(press.toastId, press.action, nowMs())
    if not item then
        return
    end
    pressAction(item, press.action)
end)

registerLayoutElements()
