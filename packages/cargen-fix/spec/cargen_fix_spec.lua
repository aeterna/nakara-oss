-- cargen_fix_spec.lua -- nakara_cargen_fix: pure logic + the real client scripts under the devkit harness.

local natives = require('helpers.natives')
local resource = require('helpers.resource')

local HERE = debug.getinfo(1, 'S').source:match('^@(.*)/[^/]*$') or '.'
local DIR = HERE .. '/..'
local NATIVE = 'SetAllVehicleGeneratorsActiveInArea'
local WORLD = { -20000.0, -20000.0, -2000.0, 20000.0, 20000.0, 5000.0 }

local function read(path)
    local f = assert(io.open(path, 'rb'))
    local s = f:read('*a')
    f:close()
    return s
end

describe('nakara_cargen_fix', function()
    describe('logic (client/logic.lua)', function()
        local L
        before_each(function()
            natives.reset()
            L = assert(loadfile(DIR .. '/client/logic.lua'))()
        end)

        it('is never networked', function()
            assert.is_false(L.NETWORKED)
        end)

        it('disables generators while relief is on and restores vanilla when off', function()
            assert.is_false(L.activeFlag(true))
            assert.is_true(L.activeFlag(false))
        end)

        it('only restores when this resource stops', function()
            assert.is_true(L.shouldRestore('nakara_cargen_fix', 'nakara_cargen_fix'))
            assert.is_false(L.shouldRestore('other_resource', 'nakara_cargen_fix'))
            assert.is_false(L.shouldRestore(nil, 'nakara_cargen_fix'))
        end)

        it('defaults to the whole-map box', function()
            assert.are.same(WORLD, L.resolveArea(nil))
            assert.are.same(WORLD, L.DEFAULT_AREA)
        end)

        it('accepts a valid custom box and rejects malformed ones', function()
            assert.are.same({ 0, 0, 0, 10, 10, 10 }, L.resolveArea({ 0, 0, 0, 10, 10, 10 }))
            assert.are.same(WORLD, L.resolveArea({ 0, 0, 0, 10, 10 }))            -- too short
            assert.are.same(WORLD, L.resolveArea({ 0, 0, 0, '10', 10, 10 }))      -- not a number
            assert.are.same(WORLD, L.resolveArea({ 10, 0, 0, 0, 10, 10 }))        -- min >= max
            assert.are.same(WORLD, L.resolveArea({ 0, 0, 0 / 0, 10, 10, 10 }))    -- NaN
        end)

        it('defaults the re-assert interval to 5000 ms and rejects too-small values', function()
            assert.are.equal(5000, L.resolveInterval(nil))
            assert.are.equal(5000, L.resolveInterval(999))
            assert.are.equal(5000, L.resolveInterval('5000'))
            assert.are.equal(1000, L.resolveInterval(1000))
            assert.are.equal(15000, L.resolveInterval(15000.7))
        end)
    end)

    describe('client scripts (loaded through fxmanifest.lua)', function()
        local calls, res
        before_each(function()
            natives.reset({ side = 'client' })
            calls = natives.spy(NATIVE)
            res = resource.load_resource(DIR, 'client')
        end)

        it('loads config, logic and main in manifest order under the manifest name', function()
            assert.are.same({ 'config.lua', 'client/logic.lua', 'client/main.lua' }, res.loaded)
            assert.are.equal('nakara_cargen_fix', res.name)
            assert.are.same({}, res.manifest.server)
            assert.are.same({}, res.manifest.shared)
        end)

        it('does nothing until the thread runs, then disables generators map-wide, not networked', function()
            assert.are.equal(0, #calls)
            natives.advance(0)
            assert.are.equal(1, #calls)
            assert.are.same({ n = 8, WORLD[1], WORLD[2], WORLD[3], WORLD[4], WORLD[5], WORLD[6], false, false },
                calls[1])
        end)

        it('re-asserts every 5000 ms', function()
            natives.advance(0)
            natives.advance(4999)
            assert.are.equal(1, #calls)
            natives.advance(1)
            assert.are.equal(2, #calls)
            natives.advance(15000)
            assert.are.equal(5, #calls)
            for _, c in ipairs(calls) do
                assert.is_false(c[7])
                assert.is_false(c[8])
            end
        end)

        it('restores vanilla generators (still not networked) when this resource stops', function()
            natives.advance(0)
            natives.fire('onResourceStop', 'nakara_cargen_fix')
            assert.are.equal(2, #calls)
            assert.is_true(calls[2][7])
            assert.is_false(calls[2][8])
        end)

        it('ignores other resources stopping', function()
            natives.fire('onResourceStop', 'some_other_resource')
            assert.are.equal(0, #calls)
        end)
    end)

    describe('config overrides', function()
        it('uses a valid custom interval and area from config.lua values', function()
            natives.reset({ side = 'client' })
            local calls = natives.spy(NATIVE)
            -- run config.lua, then override before logic/main read it
            resource.load_resource(DIR, 'client', { skip = { ['client/main.lua'] = true } })
            Config.ReassertMs = 2000
            Config.Area = { 0, 0, 0, 10, 10, 10 }
            assert(loadfile(DIR .. '/client/main.lua'))()
            natives.advance(4000)
            assert.are.equal(3, #calls) -- t = 0, 2000, 4000
            assert.are.same({ n = 8, 0, 0, 0, 10, 10, 10, false, false }, calls[3])
        end)
    end)

    describe('source guard', function()
        -- Regression pin: every call to the native in this resource must pass the literal `false` as
        -- its last argument. A past version passed `true` (misread as "instantly") and refilled the pool.
        it('passes the literal false as bNetworked in every native call', function()
            local src = read(DIR .. '/client/main.lua'):gsub('%-%-[^\n]*', '')
            local n = 0
            for args in src:gmatch(NATIVE .. '%s*(%b())') do
                n = n + 1
                local last = args:sub(2, -2):match('([^,]+)%s*$')
                assert.are.equal('false', last:match('^%s*(.-)%s*$'))
            end
            assert.is_true(n >= 1)
        end)
    end)
end)
