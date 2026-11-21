-- aeterna_core server: self-test registry, runner and aeterna_core_selftest command.

AeternaCoreLogic = AeternaCoreLogic or {}
AeternaCore = AeternaCore or {}

local ID_CHARS = '0123456789abcdefghijklmnopqrstuvwxyz'
local ST = AeternaCoreLogic.selftest

local registeredTests = {}
local noneReasons = {}
local activeRuns = {}
local lock = nil
local runSeq = 0

local function normalizeTestName(owner, name)
    local cleanName = tostring(name or '')
    local prefix = tostring(owner) .. '.'
    if cleanName:sub(1, #prefix) == prefix then
        return cleanName
    end
    return prefix .. cleanName
end

local function addSelftestInternal(owner, name, meta)
    if type(name) ~= 'string' or name == '' then
        return nil
    end
    local resOwner = tostring(owner or GetCurrentResourceName() or 'aeterna_core')
    local fullName = normalizeTestName(resOwner, name)
    local test, err, warn = ST.normalize(meta)
    if not test then
        AeternaCore.log.warn('selftest refused', { name = fullName, reason = err })
        return nil, err
    end
    if warn then
        AeternaCore.log.warn('selftest meta', { name = fullName, reason = warn })
    end
    for i = 1, #registeredTests do
        if registeredTests[i].name == fullName then
            registeredTests[i].owner = resOwner
            registeredTests[i].test = test
            return fullName
        end
    end
    registeredTests[#registeredTests + 1] = {
        name = fullName,
        owner = resOwner,
        test = test,
    }
    return fullName
end

-- Turns a report into a judged result { state, detail, step, expected } (rules in shared/logic/selftest.lua).
local function judge(test, report)
    local state, detail = ST.fold(test, report)
    return { state = state, detail = detail, step = report.step, expected = report.expected }
end

-- 'r' + base-36 counter + '-' + four random base-36 characters (at most 24).
local function newRunId()
    runSeq = runSeq + 1
    local head, n = '', runSeq
    repeat
        head = ID_CHARS:sub(n % 36 + 1, n % 36 + 1) .. head
        n = math.floor(n / 36)
    until n == 0
    local tail = ''
    for _ = 1, 4 do
        local d = math.random(1, 36)
        tail = tail .. ID_CHARS:sub(d, d)
    end
    return 'r' .. head .. '-' .. tail
end

-- Counts one final row and announces it with runProgress.
local function addRow(run, row)
    run.rows[#run.rows + 1] = row
    run.counts[row.state] = run.counts[row.state] + 1
    run.done = run.done + 1
    lock = ST.progress(lock, run.phase, run.done, run.total)
    TriggerEvent('aeterna_core:runProgress', run.id, row)
end

local function settle(run, item, res)
    if item.done then
        return
    end
    item.done = true
    addRow(run, {
        name = item.name, suite = item.owner, kind = item.kind, players = item.players, destructive = item.destructive,
        state = res.state, ok = res.state ~= 'FAIL', detail = res.detail or (res.state == 'FAIL' and 'failed' or 'ok'),
        ms = GetGameTimer() - (item.startMs or GetGameTimer()), step = res.step, expected = res.expected,
    })
end

-- Waits until each test in the batch is final. A test that passes its own deadline settles as a timeout.
-- A clock that does not move (no scheduler around us) ends the wait; what is still open then times out.
local function await(run, items)
    while true do
        local open, now = false, GetGameTimer()
        for _, item in ipairs(items) do
            if not item.done then
                if now >= item.deadline then
                    settle(run, item, judge(item, { timeout = true }))
                else
                    open = true
                end
            end
        end
        if not open then
            return
        end
        local before = GetGameTimer()
        Wait(50)
        if GetGameTimer() == before then
            break
        end
    end
    for _, item in ipairs(items) do
        if not item.done then
            settle(run, item, judge(item, { timeout = true }))
        end
    end
end

-- Server-side judging of one report: a 0.1 ok (true/false), a 0.2 state string, or the extras. 'ready' is client-only.
local function reportSelftestInternal(invoker, runId, name, ok, detail, extra)
    if type(runId) ~= 'string' or type(name) ~= 'string' or ok == 'ready' then
        return false
    end
    local run = activeRuns[runId]
    if not run then
        return false
    end

    local entry = run.byName[name]
    if not entry and invoker then
        entry = run.byName[normalizeTestName(invoker, name)]
    end
    if not entry or entry.done then
        return false
    end
    if invoker and invoker ~= '' and invoker ~= GetCurrentResourceName() and invoker ~= entry.owner then
        return false
    end

    local e = type(extra) == 'table' and extra or {}
    local text = type(detail) == 'string' and AeternaCore.text.clean(detail, 300) or nil
    settle(run, entry, judge(entry, {
        ok = ok, detail = text, restored = e.restored, wrote = e.wrote,
        step = (type(e.step) == 'number' and e.step >= 1 and e.step <= 99) and e.step or nil,
        expected = type(e.expected) == 'string' and AeternaCore.text.clean(e.expected, 80) or nil,
    }))
    return true
end

-- Decides a test before it fires: skipWhen, the destructive gate, then the GAPs for a missing B and a missing person.
local function preJudge(test, gateOpen, gateReason)
    local why = ST.skipFor(test, GetResourceState)
    if why then return { ok = 'skip', detail = why } end
    if test.destructive and not gateOpen then return { ok = 'skip', detail = gateReason } end
    if test.kind == 'eye' and (test.expect or ''):match('^%s*$') then return {} end
    if test.players == 2 then return { gap = 'needs player B' } end
    if test.side == 'client' then return { gap = 'needs a person' } end
    return nil
end

-- Takes the run lock and records the run, then pre-judges the tests that need no play.
-- Returns the run, or nil and the lock that is held.
local function beginRun(by, starter)
    if lock ~= nil then
        return nil, lock
    end
    local now = GetGameTimer()
    local run = {
        id = newRunId(), starter = starter, startMs = now, phase = 'starting', items = {}, byName = {}, rows = {},
        done = 0, total = 0, counts = { PASS = 0, FAIL = 0, SKIP = 0, GAP = 0, MOCK = 0, MISSING = 0 },
    }
    lock = ST.acquire(nil, run.id, by == 0 and 'console' or 'resource', starter, now)
    run.gateOpen, run.gateReason = ST.gate(GetConvar('aeterna_core_allow_destructive', 'false'), GetConvar('sv_master1', '<unset>'))
    activeRuns[run.id] = run
    for i = 1, #registeredTests do
        local item = { name = registeredTests[i].name, owner = registeredTests[i].owner }
        for k, v in pairs(registeredTests[i].test) do item[k] = v end
        run.items[#run.items + 1] = item
        run.byName[item.name] = item
    end
    run.total = #run.items
    lock = ST.progress(lock, 'starting', 0, run.total)
    for _, item in ipairs(run.items) do
        local pre = preJudge(item, run.gateOpen, run.gateReason)
        if pre then
            settle(run, item, judge(item, pre))
        end
    end
    return run
end

-- Phases in order (headless together, then mocks one at a time). Frees the lock, emits runDone.
local function drive(run)
    for _, group in ipairs(ST.order(run.items)) do
        run.phase = group.phase
        local batch = {}
        for _, item in ipairs(group.tests) do
            if not item.done then
                item.startMs = GetGameTimer()
                item.deadline = item.startMs + item.timeout
                TriggerEvent('aeterna_core:selftest', run.id, item.name,
                    { kind = item.kind, side = 'server', destructive = item.destructive })
                if group.phase == 'headless' then
                    batch[#batch + 1] = item
                else
                    await(run, { item })
                end
            end
        end
        await(run, batch)
    end
    lock = ST.release(lock, run.id)
    activeRuns[run.id] = nil
    local c = run.counts
    TriggerEvent('aeterna_core:runDone', run.id, {
        counts = c, ok = c.FAIL == 0, ms = GetGameTimer() - run.startMs, destructive = run.gateOpen and 'on' or 'off',
    })
end

-- The synchronous run behind runSelftests and the console command. A held lock gives the busy row.
local function executeSelftests()
    local run, held = beginRun(0, nil)
    if not run then
        return { { name = 'aeterna_core.lock', ok = false, state = 'FAIL', detail = ST.busyReason(held, GetGameTimer()) } }
    end
    drive(run)
    return run.rows
end

local function declareNoneInternal(owner, reason)
    if type(reason) ~= 'string' or AeternaCore.text.len(reason) > 120 then
        return false
    end
    local clean = AeternaCore.text.clean(reason, 120)
    if clean == '' then
        return false
    end
    noneReasons[owner] = clean
    return true
end

local function listInternal()
    local out = {}
    for i = 1, #registeredTests do
        local r = { name = registeredTests[i].name, owner = registeredTests[i].owner }
        for k, v in pairs(registeredTests[i].test) do r[k] = v end
        out[#out + 1] = r
    end
    for owner, reason in pairs(noneReasons) do
        out[#out + 1] = { name = owner, owner = owner, noTests = reason }
    end
    return out
end

exports('addSelftest', function(name, meta)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    return addSelftestInternal(owner, name, meta)
end)

exports('declareNoSelftests', function(reason)
    return declareNoneInternal(GetInvokingResource() or GetCurrentResourceName(), reason)
end)

exports('listSelftests', listInternal)

exports('reportSelftest', function(runId, name, ok, detail, extra)
    local invoker = GetInvokingResource() or GetCurrentResourceName()
    return reportSelftestInternal(invoker, runId, name, ok, detail, extra)
end)

exports('runSelftests', function()
    return executeSelftests()
end)

-- A run starts at once and reports by event (runProgress, runDone). The starter is the invoking resource.
exports('startRun', function(opts)
    if type(opts) ~= 'table' or type(opts.by) ~= 'number' or opts.by < 0 then
        return nil, 'opts: type'
    end
    local run, held = beginRun(opts.by, GetInvokingResource() or GetCurrentResourceName())
    if not run then
        return nil, ST.busy(held, GetGameTimer())
    end
    CreateThread(function() drive(run) end)
    return run.id
end)

exports('runStatus', function(runId)
    local run = activeRuns[runId]
    if not run then
        return nil
    end
    return { runId = run.id, phase = run.phase, done = run.done, total = run.total, counts = run.counts, rows = run.rows }
end)

exports('busy', function()
    return ST.busy(lock, GetGameTimer())
end)

AddEventHandler('aeterna_core:selftest:report', function(owner, runId, name, ok, detail, extra)
    if type(owner) == 'string' and owner == GetInvokingResource() then
        reportSelftestInternal(owner, runId, name, ok, detail, extra)
    end
end)

-- Built-in self-test for aeterna_core itself.
addSelftestInternal(GetCurrentResourceName(), 'core')

AddEventHandler('aeterna_core:selftest', function(runId, name)
    local selfTestName = normalizeTestName(GetCurrentResourceName(), 'core')
    if name ~= selfTestName then
        return
    end
    local lenOk = AeternaCore.text.len('สวัสดี') == 4
    local valOk = AeternaCore.validate({ id = 'ok_1' }, {
        type = 'table',
        fields = { id = { type = 'string', maxLen = 16, pattern = '^[%w_]+$' } },
    })
    local ok = lenOk and valOk
    reportSelftestInternal(GetCurrentResourceName(), runId, selfTestName, ok, ok and 'ok' or 'core check failed')
end)

-- Server-local registration for resources without an export edge (owner must be the invoking resource).
AddEventHandler('aeterna_core:selftest:add', function(owner, name, meta)
    if type(owner) == 'string' and owner == GetInvokingResource() then
        addSelftestInternal(owner, name, meta)
    end
end)

AddEventHandler('aeterna_core:selftest:none', function(owner, reason)
    if type(owner) == 'string' and owner == GetInvokingResource() then
        declareNoneInternal(owner, reason)
    end
end)

AddEventHandler('onResourceStop', function(stoppedResource)
    if not stoppedResource then
        return
    end
    noneReasons[stoppedResource] = nil
    for i = #registeredTests, 1, -1 do
        if registeredTests[i].owner == stoppedResource then
            table.remove(registeredTests, i)
        end
    end
end)

RegisterCommand('aeterna_core_selftest', function(src)
    if src ~= 0 then
        return
    end
    local results = executeSelftests()
    local passed = 0
    for i = 1, #results do
        local r = results[i]
        if r.ok then
            passed = passed + 1
        end
        if r.state == 'PASS' then
            print(AeternaCore.t('core.selftest.pass', {
                name = r.name,
                ms = r.ms,
            }))
        elseif r.state == 'FAIL' then
            print(AeternaCore.t('core.selftest.fail', {
                name = r.name,
                ms = r.ms,
                detail = r.detail or 'failed',
            }))
        else
            print(string.format('%s %s %s ms %s', r.state, r.name, tostring(r.ms), tostring(r.detail)))
        end
    end
    print(AeternaCore.t('core.selftest.total', {
        passed = passed,
        total = #results,
    }))
end, false)

-- Core is ready: resources with an optional edge register again on this event.
TriggerEvent('aeterna_core:hello')
