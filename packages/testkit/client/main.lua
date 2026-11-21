-- aeterna_testkit client: key mappings, the eye-check card (its own NUI), the player B confirm and the env answer.

local Menu = TestkitLogic.menu

local RES = GetCurrentResourceName()
local role = 'none'

local LOCALE_KEYS = { 'testkit.eye.normally', 'testkit.eye.pass', 'testkit.eye.mismatch', 'testkit.eye.skip' }

local function t(key, vars)
    return AeternaCore.t(key, vars)
end

local function sendLocale()
    local strings = {}
    for _, k in ipairs(LOCALE_KEYS) do strings[k] = t(k) end
    SendNUIMessage({ type = 'locale', strings = strings })
end

local card = Menu.createEyeCard({
    request = function(opts) return AeternaCore.requestFocus(opts) end,
    release = function(token) AeternaCore.releaseFocus(token) end,
    answer = function(runId, name, answer)
        local ok = pcall(function() return exports.aeterna_core:answerEye(runId, name, answer) end)
        if not ok then AeternaCore.log.warn('answerEye failed', { name = tostring(name) }) end
    end,
    show = function(msg)
        local suite = tostring(msg.name):match('^aeterna_([^%.]+)%.') or tostring(msg.name):match('^([^%.]+)%.') or ''
        local header = t(msg.role == 'B' and 'testkit.eye.role_b' or 'testkit.eye.header', { index = msg.index, suite = suite })
        SendNUIMessage(AeternaCore.themeMessage())
        sendLocale()
        SendNUIMessage({ type = 'eye:show', header = header, ask = msg.ask, expect = msg.expect, index = msg.index,
            role = msg.role })
    end,
    hide = function()
        SendNUIMessage({ type = 'eye:hide' })
    end,
})

RegisterCommand('+aeterna_testkit_menu', function()
    TriggerServerEvent('aeterna_testkit:sv:open')
end, false)
RegisterCommand('-aeterna_testkit_menu', function() end, false)
AeternaCore.key('+aeterna_testkit_menu', 'testkit.key.menu')

RegisterCommand('+aeterna_testkit_leave', function()
    if role == 'B' then TriggerServerEvent('aeterna_testkit:sv:leave') end
end, false)
RegisterCommand('-aeterna_testkit_leave', function() end, false)
AeternaCore.key('+aeterna_testkit_leave', 'testkit.key.leave')

AddEventHandler('aeterna_core:eyeAsk', function(runId, name, info)
    if GetInvokingResource() ~= 'aeterna_core' or type(runId) ~= 'string' or type(name) ~= 'string' then return end
    card:ask(runId, name, info)
end)

local strip = Menu.createNowStrip({
    show = function(msg)
        SendNUIMessage(AeternaCore.themeMessage())
        SendNUIMessage({ type = 'now:show', name = msg.name, label = t('testkit.now_doing'), expect = msg.expect })
    end,
    hide = function()
        SendNUIMessage({ type = 'now:hide' })
    end,
})

-- Any aeterna_core self-test reaching this client: a ped test with expect shows the now-testing strip.
AddEventHandler('aeterna_core:selftest', function(runId, name, ctx)
    if GetInvokingResource() ~= 'aeterna_core' or type(runId) ~= 'string' or type(name) ~= 'string' then return end
    strip:started(runId, name, ctx)
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' then return end
    card:ended(runId, name)
    strip:ended(runId, name)
end)

AddEventHandler('aeterna_core:focusLost', function(owner, token)
    if owner == RES then card:lost(token) end
end)

local INVITE_SCHEMA = { type = 'table', fields = { seconds = { type = 'number', integer = true, min = 10, max = 120 } } }
local ROLE_SCHEMA = { type = 'table', fields = { role = { type = 'string', enum = { 'A', 'B', 'none' } } } }
local ANSWER_SCHEMA = { type = 'table', fields = { answer = { type = 'string', enum = { 'pass', 'mismatch', 'skip' } } } }

local inviteOpen = false

RegisterNetEvent('aeterna_testkit:cl:invite', function(payload)
    local ok = AeternaCore.validate(payload, INVITE_SCHEMA)
    if not ok or inviteOpen then return end
    inviteOpen = true
    CreateThread(function()
        local okConfirm, accept = pcall(function()
            return exports.aeterna_uikit:confirm({ title = t('testkit.menu.invite'), body = t('testkit.invite.body') })
        end)
        inviteOpen = false
        TriggerServerEvent('aeterna_testkit:sv:inviteAnswer', { accept = okConfirm and accept == true })
    end)
end)

RegisterNetEvent('aeterna_testkit:cl:role', function(payload)
    local ok, _, p = AeternaCore.validate(payload, ROLE_SCHEMA)
    if ok then role = p.role end
end)

-- The askEnv reply: the game build and the screen resolution, as sv:env carries them.
local function envReply()
    local w, h = GetActiveScreenResolution()
    return { gameBuild = math.tointeger(GetGameBuildNumber()) or 0, w = math.tointeger(w) or 0,
        h = math.tointeger(h) or 0 }
end

RegisterNetEvent('aeterna_testkit:cl:askEnv', function()
    TriggerServerEvent('aeterna_testkit:sv:env', envReply())
end)

-- Own client self-tests: env checks the askEnv reply against the sv:env schema; the eye cards need no set-up (the menu panel the
-- run was started from is the uikit panel behind the card).
local Selftest = TestkitLogic.selftest

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' or not Selftest.owns(RES, name) then return end
    local ok, detail
    if name == RES .. '.env' then
        ok, detail = Selftest.env(AeternaCore.validate, envReply())
    elseif name == RES .. '.eye_card' or name == RES .. '.eye_card_b' then
        ok, detail = 'ready', ''
    else
        return
    end
    local sent, err = pcall(function() return exports.aeterna_core:reportSelftest(runId, name, ok, detail) end)
    if not sent then AeternaCore.log.warn('reportSelftest failed', { name = name, err = tostring(err) }) end
end)

RegisterNUICallback('eyeAnswer', function(data, cb)
    local ok, _, p = AeternaCore.validate(data, ANSWER_SCHEMA)
    if ok then card:answer(p.answer) end
    cb({ ok = ok == true })
end)

RegisterNUICallback('escape', function(_, cb)
    card:escape()
    cb({ ok = true })
end)

exports('isOpen', function()
    return card:isOpen()
end)

AddEventHandler('onResourceStop', function(name)
    if name == RES then card:close() end
end)
