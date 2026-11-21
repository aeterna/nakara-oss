-- spec/selftest_spec.lua -- aeterna_camera self-test rows and their pure decision logic (shared/logic/selftests.lua).

local natives = require('helpers.natives')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load(name)
    return assert(loadfile(DIR .. '/shared/logic/' .. name .. '.lua'))()
end

describe('aeterna_camera self-tests', function()
    local ST, Ids, Router, Codec

    before_each(function()
        natives.reset({ resource = 'aeterna_camera', side = 'server' })
        Ids = load('ids')
        Codec = load('codec')
        Router = load('router')
        ST = load('selftests')
    end)

    local function t(key) return '<' .. key .. '>' end

    it('registers exactly the rows of the spec table', function()
        local rows = ST.rows(t)
        local byName = {}
        for i, r in ipairs(rows) do byName[r.name] = { i = i, meta = r.meta } end
        assert.are.equal(8, #rows)
        local expected = {
            ['aeterna_camera.id_and_path_guard'] = { kind = 'headless', players = 1, destructive = false },
            ['aeterna_camera.http_router'] = { kind = 'headless', players = 1, destructive = false },
            ['aeterna_camera.store_roundtrip'] = { kind = 'mock', players = 1, destructive = false },
            ['aeterna_camera.caps'] = { kind = 'mock', players = 1, destructive = false },
            ['aeterna_camera.saved_hook'] = { kind = 'mock', players = 1, destructive = false },
            ['aeterna_camera.screenshot_detect'] = { kind = 'headless', players = 1, destructive = false },
            ['aeterna_camera.viewfinder'] = { kind = 'eye', players = 1, destructive = false,
                expect = '<camera.selftest.viewfinder>' },
            ['aeterna_camera.shoot_and_view'] = { kind = 'eye', players = 1, destructive = true,
                expect = '<camera.selftest.shoot_and_view>', skipWhen = { resources = { 'screenshot-basic' } },
                timeout = 15000 },
        }
        for name, meta in pairs(expected) do
            assert.is_not_nil(byName[name], name)
            assert.are.same(meta, byName[name].meta, name)
        end
        -- spec order
        assert.are.equal('aeterna_camera.id_and_path_guard', rows[1].name)
        assert.are.equal('aeterna_camera.shoot_and_view', rows[8].name)
    end)

    it('every row passes aeterna_core\'s meta check', function()
        local CoreST = assert(loadfile(DIR .. '/../core/shared/logic/selftest.lua'))()
        for _, r in ipairs(ST.rows(t)) do
            local ok, err = CoreST.normalize(r.meta)
            assert.is_truthy(ok, r.name .. ': ' .. tostring(err))
        end
    end)

    it('id_and_path_guard passes with the real generator and fails on a bad one', function()
        local nextId = Ids.stream({ seed = 5, rand = math.random, now = os.time, clock = os.clock })
        local ok, detail = ST.guard(Ids.isId, nextId)
        assert.is_true(ok, detail)
        assert.is_false((ST.guard(Ids.isId, function() return 'ABC' end)))
        assert.is_false((ST.guard(function() return true end, nextId)))
        local same = nextId()
        assert.is_false((ST.guard(Ids.isId, function() return same end)))
    end)

    it('http_router: the cases pass against the real router and fail on a broken answer', function()
        local id = string.rep('c3', 16)
        local now = 0
        local router = Router.new({
            now = function() return now end,
            has = function(x) return x == id end,
            load = function(x) return x == id and Codec.tinyJpeg() or nil end,
        })
        local cases = ST.httpCases(id)
        local answers = {}
        for i, c in ipairs(cases) do
            local r = router:handle(c.req)
            answers[i] = { status = r.status, headers = r.headers }
        end
        assert.is_true(ST.judgeHttp(cases, answers))
        local broken = {}
        for i, a in ipairs(answers) do broken[i] = { status = a.status, headers = a.headers } end
        broken[1].headers = {}
        local ok, detail = ST.judgeHttp(cases, broken)
        assert.is_false(ok)
        assert.is_truthy(detail:find('header', 1, true))
        broken[1].headers = answers[1].headers
        broken[2].status = 200
        assert.is_false((ST.judgeHttp(cases, broken)))
        assert.is_false((ST.judgeHttp(cases, {})))
        local has429 = false
        for _, c in ipairs(cases) do if c.status == 429 then has429 = true end end
        assert.is_true(has429)
    end)

    it('saved_hook: exactly one event with every field', function()
        local id = string.rep('d4', 16)
        local photo = { id = id, who = 'test:camera', ts = 5, mode = 'back', bytes = 20,
            path = 'photos/' .. id .. '.jpg', urlPath = '/aeterna_camera/p/' .. id .. '.jpg' }
        assert.is_true(ST.checkSaved({ { 0, photo } }, id))
        assert.is_false((ST.checkSaved({}, id)))
        assert.is_false((ST.checkSaved({ { 0, photo }, { 0, photo } }, id)))
        local partial = {}
        for k, v in pairs(photo) do partial[k] = v end
        partial.urlPath = nil
        local ok, detail = ST.checkSaved({ { 0, partial } }, id)
        assert.is_false(ok)
        assert.is_truthy(detail:find('urlPath', 1, true))
    end)

    it('mock tests count as restored only when the total and the fake key are back', function()
        assert.is_true(ST.restored({ total = 10 }, { total = 10, count = 0, left = 0 }))
        assert.is_false(ST.restored({ total = 10 }, { total = 30, count = 0, left = 0 }))
        assert.is_false(ST.restored({ total = 10 }, { total = 10, count = 1, left = 0 }))
        assert.is_false(ST.restored({ total = 10 }, { total = 10, count = 0, left = 1 }))
    end)

    it('screenshot_detect passes either way and names the state', function()
        local ok1, d1 = ST.screenshotDetail(true)
        local ok2, d2 = ST.screenshotDetail(false)
        assert.is_true(ok1)
        assert.is_true(ok2)
        assert.are_not.equal(d1, d2)
    end)

    it('the viewfinder eye sequence opens, switches and closes inside the default timeout', function()
        local steps = ST.VIEWFINDER_STEPS
        assert.are.same({ 'open', 'selfie', 'close' }, { steps[1].action, steps[2].action, steps[3].action })
        assert.is_true(steps[#steps].at < 4500)
    end)

    it('the shoot_and_view client waits fit inside its 15 s timeout', function()
        assert.are.equal(5000, ST.SHOOT_WAIT_VIEWFINDER_MS)
        assert.are.equal(8000, ST.SHOOT_WAIT_GALLERY_MS)
        assert.is_true(ST.SHOOT_WAIT_VIEWFINDER_MS + ST.SHOOT_WAIT_GALLERY_MS < 15000)
    end)
end)
