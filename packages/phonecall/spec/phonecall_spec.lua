-- spec/phonecall_spec.lua -- busted tests for aeterna_phonecall (pure logic in shared/logic/), spec "Tests" 1-8
-- plus the decision logic of the self-tests.

local natives = require('helpers.natives')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load(rel)
    return assert(loadfile(DIR .. '/shared/logic/' .. rel))()
end

-- AeternaCore.text from the real import.lua, so body cleaning is the one the server uses.
local function coreText()
    natives.reset({ resource = 'aeterna_phonecall', side = 'server' })
    assert(loadfile(DIR .. '/../core/import.lua'))()
    return AeternaCore.text
end

-- A sliding-window limiter with a fake clock, shaped like AeternaCore.rateLimit(src, key, max, windowMs).
local function fakeLimiter()
    local clock = { now = 0 }
    local buckets = {}
    local function rl(src, key, max, windowMs)
        local k = tostring(src) .. '|' .. tostring(key)
        local win = buckets[k] or {}
        buckets[k] = win
        local kept = {}
        for _, t in ipairs(win) do
            if t > clock.now - windowMs then kept[#kept + 1] = t end
        end
        buckets[k] = kept
        if #kept >= max then return false end
        kept[#kept + 1] = clock.now
        return true
    end
    return rl, clock
end

-- A sequence rng: returns the digits of `seq` in turn, then repeats.
local function seqRng(seq)
    local i = 0
    return function()
        i = i % #seq + 1
        return tonumber(seq:sub(i, i))
    end
end

describe('aeterna_phonecall', function()
    describe('1. number format (shared/logic/number.lua)', function()
        local N
        before_each(function()
            natives.reset()
            N = load('number.lua')
        end)

        it('555-#### makes 555- and 4 digits', function()
            local n = N.generate('555-####', seqRng('0142'))
            assert.are.equal('555-0142', n)
            for _ = 1, 20 do
                local r = N.generate('555-####', function(lo, hi) return math.random(lo, hi) end)
                assert.is_truthy(r:match('^555%-%d%d%d%d$'))
            end
        end)

        it('refuses formats with fewer than 4 # or over 20 characters', function()
            assert.is_true(N.validateFormat('555-####'))
            local ok, err = N.validateFormat('555-###')
            assert.is_false(ok)
            assert.is_truthy(err:match('#'))
            assert.is_false((N.validateFormat('##########-##########-')))
            assert.is_false((N.validateFormat(nil)))
            assert.is_true(N.validateFormat('####'))
        end)

        it('skips reserved and taken numbers', function()
            local taken = { ['5550001'] = true }
            local n = N.draw('555-####', {
                rng = seqRng('0000' .. '0911' .. '0001' .. '0002'),
                reserved = { '555-0000', '5550911' },
                isTaken = function(d) return taken[d] == true end,
            })
            assert.are.equal('555-0002', n)
        end)

        it('returns nil after 50 failures', function()
            local tries = 0
            local n = N.draw('555-####', {
                rng = function() return 7 end,
                reserved = {},
                isTaken = function() tries = tries + 1 return true end,
            })
            assert.is_nil(n)
            assert.are.equal(50, tries)
        end)

        it('compares numbers by their digits only', function()
            assert.are.equal('5550142', N.digits('555-0142'))
            assert.are.equal('5550142', N.digits('(555) 01 42'))
            assert.is_true(N.same('5550142', '555-0142'))
            assert.is_false(N.same('5550142', '555-0143'))
            assert.is_false(N.same('', ''))
            assert.is_true(N.isReserved({ '555-0911' }, '5550911'))
        end)

        it('matches and normalizes against the format (admin setnumber)', function()
            assert.is_true(N.matches('555-####', '555-1234'))
            assert.is_false(N.matches('555-####', '556-1234'))
            assert.is_false(N.matches('555-####', '555-12a4'))
            assert.are.equal('555-1234', N.normalize('555-####', '555-1234'))
            assert.are.equal('555-1234', N.normalize('555-####', '5551234'))
            assert.is_nil(N.normalize('555-####', '5561234'))
            assert.is_nil(N.normalize('555-####', '55512345'))
        end)
    end)

    describe('config (shared/logic/config.lua)', function()
        local C
        before_each(function()
            natives.reset()
            C = load('config.lua')
        end)

        it('falls back to the default format with one error when it has fewer than 4 #', function()
            local errors = {}
            local cfg = C.resolve({ number = { format = '55-##' } }, function() end,
                function(msg) errors[#errors + 1] = msg end)
            assert.are.equal('555-####', cfg.number.format)
            assert.are.equal(1, #errors)
        end)

        it('ringSeconds is at most 60, the length of the phonekit ring card', function()
            local warns = 0
            local cfg = C.resolve({ call = { ringSeconds = 90 } }, function() warns = warns + 1 end, function() end)
            assert.are.equal(30, cfg.call.ringSeconds)
            assert.are.equal(1, warns)
            assert.are.equal(60, C.resolve({ call = { ringSeconds = 60 } }, function() end, function() end).call.ringSeconds)
        end)

        it('clamps ranges and keeps defaults', function()
            local warns = 0
            local cfg = C.resolve({ sms = { maxLen = 999, keep = 3 }, call = { ringSeconds = 30 } },
                function() warns = warns + 1 end, function() end)
            assert.are.equal(160, cfg.sms.maxLen)
            assert.are.equal(100, cfg.sms.keep)
            assert.are.equal(2, warns)
            assert.are.equal('first_open', cfg.number.assign)
            assert.are.same({ '555-0000', '555-0911' }, cfg.number.reserved)
            assert.are.equal(60, cfg.call.maxMinutes)
            assert.are.equal(20000, cfg.call.channelBase)
            assert.are.equal(30, cfg.recentCalls)
        end)
    end)

    describe('2. message store (shared/logic/store.lua)', function()
        local S, text
        before_each(function()
            text = coreText()
            S = load('store.lua')
        end)

        local function memIo()
            local data = {}
            return {
                data = data,
                load = function(who) return data[who] or {} end,
                save = function(who, list) data[who] = list end,
            }
        end

        it('caps at keep and drops the oldest', function()
            local list = {}
            for i = 1, 12 do
                list = S.push(list, { id = tostring(i), body = 'm' .. i }, 10)
            end
            assert.are.equal(10, #list)
            assert.are.equal('m3', list[1].body)
            assert.are.equal('m12', list[10].body)
        end)

        it('writes both copies', function()
            local io = memIo()
            local ok, out, inc = S.deliver(io, {
                fromWho = 'cid:A', toWho = 'cid:B', fromPeer = '5550001', toPeer = '5550002',
                body = 'hello', ts = 100, keep = 100, idOut = 'a1', idIn = 'b1',
            })
            assert.is_true(ok)
            assert.are.same({ id = 'a1', peer = '5550002', dir = 'out', body = 'hello', ts = 100, read = true },
                io.data['cid:A'][1])
            assert.are.same({ id = 'b1', peer = '5550001', dir = 'in', body = 'hello', ts = 100, read = false },
                io.data['cid:B'][1])
            assert.are.equal('a1', out.id)
            assert.are.equal('b1', inc.id)
        end)

        it('an unknown number stores nothing', function()
            local io = memIo()
            local ok, err = S.deliver(io, { fromWho = 'cid:A', toWho = nil, fromPeer = '1', toPeer = '2',
                body = 'x', ts = 1, keep = 100 })
            assert.is_false(ok)
            assert.are.equal('phonecall.sms.unknown', err)
            assert.is_nil(next(io.data))
        end)

        it('a service message is stored only for the recipient, marked svc', function()
            local io = memIo()
            local ok = S.deliver(io, { fromWho = nil, toWho = 'cid:B', fromPeer = 'Bank', toPeer = '5550002',
                body = 'paid', ts = 5, keep = 100, idIn = 'b2', svc = true })
            assert.is_true(ok)
            assert.is_nil(io.data['cid:A'])
            assert.is_true(io.data['cid:B'][1].svc)
            assert.are.equal('Bank', io.data['cid:B'][1].peer)
        end)

        it('refuses empty bodies, cuts long ones and removes control characters', function()
            local body, err = S.cleanBody(text, '   ', 160)
            assert.is_nil(body)
            assert.are.equal('phonecall.sms.empty', err)
            assert.is_nil((S.cleanBody(text, nil, 160)))
            assert.are.equal('ab', S.cleanBody(text, 'a\nb', 160))
            assert.are.equal('line one two', S.cleanBody(text, 'line one\r\n two', 160):gsub('%s+', ' '))
            local long = string.rep('ก', 200)
            local cut = S.cleanBody(text, long, 160)
            assert.are.equal(160, text.len(cut))
            assert.is_nil((S.cleanBody(text, '\n\t', 160)))
        end)

        it('drops the oldest until a write fits, with one warn', function()
            local list = {}
            for i = 1, 10 do list[i] = { id = tostring(i) } end
            local warns = 0
            local saved = S.shrinkToFit(list, function(l) return #l <= 6 end, function() warns = warns + 1 end)
            assert.are.equal(6, #saved)
            assert.are.equal('5', saved[1].id)
            assert.are.equal(1, warns)
            local same = S.shrinkToFit({ { id = 'x' } }, function() return true end, function() warns = warns + 1 end)
            assert.are.equal(1, #same)
            assert.are.equal(1, warns)
        end)

        it('makes short ids', function()
            assert.are.equal('1', S.makeId(1))
            assert.are.equal('z', S.makeId(35))
            assert.are.equal('10', S.makeId(36))
            assert.is_true(#S.makeId(2 ^ 52) <= 12)
        end)

        it('call log keeps the newest entries', function()
            local list = {}
            for i = 1, 35 do list = S.push(list, { ts = i }, 30) end
            assert.are.equal(30, #list)
            assert.are.equal(6, list[1].ts)
        end)
    end)

    describe('3. threads (shared/logic/store.lua)', function()
        local S
        before_each(function()
            natives.reset()
            S = load('store.lua')
        end)

        local function msg(i, peer, dir, read, svc)
            return { id = tostring(i), peer = peer, dir = dir, body = 'b' .. i, ts = i, read = read, svc = svc }
        end

        it('groups by peer, newest first, with unread counts', function()
            local list = {
                msg(1, '5550001', 'in', false), msg(2, '5550002', 'out', true),
                msg(3, '5550001', 'in', false), msg(4, 'Bank', 'in', false, true),
                msg(5, '5550002', 'in', true),
            }
            local th = S.threads(list)
            assert.are.equal(3, #th)
            assert.are.equal('5550002', th[1].peer)
            assert.are.equal(5, th[1].ts)
            assert.are.equal(0, th[1].unread)
            assert.are.equal('Bank', th[2].peer)
            assert.is_true(th[2].svc)
            assert.are.equal('5550001', th[3].peer)
            assert.are.equal(2, th[3].unread)
            assert.are.equal('b3', th[3].last.body)
            assert.are.equal(3, S.unread(list))
        end)

        it('a number and a service label with the same text are two threads', function()
            local th = S.threads({ msg(1, '5550001', 'in', true), msg(2, '5550001', 'in', true, true) })
            assert.are.equal(2, #th)
        end)

        it('lists at most 50 threads and a thread shows its last 50 messages', function()
            local list = {}
            for i = 1, 60 do list[#list + 1] = msg(i, tostring(1000 + i), 'in', true) end
            local th = S.threads(list)
            assert.are.equal(50, #th)
            assert.are.equal(tostring(1060), th[1].peer)

            local one = {}
            for i = 1, 70 do one[#one + 1] = msg(i, '5550001', i % 2 == 0 and 'out' or 'in', true) end
            one[#one + 1] = msg(71, '5550002', 'in', true)
            local t = S.thread(one, '5550001')
            assert.are.equal(50, #t)
            assert.are.equal('21', t[1].id)
            assert.are.equal('70', t[50].id)
        end)

        it('opening a thread marks its messages read', function()
            local list = { msg(1, '5550001', 'in', false), msg(2, '5550002', 'in', false),
                msg(3, '5550001', 'in', false) }
            assert.are.equal(2, S.markRead(list, '5550001'))
            assert.is_true(list[1].read)
            assert.is_false(list[2].read)
            assert.are.equal(0, S.markRead(list, '5550001'))
            assert.are.equal(1, S.unread(list))
        end)
    end)

    describe('4. rate limits (shared/logic/limits.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load('limits.lua')
        end)

        it('1 message / 2 s per sender', function()
            local rl, clock = fakeLimiter()
            assert.is_true(L.checkSms(rl, 1, '5550002'))
            local ok, err = L.checkSms(rl, 1, '5550003')
            assert.is_false(ok)
            assert.are.equal('phonecall.sms.slow', err)
            clock.now = 2001
            assert.is_true(L.checkSms(rl, 1, '5550003'))
        end)

        it('15 messages / 60 s per sender', function()
            local rl, clock = fakeLimiter()
            for i = 1, 15 do
                clock.now = (i - 1) * 2100
                assert.is_true(L.checkSms(rl, 1, tostring(5550000 + i)), 'message ' .. i)
            end
            clock.now = 15 * 2100
            assert.is_false(L.checkSms(rl, 1, '5559999'))
        end)

        it('6 messages / 60 s per sender and recipient pair', function()
            local rl, clock = fakeLimiter()
            for i = 1, 6 do
                clock.now = (i - 1) * 2100
                assert.is_true(L.checkSms(rl, 1, '5550002'))
            end
            clock.now = 6 * 2100
            assert.is_false(L.checkSms(rl, 1, '5550002'))
            clock.now = 7 * 2100
            assert.is_true(L.checkSms(rl, 1, '5550003'))
        end)

        it('sendSms: 30 / 60 s per calling resource', function()
            local rl, clock = fakeLimiter()
            for _ = 1, 30 do assert.is_true(L.checkService(rl, 'bank')) end
            assert.is_false(L.checkService(rl, 'bank'))
            assert.is_true(L.checkService(rl, 'job'))
            clock.now = 60001
            assert.is_true(L.checkService(rl, 'bank'))
        end)

        it('dial: 1 / 3000 ms and 10 / 60 s', function()
            local rl, clock = fakeLimiter()
            assert.is_true(L.checkDial(rl, 1))
            assert.is_false(L.checkDial(rl, 1))
            for i = 2, 10 do
                clock.now = (i - 1) * 3001
                assert.is_true(L.checkDial(rl, 1))
            end
            clock.now = 10 * 3001
            assert.is_false(L.checkDial(rl, 1))
        end)

        it('re-validates dial and send payloads with the spec schemas', function()
            coreText()
            local v = AeternaCore.validate
            local ok, _, clean = v({ number = '(555) 01-42' }, L.DIAL_SCHEMA)
            assert.is_true(ok)
            assert.are.equal('(555) 01-42', clean.number)
            assert.is_false((v({ number = '555-01a2' }, L.DIAL_SCHEMA)))
            -- core's maxLen cuts rather than refuses: a 21-digit number comes back as its first 20 digits
            local _, _, long = v({ number = string.rep('5', 21) }, L.DIAL_SCHEMA)
            assert.are.equal(20, #long.number)
            assert.is_false((v({ number = 5550142 }, L.DIAL_SCHEMA)))
            assert.is_false((v({ number = '5550142', extra = 1 }, L.DIAL_SCHEMA)))
            assert.is_true((v({ number = '5550142', body = 'hi' }, L.SEND_SCHEMA)))
            local okLong, _, cut = v({ number = '5550142', body = string.rep('ก', 400) }, L.SEND_SCHEMA)
            assert.is_true(okLong)
            assert.are.equal(300, AeternaCore.text.len(cut.body))
            assert.is_false((v({ number = '5550142' }, L.SEND_SCHEMA)))
            assert.is_false((v({ number = '', body = 'hi' }, L.SEND_SCHEMA)))
        end)
    end)

    describe('5. call state machine (shared/logic/calls.lua)', function()
        local C, mgr, clock
        before_each(function()
            natives.reset()
            C = load('calls.lua')
            clock = { now = 0 }
            mgr = C.create({ now = function() return clock.now end, ringSeconds = 30, maxSeconds = 3600 })
        end)

        local OK = { aCan = true, bCan = true, backend = true }

        it('dialing -> ringing -> active -> ended (hangup)', function()
            local call = assert(mgr:dial(1, 2, OK))
            assert.are.equal('ringing', call.state)
            assert.are.equal('dialing', mgr:viewState(call, 1))
            assert.are.equal('ringing', mgr:viewState(call, 2))
            assert.are.equal(call, mgr:of(1))
            assert.are.equal(call, mgr:of(2))
            assert.is_nil(mgr:answer(1))
            clock.now = 4
            assert.are.equal(call, mgr:answer(2))
            assert.are.equal('active', call.state)
            assert.are.equal('active', mgr:viewState(call, 1))
            clock.now = 64
            local c2, reason = mgr:hangup(1)
            assert.are.equal(call, c2)
            assert.are.equal('hangup', reason)
            mgr:finish(call, reason)
            assert.are.equal('ended', call.state)
            assert.are.equal('hangup', call.reason)
            assert.are.equal(60, call.seconds)
            assert.is_nil(mgr:of(1))
            assert.is_nil(mgr:of(2))
        end)

        it('callee declines while ringing; caller hangs up while dialing', function()
            local call = assert(mgr:dial(1, 2, OK))
            local _, reason = mgr:hangup(2)
            assert.are.equal('declined', reason)
            mgr:finish(call, reason)
            assert.are.equal(0, call.seconds)
            local call2 = assert(mgr:dial(1, 2, OK))
            local _, r2 = mgr:hangup(1)
            assert.are.equal('hangup', r2)
            mgr:finish(call2, r2)
            assert.is_nil(mgr:hangup(1))
        end)

        it('a call to a busy player ends busy; a busy caller is refused busy', function()
            assert(mgr:dial(1, 2, OK))
            local none, reason = mgr:dial(3, 2, OK)
            assert.is_nil(none)
            assert.are.equal('busy', reason)
            local _, r2 = mgr:dial(1, 3, OK)
            assert.are.equal('busy', r2)
            mgr:hold(4)
            local _, r3 = mgr:dial(3, 4, OK)
            assert.are.equal('busy', r3)
            mgr:release(4)
            assert.is_truthy(mgr:dial(3, 4, OK))
        end)

        it('self-call, unknown callee, a phone that cannot call or no backend end unavailable', function()
            assert.are.equal('unavailable', select(2, mgr:dial(1, 1, OK)))
            assert.are.equal('unavailable', select(2, mgr:dial(1, nil, OK)))
            assert.are.equal('unavailable', select(2, mgr:dial(1, 2, { aCan = true, bCan = false, backend = true })))
            assert.are.equal('unavailable', select(2, mgr:dial(1, 2, { aCan = false, bCan = true, backend = true })))
            assert.are.equal('unavailable', select(2, mgr:dial(1, 2, { aCan = true, bCan = true, backend = false })))
            assert.is_nil(mgr:of(1))
        end)

        it('ring timeout ends missed; an active call past maxMinutes ends limit', function()
            local call = assert(mgr:dial(1, 2, OK))
            clock.now = 29
            assert.are.equal(0, #mgr:expire())
            clock.now = 30
            local due = mgr:expire()
            assert.are.equal(1, #due)
            assert.are.equal(call, due[1].call)
            assert.are.equal('missed', due[1].reason)

            mgr:finish(call, 'missed')
            local c2 = assert(mgr:dial(1, 2, OK))
            mgr:answer(2)
            clock.now = 30 + 3599
            assert.are.equal(0, #mgr:expire())
            clock.now = 30 + 3600
            local due2 = mgr:expire()
            assert.are.equal(c2, due2[1].call)
            assert.are.equal('limit', due2[1].reason)
        end)

        it('dropped and every end reason are accepted; unknown reasons are not', function()
            for reason in pairs(C.REASONS) do
                local call = assert(mgr:dial(1, 2, OK))
                assert.is_true(mgr:finish(call, reason) ~= nil)
                assert.are.equal(reason, call.reason)
            end
            local call = assert(mgr:dial(1, 2, OK))
            assert.is_nil(mgr:finish(call, 'boom'))
            assert.are.equal('ringing', call.state)
            assert.is_nil(mgr:finish({ state = 'ended' }, 'hangup'))
        end)

        it('canAnswer finds the ringing call for its callee without changing its state', function()
            local call = assert(mgr:dial(1, 2, OK))
            assert.is_nil(mgr:canAnswer(1))
            assert.are.equal(call, mgr:canAnswer(2))
            assert.are.equal('ringing', call.state)
            assert.is_nil(call.activeAt)
            mgr:answer(2)
            assert.is_nil(mgr:canAnswer(2))
        end)

        it('a call ended from ringing was never active and has no seconds', function()
            local call = assert(mgr:dial(1, 2, OK))
            clock.now = 10
            mgr:finish(call, 'voice_off')
            assert.is_false(call.wasActive)
            assert.are.equal(0, call.seconds)
        end)

        it('allocates channel slots lowest-free and releases them', function()
            local slots = C.createSlots(3)
            assert.are.equal(1, slots:alloc())
            assert.are.equal(2, slots:alloc())
            assert.are.equal(3, slots:alloc())
            assert.is_nil(slots:alloc())
            slots:free(2)
            assert.are.equal(2, slots:alloc())
            slots:free(1)
            slots:free(3)
            assert.are.equal(1, slots:alloc())
        end)
    end)

    describe('6-7. voice backend (shared/logic/voice.lua)', function()
        local V

        local function fakeNatives(opts)
            local o = opts or {}
            local log = { create = {}, add = {}, mute = {}, remove = {}, delete = {} }
            local n = {
                CreateVoiceChannel = function(mode, dist)
                    log.create[#log.create + 1] = { mode, dist }
                    if o.createError then error('create failed') end
                    if o.createResult ~= nil then return o.createResult end
                    return 7
                end,
                AddPlayerToVoiceChannel = function(ch, src) log.add[#log.add + 1] = { ch, src } end,
                SetPlayerMutedInVoiceChannel = function(ch, src, muted) log.mute[#log.mute + 1] = { ch, src, muted } end,
                RemovePlayerFromVoiceChannel = function(ch, src)
                    log.remove[#log.remove + 1] = { ch, src }
                    if o.removeError then error('remove failed') end
                end,
                DeleteVoiceChannel = function(ch)
                    log.delete[#log.delete + 1] = ch
                    if o.deleteError then error('delete failed') end
                end,
            }
            return n, log
        end

        local function fakePma(started)
            local calls = {}
            return {
                calls = calls,
                state = function(name) return (name == 'pma-voice' and started) and 'started' or 'stopped' end,
                setPlayerCall = function(src, ch) calls[#calls + 1] = { src, ch } end,
            }
        end

        before_each(function()
            natives.reset()
            V = load('voice.lua')
        end)

        it('gta5enhanced picks channels and never touches the pma-voice exports', function()
            local n = fakeNatives()
            local pma = fakePma(true)
            local b = V.create({ gamename = 'gta5enhanced', natives = n, resourceState = pma.state,
                setPlayerCall = pma.setPlayerCall })
            assert.are.equal('channels', b.kind)
            assert.is_true(b:available())
            assert.are.equal('channels', b:name())
            local call = { id = 'c1' }
            assert.is_true(b:connect(call, { 1, 2 }))
            b:disconnect(call, function() return true end)
            assert.are.equal(0, #pma.calls)
        end)

        it('any other gamename picks pma', function()
            for _, g in ipairs({ 'gta5', '', 'rdr3' }) do
                assert.are.equal('pma', V.create({ gamename = g, natives = {} }).kind)
            end
            assert.are.equal('pma', V.create({ natives = {} }).kind)
        end)

        it('pma with pma-voice not started is no backend and makes no setPlayerCall call', function()
            local pma = fakePma(false)
            local b = V.create({ gamename = 'gta5', natives = {}, resourceState = pma.state,
                setPlayerCall = pma.setPlayerCall, channelBase = 20000 })
            assert.is_false(b:available())
            assert.are.equal('none', b:name())
            local ok, reason = b:connect({ id = 'c1' }, { 1, 2 })
            assert.is_false(ok)
            assert.are.equal('voice_off', reason)
            assert.are.equal(0, #pma.calls)
        end)

        it('pma started: lowest free channel above channelBase for both, 0 on end, slot freed', function()
            local pma = fakePma(true)
            local b = V.create({ gamename = 'gta5', natives = {}, resourceState = pma.state,
                setPlayerCall = pma.setPlayerCall, channelBase = 20000 })
            assert.are.equal('pma', b:name())
            local c1, c2 = { id = 'c1' }, { id = 'c2' }
            assert.is_true(b:connect(c1, { 1, 2 }))
            assert.is_true(b:connect(c2, { 3, 4 }))
            assert.are.same({ { 1, 20001 }, { 2, 20001 }, { 3, 20002 }, { 4, 20002 } }, pma.calls)
            b:disconnect(c1, function(src) return src ~= 2 end)
            assert.are.same({ 1, 0 }, pma.calls[5])
            assert.are.equal(5, #pma.calls)
            local c3 = { id = 'c3' }
            assert.is_true(b:connect(c3, { 5, 6 }))
            assert.are.same({ 5, 20001 }, pma.calls[6])
        end)

        it('channels with a missing native counts as no backend', function()
            local n = fakeNatives()
            n.DeleteVoiceChannel = nil
            local b = V.create({ gamename = 'gta5enhanced', natives = n })
            assert.are.equal('channels', b.kind)
            assert.is_false(b:available())
            assert.are.equal('none', b:name())
        end)

        it('channels: one mode-0 channel, both added and unmuted; end removes connected players, deletes once', function()
            local n, log = fakeNatives()
            local b = V.create({ gamename = 'gta5enhanced', natives = n })
            local call = { id = 'c1' }
            assert.is_true(b:connect(call, { 1, 2 }))
            assert.are.same({ { 0, 0.0 } }, log.create)
            assert.are.same({ { 7, 1 }, { 7, 2 } }, log.add)
            assert.are.same({ { 7, 1, false }, { 7, 2, false } }, log.mute)
            b:disconnect(call, function(src) return src == 1 end)
            assert.are.same({ { 7, 1 } }, log.remove)
            assert.are.same({ 7 }, log.delete)
            b:disconnect(call, function() return true end)
            assert.are.same({ 7 }, log.delete)
        end)

        it('a create error, a non-number, a negative id or 65535 ends voice_off and adds nobody', function()
            for _, o in ipairs({ { createError = true }, { createResult = -1 }, { createResult = 65535 },
                { createResult = 'x' } }) do
                local n, log = fakeNatives(o)
                local warns = {}
                local b = V.create({ gamename = 'gta5enhanced', natives = n,
                    warn = function(msg, f) warns[#warns + 1] = f end })
                local ok, reason = b:connect({ id = 'c' }, { 1, 2 })
                assert.is_false(ok)
                assert.are.equal('voice_off', reason)
                assert.are.equal(0, #log.add)
                assert.are.equal(1, #warns)
                assert.is_string(warns[1].result)
            end
        end)

        it('remove and delete errors are caught', function()
            local n, log = fakeNatives({ removeError = true, deleteError = true })
            local b = V.create({ gamename = 'gta5enhanced', natives = n, warn = function() end })
            local call = { id = 'c' }
            assert.is_true(b:connect(call, { 1, 2 }))
            assert.has_no.errors(function() b:disconnect(call, function() return true end) end)
            assert.are.equal(2, #log.remove)
            assert.are.equal(1, #log.delete)
        end)

        it('probe creates one mode-0 channel and deletes it with nobody in it', function()
            local n, log = fakeNatives()
            local b = V.create({ gamename = 'gta5enhanced', natives = n })
            local ok = b:probe()
            assert.is_true(ok)
            assert.are.same({ { 0, 0.0 } }, log.create)
            assert.are.equal(0, #log.add)
            assert.are.same({ 7 }, log.delete)
            local bad = V.create({ gamename = 'gta5enhanced', natives = (fakeNatives({ createResult = 65535 })),
                warn = function() end })
            local ok2, detail = bad:probe()
            assert.is_false(ok2)
            assert.is_truthy(detail:match('65535'))
        end)
    end)

    describe('8. names map (shared/logic/names.lua)', function()
        local M
        before_each(function()
            natives.reset()
            M = load('names.lua')
        end)

        it('accepts digits keys and short names', function()
            local ok, clean = M.validate({ ['5550142'] = 'Mint', ['5550143'] = 'สมชาย' })
            assert.is_true(ok)
            assert.are.equal('Mint', clean['5550142'])
        end)

        it('refuses over 100 keys, long values, and bad keys', function()
            local big = {}
            for i = 1, 101 do big[tostring(5550000 + i)] = 'n' end
            assert.is_false((M.validate(big)))
            assert.is_false((M.validate({ ['5550142'] = string.rep('a', 41) })))
            assert.is_true((M.validate({ ['5550142'] = string.rep('ก', 40) })))
            assert.is_false((M.validate({ ['555-0142'] = 'x' })))
            assert.is_false((M.validate({ [string.rep('1', 21)] = 'x' })))
            assert.is_false((M.validate({ ['5550142'] = 5 })))
            assert.is_false((M.validate('x')))
        end)

        it('coalesces names updates into one trailing send at least 5 s after the previous one', function()
            local th = M.createThrottle(5000)
            assert.are.equal(0, th:request(1000))        -- askNames: send now
            assert.are.equal(4000, th:request(2000))     -- contactsChanged 1 s later: one trailing send at 6000
            assert.is_nil(th:request(3000))              -- already scheduled
            th:fire(6000)
            assert.are.equal(4500, th:request(6500))     -- 0.5 s after the trailing send: wait until 11000
            th:fire(11000)
            assert.are.equal(0, th:request(16000))
        end)

        it('labels fall back to the number', function()
            local names = { ['5550142'] = 'Mint' }
            assert.are.equal('Mint', M.label(names, '555-0142'))
            assert.are.equal('555-0143', M.label(names, '555-0143'))
            assert.are.equal('555-0143', M.label(nil, '555-0143'))
            assert.are.equal('5550143', M.label(names, '5550143'))
        end)

        it('builds the map from phonekit contacts (client side)', function()
            local map = M.fromContacts({
                { name = 'Mint', number = '555-0142' },
                { name = '', number = '555-0144' },
                { name = 'No digits', number = '---' },
                { name = string.rep('a', 50), number = '5550145' },
            })
            assert.are.equal('Mint', map['5550142'])
            assert.is_nil(map['5550144'])
            assert.are.equal(40, #map['5550145'])
            local many = {}
            for i = 1, 150 do many[i] = { name = 'n' .. i, number = tostring(5550000 + i) } end
            local n = 0
            for _ in pairs(M.fromContacts(many)) do n = n + 1 end
            assert.are.equal(100, n)
        end)
    end)

    describe('self-test decisions (shared/logic/selftest.lua)', function()
        local T, N
        before_each(function()
            natives.reset()
            T = load('selftest.lua')
            N = load('number.lua')
        end)

        it('lists exactly the rows of the spec table', function()
            local names = {}
            for i, row in ipairs(T.ROWS) do names[i] = row.name end
            assert.are.same({
                'aeterna_phonecall.number_format', 'aeterna_phonecall.number_unique',
                'aeterna_phonecall.sms_store_cap', 'aeterna_phonecall.sms_rate_limit',
                'aeterna_phonecall.voice_detect', 'aeterna_phonecall.voice_channel',
                'aeterna_phonecall.my_number', 'aeterna_phonecall.sms_ab', 'aeterna_phonecall.call_ab',
                'aeterna_phonecall.call_busy',
            }, names)
            local byName = {}
            for _, row in ipairs(T.ROWS) do byName[row.name] = row end
            assert.are.same({ kind = 'mock', players = 1, destructive = false },
                byName['aeterna_phonecall.number_unique'].meta)
            assert.are.equal('eye', byName['aeterna_phonecall.sms_ab'].meta.kind)
            assert.are.equal(2, byName['aeterna_phonecall.sms_ab'].meta.players)
            assert.is_true(byName['aeterna_phonecall.sms_ab'].meta.destructive)
            assert.are.equal('phonecall.selftest.sms_ab', byName['aeterna_phonecall.sms_ab'].expect)
            assert.are.equal('ped', byName['aeterna_phonecall.call_busy'].meta.kind)
            assert.is_nil(byName['aeterna_phonecall.call_busy'].expect)
        end)

        it('builds meta with translated expect and the pma skip only on the pma backend', function()
            local t = function(k) return 'T:' .. k end
            local rows = T.metas(t, 'channels')
            assert.are.equal('T:phonecall.selftest.call_ab', rows['aeterna_phonecall.call_ab'].expect)
            assert.is_nil(rows['aeterna_phonecall.call_ab'].skipWhen)
            local pma = T.metas(t, 'pma')
            assert.are.same({ resources = { 'pma-voice' } }, pma['aeterna_phonecall.call_ab'].skipWhen)
            assert.are.same({ resources = { 'pma-voice' } }, pma['aeterna_phonecall.call_busy'].skipWhen)
            assert.is_nil(pma['aeterna_phonecall.sms_ab'].skipWhen)
            assert.are.equal('T:phonecall.selftest.my_number', pma['aeterna_phonecall.my_number'].expect)
        end)

        it('number_format: generated numbers match the format', function()
            local state, detail = T.numberFormat(N, '555-####', function(lo, hi) return math.random(lo, hi) end)
            assert.are.equal('pass', state)
            assert.is_truthy(detail:match('555'))
            local bad = T.numberFormat(N, '55-##', function() return 1 end)
            assert.are.equal('fail', bad)
        end)

        it('number_unique: two different numbers, owner index, taken refused', function()
            assert.are.equal('mock', (T.numberUnique({ a = '555-0001', b = '555-0002', ownerA = 'test:a',
                ownerB = 'test:b', takenRefused = true, restored = true })))
            assert.are.equal('fail', (T.numberUnique({ a = '555-0001', b = '5550001', ownerA = 'test:a',
                ownerB = 'test:b', takenRefused = true, restored = true })))
            assert.are.equal('fail', (T.numberUnique({ a = '555-0001', b = '555-0002', ownerA = 'test:b',
                ownerB = 'test:b', takenRefused = true, restored = true })))
            assert.are.equal('fail', (T.numberUnique({ a = '555-0001', b = '555-0002', ownerA = 'test:a',
                ownerB = 'test:b', takenRefused = false, restored = true })))
            local state, detail = T.numberUnique({ a = '555-0001', b = '555-0002', ownerA = 'test:a',
                ownerB = 'test:b', takenRefused = true, restored = false })
            assert.are.equal('fail', state)
            assert.is_truthy(detail:match('restore'))
            assert.are.equal('fail', (T.numberUnique({})))
        end)

        it('sms_store_cap: both lists at keep, oldest gone', function()
            assert.are.equal('mock', (T.smsCap({ keep = 100, lenA = 100, lenB = 100, oldestGone = true,
                restored = true })))
            assert.are.equal('fail', (T.smsCap({ keep = 100, lenA = 101, lenB = 100, oldestGone = true,
                restored = true })))
            assert.are.equal('fail', (T.smsCap({ keep = 100, lenA = 100, lenB = 100, oldestGone = false,
                restored = true })))
            assert.are.equal('fail', (T.smsCap({ keep = 100, lenA = 100, lenB = 100, oldestGone = true,
                restored = false })))
        end)

        it('sms_rate_limit: runs every rule against a limiter', function()
            local rl = fakeLimiter()
            local L = load('limits.lua')
            local state, detail = T.smsRate(L, rl, 'selftest:r1')
            assert.are.equal('pass', state)
            assert.is_truthy(detail:match('2000'))
            local state2 = T.smsRate(L, function() return true end, 'selftest:r2')
            assert.are.equal('fail', state2)
        end)

        it('voice_detect passes with the backend in the detail, none included', function()
            for _, n in ipairs({ 'channels', 'pma', 'none' }) do
                local state, detail = T.voiceDetect(n)
                assert.are.equal('pass', state)
                assert.is_truthy(detail:find(n, 1, true))
            end
        end)

        it('voice_channel skips off channels, passes or fails on the probe', function()
            assert.are.equal('skip', (T.voiceChannel('pma', nil)))
            assert.are.equal('skip', (T.voiceChannel('none', nil)))
            assert.are.equal('pass', (T.voiceChannel('channels', true, 'channel 3')))
            assert.are.equal('fail', (T.voiceChannel('channels', false, 'create returned 65535')))
        end)

        it('client call outcomes for call_ab and call_busy', function()
            assert.are.equal('ready', T.callOutcome('call_ab', 'A', { state = 'dialing' }))
            assert.are.equal('ready', T.callOutcome('call_ab', 'B', { state = 'ringing' }))
            assert.is_nil(T.callOutcome('call_ab', 'A', { state = 'ringing' }))
            assert.are.equal('skip', T.callOutcome('call_ab', 'A', { state = 'ended', reason = 'voice_off' }))
            local s, d = T.callOutcome('call_ab', 'A', { state = 'ended', reason = 'unavailable' })
            assert.are.equal('fail', s)
            assert.is_truthy(d:match('unavailable'))
            assert.are.equal('pass', T.callOutcome('call_busy', 'A', { state = 'ended', reason = 'busy' }))
            assert.are.equal('fail', T.callOutcome('call_busy', 'A', { state = 'dialing' }))
            assert.are.equal('fail', T.callOutcome('call_busy', 'A', { state = 'ended', reason = 'hangup' }))
            assert.are.equal('skip', T.callOutcome('call_busy', 'A', { state = 'ended', reason = 'voice_off' }))
        end)

        it('a set-up failure the server sends as a call state becomes a visible fail detail', function()
            assert.are.equal('open the phone once first', T.setupFailure('st-nonumber'))
            assert.are.equal('a player has no character loaded', T.setupFailure('st-nosession'))
            assert.is_nil(T.setupFailure('c1'))
            assert.is_nil(T.setupFailure(nil))
            local st = { callId = 'st-nonumber', state = 'ended', reason = 'unavailable' }
            local s1, d1 = T.callOutcome('call_ab', 'B', st)
            assert.are.equal('fail', s1)
            assert.are.equal('open the phone once first', d1)
            local s2, d2 = T.callOutcome('call_busy', 'B', { callId = 'st-nosession', state = 'ended',
                reason = 'unavailable' })
            assert.are.equal('fail', s2)
            assert.are.equal('a player has no character loaded', d2)
        end)

        it('tracks two-player tests from selftestStarted until selftestEnd', function()
            local tr = T.createTracker()
            local ctx = { kind = 'eye', side = 'client', a = 1, b = 2, destructive = true }
            assert.are.same({ a = 1, b = 2 }, tr:start('r1', 'aeterna_phonecall.sms_ab', ctx))
            assert.is_true(tr:active('r1', 'aeterna_phonecall.sms_ab'))
            -- a second start of the same test, a missing or identical B, or a test that is not ours: nothing to do
            assert.is_nil(tr:start('r1', 'aeterna_phonecall.sms_ab', ctx))
            assert.is_nil(tr:start('r2', 'aeterna_phonecall.call_ab', { a = 3 }))
            assert.is_nil(tr:start('r2', 'aeterna_phonecall.call_ab', { a = 3, b = 3 }))
            assert.is_nil(tr:start('r2', 'aeterna_phonecall.my_number', { a = 3, b = 4 }))
            assert.is_nil(tr:start('r2', 'aeterna_phonecall.call_busy', nil))
            tr:finish('r1', 'aeterna_phonecall.sms_ab')
            assert.is_false(tr:active('r1', 'aeterna_phonecall.sms_ab'))
            assert.is_nil(next(tr.items))
            assert.are.same({ a = 5, b = 6 }, tr:start('r3', 'aeterna_phonecall.call_busy', { a = 5, b = 6 }))
            tr:clear()
            assert.is_false(tr:active('r3', 'aeterna_phonecall.call_busy'))
            assert.are.same({ a = 5, b = 6 }, tr:start('r3', 'aeterna_phonecall.call_busy', { a = 5, b = 6 }))
        end)
    end)
end)
