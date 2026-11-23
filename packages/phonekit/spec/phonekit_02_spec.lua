-- phonekit_02_spec.lua -- aeterna_phonekit 0.2: "Tests (0.2 additions)" 1-10, review fixes and the uikit 0.2 spec copy.

local natives = require('helpers.natives')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load(rel)
    return assert(loadfile(DIR .. '/shared/logic/' .. rel))()
end

describe('aeterna_phonekit 0.2 additions', function()
    local L, D, B, E, S, H
    before_each(function()
        natives.reset()
        L = load('phone.lua')
        D = load('device.lua')
        B = load('battery.lua')
        E = load('exitkeys.lua')
        S = load('shell.lua')
        H = load('hooks.lua')
    end)

    describe('review fixes', function()
        it('isAppAllowed applies the model default spec when no config spec is given', function()
            assert.is_false(D.isAppAllowed(nil, 'contacts', nil, 'burner'))
            assert.is_true(D.isAppAllowed(nil, 'notes', nil, 'burner'))
            assert.is_true(D.isAppAllowed(nil, 'contacts', nil, 'slab'))
            assert.is_true(D.isAppAllowed(nil, 'settings', nil, 'burner'))
            -- a config spec wins over the default
            assert.is_true(D.isAppAllowed('*', 'contacts', nil, 'burner'))
        end)

        it('drawn scale is min(place scale, fit)', function()
            assert.are.equal(0.8, S.drawnScale(0.8, 0.84))
            assert.are.equal(0.9, S.drawnScale(1.5, 0.9))
            assert.are.equal(1, S.drawnScale(nil, nil))
        end)
    end)

    describe('1. device rules', function()
        it('frame size per model and fold, invalid fold, toggle, tiles, two panes', function()
            local sizes = {
                keypad = { 300, 660 }, burner = { 300, 660 }, qwerty = { 392, 760 }, slab = { 392, 812 },
                pro = { 392, 812 }, pad = { 600, 812 },
            }
            for id, wh in pairs(sizes) do
                local w, h = D.getFrameSize(id)
                assert.are.same(wh, { w, h })
            end
            assert.are.same({ 380, 842 }, { D.getFrameSize('fold', 'open') })
            assert.are.same({ 380, 430 }, { D.getFrameSize('fold', 'closed') })
            assert.are.equal('open', D.validateFold('fold', 'sideways'))
            assert.are.equal('closed', D.validateFold('book', nil))
            assert.is_nil(D.toggleFold('pad', nil))
            assert.are.equal(24, D.getTilesPerPage('book', 'open'))
            assert.are.equal(20, D.getTilesPerPage('pad'))
            assert.are.equal(8, D.getTilesPerPage('qwerty'))
            assert.are.equal(12, D.getTilesPerPage('fold', 'open'))
            assert.is_true(D.supportsTwoPanes('book', 'open'))
            assert.is_false(D.supportsTwoPanes('fold', 'open'))
        end)

        it('fit never exceeds 1 and keeps every frame inside 1280 x 720', function()
            for id in pairs(D.MODELS) do
                for _, fold in ipairs({ 'open', 'closed' }) do
                    local w, h = D.getFrameSize(id, fold)
                    local fit = D.calcFit(w, h, 1280, 720)
                    assert.is_true(fit <= 1)
                    assert.is_true(h * fit <= 720)
                    assert.is_true(w * fit <= 1280)
                end
            end
            assert.are.equal(1, D.calcFit(300, 660, 3840, 2160))
        end)

        it('resolves model config: label precedence, colours, apps, prop', function()
            local t = function(k) return 'T:' .. k end
            local m = D.resolveModel('slab', nil, { names = 'neutral', t = t, prop = 'prop_npc_phone_02' })
            assert.are.equal('T:phonekit.model.slab', m.label)
            assert.are.equal('#3D4046', m.colors[1])
            assert.are.equal('*', m.apps)
            assert.are.equal('prop_npc_phone_02', m.prop)
            assert.are.equal('*,-contacts', D.resolveModel('burner', {}, {}).apps)
            assert.are.equal('iFruit Pro', D.resolveModel('pro', {}, { names = 'universe', t = t }).label)
            local custom = D.resolveModel('pro', { pro = { label = 'My Phone', colors = { '#112233', 'bad' }, prop = 'p2' } },
                { names = 'universe', t = t })
            assert.are.equal('My Phone', custom.label)
            assert.are.same({ '#112233' }, custom.colors)
            assert.are.equal('p2', custom.prop)
            assert.are.equal('#45474B', D.resolveModel('pro', { pro = { colors = { 'bad' } } }, {}).colors[1])
            assert.are.equal('#3A5F8F', D.colorAt('keypad', nil, 1))
            assert.are.equal('#33363B', D.colorAt('keypad', nil, 0))
            assert.are.equal('#33363B', D.colorAt('keypad', nil, 9))
        end)

        it('Config.cover = false forces a fold open', function()
            assert.are.equal('open', D.validateFold('fold', 'closed', false))
            assert.are.equal('closed', D.validateFold('fold', 'closed', true))
            assert.are.equal('closed', D.validateFold('book', 'closed', false))
        end)

        it('builds the server KVP owner key', function()
            assert.are.equal('cid:ABC123', D.whoKey('ABC123', 'license:x'))
            assert.are.equal('lic:license:x', D.whoKey(nil, 'license:x'))
            assert.is_nil(D.whoKey(nil, nil))
        end)
    end)

    describe('2. fold continuity (two panes)', function()
        local list = { screenId = 'a', spec = { blocks = { { id = 'people', type = 'list', items = {} } } } }
        local table1 = { screenId = 'a', spec = { blocks = { { id = 'log', type = 'table', rows = {} } } } }
        local detail = { screenId = 'b', spec = { detailOf = 'people', detailItem = 'p1', blocks = {} } }

        it('close with a detail beside its list leaves the detail alone', function()
            local open = S.panes({ list, detail }, 'book', 'open')
            assert.are.same({ main = 2, left = 1, highlight = 'p1' }, open)
            local closed = S.panes({ list, detail }, 'book', 'closed')
            assert.are.same({ main = 2 }, closed)
        end)

        it('open with a detail on top whose detailOf names a block of the screen under it gives a pair', function()
            assert.are.same({ main = 2, left = 1, highlight = 'p1' }, S.panes({ list, detail }, 'book', 'open'))
            local tdetail = { screenId = 'c', spec = { detailOf = 'log', detailItem = 'r1', blocks = {} } }
            assert.are.equal(1, S.panes({ table1, tdetail }, 'book', 'open').left)
        end)

        it('a detailOf that names no block there is a single screen', function()
            local stray = { screenId = 'c', spec = { detailOf = 'nothere', blocks = {} } }
            assert.are.same({ main = 2 }, S.panes({ list, stray }, 'book', 'open'))
            assert.are.same({ main = 2 }, S.panes({ list, detail }, 'slab', nil))
            assert.are.same({ main = 1 }, S.panes({ detail }, 'book', 'open'))
            assert.are.same({}, S.panes({}, 'book', 'open'))
        end)
    end)

    describe('3. keypad list', function()
        it('arrows wrap, digits map to rows, a digit past the end does nothing, empty stays 0', function()
            assert.are.equal(2, (S.keypadMove(1, 3, 'ArrowDown')))
            assert.are.equal(1, (S.keypadMove(3, 3, 'ArrowDown')))
            assert.are.equal(3, (S.keypadMove(1, 3, 'ArrowUp')))
            local idx, open = S.keypadMove(2, 3, 'Enter')
            assert.are.equal(2, idx)
            assert.are.equal(2, open)
            local i3, o3 = S.keypadMove(1, 12, '3')
            assert.are.equal(3, i3)
            assert.are.equal(3, o3)
            local i10, o10 = S.keypadMove(1, 12, '0')
            assert.are.equal(10, i10)
            assert.are.equal(10, o10)
            local i5, o5 = S.keypadMove(2, 4, '5')
            assert.are.equal(2, i5)
            assert.is_nil(o5)
            local i0, o0 = S.keypadMove(0, 0, 'ArrowDown')
            assert.are.equal(0, i0)
            assert.is_nil(o0)
            assert.is_nil(select(2, S.keypadMove(0, 0, 'Enter')))
        end)
    end)

    describe('4. exit contract', function()
        it('open key: an F-key closes while typing, a letter types; a key a screen used does not close', function()
            assert.are.equal('close', E.decide({ isFieldFocused = true, openKeyCode = 'F2' }, 'F2'))
            assert.are.equal('edit', E.decide({ isFieldFocused = true, openKeyCode = 'KeyM' }, 'KeyM'))
            assert.are.equal('close', E.decide({ openKeyCode = 'KeyM', screen = 'home' }, 'KeyM'))
            assert.are.equal('none', E.decide({ openKeyCode = 'KeyM', screenUsedKey = true }, 'KeyM'))
            assert.are.equal('close', E.decide({ openKeyCode = 'F2', screenUsedKey = true }, 'F2'))
            assert.are.equal('none', E.decide({ screen = 'home' }, 'KeyM'))
        end)

        it('ESC closes from an app screen, the lock screen, the control centre and the cover', function()
            for _, scr in ipairs({ 'app', 'lock', 'cc', 'cover', 'home' }) do
                assert.are.equal('close', E.decide({ screen = scr, isFieldFocused = true }, 'Escape'))
            end
        end)

        it('Backspace and the right mouse button', function()
            assert.are.equal('edit', E.decide({ screen = 'app', isFieldFocused = true }, 'Backspace'))
            assert.are.equal('close_cc', E.decide({ screen = 'cc' }, 'Backspace'))
            assert.are.equal('close_cc', E.decide({ screen = 'cc' }, 'RightMouse'))
            assert.are.equal('back', E.decide({ screen = 'app' }, 'Backspace'))
            assert.are.equal('back', E.decide({ screen = 'app' }, 'RightMouse'))
            assert.are.equal('close', E.decide({ screen = 'home', model = 'burner' }, 'Backspace'))
            assert.are.equal('back', E.decide({ screen = 'lock', model = 'keypad' }, 'Backspace'))
            assert.are.equal('back', E.decide({ screen = 'home', model = 'slab' }, 'Backspace'))
        end)

        it('home bar tap', function()
            assert.are.equal('close_cc', E.decide({ screen = 'cc' }, 'HomeBar'))
            assert.are.equal('close', E.decide({ screen = 'lock' }, 'HomeBar'))
            assert.are.equal('close', E.decide({ screen = 'home' }, 'HomeBar'))
            assert.are.equal('home', E.decide({ screen = 'app' }, 'HomeBar'))
        end)
    end)

    describe('5. battery', function()
        local cfg
        before_each(function()
            cfg = B.validateConfig({})
        end)

        it('drain = standby + max(screen, call, media) / multiplier; charging stops it', function()
            assert.are.equal(1.25, B.drainRate({ screen = true }))
            assert.are.equal(2.75, B.drainRate({ screen = true, media = true }))
            assert.are.equal(1.75, B.drainRate({ screen = true, call = true }))
            assert.are.equal(1.25 / 4, B.drainRate({ screen = true, multiplier = 4 }))
            assert.are.equal(0, B.drainRate({ charging = true, call = true }))
            local st = B.createState(50)
            B.advance(st, 60, { inVehicle = true, screen = 'on', pulseAge = 1 }, cfg)
            assert.is_true(st.pct > 50)
        end)

        it('a duration <= 0 means no charging and the fastest charger wins', function()
            assert.is_nil(B.fastestCharger({ a = 0, b = -5 }, false, 300))
            assert.is_nil(B.fastestCharger({}, true, 0))
            assert.are.equal(60, B.fastestCharger({ a = { secToFull = 600 }, b = { secToFull = 60 } }, true, 300))
            assert.are.equal(300, B.fastestCharger({ a = 900 }, true, 300))
        end)

        it('shown is 0 only at 0', function()
            assert.are.equal(1, B.shown(0.0001))
            assert.are.equal(0, B.shown(0))
        end)

        it('saves on a step crossing, at 0 and at 100', function()
            local st = B.createState(95.2)
            local ev = B.set(st, 94.9, cfg)
            assert.is_true(ev.save)
            ev = B.set(st, 92, cfg)
            assert.is_false(ev.save)
            ev = B.set(st, 0, cfg)
            assert.is_true(ev.save)
            ev = B.set(st, 100, cfg)
            assert.is_true(ev.save)
        end)

        it('warns only going down, once per crossing, never at 0; 0 powers off and above 0 powers on', function()
            local st = B.createState(21)
            local ev = B.set(st, 19.5, cfg)
            assert.are.same({ 20 }, ev.warn)
            ev = B.set(st, 19, cfg)
            assert.are.same({}, ev.warn)
            ev = B.set(st, 25, cfg)
            assert.are.same({}, ev.warn)
            ev = B.set(st, 4, cfg)
            assert.are.same({ 5 }, ev.warn)
            ev = B.set(st, 0, cfg)
            assert.are.same({}, ev.warn)
            assert.is_false(ev.power)
            assert.is_true(st.dead)
            ev = B.set(st, 3, cfg)
            assert.is_true(ev.power)
            assert.is_false(st.dead)
        end)

        it('a stale pulse counts as off', function()
            local a = B.createState(80)
            B.advance(a, 60, { screen = 'on', pulseAge = 50 }, cfg)
            local b = B.createState(80)
            B.advance(b, 60, { screen = 'off' }, cfg)
            assert.are.equal(b.pct, a.pct)
            local c = B.createState(80)
            B.advance(c, 60, { screen = 'on', pulseAge = 5 }, cfg)
            assert.is_true(c.pct < b.pct)
        end)

        it('validates the battery config with one warn per bad key; false turns it off', function()
            local warns = {}
            local clean = B.validateConfig({ tickSec = 2, standby = 'x', warnAt = { 20 }, startPct = 50 },
                function(k) warns[#warns + 1] = k end)
            assert.are.equal(10, clean.tickSec)
            assert.are.equal(0.25, clean.standby)
            assert.are.same({ 20 }, clean.warnAt)
            assert.are.equal(50, clean.startPct)
            assert.are.same({ 'tickSec', 'standby' }, warns)
            assert.is_false(B.validateConfig(false))
        end)
    end)

    describe('6. app specs', function()
        it('*, -x, unknown tokens kept, settings always kept, needs = voice hidden on pad', function()
            local spec = D.parseAppSpec('calculator,-notes,later:app')
            assert.is_false(spec.wildcard)
            assert.is_true(D.isAppAllowed(spec, 'calculator', nil, 'slab'))
            assert.is_false(D.isAppAllowed(spec, 'notes', nil, 'slab'))
            assert.is_true(D.isAppAllowed(spec, 'later:app', nil, 'slab'))
            assert.is_false(D.isAppAllowed(spec, 'contacts', nil, 'slab'))
            assert.is_true(D.isAppAllowed('-settings', 'settings', nil, 'slab'))
            assert.is_true(D.isAppAllowed('*', 'res:call', { needs = 'voice' }, 'slab'))
            assert.is_false(D.isAppAllowed('*', 'res:call', { needs = 'voice' }, 'pad'))
        end)
    end)

    describe('7. active device', function()
        it('last chosen wins while carried; else rank; ties to the smallest id; empty = none', function()
            local devs = { { id = 'z', model = 'keypad' }, { id = 'y', model = 'book' }, { id = 'x', model = 'book' } }
            assert.are.equal('z', D.pickActiveDevice(devs, 'z').id)
            assert.are.equal('x', D.pickActiveDevice(devs, 'gone').id)
            assert.are.equal('x', D.pickActiveDevice(devs).id)
            assert.is_nil(D.pickActiveDevice({}, 'z'))
            assert.is_nil(D.pickActiveDevice(nil))
        end)
    end)

    describe('8. gate answers', function()
        local timers, mgr
        before_each(function()
            timers = {}
            mgr = L.createOpeningCheckManager({
                setTimeout = function(_, fn) timers[#timers + 1] = fn; return #timers end,
                clearTimeout = function() end,
            })
        end)

        it('devices schema and the single-device form; unknown models and duplicate ids dropped', function()
            local ok, devs = D.validateGateAnswer({ allow = true, devices = {
                { id = 'a', model = 'slab', battery = 40, fold = 'open', color = 2 },
                { id = 'a', model = 'pad' },
                { id = 'b', model = 'brick' },
                { id = string.rep('x', 65), model = 'slab' },
                { id = 'c', model = 'fold', battery = 300, fold = 'sideways', color = -1 },
            } })
            assert.is_true(ok)
            assert.are.equal(2, #devs)
            assert.are.equal(40, devs[1].battery)
            assert.are.equal(2, devs[1].color)
            assert.is_nil(devs[2].battery)
            assert.is_nil(devs[2].fold)
            assert.is_nil(devs[2].color)
            local ok1, one = D.validateGateAnswer({ allow = true, id = 'p1', model = 'book' })
            assert.is_true(ok1)
            assert.are.equal('book', one[1].model)
            local nine = {}
            for i = 1, 9 do nine[i] = { id = 'd' .. i, model = 'slab' } end
            local _, eight = D.validateGateAnswer({ allow = true, devices = nine })
            assert.are.equal(8, #eight)
        end)

        it('an empty list is a denial with nodevice', function()
            local ok, reason = D.validateGateAnswer({ allow = true, devices = {} })
            assert.is_false(ok)
            assert.are.equal('phonekit.refused.nodevice', reason)
        end)

        it('item mode silence denies with nodevice even with no listener', function()
            local got
            mgr:createCheck(1, function(_, allowed, reason) got = { allowed, reason } end,
                { silenceDenies = true, silenceReason = 'phonekit.refused.nodevice' })
            timers[1]()
            assert.are.same({ false, 'phonekit.refused.nodevice' }, got)
        end)

        it('answer with allow = false is denyOpen; allow with devices passes the list', function()
            local got
            local id = mgr:createCheck(1, function(_, allowed, reason, devices) got = { allowed, reason, devices } end)
            assert.is_true(mgr:answer(id, { allow = false, reason = 'phonekit.refused.custom' }))
            assert.are.same({ false, 'phonekit.refused.custom' }, { got[1], got[2] })
            local id2 = mgr:createCheck(1, function(_, allowed, reason, devices) got = { allowed, reason, devices } end)
            assert.is_true(mgr:allowOpen(id2, { allow = true, devices = { { id = 'q', model = 'pro' } } }))
            assert.is_true(got[1])
            assert.are.equal('q', got[3][1].id)
            local id3 = mgr:createCheck(1, function(_, allowed, reason) got = { allowed, reason } end)
            mgr:answer(id3, { allow = true, devices = {} })
            assert.are.same({ false, 'phonekit.refused.nodevice' }, got)
        end)

        it('a stale checkId is ignored', function()
            local calls = 0
            local id = mgr:createCheck(1, function() calls = calls + 1 end)
            mgr:answer(id, { allow = true, id = 'a', model = 'slab' })
            local ok, err = mgr:answer(id, { allow = true, id = 'a', model = 'slab' })
            assert.is_false(ok)
            assert.are.equal('stale', err)
            assert.is_false((mgr:answer('chk_999', { allow = false })))
            assert.are.equal(1, calls)
        end)
    end)

    describe('9. own clamp (no layout)', function()
        it('a frame that grows on unfold is shifted inside the viewport and nothing is saved', function()
            local place = { x = 1, y = 0, ax = 1, ay = 0, scale = 1 }
            local closed = S.frameRect(place, 'bottom-right', 380, 812, 1920, 1080)
            assert.is_true(closed.x + 380 * closed.scale <= 1920)
            local open = S.frameRect(place, 'bottom-right', 780, 700, 1920, 1080)
            assert.is_true(open.x >= 0 and open.x + 780 * open.scale <= 1920)
            assert.is_true(open.y >= 0 and open.y + 700 * open.scale <= 1080)
            assert.are.same({ x = 1, y = 0, ax = 1, ay = 0, scale = 1 }, place)
            local small = S.frameRect(nil, 'bottom-left', 780, 700, 1280, 720)
            assert.is_true(small.x >= 0 and small.x + 780 * small.scale <= 1280)
            assert.is_true(small.y >= 0 and small.y + 700 * small.scale <= 720)
        end)

        it('drawn scale = min(place scale, fit) on real viewports', function()
            -- slab 392 x 812 in 1280 x 720: fit = (720 - 0.048 * 720) / 812 = 0.8441
            local fit = (720 - 0.048 * 720) / 812
            local r = S.frameRect({ x = 0.5, y = 0.5, ax = 0.5, ay = 0.5, scale = 0.8 }, 'bottom-right', 392, 812, 1280, 720)
            assert.are.equal(0.8, r.scale)
            local big = S.frameRect({ x = 0.5, y = 0.5, ax = 0.5, ay = 0.5, scale = 1.5 }, 'bottom-right', 392, 812, 1280, 720)
            assert.is_true(math.abs(big.scale - fit) < 1e-9)
            local none = S.frameRect(nil, 'bottom-right', 392, 812, 1920, 1080)
            assert.are.equal(1, none.scale)
        end)
    end)

    describe('10. hooks', function()
        it('addContact limits and contactsChanged fires once per change', function()
            local saved, changes = nil, 0
            local hook = H.createContactsHook({
                load = function() return saved or {} end,
                save = function(list) saved = list end,
                onChange = function() changes = changes + 1 end,
            })
            assert.is_true(hook:addContact({ name = 'Ann', number = '555-1' }))
            assert.are.equal(1, changes)
            assert.are.equal(1, #saved)
            local ok, key = hook:addContact({ name = string.rep('n', 41), number = '1' })
            assert.is_true(ok)
            assert.are.equal(40, utf8.len(hook:getContacts()[2].name))
            assert.are.equal(2, changes)
            ok, key = hook:addContact({ name = '', number = '1' })
            assert.is_false(ok)
            assert.is_string(key)
            assert.are.equal(2, changes)
            local copy = hook:getContacts()
            copy[1].name = 'mutated'
            assert.are_not.equal('mutated', hook:getContacts()[1].name)
            hook:replaceAll({ { id = 'c1', name = 'Bob', number = '2' } })
            assert.are.equal(3, changes)
            local full = H.createContactsHook({ load = function()
                local l = {}
                for i = 1, 100 do l[i] = { id = 'c' .. i, name = 'N' .. i, number = '1' } end
                return l
            end })
            ok, key = full:addContact({ name = 'Over', number = '1' })
            assert.is_false(ok)
            assert.are.equal('phonekit.contacts.full', key)
        end)

        it('an intent reaches only the handling app; the first registered wins with a warn', function()
            local warns = {}
            local intents = H.createIntents(function(msg, f) warns[#warns + 1] = f end)
            intents:register('res_a', 'dialer', { 'tel' })
            intents:register('res_b', 'dialer2', { 'tel', 'sms' })
            assert.are.equal(1, #warns)
            local r = intents:route('tel', '555')
            assert.are.same({ owner = 'res_a', id = 'dialer', intent = { kind = 'tel', number = '555' } }, r)
            assert.are.equal('res_b', intents:route('sms', '1').owner)
            assert.is_nil(intents:route('fax', '1'))
            assert.is_true(intents:isHandler('tel', 'res_a', 'dialer'))
            assert.is_false(intents:isHandler('tel', 'res_b', 'dialer2'))
            intents:set('res_a', 'dialer', { 'tel' })
            assert.is_true(intents:isHandler('tel', 'res_a', 'dialer'))
            intents:set('res_a', 'dialer', {})
            assert.is_true(intents:isHandler('tel', 'res_b', 'dialer2'))
            intents:set('res_a', 'dialer', { 'tel' })
            assert.is_true(intents:isHandler('tel', 'res_b', 'dialer2'))
            assert.is_true(H.isPhoneNumber('+66 (81) 555-01*2#'))
            assert.is_false(H.isPhoneNumber('call me'))
            assert.is_false(H.isPhoneNumber(''))
            intents:removeOwner('res_a')
            assert.are.equal('res_b', intents:route('tel', '1').owner)
            assert.are.same({ tel = { owner = 'res_b', id = 'dialer2' }, sms = { owner = 'res_b', id = 'dialer2' } },
                intents:available())
        end)

        it('ring refuses novoice, busy and dead; answer maps to __answer; it expires at 60 s', function()
            local now = 1000
            local rings = H.createRingManager({ now = function() return now end })
            local base = { owner = 'res', id = 'dialer', appExists = true, hasDevice = true, voice = true, battery = 50,
                title = 'Call', body = 'Ann' }
            local function with(over)
                local t = {}
                for k, v in pairs(base) do t[k] = v end
                for k, v in pairs(over) do t[k] = v end
                return t
            end
            assert.are.same({ nil, 'novoice' }, { rings:ring(1, with({ voice = false })) })
            assert.are.same({ nil, 'dead' }, { rings:ring(1, with({ battery = 0 })) })
            assert.are.same({ nil, 'nodevice' }, { rings:ring(1, with({ hasDevice = false })) })
            assert.are.same({ nil, 'noapp' }, { rings:ring(1, with({ appExists = false })) })
            local ringId = rings:ring(1, base)
            assert.is_string(ringId)
            assert.are.same({ nil, 'busy' }, { rings:ring(1, base) })
            local act = rings:answer(1, ringId, true)
            assert.are.same({ owner = 'res', id = 'dialer', screenId = ringId, action = '__answer', values = {} }, act)
            assert.is_nil(rings:answer(1, ringId, true))
            local r2 = rings:ring(1, base)
            assert.are.equal('__decline', rings:answer(1, r2, false).action)
            local r3 = rings:ring(1, base)
            now = now + 59
            assert.are.same({}, rings:expire())
            now = now + 2
            assert.are.same({ { src = 1, ringId = r3 } }, rings:expire())
            assert.is_nil(rings:current(1))
        end)

        it('canCall truth table', function()
            assert.is_true(H.canCall({ hasDevice = true, model = 'slab', battery = 50 }))
            assert.is_false(H.canCall({ hasDevice = true, model = 'pad', battery = 50 }))
            assert.is_false(H.canCall({ hasDevice = false, model = 'slab', battery = 50 }))
            assert.is_false(H.canCall({ hasDevice = true, model = 'slab', battery = 0 }))
            assert.is_true(H.canCall({ hasDevice = true, model = 'keypad', battery = nil }))
        end)
    end)

    describe('lock screen and history', function()
        it('locks only when enabled and something waits; unread is newer than the seen mark', function()
            assert.is_false(S.shouldLock(false, { a = 2 }, {}, 0))
            assert.is_false(S.shouldLock(true, {}, { { at = 5 } }, 10))
            assert.is_true(S.shouldLock(true, { a = 1 }, {}, 0))
            assert.is_true(S.shouldLock(true, {}, { { at = 11 } }, 10))
            assert.are.equal(1, S.unreadCount({ { at = 11 }, { at = 9 } }, 10))
        end)
    end)

    describe('uikit 0.2 spec copy', function()
        local function spec(blocks, extra)
            local s = { title = 'T', blocks = blocks }
            for k, v in pairs(extra or {}) do s[k] = v end
            return s
        end

        it('tabs: one per spec, 2-6 items, tab must name an item, value defaults to the first', function()
            local tabs = { id = 'tb', type = 'tabs', items = { { id = 'a', label = 'A' }, { id = 'b', label = 'B' } } }
            local ok, _, clean = L.validateSpec(spec({ tabs, { id = 'x', type = 'text', label = 'hi', tab = 'b' } }))
            assert.is_true(ok)
            assert.are.equal('a', clean.blocks[1].value)
            assert.are.equal('b', clean.blocks[2].tab)
            assert.is_false((L.validateSpec(spec({ tabs, { id = 't2', type = 'tabs', items = { { id = 'c', label = 'C' }, { id = 'd', label = 'D' } } } }))))
            assert.is_false((L.validateSpec(spec({ { id = 'tb', type = 'tabs', items = { { id = 'a', label = 'A' } } } }))))
            assert.is_false((L.validateSpec(spec({ tabs, { id = 'x', type = 'text', label = 'hi', tab = 'zz' } }))))
            assert.is_false((L.validateSpec(spec({ { id = 'x', type = 'text', label = 'hi', tab = 'a' } }))))
            local okV, _, cv = L.validateValues(clean, { tb = 'b' })
            assert.is_true(okV)
            assert.are.equal('b', cv.tb)
            local rep = { id = 'tb', type = 'tabs', report = true, items = tabs.items }
            local _, _, c2 = L.validateSpec(spec({ rep }))
            assert.is_true((L.validateAction({ screenId = 's', spec = c2 }, { screenId = 's', action = 'b' })))
            assert.is_false((L.validateAction({ screenId = 's', spec = clean }, { screenId = 's', action = 'b' })))
        end)

        it('slider: range, step and value rules; returned values re-checked', function()
            local good = { id = 'v', type = 'slider', label = 'Vol', min = 0, max = 100, step = 5, value = 50 }
            local ok, _, clean = L.validateSpec(spec({ good }))
            assert.is_true(ok)
            assert.is_false((L.validateSpec(spec({ { id = 'v', type = 'slider', label = 'V', min = 5, max = 5, step = 1 } }))))
            assert.is_false((L.validateSpec(spec({ { id = 'v', type = 'slider', label = 'V', min = 0, max = 5, step = 0 } }))))
            assert.is_false((L.validateSpec(spec({ { id = 'v', type = 'slider', label = 'V', min = 0, max = 1001, step = 1 } }))))
            assert.is_false((L.validateSpec(spec({ { id = 'v', type = 'slider', label = 'V', min = 0, max = 5, step = 1, value = 9 } }))))
            assert.is_true((L.validateValues(clean, { v = 55 })))
            assert.is_false((L.validateValues(clean, { v = 52 })))
            assert.is_false((L.validateValues(clean, { v = 105 })))
        end)

        it('table: columns, rows, cell keys, selectable rows are actions', function()
            local cols = { { id = 'when', label = 'When' }, { id = 'what', label = 'What', align = 'end' } }
            local tbl = { id = 'log', type = 'table', columns = cols, selectable = true,
                rows = { { id = 'r1', cells = { when = '21:47' } } } }
            local ok, _, clean = L.validateSpec(spec({ tbl }))
            assert.is_true(ok)
            assert.is_true((L.validateAction({ screenId = 's', spec = clean }, { screenId = 's', action = 'r1' })))
            local seven = {}
            for i = 1, 7 do seven[i] = { id = 'c' .. i, label = 'C' } end
            assert.is_false((L.validateSpec(spec({ { id = 'log', type = 'table', columns = seven, rows = {} } }))))
            local rows = {}
            for i = 1, 51 do rows[i] = { id = 'r' .. i, cells = {} } end
            assert.is_false((L.validateSpec(spec({ { id = 'log', type = 'table', columns = cols, rows = rows } }))))
            assert.is_false((L.validateSpec(spec({ { id = 'log', type = 'table', columns = cols, rows = { { id = 'r', cells = { nope = 'x' } } } } }))))
            assert.is_false((L.validateSpec(spec({ { id = 'log', type = 'table', columns = cols, rows = { { id = 'r', cells = {} }, { id = 'r', cells = {} } } } }))))
            local _, _, plain = L.validateSpec(spec({ { id = 'log', type = 'table', columns = cols, rows = { { id = 'r1', cells = {} } } } }))
            assert.is_false((L.validateAction({ screenId = 's', spec = plain }, { screenId = 's', action = 'r1' })))
        end)

        it('list search raises the limit to 200; empty block needs a label and its action is allowed', function()
            local items = {}
            for i = 1, 200 do items[i] = { id = 'i' .. i, label = 'L' } end
            assert.is_true((L.validateSpec(spec({ { id = 'l', type = 'list', search = true, items = items } }))))
            local fifty1 = {}
            for i = 1, 51 do fifty1[i] = { id = 'i' .. i, label = 'L' } end
            assert.is_false((L.validateSpec(spec({ { id = 'l', type = 'list', items = fifty1 } }))))
            assert.is_false((L.validateSpec(spec({ { id = 'e', type = 'empty' } }))))
            local ok, _, clean = L.validateSpec(spec({ { id = 'e', type = 'empty', icon = 'box', label = 'Nothing',
                action = { id = 'add', label = 'Add' } } }))
            assert.is_true(ok)
            assert.is_true((L.validateAction({ screenId = 's', spec = clean }, { screenId = 's', action = 'add' })))
        end)

        it('detailOf and detailItem pass through; bad ids and detailItem alone fail', function()
            local ok, _, clean = L.validateSpec(spec({}, { detailOf = 'people', detailItem = 'p1' }))
            assert.is_true(ok)
            assert.are.equal('people', clean.detailOf)
            assert.are.equal('p1', clean.detailItem)
            assert.is_false((L.validateSpec(spec({}, { detailOf = 'bad id' }))))
            assert.is_false((L.validateSpec(spec({}, { detailItem = 'p1' }))))
        end)

        it('update patches rows, tab value and slider value; a slider value out of range is refused', function()
            local _, _, clean = L.validateSpec(spec({
                { id = 'tb', type = 'tabs', items = { { id = 'a', label = 'A' }, { id = 'b', label = 'B' } } },
                { id = 'v', type = 'slider', label = 'V', min = 0, max = 10, step = 1 },
                { id = 'log', type = 'table', columns = { { id = 'c', label = 'C' } }, rows = {} },
            }))
            local ok, err, p = L.validatePatch(clean, { blocks = {
                tb = { value = 'b' }, v = { value = 3 }, log = { rows = { { id = 'r9', cells = { c = 'x' } } } },
            } })
            assert.is_true(ok, err)
            assert.are.equal('r9', p.blocks.log.rows[1].id)
            assert.is_false((L.validatePatch(clean, { blocks = { v = { value = 11 } } })))
            assert.is_false((L.validatePatch(clean, { blocks = { tb = { value = 'zz' } } })))
        end)
    end)
end)

describe('aeterna_phonekit 0.2 server under the harness', function()
    local resource = require('helpers.resource')

    local function boot()
        natives.reset({ resource = 'aeterna_phonekit', side = 'server', players = { [1] = 'One' } })
        natives.stub('AeternaCore', {
            log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
            t = function(k) return k end,
            lang = function() return 'en' end,
            can = function() return true end,
            rateLimit = function() return true end,
        })
        natives.stub('GetPlayerIdentifierByType', function() return 'license:abc' end)
        natives.stub_export('aeterna_notify', 'notify', function() return true end)
        return resource.load_resource(DIR, 'server').exports
    end

    local function lastArgs(kind, name)
        local e = natives.last_emitted(kind, name)
        return e and e.args[1], e
    end

    it('battery: 0 closes every surface, fires power off, saves KVP and refuses open; charge brings it back', function()
        local api = boot()
        natives.fire_net('aeterna_phonekit:sv:battery', 1)
        assert.are.equal(100, lastArgs('client', 'aeterna_phonekit:cl:battery').pct)
        assert.are.equal('slab', lastArgs('client', 'aeterna_phonekit:cl:device').model)
        assert.are.equal(100, api.battery(1))

        natives.fire_net('aeterna_phonekit:sv:open', 1)
        assert.is_true(api.setBattery(1, 0))
        assert.is_false(lastArgs('client', 'aeterna_phonekit:cl:power').on)
        local power = natives.last_emitted('local', 'aeterna_phonekit:power')
        assert.are.equal(1, power.args[1])
        assert.is_false(power.args[2].on)
        assert.is_nil(api.device(1))
        assert.is_truthy(natives.get_kvp('aeterna_phonekit:device:v1:lic:license:abc'))
        assert.is_nil(api.showApp(1, 'nothing', { title = 'x', blocks = {} }))

        natives.fire_net('aeterna_phonekit:sv:open', 1)
        assert.are.equal('phonekit.battery.dead', lastArgs('client', 'aeterna_phonekit:cl:refused').reason)

        assert.is_true(api.charge(1, 30))
        assert.is_true(lastArgs('client', 'aeterna_phonekit:cl:power').on)
        assert.are.equal(30, api.battery(1))
        assert.are.equal('slab', api.device(1).model)
    end)

    it('the tick drains a loaded player and a stale pulse counts as off', function()
        local api = boot()
        natives.fire_net('aeterna_phonekit:sv:battery', 1)
        natives.fire_net('aeterna_phonekit:sv:screen', 1, { level = 'on' })
        natives.advance(30000)
        natives.fire_net('aeterna_phonekit:sv:screen', 1, { level = 'on' })
        natives.advance(30000)
        local onScreen = 100 - api.battery(1)
        assert.is_true(onScreen >= 1)
        natives.advance(600000)
        local before = api.battery(1)
        natives.advance(60000)
        -- pulse long stale: only standby (0.25 %/min) drains
        assert.is_true(before - api.battery(1) <= 1)
    end)

    local function bootItems()
        natives.reset({ resource = 'aeterna_phonekit', side = 'server', players = { [1] = 'One' } })
        natives.stub('AeternaCore', {
            log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
            t = function(k) return k end,
            lang = function() return 'en' end,
            can = function() return true end,
            rateLimit = function() return true end,
        })
        natives.stub('GetPlayerIdentifierByType', function() return 'license:abc' end)
        natives.stub_export('aeterna_notify', 'notify', function() return true end)
        natives.stub('Config', { devices = 'items', models = {}, battery = {}, apps = {} })
        local res = resource.load_resource(DIR, 'server', { skip = { ['config.lua'] = true } })
        return res.exports
    end

    local function answerLast(answer)
        local ask = natives.last_emitted('local', 'aeterna_phonekit:asking')
        natives.fire('aeterna_phonekit:answer', ask.args[2].checkId, answer)
    end

    it('items: a phone handed away and back carries the battery from the item', function()
        local api = bootItems()
        natives.fire_net('aeterna_phonekit:sv:open', 1)
        answerLast({ allow = true, devices = { { id = 'A', model = 'slab', battery = 80, fold = nil },
            { id = 'B', model = 'keypad', battery = 50 } } })
        assert.are.equal('A', api.device(1).id)
        assert.is_true(api.setBattery(1, 40))
        api.refreshDevices(1)
        answerLast({ allow = true, devices = { { id = 'B', model = 'keypad', battery = 50 } } })
        assert.are.equal('B', api.device(1).id)
        api.refreshDevices(1)
        answerLast({ allow = true, devices = { { id = 'A', model = 'slab', battery = 90 },
            { id = 'B', model = 'keypad', battery = 50 } } })
        assert.are.equal('A', api.device(1).id)
        assert.are.equal(90, api.battery(1))
    end)

    it('items: the active phone keeps its own number; a fold-less item is not saved on every answer', function()
        local api = bootItems()
        natives.fire_net('aeterna_phonekit:sv:open', 1)
        answerLast({ allow = true, devices = { { id = 'A', model = 'slab', battery = 80 } } })
        api.setBattery(1, 61)
        local saves = #natives.emitted('local', 'aeterna_phonekit:deviceSave')
        api.refreshDevices(1)
        answerLast({ allow = true, devices = { { id = 'A', model = 'slab', battery = 80 } } })
        assert.are.equal(61, api.battery(1))
        assert.are.equal(saves, #natives.emitted('local', 'aeterna_phonekit:deviceSave'))
    end)

    it('items: switching to a phone at 0 % powers off; no device refuses open with nodevice', function()
        local api = bootItems()
        natives.fire_net('aeterna_phonekit:sv:open', 1)
        answerLast({ allow = true, devices = { { id = 'A', model = 'slab', battery = 80 },
            { id = 'Z', model = 'keypad', battery = 0 } } })
        natives.fire_net('aeterna_phonekit:sv:device', 1, { id = 'Z' })
        assert.is_false(lastArgs('client', 'aeterna_phonekit:cl:power').on)
        natives.fire_net('aeterna_phonekit:sv:device', 1, { id = 'A' })
        assert.is_true(lastArgs('client', 'aeterna_phonekit:cl:power').on)

        natives.stub('GetPlayerIdentifierByType', function() return nil end)
        natives.fire_net('aeterna_phonekit:sv:open', 2)
        assert.are.equal('phonekit.refused.nodevice', lastArgs('client', 'aeterna_phonekit:cl:refused').reason)
    end)

    it('intent number must look like a number; the live pill is cleared only by its owner', function()
        local api = boot()
        assert.is_true(api.addTile({ id = 'dialer', label = 'Dialer', icon = 'phone', handles = { 'tel' } }))
        natives.fire_net('aeterna_phonekit:sv:battery', 1)
        natives.fire_net('aeterna_phonekit:sv:open', 1)
        local before = #natives.emitted('local', 'aeterna_phonekit:app')
        natives.fire_net('aeterna_phonekit:sv:tap', 1, { id = 'dialer', owner = 'aeterna_phonekit',
            intent = { kind = 'tel', number = 'call me' } })
        assert.are.equal(before, #natives.emitted('local', 'aeterna_phonekit:app'))
        natives.fire_net('aeterna_phonekit:sv:tap', 1, { id = 'dialer', owner = 'aeterna_phonekit',
            intent = { kind = 'tel', number = '555-0101' } })
        assert.are.equal(before + 1, #natives.emitted('local', 'aeterna_phonekit:app'))

        natives.stub('GetInvokingResource', function() return 'res_a' end)
        assert.is_true(api.live(1, { id = 'call', text = 'On call' }))
        natives.stub('GetInvokingResource', function() return 'res_b' end)
        assert.is_false(api.live(1, nil))
        natives.stub('GetInvokingResource', function() return 'res_a' end)
        assert.is_true(api.live(1, nil))
    end)

    it('ring: busy on a second ring, answer maps to __answer, sv:fold refused on a slab', function()
        local api = boot()
        assert.is_true(api.addTile({ id = 'dialer', label = 'Dialer', icon = 'phone', needs = 'voice', handles = { 'tel' } }))
        natives.fire_net('aeterna_phonekit:sv:battery', 1)
        natives.fire_net('aeterna_phonekit:sv:open', 1)
        assert.is_true(api.canCall(1))
        local ringId = api.ring(1, 'dialer', { title = 'Ann', body = 'calling' })
        assert.is_string(ringId)
        assert.are.equal(ringId, lastArgs('client', 'aeterna_phonekit:cl:ring').ringId)
        assert.are.same({ nil, 'busy' }, { api.ring(1, 'dialer', { title = 'Bob' }) })
        natives.fire_net('aeterna_phonekit:sv:ring', 1, { ringId = ringId, answer = true })
        local e = natives.last_emitted('local', 'aeterna_phonekit:action')
        assert.are.equal('__answer', e.args[2].action)
        assert.are.equal(ringId, e.args[2].screenId)
        assert.are.equal('dialer', e.args[2].id)
        local opened = lastArgs('client', 'aeterna_phonekit:cl:open')
        assert.are.equal('dialer', opened.intents.tel.id)
        local kvpBefore = natives.get_kvp('aeterna_phonekit:device:v1:lic:license:abc')
        natives.fire_net('aeterna_phonekit:sv:fold', 1, { state = 'closed' })
        assert.are.equal(kvpBefore, natives.get_kvp('aeterna_phonekit:device:v1:lic:license:abc'))
    end)
end)

describe('aeterna_phonekit 0.2 client under the harness', function()
    local resource = require('helpers.resource')

    it('a focus-denied open tells the server the phone is closed', function()
        natives.reset({ resource = 'aeterna_phonekit', side = 'client' })
        natives.spy('SendNUIMessage')
        natives.spy('RegisterNUICallback')
        natives.spy('RegisterKeyMapping')
        natives.spy('RegisterCommand')
        natives.stub('AeternaCore', {
            log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
            t = function(k) return k end,
            lang = function() return 'en' end,
            kvp = { get = function(_, _, default) return default end, set = function() end },
            key = function() end,
            requestFocus = function() return nil end,
            releaseFocus = function() return true end,
        })
        natives.stub_export('aeterna_core', 'themeHref', function() return nil end)
        natives.stub_export('aeterna_core', 'themePreset', function() return 'paper' end)
        natives.stub_export('aeterna_notify', 'history', function() return {} end)
        resource.load_resource(DIR, 'client')
        local before = #natives.emitted('server', 'aeterna_phonekit:sv:close')
        natives.fire('aeterna_phonekit:cl:open', { apps = {} })
        assert.are.equal(before + 1, #natives.emitted('server', 'aeterna_phonekit:sv:close'))
        -- live W3 2026-11-23: the theme preset never reached the phone page
        local theme
        for _, call in ipairs(natives.calls('SendNUIMessage')) do
            if type(call[1]) == 'table' and call[1].type == 'aeterna:theme' then theme = call[1] end
        end
        assert.is_truthy(theme, 'expected aeterna:theme on open')
        assert.are.equal('paper', theme.preset)
    end)
end)
