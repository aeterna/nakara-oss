-- client_selftest_spec.lua -- busted tests for the 0.2 client side of aeterna_core: theme preset, themeMessage,
-- hello, the client self-test protocol (cl:selftest, reportSelftest, eye answers) and core's own client checks.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'
local RESULT, ANSWER = 'aeterna_core:sv:selftestResult', 'aeterna_core:sv:eyeAnswer'

-- Fresh client aeterna_core (import.lua + client/main.lua) without a leftover AeternaCore table.
local function load_client(convars)
    natives.reset({ resource = 'aeterna_core', side = 'client', convars = convars })
    rawset(_G, 'AeternaCore', nil)
    resource.load_resource(DIR, 'client')
end

local function as(who)
    natives.stub('GetInvokingResource', function() return who end)
end

-- Records AeternaCore.log.warn calls (core looks the function up at call time, so replacing it works).
local function capture_warns()
    local warns = {}
    AeternaCore.log.warn = function(msg, fields) warns[#warns + 1] = { msg = msg, fields = fields } end
    return warns
end

-- First argument of every captured server call named `name`.
local function sent(name)
    local out = {}
    for _, e in ipairs(natives.emitted('server', name)) do out[#out + 1] = e.args[1] end
    return out
end

local function last(name)
    local list = sent(name)
    return list[#list]
end

-- A server-to-client test message; `over` replaces fields.
local function send_test(over)
    local p = { runId = 'r1-abcd', name = 'aeterna_demo.spawn', kind = 'ped', role = 'A', timeout = 5000, destructive = false }
    for k, v in pairs(over or {}) do p[k] = v end
    natives.fire('aeterna_core:cl:selftest', p)
end

-- Owner report through the client export, invoked as `owner`.
local function report(owner, name, ok, detail, extra)
    as(owner)
    return exports.aeterna_core:reportSelftest('r1-abcd', name, ok, detail, extra)
end

-- Eye answer through the client export, invoked as the testkit.
local function answer(name, a)
    as('aeterna_testkit')
    return exports.aeterna_core:answerEye('r1-abcd', name, a)
end

describe('aeterna_core client: theme preset', function()
    it('c1. valid and unset presets are returned with no warning', function()
        load_client({})
        local warns = capture_warns()
        assert.are.equal('asphalt', exports.aeterna_core:themePreset())
        natives.set_convar('aeterna_theme_preset', 'night-market')
        assert.are.equal('night-market', exports.aeterna_core:themePreset())
        natives.set_convar('aeterna_theme_preset', 'paper')
        assert.are.equal('paper', exports.aeterna_core:themePreset())
        assert.are.equal(0, #warns)
    end)

    it('c3. an invalid value is asphalt, warned once per new value', function()
        load_client({})
        local warns = capture_warns()
        natives.set_convar('aeterna_theme_preset', 'Paper')
        assert.are.equal('asphalt', exports.aeterna_core:themePreset())
        assert.are.equal('asphalt', exports.aeterna_core:themePreset())
        natives.set_convar('aeterna_theme_preset', 'neon')
        assert.are.equal('asphalt', exports.aeterna_core:themePreset())
        assert.are.equal(2, #warns)
        assert.are.equal('Paper', warns[1].fields.value)
        assert.are.equal('neon', warns[2].fields.value)
    end)
end)

describe('aeterna_core client: theme message and hello', function()
    it('c4. themeMessage has the preset and no href without an override', function()
        load_client({ aeterna_theme_preset = 'night-market' })
        assert.are.same({ type = 'aeterna:theme', preset = 'night-market' }, AeternaCore.themeMessage())
    end)

    it('c5. themeMessage has the href and the preset when aeterna_theme is set', function()
        load_client({ aeterna_theme = 'nui://aeterna_uikit/html/theme.css', aeterna_theme_preset = 'paper' })
        assert.are.same({ type = 'aeterna:theme', href = 'nui://aeterna_uikit/html/theme.css', preset = 'paper' },
            AeternaCore.themeMessage())
    end)

    it('c6. the client fires aeterna_core:hello once when it starts', function()
        load_client({})
        assert.are.equal(1, #natives.emitted('local', 'aeterna_core:hello'))
    end)
end)

describe('aeterna_core client: self-test protocol', function()
    it('c7. cl:selftest fires the client-local event with the client ctx', function()
        load_client({})
        local seen = {}
        AddEventHandler('aeterna_core:selftest', function(runId, name, ctx) seen[#seen + 1] = { runId, name, ctx } end)
        send_test({ role = 'B', destructive = true })
        assert.are.same({ { 'r1-abcd', 'aeterna_demo.spawn', { kind = 'ped', side = 'client', role = 'B', destructive = true } } }, seen)
    end)

    it('c8. an invalid cl:selftest is dropped: no event, and a later report is refused', function()
        load_client({})
        local seen = {}
        AddEventHandler('aeterna_core:selftest', function() seen[#seen + 1] = true end)
        send_test({ kind = 'video' })
        assert.are.equal(0, #seen)
        assert.is_false(report('aeterna_demo', 'aeterna_demo.spawn', true))
        assert.are.equal(0, #sent(RESULT))
    end)

    it('c9. a pass is sent with the detail cleaned', function()
        load_client({})
        send_test()
        assert.is_true(report('aeterna_demo', 'aeterna_demo.spawn', true, '  spawned\n'))
        assert.are.same({ runId = 'r1-abcd', name = 'aeterna_demo.spawn', state = 'pass', detail = 'spawned' }, last(RESULT))
    end)

    it('c10. false is a fail; extra keeps only the allowed keys', function()
        load_client({})
        send_test({ kind = 'mock', name = 'aeterna_demo.stack' })
        assert.is_true(report('aeterna_demo', 'aeterna_demo.stack', false, 'stuck',
            { restored = true, wrote = false, step = 3, expected = 'contacts.detail', junk = 'x' }))
        assert.are.same({ runId = 'r1-abcd', name = 'aeterna_demo.stack', state = 'fail', detail = 'stuck',
            restored = true, wrote = false, step = 3, expected = 'contacts.detail' }, last(RESULT))
    end)

    it('c11. a report from another resource, an unknown test or a repeat is dropped', function()
        load_client({})
        send_test()
        as('aeterna_other')
        assert.is_false(exports.aeterna_core:reportSelftest('r1-abcd', 'aeterna_demo.spawn', true))
        assert.is_false(report('aeterna_demo', 'aeterna_demo.other', true))
        assert.is_true(report('aeterna_demo', 'aeterna_demo.spawn', true))
        assert.is_false(report('aeterna_demo', 'aeterna_demo.spawn', true))
        assert.are.equal(1, #sent(RESULT))
    end)

    it('c12. selftestEnd fires the client-local end event and closes the test', function()
        load_client({})
        local ends = {}
        AddEventHandler('aeterna_core:selftestEnd', function(runId, name) ends[#ends + 1] = { runId, name } end)
        send_test()
        natives.fire('aeterna_core:cl:selftestEnd', { runId = 'r1-abcd', name = 'aeterna_demo.spawn' })
        assert.are.same({ { 'r1-abcd', 'aeterna_demo.spawn' } }, ends)
        assert.is_false(report('aeterna_demo', 'aeterna_demo.spawn', true))
    end)

    it('c13. ready is refused for a test that is not an eye test', function()
        load_client({})
        send_test()
        assert.is_false(report('aeterna_demo', 'aeterna_demo.spawn', 'ready'))
        assert.are.equal(0, #sent(RESULT))
    end)

    it('c14. eye ready asks the person and sends ready; ask defaults to the test name', function()
        load_client({})
        local asks = {}
        AddEventHandler('aeterna_core:eyeAsk', function(runId, name, q) asks[#asks + 1] = { runId, name, q } end)
        send_test({ kind = 'eye', name = 'aeterna_demo.look', expect = 'Red light on the phone' })
        assert.is_true(report('aeterna_demo', 'aeterna_demo.look', 'ready'))
        assert.are.same({ runId = 'r1-abcd', name = 'aeterna_demo.look', state = 'ready' }, last(RESULT))
        assert.are.same({ { 'r1-abcd', 'aeterna_demo.look', { ask = 'aeterna_demo.look', expect = 'Red light on the phone', role = 'A' } } }, asks)
    end)

    it('c15. eye: pass is never reported, and ready needs an expect and happens once', function()
        load_client({})
        send_test({ kind = 'eye', name = 'aeterna_demo.look', expect = 'Lamp' })
        assert.is_false(report('aeterna_demo', 'aeterna_demo.look', 'pass'))
        assert.is_true(report('aeterna_demo', 'aeterna_demo.look', 'ready'))
        assert.is_false(report('aeterna_demo', 'aeterna_demo.look', 'ready'))
        send_test({ kind = 'eye', name = 'aeterna_demo.nolook' })
        assert.is_false(report('aeterna_demo', 'aeterna_demo.nolook', 'ready'))
        assert.are.equal(1, #sent(RESULT))
    end)

    it('c16. answerEye is refused before ready and for unknown answers; a valid answer is sent once', function()
        load_client({})
        send_test({ kind = 'eye', name = 'aeterna_demo.look', expect = 'Lamp' })
        assert.is_false(answer('aeterna_demo.look', 'pass'))
        report('aeterna_demo', 'aeterna_demo.look', 'ready')
        assert.is_false(answer('aeterna_demo.look', 'maybe'))
        assert.is_true(answer('aeterna_demo.look', 'mismatch'))
        assert.are.same({ runId = 'r1-abcd', name = 'aeterna_demo.look', answer = 'mismatch' }, last(ANSWER))
        assert.is_false(answer('aeterna_demo.look', 'pass'))
        assert.are.equal(1, #sent(ANSWER))
    end)

    it('c17. the local report and answer events are accepted only when owner is the invoking resource', function()
        load_client({})
        send_test()
        as('aeterna_other')
        natives.fire('aeterna_core:selftest:report', 'aeterna_demo', 'r1-abcd', 'aeterna_demo.spawn', true, 'hi')
        assert.are.equal(0, #sent(RESULT))
        as('aeterna_demo')
        natives.fire('aeterna_core:selftest:report', 'aeterna_demo', 'r1-abcd', 'aeterna_demo.spawn', true, 'hi')
        assert.are.same({ runId = 'r1-abcd', name = 'aeterna_demo.spawn', state = 'pass', detail = 'hi' }, last(RESULT))

        send_test({ kind = 'eye', name = 'aeterna_demo.look', expect = 'Lamp' })
        report('aeterna_demo', 'aeterna_demo.look', 'ready')
        as('aeterna_other')
        natives.fire('aeterna_core:selftest:answer', 'aeterna_demo', 'r1-abcd', 'aeterna_demo.look', 'pass')
        assert.are.equal(0, #sent(ANSWER))
    end)

    it('c18. core client_echo passes; core focus_overlay passes and leaves no focus held', function()
        load_client({})
        send_test({ name = 'aeterna_core.client_echo' })
        assert.are.equal('pass', last(RESULT).state)
        send_test({ name = 'aeterna_core.focus_overlay', kind = 'headless' })
        assert.are.equal('pass', last(RESULT).state)
        assert.is_nil(exports.aeterna_core:focusOwner())
    end)

    it('c20. core focus_overlay skips without taking focus when another resource holds it', function()
        load_client({})
        as('aeterna_demo')
        exports.aeterna_core:requestFocus({ cursor = true })
        send_test({ name = 'aeterna_core.focus_overlay', kind = 'headless' })
        assert.are.equal('skip', last(RESULT).state)
        assert.are.equal('aeterna_demo', exports.aeterna_core:focusOwner())
    end)
end)
