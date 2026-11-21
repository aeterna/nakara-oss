-- client/selftest.lua -- runs the aeterna_radial eye self-tests on the presser's client: adds temporary slots
-- under the owner aeterna_radial, opens the ring, waits for the person to use it, then asks for the eye card
-- (the card takes focus, so the person acts first). Decisions live in shared/logic/selftest.lua.

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
        if test.picked or test.watch.observe(hooks.state()) then break end
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

AddEventHandler('aeterna_core:selftest', function(runId, name)
    local short = ST.shortName(name)
    if short ~= 'open_pick' and short ~= 'child_ring' and short ~= 'gamepad' then return end
    if current then cleanUp(current) end
    local test = { runId = runId, name = name, short = short, watch = ST.newEyeWatch(short), ids = {}, labels = {} }
    current = test
    CreateThread(function() run(test) end)
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    local test = current
    if not test or test.runId ~= runId or test.name ~= name then return end
    current = nil
    cleanUp(test)
end)
