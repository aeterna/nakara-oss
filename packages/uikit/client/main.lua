-- aeterna_uikit client: NUI bridge, focus coordination via aeterna_core, client prompts and key mappings.

local L = UikitLogic

local currentPanel = nil
local activePrompt = nil
local activeProgress = nil
local focusToken = nil
local paused = false -- 0.2: another resource holds focus as an overlay; ignore all input until it resumes
local promptSeq = 0
local localeReady = false
local selftest = nil -- 0.2: the client self-test in flight (Self-tests section at the end)
local SINK_SRC = 0 -- key of the test panel in the self-test's own panel manager

local LOCALE_KEYS = {
    'uikit.menu.title',
    'uikit.confirm.ok',
    'uikit.confirm.cancel',
    'uikit.input.submit',
    'uikit.progress.cancel',
    'uikit.skill.title',
    'uikit.skill.bind',
    'uikit.key.unbound',
    'uikit.close',
    'uikit.key.menu',
    'uikit.key.cancel',
    'uikit.key.skill',
    'uikit.search.placeholder',
    'uikit.search.none',
    'uikit.table.empty',
    'uikit.tabs.label',
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

-- The page learns the pause state too, so its own buttons and keys do nothing while paused.
local function setPaused(flag)
    if paused == flag then return end
    paused = flag
    sendUi({ type = 'focus:paused', paused = flag })
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

local function acquireFocus(opts)
    local ok, tok = pcall(function()
        return AeternaCore.requestFocus(opts)
    end)
    setPaused(false)
    if ok and type(tok) == 'string' then
        focusToken = tok
        return tok
    end
    focusToken = 'local_focus'
    return focusToken
end

local function dropFocus()
    if not focusToken then return end
    local tok = focusToken
    focusToken = nil
    setPaused(false)
    pcall(function()
        AeternaCore.releaseFocus(tok)
    end)
end

local function syncFocusRelease()
    if not currentPanel and not activePrompt then
        dropFocus()
    end
end

-- A test panel's actions go to the self-test's own panel manager (the validation the server runs), never to the
-- server, which does not know that panel.
local function forwardAction(panel, payload)
    if not panel.selftest then
        TriggerServerEvent('aeterna_uikit:sv:action', payload)
        return
    end
    local st = selftest
    if not st or st.panelId ~= panel.panelId then return end
    local ok, _, result = st.sink:handleAction(SINK_SRC, payload)
    st.results[#st.results + 1] = ok and result or false
    if st.onAction then
        st.onAction(ok and result or nil)
    end
end

local function resolveCommandKey(cmd, fallback)
    if type(GetControlInstructionalButton) == 'function' and type(GetHashKey) == 'function' then
        local raw = GetControlInstructionalButton(2, GetHashKey(cmd) | 0x80000000, true)
        local formatted = L.formatKeyBinding(raw, '')
        if formatted ~= '' then
            return formatted
        end
    end
    return fallback
end

local function disableControls(disable)
    if type(disable) ~= 'table' or type(DisableControlAction) ~= 'function' then return end
    if disable.mouse then
        DisableControlAction(0, 1, true)
        DisableControlAction(0, 2, true)
        DisableControlAction(0, 106, true)
    end
    if disable.move then
        DisableControlAction(0, 21, true)
        DisableControlAction(0, 22, true)
        DisableControlAction(0, 30, true)
        DisableControlAction(0, 31, true)
        DisableControlAction(0, 36, true)
    end
    if disable.car then
        DisableControlAction(0, 63, true)
        DisableControlAction(0, 64, true)
        DisableControlAction(0, 71, true)
        DisableControlAction(0, 72, true)
        DisableControlAction(0, 75, true)
    end
    if disable.combat then
        DisableControlAction(0, 24, true)
        DisableControlAction(0, 25, true)
        DisableControlAction(0, 47, true)
        DisableControlAction(0, 58, true)
        DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true)
        DisableControlAction(0, 142, true)
        DisableControlAction(0, 143, true)
        DisableControlAction(0, 257, true)
        DisableControlAction(0, 263, true)
    end
end

local function isEscapePressed()
    if type(IsControlJustPressed) == 'function' then
        if IsControlJustPressed(0, 200) or IsControlJustPressed(0, 322) then
            return true
        end
    end
    if type(IsDisabledControlJustPressed) == 'function' then
        if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) then
            return true
        end
    end
    return false
