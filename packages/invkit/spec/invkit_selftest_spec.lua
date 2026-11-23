-- invkit_selftest_spec.lua -- busted tests for the aeterna_invkit 0.2 self-tests
-- (docs/specs/aeterna_invkit.md § Self-tests (0.2); judging rules in docs/specs/aeterna_core.md § 0.2 additions).

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'
local CORE_DIR = DIR .. '/../core'

local SHIPPED_ITEMS = {
    phone = 'slab',
    phone_keypad = 'keypad', phone_burner = 'burner', phone_qwerty = 'qwerty', phone_slab = 'slab',
    phone_fold = 'fold', phone_pro = 'pro', phone_book = 'book', phone_pad = 'pad',
}

local function load_logic(name)
    return assert(loadfile(DIR .. '/shared/logic/' .. name .. '.lua'))()
end

-- Core's local events come from aeterna_core: fire them with that invoking resource, as FXServer does.
local function fireAsCore(name, ...)
    local original = GetInvokingResource
    natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
    natives.fire(name, ...)
    natives.stub('GetInvokingResource', original)
end

local function by_name(defs)
    local out = {}
    for _, d in ipairs(defs) do out[d.name] = d.meta end
    return out
end

describe('aeterna_invkit self-tests', function()
    local ST

    before_each(function()
        natives.reset()
        load_logic('invkit')
        load_logic('phone')
        ST = load_logic('selftest')
    end)

    describe('registration rows', function()
        it('lists the nine spec rows in spec order', function()
            local names = {}
            for i, d in ipairs(ST.definitions()) do names[i] = d.name end
            assert.are.same({ 'stash_id', 'use_state_machine', 'phone_item_map', 'stash_open', 'item_use',
                'phone_two_items', 'phone_drop_active', 'phone_no_item', 'phone_device_save' }, names)
        end)

        it('sets kind, side, players and destructive as the spec table says', function()
            local rules = assert(loadfile(CORE_DIR .. '/shared/logic/selftest.lua'))()
            local want = {
                stash_id = { 'headless', 'server', false },
                use_state_machine = { 'headless', 'server', false },
                phone_item_map = { 'headless', 'server', false },
                stash_open = { 'ped', 'client', false },
                item_use = { 'mock', 'client', true },
                -- owner 2026-11-23: no manual steps; the server gives and takes the phone items itself
                phone_two_items = { 'ped', 'client', true },
                phone_drop_active = { 'ped', 'client', true },
                phone_no_item = { 'ped', 'client', true },
                phone_device_save = { 'mock', 'server', true },
            }
            local m = by_name(ST.definitions())
            for name, kw in pairs(want) do
                local test, err = rules.normalize(m[name])
                assert.is_nil(err, name)
                assert.are.equal(kw[1], test.kind, name)
                assert.are.equal(kw[2], test.side, name)
                assert.are.equal(1, test.players, name)
                assert.are.equal(kw[3], test.destructive, name)
                assert.is_nil(test.ask, name)
            end
        end)

        it('takes the ped expect strings from the package locale, and has none for the others', function()
            local m = by_name(ST.definitions(function(key) return 'T:' .. key end))
            for _, name in ipairs({ 'stash_open', 'phone_two_items', 'phone_drop_active', 'phone_no_item' }) do
                assert.are.equal('T:invkit.selftest.' .. name .. '.expect', m[name].expect)
            end
            for _, name in ipairs({ 'stash_id', 'use_state_machine', 'phone_item_map', 'item_use',
                'phone_device_save' }) do
                assert.is_nil(m[name].expect, name)
            end
        end)

        it('names the fold and slab items from Config.phone.items in the phone_two_items instruction', function()
            natives.stub('Locales', {})
            assert(loadfile(DIR .. '/locales/en.lua'))()
            local function t(key, vars)
                return (Locales.en[key]:gsub('{(%w+)}', function(k) return tostring(vars and vars[k]) end))
            end
            local items = { my_fold = 'fold', big_slab = 'slab', phone = 'slab' }
            local m = by_name(ST.definitions(t, { phone = { items = items } }))
            assert.are.equal('The test gives you a my_fold and a big_slab item for a moment', m.phone_two_items.expect)
            local shipped = by_name(ST.definitions(t, { phone = { items = SHIPPED_ITEMS } }))
            assert.are.equal('The test gives you a phone_fold and a phone_slab item for a moment', shipped.phone_two_items.expect)
        end)

        it('has the expect string in en and th within core limits', function()
            natives.stub('Locales', {})
            assert(loadfile(DIR .. '/locales/en.lua'))()
            assert(loadfile(DIR .. '/locales/th.lua'))()
            for _, lang in ipairs({ 'en', 'th' }) do
                local m = by_name(ST.definitions(function(key) return Locales[lang][key] end))
                for _, name in ipairs({ 'stash_open', 'phone_two_items', 'phone_drop_active', 'phone_no_item' }) do
                    assert.is_string(m[name].expect, lang .. ' ' .. name)
                    assert.is_true(utf8.len(m[name].expect) <= 240, lang .. ' ' .. name)
                end
            end
        end)

        it('tells the presser what to do on every ped row, in en and th', function()
            natives.stub('Locales', {})
            assert(loadfile(DIR .. '/locales/en.lua'))()
            assert(loadfile(DIR .. '/locales/th.lua'))()
            local function t(lang)
                return function(key, vars)
                    return (Locales[lang][key]:gsub('{(%w+)}', function(k) return tostring(vars and vars[k]) end))
                end
            end
            local cfg = { phone = { items = SHIPPED_ITEMS } }
            local en = by_name(ST.definitions(t('en'), cfg))
            assert.are.equal('The test moves you to a stash point and away from it, then back where you stood', en.stash_open.expect)
            assert.are.equal('The test gives you a phone_fold and a phone_slab item for a moment', en.phone_two_items.expect)
            assert.are.equal('The test gives you two phone items, then takes one back', en.phone_drop_active.expect)
            assert.are.equal('The test puts your phone items aside for a moment, then gives them back', en.phone_no_item.expect)
            local th = by_name(ST.definitions(t('th'), cfg))
            for _, name in ipairs({ 'stash_open', 'phone_two_items', 'phone_drop_active', 'phone_no_item' }) do
                assert.is_true(utf8.len(th[name].expect) > 0 and utf8.len(th[name].expect) <= 240, name)
            end
            assert.truthy(th.phone_two_items.expect:find('phone_fold', 1, true))
        end)

        it('lets core skip the ox_inventory rows when ox_inventory is not started', function()
            local m = by_name(ST.definitions())
            assert.are.same({ resources = { 'ox_inventory' } }, m.stash_open.skipWhen)
            assert.are.same({ resources = { 'ox_inventory' } }, m.item_use.skipWhen)
            assert.are.same({ resources = { 'ox_inventory' } }, m.phone_device_save.skipWhen)
            for _, name in ipairs({ 'phone_two_items', 'phone_drop_active', 'phone_no_item' }) do
                assert.are.same({ resources = { 'ox_inventory', 'aeterna_phonekit' } }, m[name].skipWhen, name)
            end
            for _, name in ipairs({ 'stash_id', 'use_state_machine', 'phone_item_map' }) do
                assert.is_nil(m[name].skipWhen, name)
            end
        end)

        it('gives phone_device_save time for one held save window and stash_open time to walk', function()
            local m = by_name(ST.definitions())
            assert.is_true(m.phone_device_save.timeout > ST.SAVE_WAIT_MS)
            assert.is_true(ST.SAVE_WAIT_MS > InvkitPhoneLogic.SAVE_WINDOW_MS)
            assert.is_true(m.stash_open.timeout > ST.STASH_WATCH_MS)
            assert.is_true(m.item_use.timeout > ST.ITEM_WAIT_MS + ST.USE_WAIT_MS)
            for _, name in ipairs({ 'phone_two_items', 'phone_drop_active', 'phone_no_item' }) do
                assert.is_true(m[name].timeout > ST.PHONE_WATCH_MS, name)
            end
        end)

        it('maps full names to short names only for its own prefix', function()
            assert.are.equal('stash_id', ST.shortName('aeterna_invkit.stash_id'))
            assert.is_nil(ST.shortName('aeterna_hudkit.stash_id'))
            assert.is_nil(ST.shortName('aeterna_invkit.nope'))
        end)
    end)

    describe('skip reasons (only the listed ones)', function()
        local cfg = { stash = { points = { { coords = { x = 1, y = 2, z = 3 }, radius = 2.0 } } },
            phone = { enabled = true, items = SHIPPED_ITEMS } }

        it('phone_item_map skips only when phone item mode is off', function()
            assert.is_nil(ST.skipReason('phone_item_map', cfg, { oxStarted = false }))
            assert.are.equal('Config.phone.enabled = false',
                ST.skipReason('phone_item_map', { phone = { enabled = false } }, { oxStarted = true }))
        end)

        it('names a missing phone.enabled as nil, not as false', function()
            assert.are.equal('Config.phone.enabled = nil', ST.skipReason('phone_item_map', { phone = {} }, {}))
            assert.are.equal('Config.phone.enabled = nil', ST.skipReason('phone_item_map', {}, {}))
        end)

        it('item_use skips only without ox_inventory', function()
            assert.is_nil(ST.skipReason('item_use', { phone = { enabled = false } }, { oxStarted = true }))
            assert.are.equal('needs ox_inventory', ST.skipReason('item_use', cfg, { oxStarted = false }))
        end)

        it('the phone ped rows skip without ox_inventory, without phonekit, or with phone item mode off', function()
            for _, name in ipairs({ 'phone_two_items', 'phone_drop_active', 'phone_no_item' }) do
                local both = { oxStarted = true, phonekitStarted = true }
                assert.is_nil(ST.skipReason(name, cfg, both), name)
                assert.are.equal('needs ox_inventory', ST.skipReason(name, cfg, { oxStarted = false,
                    phonekitStarted = true }))
                assert.are.equal('needs aeterna_phonekit', ST.skipReason(name, cfg, { oxStarted = true,
                    phonekitStarted = false }))
                assert.are.equal('Config.phone.enabled = false',
                    ST.skipReason(name, { phone = { enabled = false } }, both))
            end
        end)

        it('stash_open skips without ox_inventory or without a stash point', function()
            assert.is_nil(ST.skipReason('stash_open', cfg, { oxStarted = true }))
            assert.are.equal('needs ox_inventory', ST.skipReason('stash_open', cfg, { oxStarted = false }))
            assert.are.equal('no stash point configured',
                ST.skipReason('stash_open', { stash = { points = {} } }, { oxStarted = true }))
        end)

        it('phone_device_save skips without ox_inventory or with phone item mode off', function()
            assert.is_nil(ST.skipReason('phone_device_save', cfg, { oxStarted = true }))
            assert.are.equal('needs ox_inventory', ST.skipReason('phone_device_save', cfg, { oxStarted = false }))
            assert.are.equal('Config.phone.enabled = false',
                ST.skipReason('phone_device_save', { phone = { enabled = false } }, { oxStarted = true }))
        end)

        it('phone_device_save skips with needs a presser on a run nobody pressed', function()
            assert.are.equal('needs a presser',
                ST.skipReason('phone_device_save', cfg, { oxStarted = true, presser = false }))
        end)

        it('never skips the two 0.1 headless rows', function()
            for _, name in ipairs({ 'stash_id', 'use_state_machine' }) do
                assert.is_nil(ST.skipReason(name, {}, { oxStarted = false }), name)
            end
        end)
    end)

    describe('stash_id', function()
        it('passes with the shipped InvkitLogic', function()
            assert.are.equal('pass', (ST.stashIdCheck(InvkitLogic)))
        end)

        it('fails naming the case that is wrong', function()
            local broken = setmetatable({ stashId = function() return 'aeterna_stash:x', nil end },
                { __index = InvkitLogic })
            local state, detail = ST.stashIdCheck(broken)
            assert.are.equal('fail', state)
            assert.truthy(detail:find('character', 1, true))
        end)
    end)

    describe('use_state_machine', function()
        it('passes with the shipped use manager', function()
            local state, detail = ST.useStateMachine(InvkitLogic)
            assert.are.equal('pass', state)
            assert.is_string(detail)
        end)

        it('fails when done is accepted too early', function()
            local real = InvkitLogic.createUseManager
            local broken = setmetatable({ createUseManager = function(opts)
                local m = real(opts)
                local done = m.done
                function m:done(src, useId)
                    local p = self:getPending(src)
                    if p then p.startedAt = -1e9 end
                    return done(self, src, useId)
                end
                return m
            end }, { __index = InvkitLogic })
            local state, detail = ST.useStateMachine(broken)
            assert.are.equal('fail', state)
            assert.truthy(detail:find('early', 1, true))
        end)
    end)

    describe('phone_item_map', function()
        it('passes for the shipped map', function()
            local state, detail = ST.phoneItemMap(InvkitPhoneLogic, SHIPPED_ITEMS)
            assert.are.equal('pass', state)
            assert.truthy(detail:find('9', 1, true))
        end)

        it('fails listing skipped entries', function()
            local state, detail = ST.phoneItemMap(InvkitPhoneLogic, { phone = 'slab', phone_x = 'toaster' })
            assert.are.equal('fail', state)
            assert.truthy(detail:find('phone_x', 1, true))
        end)

        it('fails when nothing is mapped', function()
            assert.are.equal('fail', (ST.phoneItemMap(InvkitPhoneLogic, {})))
        end)
    end)

    describe('stash_open watch', function()
        it('passes once it opened at a point and was refused away from it', function()
            local w = ST.newStashWatch(false)
            assert.is_true(w.needs(true))
            assert.is_false(w.record(true, 'opened'))
            assert.is_false(w.needs(true))
            assert.is_true(w.needs(false))
            assert.is_true(w.record(false, 'refused', 'invkit.stash.far'))
            assert.are.equal('pass', (w.verdict()))
        end)

        it('with anywhere = true one opening is enough', function()
            local w = ST.newStashWatch(true)
            assert.is_false(w.needs(false))
            assert.is_true(w.record(true, 'opened'))
            assert.are.equal('pass', (w.verdict()))
        end)

        it('fails when refused at a stash point', function()
            local w = ST.newStashWatch(false)
            assert.is_true(w.record(true, 'refused', 'invkit.stash.far'))
            local state, detail, extra = w.verdict()
            assert.are.equal('fail', state)
            assert.truthy(detail:find('refused at a stash point', 1, true))
            assert.are.equal(1, extra.step)
        end)

        it('fails when the stash opened away from every point', function()
            local w = ST.newStashWatch(false)
            w.record(true, 'opened')
            assert.is_true(w.record(false, 'opened'))
            local state, _, extra = w.verdict()
            assert.are.equal('fail', state)
            assert.are.equal(2, extra.step)
            assert.are.equal('invkit.stash.far', extra.expected)
        end)

        it('fails when nothing happened', function()
            local w = ST.newStashWatch(false)
            w.record(true, 'none')
            assert.are.equal('fail', (w.verdict()))
        end)

        it('fails naming the side that was never checked', function()
            local w = ST.newStashWatch(false)
            w.record(true, 'opened')
            local state, detail = w.verdict()
            assert.are.equal('fail', state)
            assert.truthy(detail:find('away', 1, true))
        end)
    end)

    describe('phone rows driven by the server (owner 2026-11-23: no manual steps)', function()
        local function ids()
            local n = 0
            return function() n = n + 1 return ('0000000%d'):format(n) end
        end
        local map = { phone = 'slab', phone_slab = 'slab', phone_fold = 'fold' }

        it('phone_two_items gives a fold and a slab item, tagged, each with its own id and a battery', function()
            local plan = assert(ST.phonePlan('phone_two_items', map, 'r1-abcd', ids()))
            assert.are.equal(2, #plan.give)
            assert.are.equal('phone_fold', plan.give[1].item)
            assert.are.equal('phone_slab', plan.give[2].item)
            for _, g in ipairs(plan.give) do
                assert.are.equal('r1-abcd', g.metadata.aeterna_selftest)
                assert.is_number(g.metadata.battery)
            end
            assert.are_not.equal(plan.give[1].metadata.phoneId, plan.give[2].metadata.phoneId)
            assert.is_nil(plan.drop)
            assert.is_false(plan.takeAway)
        end)

        it('phone_drop_active gives two and takes the second back after a pause', function()
            local plan = assert(ST.phonePlan('phone_drop_active', map, 'r1-abcd', ids()))
            assert.are.equal(2, #plan.give)
            assert.are.equal(2, plan.drop)
            assert.is_true(ST.PHONE_DROP_DELAY_MS >= 1000 and ST.PHONE_DROP_DELAY_MS < ST.PHONE_WATCH_MS)
        end)

        it('phone_no_item gives nothing and puts the presser\'s own phone items aside', function()
            local plan = assert(ST.phonePlan('phone_no_item', map, 'r1-abcd', ids()))
            assert.are.equal(0, #plan.give)
            assert.is_true(plan.takeAway)
        end)

        it('refuses a plan when no item maps to a model it needs', function()
            local plan, err = ST.phonePlan('phone_two_items', { phone = 'slab' }, 'r1-abcd', ids())
            assert.is_nil(plan)
            assert.are.equal('no phone item maps to fold', err)
        end)

        it('stash_open stops at the first point, then away from every point', function()
            local points = { { coords = { x = 10.0, y = 0.0, z = 5.0 }, radius = 2.0 } }
            local stops = ST.stashStops(points)
            assert.are.equal(2, #stops)
            assert.are.same({ x = 10.0, y = 0.0, z = 5.0 }, stops[1])
            local dx = stops[2].x - 10.0
            assert.is_true(math.abs(dx) > 2.0 + 5.0)
            assert.is_nil(ST.stashStops({}))
        end)

        it('stash_open reads a vector3 point the way invkit does (live W3 r3-v5p2: "not checked at a stash point")', function()
            local vec = setmetatable({ x = 195.0, y = -933.0, z = 30.7 }, {})
            local asked = 0
            local stops = ST.stashStops({ { coords = vec, radius = 2.0 } }, function() asked = asked + 1 return 'vector3' end)
            assert.is_true(asked > 0) -- type() of a game vector3 is 'vector3', not 'table'
            assert.are.same({ x = 195.0, y = -933.0, z = 30.7 }, stops[1])
        end)
    end)

    describe('phone_device_save', function()
        it('uses the first mapped item name as the test phone', function()
            local map = InvkitPhoneLogic.validateItemMap(SHIPPED_ITEMS)
            assert.are.equal('phone', ST.testPhoneItem(map))
            assert.is_nil(ST.testPhoneItem({}))
        end)

        -- kit-test W3 2026-11-23: a phone given without a battery gets phonekit's start battery written once,
        -- and that write landed after the test's own save (got 100, expected 42).
        it('gives the test phone with a battery already set, unlike the saved one', function()
            local md = ST.testPhoneMetadata('abcd1234')
            assert.are.equal('abcd1234', md.phoneId)
            assert.is_number(md.battery)
            assert.are_not.equal(ST.SAVE.battery, md.battery)
        end)

        it('reports mock with restored when the metadata was written and the item removed', function()
            local state, _, extra = ST.deviceSaveVerdict({ given = true, metadata = { phoneId = 'abcd1234',
                battery = 42, fold = 'closed' }, id = 'abcd1234', gone = true })
            assert.are.equal('mock', state)
            assert.is_true(extra.restored)
            assert.is_nil(extra.wrote)
        end)

        it('fails without writing when the write guard says no', function()
            local state, detail, extra = ST.deviceSaveVerdict({ guard = false })
            assert.are.equal('fail', state)
            assert.truthy(detail:find('write guard', 1, true))
            assert.is_true(extra.restored)
        end)

        it('fails when the item could not be given', function()
            local state, detail = ST.deviceSaveVerdict({ given = false, item = 'phone' })
            assert.are.equal('fail', state)
            assert.truthy(detail:find('phone', 1, true))
        end)

        it('fails naming the field that was not written', function()
            local state, detail, extra = ST.deviceSaveVerdict({ given = true, id = 'abcd1234', gone = true,
                metadata = { phoneId = 'abcd1234', battery = 100, fold = 'closed' } })
            assert.are.equal('fail', state)
            assert.truthy(detail:find('battery', 1, true))
            assert.is_true(extra.restored)
        end)

        it('never claims restored while the test phone is still carried', function()
            local state, _, extra = ST.deviceSaveVerdict({ given = true, id = 'abcd1234', gone = false,
                metadata = { phoneId = 'abcd1234', battery = 42, fold = 'closed' } })
            assert.are.equal('fail', state)
            assert.is_false(extra.restored)
        end)
    end)

    describe('item_use', function()
        it('picks the first test item no other resource has registered', function()
            assert.are.equal(ST.USE_ITEMS[1], ST.pickUseItem(function() return false end))
            assert.are.equal(ST.USE_ITEMS[2], ST.pickUseItem(function(n) return n == ST.USE_ITEMS[1] end))
            assert.is_nil(ST.pickUseItem(function() return true end))
        end)

        it('uses a valid usable definition with a short progress bar', function()
            assert.is_true((InvkitLogic.validateUsableDef(ST.USE_ITEMS[1], ST.USE_DEF)))
            assert.is_true(ST.USE_DEF.duration < ST.USE_WAIT_MS)
        end)

        it('reports mock with restored when one item went, one use ran and nothing is left', function()
            local state, _, extra = ST.itemUseVerdict({ before = 1, uses = 1, after = 0 })
            assert.are.equal('mock', state)
            assert.is_true(extra.restored)
        end)

        it('fails when the test item never arrived', function()
            local state, detail, extra = ST.itemUseVerdict({ before = 0, uses = 0, after = 0 })
            assert.are.equal('fail', state)
            assert.truthy(detail:find('never arrived', 1, true))
            assert.are.equal(1, extra.step)
        end)

        it('fails when the progress bar did not run exactly once', function()
            local state, _, extra = ST.itemUseVerdict({ before = 1, uses = 2, after = 0 })
            assert.are.equal('fail', state)
            assert.are.equal(2, extra.step)
        end)

        it('fails and never claims restored while the test item is still carried', function()
            local state, detail, extra = ST.itemUseVerdict({ before = 1, uses = 1, after = 1 })
            assert.are.equal('fail', state)
            assert.truthy(detail:find('not removed', 1, true))
            assert.is_false(extra.restored)
        end)
    end)

    describe('phone ped watches', function()
        local map = InvkitPhoneLogic and nil
        local function slots(list)
            local out = {}
            for i, e in ipairs(list) do
                out[i] = { slot = i, name = e[1], metadata = { phoneId = e[2], battery = e[3] } }
            end
            return out
        end
        local function devices(list)
            return ST.devicesFrom(InvkitPhoneLogic, slots(list), InvkitPhoneLogic.validateItemMap(SHIPPED_ITEMS))
        end

        it('builds the device list invkit would answer from the presser inventory', function()
            local d = devices({ { 'phone_fold', 'aaaa0001', 64 }, { 'phone_slab', 'aaaa0002', 12 } })
            assert.are.equal(2, #d)
            assert.are.equal('fold', d[1].model)
            assert.are.equal(64, d[1].battery)
            assert.is_nil(map)
        end)

        it('phone_two_items passes once a fold and a slab are carried, naming both batteries', function()
            local w = ST.newPhoneWatch('phone_two_items')
            assert.is_false(w.observe(devices({ { 'phone_fold', 'aaaa0001', 64 } })))
            assert.is_true(w.observe(devices({ { 'phone_fold', 'aaaa0001', 64 }, { 'phone_slab', 'aaaa0002', 12 } })))
            local state, detail = w.verdict()
            assert.are.equal('pass', state)
            assert.truthy(detail:find('64', 1, true))
            assert.truthy(detail:find('inventory shows', 1, true))
            assert.falsy(detail:find('answers', 1, true))
        end)

        it('phone_two_items fails naming the missing model', function()
            local w = ST.newPhoneWatch('phone_two_items')
            w.observe(devices({ { 'phone_fold', 'aaaa0001', 64 } }))
            local state, detail = w.verdict()
            assert.are.equal('fail', state)
            assert.truthy(detail:find('slab', 1, true))
        end)

        it('phone_drop_active passes once one of two phones left and the other stayed', function()
            local w = ST.newPhoneWatch('phone_drop_active')
            assert.is_false(w.observe(devices({ { 'phone_fold', 'aaaa0001', 64 } })))
            assert.is_false(w.observe(devices({ { 'phone_fold', 'aaaa0001', 64 }, { 'phone_slab', 'aaaa0002', 12 } })))
            assert.is_true(w.observe(devices({ { 'phone_slab', 'aaaa0002', 12 } })))
            assert.are.equal('pass', (w.verdict()))
        end)

        it('phone_drop_active compares stable ids: a phone without phoneId is not taken for a new one', function()
            local w = ST.newPhoneWatch('phone_drop_active')
            assert.is_false(w.observe(devices({ { 'phone_fold', nil, 64 }, { 'phone_slab', nil, 12 } })))
            -- Same two phones, still carried: nothing was dropped.
            assert.is_false(w.observe(devices({ { 'phone_fold', nil, 64 }, { 'phone_slab', nil, 12 } })))
            -- The fold in slot 1 left; the slab in slot 2 stays.
            local after = ST.devicesFrom(InvkitPhoneLogic, { { slot = 2, name = 'phone_slab', metadata = { battery = 12 } } },
                InvkitPhoneLogic.validateItemMap(SHIPPED_ITEMS))
            assert.is_true(w.observe(after))
            local state, detail = w.verdict()
            assert.are.equal('pass', state)
            assert.truthy(detail:find('inventory shows', 1, true))
        end)

        it('phone_drop_active fails when the presser never carried two phones', function()
            local w = ST.newPhoneWatch('phone_drop_active')
            w.observe(devices({ { 'phone_fold', 'aaaa0001', 64 } }))
            w.observe(devices({}))
            local state, detail = w.verdict()
            assert.are.equal('fail', state)
            assert.truthy(detail:find('two phones', 1, true))
        end)

        it('phone_no_item passes once no phone item is carried', function()
            local w = ST.newPhoneWatch('phone_no_item')
            assert.is_false(w.observe(devices({ { 'phone', 'aaaa0003', 50 } })))
            assert.is_true(w.observe(devices({})))
            local state, detail = w.verdict()
            assert.are.equal('pass', state)
            assert.are.equal('inventory shows no phone item', detail)
        end)

        it('phone_no_item fails while a phone is still carried', function()
            local w = ST.newPhoneWatch('phone_no_item')
            w.observe(devices({ { 'phone', 'aaaa0003', 50 } }))
            local state, detail = w.verdict()
            assert.are.equal('fail', state)
            assert.truthy(detail:find('still carried', 1, true))
        end)

        it('a failed inventory read is never taken as no phone', function()
            local w = ST.newPhoneWatch('phone_no_item')
            assert.is_false(w.observe(nil))
            assert.are.equal('fail', (w.verdict()))
        end)
    end)

    describe('server wrapper', function()
        -- Fake ox_inventory: inv[src][slot] = { name, slot, count, metadata }.
        local env_guard
        local function boot(opts)
            opts = opts or {}
            env_guard = {}
            natives.reset({ resource = 'aeterna_invkit', side = 'server', invoker = 'aeterna_invkit' })
            natives.add_player(5, 'player5')
            natives.add_player(6, 'player6')
            local inv = { [5] = {}, [6] = {} }
            local ox = { inv = inv, added = {}, removed = {}, removeCalls = {} }
            for i, it in ipairs(opts.carried or {}) do inv[5][i] = it end
            natives.stub_export('ox_inventory', 'Search', function(src, _, names)
                if opts.searchFails then return false end
                local out = {}
                for _, name in ipairs(names) do
                    out[name] = {}
                    for _, slot in pairs(inv[tonumber(src)] or {}) do
                        if slot.name == name then out[name][#out[name] + 1] = slot end
                    end
                end
                if #names == 1 then return out[names[1]] end
                return out
            end)
            natives.stub_export('ox_inventory', 'SetMetadata', function(src, slot, metadata)
                inv[tonumber(src)][slot].metadata = metadata
            end)
            natives.stub_export('ox_inventory', 'AddItem', function(src, item, count, metadata)
                if opts.addFails then return false, 'invalid_item' end
                local items = inv[tonumber(src)]
                local slot = #items + 1
                items[slot] = { name = item, slot = slot, count = count, metadata = metadata }
                ox.added[#ox.added + 1] = item
                return true
            end)
            natives.stub_export('ox_inventory', 'RemoveItem', function(src, item, count, metadata, slot)
                local items = inv[tonumber(src)]
                ox.removed[#ox.removed + 1] = item
                ox.removeCalls[#ox.removeCalls + 1] = { item = item, metadata = metadata, slot = slot }
                for k, it in pairs(items) do
                    local md = it.metadata or {}
                    local match = it.name == item and (slot == nil or slot == k)
                    -- ox_inventory matches metadata as a whole (live W3 r3-v5p2: a { phoneId } remove missed a
                    -- phone whose metadata also carried battery)
                    if metadata then
                        for mk, mv in pairs(metadata) do if md[mk] ~= mv then match = false end end
                        for mk, mv in pairs(md) do if metadata[mk] ~= mv then match = false end end
                    end
                    if match then items[k] = nil; return true end
                end
                return false
            end)
            natives.stub_export('ox_inventory', 'GetItemCount', function(src, item)
                local n = 0
                for _, it in pairs(inv[tonumber(src)] or {}) do
                    if it.name == item then n = n + (it.count or 1) end
                end
                return n
            end)
            ox.hooks = {}
            natives.stub_export('ox_inventory', 'registerHook', function(event, fn)
                ox.hooks[event] = fn
                return 1
            end)
            natives.stub_export('ox_inventory', 'removeHooks', function() end)
            natives.stub('GetResourceState', function(name)
                if name == 'ox_inventory' then return 'started' end
                return 'missing'
            end)
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
                t = function(k) return k end,
                rateLimit = function() return true end,
                selftest = { mayWrite = function(runId, name)
                    env_guard[#env_guard + 1] = name
                    return opts.mayWrite ~= false
                end },
            })
            natives.stub('Config', {
                stash = { scope = 'character', slots = 40, maxWeight = 100000, label = 'invkit.stash.label', points = {} },
                phone = { enabled = opts.phone ~= false, items = SHIPPED_ITEMS },
            })
            natives.spy('RegisterCommand')
            local added, reports = {}, {}
            natives.stub_export('aeterna_core', 'addSelftest', function(name, meta)
                added[#added + 1] = { name = name, meta = meta }
                return true
            end)
            natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail, extra)
                reports[#reports + 1] = { name = name, ok = ok, detail = detail, extra = extra }
                return true
            end)
            resource.load_resource(DIR, 'server', { skip = { ['config.lua'] = true } })
            natives.advance(0)
            return { added = added, reports = reports, ox = ox, inv = inv, guard = env_guard }
        end

        it('registers the rows with aeterna_core on start', function()
            local env = boot()
            assert.are.equal(9, #env.added)
            assert.are.equal('stash_id', env.added[1].name)
            assert.are.equal('phone_device_save', env.added[9].name)
        end)

        it('answers the three headless rows', function()
            local env = boot()
            for _, n in ipairs({ 'stash_id', 'use_state_machine', 'phone_item_map' }) do
                fireAsCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_invkit.' .. n, { kind = 'headless' })
            end
            fireAsCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_hudkit.stash_id', { kind = 'headless' })
            natives.advance(0)
            assert.are.equal(3, #env.reports)
            for _, r in ipairs(env.reports) do assert.are.equal('pass', r.ok, r.name) end
        end)

        it('phone_item_map reports skip when phone item mode is off', function()
            local env = boot({ phone = false })
            fireAsCore('aeterna_core:selftest', 'r1-abcd', 'aeterna_invkit.phone_item_map', { kind = 'headless' })
            natives.advance(0)
            assert.are.equal('skip', env.reports[1].ok)
            assert.are.equal('Config.phone.enabled = false', env.reports[1].detail)
        end)

        it('phone_device_save gives a test phone, writes battery 42 and fold closed, then removes it', function()
            local env = boot()
            fireAsCore('aeterna_core:selftest', 'r2-abcd', 'aeterna_invkit.phone_device_save',
                { kind = 'mock', side = 'server', a = 5, destructive = true })
            natives.advance(10000)
            assert.are.equal(1, #env.reports)
            assert.are.equal('mock', env.reports[1].ok)
            assert.is_true(env.reports[1].extra.restored)
            assert.is_nil(env.reports[1].extra.wrote)
            assert.are.same({ 'phone' }, env.ox.added)
            assert.are.same({ 'phone' }, env.ox.removed)
            assert.is_nil(next(env.inv[5]))
            assert.is_true(#env.guard >= 1)
        end)

        it('phone_device_save removes its phone by phoneId, never by a slot it guessed', function()
            local env = boot({ carried = { { name = 'phone', slot = 1, count = 1, metadata = { phoneId = 'own00001' } } } })
            fireAsCore('aeterna_core:selftest', 'r2-abcd', 'aeterna_invkit.phone_device_save',
                { kind = 'mock', side = 'server', a = 5, destructive = true })
            natives.advance(10000)
            assert.are.equal(1, #env.ox.removeCalls)
            local call = env.ox.removeCalls[1]
            assert.are.equal(2, call.slot) -- the slot of the phone it gave, found by that phone's phoneId
            assert.are.equal('own00001', env.inv[5][1].metadata.phoneId)
            assert.are.equal('mock', env.reports[1].ok)
        end)

        it('phone_device_save never claims restored when it cannot read the inventory back', function()
            local env = boot({ searchFails = true })
            fireAsCore('aeterna_core:selftest', 'r2-abcd', 'aeterna_invkit.phone_device_save',
                { kind = 'mock', side = 'server', a = 5, destructive = true })
            natives.advance(10000)
            assert.are.equal('fail', env.reports[1].ok)
            -- The phone it gave is removed by its phoneId all the same, and the count tells it is gone.
            assert.is_nil(next(env.inv[5]))
            assert.is_true(env.reports[1].extra.restored)
        end)

        it('phone_device_save gives nothing when the write guard says no', function()
            local env = boot({ mayWrite = false })
            fireAsCore('aeterna_core:selftest', 'r2-abcd', 'aeterna_invkit.phone_device_save',
                { kind = 'mock', side = 'server', a = 5, destructive = true })
            natives.advance(10000)
            assert.are.equal('fail', env.reports[1].ok)
            assert.are.same({}, env.ox.added)
        end)

        it('phone_device_save skips with needs a presser when nobody pressed', function()
            local env = boot()
            fireAsCore('aeterna_core:selftest', 'r3-abcd', 'aeterna_invkit.phone_device_save',
                { kind = 'mock', side = 'server', destructive = true })
            natives.advance(0)
            assert.are.equal('skip', env.reports[1].ok)
            assert.are.equal('needs a presser', env.reports[1].detail)
            assert.are.same({}, env.ox.added)
        end)

        it('phone_drop_active: gives two tagged phones, takes one back, and selftestEnd takes the other', function()
            local env = boot()
            fireAsCore('aeterna_core:selftestStarted', 'r9-abcd', 'aeterna_invkit.phone_drop_active',
                { kind = 'ped', a = 5, destructive = true })
            natives.advance(0)
            assert.are.equal(2, #env.ox.added)
            local kept = 0
            for _, it in pairs(env.inv[5]) do if it.metadata.aeterna_selftest == 'r9-abcd' then kept = kept + 1 end end
            assert.are.equal(2, kept)
            natives.advance(ST.PHONE_DROP_DELAY_MS + 10)
            kept = 0
            for _ in pairs(env.inv[5]) do kept = kept + 1 end
            assert.are.equal(1, kept)
            fireAsCore('aeterna_core:selftestEnd', 'r9-abcd', 'aeterna_invkit.phone_drop_active')
            natives.advance(0)
            assert.is_nil(next(env.inv[5]))
            assert.are.equal(0, #env.reports) -- the client reports
        end)

        it('phone_no_item: puts the presser\'s own phones aside and gives them back with their metadata', function()
            local env = boot({ carried = { { name = 'phone', slot = 1, count = 1, metadata = { phoneId = 'aaaa0001', battery = 77 } } } })
            fireAsCore('aeterna_core:selftestStarted', 'r9-abcd', 'aeterna_invkit.phone_no_item',
                { kind = 'ped', a = 5, destructive = true })
            natives.advance(0)
            assert.is_nil(next(env.inv[5]))
            fireAsCore('aeterna_core:selftestEnd', 'r9-abcd', 'aeterna_invkit.phone_no_item')
            natives.advance(0)
            local _, back = next(env.inv[5])
            assert.are.equal('phone', back.name)
            assert.are.same({ phoneId = 'aaaa0001', battery = 77 }, back.metadata)
        end)

        it('phone rows give nothing when the write guard refuses', function()
            local env = boot({ mayWrite = false })
            fireAsCore('aeterna_core:selftestStarted', 'r9-abcd', 'aeterna_invkit.phone_two_items',
                { kind = 'ped', a = 5, destructive = true })
            natives.advance(0)
            assert.are.same({}, env.ox.added)
        end)

        it('item_use: on selftestStarted gives one tagged test item, registers it and starts the use', function()
            local env = boot()
            fireAsCore('aeterna_core:selftestStarted', 'r7-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            natives.advance(0)
            assert.are.same({ ST.USE_ITEMS[1] }, env.ox.added)
            assert.are.equal('r7-abcd', env.inv[5][1].metadata.aeterna_selftest)
            assert.are.same({ 'aeterna_invkit.item_use' }, env.guard)
            natives.advance(ST.USE_START_DELAY_MS + 10)
            local use = natives.last_emitted('client', 'aeterna_invkit:cl:use')
            assert.is_truthy(use)
            assert.are.equal(5, use.target)
            -- No report from the server for a client test.
            assert.are.equal(0, #env.reports)
        end)

        it('item_use: selftestEnd removes the tagged item and the registration, and nothing else', function()
            local env = boot({ carried = { { name = ST.USE_ITEMS[1], slot = 1, count = 3, metadata = {} } } })
            fireAsCore('aeterna_core:selftestStarted', 'r8-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            natives.advance(0)
            fireAsCore('aeterna_core:selftestEnd', 'r8-abcd', 'aeterna_invkit.item_use')
            natives.advance(ST.USE_START_DELAY_MS + 10)
            assert.are.equal(1, #env.ox.removeCalls)
            assert.are.equal('r8-abcd', env.ox.removeCalls[1].metadata.aeterna_selftest)
            assert.are.equal(3, env.inv[5][1].count)
            assert.is_nil(natives.last_emitted('client', 'aeterna_invkit:cl:use'))
        end)

        it('item_use: another player using the same item during the test goes to ox untouched', function()
            local env = boot({ carried = {} })
            env.inv[6][1] = { name = ST.USE_ITEMS[1], slot = 1, count = 2, metadata = {} }
            fireAsCore('aeterna_core:selftestStarted', 'r7-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            natives.advance(0)
            local verdict = env.ox.hooks.usingItem({ source = 6, item = { name = ST.USE_ITEMS[1], slot = 1, metadata = {} } })
            assert.is_nil(verdict) -- nil = ox goes on with its own use
            for _, e in ipairs(natives.emitted('client', 'aeterna_invkit:cl:use')) do
                assert.are_not.equal(6, e.target)
            end
            assert.are.equal(2, env.inv[6][1].count)
        end)

        it('item_use: the presser using an untagged item of the same name also goes to ox', function()
            local env = boot({ carried = { { name = ST.USE_ITEMS[1], slot = 1, count = 4, metadata = {} } } })
            fireAsCore('aeterna_core:selftestStarted', 'r7-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            natives.advance(0)
            local verdict = env.ox.hooks.usingItem({ source = 5, item = { name = ST.USE_ITEMS[1], slot = 1, metadata = {} } })
            assert.is_nil(verdict)
            assert.is_nil(natives.last_emitted('client', 'aeterna_invkit:cl:use'))
        end)

        it('item_use: the tagged test item is taken by the test', function()
            local env = boot()
            fireAsCore('aeterna_core:selftestStarted', 'r7-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            natives.advance(0)
            local slot = env.inv[5][1]
            local verdict = env.ox.hooks.usingItem({ source = 5, item = { name = slot.name, slot = slot.slot,
                metadata = slot.metadata } })
            assert.is_false(verdict)
            assert.are.equal(5, natives.last_emitted('client', 'aeterna_invkit:cl:use').target)
        end)

        it('item_use: the delayed start asks the write guard again', function()
            local env = boot()
            fireAsCore('aeterna_core:selftestStarted', 'r7-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            natives.advance(0)
            natives.stub('AeternaCore', setmetatable({ selftest = { mayWrite = function() return false end } },
                { __index = AeternaCore }))
            natives.advance(ST.USE_START_DELAY_MS + 10)
            assert.is_nil(natives.last_emitted('client', 'aeterna_invkit:cl:use'))
        end)

        it('item_use: when aeterna_invkit itself stops, the tagged item goes', function()
            local env = boot()
            fireAsCore('aeterna_core:selftestStarted', 'r7-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            natives.advance(0)
            natives.fire('onResourceStop', 'aeterna_invkit')
            assert.are.equal(1, #env.ox.removeCalls)
            assert.are.equal('r7-abcd', env.ox.removeCalls[1].metadata.aeterna_selftest)
        end)

        it('item_use: a used event from another resource changes nothing', function()
            local env = boot()
            fireAsCore('aeterna_core:selftestStarted', 'r7-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            natives.advance(0)
            natives.stub('GetInvokingResource', function() return 'other_res' end)
            natives.fire('aeterna_invkit:used', 5, { owner = 'aeterna_invkit', item = ST.USE_ITEMS[1] })
            natives.stub('GetInvokingResource', function() return 'aeterna_invkit' end)
            assert.is_not_nil(InvkitServerSelftestHooks.useManager:getUsable(ST.USE_ITEMS[1]))
        end)

        it('item_use: a selftestStarted from another resource gives nothing and registers nothing', function()
            local env = boot()
            natives.fire('aeterna_core:selftestStarted', 'r9-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            natives.advance(ST.USE_START_DELAY_MS + 10)
            assert.are.same({}, env.ox.added)
            assert.are.same({}, env.guard)
            assert.is_nil(natives.last_emitted('client', 'aeterna_invkit:cl:use'))
        end)

        it('item_use: when aeterna_core stops, the tagged item and the registration go', function()
            local env = boot()
            fireAsCore('aeterna_core:selftestStarted', 'r9-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            natives.advance(0)
            natives.fire('onResourceStop', 'aeterna_core')
            natives.advance(ST.USE_START_DELAY_MS + 10)
            assert.are.equal(1, #env.ox.removeCalls)
            assert.are.equal('r9-abcd', env.ox.removeCalls[1].metadata.aeterna_selftest)
            assert.is_nil(next(env.inv[5]))
            assert.is_nil(natives.last_emitted('client', 'aeterna_invkit:cl:use'))
            assert.is_nil(InvkitServerSelftestHooks.useManager:getUsable(ST.USE_ITEMS[1]))
        end)

        it('server rows ignore a selftest event from another resource', function()
            local env = boot()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_invkit.phone_device_save',
                { kind = 'mock', side = 'server', a = 5, destructive = true })
            natives.advance(10000)
            assert.are.equal(0, #env.reports)
            assert.are.same({}, env.ox.added)
        end)

        it('item_use: prepares nothing when the write guard says no or nobody pressed', function()
            local env = boot({ mayWrite = false })
            fireAsCore('aeterna_core:selftestStarted', 'r9-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', a = 5, destructive = true })
            fireAsCore('aeterna_core:selftestStarted', 'r9-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', destructive = true })
            natives.advance(ST.USE_START_DELAY_MS + 10)
            assert.are.same({}, env.ox.added)
            assert.is_nil(natives.last_emitted('client', 'aeterna_invkit:cl:use'))
        end)

        it('phone_device_save fails and gives nothing when ox refuses the item', function()
            local env = boot({ addFails = true })
            fireAsCore('aeterna_core:selftest', 'r4-abcd', 'aeterna_invkit.phone_device_save',
                { kind = 'mock', side = 'server', a = 5, destructive = true })
            natives.advance(10000)
            assert.are.equal('fail', env.reports[1].ok)
            assert.are.same({}, env.ox.removed)
        end)
    end)
    describe('client wrapper (stash_open)', function()
        local function boot_client(points)
            natives.reset({ resource = 'aeterna_invkit', side = 'client', invoker = 'aeterna_invkit' })
            natives.spy('RegisterCommand')
            natives.spy('RegisterKeyMapping')
            natives.spy('BeginTextCommandThefeedPost')
            natives.spy('AddTextComponentSubstringPlayerName')
            natives.spy('EndTextCommandThefeedPostTicker')
            natives.stub_export('aeterna_uikit', 'keyHints', function() end)
            natives.stub_export('aeterna_uikit', 'clearKeyHints', function() end)
            local closed = 0
            natives.stub_export('ox_inventory', 'closeInventory', function() closed = closed + 1 end)
            local inv = { count = 0, slots = {} }
            natives.stub_export('ox_inventory', 'Search', function(search, item, metadata)
                if search == 'count' then
                    if item == ST.USE_ITEMS[1] and type(metadata) == 'table' and metadata.aeterna_selftest == inv.runId then
                        return inv.count
                    end
                    return 0
                end
                if type(item) == 'table' and #item == 1 then return inv.slots[item[1]] or {} end
                local out = {}
                for _, n in ipairs(item) do out[n] = inv.slots[n] or {} end
                return out
            end)
            natives.stub_export('aeterna_uikit', 'progress', function() return true end)
            natives.stub('GetResourceState', function() return 'started' end)
            local bag = {}
            natives.stub('LocalPlayer', { state = bag })
            local reports = {}
            natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail, extra)
                reports[#reports + 1] = { name = name, ok = ok, detail = detail, extra = extra }
                return true
            end)
            resource.load_resource(DIR, 'client', {
                externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
            })
            Config.stash.points = points
            natives.advance(0)
            return { reports = reports, bag = bag, inv = inv, closed = function() return closed end }
        end

        local function opens()
            return #natives.emitted('server', 'aeterna_invkit:sv:open')
        end

        it('moves the presser to the point, then away, then back where they stood, and passes', function()
            local env = boot_client({ { coords = vector3(10.0, 10.0, 10.0), radius = 2.0 } })
            local moves = {}
            natives.stub('SetEntityCoords', function(h, x, y, z)
                moves[#moves + 1] = { x, y, z }
                natives.set_entity_coords(h, vector3(x, y, z))
            end)
            natives.stub('GetEntityHeading', function() return 45.0 end)
            natives.stub('SetEntityHeading', function() end)
            natives.set_entity_coords(1, vector3(50.0, 50.0, 10.0))
            fireAsCore('aeterna_core:selftest', 'r5-abcd', 'aeterna_invkit.stash_open', { kind = 'ped', role = 'A' })
            natives.advance(600)
            assert.are.equal(1, opens()) -- at the point
            env.bag.invOpen = true
            natives.advance(200)
            env.bag.invOpen = false
            natives.advance(600)
            assert.are.equal(2, opens()) -- away from it
            natives.fire_net('aeterna_invkit:cl:refused', 1, { item = 'stash', reason = 'invkit.stash.far' })
            natives.advance(1000)
            assert.are.equal(1, #env.reports)
            assert.are.equal('pass', env.reports[1].ok, env.reports[1].detail)
            assert.are.equal(1, env.closed())
            assert.are.same({ 50.0, 50.0, 10.0 }, moves[#moves]) -- back where they stood
        end)

        it('item_use: sees the tagged item, one use, the item gone, and reports mock with restored', function()
            local env = boot_client({})
            env.inv.runId = 'r7-abcd'
            fireAsCore('aeterna_core:selftest', 'r7-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', role = 'A', destructive = true })
            natives.advance(300)
            env.inv.count = 1
            natives.advance(600)
            natives.fire_net('aeterna_invkit:cl:use', 1, { useId = 'u0', label = 'Water', duration = 1500,
                cancelable = true })
            natives.advance(2000)
            natives.fire_net('aeterna_invkit:cl:use', 1, { useId = 'u1', label = ST.USE_DEF.label, duration = 1500,
                cancelable = true })
            env.inv.count = 0
            natives.advance(3000)
            assert.are.equal(1, #env.reports)
            assert.are.equal('mock', env.reports[1].ok)
            assert.is_true(env.reports[1].extra.restored)
            assert.is_truthy(natives.last_emitted('server', 'aeterna_invkit:sv:done'))
        end)

        it('item_use: fails when the test item never arrives', function()
            local env = boot_client({})
            env.inv.runId = 'r8-abcd'
            fireAsCore('aeterna_core:selftest', 'r8-abcd', 'aeterna_invkit.item_use',
                { kind = 'mock', side = 'client', role = 'A', destructive = true })
            natives.advance(ST.ITEM_WAIT_MS + ST.USE_WAIT_MS + 1000)
            assert.are.equal(1, #env.reports)
            assert.are.equal('fail', env.reports[1].ok)
        end)

        it('phone_no_item passes at once when no phone item is carried', function()
            local env = boot_client({})
            Config.phone.enabled = true
            fireAsCore('aeterna_core:selftest', 'r9-abcd', 'aeterna_invkit.phone_no_item', { kind = 'ped', role = 'A' })
            natives.advance(500)
            assert.are.equal(1, #env.reports)
            assert.are.equal('pass', env.reports[1].ok)
        end)

        it('phone rows report skip while phone item mode is off', function()
            local env = boot_client({})
            Config.phone.enabled = false
            fireAsCore('aeterna_core:selftest', 'r9-abcd', 'aeterna_invkit.phone_two_items', { kind = 'ped', role = 'A' })
            natives.advance(0)
            assert.are.equal('skip', env.reports[1].ok)
            assert.are.equal('Config.phone.enabled = false', env.reports[1].detail)
        end)

        it('ignores a selftest event from another resource', function()
            local env = boot_client({ { coords = vector3(10.0, 10.0, 10.0), radius = 2.0 } })
            natives.fire('aeterna_core:selftest', 'r6-abcd', 'aeterna_invkit.stash_open', { kind = 'ped', role = 'A' })
            natives.advance(100)
            assert.are.equal(0, #env.reports)
            assert.are.equal(0, opens())
        end)

        it('reports skip when no stash point is configured', function()
            local env = boot_client({})
            fireAsCore('aeterna_core:selftest', 'r6-abcd', 'aeterna_invkit.stash_open', { kind = 'ped', role = 'A' })
            natives.advance(0)
            assert.are.equal('skip', env.reports[1].ok)
            assert.are.equal('no stash point configured', env.reports[1].detail)
            assert.are.equal(0, opens())
        end)
    end)
end)
