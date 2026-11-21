-- spec/loading_spec.lua -- busted tests for aeterna_loading (pure logic in shared/logic/loading.lua).
-- The page runs the same rules from html/logic.js; spec/logic.test.js runs these cases against it.

local natives = require('helpers.natives')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load_logic()
    return assert(loadfile(DIR .. '/shared/logic/loading.lua'))()
end

local function fields(errors)
    local out = {}
    for i = 1, #errors do out[#out + 1] = errors[i].field end
    table.sort(out)
    return out
end

local function run(L, msgs)
    local s = L.newState()
    for i = 1, #msgs do s = L.reduce(s, msgs[i]) end
    return s
end

describe('aeterna_loading', function()
    local L
    before_each(function()
        natives.reset({ resource = 'aeterna_loading', side = 'server' })
        L = load_logic()
    end)

    describe('1. Config validation', function()
        it('accepts the shipped defaults with no errors', function()
            local cfg, errors = L.validateConfig(L.defaults())
            assert.are.same({}, errors)
            assert.are.same(L.defaults(), cfg)
        end)

        it('replaces a config that is not a table with the defaults and one error', function()
            local cfg, errors = L.validateConfig('nope')
            assert.are.same({ 'config' }, fields(errors))
            assert.are.same(L.defaults(), cfg)
        end)

        it('uses the default for a missing field without an error', function()
            local cfg, errors = L.validateConfig({ serverName = 'Harbour' })
            assert.are.same({}, errors)
            assert.are.equal('Harbour', cfg.serverName)
            assert.are.equal(8, cfg.tipSeconds)
            assert.are.equal(0.3, cfg.audio.volume)
        end)

        local cases = {
            { 'serverName', { serverName = string.rep('a', 41) } },
            { 'serverName', { serverName = '' } },
            { 'serverName', { serverName = 12 } },
            { 'tagline', { tagline = string.rep('a', 81) } },
            { 'lang', { lang = 'de' } },
            { 'preset', { preset = 'neon' } },
            { 'background', { background = 'custom/bg.gif' } },
            { 'background', { background = 'custom/' .. string.rep('a', 120) .. '.jpg' } },
            { 'tips', { tips = 'one tip' } },
            { 'tips', { tips = { string.rep('a', 161) } } },
            { 'tips', { tips = { 'ok', 5 } } },
            { 'tipSeconds', { tipSeconds = 3 } },
            { 'tipSeconds', { tipSeconds = 31 } },
            { 'tipSeconds', { tipSeconds = '8' } },
            { 'audio.src', { audio = { src = 'custom/a.wav' } } },
            { 'audio.autoplay', { audio = { autoplay = 'yes' } } },
            { 'audio.volume', { audio = { volume = 1.5 } } },
            { 'audio.volume', { audio = { volume = -0.1 } } },
            { 'shutdown.fallbackSeconds', { shutdown = { fallbackSeconds = 9 } } },
            { 'shutdown.fallbackSeconds', { shutdown = { fallbackSeconds = 121 } } },
        }
        for _, case in ipairs(cases) do
            it(('fails only %s and falls back to its default (%s)'):format(case[1], next(case[2])), function()
                local raw = L.defaults()
                raw.serverName = 'Harbour'
                for k, v in pairs(case[2]) do
                    if type(v) == 'table' and type(raw[k]) == 'table' and k ~= 'tips' then
                        for k2, v2 in pairs(v) do raw[k][k2] = v2 end
                    else
                        raw[k] = v
                    end
                end
                local cfg, errors = L.validateConfig(raw)
                assert.are.same({ case[1] }, fields(errors))
                local expected = L.defaults()
                if case[1] ~= 'serverName' then expected.serverName = 'Harbour' end
                assert.are.same(expected, cfg)
            end)
        end

        it('accepts the edges of every limit', function()
            local th40 = string.rep('ก', 40) -- 120 bytes, 40 characters
            local cfg, errors = L.validateConfig({
                serverName = th40,
                tagline = string.rep('ข', 80),
                lang = 'th',
                preset = 'night-market',
                background = 'custom/bg.webp',
                tips = (function() local t = {} for i = 1, 30 do t[i] = string.rep('ค', 160) end return t end)(),
                tipSeconds = 30,
                audio = { src = 'custom/theme.ogg', autoplay = true, volume = 1 },
                shutdown = { fallbackSeconds = 120 },
            })
            assert.are.same({}, errors)
            assert.are.equal(th40, cfg.serverName)
            assert.are.equal(30, #cfg.tips)
            assert.is_true(cfg.audio.autoplay)
        end)

        it('refuses 31 tips', function()
            local t = {}
            for i = 1, 31 do t[i] = 'tip' end
            local _, errors = L.validateConfig({ tips = t })
            assert.are.same({ 'tips' }, fields(errors))
        end)

        it('accepts an empty tip list and an empty tagline', function()
            local cfg, errors = L.validateConfig({ tips = {}, tagline = '' })
            assert.are.same({}, errors)
            assert.are.same({}, cfg.tips)
        end)

        it('treats an empty JSON object for tips as an empty list, and refuses a non-empty object', function()
            -- Lua JSON decoders cannot tell {} from []; the JS twin applies the same rule.
            local cfg, errors = L.validateConfig(json.decode('{"tips":{}}'))
            assert.are.same({}, errors)
            assert.are.same({}, cfg.tips)
            local _, errors2 = L.validateConfig(json.decode('{"tips":{"a":"tip"}}'))
            assert.are.same({ 'tips' }, fields(errors2))
        end)

        it('refuses paths outside the resource or with a wrong extension', function()
            local bad = { '/x.jpg', '/custom/bg.jpg', '../bg.jpg', 'custom/../../bg.jpg', 'http://example.com/bg.jpg',
                'http:bg.jpg', '//example.com/bg.jpg', 'custom//bg.jpg', 'custom/bg.png.exe', 'custom/bg', 'nui:x.png' }
            for _, p in ipairs(bad) do
                assert.is_false(L.isLocalPath(p, L.IMAGE_EXT), p)
                local _, errors = L.validateConfig({ background = p })
                assert.are.same({ 'background' }, fields(errors), p)
            end
            assert.is_true(L.isLocalPath('custom/bg.jpg', L.IMAGE_EXT))
            assert.is_true(L.isLocalPath('custom/bg.png', L.IMAGE_EXT))
            assert.is_true(L.isLocalPath('custom/theme.mp3', L.AUDIO_EXT))
            assert.is_false(L.isLocalPath('custom/theme.mp3', L.IMAGE_EXT))
            assert.is_false(L.isLocalPath('custom/bg.jpg', L.AUDIO_EXT))
        end)

        it('reports several bad fields at once, each falling back on its own', function()
            local cfg, errors = L.validateConfig({ lang = 'xx', tipSeconds = 100, serverName = 'Harbour' })
            assert.are.same({ 'lang', 'tipSeconds' }, fields(errors))
            assert.are.equal('Harbour', cfg.serverName)
            assert.are.equal('en', cfg.lang)
            assert.are.equal(8, cfg.tipSeconds)
        end)
    end)

    describe('2. Stage reducer', function()
        it('starts with no stage', function()
            local s = L.newState()
            assert.are.equal(0, s.stage)
            assert.is_nil(s.percent)
        end)

        it('goes Map -> Scripts -> Character in order with real percentages', function()
            local s = L.newState()
            s = L.reduce(s, { eventName = 'startDataFileEntries', count = 4 })
            assert.are.equal(L.STAGE.MAP, s.stage)
            assert.are.equal(0, s.percent)
            s = L.reduce(s, { eventName = 'onDataFileEntry', name = 'a', type = 1, isNew = true })
            assert.are.equal(25, s.percent)
            s = L.reduce(s, { eventName = 'onDataFileEntry', name = 'b' })
            s = L.reduce(s, { eventName = 'onDataFileEntry', name = 'c' })
            assert.are.equal(75, s.percent)
            s = L.reduce(s, { eventName = 'startInitFunctionOrder', type = 'INIT_SESSION', order = 1, count = 10 })
            assert.are.equal(L.STAGE.SCRIPTS, s.stage)
            assert.are.equal(0, s.percent)
            s = L.reduce(s, { eventName = 'initFunctionInvoking', type = 'INIT_SESSION', name = 'x', idx = 5 })
            assert.are.equal(50, s.percent)
            s = L.reduce(s, { type = 'aeterna_loading:stage', stage = 'character' })
            assert.are.equal(L.STAGE.CHARACTER, s.stage)
            assert.is_nil(s.percent)
        end)

        it('sums init function orders into one percentage', function()
            local s = run(L, {
                { eventName = 'startInitFunctionOrder', type = 'INIT_SESSION', order = 1, count = 4 },
                { eventName = 'initFunctionInvoking', idx = 3 },
                { eventName = 'startInitFunctionOrder', type = 'INIT_SESSION', order = 2, count = 4 },
                { eventName = 'initFunctionInvoking', idx = 3 },
            })
            -- (4 + 3) of (4 + 4) = 87.5 -> 87
            assert.are.equal(87, s.percent)
        end)

        it('ignores unknown and malformed messages', function()
            local s = run(L, {
                { eventName = 'startDataFileEntries', count = 2 },
                { eventName = 'onDataFileEntry' },
            })
            local before = s.percent
            for _, msg in ipairs({ { eventName = 'somethingNew' }, { type = 'other:stage', stage = 'character' },
                { type = 'aeterna_loading:stage', stage = 'unknown' }, {}, 'text', 42, false,
                { eventName = 'startDataFileEntries', count = 'many' }, { eventName = 'initFunctionInvoking', idx = 1 } }) do
                s = L.reduce(s, msg)
            end
            assert.are.equal(L.STAGE.MAP, s.stage)
            assert.are.equal(before, s.percent)
        end)

        it('never goes back to an earlier stage', function()
            local s = run(L, {
                { eventName = 'startInitFunctionOrder', type = 'INIT_SESSION', order = 1, count = 2 },
                { eventName = 'startDataFileEntries', count = 4 },
                { eventName = 'onDataFileEntry' },
            })
            assert.are.equal(L.STAGE.SCRIPTS, s.stage)
            assert.are.equal(0, s.percent)
            s = L.reduce(s, { type = 'aeterna_loading:stage', stage = 'character' })
            s = L.reduce(s, { eventName = 'startInitFunctionOrder', type = 'INIT_SESSION', order = 2, count = 3 })
            assert.are.equal(L.STAGE.CHARACTER, s.stage)
            assert.is_nil(s.percent)
        end)

        it('never lowers a percentage when a later order grows the total', function()
            local s = run(L, {
                { eventName = 'startInitFunctionOrder', type = 'INIT_SESSION', order = 1, count = 2 },
                { eventName = 'initFunctionInvoking', idx = 2 },
            })
            assert.are.equal(100, s.percent)
            s = L.reduce(s, { eventName = 'startInitFunctionOrder', type = 'INIT_SESSION', order = 2, count = 8 })
            assert.are.equal(100, s.percent)
            s = L.reduce(s, { eventName = 'initFunctionInvoking', idx = 1 })
            assert.are.equal(100, s.percent)
        end)

        it('never lowers the map percentage when more entries arrive', function()
            local s = run(L, {
                { eventName = 'startDataFileEntries', count = 2 },
                { eventName = 'onDataFileEntry' },
                { eventName = 'startDataFileEntries', count = 6 },
            })
            assert.are.equal(50, s.percent)
        end)

        it('uses loadFraction for Scripts when it is higher', function()
            local s = run(L, {
                { eventName = 'startInitFunctionOrder', type = 'INIT_SESSION', order = 1, count = 10 },
                { eventName = 'initFunctionInvoking', idx = 2 },
            })
            assert.are.equal(20, s.percent)
            s = L.reduce(s, { eventName = 'loadProgress', loadFraction = 0.64 })
            assert.are.equal(64, s.percent)
            s = L.reduce(s, { eventName = 'loadProgress', loadFraction = 0.3 })
            assert.are.equal(64, s.percent)
            s = L.reduce(s, { eventName = 'initFunctionInvoking', idx = 9 })
            assert.are.equal(90, s.percent)
            s = L.reduce(s, { eventName = 'loadProgress', loadFraction = 7 })
            assert.are.equal(100, s.percent)
        end)

        it('does not use loadFraction for the Map stage', function()
            local s = run(L, {
                { eventName = 'startDataFileEntries', count = 10 },
                { eventName = 'loadProgress', loadFraction = 0.9 },
            })
            assert.are.equal(0, s.percent)
        end)

        it('marks closing on the closing message without changing the stage', function()
            local s = run(L, {
                { eventName = 'startDataFileEntries', count = 1 },
                { type = 'aeterna_loading:closing' },
            })
            assert.is_true(s.closing)
            assert.are.equal(L.STAGE.MAP, s.stage)
        end)

        it('does not change the state it was given', function()
            local s = L.newState()
            local s2 = L.reduce(s, { eventName = 'startDataFileEntries', count = 3 })
            assert.are.equal(0, s.stage)
            assert.are.equal(1, s2.stage)
        end)

        it('says "still loading" after 20 s without a message', function()
            assert.is_false(L.isStill(1000, 20999))
            assert.is_true(L.isStill(1000, 21000))
        end)
    end)

    describe('3. Tip rotation', function()
        it('rotates the tips in order and wraps around', function()
            local tips = { 'a', 'b', 'c' }
            assert.are.equal(1, L.tipAt(tips, 8, 0))
            assert.are.equal(1, L.tipAt(tips, 8, 7999))
            assert.are.equal(2, L.tipAt(tips, 8, 8000))
            assert.are.equal(3, L.tipAt(tips, 8, 16000))
            assert.are.equal(1, L.tipAt(tips, 8, 24000))
        end)

        it('clamps tipSeconds to 4-30', function()
            assert.are.equal(4, L.clampTipSeconds(1))
            assert.are.equal(30, L.clampTipSeconds(99))
            assert.are.equal(12, L.clampTipSeconds(12))
            assert.are.equal(8, L.clampTipSeconds('x'))
            local tips = { 'a', 'b' }
            assert.are.equal(2, L.tipAt(tips, 1, 4000))
            assert.are.equal(1, L.tipAt(tips, 99, 29999))
        end)

        it('hides the tip line for an empty list', function()
            assert.is_nil(L.tipAt({}, 8, 0))
            assert.is_nil(L.tipAt(nil, 8, 0))
        end)
    end)

    describe('Shutdown fallback', function()
        it('is due fallbackSeconds after the session started, never before it started', function()
            assert.is_false(L.fallbackDue(nil, 100000, 30))
            assert.is_false(L.fallbackDue(1000, 30999, 30))
            assert.is_true(L.fallbackDue(1000, 31000, 30))
        end)

        it('closeDue: counts from the session start, or from the resource start while the session has not started', function()
            -- resource started at 1000, session never started: hard cap at 1000 + 30 s
            assert.is_false(L.closeDue(1000, nil, 30999, 30))
            assert.is_true(L.closeDue(1000, nil, 31000, 30))
            -- session started at 20000: due at 50000, not at the resource-start cap
            assert.is_false(L.closeDue(1000, 20000, 49999, 30))
            assert.is_true(L.closeDue(1000, 20000, 50000, 30))
        end)
    end)

    describe('Client script (client/main.lua)', function()
        local shutdowns, nuiShutdowns, messages, active, sessionStarted

        local function start_client(opts)
            opts = opts or {}
            natives.reset({ resource = 'aeterna_loading', side = 'client' })
            active, sessionStarted = true, false
            if not opts.noLogic then load_logic() else LoadingLogic = nil end
            natives.track_global('LoadingLogic')
            natives.stub('LoadResourceFile', function(_, path)
                assert.are.equal('html/config.json', path)
                if opts.configError then error('read failed') end
                return opts.config or '{"shutdown":{"fallbackSeconds":30}}'
            end)
            natives.stub('NetworkIsSessionStarted', function() return sessionStarted end)
            natives.stub('GetIsLoadingScreenActive', function() return active end)
            shutdowns = natives.spy('ShutdownLoadingScreen')
            nuiShutdowns = natives.spy('ShutdownLoadingScreenNui', function() active = false end)
            messages = natives.spy('SendLoadingScreenMessage')
            assert(loadfile(DIR .. '/client/main.lua'))()
        end

        local function closed() return #nuiShutdowns == 1 and #shutdowns == 1 end

        it('closes the page on playerSpawned once the session started', function()
            start_client()
            sessionStarted = true
            natives.advance(500)
            assert.are.equal(1, #messages)
            assert.truthy(messages[1][1]:find('character', 1, true))
            natives.fire('playerSpawned')
            natives.advance(1500)
            assert.is_true(closed())
        end)

        it('closes fallbackSeconds after the session started', function()
            start_client()
            natives.advance(20000)
            sessionStarted = true
            natives.advance(28000) -- session at 20 s, now 48 s: not yet
            assert.are.equal(0, #nuiShutdowns)
            natives.advance(4000)
            assert.is_true(closed())
        end)

        it('closes anyway when the session never starts (hard cap from resource start)', function()
            start_client()
            natives.advance(29000)
            assert.are.equal(0, #nuiShutdowns)
            natives.advance(3000)
            assert.is_true(closed())
        end)

        it('still closes when LoadingLogic is missing', function()
            start_client({ noLogic = true })
            natives.advance(32000)
            assert.is_true(closed())
        end)

        it('still closes when the config cannot be read or decoded', function()
            start_client({ configError = true })
            natives.advance(32000)
            assert.is_true(closed())
            start_client({ config = 'not json' })
            natives.advance(32000)
            assert.is_true(closed())
        end)

        it('does not shut down a loading screen that something else already closed', function()
            start_client()
            sessionStarted = true
            natives.advance(500)
            active = false
            natives.fire('playerSpawned')
            natives.advance(2000)
            assert.are.equal(0, #shutdowns)
            assert.are.equal(0, #nuiShutdowns)
        end)
    end)
end)
