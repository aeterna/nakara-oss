-- shared/logic/selftest.lua -- natives-free rules of the aeterna_radial 0.2 self-tests
-- (docs/specs/aeterna_radial.md § Self-tests (0.2)). Judges return state, detail for
-- exports.aeterna_core:reportSelftest; server/selftest.lua and client/selftest.lua stay thin.
-- server_recheck is prepared by the server on aeterna_core:selftestStarted (a vehicle-only server slot sent to
-- the presser alone) and judged on the client.

RadialSelftest = RadialSelftest or {}

local PREFIX = 'aeterna_radial.'

-- An eye test opens the ring and waits this long for the person to act before it asks for the card.
RadialSelftest.EYE_WATCH_MS = 50000
-- gamepad: with no pad input at all for this long, the row skips (a stick cannot be driven).
RadialSelftest.PAD_IDLE_MS = 3000
-- open_pick / child_ring: the test drives the ring itself (owner 2026-11-23: no manual steps), one step per
-- DRIVE_STEP_MS, slow enough for the person to see each highlight before the card asks.
RadialSelftest.DRIVE_STEP_MS = 400
-- server_recheck: how long the client waits for the test slot, then for the server's answer to the pick.
RadialSelftest.SLOT_WAIT_MS = 2000
RadialSelftest.DROP_WAIT_MS = 1500
RadialSelftest.RECHECK_ID = 'selftest_recheck'

local ROWS = {
    { name = 'registry', kind = 'headless' },
    { name = 'conditions', kind = 'headless' },
    { name = 'server_recheck', kind = 'ped' },
    { name = 'open_pick', kind = 'eye' },
    { name = 'child_ring', kind = 'eye' },
    { name = 'gamepad', kind = 'eye' },
}

local KNOWN = {}
for _, row in ipairs(ROWS) do KNOWN[row.name] = true end

--- The registered rows in spec order: { { name, meta }, … }. `t(key)` translates the expect strings.
function RadialSelftest.definitions(t)
    t = t or function(key) return key end
    local out = {}
    for i, row in ipairs(ROWS) do
        local meta = { kind = row.kind, players = 1, destructive = false }
        if row.kind == 'eye' then
            meta.expect = t('radial.selftest.' .. row.name .. '.expect')
            meta.timeout = 60000
        elseif row.kind == 'ped' then
            meta.timeout = 10000
        end
        out[i] = { name = row.name, meta = meta }
    end
    return out
end

