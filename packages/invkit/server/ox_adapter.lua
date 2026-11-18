-- Isolated adapter for optional external resources (ox_inventory and qbx_core).
-- Every ox_inventory export listed in docs/specs/aeterna_invkit.md lives here so signatures
-- stay in one module and are called only when GetResourceState reports 'started'.

InvkitOxAdapter = {}
local A = InvkitOxAdapter

local warnedNoOx = false
local currentHookId = nil

local function translate(key)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key)
    end
    if Locales and Locales.en and Locales.en[key] then
        return Locales.en[key]
    end
    return key
end

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

function A.isOxStarted()
    return type(GetResourceState) == 'function' and GetResourceState('ox_inventory') == 'started'
end

function A.isQbxStarted()
    return type(GetResourceState) == 'function' and GetResourceState('qbx_core') == 'started'
end

function A.ensureOxStarted()
    if A.isOxStarted() then
        return true
    end
    if not warnedNoOx then
        warnedNoOx = true
        logWarn(translate('invkit.noox'))
    end
    return false
end

function A.resetWarnState()
    warnedNoOx = false
    currentHookId = nil
end

function A.getPlayerIdentifiers(src)
    local citizenid = nil
    local license = nil
    local qbxStarted = A.isQbxStarted()

    if qbxStarted then
        local ok, player = pcall(function()
            return exports.qbx_core:GetPlayer(src)
        end)
        if ok and type(player) == 'table' then
            local pdata = player.PlayerData
            if type(pdata) == 'table' then
                if type(pdata.citizenid) == 'string' and pdata.citizenid ~= '' then
                    citizenid = pdata.citizenid
                end
                if type(pdata.license) == 'string' and pdata.license ~= '' then
                    license = pdata.license
                end
            elseif type(player.citizenid) == 'string' and player.citizenid ~= '' then
                citizenid = player.citizenid
            end
        end
    end

    if not license and type(GetPlayerIdentifierByType) == 'function' then
        local ok, id = pcall(GetPlayerIdentifierByType, src, 'license')
        if ok and type(id) == 'string' and id ~= '' then
            license = id
        end
    end

    if not license and type(GetPlayerIdentifiers) == 'function' then
        local ok, list = pcall(GetPlayerIdentifiers, src)
        if ok and type(list) == 'table' then
            license = InvkitLogic.extractLicense(list)
        end
    end

    return {
        qbxStarted = qbxStarted,
        citizenid = citizenid,
        license = license,
    }
end

function A.registerStash(id, label, slots, maxWeight, owner)
    if not A.ensureOxStarted() then
        return false
    end
    local ok, err = pcall(function()
        exports.ox_inventory:RegisterStash(id, label, slots, maxWeight, owner)
    end)
    if not ok then
        logWarn('ox_inventory:RegisterStash failed', { id = tostring(id), err = tostring(err) })
        return false
    end
    return true
end

function A.forceOpenStash(src, id)
    if not A.ensureOxStarted() then
        return false
    end
    local ok, res = pcall(function()
        return exports.ox_inventory:forceOpenInventory(src, 'stash', id)
    end)
    if not ok or res == false then
        logWarn('ox_inventory:forceOpenInventory failed', { src = tostring(src), id = tostring(id) })
        return false
    end
    return true
end

function A.parseUsingItemPayload(payload, arg2, arg3)
    if type(payload) == 'table' then
        local src = tonumber(payload.source or payload.src)
        local itemField = payload.item
        local itemName = nil
        local slot = payload.slot or payload.fromSlot
        if type(itemField) == 'table' then
            itemName = itemField.name
            if slot == nil then
                slot = itemField.slot
            end
        elseif type(itemField) == 'string' then
            itemName = itemField
        elseif type(payload.name) == 'string' then
            itemName = payload.name
        end
        return src, itemName, tonumber(slot) or slot
    elseif type(payload) == 'number' then
        local itemName = type(arg2) == 'table' and arg2.name or arg2
        local slot = arg3 or (type(arg2) == 'table' and arg2.slot or nil)
        return payload, itemName, tonumber(slot) or slot
    end
    return nil, nil, nil
end

function A.syncUsingItemHook(onUsingItemFn, itemFilter, filterCount)
    if not A.isOxStarted() then
        return false
    end
    if currentHookId ~= nil then
        pcall(function()
            exports.ox_inventory:removeHooks(currentHookId)
        end)
        currentHookId = nil
    end
    if type(filterCount) == 'number' and filterCount <= 0 then
        return true
    end
    local ok, hookId = pcall(function()
        return exports.ox_inventory:registerHook('usingItem', function(payload, a2, a3)
            local src, itemName, slot = A.parseUsingItemPayload(payload, a2, a3)
            if not src or type(itemName) ~= 'string' then
                return
            end
            return onUsingItemFn(src, itemName, slot)
        end, { itemFilter = itemFilter })
    end)
    if not ok then
        logWarn('ox_inventory:registerHook failed', { err = tostring(hookId) })
        return false
    end
    currentHookId = hookId
    return true
end

function A.consumeItem(src, item, count, slot)
    if not A.ensureOxStarted() then
        return false
    end
    local okCount, currentCount = pcall(function()
        return exports.ox_inventory:GetItemCount(src, item)
    end)
    if not okCount or type(currentCount) ~= 'number' or currentCount < count then
        return false
    end
    local okRemove, removed = pcall(function()
        return exports.ox_inventory:RemoveItem(src, item, count, nil, slot)
    end)
    if not okRemove or removed == false then
        return false
    end
    return true
end

return A
