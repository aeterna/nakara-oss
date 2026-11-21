-- selftest_server_spec.lua -- busted tests for the 0.2 server side of aeterna_core's self-tests (registry part):
-- addSelftest meta, declareNoSelftests, listSelftests, the server-local registration events, hello and the
-- console command (source 0 only). Stubs only the FiveM runtime; the rules come from shared/logic/selftest.lua.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

-- Commands registered by the server script, by name.
local commands = {}

-- Fresh server aeterna_core (shared scripts + server/main.lua). Returns the list that collects AeternaCore.log.warn.
local function load_server(convars)
    natives.reset({ resource = 'aeterna_core', side = 'server', convars = convars })
    commands = {}
    natives.spy('RegisterCommand', function(name, fn) commands[name] = fn end)
    rawset(_G, 'AeternaCore', nil)
    resource.load_resource(DIR, 'server')
    local warns = {}
    AeternaCore.log.warn = function(msg, fields) warns[#warns + 1] = { msg = msg, fields = fields } end
    return warns
end

-- Calls made by resources invoking the exports (GetInvokingResource).
local function as(who)
    natives.stub('GetInvokingResource', function() return who end)
end

-- The listSelftests row for `name`, or nil.
local function row(name)
    for _, r in ipairs(exports.aeterna_core:listSelftests()) do
        if r.name == name then return r end
    end
    return nil
end

describe('aeterna_core server: self-test registry (0.2)', function()
    local warns
    before_each(function() warns = load_server() end)

    it('keeps the 0.1 call: addSelftest(name) gets the 0.2 defaults', function()
        assert.are.equal('aeterna_core.sample', exports.aeterna_core:addSelftest('sample'))
        local r = row('aeterna_core.sample')
        assert.are.same({ 'headless', 'server', 1, false, 5000 }, { r.kind, r.side, r.players, r.destructive, r.timeout })
        assert.are.equal(0, #warns)
    end)

    it('clamps timeout to 60000 with one warn, and refuses a bad kind by field name', function()
        exports.aeterna_core:addSelftest('slow', { timeout = 90000 })
        assert.are.equal(60000, row('aeterna_core.slow').timeout)
        assert.are.equal(1, #warns)

        local name, err = exports.aeterna_core:addSelftest('video', { kind = 'video' })
        assert.is_nil(name)
        assert.are.equal('kind: enum', err)
        assert.is_nil(row('aeterna_core.video'))
        assert.are.equal(2, #warns)
    end)

    it('makes ped tests client-side and refuses side = server', function()
        exports.aeterna_core:addSelftest('walk', { kind = 'ped' })
        assert.are.equal('client', row('aeterna_core.walk').side)
        local name, err = exports.aeterna_core:addSelftest('walk2', { kind = 'ped', side = 'server' })
        assert.is_nil(name)
        assert.are.equal('side: enum', err)
    end)

    it('declares a resource with no tests on purpose, as one row with its reason', function()
        as('aeterna_demo')
        assert.is_true(exports.aeterna_core:declareNoSelftests('owner tool'))
        assert.are.equal('owner tool', row('aeterna_demo').noTests)
        assert.is_false(exports.aeterna_core:declareNoSelftests(string.rep('a', 121)))
    end)

    it('accepts the local add and none events only from the owner that invokes them', function()
        as('aeterna_demo')
        natives.fire('aeterna_core:selftest:add', 'aeterna_demo', 'ping', { timeout = 1000 })
        assert.are.equal(1000, row('aeterna_demo.ping').timeout)

        natives.fire('aeterna_core:selftest:add', 'aeterna_other', 'spoof')
        assert.is_nil(row('aeterna_other.spoof'))
        natives.fire('aeterna_core:selftest:none', 'aeterna_other', 'not mine')
        assert.is_nil(row('aeterna_other'))

        natives.fire('aeterna_core:selftest:none', 'aeterna_demo', 'owner tool')
        assert.are.equal('owner tool', row('aeterna_demo').noTests)
    end)

    it('fires the server-local hello once when it starts', function()
        assert.are.equal(1, #natives.emitted('local', 'aeterna_core:hello'))
    end)

    it('runs the console command for source 0 only', function()
        local cmd = commands['aeterna_core_selftest']
        cmd(1)
        assert.are.equal(0, #natives.emitted('local', 'aeterna_core:selftest'))
        cmd(0)
        assert.is_true(#natives.emitted('local', 'aeterna_core:selftest') >= 1)
    end)
end)

describe('aeterna_core server: gates in a console run (0.2)', function()
    before_each(function() load_server() end)

    -- { state, detail } of the console-run row for `name`.
    local function judged(name)
        for _, r in ipairs(exports.aeterna_core:runSelftests()) do
            if r.name == name then return { r.state, r.detail } end
        end
        return nil
    end

    it('skips a destructive test while the gate is shut, and runs it once the gate is open', function()
        exports.aeterna_core:addSelftest('wipe', { destructive = true })
        local fired = 0
        AddEventHandler('aeterna_core:selftest', function(runId, name)
            if name == 'aeterna_core.wipe' then
                fired = fired + 1
                exports.aeterna_core:reportSelftest(runId, name, true, 'ok')
            end
        end)
        assert.are.same({ 'SKIP', 'destructive tests are off' }, judged('aeterna_core.wipe'))
        assert.are.equal(0, fired)

        natives.set_convar('aeterna_core_allow_destructive', 'true')
        natives.set_convar('sv_master1', '')
        assert.are.same({ 'PASS', 'ok' }, judged('aeterna_core.wipe'))
        assert.are.equal(1, fired)
    end)

    it('skips a test whose skipWhen resource is not started', function()
        natives.stub('GetResourceState', function() return 'missing' end)
        exports.aeterna_core:addSelftest('voice', { skipWhen = { resources = { 'pma-voice' } } })
        assert.are.same({ 'SKIP', 'needs pma-voice' }, judged('aeterna_core.voice'))
    end)

    it('gives GAP to a two-player test and to a client test when nobody pressed', function()
        exports.aeterna_core:addSelftest('pair', { players = 2 })
        exports.aeterna_core:addSelftest('walk', { kind = 'ped' })
        assert.are.same({ 'GAP', 'needs player B' }, judged('aeterna_core.pair'))
        assert.are.same({ 'GAP', 'needs a person' }, judged('aeterna_core.walk'))
    end)
end)

describe('aeterna_core server: runs, phases and results (0.2)', function()
    before_each(function() load_server() end)

    -- runProgress rows named `name`, in emitted order.
    local function rowsNamed(name)
        local out = {}
        for _, e in ipairs(natives.emitted('local', 'aeterna_core:runProgress')) do
            if e.args[2].name == name then out[#out + 1] = e.args[2] end
        end
        return out
    end
    local function rowOf(name) return rowsNamed(name)[1] end

    it('holds one run at a time: busy() shows it, a second start is refused, runDone counts rows', function()
        exports.aeterna_core:addSelftest('slow', { timeout = 1000 })
        local id = exports.aeterna_core:startRun({ by = 0 })
        assert.are.equal(id, exports.aeterna_core:runStatus(id).runId)
        assert.are.equal('console', exports.aeterna_core:busy().by)
        local nope, held = exports.aeterna_core:startRun({ by = 0 })
        assert.is_nil(nope)
        assert.are.equal('console', held.by)
        local rows = exports.aeterna_core:runSelftests()
        assert.are.same({ 'aeterna_core.lock', 'FAIL' }, { rows[1].name, rows[1].state })
        natives.advance(1000)
        assert.is_nil(exports.aeterna_core:busy())
        assert.are.same({ 'FAIL', 'timeout' }, { rowOf('aeterna_core.slow').state, rowOf('aeterna_core.slow').detail })
        local done = natives.last_emitted('local', 'aeterna_core:runDone').args[2]
        assert.are.same({ 1, 1 }, { done.counts.PASS, done.counts.FAIL })
    end)

    it('fires headless tests before mocks, whatever the registration order', function()
        exports.aeterna_core:addSelftest('m', { kind = 'mock' })
        exports.aeterna_core:addSelftest('h1')
        local order = {}
        AddEventHandler('aeterna_core:selftest', function(runId, name)
            order[#order + 1] = name
            if name == 'aeterna_core.h1' then exports.aeterna_core:reportSelftest(runId, name, true, 'ok') end
            if name == 'aeterna_core.m' then exports.aeterna_core:reportSelftest(runId, name, 'mock', 'ok', { restored = true }) end
        end)
        exports.aeterna_core:startRun({ by = 0 })
        natives.advance(0)
        assert.are.same({ 'aeterna_core.core', 'aeterna_core.h1', 'aeterna_core.m' }, order)
        assert.are.equal('MOCK', rowOf('aeterna_core.m').state)
    end)

    it('gives each test its own timeout', function()
        exports.aeterna_core:addSelftest('quick', { timeout = 500 })
        exports.aeterna_core:addSelftest('long', { timeout = 3000 })
        exports.aeterna_core:startRun({ by = 0 })
        natives.advance(500)
        assert.are.same({ 'FAIL', 'timeout' }, { rowOf('aeterna_core.quick').state, rowOf('aeterna_core.quick').detail })
        assert.is_nil(rowOf('aeterna_core.long'))
        assert.is_not_nil(exports.aeterna_core:busy())
        natives.advance(2500)
        assert.are.equal('timeout', rowOf('aeterna_core.long').detail)
        assert.is_nil(exports.aeterna_core:busy())
    end)

    it('reports busy().since in whole seconds, not milliseconds', function()
        exports.aeterna_core:addSelftest('slow', { timeout = 10000 })
        exports.aeterna_core:startRun({ by = 0 })
        natives.advance(4000)
        assert.are.equal(4, exports.aeterna_core:busy().since)
    end)

    it('accepts the 0.2 states and extras from reportSelftest, and refuses ready on the server', function()
        exports.aeterna_core:addSelftest('skipper')
        exports.aeterna_core:addSelftest('step')
        exports.aeterna_core:addSelftest('mockless', { kind = 'mock' })
        exports.aeterna_core:addSelftest('ready')
        local refused
        AddEventHandler('aeterna_core:selftest', function(runId, name)
            if name == 'aeterna_core.skipper' then exports.aeterna_core:reportSelftest(runId, name, 'skip', 'needs pma-voice') end
            if name == 'aeterna_core.step' then
                exports.aeterna_core:reportSelftest(runId, name, false, 'step 3: home', { step = 3, expected = 'contacts.detail' })
            end
            if name == 'aeterna_core.mockless' then exports.aeterna_core:reportSelftest(runId, name, 'mock', 'ok') end
            if name == 'aeterna_core.ready' then refused = exports.aeterna_core:reportSelftest(runId, name, 'ready') end
        end)
        exports.aeterna_core:runSelftests()
        assert.are.same({ 'SKIP', 'needs pma-voice' }, { rowOf('aeterna_core.skipper').state, rowOf('aeterna_core.skipper').detail })
        local step = rowOf('aeterna_core.step')
        assert.are.same({ 'FAIL', 3, 'contacts.detail' }, { step.state, step.step, step.expected })
        assert.are.equal('state not restored', rowOf('aeterna_core.mockless').detail)
        assert.is_false(refused)
        assert.are.equal('timeout', rowOf('aeterna_core.ready').detail)
    end)

    it('takes a local report only from the owner that invokes it', function()
        as('aeterna_demo')
        exports.aeterna_core:addSelftest('ping')
        AddEventHandler('aeterna_core:selftest', function(runId, name)
            if name ~= 'aeterna_demo.ping' then return end
            natives.fire('aeterna_core:selftest:report', 'aeterna_other', runId, name, true, 'spoof')
            natives.fire('aeterna_core:selftest:report', 'aeterna_demo', runId, name, true, 'ok')
        end)
        exports.aeterna_core:runSelftests()
        assert.are.equal('ok', rowOf('aeterna_demo.ping').detail)
    end)
end)



describe('aeterna_core server: client tests, MISSING and cancel (0.2)', function()
    before_each(function()
        load_server()
        natives.add_player(1, 'A')
        natives.add_player(2, 'B')
        natives.add_player(3, 'C')
    end)

    local function rowOf(name)
        for _, e in ipairs(natives.emitted('local', 'aeterna_core:runProgress')) do
            if e.args[2].name == name then return e.args[2] end
        end
        return nil
    end
    -- cl:selftest events sent to `target` for `name`.
    local function sentTo(target, name, event)
        local out = {}
        for _, e in ipairs(natives.emitted('client', event or 'aeterna_core:cl:selftest')) do
            if tonumber(e.target) == target and e.args[1].name == name then out[#out + 1] = e.args[1] end
        end
        return out
    end
    local function result(src, runId, name, state, extra)
        local p = { runId = runId, name = name, state = state }
        for k, v in pairs(extra or {}) do p[k] = v end
        return natives.fire_net('aeterna_core:sv:selftestResult', src, p)
    end

    it('sends a client test to the presser and accepts its report only from that player', function()
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 2000 })
        local id = exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        local sent = sentTo(1, 'aeterna_core.walk')
        assert.are.equal(1, #sent)
        assert.are.same({ id, 'ped', 'A' }, { sent[1].runId, sent[1].kind, sent[1].role })
        result(3, id, 'aeterna_core.walk', 'pass')
        assert.is_nil(rowOf('aeterna_core.walk'))
        result(1, id, 'aeterna_core.walk', 'pass', { detail = 'walked' })
        natives.advance(50)
        assert.are.same({ 'PASS', 'walked' }, { rowOf('aeterna_core.walk').state, rowOf('aeterna_core.walk').detail })
        assert.are.equal(1, #sentTo(1, 'aeterna_core.walk', 'aeterna_core:cl:selftestEnd'))
    end)

    it('runs a two-player test on A and B and keeps the worse result', function()
        exports.aeterna_core:addSelftest('call', { kind = 'ped', players = 2, timeout = 2000 })
        local id = exports.aeterna_core:startRun({ by = 1, b = 2 })
        natives.advance(0)
        assert.are.equal('B', sentTo(2, 'aeterna_core.call')[1].role)
        result(1, id, 'aeterna_core.call', 'pass')
        result(2, id, 'aeterna_core.call', 'fail', { detail = 'no ring' })
        natives.advance(50)
        assert.are.same({ 'FAIL', 'no ring' }, { rowOf('aeterna_core.call').state, rowOf('aeterna_core.call').detail })
    end)

    it('waits for the eye answer after ready, and gives GAP when nobody answers in 120 s', function()
        exports.aeterna_core:addSelftest('look', { kind = 'eye', expect = 'A lamp', timeout = 2000 })
        exports.aeterna_core:addSelftest('stare', { kind = 'eye', expect = 'A door', timeout = 2000 })
        local id = exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        assert.are.equal('A lamp', sentTo(1, 'aeterna_core.look')[1].expect)
        result(1, id, 'aeterna_core.look', 'ready')
        natives.advance(3000)
        assert.is_nil(rowOf('aeterna_core.look'))
        natives.fire_net('aeterna_core:sv:eyeAnswer', 1, { runId = id, name = 'aeterna_core.look', answer = 'pass' })
        natives.advance(50)
        assert.are.equal('PASS', rowOf('aeterna_core.look').state)
        result(1, id, 'aeterna_core.stare', 'ready')
        natives.advance(120050)
        assert.are.same({ 'GAP', 'no answer' }, { rowOf('aeterna_core.stare').state, rowOf('aeterna_core.stare').detail })
    end)

    it('gives GAP when the player leaves while a test is in flight', function()
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 5000 })
        exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        rawset(_G, 'source', 1)
        natives.fire('playerDropped', 'quit')
        rawset(_G, 'source', nil)
        natives.advance(50)
        assert.are.same({ 'GAP', 'player left' }, { rowOf('aeterna_core.walk').state, rowOf('aeterna_core.walk').detail })
    end)

    it('adds MISSING rows for started aeterna_* resources with no tests; declared ones are SKIP; core never', function()
        local started = { 'aeterna_core', 'aeterna_demo', 'aeterna_quiet', 'ox_lib' }
        natives.stub('GetNumResources', function() return #started end)
        natives.stub('GetResourceByFindIndex', function(i) return started[i + 1] end)
        natives.stub('GetResourceState', function() return 'started' end)
        as('aeterna_quiet')
        exports.aeterna_core:declareNoSelftests('owner tool')
        local rows = exports.aeterna_core:runSelftests()
        local byName = {}
        for _, r in ipairs(rows) do byName[r.name] = r end
        assert.are.equal('MISSING', byName['aeterna_demo'].state)
        assert.are.same({ 'SKIP', 'owner tool' }, { byName['aeterna_quiet'].state, byName['aeterna_quiet'].detail })
        assert.is_nil(byName['ox_lib'])
        assert.is_nil(byName['aeterna_core'])
    end)

    it('cancels a run only for its starter: tests not started become GAP and runDone says cancelled', function()
        exports.aeterna_core:addSelftest('one', { kind = 'ped', timeout = 5000 })
        exports.aeterna_core:addSelftest('two', { kind = 'ped', timeout = 5000 })
        as('aeterna_testkit')
        local id = exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        as('aeterna_other')
        assert.is_false(exports.aeterna_core:cancelRun(id))
        as('aeterna_testkit')
        assert.is_true(exports.aeterna_core:cancelRun(id))
        natives.advance(5050)
        assert.are.same({ 'GAP', 'run cancelled' }, { rowOf('aeterna_core.two').state, rowOf('aeterna_core.two').detail })
        assert.is_true(natives.last_emitted('local', 'aeterna_core:runDone').args[2].cancelled)
        assert.is_nil(exports.aeterna_core:busy())
    end)
    it('refuses a bad only entry without taking the lock', function()
        local id, err = exports.aeterna_core:startRun({ by = 0, only = { 1 } })
        assert.is_nil(id)
        assert.are.equal('only: type', err)
        assert.is_nil(exports.aeterna_core:busy())
    end)

    it('runs only the filtered tests and adds no MISSING rows then', function()
        local started = { 'aeterna_demo' }
        natives.stub('GetNumResources', function() return #started end)
        natives.stub('GetResourceByFindIndex', function(i) return started[i + 1] end)
        natives.stub('GetResourceState', function() return 'started' end)
        exports.aeterna_core:addSelftest('picked')
        exports.aeterna_core:addSelftest('other')
        exports.aeterna_core:startRun({ by = 0, only = { 'aeterna_core.picked' } })
        natives.advance(6000)
        assert.is_not_nil(rowOf('aeterna_core.picked'))
        assert.is_nil(rowOf('aeterna_core.other'))
        assert.is_nil(rowOf('aeterna_demo'))
    end)

    it('gives GAP player left to later client tests after the presser leaves', function()
        exports.aeterna_core:addSelftest('first', { kind = 'ped', timeout = 5000 })
        exports.aeterna_core:addSelftest('second', { kind = 'ped', timeout = 5000 })
        exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        rawset(_G, 'source', 1)
        natives.fire('playerDropped', 'quit')
        rawset(_G, 'source', nil)
        natives.advance(100)
        assert.are.same({ 'GAP', 'player left' }, { rowOf('aeterna_core.second').state, rowOf('aeterna_core.second').detail })
        assert.are.equal(0, #sentTo(1, 'aeterna_core.second'))
    end)

    it('ends a waiting eye test at once when the run is cancelled', function()
        exports.aeterna_core:addSelftest('look', { kind = 'eye', expect = 'A lamp', timeout = 2000 })
        as('aeterna_testkit')
        local id = exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        result(1, id, 'aeterna_core.look', 'ready')
        exports.aeterna_core:cancelRun(id)
        natives.advance(100)
        assert.are.same({ 'GAP', 'run cancelled' }, { rowOf('aeterna_core.look').state, rowOf('aeterna_core.look').detail })
        assert.is_nil(exports.aeterna_core:busy())
    end)

    it('does not let a resource settle a client-side test through the server export', function()
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 1000 })
        local refused
        AddEventHandler('aeterna_core:runProgress', function() end)
        local id = exports.aeterna_core:startRun({ by = 1 })
        refused = exports.aeterna_core:reportSelftest(id, 'aeterna_core.walk', true, 'spoof')
        assert.is_false(refused)
        natives.advance(1100)
        assert.are.equal('timeout', rowOf('aeterna_core.walk').detail)
    end)
end)
