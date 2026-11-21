-- selftest_spec.lua -- aeterna_testkit's own self-tests (docs/specs/aeterna_testkit.md "Self-tests"): the six rows,
-- their pass rules (shared/logic/selftest.lua) and the server and client handlers under the harness.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local DIR = (debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.') .. '/..'

local function loadLogic(name)
    return assert(loadfile(DIR .. '/shared/logic/' .. name .. '.lua'))()
end

local function coreText()
    return assert(loadfile(DIR .. '/../core/shared/logic/text.lua'))()
end

local function readFile(path)
    local f = assert(io.open(path, 'rb'))
    local body = f:read('*a')
    f:close()
    return body
end

-- A small JSON decoder for these cases (CI's busted has no JSON library). null decodes to nil, as in FiveM.
local function decodeJson(s)
    local pos = 1
    local value
    local function ws() pos = s:find('[^%s]', pos) or #s + 1 end
    local function str()
        local out = {}
        pos = pos + 1
        while true do
            local c = s:sub(pos, pos)
            if c == '"' then pos = pos + 1 return table.concat(out) end
            if c == '\\' then
                local e = s:sub(pos + 1, pos + 1)
                if e == 'u' then
                    out[#out + 1] = utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16))
                    pos = pos + 6
                else
                    out[#out + 1] = ({ n = '\n', t = '\t', r = '\r', b = '\b', f = '\f' })[e] or e
                    pos = pos + 2
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
    end
    function value()
        ws()
        local c = s:sub(pos, pos)
        if c == '{' then
            local t = {}
            pos = pos + 1
            ws()
            if s:sub(pos, pos) == '}' then pos = pos + 1 return t end
            while true do
                ws()
                local k = str()
                ws()
                pos = pos + 1 -- ':'
                t[k] = value()
                ws()
                local sep = s:sub(pos, pos)
                pos = pos + 1
                if sep == '}' then return t end
            end
        elseif c == '[' then
            local t, i = {}, 0
            pos = pos + 1
            ws()
            if s:sub(pos, pos) == ']' then pos = pos + 1 return t end
            while true do
                i = i + 1
                t[i] = value()
                ws()
                local sep = s:sub(pos, pos)
                pos = pos + 1
                if sep == ']' then return t end
            end
        elseif c == '"' then
            return str()
        elseif s:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false
        elseif s:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil
        end
        local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
        pos = pos + #num
        return math.tointeger(tonumber(num)) or tonumber(num)
    end
    return value()
end

local OWNER = 'aeterna_testkit'
local FOOTER = 'No player names, identifiers, IPs, convar values or paths.'

describe('aeterna_testkit self-tests', function()
    local S, Report, Scrub
    before_each(function()
        natives.reset()
        Scrub = loadLogic('scrub')
        Report = loadLogic('report')
        S = loadLogic('selftest')
    end)

    describe('rows', function()
        it('are exactly the six rows of the spec table, in order', function()
            local rows = S.rows(OWNER, function(k) return '<' .. k .. '>' end)
            local got = {}
            for i, r in ipairs(rows) do got[i] = { r.name, r.meta } end
            assert.are.same({
                { 'aeterna_testkit.scrub', { kind = 'headless', players = 1, destructive = false } },
                { 'aeterna_testkit.report_schema', { kind = 'headless', players = 1, destructive = false } },
                { 'aeterna_testkit.save', { kind = 'headless', players = 1, destructive = false } },
                { 'aeterna_testkit.env', { kind = 'headless', side = 'client', players = 1, destructive = false } },
                { 'aeterna_testkit.eye_card', { kind = 'eye', players = 1, destructive = false,
                    expect = '<testkit.selftest.expect.card>' } },
                { 'aeterna_testkit.eye_card_b', { kind = 'eye', players = 2, destructive = false,
                    expect = '<testkit.selftest.expect.card_b>' } },
            }, got)
        end)

        it('have both expect lines in Thai and English, within 240 characters', function()
            assert(loadfile(DIR .. '/locales/en.lua'))()
            assert(loadfile(DIR .. '/locales/th.lua'))()
            for _, lang in ipairs({ 'en', 'th' }) do
                for _, k in ipairs({ 'testkit.selftest.expect.card', 'testkit.selftest.expect.card_b' }) do
                    local s = Locales[lang][k]
                    assert.is_string(s, lang .. ' ' .. k)
                    assert.is_true(utf8.len(s) >= 1 and utf8.len(s) <= 240)
                end
            end
        end)
    end)

    describe('checks', function()
        it('scrub turns the sample detail into A, [id], [ip], [path]', function()
            assert.are.same({ true, 'player A lost [id] at [ip] [path]' }, { S.scrub(Scrub, coreText().clean) })
            local ok, detail = S.scrub({ scrub = function() return 'player Somchai' end }, coreText().clean)
            assert.is_false(ok)
            assert.are.equal('scrub gave: player Somchai', detail)
        end)

        it('report_schema accepts the built sample and refuses a missing or extra key', function()
            local schema = decodeJson(readFile(DIR .. '/schema/report-1.schema.json'))
            assert.are.same({ true, 'JSON keys match the schema; Markdown ends with the footer' },
                { S.reportSchema(Report, schema, decodeJson, FOOTER) })

            local broken = setmetatable({}, { __index = Report })
            broken.encode = function(r) return Report.encode(r):gsub('"cancelled":false,', '') end
            local ok, detail = S.reportSchema(broken, schema, decodeJson, FOOTER)
            assert.is_false(ok)
            assert.are.equal('missing key: cancelled', detail)

            broken.encode = function(r) return Report.encode(r):gsub('^{', '{"extra":1,') end
            ok, detail = S.reportSchema(broken, schema, decodeJson, FOOTER)
            assert.is_false(ok)
            assert.are.equal('unknown key: extra', detail)

            broken.encode = Report.encode
            broken.markdown = function(r) return Report.markdown(r, FOOTER) .. '\nmore' end
            ok, detail = S.reportSchema(broken, schema, decodeJson, FOOTER)
            assert.is_false(ok)
            assert.are.equal('Markdown does not end with the footer', detail)
        end)

        it('save reads both report files back: a report JSON line and the Markdown header', function()
            local built = Report.build(S.sampleInput())
            local json1, md1 = Report.encode(built), Report.markdown(built, FOOTER)
            assert.are.same({ true, 'both report files read back' }, { S.save(json1, md1, decodeJson) })
            assert.are.same({ false, 'reports/latest.json: not a report' }, { S.save('{"x":1}', md1, decodeJson) })
            assert.are.same({ false, 'reports/latest.json: not a report' }, { S.save('{oops', md1, decodeJson) })
            assert.are.same({ false, 'reports/latest.md: not a report' }, { S.save(json1, 'hello', decodeJson) })
        end)

        it('env checks the askEnv reply against the sv:env schema', function()
            local V = assert(loadfile(DIR .. '/../core/shared/logic/validate.lua'))().validate
            assert.are.same({ true, 'game build 3258 · 1920x1080' },
                { S.env(V, { gameBuild = 3258, w = 1920, h = 1080 }) })
            assert.is_false((S.env(V, { gameBuild = 0, w = 1920, h = 1080 })))
            assert.is_false((S.env(V, { gameBuild = 3258, w = 100, h = 1080 })))
            assert.is_false((S.env(V, { gameBuild = 3258, w = 1920, h = 9000 })))
            local ok, detail = S.env(V, { gameBuild = 3258, w = 1920 })
            assert.is_false(ok)
            assert.is_truthy(detail:find('^askEnv reply refused: '))
        end)

        it('the server checks sv:env with the same schema', function()
            local f = assert(io.open(DIR .. '/server/main.lua', 'rb'))
            local src = f:read('*a')
            f:close()
            assert.is_truthy(src:find('AeternaCore.validate(payload, Selftest.ENV_SCHEMA)', 1, true))
            assert.is_nil(src:find('local ENV_SCHEMA', 1, true))
        end)
    end)

    describe('server handler', function()
        local added, reports, saved, files

        local function boot()
            natives.reset({ resource = OWNER, side = 'server', json = {
                encode = function() return '' end,
                decode = decodeJson,
            } })
            added, reports, saved, files = {}, {}, {}, {}
            natives.spy('RegisterCommand')
            natives.stub('GetNumResources', function() return 0 end)
            natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
            natives.stub('SaveResourceFile', function(_, path, data)
                saved[#saved + 1] = path
                files[path] = data
                return true
            end)
            natives.stub('LoadResourceFile', function(_, path)
                if path == 'schema/report-1.schema.json' then return readFile(DIR .. '/schema/report-1.schema.json') end
                return files[path]
            end)
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
                t = function(k) return (Locales and Locales.en and Locales.en[k]) or k end,
                can = function() return false end,
                rateLimit = function() return true end,
                validate = function(v) return true, nil, v end,
                text = coreText(),
            })
            natives.stub_export('aeterna_uikit', 'addMenuEntry', function() return true end)
            natives.stub_export('aeterna_core', 'addSelftest', function(name, meta)
                added[#added + 1] = { name, meta }
                return name
            end)
            natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail)
                reports[#reports + 1] = { runId, name, ok, detail }
                return true
            end)
            resource.load_resource(DIR, 'server')
        end

        it('registers the six rows on start', function()
            boot()
            assert.are.equal(6, #added)
            assert.are.equal('aeterna_testkit.scrub', added[1][1])
            assert.are.equal('aeterna_testkit.eye_card_b', added[6][1])
            assert.are.equal(2, added[6][2].players)
            assert.is_string(added[5][2].expect)
        end)

        it('reports scrub, report_schema and save; save writes nothing', function()
            boot()
            local built = TestkitLogic.report.build(TestkitLogic.selftest.sampleInput())
            files['reports/latest.json'] = TestkitLogic.report.encode(built)
            files['reports/latest.md'] = TestkitLogic.report.markdown(built, FOOTER)
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.scrub', { kind = 'headless' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.report_schema', { kind = 'headless' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.save', { kind = 'headless' })
            assert.are.equal(3, #reports)
            for _, r in ipairs(reports) do assert.is_true(r[3], r[2] .. ': ' .. tostring(r[4])) end
            assert.are.same({}, saved)
        end)

        it('save skips with no report yet and writes nothing', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.save', {})
            assert.are.same({ 'skip', 'no report yet' }, { reports[1][3], reports[1][4] })
            files['reports/latest.json'] = '{"old":1}'
            natives.fire('aeterna_core:selftest', 'r2-abcd', 'aeterna_testkit.save', {})
            assert.are.same({ 'skip', 'no report yet' }, { reports[2][3], reports[2][4] })
            assert.are.same({}, saved)
            assert.is_nil(files['reports/latest.md'])
        end)

        it('ignores other resources\' tests and events not fired by aeterna_core', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_core.core', {})
            natives.stub('GetInvokingResource', function() return 'other' end)
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.scrub', {})
            assert.are.equal(0, #reports)
        end)
    end)

    describe('client handler', function()
        local reports, warns, schemas, failReport

        local function boot()
            natives.reset({ resource = OWNER, side = 'client' })
            reports, warns, schemas, failReport = {}, {}, {}, false
            local V = assert(loadfile(DIR .. '/../core/shared/logic/validate.lua'))().validate
            natives.spy('SendNUIMessage')
            natives.spy('RegisterNUICallback')
            natives.spy('RegisterKeyMapping')
            natives.spy('RegisterCommand')
            natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
            natives.stub('GetGameBuildNumber', function() return 3258 end)
            natives.stub('GetActiveScreenResolution', function() return 1920, 1080 end)
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, error = function() end,
                    warn = function(msg, fields) warns[#warns + 1] = { msg = msg, fields = fields } end },
                t = function(k) return k end,
                key = function() end,
                validate = function(v, schema)
                    schemas[#schemas + 1] = schema
                    return V(v, schema)
                end,
                requestFocus = function() return 'tok' end,
                releaseFocus = function() return true end,
                themeMessage = function() return { type = 'aeterna:theme' } end,
            })
            natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail)
                if failReport then error('core is gone') end
                reports[#reports + 1] = { runId, name, ok, detail }
                return true
            end)
            resource.load_resource(DIR, 'client')
        end

        it('answers env by checking the askEnv reply against the sv:env schema', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.env', { kind = 'headless', side = 'client' })
            assert.are.same({ { 'r1-abcd', 'aeterna_testkit.env', true, 'game build 3258 · 1920x1080' } }, reports)
            assert.are.equal(TestkitLogic.selftest.ENV_SCHEMA, schemas[#schemas])
            natives.fire('aeterna_testkit:cl:askEnv')
            assert.are.same({ gameBuild = 3258, w = 1920, h = 1080 },
                natives.last_emitted('server', 'aeterna_testkit:sv:env').args[1])
        end)

        it('a game reporting no resolution fails env', function()
            boot()
            natives.stub('GetActiveScreenResolution', function() return nil, nil end)
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.env', { kind = 'headless', side = 'client' })
            assert.is_false(reports[1][3])
        end)

        it('logs a failed reportSelftest at warn instead of hiding it', function()
            boot()
            failReport = true
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.eye_card', { kind = 'eye', role = 'A' })
            assert.are.equal(1, #warns)
            assert.are.equal('reportSelftest failed', warns[1].msg)
        end)

        it('marks both eye cards ready for player A and player B', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.eye_card', { kind = 'eye', role = 'A' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.eye_card_b', { kind = 'eye', role = 'B' })
            assert.are.same({ 'r1-abcd', 'aeterna_testkit.eye_card', 'ready' }, { reports[1][1], reports[1][2], reports[1][3] })
            assert.are.same({ 'r1-abcd', 'aeterna_testkit.eye_card_b', 'ready' }, { reports[2][1], reports[2][2], reports[2][3] })
        end)

        it('ignores eyeAsk, selftest and selftestEnd that aeterna_core did not fire', function()
            boot()
            natives.stub('GetInvokingResource', function() return 'other' end)
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.env', { kind = 'headless', side = 'client' })
            natives.fire('aeterna_core:eyeAsk', 'r1-abcd', 'aeterna_x.a', { ask = 'a', expect = 'b', role = 'A' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_x.p', { kind = 'ped', expect = 'Do it' })
            local nuiTypes = {}
            for _, c in ipairs(natives.calls('SendNUIMessage')) do nuiTypes[#nuiTypes + 1] = c[1].type end
            assert.are.equal(0, #reports)
            assert.are.same({}, nuiTypes)
        end)

        it('ignores tests of other resources', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_core.client_echo', { kind = 'ped' })
            assert.are.equal(0, #reports)
        end)
    end)
end)

describe('aeterna_testkit now-testing strip', function()
    local M, shown, hidden, strip
    before_each(function()
        natives.reset()
        M = loadLogic('menu')
        shown, hidden = {}, 0
        strip = M.createNowStrip({
            show = function(msg) shown[#shown + 1] = msg end,
            hide = function() hidden = hidden + 1 end,
        })
    end)

    it('shows a ped test with expect: the name and the expect line', function()
        assert.is_true(strip:started('r1-abcd', 'aeterna_phonekit.exit_contract',
            { kind = 'ped', expect = 'Press ESC while the phone is open' }))
        assert.are.same({ { name = 'aeterna_phonekit.exit_contract', expect = 'Press ESC while the phone is open' } },
            shown)
        assert.is_true(strip:isShown())
    end)

    it('shows nothing for a ped test without expect, or for any other kind', function()
        assert.is_false(strip:started('r1-abcd', 'aeterna_x.a', { kind = 'ped' }))
        assert.is_false(strip:started('r1-abcd', 'aeterna_x.b', { kind = 'ped', expect = '   ' }))
        assert.is_false(strip:started('r1-abcd', 'aeterna_x.c', { kind = 'eye', expect = 'Look' }))
        assert.is_false(strip:started('r1-abcd', 'aeterna_x.d', { kind = 'headless', expect = 'x' }))
        assert.is_false(strip:started('r1-abcd', 'aeterna_x.e', nil))
        assert.are.equal(0, #shown)
        assert.is_false(strip:isShown())
    end)

    it('hides on selftestEnd for its own test only, once', function()
        strip:started('r1-abcd', 'aeterna_x.a', { kind = 'ped', expect = 'Do it' })
        strip:ended('r1-abcd', 'aeterna_x.other')
        strip:ended('r2-abcd', 'aeterna_x.a')
        assert.are.equal(0, hidden)
        strip:ended('r1-abcd', 'aeterna_x.a')
        strip:ended('r1-abcd', 'aeterna_x.a')
        assert.are.equal(1, hidden)
        assert.is_false(strip:isShown())
    end)

    it('a new ped test replaces the strip; a test without expect hides the old one', function()
        strip:started('r1-abcd', 'aeterna_x.a', { kind = 'ped', expect = 'One' })
        strip:started('r1-abcd', 'aeterna_x.b', { kind = 'ped', expect = 'Two' })
        assert.are.equal('Two', shown[2].expect)
        strip:started('r1-abcd', 'aeterna_x.c', { kind = 'ped' })
        assert.are.equal(1, hidden)
        assert.is_false(strip:isShown())
    end)

    it('the client shows it without focus and hides it on selftestEnd', function()
        natives.reset({ resource = OWNER, side = 'client' })
        local nui, focus = {}, 0
        natives.spy('SendNUIMessage', function(msg) nui[#nui + 1] = msg end)
        natives.spy('RegisterNUICallback')
        natives.spy('RegisterKeyMapping')
        natives.spy('RegisterCommand')
        natives.spy('SetNuiFocus')
        natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
        natives.stub('AeternaCore', {
            log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
            t = function(k) return '<' .. k .. '>' end,
            key = function() end,
            validate = function(v) return true, nil, v end,
            requestFocus = function() focus = focus + 1 return 'tok' end,
            releaseFocus = function() return true end,
            themeMessage = function() return { type = 'aeterna:theme' } end,
        })
        resource.load_resource(DIR, 'client')
        natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_phonekit.exit_contract',
            { kind = 'ped', side = 'client', role = 'A', expect = 'Press ESC' })
        local show
        for _, m in ipairs(nui) do if m.type == 'now:show' then show = m end end
        assert.are.same({ type = 'now:show', name = 'aeterna_phonekit.exit_contract', label = '<testkit.now_doing>',
            expect = 'Press ESC' }, show)
        assert.are.equal(0, focus)
        assert.are.equal(0, #natives.calls('SetNuiFocus'))
        natives.fire('aeterna_core:selftestEnd', 'r1-abcd', 'aeterna_phonekit.exit_contract')
        assert.are.equal('now:hide', nui[#nui].type)
    end)

    it('has testkit.now_doing in Thai and English', function()
        natives.reset()
        assert(loadfile(DIR .. '/locales/en.lua'))()
        assert(loadfile(DIR .. '/locales/th.lua'))()
        assert.are.equal('Do this now:', Locales.en['testkit.now_doing'])
        assert.is_string(Locales.th['testkit.now_doing'])
    end)
end)
