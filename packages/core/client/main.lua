-- aeterna_core client: NUI focus lock and themeHref export.

AeternaCoreLogic = AeternaCoreLogic or {}
AeternaCore = AeternaCore or {}

local focusLogic = AeternaCoreLogic.focus
local focusManager = focusLogic.new({
    onLost = function(owner, token, reason)
        TriggerEvent('aeterna_core:focusLost', owner, token, reason)
    end,
    onPaused = function(owner, token)
        TriggerEvent('aeterna_core:focusPaused', owner, token)
    end,
    onResumed = function(owner, token)
        TriggerEvent('aeterna_core:focusResumed', owner, token)
    end,
})

local warnedTheme = nil

local function isValidThemeHref(href)
    if type(href) ~= 'string' or #href <= 10 then
        return false
    end
    if href:sub(1, 6) ~= 'nui://' or href:sub(-4) ~= '.css' then
        return false
    end
    local slash = href:find('/', 7, true)
    if not slash or slash == 7 or slash >= #href - 3 then
        return false
    end
    return true
end

exports('requestFocus', function(opts)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    local token = focusManager:request(owner, opts)
    return token
end)

exports('releaseFocus', function(token)
    return focusManager:release(token)
end)

exports('focusOwner', function()
    return focusManager:owner()
end)

exports('focusPausedOwner', function()
    return focusManager:pausedOwner()
end)

exports('themeHref', function()
    local raw = GetConvar('aeterna_theme', '')
    if raw == nil or raw == '' then
        return nil
    end
    if isValidThemeHref(raw) then
        return raw
    end
    if warnedTheme ~= raw then
        warnedTheme = raw
        AeternaCore.log.warn('invalid aeterna_theme; expected nui://<resource>/<path>.css', { value = raw })
    end
    return nil
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    focusManager:onResourceStop(stoppedResource, GetCurrentResourceName())
end)

-- Theme preset (ADR 0005 decision 9): an unknown value is asphalt and one warning per new value.
local THEME_PRESETS = { asphalt = true, paper = true, ['night-market'] = true }
local warnedPreset = {}

exports('themePreset', function()
    local raw = GetConvar('aeterna_theme_preset', 'asphalt')
    if THEME_PRESETS[raw] then return raw end
    if not warnedPreset[raw] then
        warnedPreset[raw] = true
        AeternaCore.log.warn('invalid aeterna_theme_preset; falling back to asphalt', { value = raw })
    end
    return 'asphalt'
end)

-- Self-test client protocol (0.2): core sends a test here, the owner reports, the server judges.
local TEST_SCHEMA = { type = 'table', fields = {
    runId = { type = 'string', minLen = 1, maxLen = 24 },
    name = { type = 'string', minLen = 1, maxLen = 96 },
    kind = { type = 'string', enum = { 'headless', 'mock', 'ped', 'eye' } },
    role = { type = 'string', enum = { 'A', 'B' } },
    timeout = { type = 'number', integer = true, min = 500, max = 60000 },
    destructive = { type = 'boolean' },
    expect = { type = 'string', maxLen = 240, optional = true },
    ask = { type = 'string', maxLen = 160, optional = true },
} }
local END_SCHEMA = { type = 'table', fields = {
    runId = { type = 'string', minLen = 1, maxLen = 24 },
    name = { type = 'string', minLen = 1, maxLen = 96 },
} }
local RESULT_STATES = { pass = true, fail = true, skip = true, mock = true, ready = true }
local flights = {} -- ['runId|name'] = { kind, role, expect, ask, ready, final } for tests sent to this client

local function flightKey(runId, name) return tostring(runId) .. '|' .. tostring(name) end

