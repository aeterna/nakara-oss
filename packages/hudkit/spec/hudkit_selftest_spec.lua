-- spec/hudkit_selftest_spec.lua -- busted tests for the aeterna_hudkit 0.2 self-tests
-- (docs/specs/aeterna_hudkit.md § Self-tests (0.2); judging rules in docs/specs/aeterna_core.md § 0.2 additions).

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'
local CORE_DIR = DIR .. '/../core'

local function load_logic(name)
    return assert(loadfile(DIR .. '/shared/logic/' .. name .. '.lua'))()
end

local function core_rules()
    return assert(loadfile(CORE_DIR .. '/shared/logic/selftest.lua'))()
end

local function shipped_config(overrides)
    local cfg = {
        tick = 200, low = 20, needs = { 'hunger', 'thirst', 'stress' }, speedUnit = 'kmh',
        minimap = { mode = 'always' }, hideBaseBars = true, barStyle = 'bar',
        compass = { enabled = true, span = 120 }, voice = { enabled = true }, seatbelt = { enabled = true },
    }
    for k, v in pairs(overrides or {}) do cfg[k] = v end
    return cfg
end

local function by_name(defs)
    local out = {}
    for _, d in ipairs(defs) do out[d.name] = d.meta end
    return out
end

describe('aeterna_hudkit self-tests', function()
    local ST

    before_each(function()
        natives.reset()
        load_logic('hud')
        load_logic('compass')
        load_logic('minimap')
        load_logic('seatbelt')
        ST = load_logic('selftest')
    end)

    describe('registration rows', function()
        it('lists exactly the eight spec rows, in spec order', function()
            local names = {}
            for i, d in ipairs(ST.definitions()) do names[i] = d.name end
            assert.are.same({ 'values_mapping', 'compass_math', 'bar_style', 'compass_tape', 'voice_indicator',
                'voice_radio', 'seatbelt_event', 'minimap_follows' }, names)
        end)

        it('sets kind, side, players and destructive as the spec table says', function()
            local m = by_name(ST.definitions())
            local want = {
                values_mapping = { 'headless', 'server' }, compass_math = { 'headless', 'server' },
                bar_style = { 'eye', 'client' }, compass_tape = { 'ped', 'client' },
                voice_indicator = { 'ped', 'client' }, voice_radio = { 'ped', 'client' },
                seatbelt_event = { 'mock', 'client' }, minimap_follows = { 'ped', 'client' },
            }
            local rules = core_rules()
            for name, kw in pairs(want) do
                local test, err = rules.normalize(m[name])
                assert.is_nil(err, name)
                assert.are.equal(kw[1], test.kind, name)
                assert.are.equal(kw[2], test.side, name)
                assert.are.equal(1, test.players, name)
                assert.is_false(test.destructive, name)
                assert.is_nil(test.ask, name)
            end
        end)

        it('takes expect from the package locale for every row that has one, and none for the others', function()
            local asked = {}
            local m = by_name(ST.definitions(function(key) asked[#asked + 1] = key; return 'T:' .. key end))
            for _, name in ipairs({ 'bar_style', 'compass_tape', 'voice_indicator', 'voice_radio', 'minimap_follows' }) do
                assert.are.equal('T:hudkit.selftest.' .. name .. '.expect', m[name].expect)
            end
            for _, name in ipairs({ 'values_mapping', 'compass_math', 'seatbelt_event' }) do
                assert.is_nil(m[name].expect, name)
            end
            assert.are.equal(5, #asked)
        end)

        it('has a locale string in en and th for every expect key, each within core limits', function()
            natives.stub('Locales', {})
            assert(loadfile(DIR .. '/locales/en.lua'))()
            assert(loadfile(DIR .. '/locales/th.lua'))()
            for _, lang in ipairs({ 'en', 'th' }) do
                local m = by_name(ST.definitions(function(key) return Locales[lang][key] end))
                for name, meta in pairs(m) do
                    if meta.expect ~= nil then
                        assert.is_string(meta.expect, lang .. ' ' .. name)
                        assert.is_true(utf8.len(meta.expect) <= 240, lang .. ' ' .. name)
                    end
                end
            end
        end)

        it('lets core skip the voice rows when pma-voice is not started, and nothing else', function()
            local m = by_name(ST.definitions())
            assert.are.same({ resources = { 'pma-voice' } }, m.voice_indicator.skipWhen)
            assert.are.same({ resources = { 'pma-voice' } }, m.voice_radio.skipWhen)
            for _, name in ipairs({ 'values_mapping', 'compass_math', 'bar_style', 'compass_tape', 'seatbelt_event',
                'minimap_follows' }) do
                assert.is_nil(m[name].skipWhen, name)
            end
        end)

        it('gives the ped tests that wait on the camera or a person enough time', function()
            local m = by_name(ST.definitions())
            assert.is_true(m.compass_tape.timeout >= 5000)
            assert.is_true(m.voice_indicator.timeout > ST.VOICE_WATCH_MS)
            assert.is_true(m.voice_radio.timeout > ST.VOICE_WATCH_MS)
        end)

        it('maps full names to short names only for its own prefix', function()
            assert.are.equal('compass_math', ST.shortName('aeterna_hudkit.compass_math'))
            assert.is_nil(ST.shortName('aeterna_notify.compass_math'))
            assert.is_nil(ST.shortName('aeterna_hudkit.unknown'))
            assert.is_nil(ST.shortName(nil))
        end)
    end)

    describe('skip reasons (only the listed ones)', function()
        it('skips compass_tape only when the compass is off', function()
            assert.is_nil(ST.skipReason('compass_tape', shipped_config(), {}))
            assert.are.equal('Config.compass.enabled = false',
                ST.skipReason('compass_tape', shipped_config({ compass = { enabled = false } }), {}))
        end)

        it('skips the voice rows when pma-voice is not started or voice is off', function()
            for _, name in ipairs({ 'voice_indicator', 'voice_radio' }) do
                assert.is_nil(ST.skipReason(name, shipped_config(), { voiceStarted = true }))
                assert.are.equal('needs pma-voice', ST.skipReason(name, shipped_config(), { voiceStarted = false }))
                assert.are.equal('Config.voice.enabled = false',
                    ST.skipReason(name, shipped_config({ voice = { enabled = false } }), { voiceStarted = true }))
            end
        end)

        it('skips seatbelt_event only when the seatbelt icon is off', function()
            assert.is_nil(ST.skipReason('seatbelt_event', shipped_config(), {}))
            assert.are.equal('Config.seatbelt.enabled = false',
                ST.skipReason('seatbelt_event', shipped_config({ seatbelt = { enabled = false } }), {}))
        end)

        it('never skips the rows whose skip-when is never or empty', function()
            local off = shipped_config({ compass = { enabled = false }, voice = { enabled = false },
                seatbelt = { enabled = false } })
            for _, name in ipairs({ 'values_mapping', 'compass_math', 'bar_style', 'minimap_follows' }) do
                assert.is_nil(ST.skipReason(name, off, { voiceStarted = false }), name)
            end
        end)
    end)

    describe('values_mapping', function()
        it('passes with the shipped HudLogic', function()
            local state, detail = ST.valuesMapping(HudLogic)
            assert.are.equal('pass', state)
            assert.is_string(detail)
        end)

        it('fails naming the first wrong value', function()
            local broken = setmetatable({ mapHealth = function() return 49 end }, { __index = HudLogic })
            local state, detail = ST.valuesMapping(broken)
            assert.are.equal('fail', state)
            assert.truthy(detail:find('mapHealth', 1, true))
        end)

        it('fails when a gear text is wrong', function()
            local broken = setmetatable({ gearText = function() return 'N' end }, { __index = HudLogic })
            local state, detail = ST.valuesMapping(broken)
            assert.are.equal('fail', state)
            assert.truthy(detail:find('gearText', 1, true))
        end)
    end)

    describe('compass_math', function()
        it('passes with the shipped CompassLogic', function()
            assert.are.equal('pass', (ST.compassMath(CompassLogic)))
        end)

        it('fails when the wrap at 360 is wrong', function()
            local broken = setmetatable({ offset = function(tick, heading, span)
                return ((tonumber(tick) or 0) - (tonumber(heading) or 0)) / span
            end }, { __index = CompassLogic })
            local state, detail = ST.compassMath(broken)
            assert.are.equal('fail', state)
            assert.truthy(detail:find('offset', 1, true))
        end)

        it('fails when the span is not clamped', function()
            local broken = setmetatable({ clampSpan = function(s) return tonumber(s) or 120 end },
                { __index = CompassLogic })
            assert.are.equal('fail', (ST.compassMath(broken)))
        end)
    end)

    describe('compass_tape samples', function()
        local function samples_for(camZs, lagAt)
            local out = {}
            for i, z in ipairs(camZs) do
                local sent = CompassLogic.fromCamRot(z)
                if i == lagAt then sent = (sent + 40) % 360 end
                out[i] = { camZ = z, sent = sent }
            end
            return out
        end

        it('lists the camera headings for a full circle that starts and ends facing north', function()
            local h = ST.compassHeadings()
            assert.are.equal(0, h[1])
            assert.are.equal(0, h[#h] % 360)
            assert.is_true(#h >= 9)
        end)

        it('passes when every sent degree follows the camera and N sits on the centre mark', function()
            local state, detail = ST.compassSamples(CompassLogic, samples_for(ST.compassHeadings()), 120)
            assert.are.equal('pass', state)
            assert.is_string(detail)
        end)

        it('fails at the step where the tape lags the camera', function()
            local state, detail, extra = ST.compassSamples(CompassLogic, samples_for(ST.compassHeadings(), 4), 120)
            assert.are.equal('fail', state)
            assert.are.equal(4, extra.step)
            assert.is_string(extra.expected)
            assert.truthy(detail:find('step 4', 1, true))
        end)

        it('fails when no degree was sent (element hidden or thread not running)', function()
            local s = samples_for(ST.compassHeadings())
            s[1].sent = nil
            local state, _, extra = ST.compassSamples(CompassLogic, s, 120)
            assert.are.equal('fail', state)
            assert.are.equal(1, extra.step)
        end)

        it('fails when there is no sample facing north', function()
            local state, detail = ST.compassSamples(CompassLogic, samples_for({ 90, 180 }), 120)
            assert.are.equal('fail', state)
            assert.truthy(detail:find('north', 1, true))
        end)
    end)

    describe('voice watch', function()
        local function msg(t)
            return { available = t.available ~= false, talking = t.talking == true, mode = t.mode,
                radio = t.radio == true, radioActive = t.radioActive == true }
        end

        it('indicator passes once talking was seen and the mode label changed', function()
            local w = ST.newVoiceWatch('voice_indicator')
            assert.is_false(w.observe(msg({ mode = 'Normal' })))
            assert.is_false(w.observe(msg({ talking = true, mode = 'Normal' })))
            assert.is_true(w.observe(msg({ mode = 'Shout' })))
            assert.are.equal('pass', (w.verdict()))
        end)

        it('indicator fails naming what was not seen', function()
            local w = ST.newVoiceWatch('voice_indicator')
            w.observe(msg({ mode = 'Normal' }))
            local state, detail = w.verdict()
            assert.are.equal('fail', state)
            assert.truthy(detail:find('talking', 1, true))
            assert.truthy(detail:find('mode', 1, true))
        end)

        it('radio passes once the radio icon showed and was highlighted', function()
            local w = ST.newVoiceWatch('voice_radio')
            assert.is_false(w.observe(msg({ radio = true })))
            assert.is_true(w.observe(msg({ radio = true, radioActive = true })))
            assert.are.equal('pass', (w.verdict()))
        end)

        it('radio fails when the presser never transmitted', function()
            local w = ST.newVoiceWatch('voice_radio')
            w.observe(msg({ radio = true }))
            local state, detail = w.verdict()
            assert.are.equal('fail', state)
            assert.truthy(detail:find('transmit', 1, true))
        end)

        it('fails when the voice element never became available', function()
            local w = ST.newVoiceWatch('voice_indicator')
            w.observe(nil)
            w.observe(msg({ available = false }))
            local state, detail = w.verdict()
            assert.are.equal('fail', state)
            assert.truthy(detail:find('not shown', 1, true))
        end)
    end)

    describe('seatbelt_event', function()
        it('fires true, false, nil in that order', function()
            local steps = ST.seatbeltSteps()
            assert.are.equal(3, #steps)
            assert.are.same({ on = true }, steps[1].payload)
            assert.is_true(steps[1].expect)
            assert.are.same({ on = false }, steps[2].payload)
            assert.is_false(steps[2].expect)
            assert.is_nil(steps[3].payload)
            assert.is_nil(steps[3].expect)
        end)

        it('reports mock with restored only when every step matched and the state is back', function()
            local state, _, extra = ST.seatbeltVerdict({ true, false, nil, n = 3 }, true)
            assert.are.equal('mock', state)
            assert.is_true(extra.restored)
        end)

        it('fails at the first step whose icon state is wrong', function()
            local state, detail, extra = ST.seatbeltVerdict({ true, true, nil, n = 3 }, true)
            assert.are.equal('fail', state)
            assert.are.equal(2, extra.step)
            assert.are.equal('false', extra.expected)
            assert.truthy(detail:find('step 2', 1, true))
            assert.is_true(extra.restored)
        end)

        it('never claims restored when the state did not come back', function()
            local state, _, extra = ST.seatbeltVerdict({ true, false, nil, n = 3 }, false)
            assert.are.equal('fail', state)
            assert.is_false(extra.restored)
        end)

        it('SeatbeltLogic snapshot and restore put another owner back', function()
            local S = SeatbeltLogic.create({})
            S.set('other_res', { on = true })
            local snap = S.snapshot()
            S.set('aeterna_hudkit', { on = false })
            S.set('aeterna_hudkit', nil)
            assert.is_nil(S.display(true))
            S.restore(snap)
            assert.is_true(S.display(true))
            assert.are.equal('other_res', S.owner())
            assert.is_true(S.same(snap))
        end)
    end)

    describe('minimap_follows', function()
        local metrics = {
            p0 = { x = 0.0150, y = 0.9850 }, p1 = { x = 0.5775, y = 1.9850 },
            pxW = 162, pxH = 204, screenW = 1920, screenH = 1080,
        }
        metrics.defaultSx, metrics.defaultSy = MinimapLogic.offsetToScreen(
            MinimapLogic.DEFAULT_COMPONENTS.minimap.x, MinimapLogic.DEFAULT_COMPONENTS.minimap.y, metrics.p0, metrics.p1)

        -- What client/main.lua applyMinimapPlace sends to SetMinimapComponentPosition for a place.
        local function applied_for(place)
            local scale = MinimapLogic.clampScale(place.scale)
            local leftPx = place.x * metrics.screenW - place.ax * metrics.pxW * scale
            local bottomPx = place.y * metrics.screenH - place.ay * metrics.pxH * scale + metrics.pxH * scale
            local dOx = (leftPx / metrics.screenW - metrics.defaultSx) / (metrics.p1.x - metrics.p0.x)
            local dOy = (bottomPx / metrics.screenH - metrics.defaultSy) / (metrics.p1.y - metrics.p0.y)
            return MinimapLogic.computePositions(dOx, dOy, scale)
        end

        it('has a top-right place and returns to the place it started from', function()
            local places = ST.minimapPlaces({ x = 0.1, y = 0.9, ax = 0, ay = 1, scale = 1 })
            assert.are.equal(2, #places)
            assert.is_true(places[1].x > 0.5 and places[1].y < 0.5)
            assert.are.same({ x = 0.1, y = 0.9, ax = 0, ay = 1, scale = 1 }, places[2])
        end)

        it('passes when the radar sits under the stand-in rectangle', function()
            local place = ST.minimapPlaces(nil)[1]
            local state = ST.minimapCheck(MinimapLogic, metrics, place, applied_for(place))
            assert.are.equal('pass', state)
        end)

        it('passes for the default place too', function()
            local place = { x = metrics.defaultSx, y = metrics.defaultSy, ax = 0, ay = 1, scale = 1 }
            assert.are.equal('pass', (ST.minimapCheck(MinimapLogic, metrics, place, applied_for(place))))
        end)

        it('fails when the radar is left behind', function()
            local place = ST.minimapPlaces(nil)[1]
            local stale = applied_for({ x = metrics.defaultSx, y = metrics.defaultSy, ax = 0, ay = 1, scale = 1 })
            local state, detail = ST.minimapCheck(MinimapLogic, metrics, place, stale)
            assert.are.equal('fail', state)
            assert.truthy(detail:find('radar', 1, true))
        end)

        it('fails when the mask no longer moves with the radar', function()
            local place = ST.minimapPlaces(nil)[1]
            local applied = applied_for(place)
            applied.minimap_mask.x = applied.minimap_mask.x + 0.05
            local state, detail = ST.minimapCheck(MinimapLogic, metrics, place, applied)
            assert.are.equal('fail', state)
            assert.truthy(detail:find('minimap_mask', 1, true))
        end)

        it('fails when nothing was applied', function()
            assert.are.equal('fail', (ST.minimapCheck(MinimapLogic, metrics, ST.minimapPlaces(nil)[1], nil)))
        end)
    end)

    describe('server wrapper', function()
        it('registers the eight rows with aeterna_core on start and answers its own headless tests', function()
            natives.reset({ side = 'server', resource = 'aeterna_hudkit' })
            local added, reports = {}, {}
            natives.stub_export('aeterna_core', 'addSelftest', function(name, meta)
                added[#added + 1] = { name = name, meta = meta }
                return true
            end)
            natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail, extra)
                reports[#reports + 1] = { runId = runId, name = name, ok = ok, detail = detail, extra = extra }
                return true
            end)
            natives.stub_export('aeterna_uikit', 'addMenuEntry', function() return true end)
            resource.load_resource(DIR, 'server')
            natives.advance(0)

            assert.are.equal(8, #added)
            assert.are.equal('values_mapping', added[1].name)
            assert.are.equal('minimap_follows', added[8].name)

            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_hudkit.values_mapping', { kind = 'headless' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_hudkit.compass_math', { kind = 'headless' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_notify.values_mapping', { kind = 'headless' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_hudkit.bar_style', { kind = 'eye' })
            natives.advance(0)

            assert.are.equal(2, #reports)
            assert.are.equal('aeterna_hudkit.values_mapping', reports[1].name)
            assert.are.equal('pass', reports[1].ok)
            assert.are.equal('aeterna_hudkit.compass_math', reports[2].name)
            assert.are.equal('pass', reports[2].ok)
        end)
    end)

    describe('client wrapper', function()
        local function load_client(opts)
            opts = opts or {}
            natives.reset({ side = 'client', resource = 'aeterna_hudkit', invoker = 'aeterna_hudkit' })
            natives.spy('RegisterCommand')
            natives.spy('RegisterKeyMapping')
            natives.spy('RegisterNUICallback')
            local ui = natives.spy('SendNUIMessage')
            natives.stub('GetResourceState', function(name)
                if name == 'pma-voice' then return 'missing' end
                return 'started'
            end)
            natives.stub('AddStateBagChangeHandler', function() return 1 end)
            natives.stub('GetPlayerServerId', function() return 7 end)
            natives.stub('LocalPlayer', { state = {} })
            natives.stub('IsPedInAnyVehicle', function() return false end)
            local reports = {}
            natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail, extra)
                reports[#reports + 1] = { runId = runId, name = name, ok = ok, detail = detail, extra = extra }
                return true
            end)
            local loadOpts = {}
            if opts.config then
                natives.stub('Config', opts.config)
                loadOpts.skip = { ['config.lua'] = true }
            end
            resource.load_resource(DIR, 'client', loadOpts)
            natives.advance(0)
            return { reports = reports, ui = ui }
        end

        it('seatbelt_event reports mock with restored and leaves the icon as it found it', function()
            local ctx = load_client()
            natives.fire('aeterna_core:selftest', 'r2-abcd', 'aeterna_hudkit.seatbelt_event',
                { kind = 'mock', side = 'client', role = 'A' })
            natives.advance(2000)
            assert.are.equal(1, #ctx.reports)
            assert.are.equal('mock', ctx.reports[1].ok)
            assert.is_true(ctx.reports[1].extra.restored)
            local last
            for _, call in ipairs(ctx.ui) do
                if type(call[1]) == 'table' and call[1].type == 'hud:seatbelt' then last = call[1] end
            end
            assert.is_nil(last.state)
        end)

        it('seatbelt_event reports skip with the config reason when the icon is off', function()
            local ctx = load_client({ config = shipped_config({ seatbelt = { enabled = false } }) })
            natives.fire('aeterna_core:selftest', 'r3-abcd', 'aeterna_hudkit.seatbelt_event',
                { kind = 'mock', side = 'client', role = 'A' })
            natives.advance(2000)
            assert.are.equal(1, #ctx.reports)
            assert.are.equal('skip', ctx.reports[1].ok)
            assert.are.equal('Config.seatbelt.enabled = false', ctx.reports[1].detail)
        end)

        it('voice rows report skip when pma-voice is not started on this client', function()
            local ctx = load_client()
            natives.fire('aeterna_core:selftest', 'r4-abcd', 'aeterna_hudkit.voice_radio',
                { kind = 'ped', side = 'client', role = 'A' })
            natives.advance(100)
            assert.are.equal(1, #ctx.reports)
            assert.are.equal('skip', ctx.reports[1].ok)
            assert.are.equal('needs pma-voice', ctx.reports[1].detail)
        end)

        it('bar_style shows the ring, reports ready, and puts the player style back on selftestEnd', function()
            local ctx = load_client()
            natives.fire('aeterna_core:selftest', 'r5-abcd', 'aeterna_hudkit.bar_style',
                { kind = 'eye', side = 'client', role = 'A' })
            natives.advance(2000)
            assert.are.equal(1, #ctx.reports)
            assert.are.equal('ready', ctx.reports[1].ok)
            local styles = {}
            for _, call in ipairs(ctx.ui) do
                local m = call[1]
                if type(m) == 'table' and m.type == 'settings:apply' then styles[#styles + 1] = m.settings.barStyle end
            end
            assert.are.equal('ring', styles[#styles])
            natives.fire('aeterna_core:selftestEnd', 'r5-abcd', 'aeterna_hudkit.bar_style')
            natives.advance(0)
            styles = {}
            for _, call in ipairs(ctx.ui) do
                local m = call[1]
                if type(m) == 'table' and m.type == 'settings:apply' then styles[#styles + 1] = m.settings.barStyle end
            end
            assert.are.equal('bar', styles[#styles])
        end)

        it('ignores tests of other resources', function()
            local ctx = load_client()
            natives.fire('aeterna_core:selftest', 'r6-abcd', 'aeterna_radial.seatbelt_event',
                { kind = 'mock', side = 'client', role = 'A' })
            natives.advance(2000)
            assert.are.equal(0, #ctx.reports)
        end)
    end)
end)
