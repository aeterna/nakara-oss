-- client/selftest.lua -- runs the aeterna_radial client self-tests on the presser's client. Eye tests add
-- temporary slots under the owner aeterna_radial, open the ring, wait for the person to use it, then ask for the
-- eye card (the card takes focus, so the person acts first). server_recheck sends a forged pick for the
-- vehicle-only server slot the server prepared for this run. Decisions live in shared/logic/selftest.lua.

local ST = RadialSelftest
local hooks = RadialSelftestHooks
local RESOURCE = GetCurrentResourceName()

local current = nil -- { runId, name, short, watch, ids, labels } of the eye test running on this client

local function report(runId, name, state, detail)
    exports.aeterna_core:reportSelftest(runId, name, state, detail)
end

local function feedLine(text)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandThefeedPostTicker(false, false)
end

local function cleanUp(test)
    if hooks.state().open then hooks.close() end
    for i = #test.ids, 1, -1 do hooks.removeSlot(test.ids[i]) end
end

local function run(test)
    for _, slot in ipairs(ST.testSlots(test.short, AeternaCore.t)) do
        if hooks.addSlot(slot) then
            test.ids[#test.ids + 1] = slot.id
            test.labels[slot.id] = slot.label
        end
    end
    hooks.open()
    if not hooks.state().open then
        report(test.runId, test.name, 'fail', 'the radial menu did not open')
        return
    end
    local waited = 0
    while current == test and waited < ST.EYE_WATCH_MS do
        if test.picked or test.watch.observe(hooks.state(), waited) then break end
        Wait(100)
        waited = waited + 100
    end
    if current ~= test then return end
    report(test.runId, test.name, 'ready')
end

-- Picks of the temporary slots: say which one, and tell the watch.
AddEventHandler('aeterna_radial:select', function(owner, id)
    local test = current
    if not test or owner ~= RESOURCE or not test.labels[id] then return end
    feedLine(ST.pickedLine(AeternaCore.t, test.labels[id]))
    if test.watch.observe({ type = 'pick', id = id }) then test.picked = true end
end)

-- server_recheck: on foot, pick the vehicle-only server slot straight to the server (the client's own check is
-- skipped on purpose, as a forged pick would). The server takes the slot back only if it accepts the pick.
local function serverRecheck(runId, name)
    local function there() return hooks.hasServerSlot(RESOURCE, ST.RECHECK_ID) end
    local waited = 0
    while not there() and waited < ST.SLOT_WAIT_MS do
        Wait(100)
        waited = waited + 100
    end
    local arrived = there()
    if arrived then
        TriggerServerEvent('aeterna_radial:sv:select', { owner = RESOURCE, id = ST.RECHECK_ID })
        Wait(ST.DROP_WAIT_MS)
    end
    report(runId, name, ST.recheckVerdict({ arrived = arrived, stillThere = there() }))
end

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' then return end -- only core runs tests
    local short = ST.shortName(name)
    if short == 'server_recheck' then
        if hooks.inVehicle() then
            report(runId, name, 'skip', 'presser is in a vehicle')
            return
        end
        CreateThread(function() serverRecheck(runId, name) end)
        return
    end
    if short ~= 'open_pick' and short ~= 'child_ring' and short ~= 'gamepad' then return end
    if current then cleanUp(current) end
    local test = { runId = runId, name = name, short = short, watch = ST.newEyeWatch(short), ids = {}, labels = {} }
    current = test
    CreateThread(function() run(test) end)
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' then return end -- only core runs tests
    local test = current
    if not test or test.runId ~= runId or test.name ~= name then return end
    current = nil
    cleanUp(test)
end)
