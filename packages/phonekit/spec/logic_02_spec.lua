-- logic_02_spec.lua -- 0.2 pure logic tests: device, exitkeys, battery.

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

describe('aeterna_phonekit 0.2 pure logic', function()
    local D = assert(loadfile(DIR .. '/shared/logic/device.lua'))()
    local E = assert(loadfile(DIR .. '/shared/logic/exitkeys.lua'))()
    local B = assert(loadfile(DIR .. '/shared/logic/battery.lua'))()

    describe('1. device rules', function()
        it('calculates frame size, fold validation, toggle, tiles per page and two panes', function()
            local w, h = D.getFrameSize('slab')
            assert.are.equal(392, w)
            assert.are.equal(812, h)
            local bw, bh = D.getFrameSize('book', 'open')
            assert.are.equal(780, bw)
            assert.are.equal(700, bh)
            local bcw, bch = D.getFrameSize('book', 'closed')
            assert.are.equal(380, bcw)
            assert.are.equal(812, bch)

            assert.is_nil(D.validateFold('slab', 'open'))
            assert.are.equal('open', D.validateFold('fold', 'invalid'))
            assert.are.equal('closed', D.validateFold('book', 'invalid'))
            assert.are.equal('open', D.toggleFold('fold', 'closed'))
            assert.are.equal('closed', D.toggleFold('fold', 'open'))
            assert.are.equal('open', D.toggleFold('slab', 'open'))

            assert.are.equal(24, D.getTilesPerPage('book', 'open'))
            assert.are.equal(12, D.getTilesPerPage('book', 'closed'))
            assert.are.equal(20, D.getTilesPerPage('pad'))
            assert.are.equal(8, D.getTilesPerPage('qwerty'))
            assert.are.equal(12, D.getTilesPerPage('slab'))

            assert.is_true(D.supportsTwoPanes('book', 'open'))
            assert.is_false(D.supportsTwoPanes('book', 'closed'))
            assert.is_false(D.supportsTwoPanes('slab', 'open'))

            local fit = D.calcFit(392, 812, 1280, 720)
            assert.is_true(fit <= 1)
            assert.is_true(812 * fit <= 720)
        end)
    end)

    describe('4. exit contract', function()
        it('handles F-keys vs letters while typing, ESC on all screens, and Backspace', function()
            local st = { isFieldFocused = true, openKeyCode = 'F1' }
            assert.are.equal('close', E.decide(st, 'F1'))
            st.openKeyCode = 'KeyP'
            assert.are.equal('edit', E.decide(st, 'KeyP'))
            st.isFieldFocused = false
            assert.are.equal('close', E.decide(st, 'KeyP'))

            for _, scr in ipairs({ 'app', 'lock', 'cc', 'cover', 'home' }) do
                assert.are.equal('close', E.decide({ screen = scr }, 'Escape'))
            end

            assert.are.equal('edit', E.decide({ isFieldFocused = true }, 'Backspace'))
            assert.are.equal('close_cc', E.decide({ screen = 'cc' }, 'Backspace'))
            assert.are.equal('close', E.decide({ screen = 'home', model = 'keypad' }, 'Backspace'))
            assert.are.equal('back', E.decide({ screen = 'app', model = 'keypad' }, 'Backspace'))

            assert.are.equal('close_cc', E.decide({ screen = 'cc' }, 'HomeBar'))
            assert.are.equal('close', E.decide({ screen = 'home' }, 'HomeBar'))
            assert.are.equal('close', E.decide({ screen = 'lock' }, 'HomeBar'))
            assert.are.equal('home', E.decide({ screen = 'app' }, 'HomeBar'))
        end)
    end)

    describe('5. battery logic', function()
        it('calculates drain, charging, chargers, shown, save step, warnings and pulse', function()
            local rate = B.drainRate({ screen = true, multiplier = 1 })
            assert.are.equal(1.25, rate)
            assert.are.equal(0, B.drainRate({ charging = true, screen = true }))
            local fast = B.fastestCharger({ c1 = { secToFull = 120 }, c2 = { secToFull = -10 } }, true, 300)
            assert.are.equal(120, fast)

            assert.are.equal(0, B.shown(0))
            assert.are.equal(0, B.shown(-5))
            assert.are.equal(1, B.shown(0.1))
            assert.are.equal(100, B.shown(99.2))

            assert.is_true(B.shouldSave(96, 95, 5))
            assert.is_false(B.shouldSave(95, 94, 5))
            assert.is_true(B.shouldSave(1, 0, 5))
            assert.is_true(B.shouldSave(99, 100, 5))

            local w = B.checkWarnings(21, 19, { 20, 10, 5 })
            assert.are.equal(1, #w)
            assert.are.equal(20, w[1])
            assert.are.equal(0, #B.checkWarnings(19, 21, { 20, 10, 5 }))
            assert.are.equal(0, #B.checkWarnings(1, 0, { 20, 10, 5 }))

            assert.is_true(B.isPulseStale(50, 45))
            assert.is_false(B.isPulseStale(30, 45))
        end)
    end)

    describe('6. app specs per model', function()
        it('handles wildcard, exclusions, unknown tokens, settings and voice requirement', function()
            local spec = D.parseAppSpec('*,-contacts,custom:app')
            assert.is_true(spec.wildcard)
            assert.is_true(spec.excluded.contacts)
            assert.is_true(spec.included['custom:app'])

            assert.is_true(D.isAppAllowed(spec, 'settings', nil, 'burner'))
            assert.is_false(D.isAppAllowed(spec, 'contacts', nil, 'burner'))
            assert.is_true(D.isAppAllowed(spec, 'calculator', nil, 'burner'))
            assert.is_true(D.isAppAllowed(spec, 'custom:app', nil, 'burner'))
            assert.is_false(D.isAppAllowed('*', 'phonecall', { needs = 'voice' }, 'pad'))
        end)
    end)

    describe('7. active device pick rule', function()
        it('picks last chosen, or highest rank, ties to smallest id, and nil on empty', function()
            local devs = {
                { id = 'b', model = 'slab' },
                { id = 'a', model = 'slab' },
                { id = 'c', model = 'burner' },
            }
            assert.are.equal('c', D.pickActiveDevice(devs, 'c').id)
            assert.are.equal('a', D.pickActiveDevice(devs).id)
            assert.is_nil(D.pickActiveDevice({}))
        end)
    end)

    describe('8. gate answers validation', function()
        it('validates single and multi-device forms, dropping invalid and duplicates', function()
            local ok, devs = D.validateGateAnswer({ allow = true, id = 'd1', model = 'slab' })
            assert.is_true(ok)
            assert.are.equal(1, #devs)
            assert.are.equal('d1', devs[1].id)

            local ok2, devs2 = D.validateGateAnswer({
                allow = true,
                devices = {
                    { id = 'dup', model = 'slab' },
                    { id = 'dup', model = 'pro' },
                    { id = 'bad', model = 'unknown_model' },
                    { id = 'ok2', model = 'keypad' },
                },
            })
            assert.is_true(ok2)
            assert.are.equal(2, #devs2)
            assert.are.equal('dup', devs2[1].id)
            assert.are.equal('ok2', devs2[2].id)

            local ok3, err = D.validateGateAnswer({ allow = false, reason = 'nodevice' })
            assert.is_false(ok3)
            assert.are.equal('nodevice', err)
        end)
    end)
end)
