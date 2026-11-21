-- selftest_spec.lua -- aeterna_phonekit "Self-tests (0.2)": the rows, the pass rule of each test
-- (shared/logic/selftest.lua) and the server and client handlers under the harness.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load(rel)
    return assert(loadfile(DIR .. '/shared/logic/' .. rel))()
end

local OWNER = 'aeterna_phonekit'
local MODELS = { 'keypad', 'burner', 'qwerty', 'slab', 'fold', 'pro', 'book', 'pad' }

describe('aeterna_phonekit self-tests', function()
    local P, L, D, B
    before_each(function()
        natives.reset()
        L = load('phone.lua')
        D = load('device.lua')
        B = load('battery.lua')
        P = load('selftest.lua')
    end)

    describe('rows', function()
        local function rows()
            return P.rows(OWNER, function(k, vars)
                return '<' .. k .. (vars and vars.model and (':' .. vars.model) or '') .. '>'
            end, function(id) return id:upper() end)
        end

        it('are the spec table in order', function()
            local names = {}
            for i, r in ipairs(rows()) do names[i] = r.name:sub(#OWNER + 2) end
            local want = { 'rules_loaded', 'models_have_apps', 'battery_drain_tick', 'battery_zero_closes_all',
                'battery_kvp_roundtrip', 'stale_pulse_is_off', 'gate_items_silence_denies', 'open_close_prop',
                'fold_keeps_screen', 'clamp_on_unfold', 'exit_contract' }
            for _, m in ipairs(MODELS) do want[#want + 1] = 'eye_model_' .. m end
            for _, n in ipairs({ 'eye_book_two_pane', 'eye_fold_cover', 'eye_lock', 'eye_control_centre', 'eye_battery_dead',
                'ring_cover', 'contacts_hooks' }) do
                want[#want + 1] = n
            end
            assert.are.same(want, names)
            assert.is_nil(P.NOT_BUILT)
        end)

        it('carry kind, side, players, destructive and expect as the spec says', function()
            local by = {}
            for _, r in ipairs(rows()) do by[r.name:sub(#OWNER + 2)] = r.meta end
            local plain = { kind = 'headless', players = 1, destructive = false }
            assert.are.same(plain, by.rules_loaded)
            assert.are.same(plain, by.models_have_apps)
            assert.are.same(plain, by.battery_drain_tick)
            assert.are.same(plain, by.stale_pulse_is_off)
            assert.are.same({ kind = 'mock', players = 1, destructive = true }, by.battery_zero_closes_all)
            assert.are.same({ kind = 'mock', players = 1, destructive = true }, by.battery_kvp_roundtrip)
            assert.are.same({ kind = 'mock', players = 1, destructive = false }, by.gate_items_silence_denies)
            for _, n in ipairs({ 'open_close_prop', 'fold_keeps_screen', 'clamp_on_unfold', 'exit_contract' }) do
                assert.are.same({ kind = 'ped', players = 1, destructive = false, timeout = 15000 }, by[n])
            end
            assert.are.same({ kind = 'eye', players = 1, destructive = false, timeout = 15000,
                expect = '<phonekit.selftest.expect.model:BOOK>' }, by.eye_model_book)
            assert.are.same({ kind = 'eye', players = 1, destructive = false, timeout = 15000,
                expect = '<phonekit.selftest.expect.ring_cover>' }, by.ring_cover)
            assert.are.same({ kind = 'eye', players = 1, destructive = true, timeout = 15000,
                expect = '<phonekit.selftest.expect.battery_dead>' }, by.eye_battery_dead)
            assert.are.same({ kind = 'mock', side = 'client', players = 1, destructive = false }, by.contacts_hooks)
            for name, meta in pairs(by) do
                if meta.kind == 'eye' then assert.is_string(meta.expect, name) end
                assert.is_nil(meta.ask, name)
                -- rows that open the phone (server gate, focus, prop) get 15 s; the rest keep core's default
                if meta.kind == 'ped' or meta.kind == 'eye' then
                    assert.are.equal(15000, meta.timeout, name)
                else
                    assert.is_nil(meta.timeout, name)
                end
                assert.is_nil(meta.skipWhen, name)
            end
        end)

        it('have every expect line in Thai and English within 240 characters', function()
            assert(loadfile(DIR .. '/locales/en.lua'))()
            assert(loadfile(DIR .. '/locales/th.lua'))()
            for _, lang in ipairs({ 'en', 'th' }) do
                for _, k in ipairs({ 'model', 'book_two_pane', 'fold_cover', 'lock', 'control_centre', 'battery_dead', 'ring_cover' }) do
                    local s = Locales[lang]['phonekit.selftest.expect.' .. k]
                    assert.is_string(s, lang .. ' ' .. k)
                    assert.is_true(utf8.len(s) <= 240 - 24, lang .. ' ' .. k)
                end
                assert.is_string(Locales[lang]['phonekit.selftest.ring.title'])
                assert.is_string(Locales[lang]['phonekit.selftest.ring.body'])
            end
        end)
    end)

    describe('skip conditions', function()
        local env
        before_each(function()
            env = { battery = true, mode = 'single', lockScreen = true, cover = true, model = 'slab', ped = true }
        end)

        it('follow the spec table', function()
            assert.is_nil(P.skipReason('battery_drain_tick', env))
            env.battery = false
            for _, n in ipairs({ 'battery_drain_tick', 'battery_zero_closes_all', 'stale_pulse_is_off', 'eye_battery_dead' }) do
                assert.are.equal('Config.battery is false', P.skipReason(n, env))
            end
            assert.is_nil(P.skipReason('battery_kvp_roundtrip', env))
            assert.are.equal("Config.devices is 'single'", P.skipReason('gate_items_silence_denies', env))
            env.mode = 'items'
            assert.are.equal("Config.devices is 'items'", P.skipReason('battery_kvp_roundtrip', env))
            assert.is_nil(P.skipReason('gate_items_silence_denies', env))
            assert.is_nil(P.skipReason('open_close_prop', env))
            env.ped = false
            assert.are.equal('presser not spawned', P.skipReason('open_close_prop', env))
            assert.are.equal('held model does not fold', P.skipReason('fold_keeps_screen', env))
            assert.are.equal('held model is not book', P.skipReason('clamp_on_unfold', env))
            assert.are.equal('held model is not fold', P.skipReason('ring_cover', env))
            env.lockScreen = false
            assert.are.equal('Config.lockScreen is false', P.skipReason('eye_lock', env))
            for _, n in ipairs({ 'rules_loaded', 'models_have_apps', 'exit_contract', 'eye_model_pad', 'eye_book_two_pane',
                'eye_fold_cover', 'eye_control_centre', 'contacts_hooks' }) do
                assert.is_nil(P.skipReason(n, env), n)
            end
        end)

        it('fold and book fold; a fold with Config.cover = false does not', function()
            env.model = 'book'
            assert.is_nil(P.skipReason('fold_keeps_screen', env))
            assert.is_nil(P.skipReason('clamp_on_unfold', env))
            env.model = 'fold'
            assert.is_nil(P.skipReason('eye_fold_cover', env))
            assert.is_nil(P.skipReason('fold_keeps_screen', env))
            assert.is_nil(P.skipReason('ring_cover', env))
            env.cover = false
            assert.are.equal('held model does not fold', P.skipReason('fold_keeps_screen', env))
            assert.are.equal('Config.cover is false', P.skipReason('ring_cover', env))
            assert.are.equal('cover is off', P.skipReason('eye_fold_cover', env))
        end)
    end)

    describe('headless checks', function()
        it('rules_loaded passes for the shipped config and names what is wrong', function()
            local cfg = B.validateConfig({})
            assert.are.same({ true, 'mode single · model slab · battery on · 8 models' },
                { P.rulesLoaded({ mode = 'single', singleModel = 'slab', models = D.MODELS, batteryOn = true,
                    battery = cfg }) })
            assert.is_true((P.rulesLoaded({ mode = 'items', singleModel = 'pad', models = D.MODELS, batteryOn = false,
                battery = false })))
            assert.are.same({ false, 'mode: unknown' }, { P.rulesLoaded({ mode = 'x', singleModel = 'slab',
                models = D.MODELS, batteryOn = true, battery = cfg }) })
            assert.are.same({ false, 'singleModel: not a model id' }, { P.rulesLoaded({ mode = 'single',
                singleModel = 'brick', models = D.MODELS, batteryOn = true, battery = cfg }) })
            assert.are.same({ false, 'battery: config did not load' }, { P.rulesLoaded({ mode = 'single',
                singleModel = 'slab', models = D.MODELS, batteryOn = true, battery = false }) })
            assert.are.same({ false, 'models: 1 of 8' }, { P.rulesLoaded({ mode = 'single', singleModel = 'slab',
                models = { slab = D.MODELS.slab }, batteryOn = true, battery = cfg }) })
        end)

        it('models_have_apps lists the built-in apps of every model', function()
            local resolve = function(id) return D.resolveModel(id, { burner = { apps = '*,-contacts' } }, {}) end
            local ok, detail = P.modelsHaveApps(D, resolve)
            assert.is_true(ok)
            assert.are.equal('keypad 4 · burner 3 · qwerty 4 · slab 4 · fold 4 · pro 4 · book 4 · pad 4', detail)
            local noLabel = function(id) local m = resolve(id) if id == 'pad' then m.label = '' end return m end
            assert.are.same({ false, 'pad: no label' }, { P.modelsHaveApps(D, noLabel) })
        end)

        it('battery_drain_tick: one minute with the screen on drains standby + screen on a slab', function()
            local cfg = B.validateConfig({})
            assert.are.same({ true, '100 → 98.75 % in 60 s (screen on, slab)' }, { P.drainTick(B, cfg) })
            local wrong = setmetatable({ advance = function(st) st.pct = 50 return {} end }, { __index = B })
            local ok, detail = P.drainTick(wrong, cfg)
            assert.is_false(ok)
            assert.are.equal('expected 98.75 %, got 50 %', detail)
        end)

        it('stale_pulse_is_off: a stale "on" pulse drains like the screen off', function()
            local cfg = B.validateConfig({})
            assert.are.same({ true, 'stale pulse drained 0.25 %/min, as off' }, { P.stalePulse(B, cfg) })
            -- advance reads B.isPulseStale through the module table: a pulse that never goes stale fails the row
            local real = B.isPulseStale
            B.isPulseStale = function() return false end
            local ok = P.stalePulse(B, cfg)
            B.isPulseStale = real
            assert.is_false(ok)
        end)

        it('gate_items_silence_denies: the live items options make silence a denial with nodevice', function()
            assert.are.same({ silenceDenies = true, silenceReason = 'phonekit.refused.nodevice' },
                D.gateCheckOptions('items'))
            assert.is_nil(D.gateCheckOptions('single'))
            assert.are.same({ true, 'silence denied with phonekit.refused.nodevice' },
                { P.silenceDenies(L, D.gateCheckOptions('items')) })
            -- the single-mode options (none): silence with no listener allows the phone
            assert.are.same({ false, 'silence allowed the phone' }, { P.silenceDenies(L, D.gateCheckOptions('single')) })
            local never = { createOpeningCheckManager = function()
                return { createCheck = function() return 'c' end, handleTimeout = function() end }
            end }
            assert.are.same({ false, 'the check never resolved' }, { P.silenceDenies(never, D.gateCheckOptions('items')) })
        end)
    end)

    describe('mock and client checks', function()
        it('battery_zero_closes_all needs every surface closed and power off', function()
            local good = { dead = true, open = false, screens = false, powerOff = true }
            assert.are.same({ true, 'at 0 %: power off, no device, no screen, phone closed' }, { P.zeroClosed(good) })
            good.open = true
            assert.are.same({ false, 'phone still open' }, { P.zeroClosed(good) })
            good.open, good.powerOff = false, false
            assert.are.same({ false, 'no power off sent' }, { P.zeroClosed(good) })
        end)

        it('battery_kvp_roundtrip compares battery and fold', function()
            assert.is_true((P.kvpRoundtrip({ battery = 42.5, fold = 'open' }, { battery = 42.5, fold = 'open' })))
            assert.are.same({ false, 'read back battery 40' },
                { P.kvpRoundtrip({ battery = 42.5 }, { battery = 40 }) })
            assert.are.same({ false, 'nothing read back' }, { P.kvpRoundtrip({ battery = 42.5 }, nil) })
        end)

        it('open_close_prop follows Config.animation', function()
            assert.are.same({ true, 'prop attached while open, gone after close' },
                { P.propResult({ opened = true, animation = true, prop = true, attached = true, gone = true }) })
            assert.are.same({ false, 'no prop while open' },
                { P.propResult({ opened = true, animation = true, prop = false, gone = true }) })
            assert.are.same({ false, 'prop is not attached to the ped' },
                { P.propResult({ opened = true, animation = true, prop = true, attached = false, gone = true }) })
            assert.are.same({ false, 'prop left after close' },
                { P.propResult({ opened = true, animation = true, prop = true, attached = true, gone = false }) })
            assert.are.same({ true, 'Config.animation is off: no prop' },
                { P.propResult({ opened = true, animation = false, prop = false, gone = true }) })
            assert.are.same({ false, 'phone did not open: phonekit.refused.nodevice' },
                { P.propResult({ opened = false, reason = 'phonekit.refused.nodevice' }) })
        end)

        it('fold_keeps_screen wants the same screen key on top before and after', function()
            assert.are.same({ true, 'selftest_a on top after fold and unfold' },
                { P.foldKept({ opened = true, expected = 'selftest_a', before = 'selftest_a', after = 'selftest_a' }) })
            assert.are.same({ false, 'step 2: top is home' },
                { P.foldKept({ opened = true, expected = 'selftest_a', before = 'selftest_a', after = nil }) })
            assert.are.same({ false, 'step 1: top is home' },
                { P.foldKept({ opened = true, expected = 'selftest_a', before = nil }) })
        end)

        it('clamp_on_unfold wants the open frame inside the viewport', function()
            local r = { opened = true, fold = 'open', rect = { x = 10, y = 20, w = 700, h = 640 }, vw = 1280, vh = 720 }
            assert.are.same({ true, 'open frame 700x640 inside 1280x720' }, { P.clampInside(r) })
            r.rect.x = 600
            assert.are.same({ false, 'open frame 700x640 at 600,20 leaves 1280x720' }, { P.clampInside(r) })
            r.fold = 'closed'
            assert.are.same({ false, 'frame did not unfold' }, { P.clampInside(r) })
        end)

        it('exit_contract: ESC closes, a reopen inside 300 ms is ignored, the bound key closes', function()
            assert.are.same({ true, 'ESC closes; reopen within 300 ms ignored; F2 closes' },
                { P.exitResult({ opened = true, escClosed = true, reopenIgnored = true, keyCode = 'F2', keyClosed = true }) })
            assert.are.same({ true, 'ESC closes; reopen within 300 ms ignored; no key bound' },
                { P.exitResult({ opened = true, escClosed = true, reopenIgnored = true }) })
            assert.are.same({ false, 'step 1: ESC did not close' },
                { P.exitResult({ opened = true, escClosed = false }) })
            assert.are.same({ false, 'step 2: reopen within 300 ms was not ignored' },
                { P.exitResult({ opened = true, escClosed = true, reopenIgnored = false }) })
            assert.are.same({ false, 'step 3: KeyM did not close' },
                { P.exitResult({ opened = true, escClosed = true, reopenIgnored = true, keyCode = 'KeyM', keyClosed = false }) })
        end)

        it('contacts_hooks: one add, one change event, the list put back', function()
            local good = { added = true, found = true, changes = 1, restored = true }
            assert.are.same({ true, 'addContact added, contactsChanged once, list restored' }, { P.contactsResult(good) })
            assert.are.same({ false, 'contactsChanged fired 2 times' },
                { P.contactsResult({ added = true, found = true, changes = 2, restored = true }) })
            assert.are.same({ false, 'addContact refused: phonekit.contacts.full' },
                { P.contactsResult({ added = false, reason = 'phonekit.contacts.full', restored = true }) })
            assert.are.same({ false, 'getContacts does not list the new contact' },
                { P.contactsResult({ added = true, found = false, changes = 1, restored = true }) })
        end)
    end)
end)

-- JSON for the flat KVP values phonekit stores ({ battery, fold }); CI's busted has no JSON library.
local flatJson = {
    encode = function(t)
        if type(t) ~= 'table' then return string.format('%q', tostring(t)) end
        local keys, parts = {}, {}
        for k in pairs(t) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local v = t[k]
            local enc = type(v) == 'string' and ('"' .. v .. '"') or (math.type(v) == 'integer' and ('%d'):format(v))
                or (type(v) == 'number' and ('%.14g'):format(v)) or tostring(v)
            parts[#parts + 1] = '"' .. k .. '":' .. enc
        end
        return '{' .. table.concat(parts, ',') .. '}'
    end,
    decode = function(s)
        if type(s) ~= 'string' or s:sub(1, 1) ~= '{' then error('not an object') end
        local t = {}
        for k, v in s:gmatch('"([%w_]+)":([^,}]+)') do
            if v:sub(1, 1) == '"' then t[k] = v:sub(2, -2)
            elseif v == 'true' or v == 'false' then t[k] = v == 'true'
            elseif v ~= 'null' then t[k] = math.tointeger(tonumber(v)) or tonumber(v) end
        end
        return t
    end,
}

describe('aeterna_phonekit self-tests under the harness', function()
    local added, reports
    local warns, guardCalls, mayWriteAnswer, failReport = {}, {}, true, false

    local function stubCore(extra)
        local core = {
            log = { debug = function() end, info = function() end, error = function() end,
                warn = function(msg, fields) warns[#warns + 1] = { msg = msg, fields = fields } end },
            selftest = { mayWrite = function(runId, name)
                guardCalls[#guardCalls + 1] = { runId, name }
                return mayWriteAnswer
            end },
            t = function(k) return k end,
            lang = function() return 'en' end,
            can = function() return true end,
            rateLimit = function() return true end,
        }
        for k, v in pairs(extra or {}) do core[k] = v end
        natives.stub('AeternaCore', core)
    end

    local function bootServer(config)
        natives.reset({ resource = OWNER, side = 'server', players = { [1] = 'One' }, json = flatJson })
        added, reports, warns, guardCalls, mayWriteAnswer, failReport = {}, {}, {}, {}, true, false
        stubCore()
        natives.stub('GetPlayerIdentifierByType', function() return 'license:abc' end)
        natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
        natives.stub_export('aeterna_notify', 'notify', function() return true end)
        natives.stub_export('aeterna_core', 'addSelftest', function(name, meta)
            added[#added + 1] = { name = name, meta = meta }
            return name
        end)
        natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail, extra)
            if failReport then error('core is gone') end
            reports[#reports + 1] = { runId = runId, name = name, ok = ok, detail = detail, extra = extra }
            return true
        end)
        local opts
        if config then
            natives.stub('Config', config)
            opts = { skip = { ['config.lua'] = true } }
        end
        return resource.load_resource(DIR, 'server', opts).exports
    end

    local function run(name, ctx)
        natives.fire('aeterna_core:selftest', 'r1-abcd', OWNER .. '.' .. name, ctx or { kind = 'headless', side = 'server' })
        return reports[#reports]
    end

    describe('server', function()
        it('registers 26 rows on start', function()
            bootServer()
            assert.are.equal(26, #added)
            assert.are.equal('aeterna_phonekit.rules_loaded', added[1].name)
            assert.are.equal('aeterna_phonekit.contacts_hooks', added[26].name)
        end)

        it('reports the headless rows and skips the items gate in single mode', function()
            bootServer()
            for _, n in ipairs({ 'rules_loaded', 'models_have_apps', 'battery_drain_tick', 'stale_pulse_is_off' }) do
                local r = run(n)
                assert.are.equal(OWNER .. '.' .. n, r.name)
                assert.is_true(r.ok, n .. ': ' .. tostring(r.detail))
            end
            local r = run('gate_items_silence_denies', { kind = 'mock', side = 'server' })
            assert.are.same({ 'skip', "Config.devices is 'single'" }, { r.ok, r.detail })
        end)

        it('battery_zero_closes_all saves 0 for the presser, closes everything, then restores the value', function()
            local api = bootServer()
            natives.fire_net('aeterna_phonekit:sv:battery', 1)
            assert.is_true(api.setBattery(1, 64))
            natives.fire_net('aeterna_phonekit:sv:open', 1)
            local zeroSaved = false
            local realSet = SetResourceKvp
            natives.stub('SetResourceKvp', function(k, v)
                if v:find('"battery":0', 1, true) then zeroSaved = true end
                realSet(k, v)
            end)
            local r = run('battery_zero_closes_all', { kind = 'mock', side = 'server', a = 1, destructive = true })
            assert.are.equal('mock', r.ok, r.detail)
            assert.is_true(r.extra.restored)
            assert.is_true(r.extra.wrote)
            assert.is_true(zeroSaved)
            assert.are.equal(64, api.battery(1))
            assert.is_true(natives.last_emitted('client', 'aeterna_phonekit:cl:power').args[1].on)
            assert.is_truthy(natives.get_kvp('aeterna_phonekit:device:v1:lic:license:abc'):find('"battery":64', 1, true))
        end)

        it('battery_zero_closes_all skips with no presser and on a phone that is already dead', function()
            local api = bootServer()
            assert.are.same({ 'skip', 'needs a presser' },
                { run('battery_zero_closes_all', { kind = 'mock', side = 'server' }).ok, reports[#reports].detail })
            natives.fire_net('aeterna_phonekit:sv:battery', 1)
            api.setBattery(1, 0)
            local r = run('battery_zero_closes_all', { kind = 'mock', side = 'server', a = 1 })
            assert.are.same({ 'skip', 'presser phone is already at 0 %' }, { r.ok, r.detail })
        end)

        it('battery_kvp_roundtrip writes the presser KVP and puts the old value back', function()
            bootServer()
            natives.fire_net('aeterna_phonekit:sv:battery', 1)
            natives.set_kvp('aeterna_phonekit:device:v1:lic:license:abc', '{"battery":77,"fold":null}')
            local before = natives.get_kvp('aeterna_phonekit:device:v1:lic:license:abc')
            local r = run('battery_kvp_roundtrip', { kind = 'mock', side = 'server', a = 1, destructive = true })
            assert.are.equal('mock', r.ok, r.detail)
            assert.is_true(r.extra.restored)
            assert.are.equal(before, natives.get_kvp('aeterna_phonekit:device:v1:lic:license:abc'))
        end)

        it('items mode: the KVP roundtrip skips and silence on the gate is a denial', function()
            bootServer({ devices = 'items', models = {}, battery = {}, apps = {} })
            local r = run('battery_kvp_roundtrip', { kind = 'mock', side = 'server', a = 1 })
            assert.are.same({ 'skip', "Config.devices is 'items'" }, { r.ok, r.detail })
            r = run('gate_items_silence_denies', { kind = 'mock', side = 'server' })
            assert.are.equal('mock', r.ok, r.detail)
            assert.is_true(r.extra.restored)
        end)

        it('battery off: battery rows skip with the reason', function()
            bootServer({ battery = false, models = {}, apps = {} })
            assert.are.same({ 'skip', 'Config.battery is false' },
                { run('battery_drain_tick').ok, reports[#reports].detail })
        end)

        it('destructive rows fail closed when the write guard says no', function()
            local api = bootServer()
            natives.fire_net('aeterna_phonekit:sv:battery', 1)
            api.setBattery(1, 64)
            mayWriteAnswer = false
            local r = run('battery_zero_closes_all', { kind = 'mock', side = 'server', a = 1, destructive = true })
            assert.are.same({ false, 'write guard refused' }, { r.ok, r.detail })
            assert.are.equal(64, api.battery(1))
            assert.are.same({ { 'r1-abcd', 'aeterna_phonekit.battery_zero_closes_all' } }, guardCalls)
            r = run('battery_kvp_roundtrip', { kind = 'mock', side = 'server', a = 1, destructive = true })
            assert.are.same({ false, 'write guard refused' }, { r.ok, r.detail })
        end)

        it('no write guard in AeternaCore means no write', function()
            local api = bootServer()
            AeternaCore.selftest = nil
            natives.fire_net('aeterna_phonekit:sv:battery', 1)
            api.setBattery(1, 64)
            local r = run('battery_zero_closes_all', { kind = 'mock', side = 'server', a = 1, destructive = true })
            assert.are.same({ false, 'write guard refused' }, { r.ok, r.detail })
            assert.are.equal(64, api.battery(1))
        end)

        it('battery_kvp_roundtrip deletes the key again when it was absent before', function()
            bootServer()
            natives.fire_net('aeterna_phonekit:sv:battery', 1)
            assert.is_nil(natives.get_kvp('aeterna_phonekit:device:v1:lic:license:abc'))
            local r = run('battery_kvp_roundtrip', { kind = 'mock', side = 'server', a = 1, destructive = true })
            assert.are.equal('mock', r.ok, r.detail)
            assert.is_true(r.extra.restored)
            assert.is_nil(natives.get_kvp('aeterna_phonekit:device:v1:lic:license:abc'))
        end)

        it('a failed reportSelftest is logged at warn', function()
            bootServer()
            failReport = true
            run('rules_loaded')
            assert.are.equal('reportSelftest failed', warns[#warns].msg)
        end)

        it('eye_battery_dead: selftestStarted saves 0 for the presser, selftestEnd puts the value back', function()
            local api = bootServer()
            natives.fire_net('aeterna_phonekit:sv:battery', 1)
            api.setBattery(1, 64)
            local ctx = { kind = 'eye', side = 'client', a = 1, destructive = true }
            natives.fire('aeterna_core:selftestStarted', 'r1-abcd', OWNER .. '.eye_battery_dead', ctx)
            assert.are.equal(0, api.battery(1))
            assert.is_false(natives.last_emitted('client', 'aeterna_phonekit:cl:power').args[1].on)
            assert.is_truthy(natives.get_kvp('aeterna_phonekit:device:v1:lic:license:abc'):find('"battery":0', 1, true))
            assert.are.same({ { 'r1-abcd', 'aeterna_phonekit.eye_battery_dead' } }, guardCalls)
            assert.are.equal(0, #reports) -- the client reports; the server only prepares
            natives.fire('aeterna_core:selftestEnd', 'r1-abcd', OWNER .. '.eye_battery_dead')
            assert.are.equal(64, api.battery(1))
            assert.is_true(natives.last_emitted('client', 'aeterna_phonekit:cl:power').args[1].on)
            assert.is_truthy(natives.get_kvp('aeterna_phonekit:device:v1:lic:license:abc'):find('"battery":64', 1, true))
            -- a second end changes nothing
            api.setBattery(1, 50)
            natives.fire('aeterna_core:selftestEnd', 'r1-abcd', OWNER .. '.eye_battery_dead')
            assert.are.equal(50, api.battery(1))
        end)

        it('eye_battery_dead: no write without the guard, and nothing for other tests or other invokers', function()
            local api = bootServer()
            natives.fire_net('aeterna_phonekit:sv:battery', 1)
            api.setBattery(1, 64)
            local ctx = { kind = 'eye', side = 'client', a = 1, destructive = true }
            mayWriteAnswer = false
            natives.fire('aeterna_core:selftestStarted', 'r1-abcd', OWNER .. '.eye_battery_dead', ctx)
            assert.are.equal(64, api.battery(1))
            mayWriteAnswer = true
            natives.fire('aeterna_core:selftestStarted', 'r1-abcd', OWNER .. '.eye_lock', ctx)
            natives.stub('GetInvokingResource', function() return 'other' end)
            natives.fire('aeterna_core:selftestStarted', 'r1-abcd', OWNER .. '.eye_battery_dead', ctx)
            assert.are.equal(64, api.battery(1))
        end)

        it('ignores tests of other resources and events not fired by aeterna_core', function()
            bootServer()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_core.core', {})
            natives.stub('GetInvokingResource', function() return 'other' end)
            run('rules_loaded')
            assert.are.equal(0, #reports)
        end)
    end)

    describe('client', function()
        local kvp, nui
        local failContactsSave = false

        local toasts

        local function bootClient(config)
            natives.reset({ resource = OWNER, side = 'client', json = flatJson })
            reports, kvp, nui, warns, toasts, failReport = {}, {}, {}, {}, {}, false
            natives.spy('SendNUIMessage', function(msg) nui[#nui + 1] = msg end)
            natives.spy('RegisterNUICallback')
            natives.spy('RegisterKeyMapping')
            natives.spy('RegisterCommand')
            natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
            stubCore({
                kvp = {
                    get = function(name, _, default) if kvp[name] == nil then return default end return kvp[name] end,
                    set = function(name, _, value)
                        if name == 'contacts' and type(value) == 'table' and failContactsSave then
                            for _, c in ipairs(value) do
                                if c.name == 'Self-test' then error('disk full') end
                            end
                        end
                        kvp[name] = value
                    end,
                },
                key = function() end,
                requestFocus = function() return 'tok' end,
                releaseFocus = function() return true end,
            })
            natives.stub_export('aeterna_core', 'themeHref', function() return nil end)
            natives.stub_export('aeterna_notify', 'history', function() return {} end)
            natives.stub_export('aeterna_notify', 'notify', function(opts) toasts[#toasts + 1] = opts.title end)
            natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail, extra)
                if failReport then error('core is gone') end
                reports[#reports + 1] = { runId = runId, name = name, ok = ok, detail = detail, extra = extra }
                return true
            end)
            local opts
            if config then
                natives.stub('Config', config)
                opts = { skip = { ['config.lua'] = true } }
            end
            resource.load_resource(DIR, 'client', opts)
        end

        local function runClient(name, kind)
            natives.fire('aeterna_core:selftest', 'r1-abcd', OWNER .. '.' .. name,
                { kind = kind or 'eye', side = 'client', role = 'A' })
        end

        it('contacts_hooks adds a contact, sees one change event and puts the list back', function()
            bootClient()
            kvp.contacts = { { name = 'Ann', number = '555-0101' } }
            local changes = 0
            AddEventHandler('aeterna_phonekit:contactsChanged', function() changes = changes + 1 end)
            runClient('contacts_hooks', 'mock')
            natives.advance(100)
            local r = reports[#reports]
            assert.are.equal('mock', r.ok, r.detail)
            assert.is_true(r.extra.restored)
            assert.are.same({ { name = 'Ann', number = '555-0101' } }, kvp.contacts)
            assert.are.equal(2, changes) -- the add, then the restore
        end)

        it('ped and eye rows that do not fit the held phone skip with the reason', function()
            bootClient()
            runClient('clamp_on_unfold', 'ped')
            natives.advance(10)
            assert.are.same({ 'skip', 'held model is not book' }, { reports[1].ok, reports[1].detail })
            runClient('eye_lock')
            natives.advance(10)
            assert.are.same({ 'skip', 'Config.lockScreen is false' }, { reports[2].ok, reports[2].detail })
        end)

        it('eye_model_pad opens the phone, shows the pad frame and marks the card ready; the end closes it', function()
            bootClient()
            runClient('eye_model_pad')
            natives.advance(400)
            assert.is_truthy(natives.last_emitted('server', 'aeterna_phonekit:sv:open'))
            natives.fire('aeterna_phonekit:cl:open', { apps = {} })
            natives.advance(400)
            local shown
            for _, m in ipairs(nui) do if m.type == 'device' then shown = m.model end end
            assert.are.equal('pad', shown)
            assert.are.equal('ready', reports[#reports].ok)
            local closes = #natives.emitted('server', 'aeterna_phonekit:sv:close')
            natives.fire('aeterna_core:selftestEnd', 'r1-abcd', OWNER .. '.eye_model_pad')
            natives.advance(10)
            assert.are.equal(closes + 1, #natives.emitted('server', 'aeterna_phonekit:sv:close'))
        end)

        it('a test ended by core before the phone opens changes nothing afterwards', function()
            bootClient()
            runClient('eye_model_pad')
            natives.advance(400)
            natives.fire('aeterna_core:selftestEnd', 'r1-abcd', OWNER .. '.eye_model_pad')
            local mark = #nui
            local closes = #natives.emitted('server', 'aeterna_phonekit:sv:close')
            natives.fire('aeterna_phonekit:cl:open', { apps = {} })
            natives.advance(2000)
            for i = mark + 1, #nui do
                assert.is_false(nui[i].type == 'device' and nui[i].model == 'pad', 'device override after the end')
                assert.is_false(nui[i].type == 'fold', 'fold after the end')
            end
            assert.are.equal(0, #reports)
            -- the late open is put away again
            assert.are.equal(closes + 1, #natives.emitted('server', 'aeterna_phonekit:sv:close'))
        end)

        it('eye_battery_dead: with the power off from the server, opening is refused and the card is ready', function()
            bootClient()
            natives.fire('aeterna_phonekit:cl:power', { on = false })
            local opens = #natives.emitted('server', 'aeterna_phonekit:sv:open')
            runClient('eye_battery_dead')
            natives.advance(200)
            assert.are.equal('ready', reports[#reports].ok)
            assert.are.equal(opens, #natives.emitted('server', 'aeterna_phonekit:sv:open'))
            assert.are.equal('phonekit.battery.dead', toasts[#toasts])
        end)

        it('eye_battery_dead: a phone still powered after 1 s fails the row', function()
            bootClient()
            runClient('eye_battery_dead')
            natives.advance(2000)
            local r = reports[#reports]
            assert.are.same({ 'fail', 'phone still powered: the server did not set 0 %' }, { r.ok, r.detail })
        end)

        it('contacts_hooks restores the list even when the add throws', function()
            bootClient()
            kvp.contacts = { { name = 'Ann', number = '555-0101' } }
            failContactsSave = true
            runClient('contacts_hooks', 'mock')
            natives.advance(100)
            failContactsSave = false
            local r = reports[#reports]
            assert.is_false(r.ok)
            assert.is_true(r.extra.restored)
            assert.are.same({ { name = 'Ann', number = '555-0101' } }, kvp.contacts)
        end)

        it('a failed client reportSelftest is logged at warn', function()
            bootClient()
            failReport = true
            runClient('clamp_on_unfold', 'ped')
            assert.are.equal('reportSelftest failed', warns[#warns].msg)
        end)

        it('a phone that does not open fails the row with the refusal', function()
            bootClient()
            runClient('eye_control_centre')
            natives.advance(100)
            natives.fire('aeterna_phonekit:cl:refused', { reason = 'phonekit.refused.nodevice' })
            natives.advance(4000)
            local r = reports[#reports]
            assert.are.same({ 'fail', 'phone did not open: phonekit.refused.nodevice' }, { r.ok, r.detail })
        end)
    end)
end)

describe('aeterna_phonekit icons for the camera package', function()
    it('camera and image are in the icon whitelist and drawn in icons.js', function()
        natives.reset()
        local L = load('phone.lua')
        assert.is_true(L.isValidIcon('camera'))
        assert.is_true(L.isValidIcon('image'))
        local f = assert(io.open(DIR .. '/html/icons.js', 'rb'))
        local js = f:read('*a')
        f:close()
        assert.is_truthy(js:find("    'camera': [", 1, true))
        assert.is_truthy(js:find("    'image': [", 1, true))
    end)
end)
