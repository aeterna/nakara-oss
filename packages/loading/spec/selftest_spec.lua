-- spec/selftest_spec.lua -- busted tests for the aeterna_loading self-tests (docs/specs/aeterna_loading.md
-- "Self-tests (0.2)"): the rows, their checks (shared/logic/selftest.lua) and the local-events-only edge to
-- aeterna_core in server/main.lua and client/main.lua.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function loadLogic()
    assert(loadfile(DIR .. '/shared/logic/loading.lua'))()
    return assert(loadfile(DIR .. '/shared/logic/selftest.lua'))()
end

local function readFile(path)
    local f = assert(io.open(path, 'rb'))
    local body = f:read('*a')
    f:close()
    return body
end

local OWNER = 'aeterna_loading'

describe('aeterna_loading self-tests', function()
    local S
    before_each(function()
        natives.reset({ resource = OWNER, side = 'server' })
        S = loadLogic()
    end)

    describe('rows', function()
        it('are exactly the four rows of the spec table, in order', function()
            local rows = S.rows(OWNER, function(key) return '<' .. key .. '>' end)
            local names = {}
            for i, r in ipairs(rows) do names[i] = r.name end
            assert.are.same({
                'aeterna_loading.config_valid', 'aeterna_loading.local_paths_only', 'aeterna_loading.shut_down',
                'aeterna_loading.page_looked_right',
            }, names)
            assert.are.same({ kind = 'headless', players = 1, destructive = false }, rows[1].meta)
            assert.are.same({ kind = 'headless', players = 1, destructive = false }, rows[2].meta)
            assert.are.same({ kind = 'ped', players = 1, destructive = false }, rows[3].meta)
            assert.are.same({ kind = 'eye', players = 1, destructive = false,
                expect = '<loading.selftest.expect.page>' }, rows[4].meta)
        end)

        it('take the eye expect from the package locale in Thai and English', function()
            natives.reset({ resource = OWNER, side = 'server' })
            assert(loadfile(DIR .. '/locales/en.lua'))()
            assert(loadfile(DIR .. '/locales/th.lua'))()
            for _, lang in ipairs({ 'en', 'th' }) do
                local s = Locales[lang]['loading.selftest.expect.page']
                assert.is_string(s)
                assert.is_true(utf8.len(s) >= 1 and utf8.len(s) <= 240)
            end
        end)

        it('name tests only under the owner prefix', function()
            assert.is_true(S.owns(OWNER, 'aeterna_loading.config_valid'))
            assert.is_false(S.owns(OWNER, 'aeterna_loadingx.config_valid'))
            assert.is_false(S.owns(OWNER, 'aeterna_core.core'))
            assert.is_false(S.owns(OWNER, nil))
        end)
    end)

    describe('checks', function()
        it('config_valid passes with no errors and names every bad field', function()
            assert.are.same({ true, 'html/config.json is valid' }, { S.configValid({}) })
            local ok, detail = S.configValid({ { field = 'serverName' }, { field = 'tipSeconds' } })
            assert.is_false(ok)
            assert.are.equal('bad fields: serverName, tipSeconds', detail)
        end)

        it('local_paths_only accepts empty and local paths and names a remote one', function()
            assert.are.same({ true, 'background and audio.src are local' },
                { S.localPaths(LoadingLogic, { background = '', audio = { src = '' } }) })
            assert.is_true((S.localPaths(LoadingLogic, { background = 'img/bg.jpg', audio = { src = 'a/m.ogg' } })))
            assert.is_true((S.localPaths(LoadingLogic, {})))
            local ok, detail = S.localPaths(LoadingLogic, { background = 'https://example.invalid/bg.jpg',
                audio = { src = '../x.ogg' } })
            assert.is_false(ok)
            assert.are.equal('not a local path: background, audio.src', detail)
            assert.are.same({ false, 'html/config.json could not be read' }, { S.localPaths(LoadingLogic, nil) })
        end)

        it('shut_down passes only when the loading screen is no longer active', function()
            assert.are.same({ true, 'loading screen is shut down' }, { S.shutDown(false) })
            assert.are.same({ false, 'loading screen is still active' }, { S.shutDown(true) })
        end)
    end)

    describe('server script (local events only)', function()
        -- `config` is the decoded html/config.json; json.decode is stubbed so the case needs no JSON library.
        local function boot(coreState, config)
            natives.reset({ resource = OWNER, side = 'server', json = {
                encode = function() return '' end,
                decode = function(s) if s == 'CONFIG' then return config end error('not json') end,
            } })
            natives.stub('GetResourceState', function(name)
                if name == 'aeterna_core' then return coreState end
                return 'missing'
            end)
            natives.stub('LoadResourceFile', function(_, path)
                if path == 'html/config.json' then return 'CONFIG' end
                return nil
            end)
            natives.stub('print', function() end)
            natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
            return resource.load_resource(DIR, 'server')
        end

        local function defaults()
            return LoadingLogic.defaults()
        end

        local function adds()
            return natives.emitted('local', 'aeterna_core:selftest:add')
        end

        it('registers the four rows with owner first when core is already started', function()
            boot('started', defaults())
            local list = adds()
            assert.are.equal(4, #list)
            for _, e in ipairs(list) do assert.are.equal(OWNER, e.args[1]) end
            assert.are.equal('aeterna_loading.page_looked_right', list[4].args[2])
            assert.are.equal('eye', list[4].args[3].kind)
            assert.is_string(list[4].args[3].expect)
        end)

        it('sends nothing while core is not started, and registers again on every hello', function()
            boot('stopped', defaults())
            assert.are.equal(0, #adds())
            natives.fire('aeterna_core:hello')
            assert.are.equal(4, #adds())
            natives.fire('aeterna_core:hello')
            assert.are.equal(8, #adds())
        end)

        it('reports config_valid and local_paths_only through aeterna_core:selftest:report with owner', function()
            boot('started', defaults())
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_loading.config_valid', { kind = 'headless' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_loading.local_paths_only', { kind = 'headless' })
            local reps = natives.emitted('local', 'aeterna_core:selftest:report')
            assert.are.equal(2, #reps)
            assert.are.same({ OWNER, 'r1-abcd', 'aeterna_loading.config_valid', true, 'html/config.json is valid' },
                { reps[1].args[1], reps[1].args[2], reps[1].args[3], reps[1].args[4], reps[1].args[5] })
            assert.are.equal('aeterna_loading.local_paths_only', reps[2].args[3])
            assert.is_true(reps[2].args[4])
        end)

        it('fails config_valid and local_paths_only for a config with a remote background', function()
            boot('started', { serverName = 'X', background = 'https://example.invalid/bg.jpg' })
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_loading.config_valid', {})
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_loading.local_paths_only', {})
            local reps = natives.emitted('local', 'aeterna_core:selftest:report')
            assert.is_false(reps[1].args[4])
            assert.are.equal('bad fields: background', reps[1].args[5])
            assert.is_false(reps[2].args[4])
            assert.are.equal('not a local path: background', reps[2].args[5])
        end)

        it('ignores tests of other resources and events not fired by aeterna_core', function()
            boot('started', defaults())
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_core.core', {})
            natives.stub('GetInvokingResource', function() return 'someone_else' end)
            natives.fire('aeterna_core:selftest', 'r1-abcd', 'aeterna_loading.config_valid', {})
            assert.are.equal(0, #natives.emitted('local', 'aeterna_core:selftest:report'))
        end)
    end)

    describe('client script', function()
        local active
        local function boot()
            natives.reset({ resource = OWNER, side = 'client' })
            active = false
            natives.stub('GetIsLoadingScreenActive', function() return active end)
            natives.stub('NetworkIsSessionStarted', function() return true end)
            natives.stub('SendLoadingScreenMessage', function() end)
            natives.stub('ShutdownLoadingScreen', function() end)
            natives.stub('ShutdownLoadingScreenNui', function() end)
            natives.stub('LoadResourceFile', function() return nil end)
            natives.stub('GetInvokingResource', function() return 'aeterna_core' end)
            return resource.load_resource(DIR, 'client')
        end

        it('answers shut_down with the loading screen state', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r2-abcd', 'aeterna_loading.shut_down', { kind = 'ped', role = 'A' })
            active = true
            natives.fire('aeterna_core:selftest', 'r3-abcd', 'aeterna_loading.shut_down', { kind = 'ped', role = 'A' })
            local reps = natives.emitted('local', 'aeterna_core:selftest:report')
            assert.are.equal(2, #reps)
            assert.are.same({ OWNER, 'r2-abcd', 'aeterna_loading.shut_down', true, 'loading screen is shut down' },
                { reps[1].args[1], reps[1].args[2], reps[1].args[3], reps[1].args[4], reps[1].args[5] })
            assert.is_false(reps[2].args[4])
        end)

        it('marks the page_looked_right card ready so core can show it', function()
            boot()
            natives.fire('aeterna_core:selftest', 'r2-abcd', 'aeterna_loading.page_looked_right', { kind = 'eye' })
            local rep = natives.last_emitted('local', 'aeterna_core:selftest:report')
            assert.are.same({ OWNER, 'r2-abcd', 'aeterna_loading.page_looked_right', 'ready' },
                { rep.args[1], rep.args[2], rep.args[3], rep.args[4] })
        end)
    end)

    describe('edge to aeterna_core', function()
        it('never calls a core export and never lists core in the manifest', function()
            for _, path in ipairs({ '/server/main.lua', '/client/main.lua', '/shared/logic/selftest.lua',
                '/fxmanifest.lua' }) do
                local src = readFile(DIR .. path)
                assert.is_nil(src:find('exports%.aeterna_core'), path)
                assert.is_nil(src:find("exports%[%s*['\"]aeterna_core"), path)
                assert.is_nil(src:find('@aeterna_core/'), path)
            end
            assert.is_nil(readFile(DIR .. '/fxmanifest.lua'):find('dependenc'))
        end)
    end)
end)
