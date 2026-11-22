-- spec/camera_spec.lua -- busted tests for aeterna_camera's pure logic (shared/logic/*.lua), cases 1-7 of the spec.

local natives = require('helpers.natives')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'

local function load(name)
    return assert(loadfile(DIR .. '/shared/logic/' .. name .. '.lua'))()
end

-- Deterministic stand-in for math.random(lo, hi).
local function seqRand(seed)
    local x = seed or 12345
    return function(lo, hi)
        x = (x * 1103515245 + 12345) % 2147483648
        return lo + x % (hi - lo + 1)
    end
end

-- KVP stand-in with the same calls the server wires to GetResourceKvpString / SetResourceKvp / StartFindKvp.
local function fakeKv()
    local data = {}
    return {
        data = data,
        get = function(k) return data[k] end,
        set = function(k, v) data[k] = v end,
        del = function(k) data[k] = nil end,
        keys = function(prefix)
            local out = {}
            for k in pairs(data) do
                if k:sub(1, #prefix) == prefix then out[#out + 1] = k end
            end
            table.sort(out)
            return out
        end,
    }
end

local function jpegOf(n)
    -- FF D8 FF ... FF D9, n bytes in total
    return '\255\216\255' .. string.rep('A', n - 5) .. '\255\217'
end

describe('aeterna_camera', function()
    local Codec, Ids, Tickets, Store, Service, Router, Settings

    before_each(function()
        natives.reset({ resource = 'aeterna_camera', side = 'server' })
        Codec = load('codec')
        Ids = load('ids')
        Tickets = load('tickets')
        Store = load('store')
        Service = load('service')
        Router = load('router')
        Settings = load('settings')
    end)

    describe('1. base64 and JPEG (codec.lua)', function()
        it('decodes the RFC 4648 vectors with and without padding', function()
            local vectors = {
                { '', '' }, { 'f', 'Zg==' }, { 'fo', 'Zm8=' }, { 'foo', 'Zm9v' },
                { 'foob', 'Zm9vYg==' }, { 'fooba', 'Zm9vYmE=' }, { 'foobar', 'Zm9vYmFy' },
            }
            for _, v in ipairs(vectors) do
                if v[1] ~= '' then
                    assert.are.equal(v[1], Codec.decode(v[2]))
                end
                assert.are.equal(v[2], Codec.encode(v[1]))
            end
        end)

        it('round-trips every byte value', function()
            local all = {}
            for i = 0, 255 do all[#all + 1] = string.char(i) end
            local bytes = table.concat(all):rep(5)
            assert.are.equal(bytes, Codec.decode(Codec.encode(bytes)))
        end)

        it('refuses invalid characters, misplaced padding and bad lengths', function()
            for _, bad in ipairs({ 'Zm9v!', 'Zm9', 'Zm=v', 'Z===', '====', 'Zm9v\nYmFy', 'Zm 9v', '' }) do
                local out, err = Codec.decode(bad)
                assert.is_nil(out, bad)
                assert.is_string(err)
            end
            assert.is_nil(Codec.decode(42))
        end)

        it('checks the JPEG start bytes FF D8 FF and end bytes FF D9', function()
            assert.is_true(Codec.isJpeg(jpegOf(10)))
            assert.is_false(Codec.isJpeg('\255\216\254AAAA\255\217'))
            assert.is_false(Codec.isJpeg('\255\216\255AAAA\255\218'))
            assert.is_false(Codec.isJpeg('\255\216\255'))
            assert.is_false(Codec.isJpeg(nil))
            assert.is_true(Codec.isJpeg(Codec.tinyJpeg()))
        end)

        it('accepts a JPEG data URI and returns its bytes', function()
            local bytes = jpegOf(300)
            local ok, out = Codec.checkUpload(Codec.PREFIX .. Codec.encode(bytes), 1000)
            assert.is_true(ok)
            assert.are.equal(bytes, out)
        end)

        it('refuses a wrong prefix, bad base64, a non-JPEG and a photo over maxBytes', function()
            local bytes = jpegOf(300)
            local b64 = Codec.encode(bytes)
            local cases = {
                { 'data:image/png;base64,' .. b64, 'prefix' },
                { Codec.PREFIX .. b64:sub(2), 'base64' },
                { Codec.PREFIX .. Codec.encode('plain text'), 'not jpeg' },
                { Codec.PREFIX .. Codec.encode(jpegOf(260)), 'too large', 255 },
                { 42, 'type' },
            }
            for _, c in ipairs(cases) do
                local ok, reason = Codec.checkUpload(c[1], c[3] or 1000)
                assert.is_false(ok)
                assert.are.equal(c[2], reason)
            end
        end)

        it('refuses data longer than ceil(maxBytes * 4 / 3) + 32 before decoding', function()
            assert.are.equal(math.ceil(900000 * 4 / 3) + 32, Codec.maxDataLen(900000))
            local decoded = false
            local real = Codec.decode
            Codec.decode = function(...) decoded = true return real(...) end
            local ok, reason = Codec.checkUpload(string.rep('A', Codec.maxDataLen(300) + 1), 300)
            Codec.decode = real
            assert.is_false(ok)
            assert.are.equal('too long', reason)
            assert.is_false(decoded)
        end)
    end)

    describe('2. ids, path guard and the HTTP router (ids.lua, router.lua)', function()
        -- A stream: its own xorshift state from `seed`, plus math.random, a running counter, the game timer and
        -- os.clock mixed into every draw.
        local function stream(seed, rand, now, clock)
            return Ids.stream({ seed = seed, rand = rand or seqRand(seed), now = now or function() return 0 end,
                clock = clock or function() return 0 end })
        end

        it('draws ids of 32 lowercase hex characters, never the same twice', function()
            local nextId = stream(7)
            local seen, bad, dup = {}, 0, 0
            for _ = 1, 2000 do
                local id = nextId()
                if #id ~= 32 or not id:match('^[0-9a-f]+$') then bad = bad + 1 end
                if seen[id] then dup = dup + 1 end
                seen[id] = true
            end
            assert.are.same({ 0, 0 }, { bad, dup })
        end)

        it('stays distinct when math.random, the timer and the clock repeat', function()
            local nextId = stream(11, function() return 0 end, function() return 5 end, function() return 1.5 end)
            local seen = {}
            for _ = 1, 500 do
                local id = nextId()
                assert.is_nil(seen[id])
                seen[id] = true
            end
        end)

        it('mixes the counter, timer and clock into every draw', function()
            local fixed = function() return 0 end
            local a = stream(3, fixed, fixed, fixed)
            local b = stream(3, fixed, function() return 1 end, fixed)
            local c = stream(3, fixed, fixed, function() return 0.001 end)
            local first = a()
            assert.are_not.equal(first, b())
            assert.are_not.equal(first, c())
            assert.are_not.equal(first, a())
        end)

        it('every bit of math.random reaches the id', function()
            local fixed = function() return 0 end
            local base = stream(4, fixed, fixed, fixed)()
            for bit = 0, 15 do
                local flipped = stream(4, function() return 1 << bit end, fixed, fixed)()
                assert.are_not.equal(base, flipped, 'bit ' .. bit)
            end
        end)

        it('two streams with different seeds give different ids from the same inputs', function()
            local fixed = function() return 0 end
            local tickets, photos = stream(1, fixed, fixed, fixed), stream(2, fixed, fixed, fixed)
            for _ = 1, 50 do assert.are_not.equal(tickets(), photos()) end
        end)

        it('accepts only exact 32-character lowercase hex ids', function()
            local good = string.rep('a1', 16)
            assert.is_true(Ids.isId(good))
            for _, bad in ipairs({ string.rep('A1', 16), good:sub(2), good .. '0', '../' .. good:sub(4),
                good:sub(1, 31) .. '/', good:sub(1, 31) .. 'g', 42, nil }) do
                assert.is_false(Ids.isId(bad), tostring(bad))
            end
            assert.are.equal('/aeterna_camera/p/' .. good .. '.jpg', Ids.urlPath(good))
            assert.are.equal('photos/' .. good .. '.jpg', Ids.path(good))
        end)

        local ID = string.rep('0f', 16)
        local function router(now)
            local t = { now = now or 0 }
            local r = Router.new({
                now = function() return t.now end,
                has = function(id) return id == ID end,
                load = function(id) return id == ID and 'JPEGBYTES' or nil end,
            })
            return r, t
        end

        local function nonEmpty(h)
            return type(h) == 'table' and next(h) ~= nil
        end

        it('answers 200 with the image headers for a known id', function()
            local r = router()
            local res = r:handle({ method = 'GET', path = '/p/' .. ID .. '.jpg', address = '1.2.3.4:5000' })
            assert.are.equal(200, res.status)
            assert.are.equal('image/jpeg', res.headers['Content-Type'])
            assert.are.equal('private, max-age=86400', res.headers['Cache-Control'])
            assert.are.equal('nosniff', res.headers['X-Content-Type-Options'])
            assert.are.equal('JPEGBYTES', res.body)
        end)

        it('splits the query string off before routing', function()
            local r = router()
            local res = r:handle({ method = 'GET', path = '/p/' .. ID .. '.jpg?x=1&y=../../a', address = '1.2.3.4' })
            assert.are.equal(200, res.status)
        end)

        it('answers 404 with an empty body for every other path, method or id', function()
            local r = router()
            local upper = ID:upper()
            local paths = {
                '/p/../' .. ID .. '.jpg', '/p/' .. upper .. '.jpg', '/p/' .. ID:sub(2) .. '.jpg',
                '/p/' .. ID .. '0.jpg', '/p/' .. ID .. '.png', '/p/' .. ID, '/p/' .. string.rep('1', 32) .. '.jpg',
                '/', '', '/list', '/p/', '/p/' .. ID .. '.jpg/x', '/x/' .. ID .. '.jpg', '/p/%2e%2e/' .. ID .. '.jpg',
            }
            for _, p in ipairs(paths) do
                local res = r:handle({ method = 'GET', path = p, address = '1.2.3.4' })
                assert.are.equal(404, res.status, p)
                assert.are.equal('', res.body)
                assert.is_true(nonEmpty(res.headers))
            end
            for _, m in ipairs({ 'POST', 'PUT', 'DELETE', 'HEAD', 'OPTIONS' }) do
                local res = r:handle({ method = m, path = '/p/' .. ID .. '.jpg', address = '1.2.3.4' })
                assert.are.equal(404, res.status, m)
            end
            local res = r:handle({ method = 'GET', path = 42, address = '1.2.3.4' })
            assert.are.equal(404, res.status)
        end)

        it('answers 404 when the file is gone or empty', function()
            local r = Router.new({ now = function() return 0 end, has = function() return true end,
                load = function() return '' end })
            assert.are.equal(404, r:handle({ method = 'GET', path = '/p/' .. ID .. '.jpg', address = 'a' }).status)
        end)

        it('answers 429 after 60 requests in 10 s from one address, port ignored, and recovers', function()
            local r, t = router()
            for i = 1, 60 do
                local res = r:handle({ method = 'GET', path = '/nope', address = '9.9.9.9:' .. i })
                assert.are.equal(404, res.status)
            end
            local blocked = r:handle({ method = 'GET', path = '/p/' .. ID .. '.jpg', address = '9.9.9.9:1' })
            assert.are.equal(429, blocked.status)
            assert.are.equal('', blocked.body)
            assert.is_true(nonEmpty(blocked.headers))
            -- another address is not affected
            assert.are.equal(200, r:handle({ method = 'GET', path = '/p/' .. ID .. '.jpg', address = '8.8.8.8' }).status)
            t.now = 10001
            assert.are.equal(200, r:handle({ method = 'GET', path = '/p/' .. ID .. '.jpg', address = '9.9.9.9:1' }).status)
        end)

        it('passes a non-empty headers table on every answer', function()
            local r = router()
            local reqs = {
                { method = 'GET', path = '/p/' .. ID .. '.jpg' }, { method = 'GET', path = '/x' },
                { method = 'POST', path = '/p/' .. ID .. '.jpg' }, {},
            }
            for _, q in ipairs(reqs) do
                q.address = '7.7.7.7'
                assert.is_true(nonEmpty(r:handle(q).headers))
            end
        end)
    end)

    -- A service over a fake KVP, a fake disk and a fake clock.
    local function setup(cfg)
        cfg = cfg or {}
        local kv = fakeKv()
        local disk, events, warns = {}, {}, {}
        local clock = { ms = 100000, s = 1700000000 }
        local avail = { on = true }
        local store = Store.new({ kv = kv, json = json, perCharacter = cfg.perCharacter or 3,
            maxTotalBytes = cfg.maxTotalBytes or 100000, perAccountBytes = cfg.perAccountBytes })
        local accts = cfg.accts or {}
        local newId = Ids.stream({ seed = 99, rand = seqRand(99), now = function() return clock.ms end,
            clock = function() return 0 end })
        local tickets = Tickets.new({ now = function() return clock.ms end, newId = newId })
        local svc = Service.new({
            store = store,
            tickets = tickets,
            newId = newId,
            now = function() return clock.ms end,
            clock = function() return clock.s end,
            available = function() return avail.on end,
            writePhoto = function(id, bytes) disk[id] = bytes return true end,
            acctOf = function(src) return accts[src] or ('license:s' .. tostring(src)) end,
            emit = function(name, ...) events[#events + 1] = { name = name, args = { ... } } end,
            warn = function(msg, fields) warns[#warns + 1] = { msg = msg, fields = fields } end,
        }, { cooldownMs = cfg.cooldownMs or 3000, maxBytes = cfg.maxBytes or 5000, perCharacter = cfg.perCharacter or 3 })
        return { svc = svc, store = store, tickets = tickets, kv = kv, disk = disk, events = events, warns = warns,
            clock = clock, avail = avail }
    end

    local function dataOf(n)
        return Codec.PREFIX .. Codec.encode(jpegOf(n))
    end

    -- open, shoot, upload: returns the upload result
    local function takePhoto(e, src, who, n)
        e.svc:openViewfinder(src, who)
        local ok, ticket = e.svc:shoot(src, who, 'back')
        assert.is_true(ok, tostring(ticket))
        e.clock.ms = e.clock.ms + 5000
        return e.svc:upload(src, who, { ticket = ticket, data = dataOf(n or 100) })
    end

    describe('3. index (store.lua)', function()
        it('adds a photo: record, newest-first list and total', function()
            local e = setup()
            local id1 = select(2, takePhoto(e, 1, 'cid:A', 100)).id
            local id2 = select(2, takePhoto(e, 1, 'cid:A', 200)).id
            assert.are.same({ id2, id1 }, e.store:list('cid:A'))
            assert.are.equal(300, e.store:total())
            local rec = e.store:get(id1)
            assert.are.equal('cid:A', rec.who)
            assert.are.equal(100, rec.bytes)
            assert.are.equal('back', rec.mode)
            assert.is_number(rec.ts)
            assert.is_string(e.kv.data['aeterna_camera:photo:v1:' .. id1])
            assert.is_string(e.kv.data['aeterna_camera:photos:v1:cid:A'])
            assert.are.equal('300', e.kv.data['aeterna_camera:total:v1'])
        end)

        it('refuses at the per-character cap with camera.full', function()
            local e = setup({ perCharacter = 2 })
            takePhoto(e, 1, 'cid:A')
            takePhoto(e, 1, 'cid:A')
            assert.are.same({ false, 'camera.full' }, { e.store:check('cid:A', 0) })
            e.clock.ms = e.clock.ms + 5000
            assert.are.same({ false, 'camera.full' }, { e.svc:shoot(1, 'cid:A', 'back') })
            -- another character still has room
            assert.is_true(e.store:check('cid:B', 0))
            assert.are.same({ false, 'camera.full' }, { e.store:add(string.rep('ab', 16), { who = 'cid:A', ts = 1, mode = 'back', bytes = 1 }) })
        end)

        it('refuses at the total cap with camera.disk_full', function()
            local e = setup({ maxTotalBytes = 250, perCharacter = 10 })
            takePhoto(e, 1, 'cid:A', 200)
            assert.are.same({ false, 'camera.disk_full' }, { e.store:check('cid:B', 100) })
            assert.is_true(e.store:check('cid:B', 50))
            local status, reason = takePhoto(e, 2, 'cid:B', 100)
            assert.are.equal('refused', status)
            assert.are.equal('camera.disk_full', reason)
        end)

        it('a removal frees the bytes and takes the id out of its list', function()
            local e = setup()
            local p1 = select(2, takePhoto(e, 1, 'cid:A', 100))
            local p2 = select(2, takePhoto(e, 1, 'cid:A', 200))
            assert.is_true(e.svc:delete(1, 'cid:A', p1.id))
            assert.are.equal(200, e.store:total())
            assert.are.same({ p2.id }, e.store:list('cid:A'))
            assert.is_nil(e.store:get(p1.id))
            assert.is_nil(e.kv.data['aeterna_camera:photo:v1:' .. p1.id])
            assert.are.equal('', e.disk[p1.id])
            e.clock.ms = e.clock.ms + 3000
            assert.is_true(e.svc:delete(1, 'cid:A', p2.id))
            assert.are.equal(0, e.store:total())
            assert.are.same({}, e.store:list('cid:A'))
        end)

        it('repairs a wrong total at start and reports the change once', function()
            local e = setup()
            takePhoto(e, 1, 'cid:A', 100)
            takePhoto(e, 2, 'cid:B', 150)
            e.kv.data['aeterna_camera:total:v1'] = '9999'
            local changed, before, after = e.store:repair()
            assert.is_true(changed)
            assert.are.equal(9999, before)
            assert.are.equal(250, after)
            assert.are.equal(250, e.store:total())
            assert.is_false((e.store:repair()))
        end)

        it('treats a missing or broken total as 0 and repairs it', function()
            local e = setup()
            takePhoto(e, 1, 'cid:A', 100)
            e.kv.data['aeterna_camera:total:v1'] = 'not json'
            assert.are.equal(0, e.store:total())
            assert.is_true((e.store:repair()))
            assert.are.equal(100, e.store:total())
        end)
    end)

    describe('3b. account cap and file reuse (store.lua)', function()
        it('caps the bytes of all characters of one account with camera.full; other accounts keep room', function()
            local e = setup({ perAccountBytes = 250, perCharacter = 10,
                accts = { [1] = 'license:x', [2] = 'license:x', [3] = 'license:y' } })
            assert.are.equal('saved', (takePhoto(e, 1, 'cid:A', 200)))
            e.svc:openViewfinder(2, 'cid:B')
            assert.are.same({ false, 'camera.full' }, { e.store:check('cid:B', 100, 'license:x') })
            local ok, ticket = e.svc:shoot(2, 'cid:B', 'back')
            assert.is_true(ok)
            e.clock.ms = e.clock.ms + 5000
            local status, reason = e.svc:upload(2, 'cid:B', { ticket = ticket, data = dataOf(100) })
            assert.are.same({ 'refused', 'camera.full' }, { status, reason })
            assert.are.equal('saved', (takePhoto(e, 3, 'cid:C', 200)))
            assert.are.equal('200', e.kv.data['aeterna_camera:acct:v1:license:x'])
        end)

        it('a deleted photo gives its bytes back to the account and the account key goes when it is empty', function()
            local e = setup({ perAccountBytes = 250, perCharacter = 10, accts = { [1] = 'license:x', [2] = 'license:x' } })
            local p = select(2, takePhoto(e, 1, 'cid:A', 200))
            assert.is_true(e.svc:delete(1, 'cid:A', p.id))
            assert.is_nil(e.kv.data['aeterna_camera:acct:v1:license:x'])
            assert.are.equal('saved', (takePhoto(e, 2, 'cid:B', 200)))
        end)

        it('reuses the empty file of a deleted photo for the next photo, so a shoot-delete loop adds no files', function()
            local e = setup({ perCharacter = 10 })
            local first = select(2, takePhoto(e, 1, 'cid:A', 100))
            for _ = 1, 5 do
                assert.is_true(e.svc:delete(1, 'cid:A', e.store:list('cid:A')[1]))
                e.clock.ms = e.clock.ms + 5000
                takePhoto(e, 1, 'cid:A', 100)
            end
            local files = 0
            for _ in pairs(e.disk) do files = files + 1 end
            assert.are.equal(1, files)
            assert.are.same({ first.id }, e.store:list('cid:A'))
        end)

        it('a free id that is taken again is never handed out twice', function()
            local e = setup({ perCharacter = 10 })
            local p1 = select(2, takePhoto(e, 1, 'cid:A', 100))
            local p2 = select(2, takePhoto(e, 1, 'cid:A', 100))
            e.svc:delete(1, 'cid:A', p1.id)
            e.clock.ms = e.clock.ms + 5000
            e.svc:delete(1, 'cid:A', p2.id)
            local a = select(2, takePhoto(e, 1, 'cid:A', 100))
            local b = select(2, takePhoto(e, 1, 'cid:A', 100))
            local c = select(2, takePhoto(e, 1, 'cid:A', 100))
            assert.are_not.equal(a.id, b.id)
            assert.are_not.equal(b.id, c.id)
            assert.are_not.equal(a.id, c.id)
            assert.is_nil(e.kv.data['aeterna_camera:free:v1'])
        end)

        it('repairs account totals at start', function()
            local e = setup({ perAccountBytes = 1000, perCharacter = 10, accts = { [1] = 'license:x' } })
            takePhoto(e, 1, 'cid:A', 100)
            e.kv.data['aeterna_camera:acct:v1:license:x'] = '777'
            e.kv.data['aeterna_camera:acct:v1:license:gone'] = '50'
            assert.is_true((e.store:repair()))
            assert.are.equal('100', e.kv.data['aeterna_camera:acct:v1:license:x'])
            assert.is_nil(e.kv.data['aeterna_camera:acct:v1:license:gone'])
        end)
    end)

    describe('4. ownership', function()
        it('limits deletes of one player to one per Config.cooldownMs', function()
            local e = setup({ cooldownMs = 3000 })
            local p1 = select(2, takePhoto(e, 1, 'cid:A'))
            local p2 = select(2, takePhoto(e, 1, 'cid:A'))
            local p3 = select(2, takePhoto(e, 2, 'cid:B'))
            assert.is_true(e.svc:delete(1, 'cid:A', p1.id))
            e.clock.ms = e.clock.ms + 2999
            assert.are.same({ false, 'camera.slow' }, { e.svc:delete(1, 'cid:A', p2.id) })
            assert.is_not_nil(e.store:get(p2.id))
            -- another player is not held back
            assert.is_true(e.svc:delete(2, 'cid:B', p3.id))
            e.clock.ms = e.clock.ms + 1
            assert.is_true(e.svc:delete(1, 'cid:A', p2.id))
        end)

        it('a refused delete does not start the cooldown', function()
            local e = setup({ cooldownMs = 3000 })
            local p = select(2, takePhoto(e, 1, 'cid:A'))
            assert.is_false(e.svc:delete(1, 'cid:A', string.rep('9', 32)))
            assert.is_true(e.svc:delete(1, 'cid:A', p.id))
        end)

        it('drops a delete of another character\'s photo', function()
            local e = setup()
            local p = select(2, takePhoto(e, 1, 'cid:A', 100))
            assert.is_false(e.svc:delete(2, 'cid:B', p.id))
            assert.is_false(e.svc:delete(1, 'cid:A2', p.id))
            assert.is_false(e.svc:delete(1, 'cid:A', string.rep('9', 32)))
            assert.is_false(e.svc:delete(1, 'cid:A', 'not an id'))
            assert.is_not_nil(e.store:get(p.id))
            assert.are.equal(100, e.store:total())
            for _, ev in ipairs(e.events) do assert.are_not.equal('aeterna_camera:removed', ev.name) end
        end)

        it('fires removed with owner, admin or the given reason', function()
            local e = setup()
            local p1 = select(2, takePhoto(e, 1, 'cid:A'))
            local p2 = select(2, takePhoto(e, 1, 'cid:A'))
            local p3 = select(2, takePhoto(e, 1, 'cid:A'))
            e.svc:delete(1, 'cid:A', p1.id)
            e.svc:remove(p2.id)
            e.svc:remove(p3.id, 'rule 4')
            local removed = {}
            for _, ev in ipairs(e.events) do
                if ev.name == 'aeterna_camera:removed' then removed[#removed + 1] = ev.args end
            end
            assert.are.same({ { p1.id, 'owner' }, { p2.id, 'admin' }, { p3.id, 'rule 4' } }, removed)
            assert.is_false(e.svc:remove(p3.id, 'again'))
        end)
    end)

    describe('5. shoot gate', function()
        local function noTicket(e, src)
            assert.is_nil(e.tickets:peek(src))
        end

        it('refuses with no viewfinder open', function()
            local e = setup()
            assert.are.same({ false, 'camera.failed' }, { e.svc:shoot(1, 'cid:A', 'back') })
            noTicket(e, 1)
            e.svc:openViewfinder(1, 'cid:A')
            e.svc:close(1)
            assert.are.same({ false, 'camera.failed' }, { e.svc:shoot(1, 'cid:A', 'back') })
            noTicket(e, 1)
        end)

        it('refuses inside the cooldown with camera.slow', function()
            local e = setup({ cooldownMs = 3000 })
            e.svc:openViewfinder(1, 'cid:A')
            assert.is_true((e.svc:shoot(1, 'cid:A', 'back')))
            e.tickets:drop(1)
            e.clock.ms = e.clock.ms + 2999
            assert.are.same({ false, 'camera.slow' }, { e.svc:shoot(1, 'cid:A', 'back') })
            noTicket(e, 1)
            e.clock.ms = e.clock.ms + 1
            assert.is_true((e.svc:shoot(1, 'cid:A', 'selfie')))
        end)

        it('refuses at the cap with camera.full', function()
            local e = setup({ perCharacter = 1 })
            takePhoto(e, 1, 'cid:A')
            e.clock.ms = e.clock.ms + 5000
            assert.are.same({ false, 'camera.full' }, { e.svc:shoot(1, 'cid:A', 'back') })
            noTicket(e, 1)
        end)

        it('refuses at the total cap with camera.disk_full and warns at most once an hour', function()
            local e = setup({ maxTotalBytes = 100, perCharacter = 10 })
            takePhoto(e, 1, 'cid:A', 100)
            local function diskWarns()
                local n = 0
                for _, w in ipairs(e.warns) do if w.msg:find('disk', 1, true) then n = n + 1 end end
                return n
            end
            for _ = 1, 3 do
                e.clock.ms = e.clock.ms + 5000
                assert.are.same({ false, 'camera.disk_full' }, { e.svc:shoot(1, 'cid:A', 'back') })
            end
            assert.are.equal(1, diskWarns())
            e.clock.ms = e.clock.ms + 3600000
            e.svc:shoot(1, 'cid:A', 'back')
            assert.are.equal(2, diskWarns())
            noTicket(e, 1)
        end)

        it('refuses with camera.unavailable when screenshot-basic is not started', function()
            local e = setup()
            e.avail.on = false
            e.svc:openViewfinder(1, 'cid:A')
            assert.are.same({ false, 'camera.unavailable' }, { e.svc:shoot(1, 'cid:A', 'back') })
            noTicket(e, 1)
        end)

        it('reports the count and cap when the viewfinder opens', function()
            local e = setup({ perCharacter = 3 })
            takePhoto(e, 1, 'cid:A')
            assert.are.same({ count = 1, cap = 3 }, e.svc:openViewfinder(1, 'cid:A'))
        end)
    end)

    describe('6. tickets', function()
        it('issues 32-hex tickets bound to source and character', function()
            local e = setup()
            e.svc:openViewfinder(1, 'cid:A')
            local ok, ticket = e.svc:shoot(1, 'cid:A', 'back')
            assert.is_true(ok)
            assert.is_true(Ids.isId(ticket))
            assert.are.equal(ticket, e.tickets:peek(1))
        end)

        it('is single use: a second upload with the same ticket is dropped', function()
            local e = setup()
            e.svc:openViewfinder(1, 'cid:A')
            local _, ticket = e.svc:shoot(1, 'cid:A', 'back')
            assert.are.equal('saved', (e.svc:upload(1, 'cid:A', { ticket = ticket, data = dataOf(100) })))
            assert.are.same({ 'dropped', 'unknown' }, { e.svc:upload(1, 'cid:A', { ticket = ticket, data = dataOf(100) }) })
            assert.are.equal(1, #e.store:list('cid:A'))
        end)

        it('expires after 30 s', function()
            local e = setup()
            e.svc:openViewfinder(1, 'cid:A')
            local _, ticket = e.svc:shoot(1, 'cid:A', 'back')
            e.clock.ms = e.clock.ms + 30001
            assert.are.same({ 'dropped', 'expired' }, { e.svc:upload(1, 'cid:A', { ticket = ticket, data = dataOf(100) }) })
            assert.are.equal(0, e.store:total())
        end)

        it('is still valid at exactly 30 s', function()
            local e = setup()
            e.svc:openViewfinder(1, 'cid:A')
            local _, ticket = e.svc:shoot(1, 'cid:A', 'back')
            e.clock.ms = e.clock.ms + 30000
            assert.are.equal('saved', (e.svc:upload(1, 'cid:A', { ticket = ticket, data = dataOf(100) })))
        end)

        it('drops an upload from another source or a switched character, and the ticket is gone after', function()
            local e = setup()
            e.svc:openViewfinder(1, 'cid:A')
            local _, ticket = e.svc:shoot(1, 'cid:A', 'back')
            assert.are.same({ 'dropped', 'source' }, { e.svc:upload(2, 'cid:A', { ticket = ticket, data = dataOf(100) }) })
            assert.are.same({ 'dropped', 'unknown' }, { e.svc:upload(1, 'cid:A', { ticket = ticket, data = dataOf(100) }) })
            e.clock.ms = e.clock.ms + 5000
            local _, t2 = e.svc:shoot(1, 'cid:A', 'back')
            assert.are.same({ 'dropped', 'character' }, { e.svc:upload(1, 'cid:B', { ticket = t2, data = dataOf(100) }) })
            assert.are.equal(0, e.store:total())
        end)

        it('a new shoot replaces the old ticket', function()
            local e = setup({ cooldownMs = 0 })
            e.svc:openViewfinder(1, 'cid:A')
            local _, t1 = e.svc:shoot(1, 'cid:A', 'back')
            e.clock.ms = e.clock.ms + 1
            local _, t2 = e.svc:shoot(1, 'cid:A', 'selfie')
            assert.are_not.equal(t1, t2)
            assert.are.equal(t2, e.tickets:peek(1))
            assert.are.same({ 'dropped', 'unknown' }, { e.svc:upload(1, 'cid:A', { ticket = t1, data = dataOf(100) }) })
            local status, photo = e.svc:upload(1, 'cid:A', { ticket = t2, data = dataOf(100) })
            assert.are.equal('saved', status)
            assert.are.equal('selfie', photo.mode)
        end)

        it('refuses an upload over the length cap before decoding, and the ticket is spent', function()
            local e = setup({ maxBytes = 1000 })
            e.svc:openViewfinder(1, 'cid:A')
            local _, ticket = e.svc:shoot(1, 'cid:A', 'back')
            local decoded = false
            local real = Codec.decode
            Codec.decode = function(...) decoded = true return real(...) end
            local status, reason, detail = e.svc:upload(1, 'cid:A',
                { ticket = ticket, data = string.rep('A', Codec.maxDataLen(1000) + 1) })
            Codec.decode = real
            assert.are.equal('refused', status)
            assert.are.equal('camera.failed', reason)
            assert.are.equal('too long', detail)
            assert.is_false(decoded)
            assert.is_nil(e.tickets:peek(1))
            assert.is_true(#e.warns >= 1)
            for _, w in ipairs(e.warns) do
                for _, v in pairs(w.fields or {}) do assert.is_true(#tostring(v) < 200) end
            end
        end)

        it('drops a payload with a malformed ticket without touching the real one', function()
            local e = setup()
            e.svc:openViewfinder(1, 'cid:A')
            local _, ticket = e.svc:shoot(1, 'cid:A', 'back')
            for _, bad in ipairs({ ticket:upper(), ticket:sub(2), 42 }) do
                local status = e.svc:upload(1, 'cid:A', { ticket = bad, data = dataOf(100) })
                assert.are.equal('dropped', status)
            end
            assert.are.equal('dropped', (e.svc:upload(1, 'cid:A', 'x')))
            assert.are.equal('dropped', (e.svc:upload(1, 'cid:A', { ticket = ticket, data = dataOf(100), extra = 1 })))
            assert.are.equal(ticket, e.tickets:peek(1))
        end)

        it('drop() forgets the player\'s ticket, viewfinder and cooldown', function()
            local e = setup()
            e.svc:openViewfinder(1, 'cid:A')
            e.svc:shoot(1, 'cid:A', 'back')
            e.svc:drop(1)
            assert.is_nil(e.tickets:peek(1))
            assert.is_false(e.svc:isOpen(1))
        end)
    end)

    describe('7. hook', function()
        it('a successful save fires exactly one aeterna_camera:saved with every field', function()
            local e = setup()
            local status, photo = takePhoto(e, 4, 'lic:abc', 120)
            assert.are.equal('saved', status)
            local saved = {}
            for _, ev in ipairs(e.events) do
                if ev.name == 'aeterna_camera:saved' then saved[#saved + 1] = ev end
            end
            assert.are.equal(1, #saved)
            local src, p = saved[1].args[1], saved[1].args[2]
            assert.are.equal(4, src)
            assert.are.same({
                id = photo.id, who = 'lic:abc', ts = e.clock.s, mode = 'back', bytes = 120,
                path = 'photos/' .. photo.id .. '.jpg', urlPath = '/aeterna_camera/p/' .. photo.id .. '.jpg',
            }, p)
            assert.are.equal(jpegOf(120), e.disk[photo.id])
        end)

        it('a refused or dropped upload fires nothing and writes nothing', function()
            local e = setup()
            e.svc:openViewfinder(1, 'cid:A')
            local _, ticket = e.svc:shoot(1, 'cid:A', 'back')
            e.svc:upload(1, 'cid:A', { ticket = ticket, data = Codec.PREFIX .. Codec.encode('nope') })
            e.svc:upload(1, 'cid:A', { ticket = ticket, data = dataOf(100) })
            assert.are.equal(0, #e.events)
            assert.is_nil(next(e.disk))
        end)

        it('a failed file write refuses with camera.failed and leaves the index alone', function()
            local e = setup()
            e.svc.deps.writePhoto = function() return false end
            local status, reason = takePhoto(e, 1, 'cid:A', 100)
            assert.are.equal('refused', status)
            assert.are.equal('camera.failed', reason)
            assert.are.equal(0, e.store:total())
            assert.are.equal(0, #e.events)
        end)

        it('exports read back the same photo views', function()
            local e = setup()
            local p1 = select(2, takePhoto(e, 1, 'cid:A', 100))
            local p2 = select(2, takePhoto(e, 1, 'cid:A', 110))
            assert.are.same(p1, e.svc:getPhoto(p1.id))
            assert.is_nil(e.svc:getPhoto('nope'))
            assert.are.same({ p2, p1 }, e.svc:listPhotos('cid:A'))
            assert.are.same({ { id = p2.id, ts = p2.ts, mode = 'back', bytes = 110 },
                { id = p1.id, ts = p1.ts, mode = 'back', bytes = 100 } }, e.svc:gallery('cid:A'))
        end)
    end)

    describe('config (settings.lua)', function()
        it('keeps valid values and falls back with one warn per bad key', function()
            local warns = {}
            local cfg = Settings.check({ perCharacter = 0, maxBytes = 50, maxTotalMB = 'x', quality = 0.8, cooldownMs = 1000 },
                function(msg, f) warns[#warns + 1] = f.key end)
            assert.are.same({ perCharacter = 60, maxBytes = 900000, maxTotalMB = 1024, perAccountMB = 200, quality = 0.8,
                cooldownMs = 1000 }, cfg)
            table.sort(warns)
            assert.are.same({ 'maxBytes', 'maxTotalMB', 'perCharacter' }, warns)
            local defaults = Settings.check(nil, function() end)
            assert.are.equal(60, defaults.perCharacter)
            assert.are.equal(3000, defaults.cooldownMs)
        end)
    end)
end)
