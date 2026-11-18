-- aeterna_core server: self-test registry, runner and aeterna_core_selftest command.

AeternaCoreLogic = AeternaCoreLogic or {}
AeternaCore = AeternaCore or {}

local SELFTEST_TIMEOUT_MS = 5000

local registeredTests = {}
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

local function addSelftestInternal(owner, name)
    if type(name) ~= 'string' or name == '' then
        return nil
    end
    local resOwner = tostring(owner or GetCurrentResourceName() or 'aeterna_core')
    local fullName = normalizeTestName(resOwner, name)
    for i = 1, #registeredTests do
        if registeredTests[i].name == fullName then
            registeredTests[i].owner = resOwner
            return fullName
        end
    end
    registeredTests[#registeredTests + 1] = {
        name = fullName,
        owner = resOwner,
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
    entry.detail = detail ~= nil and tostring(detail) or (entry.ok and 'ok' or 'failed')
    entry.ms = elapsed
    run.remaining = run.remaining - 1
    return true
end

local function executeSelftests()
    runSeq = runSeq + 1
    local runId = 'run_' .. tostring(runSeq)
    local startMs = GetGameTimer()

    local list = {}
    local byName = {}
    for i = 1, #registeredTests do
        local t = registeredTests[i]
        local item = {
            name = t.name,
            owner = t.owner,
            startMs = startMs,
            done = false,
            ok = false,
            detail = 'timeout',
            ms = 0,
        }
        list[#list + 1] = item
        byName[t.name] = item
    end

    local run = {
        id = runId,
        byName = byName,
        remaining = #list,
    }
    activeRuns[runId] = run

    for i = 1, #list do
        local item = list[i]
        item.startMs = GetGameTimer()
        TriggerEvent('aeterna_core:selftest', runId, item.name)
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
            item.detail = 'timeout'
        end
        results[#results + 1] = {
            name = item.name,
            ok = item.ok,
            detail = item.detail,
            ms = item.ms,
        }
    end

    activeRuns[runId] = nil
    return results
end

exports('addSelftest', function(name)
    local owner = GetInvokingResource() or GetCurrentResourceName()
    return addSelftestInternal(owner, name)
end)

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

AddEventHandler('onResourceStop', function(stoppedResource)
    if not stoppedResource then
        return
    end
    for i = #registeredTests, 1, -1 do
        if registeredTests[i].owner == stoppedResource then
            table.remove(registeredTests, i)
        end
    end
end)

RegisterCommand('aeterna_core_selftest', function(src)
    if not AeternaCore.can(src, 'aeterna.core.selftest') then
        return
    end
    local results = executeSelftests()
    local passed = 0
    for i = 1, #results do
        local r = results[i]
        if r.ok then
            passed = passed + 1
            print(AeternaCore.t('core.selftest.pass', {
                name = r.name,
                ms = r.ms,
            }))
        else
            print(AeternaCore.t('core.selftest.fail', {
                name = r.name,
                ms = r.ms,
                detail = r.detail or 'failed',
            }))
        end
    end
    print(AeternaCore.t('core.selftest.total', {
        passed = passed,
        total = #results,
    }))
end, false)
