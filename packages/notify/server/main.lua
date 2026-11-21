-- aeterna_notify server: single-player toast export (0.2: action presses), queued server-wide announcements,
-- countdown announcements, and the ACE-checked commands.

local L = NotifyLogic

local announceQueue = nil
local activeTimer = nil
local toastSeq = 0
local actionTracker = L.createActionTracker({ max = L.ACTION_TOAST_MAX, graceMs = L.ACTION_GRACE_MS })
local countdown = nil

local function selfName()
    local n = GetCurrentResourceName()
    if type(n) == 'string' and n ~= '' then
        return n
    end
    return 'aeterna_notify'
end

local function callerName()
    local n = GetInvokingResource()
    if type(n) == 'string' and n ~= '' then
        return n
    end
    return selfName()
end

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local function logInfo(msg)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.info) == 'function' then
        AeternaCore.log.info(msg)
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

local function checkAce(src, ace)
    if AeternaCore and type(AeternaCore.can) == 'function' then
        return AeternaCore.can(src, ace)
    end
    if tonumber(src) == 0 then
        return true
    end
    if type(IsPlayerAceAllowed) == 'function' then
        return IsPlayerAceAllowed(src, ace) == true
    end
    return false
end

local function getPlayerNameSafe(s)
    if type(GetPlayerName) == 'function' then
        return GetPlayerName(s)
    end
    return nil
end

local function getAnnounceQueue()
    if announceQueue then
        return announceQueue
    end
    local maxWaiting = 5
    if type(Config) == 'table' and type(Config.announce) == 'table' and tonumber(Config.announce.queue) then
        maxWaiting = math.max(0, math.floor(tonumber(Config.announce.queue)))
    end

    local function scheduleNext(durationMs)
        if type(SetTimeout) ~= 'function' then
            return
        end
        if activeTimer and type(ClearTimeout) == 'function' then
            ClearTimeout(activeTimer)
        end
        activeTimer = SetTimeout(durationMs, function()
            activeTimer = nil
            if announceQueue then
                announceQueue:next()
            end
        end)
    end

    announceQueue = L.createAnnounceQueue({
        max = maxWaiting,
        warn = logWarn,
        onShow = function(item)
            TriggerClientEvent('aeterna_notify:cl:announce', -1, item)
            scheduleNext(item.duration)
        end,
    })
    return announceQueue
end

local function sendToastToPlayer(src, opts, owner)
    local target = tonumber(src)
    if not target or target <= 0 then
        logWarn('notify refused invalid target player', { src = tostring(src) })
        return false, 'src: invalid'
    end
    local toastCfg = type(Config) == 'table' and Config.toast or nil
    local ok, err, clean = L.validateToastOpts(opts, toastCfg, logWarn)
    if not ok then
        logWarn('notify invalid opts', { src = target, err = err })
        return false, err
    end
    if clean.id then
        clean.toastId = clean.id
    else
        toastSeq = toastSeq + 1
        clean.toastId = 's' .. L.base36(toastSeq)
    end
    clean.owner = owner or selfName()
    if clean.id and not clean.actions then
        actionTracker:untrack(target, clean.owner, clean.toastId)
    end
    if clean.actions then
        actionTracker:track(target, {
            toastId = clean.toastId,
            actions = clean.actions,
            duration = clean.duration,
            owner = clean.owner,
        }, GetGameTimer())
    end
    TriggerClientEvent('aeterna_notify:cl:toast', target, clean)
    return true, nil, clean
end

local function sendAnnouncement(opts)
    local aq = getAnnounceQueue()
    return aq:push(opts)
end

local function getCountdown()
    if countdown then
        return countdown
    end
    countdown = L.createCountdown({
        send = function(payload)
            TriggerClientEvent('aeterna_notify:cl:countdown', -1, payload)
        end,
        fire = function(payload)
            TriggerEvent('aeterna_notify:countdownEnd', payload)
        end,
    })
    return countdown
