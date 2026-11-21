-- server/selftest.lua -- registers the aeterna_invkit 0.2 self-tests with aeterna_core, runs the server rows
-- (three headless checks and the phone_device_save mock) and prepares item_use for the presser's client on
-- aeterna_core:selftestStarted. Client rows report from client/selftest.lua; this file never reports for them.

local ST = InvkitSelftest
local P = InvkitPhoneLogic
local A = InvkitOxAdapter
local hooks = InvkitServerSelftestHooks
local RESOURCE = GetCurrentResourceName()

local function translate(key, vars)
    if AeternaCore and type(AeternaCore.t) == 'function' then
        return AeternaCore.t(key, vars)
    end
    if Locales and Locales.en and Locales.en[key] then
        return Locales.en[key]
    end
    return key
end

local function mayWrite(runId, name)
    return AeternaCore.selftest.mayWrite(runId, name) == true
end

for _, row in ipairs(ST.definitions(translate, Config)) do
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
-- item's metadata back, then removes that item by its serial. Only the item it created is written or removed.
local function phoneDeviceSave(runId, name, src)
    local map = P.validateItemMap(phoneConfig().items)
    local names = P.itemNames(map)
    local item = ST.testPhoneItem(map)
    local taken = {}
    local _, slots = findTestPhone(src, map, names, nil)
    for _, slot in ipairs(slots) do
        if type(slot.metadata) == 'table' and slot.metadata.phoneId then taken[slot.metadata.phoneId] = true end
    end
    local id = P.newPhoneId(taken)
    if not mayWrite(runId, name) then
        return ST.deviceSaveVerdict({ guard = false })
    end
    local countBefore = item and A.itemCount(src, item)
    if not item or not id or countBefore == nil or not A.addItem(src, item, 1, { phoneId = id }) then
        return ST.deviceSaveVerdict({ given = false, item = item })
    end

    local slot = nil
    if mayWrite(runId, name) then
        TriggerEvent('aeterna_phonekit:deviceSave', src, { id = id, battery = ST.SAVE.battery, fold = ST.SAVE.fold })
        local waited = 0
        while waited <= ST.SAVE_WAIT_MS do
            slot = findTestPhone(src, map, names, id)
            local md = slot and slot.metadata
            if type(md) == 'table' and md.battery == ST.SAVE.battery and md.fold == ST.SAVE.fold then break end
            Wait(250)
            waited = waited + 250
        end
    end

    local metadata = slot and slot.metadata or nil
    A.removeTagged(src, item, 1, { phoneId = id })
    local gone = A.itemCount(src, item) == countBefore
    return ST.deviceSaveVerdict({ given = true, item = item, id = id, metadata = metadata, gone = gone })
end

local SERVER_TESTS = {
    stash_id = function() return ST.stashIdCheck(InvkitLogic) end,
    use_state_machine = function() return ST.useStateMachine(InvkitLogic) end,
    phone_item_map = function() return ST.phoneItemMap(P, phoneConfig().items) end,
    phone_device_save = function(runId, name, ctx) return phoneDeviceSave(runId, name, tonumber(ctx.a)) end,
}

AddEventHandler('aeterna_core:selftest', function(runId, name, ctx)
    if GetInvokingResource() ~= 'aeterna_core' then return end -- only core runs tests
    local short = ST.shortName(name)
    local test = short and SERVER_TESTS[short]
    if not test then return end
    ctx = type(ctx) == 'table' and ctx or {}
    local reason = ST.skipReason(short, Config, { oxStarted = A.isOxStarted(), presser = tonumber(ctx.a) ~= nil })
    if reason then
        exports.aeterna_core:reportSelftest(runId, name, 'skip', reason)
        return
    end
    CreateThread(function()
        exports.aeterna_core:reportSelftest(runId, name, test(runId, name, ctx))
    end)
end)

-- item_use: server state for the client test. key = runId .. '|' .. name.
local prepared = {}

local function tag(runId)
    return { aeterna_selftest = runId }
end

