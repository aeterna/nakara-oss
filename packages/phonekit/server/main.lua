-- server/main.lua -- aeterna_phonekit server: app registry, app screen lifecycle,
-- badge tracking, opening check controller, and rate-limited net events.

local L = PhoneLogic

local registry = L.createAppRegistry({
    maxApps = (type(Config) == 'table' and tonumber(Config.maxApps)) or 24,
})

local badgeMgr = L.createBadgeManager()

local openingMgr = L.createOpeningCheckManager({
    setTimeout = type(SetTimeout) == 'function' and SetTimeout or nil,
    clearTimeout = type(ClearTimeout) == 'function' and ClearTimeout or nil,
})

local playerScreens = {}

local function getCurrentScreen(src)
    local stack = playerScreens[src]
    if stack and #stack > 0 then
        return stack[#stack]
    end
    return nil
end

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local function selfName()
    if type(GetCurrentResourceName) == 'function' then
        local n = GetCurrentResourceName()
        if type(n) == 'string' and n ~= '' then
            return n
        end
    end
    return 'aeterna_phonekit'
end

local function callerResource()
    if type(GetInvokingResource) == 'function' then
        local inv = GetInvokingResource()
        if type(inv) == 'string' and inv ~= '' then
            return inv
        end
    end
    return selfName()
end

local function canPlayerAccess(src, ace)
    if not ace or ace == '' then return true end
    if AeternaCore and type(AeternaCore.can) == 'function' then
        return AeternaCore.can(src, ace)
    end
    return false
end

--------------------------------------------------------------------------------
-- Server Exports
--------------------------------------------------------------------------------

exports('addTile', function(app)
    local owner = callerResource()
    local ok, err = registry:addTile(owner, app)
    if not ok then
        logWarn('addTile rejected tile', { owner = owner, err = err })
        return false, err
    end
    return true
end)

exports('removeTile', function(id)
    local owner = callerResource()
    return registry:removeTile(owner, id)
end)

exports('showApp', function(src, id, spec)
    local numSrc = tonumber(src)
    if not numSrc or numSrc < 0 then
        return nil, 'invalid_src'
    end

    local invoker = callerResource()
    local app = registry:find(invoker, id)
    if not app then
        logWarn('showApp rejected unknown app or unowned tile', { owner = invoker, id = id })
        return nil, 'unknown_app'
    end

    if not badgeMgr:isPhoneOpen(numSrc) then
        logWarn('showApp rejected phone closed', { src = numSrc, id = id })
        return nil, 'phone_closed'
    end

    if app.ace and not canPlayerAccess(numSrc, app.ace) then
        logWarn('showApp rejected ace denied', { src = numSrc, id = id, ace = app.ace })
        return nil, 'ace_denied'
    end

    local okVal, errVal, cleanSpec = L.validateSpec(spec)
    if not okVal then
        logWarn('showApp rejected invalid spec', { owner = invoker, id = id, err = errVal })
        return nil, errVal
    end

    local screenId = L.generateScreenId(numSrc)

    if not playerScreens[numSrc] then
        playerScreens[numSrc] = {}
    else
        local curr = getCurrentScreen(numSrc)
        if curr and (curr.id ~= id or curr.owner ~= invoker) then
            playerScreens[numSrc] = {}
        end
    end

    local stack = playerScreens[numSrc]
    if #stack >= 8 then
        table.remove(stack, 1)
    end

    stack[#stack + 1] = {
        screenId = screenId,
        id = id,
        owner = invoker,
        spec = cleanSpec,
    }

    badgeMgr:setCurrentApp(numSrc, id)

    TriggerClientEvent('aeterna_phonekit:cl:screen', numSrc, {
        screenId = screenId,
        id = id,
        title = cleanSpec.title,
        subtitle = cleanSpec.subtitle,
        blocks = cleanSpec.blocks,
    })

    return screenId
end)

exports('updateApp', function(src, screenId, patch)
    local numSrc = tonumber(src)
    if not numSrc then return false, 'invalid_src' end

    if not badgeMgr:isPhoneOpen(numSrc) then
        return false, 'phone_closed'
    end

    local invoker = callerResource()
    local current = getCurrentScreen(numSrc)
    if not current or current.screenId ~= screenId then
        return false, 'unknown_screen'
    end

    if current.owner ~= invoker then
        logWarn('updateApp rejected owner mismatch', { invoker = invoker, screenOwner = current.owner })
        return false, 'owner_mismatch'
    end

    local app = registry:find(current.owner, current.id)
    if not app then
        return false, 'unknown_app'
    end

    if app.ace and not canPlayerAccess(numSrc, app.ace) then
        return false, 'ace_denied'
    end

    local okPatch, errPatch, cleanPatch = L.validatePatch(current.spec, patch)
    if not okPatch then
        logWarn('updateApp rejected invalid patch', { screenId = screenId, err = errPatch })
        return false, errPatch
    end

    -- Apply patch in place to server copy
    if cleanPatch.blocks then
        for blockId, partial in pairs(cleanPatch.blocks) do
            for i = 1, #current.spec.blocks do
                local b = current.spec.blocks[i]
                if b.id == blockId then
                    for pk, pv in pairs(partial) do
                        b[pk] = pv
                    end
                    break
                end
            end
        end
    end

    TriggerClientEvent('aeterna_phonekit:cl:update', numSrc, {
        screenId = screenId,
        patch = cleanPatch,
    })

    return true
end)

exports('badge', function(src, id, count)
    local numSrc = tonumber(src)
    if not numSrc then return 0 end

    local owner = callerResource()
    local clamped = badgeMgr:setBadge(numSrc, owner, id, count)
    TriggerClientEvent('aeterna_phonekit:cl:badge', numSrc, {
        id = id,
        count = clamped,
    })
    return clamped
end)

exports('notifyApp', function(src, id, opts)
    local numSrc = tonumber(src)
    if not numSrc then return false end

    local owner = callerResource()
    local app = registry:find(owner, id) or registry:find(nil, id)
    local appOwner = app and app.owner or owner

    local cleanOpts = {
        title = (opts and opts.title) or (app and app.label) or 'Notification',
        body = (opts and opts.body) or '',
    }

    local newBadge = badgeMgr:notifyApp(
        numSrc,
        appOwner,
        id,
        cleanOpts,
        app,
        function(target, toastData)
            pcall(function()
                exports.aeterna_notify:notify(target, toastData)
            end)
        end,
        function(target, bannerData)
            TriggerClientEvent('aeterna_phonekit:cl:banner', target, bannerData)
        end
    )

    TriggerClientEvent('aeterna_phonekit:cl:badge', numSrc, {
        id = id,
        count = newBadge,
    })

    return true
end)

exports('listenOpen', function()
    return openingMgr:listenOpen()
end)

exports('allowOpen', function(checkId)
    return openingMgr:allowOpen(checkId)
end)

exports('denyOpen', function(checkId, reasonKey)
    return openingMgr:denyOpen(checkId, reasonKey)
end)

--------------------------------------------------------------------------------
-- Net Events (Server)
--------------------------------------------------------------------------------

RegisterNetEvent('aeterna_phonekit:sv:open', function()
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:open', 2, 1000) then
        logWarn('aeterna_phonekit:sv:open rate limited', { src = src })
        return
    end

    local isAsk = (type(Config) == 'table' and Config.ask == true)
    if not isAsk then
        badgeMgr:setPhoneOpen(src, true)
        local visibleApps = registry:getVisibleApps(src, canPlayerAccess)
        TriggerClientEvent('aeterna_phonekit:cl:open', src, { apps = visibleApps })
        return
    end

    local checkId = openingMgr:createCheck(src, function(targetSrc, allowed, reasonKey)
        if allowed then
            badgeMgr:setPhoneOpen(targetSrc, true)
            local visibleApps = registry:getVisibleApps(targetSrc, canPlayerAccess)
            TriggerClientEvent('aeterna_phonekit:cl:open', targetSrc, { apps = visibleApps })
        else
            TriggerClientEvent('aeterna_phonekit:cl:refused', targetSrc, {
                reason = reasonKey or 'phonekit.refused.default',
            })
        end
    end)

    TriggerEvent('aeterna_phonekit:asking', src, { checkId = checkId })
end)

RegisterNetEvent('aeterna_phonekit:sv:close', function()
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:close', 5, 1000) then
        logWarn('aeterna_phonekit:sv:close rate limited', { src = src })
        return
    end

    badgeMgr:setPhoneOpen(src, false)
    local current = getCurrentScreen(src)
    playerScreens[src] = nil
    badgeMgr:setCurrentApp(src, nil)

    if current then
        TriggerEvent('aeterna_phonekit:action', src, {
            owner = current.owner,
            id = current.id,
            screenId = current.screenId,
            action = '__close',
            values = {},
        })
    end
end)

RegisterNetEvent('aeterna_phonekit:sv:tap', function(data)
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:tap', 5, 1000) then
        logWarn('aeterna_phonekit:sv:tap rate limited', { src = src })
        return
    end

    if type(data) ~= 'table' or type(data.id) ~= 'string' or #data.id < 1 or #data.id > 32 then
        logWarn('aeterna_phonekit:sv:tap invalid payload', { src = src })
        return
    end
    if data.owner ~= nil and (type(data.owner) ~= 'string' or #data.owner > 64) then
        logWarn('aeterna_phonekit:sv:tap invalid owner', { src = src })
        return
    end

    local id = data.id
    local owner = type(data.owner) == 'string' and data.owner or nil
    local app = registry:find(owner, id) or registry:find(nil, id)

    if not app then
        logWarn('aeterna_phonekit:sv:tap unknown app', { src = src, id = id })
        return
    end

    if app.ace and not canPlayerAccess(src, app.ace) then
        logWarn('aeterna_phonekit:sv:tap ace denied', { src = src, id = id, ace = app.ace })
        return
    end

    badgeMgr:setCurrentApp(src, id)
    TriggerEvent('aeterna_phonekit:app', src, {
        owner = app.owner,
        id = app.id,
    })
end)

RegisterNetEvent('aeterna_phonekit:sv:action', function(data)
    local src = source
    if not AeternaCore.rateLimit(src, 'phonekit:action', 10, 1000) then
        logWarn('aeterna_phonekit:sv:action rate limited', { src = src })
        return
    end

    if type(data) ~= 'table' then
        logWarn('aeterna_phonekit:sv:action invalid payload', { src = src })
        return
    end

    if type(data.screenId) ~= 'string' or #data.screenId < 1 or #data.screenId > 24 then
        logWarn('aeterna_phonekit:sv:action invalid screenId', { src = src })
        return
    end

    if type(data.action) ~= 'string' or #data.action < 1 or #data.action > 32 then
        logWarn('aeterna_phonekit:sv:action invalid action', { src = src })
        return
    end

    if data.values ~= nil then
        if type(data.values) ~= 'table' then
            logWarn('aeterna_phonekit:sv:action invalid values', { src = src })
            return
        end
        local count = 0
        for _ in pairs(data.values) do
            count = count + 1
            if count > 40 then
                logWarn('aeterna_phonekit:sv:action too many values keys', { src = src })
                return
            end
        end
    end

    local current = getCurrentScreen(src)
    if not current or current.screenId ~= data.screenId then
        logWarn('aeterna_phonekit:sv:action screen mismatch or closed', { src = src, screenId = data.screenId })
        return
    end

    if data.action == '__close' then
        local appOwner = current.owner
        local appId = current.id
        local sId = current.screenId
        playerScreens[src] = nil
        badgeMgr:setCurrentApp(src, nil)

        TriggerEvent('aeterna_phonekit:action', src, {
            owner = appOwner,
            id = appId,
            screenId = sId,
            action = '__close',
            values = {},
        })
        return
    end

    if data.action == '__back' then
        local stack = playerScreens[src]
        if stack and #stack > 1 then
            table.remove(stack)
            local prev = stack[#stack]
            badgeMgr:setCurrentApp(src, prev.id)
            TriggerClientEvent('aeterna_phonekit:cl:screen', src, {
                screenId = prev.screenId,
                id = prev.id,
                title = prev.spec.title,
                subtitle = prev.spec.subtitle,
                blocks = prev.spec.blocks,
            })
        else
            local last = stack and table.remove(stack) or current
            playerScreens[src] = nil
            badgeMgr:setCurrentApp(src, nil)
            TriggerEvent('aeterna_phonekit:action', src, {
                owner = last.owner,
                id = last.id,
                screenId = last.screenId,
                action = '__close',
                values = {},
            })
        end
        return
    end

    local okVal, errVal, clean = L.validateAction(current, data)
    if not okVal then
        logWarn('aeterna_phonekit:sv:action validation failed', { src = src, err = errVal })
        return
    end

    TriggerEvent('aeterna_phonekit:action', src, clean)
end)

--------------------------------------------------------------------------------
-- Resource Cleanup & Player Disconnect
--------------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resName)
    if resName ~= selfName() then
        registry:removeOwner(resName)
        badgeMgr:removeOwner(resName)
        for src, stack in pairs(playerScreens) do
            local current = getCurrentScreen(src)
            if current and current.owner == resName then
                playerScreens[src] = nil
                badgeMgr:setCurrentApp(src, nil)
            end
        end
        for srcStr, p in pairs(badgeMgr.players) do
            local numSrc = tonumber(srcStr)
            if numSrc and p.phoneOpen then
                local visibleApps = registry:getVisibleApps(numSrc, canPlayerAccess)
                TriggerClientEvent('aeterna_phonekit:cl:open', numSrc, { apps = visibleApps })
            end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    if src then
        playerScreens[src] = nil
        badgeMgr:removePlayer(src)
    end
end)
