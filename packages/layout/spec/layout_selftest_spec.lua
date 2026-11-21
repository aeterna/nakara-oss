-- layout_selftest_spec.lua -- aeterna_layout self-tests (docs/specs/aeterna_layout.md § Self-tests (0.2)): the rows
-- it registers with aeterna_core, the pure checks in shared/logic/selftests.lua, and the thin wrappers.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'
local CORE = HERE .. '/../../core'
local CORE_IMPORT = { ['@aeterna_core/import.lua'] = CORE .. '/import.lua' }

local CFG = { snap = 8, snapSteps = { 8, 16, 32 }, scale = { min = 0.5, max = 2.0, step = 0.05 }, maxElements = 64 }

local function loadModules()
    natives.reset()
    rawset(_G, 'Locales', nil)
    rawset(_G, 'LayoutLogic', nil)
    assert(loadfile(DIR .. '/locales/en.lua'))()
    assert(loadfile(DIR .. '/locales/th.lua'))()
    local L = assert(loadfile(DIR .. '/shared/logic/layout.lua'))()
    assert(loadfile(DIR .. '/shared/logic/share.lua'))()
    assert(loadfile(DIR .. '/shared/logic/selftests.lua'))()
    return L, LayoutSelftests
end

local function coreNormalize()
    rawset(_G, 'AeternaCoreLogic', nil)
    assert(loadfile(CORE .. '/shared/logic/selftest.lua'))()
    return AeternaCoreLogic.selftest.normalize
end

local function translator(lang)
    return function(key, vars)
        local s = Locales[lang][key] or key
        return (s:gsub('{([%w_]+)}', function(k) return vars and vars[k] ~= nil and tostring(vars[k]) or '{' .. k .. '}' end))
    end
end

local function broken(L, name, fn)
    return setmetatable({ [name] = fn }, { __index = L })
end

-- name, kind, side, destructive, has Expect
local SPEC_ROWS = {
    { 'placement_math', 'headless', 'server', false, false },
    { 'import_validate', 'headless', 'server', false, false },
    { 'clamp_on_grow', 'mock', 'client', false, false },
    { 'preset_apply', 'eye', 'client', false, true },
    { 'grid_drag', 'ped', 'client', false, true },
    { 'export_import', 'ped', 'client', false, true },
    { 'export_copy', 'ped', 'client', false, true },
    { 'reset_from_menu', 'ped', 'client', true, true },
}

