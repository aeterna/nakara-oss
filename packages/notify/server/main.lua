-- aeterna_notify server: single-player toast export, queued server-wide announcements, and ACE-checked command.

local L = NotifyLogic

local announceQueue = nil
local activeTimer = nil

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

local function sendToastToPlayer(src, opts)
    local target = tonumber(src)
    if not target or target <= 0 then
        logWarn('notify refused invalid target player', { src = tostring(src) })
        return false, 'src: invalid'
    end
    local toastCfg = type(Config) == 'table' and Config.toast or nil
    local ok, err, clean = L.validateToastOpts(opts, toastCfg)
    if not ok then
        logWarn('notify invalid opts', { src = target, err = err })
        return false, err
    end
    TriggerClientEvent('aeterna_notify:cl:toast', target, clean)
    return true, nil, clean
end

local function sendAnnouncement(opts)
    local aq = getAnnounceQueue()
    return aq:push(opts)
end

exports('notify', function(src, opts)
    return sendToastToPlayer(src, opts)
end)

exports('announce', function(opts)
    return sendAnnouncement(opts)
end)

RegisterCommand('aeterna_announce', function(src, args, rawCommand)
    local rawText = L.extractCommandText(args, rawCommand, 'aeterna_announce')
    local ok, errKey, msgOrRes = L.handleAnnounceCommand(src, rawText, {
        can = checkAce,
        t = translate,
        getPlayerName = function(s)
            if type(GetPlayerName) == 'function' then
                return GetPlayerName(s)
            end
            return nil
        end,
        notify = function(targetSrc, toastOpts)
            sendToastToPlayer(targetSrc, toastOpts)
        end,
        announce = function(annOpts)
            return sendAnnouncement(annOpts)
        end,
    })
    if not ok and (tonumber(src) or 0) == 0 and AeternaCore and AeternaCore.log and type(AeternaCore.log.info) == 'function' then
        AeternaCore.log.info(tostring(msgOrRes))
    end
    return ok, errKey, msgOrRes
end, false)
