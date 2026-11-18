-- client/main.lua -- aeterna_phonekit client: shell UI, NUI callbacks, KVP persistence,
-- focus coordination through aeterna_core, animation control, and aeterna_layout protocol.

local L = PhoneLogic
local isOpen = false
local focusToken = nil
local activeScreenId = nil
local currentAppId = nil
local localeReady = false
local isHovering = false

local layoutPlace = nil

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
    'phonekit.contacts.new',
    'phonekit.contacts.empty',
    'phonekit.contacts.full',
    'phonekit.settings.textSize',
    'phonekit.settings.clock24',
    'phonekit.settings.layout',
    'phonekit.refused.default',
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

local function currentPosition()
    if type(Config) == 'table' and type(Config.position) == 'string' then
        return Config.position
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

local function getSavedNotes()
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.get) == 'function' then
        local n = AeternaCore.kvp.get('notes', 1, {})
        if type(n) == 'table' then
            return n
        end
    end
    return {}
end

local function getSavedContacts()
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.get) == 'function' then
        local c = AeternaCore.kvp.get('contacts', 1, {})
        if type(c) == 'table' then
            return c
        end
    end
    return {}
end

local function registerLayoutElement()
    local defs = L.buildLayoutDefs(currentPosition(), translate('phonekit.home.title'))
    for i = 1, #defs do
        defs[i].owner = selfName()
        TriggerEvent('aeterna_layout:add', defs[i])
    end
end

local function acquireFocus()
    local ok, tok = pcall(function()
        return exports.aeterna_core:requestFocus({
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
        exports.aeterna_core:releaseFocus(tok)
    end)
end

local function closePhone()
    if not isOpen then return end
    isOpen = false
    activeScreenId = nil
    currentAppId = nil
    isHovering = false

    dropFocus()

    if Config and Config.animation and PhoneAnim and type(PhoneAnim.stop) == 'function' then
        PhoneAnim.stop()
    end

    sendUi({ type = 'shell:close' })
end

local function requestOpenPhone()
    if isOpen then
        closePhone()
        return
    end

    TriggerServerEvent('aeterna_phonekit:sv:open')
end

-- Server -> Client Net Events
RegisterNetEvent('aeterna_phonekit:cl:open', function(data)
    if isOpen then return end

    syncThemeAndLocale()

    local tok = acquireFocus()
    if not tok then
        logWarn('aeterna_phonekit focus denied by aeterna_core')
        return
    end

    isOpen = true
    activeScreenId = nil
    currentAppId = nil

    if Config and Config.animation and PhoneAnim and type(PhoneAnim.start) == 'function' then
        PhoneAnim.start()
    end

    local settings = getSavedSettings()
    local hasLayout = type(GetResourceState) == 'function' and GetResourceState('aeterna_layout') == 'started'
    settings.hasLayout = hasLayout

    local apps = (data and type(data.apps) == 'table') and data.apps or {}
    sendUi({
        type = 'shell:open',
        apps = apps,
        settings = settings,
        position = currentPosition(),
        place = layoutPlace,
        builtins = Config.apps or {},
    })

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
    local msg = translate(reason)
    pcall(function()
        exports.aeterna_notify:notify({
            title = msg,
            type = 'error',
        })
    end)
end)

-- Focus Loss Handler
AddEventHandler('aeterna_core:focusLost', function(owner, token)
    if owner ~= nil and owner ~= selfName() then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    closePhone()
end)

-- Ped State & Ragdoll Watcher
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
            if isOpen and isHovering and type(DisableControlAction) == 'function' then
                -- Disable mouse look controls while cursor is over the phone frame
                DisableControlAction(0, 1, true) -- LookLeftRight
                DisableControlAction(0, 2, true) -- LookUpDown
            end
            Wait(isOpen and 0 or 250)
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

if AeternaCore and type(AeternaCore.key) == 'function' then
    AeternaCore.key('+aeterna_phonekit_open', 'phonekit.key.open')
end

-- NUI Callbacks
RegisterNUICallback('tap', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if type(data) ~= 'table' or type(data.id) ~= 'string' then return end

    local id = data.id
    local owner = type(data.owner) == 'string' and data.owner or ''

    -- Check if it is a built-in app
    if id == 'calculator' or id == 'notes' or id == 'contacts' or id == 'settings' then
        currentAppId = id
        activeScreenId = nil
        return
    end

    currentAppId = id
    TriggerServerEvent('aeterna_phonekit:sv:tap', {
        id = id,
        owner = owner,
    })
end)

RegisterNUICallback('action', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if type(data) ~= 'table' then return end

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
    if activeScreenId then
        local sId = activeScreenId
        activeScreenId = nil
        currentAppId = nil
        TriggerServerEvent('aeterna_phonekit:sv:action', {
            screenId = sId,
            action = '__close',
            values = {},
        })
    else
        currentAppId = nil
    end
end)

RegisterNUICallback('close', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    closePhone()
end)

RegisterNUICallback('hover', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if type(data) == 'table' and type(data.hovering) == 'boolean' then
        isHovering = data.hovering
    end
end)

RegisterNUICallback('builtin:save', function(data, cb)
    if type(data) ~= 'table' or type(data.app) ~= 'string' or type(data.data) ~= 'table' then
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
        if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.set) == 'function' then
            AeternaCore.kvp.set('notes', 1, store:list())
        end
        if type(cb) == 'function' then cb({ ok = true, list = store:list() }) end

    elseif appName == 'contacts' then
        local store = L.createContactsStore()
        for i = 1, #items do
            local ok, errKey = store:save(items[i], type(json) == 'table' and json.encode or nil)
            if not ok then
                if type(cb) == 'function' then cb({ ok = false, err = translate(errKey) }) end
                return
            end
        end
        if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.set) == 'function' then
            AeternaCore.kvp.set('contacts', 1, store:list())
        end
        if type(cb) == 'function' then cb({ ok = true, list = store:list() }) end

    else
        if type(cb) == 'function' then cb({ ok = false, err = 'unknown app' }) end
    end
end)

RegisterNUICallback('settings', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if type(data) ~= 'table' or type(data.key) ~= 'string' then return end

    if data.key == 'layout' then
        if type(ExecuteCommand) == 'function' then
            ExecuteCommand('aeterna_layout')
        end
    else
        saveSetting(data.key, data.value)
    end
end)

-- Initial layout element registration
registerLayoutElement()