end

-- Server -> Client Net Events
RegisterNetEvent('aeterna_uikit:cl:open', function(data)
    if type(data) ~= 'table' or type(data.panelId) ~= 'string' then return end
    syncThemeAndLocale()
    currentPanel = data
    acquireFocus({ cursor = true, keyboard = true, keepGameInput = false })
    sendUi({ type = 'panel:open', panel = data })
end)

RegisterNetEvent('aeterna_uikit:cl:update', function(data)
    if type(data) ~= 'table' or not currentPanel or currentPanel.selftest then return end
    if data.panelId ~= currentPanel.panelId then return end
    sendUi({
        type = 'panel:update',
        panelId = data.panelId,
        patch = data.patch,
    })
end)

RegisterNetEvent('aeterna_uikit:cl:close', function(data)
    if type(data) ~= 'table' or not currentPanel then return end
    if data.panelId and (currentPanel.selftest or data.panelId ~= currentPanel.panelId) then return end
    local pId = currentPanel.panelId
    currentPanel = nil
    sendUi({
        type = 'panel:close',
        panelId = pId,
        reason = data.reason or 'closed',
    })
    syncFocusRelease()
end)

local function isOurFocusEvent(owner, token)
    local selfName = type(GetCurrentResourceName) == 'function' and GetCurrentResourceName() or 'aeterna_uikit'
    if owner ~= nil and owner ~= selfName then return false end
    if token ~= nil and focusToken ~= nil and token ~= focusToken then return false end
    return true
end

-- Focus overlay (core 0.2): stay on screen, ignore input, send nothing; a skill check's marker stops.
AddEventHandler('aeterna_core:focusPaused', function(owner, token)
    if not isOurFocusEvent(owner, token) or not focusToken then return end
    setPaused(true)
end)

AddEventHandler('aeterna_core:focusResumed', function(owner, token)
    if not isOurFocusEvent(owner, token) or not paused then return end
    setPaused(false)
end)

-- Focus loss handler from aeterna_core (a real loss closes even while paused)
AddEventHandler('aeterna_core:focusLost', function(owner, token, reason)
    if not isOurFocusEvent(owner, token) then return end
    focusToken = nil
    setPaused(false)

    if activePrompt and not activePrompt.done then
        activePrompt.done = true
        if activePrompt.kind == 'input' then
            activePrompt.result = nil
        else
            activePrompt.result = false
        end
        sendUi({ type = 'panel:close', panelId = '__prompt', reason = reason or 'preempted' })
        activePrompt = nil
    end

    if currentPanel then
        local panel = currentPanel
        local pId = currentPanel.panelId
        local isMenu = currentPanel.kind == 'menu'
        currentPanel = nil
        sendUi({ type = 'panel:close', panelId = pId, reason = reason or 'preempted' })
        if not isMenu then
            forwardAction(panel, {
                panelId = pId,
                action = '__close',
                values = {},
            })
        end
    end
end)

-- NUI Callbacks
RegisterNUICallback('panelAction', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if paused or type(data) ~= 'table' or not currentPanel then return end
    if data.panelId ~= currentPanel.panelId then return end

    if currentPanel.kind == 'menu' then
        local action = data.action
        currentPanel = nil
        sendUi({ type = 'panel:close', panelId = '__menu', reason = 'closed' })
        syncFocusRelease()
        if action ~= '__close' and type(data.owner) == 'string' and L.isValidId(data.id, 32) then
            TriggerServerEvent('aeterna_uikit:sv:menu', {
                owner = data.owner,
                id = data.id,
            })
        end
        return
    end

    local action = data.action
    if type(action) ~= 'string' or #action < 1 or #action > 32 then
        logWarn('panelAction invalid action')
        return
    end
    local values = type(data.values) == 'table' and data.values or {}
    local panel = currentPanel
    local pId = currentPanel.panelId

    if action == '__close' then
        currentPanel = nil
        sendUi({ type = 'panel:close', panelId = pId, reason = 'closed' })
        syncFocusRelease()
    end

    forwardAction(panel, {
        panelId = pId,
        action = action,
        values = values,
    })
end)

