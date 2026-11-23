-- selftest_spec.lua -- busted tests for the 0.2 self-test rules in shared/logic/selftest.lua: field checks,
-- result states, two-player merge, phase order, skip conditions, destructive gate, run lock, MISSING rows.
-- Pure Lua, no natives.

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local st = assert(loadfile(HERE .. '/../shared/logic/selftest.lua'))()

local function rule(opts) return select(2, st.normalize(opts)) end
local function names(list)
    local out = {}
    for i, t in ipairs(list) do out[i] = t.name end
    return out
end
local function T(name, kind, side, players)
    return { name = name, kind = kind, side = side, players = players or 1 }
end

describe('self-test fields (normalize)', function()
    it('applies the defaults; ped and eye default to the client side', function()
        assert.are.same({ kind = 'headless', side = 'server', players = 1, destructive = false, timeout = 5000 },
            (st.normalize(nil)))
        assert.are.equal('client', st.normalize({ kind = 'ped' }).side)
        assert.are.equal('client', st.normalize({ kind = 'eye' }).side)
    end)

    it('refuses bad enums, types and unknown fields by name', function()
        assert.are.equal('kind: enum', rule({ kind = 'video' }))
        assert.are.equal('side: enum', rule({ side = 'nowhere' }))
        assert.are.equal('side: enum', rule({ kind = 'ped', side = 'server' }))
        assert.are.equal('side: enum', rule({ kind = 'eye', side = 'server' }))
        assert.are.equal('players: enum', rule({ players = 3 }))
        assert.are.equal('destructive: type', rule({ destructive = 'yes' }))
        assert.are.equal('colour: unknown field', rule({ colour = 'red' }))
        assert.are.equal('meta: type', rule('headless'))
    end)

    it('caps expect at 240 and ask at 160 characters', function()
        assert.is_nil(rule({ expect = string.rep('a', 240) }))
        assert.are.equal('expect: maxLen 240', rule({ expect = string.rep('a', 241) }))
        assert.are.equal('ask: maxLen 160', rule({ ask = string.rep('a', 161) }))
    end)

    it('clamps timeout to 500..60000 with one warning; rejects non-integers', function()
        local f, _, warn = st.normalize({ timeout = 90000 })
        assert.are.equal(60000, f.timeout)
        assert.is_string(warn)
        assert.are.equal(500, (st.normalize({ timeout = 100 })).timeout)
        assert.is_nil(select(3, st.normalize({ timeout = 1000 })))
        assert.are.equal('timeout: type', rule({ timeout = 'soon' }))
        assert.are.equal('timeout: integer', rule({ timeout = 1.5 }))
    end)

    it('accepts an empty eye expect (fold judges it, normalize does not refuse it)', function()
        assert.are.equal('', st.normalize({ kind = 'eye', expect = '' }).expect)
    end)

    it('checks skipWhen: type, at most 8 names, at most 64 characters each', function()
        assert.are.same({ 'pma-voice' }, st.normalize({ skipWhen = { resources = { 'pma-voice' } } }).skipWhen.resources)
        assert.are.equal('skipWhen: type', rule({ skipWhen = 'pma-voice' }))
        local nine = {}
        for i = 1, 9 do nine[i] = 'r' .. i end
        assert.are.equal('skipWhen: maxItems 8', rule({ skipWhen = { resources = nine } }))
        assert.are.equal('skipWhen: maxLen 64', rule({ skipWhen = { resources = { string.rep('a', 65) } } }))
    end)
end)

