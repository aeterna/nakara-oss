-- phonekit_spec.lua -- aeterna_phonekit: pure logic in shared/logic/ + server/client harness tests.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

describe('aeterna_phonekit', function()
    describe('1. calculator (shared/logic/calc.lua)', function()
        local C
        before_each(function()
            natives.reset()
            C = assert(loadfile(DIR .. '/shared/logic/calc.lua'))()
        end)

        it('evaluates operators in order as typed without precedence', function()
            local calc = C.new()
            -- 2 + 3 * 4 = 20 (not 14)
            calc:input('2')
            calc:input('+')
            calc:input('3')
            assert.are.equal('3', calc.display)
            calc:input('*')
            -- Immediate evaluation of 2 + 3 = 5
            assert.are.equal('5', calc.display)
            calc:input('4')
            calc:input('=')
            assert.are.equal('20', calc.display)

            -- 10 - 2 * 3 = 24
            calc:reset()
            calc:feed({ '1', '0', '-', '2', '*', '3', '=' })
            assert.are.equal('24', calc.display)

            -- 10 + 5 / 3 = 5
            calc:reset()
            calc:feed({ '1', '0', '+', '5', '/', '3', '=' })
            assert.are.equal('5', calc.display)
        end)

        it('handles percent standalone and chained with accumulator', function()
            local calc = C.new()
            -- Standalone percent: 50 % = 0.5
            calc:feed({ '5', '0', '%' })
            assert.are.equal('0.5', calc.display)

            -- Chained percent: 200 + 10 % => 200 + 20 => 220
            calc:reset()
            calc:feed({ '2', '0', '0', '+', '1', '0', '%' })
            assert.are.equal('20', calc.display)
            calc:input('=')
            assert.are.equal('220', calc.display)

            -- Chained percent: 100 - 25 % => 100 - 25 => 75
            calc:reset()
            calc:feed({ '1', '0', '0', '-', '2', '5', '%', '=' })
            assert.are.equal('75', calc.display)
        end)

        it('shows an error state on divide by zero', function()
            local calc = C.new()
            calc:feed({ '5', '/', '0', '=' })
            assert.are.equal('Error', calc.display)
            assert.is_true(calc.isError)

            -- Subsequent operations in error state keep Error until cleared or digit pressed
            calc:input('+')
            assert.are.equal('Error', calc.display)

            calc:input('C')
            assert.are.equal('0', calc.display)
            assert.is_false(calc.isError)
        end)

        it('rounds long results to 10 significant digits', function()
            local calc = C.new()
            -- 1 / 3 = 0.3333333333 (10 digits)
            calc:feed({ '1', '/', '3', '=' })
            assert.are.equal('0.3333333333', calc.display)

            -- 10 / 3 = 3.333333333 (10 digits)
            calc:reset()
            calc:feed({ '1', '0', '/', '3', '=' })
            assert.are.equal('3.333333333', calc.display)

            -- 10000000000 / 3
            local largeResult = C.formatResult(10000000000 / 3)
            assert.are.equal('3333333333', largeResult)
        end)
    end)

    describe('2. notes and contacts (shared/logic/phone.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/phone.lua'))()
        end)

        it('enforces notes count (50) and length limits', function()
            local store = L.createNotesStore()
            for i = 1, 50 do
                local ok = store:save({ id = 'n' .. i, title = 'Note ' .. i, body = 'Content ' .. i })
                assert.is_true(ok)
            end
            assert.are.equal(50, store:count())

            -- 51st note is refused with locale error key
            local okExtra, errKey = store:save({ id = 'n51', title = 'Overflow', body = 'Over' })
            assert.is_false(okExtra)
            assert.are.equal('phonekit.notes.full', errKey)
            assert.are.equal(50, store:count())

            -- Title and body lengths cut
            local longTitle = string.rep('A', 80)
            local longBody = string.rep('B', 2500)
            local okVal, _, clean = L.validateNote({ id = 'n1', title = longTitle, body = longBody })
            assert.is_true(okVal)
            assert.are.equal(60, #clean.title)
            assert.are.equal(2000, #clean.body)
        end)

        it('enforces contacts count (100) and length limits', function()
            local store = L.createContactsStore()
            for i = 1, 100 do
                local ok = store:save({ id = 'c' .. i, name = 'Contact ' .. i, number = '555-' .. i })
                assert.is_true(ok)
            end
            assert.are.equal(100, store:count())

            -- 101st contact is refused with locale error key
            local okExtra, errKey = store:save({ id = 'c101', name = 'Overflow', number = '555-999' })
            assert.is_false(okExtra)
            assert.are.equal('phonekit.contacts.full', errKey)
            assert.are.equal(100, store:count())

            -- Name and number lengths cut
            local longName = string.rep('N', 60)
            local longNum = string.rep('1', 35)
            local okVal, _, clean = L.validateContact({ id = 'c1', name = longName, number = longNum })
            assert.is_true(okVal)
            assert.are.equal(40, #clean.name)
            assert.are.equal(20, #clean.number)
        end)

        it('refuses notes and contacts that exceed the 16 KB limit with locale key', function()
            local store = L.createNotesStore()
            -- Add notes with large content until near 16 KB
            local largeBody = string.rep('X', 1800)
            for i = 1, 8 do
                assert.is_true(store:save({ id = 'n' .. i, title = 'Big Note ' .. i, body = largeBody }))
            end

            -- Adding another large note that pushes total past 16384 bytes fails
            local ok, errKey = store:save({ id = 'n9', title = 'Pushes over 16KB', body = largeBody })
            assert.is_false(ok)
            assert.are.equal('phonekit.notes.full', errKey)
        end)

        it('preserves fields across round trip', function()
            local store = L.createNotesStore()
            assert(store:save({ id = 'n1', title = 'Shopping', body = 'Milk, Bread, Coffee' }))
            assert(store:save({ id = 'n2', title = 'Garage', body = 'Code 4821' }))

            local list = store:list()
            assert.are.equal(2, #list)
            assert.are.equal('Shopping', list[1].title)
            assert.are.equal('Milk, Bread, Coffee', list[1].body)
            assert.are.equal('Garage', list[2].title)
            assert.are.equal('Code 4821', list[2].body)

            -- Delete one
            assert.is_true(store:delete('n1'))
            assert.are.equal(1, store:count())
            assert.is_nil(store:get('n1'))
            assert.is_truthy(store:get('n2'))
        end)

        it('saves notes when global os is nil using GetCloudTimeAsInt', function()
            local store = L.createNotesStore()

            natives.stub('GetCloudTimeAsInt', function() return 1700000000 end)
            finally(function()
                rawset(_G, 'GetCloudTimeAsInt', nil)
            end)

            local okVal, _, cleanNote = L.validateNote({ id = 'n_direct', title = 'Direct Note' })
            assert.is_true(okVal)
            assert.are.equal(1700000000, cleanNote.updatedAt)

            local okSave, errSave, clean = store:save({ title = 'Client Note', body = 'Works without os' })
            assert.is_true(okSave)
            assert.is_nil(errSave)
            assert.are.equal('n1', clean.id)
            assert.are.equal(1700000000, clean.updatedAt)

            local note = store:get('n1')
            assert.is_truthy(note)
            assert.are.equal('Client Note', note.title)
            assert.are.equal('Works without os', note.body)
            assert.are.equal(1700000000, note.updatedAt)

            rawset(_G, 'GetCloudTimeAsInt', nil)
        end)
    end)

    describe('3. app registry (shared/logic/phone.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/phone.lua'))()
        end)

        it('adds tiles and replaces in place when owner and id match', function()
            local reg = L.createAppRegistry({ maxApps = 24 })
            assert.is_true(reg:addTile('res_a', { id = 'app1', label = 'App One', icon = 'bell', order = 10 }))
            assert.are.equal(1, reg:count())

            -- Replacing the same owner/id updates properties and does not increment count
            assert.is_true(reg:addTile('res_a', { id = 'app1', label = 'App One Updated', icon = 'star', order = 5 }))
            assert.are.equal(1, reg:count())

            local app = reg:find('res_a', 'app1')
            assert.is_truthy(app)
            assert.are.equal('App One Updated', app.label)
            assert.are.equal('star', app.icon)
            assert.are.equal(5, app.order)
        end)

        it('refuses reserved app ids (calculator, notes, contacts, settings)', function()
            local reg = L.createAppRegistry()
            assert.is_false(reg:addTile('res', { id = 'calculator', label = 'Calc' }))
            assert.is_false(reg:addTile('res', { id = 'notes', label = 'Notes' }))
            assert.is_false(reg:addTile('res', { id = 'contacts', label = 'Contacts' }))
            assert.is_false(reg:addTile('res', { id = 'settings', label = 'Settings' }))
            assert.are.equal(0, reg:count())
        end)

        it('refuses extra apps past Config.maxApps with a warn', function()
            local warnings = {}
            local reg = L.createAppRegistry({
                maxApps = 3,
                warn = function(msg, fields)
                    warnings[#warnings + 1] = { msg = msg, fields = fields }
                end,
            })

            assert.is_true(reg:addTile('res_a', { id = 'a1', label = 'App 1', icon = 'home' }))
            assert.is_true(reg:addTile('res_a', { id = 'a2', label = 'App 2', icon = 'car' }))
            assert.is_true(reg:addTile('res_b', { id = 'b1', label = 'App 3', icon = 'box' }))
            assert.are.equal(3, reg:count())

            -- 4th app refused
            local ok4, err4 = reg:addTile('res_c', { id = 'c1', label = 'App 4', icon = 'phone' })
            assert.is_false(ok4)
            assert.are.equal('maxApps', err4)
            assert.are.equal(3, reg:count())
            assert.are.equal(1, #warnings)
        end)

        it('removes only apps belonging to a stopped resource', function()
            local reg = L.createAppRegistry()
            assert(reg:addTile('res_a', { id = 'a1', label = 'A1', icon = 'home' }))
            assert(reg:addTile('res_a', { id = 'a2', label = 'A2', icon = 'car' }))
            assert(reg:addTile('res_b', { id = 'b1', label = 'B1', icon = 'star' }))
            assert.are.equal(3, reg:count())

            local removed = reg:removeOwner('res_a')
            assert.are.equal(2, removed)
            assert.are.equal(1, reg:count())
            assert.is_nil(reg:find('res_a', 'a1'))
            assert.is_nil(reg:find('res_a', 'a2'))
            assert.is_truthy(reg:find('res_b', 'b1'))
        end)

        it('sorts visible apps by order ascending then id, and filters by ACE', function()
            local reg = L.createAppRegistry()
            assert(reg:addTile('owner', { id = 'z_app', label = 'Z App', icon = 'home', order = 50 }))
            assert(reg:addTile('owner', { id = 'a_app', label = 'A App', icon = 'car', order = 50 }))
            assert(reg:addTile('owner', { id = 'vip_app', label = 'VIP', icon = 'star', order = 10, ace = 'aeterna.vip' }))
            assert(reg:addTile('owner', { id = 'first_app', label = 'First', icon = 'bell', order = 5 }))

            -- Player without ACE 'aeterna.vip'
            local visibleNormal = reg:getVisibleApps(1, function(src, ace)
                return ace ~= 'aeterna.vip'
            end)
            assert.are.equal(3, #visibleNormal)
            assert.are.equal('first_app', visibleNormal[1].id)
            assert.are.equal('a_app', visibleNormal[2].id)
            assert.are.equal('z_app', visibleNormal[3].id)

            -- Player with ACE 'aeterna.vip'
            local visibleVip = reg:getVisibleApps(2, function() return true end)
            assert.are.equal(4, #visibleVip)
            assert.are.equal('first_app', visibleVip[1].id)
            assert.are.equal('vip_app', visibleVip[2].id)
            assert.are.equal('a_app', visibleVip[3].id)
            assert.are.equal('z_app', visibleVip[4].id)
        end)
    end)

    describe('4. action validation (shared/logic/phone.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/phone.lua'))()
        end)

        it('drops actions with unknown screenId or action not in spec', function()
            local activeScreen = {
                screenId = 's1',
                id = 'taxi',
                owner = 'taxi_resource',
                spec = {
                    title = 'Taxi Service',
                    blocks = {
                        { id = 'b_call', type = 'buttons', items = { { id = 'btn_call', label = 'Call Taxi' } } },
                        { id = 'b_list', type = 'list', items = { { id = 'pick_airport', label = 'Airport' } } },
                    },
                },
            }

            -- Unknown screenId
            local okId, errId = L.validateAction(activeScreen, { screenId = 'unknown_screen', action = 'btn_call' })
            assert.is_false(okId)
            assert.are.equal('screenId: mismatch', errId)

            -- Action not in spec
            local okAct, errAct = L.validateAction(activeScreen, { screenId = 's1', action = 'not_a_button' })
            assert.is_false(okAct)
            assert.are.equal('action: not in spec', errAct)

            -- Valid actions
            local okBtn, _, cleanBtn = L.validateAction(activeScreen, { screenId = 's1', action = 'btn_call' })
            assert.is_true(okBtn)
            assert.are.equal('btn_call', cleanBtn.action)

            local okPick, _, cleanPick = L.validateAction(activeScreen, { screenId = 's1', action = 'pick_airport' })
            assert.is_true(okPick)
            assert.are.equal('pick_airport', cleanPick.action)

            -- __close and __back actions are always permitted
            local okClose, _, cleanClose = L.validateAction(activeScreen, { screenId = 's1', action = '__close' })
            assert.is_true(okClose)
            assert.are.equal('__close', cleanClose.action)

            local okBack, _, cleanBack = L.validateAction(activeScreen, { screenId = 's1', action = '__back' })
            assert.is_true(okBack)
            assert.are.equal('__back', cleanBack.action)
        end)

        it('validates form values against spec limits and drops out-of-range values', function()
            local spec = {
                title = 'Form App',
                blocks = {
                    { id = 'f_amount', type = 'field', input = 'number', min = 10, max = 500 },
                    { id = 'f_name', type = 'field', input = 'text', maxLen = 20 },
                    { id = 'f_agree', type = 'toggle' },
                    { id = 'f_tier', type = 'select', options = { { id = 'bronze', label = 'B' }, { id = 'silver', label = 'S' } } },
                },
            }

            -- Out-of-range number rejected
            local okMin, errMin = L.validateValues(spec, { f_amount = 5 })
            assert.is_false(okMin)
            assert.is_truthy(errMin:find('min'))

            local okMax, errMax = L.validateValues(spec, { f_amount = 1000 })
            assert.is_false(okMax)
            assert.is_truthy(errMax:find('max'))

            -- Invalid select option rejected
            local okSel, errSel = L.validateValues(spec, { f_tier = 'gold' })
            assert.is_false(okSel)
            assert.is_truthy(errSel:find('option not in list'))

            -- Extra keys rejected
            local okExtra, errExtra = L.validateValues(spec, { extra_field = 'test' })
            assert.is_false(okExtra)
            assert.is_truthy(errExtra:find('extra key'))

            -- Clean valid values
            local okGood, _, clean = L.validateValues(spec, {
                f_amount = 150,
                f_name = '  Alice   ',
                f_agree = true,
                f_tier = 'silver',
            })
            assert.is_true(okGood)
            assert.are.equal(150, clean.f_amount)
            assert.are.equal('Alice', clean.f_name)
            assert.is_true(clean.f_agree)
            assert.are.equal('silver', clean.f_tier)

            -- Empty/untouched number field is omitted from values table
            local okEmpty, _, cleanEmpty = L.validateValues(spec, { f_amount = '' })
            assert.is_true(okEmpty)
            assert.is_nil(cleanEmpty.f_amount)
        end)
    end)

    describe('5. opening check (shared/logic/phone.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/phone.lua'))()
        end)

        it('allows opening when no resource listens and silence occurs', function()
            local mgr = L.createOpeningCheckManager()
            assert.is_false(mgr.hasListeners)

            local resolved = nil
            local checkId = mgr:createCheck(1, function(src, allowed, reasonKey)
                resolved = { src = src, allowed = allowed, reason = reasonKey }
            end)

            assert.is_truthy(checkId)
            mgr:handleTimeout(checkId)

            assert.is_truthy(resolved)
            assert.are.equal(1, resolved.src)
            assert.is_true(resolved.allowed)
            assert.is_nil(resolved.reason)
        end)

        it('denies opening when a listener has registered and silence occurs', function()
            local mgr = L.createOpeningCheckManager()
            mgr:listenOpen()
            assert.is_true(mgr.hasListeners)

            local resolved = nil
            local checkId = mgr:createCheck(1, function(src, allowed, reasonKey)
                resolved = { src = src, allowed = allowed, reason = reasonKey }
            end)

            mgr:handleTimeout(checkId)

            assert.is_truthy(resolved)
            assert.are.equal(1, resolved.src)
            assert.is_false(resolved.allowed)
            assert.are.equal('phonekit.refused.default', resolved.reason)
        end)

        it('ignores stale checkId after resolution', function()
            local mgr = L.createOpeningCheckManager()
            local resolvedCount = 0
            local checkId = mgr:createCheck(1, function()
                resolvedCount = resolvedCount + 1
            end)

            assert.is_true(mgr:allowOpen(checkId))
            assert.are.equal(1, resolvedCount)

            -- Subsequent call with stale checkId returns false, 'stale'
            local okStale, errStale = mgr:allowOpen(checkId)
            assert.is_false(okStale)
            assert.are.equal('stale', errStale)
            assert.are.equal(1, resolvedCount)

            local okDenyStale, errDenyStale = mgr:denyOpen(checkId, 'other')
            assert.is_false(okDenyStale)
            assert.are.equal('stale', errDenyStale)
            assert.are.equal(1, resolvedCount)
        end)
    end)

    describe('6. badges and notifications (shared/logic/phone.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/phone.lua'))()
        end)

        it('clamps badge count between 0 and 99', function()
            assert.are.equal(0, L.clampBadge(-10))
            assert.are.equal(0, L.clampBadge(0))
            assert.are.equal(42, L.clampBadge(42))
            assert.are.equal(99, L.clampBadge(99))
            assert.are.equal(99, L.clampBadge(150))
        end)

        it('increments badge on notifyApp unless the app is on screen', function()
            local mgr = L.createBadgeManager()
            local toasts = {}
            local banners = {}

            local function notifyStub(src, tData)
                toasts[#toasts + 1] = { src = src, data = tData }
            end
            local function bannerStub(src, bData)
                banners[#banners + 1] = { src = src, data = bData }
            end

            -- Case 1: Phone is closed => sends toast, increments badge
            mgr:setPhoneOpen(1, false)
            local b1 = mgr:notifyApp(1, 'demo', 'chat', { title = 'New message', body = 'Hi' }, { icon = 'message-circle' }, notifyStub, bannerStub)
            assert.are.equal(1, b1)
            assert.are.equal(1, #toasts)
            assert.are.equal(0, #banners)
            assert.are.equal(1, mgr:getBadge(1, 'demo', 'chat'))

            -- Case 2: Phone is open, but player is on home screen => sends banner, increments badge
            mgr:setPhoneOpen(1, true)
            mgr:setCurrentApp(1, nil)
            local b2 = mgr:notifyApp(1, 'demo', 'chat', { title = 'Another message', body = 'Hello' }, { icon = 'message-circle' }, notifyStub, bannerStub)
            assert.are.equal(2, b2)
            assert.are.equal(1, #toasts)
            assert.are.equal(1, #banners)
            assert.are.equal(2, mgr:getBadge(1, 'demo', 'chat'))

            -- Case 3: Phone is open and player is on screen for 'chat' => sends banner, DOES NOT increment badge
            mgr:setCurrentApp(1, 'chat')
            local b3 = mgr:notifyApp(1, 'demo', 'chat', { title = 'Third message', body = 'Viewed live' }, { icon = 'message-circle' }, notifyStub, bannerStub)
            assert.are.equal(2, b3)
            assert.are.equal(2, #banners)
            assert.are.equal(2, mgr:getBadge(1, 'demo', 'chat'))
        end)
    end)

    describe('7. position and layout helpers (shared/logic/phone.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/shared/logic/phone.lua'))()
        end)

        it('calculates anchor coordinates and buildLayoutDefs for element phone', function()
            local defs = L.buildLayoutDefs('bottom-right', 'Phone')
            assert.are.equal(1, #defs)
            assert.are.equal('phone', defs[1].id)
            assert.are.equal('Phone', defs[1].label)
            assert.are.equal(320, defs[1].w)
            assert.are.equal(640, defs[1].h)
            assert.are.equal(0.9875, defs[1].x)
            assert.are.equal(0.9778, defs[1].y)
            assert.are.equal(1, defs[1].ax)
            assert.are.equal(1, defs[1].ay)
            assert.is_true(defs[1].scalable)
            assert.is_false(defs[1].hideable)

            local defsLeft = L.buildLayoutDefs('bottom-left', 'Phone')
            assert.are.equal(0.0125, defsLeft[1].x)
            assert.are.equal(0, defsLeft[1].ax)
        end)

        it('validates layout place coordinates', function()
            local okGood, _, cleanGood = L.validateLayoutPlace({ x = 0.5, y = 0.5, ax = 0.5, ay = 0.5, scale = 1.2 })
            assert.is_true(okGood)
            assert.are.equal(1.2, cleanGood.scale)

            assert.is_false((L.validateLayoutPlace({ x = -0.1, y = 0.5, ax = 0, ay = 0 })))
            assert.is_false((L.validateLayoutPlace({ x = 0.5, y = 1.1, ax = 0, ay = 0 })))
            assert.is_false((L.validateLayoutPlace({ x = 0.5, y = 0.5, ax = 0.3, ay = 0 })))
            assert.is_false((L.validateLayoutPlace({ x = 0.5, y = 0.5, ax = 0, ay = 0, scale = 5.0 })))
        end)
    end)

    describe('8. resource scripts under harness', function()
        it('runs server exports, app registry and net events', function()
            natives.reset({
                resource = 'aeterna_phonekit',
                side = 'server',
                players = { [1] = 'PlayerOne', [2] = 'PlayerTwo' },
            })
            local warnings = {}
            natives.stub('AeternaCore', {
                log = {
                    debug = function() end,
                    info = function() end,
                    warn = function(msg, fields) warnings[#warnings + 1] = { msg = msg, fields = fields } end,
                    error = function() end,
                },
                t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
                lang = function() return 'en' end,
                can = function() return true end,
                rateLimit = function() return true end,
            })
            natives.stub_export('aeterna_notify', 'notify', function() return true end)
            natives.spy('IsPlayerAceAllowed', function() return true end)

            local res = resource.load_resource(DIR, 'server')
            local api = res.exports

            -- Add tile export
            assert.is_true(api.addTile({ id = 'dispatch', label = 'Dispatch', icon = 'bell', order = 15 }))
            assert.is_true(api.addTile({ id = 'garage', label = 'Garage', icon = 'car', order = 25 }))

            -- Refuses reserved tile ids
            assert.is_false(api.addTile({ id = 'calculator', label = 'Calc', icon = 'calculator' }))
            assert.is_false(api.addTile({ id = 'notes', label = 'Notes', icon = 'file-text' }))
            assert.is_false(api.addTile({ id = 'contacts', label = 'Contacts', icon = 'users' }))
            assert.is_false(api.addTile({ id = 'settings', label = 'Settings', icon = 'settings' }))

            -- Badge export
            assert.are.equal(5, api.badge(1, 'dispatch', 5))
            local badgeEvents = natives.emitted('client', 'aeterna_phonekit:cl:badge')
            assert.are.equal(1, #badgeEvents)
            assert.are.equal(1, badgeEvents[1].target)
            assert.are.equal('dispatch', badgeEvents[1].args[1].id)
            assert.are.equal(5, badgeEvents[1].args[1].count)

            -- ShowApp fails when phone is closed
            local closedScreen, errClosed = api.showApp(1, 'dispatch', {
                title = 'Dispatch Live',
                blocks = { { id = 'txt', type = 'text', label = 'Calls list' } },
            })
            assert.is_nil(closedScreen)
            assert.are.equal('phone_closed', errClosed)

            -- Open phone for player 1
            rawset(_G, 'source', 1)
            natives.fire('aeterna_phonekit:sv:open')
            rawset(_G, 'source', nil)

            -- ShowApp export succeeds when phone is open
            local screenId, errShow = api.showApp(1, 'dispatch', {
                title = 'Dispatch Live',
                blocks = {
                    { id = 'txt', type = 'text', label = 'Calls list' },
                    { id = 'btns', type = 'buttons', items = { { id = 'btn_ack', label = 'Acknowledge' } } },
                },
            })
            assert.is_truthy(screenId)
            assert.is_nil(errShow)

            local screenEvents = natives.emitted('client', 'aeterna_phonekit:cl:screen')
            assert.are.equal(1, #screenEvents)
            assert.are.equal(1, screenEvents[1].target)
            assert.are.equal(screenId, screenEvents[1].args[1].screenId)

            -- UpdateApp export
            assert.is_true(api.updateApp(1, screenId, {
                blocks = {
                    txt = { label = 'Updated calls list' },
                },
            }))
            local updateEvents = natives.emitted('client', 'aeterna_phonekit:cl:update')
            assert.are.equal(1, #updateEvents)
            assert.are.equal(screenId, updateEvents[1].args[1].screenId)

            -- UpdateApp fails on invalid screenId
            local okWrong, errWrong = api.updateApp(1, 'invalid_screen_id', { blocks = {} })
            assert.is_false(okWrong)
            assert.are.equal('unknown_screen', errWrong)

            -- NotifyApp export
            assert.is_true(api.notifyApp(1, 'garage', { title = 'Car Ready', body = 'In Bay 2' }))

            -- Back action pops screen
            rawset(_G, 'source', 1)
            natives.fire('aeterna_phonekit:sv:action', {
                screenId = screenId,
                action = '__back',
            })
            rawset(_G, 'source', nil)

            -- Close net event clears screens and sets phone closed
            rawset(_G, 'source', 1)
            natives.fire('aeterna_phonekit:sv:close')
            rawset(_G, 'source', nil)

            -- Subsequent showApp fails because phone is now closed
            local screenAfterClose, errAfterClose = api.showApp(1, 'dispatch', {
                title = 'Dispatch Live',
                blocks = { { id = 'txt', type = 'text', label = 'Calls list' } },
            })
            assert.is_nil(screenAfterClose)
            assert.are.equal('phone_closed', errAfterClose)

            -- Remove tile export
            assert.is_true(api.removeTile('garage'))
        end)

        it('runs client commands, focus coordination, layout and NUI callbacks', function()
            natives.reset({ resource = 'aeterna_phonekit', side = 'client' })
            natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            local nuiMessages = natives.spy('SendNUIMessage')
            local nuiCallbacks = {}
            natives.spy('RegisterNUICallback', function(name, fn)
                nuiCallbacks[name] = fn
            end)
            natives.spy('GetResourceState', function(resName)
                if resName == 'aeterna_layout' then return 'started' end
                return 'missing'
            end)
            local cmdCalls = natives.spy('RegisterCommand')
            local mapCalls = natives.spy('RegisterKeyMapping')
            local execCalls = natives.spy('ExecuteCommand')
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
                t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
                lang = function() return 'en' end,
                kvp = {
                    get = function(_, _, default) return default end,
                    set = function() end,
                },
                key = function(cmd, desc)
                    RegisterKeyMapping(cmd, (Locales and Locales.en and Locales.en[desc]) or desc, 'keyboard', '')
                end,
                requestFocus = function(opts)
                    local ok, tok = pcall(function() return exports.aeterna_core:requestFocus(opts) end)
                    if not ok or not tok then return nil end
                    local normalized = type(opts) == 'table' and opts or {}
                    SetNuiFocus(normalized.keyboard ~= false, normalized.cursor ~= false)
                    SetNuiFocusKeepInput(normalized.keepGameInput == true)
                    return tok
                end,
                releaseFocus = function(tok)
                    local ok, res = pcall(function() return exports.aeterna_core:releaseFocus(tok) end)
                    if ok and res == true then
                        SetNuiFocusKeepInput(false)
                        SetNuiFocus(false, false)
                        return true
                    end
                    return false
                end,
            })
            local focusRequested = false
            natives.stub_export('aeterna_core', 'requestFocus', function(opts)
                focusRequested = true
                assert.is_true(opts.keepGameInput)
                return 'phone_focus_token'
            end)
            natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
            natives.stub_export('aeterna_core', 'themeHref', function() return nil end)
            natives.stub_export('aeterna_notify', 'notify', function() return true end)
            natives.spy('IsPlayerAceAllowed', function() return true end)

            local res = resource.load_resource(DIR, 'client')

            -- Commands and key mapping registered on load
            assert.are.equal(3, #cmdCalls)
            assert.are.equal('aeterna_phonekit_open', cmdCalls[1][1])
            assert.are.equal('+aeterna_phonekit_open', cmdCalls[2][1])
            assert.are.equal('-aeterna_phonekit_open', cmdCalls[3][1])
            assert.are.equal(1, #mapCalls)
            assert.are.equal('+aeterna_phonekit_open', mapCalls[1][1])

            -- Layout add event fired on startup
            local layoutAdds = natives.emitted('local', 'aeterna_layout:add')
            assert.are.equal(1, #layoutAdds)
            assert.are.equal('phone', layoutAdds[1].args[1].id)
            assert.are.equal('aeterna_phonekit', layoutAdds[1].args[1].owner)

            -- Server open event triggers client focus acquisition and NUI message
            natives.fire('aeterna_phonekit:cl:open', { apps = {} })
            assert.is_true(focusRequested)

            local foundShellOpen = false
            for i = 1, #nuiMessages do
                if nuiMessages[i][1] and nuiMessages[i][1].type == 'shell:open' then
                    foundShellOpen = true
                end
            end
            assert.is_true(foundShellOpen)

            -- Layout apply event updates placement
            natives.fire('aeterna_layout:apply', 'aeterna_phonekit', 'phone', {
                x = 0.9, y = 0.9, ax = 1, ay = 1, scale = 1.0, hidden = false,
            })

            -- Settings NUI callback executes aeterna_layout command
            nuiCallbacks.settings({ key = 'layout', value = true }, function() end)
            local foundExec = false
            for _, c in ipairs(execCalls) do
                if c[1] == 'aeterna_layout' then
                    foundExec = true
                end
            end
            assert.is_true(foundExec)

            -- NUI typing callback
            nuiCallbacks.typing({ on = true }, function() end)

            -- NUI back callback
            nuiCallbacks.back({}, function() end)

            -- NUI close callback drops focus and closes, sending sv:close
            nuiCallbacks.close({}, function() end)
            local foundShellClose = false
            for i = 1, #nuiMessages do
                if nuiMessages[i][1] and nuiMessages[i][1].type == 'shell:close' then
                    foundShellClose = true
                end
            end
            assert.is_true(foundShellClose)

            local svCloseEvents = natives.emitted('server', 'aeterna_phonekit:sv:close')
            assert.is_true(#svCloseEvents >= 1)
        end)
    end)

    describe('9. locale files (locales/en.lua, locales/th.lua)', function()
        it('merges into the tables created by @aeterna_core/import.lua', function()
            natives.reset({ resource = 'aeterna_phonekit', side = 'client' })
            local res = resource.load_resource(DIR, 'client', {
                externals = {
                    ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua',
                },
                skip = { ['client/main.lua'] = true, ['client/anim.lua'] = true },
            })
            assert.is_truthy(res)
            assert.are.equal('January', Locales.en['core.month.1'])
            assert.are.equal('Calculator', Locales.en['phonekit.app.calculator'])
            assert.are.equal('Notes storage is full', Locales.en['phonekit.notes.full'])
            assert.are.equal('มกราคม', Locales.th['core.month.1'])
            assert.are.equal('เครื่องคิดเลข', Locales.th['phonekit.app.calculator'])
            assert.are.equal('พื้นที่จัดเก็บบันทึกเต็ม', Locales.th['phonekit.notes.full'])
        end)
    end)
end)