RegisterNUICallback('promptResult', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if paused or type(data) ~= 'table' then return end

    if data.kind == 'progress' and activeProgress then
        if data.value == false and activeProgress.cancelable then
            activeProgress.cancelled = true
        elseif data.value == true then
            activeProgress.finished = true
        end
        return
    end

    if not activePrompt or activePrompt.done then return end
    if data.kind ~= activePrompt.kind then return end

    activePrompt.result = data.value
    activePrompt.done = true
end)

RegisterNUICallback('escape', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    if paused then return end

    if activePrompt and not activePrompt.done then
        if activePrompt.kind == 'input' then
            activePrompt.result = nil
        else
            activePrompt.result = false
        end
        activePrompt.done = true
        sendUi({ type = 'panel:close', panelId = '__prompt', reason = 'escape' })
        return
    end

    if currentPanel then
        local panel = currentPanel
        local pId = currentPanel.panelId
        local isMenu = currentPanel.kind == 'menu'
        currentPanel = nil
        sendUi({ type = 'panel:close', panelId = pId, reason = 'escape' })
        syncFocusRelease()
        if not isMenu then
            forwardAction(panel, {
                panelId = pId,
                action = '__close',
                values = {},
            })
        end
        return
    end

    if activeProgress and activeProgress.cancelable then
        activeProgress.cancelled = true
    end
end)

-- Client Exports
exports('confirm', function(opts)
    local ok, err, clean = L.validateConfirmOpts(
        opts,
        translate('uikit.confirm.ok'),
        translate('uikit.confirm.cancel')
    )
    if not ok then
        logWarn('confirm invalid opts', { err = err })
        return false
    end
    syncThemeAndLocale()
    if activePrompt and not activePrompt.done then
        activePrompt.done = true
    end
    promptSeq = promptSeq + 1
    local p = { id = promptSeq, kind = 'confirm', done = false, result = false }
    activePrompt = p
    acquireFocus({ cursor = true, keyboard = true, keepGameInput = false })
    sendUi({
        type = 'prompt:confirm',
        prompt = clean,
    })
    while not p.done do
        Wait(10)
    end
    if activePrompt == p then
        activePrompt = nil
    end
    syncFocusRelease()
    return p.result == true
end)

exports('input', function(opts)
    local ok, err, clean = L.validateInputOpts(opts)
    if not ok then
        logWarn('input invalid opts', { err = err })
        return nil
    end
    syncThemeAndLocale()
    if activePrompt and not activePrompt.done then
        activePrompt.done = true
    end
    promptSeq = promptSeq + 1
    local p = { id = promptSeq, kind = 'input', done = false, result = nil }
    activePrompt = p
    acquireFocus({ cursor = true, keyboard = true, keepGameInput = false })
    sendUi({
        type = 'prompt:input',
        prompt = {
            title = clean.title,
            fields = clean.fields,
            submit = translate('uikit.input.submit'),
            cancel = translate('uikit.confirm.cancel'),
        },
    })
    while not p.done do
        Wait(10)
    end
    if activePrompt == p then
        activePrompt = nil
    end
    syncFocusRelease()
    if type(p.result) ~= 'table' then
        return nil
    end
    local okVal, errVal, cleanVal = L.validateInputValues(clean.fields, p.result)
    if not okVal then
        logWarn('input values rejected', { err = errVal })
        return nil
    end
    return cleanVal
end)

