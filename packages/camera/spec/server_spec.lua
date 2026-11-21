-- spec/server_spec.lua -- aeterna_camera's server wiring under the devkit harness: tiles, net events, the HTTP
-- handler's writeHead headers, ownership, and the server-side self-tests.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function jpegData(n)
    local codec = CameraLogic.codec
    return codec.PREFIX .. codec.encode('\255\216\255' .. string.rep('B', n - 5) .. '\255\217')
end

describe('aeterna_camera server under the harness', function()
    local files, http, tests, tiles, toasts, reports, started, mayWriteCalls

    local function boot(opts)
        opts = opts or {}
        natives.reset({
            resource = 'aeterna_camera', side = 'server', players = { [1] = 'One', [2] = 'Two' },
            convars = { aeterna_core_log_level = 'error' },
        })
        files, http, tests, tiles, toasts, reports, mayWriteCalls = {}, nil, {}, {}, {}, {}, {}
        started = { ['screenshot-basic'] = opts.screenshot ~= false, aeterna_phonekit = true }
        natives.stub('GetResourceState', function(name) return started[name] and 'started' or 'missing' end)
        natives.stub('GetPlayerIdentifierByType', function(src) return 'license:p' .. tostring(src) end)
        natives.stub('IsPlayerAceAllowed', function() return false end)
        natives.stub('RegisterCommand', function() end)
        natives.stub('SaveResourceFile', function(res, path, data, len)
            assert.are.equal('aeterna_camera', res)
            assert.are.equal(#data, len)
            files[path] = data
            return true
        end)
        natives.stub('LoadResourceFile', function(res, path)
            assert.are.equal('aeterna_camera', res)
            return files[path]
        end)
        natives.stub('SetHttpHandler', function(fn) http = fn end)
        local kvp = natives.state().kvp
        natives.stub('StartFindKvp', function(prefix)
            local keys = {}
            for k in pairs(kvp) do if k:sub(1, #prefix) == prefix then keys[#keys + 1] = k end end
            table.sort(keys)
            return { keys = keys, i = 0 }
        end)
        natives.stub('FindKvp', function(h) h.i = h.i + 1 return h.keys[h.i] end)
        natives.stub('EndFindKvp', function() end)
        natives.stub_export('aeterna_core', 'addSelftest', function(name, meta) tests[#tests + 1] = { name, meta } return name end)
        natives.stub_export('aeterna_core', 'reportSelftest', function(runId, name, ok, detail, extra)
            reports[name] = { ok = ok, detail = detail, extra = extra }
            return true
        end)
        natives.stub_export('aeterna_core', 'selftestMayWrite', function(runId, name)
            mayWriteCalls[#mayWriteCalls + 1] = { runId, name }
            return opts.mayWrite ~= false
        end)
        natives.stub_export('aeterna_phonekit', 'addTile', function(app) tiles[#tiles + 1] = app return true end)
        natives.stub_export('aeterna_notify', 'notify', function(src, o) toasts[#toasts + 1] = { src, o } return true end)
        local res = resource.load_resource(DIR, 'server', {
            externals = { ['@aeterna_core/import.lua'] = DIR .. '/../core/import.lua' },
        })
        natives.advance(0)
        return res.exports
    end

    local function last(name)
        local e = natives.last_emitted('client', name)
        return e and e.args[1], e and e.target
    end

    local function open(src)
        natives.fire('aeterna_phonekit:app', src, { owner = 'aeterna_camera', id = 'camera' })
    end

    local function shootAndUpload(src, n)
        open(src)
        natives.fire_net('aeterna_camera:sv:shoot', src, { mode = 'back' })
        local cap = last('aeterna_camera:cl:capture')
        assert.is_table(cap)
        natives.advance(1100)
        natives.fire_net('aeterna_camera:sv:upload', src, { ticket = cap.ticket, data = jpegData(n or 64) })
        return last('aeterna_camera:cl:shot')
    end

    it('adds the Camera and Gallery tiles and registers the self-test rows', function()
        boot()
        assert.are.equal(2, #tiles)
        assert.are.same({ 'camera', 'gallery' }, { tiles[1].id, tiles[2].id })
        assert.are.same({ 'camera', 'image' }, { tiles[1].icon, tiles[2].icon })
        assert.are.equal(8, #tests)
        for _, row in ipairs(tests) do assert.is_truthy(row[1]:find('^aeterna_camera%.')) end
    end)

    it('takes a photo end to end: viewfinder, capture ticket, latent upload, file, toast and one saved event', function()
        boot()
        open(1)
        local vf, target = last('aeterna_camera:cl:viewfinder')
        assert.are.equal(1, target)
        assert.are.same({ count = 0, cap = 60 }, vf)
        local shot = shootAndUpload(1, 80)
        assert.is_true(shot.ok)
        assert.is_truthy(shot.id:match('^%x+$'))
        assert.is_not_nil(files['photos/' .. shot.id .. '.jpg'])
        local saved = natives.emitted('local', 'aeterna_camera:saved')
        assert.are.equal(1, #saved)
        assert.are.equal('lic:license:p1', saved[1].args[2].who)
        assert.are.equal(1, #toasts)
        assert.are.equal(1, toasts[1][1])
    end)

    it('refuses the shutter with camera.unavailable when screenshot-basic is not started', function()
        boot({ screenshot = false })
        open(1)
        natives.fire_net('aeterna_camera:sv:shoot', 1, { mode = 'back' })
        assert.are.same({ ok = false, reason = 'camera.unavailable' }, (last('aeterna_camera:cl:shot')))
        assert.is_nil(last('aeterna_camera:cl:capture'))
    end)

    it('serves the photo over HTTP and passes headers on every writeHead', function()
        boot()
        local shot = shootAndUpload(1)
        local function get(path, method)
            local out = {}
            local res = {
                writeHead = function(code, headers)
                    assert.is_table(headers)
                    assert.is_not_nil(next(headers), 'writeHead with an empty headers table')
                    out.code = code
                end,
                send = function(body) out.body = body end,
            }
            http({ method = method or 'GET', path = path, address = '10.0.0.1:1', headers = {} }, res)
            return out
        end
        local ok = get('/p/' .. shot.id .. '.jpg')
        assert.are.equal(200, ok.code)
        assert.are.equal(files['photos/' .. shot.id .. '.jpg'], ok.body)
        assert.are.equal(404, get('/p/' .. shot.id:upper() .. '.jpg').code)
        assert.are.equal(404, get('/p/' .. shot.id .. '.jpg', 'POST').code)
    end)

    it('drops a delete from another character and removes the owner\'s photo with an empty file', function()
        boot()
        local shot = shootAndUpload(1)
        natives.fire_net('aeterna_camera:sv:delete', 2, { id = shot.id })
        assert.are.equal(0, #natives.emitted('local', 'aeterna_camera:removed'))
        natives.fire_net('aeterna_camera:sv:delete', 1, { id = shot.id })
        local removed = natives.emitted('local', 'aeterna_camera:removed')
        assert.are.equal(1, #removed)
        assert.are.same({ shot.id, 'owner' }, { removed[1].args[1], removed[1].args[2] })
        assert.are.equal('', files['photos/' .. shot.id .. '.jpg'])
        local gallery = last('aeterna_camera:cl:gallery')
        assert.are.same({}, gallery.items)
    end)

    it('closes the viewfinder when phonekit reports the phone powered off', function()
        boot()
        open(1)
        natives.fire('aeterna_phonekit:power', 1, { on = false })
        assert.are.same({ ok = false, reason = 'power_off' }, (last('aeterna_camera:cl:shot')))
        natives.fire_net('aeterna_camera:sv:shoot', 1, { mode = 'back' })
        assert.are.same({ ok = false, reason = 'camera.failed' }, (last('aeterna_camera:cl:shot')))
    end)

    it('runs the server-side self-tests: headless PASS, mocks restored, nothing left behind', function()
        local api = boot()
        local before = {}
        for k, v in pairs(natives.state().kvp) do before[k] = v end
        for _, name in ipairs({ 'id_and_path_guard', 'http_router', 'store_roundtrip', 'caps', 'saved_hook',
            'screenshot_detect' }) do
            natives.fire('aeterna_core:selftest', 'r1-test', 'aeterna_camera.' .. name, { kind = 'x', side = 'server' })
        end
        natives.advance(100)
        for _, name in ipairs({ 'id_and_path_guard', 'http_router', 'screenshot_detect' }) do
            local r = reports['aeterna_camera.' .. name]
            assert.is_table(r, name)
            assert.are.equal(true, r.ok, name .. ': ' .. tostring(r.detail))
        end
        for _, name in ipairs({ 'store_roundtrip', 'caps', 'saved_hook' }) do
            local r = reports['aeterna_camera.' .. name]
            assert.is_table(r, name)
            assert.are.equal('mock', r.ok, name .. ': ' .. tostring(r.detail))
            assert.are.same({ restored = true }, r.extra)
        end
        assert.are.same(before, natives.state().kvp)
        assert.are.same({}, api.listPhotos('test:camera'))
        -- other resources' names are ignored
        reports = {}
        natives.fire('aeterna_core:selftest', 'r1-test', 'aeterna_other.caps', {})
        assert.is_nil(next(reports))
    end)

    local SHOOT = 'aeterna_camera.shoot_and_view'
    local CTX = { kind = 'eye', side = 'client', a = 1, destructive = true }

    -- What the client half of the eye test sends once the viewfinder is open.
    local function clientShoots(src)
        natives.fire_net('aeterna_camera:sv:shoot', src, { mode = 'back' })
        local cap = last('aeterna_camera:cl:capture')
        assert.is_table(cap)
        natives.advance(1100)
        natives.fire_net('aeterna_camera:sv:upload', src, { ticket = cap.ticket, data = jpegData(64) })
        return last('aeterna_camera:cl:shot')
    end

    it('shoot_and_view: selftestStarted opens the viewfinder for A; the photo passes the write guard, then the gallery opens', function()
        boot()
        natives.fire('aeterna_core:selftestStarted', 'r9-test', SHOOT, CTX)
        local vf, target = last('aeterna_camera:cl:viewfinder')
        assert.are.equal(1, target)
        assert.is_table(vf)
        local shot = clientShoots(1)
        assert.is_true(shot.ok)
        assert.are.same({ { 'r9-test', SHOOT } }, mayWriteCalls)
        assert.is_not_nil(files['photos/' .. shot.id .. '.jpg'])
        local gallery, gTarget = last('aeterna_camera:cl:gallery')
        assert.are.equal(1, gTarget)
        assert.are.equal(shot.id, gallery.items[1].id)
        natives.fire('aeterna_core:selftestEnd', 'r9-test', SHOOT)
        natives.advance(5000)
        natives.fire_net('aeterna_camera:sv:shoot', 1, { mode = 'back' })
        assert.are.same({ ok = false, reason = 'camera.failed' }, (last('aeterna_camera:cl:shot')))
    end)

    it('shoot_and_view: a closed write guard refuses the photo and writes nothing', function()
        boot({ mayWrite = false })
        natives.fire('aeterna_core:selftestStarted', 'r9-test', SHOOT, CTX)
        local shot = clientShoots(1)
        assert.are.same({ ok = false, reason = 'camera.failed' }, shot)
        assert.is_nil(next(files))
        assert.are.equal(0, #natives.emitted('local', 'aeterna_camera:saved'))
        assert.is_nil(last('aeterna_camera:cl:gallery'))
    end)

    it('shoot_and_view: ordinary photos never ask the write guard; other tests and other runs are ignored', function()
        boot()
        shootAndUpload(1)
        assert.are.same({}, mayWriteCalls)
        natives.fire('aeterna_core:selftestStarted', 'r9-test', 'aeterna_camera.viewfinder', CTX)
        natives.fire('aeterna_core:selftestStarted', 'r9-test', 'aeterna_other.shoot_and_view', CTX)
        assert.are.equal(1, #natives.emitted('client', 'aeterna_camera:cl:viewfinder'))
        natives.fire('aeterna_core:selftestStarted', 'r9-test', SHOOT, CTX)
        natives.fire('aeterna_core:selftestEnd', 'r8-other', SHOOT)
        natives.advance(5000)
        assert.is_true(clientShoots(1).ok)
    end)

    it('exports getPhoto, listPhotos, removePhoto and available', function()
        local api = boot()
        local shot = shootAndUpload(1)
        assert.are.equal(shot.id, api.getPhoto(shot.id).id)
        assert.are.equal(1, #api.listPhotos('lic:license:p1'))
        assert.is_true(api.available())
        assert.is_true(api.removePhoto(shot.id, 'moderation'))
        assert.is_false(api.removePhoto(shot.id))
        local removed = natives.last_emitted('local', 'aeterna_camera:removed')
        assert.are.equal('moderation', removed.args[2])
    end)
end)
