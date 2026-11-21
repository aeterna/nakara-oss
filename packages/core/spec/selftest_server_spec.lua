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

    it('sends expect for ped and eye tests, ask only for eye, and neither for a client-side headless test', function()
        exports.aeterna_core:addSelftest('seat', { kind = 'ped', expect = 'Get in a vehicle', ask = 'Seated?', timeout = 500 })
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 500 })
        exports.aeterna_core:addSelftest('echo', { side = 'client', expect = 'not sent', timeout = 500 })
        exports.aeterna_core:addSelftest('look', { kind = 'eye', expect = 'A lamp', ask = 'Lamp?', timeout = 500 })
        exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        natives.advance(500)
        natives.advance(500)
        natives.advance(500)
        local seat = sentTo(1, 'aeterna_core.seat')[1]
        assert.are.same({ 'Get in a vehicle', nil }, { seat.expect, seat.ask })
        assert.is_nil(sentTo(1, 'aeterna_core.walk')[1].expect)
        local echo = sentTo(1, 'aeterna_core.echo')[1]
        assert.are.same({ nil, nil }, { echo.expect, echo.ask })
        local look = sentTo(1, 'aeterna_core.look')[1]
        assert.are.same({ 'A lamp', 'Lamp?' }, { look.expect, look.ask })
    end)

    it('judges a ped test with expect like any ped test; an eye test with an empty expect still fails unsent', function()
        exports.aeterna_core:addSelftest('seat', { kind = 'ped', expect = 'Get in a vehicle', timeout = 2000 })
        exports.aeterna_core:addSelftest('blank', { kind = 'eye', expect = '' })
        local id = exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        result(1, id, 'aeterna_core.seat', 'pass', { detail = 'seated' })
        natives.advance(50)
        assert.are.same({ 'PASS', 'seated' }, { rowOf('aeterna_core.seat').state, rowOf('aeterna_core.seat').detail })
        assert.are.same({ 'FAIL', 'expect is empty' }, { rowOf('aeterna_core.blank').state, rowOf('aeterna_core.blank').detail })
        assert.are.equal(0, #sentTo(1, 'aeterna_core.blank'))
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

describe('aeterna_core server: client test started and selftestEnd (case 17)', function()
    before_each(function()
        load_server()
        natives.add_player(1, 'A')
        natives.add_player(2, 'B')
    end)

    local function rowOf(name)
        for _, e in ipairs(natives.emitted('local', 'aeterna_core:runProgress')) do
            if e.args[2].name == name then return e.args[2] end
        end
        return nil
    end
    local function eventsFor(event, name)
        local out = {}
        for _, e in ipairs(natives.emitted('local', event)) do
            if e.args[2] == name then out[#out + 1] = e end
        end
        return out
    end
    local function payloadsFor(name)
        local n = 0
        for _, e in ipairs(natives.emitted('client', 'aeterna_core:cl:selftest')) do
            if e.args[1].name == name then n = n + 1 end
        end
        return n
    end
    local function result(src, runId, name, state, extra)
        local p = { runId = runId, name = name, state = state }
        for k, v in pairs(extra or {}) do p[k] = v end
        return natives.fire_net('aeterna_core:sv:selftestResult', src, p)
    end

    it('fires selftestStarted once with a and b before a two-player ped test goes out, and selftestEnd after', function()
        exports.aeterna_core:addSelftest('call', { kind = 'ped', players = 2, timeout = 2000 })
        exports.aeterna_core:addSelftest('h')
        local seen = {}
        AddEventHandler('aeterna_core:selftestStarted', function(runId, name, ctx)
            seen[#seen + 1] = { runId = runId, name = name, ctx = ctx, sentBefore = payloadsFor(name) }
        end)
        AddEventHandler('aeterna_core:selftest', function(runId, name)
            if name == 'aeterna_core.h' then exports.aeterna_core:reportSelftest(runId, name, true, 'ok') end
        end)
        local id = exports.aeterna_core:startRun({ by = 1, b = 2 })
        natives.advance(0)
        assert.are.equal(1, #seen)
        assert.are.same({ id, 'aeterna_core.call', 0 }, { seen[1].runId, seen[1].name, seen[1].sentBefore })
        assert.are.same({ kind = 'ped', side = 'client', a = 1, b = 2, destructive = false }, seen[1].ctx)
        assert.are.equal(2, payloadsFor('aeterna_core.call'))
        assert.are.equal(0, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.call'))

        result(1, id, 'aeterna_core.call', 'pass')
        result(2, id, 'aeterna_core.call', 'pass')
        natives.advance(50)
        assert.are.equal('PASS', rowOf('aeterna_core.call').state)
        local ends = eventsFor('aeterna_core:selftestEnd', 'aeterna_core.call')
        assert.are.equal(1, #ends)
        assert.are.equal(id, ends[1].args[1])
        -- A server-side headless test gets no selftestStarted, but its end is announced too.
        assert.are.equal(0, #eventsFor('aeterna_core:selftestStarted', 'aeterna_core.h'))
        assert.are.equal(1, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.h'))
    end)

    it('fires selftestEnd on the server when a client test times out', function()
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 1000 })
        exports.aeterna_core:startRun({ by = 1 })
        natives.advance(1100)
        assert.are.equal('timeout', rowOf('aeterna_core.walk').detail)
        assert.are.equal(1, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.walk'))
    end)

    it('fires selftestEnd on the server when the owner stops mid-test', function()
        as('aeterna_demo')
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 5000 })
        exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        natives.fire('onResourceStop', 'aeterna_demo')
        natives.advance(50)
        assert.are.equal('owner stopped', rowOf('aeterna_demo.walk').detail)
        assert.are.equal(1, #eventsFor('aeterna_core:selftestEnd', 'aeterna_demo.walk'))
    end)

    it('fires selftestEnd on the server when the player leaves mid-test', function()
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 5000 })
        exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        rawset(_G, 'source', 1)
        natives.fire('playerDropped', 'quit')
        rawset(_G, 'source', nil)
        natives.advance(50)
        assert.are.equal('player left', rowOf('aeterna_core.walk').detail)
        assert.are.equal(1, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.walk'))
    end)

    it('fires neither event for a client test that never started', function()
        exports.aeterna_core:addSelftest('walk', { kind = 'ped' })
        exports.aeterna_core:runSelftests()
        assert.are.equal('needs a person', rowOf('aeterna_core.walk').detail)
        assert.are.equal(0, #eventsFor('aeterna_core:selftestStarted', 'aeterna_core.walk'))
        assert.are.equal(0, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.walk'))
    end)

    it('fires exactly one server selftestEnd when the run is cancelled in the middle of a client test', function()
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 5000 })
        as('aeterna_testkit')
        local id = exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        assert.are.equal(1, #eventsFor('aeterna_core:selftestStarted', 'aeterna_core.walk'))
        assert.is_true(exports.aeterna_core:cancelRun(id))
        natives.advance(100)
        assert.are.equal('run cancelled', rowOf('aeterna_core.walk').detail)
        assert.are.equal(1, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.walk'))
        natives.advance(6000)
        assert.are.equal(1, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.walk'))
    end)

    it('has ended every fired test exactly once before runDone, and fires no end after it', function()
        exports.aeterna_core:addSelftest('h')
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 1000 })
        AddEventHandler('aeterna_core:selftest', function(runId, name)
            if name == 'aeterna_core.h' then exports.aeterna_core:reportSelftest(runId, name, true, 'ok') end
        end)
        local id = exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        natives.fire_net('aeterna_core:sv:selftestResult', 1, { runId = id, name = 'aeterna_core.walk', state = 'pass' })
        natives.advance(50)
        local doneAt, ends = nil, {}
        for i, e in ipairs(natives.emitted('local')) do
            if e.name == 'aeterna_core:runDone' then doneAt = i end
            if e.name == 'aeterna_core:selftestEnd' then ends[#ends + 1] = { at = i, name = e.args[2] } end
        end
        assert.is_number(doneAt)
        local count = {}
        for _, e in ipairs(ends) do
            assert.is_true(e.at < doneAt)
            count[e.name] = (count[e.name] or 0) + 1
        end
        assert.are.same({ ['aeterna_core.core'] = 1, ['aeterna_core.h'] = 1, ['aeterna_core.walk'] = 1 }, count)
        natives.advance(5000)
        assert.are.equal(#ends, #natives.emitted('local', 'aeterna_core:selftestEnd'))
    end)

    it('ends a fired test once on the run failed path and frees the lock', function()
        exports.aeterna_core:addSelftest('boom')
        exports.aeterna_core:addSelftest('later', { kind = 'mock' })
        AddEventHandler('aeterna_core:selftest', function(_, name)
            if name == 'aeterna_core.boom' then error('owner handler broke') end
        end)
        exports.aeterna_core:startRun({ by = 0 })
        natives.advance(0)
        assert.are.same({ 'GAP', 'run failed' }, { rowOf('aeterna_core.boom').state, rowOf('aeterna_core.boom').detail })
        assert.are.equal(1, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.boom'))
        assert.are.equal('run failed', rowOf('aeterna_core.later').detail)
        assert.are.equal(0, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.later'))
        assert.is_true(natives.last_emitted('local', 'aeterna_core:runDone').args[2].cancelled)
        assert.is_nil(exports.aeterna_core:busy())
    end)

    it('frees the lock and ends the test once when a selftestStarted listener throws', function()
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 2000 })
        AddEventHandler('aeterna_core:selftestStarted', function() error('listener broke') end)
        exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        assert.are.equal('run failed', rowOf('aeterna_core.walk').detail)
        assert.are.equal(1, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.walk'))
        assert.are.equal(0, #natives.emitted('client', 'aeterna_core:cl:selftest'))
        assert.is_nil(exports.aeterna_core:busy())
        natives.advance(3000)
        assert.are.equal(1, #eventsFor('aeterna_core:selftestEnd', 'aeterna_core.walk'))
    end)
end)

describe('aeterna_core server: write guard (case 18)', function()
    before_each(function()
        load_server()
        natives.add_player(1, 'A')
    end)

    local function rowOf(name)
        for _, e in ipairs(natives.emitted('local', 'aeterna_core:runProgress')) do
            if e.args[2].name == name then return e.args[2] end
        end
        return nil
    end
    local function openGate()
        natives.set_convar('aeterna_core_allow_destructive', 'true')
        natives.set_convar('sv_master1', '')
    end

    it('returns true for an in-flight destructive test while the gate is open, through the export and import.lua', function()
        openGate()
        exports.aeterna_core:addSelftest('wipe', { kind = 'ped', destructive = true, timeout = 2000 })
        local viaExport, viaImport
        AddEventHandler('aeterna_core:selftestStarted', function(runId, name)
            viaExport = exports.aeterna_core:selftestMayWrite(runId, name)
            viaImport = AeternaCore.selftest.mayWrite(runId, name)
        end)
        local id = exports.aeterna_core:startRun({ by = 1 })
        natives.advance(0)
        assert.is_true(viaExport)
        assert.is_true(viaImport)
        natives.fire_net('aeterna_core:sv:selftestResult', 1, { runId = id, name = 'aeterna_core.wipe', state = 'pass' })
        natives.advance(50)
        assert.are.equal('PASS', rowOf('aeterna_core.wipe').state)
    end)

    it('returns false for a destructive test that the shut gate kept from firing (SKIP, never in flight)', function()
        exports.aeterna_core:addSelftest('wipe', { destructive = true })
        local answer
        AddEventHandler('aeterna_core:runProgress', function(runId, row)
            if row.name == 'aeterna_core.wipe' then answer = exports.aeterna_core:selftestMayWrite(runId, row.name) end
        end)
        exports.aeterna_core:runSelftests()
        assert.is_false(answer)
        assert.are.same({ 'SKIP', 'destructive tests are off' }, { rowOf('aeterna_core.wipe').state, rowOf('aeterna_core.wipe').detail })
    end)

    it('returns false and fails an in-flight test that is not declared destructive', function()
        openGate()
        exports.aeterna_core:addSelftest('plain')
        local answer, late
        AddEventHandler('aeterna_core:selftest', function(runId, name)
            if name ~= 'aeterna_core.plain' then return end
            answer = AeternaCore.selftest.mayWrite(runId, name)
            late = exports.aeterna_core:reportSelftest(runId, name, true, 'ok')
        end)
        exports.aeterna_core:runSelftests()
        assert.is_false(answer)
        assert.is_false(late)
        assert.are.same({ 'FAIL', 'undeclared destructive' }, { rowOf('aeterna_core.plain').state, rowOf('aeterna_core.plain').detail })
    end)

    it('fails a client test that calls the guard without being destructive, before its payload goes out', function()
        openGate()
        exports.aeterna_core:addSelftest('walk', { kind = 'ped', timeout = 2000 })
        AddEventHandler('aeterna_core:selftestStarted', function(runId, name)
            AeternaCore.selftest.mayWrite(runId, name)
        end)
        exports.aeterna_core:startRun({ by = 1 })
        natives.advance(50)
        assert.are.equal('undeclared destructive', rowOf('aeterna_core.walk').detail)
        assert.are.equal(0, #natives.emitted('client', 'aeterna_core:cl:selftest'))
    end)

    it('returns false and changes nothing for an unknown run, a test not in flight, or another resource', function()
        openGate()
        exports.aeterna_core:addSelftest('first', { timeout = 2000 })
        exports.aeterna_core:addSelftest('later', { kind = 'mock', timeout = 2000 })
        local answers = {}
        AddEventHandler('aeterna_core:selftest', function(runId, name)
            if name ~= 'aeterna_core.first' then return end
            answers.unknownRun = exports.aeterna_core:selftestMayWrite('r0-zzzz', name)
            answers.notStarted = exports.aeterna_core:selftestMayWrite(runId, 'aeterna_core.later')
            as('aeterna_other')
            answers.otherOwner = exports.aeterna_core:selftestMayWrite(runId, name)
            as(nil)
        end)
        AddEventHandler('aeterna_core:runDone', function(runId)
            answers.ended = exports.aeterna_core:selftestMayWrite(runId, 'aeterna_core.first')
        end)
        exports.aeterna_core:startRun({ by = 0 })
        natives.advance(2000)
        assert.are.same({ unknownRun = false, notStarted = false, otherOwner = false },
            { unknownRun = answers.unknownRun, notStarted = answers.notStarted, otherOwner = answers.otherOwner })
        assert.are.equal('timeout', rowOf('aeterna_core.first').detail)
        natives.advance(2000)
        assert.are.equal('timeout, state may not be restored', rowOf('aeterna_core.later').detail)
        assert.is_false(answers.ended)
    end)

    it('resolves a short name with the core prefix when no resource invokes it, and still fails a non-destructive test', function()
        exports.aeterna_core:addSelftest('plain')
        local answer
        AddEventHandler('aeterna_core:selftest', function(runId, name)
            if name == 'aeterna_core.plain' then answer = exports.aeterna_core:selftestMayWrite(runId, 'plain') end
        end)
        exports.aeterna_core:runSelftests()
        assert.is_false(answer)
        assert.are.equal('undeclared destructive', rowOf('aeterna_core.plain').detail)
    end)
end)

describe('aeterna_core import.lua: write guard fails closed (case 18)', function()
    local function load_import_in(res)
        natives.reset({ resource = res, side = 'server' })
        rawset(_G, 'AeternaCore', nil)
        assert(loadfile(DIR .. '/import.lua'))()
    end

    it('returns false when aeterna_core is absent', function()
        load_import_in('aeterna_demo')
        assert.is_false(AeternaCore.selftest.mayWrite('r1-abcd', 'aeterna_demo.wipe'))
    end)

    it('returns false when the export throws or answers with something other than true', function()
        load_import_in('aeterna_demo')
        natives.stub_export('aeterna_core', 'selftestMayWrite', function() error('core broke') end)
        assert.is_false(AeternaCore.selftest.mayWrite('r1-abcd', 'aeterna_demo.wipe'))
        natives.stub_export('aeterna_core', 'selftestMayWrite', function() return 'yes' end)
        assert.is_false(AeternaCore.selftest.mayWrite('r1-abcd', 'aeterna_demo.wipe'))
        natives.stub_export('aeterna_core', 'selftestMayWrite', function() return true end)
        assert.is_true(AeternaCore.selftest.mayWrite('r1-abcd', 'aeterna_demo.wipe'))
    end)
end)
