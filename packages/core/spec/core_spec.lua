-- core_spec.lua -- busted tests for aeterna_core (pure shared/logic modules + resource runtime).

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load_logic(name)
    return assert(loadfile(DIR .. '/shared/logic/' .. name .. '.lua'))()
end

describe('aeterna_core', function()
    describe('shared/logic/text.lua', function()
        local text
        before_each(function()
            natives.reset()
            text = load_logic('text')
        end)

        it('1. text.len counts Thai combining marks as 0 visible characters', function()
            assert.are.equal(4, text.len('สวัสดี'))
            assert.are.equal(1, text.len('ก้'))
            assert.are.equal(3, text.len('abc'))
            assert.are.equal(0, text.len(''))
        end)

        it('2. text.cut keeps combining marks with their base and never splits UTF-8', function()
            assert.are.equal('สวัส', text.cut('สวัสดีครับ', 3))
            assert.are.equal('ดี', text.cut('ดี', 1))
            assert.are.equal('', text.cut('สวัสดี', 0))
            -- Truncated UTF-8 sequence at the end is dropped cleanly without splitting bytes
            local partial = 'ab' .. ('ก'):sub(1, 2)
            assert.are.equal('ab', text.cut(partial, 3))
            -- Leading lone combining mark is not left behind
            assert.are.equal('ก', text.cut('\224\184\177กข', 1))
        end)

        it('3. text.clean removes U+200B and newlines, trims, and respects maxLen', function()
            local raw = '  \n\tสวัสดี\226\128\139ครับ\r\n  '
            assert.are.equal('สวัสดีครับ', text.clean(raw))
            assert.are.equal('สวัส', text.clean(raw, 3))
            -- Control chars U+0000, U+007F and bidi override U+202E are stripped
            assert.are.equal('ab', text.clean('\0a\127\226\128\174b', 10))
        end)
    end)

    describe('shared/logic/validate.lua', function()
        local validate
        local schema
        before_each(function()
            natives.reset()
            load_logic('text')
            validate = load_logic('validate')
            schema = {
                type = 'table',
                fields = {
                    id     = { type = 'string', maxLen = 32, pattern = '^[%w_%-]+$' },
                    amount = { type = 'number', integer = true, min = 1, max = 1000 },
                    mode   = { type = 'string', enum = { 'a', 'b' } },
                    note   = { type = 'string', maxLen = 120, optional = true },
                },
                extra = false,
            }
        end)

        it('4a. passes a good payload and cleans strings', function()
            local ok, err, clean = validate.validate({
                id = '  item_01\n',
                amount = 25,
                mode = 'a',
                note = '  hello\226\128\139 world  ',
            }, schema)
            assert.is_true(ok)
            assert.is_nil(err)
            assert.are.same({
                id = 'item_01',
                amount = 25,
                mode = 'a',
                note = 'hello world',
            }, clean)
        end)

        it('4b. fails with exact path and rule on bad payloads', function()
            local ok1, err1 = validate.validate({
                id = 'ok_1',
                amount = 1001,
                mode = 'a',
            }, schema)
            assert.is_false(ok1)
            assert.are.equal('amount: max 1000', err1)

            local ok2, err2 = validate.validate({
                id = 'bad id!',
                amount = 10,
                mode = 'a',
            }, schema)
            assert.is_false(ok2)
            assert.are.equal('id: pattern', err2)

            local ok3, err3 = validate.validate({
                id = 'ok_1',
                amount = 10,
                mode = 'a',
                extra = true,
            }, schema)
            assert.is_false(ok3)
            assert.are.equal('extra: not allowed', err3)

            local ok4, err4 = validate.validate({
                id = 'ok_1',
                amount = 10,
                mode = 'a',
                note = 123,
            }, schema)
            assert.is_false(ok4)
            assert.are.equal('note: type', err4)
        end)

        it('4c. fails when arrays exceed maxItems', function()
            local arrSchema = {
                type = 'array',
                maxItems = 3,
                items = { type = 'string', maxLen = 4 },
            }
            local okGood, errGood, cleanGood = validate.validate({ 'abcdef', 'xy' }, arrSchema)
            assert.is_true(okGood)
            assert.is_nil(errGood)
            assert.are.same({ 'abcd', 'xy' }, cleanGood)

            local okBad, errBad = validate.validate({ 'a', 'b', 'c', 'd' }, arrSchema)
            assert.is_false(okBad)
            assert.are.equal('value: maxItems 3', errBad)
        end)
    end)

    describe('shared/logic/ratelimit.lua', function()
        local ratelimit
        before_each(function()
            natives.reset()
            ratelimit = load_logic('ratelimit')
        end)

        it('5. allows 5 calls in a window, blocks the 6th, and allows again after the window', function()
            local clock = 1000
            local limiter = ratelimit.new(function() return clock end)
            for i = 1, 5 do
                assert.is_true(limiter:check(1, 'act', 5, 1000), 'call ' .. i .. ' should pass')
                clock = clock + 100
            end
            -- At clock = 1500, all 5 calls are within the 1000 ms window
            assert.is_false(limiter:check(1, 'act', 5, 1000))

            -- Advance past the first call's 1000 ms window (1000 + 1000 = 2000)
            clock = 2001
            assert.is_true(limiter:check(1, 'act', 5, 1000))

            -- Dropping player frees their buckets
            limiter:drop(1)
            for i = 1, 5 do
                assert.is_true(limiter:check(1, 'act', 5, 1000))
            end
        end)
    end)

    describe('shared/logic/time.lua', function()
        local timeLogic
        before_each(function()
            natives.reset()
            timeLogic = load_logic('time')
        end)

        it('6. time.parts converts 1700000000 in +07:00 and shifts day in -03:30', function()
            local p = timeLogic.parts(1700000000, '+07:00')
            assert.are.same({
                year = 2023,
                month = 11,
                day = 15,
                hour = 5,
                min = 13,
                sec = 20,
                wday = 4,
            }, p)
            assert.are.equal('2023-11-15 05:13:20', timeLogic.format(1700000000, 'YYYY-MM-DD HH:mm:ss', '+07:00'))

            -- 1700000000 UTC is 2023-11-14 22:13:20; in -03:30 it is 2023-11-14 18:43:20 (Tuesday, wday = 3)
            local pNeg = timeLogic.parts(1700000000, '-03:30')
            assert.are.same({
                year = 2023,
                month = 11,
                day = 14,
                hour = 18,
                min = 43,
                sec = 20,
                wday = 3,
            }, pNeg)

            -- 1700010000 UTC is 2023-11-15 01:00:00; in -03:30 the day changes back to 2023-11-14 21:30:00
            local pBoundary = timeLogic.parts(1700010000, '-03:30')
            assert.are.equal(2023, pBoundary.year)
            assert.are.equal(11, pBoundary.month)
            assert.are.equal(14, pBoundary.day)
            assert.are.equal(21, pBoundary.hour)
            assert.are.equal(30, pBoundary.min)
            assert.are.equal(0, pBoundary.sec)
            assert.are.equal(3, pBoundary.wday)
        end)
    end)

    describe('shared/logic/locale.lua', function()
        local localeLogic
        before_each(function()
            natives.reset()
            localeLogic = load_logic('locale')
        end)

        it('7. t() falls back th -> en -> key, replaces {name}, and leaves missing vars', function()
            local locales = {
                en = {
                    ['greet'] = 'Hello {name}, welcome to {place}',
                    ['only_en'] = 'English fallback',
                },
                th = {
                    ['greet'] = 'สวัสดี {name} ยินดีต้อนรับสู่ {place}',
                },
            }

            assert.are.equal(
                'สวัสดี สมชาย ยินดีต้อนรับสู่ {place}',
                localeLogic.t(locales, 'th', 'greet', { name = 'สมชาย' })
            )
            assert.are.equal(
                'English fallback',
                localeLogic.t(locales, 'th', 'only_en')
            )
            assert.are.equal(
                'missing.key',
                localeLogic.t(locales, 'th', 'missing.key')
            )
        end)
    end)

    describe('shared/logic/focus.lua', function()
        local focusLogic
        before_each(function()
            natives.reset()
            focusLogic = load_logic('focus')
        end)

        it('8. manages focus ownership, preemption, token validation and resource stop', function()
            local lost = {}
            local applied = {}
            local fm = focusLogic.new({
                onLost = function(owner, token, reason)
                    lost[#lost + 1] = { owner = owner, token = token, reason = reason }
                end,
                onApply = function(keyboard, cursor, keepGameInput)
                    applied[#applied + 1] = { keyboard = keyboard, cursor = cursor, keepGameInput = keepGameInput }
                end,
            })

            -- Request A -> owner A
            local tokenA = fm:request('aeterna_uikit', { cursor = true, keyboard = true })
            assert.is_string(tokenA)
            assert.are.equal('aeterna_uikit', fm:owner())
            assert.are.equal(0, #lost)

            -- Request B -> A gets preempted, owner B
            local tokenB = fm:request('aeterna_phonekit', { cursor = true, keyboard = true, keepGameInput = true })
            assert.are.equal('aeterna_phonekit', fm:owner())
            assert.are.equal(1, #lost)
            assert.are.same({ owner = 'aeterna_uikit', token = tokenA, reason = 'preempted' }, lost[1])

            -- Release with A's stale token returns false and changes nothing
            assert.is_false(fm:release(tokenA))
            assert.are.equal('aeterna_phonekit', fm:owner())

            -- Release with B's token clears focus
            assert.is_true(fm:release(tokenB))
            assert.is_nil(fm:owner())

            -- Owner stop clears and notifies
            local tokenC = fm:request('aeterna_layout', { cursor = true, keyboard = true })
            assert.are.equal('aeterna_layout', fm:owner())
            fm:onResourceStop('aeterna_layout', 'aeterna_core')
            assert.is_nil(fm:owner())
            assert.are.equal(2, #lost)
            assert.are.same({ owner = 'aeterna_layout', token = tokenC, reason = 'owner_stopped' }, lost[2])
        end)
    end)

    describe('shared/logic/kvp.lua', function()
        local kvpLogic
        before_each(function()
            natives.reset()
            kvpLogic = load_logic('kvp')
        end)

        it('9. kvp.migrate converts once and deletes the old key', function()
            local store = {}
            local warnings = {}
            local kvp = kvpLogic.new({
                resource = function() return 'aeterna_layout' end,
                getString = function(k) return store[k] end,
                setString = function(k, v) store[k] = v end,
                delete = function(k) store[k] = nil end,
                encode = json.encode,
                decode = json.decode,
                warn = function(msg) warnings[#warnings + 1] = msg end,
            })

            kvp.set('places', 1, { x = 10 })
            assert.is_not_nil(store['aeterna_layout:places:v1'])

            local calls = 0
            kvp.migrate('places', 1, 2, function(old)
                calls = calls + 1
                return { x = old.x * 2, migrated = true }
            end)

            assert.are.equal(1, calls)
            assert.is_nil(store['aeterna_layout:places:v1'])
            assert.are.same({ x = 20, migrated = true }, kvp.get('places', 2, nil))

            -- Second migrate does nothing
            kvp.migrate('places', 1, 2, function()
                calls = calls + 1
                return { x = 999 }
            end)
            assert.are.equal(1, calls)
            assert.are.same({ x = 20, migrated = true }, kvp.get('places', 2, nil))

            -- Bad JSON returns default and logs one warn
            store['aeterna_layout:bad:v1'] = '{broken'
            assert.are.equal('fallback', kvp.get('bad', 1, 'fallback'))
            assert.are.equal('fallback', kvp.get('bad', 1, 'fallback'))
            assert.are.equal(1, #warnings)

            -- Refuses values over 16 KB
            kvp.set('huge', 1, ('a'):rep(17000))
            assert.is_nil(store['aeterna_layout:huge:v1'])
        end)
    end)

    describe('resource integration (import.lua, client, server)', function()
        it('client: exposes focus and themeHref exports, event bus, kvp and key mappings', function()
            natives.reset({
                side = 'client',
                convars = {
                    aeterna_locale = 'th',
                    aeterna_timezone = '+07:00',
                    aeterna_theme = 'nui://my_theme/theme.css',
                },
            })
            local focusCalls = natives.spy('SetNuiFocus')
            local keepCalls = natives.spy('SetNuiFocusKeepInput')
            local mapCalls = natives.spy('RegisterKeyMapping')

            resource.load_resource(DIR, 'client')

            assert.are.equal('th', AeternaCore.lang())
            assert.are.equal('มกราคม', AeternaCore.t('core.month.1'))
            assert.are.equal('2023-11-15 05:13:20', AeternaCore.time.format(1700000000, 'YYYY-MM-DD HH:mm:ss'))
            assert.are.equal('nui://my_theme/theme.css', exports.aeterna_core:themeHref())

            natives.set_convar('aeterna_theme', 'https://evil.example/theme.css')
            assert.is_nil(exports.aeterna_core:themeHref())

            -- Event bus
            local received = nil
            local h = AeternaCore.on('ping', function(v) received = v end)
            AeternaCore.emit('ping', 42)
            assert.are.equal(42, received)
            AeternaCore.off(h)
            AeternaCore.emit('ping', 99)
            assert.are.equal(42, received)

            -- Focus exports decide ownership only (no native calls)
            local tok = exports.aeterna_core:requestFocus({ cursor = true, keyboard = false, keepGameInput = true })
            assert.is_string(tok)
            assert.are.equal('aeterna_core', exports.aeterna_core:focusOwner())
            assert.are.equal(0, #focusCalls)
            assert.are.equal(0, #keepCalls)

            assert.is_true(exports.aeterna_core:releaseFocus(tok))
            assert.is_nil(exports.aeterna_core:focusOwner())
            assert.are.equal(0, #focusCalls)
            assert.are.equal(0, #keepCalls)

            -- Focus helpers in AeternaCore call natives
            local helperTok = AeternaCore.requestFocus({ cursor = true, keyboard = false, keepGameInput = true })
            assert.is_string(helperTok)
            assert.are.equal('aeterna_core', exports.aeterna_core:focusOwner())
            assert.are.equal(1, #focusCalls)
            assert.are.same({ n = 2, false, true }, focusCalls[1])
            assert.are.equal(1, #keepCalls)
            assert.are.same({ n = 1, true }, keepCalls[1])

            -- AeternaCore.releaseFocus clears both natives
            assert.is_true(AeternaCore.releaseFocus(helperTok))
            assert.is_nil(exports.aeterna_core:focusOwner())
            assert.are.equal(2, #focusCalls)
            assert.are.same({ n = 2, false, false }, focusCalls[2])
            assert.are.equal(2, #keepCalls)
            assert.are.same({ n = 1, false }, keepCalls[2])

            -- Re-acquire focus to test focusLost
            local lostTok = AeternaCore.requestFocus({ cursor = true, keyboard = true, keepGameInput = false })
            assert.is_string(lostTok)
            assert.are.equal(3, #focusCalls)
            assert.are.same({ n = 2, true, true }, focusCalls[3])
            assert.are.equal(3, #keepCalls)
            assert.are.same({ n = 1, false }, keepCalls[3])

            -- focusLost for another resource does NOT clear natives for aeterna_core
            natives.fire('aeterna_core:focusLost', 'other_resource', lostTok, 'preempted')
            assert.are.equal(3, #focusCalls)
            assert.are.equal(3, #keepCalls)

            -- focusLost for own resource clears both natives
            natives.fire('aeterna_core:focusLost', 'aeterna_core', lostTok, 'preempted')
            assert.are.equal(4, #focusCalls)
            assert.are.same({ n = 2, false, false }, focusCalls[4])
            assert.are.equal(4, #keepCalls)
            assert.are.same({ n = 1, false }, keepCalls[4])

            -- Key mapping requires +aeterna_ prefix
            AeternaCore.key('bad_command', 'core.month.1')
            assert.are.equal(0, #mapCalls)
            AeternaCore.key('+aeterna_core_test', 'core.month.1')
            assert.are.equal(1, #mapCalls)
            assert.are.same({ n = 4, '+aeterna_core_test', 'มกราคม', 'keyboard', '' }, mapCalls[1])
        end)

        it('server: runs selftests, checks ACE, rate limits and registers aeterna_core_selftest', function()
            natives.reset({ side = 'server' })
            local cmdHandler
            natives.spy('RegisterCommand', function(name, fn)
                if name == 'aeterna_core_selftest' then cmdHandler = fn end
            end)
            natives.spy('IsPlayerAceAllowed', function(src, action)
                return tonumber(src) == 1 and action == 'aeterna.core.selftest'
            end)

            resource.load_resource(DIR, 'server')

            assert.is_true(AeternaCore.can(0, 'aeterna.core.selftest'))
            assert.is_true(AeternaCore.can(1, 'aeterna.core.selftest'))
            assert.is_false(AeternaCore.can(2, 'aeterna.core.selftest'))
            assert.is_false(AeternaCore.can(0, 'other.perm'))

            -- Rate limit + playerDropped cleanup
            for _ = 1, 3 do
                assert.is_true(AeternaCore.rateLimit(7, 'test', 3, 1000))
            end
            assert.is_false(AeternaCore.rateLimit(7, 'test', 3, 1000))
            rawset(_G, 'source', 7)
            natives.fire('playerDropped', 'quit')
            rawset(_G, 'source', nil)
            assert.is_true(AeternaCore.rateLimit(7, 'test', 3, 1000))

            exports.aeterna_core:addSelftest('sample')
            AddEventHandler('aeterna_core:selftest', function(runId, name)
                if name == 'aeterna_core.sample' then
                    exports.aeterna_core:reportSelftest(runId, name, true, 'ok')
                end
            end)

            local results = exports.aeterna_core:runSelftests()
            assert.is_true(#results >= 2)
            local foundSample = false
            local foundCore = false
            for _, r in ipairs(results) do
                if r.name == 'aeterna_core.sample' then
                    foundSample = true
                    assert.is_true(r.ok)
                    assert.are.equal('ok', r.detail)
                elseif r.name == 'aeterna_core.core' then
                    foundCore = true
                    assert.is_true(r.ok)
                end
            end
            assert.is_true(foundSample)
            assert.is_true(foundCore)
            assert.is_function(cmdHandler)
            cmdHandler(0)
        end)

        it('standalone import.lua works when loaded directly by another resource', function()
            natives.reset({ resource = 'aeterna_uikit', side = 'client' })
            local focusCalls = natives.spy('SetNuiFocus')
            local keepCalls = natives.spy('SetNuiFocusKeepInput')
            natives.stub_export('aeterna_core', 'requestFocus', function(opts) return 'tok_uikit' end)
            natives.stub_export('aeterna_core', 'releaseFocus', function(tok) return tok == 'tok_uikit' end)
            assert(loadfile(DIR .. '/import.lua'))()

            assert.are.equal(4, AeternaCore.text.len('สวัสดี'))
            assert.are.equal('สวัส', AeternaCore.text.cut('สวัสดีครับ', 3))
            local ok, err, clean = AeternaCore.validate(
                { id = 'btn_1' },
                { type = 'table', fields = { id = { type = 'string', maxLen = 16, pattern = '^[%w_]+$' } } }
            )
            assert.is_true(ok)
            assert.is_nil(err)
            assert.are.same({ id = 'btn_1' }, clean)

            -- Test AeternaCore.requestFocus / releaseFocus / focusLost in another resource
            local tok = AeternaCore.requestFocus({ cursor = true, keyboard = false, keepGameInput = true })
            assert.are.equal('tok_uikit', tok)
            assert.are.equal(1, #focusCalls)
            assert.are.same({ n = 2, false, true }, focusCalls[1])
            assert.are.equal(1, #keepCalls)
            assert.are.same({ n = 1, true }, keepCalls[1])

            assert.is_true(AeternaCore.releaseFocus(tok))
            assert.are.equal(2, #focusCalls)
            assert.are.same({ n = 2, false, false }, focusCalls[2])
            assert.are.equal(2, #keepCalls)
            assert.are.same({ n = 1, false }, keepCalls[2])

            -- Re-acquire and test focusLost only clears for own resource ('aeterna_uikit')
            tok = AeternaCore.requestFocus({ cursor = true, keyboard = true, keepGameInput = false })
            assert.are.equal(3, #focusCalls)
            assert.are.same({ n = 2, true, true }, focusCalls[3])

            natives.fire('aeterna_core:focusLost', 'some_other_res', tok, 'preempted')
            assert.are.equal(3, #focusCalls)
            assert.are.equal(3, #keepCalls)

            natives.fire('aeterna_core:focusLost', 'aeterna_uikit', tok, 'preempted')
            assert.are.equal(4, #focusCalls)
            assert.are.same({ n = 2, false, false }, focusCalls[4])
            assert.are.equal(4, #keepCalls)
            assert.are.same({ n = 1, false }, keepCalls[4])
        end)
    end)
end)