describe('aeterna_layout self-tests: rows', function()
    it('registers exactly the spec rows, in order, with core-valid meta', function()
        local _, S = loadModules()
        local normalize = coreNormalize()
        local added = {}
        S.register(function(name, meta) added[#added + 1] = { name = name, meta = meta } return name end, translator('en'))
        assert.are.equal(#SPEC_ROWS, #added)
        for i, row in ipairs(SPEC_ROWS) do
            assert.are.equal('aeterna_layout.' .. row[1], added[i].name)
            local fields, err = normalize(added[i].meta)
            assert.is_nil(err, row[1])
            assert.are.equal(row[2], fields.kind, row[1])
            assert.are.equal(row[3], fields.side, row[1])
            assert.are.equal(1, fields.players, row[1])
            assert.are.equal(row[4], fields.destructive, row[1])
            assert.are.equal(5000, fields.timeout, row[1])
            assert.is_nil(fields.ask, row[1])
            assert.is_nil(fields.skipWhen, row[1])
            if row[5] then
                assert.is_true(type(fields.expect) == 'string' and fields.expect ~= '', row[1])
            else
                assert.is_nil(fields.expect, row[1])
            end
        end
    end)

    it('takes every expect from the locale, in th and en', function()
        local _, S = loadModules()
        for _, lang in ipairs({ 'en', 'th' }) do
            local metas = {}
            S.register(function(name, meta) metas[name] = meta return name end, translator(lang))
            for _, row in ipairs(SPEC_ROWS) do
                if row[5] then
                    local key = 'layout.selftest.' .. row[1]
                    assert.is_string(Locales[lang][key], lang .. ' ' .. key)
                    assert.are.equal(Locales[lang][key], metas['aeterna_layout.' .. row[1]].expect)
                    assert.is_true(utf8.len(Locales[lang][key]) <= 240, key)
                end
            end
        end
    end)

    it('maps a full name back to its row only for this resource', function()
        local _, S = loadModules()
        assert.are.equal('grid_drag', S.shortName('aeterna_layout.grid_drag'))
        assert.is_nil(S.shortName('aeterna_uikit.grid_drag'))
        assert.is_nil(S.shortName('aeterna_layout.nope'))
    end)
end)

describe('aeterna_layout self-tests: headless checks', function()
    it('placement_math passes on the real logic', function()
        local L, S = loadModules()
        local ok, detail = S.run('placement_math', L, CFG)
        assert.is_true(ok, detail)
    end)

    it('placement_math fails when a grown element is not clamped', function()
        local L, S = loadModules()
        local ok, detail = S.run('placement_math', broken(L, 'clampPlace', function(place)
            local out = {}
            for k, v in pairs(place) do out[k] = v end
            return out, false
        end), CFG)
        assert.is_false(ok)
        assert.matches('grows from 320 to 780', detail, 1, true)
    end)

    it('import_validate passes on the real logic', function()
        local L, S = loadModules()
        local ok, detail = S.run('import_validate', L, CFG)
        assert.is_true(ok, detail)
    end)

    it('import_validate fails when an over-long text is accepted', function()
        local L, S = loadModules()
        local ok, detail = S.run('import_validate', broken(L, 'decodeImport', function(text, cfg)
            if #text > 8192 then return true, nil, {}, nil end
            return L.decodeImport(text, cfg)
        end), CFG)
        assert.is_false(ok)
        assert.matches('8193 bytes', detail, 1, true)
    end)

    it('run returns nil for a client test', function()
        local L, S = loadModules()
        assert.is_nil(S.run('grid_drag', L, CFG))
    end)
end)

describe('aeterna_layout self-tests: client judges', function()
    it('boxOnScreen', function()
        local _, S = loadModules()
        assert.is_true((S.boxOnScreen({ x = 1, y = 0.5, ax = 1, ay = 0.5, scale = 1 }, 320, 60, 1920, 1080)))
        assert.is_false((S.boxOnScreen({ x = 1, y = 0.5, ax = 0, ay = 0.5, scale = 1 }, 320, 60, 1920, 1080)))
        assert.is_false((S.boxOnScreen({ x = 0.5, y = 1, ax = 0.5, ay = 0, scale = 2 }, 320, 60, 1920, 1080)))
    end)

    it('growDef puts a left-anchored box flush with the right edge', function()
        local L, S = loadModules()
        local d = S.growDef(320, 1920, 'label')
        assert.are.equal(0, d.ax)
        assert.is_true(math.abs(d.x * 1920 + 320 - 1920) < 1e-6)
        assert.is_true((L.validateDef(d, CFG)))
    end)

    it('judgeGrid: snapped drag lands on the grid with the grid shown; Shift drag shows no grid and lands off it', function()
        local _, S = loadModules()
        local snapped = { grid = true, left = 432, top = 216 }
        local free = { grid = false, left = 437, top = 221 }
        assert.is_true((S.judgeGrid(snapped, free, 8)))
        assert.is_false((S.judgeGrid({ grid = false, left = 432, top = 216 }, free, 8)))
        assert.is_false((S.judgeGrid({ grid = true, left = 433, top = 216 }, free, 8)))
        assert.is_false((S.judgeGrid(snapped, { grid = true, left = 437, top = 221 }, 8)))
        assert.is_false((S.judgeGrid(snapped, { grid = false, left = 440, top = 224 }, 8)))
        assert.is_false((S.judgeGrid(nil, free, 8)))
    end)

    it('judgeExportImport: one line, shown in the page, imported back to the same places', function()
        local _, S = loadModules()
        local p = { x = 0.5, y = 0.5, ax = 0.5, ay = 0.5, scale = 1, hidden = false }
        local good = { text = 'aeterna-layout:1:{}', pageText = 'aeterna-layout:1:{}', importOk = true, before = p, after = p }
        assert.is_true((S.judgeExportImport(good)))
        local function with(k, v)
            local f = {}
            for kk, vv in pairs(good) do f[kk] = vv end
            f[k] = v
            return f
        end
        assert.is_false((S.judgeExportImport(with('text', 'aeterna-layout:1:{\n}'))))
        assert.is_false((S.judgeExportImport(with('text', nil))))
        assert.is_false((S.judgeExportImport(with('pageText', 'other'))))
        assert.is_false((S.judgeExportImport(with('importOk', false))))
        assert.is_false((S.judgeExportImport(with('after', { x = 0.4, y = 0.5, ax = 0.5, ay = 0.5, scale = 1, hidden = false }))))
    end)

    it('judgeCopy needs a copy, a matching paste and an accepted import', function()
        local _, S = loadModules()
        assert.is_true((S.judgeCopy({ copied = true, pasted = true, matches = true }, true)))
        assert.is_false((S.judgeCopy({ copied = false, pasted = true, matches = true }, true)))
        assert.is_false((S.judgeCopy({ copied = true, pasted = false, matches = false }, nil)))
        assert.is_false((S.judgeCopy({ copied = true, pasted = true, matches = true }, false)))
        assert.is_false((S.judgeCopy(nil, nil)))
    end)

    it('judgeReset needs an empty saved layout and every element at its default', function()
        local _, S = loadModules()
        local d = { x = 0.1, y = 0.9, ax = 0, ay = 1, scale = 1, hidden = false }
        local moved = { x = 0.5, y = 0.9, ax = 0, ay = 1, scale = 1, hidden = false }
        assert.is_true((S.judgeReset({}, { { key = 'a/b', place = d, default = d } })))
        assert.is_false((S.judgeReset({ ['a/b'] = moved }, { { key = 'a/b', place = d, default = d } })))
        assert.is_false((S.judgeReset({}, { { key = 'a/b', place = moved, default = d } })))
    end)
end)

describe('aeterna_layout self-tests: wrappers', function()
    local reports

    local function stubCore()
        reports = {}
        natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail, extra)
            reports[#reports + 1] = { runId = runId, name = name, ok = ok, detail = detail, extra = extra }
            return true
        end)
    end

    it('the server registers all eight rows on start and answers its headless tests', function()
        natives.reset({ side = 'server', resource = 'aeterna_layout' })
        rawset(_G, 'Locales', nil)
        rawset(_G, 'Config', nil)
        stubCore()
        local added = {}
        natives.stub_export('aeterna_core', 'addSelftest', function(name) added[#added + 1] = name return name end)
        natives.stub_export('aeterna_uikit', 'addMenuEntry', function() return true end)
        resource.load_resource(DIR, 'server', { externals = CORE_IMPORT })
        assert.are.equal(8, #added)

        natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_layout.import_validate', { kind = 'headless', side = 'server' })
        natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_layout.grid_drag', { kind = 'ped', side = 'client' })
        assert.are.equal(1, #reports)
        assert.are.equal('aeterna_layout.import_validate', reports[1].name)
        assert.is_true(reports[1].ok, reports[1].detail)
    end)

    describe('client', function()
        local h

        local function loadClient(kvp)
            natives.reset({ resource = 'aeterna_layout', side = 'client' })
            rawset(_G, 'Locales', nil)
            rawset(_G, 'Config', nil)
            rawset(_G, 'AeternaCore', nil)
            for k, v in pairs(kvp or {}) do natives.set_kvp(k, v) end
            natives.spy('SetNuiFocus')
            natives.spy('SetNuiFocusKeepInput')
            h = { callbacks = {}, messages = natives.spy('SendNUIMessage') }
            natives.spy('RegisterNUICallback', function(name, fn) h.callbacks[name] = fn end)
            natives.spy('RegisterCommand')
            natives.spy('RegisterKeyMapping')
            natives.spy('GetResourceState', function() return 'started' end)
            natives.stub_export('aeterna_core', 'requestFocus', function() return 'tok_1' end)
            natives.stub_export('aeterna_core', 'releaseFocus', function() return true end)
            natives.stub_export('aeterna_core', 'themeHref', function() return nil end)
            natives.stub_export('aeterna_core', 'themePreset', function() return 'asphalt' end)
            stubCore()
            resource.load_resource(DIR, 'client', { externals = CORE_IMPORT })
            function h.cb(name, data) h.callbacks[name](data, function() end) end
            function h.sent(msgType)
                local out = {}
                for i = 1, #h.messages do
                    local m = h.messages[i][1]
                    if type(m) == 'table' and m.type == msgType then out[#out + 1] = m end
                end
                return out
            end
        end

        local function fire(short, kind, side)
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_layout.' .. short, { kind = kind, side = side or 'client' })
        end

        it('clamp_on_grow keeps the grown test element on screen, removes it and reports mock restored', function()
            loadClient()
            h.cb('screen', { w = 1920, h = 1080 })
            fire('clamp_on_grow', 'mock')
            natives.advance(100)
            assert.are.equal(1, #reports)
            assert.are.equal('mock', reports[1].ok, reports[1].detail)
            assert.is_true(reports[1].extra.restored)
            assert.is_nil(natives.get_kvp('aeterna_layout:places:v1'))
        end)

        it('clamp_on_grow fails while the screen size is unknown', function()
            loadClient()
            fire('clamp_on_grow', 'mock')
            natives.advance(100)
            assert.are.equal('fail', reports[1].ok)
        end)

        it('export_import: the page shows the export text and importing it puts the moved element back', function()
            loadClient()
            h.cb('screen', { w = 1920, h = 1080 })
            fire('export_import', 'ped')
            natives.advance(500)
            local drive = h.sent('selftest:drive')
            assert.are.equal(1, #drive)
            assert.are.equal('export', drive[1].op)
            local shown = h.sent('export:show')
            h.cb('selftestProbe', { op = 'export', text = shown[#shown].text })
            natives.advance(500)
            assert.are.equal(1, #reports)
            assert.are.equal('pass', reports[1].ok, reports[1].detail)
            assert.is_true(#h.sent('editor:close') >= 1)
            assert.is_nil(natives.get_kvp('aeterna_layout:places:v1'))
        end)

        it('preset_apply opens the editor with compact and closes it, unsaved, when the test ends', function()
            loadClient()
            h.cb('screen', { w = 1920, h = 1080 })
            fire('preset_apply', 'eye')
            natives.advance(100)
            assert.are.equal('ready', reports[1].ok)
            assert.is_true(#h.sent('editor:open') >= 1)
            natives.advance(7000)
            natives.fire('aeterna_core:selftestEnd', 'r1-abcd', 'aeterna_layout.preset_apply')
            assert.are.equal(1, #h.sent('editor:close'))
            assert.is_nil(natives.get_kvp('aeterna_layout:places:v1'))
        end)

        it('reset_from_menu clears the saved layout and reports a declared write', function()
            local saved = '{"aeterna_hudkit/status":{"x":0.5,"y":0.5,"ax":0.5,"ay":0.5,"scale":1,"hidden":false}}'
            loadClient({ ['aeterna_layout:places:v1'] = saved })
            natives.stub('GetInvokingResource', function() return 'aeterna_hudkit' end)
            natives.fire('aeterna_layout:add', { id = 'status', label = 'Status', w = 200, h = 60, x = 0.1, y = 0.9, ax = 0, ay = 1 })
            natives.stub('GetInvokingResource', function() return nil end)
            fire('reset_from_menu', 'ped')
            natives.advance(500)
            assert.are.equal(1, #reports)
            assert.are.equal('pass', reports[1].ok, reports[1].detail)
            assert.is_true(reports[1].extra.wrote)
            -- an empty table: the encoder may write it as {} or []
            assert.are.same({}, json.decode(natives.get_kvp('aeterna_layout:places:v1')))
        end)
    end)
end)
