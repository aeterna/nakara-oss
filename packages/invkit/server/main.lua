-- aeterna_invkit server: personal stash registration/opening, item-use registry,
-- ox_inventory hook integration and rate-limited net events.

local L = InvkitLogic
local A = InvkitOxAdapter

local registeredStashes = {}

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

local function callerResource()
    local inv = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    if inv and inv ~= '' then
        return inv
    end
    if type(GetCurrentResourceName) == 'function' then
        return GetCurrentResourceName()
    end
    return 'aeterna_invkit'
end

local function optionalCallerOwner()
    local inv = type(GetInvokingResource) == 'function' and GetInvokingResource() or nil
    if inv and inv ~= '' then
        return inv
    end
    return nil
end

local useManager
useManager = L.createUseManager({
    now = function()
        if type(GetGameTimer) == 'function' then
            return GetGameTimer()
        end
        return 0
    end,
    onAsk = function(src, payload)
        TriggerEvent('aeterna_invkit:asking', src, payload)
        if type(SetTimeout) == 'function' then
            SetTimeout(L.ASK_TIMEOUT_MS, function()
                useManager:expireAsk(payload.useId)
            end)
        end
    end,
    onStartClient = function(src, payload)
        TriggerClientEvent('aeterna_invkit:cl:use', src, payload)
    end,
    onRefused = function(src, payload)
        TriggerClientEvent('aeterna_invkit:cl:refused', src, payload)
    end,
    onUsed = function(src, payload)
        TriggerEvent('aeterna_invkit:used', src, payload)
    end,
    consumeItem = function(src, item, count, slot)
        return A.consumeItem(src, item, count, slot)
    end,
})

local function onOxUsingItem(src, itemName, slot)
    if not useManager:getUsable(itemName) then
        return
    end
    useManager:startUse(src, itemName, slot)
    return false
end

local function syncOxHook()
    if not A.isOxStarted() then
        return false
    end
    local filter, count = useManager:itemFilter()
    return A.syncUsingItemHook(onOxUsingItem, filter, count)
end

local function resolvePlayerStashId(src, scopeOverride)
    local target = tonumber(src)
    if not target or target <= 0 then
        return nil, 'src: invalid'
    end
    local stashCfg = (Config and type(Config.stash) == 'table') and Config.stash or {}
    local scope = scopeOverride or stashCfg.scope or 'character'
    local info = A.getPlayerIdentifiers(target)
    return L.stashId(scope, info)
end

local function openStashInternal(src, scopeOverride)
    if not A.ensureOxStarted() then
        return false, 'ox_inventory: not started'
    end
    local id, err = resolvePlayerStashId(src, scopeOverride)
    if not id then
        logWarn('stashId failed', { src = tostring(src), err = tostring(err) })
        return false, err
    end
    local stashCfg = (Config and type(Config.stash) == 'table') and Config.stash or {}
    if not registeredStashes[id] then
        local rawLabel = stashCfg.label
        local label = (type(rawLabel) == 'string' and rawLabel ~= '') and translate(rawLabel) or translate('invkit.stash.label')
        local slots = tonumber(stashCfg.slots) or 40
        local maxWeight = tonumber(stashCfg.maxWeight) or 100000
        if not A.registerStash(id, label, slots, maxWeight, nil) then
            return false, 'registerStash: failed'
        end
        registeredStashes[id] = true
    end
    if not A.forceOpenStash(tonumber(src), id) then
        return false, 'forceOpenInventory: failed'
    end
    return true, id
end

local function getServerPlayerCoords(src)
    if type(GetEntityCoords) ~= 'function' then
        return nil
    end
    local ped = src
    if type(GetPlayerPed) == 'function' then
        local p = GetPlayerPed(src)
        if p and p ~= 0 then
            ped = p
        end
    end
    return GetEntityCoords(ped)
end

