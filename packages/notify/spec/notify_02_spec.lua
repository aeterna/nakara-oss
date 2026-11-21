-- notify_02_spec.lua -- aeterna_notify 0.2 additions (docs/specs/aeterna_notify.md "Tests (0.2, busted)").

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local LOGIC_FILES = {
    'shared/logic/notify.lua',
    'shared/logic/actions.lua',
    'shared/logic/countdown.lua',
    'shared/logic/history.lua',
}

local function loadLogic()
    NotifyLogic = nil
    for i = 1, #LOGIC_FILES do
        assert(loadfile(DIR .. '/' .. LOGIC_FILES[i]))()
    end
    return NotifyLogic
end

local function coreStub(extra)
    local warnings = {}
    local t = {
        log = {
            debug = function() end,
            info = function() end,
            warn = function(msg, fields) warnings[#warnings + 1] = { msg = msg, fields = fields } end,
            error = function() end,
        },
        t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
        lang = function() return 'en' end,
        rateLimit = function() return true end,
        can = function(src) return tonumber(src) == 0 end,
        time = { now = function() return 1700000000 end },
        kvp = {
            get = function(name, version, default)
                local raw = natives.get_kvp('aeterna_notify:' .. name .. ':v' .. version)
                if not raw then return default end
                return json.decode(raw)
            end,
            set = function(name, version, val)
                natives.set_kvp('aeterna_notify:' .. name .. ':v' .. version, json.encode(val))
            end,
        },
        key = function() end,
    }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t, warnings
end

local function nuiOfType(messages, msgType)
    local out = {}
    for i = 1, #messages do
        local m = messages[i][1]
        if type(m) == 'table' and m.type == msgType then out[#out + 1] = m end
    end
    return out
end

describe('aeterna_notify 0.2', function()
    describe('1. actions', function()
        local L
        before_each(function()
            natives.reset()
            L = loadLogic()
        end)

        it('falls back to no actions with one warn for three actions, a bad id or a 21-char label', function()
            local cases = {
                { { id = 'a', label = 'A' }, { id = 'b', label = 'B' }, { id = 'c', label = 'C' } },
                { { id = 'bad id', label = 'A' } },
                { { id = 'ok', label = string.rep('L', 21) } },
                { { id = 'dup', label = 'A' }, { id = 'dup', label = 'B' } },
            }
            for i = 1, #cases do
                local warnings = {}
                local ok, err, clean = L.validateToastOpts({ title = 'Hi', actions = cases[i] }, nil, function(msg, fields)
                    warnings[#warnings + 1] = { msg = msg, fields = fields }
                end)
                assert.is_true(ok, 'case ' .. i)
                assert.is_nil(err)
                assert.is_nil(clean.actions, 'case ' .. i)
                assert.are.equal(1, #warnings, 'case ' .. i)
            end
        end)

        it('keeps up to two good actions with secondary as the default variant', function()
            local ok, _, clean = L.validateToastOpts({
                title = 'Mind sent a location',
                actions = { { id = 'pin', label = 'Pin it', variant = 'primary' }, { id = 'skip', label = 'Ignore' } },
            }, { defaultDuration = 4000, actionDuration = 8000 })
            assert.is_true(ok)
            assert.are.equal(2, #clean.actions)
            assert.are.same({ id = 'pin', label = 'Pin it', variant = 'primary' }, clean.actions[1])
            assert.are.same({ id = 'skip', label = 'Ignore', variant = 'secondary' }, clean.actions[2])
            assert.are.equal(8000, clean.duration)
            assert.is_true(clean.sound)
            assert.is_true(clean.history)
            assert.is_true(clean.merge)
        end)

        it('drops unknown, wrong-action, second and late presses and answers a good press once', function()
            local tr = L.createActionTracker({ max = 8, graceMs = 2000 })
            tr:track(1, { toastId = 't1', actions = { 'pin', 'skip' }, duration = 4000, owner = 'my_job' }, 0)

            assert.is_false((tr:press(1, 'nope', 'pin', 100)))
            assert.is_false((tr:press(2, 't1', 'pin', 100)))
            assert.is_false((tr:press(1, 't1', 'other', 100)))
            local ok, rec = tr:press(1, 't1', 'pin', 100)
            assert.is_true(ok)
            assert.are.same({ owner = 'my_job', toastId = 't1', action = 'pin' }, rec)
            assert.is_false((tr:press(1, 't1', 'pin', 200)))

            tr:track(1, { toastId = 't2', actions = { 'pin' }, duration = 4000, owner = 'my_job' }, 0)
            assert.is_false((tr:press(1, 't2', 'pin', 6001)))
            tr:track(1, { toastId = 't3', actions = { 'pin' }, duration = 4000, owner = 'my_job' }, 0)
            assert.is_true((tr:press(1, 't3', 'pin', 6000)))
        end)

        it('keeps at most 8 open action toasts per player; the ninth replaces the oldest', function()
            local tr = L.createActionTracker({ max = 8, graceMs = 2000 })
            for i = 1, 9 do
                tr:track(1, { toastId = 't' .. i, actions = { 'a' }, duration = 4000, owner = 'x' }, 0)
            end
            assert.are.equal(8, tr:count(1))
            assert.is_false((tr:press(1, 't1', 'a', 10)))
            assert.is_true((tr:press(1, 't9', 'a', 10)))
        end)

        it('server: a forged press is dropped and a good press fires aeterna_notify:action once with the owner', function()
            natives.reset({ resource = 'aeterna_notify', side = 'server', invoker = 'my_job', players = { [1] = 'Alice' } })
            natives.spy('RegisterCommand')
            local core = coreStub()
            natives.stub('AeternaCore', core)
            local res = resource.load_resource(DIR, 'server')

            local ok, err, clean = res.exports.notify(1, {
                title = 'Accept the job?',
                actions = { { id = 'yes', label = 'Yes', variant = 'primary' }, { id = 'no', label = 'No' } },
            })
            assert.is_true(ok)
            assert.is_nil(err)
            assert.is_string(clean.toastId)
            local sent = natives.last_emitted('client', 'aeterna_notify:cl:toast').args[1]
            assert.are.equal(clean.toastId, sent.toastId)
            assert.are.equal('my_job', sent.owner)

            natives.fire_net('aeterna_notify:sv:action', 1, { toastId = 'tzz', action = 'yes' })
            natives.fire_net('aeterna_notify:sv:action', 1, { toastId = clean.toastId, action = 'maybe' })
            natives.fire_net('aeterna_notify:sv:action', 2, { toastId = clean.toastId, action = 'yes' })
            natives.fire_net('aeterna_notify:sv:action', 1, 'garbage')
            assert.are.equal(0, #natives.emitted('local', 'aeterna_notify:action'))

            natives.fire_net('aeterna_notify:sv:action', 1, { toastId = clean.toastId, action = 'yes' })
            natives.fire_net('aeterna_notify:sv:action', 1, { toastId = clean.toastId, action = 'yes' })
            local evs = natives.emitted('local', 'aeterna_notify:action')
            assert.are.equal(1, #evs)
            assert.are.equal(1, evs[1].args[1])
            assert.are.same({ owner = 'my_job', toastId = clean.toastId, action = 'yes' }, evs[1].args[2])
        end)

        it('server: drops presses when the rate limit refuses', function()
            natives.reset({ resource = 'aeterna_notify', side = 'server', invoker = 'my_job', players = { [1] = 'Alice' } })
            natives.spy('RegisterCommand')
            local limited = {}
            natives.stub('AeternaCore', coreStub({
                rateLimit = function(src, key, max, windowMs)
                    limited[#limited + 1] = { src = src, key = key, max = max, windowMs = windowMs }
                    return false
                end,
            }))
            local res = resource.load_resource(DIR, 'server')
            local _, _, clean = res.exports.notify(1, { title = 'Q', actions = { { id = 'yes', label = 'Yes' } } })
            natives.fire_net('aeterna_notify:sv:action', 1, { toastId = clean.toastId, action = 'yes' })
            assert.are.equal(0, #natives.emitted('local', 'aeterna_notify:action'))
            assert.are.equal(1, #limited)
            assert.are.equal(5, limited[1].max)
            assert.are.equal(1000, limited[1].windowMs)
        end)

        it('client: a press by key or by NUI fires the client-local event once with the calling resource as owner', function()
            natives.reset({ resource = 'aeterna_notify', side = 'client', invoker = 'my_job' })
            local commands, nuiCallbacks = {}, {}
            natives.spy('RegisterCommand', function(name, fn) commands[name] = fn end)
            natives.spy('RegisterNUICallback', function(name, fn) nuiCallbacks[name] = fn end)
            local nui = natives.spy('SendNUIMessage')
            natives.spy('LoadResourceFile', function() return nil end)
            natives.stub('AeternaCore', coreStub())
            local res = resource.load_resource(DIR, 'client')

            local toastId = res.exports.notify({
                title = 'Pick',
                actions = { { id = 'pin', label = 'Pin it' }, { id = 'skip', label = 'Ignore' } },
            })
            assert.is_string(toastId)
            local add = nuiOfType(nui, 'toast:add')
            assert.are.equal(toastId, add[#add].toastId)
            assert.are.equal(2, #add[#add].toast.actions)

            nuiCallbacks.toastAction({ toastId = toastId, action = 'nope' }, function() end)
            nuiCallbacks.toastAction({ toastId = 'unknown', action = 'pin' }, function() end)
            assert.are.equal(0, #natives.emitted('local', 'aeterna_notify:action'))

            assert.is_function(commands['+aeterna_notify_action2'])
            commands['+aeterna_notify_action2']()
            commands['+aeterna_notify_action2']()
            nuiCallbacks.toastAction({ toastId = toastId, action = 'pin' }, function() end)
            local evs = natives.emitted('local', 'aeterna_notify:action')
            assert.are.equal(1, #evs)
            assert.are.same({ owner = 'my_job', toastId = toastId, action = 'skip' }, evs[1].args[1])
            assert.are.equal(1, #nuiOfType(nui, 'toast:clear'))
        end)

        it('client: a server toast press goes to the server event instead', function()
            natives.reset({ resource = 'aeterna_notify', side = 'client' })
            local commands = {}
            natives.spy('RegisterCommand', function(name, fn) commands[name] = fn end)
            natives.spy('RegisterNUICallback')
            natives.spy('SendNUIMessage')
            natives.spy('LoadResourceFile', function() return nil end)
            natives.stub('AeternaCore', coreStub())
            resource.load_resource(DIR, 'client')

            natives.fire('aeterna_notify:cl:toast', {
                title = 'Accept?', toastId = 't5', owner = 'my_job', duration = 8000,
                actions = { { id = 'yes', label = 'Yes' } },
            })
            commands['+aeterna_notify_action1']()
            local evs = natives.emitted('server', 'aeterna_notify:sv:action')
            assert.are.equal(1, #evs)
            assert.are.same({ toastId = 't5', action = 'yes' }, evs[1].args[1])
            assert.are.equal(0, #natives.emitted('local', 'aeterna_notify:action'))
        end)
    end)

    describe('2. merge', function()
        local L
        before_each(function()
            natives.reset()
            L = loadLogic()
        end)

        local function ctx(now, owner)
            return { now = now, owner = owner or 'res_a', origin = 'client', soundAllowed = false }
        end

        it('merges the same key on screen into x2 and restarts the timer without a new toast', function()
            local q = L.createToastQueue({ max = 4, defaultDuration = 4000, merge = true })
            local ok1, _, r1 = q:push({ title = 'Saved', description = 'Slot 1' }, ctx(0))
            assert.is_true(ok1)
            assert.is_false(r1.merged)
            local ok2, _, r2 = q:push({ title = 'Saved', description = 'Slot 1', icon = 'check', duration = 9000 }, ctx(1500))
            assert.is_true(ok2)
            assert.is_true(r2.merged)
            assert.are.equal(1, q:count())
            assert.are.equal(2, r2.toast.count)
            assert.are.equal(r1.toast.id, r2.toast.id)
            assert.are.equal(5500, r2.toast.expiresAt)
            assert.are.equal('×2', L.formatCount(r2.toast.count))
        end)

        it('adds a new toast for a different description, owner, or after the first one left the screen', function()
            local q = L.createToastQueue({ max = 4, defaultDuration = 4000, merge = true })
            q:push({ title = 'Saved', description = 'Slot 1' }, ctx(0))
            local _, _, r = q:push({ title = 'Saved', description = 'Slot 2' }, ctx(10))
            assert.is_false(r.merged)
            _, _, r = q:push({ title = 'Saved', description = 'Slot 1' }, ctx(20, 'res_b'))
            assert.is_false(r.merged)
            assert.are.equal(3, q:count())
            _, _, r = q:push({ title = 'Saved', description = 'Slot 2' }, ctx(5000))
            assert.is_false(r.merged)
            assert.are.equal(1, q:count())
        end)

        it('never merges a toast with id, with actions, or with merge = false, or when Config.toast.merge is off', function()
            local q = L.createToastQueue({ max = 8, defaultDuration = 4000, merge = true })
            q:push({ title = 'Same' }, ctx(0))
            local _, _, r = q:push({ id = 'job', title = 'Same' }, ctx(1))
            assert.is_false(r.merged)
            _, _, r = q:push({ title = 'Same', actions = { { id = 'a', label = 'A' } } }, ctx(2))
            assert.is_false(r.merged)
            _, _, r = q:push({ title = 'Same', merge = false }, ctx(3))
            assert.is_false(r.merged)
            assert.are.equal(4, q:count())

            local off = L.createToastQueue({ max = 4, defaultDuration = 4000, merge = false })
            off:push({ title = 'Same' }, ctx(0))
            _, _, r = off:push({ title = 'Same' }, ctx(1))
            assert.is_false(r.merged)
            assert.are.equal(2, off:count())
        end)

        it('shows x99+ above 99 copies', function()
            local q = L.createToastQueue({ max = 4, defaultDuration = 4000, merge = true })
            local r
            for i = 1, 100 do
                _, _, r = q:push({ title = 'Spam' }, ctx(i))
            end
            assert.are.equal(100, r.toast.count)
            assert.are.equal('×99+', L.formatCount(100))
            assert.are.equal('×99', L.formatCount(99))
            assert.are.equal('', L.formatCount(1))
        end)
    end)

    describe('3. sound gate', function()
        local L
        before_each(function()
            natives.reset()
            L = loadLogic()
        end)

        it('plays only when owner, player and toast all allow it', function()
            assert.is_true(L.soundGate(true, true, true))
            assert.is_false(L.soundGate(false, true, true))
            assert.is_false(L.soundGate(true, false, true))
            assert.is_false(L.soundGate(true, true, false))
            assert.is_true(L.soundGate(true, true, nil))

            local q = L.createToastQueue({ max = 4, defaultDuration = 4000, merge = true })
            local _, _, r = q:push({ title = 'A' }, { now = 0, owner = 'x', soundAllowed = true })
            assert.is_true(r.sound)
            _, _, r = q:push({ title = 'B', sound = false }, { now = 0, owner = 'x', soundAllowed = true })
            assert.is_false(r.sound)
            _, _, r = q:push({ title = 'C' }, { now = 0, owner = 'x', soundAllowed = false })
            assert.is_false(r.sound)
        end)

        it('plays a burst of five merged copies once', function()
            local q = L.createToastQueue({ max = 4, defaultDuration = 4000, merge = true })
            local plays = 0
            for i = 0, 4 do
                local _, _, r = q:push({ title = 'Burst' }, { now = i * 150, owner = 'x', soundAllowed = true })
                if r.sound then plays = plays + 1 end
            end
            assert.are.equal(1, plays)
            local _, _, r = q:push({ title = 'Burst' }, { now = 1800, owner = 'x', soundAllowed = true })
            assert.is_true(r.sound)
        end)
    end)

    describe('4. countdown', function()
        local L
        before_each(function()
            natives.reset()
            L = loadLogic()
        end)

        it('refuses seconds 9 and 3601 and drops marks at or above seconds', function()
            assert.is_false((L.validateCountdownOpts({ title = 'Restart', seconds = 9 })))
            assert.is_false((L.validateCountdownOpts({ title = 'Restart', seconds = 3601 })))
            assert.is_true((L.validateCountdownOpts({ title = 'Restart', seconds = 10 })))
            local ok, _, clean = L.validateCountdownOpts({ title = 'Restart', seconds = 120, marks = { 600, 120, 60, 30, 10 } })
            assert.is_true(ok)
            assert.are.same({ 60, 30, 10 }, clean.marks)
            local _, _, def = L.validateCountdownOpts({ title = 'Restart', seconds = 400 }, { 600, 300, 60, 30, 10 })
            assert.are.same({ 300, 60, 30, 10 }, def.marks)
        end)

        it('returns busy for a second countdown, resends at marks, and ends once with cancelled = false', function()
            local sent, ended = {}, {}
            local cd = L.createCountdown({
                send = function(p) sent[#sent + 1] = p end,
                fire = function(p) ended[#ended + 1] = p end,
                marks = { 600, 300, 60, 30, 10 },
            })
            local id = cd:start({ title = 'Restart', seconds = 60, marks = { 30, 10 } }, 0)
            assert.is_string(id)
            local id2, err = cd:start({ title = 'Again', seconds = 60 }, 0)
            assert.is_nil(id2)
            assert.are.equal('busy', err)
            assert.are.equal(1, #sent)
            assert.are.equal(60000, sent[1].remainingMs)
            assert.are.equal(id, sent[1].countdownId)

            cd:tick(29000)
            assert.are.equal(1, #sent)
            cd:tick(30000)
            assert.are.equal(2, #sent)
            assert.are.equal(30000, sent[2].remainingMs)
            cd:tick(50500)
            assert.are.equal(3, #sent)
            assert.are.equal(9500, sent[3].remainingMs)
            cd:tick(60000)
            cd:tick(61000)
            assert.are.equal(1, #ended)
            assert.are.same({ countdownId = id, cancelled = false }, ended[1])
            assert.is_nil(cd:active())
        end)

        it('cancelCountdown hides it and fires the end event with cancelled = true', function()
            local sent, ended = {}, {}
            local cd = L.createCountdown({
                send = function(p) sent[#sent + 1] = p end,
                fire = function(p) ended[#ended + 1] = p end,
            })
            local id = cd:start({ title = 'Restart', seconds = 30 }, 0)
            assert.is_false(cd:cancel('c999'))
            assert.is_true(cd:cancel(id))
            assert.are.same({ countdownId = id, hide = true }, sent[#sent])
            cd:tick(40000)
            assert.are.equal(1, #ended)
            assert.are.same({ countdownId = id, cancelled = true }, ended[1])
            assert.is_string(cd:start({ title = 'Next', seconds = 30 }, 0))
        end)

        it('formats mm:ss', function()
            assert.are.equal('01:00', L.formatClock(60000))
            assert.are.equal('00:10', L.formatClock(9001))
            assert.are.equal('60:00', L.formatClock(3600000))
            assert.are.equal('00:00', L.formatClock(-5))
        end)

        it('server: export, end event and the ACE-checked command', function()
            natives.reset({ resource = 'aeterna_notify', side = 'server', players = { [1] = 'Alice', [2] = 'Bob' } })
            local commands = {}
            natives.spy('RegisterCommand', function(name, fn) commands[name] = fn end)
            natives.stub('AeternaCore', coreStub({
                can = function(src) return tonumber(src) == 0 or tonumber(src) == 2 end,
            }))
            local res = resource.load_resource(DIR, 'server')

            local id = res.exports.announceCountdown({ title = 'Restart', seconds = 10 })
            assert.is_string(id)
            local nilId, err = res.exports.announceCountdown({ title = 'Again', seconds = 10 })
            assert.is_nil(nilId)
            assert.are.equal('busy', err)
            local evs = natives.emitted('client', 'aeterna_notify:cl:countdown')
            assert.are.equal(1, #evs)
            assert.are.equal(-1, evs[1].target)
            natives.advance(11000)
            local ends = natives.emitted('local', 'aeterna_notify:countdownEnd')
            assert.are.equal(1, #ends)
            assert.are.same({ countdownId = id, cancelled = false }, ends[1].args[1])

            commands.aeterna_announce_countdown(1, { '5', 'Restart' }, 'aeterna_announce_countdown 5 Restart')
            assert.are.equal(1, #natives.emitted('client', 'aeterna_notify:cl:countdown'))
            assert.are.equal(Locales.en['notify.announce.denied'], natives.last_emitted('client', 'aeterna_notify:cl:toast').args[1].title)
            commands.aeterna_announce_countdown(2, { '61', 'Restart' }, 'aeterna_announce_countdown 61 Restart')
            assert.are.equal(Locales.en['notify.countdown.usage'], natives.last_emitted('client', 'aeterna_notify:cl:toast').args[1].title)
            commands.aeterna_announce_countdown(2, { '5', 'Server', 'restart' }, 'aeterna_announce_countdown 5 Server restart')
            evs = natives.emitted('client', 'aeterna_notify:cl:countdown')
            assert.are.equal(2, #evs)
            assert.are.equal(300000, evs[2].args[1].remainingMs)
            assert.are.equal('Server restart', evs[2].args[1].body)
            assert.are.equal('Bob', evs[2].args[1].by)
            assert.are.equal(Locales.en['notify.countdown.title'], evs[2].args[1].title)
            commands.aeterna_announce_countdown(0, { '1', 'Again' }, 'aeterna_announce_countdown 1 Again')
            assert.are.equal(2, #natives.emitted('client', 'aeterna_notify:cl:countdown'))

            assert.is_true(res.exports.cancelCountdown(evs[2].args[1].countdownId))
            ends = natives.emitted('local', 'aeterna_notify:countdownEnd')
            assert.are.equal(2, #ends)
            assert.is_true(ends[2].args[1].cancelled)
        end)
    end)

    describe('5. history', function()
        local L
        before_each(function()
            natives.reset()
            L = loadLogic()
        end)

        it('lists newest first, clamps limit to 1-50, and keeps nothing when max = 0', function()
            local h = L.createHistory(50)
            for i = 1, 60 do
                h:upsert({ id = 't' .. i, owner = 'x', kind = 'toast', type = 'info', title = 'N' .. i, count = 1, at = i })
            end
            assert.are.equal(50, h:count())
            local all = h:list()
            assert.are.equal(50, #all)
            assert.are.equal('t60', all[1].id)
            assert.are.equal('t11', all[50].id)
            assert.are.equal(1, #h:list(0))
            assert.are.equal(1, #h:list(-3))
            assert.are.equal(50, #h:list(500))
            assert.are.equal(3, #h:list(3))
            h:clear()
            assert.are.equal(0, h:count())

            local off = L.createHistory(0)
            assert.is_nil(off:upsert({ id = 't1', kind = 'toast', title = 'X', count = 1, at = 1 }))
            assert.are.equal(0, #off:list())
        end)

        it('client: a merge updates count instead of adding; history = false and the MOTD stay out', function()
            natives.reset({ resource = 'aeterna_notify', side = 'client', invoker = 'my_job' })
            natives.spy('RegisterCommand')
            local nuiCallbacks = {}
            natives.spy('RegisterNUICallback', function(name, fn) nuiCallbacks[name] = fn end)
            natives.spy('SendNUIMessage')
            natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            natives.spy('GetResourceState', function() return 'missing' end)
            natives.spy('LoadResourceFile', function(_, path)
                if path == 'config/motd.json' then
                    return json.encode({ version = 'v1', title = 'Welcome', lines = { 'Hello' } })
                end
                return nil
            end)
            natives.stub('AeternaCore', coreStub({
                requestFocus = function() return 'tok' end,
                releaseFocus = function() return true end,
            }))
            local res = resource.load_resource(DIR, 'client')
            local api = res.exports

            natives.fire('playerSpawned')
            api.notify({ title = 'Hidden', history = false })
            assert.are.equal(0, #api.history())

            api.notify({ title = 'Saved' })
            natives.advance(500)
            api.notify({ title = 'Saved' })
            local list = api.history()
            assert.are.equal(1, #list)
            assert.are.equal(2, list[1].count)
            assert.are.equal('toast', list[1].kind)
            assert.are.equal('my_job', list[1].owner)
            assert.are.equal(1700000000, list[1].at)
            assert.is_nil(list[1].actions)
            assert.are.equal(2, #natives.emitted('local', 'aeterna_notify:added'))

            natives.fire('aeterna_notify:cl:announce', { id = 'a1', title = 'News', body = 'Body', duration = 5000 })
            list = api.history()
            assert.are.equal(2, #list)
            assert.are.equal('announce', list[1].kind)
            assert.are.equal('Body', list[1].description)

            api.clearHistory()
            assert.are.equal(0, #api.history())
        end)
    end)

    describe('6. settings', function()
        local L
        before_each(function()
            natives.reset()
            L = loadLogic()
        end)

        it('round-trips the sound setting and uses Config.sound.playerDefault with no saved value', function()
            local store = nil
            local s = L.createSettings({
                get = function() return store end,
                set = function(v) store = v end,
                playerDefault = true,
            })
            assert.is_true(s:sound())
            assert.is_false(s:toggle())
            assert.are.same({ sound = false }, store)
            assert.is_false(s:sound())
            local s2 = L.createSettings({ get = function() return store end, set = function() end, playerDefault = true })
            assert.is_false(s2:sound())
            local s3 = L.createSettings({ get = function() return nil end, set = function() end, playerDefault = false })
            assert.is_false(s3:sound())
            local s4 = L.createSettings({ get = function() return { sound = 'yes' } end, set = function() end, playerDefault = true })
            assert.is_true(s4:sound())
        end)

        it('client: aeterna_notify_sound writes KVP aeterna_notify:settings:v1 and shows the new state', function()
            natives.reset({ resource = 'aeterna_notify', side = 'client' })
            local commands = {}
            natives.spy('RegisterCommand', function(name, fn) commands[name] = fn end)
            natives.spy('RegisterNUICallback')
            local nui = natives.spy('SendNUIMessage')
            natives.spy('LoadResourceFile', function() return nil end)
            natives.stub('AeternaCore', coreStub())
            local prevEnabled = Config and Config.sound and Config.sound.enabled
            resource.load_resource(DIR, 'client')
            Config.sound.enabled = true
            Config.sound.playerDefault = false

            commands.aeterna_notify_sound(0, {}, 'aeterna_notify_sound')
            assert.are.equal('{"sound":true}', natives.get_kvp('aeterna_notify:settings:v1'))
            local adds = nuiOfType(nui, 'toast:add')
            assert.are.equal(Locales.en['notify.sound.on'], adds[#adds].toast.title)
            local st = nuiOfType(nui, 'settings')
            assert.is_true(st[#st].sound)

            commands.aeterna_notify_sound(0, {}, 'aeterna_notify_sound')
            assert.are.equal('{"sound":false}', natives.get_kvp('aeterna_notify:settings:v1'))

            Config.sound.enabled = false
            commands.aeterna_notify_sound(0, {}, 'aeterna_notify_sound')
            assert.are.equal('{"sound":false}', natives.get_kvp('aeterna_notify:settings:v1'))
            adds = nuiOfType(nui, 'toast:add')
            assert.are.equal(Locales.en['notify.sound.disabled'], adds[#adds].toast.title)
            Config.sound.enabled = prevEnabled or false
        end)
    end)

    describe('7. MOTD while paused', function()
        it('ignores MOTD input while paused by a focus overlay and closes on a real focus loss', function()
            natives.reset({ resource = 'aeterna_notify', side = 'client' })
            natives.spy('RegisterCommand')
            local nuiCallbacks = {}
            natives.spy('RegisterNUICallback', function(name, fn) nuiCallbacks[name] = fn end)
            local nui = natives.spy('SendNUIMessage')
            natives.spy('GetResourceState', function() return 'missing' end)
            natives.spy('LoadResourceFile', function(_, path)
                if path == 'config/motd.json' then
                    return json.encode({ version = 'v2', title = 'Welcome', lines = { 'Hello' } })
                end
                return nil
            end)
            natives.stub('AeternaCore', coreStub({
                requestFocus = function() return 'tok' end,
                releaseFocus = function() return true end,
            }))
            local res = resource.load_resource(DIR, 'client')
            assert.is_true(res.exports.showMotd())

            natives.fire('aeterna_core:focusPaused', 'aeterna_notify', 'tok')
            nuiCallbacks.motdClose({ dismiss = true }, function() end)
            nuiCallbacks.escape({}, function() end)
            assert.are.equal(0, #nuiOfType(nui, 'motd:hide'))
            assert.is_nil(natives.get_kvp('aeterna_notify:motd_seen:v1'))

            natives.fire('aeterna_core:focusResumed', 'aeterna_notify', 'tok')
            natives.fire('aeterna_core:focusLost', 'aeterna_notify', 'tok', 'preempted')
            assert.are.equal(1, #nuiOfType(nui, 'motd:hide'))
            assert.is_nil(natives.get_kvp('aeterna_notify:motd_seen:v1'))
        end)
    end)

    describe('8. manifest and locales', function()
        it('is version 0.2.0 and every 0.2 locale key exists in th and en', function()
            local f = assert(io.open(DIR .. '/fxmanifest.lua', 'rb'))
            local manifest = f:read('*a')
            f:close()
            assert.is_truthy(manifest:match("version '0%.2%.0'"))
            natives.reset({ resource = 'aeterna_notify', side = 'client' })
            Locales = nil
            assert(loadfile(DIR .. '/locales/en.lua'))()
            assert(loadfile(DIR .. '/locales/th.lua'))()
            local keys = {
                'notify.action.unbound', 'notify.sound.on', 'notify.sound.off', 'notify.sound.disabled',
                'notify.countdown.title', 'notify.countdown.usage', 'notify.countdown.busy',
                'notify.key.action1', 'notify.key.action2',
            }
            for i = 1, #keys do
                assert.is_string(Locales.en[keys[i]], keys[i])
                assert.is_string(Locales.th[keys[i]], keys[i])
            end
        end)
    end)
end)
