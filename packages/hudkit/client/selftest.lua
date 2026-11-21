-- client/selftest.lua -- runs the aeterna_hudkit self-tests that core sends to the presser's client
-- (ped, eye and the client mock). Decisions live in shared/logic/selftest.lua; this file only reads and sets
-- game state through HudkitSelftestHooks (client/main.lua).

local ST = HudSelftest
local hooks = HudkitSelftestHooks

local running = {} -- [full name] = runId while a test runs on this client

local function report(runId, name, state, detail, extra)
    exports.aeterna_core:reportSelftest(runId, name, state, detail, extra)
end

local function stillRunning(runId, name)
    return running[name] == runId
end

local function voiceStarted()
    return type(GetResourceState) == 'function' and GetResourceState(VoiceLogic.RESOURCE) == 'started'
end

local function barStyle(runId, name)
    hooks.showBarStyle('bar')
    Wait(500)
    if not stillRunning(runId, name) then return end
    hooks.showBarStyle('ring')
    Wait(500)
    if not stillRunning(runId, name) then return end
    report(runId, name, 'ready')
end

local function compassTape(runId, name)
    local ped = PlayerPedId()
    local startRel = GetGameplayCamRelativeHeading()
    local samples = {}
    for i, target in ipairs(ST.compassHeadings()) do
        local rel = ((target - GetEntityHeading(ped)) + 540) % 360 - 180
        SetGameplayCamRelativeHeading(rel)
        Wait(200)
        local rot = GetGameplayCamRot(2)
        Wait(120)
        samples[i] = { camZ = rot and rot.z or 0.0, sent = hooks.compassDeg() }
        if not stillRunning(runId, name) then break end
    end
    SetGameplayCamRelativeHeading(startRel)
    if not stillRunning(runId, name) then return end
    report(runId, name, ST.compassSamples(CompassLogic, samples, hooks.compassSpan()))
end

local function voiceWatch(runId, name)
    local watch = ST.newVoiceWatch(name)
    local waited = 0
    while waited < ST.VOICE_WATCH_MS and stillRunning(runId, name) do
        if watch.observe(hooks.voiceMessage()) then break end
        Wait(100)
        waited = waited + 100
    end
    if not stillRunning(runId, name) then return end
    report(runId, name, watch.verdict())
end

-- Waits up to SEATBELT_WAIT_MS for the presser to sit in a vehicle (the row's instruction), then fires the three
-- payloads through hudkit's own event handler and reads
-- the icon state that handler sent to the page; then puts the previous state and owner back.
local function seatbeltEvent(runId, name)
    local waited = 0
    while not hooks.isInVehicle() and waited < ST.SEATBELT_WAIT_MS and stillRunning(runId, name) do
        Wait(250)
        waited = waited + 250
    end
    if not stillRunning(runId, name) then return end
    if not hooks.isInVehicle() then
        report(runId, name, ST.seatbeltVerdict(nil, true, false))
        return
    end
    local before = hooks.seatbelt.snapshot()
    local observed = { n = 3 }
    for i, step in ipairs(ST.seatbeltSteps()) do
        TriggerEvent('aeterna_hudkit:seatbelt', step.payload)
        observed[i] = hooks.lastSeatbelt()
    end
    hooks.seatbelt.restore(before)
    local inVeh = hooks.isInVehicle()
    hooks.sendSeatbelt(inVeh)
    local restored = hooks.seatbelt.same(before) and hooks.lastSeatbelt() == hooks.seatbelt.display(inVeh)
    report(runId, name, ST.seatbeltVerdict(observed, restored, true))
end

local function minimapFollows(runId, name)
    local original = hooks.minimapPlace()
    local metrics = hooks.minimapMetrics()
    local back = original or { x = metrics.defaultSx, y = metrics.defaultSy, ax = 0.0, ay = 1.0, scale = 1.0 }
    local state, detail, extra = 'pass', nil, nil
    for i, place in ipairs(ST.minimapPlaces(back)) do
        hooks.applyMinimapPlace(place)
        Wait(100)
        state, detail = ST.minimapCheck(MinimapLogic, metrics, place, hooks.appliedMinimap())
        if state ~= 'pass' then
            extra = { step = i, expected = i == 1 and 'radar at the top-right' or 'radar back in place' }
            hooks.applyMinimapPlace(back)
            break
        end
    end
    if not original then hooks.clearMinimapPlace() end
    if not stillRunning(runId, name) then return end
    report(runId, name, state, detail, extra)
end

local CLIENT_TESTS = {
    bar_style = barStyle,
    compass_tape = compassTape,
    voice_indicator = voiceWatch,
    voice_radio = voiceWatch,
    seatbelt_event = seatbeltEvent,
    minimap_follows = minimapFollows,
}

AddEventHandler('aeterna_core:selftest', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' then return end -- only core runs tests
    local short = ST.shortName(name)
    local test = short and CLIENT_TESTS[short]
    if not test then return end
    local reason = ST.skipReason(short, Config, { voiceStarted = voiceStarted() })
    if reason then
        report(runId, name, 'skip', reason)
        return
    end
    running[name] = runId
    CreateThread(function()
        test(runId, name)
    end)
end)

AddEventHandler('aeterna_core:selftestEnd', function(runId, name)
    if GetInvokingResource() ~= 'aeterna_core' then return end -- only core runs tests
    local short = ST.shortName(name)
    if not short or running[name] ~= runId then return end
    running[name] = nil
    if short == 'bar_style' then
        hooks.showBarStyle(hooks.barStyle())
    end
end)
