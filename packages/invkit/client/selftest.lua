-- client/selftest.lua -- runs the aeterna_invkit client self-tests on the presser's client: stash_open (moves the
-- presser to a stash point and away, sending the same request as the bound key at each stop), item_use (watches the item the server gave for
-- this run go through one use) and the three phone ped rows (read the presser's own ox_inventory and build the
-- device list invkit answers phonekit with). Decisions live in shared/logic/selftest.lua.

local ST = InvkitSelftest
local L = InvkitLogic

local running = {} -- [full name] = runId
local lastRefusal = nil
local useCount = 0 -- aeterna_invkit:cl:use events seen while item_use runs

local function report(runId, name, state, detail, extra)
    exports.aeterna_core:reportSelftest(runId, name, state, detail, extra)
end

AddEventHandler('aeterna_invkit:cl:refused', function(data)
    if type(data) == 'table' and data.item == 'stash' and type(data.reason) == 'string' then
        lastRefusal = data.reason
    end
end)

-- ox_inventory marks its open inventory in the player's state bag.
local function inventoryOpen()
    local ok, open = pcall(function() return LocalPlayer.state.invOpen end)
    return ok and open == true
end

local function closeInventory()
    pcall(function() exports.ox_inventory:closeInventory() end)
end

-- Sends one open request and waits up to 1500 ms: 'opened', 'refused' (+ reason) or 'none'.
local function tryOpen()
    lastRefusal = nil
    TriggerServerEvent('aeterna_invkit:sv:open')
    for _ = 1, 15 do
        Wait(100)
        if lastRefusal then return 'refused', lastRefusal end
        if inventoryOpen() then
            closeInventory()
            return 'opened'
        end
    end
    return 'none'
end

-- The test moves the presser itself (owner 2026-11-23: no manual steps): to the first stash point, then away from
-- every point, sends the bound key's open request at each stop, then puts the presser back where they stood.
local function stashOpen(runId, name)
    local cfg = Config.stash
    local watch = ST.newStashWatch(cfg.anywhere == true)
    local stops = ST.stashStops(cfg.points) or {}
    local ped = PlayerPedId()
    local origin = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    for _, stop in ipairs(stops) do
        if running[name] ~= runId then break end
        SetEntityCoords(ped, stop.x, stop.y, stop.z, false, false, false, false)
        Wait(500)
        local canOpen = (L.canOpenAt(GetEntityCoords(ped), cfg))
        if watch.needs(canOpen) then
            local outcome, reason = tryOpen()
            if watch.record(canOpen, outcome, reason) then break end
        end
    end
    SetEntityCoords(ped, origin.x, origin.y, origin.z, false, false, false, false)
    SetEntityHeading(ped, heading)
    if running[name] ~= runId then return end
    report(runId, name, watch.verdict())
end

-- Counts only the test's own use (its label); a real use of another item during the test is not counted.
AddEventHandler('aeterna_invkit:cl:use', function(data)
    if type(data) == 'table' and data.label == ST.USE_DEF.label then
        useCount = useCount + 1
    end
end)

-- Tagged test items of this run, from the client's own ox_inventory view: item name and count.
local function taggedItem(runId)
    for _, item in ipairs(ST.USE_ITEMS) do
        local ok, count = pcall(function()
            return exports.ox_inventory:Search('count', item, { aeterna_selftest = runId })
        end)
        if ok and (tonumber(count) or 0) > 0 then return item, tonumber(count) end
    end
    return nil, 0
end

local function waitFor(runId, name, ms, check)
    local waited = 0
    while waited < ms and running[name] == runId do
        if check() then return true end
        Wait(250)
        waited = waited + 250
    end
    return check()
end

-- The server gives the item and starts the use (aeterna_core:selftestStarted); this side watches it.
local function itemUse(runId, name)
    useCount = 0
    local item, before = nil, 0
    waitFor(runId, name, ST.ITEM_WAIT_MS, function()
        item, before = taggedItem(runId)
        return item ~= nil
    end)
    local after = before
    if item then
        waitFor(runId, name, ST.USE_WAIT_MS, function()
            local _, n = taggedItem(runId)
            after = n
            return useCount >= 1 and after == 0
        end)
        Wait(500) -- a second use would show up here
    end
    if running[name] ~= runId then return end
    report(runId, name, ST.itemUseVerdict({ before = before, uses = useCount, after = after }))
end

local function phoneDevices()
    local map = InvkitPhoneLogic.validateItemMap(Config.phone and Config.phone.items)
    local names = InvkitPhoneLogic.itemNames(map)
    if #names == 0 then return {} end
    local ok, result = pcall(function() return exports.ox_inventory:Search('slots', names) end)
    if not ok or type(result) ~= 'table' then return nil end
    return ST.devicesFrom(InvkitPhoneLogic, InvkitPhoneLogic.collectSlots(result, names), map)
end

local function phoneWatch(runId, name, short)
    local watch = ST.newPhoneWatch(short)
    waitFor(runId, name, ST.PHONE_WATCH_MS, function() return watch.observe(phoneDevices()) end)
    if running[name] ~= runId then return end
    report(runId, name, watch.verdict())
end

local CLIENT_TESTS = {
    stash_open = stashOpen,
    item_use = itemUse,
    phone_two_items = phoneWatch,
    phone_drop_active = phoneWatch,
    phone_no_item = phoneWatch,
}

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' then return end -- only core runs tests
    local short = ST.shortName(name)
    local test = short and CLIENT_TESTS[short]
    if not test then return end
    local reason = ST.skipReason(short, Config, {
        oxStarted = GetResourceState('ox_inventory') == 'started',
        phonekitStarted = GetResourceState('aeterna_phonekit') == 'started',
    })
    if reason then
        report(runId, name, 'skip', reason)
        return
    end
    running[name] = runId
    CreateThread(function()
        test(runId, name, short)
    end)
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' then return end -- only core runs tests
    if running[name] == runId then running[name] = nil end
end)
