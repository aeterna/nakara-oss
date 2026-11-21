-- server/main.lua -- aeterna_phonecall server: numbers, messages and calls as two phonekit apps (Phone, Messages).
-- Pure rules live in shared/logic/; this file wires them to KVP, phonekit's exports, the voice natives and events.

local N = PhonecallNumber
local S = PhonecallStore
local L = PhonecallLimits
local M = PhonecallNames
local C = PhonecallCalls
local V = PhonecallVoice
local T = PhonecallSelftest

local RES = GetCurrentResourceName()
local PREFIX = 'aeterna_phonecall.'
local MAX_MESSAGE_BLOCKS = 34 -- phonekit draws at most 40 blocks; the rest of a thread screen takes up to 3

local function logWarn(msg, fields) AeternaCore.log.warn(msg, fields) end
local function logError(msg, fields) AeternaCore.log.error(msg, fields) end
local function t(key, vars) return AeternaCore.t(key, vars) end
local function cut(s, n) return AeternaCore.text.cut(s, n) end

local Cfg = PhonecallConfig.resolve(Config, logWarn, logError)

--------------------------------------------------------------------------------
-- Server resource KVP (JSON values)
--------------------------------------------------------------------------------

local function kvpKey(name, id) return ('aeterna_phonecall:%s:v1:%s'):format(name, id) end

local function readJson(key)
    local raw = GetResourceKvpString(key)
    if raw == nil or raw == '' then return nil end
    local ok, value = pcall(json.decode, raw)
    return ok and value or nil
end

local function writeJson(key, value)
    local okEnc, encoded = pcall(json.encode, value)
    if not okEnc or type(encoded) ~= 'string' then return false end
    return (pcall(SetResourceKvp, key, encoded))
end

local function numberOf(who)
    local v = who and readJson(kvpKey('number', who))
    return type(v) == 'table' and type(v.number) == 'string' and v.number or nil
end

local function ownerOf(digits)
    if type(digits) ~= 'string' or digits == '' then return nil end
    local v = readJson(kvpKey('owner', digits))
    return type(v) == 'string' and v or nil
end

local function loadList(name, who)
    local v = readJson(kvpKey(name, who))
    return type(v) == 'table' and v or {}
end

local function saveList(name, who, list)
    return S.shrinkToFit(list, function(l) return writeJson(kvpKey(name, who), l) end, logWarn)
end

local smsIo = {
    load = function(who) return loadList('sms', who) end,
    save = function(who, list) saveList('sms', who, list) end,
}

local idSeq = 0
local function nextId()
    idSeq = (idSeq + 1) % 1000
    return S.makeId(os.time() * 1000 + idSeq)
end

--------------------------------------------------------------------------------
-- Numbers
--------------------------------------------------------------------------------

local function isTaken(digits)
    return ownerOf(digits) ~= nil
end

local function assignNumber(who)
    if not who then return nil end
    local current = numberOf(who)
    if current then return current end
    local n = N.draw(Cfg.number.format, {
        rng = math.random, reserved = Cfg.number.reserved, isTaken = isTaken,
    })
    if not n then
        logError('number pool exhausted', { format = Cfg.number.format })
        return nil
    end
    writeJson(kvpKey('number', who), { number = n })
    writeJson(kvpKey('owner', N.digits(n)), who)
    return n
end

-- Admin change: the input must fit the format and be free. Returns the number or nil, locale key.
local function setNumber(who, input)
    local n = type(input) == 'string' and N.normalize(Cfg.number.format, input) or nil
    if not n then return nil, 'phonecall.admin.format' end
    local digits = N.digits(n)
    local holder = ownerOf(digits)
    if (holder ~= nil and holder ~= who) or N.isReserved(Cfg.number.reserved, n) then
        return nil, 'phonecall.admin.taken'
    end
    local old = numberOf(who)
    if old and N.digits(old) ~= digits then DeleteResourceKvp(kvpKey('owner', N.digits(old))) end
    writeJson(kvpKey('number', who), { number = n })
    writeJson(kvpKey('owner', digits), who)
    return n
end

-- A peer stored as digits, shown in the format when it fits.
local function shown(digits)
    return N.normalize(Cfg.number.format, digits) or digits
end

--------------------------------------------------------------------------------
-- Sessions (per player, in memory): character key, names map, screens on display
--------------------------------------------------------------------------------

local sessions = {}
local whoOnline = {}
local gone = {}

local function qbxStarted()
    return GetResourceState('qbx_core') == 'started'
end

-- `cid:<citizenid>` with qbx_core, else `lic:<license>`; nil while qbx_core has no character loaded.
local function whoOf(src)
    if qbxStarted() then
        local ok, player = pcall(function() return exports.qbx_core:GetPlayer(src) end)
        local cid = ok and type(player) == 'table' and type(player.PlayerData) == 'table'
            and player.PlayerData.citizenid or nil
        if type(cid) ~= 'string' or cid == '' then return nil end
        return 'cid:' .. cid
    end
    local ok, license = pcall(GetPlayerIdentifierByType, src, 'license')
    if not ok or type(license) ~= 'string' or license == '' then return nil end
    return 'lic:' .. license