--- 'aeterna_radial.<name>' -> '<name>' for this package's own rows, else nil.
function RadialSelftest.shortName(fullName)
    if type(fullName) ~= 'string' or fullName:sub(1, #PREFIX) ~= PREFIX then return nil end
    local short = fullName:sub(#PREFIX + 1)
    return KNOWN[short] and short or nil
end

local function firstMismatch(checks)
    for _, c in ipairs(checks) do
        if c[2] ~= c[3] then
            return ('%s: got %s, expected %s'):format(c[1], tostring(c[2]), tostring(c[3]))
        end
    end
    return nil
end

--- registry: replace, per-owner and total limits, depth and cross-owner parents, owner stop.
function RadialSelftest.registryCheck(L)
    local small = L.createRegistry({ maxPerOwner = 2, maxTotal = 3 })
    local added = small:addSlot('res_a', { id = 'a1', label = 'A1' }, 'client')
    local replaced = small:addSlot('res_a', { id = 'a1', label = 'A1b' }, 'client')
    local replacedLabel = small:getSlot('res_a', 'a1', 'client').label
    small:addSlot('res_a', { id = 'a2', label = 'A2' }, 'client')
    local _, perOwnerErr = small:addSlot('res_a', { id = 'a3', label = 'A3' }, 'client')
    small:addSlot('res_b', { id = 'b1', label = 'B1' }, 'client')
    local _, totalErr = small:addSlot('res_b', { id = 'b2', label = 'B2' }, 'client')

    local reg = L.createRegistry({ maxPerOwner = 64, maxTotal = 128 })
    reg:addSlot('res_a', { id = 'grp', label = 'Group' }, 'client')
    local child = reg:addSlot('res_a', { id = 'c1', label = 'C1', parent = 'grp' }, 'client')
    local grandOk, grandErr = reg:addSlot('res_a', { id = 'c2', label = 'C2', parent = 'c1' }, 'client')
    local _, crossErr = reg:addSlot('res_b', { id = 'x1', label = 'X1', parent = 'grp' }, 'client')
    reg:addSlot('res_b', { id = 'b1', label = 'B1' }, 'client')
    reg:setFlag('res_a', 'f', true)
    reg:setFlag('res_b', 'g', true)
    reg:removeByOwner('res_a')

    local bad = firstMismatch({
        { 'add', added, true },
        { 'replace same owner/id', replaced and replacedLabel, 'A1b' },
        { 'maxPerOwner', perOwnerErr, 'maxPerOwner limit reached' },
        { 'maxTotal', totalErr, 'maxTotal limit reached' },
        { 'child of a root', child, true },
        { 'child of a child', grandOk == true and 'accepted' or grandErr, 'parent: depth' },
        { 'parent of another owner', crossErr, 'parent: unknown' },
        { 'owner stop removes its slots', reg:getSlot('res_a', 'grp', 'client'), nil },
        { 'owner stop removes its flags', reg:getFlag('res_a', 'f'), false },
        { 'owner stop keeps other slots', reg:getSlot('res_b', 'b1', 'client') ~= nil, true },
        { 'owner stop keeps other flags', reg:getFlag('res_b', 'g'), true },
    })
    if bad then return 'fail', bad end
    return 'pass', 'add, replace, limits, parents and owner stop behave as specified'
end

--- conditions: vehicle in/out/driver, jobs + grade, missing qbx_core, flags all-true.
function RadialSelftest.conditionsCheck(L)
    local onFoot = { inVehicle = false, isDriver = false }
    local passenger = { inVehicle = true, isDriver = false }
    local driver = { inVehicle = true, isDriver = true }
    local function job(name, grade, qbx)
        return { hasQbx = qbx ~= false, job = name, grade = grade }
    end
    local flags = { res_a = { a = true, b = true } }
    local half = { res_a = { a = true, b = false } }
    local bad = firstMismatch({
        { 'no condition', L.evalCondition(nil, onFoot), true },
        { 'vehicle in, on foot', L.evalCondition({ vehicle = 'in' }, onFoot), false },
        { 'vehicle in, passenger', L.evalCondition({ vehicle = 'in' }, passenger), true },
        { 'vehicle out, passenger', L.evalCondition({ vehicle = 'out' }, passenger), false },
        { 'vehicle out, on foot', L.evalCondition({ vehicle = 'out' }, onFoot), true },
        { 'vehicle driver, passenger', L.evalCondition({ vehicle = 'driver' }, passenger), false },
        { 'vehicle driver, driver', L.evalCondition({ vehicle = 'driver' }, driver), true },
        { 'jobs + grade met', L.evalCondition({ jobs = { 'police' }, grade = 2 }, job('police', 3)), true },
        { 'jobs, grade too low', L.evalCondition({ jobs = { 'police' }, grade = 2 }, job('police', 1)), false },
        { 'jobs, other job', L.evalCondition({ jobs = { 'police' } }, job('ems', 5)), false },
        { 'jobs without qbx_core', L.evalCondition({ jobs = { 'police' } }, job('police', 5, false)), false },
        { 'flags all true', L.evalCondition({ flags = { 'a', 'b' } }, { owner = 'res_a', flags = flags }), true },
        { 'flags one false', L.evalCondition({ flags = { 'a', 'b' } }, { owner = 'res_a', flags = half }), false },
    })
    if bad then return 'fail', bad end
    return 'pass', 'vehicle, jobs, grade and flag conditions decide as specified'
end

--- Temporary client slots under the owner aeterna_radial. `t(key, vars)` translates labels.
function RadialSelftest.testSlots(name, t)
    t = t or function(key) return key end
    local slots = {}
    if name == 'child_ring' then
        slots[1] = { id = 'selftest_group', label = t('radial.selftest.group'), order = 1 }
        for i = 1, 3 do
            slots[#slots + 1] = { id = 'selftest_child_' .. i, label = t('radial.selftest.slot', { n = i }),
                order = i, parent = 'selftest_group' }
        end
    else
        for i = 1, 6 do
            slots[i] = { id = 'selftest_' .. i, label = t('radial.selftest.slot', { n = i }), order = i }
        end
    end
    return slots
end

--- The steps the test takes on the open ring: { op = 'hover' | 'pick', id } or { op = 'back' }.
function RadialSelftest.drivePlan(name)
    local plan = {}
    if name == 'open_pick' then
        for i = 1, 6 do plan[#plan + 1] = { op = 'hover', id = 'selftest_' .. i } end
        plan[#plan + 1] = { op = 'hover', id = 'selftest_3' }
        plan[#plan + 1] = { op = 'pick', id = 'selftest_3' }
    elseif name == 'child_ring' then
        plan[#plan + 1] = { op = 'hover', id = 'selftest_group' }
        plan[#plan + 1] = { op = 'pick', id = 'selftest_group' }
        for i = 1, 3 do plan[#plan + 1] = { op = 'hover', id = 'selftest_child_' .. i } end
        plan[#plan + 1] = { op = 'back' }
    end
    return plan
end

--- The line shown after a test slot is picked.
function RadialSelftest.pickedLine(t, label)
    return t('radial.selftest.picked', { label = label })
end

--- observe(ev, elapsedMs) returns true once the person has done what the card will ask about:
--- ev = { type = 'pick', id } or { type = 'state', open, parentId?, hoverId?, pad? } (pad = last input was a
--- gamepad). gamepad: only a close made with the pad counts; with no pad input at all, PAD_IDLE_MS is enough.
function RadialSelftest.newEyeWatch(name)
    local sawOpen, sawChild, sawPad = false, false, false
    local w = {}

    function w.sawPad() return sawPad end

    function w.observe(ev, elapsedMs)
        if type(ev) ~= 'table' then return false end
        if name == 'open_pick' then
            return ev.type == 'pick' and type(ev.id) == 'string' and ev.id:match('^selftest_%d$') ~= nil
        end
        if ev.type ~= 'state' then return false end
        if name == 'child_ring' then
            if ev.open and ev.parentId == 'selftest_group' then sawChild = true end
            return sawChild and ev.open == true and ev.parentId == nil and ev.hoverId == 'selftest_group'
        end
        if ev.pad then sawPad = true end
        if ev.open and ev.pad then sawOpen = true end
        if sawOpen and not ev.open and ev.pad then return true end
        return not sawPad and (tonumber(elapsedMs) or 0) >= RadialSelftest.PAD_IDLE_MS
    end

    return w
end

--- server_recheck: the temporary server slot, shown only in a vehicle.
function RadialSelftest.recheckSlot(t)
    t = t or function(key) return key end
    return { id = RadialSelftest.RECHECK_ID, label = t('radial.selftest.recheck'), when = { vehicle = 'in' } }
end

--- r = { arrived = the test slot reached the presser, stillThere = it is still there after the pick }.
--- The server takes the slot back only when it accepts the pick, so a slot still there means it dropped it.
function RadialSelftest.recheckVerdict(r)
    r = r or {}
    if not r.arrived then
        return 'fail', 'the test server slot never reached the presser'
    end
    if not r.stillThere then
        return 'fail', 'the server accepted a vehicle-only pick from a player on foot'
    end
    return 'pass', 'the server dropped a vehicle-only pick from a player on foot'
end

return RadialSelftest
