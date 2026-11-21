-- aeterna_invkit server: phone item mode (0.2). Answers aeterna_phonekit's open gate with the phone items a
-- player carries and writes battery/fold back into item metadata. Server-local events only: phonekit is
-- optional, never a dependency, and never called through exports (docs/specs/aeterna_invkit.md § 0.2).

local P = InvkitPhoneLogic
local A = InvkitOxAdapter

local phoneCfg = (Config and type(Config.phone) == 'table') and Config.phone or {}
local enabled = phoneCfg.enabled == true

local function logWarn(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.warn) == 'function' then
        AeternaCore.log.warn(msg, fields)
    end
end

local phoneMap, skipped = P.validateItemMap(phoneCfg.items)
local phoneNames = P.itemNames(phoneMap)

if enabled and #skipped > 0 then
    local names = {}
    for i, entry in ipairs(skipped) do
        names[i] = ('%s (%s)'):format(entry.name, entry.reason)
    end
    logWarn('Config.phone.items entries skipped', { count = #skipped, entries = table.concat(names, ', ') })
end

local function now()
    return type(GetGameTimer) == 'function' and GetGameTimer() or 0
end

local saveQueue = P.createSaveQueue({ now = now })
local changedPending = {}
-- src -> time until which a late deviceSave is written at once. Handler order across resources is not
-- defined, so phonekit's last save for a leaving player can arrive after our playerDropped.
local dropping = {}

local function logDebug(msg, fields)
    if AeternaCore and AeternaCore.log and type(AeternaCore.log.debug) == 'function' then
        AeternaCore.log.debug(msg, fields)
    end
end

local function isDropping(src)
    local untilMs = dropping[src]
    if untilMs == nil then
        return false
    end
    if now() >= untilMs then
        dropping[src] = nil
        return false
    end
    return true
end

local function isPlayer(src)
    return type(GetPlayerName) == 'function' and GetPlayerName(src) ~= nil
end

local function fireListen()
    TriggerEvent('aeterna_phonekit:listen')
end

--- Fires devicesChanged for a player on the next tick, once per player per tick. ox_inventory runs its
--- hooks before it moves or creates the item, so phonekit must ask again only after that has happened.
local function queueDevicesChanged(src)
    if changedPending[src] then
        return
    end
    changedPending[src] = true
    SetTimeout(0, function()
        if not changedPending[src] then
            return
        end
        changedPending[src] = nil
        if not isDropping(src) and isPlayer(src) then
            TriggerEvent('aeterna_phonekit:devicesChanged', src)
        end
    end)
end

local function phoneSlots(src)
    local result = A.searchSlots(src, phoneNames)
    if result == nil then
        return nil
    end
    return P.collectSlots(result, phoneNames)
end

local function buildAnswer(src)
    if #phoneNames == 0 then
        return {}
    end
    local slots = phoneSlots(src)
    if not slots then
        return {}
    end
    local devices, writes = P.buildDevices(slots, phoneMap)
    local failed = {}
    for _, w in ipairs(writes) do
        if not A.setMetadata(src, w.slot, w.metadata) then
            failed[w.id] = true
        end
    end
    if next(failed) == nil then
        return devices
    end
    -- An id that could not be stored would change on the next answer; leave that phone out.
    local kept = {}
    for _, d in ipairs(devices) do
        if not failed[d.id] then kept[#kept + 1] = d end
    end
    return kept
end

--- Writes one cleaned save into the phone item with that id. When the item is gone, nothing is written and
--- devicesChanged fires at once, unless `quiet` (the player is leaving).
local function writeSave(src, save, quiet)
    local slots = phoneSlots(src)
    local slot = slots and P.findById(slots, phoneMap, save.id) or nil
    if not slot then
        if quiet or not isPlayer(src) then
            logDebug('phone save dropped: item not found', { src = src, id = save.id })
        else
            TriggerEvent('aeterna_phonekit:devicesChanged', src)
        end
        return false
    end
    return A.setMetadata(src, tonumber(slot.slot), P.applySave(slot.metadata, save))
end

local function flushHeld(src, quiet)
    local held = saveQueue:take(src)
    if not held then
        return
    end
    local ids = {}
    for id in pairs(held) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        writeSave(src, held[id], quiet)
    end
end

local function syncPhoneHooks()
    if not enabled or not A.isOxStarted() then
        return false
    end
    return A.syncPhoneHooks({
        swapItems = function(payload)
            for _, src in ipairs(P.hookTargets('swapItems', payload, phoneMap, isPlayer)) do
                queueDevicesChanged(src)
            end
        end,
        createItem = function(payload)
            for _, src in ipairs(P.hookTargets('createItem', payload, phoneMap, isPlayer)) do
                queueDevicesChanged(src)
            end
        end,
    }, P.itemFilter(phoneMap))
end

AddEventHandler('aeterna_phonekit:hello', function()
    if not enabled then return end
    fireListen()
end)

AddEventHandler('aeterna_phonekit:asking', function(src, data)
    if not enabled then return end
    if type(data) ~= 'table' or data.devices ~= 'items' or data.checkId == nil then return end
    local target = tonumber(src)
    local devices = (target and target > 0) and buildAnswer(target) or {}
    TriggerEvent('aeterna_phonekit:answer', data.checkId, { allow = true, devices = devices })
end)

AddEventHandler('aeterna_phonekit:deviceSave', function(src, data)
    if not enabled then return end
    local target = tonumber(src)
    if not target or target <= 0 then return end
    local clean = P.cleanSave(data)
    if not clean then return end
    if isDropping(target) then
        writeSave(target, clean, true)
        return
    end
    local verdict, delay, first = saveQueue:offer(target, clean)
    if verdict == 'write' then
        writeSave(target, clean)
    elseif first then
        SetTimeout(delay, function()
            flushHeld(target)
        end)
    end
end)

AddEventHandler('onResourceStart', function(resName)
    if resName == 'ox_inventory' then
        syncPhoneHooks()
    end
end)

AddEventHandler('onResourceStop', function(resName)
    if not enabled or type(GetCurrentResourceName) ~= 'function' or resName ~= GetCurrentResourceName() then
        return
    end
    for _, src in ipairs(saveQueue:heldSources()) do
        flushHeld(src, true)
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    if not src then return end
    if enabled then
        flushHeld(src, true)
        dropping[src] = now() + P.DROP_GRACE_MS
        SetTimeout(P.DROP_GRACE_MS, function()
            if dropping[src] and now() >= dropping[src] then
                dropping[src] = nil
            end
        end)
    end
    saveQueue:drop(src)
    changedPending[src] = nil
end)

if enabled then
    syncPhoneHooks()
    fireListen()
end
