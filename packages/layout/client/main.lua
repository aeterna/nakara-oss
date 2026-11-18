-- aeterna_layout client: local owner protocol, KVP persistence, NUI editor bridge and focus lock coordination.

local L = LayoutLogic

local editorOpen = false
local focusToken = nil
local localeReady = false

local LOCALE_KEYS = {
    'layout.menu.entry',
    'layout.key.edit',
    'layout.editor.title',
    'layout.editor.snap',
    'layout.editor.reset',
    'layout.editor.resetAll',
    'layout.editor.resetAllConfirm',
    'layout.editor.hide',
    'layout.editor.show',
    'layout.editor.scale',
    'layout.editor.cancel',
    'layout.editor.done',
    'layout.editor.doneHint',
    'layout.editor.empty',
}

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local function translate(key)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key)
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

local function loadPlaces()
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.get) == 'function' then
        local stored = AeternaCore.kvp.get('places', 1, {})
        if type(stored) == 'table' then
            return stored
        end
    end
    return {}
end

local function savePlaces(places)
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.set) == 'function' then
        AeternaCore.kvp.set('places', 1, places)
    end
end

local function isResourceStarted(resName)
    if type(GetResourceState) ~= 'function' then
        return true
    end
    local st = GetResourceState(resName)
    return st == 'started' or st == 'starting'
end

local registry = L.createRegistry({
    config = Config,
    warn = logWarn,
    loadPlaces = loadPlaces,
    savePlaces = savePlaces,
    onApply = function(owner, id, place)
        TriggerEvent('aeterna_layout:apply', owner, id, place)
    end,
})

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
        return AeternaCore.requestFocus({
            cursor = true,
            keyboard = true,
            keepGameInput = false,
        })
    end)
    if ok and type(tok) == 'string' then
        focusToken = tok
        return tok
    end
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

local function sendEditorOpen()
    sendUi({
        type = 'editor:open',
        elements = registry:listElements(),
        snap = L.resolveSnap(Config and Config.snap),
        scale = L.resolveScaleConfig(Config and Config.scale),
    })
end

local function openEditor()
    if not editorOpen then
        if not acquireFocus() then
            logWarn('aeterna_layout: editor open refused', { err = 'focus: unavailable' })
            return
        end
        editorOpen = true
        registry:beginSession()
    end
    syncThemeAndLocale()
    sendEditorOpen()
end

local function closeEditor(release)
    editorOpen = false
    sendUi({ type = 'editor:close' })
    if release ~= false then
        dropFocus()
    end
end

-- Local owner protocol events
AddEventHandler('aeterna_layout:add', function(def)
    local inv = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    local payloadOwner = type(def) == 'table' and def.owner or nil
    local okOwner, errOwner, owner = L.resolveOwner(inv, payloadOwner, isResourceStarted)
    if not okOwner then
        logWarn('aeterna_layout:add refused', { err = errOwner })
        return
    end
    local ok = registry:add(owner, def)
    if ok and editorOpen then
        sendEditorOpen()
    end
end)

AddEventHandler('aeterna_layout:remove', function(arg1, arg2)
    local inv = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    local id = type(arg1) == 'table' and arg1.id or arg1
    local payloadOwner = type(arg1) == 'table' and arg1.owner or arg2
    local okOwner, errOwner, owner = L.resolveOwner(inv, payloadOwner, isResourceStarted)
    if not okOwner then
        logWarn('aeterna_layout:remove refused', { err = errOwner })
        return
    end
    if not L.isValidId(id, 32) then
        logWarn('aeterna_layout:remove refused', { owner = owner, err = 'id: pattern' })
        return
    end
    if registry:remove(owner, id) and editorOpen then
        sendEditorOpen()
    end
end)

AddEventHandler('onResourceStop', function(stoppedRes)
    if type(stoppedRes) ~= 'string' or stoppedRes == '' then return end
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_layout'
    if stoppedRes == selfName then
        if editorOpen then
            registry:cancelSession()
            closeEditor(true)
        end
        return
    end
    local removed = registry:removeByOwner(stoppedRes)
    if removed > 0 and editorOpen then
        sendEditorOpen()
    end
end)

-- Server -> Client Net Event
RegisterNetEvent('aeterna_layout:cl:open', function()
    openEditor()
end)

-- Focus loss handler from aeterna_core (counts as Cancel)
AddEventHandler('aeterna_core:focusLost', function(owner, token)
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_layout'
    if owner ~= nil and owner ~= selfName then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    focusToken = nil
    if editorOpen then
        registry:cancelSession()
        closeEditor(false)
    end
end)

-- NUI Callbacks
RegisterNUICallback('moved', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not editorOpen then return end
    registry:move(data)
end)

RegisterNUICallback('hide', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not editorOpen then return end
    registry:hide(data)
end)

RegisterNUICallback('reset', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not editorOpen then return end
    local ok = registry:reset(data)
    if ok and editorOpen then
        sendEditorOpen()
    end
end)

RegisterNUICallback('done', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not editorOpen then return end
    local ok = L.validateEmptyCallback(data, logWarn)
    if not ok then return end
    registry:commitSession()
    closeEditor(true)
end)

RegisterNUICallback('cancel', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not editorOpen then return end
    local ok = L.validateEmptyCallback(data, logWarn)
    if not ok then return end
    registry:cancelSession()
    closeEditor(true)
end)

-- Commands and key mappings (literal names required by fivem-devkit safety)
RegisterCommand('aeterna_layout', function()
    openEditor()
end, false)

RegisterCommand('+aeterna_layout_edit', function()
    openEditor()
end, false)

RegisterCommand('-aeterna_layout_edit', function() end, false)

if AeternaCore and type(AeternaCore.key) == 'function' then
    AeternaCore.key('+aeterna_layout_edit', 'layout.key.edit')
end

-- Announce layout readiness so owners started before layout register their elements
TriggerEvent('aeterna_layout:hello')
