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

local function nativeYes(v) return v == true or v == 1 end

local function watchFor(watch, ms, until_)
    local waited = 0
    while waited < ms do
        watch.observe(hooks.voiceMessage())
        if until_ and until_() then return true end
        Wait(100)
        waited = waited + 100
    end
    watch.observe(hooks.voiceMessage())
    return until_ and until_() or false
end

-- The test drives pma-voice itself (owner 2026-11-23: no manual steps): voice_indicator presses its
-- cycleproximity command once round, so the range ends where it started; voice_radio joins a channel of its own,
-- transmits for a moment through +radiotalk / -radiotalk, then goes back to the presser's own channel.
local function voiceDrive(runId, name)
    local short = ST.shortName(name)
    local watch = ST.newVoiceWatch(name)
    watch.observe(hooks.voiceMessage())
    if short == 'voice_indicator' then
        for _ = 1, ST.cyclePresses(nil) do
            if not stillRunning(runId, name) then return end
            ExecuteCommand('cycleproximity')
            watchFor(watch, 700)
        end
    else
        local before = tonumber((LocalPlayer and LocalPlayer.state or {}).radioChannel) or 0
        pcall(function() exports['pma-voice']:setRadioChannel(ST.RADIO_TEST_CHANNEL) end)
        local joined = watchFor(watch, 3000, function()
            local m = hooks.voiceMessage()
            return m ~= nil and m.radio == true
        end)
        if joined and stillRunning(runId, name) then
            ExecuteCommand('+radiotalk')
            watchFor(watch, 2000, function()
                local m = hooks.voiceMessage()
                return m ~= nil and m.radioActive == true
            end)
            ExecuteCommand('-radiotalk')
            watchFor(watch, 300)
        end
        pcall(function() exports['pma-voice']:setRadioChannel(before) end)
    end
    if not stillRunning(runId, name) then return end
    local state = LocalPlayer and LocalPlayer.state or {}
    local dead = state.isDead == true or (type(IsPlayerDead) == 'function' and nativeYes(IsPlayerDead(PlayerId())))
    report(runId, name, watch.verdict({ dead = dead }))
end

-- seatbelt_event: a local test vehicle at the presser, seated as driver; nil when the presser already sits in one.
-- Returns ok, placed (what to undo).
local function seatInTestVehicle()
    if hooks.isInVehicle() then return true, nil end
    local ped = PlayerPedId()
    local model = GetHashKey(ST.SEATBELT_VEHICLE)
    RequestModel(model)
    local waited = 0
    while not nativeYes(HasModelLoaded(model)) and waited < ST.SEATBELT_WAIT_MS do
        Wait(100)
        waited = waited + 100
    end
    if not nativeYes(HasModelLoaded(model)) then return false, nil end
    local c = GetEntityCoords(ped)
    local placed = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ped) }
    placed.veh = CreateVehicle(model, c.x, c.y, c.z, placed.h, false, false)
    SetModelAsNoLongerNeeded(model)
    if not placed.veh or placed.veh == 0 then return false, nil end
    SetPedIntoVehicle(ped, placed.veh, -1)
    for _ = 1, 10 do
        if hooks.isInVehicle() then break end
        Wait(100)
    end
    return hooks.isInVehicle(), placed
end

local function leaveTestVehicle(placed)
    if not placed then return end
    local ped = PlayerPedId()
    SetEntityCoords(ped, placed.x, placed.y, placed.z, false, false, false, false)
    SetEntityHeading(ped, placed.h)
    if placed.veh and nativeYes(DoesEntityExist(placed.veh)) then DeleteEntity(placed.veh) end
end

-- Seats the presser in a test vehicle when on foot (owner 2026-11-23: no manual steps), fires the three payloads
-- through hudkit's own event handler and reads the icon state that handler sent to the page; then puts the
-- previous state and owner back, and the presser where they stood.
local function seatbeltEvent(runId, name)
    local seated, placed = seatInTestVehicle()
    if not stillRunning(runId, name) then
        leaveTestVehicle(placed)
        return
    end
    if not seated then
        leaveTestVehicle(placed)
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
    leaveTestVehicle(placed)
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
    voice_indicator = voiceDrive,
    voice_radio = voiceDrive,
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
