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
        it('lists the buildable spec rows in spec order', function()
            local names = {}
            for i, d in ipairs(ST.definitions()) do names[i] = d.name end
            assert.are.same({ 'stash_id', 'use_state_machine', 'phone_item_map', 'stash_open', 'phone_device_save' },
                names)
        end)

        it('sets kind, side, players and destructive as the spec table says', function()
            local rules = assert(loadfile(CORE_DIR .. '/shared/logic/selftest.lua'))()
            local want = {
                stash_id = { 'headless', 'server', false },
                use_state_machine = { 'headless', 'server', false },
                phone_item_map = { 'headless', 'server', false },
                stash_open = { 'ped', 'client', false },
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

        it('takes the stash_open expect from the package locale, and has none for the others', function()
            local m = by_name(ST.definitions(function(key) return 'T:' .. key end))
            assert.are.equal('T:invkit.selftest.stash_open.expect', m.stash_open.expect)
            for _, name in ipairs({ 'stash_id', 'use_state_machine', 'phone_item_map', 'phone_device_save' }) do
                assert.is_nil(m[name].expect, name)
            end
        end)

        it('has the expect string in en and th within core limits', function()
            natives.stub('Locales', {})
            assert(loadfile(DIR .. '/locales/en.lua'))()
            assert(loadfile(DIR .. '/locales/th.lua'))()
            for _, lang in ipairs({ 'en', 'th' }) do
                local m = by_name(ST.definitions(function(key) return Locales[lang][key] end))
                assert.is_string(m.stash_open.expect, lang)
                assert.is_true(utf8.len(m.stash_open.expect) <= 240, lang)
            end
        end)

        it('lets core skip the ox_inventory rows when ox_inventory is not started', function()
            local m = by_name(ST.definitions())
            assert.are.same({ resources = { 'ox_inventory' } }, m.stash_open.skipWhen)
            assert.are.same({ resources = { 'ox_inventory' } }, m.phone_device_save.skipWhen)
            for _, name in ipairs({ 'stash_id', 'use_state_machine', 'phone_item_map' }) do
                assert.is_nil(m[name].skipWhen, name)
            end
        end)

        it('gives phone_device_save time for one held save window and stash_open time to walk', function()
            local m = by_name(ST.definitions())
            assert.is_true(m.phone_device_save.timeout > ST.SAVE_WAIT_MS)
            assert.is_true(ST.SAVE_WAIT_MS > InvkitPhoneLogic.SAVE_WINDOW_MS)
            assert.is_true(m.stash_open.timeout > ST.STASH_WATCH_MS)
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

    describe('phone_device_save', function()
        it('uses the first mapped item name as the test phone', function()
            local map = InvkitPhoneLogic.validateItemMap(SHIPPED_ITEMS)
            assert.are.equal('phone', ST.testPhoneItem(map))
            assert.is_nil(ST.testPhoneItem({}))
        end)

        it('reports mock with restored and wrote when the metadata was written and the item removed', function()
            local state, _, extra = ST.deviceSaveVerdict({ given = true, metadata = { phoneId = 'abcd1234',
                battery = 42, fold = 'closed' }, id = 'abcd1234', gone = true })
            assert.are.equal('mock', state)
            assert.is_true(extra.restored)
            assert.is_true(extra.wrote)
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

    describe('server wrapper', function()
        -- Fake ox_inventory: inv[src][slot] = { name, slot, count, metadata }.
        local function boot(opts)
            opts = opts or {}
            natives.reset({ resource = 'aeterna_invkit', side = 'server', invoker = 'aeterna_invkit' })
            natives.add_player(5, 'player5')
            local inv = { [5] = {} }
            local ox = { inv = inv, added = {}, removed = {} }
            natives.stub_export('ox_inventory', 'Search', function(src, _, names)
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
            natives.stub_export('ox_inventory', 'RemoveItem', function(src, item, count, _, slot)
                local items = inv[tonumber(src)]
                if items[slot] and items[slot].name == item then items[slot] = nil end
                ox.removed[#ox.removed + 1] = item
                return true
            end)
            natives.stub_export('ox_inventory', 'registerHook', function() return 1 end)
            natives.stub_export('ox_inventory', 'removeHooks', function() end)
            natives.stub('GetResourceState', function(name)
                if name == 'ox_inventory' then return 'started' end
                return 'missing'
            end)
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
                t = function(k) return k end,
                rateLimit = function() return true end,
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
            return { added = added, reports = reports, ox = ox, inv = inv }
        end

        it('registers the rows with aeterna_core on start', function()
            local env = boot()
            assert.are.equal(5, #env.added)
            assert.are.equal('stash_id', env.added[1].name)
            assert.are.equal('phone_device_save', env.added[5].name)
        end)

        it('answers the three headless rows', function()
            local env = boot()
            for _, n in ipairs({ 'stash_id', 'use_state_machine', 'phone_item_map' }) do
                natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_invkit.' .. n, { kind = 'headless' })
            end
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_hudkit.stash_id', { kind = 'headless' })
            natives.advance(0)
            assert.are.equal(3, #env.reports)
            for _, r in ipairs(env.reports) do assert.are.equal('pass', r.ok, r.name) end
        end)

        it('phone_item_map reports skip when phone item mode is off', function()
            local env = boot({ phone = false })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_invkit.phone_item_map', { kind = 'headless' })
            natives.advance(0)
            assert.are.equal('skip', env.reports[1].ok)
            assert.are.equal('Config.phone.enabled = false', env.reports[1].detail)
        end)

        it('phone_device_save gives a test phone, writes battery 42 and fold closed, then removes it', function()
            local env = boot()
            natives.fire('aeterna_core:selftest', 'r2-abcd', 'aeterna_invkit.phone_device_save',
                { kind = 'mock', side = 'server', a = 5, destructive = true })
            natives.advance(10000)
            assert.are.equal(1, #env.reports)
            assert.are.equal('mock', env.reports[1].ok)
            assert.is_true(env.reports[1].extra.restored)
            assert.are.same({ 'phone' }, env.ox.added)
            assert.are.same({ 'phone' }, env.ox.removed)
            assert.is_nil(next(env.inv[5]))
        end)

        it('phone_device_save fails when there is no presser', function()
            local env = boot()
            natives.fire('aeterna_core:selftest', 'r3-abcd', 'aeterna_invkit.phone_device_save',
                { kind = 'mock', side = 'server', destructive = true })
            natives.advance(0)
            assert.are.equal('fail', env.reports[1].ok)
            assert.are.same({}, env.ox.added)
        end)

        it('phone_device_save fails and gives nothing when ox refuses the item', function()
            local env = boot({ addFails = true })
            natives.fire('aeterna_core:selftest', 'r4-abcd', 'aeterna_invkit.phone_device_save',
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
            return { reports = reports, bag = bag, closed = function() return closed end }
        end

        local function opens()
            return #natives.emitted('server', 'aeterna_invkit:sv:open')
        end

        it('checks away from the point, then at it, and passes', function()
            local env = boot_client({ { coords = vector3(10.0, 10.0, 10.0), radius = 2.0 } })
            natives.set_entity_coords(1, vector3(50.0, 50.0, 10.0))
            natives.fire('aeterna_core:selftest', 'r5-abcd', 'aeterna_invkit.stash_open', { kind = 'ped', role = 'A' })
            natives.advance(0)
            assert.are.equal(1, opens())
            natives.fire_net('aeterna_invkit:cl:refused', 1, { item = 'stash', reason = 'invkit.stash.far' })
            natives.advance(2000)
            natives.set_entity_coords(1, vector3(10.5, 10.0, 10.0))
            natives.advance(1000)
            assert.are.equal(2, opens())
            env.bag.invOpen = true
            natives.advance(3000)
            assert.are.equal(1, #env.reports)
            assert.are.equal('pass', env.reports[1].ok)
            assert.are.equal(1, env.closed())
        end)

        it('reports skip when no stash point is configured', function()
            local env = boot_client({})
            natives.fire('aeterna_core:selftest', 'r6-abcd', 'aeterna_invkit.stash_open', { kind = 'ped', role = 'A' })
            natives.advance(0)
            assert.are.equal('skip', env.reports[1].ok)
            assert.are.equal('no stash point configured', env.reports[1].detail)
            assert.are.equal(0, opens())
        end)
    end)
end)
