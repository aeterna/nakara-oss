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

local function requestOpenPhone()
    if isOpen then
        closePhone()
        return
    end
    -- One key press reaches both the page and the game (keepGameInput): ignore an open right after a close.
    if gameTimer() - lastCloseAt < 300 then
        return
    end
    if not powerOn then
        toast('phonekit.battery.dead')
        return
    end

    TriggerServerEvent('aeterna_phonekit:sv:open')
end

local function toggleFold()
    if not isOpen or not D.MODELS[device.model] or not D.MODELS[device.model].folds then return end
    if device.model == 'fold' and Cfg.cover == false then return end
    local nextFold = D.toggleFold(device.model, device.fold)
    if nextFold == device.fold then return end
    device.fold = nextFold
    sendUi({ type = 'fold', fold = nextFold })
    TriggerServerEvent('aeterna_phonekit:sv:fold', { state = nextFold })
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

-- Initial layout element registration
registerLayoutElement()
