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


