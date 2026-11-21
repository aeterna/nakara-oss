-- aeterna_core server: self-test registry, runner and aeterna_core_selftest command.

AeternaCoreLogic = AeternaCoreLogic or {}
AeternaCore = AeternaCore or {}

local SELFTEST_TIMEOUT_MS = 5000
local ST = AeternaCoreLogic.selftest

local registeredTests = {}
local noneReasons = {}
local activeRuns = {}
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

local function reportSelftestInternal(invoker, runId, name, ok, detail)
    if type(runId) ~= 'string' or type(name) ~= 'string' then
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

    local elapsed = math.max(0, GetGameTimer() - entry.startMs)
    entry.done = true
    entry.ok = (ok == true)
    entry.state = entry.ok and 'PASS' or 'FAIL'
    entry.detail = detail ~= nil and tostring(detail) or (entry.ok and 'ok' or 'failed')
    entry.ms = elapsed
    run.remaining = run.remaining - 1
    return true
end

-- Decides a test before it fires: skipWhen, the destructive gate, then the GAPs for a missing B and a missing person.
local function preJudge(test, gateOpen, gateReason)
    local why = ST.skipFor(test, GetResourceState)
    if why then return { ok = 'skip', detail = why } end
    if test.destructive and not gateOpen then return { ok = 'skip', detail = gateReason } end
    if test.players == 2 then return { gap = 'needs player B' } end
    if test.side == 'client' then return { gap = 'needs a person' } end
    return nil
end

local function executeSelftests()
    runSeq = runSeq + 1
    local runId = 'run_' .. tostring(runSeq)
    local startMs = GetGameTimer()
    local gateOpen, gateReason = ST.gate(GetConvar('aeterna_core_allow_destructive', 'false'), GetConvar('sv_master1', '<unset>'))

    local list = {}
    local byName = {}
    local open = 0
    for i = 1, #registeredTests do
        local t = registeredTests[i]
        local item = {
            name = t.name,
            owner = t.owner,
            test = t.test,
            startMs = startMs,
            done = false,
            ok = false,
            detail = 'timeout',
            ms = 0,
        }
        list[#list + 1] = item
        byName[t.name] = item
        local pre = preJudge(t.test, gateOpen, gateReason)
        if pre then
            item.done = true
            item.state, item.detail = ST.fold(t.test, pre)
            item.ok = item.state ~= 'FAIL'
        else
            open = open + 1
        end
    end

    local run = {
        id = runId,
        byName = byName,
        remaining = open,
    }
    activeRuns[runId] = run

    for i = 1, #list do
        local item = list[i]
        if not item.done then
            item.startMs = GetGameTimer()
            TriggerEvent('aeterna_core:selftest', runId, item.name,
                { kind = item.test.kind, side = 'server', destructive = item.test.destructive })
        end
    end

    local guardSteps = 0
    while run.remaining > 0 and (GetGameTimer() - startMs) < SELFTEST_TIMEOUT_MS and guardSteps < 100 do
        local beforeWait = GetGameTimer()
        Wait(50)
        guardSteps = guardSteps + 1
        if GetGameTimer() == beforeWait then
            break
        end
    end

    local endMs = GetGameTimer()
    local results = {}
    for i = 1, #list do
        local item = list[i]
        if not item.done then
            item.ms = math.max(0, endMs - item.startMs)
            item.ok = false
            item.state = 'FAIL'
            item.detail = 'timeout'
        end
        results[#results + 1] = {
            name = item.name,
            ok = item.ok,
            state = item.state,
            detail = item.detail,
            ms = item.ms,
            kind = item.test.kind,
            players = item.test.players,
            destructive = item.test.destructive,
        }
    end

    activeRuns[runId] = nil
    return results
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

exports('reportSelftest', function(runId, name, ok, detail)
    local invoker = GetInvokingResource() or GetCurrentResourceName()
    return reportSelftestInternal(invoker, runId, name, ok, detail)
end)

exports('runSelftests', function()
    return executeSelftests()
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
