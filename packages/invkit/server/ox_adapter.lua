-- Isolated adapter for optional external resources (ox_inventory and qbx_core).
-- Every ox_inventory export listed in docs/specs/aeterna_invkit.md lives here so signatures
-- stay in one module and are called only when GetResourceState reports 'started'.

InvkitOxAdapter = {}
local A = InvkitOxAdapter

local warnedNoOx = false
local currentHookId = nil
local phoneHookIds = {}

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

function A.clearHookState()
    currentHookId = nil
    phoneHookIds = {}
end

function A.resetWarnState()
    warnedNoOx = false
    A.clearHookState()
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
    if not ok or not res then
        logWarn('ox_inventory:forceOpenInventory failed', { src = tostring(src), id = tostring(id) })
        return false
    end
    return true
end

function A.parseUsingItemPayload(payload)
    if type(payload) ~= 'table' then
        return nil, nil, nil
    end
    local src = tonumber(payload.source)
    local itemField = payload.item
    if type(itemField) ~= 'table' then
        return src, nil, nil
    end
    return src, itemField.name, tonumber(itemField.slot)
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
        return exports.ox_inventory:registerHook('usingItem', function(payload)
            local src, itemName, slot = A.parseUsingItemPayload(payload)
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

-- Phone item mode (0.2). Calls verified against ox_inventory v2.44.0 server exports.

--- Every slot of the player holding one of `names`, or nil when ox_inventory is not started or the call
--- fails. Search(src, 'slots', names) returns the slot list itself for one name, a name -> list map for more.
function A.searchSlots(src, names)
    if not A.isOxStarted() or type(names) ~= 'table' or #names == 0 then
        return nil
    end
    local ok, result = pcall(function()
        return exports.ox_inventory:Search(src, 'slots', names)
    end)
    if not ok then
        logWarn('ox_inventory:Search failed', { src = tostring(src), err = tostring(result) })
        return nil
    end
    return result
end

--- Replaces the metadata of one slot (SetMetadata replaces the whole table; callers pass a merged copy).
function A.setMetadata(src, slot, metadata)
    if not A.isOxStarted() then
        return false
    end
    local ok, err = pcall(function()
        exports.ox_inventory:SetMetadata(src, slot, metadata)
    end)
    if not ok then
        logWarn('ox_inventory:SetMetadata failed', { src = tostring(src), slot = tostring(slot), err = tostring(err) })
        return false
    end
    return true
end

--- Self-test only (phone_device_save): gives one item with `metadata`. true when ox_inventory added it.
function A.addItem(src, item, count, metadata)
    if not A.isOxStarted() then
        return false
    end
    local ok, added = pcall(function()
        return exports.ox_inventory:AddItem(src, item, count, metadata)
    end)
    if not ok or not added then
        logWarn('ox_inventory:AddItem failed', { src = tostring(src), item = tostring(item) })
        return false
    end
    return true
end

--- Self-test only (phone_device_save): removes `count` of `item` from that one slot.
function A.removeItem(src, item, count, slot)
    if not A.isOxStarted() then
        return false
    end
    local ok, removed = pcall(function()
        return exports.ox_inventory:RemoveItem(src, item, count, nil, slot)
    end)
    return ok and removed ~= false
end

--- (Re)registers the swapItems and createItem hooks for the phone items. `handlers` maps the hook event
--- name to fn(payload); `itemFilter` is { [name] = true }. An empty filter only removes the old hooks.
function A.syncPhoneHooks(handlers, itemFilter)
    if not A.isOxStarted() then
        return false
    end
    for _, id in pairs(phoneHookIds) do
        pcall(function()
            exports.ox_inventory:removeHooks(id)
        end)
    end
    phoneHookIds = {}
    if type(itemFilter) ~= 'table' or next(itemFilter) == nil then
        return true
    end
    local allOk = true
    for _, event in ipairs({ 'swapItems', 'createItem' }) do
        local fn = handlers[event]
        local ok, hookId = pcall(function()
            return exports.ox_inventory:registerHook(event, function(payload)
                fn(payload)
            end, { itemFilter = itemFilter })
        end)
        if ok then
            phoneHookIds[event] = hookId
        else
            allOk = false
            logWarn('ox_inventory:registerHook failed', { event = event, err = tostring(hookId) })
        end
    end
    return allOk
end

return A