local function handleOpenStashRequest(src)
    if not A.ensureOxStarted() then
        return false
    end
    local stashCfg = (Config and type(Config.stash) == 'table') and Config.stash or {}
    local coords = getServerPlayerCoords(src)
    local okDist, reasonKey = L.canOpenAt(coords, stashCfg)
    if not okDist then
        TriggerClientEvent('aeterna_invkit:cl:refused', src, {
            item = 'stash',
            reason = reasonKey or 'invkit.stash.far',
        })
        return false
    end
    return openStashInternal(src, stashCfg.scope)
end

-- Check ox_inventory state once at startup
A.ensureOxStarted()

-- Server Exports
exports('stashId', function(src, scope)
    return resolvePlayerStashId(src, scope)
end)

exports('openStash', function(src, opts)
    local scopeOverride = type(opts) == 'table' and opts.scope or nil
    local ok = openStashInternal(src, scopeOverride)
    return ok == true
end)

exports('registerUsable', function(item, def)
    local owner = callerResource()
    local ok, err = useManager:registerUsable(owner, item, def)
    if not ok then
        logWarn('registerUsable refused', { owner = owner, item = tostring(item), err = tostring(err) })
        return false, err
    end
    if A.ensureOxStarted() then
        syncOxHook()
    end
    return true
end)

exports('unregisterUsable', function(item)
    local owner = optionalCallerOwner()
    local ok = useManager:unregisterUsable(item, owner)
    if ok and A.isOxStarted() then
        syncOxHook()
    end
    return ok
end)

exports('allowUse', function(useId)
    local owner = optionalCallerOwner()
    local ok = useManager:allowUse(useId, owner)
    return ok == true
end)

exports('denyUse', function(useId, reasonKey)
    local owner = optionalCallerOwner()
    local ok = useManager:denyUse(useId, reasonKey, owner)
    return ok == true
end)

-- Commands (literal name required by fivem-devkit safety)
RegisterCommand('aeterna_stash', function(src)
    local playerSrc = tonumber(src)
    if not playerSrc or playerSrc <= 0 then return end
    if not (Config and Config.stash and Config.stash.command == true) then
        return
    end
    handleOpenStashRequest(playerSrc)
end, false)

-- Client -> Server Net Events
RegisterNetEvent('aeterna_invkit:sv:open', function()
    local src = tonumber(source)
    if not src or src <= 0 then return end
    if AeternaCore and AeternaCore.rateLimit then
        if not AeternaCore.rateLimit(src, 'aeterna_invkit:sv:open', 2, 1000) then
            return
        end
    end
    handleOpenStashRequest(src)
end)

RegisterNetEvent('aeterna_invkit:sv:done', function(payload)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    if AeternaCore and AeternaCore.rateLimit then
        if not AeternaCore.rateLimit(src, 'aeterna_invkit:sv:done', 4, 1000) then
            return
        end
    end
    local ok, err, clean = L.validateUseIdPayload(payload)
    if not ok then
        logWarn('aeterna_invkit:sv:done dropped', { src = src, err = err })
        return
    end
    useManager:done(src, clean.useId)
end)

RegisterNetEvent('aeterna_invkit:sv:cancel', function(payload)
    local src = tonumber(source)
    if not src or src <= 0 then return end
    if AeternaCore and AeternaCore.rateLimit then
        if not AeternaCore.rateLimit(src, 'aeterna_invkit:sv:cancel', 4, 1000) then
            return
        end
    end
    local ok, err, clean = L.validateUseIdPayload(payload)
    if not ok then
        logWarn('aeterna_invkit:sv:cancel dropped', { src = src, err = err })
        return
    end
    useManager:cancel(src, clean.useId)
end)

AddEventHandler('onResourceStop', function(resName)
    if type(resName) ~= 'string' then return end
    if type(GetCurrentResourceName) == 'function' and resName == GetCurrentResourceName() then
        return
    end
    local removed = useManager:removeByOwner(resName)
    if removed > 0 and A.isOxStarted() then
        syncOxHook()
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if src then
        useManager:removePlayer(src)
    end
end)
