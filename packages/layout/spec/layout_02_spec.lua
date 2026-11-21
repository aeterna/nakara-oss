-- layout_02_spec.lua -- busted tests for the aeterna_layout 0.2 additions (docs/specs/aeterna_layout.md § 0.2 additions):
-- clamp on size change, presets, export / import as text, snap prefs, the menu panel and the client wiring.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'
local CORE_IMPORT = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' }

local function load_logic()
    local L = assert(loadfile(DIR .. '/shared/logic/layout.lua'))()
    assert(loadfile(DIR .. '/shared/logic/share.lua'))()
    return L
end

local function load_shipped_config()
    local previous = rawget(_G, 'Config')
    assert(loadfile(DIR .. '/config.lua'))()
    local cfg = rawget(_G, 'Config')
    rawset(_G, 'Config', previous)
    return cfg
end

local CFG = { snap = 8, snapSteps = { 8, 16, 32 }, scale = { min = 0.5, max = 2.0, step = 0.05 }, maxElements = 64 }

local function def(overrides)
    local d = { id = 'box', label = 'Box', w = 300, h = 100, x = 0.5, y = 0.5, ax = 0.5, ay = 0.5,
        scalable = true, hideable = true }
    for k, v in pairs(overrides or {}) do d[k] = v end
    return d
end

local function near(a, b, eps)
    return math.abs(a - b) <= (eps or 1e-6)
end