-- A test belongs to the resource named by its prefix: 'aeterna_demo.spawn' belongs to 'aeterna_demo'.
local function ownsTest(owner, name)
    return type(owner) == 'string' and type(name) == 'string' and name:sub(1, #owner + 1) == owner .. '.'
end

local function reportFlight(owner, runId, name, ok, detail, extra)
    local flight = ownsTest(owner, name) and flights[flightKey(runId, name)]
    local state = ok == true and 'pass' or ok == false and 'fail' or ok
    local refused = nil
    if not flight then refused = 'not in flight'
    elseif type(state) ~= 'string' or not RESULT_STATES[state] then refused = 'state'
    elseif flight.final then refused = 'already reported'
    elseif state == 'ready' and (flight.kind ~= 'eye' or flight.ready or flight.expect == '') then refused = 'ready'
    elseif flight.kind == 'eye' and (flight.ready or state == 'pass' or state == 'mock') then refused = 'eye'
    end
    if refused then
        AeternaCore.log.debug('selftest report dropped', { name = tostring(name), reason = refused })
        return false
    end

    local payload = { runId = runId, name = name, state = state }
    local cleanDetail = type(detail) == 'string' and AeternaCore.text.clean(detail, 300) or ''
    if cleanDetail ~= '' then payload.detail = cleanDetail end
    if type(extra) == 'table' then
        if type(extra.restored) == 'boolean' then payload.restored = extra.restored end
        if type(extra.wrote) == 'boolean' then payload.wrote = extra.wrote end
        local step = extra.step
        if type(step) == 'number' and step == math.floor(step) and step >= 1 and step <= 99 then payload.step = step end
        local expected = type(extra.expected) == 'string' and AeternaCore.text.clean(extra.expected, 80) or ''
        if expected ~= '' then payload.expected = expected end
    end

    if state == 'ready' then flight.ready = true else flight.final = true end
    TriggerServerEvent('aeterna_core:sv:selftestResult', payload)
    if state == 'ready' then
        TriggerEvent('aeterna_core:eyeAsk', runId, name, { ask = flight.ask or name, expect = flight.expect, role = flight.role })
    end
    return true
end

local function answerFlight(runId, name, answer)
    local flight = type(name) == 'string' and flights[flightKey(runId, name)]
    if not flight or flight.kind ~= 'eye' or not flight.ready or flight.final then return false end
    if answer ~= 'pass' and answer ~= 'mismatch' and answer ~= 'skip' then return false end
    flight.final = true
    TriggerServerEvent('aeterna_core:sv:eyeAnswer', { runId = runId, name = name, answer = answer })
    return true
end

-- Core's own client check: holder, then an overlay on top of it. Returns a state and a detail.
local function focusOverlayCheck()
    if focusManager:owner() ~= nil then return 'skip', 'focus is held' end
    local paused = nil
    local h = AddEventHandler('aeterna_core:focusPaused', function(owner, token) paused = { owner = owner, token = token } end)
    local holder = focusManager:request('aeterna_core', { cursor = true })
    local overlay = focusManager:request('aeterna_core.overlay', { overlay = true, cursor = true })
    local kept = focusManager:pausedToken() == holder and focusManager:owner() == 'aeterna_core.overlay'
    local pausedOk = paused ~= nil and paused.token == holder and paused.owner == 'aeterna_core'
    focusManager:release(overlay)
    local resumed = focusManager:owner() == 'aeterna_core' and focusManager:token() == holder
    focusManager:release(holder)
    RemoveEventHandler(h)
    if kept and pausedOk and resumed then return 'pass', 'overlay paused the holder and resumed it' end
    return 'fail', 'focus overlay state is wrong'
end

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if name == 'aeterna_core.client_echo' then
        reportFlight('aeterna_core', runId, name, 'pass', 'echo')
    elseif name == 'aeterna_core.focus_overlay' then
        reportFlight('aeterna_core', runId, name, focusOverlayCheck())
    end
end)

RegisterNetEvent('aeterna_core:cl:selftest')
AddEventHandler('aeterna_core:cl:selftest', function(payload)
    local ok, err, p = AeternaCore.validate(payload, TEST_SCHEMA)
    if not ok then
        AeternaCore.log.debug('selftest refused', { reason = err })
        return
    end
    local key = flightKey(p.runId, p.name)
    if flights[key] then return end
    flights[key] = { kind = p.kind, role = p.role, expect = p.expect or '', ask = p.ask }
    TriggerEvent('aeterna_core:selftest', p.runId, p.name,
        { kind = p.kind, side = 'client', role = p.role, destructive = p.destructive })
end)

RegisterNetEvent('aeterna_core:cl:selftestEnd')
AddEventHandler('aeterna_core:cl:selftestEnd', function(payload)
    local ok, _, p = AeternaCore.validate(payload, END_SCHEMA)
    local key = ok and flightKey(p.runId, p.name)
    if not key or not flights[key] then return end
    flights[key] = nil
    TriggerEvent('aeterna_core:selftestEnd', p.runId, p.name)
end)

exports('reportSelftest', function(runId, name, ok, detail, extra)
    return reportFlight(GetInvokingResource() or GetCurrentResourceName(), runId, name, ok, detail, extra)
end)

exports('answerEye', answerFlight)

AddEventHandler('aeterna_core:selftest:report', function(owner, runId, name, ok, detail, extra)
    if type(owner) == 'string' and owner == GetInvokingResource() then
        reportFlight(owner, runId, name, ok, detail, extra)
    end
end)

AddEventHandler('aeterna_core:selftest:answer', function(owner, runId, name, answer)
    if type(owner) == 'string' and owner == GetInvokingResource() then
        answerFlight(runId, name, answer)
    end
end)

TriggerEvent('aeterna_core:hello')