exports('progress', function(opts)
    local ok, err, clean = L.validateProgressOpts(opts)
    if not ok then
        logWarn('progress invalid opts', { err = err })
        return false
    end
    syncThemeAndLocale()
    local prog = {
        cancelable = clean.cancelable,
        cancelled = false,
        finished = false,
    }
    activeProgress = prog
    sendUi({
        type = 'prompt:progress',
        prompt = {
            active = true,
            label = clean.label,
            duration = clean.duration,
            cancelable = clean.cancelable,
            cancelLabel = translate('uikit.progress.cancel'),
        },
    })
    local startAt = type(GetGameTimer) == 'function' and GetGameTimer() or 0
    while not prog.cancelled and not prog.finished do
        local now = type(GetGameTimer) == 'function' and GetGameTimer() or (startAt + clean.duration)
        if (now - startAt) >= clean.duration then
            prog.finished = true
            break
        end
        disableControls(clean.disable)
        if clean.cancelable and not paused and not clean.disable.mouse and isEscapePressed() then
            prog.cancelled = true
            break
        end
        Wait(0)
    end
    if activeProgress == prog then
        activeProgress = nil
    end
    sendUi({
        type = 'prompt:progress',
        prompt = { active = false },
    })
    return not prog.cancelled
end)

exports('skillCheck', function(opts)
    local ok, err, clean = L.validateSkillOpts(opts)
    if not ok then
        logWarn('skillCheck invalid opts', { err = err })
        return false
    end
    syncThemeAndLocale()
    if activePrompt and not activePrompt.done then
        activePrompt.done = true
    end
    promptSeq = promptSeq + 1
    local p = { id = promptSeq, kind = 'skill', done = false, result = false }
    activePrompt = p
    acquireFocus({ cursor = false, keyboard = true, keepGameInput = true })
    sendUi({
        type = 'prompt:skill',
        prompt = {
            active = true,
            difficulty = clean.difficulty,
            rounds = clean.rounds,
            title = translate('uikit.skill.title'),
            bind = resolveCommandKey('+aeterna_uikit_skill', translate('uikit.skill.bind')),
        },
    })
    while not p.done do
        if type(DisableControlAction) == 'function' then
            DisableControlAction(0, 22, true)
        end
        if not paused and type(IsDisabledControlJustPressed) == 'function' and IsDisabledControlJustPressed(0, 22) then
            sendUi({ type = 'prompt:skill', action = 'hit' })
        end
        if not paused and isEscapePressed() then
            p.result = false
            p.done = true
            break
        end
        Wait(0)
    end
    if activePrompt == p then
        activePrompt = nil
    end
    sendUi({ type = 'prompt:skill', prompt = { active = false } })
    syncFocusRelease()
    return p.result == true
end)

exports('keyHints', function(list)
    local ok, err, clean = L.validateKeyHints(list)
    if not ok then
        logWarn('keyHints invalid list', { err = err })
        return nil
    end
    syncThemeAndLocale()
    local unboundText = translate('uikit.key.unbound')
    local resolved = {}
    for i = 1, #clean do
        local row = clean[i]
        local raw = nil
        if type(GetControlInstructionalButton) == 'function' and type(GetHashKey) == 'function' then
            raw = GetControlInstructionalButton(2, GetHashKey(row.key) | 0x80000000, true)
        end
        resolved[i] = {
            key = row.key,
            bind = L.formatKeyBinding(raw, unboundText),
            label = row.label,
        }
    end
    sendUi({
        type = 'hints:show',
        hints = resolved,
    })
    return nil
end)

exports('clearKeyHints', function()
    sendUi({ type = 'hints:clear' })
    return nil
end)

-- Commands and key mappings (literal names required by fivem-devkit safety)
RegisterCommand('aeterna_uikit_menu', function()
    TriggerServerEvent('aeterna_uikit:sv:showMenu')
end, false)

RegisterCommand('+aeterna_uikit_menu', function()
    TriggerServerEvent('aeterna_uikit:sv:showMenu')
end, false)

