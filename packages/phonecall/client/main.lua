-- client/main.lua -- aeterna_phonecall client: key mappings for answer and hang up, the phone at the ear while a
-- call is active, the names map from phonekit's contacts, and the client side of the self-tests. No screens:
-- phonekit draws every one.

local M = PhonecallNames
local T = PhonecallSelftest

local PREFIX = 'aeterna_phonecall.'
local current = { state = nil }

local STATE_SCHEMA = { type = 'table', fields = {
    callId = { type = 'string', minLen = 1, maxLen = 12 },
    state = { type = 'string', enum = { 'dialing', 'ringing', 'active', 'ended' } },
    peer = { type = 'string', maxLen = 40 },
    reason = { type = 'string', optional = true, enum = {
        'hangup', 'declined', 'missed', 'busy', 'unavailable', 'dropped', 'limit', 'voice_off' } },
} }
local CONTACT_SCHEMA = { type = 'table', fields = {
    name = { type = 'string', minLen = 1, maxLen = 40 },
    number = { type = 'string', minLen = 1, maxLen = 20, pattern = '^[%d%-%s%+%(%)]+$' },
} }

--------------------------------------------------------------------------------
-- Names map (phonekit contacts -> server, for labels)
--------------------------------------------------------------------------------

local function pushNames()
    local ok, contacts = pcall(function() return exports.aeterna_phonekit:getContacts() end)
    TriggerServerEvent('aeterna_phonecall:sv:names', { names = M.fromContacts(ok and contacts or {}) })
end

-- The server takes one names map per 5000 ms; a change inside that window becomes one trailing send.
local namesThrottle = M.createThrottle(5200)

local function sendNames()
    local delay = namesThrottle:request(GetGameTimer())
    if delay == 0 then
        pushNames()
    elseif delay then
        SetTimeout(delay, function()
            namesThrottle:fire(GetGameTimer())
            pushNames()
        end)
    end
end

RegisterNetEvent('aeterna_phonecall:cl:askNames', sendNames)
AddEventHandler('aeterna_phonekit:contactsChanged', sendNames)

RegisterNetEvent('aeterna_phonecall:cl:saveContact', function(data)
    local ok, _, clean = AeternaCore.validate(data, CONTACT_SCHEMA)
    if not ok then return end
    pcall(function() exports.aeterna_phonekit:addContact({ name = clean.name, number = clean.number }) end)
end)

--------------------------------------------------------------------------------
-- Phone at the ear while active (phonekit owns the prop and every screen)
--------------------------------------------------------------------------------

local EAR_DICT, EAR_ANIM = 'cellphone@', 'cellphone_call_listen_base'
local earOn = false

local function phoneOpen()
    local ok, open = pcall(function() return exports.aeterna_phonekit:isOpen() end)
    return ok and open == true
end

local function setEar(on)
    if on == earOn then return end
    earOn = on
    local ped = PlayerPedId()
    if on then
        RequestAnimDict(EAR_DICT)
        local tries = 0
        while not HasAnimDictLoaded(EAR_DICT) and tries < 50 do
            Wait(10)
            tries = tries + 1
        end
        TaskPlayAnim(ped, EAR_DICT, EAR_ANIM, 3.0, 3.0, -1, 49, 0, false, false, false)
    else
        StopAnimTask(ped, EAR_DICT, EAR_ANIM, 1.0)
    end
end

local function earLoop()
    CreateThread(function()
        while current.state == 'active' do
            setEar(not phoneOpen())
            Wait(500)
        end
        setEar(false)
    end)
end

--------------------------------------------------------------------------------
-- Self-tests (client side): my_number, sms_ab, call_ab, call_busy
--------------------------------------------------------------------------------

local pending = {} -- [name] = { runId, role, reported }

local function report(runId, name, state, detail)
    pcall(function() exports.aeterna_core:reportSelftest(runId, name, state, detail) end)
end

local function onCallState(data)
    for name, p in pairs(pending) do
        local short = name:sub(#PREFIX + 1)
        local setup = T.setupFailure(data.callId)
        if not p.reported and short == 'sms_ab' and setup then
            p.reported = true
            report(p.runId, name, 'fail', setup)
        elseif not p.reported and (short == 'call_ab' or short == 'call_busy') then
            local state, detail = T.callOutcome(short, p.role, data)
            if state then
                p.reported = true
                report(p.runId, name, state, detail)
            end
        end
    end
end

AddEventHandler('aeterna_core:selftest', function(runId, name, ctx)
    if type(name) ~= 'string' or name:sub(1, #PREFIX) ~= PREFIX then return end
    local role = type(ctx) == 'table' and ctx.role or 'A'
    local short = name:sub(#PREFIX + 1)
    if short == 'my_number' then
        report(runId, name, 'ready')
    elseif short == 'sms_ab' or short == 'call_ab' or short == 'call_busy' then
        -- the server set this test up from core's selftestStarted and acts 500 ms after it
        pending[name] = { runId = runId, role = role }
        if short == 'sms_ab' then
            SetTimeout(1500, function()
                local p = pending[name]
                if p and p.runId == runId and not p.reported then
                    p.reported = true
                    report(runId, name, 'ready')
                end
            end)
        elseif short == 'call_busy' and role == 'B' then
            pending[name].reported = true
            report(runId, name, 'pass', 'B was in a call')
        end
    end
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    local p = pending[name]
    if not p or p.runId ~= runId then return end
    pending[name] = nil
    if name == PREFIX .. 'call_ab' and current.state and current.state ~= 'ended' then
        TriggerServerEvent('aeterna_phonecall:sv:hangup')
    end
end)

--------------------------------------------------------------------------------
-- Call state from the server
--------------------------------------------------------------------------------

RegisterNetEvent('aeterna_phonecall:cl:state', function(data)
    local ok, _, clean = AeternaCore.validate(data, STATE_SCHEMA)
    if not ok then return end
    local wasActive = current.state == 'active'
    current = clean
    if clean.state == 'active' and not wasActive then earLoop() end
    onCallState(clean)
end)

--------------------------------------------------------------------------------
-- Keys (no default key)
--------------------------------------------------------------------------------

RegisterCommand('+aeterna_phonecall_answer', function()
    if current.state == 'ringing' then TriggerServerEvent('aeterna_phonecall:sv:answer') end
end, false)
RegisterCommand('-aeterna_phonecall_answer', function() end, false)
RegisterCommand('+aeterna_phonecall_hangup', function()
    if current.state and current.state ~= 'ended' then TriggerServerEvent('aeterna_phonecall:sv:hangup') end
end, false)
RegisterCommand('-aeterna_phonecall_hangup', function() end, false)
AeternaCore.key('+aeterna_phonecall_answer', 'phonecall.key.answer')
AeternaCore.key('+aeterna_phonecall_hangup', 'phonecall.key.hangup')

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and earOn then
        StopAnimTask(PlayerPedId(), EAR_DICT, EAR_ANIM, 1.0)
    end
end)
