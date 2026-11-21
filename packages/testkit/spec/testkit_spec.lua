-- testkit_spec.lua -- aeterna_testkit: the busted cases of docs/specs/aeterna_testkit.md "Tests".
-- Pure modules (shared/logic/report.lua, scrub.lua, menu.lua) plus the console command under the harness.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local DIR = (debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.') .. '/..'

local function loadLogic(name)
    return assert(loadfile(DIR .. '/shared/logic/' .. name .. '.lua'))()
end

local function coreText()
    return assert(loadfile(DIR .. '/../core/shared/logic/text.lua'))()
end

local function row(over)
    local r = {
        suite = 'aeterna_core', name = 'aeterna_core.core', kind = 'headless', players = 1, destructive = false,
        state = 'PASS', detail = 'ok', ms = 3,
    }
    for k, v in pairs(over or {}) do r[k] = v end
    return r
end

local function sortedKeys(t)
    local out = {}
    for k in pairs(t) do out[#out + 1] = k end
    table.sort(out)
    return out
end

-- Runs `fn` with aeterna_core as the invoking resource, as for events core fires.
local function asCore(fn)
    natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
    local ok, err = pcall(fn)
    natives.stub('GetInvokingResource', function() return nil end)
    if not ok then error(err, 0) end
end

local function sampleInput(rows)
    return {
        runId = 'r1k-4f2a', startedAt = '2026-11-21T14:02:11Z', ms = 184230, by = 'menu', playerB = true,
        destructive = 'off', cancelled = false,
        env = { fxserver = '13068', gameBuild = 3788, resolution = '1920x1080' },
        kit = { aeterna_core = '0.2.0', aeterna_uikit = '0.2.0', aeterna_testkit = '0.1.0' },
        rows = rows,
    }
end

describe('aeterna_testkit', function()
    before_each(function()
        natives.reset()
    end)

    describe('1. scrub (shared/logic/scrub.lua)', function()
        local S, clean
        before_each(function()
            S = loadLogic('scrub')
            clean = coreText().clean
        end)

        it('replaces the player name, a license id, an IPv4 with port and a Windows path', function()
            local out = S.scrub('player Somchai lost license:abc123 at 10.0.0.5:30120 C:\\srv\\x.lua',
                { A = 'Somchai' }, clean)
            assert.are.equal('player A lost [id] at [ip] [path]', out)
        end)

        it('replaces player B by name too', function()
            assert.are.equal('A gave B a car', S.scrub('Somchai gave Malee a car', { A = 'Somchai', B = 'Malee' }, clean))
        end)

        it('replaces a POSIX path with two or more segments', function()
            assert.are.equal('[path]', S.scrub('/home/u/a', {}, clean))
            assert.are.equal('read [path] failed', S.scrub('read /srv/fx/server.cfg failed', {}, clean))
        end)

        it('replaces every documented identifier prefix', function()
            for _, id in ipairs({ 'steam:1100001abcdef', 'license2:0f0f0f', 'fivem:123456', 'ip:10.1.2.3',
                'xbl:2535', 'live:1234', 'license:abc' }) do
                assert.are.equal('id [id] seen', S.scrub('id ' .. id .. ' seen', {}, clean))
            end
        end)

        it('leaves other word:value text alone', function()
            assert.are.equal('screen:home', S.scrub('screen:home', {}, clean))
        end)

        it('replaces IPv6 forms', function()
            assert.are.equal('[ip]', S.scrub('::1', {}, clean))
            assert.are.equal('from [ip] now', S.scrub('from fe80::1 now', {}, clean))
            assert.are.equal('[ip]', S.scrub('2001:db8:0:0:0:0:2:1', {}, clean))
        end)

        it('leaves a plain game-terms detail unchanged', function()
            assert.are.equal('step 3: screen is home', S.scrub('step 3: screen is home', {}, clean))
            assert.are.equal('at 12:30:45', S.scrub('at 12:30:45', {}, clean))
            assert.are.equal('passed 3/5', S.scrub('passed 3/5', {}, clean))
            assert.are.equal('build v1.0.0.13068', S.scrub('build v1.0.0.13068', {}, clean))
        end)

        it('replaces a discord snowflake id', function()
            assert.are.equal('by [id] now', S.scrub('by discord:123456789012345678 now', {}, clean))
        end)

        it('replaces an unknown <letters>: prefix followed by 15 or more digits', function()
            assert.are.equal('id [id]', S.scrub('id newsvc:123456789012345', {}, clean))
            assert.are.equal('id other:12345678901234', S.scrub('id other:12345678901234', {}, clean))
        end)

        it('leaves resource-style names, step labels and times unchanged', function()
            assert.are.equal('aeterna_core:foo', S.scrub('aeterna_core:foo', {}, clean))
            assert.are.equal('step 3: x', S.scrub('step 3: x', {}, clean))
            assert.are.equal('at 12:30', S.scrub('at 12:30', {}, clean))
        end)

        it('replaces paths after (, = and @, and in stack frames', function()
            assert.are.equal('open ([path]) failed', S.scrub('open (/srv/fx/a.cfg) failed', {}, clean))
            assert.are.equal('file=[path] bad', S.scrub('file=/home/u/x.lua bad', {}, clean))
            assert.are.equal('file=[path] bad', S.scrub('file=C:\\srv\\x.lua bad', {}, clean))
            assert.are.equal('error at [path] boom', S.scrub('error at @aeterna_demo/server/main.lua:12: boom', {}, clean))
        end)

        it('skips names shorter than 3 characters and matches whole words only', function()
            assert.are.equal('Bo ate a box', S.scrub('Bo ate a box', { A = 'Bo' }, clean))
            assert.are.equal('A met Annabel', S.scrub('Ann met Annabel', { A = 'Ann' }, clean))
            assert.are.equal('ok A.', S.scrub('ok Ann.', { A = 'Ann' }, clean))
        end)

        it('cuts to 300 visible characters and drops control characters', function()
            local out = S.scrub(string.rep('a', 310) .. '\n', {}, clean)
            assert.are.equal(300, utf8.len(out))
        end)

        it('returns nil for a non-string', function()
            assert.is_nil(S.scrub(nil, {}, clean))
        end)
    end)

    describe('2. report JSON (shared/logic/report.lua)', function()
        local R
        before_each(function()
            R = loadLogic('report')
        end)

        it('has exactly the schema keys, top level, env and rows', function()
            local rep = R.build(sampleInput({ row(), row({ state = 'FAIL', detail = 'step 3: screen is home', step = 3,
                expected = 'contacts.detail', suite = 'aeterna_phonekit', name = 'aeterna_phonekit.fold_keeps_screen',
                kind = 'ped' }) }))
            assert.are.same({ 'by', 'cancelled', 'counts', 'destructive', 'env', 'kit', 'ms', 'ok', 'playerB', 'rows',
                'runId', 'schema', 'startedAt' }, sortedKeys(rep))
            assert.are.equal('aeterna_testkit.report/1', rep.schema)
            assert.are.same({ 'fxserver', 'gameBuild', 'resolution' }, sortedKeys(rep.env))
            assert.are.same({ 'FAIL', 'GAP', 'MISSING', 'MOCK', 'PASS', 'SKIP' }, sortedKeys(rep.counts))
            for _, r in ipairs(rep.rows) do
                assert.are.same({ 'destructive', 'detail', 'expected', 'kind', 'ms', 'name', 'players', 'state', 'step',
                    'suite' }, sortedKeys(r))
            end
            assert.are.equal('phonekit', rep.rows[2].suite)
            assert.are.equal('aeterna_phonekit.fold_keeps_screen', rep.rows[2].name)
            assert.are.equal(R.NULL, rep.rows[1].step)
        end)

        it('ok is true only with no FAIL and no MISSING', function()
            assert.is_true(R.build(sampleInput({ row(), row({ state = 'GAP' }), row({ state = 'SKIP' }) })).ok)
            assert.is_false(R.build(sampleInput({ row(), row({ state = 'FAIL' }) })).ok)
            assert.is_false(R.build(sampleInput({ row(), row({ state = 'MISSING', kind = nil }) })).ok)
        end)

        it('counts match the rows', function()
            local rows = { row(), row(), row({ state = 'FAIL' }), row({ state = 'SKIP' }), row({ state = 'GAP' }),
                row({ state = 'MOCK' }), row({ state = 'MISSING' }) }
            local rep = R.build(sampleInput(rows))
            assert.are.same({ PASS = 2, FAIL = 1, SKIP = 1, GAP = 1, MOCK = 1, MISSING = 1 }, rep.counts)
        end)

        it('cuts rows past 500 and sets truncated = true', function()
            local rows = {}
            for i = 1, 520 do rows[i] = row({ name = 'aeterna_core.t' .. i }) end
            local rep = R.build(sampleInput(rows))
            assert.are.equal(500, #rep.rows)
            assert.is_true(rep.truncated)
            assert.are.equal(520, rep.counts.PASS)
            assert.is_nil(R.build(sampleInput({ row() })).truncated)
        end)

        it('encodes one JSON line with keys in schema order and null for missing values', function()
            local input = sampleInput({ row() })
            input.env = { fxserver = R.NULL, gameBuild = R.NULL, resolution = R.NULL }
            local line = R.encode(R.build(input))
            assert.is_nil(line:find('\n', 1, true))
            assert.are.equal(1, line:find('{"schema":"aeterna_testkit.report/1","runId":"r1k-4f2a"', 1, true))
            assert.truthy(line:find('"env":{"fxserver":null,"gameBuild":null,"resolution":null}', 1, true))
            assert.truthy(line:find('"step":null,"expected":null}', 1, true))
        end)

        it('plain() turns the null marker into nil for the lastReport export', function()
            local plain = R.plain(R.build(sampleInput({ row() })))
            assert.is_nil(plain.rows[1].step)
            assert.are.equal('13068', plain.env.fxserver)
        end)
    end)

    describe('3. report Markdown', function()
        local R
        before_each(function()
            R = loadLogic('report')
        end)

        local FOOTER = 'No player names, identifiers, IPs, convar values or paths.'

        local function lines(s)
            local out = {}
            for l in (s .. '\n'):gmatch('(.-)\n') do out[#out + 1] = l end
            return out
        end

        it('has the header, counts line, a table row per suite, sections and the footer last', function()
            local rows = {
                row(),
                row({ suite = 'aeterna_phonekit', name = 'aeterna_phonekit.fold_keeps_screen', kind = 'ped',
                    state = 'FAIL', detail = 'step 3: screen is home', step = 3, expected = 'contacts.detail' }),
                row({ suite = 'aeterna_phonecall', name = 'aeterna_phonecall.call_ab', state = 'GAP',
                    detail = 'needs player B' }),
                row({ suite = 'aeterna_hudkit', name = 'aeterna_hudkit.voice_indicator', state = 'SKIP',
                    detail = 'needs pma-voice' }),
            }
            local md = R.markdown(R.build(sampleInput(rows)), FOOTER)
            local l = lines(md)
            assert.are.equal('# Starter Kit test report · r1k-4f2a', l[1])
            assert.are.equal('FXServer 13068 · game build 3788 · 1920x1080 · by menu · player B yes · destructive off', l[2])
            assert.are.equal('**FAIL** · PASS 1 · FAIL 1 · SKIP 1 · GAP 1 · MOCK 0 · MISSING 0 · 184 s', l[3])
            assert.truthy(md:find('| core | 1/1 | PASS |', 1, true))
            assert.truthy(md:find('| phonekit | 0/1 | FAIL |', 1, true))
            assert.truthy(md:find('| phonecall | 0/1 | GAP |', 1, true))
            assert.truthy(md:find('| hudkit | 1/1 | SKIP |', 1, true))
            assert.truthy(md:find(
                '- phonekit.fold_keeps_screen (ped) · step 3 · expected contacts.detail · step 3: screen is home', 1, true))
            assert.truthy(md:find('## Left for a person (GAP)\n- phonecall.call_ab · needs player B', 1, true))
            assert.truthy(md:find('## SKIP\n- hudkit.voice_indicator · needs pma-voice', 1, true))
            assert.truthy(md:find('## Versions\naeterna_core 0.2.0 · aeterna_testkit 0.1.0 · aeterna_uikit 0.2.0', 1, true))
            assert.is_nil(md:find('aeterna_phonekit.', 1, true))
            assert.are.equal(FOOTER, l[#l])
        end)

        it('leaves out empty sections, and a green run says PASS', function()
            local md = R.markdown(R.build(sampleInput({ row() })), FOOTER)
            assert.is_nil(md:find('## FAIL and MISSING', 1, true))
            assert.is_nil(md:find('## Left for a person', 1, true))
            assert.is_nil(md:find('## SKIP', 1, true))
            assert.truthy(md:find('\n**PASS** · PASS 1', 1, true))
            local l = lines(md)
            assert.are.equal(FOOTER, l[#l])
        end)

        it('shows null environment values for a console run', function()
            local input = sampleInput({ row() })
            input.by = 'console'
            input.playerB = false
            input.env = { fxserver = R.NULL, gameBuild = R.NULL, resolution = R.NULL }
            local l = lines(R.markdown(R.build(input), FOOTER))
            assert.are.equal('FXServer - · game build - · - · by console · player B no · destructive off', l[2])
        end)
    end)

    describe('4. FXServer build parse', function()
        local R
        before_each(function()
            R = loadLogic('report')
        end)

        it('keeps only the build number', function()
            assert.are.equal('13068', R.parseBuild('FXServer-master SERVER v1.0.0.13068 win32'))
            assert.are.equal('7290', R.parseBuild('FXServer-master v1.0.0.7290 linux'))
        end)

        it('returns nil when there is no build', function()
            assert.is_nil(R.parseBuild('FXServer-master SERVER win32'))
            assert.is_nil(R.parseBuild(''))
            assert.is_nil(R.parseBuild(nil))
        end)

        it('the rest of the version string never reaches the report', function()
            local input = sampleInput({ row() })
            input.env.fxserver = R.parseBuild('FXServer-master SERVER v1.0.0.13068 win32')
            local rep = R.build(input)
            local text = R.encode(rep) .. R.markdown(rep, 'footer')
            assert.is_nil(text:find('master', 1, true))
            assert.is_nil(text:find('win32', 1, true))
            assert.is_nil(text:find('SERVER', 1, true))
        end)
    end)

    describe('5. suite rows', function()
        local R
        before_each(function()
            R = loadLogic('report')
        end)

        it('passed counts PASS, SKIP and MOCK; total counts every row', function()
            local suites = R.suites({
                row({ state = 'PASS' }), row({ state = 'SKIP' }), row({ state = 'MOCK' }), row({ state = 'GAP' }),
                row({ state = 'FAIL' }),
            })
            assert.are.equal(1, #suites)
            assert.are.equal('core', suites[1].suite)
            assert.are.equal(3, suites[1].passed)
            assert.are.equal(5, suites[1].total)
        end)

        it('worst state order is FAIL, MISSING, GAP, SKIP, MOCK, PASS', function()
            local order = { 'FAIL', 'MISSING', 'GAP', 'SKIP', 'MOCK', 'PASS' }
            for i = 1, #order do
                for j = i, #order do
                    assert.are.equal(order[i], R.worst(order[i], order[j]))
                    assert.are.equal(order[i], R.worst(order[j], order[i]))
                end
            end
            local suites = R.suites({ row({ state = 'MOCK' }), row({ state = 'GAP' }), row({ state = 'SKIP' }) })
            assert.are.equal('GAP', suites[1].worst)
        end)

        it('keeps suites in the order they first appear', function()
            local suites = R.suites({ row({ suite = 'aeterna_uikit' }), row(), row({ suite = 'aeterna_uikit' }) })
            assert.are.equal('uikit', suites[1].suite)
            assert.are.equal('core', suites[2].suite)
            assert.are.equal(2, suites[1].total)
        end)
    end)

    describe('6. invite rules (shared/logic/menu.lua)', function()
        local M, clock, online, inv
        before_each(function()
            M = loadLogic('menu')
            clock = 0
            online = { [1] = true, [2] = true, [3] = true, [4] = true }
            inv = M.createInvites({ seconds = 30, now = function() return clock end })
        end)

        local function isOnline(id) return online[id] == true end

        it('refuses yourself, an offline id and an id out of range', function()
            assert.are.same({ false, 'self' }, { inv:create(1, 1, isOnline) })
            assert.are.same({ false, 'offline' }, { inv:create(1, 9, isOnline) })
            assert.are.same({ false, 'invalid' }, { inv:create(1, 0, isOnline) })
            assert.are.same({ false, 'invalid' }, { inv:create(1, 70000, isOnline) })
        end)

        it('refuses an id already in a pending invite and a second invite while one is open', function()
            assert.is_true(inv:create(1, 2, isOnline))
            assert.are.same({ false, 'pending' }, { inv:create(3, 2, isOnline) })
            assert.are.same({ false, 'pending' }, { inv:create(1, 3, isOnline) })
            assert.are.same({ false, 'pending' }, { inv:create(2, 3, isOnline) })
            assert.are.same({ false, 'pending' }, { inv:create(3, 1, isOnline) })
        end)

        it('refuses while either side is in a run', function()
            local inRun = function(id) return id == 2 end
            assert.are.same({ false, 'busy' }, { inv:create(1, 2, isOnline, inRun) })
        end)

        it('drops an answer from someone other than the invited player', function()
            assert.is_true(inv:create(1, 2, isOnline))
            assert.is_nil(inv:answer(3, true))
            assert.is_nil(inv:answer(1, true))
            assert.is_nil(inv:bOf(1))
            assert.are.same({ 'accepted', 1 }, { inv:answer(2, true) })
            assert.are.equal(2, inv:bOf(1))
            assert.is_nil(inv:answer(2, true))
        end)

        it('a decline frees both sides', function()
            assert.is_true(inv:create(1, 2, isOnline))
            assert.are.same({ 'declined', 1 }, { inv:answer(2, false) })
            assert.is_nil(inv:bOf(1))
            assert.is_true(inv:create(3, 2, isOnline))
        end)

        it('expires after Config.inviteSeconds (fake clock)', function()
            assert.is_true(inv:create(1, 2, isOnline))
            clock = 29999
            assert.are.same({}, inv:expire())
            clock = 30000
            local gone = inv:expire()
            assert.are.equal(1, #gone)
            assert.are.equal(1, gone[1].a)
            assert.are.equal(2, gone[1].b)
            assert.is_nil(inv:answer(2, true))
            assert.is_true(inv:create(1, 2, isOnline))
        end)

        it('an accepted B blocks new invites until B leaves or is released', function()
            assert.is_true(inv:create(1, 2, isOnline))
            inv:answer(2, true)
            assert.are.same({ false, 'pending' }, { inv:create(3, 2, isOnline) })
            local left = inv:leave(2)
            assert.are.same({ { a = 1, b = 2 } }, left)
            assert.is_nil(inv:bOf(1))
            assert.is_true(inv:create(1, 2, isOnline))
            inv:answer(2, true)
            assert.are.equal(2, inv:release(1))
            assert.is_nil(inv:bOf(1))
        end)

        it('a disconnect of A clears an open invite', function()
            assert.is_true(inv:create(1, 2, isOnline))
            assert.are.same({ { a = 1, b = 2 } }, inv:leave(1))
            assert.is_nil(inv:answer(2, true))
        end)
    end)

    describe('7. menu progress throttle', function()
        local M
        before_each(function()
            M = loadLogic('menu')
        end)

        it('sends at most 4 updates a second', function()
            local t = M.createThrottle(250)
            local sent = 0
            for now = 0, 990, 10 do
                if t:hit(now) then sent = sent + 1 end
                if t:due(now) then sent = sent + 1 end
            end
            assert.is_true(sent <= 4)
            assert.is_true(sent >= 3)
        end)

        it('a deferred update is sent once its slot comes', function()
            local t = M.createThrottle(250)
            assert.is_true(t:hit(0))
            assert.is_false(t:hit(100))
            assert.is_false(t:due(200))
            assert.is_true(t:due(250))
            assert.is_false(t:due(600))
            assert.are.equal(0, t:wait(600))
        end)

        it('the last update after runDone is never dropped', function()
            local t = M.createThrottle(250)
            assert.is_true(t:hit(1000))
            assert.is_true(t:final(1001))
            assert.is_false(t:due(2000))
        end)
    end)

    describe('8. console guard (server/main.lua under the harness)', function()
        local commands, restricted, starts, saved, warnings, printed, realPrint, panels

        before_each(function()
            natives.reset({ resource = 'aeterna_testkit', side = 'server', players = { [1] = 'Somchai', [2] = 'Malee' } })
            commands, restricted, starts, saved, warnings, printed, panels = {}, {}, {}, {}, {}, {}, 0
            natives.spy('RegisterCommand', function(name, fn, isRestricted)
                commands[name] = fn
                restricted[name] = isRestricted
            end)
            natives.stub('GetNumResources', function() return 2 end)
            natives.stub('GetResourceByFindIndex', function(i) return ({ [0] = 'aeterna_core', [1] = 'aeterna_testkit' })[i] end)
            natives.stub('GetResourceState', function() return 'started' end)
            natives.stub('GetResourceMetadata', function(res) return res == 'aeterna_core' and '0.2.0' or '0.1.0' end)
            natives.stub('SaveResourceFile', function(_, path, data)
                saved[path] = data
                return true
            end)
            natives.set_convar('version', 'FXServer-master SERVER v1.0.0.13068 win32')
            natives.stub('AeternaCore', {
                log = {
                    debug = function() end, info = function() end, error = function() end,
                    warn = function(msg, fields) warnings[#warnings + 1] = { msg = msg, fields = fields } end,
                },
                t = function(k, vars)
                    local s = (Locales and Locales.en and Locales.en[k]) or k
                    return (s:gsub('{(%w+)}', function(v) return vars and vars[v] ~= nil and tostring(vars[v]) or '{' .. v .. '}' end))
                end,
                can = function(src) return tonumber(src) == 0 or tonumber(src) == 1 end,
                rateLimit = function() return true end,
                validate = function(v) return true, nil, v end,
                text = coreText(),
            })
            natives.stub_export('aeterna_uikit', 'addMenuEntry', function() return true end)
            natives.stub_export('aeterna_uikit', 'open', function()
                panels = panels + 1
                return 'p' .. panels
            end)
            natives.stub_export('aeterna_uikit', 'update', function() return true end)
            natives.stub_export('aeterna_core', 'listSelftests', function() return {} end)
            natives.stub_export('aeterna_core', 'runStatus', function() return nil end)
            natives.stub_export('aeterna_core', 'busy', function() return nil end)
            natives.stub_export('aeterna_core', 'startRun', function(opts)
                starts[#starts + 1] = opts
                if #starts > 1 then return 'r' .. #starts .. '-abcd' end
                asCore(function()
                    natives.fire('aeterna_core:runProgress', 'r1-abcd', {
                        name = 'aeterna_core.core', suite = 'aeterna_core', kind = 'headless', players = 1,
                        destructive = false, state = 'PASS', ok = true, detail = 'ok', ms = 2,
                    })
                end)
                return 'r1-abcd'
            end)
            realPrint = print
            _G.print = function(...)
                local parts = {}
                for i = 1, select('#', ...) do parts[i] = tostring(select(i, ...)) end
                printed[#printed + 1] = table.concat(parts, ' ')
            end
        end)

        after_each(function()
            _G.print = realPrint
        end)

        it('starts nothing and prints nothing when source is a player', function()
            resource.load_resource(DIR, 'server')
            assert.is_function(commands.aeterna_testkit_run)
            commands.aeterna_testkit_run(1, { '--json' }, 'aeterna_testkit_run --json')
            assert.are.equal(0, #starts)
            assert.are.equal(0, #printed)
            assert.are.equal(1, #warnings)
            for _, w in ipairs(warnings) do
                assert.is_nil((w.msg .. tostring(w.fields and w.fields.src)):find('Somchai', 1, true))
            end
        end)

        it('registers the console command restricted, and no sv:invite net event', function()
            resource.load_resource(DIR, 'server')
            assert.is_true(restricted.aeterna_testkit_run)
            assert.is_true(natives.is_net_event('aeterna_testkit:sv:open'))
            assert.is_false(natives.is_net_event('aeterna_testkit:sv:invite'))
        end)

        it('clears the run, releases player B and resets roles when aeterna_core stops mid-run', function()
            resource.load_resource(DIR, 'server')
            local function act(panelId, action, values)
                natives.fire('aeterna_uikit:action', 1, { owner = 'aeterna_testkit', panelId = panelId, action = action,
                    values = values or {} })
            end
            natives.fire_net('aeterna_testkit:sv:open', 1)
            act('p1', 'invite')
            act('p2', 'send', { target = 2 })
            assert.are.equal(2, natives.last_emitted('client', 'aeterna_testkit:cl:invite').target)
            natives.fire_net('aeterna_testkit:sv:inviteAnswer', 2, { accept = true })
            act('p3', 'run')
            assert.are.equal(1, #starts)
            assert.are.equal(2, starts[1].b)

            natives.fire('onResourceStop', 'aeterna_core')
            local last = {}
            for _, e in ipairs(natives.emitted('client', 'aeterna_testkit:cl:role')) do last[e.target] = e.args[1].role end
            assert.are.equal('none', last[1])
            assert.are.equal('none', last[2])

            commands.aeterna_testkit_run(0, {}, 'aeterna_testkit_run')
            assert.are.equal(2, #starts)
            act('p3', 'invite')
            act('p4', 'send', { target = 2 })
            assert.are.equal(2, #natives.emitted('client', 'aeterna_testkit:cl:invite'))
        end)

        it('runProgress and runDone with no invoking resource are ignored', function()
            resource.load_resource(DIR, 'server')
            commands.aeterna_testkit_run(0, { '--json' }, 'aeterna_testkit_run --json')
            local before = #printed
            natives.stub('GetInvokingResource', function() return nil end)
            natives.fire('aeterna_core:runProgress', 'r1-abcd', { name = 'aeterna_core.x', suite = 'aeterna_core',
                state = 'PASS', ok = true, detail = 'ok', ms = 1 })
            natives.fire('aeterna_core:runDone', 'r1-abcd', { counts = {}, ok = true, cancelled = false, ms = 1,
                destructive = 'off' })
            assert.are.equal(before, #printed)
            assert.is_nil(saved['reports/latest.json'])
        end)

        it('--json from the console prints the report as one line and saves both files', function()
            resource.load_resource(DIR, 'server')
            commands.aeterna_testkit_run(0, { '--json', '--only', 'aeterna_core' }, 'aeterna_testkit_run --json --only aeterna_core')
            assert.are.equal(1, #starts)
            assert.are.equal(0, starts[1].by)
            assert.are.same({ 'aeterna_core' }, starts[1].only)
            asCore(function()
                natives.fire('aeterna_core:runDone', 'r1-abcd', {
                    counts = { PASS = 1, FAIL = 0, SKIP = 0, GAP = 0, MOCK = 0, MISSING = 0 }, ok = true,
                    cancelled = false, ms = 1200, destructive = 'off',
                })
            end)
            local jsonLines = {}
            for _, p in ipairs(printed) do
                if p:sub(1, 1) == '{' then jsonLines[#jsonLines + 1] = p end
            end
            assert.are.equal(1, #jsonLines)
            assert.is_nil(jsonLines[1]:find('\n', 1, true))
            assert.are.equal(1, jsonLines[1]:find('{"schema":"aeterna_testkit.report/1","runId":"r1-abcd"', 1, true))
            assert.truthy(jsonLines[1]:find('"by":"console"', 1, true))
            assert.truthy(jsonLines[1]:find('"fxserver":"13068"', 1, true))
            assert.is_nil(jsonLines[1]:find('win32', 1, true))
            assert.is_string(saved['reports/latest.json'])
            assert.is_string(saved['reports/latest.md'])
            assert.are.equal(jsonLines[1], saved['reports/latest.json'])
        end)
    end)

    describe('9. eye card state (shared/logic/menu.lua)', function()
        local M, card, requests, releases, answers, shown, hidden

        before_each(function()
            M = loadLogic('menu')
            requests, releases, answers, shown, hidden = {}, {}, {}, {}, 0
            card = M.createEyeCard({
                request = function(opts)
                    requests[#requests + 1] = opts
                    return 'tok' .. #requests
                end,
                release = function(token) releases[#releases + 1] = token end,
                answer = function(runId, name, a) answers[#answers + 1] = { runId, name, a } end,
                show = function(msg) shown[#shown + 1] = msg end,
                hide = function() hidden = hidden + 1 end,
            })
        end)

        local function ask(name)
            return card:ask('r1-abcd', name or 'aeterna_phonekit.home', { ask = 'Is the phone open?', expect = 'A phone', role = 'A' })
        end

        it('requests focus in overlay mode with cursor and keyboard', function()
            assert.is_true(ask())
            assert.are.same({ overlay = true, cursor = true, keyboard = true }, requests[1])
            assert.is_true(card:isOpen())
            assert.are.equal(1, shown[1].index)
            assert.are.equal('Is the phone open?', shown[1].ask)
        end)

        it('an answer sends it to core, closes, and releases the token once', function()
            ask()
            assert.is_true(card:answer('mismatch'))
            assert.are.same({ { 'r1-abcd', 'aeterna_phonekit.home', 'mismatch' } }, answers)
            assert.are.same({ 'tok1' }, releases)
            assert.is_false(card:isOpen())
            card:ended('r1-abcd', 'aeterna_phonekit.home')
            card:lost('tok1')
            assert.are.same({ 'tok1' }, releases)
            assert.are.equal(1, hidden)
        end)

        it('refuses an answer outside pass, mismatch, skip', function()
            ask()
            assert.is_false(card:answer('PASS'))
            assert.are.equal(0, #answers)
            assert.is_true(card:isOpen())
        end)

        it('selftestEnd for its test closes it and releases once; another test does not', function()
            ask()
            card:ended('r1-abcd', 'aeterna_phonekit.other')
            assert.is_true(card:isOpen())
            card:ended('r1-abcd', 'aeterna_phonekit.home')
            assert.is_false(card:isOpen())
            assert.are.same({ 'tok1' }, releases)
            assert.are.equal(0, #answers)
        end)

        it('focusLost for its own token closes it and releases once; another token does not', function()
            ask()
            card:lost('other')
            assert.is_true(card:isOpen())
            card:lost('tok1')
            assert.is_false(card:isOpen())
            card:lost('tok1')
            assert.are.same({ 'tok1' }, releases)
            assert.are.equal(0, #answers)
        end)

        it('ESC sends skip', function()
            ask()
            assert.is_true(card:escape())
            assert.are.same({ { 'r1-abcd', 'aeterna_phonekit.home', 'skip' } }, answers)
            assert.are.same({ 'tok1' }, releases)
        end)

        it('a new ask replaces an open card, releasing the old token, and counts the index', function()
            ask('aeterna_phonekit.a')
            ask('aeterna_phonekit.b')
            assert.are.same({ 'tok1' }, releases)
            assert.are.equal(2, shown[2].index)
            card:answer('pass')
            assert.are.same({ 'tok1', 'tok2' }, releases)
        end)

        it('shows nothing when focus is refused', function()
            card = M.createEyeCard({
                request = function() return nil end,
                release = function(token) releases[#releases + 1] = token end,
                answer = function() end, show = function(msg) shown[#shown + 1] = msg end, hide = function() end,
            })
            assert.is_false(ask())
            assert.is_false(card:isOpen())
            assert.are.equal(0, #shown)
            assert.are.equal(0, #releases)
        end)
    end)

    describe('console arguments', function()
        it('parses --json and --only', function()
            local M = loadLogic('menu')
            assert.are.same({ json = false }, M.parseArgs({}))
            assert.are.same({ json = true, only = 'aeterna_core' }, M.parseArgs({ '--only', 'aeterna_core', '--json' }))
            assert.are.same({ json = false }, M.parseArgs({ '--only' }))
        end)
    end)
end)