RegisterCommand('-aeterna_uikit_menu', function() end, false)

RegisterCommand('+aeterna_uikit_cancel', function()
    if not paused and activeProgress and activeProgress.cancelable then
        activeProgress.cancelled = true
    end
end, false)

RegisterCommand('-aeterna_uikit_cancel', function() end, false)

RegisterCommand('+aeterna_uikit_skill', function()
    if not paused and activePrompt and activePrompt.kind == 'skill' and not activePrompt.done then
        sendUi({ type = 'prompt:skill', action = 'hit' })
    end
end, false)

RegisterCommand('-aeterna_uikit_skill', function() end, false)

if AeternaCore and type(AeternaCore.key) == 'function' then
    AeternaCore.key('+aeterna_uikit_menu', 'uikit.key.menu')
    AeternaCore.key('+aeterna_uikit_cancel', 'uikit.key.cancel')
    AeternaCore.key('+aeterna_uikit_skill', 'uikit.key.skill')
end

--------------------------------------------------------------------------------
-- Self-tests (0.2): the ped and eye rows run here (docs/specs/aeterna_uikit.md § Self-tests (0.2)).
-- A test panel opens on this client only; what the owner would receive is checked by a client-side panel manager
-- running the same validation as the server.
--------------------------------------------------------------------------------

local Selftests = UikitSelftests
local RENDER_WAIT_MS = 300 -- the page draws the panel before the test drives it
local DRIVE_WAIT_MS = 3000
local MOTION_TOGGLE_MS = 2000

local function reportSelftest(runId, name, state, detail)
    pcall(function()
        exports.aeterna_core:reportSelftest(runId, name, state, detail)
    end)
end

local function closeTestPanel(st)
    if currentPanel and currentPanel.selftest and currentPanel.panelId == st.panelId then
        currentPanel = nil
        sendUi({ type = 'panel:close', panelId = st.panelId, reason = 'closed' })
        syncFocusRelease()
    end
end

local function endSelftest()
    local st = selftest
    if not st then return end
    selftest = nil
    st.ended = true
    closeTestPanel(st)
end

-- Opens the test panel like the server's open would: an open panel is replaced and its owner gets __close.
local function beginSelftest(runId, name, short)
    endSelftest()
    local sink = L.createPanelManager()
    local panelId, err = sink:open(SINK_SRC, GetCurrentResourceName(), Selftests.panelSpec(short, translate))
    if not panelId then
        reportSelftest(runId, name, 'fail', 'test panel refused: ' .. tostring(err))
        return nil
    end
    if currentPanel then
        local old = currentPanel
        currentPanel = nil
        sendUi({ type = 'panel:close', panelId = old.panelId, reason = 'replaced' })
        if old.kind ~= 'menu' then
            forwardAction(old, { panelId = old.panelId, action = '__close', values = {} })
        end
    end
    local clean = sink:getOpen(SINK_SRC).spec
    selftest = { runId = runId, name = name, sink = sink, panelId = panelId, spec = clean, results = {} }
    syncThemeAndLocale()
    currentPanel = { panelId = panelId, title = clean.title, size = clean.size, blocks = clean.blocks, selftest = true }
    acquireFocus({ cursor = true, keyboard = true, keepGameInput = false })
    sendUi({ type = 'panel:open', panel = currentPanel })
    return selftest
end

