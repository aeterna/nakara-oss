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

        it('save passes only when both files were saved and read back unchanged', function()
            local good = { json = { saved = true, wrote = 'a', back = 'a' }, md = { saved = true, wrote = 'b', back = 'b' } }
            assert.are.same({ true, 'both report files saved and read back' }, { S.save(good) })
            good.md.saved = false
            assert.are.same({ false, 'reports/latest.md: SaveResourceFile returned false' }, { S.save(good) })
            good.md.saved, good.json.back = true, nil
            assert.are.same({ false, 'reports/latest.json: read back differs' }, { S.save(good) })
        end)

        it('env passes for a game build and resolution in range', function()
            assert.are.same({ true, 'game build 3258 · 1920x1080' }, { S.env(3258, 1920, 1080) })
            assert.is_false((S.env(0, 1920, 1080)))
            assert.is_false((S.env(3258, 100, 1080)))
            assert.is_false((S.env(3258, 1920, 9000)))
            assert.are.same({ false, 'game build 3258 · 1920x1080.5 out of range' }, { S.env(3258, 1920, 1080.5) })
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

        it('reports scrub, report_schema and save; save keeps an existing report byte for byte', function()
            boot()
            files['reports/latest.json'] = '{"old":1}'
            files['reports/latest.md'] = '# old'
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.scrub', { kind = 'headless' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.report_schema', { kind = 'headless' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.save', { kind = 'headless' })
            assert.are.equal(3, #reports)
            for _, r in ipairs(reports) do assert.is_true(r[3], r[2] .. ': ' .. tostring(r[4])) end
            assert.are.equal('{"old":1}', files['reports/latest.json'])
            assert.are.equal('# old', files['reports/latest.md'])
            assert.are.same({ 'reports/latest.json', 'reports/latest.md' }, saved)
        end)

        it('save writes a sample report when there is none yet', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.save', {})
            assert.is_true(reports[1][3])
            assert.is_truthy(files['reports/latest.json']:find('aeterna_testkit.report/1', 1, true))
            assert.is_truthy(files['reports/latest.md']:find('# Starter Kit test report', 1, true))
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
        local reports

        local function boot()
            natives.reset({ resource = OWNER, side = 'client' })
            reports = {}
            natives.spy('SendNUIMessage')
            natives.spy('RegisterNUICallback')
            natives.spy('RegisterKeyMapping')
            natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
            natives.stub('GetGameBuildNumber', function() return 3258 end)
            natives.stub('GetActiveScreenResolution', function() return 1920, 1080 end)
            natives.stub('AeternaCore', {
                log = { debug = function() end, info = function() end, warn = function() end, error = function() end },
                t = function(k) return k end,
                key = function() end,
                validate = function(v) return true, nil, v end,
                requestFocus = function() return 'tok' end,
                releaseFocus = function() return true end,
                themeMessage = function() return { type = 'aeterna:theme' } end,
            })
            natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail)
                reports[#reports + 1] = { runId, name, ok, detail }
                return true
            end)
            resource.load_resource(DIR, 'client')
        end

        it('answers env with the values askEnv sends', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.env', { kind = 'headless', side = 'client' })
            assert.are.same({ { 'r1-abcd', 'aeterna_testkit.env', true, 'game build 3258 · 1920x1080' } }, reports)
            natives.fire('aeterna_testkit:cl:askEnv')
            assert.are.same({ gameBuild = 3258, w = 1920, h = 1080 },
                natives.last_emitted('server', 'aeterna_testkit:sv:env').args[1])
        end)

        it('marks both eye cards ready for player A and player B', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.eye_card', { kind = 'eye', role = 'A' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_testkit.eye_card_b', { kind = 'eye', role = 'B' })
            assert.are.same({ 'r1-abcd', 'aeterna_testkit.eye_card', 'ready' }, { reports[1][1], reports[1][2], reports[1][3] })
            assert.are.same({ 'r1-abcd', 'aeterna_testkit.eye_card_b', 'ready' }, { reports[2][1], reports[2][2], reports[2][3] })
        end)

        it('ignores tests of other resources', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_core.client_echo', { kind = 'ped' })
            assert.are.equal(0, #reports)
        end)
    end)
end)