end

local function session(src)
    src = tonumber(src)
    if not src or gone[src] then return nil end
    if sessions[src] then return sessions[src] end
    local who = whoOf(src)
    if not who then return nil end
    local s = { who = who, names = {}, screens = {}, order = {} }
    sessions[src] = s
    whoOnline[who] = src
    if Cfg.number.assign == 'on_load' then assignNumber(who) end
    return s
end

local function peerLabel(src, number)
    local s = sessions[src]
    return M.label(s and s.names, number)
end

local function refreshBadge(src)
    local s = session(src)
    if not s then return end
    local unread = S.unread(loadList('sms', s.who))
    pcall(function() exports.aeterna_phonekit:badge(src, 'messages', unread) end)
end

local APP_OF = { phone = 'phone', call = 'phone', messages = 'messages', thread = 'messages', compose = 'messages' }

-- Draws a screen through phonekit and remembers what it is, by screen id (phonekit's Back re-shows old ones).
local function show(src, kind, spec, data)
    local s = sessions[src]
    if not s then return nil end
    local ok, screenId = pcall(function() return exports.aeterna_phonekit:showApp(src, APP_OF[kind], spec) end)
    if not ok or type(screenId) ~= 'string' then return nil end
    s.screens[screenId] = { kind = kind, data = data or {} }
    s.order[#s.order + 1] = screenId
    while #s.order > 16 do s.screens[table.remove(s.order, 1)] = nil end
    s.lastShown = screenId
    return screenId
end

local function update(src, screenId, patch)
    pcall(function() exports.aeterna_phonekit:updateApp(src, screenId, patch) end)
end

local function numberLine(who)
    local n = numberOf(who)
    return n and t('phonecall.number.mine', { number = n }) or t('phonecall.number.none')
end

--------------------------------------------------------------------------------
-- Voice backend and calls
--------------------------------------------------------------------------------

local backend = V.create({
    gamename = GetConvar('gamename', ''),
    natives = {
        CreateVoiceChannel = CreateVoiceChannel,
        AddPlayerToVoiceChannel = AddPlayerToVoiceChannel,
        RemovePlayerFromVoiceChannel = RemovePlayerFromVoiceChannel,
        SetPlayerMutedInVoiceChannel = SetPlayerMutedInVoiceChannel,
        DeleteVoiceChannel = DeleteVoiceChannel,
    },
    resourceState = GetResourceState,
    setPlayerCall = function(src, channel) exports['pma-voice']:setPlayerCall(src, channel) end,
    channelBase = Cfg.call.channelBase,
    warn = logWarn,
})

local function nowSec() return GetGameTimer() / 1000 end

local calls = C.create({ now = nowSec, ringSeconds = Cfg.call.ringSeconds, maxSeconds = Cfg.call.maxMinutes * 60 })

local function connected(src)
    return not gone[src] and GetPlayerName(src) ~= nil
end

local function canCall(src)
    local ok, yes = pcall(function() return exports.aeterna_phonekit:canCall(src) end)
    return ok and yes == true
end

local function mmss(sec)
    sec = math.max(0, math.floor(sec))
    return ('%02d:%02d'):format(sec // 60, sec % 60)
end

local function peerNumberOf(call, src)
    return src == call.from and call.toNum or call.fromNum
end

local function statusLine(call, src)
    local view = calls:viewState(call, src)
    if view == 'dialing' then return t('phonecall.call.dialing') end
    if view == 'ringing' then return t('phonecall.call.incoming') end
    if view == 'active' then return t('phonecall.call.active', { time = mmss(nowSec() - call.activeAt) }) end
    return t('phonecall.end.' .. tostring(call.reason))
end

local function callSpec(call, src)
    local peer = peerNumberOf(call, src)
    local items
    if calls:viewState(call, src) == 'ringing' then
        items = { { id = 'answer', label = t('phonecall.call.answer'), variant = 'primary' },
            { id = 'decline', label = t('phonecall.call.decline'), variant = 'danger' } }
    else
        items = { { id = 'hangup', label = t('phonecall.call.hangup'), variant = 'danger' } }
    end
    return {
        title = cut(peerLabel(src, peer), 60),
        subtitle = peer,
        blocks = {
            { id = 'status', type = 'text', label = statusLine(call, src) },
            { id = 'actions', type = 'buttons', items = items },
        },
    }
end

local function sendState(src, callId, state, peer, reason)
    if not connected(src) then return end
    TriggerClientEvent('aeterna_phonecall:cl:state', src, {
        callId = callId, state = state, peer = cut(peerLabel(src, peer), 40), reason = reason,
    })
end

local function emitCall(callId, state, call, reason)
    TriggerEvent('aeterna_phonecall:call', callId, state, { from = call.fromNum, to = call.toNum, reason = reason })
end

local function callScreens(src, callId)
    local s = sessions[src]
    local out = {}
    for screenId, scr in pairs(s and s.screens or {}) do
        if scr.kind == 'call' and scr.data.callId == callId then out[#out + 1] = screenId end
    end
    return out
end

local function refreshCallScreens(call, src)
    for _, screenId in ipairs(callScreens(src, call.id)) do
        update(src, screenId, { blocks = { status = { label = statusLine(call, src) } } })
    end
end

local function logCall(who, entry)
    if not who then return end
    saveList('calls', who, S.push(loadList('calls', who), entry, Cfg.recentCalls))
end

local phoneHome -- forward

local endCall
endCall = function(call, reason)
    local wasRinging = call.state == 'ringing'
    if not calls:finish(call, reason) then return false end
    if wasRinging and call.ringId and connected(call.to) then
        pcall(function() exports.aeterna_phonekit:stopRing(call.to, call.ringId) end)
    end
    if call.voice then backend:disconnect(call, connected) end
    local ts = os.time()
    for _, src in ipairs({ call.from, call.to }) do
        if call.wasActive and connected(src) then
            pcall(function() exports.aeterna_phonekit:activity(src, 'call', false) end)
            pcall(function() exports.aeterna_phonekit:live(src, nil) end)
        end
        sendState(src, call.id, 'ended', peerNumberOf(call, src), reason)
        local screens = callScreens(src, call.id)
        for _, screenId in ipairs(screens) do
            update(src, screenId, { blocks = { status = { label = t('phonecall.end.' .. reason) } } })
        end
        if #screens > 0 then
            SetTimeout(3000, function()
                local s = sessions[src]
                if s and s.lastShown == screens[#screens] then phoneHome(src) end
            end)
        end
    end
    local result = call.wasActive and 'answered' or reason
    logCall(call.fromWho, { peer = call.toNum, dir = 'out', result = result, ts = ts, seconds = call.seconds })
    logCall(call.toWho, { peer = call.fromNum, dir = 'in', result = result, ts = ts, seconds = call.seconds })
    emitCall(call.id, 'ended', call, reason)
    return true
end

local refusedSeq = 0

-- Places a call from `a` (number aNum) to `b` (nil when the number is unknown or offline, number bNum).
local function placeCall(a, b, aNum, bNum)
    local call, reason = calls:dial(a, b, {
        backend = backend:available(), aCan = canCall(a), bCan = b ~= nil and canCall(b),
    })
    if not call then
        refusedSeq = refusedSeq + 1
        local id = 'x' .. S.makeId(refusedSeq)
        sendState(a, id, 'ended', bNum, reason)
        local s = sessions[a]
        logCall(s and s.who, { peer = bNum, dir = 'out', result = reason, ts = os.time(), seconds = 0 })
        emitCall(id, 'ended', { fromNum = aNum, toNum = bNum }, reason)
        return nil, reason
    end
    call.fromNum, call.toNum = aNum, bNum
    call.fromWho = sessions[a] and sessions[a].who
    call.toWho = sessions[b] and sessions[b].who
    call.startedTs = os.time()
    local okRing, ringId, err = pcall(function()
        return exports.aeterna_phonekit:ring(b, 'phone', {
            title = cut(peerLabel(b, aNum), 40), body = t('phonecall.call.incoming'),
        })
    end)
    if not okRing or not ringId then
        endCall(call, err == 'busy' and 'busy' or 'unavailable')
        return nil, 'unavailable'
    end
    call.ringId = ringId
    emitCall(call.id, 'dialing', call)
    sendState(a, call.id, 'dialing', bNum)
    sendState(b, call.id, 'ringing', aNum)
    show(a, 'call', callSpec(call, a), { callId = call.id })
    return call
end

local function answerCall(src)
    local call = calls:answer(src)
    if not call then return false end
    if call.ringId then
        pcall(function() exports.aeterna_phonekit:stopRing(call.to, call.ringId) end)
    end
    local ok = backend:connect(call, { call.from, call.to })
    if not ok then
        endCall(call, 'voice_off')
        return false
    end
    call.activeTs = os.time()
    for _, p in ipairs({ call.from, call.to }) do
        pcall(function() exports.aeterna_phonekit:activity(p, 'call', true) end)
        pcall(function() exports.aeterna_phonekit:live(p, { id = 'call', text = mmss(0) }) end)
        sendState(p, call.id, 'active', peerNumberOf(call, p))
        if #callScreens(p, call.id) > 0 then
            refreshCallScreens(call, p)
        else
            show(p, 'call', callSpec(call, p), { callId = call.id })
        end
    end
    emitCall(call.id, 'active', call)
    return true
end

local function hangupBy(src)
    local call, reason = calls:hangup(src)
    if call then return endCall(call, reason) end
    return false
end

-- Dial from the Phone app (or a contact intent): the number typed, re-validated and rate limited.
local function dialFrom(src, input)
    local s = session(src)
    if not s then return end
    local ok, _, clean = AeternaCore.validate({ number = input }, L.DIAL_SCHEMA)
    if not ok then return end
    if not L.checkDial(AeternaCore.rateLimit, src) then return end
    local mine = assignNumber(s.who)
    if not mine then return end
    local calleeWho = ownerOf(N.digits(clean.number))
    local b = calleeWho and whoOnline[calleeWho] or nil
    placeCall(src, b, mine, calleeWho and numberOf(calleeWho) or clean.number)
end

--------------------------------------------------------------------------------
-- Screens: Phone (home, in call) and Messages (home, thread, compose)
--------------------------------------------------------------------------------

local function recentMeta(r)
    local when = AeternaCore.time.format(r.ts, 'DD/MM HH:mm')
    local what = r.result == 'answered' and mmss(r.seconds or 0) or t('phonecall.end.' .. tostring(r.result))
    return cut(when .. ' · ' .. what, 30)
end

phoneHome = function(src, prefill)
    local s = session(src)
    if not s then return end
    local blocks = {}
    local voice = backend:available()
    if not voice then
        blocks[#blocks + 1] = { id = 'unavailable', type = 'text', label = t('phonecall.call.unavailable_server') }
    end
    blocks[#blocks + 1] = { id = 'number', type = 'field', label = t('phonecall.dial.title'), input = 'text',
        maxLen = 20, value = cut(prefill or '', 20) }
    blocks[#blocks + 1] = { id = 'actions', type = 'buttons', items = {
        { id = 'call', label = t('phonecall.dial.call'), variant = 'primary', disabled = not voice } } }
    local recents, items, map = loadList('calls', s.who), {}, {}
    for i = #recents, 1, -1 do
        if #items >= 50 then break end
        local r = recents[i]
        if type(r) == 'table' and type(r.peer) == 'string' then
            local id = 'r' .. (#items + 1)
            items[#items + 1] = { id = id, label = cut(peerLabel(src, r.peer), 60), meta = recentMeta(r),
                icon = r.dir == 'in' and 'arrow-down' or 'arrow-up' }
            map[id] = r.peer
        end
    end
    blocks[#blocks + 1] = { id = 'recent', type = 'list', label = t('phonecall.recent.title'), items = items,
        empty = { label = t('phonecall.recent.empty') } }
    return show(src, 'phone', { title = t('phonecall.app.phone'), subtitle = numberLine(s.who), blocks = blocks },
        { recent = map })
end

local function messagesHome(src)
    local s = session(src)
    if not s then return end
    local items, map = {}, {}
    for i, th in ipairs(S.threads(loadList('sms', s.who))) do
        local id = 't' .. i
        local label = th.svc and th.peer or peerLabel(src, shown(th.peer))
        local when = AeternaCore.time.format(th.ts, 'DD/MM HH:mm')
        items[#items + 1] = { id = id, label = cut(label, 60),
            meta = cut(th.unread > 0 and ('(' .. th.unread .. ') ' .. when) or when, 30),
            icon = th.svc and 'info' or 'message-circle' }
        map[id] = { peer = th.peer, svc = th.svc }
    end
    return show(src, 'messages', {
        title = t('phonecall.app.messages'),
        subtitle = numberLine(s.who),
        blocks = {
            { id = 'actions', type = 'buttons', items = {
                { id = 'compose', label = t('phonecall.sms.compose'), variant = 'primary' } } },
            { id = 'threads', type = 'list', items = items, empty = { label = t('phonecall.sms.empty') } },
        },
    }, { threads = map })
end

local function threadScreen(src, peer, svc)
    local s = session(src)
    if not s then return end
    local list = loadList('sms', s.who)
    if S.markRead(list, peer, svc) > 0 then
        saveList('sms', s.who, list)
        refreshBadge(src)
    end
    local msgs = S.thread(list, peer, svc)
    local blocks = {}
    for i = math.max(1, #msgs - MAX_MESSAGE_BLOCKS + 1), #msgs do
        local m = msgs[i]
        blocks[#blocks + 1] = { id = 'm' .. i, type = 'text', label = (m.dir == 'out' and '» ' or '') .. m.body }
    end
    local number = shown(peer)
    if not svc then
        blocks[#blocks + 1] = { id = 'body', type = 'field', label = t('phonecall.sms.title'), input = 'text',
            maxLen = Cfg.sms.maxLen, value = '' }
        local buttons = { { id = 'send', label = t('phonecall.sms.send'), variant = 'primary' } }
        if backend:available() then
            buttons[#buttons + 1] = { id = 'call', label = t('phonecall.dial.call'), variant = 'secondary' }
        end
        if not s.names[peer] then
            blocks[#blocks + 1] = { id = 'cname', type = 'field', label = t('phonecall.contact.save'), input = 'text',
                maxLen = 40, value = '' }
            buttons[#buttons + 1] = { id = 'save', label = t('phonecall.contact.save'), variant = 'secondary' }
        end
        blocks[#blocks + 1] = { id = 'actions', type = 'buttons', items = buttons }
    elseif #blocks == 0 then
        blocks[1] = { id = 'svc', type = 'text', label = t('phonecall.sms.service') }
    end
    return show(src, 'thread', {
        title = cut(svc and peer or peerLabel(src, number), 60),
        subtitle = svc and t('phonecall.sms.service') or number,
        blocks = blocks,
    }, { peer = peer, svc = svc })
end

local function composeScreen(src, prefill)
    local s = session(src)
    if not s then return end
    return show(src, 'compose', {
        title = t('phonecall.sms.compose'),
        subtitle = numberLine(s.who),
        blocks = {
            { id = 'number', type = 'field', label = t('phonecall.dial.title'), input = 'text', maxLen = 20,
                value = cut(prefill or '', 20) },
            { id = 'body', type = 'field', label = t('phonecall.sms.title'), input = 'text', maxLen = Cfg.sms.maxLen,
                value = '' },
            { id = 'actions', type = 'buttons', items = {
                { id = 'send', label = t('phonecall.sms.send'), variant = 'primary' } } },
        },
    })
end

--------------------------------------------------------------------------------
-- Messages
--------------------------------------------------------------------------------

local function notifyMessage(dst, fromText, body)
    pcall(function()
        exports.aeterna_phonekit:notifyApp(dst, 'messages', {
            title = cut(fromText, 60), body = cut(body, 60),
        })
    end)
end

-- A player's message. Returns true, or false and a locale key (shown in the body field's label).
local function sendFromPlayer(src, numberInput, bodyInput)
    local s = session(src)
    if not s then return false end
    local ok, _, clean = AeternaCore.validate({ number = numberInput, body = bodyInput }, L.SEND_SCHEMA)
    if not ok then return false end
    local body, emptyKey = S.cleanBody(AeternaCore.text, clean.body, Cfg.sms.maxLen)
    if not body then return false, emptyKey end
    local toDigits = N.digits(clean.number)
    local okRate, slowKey = L.checkSms(AeternaCore.rateLimit, src, toDigits)
    if not okRate then return false, slowKey end
    local mine = assignNumber(s.who)
    if not mine then return false, 'phonecall.number.none' end
    local toWho = ownerOf(toDigits)
    local delivered, out = S.deliver(smsIo, {
        fromWho = s.who, toWho = toWho, fromPeer = N.digits(mine), toPeer = toDigits, body = body,
        ts = os.time(), keep = Cfg.sms.keep, idOut = nextId(), idIn = nextId(),
    })
    if not delivered then return false, out end
    local dst = whoOnline[toWho]
    if dst then notifyMessage(dst, peerLabel(dst, mine), body) end
    TriggerEvent('aeterna_phonecall:sms', mine, numberOf(toWho) or clean.number, { id = out.id, ts = out.ts })
    return true, toDigits
end

local function refuseInField(src, screenId, key)
    if key then update(src, screenId, { blocks = { body = { label = cut(t(key), 40) } } }) end
end

--------------------------------------------------------------------------------
-- phonekit hooks: tiles, app taps, actions, ring answers, power
--------------------------------------------------------------------------------

local function registerTiles()
    pcall(function()
        exports.aeterna_phonekit:addTile({ id = 'phone', label = t('phonecall.app.phone'), icon = 'phone', order = 10,
            needs = 'voice', handles = { 'tel' } })
        exports.aeterna_phonekit:addTile({ id = 'messages', label = t('phonecall.app.messages'),
            icon = 'message-circle', order = 11, handles = { 'sms' } })
    end)
end

AddEventHandler('aeterna_phonekit:hello', registerTiles)

AddEventHandler('aeterna_phonekit:app', function(src, payload)
    if type(payload) ~= 'table' or payload.owner ~= RES then return end
    local s = session(src)
    if not s then return end
    if Cfg.number.assign == 'first_open' then assignNumber(s.who) end
    TriggerClientEvent('aeterna_phonecall:cl:askNames', src)
    local intent = type(payload.intent) == 'table' and payload.intent or nil
    if payload.id == 'phone' then
        local call = calls:of(src)
        if call then
            show(src, 'call', callSpec(call, src), { callId = call.id })
        else
            phoneHome(src, intent and intent.kind == 'tel' and intent.number or nil)
        end
    elseif payload.id == 'messages' then
        if intent and intent.kind == 'sms' and N.digits(intent.number) ~= '' then
            threadScreen(src, N.digits(intent.number), false)
        else
            messagesHome(src)
        end
    end
end)

local function onRing(src, ringId, answer)
    local call = calls:of(src)
    if not call or call.to ~= src or call.ringId ~= ringId or call.state ~= 'ringing' then return end
    if answer then answerCall(src) else endCall(call, 'declined') end
end

local function onAction(src, scr, screenId, action, values)
    local kind, data = scr.kind, scr.data
    if kind == 'phone' then
        if action == 'call' then
            dialFrom(src, values.number)
        elseif data.recent and data.recent[action] then
            update(src, screenId, { blocks = { number = { value = data.recent[action] } } })
        end
    elseif kind == 'call' then
        if action == 'answer' then
            local call = calls:of(src)
            if call and call.id == data.callId then answerCall(src) end
        elseif action == 'hangup' or action == 'decline' then
            local call = calls:of(src)
            if call and call.id == data.callId then hangupBy(src) end
        end
    elseif kind == 'messages' then
        if action == 'compose' then
            composeScreen(src)
        elseif data.threads and data.threads[action] then
            threadScreen(src, data.threads[action].peer, data.threads[action].svc)
        end
    elseif kind == 'thread' then
        if data.svc then return end
        if action == 'send' then
            local ok, key = sendFromPlayer(src, data.peer, values.body)
            if ok then threadScreen(src, data.peer, false) else refuseInField(src, screenId, key) end
        elseif action == 'call' then
            dialFrom(src, data.peer)
        elseif action == 'save' then
            local name = AeternaCore.text.clean(type(values.cname) == 'string' and values.cname or '', 40)
            if name ~= '' then
                TriggerClientEvent('aeterna_phonecall:cl:saveContact', src, { name = name, number = shown(data.peer) })
            end
        end
    elseif kind == 'compose' and action == 'send' then
        local ok, result = sendFromPlayer(src, values.number, values.body)
        if ok then threadScreen(src, result, false) else refuseInField(src, screenId, result) end
    end
end

AddEventHandler('aeterna_phonekit:action', function(src, payload)
    if type(payload) ~= 'table' or payload.owner ~= RES then return end
    src = tonumber(src)
    if not src then return end
    if payload.action == '__answer' or payload.action == '__decline' then
        return onRing(src, payload.screenId, payload.action == '__answer')
    end
    local s = sessions[src]
    if not s then return end
    if payload.action == '__close' then
        s.screens, s.order, s.lastShown = {}, {}, nil
        return
    end
    local scr = s.screens[payload.screenId]
    if not scr then return end
    onAction(src, scr, payload.screenId, payload.action, type(payload.values) == 'table' and payload.values or {})
end)

AddEventHandler('aeterna_phonekit:power', function(src, data)
    local call = calls:of(tonumber(src))
    if call and type(data) == 'table' and data.on == false then endCall(call, 'dropped') end
end)

--------------------------------------------------------------------------------
-- Net events
--------------------------------------------------------------------------------

RegisterNetEvent('aeterna_phonecall:sv:names', function(data)
    local src = source
    if not AeternaCore.rateLimit(src, 'phonecall:names', 1, 5000) then return end
    local okShape = type(data) == 'table'
    for k in pairs(okShape and data or {}) do
        if k ~= 'names' then okShape = false end
    end
    local ok, clean = false, 'names: type'
    if okShape then ok, clean = M.validate(data.names) end
    if not ok then
        logWarn('aeterna_phonecall:sv:names invalid payload', { src = src, err = clean })
        return
    end
    local s = session(src)
    if not s then return end
    s.names = clean
    if not s.badgeSent then
        s.badgeSent = true
        refreshBadge(src)
    end
end)

RegisterNetEvent('aeterna_phonecall:sv:answer', function()
    local src = source
    if not AeternaCore.rateLimit(src, 'phonecall:answer', 2, 1000) then return end
    answerCall(src)
end)

RegisterNetEvent('aeterna_phonecall:sv:hangup', function()
    local src = source
    if not AeternaCore.rateLimit(src, 'phonecall:hangup', 2, 1000) then return end
    hangupBy(src)
end)

--------------------------------------------------------------------------------
-- Ticks: ring timeouts, the call limit, the running timer
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(1000)
        for _, due in ipairs(calls:expire()) do endCall(due.call, due.reason) end
        for _, call in ipairs(calls:all()) do
            if call.state == 'active' then
                local text = mmss(nowSec() - call.activeAt)
                for _, p in ipairs({ call.from, call.to }) do
                    pcall(function() exports.aeterna_phonekit:live(p, { id = 'call', text = text }) end)
                    refreshCallScreens(call, p)
                end
            end
        end
    end
end)

--------------------------------------------------------------------------------
-- Players: load, character switch, drop
--------------------------------------------------------------------------------

local function dropSession(src, reason)
    src = tonumber(src)
    if not src then return end
    local call = calls:of(src)
    if call then endCall(call, reason or 'dropped') end
    local s = sessions[src]
    if s and whoOnline[s.who] == src then whoOnline[s.who] = nil end
    sessions[src] = nil
end

AddEventHandler('QBCore:Server:OnPlayerUnload', function(src)
    dropSession(src or source, 'dropped')
end)

AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
    local src = type(player) == 'table' and type(player.PlayerData) == 'table' and player.PlayerData.source or nil
    if not src then return end
    dropSession(src, 'dropped')
    if session(src) then refreshBadge(src) end
end)

AddEventHandler('playerJoining', function()
    local src = tonumber(source)
    if not src then return end
    gone[src] = nil
    if not qbxStarted() then session(src) end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    gone[src] = true
    dropSession(src, 'dropped')
    SetTimeout(5000, function() gone[src] = nil end)
end)

AddEventHandler('onResourceStop', function(name)
    if name == 'pma-voice' and backend.kind == 'pma' then
        for _, call in ipairs(calls:all()) do endCall(call, 'voice_off') end
    elseif name == RES then
        for _, call in ipairs(calls:all()) do
            if call.voice then backend:disconnect(call, connected) end
        end
    end
end)

--------------------------------------------------------------------------------
-- Exports (server)
--------------------------------------------------------------------------------

exports('getNumber', function(src)
    local s = session(src)
    if not s then return nil end
    if Cfg.number.assign == 'on_load' then return assignNumber(s.who) end
    return numberOf(s.who)
end)

exports('findByNumber', function(number)
    local who = ownerOf(N.digits(number))
    return who and whoOnline[who] or nil
end)

exports('sendSms', function(fromLabel, toNumber, body)
    local res = GetInvokingResource() or RES
    if type(fromLabel) ~= 'string' or type(toNumber) ~= 'string' then return false, 'invalid' end
    local label = AeternaCore.text.clean(fromLabel, 24)
    if label == '' then return false, 'invalid' end
    local clean, emptyKey = S.cleanBody(AeternaCore.text, body, Cfg.sms.maxLen)
    if not clean then return false, emptyKey end
    if not L.checkService(AeternaCore.rateLimit, res) then return false, 'phonecall.sms.slow' end
    local toWho = ownerOf(N.digits(toNumber))
    local ok, _, inc = S.deliver(smsIo, {
        toWho = toWho, fromPeer = label, toPeer = N.digits(toNumber), body = clean, ts = os.time(),
        keep = Cfg.sms.keep, idIn = nextId(), svc = true,
    })
    if not ok then return false, 'phonecall.sms.unknown' end
    local dst = whoOnline[toWho]
    if dst then notifyMessage(dst, label, clean) end
    TriggerEvent('aeterna_phonecall:sms', label, toNumber, { id = inc.id, ts = inc.ts })
    return true
end)

exports('endCall', function(src, reason)
    local r = reason or 'hangup'
    local call = calls:of(tonumber(src))
    if not call or not C.REASONS[r] then return false end
    return endCall(call, r)
end)

exports('callState', function(src)
    local p = tonumber(src)
    local call = calls:of(p)
    if not call then return nil end
    return { state = calls:viewState(call, p), peerNumber = peerNumberOf(call, p),
        since = call.activeTs or call.startedTs }
end)

--------------------------------------------------------------------------------
-- Admin commands (console or ACE aeterna.phonecall.admin)
--------------------------------------------------------------------------------

local function targetSession(arg)
    local target = tonumber(arg)
    if not target or GetPlayerName(target) == nil then return nil end
    return session(target), target
end

RegisterCommand('aeterna_phonecall_number', function(source, args)
    if not AeternaCore.can(source, 'aeterna.phonecall.admin') then return end
    local s, target = targetSession(args[1])
    if not s then
        print(t('phonecall.admin.usage'))
        return
    end
    print(('[%s] %s: %s'):format(RES, target, numberOf(s.who) or t('phonecall.number.none')))
end, false)

RegisterCommand('aeterna_phonecall_setnumber', function(source, args)
    if not AeternaCore.can(source, 'aeterna.phonecall.admin') then return end
    local s, target = targetSession(args[1])
    if not s or type(args[2]) ~= 'string' then
        print(t('phonecall.admin.usage'))
        return
    end
    local n, err = setNumber(s.who, args[2])
    if not n then
        print(t(err, { format = Cfg.number.format }))
        return
    end
    print(('[%s] %s: %s'):format(RES, target, t('phonecall.number.mine', { number = n })))
    local last = s.lastShown and s.screens[s.lastShown]
    if last and APP_OF[last.kind] == 'phone' then phoneHome(target) elseif last then messagesHome(target) end
end, false)

--------------------------------------------------------------------------------
-- Self-tests (spec "Self-tests (0.2)"): decisions in shared/logic/selftest.lua
--------------------------------------------------------------------------------

local function report(runId, name, state, detail, extra)
    pcall(function() exports.aeterna_core:reportSelftest(runId, name, state, detail, extra) end)
end

local FAKE = { 'test:a', 'test:b' }

-- Deletes every key the mock tests write for the fake keys. Returns true when none is left.
local function clearFake()
    for _, who in ipairs(FAKE) do
        local n = numberOf(who)
        if n then DeleteResourceKvp(kvpKey('owner', N.digits(n))) end
        DeleteResourceKvp(kvpKey('number', who))
        DeleteResourceKvp(kvpKey('sms', who))
    end
    for _, who in ipairs(FAKE) do
        if GetResourceKvpString(kvpKey('number', who)) or GetResourceKvpString(kvpKey('sms', who)) then
            return false
        end
    end
    return true
end

local function testNumberUnique()
    clearFake()
    local a, b = assignNumber(FAKE[1]), assignNumber(FAKE[2])
    local r = { a = a, b = b }
    if a and b then
        r.ownerA, r.ownerB = ownerOf(N.digits(a)), ownerOf(N.digits(b))
        r.takenRefused = select(2, setNumber(FAKE[2], a)) == 'phonecall.admin.taken'
    end
    local ownerKeys = { a and kvpKey('owner', N.digits(a)), b and kvpKey('owner', N.digits(b)) }
    r.restored = clearFake()
    for _, k in pairs(ownerKeys) do
        if GetResourceKvpString(k) then r.restored = false end
    end
    return T.numberUnique(r)
end

local function testSmsCap()
    clearFake()
    local a, b = assignNumber(FAKE[1]), assignNumber(FAKE[2])
    local r = { keep = Cfg.sms.keep }
    if a and b then
        for i = 1, Cfg.sms.keep + 1 do
            S.deliver(smsIo, { fromWho = FAKE[1], toWho = FAKE[2], fromPeer = N.digits(a), toPeer = N.digits(b),
                body = 'm' .. i, ts = i, keep = Cfg.sms.keep, idOut = S.makeId(i), idIn = S.makeId(i) })
        end
        local la, lb = loadList('sms', FAKE[1]), loadList('sms', FAKE[2])
        r.lenA, r.lenB = #la, #lb
        r.oldestGone = la[1] ~= nil and la[1].body == 'm2' and lb[1] ~= nil and lb[1].body == 'm2'
    end
    r.restored = clearFake()
    return T.smsCap(r)
end

local SERVER_TESTS = {
    number_format = function() return T.numberFormat(N, Cfg.number.format, math.random) end,
    number_unique = testNumberUnique,
    sms_store_cap = testSmsCap,
    voice_detect = function() return T.voiceDetect(backend:name()) end,
    voice_channel = function()
        local ok, detail
        if backend:name() == 'channels' then ok, detail = backend:probe() end
        return T.voiceChannel(backend:name(), ok, detail)
    end,
}

AddEventHandler('aeterna_core:selftest', function(runId, name, ctx)
    if type(name) ~= 'string' or name:sub(1, #PREFIX) ~= PREFIX then return end
    if type(ctx) == 'table' and ctx.side ~= nil and ctx.side ~= 'server' then return end
    local short = name:sub(#PREFIX + 1)
    local state, detail
    if short == 'sms_rate_limit' then
        state, detail = T.smsRate(L, AeternaCore.rateLimit, 'selftest:' .. tostring(runId))
    elseif SERVER_TESTS[short] then
        local ok, s, d = pcall(SERVER_TESTS[short])
        if ok then state, detail = s, d else state, detail = 'fail', tostring(s) end
    else
        return
    end
    report(runId, name, state, detail, state == 'mock' and { restored = true } or nil)
end)

-- Two-player tests: both clients join; the server acts once it has A and B of a test that is in flight.
local selftestPairs = T.createPairs()
local SELFTEST_SCHEMA = { type = 'table', fields = {
    runId = { type = 'string', minLen = 1, maxLen = 24 },
    name = { type = 'string', enum = { PREFIX .. 'sms_ab', PREFIX .. 'call_ab', PREFIX .. 'call_busy' } },
    role = { type = 'string', enum = { 'A', 'B' } },
} }

local function selftestPair(name, a, b)
    local sa, sb = session(a), session(b)
    if not sa or not sb then return end
    local na, nb = assignNumber(sa.who), assignNumber(sb.who)
    if not na or not nb then return end
    if name == PREFIX .. 'sms_ab' then
        S.deliver(smsIo, { fromWho = sa.who, toWho = sb.who, fromPeer = N.digits(na), toPeer = N.digits(nb),
            body = 'Self-test', ts = os.time(), keep = Cfg.sms.keep, idOut = nextId(), idIn = nextId() })
        notifyMessage(b, peerLabel(b, na), 'Self-test')
        return
    end
    if not backend:available() then
        sendState(a, 'selftest', 'ended', nb, 'voice_off')
        sendState(b, 'selftest', 'ended', na, 'voice_off')
        return
    end
    if name == PREFIX .. 'call_busy' then
        calls:hold(b)
        placeCall(a, b, na, nb)
        calls:release(b)
    else
        placeCall(a, b, na, nb)
    end
end

RegisterNetEvent('aeterna_phonecall:sv:selftest', function(data)
    local src = source
    if not AeternaCore.rateLimit(src, 'phonecall:selftest', 4, 1000) then return end
    local ok, err, p = AeternaCore.validate(data, SELFTEST_SCHEMA)
    if not ok then
        logWarn('aeterna_phonecall:sv:selftest invalid payload', { src = src, err = err })
        return
    end
    local okStatus, status = pcall(function() return exports.aeterna_core:runStatus(p.runId) end)
    if not okStatus or not T.inFlight(status, p.name) then return end
    local pair = selftestPairs:join(p.runId, p.name, p.role, src)
    if pair then selftestPair(p.name, pair.a, pair.b) end
end)

local function registerSelftests()
    local metas = T.metas(t, backend.kind)
    for _, row in ipairs(T.ROWS) do
        local name, meta = row.name, metas[row.name]
        local ok, res, err = pcall(function() return exports.aeterna_core:addSelftest(name, meta) end)
        if not ok or res == nil and err ~= nil then
            logWarn('phonecall self-test not registered', { name = name, err = tostring(err or res) })
        end
    end
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

if backend.kind == 'channels' and not backend:available() then
    logWarn('phonecall voice-channel natives are missing on this server; calls are off', {})
end
registerTiles()
registerSelftests()
for _, id in ipairs(GetPlayers()) do
    local src = tonumber(id)
    if src and session(src) then refreshBadge(src) end
end
