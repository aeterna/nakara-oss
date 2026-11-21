-- aeterna_layout client: local owner protocol, KVP persistence, NUI editor bridge and focus lock coordination;
-- 0.2: clamp on size change, presets, snap prefs, export / import as text and the paused editor.

local L = LayoutLogic

local editorOpen = false
local editorPaused = false
local focusToken = nil
local localeReady = false
local selftest = nil -- 0.2: the client self-test in flight (Self-tests section at the end)
local testSnap = nil -- 0.2: grid_drag's snap step, shown in the page during that test only and never saved

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
        snap = testSnap or snapStep,
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

-- Core's local events count only when aeterna_core fired them, so another resource cannot fake one.
local function fromCore()
    return GetInvokingResource() == 'aeterna_core'
end

-- Focus overlay (core 0.2): the editor stays open with its session and ignores input until focus comes back.
AddEventHandler('aeterna_core:focusPaused', function(owner, token)
    if not fromCore() then return end
    if owner ~= (type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_layout') then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    if editorOpen then
        editorPaused = true
    end
end)

AddEventHandler('aeterna_core:focusResumed', function(owner, token)
    if not fromCore() then return end
    if owner ~= (type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_layout') then return end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return end
    editorPaused = false
end)

local function acceptsInput()
    return editorOpen and not editorPaused
end

-- Focus loss handler from aeterna_core (counts as Cancel)
AddEventHandler('aeterna_core:focusLost', function(owner, token)
    if not fromCore() then return end
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

-- A self-test's editor session is never saved: Done acts as Cancel there.
RegisterNUICallback('done', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not acceptsInput() then return end
    local ok = L.validateEmptyCallback(data, logWarn)
    if not ok then return end
    if selftest and selftest.editor then
        registry:cancelSession()
    else
        registry:commitSession()
    end
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
    if selftest and selftest.editor then
        testSnap = clean.step -- shown for the rest of the test, never saved
        return
    end
    snapStep = clean.step
    savePrefs({ snap = snapStep })
end)

-- Imports `text` into the editor session and tells the page the result. Returns whether it was accepted.
local function applyImport(okPayload, errPayload, text)
    local ok, err, places, kind = false, errPayload, nil, 'invalid'
    if okPayload then
        ok, err, places, kind = L.decodeImport(text, Config)
    end
    if not ok then
        local message = kind == 'version' and translate('layout.import.version')
            or translate('layout.import.invalid', { path = err })
        sendUi({ type = 'import:result', ok = false, error = message })
        return false
    end
    registry:importPlaces(places)
    sendEditorOpen()
    sendUi({ type = 'import:result', ok = true })
    return true
end

RegisterNUICallback('import', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if not acceptsInput() then return end
    local okPayload, errPayload, clean = L.validateImportCallback(data)
    local ok = applyImport(okPayload, errPayload, clean and clean.text)
    if selftest then
        selftest.imported = ok
    end
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

--------------------------------------------------------------------------------
-- Self-tests (0.2): the client rows (docs/specs/aeterna_layout.md § Self-tests (0.2)). Test elements belong to
-- aeterna_layout itself and are removed when the test ends; an editor a test opened is cancelled, never saved.
--------------------------------------------------------------------------------

local Selftests = LayoutSelftests
local RENDER_WAIT_MS = 300 -- the page draws the editor before the test drives it
local DRIVE_WAIT_MS = 3000
local MOVE_SETTLE_MS = 200 -- the page's `moved` callback arrives after its pointerup
local PRESET_TOGGLE_MS = 3000
local GROW_W = 320
local DRAG_DX, DRAG_DY = 37, 21 -- not a multiple of any offered step, so an unsnapped drop is off the grid

local function resName()
    return type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_layout'
end

local function reportSelftest(runId, name, state, detail, extra)
    pcall(function()
        exports.aeterna_core:reportSelftest(runId, name, state, detail, extra)
    end)
end

local function addTestElement(st, def)
    local ok, err, eff = registry:add(resName(), def)
    if ok then
        st.elements[def.id] = true
        if editorOpen then sendEditorOpen() end
    end
    return ok, err, eff
end

local function endSelftest()
    local st = selftest
    if not st then return end
    selftest = nil
    st.ended = true
    testSnap = nil
    if st.editor and editorOpen then
        registry:cancelSession()
        closeEditor(true)
    end
    for id in pairs(st.elements) do
        registry:remove(resName(), id)
    end
    if editorOpen then sendEditorOpen() end
end

local function finish(st, ok, detail, extra)
    if st.ended then return end
    local state = ok
    if type(ok) == 'boolean' then
        state = ok and 'pass' or 'fail'
    end
    reportSelftest(st.runId, st.name, state, detail, extra)
    endSelftest()
end

-- Opens the editor for a test; refuses while the player has it open, so their unsaved moves are never lost.
local function openTestEditor(st)
    if editorOpen then
        finish(st, false, 'the layout editor is open; close it and run again')
        return false
    end
    if not openEditor() then
        finish(st, false, 'the editor could not take focus')
        return false
    end
    st.editor = true
    return true
end

local function waitFor(st, cond, ms)
    local deadline = GetGameTimer() + ms
    while not st.ended and not cond() and GetGameTimer() < deadline do
        Wait(50)
    end
    return not st.ended and cond()
end

local function driveAndWait(st, msg)
    st.probe = nil
    st.driveOp = msg.op
    msg.type = 'selftest:drive'
    sendUi(msg)
    return waitFor(st, function() return st.probe ~= nil end, DRIVE_WAIT_MS)
end

local CLIENT_TESTS = {}

-- mock: a test element at the right edge is added again twice as wide, checked on screen, then removed.
function CLIENT_TESTS.clamp_on_grow(st)
    local screen = registry.screen
    if not screen then
        return finish(st, false, 'screen size unknown: the page has not reported it')
    end
    local def = Selftests.growDef(GROW_W, screen.w, translate('layout.selftest.element'))
    local grown = {}
    for k, v in pairs(def) do grown[k] = v end
    grown.w = GROW_W * 2
    addTestElement(st, def)
    local ok, err, eff = addTestElement(st, grown)
    local onScreen, detail = false, 'test element refused: ' .. tostring(err)
    if ok then
        onScreen, detail = Selftests.boxOnScreen(eff, grown.w, grown.h, screen.w, screen.h)
    end
    registry:remove(resName(), def.id)
    st.elements[def.id] = nil
    if editorOpen then sendEditorOpen() end
    if registry:get(resName(), def.id) ~= nil then
        return finish(st, false, 'test element still registered')
    end
    if not onScreen then
        return finish(st, false, detail)
    end
    finish(st, 'mock', detail, { restored = true })
end

-- The editor alternates between the compact preset and Cancel (the session's snapshot) until the person answers.
function CLIENT_TESTS.preset_apply(st)
    local compact = presets.compact
    if not compact then
        return finish(st, false, 'Config.presets has no compact preset')
    end
    if not openTestEditor(st) then return end
    registry:applyPreset(compact)
    sendEditorOpen()
    reportSelftest(st.runId, st.name, 'ready', 'compact applied')
    CreateThread(function()
        local onPreset = true
        while true do
            Wait(PRESET_TOGGLE_MS)
            if st.ended then return end
            if onPreset then
                registry:cancelSession()
                registry:beginSession()
            else
                registry:applyPreset(compact)
            end
            sendEditorOpen()
            onPreset = not onPreset
        end
    end)
end

-- Two drags of a test element in the page, without and with Shift; the step is the player's (or the first offered
-- one when snap is off), shown in the page for this test only and never saved.
function CLIENT_TESTS.grid_drag(st)
    local screen = registry.screen
    if not screen then
        return finish(st, false, 'screen size unknown: the page has not reported it')
    end
    if editorOpen then
        return finish(st, false, 'the layout editor is open; close it and run again')
    end
    local def = Selftests.centerDef('st_grid', translate('layout.selftest.element'))
    addTestElement(st, def)
    testSnap = Selftests.gridStep(snapStep, L.resolveSnapSteps(Config))
    if not openTestEditor(st) then return end
    CreateThread(function()
        Wait(RENDER_WAIT_MS)
        local landed = {}
        for _, shift in ipairs({ false, true }) do
            if not driveAndWait(st, { op = 'drag', owner = resName(), id = def.id, dx = DRAG_DX, dy = DRAG_DY, shift = shift }) then
                break
            end
            Wait(MOVE_SETTLE_MS)
            if st.ended then return end
            local el = registry:get(resName(), def.id)
            if not el then
                return finish(st, false, 'the test element is no longer registered')
            end
            local left, top = Selftests.leftTop(el.place, def.w, def.h, screen.w, screen.h)
            landed[#landed + 1] = { grid = st.probe.grid == true, left = left, top = top }
        end
        finish(st, Selftests.judgeGrid(landed[1], landed[2], testSnap))
    end)
end

-- Export, move a test element, import the text the export box showed: the element is back where it was.
function CLIENT_TESTS.export_import(st)
    if editorOpen then
        return finish(st, false, 'the layout editor is open; close it and run again')
    end
    local def = Selftests.centerDef('st_share', translate('layout.selftest.element'))
    addTestElement(st, def)
    if not openTestEditor(st) then return end
    local start = registry:get(resName(), def.id)
    if not start then
        return finish(st, false, 'the test element was refused')
    end
    local before = start.place
    local text = L.encodeExport(registry:getSavedPlaces(), registry:registeredKeys(), Config)
    sendExport()
    CreateThread(function()
        Wait(RENDER_WAIT_MS)
        driveAndWait(st, { op = 'export' })
        if st.ended then return end
        registry:move({ owner = resName(), id = def.id, x = 0.25, y = 0.25, ax = 0, ay = 0, scale = 1 })
        local pageText = st.probe and st.probe.text or nil
        local importOk = pageText ~= nil and applyImport(true, nil, pageText)
        local after = registry:get(resName(), def.id)
        if not after then
            return finish(st, false, 'the test element is no longer registered')
        end
        finish(st, Selftests.judgeExportImport({
            text = text, pageText = pageText, importOk = importOk, before = before, after = after.place,
        }))
    end)
end

-- The page runs the copy command on the export box, puts the export text into the import box from code (a paste
-- needs clipboard read access the page does not have) and presses Import.
function CLIENT_TESTS.export_copy(st)
    if not openTestEditor(st) then return end
    sendExport()
    CreateThread(function()
        Wait(RENDER_WAIT_MS)
        st.imported = nil
        if driveAndWait(st, { op = 'copy' }) then
            waitFor(st, function() return st.imported ~= nil end, DRIVE_WAIT_MS)
        end
        finish(st, Selftests.judgeCopy(st.probe, st.imported))
    end)
end

-- Destructive: clears the presser's saved layout through the client half of Reset all (the arm and reset messages
-- the server sends after the panel's confirm). The layout is printed to the F8 console first so it can be imported.
function CLIENT_TESTS.reset_from_menu(st)
    if editorOpen then
        return finish(st, false, 'the layout editor is open; close it and run again')
    end
    local hadSaved = next(registry:getSavedPlaces()) ~= nil
    local backup = L.encodeExport(registry:getSavedPlaces(), registry:registeredKeys(), Config)
    if backup then
        print(translate('layout.selftest.backup', { text = backup }))
    end
    local token = ('%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
    TriggerEvent('aeterna_layout:cl:open', { mode = 'arm', token = token })
    TriggerEvent('aeterna_layout:cl:open', { mode = 'reset', token = token })
    local elements = {}
    for _, el in ipairs(registry:listElements()) do
        local cur = registry:get(el.owner, el.id)
        if not cur then
            return finish(st, false, el.owner .. '/' .. el.id .. ' is no longer registered', { wrote = true })
        end
        elements[#elements + 1] = { key = el.owner .. '/' .. el.id, place = cur.place, default = el.defaultPlace }
    end
    local ok, detail = Selftests.judgeReset(registry:getSavedPlaces(), elements, hadSaved)
    finish(st, ok, detail, { wrote = true })
end

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if not fromCore() then return end
    local short = Selftests.shortName(name)
    local run = short and CLIENT_TESTS[short]
    if not run then return end
    endSelftest()
    selftest = { runId = runId, name = name, elements = {} }
    run(selftest)
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if not fromCore() then return end
    if selftest and selftest.runId == runId and selftest.name == name then
        endSelftest()
    end
end)

-- Core stopping ends the run: cancel the test's editor session and remove its elements.
AddEventHandler('onResourceStop', function(resName)
    if resName == 'aeterna_core' then
        endSelftest()
    end
end)

-- The page's report after a drive: { op, grid } (drag), { op, text } (export) or { op, copied } (copy).
RegisterNUICallback('selftestProbe', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    local st = selftest
    if not st or st.probe or type(data) ~= 'table' or data.op ~= st.driveOp then return end
    local probe = {}
    for _, k in ipairs({ 'grid', 'copied' }) do
        probe[k] = data[k] == true
    end
    if type(data.text) == 'string' and #data.text <= L.MAX_TEXT_BYTES then
        probe.text = data.text
    end
    st.probe = probe
end)

-- Announce layout readiness so owners started before layout register their elements
TriggerEvent('aeterna_layout:hello')