local function newRegistry(L, opts)
    local log = { applied = {}, clamped = {}, saves = {}, warns = {} }
    local o = {
        config = CFG,
        warn = function(msg, fields) log.warns[#log.warns + 1] = { msg = msg, fields = fields } end,
        onApply = function(owner, id, place) log.applied[#log.applied + 1] = { owner = owner, id = id, place = place } end,
        onClamp = function(owner, id, place) log.clamped[#log.clamped + 1] = { owner = owner, id = id, place = place } end,
        savePlaces = function(places) log.saves[#log.saves + 1] = places end,
    }
    for k, v in pairs(opts or {}) do o[k] = v end
    return L.createRegistry(o), log
end

local function lastApplied(log)
    return log.applied[#log.applied].place
end

local function samePlace(a, b)
    return a.x == b.x and a.y == b.y and a.ax == b.ax and a.ay == b.ay and a.scale == b.scale
        and (a.hidden == true) == (b.hidden == true)
end

local function loadClient(opts)
    opts = opts or {}
    natives.reset({ resource = 'aeterna_layout', side = 'client' })
    for k, v in pairs(opts.kvp or {}) do natives.set_kvp(k, v) end
    natives.spy('SetNuiFocus')
    natives.spy('SetNuiFocusKeepInput')
    local h = { callbacks = {}, messages = natives.spy('SendNUIMessage') }
    natives.spy('RegisterNUICallback', function(name, fn) h.callbacks[name] = fn end)
    natives.spy('RegisterCommand')
    natives.spy('RegisterKeyMapping')
    natives.spy('GetResourceState', function() return 'started' end)
    natives.stub_export('aeterna_core', 'requestFocus', function() return 'tok_1' end)
    natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
    natives.stub_export('aeterna_core', 'themeHref', function() return nil end)
    natives.stub_export('aeterna_core', 'themePreset', function() return 'asphalt' end)
    resource.load_resource(DIR, 'client', { externals = CORE_IMPORT })
    natives.stub('GetInvokingResource', function() return 'aeterna_hudkit' end)

    function h.cb(name, data)
        local reply
        h.callbacks[name](data, function(r) reply = r end)
        return reply
    end

    function h.sent(msgType)
        local out = {}
        for i = 1, #h.messages do
            local m = h.messages[i][1]
            if type(m) == 'table' and m.type == msgType then out[#out + 1] = m end
        end
        return out
    end

    function h.lastSent(msgType)
        local list = h.sent(msgType)
        return list[#list]
    end

    return h
end

describe('aeterna_layout 0.2', function()
    describe('1. size-change clamp (shared/logic/layout.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('keeps a growing element on screen, returns exactly on shrink, never saves, and puts an oversize box at 0, 0', function()
            local saved = { ['res/phone'] = { x = 0.8, y = 0.5, ax = 0, ay = 0.5, scale = 1, hidden = false } }
            local reg, log = newRegistry(L, { initialPlaces = saved })
            reg:setScreen(1920, 1080)

            assert.is_true(reg:add('res', def({ id = 'phone', w = 320, h = 640 })))
            assert.is_true(samePlace(saved['res/phone'], lastApplied(log)))

            -- Grows from 320 to 780 px wide: the box ends at the right edge, anchor unchanged
            assert.is_true(reg:add('res', def({ id = 'phone', w = 780, h = 640 })))
            local grown = lastApplied(log)
            local left, top, sw, sh = L.placeToPixels(grown, 780, 640, 1920, 1080)
            assert.is_true(near(left + sw, 1920), 'right edge at ' .. tostring(left + sw))
            assert.is_true(left >= 0 and top >= 0 and top + sh <= 1080)
            assert.are.equal(0, grown.ax)
            assert.are.equal(0.5, grown.ay)

            -- The saved place never changes
            assert.are.equal(0.8, reg:getSavedPlaces()['res/phone'].x)
            assert.are.equal(0.8, reg:get('res', 'phone').place.x)

            -- Shrinks back: exactly the saved place
            assert.is_true(reg:add('res', def({ id = 'phone', w = 320, h = 640 })))
            assert.is_true(samePlace(saved['res/phone'], lastApplied(log)))

            -- Larger than the screen: the box starts at 0, 0
            assert.is_true(reg:add('res', def({ id = 'phone', w = 2000, h = 1200 })))
            local huge = lastApplied(log)
            local hl, ht = L.placeToPixels(huge, 2000, 1200, 1920, 1080)
            assert.is_true(near(hl, 0) and near(ht, 0), ('oversize box at %s, %s'):format(hl, ht))
            assert.is_true(huge.x >= 0 and huge.x <= 1 and huge.y >= 0 and huge.y <= 1)

            assert.are.equal(0, #log.saves)
            assert.are.equal(0.8, reg:getSavedPlaces()['res/phone'].x)
        end)

        it('clampPlace leaves a place that fits untouched (same values, not recomputed)', function()
            local place = { x = 0.3, y = 0.7, ax = 0.5, ay = 1, scale = 1.25, hidden = true }
            local out, changed = L.clampPlace(place, 200, 100, 1920, 1080)
            assert.is_false(changed)
            assert.is_true(samePlace(place, out))
            assert.are_not.equal(place, out)
        end)
    end)

    describe('2. scale and resolution clamp (shared/logic/layout.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('keeps the box on screen at scale 2.0 near the bottom edge (editor) and when the width drops from 3440 to 1280', function()
            local reg, log = newRegistry(L)
            reg:setScreen(1920, 1080)
            reg:add('res', def({ id = 'bar', w = 300, h = 100, x = 0.5, y = 0.9, ax = 0.5, ay = 0 }))
            reg:beginSession()

            local ok = reg:move({ owner = 'res', id = 'bar', x = 0.5, y = 0.9, ax = 0.5, ay = 0, scale = 2.0 })
            assert.is_true(ok)
            local scaled = lastApplied(log)
            local _, top, _, sh = L.placeToPixels(scaled, 300, 100, 1920, 1080)
            assert.is_true(top + sh <= 1080 + 1e-6, 'bottom at ' .. tostring(top + sh))
            assert.are.equal(2.0, scaled.scale)
            assert.are.equal(1, #log.clamped)
            assert.is_true(samePlace(scaled, log.clamped[1].place))
            reg:cancelSession()

            -- Resolution: 3440 -> 1280 px wide
            local reg2, log2 = newRegistry(L)
            reg2:setScreen(3440, 1440)
            reg2:add('res', def({ id = 'wide', w = 300, h = 100, x = 0.9, y = 0.5, ax = 0, ay = 0.5 }))
            assert.are.equal(0.9, lastApplied(log2).x)

            reg2:setScreen(1280, 1440)
            local narrow = lastApplied(log2)
            local left, _, sw = L.placeToPixels(narrow, 300, 100, 1280, 1440)
            assert.is_true(left >= 0 and near(left + sw, 1280), 'right edge at ' .. tostring(left + sw))

            -- Back to the wide screen: exactly the place it had
            reg2:setScreen(3440, 1440)
            assert.are.equal(0.9, lastApplied(log2).x)
            assert.are.equal(0, #log2.saves)
        end)

        it('sends no apply on a screen change that clamps nothing', function()
            local reg, log = newRegistry(L)
            reg:setScreen(1920, 1080)
            reg:add('res', def({ id = 'small', w = 100, h = 50 }))
            local before = #log.applied
            reg:setScreen(2560, 1440)
            assert.are.equal(before, #log.applied)
        end)
    end)

    describe('3. presets (shared/logic/layout.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('passes validation for every shipped preset', function()
            local cfg = load_shipped_config()
            local warns = {}
            local clean, list = L.validatePresets(cfg.presets, cfg, function(msg, f) warns[#warns + 1] = f end)
            assert.are.equal(0, #warns)
            assert.are.same({ 'default', 'centered', 'compact' }, list)
            assert.are.same({}, clean.default)
            for _, name in ipairs({ 'compact', 'centered' }) do
                local n = 0
                for key in pairs(cfg.presets[name]) do
                    n = n + 1
                    assert.is_table(clean[name][key], name .. ' ' .. key)
                end
                assert.is_true(n > 0)
            end
            assert.are.equal(0.85, clean.compact['aeterna_hudkit/status'].scale)
        end)

        it('skips a bad entry with one warn and keeps the rest; refuses bad names and a ninth preset', function()
            local warns = {}
            local function w(msg, f) warns[#warns + 1] = { msg = msg, f = f } end
            local clean = L.validatePresets({
                mine = {
                    ['res/a'] = { x = 2, y = 0.5, ax = 0, ay = 0 },
                    ['res/b'] = { x = 0.2, y = 0.5, ax = 0, ay = 0.5, scale = 1.5 },
                },
            }, CFG, w)
            assert.are.equal(1, #warns)
            assert.is_nil(clean.mine['res/a'])
            assert.are.equal(0.2, clean.mine['res/b'].x)

            warns = {}
            clean = L.validatePresets({
                ['bad name'] = {},
                hid = { ['res/a'] = { x = 0.1, y = 0.1, ax = 0, ay = 0, hidden = true } },
                ['res/key'] = {},
            }, CFG, w)
            assert.is_nil(clean['bad name'])
            assert.is_nil(clean['res/key'])
            assert.is_nil(clean.hid['res/a'])
            assert.are.equal(3, #warns)

            warns = {}
            local many = {}
            for i = 1, 9 do many['p' .. i] = {} end
            local _, list = L.validatePresets(many, CFG, w)
            assert.are.equal(8, #list)
            assert.are.equal(1, #warns)
        end)

        it('applies to the session only, sends unnamed elements to default, never changes hidden, and Cancel restores', function()
            local reg, log = newRegistry(L, {
                initialPlaces = { ['res/a'] = { x = 0.9, y = 0.9, ax = 1, ay = 1, scale = 1, hidden = true },
                                  ['res/b'] = { x = 0.1, y = 0.1, ax = 0, ay = 0, scale = 1.5, hidden = false } },
            })
            reg:setScreen(1920, 1080)
            reg:add('res', def({ id = 'a', w = 100, h = 50 }))
            reg:add('res', def({ id = 'b', w = 100, h = 50 }))
            reg:beginSession()

            local preset = L.validatePresets({ p = {
                ['res/a'] = { x = 0.2, y = 0.8, ax = 0, ay = 1, scale = 0.85 },
                ['gone/el'] = { x = 0.5, y = 0.5, ax = 0.5, ay = 0.5, scale = 1 },
            } }, CFG).p
            assert.is_true(reg:applyPreset(preset))

            local a = reg:get('res', 'a')
            assert.are.equal(0.2, a.place.x)
            assert.are.equal(0.85, a.place.scale)
            assert.is_true(a.place.hidden)
            local b = reg:get('res', 'b')
            assert.are.equal(0.5, b.place.x)
            assert.are.equal(1, b.place.scale)
            assert.are.equal(0, #log.saves)

            reg:cancelSession()
            assert.are.equal(0.9, reg:get('res', 'a').place.x)
            assert.are.equal(0.1, reg:get('res', 'b').place.x)
            assert.are.equal(0, #log.saves)

            -- Done after a preset saves it, and keeps the place for the unregistered element
            reg:beginSession()
            reg:applyPreset(preset)
            reg:commitSession()
            local saved = log.saves[#log.saves]
            assert.are.equal(0.2, saved['res/a'].x)
            assert.is_true(saved['res/a'].hidden)
            assert.is_nil(saved['res/b'])
            assert.are.equal(0.5, saved['gone/el'].x)
        end)

        it('refuses a preset outside the editor session', function()
            local reg = newRegistry(L)
            assert.is_false((reg:applyPreset({})))
        end)
    end)

    describe('4. export (shared/logic/share.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('starts with the prefix, holds only saved places, and round-trips through import', function()
            local saved = { ['aeterna_hudkit/status'] = { x = 0.17, y = 0.97, ax = 0, ay = 1, scale = 0.85, hidden = false },
                            ['aeterna_notify/toasts'] = { x = 0.98, y = 0.02, ax = 1, ay = 0, scale = 1, hidden = true } }
            local reg = newRegistry(L, { initialPlaces = saved })
            reg:add('aeterna_hudkit', def({ id = 'status' }))
            reg:add('aeterna_hudkit', def({ id = 'vehicle' }))

            local text = L.encodeExport(reg:getSavedPlaces())
            assert.are.equal('aeterna-layout:1:', text:sub(1, 17))
            local body = json.decode(text:sub(18))
            assert.are.equal(1, body.v)
            local keys = {}
            for k in pairs(body.places) do keys[#keys + 1] = k end
            table.sort(keys)
            assert.are.same({ 'aeterna_hudkit/status', 'aeterna_notify/toasts' }, keys)

            local ok, err, places = L.decodeImport(text, CFG)
            assert.is_true(ok, tostring(err))
            assert.are.same(saved, places)
        end)

        it('exports an empty layout as a valid text', function()
            local text = L.encodeExport({})
            local ok, err, places = L.decodeImport(text, CFG)
            assert.is_true(ok, tostring(err))
            assert.are.same({}, places)
        end)
    end)

    describe('5. import (shared/logic/share.lua)', function()
        local L
        local PREFIX = 'aeterna-layout:1:'
        local GOOD = { x = 0.17, y = 0.97, ax = 0, ay = 1, scale = 0.85 }
        local function body(places, extra)
            local b = { v = 1, places = places }
            for k, v in pairs(extra or {}) do b[k] = v end
            return PREFIX .. json.encode(b)
        end
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('refuses each bad text whole with the right path', function()
            local cases = {
                { PREFIX .. string.rep(' ', 8193 - #PREFIX), 'text: max 8192 bytes' },
                { 'other-layout:1:{"v":1,"places":{}}', 'text: prefix' },
                { PREFIX .. '{"v":1,', 'text: json' },
                { body({}, { v = 2 }), 'v: version' },
                { body({}, { extra = true }), 'extra: not allowed' },
            }
            local many = {}
            for i = 1, 65 do many['res/el' .. i] = GOOD end
            cases[#cases + 1] = { body(many), 'places: max 64' }
            cases[#cases + 1] = { body({ ['noslash'] = GOOD }), 'places["noslash"]: key' }
            cases[#cases + 1] = { body({ ['bad owner/id'] = GOOD }), 'places["bad owner/id"]: key' }
            cases[#cases + 1] = { body({ ['aeterna_hudkit/status'] = { x = 0.17, y = 0.97, ax = 0, ay = 1, scale = 3 } }),
                'places["aeterna_hudkit/status"].scale: out of range' }
            cases[#cases + 1] = { body({ ['aeterna_hudkit/status'] = { x = 0.17, y = 0.97, ax = 0.3, ay = 1, scale = 1 } }),
                'places["aeterna_hudkit/status"].ax: enum' }
            cases[#cases + 1] = { body({ ['aeterna_hudkit/status'] = { x = 0.17, y = 0.97, ax = 0, ay = 1, scale = 1, color = 'red' } }),
                'places["aeterna_hudkit/status"].color: not allowed' }
            cases[#cases + 1] = { body({ ['aeterna_hudkit/status'] = { x = 0.17, y = 0.97, ax = 0, ay = 1, scale = 1, hidden = 'yes' } }),
                'places["aeterna_hudkit/status"].hidden: type' }

            for _, c in ipairs(cases) do
                local ok, err, places, kind = L.decodeImport(c[1], CFG)
                assert.is_false(ok, c[2])
                assert.are.equal(c[2], err)
                assert.is_nil(places)
                assert.are.equal(c[2] == 'v: version' and 'version' or 'invalid', kind)
            end
        end)

        it('accepts a valid text and defaults hidden to false', function()
            local ok, err, places = L.decodeImport(body({ ['aeterna_hudkit/status'] = GOOD }), CFG)
            assert.is_true(ok, tostring(err))
            assert.is_false(places['aeterna_hudkit/status'].hidden)
        end)

        it('checks the import callback payload size before parsing', function()
            assert.is_true((L.validateImportCallback({ text = PREFIX .. '{}' })))
            assert.is_false((L.validateImportCallback({ text = string.rep('a', 8193) })))
            assert.is_false((L.validateImportCallback({ text = 5 })))
            assert.is_false((L.validateImportCallback({ text = 'a', more = 1 })))
        end)

        it('a refused import changes nothing in the editor session (client)', function()
            local h = loadClient()
            natives.fire('aeterna_layout:add', def({ id = 'status' }))
            h.cb('screen', { w = 1920, h = 1080 })
            natives.fire_net('aeterna_layout:cl:open', 1)
            local appliesBefore = #natives.emitted('local', 'aeterna_layout:apply')

            h.cb('import', { text = body({ ['aeterna_hudkit/status'] = { x = 0.1, y = 0.1, ax = 0, ay = 0, scale = 9 } }) })
            local result = h.lastSent('import:result')
            assert.is_false(result.ok)
            assert.is_truthy(result.error:find('places["aeterna_hudkit/status"].scale: out of range', 1, true))
            assert.are.equal(appliesBefore, #natives.emitted('local', 'aeterna_layout:apply'))

            h.cb('import', { text = body({}, { v = 2 }) })
            assert.are.equal('Unsupported layout text version', h.lastSent('import:result').error)

            h.cb('done', {})
            assert.is_nil(natives.get_kvp('aeterna_layout:places:v1') and json.decode(natives.get_kvp('aeterna_layout:places:v1'))['aeterna_hudkit/status'])

            -- A valid import moves the element, Done saves it
            natives.fire_net('aeterna_layout:cl:open', 1)
            h.cb('import', { text = body({ ['aeterna_hudkit/status'] = GOOD, ['other_res/x'] = GOOD }) })
            assert.is_true(h.lastSent('import:result').ok)
            local applied = natives.last_emitted('local', 'aeterna_layout:apply')
            assert.are.equal(0.17, applied.args[3].x)
            h.cb('done', {})
            local savedNow = json.decode(natives.get_kvp('aeterna_layout:places:v1'))
            assert.are.equal(0.85, savedNow['aeterna_hudkit/status'].scale)
            assert.are.equal(0.17, savedNow['other_res/x'].x)

            -- Export shows the saved places
            natives.fire_net('aeterna_layout:cl:open', 1)
            h.cb('exportOpen', {})
            local shown = h.lastSent('export:show')
            local ok, err, places = LayoutLogic.decodeImport(shown.text, CFG)
            assert.is_true(ok, tostring(err))
            assert.are.equal(0.17, places['other_res/x'].x)
            h.cb('cancel', {})
        end)
    end)

    describe('6. snap prefs (shared/logic/layout.lua + client)', function()
        local L
        before_each(function()
            natives.reset()
            L = load_logic()
        end)

        it('accepts only 0, 8, 16 and 32 by default', function()
            for _, v in ipairs({ 0, 8, 16, 32 }) do
                assert.is_true(L.isValidSnapStep(v, CFG), tostring(v))
            end
            for _, v in ipairs({ 4, 12, -8, 8.5, 64, '8', true }) do
                assert.is_false(L.isValidSnapStep(v, CFG), tostring(v))
            end
            assert.are.same({ 8, 16, 32 }, L.resolveSnapSteps(CFG))
        end)

        it('uses Config.snap when nothing is saved, and the saved pick otherwise', function()
            assert.are.equal(8, L.resolveSnapPref(nil, CFG))
            assert.are.equal(16, L.resolveSnapPref(nil, { snap = 16, snapSteps = { 8, 16, 32 } }))
            assert.are.equal(0, L.resolveSnapPref({ snap = 0 }, CFG))
            assert.are.equal(32, L.resolveSnapPref({ snap = 32 }, CFG))
            assert.are.equal(8, L.resolveSnapPref({ snap = 12 }, CFG))
        end)

        it('keeps the pick in KVP aeterna_layout:prefs:v1 across a restart (client)', function()
            local h = loadClient()
            natives.fire_net('aeterna_layout:cl:open', 1)
            assert.are.equal(8, h.lastSent('editor:open').snap)

            h.cb('snap', { step = 16 })
            assert.are.equal(16, json.decode(natives.get_kvp('aeterna_layout:prefs:v1')).snap)
            h.cb('snap', { step = 12 })
            assert.are.equal(16, json.decode(natives.get_kvp('aeterna_layout:prefs:v1')).snap)
            h.cb('cancel', {})

            local raw = natives.get_kvp('aeterna_layout:prefs:v1')
            local h2 = loadClient({ kvp = { ['aeterna_layout:prefs:v1'] = raw } })
            natives.fire_net('aeterna_layout:cl:open', 1)
            local open = h2.lastSent('editor:open')
            assert.are.equal(16, open.snap)
            assert.are.same({ 8, 16, 32 }, open.snapSteps)
        end)
    end)

    describe('7. client wiring (client/main.lua)', function()
        it('clamps on a screen report outside the editor, sends presets on open and applies one', function()
            local h = loadClient()
            natives.fire('aeterna_layout:add', def({ id = 'status', w = 300, h = 100, x = 0.9, y = 0.5, ax = 0, ay = 0.5 }))
            h.cb('screen', { w = 3440, h = 1440 })
            local before = #natives.emitted('local', 'aeterna_layout:apply')
            h.cb('screen', { w = 1280, h = 1440 })
            local after = natives.emitted('local', 'aeterna_layout:apply')
            assert.are.equal(before + 1, #after)
            local p = after[#after].args[3]
            assert.is_true(p.x * 1280 + 300 <= 1280 + 1e-6)
            assert.is_nil(natives.get_kvp('aeterna_layout:places:v1'))

            -- Bad screen payloads are refused
            local n = #natives.emitted('local', 'aeterna_layout:apply')
            h.cb('screen', { w = 0, h = 1080 })
            h.cb('screen', { w = 16385, h = 1080 })
            h.cb('screen', { w = 1920.5, h = 1080 })
            assert.are.equal(n, #natives.emitted('local', 'aeterna_layout:apply'))

            natives.fire_net('aeterna_layout:cl:open', 1)
            local presets = h.lastSent('editor:presets')
            assert.are.equal('default', presets.list[1].name)
            assert.are.equal('Default', presets.list[1].label)
            assert.are.equal(3, #presets.list)

            h.cb('preset', { name = 'compact' })
            local applied = natives.last_emitted('local', 'aeterna_layout:apply')
            assert.are.equal(0.85, applied.args[3].scale)
            h.cb('preset', { name = 'nope' })
            h.cb('cancel', {})
            assert.are.equal(p.x, natives.last_emitted('local', 'aeterna_layout:apply').args[3].x)
        end)

        it('ignores editor input while paused by a focus overlay and resumes after', function()
            local h = loadClient()
            natives.fire('aeterna_layout:add', def({ id = 'status' }))
            natives.fire_net('aeterna_layout:cl:open', 1)
            natives.fire('aeterna_core:focusPaused', 'aeterna_layout', 'tok_1')
            local n = #natives.emitted('local', 'aeterna_layout:apply')
            h.cb('moved', { owner = 'aeterna_hudkit', id = 'status', x = 0.1, y = 0.1, ax = 0, ay = 0, scale = 1 })
            h.cb('done', {})
            assert.are.equal(n, #natives.emitted('local', 'aeterna_layout:apply'))
            assert.is_nil(natives.get_kvp('aeterna_layout:places:v1'))

            natives.fire('aeterna_core:focusResumed', 'aeterna_layout', 'tok_1')
            h.cb('moved', { owner = 'aeterna_hudkit', id = 'status', x = 0.1, y = 0.1, ax = 0, ay = 0, scale = 1 })
            assert.are.equal(n + 1, #natives.emitted('local', 'aeterna_layout:apply'))
            h.cb('done', {})
            assert.are.equal(0.1, json.decode(natives.get_kvp('aeterna_layout:places:v1'))['aeterna_hudkit/status'].x)
        end)

        it('opens the share box for mode share, and mode reset clears the saved layout at once', function()
            local saved = json.encode({ ['aeterna_hudkit/status'] = { x = 0.1, y = 0.1, ax = 0, ay = 0, scale = 1, hidden = false },
                                        ['gone/el'] = { x = 0.2, y = 0.2, ax = 0, ay = 0, scale = 1, hidden = false } })
            local h = loadClient({ kvp = { ['aeterna_layout:places:v1'] = saved } })
            natives.fire('aeterna_layout:add', def({ id = 'status' }))
            assert.are.equal(0.1, natives.last_emitted('local', 'aeterna_layout:apply').args[3].x)

            natives.fire_net('aeterna_layout:cl:open', 1, { mode = 'share' })
            assert.is_truthy(h.lastSent('editor:open'))
            local shown = h.lastSent('export:show')
            assert.are.equal('aeterna-layout:1:', shown.text:sub(1, 17))
            h.cb('cancel', {})

            natives.fire_net('aeterna_layout:cl:open', 1, { mode = 'bogus' })
            assert.are.equal(1, #h.sent('editor:open'))

            natives.fire_net('aeterna_layout:cl:open', 1, { mode = 'reset' })
            assert.are.equal(0.5, natives.last_emitted('local', 'aeterna_layout:apply').args[3].x)
            assert.are.same({}, json.decode(natives.get_kvp('aeterna_layout:places:v1')))
            assert.are.equal(1, #h.sent('editor:open'))
        end)
    end)

    describe('8. menu panel (server/main.lua)', function()
        local function loadServer(menuPanel)
            natives.reset({ resource = 'aeterna_layout', side = 'server' })
            local h = { opened = {}, closed = {} }
            natives.stub_export('aeterna_uikit', 'addMenuEntry', function() return true end)
            natives.stub_export('aeterna_uikit', 'open', function(src, spec)
                h.opened[#h.opened + 1] = { src = src, spec = spec }
                return 'p1'
            end)
            natives.stub_export('aeterna_uikit', 'close', function(src)
                h.closed[#h.closed + 1] = src
                return true
            end)
            resource.load_resource(DIR, 'server', { externals = CORE_IMPORT })
            if menuPanel ~= nil then Config.menuPanel = menuPanel end
            return h
        end

        local function buttonIds(spec)
            local ids = {}
            for _, block in ipairs(spec.blocks) do
                if block.type == 'buttons' then
                    for _, item in ipairs(block.items) do ids[#ids + 1] = item.id end
                end
            end
            return ids
        end

        it('opens the panel and maps Edit, Export / import and a confirmed Reset all to the client event', function()
            local h = loadServer()
            natives.fire('aeterna_uikit:menu', 4, { owner = 'aeterna_layout', id = 'layout' })
            assert.are.equal(0, #natives.emitted('client', 'aeterna_layout:cl:open'))
            assert.are.equal(1, #h.opened)
            assert.are.same({ 'edit', 'resetAll', 'share' }, buttonIds(h.opened[1].spec))

            local function act(action, owner)
                natives.fire('aeterna_uikit:action', 4, { owner = owner or 'aeterna_layout', panelId = 'p1', action = action, values = {} })
            end

            act('edit', 'other_res')
            assert.are.equal(0, #natives.emitted('client', 'aeterna_layout:cl:open'))

            act('edit')
            local ev = natives.last_emitted('client', 'aeterna_layout:cl:open')
            assert.are.equal(4, ev.target)
            assert.are.same({ mode = 'editor' }, ev.args[1])

            act('share')
            assert.are.same({ mode = 'share' }, natives.last_emitted('client', 'aeterna_layout:cl:open').args[1])

            local sends = #natives.emitted('client', 'aeterna_layout:cl:open')
            act('resetAll')
            assert.are.equal(sends, #natives.emitted('client', 'aeterna_layout:cl:open'))
            assert.are.same({ 'resetConfirm', 'back' }, buttonIds(h.opened[#h.opened].spec))
            act('back')
            assert.are.same({ 'edit', 'resetAll', 'share' }, buttonIds(h.opened[#h.opened].spec))
            act('resetConfirm')
            assert.are.same({ mode = 'reset' }, natives.last_emitted('client', 'aeterna_layout:cl:open').args[1])

            act('__close')
            act('unknown')
            assert.are.equal(sends + 1, #natives.emitted('client', 'aeterna_layout:cl:open'))
        end)

        it('keeps the 0.1 behaviour with Config.menuPanel = false', function()
            local h = loadServer(false)
            natives.fire('aeterna_uikit:menu', 4, { owner = 'aeterna_layout', id = 'layout' })
            assert.are.equal(0, #h.opened)
            local ev = natives.last_emitted('client', 'aeterna_layout:cl:open')
            assert.are.equal(4, ev.target)
        end)
    end)

    describe('9. locales 0.2 (locales/*.lua)', function()
        it('has every 0.2 key in en and th', function()
            local previous = rawget(_G, 'Locales')
            rawset(_G, 'Locales', {})
            assert(loadfile(DIR .. '/locales/en.lua'))()
            assert(loadfile(DIR .. '/locales/th.lua'))()
            local loaded = rawget(_G, 'Locales')
            rawset(_G, 'Locales', previous)
            local keys = { 'layout.editor.preset', 'layout.preset.default', 'layout.preset.compact', 'layout.preset.centered',
                'layout.editor.snapOff', 'layout.menu.edit', 'layout.menu.resetAll', 'layout.menu.share', 'layout.export.title',
                'layout.export.hint', 'layout.import.title', 'layout.import.apply', 'layout.import.ok', 'layout.import.version',
                'layout.import.invalid' }
            for _, k in ipairs(keys) do
                assert.is_string(loaded.en[k], 'en ' .. k)
                assert.is_string(loaded.th[k], 'th ' .. k)
            end
        end)
    end)
end)
