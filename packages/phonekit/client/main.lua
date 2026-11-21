-- client/main.lua -- aeterna_phonekit client: shell UI, NUI callbacks, KVP persistence,
-- focus coordination through aeterna_core, animation control, and aeterna_layout protocol.
-- 0.2: the held device and its fold, the battery shown by the server, the screen pulse, the ring card,
-- notification history pulled from aeterna_notify, contacts hooks and the exit contract's close key.

local L = PhoneLogic
local D = DeviceLogic
local H = HooksLogic
local Cfg = type(Config) == 'table' and Config or {}

local isOpen = false
local focusToken = nil
local activeScreenId = nil
local currentAppId = nil
local localeReady = false
local isHovering = false
local isTyping = false
local isPaused = false
local lastCloseAt = -1000

local layoutPlace = nil
-- true while a self-test shows a model other than the held one (the server must not hear its folds)
local displayOverride = false
local lastRefused = nil

-- 0.2 device state (the server owns it; the client only shows it)
local device = {
    model = D.MODELS[Cfg.singleModel] and Cfg.singleModel or 'slab',
    label = nil,
    fold = nil,
    voice = true,
    color = nil,
    devices = {},
}
device.fold = D.validateFold(device.model, nil, Cfg.cover ~= false)
local batteryState = { none = true }
local powerOn = true
local haveBattery = false
local mediaOwners = {}
local surfaceLevel = 'off'
local lastPulse = { level = 'off', at = -100000 }
local historyPulledAt = -100000
local layoutSize = nil

local LOCALE_KEYS = {
    'phonekit.key.open',
    'phonekit.home.title',
    'phonekit.back',
    'phonekit.app.calculator',
    'phonekit.app.notes',
    'phonekit.app.contacts',
    'phonekit.app.settings',
    'phonekit.notes.new',
    'phonekit.notes.empty',
    'phonekit.notes.full',
    'phonekit.notes.delete',
    'phonekit.contacts.new',
    'phonekit.contacts.empty',
    'phonekit.contacts.full',
    'phonekit.contacts.delete',
    'phonekit.settings.textSize',
    'phonekit.settings.normal',
    'phonekit.settings.large',
    'phonekit.settings.clock24',
    'phonekit.settings.layout',
    'phonekit.refused.default',
    'phonekit.model.keypad',
    'phonekit.model.burner',
    'phonekit.model.qwerty',
    'phonekit.model.slab',
    'phonekit.model.fold',
    'phonekit.model.pro',
    'phonekit.model.book',
    'phonekit.model.pad',
    'phonekit.lock.hint',
    'phonekit.lock.hintKeypad',
    'phonekit.cc.title',
    'phonekit.cc.devices',
    'phonekit.cc.active',
    'phonekit.history.title',
    'phonekit.history.empty',
    'phonekit.history.clear',
    'phonekit.cover.waiting',
    'phonekit.ring.answer',
    'phonekit.ring.decline',
    'phonekit.ring.busy',
    'phonekit.contacts.call',
    'phonekit.contacts.message',
    'phonekit.battery.low',
    'phonekit.battery.dead',
    'phonekit.battery.charging',
    'phonekit.refused.nodevice',
    'phonekit.refused.noapp',
}

local function selfName()
    if type(GetCurrentResourceName) == 'function' then
        local n = GetCurrentResourceName()
        if type(n) == 'string' and n ~= '' then
            return n
        end
    end
    return 'aeterna_phonekit'
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

local function gameTimer()
    return type(GetGameTimer) == 'function' and GetGameTimer() or 0
end

local function toast(key, kind)
    local msg = translate(key)
    pcall(function()
        exports.aeterna_notify:notify({
            title = msg,
            type = kind or 'error',
        })
    end)
end

local function currentPosition()
    if type(Cfg.position) == 'string' then
        return Cfg.position
    end
    return 'bottom-right'
end

local function syncThemeAndLocale()
    if not localeReady then
        local strings = {}
        for i = 1, #LOCALE_KEYS do
            local k = LOCALE_KEYS[i]
            strings[k] = translate(k)
        end
        local colorNames = { 'black', 'charcoal', 'graphite', 'silver', 'sand', 'blue', 'green', 'olive', 'orange' }
        for i = 1, #colorNames do
            local k = 'phonekit.color.' .. colorNames[i]
            strings[k] = translate(k)
        end
        sendUi({ type = 'locale', strings = strings })

        local ok, href = pcall(function()
            return exports.aeterna_core:themeHref()
        end)
        if ok and href then
            sendUi({ type = 'aeterna:theme', href = href })
        end
        localeReady = true
    end
end

local function getSavedSettings()
    local defaultSettings = {
        textSize = 'normal',
        clock24 = true,
    }
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.get) == 'function' then
        local s = AeternaCore.kvp.get('settings', 1, defaultSettings)
        if type(s) == 'table' then
            return {
                textSize = s.textSize == 'large' and 'large' or 'normal',
                clock24 = s.clock24 ~= false,
            }
        end
    end
    return defaultSettings
end

local function saveSetting(key, val)
    local s = getSavedSettings()
    if key == 'textSize' then
        s.textSize = (val == 'large') and 'large' or 'normal'
    elseif key == 'clock24' then
        s.clock24 = (val == true)
    end
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.set) == 'function' then
        AeternaCore.kvp.set('settings', 1, s)
    end
