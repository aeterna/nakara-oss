-- Pure self-test rules for aeterna_core 0.2: field checks, result states, merge, phase order, skips, gate,
-- run lock and MISSING rows. No natives.

AeternaCoreLogic = AeternaCoreLogic or {}

local M = {}

local KINDS = { headless = true, ped = true, eye = true, mock = true }
local SIDES = { server = true, client = true }
local FIELDS = { kind = true, side = true, players = true, destructive = true, expect = true, ask = true, timeout = true, skipWhen = true }
local RANK = { FAIL = 1, GAP = 2, SKIP = 3, MOCK = 4, PASS = 5 }
local PHASES = { 'headless', 'mock', 'client', 'pair' }

local function default(v, d)
    if v == nil then return d end
    return v
end

local function blank(s)
    return s == nil or s:match('^%s*$') ~= nil
end

local function tooLong(s, max)
    return (utf8.len(s) or #s) > max
end

-- Validates a self-test meta table. Returns fields, nil, warn  or  nil, '<field>: <rule>'.
function M.normalize(opts)
    opts = default(opts, {})
    if type(opts) ~= 'table' then return nil, 'meta: type' end
    for k in pairs(opts) do
        if not FIELDS[k] then return nil, tostring(k) .. ': unknown field' end
    end
    local kind = default(opts.kind, 'headless')
    if not KINDS[kind] then return nil, 'kind: enum' end
    local clientOnly = kind == 'ped' or kind == 'eye'
    local side = default(opts.side, clientOnly and 'client' or 'server')
    if not SIDES[side] or (clientOnly and side ~= 'client') then return nil, 'side: enum' end
    local players = default(opts.players, 1)
    if players ~= 1 and players ~= 2 then return nil, 'players: enum' end
    local destructive = default(opts.destructive, false)
    if type(destructive) ~= 'boolean' then return nil, 'destructive: type' end
    for _, f in ipairs({ { 'expect', 240 }, { 'ask', 160 } }) do
        local v = opts[f[1]]
        if v ~= nil and type(v) ~= 'string' then return nil, f[1] .. ': type' end
        if v ~= nil and tooLong(v, f[2]) then return nil, f[1] .. ': maxLen ' .. f[2] end
    end
    local timeout = default(opts.timeout, 5000)
    if type(timeout) ~= 'number' then return nil, 'timeout: type' end
    if timeout ~= math.floor(timeout) then return nil, 'timeout: integer' end
    local clamped = math.min(math.max(timeout, 500), 60000)
    local warn = nil
    if clamped ~= timeout then warn = 'timeout: clamped to ' .. clamped end
    local sw = opts.skipWhen
    if sw ~= nil then
        if type(sw) ~= 'table' then return nil, 'skipWhen: type' end
        for k in pairs(sw) do
            if k ~= 'resources' then return nil, 'skipWhen: unknown field' end
        end
        local list = sw.resources
        if type(list) ~= 'table' then return nil, 'skipWhen: type' end
        if #list > 8 then return nil, 'skipWhen: maxItems 8' end
        for _, r in ipairs(list) do
            if type(r) ~= 'string' then return nil, 'skipWhen: type' end
            if #r > 64 then return nil, 'skipWhen: maxLen 64' end
        end
    end
    return {
        kind = kind, side = side, players = players, destructive = destructive, expect = opts.expect,
        ask = opts.ask, timeout = clamped, skipWhen = sw,
    }, nil, warn
end

-- 'needs <name>' for the first listed resource that is not started, else nil. stateOf(name) = GetResourceState.
function M.skipFor(test, stateOf)
    local sw = test.skipWhen
    if type(sw) ~= 'table' then return nil end
    for _, r in ipairs(sw.resources or {}) do
        if stateOf(r) ~= 'started' then return 'needs ' .. r end
    end
    return nil
end

-- Judges one result. report: { ok, detail, restored, wrote, guard, timeout, stopped, answer, gap }.
-- Returns state, reason.
function M.fold(test, report)
    if type(report) ~= 'table' then return 'FAIL', 'no result' end
    local mock = test.kind == 'mock'
    if test.kind == 'eye' and blank(test.expect) then return 'FAIL', 'expect is empty' end
    if report.timeout then return 'FAIL', mock and 'timeout, state may not be restored' or 'timeout' end
    if report.stopped then return 'FAIL', 'owner stopped' end
    if (report.wrote or report.guard) and test.destructive ~= true then return 'FAIL', 'undeclared destructive' end
    if report.answer == 'pass' then return 'PASS', report.detail end
    if report.answer == 'mismatch' then return 'FAIL', 'tester saw something else' end
    if report.answer == 'skip' then return 'GAP', 'skipped by the tester' end
    if report.gap then return 'GAP', report.gap end
    local ok = report.ok
    if ok == 'skip' then
        if blank(report.detail) then return 'FAIL', 'skip needs a reason' end
        return 'SKIP', report.detail
    end
    if ok == false or ok == 'fail' then return 'FAIL', default(report.detail, 'failed') end
    if ok == true or ok == 'pass' or ok == 'mock' then
        if not mock then return 'PASS', report.detail end
        if report.restored ~= true then return 'FAIL', 'state not restored' end
        return 'MOCK', report.detail
    end
    return 'FAIL', 'no result'
end

-- Worst of two two-player results: FAIL, GAP, SKIP, MOCK, PASS.
function M.merge(a, b)
    if RANK[a] == nil or RANK[b] == nil then return nil, 'state: enum' end
    if RANK[a] <= RANK[b] then return a end
    return b
end

local function phaseOf(t)
    if t.players == 2 then return 'pair' end
    if t.side == 'client' or t.kind == 'ped' or t.kind == 'eye' then return 'client' end
    if t.kind == 'mock' then return 'mock' end
    return 'headless'
end

-- Groups tests into run phases, keeping registration order inside each group. Empty phases are dropped.
function M.order(tests)
    local groups = {}
    for _, p in ipairs(PHASES) do groups[p] = { phase = p, tests = {} } end
    for _, t in ipairs(tests or {}) do
        local g = groups[phaseOf(t)].tests
        g[#g + 1] = t
    end
    local out = {}
    for _, p in ipairs(PHASES) do
        if #groups[p].tests > 0 then out[#out + 1] = groups[p] end
    end
    return out
end

-- Destructive gate. allowDestructive is the convar string; svMaster1 is the convar, nil when unset.
-- Unset counts as listed; only the explicit empty string is private.
function M.gate(allowDestructive, svMaster1)
    if allowDestructive ~= 'true' then return false, 'destructive tests are off' end
    if svMaster1 ~= '' then return false, 'server is listed publicly' end
    return true, nil
end

-- Run lock as a plain table { runId, by = 'console'|'resource', starter, startedAt, phase, done, total }.
-- acquire returns the new lock, or nil and the held lock when busy. No player names are stored.
function M.acquire(lock, runId, by, starter, now)
    if lock ~= nil then return nil, lock end
    return { runId = runId, by = by, starter = starter, startedAt = now, phase = 'starting', done = 0, total = 0 }
end

-- Frees the lock only for its own run. Returns nil, true when freed, else lock, false.
function M.release(lock, runId)
    if lock ~= nil and lock.runId == runId then return nil, true end
    return lock, false
end

function M.progress(lock, phase, done, total)
    if lock == nil then return nil end
    local c = {}
    for k, v in pairs(lock) do c[k] = v end
    c.phase, c.done, c.total = phase, done, total
    return c
end

-- The busy() row without the run id. since = whole seconds held.
function M.busy(lock, now)
    if lock == nil then return nil end
    return {
        by = lock.by, starter = lock.starter, since = math.floor(now - lock.startedAt),
        phase = lock.phase, done = lock.done, total = lock.total,
    }
end

function M.busyReason(lock, now)
    local b = M.busy(lock, now)
    if b == nil then return nil end
    return string.format('busy: %s since %d s', b.phase, b.since)
end

-- MISSING rows for started aeterna_* resources with no test. declaredNone maps resource -> reason and gives
-- one SKIP row instead. aeterna_core is never reported.
function M.missing(startedResources, registered, declaredNone)
    registered, declaredNone = default(registered, {}), default(declaredNone, {})
    local rows = {}
    for _, res in ipairs(startedResources or {}) do
        if res ~= 'aeterna_core' and res:sub(1, 8) == 'aeterna_' then
            if declaredNone[res] ~= nil then
                rows[#rows + 1] = { name = res, owner = res, state = 'SKIP', ok = true, detail = declaredNone[res] }
            elseif not registered[res] then
                rows[#rows + 1] = { name = res, owner = res, state = 'MISSING', ok = false, detail = 'no self-test registered' }
            end
        end
    end
    return rows
end

AeternaCoreLogic.selftest = M
return M