describe('result states (fold)', function()
    it('folds passes, fails and a missing report', function()
        assert.are.equal('PASS', (st.fold({ kind = 'headless' }, { ok = true })))
        assert.are.same({ 'FAIL', 'step 3' }, { st.fold({ kind = 'headless' }, { ok = false, detail = 'step 3' }) })
        assert.are.equal('FAIL', (st.fold({ kind = 'headless' }, nil)))
    end)

    it('keeps a SKIP with a reason and fails a SKIP without one', function()
        assert.are.same({ 'SKIP', 'needs pma-voice' }, { st.fold({ kind = 'headless' }, { ok = 'skip', detail = 'needs pma-voice' }) })
        assert.are.same({ 'FAIL', 'skip needs a reason' }, { st.fold({ kind = 'headless' }, { ok = 'skip', detail = '  ' }) })
    end)

    it('judges mocks: restored is MOCK, otherwise FAIL; a timeout says so', function()
        assert.are.equal('MOCK', (st.fold({ kind = 'mock' }, { ok = 'mock', restored = true })))
        assert.are.same({ 'FAIL', 'state not restored' }, { st.fold({ kind = 'mock' }, { ok = true }) })
        assert.are.same({ 'FAIL', 'timeout, state may not be restored' }, { st.fold({ kind = 'mock' }, { timeout = true }) })
        assert.are.same({ 'FAIL', 'timeout' }, { st.fold({ kind = 'headless' }, { timeout = true }) })
    end)

    it('fails an undeclared destructive write and accepts a declared one', function()
        assert.are.same({ 'FAIL', 'undeclared destructive' }, { st.fold({ kind = 'headless' }, { ok = true, wrote = true }) })
        assert.are.equal('FAIL', (st.fold({ kind = 'headless' }, { ok = true, guard = true })))
        assert.are.equal('PASS', (st.fold({ kind = 'headless', destructive = true }, { ok = true, wrote = true })))
    end)

    it('fails when the owner stopped mid-test', function()
        assert.are.same({ 'FAIL', 'owner stopped' }, { st.fold({ kind = 'headless' }, { stopped = true }) })
    end)

    it('judges eye tests: an empty expect fails, answers map to PASS, FAIL or GAP', function()
        assert.are.same({ 'FAIL', 'expect is empty' }, { st.fold({ kind = 'eye', expect = '' }, { ok = true, answer = 'pass' }) })
        assert.are.equal('PASS', (st.fold({ kind = 'eye', expect = 'x' }, { answer = 'pass' })))
        assert.are.equal('FAIL', (st.fold({ kind = 'eye', expect = 'x' }, { answer = 'mismatch' })))
        assert.are.same({ 'GAP', 'skipped by the tester' }, { st.fold({ kind = 'eye', expect = 'x' }, { answer = 'skip' }) })
    end)

    it('folds a gap reason to GAP', function()
        assert.are.same({ 'GAP', 'needs a person' }, { st.fold({ kind = 'ped' }, { gap = 'needs a person' }) })
    end)
end)

describe('two-player merge', function()
    it('takes the worst state and refuses an unknown one', function()
        assert.are.equal('GAP', st.merge('PASS', 'GAP'))
        assert.are.equal('FAIL', st.merge('MOCK', 'FAIL'))
        assert.are.equal('PASS', st.merge('PASS', 'PASS'))
        assert.are.equal('GAP', st.merge('GAP', 'PASS'))
        assert.are.same({ nil, 'state: enum' }, { st.merge('PASS', 'video') })
    end)
end)