end

local function kvpGet(name, default)
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.get) == 'function' then
        return AeternaCore.kvp.get(name, 1, default)
    end
    return default
end

local function kvpSet(name, value)
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.set) == 'function' then
        AeternaCore.kvp.set(name, 1, value)
    end
end

local function getSavedNotes()
    local n = kvpGet('notes', {})
    return type(n) == 'table' and n or {}
end

local function getSavedContacts()
    local c = kvpGet('contacts', {})
    return type(c) == 'table' and c or {}
end

local function seenAt()
    return tonumber(kvpGet('seen', 0)) or 0
end

local contactsHook = H.createContactsHook({
    load = getSavedContacts,
    save = function(list) kvpSet('contacts', list) end,
    onChange = function() TriggerEvent('aeterna_phonekit:contactsChanged') end,
    encode = type(json) == 'table' and json.encode or nil,
})

local function modelInfo()
    return D.resolveModel(device.model, Cfg.models, { names = Cfg.names, t = translate, prop = Cfg.prop })
end

local function frameSize()
    return D.getFrameSize(device.model, device.fold)
end

local function registerLayoutElement()
    local w, h = frameSize()
    layoutSize = w .. 'x' .. h
    local defs = L.buildLayoutDefs(currentPosition(), translate('phonekit.home.title'), w, h)
    for i = 1, #defs do
        defs[i].owner = selfName()
        TriggerEvent('aeterna_layout:add', defs[i])
    end
end

-- 0.2 layout: re-add element `phone` whenever the held frame's size changes (same id: the saved place stays).
local function layoutSizeChanged()
    local w, h = frameSize()
    if layoutSize ~= w .. 'x' .. h then
        registerLayoutElement()
    end
end

local function builtinsForModel()
    local apps = modelInfo().apps
    local out = {}
    for _, id in ipairs({ 'calculator', 'notes', 'contacts', 'settings' }) do
        local enabled = not (type(Cfg.apps) == 'table' and Cfg.apps[id] == false)
        out[id] = enabled and D.isAppAllowed(apps, id, nil, device.model)
    end
    out.settings = true
    return out
end

local function deviceMessage()
    local info = modelInfo()
    return {
        type = 'device',
        model = device.model,
        label = device.label or info.label,
        fold = device.fold,
        voice = device.voice,
        color = device.color or info.colors[1],
        devices = device.devices,
        builtins = builtinsForModel(),
        cover = Cfg.cover ~= false,
    }
end

-- KeyboardEvent.code of the key bound to the open mapping, or nil with no key bound.
-- Reads the instructional-button text of the mapping hash ("t_F2", "t_M"); not verified on FXServer Enhanced.
local function openKeyCode()
    if type(GetControlInstructionalButton) ~= 'function' or type(GetHashKey) ~= 'function' then return nil end
    local ok, txt = pcall(function()
        return GetControlInstructionalButton(0, GetHashKey('+aeterna_phonekit_open') | 0x80000000, true)
    end)
    if not ok or type(txt) ~= 'string' then return nil end
    local key = txt:match('^t_(.+)$')
    if not key then return nil end
    if key:match('^F%d%d?$') then return key end
    if key:match('^%a$') then return 'Key' .. key:upper() end
    if key:match('^%d$') then return 'Digit' .. key end
    return nil
end

local function pullHistory(force)
    local now = gameTimer()
    if not force and now - historyPulledAt < 1000 then return end
    historyPulledAt = now
    local ok, entries = pcall(function()
        return exports.aeterna_notify:history(20)
    end)
    sendUi({ type = 'history', entries = (ok and type(entries) == 'table') and entries or {}, seenAt = seenAt() })
end

