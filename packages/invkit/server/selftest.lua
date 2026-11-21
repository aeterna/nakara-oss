-- server/selftest.lua -- registers the aeterna_invkit 0.2 self-tests with aeterna_core and runs the server
-- rows (three headless checks and the phone_device_save mock). stash_open runs in client/selftest.lua.

local ST = InvkitSelftest
local P = InvkitPhoneLogic
local A = InvkitOxAdapter

local function translate(key)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key)
    end
    if Locales and Locales.en and Locales.en[key] then
        return Locales.en[key]
    end
    return key
end

for _, row in ipairs(ST.definitions(translate)) do
    exports.aeterna_core:addSelftest(row.name, row.meta)
end

local function phoneConfig()
    return (Config and type(Config.phone) == 'table') and Config.phone or {}
end

local function findTestPhone(src, map, names, id)
    local result = A.searchSlots(src, names)
    local slots = result and P.collectSlots(result, names) or {}
    return P.findById(slots, map, id), slots
end

-- Gives the presser one phone item with a fresh serial, fires deviceSave for it as phonekit would, reads the
-- item's metadata back, then removes the item. Only the item it created is written or removed.
local function phoneDeviceSave(src)
    local map = P.validateItemMap(phoneConfig().items)
    local names = P.itemNames(map)
    local item = ST.testPhoneItem(map)
    local taken = {}
    local _, slots = findTestPhone(src, map, names, nil)
    for _, slot in ipairs(slots) do
        if type(slot.metadata) == 'table' and slot.metadata.phoneId then taken[slot.metadata.phoneId] = true end
    end
    local id = P.newPhoneId(taken)
    if not item or not id or not A.addItem(src, item, 1, { phoneId = id }) then
        return ST.deviceSaveVerdict({ given = false, item = item })
    end

    TriggerEvent('aeterna_phonekit:deviceSave', src,
        { id = id, battery = ST.SAVE.battery, fold = ST.SAVE.fold })
    local slot = nil
    local waited = 0
    while waited <= ST.SAVE_WAIT_MS do
        slot = findTestPhone(src, map, names, id)
        local md = slot and slot.metadata
        if type(md) == 'table' and md.battery == ST.SAVE.battery and md.fold == ST.SAVE.fold then break end
        Wait(250)
        waited = waited + 250
    end

    local metadata = slot and slot.metadata or nil
    if slot then A.removeItem(src, item, 1, tonumber(slot.slot)) end
    local gone = findTestPhone(src, map, names, id) == nil
    return ST.deviceSaveVerdict({ given = true, item = item, id = id, metadata = metadata, gone = gone })
end

local SERVER_TESTS = {
    stash_id = function() return ST.stashIdCheck(InvkitLogic) end,
    use_state_machine = function() return ST.useStateMachine(InvkitLogic) end,
    phone_item_map = function() return ST.phoneItemMap(P, phoneConfig().items) end,
    phone_device_save = function(ctx)
        local src = type(ctx) == 'table' and tonumber(ctx.a) or nil
        if not src then return 'fail', 'needs a presser: run it from the test menu' end
        return phoneDeviceSave(src)
    end,
}

AddEventHandler('aeterna_core:selftest', function(runId, name, ctx)
    local short = ST.shortName(name)
    local test = short and SERVER_TESTS[short]
    if not test then return end
    local reason = ST.skipReason(short, Config, { oxStarted = A.isOxStarted() })
    if reason then
        exports.aeterna_core:reportSelftest(runId, name, 'skip', reason)
        return
    end
    CreateThread(function()
        exports.aeterna_core:reportSelftest(runId, name, test(ctx))
    end)
end)
