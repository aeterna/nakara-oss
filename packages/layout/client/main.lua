-- aeterna_layout client: local owner protocol, KVP persistence, NUI editor bridge and focus lock coordination;
-- 0.2: clamp on size change, presets, snap prefs, export / import as text and the paused editor.

local L = LayoutLogic

local editorOpen = false
local editorPaused = false
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
    'layout.editor.preset',
    'layout.editor.snapOff',
    'layout.menu.share',
    'layout.export.title',
    'layout.export.hint',
    'layout.import.title',
    'layout.import.apply',
    'layout.import.ok',
}

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local function translate(key, vars)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key, vars)
    end
    local str = (Locales and Locales.en and Locales.en[key]) or key
    if type(vars) == 'table' then
        str = str:gsub('{([%w_]+)}', function(k)
            return vars[k] ~= nil and tostring(vars[k]) or ('{' .. k .. '}')
        end)
    end
    return str
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

local function loadPrefs()
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.get) == 'function' then
        local stored = AeternaCore.kvp.get('prefs', 1, {})
        if type(stored) == 'table' then
            return stored
        end
    end
    return {}
end

local function savePrefs(prefs)
    if AeternaCore and AeternaCore.kvp and type(AeternaCore.kvp.set) == 'function' then
        AeternaCore.kvp.set('prefs', 1, prefs)
    end
end

local snapStep = L.resolveSnapPref(loadPrefs(), Config)
local presets, presetNames = L.validatePresets(Config and Config.presets, Config, logWarn)

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
    onClamp = function(owner, id, place)
        if editorOpen then
            sendUi({ type = 'editor:clamp', owner = owner, id = id, place = place })
        end
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
        if AeternaCore and type(AeternaCore.themeMessage) == 'function' then
            sendUi(AeternaCore.themeMessage())
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
        snap = snapStep,
        snapSteps = L.resolveSnapSteps(Config),
        scale = L.resolveScaleConfig(Config and Config.scale),
    })
end