local function acquireFocus()
    local ok, tok = pcall(function()
        return AeternaCore.requestFocus({
            cursor = true,
            keyboard = true,
            keepGameInput = true,
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

local function closePhone()
    if not isOpen then return end
    isOpen = false
    isPaused = false
    activeScreenId = nil
    currentAppId = nil
    isHovering = false
    isTyping = false
    surfaceLevel = 'off'
    lastCloseAt = gameTimer()

    dropFocus()

    if Cfg.animation and PhoneAnim and type(PhoneAnim.stop) == 'function' then
        PhoneAnim.stop()
    end

    TriggerServerEvent('aeterna_phonekit:sv:close')
    sendUi({ type = 'shell:close' })
end

-- Returns what it did: 'closed', 'ignored', 'dead' or 'asked' (the self-tests read it).
local function requestOpenPhone()
    if isOpen then
        closePhone()
        return 'closed'
    end
    -- One key press reaches both the page and the game (keepGameInput): ignore an open right after a close.
    if gameTimer() - lastCloseAt < 300 then
        return 'ignored'
    end
    if not powerOn then
        toast('phonekit.battery.dead')
        return 'dead'
    end

    TriggerServerEvent('aeterna_phonekit:sv:open')
    return 'asked'
end

local function toggleFold()
    if not isOpen or not D.MODELS[device.model] or not D.MODELS[device.model].folds then return end
    if device.model == 'fold' and Cfg.cover == false then return end
    local nextFold = D.toggleFold(device.model, device.fold)
    if nextFold == device.fold then return end
    device.fold = nextFold
    sendUi({ type = 'fold', fold = nextFold })
    if not displayOverride then
        TriggerServerEvent('aeterna_phonekit:sv:fold', { state = nextFold })
    end
    layoutSizeChanged()
end

-- Server -> Client Net Events
RegisterNetEvent('aeterna_phonekit:cl:open', function(data)
    local apps = (data and type(data.apps) == 'table') and data.apps or {}
    local initialTime = nil
    if AeternaCore and AeternaCore.time and type(AeternaCore.time.parts) == 'function' then
        local p = AeternaCore.time.parts()
        if p then
            initialTime = { hour = p.hour, min = p.min, sec = p.sec, day = p.day, month = p.month, year = p.year }
        end
    end

    local settings = getSavedSettings()
    local hasLayout = type(GetResourceState) == 'function' and GetResourceState('aeterna_layout') == 'started'
    settings.hasLayout = hasLayout

    local openMsg = {
        type = 'shell:open',
        apps = apps,
        settings = settings,
        position = currentPosition(),
        place = layoutPlace,
        builtins = builtinsForModel(),
        time = initialTime,
        intents = (data and type(data.intents) == 'table') and data.intents or {},
        lockScreen = Cfg.lockScreen == true,
        itemMode = Cfg.devices == 'items',
    }

    if isOpen then
        sendUi(openMsg)
        return
    end

    syncThemeAndLocale()

    local tok = acquireFocus()
    if not tok then
        logWarn('aeterna_phonekit focus denied by aeterna_core')
        -- the server already counts the phone as open: tell it the phone did not open
        TriggerServerEvent('aeterna_phonekit:sv:close')
        return
    end

    isOpen = true
    isPaused = false
    activeScreenId = nil
    currentAppId = nil
    isTyping = false
    surfaceLevel = 'on'

    if Cfg.animation and PhoneAnim and type(PhoneAnim.start) == 'function' then
        PhoneAnim.PROP_MODEL = modelInfo().prop
        PhoneAnim.start()
    end

    sendUi(deviceMessage())
    sendUi({ type = 'closeKey', code = openKeyCode() })
    pullHistory(true)
    sendUi(openMsg)

    -- Send initial notes and contacts data to NUI
    sendUi({
        type = 'builtin:data',
        notes = getSavedNotes(),
        contacts = getSavedContacts(),
    })
end)

RegisterNetEvent('aeterna_phonekit:cl:screen', function(data)
    if not isOpen or type(data) ~= 'table' then return end
    activeScreenId = data.screenId
    currentAppId = data.id

    sendUi({
        type = 'screen:show',
        screenId = data.screenId,
        id = data.id,
        title = data.title,
        subtitle = data.subtitle,
        blocks = data.blocks or {},
        detailOf = data.detailOf,
        detailItem = data.detailItem,
    })
end)

RegisterNetEvent('aeterna_phonekit:cl:update', function(data)
    if not isOpen or type(data) ~= 'table' then return end
    sendUi({
        type = 'screen:update',
        screenId = data.screenId,
        patch = data.patch,
    })
end)

RegisterNetEvent('aeterna_phonekit:cl:badge', function(data)
    if type(data) ~= 'table' then return end
    sendUi({
        type = 'badge',
        id = data.id,
        count = data.count,
    })
end)

RegisterNetEvent('aeterna_phonekit:cl:banner', function(data)
    if not isOpen or type(data) ~= 'table' then return end
    sendUi({
        type = 'banner',
        id = data.id,
        title = data.title,
        body = data.body,
    })
end)

RegisterNetEvent('aeterna_phonekit:cl:refused', function(data)
    local reason = (type(data) == 'table' and type(data.reason) == 'string') and data.reason or 'phonekit.refused.default'
    lastRefused = reason
    toast(reason)
end)

RegisterNetEvent('aeterna_phonekit:cl:device', function(data)
    if type(data) ~= 'table' then return end
    if type(data.model) ~= 'string' or not D.MODELS[data.model] then
        -- No phone (item mode) or the active phone is gone: every surface closes.
        device.devices = {}
        closePhone()
        return
    end
    local sizeBefore = layoutSize
    device.model = data.model
    device.label = type(data.label) == 'string' and data.label or nil
    device.fold = D.validateFold(data.model, data.fold, Cfg.cover ~= false)
    device.voice = data.voice ~= false
    device.color = (type(data.color) == 'string' and data.color:match('^#%x%x%x%x%x%x$')) and data.color or nil
    device.devices = type(data.devices) == 'table' and data.devices or {}
    if isOpen then
        sendUi(deviceMessage())
    end
    layoutSizeChanged()
    if sizeBefore ~= layoutSize and isOpen then
        sendUi({ type = 'layout:apply', place = layoutPlace, position = currentPosition() })
    end
end)

RegisterNetEvent('aeterna_phonekit:cl:battery', function(data)
    if type(data) ~= 'table' then return end
    if data.none then
        batteryState = { none = true }
        haveBattery = false
    elseif type(data.pct) == 'number' then
        batteryState = { pct = math.max(0, math.min(100, math.floor(data.pct))), charging = data.charging == true }
        haveBattery = true
    else
        return
    end
    sendUi({ type = 'battery', pct = batteryState.pct, charging = batteryState.charging, none = batteryState.none })
end)

RegisterNetEvent('aeterna_phonekit:cl:power', function(data)
    if type(data) ~= 'table' or type(data.on) ~= 'boolean' then return end
    powerOn = data.on
    sendUi({ type = 'power', on = data.on })
    if not data.on then
        local wasOpen = isOpen
        closePhone()
        if wasOpen then
            toast('phonekit.battery.dead')
        end
    end
end)

RegisterNetEvent('aeterna_phonekit:cl:ring', function(data)
    if type(data) ~= 'table' or type(data.ringId) ~= 'string' then return end
    sendUi({ type = 'ring', ringId = data.ringId, id = data.id, title = data.title, body = data.body })
end)

RegisterNetEvent('aeterna_phonekit:cl:ringStop', function(data)
    if type(data) ~= 'table' then return end
    sendUi({ type = 'ringStop', ringId = data.ringId })
end)

RegisterNetEvent('aeterna_phonekit:cl:live', function(data)
    if type(data) ~= 'table' then return end
    sendUi({ type = 'live', id = data.id, text = data.text })
end)

-- Focus Loss Handler
AddEventHandler('aeterna_core:focusLost', function(owner, token)
    if owner ~= nil and owner ~= selfName() then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    closePhone()
end)

-- 0.2: a focus overlay pauses the phone (same screen, input ignored); resume gives it back.
AddEventHandler('aeterna_core:focusPaused', function(owner)
    if owner ~= selfName() or not isOpen then return end
    isPaused = true
    sendUi({ type = 'paused', on = true })
end)

AddEventHandler('aeterna_core:focusResumed', function(owner)
    if owner ~= selfName() or not isOpen then return end
    isPaused = false
    sendUi({ type = 'paused', on = false })
end)

-- notify fires this for every new or updated entry; refresh while the phone is open (at most once per second).
AddEventHandler('aeterna_notify:added', function()
    if isOpen then
        pullHistory(false)
    end
end)

local DISABLED_PHONE_CONTROLS = {
    24, 25, 257, 68, 69, 70, 92, 14, 15, 16, 17, 199, 200,
}

-- Ped State & Control Watcher
if type(CreateThread) == 'function' then
    CreateThread(function()
        while true do
            if isOpen and type(PlayerPedId) == 'function' then
                local ped = PlayerPedId()
                local dead = type(IsEntityDead) == 'function' and IsEntityDead(ped)
                local ragdoll = type(IsPedRagdoll) == 'function' and IsPedRagdoll(ped)
                local inWater = type(IsEntityInWater) == 'function' and IsEntityInWater(ped)
                if dead or ragdoll or inWater then
                    closePhone()
                end
            end
            if isOpen and type(DisableControlAction) == 'function' then
                for i = 1, #DISABLED_PHONE_CONTROLS do
                    DisableControlAction(0, DISABLED_PHONE_CONTROLS[i], true)
                end
            end
            if isOpen and isHovering and type(DisableControlAction) == 'function' then
                -- Disable mouse look controls while cursor is over the phone frame
                DisableControlAction(0, 1, true) -- LookLeftRight
                DisableControlAction(0, 2, true) -- LookUpDown
            end
            if isOpen and isTyping and type(DisableAllControlActions) == 'function' then
                DisableAllControlActions(0)
            end
            Wait(isOpen and 0 or 250)
        end
    end)

    -- 0.2 screen pulse: on every change, and every 30 s while not off. Also asks for the battery until the
    -- server has one (after join, a character load or a restart).
    CreateThread(function()
        local lastAsk = -100000
        while true do
            local level = 'off'
            if isOpen and surfaceLevel ~= 'off' then
                level = next(mediaOwners) ~= nil and 'media' or 'on'
            end
            local now = gameTimer()
            if level ~= lastPulse.level or (level ~= 'off' and now - lastPulse.at >= 30000) then
                lastPulse = { level = level, at = now }
                TriggerServerEvent('aeterna_phonekit:sv:screen', { level = level })
            end
            if Cfg.battery ~= false and not haveBattery and now - lastAsk >= 30000 then
                lastAsk = now
                TriggerServerEvent('aeterna_phonekit:sv:battery')
            end
            Wait(1000)
        end
    end)
end

-- Optional aeterna_layout protocol (local client events only)
AddEventHandler('aeterna_layout:hello', function()
    registerLayoutElement()
end)

AddEventHandler('aeterna_layout:apply', function(owner, id, place)
    if owner ~= selfName() or id ~= 'phone' then return end
    local ok, err, cleanPlace = L.validateLayoutPlace(place)
    if not ok then
        logWarn('aeterna_layout:apply dropped invalid place', { id = id, err = err })
        return
    end
    layoutPlace = cleanPlace
    sendUi({
        type = 'layout:apply',
        place = cleanPlace,
        position = currentPosition(),
    })
end)

AddEventHandler('onResourceStop', function(resName)
    mediaOwners[resName] = nil
    if resName == 'aeterna_layout' then
        layoutPlace = nil
        sendUi({
            type = 'layout:apply',
            place = nil,
            position = currentPosition(),
        })
    elseif resName == selfName() then
        if isOpen then
            closePhone()
        end
    end
end)

-- Commands & Key Bindings
RegisterCommand('aeterna_phonekit_open', function()
    requestOpenPhone()
end, false)

RegisterCommand('+aeterna_phonekit_open', function()
    requestOpenPhone()
end, false)

RegisterCommand('-aeterna_phonekit_open', function()
    -- Key release is a no-op
end, false)

RegisterCommand('aeterna_phonekit_fold', function()
    toggleFold()
end, false)

RegisterCommand('+aeterna_phonekit_fold', function()
    toggleFold()
end, false)

RegisterCommand('-aeterna_phonekit_fold', function()
    -- Key release is a no-op
end, false)

if AeternaCore and type(AeternaCore.key) == 'function' then
    AeternaCore.key('+aeterna_phonekit_open', 'phonekit.key.open')
    AeternaCore.key('+aeterna_phonekit_fold', 'phonekit.key.fold')
end

-- Client exports (0.2)
exports('isOpen', function()
    return isOpen
end)

exports('activity', function(kind, on)
    if kind ~= 'media' then return false end
    local owner = selfName()
    if type(GetInvokingResource) == 'function' then
        local inv = GetInvokingResource()
        if type(inv) == 'string' and inv ~= '' then owner = inv end
    end
    mediaOwners[owner] = on == true or nil
    return true
end)

exports('getContacts', function()
    return contactsHook:getContacts()
end)

exports('addContact', function(contact)
    local ok, reason = contactsHook:addContact(contact)
    if ok then
        sendUi({ type = 'builtin:data', contacts = getSavedContacts() })
        return true
    end
    return false, reason
end)

-- NUI Callbacks
RegisterNUICallback('tap', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if isPaused or type(data) ~= 'table' or type(data.id) ~= 'string' then return end

    local id = data.id
    local owner = type(data.owner) == 'string' and data.owner or ''

    -- Check if it is a built-in app
    if id == 'calculator' or id == 'notes' or id == 'contacts' or id == 'settings' then
        currentAppId = id
        activeScreenId = nil
        return
    end

    local payload = { id = id, owner = owner }
    if type(data.intent) == 'table' and (data.intent.kind == 'tel' or data.intent.kind == 'sms')
        and H.isPhoneNumber(data.intent.number) then
        payload.intent = { kind = data.intent.kind, number = L.textClean(data.intent.number, 20) }
    end

    currentAppId = id
    TriggerServerEvent('aeterna_phonekit:sv:tap', payload)
end)

RegisterNUICallback('action', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if isPaused or type(data) ~= 'table' then return end

    local screenId = data.screenId
    local action = data.action
    local values = type(data.values) == 'table' and data.values or {}

    TriggerServerEvent('aeterna_phonekit:sv:action', {
        screenId = screenId,
        action = action,
        values = values,
    })
end)

RegisterNUICallback('back', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if isPaused then return end
    local sId = (type(data) == 'table' and type(data.screenId) == 'string') and data.screenId or activeScreenId
    if sId then
        activeScreenId = nil
        TriggerServerEvent('aeterna_phonekit:sv:action', {
            screenId = sId,
            action = '__back',
            values = {},
        })
    else
        currentAppId = nil
    end
end)

RegisterNUICallback('typing', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if type(data) == 'table' and type(data.on) == 'boolean' then
        isTyping = data.on
    end
end)

RegisterNUICallback('close', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if isPaused then return end
    closePhone()
end)

RegisterNUICallback('hover', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if type(data) == 'table' and type(data.hovering) == 'boolean' then
        isHovering = data.hovering
    end
end)

RegisterNUICallback('builtin:save', function(data, cb)
    if isPaused or type(data) ~= 'table' or type(data.app) ~= 'string' or type(data.data) ~= 'table' then
        if type(cb) == 'function' then cb({ ok = false, err = 'invalid payload' }) end
        return
    end

    local appName = data.app
    local items = data.data

    if appName == 'notes' then
        local store = L.createNotesStore()
        for i = 1, #items do
            local ok, errKey = store:save(items[i], type(json) == 'table' and json.encode or nil)
            if not ok then
                if type(cb) == 'function' then cb({ ok = false, err = translate(errKey) }) end
                return
            end
        end
        kvpSet('notes', store:list())
        if type(cb) == 'function' then cb({ ok = true, list = store:list() }) end

    elseif appName == 'contacts' then
        local ok, errOrList = contactsHook:replaceAll(items)
        if not ok then
            if type(cb) == 'function' then cb({ ok = false, err = translate(errOrList) }) end
            return
        end
        if type(cb) == 'function' then cb({ ok = true, list = errOrList }) end

    else
        if type(cb) == 'function' then cb({ ok = false, err = 'unknown app' }) end
    end
end)

RegisterNUICallback('settings', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if isPaused or type(data) ~= 'table' or type(data.key) ~= 'string' then return end

    if data.key == 'layout' then
        ExecuteCommand('aeterna_layout')
    else
        saveSetting(data.key, data.value)
    end
end)

-- 0.2 NUI callbacks
RegisterNUICallback('fold', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if isPaused or type(data) ~= 'table' or (data.state ~= 'open' and data.state ~= 'closed') then return end
    if data.state ~= device.fold then
        toggleFold()
    end
end)

RegisterNUICallback('device', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if isPaused or type(data) ~= 'table' or type(data.id) ~= 'string' or #data.id < 1 or #data.id > 64 then return end
    TriggerServerEvent('aeterna_phonekit:sv:device', { id = data.id })
end)

RegisterNUICallback('ring', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if isPaused or type(data) ~= 'table' or type(data.ringId) ~= 'string' or #data.ringId > 24
        or type(data.answer) ~= 'boolean' then
        return
    end
    if data.ringId == PhoneSelftest.RING_ID then
        -- the self-test ring card is drawn by the page only; nothing on the server rings
        sendUi({ type = 'ringStop', ringId = data.ringId })
        return
    end
    TriggerServerEvent('aeterna_phonekit:sv:ring', { ringId = data.ringId, answer = data.answer })
end)

RegisterNUICallback('seen', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if type(data) ~= 'table' or type(data.at) ~= 'number' or data.at ~= data.at or data.at < 0 then return end
    kvpSet('seen', math.floor(data.at))
    pullHistory(true)
end)

RegisterNUICallback('screen', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if type(data) ~= 'table' or (data.level ~= 'off' and data.level ~= 'on') then return end
    surfaceLevel = isOpen and data.level or 'off'
    if isOpen and data.level == 'on' then
        pullHistory(false)
    end
end)

--------------------------------------------------------------------------------
-- Self-tests (spec § Self-tests (0.2)): ped, eye and client mock rows. Pass rules and skips live in
-- shared/logic/selftest.lua; this part only drives the phone and the page and reads them back.
--------------------------------------------------------------------------------

local PS = PhoneSelftest
local selftest = nil -- the test in flight: { runId, name, touched, saved, badge, ring }
local probes, probeSeq = {}, 0
local contactsChangedCount = 0

AddEventHandler('aeterna_phonekit:contactsChanged', function()
    contactsChangedCount = contactsChangedCount + 1
end)

local function fromCore()
    return type(GetInvokingResource) == 'function' and GetInvokingResource() == 'aeterna_core'
end

-- Client KVP key of an AeternaCore.kvp name (same rule as aeterna_core's kvp module).
local function kvpDelete(name)
    local mod = AeternaCoreLogic and AeternaCoreLogic.kvp
    local key = mod and mod.keyFor and mod.keyFor(selfName(), name, 1) or ('aeterna_phonekit:' .. name .. ':v1')
    DeleteResourceKvp(key)
end

local function reportTest(runId, name, ok, detail, extra)
    local sent, err = pcall(function() return exports.aeterna_core:reportSelftest(runId, name, ok, detail, extra) end)
    if not sent then logWarn('reportSelftest failed', { name = name, err = tostring(err) }) end
end

local function waitFor(fn, ms)
    local deadline = gameTimer() + ms
    while not fn() do
        if gameTimer() >= deadline then return false end
        Wait(50)
    end
    return true
end

local function pedReady()
    if type(PlayerPedId) ~= 'function' or type(DoesEntityExist) ~= 'function' then return false end
    local ped = PlayerPedId()
    return ped ~= nil and ped ~= 0 and DoesEntityExist(ped) == true
end

-- Opens the phone through the normal path (server gate, focus). `fresh` closes an open phone first so the open
-- runs from scratch (the lock screen is decided on open). Returns true, or false and the refusal.
-- Every helper below returns at once when core has ended the test (t.ended): a timed-out test must not change the
-- phone after endSelftest put it back.
local function openForTest(t, fresh)
    if t.ended then return false, 'ended' end
    t.touched = true
    if isOpen and fresh then closePhone() end
    if isOpen then return true end
    waitFor(function() return t.ended or gameTimer() - lastCloseAt >= 320 end, 1000)
    for _ = 1, 2 do
        if t.ended then return false, 'ended' end
        lastRefused = nil
        requestOpenPhone()
        waitFor(function() return t.ended or isOpen or lastRefused ~= nil end, 1500)
        if t.ended then
            -- the open landed after the end: put the phone away again
            if isOpen then closePhone() end
            return false, 'ended'
        end
        if isOpen then return true end
        if lastRefused then return false, lastRefused end
    end
    return false, 'timeout'
end

-- Asks the page for its state after `op` ('state', 'key', 'cc'); nil when it does not answer within 1 s.
local function probe(t, op, extra)
    if t.ended then return nil end
    probeSeq = probeSeq + 1
    local id = probeSeq
    local msg = { type = 'selftest', op = op, id = id }
    for k, v in pairs(extra or {}) do msg[k] = v end
    sendUi(msg)
    if not waitFor(function() return probes[id] ~= nil end, 1000) then return nil end
    local r = probes[id]
    probes[id] = nil
    return r
end

RegisterNUICallback('selftest', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    local id = type(data) == 'table' and math.tointeger(tonumber(data.id)) or nil
    if selftest and id and id >= 1 and id <= probeSeq then probes[id] = data end
end)

local function saveDisplay(t)
    if not t.saved then
        t.saved = { model = device.model, label = device.label, fold = device.fold, voice = device.voice,
            color = device.color }
    end
end

-- Shows another model on the page only; the held phone on the server is unchanged.
local function showModel(t, model, fold)
    if t.ended then return end
    saveDisplay(t)
    displayOverride = model ~= t.saved.model
    device.model = model
    device.label = nil
    device.fold = D.validateFold(model, fold, Cfg.cover ~= false)
    device.voice = D.MODELS[model].calls ~= false
    device.color = nil
    sendUi(deviceMessage())
end

-- Folds on the page only (no sv:fold, nothing saved), then waits out the ~260 ms fold animation.
local function pageFold(t, fold)
    if t.ended then return end
    saveDisplay(t)
    device.fold = fold
    sendUi({ type = 'fold', fold = fold })
    Wait(350)
end

local function showScreen(t, screenId, spec)
    if t.ended then return end
    sendUi({ type = 'screen:show', screenId = screenId, id = PS.APP_ID, title = translate('phonekit.selftest.screen'),
        blocks = spec.blocks, detailOf = spec.detailOf, detailItem = spec.detailItem })
end

local function textScreen()
    return { blocks = { { id = 'note', type = 'text', label = translate('phonekit.selftest.screen') } } }
end

local function endSelftest()
    local t = selftest
    selftest = nil
    probes = {}
    if not t then return end
    t.ended = true
    if t.badge then sendUi({ type = 'badge', id = 'settings', count = 0 }) end
    if t.ring then sendUi({ type = 'ringStop', ringId = PS.RING_ID }) end
    if t.saved then
        device.model, device.label, device.fold = t.saved.model, t.saved.label, t.saved.fold
        device.voice, device.color = t.saved.voice, t.saved.color
        displayOverride = false
        sendUi(deviceMessage())
    end
    if t.touched and isOpen then closePhone() end
end

local function notOpened(reason)
    return 'fail', 'phone did not open: ' .. tostring(reason)
end

local function copyList(list)
    local out = {}
    for i, c in ipairs(type(list) == 'table' and list or {}) do
        local row = {}
        for k, v in pairs(c) do row[k] = v end
        out[i] = row
    end
    return out
end

local function sameList(a, b)
    if #a ~= #b then return false end
    for i = 1, #a do
        for k, v in pairs(a[i]) do if b[i][k] ~= v then return false end end
        for k, v in pairs(b[i]) do if a[i][k] ~= v then return false end end
    end
    return true
end

local function eyeModel(model)
    return function(t)
        local ok, reason = openForTest(t)
        if not ok then return notOpened(reason) end
        showModel(t, model, nil)
        return 'ready', ''
    end
end

local CLIENT_TESTS = {
    open_close_prop = function(t)
        local animation = Cfg.animation and true or false
        local ok, reason = openForTest(t, true)
        if not ok then return PS.propResult({ opened = false, reason = reason }) end
        waitFor(function() return PhoneAnim.prop() ~= nil end, animation and 1500 or 300)
        local prop = PhoneAnim.prop()
        local attached = prop ~= nil and type(IsEntityAttachedToEntity) == 'function'
            and IsEntityAttachedToEntity(prop, PlayerPedId()) == true
        closePhone()
        local gone = waitFor(function()
            return PhoneAnim.prop() == nil and not (prop and DoesEntityExist(prop))
        end, 1000)
        return PS.propResult({ opened = true, animation = animation, prop = prop ~= nil, attached = attached, gone = gone })
    end,

    fold_keeps_screen = function(t)
        local ok, reason = openForTest(t)
        if not ok then return PS.foldKept({ opened = false, reason = reason }) end
        showScreen(t, 'selftest_a', textScreen())
        local before = probe(t, 'state')
        local start = device.fold
        pageFold(t, D.toggleFold(device.model, start))
        pageFold(t, start)
        local after = probe(t, 'state')
        return PS.foldKept({ opened = true, expected = 'selftest_a', before = before and before.top,
            after = after and after.top })
    end,

    clamp_on_unfold = function(t)
        local ok, reason = openForTest(t)
        if not ok then return PS.clampInside({ opened = false, reason = reason }) end
        if device.fold ~= 'closed' then pageFold(t, 'closed') end
        pageFold(t, 'open')
        local r = probe(t, 'state')
        return PS.clampInside({ opened = true, fold = r and r.fold, vw = r and r.vw, vh = r and r.vh,
            rect = r and { x = r.x, y = r.y, w = r.w, h = r.h } })
    end,

    exit_contract = function(t)
        local ok, reason = openForTest(t)
        if not ok then return PS.exitResult({ opened = false, reason = reason }) end
        probe(t, 'key', { key = 'Escape', code = 'Escape' })
        local escClosed = waitFor(function() return not isOpen end, 1000)
        local reopenIgnored = escClosed and requestOpenPhone() == 'ignored'
        local keyCode = openKeyCode()
        local keyClosed = false
        if escClosed and reopenIgnored and keyCode then
            local reopened = openForTest(t)
            if reopened then
                local letter = keyCode:match('^Key(%u)$')
                local key = letter and letter:lower() or keyCode:match('^Digit(%d)$') or keyCode
                probe(t, 'key', { key = key, code = keyCode })
                keyClosed = waitFor(function() return not isOpen end, 1000)
            end
        end
        return PS.exitResult({ opened = true, escClosed = escClosed, reopenIgnored = reopenIgnored, keyCode = keyCode,
            keyClosed = keyClosed })
    end,

    eye_book_two_pane = function(t)
        local ok, reason = openForTest(t)
        if not ok then return notOpened(reason) end
        showModel(t, 'book', 'closed')
        local items = {}
        for i = 1, 3 do
            items[i] = { id = 'i' .. i, label = translate('phonekit.selftest.item', { n = i }) }
        end
        showScreen(t, 'selftest_list', { blocks = { { id = 'items', type = 'list', items = items } } })
        showScreen(t, 'selftest_detail', { detailOf = 'items', detailItem = 'i1',
            blocks = { { id = 'note', type = 'text', label = translate('phonekit.selftest.item', { n = 1 }) } } })
        pageFold(t, 'open')
        return 'ready', ''
    end,

    eye_fold_cover = function(t)
        local ok, reason = openForTest(t)
        if not ok then return notOpened(reason) end
        showModel(t, 'fold', 'open')
        showScreen(t, 'selftest_a', textScreen())
        pageFold(t, 'closed')
        return 'ready', ''
    end,

    eye_lock = function(t)
        -- a waiting badge before the open, so the lock screen comes up with one card
        t.badge = true
        sendUi({ type = 'badge', id = 'settings', count = 1 })
        local ok, reason = openForTest(t, true)
        if not ok then return notOpened(reason) end
        return 'ready', ''
    end,

    eye_control_centre = function(t)
        local ok, reason = openForTest(t)
        if not ok then return notOpened(reason) end
        probe(t, 'cc')
        return 'ready', ''
    end,

    ring_cover = function(t)
        local ok, reason = openForTest(t)
        if not ok then return notOpened(reason) end
        if device.fold ~= 'closed' then pageFold(t, 'closed') end
        t.ring = true
        sendUi({ type = 'ring', ringId = PS.RING_ID, id = PS.APP_ID, title = translate('phonekit.selftest.ring.title'),
            body = translate('phonekit.selftest.ring.body') })
        return 'ready', ''
    end,

    eye_battery_dead = function(t)
        -- the server set 0 % on aeterna_core:selftestStarted, before this test reached the client
        if not waitFor(function() return t.ended or not powerOn end, 1000) then
            return 'fail', 'phone still powered: the server did not set 0 %'
        end
        if t.ended then return 'fail', 'ended' end
        -- the open the person would try: refused on the client with the "battery dead" toast
        requestOpenPhone()
        return 'ready', ''
    end,

    contacts_hooks = function()
        local before = copyList(getSavedContacts())
        local count = contactsChangedCount
        local found, changes = false, 0
        local okRun, added, reason = pcall(function()
            local a, r = contactsHook:addContact({ name = 'Self-test', number = '000-0000' })
            for _, c in ipairs(contactsHook:getContacts()) do
                if c.name == 'Self-test' and c.number == '000-0000' then found = true end
            end
            return a, r
        end)
        changes = contactsChangedCount - count
        -- put the list back whatever happened above
        local changed = not sameList(copyList(getSavedContacts()), before)
        if changed then
            -- an empty book had no key before: delete it rather than store an empty list
            if #before == 0 then kvpDelete('contacts') else kvpSet('contacts', before) end
        end
        if changed or added then
            TriggerEvent('aeterna_phonekit:contactsChanged')
            sendUi({ type = 'builtin:data', contacts = getSavedContacts() })
        end
        local restored = sameList(copyList(getSavedContacts()), before)
        if not okRun then
            logWarn('phonekit self-test error', { name = 'contacts_hooks', err = tostring(added) })
            return false, 'addContact raised an error', { restored = restored }
        end
        local ok, detail = PS.contactsResult({ added = added, reason = reason, found = found, changes = changes,
            restored = restored })
        return ok and 'mock' or false, detail, { restored = restored }
    end,
}

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if not fromCore() then return end
    local short = PS.shortName(selfName(), name)
    if not short then return end
    local model = short:match('^eye_model_(%a+)$')
    local fn = CLIENT_TESTS[short] or (model and D.MODELS[model] and eyeModel(model))
    if not fn then return end
    local skip = PS.skipReason(short, { battery = Cfg.battery ~= false, mode = Cfg.devices == 'items' and 'items' or 'single',
        lockScreen = Cfg.lockScreen == true, cover = Cfg.cover ~= false, model = device.model, ped = pedReady() })
    if skip then
        reportTest(runId, name, 'skip', skip)
        return
    end
    endSelftest()
    local t = { runId = runId, name = name }
    selftest = t
    CreateThread(function()
        local okRun, ok, detail, extra = pcall(fn, t)
        if selftest ~= t then return end
        if not okRun then
            reportTest(runId, name, 'fail', 'test error')
            logWarn('phonekit self-test error', { name = name, err = tostring(ok) })
            return
        end
        reportTest(runId, name, ok, detail, extra)
    end)
end)

-- Core ends every test with this, reported or not: put back what the test changed.
AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if not fromCore() then return end
    if selftest and selftest.runId == runId and selftest.name == name then endSelftest() end
end)

-- Initial layout element registration
registerLayoutElement()