describe('phase order', function()
    it('runs headless, mock, client, then two-player rows, each in registration order', function()
        local groups = st.order({
            T('h1', 'headless', 'server'), T('m1', 'mock', 'server'), T('c1', 'headless', 'client'),
            T('p1', 'ped', 'client'), T('pair', 'headless', 'server', 2), T('h2', 'headless', 'server'),
            T('e1', 'eye', 'client'), T('m2', 'mock', 'server'), T('cm', 'mock', 'client'),
        })
        local got = {}
        for _, g in ipairs(groups) do got[#got + 1] = g.phase .. ':' .. table.concat(names(g.tests), ',') end
        assert.are.same({ 'headless:h1,h2', 'mock:m1,m2', 'client:c1,p1,e1,cm', 'pair:pair' }, got)
        assert.are.same({}, st.order({}))
    end)
end)

describe('skip conditions and destructive gate', function()
    it('skipFor names the first listed resource that is not started', function()
        local test = st.normalize({ skipWhen = { resources = { 'pma-voice' } } })
        assert.are.equal('needs pma-voice', st.skipFor(test, function() return 'missing' end))
        assert.is_nil(st.skipFor(test, function() return 'started' end))
    end)

    it('gate opens only for the string true with an explicit empty sv_master1', function()
        assert.are.same({ true }, { st.gate('true', '') })
        assert.are.same({ false, 'server is listed publicly' }, { st.gate('true', nil) })
        assert.are.same({ false, 'server is listed publicly' }, { st.gate('true', '<unset>') })
        assert.are.same({ false, 'destructive tests are off' }, { st.gate('false', '') })
    end)
end)

describe('run lock (pure state)', function()
    it('refuses a second run with the starter and no player name, and frees only for its own run', function()
        local lock = st.acquire(nil, 'r1-aaaa', 'resource', 'aeterna_testkit', 100)
        local again, held = st.acquire(lock, 'r2-bbbb', 'console', 'console', 105)
        assert.is_nil(again)
        assert.are.equal(lock, held)
        assert.are.same({ by = 'resource', starter = 'aeterna_testkit', since = 5, phase = 'starting', done = 0, total = 0 },
            st.busy(held, 105))
        assert.are.equal('busy: starting since 5 s', st.busyReason(held, 105))
        local same, released = st.release(held, 'r9-zzzz')
        assert.are.equal(lock, same)
        assert.is_false(released)
        local none, freed = st.release(held, 'r1-aaaa')
        assert.is_nil(none)
        assert.is_true(freed)
        assert.is_table(st.acquire(none, 'r2-bbbb', 'console', 'console', 200))
    end)

    it('shows the phase reached in the busy reason', function()
        local lock = st.progress(st.acquire(nil, 'r1-aaaa', 'console', 'console', 100), 'mock', 2, 7)
        assert.are.equal('busy: mock since 4 s', st.busyReason(lock, 104))
        assert.is_nil(st.busy(nil, 104))
    end)
end)

describe('MISSING rows', function()
    it('marks an unregistered aeterna_ resource MISSING, and never aeterna_core', function()
        local rows = st.missing({ 'aeterna_demo', 'qbx_core', 'aeterna_core' }, {}, {})
        assert.are.equal(1, #rows)
        assert.are.equal('aeterna_demo', rows[1].name)
        assert.are.equal('MISSING', rows[1].state)
        assert.is_false(rows[1].ok)
    end)

    it('leaves a registered resource alone and turns a declared one into one SKIP row', function()
        assert.are.same({}, st.missing({ 'aeterna_demo' }, { aeterna_demo = true }, {}))
        local rows = st.missing({ 'aeterna_demo' }, {}, { aeterna_demo = 'owner tool' })
        assert.are.equal(1, #rows)
        assert.are.equal('SKIP', rows[1].state)
        assert.are.equal('owner tool', rows[1].detail)
    end)
end)

describe('client test started and the write guard (cases 17 and 18)', function()
    it('17. sends ped, eye, side = client and two-player tests to clients, and builds the started ctx', function()
        assert.is_true(st.toClients(T('p', 'ped', 'client')))
        assert.is_true(st.toClients(T('e', 'eye', 'client')))
        assert.is_true(st.toClients(T('h', 'headless', 'client')))
        assert.is_true(st.toClients(T('pair', 'headless', 'server', 2)))
        assert.is_false(st.toClients(T('h', 'headless', 'server')))
        assert.is_false(st.toClients(T('m', 'mock', 'server')))

        local pair = { kind = 'ped', side = 'client', players = 2, destructive = true }
        assert.are.same({ kind = 'ped', side = 'client', a = 1, b = 2, destructive = true }, st.startedCtx(pair, 1, 2))
        local solo = { kind = 'eye', side = 'client', players = 1, destructive = false }
        assert.are.same({ kind = 'eye', side = 'client', a = 1, destructive = false }, st.startedCtx(solo, 1, 2))
    end)

    it('18. allows a write only for an in-flight destructive test with the gate open', function()
        local wipe = { destructive = true, fired = true }
        assert.are.same({ true }, { st.mayWrite(wipe, true) })
        assert.are.same({ false }, { st.mayWrite(wipe, false) })
    end)

    it('18. refuses an in-flight test that is not destructive and names the failure', function()
        assert.are.same({ false, 'undeclared destructive' }, { st.mayWrite({ destructive = false, fired = true }, true) })
    end)

    it('18. refuses an unknown test, one not fired yet and one that already ended, with no failure', function()
        assert.are.same({ false }, { st.mayWrite(nil, true) })
        assert.are.same({ false }, { st.mayWrite({ destructive = false }, true) })
        assert.are.same({ false }, { st.mayWrite({ destructive = false, fired = true, done = true }, true) })
    end)
end)
