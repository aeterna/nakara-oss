-- aeterna_uikit server: panels, action validation, menu registry and rate-limited net events.

local L = UikitLogic
local panels = L.createPanelManager()
local menus = L.createMenuManager()

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local function translate(key)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key)
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
    if type(IsPlayerAceAllowed) == 'function' then
        return IsPlayerAceAllowed(src, ace) == true
    end
    return false
end

local function callerResource()
    local inv = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    if inv and inv ~= '' then
        return inv
    end
    if type(GetCurrentResourceName) == 'function' then
        return GetCurrentResourceName()
    end
    return 'aeterna_uikit'
end

local function openMenuForPlayer(src)
    local target = tonumber(src)
    if not target or target <= 0 then return false end
    local ok, closed = panels:close(target, nil, 'closed')
    if ok and closed then
        TriggerClientEvent('aeterna_uikit:cl:close', target, {
            panelId = closed.panelId,
            reason = 'closed',
        })
        TriggerEvent('aeterna_uikit:action', target, {
            owner = closed.owner,
            panelId = closed.panelId,
            action = '__close',
            values = {},
        })
    end
    local rawTitle = GetConvar('aeterna_uikit_menu_title', '')
    local title
    if type(rawTitle) == 'string' and L.stripControlAndTrim(rawTitle) ~= '' then
        title = L.textClean(rawTitle, 60)
    else
        title = translate('uikit.menu.title')
    end
    local entries = menus:listForPlayer(target, checkAce)
    TriggerClientEvent('aeterna_uikit:cl:open', target, {
        panelId = '__menu',
        kind = 'menu',
        title = title,
        size = 'sm',
        entries = entries,
    })
    return true
end

exports('open', function(src, spec)
    local target = tonumber(src)
    if not target or target <= 0 then
        return nil, 'src: invalid'
    end
    local owner = callerResource()
    local panelId, err, replaced = panels:open(target, owner, spec)
    if not panelId then
        logWarn('open failed', { owner = owner, err = err })
        return nil, err
    end
    if replaced then
        TriggerClientEvent('aeterna_uikit:cl:close', target, {
            panelId = replaced.panelId,
            reason = 'replaced',
        })
        TriggerEvent('aeterna_uikit:action', target, {
            owner = replaced.owner,
            panelId = replaced.panelId,
            action = '__close',
            values = {},
        })
    end
    local cur = panels:getOpen(target)
    TriggerClientEvent('aeterna_uikit:cl:open', target, {
        panelId = panelId,
        title = cur.spec.title,
        subtitle = cur.spec.subtitle,
        size = cur.spec.size,
        blocks = cur.spec.blocks,
    })
    return panelId
end)

exports('update', function(src, panelId, patch)
    local target = tonumber(src)
    if not target or target <= 0 then
        return false
    end
    local ok, err, cleanPatch = panels:update(target, panelId, patch)
    if not ok then
        logWarn('update refused', { panelId = tostring(panelId), err = err })
        return false
    end
    TriggerClientEvent('aeterna_uikit:cl:update', target, {
        panelId = panelId,
        patch = cleanPatch,
    })
    return true
end)

exports('close', function(src, panelId)
    local target = tonumber(src)
    if not target or target <= 0 then
        return false
    end
    local ok, closed = panels:close(target, panelId, 'closed')
    if not ok then
        return false
    end
    TriggerClientEvent('aeterna_uikit:cl:close', target, {
        panelId = closed.panelId,
        reason = 'closed',
    })
    return true
end)

exports('isOpen', function(src)
    return panels:isOpen(src)
end)

exports('addMenuEntry', function(entry)
    local owner = callerResource()
    local ok, err = menus:add(owner, entry)
    if not ok then
        logWarn('addMenuEntry refused', { owner = owner, err = err })
        return false, err
    end
    return true
end)

exports('removeMenuEntry', function(id)
    local owner = callerResource()
    return menus:remove(owner, id)
end)

exports('showMenu', function(src)
    return openMenuForPlayer(src)
end)

RegisterNetEvent('aeterna_uikit:sv:action', function(payload)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    if AeternaCore and AeternaCore.rateLimit then
        if not AeternaCore.rateLimit(src, 'aeterna_uikit:sv:action', 10, 1000) then
            return
        end
    end
    local ok, err, result = panels:handleAction(src, payload)
    if not ok then
        logWarn('aeterna_uikit:sv:action dropped', { src = src, err = err })
        return
    end
    TriggerEvent('aeterna_uikit:action', src, result)
end)

RegisterNetEvent('aeterna_uikit:sv:menu', function(payload)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    if AeternaCore and AeternaCore.rateLimit then
        if not AeternaCore.rateLimit(src, 'aeterna_uikit:sv:menu', 5, 1000) then
            return
        end
    end
    if type(payload) ~= 'table' then
        logWarn('aeterna_uikit:sv:menu dropped', { src = src, err = 'payload: type' })
        return
    end
    local ok, err, picked = menus:pick(src, payload.owner, payload.id, checkAce)
    if not ok then
        logWarn('aeterna_uikit:sv:menu dropped', { src = src, err = err })
        return
    end
    TriggerEvent('aeterna_uikit:menu', src, picked)
end)

RegisterNetEvent('aeterna_uikit:sv:showMenu', function()
    local src = tonumber(source)
    if not src or src <= 0 then return end
    if AeternaCore and AeternaCore.rateLimit then
        if not AeternaCore.rateLimit(src, 'aeterna_uikit:sv:showMenu', 2, 1000) then
            return
        end
    end
    openMenuForPlayer(src)
end)

AddEventHandler('onResourceStop', function(resName)
    if type(resName) ~= 'string' then return end
    if type(GetCurrentResourceName) == 'function' and resName == GetCurrentResourceName() then
        return
    end
    menus:removeByOwner(resName)
    local closed = panels:removeByOwner(resName)
    for i = 1, #closed do
        local p = closed[i]
        TriggerClientEvent('aeterna_uikit:cl:close', p.src, {
            panelId = p.panelId,
            reason = 'owner_stopped',
        })
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then
        panels:removePlayer(src)
    end
end)

-- Self-tests (0.2): register every row with aeterna_core and answer the server-side headless ones.
local Selftests = UikitSelftests

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