local function lastResult(st)
    return st.results[#st.results] or nil
end

local function waitFor(st, cond, ms)
    local deadline = GetGameTimer() + ms
    while not st.ended and not cond() and GetGameTimer() < deadline do
        Wait(50)
    end
    return not st.ended and cond()
end

local function finish(st, ok, detail)
    if st.ended then return end
    reportSelftest(st.runId, st.name, ok and 'pass' or 'fail', detail)
    endSelftest()
end

-- Sends one drive message to the page, waits for its probe and the owner's action, then judges.
local function drive(st, msg, judge)
    CreateThread(function()
        Wait(RENDER_WAIT_MS)
        if st.ended then return end
        st.driveOp = msg.op
        sendUi(msg)
        waitFor(st, function() return st.probe ~= nil and #st.results > 0 end, DRIVE_WAIT_MS)
        finish(st, judge(lastResult(st), st.probe))
    end)
end

local CLIENT_TESTS = {}

function CLIENT_TESTS.panel_every_block(st)
    reportSelftest(st.runId, st.name, 'ready', 'panel open')
end

function CLIENT_TESTS.overlay_pauses(st)
    local presses = 0
    st.onAction = function(result)
        if not result or result.action ~= 'press' then return end
        presses = presses + 1
        local ok, _, patch = st.sink:update(SINK_SRC, st.panelId,
            { blocks = { info = { label = translate('uikit.selftest.pressed', { n = presses }) } } })
        if ok then
            sendUi({ type = 'panel:update', panelId = st.panelId, patch = patch })
        end
    end
    reportSelftest(st.runId, st.name, 'ready', 'panel open')
end

-- The page only: the panel leaves and enters again, so the person sees both animations (or none).
function CLIENT_TESTS.motion_reduced(st)
    reportSelftest(st.runId, st.name, 'ready', 'panel open')
    CreateThread(function()
        local shown = true
        while true do
            Wait(MOTION_TOGGLE_MS)
            if st.ended or not currentPanel or currentPanel.panelId ~= st.panelId then return end
            shown = not shown
            if shown then
                sendUi({ type = 'panel:open', panel = currentPanel })
            else
                sendUi({ type = 'panel:close', panelId = st.panelId, reason = 'closed' })
            end
        end
    end)
end

function CLIENT_TESTS.tabs_switch(st)
    drive(st, { type = 'selftest:drive', op = 'tab', target = Selftests.TAB_TARGET }, function(result, probe)
        return Selftests.judgeTabs(st.spec, result, probe)
    end)
end

function CLIENT_TESTS.slider_keyboard(st)
    drive(st, { type = 'selftest:drive', op = 'slider', block = Selftests.SLIDER.id, press = 'act' }, Selftests.judgeSlider)
end

-- Fires the event core sends when another resource takes focus without the overlay option, then hands the token
-- back, because core still counts it as held.
function CLIENT_TESTS.focus_lost_closes(st)
    CreateThread(function()
        Wait(RENDER_WAIT_MS)
        if st.ended then return end
        local tok = focusToken
        TriggerEvent('aeterna_core:focusLost', GetCurrentResourceName(), tok, 'preempted')
        local open = currentPanel ~= nil and currentPanel.panelId == st.panelId
        local ok, detail = Selftests.judgeFocusLost({ panelOpen = open, close = lastResult(st) })
        if tok then
            pcall(function() AeternaCore.releaseFocus(tok) end)
        end
        finish(st, ok, detail)
    end)
end

AddEventHandler('aeterna_core:selftest', function(runId, name)
    local short = Selftests.shortName(name)
    local run = short and CLIENT_TESTS[short]
    if not run then return end
    local st = beginSelftest(runId, name, short)
    if st then
        run(st)
    end
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if selftest and selftest.runId == runId and selftest.name == name then
        endSelftest()
    end
end)

-- The page's report after a drive: { op, visible = { blockId, ... } } or { op, shown }.
RegisterNUICallback('selftestProbe', function(data, cb)
    if type(cb) == 'function' then cb({ ok = true }) end
    local st = selftest
    if not st or st.probe or type(data) ~= 'table' or data.op ~= st.driveOp then return end
    local probe = {}
    if type(data.visible) == 'table' then
        probe.visible = {}
        for i = 1, math.min(#data.visible, 40) do
            if L.isValidId(data.visible[i], 32) then
                probe.visible[#probe.visible + 1] = data.visible[i]
            end
        end
    end
    if type(data.shown) == 'string' and #data.shown <= 32 then
        probe.shown = data.shown
    end
    st.probe = probe
end)