end

local function startCountdown(opts, owner)
    local cd = getCountdown()
    local id, err = cd:start(opts, GetGameTimer(), owner or selfName())
    if not id then
        if err ~= 'busy' then
            logWarn('announceCountdown invalid opts', { err = err })
        end
        return nil, err
    end
    CreateThread(function()
        while cd:active() == id do
            Wait(250)
            cd:tick(GetGameTimer())
        end
    end)
    return id
end

exports('notify', function(src, opts)
    return sendToastToPlayer(src, opts, callerName())
end)

exports('announce', function(opts)
    return sendAnnouncement(opts)
end)

exports('announceCountdown', function(opts)
    return startCountdown(opts, callerName())
end)

-- Only the resource that started the countdown may cancel it.
exports('cancelCountdown', function(countdownId)
    return getCountdown():cancel(countdownId, callerName())
end)

RegisterNetEvent('aeterna_notify:sv:action', function(payload)
    local src = source
    if not AeternaCore.rateLimit(src, 'aeterna_notify:sv:action', 5, 1000) then
        return
    end
    local ok, err, press = L.validateActionPress(payload)
    if not ok then
        logWarn('aeterna_notify:sv:action dropped', { src = tostring(src), err = err })
        return
    end
    local accepted, rec = actionTracker:press(src, press.toastId, press.action, GetGameTimer())
    if not accepted then
        return
    end
    TriggerEvent('aeterna_notify:action', src, rec)
end)

AddEventHandler('playerDropped', function()
    actionTracker:drop(source)
end)

-- A countdown ends as cancelled when its owner resource stops, or when notify itself stops.
AddEventHandler('onResourceStop', function(resName)
    if not countdown then return end
    if resName == selfName() then
        local id = countdown:active()
        if id then
            countdown:cancel(id)
        end
        return
    end
    countdown:cancelOwnedBy(resName)
end)

RegisterCommand('aeterna_announce', function(src, args, rawCommand)
    local rawText = L.extractCommandText(args, rawCommand, 'aeterna_announce')
    local ok, errKey, msgOrRes = L.handleAnnounceCommand(src, rawText, {
        can = checkAce,
        t = translate,
        getPlayerName = getPlayerNameSafe,
        notify = function(targetSrc, toastOpts)
            sendToastToPlayer(targetSrc, toastOpts)
        end,
        announce = function(annOpts)
            return sendAnnouncement(annOpts)
        end,
    })
    if not ok and (tonumber(src) or 0) == 0 then
        logInfo(tostring(msgOrRes))
    end
    return ok, errKey, msgOrRes
end, false)

RegisterCommand('aeterna_announce_countdown', function(src, args, rawCommand)
    local rawText = L.extractCommandText(args, rawCommand, 'aeterna_announce_countdown')
    local ok, errKey, msgOrRes = L.handleCountdownCommand(src, rawText, {
        can = checkAce,
        t = translate,
        getPlayerName = getPlayerNameSafe,
        notify = function(targetSrc, toastOpts)
            sendToastToPlayer(targetSrc, toastOpts)
        end,
        start = function(cdOpts)
            return startCountdown(cdOpts, selfName())
        end,
    })
    if not ok and (tonumber(src) or 0) == 0 then
        logInfo(tostring(msgOrRes))
    end
    return ok, errKey, msgOrRes
end, false)

-- Self-tests (0.2): register every row with aeterna_core and answer the server-side headless ones.
local Selftests = NotifySelftests

pcall(function()
    Selftests.register(function(name, meta)
        return exports.aeterna_core:addSelftest(name, meta)
    end, translate)
end)

AddEventHandler('aeterna_core:selftest', function(runId, name)
    local short = Selftests.shortName(name)
    if not short then return end
    local ok, detail = Selftests.run(short, L)
    if ok == nil then return end
    exports.aeterna_core:reportSelftest(runId, name, ok, detail)
end)