local function findTagged(src, item, runId)
    local result = A.searchSlots(src, { item })
    for _, slot in ipairs(result and P.collectSlots(result, { item }) or {}) do
        if type(slot.metadata) == 'table' and slot.metadata.aeterna_selftest == runId then return slot end
    end
    return nil
end

local function unregister(prep)
    local entry = hooks.useManager:getUsable(prep.item)
    if prep.registered and entry and entry.owner == RESOURCE then
        hooks.useManager:unregisterUsable(prep.item, RESOURCE)
        hooks.syncOxHook()
    end
    prep.registered = false
end

-- The use gate: a test registration takes only the presser's item tagged with the run id. Any other player's
-- use, or the presser's own untagged item of the same name, falls through to ox_inventory.
local function useGate(src, item, slot, metadata, entry)
    if type(entry) ~= 'table' or entry.owner ~= RESOURCE then return true end
    for _, prep in pairs(prepared) do
        if prep.item == item and prep.src == src then
            if type(metadata) == 'table' then return metadata.aeterna_selftest == prep.runId end
            local tagged = findTagged(src, item, prep.runId)
            return tagged ~= nil and tonumber(tagged.slot) == tonumber(slot)
        end
    end
    return false
end
hooks.setUseGate(useGate)

-- Registers a usable on a free default item, gives the presser one tagged with the run id, and starts the use
-- once the client listens. Nothing happens unless the write guard agrees, at the start and again before the use.
local function prepareItemUse(runId, name, src)
    local item = ST.pickUseItem(function(n) return hooks.useManager:getUsable(n) ~= nil end)
    if not item or not mayWrite(runId, name) then return end
    local prep = { src = src, item = item, runId = runId }
    if not hooks.useManager:registerUsable(RESOURCE, item, ST.USE_DEF) then return end
    prep.registered = true
    hooks.syncOxHook()
    if not A.addItem(src, item, 1, tag(runId)) then
        unregister(prep)
        return
    end
    prep.given = true
    local key = runId .. '|' .. name
    prepared[key] = prep
    SetTimeout(ST.USE_START_DELAY_MS, function()
        if prepared[key] ~= prep or not mayWrite(runId, name) then return end
        local slot = findTagged(src, item, runId)
        if slot and useGate(src, item, tonumber(slot.slot), slot.metadata, hooks.useManager:getUsable(item)) then
            hooks.useManager:startUse(src, item, tonumber(slot.slot))
        end
    end)
end

AddEventHandler('aeterna_core:selftestStarted', function(runId, name, ctx)
    if GetInvokingResource() ~= 'aeterna_core' then return end -- only core runs tests
    if ST.shortName(name) ~= 'item_use' then return end
    local src = type(ctx) == 'table' and tonumber(ctx.a) or nil
    if not src or not A.isOxStarted() then return end
    prepareItemUse(runId, name, src)
end)

-- The used event for the test item: drop the registration at once, so the use runs exactly once.
AddEventHandler('aeterna_invkit:used', function(src, data)
    local invoker = GetInvokingResource()
    if invoker ~= nil and invoker ~= RESOURCE then return end -- fired by invkit's own use manager only
    if type(data) ~= 'table' or data.owner ~= RESOURCE then return end
    for _, prep in pairs(prepared) do
        if prep.src == src and prep.item == data.item then unregister(prep) end
    end
end)

local function tearDown(key)
    local prep = prepared[key]
    if not prep then return end
    prepared[key] = nil
    local pending = hooks.useManager:getPending(prep.src)
    if pending and pending.owner == RESOURCE and pending.item == prep.item then
        hooks.useManager:cancel(prep.src)
    end
    unregister(prep)
    if prep.given then A.removeTagged(prep.src, prep.item, 1, tag(prep.runId)) end
end

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' then return end -- only core runs tests
    tearDown(tostring(runId) .. '|' .. tostring(name))
end)

-- aeterna_core or invkit itself stopped mid-test: no selftestEnd will come, so undo every preparation now.
AddEventHandler('onResourceStop', function(res)
    if res ~= 'aeterna_core' and res ~= RESOURCE then return end
    for key in pairs(prepared) do tearDown(key) end
end)