local function sendPresets()
    local list = {}
    for i = 1, #presetNames do
        local name = presetNames[i]
        local key = 'layout.preset.' .. name
        local label = translate(key)
        list[#list + 1] = { name = name, label = label ~= key and label or name }
    end
    sendUi({ type = 'editor:presets', list = list })
end

local function sendExport()
    local text, err = L.encodeExport(registry:getSavedPlaces(), registry:registeredKeys(), Config)
    if not text then
        logWarn('aeterna_layout: export refused', { err = err })
        sendUi({ type = 'export:show', error = translate('layout.export.tooLong') })
        return
    end
    sendUi({ type = 'export:show', text = text })
end

local function openEditor()
    if not editorOpen then
        if not acquireFocus() then
            logWarn('aeterna_layout: editor open refused', { err = 'focus: unavailable' })
            return
        end
        editorOpen = true
        editorPaused = false
        registry:beginSession()
    end
    syncThemeAndLocale()
    sendEditorOpen()
    sendPresets()
    return true
end

local function closeEditor(release)
    editorOpen = false
    editorPaused = false
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

-- Server -> Client Net Event. Optional payload from the menu panel (0.2): { mode = 'editor' | 'share' }, or
-- { mode = 'arm', token } when the player presses Reset all and { mode = 'reset', token } after the confirm.
-- A reset runs only with the token armed in the last 30 s, once; a local event cannot know it.
local OPEN_MODES = { editor = false, share = false, arm = true, reset = true } -- value: carries a token
local RESET_TOKEN_TTL_MS = 30000
local armedReset = nil

local function parseOpenPayload(payload)
    if payload == nil then
        return true, 'editor', nil
    end
    if type(payload) ~= 'table' or OPEN_MODES[payload.mode] == nil then
        return false, 'mode: enum'
    end
    for k in pairs(payload) do
        if k ~= 'mode' and not (k == 'token' and OPEN_MODES[payload.mode]) then
            return false, tostring(k) .. ': not allowed'
        end
    end
    if OPEN_MODES[payload.mode] then
        local token = payload.token
        if type(token) ~= 'string' or #token ~= 16 or not token:match('^%x+$') then
            return false, 'token: pattern'
        end
    end
    return true, payload.mode, payload.token
end

RegisterNetEvent('aeterna_layout:cl:open', function(payload)
    local ok, mode, token = parseOpenPayload(payload)
    if not ok then
        logWarn('aeterna_layout:cl:open refused', { err = mode })
        return
    end
    if mode == 'arm' then
        armedReset = { token = token, expires = GetGameTimer() + RESET_TOKEN_TTL_MS }
        return
    end
    if mode == 'reset' then
        local armed = armedReset
        if not armed or armed.token ~= token or GetGameTimer() > armed.expires then
            logWarn('aeterna_layout: reset refused', { err = 'token: invalid' })
            return
        end
        armedReset = nil
        if editorOpen then
            logWarn('aeterna_layout: reset refused', { err = 'editor: open' })
            return
        end
        registry:resetAllSaved()
        return
    end
    if openEditor() and mode == 'share' then
        sendExport()
    end
end)

-- Focus overlay (core 0.2): the editor stays open with its session and ignores input until focus comes back.
AddEventHandler('aeterna_core:focusPaused', function(owner, token)
    if owner ~= (type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_layout') then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    if editorOpen then
        editorPaused = true
    end
end)

AddEventHandler('aeterna_core:focusResumed', function(owner, token)
    if owner ~= (type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_layout') then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    editorPaused = false
end)

local function acceptsInput()
    return editorOpen and not editorPaused
end

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
    if not acceptsInput() then return end
    registry:move(data)
end)

RegisterNUICallback('hide', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not acceptsInput() then return end
    registry:hide(data)
end)

RegisterNUICallback('reset', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not acceptsInput() then return end
    local ok = registry:reset(data)
    if ok and editorOpen then
        sendEditorOpen()
    end
end)

RegisterNUICallback('done', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not acceptsInput() then return end
    local ok = L.validateEmptyCallback(data, logWarn)
    if not ok then return end
    registry:commitSession()
    closeEditor(true)
end)

RegisterNUICallback('cancel', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not acceptsInput() then return end
    local ok = L.validateEmptyCallback(data, logWarn)
    if not ok then return end
    registry:cancelSession()
    closeEditor(true)
end)

RegisterNUICallback('preset', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not acceptsInput() then return end
    local ok, _, clean = L.validatePresetCallback(data, logWarn)
    if not ok then return end
    if not presets[clean.name] then
        logWarn('aeterna_layout: unknown preset', { name = clean.name })
        return
    end
    if registry:applyPreset(presets[clean.name]) then
        sendEditorOpen()
    end
end)

RegisterNUICallback('snap', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not acceptsInput() then return end
    local ok, _, clean = L.validateSnapCallback(data, Config, logWarn)
    if not ok then return end
    snapStep = clean.step
    savePrefs({ snap = snapStep })
end)

RegisterNUICallback('import', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not acceptsInput() then return end
    local okPayload, errPayload, clean = L.validateImportCallback(data)
    local ok, err, places, kind = false, errPayload, nil, 'invalid'
    if okPayload then
        ok, err, places, kind = L.decodeImport(clean.text, Config)
    end
    if not ok then
        local message = kind == 'version' and translate('layout.import.version')
            or translate('layout.import.invalid', { path = err })
        sendUi({ type = 'import:result', ok = false, error = message })
        return
    end
    registry:importPlaces(places)
    sendEditorOpen()
    sendUi({ type = 'import:result', ok = true })
end)

RegisterNUICallback('exportOpen', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not acceptsInput() then return end
    if not L.validateEmptyCallback(data, logWarn) then return end
    sendExport()
end)

-- The page reports its size on load and on resize, also outside the editor, so owners stay on screen.
RegisterNUICallback('screen', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    local ok, _, clean = L.validateScreen(data, logWarn)
    if not ok then return end
    registry:setScreen(clean.w, clean.h)
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
